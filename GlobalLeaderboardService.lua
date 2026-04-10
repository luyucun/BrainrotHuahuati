--[[
脚本名字: GlobalLeaderboardService
脚本文件: GlobalLeaderboardService.lua
脚本类型: ModuleScript
Studio放置路径: ServerScriptService/Services/GlobalLeaderboardService
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

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
        "[GlobalLeaderboardService] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local GameConfig = requireSharedModule("GameConfig")
local BrainrotConfig = requireSharedModule("BrainrotConfig")
local FormatUtil = requireSharedModule("FormatUtil")

local GlobalLeaderboardService = {}
GlobalLeaderboardService._playerDataService = nil
GlobalLeaderboardService._friendBonusService = nil
GlobalLeaderboardService._orderedStoreByBoardKey = {}
GlobalLeaderboardService._storeModeByBoardKey = {}
GlobalLeaderboardService._memoryScoresByBoardKey = {}
GlobalLeaderboardService._cachedEntriesByBoardKey = {}
GlobalLeaderboardService._userInfoByUserId = {}
GlobalLeaderboardService._didWarnByKey = {}
GlobalLeaderboardService._refreshThread = nil
GlobalLeaderboardService._refreshQueued = false
GlobalLeaderboardService._isRefreshing = false
GlobalLeaderboardService._refreshAgain = false

local BOARD_KEYS = {
    Production = "Production",
    Playtime = "Playtime",
}

local function isStudioApiDeniedError(err)
    return string.find(string.lower(tostring(err)), "studio access to apis is not allowed", 1, true) ~= nil
end

local function clampNonNegativeNumber(value)
    return math.max(0, tonumber(value) or 0)
end

local function roundProductionValue(value)
    local precision = math.max(0, math.floor(tonumber(((GameConfig.BRAINROT or {}).UpgradeInternalPrecisionDecimals)) or 4))
    return math.max(0, FormatUtil.RoundToDecimals(value, precision))
end

local function getProductionOrderedStoreScale()
    return 1
end

local function normalizeBoardRuntimeScore(boardKey, score)
    if boardKey == BOARD_KEYS.Playtime then
        return math.max(0, math.floor(tonumber(score) or 0))
    end

    return math.max(0, tonumber(score) or 0)
end

local function encodeBoardScoreForStore(boardKey, score)
    local normalizedScore = normalizeBoardRuntimeScore(boardKey, score)
    if boardKey == BOARD_KEYS.Production then
        return math.max(0, math.floor((normalizedScore * getProductionOrderedStoreScale()) + 0.5))
    end

    return normalizedScore
end

local function decodeBoardScoreFromStore(boardKey, storedScore)
    local normalizedScore = math.max(0, tonumber(storedScore) or 0)
    if boardKey == BOARD_KEYS.Production then
        return normalizedScore / getProductionOrderedStoreScale()
    end

    return math.max(0, math.floor(normalizedScore))
end

local function getBaseBrainrotLevel()
    return math.max(1, math.floor(tonumber((GameConfig.BRAINROT or {}).BaseLevel) or 1))
end

local function normalizeBrainrotLevel(level)
    return math.max(getBaseBrainrotLevel(), math.floor(tonumber(level) or getBaseBrainrotLevel()))
end

local function getLeveledBrainrotProductionSpeed(brainrotDefinition, level)
    local baseSpeed = clampNonNegativeNumber(brainrotDefinition and brainrotDefinition.CoinPerSecond)
    local normalizedLevel = normalizeBrainrotLevel(level)
    local exponent = math.max(0, normalizedLevel - getBaseBrainrotLevel())
    local multiplier = math.max(0, tonumber((GameConfig.BRAINROT or {}).UpgradeProductionMultiplier) or 1.25)
    return roundProductionValue(baseSpeed * (multiplier ^ exponent))
end

local function findFirstDescendantByNames(root, names)
    if not root then
        return nil
    end

    for _, name in ipairs(names or {}) do
        local direct = root:FindFirstChild(name)
        if direct then
            return direct
        end
    end

    for _, name in ipairs(names or {}) do
        local nested = root:FindFirstChild(name, true)
        if nested then
            return nested
        end
    end

    return nil
end

local function findFirstTextLabel(root, name)
    local node = root and findFirstDescendantByNames(root, { name }) or nil
    if node and node:IsA("TextLabel") then
        return node
    end

    if node then
        local nested = node:FindFirstChildWhichIsA("TextLabel", true)
        if nested then
            return nested
        end
    end

    return nil
end

local function findFirstImageLabel(root, name)
    local node = root and findFirstDescendantByNames(root, { name }) or nil
    if node and node:IsA("ImageLabel") then
        return node
    end

    if node then
        local nested = node:FindFirstChildWhichIsA("ImageLabel", true)
        if nested then
            return nested
        end
    end

    return root and root:FindFirstChildWhichIsA("ImageLabel", true) or nil
end

local function setGuiVisible(node, isVisible)
    if node and node:IsA("GuiObject") then
        node.Visible = isVisible == true
    end
end

function GlobalLeaderboardService:_warnOnce(key, message)
    if self._didWarnByKey[key] then
        return
    end

    self._didWarnByKey[key] = true
    warn(message)
end

function GlobalLeaderboardService:_getConfig()
    return GameConfig.LEADERBOARD or {}
end

function GlobalLeaderboardService:_getBoardConfig(boardKey)
    local config = self:_getConfig()
    local boardModels = type(config.BoardModels) == "table" and config.BoardModels or {}
    return {
        ModelName = tostring(boardModels[boardKey] or (boardKey == BOARD_KEYS.Production and "Leaderboard01" or "Leaderboard02")),
        MaxEntries = math.max(1, math.floor(tonumber(config.MaxEntries) or 50)),
        PendingRankText = tostring(config.PendingRankText or "--"),
        OverflowRankText = tostring(config.OverflowRankText or "50+"),
    }
end

function GlobalLeaderboardService:_getPlayerAttributeName(attributeKey)
    local playerAttributes = type((self:_getConfig()).PlayerAttributes) == "table" and (self:_getConfig()).PlayerAttributes or {}
    return tostring(playerAttributes[attributeKey] or "")
end

function GlobalLeaderboardService:_setPlayerAttribute(player, attributeKey, value)
    if not player then
        return
    end

    local attributeName = self:_getPlayerAttributeName(attributeKey)
    if attributeName ~= "" then
        player:SetAttribute(attributeName, value)
    end
end

function GlobalLeaderboardService:_clearPlayerAttributes(player)
    if not player then
        return
    end

    for _, attributeKey in ipairs({ "ProductionValue", "ProductionRank", "PlaytimeValue", "PlaytimeRank" }) do
        local attributeName = self:_getPlayerAttributeName(attributeKey)
        if attributeName ~= "" then
            player:SetAttribute(attributeName, nil)
        end
    end
end

function GlobalLeaderboardService:_resolveOrderedStoreName(boardKey)
    local config = self:_getConfig()
    local orderedStores = type(config.OrderedDataStores) == "table" and config.OrderedDataStores or {}
    local storeConfig = type(orderedStores[boardKey]) == "table" and orderedStores[boardKey] or nil
    if not storeConfig then
        return nil
    end

    if RunService:IsStudio() then
        return tostring(storeConfig.StudioName or "")
    end

    return tostring(storeConfig.LiveName or "")
end

function GlobalLeaderboardService:_setBoardMode(boardKey, mode, warnMessage)
    self._storeModeByBoardKey[boardKey] = mode
    if warnMessage then
        self:_warnOnce(string.format("BoardMode:%s:%s", boardKey, mode), warnMessage)
    end
end

function GlobalLeaderboardService:_initBoardStores()
    local config = self:_getConfig()
    local useOrderedDataStore = not (RunService:IsStudio() and config.EnableOrderedDataStoreInStudio == false)

    for _, boardKey in ipairs({ BOARD_KEYS.Production, BOARD_KEYS.Playtime }) do
        self._memoryScoresByBoardKey[boardKey] = self._memoryScoresByBoardKey[boardKey] or {}
        self._cachedEntriesByBoardKey[boardKey] = self._cachedEntriesByBoardKey[boardKey] or {}

        local storeName = self:_resolveOrderedStoreName(boardKey)
        if not useOrderedDataStore or storeName == "" then
            self:_setBoardMode(boardKey, "memory", string.format("[GlobalLeaderboardService] %s 排行榜已切换为内存模式。", boardKey))
            self._orderedStoreByBoardKey[boardKey] = nil
        else
            self._orderedStoreByBoardKey[boardKey] = DataStoreService:GetOrderedDataStore(storeName)
            self._storeModeByBoardKey[boardKey] = "ordered"
        end
    end
end

function GlobalLeaderboardService:_getUserInfo(userId)
    local numericUserId = math.floor(tonumber(userId) or 0)
    if numericUserId <= 0 then
        return {
            Name = "Unknown",
            Avatar = "",
        }
    end

    local cached = self._userInfoByUserId[numericUserId]
    if cached then
        return cached
    end

    local info = {
        Name = tostring(numericUserId),
        Avatar = "",
    }

    local onlinePlayer = Players:GetPlayerByUserId(numericUserId)
    if onlinePlayer then
        info.Name = onlinePlayer.Name
    else
        local successName, resolvedName = pcall(function()
            return Players:GetNameFromUserIdAsync(numericUserId)
        end)
        if successName and type(resolvedName) == "string" and resolvedName ~= "" then
            info.Name = resolvedName
        end
    end

    local successThumbnail, thumbnail = pcall(function()
        local image, _isReady = Players:GetUserThumbnailAsync(numericUserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
        return image
    end)
    if successThumbnail and type(thumbnail) == "string" then
        info.Avatar = thumbnail
    end

    self._userInfoByUserId[numericUserId] = info
    return info
end

function GlobalLeaderboardService:_computeCurrentProductionScore(player)
    if not (self._playerDataService and player) then
        return 0
    end

    local playerData = self._playerDataService:GetPlayerData(player)
    if type(playerData) ~= "table" then
        return 0
    end

    local placedBrainrots = type(playerData.HomeState) == "table" and playerData.HomeState.PlacedBrainrots or nil
    local baseSpeed = 0
    if type(placedBrainrots) == "table" then
        for _, placedData in pairs(placedBrainrots) do
            local brainrotId = math.floor(tonumber(type(placedData) == "table" and placedData.BrainrotId or 0) or 0)
            local definition = BrainrotConfig.ById[brainrotId]
            if definition then
                local brainrotLevel = type(placedData) == "table" and placedData.Level or nil
                baseSpeed += getLeveledBrainrotProductionSpeed(definition, brainrotLevel)
            end
        end
    end

    local friendBonusRate = 0
    if self._friendBonusService then
        friendBonusRate = clampNonNegativeNumber(self._friendBonusService:GetBonusPercent(player)) / 100
    end

    local rebirthBonusRate = clampNonNegativeNumber(player:GetAttribute("RebirthBonusRate"))
    local vipBonusRate = clampNonNegativeNumber(player:GetAttribute("VipProductionBonusRate"))
    local extraBonusRate = clampNonNegativeNumber(player:GetAttribute("ExtraProductionBonusPercent")) / 100
    local totalBonusRate = friendBonusRate + rebirthBonusRate + vipBonusRate + extraBonusRate
    return roundProductionValue(baseSpeed * (1 + totalBonusRate))
end

function GlobalLeaderboardService:_computeCurrentPlaytimeScore(player)
    if not (self._playerDataService and player) then
        return 0
    end

    return math.max(0, math.floor(tonumber(self._playerDataService:GetTotalPlaySeconds(player)) or 0))
end

function GlobalLeaderboardService:_writeScore(boardKey, userId, score)
    local numericUserId = math.floor(tonumber(userId) or 0)
    if numericUserId <= 0 then
        return false
    end

    local normalizedScore = normalizeBoardRuntimeScore(boardKey, score)
    local storedScore = encodeBoardScoreForStore(boardKey, normalizedScore)

    local memoryScores = self._memoryScoresByBoardKey[boardKey]
    if type(memoryScores) == "table" then
        memoryScores[numericUserId] = normalizedScore
    end

    if self._storeModeByBoardKey[boardKey] ~= "ordered" then
        return true
    end

    local orderedStore = self._orderedStoreByBoardKey[boardKey]
    if not orderedStore then
        return false
    end

    local success, err = pcall(function()
        orderedStore:SetAsync(tostring(numericUserId), storedScore)
    end)
    if success then
        return true
    end

    if isStudioApiDeniedError(err) then
        self:_setBoardMode(boardKey, "memory", string.format("[GlobalLeaderboardService] %s 排行榜 OrderedDataStore 在 Studio 中不可用，已切换为内存模式。", boardKey))
        return true
    end

    warn(string.format("[GlobalLeaderboardService] 写入 %s 排行榜失败 userId=%d err=%s", boardKey, numericUserId, tostring(err)))
    return false
end

function GlobalLeaderboardService:_readOrderedEntries(boardKey)
    if self._storeModeByBoardKey[boardKey] ~= "ordered" then
        return nil
    end

    local orderedStore = self._orderedStoreByBoardKey[boardKey]
    if not orderedStore then
        return nil
    end

    local maxEntries = self:_getBoardConfig(boardKey).MaxEntries
    local success, pagesOrErr = pcall(function()
        return orderedStore:GetSortedAsync(false, maxEntries)
    end)
    if not success then
        if isStudioApiDeniedError(pagesOrErr) then
            self:_setBoardMode(boardKey, "memory", string.format("[GlobalLeaderboardService] %s 排行榜 OrderedDataStore 在 Studio 中不可读，已切换为内存模式。", boardKey))
            return nil
        end

        warn(string.format("[GlobalLeaderboardService] 读取 %s 排行榜失败 err=%s", boardKey, tostring(pagesOrErr)))
        return nil
    end

    local successPage, currentPage = pcall(function()
        return pagesOrErr:GetCurrentPage()
    end)
    if not successPage or type(currentPage) ~= "table" then
        warn(string.format("[GlobalLeaderboardService] 读取 %s 排行榜页面失败 err=%s", boardKey, tostring(currentPage)))
        return nil
    end

    local entries = {}
    for _, rawEntry in ipairs(currentPage) do
        local numericUserId = math.floor(tonumber(rawEntry.key) or 0)
        if numericUserId > 0 then
            table.insert(entries, {
                UserId = numericUserId,
                Score = decodeBoardScoreFromStore(boardKey, rawEntry.value),
            })
        end
    end

    return entries
end

function GlobalLeaderboardService:_buildEntriesFromMemory(boardKey)
    local entries = {}
    local memoryScores = self._memoryScoresByBoardKey[boardKey]
    if type(memoryScores) ~= "table" then
        return entries
    end

    for userId, score in pairs(memoryScores) do
        table.insert(entries, {
            UserId = math.floor(tonumber(userId) or 0),
            Score = boardKey == BOARD_KEYS.Playtime
                and math.max(0, math.floor(tonumber(score) or 0))
                or math.max(0, tonumber(score) or 0),
        })
    end

    return entries
end

function GlobalLeaderboardService:_mergeAndSortEntries(boardKey, baseEntries)
    local mergedByUserId = {}

    for _, entry in ipairs(baseEntries or {}) do
        local numericUserId = math.floor(tonumber(entry.UserId) or 0)
        if numericUserId > 0 then
            mergedByUserId[numericUserId] = boardKey == BOARD_KEYS.Playtime
                and math.max(0, math.floor(tonumber(entry.Score) or 0))
                or math.max(0, tonumber(entry.Score) or 0)
        end
    end

    local memoryScores = self._memoryScoresByBoardKey[boardKey]
    if type(memoryScores) == "table" then
        for userId, score in pairs(memoryScores) do
            local numericUserId = math.floor(tonumber(userId) or 0)
            if numericUserId > 0 then
                mergedByUserId[numericUserId] = boardKey == BOARD_KEYS.Playtime
                    and math.max(0, math.floor(tonumber(score) or 0))
                    or math.max(0, tonumber(score) or 0)
            end
        end
    end

    local mergedEntries = {}
    for userId, score in pairs(mergedByUserId) do
        table.insert(mergedEntries, {
            UserId = userId,
            Score = score,
        })
    end

    table.sort(mergedEntries, function(a, b)
        if a.Score == b.Score then
            return a.UserId < b.UserId
        end
        return a.Score > b.Score
    end)

    local maxEntries = self:_getBoardConfig(boardKey).MaxEntries
    while #mergedEntries > maxEntries do
        table.remove(mergedEntries)
    end

    for rank, entry in ipairs(mergedEntries) do
        entry.Rank = rank
    end

    return mergedEntries
end

function GlobalLeaderboardService:_getTopEntries(boardKey)
    local orderedEntries = self:_readOrderedEntries(boardKey)
    local sourceEntries = orderedEntries or self._cachedEntriesByBoardKey[boardKey] or {}
    if orderedEntries == nil and #sourceEntries <= 0 then
        sourceEntries = self:_buildEntriesFromMemory(boardKey)
    end

    local mergedEntries = self:_mergeAndSortEntries(boardKey, sourceEntries)
    self._cachedEntriesByBoardKey[boardKey] = mergedEntries
    return mergedEntries
end

function GlobalLeaderboardService:_formatBoardValue(boardKey, value)
    if boardKey == BOARD_KEYS.Playtime then
        return FormatUtil.FormatDurationDaysHoursMinutes(value)
    end

    return FormatUtil.FormatCompactCurrencyPerSecond(value)
end

function GlobalLeaderboardService:_applyEntryToRow(row, rank, entry, boardKey, shouldUpdateRank)
    if not row then
        return
    end

    setGuiVisible(row, true)

    local avatarLabel = findFirstImageLabel(row, "Avatar")
    local nameLabel = findFirstTextLabel(row, "Name")
    local numLabel = findFirstTextLabel(row, "Num")
    local rankLabel = shouldUpdateRank == true and findFirstTextLabel(row, "Rank") or nil
    local userInfo = self:_getUserInfo(entry.UserId)

    if avatarLabel then
        avatarLabel.Image = tostring(userInfo.Avatar or "")
    end
    if nameLabel then
        nameLabel.Text = tostring(userInfo.Name or "Unknown")
    end
    if numLabel then
        numLabel.Text = self:_formatBoardValue(boardKey, entry.Score)
    end
    if rankLabel then
        rankLabel.Text = tostring(rank)
    end
end

function GlobalLeaderboardService:_resolveBoardNodes(boardKey)
    local boardConfig = self:_getBoardConfig(boardKey)
    local boardModel = Workspace:FindFirstChild(boardConfig.ModelName) or Workspace:FindFirstChild(boardConfig.ModelName, true)
    if not boardModel then
        self:_warnOnce(string.format("MissingBoardModel:%s", boardKey), string.format("[GlobalLeaderboardService] 找不到排行榜模型 %s。", boardConfig.ModelName))
        return nil
    end

    local mainNode = findFirstDescendantByNames(boardModel, { "Main" })
    local surfaceGui = mainNode and findFirstDescendantByNames(mainNode, { "SurfaceGui" }) or nil
    local frame = surfaceGui and findFirstDescendantByNames(surfaceGui, { "Frame" }) or nil
    local scrollingFrame = frame and findFirstDescendantByNames(frame, { "ScrollingFrame" }) or nil
    if not (frame and scrollingFrame) then
        self:_warnOnce(string.format("MissingBoardNodes:%s", boardKey), string.format("[GlobalLeaderboardService] %s 缺少 Frame/ScrollingFrame 结构。", boardConfig.ModelName))
        return nil
    end

    return {
        Frame = frame,
        ScrollingFrame = scrollingFrame,
    }
end

function GlobalLeaderboardService:_clearGeneratedRows(scrollingFrame)
    if not scrollingFrame then
        return
    end

    for _, child in ipairs(scrollingFrame:GetChildren()) do
        if child:GetAttribute("GeneratedGlobalLeaderboardRow") == true then
            child:Destroy()
        end
    end
end

function GlobalLeaderboardService:_applyBoardEntries(boardKey, entries)
    local nodes = self:_resolveBoardNodes(boardKey)
    if not nodes then
        return
    end

    local scrollingFrame = nodes.ScrollingFrame
    self:_clearGeneratedRows(scrollingFrame)

    local fixedRows = {
        scrollingFrame:FindFirstChild("Rank01"),
        scrollingFrame:FindFirstChild("Rank02"),
        scrollingFrame:FindFirstChild("Rank03"),
    }
    local rankTemplate = scrollingFrame:FindFirstChild("RankTemplate")

    for index, fixedRow in ipairs(fixedRows) do
        local entry = entries[index]
        if entry then
            self:_applyEntryToRow(fixedRow, index, entry, boardKey, false)
        else
            setGuiVisible(fixedRow, false)
        end
    end

    if rankTemplate and rankTemplate:IsA("GuiObject") then
        rankTemplate.Visible = false
    end

    if not rankTemplate then
        if #entries > 3 then
            self:_warnOnce(string.format("MissingRankTemplate:%s", boardKey), string.format("[GlobalLeaderboardService] %s 缺少 RankTemplate，第四名之后无法显示。", boardKey))
        end
        return
    end

    for index = 4, math.min(#entries, self:_getBoardConfig(boardKey).MaxEntries) do
        local entry = entries[index]
        local rowClone = rankTemplate:Clone()
        rowClone.Name = string.format("GeneratedRank%02d", index)
        rowClone.Visible = true
        rowClone.LayoutOrder = index
        rowClone:SetAttribute("GeneratedGlobalLeaderboardRow", true)
        rowClone.Parent = scrollingFrame
        self:_applyEntryToRow(rowClone, index, entry, boardKey, true)
    end
end

function GlobalLeaderboardService:_refreshPlayerAttributes(productionEntries, playtimeEntries, productionScoresByUserId, playtimeScoresByUserId)
    local productionRankByUserId = {}
    for rank, entry in ipairs(productionEntries or {}) do
        productionRankByUserId[entry.UserId] = tostring(rank)
    end

    local playtimeRankByUserId = {}
    for rank, entry in ipairs(playtimeEntries or {}) do
        playtimeRankByUserId[entry.UserId] = tostring(rank)
    end

    local productionOverflowRankText = self:_getBoardConfig(BOARD_KEYS.Production).OverflowRankText
    local playtimeOverflowRankText = self:_getBoardConfig(BOARD_KEYS.Playtime).OverflowRankText
    for _, player in ipairs(Players:GetPlayers()) do
        local userId = player.UserId
        self:_setPlayerAttribute(player, "ProductionValue", productionScoresByUserId[userId] or 0)
        self:_setPlayerAttribute(player, "PlaytimeValue", playtimeScoresByUserId[userId] or 0)
        self:_setPlayerAttribute(player, "ProductionRank", productionRankByUserId[userId] or productionOverflowRankText)
        self:_setPlayerAttribute(player, "PlaytimeRank", playtimeRankByUserId[userId] or playtimeOverflowRankText)
    end
end

function GlobalLeaderboardService:_storeOnlinePlayerScores()
    local productionScoresByUserId = {}
    local playtimeScoresByUserId = {}

    for _, player in ipairs(Players:GetPlayers()) do
        local productionScore = self:_computeCurrentProductionScore(player)
        local playtimeScore = self:_computeCurrentPlaytimeScore(player)
        productionScoresByUserId[player.UserId] = productionScore
        playtimeScoresByUserId[player.UserId] = playtimeScore

        if self._playerDataService then
            self._playerDataService:SetProductionSpeedSnapshot(player, productionScore)
        end

        self:_writeScore(BOARD_KEYS.Production, player.UserId, productionScore)
        self:_writeScore(BOARD_KEYS.Playtime, player.UserId, playtimeScore)
    end

    return productionScoresByUserId, playtimeScoresByUserId
end

function GlobalLeaderboardService:_refreshNow()
    if self._isRefreshing then
        self._refreshAgain = true
        return
    end

    self._isRefreshing = true
    repeat
        self._refreshAgain = false

        local productionScoresByUserId, playtimeScoresByUserId = self:_storeOnlinePlayerScores()
        local productionEntries = self:_getTopEntries(BOARD_KEYS.Production)
        local playtimeEntries = self:_getTopEntries(BOARD_KEYS.Playtime)

        self:_applyBoardEntries(BOARD_KEYS.Production, productionEntries)
        self:_applyBoardEntries(BOARD_KEYS.Playtime, playtimeEntries)
        self:_refreshPlayerAttributes(productionEntries, playtimeEntries, productionScoresByUserId, playtimeScoresByUserId)
    until not self._refreshAgain

    self._isRefreshing = false
end

function GlobalLeaderboardService:RequestRefresh()
    if self._refreshQueued then
        return
    end

    self._refreshQueued = true
    task.defer(function()
        self._refreshQueued = false
        self:_refreshNow()
    end)
end

function GlobalLeaderboardService:Init(dependencies)
    if self._refreshThread then
        return
    end

    self._playerDataService = dependencies.PlayerDataService
    self._friendBonusService = dependencies.FriendBonusService
    self:_initBoardStores()
    self:RequestRefresh()

    self._refreshThread = task.spawn(function()
        local refreshInterval = math.max(15, math.floor(tonumber((self:_getConfig()).RefreshIntervalSeconds) or 120))
        while true do
            task.wait(refreshInterval)
            self:RequestRefresh()
        end
    end)
end

function GlobalLeaderboardService:OnPlayerReady(player)
    if not player then
        return
    end

    self:_setPlayerAttribute(player, "ProductionValue", self:_computeCurrentProductionScore(player))
    self:_setPlayerAttribute(player, "PlaytimeValue", self:_computeCurrentPlaytimeScore(player))
    self:_setPlayerAttribute(player, "ProductionRank", self:_getBoardConfig(BOARD_KEYS.Production).PendingRankText)
    self:_setPlayerAttribute(player, "PlaytimeRank", self:_getBoardConfig(BOARD_KEYS.Playtime).PendingRankText)
    self:RequestRefresh()
end

function GlobalLeaderboardService:OnPlayerRemoving(player)
    if not player then
        return
    end

    local productionScore = self:_computeCurrentProductionScore(player)
    local playtimeScore = self:_computeCurrentPlaytimeScore(player)
    if self._playerDataService then
        self._playerDataService:SetProductionSpeedSnapshot(player, productionScore)
    end
    self:_writeScore(BOARD_KEYS.Production, player.UserId, productionScore)
    self:_writeScore(BOARD_KEYS.Playtime, player.UserId, playtimeScore)
    self:_clearPlayerAttributes(player)
    self:RequestRefresh()
end

function GlobalLeaderboardService:FlushAllPlayers()
    local allSuccess = true
    for _, player in ipairs(Players:GetPlayers()) do
        local productionScore = self:_computeCurrentProductionScore(player)
        local playtimeScore = self:_computeCurrentPlaytimeScore(player)
        if self._playerDataService then
            self._playerDataService:SetProductionSpeedSnapshot(player, productionScore)
        end
        if not self:_writeScore(BOARD_KEYS.Production, player.UserId, productionScore) then
            allSuccess = false
        end
        if not self:_writeScore(BOARD_KEYS.Playtime, player.UserId, playtimeScore) then
            allSuccess = false
        end
    end

    self:RequestRefresh()
    return allSuccess
end

return GlobalLeaderboardService
