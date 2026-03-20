--[[
脚本名字: MainClient
脚本文件: MainClient.client.lua
脚本类型: LocalScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/MainClient
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function requireControllerModule(moduleName)
    local controllersFolder = script.Parent:FindFirstChild("Controllers")
    if controllersFolder then
        local moduleInControllers = controllersFolder:FindFirstChild(moduleName)
        if moduleInControllers and moduleInControllers:IsA("ModuleScript") then
            return require(moduleInControllers)
        end
    end

    local moduleInRoot = script.Parent:FindFirstChild(moduleName)
    if moduleInRoot and moduleInRoot:IsA("ModuleScript") then
        return require(moduleInRoot)
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

local CoinDisplayController = requireControllerModule("CoinDisplayController")
local FriendBonusController = requireControllerModule("FriendBonusController")
local SocialController = requireControllerModule("SocialController")
local QuickTeleportController = requireControllerModule("QuickTeleportController")
local MainButtonFxController = requireControllerModule("MainButtonFxController")
local ClaimFeedbackController = requireControllerModule("ClaimFeedbackController")
local ModalController = requireControllerModule("ModalController")
local RebirthController = requireControllerModule("RebirthController")
local IndexController = requireControllerModule("IndexController")
local BrainrotUpgradeController = requireControllerModule("BrainrotUpgradeController")
local HomeExpansionController = requireControllerModule("HomeExpansionController")
local GlobalLeaderboardController = requireControllerModule("GlobalLeaderboardController")
local SpecialEventController = requireControllerModule("SpecialEventController")
local BrainrotSellController = requireControllerModule("BrainrotSellController")
local StudioBrainrotDebugController = requireControllerModule("StudioBrainrotDebugController")
local CustomBackpackController = requireControllerModule("CustomBackpackController")
local GiftController = requireControllerModule("GiftController")
local RemoteNames = requireSharedModule("RemoteNames")

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
local indexController = IndexController.new(modalController)
indexController:Start()

local brainrotUpgradeController = BrainrotUpgradeController.new()
brainrotUpgradeController:Start()

local homeExpansionController = HomeExpansionController.new()
homeExpansionController:Start()

local rebirthController = RebirthController.new(modalController)
rebirthController:Start()

local globalLeaderboardController = GlobalLeaderboardController.new()
globalLeaderboardController:Start()

local specialEventController = SpecialEventController.new()
specialEventController:Start()

local brainrotSellController = BrainrotSellController.new(modalController)
brainrotSellController:Start()

local giftController = GiftController.new(modalController)
giftController:Start()

local customBackpackController = CustomBackpackController.new(modalController)
customBackpackController:Start()
local studioBrainrotDebugController = StudioBrainrotDebugController.new()
studioBrainrotDebugController:Start()

local eventsRoot = ReplicatedStorage:WaitForChild(RemoteNames.RootFolder)
local brainrotEvents = eventsRoot:FindFirstChild(RemoteNames.BrainrotEventsFolder)
if brainrotEvents then
    local requestBrainrotStateSync = brainrotEvents:FindFirstChild(RemoteNames.Brainrot.RequestBrainrotStateSync)
    if requestBrainrotStateSync and requestBrainrotStateSync:IsA("RemoteEvent") then
        requestBrainrotStateSync:FireServer()
    end
end

