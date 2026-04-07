--[[
脚本名字: RebirthConfig
脚本文件: RebirthConfig.lua
脚本类型: ModuleScript
Studio放置路径: ReplicatedStorage/Shared/RebirthConfig
]]

local RebirthConfig = {}

RebirthConfig.FirstRequiredCoins = 5000
RebirthConfig.RequiredCoinsMultiplier = 15
RebirthConfig.SkipProductId = 3571688214

function RebirthConfig.NormalizeLevel(level)
    return math.max(0, math.floor(tonumber(level) or 0))
end

function RebirthConfig.GetBonusRateByLevel(level)
    return RebirthConfig.NormalizeLevel(level)
end

function RebirthConfig.GetNextLevel(currentLevel)
    return RebirthConfig.NormalizeLevel(currentLevel) + 1
end

function RebirthConfig.GetRequiredCoinsForNextLevel(currentLevel)
    local normalizedLevel = RebirthConfig.NormalizeLevel(currentLevel)
    local requiredCoins = math.max(0, math.floor(tonumber(RebirthConfig.FirstRequiredCoins) or 0))
    local multiplier = math.max(1, math.floor(tonumber(RebirthConfig.RequiredCoinsMultiplier) or 1))

    for _ = 1, normalizedLevel do
        requiredCoins = math.floor((requiredCoins * multiplier) + 0.5)
    end

    return requiredCoins
end

return RebirthConfig
