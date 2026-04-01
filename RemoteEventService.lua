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
RemoteEventService._eventDefinitions = {}

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

function RemoteEventService:_registerEvent(eventKey, parent, eventName)
    local normalizedName = tostring(eventName or "")
    if normalizedName == "" then
        return nil
    end

    self._eventDefinitions[eventKey] = {
        Parent = parent,
        EventName = normalizedName,
    }

    local event = findOrCreateRemoteEvent(parent, normalizedName)
    self._events[eventKey] = event
    return event
end

function RemoteEventService:_ensureEvent(eventKey)
    local cachedEvent = self._events[eventKey]
    if cachedEvent and cachedEvent.Parent then
        return cachedEvent
    end

    local definition = self._eventDefinitions[eventKey]
    if not definition then
        return nil
    end

    local parent = definition.Parent
    if not (parent and parent.Parent) then
        return nil
    end

    local event = findOrCreateRemoteEvent(parent, definition.EventName)
    self._events[eventKey] = event
    return event
end

function RemoteEventService:Init()
    self._events = {}
    self._eventDefinitions = {}

    local rootFolder = findOrCreateFolder(ReplicatedStorage, RemoteNames.RootFolder)
    local currencyEvents = findOrCreateFolder(rootFolder, RemoteNames.CurrencyEventsFolder)
    local systemEvents = findOrCreateFolder(rootFolder, RemoteNames.SystemEventsFolder)
    local brainrotEvents = findOrCreateFolder(rootFolder, RemoteNames.BrainrotEventsFolder)

    local eventDefinitions = {
        { Key = "CoinChanged", Parent = currencyEvents, Name = RemoteNames.Currency.CoinChanged },
        { Key = "RequestCoinSync", Parent = currencyEvents, Name = RemoteNames.Currency.RequestCoinSync },
        { Key = "HomeAssigned", Parent = systemEvents, Name = RemoteNames.System.HomeAssigned },
        { Key = "LikeTip", Parent = systemEvents, Name = RemoteNames.System.LikeTip },
        { Key = "SocialStateSync", Parent = systemEvents, Name = RemoteNames.System.SocialStateSync },
        { Key = "RequestSocialStateSync", Parent = systemEvents, Name = RemoteNames.System.RequestSocialStateSync },
        { Key = "FriendBonusSync", Parent = systemEvents, Name = RemoteNames.System.FriendBonusSync },
        { Key = "RequestFriendBonusSync", Parent = systemEvents, Name = RemoteNames.System.RequestFriendBonusSync },
        { Key = "RequestQuickTeleport", Parent = systemEvents, Name = RemoteNames.System.RequestQuickTeleport },
        { Key = "ClaimCashFeedback", Parent = systemEvents, Name = RemoteNames.System.ClaimCashFeedback },
        { Key = "RebirthStateSync", Parent = systemEvents, Name = RemoteNames.System.RebirthStateSync },
        { Key = "RequestRebirthStateSync", Parent = systemEvents, Name = RemoteNames.System.RequestRebirthStateSync },
        { Key = "RequestRebirth", Parent = systemEvents, Name = RemoteNames.System.RequestRebirth },
        { Key = "RebirthFeedback", Parent = systemEvents, Name = RemoteNames.System.RebirthFeedback },
        { Key = "RequestHomeExpansion", Parent = systemEvents, Name = RemoteNames.System.RequestHomeExpansion },
        { Key = "HomeExpansionFeedback", Parent = systemEvents, Name = RemoteNames.System.HomeExpansionFeedback },
        { Key = "SpecialEventStateSync", Parent = systemEvents, Name = RemoteNames.System.SpecialEventStateSync },
        { Key = "RequestSpecialEventStateSync", Parent = systemEvents, Name = RemoteNames.System.RequestSpecialEventStateSync },
        { Key = "LaunchPowerStateSync", Parent = systemEvents, Name = RemoteNames.System.LaunchPowerStateSync },
        { Key = "RequestLaunchPowerStateSync", Parent = systemEvents, Name = RemoteNames.System.RequestLaunchPowerStateSync },
        { Key = "RequestLaunchPowerUpgrade", Parent = systemEvents, Name = RemoteNames.System.RequestLaunchPowerUpgrade },
        { Key = "RequestStudioResetLaunchPower", Parent = systemEvents, Name = RemoteNames.System.RequestStudioResetLaunchPower },
        { Key = "LaunchPowerFeedback", Parent = systemEvents, Name = RemoteNames.System.LaunchPowerFeedback },
        { Key = "JetpackStateSync", Parent = systemEvents, Name = RemoteNames.System.JetpackStateSync },
        { Key = "RequestJetpackStateSync", Parent = systemEvents, Name = RemoteNames.System.RequestJetpackStateSync },
        { Key = "RequestJetpackCoinPurchase", Parent = systemEvents, Name = RemoteNames.System.RequestJetpackCoinPurchase },
        { Key = "RequestJetpackEquip", Parent = systemEvents, Name = RemoteNames.System.RequestJetpackEquip },
        { Key = "JetpackFeedback", Parent = systemEvents, Name = RemoteNames.System.JetpackFeedback },
        { Key = "SettingsStateSync", Parent = systemEvents, Name = RemoteNames.System.SettingsStateSync },
        { Key = "RequestSettingsStateSync", Parent = systemEvents, Name = RemoteNames.System.RequestSettingsStateSync },
        { Key = "RequestSettingsUpdate", Parent = systemEvents, Name = RemoteNames.System.RequestSettingsUpdate },
        { Key = "GroupRewardStateSync", Parent = systemEvents, Name = RemoteNames.System.GroupRewardStateSync },
        { Key = "RequestGroupRewardStateSync", Parent = systemEvents, Name = RemoteNames.System.RequestGroupRewardStateSync },
        { Key = "RequestGroupRewardClaim", Parent = systemEvents, Name = RemoteNames.System.RequestGroupRewardClaim },
        { Key = "GroupRewardFeedback", Parent = systemEvents, Name = RemoteNames.System.GroupRewardFeedback },
        { Key = "IdleCoinStateSync", Parent = systemEvents, Name = RemoteNames.System.IdleCoinStateSync },
        { Key = "RequestIdleCoinStateSync", Parent = systemEvents, Name = RemoteNames.System.RequestIdleCoinStateSync },
        { Key = "RequestIdleCoinClaim", Parent = systemEvents, Name = RemoteNames.System.RequestIdleCoinClaim },
        { Key = "RequestIdleCoinClaim10Purchase", Parent = systemEvents, Name = RemoteNames.System.RequestIdleCoinClaim10Purchase },
        { Key = "PromptIdleCoinClaim10Purchase", Parent = systemEvents, Name = RemoteNames.System.PromptIdleCoinClaim10Purchase },
        { Key = "RequestIdleCoinClaim10PurchaseClosed", Parent = systemEvents, Name = RemoteNames.System.RequestIdleCoinClaim10PurchaseClosed },
        { Key = "IdleCoinFeedback", Parent = systemEvents, Name = RemoteNames.System.IdleCoinFeedback },
        { Key = "SevenDayLoginRewardStateSync", Parent = systemEvents, Name = RemoteNames.System.SevenDayLoginRewardStateSync },
        { Key = "RequestSevenDayLoginRewardStateSync", Parent = systemEvents, Name = RemoteNames.System.RequestSevenDayLoginRewardStateSync },
        { Key = "RequestSevenDayLoginRewardClaim", Parent = systemEvents, Name = RemoteNames.System.RequestSevenDayLoginRewardClaim },
        { Key = "StarterPackStateSync", Parent = systemEvents, Name = RemoteNames.System.StarterPackStateSync },
        { Key = "RequestStarterPackStateSync", Parent = systemEvents, Name = RemoteNames.System.RequestStarterPackStateSync },
        { Key = "StealTip", Parent = systemEvents, Name = RemoteNames.System.StealTip },
        { Key = "BrainrotClaimTip", Parent = systemEvents, Name = RemoteNames.System.BrainrotClaimTip },
        { Key = "BrainrotStateSync", Parent = brainrotEvents, Name = RemoteNames.Brainrot.BrainrotStateSync },
        { Key = "RequestBrainrotStateSync", Parent = brainrotEvents, Name = RemoteNames.Brainrot.RequestBrainrotStateSync },
        { Key = "RequestBrainrotUpgrade", Parent = brainrotEvents, Name = RemoteNames.Brainrot.RequestBrainrotUpgrade },
        { Key = "BrainrotUpgradeFeedback", Parent = brainrotEvents, Name = RemoteNames.Brainrot.BrainrotUpgradeFeedback },
        { Key = "RequestBrainrotSell", Parent = brainrotEvents, Name = RemoteNames.Brainrot.RequestBrainrotSell },
        { Key = "BrainrotSellFeedback", Parent = brainrotEvents, Name = RemoteNames.Brainrot.BrainrotSellFeedback },
        { Key = "BrainrotGiftOffer", Parent = brainrotEvents, Name = RemoteNames.Brainrot.BrainrotGiftOffer },
        { Key = "RequestBrainrotGiftDecision", Parent = brainrotEvents, Name = RemoteNames.Brainrot.RequestBrainrotGiftDecision },
        { Key = "BrainrotGiftFeedback", Parent = brainrotEvents, Name = RemoteNames.Brainrot.BrainrotGiftFeedback },
        { Key = "RequestStudioBrainrotGrant", Parent = brainrotEvents, Name = RemoteNames.Brainrot.RequestStudioBrainrotGrant },
        { Key = "StudioBrainrotGrantFeedback", Parent = brainrotEvents, Name = RemoteNames.Brainrot.StudioBrainrotGrantFeedback },
        { Key = "PromptBrainrotStealPurchase", Parent = brainrotEvents, Name = RemoteNames.Brainrot.PromptBrainrotStealPurchase },
        { Key = "RequestBrainrotStealPurchaseClosed", Parent = brainrotEvents, Name = RemoteNames.Brainrot.RequestBrainrotStealPurchaseClosed },
        { Key = "BrainrotStealFeedback", Parent = brainrotEvents, Name = RemoteNames.Brainrot.BrainrotStealFeedback },
        { Key = "RequestCarryUpgrade", Parent = brainrotEvents, Name = RemoteNames.Brainrot.RequestCarryUpgrade },
        { Key = "CarryUpgradeFeedback", Parent = brainrotEvents, Name = RemoteNames.Brainrot.CarryUpgradeFeedback },
    }

    for _, eventDefinition in ipairs(eventDefinitions) do
        self:_registerEvent(eventDefinition.Key, eventDefinition.Parent, eventDefinition.Name)
    end
end

function RemoteEventService:GetEvent(eventKey)
    return self:_ensureEvent(eventKey)
end

return RemoteEventService
