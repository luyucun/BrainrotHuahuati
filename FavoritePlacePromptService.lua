--[[
脚本名字: FavoritePlacePromptService
脚本文件: FavoritePlacePromptService.lua
脚本类型: ModuleScript
Studio放置路径: ServerScriptService/Services/FavoritePlacePromptService
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
        "[FavoritePlacePromptService] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local GameConfig = requireSharedModule("GameConfig")

local FavoritePlacePromptService = {}
FavoritePlacePromptService._playerDataService = nil
FavoritePlacePromptService._remoteEventService = nil
FavoritePlacePromptService._promptFavoritePlaceEvent = nil
FavoritePlacePromptService._favoritePlacePromptStartedEvent = nil
FavoritePlacePromptService._favoritePlacePromptResultEvent = nil
FavoritePlacePromptService._pendingRequestIdByUserId = {}
FavoritePlacePromptService._startedRequestIdByUserId = {}

local function asNonNegativeInteger(value)
    return math.max(0, math.floor(tonumber(value) or 0))
end

local function getUtcDayKey(timestamp)
    return math.floor(asNonNegativeInteger(timestamp) / 86400)
end

local function ensureFavoritePromptState(playerData)
    if type(playerData) ~= "table" then
        return nil
    end

    local state = playerData.FavoritePromptState
    if type(state) ~= "table" then
        state = {}
        playerData.FavoritePromptState = state
    end

    local legacyHasPrompted = state.HasPrompted == true
    local lastPromptResult = tostring(state.LastPromptResult or "")

    state.HasFavorited = state.HasFavorited == true
        or (legacyHasPrompted and lastPromptResult == "Success")
    state.PromptedAt = asNonNegativeInteger(state.PromptedAt)
    state.LastPromptUtcDay = asNonNegativeInteger(state.LastPromptUtcDay)
    if state.LastPromptUtcDay <= 0 and state.PromptedAt > 0 then
        state.LastPromptUtcDay = getUtcDayKey(state.PromptedAt)
    end
    state.LastPromptResult = lastPromptResult
    state.LastResultAt = asNonNegativeInteger(state.LastResultAt)
    return state
end

function FavoritePlacePromptService:_getConfig()
    return GameConfig.FAVORITE_PROMPT or {}
end

function FavoritePlacePromptService:_buildRequestId(player)
    return string.format(
        "FavoritePlace:%d:%d:%d",
        asNonNegativeInteger(player and player.UserId or 0),
        asNonNegativeInteger(os.time()),
        asNonNegativeInteger(math.floor(os.clock() * 1000))
    )
end

function FavoritePlacePromptService:_shouldPromptPlayer(player)
    if not player then
        return false
    end

    local config = self:_getConfig()
    if config.Enabled == false then
        return false
    end

    if asNonNegativeInteger(game.PlaceId) <= 0 then
        return false
    end

    local playerData = self._playerDataService and self._playerDataService:GetPlayerData(player) or nil
    local favoritePromptState = ensureFavoritePromptState(playerData)
    if not favoritePromptState then
        return false
    end

    if favoritePromptState.HasFavorited == true then
        return false
    end

    return favoritePromptState.LastPromptUtcDay < getUtcDayKey(os.time())
end

function FavoritePlacePromptService:_savePromptState(player)
    if not (self._playerDataService and player) then
        return false
    end

    return self._playerDataService:SavePlayerData(player, {
        SkipCommitPlaytime = true,
    })
end

function FavoritePlacePromptService:_handlePromptStarted(player, payload)
    if not player then
        return
    end

    local requestId = type(payload) == "table" and tostring(payload.requestId or "") or ""
    if requestId == "" or self._pendingRequestIdByUserId[player.UserId] ~= requestId then
        return
    end

    local playerData = self._playerDataService and self._playerDataService:GetPlayerData(player) or nil
    local favoritePromptState = ensureFavoritePromptState(playerData)
    if not favoritePromptState then
        self._startedRequestIdByUserId[player.UserId] = requestId
        return
    end

    local nowTimestamp = asNonNegativeInteger(os.time())
    favoritePromptState.PromptedAt = nowTimestamp
    favoritePromptState.LastPromptUtcDay = getUtcDayKey(nowTimestamp)
    self._startedRequestIdByUserId[player.UserId] = requestId

    local didSave = self:_savePromptState(player)
    if didSave ~= true then
        warn(string.format(
            "[FavoritePlacePromptService] 保存首收藏提示状态失败 userId=%d requestId=%s",
            asNonNegativeInteger(player.UserId),
            requestId
        ))
    end
end

function FavoritePlacePromptService:_handlePromptResult(player, payload)
    if not player then
        return
    end

    local requestId = type(payload) == "table" and tostring(payload.requestId or "") or ""
    local pendingRequestId = tostring(self._pendingRequestIdByUserId[player.UserId] or "")
    local startedRequestId = tostring(self._startedRequestIdByUserId[player.UserId] or "")
    if requestId == "" or (requestId ~= pendingRequestId and requestId ~= startedRequestId) then
        return
    end

    local playerData = self._playerDataService and self._playerDataService:GetPlayerData(player) or nil
    local favoritePromptState = ensureFavoritePromptState(playerData)
    if not favoritePromptState then
        self._pendingRequestIdByUserId[player.UserId] = nil
        self._startedRequestIdByUserId[player.UserId] = nil
        return
    end

    favoritePromptState.LastPromptResult = type(payload) == "table" and tostring(payload.result or "") or ""
    favoritePromptState.LastResultAt = asNonNegativeInteger(os.time())
    if favoritePromptState.LastPromptResult == "Success"
        or favoritePromptState.LastPromptResult == "AlreadyFavorite" then
        favoritePromptState.HasFavorited = true
    end

    local didSave = self:_savePromptState(player)
    if didSave ~= true then
        warn(string.format(
            "[FavoritePlacePromptService] 保存收藏提示结果失败 userId=%d requestId=%s result=%s",
            asNonNegativeInteger(player.UserId),
            requestId,
            favoritePromptState.LastPromptResult
        ))
    end

    self._pendingRequestIdByUserId[player.UserId] = nil
    self._startedRequestIdByUserId[player.UserId] = nil
end

function FavoritePlacePromptService:OnPlayerReady(player)
    if not (self._promptFavoritePlaceEvent and self:_shouldPromptPlayer(player)) then
        return
    end

    local requestId = self:_buildRequestId(player)
    self._pendingRequestIdByUserId[player.UserId] = requestId
    self._startedRequestIdByUserId[player.UserId] = nil

    self._promptFavoritePlaceEvent:FireClient(player, {
        requestId = requestId,
        placeId = asNonNegativeInteger(game.PlaceId),
        delaySeconds = math.max(0, tonumber(self:_getConfig().DelaySeconds) or 60),
        timestamp = os.clock(),
    })
end

function FavoritePlacePromptService:OnPlayerRemoving(player)
    if not player then
        return
    end

    self._pendingRequestIdByUserId[player.UserId] = nil
    self._startedRequestIdByUserId[player.UserId] = nil
end

function FavoritePlacePromptService:Init(dependencies)
    self._playerDataService = dependencies.PlayerDataService
    self._remoteEventService = dependencies.RemoteEventService

    self._promptFavoritePlaceEvent = self._remoteEventService:GetEvent("PromptFavoritePlace")
    self._favoritePlacePromptStartedEvent = self._remoteEventService:GetEvent("FavoritePlacePromptStarted")
    self._favoritePlacePromptResultEvent = self._remoteEventService:GetEvent("FavoritePlacePromptResult")

    if self._favoritePlacePromptStartedEvent then
        self._favoritePlacePromptStartedEvent.OnServerEvent:Connect(function(player, payload)
            self:_handlePromptStarted(player, payload)
        end)
    end

    if self._favoritePlacePromptResultEvent then
        self._favoritePlacePromptResultEvent.OnServerEvent:Connect(function(player, payload)
            self:_handlePromptResult(player, payload)
        end)
    end
end

return FavoritePlacePromptService
