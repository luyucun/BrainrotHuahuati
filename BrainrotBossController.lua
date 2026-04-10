--[[
脚本名字: BrainrotBossController
脚本文件: BrainrotBossController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/BrainrotBossController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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

local function getBossRuntimeFolderName()
    return tostring((GameConfig.BRAINROT or {}).WorldSpawnBossRuntimeFolderName or "WorldSpawnBosses")
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

function BrainrotBossController.new()
    local self = setmetatable({}, BrainrotBossController)
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
    self._dropButtonConnection = nil
    self._homeButtonConnection = nil
    self._warningAlpha = 1
    self._warningSerial = 0
    self._homeEnabled = false
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
    self._state = {
        visible = false,
        carriedCount = 0,
        homeUnlockAt = 0,
        isChased = false,
    }
    self._homeDefaultBackgroundColor = nil
    self._homeDefaultTextColor = nil
    self._countdownDefaultTextColor = nil
    return self
end

function BrainrotBossController:_getPlayerGui()
    return localPlayer:FindFirstChildOfClass("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
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

    local didChange = dropRoot ~= self._dropRoot
        or dropButton ~= self._dropButton
        or homeButton ~= self._homeButton
        or countdownLabel ~= self._countdownLabel
        or warningRoot ~= self._warningRoot
        or warningText ~= self._warningText

    self._dropRoot = dropRoot
    self._dropButton = dropButton
    self._homeButton = homeButton
    self._countdownLabel = countdownLabel
    self._homeReadyNodes = homeReadyNodes
    self._homeLockedNodes = homeLockedNodes
    self._warningRoot = warningRoot
    self._warningText = warningText

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
    self:_ensureUiNodes()
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
        return
    end

    local remaining = math.max(0, (tonumber(self._state.homeUnlockAt) or 0) - getSharedClock())
    local isUnlocked = remaining <= 0
    self:_applyHomeButtonEnabled(isUnlocked)
    self:_applyHomeAvailabilityVisuals(isUnlocked, not isUnlocked)
    if self._countdownLabel then
        self._countdownLabel.Text = isUnlocked and "" or formatCountdownText(remaining)
    end
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
    local blinkCount = math.max(1, math.floor(tonumber(type(payload) == "table" and payload.blinkCount or 0) or tonumber((GameConfig.BRAINROT or {}).BossWarningBlinkCount) or 3))
    local fadeTime = math.max(0.05, tonumber(type(payload) == "table" and payload.fadeTime or 0) or tonumber((GameConfig.BRAINROT or {}).BossWarningFadeTime) or 0.18)

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
    self:_refreshDropUi()
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

    if self._bossVisualSmoothingEnabled and not self._bossRenderConnection then
        self._bossRenderConnection = RunService.RenderStepped:Connect(function()
            self:_updateBossVisuals()
        end)
    end

    task.spawn(function()
        while self._started do
            task.wait(self._updateInterval)
            self:_refreshDropUi()
        end
    end)

    self:_refreshDropUi()
end

return BrainrotBossController
