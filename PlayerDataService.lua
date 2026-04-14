--[[
Script: PlayerDataService
Type: ModuleScript
Studio path: ServerScriptService/Services/PlayerDataService
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
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
        "[PlayerDataService] Missing shared module %s",
        moduleName
    ))
end

local GameConfig = requireSharedModule("GameConfig")

local PlayerDataService = {}
PlayerDataService._sessionDataByUserId = {}
PlayerDataService._sessionFlagsByUserId = {}
PlayerDataService._allowDataStoreSaveByUserId = {}
PlayerDataService._autosaveThread = nil
PlayerDataService._isShuttingDown = false
PlayerDataService._dataStore = nil
PlayerDataService._didWarnStudioMemoryMode = false
PlayerDataService._didWarnStudioApiDenied = false

local function isStudioApiDeniedError(err)
    return string.find(string.lower(tostring(err)), "studio access to apis is not allowed", 1, true) ~= nil
end

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, nestedValue in pairs(value) do
        copy[key] = deepCopy(nestedValue)
    end

    return copy
end

local function mergeDefaults(target, defaults)
    for key, defaultValue in pairs(defaults) do
        if target[key] == nil then
            target[key] = deepCopy(defaultValue)
        elseif type(defaultValue) == "table" and type(target[key]) == "table" then
            mergeDefaults(target[key], defaultValue)
        end
    end
end

local function waitForRetry(attempt)
    task.wait(GameConfig.DATASTORE.RetryDelay * attempt)
end

local function roundCurrencyValue(value)
    local numericValue = math.max(0, tonumber(value) or 0)
    return math.floor((numericValue * 10000) + 0.5) / 10000
end

local function ensureMetaTable(playerData)
    if type(playerData) ~= "table" then
        return nil
    end

    local meta = playerData.Meta
    if type(meta) ~= "table" then
        meta = {}
        playerData.Meta = meta
    end

    meta.CreatedAt = math.max(0, math.floor(tonumber(meta.CreatedAt) or 0))
    meta.LastLoginAt = math.max(0, math.floor(tonumber(meta.LastLoginAt) or 0))
    meta.LastLogoutAt = math.max(0, math.floor(tonumber(meta.LastLogoutAt) or 0))
    meta.LastSaveAt = math.max(0, math.floor(tonumber(meta.LastSaveAt) or 0))
    return meta
end

local function ensureCurrencyState(playerData)
    if type(playerData) ~= "table" then
        return nil
    end

    local currency = playerData.Currency
    if type(currency) ~= "table" then
        currency = {}
        playerData.Currency = currency
    end

    currency.Coins = roundCurrencyValue(currency.Coins)
    return currency
end

local function ensureLeaderboardState(playerData)
    if type(playerData) ~= "table" then
        return nil
    end

    local leaderboardState = playerData.LeaderboardState
    if type(leaderboardState) ~= "table" then
        leaderboardState = {}
        playerData.LeaderboardState = leaderboardState
    end

    leaderboardState.TotalPlaySeconds = math.max(0, math.floor(tonumber(leaderboardState.TotalPlaySeconds) or 0))
    leaderboardState.ProductionSpeedSnapshot = math.max(0, tonumber(leaderboardState.ProductionSpeedSnapshot) or 0)
    return leaderboardState
end

local function buildSaveSnapshot(playerData)
    if type(playerData) ~= "table" then
        return nil
    end

    local snapshot = deepCopy(playerData)
    ensureCurrencyState(snapshot)
    ensureLeaderboardState(snapshot)
    return snapshot
end

local function writeDataStoreSnapshot(self, userId, snapshot)
    if not self._dataStore then
        return true, nil
    end

    local success = false
    local errMsg = nil
    for attempt = 1, GameConfig.DATASTORE.MaxRetries do
        success, errMsg = pcall(function()
            self._dataStore:UpdateAsync(tostring(userId), function()
                return snapshot
            end)
        end)

        if success then
            return true, nil
        end

        if isStudioApiDeniedError(errMsg) then
            if not self._didWarnStudioApiDenied then
                warn("[PlayerDataService] Studio API access is disabled; switching saves to memory-only mode.")
                self._didWarnStudioApiDenied = true
            end
            self._dataStore = nil
            return true, nil
        end

        warn(string.format(
            "[PlayerDataService] Save failed userId=%d attempt=%d err=%s",
            userId,
            attempt,
            tostring(errMsg)
        ))

        if attempt < GameConfig.DATASTORE.MaxRetries then
            waitForRetry(attempt)
        end
    end

    return false, tostring(errMsg)
