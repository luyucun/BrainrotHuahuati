--[[
脚本名字: ModalController
脚本文件: ModalController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/ModalController
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

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
        "[ModalController] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local GameConfig = requireSharedModule("GameConfig")

local ModalController = {}
ModalController.__index = ModalController

local MODAL_SOUND_TEMPLATE_FOLDER_NAME = "UI"
local MODAL_SOUND_TEMPLATE_NAME = "UI Button custom open1"
local MODAL_SOUND_ASSET_ID = "rbxassetid://8968249401"
local MODAL_SOUND_FALLBACK_NAME = "_ModalOpenCloseFallback"

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

local function getVisibilityValue(instance)
    if not instance then
        return nil
    end

    if instance:IsA("LayerCollector") then
        return instance.Enabled
    end

    if instance:IsA("GuiObject") then
        return instance.Visible
    end

    return nil
end

local function setVisibilityValue(instance, isVisible)
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

local function resolveSoundTemplate(soundFolderName, soundName)
    local soundFolder = SoundService:FindFirstChild(soundFolderName)
    local soundTemplate = soundFolder and (soundFolder:FindFirstChild(soundName) or soundFolder:FindFirstChild(soundName, true)) or nil
    if soundTemplate and soundTemplate:IsA("Sound") then
        return soundTemplate
    end

    return nil
end

function ModalController.new()
    local self = setmetatable({}, ModalController)
    self._openModals = {}
    self._closingModals = {}
    self._hiddenNodeStateByNode = {}
    self._hiddenNodeRefCountByNode = {}
    self._activeTweensByModalKey = {}
    self._animationSerialByModalKey = {}
    self._modalOpenCloseSoundTemplate = nil
    self._visibilityChangedEvent = Instance.new("BindableEvent")
    self._coreBackpackModalRefCount = 0
    self._coreBackpackOriginalEnabled = nil
    self._didWarnMissingBlur = false
    self._didWarnMissingModalSound = false
    return self
end

function ModalController:_getCoreBackpackEnabled()
    local ok, enabled = pcall(function()
        return StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack)
    end)
    if ok then
        return enabled == true
    end

    return nil
end

function ModalController:_setCoreBackpackEnabled(enabled)
    pcall(function()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, enabled == true)
    end)
end

function ModalController:_retainCoreBackpackVisibility()
    local refCount = tonumber(self._coreBackpackModalRefCount) or 0
    if refCount <= 0 then
        self._coreBackpackOriginalEnabled = self:_getCoreBackpackEnabled()
    end

    self._coreBackpackModalRefCount = refCount + 1
    self:_setCoreBackpackEnabled(false)
end

function ModalController:_releaseCoreBackpackVisibility()
    local refCount = tonumber(self._coreBackpackModalRefCount) or 0
    if refCount <= 1 then
        self._coreBackpackModalRefCount = 0
        if self._coreBackpackOriginalEnabled ~= nil then
            self:_setCoreBackpackEnabled(self._coreBackpackOriginalEnabled)
        end
        self._coreBackpackOriginalEnabled = nil
        return
    end

    self._coreBackpackModalRefCount = refCount - 1
end

function ModalController:_stopTweens(modalKey)
    local tweenList = self._activeTweensByModalKey[modalKey]
    if not tweenList then
        return
    end

    for _, tween in ipairs(tweenList) do
        tween:Cancel()
    end

    self._activeTweensByModalKey[modalKey] = nil
end

function ModalController:_getNextAnimationSerial(modalKey)
    local nextSerial = (tonumber(self._animationSerialByModalKey[modalKey]) or 0) + 1
    self._animationSerialByModalKey[modalKey] = nextSerial
    return nextSerial
end

function ModalController:_isAnimationSerialCurrent(modalKey, animationSerial)
    return self._animationSerialByModalKey[modalKey] == animationSerial
end

function ModalController:_getBlurEffect()
    local blurName = tostring((GameConfig.UI and GameConfig.UI.ModalBlurName) or "Blur")
    local blurEffect = Lighting:FindFirstChild(blurName)
    if blurEffect and blurEffect:IsA("BlurEffect") then
        return blurEffect
    end

    blurEffect = Lighting:FindFirstChild(blurName, true)
    if blurEffect and blurEffect:IsA("BlurEffect") then
        return blurEffect
    end

    if not self._didWarnMissingBlur then
        warn(string.format("[ModalController] 找不到 Lighting/%s，弹框 Blur 效果将被跳过。", blurName))
        self._didWarnMissingBlur = true
    end

    return nil
end

function ModalController:_setBlurEnabled(enabled)
    local blurEffect = self:_getBlurEffect()
    if blurEffect then
        blurEffect.Enabled = enabled == true
    end
