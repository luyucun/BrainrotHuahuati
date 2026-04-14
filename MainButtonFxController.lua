--[[
脚本名字: MainButtonFxController
脚本文件: MainButtonFxController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/MainButtonFxController
]]

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer

local TARGET_BUTTONS = {
    { section = "Left", name = "Index", rotateIcon = true, scaleTitleShadow = false },
    { section = "Left", name = "Rebirth", rotateIcon = true, scaleTitleShadow = false },
    { section = "Left", name = "Shop", rotateIcon = true, scaleTitleShadow = false },
    { section = "Left", name = "Jetpack", rotateIcon = true, scaleTitleShadow = false },
    { section = "Top", name = "Home", rotateIcon = false, scaleTitleShadow = true },
    { section = "Top", name = "Sell", rotateIcon = false, scaleTitleShadow = true },
    { section = "Top", name = "Shop", rotateIcon = false, scaleTitleShadow = true },
}

local WATCHED_NAMES = {
    Main = true,
    Left = true,
    Top = true,
    Index = true,
    Rebirth = true,
    Shop = true,
    Jetpack = true,
    Home = true,
    Sell = true,
    Icon = true,
}

local HOVER_SCALE_RATIO = 1.1
local PRESSED_SCALE_RATIO = 0.9
local HOVER_ROTATION_OFFSET = 20

local HOVER_TWEEN_INFO = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_TWEEN_INFO = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RESET_TWEEN_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local UI_CLICK_SOUND_TEMPLATE_FOLDER_NAME = "UI"
local UI_CLICK_SOUND_TEMPLATE_NAME = "Click Sound"
local UI_CLICK_SOUND_ASSET_ID = "rbxassetid://139421450430380"
local UI_CLICK_SOUND_FALLBACK_NAME = "_UiClickSoundFallback"
local BUTTON_CLICK_SOUND_DISABLED_ATTRIBUTE = "DisableUiClickSound"

local MainButtonFxController = {}
MainButtonFxController.__index = MainButtonFxController

local function buildTargetKey(sectionName, buttonName)
    return string.format("%s/%s", tostring(sectionName), tostring(buttonName))
end

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

local function computeCompensatedPosition(basePosition, guiObject, baseScale, targetScale)
    if not (basePosition and guiObject and guiObject:IsA("GuiObject")) then
        return basePosition
    end

    local absoluteSize = guiObject.AbsoluteSize
    local anchorPoint = guiObject.AnchorPoint
    local safeBaseScale = tonumber(baseScale) or 1
    local safeTargetScale = tonumber(targetScale) or safeBaseScale
    local deltaScale = safeTargetScale - safeBaseScale

    local offsetX = (anchorPoint.X - 0.5) * absoluteSize.X * deltaScale
    local offsetY = (anchorPoint.Y - 0.5) * absoluteSize.Y * deltaScale

    return UDim2.new(
        basePosition.X.Scale,
        basePosition.X.Offset + offsetX,
        basePosition.Y.Scale,
        basePosition.Y.Offset + offsetY
    )
end

local function resolveSoundTemplate(soundFolderName, soundName)
    local soundFolder = SoundService:FindFirstChild(soundFolderName)
    local soundTemplate = soundFolder and (soundFolder:FindFirstChild(soundName) or soundFolder:FindFirstChild(soundName, true)) or nil
    if soundTemplate and soundTemplate:IsA("Sound") then
        return soundTemplate
    end

    return nil
end

function MainButtonFxController.new()
    local self = setmetatable({}, MainButtonFxController)
    self._bindingsByKey = {}
    self._buttonClickConnectionsByButton = setmetatable({}, { __mode = "k" })
    self._didWarnByKey = {}
    self._didWarnMissingUiClickSound = false
    self._playerGuiAddedConnection = nil
    self._playerGuiRemovingConnection = nil
    self._characterAddedConnection = nil
    self._rebindQueued = false
    self._started = false
    self._uiClickSoundTemplate = nil
    return self
end

function MainButtonFxController:_warnOnce(key, message)
    if self._didWarnByKey[key] then
        return
    end

    self._didWarnByKey[key] = true
    warn(message)
end

