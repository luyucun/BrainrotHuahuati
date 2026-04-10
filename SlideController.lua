--[[
脚本名字: SlideController
脚本文件: SlideController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/SlideController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ContextActionService = game:GetService("ContextActionService")

local localPlayer = Players.LocalPlayer
local BLOCK_CHARACTER_ACTION = "SlideController_BlockCharacterActions"
local STUDIO_DEBUG_LAUNCH_POWER_ATTRIBUTE = "StudioSlideLaunchPower"
local STUDIO_DEBUG_LAST_LAUNCH_HORIZONTAL_SPEED_ATTRIBUTE = "StudioSlideLastLaunchHorizontalSpeed"
local STUDIO_DEBUG_LAST_LAUNCH_VERTICAL_SPEED_ATTRIBUTE = "StudioSlideLastLaunchVerticalSpeed"
local STUDIO_DEBUG_LAST_LAUNCH_TOTAL_SPEED_ATTRIBUTE = "StudioSlideLastLaunchTotalSpeed"
local STUDIO_DEBUG_LAST_LAUNCH_POWER_USED_ATTRIBUTE = "StudioSlideLastLaunchPowerUsed"
local STUDIO_DEBUG_LAST_LAUNCH_SLIDE_SPEED_ATTRIBUTE = "StudioSlideLastLaunchSlideSpeed"
local MIN_DIRECTION_MAGNITUDE = 0.001
local LAUNCH_CLEARANCE_HEIGHT = 1.5
local FLY_LATERAL_SPEED_FACTOR = 0.3
local FLY_LATERAL_SPEED_MIN = 18
local FLY_LATERAL_SPEED_MAX = 42
local BULLET_TIME_FX_ROOT_NAME = "BulletTimeFx"
local BULLET_TIME_FX_IMAGE_NAME = "EdgeBlur"
local BULLET_TIME_FX_OUTER_IMAGE_NAME = "EdgeBlurOuter"
local BULLET_TIME_FX_IMAGE_ASSET = "rbxassetid://135462643733179"
local BULLET_TIME_FX_FADE_IN_TIME = 0.08
local BULLET_TIME_FX_FADE_OUT_TIME = 0.12
local BULLET_TIME_FX_VISIBLE_TRANSPARENCY = 0.72
local BULLET_TIME_FX_OUTER_VISIBLE_TRANSPARENCY = 0.82
local BULLET_TIME_FX_HIDDEN_TRANSPARENCY = 1
local BULLET_TIME_FX_IMAGE_COLOR = Color3.fromRGB(255, 255, 255)
local BULLET_TIME_FX_IDLE_SIZE = UDim2.fromScale(1.14, 1.14)
local BULLET_TIME_FX_ACTIVE_SIZE = UDim2.fromScale(1.28, 1.28)
local BULLET_TIME_FX_OUTER_IDLE_SIZE = UDim2.fromScale(1.28, 1.28)
local BULLET_TIME_FX_OUTER_ACTIVE_SIZE = UDim2.fromScale(1.44, 1.44)
local BULLET_TIME_COLOR_CORRECTION_NAME = "SlideBulletTimeColorCorrection"
local BULLET_TIME_BLUR_NAME = "SlideBulletTimeBlur"
local BULLET_TIME_COLOR_CONTRAST = 0.12
local BULLET_TIME_COLOR_SATURATION = -0.02
local BULLET_TIME_COLOR_TINT = Color3.fromRGB(255, 248, 240)
local BULLET_TIME_BLUR_SIZE = 4
local BULLET_TIME_FOV_OFFSET = -10
local HIDDEN_CORE_GUI_TYPE_NAMES = { "Backpack", "Chat", "EmotesMenu", "Health", "PlayerList", "SelfView" }
local LANDING_BURST_ROOT_NAME = "SlideLandingFx"
local LANDING_BURST_COLOR = Color3.fromRGB(0, 255, 0)
local FAST_LANDING_TRIGGER_KEYCODE = Enum.KeyCode.Space
local AIR_CONTROL_KEYCODES = {
	[Enum.KeyCode.A] = Vector2.new(-1, 0),
	[Enum.KeyCode.Left] = Vector2.new(-1, 0),
	[Enum.KeyCode.D] = Vector2.new(1, 0),
	[Enum.KeyCode.Right] = Vector2.new(1, 0),
}

local function sinkCharacterAction()
	return Enum.ContextActionResult.Sink
end

local function disconnectAll(connectionList)
	if type(connectionList) ~= "table" then
		return
	end

	for _, connection in ipairs(connectionList) do
		if connection then
			connection:Disconnect()
		end
	end
	table.clear(connectionList)
end

local function isPressInput(inputObject)
	if not inputObject then
		return false
	end

	local userInputType = inputObject.UserInputType
	return userInputType == Enum.UserInputType.MouseButton1
		or userInputType == Enum.UserInputType.Touch
end
local function playTween(instance, duration, properties)
	if not instance then
		return nil
	end

	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		properties
	)
	tween:Play()
	return tween
end

local function setGuiEnabled(guiObject, isEnabled)
	return pcall(function()
		guiObject.Enabled = isEnabled
	end)
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
local JetpackConfig = requireSharedModule("JetpackConfig")

local SlideController = {}
SlideController.__index = SlideController

local function flattenVector(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function normalizeJetpackId(value)
	return math.max(0, math.floor(tonumber(value) or 0))
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

local function clampVector2Magnitude(vector, maxMagnitude)
	local magnitude = vector.Magnitude
	if magnitude <= maxMagnitude then
		return vector
	end

	if magnitude <= MIN_DIRECTION_MAGNITUDE then
		return Vector2.zero
	end

	return vector.Unit * maxMagnitude
end

local function moveTowardsVector3(current, target, maxDelta)
	local delta = target - current
	local distance = delta.Magnitude
	if distance <= maxDelta or distance <= MIN_DIRECTION_MAGNITUDE then
		return target
	end

	return current + (delta / distance) * maxDelta
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

local NO_GRAVITY_ATTACHMENT_NAME = "SlideNoGravityAttachment"
local NO_GRAVITY_FORCE_NAME = "SlideNoGravityForce"
local NO_GRAVITY_GROUND_CHECK_GRACE_SECONDS = 0.15
local MOVEMENT_ANIMATION_KEYS = { "slide", "launch", "fall" }
local LANDING_RECOVERY_STATE_RESET_DELAY = 0.45
local DEFAULT_LANDING_RECOVERY_HORIZONTAL_SPEED = 6
local FLIGHT_EFFECT_FOLDER_NAME = "Effect"
local FLIGHT_EFFECT_RUNTIME_FOLDER_NAME = "SlideFlightEffects"
local FLIGHT_EFFECT_WELD_NAME = "SlideFlightEffectWeld"
local FLIGHT_EFFECT_TEMPLATE_NAMES = { "FlyEffect01" }
local LANDING_SOUND_ASSET_ID = "rbxassetid://138533090376585"
local LANDING_SOUND_TEMPLATE_FOLDER_NAME = "Audio"
local LANDING_SOUND_TEMPLATE_SLIDE_FOLDER_NAME = "Slide"
local LANDING_SOUND_TEMPLATE_NAME = "Landing"
local FLIGHT_COLLISION_FALL_SPEED = 24
local LANDING_SHAKE_RENDERSTEP_NAME = "SlideController_LandingShake"
local FAST_LANDING_GROUND_BUFFER = 0.35
local FAST_LANDING_FALLBACK_DELTA_TIME = 1 / 60
local FAST_LANDING_UPWARD_SUPPRESS_FRAMES = 8

function SlideController.new(progressController)
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
	self._didWarnAnimationLoadFailed = {}
	self._slideAnimationTrack = nil
	self._launchAnimationTrack = nil
	self._fallAnimationTrack = nil
	self._landingAnimationTrack = nil
	self._animationHumanoid = nil
	self._currentAnimationKey = nil
	self._lastLandingAt = 0
	self._lastLandingSoundAt = 0
	self._playerControls = nil
	self._controlsLocked = false
	self._jumpStateLockedHumanoid = nil
	self._isSliding = false
	self._slideDirection = nil
	self._slideSpeed = 0
	self._launchMomentumVelocity = nil
	self._noGravityAttachment = nil
	self._noGravityForce = nil
	self._launchNoGravityRootPart = nil
	self._launchNoGravityDuration = 0
	self._launchNoGravityEndTime = 0
	self._launchNoGravityGroundCheckAt = 0
	self._flyProgressRoot = nil
	self._flyProgressBar = nil
	self._flyProgressBarBaseSize = nil
	self._flyButtonRoot = nil
	self._flyHoldButton = nil
	self._flyLeftButton = nil
	self._flyRightButton = nil
	self._flyLandButton = nil
	self._flyTipsRoot = nil
	self._flyUiConnections = {}
	self._flyLeftPressed = false
	self._flyRightPressed = false
	self._flyLateralVelocity = Vector3.zero
	self._flyControlVelocity = Vector3.zero
	self._flyKeyboardState = {}
	self._flyKeyboardInput = Vector2.zero
	self._flyTouchInput = Vector2.zero
	self._flyTouchDragInputObject = nil
	self._flyTouchDragStartPosition = nil
	self._flyTouchDragPosition = nil
	self._flyInputConnections = {}
	self._isLaunchFlightActive = false
	self._isFastLandingActive = false
	self._isBulletTimeActive = false
	self._bulletTimeBaselineVelocity = nil
	self._bulletTimeBaselineLaunchMomentumVelocity = nil
	self._bulletTimeBaselineTrajectoryVelocity = nil
	self._bulletTimeStartedAt = 0
	self._bulletTimeFxRoot = nil
	self._bulletTimeFxImage = nil
	self._bulletTimeFxOuterImage = nil
	self._bulletTimeColorCorrection = nil
	self._bulletTimeBlur = nil
	self._bulletTimeBaseFieldOfView = nil
	self._isGameplayUiHidden = false
	self._hiddenPlayerGuiStates = {}
	self._hiddenMainGuiStates = {}
	self._hiddenCoreGuiStates = {}
	self._touchedSlidePart = nil
	self._touchedSlidePartExpireAt = 0
	self._slideTouchedConnections = {}
	self._launchFlightCollisionConnections = {}
	self._pendingLaunchCollisionPart = nil
	self._pendingLaunchLandingImpact = false
	self._flightEffectRuntimeRoot = nil
	self._flightEffectRootPart = nil
	self._didWarnMissingFlightEffectTemplate = {}
	self._progressController = type(progressController) == "table" and progressController or nil
	self._flightProgressStartWorldPosition = nil
	self._flightProgressEndWorldPosition = nil
	self._flightProgressDistanceXZ = 0
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

function SlideController:_getProgressWorldConfig()
	local progressConfig = GameConfig.PROGRESS or {}
	return {
		landRootFolderName = tostring(progressConfig.LandRootFolderName or "Land"),
		floatLandFolderPrefix = tostring(progressConfig.FloatLandFolderPrefix or "FloatLand"),
		floatLandCount = math.max(1, math.floor(tonumber(progressConfig.FloatLandCount) or 9)),
		floatLandPartName = tostring(progressConfig.FloatLandPartName or "Land"),
	}
end

function SlideController:_resolveFlightProgressStartWorldPosition()
	local slidePart = self:_resolveSlideSurfacePart()
	if not (slidePart and slidePart:IsA("BasePart")) then
		return nil
	end

	local launchPart = self:_resolveLaunchPart()
	if launchPart and launchPart:IsA("BasePart") then
		local launchDirection = flattenVector(launchPart.Position - slidePart.Position)
		if launchDirection.Magnitude > MIN_DIRECTION_MAGNITUDE then
			local halfExtent = math.max(slidePart.Size.X, slidePart.Size.Z) * 0.5
			local startPosition = slidePart.Position - (launchDirection.Unit * halfExtent)
			return Vector3.new(startPosition.X, slidePart.Position.Y, startPosition.Z)
		end
	end

	return slidePart.Position
end

function SlideController:_resolveFlightProgressEndWorldPosition()
	local progressConfig = self:_getProgressWorldConfig()
	local landRoot = Workspace:FindFirstChild(progressConfig.landRootFolderName)
	if not landRoot then
		return nil
	end

	local ogPart = landRoot:FindFirstChild("OG") or landRoot:FindFirstChild("OG", true)
	if ogPart and ogPart:IsA("BasePart") then
		return ogPart.Position
	end

	local targetFloatLandName = string.format(
		"%s%d",
		progressConfig.floatLandFolderPrefix,
		progressConfig.floatLandCount
	)
	local targetFloatLand = landRoot:FindFirstChild(targetFloatLandName)
		or landRoot:FindFirstChild(targetFloatLandName, true)
	if targetFloatLand then
		local targetPart = targetFloatLand:FindFirstChild(progressConfig.floatLandPartName)
			or targetFloatLand:FindFirstChild(progressConfig.floatLandPartName, true)
		if targetPart and targetPart:IsA("BasePart") then
			return targetPart.Position
		end
	end

	return nil
end

function SlideController:_cacheFlightProgressPath()
	self._flightProgressStartWorldPosition = self:_resolveFlightProgressStartWorldPosition()
	self._flightProgressEndWorldPosition = self:_resolveFlightProgressEndWorldPosition()
	self._flightProgressDistanceXZ = 0

	local startPosition = self._flightProgressStartWorldPosition
	local endPosition = self._flightProgressEndWorldPosition
	if startPosition and endPosition then
		local startPlanar = Vector3.new(startPosition.X, 0, startPosition.Z)
		local endPlanar = Vector3.new(endPosition.X, 0, endPosition.Z)
		self._flightProgressDistanceXZ = (endPlanar - startPlanar).Magnitude
	end
end

function SlideController:_computeFlightProgressRatio(worldPosition)
	local startPosition = self._flightProgressStartWorldPosition
	local endPosition = self._flightProgressEndWorldPosition
	if not (startPosition and endPosition and typeof(worldPosition) == "Vector3") then
		return nil
	end

	if self._flightProgressDistanceXZ <= MIN_DIRECTION_MAGNITUDE then
		return nil
	end

	local startPlanar = Vector3.new(startPosition.X, 0, startPosition.Z)
	local endPlanar = Vector3.new(endPosition.X, 0, endPosition.Z)
	local currentPlanar = Vector3.new(worldPosition.X, 0, worldPosition.Z)
	local pathDirection = endPlanar - startPlanar
	if pathDirection.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		return nil
	end

	local projectedDistance = (currentPlanar - startPlanar):Dot(pathDirection.Unit)
	return math.clamp(projectedDistance / pathDirection.Magnitude, 0, 1)
end

function SlideController:_setMainProgressFlightOverride(isActive, ratio)
	local progressController = self._progressController
	if not (progressController and type(progressController.SetLocalFlightProgressOverride) == "function") then
		return
	end

	progressController:SetLocalFlightProgressOverride(isActive == true, ratio)
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

function SlideController:_getAnimationFadeTime(animationKey)
	local config = self:_getConfig()
	if animationKey == "slide" then
		return math.max(0, tonumber(config.SlideAnimationFadeTime) or 0)
	end

	return math.max(0, tonumber(config.AnimationFadeTime) or 0.15)
end

function SlideController:_getSlideAnimationId()
	return normalizeAssetId(self:_getConfig().SlideAnimationId or self:_getConfig().AnimationId)
end

function SlideController:_getLaunchAnimationId()
	return normalizeAssetId(self:_getConfig().LaunchAnimationId or self:_getConfig().AnimationId)
end

function SlideController:_getFallAnimationId()
	return normalizeAssetId(self:_getConfig().FallAnimationId or self:_getConfig().AnimationId)
end

function SlideController:_getLandingAnimationId()
	return normalizeAssetId(self:_getConfig().LandingAnimationId)
end

function SlideController:_getLandingRecoveryHorizontalSpeed()
	return math.max(0, tonumber(self:_getConfig().LandingRecoveryHorizontalSpeed) or DEFAULT_LANDING_RECOVERY_HORIZONTAL_SPEED)
end

function SlideController:_getLandingBurstConfig()
	local config = self:_getConfig()
	local landingBurstConfig = {
		enabled = config.LandingBurstEnabled ~= false,
		rootName = tostring(config.LandingBurstRootName or LANDING_BURST_ROOT_NAME),
		partCount = math.clamp(math.floor(tonumber(config.LandingBurstPartCount) or 14), 0, 28),
		lifetime = math.clamp(tonumber(config.LandingBurstLifetime) or 3.2, 0.2, 6),
		sizeMin = math.clamp(tonumber(config.LandingBurstMinSize) or 0.44, 0.05, 4),
		sizeMax = math.clamp(tonumber(config.LandingBurstMaxSize) or 1.4, 0.05, 4.5),
		radiusMin = math.clamp(tonumber(config.LandingBurstRadiusMin) or 1.05, 0, 10),
		radiusMax = math.clamp(tonumber(config.LandingBurstRadiusMax) or 6.6, 0, 16),
		spawnRadiusMin = math.clamp(tonumber(config.LandingBurstSpawnRadiusMin) or 0, 0, 2),
		spawnRadiusMax = math.clamp(tonumber(config.LandingBurstSpawnRadiusMax) or 0, 0, 3),
		launchAngleMinDegrees = math.clamp(tonumber(config.LandingBurstLaunchAngleMinDegrees) or 30, 5, 80),
		launchAngleMaxDegrees = math.clamp(tonumber(config.LandingBurstLaunchAngleMaxDegrees) or 45, 5, 85),
		forceMin = math.clamp(tonumber(config.LandingBurstForceMin) or 1.5, 0.1, 6),
		forceMax = math.clamp(tonumber(config.LandingBurstForceMax) or 2.2, 0.1, 8),
		collisionEnableDelay = math.clamp(tonumber(config.LandingBurstCollisionEnableDelay) or 0.12, 0, 1),
		fadeDelayRatioMin = math.clamp(tonumber(config.LandingBurstFadeDelayRatioMin) or 0.78, 0, 0.98),
		fadeDelayRatioMax = math.clamp(tonumber(config.LandingBurstFadeDelayRatioMax) or 0.9, 0, 0.99),
		color = typeof(config.LandingBurstColor) == "Color3" and config.LandingBurstColor or LANDING_BURST_COLOR,
	}

	if landingBurstConfig.rootName == "" then
		landingBurstConfig.rootName = LANDING_BURST_ROOT_NAME
	end

	landingBurstConfig.sizeMax = math.max(landingBurstConfig.sizeMin, landingBurstConfig.sizeMax)
	landingBurstConfig.radiusMax = math.max(landingBurstConfig.radiusMin, landingBurstConfig.radiusMax)
	landingBurstConfig.spawnRadiusMax = math.max(landingBurstConfig.spawnRadiusMin, landingBurstConfig.spawnRadiusMax)
	landingBurstConfig.launchAngleMaxDegrees = math.max(
		landingBurstConfig.launchAngleMinDegrees,
		landingBurstConfig.launchAngleMaxDegrees
	)
	landingBurstConfig.forceMax = math.max(landingBurstConfig.forceMin, landingBurstConfig.forceMax)
	landingBurstConfig.fadeDelayRatioMax = math.max(
		landingBurstConfig.fadeDelayRatioMin,
		landingBurstConfig.fadeDelayRatioMax
	)

	return landingBurstConfig
end

function SlideController:_getAirControlConfig()
	local config = self:_getConfig()
	return {
		enabled = config.AirControlEnabled ~= false,
		maxSpeed = math.clamp(tonumber(config.AirControlMaxSpeed) or 62, 0, 240),
		acceleration = math.clamp(tonumber(config.AirControlAcceleration) or 180, 0, 600),
		deceleration = math.clamp(tonumber(config.AirControlDeceleration) or 220, 0, 700),
		turnResponsiveness = math.clamp(tonumber(config.AirControlTurnResponsiveness) or 4.5, 0.1, 12),
		keyboardInfluence = math.clamp(tonumber(config.AirControlKeyboardInfluence) or 1, 0, 3),
		touchSensitivity = math.clamp(tonumber(config.AirControlTouchSensitivity) or 1.15, 0, 4),
		touchDeadzone = math.clamp(tonumber(config.AirControlTouchDeadzone) or 0.08, 0, 0.95),
		touchMaxDragPixels = math.clamp(tonumber(config.AirControlTouchMaxDragPixels) or 180, 16, 800),
		momentumBlend = math.clamp(tonumber(config.AirControlMomentumBlend) or 1, 0, 3),
		verticalLock = config.AirControlVerticalLock ~= false,
	}
end

function SlideController:_getLandingShakeConfig()
	local config = self:_getConfig()
	return {
		enabled = config.LandingShakeEnabled ~= false,
		duration = math.clamp(tonumber(config.LandingShakeDuration) or 0.38, 0.05, 2),
		frequency = math.clamp(tonumber(config.LandingShakeFrequency) or 17, 0.1, 60),
		damping = math.clamp(tonumber(config.LandingShakeDamping) or 8, 0, 40),
		amplitude = Vector3.new(
			math.clamp(tonumber(config.LandingShakeAmplitudeX) or 0.42, 0, 5),
			math.clamp(tonumber(config.LandingShakeAmplitudeY) or 0.28, 0, 5),
			math.clamp(tonumber(config.LandingShakeAmplitudeZ) or 0.58, 0, 5)
		),
	}
end

function SlideController:_getFastLandFallSpeed()
	local config = self:_getConfig()
	return math.clamp(tonumber(config.FastLandFallSpeed) or 900, 24, 2000)
end

function SlideController:_getCurrentLaunchBaseHorizontalVelocity(rootPart)
	local launchMomentumVelocity = flattenVector(self._launchMomentumVelocity or Vector3.zero)
	if launchMomentumVelocity.Magnitude > MIN_DIRECTION_MAGNITUDE then
		return launchMomentumVelocity
	end

	if self._bulletTimeBaselineTrajectoryVelocity then
		local baselineHorizontalVelocity = flattenVector(self._bulletTimeBaselineTrajectoryVelocity)
		if baselineHorizontalVelocity.Magnitude > MIN_DIRECTION_MAGNITUDE then
			return baselineHorizontalVelocity
		end
	end

	if rootPart and rootPart.Parent then
		local currentHorizontalVelocity = flattenVector(rootPart.AssemblyLinearVelocity)
		if currentHorizontalVelocity.Magnitude > MIN_DIRECTION_MAGNITUDE then
			return currentHorizontalVelocity
		end

		local lookHorizontalVelocity = flattenVector(rootPart.CFrame.LookVector)
		if lookHorizontalVelocity.Magnitude > MIN_DIRECTION_MAGNITUDE then
			return lookHorizontalVelocity.Unit
		end
	end

	return Vector3.zero
end

function SlideController:_getLaunchTrajectoryPlanarBasis(rootPart)
	local forwardDirection = self:_getCurrentLaunchBaseHorizontalVelocity(rootPart)
	if forwardDirection.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		return nil, nil
	end

	forwardDirection = forwardDirection.Unit
	local rightDirection = Vector3.new(-forwardDirection.Z, 0, forwardDirection.X)
	if rightDirection.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		return nil, nil
	end

	return forwardDirection, rightDirection.Unit
end

function SlideController:_getFlyLateralAdjustmentVelocity()
	if self._flyLateralVelocity.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		return Vector3.zero
	end

	local airControlConfig = self:_getAirControlConfig()
	return self._flyLateralVelocity * airControlConfig.momentumBlend
end

function SlideController:_getBulletTimeScaledBaseTrajectoryVelocity(rootPart)
	local baselineTrajectoryVelocity = self._bulletTimeBaselineTrajectoryVelocity
	if not baselineTrajectoryVelocity then
		local baseHorizontalVelocity = self:_getCurrentLaunchBaseHorizontalVelocity(rootPart)
		if baseHorizontalVelocity.Magnitude <= MIN_DIRECTION_MAGNITUDE and not (rootPart and rootPart.Parent) then
			return nil
		end

		local verticalVelocity = rootPart and rootPart.AssemblyLinearVelocity.Y or 0
		baselineTrajectoryVelocity = Vector3.new(baseHorizontalVelocity.X, verticalVelocity, baseHorizontalVelocity.Z)
	end

	local fallSpeed = self:_getBulletTimeFallSpeed()
	local verticalMagnitude = math.abs(baselineTrajectoryVelocity.Y)
	local ratio = 1
	if fallSpeed > 0 and verticalMagnitude > MIN_DIRECTION_MAGNITUDE then
		ratio = math.min(1, fallSpeed / verticalMagnitude)
	end

	return baselineTrajectoryVelocity * ratio
end

function SlideController:_getLandingBurstOrigin(rootPart)
	local fallbackImpactPosition = rootPart.Position - Vector3.new(0, self:_getRaycastStartOffsetY(), 0)
	local raycastResult = self:_raycastGround(rootPart)
	if raycastResult then
		fallbackImpactPosition = raycastResult.Position
	end

	local character = self._character
	if not character then
		return fallbackImpactPosition
	end

	local footPartNames = { "LeftFoot", "RightFoot", "Left Leg", "Right Leg", "LeftLowerLeg", "RightLowerLeg" }
	local footCenter = Vector3.zero
	local footPartCount = 0
	for _, footPartName in ipairs(footPartNames) do
		local footPart = character:FindFirstChild(footPartName)
		if footPart and footPart:IsA("BasePart") then
			footCenter += footPart.Position
			footPartCount += 1
		end
	end

	if footPartCount <= 0 then
		return fallbackImpactPosition
	end

	footCenter /= footPartCount

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = self:_getGroundRaycastExcludeInstances()
	raycastParams.IgnoreWater = true

	local rayOrigin = Vector3.new(
		footCenter.X,
		math.max(rootPart.Position.Y, footCenter.Y) + self:_getRaycastStartOffsetY(),
		footCenter.Z
	)
	local footGroundResult = Workspace:Raycast(
		rayOrigin,
		Vector3.new(0, -self:_getRaycastLength(), 0),
		raycastParams
	)
	if footGroundResult then
		return footGroundResult.Position
	end

	return Vector3.new(footCenter.X, fallbackImpactPosition.Y, footCenter.Z)
end

function SlideController:_playLandingBurst(rootPart)
	if not (rootPart and rootPart.Parent) then
		return
	end

	local config = self:_getLandingBurstConfig()
	if not config.enabled or config.partCount <= 0 or config.lifetime <= 0 then
		return
	end

	local burstRoot = Workspace:FindFirstChild(config.rootName)
	if burstRoot and not burstRoot:IsA("Folder") then
		burstRoot = nil
	end
	if not burstRoot then
		burstRoot = Instance.new("Folder")
		burstRoot.Name = config.rootName
		burstRoot.Parent = Workspace
	end

	local randomizer = Random.new()
	local burstOrigin = self:_getLandingBurstOrigin(rootPart)

	local characterParts = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local characterRoot = character and character:FindFirstChild("HumanoidRootPart")
		if characterRoot and (characterRoot.Position - burstOrigin).Magnitude <= 48 then
			for _, descendant in ipairs(character:GetDescendants()) do
				if descendant:IsA("BasePart") then
					table.insert(characterParts, descendant)
				end
			end
		end
	end

	local gravity = math.max(0.1, Workspace.Gravity)
	for partIndex = 1, config.partCount do
		local sizeValue = randomizer:NextNumber(config.sizeMin, config.sizeMax)
		local angle = (((partIndex - 1) / config.partCount) * math.pi * 2) + randomizer:NextNumber(-0.24, 0.24)
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		if direction.Magnitude <= MIN_DIRECTION_MAGNITUDE then
			direction = Vector3.xAxis
		else
			direction = direction.Unit
		end

		local spawnOffset = direction * randomizer:NextNumber(config.spawnRadiusMin, config.spawnRadiusMax)
		local spawnHeight = (sizeValue * 0.5) + randomizer:NextNumber(0.02, 0.08)
		local spawnPosition = burstOrigin + spawnOffset + Vector3.new(0, spawnHeight, 0)
		local burstPart = Instance.new("Part")
		burstPart.Name = "LandingBurstChunk"
		burstPart.Size = Vector3.new(sizeValue, sizeValue, sizeValue)
		burstPart.Color = config.color
		burstPart.Material = Enum.Material.SmoothPlastic
		burstPart.Anchored = false
		burstPart.CanCollide = false
		burstPart.CanTouch = false
		burstPart.CanQuery = false
		burstPart.CastShadow = false
		burstPart.Massless = false
		burstPart.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.22, 0.02, 1, 1)
		burstPart.TopSurface = Enum.SurfaceType.Smooth
		burstPart.BottomSurface = Enum.SurfaceType.Smooth
		burstPart.CFrame = CFrame.new(spawnPosition) * CFrame.Angles(
			math.rad(randomizer:NextNumber(-30, 30)),
			math.rad(randomizer:NextNumber(-180, 180)),
			math.rad(randomizer:NextNumber(-30, 30))
		)
		burstPart.Parent = burstRoot

		for _, characterPart in ipairs(characterParts) do
			if characterPart.Parent then
				local noCollisionConstraint = Instance.new("NoCollisionConstraint")
				noCollisionConstraint.Name = "LandingBurstNoCollision"
				noCollisionConstraint.Part0 = burstPart
				noCollisionConstraint.Part1 = characterPart
				noCollisionConstraint.Parent = burstPart
			end
		end

		local launchAngleDegrees = randomizer:NextNumber(
			config.launchAngleMinDegrees,
			config.launchAngleMaxDegrees
		)
		local launchAngleRadians = math.rad(launchAngleDegrees)
		local targetDistance = randomizer:NextNumber(config.radiusMin, config.radiusMax)
		local denominator = math.max(0.08, math.sin(2 * launchAngleRadians))
		local baseLaunchSpeed = math.sqrt((targetDistance * gravity) / denominator)
		local launchForce = randomizer:NextNumber(config.forceMin, config.forceMax)
		local launchSpeed = baseLaunchSpeed * launchForce
		local horizontalSpeed = launchSpeed * math.cos(launchAngleRadians)
		local verticalSpeed = launchSpeed * math.sin(launchAngleRadians)

		burstPart.AssemblyLinearVelocity = (direction * horizontalSpeed) + Vector3.new(0, verticalSpeed, 0)
		burstPart.AssemblyAngularVelocity = Vector3.new(
			randomizer:NextNumber(-6, 6),
			randomizer:NextNumber(-7, 7),
			randomizer:NextNumber(-6, 6)
		)

		task.delay(config.collisionEnableDelay, function()
			if burstPart and burstPart.Parent then
				burstPart.CanCollide = true
			end
		end)

		local fadeDelay = config.lifetime * randomizer:NextNumber(
			config.fadeDelayRatioMin,
			config.fadeDelayRatioMax
		)
		local finalSizeValue = math.max(0.08, sizeValue * randomizer:NextNumber(0.92, 1.0))
		task.delay(fadeDelay, function()
			if burstPart and burstPart.Parent then
				playTween(burstPart, math.max(0.15, config.lifetime - fadeDelay), {
					Transparency = 1,
					Size = Vector3.new(finalSizeValue, finalSizeValue, finalSizeValue),
				})
			end
		end)
		task.delay(config.lifetime + 0.12, function()
			if burstPart then
				burstPart:Destroy()
			end
		end)
	end
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

function SlideController:_recordStudioLaunchDebug(targetVelocity, effectiveLaunchPower, slideSpeedAtLaunch)
	if not RunService:IsStudio() then
		return
	end

	if not localPlayer or typeof(targetVelocity) ~= "Vector3" then
		return
	end

	local horizontalSpeed = Vector3.new(targetVelocity.X, 0, targetVelocity.Z).Magnitude
	local verticalSpeed = targetVelocity.Y
	local totalSpeed = targetVelocity.Magnitude

	localPlayer:SetAttribute(STUDIO_DEBUG_LAST_LAUNCH_HORIZONTAL_SPEED_ATTRIBUTE, horizontalSpeed)
	localPlayer:SetAttribute(STUDIO_DEBUG_LAST_LAUNCH_VERTICAL_SPEED_ATTRIBUTE, verticalSpeed)
	localPlayer:SetAttribute(STUDIO_DEBUG_LAST_LAUNCH_TOTAL_SPEED_ATTRIBUTE, totalSpeed)
	localPlayer:SetAttribute(
		STUDIO_DEBUG_LAST_LAUNCH_POWER_USED_ATTRIBUTE,
		math.max(0, tonumber(effectiveLaunchPower) or 0)
	)
	localPlayer:SetAttribute(
		STUDIO_DEBUG_LAST_LAUNCH_SLIDE_SPEED_ATTRIBUTE,
		math.max(0, tonumber(slideSpeedAtLaunch) or 0)
	)
end
function SlideController:_getPlayerGui()
	return localPlayer:FindFirstChildOfClass("PlayerGui")
end

function SlideController:_getMainGui()
	local playerGui = self:_getPlayerGui()
	if not playerGui then
		return nil
	end

	local mainGui = playerGui:FindFirstChild("Main") or playerGui:FindFirstChild("Main", true)
	if mainGui and mainGui:IsA("LayerCollector") then
		return mainGui
	end

	return nil
end

function SlideController:_setMainGuiVisibleExceptFlyButton(isVisible)
	local shouldShow = isVisible == true
	if shouldShow then
		for guiObject, wasVisible in pairs(self._hiddenMainGuiStates) do
			if guiObject and guiObject.Parent and guiObject:IsA("GuiObject") then
				guiObject.Visible = wasVisible == true
			end
		end
		self._hiddenMainGuiStates = {}
		return
	end

	self._hiddenMainGuiStates = {}

	local mainGui = self:_getMainGui()
	if not mainGui then
		return
	end

	for _, guiObject in ipairs(mainGui:GetChildren()) do
		if guiObject:IsA("GuiObject")
			and guiObject.Name ~= "FlyButton"
			and guiObject.Name ~= "Progress" then
			self._hiddenMainGuiStates[guiObject] = guiObject.Visible == true
			if guiObject.Visible then
				guiObject.Visible = false
			end
		end
	end
end

function SlideController:_setPlayerGuiVisible(isVisible)
	local shouldShow = isVisible == true
	if shouldShow then
		self:_setMainGuiVisibleExceptFlyButton(true)
		for guiObject, wasEnabled in pairs(self._hiddenPlayerGuiStates) do
			if guiObject and guiObject.Parent then
				setGuiEnabled(guiObject, wasEnabled == true)
			end
		end
		self._hiddenPlayerGuiStates = {}
		return
	end

	self._hiddenPlayerGuiStates = {}

	local playerGui = self:_getPlayerGui()
	if not playerGui then
		return
	end

	local mainGui = self:_getMainGui()
	self:_setMainGuiVisibleExceptFlyButton(false)

	for _, guiObject in ipairs(playerGui:GetChildren()) do
		if guiObject:IsA("LayerCollector") and guiObject ~= mainGui then
			local isEnabled = false
			local success = pcall(function()
				isEnabled = guiObject.Enabled
			end)
			if success then
				self._hiddenPlayerGuiStates[guiObject] = isEnabled
				if isEnabled then
					setGuiEnabled(guiObject, false)
				end
			end
		end
	end
end

function SlideController:_setCoreGuiVisible(isVisible)
	local shouldShow = isVisible == true
	if shouldShow then
		for coreGuiName, wasEnabled in pairs(self._hiddenCoreGuiStates) do
			local coreGuiType = Enum.CoreGuiType[coreGuiName]
			if coreGuiType then
				pcall(function()
					StarterGui:SetCoreGuiEnabled(coreGuiType, wasEnabled == true)
				end)
			end
		end
		self._hiddenCoreGuiStates = {}
		return
	end

	self._hiddenCoreGuiStates = {}

	for _, coreGuiName in ipairs(HIDDEN_CORE_GUI_TYPE_NAMES) do
		local coreGuiType = Enum.CoreGuiType[coreGuiName]
		if coreGuiType then
			local isEnabled = true
			local success = pcall(function()
				isEnabled = StarterGui:GetCoreGuiEnabled(coreGuiType)
			end)
			if success then
				self._hiddenCoreGuiStates[coreGuiName] = isEnabled
				pcall(function()
					StarterGui:SetCoreGuiEnabled(coreGuiType, false)
				end)
			end
		end
	end
end

function SlideController:_setGameplayUiHidden(isHidden)
	local shouldHide = isHidden == true
	if self._isGameplayUiHidden == shouldHide then
		return
	end

	self._isGameplayUiHidden = shouldHide
	self:_setPlayerGuiVisible(not shouldHide)
	self:_setCoreGuiVisible(not shouldHide)
end

function SlideController:_resolveBulletTimeFxNodes()
	local bulletTimeFxRoot = self._bulletTimeFxRoot
	local bulletTimeFxImage = self._bulletTimeFxImage
	local bulletTimeFxOuterImage = self._bulletTimeFxOuterImage
	if bulletTimeFxRoot and bulletTimeFxRoot.Parent
		and bulletTimeFxImage and bulletTimeFxImage.Parent
		and bulletTimeFxOuterImage and bulletTimeFxOuterImage.Parent then
		return bulletTimeFxRoot, bulletTimeFxImage, bulletTimeFxOuterImage
	end

	local mainGui = self:_getMainGui()
	if not mainGui then
		return nil, nil, nil
	end

	bulletTimeFxRoot = mainGui:FindFirstChild(BULLET_TIME_FX_ROOT_NAME)
	if bulletTimeFxRoot and not bulletTimeFxRoot:IsA("Frame") then
		bulletTimeFxRoot:Destroy()
		bulletTimeFxRoot = nil
	end
	if not bulletTimeFxRoot then
		bulletTimeFxRoot = Instance.new("Frame")
		bulletTimeFxRoot.Name = BULLET_TIME_FX_ROOT_NAME
		bulletTimeFxRoot.BackgroundTransparency = 1
		bulletTimeFxRoot.BorderSizePixel = 0
		bulletTimeFxRoot.Size = UDim2.fromScale(1, 1)
		bulletTimeFxRoot.Active = false
		bulletTimeFxRoot.ClipsDescendants = false
		bulletTimeFxRoot.Visible = false
		bulletTimeFxRoot.Parent = mainGui
	end

	bulletTimeFxOuterImage = bulletTimeFxRoot:FindFirstChild(BULLET_TIME_FX_OUTER_IMAGE_NAME)
	if bulletTimeFxOuterImage and not bulletTimeFxOuterImage:IsA("ImageLabel") then
		bulletTimeFxOuterImage:Destroy()
		bulletTimeFxOuterImage = nil
	end
	if not bulletTimeFxOuterImage then
		bulletTimeFxOuterImage = Instance.new("ImageLabel")
		bulletTimeFxOuterImage.Name = BULLET_TIME_FX_OUTER_IMAGE_NAME
		bulletTimeFxOuterImage.AnchorPoint = Vector2.new(0.5, 0.5)
		bulletTimeFxOuterImage.Position = UDim2.fromScale(0.5, 0.5)
		bulletTimeFxOuterImage.Size = BULLET_TIME_FX_OUTER_IDLE_SIZE
		bulletTimeFxOuterImage.BackgroundTransparency = 1
		bulletTimeFxOuterImage.BorderSizePixel = 0
		bulletTimeFxOuterImage.Active = false
		bulletTimeFxOuterImage.Image = BULLET_TIME_FX_IMAGE_ASSET
		bulletTimeFxOuterImage.ImageColor3 = BULLET_TIME_FX_IMAGE_COLOR
		bulletTimeFxOuterImage.ImageTransparency = BULLET_TIME_FX_HIDDEN_TRANSPARENCY
		bulletTimeFxOuterImage.ScaleType = Enum.ScaleType.Stretch
		bulletTimeFxOuterImage.ZIndex = 0
		bulletTimeFxOuterImage.Parent = bulletTimeFxRoot
	end

	bulletTimeFxImage = bulletTimeFxRoot:FindFirstChild(BULLET_TIME_FX_IMAGE_NAME)
	if bulletTimeFxImage and not bulletTimeFxImage:IsA("ImageLabel") then
		bulletTimeFxImage:Destroy()
		bulletTimeFxImage = nil
	end
	if not bulletTimeFxImage then
		bulletTimeFxImage = Instance.new("ImageLabel")
		bulletTimeFxImage.Name = BULLET_TIME_FX_IMAGE_NAME
		bulletTimeFxImage.AnchorPoint = Vector2.new(0.5, 0.5)
		bulletTimeFxImage.Position = UDim2.fromScale(0.5, 0.5)
		bulletTimeFxImage.Size = BULLET_TIME_FX_IDLE_SIZE
		bulletTimeFxImage.BackgroundTransparency = 1
		bulletTimeFxImage.BorderSizePixel = 0
		bulletTimeFxImage.Active = false
		bulletTimeFxImage.Image = BULLET_TIME_FX_IMAGE_ASSET
		bulletTimeFxImage.ImageColor3 = BULLET_TIME_FX_IMAGE_COLOR
		bulletTimeFxImage.ImageTransparency = BULLET_TIME_FX_HIDDEN_TRANSPARENCY
		bulletTimeFxImage.ScaleType = Enum.ScaleType.Stretch
		bulletTimeFxImage.ZIndex = 0
		bulletTimeFxImage.Parent = bulletTimeFxRoot
	end

	self._bulletTimeFxRoot = bulletTimeFxRoot
	self._bulletTimeFxImage = bulletTimeFxImage
	self._bulletTimeFxOuterImage = bulletTimeFxOuterImage
	return bulletTimeFxRoot, bulletTimeFxImage, bulletTimeFxOuterImage
end

function SlideController:_resolveBulletTimePostEffects()
	local colorCorrection = self._bulletTimeColorCorrection
	if not (colorCorrection and colorCorrection.Parent == Lighting) then
		colorCorrection = Lighting:FindFirstChild(BULLET_TIME_COLOR_CORRECTION_NAME)
		if colorCorrection and not colorCorrection:IsA("ColorCorrectionEffect") then
			colorCorrection:Destroy()
			colorCorrection = nil
		end
		if not colorCorrection then
			colorCorrection = Instance.new("ColorCorrectionEffect")
			colorCorrection.Name = BULLET_TIME_COLOR_CORRECTION_NAME
			colorCorrection.Contrast = 0
			colorCorrection.Saturation = 0
			colorCorrection.TintColor = Color3.new(1, 1, 1)
			colorCorrection.Parent = Lighting
		end
		self._bulletTimeColorCorrection = colorCorrection
	end

	local blurEffect = self._bulletTimeBlur
	if not (blurEffect and blurEffect.Parent == Lighting) then
		blurEffect = Lighting:FindFirstChild(BULLET_TIME_BLUR_NAME)
		if blurEffect and not blurEffect:IsA("BlurEffect") then
			blurEffect:Destroy()
			blurEffect = nil
		end
		if not blurEffect then
			blurEffect = Instance.new("BlurEffect")
			blurEffect.Name = BULLET_TIME_BLUR_NAME
			blurEffect.Size = 0
			blurEffect.Parent = Lighting
		end
		self._bulletTimeBlur = blurEffect
	end

	return colorCorrection, blurEffect
end

function SlideController:_setBulletTimeFxActive(isActive)
	local duration = isActive and BULLET_TIME_FX_FADE_IN_TIME or BULLET_TIME_FX_FADE_OUT_TIME
	local bulletTimeFxRoot, bulletTimeFxImage, bulletTimeFxOuterImage = self:_resolveBulletTimeFxNodes()
	local colorCorrection, blurEffect = self:_resolveBulletTimePostEffects()

	if bulletTimeFxImage then
		bulletTimeFxImage.ImageTransparency = BULLET_TIME_FX_HIDDEN_TRANSPARENCY
		bulletTimeFxImage.Size = BULLET_TIME_FX_IDLE_SIZE
	end
	if bulletTimeFxOuterImage then
		bulletTimeFxOuterImage.ImageTransparency = BULLET_TIME_FX_HIDDEN_TRANSPARENCY
		bulletTimeFxOuterImage.Size = BULLET_TIME_FX_OUTER_IDLE_SIZE
	end
	if bulletTimeFxRoot then
		bulletTimeFxRoot.Visible = false
	end

	if colorCorrection then
		colorCorrection.Contrast = 0
		colorCorrection.Saturation = 0
		colorCorrection.TintColor = Color3.new(1, 1, 1)
	end
	if blurEffect then
		blurEffect.Size = 0
	end

	local currentCamera = Workspace.CurrentCamera
	if currentCamera then
		if isActive then
			if self._bulletTimeBaseFieldOfView == nil then
				self._bulletTimeBaseFieldOfView = currentCamera.FieldOfView
			end
			playTween(currentCamera, duration, {
				FieldOfView = math.max(1, self._bulletTimeBaseFieldOfView + BULLET_TIME_FOV_OFFSET),
			})
		else
			local baseFieldOfView = self._bulletTimeBaseFieldOfView
			self._bulletTimeBaseFieldOfView = nil
			if baseFieldOfView ~= nil then
				playTween(currentCamera, duration, {
					FieldOfView = baseFieldOfView,
				})
			end
		end
	elseif not isActive then
		self._bulletTimeBaseFieldOfView = nil
	end
end

function SlideController:_stopLandingShake()
	pcall(function()
		RunService:UnbindFromRenderStep(LANDING_SHAKE_RENDERSTEP_NAME)
	end)
end

function SlideController:_playLandingShake()
	self:_stopLandingShake()

	local config = self:_getLandingShakeConfig()
	if not config.enabled or config.duration <= 0 then
		return
	end

	if config.amplitude.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		return
	end

	local startedAt = os.clock()
	RunService:BindToRenderStep(LANDING_SHAKE_RENDERSTEP_NAME, Enum.RenderPriority.Camera.Value + 1, function()
		local currentCamera = Workspace.CurrentCamera
		if not currentCamera then
			return
		end

		local elapsed = os.clock() - startedAt
		if elapsed >= config.duration then
			self:_stopLandingShake()
			return
		end

		local waveTime = elapsed * config.frequency * math.pi * 2
		local damping = math.exp(-config.damping * elapsed)
		local offset = Vector3.new(
			math.sin(waveTime) * config.amplitude.X,
			math.sin((waveTime * 1.31) + 0.8) * config.amplitude.Y,
			math.sin((waveTime * 1.73) + 1.6) * config.amplitude.Z
		) * damping

		currentCamera.CFrame = currentCamera.CFrame * CFrame.new(offset)
	end)
end

function SlideController:_resolveFlyProgressNodes()
	local flyProgressRoot = self._flyProgressRoot
	local flyProgressBar = self._flyProgressBar
	if flyProgressRoot and flyProgressRoot.Parent and flyProgressBar and flyProgressBar.Parent then
		return flyProgressRoot, flyProgressBar
	end

	local playerGui = self:_getPlayerGui()
	if not playerGui then
		return nil, nil
	end

	local mainGui = playerGui:FindFirstChild("Main") or playerGui:FindFirstChild("Main", true)
	if not (mainGui and mainGui:IsA("LayerCollector")) then
		return nil, nil
	end

	flyProgressRoot = mainGui:FindFirstChild("FlyProgress") or mainGui:FindFirstChild("FlyProgress", true)
	if not (flyProgressRoot and flyProgressRoot:IsA("GuiObject")) then
		return nil, nil
	end

	flyProgressBar = flyProgressRoot:FindFirstChild("Bar") or flyProgressRoot:FindFirstChild("Bar", true)
	if not (flyProgressBar and flyProgressBar:IsA("GuiObject")) then
		return nil, nil
	end

	self._flyProgressRoot = flyProgressRoot
	self._flyProgressBar = flyProgressBar
	self._flyProgressBarBaseSize = flyProgressBar.Size
	return flyProgressRoot, flyProgressBar
end

function SlideController:_updateFlyProgressBar(progress)
	local _flyProgressRoot, flyProgressBar = self:_resolveFlyProgressNodes()
	if not flyProgressBar then
		return
	end

	local baseSize = self._flyProgressBarBaseSize or flyProgressBar.Size
	self._flyProgressBarBaseSize = baseSize
	flyProgressBar.Size = UDim2.new(
		math.clamp(tonumber(progress) or 0, 0, 1),
		0,
		baseSize.Y.Scale,
		baseSize.Y.Offset
	)
end

function SlideController:_setFlyProgressVisible(isVisible)
	local flyProgressRoot, flyProgressBar = self:_resolveFlyProgressNodes()
	if not flyProgressRoot then
		return
	end

	flyProgressRoot.Visible = isVisible == true
	if not isVisible and flyProgressBar then
		local baseSize = self._flyProgressBarBaseSize or flyProgressBar.Size
		self._flyProgressBarBaseSize = baseSize
		flyProgressBar.Size = baseSize
	end
end

function SlideController:_resolveFlyButtonNodes()
	local flyButtonRoot = self._flyButtonRoot
	local holdButton = self._flyHoldButton
	local leftButton = self._flyLeftButton
	local rightButton = self._flyRightButton
	local landButton = self._flyLandButton
	if flyButtonRoot and flyButtonRoot.Parent
		and leftButton and leftButton.Parent
		and rightButton and rightButton.Parent
		and ((not holdButton) or holdButton.Parent)
		and ((not landButton) or landButton.Parent) then
		return flyButtonRoot, holdButton, leftButton, rightButton, landButton
	end

	local playerGui = self:_getPlayerGui()
	if not playerGui then
		return nil, nil, nil, nil, nil
	end

	local mainGui = playerGui:FindFirstChild("Main") or playerGui:FindFirstChild("Main", true)
	if not (mainGui and mainGui:IsA("LayerCollector")) then
		return nil, nil, nil, nil, nil
	end

	flyButtonRoot = mainGui:FindFirstChild("FlyButton") or mainGui:FindFirstChild("FlyButton", true)
	if not (flyButtonRoot and flyButtonRoot:IsA("GuiObject")) then
		return nil, nil, nil, nil, nil
	end

	holdButton = flyButtonRoot:FindFirstChild("Hold") or flyButtonRoot:FindFirstChild("Hold", true)
	leftButton = flyButtonRoot:FindFirstChild("Left") or flyButtonRoot:FindFirstChild("Left", true)
	rightButton = flyButtonRoot:FindFirstChild("Right") or flyButtonRoot:FindFirstChild("Right", true)
	landButton = flyButtonRoot:FindFirstChild("Land") or flyButtonRoot:FindFirstChild("Land", true)
	if holdButton and not holdButton:IsA("GuiButton") then
		holdButton = nil
	end
	if not (leftButton and leftButton:IsA("GuiButton")) then
		return nil, nil, nil, nil, nil
	end
	if not (rightButton and rightButton:IsA("GuiButton")) then
		return nil, nil, nil, nil, nil
	end
	if landButton and not landButton:IsA("GuiButton") then
		landButton = nil
	end

	self._flyButtonRoot = flyButtonRoot
	self._flyHoldButton = holdButton
	self._flyLeftButton = leftButton
	self._flyRightButton = rightButton
	self._flyLandButton = landButton
	return flyButtonRoot, holdButton, leftButton, rightButton, landButton
end

function SlideController:_resolveFlyButtonTipsRoot()
	local flyButtonRoot = self._flyButtonRoot
	local tipsRoot = self._flyTipsRoot
	if tipsRoot and tipsRoot.Parent and flyButtonRoot and flyButtonRoot.Parent and tipsRoot:IsDescendantOf(flyButtonRoot) then
		return tipsRoot
	end

	if not (flyButtonRoot and flyButtonRoot.Parent) then
		self._flyTipsRoot = nil
		return nil
	end

	tipsRoot = flyButtonRoot:FindFirstChild("Tips") or flyButtonRoot:FindFirstChild("Tips", true)
	if tipsRoot and tipsRoot:IsA("GuiObject") then
		self._flyTipsRoot = tipsRoot
		return tipsRoot
	end

	self._flyTipsRoot = nil
	return nil
end

function SlideController:_refreshFlyButtonTipsContent()
	local tipsRoot = self:_resolveFlyButtonTipsRoot()
	if not tipsRoot then
		return
	end

	for _, descendant in ipairs(tipsRoot:GetDescendants()) do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
			local normalizedText = string.lower((tostring(descendant.Text or ""):gsub("%s+", "")))
			local shouldHide = normalizedText == "space" or normalizedText == "slowdown"
			descendant.Visible = not shouldHide
		end
	end
end

function SlideController:_shouldUseMobileFlyButtonLayout()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function SlideController:_applyFlyButtonPlatformVisibility()
	local flyButtonRoot, holdButton, leftButton, rightButton, landButton = self:_resolveFlyButtonNodes()
	if not flyButtonRoot then
		return
	end

	local showTouchButtons = self:_shouldUseMobileFlyButtonLayout()
	if holdButton then
		holdButton.Visible = false
	end
	if leftButton then
		leftButton.Visible = showTouchButtons
	end
	if rightButton then
		rightButton.Visible = showTouchButtons
	end
	if landButton then
		landButton.Visible = true
	end

	local tipsRoot = self:_resolveFlyButtonTipsRoot()
	if tipsRoot then
		self:_refreshFlyButtonTipsContent()
		tipsRoot.Visible = not showTouchButtons
	end
end

function SlideController:_clearFlyButtonInputState()
	self._flyLeftPressed = false
	self._flyRightPressed = false
	self._flyLateralVelocity = Vector3.zero
	self._flyControlVelocity = Vector3.zero
	self._flyTouchInput = Vector2.zero
	self._flyTouchDragInputObject = nil
	self._flyTouchDragStartPosition = nil
	self._flyTouchDragPosition = nil
end

function SlideController:_clearFlyButtonBindings()
	disconnectAll(self._flyUiConnections)
	self._flyUiConnections = {}
	self._flyButtonRoot = nil
	self._flyHoldButton = nil
	self._flyLeftButton = nil
	self._flyRightButton = nil
	self._flyLandButton = nil
	self._flyTipsRoot = nil
	self:_clearFlyButtonInputState()
end

function SlideController:_bindFlyButtonState(button, onPressedChanged)
	if not (button and onPressedChanged) then
		return
	end

	table.insert(self._flyUiConnections, button.InputBegan:Connect(function(inputObject)
		if isPressInput(inputObject) then
			onPressedChanged(true)
		end
	end))

	table.insert(self._flyUiConnections, button.InputEnded:Connect(function(inputObject)
		if isPressInput(inputObject) then
			onPressedChanged(false)
		end
	end))

	table.insert(self._flyUiConnections, button.MouseLeave:Connect(function()
		onPressedChanged(false)
	end))
end

function SlideController:_ensureFlyButtonBindings()
	local previousRoot = self._flyButtonRoot
	local previousHoldButton = self._flyHoldButton
	local previousLeftButton = self._flyLeftButton
	local previousRightButton = self._flyRightButton
	local previousLandButton = self._flyLandButton
	local flyButtonRoot, holdButton, leftButton, rightButton, landButton = self:_resolveFlyButtonNodes()
	if not (flyButtonRoot and leftButton and rightButton) then
		return nil, nil, nil, nil, nil
	end

	local needsRebind = #self._flyUiConnections <= 0
		or previousRoot ~= flyButtonRoot
		or previousHoldButton ~= holdButton
		or previousLeftButton ~= leftButton
		or previousRightButton ~= rightButton
		or previousLandButton ~= landButton
	if not needsRebind then
		return flyButtonRoot, holdButton, leftButton, rightButton, landButton
	end

	disconnectAll(self._flyUiConnections)
	self._flyUiConnections = {}

	self:_bindFlyButtonState(leftButton, function(isPressed)
		self._flyLeftPressed = isPressed == true
	end)
	self:_bindFlyButtonState(rightButton, function(isPressed)
		self._flyRightPressed = isPressed == true
	end)
	if landButton then
		table.insert(self._flyUiConnections, landButton.Activated:Connect(function()
			self:_triggerFastLanding()
		end))
	end

	flyButtonRoot.Visible = false
	self:_applyFlyButtonPlatformVisibility()
	return flyButtonRoot, holdButton, leftButton, rightButton, landButton
end

function SlideController:_setFlyButtonVisible(isVisible)
	local flyButtonRoot = select(1, self:_resolveFlyButtonNodes()) or self._flyButtonRoot
	if not flyButtonRoot then
		return
	end

	self:_applyFlyButtonPlatformVisibility()
	flyButtonRoot.Visible = isVisible == true
end

function SlideController:_applyFastLandingVelocity(rootPart, deltaTime)
	if not (rootPart and rootPart.Parent) then
		return false
	end

	local targetFallSpeed = self:_getFastLandFallSpeed()
	local groundDistance = self:_getGroundDistance(rootPart)
	if groundDistance then
		local safeTravelDistance = math.max(0, groundDistance - FAST_LANDING_GROUND_BUFFER)
		local effectiveDeltaTime = math.max(1 / 240, tonumber(deltaTime) or FAST_LANDING_FALLBACK_DELTA_TIME)
		targetFallSpeed = math.min(targetFallSpeed, safeTravelDistance / effectiveDeltaTime)
	end

	local currentVelocity = rootPart.AssemblyLinearVelocity
	rootPart.AssemblyLinearVelocity = Vector3.new(
		0,
		(targetFallSpeed <= MIN_DIRECTION_MAGNITUDE) and 0 or math.min(currentVelocity.Y, -targetFallSpeed),
		0
	)
	return true
end

function SlideController:_startFastLanding(humanoid, rootPart)
	local hasTakeoffWindow = self._launchNoGravityEndTime > os.clock()
	if self._isFastLandingActive or not (self._isLaunchFlightActive or hasTakeoffWindow) then
		return false
	end
	if not (humanoid and rootPart and rootPart.Parent) then
		return false
	end
	if not self._isLaunchFlightActive then
		self:_startLaunchFlight(rootPart)
	end

	self._isFastLandingActive = true
	self:_stopLaunchNoGravity()
	self:_stopBulletTime(rootPart, false)
	self:_clearFlyButtonInputState()
	self:_clearLaunchMomentum()
	self:_setFlyButtonVisible(false)
	self:_setGameplayUiHidden(true)
	self:_applyFastLandingVelocity(rootPart, FAST_LANDING_FALLBACK_DELTA_TIME)

	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end)

	return true
