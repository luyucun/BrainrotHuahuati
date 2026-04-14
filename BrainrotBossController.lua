--[[
鑴氭湰鍚嶅瓧: BrainrotBossController
鑴氭湰鏂囦欢: BrainrotBossController.lua
鑴氭湰绫诲瀷: ModuleScript
Studio鏀剧疆璺緞: StarterPlayer/StarterPlayerScripts/Controllers/BrainrotBossController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
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
        "[BrainrotBossController] Missing shared module %s (expected in ReplicatedStorage/Shared or ReplicatedStorage root)",
        moduleName
    ))
end

local GameConfig = requireSharedModule("GameConfig")
local RemoteNames = requireSharedModule("RemoteNames")
local BOSS_RUNTIME_ATTRIBUTE = "BrainrotBossRuntime"
local BOSS_TARGET_POSITION_ATTRIBUTE = "BrainrotBossTargetPosition"
local BOSS_TARGET_LOOK_VECTOR_ATTRIBUTE = "BrainrotBossTargetLookVector"
local BOSS_STATE_ATTRIBUTE = "BrainrotBossState"
local BOSS_SERVER_UPDATED_AT_ATTRIBUTE = "BrainrotBossServerUpdatedAt"
local WARNING_SOUND_TEMPLATE_FOLDER_NAME = "BGM"
local WARNING_SOUND_TEMPLATE_NAME = "Warning two"
local WARNING_SOUND_ASSET_ID = "rbxassetid://120285011638501"
local WARNING_SOUND_FALLBACK_NAME = "_BrainrotBossWarningFallback"
local NORMALIZED_WARNING_SOUND_ASSET_ID = string.lower(WARNING_SOUND_ASSET_ID)
local CHASE_OVERLAY_GUI_NAME = "BossChaseOverlay"
local CHASE_OVERLAY_ROOT_NAME = "Overlay"

local BrainrotBossController = {}
BrainrotBossController.__index = BrainrotBossController

local function getSharedClock()
    local ok, serverNow = pcall(function()
        return Workspace:GetServerTimeNow()
    end)
    if ok and type(serverNow) == "number" then
        return serverNow
    end

    return os.clock()
end

local function formatCountdownText(remainingSeconds)
    local safeRemaining = math.max(0, tonumber(remainingSeconds) or 0)
    return string.format("%.1fS", safeRemaining)
end

local function setGuiVisible(node, visible)
    if not node then
        return
    end

    if node:IsA("ScreenGui") then
        node.Enabled = visible
    elseif node:IsA("GuiObject") then
        node.Visible = visible
    end
end

local function resolveSoundTemplate(soundFolderName, soundName)
    local soundFolder = SoundService:FindFirstChild(soundFolderName)
    local soundTemplate = soundFolder and (soundFolder:FindFirstChild(soundName) or soundFolder:FindFirstChild(soundName, true)) or nil
    if soundTemplate and soundTemplate:IsA("Sound") then
        return soundTemplate
    end

    return nil
end

local function collectGuiDescendantsByName(root, targetName)
    local result = {}
    if not root then
        return result
    end

    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant.Name == targetName and descendant:IsA("GuiObject") then
            table.insert(result, descendant)
        end
    end

    return result
end

local function ensureOverlayEdge(parent, edgeName, rotation)
    local edge = parent:FindFirstChild(edgeName)
    if edge and not edge:IsA("Frame") then
        edge:Destroy()
        edge = nil
    end

    if not edge then
        edge = Instance.new("Frame")
        edge.Name = edgeName
        edge.BorderSizePixel = 0
        edge.BackgroundTransparency = 1
        edge.ZIndex = 10
        edge.Parent = parent
    end

    local gradient = edge:FindFirstChild("Fade")
    if gradient and not gradient:IsA("UIGradient") then
        gradient:Destroy()
        gradient = nil
    end

    if not gradient then
        gradient = Instance.new("UIGradient")
        gradient.Name = "Fade"
        gradient.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(1, 1),
        })
        gradient.Parent = edge
    end

    gradient.Rotation = rotation
    return edge
end

local function getBossRuntimeFolderName()
    return tostring((GameConfig.BRAINROT or {}).WorldSpawnBossRuntimeFolderName or "WorldSpawnBosses")
end

local function getBossChaseOverlayConfig()
    local config = GameConfig.BRAINROT or {}
    local minTransparency = math.clamp(tonumber(config.BossChaseOverlayMinTransparency) or 0.28, 0, 1)
    local maxTransparency = math.clamp(tonumber(config.BossChaseOverlayMaxTransparency) or 0.82, 0, 1)
    if minTransparency > maxTransparency then
        minTransparency, maxTransparency = maxTransparency, minTransparency
    end

    return {
        enabled = config.BossChaseOverlayEnabled ~= false,
        color = typeof(config.BossChaseOverlayColor) == "Color3"
            and config.BossChaseOverlayColor
            or Color3.fromRGB(255, 60, 60),
        thicknessScale = math.clamp(tonumber(config.BossChaseOverlayThicknessScale) or 0.22, 0.08, 0.4),
        minTransparency = minTransparency,
        maxTransparency = maxTransparency,
        pulseSpeed = math.max(0.1, tonumber(config.BossChaseOverlayPulseSpeed) or 5.6),
    }
end

local function getMusicFolderName()
    local settingsConfig = GameConfig.SETTINGS or {}
    return tostring(settingsConfig.MusicFolderName or "BGM")
end