end

function PlayerDataService:Init()
    if self._autosaveThread then
        return
    end

    self._isShuttingDown = false

    if RunService:IsStudio() and not GameConfig.DATASTORE.EnableInStudio then
        if not self._didWarnStudioMemoryMode then
            warn("[PlayerDataService] Studio memory mode enabled because DATASTORE.EnableInStudio is false.")
            self._didWarnStudioMemoryMode = true
        end
        self._dataStore = nil
    else
        self._dataStore = DataStoreService:GetDataStore(GameConfig.DATASTORE.ActiveName)
    end

    self._autosaveThread = task.spawn(function()
        while not self._isShuttingDown do
            task.wait(GameConfig.DATASTORE.AutoSaveInterval)
            if self._isShuttingDown then
                break
            end

            for _, player in ipairs(Players:GetPlayers()) do
                self:SavePlayerData(player)
            end
        end
    end)
end

function PlayerDataService:Shutdown()
    self._isShuttingDown = true
end

function PlayerDataService:LoadPlayerData(player)
    local userId = player.UserId
    local loadedData
    local success = self._dataStore == nil
    local readFailed = false
    local allowDataStoreSave = self._dataStore ~= nil

    if self._dataStore then
        for attempt = 1, GameConfig.DATASTORE.MaxRetries do
            success, loadedData = pcall(function()
                return self._dataStore:GetAsync(tostring(userId))
            end)

            if success then
                break
            end

            readFailed = true

            if isStudioApiDeniedError(loadedData) then
                if not self._didWarnStudioApiDenied then
                    warn("[PlayerDataService] Studio API access is disabled; switching to memory-only mode.")
                    self._didWarnStudioApiDenied = true
                end
                self._dataStore = nil
                allowDataStoreSave = false
                break
            end

            warn(string.format(
                "[PlayerDataService] Read failed userId=%d attempt=%d err=%s",
                userId,
                attempt,
                tostring(loadedData)
            ))

            if attempt < GameConfig.DATASTORE.MaxRetries then
                waitForRetry(attempt)
            end
        end
    end

    if self._dataStore and readFailed and not success then
        allowDataStoreSave = false
        warn(string.format(
            "[PlayerDataService] Read failed repeatedly for userId=%d; this session will not write back to DataStore.",
            userId
        ))
    end

    local didCreateProfileThisSession = success and type(loadedData) ~= "table"
    local now = os.time()
    if not success or type(loadedData) ~= "table" then
        loadedData = deepCopy(GameConfig.DEFAULT_PLAYER_DATA)
        loadedData.Meta.CreatedAt = now
    end

    mergeDefaults(loadedData, GameConfig.DEFAULT_PLAYER_DATA)
    ensureCurrencyState(loadedData)
    local meta = ensureMetaTable(loadedData)
    local leaderboardState = ensureLeaderboardState(loadedData)
    if meta.CreatedAt <= 0 then
        meta.CreatedAt = now
    end
    if leaderboardState then
        leaderboardState.TotalPlaySeconds = math.max(0, math.floor(tonumber(leaderboardState.TotalPlaySeconds) or 0))
        leaderboardState.ProductionSpeedSnapshot = math.max(0, tonumber(leaderboardState.ProductionSpeedSnapshot) or 0)
    end

    meta.LastLoginAt = now
    self._sessionDataByUserId[userId] = loadedData
    self._sessionFlagsByUserId[userId] = {
        DidCreateProfileThisSession = didCreateProfileThisSession,
    }
    self._allowDataStoreSaveByUserId[userId] = allowDataStoreSave

    return loadedData
end

function PlayerDataService:GetPlayerData(player)
    return self._sessionDataByUserId[player.UserId]
end

function PlayerDataService:WasProfileCreatedThisSession(player)
    if not player then
        return false
    end

    local sessionFlags = self._sessionFlagsByUserId[player.UserId]
    return type(sessionFlags) == "table" and sessionFlags.DidCreateProfileThisSession == true
end

function PlayerDataService:GetCoins(player)
    local data = self:GetPlayerData(player)
    if not data then
        return 0
    end

    local currency = ensureCurrencyState(data)
    if not currency then
        return 0
    end

    return math.max(0, tonumber(currency.Coins) or 0)
