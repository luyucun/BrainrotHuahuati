--[[
脚本名字: StarterPackService
脚本文件: StarterPackService.lua
脚本类型: ModuleScript
Studio放置路径: ServerScriptService/Services/StarterPackService
]]

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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
		"[StarterPackService] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
		moduleName
	))
end

local GameConfig = requireSharedModule("GameConfig")

local StarterPackService = {}
StarterPackService._playerDataService = nil
StarterPackService._remoteEventService = nil
StarterPackService._currencyService = nil
StarterPackService._brainrotService = nil
StarterPackService._stateSyncEvent = nil
StarterPackService._requestStateSyncEvent = nil
StarterPackService._lastRequestClockByUserId = {}
StarterPackService._lastOwnershipCheckClockByUserId = {}
StarterPackService._pendingSuccessTokenByUserId = {}
StarterPackService._studioForceShowEntryByUserId = {}

local STUDIO_FORCE_SHOW_ENTRY_ATTRIBUTE = "StarterPackStudioForceShowEntry"

local function getStarterPackConfig()
	return GameConfig.STARTER_PACK or {}
end

local function getGamePassId()
	return math.max(0, math.floor(tonumber(getStarterPackConfig().GamePassId) or 0))
end

local function getRewardDefinitions()
	local rewards = getStarterPackConfig().Rewards
	if type(rewards) ~= "table" then
		return {}
	end

	return rewards
end

local function getRewardCount()
	return #getRewardDefinitions()
end

local function getRequestDebounceSeconds()
	return math.max(0.05, tonumber(getStarterPackConfig().RequestDebounceSeconds) or 0.2)
end

local function getOwnershipRefreshCooldownSeconds()
	return math.max(0.1, tonumber(getStarterPackConfig().OwnershipRefreshCooldownSeconds) or 0.75)
end

local function normalizeGrantedRewardIndexes(sourceValue)
	local grantedRewardIndexes = {}
	if type(sourceValue) ~= "table" then
		return grantedRewardIndexes
	end

	for key, value in pairs(sourceValue) do
		local rewardIndex = math.max(0, math.floor(tonumber(key) or tonumber(value) or 0))
		if rewardIndex >= 1 and rewardIndex <= getRewardCount() and value then
			grantedRewardIndexes[rewardIndex] = true
		end
	end

	return grantedRewardIndexes
end

local function countGrantedRewardIndexes(grantedRewardIndexes)
	local count = 0
	if type(grantedRewardIndexes) ~= "table" then
		return 0
	end

	for _, isGranted in pairs(grantedRewardIndexes) do
		if isGranted == true then
			count += 1
		end
	end

	return count
end

local function getNormalizedRewardDefinition(rewardIndex)
	local rawDefinition = getRewardDefinitions()[rewardIndex]
	local rewardType = "Brainrot"
	local rewardId = 0
	local amount = 1

	if type(rawDefinition) == "table" then
		local rewardTypeText = string.lower(tostring(rawDefinition.RewardType or rawDefinition.Type or rewardType))
		if rewardTypeText == "coin" or rewardTypeText == "coins" then
			rewardType = "Coins"
		end

		rewardId = math.max(0, math.floor(tonumber(rawDefinition.RewardId or rawDefinition.BrainrotId or rawDefinition.Id) or 0))
		amount = math.max(1, math.floor(tonumber(rawDefinition.Amount or rawDefinition.Count) or 1))
	end

	return {
		RewardType = rewardType,
		RewardId = rewardId,
		Amount = amount,
	}
end

local function ensureStarterPackState(playerData)
	if type(playerData) ~= "table" then
		return nil, false
	end

	local didChange = false
	local starterPackState = playerData.StarterPackState
	if type(starterPackState) ~= "table" then
		starterPackState = {}
		playerData.StarterPackState = starterPackState
		didChange = true
	end

	starterPackState.Owned = starterPackState.Owned == true or starterPackState.Granted == true
	starterPackState.Granted = starterPackState.Granted == true
	starterPackState.GrantedAt = math.max(0, math.floor(tonumber(starterPackState.GrantedAt) or 0))
	starterPackState.GrantedRewardIndexes = normalizeGrantedRewardIndexes(starterPackState.GrantedRewardIndexes)

	if getRewardCount() > 0 and starterPackState.Granted == true then
		if countGrantedRewardIndexes(starterPackState.GrantedRewardIndexes) < getRewardCount() then
			for rewardIndex = 1, getRewardCount() do
				starterPackState.GrantedRewardIndexes[rewardIndex] = true
			end
			didChange = true
		end
	end

	if getRewardCount() > 0 and countGrantedRewardIndexes(starterPackState.GrantedRewardIndexes) >= getRewardCount() then
		if starterPackState.Granted ~= true then
			starterPackState.Granted = true
			didChange = true
		end
		if starterPackState.Owned ~= true then
			starterPackState.Owned = true
			didChange = true
		end
	end

	return starterPackState, didChange
