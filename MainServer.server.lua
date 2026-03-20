--[[
脚本名字: MainServer
脚本文件: MainServer.server.lua
脚本类型: Script
本地路径: D:/RobloxGame/BrainrotsTemplate/MainServer.server.lua
Studio放置路径: ServerScriptService/MainServer
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
		"[MainServer] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
		moduleName
		))
end

local function requireServerModule(moduleName)
	local servicesFolder = script.Parent:FindFirstChild("Services")
	if servicesFolder then
		local moduleInServices = servicesFolder:FindFirstChild(moduleName)
		if moduleInServices and moduleInServices:IsA("ModuleScript") then
			return require(moduleInServices)
		end
	end

	local moduleInRoot = script.Parent:FindFirstChild(moduleName)
	if moduleInRoot and moduleInRoot:IsA("ModuleScript") then
		return require(moduleInRoot)
	end

	error(string.format(
		"[MainServer] 缺少服务模块 %s（应放在 ServerScriptService/Services 或 ServerScriptService 根目录）",
		moduleName
		))
end

local GameConfig = requireSharedModule("GameConfig")
local RemoteEventService = requireServerModule("RemoteEventService")
local PlayerDataService = requireServerModule("PlayerDataService")
local HomeService = requireServerModule("HomeService")
local CurrencyService = requireServerModule("CurrencyService")
local WeaponService = requireServerModule("WeaponService")
local WeaponKnockbackService = requireServerModule("WeaponKnockbackService")
local GMCommandService = requireServerModule("GMCommandService")
local BrainrotService = requireServerModule("BrainrotService")
local HomeExpansionService = requireServerModule("HomeExpansionService")
local RebirthService = requireServerModule("RebirthService")
local FriendBonusService = requireServerModule("FriendBonusService")
local SocialService = requireServerModule("SocialService")
local QuickTeleportService = requireServerModule("QuickTeleportService")
local GlobalLeaderboardService = requireServerModule("GlobalLeaderboardService")
local SpecialEventService = requireServerModule("SpecialEventService")
local GiftService = requireServerModule("GiftService")

RemoteEventService:Init()
PlayerDataService:Init()
WeaponService:Init({
	PlayerDataService = PlayerDataService,
})
WeaponKnockbackService:Init()
HomeService:Init()
CurrencyService:Init({
	PlayerDataService = PlayerDataService,
	RemoteEventService = RemoteEventService,
})
FriendBonusService:Init({
	RemoteEventService = RemoteEventService,
})
QuickTeleportService:Init({
	HomeService = HomeService,
	RemoteEventService = RemoteEventService,
})
BrainrotService:Init({
	PlayerDataService = PlayerDataService,
	HomeService = HomeService,
	CurrencyService = CurrencyService,
	FriendBonusService = FriendBonusService,
	RemoteEventService = RemoteEventService,
})
HomeExpansionService:Init({
	PlayerDataService = PlayerDataService,
	HomeService = HomeService,
	CurrencyService = CurrencyService,
	RemoteEventService = RemoteEventService,
	BrainrotService = BrainrotService,
})
RebirthService:Init({
	PlayerDataService = PlayerDataService,
	CurrencyService = CurrencyService,
	BrainrotService = BrainrotService,
	RemoteEventService = RemoteEventService,
})
GMCommandService:Init({
	CurrencyService = CurrencyService,
	HomeExpansionService = HomeExpansionService,
	BrainrotService = BrainrotService,
	RebirthService = RebirthService,
	PlayerDataService = PlayerDataService,
	HomeService = HomeService,
	WeaponService = WeaponService,
	GlobalLeaderboardService = GlobalLeaderboardService,
	SpecialEventService = SpecialEventService,
})
SocialService:Init({
	PlayerDataService = PlayerDataService,
	HomeService = HomeService,
	RemoteEventService = RemoteEventService,
})
GlobalLeaderboardService:Init({
	PlayerDataService = PlayerDataService,
	FriendBonusService = FriendBonusService,
})
SpecialEventService:Init({
	RemoteEventService = RemoteEventService,
})
GiftService:Init({
	RemoteEventService = RemoteEventService,
	BrainrotService = BrainrotService,
})

local function onPlayerAdded(player)
	local assignedHome = HomeService:AssignHome(player)
	if not assignedHome then
		player:Kick("当前服务器家园已满（最多 5 人）")
		return
	end

	PlayerDataService:LoadPlayerData(player)
	PlayerDataService:SetHomeId(player, assignedHome.Name)
	player:SetAttribute("HomeId", assignedHome.Name)
	WeaponService:OnPlayerReady(player)
	WeaponKnockbackService:OnPlayerReady(player)
	GMCommandService:BindPlayer(player)
	FriendBonusService:OnPlayerReady(player)
	RebirthService:OnPlayerReady(player)
	HomeExpansionService:OnPlayerReady(player, assignedHome)
	BrainrotService:OnPlayerReady(player, assignedHome)
	GiftService:OnPlayerReady(player)
	SocialService:OnPlayerReady(player, assignedHome)
	SpecialEventService:OnPlayerReady(player)

	local homeAssignedEvent = RemoteEventService:GetEvent("HomeAssigned")
	if homeAssignedEvent then
		homeAssignedEvent:FireClient(player, {
			homeId = assignedHome.Name,
		})
	end

	if player.Character then
		HomeService:TeleportPlayerToHomeSpawn(player)
	end

	CurrencyService:OnPlayerReady(player)
	GlobalLeaderboardService:OnPlayerReady(player)

	if #Players:GetPlayers() > GameConfig.MAX_SERVER_PLAYERS then
		warn("[MainServer] 在线人数超过配置上限，请检查游戏服务器最大人数设置")
	end
end

local function onPlayerRemoving(player)
	local assignedHome = HomeService:GetAssignedHome(player)
	GMCommandService:UnbindPlayer(player)
	WeaponKnockbackService:OnPlayerRemoving(player)
	WeaponService:OnPlayerRemoving(player)
	GlobalLeaderboardService:OnPlayerRemoving(player)
	FriendBonusService:OnPlayerRemoving(player)
	BrainrotService:OnPlayerRemoving(player)
	GiftService:OnPlayerRemoving(player)
	HomeExpansionService:OnPlayerRemoving(player, assignedHome)
	RebirthService:OnPlayerRemoving(player)
	CurrencyService:OnPlayerRemoving(player)
	SocialService:OnPlayerRemoving(player, assignedHome)
	SpecialEventService:OnPlayerRemoving(player)
	HomeService:ReleaseHome(player)
	PlayerDataService:OnPlayerRemoving(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

game:BindToClose(function()
	GlobalLeaderboardService:FlushAllPlayers()
	PlayerDataService:SaveAllPlayers()
end)

