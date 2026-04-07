--[[
Script: StudioBossDebugService
Type: ModuleScript
Studio path: ServerScriptService/Services/StudioBossDebugService
]]

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
		"[StudioBossDebugService] Missing shared module %s",
		moduleName
	))
end

local RemoteNames = requireSharedModule("RemoteNames")

local StudioBossDebugService = {}
StudioBossDebugService._brainrotService = nil
StudioBossDebugService._remoteEventService = nil
StudioBossDebugService._gmCommandService = nil
StudioBossDebugService._requestActionEvent = nil
StudioBossDebugService._feedbackEvent = nil

local function getActionName(payload)
	return type(payload) == "table" and tostring(payload.action or "") or ""
end

local function getGroupId(payload)
	return math.max(0, math.floor(tonumber(type(payload) == "table" and payload.groupId or 0) or 0))
end

local function getRequestedMoveSpeed(payload)
	if type(payload) ~= "table" then
		return nil
	end

	return tonumber(payload.moveSpeed)
end

function StudioBossDebugService:_sendFeedback(player, payload)
	if self._feedbackEvent and player then
		self._feedbackEvent:FireClient(player, payload)
	end
end

function StudioBossDebugService:_canUse(player)
	if not RunService:IsStudio() then
		return false, "NotStudio"
	end

	if not player then
		return false, "InvalidPlayer"
	end

	if self._gmCommandService and player.UserId > 0 and not self._gmCommandService:IsDeveloper(player) then
		return false, "NotAllowed"
	end

	return true
end

function StudioBossDebugService:_handleTeleportToGroup(player, payload)
	local groupId = getGroupId(payload)
	if groupId <= 0 then
		self:_sendFeedback(player, {
			action = "TeleportToGroup",
			status = "InvalidGroupId",
		})
		return
	end

	local success, result = self._brainrotService:TeleportPlayerToWorldSpawnGroup(player, groupId)
	local feedback = {
		action = "TeleportToGroup",
		groupId = groupId,
		status = success and "Success" or tostring(result or "Failed"),
	}

	if success and type(result) == "table" then
		feedback.partName = result.partName
		feedback.bossName = result.bossName
	else
		local groupConfig = self._brainrotService:GetWorldSpawnGroupConfig(groupId)
		if groupConfig then
			feedback.partName = tostring(groupConfig.PartName or "")
			feedback.bossName = self._brainrotService:GetWorldSpawnBossDisplayName(groupId)
		end
	end

	self:_sendFeedback(player, feedback)
end

function StudioBossDebugService:_handleSetBossMoveSpeed(player, payload)
	local groupId = getGroupId(payload)
	if groupId <= 0 then
		self:_sendFeedback(player, {
			action = "SetBossMoveSpeed",
			status = "InvalidGroupId",
		})
		return
	end

	local moveSpeed = getRequestedMoveSpeed(payload)
	if type(moveSpeed) ~= "number" then
		self:_sendFeedback(player, {
			action = "SetBossMoveSpeed",
			groupId = groupId,
			status = "InvalidMoveSpeed",
		})
		return
	end

	local success, result = self._brainrotService:SetWorldSpawnBossMoveSpeed(groupId, moveSpeed)
	local feedback = {
		action = "SetBossMoveSpeed",
		groupId = groupId,
		status = success and "Success" or tostring(result or "Failed"),
	}

	if success and type(result) == "table" then
		feedback.partName = result.partName
		feedback.bossName = result.bossName
		feedback.moveSpeed = result.moveSpeed
		feedback.runtimeReady = result.runtimeReady
	else
		local groupConfig = self._brainrotService:GetWorldSpawnGroupConfig(groupId)
		if groupConfig then
			feedback.partName = tostring(groupConfig.PartName or "")
			feedback.bossName = self._brainrotService:GetWorldSpawnBossDisplayName(groupId)
		end
	end

	self:_sendFeedback(player, feedback)
end

function StudioBossDebugService:_handleRequest(player, payload)
	local canUse, errCode = self:_canUse(player)
	if not canUse then
		self:_sendFeedback(player, {
			action = getActionName(payload),
			groupId = getGroupId(payload),
			status = errCode,
		})
		return
	end

	if not self._brainrotService then
		self:_sendFeedback(player, {
			action = getActionName(payload),
			groupId = getGroupId(payload),
			status = "ServiceNotReady",
		})
		return
	end

	local action = getActionName(payload)
	if action == "TeleportToGroup" then
		self:_handleTeleportToGroup(player, payload)
		return
	end

	if action == "SetBossMoveSpeed" then
		self:_handleSetBossMoveSpeed(player, payload)
		return
	end

	self:_sendFeedback(player, {
		action = action,
		groupId = getGroupId(payload),
		status = "InvalidAction",
	})
end

function StudioBossDebugService:Init(dependencies)
	self._brainrotService = type(dependencies) == "table" and dependencies.BrainrotService or nil
	self._remoteEventService = type(dependencies) == "table" and dependencies.RemoteEventService or nil
	self._gmCommandService = type(dependencies) == "table" and dependencies.GMCommandService or nil
	self._requestActionEvent = self._remoteEventService and self._remoteEventService:GetEvent("RequestStudioBossDebugAction") or nil
	self._feedbackEvent = self._remoteEventService and self._remoteEventService:GetEvent("StudioBossDebugFeedback") or nil

	if self._requestActionEvent then
		self._requestActionEvent.OnServerEvent:Connect(function(player, payload)
			self:_handleRequest(player, payload)
		end)
	end
end

return StudioBossDebugService
