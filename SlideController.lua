--[[
脚本名字: SlideController
脚本文件: SlideController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/SlideController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

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
        "[SlideController] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local GameConfig = requireSharedModule("GameConfig")

local SlideController = {}
SlideController.__index = SlideController

local function flattenVector(vector)
    return Vector3.new(vector.X, 0, vector.Z)
end

function SlideController.new()
    local self = setmetatable({}, SlideController)
    self._slideRoot = nil
    self._character = nil
    self._humanoid = nil
    self._humanoidRootPart = nil
    self._heartbeatConnection = nil
    self._characterAddedConnection = nil
    self._didWarnMissingSlideRoot = false
    return self
end

function SlideController:_getConfig()
    return GameConfig.SLIDE or {}
end

function SlideController:_warnMissingSlideRoot()
    if self._didWarnMissingSlideRoot then
        return
    end

    self._didWarnMissingSlideRoot = true
    warn(string.format(
        "[SlideController] 找不到滑梯模型 Workspace/%s，滑滑梯功能暂不可用。",
        tostring(self:_getConfig().ModelName or "SlideRainbow01")
    ))
end

function SlideController:_resolveSlideRoot()
    local currentRoot = self._slideRoot
    if currentRoot and currentRoot.Parent then
        return currentRoot
    end

    local modelName = tostring(self:_getConfig().ModelName or "")
    if modelName == "" then
        return nil
    end

    local slideRoot = Workspace:FindFirstChild(modelName)
    if slideRoot then
        self._slideRoot = slideRoot
        return slideRoot
    end

    self:_warnMissingSlideRoot()
    return nil
end

function SlideController:_attachCharacter(character)
    self._character = character
    self._humanoid = nil
    self._humanoidRootPart = nil

    if not character then
        return
    end

    task.defer(function()
        if self._character ~= character then
            return
        end

        self._humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
        self._humanoidRootPart = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 5)
    end)
end

function SlideController:_ensureCharacterContext()
    local character = localPlayer.Character
    if character ~= self._character then
        self:_attachCharacter(character)
    end

    if not (self._character and self._character.Parent) then
        return nil, nil
    end

    if not (self._humanoid and self._humanoid.Parent) then
        self._humanoid = self._character:FindFirstChildOfClass("Humanoid")
    end

    if not (self._humanoidRootPart and self._humanoidRootPart.Parent) then
        self._humanoidRootPart = self._character:FindFirstChild("HumanoidRootPart")
    end

    return self._humanoid, self._humanoidRootPart
end

function SlideController:_getCurrentSlidePart(rootPart)
    local slideRoot = self:_resolveSlideRoot()
    if not (slideRoot and rootPart) then
        return nil
    end

    local config = self:_getConfig()
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = { self._character }
    raycastParams.IgnoreWater = true

    local startOffsetY = math.max(0, tonumber(config.RaycastStartOffsetY) or 2)
    local rayLength = math.max(2, tonumber(config.RaycastLength) or 8)
    local origin = rootPart.Position + Vector3.new(0, startOffsetY, 0)
    local result = Workspace:Raycast(origin, Vector3.new(0, -rayLength, 0), raycastParams)
    if not (result and result.Instance and result.Instance:IsA("BasePart")) then
        return nil
    end

    if not result.Instance:IsDescendantOf(slideRoot) then
        return nil
    end

    return result.Instance
end

function SlideController:_computeDownhillDirection(slidePart)
    if not slidePart then
        return nil
    end

    local bestDirection = nil
    local bestY = math.huge
    local candidates = {
        slidePart.CFrame.LookVector,
        -slidePart.CFrame.LookVector,
        slidePart.CFrame.RightVector,
        -slidePart.CFrame.RightVector,
    }

    for _, direction in ipairs(candidates) do
        if direction.Y < bestY then
            bestY = direction.Y
            bestDirection = direction
        end
    end

    local minSlopeVerticalComponent = math.max(0.001, tonumber(self:_getConfig().MinSlopeVerticalComponent) or 0.03)
    if not bestDirection or bestDirection.Y >= -minSlopeVerticalComponent then
        return nil
    end

    return bestDirection.Unit
end

function SlideController:_applySlideVelocity(rootPart, slideDirection, deltaTime)
    local horizontalDirection = flattenVector(slideDirection)
    if horizontalDirection.Magnitude <= 0.001 then
        return
    end

    horizontalDirection = horizontalDirection.Unit

    local config = self:_getConfig()
    local currentVelocity = rootPart.AssemblyLinearVelocity
    local currentHorizontalVelocity = flattenVector(currentVelocity)
    local currentDownhillSpeed = currentHorizontalVelocity:Dot(horizontalDirection)
    local lateralVelocity = currentHorizontalVelocity - (horizontalDirection * currentDownhillSpeed)

    local slopeFactor = math.clamp(-slideDirection.Y, 0, 1)
    local entrySpeed = math.max(0, tonumber(config.EntrySpeed) or 24)
    local maxSpeed = math.max(entrySpeed, tonumber(config.MaxSpeed) or 120)
    local acceleration = math.max(0, tonumber(config.Acceleration) or 160)
    local targetDownhillSpeed = math.max(entrySpeed, currentDownhillSpeed)
    targetDownhillSpeed = math.min(maxSpeed, targetDownhillSpeed + (acceleration * slopeFactor * deltaTime))

    local lateralDamping = math.max(0, tonumber(config.LateralDamping) or 3)
    local lateralAlpha = math.clamp(lateralDamping * deltaTime, 0, 1)
    local dampedLateralVelocity = lateralVelocity:Lerp(Vector3.zero, lateralAlpha)

    local targetHorizontalVelocity = (horizontalDirection * targetDownhillSpeed) + dampedLateralVelocity
    local responsiveness = math.max(0, tonumber(config.HorizontalResponsiveness) or 10)
    local responseAlpha = math.clamp(responsiveness * deltaTime, 0, 1)
    local blendedHorizontalVelocity = currentHorizontalVelocity:Lerp(targetHorizontalVelocity, responseAlpha)

    rootPart.AssemblyLinearVelocity = Vector3.new(
        blendedHorizontalVelocity.X,
        currentVelocity.Y,
        blendedHorizontalVelocity.Z
    )
end

function SlideController:_shouldSkipCurrentState(humanoid)
    if not humanoid then
        return true
    end

    if humanoid.Health <= 0 then
        return true
    end

    local state = humanoid:GetState()
    return state == Enum.HumanoidStateType.Dead
        or state == Enum.HumanoidStateType.Seated
        or state == Enum.HumanoidStateType.Climbing
        or state == Enum.HumanoidStateType.Swimming
end

function SlideController:_onHeartbeat(deltaTime)
    local humanoid, rootPart = self:_ensureCharacterContext()
    if not humanoid or not rootPart or self:_shouldSkipCurrentState(humanoid) then
        return
    end

    local slidePart = self:_getCurrentSlidePart(rootPart)
    if not slidePart then
        return
    end

    local downhillDirection = self:_computeDownhillDirection(slidePart)
    if not downhillDirection then
        return
    end

    self:_applySlideVelocity(rootPart, downhillDirection, deltaTime)
end

function SlideController:Start()
    self:_resolveSlideRoot()
    self:_attachCharacter(localPlayer.Character)

    if self._characterAddedConnection then
        self._characterAddedConnection:Disconnect()
        self._characterAddedConnection = nil
    end

    self._characterAddedConnection = localPlayer.CharacterAdded:Connect(function(character)
        self:_attachCharacter(character)
    end)

    if self._heartbeatConnection then
        self._heartbeatConnection:Disconnect()
        self._heartbeatConnection = nil
    end

    self._heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
        self:_onHeartbeat(deltaTime)
    end)
end

return SlideController