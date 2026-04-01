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
		"[IdleCoinService] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
		moduleName
	))
end

local GameConfig = requireSharedModule("GameConfig")

local IdleCoinService = {}
IdleCoinService._playerDataService = nil
IdleCoinService._brainrotService = nil
IdleCoinService._idleCoinStateSyncEvent = nil
IdleCoinService._requestIdleCoinStateSyncEvent = nil
IdleCoinService._requestIdleCoinClaimEvent = nil
IdleCoinService._requestIdleCoinClaim10PurchaseEvent = nil
IdleCoinService._promptIdleCoinClaim10PurchaseEvent = nil
IdleCoinService._requestIdleCoinClaim10PurchaseClosedEvent = nil
IdleCoinService._idleCoinFeedbackEvent = nil
IdleCoinService._claimCashFeedbackEvent = nil
IdleCoinService._lastRequestClockByUserId = {}
IdleCoinService._didConsumeAutoOpenByUserId = {}
IdleCoinService._pendingPurchaseByUserId = {}
IdleCoinService._purchaseSerialByUserId = {}

local function getIdleCoinConfig()
	return GameConfig.IDLE_COIN or {}
end

local function getIdleCoinProductId()
	return math.max(0, math.floor(tonumber(getIdleCoinConfig().DeveloperProductId) or 0))
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

local function ensureIdleCoinState(playerData)
	if type(playerData) ~= "table" then
		return nil
	end

	local idleCoinState = playerData.IdleCoinState
	if type(idleCoinState) ~= "table" then
		idleCoinState = {}
		playerData.IdleCoinState = idleCoinState
	end

	idleCoinState.ProcessedPurchaseIds = normalizeProcessedPurchaseIds(idleCoinState.ProcessedPurchaseIds)
	return idleCoinState
end

function IdleCoinService:_getPlayerDataAndState(player)
	if not (self._playerDataService and player) then
		return nil, nil
	end

	local playerData = self._playerDataService:GetPlayerData(player)
	if type(playerData) ~= "table" then
		return nil, nil
	end

	return playerData, ensureIdleCoinState(playerData)
end

function IdleCoinService:_getTotalIdleCoin(player)
	if not (self._brainrotService and player) then
		return 0
	end

	return math.max(0, tonumber(self._brainrotService:GetTotalOfflineGold(player)) or 0)
end

function IdleCoinService:_buildStatePayload(player, options)
	local userId = player and player.UserId or 0
	local consumeAutoOpen = type(options) == "table" and options.ConsumeAutoOpen == true
	local idleCoins = self:_getTotalIdleCoin(player)
	local shouldAutoOpen = idleCoins >= 1 and self._didConsumeAutoOpenByUserId[userId] ~= true
	if consumeAutoOpen and shouldAutoOpen then
		self._didConsumeAutoOpenByUserId[userId] = true
	end

	return {
		idleCoins = idleCoins,
		claim10Coins = idleCoins * 10,
		canClaim = idleCoins >= 1,
		shouldAutoOpen = shouldAutoOpen,
		productId = getIdleCoinProductId(),
		isPurchasePending = self._pendingPurchaseByUserId[userId] ~= nil,
		timestamp = os.clock(),
	}
end

function IdleCoinService:PushIdleCoinState(player, options)
	if not (player and self._idleCoinStateSyncEvent) then
		return
	end

	self._idleCoinStateSyncEvent:FireClient(player, self:_buildStatePayload(player, options))
end

function IdleCoinService:_pushFeedback(player, status, extraPayload)
	if not (player and self._idleCoinFeedbackEvent) then
		return
	end

	local payload = type(extraPayload) == "table" and extraPayload or {}
	payload.status = tostring(status or "Unknown")
	payload.timestamp = os.clock()
	self._idleCoinFeedbackEvent:FireClient(player, payload)
end
function IdleCoinService:_pushClaimCashFeedback(player)
	if not (player and self._claimCashFeedbackEvent) then
		return
	end

	self._claimCashFeedbackEvent:FireClient(player, {
		source = "IdleCoin",
		timestamp = os.clock(),
	})
end

function IdleCoinService:_savePlayerDataAsync(player)
	if not (self._playerDataService and player) then
		return
	end

	task.spawn(function()
		self._playerDataService:SavePlayerData(player)
	end)
end

function IdleCoinService:_canProcessRequest(player)
	if not player then
		return false
	end

	local debounceSeconds = math.max(0.05, tonumber(getIdleCoinConfig().RequestDebounceSeconds) or 0.2)
	local userId = player.UserId
	local nowClock = os.clock()
	local lastClock = tonumber(self._lastRequestClockByUserId[userId]) or 0
	if nowClock - lastClock < debounceSeconds then
		return false
	end

	self._lastRequestClockByUserId[userId] = nowClock
	return true