end

function StarterPackService:_savePlayerDataAsync(player)
	if not (self._playerDataService and player) then
		return
	end

	task.spawn(function()
		self._playerDataService:SavePlayerData(player)
	end)
end

function StarterPackService:IsStudioForceShowEntryEnabled(player)
	if not (player and RunService:IsStudio()) then
		return false
	end

	return self._studioForceShowEntryByUserId[player.UserId] == true
end

function StarterPackService:SetStudioForceShowEntry(player, enabled)
	if not player then
		return false
	end

	local resolvedEnabled = enabled == true and RunService:IsStudio()
	if resolvedEnabled then
		self._studioForceShowEntryByUserId[player.UserId] = true
	else
		self._studioForceShowEntryByUserId[player.UserId] = nil
	end

	pcall(function()
		player:SetAttribute(STUDIO_FORCE_SHOW_ENTRY_ATTRIBUTE, resolvedEnabled)
	end)

	self:PushState(player, {
		SkipSave = true,
	})

	return resolvedEnabled
end

function StarterPackService:_canProcessRequest(player)
	if not player then
		return false
	end

	local nowClock = os.clock()
	local lastClock = tonumber(self._lastRequestClockByUserId[player.UserId]) or 0
	if nowClock - lastClock < getRequestDebounceSeconds() then
		return false
	end

	self._lastRequestClockByUserId[player.UserId] = nowClock
	return true
end

function StarterPackService:_refreshOwnership(player, starterPackState, forceRefresh)
	if not (player and starterPackState) then
		return false
	end

	local passId = getGamePassId()
	if passId <= 0 then
		return false
	end

	local nowClock = os.clock()
	local lastCheckClock = tonumber(self._lastOwnershipCheckClockByUserId[player.UserId]) or 0
	if forceRefresh ~= true and nowClock - lastCheckClock < getOwnershipRefreshCooldownSeconds() then
		return false
	end

	if forceRefresh ~= true and starterPackState.Owned == true then
		return false
	end

	self._lastOwnershipCheckClockByUserId[player.UserId] = nowClock
	local success, ownsGamePass = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
	end)

	if not success then
		warn(string.format(
			"[StarterPackService] 通行证拥有状态校验失败 userId=%d gamePassId=%d err=%s",
			player.UserId,
			passId,
			tostring(ownsGamePass)
		))
		return false
	end

	if ownsGamePass == true and starterPackState.Owned ~= true then
		starterPackState.Owned = true
		return true
	end

	return false
end

function StarterPackService:_grantReward(player, rewardDefinition)
	if type(rewardDefinition) ~= "table" then
		return false, "InvalidReward"
	end

	if rewardDefinition.RewardType == "Coins" then
		if not self._currencyService then
			return false, "MissingCurrencyService"
		end

		local didGrantCoins = nil
		local _nextCoins = nil
		didGrantCoins, _nextCoins = self._currencyService:AddCoins(player, rewardDefinition.Amount, "StarterPack")
		if didGrantCoins ~= true then
			return false, "GrantCoinsFailed"
		end

		return true, nil
	end

	if rewardDefinition.RewardType ~= "Brainrot" then
		return false, "UnsupportedRewardType"
	end

	if not self._brainrotService then
		return false, "MissingBrainrotService"
	end

	if rewardDefinition.RewardId <= 0 then
		return false, "InvalidRewardId"
	end

	for _ = 1, rewardDefinition.Amount do
		local didGrantBrainrot, grantReason = self._brainrotService:GrantBrainrotInstance(player, rewardDefinition.RewardId, 1, "StarterPack")
		if didGrantBrainrot ~= true then
			return false, tostring(grantReason or "GrantFailed")
		end
	end

	return true, nil
end

