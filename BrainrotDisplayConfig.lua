--[[
脚本名字: BrainrotDisplayConfig
脚本文件: BrainrotDisplayConfig.lua
脚本类型: ModuleScript
Studio放置路径: ReplicatedStorage/Shared/BrainrotDisplayConfig
]]

local BrainrotDisplayConfig = {}

BrainrotDisplayConfig.Quality = {
    [1] = {
        Name = "Common",
        GradientPath = "StarterGui/Gradients/Animation/Quality/Common",
    },
    [2] = {
        Name = "Uncommon",
        GradientPath = "StarterGui/Gradients/Animation/Quality/Uncommon",
    },
    [3] = {
        Name = "Rare",
        GradientPath = "StarterGui/Gradients/Animation/Quality/Rare",
    },
    [4] = {
        Name = "Epic",
        GradientPath = "StarterGui/Gradients/Animation/Quality/Epic",
    },
    [5] = {
        Name = "Legendary",
        GradientPath = "StarterGui/Gradients/Animation/Quality/Legendary",
    },
    [6] = {
        Name = "Mythic",
        GradientPath = "StarterGui/Gradients/Animation/Quality/Mythic",
    },
    [7] = {
        Name = "Secret",
        GradientPath = {
            "StarterGui/Gradients/Animation/Quality/Secret1",
            "StarterGui/Gradients/Animation/Quality/Secret2",
        },
    },
    [8] = {
        Name = "God",
        GradientPath = "StarterGui/Gradients/Animation/Quality/God",
    },
    [9] = {
        Name = "OG",
        GradientPath = "StarterGui/Gradients/Animation/Quality/OG",
    },
}

BrainrotDisplayConfig.Rarity = {
    [1] = {
        Name = "Normal",
        GradientPath = "StarterGui/Gradients/Animation/Rarity/Common",
    },
    [2] = {
        Name = "Gold",
        GradientPath = "StarterGui/Gradients/Animation/Rarity/Gold",
    },
    [3] = {
        Name = "Diamond",
        GradientPath = "StarterGui/Gradients/Animation/Rarity/Diamond",
    },
    [4] = {
        Name = "Hacker",
        GradientPath = "StarterGui/Gradients/Animation/Rarity/Hacker",
    },
    [5] = {
        Name = "Lava",
        GradientPath = "StarterGui/Gradients/Animation/Rarity/Lava",
    },
    [6] = {
        Name = "Rainbow",
        GradientPath = "StarterGui/Gradients/Animation/Rarity/Rainbow",
    },
}

return BrainrotDisplayConfig



