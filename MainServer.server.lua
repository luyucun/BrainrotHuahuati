--[[
脚本名字: MainServer
脚本文件: MainServer.server.lua
脚本类型: Script
Studio放置路径: ServerScriptService/MainServer
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

Players.RespawnTime = 0.5

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
local StudioBossDebugService = requireServerModule("StudioBossDebugService")
local HomeExpansionService = requireServerModule("HomeExpansionService")
local RebirthService = requireServerModule("RebirthService")
local LaunchPowerService = requireServerModule("LaunchPowerService")
local ProgressService = requireServerModule("ProgressService")
local JetpackService = requireServerModule("JetpackService")
local LuckyBlockService = requireServerModule("LuckyBlockService")
local ShopService = requireServerModule("ShopService")
local FriendBonusService = requireServerModule("FriendBonusService")
local SocialService = requireServerModule("SocialService")
local QuickTeleportService = requireServerModule("QuickTeleportService")
local GlobalLeaderboardService = requireServerModule("GlobalLeaderboardService")
local SpecialEventService = requireServerModule("SpecialEventService")
local GiftService = requireServerModule("GiftService")

local SEA_TOUCH_DEBOUNCE_SECONDS = 0.05
local SEA_TOUCH_VALIDATION_RETRY_COUNT = 4
local SEA_TOUCH_VALIDATION_RETRY_INTERVAL = 0.05
local SEA_RESPAWN_GRACE_SECONDS = 1
local SEA_RESPAWN_ARM_CHECK_INTERVAL = 0.1

local seaTouchConnections = {}
local seaDescendantAddedConnection = nil
local seaHazardTriggerClockByUserId = {}
local seaHazardArmedByUserId = {}
local seaHazardArmTokenByUserId = {}
local requestSeaHazardDeathEvent = nil
local beginSeaHazardRespawnGrace

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

local function teleportPlayerFromSea(player, character)
	if not (player and character) then
		return
	end

	if seaHazardArmedByUserId[player.UserId] ~= true then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health <= 0 then
		return
	end

	local now = os.clock()
	local lastTriggerClock = seaHazardTriggerClockByUserId[player.UserId]
	if lastTriggerClock and now - lastTriggerClock < SEA_TOUCH_DEBOUNCE_SECONDS then
		return
	end

	seaHazardTriggerClockByUserId[player.UserId] = now
	HomeService:TeleportPlayerToHomeSpawn(player)
	beginSeaHazardRespawnGrace(player, player.Character)
end

local function teleportCharacterFromSeaTouch(hitPart)
	local character, humanoid = resolveHumanoidFromHitPart(hitPart)
	if not (character and humanoid) then
		return
	end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	teleportPlayerFromSea(player, character)
end

local function getCharacterOverlapParams(character)
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = { character }
	return overlapParams
end

local function isCharacterTouchingSeaPart(character, seaPart)
	if not (character and seaPart and seaPart:IsA("BasePart") and seaPart.Parent) then
		return false
	end

	local ok, touchingParts = pcall(function()
		return Workspace:GetPartsInPart(seaPart, getCharacterOverlapParams(character))
	end)
	if not ok then
		return false
	end

	for _, touchingPart in ipairs(touchingParts) do
		if touchingPart and touchingPart:IsDescendantOf(character) then
			return true
		end
	end

	return false
end

local function isCharacterTouchingSea(character, seaPart)
	if not character then
		return false
	end

	if seaPart and seaTouchConnections[seaPart] and isCharacterTouchingSeaPart(character, seaPart) then
		return true
	end

	for hazardPart in pairs(seaTouchConnections) do
		if isCharacterTouchingSeaPart(character, hazardPart) then
			return true
		end
	end

	return false
end

beginSeaHazardRespawnGrace = function(player, character)
	if not (player and character) then
		return
	end

	local userId = player.UserId
	local nextToken = (seaHazardArmTokenByUserId[userId] or 0) + 1
	seaHazardArmTokenByUserId[userId] = nextToken
	seaHazardArmedByUserId[userId] = false

	task.spawn(function()
		local startedAt = os.clock()
		while seaHazardArmTokenByUserId[userId] == nextToken do
			if player.Parent == nil then
				return
			end

			local currentCharacter = player.Character
			if currentCharacter ~= character or character.Parent == nil then
				return
			end

			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health <= 0 then
				return
			end

			if os.clock() - startedAt >= SEA_RESPAWN_GRACE_SECONDS and not isCharacterTouchingSea(character) then
				seaHazardArmedByUserId[userId] = true
				return
			end

			task.wait(SEA_RESPAWN_ARM_CHECK_INTERVAL)
		end
	end)
end

local function runBindToCloseTasks(taskCallbacks, timeoutSeconds)
	local callbacks = taskCallbacks or {}
	local taskStateByName = {}
	local taskNames = {}
	for name, callback in pairs(callbacks) do
		if type(callback) == "function" then
			taskStateByName[name] = {
				Done = false,
				Success = false,
				Error = nil,
			}
			table.insert(taskNames, name)
			task.spawn(function()
				local ok, result = pcall(callback)
				local state = taskStateByName[name]
				if not state then
					return
				end

				state.Done = true
				state.Success = ok and result ~= false
				if not ok then
					state.Error = tostring(result)
				end
			end)
		end
	end

	if #taskNames <= 0 then
		return
	end

	local deadline = os.clock() + math.max(1, tonumber(timeoutSeconds) or 25)
	while os.clock() < deadline do
		local allDone = true
		for _, name in ipairs(taskNames) do
			local state = taskStateByName[name]
			if state and not state.Done then
				allDone = false
				break
			end
		end

		if allDone then
			break
		end

		task.wait(0.1)
	end

	for _, name in ipairs(taskNames) do
		local state = taskStateByName[name]
		if state and not state.Done then
			warn(string.format("[MainServer] BindToClose timed out waiting for %s", name))
		elseif state and not state.Success then
			warn(string.format(
				"[MainServer] BindToClose task failed: %s%s",
				name,
				state.Error and (" err=" .. state.Error) or ""
			))
		end
	end
end

local function onRequestSeaHazardDeath(player, payload)
	if not player then
		return
	end

	local character = player.Character
	if not (character and character.Parent) then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local seaPart = type(payload) == "table" and payload.SeaPart or nil
	if seaPart and not seaPart:IsA("BasePart") then
		seaPart = nil
	end

	for attempt = 1, SEA_TOUCH_VALIDATION_RETRY_COUNT do
		if not (character.Parent and humanoid.Parent) then
			return
		end

		if humanoid.Health <= 0 then
			return
		end

		if isCharacterTouchingSea(character, seaPart) then
			teleportPlayerFromSea(player, character)
			return
		end

		if attempt < SEA_TOUCH_VALIDATION_RETRY_COUNT then
			task.wait(SEA_TOUCH_VALIDATION_RETRY_INTERVAL)
		end
	end
end

local function bindSeaBasePart(part)
	if not (part and part:IsA("BasePart")) then
		return false
	end

	if seaTouchConnections[part] then
		return true
	end

	seaTouchConnections[part] = part.Touched:Connect(function(hitPart)
		teleportCharacterFromSeaTouch(hitPart)
	end)

	return true
end

local function bindSeaHazardTree(seaRoot)
	if not seaRoot then
		return false
	end

	local didBind = false
	if seaRoot:IsA("BasePart") then
		didBind = bindSeaBasePart(seaRoot) or didBind
	end

	for _, descendant in ipairs(seaRoot:GetDescendants()) do
		if descendant:IsA("BasePart") then
			didBind = bindSeaBasePart(descendant) or didBind
		end
	end

	return didBind
end

local function bindSeaHazard()
	local seaRoot = Workspace:FindFirstChild("Sea") or Workspace:FindFirstChild("Sea", true)
	if not seaRoot then
		warn("[MainServer] 找不到 Workspace/Sea，海面触碰致死功能未启用。")
		return
	end

	if not bindSeaHazardTree(seaRoot) then
		warn(string.format(
			"[MainServer] Sea 节点存在但没有可触碰的 BasePart: %s",
			seaRoot:GetFullName()
		))
		return
	end

	disconnectConnection(seaDescendantAddedConnection)
	seaDescendantAddedConnection = seaRoot.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			bindSeaBasePart(descendant)
		end
	end)
end

RemoteEventService:Init()
requestSeaHazardDeathEvent = RemoteEventService:GetEvent("RequestSeaHazardDeath")
if requestSeaHazardDeathEvent then
	requestSeaHazardDeathEvent.OnServerEvent:Connect(onRequestSeaHazardDeath)
end

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
ShopService:Init({
	PlayerDataService = PlayerDataService,
	RemoteEventService = RemoteEventService,
	CurrencyService = CurrencyService,
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
	GMCommandService = GMCommandService,
	SpecialEventService = SpecialEventService,
	RemoteEventService = RemoteEventService,
	WeaponKnockbackService = WeaponKnockbackService,
	ReceiptHandlers = { RebirthService, JetpackService, IdleCoinService, SevenDayLoginRewardService, ShopService },
})
LuckyBlockService:Init({
	PlayerDataService = PlayerDataService,
	BrainrotService = BrainrotService,
	HomeService = HomeService,
	RemoteEventService = RemoteEventService,
})
ShopService:SetBrainrotService(BrainrotService)
ShopService:SetLuckyBlockService(LuckyBlockService)
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
	LaunchPowerService = LaunchPowerService,
	BrainrotService = BrainrotService,
	RemoteEventService = RemoteEventService,
})
LaunchPowerService:Init({
	PlayerDataService = PlayerDataService,
	CurrencyService = CurrencyService,
	RemoteEventService = RemoteEventService,
})
ProgressService:Init({
	HomeService = HomeService,
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
	LuckyBlockService = LuckyBlockService,
})
BrainrotService:SetGMCommandService(GMCommandService)
StudioBossDebugService:Init({
	BrainrotService = BrainrotService,
	RemoteEventService = RemoteEventService,
	GMCommandService = GMCommandService,
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
BrainrotService:SetSpecialEventService(SpecialEventService)
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
bindSeaHazard()

local function onPlayerAdded(player)
	local assignedHome = HomeService:AssignHome(player)
	if not assignedHome then
		player:Kick("当前服务器家园已满（最多 5 人）")
		return
	end

	player.CharacterAdded:Connect(function(character)
		seaHazardTriggerClockByUserId[player.UserId] = nil
		if character then
			beginSeaHazardRespawnGrace(player, character)
		end
	end)

	if player.Character then
		beginSeaHazardRespawnGrace(player, player.Character)
	end

	PlayerDataService:LoadPlayerData(player)
	SettingsService:OnPlayerReady(player)
	GroupRewardService:OnPlayerReady(player)
	PlayerDataService:SetHomeId(player, assignedHome.Name)
	PlayerDataService:SavePlayerData(player, {
		SkipCommitPlaytime = true,
	})
	player:SetAttribute("HomeId", assignedHome.Name)
	WeaponService:OnPlayerReady(player)
	WeaponKnockbackService:OnPlayerReady(player)
	GMCommandService:BindPlayer(player)
	FriendBonusService:OnPlayerReady(player)
	RebirthService:OnPlayerReady(player)
	LaunchPowerService:OnPlayerReady(player)
	ProgressService:OnPlayerReady(player)
	ShopService:OnPlayerReady(player)
	JetpackService:OnPlayerReady(player)
	HomeExpansionService:OnPlayerReady(player, assignedHome)
	BrainrotService:OnPlayerReady(player, assignedHome)
	LuckyBlockService:OnPlayerReady(player)
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
	seaHazardTriggerClockByUserId[player.UserId] = nil
	seaHazardArmedByUserId[player.UserId] = nil
	seaHazardArmTokenByUserId[player.UserId] = nil
	GMCommandService:UnbindPlayer(player)
	WeaponKnockbackService:OnPlayerRemoving(player)
	WeaponService:OnPlayerRemoving(player)
	GlobalLeaderboardService:OnPlayerRemoving(player)
	FriendBonusService:OnPlayerRemoving(player)
	ShopService:OnPlayerRemoving(player)
	BrainrotService:OnPlayerRemoving(player)
	GiftService:OnPlayerRemoving(player)
	HomeExpansionService:OnPlayerRemoving(player, assignedHome)
	RebirthService:OnPlayerRemoving(player)
	LaunchPowerService:OnPlayerRemoving(player)
	ProgressService:OnPlayerRemoving(player)
	JetpackService:OnPlayerRemoving(player)
	LuckyBlockService:OnPlayerRemoving(player)
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
	PlayerDataService:Shutdown()
	runBindToCloseTasks({
		LeaderboardFlush = function()
			return GlobalLeaderboardService:FlushAllPlayers()
		end,
		PlayerDataSave = function()
			return PlayerDataService:SaveAllPlayers()
		end,
	}, 25)
end)