end

function SlideController:_triggerFastLanding()
	return self:_startFastLanding(self._humanoid, self._humanoidRootPart)
end

function SlideController:_recomputeFlyKeyboardInput()
	local inputVector = Vector2.zero
	for keyCode, axisVector in pairs(AIR_CONTROL_KEYCODES) do
		if self._flyKeyboardState[keyCode] then
			inputVector += axisVector
		end
	end

	self._flyKeyboardInput = clampVector2Magnitude(inputVector, 1)
end

function SlideController:_setFlyKeyPressed(keyCode, isPressed)
	if not AIR_CONTROL_KEYCODES[keyCode] then
		return
	end

	if isPressed then
		self._flyKeyboardState[keyCode] = true
	else
		self._flyKeyboardState[keyCode] = nil
	end

	self:_recomputeFlyKeyboardInput()
end

function SlideController:_updateFlyTouchInput(inputObject)
	local config = self:_getAirControlConfig()
	if not (inputObject and self._flyTouchDragStartPosition and config.enabled) then
		self._flyTouchInput = Vector2.zero
		return
	end

	self._flyTouchDragPosition = inputObject.Position

	local dragDelta = inputObject.Position - self._flyTouchDragStartPosition
	local normalizedX = (dragDelta.X / config.touchMaxDragPixels) * config.touchSensitivity
	local absNormalizedX = math.abs(normalizedX)
	if absNormalizedX <= config.touchDeadzone then
		self._flyTouchInput = Vector2.zero
		return
	end

	local scaledMagnitude = math.clamp((absNormalizedX - config.touchDeadzone) / (1 - config.touchDeadzone), 0, 1)
	self._flyTouchInput = Vector2.new(math.sign(normalizedX) * scaledMagnitude, 0)