end

function ModalController:_retainHiddenNodes(hiddenNodes)
    for _, node in ipairs(hiddenNodes or {}) do
        if node then
            local refCount = tonumber(self._hiddenNodeRefCountByNode[node]) or 0
            if refCount <= 0 then
                self._hiddenNodeStateByNode[node] = getVisibilityValue(node)
            end

            self._hiddenNodeRefCountByNode[node] = refCount + 1
            setVisibilityValue(node, false)
        end
    end
end

function ModalController:_releaseHiddenNodes(hiddenNodes)
    for _, node in ipairs(hiddenNodes or {}) do
        if node then
            local refCount = tonumber(self._hiddenNodeRefCountByNode[node]) or 0
            if refCount <= 1 then
                local originalVisible = self._hiddenNodeStateByNode[node]
                if originalVisible ~= nil then
                    setVisibilityValue(node, originalVisible)
                end
                self._hiddenNodeRefCountByNode[node] = nil
                self._hiddenNodeStateByNode[node] = nil
            else
                self._hiddenNodeRefCountByNode[node] = refCount - 1
            end
        end
    end
end

function ModalController:IsModalOpen(modalKey)
    return self._openModals[modalKey] ~= nil or self._closingModals[modalKey] ~= nil
end

function ModalController:_hasTrackedModals()
    return next(self._openModals) ~= nil or next(self._closingModals) ~= nil
end

function ModalController:IsNodeHiddenByModal(node)
    if not node then
        return false
    end

    return (tonumber(self._hiddenNodeRefCountByNode[node]) or 0) > 0
end

function ModalController:GetVisibilityChangedEvent()
    local bindableEvent = self._visibilityChangedEvent
    return bindableEvent and bindableEvent.Event or nil
end

function ModalController:_notifyVisibilityChanged(modalKey, isOpen)
    local bindableEvent = self._visibilityChangedEvent
    if bindableEvent then
        bindableEvent:Fire(modalKey, isOpen == true)
    end
end

function ModalController:_getModalOpenCloseSoundTemplate()
    if self._modalOpenCloseSoundTemplate and self._modalOpenCloseSoundTemplate.Parent then
        return self._modalOpenCloseSoundTemplate
    end

    local soundTemplate = resolveSoundTemplate(MODAL_SOUND_TEMPLATE_FOLDER_NAME, MODAL_SOUND_TEMPLATE_NAME)
    if soundTemplate then
        self._modalOpenCloseSoundTemplate = soundTemplate
        return soundTemplate
    end

    if not self._didWarnMissingModalSound then
        warn(string.format(
            "[ModalController] 找不到 SoundService/%s/%s，使用回退音频资源。",
            MODAL_SOUND_TEMPLATE_FOLDER_NAME,
            MODAL_SOUND_TEMPLATE_NAME
        ))
        self._didWarnMissingModalSound = true
    end

    local fallbackSound = SoundService:FindFirstChild(MODAL_SOUND_FALLBACK_NAME)
    if fallbackSound and fallbackSound:IsA("Sound") then
        self._modalOpenCloseSoundTemplate = fallbackSound
        return fallbackSound
    end

    fallbackSound = Instance.new("Sound")
    fallbackSound.Name = MODAL_SOUND_FALLBACK_NAME
    fallbackSound.SoundId = MODAL_SOUND_ASSET_ID
    fallbackSound.Volume = 1
    fallbackSound.Parent = SoundService
    self._modalOpenCloseSoundTemplate = fallbackSound
    return fallbackSound
end

function ModalController:_playModalOpenCloseSound()
    local template = self:_getModalOpenCloseSoundTemplate()
    if not template then
        return
    end

    local soundToPlay = template:Clone()
    soundToPlay.Looped = false
    soundToPlay.Parent = template.Parent or SoundService
    if soundToPlay.SoundId == "" then
        soundToPlay.SoundId = MODAL_SOUND_ASSET_ID
    end
    soundToPlay:Play()

    task.delay(4, function()
        if soundToPlay and soundToPlay.Parent then
            soundToPlay:Destroy()
        end
    end)
end

