--[[
脚本名字: GroupRewardService
脚本文件: GroupRewardService.lua
脚本类型: ModuleScript
Studio放置路径: ServerScriptService/Services/GroupRewardService
]]

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
		"[GroupRewardService] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
		moduleName
	))
end

local GameConfig = requireSharedModule("GameConfig")

local GroupRewardService = {}
GroupRewardService._playerDataService = nil
GroupRewardService._remoteEventService = nil
GroupRewardService._brainrotService = nil
GroupRewardService._groupRewardStateSyncEvent = nil
GroupRewardService._requestGroupRewardStateSyncEvent = nil
GroupRewardService._requestGroupRewardClaimEvent = nil
GroupRewardService._groupRewardFeedbackEvent = nil
GroupRewardService._lastRequestClockByUserId = {}

local function getRewardConfig()
	return GameConfig.GROUP_REWARD or {}
end

local function getRewardGroupId()
	return math.max(0, math.floor(tonumber(getRewardConfig().GroupId) or 0))
end

local function getRewardBrainrotId()
	return math.max(0, math.floor(tonumber(getRewardConfig().RewardBrainrotId) or 0))
end

local function getRewardCount()
	return math.max(1, math.floor(tonumber(getRewardConfig().RewardCount) or 1))
end

local function ensureGroupRewardState(playerData)
	if type(playerData) ~= "table" then
		return nil
	end

	local rewardState = playerData.GroupRewardState
	if type(rewardState) ~= "table" then
		rewardState = {}
		playerData.GroupRewardState = rewardState
	end

	rewardState.Claimed = rewardState.Claimed == true
	rewardState.ClaimedAt = math.max(0, math.floor(tonumber(rewardState.ClaimedAt) or 0))
	return rewardState
end

function GroupRewardService:_buildStatePayload(player)
	local hasClaimed = false

	if self._playerDataService and player then
		local playerData = self._playerDataService:GetPlayerData(player)
		local rewardState = ensureGroupRewardState(playerData)
		if rewardState then
			hasClaimed = rewardState.Claimed == true
		end
	end

	return {
		hasClaimed = hasClaimed,
		showEntry = hasClaimed ~= true,
		rewardBrainrotId = getRewardBrainrotId(),
		rewardCount = getRewardCount(),
		groupId = getRewardGroupId(),
		timestamp = os.clock(),
	}
end

function GroupRewardService:PushGroupRewardState(player)
	if not (player and self._groupRewardStateSyncEvent) then
		return
	end

	self._groupRewardStateSyncEvent:FireClient(player, self:_buildStatePayload(player))
end

function GroupRewardService:_pushFeedback(player, status, message)
	if not (player and self._groupRewardFeedbackEvent) then
		return
	end

	self._groupRewardFeedbackEvent:FireClient(player, {
		status = tostring(status or "Unknown"),
		message = tostring(message or ""),
		timestamp = os.clock(),
	})
end

function GroupRewardService:_canProcessRequest(player)
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

function GroupRewardService:_savePlayerDataAsync(player)
	if not (self._playerDataService and player) then
		return
	end

	task.spawn(function()
		self._playerDataService:SavePlayerData(player)
	end)
end

function GroupRewardService:_checkPlayerGroupMembership(player)
	local groupId = getRewardGroupId()
	if not player or groupId <= 0 then
		return false, "InvalidGroup"
	end

	local success, isInGroup = pcall(function()
		return player:IsInGroup(groupId)
	end)
	if not success then
		warn(string.format(
			"[GroupRewardService] 群组校验失败 userId=%d groupId=%d err=%s",
			player.UserId,
			groupId,
			tostring(isInGroup)
		))
		return false, "CheckFailed"
	end

	return isInGroup == true, nil
end

