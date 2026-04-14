--[[
脚本名字: RebirthController
脚本文件: RebirthController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/RebirthController
]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

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
        "[RebirthController] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local FormatUtil = requireSharedModule("FormatUtil")
local GameConfig = requireSharedModule("GameConfig")
local RebirthConfig = requireSharedModule("RebirthConfig")
local RemoteNames = requireSharedModule("RemoteNames")

local RebirthController = {}
RebirthController.__index = RebirthController
local REBIRTH_SUCCESS_SOUND_ASSET_ID = "rbxassetid://9039636239"
local REBIRTH_SUCCESS_SOUND_TEMPLATE_NAME = "Can You Feel the Love? (sting a)"
local REBIRTH_SUCCESS_SOUND_FALLBACK_NAME = "_RebirthSuccessFallback"

local function ensureUiScale(guiObject)
    if not (guiObject and guiObject:IsA("GuiObject")) then
        return nil
    end

    local uiScale = guiObject:FindFirstChildOfClass("UIScale")
    if uiScale then
        return uiScale
    end

    uiScale = Instance.new("UIScale")
    uiScale.Scale = 1
    uiScale.Parent = guiObject
    return uiScale
end

local function disconnectAll(connectionList)
    for _, connection in ipairs(connectionList) do
        connection:Disconnect()
    end
    table.clear(connectionList)
end

local function setVisibility(instance, isVisible)
    if not instance then
        return
    end

    if instance:IsA("LayerCollector") then
        instance.Enabled = isVisible
        return
    end

    if instance:IsA("GuiObject") then
        instance.Visible = isVisible
    end
end

local function isGuiRoot(node)
    if not node then
        return false
    end

    return node:IsA("ScreenGui") or node:IsA("GuiObject")
end

local function rememberTransparencyTarget(targets, instance, propertyName)
    local success, currentValue = pcall(function()
        return instance[propertyName]
    end)

    if success then
        targets[#targets + 1] = {
            instance = instance,
            propertyName = propertyName,
            baseValue = currentValue,
        }
    end
end

local function rememberColorTarget(targets, instance, propertyName)
    local success, currentValue = pcall(function()
        return instance[propertyName]
    end)

    if success and typeof(currentValue) == "Color3" then
        targets[#targets + 1] = {
            instance = instance,
            propertyName = propertyName,
            baseValue = currentValue,
        }
    end
end

local function collectColorTargets(root)
    local targets = {}

    local function visit(node)
        if not node then
            return
        end

        if node:IsA("GuiObject") then
            rememberColorTarget(targets, node, "BackgroundColor3")
        end

        if node:IsA("ImageLabel") or node:IsA("ImageButton") then
            rememberColorTarget(targets, node, "ImageColor3")
        end

        if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
            rememberColorTarget(targets, node, "TextColor3")
        end

        if node:IsA("UIStroke") then
            rememberColorTarget(targets, node, "Color")
        end

        for _, child in ipairs(node:GetChildren()) do
            visit(child)
        end
    end

    visit(root)
    return targets
end

local function getDisabledColor(baseColor)
    local disabledColor = Color3.fromRGB(155, 155, 155)
    local blendAlpha = 0.62
    return Color3.new(
        (baseColor.R * (1 - blendAlpha)) + (disabledColor.R * blendAlpha),
        (baseColor.G * (1 - blendAlpha)) + (disabledColor.G * blendAlpha),
        (baseColor.B * (1 - blendAlpha)) + (disabledColor.B * blendAlpha)
    )
end

local function applyColorEnabledState(targets, isEnabled)
    for _, entry in ipairs(targets or {}) do
        local nextValue = entry.baseValue
        if isEnabled ~= true then
            nextValue = getDisabledColor(entry.baseValue)
        end

        pcall(function()
            entry.instance[entry.propertyName] = nextValue
        end)
    end
end

local function collectTransparencyTargets(root)
    local targets = {}

    local function visit(node)
        if not node then
            return
        end

        if node:IsA("GuiObject") then
            rememberTransparencyTarget(targets, node, "BackgroundTransparency")
        end

        if node:IsA("ImageLabel") or node:IsA("ImageButton") then
            rememberTransparencyTarget(targets, node, "ImageTransparency")
        end

        if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
            rememberTransparencyTarget(targets, node, "TextTransparency")
            rememberTransparencyTarget(targets, node, "TextStrokeTransparency")
        end

        if node:IsA("ScrollingFrame") then
            rememberTransparencyTarget(targets, node, "ScrollBarImageTransparency")
        end

        if node:IsA("UIStroke") then
            rememberTransparencyTarget(targets, node, "Transparency")
        end

        for _, child in ipairs(node:GetChildren()) do
            visit(child)
        end
    end

    visit(root)
    return targets
end

local function applyTransparencyAlpha(targets, alpha)
    local clampedAlpha = math.clamp(tonumber(alpha) or 1, 0, 1)

    for _, entry in ipairs(targets or {}) do
        local nextValue = 1 - ((1 - entry.baseValue) * clampedAlpha)
        pcall(function()
            entry.instance[entry.propertyName] = nextValue
        end)
    end
end

local function tweenTransparencyAlpha(targets, duration, easingStyle, easingDirection, startAlpha, endAlpha)
    local alphaDriver = Instance.new("NumberValue")
    local startValue = math.clamp(tonumber(startAlpha) or 0, 0, 1)
    local endValue = math.clamp(tonumber(endAlpha) or 1, 0, 1)
    alphaDriver.Value = startValue

    local connection = alphaDriver:GetPropertyChangedSignal("Value"):Connect(function()
        applyTransparencyAlpha(targets, alphaDriver.Value)
    end)

    applyTransparencyAlpha(targets, startValue)

    local tween = TweenService:Create(alphaDriver, TweenInfo.new(duration, easingStyle, easingDirection), {
        Value = endValue,
    })

    tween.Completed:Connect(function(playbackState)
        if connection then
            connection:Disconnect()
        end

        if playbackState == Enum.PlaybackState.Completed then
            applyTransparencyAlpha(targets, endValue)
        end

        alphaDriver:Destroy()
    end)

    return tween
end

function RebirthController.new(modalController)
    local self = setmetatable({}, RebirthController)
    self._modalController = modalController
    self._started = false
    self._persistentConnections = {}
    self._uiConnections = {}
    self._didWarnByKey = {}
    self._rebindQueued = false
    self._playerGuiAddedConnection = nil
    self._playerGuiRemovingConnection = nil
    self._characterAddedConnection = nil
    self._coinChangedEvent = nil
    self._rebirthStateSyncEvent = nil
    self._requestRebirthStateSyncEvent = nil
    self._requestRebirthEvent = nil
    self._rebirthFeedbackEvent = nil
    self._currentCoins = 0
    self._state = {
        rebirthLevel = 0,
        currentBonusRate = 0,
        nextRebirthLevel = 1,
        nextRequiredCoins = 0,
        nextBonusRate = 0,
        developerProductId = math.max(0, math.floor(tonumber(RebirthConfig.SkipProductId) or 0)),
        isMaxLevel = false,
        maxRebirthLevel = 0,
    }
    self._hasReceivedStatePayload = false
    self._mainGui = nil
    self._leftSection = nil
    self._leftRebirthRoot = nil
    self._entryRedPoint = nil
    self._leftTimeLabel = nil
    self._rebirthRoot = nil
    self._closeButton = nil
    self._rebirthButtonRoot = nil
    self._rebirthButton = nil
    self._rebirthBuyButtonRoot = nil
    self._rebirthBuyButton = nil
    self._progressBg = nil
    self._progressBar = nil
    self._progressBarBaseSize = nil
    self._progressNumLabel = nil
    self._rewardNum1Label = nil
    self._rewardNum2Label = nil
    self._rebirthCurrentLabel = nil
    self._rebirthNextLabel = nil
    self._rebirthButtonColorTargets = nil
    self._rebirthBuyButtonColorTargets = nil
    self._tipsRoot = nil
    self._tipsTextLabel = nil
    self._tipsBasePosition = nil
    self._tipsTextTransparencyTargets = nil
    self._tipQueue = {}
    self._isShowingTip = false
    self._wrongSoundTemplate = nil
    self._didWarnMissingWrongSound = false
    self._successSoundTemplate = nil
    self._didWarnMissingSuccessSound = false
    return self
end

function RebirthController:_warnOnce(key, message)
    if self._didWarnByKey[key] then
        return
    end

    self._didWarnByKey[key] = true
    warn(message)
end

function RebirthController:_getPlayerGui()
    return localPlayer:FindFirstChild("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
end

function RebirthController:_getMainGui()
    local playerGui = self:_getPlayerGui()
    if not playerGui then
        return nil
    end

    local mainGui = playerGui:FindFirstChild("Main")
    if mainGui then
        return mainGui
    end

    return playerGui:FindFirstChild("Main", true)
end

function RebirthController:_findDescendantByNames(root, names)
    if not root then
        return nil
    end

    for _, name in ipairs(names or {}) do
        local direct = root:FindFirstChild(name)
        if direct then
            return direct
        end
    end

    for _, name in ipairs(names or {}) do
        local nested = root:FindFirstChild(name, true)
        if nested then
            return nested
        end
    end

    return nil
end

function RebirthController:_resolveInteractiveNode(node)
    if not node then
        return nil
    end

    if node:IsA("GuiButton") then
        return node
    end

    local textButton = node:FindFirstChild("TextButton")
    if textButton and textButton:IsA("GuiButton") then
        return textButton
    end

    local imageButton = node:FindFirstChild("ImageButton")
    if imageButton and imageButton:IsA("GuiButton") then
        return imageButton
    end

    return node:FindFirstChildWhichIsA("GuiButton", true)
end
function RebirthController:_findRebirthRoot(mainGui, leftRebirthRoot)
    if not mainGui then
        return nil
    end

    local directRebirth = mainGui:FindFirstChild("Rebirth")
    if directRebirth and directRebirth ~= leftRebirthRoot then
        return directRebirth
    end

    for _, descendant in ipairs(mainGui:GetDescendants()) do
        if descendant.Name == "Rebirth" and descendant ~= leftRebirthRoot then
            return descendant
        end
    end

    return nil
end

function RebirthController:_bindButtonFx(interactiveNode, options, connectionBucket)
    if not (interactiveNode and interactiveNode:IsA("GuiButton")) then
        return
    end

    local disableClickSound = type(options) == "table" and options.DisableClickSound == true
    if disableClickSound then
        interactiveNode:SetAttribute("DisableUiClickSound", true)
    elseif interactiveNode:GetAttribute("DisableUiClickSound") ~= nil then
        interactiveNode:SetAttribute("DisableUiClickSound", nil)
    end

    local scaleTarget = (type(options) == "table" and options.ScaleTarget) or interactiveNode
    local rotationTarget = (type(options) == "table" and options.RotationTarget) or nil
    local hoverScale = (type(options) == "table" and tonumber(options.HoverScale)) or 1.06
    local pressScale = (type(options) == "table" and tonumber(options.PressScale)) or 0.92
    local hoverRotation = (type(options) == "table" and tonumber(options.HoverRotation)) or 0
    local uiScale = ensureUiScale(scaleTarget)
    if not uiScale then
        return
    end

    local baseScale = uiScale.Scale
    local baseRotation = rotationTarget and rotationTarget.Rotation or 0
    local state = {
        isHovered = false,
        isPressed = false,
        scaleTween = nil,
        rotationTween = nil,
    }

    local function cancelTween(tweenKey)
        local tween = state[tweenKey]
        if tween then
            tween:Cancel()
            state[tweenKey] = nil
        end
    end

    local function playTween(instance, tweenInfo, goal, tweenKey)
        cancelTween(tweenKey)
        local tween = TweenService:Create(instance, tweenInfo, goal)
        state[tweenKey] = tween
        tween.Completed:Connect(function()
            if state[tweenKey] == tween then
                state[tweenKey] = nil
            end
        end)
        tween:Play()
    end

    local function applyVisualState()
        local targetScale = baseScale
        local targetRotation = baseRotation
        local tweenInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

        if state.isPressed then
            targetScale = baseScale * pressScale
            targetRotation = baseRotation + hoverRotation
            tweenInfo = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        elseif state.isHovered then
            targetScale = baseScale * hoverScale
            targetRotation = baseRotation + hoverRotation
            tweenInfo = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        end

        playTween(uiScale, tweenInfo, { Scale = targetScale }, "scaleTween")
        if rotationTarget then
            playTween(rotationTarget, tweenInfo, { Rotation = targetRotation }, "rotationTween")
        end
    end

    table.insert(connectionBucket, interactiveNode.MouseEnter:Connect(function()
        state.isHovered = true
        applyVisualState()
    end))
    table.insert(connectionBucket, interactiveNode.MouseLeave:Connect(function()
        state.isHovered = false
        state.isPressed = false
        applyVisualState()
    end))
    table.insert(connectionBucket, interactiveNode.InputBegan:Connect(function(inputObject)
        local inputType = inputObject.UserInputType
        if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch then
            state.isPressed = true
            if inputType == Enum.UserInputType.Touch then
                state.isHovered = true
            end
            applyVisualState()
        end
    end))
    table.insert(connectionBucket, interactiveNode.InputEnded:Connect(function(inputObject)
        local inputType = inputObject.UserInputType
        if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch then
            state.isPressed = false
            if inputType == Enum.UserInputType.Touch then
                state.isHovered = false
            end
            applyVisualState()
        end
    end))
end

function RebirthController:_clearUiBindings()
    disconnectAll(self._uiConnections)
end

function RebirthController:_findTipsRoot(mainGui, playerGui)
    if mainGui then
        local nested = mainGui:FindFirstChild("RebirthTips", true)
        if nested and isGuiRoot(nested) then
            return nested
        end
    end

    if playerGui then
        local direct = playerGui:FindFirstChild("RebirthTips")
        if direct and isGuiRoot(direct) then
            return direct
        end

        local nested = playerGui:FindFirstChild("RebirthTips", true)
        if nested and isGuiRoot(nested) then
            return nested
        end
    end

    return nil
end

function RebirthController:_ensureTipNodes()
    if self._tipsRoot and self._tipsRoot.Parent and self._tipsTextLabel and self._tipsTextLabel.Parent then
        return true
    end

    local playerGui = self:_getPlayerGui()
    local mainGui = self._mainGui or self:_getMainGui()
    local tipsRoot = self:_findTipsRoot(mainGui, playerGui)
    if not tipsRoot then
        self:_warnOnce("MissingRebirthTips", "[RebirthController] 找不到 RebirthTips，重生成功提示将被跳过。")
        return false
    end

    local textLabel = tipsRoot:FindFirstChild("Text", true)
    if not (textLabel and textLabel:IsA("TextLabel")) then
        textLabel = tipsRoot:FindFirstChildWhichIsA("TextLabel", true)
    end
    if not textLabel then
        self:_warnOnce("MissingRebirthTipsText", "[RebirthController] RebirthTips 存在但缺少 TextLabel。")
        return false
    end

    self._tipsRoot = tipsRoot
    self._tipsTextLabel = textLabel
    self._tipsBasePosition = textLabel.Position
    self._tipsTextTransparencyTargets = collectTransparencyTargets(textLabel)
    setVisibility(self._tipsRoot, false)
    return true
end
function RebirthController:_setTipTextAppearance(alpha)
    if not self._tipsTextTransparencyTargets then
        return
    end

    applyTransparencyAlpha(self._tipsTextTransparencyTargets, alpha)
end

function RebirthController:_showNextTip()
    if self._isShowingTip then
        return
    end

    if #self._tipQueue <= 0 then
        setVisibility(self._tipsRoot, false)
        return
    end

    self._isShowingTip = true
    local message = table.remove(self._tipQueue, 1)
    if not self:_ensureTipNodes() then
        self._isShowingTip = false
        return
    end

    local label = self._tipsTextLabel
    local basePosition = self._tipsBasePosition
    if not (label and basePosition) then
        self._isShowingTip = false
        setVisibility(self._tipsRoot, false)
        return
    end

    local config = GameConfig.REBIRTH or {}
    local enterOffsetY = math.floor(tonumber(config.TipsEnterOffsetY) or 40)
    local fadeOffsetY = math.floor(tonumber(config.TipsFadeOffsetY) or -8)
    local holdSeconds = math.max(0.2, tonumber(config.TipsDisplaySeconds) or 2)

    setVisibility(self._tipsRoot, true)
    label.Text = tostring(message or "")
    label.Position = UDim2.new(basePosition.X.Scale, basePosition.X.Offset, basePosition.Y.Scale, basePosition.Y.Offset + enterOffsetY)
    self:_setTipTextAppearance(1)

    local enterTween = TweenService:Create(label, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = basePosition,
    })

    enterTween.Completed:Connect(function()
        task.delay(holdSeconds, function()
            if not (label and label.Parent) then
                self._isShowingTip = false
                self:_showNextTip()
                return
            end

            local fadePositionTween = TweenService:Create(label, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Position = UDim2.new(basePosition.X.Scale, basePosition.X.Offset, basePosition.Y.Scale, basePosition.Y.Offset + fadeOffsetY),
            })
            local fadeAlphaTween = tweenTransparencyAlpha(
                self._tipsTextTransparencyTargets,
                0.35,
                Enum.EasingStyle.Quad,
                Enum.EasingDirection.Out,
                1,
                0
            )

            fadeAlphaTween.Completed:Connect(function()
                if label and label.Parent then
                    label.Position = basePosition
                    self:_setTipTextAppearance(1)
                end

                self._isShowingTip = false
                if #self._tipQueue <= 0 then
                    setVisibility(self._tipsRoot, false)
                end
                self:_showNextTip()
            end)

            fadePositionTween:Play()
            fadeAlphaTween:Play()
        end)
    end)

    enterTween:Play()
