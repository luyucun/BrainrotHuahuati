--[[
脚本名字: SevenDayLoginRewardService
脚本文件: SevenDayLoginRewardService.lua
脚本类型: ModuleScript
Studio放置路径: ServerScriptService/Services/SevenDayLoginRewardService
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
		"[SevenDayLoginRewardService] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
		moduleName
	))
end

local GameConfig = requireSharedModule("GameConfig")

local SevenDayLoginRewardService = {}
SevenDayLoginRewardService._playerDataService = nil
SevenDayLoginRewardService._currencyService = nil
SevenDayLoginRewardService._brainrotService = nil
SevenDayLoginRewardService._stateSyncEvent = nil
SevenDayLoginRewardService._requestStateSyncEvent = nil
SevenDayLoginRewardService._requestClaimEvent = nil
SevenDayLoginRewardService._lastRequestClockByUserId = {}
SevenDayLoginRewardService._didConsumeAutoOpenByUserId = {}

local function getRewardConfig()
	return GameConfig.SEVEN_DAY_LOGIN_REWARD or {}
end

local function getRewardDefinitions()
	local rewards = getRewardConfig().Rewards
	if type(rewards) ~= "table" then
		return {}
	end

	return rewards
end

local function getRewardCount()
	local rewards = getRewardDefinitions()
	if #rewards <= 0 then
		return 7
	end

	return #rewards
end

local function getUnlockAllProductId()
	return math.max(0, math.floor(tonumber(getRewardConfig().DeveloperProductId) or 0))
end

local function getUtcDayKey(timestamp)
	local safeTimestamp = math.max(0, math.floor(tonumber(timestamp) or 0))
	return math.floor(safeTimestamp / 86400)
end

local function getNextUtcTimestamp(timestamp)
	local safeTimestamp = math.max(0, math.floor(tonumber(timestamp) or 0))
	return (getUtcDayKey(safeTimestamp) + 1) * 86400
end

local function normalizeProcessedPurchaseIds(sourceValue)
	local processedPurchaseIds = {}
	if type(sourceValue) ~= "table" then
		return processedPurchaseIds
	end

	for key, value in pairs(sourceValue) do
		local purchaseId = tostring(key or "")
		if purchaseId ~= "" then
			processedPurchaseIds[purchaseId] = math.max(0, math.floor(tonumber(value) or os.time()))
		end
	end

	return processedPurchaseIds
end

local function normalizeDayFlagMap(sourceValue)
	local dayFlags = {}
	local rewardCount = getRewardCount()
	if type(sourceValue) ~= "table" then
		return dayFlags
	end

	for key, value in pairs(sourceValue) do
		local dayIndex = math.max(0, math.floor(tonumber(key) or tonumber(value) or 0))
		if dayIndex >= 1 and dayIndex <= rewardCount and value then
			dayFlags[dayIndex] = true
		end
	end

	return dayFlags
end

local function getNormalizedRewardDefinition(dayIndex)
	local rawDefinition = getRewardDefinitions()[dayIndex]
	local rewardType = "Brainrot"
	local rewardId = 0
	local amount = 1
	local name = ""
	local icon = ""

	if type(rawDefinition) == "table" then
		local rewardTypeText = string.lower(tostring(rawDefinition.RewardType or rawDefinition.Type or rewardType))
		if rewardTypeText == "coin" or rewardTypeText == "coins" then
			rewardType = "Coins"
		end
		rewardId = math.max(0, math.floor(tonumber(rawDefinition.RewardId or rawDefinition.BrainrotId or rawDefinition.Id) or 0))
		amount = math.max(1, math.floor(tonumber(rawDefinition.Amount or rawDefinition.Count) or 1))
		name = tostring(rawDefinition.Name or "")
		icon = tostring(rawDefinition.Icon or "")
	end

	return {
		RewardType = rewardType,
		RewardId = rewardId,
		Amount = amount,
		Name = name,
		Icon = icon,
	}
end

local function countDayFlags(dayFlags)
	local count = 0
	if type(dayFlags) ~= "table" then
		return 0
	end

	for _, isEnabled in pairs(dayFlags) do
		if isEnabled == true then
			count += 1
		end
	end

	return count