end

function SlideController:_beginFlyTouchDrag(inputObject)
	if not inputObject then
		return
	end

	self._flyTouchDragInputObject = inputObject
	self._flyTouchDragStartPosition = inputObject.Position
	self._flyTouchDragPosition = inputObject.Position
	self._flyTouchInput = Vector2.zero
end

function SlideController:_endFlyTouchDrag(inputObject)
	if inputObject and self._flyTouchDragInputObject and inputObject ~= self._flyTouchDragInputObject then
		return
	end

	self._flyTouchDragInputObject = nil
	self._flyTouchDragStartPosition = nil
	self._flyTouchDragPosition = nil
	self._flyTouchInput = Vector2.zero
end

function SlideController:_ensureAirControlInputBindings()
	if #self._flyInputConnections > 0 then
		return
	end

	table.insert(self._flyInputConnections, UserInputService.InputBegan:Connect(function(inputObject, gameProcessed)
		if inputObject.UserInputType == Enum.UserInputType.Keyboard then
			local hasFocusedTextBox = UserInputService:GetFocusedTextBox() ~= nil
			local shouldTriggerFastLanding = inputObject.KeyCode == FAST_LANDING_TRIGGER_KEYCODE
				and (self._isLaunchFlightActive or self._launchNoGravityEndTime > os.clock())
				and not hasFocusedTextBox
			if shouldTriggerFastLanding then
				self:_triggerFastLanding()
				return
			end

			local shouldCaptureKeyboard = AIR_CONTROL_KEYCODES[inputObject.KeyCode] ~= nil
				and self._isLaunchFlightActive
				and not hasFocusedTextBox
			if shouldCaptureKeyboard then
				self:_setFlyKeyPressed(inputObject.KeyCode, true)
				return
			end
		end

		if gameProcessed then
			return
		end
	end))

	table.insert(self._flyInputConnections, UserInputService.InputEnded:Connect(function(inputObject)
		if inputObject.UserInputType == Enum.UserInputType.Keyboard then
			self:_setFlyKeyPressed(inputObject.KeyCode, false)
		end
	end))

	table.insert(self._flyInputConnections, UserInputService.TouchStarted:Connect(function(inputObject, gameProcessed)
		if gameProcessed or not self._isLaunchFlightActive or self._flyTouchDragInputObject then
			return
		end

		self:_beginFlyTouchDrag(inputObject)
	end))

	table.insert(self._flyInputConnections, UserInputService.TouchMoved:Connect(function(inputObject, gameProcessed)
		if gameProcessed then
			return
		end

		if self._flyTouchDragInputObject and inputObject == self._flyTouchDragInputObject and self._isLaunchFlightActive then
			self:_updateFlyTouchInput(inputObject)
		end
	end))

	table.insert(self._flyInputConnections, UserInputService.TouchEnded:Connect(function(inputObject)
		self:_endFlyTouchDrag(inputObject)
	end))
