--[[
脚本名字: RebirthConfig
脚本文件: RebirthConfig.lua
脚本类型: ModuleScript
本地路径: D:/RobloxGame/BrainrotsTemplate/RebirthConfig.lua
Studio放置路径: ReplicatedStorage/Shared/RebirthConfig
]]

local RebirthConfig = {}

RebirthConfig.Entries = {
    { Level = 1, RequiredCoins = 1000, BonusRate = 0.5 },
    { Level = 2, RequiredCoins = 2000, BonusRate = 1 },
    { Level = 3, RequiredCoins = 3000, BonusRate = 1.5 },
    { Level = 4, RequiredCoins = 40000, BonusRate = 2 },
    { Level = 5, RequiredCoins = 500000, BonusRate = 2.5 },
    { Level = 6, RequiredCoins = 6000000, BonusRate = 3 },
    { Level = 7, RequiredCoins = 70000000, BonusRate = 3.5 },
    { Level = 8, RequiredCoins = 800000000, BonusRate = 4 },
    { Level = 9, RequiredCoins = 9000000000, BonusRate = 4.5 },
}

RebirthConfig.ByLevel = {}
RebirthConfig.MaxLevel = 0

for _, entry in ipairs(RebirthConfig.Entries) do
    local rebirthLevel = math.max(0, math.floor(tonumber(entry.Level) or 0))
    if rebirthLevel > 0 then
        entry.Level = rebirthLevel
        entry.RequiredCoins = math.max(0, math.floor(tonumber(entry.RequiredCoins) or 0))
        entry.BonusRate = math.max(0, tonumber(entry.BonusRate) or 0)
        RebirthConfig.ByLevel[rebirthLevel] = entry
        RebirthConfig.MaxLevel = math.max(RebirthConfig.MaxLevel, rebirthLevel)
    end
end

return RebirthConfig
