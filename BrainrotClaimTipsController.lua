--[[
ScriptName: BrainrotClaimTipsController
FileName: BrainrotClaimTipsController.lua
ScriptType: ModuleScript
StudioPath: StarterPlayer/StarterPlayerScripts/Controllers/BrainrotClaimTipsController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local randomGenerator = Random.new()

local DEFAULT_CONFETTI_COLORS = {
    Color3.fromRGB(255, 70, 70),
    Color3.fromRGB(255, 208, 58),
    Color3.fromRGB(102, 255, 102),
    Color3.fromRGB(72, 230, 255),
    Color3.fromRGB(255, 128, 48),
    Color3.fromRGB(186, 110, 255),
}

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
        "[BrainrotClaimTipsController] Missing shared module %s (expected in ReplicatedStorage/Shared or ReplicatedStorage root)",
        moduleName
    ))
end

local GameConfig = requireSharedModule("GameConfig")
local RemoteNames = requireSharedModule("RemoteNames")

local BrainrotClaimTipsController = {}
BrainrotClaimTipsController.__index = BrainrotClaimTipsController

local function randomRange(minValue, maxValue)
    local minNumber = tonumber(minValue) or 0
    local maxNumber = tonumber(maxValue) or minNumber
    if maxNumber < minNumber then
        minNumber, maxNumber = maxNumber, minNumber
    end

    return randomGenerator:NextNumber(minNumber, maxNumber)
end

local function randomInteger(minValue, maxValue)
    local minNumber = math.floor(tonumber(minValue) or 0)
    local maxNumber = math.floor(tonumber(maxValue) or minNumber)
    if maxNumber < minNumber then
        minNumber, maxNumber = maxNumber, minNumber
    end

    return randomGenerator:NextInteger(minNumber, maxNumber)
end

local function offsetY(position, yOffset)
    return UDim2.new(
        position.X.Scale,
        position.X.Offset,
        position.Y.Scale,
        position.Y.Offset + yOffset
    )
end

local function setVisibility(node, visible)
    if not node then
        return
    end

    if node:IsA("ScreenGui") then
        node.Enabled = visible
    elseif node:IsA("GuiObject") then
        node.Visible = visible
    end
end

local function isTipsRoot(node)
    return node and (node:IsA("ScreenGui") or node:IsA("GuiObject"))
end

local function findTipsRoot(playerGui)
    if not playerGui then
        return nil
    end

    local mainGui = playerGui:FindFirstChild("Main")
    if mainGui then
        local nested = mainGui:FindFirstChild("BrainrotGetTips", true)
        if nested and isTipsRoot(nested) then
            return nested
        end
    end

    local direct = playerGui:FindFirstChild("BrainrotGetTips", true)
    if direct and isTipsRoot(direct) then
        return direct
    end

    return nil
end

local function sanitizeConfettiPalette(rawPalette)
    local palette = {}
    if type(rawPalette) == "table" then
        for _, colorValue in ipairs(rawPalette) do
            if typeof(colorValue) == "Color3" then
                table.insert(palette, colorValue)
            end
        end
    end

    if #palette <= 0 then
        palette = DEFAULT_CONFETTI_COLORS
    end

    return palette
end

local function getViewportSize()
    local camera = Workspace.CurrentCamera
    local viewportSize = camera and camera.ViewportSize or Vector2.new(0, 0)
    if viewportSize.X <= 0 or viewportSize.Y <= 0 then
        return Vector2.new(1920, 1080)
    end

    return viewportSize
end

function BrainrotClaimTipsController.new()
    local self = setmetatable({}, BrainrotClaimTipsController)
    self._tipsRoot = nil
    self._tipsTextLabel = nil
    self._tipsBasePosition = nil
    self._tipQueue = {}
    self._isShowingTip = false
    self._didWarnMissingTips = false
    self._didWarnMissingTipsText = false
    self._tipEvent = nil
    self._confettiGui = nil
    self._confettiCanvas = nil
    self._confettiPieces = {}
    self._confettiPiecePool = {}
    self._confettiRenderConnection = nil
    self._confettiWarmTargetCount = 0
    self._confettiPoolWarmInFlight = false
    self._confettiConfig = nil
    return self