local function getFloatLandFolderPrefix()
    return tostring(GameConfig.FloatLandFolderPrefix or "FloatLand")
end

local function getFloatLandCount()
    return math.max(0, math.floor(tonumber(GameConfig.FloatLandCount) or 9))
end

local function getFloatLandMainPartName()
    return tostring(GameConfig.FloatLandPartName or "Land")
end

local function isPointInsidePartHorizontalBounds(part, worldPoint)
    if not (part and part:IsA("BasePart") and typeof(worldPoint) == "Vector3") then
        return false
    end

    local localPoint = part.CFrame:PointToObjectSpace(worldPoint)
    local halfSize = part.Size * 0.5
    return math.abs(localPoint.X) <= halfSize.X
        and math.abs(localPoint.Z) <= halfSize.Z
end


local function getHorizontalLookVector(rawLookVector, fallbackLookVector)
    local candidate = typeof(rawLookVector) == "Vector3"
        and Vector3.new(rawLookVector.X, 0, rawLookVector.Z)
        or Vector3.zero
    if candidate.Magnitude > 0.001 then
        return candidate.Unit
    end

    local fallback = typeof(fallbackLookVector) == "Vector3"
        and Vector3.new(fallbackLookVector.X, 0, fallbackLookVector.Z)
        or Vector3.new(0, 0, -1)
    if fallback.Magnitude > 0.001 then
        return fallback.Unit
    end

    return Vector3.new(0, 0, -1)
end

local function buildBossTargetCFrame(position, lookVector, fallbackLookVector)
    local targetPosition = typeof(position) == "Vector3" and position or Vector3.zero
    local horizontalLook = getHorizontalLookVector(lookVector, fallbackLookVector)
    return CFrame.lookAt(targetPosition, targetPosition + horizontalLook, Vector3.new(0, 1, 0))
end

function BrainrotBossController.new(modalController)
    local self = setmetatable({}, BrainrotBossController)
    self._modalController = modalController
    self._bossStateSyncEvent = nil
    self._requestDropCarriedWorldBrainrotEvent = nil
    self._bossWarningEvent = nil
    self._requestQuickTeleportEvent = nil
    self._dropRoot = nil
    self._dropButton = nil
    self._homeButton = nil
    self._countdownLabel = nil
    self._homeReadyNodes = {}
    self._homeLockedNodes = {}
    self._warningRoot = nil
    self._warningText = nil
    self._topRoot = nil
    self._dropButtonConnection = nil
    self._homeButtonConnection = nil
    self._warningAlpha = 1
    self._warningSerial = 0
    self._warningSoundSerial = 0
    self._homeEnabled = false
    self._topHiddenByCarry = false
    self._started = false
    self._updateInterval = math.max(0.05, tonumber((GameConfig.BRAINROT or {}).BossTickInterval) or 0.1)
    self._bossRuntimeFolderName = getBossRuntimeFolderName()
    self._bossRuntimeFolder = nil
    self._trackedBosses = {}
    self._bossVisualSmoothingEnabled = (GameConfig.BRAINROT or {}).BossClientVisualSmoothingEnabled ~= false
    self._bossInterpolationWindow = math.max(
        1 / 120,
        tonumber((GameConfig.BRAINROT or {}).BossClientVisualInterpolationWindow)
            or tonumber((GameConfig.BRAINROT or {}).BossTickInterval)
            or 0.1
    )
    self._bossSnapDistance = math.max(1, tonumber((GameConfig.BRAINROT or {}).BossClientVisualSnapDistance) or 8)
    self._bossRenderConnection = nil
    self._warningSoundTemplate = nil
    self._didWarnMissingWarningSound = false
    self._bossChaseOverlayGui = nil
    self._bossChaseOverlayRoot = nil
    self._bossChaseOverlayEdges = {}
    self._bossChaseOverlayPulseClock = 0
    self._musicFolder = nil
    self._suppressedBgmStatesBySound = setmetatable({}, { __mode = "k" })
    self._isBgmSuppressed = false
    self._state = {
        visible = false,
        carriedCount = 0,
        homeUnlockAt = 0,
        isChased = false,
    }
    self._homeDefaultBackgroundColor = nil
    self._homeDefaultTextColor = nil
    self._countdownDefaultTextColor = nil
    self._floatLandAirwallByLevel = {}
    self._activeAirwallLevel = nil
    self._isAirwallLockActive = false
    self._characterAddedConnection = nil
    return self
end

function BrainrotBossController:_getCharacterRootPart()
    local character = localPlayer.Character
    if not character then
        return nil
    end

    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
        return humanoidRootPart
    end

    if character.PrimaryPart and character.PrimaryPart:IsA("BasePart") then
        return character.PrimaryPart
    end

    return character:FindFirstChildWhichIsA("BasePart")
end

function BrainrotBossController:_ensureFloatLandAirwallCache()
    local landRoot = Workspace:FindFirstChild("Land")
    if not landRoot then
        self._floatLandAirwallByLevel = {}
        return false
    end

    local cache = {}
    local folderPrefix = getFloatLandFolderPrefix()
    local landPartName = getFloatLandMainPartName()

    for level = 1, getFloatLandCount() do
        local levelFolder = landRoot:FindFirstChild(string.format("%s%d", folderPrefix, level))
        local landPart = levelFolder and levelFolder:FindFirstChild(landPartName)
        local airwallFolder = levelFolder and levelFolder:FindFirstChild("Airwall")
        local parts = {}

        if airwallFolder then
            for _, child in ipairs(airwallFolder:GetChildren()) do
                if child:IsA("BasePart") then
                    table.insert(parts, child)
                end
            end
        end

        if landPart and landPart:IsA("BasePart") and #parts > 0 then
            cache[level] = {
                LandPart = landPart,
                Parts = parts,
            }
        end
    end

    self._floatLandAirwallByLevel = cache
    return next(cache) ~= nil
