--[[
脚本名字: RemoteNames
脚本文件: RemoteNames.lua
脚本类型: ModuleScript
本地路径: D:/RobloxGame/BrainrotsTemplate/RemoteNames.lua
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
    },
}

return RemoteNames


