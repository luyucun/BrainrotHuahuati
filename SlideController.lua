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
local ContextActionService = game:GetService("ContextActionService")

local localPlayer = Players.LocalPlayer
local BLOCK_CHARACTER_ACTION = "SlideController_BlockCharacterActions"
local STUDIO_DEBUG_LAUNCH_POWER_ATTRIBUTE = "StudioSlideLaunchPower"
local MIN_DIRECTION_MAGNITUDE = 0.001
local LAUNCH_CLEARANCE_HEIGHT = 1.5

local function sinkCharacterAction()
    return Enum.ContextActionResult.Sink
end

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

local function liftCharacterForLaunch(character, rootPart, height)
    if height <= 0 then
        return
    end

    local offset = Vector3.new(0, height, 0)
    if character and character:IsA("Model") then
        local movedCharacter = pcall(function()
            character:PivotTo(character:GetPivot() + offset)
        end)
        if movedCharacter then
            return
        end
    end

    if rootPart then
        pcall(function()
            rootPart.CFrame = rootPart.CFrame + offset
        end)
    end
end

function SlideController.new()
    local self = setmetatable({}, SlideController)
    self._slideRoot = nil
    self._slideSurfacePart = nil
    self._launchPart = nil
    self._character = nil
    self._humanoid = nil
    self._humanoidRootPart = nil
    self._heartbeatConnection = nil
    self._characterAddedConnection = nil
    self._didWarnMissingSlideRoot = false
    self._didWarnAnimationLoadFailed = false
    self._slideAnimationTrack = nil
    self._animationHumanoid = nil
    self._playerControls = nil
    self._controlsLocked = false
    self._jumpStateLockedHumanoid = nil
    self._isSliding = false
    self._slideDirection = nil
    self._slideSpeed = 0
    self._launchMomentumVelocity = nil
    return self
end

function SlideController:_getConfig()
    return GameConfig.SLIDE or {}
end

function SlideController:_getSurfacePartName()
    local partName = tostring(self:_getConfig().SurfacePartName or "Slide")
    if partName == "" then
        return "Slide"
    end

    return partName
end

function SlideController:_getLaunchPartName()
    local partName = tostring(self:_getConfig().LaunchPartName or "Up")
    if partName == "" then
        return "Up"
    end

    return partName
end

function SlideController:_getRaycastStartOffsetY()
    return math.max(0, tonumber(self:_getConfig().RaycastStartOffsetY) or 2.5)
end

function SlideController:_getRaycastLength()
    return math.max(2, tonumber(self:_getConfig().RaycastLength) or 8)
end

function SlideController:_getEntrySpeed()
    return math.max(0, tonumber(self:_getConfig().EntrySpeed) or 36)
end

function SlideController:_getAcceleration()
    return math.max(0, tonumber(self:_getConfig().Acceleration) or 240)
end

function SlideController:_getMaxSpeed()
    return math.max(0, tonumber(self:_getConfig().MaxSpeed) or 165)
end

function SlideController:_getLaunchAngleDegrees()
    return math.clamp(tonumber(self:_getConfig().LaunchAngleDegrees) or 45, 5, 85)
end

function SlideController:_getAnimationFadeTime()
    return math.max(0, tonumber(self:_getConfig().AnimationFadeTime) or 0.15)
end

function SlideController:_getStudioDebugLaunchPower()
    if not RunService:IsStudio() then
        return 0
    end

    return math.max(0, math.floor(tonumber(localPlayer:GetAttribute(STUDIO_DEBUG_LAUNCH_POWER_ATTRIBUTE)) or 0))
end

function SlideController:_getPersistentLaunchPower()
    return math.max(0, math.floor(tonumber(localPlayer:GetAttribute("LaunchPowerValue")) or 0))
end

function SlideController:_getEffectiveLaunchPower()
    local debugLaunchPower = self:_getStudioDebugLaunchPower()
    if debugLaunchPower > 0 then
        return debugLaunchPower
    end

    return self:_getPersistentLaunchPower()