end

local function isAllClaimed(rewardState)
	return countDayFlags(rewardState and rewardState.ClaimedDays) >= getRewardCount()
end

local function hasAnyClaimableDay(rewardState)
	if type(rewardState) ~= "table" then
		return false
	end

	for dayIndex = 1, getRewardCount() do
		if rewardState.UnlockedDays[dayIndex] == true and rewardState.ClaimedDays[dayIndex] ~= true then
			return true
		end
	end

	return false
end

local function getFirstClaimableDayIndex(rewardState)
	if type(rewardState) ~= "table" then
		return 0
	end

	for dayIndex = 1, getRewardCount() do
		if rewardState.UnlockedDays[dayIndex] == true and rewardState.ClaimedDays[dayIndex] ~= true then
			return dayIndex
		end
	end

	return 0
end

local function getNextLockedDayIndex(rewardState)
	if type(rewardState) ~= "table" then
		return 0
	end

	for dayIndex = 1, getRewardCount() do
		if rewardState.UnlockedDays[dayIndex] ~= true and rewardState.ClaimedDays[dayIndex] ~= true then
			return dayIndex
		end
	end

	return 0
end

local function startNewCycle(rewardState, nowTimestamp, unlockImmediately)
	local nextCycleId = math.max(0, math.floor(tonumber(rewardState.CycleId) or 0)) + 1
	if nextCycleId <= 0 then
		nextCycleId = 1
	end

	rewardState.CycleId = nextCycleId
	rewardState.UnlockedDays = {}
	rewardState.ClaimedDays = {}
	rewardState.LastClaimAt = 0
	rewardState.LastSequentialUnlockDay = 0
	rewardState.CycleStartUtcDay = getUtcDayKey(nowTimestamp)
	rewardState.CycleStartsLockedUntilNextUtc = unlockImmediately ~= true
	rewardState.PendingCycleReset = false

	if unlockImmediately then
		rewardState.UnlockedDays[1] = true
		rewardState.LastSequentialUnlockDay = 1
	end

	return true
end

local function unlockAllRemainingDays(rewardState)
	local didChange = false
	if type(rewardState) ~= "table" then
		return false
	end

	for dayIndex = 1, getRewardCount() do
		if rewardState.ClaimedDays[dayIndex] ~= true and rewardState.UnlockedDays[dayIndex] ~= true then
			rewardState.UnlockedDays[dayIndex] = true
			didChange = true
		end
	end

	if didChange then
		rewardState.LastSequentialUnlockDay = getRewardCount()
	end

	return didChange
end

local function ensureRewardState(playerData, nowTimestamp)
	if type(playerData) ~= "table" then
		return nil, false
	end

	local didChange = false
	local rewardState = playerData.SevenDayLoginRewardState
	if type(rewardState) ~= "table" then
		rewardState = {}
		playerData.SevenDayLoginRewardState = rewardState
		didChange = true
	end

	rewardState.CycleId = math.max(0, math.floor(tonumber(rewardState.CycleId) or 0))
	rewardState.UnlockedDays = normalizeDayFlagMap(rewardState.UnlockedDays)
	rewardState.ClaimedDays = normalizeDayFlagMap(rewardState.ClaimedDays)
	rewardState.LastClaimAt = math.max(0, math.floor(tonumber(rewardState.LastClaimAt) or 0))
	rewardState.LastSequentialUnlockDay = math.max(0, math.min(getRewardCount(), math.floor(tonumber(rewardState.LastSequentialUnlockDay) or 0)))
	rewardState.CycleStartUtcDay = math.max(0, math.floor(tonumber(rewardState.CycleStartUtcDay) or 0))
	rewardState.CycleStartsLockedUntilNextUtc = rewardState.CycleStartsLockedUntilNextUtc == true
	rewardState.PendingCycleReset = rewardState.PendingCycleReset == true
	rewardState.ProcessedPurchaseIds = normalizeProcessedPurchaseIds(rewardState.ProcessedPurchaseIds)

	if rewardState.CycleId <= 0 then
		startNewCycle(rewardState, nowTimestamp, true)
		didChange = true
	end

	if isAllClaimed(rewardState) and rewardState.PendingCycleReset ~= true then
		rewardState.PendingCycleReset = true
		didChange = true
	end

	return rewardState, didChange