end

function RebirthController:_enqueueTip(message)
    if tostring(message or "") == "" then
        return
    end

    table.insert(self._tipQueue, tostring(message))
    self:_showNextTip()
end

function RebirthController:_getWrongSoundTemplate()
    if self._wrongSoundTemplate and self._wrongSoundTemplate.Parent then
        return self._wrongSoundTemplate
    end

    local soundName = tostring((GameConfig.REBIRTH or {}).WrongSoundTemplateName or "Wrong")
    local audioRoot = SoundService:FindFirstChild("Audio")
    local wrongSound = audioRoot and (audioRoot:FindFirstChild(soundName) or audioRoot:FindFirstChild(soundName, true)) or nil
    if wrongSound and wrongSound:IsA("Sound") then
        self._wrongSoundTemplate = wrongSound
        return wrongSound
    end

    if not self._didWarnMissingWrongSound then
        warn("[RebirthController] 找不到 SoundService/Audio/Wrong，使用回退音频资源。")
        self._didWarnMissingWrongSound = true
    end

    local fallbackSound = SoundService:FindFirstChild("_RebirthWrongFallback")
    if fallbackSound and fallbackSound:IsA("Sound") then
        self._wrongSoundTemplate = fallbackSound
        return fallbackSound
    end

    fallbackSound = Instance.new("Sound")
    fallbackSound.Name = "_RebirthWrongFallback"
    fallbackSound.SoundId = tostring((GameConfig.REBIRTH or {}).WrongSoundAssetId or "rbxassetid://118029437877580")
    fallbackSound.Volume = 1
    fallbackSound.Parent = SoundService
    self._wrongSoundTemplate = fallbackSound
    return fallbackSound