end

function SlideController:_getLaunchPowerSpeedPerPoint()
    local config = GameConfig.LAUNCH_POWER or {}
    return math.max(0, tonumber(config.SpeedPerPoint) or 1)
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

function SlideController:_resolveSlideSurfacePart()
    local currentPart = self._slideSurfacePart
    if currentPart and currentPart.Parent then
        return currentPart
    end

    local slideRoot = self:_resolveSlideRoot()
    if not slideRoot then
        return nil
    end

    local partName = self:_getSurfacePartName()
    local slidePart = slideRoot:FindFirstChild(partName) or slideRoot:FindFirstChild(partName, true)
    if slidePart and slidePart:IsA("BasePart") then
        self._slideSurfacePart = slidePart
        return slidePart
    end

    return nil
end

function SlideController:_resolveLaunchPart()
    local currentPart = self._launchPart
    if currentPart and currentPart.Parent then
        return currentPart
    end

    local slideRoot = self:_resolveSlideRoot()
    if not slideRoot then
        return nil
    end

    local partName = self:_getLaunchPartName()
    local launchPart = slideRoot:FindFirstChild(partName) or slideRoot:FindFirstChild(partName, true)
    if launchPart and launchPart:IsA("BasePart") then
        self._launchPart = launchPart
        return launchPart
    end

    return nil
end

function SlideController:_getPlayerControls()
    if self._playerControls then
        return self._playerControls
    end

    local playerScripts = localPlayer:FindFirstChild("PlayerScripts")
    if not playerScripts then
        return nil
    end

    local success, controls = pcall(function()
        local playerModule = playerScripts:FindFirstChild("PlayerModule") or playerScripts:WaitForChild("PlayerModule", 2)
        if not playerModule then
            return nil
        end

        return require(playerModule):GetControls()
    end)
    if not success or not controls then
        return nil
    end

    self._playerControls = controls
    return controls
end

function SlideController:_setControlsLocked(humanoid, isLocked)
    if self._controlsLocked == isLocked and ((not isLocked) or self._jumpStateLockedHumanoid == humanoid) then
        return
    end

    local controls = self:_getPlayerControls()
    if isLocked then
        if controls then
            pcall(function()
                controls:Disable()
            end)
        end

        ContextActionService:BindActionAtPriority(
            BLOCK_CHARACTER_ACTION,
            sinkCharacterAction,
            false,
            Enum.ContextActionPriority.High.Value,
            Enum.PlayerActions.CharacterForward,
            Enum.PlayerActions.CharacterBackward,
            Enum.PlayerActions.CharacterLeft,
            Enum.PlayerActions.CharacterRight,
            Enum.PlayerActions.CharacterJump
        )

        if humanoid then
            pcall(function()
                humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
                humanoid.Jump = false
            end)
            self._jumpStateLockedHumanoid = humanoid
        end

        self._controlsLocked = true
        return
    end

    ContextActionService:UnbindAction(BLOCK_CHARACTER_ACTION)
    if controls then
        pcall(function()
            controls:Enable()
        end)
    end

    local lockedHumanoid = self._jumpStateLockedHumanoid or humanoid
    if lockedHumanoid then
        pcall(function()
            lockedHumanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
            lockedHumanoid.Jump = false
        end)
    end

    self._jumpStateLockedHumanoid = nil
    self._controlsLocked = false
end

function SlideController:_raycastGround(rootPart)
    if not rootPart then
        return nil
    end

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = { self._character }
    raycastParams.IgnoreWater = true

    local origin = rootPart.Position + Vector3.new(0, self:_getRaycastStartOffsetY(), 0)
    return Workspace:Raycast(origin, Vector3.new(0, -self:_getRaycastLength(), 0), raycastParams)
end

function SlideController:_getGroundPart(rootPart)
    local result = self:_raycastGround(rootPart)
    local instance = result and result.Instance or nil
    if instance and instance:IsA("BasePart") then
        return instance
    end

    return nil
end

