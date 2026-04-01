--[[
脚本名字: CarryConfig
脚本文件: CarryConfig.lua
脚本类型: ModuleScript
Studio放置路径: ReplicatedStorage/Shared/CarryConfig
]]

local CarryConfig = {}

CarryConfig.RequestDebounceSeconds = 0.2
CarryConfig.TouchOpenPartPath = "Workspace/Scene/UpgradeCarry"
CarryConfig.PurchaseSuccessTipText = "Purchase Successful！"
CarryConfig.BaseCarryCount = 1

CarryConfig.Entries = {
    {
        Id = 101,
        Level = 1,
        CarryCount = 2,
        CoinPrice = 5000000,
        RobuxPrice = 19,
        ProductId = 3565743552,
    },
    {
        Id = 102,
        Level = 2,
        CarryCount = 3,
        CoinPrice = 20000000,
        RobuxPrice = 19,
        ProductId = 3565743801,
    },
    {
        Id = 103,
        Level = 3,
        CarryCount = 4,
        CoinPrice = 600000000,
        RobuxPrice = 19,
        ProductId = 3565744240,
    },
    {
        Id = 104,
        Level = 4,
        CarryCount = 5,
        CoinPrice = 600000000,
        RobuxPrice = 19,
        ProductId = 3565744441,
    },
}

CarryConfig.EntriesById = {}
CarryConfig.EntriesByLevel = {}
CarryConfig.EntriesByProductId = {}
CarryConfig.MaxLevel = 0
CarryConfig.MaxCarryCount = math.max(1, math.floor(tonumber(CarryConfig.BaseCarryCount) or 1))

for index, entry in ipairs(CarryConfig.Entries) do
    entry.SortOrder = index
    entry.Level = math.max(1, math.floor(tonumber(entry.Level) or index))
    entry.CarryCount = math.max(CarryConfig.MaxCarryCount, math.floor(tonumber(entry.CarryCount) or (CarryConfig.BaseCarryCount + entry.Level)))
    entry.CoinPrice = math.max(0, math.floor(tonumber(entry.CoinPrice) or 0))
    entry.RobuxPrice = math.max(0, math.floor(tonumber(entry.RobuxPrice) or 0))
    entry.ProductId = math.max(0, math.floor(tonumber(entry.ProductId) or 0))

    CarryConfig.EntriesById[entry.Id] = entry
    CarryConfig.EntriesByLevel[entry.Level] = entry
    if entry.ProductId > 0 then
        CarryConfig.EntriesByProductId[entry.ProductId] = entry
    end

    CarryConfig.MaxLevel = math.max(CarryConfig.MaxLevel, entry.Level)
    CarryConfig.MaxCarryCount = math.max(CarryConfig.MaxCarryCount, entry.CarryCount)
end

return CarryConfig
