--[[
脚本名字: BrainrotWorldSpawnCountdownController
脚本文件: BrainrotWorldSpawnCountdownController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/BrainrotWorldSpawnCountdownController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local WORLD_SPAWN_EXPIRE_AT_ATTRIBUTE = "BrainrotWorldSpawnExpireAt"

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
		"[BrainrotWorldSpawnCountdownController] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
		moduleName
	))
end

local GameConfig = requireSharedModule("GameConfig")

local BrainrotWorldSpawnCountdownController = {}
BrainrotWorldSpawnCountdownController.__index = BrainrotWorldSpawnCountdownController

local function formatWorldSpawnCountdownText(remainingSeconds)
	local config = GameConfig.BRAINROT or {}
	local decimals = math.max(0, math.floor(tonumber(config.WorldSpawnCountdownDecimals) or 1))
	local suffix = tostring(config.WorldSpawnCountdownSuffix or "S")
	local safeRemaining = math.max(0, tonumber(remainingSeconds) or 0)
	return string.format("%0." .. tostring(decimals) .. "f%s", safeRemaining, suffix)
end

local function findFirstTextLabelByName(root, nodeName)
	if not root then
		return nil
	end

	local node = root:FindFirstChild(nodeName, true)
	if node and node:IsA("TextLabel") then
		return node
	end

	return nil
end

local function getInfoAttachment(instance)
	if not instance then
		return nil
	end

	local infoAttachmentName = tostring((GameConfig.BRAINROT or {}).InfoAttachmentName or "Info")
	local infoAttachment = instance:FindFirstChild(infoAttachmentName, true)
	if infoAttachment and infoAttachment:IsA("Attachment") then
		return infoAttachment
	end

	return nil
end

local function getSharedServerTimeNow()
	local ok, now = pcall(function()
		return Workspace:GetServerTimeNow()
	end)
	if ok and type(now) == "number" then
		return now
	end

	return math.max(0, tonumber(os.time()) or 0)
end

function BrainrotWorldSpawnCountdownController.new()
	local self = setmetatable({}, BrainrotWorldSpawnCountdownController)
	self._trackedByInstance = {}
	self._updateInterval = math.max(0.1, tonumber((GameConfig.BRAINROT or {}).WorldSpawnCountdownUpdateInterval) or 0.1)
	self._started = false
	return self
end

function BrainrotWorldSpawnCountdownController:_getRuntimeFolder()
	local folderName = tostring((GameConfig.BRAINROT or {}).WorldSpawnRuntimeFolderName or "WorldSpawnedBrainrots")
	local folder = Workspace:FindFirstChild(folderName)
	if folder and folder:IsA("Folder") then
		return folder
	end

	return nil
end

function BrainrotWorldSpawnCountdownController:_isManagedInstance(instance)
	if not (instance and instance.Parent) then
		return false
	end

	if not (instance:IsA("Model") or instance:IsA("BasePart")) then
		return false
	end

	return math.max(0, tonumber(instance:GetAttribute(WORLD_SPAWN_EXPIRE_AT_ATTRIBUTE)) or 0) > 0
end

function BrainrotWorldSpawnCountdownController:_collectManagedInstances()
	local managedInstances = {}
	local seen = {}

	local runtimeFolder = self:_getRuntimeFolder()
	if runtimeFolder then
		for _, child in ipairs(runtimeFolder:GetChildren()) do
			if self:_isManagedInstance(child) and not seen[child] then
				seen[child] = true
				table.insert(managedInstances, child)
			end
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character then
			for _, child in ipairs(character:GetChildren()) do
				if self:_isManagedInstance(child) and not seen[child] then
					seen[child] = true
					table.insert(managedInstances, child)
				end
			end
		end
	end

	return managedInstances, seen
end