end

function BrainrotClaimTipsController:_setTipsTextAppearance(textTransparency, strokeTransparency)
    if not self._tipsTextLabel then
        return
    end

    self._tipsTextLabel.TextTransparency = textTransparency
    self._tipsTextLabel.TextStrokeTransparency = strokeTransparency
end

function BrainrotClaimTipsController:_getPlayerGui()
    return localPlayer:FindFirstChildOfClass("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
end

function BrainrotClaimTipsController:_ensureTipsNodes()
    if self._tipsRoot and self._tipsRoot.Parent and self._tipsTextLabel and self._tipsTextLabel.Parent then
        return true
    end

    local playerGui = self:_getPlayerGui()
    if not playerGui then
        if not self._didWarnMissingTips then
            warn("[BrainrotClaimTipsController] PlayerGui not found; BrainrotGetTips is unavailable.")
            self._didWarnMissingTips = true
        end
        return false
    end

    local tipsRoot = findTipsRoot(playerGui)
    if not tipsRoot then
        if not self._didWarnMissingTips then
            warn("[BrainrotClaimTipsController] BrainrotGetTips UI not found.")
            self._didWarnMissingTips = true
        end
        return false
    end

    local textLabel = tipsRoot:FindFirstChild("Text", true)
    if not (textLabel and textLabel:IsA("TextLabel")) then
        textLabel = tipsRoot:FindFirstChildWhichIsA("TextLabel", true)
    end

    if not textLabel then
        if not self._didWarnMissingTipsText then
            warn("[BrainrotClaimTipsController] BrainrotGetTips exists but is missing a TextLabel.")
            self._didWarnMissingTipsText = true
        end
        return false
    end

    self._didWarnMissingTips = false
    self._didWarnMissingTipsText = false
    self._tipsRoot = tipsRoot
    self._tipsTextLabel = textLabel
    self._tipsBasePosition = textLabel.Position
    setVisibility(self._tipsRoot, false)
    return true
end

function BrainrotClaimTipsController:_ensureConfettiNodes()
    if self._confettiGui and self._confettiGui.Parent and self._confettiCanvas and self._confettiCanvas.Parent then
        return true
    end

    local playerGui = self:_getPlayerGui()
    if not playerGui then
        return false
    end

    local confettiGui = playerGui:FindFirstChild("_BrainrotClaimConfettiFx")
    if not (confettiGui and confettiGui:IsA("ScreenGui")) then
        confettiGui = Instance.new("ScreenGui")
        confettiGui.Name = "_BrainrotClaimConfettiFx"
        confettiGui.DisplayOrder = 60
        confettiGui.IgnoreGuiInset = true
        confettiGui.ResetOnSpawn = false
        confettiGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        confettiGui.Parent = playerGui
    end

    local confettiCanvas = confettiGui:FindFirstChild("Canvas")
    if not (confettiCanvas and confettiCanvas:IsA("Frame")) then
        confettiCanvas = Instance.new("Frame")
        confettiCanvas.Name = "Canvas"
        confettiCanvas.BackgroundTransparency = 1
        confettiCanvas.BorderSizePixel = 0
        confettiCanvas.Size = UDim2.fromScale(1, 1)
        confettiCanvas.ClipsDescendants = false
        confettiCanvas.Active = false
        confettiCanvas.Parent = confettiGui
    end

    self._confettiGui = confettiGui
    self._confettiCanvas = confettiCanvas
    return true
end

function BrainrotClaimTipsController:_getConfettiConfig()
    if self._confettiConfig then
        return self._confettiConfig
    end

    local config = GameConfig.BRAINROT or {}
    local pieceCount = math.max(0, math.floor(tonumber(config.WorldSpawnClaimConfettiPieceCount) or 72))
    local maxActivePieces = math.max(pieceCount, math.floor(tonumber(config.WorldSpawnClaimConfettiMaxActivePieces) or 180))
    local fadeOutDuration = math.max(0.05, tonumber(config.WorldSpawnClaimConfettiFadeOutDuration) or 0.22)
    local lifetimeMin = math.max(fadeOutDuration + 0.05, tonumber(config.WorldSpawnClaimConfettiLifetimeMin) or 0.9)
    local lifetimeMax = math.max(lifetimeMin, tonumber(config.WorldSpawnClaimConfettiLifetimeMax) or 1.35)

    local confettiConfig = {
        enabled = config.WorldSpawnClaimConfettiEnabled ~= false,
        pieceCount = pieceCount,
        maxActivePieces = maxActivePieces,
        originXScale = tonumber(config.WorldSpawnClaimConfettiOriginXScale) or 0.5,
        originYScale = tonumber(config.WorldSpawnClaimConfettiOriginYScale) or 0.38,
        originJitterXPx = math.max(0, tonumber(config.WorldSpawnClaimConfettiOriginJitterXPx) or 120),
        originJitterYPx = math.max(0, tonumber(config.WorldSpawnClaimConfettiOriginJitterYPx) or 36),
        pieceSizePxMin = math.max(4, math.floor(tonumber(config.WorldSpawnClaimConfettiPieceSizePxMin) or 10)),
        pieceSizePxMax = math.max(4, math.floor(tonumber(config.WorldSpawnClaimConfettiPieceSizePxMax) or 24)),
        pieceAspectMin = math.max(0.2, tonumber(config.WorldSpawnClaimConfettiPieceAspectMin) or 0.7),
        pieceAspectMax = math.max(0.2, tonumber(config.WorldSpawnClaimConfettiPieceAspectMax) or 1.8),
        horizontalSpeedMin = math.max(0, tonumber(config.WorldSpawnClaimConfettiHorizontalSpeedMin) or 420),
        horizontalSpeedMax = math.max(0, tonumber(config.WorldSpawnClaimConfettiHorizontalSpeedMax) or 1100),
        upwardSpeedMin = math.max(0, tonumber(config.WorldSpawnClaimConfettiUpwardSpeedMin) or 420),
        upwardSpeedMax = math.max(0, tonumber(config.WorldSpawnClaimConfettiUpwardSpeedMax) or 1180),
        gravity = math.max(0, tonumber(config.WorldSpawnClaimConfettiGravity) or 1850),
        rotationSpeedMin = tonumber(config.WorldSpawnClaimConfettiRotationSpeedMin) or -540,
        rotationSpeedMax = tonumber(config.WorldSpawnClaimConfettiRotationSpeedMax) or 540,
        lifetimeMin = lifetimeMin,
        lifetimeMax = lifetimeMax,
        fadeOutDuration = fadeOutDuration,
        palette = sanitizeConfettiPalette(config.WorldSpawnClaimConfettiColors),
    }

    self._confettiConfig = confettiConfig
    return confettiConfig
end

function BrainrotClaimTipsController:_createConfettiPieceFrame()
    if not (self._confettiCanvas and self._confettiCanvas.Parent) then
        return nil
    end

    local pieceFrame = Instance.new("Frame")
    pieceFrame.Name = "ConfettiPiece"
    pieceFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    pieceFrame.BackgroundTransparency = 1
    pieceFrame.BorderSizePixel = 0
    pieceFrame.Visible = false
    pieceFrame.Size = UDim2.fromOffset(8, 8)
    pieceFrame.Position = UDim2.fromOffset(-256, -256)
    pieceFrame.ZIndex = 2
    pieceFrame.Parent = self._confettiCanvas
    return pieceFrame
end

function BrainrotClaimTipsController:_acquireConfettiPieceFrame()
    local pieceFrame = nil
    while #self._confettiPiecePool > 0 do
        pieceFrame = self._confettiPiecePool[#self._confettiPiecePool]
        self._confettiPiecePool[#self._confettiPiecePool] = nil
        if pieceFrame and pieceFrame.Parent then
            break
        end
        pieceFrame = nil
    end

    if not pieceFrame then
        pieceFrame = self:_createConfettiPieceFrame()
    end

    if pieceFrame and pieceFrame.Parent ~= self._confettiCanvas then
        pieceFrame.Parent = self._confettiCanvas
    end

    if pieceFrame then
        pieceFrame.Visible = true
    end

    return pieceFrame
end

function BrainrotClaimTipsController:_recycleConfettiPieceFrame(pieceFrame)
    if not pieceFrame then
        return
    end

    if not (self._confettiCanvas and self._confettiCanvas.Parent) then
        if pieceFrame.Parent then
            pieceFrame:Destroy()
        end
        return
    end

    pieceFrame.Visible = false
    pieceFrame.BackgroundTransparency = 1
    pieceFrame.Position = UDim2.fromOffset(-256, -256)
    pieceFrame.Rotation = 0
    pieceFrame.Size = UDim2.fromOffset(8, 8)
    pieceFrame.Parent = self._confettiCanvas
    self._confettiPiecePool[#self._confettiPiecePool + 1] = pieceFrame
end

function BrainrotClaimTipsController:_warmConfettiPool(targetCount)
    targetCount = math.max(0, math.floor(tonumber(targetCount) or 0))
    if targetCount <= 0 then
        return
    end

    self._confettiWarmTargetCount = math.max(self._confettiWarmTargetCount or 0, targetCount)
    if self._confettiPoolWarmInFlight then
        return
    end

    self._confettiPoolWarmInFlight = true
    task.spawn(function()
        while self._confettiCanvas and self._confettiCanvas.Parent do
            local warmTargetCount = math.max(0, math.floor(tonumber(self._confettiWarmTargetCount) or 0))
            local totalPieceCount = #self._confettiPiecePool + #self._confettiPieces
            local remainingCount = warmTargetCount - totalPieceCount
            if remainingCount <= 0 then
                break
            end

            local createCount = math.min(12, remainingCount)
            for _ = 1, createCount do
                local pieceFrame = self:_createConfettiPieceFrame()
                if not pieceFrame then
                    break
                end
                self._confettiPiecePool[#self._confettiPiecePool + 1] = pieceFrame
            end

            task.wait()
        end

        self._confettiPoolWarmInFlight = false
    end)
end

function BrainrotClaimTipsController:_removeConfettiPieceAt(index)
    local pieceData = self._confettiPieces[index]
    if not pieceData then
        return
    end

    self:_recycleConfettiPieceFrame(pieceData.Instance)

    local lastIndex = #self._confettiPieces
    self._confettiPieces[index] = self._confettiPieces[lastIndex]
    self._confettiPieces[lastIndex] = nil
end

function BrainrotClaimTipsController:_stopConfettiLoopIfIdle()
    if #self._confettiPieces > 0 then
        return
    end

    if self._confettiRenderConnection then
        self._confettiRenderConnection:Disconnect()
        self._confettiRenderConnection = nil
    end
end

function BrainrotClaimTipsController:_updateConfetti(deltaTime)
    local viewportSize = getViewportSize()

    for index = #self._confettiPieces, 1, -1 do
        local pieceData = self._confettiPieces[index]
        local pieceFrame = pieceData and pieceData.Instance or nil
        if not (pieceFrame and pieceFrame.Parent) then
            table.remove(self._confettiPieces, index)
        else
            pieceData.Age = pieceData.Age + deltaTime
            pieceData.Velocity = pieceData.Velocity + (Vector2.new(0, pieceData.Gravity) * deltaTime)
            pieceData.Position = pieceData.Position + (pieceData.Velocity * deltaTime)
            pieceData.Rotation = pieceData.Rotation + (pieceData.RotationVelocity * deltaTime)

            pieceFrame.Position = UDim2.fromOffset(pieceData.Position.X, pieceData.Position.Y)
            pieceFrame.Rotation = pieceData.Rotation

            local fadeAlpha = 0
            if pieceData.Age >= pieceData.FadeStart then
                fadeAlpha = math.clamp(
                    (pieceData.Age - pieceData.FadeStart) / (pieceData.FadeDuration or math.max(0.001, pieceData.Lifetime - pieceData.FadeStart)),
                    0,
                    1
                )
            end
            pieceFrame.BackgroundTransparency = 0.05 + (fadeAlpha * 0.95)
            pieceFrame.Visible = true

            if pieceData.Age >= pieceData.Lifetime
                or pieceData.Position.Y >= (viewportSize.Y + 180)
                or pieceData.Position.X <= -220
                or pieceData.Position.X >= (viewportSize.X + 220)
            then
                self:_removeConfettiPieceAt(index)
            end
        end
    end

    self:_stopConfettiLoopIfIdle()
end

function BrainrotClaimTipsController:_ensureConfettiLoop()
    if self._confettiRenderConnection then
        return
    end

    self._confettiRenderConnection = RunService.Heartbeat:Connect(function(deltaTime)
        self:_updateConfetti(math.min(deltaTime, 1 / 20))
    end)
end

function BrainrotClaimTipsController:_spawnConfettiPiece(originPosition, config)
    if not (self._confettiCanvas and self._confettiCanvas.Parent) then
        return
    end

    local pieceFrame = self:_acquireConfettiPieceFrame()
    if not pieceFrame then
        return
    end

    local pieceSizeBase = randomInteger(config.pieceSizePxMin, config.pieceSizePxMax)
    local aspectRatio = randomRange(config.pieceAspectMin, config.pieceAspectMax)
    local pieceWidth = math.max(4, math.floor(pieceSizeBase * aspectRatio))
    local pieceHeight = math.max(4, math.floor(pieceSizeBase / math.max(0.05, aspectRatio)))
    if randomGenerator:NextNumber() >= 0.5 then
        pieceWidth, pieceHeight = pieceHeight, pieceWidth
    end

    pieceFrame.BackgroundColor3 = config.palette[randomInteger(1, #config.palette)]
    pieceFrame.BackgroundTransparency = 0.05
    pieceFrame.Size = UDim2.fromOffset(pieceWidth, pieceHeight)
    pieceFrame.Position = UDim2.fromOffset(originPosition.X, originPosition.Y)
    pieceFrame.Rotation = randomRange(-180, 180)
    pieceFrame.Visible = true

    local velocityXDirection = randomRange(-1, 1)
    if math.abs(velocityXDirection) < 0.08 then
        velocityXDirection = velocityXDirection < 0 and -0.08 or 0.08
    end

    local velocity = Vector2.new(
        velocityXDirection * randomRange(config.horizontalSpeedMin, config.horizontalSpeedMax),
        -randomRange(config.upwardSpeedMin, config.upwardSpeedMax)
    )
    local lifetime = randomRange(config.lifetimeMin, config.lifetimeMax)
    local fadeStart = math.max(0.01, lifetime - config.fadeOutDuration)

    table.insert(self._confettiPieces, {
        Instance = pieceFrame,
        Position = originPosition,
        Velocity = velocity,
        Gravity = config.gravity,
        Rotation = pieceFrame.Rotation,
        RotationVelocity = randomRange(config.rotationSpeedMin, config.rotationSpeedMax),
        Age = 0,
        Lifetime = lifetime,
        FadeStart = fadeStart,
        FadeDuration = math.max(0.001, lifetime - fadeStart),
    })
end

function BrainrotClaimTipsController:_playClaimConfettiBurst()
    local config = self:_getConfettiConfig()
    if config.enabled ~= true or config.pieceCount <= 0 then
        return
    end

    if not self:_ensureConfettiNodes() then
        return
    end

    self:_warmConfettiPool(config.maxActivePieces)

    local viewportSize = getViewportSize()
    local originX = viewportSize.X * config.originXScale
    local originY = viewportSize.Y * config.originYScale

    local burstPieceCount = math.min(config.pieceCount, config.maxActivePieces)
    local roomBeforeBurst = math.max(0, config.maxActivePieces - burstPieceCount)
    while #self._confettiPieces > roomBeforeBurst do
        self:_removeConfettiPieceAt(#self._confettiPieces)
    end

    for _ = 1, burstPieceCount do
        local spawnPosition = Vector2.new(
            originX + randomRange(-config.originJitterXPx, config.originJitterXPx),
            originY + randomRange(-config.originJitterYPx, config.originJitterYPx)
        )
        self:_spawnConfettiPiece(spawnPosition, config)
    end

    self:_ensureConfettiLoop()
end

function BrainrotClaimTipsController:_showNextTip()
    if self._isShowingTip then
        return
    end

    if #self._tipQueue <= 0 then
        setVisibility(self._tipsRoot, false)
        return
    end

    self._isShowingTip = true
    local message = table.remove(self._tipQueue, 1)

    if not self:_ensureTipsNodes() then
        self._isShowingTip = false
        table.insert(self._tipQueue, 1, message)
        task.delay(1, function()
            if not self._isShowingTip and #self._tipQueue > 0 then
                self:_showNextTip()
            end
        end)
        return
    end

    local label = self._tipsTextLabel
    local basePosition = self._tipsBasePosition
    local config = (GameConfig.BRAINROT or {})
    local enterOffsetY = math.floor(tonumber(config.ClaimTipEnterOffsetY) or 40)
    local fadeOffsetY = math.floor(tonumber(config.ClaimTipFadeOffsetY) or -8)
    local holdSeconds = math.max(0.2, tonumber(config.ClaimTipDisplaySeconds) or 2)

    setVisibility(self._tipsRoot, true)
    label.Text = tostring(message or "")
    label.Position = offsetY(basePosition, enterOffsetY)
    self:_setTipsTextAppearance(0, 0)

    local enterTween = TweenService:Create(label, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = basePosition,
    })

    enterTween.Completed:Connect(function()
        task.delay(holdSeconds, function()
            if not label or not label.Parent then
                self._isShowingTip = false
                self:_showNextTip()
                return
            end

            local fadeTween = TweenService:Create(label, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                TextTransparency = 1,
                TextStrokeTransparency = 1,
                Position = offsetY(basePosition, fadeOffsetY),
            })

            fadeTween.Completed:Connect(function()
                if label and label.Parent then
                    label.Position = basePosition
                    self:_setTipsTextAppearance(0, 0)
                end

                self._isShowingTip = false
                if #self._tipQueue <= 0 then
                    setVisibility(self._tipsRoot, false)
                end
                self:_showNextTip()
            end)

            fadeTween:Play()
        end)
    end)

    enterTween:Play()
end

function BrainrotClaimTipsController:_enqueueTip(message)
    local resolvedMessage = tostring(message or "")
    if resolvedMessage == "" then
        return
    end

    table.insert(self._tipQueue, resolvedMessage)
    self:_showNextTip()
end

function BrainrotClaimTipsController:Start()
    local eventsRoot = ReplicatedStorage:WaitForChild(RemoteNames.RootFolder)
    local systemEvents = eventsRoot:WaitForChild(RemoteNames.SystemEventsFolder)
    self._tipEvent = systemEvents:WaitForChild(RemoteNames.System.BrainrotClaimTip)

    self:_ensureTipsNodes()
    if self:_ensureConfettiNodes() then
        local confettiConfig = self:_getConfettiConfig()
        if confettiConfig.enabled then
            self:_warmConfettiPool(confettiConfig.maxActivePieces)
        end
    end

    self._tipEvent.OnClientEvent:Connect(function(payload)
        local message = type(payload) == "table" and payload.message or payload
        local shouldPlayConfetti = type(payload) ~= "table" or payload.playConfetti ~= false
        self:_enqueueTip(message)
        if shouldPlayConfetti then
            self:_playClaimConfettiBurst()
        end
    end)
end

return BrainrotClaimTipsController
