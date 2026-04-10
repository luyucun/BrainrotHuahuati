--[[
脚本名字: SeaHazardController
脚本文件: SeaHazardController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/SeaHazardController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LOCAL_SEA_TOUCH_DEBOUNCE_SECONDS = 0.05
local LOCAL_SEA_RESPAWN_GRACE_SECONDS = 1
local LOCAL_SEA_ARM_CHECK_INTERVAL = 0.1

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
        "[SeaHazardController] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local function disconnectConnection(connection)
    if connection then
        connection:Disconnect()
    end
end

local RemoteNames = requireSharedModule("RemoteNames")

local SeaHazardController = {}
SeaHazardController.__index = SeaHazardController

function SeaHazardController.new()
    local self = setmetatable({}, SeaHazardController)
    self._seaRoot = nil
    self._seaTouchConnections = {}
    self._seaDescendantAddedConnection = nil
    self._workspaceDescendantAddedConnection = nil
    self._characterAddedConnection = nil
    self._requestSeaHazardDeathEvent = nil
    self._lastLocalTriggerClock = 0
    self._isHazardArmed = false
    self._armCharacterSerial = 0
    return self
end

function SeaHazardController:_clearSeaTouchConnections()
    for seaPart, connection in pairs(self._seaTouchConnections) do
        disconnectConnection(connection)
        self._seaTouchConnections[seaPart] = nil
    end
end

function SeaHazardController:_resolveRemoteEvent()
    if self._requestSeaHazardDeathEvent and self._requestSeaHazardDeathEvent.Parent then
        return self._requestSeaHazardDeathEvent
    end

    local eventsRoot = ReplicatedStorage:WaitForChild(RemoteNames.RootFolder)
    local systemEvents = eventsRoot:WaitForChild(RemoteNames.SystemEventsFolder)
    local remoteEvent = systemEvents:FindFirstChild(RemoteNames.System.RequestSeaHazardDeath)
        or systemEvents:WaitForChild(RemoteNames.System.RequestSeaHazardDeath, 10)
    if remoteEvent and remoteEvent:IsA("RemoteEvent") then
        self._requestSeaHazardDeathEvent = remoteEvent
    end

    return self._requestSeaHazardDeathEvent
end

function SeaHazardController:_getCurrentCharacter()
    local character = localPlayer.Character
    if not (character and character.Parent) then
        return nil
    end

    return character
end

function SeaHazardController:_isCharacterTouchingSeaPart(character, seaPart)
    if not (character and seaPart and seaPart:IsA("BasePart") and seaPart.Parent) then
        return false
    end

    local overlapParams = OverlapParams.new()
    overlapParams.FilterType = Enum.RaycastFilterType.Include
    overlapParams.FilterDescendantsInstances = { character }

    local ok, touchingParts = pcall(function()
        return Workspace:GetPartsInPart(seaPart, overlapParams)
    end)
    if not ok then
        return false
    end

    for _, touchingPart in ipairs(touchingParts) do
        if touchingPart and touchingPart:IsDescendantOf(character) then
            return true
        end
    end

    return false
end

function SeaHazardController:_isCharacterTouchingSea(character)
    if not character then
        return false
    end

    for seaPart in pairs(self._seaTouchConnections) do
        if self:_isCharacterTouchingSeaPart(character, seaPart) then
            return true
        end
    end

    return false
end

function SeaHazardController:_beginRespawnGrace(character)
    self._armCharacterSerial = self._armCharacterSerial + 1
    local currentSerial = self._armCharacterSerial
    self._isHazardArmed = false
    self._lastLocalTriggerClock = 0

    if not character then
        return
    end

    task.spawn(function()
        local startedAt = os.clock()
        while self._armCharacterSerial == currentSerial do
            if localPlayer.Parent == nil then
                return
            end

            local currentCharacter = self:_getCurrentCharacter()
            if currentCharacter ~= character then
                return
            end

            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health <= 0 then
                return
            end

            if os.clock() - startedAt >= LOCAL_SEA_RESPAWN_GRACE_SECONDS and not self:_isCharacterTouchingSea(character) then
                self._isHazardArmed = true
                return
            end

            task.wait(LOCAL_SEA_ARM_CHECK_INTERVAL)
        end
    end)
end

function SeaHazardController:_requestTeleportHomeFromSea(seaPart)
    local character = self:_getCurrentCharacter()
    if not character then
        return
    end

    if not self._isHazardArmed then
        return
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        return
    end

    local now = os.clock()
    if now - self._lastLocalTriggerClock < LOCAL_SEA_TOUCH_DEBOUNCE_SECONDS then
        return
    end

    self._lastLocalTriggerClock = now
    self:_beginRespawnGrace(character)

    local remoteEvent = self:_resolveRemoteEvent()
    if remoteEvent then
        remoteEvent:FireServer({
            SeaPart = seaPart,
        })
    end
end

function SeaHazardController:_isLocalCharacterPart(part)
    local character = self:_getCurrentCharacter()
    if not (character and part and part:IsA("BasePart")) then
        return false
    end

    return part:IsDescendantOf(character)
end

function SeaHazardController:_bindSeaBasePart(seaPart)
    if not (seaPart and seaPart:IsA("BasePart")) then
        return false
    end

    if self._seaTouchConnections[seaPart] then
        return true
    end

    self._seaTouchConnections[seaPart] = seaPart.Touched:Connect(function(hitPart)
        if not self:_isLocalCharacterPart(hitPart) then
            return
        end

        self:_requestTeleportHomeFromSea(seaPart)
    end)

    return true
end

function SeaHazardController:_attachSeaRoot(seaRoot)
    if self._seaRoot == seaRoot and seaRoot and seaRoot.Parent then
        return
    end

    self._seaRoot = seaRoot
    self:_clearSeaTouchConnections()
    disconnectConnection(self._seaDescendantAddedConnection)
    self._seaDescendantAddedConnection = nil

    if not (seaRoot and seaRoot.Parent) then
        return
    end

    if seaRoot:IsA("BasePart") then
        self:_bindSeaBasePart(seaRoot)
    end

    for _, descendant in ipairs(seaRoot:GetDescendants()) do
        if descendant:IsA("BasePart") then
            self:_bindSeaBasePart(descendant)
        end
    end

    self._seaDescendantAddedConnection = seaRoot.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("BasePart") then
            self:_bindSeaBasePart(descendant)
        end
    end)
end

function SeaHazardController:_refreshSeaRoot()
    local seaRoot = Workspace:FindFirstChild("Sea") or Workspace:FindFirstChild("Sea", true)
    if not seaRoot then
        if self._seaRoot and not self._seaRoot.Parent then
            self:_attachSeaRoot(nil)
        end
        return false
    end

    self:_attachSeaRoot(seaRoot)
    return true
end

function SeaHazardController:Start()
    self:_resolveRemoteEvent()
    self:_refreshSeaRoot()
    local currentCharacter = self:_getCurrentCharacter()
    if currentCharacter then
        self:_beginRespawnGrace(currentCharacter)
    end

    self._characterAddedConnection = localPlayer.CharacterAdded:Connect(function(character)
        self:_beginRespawnGrace(character)
        task.defer(function()
            self:_refreshSeaRoot()
        end)
    end)

    self._workspaceDescendantAddedConnection = Workspace.DescendantAdded:Connect(function(descendant)
        if descendant.Name == "Sea" then
            task.defer(function()
                self:_refreshSeaRoot()
            end)
            return
        end

        if self._seaRoot and descendant:IsDescendantOf(self._seaRoot) and descendant:IsA("BasePart") then
            task.defer(function()
                self:_bindSeaBasePart(descendant)
            end)
        end
    end)
end

return SeaHazardController