end

function IdleCoinService:_nextPurchaseRequestId(player)
	local userId = player and player.UserId or 0
	local nextSerial = (tonumber(self._purchaseSerialByUserId[userId]) or 0) + 1
	self._purchaseSerialByUserId[userId] = nextSerial
	return string.format("%d:%d", userId, nextSerial)
end

function IdleCoinService:_handleRequestIdleCoinStateSync(player)
	self:PushIdleCoinState(player, {
		ConsumeAutoOpen = true,
	})
end

function IdleCoinService:_handleRequestIdleCoinClaim(player)
	if not player then
		return
	end

	if self._pendingPurchaseByUserId[player.UserId] then
		self:PushIdleCoinState(player)
		self:_pushFeedback(player, "PurchasePending")
		return
	end

	if not self:_canProcessRequest(player) then
		self:PushIdleCoinState(player)
		self:_pushFeedback(player, "Debounced")
		return
	end

	if not self._brainrotService then
		self:PushIdleCoinState(player)
		self:_pushFeedback(player, "MissingBrainrotService")
		return
	end

	local didClaim, baseIdleCoins, grantedCoins = self._brainrotService:ClaimAllOfflineGold(player, 1, "IdleCoinClaim")
	if not didClaim then
		self:PushIdleCoinState(player)
		if math.max(0, tonumber(baseIdleCoins) or 0) < 1 then
			self:_pushFeedback(player, "NoIdleCoin")
		else
			self:_pushFeedback(player, "ClaimFailed")
		end
		return
	end

	self:_pushClaimCashFeedback(player)
	self:PushIdleCoinState(player)
	self:_pushFeedback(player, "Success", {
		claimType = "Claim",
		multiplier = 1,
		baseIdleCoins = math.max(0, tonumber(baseIdleCoins) or 0),
		grantedCoins = math.max(0, tonumber(grantedCoins) or 0),
	})
	self:_savePlayerDataAsync(player)
end

function IdleCoinService:_handleRequestIdleCoinClaim10Purchase(player)
	if not player then
		return
	end

	if self._pendingPurchaseByUserId[player.UserId] then
		self:PushIdleCoinState(player)
		self:_pushFeedback(player, "PurchasePending")
		return
	end

	if not self:_canProcessRequest(player) then
		self:PushIdleCoinState(player)
		self:_pushFeedback(player, "Debounced")
		return
	end

	local idleCoins = self:_getTotalIdleCoin(player)
	if idleCoins < 1 then
		self:PushIdleCoinState(player)
		self:_pushFeedback(player, "NoIdleCoin")
		return
	end

	local productId = getIdleCoinProductId()
	if productId <= 0 then
		self:PushIdleCoinState(player)
		self:_pushFeedback(player, "InvalidProduct")
		return
	end

	if not self._promptIdleCoinClaim10PurchaseEvent then
		self:PushIdleCoinState(player)
		self:_pushFeedback(player, "MissingPromptEvent")
		return
	end
	local requestId = self:_nextPurchaseRequestId(player)
	self._pendingPurchaseByUserId[player.UserId] = {
		requestId = requestId,
		productId = productId,
		createdAt = os.clock(),
	}

	self._promptIdleCoinClaim10PurchaseEvent:FireClient(player, {
		requestId = requestId,
		productId = productId,
		idleCoins = idleCoins,
		timestamp = os.clock(),
	})
	self:PushIdleCoinState(player)
end

function IdleCoinService:_handleRequestIdleCoinClaim10PurchaseClosed(player, payload)
	if not player then
		return
	end

	local pendingPurchase = self._pendingPurchaseByUserId[player.UserId]
	if type(pendingPurchase) ~= "table" then
		return
	end

	local requestId = type(payload) == "table" and tostring(payload.requestId or "") or ""
	local productId = math.max(0, math.floor(tonumber(type(payload) == "table" and payload.productId or 0) or 0))
	if requestId ~= tostring(pendingPurchase.requestId or "") or productId ~= math.max(0, math.floor(tonumber(pendingPurchase.productId) or 0)) then
		return
	end

	if type(payload) == "table" and payload.isPurchased == true then
		self:PushIdleCoinState(player)
		return
	end

	self._pendingPurchaseByUserId[player.UserId] = nil
	self:PushIdleCoinState(player)
	if type(payload) == "table" and tostring(payload.status or "") == "PromptFailed" then
		self:_pushFeedback(player, "PromptFailed")
	end
end

