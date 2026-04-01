--[[
脚本名字: RebirthController
脚本文件: RebirthController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/RebirthController
]]

local Players = game:GetService("Players")
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
local RemoteNames = requireSharedModule("RemoteNames")

local RebirthController = {}
RebirthController.__index = RebirthController

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
        nextRequiredCoins = 0,
        nextBonusRate = 0,
        isMaxLevel = false,
        maxRebirthLevel = 0,
    }
    self._mainGui = nil
    self._leftSection = nil
    self._leftRebirthRoot = nil
    self._leftTimeLabel = nil
    self._rebirthRoot = nil
    self._closeButton = nil
    self._rebirthButtonRoot = nil
    self._rebirthButton = nil
    self._progressBg = nil
    self._progressBar = nil
    self._progressBarBaseSize = nil
    self._progressNumLabel = nil
    self._tipsRoot = nil
    self._tipsTextLabel = nil
    self._tipsBasePosition = nil
    self._tipQueue = {}
    self._isShowingTip = false
    self._wrongSoundTemplate = nil
    self._didWarnMissingWrongSound = false
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
    setVisibility(self._tipsRoot, false)
    return true
end
function RebirthController:_setTipTextAppearance(textTransparency, strokeTransparency)
    if not self._tipsTextLabel then
        return
    end

    self._tipsTextLabel.TextTransparency = textTransparency
    self._tipsTextLabel.TextStrokeTransparency = strokeTransparency
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
    self:_setTipTextAppearance(0, 0)

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

            local fadeTween = TweenService:Create(label, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                TextTransparency = 1,
                TextStrokeTransparency = 1,
                Position = UDim2.new(basePosition.X.Scale, basePosition.X.Offset, basePosition.Y.Scale, basePosition.Y.Offset + fadeOffsetY),
            })

            fadeTween.Completed:Connect(function()
                if label and label.Parent then
                    label.Position = basePosition
                    self:_setTipTextAppearance(0, 0)
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

function RebirthController:_formatCoinText(value)
    return "$" .. FormatUtil.FormatWithCommasCeil(value)
end

function RebirthController:_updateLeftTimeLabel()
    if self._leftTimeLabel and self._leftTimeLabel:IsA("TextLabel") then
        self._leftTimeLabel.Text = string.format("[%d]", math.max(0, math.floor(tonumber(self._state.rebirthLevel) or 0)))
    end
end

function RebirthController:_updateProgressUi()
    local requiredCoins = math.max(0, math.floor(tonumber(self._state.nextRequiredCoins) or 0))
    local progressRatio = 1
    if requiredCoins > 0 then
        progressRatio = math.clamp(self._currentCoins / requiredCoins, 0, 1)
    end

    if self._progressBar and self._progressBar:IsA("GuiObject") then
        self._progressBarBaseSize = self._progressBarBaseSize or self._progressBar.Size
        local baseSize = self._progressBarBaseSize
        self._progressBar.Size = UDim2.new(progressRatio, baseSize.X.Offset, baseSize.Y.Scale, baseSize.Y.Offset)
    end

    if self._progressNumLabel and self._progressNumLabel:IsA("TextLabel") then
        self._progressNumLabel.Text = string.format("%s/%s", self:_formatCoinText(self._currentCoins), self:_formatCoinText(requiredCoins))
    end

    local buttonTarget = self._rebirthButtonRoot or self._rebirthButton
    if buttonTarget and buttonTarget:IsA("GuiObject") then
        buttonTarget.Visible = self._state.isMaxLevel ~= true
    end
end

function RebirthController:_renderAll()
    self:_updateLeftTimeLabel()
    self:_updateProgressUi()
end

function RebirthController:_applyStatePayload(payload)
    if type(payload) ~= "table" then
        return
    end

    self._state.rebirthLevel = math.max(0, math.floor(tonumber(payload.rebirthLevel) or 0))
    self._state.currentBonusRate = math.max(0, tonumber(payload.currentBonusRate) or 0)
    self._state.nextRequiredCoins = math.max(0, math.floor(tonumber(payload.nextRequiredCoins) or 0))
    self._state.nextBonusRate = math.max(0, tonumber(payload.nextBonusRate) or 0)
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
    self._leftTimeLabel = self._leftRebirthRoot and self:_findDescendantByNames(self._leftRebirthRoot, { "Time" }) or nil
    self._rebirthRoot = self:_findRebirthRoot(mainGui, self._leftRebirthRoot)

    if not self._rebirthRoot then
        self:_warnOnce("MissingRebirthRoot", "[RebirthController] 找不到 Main/Rebirth，重生面板未启动。")
        self:_clearUiBindings()
        return false
    end

    local titleRoot = self:_findDescendantByNames(self._rebirthRoot, { "Title" })
    local rebirthInfoRoot = self:_findDescendantByNames(self._rebirthRoot, { "Rebirthinfo", "RebirthInfo" })
    self._closeButton = titleRoot and self:_findDescendantByNames(titleRoot, { "CloseButton" }) or nil
    self._rebirthButtonRoot = rebirthInfoRoot and self:_findDescendantByNames(rebirthInfoRoot, { "RebirthBtn" }) or nil
    self._rebirthButton = self:_resolveInteractiveNode(self._rebirthButtonRoot)
    self._progressBg = rebirthInfoRoot and self:_findDescendantByNames(rebirthInfoRoot, { "ProgressBg" }) or nil
    self._progressBar = self._progressBg and self:_findDescendantByNames(self._progressBg, { "Progress" }) or nil
    self._progressNumLabel = self._progressBg and self:_findDescendantByNames(self._progressBg, { "Num" }) or nil
    self._progressBarBaseSize = self._progressBar and self._progressBar.Size or nil

    self:_clearUiBindings()

    if openButton then
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
            elseif status == "RequirementNotMet" then
                self:_playWrongSound()
            end
        end))
    end

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