end

local function refreshRewardStateForTime(rewardState, nowTimestamp, options)
	if type(rewardState) ~= "table" then
		return false
	end

	local didChange = false
	local allowCycleReset = type(options) == "table" and options.AllowCycleReset == true
	local currentUtcDay = getUtcDayKey(nowTimestamp)

	if isAllClaimed(rewardState) and rewardState.PendingCycleReset ~= true then
		rewardState.PendingCycleReset = true
		didChange = true
	end

	if rewardState.PendingCycleReset == true then
		if allowCycleReset then
			startNewCycle(rewardState, nowTimestamp, false)
			return true
		end

		return didChange
	end

	if rewardState.CycleStartsLockedUntilNextUtc == true then
		if currentUtcDay > rewardState.CycleStartUtcDay then
			rewardState.CycleStartsLockedUntilNextUtc = false
			rewardState.UnlockedDays[1] = true
			rewardState.LastSequentialUnlockDay = math.max(1, math.floor(tonumber(rewardState.LastSequentialUnlockDay) or 0))
			didChange = true
		else
			return didChange
		end
	end

	if hasAnyClaimableDay(rewardState) then
		return didChange
	end

	local nextDayIndex = getNextLockedDayIndex(rewardState)
	if nextDayIndex <= 0 then
		return didChange
	end

	if nextDayIndex == 1 then
		rewardState.UnlockedDays[1] = true
		rewardState.LastSequentialUnlockDay = math.max(1, math.floor(tonumber(rewardState.LastSequentialUnlockDay) or 0))
		return true
	end

	if rewardState.LastClaimAt > 0 and currentUtcDay > getUtcDayKey(rewardState.LastClaimAt) then
		rewardState.UnlockedDays[nextDayIndex] = true
		rewardState.LastSequentialUnlockDay = math.max(nextDayIndex, math.floor(tonumber(rewardState.LastSequentialUnlockDay) or 0))
		didChange = true
	end

	return didChange
end

local function cloneRewardStateMap(source)
	local clone = {}
	if type(source) ~= "table" then
		return clone
	end

	for key, value in pairs(source) do
		clone[key] = value
	end

	return clone
end

local function snapshotRewardState(rewardState)
	if type(rewardState) ~= "table" then
		return nil
	end

	return {
		CycleId = math.max(0, math.floor(tonumber(rewardState.CycleId) or 0)),
		UnlockedDays = cloneRewardStateMap(rewardState.UnlockedDays),
		ClaimedDays = cloneRewardStateMap(rewardState.ClaimedDays),
		LastClaimAt = math.max(0, math.floor(tonumber(rewardState.LastClaimAt) or 0)),
		LastSequentialUnlockDay = math.max(0, math.floor(tonumber(rewardState.LastSequentialUnlockDay) or 0)),
		CycleStartUtcDay = math.max(0, math.floor(tonumber(rewardState.CycleStartUtcDay) or 0)),
		CycleStartsLockedUntilNextUtc = rewardState.CycleStartsLockedUntilNextUtc == true,
		PendingCycleReset = rewardState.PendingCycleReset == true,
		ProcessedPurchaseIds = cloneRewardStateMap(rewardState.ProcessedPurchaseIds),
	}
end

local function restoreRewardState(rewardState, snapshot)
	if type(rewardState) ~= "table" or type(snapshot) ~= "table" then
		return
	end

	rewardState.CycleId = math.max(0, math.floor(tonumber(snapshot.CycleId) or 0))
	rewardState.UnlockedDays = cloneRewardStateMap(snapshot.UnlockedDays)
	rewardState.ClaimedDays = cloneRewardStateMap(snapshot.ClaimedDays)
	rewardState.LastClaimAt = math.max(0, math.floor(tonumber(snapshot.LastClaimAt) or 0))
	rewardState.LastSequentialUnlockDay = math.max(0, math.floor(tonumber(snapshot.LastSequentialUnlockDay) or 0))
	rewardState.CycleStartUtcDay = math.max(0, math.floor(tonumber(snapshot.CycleStartUtcDay) or 0))
	rewardState.CycleStartsLockedUntilNextUtc = snapshot.CycleStartsLockedUntilNextUtc == true
	rewardState.PendingCycleReset = snapshot.PendingCycleReset == true
	rewardState.ProcessedPurchaseIds = cloneRewardStateMap(snapshot.ProcessedPurchaseIds)
