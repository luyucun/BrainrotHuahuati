--[[
脚本名字: LuckyBlockConfig
脚本文件: LuckyBlockConfig.lua
脚本类型: ModuleScript
Studio放置路径: ReplicatedStorage/Shared/LuckyBlockConfig
]]

local LuckyBlockConfig = {}

LuckyBlockConfig.RequestDebounceSeconds = 0.35
LuckyBlockConfig.OpenTimeoutSeconds = 8
LuckyBlockConfig.ToolAttributeName = "LuckyBlockTool"
LuckyBlockConfig.ToolBlockIdAttributeName = "LuckyBlockId"
LuckyBlockConfig.ToolInstanceIdAttributeName = "LuckyBlockInstanceId"
LuckyBlockConfig.ToolModelPathAttributeName = "LuckyBlockModelPath"
LuckyBlockConfig.RuntimeVisualName = "VisualModel"
LuckyBlockConfig.PlayerEquippedBlockIdAttributeName = "EquippedLuckyBlockId"
LuckyBlockConfig.PlayerEquippedBlockInstanceIdAttributeName = "EquippedLuckyBlockInstanceId"
LuckyBlockConfig.GrantReason = "LuckyBlockOpen"

LuckyBlockConfig.HomelandPath = "Scene/Grond/Homeland"
LuckyBlockConfig.BrainrotModelRootPath = "ReplicatedStorage/Model"
LuckyBlockConfig.BrainrotModelVisualName = "BrainrotModel"

LuckyBlockConfig.OpenSpawnDistance = 6
LuckyBlockConfig.OpenSpawnEdgePadding = 2
LuckyBlockConfig.BlockFloatAmplitude = 0
LuckyBlockConfig.BlockFloatSpeed = 3.2
LuckyBlockConfig.BlockSpinDegreesPerSecond = 28
LuckyBlockConfig.PreviewHeight = 5.4
LuckyBlockConfig.PreviewFloatAmplitude = 0.22
LuckyBlockConfig.PreviewFloatSpeed = 6
LuckyBlockConfig.PreviewSpinDegreesPerSecond = 150
LuckyBlockConfig.RouletteRounds = 2
LuckyBlockConfig.RouletteStartIntervalSeconds = 0.18
LuckyBlockConfig.RouletteEndIntervalSeconds = 0.045
LuckyBlockConfig.FinalRevealHoldSeconds = 1
LuckyBlockConfig.ServerGrantBufferSeconds = 0.15
LuckyBlockConfig.BurstCubeCount = 10
LuckyBlockConfig.BurstCubeLifetimeSeconds = 0.45

LuckyBlockConfig.Entries = {
    {
        Id = 1001,
        Name = "Exclusive Block",
        ModelPath = "ReplicatedStorage/Model/Block/BlockRainbow",
        Icon = "",
        PoolId = 1001,
    },
}

LuckyBlockConfig.Pools = {
    [1001] = {
        { BrainrotId = 10004, Weight = 20 },
        { BrainrotId = 10005, Weight = 20 },
        { BrainrotId = 10006, Weight = 20 },
        { BrainrotId = 10007, Weight = 20 },
        { BrainrotId = 10008, Weight = 20 },
        { BrainrotId = 10009, Weight = 20 },
    },
}

LuckyBlockConfig.EntriesById = {}
for _, entry in ipairs(LuckyBlockConfig.Entries) do
    local blockId = math.max(0, math.floor(tonumber(entry.Id) or 0))
    if blockId > 0 then
        LuckyBlockConfig.EntriesById[blockId] = entry
    end
end

return LuckyBlockConfig