function MainButtonFxController:_getPlayerGui()
    return localPlayer:FindFirstChild("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
end

function MainButtonFxController:_getUiClickSoundTemplate()
    if self._uiClickSoundTemplate and self._uiClickSoundTemplate.Parent then
        return self._uiClickSoundTemplate
    end

    local soundTemplate = resolveSoundTemplate(UI_CLICK_SOUND_TEMPLATE_FOLDER_NAME, UI_CLICK_SOUND_TEMPLATE_NAME)
    if soundTemplate then
        self._uiClickSoundTemplate = soundTemplate
        return soundTemplate
    end

    if not self._didWarnMissingUiClickSound then
        warn(string.format(
            "[MainButtonFxController] 找不到 SoundService/%s/%s，使用回退音频资源。",
            UI_CLICK_SOUND_TEMPLATE_FOLDER_NAME,
            UI_CLICK_SOUND_TEMPLATE_NAME
        ))
        self._didWarnMissingUiClickSound = true
    end

    local fallbackSound = SoundService:FindFirstChild(UI_CLICK_SOUND_FALLBACK_NAME, true)
    if fallbackSound and fallbackSound:IsA("Sound") then
        self._uiClickSoundTemplate = fallbackSound
        return fallbackSound
    end

    local soundFolder = SoundService:FindFirstChild(UI_CLICK_SOUND_TEMPLATE_FOLDER_NAME)
    fallbackSound = Instance.new("Sound")
    fallbackSound.Name = UI_CLICK_SOUND_FALLBACK_NAME
    fallbackSound.SoundId = UI_CLICK_SOUND_ASSET_ID
    fallbackSound.Volume = 1
    fallbackSound.Parent = soundFolder or SoundService
    self._uiClickSoundTemplate = fallbackSound
    return fallbackSound
end

function MainButtonFxController:_playUiClickSound()
    local template = self:_getUiClickSoundTemplate()
    if not template then
        return
    end

    local soundToPlay = template:Clone()
    soundToPlay.Looped = false
    soundToPlay.Parent = template.Parent or SoundService
    if soundToPlay.SoundId == "" then
        soundToPlay.SoundId = UI_CLICK_SOUND_ASSET_ID
    end
    soundToPlay:Play()

    task.delay(math.max(4, (tonumber(soundToPlay.TimeLength) or 0) + 1), function()
        if soundToPlay and soundToPlay.Parent then
            soundToPlay:Destroy()
        end
    end)
end

function MainButtonFxController:_bindButtonClickSound(button)
    if not (button and button:IsA("GuiButton")) then
        return
    end

    if self._buttonClickConnectionsByButton[button] then
        return
    end

    self._buttonClickConnectionsByButton[button] = button.Activated:Connect(function()
        if button:GetAttribute(BUTTON_CLICK_SOUND_DISABLED_ATTRIBUTE) == true then
            return
        end

        self:_playUiClickSound()
    end)
end

function MainButtonFxController:_bindExistingButtonClickSounds(root)
    if not root then
        return
    end

    if root:IsA("GuiButton") then
        self:_bindButtonClickSound(root)
    end

    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant:IsA("GuiButton") then
            self:_bindButtonClickSound(descendant)
        end
    end
end

function MainButtonFxController:_getMainGui()
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

function MainButtonFxController:_findButtonRoot(mainGui, sectionName, buttonName)
    if not mainGui then
        return nil
    end

    local section = mainGui:FindFirstChild(sectionName) or mainGui:FindFirstChild(sectionName, true)
    if not section then
        return nil
    end

    return section:FindFirstChild(buttonName) or section:FindFirstChild(buttonName, true)
end

function MainButtonFxController:_resolveInteractiveNode(buttonRoot)
    if not buttonRoot then
        return nil
    end

    if buttonRoot:IsA("GuiButton") then
        return buttonRoot
    end

    local textButton = buttonRoot:FindFirstChild("TextButton")
    if textButton and textButton:IsA("GuiButton") then
        return textButton
    end

    local imageButton = buttonRoot:FindFirstChild("ImageButton")
    if imageButton and imageButton:IsA("GuiButton") then
        return imageButton
    end

    return buttonRoot:FindFirstChildWhichIsA("GuiButton", true)
end

function MainButtonFxController:_resolveVisualNodes(buttonRoot, interactiveNode)
    local textNode = buttonRoot and buttonRoot:FindFirstChild("TextLabel")
    if not (textNode and textNode:IsA("GuiObject")) then
        textNode = buttonRoot and buttonRoot:FindFirstChild("TextLabel", true) or nil
    end
    if not (textNode and textNode:IsA("GuiObject")) then
        if interactiveNode and interactiveNode:IsA("TextButton") then
            textNode = interactiveNode
        elseif buttonRoot and buttonRoot:IsA("TextButton") then
            textNode = buttonRoot
        end
    end

    local iconNode = buttonRoot and buttonRoot:FindFirstChild("Icon")
    if not (iconNode and iconNode:IsA("GuiObject")) then
        iconNode = buttonRoot and buttonRoot:FindFirstChild("Icon", true) or nil
    end
    if not (iconNode and iconNode:IsA("GuiObject")) then
        iconNode = buttonRoot and buttonRoot:FindFirstChildWhichIsA("ImageLabel", true) or nil
    end
    if not (iconNode and iconNode:IsA("GuiObject")) then
        iconNode = buttonRoot and buttonRoot:FindFirstChildWhichIsA("ImageButton", true) or nil
    end

    local titleShadowNode = buttonRoot and buttonRoot:FindFirstChild("TitleShadow")
    if not (titleShadowNode and titleShadowNode:IsA("GuiObject")) then
        titleShadowNode = buttonRoot and buttonRoot:FindFirstChild("TitleShadow", true) or nil
    end

    if not (textNode and textNode:IsA("GuiObject")) then
        textNode = nil
    end
    if not (iconNode and iconNode:IsA("GuiObject")) then
        iconNode = nil
    end
    if not (titleShadowNode and titleShadowNode:IsA("GuiObject")) then
        titleShadowNode = nil
    end

    return textNode, iconNode, titleShadowNode
end
function MainButtonFxController:_cancelAndClearTween(binding, tweenKey)
    if not (binding and binding.tweens) then
        return
    end

    local existingTween = binding.tweens[tweenKey]
    if not existingTween then
        return
    end

    existingTween:Cancel()
    binding.tweens[tweenKey] = nil
end

function MainButtonFxController:_playTween(binding, tweenKey, instance, tweenInfo, goal)
    if not (binding and instance and tweenInfo and goal) then
        return
    end

    self:_cancelAndClearTween(binding, tweenKey)

    local tween = TweenService:Create(instance, tweenInfo, goal)
    binding.tweens[tweenKey] = tween
    tween.Completed:Connect(function()
        if binding.tweens[tweenKey] == tween then
            binding.tweens[tweenKey] = nil
        end
    end)
    tween:Play()
end

function MainButtonFxController:_applyVisualState(binding)
    if not binding then
        return
    end

    local scaleRatio = 1
    local rotationOffset = 0
    local hoverRotationOffset = tonumber(binding.hoverRotationOffset) or 0

    if binding.isPressed then
        scaleRatio = PRESSED_SCALE_RATIO
        rotationOffset = hoverRotationOffset
    elseif binding.isHovered then
        scaleRatio = HOVER_SCALE_RATIO
        rotationOffset = hoverRotationOffset
    end

    local tweenInfo = RESET_TWEEN_INFO
    if binding.isPressed then
        tweenInfo = PRESS_TWEEN_INFO
    elseif binding.isHovered then
        tweenInfo = HOVER_TWEEN_INFO
    end

    local targetTextScale = binding.baseTextScale * scaleRatio
    local targetIconScale = binding.baseIconScale * scaleRatio
    local targetTitleShadowScale = binding.baseTitleShadowScale * scaleRatio

    if binding.textScale then
        self:_playTween(binding, "textScale", binding.textScale, tweenInfo, {
            Scale = targetTextScale,
        })
    end

    if binding.textNode and binding.baseTextPosition then
        self:_playTween(binding, "textPosition", binding.textNode, tweenInfo, {
            Position = computeCompensatedPosition(
                binding.baseTextPosition,
                binding.textNode,
                binding.baseTextScale,
                targetTextScale
            ),
        })
    end

    if binding.titleShadowScale then
        self:_playTween(binding, "titleShadowScale", binding.titleShadowScale, tweenInfo, {
            Scale = targetTitleShadowScale,
        })
    end

    if binding.titleShadowNode and binding.baseTitleShadowPosition and binding.enableTitleShadowScale then
        self:_playTween(binding, "titleShadowPosition", binding.titleShadowNode, tweenInfo, {
            Position = computeCompensatedPosition(
                binding.baseTitleShadowPosition,
                binding.titleShadowNode,
                binding.baseTitleShadowScale,
                targetTitleShadowScale
            ),
        })
    end

    if binding.iconScale then
        self:_playTween(binding, "iconScale", binding.iconScale, tweenInfo, {
            Scale = targetIconScale,
        })
    end

    if binding.iconNode and binding.baseIconPosition then
        self:_playTween(binding, "iconPosition", binding.iconNode, tweenInfo, {
            Position = computeCompensatedPosition(
                binding.baseIconPosition,
                binding.iconNode,
                binding.baseIconScale,
                targetIconScale
            ),
        })
    end

    if binding.iconNode then
        self:_playTween(binding, "iconRotation", binding.iconNode, tweenInfo, {
            Rotation = binding.baseIconRotation + rotationOffset,
        })
    end
end
function MainButtonFxController:_disconnectBinding(targetKey)
    local binding = self._bindingsByKey[targetKey]
    if not binding then
        return
    end

    for _, connection in ipairs(binding.connections) do
        connection:Disconnect()
    end

    for tweenKey, _ in pairs(binding.tweens) do
        self:_cancelAndClearTween(binding, tweenKey)
    end

    self._bindingsByKey[targetKey] = nil
end

function MainButtonFxController:_createBinding(targetKey, buttonRoot, interactiveNode, textNode, iconNode, titleShadowNode, rotateIcon, scaleTitleShadow)
    local binding = {
        key = targetKey,
        buttonRoot = buttonRoot,
        interactiveNode = interactiveNode,
        textNode = textNode,
        iconNode = iconNode,
        titleShadowNode = titleShadowNode,
        hoverRotationOffset = rotateIcon and HOVER_ROTATION_OFFSET or 0,
        enableTitleShadowScale = scaleTitleShadow == true,
        textScale = nil,
        iconScale = nil,
        titleShadowScale = nil,
        baseTextScale = 1,
        baseTextPosition = textNode and textNode.Position or nil,
        baseIconScale = 1,
        baseIconPosition = iconNode and iconNode.Position or nil,
        baseTitleShadowScale = 1,
        baseTitleShadowPosition = titleShadowNode and titleShadowNode.Position or nil,
        baseIconRotation = iconNode and iconNode.Rotation or 0,
        isHovered = false,
        isPressed = false,
        connections = {},
        tweens = {},
    }

    if textNode then
        binding.textScale = ensureUiScale(textNode)
        if binding.textScale then
            binding.baseTextScale = binding.textScale.Scale
            binding.textScale.Scale = binding.baseTextScale
        end
    end

    if scaleTitleShadow and titleShadowNode then
        binding.titleShadowScale = ensureUiScale(titleShadowNode)
        if binding.titleShadowScale then
            binding.baseTitleShadowScale = binding.titleShadowScale.Scale
            binding.titleShadowScale.Scale = binding.baseTitleShadowScale
        end
    end

    if iconNode then
        binding.iconScale = ensureUiScale(iconNode)
        if binding.iconScale then
            binding.baseIconScale = binding.iconScale.Scale
            binding.iconScale.Scale = binding.baseIconScale
        end
        iconNode.Rotation = binding.baseIconRotation
    end

    table.insert(binding.connections, interactiveNode.MouseEnter:Connect(function()
        binding.isHovered = true
        self:_applyVisualState(binding)
    end))

    table.insert(binding.connections, interactiveNode.MouseLeave:Connect(function()
        binding.isHovered = false
        binding.isPressed = false
        self:_applyVisualState(binding)
    end))

    table.insert(binding.connections, interactiveNode.InputBegan:Connect(function(inputObject)
        local inputType = inputObject.UserInputType
        if inputType == Enum.UserInputType.Touch then
            binding.isHovered = true
            binding.isPressed = false
            self:_applyVisualState(binding)

            task.defer(function()
                if self._bindingsByKey[targetKey] ~= binding then
                    return
                end
                if not binding.isHovered then
                    return
                end
                binding.isPressed = true
                self:_applyVisualState(binding)
            end)
            return
        end

        if inputType == Enum.UserInputType.MouseButton1 then
            binding.isPressed = true
            self:_applyVisualState(binding)
        end
    end))

    table.insert(binding.connections, interactiveNode.InputEnded:Connect(function(inputObject)
        local inputType = inputObject.UserInputType
        if inputType == Enum.UserInputType.Touch then
            binding.isPressed = false
            binding.isHovered = false
            self:_applyVisualState(binding)
            return
        end

        if inputType == Enum.UserInputType.MouseButton1 then
            binding.isPressed = false
            self:_applyVisualState(binding)
        end
    end))

    self._bindingsByKey[targetKey] = binding
    self:_applyVisualState(binding)
end
function MainButtonFxController:_bindButton(mainGui, sectionName, buttonName, rotateIcon, scaleTitleShadow)
    local targetKey = buildTargetKey(sectionName, buttonName)
    local buttonRoot = self:_findButtonRoot(mainGui, sectionName, buttonName)
    if not buttonRoot then
        self:_warnOnce(
            targetKey .. "_MissingRoot",
            string.format("[MainButtonFxController] 找不到按钮节点: Main/%s/%s", tostring(sectionName), tostring(buttonName))
        )
        self:_disconnectBinding(targetKey)
        return false
    end

    local interactiveNode = self:_resolveInteractiveNode(buttonRoot)
    if not (interactiveNode and interactiveNode:IsA("GuiButton")) then
        self:_warnOnce(
            targetKey .. "_MissingButton",
            string.format("[MainButtonFxController] 找不到可交互按钮: Main/%s/%s", tostring(sectionName), tostring(buttonName))
        )
        self:_disconnectBinding(targetKey)
        return false
    end

    local textNode, iconNode, titleShadowNode = self:_resolveVisualNodes(buttonRoot, interactiveNode)
    if not textNode and not iconNode and not titleShadowNode then
        self:_warnOnce(
            targetKey .. "_MissingVisual",
            string.format("[MainButtonFxController] 按钮缺少可动画节点(TextLabel/Icon/TitleShadow): Main/%s/%s", tostring(sectionName), tostring(buttonName))
        )
        self:_disconnectBinding(targetKey)
        return false
    end

    local existingBinding = self._bindingsByKey[targetKey]
    local targetHoverRotation = rotateIcon and HOVER_ROTATION_OFFSET or 0
    local targetTitleShadowState = scaleTitleShadow == true
    if existingBinding
        and existingBinding.buttonRoot == buttonRoot
        and existingBinding.interactiveNode == interactiveNode
        and existingBinding.textNode == textNode
        and existingBinding.iconNode == iconNode
        and existingBinding.titleShadowNode == titleShadowNode
        and existingBinding.hoverRotationOffset == targetHoverRotation
        and existingBinding.enableTitleShadowScale == targetTitleShadowState
    then
        return true
    end

    if existingBinding then
        self:_disconnectBinding(targetKey)
    end

    self:_createBinding(targetKey, buttonRoot, interactiveNode, textNode, iconNode, titleShadowNode, rotateIcon, scaleTitleShadow)
    return true
end
function MainButtonFxController:_tryBindAllButtons()
    local mainGui = self:_getMainGui()
    if not mainGui then
        self:_warnOnce("MissingMain", "[MainButtonFxController] 找不到 Main UI，按钮动效暂不可用。")
        for targetKey, _ in pairs(self._bindingsByKey) do
            self:_disconnectBinding(targetKey)
        end
        return false
    end

    local success = true
    local activeKeys = {}
    for _, target in ipairs(TARGET_BUTTONS) do
        local key = buildTargetKey(target.section, target.name)
        activeKeys[key] = true
        local isBound = self:_bindButton(mainGui, target.section, target.name, target.rotateIcon, target.scaleTitleShadow)
        success = success and isBound
    end

    for targetKey, _ in pairs(self._bindingsByKey) do
        if not activeKeys[targetKey] then
            self:_disconnectBinding(targetKey)
        end
    end

    return success
end

function MainButtonFxController:_queueRebind()
    if self._rebindQueued then
        return
    end

    self._rebindQueued = true
    task.defer(function()
        self._rebindQueued = false
        self:_tryBindAllButtons()
    end)
end

function MainButtonFxController:_scheduleRetryBind()
    task.spawn(function()
        local deadline = os.clock() + 12
        repeat
            if self:_tryBindAllButtons() then
                return
            end
            task.wait(1)
        until os.clock() >= deadline
    end)
end

function MainButtonFxController:Start()
    if self._started then
        return
    end
    self._started = true

    self:_scheduleRetryBind()

    local playerGui = self:_getPlayerGui()
    if playerGui then
        self:_bindExistingButtonClickSounds(playerGui)
        self._playerGuiAddedConnection = playerGui.DescendantAdded:Connect(function(descendant)
            if descendant:IsA("GuiButton") then
                self:_bindButtonClickSound(descendant)
            end
            if WATCHED_NAMES[descendant.Name] then
                self:_queueRebind()
            end
        end)

        self._playerGuiRemovingConnection = playerGui.DescendantRemoving:Connect(function(descendant)
            if WATCHED_NAMES[descendant.Name] then
                self:_queueRebind()
            end
        end)
    end

    self._characterAddedConnection = localPlayer.CharacterAdded:Connect(function()
        task.defer(function()
            self:_queueRebind()
        end)
    end)
end

return MainButtonFxController