function ModalController:OpenModal(modalKey, modalRoot, options)
    if type(modalKey) ~= "string" or modalKey == "" or not modalRoot then
        return false
    end

    self:_playModalOpenCloseSound()

    local uiScale = ensureUiScale(modalRoot)
    if not uiScale then
        setVisibilityValue(modalRoot, true)
        return false
    end

    local hiddenNodes = (type(options) == "table" and options.HiddenNodes) or {}
    local modalState = self._openModals[modalKey]
    if modalState then
        modalState.Root = modalRoot
        modalState.HiddenNodes = hiddenNodes
    else
        modalState = {
            Root = modalRoot,
            HiddenNodes = hiddenNodes,
        }
        self._openModals[modalKey] = modalState
        self:_retainHiddenNodes(hiddenNodes)
        self:_retainCoreBackpackVisibility()
    end

    self:_notifyVisibilityChanged(modalKey, true)
    self:_setBlurEnabled(true)
    self:_stopTweens(modalKey)

    local uiConfig = GameConfig.UI or {}
    local openFromScale = tonumber(uiConfig.ModalOpenFromScale) or 0.82
    local overshootScale = tonumber(uiConfig.ModalOpenOvershootScale) or 1.06
    local overshootDuration = tonumber(uiConfig.ModalOpenOvershootDuration) or 0.18
    local settleDuration = tonumber(uiConfig.ModalOpenSettleDuration) or 0.12
    local animationSerial = self:_getNextAnimationSerial(modalKey)

    setVisibilityValue(modalRoot, true)
    uiScale.Scale = openFromScale

    local overshootTween = TweenService:Create(uiScale, TweenInfo.new(overshootDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Scale = overshootScale,
    })
    local settleTween = TweenService:Create(uiScale, TweenInfo.new(settleDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Scale = 1,
    })

    self._activeTweensByModalKey[modalKey] = { overshootTween, settleTween }

    task.spawn(function()
        overshootTween:Play()
        overshootTween.Completed:Wait()

        if not self:_isAnimationSerialCurrent(modalKey, animationSerial) then
            return
        end

        settleTween:Play()
        settleTween.Completed:Wait()

        if not self:_isAnimationSerialCurrent(modalKey, animationSerial) then
            return
        end

        uiScale.Scale = 1
        self._activeTweensByModalKey[modalKey] = nil
    end)

    return true
end

function ModalController:CloseModal(modalKey, options)
    local modalState = self._openModals[modalKey]
    if not modalState then
        return false
    end

    self:_playModalOpenCloseSound()

    local modalRoot = modalState.Root
    local hiddenNodes = modalState.HiddenNodes or {}
    local immediate = type(options) == "table" and options.Immediate == true
    local didFinalize = false

    self._openModals[modalKey] = nil
    self._closingModals[modalKey] = modalState

    local function finalizeClose()
        if didFinalize then
            return
        end
        didFinalize = true

        self._closingModals[modalKey] = nil
        self:_releaseHiddenNodes(hiddenNodes)
        self:_releaseCoreBackpackVisibility()
        self:_notifyVisibilityChanged(modalKey, false)
        if not self:_hasTrackedModals() then
            self:_setBlurEnabled(false)
        end
    end

    if not modalRoot then
        finalizeClose()
        return false
    end

    local uiScale = ensureUiScale(modalRoot)
    if not uiScale or immediate then
        if uiScale then
            uiScale.Scale = 1
        end
        setVisibilityValue(modalRoot, false)
        self:_stopTweens(modalKey)
        self:_getNextAnimationSerial(modalKey)
        finalizeClose()
        return true
    end

    self:_stopTweens(modalKey)

    local uiConfig = GameConfig.UI or {}
    local overshootScale = tonumber(uiConfig.ModalCloseOvershootScale) or 1.04
    local overshootDuration = tonumber(uiConfig.ModalCloseOvershootDuration) or 0.1
    local closeToScale = tonumber(uiConfig.ModalCloseToScale) or 0.78
    local shrinkDuration = tonumber(uiConfig.ModalCloseShrinkDuration) or 0.14
    local animationSerial = self:_getNextAnimationSerial(modalKey)

    local overshootTween = TweenService:Create(uiScale, TweenInfo.new(overshootDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Scale = overshootScale,
    })
    local shrinkTween = TweenService:Create(uiScale, TweenInfo.new(shrinkDuration, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
        Scale = closeToScale,
    })

    self._activeTweensByModalKey[modalKey] = { overshootTween, shrinkTween }

    task.spawn(function()
        overshootTween:Play()
        overshootTween.Completed:Wait()

        if not self:_isAnimationSerialCurrent(modalKey, animationSerial) then
            finalizeClose()
            return
        end

        shrinkTween:Play()
        shrinkTween.Completed:Wait()

        if not self:_isAnimationSerialCurrent(modalKey, animationSerial) then
            finalizeClose()
            return
        end

        uiScale.Scale = 1
        setVisibilityValue(modalRoot, false)
        self._activeTweensByModalKey[modalKey] = nil
        finalizeClose()
    end)

    return true
end

return ModalController