end

function PlayerDataService:SetCoins(player, amount)
    local data = self:GetPlayerData(player)
    if not data then
        return nil, nil
    end

    local currency = ensureCurrencyState(data)
    if not currency then
        return nil, nil
    end

    local previous = roundCurrencyValue(currency.Coins)
    local nextValue = roundCurrencyValue(amount)
    currency.Coins = nextValue

    return previous, nextValue
end

function PlayerDataService:ChangeCoins(player, delta)
    local current = self:GetCoins(player)
    return self:SetCoins(player, current + (tonumber(delta) or 0))
end

function PlayerDataService:SetHomeId(player, homeId)
    local data = self:GetPlayerData(player)
    if not data then
        return
    end

    data.HomeState.HomeId = tostring(homeId or "")
end

function PlayerDataService:GetTotalPlaySeconds(player)
    local data = self:GetPlayerData(player)
    if type(data) ~= "table" then
        return 0
    end

    local leaderboardState = ensureLeaderboardState(data)
    local meta = ensureMetaTable(data)
    if not (leaderboardState and meta) then
        return 0
    end

    local totalPlaySeconds = math.max(0, math.floor(tonumber(leaderboardState.TotalPlaySeconds) or 0))
    local sessionStartedAt = math.max(0, math.floor(tonumber(meta.LastLoginAt) or 0))
    if sessionStartedAt <= 0 then
        return totalPlaySeconds
    end

    local now = os.time()
    local elapsed = math.max(0, now - sessionStartedAt)
    return totalPlaySeconds + elapsed
end

function PlayerDataService:CommitPlaytime(player, nowTimestamp)
    local data = self:GetPlayerData(player)
    if type(data) ~= "table" then
        return 0
    end

    local leaderboardState = ensureLeaderboardState(data)
    local meta = ensureMetaTable(data)
    if not (leaderboardState and meta) then
        return 0
    end

    local now = math.max(0, math.floor(tonumber(nowTimestamp) or 0))
    if now <= 0 then
        now = os.time()
    end

    local sessionStartedAt = math.max(0, math.floor(tonumber(meta.LastLoginAt) or 0))
    if sessionStartedAt > 0 then
        local elapsed = math.max(0, now - sessionStartedAt)
        if elapsed > 0 then
            leaderboardState.TotalPlaySeconds = math.max(0, math.floor(tonumber(leaderboardState.TotalPlaySeconds) or 0)) + elapsed
        end
    end

    meta.LastLoginAt = now
    return math.max(0, math.floor(tonumber(leaderboardState.TotalPlaySeconds) or 0))
end

function PlayerDataService:GetProductionSpeedSnapshot(player)
    local data = self:GetPlayerData(player)
    if type(data) ~= "table" then
        return 0
    end

    local leaderboardState = ensureLeaderboardState(data)
    if not leaderboardState then
        return 0
    end

    return math.max(0, tonumber(leaderboardState.ProductionSpeedSnapshot) or 0)
end

function PlayerDataService:SetProductionSpeedSnapshot(player, value)
    local data = self:GetPlayerData(player)
    if type(data) ~= "table" then
        return 0
    end

    local leaderboardState = ensureLeaderboardState(data)
    if not leaderboardState then
        return 0
    end

    leaderboardState.ProductionSpeedSnapshot = math.max(0, tonumber(value) or 0)
    return leaderboardState.ProductionSpeedSnapshot
end

function PlayerDataService:ResetPlayerData(player)
    local userId = player.UserId
    local now = os.time()
    local preservedTotalPlaySeconds = self:GetTotalPlaySeconds(player)

    local resetData = deepCopy(GameConfig.DEFAULT_PLAYER_DATA)
    local meta = ensureMetaTable(resetData)
    local leaderboardState = ensureLeaderboardState(resetData)
    meta.CreatedAt = now
    meta.LastLoginAt = now
    meta.LastLogoutAt = 0
    meta.LastSaveAt = 0
    if leaderboardState then
        leaderboardState.TotalPlaySeconds = preservedTotalPlaySeconds
        leaderboardState.ProductionSpeedSnapshot = 0
    end

    self._sessionDataByUserId[userId] = resetData
    self._sessionFlagsByUserId[userId] = {
        DidCreateProfileThisSession = false,
    }
    return resetData
end

