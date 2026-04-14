--[[
脚本名字: SpecialEventController
脚本文件: SpecialEventController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/SpecialEventController
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local DEFAULT_BILLBOARD_FRAME_PATH = "Workspace/Scene/Billboard/SurfaceGui/Frame"
local BILLBOARD_FRAME_WARN_DELAY_SECONDS = 3
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

local function findFirstGuiObjectByName(root, name)
    if not root or tostring(name or "") == "" then
        return nil
    end

    local direct = root:FindFirstChild(name)
    if direct and direct:IsA("GuiObject") then
        return direct
    end

    local nested = root:FindFirstChild(name, true)
    if nested and nested:IsA("GuiObject") then
        return nested
    end

    return nil
end

local function countMatchingTextLabels(root, labelNames)
    if not (root and type(labelNames) == "table") then
        return 0
    end

    local matchCount = 0
    for _, labelName in ipairs(labelNames) do
        local label = root:FindFirstChild(labelName)
        if not (label and label:IsA("TextLabel")) then
            label = root:FindFirstChild(labelName, true)
        end
        if label and label:IsA("TextLabel") then
            matchCount += 1
        end
    end

    return matchCount
end

local function setGuiObjectVisible(node, visible)
    if not node then
        return
    end

    if node:IsA("ScreenGui") then
        node.Enabled = visible
    elseif node:IsA("GuiObject") then
        node.Visible = visible
    end
end

local function findNamedChildOfClass(root, className, childName)
    if not root then
        return nil
    end

    local direct = root:FindFirstChild(childName)
    if direct and direct:IsA(className) then
        return direct
    end

    for _, child in ipairs(root:GetChildren()) do
        if child.Name == childName and child:IsA(className) then
            return child
        end
    end

    return nil
end

local function getOrCreateLabelScale(label)
    if not (label and label:IsA("TextLabel")) then
        return nil
    end

    local existingScale = label:FindFirstChild("SpecialEventStartScale")
    if existingScale and existingScale:IsA("UIScale") then
        return existingScale
    end

    local scale = Instance.new("UIScale")
    scale.Name = "SpecialEventStartScale"
    scale.Scale = 1
    scale.Parent = label
    return scale
end

local function disconnectConnection(connection)
    if connection then
        connection:Disconnect()
    end
end

local function formatClockCountdown(secondsRemaining)
    local totalSeconds = math.max(0, math.ceil(tonumber(secondsRemaining) or 0))
    local minutes = math.floor(totalSeconds / 60)
    local seconds = totalSeconds % 60
    return string.format("%02d:%02d", minutes, seconds)
end

local SpecialEventController = {}
SpecialEventController.__index = SpecialEventController

function SpecialEventController.new()
    local self = setmetatable({}, SpecialEventController)
    self._stateSyncEvent = nil
    self._requestStateSyncEvent = nil
    self._characterAddedConnection = nil
    self._countdownConnection = nil
    self._activeEventsByRuntimeKey = {}
    self._currentScheduledEvent = nil
    self._nextScheduledEvent = nil
    self._serverTimeOffsetSeconds = 0
    self._billboardFrame = nil
    self._billboardFrameMissingSince = nil
    self._billboardLabelsByName = {}
    self._eventStartRoot = nil
    self._eventStartLabelsByName = {}
    self._eventStartBaseTextByName = {}
    self._eventStartQueue = {}
    self._isShowingEventStart = false
    self._didWarnByKey = {}
    self._suppressedDefaultLightingParentByInstance = {}
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

function SpecialEventController:_getPlayerGui()
    return localPlayer:FindFirstChildOfClass("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
end

function SpecialEventController:_getRuntimeFolderName()
    return tostring(self:_getConfig().RuntimeFolderName or "SpecialEventsRuntime")
end

function SpecialEventController:_getBillboardFramePath()
    local configuredPath = tostring(self:_getConfig().BillboardFramePath or "")
    if configuredPath ~= "" then
        return configuredPath
    end

    return DEFAULT_BILLBOARD_FRAME_PATH
end
function SpecialEventController:_getAttachPartNames()
    local attachPartNames = self:_getConfig().AttachPartNames
    if type(attachPartNames) == "table" then
        return attachPartNames
    end

    return { "HumanoidRootPart", "UpperTorso", "Torso", "Head" }
end

function SpecialEventController:_getDefaultLightingNodeNames()
    local nodeNames = self:_getConfig().DefaultLightingNodeNames
    if type(nodeNames) == "table" and #nodeNames > 0 then
        return nodeNames
    end

    return { "Atmosphere", "DefaultSky" }
end

function SpecialEventController:_getTemplateRootFolder()
    local rootFolderName = tostring(self:_getConfig().TemplateRootFolderName or "Event")
    return ReplicatedStorage:FindFirstChild(rootFolderName)
end

function SpecialEventController:_getTemplateInstance(templateName)
    local templateNameText = tostring(templateName or "")
    if templateNameText == "" then
        return nil
    end

    local template = nil
    if string.find(templateNameText, "/", 1, true) then
        local normalizedPath = templateNameText
        local segments = splitPath(normalizedPath)
        local firstSegment = segments[1]
        if firstSegment ~= "ReplicatedStorage" and firstSegment ~= "Lighting" and firstSegment ~= "Workspace" then
            normalizedPath = "ReplicatedStorage/" .. normalizedPath
        end
        template = self:_resolveServicePath(normalizedPath)
    else
        local rootFolder = self:_getTemplateRootFolder()
        if not rootFolder then
            self:_warnOnce("MissingTemplateRoot", "[SpecialEventController] 找不到 ReplicatedStorage/Event，事件本地表现无法复制。")
            return nil
        end

        template = rootFolder:FindFirstChild(templateNameText)
    end

    if template then
        return template
    end

    self:_warnOnce("MissingTemplate:" .. templateNameText, string.format(
        "[SpecialEventController] 找不到事件模板或路径 %s。",
        templateNameText
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
                current = Workspace
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

function SpecialEventController:_clearManagedWorkspaceRuntime()
    local toDestroy = {}
    for _, child in ipairs(Workspace:GetChildren()) do
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

function SpecialEventController:_getEventRenderMode(activeEvent)
    local renderMode = tostring(type(activeEvent) == "table" and activeEvent.renderMode or "")
    if renderMode ~= "" then
        return renderMode
    end

    local templateName = tostring(type(activeEvent) == "table" and activeEvent.templateName or "")
    if string.find(templateName, "EventScene/", 1, true) == 1 or string.find(templateName, "ReplicatedStorage/EventScene/", 1, true) == 1 then
        return "WorkspaceScene"
    end

    if string.find(templateName, "/", 1, true) then
        return "WorkspaceScene"
    end

    return "CharacterAttachment"
end

function SpecialEventController:_suppressDefaultLighting()
    for _, nodeName in ipairs(self:_getDefaultLightingNodeNames()) do
        local node = Lighting:FindFirstChild(tostring(nodeName))
        if node then
            if self._suppressedDefaultLightingParentByInstance[node] == nil then
                self._suppressedDefaultLightingParentByInstance[node] = node.Parent
            end
            node.Parent = nil
        end
    end
end

function SpecialEventController:_restoreSuppressedDefaultLighting()
    local storedParents = self._suppressedDefaultLightingParentByInstance
    for instance, originalParent in pairs(storedParents) do
        if instance and instance.Parent == nil then
            instance.Parent = originalParent or Lighting
        end
        storedParents[instance] = nil
    end
end

function SpecialEventController:_applyCharacterEvent(activeEvent)
    if type(activeEvent) ~= "table" then
        return
    end

    if self:_getEventRenderMode(activeEvent) ~= "CharacterAttachment" then
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

function SpecialEventController:_applyWorkspaceSceneEvent(activeEvent)
    if type(activeEvent) ~= "table" then
        return
    end

    if self:_getEventRenderMode(activeEvent) ~= "WorkspaceScene" then
        return
    end

    local template = self:_getTemplateInstance(activeEvent.templateName)
    if not template then
        return
    end

    local clone = template:Clone()
    clone.Name = template.Name
    self:_tagRuntimeInstance(clone, activeEvent.runtimeKey, activeEvent.eventId)
    clone.Parent = Workspace
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

function SpecialEventController:_getPrimaryActiveEvent()
    local activeEvents = self:_getSortedActiveEvents()
    return activeEvents[1]
end

function SpecialEventController:_getBillboardFrame()
    local cachedFrame = self._billboardFrame
    if cachedFrame and cachedFrame.Parent then
        return cachedFrame
    end

    local function resolveCandidateFrame()
        local framePath = self:_getBillboardFramePath()
        local labelNames = self:_getConfiguredDisplayLabelNames()
        local frame = self:_resolveServicePath(framePath)
        if frame and frame:IsA("GuiObject") then
            return frame, framePath
        end

        if framePath ~= DEFAULT_BILLBOARD_FRAME_PATH then
            frame = self:_resolveServicePath(DEFAULT_BILLBOARD_FRAME_PATH)
            if frame and frame:IsA("GuiObject") then
                return frame, framePath
            end
        end

        local sceneRoot = Workspace:FindFirstChild("Scene") or Workspace:FindFirstChild("Scene", true)
        if not sceneRoot then
            return nil, framePath
        end

        local billboardRoot = sceneRoot:FindFirstChild("Billboard") or sceneRoot:FindFirstChild("Billboard", true)
        local surfaceGui = billboardRoot and (billboardRoot:FindFirstChild("SurfaceGui") or billboardRoot:FindFirstChildWhichIsA("SurfaceGui", true)) or nil
        frame = findFirstGuiObjectByName(surfaceGui, "Frame")
        if frame then
            return frame, framePath
        end

        local bestFrame = nil
        local bestScore = 0
        for _, descendant in ipairs(sceneRoot:GetDescendants()) do
            if descendant:IsA("Frame") then
                local score = countMatchingTextLabels(descendant, labelNames)
                if score > bestScore then
                    bestScore = score
                    bestFrame = descendant
                end
            end
        end

        return bestFrame, framePath
    end

    local frame, framePath = resolveCandidateFrame()

    if not frame then
        if not self._billboardFrameMissingSince then
            self._billboardFrameMissingSince = os.clock()
        elseif os.clock() - self._billboardFrameMissingSince >= BILLBOARD_FRAME_WARN_DELAY_SECONDS then
            self:_warnOnce("MissingSpecialEventBillboardFrame", string.format(
                "[SpecialEventController] Missing billboard countdown frame at %s; special event countdown UI disabled.",
                framePath
            ))
        end
        return nil
    end

    self._billboardFrameMissingSince = nil
    self._billboardFrame = frame
    return frame
end
function SpecialEventController:_getConfiguredDisplayLabelNames()
    local labelNames = {}
    local entries = self:_getConfig().Entries
    if type(entries) ~= "table" then
        return labelNames
    end

    for _, rawEntry in ipairs(entries) do
        if type(rawEntry) == "table" then
            local labelName = tostring(rawEntry.DisplayLabelName or rawEntry.TextDisplayName or "")
            if labelName ~= "" then
                table.insert(labelNames, labelName)
            end
        end
    end

    return labelNames
end

function SpecialEventController:_getEventStartTimingConfig()
    local config = self:_getConfig()
    return {
        HoldSeconds = math.max(0.2, tonumber(config.StartTipDisplaySeconds) or 2),
        FadeInSeconds = math.max(0.05, tonumber(config.StartTipFadeInSeconds) or 0.25),
        FadeOutSeconds = math.max(0.05, tonumber(config.StartTipFadeOutSeconds) or 0.35),
        ScaleFrom = math.max(0.5, tonumber(config.StartTipScaleFrom) or 0.88),
        ScaleTo = math.max(0.5, tonumber(config.StartTipScaleTo) or 1),
        ScaleOut = math.max(0.5, tonumber(config.StartTipScaleOut) or 1.04),
    }
end

function SpecialEventController:_getEventStartRoot()
    local cachedRoot = self._eventStartRoot
    if cachedRoot and cachedRoot.Parent then
        return cachedRoot
    end

    local playerGui = self:_getPlayerGui()
    if not playerGui then
        self:_warnOnce("MissingEventStartPlayerGui", "[SpecialEventController] PlayerGui not found; EventStart UI unavailable.")
        return nil
    end

    local mainGui = playerGui:FindFirstChild("Main")
    local eventStartRoot = nil
    if mainGui then
        eventStartRoot = findFirstGuiObjectByName(mainGui, "EventStart")
    end
    if not eventStartRoot then
        eventStartRoot = findFirstGuiObjectByName(playerGui, "EventStart")
    end

    if not eventStartRoot then
        self:_warnOnce("MissingEventStartRoot", "[SpecialEventController] EventStart UI not found under PlayerGui/Main.")
        return nil
    end

    self._eventStartRoot = eventStartRoot
    return eventStartRoot
end

function SpecialEventController:_setEventStartLabelAppearance(label, textTransparency, uiStrokeTransparency, scaleValue)
    if not (label and label:IsA("TextLabel")) then
        return
    end

    label.TextTransparency = textTransparency

    local stroke = findNamedChildOfClass(label, "UIStroke", "UIStroke")
    if stroke then
        stroke.Transparency = uiStrokeTransparency
    end

    local scale = getOrCreateLabelScale(label)
    if scale then
        scale.Scale = scaleValue
    end
end

function SpecialEventController:_hideAllEventStartLabels()
    for _, label in pairs(self._eventStartLabelsByName) do
        if label and label.Parent then
            setGuiObjectVisible(label, false)
            self:_setEventStartLabelAppearance(label, 0, 0, 1)

            local baseText = self._eventStartBaseTextByName[label.Name]
            if baseText ~= nil then
                label.Text = baseText
            end
        end
    end
end

function SpecialEventController:_ensureEventStartNodes()
    local root = self:_getEventStartRoot()
    if not root then
        return false
    end

    local labelsByName = {}
    for _, labelName in ipairs(self:_getConfiguredDisplayLabelNames()) do
        local label = root:FindFirstChild(labelName)
        if not (label and label:IsA("TextLabel")) then
            label = findFirstGuiObjectByName(root, labelName)
        end

        if label and label:IsA("TextLabel") then
            labelsByName[labelName] = label
            if self._eventStartBaseTextByName[labelName] == nil then
                self._eventStartBaseTextByName[labelName] = tostring(label.Text or "")
            end
            getOrCreateLabelScale(label)
        else
            self:_warnOnce("MissingEventStartLabel:" .. labelName, string.format(
                "[SpecialEventController] Missing EventStart label %s.",
                labelName
            ))
        end
    end

    self._eventStartLabelsByName = labelsByName
    self:_hideAllEventStartLabels()
    setGuiObjectVisible(root, false)
    return true
end

function SpecialEventController:_showNextEventStartTip()
    if self._isShowingEventStart then
        return
    end

    if #self._eventStartQueue <= 0 then
        self:_hideAllEventStartLabels()
        setGuiObjectVisible(self._eventStartRoot, false)
        return
    end

    self._isShowingEventStart = true
    local queuedEvent = table.remove(self._eventStartQueue, 1)

    if not self:_ensureEventStartNodes() then
        self._isShowingEventStart = false
        table.insert(self._eventStartQueue, 1, queuedEvent)
        task.delay(1, function()
            if not self._isShowingEventStart and #self._eventStartQueue > 0 then
                self:_showNextEventStartTip()
            end
        end)
        return
    end

    local root = self._eventStartRoot
    local labelName = tostring(type(queuedEvent) == "table" and queuedEvent.displayLabelName or "")
    local eventName = tostring(type(queuedEvent) == "table" and queuedEvent.name or "Event")
    local label = self._eventStartLabelsByName[labelName]
    if not (label and label.Parent) then
        self._isShowingEventStart = false
        self:_showNextEventStartTip()
        return
    end

    local timing = self:_getEventStartTimingConfig()
    self:_hideAllEventStartLabels()
    setGuiObjectVisible(root, true)
    setGuiObjectVisible(label, true)
    label.Text = string.format("%s Event Start!", eventName)
    self:_setEventStartLabelAppearance(label, 1, 1, timing.ScaleFrom)

    local stroke = findNamedChildOfClass(label, "UIStroke", "UIStroke")
    local scale = getOrCreateLabelScale(label)
    local fadeInTweenInfo = TweenInfo.new(timing.FadeInSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
    local fadeOutTweenInfo = TweenInfo.new(timing.FadeOutSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    local fadeInLabelTween = TweenService:Create(label, fadeInTweenInfo, {
        TextTransparency = 0,
    })
    local fadeInScaleTween = scale and TweenService:Create(scale, fadeInTweenInfo, {
        Scale = timing.ScaleTo,
    }) or nil
    local fadeInStrokeTween = stroke and TweenService:Create(stroke, fadeInTweenInfo, {
        Transparency = 0,
    }) or nil

    fadeInLabelTween.Completed:Connect(function()
        task.delay(timing.HoldSeconds, function()
            if not (label and label.Parent and root and root.Parent) then
                self._isShowingEventStart = false
                self:_showNextEventStartTip()
                return
            end

            local fadeOutLabelTween = TweenService:Create(label, fadeOutTweenInfo, {
                TextTransparency = 1,
            })
            local fadeOutScaleTween = scale and TweenService:Create(scale, fadeOutTweenInfo, {
                Scale = timing.ScaleOut,
            }) or nil
            local fadeOutStrokeTween = stroke and TweenService:Create(stroke, fadeOutTweenInfo, {
                Transparency = 1,
            }) or nil

            fadeOutLabelTween.Completed:Connect(function()
                self:_hideAllEventStartLabels()
                if #self._eventStartQueue <= 0 then
                    setGuiObjectVisible(root, false)
                end
                self._isShowingEventStart = false
                self:_showNextEventStartTip()
            end)

            fadeOutLabelTween:Play()
            if fadeOutScaleTween then
                fadeOutScaleTween:Play()
            end
            if fadeOutStrokeTween then
                fadeOutStrokeTween:Play()
            end
        end)
    end)

    fadeInLabelTween:Play()
    if fadeInScaleTween then
        fadeInScaleTween:Play()
    end
    if fadeInStrokeTween then
        fadeInStrokeTween:Play()
    end
end

function SpecialEventController:_enqueueEventStartTip(activeEvent)
    if type(activeEvent) ~= "table" then
        return
    end

    local labelName = tostring(activeEvent.displayLabelName or "")
    local eventName = tostring(activeEvent.name or "")
    if labelName == "" or eventName == "" then
        return
    end

    table.insert(self._eventStartQueue, {
        runtimeKey = tostring(activeEvent.runtimeKey or ""),
        displayLabelName = labelName,
        name = eventName,
    })
    self:_showNextEventStartTip()
end

function SpecialEventController:_ensureBillboardLabels()
    local frame = self:_getBillboardFrame()
    if not frame then
        return {}
    end

    local labelsByName = {}
    for _, labelName in ipairs(self:_getConfiguredDisplayLabelNames()) do
        local label = frame:FindFirstChild(labelName)
        if label and label:IsA("TextLabel") then
            labelsByName[labelName] = label
        else
            self:_warnOnce("MissingSpecialEventLabel:" .. labelName, string.format(
                "[SpecialEventController] Missing special event countdown label %s.",
                labelName
            ))
        end
    end

    self._billboardLabelsByName = labelsByName
    return labelsByName
end

function SpecialEventController:_hideAllBillboardLabels()
    for _, label in pairs(self:_ensureBillboardLabels()) do
        label.Visible = false
    end
end

function SpecialEventController:_reapplyLightingEvents()
    self:_clearManagedLightingRuntime()

    local activeEvents = self:_getSortedActiveEvents()
    if #activeEvents > 0 then
        self:_suppressDefaultLighting()
    else
        self:_restoreSuppressedDefaultLighting()
    end

    for _, activeEvent in ipairs(activeEvents) do
        self:_applyLightingEvent(activeEvent)
    end
end

function SpecialEventController:_reapplyWorkspaceEvents()
    self:_clearManagedWorkspaceRuntime()
    for _, activeEvent in ipairs(self:_getSortedActiveEvents()) do
        self:_applyWorkspaceSceneEvent(activeEvent)
    end
end

function SpecialEventController:_reapplyCharacterEvents()
    self:_clearManagedCharacterRuntime()
    for _, activeEvent in ipairs(self:_getSortedActiveEvents()) do
        self:_applyCharacterEvent(activeEvent)
    end
end

function SpecialEventController:_normalizeStateEvent(rawEvent)
    if type(rawEvent) ~= "table" then
        return nil
    end

    local runtimeKey = tostring(rawEvent.runtimeKey or "")
    local eventId = tonumber(rawEvent.eventId) or 0
    local startedAt = tonumber(rawEvent.startedAt) or 0
    local endsAt = tonumber(rawEvent.endsAt) or 0
    if runtimeKey == "" and eventId <= 0 then
        return nil
    end

    return {
        runtimeKey = runtimeKey,
        eventId = eventId,
        name = tostring(rawEvent.name or rawEvent.eventId or ""),
        templateName = tostring(rawEvent.templateName or ""),
        lightingPath = tostring(rawEvent.lightingPath or ""),
        displayLabelName = tostring(rawEvent.displayLabelName or ""),
        renderMode = tostring(rawEvent.renderMode or ""),
        startedAt = startedAt,
        endsAt = endsAt,
        source = tostring(rawEvent.source or ""),
    }
end

function SpecialEventController:_updateBillboardCountdowns()
    local labelsByName = self:_ensureBillboardLabels()
    for _, label in pairs(labelsByName) do
        label.Visible = false
    end

    local now = os.time() + self._serverTimeOffsetSeconds
    local activeEvent = self:_getPrimaryActiveEvent()
    local nextEvent = self._nextScheduledEvent

    if activeEvent then
        local activeLabelName = tostring(activeEvent.displayLabelName or "")
        local activeLabel = labelsByName[activeLabelName]
        if activeLabel and now < activeEvent.endsAt then
            activeLabel.Visible = true
            activeLabel.Text = string.format(
                "%s End In: %s",
                tostring(activeEvent.name or "Event"),
                formatClockCountdown(activeEvent.endsAt - now)
            )
        end
    end

    if nextEvent and now < nextEvent.startedAt then
        local nextLabelName = tostring(nextEvent.displayLabelName or "")
        local nextLabel = labelsByName[nextLabelName]
        if nextLabel then
            if not activeEvent or nextLabel ~= labelsByName[tostring(activeEvent.displayLabelName or "")] then
                nextLabel.Visible = true
                nextLabel.Text = string.format(
                    "%s Event In: %s",
                    tostring(nextEvent.name or "Event"),
                    formatClockCountdown(nextEvent.startedAt - now)
                )
            end
        end
    end
end

function SpecialEventController:_startCountdownLoop()
    if self._countdownConnection then
        return
    end

    self._countdownConnection = RunService.Heartbeat:Connect(function()
        self:_updateBillboardCountdowns()
    end)
end

function SpecialEventController:_applyStatePayload(payload)
    local previousStateByRuntimeKey = self._activeEventsByRuntimeKey
    local newStateByRuntimeKey = {}
    local newlyActivatedEvents = {}
    local activeEvents = type(payload) == "table" and payload.activeEvents or nil
    if type(activeEvents) == "table" then
        for _, rawEvent in ipairs(activeEvents) do
            local normalizedEvent = self:_normalizeStateEvent(rawEvent)
            if normalizedEvent and normalizedEvent.runtimeKey ~= "" then
                newStateByRuntimeKey[normalizedEvent.runtimeKey] = normalizedEvent
                if previousStateByRuntimeKey[normalizedEvent.runtimeKey] == nil then
                    table.insert(newlyActivatedEvents, normalizedEvent)
                end
            end
        end
    end

    local serverTime = type(payload) == "table" and tonumber(payload.serverTime) or nil
    self._serverTimeOffsetSeconds = math.floor((serverTime or os.time()) - os.time())
    self._currentScheduledEvent = self:_normalizeStateEvent(type(payload) == "table" and payload.currentScheduledEvent or nil)
    self._nextScheduledEvent = self:_normalizeStateEvent(type(payload) == "table" and payload.nextScheduledEvent or nil)
    self._activeEventsByRuntimeKey = newStateByRuntimeKey
    self:_reapplyLightingEvents()
    self:_reapplyWorkspaceEvents()
    self:_reapplyCharacterEvents()
    self:_updateBillboardCountdowns()

    table.sort(newlyActivatedEvents, function(a, b)
        if a.startedAt ~= b.startedAt then
            return a.startedAt < b.startedAt
        end

        return tostring(a.runtimeKey) < tostring(b.runtimeKey)
    end)

    for _, activeEvent in ipairs(newlyActivatedEvents) do
        self:_enqueueEventStartTip(activeEvent)
    end
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
        warn("[SpecialEventController] Missing SpecialEventStateSync; special event client logic not started.")
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

    self:_startCountdownLoop()
    self:_hideAllBillboardLabels()
    self:_ensureEventStartNodes()

    if self._requestStateSyncEvent and self._requestStateSyncEvent:IsA("RemoteEvent") then
        self._requestStateSyncEvent:FireServer()
    end
end

return SpecialEventController