end

function RebirthController:_playWrongSound()
    local template = self:_getWrongSoundTemplate()
    if not template then
        return
    end

    local soundToPlay = template:Clone()
    soundToPlay.Looped = false
    soundToPlay.Parent = template.Parent or SoundService
    if soundToPlay.SoundId == "" then
        soundToPlay.SoundId = tostring((GameConfig.REBIRTH or {}).WrongSoundAssetId or "rbxassetid://118029437877580")
    end
    soundToPlay:Play()

    task.delay(3, function()
        if soundToPlay and soundToPlay.Parent then
            soundToPlay:Destroy()
        end
    end)
end

function RebirthController:_getSuccessSoundTemplate()
    if self._successSoundTemplate and self._successSoundTemplate.Parent then
        return self._successSoundTemplate
    end

    local audioRoot = SoundService:FindFirstChild("Audio")
    local successSound = audioRoot and (audioRoot:FindFirstChild(REBIRTH_SUCCESS_SOUND_TEMPLATE_NAME) or audioRoot:FindFirstChild(REBIRTH_SUCCESS_SOUND_TEMPLATE_NAME, true)) or nil
    if successSound and successSound:IsA("Sound") then
        self._successSoundTemplate = successSound
        return successSound
    end

    if not self._didWarnMissingSuccessSound then
        warn("[RebirthController] 找不到 SoundService/Audio/Get/Can You Feel the Love? (sting a)，使用回退音频资源。")
        self._didWarnMissingSuccessSound = true
    end

    local fallbackSound = SoundService:FindFirstChild(REBIRTH_SUCCESS_SOUND_FALLBACK_NAME)
    if fallbackSound and fallbackSound:IsA("Sound") then
        self._successSoundTemplate = fallbackSound
        return fallbackSound
    end

    fallbackSound = Instance.new("Sound")
    fallbackSound.Name = REBIRTH_SUCCESS_SOUND_FALLBACK_NAME
    fallbackSound.SoundId = REBIRTH_SUCCESS_SOUND_ASSET_ID
    fallbackSound.Volume = 1
    fallbackSound.Parent = SoundService
    self._successSoundTemplate = fallbackSound
    return fallbackSound