function IdleCoinService:Init(dependencies)
	self._playerDataService = dependencies.PlayerDataService
	self._brainrotService = dependencies.BrainrotService

	local remoteEventService = dependencies.RemoteEventService
	self._idleCoinStateSyncEvent = remoteEventService:GetEvent("IdleCoinStateSync")
	self._requestIdleCoinStateSyncEvent = remoteEventService:GetEvent("RequestIdleCoinStateSync")
	self._requestIdleCoinClaimEvent = remoteEventService:GetEvent("RequestIdleCoinClaim")
	self._requestIdleCoinClaim10PurchaseEvent = remoteEventService:GetEvent("RequestIdleCoinClaim10Purchase")
	self._promptIdleCoinClaim10PurchaseEvent = remoteEventService:GetEvent("PromptIdleCoinClaim10Purchase")
	self._requestIdleCoinClaim10PurchaseClosedEvent = remoteEventService:GetEvent("RequestIdleCoinClaim10PurchaseClosed")
	self._idleCoinFeedbackEvent = remoteEventService:GetEvent("IdleCoinFeedback")
	self._claimCashFeedbackEvent = remoteEventService:GetEvent("ClaimCashFeedback")

	if self._requestIdleCoinStateSyncEvent then
		self._requestIdleCoinStateSyncEvent.OnServerEvent:Connect(function(player)
			self:_handleRequestIdleCoinStateSync(player)
		end)
	end

	if self._requestIdleCoinClaimEvent then
		self._requestIdleCoinClaimEvent.OnServerEvent:Connect(function(player)
			self:_handleRequestIdleCoinClaim(player)
		end)
	end

	if self._requestIdleCoinClaim10PurchaseEvent then
		self._requestIdleCoinClaim10PurchaseEvent.OnServerEvent:Connect(function(player)
			self:_handleRequestIdleCoinClaim10Purchase(player)
		end)
	end

	if self._requestIdleCoinClaim10PurchaseClosedEvent then
		self._requestIdleCoinClaim10PurchaseClosedEvent.OnServerEvent:Connect(function(player, payload)
			self:_handleRequestIdleCoinClaim10PurchaseClosed(player, payload)
		end)
	end
end

function IdleCoinService:OnPlayerReady(player)
	local _playerData, idleCoinState = self:_getPlayerDataAndState(player)
	if not idleCoinState then
		return
	end

	self._didConsumeAutoOpenByUserId[player.UserId] = false
	self._pendingPurchaseByUserId[player.UserId] = nil
	self._purchaseSerialByUserId[player.UserId] = 0
	self:PushIdleCoinState(player)
end

function IdleCoinService:OnPlayerRemoving(player)
	if not player then
		return
	end

	local userId = player.UserId
	self._lastRequestClockByUserId[userId] = nil
	self._didConsumeAutoOpenByUserId[userId] = nil
	self._pendingPurchaseByUserId[userId] = nil
	self._purchaseSerialByUserId[userId] = nil
end
function IdleCoinService:ProcessReceipt(receiptInfo)
	local productId = math.max(0, math.floor(tonumber(receiptInfo and receiptInfo.ProductId) or 0))
	if productId ~= getIdleCoinProductId() then
		return false, nil
	end

	local player = Players:GetPlayerByUserId(math.max(0, math.floor(tonumber(receiptInfo and receiptInfo.PlayerId) or 0)))
	if not player then
		return true, Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local _playerData, idleCoinState = self:_getPlayerDataAndState(player)
	if not idleCoinState then
		return true, Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseId = tostring(receiptInfo and receiptInfo.PurchaseId or "")
	local processedPurchaseIds = idleCoinState.ProcessedPurchaseIds or {}
	if purchaseId ~= "" and processedPurchaseIds[purchaseId] then
		return true, Enum.ProductPurchaseDecision.PurchaseGranted
	end

	if not self._brainrotService then
		return true, Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local didClaim, baseIdleCoins, grantedCoins = self._brainrotService:ClaimAllOfflineGold(player, 10, "IdleCoinClaim10")
	local safeBaseIdleCoins = math.max(0, tonumber(baseIdleCoins) or 0)
	local safeGrantedCoins = math.max(0, tonumber(grantedCoins) or 0)
	if not didClaim and safeBaseIdleCoins >= 1 then
		return true, Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if purchaseId ~= "" then
		processedPurchaseIds[purchaseId] = os.time()
	end
	idleCoinState.ProcessedPurchaseIds = processedPurchaseIds
	self._pendingPurchaseByUserId[player.UserId] = nil

	if didClaim then
		self:_pushClaimCashFeedback(player)
	end

	self:PushIdleCoinState(player)
	self:_pushFeedback(player, "Success", {
		claimType = "Claim10",
		multiplier = 10,
		baseIdleCoins = safeBaseIdleCoins,
		grantedCoins = safeGrantedCoins,
	})
	self:_savePlayerDataAsync(player)
	return true, Enum.ProductPurchaseDecision.PurchaseGranted
end

return IdleCoinService