function SlideController:_attachCharacter(character)
    local previousHumanoid = self._humanoid
    if previousHumanoid then
        pcall(function()
            previousHumanoid.AutoRotate = true
        end)
    end

    self:_setControlsLocked(previousHumanoid, false)

    self._character = character
    self._humanoid = nil
    self._humanoidRootPart = nil
    self:_stopSlideAnimation()
    self._isSliding = false
    self._slideDirection = nil
    self._slideSpeed = 0
    self._launchMomentumVelocity = nil

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

function SlideController:_getDownhillDirection(slidePart)
    if not slidePart then
        return nil
    end

    local forward = slidePart.CFrame.LookVector
    local backward = -forward
    local downhill = forward.Y <= backward.Y and forward or backward
    local horizontal = flattenVector(downhill)
    if horizontal.Magnitude <= MIN_DIRECTION_MAGNITUDE then
        horizontal = flattenVector(slidePart.CFrame.LookVector)
    end
    if horizontal.Magnitude <= MIN_DIRECTION_MAGNITUDE then
        return nil
    end

    return horizontal.Unit
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

    track:Play(self:_getAnimationFadeTime())
end

function SlideController:_stopSlideAnimation()
    local track = self._slideAnimationTrack
    if track then
        pcall(function()
            track:Stop(self:_getAnimationFadeTime())
        end)
    end

    self._slideAnimationTrack = nil
    self._animationHumanoid = nil
end

function SlideController:_setSlidingActive(humanoid, isActive)
    if self._isSliding == isActive then
        self:_setControlsLocked(humanoid, isActive)
        if isActive and humanoid then
            humanoid.Jump = false
        end
        return
    end

    self._isSliding = isActive
    self:_setControlsLocked(humanoid, isActive)
    if isActive then
        if humanoid then
            humanoid.AutoRotate = false
            humanoid.Jump = false
        end
        self:_playSlideAnimation(humanoid)
        return
    end

    if humanoid then
        humanoid.AutoRotate = true
        humanoid.Jump = false
    end
    self:_stopSlideAnimation()
end

function SlideController:_leaveSlide(humanoid)
    self._slideDirection = nil
    self._slideSpeed = 0
    self:_setSlidingActive(humanoid, false)
end

function SlideController:_clearLaunchMomentum()
    self._launchMomentumVelocity = nil
end

function SlideController:_setLaunchMomentum(launchVelocity)
    local horizontalVelocity = flattenVector(launchVelocity or Vector3.zero)
    if horizontalVelocity.Magnitude <= MIN_DIRECTION_MAGNITUDE then
        self._launchMomentumVelocity = nil
        return
    end

    self._launchMomentumVelocity = horizontalVelocity
end

function SlideController:_shouldKeepLaunchMomentum(groundPart, slidePart, launchPart)
    if not self._launchMomentumVelocity then
        return false
    end

    if slidePart and groundPart == slidePart then
        return false
    end

    if groundPart and groundPart ~= launchPart then
        return false
    end

    return true
end

