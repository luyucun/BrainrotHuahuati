--[[
Script: ShopController
Type: ModuleScript
Studio path: StarterPlayer/StarterPlayerScripts/Controllers/ShopController
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TextChatService = game:GetService("TextChatService")
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

    error(string.format("[ShopController] Missing shared module %s.", tostring(moduleName)))
end

local function requireControllerModule(moduleName)
    local controllersFolder = script.Parent
    if controllersFolder then
        local moduleInControllers = controllersFolder:FindFirstChild(moduleName)
        if moduleInControllers and moduleInControllers:IsA("ModuleScript") then
            return require(moduleInControllers)
        end
    end

    error(string.format("[ShopController] Missing controller module %s.", tostring(moduleName)))
end

local GameConfig = requireSharedModule("GameConfig")
local RemoteNames = requireSharedModule("RemoteNames")
local IndexController = requireControllerModule("IndexController")

local ShopController = {}
ShopController.__index = ShopController

local STARTUP_WARNING_GRACE_SECONDS = 2
local SHOP_OPEN_EXTRA_SOUND_TEMPLATE_FOLDER_NAME = "UI"
local SHOP_OPEN_EXTRA_SOUND_TEMPLATE_NAME = "Coin Clinking Sound"
local SHOP_OPEN_EXTRA_SOUND_ASSET_ID = "rbxassetid://133570405319995"
local SHOP_OPEN_EXTRA_SOUND_FALLBACK_NAME = "_ShopOpenCoinClinkFallback"
local PURCHASE_SUCCESS_SOUND_TEMPLATE_FOLDER_NAME = "Audio"
local PURCHASE_SUCCESS_SOUND_TEMPLATE_NAME = "LevelUp01"
local PURCHASE_SUCCESS_SOUND_ASSET_ID = "rbxassetid://371274037"
local PURCHASE_SUCCESS_SOUND_FALLBACK_NAME = "_ShopPurchaseSuccessFallback"

local function getShopConfig()
    return GameConfig.SHOP or {}
end

local function getShopModalKey()
    return tostring(getShopConfig().ModalKey or "Shop")
end

local function getVipGamePassId()
    return math.max(0, math.floor(tonumber(getShopConfig().VipGamePassId) or 0))
end

local function getVipPriceRobux()
    return math.max(0, math.floor(tonumber(getShopConfig().VipPriceRobux) or 0))
end

local function getVipOwnedAttributeName()
    return tostring(getShopConfig().VipOwnedAttributeName or "VipOwned")
end

local function getVipOwnedText()
    return tostring(getShopConfig().VipOwnedText or "Owned")
end

local function getVipPromptingText()
    return tostring(getShopConfig().VipPromptingText or "...")
end

local function getVipTagColor()
    return tostring(getShopConfig().VipTagColor or "#FFC93C")
end

local function getStarterPackGamePassId()
    local starterPackConfig = GameConfig.STARTER_PACK or {}
    return math.max(0, math.floor(tonumber(starterPackConfig.GamePassId) or 0))
end

local function getPurchaseSyncRetrySeconds()
    return math.max(0.2, tonumber(getShopConfig().PurchaseSyncRetrySeconds) or 0.8)
end

local function getPurchaseSyncMaxAttempts()
    return math.max(1, math.floor(tonumber(getShopConfig().PurchaseSyncMaxAttempts) or 8))
end

local function getServerLuckyNodeNames()
    local configuredNames = getShopConfig().ServerLuckyNodeNames
    if type(configuredNames) == "table" and #configuredNames > 0 then
        return configuredNames
    end

    return { "Lukcy" }
end

local function getServerLuckyProductId()
    return math.max(0, math.floor(tonumber(getShopConfig().ServerLuckyProductId) or 0))
end

local function getServerLuckyPriceRobux()
    return math.max(0, math.floor(tonumber(getShopConfig().ServerLuckyPriceRobux) or 0))
end

local function getServerLuckyExpireAtAttributeName()
    return tostring(getShopConfig().ServerLuckyExpireAtAttributeName or "ServerLuckyExpireAt")
end

local function getServerLuckyLastBuyerNameAttributeName()
    return tostring(getShopConfig().ServerLuckyLastBuyerNameAttributeName or "ServerLuckyLastBuyerName")
end

local function getServerLuckyPurchaseSerialAttributeName()
    return tostring(getShopConfig().ServerLuckyPurchaseSerialAttributeName or "ServerLuckyPurchaseSerial")
end

local function getServerLuckyTipTemplate()
    return tostring(getShopConfig().ServerLuckyTipTemplate or "[%s] increased the server's luck!")
end

local function getServerLuckyCountdownUpdateInterval()
    return math.max(0.05, tonumber(getShopConfig().ServerLuckyCountdownUpdateInterval) or 0.25)
end

local function getServerLuckyTipDisplaySeconds()
    return math.max(0.2, tonumber(getShopConfig().ServerLuckyTipDisplaySeconds) or 2)
end

local function getServerLuckyTipEnterOffsetY()
    return math.floor(tonumber(getShopConfig().ServerLuckyTipEnterOffsetY) or 40)
end

local function getServerLuckyTipFadeOffsetY()
    return math.floor(tonumber(getShopConfig().ServerLuckyTipFadeOffsetY) or -8)
end

local function getServerLuckyTipFadeInSeconds()
    return math.max(0.05, tonumber(getShopConfig().ServerLuckyTipFadeInSeconds) or 0.25)
end

local function getServerLuckyTipFadeOutSeconds()
    return math.max(0.05, tonumber(getShopConfig().ServerLuckyTipFadeOutSeconds) or 0.35)
end

local function getPurchaseSuccessTipText()
    return tostring(getShopConfig().PurchaseSuccessTipText or "Purchase Successful!")
end

local function getPurchaseSuccessTipDisplaySeconds()
    return math.max(0.2, tonumber(getShopConfig().PurchaseSuccessTipDisplaySeconds) or 2)
end

local function getPurchaseSuccessTipEnterOffsetY()
    return math.floor(tonumber(getShopConfig().PurchaseSuccessTipEnterOffsetY) or 40)
end

local function getPurchaseSuccessTipFadeOffsetY()
    return math.floor(tonumber(getShopConfig().PurchaseSuccessTipFadeOffsetY) or -8)
end

local function getPurchaseSuccessTipFadeInSeconds()
    return math.max(0.05, tonumber(getShopConfig().PurchaseSuccessTipFadeInSeconds) or 0.25)
end

local function getPurchaseSuccessTipFadeOutSeconds()
    return math.max(0.05, tonumber(getShopConfig().PurchaseSuccessTipFadeOutSeconds) or 0.35)
end

local function getLuckyBlockBundleNodeName()
    return tostring(getShopConfig().LuckyBlockBundleNodeName or "LukcyBlock")
end

local function getLuckyBlockIconFloatOffsetPx()
    return math.max(1, math.floor(tonumber(getShopConfig().LuckyBlockIconFloatOffsetPx) or 12))
end

local function getLuckyBlockIconFloatDurationSeconds()
    return math.max(0.05, tonumber(getShopConfig().LuckyBlockIconFloatDurationSeconds) or 1.15)
end

local function getLuckyBlockLightRotateDurationSeconds()
    return math.max(0.05, tonumber(getShopConfig().LuckyBlockLightRotateDurationSeconds) or 3.8)
end

local function getNormalizedLuckyBlockBundleOffersByButtonName()
    local offersByButtonName = {}
    local rawOffers = getShopConfig().LuckyBlockBundleOffers
    if type(rawOffers) ~= "table" then
        return offersByButtonName
    end

    for offerKey, rawOffer in pairs(rawOffers) do
        if type(rawOffer) == "table" then
            local buttonName = tostring(rawOffer.ButtonName or offerKey or "")
            if buttonName ~= "" then
                offersByButtonName[buttonName] = {
                    ButtonName = buttonName,
                    ProductId = math.max(0, math.floor(tonumber(rawOffer.ProductId) or 0)),
                    BlockId = math.max(0, math.floor(tonumber(rawOffer.BlockId) or 0)),
                    Quantity = math.max(0, math.floor(tonumber(rawOffer.Quantity) or 0)),
                    PriceRobux = rawOffer.PriceRobux ~= nil
                        and math.max(0, math.floor(tonumber(rawOffer.PriceRobux) or 0))
                        or nil,
                }
            end
        end
    end

    return offersByButtonName
end

local function getNormalizedCashOffersByNodeName()
    local offersByNodeName = {}
    local rawOffers = getShopConfig().CashOffers
    if type(rawOffers) ~= "table" then
        return offersByNodeName
    end

    for offerKey, rawOffer in pairs(rawOffers) do
        if type(rawOffer) == "table" then
            local nodeName = tostring(rawOffer.NodeName or offerKey or "")
            if nodeName ~= "" then
                offersByNodeName[nodeName] = {
                    NodeName = nodeName,
                    ProductId = math.max(0, math.floor(tonumber(rawOffer.ProductId) or 0)),
                    PriceRobux = math.max(0, math.floor(tonumber(rawOffer.PriceRobux) or 0)),
                    CoinAmount = math.max(0, tonumber(rawOffer.CoinAmount) or 0),
                }
            end
        end
    end

    return offersByNodeName
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

local function isLiveInstance(instance)
    return instance ~= nil and instance.Parent ~= nil
end

local function isNestedUnderGuiButton(node, root)
    local current = node and node.Parent or nil
    while current and current ~= root do
        if current:IsA("GuiButton") then
            return true
        end
        current = current.Parent
    end

    return false
end

local function getSharedServerTimeNow()
    local ok, serverTimeNow = pcall(function()
        return Workspace:GetServerTimeNow()
    end)
    if ok then
        return math.max(0, tonumber(serverTimeNow) or 0)
    end

    return math.max(0, tonumber(os.time()) or 0)
end

local function formatServerLuckyCountdownText(remainingSeconds)
    local safeRemaining = math.max(0, math.floor((tonumber(remainingSeconds) or 0) + 0.999))
    local minutes = math.floor(safeRemaining / 60)
    local seconds = safeRemaining % 60
    return string.format("%02d:%02d", minutes, seconds)
end

local function offsetY(position, yOffset)
    return UDim2.new(
        position.X.Scale,
        position.X.Offset,
        position.Y.Scale,
        position.Y.Offset + yOffset
    )
end

local function rememberTransparencyTarget(targets, instance, propertyName)
    local ok, currentValue = pcall(function()
        return instance[propertyName]
    end)
    if ok then
        targets[#targets + 1] = {
            instance = instance,
            propertyName = propertyName,
            baseValue = currentValue,
        }
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

local function setGuiVisibility(node, visible)
    if not node then
        return
    end

    if node:IsA("ScreenGui") then
        node.Enabled = visible
        return
    end

    if node:IsA("GuiObject") then
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

function ShopController.new(modalController)
    local self = setmetatable({}, ShopController)
    self._modalController = modalController
    self._indexHelper = IndexController.new(nil)
    self._started = false
    self._startupWarnAt = 0
    self._rebindQueued = false
    self._persistentConnections = {}
    self._uiConnections = {}
    self._didWarnByKey = {}
    self._mainGui = nil
    self._leftRoot = nil
    self._leftShopRoot = nil
    self._openButton = nil
    self._shopRoot = nil
    self._closeButton = nil
    self._scrollingFrame = nil
    self._requestShopStateSyncEvent = nil
    self._starterPackStateSyncEvent = nil
    self._requestStarterPackStateSyncEvent = nil
    self._vipRoot = nil
    self._vipBuyButton = nil
    self._vipPriceLabel = nil
    self._vipPriceIcon = nil
    self._vipOwnedLabel = nil
    self._starterPackRoot = nil
    self._starterPackBuyButton = nil
    self._starterPackPriceLabel = nil
    self._starterPackPriceIcon = nil
    self._starterPackState = {
        showEntry = getStarterPackGamePassId() > 0,
        isOwned = false,
        hasGranted = false,
        gamePassId = getStarterPackGamePassId(),
    }
    self._serverLuckyRefs = {}
    self._serverLuckyTipsRoot = nil
    self._serverLuckyTipsTextLabel = nil
    self._serverLuckyTipsBasePosition = nil
    self._serverLuckyTipsTransparencyTargets = nil
    self._serverLuckyTipQueue = {}
    self._isShowingServerLuckyTip = false
    self._didWarnMissingServerLuckyTips = false
    self._didWarnMissingServerLuckyTipsText = false
    self._purchaseTipsRoot = nil
    self._purchaseTipsTextLabel = nil
    self._purchaseTipsBasePosition = nil
    self._purchaseTipsTransparencyTargets = nil
    self._purchaseTipQueue = {}
    self._isShowingPurchaseTip = false
    self._didWarnMissingPurchaseTips = false
    self._didWarnMissingPurchaseTipsText = false
    self._lastServerLuckyTipSerialSeen = math.max(0, math.floor(tonumber(
        ReplicatedStorage:GetAttribute(getServerLuckyPurchaseSerialAttributeName())
    ) or 0))
    self._cashOfferRefsByNodeName = {}
    self._luckyBlockBundleRoot = nil
    self._luckyBlockBundleOfferRefsByButtonName = {}
    self._luckyBlockIconNode = nil
    self._luckyBlockIconBasePosition = nil
    self._luckyBlockLightNode = nil
    self._luckyBlockLightBaseRotation = 0
    self._luckyBlockAnimationSerial = 0
    self._luckyBlockIconTween = nil
    self._luckyBlockLightTween = nil
    self._isVipOwned = localPlayer:GetAttribute(getVipOwnedAttributeName()) == true
    self._isVipPrompting = false
    self._activeVipGamePassId = 0
    self._isStarterPackPrompting = false
    self._activeStarterPackGamePassId = 0
    self._vipPollSerial = 0
    self._starterPackPollSerial = 0
    self._didInstallChatStyling = false
    self._shopOpenExtraSoundTemplate = nil
    self._didWarnMissingShopOpenExtraSound = false
    self._purchaseSuccessSoundTemplate = nil
    self._didWarnMissingPurchaseSuccessSound = false
    return self
end

function ShopController:_warnOnce(key, message)
    if self._didWarnByKey[key] then
        return
    end

    self._didWarnByKey[key] = true
    warn(message)
end

function ShopController:_shouldWarnBindingIssues()
    return os.clock() >= (self._startupWarnAt or 0)
end

function ShopController:_getPlayerGui()
    return localPlayer:FindFirstChild("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
end

function ShopController:_getMainGui()
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

function ShopController:_getShopOpenExtraSoundTemplate()
    if self._shopOpenExtraSoundTemplate and self._shopOpenExtraSoundTemplate.Parent then
        return self._shopOpenExtraSoundTemplate
    end

    local soundTemplate = resolveSoundTemplate(
        SHOP_OPEN_EXTRA_SOUND_TEMPLATE_FOLDER_NAME,
        SHOP_OPEN_EXTRA_SOUND_TEMPLATE_NAME
    )
    if soundTemplate then
        self._shopOpenExtraSoundTemplate = soundTemplate
        return soundTemplate
    end

    if not self._didWarnMissingShopOpenExtraSound then
        warn(string.format(
            "[ShopController] 找不到 SoundService/%s/%s，使用回退音频资源。",
            SHOP_OPEN_EXTRA_SOUND_TEMPLATE_FOLDER_NAME,
            SHOP_OPEN_EXTRA_SOUND_TEMPLATE_NAME
        ))
        self._didWarnMissingShopOpenExtraSound = true
    end

    local fallbackSound = SoundService:FindFirstChild(SHOP_OPEN_EXTRA_SOUND_FALLBACK_NAME)
    if fallbackSound and fallbackSound:IsA("Sound") then
        self._shopOpenExtraSoundTemplate = fallbackSound
        return fallbackSound
    end

    fallbackSound = Instance.new("Sound")
    fallbackSound.Name = SHOP_OPEN_EXTRA_SOUND_FALLBACK_NAME
    fallbackSound.SoundId = SHOP_OPEN_EXTRA_SOUND_ASSET_ID
    fallbackSound.Volume = 1
    fallbackSound.Parent = SoundService
    self._shopOpenExtraSoundTemplate = fallbackSound
    return fallbackSound
end

function ShopController:_playShopOpenExtraSound()
    local template = self:_getShopOpenExtraSoundTemplate()
    if not template then
        return
    end

    local soundToPlay = template:Clone()
    soundToPlay.Looped = false
    soundToPlay.Parent = template.Parent or SoundService
    if soundToPlay.SoundId == "" then
        soundToPlay.SoundId = SHOP_OPEN_EXTRA_SOUND_ASSET_ID
    end
    soundToPlay:Play()

    task.delay(4, function()
        if soundToPlay and soundToPlay.Parent then
            soundToPlay:Destroy()
        end
    end)
end

function ShopController:_getPurchaseSuccessSoundTemplate()
    if self._purchaseSuccessSoundTemplate and self._purchaseSuccessSoundTemplate.Parent then
        return self._purchaseSuccessSoundTemplate
    end

    local soundTemplate = resolveSoundTemplate(
        PURCHASE_SUCCESS_SOUND_TEMPLATE_FOLDER_NAME,
        PURCHASE_SUCCESS_SOUND_TEMPLATE_NAME
    )
    if soundTemplate then
        self._purchaseSuccessSoundTemplate = soundTemplate
        return soundTemplate
    end

    if not self._didWarnMissingPurchaseSuccessSound then
        warn(string.format(
            "[ShopController] 找不到 SoundService/%s/%s，使用回退音频资源。",
            PURCHASE_SUCCESS_SOUND_TEMPLATE_FOLDER_NAME,
            PURCHASE_SUCCESS_SOUND_TEMPLATE_NAME
        ))
        self._didWarnMissingPurchaseSuccessSound = true
    end

    local fallbackSound = SoundService:FindFirstChild(PURCHASE_SUCCESS_SOUND_FALLBACK_NAME)
    if fallbackSound and fallbackSound:IsA("Sound") then
        self._purchaseSuccessSoundTemplate = fallbackSound
        return fallbackSound
    end

    fallbackSound = Instance.new("Sound")
    fallbackSound.Name = PURCHASE_SUCCESS_SOUND_FALLBACK_NAME
    fallbackSound.SoundId = PURCHASE_SUCCESS_SOUND_ASSET_ID
    fallbackSound.Volume = 1
    fallbackSound.Parent = SoundService
    self._purchaseSuccessSoundTemplate = fallbackSound
    return fallbackSound
end

function ShopController:_playPurchaseSuccessSound()
    local template = self:_getPurchaseSuccessSoundTemplate()
    if not template then
        return
    end

    local soundToPlay = template:Clone()
    soundToPlay.Looped = false
    soundToPlay.Parent = template.Parent or SoundService
    if soundToPlay.SoundId == "" then
        soundToPlay.SoundId = PURCHASE_SUCCESS_SOUND_ASSET_ID
    end
    soundToPlay:Play()

    task.delay(4, function()
        if soundToPlay and soundToPlay.Parent then
            soundToPlay:Destroy()
        end
    end)
end

function ShopController:_findDirectChildByName(root, childName)
    if not root then
        return nil
    end

    local child = root:FindFirstChild(childName)
    if child then
        return child
    end

    for _, descendant in ipairs(root:GetChildren()) do
        if descendant.Name == childName then
            return descendant
        end
    end

    return nil
end

function ShopController:_findDescendantByNames(root, names)
    return self._indexHelper:_findDescendantByNames(root, names)
end

function ShopController:_findByPath(root, pathNames)
    if not root then
        return nil
    end

    local current = root
    for _, name in ipairs(pathNames) do
        current = current and current:FindFirstChild(name) or nil
        if not current then
            return nil
        end
    end

    return current
end

function ShopController:_resolveInteractiveNode(node)
    return self._indexHelper:_resolveInteractiveNode(node)
end

function ShopController:_bindButtonFx(interactiveNode, options, connectionBucket)
    self._indexHelper:_bindButtonFx(interactiveNode, options, connectionBucket)
end

function ShopController:_isShopModalOpen()
    if self._modalController and self._modalController.IsModalOpen then
        return self._modalController:IsModalOpen(getShopModalKey())
    end

    return isLiveInstance(self._shopRoot) and self._shopRoot.Visible == true
end

function ShopController:_getHiddenNodesForModal()
    local hiddenNodes = {}
    if not self._mainGui then
        return hiddenNodes
    end

    for _, node in ipairs(self._mainGui:GetChildren()) do
        if node and node ~= self._shopRoot then
            table.insert(hiddenNodes, node)
        end
    end

    return hiddenNodes
end

function ShopController:_collectActionButtons(closeInteractive)
    local result = {}
    if not self._shopRoot then
        return result
    end

    for _, descendant in ipairs(self._shopRoot:GetDescendants()) do
        if descendant:IsA("GuiButton")
            and descendant ~= closeInteractive
            and not isNestedUnderGuiButton(descendant, self._shopRoot)
        then
            table.insert(result, descendant)
        end
    end

    return result
end

function ShopController:_clearUiBindings()
    disconnectAll(self._uiConnections)
    self:_stopLuckyBlockBundleAnimations()
    self._starterPackRoot = nil
    self._starterPackBuyButton = nil
    self._starterPackPriceLabel = nil
    self._starterPackPriceIcon = nil
    self._vipRoot = nil
    self._vipBuyButton = nil
    self._vipPriceLabel = nil
    self._vipPriceIcon = nil
    self._vipOwnedLabel = nil
    self._serverLuckyRefs = {}
    self._cashOfferRefsByNodeName = {}
    self._luckyBlockBundleRoot = nil
    self._luckyBlockBundleOfferRefsByButtonName = {}
    self._luckyBlockIconNode = nil
    self._luckyBlockIconBasePosition = nil
    self._luckyBlockLightNode = nil
    self._luckyBlockLightBaseRotation = 0
end

function ShopController:_getServerLuckyExpireAt()
    return math.max(0, tonumber(ReplicatedStorage:GetAttribute(getServerLuckyExpireAtAttributeName())) or 0)
end

function ShopController:_getServerLuckyRemainingSeconds()
    return math.max(0, self:_getServerLuckyExpireAt() - getSharedServerTimeNow())
end

function ShopController:_setServerLuckyTipsVisible(visible)
    setGuiVisibility(self._serverLuckyTipsRoot, visible == true)
end

function ShopController:_setServerLuckyTipsAppearance(alpha)
    applyTransparencyAlpha(self._serverLuckyTipsTransparencyTargets, alpha)
end

function ShopController:_ensureServerLuckyTipsNodes()
    if self._serverLuckyTipsRoot
        and self._serverLuckyTipsRoot.Parent
        and self._serverLuckyTipsTextLabel
        and self._serverLuckyTipsTextLabel.Parent
    then
        return true
    end

    local playerGui = self:_getPlayerGui()
    if not playerGui then
        if not self._didWarnMissingServerLuckyTips then
            warn("[ShopController] PlayerGui is missing; SeverLuckyBuyTips is unavailable.")
            self._didWarnMissingServerLuckyTips = true
        end
        return false
    end

    local mainGui = self:_getMainGui()
    local tipsRoot = nil
    if mainGui then
        tipsRoot = self:_findDirectChildByName(mainGui, "SeverLuckyBuyTips")
            or self:_findDescendantByNames(mainGui, { "SeverLuckyBuyTips" })
    end
    if not tipsRoot then
        tipsRoot = playerGui:FindFirstChild("SeverLuckyBuyTips", true)
    end

    if not tipsRoot then
        if not self._didWarnMissingServerLuckyTips then
            warn("[ShopController] SeverLuckyBuyTips UI is missing.")
            self._didWarnMissingServerLuckyTips = true
        end
        return false
    end

    local textLabel = tipsRoot:FindFirstChild("Text", true)
    if not (textLabel and textLabel:IsA("TextLabel")) then
        textLabel = tipsRoot:FindFirstChildWhichIsA("TextLabel", true)
    end
    if not textLabel then
        if not self._didWarnMissingServerLuckyTipsText then
            warn("[ShopController] SeverLuckyBuyTips exists but is missing a TextLabel.")
            self._didWarnMissingServerLuckyTipsText = true
        end
        return false
    end

    self._didWarnMissingServerLuckyTips = false
    self._didWarnMissingServerLuckyTipsText = false
    self._serverLuckyTipsRoot = tipsRoot
    self._serverLuckyTipsTextLabel = textLabel
    self._serverLuckyTipsBasePosition = textLabel.Position
    self._serverLuckyTipsTransparencyTargets = collectTransparencyTargets(textLabel)
    self:_setServerLuckyTipsVisible(false)
    return true
end

function ShopController:_showNextServerLuckyTip()
    if self._isShowingServerLuckyTip then
        return
    end

    if #self._serverLuckyTipQueue <= 0 then
        self:_setServerLuckyTipsVisible(false)
        return
    end

    self._isShowingServerLuckyTip = true
    local message = table.remove(self._serverLuckyTipQueue, 1)
    if not self:_ensureServerLuckyTipsNodes() then
        self._isShowingServerLuckyTip = false
        table.insert(self._serverLuckyTipQueue, 1, message)
        task.delay(1, function()
            if not self._isShowingServerLuckyTip and #self._serverLuckyTipQueue > 0 then
                self:_showNextServerLuckyTip()
            end
        end)
        return
    end

    local label = self._serverLuckyTipsTextLabel
    local basePosition = self._serverLuckyTipsBasePosition
    if not (label and basePosition) then
        self._isShowingServerLuckyTip = false
        self:_setServerLuckyTipsVisible(false)
        return
    end

    self:_setServerLuckyTipsVisible(true)
    label.Text = tostring(message or "")
    label.Position = offsetY(basePosition, getServerLuckyTipEnterOffsetY())
    self:_setServerLuckyTipsAppearance(1)

    local enterTween = TweenService:Create(label, TweenInfo.new(
        getServerLuckyTipFadeInSeconds(),
        Enum.EasingStyle.Back,
        Enum.EasingDirection.Out
    ), {
        Position = basePosition,
    })

    enterTween.Completed:Connect(function()
        task.delay(getServerLuckyTipDisplaySeconds(), function()
            if not (label and label.Parent) then
                self._isShowingServerLuckyTip = false
                self:_showNextServerLuckyTip()
                return
            end

            local fadePositionTween = TweenService:Create(label, TweenInfo.new(
                getServerLuckyTipFadeOutSeconds(),
                Enum.EasingStyle.Quad,
                Enum.EasingDirection.Out
            ), {
                Position = offsetY(basePosition, getServerLuckyTipFadeOffsetY()),
            })
            local fadeAlphaTween = tweenTransparencyAlpha(
                self._serverLuckyTipsTransparencyTargets,
                getServerLuckyTipFadeOutSeconds(),
                Enum.EasingStyle.Quad,
                Enum.EasingDirection.Out,
                1,
                0
            )

            fadeAlphaTween.Completed:Connect(function()
                if label and label.Parent then
                    label.Position = basePosition
                    self:_setServerLuckyTipsAppearance(1)
                end

                self._isShowingServerLuckyTip = false
                if #self._serverLuckyTipQueue <= 0 then
                    self:_setServerLuckyTipsVisible(false)
                end
                self:_showNextServerLuckyTip()
            end)

            fadePositionTween:Play()
            fadeAlphaTween:Play()
        end)
    end)

    enterTween:Play()
end

function ShopController:_enqueueServerLuckyTip(message)
    local normalizedMessage = tostring(message or "")
    if normalizedMessage == "" then
        return
    end

    table.insert(self._serverLuckyTipQueue, normalizedMessage)
    self:_showNextServerLuckyTip()
end

function ShopController:_handleServerLuckyTipSerialChanged()
    local currentSerial = math.max(0, math.floor(tonumber(
        ReplicatedStorage:GetAttribute(getServerLuckyPurchaseSerialAttributeName())
    ) or 0))
    if currentSerial <= self._lastServerLuckyTipSerialSeen then
        return
    end

    self._lastServerLuckyTipSerialSeen = currentSerial
    local buyerName = tostring(ReplicatedStorage:GetAttribute(getServerLuckyLastBuyerNameAttributeName()) or "")
    if buyerName == "" then
        return
    end

    self:_enqueueServerLuckyTip(string.format(getServerLuckyTipTemplate(), buyerName))
end

function ShopController:_setPurchaseTipsVisible(visible)
    setGuiVisibility(self._purchaseTipsRoot, visible == true)
end

function ShopController:_setPurchaseTipsAppearance(alpha)
    applyTransparencyAlpha(self._purchaseTipsTransparencyTargets, alpha)
end

function ShopController:_ensurePurchaseTipsNodes()
    if self._purchaseTipsRoot
        and self._purchaseTipsRoot.Parent
        and self._purchaseTipsTextLabel
        and self._purchaseTipsTextLabel.Parent
    then
        return true
    end

    local playerGui = self:_getPlayerGui()
    if not playerGui then
        if not self._didWarnMissingPurchaseTips then
            warn("[ShopController] PlayerGui is missing; PurchaseSuccessfulTips is unavailable.")
            self._didWarnMissingPurchaseTips = true
        end
        return false
    end

    local mainGui = self:_getMainGui()
    local tipsRoot = nil
    if mainGui then
        tipsRoot = self:_findDirectChildByName(mainGui, "PurchaseSuccessfulTips")
            or self:_findDescendantByNames(mainGui, { "PurchaseSuccessfulTips" })
    end
    if not tipsRoot then
        tipsRoot = playerGui:FindFirstChild("PurchaseSuccessfulTips")
            or playerGui:FindFirstChild("PurchaseSuccessfulTips", true)
    end

    if not tipsRoot then
        if not self._didWarnMissingPurchaseTips then
            warn("[ShopController] PurchaseSuccessfulTips UI is missing.")
            self._didWarnMissingPurchaseTips = true
        end
        return false
    end

    local textLabel = tipsRoot:FindFirstChild("Text", true)
    if not (textLabel and textLabel:IsA("TextLabel")) then
        textLabel = tipsRoot:FindFirstChildWhichIsA("TextLabel", true)
    end
    if not textLabel then
        if not self._didWarnMissingPurchaseTipsText then
            warn("[ShopController] PurchaseSuccessfulTips exists but is missing a TextLabel.")
            self._didWarnMissingPurchaseTipsText = true
        end
        return false
    end

    self._didWarnMissingPurchaseTips = false
    self._didWarnMissingPurchaseTipsText = false
    self._purchaseTipsRoot = tipsRoot
    self._purchaseTipsTextLabel = textLabel
    self._purchaseTipsBasePosition = textLabel.Position
    self._purchaseTipsTransparencyTargets = collectTransparencyTargets(textLabel)
    self:_setPurchaseTipsVisible(false)
    return true
end

function ShopController:_showNextPurchaseTip()
    if self._isShowingPurchaseTip then
        return
    end

    if #self._purchaseTipQueue <= 0 then
        self:_setPurchaseTipsVisible(false)
        return
    end

    self._isShowingPurchaseTip = true
    local message = table.remove(self._purchaseTipQueue, 1)
    if not self:_ensurePurchaseTipsNodes() then
        self._isShowingPurchaseTip = false
        table.insert(self._purchaseTipQueue, 1, message)
        task.delay(1, function()
            if not self._isShowingPurchaseTip and #self._purchaseTipQueue > 0 then
                self:_showNextPurchaseTip()
            end
        end)
        return
    end

    local label = self._purchaseTipsTextLabel
    local basePosition = self._purchaseTipsBasePosition
    if not (label and basePosition) then
        self._isShowingPurchaseTip = false
        self:_setPurchaseTipsVisible(false)
        return
    end

    self:_setPurchaseTipsVisible(true)
    label.Text = tostring(message or getPurchaseSuccessTipText())
    label.Position = offsetY(basePosition, getPurchaseSuccessTipEnterOffsetY())
    self:_setPurchaseTipsAppearance(1)

    local enterTween = TweenService:Create(label, TweenInfo.new(
        getPurchaseSuccessTipFadeInSeconds(),
        Enum.EasingStyle.Back,
        Enum.EasingDirection.Out
    ), {
        Position = basePosition,
    })

    enterTween.Completed:Connect(function()
        task.delay(getPurchaseSuccessTipDisplaySeconds(), function()
            if not (label and label.Parent) then
                self._isShowingPurchaseTip = false
                self:_showNextPurchaseTip()
                return
            end

            local fadePositionTween = TweenService:Create(label, TweenInfo.new(
                getPurchaseSuccessTipFadeOutSeconds(),
                Enum.EasingStyle.Quad,
                Enum.EasingDirection.Out
            ), {
                Position = offsetY(basePosition, getPurchaseSuccessTipFadeOffsetY()),
            })
            local fadeAlphaTween = tweenTransparencyAlpha(
                self._purchaseTipsTransparencyTargets,
                getPurchaseSuccessTipFadeOutSeconds(),
                Enum.EasingStyle.Quad,
                Enum.EasingDirection.Out,
                1,
                0
            )

            fadeAlphaTween.Completed:Connect(function()
                if label and label.Parent then
                    label.Position = basePosition
                    self:_setPurchaseTipsAppearance(1)
                end

                self._isShowingPurchaseTip = false
                if #self._purchaseTipQueue <= 0 then
                    self:_setPurchaseTipsVisible(false)
                end
                self:_showNextPurchaseTip()
            end)

            fadePositionTween:Play()
            fadeAlphaTween:Play()
        end)
    end)

    enterTween:Play()
end

function ShopController:_enqueuePurchaseTip(message)
    local normalizedMessage = tostring(message or "")
    if normalizedMessage == "" then
        normalizedMessage = getPurchaseSuccessTipText()
    end

    self:_playPurchaseSuccessSound()
    table.insert(self._purchaseTipQueue, normalizedMessage)
    self:_showNextPurchaseTip()
end

function ShopController:_isShopProductId(productId)
    local normalizedProductId = math.max(0, math.floor(tonumber(productId) or 0))
    if normalizedProductId <= 0 then
        return false
    end

    if normalizedProductId == getServerLuckyProductId() then
        return true
    end

    for _, offer in pairs(getNormalizedCashOffersByNodeName()) do
        if offer and normalizedProductId == math.max(0, math.floor(tonumber(offer.ProductId) or 0)) then
            return true
        end
    end

    for _, offer in pairs(getNormalizedLuckyBlockBundleOffersByButtonName()) do
        if offer and normalizedProductId == math.max(0, math.floor(tonumber(offer.ProductId) or 0)) then
            return true
        end
    end

    return false
end

function ShopController:_isShopGamePassId(gamePassId)
    local normalizedGamePassId = math.max(0, math.floor(tonumber(gamePassId) or 0))
    if normalizedGamePassId <= 0 then
        return false
    end

    if normalizedGamePassId == getVipGamePassId() then
        return true
    end

    if normalizedGamePassId == getStarterPackGamePassId() then
        return true
    end

    local extraGamePassIds = getShopConfig().PurchaseSuccessTipGamePassIds
    if type(extraGamePassIds) == "table" then
        for _, rawId in ipairs(extraGamePassIds) do
            if normalizedGamePassId == math.max(0, math.floor(tonumber(rawId) or 0)) then
                return true
            end
        end
    end

    return false
end

function ShopController:_renderServerLuckyCountdown()
    local remainingSeconds = self:_getServerLuckyRemainingSeconds()
    local isActive = remainingSeconds > 0
    local countdownText = formatServerLuckyCountdownText(remainingSeconds)

    for _, refs in ipairs(self._serverLuckyRefs or {}) do
        local label = refs.lastTimeLabel
        if label and label:IsA("TextLabel") then
            label.Visible = isActive
            if isActive then
                label.Text = countdownText
            end
        end
    end
end

function ShopController:_applyVipAttributeState()
    local isVipOwned = localPlayer:GetAttribute(getVipOwnedAttributeName()) == true
    self._isVipOwned = isVipOwned
    if isVipOwned then
        self._activeVipGamePassId = 0
        self._isVipPrompting = false
        self:_stopVipPolling()
    end
end

function ShopController:_renderPurchaseState()
    self:_applyVipAttributeState()

    local starterPackState = self._starterPackState or {}
    local starterPackGamePassId = math.max(0, math.floor(tonumber(starterPackState.gamePassId) or getStarterPackGamePassId()))
    local shouldShowStarterPackEntry = starterPackState.showEntry == true
    local isStarterPackOwned = starterPackState.isOwned == true

    if self._starterPackRoot and self._starterPackRoot:IsA("GuiObject") then
        self._starterPackRoot.Visible = shouldShowStarterPackEntry
    end

    if self._starterPackBuyButton and self._starterPackBuyButton:IsA("GuiButton") then
        local canPromptStarterPack = shouldShowStarterPackEntry
            and not isStarterPackOwned
            and starterPackGamePassId > 0
            and self._isStarterPackPrompting ~= true
        self._starterPackBuyButton.Active = canPromptStarterPack
        self._starterPackBuyButton.AutoButtonColor = canPromptStarterPack
    end

    if self._starterPackPriceIcon and self._starterPackPriceIcon:IsA("GuiObject") then
        self._starterPackPriceIcon.Visible = shouldShowStarterPackEntry and not isStarterPackOwned
    end

    local vipGamePassId = getVipGamePassId()
    local vipPriceRobux = getVipPriceRobux()
    local serverLuckyProductId = getServerLuckyProductId()
    local serverLuckyPriceRobux = getServerLuckyPriceRobux()
    if self._vipPriceLabel and self._vipPriceLabel:IsA("TextLabel") then
        if self._isVipOwned then
            self._vipPriceLabel.Text = getVipOwnedText()
        elseif self._isVipPrompting then
            self._vipPriceLabel.Text = getVipPromptingText()
        else
            self._vipPriceLabel.Text = tostring(vipPriceRobux)
        end
    end

    if self._vipPriceIcon and self._vipPriceIcon:IsA("GuiObject") then
        self._vipPriceIcon.Visible = not self._isVipOwned and vipPriceRobux > 0
    end

    if self._vipOwnedLabel and self._vipOwnedLabel:IsA("GuiObject") then
        self._vipOwnedLabel.Visible = self._isVipOwned
    end

    if self._vipBuyButton and self._vipBuyButton:IsA("GuiButton") then
        self._vipBuyButton.Visible = not self._isVipOwned
        local isActive = vipGamePassId > 0 and not self._isVipOwned and not self._isVipPrompting
        self._vipBuyButton.Active = isActive
        self._vipBuyButton.AutoButtonColor = isActive
    end

    for _, refs in ipairs(self._serverLuckyRefs or {}) do
        if refs.priceLabel and refs.priceLabel:IsA("TextLabel") then
            refs.priceLabel.Text = tostring(serverLuckyPriceRobux)
        end

        if refs.priceIcon and refs.priceIcon:IsA("GuiObject") then
            refs.priceIcon.Visible = serverLuckyProductId > 0 and serverLuckyPriceRobux > 0
        end

        if refs.buyButton and refs.buyButton:IsA("GuiButton") then
            local isEnabled = serverLuckyProductId > 0
            refs.buyButton.Active = isEnabled
            refs.buyButton.AutoButtonColor = isEnabled
        end
    end

    local cashOffersByNodeName = getNormalizedCashOffersByNodeName()
    for nodeName, refs in pairs(self._cashOfferRefsByNodeName or {}) do
        local offer = cashOffersByNodeName[nodeName]
        local isEnabled = offer ~= nil and offer.ProductId > 0

        if refs.priceLabel and refs.priceLabel:IsA("TextLabel") and offer then
            refs.priceLabel.Text = tostring(offer.PriceRobux)
        end

        if refs.priceIcon and refs.priceIcon:IsA("GuiObject") then
            refs.priceIcon.Visible = isEnabled
        end

        if refs.purchasedLabel and refs.purchasedLabel:IsA("GuiObject") then
            refs.purchasedLabel.Visible = false
        end

        if refs.buyButton and refs.buyButton:IsA("GuiButton") then
            refs.buyButton.Active = isEnabled
            refs.buyButton.AutoButtonColor = isEnabled
        end
    end

    local luckyBlockOffersByButtonName = getNormalizedLuckyBlockBundleOffersByButtonName()
    for buttonName, refs in pairs(self._luckyBlockBundleOfferRefsByButtonName or {}) do
        local offer = luckyBlockOffersByButtonName[buttonName]
        local isEnabled = offer ~= nil
            and offer.ProductId > 0
            and offer.BlockId > 0
            and offer.Quantity > 0

        if refs.priceLabel and refs.priceLabel:IsA("TextLabel") and offer and offer.PriceRobux ~= nil then
            refs.priceLabel.Text = tostring(offer.PriceRobux)
        end

        if refs.priceIcon and refs.priceIcon:IsA("GuiObject") and offer and offer.PriceRobux ~= nil then
            refs.priceIcon.Visible = offer.PriceRobux > 0
        end

        if refs.buyButton and refs.buyButton:IsA("GuiButton") then
            refs.buyButton.Active = isEnabled
            refs.buyButton.AutoButtonColor = isEnabled
        end
    end

    self:_renderServerLuckyCountdown()
end

function ShopController:_requestVipStateSync(reason, forceOwnershipRefresh)
    if self._requestShopStateSyncEvent and self._requestShopStateSyncEvent:IsA("RemoteEvent") then
        self._requestShopStateSyncEvent:FireServer({
            reason = tostring(reason or ""),
            forceOwnershipRefresh = forceOwnershipRefresh == true,
        })
    end
end

function ShopController:_requestStarterPackStateSync(reason, forceOwnershipRefresh, consumePendingSuccess)
    if self._requestStarterPackStateSyncEvent and self._requestStarterPackStateSyncEvent:IsA("RemoteEvent") then
        self._requestStarterPackStateSyncEvent:FireServer({
            reason = tostring(reason or ""),
            forceOwnershipRefresh = forceOwnershipRefresh == true,
            consumePendingSuccess = consumePendingSuccess == true,
        })
    end
end

function ShopController:_applyStarterPackState(payload)
    if type(payload) ~= "table" then
        return
    end

    local starterPackState = self._starterPackState or {}
    starterPackState.showEntry = payload.showEntry == true
    starterPackState.isOwned = payload.isOwned == true
    starterPackState.hasGranted = payload.hasGranted == true
    starterPackState.gamePassId = math.max(0, math.floor(tonumber(payload.gamePassId) or starterPackState.gamePassId or getStarterPackGamePassId()))
    self._starterPackState = starterPackState

    if starterPackState.showEntry ~= true then
        self._isStarterPackPrompting = false
        self._activeStarterPackGamePassId = 0
    end

    if starterPackState.hasGranted == true then
        self:_stopStarterPackPolling()
    end

    self:_renderPurchaseState()
end

function ShopController:_stopVipPolling()
    self._vipPollSerial = (tonumber(self._vipPollSerial) or 0) + 1
end

function ShopController:_stopStarterPackPolling()
    self._starterPackPollSerial = (tonumber(self._starterPackPollSerial) or 0) + 1
end

function ShopController:_startVipPolling()
    self:_stopVipPolling()

    local serial = self._vipPollSerial
    local remaining = getPurchaseSyncMaxAttempts()

    local function step()
        if serial ~= self._vipPollSerial or self._isVipOwned == true or remaining <= 0 then
            return
        end

        remaining -= 1
        self:_requestVipStateSync("PurchaseFinished", true)
        if remaining > 0 then
            task.delay(getPurchaseSyncRetrySeconds(), step)
        end
    end

    step()
end

function ShopController:_startStarterPackPolling()
    self:_stopStarterPackPolling()

    local serial = self._starterPackPollSerial
    local remaining = getPurchaseSyncMaxAttempts()

    local function step()
        local starterPackState = self._starterPackState or {}
        if serial ~= self._starterPackPollSerial or starterPackState.hasGranted == true or remaining <= 0 then
            return
        end

        remaining -= 1
        self:_requestStarterPackStateSync("ShopPurchaseFinished", true, false)
        if remaining > 0 then
            task.delay(getPurchaseSyncRetrySeconds(), step)
        end
    end

    step()
end

function ShopController:_promptVipPurchase()
    if self._isVipOwned or self._isVipPrompting then
        return
    end

    local gamePassId = getVipGamePassId()
    if gamePassId <= 0 then
        return
    end

    self._activeVipGamePassId = gamePassId
    self._isVipPrompting = true
    self:_renderPurchaseState()

    local ok, err = pcall(function()
        MarketplaceService:PromptGamePassPurchase(localPlayer, gamePassId)
    end)

    if not ok then
        warn(string.format(
            "[ShopController] Failed to prompt VIP game pass purchase gamePassId=%d err=%s",
            gamePassId,
            tostring(err)
        ))
        self._activeVipGamePassId = 0
        self._isVipPrompting = false
        self:_renderPurchaseState()
    end
end

function ShopController:_promptStarterPackPurchase()
    local starterPackState = self._starterPackState or {}
    local gamePassId = math.max(0, math.floor(tonumber(starterPackState.gamePassId) or getStarterPackGamePassId()))
    if gamePassId <= 0 then
        return
    end

    if starterPackState.showEntry ~= true or starterPackState.isOwned == true or self._isStarterPackPrompting == true then
        return
    end

    self._activeStarterPackGamePassId = gamePassId
    self._isStarterPackPrompting = true
    self:_renderPurchaseState()

    local ok, err = pcall(function()
        MarketplaceService:PromptGamePassPurchase(localPlayer, gamePassId)
    end)

    if not ok then
        warn(string.format(
            "[ShopController] Failed to prompt starter pack game pass purchase gamePassId=%d err=%s",
            gamePassId,
            tostring(err)
        ))
        self._activeStarterPackGamePassId = 0
        self._isStarterPackPrompting = false
        self:_renderPurchaseState()
    end
end

function ShopController:_promptServerLuckyPurchase()
    local productId = getServerLuckyProductId()
    if productId <= 0 then
        return
    end

    local ok, err = pcall(function()
        MarketplaceService:PromptProductPurchase(localPlayer, productId)
    end)

    if not ok then
        warn(string.format(
            "[ShopController] Failed to prompt server lucky purchase productId=%d err=%s",
            productId,
            tostring(err)
        ))
    end
end

function ShopController:_promptCashPurchase(nodeName)
    local cashOffer = getNormalizedCashOffersByNodeName()[tostring(nodeName or "")]
    if not cashOffer or cashOffer.ProductId <= 0 then
        return
    end

    local ok, err = pcall(function()
        MarketplaceService:PromptProductPurchase(localPlayer, cashOffer.ProductId)
    end)

    if not ok then
        warn(string.format(
            "[ShopController] Failed to prompt cash product purchase node=%s productId=%d err=%s",
            tostring(nodeName),
            cashOffer.ProductId,
            tostring(err)
        ))
    end
end

function ShopController:_promptLuckyBlockBundlePurchase(buttonName)
    local offer = getNormalizedLuckyBlockBundleOffersByButtonName()[tostring(buttonName or "")]
    if not offer or offer.ProductId <= 0 then
        return
    end

    local ok, err = pcall(function()
        MarketplaceService:PromptProductPurchase(localPlayer, offer.ProductId)
    end)

    if not ok then
        warn(string.format(
            "[ShopController] Failed to prompt lucky block bundle purchase button=%s productId=%d err=%s",
            tostring(buttonName),
            offer.ProductId,
            tostring(err)
        ))
    end
end

function ShopController:_cancelLuckyBlockBundleTweens()
    if self._luckyBlockIconTween then
        self._luckyBlockIconTween:Cancel()
        self._luckyBlockIconTween = nil
    end

    if self._luckyBlockLightTween then
        self._luckyBlockLightTween:Cancel()
        self._luckyBlockLightTween = nil
    end
end

function ShopController:_stopLuckyBlockBundleAnimations()
    self._luckyBlockAnimationSerial = (tonumber(self._luckyBlockAnimationSerial) or 0) + 1
    self:_cancelLuckyBlockBundleTweens()

    if self._luckyBlockIconNode
        and self._luckyBlockIconNode:IsA("GuiObject")
        and self._luckyBlockIconBasePosition
        and self._luckyBlockIconNode.Parent
    then
        self._luckyBlockIconNode.Position = self._luckyBlockIconBasePosition
    end

    if self._luckyBlockLightNode
        and self._luckyBlockLightNode:IsA("GuiObject")
        and self._luckyBlockLightNode.Parent
    then
        self._luckyBlockLightNode.Rotation = tonumber(self._luckyBlockLightBaseRotation) or 0
    end
end

function ShopController:_startLuckyBlockBundleAnimations()
    local iconNode = self._luckyBlockIconNode
    local lightNode = self._luckyBlockLightNode
    if not (
        iconNode
        and iconNode:IsA("GuiObject")
        and iconNode.Parent
        and lightNode
        and lightNode:IsA("GuiObject")
        and lightNode.Parent
    ) then
        return
    end

    if not self._luckyBlockIconBasePosition then
        self._luckyBlockIconBasePosition = iconNode.Position
    end
    self._luckyBlockLightBaseRotation = tonumber(lightNode.Rotation) or 0

    self:_stopLuckyBlockBundleAnimations()
    local serial = self._luckyBlockAnimationSerial
    local iconBasePosition = self._luckyBlockIconBasePosition
    local lightBaseRotation = tonumber(self._luckyBlockLightBaseRotation) or 0
    local floatOffset = getLuckyBlockIconFloatOffsetPx()
    local floatDuration = getLuckyBlockIconFloatDurationSeconds()
    local rotateDuration = getLuckyBlockLightRotateDurationSeconds()

    local loopIconDown
    local function loopIconUp()
        if serial ~= self._luckyBlockAnimationSerial or not isLiveInstance(iconNode) then
            return
        end

        local tween = TweenService:Create(iconNode, TweenInfo.new(
            floatDuration,
            Enum.EasingStyle.Sine,
            Enum.EasingDirection.InOut
        ), {
            Position = offsetY(iconBasePosition, -floatOffset),
        })
        self._luckyBlockIconTween = tween
        tween.Completed:Connect(function(playbackState)
            if self._luckyBlockIconTween == tween then
                self._luckyBlockIconTween = nil
            end

            if playbackState == Enum.PlaybackState.Completed then
                task.defer(loopIconDown)
            end
        end)
        tween:Play()
    end

    loopIconDown = function()
        if serial ~= self._luckyBlockAnimationSerial or not isLiveInstance(iconNode) then
            return
        end

        local tween = TweenService:Create(iconNode, TweenInfo.new(
            floatDuration,
            Enum.EasingStyle.Sine,
            Enum.EasingDirection.InOut
        ), {
            Position = iconBasePosition,
        })
        self._luckyBlockIconTween = tween
        tween.Completed:Connect(function(playbackState)
            if self._luckyBlockIconTween == tween then
                self._luckyBlockIconTween = nil
            end

            if playbackState == Enum.PlaybackState.Completed then
                task.defer(loopIconUp)
            end
        end)
        tween:Play()
    end

    local function loopLight()
        if serial ~= self._luckyBlockAnimationSerial or not isLiveInstance(lightNode) then
            return
        end

        lightNode.Rotation = lightBaseRotation
        local tween = TweenService:Create(lightNode, TweenInfo.new(
            rotateDuration,
            Enum.EasingStyle.Linear,
            Enum.EasingDirection.InOut
        ), {
            Rotation = lightBaseRotation + 360,
        })
        self._luckyBlockLightTween = tween
        tween.Completed:Connect(function(playbackState)
            if self._luckyBlockLightTween == tween then
                self._luckyBlockLightTween = nil
            end

            if playbackState == Enum.PlaybackState.Completed then
                task.defer(loopLight)
            end
        end)
        tween:Play()
    end

    iconNode.Position = iconBasePosition
    lightNode.Rotation = lightBaseRotation
    task.defer(loopIconUp)
    task.defer(loopLight)
end

function ShopController:_bindPurchaseButtons()
    local shopInfoRoot = self._shopRoot and (
        self:_findDirectChildByName(self._shopRoot, "Shopinfo")
        or self:_findDescendantByNames(self._shopRoot, { "Shopinfo" })
    ) or nil
    self._scrollingFrame = shopInfoRoot and self:_findDescendantByNames(shopInfoRoot, { "ScrollingFrame" }) or nil

    self._starterPackRoot = self._scrollingFrame and (
        self:_findDirectChildByName(self._scrollingFrame, "StarterPack")
        or self:_findDescendantByNames(self._scrollingFrame, { "StarterPack" })
    ) or nil
    self._starterPackBuyButton = self._starterPackRoot and self:_findDescendantByNames(self._starterPackRoot, { "BuyButton" }) or nil
    self._starterPackPriceLabel = self._starterPackBuyButton and self:_findDescendantByNames(self._starterPackBuyButton, { "RightPrice" }) or nil
    self._starterPackPriceIcon = self._starterPackBuyButton and self:_findDescendantByNames(self._starterPackBuyButton, { "Icon" }) or nil

    local starterPackInteractive = self:_resolveInteractiveNode(self._starterPackBuyButton)
    if starterPackInteractive then
        table.insert(self._uiConnections, starterPackInteractive.Activated:Connect(function()
            self:_promptStarterPackPurchase()
        end))
    elseif self:_shouldWarnBindingIssues() and self._starterPackRoot ~= nil then
        self:_warnOnce("MissingStarterPackButton", "[ShopController] Main/Shop/.../StarterPack/BuyButton is missing.")
    end

    local vipRoot = self._scrollingFrame and (
        self:_findDirectChildByName(self._scrollingFrame, "Vip")
        or self:_findDescendantByNames(self._scrollingFrame, { "Vip" })
    ) or nil
    self._vipRoot = vipRoot
    self._vipBuyButton = vipRoot and self:_findDescendantByNames(vipRoot, { "BuyButton" }) or nil
    self._vipPriceLabel = self._vipBuyButton and self:_findDescendantByNames(self._vipBuyButton, { "RightPrice" }) or nil
    self._vipPriceIcon = self._vipBuyButton and self:_findDescendantByNames(self._vipBuyButton, { "Icon" }) or nil
    self._vipOwnedLabel = vipRoot and self:_findDescendantByNames(vipRoot, { "Owned" }) or nil

    local vipInteractive = self:_resolveInteractiveNode(self._vipBuyButton)
    if vipInteractive then
        table.insert(self._uiConnections, vipInteractive.Activated:Connect(function()
            self:_promptVipPurchase()
        end))
    elseif self:_shouldWarnBindingIssues() then
        self:_warnOnce("MissingVipButton", "[ShopController] Main/Shop/.../Vip/BuyButton is missing.")
    end

    self._serverLuckyRefs = {}
    for _, nodeName in ipairs(getServerLuckyNodeNames()) do
        local luckyRoot = self._scrollingFrame and (
            self:_findDirectChildByName(self._scrollingFrame, nodeName)
            or self:_findDescendantByNames(self._scrollingFrame, { nodeName })
        ) or nil
        if luckyRoot then
            local buyButton = self:_findDescendantByNames(luckyRoot, { "BuyButton" })
            local priceLabel = buyButton and self:_findDescendantByNames(buyButton, { "RightPrice" }) or nil
            local priceIcon = buyButton and self:_findDescendantByNames(buyButton, { "Icon" }) or nil
            local lastTimeLabel = self:_findDescendantByNames(luckyRoot, { "LastTime" })
            local refs = {
                root = luckyRoot,
                buyButton = buyButton,
                priceLabel = priceLabel,
                priceIcon = priceIcon,
                lastTimeLabel = lastTimeLabel,
            }
            table.insert(self._serverLuckyRefs, refs)

            local interactive = self:_resolveInteractiveNode(buyButton)
            if interactive then
                table.insert(self._uiConnections, interactive.Activated:Connect(function()
                    self:_promptServerLuckyPurchase()
                end))
            end
        elseif self:_shouldWarnBindingIssues() and nodeName == "Lukcy" then
            self:_warnOnce("MissingServerLuckyOffer", "[ShopController] Main/Shop/.../Lukcy is missing.")
        end
    end

    local cashContent = self:_findByPath(self._scrollingFrame, { "Cash", "Content" })
    if not cashContent then
        cashContent = self._scrollingFrame and self:_findDescendantByNames(self._scrollingFrame, { "Content" }) or nil
    end

    local cashOffersByNodeName = getNormalizedCashOffersByNodeName()
    for nodeName, offer in pairs(cashOffersByNodeName) do
        local root = cashContent and (
            self:_findDirectChildByName(cashContent, nodeName)
            or self:_findDescendantByNames(cashContent, { nodeName })
        ) or nil
        if root then
            local buyButton = self:_findDescendantByNames(root, { "BuyButton" })
            local priceLabel = buyButton and self:_findDescendantByNames(buyButton, { "RightPrice" }) or nil
            local priceIcon = buyButton and self:_findDescendantByNames(buyButton, { "Icon" }) or nil
            local purchasedLabel = self:_findDescendantByNames(root, { "Purchased" })

            self._cashOfferRefsByNodeName[nodeName] = {
                root = root,
                buyButton = buyButton,
                priceLabel = priceLabel,
                priceIcon = priceIcon,
                purchasedLabel = purchasedLabel,
            }

            local interactive = self:_resolveInteractiveNode(buyButton)
            if interactive then
                table.insert(self._uiConnections, interactive.Activated:Connect(function()
                    self:_promptCashPurchase(offer.NodeName)
                end))
            end
        elseif self:_shouldWarnBindingIssues() then
            self:_warnOnce("MissingCashOffer:" .. nodeName, string.format(
                "[ShopController] Main/Shop/.../Cash/Content/%s is missing.",
                nodeName
            ))
        end
    end

    self._luckyBlockBundleRoot = self._scrollingFrame and (
        self:_findDirectChildByName(self._scrollingFrame, getLuckyBlockBundleNodeName())
        or self:_findDescendantByNames(self._scrollingFrame, { getLuckyBlockBundleNodeName() })
    ) or nil
    self._luckyBlockBundleOfferRefsByButtonName = {}
    self._luckyBlockIconNode = self._luckyBlockBundleRoot and self:_findDescendantByNames(self._luckyBlockBundleRoot, { "LuckyBlockIcon" }) or nil
    self._luckyBlockLightNode = self._luckyBlockBundleRoot and self:_findDescendantByNames(self._luckyBlockBundleRoot, { "Light" }) or nil
    self._luckyBlockIconBasePosition = self._luckyBlockIconNode and self._luckyBlockIconNode:IsA("GuiObject")
        and self._luckyBlockIconNode.Position
        or nil
    self._luckyBlockLightBaseRotation = self._luckyBlockLightNode and self._luckyBlockLightNode:IsA("GuiObject")
        and (tonumber(self._luckyBlockLightNode.Rotation) or 0)
        or 0

    local luckyBlockOffersByButtonName = getNormalizedLuckyBlockBundleOffersByButtonName()
    for buttonName, offer in pairs(luckyBlockOffersByButtonName) do
        local buyButton = self._luckyBlockBundleRoot and self:_findDescendantByNames(self._luckyBlockBundleRoot, { buttonName }) or nil
        if buyButton then
            local priceLabel = self:_findDescendantByNames(buyButton, { "RightPrice" })
            local priceIcon = self:_findDescendantByNames(buyButton, { "Icon" })
            self._luckyBlockBundleOfferRefsByButtonName[buttonName] = {
                buyButton = buyButton,
                priceLabel = priceLabel,
                priceIcon = priceIcon,
            }

            local interactive = self:_resolveInteractiveNode(buyButton)
            if interactive then
                table.insert(self._uiConnections, interactive.Activated:Connect(function()
                    self:_promptLuckyBlockBundlePurchase(offer.ButtonName)
                end))
            end
        elseif self:_shouldWarnBindingIssues() then
            self:_warnOnce("MissingLuckyBlockBundleOffer:" .. buttonName, string.format(
                "[ShopController] Main/Shop/.../%s/%s is missing.",
                getLuckyBlockBundleNodeName(),
                buttonName
            ))
        end
    end

    if self._luckyBlockBundleRoot == nil and self:_shouldWarnBindingIssues() then
        self:_warnOnce("MissingLuckyBlockBundleRoot", string.format(
            "[ShopController] Main/Shop/.../%s is missing.",
            getLuckyBlockBundleNodeName()
        ))
    end
end

function ShopController:_installVipChatStyling()
    if self._didInstallChatStyling then
        return
    end

    self._didInstallChatStyling = true

    if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
        return
    end

    local vipTagColor = tostring(getShopConfig().VipTagColor or "#FFC93C")

    TextChatService.OnIncomingMessage = function(message)
        local textSource = message and message.TextSource or nil
        if not textSource then
            return nil
        end

        local speakerPlayer = Players:GetPlayerByUserId(textSource.UserId)
        if not speakerPlayer or speakerPlayer:GetAttribute(getVipOwnedAttributeName()) ~= true then
            return nil
        end

        local existingPrefix = tostring(message.PrefixText or "")
        if string.find(existingPrefix, "[VIP]", 1, true) then
            return nil
        end

        local targetProperties = Instance.new("TextChatMessageProperties")
        local vipPrefix = '<font color="' .. vipTagColor .. '">[VIP]</font>'
        if existingPrefix ~= "" then
            targetProperties.PrefixText = string.format("%s %s", vipPrefix, existingPrefix)
        else
            targetProperties.PrefixText = vipPrefix
        end

        return targetProperties
    end
end

function ShopController:_bindMainUi()
    local mainGui = self:_getMainGui()
    if not mainGui then
        if self:_shouldWarnBindingIssues() then
            self:_warnOnce("MissingMain", "[ShopController] Main UI is missing, shop panel is unavailable.")
        end
        self:_clearUiBindings()
        return false
    end

    self._mainGui = mainGui
    self._leftRoot = self:_findDirectChildByName(mainGui, "Left")
    self._leftShopRoot = self._leftRoot and self:_findDescendantByNames(self._leftRoot, { "Shop" }) or nil
    self._openButton = self._leftShopRoot and self:_resolveInteractiveNode(
        self:_findDescendantByNames(self._leftShopRoot, { "TextButton", "Button" }) or self._leftShopRoot
    ) or nil
    self._shopRoot = self:_findDirectChildByName(mainGui, "Shop")

    if not self._shopRoot then
        if self:_shouldWarnBindingIssues() then
            self:_warnOnce("MissingShopRoot", "[ShopController] Main/Shop is missing, shop panel did not bind.")
        end
        self:_clearUiBindings()
        return false
    end

    local titleRoot = self:_findDirectChildByName(self._shopRoot, "Title")
    self._closeButton = titleRoot and self:_findDescendantByNames(titleRoot, { "CloseButton" }) or nil

    self:_clearUiBindings()

    if self._openButton then
        self._openButton:SetAttribute("DisableUiClickSound", true)
        table.insert(self._uiConnections, self._openButton.Activated:Connect(function()
            self:OpenShop()
        end))
    elseif self:_shouldWarnBindingIssues() then
        self:_warnOnce("MissingOpenButton", "[ShopController] Main/Left/Shop/TextButton is missing.")
    end

    local closeInteractive = self:_resolveInteractiveNode(self._closeButton)
    if closeInteractive then
        table.insert(self._uiConnections, closeInteractive.Activated:Connect(function()
            self:CloseShop()
        end))
        self:_bindButtonFx(closeInteractive, {
            ScaleTarget = self._closeButton,
            RotationTarget = self._closeButton,
            HoverScale = 1.12,
            PressScale = 0.92,
            HoverRotation = 20,
            DisableClickSound = true,
        }, self._uiConnections)
    elseif self:_shouldWarnBindingIssues() then
        self:_warnOnce("MissingCloseButton", "[ShopController] Main/Shop/Title/CloseButton is missing.")
    end

    for _, button in ipairs(self:_collectActionButtons(closeInteractive)) do
        self:_bindButtonFx(button, {
            ScaleTarget = button,
            HoverScale = 1.05,
            PressScale = 0.94,
        }, self._uiConnections)
    end

    self:_bindPurchaseButtons()
    self:_renderPurchaseState()

    if self:_isShopModalOpen() then
        self:_startLuckyBlockBundleAnimations()
    end

    if self._shopRoot:IsA("GuiObject") and not self:_isShopModalOpen() then
        self._shopRoot.Visible = false
    end

    return true
end

function ShopController:_queueRebind()
    if self._rebindQueued then
        return
    end

    self._rebindQueued = true
    task.defer(function()
        self._rebindQueued = false
        self:_bindMainUi()
    end)
end

function ShopController:_scheduleRetryBind()
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

function ShopController:OpenShop()
    if not isLiveInstance(self._shopRoot) and not self:_bindMainUi() then
        return
    end

    self:_requestStarterPackStateSync("OpenShop", false, false)
    self:_renderPurchaseState()
    if self._scrollingFrame and self._scrollingFrame:IsA("ScrollingFrame") then
        self._scrollingFrame.CanvasPosition = Vector2.new(0, 0)
    end

    local didOpenShop = false

    if self._modalController then
        if not self:_isShopModalOpen() then
            self._modalController:OpenModal(getShopModalKey(), self._shopRoot, {
                HiddenNodes = self:_getHiddenNodesForModal(),
            })
            didOpenShop = true
        end
    elseif self._shopRoot and self._shopRoot:IsA("GuiObject") then
        didOpenShop = self._shopRoot.Visible ~= true
        self._shopRoot.Visible = true
    end

    if didOpenShop then
        self:_playShopOpenExtraSound()
    end

    self:_startLuckyBlockBundleAnimations()
end

function ShopController:CloseShop(immediate)
    if not isLiveInstance(self._shopRoot) then
        return
    end

    self:_stopLuckyBlockBundleAnimations()

    if self._modalController then
        self._modalController:CloseModal(getShopModalKey(), {
            Immediate = immediate == true,
        })
    elseif self._shopRoot and self._shopRoot:IsA("GuiObject") then
        self._shopRoot.Visible = false
    end
end

function ShopController:Start()
    if self._started then
        return
    end

    self._started = true
    self._startupWarnAt = os.clock() + STARTUP_WARNING_GRACE_SECONDS
    self:_installVipChatStyling()
    self:_applyVipAttributeState()
    self:_ensureServerLuckyTipsNodes()
    self:_ensurePurchaseTipsNodes()
    self._lastServerLuckyTipSerialSeen = math.max(0, math.floor(tonumber(
        ReplicatedStorage:GetAttribute(getServerLuckyPurchaseSerialAttributeName())
    ) or 0))

    local eventsRoot = ReplicatedStorage:WaitForChild(RemoteNames.RootFolder)
    local systemEvents = eventsRoot:WaitForChild(RemoteNames.SystemEventsFolder)
    self._requestShopStateSyncEvent = systemEvents:FindFirstChild(RemoteNames.System.RequestShopStateSync)
        or systemEvents:WaitForChild(RemoteNames.System.RequestShopStateSync, 10)
    self._starterPackStateSyncEvent = systemEvents:FindFirstChild(RemoteNames.System.StarterPackStateSync)
        or systemEvents:WaitForChild(RemoteNames.System.StarterPackStateSync, 10)
    self._requestStarterPackStateSyncEvent = systemEvents:FindFirstChild(RemoteNames.System.RequestStarterPackStateSync)
        or systemEvents:WaitForChild(RemoteNames.System.RequestStarterPackStateSync, 10)

    if self._starterPackStateSyncEvent and self._starterPackStateSyncEvent:IsA("RemoteEvent") then
        table.insert(self._persistentConnections, self._starterPackStateSyncEvent.OnClientEvent:Connect(function(payload)
            self:_applyStarterPackState(payload)
        end))
    end

    table.insert(self._persistentConnections, localPlayer:GetAttributeChangedSignal(getVipOwnedAttributeName()):Connect(function()
        self:_applyVipAttributeState()
        self:_renderPurchaseState()
    end))

    table.insert(self._persistentConnections, ReplicatedStorage:GetAttributeChangedSignal(
        getServerLuckyExpireAtAttributeName()
    ):Connect(function()
        self:_renderServerLuckyCountdown()
    end))

    table.insert(self._persistentConnections, ReplicatedStorage:GetAttributeChangedSignal(
        getServerLuckyPurchaseSerialAttributeName()
    ):Connect(function()
        self:_handleServerLuckyTipSerialChanged()
        self:_renderServerLuckyCountdown()
    end))

    table.insert(self._persistentConnections, MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
        if player ~= localPlayer then
            return
        end

        local parsedId = math.max(0, math.floor(tonumber(gamePassId) or 0))
        local wasStarterPackPromptedByShop = self._activeStarterPackGamePassId > 0 and parsedId == self._activeStarterPackGamePassId
        if self._activeStarterPackGamePassId > 0 and parsedId == self._activeStarterPackGamePassId then
            self._activeStarterPackGamePassId = 0
            self._isStarterPackPrompting = false
            self:_renderPurchaseState()
        end

        if parsedId == getStarterPackGamePassId() then
            if wasPurchased == true then
                if wasStarterPackPromptedByShop then
                    self:_playPurchaseSuccessSound()
                end
                self:_startStarterPackPolling()
            else
                self:_requestStarterPackStateSync("ShopPromptClosed", false, false)
            end
        end

        if wasPurchased == true
            and parsedId ~= getStarterPackGamePassId()
            and self:_isShopGamePassId(parsedId)
        then
            self:_enqueuePurchaseTip(getPurchaseSuccessTipText())
        end

        if self._activeVipGamePassId <= 0 or parsedId ~= self._activeVipGamePassId then
            return
        end

        self._activeVipGamePassId = 0
        self._isVipPrompting = false
        self:_renderPurchaseState()

        if wasPurchased == true then
            self:_startVipPolling()
        else
            self:_requestVipStateSync("PromptClosed", false)
        end
    end))

    table.insert(self._persistentConnections, MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, isPurchased)
        if userId ~= localPlayer.UserId or isPurchased ~= true then
            return
        end

        local parsedId = math.max(0, math.floor(tonumber(productId) or 0))
        if parsedId <= 0 or not self:_isShopProductId(parsedId) then
            return
        end

        self:_enqueuePurchaseTip(getPurchaseSuccessTipText())
    end))

    local playerGui = self:_getPlayerGui()
    if playerGui then
        table.insert(self._persistentConnections, playerGui.DescendantAdded:Connect(function(descendant)
            local watchedNames = {
                Main = true,
                Left = true,
                Shop = true,
                Title = true,
                CloseButton = true,
                TextButton = true,
                Button = true,
                BuyButton = true,
                ScrollingFrame = true,
                Vip = true,
                Lukcy = true,
                LukcyBlock = true,
                Cash = true,
                Content = true,
                Cash1 = true,
                Cash2 = true,
                Cash3 = true,
                StarterPack = true,
                BuyButton1 = true,
                BuyButton2 = true,
                BuyButton3 = true,
                LuckyBlockIcon = true,
                Light = true,
                SeverLuckyBuyTips = true,
                PurchaseSuccessfulTips = true,
            }
            if watchedNames[descendant.Name] then
                self:_queueRebind()
                if descendant.Name == "SeverLuckyBuyTips" then
                    self:_ensureServerLuckyTipsNodes()
                elseif descendant.Name == "PurchaseSuccessfulTips" then
                    self:_ensurePurchaseTipsNodes()
                end
            end
        end))
    end

    table.insert(self._persistentConnections, localPlayer.CharacterAdded:Connect(function()
        task.defer(function()
            self:_queueRebind()
        end)
    end))

    task.spawn(function()
        while self._started do
            self:_renderServerLuckyCountdown()
            task.wait(getServerLuckyCountdownUpdateInterval())
        end
    end)

    self:_scheduleRetryBind()
    self:_requestVipStateSync("Startup", true)
    self:_requestStarterPackStateSync("Startup", false, false)
end

return ShopController