end

function BrainrotBossController:_setAirwallCanCollideForLevel(level, enabled)
    local entry = self._floatLandAirwallByLevel[level]
    if type(entry) ~= "table" then
        return
    end

    for _, part in ipairs(entry.Parts or {}) do
        if part and part.Parent and part:IsA("BasePart") then
            part.CanCollide = enabled == true
        end
    end
end

function BrainrotBossController:_setAllAirwallCanCollide(enabled)
    for level in pairs(self._floatLandAirwallByLevel) do
        self:_setAirwallCanCollideForLevel(level, enabled)
    end
end

function BrainrotBossController:_resolveFloatLandLevelFromPosition(worldPosition)
    if typeof(worldPosition) ~= "Vector3" then
        return nil
    end

    local nearestLevel = nil
    local nearestDistance = nil
    local horizontalPoint = Vector2.new(worldPosition.X, worldPosition.Z)

    for level, entry in pairs(self._floatLandAirwallByLevel) do
        local landPart = type(entry) == "table" and entry.LandPart or nil
        if landPart and landPart.Parent and landPart:IsA("BasePart") then
            if isPointInsidePartHorizontalBounds(landPart, worldPosition) then
                return level
            end

            local landHorizontalPoint = Vector2.new(landPart.Position.X, landPart.Position.Z)
            local horizontalDistance = (horizontalPoint - landHorizontalPoint).Magnitude
            if nearestDistance == nil or horizontalDistance < nearestDistance then
                nearestDistance = horizontalDistance
                nearestLevel = level
            end
        end
    end

    return nearestLevel
end

function BrainrotBossController:_updateLocalAirwallCollision()
    local shouldLock = self._state.visible == true
        and (tonumber(self._state.carriedCount) or 0) > 0
        and getSharedClock() < math.max(0, tonumber(self._state.homeUnlockAt) or 0)

    if not self:_ensureFloatLandAirwallCache() then
        self._activeAirwallLevel = nil
        self._isAirwallLockActive = false
        return
    end

    if not shouldLock then
        self:_setAllAirwallCanCollide(false)
        self._activeAirwallLevel = nil
        self._isAirwallLockActive = false
        return
    end

    if not self._isAirwallLockActive or type(self._activeAirwallLevel) ~= "number" then
        local rootPart = self:_getCharacterRootPart()
        self._activeAirwallLevel = rootPart and self:_resolveFloatLandLevelFromPosition(rootPart.Position) or nil
        self._isAirwallLockActive = true
    end

    self:_setAllAirwallCanCollide(false)
    if type(self._activeAirwallLevel) == "number" then
        self:_setAirwallCanCollideForLevel(self._activeAirwallLevel, true)
    end
end