function SlideController:_applyLaunchMomentum(rootPart)
    local launchMomentumVelocity = self._launchMomentumVelocity
    if not (rootPart and launchMomentumVelocity) then
        return
    end

    local currentVelocity = rootPart.AssemblyLinearVelocity
    rootPart.AssemblyLinearVelocity = Vector3.new(
        launchMomentumVelocity.X,
        currentVelocity.Y,
        launchMomentumVelocity.Z
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

function SlideController:_updateSlidingVelocity(rootPart, downhillDirection, deltaTime)
    if not (rootPart and downhillDirection) then
        return
    end

    local currentVelocity = rootPart.AssemblyLinearVelocity
    local currentForwardSpeed = math.max(0, flattenVector(currentVelocity):Dot(downhillDirection))

    if not self._isSliding or not self._slideDirection then
        self._slideSpeed = math.max(currentForwardSpeed, self:_getEntrySpeed())
    else
        self._slideSpeed = math.max(self._slideSpeed, currentForwardSpeed)
    end

    self._slideSpeed = math.clamp(self._slideSpeed + (self:_getAcceleration() * deltaTime), 0, self:_getMaxSpeed())
    self._slideDirection = downhillDirection

    rootPart.AssemblyLinearVelocity = Vector3.new(
        downhillDirection.X * self._slideSpeed,
        currentVelocity.Y,
        downhillDirection.Z * self._slideSpeed
    )
end

function SlideController:_launchFromUp(humanoid, rootPart)
    local forwardDirection = self._slideDirection
    if not forwardDirection or forwardDirection.Magnitude <= MIN_DIRECTION_MAGNITUDE then
        forwardDirection = self:_getDownhillDirection(self:_resolveSlideSurfacePart()) or flattenVector(rootPart.AssemblyLinearVelocity)
    end
    if not forwardDirection or forwardDirection.Magnitude <= MIN_DIRECTION_MAGNITUDE then
        return false
    end
    forwardDirection = forwardDirection.Unit

    local currentVelocity = rootPart.AssemblyLinearVelocity
    local currentForwardSpeed = math.max(0, flattenVector(currentVelocity):Dot(forwardDirection))
    local launchHorizontalSpeed = math.max(currentForwardSpeed, self._slideSpeed)
    local effectiveLaunchPower = self:_getEffectiveLaunchPower()
    if effectiveLaunchPower > 0 then
        launchHorizontalSpeed = launchHorizontalSpeed + (effectiveLaunchPower * self:_getLaunchPowerSpeedPerPoint())
    end

    local launchAngleRadians = math.rad(self:_getLaunchAngleDegrees())
    local launchVerticalSpeed = math.max(currentVelocity.Y, launchHorizontalSpeed * math.tan(launchAngleRadians))
    local targetVelocity = Vector3.new(
        forwardDirection.X * launchHorizontalSpeed,
        launchVerticalSpeed,
        forwardDirection.Z * launchHorizontalSpeed
    )

    -- Leave the flat Up part first so the launch impulse is not immediately eaten by ground contact.
    liftCharacterForLaunch(self._character, rootPart, LAUNCH_CLEARANCE_HEIGHT)

    if humanoid then
        pcall(function()
            humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
        end)
    end

    local currentLaunchVelocity = rootPart.AssemblyLinearVelocity
    local deltaVelocity = targetVelocity - currentLaunchVelocity
    local assemblyMass = rootPart.AssemblyMass
    if assemblyMass > 0 then
        rootPart:ApplyImpulse(deltaVelocity * assemblyMass)
    else
        rootPart.AssemblyLinearVelocity = targetVelocity
    end

    self:_setLaunchMomentum(targetVelocity)
    self:_leaveSlide(humanoid)
    return true
end

function SlideController:_onHeartbeat(deltaTime)
    local humanoid, rootPart = self:_ensureCharacterContext()
    if not humanoid or not rootPart or self:_shouldSkipCurrentState(humanoid) then
        self:_clearLaunchMomentum()
        self:_leaveSlide(humanoid)
        return
    end

    local groundPart = self:_getGroundPart(rootPart)
    local launchPart = self:_resolveLaunchPart()
    if self._isSliding and launchPart and groundPart == launchPart then
        if self:_launchFromUp(humanoid, rootPart) then
            return
        end
    end

    local slidePart = self:_resolveSlideSurfacePart()
    if slidePart and groundPart == slidePart then
        self:_clearLaunchMomentum()
        local downhillDirection = self:_getDownhillDirection(slidePart)
        if downhillDirection then
            self:_setSlidingActive(humanoid, true)
            humanoid.Jump = false
            self:_updateSlidingVelocity(rootPart, downhillDirection, deltaTime)
            return
        end
    end

    if self:_shouldKeepLaunchMomentum(groundPart, slidePart, launchPart) then
        self:_applyLaunchMomentum(rootPart)
    else
        self:_clearLaunchMomentum()
    end

    self:_leaveSlide(humanoid)
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