function BrainrotWorldSpawnCountdownController:_resolveCountdownUi(instance)
	local infoAttachment = getInfoAttachment(instance)
	if not infoAttachment then
		return nil
	end

	local infoTemplateName = tostring((GameConfig.BRAINROT or {}).InfoTemplateName or "BaseInfo")
	local infoTitleRootName = tostring((GameConfig.BRAINROT or {}).InfoTitleRootName or "Title")
	local infoTimeRootName = tostring((GameConfig.BRAINROT or {}).InfoTimeRootName or "Time")
	local infoTimeLabelName = tostring((GameConfig.BRAINROT or {}).InfoTimeLabelName or "Time")
	local infoGui = infoAttachment:FindFirstChild(infoTemplateName)
	if not (infoGui and infoGui:IsA("BillboardGui")) then
		return nil
	end

	local titleRoot = infoGui:FindFirstChild(infoTitleRootName, true) or infoGui
	local timeRoot = titleRoot:FindFirstChild(infoTimeRootName, true) or infoGui:FindFirstChild(infoTimeRootName, true)
	local timeLabel = findFirstTextLabelByName(timeRoot or titleRoot, infoTimeLabelName) or findFirstTextLabelByName(infoGui, infoTimeLabelName)
	if not timeLabel then
		return nil
	end

	return {
		TimeRoot = timeRoot,
		TimeLabel = timeLabel,
	}
end

function BrainrotWorldSpawnCountdownController:_setCountdownVisible(state, visible)
	if type(state) ~= "table" then
		return
	end

	local timeRoot = state.TimeRoot
	local timeLabel = state.TimeLabel
	if timeRoot and timeRoot:IsA("GuiObject") then
		timeRoot.Visible = visible
	end
	if timeRoot and timeRoot:IsA("LayerCollector") then
		timeRoot.Enabled = visible
	end
	if timeLabel then
		timeLabel.Visible = visible
		if not visible then
			timeLabel.Text = ""
		end
	end
end

function BrainrotWorldSpawnCountdownController:_updateTrackedState(state)
	if type(state) ~= "table" then
		return false
	end

	local instance = state.Instance
	if not self:_isManagedInstance(instance) then
		self:_setCountdownVisible(state, false)
		return false
	end

	if not (state.TimeLabel and state.TimeLabel.Parent) then
		local resolvedState = self:_resolveCountdownUi(instance)
		if not resolvedState then
			return true
		end

		state.TimeRoot = resolvedState.TimeRoot
		state.TimeLabel = resolvedState.TimeLabel
	end

	local expireAt = math.max(0, tonumber(instance:GetAttribute(WORLD_SPAWN_EXPIRE_AT_ATTRIBUTE)) or 0)
	if expireAt <= 0 then
		self:_setCountdownVisible(state, false)
		return false
	end

	self:_setCountdownVisible(state, true)
	state.TimeLabel.Text = formatWorldSpawnCountdownText(expireAt - getSharedServerTimeNow())
	return true
end

function BrainrotWorldSpawnCountdownController:_refreshTrackedInstances()
	local managedInstances, seen = self:_collectManagedInstances()

	for _, instance in ipairs(managedInstances) do
		if not self._trackedByInstance[instance] then
			local resolvedState = self:_resolveCountdownUi(instance) or {}
			resolvedState.Instance = instance
			self._trackedByInstance[instance] = resolvedState
		end
	end

	for instance, state in pairs(self._trackedByInstance) do
		if not seen[instance] then
			self:_setCountdownVisible(state, false)
			self._trackedByInstance[instance] = nil
		elseif not self:_updateTrackedState(state) then
			self._trackedByInstance[instance] = nil
		end
	end
end

function BrainrotWorldSpawnCountdownController:Start()
	if self._started then
		return
	end

	self._started = true
	task.spawn(function()
		self:_refreshTrackedInstances()
		while self._started do
			task.wait(self._updateInterval)
			self:_refreshTrackedInstances()
		end
	end)
end

return BrainrotWorldSpawnCountdownController