end

function RebirthController:_playSuccessSound()
    local template = self:_getSuccessSoundTemplate()
    if not template then
        return
    end

    local soundToPlay = template:Clone()
    soundToPlay.Looped = false
    soundToPlay.Parent = template.Parent or SoundService
    if soundToPlay.SoundId == "" then
        soundToPlay.SoundId = REBIRTH_SUCCESS_SOUND_ASSET_ID
    end
    soundToPlay:Play()

    task.delay(4, function()
        if soundToPlay and soundToPlay.Parent then
            soundToPlay:Destroy()
        end
    end)
end

function RebirthController:_formatCoinText(value)
    return FormatUtil.FormatCompactCurrencyCeil(value)
end

function RebirthController:_updateLeftTimeLabel()
    if self._leftTimeLabel and self._leftTimeLabel:IsA("TextLabel") then
        self._leftTimeLabel.Text = string.format("[%d]", math.max(0, math.floor(tonumber(self._state.rebirthLevel) or 0)))
    end
end

function RebirthController:_updateEntryRedPoint()
    if self._hasReceivedStatePayload ~= true then
        setVisibility(self._entryRedPoint, false)
        return
    end

    local requiredCoins = math.max(0, math.floor(tonumber(self._state.nextRequiredCoins) or 0))
    local canAffordRebirth = self._state.isMaxLevel ~= true
        and (requiredCoins <= 0 or self._currentCoins >= requiredCoins)

    setVisibility(self._entryRedPoint, canAffordRebirth)