end

function SevenDayLoginRewardService:_savePlayerDataAsync(player)
	if not (self._playerDataService and player) then
		return
	end

	task.spawn(function()
		self._playerDataService:SavePlayerData(player)
	end)
end

function SevenDayLoginRewardService:_getPlayerDataAndState(player, options)
	if not (self._playerDataService and player) then
		return nil, nil, false, 0
	end

	local playerData = self._playerDataService:GetPlayerData(player)
	if type(playerData) ~= "table" then
		return nil, nil, false, 0
	end

	local nowTimestamp = math.max(0, math.floor(tonumber(type(options) == "table" and options.NowTimestamp or 0) or os.time()))
	local rewardState, didChange = ensureRewardState(playerData, nowTimestamp)
	if rewardState then
		didChange = refreshRewardStateForTime(rewardState, nowTimestamp, options) or didChange
	end

	return playerData, rewardState, didChange, nowTimestamp
end

function SevenDayLoginRewardService:_buildStatePayload(player, rewardState, nowTimestamp, options)
	local userId = player and player.UserId or 0
	local consumeAutoOpen = type(options) == "table" and options.ConsumeAutoOpen == true
	local rewards = {}
	for dayIndex = 1, getRewardCount() do
		local rewardDefinition = getNormalizedRewardDefinition(dayIndex)
		local isClaimed = rewardState.ClaimedDays[dayIndex] == true
		local isUnlocked = rewardState.UnlockedDays[dayIndex] == true
		rewards[dayIndex] = {
			dayIndex = dayIndex,
			rewardType = rewardDefinition.RewardType,
			rewardId = rewardDefinition.RewardId,
			amount = rewardDefinition.Amount,
			name = rewardDefinition.Name,
			icon = rewardDefinition.Icon,
			isUnlocked = isUnlocked,
			isClaimed = isClaimed,
			isClaimable = isUnlocked and not isClaimed,
		}
	end

	local hasClaimableReward = hasAnyClaimableDay(rewardState)
	local shouldAutoOpen = hasClaimableReward and self._didConsumeAutoOpenByUserId[userId] ~= true
	if consumeAutoOpen and shouldAutoOpen then
		self._didConsumeAutoOpenByUserId[userId] = true
	end

	local claimedCount = countDayFlags(rewardState.ClaimedDays)
	local remainingRewardCount = math.max(0, getRewardCount() - claimedCount)
	return {
		cycleId = math.max(1, math.floor(tonumber(rewardState.CycleId) or 1)),
		rewards = rewards,
		hasClaimableReward = hasClaimableReward,
		shouldAutoOpen = shouldAutoOpen,
		remainingRewardCount = remainingRewardCount,
		pendingCycleReset = rewardState.PendingCycleReset == true,
		isWaitingForNextCycleDay1 = rewardState.CycleStartsLockedUntilNextUtc == true,
		productId = getUnlockAllProductId(),
		canUnlockAll = getUnlockAllProductId() > 0 and remainingRewardCount > 0,
		nextRefreshAt = getNextUtcTimestamp(nowTimestamp),
		timestamp = os.clock(),
	}
end

function SevenDayLoginRewardService:PushState(player, options)
	if not (player and self._stateSyncEvent) then
		return
	end

	local _playerData, rewardState, didChange, nowTimestamp = self:_getPlayerDataAndState(player, options)
	if not rewardState then
		return
	end

	if didChange and not (type(options) == "table" and options.SkipSave == true) then
		self:_savePlayerDataAsync(player)
	end

	self._stateSyncEvent:FireClient(player, self:_buildStatePayload(player, rewardState, nowTimestamp, options))
