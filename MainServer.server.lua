--[[
脚本名字: MainServer
脚本文件: MainServer.server.lua
脚本类型: Script
Studio放置路径: ServerScriptService/MainServer
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

Players.RespawnTime = 0

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
local SettingsService = requireServerModule("SettingsService")
local GroupRewardService = requireServerModule("GroupRewardService")
local IdleCoinService = requireServerModule("IdleCoinService")
local SevenDayLoginRewardService = requireServerModule("SevenDayLoginRewardService")
local StarterPackService = requireServerModule("StarterPackService")
local HomeService = requireServerModule("HomeService")
local CurrencyService = requireServerModule("CurrencyService")
local WeaponService = requireServerModule("WeaponService")
local WeaponKnockbackService = requireServerModule("WeaponKnockbackService")
local GMCommandService = requireServerModule("GMCommandService")
local BrainrotService = requireServerModule("BrainrotService")
local HomeExpansionService = requireServerModule("HomeExpansionService")
local RebirthService = requireServerModule("RebirthService")
local LaunchPowerService = requireServerModule("LaunchPowerService")
local JetpackService = requireServerModule("JetpackService")
local FriendBonusService = requireServerModule("FriendBonusService")
local SocialService = requireServerModule("SocialService")
local QuickTeleportService = requireServerModule("QuickTeleportService")
local GlobalLeaderboardService = requireServerModule("GlobalLeaderboardService")
local SpecialEventService = requireServerModule("SpecialEventService")
local GiftService = requireServerModule("GiftService")

local ICE_TOUCH_DEBOUNCE_SECONDS = 0.5

local iceTouchConnections = {}
local iceDescendantAddedConnection = nil
local iceKillClockByUserId = {}

local function disconnectConnection(connection)
	if connection then
		connection:Disconnect()
	end
end

local function resolveHumanoidFromHitPart(hitPart)
	if not (hitPart and hitPart:IsA("BasePart")) then
		return nil, nil
	end

	local current = hitPart.Parent
	while current and current ~= Workspace do
		if current:IsA("Model") then
			local humanoid = current:FindFirstChildOfClass("Humanoid")
			if humanoid then
				return current, humanoid
			end
		end

		current = current.Parent
	end

	return nil, nil
end

local function killCharacterFromIceTouch(hitPart)
	local character, humanoid = resolveHumanoidFromHitPart(hitPart)
	if not (character and humanoid) then
		return
	end

	if humanoid.Health <= 0 then
		return
	end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	local now = os.clock()
	local lastKillClock = iceKillClockByUserId[player.UserId]
	if lastKillClock and now - lastKillClock < ICE_TOUCH_DEBOUNCE_SECONDS then
		return
	end

	iceKillClockByUserId[player.UserId] = now
	humanoid.Health = 0
end

local function bindIceBasePart(part)
	if not (part and part:IsA("BasePart")) then
		return false
	end

	if iceTouchConnections[part] then
		return true
	end

	iceTouchConnections[part] = part.Touched:Connect(function(hitPart)
		killCharacterFromIceTouch(hitPart)
	end)

	return true
end

local function bindIceHazardTree(iceRoot)
	if not iceRoot then
		return false
	end

	local didBind = false
	if iceRoot:IsA("BasePart") then
		didBind = bindIceBasePart(iceRoot) or didBind
	end

	for _, descendant in ipairs(iceRoot:GetDescendants()) do
		if descendant:IsA("BasePart") then
			didBind = bindIceBasePart(descendant) or didBind
		end
	end

	return didBind
end

local function bindIceHazard()
	local iceRoot = Workspace:FindFirstChild("Ice") or Workspace:FindFirstChild("Ice", true)
	if not iceRoot then
		warn("[MainServer] 找不到 Workspace/Ice，冰面触碰致死功能未启用。")
		return
	end

	if not bindIceHazardTree(iceRoot) then
		warn(string.format(
			"[MainServer] Ice 节点存在但没有可触碰的 BasePart: %s",
			iceRoot:GetFullName()
		))
		return
	end

	disconnectConnection(iceDescendantAddedConnection)
	iceDescendantAddedConnection = iceRoot.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			bindIceBasePart(descendant)
		end
	end)
end

RemoteEventService:Init()
PlayerDataService:Init()
SettingsService:Init({
	PlayerDataService = PlayerDataService,
	RemoteEventService = RemoteEventService,
})
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
JetpackService:Init({
	PlayerDataService = PlayerDataService,
	CurrencyService = CurrencyService,
	RemoteEventService = RemoteEventService,
})
BrainrotService:Init({
	PlayerDataService = PlayerDataService,
	HomeService = HomeService,
	CurrencyService = CurrencyService,
	FriendBonusService = FriendBonusService,
	RemoteEventService = RemoteEventService,
	ReceiptHandlers = { JetpackService, IdleCoinService, SevenDayLoginRewardService },
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
LaunchPowerService:Init({
	PlayerDataService = PlayerDataService,
	CurrencyService = CurrencyService,
	RemoteEventService = RemoteEventService,
})
GMCommandService:Init({
	CurrencyService = CurrencyService,
	HomeExpansionService = HomeExpansionService,
	BrainrotService = BrainrotService,
	RebirthService = RebirthService,
	LaunchPowerService = LaunchPowerService,
	PlayerDataService = PlayerDataService,
	HomeService = HomeService,
	WeaponService = WeaponService,
	GlobalLeaderboardService = GlobalLeaderboardService,
	SpecialEventService = SpecialEventService,
	StarterPackService = StarterPackService,
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
GroupRewardService:Init({
	PlayerDataService = PlayerDataService,
	RemoteEventService = RemoteEventService,
	BrainrotService = BrainrotService,
})
IdleCoinService:Init({
	PlayerDataService = PlayerDataService,
	RemoteEventService = RemoteEventService,
	BrainrotService = BrainrotService,
})
SevenDayLoginRewardService:Init({
	PlayerDataService = PlayerDataService,
	CurrencyService = CurrencyService,
	RemoteEventService = RemoteEventService,
	BrainrotService = BrainrotService,
})
StarterPackService:Init({
	PlayerDataService = PlayerDataService,
	RemoteEventService = RemoteEventService,
	CurrencyService = CurrencyService,
	BrainrotService = BrainrotService,
})
bindIceHazard()

local function onPlayerAdded(player)
	local assignedHome = HomeService:AssignHome(player)
	if not assignedHome then
		player:Kick("当前服务器家园已满（最多 5 人）")
		return
	end

	PlayerDataService:LoadPlayerData(player)
	SettingsService:OnPlayerReady(player)
	GroupRewardService:OnPlayerReady(player)
	PlayerDataService:SetHomeId(player, assignedHome.Name)
	player:SetAttribute("HomeId", assignedHome.Name)
	WeaponService:OnPlayerReady(player)
	WeaponKnockbackService:OnPlayerReady(player)
	GMCommandService:BindPlayer(player)
	FriendBonusService:OnPlayerReady(player)
	RebirthService:OnPlayerReady(player)
	LaunchPowerService:OnPlayerReady(player)
	JetpackService:OnPlayerReady(player)
	HomeExpansionService:OnPlayerReady(player, assignedHome)
	BrainrotService:OnPlayerReady(player, assignedHome)
	StarterPackService:OnPlayerReady(player)
	SevenDayLoginRewardService:OnPlayerReady(player)
	IdleCoinService:OnPlayerReady(player)
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
	iceKillClockByUserId[player.UserId] = nil
	GMCommandService:UnbindPlayer(player)
	WeaponKnockbackService:OnPlayerRemoving(player)
	WeaponService:OnPlayerRemoving(player)
	GlobalLeaderboardService:OnPlayerRemoving(player)
	FriendBonusService:OnPlayerRemoving(player)
	BrainrotService:OnPlayerRemoving(player)
	GiftService:OnPlayerRemoving(player)
	HomeExpansionService:OnPlayerRemoving(player, assignedHome)
	RebirthService:OnPlayerRemoving(player)
	LaunchPowerService:OnPlayerRemoving(player)
	JetpackService:OnPlayerRemoving(player)
	CurrencyService:OnPlayerRemoving(player)
	SocialService:OnPlayerRemoving(player, assignedHome)
	SpecialEventService:OnPlayerRemoving(player)
	SettingsService:OnPlayerRemoving(player)
	GroupRewardService:OnPlayerRemoving(player)
	IdleCoinService:OnPlayerRemoving(player)
	SevenDayLoginRewardService:OnPlayerRemoving(player)
	StarterPackService:OnPlayerRemoving(player)
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
