--[[
脚本名字: SettingsService
脚本文件: SettingsService.lua
脚本类型: ModuleScript
Studio放置路径: ServerScriptService/Services/SettingsService
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
		"[SettingsService] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
		moduleName
	))
end

local GameConfig = requireSharedModule("GameConfig")

local SettingsService = {}
SettingsService._playerDataService = nil
SettingsService._settingsStateSyncEvent = nil
SettingsService._requestSettingsStateSyncEvent = nil
SettingsService._requestSettingsUpdateEvent = nil
SettingsService._lastRequestClockByUserId = {}

local function getDefaultMusicEnabled()
	return ((GameConfig.SETTINGS or {}).DefaultMusicEnabled) ~= false
end

local function getDefaultSfxEnabled()
	return ((GameConfig.SETTINGS or {}).DefaultSfxEnabled) ~= false
end

local function ensureSettingsState(playerData)
	if type(playerData) ~= "table" then
		return nil
	end

	local settingsState = playerData.SettingsState
	if type(settingsState) ~= "table" then
		settingsState = {}
		playerData.SettingsState = settingsState
	end

	if settingsState.MusicEnabled == nil then
		settingsState.MusicEnabled = getDefaultMusicEnabled()
	else
		settingsState.MusicEnabled = settingsState.MusicEnabled == true
	end

	if settingsState.SfxEnabled == nil then
		settingsState.SfxEnabled = getDefaultSfxEnabled()
	else
		settingsState.SfxEnabled = settingsState.SfxEnabled == true
	end

	return settingsState
end

function SettingsService:_buildStatePayload(player)
	local musicEnabled = getDefaultMusicEnabled()
	local sfxEnabled = getDefaultSfxEnabled()

	if self._playerDataService and player then
		local playerData = self._playerDataService:GetPlayerData(player)
		local settingsState = ensureSettingsState(playerData)
		if settingsState then
			musicEnabled = settingsState.MusicEnabled == true
			sfxEnabled = settingsState.SfxEnabled == true
		end
	end

	return {
		musicEnabled = musicEnabled,
		sfxEnabled = sfxEnabled,
		timestamp = os.clock(),
	}
end

function SettingsService:PushSettingsState(player)
	if not (player and self._settingsStateSyncEvent) then
		return
	end

	self._settingsStateSyncEvent:FireClient(player, self:_buildStatePayload(player))
end

function SettingsService:_canProcessRequest(player)
	if not player then
		return false
	end

	local debounceSeconds = math.max(0.05, tonumber((GameConfig.SETTINGS or {}).RequestDebounceSeconds) or 0.15)
	local userId = player.UserId
	local nowClock = os.clock()
	local lastClock = tonumber(self._lastRequestClockByUserId[userId]) or 0
	if nowClock - lastClock < debounceSeconds then
		return false
	end

	self._lastRequestClockByUserId[userId] = nowClock
	return true
end

function SettingsService:_savePlayerDataAsync(player)
	if not (self._playerDataService and player) then
		return
	end

	task.spawn(function()
		self._playerDataService:SavePlayerData(player)
	end)
end

function SettingsService:_handleRequestSettingsStateSync(player)
	self:PushSettingsState(player)
end

function SettingsService:_handleRequestSettingsUpdate(player, payload)
	if not player then
		return
	end

	if not self:_canProcessRequest(player) then
		self:PushSettingsState(player)
		return
	end

	if not self._playerDataService then
		return
	end

	local playerData = self._playerDataService:GetPlayerData(player)
	local settingsState = ensureSettingsState(playerData)
	if not settingsState then
		self:PushSettingsState(player)
		return
	end

	local nextMusicEnabled = settingsState.MusicEnabled == true
	local nextSfxEnabled = settingsState.SfxEnabled == true
	if type(payload) == "table" then
		if payload.musicEnabled ~= nil then
			nextMusicEnabled = payload.musicEnabled == true
		end
		if payload.sfxEnabled ~= nil then
			nextSfxEnabled = payload.sfxEnabled == true
		end
	end

	settingsState.MusicEnabled = nextMusicEnabled
	settingsState.SfxEnabled = nextSfxEnabled

	self:PushSettingsState(player)
	self:_savePlayerDataAsync(player)
end

function SettingsService:Init(dependencies)
	self._playerDataService = dependencies.PlayerDataService

	local remoteEventService = dependencies.RemoteEventService
	self._settingsStateSyncEvent = remoteEventService:GetEvent("SettingsStateSync")
	self._requestSettingsStateSyncEvent = remoteEventService:GetEvent("RequestSettingsStateSync")
	self._requestSettingsUpdateEvent = remoteEventService:GetEvent("RequestSettingsUpdate")

	if self._requestSettingsStateSyncEvent then
		self._requestSettingsStateSyncEvent.OnServerEvent:Connect(function(player)
			self:_handleRequestSettingsStateSync(player)
		end)
	end

	if self._requestSettingsUpdateEvent then
		self._requestSettingsUpdateEvent.OnServerEvent:Connect(function(player, payload)
			self:_handleRequestSettingsUpdate(player, payload)
		end)
	end
end

function SettingsService:OnPlayerReady(player)
	if not (self._playerDataService and player) then
		return
	end

	local playerData = self._playerDataService:GetPlayerData(player)
	ensureSettingsState(playerData)
	self:PushSettingsState(player)
end

function SettingsService:OnPlayerRemoving(player)
	if not player then
		return
	end

	self._lastRequestClockByUserId[player.UserId] = nil
end

return SettingsService