end

function RebirthController:_setActionButtonVisualState(interactiveNode, colorTargets, isEnabled)
    if interactiveNode and interactiveNode:IsA("GuiButton") then
        interactiveNode.AutoButtonColor = isEnabled == true
    end

    applyColorEnabledState(colorTargets, isEnabled)
end

function RebirthController:_updateRewardUi()
    local currentBonusRate = math.max(0, math.floor(tonumber(self._state.currentBonusRate) or 0))
    local nextBonusRate = math.max(0, math.floor(tonumber(self._state.nextBonusRate) or 0))
    local currentRebirthLevel = math.max(0, math.floor(tonumber(self._state.rebirthLevel) or 0))
    local nextRebirthLevel = math.max(currentRebirthLevel + 1, math.floor(tonumber(self._state.nextRebirthLevel) or (currentRebirthLevel + 1)))

    if self._rewardNum1Label and self._rewardNum1Label:IsA("TextLabel") then
        self._rewardNum1Label.Text = string.format("x%d Cash", currentBonusRate)
    end

    if self._rewardNum2Label and self._rewardNum2Label:IsA("TextLabel") then
        self._rewardNum2Label.Text = string.format("x%d Cash", nextBonusRate)
    end

    if self._rebirthCurrentLabel and self._rebirthCurrentLabel:IsA("TextLabel") then
        self._rebirthCurrentLabel.Text = string.format("Rebirth %d", currentRebirthLevel)
    end

    if self._rebirthNextLabel and self._rebirthNextLabel:IsA("TextLabel") then
        self._rebirthNextLabel.Text = string.format("Rebirth %d", nextRebirthLevel)
    end
end