end
function SlideController:_getEquippedJetpackEntry()
	local equippedJetpackId = normalizeJetpackId(localPlayer:GetAttribute("EquippedJetpackId"))
	local entry = equippedJetpackId > 0 and JetpackConfig.EntriesById[equippedJetpackId] or nil
	if entry then
		return entry
	end

	local defaultJetpackId = normalizeJetpackId(JetpackConfig.DefaultEntryId)
	return defaultJetpackId > 0 and JetpackConfig.EntriesById[defaultJetpackId] or nil
end

function SlideController:_getNoGravityDuration()
	local entry = self:_getEquippedJetpackEntry()
	return math.max(0, tonumber(entry and entry.NoGravityDuration) or 0)
end

function SlideController:_getBulletTimeFallSpeed()
	local entry = self:_getEquippedJetpackEntry()
	return math.max(0, tonumber(entry and entry.BulletTimeFallSpeed) or 0)
end

function SlideController:_getFlyLateralSpeed()
	local baseSpeed = 0
	if self._launchMomentumVelocity then
		baseSpeed = self._launchMomentumVelocity.Magnitude
	end

	baseSpeed = math.max(baseSpeed, self._slideSpeed, self:_getEntrySpeed())
	return math.clamp(baseSpeed * FLY_LATERAL_SPEED_FACTOR, FLY_LATERAL_SPEED_MIN, FLY_LATERAL_SPEED_MAX)
