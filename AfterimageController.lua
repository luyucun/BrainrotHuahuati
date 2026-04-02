--[[
脚本名字: AfterimageController
脚本文件: AfterimageController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/AfterimageController
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer

local AFTERIMAGE_RUNTIME_FOLDER_NAME = "PlayerAfterimageFx"
local AFTERIMAGE_INTERVAL = 0.1
local AFTERIMAGE_LIFETIME = 0.5
local AFTERIMAGE_START_TRANSPARENCY = 0.3
local AFTERIMAGE_MIN_FALL_SPEED = 2

local FALLING_STATES = {
    [Enum.HumanoidStateType.Freefall] = true,
    [Enum.HumanoidStateType.Jumping] = true,
    [Enum.HumanoidStateType.FallingDown] = true,
    [Enum.HumanoidStateType.Physics] = true,
    [Enum.HumanoidStateType.Ragdoll] = true,
}

local function getCharacterHumanoid(character)
    if not character then
        return nil
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        return humanoid
    end

    return character:WaitForChild("Humanoid", 5)
end

local function getCharacterRootPart(character)
    if not character then
        return nil
    end

    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
        return humanoidRootPart
    end

    local waitedRootPart = character:WaitForChild("HumanoidRootPart", 5)
    if waitedRootPart and waitedRootPart:IsA("BasePart") then
        return waitedRootPart
    end

    local primaryPart = character.PrimaryPart
    if primaryPart and primaryPart:IsA("BasePart") then
        return primaryPart
    end

    local fallbackPart = character:FindFirstChildWhichIsA("BasePart")
    if fallbackPart and fallbackPart:IsA("BasePart") then
        return fallbackPart
    end

    return nil
end

local function destroyInstance(instance)
    if instance and instance.Parent then
        instance:Destroy()
    end
end

local function disconnectConnection(connection)
    if connection then
        connection:Disconnect()
    end
end

local function getFadeStartTransparency(originalTransparency)
    return math.clamp(
        math.max(tonumber(originalTransparency) or 0, AFTERIMAGE_START_TRANSPARENCY),
        0,
        1
    )
end

local AfterimageController = {}
AfterimageController.__index = AfterimageController

function AfterimageController.new()
    local self = setmetatable({}, AfterimageController)
    self._started = false
    self._character = nil
    self._humanoid = nil
    self._rootPart = nil
    self._heartbeatConnection = nil
    self._characterAddedConnection = nil
    self._characterRemovingConnection = nil
    self._runtimeFolder = nil
    self._activeAfterimages = {}
    self._isFalling = false
    self._lastAfterimageAt = 0
    return self
end

function AfterimageController:_getRuntimeFolder()
    if self._runtimeFolder and self._runtimeFolder.Parent then
        return self._runtimeFolder
    end

    local runtimeFolder = Workspace:FindFirstChild(AFTERIMAGE_RUNTIME_FOLDER_NAME)
    if runtimeFolder and runtimeFolder:IsA("Folder") then
        self._runtimeFolder = runtimeFolder
        return runtimeFolder
    end

    runtimeFolder = Instance.new("Folder")
    runtimeFolder.Name = AFTERIMAGE_RUNTIME_FOLDER_NAME
    runtimeFolder.Parent = Workspace
    self._runtimeFolder = runtimeFolder
    return runtimeFolder
end

function AfterimageController:_trackAfterimage(afterimageModel)
    if not afterimageModel then
        return
    end

    self._activeAfterimages[afterimageModel] = true
end

function AfterimageController:_untrackAfterimage(afterimageModel)
    if not afterimageModel then
        return
    end

    self._activeAfterimages[afterimageModel] = nil
end

function AfterimageController:_destroyAfterimage(afterimageModel)
    self:_untrackAfterimage(afterimageModel)
    destroyInstance(afterimageModel)
end

function AfterimageController:_clearAfterimages()
    for afterimageModel in pairs(self._activeAfterimages) do
        self:_destroyAfterimage(afterimageModel)
    end
end

function AfterimageController:_prepareAfterimageClone(afterimageModel)
    for _, descendant in ipairs(afterimageModel:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.Anchored = true
            descendant.CanCollide = false
            descendant.CanTouch = false
            descendant.CanQuery = false
            descendant.Massless = true
            descendant.CastShadow = false

            local fadeStart = getFadeStartTransparency(descendant.Transparency)
            descendant.Transparency = fadeStart
            TweenService:Create(descendant, TweenInfo.new(AFTERIMAGE_LIFETIME), {
                Transparency = 1,
            }):Play()
        elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
            local fadeStart = getFadeStartTransparency(descendant.Transparency)
            descendant.Transparency = fadeStart
            TweenService:Create(descendant, TweenInfo.new(AFTERIMAGE_LIFETIME), {
                Transparency = 1,
            }):Play()
        elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Trail") or descendant:IsA("Beam") then
            descendant.Enabled = false
        elseif descendant:IsA("Humanoid") then
            descendant.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
            descendant.BreakJointsOnDeath = false
            descendant.AutoRotate = false
            descendant.PlatformStand = true
        elseif descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("ModuleScript") then
            descendant:Destroy()
        end
    end
end

function AfterimageController:_spawnAfterimage()
    local character = self._character
    local rootPart = self._rootPart
    if not (character and character.Parent and rootPart and rootPart.Parent) then
        return
    end

    local originalArchivable = character.Archivable
    if not originalArchivable then
        character.Archivable = true
    end

    local afterimageModel = character:Clone()
    character.Archivable = originalArchivable

    if not afterimageModel then
        return
    end

    afterimageModel.Name = "Afterimage"
    self:_prepareAfterimageClone(afterimageModel)
    afterimageModel:PivotTo(character:GetPivot())
    afterimageModel.Parent = self:_getRuntimeFolder()
    self:_trackAfterimage(afterimageModel)

    task.delay(AFTERIMAGE_LIFETIME, function()
        self:_destroyAfterimage(afterimageModel)
    end)
end

function AfterimageController:_shouldSpawnAfterimage()
    local character = self._character
    local humanoid = self._humanoid
    local rootPart = self._rootPart
    if not (character and character.Parent and humanoid and rootPart and rootPart.Parent) then
        return false
    end

    if humanoid.Health <= 0 then
        return false
    end

    if humanoid.FloorMaterial ~= Enum.Material.Air then
        return false
    end

    local state = humanoid:GetState()
    if not FALLING_STATES[state] then
        return false
    end

    return rootPart.AssemblyLinearVelocity.Y <= -AFTERIMAGE_MIN_FALL_SPEED
end

function AfterimageController:_bindCharacter(character)
    self._character = character
    self._humanoid = getCharacterHumanoid(character)
    self._rootPart = getCharacterRootPart(character)
    self._isFalling = false
    self._lastAfterimageAt = 0
    self:_clearAfterimages()
end

function AfterimageController:_step()
    local isFalling = self:_shouldSpawnAfterimage()
    if not isFalling then
        if self._isFalling then
            self:_clearAfterimages()
        end
        self._isFalling = false
        self._lastAfterimageAt = 0
        return
    end

    local now = os.clock()
    if not self._isFalling then
        self._isFalling = true
        self._lastAfterimageAt = 0
    end

    if now - (self._lastAfterimageAt or 0) < AFTERIMAGE_INTERVAL then
        return
    end

    self._lastAfterimageAt = now
    self:_spawnAfterimage()
end

function AfterimageController:Start()
    if self._started then
        return
    end

    self._started = true
    self:_bindCharacter(localPlayer.Character or localPlayer.CharacterAdded:Wait())

    self._characterAddedConnection = localPlayer.CharacterAdded:Connect(function(character)
        self:_bindCharacter(character)
    end)

    self._characterRemovingConnection = localPlayer.CharacterRemoving:Connect(function()
        self._character = nil
        self._humanoid = nil
        self._rootPart = nil
        self._isFalling = false
        self._lastAfterimageAt = 0
        self:_clearAfterimages()
    end)

    self._heartbeatConnection = RunService.Heartbeat:Connect(function()
        self:_step()
    end)
end

function AfterimageController:Destroy()
    disconnectConnection(self._heartbeatConnection)
    disconnectConnection(self._characterAddedConnection)
    disconnectConnection(self._characterRemovingConnection)
    self._heartbeatConnection = nil
    self._characterAddedConnection = nil
    self._characterRemovingConnection = nil
    self:_clearAfterimages()
end

return AfterimageController