function RebirthController:_updateProgressUi()
    local requiredCoins = math.max(0, math.floor(tonumber(self._state.nextRequiredCoins) or 0))
    local progressRatio = 1
    if requiredCoins > 0 then
        progressRatio = math.clamp(self._currentCoins / requiredCoins, 0, 1)
    end

    self:_updateEntryRedPoint()

    if self._progressBar and self._progressBar:IsA("GuiObject") then
        self._progressBarBaseSize = self._progressBarBaseSize or self._progressBar.Size
        local baseSize = self._progressBarBaseSize
        self._progressBar.Size = UDim2.new(progressRatio, baseSize.X.Offset, baseSize.Y.Scale, baseSize.Y.Offset)
    end

    if self._progressNumLabel and self._progressNumLabel:IsA("TextLabel") then
        self._progressNumLabel.Text = string.format("%s/%s", self:_formatCoinText(self._currentCoins), self:_formatCoinText(requiredCoins))
    end

    local canAffordRebirth = requiredCoins <= 0 or self._currentCoins >= requiredCoins
    local buttonTarget = self._rebirthButtonRoot or self._rebirthButton
    if buttonTarget and buttonTarget:IsA("GuiObject") then
        buttonTarget.Visible = true
    end

    self:_setActionButtonVisualState(self._rebirthButton, self._rebirthButtonColorTargets, canAffordRebirth)
    self:_setActionButtonVisualState(
        self._rebirthBuyButton,
        self._rebirthBuyButtonColorTargets,
        math.max(0, math.floor(tonumber(self._state.developerProductId) or 0)) > 0
    )
end

function RebirthController:_renderAll()
    self:_updateLeftTimeLabel()
    self:_updateRewardUi()
    self:_updateProgressUi()
end

function RebirthController:_applyStatePayload(payload)
    if type(payload) ~= "table" then
        return
    end

    self._hasReceivedStatePayload = true
    self._state.rebirthLevel = math.max(0, math.floor(tonumber(payload.rebirthLevel) or 0))
    self._state.currentBonusRate = math.max(0, tonumber(payload.currentBonusRate) or 0)
    self._state.nextRebirthLevel = math.max(self._state.rebirthLevel + 1, math.floor(tonumber(payload.nextRebirthLevel) or (self._state.rebirthLevel + 1)))
    self._state.nextRequiredCoins = math.max(0, math.floor(tonumber(payload.nextRequiredCoins) or 0))
    self._state.nextBonusRate = math.max(0, tonumber(payload.nextBonusRate) or 0)
    self._state.developerProductId = math.max(
        0,
        math.floor(tonumber(payload.developerProductId) or tonumber(RebirthConfig.SkipProductId) or 0)
    )
    self._state.isMaxLevel = payload.isMaxLevel == true
    self._state.maxRebirthLevel = math.max(0, math.floor(tonumber(payload.maxRebirthLevel) or 0))
    if payload.currentCoins ~= nil then
        self._currentCoins = math.max(0, tonumber(payload.currentCoins) or 0)
    end
    self:_renderAll()
end
function RebirthController:_getHiddenNodesForModal()
    local hiddenNodes = {}
    if not self._mainGui then
        return hiddenNodes
    end

    for _, node in ipairs(self._mainGui:GetChildren()) do
        if node and node ~= self._rebirthRoot then
            table.insert(hiddenNodes, node)
        end
    end

    return hiddenNodes
end

function RebirthController:OpenRebirth()
    if not self._rebirthRoot then
        return
    end

    self:_renderAll()
    if self._modalController then
        self._modalController:OpenModal("Rebirth", self._rebirthRoot, {
            HiddenNodes = self:_getHiddenNodesForModal(),
        })
    elseif self._rebirthRoot:IsA("GuiObject") then
        self._rebirthRoot.Visible = true
    end
end

function RebirthController:CloseRebirth()
    if not self._rebirthRoot then
        return
    end

    if self._modalController then
        self._modalController:CloseModal("Rebirth")
    elseif self._rebirthRoot:IsA("GuiObject") then
        self._rebirthRoot.Visible = false
    end
end