end
function SlideController:_clearNoGravityForce()
	local noGravityForce = self._noGravityForce
	self._noGravityForce = nil
	if noGravityForce then
		pcall(function()
			noGravityForce:Destroy()
		end)
	end

	local noGravityAttachment = self._noGravityAttachment
	self._noGravityAttachment = nil
	if noGravityAttachment then
		pcall(function()
			noGravityAttachment:Destroy()
		end)
	end

	self._launchNoGravityRootPart = nil
end

function SlideController:_ensureNoGravityForce(rootPart)
	if not (rootPart and rootPart.Parent) then
		return nil
	end

	local hasReusableForce = self._launchNoGravityRootPart == rootPart
		and self._noGravityAttachment
		and self._noGravityAttachment.Parent == rootPart
		and self._noGravityForce
		and self._noGravityForce.Parent == rootPart

	if not hasReusableForce then
		self:_clearNoGravityForce()

		local attachment = Instance.new("Attachment")
		attachment.Name = NO_GRAVITY_ATTACHMENT_NAME
		attachment.Parent = rootPart

		local vectorForce = Instance.new("VectorForce")
		vectorForce.Name = NO_GRAVITY_FORCE_NAME
		vectorForce.Attachment0 = attachment
		vectorForce.ApplyAtCenterOfMass = true
		vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World
		vectorForce.Parent = rootPart

		self._launchNoGravityRootPart = rootPart
		self._noGravityAttachment = attachment
		self._noGravityForce = vectorForce
	end

	return self._noGravityForce
end

function SlideController:_stopLaunchNoGravity()
	self._launchNoGravityDuration = 0
	self._launchNoGravityEndTime = 0
	self._launchNoGravityGroundCheckAt = 0
	self:_clearNoGravityForce()
	self:_setFlyProgressVisible(false)
end

function SlideController:_startLaunchNoGravity(rootPart)
	self:_stopLaunchNoGravity()

	local duration = self:_getNoGravityDuration()
	if duration <= 0 then
		return
	end

	local noGravityForce = self:_ensureNoGravityForce(rootPart)
	if not noGravityForce then
		return
	end

	self._launchNoGravityDuration = duration
	self._launchNoGravityEndTime = os.clock() + duration
	self._launchNoGravityGroundCheckAt = os.clock() + NO_GRAVITY_GROUND_CHECK_GRACE_SECONDS
	noGravityForce.Force = Vector3.new(0, rootPart.AssemblyMass * Workspace.Gravity, 0)
	self:_updateFlyProgressBar(1)
	self:_setFlyProgressVisible(true)
end

function SlideController:_updateLaunchNoGravity(humanoid, rootPart)
	if self._launchNoGravityEndTime <= 0 or self._launchNoGravityDuration <= 0 then
		return false
	end

	if not (humanoid and rootPart and rootPart.Parent) then
		self:_stopLaunchNoGravity()
		return false
	end

	if os.clock() >= self._launchNoGravityGroundCheckAt and humanoid.FloorMaterial ~= Enum.Material.Air then
		self:_stopLaunchNoGravity()
		return false
	end

	local remainingTime = self._launchNoGravityEndTime - os.clock()
	if remainingTime <= 0 then
		self:_stopLaunchNoGravity()
		return false
	end

	local noGravityForce = self:_ensureNoGravityForce(rootPart)
	if not noGravityForce then
		self:_stopLaunchNoGravity()
		return false
	end

	noGravityForce.Force = Vector3.new(0, rootPart.AssemblyMass * Workspace.Gravity, 0)
	self:_updateFlyProgressBar(remainingTime / self._launchNoGravityDuration)
	return true
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
function SlideController:_isNamedSlidePart(part, expectedName)
	if not (part and part:IsA("BasePart")) then
		return false
	end

	if part.Name ~= tostring(expectedName or "") then
		return false
	end

	local slideRoot = self:_resolveSlideRoot()
	return slideRoot ~= nil and part:IsDescendantOf(slideRoot)