end

function SevenDayLoginRewardService:_canProcessRequest(player)
	if not player then
		return false
	end

	local debounceSeconds = math.max(0.05, tonumber(getRewardConfig().RequestDebounceSeconds) or 0.2)
	local userId = player.UserId
	local nowClock = os.clock()
	local lastClock = tonumber(self._lastRequestClockByUserId[userId]) or 0
	if nowClock - lastClock < debounceSeconds then
		return false
	end

	self._lastRequestClockByUserId[userId] = nowClock
	return true
end

function SevenDayLoginRewardService:_grantReward(player, rewardDefinition)
	if type(rewardDefinition) ~= "table" then
		return false, "InvalidReward"
	end

	if rewardDefinition.RewardType == "Coins" then
		if not self._currencyService then
			return false, "MissingCurrencyService"
		end

		local didGrant = select(1, self._currencyService:AddCoins(player, rewardDefinition.Amount, "SevenDayLoginReward"))
		if not didGrant then
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

	for rewardIndex = 1, rewardDefinition.Amount do
		local didGrantReward, grantReason = self._brainrotService:GrantBrainrotInstance(player, rewardDefinition.RewardId, 1, "SevenDayLoginReward")
		if not didGrantReward then
			return false, tostring(grantReason or string.format("GrantFailed_%d", rewardIndex))
		end
	end

	return true, nil
end

function SevenDayLoginRewardService:_handleRequestStateSync(player, payload)
	local reason = type(payload) == "table" and tostring(payload.reason or "") or ""
	local allowCycleReset = type(payload) == "table"
		and (payload.allowCycleReset == true or reason == "Open")
	self:PushState(player, {
		AllowCycleReset = allowCycleReset,
		ConsumeAutoOpen = reason == "Startup",
	})
end

function SevenDayLoginRewardService:_handleRequestClaim(player, payload)
	if not player then
		return
	end

	if not self:_canProcessRequest(player) then
		self:PushState(player)
		return
	end

	local _playerData, rewardState = self:_getPlayerDataAndState(player)
	if not rewardState then
		self:PushState(player)
		return
	end

	local requestedDayIndex = math.max(0, math.floor(tonumber(type(payload) == "table" and payload.dayIndex or 0) or 0))
	if requestedDayIndex <= 0 then
		requestedDayIndex = getFirstClaimableDayIndex(rewardState)
	end

	if requestedDayIndex <= 0 or requestedDayIndex > getRewardCount() then
		self:PushState(player)
		return
	end

	if rewardState.UnlockedDays[requestedDayIndex] ~= true or rewardState.ClaimedDays[requestedDayIndex] == true then
		self:PushState(player)
		return
	end

	local rewardDefinition = getNormalizedRewardDefinition(requestedDayIndex)
	local rewardStateSnapshot = snapshotRewardState(rewardState)
	local previousCoins = self._playerDataService and self._playerDataService:GetCoins(player) or 0
	local brainrotSnapshot = rewardDefinition.RewardType == "Brainrot"
		and self._brainrotService
		and self._brainrotService.CreatePlayerStateSnapshot
		and self._brainrotService:CreatePlayerStateSnapshot(player)
		or nil

	local didGrantReward, grantReason = self:_grantReward(player, rewardDefinition)
	if not didGrantReward then
		if brainrotSnapshot and self._brainrotService and self._brainrotService.RestorePlayerStateSnapshot then
			self._brainrotService:RestorePlayerStateSnapshot(player, brainrotSnapshot)
		end
		warn(string.format(
			"[SevenDayLoginRewardService] ?????? userId=%d day=%d reason=%s",
			player.UserId,
			requestedDayIndex,
			tostring(grantReason)
		))
		self:PushState(player)
		return
	end

	rewardState.ClaimedDays[requestedDayIndex] = true
	rewardState.LastClaimAt = os.time()
	if isAllClaimed(rewardState) then
		rewardState.PendingCycleReset = true
	end

	local didSave = not self._playerDataService or self._playerDataService:SavePlayerData(player)
	if not didSave then
		restoreRewardState(rewardState, rewardStateSnapshot)
		if rewardDefinition.RewardType == "Coins" and self._currencyService then
			local currentCoins = self._playerDataService and self._playerDataService:GetCoins(player) or previousCoins
			local rollbackAmount = math.max(0, currentCoins - previousCoins)
			if rollbackAmount > 0 then
				self._currencyService:AddCoins(player, -rollbackAmount, "SevenDayLoginRewardRollback")
			end
		elseif brainrotSnapshot and self._brainrotService and self._brainrotService.RestorePlayerStateSnapshot then
			self._brainrotService:RestorePlayerStateSnapshot(player, brainrotSnapshot)
		end
		self:PushState(player)
		return
	end

	self._stateSyncEvent:FireClient(player, self:_buildStatePayload(player, rewardState, os.time()))
