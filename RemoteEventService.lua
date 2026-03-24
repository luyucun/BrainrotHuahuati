--[[
脚本名字: RemoteEventService
脚本文件: RemoteEventService.lua
脚本类型: ModuleScript
Studio放置路径: ServerScriptService/Services/RemoteEventService
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
        "[RemoteEventService] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local RemoteNames = requireSharedModule("RemoteNames")

local RemoteEventService = {}
RemoteEventService._events = {}

local function findOrCreateFolder(parent, folderName)
    local folder = parent:FindFirstChild(folderName)
    if folder and folder:IsA("Folder") then
        return folder
    end

    folder = Instance.new("Folder")
    folder.Name = folderName
    folder.Parent = parent
    return folder
end

local function findOrCreateRemoteEvent(parent, eventName)
    local event = parent:FindFirstChild(eventName)
    if event and event:IsA("RemoteEvent") then
        return event
    end

    event = Instance.new("RemoteEvent")
    event.Name = eventName
    event.Parent = parent
    return event
end

function RemoteEventService:Init()
    local rootFolder = findOrCreateFolder(ReplicatedStorage, RemoteNames.RootFolder)
    local currencyEvents = findOrCreateFolder(rootFolder, RemoteNames.CurrencyEventsFolder)
    local systemEvents = findOrCreateFolder(rootFolder, RemoteNames.SystemEventsFolder)
    local brainrotEvents = findOrCreateFolder(rootFolder, RemoteNames.BrainrotEventsFolder)

    self._events.CoinChanged = findOrCreateRemoteEvent(currencyEvents, RemoteNames.Currency.CoinChanged)
    self._events.RequestCoinSync = findOrCreateRemoteEvent(currencyEvents, RemoteNames.Currency.RequestCoinSync)
    self._events.HomeAssigned = findOrCreateRemoteEvent(systemEvents, RemoteNames.System.HomeAssigned)
    self._events.LikeTip = findOrCreateRemoteEvent(systemEvents, RemoteNames.System.LikeTip)
    self._events.SocialStateSync = findOrCreateRemoteEvent(systemEvents, RemoteNames.System.SocialStateSync)
    self._events.RequestSocialStateSync = findOrCreateRemoteEvent(systemEvents, RemoteNames.System.RequestSocialStateSync)
    self._events.FriendBonusSync = findOrCreateRemoteEvent(systemEvents, RemoteNames.System.FriendBonusSync)
    self._events.RequestFriendBonusSync = findOrCreateRemoteEvent(systemEvents, RemoteNames.System.RequestFriendBonusSync)
    self._events.RequestQuickTeleport = findOrCreateRemoteEvent(systemEvents, RemoteNames.System.RequestQuickTeleport)
    self._events.ClaimCashFeedback = findOrCreateRemoteEvent(systemEvents, RemoteNames.System.ClaimCashFeedback)
    self._events.RebirthStateSync = findOrCreateRemoteEvent(systemEvents, RemoteNames.System.RebirthStateSync)
    self._events.RequestRebirthStateSync = findOrCreateRemoteEvent(systemEvents, RemoteNames.System.RequestRebirthStateSync)
    self._events.RequestRebirth = findOrCreateRemoteEvent(systemEvents, RemoteNames.System.RequestRebirth)
    self._events.RebirthFeedback = findOrCreateRemoteEvent(systemEvents, RemoteNames.System.RebirthFeedback)
    self._events.RequestHomeExpansion = findOrCreateRemoteEvent(systemEvents, RemoteNames.System.RequestHomeExpansion)
    self._events.HomeExpansionFeedback = findOrCreateRemoteEvent(systemEvents, RemoteNames.System.HomeExpansionFeedback)
    self._events.SpecialEventStateSync = findOrCreateRemoteEvent(systemEvents, RemoteNames.System.SpecialEventStateSync)
    self._events.RequestSpecialEventStateSync = findOrCreateRemoteEvent(systemEvents, RemoteNames.System.RequestSpecialEventStateSync)
    self._events.LaunchPowerStateSync = findOrCreateRemoteEvent(systemEvents, RemoteNames.System.LaunchPowerStateSync)
    self._events.RequestLaunchPowerStateSync = findOrCreateRemoteEvent(systemEvents, RemoteNames.System.RequestLaunchPowerStateSync)
    self._events.RequestLaunchPowerUpgrade = findOrCreateRemoteEvent(systemEvents, RemoteNames.System.RequestLaunchPowerUpgrade)
    self._events.LaunchPowerFeedback = findOrCreateRemoteEvent(systemEvents, RemoteNames.System.LaunchPowerFeedback)
    self._events.StealTip = findOrCreateRemoteEvent(systemEvents, RemoteNames.System.StealTip)
    self._events.BrainrotStateSync = findOrCreateRemoteEvent(brainrotEvents, RemoteNames.Brainrot.BrainrotStateSync)
    self._events.RequestBrainrotStateSync = findOrCreateRemoteEvent(brainrotEvents, RemoteNames.Brainrot.RequestBrainrotStateSync)
    self._events.RequestBrainrotUpgrade = findOrCreateRemoteEvent(brainrotEvents, RemoteNames.Brainrot.RequestBrainrotUpgrade)
    self._events.BrainrotUpgradeFeedback = findOrCreateRemoteEvent(brainrotEvents, RemoteNames.Brainrot.BrainrotUpgradeFeedback)
    self._events.RequestBrainrotSell = findOrCreateRemoteEvent(brainrotEvents, RemoteNames.Brainrot.RequestBrainrotSell) -- V2.6
    self._events.BrainrotSellFeedback = findOrCreateRemoteEvent(brainrotEvents, RemoteNames.Brainrot.BrainrotSellFeedback) -- V2.6
    self._events.BrainrotGiftOffer = findOrCreateRemoteEvent(brainrotEvents, RemoteNames.Brainrot.BrainrotGiftOffer) -- V2.9
    self._events.RequestBrainrotGiftDecision = findOrCreateRemoteEvent(brainrotEvents, RemoteNames.Brainrot.RequestBrainrotGiftDecision) -- V2.9
    self._events.BrainrotGiftFeedback = findOrCreateRemoteEvent(brainrotEvents, RemoteNames.Brainrot.BrainrotGiftFeedback) -- V2.9
    self._events.RequestStudioBrainrotGrant = findOrCreateRemoteEvent(brainrotEvents, RemoteNames.Brainrot.RequestStudioBrainrotGrant) -- Studio Only
    self._events.StudioBrainrotGrantFeedback = findOrCreateRemoteEvent(brainrotEvents, RemoteNames.Brainrot.StudioBrainrotGrantFeedback) -- Studio Only
    self._events.PromptBrainrotStealPurchase = findOrCreateRemoteEvent(brainrotEvents, RemoteNames.Brainrot.PromptBrainrotStealPurchase) -- V3.1.2
    self._events.RequestBrainrotStealPurchaseClosed = findOrCreateRemoteEvent(brainrotEvents, RemoteNames.Brainrot.RequestBrainrotStealPurchaseClosed) -- V3.1.2
    self._events.BrainrotStealFeedback = findOrCreateRemoteEvent(brainrotEvents, RemoteNames.Brainrot.BrainrotStealFeedback) -- V3.1.2
end

function RemoteEventService:GetEvent(eventKey)
    return self._events[eventKey]
end

return RemoteEventService