function RebirthController:_bindMainUi()
    local mainGui = self:_getMainGui()
    if not mainGui then
        self:_warnOnce("MissingMain", "[RebirthController] 找不到 Main UI，重生系统暂不可用。")
        self:_clearUiBindings()
        return false
    end

    self._mainGui = mainGui
    self._leftSection = self:_findDescendantByNames(mainGui, { "Left" })
    self._leftRebirthRoot = self._leftSection and self:_findDescendantByNames(self._leftSection, { "Rebirth" }) or nil
    local openButton = self:_resolveInteractiveNode(self._leftRebirthRoot)
    self._entryRedPoint = self._leftRebirthRoot and self:_findDescendantByNames(self._leftRebirthRoot, { "RedPoint" }) or nil
    self._leftTimeLabel = self._leftRebirthRoot and self:_findDescendantByNames(self._leftRebirthRoot, { "Time" }) or nil
    self._rebirthRoot = self:_findRebirthRoot(mainGui, self._leftRebirthRoot)

    if not self._rebirthRoot then
        self:_warnOnce("MissingRebirthRoot", "[RebirthController] 找不到 Main/Rebirth，重生面板未启动。")
        self:_clearUiBindings()
        return false
    end

    local titleRoot = self:_findDescendantByNames(self._rebirthRoot, { "Title" })
    local rebirthInfoRoot = self:_findDescendantByNames(self._rebirthRoot, { "Rebirthinfo", "RebirthInfo" })
    local rewardBg = rebirthInfoRoot and self:_findDescendantByNames(rebirthInfoRoot, { "RewardBg" }) or nil
    self._closeButton = titleRoot and self:_findDescendantByNames(titleRoot, { "CloseButton" }) or nil
    self._rebirthButtonRoot = rebirthInfoRoot and self:_findDescendantByNames(rebirthInfoRoot, { "RebirthBtn" }) or nil
    self._rebirthButton = self:_resolveInteractiveNode(self._rebirthButtonRoot)
    self._rebirthBuyButtonRoot = rebirthInfoRoot and self:_findDescendantByNames(rebirthInfoRoot, { "RebirthBuy" }) or nil
    self._rebirthBuyButton = self:_resolveInteractiveNode(self._rebirthBuyButtonRoot)
    self._progressBg = rebirthInfoRoot and self:_findDescendantByNames(rebirthInfoRoot, { "ProgressBg" }) or nil
    self._progressBar = self._progressBg and self:_findDescendantByNames(self._progressBg, { "Progress" }) or nil
    self._progressNumLabel = self._progressBg and self:_findDescendantByNames(self._progressBg, { "Num" }) or nil
    self._progressBarBaseSize = self._progressBar and self._progressBar.Size or nil
    self._rewardNum1Label = rewardBg and self:_findDescendantByNames(rewardBg, { "Num1" }) or nil
    self._rewardNum2Label = rewardBg and self:_findDescendantByNames(rewardBg, { "Num2" }) or nil
    self._rebirthCurrentLabel = rewardBg and self:_findDescendantByNames(rewardBg, { "RebirthCurrent" }) or nil
    self._rebirthNextLabel = rewardBg and self:_findDescendantByNames(rewardBg, { "RebirthNext" }) or nil
    self._rebirthButtonColorTargets = collectColorTargets(self._rebirthButtonRoot or self._rebirthButton)
    self._rebirthBuyButtonColorTargets = collectColorTargets(self._rebirthBuyButtonRoot or self._rebirthBuyButton)

    self:_clearUiBindings()

    if openButton then
        openButton:SetAttribute("DisableUiClickSound", true)
        table.insert(self._uiConnections, openButton.Activated:Connect(function()
            self:OpenRebirth()
        end))
    else
        self:_warnOnce("MissingRebirthOpenButton", "[RebirthController] 找不到 Main/Left/Rebirth/TextButton，重生打开按钮未绑定。")
    end

    local closeInteractive = self:_resolveInteractiveNode(self._closeButton)
    if closeInteractive then
        table.insert(self._uiConnections, closeInteractive.Activated:Connect(function()
            self:CloseRebirth()
        end))
        self:_bindButtonFx(closeInteractive, {
            ScaleTarget = self._closeButton,
            RotationTarget = self._closeButton,
            HoverScale = 1.12,
            PressScale = 0.92,
            HoverRotation = 20,
            DisableClickSound = true,
        }, self._uiConnections)
    else
        self:_warnOnce("MissingRebirthCloseButton", "[RebirthController] 找不到 Main/Rebirth/Title/CloseButton。")
    end

    if self._rebirthButton then
        table.insert(self._uiConnections, self._rebirthButton.Activated:Connect(function()
            if self._requestRebirthEvent then
                self._requestRebirthEvent:FireServer()
            end
        end))
        self:_bindButtonFx(self._rebirthButton, {
            ScaleTarget = self._rebirthButtonRoot or self._rebirthButton,
            HoverScale = 1.05,
            PressScale = 0.93,
            HoverRotation = 0,
        }, self._uiConnections)
    else
        self:_warnOnce("MissingRebirthActionButton", "[RebirthController] 找不到 Main/Rebirth/Rebirthinfo/RebirthBtn。")
    end

    if self._rebirthBuyButton then
        table.insert(self._uiConnections, self._rebirthBuyButton.Activated:Connect(function()
            local productId = math.max(0, math.floor(tonumber(self._state.developerProductId) or tonumber(RebirthConfig.SkipProductId) or 0))
            if productId <= 0 then
                return
            end

            local success, err = pcall(function()
                MarketplaceService:PromptProductPurchase(localPlayer, productId)
            end)
            if not success then
                warn(string.format("[RebirthController] 打开付费重生购买弹窗失败 productId=%d err=%s", productId, tostring(err)))
            end
        end))
        self:_bindButtonFx(self._rebirthBuyButton, {
            ScaleTarget = self._rebirthBuyButtonRoot or self._rebirthBuyButton,
            HoverScale = 1.05,
            PressScale = 0.93,
            HoverRotation = 0,
        }, self._uiConnections)
    else
        self:_warnOnce("MissingRebirthBuyButton", "[RebirthController] 找不到 Main/Rebirth/Rebirthinfo/RebirthBuy。")
    end

    self:_renderAll()
    return true