end

function SlideController:_isSlideSurfacePart(part)
	return self:_isNamedSlidePart(part, self:_getSurfacePartName())
end

function SlideController:_isLaunchPart(part)
	return self:_isNamedSlidePart(part, self:_getLaunchPartName())
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

function SlideController:_getGroundRaycastExcludeInstances()
	local excludedInstances = {}
	if self._character then
		table.insert(excludedInstances, self._character)
	end

	if self._flightEffectRuntimeRoot and self._flightEffectRuntimeRoot.Parent then
		table.insert(excludedInstances, self._flightEffectRuntimeRoot)
	end


	return excludedInstances
end

function SlideController:_raycastGround(rootPart)
	if not rootPart then
		return nil
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = self:_getGroundRaycastExcludeInstances()
	raycastParams.IgnoreWater = true

	local origin = rootPart.Position + Vector3.new(0, self:_getRaycastStartOffsetY(), 0)
	return Workspace:Raycast(origin, Vector3.new(0, -self:_getRaycastLength(), 0), raycastParams)
end

function SlideController:_getGroundDistance(rootPart)
	local result = self:_raycastGround(rootPart)
	if not (result and rootPart) then
		return nil, nil
	end

	local rootBottomY = rootPart.Position.Y - (rootPart.Size.Y * 0.5)
	local distance = math.max(0, rootBottomY - result.Position.Y)
	return distance, result
end

function SlideController:_getGroundPart(rootPart)
	local result = self:_raycastGround(rootPart)
	local instance = result and result.Instance or nil
	if instance and instance:IsA("BasePart") then
		return instance
	end

	return nil
end
function SlideController:_getTrackedSlideGroundParts()
	local slideRoot = self:_resolveSlideRoot()
	if not slideRoot then
		return nil
	end

	local surfacePartName = self:_getSurfacePartName()
	local launchPartName = self:_getLaunchPartName()
	local trackedParts = {}
	for _, descendant in ipairs(slideRoot:GetDescendants()) do
		if descendant:IsA("BasePart") and (descendant.Name == surfacePartName or descendant.Name == launchPartName) then
			table.insert(trackedParts, descendant)
		end
	end

	if #trackedParts <= 0 then
		return nil
	end

	return trackedParts
end

function SlideController:_raycastTrackedSlideGround(rootPart)
	if not rootPart then
		return nil
	end

	local trackedParts = self:_getTrackedSlideGroundParts()
	if not trackedParts then
		return nil
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = trackedParts
	raycastParams.IgnoreWater = true

	local origin = rootPart.Position + Vector3.new(0, self:_getRaycastStartOffsetY(), 0)
	return Workspace:Raycast(origin, Vector3.new(0, -self:_getRaycastLength(), 0), raycastParams)
end

function SlideController:_getTrackedSlideGroundPart(rootPart)
	local result = self:_raycastTrackedSlideGround(rootPart)
	local instance = result and result.Instance or nil
	if instance and instance:IsA("BasePart") then
		return instance
	end

	return nil
end

local TOUCHED_SLIDE_GRACE_SECONDS = 0.25

function SlideController:_clearSlideTouchedConnections()
	for _, conn in ipairs(self._slideTouchedConnections) do
		if conn then
			conn:Disconnect()
		end
	end
	table.clear(self._slideTouchedConnections)
	self._touchedSlidePart = nil
	self._touchedSlidePartExpireAt = 0
end