end

function SevenDayLoginRewardService:Init(dependencies)
	self._playerDataService = dependencies.PlayerDataService
	self._currencyService = dependencies.CurrencyService
	self._brainrotService = dependencies.BrainrotService

	local remoteEventService = dependencies.RemoteEventService
	self._stateSyncEvent = remoteEventService:GetEvent("SevenDayLoginRewardStateSync")
	self._requestStateSyncEvent = remoteEventService:GetEvent("RequestSevenDayLoginRewardStateSync")
	self._requestClaimEvent = remoteEventService:GetEvent("RequestSevenDayLoginRewardClaim")

	if self._requestStateSyncEvent then
		self._requestStateSyncEvent.OnServerEvent:Connect(function(player, payload)
			self:_handleRequestStateSync(player, payload)
		end)
	end

	if self._requestClaimEvent then
		self._requestClaimEvent.OnServerEvent:Connect(function(player, payload)
			self:_handleRequestClaim(player, payload)
		end)
	end
end

function SevenDayLoginRewardService:OnPlayerReady(player)
	if not player then
		return
	end

	self._didConsumeAutoOpenByUserId[player.UserId] = false
	self:PushState(player)
end

function SevenDayLoginRewardService:OnPlayerRemoving(player)
	if not player then
		return
	end

	self._lastRequestClockByUserId[player.UserId] = nil
	self._didConsumeAutoOpenByUserId[player.UserId] = nil
end

function SevenDayLoginRewardService:ProcessReceipt(receiptInfo)
	local productId = math.max(0, math.floor(tonumber(receiptInfo and receiptInfo.ProductId) or 0))
	if productId ~= getUnlockAllProductId() then
		return false, nil
	end

	local player = Players:GetPlayerByUserId(math.max(0, math.floor(tonumber(receiptInfo and receiptInfo.PlayerId) or 0)))
	if not player then
		return true, Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local _playerData, rewardState, didChange, nowTimestamp = self:_getPlayerDataAndState(player, {
		AllowCycleReset = true,
	})
	if not rewardState then
		return true, Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseId = tostring(receiptInfo and receiptInfo.PurchaseId or "")
	local processedPurchaseIds = rewardState.ProcessedPurchaseIds or {}
	if purchaseId ~= "" and processedPurchaseIds[purchaseId] then
		return true, Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local rewardStateSnapshot = snapshotRewardState(rewardState)
	if unlockAllRemainingDays(rewardState) then
		didChange = true
	end

	if purchaseId ~= "" then
		processedPurchaseIds[purchaseId] = os.time()
		rewardState.ProcessedPurchaseIds = processedPurchaseIds
		didChange = true
	end

	if didChange then
		local didSave = not self._playerDataService or self._playerDataService:SavePlayerData(player)
		if not didSave then
			restoreRewardState(rewardState, rewardStateSnapshot)
			self._stateSyncEvent:FireClient(player, self:_buildStatePayload(player, rewardState, nowTimestamp))
			return true, Enum.ProductPurchaseDecision.NotProcessedYet
		end
		self._stateSyncEvent:FireClient(player, self:_buildStatePayload(player, rewardState, nowTimestamp))
	end

	return true, Enum.ProductPurchaseDecision.PurchaseGranted
end

return SevenDayLoginRewardService