end

function RebirthController:_queueRebind()
    if self._rebindQueued then
        return
    end

    self._rebindQueued = true
    task.defer(function()
        self._rebindQueued = false
        self:_bindMainUi()
    end)
end

function RebirthController:_scheduleRetryBind()
    task.spawn(function()
        local deadline = os.clock() + 12
        repeat
            if self:_bindMainUi() then
                return
            end
            task.wait(1)
        until os.clock() >= deadline
    end)
end

function RebirthController:Start()
    if self._started then
        return
    end
    self._started = true

    self._currentCoins = math.max(0, tonumber(localPlayer:GetAttribute("CashRaw")) or 0)
    self:_ensureTipNodes()

    local eventsRoot = ReplicatedStorage:WaitForChild(RemoteNames.RootFolder)
    local currencyEvents = eventsRoot:WaitForChild(RemoteNames.CurrencyEventsFolder)
    local systemEvents = eventsRoot:WaitForChild(RemoteNames.SystemEventsFolder)

    self._coinChangedEvent = currencyEvents:FindFirstChild(RemoteNames.Currency.CoinChanged) or currencyEvents:WaitForChild(RemoteNames.Currency.CoinChanged, 10)
    self._rebirthStateSyncEvent = systemEvents:FindFirstChild(RemoteNames.System.RebirthStateSync) or systemEvents:WaitForChild(RemoteNames.System.RebirthStateSync, 10)
    self._requestRebirthStateSyncEvent = systemEvents:FindFirstChild(RemoteNames.System.RequestRebirthStateSync) or systemEvents:WaitForChild(RemoteNames.System.RequestRebirthStateSync, 10)
    self._requestRebirthEvent = systemEvents:FindFirstChild(RemoteNames.System.RequestRebirth) or systemEvents:WaitForChild(RemoteNames.System.RequestRebirth, 10)
    self._rebirthFeedbackEvent = systemEvents:FindFirstChild(RemoteNames.System.RebirthFeedback) or systemEvents:WaitForChild(RemoteNames.System.RebirthFeedback, 10)

    if self._coinChangedEvent and self._coinChangedEvent:IsA("RemoteEvent") then
        table.insert(self._persistentConnections, self._coinChangedEvent.OnClientEvent:Connect(function(payload)
            if type(payload) == "table" then
                self._currentCoins = math.max(0, tonumber(payload.total) or 0)
                self:_updateProgressUi()
            end
        end))
    end

    if self._rebirthStateSyncEvent and self._rebirthStateSyncEvent:IsA("RemoteEvent") then
        table.insert(self._persistentConnections, self._rebirthStateSyncEvent.OnClientEvent:Connect(function(payload)
            self:_applyStatePayload(payload)
        end))
    else
        self:_warnOnce("MissingRebirthStateSync", "[RebirthController] 找不到 RebirthStateSync，重生面板不会自动刷新。")
    end

    if self._rebirthFeedbackEvent and self._rebirthFeedbackEvent:IsA("RemoteEvent") then
        table.insert(self._persistentConnections, self._rebirthFeedbackEvent.OnClientEvent:Connect(function(payload)
            local status = type(payload) == "table" and tostring(payload.status or "") or ""
            local message = type(payload) == "table" and tostring(payload.message or "") or ""
            if status == "Success" then
                self:_enqueueTip(message)
                self:_playSuccessSound()
            elseif status == "RequirementNotMet" then
                self:_playWrongSound()
            end
        end))
    end

    table.insert(self._persistentConnections, MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, isPurchased)
        if userId ~= localPlayer.UserId or isPurchased ~= true then
            return
        end

        local rebirthProductId = math.max(0, math.floor(tonumber(self._state.developerProductId) or tonumber(RebirthConfig.SkipProductId) or 0))
        if rebirthProductId <= 0 or productId ~= rebirthProductId then
            return
        end

        if self._requestRebirthStateSyncEvent then
            task.delay(1, function()
                self._requestRebirthStateSyncEvent:FireServer()
            end)
        end
    end))

    self:_scheduleRetryBind()

    local playerGui = self:_getPlayerGui()
    if playerGui then
        self._playerGuiAddedConnection = playerGui.ChildAdded:Connect(function(child)
            if child.Name == "Main" then
                self:_queueRebind()
            end
        end)
        self._playerGuiRemovingConnection = playerGui.ChildRemoved:Connect(function(child)
            if child.Name == "Main" then
                self:_queueRebind()
            end
        end)
    end

    self._characterAddedConnection = localPlayer.CharacterAdded:Connect(function()
        task.defer(function()
            self:_queueRebind()
        end)
    end)

    if self._requestRebirthStateSyncEvent and self._requestRebirthStateSyncEvent:IsA("RemoteEvent") then
        self._requestRebirthStateSyncEvent:FireServer()
    end
end

return RebirthController




