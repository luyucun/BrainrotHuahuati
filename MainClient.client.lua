--[[
脚本名字: MainClient
脚本文件: MainClient.client.lua
脚本类型: LocalScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/MainClient
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local localPlayer = Players.LocalPlayer
local ENABLE_CUSTOM_BACKPACK = false

local function setCoreBackpackEnabled(enabled)
    pcall(function()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, enabled == true)
    end)
end

local function findControllerModuleScript(moduleName)
    local controllersFolder = script.Parent:FindFirstChild("Controllers")
    if controllersFolder then
        local moduleInControllers = controllersFolder:FindFirstChild(moduleName)
        if moduleInControllers and moduleInControllers:IsA("ModuleScript") then
            return moduleInControllers
        end
    end

    local moduleInRoot = script.Parent:FindFirstChild(moduleName)
    if moduleInRoot and moduleInRoot:IsA("ModuleScript") then
        return moduleInRoot
    end

    return nil
end

local function requireControllerModule(moduleName)
    local moduleScript = findControllerModuleScript(moduleName)
    if moduleScript then
        return require(moduleScript)
    end

    error(string.format(
        "[MainClient] 缺少控制器模块 %s（应放在 StarterPlayerScripts/Controllers 或 StarterPlayerScripts 根目录）",
        moduleName
    ))
end

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
        "[MainClient] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local function tryRequireControllerModule(moduleName)
    local moduleScript = findControllerModuleScript(moduleName)
    if not moduleScript then
        return nil
    end

    local ok, result = pcall(require, moduleScript)
    if ok then
        return result
    end

    warn(string.format("[MainClient] 可选控制器模块加载失败 %s: %s", tostring(moduleName), tostring(result)))
    return nil
end

local function startOptionalController(moduleRef, ...)
    if type(moduleRef) ~= "table" or type(moduleRef.new) ~= "function" then
        return nil
    end

    local packedArgs = table.pack(...)
    local okCreate, controllerOrError = pcall(
        moduleRef.new,
        table.unpack(packedArgs, 1, packedArgs.n)
    )
    if not okCreate then
        warn(string.format("[MainClient] 可选控制器创建失败: %s", tostring(controllerOrError)))
        return nil
    end

    if controllerOrError and type(controllerOrError.Start) == "function" then
        local okStart, startError = pcall(function()
            controllerOrError:Start()
        end)
        if not okStart then
            warn(string.format("[MainClient] 可选控制器启动失败: %s", tostring(startError)))
            return nil
        end
    end

    return controllerOrError
end

local function getPlayerGui()
    return localPlayer:FindFirstChild("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
end

local function waitForMainGui(timeoutSeconds)
    local playerGui = getPlayerGui()
    if not playerGui then
        return nil
    end

    local deadline = os.clock() + math.max(0, tonumber(timeoutSeconds) or 0)
    repeat
        local mainGui = playerGui:FindFirstChild("Main") or playerGui:FindFirstChild("Main", true)
        if mainGui and mainGui:IsA("LayerCollector") then
            return mainGui
        end

        task.wait(0.25)
        if not playerGui.Parent then
            playerGui = getPlayerGui()
            if not playerGui then
                return nil
            end
        end
    until os.clock() >= deadline

    local mainGui = playerGui:FindFirstChild("Main") or playerGui:FindFirstChild("Main", true)
    if mainGui and mainGui:IsA("LayerCollector") then
        return mainGui
    end

    return nil
end

local CoinDisplayController = requireControllerModule("CoinDisplayController")
local FriendBonusController = requireControllerModule("FriendBonusController")
local SocialController = requireControllerModule("SocialController")
local QuickTeleportController = requireControllerModule("QuickTeleportController")
local MainButtonFxController = requireControllerModule("MainButtonFxController")
local ClaimFeedbackController = requireControllerModule("ClaimFeedbackController")
local ModalController = requireControllerModule("ModalController")
local SettingsController = requireControllerModule("SettingsController")
local GroupRewardController = requireControllerModule("GroupRewardController")
local IdleCoinController = requireControllerModule("IdleCoinController")
local SevenDayLoginRewardController = requireControllerModule("SevenDayLoginRewardController")
local StarterPackController = requireControllerModule("StarterPackController")
local RebirthController = requireControllerModule("RebirthController")
local LaunchPowerUpgradeController = requireControllerModule("LaunchPowerUpgradeController")
local ProgressController = requireControllerModule("ProgressController")
local JetpackController = requireControllerModule("JetpackController")
local LuckyBlockController = requireControllerModule("LuckyBlockController")
local ShopController = requireControllerModule("ShopController")
local IndexController = requireControllerModule("IndexController")
local BrainrotUpgradeController = requireControllerModule("BrainrotUpgradeController")
local BrainrotPlatformPromptController = requireControllerModule("BrainrotPlatformPromptController")
local BrainrotStealController = requireControllerModule("BrainrotStealController")
local BrainrotClaimTipsController = tryRequireControllerModule("BrainrotClaimTipsController")
local BrainrotWorldSpawnCountdownController = tryRequireControllerModule("BrainrotWorldSpawnCountdownController")
local BrainrotBossController = tryRequireControllerModule("BrainrotBossController")
local HomeExpansionController = requireControllerModule("HomeExpansionController")
local GlobalLeaderboardController = requireControllerModule("GlobalLeaderboardController")
local SpecialEventController = requireControllerModule("SpecialEventController")
local BrainrotSellController = requireControllerModule("BrainrotSellController")
local CarryUpgradeController = tryRequireControllerModule("CarryUpgradeController")
local NpcIdleAnimationController = tryRequireControllerModule("NpcIdleAnimationController")
local InviteController = tryRequireControllerModule("InviteController")
local StudioBrainrotDebugController = tryRequireControllerModule("StudioBrainrotDebugController")
local StudioBossDebugController = tryRequireControllerModule("StudioBossDebugController")
local CustomBackpackController = requireControllerModule("CustomBackpackController")
local GiftController = requireControllerModule("GiftController")
local SlideController = requireControllerModule("SlideController")
local SeaHazardController = requireControllerModule("SeaHazardController")
local StudioSlideDebugController = tryRequireControllerModule("StudioSlideDebugController")
local RemoteNames = requireSharedModule("RemoteNames")

-- Give PlayerGui/Main a brief head start without blocking the full client startup for too long.
waitForMainGui(3)

local coinDisplayController = CoinDisplayController.new()
coinDisplayController:Start()

local friendBonusController = FriendBonusController.new()
friendBonusController:Start()

local socialController = SocialController.new()
socialController:Start()

local quickTeleportController = QuickTeleportController.new()
quickTeleportController:Start()

local mainButtonFxController = MainButtonFxController.new()
mainButtonFxController:Start()

local claimFeedbackController = ClaimFeedbackController.new()
claimFeedbackController:Start()

local modalController = ModalController.new()
local settingsController = SettingsController.new(modalController)
settingsController:Start()

local groupRewardController = GroupRewardController.new(modalController)
groupRewardController:Start()

local sevenDayLoginRewardController = SevenDayLoginRewardController.new(modalController)
sevenDayLoginRewardController:Start()

local starterPackController = StarterPackController.new(modalController)
starterPackController:Start()

local idleCoinController = IdleCoinController.new(modalController)
idleCoinController:Start()

local indexController = IndexController.new(modalController)
indexController:Start()

local brainrotUpgradeController = BrainrotUpgradeController.new()
brainrotUpgradeController:Start()

local brainrotPlatformPromptController = BrainrotPlatformPromptController.new()
brainrotPlatformPromptController:Start()

local brainrotStealController = BrainrotStealController.new()
brainrotStealController:Start()

local brainrotClaimTipsController = startOptionalController(BrainrotClaimTipsController)
local brainrotWorldSpawnCountdownController = startOptionalController(BrainrotWorldSpawnCountdownController)
local brainrotBossController = startOptionalController(BrainrotBossController)

local homeExpansionController = HomeExpansionController.new()
homeExpansionController:Start()

local rebirthController = RebirthController.new(modalController)
rebirthController:Start()

local launchPowerUpgradeController = LaunchPowerUpgradeController.new(modalController)
launchPowerUpgradeController:Start()

local progressController = ProgressController.new()
progressController:Start()

local jetpackController = JetpackController.new(modalController)
jetpackController:Start()

local shopController = ShopController.new(modalController)
shopController:Start()

local globalLeaderboardController = GlobalLeaderboardController.new()
globalLeaderboardController:Start()

local specialEventController = SpecialEventController.new()
specialEventController:Start()

local brainrotSellController = BrainrotSellController.new(modalController)
brainrotSellController:Start()

local carryUpgradeController = startOptionalController(CarryUpgradeController, modalController)
local npcIdleAnimationController = startOptionalController(NpcIdleAnimationController)
local inviteController = startOptionalController(InviteController)

local giftController = GiftController.new(modalController)
giftController:Start()

if ENABLE_CUSTOM_BACKPACK then
    local customBackpackController = CustomBackpackController.new(modalController)
    customBackpackController:Start()
else
    setCoreBackpackEnabled(true)
end

local luckyBlockController = LuckyBlockController.new()
luckyBlockController:Start()

local slideController = SlideController.new(progressController)
slideController:Start()

local seaHazardController = SeaHazardController.new()
seaHazardController:Start()

local studioSlideDebugController = startOptionalController(StudioSlideDebugController)
local studioBrainrotDebugController = startOptionalController(StudioBrainrotDebugController)
local studioBossDebugController = startOptionalController(StudioBossDebugController)

local eventsRoot = ReplicatedStorage:WaitForChild(RemoteNames.RootFolder)
local brainrotEvents = eventsRoot:FindFirstChild(RemoteNames.BrainrotEventsFolder)
if brainrotEvents then
    local requestBrainrotStateSync = brainrotEvents:FindFirstChild(RemoteNames.Brainrot.RequestBrainrotStateSync)
    if requestBrainrotStateSync and requestBrainrotStateSync:IsA("RemoteEvent") then
        requestBrainrotStateSync:FireServer()
    end
end