function GroupRewardService:_grantReward(player)
	if not self._brainrotService then
		return false, "MissingBrainrotService"
	end

	local rewardBrainrotId = getRewardBrainrotId()
	if rewardBrainrotId <= 0 then
		return false, "InvalidReward"
	end

	local rewardCount = getRewardCount()
	for rewardIndex = 1, rewardCount do
		local didGrant, grantReason = self._brainrotService:GrantBrainrotInstance(player, rewardBrainrotId, 1, "GroupReward")
		if not didGrant then
			return false, tostring(grantReason or string.format("GrantFailed_%d", rewardIndex))
		end
	end

	return true, nil
end

function GroupRewardService:_handleRequestGroupRewardStateSync(player)
	self:PushGroupRewardState(player)
end

function GroupRewardService:_handleRequestGroupRewardClaim(player)
	if not player then
		return
	end

	if not self:_canProcessRequest(player) then
		self:PushGroupRewardState(player)
		self:_pushFeedback(player, "Debounced", "")
		return
	end

	if not self._playerDataService then
		return
	end

	local playerData = self._playerDataService:GetPlayerData(player)
	local rewardState = ensureGroupRewardState(playerData)
	if not rewardState then
		self:PushGroupRewardState(player)
		self:_pushFeedback(player, "MissingData", "")
		return
	end

	if rewardState.Claimed == true then
		self:PushGroupRewardState(player)
		self:_pushFeedback(player, "AlreadyClaimed", "")
		return
	end

	local isInGroup, groupError = self:_checkPlayerGroupMembership(player)
	if not isInGroup then
		self:PushGroupRewardState(player)
		if groupError == "CheckFailed" then
			self:_pushFeedback(
				player,
				"CheckFailed",
				tostring(getRewardConfig().VerifyFailedTipText or "Unable to verify group membership. Try again.")
			)
		else
			self:_pushFeedback(
				player,
				"NotInGroup",
				tostring(getRewardConfig().RequirementTipText or "Join the group for rewards!")
			)
		end
		return
	end

	local didGrantReward, grantReason = self:_grantReward(player)
	if not didGrantReward then
		warn(string.format(
			"[GroupRewardService] 奖励发放失败 userId=%d reason=%s",
			player.UserId,
			tostring(grantReason)
		))
		self:PushGroupRewardState(player)
		self:_pushFeedback(player, "GrantFailed", "")
		return
	end

	rewardState.Claimed = true
	rewardState.ClaimedAt = os.time()

	self:PushGroupRewardState(player)
	self:_pushFeedback(
		player,
		"Success",
		tostring(getRewardConfig().SuccessTipText or "Claim Successful!")
	)
	self:_savePlayerDataAsync(player)
end

function GroupRewardService:Init(dependencies)
	self._playerDataService = dependencies.PlayerDataService
	self._remoteEventService = dependencies.RemoteEventService
	self._brainrotService = dependencies.BrainrotService

	self._groupRewardStateSyncEvent = self._remoteEventService:GetEvent("GroupRewardStateSync")
	self._requestGroupRewardStateSyncEvent = self._remoteEventService:GetEvent("RequestGroupRewardStateSync")
	self._requestGroupRewardClaimEvent = self._remoteEventService:GetEvent("RequestGroupRewardClaim")
	self._groupRewardFeedbackEvent = self._remoteEventService:GetEvent("GroupRewardFeedback")

	if self._requestGroupRewardStateSyncEvent then
		self._requestGroupRewardStateSyncEvent.OnServerEvent:Connect(function(player)
			self:_handleRequestGroupRewardStateSync(player)
		end)
	end

	if self._requestGroupRewardClaimEvent then
		self._requestGroupRewardClaimEvent.OnServerEvent:Connect(function(player)
			self:_handleRequestGroupRewardClaim(player)
		end)
	end
end

function GroupRewardService:OnPlayerReady(player)
	if not (self._playerDataService and player) then
		return
	end

	local playerData = self._playerDataService:GetPlayerData(player)
	ensureGroupRewardState(playerData)
	self:PushGroupRewardState(player)
end

function GroupRewardService:OnPlayerRemoving(player)
	if not player then
		return
	end

	self._lastRequestClockByUserId[player.UserId] = nil
end

return GroupRewardService