function StarterPackService:_grantPendingRewards(player, starterPackState)
	if not starterPackState then
		return false
	end

	local didChange = false
	for rewardIndex = 1, getRewardCount() do
		if starterPackState.GrantedRewardIndexes[rewardIndex] ~= true then
			local didGrantReward, grantReason = self:_grantReward(player, getNormalizedRewardDefinition(rewardIndex))
			if didGrantReward ~= true then
				warn(string.format(
					"[StarterPackService] 新手礼包奖励发放失败 userId=%d rewardIndex=%d reason=%s",
					player.UserId,
					rewardIndex,
					tostring(grantReason)
				))
				return didChange
			end

			starterPackState.GrantedRewardIndexes[rewardIndex] = true
			didChange = true
		end
	end

	if getRewardCount() > 0 and countGrantedRewardIndexes(starterPackState.GrantedRewardIndexes) >= getRewardCount() then
		if starterPackState.Granted ~= true then
			starterPackState.Granted = true
			starterPackState.Owned = true
			starterPackState.GrantedAt = os.time()
			self._pendingSuccessTokenByUserId[player.UserId] = starterPackState.GrantedAt
			didChange = true
		end
	end

	return didChange
end

function StarterPackService:_refreshState(player, options)
	if not (self._playerDataService and player) then
		return nil, nil, false
	end

	local playerData = self._playerDataService:GetPlayerData(player)
	if type(playerData) ~= "table" then
		return nil, nil, false
	end

	local starterPackState, didChange = ensureStarterPackState(playerData)
	if not starterPackState then
		return playerData, nil, didChange
	end

	local forceOwnershipRefresh = type(options) == "table" and options.ForceOwnershipRefresh == true
	if self:_refreshOwnership(player, starterPackState, forceOwnershipRefresh) then
		didChange = true
	end

	if starterPackState.Owned == true and starterPackState.Granted ~= true then
		if self:_grantPendingRewards(player, starterPackState) then
			didChange = true
		end
	end

	return playerData, starterPackState, didChange
end

function StarterPackService:_buildStatePayload(player, starterPackState)
	local userId = player and player.UserId or 0
	local successToken = math.max(0, math.floor(tonumber(self._pendingSuccessTokenByUserId[userId]) or 0))
	local shouldForceShowEntry = self:IsStudioForceShowEntryEnabled(player)

	return {
		showEntry = getGamePassId() > 0
			and (
				shouldForceShowEntry
				or (starterPackState and starterPackState.Owned ~= true and starterPackState.Granted ~= true)
			),
		isOwned = starterPackState and starterPackState.Owned == true or false,
		hasGranted = starterPackState and starterPackState.Granted == true or false,
		gamePassId = getGamePassId(),
		shouldShowClaimSuccess = successToken > 0,
		successToken = successToken,
		timestamp = os.clock(),
	}
end

function StarterPackService:PushState(player, options)
	if not (player and self._stateSyncEvent) then
		return
	end

	local _playerData, starterPackState, didChange = self:_refreshState(player, options)
	if not starterPackState then
		return
	end

	if didChange and not (type(options) == "table" and options.SkipSave == true) then
		self:_savePlayerDataAsync(player)
	end

	local payload = self:_buildStatePayload(player, starterPackState)
	self._stateSyncEvent:FireClient(player, payload)

	if type(options) == "table" and options.ConsumePendingSuccess == true and payload.shouldShowClaimSuccess == true then
		self._pendingSuccessTokenByUserId[player.UserId] = nil
	end
end

function StarterPackService:Init(dependencies)
	self._playerDataService = dependencies.PlayerDataService
	self._remoteEventService = dependencies.RemoteEventService
	self._currencyService = dependencies.CurrencyService
	self._brainrotService = dependencies.BrainrotService
	self._stateSyncEvent = self._remoteEventService:GetEvent("StarterPackStateSync")
	self._requestStateSyncEvent = self._remoteEventService:GetEvent("RequestStarterPackStateSync")

	if self._requestStateSyncEvent then
		self._requestStateSyncEvent.OnServerEvent:Connect(function(player, payload)
			if not self:_canProcessRequest(player) then
				self:PushState(player)
				return
			end

			local reason = type(payload) == "table" and tostring(payload.reason or "") or ""
			self:PushState(player, {
				ForceOwnershipRefresh = type(payload) == "table" and payload.forceOwnershipRefresh == true,
				ConsumePendingSuccess = (type(payload) == "table" and payload.consumePendingSuccess == true)
					or reason == "Startup"
					or reason == "PurchaseFinished",
			})
		end)
	end
end

function StarterPackService:OnPlayerReady(player)
	self:PushState(player, {
		ForceOwnershipRefresh = true,
	})
end

function StarterPackService:OnPlayerRemoving(player)
	if not player then
		return
	end

	self._lastRequestClockByUserId[player.UserId] = nil
	self._lastOwnershipCheckClockByUserId[player.UserId] = nil
	self._pendingSuccessTokenByUserId[player.UserId] = nil
	self._studioForceShowEntryByUserId[player.UserId] = nil
end

return StarterPackService
