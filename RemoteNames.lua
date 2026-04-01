--[[
脚本名字: RemoteNames
脚本文件: RemoteNames.lua
脚本类型: ModuleScript
Studio放置路径: ReplicatedStorage/Shared/RemoteNames
]]

local RemoteNames = {
    RootFolder = "Events",
    CurrencyEventsFolder = "CurrencyEvents",
    SystemEventsFolder = "SystemEvents",
    BrainrotEventsFolder = "BrainrotEvents",
    Currency = {
        CoinChanged = "CoinChanged",
        RequestCoinSync = "RequestCoinSync",
    },
    System = {
        HomeAssigned = "HomeAssigned",
        LikeTip = "LikeTip",
        SocialStateSync = "SocialStateSync",
        RequestSocialStateSync = "RequestSocialStateSync",
        FriendBonusSync = "FriendBonusSync",
        RequestFriendBonusSync = "RequestFriendBonusSync",
        RequestQuickTeleport = "RequestQuickTeleport",
        ClaimCashFeedback = "ClaimCashFeedback",
        RebirthStateSync = "RebirthStateSync",
        RequestRebirthStateSync = "RequestRebirthStateSync",
        RequestRebirth = "RequestRebirth",
        RebirthFeedback = "RebirthFeedback",
        RequestHomeExpansion = "RequestHomeExpansion",
        HomeExpansionFeedback = "HomeExpansionFeedback",
        SpecialEventStateSync = "SpecialEventStateSync",
        RequestSpecialEventStateSync = "RequestSpecialEventStateSync",
        LaunchPowerStateSync = "LaunchPowerStateSync",
        RequestLaunchPowerStateSync = "RequestLaunchPowerStateSync",
        RequestLaunchPowerUpgrade = "RequestLaunchPowerUpgrade",
        RequestStudioResetLaunchPower = "RequestStudioResetLaunchPower",
        LaunchPowerFeedback = "LaunchPowerFeedback",
        JetpackStateSync = "JetpackStateSync",
        RequestJetpackStateSync = "RequestJetpackStateSync",
        RequestJetpackCoinPurchase = "RequestJetpackCoinPurchase",
        RequestJetpackEquip = "RequestJetpackEquip",
        JetpackFeedback = "JetpackFeedback",
        SettingsStateSync = "SettingsStateSync",
        RequestSettingsStateSync = "RequestSettingsStateSync",
        RequestSettingsUpdate = "RequestSettingsUpdate",
        GroupRewardStateSync = "GroupRewardStateSync",
        RequestGroupRewardStateSync = "RequestGroupRewardStateSync",
        RequestGroupRewardClaim = "RequestGroupRewardClaim",
        GroupRewardFeedback = "GroupRewardFeedback",
        IdleCoinStateSync = "IdleCoinStateSync",
        RequestIdleCoinStateSync = "RequestIdleCoinStateSync",
        RequestIdleCoinClaim = "RequestIdleCoinClaim",
        RequestIdleCoinClaim10Purchase = "RequestIdleCoinClaim10Purchase",
        PromptIdleCoinClaim10Purchase = "PromptIdleCoinClaim10Purchase",
        RequestIdleCoinClaim10PurchaseClosed = "RequestIdleCoinClaim10PurchaseClosed",
        IdleCoinFeedback = "IdleCoinFeedback",
        SevenDayLoginRewardStateSync = "SevenDayLoginRewardStateSync",
        RequestSevenDayLoginRewardStateSync = "RequestSevenDayLoginRewardStateSync",
        RequestSevenDayLoginRewardClaim = "RequestSevenDayLoginRewardClaim",
        StarterPackStateSync = "StarterPackStateSync",
        RequestStarterPackStateSync = "RequestStarterPackStateSync",
        StealTip = "StealTip",
        BrainrotClaimTip = "BrainrotClaimTip",
    },
    Brainrot = {
        BrainrotStateSync = "BrainrotStateSync",
        RequestBrainrotStateSync = "RequestBrainrotStateSync",
        RequestBrainrotUpgrade = "RequestBrainrotUpgrade",
        BrainrotUpgradeFeedback = "BrainrotUpgradeFeedback",
        RequestBrainrotSell = "RequestBrainrotSell", -- V2.6: C -> S，请求出售单个/全部背包脑红
        BrainrotSellFeedback = "BrainrotSellFeedback", -- V2.6: S -> C，返回出售结果与剩余背包数量
        BrainrotGiftOffer = "BrainrotGiftOffer", -- V2.9: S -> C，向接收方弹出脑红赠送确认框
        RequestBrainrotGiftDecision = "RequestBrainrotGiftDecision", -- V2.9: C -> S，接收方提交接受/拒绝结果
        BrainrotGiftFeedback = "BrainrotGiftFeedback", -- V2.9: S -> C，给发起方/接收方同步赠送状态与拒绝冷却
        RequestStudioBrainrotGrant = "RequestStudioBrainrotGrant", -- Studio Only: C -> S，请求测试发放 1 个指定脑红
        StudioBrainrotGrantFeedback = "StudioBrainrotGrantFeedback", -- Studio Only: S -> C，返回测试发放结果
        PromptBrainrotStealPurchase = "PromptBrainrotStealPurchase", -- V3.1.2: S -> C prompt the steal developer product purchase
        RequestBrainrotStealPurchaseClosed = "RequestBrainrotStealPurchaseClosed", -- V3.1.2: C -> S notify the server when the steal purchase prompt closes
        BrainrotStealFeedback = "BrainrotStealFeedback", -- V3.1.2: S -> C steal flow feedback
        RequestCarryUpgrade = "RequestCarryUpgrade", -- V3.3.5: C -> S ????????
        CarryUpgradeFeedback = "CarryUpgradeFeedback", -- V3.3.5: S -> C ????????
    },
}

return RemoteNames
