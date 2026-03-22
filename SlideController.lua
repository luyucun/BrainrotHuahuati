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
local STUDIO_DEBUG_LAUNCH_POWER_ATTRIBUTE = "StudioSlideLaunchPower"
local STUDIO_DEBUG_LAUNCH_SPEED_SCALE = 0.5

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

local function normalizeAssetId(assetId)
    local text = tostring(assetId or "")
    if text == "" then
        return ""
    end

    if string.find(text, "rbxassetid://", 1, true) then
        return text
    end

    return "rbxassetid://" .. text
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
    self._didWarnAnimationLoadFailed = false
    self._slideAnimationTrack = nil
    self._animationHumanoid = nil
    self._isSliding = false
    self._lastSlideTangent = nil
    self._lastSlideSpeed = 0
    self._lastSlideClock = 0
    self._lastLaunchClock = -math.huge
    self._ignoreSlideUntilClock = -math.huge
    self._lastSlidePart = nil
    self._lastSlideContactClock = -math.huge
    self._launchCarryDirection = nil
    self._launchCarrySpeed = 0
    self._launchCarryGroundGraceUntilClock = -math.huge
    return self
end

function SlideController:_getConfig()
    return GameConfig.SLIDE or {}
end

function SlideController:_getSpeedMultiplier()
    return math.max(0.1, tonumber(self:_getConfig().SpeedMultiplier) or 1)
end

function SlideController:_getSlideContactGraceWindow()
    return math.max(0, tonumber(self:_getConfig().ContactGraceWindow) or 0.08)
end

function SlideController:_getStudioDebugLaunchPower()
    if not RunService:IsStudio() then
        return 0
    end

    return math.max(0, tonumber(localPlayer:GetAttribute(STUDIO_DEBUG_LAUNCH_POWER_ATTRIBUTE)) or 0)
end