function BrainrotBossController:_getPlayerGui()
    return localPlayer:FindFirstChildOfClass("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
end

function BrainrotBossController:_ensureBossChaseOverlay()
    local overlayConfig = getBossChaseOverlayConfig()
    if overlayConfig.enabled ~= true then
        return false
    end

    local playerGui = self:_getPlayerGui()
    if not playerGui then
        return false
    end

    local overlayGui = self._bossChaseOverlayGui
    if not (overlayGui and overlayGui.Parent == playerGui and overlayGui:IsA("ScreenGui")) then
        overlayGui = playerGui:FindFirstChild(CHASE_OVERLAY_GUI_NAME)
        if overlayGui and not overlayGui:IsA("ScreenGui") then
            overlayGui:Destroy()
            overlayGui = nil
        end

        if not overlayGui then
            overlayGui = Instance.new("ScreenGui")
            overlayGui.Name = CHASE_OVERLAY_GUI_NAME
            overlayGui.ResetOnSpawn = false
            overlayGui.IgnoreGuiInset = true
            overlayGui.DisplayOrder = 90
            overlayGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            overlayGui.Parent = playerGui
        end

        self._bossChaseOverlayGui = overlayGui
    end

    local root = overlayGui:FindFirstChild(CHASE_OVERLAY_ROOT_NAME)
    if root and not root:IsA("Frame") then
        root:Destroy()
        root = nil
    end

    if not root then
        root = Instance.new("Frame")
        root.Name = CHASE_OVERLAY_ROOT_NAME
        root.BackgroundTransparency = 1
        root.BorderSizePixel = 0
        root.Size = UDim2.fromScale(1, 1)
        root.ZIndex = 9
        root.Visible = false
        root.Parent = overlayGui
    end

    root.Position = UDim2.fromScale(0, 0)
    root.Size = UDim2.fromScale(1, 1)

    local topEdge = ensureOverlayEdge(root, "Top", 90)
    local bottomEdge = ensureOverlayEdge(root, "Bottom", 270)
    local leftEdge = ensureOverlayEdge(root, "Left", 0)
    local rightEdge = ensureOverlayEdge(root, "Right", 180)
    local thicknessScale = overlayConfig.thicknessScale

    topEdge.AnchorPoint = Vector2.new(0.5, 0)
    topEdge.Position = UDim2.fromScale(0.5, 0)
    topEdge.Size = UDim2.fromScale(1, thicknessScale)

    bottomEdge.AnchorPoint = Vector2.new(0.5, 1)
    bottomEdge.Position = UDim2.fromScale(0.5, 1)
    bottomEdge.Size = UDim2.fromScale(1, thicknessScale)

    leftEdge.AnchorPoint = Vector2.new(0, 0.5)
    leftEdge.Position = UDim2.fromScale(0, 0.5)
    leftEdge.Size = UDim2.fromScale(thicknessScale, 1)

    rightEdge.AnchorPoint = Vector2.new(1, 0.5)
    rightEdge.Position = UDim2.fromScale(1, 0.5)
    rightEdge.Size = UDim2.fromScale(thicknessScale, 1)

    self._bossChaseOverlayRoot = root
    self._bossChaseOverlayEdges = {
        topEdge,
        bottomEdge,
        leftEdge,
        rightEdge,
    }

    for _, edge in ipairs(self._bossChaseOverlayEdges) do
        edge.BackgroundColor3 = overlayConfig.color
    end

    return true
end

function BrainrotBossController:_setBossChaseOverlayVisible(visible)
    local root = self._bossChaseOverlayRoot
    if root and root.Parent and root:IsA("GuiObject") then
        root.Visible = visible == true
    end
end

function BrainrotBossController:_setBossChaseOverlayTransparency(transparency)
    local resolvedTransparency = math.clamp(tonumber(transparency) or 1, 0, 1)
    for _, edge in ipairs(self._bossChaseOverlayEdges or {}) do
        if edge and edge.Parent and edge:IsA("Frame") then
            edge.BackgroundTransparency = resolvedTransparency
        end
    end
end

function BrainrotBossController:_updateBossChaseOverlay(deltaTime)
    local overlayConfig = getBossChaseOverlayConfig()
    if overlayConfig.enabled ~= true or self._state.isChased ~= true then
        self._bossChaseOverlayPulseClock = 0
        self:_setBossChaseOverlayVisible(false)
        return
    end

    if not self:_ensureBossChaseOverlay() then
        return
    end

    self._bossChaseOverlayPulseClock += math.max(0, tonumber(deltaTime) or 0)
    local pulse = 0.5 + (math.sin(self._bossChaseOverlayPulseClock * overlayConfig.pulseSpeed) * 0.5)
    local transparencyRange = overlayConfig.maxTransparency - overlayConfig.minTransparency
    local targetTransparency = overlayConfig.maxTransparency - (transparencyRange * pulse)

    self:_setBossChaseOverlayVisible(true)
    self:_setBossChaseOverlayTransparency(targetTransparency)
end

function BrainrotBossController:_getWarningSoundTemplate()
    if self._warningSoundTemplate and self._warningSoundTemplate.Parent then
        return self._warningSoundTemplate
    end

    local soundTemplate = resolveSoundTemplate(WARNING_SOUND_TEMPLATE_FOLDER_NAME, WARNING_SOUND_TEMPLATE_NAME)
    if soundTemplate then
        self._warningSoundTemplate = soundTemplate
        return soundTemplate
    end

    if not self._didWarnMissingWarningSound then
        warn(string.format(
            "[BrainrotBossController] 找不到 SoundService/%s/%s，使用回退音频资源。",
            WARNING_SOUND_TEMPLATE_FOLDER_NAME,
            WARNING_SOUND_TEMPLATE_NAME
        ))
        self._didWarnMissingWarningSound = true
    end

    local fallbackSound = SoundService:FindFirstChild(WARNING_SOUND_FALLBACK_NAME, true)
    if fallbackSound and fallbackSound:IsA("Sound") then
        self._warningSoundTemplate = fallbackSound
        return fallbackSound
    end

    local soundFolder = SoundService:FindFirstChild(WARNING_SOUND_TEMPLATE_FOLDER_NAME)
    fallbackSound = Instance.new("Sound")
    fallbackSound.Name = WARNING_SOUND_FALLBACK_NAME
    fallbackSound.SoundId = WARNING_SOUND_ASSET_ID
    fallbackSound.Volume = 1
    fallbackSound.Parent = soundFolder or SoundService
    self._warningSoundTemplate = fallbackSound
    return fallbackSound
end

function BrainrotBossController:_playWarningSoundOnce()
    local template = self:_getWarningSoundTemplate()
    if not template then
        return nil
    end

    local soundToPlay = template:Clone()
    soundToPlay.Looped = false
    soundToPlay.Parent = template.Parent or SoundService
    if soundToPlay.SoundId == "" then
        soundToPlay.SoundId = WARNING_SOUND_ASSET_ID
    end
    soundToPlay:Play()

    task.delay(math.max(4, (tonumber(soundToPlay.TimeLength) or 0) + 1), function()
        if soundToPlay and soundToPlay.Parent then
            soundToPlay:Destroy()
        end
    end)

    return soundToPlay
end

function BrainrotBossController:_playWarningSoundTwice()
    self._warningSoundSerial += 1
    local serial = self._warningSoundSerial

    task.spawn(function()
        for playIndex = 1, 2 do
            if serial ~= self._warningSoundSerial then
                return
            end

            local soundToPlay = self:_playWarningSoundOnce()
            if playIndex < 2 then
                local waitSeconds = tonumber(soundToPlay and soundToPlay.TimeLength) or 0
                task.wait(waitSeconds > 0.05 and waitSeconds or 0.75)
            end
        end
    end)
end

function BrainrotBossController:_getMusicFolder()
    local musicFolder = self._musicFolder
    if musicFolder and musicFolder.Parent then
        return musicFolder
    end

    musicFolder = SoundService:FindFirstChild(getMusicFolderName())
    if musicFolder then
        self._musicFolder = musicFolder
        return musicFolder
    end

    self._musicFolder = nil
    return nil
end

function BrainrotBossController:_isWarningMusicSound(sound)
    if not (sound and sound:IsA("Sound")) then
        return false
    end

    local normalizedSoundId = string.lower(tostring(sound.SoundId or ""))
    return sound.Name == WARNING_SOUND_TEMPLATE_NAME
        or sound.Name == WARNING_SOUND_FALLBACK_NAME
        or normalizedSoundId == NORMALIZED_WARNING_SOUND_ASSET_ID
end

function BrainrotBossController:_shouldSuppressBgm()
    local carriedCount = math.max(0, math.floor(tonumber(self._state.carriedCount) or 0))
    local remaining = math.max(0, (tonumber(self._state.homeUnlockAt) or 0) - getSharedClock())
    if carriedCount > 0 then
        return remaining > 0
    end

    return self._state.isChased == true
end

function BrainrotBossController:_suppressActiveBgm()
    local musicFolder = self:_getMusicFolder()
    if not musicFolder then
        return
    end

    self._isBgmSuppressed = true

    for _, descendant in ipairs(musicFolder:GetDescendants()) do
        if descendant:IsA("Sound") and not self:_isWarningMusicSound(descendant) and descendant.IsPlaying then
            local pausedTimePosition = 0
            pcall(function()
                pausedTimePosition = descendant.TimePosition
            end)

            self._suppressedBgmStatesBySound[descendant] = {
                TimePosition = math.max(0, tonumber(pausedTimePosition) or 0),
            }

            pcall(function()
                descendant:Stop()
            end)
        end
    end
end

function BrainrotBossController:_resumeSuppressedBgm()
    if not self._isBgmSuppressed and next(self._suppressedBgmStatesBySound) == nil then
        return
    end

    for sound, soundState in pairs(self._suppressedBgmStatesBySound) do
        self._suppressedBgmStatesBySound[sound] = nil

        if sound
            and sound.Parent
            and sound:IsA("Sound")
            and not sound.IsPlaying
            and not self:_isWarningMusicSound(sound)
            and math.max(0, tonumber(sound.Volume) or 0) > 0
        then
            local resumeTimePosition = math.max(0, tonumber(soundState and soundState.TimePosition) or 0)
            pcall(function()
                sound.TimePosition = resumeTimePosition
            end)
            pcall(function()
                sound:Play()
            end)
        end
    end

    self._isBgmSuppressed = false
end

function BrainrotBossController:_refreshChaseBgmSuppression()
    if self:_shouldSuppressBgm() then
        self:_suppressActiveBgm()
        return
    end

    self:_resumeSuppressedBgm()
end


function BrainrotBossController:_disconnectButtonConnections()
    if self._dropButtonConnection then
        self._dropButtonConnection:Disconnect()
        self._dropButtonConnection = nil
    end
    if self._homeButtonConnection then
        self._homeButtonConnection:Disconnect()
        self._homeButtonConnection = nil
    end
end

function BrainrotBossController:_bindButtons()
    self:_disconnectButtonConnections()

    if self._dropButton then
        self._dropButtonConnection = self._dropButton.Activated:Connect(function()
            if self._requestDropCarriedWorldBrainrotEvent then
                self._requestDropCarriedWorldBrainrotEvent:FireServer()
            end
        end)
    end

    if self._homeButton then
        self._homeButtonConnection = self._homeButton.Activated:Connect(function()
            if not self._homeEnabled then
                return
            end

            if self._requestQuickTeleportEvent then
                self._requestQuickTeleportEvent:FireServer({
                    target = "Home",
                })
            end
        end)
    end
end

function BrainrotBossController:_ensureUiNodes()
    local playerGui = self:_getPlayerGui()
    if not playerGui then
        return false
    end

    local mainGui = playerGui:FindFirstChild("Main")
    if not mainGui then
        return false
    end

    local dropRoot = mainGui:FindFirstChild("Drop", true)
    local dropButton = dropRoot and dropRoot:FindFirstChild("DropButton", true) or nil
    local homeButton = dropRoot and dropRoot:FindFirstChild("Home", true) or nil
    local countdownLabel = homeButton and homeButton:FindFirstChild("CountDownTime", true) or nil
    local homeReadyNodes = collectGuiDescendantsByName(homeButton, "Home")
    local homeLockedNodes = collectGuiDescendantsByName(homeButton, "NoHome")
    local warningRoot = mainGui:FindFirstChild("Warning", true)
    local warningText = warningRoot and warningRoot:FindFirstChild("Text", true) or nil
    local topRoot = mainGui:FindFirstChild("Top") or mainGui:FindFirstChild("Top", true)

    local didChange = dropRoot ~= self._dropRoot
        or dropButton ~= self._dropButton
        or homeButton ~= self._homeButton
        or countdownLabel ~= self._countdownLabel
        or warningRoot ~= self._warningRoot
        or warningText ~= self._warningText
        or topRoot ~= self._topRoot

    self._dropRoot = dropRoot
    self._dropButton = dropButton
    self._homeButton = homeButton
    self._countdownLabel = countdownLabel
    self._homeReadyNodes = homeReadyNodes
    self._homeLockedNodes = homeLockedNodes
    self._warningRoot = warningRoot
    self._warningText = warningText
    self._topRoot = topRoot

    if self._homeButton and not self._homeDefaultBackgroundColor then
        self._homeDefaultBackgroundColor = self._homeButton.BackgroundColor3
        self._homeDefaultTextColor = self._homeButton.TextColor3
    end
    if self._countdownLabel and not self._countdownDefaultTextColor then
        self._countdownDefaultTextColor = self._countdownLabel.TextColor3
    end

    if didChange then
        self:_bindButtons()
        setGuiVisible(self._warningRoot, false)
        self:_setWarningAlpha(1)
    end

    return self._dropRoot ~= nil
end

function BrainrotBossController:_setTopVisible(visible)
    if self._topRoot and self._topRoot:IsA("GuiObject") then
        self._topRoot.Visible = visible == true
    end
end

function BrainrotBossController:_isTopHiddenByModal()
    return self._modalController
        and type(self._modalController.IsNodeHiddenByModal) == "function"
        and self._modalController:IsNodeHiddenByModal(self._topRoot)
end

function BrainrotBossController:_refreshTopVisibility()
    self:_ensureUiNodes()
    if not (self._topRoot and self._topRoot:IsA("GuiObject")) then
        return
    end

    local carriedCount = math.max(0, math.floor(tonumber(self._state.carriedCount) or 0))
    local homeUnlockAt = math.max(0, tonumber(self._state.homeUnlockAt) or 0)
    local shouldHideTop = carriedCount > 0 and (homeUnlockAt - getSharedClock()) > 0

    if shouldHideTop then
        self._topHiddenByCarry = true
        self:_setTopVisible(false)
        return
    end

    if self._topHiddenByCarry and not self:_isTopHiddenByModal() then
        self._topHiddenByCarry = false
        self:_setTopVisible(true)
    end
end

function BrainrotBossController:_applyHomeAvailabilityVisuals(isUnlocked, showCountdown)
    local shouldShowHome = isUnlocked == true
    local shouldShowCountdown = showCountdown == true

    for _, node in ipairs(self._homeReadyNodes or {}) do
        setGuiVisible(node, shouldShowHome)
    end

    for _, node in ipairs(self._homeLockedNodes or {}) do
        setGuiVisible(node, not shouldShowHome)
    end

    if self._countdownLabel then
        setGuiVisible(self._countdownLabel, shouldShowCountdown)
    end
end

function BrainrotBossController:_applyHomeButtonEnabled(enabled)
    self._homeEnabled = enabled == true
    if not self._homeButton then
        return
    end

    local backgroundColor = self._homeDefaultBackgroundColor or self._homeButton.BackgroundColor3
    local textColor = self._homeDefaultTextColor or self._homeButton.TextColor3
    local countdownTextColor = self._countdownDefaultTextColor or (self._countdownLabel and self._countdownLabel.TextColor3) or textColor

    self._homeButton.Active = self._homeEnabled
    self._homeButton.AutoButtonColor = self._homeEnabled
    self._homeButton.Selectable = self._homeEnabled
    self._homeButton.BackgroundColor3 = self._homeEnabled and backgroundColor or Color3.fromRGB(110, 110, 110)
    self._homeButton.TextColor3 = self._homeEnabled and textColor or Color3.fromRGB(220, 220, 220)

    if self._countdownLabel then
        self._countdownLabel.TextColor3 = self._homeEnabled and countdownTextColor or Color3.fromRGB(220, 220, 220)
    end
end

function BrainrotBossController:_refreshDropUi()
    self:_updateLocalAirwallCollision()
    self:_ensureUiNodes()
    self:_refreshTopVisibility()
    if not self._dropRoot then
        return
    end

    local shouldShow = self._state.visible == true and (tonumber(self._state.carriedCount) or 0) > 0
    setGuiVisible(self._dropRoot, shouldShow)

    if not shouldShow then
        self:_applyHomeButtonEnabled(false)
        self:_applyHomeAvailabilityVisuals(false, false)
        if self._countdownLabel then
            self._countdownLabel.Text = ""
        end
        self:_refreshTopVisibility()
        return
    end

    local remaining = math.max(0, (tonumber(self._state.homeUnlockAt) or 0) - getSharedClock())
    local isUnlocked = remaining <= 0
    self:_applyHomeButtonEnabled(isUnlocked)
    self:_applyHomeAvailabilityVisuals(isUnlocked, not isUnlocked)
    if self._countdownLabel then
        self._countdownLabel.Text = isUnlocked and "" or formatCountdownText(remaining)
    end
    self:_refreshTopVisibility()
end


function BrainrotBossController:_setWarningAlpha(alpha)
    self._warningAlpha = math.clamp(tonumber(alpha) or 1, 0, 1)
    if self._warningText and self._warningText:IsA("TextLabel") then
        self._warningText.TextTransparency = self._warningAlpha
        self._warningText.TextStrokeTransparency = math.clamp(self._warningAlpha + 0.1, 0, 1)

        local uiStroke = self._warningText:FindFirstChildWhichIsA("UIStroke")
        if uiStroke then
            uiStroke.Transparency = math.clamp(self._warningAlpha + 0.1, 0, 1)
        end
    end
end

function BrainrotBossController:_tweenWarningAlpha(targetAlpha, duration)
    self:_ensureUiNodes()
    if not self._warningRoot then
        return
    end

    setGuiVisible(self._warningRoot, true)

    local driver = Instance.new("NumberValue")
    driver.Value = self._warningAlpha
    local connection = driver:GetPropertyChangedSignal("Value"):Connect(function()
        self:_setWarningAlpha(driver.Value)
    end)

    local tween = TweenService:Create(driver, TweenInfo.new(math.max(0.05, duration), Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
        Value = math.clamp(targetAlpha, 0, 1),
    })
    tween:Play()
    tween.Completed:Wait()

    connection:Disconnect()
    driver:Destroy()
end

function BrainrotBossController:_playWarningBlink(payload)
    self._warningSerial += 1
    local serial = self._warningSerial
    local explicitBlinkCount = type(payload) == "table" and tonumber(payload.blinkCount) or nil
    local explicitFadeTime = type(payload) == "table" and tonumber(payload.fadeTime) or nil
    local blinkCount = math.max(1, math.floor(explicitBlinkCount or tonumber((GameConfig.BRAINROT or {}).BossWarningBlinkCount) or 3))
    local fadeTime = math.max(0.05, explicitFadeTime or tonumber((GameConfig.BRAINROT or {}).BossWarningFadeTime) or 0.18)

    self:_playWarningSoundTwice()

    task.spawn(function()
        self:_ensureUiNodes()
        if not self._warningRoot then
            return
        end

        setGuiVisible(self._warningRoot, true)
        self:_setWarningAlpha(1)

        for _ = 1, blinkCount do
            if serial ~= self._warningSerial then
                return
            end
            self:_tweenWarningAlpha(0, fadeTime)
            if serial ~= self._warningSerial then
                return
            end
            self:_tweenWarningAlpha(1, fadeTime)
        end

        if serial == self._warningSerial then
            self:_setWarningAlpha(1)
            setGuiVisible(self._warningRoot, false)
        end
    end)
end

function BrainrotBossController:_handleBossStateSync(payload)
    local normalizedPayload = type(payload) == "table" and payload or {}
    self._state.visible = normalizedPayload.visible == true
    self._state.carriedCount = math.max(0, math.floor(tonumber(normalizedPayload.carriedCount) or 0))
    self._state.homeUnlockAt = math.max(0, tonumber(normalizedPayload.homeUnlockAt) or 0)
    self._state.isChased = normalizedPayload.isChased == true
    self:_refreshChaseBgmSuppression()
    self:_refreshDropUi()
    self:_updateBossChaseOverlay(0)
end

function BrainrotBossController:_ensureBossRuntimeFolder()
    local folder = Workspace:FindFirstChild(self._bossRuntimeFolderName)
    if folder and folder:IsA("Folder") then
        self._bossRuntimeFolder = folder
        return folder
    end

    self._bossRuntimeFolder = nil
    return nil
end

function BrainrotBossController:_isBossRuntimeModel(model)
    if not (model and model:IsA("Model")) then
        return false
    end

    return model:GetAttribute(BOSS_RUNTIME_ATTRIBUTE) == true
        or string.sub(model.Name, 1, #"WorldSpawnBoss_") == "WorldSpawnBoss_"
end

function BrainrotBossController:_readBossTargetCFrame(model, fallbackCFrame)
    local fallback = fallbackCFrame
    if not fallback then
        local ok, pivotOrError = pcall(function()
            return model:GetPivot()
        end)
        fallback = ok and pivotOrError or CFrame.new()
    end

    local targetPosition = model:GetAttribute(BOSS_TARGET_POSITION_ATTRIBUTE)
    if typeof(targetPosition) ~= "Vector3" then
        targetPosition = fallback.Position
    end

    local targetLookVector = model:GetAttribute(BOSS_TARGET_LOOK_VECTOR_ATTRIBUTE)
    return buildBossTargetCFrame(targetPosition, targetLookVector, fallback.LookVector)
end

function BrainrotBossController:_trackBossModel(model)
    if not self:_isBossRuntimeModel(model) or self._trackedBosses[model] then
        return
    end

    local initialTarget = self:_readBossTargetCFrame(model)
    local initialUpdatedAt = math.max(0, tonumber(model:GetAttribute(BOSS_SERVER_UPDATED_AT_ATTRIBUTE) or 0) or 0)
    self._trackedBosses[model] = {
        previousServerCFrame = initialTarget,
        latestServerCFrame = initialTarget,
        currentCFrame = initialTarget,
        receiveAt = os.clock(),
        interpolationWindow = self._bossInterpolationWindow,
        lastServerUpdatedAt = initialUpdatedAt,
        lastState = tostring(model:GetAttribute(BOSS_STATE_ATTRIBUTE) or "Idle"),
    }
end

function BrainrotBossController:_refreshTrackedBosses()
    local folder = self:_ensureBossRuntimeFolder()
    local seen = {}
    if folder then
        for _, child in ipairs(folder:GetChildren()) do
            if self:_isBossRuntimeModel(child) then
                seen[child] = true
                self:_trackBossModel(child)
            end
        end
    end

    for model in pairs(self._trackedBosses) do
        if not seen[model] or not model.Parent then
            self._trackedBosses[model] = nil
        end
    end
end

function BrainrotBossController:_updateBossVisual(model, trackedBoss)
    local latestTargetCFrame = self:_readBossTargetCFrame(model, trackedBoss.latestServerCFrame or trackedBoss.currentCFrame)
    local currentState = tostring(model:GetAttribute(BOSS_STATE_ATTRIBUTE) or "Idle")
    local serverUpdatedAt = math.max(0, tonumber(model:GetAttribute(BOSS_SERVER_UPDATED_AT_ATTRIBUTE) or 0) or 0)

    if serverUpdatedAt > 0 and serverUpdatedAt ~= trackedBoss.lastServerUpdatedAt then
        local previousServerCFrame = trackedBoss.latestServerCFrame or latestTargetCFrame
        local jumpDistance = (latestTargetCFrame.Position - previousServerCFrame.Position).Magnitude
        local shouldSnap = currentState == "Attack" or jumpDistance >= self._bossSnapDistance
        local serverDelta = trackedBoss.lastServerUpdatedAt > 0
            and math.max(0, serverUpdatedAt - trackedBoss.lastServerUpdatedAt)
            or self._bossInterpolationWindow

        trackedBoss.previousServerCFrame = shouldSnap and latestTargetCFrame or previousServerCFrame
        trackedBoss.latestServerCFrame = latestTargetCFrame
        trackedBoss.receiveAt = os.clock()
        trackedBoss.interpolationWindow = shouldSnap
            and (1 / 120)
            or math.clamp(math.max(self._bossInterpolationWindow, serverDelta), 1 / 120, 0.35)
        trackedBoss.lastServerUpdatedAt = serverUpdatedAt
    elseif not trackedBoss.latestServerCFrame then
        trackedBoss.previousServerCFrame = latestTargetCFrame
        trackedBoss.latestServerCFrame = latestTargetCFrame
        trackedBoss.receiveAt = os.clock()
        trackedBoss.interpolationWindow = self._bossInterpolationWindow
        trackedBoss.lastServerUpdatedAt = serverUpdatedAt
    else
        trackedBoss.latestServerCFrame = latestTargetCFrame
    end

    local visualCFrame = trackedBoss.latestServerCFrame or latestTargetCFrame
    if currentState ~= "Attack" then
        local interpolationWindow = math.max(1 / 120, trackedBoss.interpolationWindow or self._bossInterpolationWindow)
        local alpha = math.clamp((os.clock() - (trackedBoss.receiveAt or os.clock())) / interpolationWindow, 0, 1)
        local fromCFrame = trackedBoss.previousServerCFrame or visualCFrame
        visualCFrame = fromCFrame:Lerp(visualCFrame, alpha)
    end

    trackedBoss.currentCFrame = visualCFrame
    trackedBoss.lastState = currentState
    pcall(function()
        model:PivotTo(visualCFrame)
    end)
end

function BrainrotBossController:_updateBossVisuals()
    if not self._bossVisualSmoothingEnabled then
        return
    end

    self:_refreshTrackedBosses()
    for model, trackedBoss in pairs(self._trackedBosses) do
        if model and model.Parent and self:_isBossRuntimeModel(model) then
            self:_updateBossVisual(model, trackedBoss)
        else
            self._trackedBosses[model] = nil
        end
    end
end

function BrainrotBossController:Start()
    if self._started then
        return
    end

    self._started = true

    self:_ensureFloatLandAirwallCache()
    self:_setAllAirwallCanCollide(false)

    if self._characterAddedConnection then
        self._characterAddedConnection:Disconnect()
        self._characterAddedConnection = nil
    end

    self._characterAddedConnection = localPlayer.CharacterAdded:Connect(function()
        self._activeAirwallLevel = nil
        self._isAirwallLockActive = false
        self:_setAllAirwallCanCollide(false)
    end)

    local eventsRoot = ReplicatedStorage:WaitForChild(RemoteNames.RootFolder)
    local brainrotEvents = eventsRoot:WaitForChild(RemoteNames.BrainrotEventsFolder)
    local systemEvents = eventsRoot:WaitForChild(RemoteNames.SystemEventsFolder)

    self._bossStateSyncEvent = brainrotEvents:WaitForChild(RemoteNames.Brainrot.BossStateSync, 10)
    self._requestDropCarriedWorldBrainrotEvent = brainrotEvents:WaitForChild(RemoteNames.Brainrot.RequestDropCarriedWorldBrainrot, 10)
    self._bossWarningEvent = brainrotEvents:WaitForChild(RemoteNames.Brainrot.BossWarning, 10)
    self._requestQuickTeleportEvent = systemEvents:WaitForChild(RemoteNames.System.RequestQuickTeleport, 10)

    if self._bossStateSyncEvent and self._bossStateSyncEvent:IsA("RemoteEvent") then
        self._bossStateSyncEvent.OnClientEvent:Connect(function(payload)
            self:_handleBossStateSync(payload)
        end)
    end

    if self._bossWarningEvent and self._bossWarningEvent:IsA("RemoteEvent") then
        self._bossWarningEvent.OnClientEvent:Connect(function(payload)
            self:_playWarningBlink(payload)
        end)
    end

    if not self._bossRenderConnection then
        self._bossRenderConnection = RunService.RenderStepped:Connect(function(deltaTime)
            if self._bossVisualSmoothingEnabled then
                self:_updateBossVisuals()
            end
            self:_updateBossChaseOverlay(deltaTime)
        end)
    end

    task.spawn(function()
        while self._started do
            task.wait(self._updateInterval)
            self:_refreshChaseBgmSuppression()
            self:_refreshDropUi()
        end
    end)

    self:_refreshChaseBgmSuppression()
    self:_refreshDropUi()
    self:_updateBossChaseOverlay(0)
end

return BrainrotBossController
