--[[
脚本名字: SpecialEventController
脚本文件: SpecialEventController.lua
脚本类型: ModuleScript
本地路径: D:/RobloxGame/BrainrotsTemplate/SpecialEventController.lua
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/SpecialEventController
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer

local function requireSharedModule(moduleName)
    local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
    if sharedFolder then
        local moduleInShared = sharedFolder:FindFirstChild(moduleName)
        if moduleInShared and moduleInShared:IsA("ModuleScript") then
            return require(moduleInShared)
        end
    end

    local moduleInRoot = ReplicatedStorage:FindFirstChild(moduleName)
    if moduleInRoot and moduleInRoot:IsA("ModuleScript") then
        return require(moduleInRoot)
    end

    error(string.format(
        "[SpecialEventController] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local GameConfig = requireSharedModule("GameConfig")
local RemoteNames = requireSharedModule("RemoteNames")

local function collectBaseParts(root)
    local baseParts = {}
    if not root then
        return baseParts
    end

    if root:IsA("BasePart") then
        table.insert(baseParts, root)
    end

    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant:IsA("BasePart") then
            table.insert(baseParts, descendant)
        end
    end

    return baseParts
end

local function findAttachPart(character, preferredNames)
    if not character then
        return nil
    end

    for _, name in ipairs(preferredNames or {}) do
        local part = character:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            return part
        end
    end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if rootPart and rootPart:IsA("BasePart") then
        return rootPart
    end

    return character:FindFirstChildWhichIsA("BasePart")
end

local function splitPath(pathText)
    local segments = {}
    for segment in string.gmatch(tostring(pathText or ""), "[^/]+") do
        table.insert(segments, segment)
    end
    return segments
end

local function disconnectConnection(connection)
    if connection then
        connection:Disconnect()
    end
end

local SpecialEventController = {}
SpecialEventController.__index = SpecialEventController

function SpecialEventController.new()
    local self = setmetatable({}, SpecialEventController)
    self._stateSyncEvent = nil
    self._requestStateSyncEvent = nil
    self._characterAddedConnection = nil
    self._activeEventsByRuntimeKey = {}
    self._didWarnByKey = {}
    return self
end

function SpecialEventController:_warnOnce(key, message)
    if self._didWarnByKey[key] then
        return
    end

    self._didWarnByKey[key] = true
    warn(message)
end

function SpecialEventController:_getConfig()
    return GameConfig.SPECIAL_EVENT or {}
end

function SpecialEventController:_getRuntimeFolderName()
    return tostring(self:_getConfig().RuntimeFolderName or "SpecialEventsRuntime")
end

function SpecialEventController:_getAttachPartNames()
    local attachPartNames = self:_getConfig().AttachPartNames
    if type(attachPartNames) == "table" then
        return attachPartNames
    end

    return { "HumanoidRootPart", "UpperTorso", "Torso", "Head" }
end

function SpecialEventController:_getTemplateRootFolder()
    local rootFolderName = tostring(self:_getConfig().TemplateRootFolderName or "Event")
    return ReplicatedStorage:FindFirstChild(rootFolderName)
end

function SpecialEventController:_getTemplateInstance(templateName)
    local rootFolder = self:_getTemplateRootFolder()
    if not rootFolder then
        self:_warnOnce("MissingTemplateRoot", "[SpecialEventController] 找不到 ReplicatedStorage/Event，事件本地表现无法复制。")
        return nil
    end

    local template = rootFolder:FindFirstChild(tostring(templateName or ""))
    if template then
        return template
    end

    self:_warnOnce("MissingTemplate:" .. tostring(templateName), string.format(
        "[SpecialEventController] 找不到事件模板 %s。",
        tostring(templateName)
    ))
    return nil
end

function SpecialEventController:_resolveServicePath(pathText)
    local segments = splitPath(pathText)
    if #segments <= 0 then
        return nil
    end

    local current = nil
    for index, segment in ipairs(segments) do
        if index == 1 then
            if segment == "Lighting" then
                current = Lighting
            elseif segment == "ReplicatedStorage" then
                current = ReplicatedStorage
            elseif segment == "Workspace" or segment == "workspace" then
                current = workspace
            else
                current = game:FindFirstChild(segment)
            end
        else
            current = current and current:FindFirstChild(segment) or nil
        end

        if not current then
            return nil
        end
    end

    return current
end

function SpecialEventController:_ensureRuntimeFolder(character)
    local folderName = self:_getRuntimeFolderName()
    local folder = character and character:FindFirstChild(folderName) or nil
    if folder and folder:IsA("Folder") then
        return folder
    end

    folder = Instance.new("Folder")
    folder.Name = folderName
    folder.Parent = character
    return folder
end

function SpecialEventController:_tagRuntimeInstance(instance, runtimeKey, eventId)
    if not instance then
        return
    end

    instance:SetAttribute("SpecialEventManaged", true)
    instance:SetAttribute("SpecialEventRuntimeKey", tostring(runtimeKey))
    instance:SetAttribute("SpecialEventId", tonumber(eventId) or 0)
end

function SpecialEventController:_prepareRuntimePart(part)
    if not (part and part:IsA("BasePart")) then
        return
    end

    part.Anchored = false
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.Massless = true
end

function SpecialEventController:_createWeld(part0, part1)
    if not (part0 and part1) or part0 == part1 then
        return
    end

    local weld = Instance.new("WeldConstraint")
    weld.Part0 = part0
    weld.Part1 = part1
    weld.Parent = part1
end

function SpecialEventController:_bindCloneBaseParts(clone, attachPart)
    local baseParts = collectBaseParts(clone)
    if #baseParts <= 0 then
        return
    end

    local rootPart = baseParts[1]
    if clone:IsA("Model") and clone.PrimaryPart and clone.PrimaryPart:IsA("BasePart") then
        rootPart = clone.PrimaryPart
    end

    local rootCFrame = rootPart.CFrame
    local relativeCFrames = {}
    for _, part in ipairs(baseParts) do
        relativeCFrames[part] = rootCFrame:ToObjectSpace(part.CFrame)
    end

    for _, part in ipairs(baseParts) do
        self:_prepareRuntimePart(part)
    end

    rootPart.CFrame = attachPart.CFrame
    for _, part in ipairs(baseParts) do
        if part ~= rootPart then
            part.CFrame = attachPart.CFrame * relativeCFrames[part]
        end
    end

    self:_createWeld(attachPart, rootPart)
    for _, part in ipairs(baseParts) do
        if part ~= rootPart then
            self:_createWeld(rootPart, part)
        end
    end
end

function SpecialEventController:_clearManagedCharacterRuntime()
    local character = localPlayer.Character
    if not character then
        return
    end

    local toDestroy = {}
    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:GetAttribute("SpecialEventManaged") == true then
            table.insert(toDestroy, descendant)
        end
    end

    for _, instance in ipairs(toDestroy) do
        if instance.Parent then
            instance:Destroy()
        end
    end

    local runtimeFolder = character:FindFirstChild(self:_getRuntimeFolderName())
    if runtimeFolder and runtimeFolder:IsA("Folder") then
        runtimeFolder:Destroy()
    end
end

function SpecialEventController:_clearManagedLightingRuntime()
    local toDestroy = {}
    for _, child in ipairs(Lighting:GetChildren()) do
        if child:GetAttribute("SpecialEventManaged") == true then
            table.insert(toDestroy, child)
        end
    end

    for _, instance in ipairs(toDestroy) do
        if instance.Parent then
            instance:Destroy()
        end
    end
end

function SpecialEventController:_applyCharacterEvent(activeEvent)
    if type(activeEvent) ~= "table" then
        return
    end

    local character = localPlayer.Character
    if not character then
        return
    end

    local attachPart = findAttachPart(character, self:_getAttachPartNames())
    if not attachPart then
        local waitedPart = character:WaitForChild("HumanoidRootPart", 5)
        if waitedPart and waitedPart:IsA("BasePart") then
            attachPart = waitedPart
        end
    end

    if not (attachPart and attachPart:IsA("BasePart")) then
        self:_warnOnce("MissingAttachPart", "[SpecialEventController] 当前角色缺少可挂载事件的部件。")
        return
    end

    local template = self:_getTemplateInstance(activeEvent.templateName)
    if not template then
        return
    end

    local clone = template:Clone()
    clone.Name = string.format("%s_Runtime_%s", template.Name, tostring(activeEvent.runtimeKey or ""))
    self:_tagRuntimeInstance(clone, activeEvent.runtimeKey, activeEvent.eventId)

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if clone:IsA("Accessory") and humanoid then
        clone.Parent = character
        local success, err = pcall(function()
            humanoid:AddAccessory(clone)
        end)
        if not success then
            clone:Destroy()
            self:_warnOnce("AddAccessoryFailed:" .. tostring(activeEvent.eventId), string.format(
                "[SpecialEventController] 本地挂载事件 Accessory 失败: %s",
                tostring(err)
            ))
        end
        return
    end

    if clone:IsA("Attachment") or clone:IsA("BillboardGui") or clone:IsA("ParticleEmitter") then
        clone.Parent = attachPart
        return
    end

    local runtimeFolder = self:_ensureRuntimeFolder(character)
    clone.Parent = runtimeFolder
    self:_bindCloneBaseParts(clone, attachPart)
end

function SpecialEventController:_applyLightingEvent(activeEvent)
    if type(activeEvent) ~= "table" then
        return
    end

    local lightingPath = tostring(activeEvent.lightingPath or "")
    if lightingPath == "" then
        return
    end

    local sourceFolder = self:_resolveServicePath(lightingPath)
    if not sourceFolder then
        self:_warnOnce("MissingLightingPath:" .. lightingPath, string.format(
            "[SpecialEventController] 找不到事件天空盒路径 %s。",
            lightingPath
        ))
        return
    end

    for _, child in ipairs(sourceFolder:GetChildren()) do
        local clone = child:Clone()
        self:_tagRuntimeInstance(clone, activeEvent.runtimeKey, activeEvent.eventId)
        clone.Parent = Lighting
    end
end

function SpecialEventController:_getSortedActiveEvents()
    local activeEvents = {}
    for _, activeEvent in pairs(self._activeEventsByRuntimeKey) do
        table.insert(activeEvents, activeEvent)
    end

    table.sort(activeEvents, function(a, b)
        if a.startedAt ~= b.startedAt then
            return a.startedAt < b.startedAt
        end

        return tostring(a.runtimeKey) < tostring(b.runtimeKey)
    end)

    return activeEvents
end

function SpecialEventController:_reapplyLightingEvents()
    self:_clearManagedLightingRuntime()
    for _, activeEvent in ipairs(self:_getSortedActiveEvents()) do
        self:_applyLightingEvent(activeEvent)
    end
end

function SpecialEventController:_reapplyCharacterEvents()
    self:_clearManagedCharacterRuntime()
    for _, activeEvent in ipairs(self:_getSortedActiveEvents()) do
        self:_applyCharacterEvent(activeEvent)
    end
end

function SpecialEventController:_applyStatePayload(payload)
    local newStateByRuntimeKey = {}
    local activeEvents = type(payload) == "table" and payload.activeEvents or nil
    if type(activeEvents) == "table" then
        for _, rawEvent in ipairs(activeEvents) do
            if type(rawEvent) == "table" then
                local runtimeKey = tostring(rawEvent.runtimeKey or "")
                if runtimeKey ~= "" then
                    newStateByRuntimeKey[runtimeKey] = {
                        runtimeKey = runtimeKey,
                        eventId = tonumber(rawEvent.eventId) or 0,
                        name = tostring(rawEvent.name or rawEvent.eventId or ""),
                        templateName = tostring(rawEvent.templateName or ""),
                        lightingPath = tostring(rawEvent.lightingPath or ""),
                        startedAt = tonumber(rawEvent.startedAt) or 0,
                        endsAt = tonumber(rawEvent.endsAt) or 0,
                        source = tostring(rawEvent.source or ""),
                    }
                end
            end
        end
    end

    self._activeEventsByRuntimeKey = newStateByRuntimeKey
    self:_reapplyLightingEvents()
    self:_reapplyCharacterEvents()
end

function SpecialEventController:Start()
    local eventsRoot = ReplicatedStorage:WaitForChild(RemoteNames.RootFolder)
    local systemEvents = eventsRoot:WaitForChild(RemoteNames.SystemEventsFolder)

    self._stateSyncEvent = systemEvents:FindFirstChild(RemoteNames.System.SpecialEventStateSync)
    if not (self._stateSyncEvent and self._stateSyncEvent:IsA("RemoteEvent")) then
        self._stateSyncEvent = systemEvents:WaitForChild(RemoteNames.System.SpecialEventStateSync, 10)
    end

    self._requestStateSyncEvent = systemEvents:FindFirstChild(RemoteNames.System.RequestSpecialEventStateSync)
    if not (self._requestStateSyncEvent and self._requestStateSyncEvent:IsA("RemoteEvent")) then
        self._requestStateSyncEvent = systemEvents:WaitForChild(RemoteNames.System.RequestSpecialEventStateSync, 10)
    end

    if not (self._stateSyncEvent and self._stateSyncEvent:IsA("RemoteEvent")) then
        warn("[SpecialEventController] 找不到 SpecialEventStateSync，特殊事件客户端表现未启动。")
        return
    end

    self._stateSyncEvent.OnClientEvent:Connect(function(payload)
        self:_applyStatePayload(payload)
    end)

    disconnectConnection(self._characterAddedConnection)
    self._characterAddedConnection = localPlayer.CharacterAdded:Connect(function()
        task.defer(function()
            self:_reapplyCharacterEvents()
        end)
    end)

    if self._requestStateSyncEvent and self._requestStateSyncEvent:IsA("RemoteEvent") then
        self._requestStateSyncEvent:FireServer()
    end
end

return SpecialEventController