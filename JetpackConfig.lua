--[[
脚本名字: JetpackConfig
脚本文件: JetpackConfig.lua
脚本类型: ModuleScript
Studio放置路径: ReplicatedStorage/Shared/JetpackConfig
]]

local JetpackConfig = {}

JetpackConfig.RequestDebounceSeconds = 0.2
JetpackConfig.PurchaseSuccessTipText = "Purchase Successful！"
JetpackConfig.PurchaseSuccessTipDisplaySeconds = 2
JetpackConfig.PurchaseSuccessTipEnterOffsetY = 40
JetpackConfig.PurchaseSuccessTipFadeOffsetY = -8
JetpackConfig.RuntimeAccessoryAttributeName = "JetpackRuntimeAccessory"
JetpackConfig.RuntimeJetpackIdAttributeName = "JetpackId"

JetpackConfig.Entries = {
    {
        Id = 1001,
        CoinPrice = 0,
        RobuxPrice = 0,
        ProductId = 3562613109,
        IsDefaultUnlocked = true,
        Name = "Takekopter",
        Icon = "rbxassetid://138477934814998",
        AssetPath = "ReplicatedStorage/Jetpack/Takekopter",
        NoGravityDuration = 3,
        BulletTimeFallSpeed = 0.01,
    },
    {
        Id = 1002,
        CoinPrice = 1000,
        RobuxPrice = 19,
        ProductId = 3562613276,
        IsDefaultUnlocked = false,
        Name = "StarBackpack",
        Icon = "rbxassetid://107730139753375",
        AssetPath = "ReplicatedStorage/Jetpack/StarBackpack",
        NoGravityDuration = 5,
        BulletTimeFallSpeed = 0.01,
    },
    {
        Id = 1003,
        CoinPrice = 20000,
        RobuxPrice = 29,
        ProductId = 3562613455,
        IsDefaultUnlocked = false,
        Name = "FireRocket",
        Icon = "rbxassetid://136689093387925",
        AssetPath = "ReplicatedStorage/Jetpack/FireRocket",
        NoGravityDuration = 7,
        BulletTimeFallSpeed = 0.01,
    },
    {
        Id = 1004,
        CoinPrice = 300000,
        RobuxPrice = 39,
        ProductId = 3562613596,
        IsDefaultUnlocked = false,
        Name = "Cola",
        Icon = "rbxassetid://122686478401756",
        AssetPath = "ReplicatedStorage/Jetpack/Cola",
        NoGravityDuration = 9,
        BulletTimeFallSpeed = 0.01,
    },
    {
        Id = 1005,
        CoinPrice = 6000000,
        RobuxPrice = 49,
        ProductId = 3562613719,
        IsDefaultUnlocked = false,
        Name = "Keyboard",
        Icon = "rbxassetid://118959317539160",
        AssetPath = "ReplicatedStorage/Jetpack/Keyboard",
        NoGravityDuration = 11,
        BulletTimeFallSpeed = 0.01,
    },
}

JetpackConfig.EntriesById = {}
JetpackConfig.EntriesByProductId = {}
JetpackConfig.DefaultEntryId = 0

for index, entry in ipairs(JetpackConfig.Entries) do
    entry.SortOrder = index
    JetpackConfig.EntriesById[entry.Id] = entry

    local productId = math.max(0, math.floor(tonumber(entry.ProductId) or 0))
    if productId > 0 then
        JetpackConfig.EntriesByProductId[productId] = entry
    end

    if entry.IsDefaultUnlocked and JetpackConfig.DefaultEntryId <= 0 then
        JetpackConfig.DefaultEntryId = entry.Id
    end
end

return JetpackConfig