function SlideController:_bindSlideTouchedEvents(character)
	self:_clearSlideTouchedConnections()
	if not character then
		return
	end

	local slideRoot = self:_resolveSlideRoot()
	if not slideRoot then
		return
	end

	local surfacePartName = self:_getSurfacePartName()
	local trackedParts = {}
	for _, descendant in ipairs(slideRoot:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == surfacePartName then
			table.insert(trackedParts, descendant)
		end
	end

	for _, slidePart in ipairs(trackedParts) do
		local conn = slidePart.Touched:Connect(function(otherPart)
			if not otherPart or not otherPart:IsDescendantOf(self._character) then
				return
			end
			self._touchedSlidePart = slidePart
			self._touchedSlidePartExpireAt = os.clock() + TOUCHED_SLIDE_GRACE_SECONDS
		end)
		table.insert(self._slideTouchedConnections, conn)
	end
end

function SlideController:_consumeTouchedSlidePart()
	if not self._touchedSlidePart then
		return nil
	end
	if os.clock() > self._touchedSlidePartExpireAt then
		self._touchedSlidePart = nil
		self._touchedSlidePartExpireAt = 0
		return nil
	end
	local part = self._touchedSlidePart
	self._touchedSlidePart = nil
	self._touchedSlidePartExpireAt = 0
	return part
end

function SlideController:_clearLaunchFlightCollisionConnections()
	disconnectAll(self._launchFlightCollisionConnections)
	self._pendingLaunchCollisionPart = nil
end

function SlideController:_shouldStopLaunchFlightFromTouchedPart(touchedPart)
	if not self._isLaunchFlightActive then
		return false
	end

	if not (touchedPart and touchedPart:IsA("BasePart") and touchedPart.Parent) then
		return false
	end

	if touchedPart.CanCollide ~= true then
		return false
	end

	if self._character and touchedPart:IsDescendantOf(self._character) then
		return false
	end

	if self._flightEffectRuntimeRoot and touchedPart:IsDescendantOf(self._flightEffectRuntimeRoot) then
		return false
	end

	if self:_isSlideSurfacePart(touchedPart) or self:_isLaunchPart(touchedPart) then
		return false
	end

	local rootPart = self._humanoidRootPart
	if rootPart and rootPart.Parent then
		local rootBottomY = rootPart.Position.Y - (rootPart.Size.Y * 0.5)
		local touchedTopY = touchedPart.Position.Y + (touchedPart.Size.Y * 0.5)
		if touchedTopY <= rootBottomY + 0.2 then
			return false
		end
	end

	local ancestorModel = touchedPart:FindFirstAncestorOfClass("Model")
	if ancestorModel and ancestorModel ~= self._character and ancestorModel:FindFirstChildOfClass("Humanoid") then
		return false
	end

	return true
end

function SlideController:_queueLaunchFlightCollision(touchedPart)
	if self:_shouldStopLaunchFlightFromTouchedPart(touchedPart) then
		self._pendingLaunchCollisionPart = touchedPart
	end
end

function SlideController:_bindLaunchFlightCollisionConnections(character)
	self:_clearLaunchFlightCollisionConnections()
	if not character then
		return
	end

	local function bindPart(part)
		if not (part and part:IsA("BasePart")) then
			return
		end

		table.insert(self._launchFlightCollisionConnections, part.Touched:Connect(function(otherPart)
			self:_queueLaunchFlightCollision(otherPart)
		end))
	end

	for _, descendant in ipairs(character:GetDescendants()) do
		bindPart(descendant)
	end

	table.insert(self._launchFlightCollisionConnections, character.DescendantAdded:Connect(function(descendant)
		bindPart(descendant)
	end))
end

function SlideController:_consumePendingLaunchFlightCollision()
	local collisionPart = self._pendingLaunchCollisionPart
	self._pendingLaunchCollisionPart = nil
	if self:_shouldStopLaunchFlightFromTouchedPart(collisionPart) then
		return collisionPart
	end

	return nil
end

function SlideController:_abortLaunchFlightFromCollision(humanoid, rootPart, collisionPart)
	if not (collisionPart and self._isLaunchFlightActive) then
		return false
	end

	self:_stopLaunchNoGravity()
	self:_stopLaunchFlight(rootPart)
	self:_clearLaunchMomentum()
	self._pendingLaunchLandingImpact = true
	self:_setGameplayUiHidden(false)

	if rootPart and rootPart.Parent then
		local currentVelocity = rootPart.AssemblyLinearVelocity
		rootPart.AssemblyLinearVelocity = Vector3.new(0, math.min(currentVelocity.Y, -FLIGHT_COLLISION_FALL_SPEED), 0)
	end

	if humanoid then
		pcall(function()
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		end)
	end

	return true
end

function SlideController:_attachCharacter(character)
	local previousHumanoid = self._humanoid
	if previousHumanoid then
		pcall(function()
			previousHumanoid.AutoRotate = true
		end)
	end

	self:_setControlsLocked(previousHumanoid, false)
	self:_setGameplayUiHidden(false)
	self:_stopLandingShake()

	self._character = character
	self._humanoid = nil
	self._humanoidRootPart = nil
	self:_stopSlideAnimation()
	self._isSliding = false
	self._slideDirection = nil
	self._slideSpeed = 0
	self._launchMomentumVelocity = nil
	self._isFastLandingActive = false
	self._pendingLaunchLandingImpact = false
	self:_stopLaunchFlight(nil)
	self:_stopLaunchNoGravity()
	self:_clearFlyButtonBindings()
	self:_clearSlideTouchedConnections()

	if not character then
		return
	end


	task.defer(function()
		if self._character ~= character then
			return
		end

		self._humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
		self._humanoidRootPart = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 5)
		self:_stopLandingAnimation()
		self:_bindSlideTouchedEvents(character)
		self:_primeMovementAnimationTracks(self._humanoid)
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

	if self._humanoid then
		self:_primeMovementAnimationTracks(self._humanoid)
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

function SlideController:_getAnimationTrackFieldName(animationKey)
	if animationKey == "slide" then
		return "_slideAnimationTrack"
	end

	if animationKey == "launch" then
		return "_launchAnimationTrack"
	end

	if animationKey == "fall" then
		return "_fallAnimationTrack"
	end

	return nil
end

function SlideController:_getAnimationIdByKey(animationKey)
	if animationKey == "slide" then
		return self:_getSlideAnimationId()
	end

	if animationKey == "launch" then
		return self:_getLaunchAnimationId()
	end

	if animationKey == "fall" then
		return self:_getFallAnimationId()
	end

	return ""
end

function SlideController:_resolveLandingSoundTemplate()
	local audioFolder = SoundService:FindFirstChild(LANDING_SOUND_TEMPLATE_FOLDER_NAME)
	local slideFolder = audioFolder and audioFolder:FindFirstChild(LANDING_SOUND_TEMPLATE_SLIDE_FOLDER_NAME)
	local template = slideFolder and slideFolder:FindFirstChild(LANDING_SOUND_TEMPLATE_NAME)
	if template and template:IsA("Sound") then
		return template
	end

	return nil
end

function SlideController:_playLandingSound(rootPart)
	local now = os.clock()
	if now - (self._lastLandingSoundAt or 0) < 0.12 then
		return
	end
	self._lastLandingSoundAt = now

	local template = self:_resolveLandingSoundTemplate()
	local landingSound = nil
	if template then
		landingSound = template:Clone()
	else
		landingSound = Instance.new("Sound")
		landingSound.Name = LANDING_SOUND_TEMPLATE_NAME
		landingSound.SoundId = LANDING_SOUND_ASSET_ID
		landingSound.Volume = 1
	end

	landingSound.Parent = rootPart or SoundService
	landingSound:Play()

	local cleanupDelay = math.max(2, tonumber(landingSound.TimeLength) or 0)
	task.delay(cleanupDelay + 0.1, function()
		if landingSound and landingSound.Parent then
			landingSound:Destroy()
		end
	end)
end

function SlideController:_stopLandingAnimation()
	local track = self._landingAnimationTrack
	if track then
		pcall(function()
			track:Stop(self:_getAnimationFadeTime("fall"))
		end)
	end

	self._landingAnimationTrack = nil
end

function SlideController:_playLandingAnimation(humanoid)
	local animationId = self:_getLandingAnimationId()
	if animationId == "" or not humanoid then
		return
	end

	local now = os.clock()
	if now - (self._lastLandingAt or 0) < 0.2 then
		return
	end
	self._lastLandingAt = now

	self:_stopLandingAnimation()

	local animator = self:_getAnimator(humanoid)
	if not animator then
		return
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animationId

	local success, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()

	if not success or not track then
		return
	end

	track.Priority = Enum.AnimationPriority.Action
	track.Looped = false
	self._landingAnimationTrack = track
	track:Play(self:_getAnimationFadeTime("fall"))

	local cleanupDelay = math.max(0.35, tonumber(track.Length) or 0.6)
	task.delay(cleanupDelay, function()
		if self._landingAnimationTrack ~= track then
			return
		end
		self:_stopLandingAnimation()
	end)
end

function SlideController:_stabilizeLanding(humanoid, rootPart)
	if not (humanoid and rootPart and rootPart.Parent) then
		return
	end

	local currentVelocity = rootPart.AssemblyLinearVelocity
	local horizontalVelocity = flattenVector(currentVelocity)
	local maxHorizontalSpeed = self:_getLandingRecoveryHorizontalSpeed()
	if horizontalVelocity.Magnitude > maxHorizontalSpeed and horizontalVelocity.Magnitude > MIN_DIRECTION_MAGNITUDE then
		horizontalVelocity = horizontalVelocity.Unit * maxHorizontalSpeed
	end

	rootPart.AssemblyLinearVelocity = Vector3.new(horizontalVelocity.X, 0, horizontalVelocity.Z)
	rootPart.AssemblyAngularVelocity = Vector3.zero

	local suppressRootPart = rootPart
	local suppressCount = 0
	local isFastLanding = self._isFastLandingActive == true
	local suppressMax = isFastLanding and FAST_LANDING_UPWARD_SUPPRESS_FRAMES or 4
	local suppressConnection
	suppressConnection = RunService.Heartbeat:Connect(function()
		suppressCount += 1
		if suppressCount > suppressMax or not (suppressRootPart and suppressRootPart.Parent) then
			if suppressConnection then
				suppressConnection:Disconnect()
			end
			return
		end
		local vel = suppressRootPart.AssemblyLinearVelocity
		if vel.Y > 0 then
			suppressRootPart.AssemblyLinearVelocity = Vector3.new(vel.X, 0, vel.Z)
		end
	end)

	pcall(function()
		humanoid.AutoRotate = true
		humanoid.PlatformStand = false
		humanoid.Sit = false
		if isFastLanding then
			humanoid:ChangeState(Enum.HumanoidStateType.Landed)
		end
		if not isFastLanding then
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
		end
	end)

	if isFastLanding then
		return
	end

	local landingHumanoid = humanoid
	task.delay(LANDING_RECOVERY_STATE_RESET_DELAY, function()
		if self._humanoid ~= landingHumanoid then
			return
		end
		pcall(function()
			landingHumanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
			landingHumanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
		end)
	end)
end

function SlideController:_getAnimationTrackByKey(animationKey)
	local fieldName = self:_getAnimationTrackFieldName(animationKey)
	if not fieldName then
		return nil
	end

	return self[fieldName]
end

function SlideController:_setAnimationTrackByKey(animationKey, track)
	local fieldName = self:_getAnimationTrackFieldName(animationKey)
	if fieldName then
		self[fieldName] = track
	end
end

function SlideController:_stopMovementAnimationPlayback(animationKey, shouldClearTrackReference)
	local track = self:_getAnimationTrackByKey(animationKey)
	if track then
		pcall(function()
			track:Stop(self:_getAnimationFadeTime(animationKey))
		end)
	end

	if shouldClearTrackReference then
		self:_setAnimationTrackByKey(animationKey, nil)
	end

	if self._currentAnimationKey == animationKey then
		self._currentAnimationKey = nil
	end
end

function SlideController:_stopAllMovementAnimationPlayback(shouldClearTrackReferences)
	for _, animationKey in ipairs(MOVEMENT_ANIMATION_KEYS) do
		self:_stopMovementAnimationPlayback(animationKey, shouldClearTrackReferences)
	end
end

function SlideController:_clearAnimationTracks()
	self:_stopAllMovementAnimationPlayback(true)
	self._animationHumanoid = nil
	self._currentAnimationKey = nil
end

function SlideController:_ensureMovementAnimationTrack(humanoid, animationKey)
	if self._animationHumanoid ~= humanoid then
		self:_clearAnimationTracks()
	end

	local existingTrack = self:_getAnimationTrackByKey(animationKey)
	if self._animationHumanoid == humanoid and existingTrack then
		return existingTrack
	end

	local animator = self:_getAnimator(humanoid)
	if not animator then
		return nil
	end

	local animationId = self:_getAnimationIdByKey(animationKey)
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
		if not self._didWarnAnimationLoadFailed[animationKey] then
			self._didWarnAnimationLoadFailed[animationKey] = true
			warn(string.format("[SlideController] %s animation load failed: %s", animationKey, tostring(track)))
		end
		return nil
	end

	track.Priority = Enum.AnimationPriority.Action
	track.Looped = true
	track:AdjustSpeed(math.max(0.1, tonumber(self:_getConfig().AnimationPlaybackSpeed) or 1))
	self._animationHumanoid = humanoid
	self:_setAnimationTrackByKey(animationKey, track)
	return track
end

function SlideController:_primeMovementAnimationTracks(humanoid)
	if not humanoid then
		return
	end

	for _, animationKey in ipairs(MOVEMENT_ANIMATION_KEYS) do
		self:_ensureMovementAnimationTrack(humanoid, animationKey)
	end
end

function SlideController:_playMovementAnimation(humanoid, animationKey)
	self:_stopLandingAnimation()

	local track = self:_ensureMovementAnimationTrack(humanoid, animationKey)
	if not track then
		return
	end

	for _, otherAnimationKey in ipairs(MOVEMENT_ANIMATION_KEYS) do
		if otherAnimationKey ~= animationKey then
			local otherTrack = self:_getAnimationTrackByKey(otherAnimationKey)
			if otherTrack and otherTrack.IsPlaying then
				pcall(function()
					otherTrack:Stop(self:_getAnimationFadeTime(otherAnimationKey))
				end)
			end
		end
	end

	if not track.IsPlaying then
		track:Play(self:_getAnimationFadeTime(animationKey))
	end

	self._currentAnimationKey = animationKey
end

function SlideController:_playSlideAnimation(humanoid)
	self:_primeMovementAnimationTracks(humanoid)
	self:_playMovementAnimation(humanoid, "slide")
end

function SlideController:_updateLaunchFlightAnimation(humanoid, rootPart)
	if not humanoid then
		return
	end

	self:_primeMovementAnimationTracks(humanoid)

	local currentVelocity = rootPart and rootPart.AssemblyLinearVelocity or Vector3.zero
	if currentVelocity.Y >= 0 then
		self:_playMovementAnimation(humanoid, "launch")
		return
	end

	self:_playMovementAnimation(humanoid, "fall")
end

function SlideController:_stopSlideAnimation()
	self:_stopMovementAnimationPlayback("slide", false)
end

function SlideController:_stopLaunchFlightAnimations()
	self:_stopMovementAnimationPlayback("launch", false)
	self:_stopMovementAnimationPlayback("fall", false)
end

function SlideController:_setSlidingActive(humanoid, isActive)
	if self._isSliding == isActive then
		self:_setControlsLocked(humanoid, isActive)
		if isActive and humanoid then
			humanoid.Jump = false
			self:_playSlideAnimation(humanoid)
		end
		return
	end

	self._isSliding = isActive
	self:_setControlsLocked(humanoid, isActive)
	if isActive then
		self:_setGameplayUiHidden(true)
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
	self._flyLateralVelocity = Vector3.zero
	self._flyControlVelocity = Vector3.zero
end

function SlideController:_setLaunchMomentum(launchVelocity)
	local horizontalVelocity = flattenVector(launchVelocity or Vector3.zero)
	if horizontalVelocity.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		self._launchMomentumVelocity = nil
		return
	end

	self._launchMomentumVelocity = horizontalVelocity
	self._flyLateralVelocity = Vector3.zero
	self._flyControlVelocity = Vector3.zero
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

function SlideController:_shouldKeepLaunchFlight(humanoid, rootPart)
	if not self._isLaunchFlightActive then
		return false
	end

	if self._launchNoGravityEndTime > 0 then
		return true
	end

	if humanoid == nil then
		return false
	end

	if humanoid.FloorMaterial == Enum.Material.Air then
		return true
	end

	return self:_getGroundPart(rootPart) == nil
end

function SlideController:_applyLaunchMomentum(rootPart)
	if not (rootPart and rootPart.Parent) then
		return
	end

	local horizontalVelocity = self:_getCurrentLaunchBaseHorizontalVelocity(rootPart)
	if self._isBulletTimeActive then
		local scaledTrajectoryVelocity = self:_getBulletTimeScaledBaseTrajectoryVelocity(rootPart)
		if scaledTrajectoryVelocity then
			horizontalVelocity = flattenVector(scaledTrajectoryVelocity)
		end
	end

	horizontalVelocity += self:_getFlyLateralAdjustmentVelocity()
	if horizontalVelocity.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		return
	end

	local currentVelocity = rootPart.AssemblyLinearVelocity
	rootPart.AssemblyLinearVelocity = Vector3.new(
		horizontalVelocity.X,
		currentVelocity.Y,
		horizontalVelocity.Z
	)
end

function SlideController:_clearLaunchFlightEffects()
	local runtimeRoot = self._flightEffectRuntimeRoot
	self._flightEffectRuntimeRoot = nil
	self._flightEffectRootPart = nil

	if runtimeRoot then
		runtimeRoot:Destroy()
	end
end

function SlideController:_warnMissingFlightEffectTemplate(templateName)
	if self._didWarnMissingFlightEffectTemplate[templateName] then
		return
	end

	self._didWarnMissingFlightEffectTemplate[templateName] = true
	warn(string.format(
		"[SlideController] Missing flight effect template: ReplicatedStorage.%s.%s",
		FLIGHT_EFFECT_FOLDER_NAME,
		templateName
		))
end

function SlideController:_attachLaunchFlightEffects(rootPart)
	local character = self._character
	if not (character and character.Parent and rootPart and rootPart.Parent) then
		self:_clearLaunchFlightEffects()
		return
	end

	local runtimeRoot = self._flightEffectRuntimeRoot
	if runtimeRoot and runtimeRoot.Parent == character and self._flightEffectRootPart == rootPart then
		return
	end

	self:_clearLaunchFlightEffects()

	local effectFolder = ReplicatedStorage:FindFirstChild(FLIGHT_EFFECT_FOLDER_NAME)
	if not (effectFolder and effectFolder:IsA("Folder")) then
		return
	end

	runtimeRoot = Instance.new("Folder")
	runtimeRoot.Name = FLIGHT_EFFECT_RUNTIME_FOLDER_NAME
	runtimeRoot.Parent = character

	for _, templateName in ipairs(FLIGHT_EFFECT_TEMPLATE_NAMES) do
		local template = effectFolder:FindFirstChild(templateName)
		if not template then
			self:_warnMissingFlightEffectTemplate(templateName)
			continue
		end

		local clone = template:Clone()
		local primaryPart = clone:IsA("BasePart") and clone or clone:FindFirstChildWhichIsA("BasePart", true)
		if not primaryPart then
			clone:Destroy()
			continue
		end

		if clone:IsA("BasePart") then
			clone.Anchored = false
			clone.CanCollide = false
			clone.CanTouch = false
			clone.CanQuery = false
			clone.CastShadow = false
			clone.Massless = true
			clone.CFrame = rootPart.CFrame
		elseif clone:IsA("Model") then
			clone:PivotTo(rootPart.CFrame)
		end

		for _, descendant in ipairs(clone:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Anchored = false
				descendant.CanCollide = false
				descendant.CanTouch = false
				descendant.CanQuery = false
				descendant.CastShadow = false
				descendant.Massless = true
			end
		end

		clone.Parent = runtimeRoot

		local weldConstraint = Instance.new("WeldConstraint")
		weldConstraint.Name = FLIGHT_EFFECT_WELD_NAME
		weldConstraint.Part0 = rootPart
		weldConstraint.Part1 = primaryPart
		weldConstraint.Parent = primaryPart
	end

	if #runtimeRoot:GetChildren() <= 0 then
		runtimeRoot:Destroy()
		return
	end

	self._flightEffectRuntimeRoot = runtimeRoot
	self._flightEffectRootPart = rootPart
end

function SlideController:_startLaunchFlight(rootPart)
	self._isLaunchFlightActive = true
	self._isFastLandingActive = false
	self._pendingLaunchLandingImpact = false
	self:_cacheFlightProgressPath()
	self:_stopBulletTime(rootPart, false)
	self:_clearFlyButtonInputState()
	self:_bindLaunchFlightCollisionConnections(self._character)
	self:_attachLaunchFlightEffects(rootPart)
	self:_setFlyButtonVisible(false)
	self:_setGameplayUiHidden(true)
	local startRatio = self:_computeFlightProgressRatio(rootPart and rootPart.Position or nil)
	self:_setMainProgressFlightOverride(true, startRatio or 0)
	self:_stopLandingShake()

	if self._humanoid then
		self:_setControlsLocked(self._humanoid, true)
		pcall(function()
			self._humanoid.AutoRotate = false
			self._humanoid.Jump = false
		end)
	end
end

function SlideController:_stopLaunchFlight(rootPart)
	self._isLaunchFlightActive = false
	self._isFastLandingActive = false
	self:_stopBulletTime(rootPart, false)
	self:_clearFlyButtonInputState()
	self:_clearLaunchFlightCollisionConnections()
	self:_clearLaunchFlightEffects()
	self:_setFlyButtonVisible(false)
	self:_stopLaunchFlightAnimations()
	if not self._isSliding then
		self:_stopSlideAnimation()
	end

	if self._humanoid then
		self:_setControlsLocked(self._humanoid, self._isSliding)
	end

	if self._humanoid and not self._isSliding then
		pcall(function()
			self._humanoid.AutoRotate = true
			self._humanoid.Jump = false
		end)
	end

	self:_setMainProgressFlightOverride(false, 0)
end
function SlideController:_startBulletTime(rootPart)
	local fallSpeed = self:_getBulletTimeFallSpeed()
	if self._isBulletTimeActive or fallSpeed <= 0 or not (rootPart and rootPart.Parent) then
		return
	end

	local baselineHorizontalVelocity = self:_getCurrentLaunchBaseHorizontalVelocity(rootPart)
	local baselineTrajectoryVelocity = Vector3.new(
		baselineHorizontalVelocity.X,
		rootPart.AssemblyLinearVelocity.Y,
		baselineHorizontalVelocity.Z
	)

	self._isBulletTimeActive = true
	self._bulletTimeBaselineVelocity = baselineTrajectoryVelocity
	self._bulletTimeBaselineLaunchMomentumVelocity = baselineHorizontalVelocity
	self._bulletTimeBaselineTrajectoryVelocity = baselineTrajectoryVelocity
	self._bulletTimeStartedAt = os.clock()
	self:_setBulletTimeFxActive(true)
end

function SlideController:_stopBulletTime(rootPart, shouldRestoreVelocity)
	if not self._isBulletTimeActive then
		self._bulletTimeBaselineVelocity = nil
		self._bulletTimeBaselineLaunchMomentumVelocity = nil
		self._bulletTimeBaselineTrajectoryVelocity = nil
		self._bulletTimeStartedAt = 0
		return
	end

	local baselineLaunchMomentumVelocity = self._bulletTimeBaselineLaunchMomentumVelocity
	local baselineTrajectoryVelocity = self._bulletTimeBaselineTrajectoryVelocity
	self._isBulletTimeActive = false
	self._bulletTimeBaselineVelocity = nil
	self._bulletTimeBaselineLaunchMomentumVelocity = nil
	self._bulletTimeBaselineTrajectoryVelocity = nil
	self._bulletTimeStartedAt = 0
	self:_setBulletTimeFxActive(false)

	if baselineLaunchMomentumVelocity and baselineLaunchMomentumVelocity.Magnitude > MIN_DIRECTION_MAGNITUDE then
		self._launchMomentumVelocity = baselineLaunchMomentumVelocity
	end

	if shouldRestoreVelocity ~= true or not (rootPart and rootPart.Parent) or not baselineTrajectoryVelocity then
		return
	end

	local lateralAdjustmentVelocity = self:_getFlyLateralAdjustmentVelocity()
	local restoredHorizontalVelocity = flattenVector(baselineTrajectoryVelocity) + lateralAdjustmentVelocity
	rootPart.AssemblyLinearVelocity = Vector3.new(
		restoredHorizontalVelocity.X,
		baselineTrajectoryVelocity.Y,
		restoredHorizontalVelocity.Z
	)
end

function SlideController:_applyBulletTime(rootPart)
	local fallSpeed = self:_getBulletTimeFallSpeed()
	if not self._isBulletTimeActive or fallSpeed <= 0 or not (rootPart and rootPart.Parent) then
		self:_stopBulletTime(rootPart, false)
		return
	end

	local scaledTrajectoryVelocity = self:_getBulletTimeScaledBaseTrajectoryVelocity(rootPart)
	if not scaledTrajectoryVelocity then
		self:_stopBulletTime(rootPart, false)
		return
	end

	local currentVelocity = rootPart.AssemblyLinearVelocity
	rootPart.AssemblyLinearVelocity = Vector3.new(
		currentVelocity.X,
		scaledTrajectoryVelocity.Y,
		currentVelocity.Z
	)
end

function SlideController:_getFlyLateralDirection(rootPart)
	local _, rightDirection = self:_getLaunchTrajectoryPlanarBasis(rootPart)
	return rightDirection
end

function SlideController:_getFlyCameraPlanarBasis(rootPart)
	local currentCamera = Workspace.CurrentCamera
	local forwardDirection = currentCamera and flattenVector(currentCamera.CFrame.LookVector) or Vector3.zero
	local rightDirection = currentCamera and flattenVector(currentCamera.CFrame.RightVector) or Vector3.zero

	if forwardDirection.Magnitude <= MIN_DIRECTION_MAGNITUDE and rootPart then
		forwardDirection = flattenVector(rootPart.CFrame.LookVector)
	end
	if rightDirection.Magnitude <= MIN_DIRECTION_MAGNITUDE and rootPart then
		rightDirection = flattenVector(rootPart.CFrame.RightVector)
	end

	if forwardDirection.Magnitude <= MIN_DIRECTION_MAGNITUDE and rightDirection.Magnitude > MIN_DIRECTION_MAGNITUDE then
		forwardDirection = Vector3.new(rightDirection.Z, 0, -rightDirection.X)
	end
	if rightDirection.Magnitude <= MIN_DIRECTION_MAGNITUDE and forwardDirection.Magnitude > MIN_DIRECTION_MAGNITUDE then
		rightDirection = Vector3.new(-forwardDirection.Z, 0, forwardDirection.X)
	end

	if forwardDirection.Magnitude <= MIN_DIRECTION_MAGNITUDE or rightDirection.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		return nil, nil
	end

	forwardDirection = forwardDirection.Unit
	rightDirection = Vector3.new(-forwardDirection.Z, 0, forwardDirection.X)
	if rightDirection.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		return nil, nil
	end

	return forwardDirection, rightDirection.Unit
end

function SlideController:_getFlyButtonInputVector()
	local lateralInput = 0
	if self._flyLeftPressed and not self._flyRightPressed then
		lateralInput = -1
	elseif self._flyRightPressed and not self._flyLeftPressed then
		lateralInput = 1
	end

	return Vector2.new(lateralInput, 0)
end
function SlideController:_getCombinedFlyInputVector()
	local config = self:_getAirControlConfig()
	if not config.enabled then
		return Vector2.zero
	end

	local combinedInput = (self._flyKeyboardInput * config.keyboardInfluence)
		+ self._flyTouchInput
		+ self:_getFlyButtonInputVector()
	return Vector2.new(math.clamp(combinedInput.X, -1, 1), 0)
end

function SlideController:_updateFlyLateralControl(rootPart, deltaTime)
	local airControlConfig = self:_getAirControlConfig()
	if not airControlConfig.enabled or not (rootPart and rootPart.Parent) then
		self._flyLateralVelocity = Vector3.zero
		self._flyControlVelocity = Vector3.zero
		return
	end

	local _, rightDirection = self:_getLaunchTrajectoryPlanarBasis(rootPart)
	if not rightDirection then
		self._flyLateralVelocity = Vector3.zero
		self._flyControlVelocity = Vector3.zero
		return
	end

	local lateralInput = self:_getCombinedFlyInputVector().X
	local targetVelocity = Vector3.zero
	if math.abs(lateralInput) > MIN_DIRECTION_MAGNITUDE then
		targetVelocity = rightDirection * (airControlConfig.maxSpeed * lateralInput)
	end

	local currentVelocity = self._flyControlVelocity or Vector3.zero
	local stepAcceleration = airControlConfig.acceleration
	if targetVelocity.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		stepAcceleration = airControlConfig.deceleration
	elseif currentVelocity.Magnitude > MIN_DIRECTION_MAGNITUDE then
		local alignment = math.clamp(currentVelocity.Unit:Dot(targetVelocity.Unit), -1, 1)
		local turnBoost = 1 + ((1 - alignment) * 0.5 * airControlConfig.turnResponsiveness)
		stepAcceleration *= turnBoost
	end

	self._flyControlVelocity = moveTowardsVector3(currentVelocity, targetVelocity, math.max(0, stepAcceleration * deltaTime))
	self._flyLateralVelocity = flattenVector(self._flyControlVelocity)
end

function SlideController:_updateLaunchFlightControls(humanoid, rootPart, deltaTime)
	if not self._isLaunchFlightActive then
		self:_stopBulletTime(rootPart, false)
		self._flyLateralVelocity = Vector3.zero
		self._flyControlVelocity = Vector3.zero
		self:_setFlyButtonVisible(false)
		self:_setGameplayUiHidden(false)
		return
	end

	local flyButtonRoot, _, _, _, landButton = self:_ensureFlyButtonBindings()
	self:_ensureAirControlInputBindings()

	if self._isFastLandingActive then
		self:_stopBulletTime(rootPart, false)
		self:_setFlyButtonVisible(false)
		self:_setGameplayUiHidden(true)
		self:_applyFastLandingVelocity(rootPart, deltaTime)
		return
	end

	local isAirborne = humanoid
		and rootPart
		and humanoid.FloorMaterial == Enum.Material.Air
	if not isAirborne then
		self:_stopBulletTime(rootPart, false)
		self:_clearFlyButtonInputState()
		self:_setGameplayUiHidden(true)
		if flyButtonRoot and landButton then
			flyButtonRoot.Visible = true
			self:_applyFlyButtonPlatformVisibility()
		else
			self:_setFlyButtonVisible(false)
		end
		return
	end

	self:_setGameplayUiHidden(true)
	self:_stopBulletTime(rootPart, false)
	if flyButtonRoot and landButton then
		self:_setFlyButtonVisible(true)
	else
		self:_setFlyButtonVisible(false)
	end
	self:_updateFlyLateralControl(rootPart, deltaTime or 0)
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
		local currentGroundPart = self:_getTrackedSlideGroundPart(rootPart) or self:_getGroundPart(rootPart)
		local slidePart = self:_isSlideSurfacePart(currentGroundPart) and currentGroundPart or self:_resolveSlideSurfacePart()
		forwardDirection = self:_getDownhillDirection(slidePart) or flattenVector(rootPart.AssemblyLinearVelocity)
	end
	if not forwardDirection or forwardDirection.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		return false
	end
	forwardDirection = forwardDirection.Unit

	local currentVelocity = rootPart.AssemblyLinearVelocity
	local currentForwardSpeed = math.max(0, flattenVector(currentVelocity):Dot(forwardDirection))
	local slideSpeedAtLaunch = math.max(currentForwardSpeed, self._slideSpeed)
	local launchHorizontalSpeed = slideSpeedAtLaunch
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
	self:_recordStudioLaunchDebug(targetVelocity, effectiveLaunchPower, slideSpeedAtLaunch)

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
	self:_startLaunchNoGravity(rootPart)
	self:_leaveSlide(humanoid)
	self:_startLaunchFlight(rootPart)
	self:_updateLaunchFlightAnimation(humanoid, rootPart)
	return true
end

function SlideController:_onHeartbeat(deltaTime)
	local humanoid, rootPart = self:_ensureCharacterContext()
	if not humanoid or not rootPart or self:_shouldSkipCurrentState(humanoid) then
		self:_setGameplayUiHidden(false)
		self:_stopLandingShake()
		self:_stopLaunchFlight(rootPart)
		self:_stopLaunchNoGravity()
		self:_clearLaunchMomentum()
		self:_leaveSlide(humanoid)
		return
	end

	self:_updateLaunchNoGravity(humanoid, rootPart)

	local collisionPart = self:_consumePendingLaunchFlightCollision()
	if self:_abortLaunchFlightFromCollision(humanoid, rootPart, collisionPart) then
		self:_leaveSlide(humanoid)
		return
	end

	local shouldKeepLaunchFlight = self:_shouldKeepLaunchFlight(humanoid, rootPart)
	local groundPart = self:_getGroundPart(rootPart)
	local shouldPlayLaunchLandingImpact = (self._isLaunchFlightActive or self._pendingLaunchLandingImpact)
		and humanoid.FloorMaterial ~= Enum.Material.Air
		and groundPart ~= nil
	local trackedGroundPart = self:_getTrackedSlideGroundPart(rootPart) or groundPart
	local isOnLaunchPart = self:_isLaunchPart(trackedGroundPart)
	if self._isSliding and isOnLaunchPart then
		if self:_launchFromUp(humanoid, rootPart) then
			return
		end
	end

	local slidePart = nil
	if not shouldKeepLaunchFlight then
		-- Once launch flight starts, ignore slide raycasts so we do not snap back to slide mid-air.
		slidePart = self:_isSlideSurfacePart(trackedGroundPart) and trackedGroundPart or nil
		if not slidePart and not self._isSliding then
			local touchedPart = self:_consumeTouchedSlidePart()
			if touchedPart and touchedPart.Parent and self:_isSlideSurfacePart(touchedPart) then
				slidePart = touchedPart
			end
		end
	end
	if slidePart then
		if shouldPlayLaunchLandingImpact then
			self:_playLandingSound(rootPart)
			self:_playLandingBurst(rootPart)
			self:_playLandingShake()
			self:_stabilizeLanding(humanoid, rootPart)
			self._pendingLaunchLandingImpact = false
		end
		self:_stopLaunchFlight(rootPart)
		self:_clearLaunchMomentum()
		local downhillDirection = self:_getDownhillDirection(slidePart)
		if downhillDirection then
			self:_setSlidingActive(humanoid, true)
			humanoid.Jump = false
			self:_updateSlidingVelocity(rootPart, downhillDirection, deltaTime)
			return
		end
	end

	local shouldKeepLaunchMomentum = shouldKeepLaunchFlight
		or self:_shouldKeepLaunchMomentum(groundPart, slidePart, isOnLaunchPart and trackedGroundPart or nil)
	if self._isFastLandingActive then
		shouldKeepLaunchMomentum = false
	end

	if shouldKeepLaunchFlight then
		self:_updateLaunchFlightAnimation(humanoid, rootPart)
		self:_updateLaunchFlightControls(humanoid, rootPart, deltaTime)
		local progressRatio = self:_computeFlightProgressRatio(rootPart.Position)
		if progressRatio ~= nil then
			self:_setMainProgressFlightOverride(true, progressRatio)
		end
	else
		if shouldPlayLaunchLandingImpact then
			self:_playLandingSound(rootPart)
			self:_playLandingBurst(rootPart)
			self:_playLandingShake()
			self:_stabilizeLanding(humanoid, rootPart)
			self:_playLandingAnimation(humanoid)
			self._pendingLaunchLandingImpact = false
		end
		self:_setGameplayUiHidden(false)
		self:_stopLaunchFlight(rootPart)
	end

	if shouldKeepLaunchMomentum then
		self:_applyLaunchMomentum(rootPart)
	else
		self:_clearLaunchMomentum()
	end

	self:_leaveSlide(humanoid)
end

function SlideController:Start()
	self:_resolveSlideRoot()
	self:_attachCharacter(localPlayer.Character)
	self:_ensureFlyButtonBindings()
	self:_ensureAirControlInputBindings()

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