function PlayerDataService:LoadStoredDataByUserId(userId)
    local resolvedUserId = math.max(0, math.floor(tonumber(userId) or 0))
    if resolvedUserId <= 0 then
        return nil, "InvalidUserId"
    end

    local loadedData = nil
    local success = self._dataStore == nil
    local errMsg = nil
    if self._dataStore then
        for attempt = 1, GameConfig.DATASTORE.MaxRetries do
            success, loadedData = pcall(function()
                return self._dataStore:GetAsync(tostring(resolvedUserId))
            end)

            if success then
                break
            end

            errMsg = loadedData
            if attempt < GameConfig.DATASTORE.MaxRetries then
                waitForRetry(attempt)
            end
        end
    end

    if not success then
        warn(string.format(
            "[PlayerDataService] Read stored data failed userId=%d err=%s",
            resolvedUserId,
            tostring(errMsg)
        ))
        return nil, "ReadFailed"
    end

    local now = os.time()
    if type(loadedData) ~= "table" then
        loadedData = deepCopy(GameConfig.DEFAULT_PLAYER_DATA)
    end

    mergeDefaults(loadedData, GameConfig.DEFAULT_PLAYER_DATA)
    ensureCurrencyState(loadedData)
    local meta = ensureMetaTable(loadedData)
    ensureLeaderboardState(loadedData)
    if meta and meta.CreatedAt <= 0 then
        meta.CreatedAt = now
    end

    return loadedData, nil
end

function PlayerDataService:SaveStoredDataByUserId(userId, data, options)
    local _options = options
    local resolvedUserId = math.max(0, math.floor(tonumber(userId) or 0))
    if resolvedUserId <= 0 then
        return false, "InvalidUserId"
    end
    if type(data) ~= "table" then
        return false, "InvalidData"
    end

    ensureCurrencyState(data)
    ensureLeaderboardState(data)
    local meta = ensureMetaTable(data)
    if meta then
        meta.LastSaveAt = os.time()
    end

    local snapshot = buildSaveSnapshot(data)
    if not snapshot then
        return false, "InvalidData"
    end

    return writeDataStoreSnapshot(self, resolvedUserId, snapshot)
end

function PlayerDataService:SavePlayerData(player, options)
    local userId = player.UserId
    local data = self._sessionDataByUserId[userId]
    if not data then
        return false
    end

    local skipCommitPlaytime = type(options) == "table" and options.SkipCommitPlaytime == true
    if not skipCommitPlaytime then
        self:CommitPlaytime(player)
    end
    local meta = ensureMetaTable(data)
    if meta then
        meta.LastSaveAt = os.time()
    end

    if not self._dataStore then
        return true
    end

    local forceDataStoreWrite = type(options) == "table" and options.ForceDataStoreWrite == true
    if self._allowDataStoreSaveByUserId[userId] == false and not forceDataStoreWrite then
        warn(string.format(
            "[PlayerDataService] Skipping save for userId=%d because the session had a DataStore read failure.",
            userId
        ))
        return false
    end

    local snapshot = buildSaveSnapshot(data)
    if not snapshot then
        return false
    end

    local success = writeDataStoreSnapshot(self, userId, snapshot)
    return success
end

function PlayerDataService:SaveAllPlayers()
    local players = Players:GetPlayers()
    local allSuccess = true
    local now = os.time()
    local pendingCount = #players
    if pendingCount <= 0 then
        return true
    end

    for _, player in ipairs(players) do
        local data = self._sessionDataByUserId[player.UserId]
        if type(data) == "table" then
            local meta = ensureMetaTable(data)
            if meta then
                meta.LastLogoutAt = now
            end
        end

        task.spawn(function()
            local success = self:SavePlayerData(player)
            if not success then
                allSuccess = false
            end

            pendingCount -= 1
        end)
    end

    while pendingCount > 0 do
        task.wait()
    end

    return allSuccess
end

function PlayerDataService:OnPlayerRemoving(player)
    local data = self._sessionDataByUserId[player.UserId]
    if type(data) == "table" then
        local meta = ensureMetaTable(data)
        if meta then
            meta.LastLogoutAt = os.time()
        end
    end

    self:SavePlayerData(player)
    self._sessionDataByUserId[player.UserId] = nil
    self._sessionFlagsByUserId[player.UserId] = nil
    self._allowDataStoreSaveByUserId[player.UserId] = nil
end

return PlayerDataService