function SlideController:_warnMissingSlideRoot()
    if self._didWarnMissingSlideRoot then
        return
    end

    self._didWarnMissingSlideRoot = true
    local config = self:_getConfig()
    local modelName = tostring(config.ModelName or "SlideRainbow01")
    local surfaceContainerName = tostring(config.SurfaceContainerName or "")
    local rootPath = surfaceContainerName ~= ""
        and string.format("Workspace/%s/%s", modelName, surfaceContainerName)
        or string.format("Workspace/%s", modelName)
    warn(string.format(
        "[SlideController] 找不到滑梯节点 %s，滑滑梯功能暂不可用。",
        rootPath
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

    local slideModel = Workspace:FindFirstChild(modelName)
    if not slideModel then
        self:_warnMissingSlideRoot()
        return nil
    end

    local surfaceContainerName = tostring(self:_getConfig().SurfaceContainerName or "")
    local slideRoot = surfaceContainerName ~= ""
        and (slideModel:FindFirstChild(surfaceContainerName) or slideModel:FindFirstChild(surfaceContainerName, true))
        or slideModel
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
    self:_stopSlideAnimation()
    self._isSliding = false
    self._lastSlideTangent = nil
    self._lastSlideSpeed = 0
    self._lastSlideClock = 0
    self._ignoreSlideUntilClock = -math.huge
    self._lastSlidePart = nil
    self._lastSlideContactClock = -math.huge
    self._launchCarryDirection = nil
    self._launchCarrySpeed = 0
    self._launchCarryGroundGraceUntilClock = -math.huge

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
    if os.clock() < self._ignoreSlideUntilClock then
        return nil
    end

    local slideRoot = self:_resolveSlideRoot()
    if not (slideRoot and rootPart) then
        return nil
    end

    local config = self:_getConfig()
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = { self._character }
    raycastParams.IgnoreWater = true

    local startOffsetY = math.max(0, tonumber(config.RaycastStartOffsetY) or 2.5)
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

function SlideController:_resolveTravelTangent(slidePart, currentVelocity)
    local forward = slidePart.CFrame.LookVector.Unit
    local backward = -forward
    local downhill = forward.Y <= backward.Y and forward or backward

    if self._isSliding and self._lastSlideTangent then
        if self._lastSlideTangent:Dot(forward) >= self._lastSlideTangent:Dot(backward) then
            return forward, downhill
        end

        return backward, downhill
    end

    local directionLockSpeedThreshold = math.max(0, tonumber(self:_getConfig().DirectionLockSpeedThreshold) or 6)
    local forwardScore = currentVelocity:Dot(forward)
    local backwardScore = currentVelocity:Dot(backward)

    if math.max(forwardScore, backwardScore) >= directionLockSpeedThreshold then
        if forwardScore >= backwardScore then
            return forward, downhill
        end
        return backward, downhill
    end

    if self._lastSlideTangent then
        if self._lastSlideTangent:Dot(forward) >= self._lastSlideTangent:Dot(backward) then
            return forward, downhill
        end
        return backward, downhill
    end

    return downhill, downhill
end

function SlideController:_computeTargetVelocity(currentVelocity, travelTangent, deltaTime)
    local config = self:_getConfig()
    local speedMultiplier = self:_getSpeedMultiplier()
    local tangentUnit = travelTangent.Unit
    local horizontalDirection = flattenVector(tangentUnit)
    if horizontalDirection.Magnitude <= 0.001 then
        return currentVelocity, 0
    end
    horizontalDirection = horizontalDirection.Unit

    local currentHorizontalVelocity = flattenVector(currentVelocity)
    local currentTangentialSpeed = currentHorizontalVelocity:Dot(horizontalDirection)
    local entrySpeed = math.max(0, tonumber(config.EntrySpeed) or 24) * speedMultiplier

    local currentTravelSpeed = math.max(0, currentTangentialSpeed)
    if self._isSliding then
        currentTravelSpeed = math.max(currentTravelSpeed, tonumber(self._lastSlideSpeed) or 0)
    else
        currentTravelSpeed = entrySpeed
    end

    local signedSlope = -tangentUnit.Y
    local acceleration = math.max(0, tonumber(config.Acceleration) or 160) * speedMultiplier
    local surfaceDeceleration = math.max(0, tonumber(config.SurfaceDeceleration) or 10) * speedMultiplier
    local maxSpeed = math.max(0, tonumber(config.MaxSpeed) or 120) * speedMultiplier
    local climbDecelerationMultiplier = math.max(0, tonumber(config.ClimbDecelerationMultiplier) or 1)

    local slopeAcceleration = acceleration * signedSlope
    if signedSlope < 0 then
        slopeAcceleration = slopeAcceleration * climbDecelerationMultiplier
    end

    local launchUpwardThreshold = math.max(0, tonumber(config.LaunchUpwardDirectionThreshold) or 0.08)
    local isExitSegment = tangentUnit.Y >= launchUpwardThreshold
    local nextSpeed = currentTravelSpeed + (slopeAcceleration * deltaTime)
    if isExitSegment then
        nextSpeed = math.max(currentTravelSpeed, nextSpeed)
    else
        nextSpeed = math.max(0, nextSpeed - (surfaceDeceleration * deltaTime))
    end
    nextSpeed = math.min(maxSpeed, nextSpeed)

    local baseTangentialSpeed = self._isSliding and currentTravelSpeed or currentTangentialSpeed
    local tangentialVelocity = horizontalDirection * baseTangentialSpeed
    local orthogonalVelocity = currentHorizontalVelocity - tangentialVelocity
    local lateralDamping = math.max(0, tonumber(config.LateralDamping) or 6)
    local lateralAlpha = self._isSliding and math.clamp(lateralDamping * deltaTime, 0, 1) or 1
    local dampedOrthogonalVelocity = orthogonalVelocity:Lerp(Vector3.zero, lateralAlpha)

    local responsiveness = math.max(0, tonumber(config.HorizontalResponsiveness) or 10)
    local responseAlpha = self._isSliding and math.clamp(responsiveness * deltaTime, 0, 1) or 1
    local targetTangentialVelocity = horizontalDirection * nextSpeed
    local blendedTangentialVelocity = tangentialVelocity:Lerp(targetTangentialVelocity, responseAlpha)
    local blendedHorizontalVelocity = blendedTangentialVelocity + dampedOrthogonalVelocity
    local blendedVelocity = Vector3.new(
        blendedHorizontalVelocity.X,
        currentVelocity.Y,
        blendedHorizontalVelocity.Z
    )
    return blendedVelocity, nextSpeed
end

function SlideController:_clearLaunchCarry()
    self._launchCarryDirection = nil
    self._launchCarrySpeed = 0
    self._launchCarryGroundGraceUntilClock = -math.huge
end

function SlideController:_beginLaunchCarry(launchVelocity, nowClock)
    local horizontalVelocity = flattenVector(launchVelocity)
    local horizontalSpeed = horizontalVelocity.Magnitude
    if horizontalSpeed <= 0.001 then
        self:_clearLaunchCarry()
        return
    end

    self._launchCarryDirection = horizontalVelocity.Unit
    self._launchCarrySpeed = horizontalSpeed
    self._launchCarryGroundGraceUntilClock = nowClock + 0.2
end

function SlideController:_maintainLaunchCarry(humanoid, rootPart)
    if not (humanoid and rootPart and self._launchCarryDirection and self._launchCarrySpeed > 0) then
        return
    end

    local nowClock = os.clock()
    local state = humanoid:GetState()
    local isAirborne = humanoid.FloorMaterial == Enum.Material.Air
        or state == Enum.HumanoidStateType.Freefall
        or state == Enum.HumanoidStateType.Jumping
        or state == Enum.HumanoidStateType.FallingDown
        or nowClock < self._launchCarryGroundGraceUntilClock

    if not isAirborne then
        self:_clearLaunchCarry()
        return
    end

    local currentVelocity = rootPart.AssemblyLinearVelocity
    local currentHorizontalVelocity = flattenVector(currentVelocity)
    local currentForwardSpeed = currentHorizontalVelocity:Dot(self._launchCarryDirection)
    if currentForwardSpeed >= self._launchCarrySpeed then
        return
    end

    local desiredHorizontalVelocity = self._launchCarryDirection * self._launchCarrySpeed
    rootPart.AssemblyLinearVelocity = Vector3.new(
        desiredHorizontalVelocity.X,
        currentVelocity.Y,
        desiredHorizontalVelocity.Z
    )
end

function SlideController:_getAnimator(humanoid)
    if not humanoid then
        return nil
    end

    local animator = humanoid:FindFirstChildOfClass("Animator")
    if animator then
        return animator
    end

    return humanoid:FindFirstChild("Animator") or humanoid:WaitForChild("Animator", 2)
end

function SlideController:_ensureSlideAnimationTrack(humanoid)
    if self._animationHumanoid == humanoid and self._slideAnimationTrack then
        return self._slideAnimationTrack
    end

    self:_stopSlideAnimation()

    local animator = self:_getAnimator(humanoid)
    if not animator then
        return nil
    end

    local animationId = normalizeAssetId(self:_getConfig().AnimationId)
    if animationId == "" then
        return nil
    end

    local animation = Instance.new("Animation")
    animation.AnimationId = animationId

    local success, track = pcall(function()
        return animator:LoadAnimation(animation)
    end)
    animation:Destroy()

    if not success or not track then
        if not self._didWarnAnimationLoadFailed then
            self._didWarnAnimationLoadFailed = true
            warn(string.format("[SlideController] 滑梯动作加载失败: %s", tostring(track)))
        end
        return nil
    end

    track.Priority = Enum.AnimationPriority.Action
    track.Looped = true
    track:AdjustSpeed(math.max(0.1, tonumber(self:_getConfig().AnimationPlaybackSpeed) or 1))
    self._slideAnimationTrack = track
    self._animationHumanoid = humanoid
    return track
end

function SlideController:_playSlideAnimation(humanoid)
    local track = self:_ensureSlideAnimationTrack(humanoid)
    if not track or track.IsPlaying then
        return
    end

    track:Play(math.max(0, tonumber(self:_getConfig().AnimationFadeTime) or 0.15))
end

function SlideController:_stopSlideAnimation()
    local track = self._slideAnimationTrack
    if track then
        pcall(function()
            track:Stop(math.max(0, tonumber(self:_getConfig().AnimationFadeTime) or 0.15))
        end)
    end

    self._slideAnimationTrack = nil
    self._animationHumanoid = nil
end

function SlideController:_setSlidingActive(humanoid, isActive)
    if self._isSliding == isActive then
        return
    end

    self._isSliding = isActive
    if isActive then
        if humanoid then
            humanoid.AutoRotate = false
        end
        self:_playSlideAnimation(humanoid)
        return
    end

    if humanoid then
        humanoid.AutoRotate = true
    end
    self:_stopSlideAnimation()
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

function SlideController:_shouldLaunch(nowClock)
    local config = self:_getConfig()
    if nowClock - self._lastLaunchClock < math.max(0, tonumber(config.LaunchCooldown) or 0.35) then
        return false
    end

    if nowClock - self._lastSlideClock > math.max(0, tonumber(config.LaunchWindow) or 0.15) then
        return false
    end

    if not self._lastSlideTangent then
        return false
    end

    if self._lastSlideTangent.Y < math.max(0, tonumber(config.LaunchUpwardDirectionThreshold) or 0.08) then
        return false
    end

    local minLaunchSpeed = math.max(0, tonumber(config.LaunchMinSpeed) or 42) * self:_getSpeedMultiplier()
    return self._lastSlideSpeed >= minLaunchSpeed
end

function SlideController:_applyLaunch(humanoid, rootPart, nowClock)
    if not (rootPart and self._lastSlideTangent) then
        return
    end

    local tangentUnit = self._lastSlideTangent.Unit
    local config = self:_getConfig()
    local currentSpeed = math.max(0, rootPart.AssemblyLinearVelocity:Dot(tangentUnit))
    local launchSpeed = math.max(currentSpeed, self._lastSlideSpeed)

    local debugLaunchPower = self:_getStudioDebugLaunchPower()
    if debugLaunchPower > 0 then
        launchSpeed = launchSpeed + (debugLaunchPower * STUDIO_DEBUG_LAUNCH_SPEED_SCALE)
    end

    local launchVelocity = tangentUnit * launchSpeed
    rootPart.AssemblyLinearVelocity = launchVelocity
    self:_beginLaunchCarry(launchVelocity, nowClock)

    if humanoid then
        pcall(function()
            humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
        end)
    end

    self._lastLaunchClock = nowClock
    self._ignoreSlideUntilClock = nowClock + math.max(0.2, tonumber(config.LaunchCooldown) or 0.35)
end

function SlideController:_onHeartbeat(deltaTime)
    local humanoid, rootPart = self:_ensureCharacterContext()
    if not humanoid or not rootPart or self:_shouldSkipCurrentState(humanoid) then
        self:_setSlidingActive(humanoid, false)
        return
    end

    local nowClock = os.clock()
    local currentVelocity = rootPart.AssemblyLinearVelocity
    local slidePart = self:_getCurrentSlidePart(rootPart)
    if slidePart then
        self._lastSlidePart = slidePart
        self._lastSlideContactClock = nowClock
    elseif self._isSliding and self:_shouldLaunch(nowClock) then
        self:_applyLaunch(humanoid, rootPart, nowClock)
    elseif self._isSliding and self._lastSlidePart and (nowClock - self._lastSlideContactClock) <= self:_getSlideContactGraceWindow() then
        slidePart = self._lastSlidePart
    end

    if slidePart then
        self:_clearLaunchCarry()
        local travelTangent = select(1, self:_resolveTravelTangent(slidePart, currentVelocity))
        local targetVelocity, nextSpeed = self:_computeTargetVelocity(currentVelocity, travelTangent, deltaTime)
        rootPart.AssemblyLinearVelocity = targetVelocity

        local moveDirection = flattenVector(travelTangent)
        if moveDirection.Magnitude > 0.001 then
            humanoid:Move(moveDirection.Unit, false)
        end

        self._lastSlidePart = slidePart
        self._lastSlideTangent = travelTangent.Unit
        self._lastSlideSpeed = nextSpeed
        self._lastSlideClock = nowClock
        self:_setSlidingActive(humanoid, true)
        return
    end

    self:_maintainLaunchCarry(humanoid, rootPart)
    self._lastSlidePart = nil
    self._lastSlideTangent = nil
    self._lastSlideSpeed = 0
    self._lastSlideClock = 0
    self._lastSlideContactClock = -math.huge
    self:_setSlidingActive(humanoid, false)
end

function SlideController:Start()
    self:_resolveSlideRoot()
    self:_attachCharacter(localPlayer.Character)

    if self._characterAddedConnection then
        self._characterAddedConnection:Disconnect()
        self._characterAddedConnection = nil
    end

    if self._heartbeatConnection then
        self._heartbeatConnection:Disconnect()
        self._heartbeatConnection = nil
    end

    self._characterAddedConnection = localPlayer.CharacterAdded:Connect(function(character)
        self:_attachCharacter(character)
    end)

    self._heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
        self:_onHeartbeat(deltaTime)
    end)
end

return SlideController
