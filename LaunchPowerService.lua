--[[
脚本名字: LaunchPowerService
脚本文件: LaunchPowerService.lua
脚本类型: ModuleScript
Studio放置路径: ServerScriptService/Services/LaunchPowerService
]]

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
        "[LaunchPowerService] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local GameConfig = requireSharedModule("GameConfig")

local LaunchPowerService = {}
LaunchPowerService._playerDataService = nil
LaunchPowerService._currencyService = nil
LaunchPowerService._launchPowerStateSyncEvent = nil
LaunchPowerService._requestLaunchPowerStateSyncEvent = nil
LaunchPowerService._requestLaunchPowerUpgradeEvent = nil
LaunchPowerService._requestStudioResetLaunchPowerEvent = nil
LaunchPowerService._launchPowerFeedbackEvent = nil
LaunchPowerService._lastRequestClockByUserId = {}

local function getConfig()
    return GameConfig.LAUNCH_POWER or {}
end

local function getDefaultLevel()
    return math.max(1, math.floor(tonumber(getConfig().DefaultLevel) or 1))
end

local function getBulkUpgradeLevelCount()
    return math.max(1, math.floor(tonumber(getConfig().BulkUpgradeLevelCount) or 10))
end

local function getMiddleUpgradeLevelCount()
    return math.max(1, math.floor(tonumber(getConfig().MiddleUpgradeLevelCount) or 5))
end

local function getLargeUpgradeLevelCount()
    local configuredLarge = math.max(1, math.floor(tonumber(getConfig().LargeUpgradeLevelCount) or getBulkUpgradeLevelCount()))
    return math.max(configuredLarge, getMiddleUpgradeLevelCount())
end

local function getSupportedUpgradeLevelCounts()
    local supportedCountMap = {}
    supportedCountMap[1] = true
    supportedCountMap[getMiddleUpgradeLevelCount()] = true
    supportedCountMap[getLargeUpgradeLevelCount()] = true

    local counts = {}
    for count in pairs(supportedCountMap) do
        table.insert(counts, count)
    end
    table.sort(counts, function(a, b)
        return a < b
    end)
    return counts
end

local function getRobuxProductIdByUpgradeCount(upgradeCount)
    local products = getConfig().RobuxUpgradeProducts
    if type(products) ~= "table" then
        return 0
    end
    return math.max(
        0,
        math.floor(tonumber(products[math.max(1, math.floor(tonumber(upgradeCount) or 1))]) or 0)
    )
end

local function getUpgradeCountByRobuxProductId(productId)
    local normalizedProductId = math.max(0, math.floor(tonumber(productId) or 0))
    if normalizedProductId <= 0 then
        return nil
    end

    for _, count in ipairs(getSupportedUpgradeLevelCounts()) do
        if getRobuxProductIdByUpgradeCount(count) == normalizedProductId then
            return count
        end
    end

    return nil
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

local function getBaseUpgradeCost()
    return math.max(0, math.ceil((tonumber(getConfig().BaseUpgradeCost) or 200) - 1e-6))
end

local function getUpgradeCostSegments()
    local defaultLevel = getDefaultLevel()
    local baseTargetLevel = defaultLevel + 1
    local rawSegments = getConfig().UpgradeCostSegments
    local segments = {}

    if type(rawSegments) == "table" then
        for _, rawSegment in ipairs(rawSegments) do
            if type(rawSegment) == "table" then
                local multiplier = math.max(1, tonumber(rawSegment.Multiplier) or 1)
                local maxTargetLevel = rawSegment.MaxTargetLevel
                if maxTargetLevel ~= nil then
                    maxTargetLevel = math.max(baseTargetLevel, math.floor(tonumber(maxTargetLevel) or baseTargetLevel))
                end

                table.insert(segments, {
                    MaxTargetLevel = maxTargetLevel,
                    Multiplier = multiplier,
                })
            end
        end
    end

    if #segments <= 0 then
        table.insert(segments, {
            Multiplier = math.max(1, tonumber(getConfig().UpgradeCostMultiplier) or 1.08),
        })
    end

    return segments
end

local function getUpgradeCostMultiplierForTargetLevel(segments, targetLevel)
    local defaultLevel = getDefaultLevel()
    local normalizedTargetLevel = math.max(defaultLevel + 1, math.floor(tonumber(targetLevel) or (defaultLevel + 1)))
    local fallbackMultiplier = 1

    for _, segment in ipairs(segments) do
        fallbackMultiplier = math.max(1, tonumber(segment.Multiplier) or fallbackMultiplier)
        local maxTargetLevel = segment.MaxTargetLevel
        if maxTargetLevel == nil or normalizedTargetLevel <= maxTargetLevel then
            return fallbackMultiplier
        end
    end

    return fallbackMultiplier
end

local function ensureGrowthTable(playerData)
    if type(playerData) ~= "table" then
        return nil
    end

    local growth = playerData.Growth
    if type(growth) ~= "table" then
        growth = {}
        playerData.Growth = growth
    end

    growth.PowerLevel = math.max(getDefaultLevel(), math.floor(tonumber(growth.PowerLevel) or getDefaultLevel()))
    if growth.RebirthLevel == nil then
        growth.RebirthLevel = 0
    end
    growth.ProcessedLaunchPowerPurchaseIds = normalizeProcessedPurchaseIds(growth.ProcessedLaunchPowerPurchaseIds)

    return growth
end

function LaunchPowerService:_getPlayerDataAndGrowth(player)
    if not (self._playerDataService and player) then
        return nil, nil
    end

    local playerData = self._playerDataService:GetPlayerData(player)
    if type(playerData) ~= "table" then
        return nil, nil
    end

    return playerData, ensureGrowthTable(playerData)
end

function LaunchPowerService:_getOrCreateProcessedLaunchPowerPurchaseIds(growth)
    if type(growth) ~= "table" then
        return {}
    end

    growth.ProcessedLaunchPowerPurchaseIds = normalizeProcessedPurchaseIds(growth.ProcessedLaunchPowerPurchaseIds)
    return growth.ProcessedLaunchPowerPurchaseIds
end

function LaunchPowerService:GetLaunchPowerLevel(player)
    local _playerData, growth = self:_getPlayerDataAndGrowth(player)
    if not growth then
        return getDefaultLevel()
    end

    growth.PowerLevel = math.max(getDefaultLevel(), math.floor(tonumber(growth.PowerLevel) or getDefaultLevel()))
    return growth.PowerLevel
end

function LaunchPowerService:GetLaunchPowerValueByLevel(level)
    local normalizedLevel = math.max(getDefaultLevel(), math.floor(tonumber(level) or getDefaultLevel()))
    return math.max(0, normalizedLevel - getDefaultLevel())
end

function LaunchPowerService:GetLaunchPowerValue(player)
    return self:GetLaunchPowerValueByLevel(self:GetLaunchPowerLevel(player))
end

function LaunchPowerService:GetNextUpgradeCostByLevel(currentLevel)
    local defaultLevel = getDefaultLevel()
    local normalizedLevel = math.max(defaultLevel, math.floor(tonumber(currentLevel) or defaultLevel))
    local baseTargetLevel = defaultLevel + 1
    local targetLevel = normalizedLevel + 1
    local currentCost = getBaseUpgradeCost()

    if targetLevel <= baseTargetLevel then
        return currentCost
    end

    local segments = getUpgradeCostSegments()
    for iterTargetLevel = baseTargetLevel + 1, targetLevel do
        local multiplier = getUpgradeCostMultiplierForTargetLevel(segments, iterTargetLevel)
        currentCost = math.max(0, math.ceil((currentCost * multiplier) - 1e-6))
    end

    return currentCost
end

function LaunchPowerService:GetUpgradePackageCostByLevel(currentLevel, upgradeCount)
    local defaultLevel = getDefaultLevel()
    local normalizedLevel = math.max(defaultLevel, math.floor(tonumber(currentLevel) or defaultLevel))
    local normalizedUpgradeCount = math.max(1, math.floor(tonumber(upgradeCount) or 1))
    local totalCost = 0
    local nextUpgradeCost = self:GetNextUpgradeCostByLevel(normalizedLevel)
    local segments = getUpgradeCostSegments()

    for step = 1, normalizedUpgradeCount do
        totalCost += nextUpgradeCost

        if step < normalizedUpgradeCount then
            local nextTargetLevel = normalizedLevel + step + 1
            local multiplier = getUpgradeCostMultiplierForTargetLevel(segments, nextTargetLevel)
            nextUpgradeCost = math.max(0, math.ceil((nextUpgradeCost * multiplier) - 1e-6))
        end
    end

    return math.max(0, totalCost)
end

function LaunchPowerService:_normalizeRequestedUpgradeCount(payload)
    local requestedCount = 1
    if type(payload) == "table" then
        requestedCount = math.max(1, math.floor(tonumber(payload.upgradeCount) or 1))
    end

    for _, supportedCount in ipairs(getSupportedUpgradeLevelCounts()) do
        if requestedCount == supportedCount then
            return requestedCount
        end
    end

    return nil
end

function LaunchPowerService:_applyPlayerAttributes(player, level)
    if not player then
        return 0
    end

    local normalizedLevel = math.max(getDefaultLevel(), math.floor(tonumber(level) or getDefaultLevel()))
    local launchPowerValue = self:GetLaunchPowerValueByLevel(normalizedLevel)
    player:SetAttribute("LaunchPowerLevel", normalizedLevel)
    player:SetAttribute("LaunchPowerValue", launchPowerValue)
    return launchPowerValue
end

function LaunchPowerService:_buildStatePayload(player)
    local currentLevel = self:GetLaunchPowerLevel(player)
    local currentValue = self:GetLaunchPowerValueByLevel(currentLevel)
    local upgrade1Count = 1
    local upgrade2Count = getMiddleUpgradeLevelCount()
    local upgrade3Count = getLargeUpgradeLevelCount()
    local upgrade1NextLevel = currentLevel + upgrade1Count
    local upgrade2NextLevel = currentLevel + upgrade2Count
    local upgrade3NextLevel = currentLevel + upgrade3Count
    local upgrade1NextValue = self:GetLaunchPowerValueByLevel(upgrade1NextLevel)
    local upgrade2NextValue = self:GetLaunchPowerValueByLevel(upgrade2NextLevel)
    local upgrade3NextValue = self:GetLaunchPowerValueByLevel(upgrade3NextLevel)
    local upgrade1NextCost = self:GetUpgradePackageCostByLevel(currentLevel, upgrade1Count)
    local upgrade2NextCost = self:GetUpgradePackageCostByLevel(currentLevel, upgrade2Count)
    local upgrade3NextCost = self:GetUpgradePackageCostByLevel(currentLevel, upgrade3Count)
    local currentCoins = self._playerDataService and self._playerDataService:GetCoins(player) or 0
    local config = getConfig()

    return {
        currentLevel = currentLevel,
        currentValue = currentValue,
        nextLevel = upgrade1NextLevel,
        nextValue = upgrade1NextValue,
        nextCost = upgrade1NextCost,
        bulkUpgradeCount = upgrade3Count,
        bulkNextLevel = upgrade3NextLevel,
        bulkNextValue = upgrade3NextValue,
        bulkNextCost = upgrade3NextCost,
        upgrade1Count = upgrade1Count,
        upgrade1NextLevel = upgrade1NextLevel,
        upgrade1NextValue = upgrade1NextValue,
        upgrade1NextCost = upgrade1NextCost,
        upgrade1ProductId = getRobuxProductIdByUpgradeCount(upgrade1Count),
        upgrade2Count = upgrade2Count,
        upgrade2NextLevel = upgrade2NextLevel,
        upgrade2NextValue = upgrade2NextValue,
        upgrade2NextCost = upgrade2NextCost,
        upgrade2ProductId = getRobuxProductIdByUpgradeCount(upgrade2Count),
        upgrade3Count = upgrade3Count,
        upgrade3NextLevel = upgrade3NextLevel,
        upgrade3NextValue = upgrade3NextValue,
        upgrade3NextCost = upgrade3NextCost,
        upgrade3ProductId = getRobuxProductIdByUpgradeCount(upgrade3Count),
        currentCoins = math.max(0, tonumber(currentCoins) or 0),
        speedPerPoint = math.max(0, tonumber(config.SpeedPerPoint) or 1),
        timestamp = os.clock(),
    }
end

function LaunchPowerService:PushLaunchPowerState(player)
    if not (player and self._launchPowerStateSyncEvent) then
        return
    end

    self._launchPowerStateSyncEvent:FireClient(player, self:_buildStatePayload(player))
end

function LaunchPowerService:_pushFeedback(player, status, message, requestId, currentCoins)
    if not (player and self._launchPowerFeedbackEvent) then
        return
    end

    self._launchPowerFeedbackEvent:FireClient(player, {
        status = tostring(status or "Unknown"),
        message = tostring(message or ""),
        requestId = tostring(requestId or ""),
        currentCoins = math.max(0, tonumber(currentCoins) or 0),
        timestamp = os.clock(),
    })
end

function LaunchPowerService:_canSendRequest(player)
    if not player then
        return false
    end

    local debounceSeconds = math.max(0.05, tonumber(getConfig().RequestDebounceSeconds) or 0.35)
    local userId = player.UserId
    local nowClock = os.clock()
    local lastClock = tonumber(self._lastRequestClockByUserId[userId]) or 0
    if nowClock - lastClock < debounceSeconds then
        return false
    end

    self._lastRequestClockByUserId[userId] = nowClock
    return true
end

function LaunchPowerService:_handleRequestLaunchPowerStateSync(player)
    if not player then
        return
    end

    self:PushLaunchPowerState(player)
end

function LaunchPowerService:_handleRequestLaunchPowerUpgrade(player, payload)
    if not player then
        return
    end

    local requestId = type(payload) == "table" and tostring(payload.requestId or "") or ""
    if not self:_canSendRequest(player) then
        self:_pushFeedback(player, "Debounced", "", requestId, self._playerDataService and self._playerDataService:GetCoins(player) or 0)
        return
    end

    local _playerData, growth = self:_getPlayerDataAndGrowth(player)
    if not growth then
        self:_pushFeedback(player, "MissingData", "", requestId, self._playerDataService and self._playerDataService:GetCoins(player) or 0)
        return
    end

    local currentLevel = math.max(getDefaultLevel(), math.floor(tonumber(growth.PowerLevel) or getDefaultLevel()))
    growth.PowerLevel = currentLevel

    local upgradeCount = self:_normalizeRequestedUpgradeCount(payload)
    if not upgradeCount then
        self:PushLaunchPowerState(player)
        self:_pushFeedback(player, "InvalidUpgradeCount", "", requestId, self._playerDataService and self._playerDataService:GetCoins(player) or 0)
        return
    end

    local requiredCoins = self:GetUpgradePackageCostByLevel(currentLevel, upgradeCount)
    local currentCoins = self._playerDataService and self._playerDataService:GetCoins(player) or 0
    if currentCoins < requiredCoins then
        self:PushLaunchPowerState(player)
        self:_pushFeedback(player, "InsufficientCoins", "", requestId, currentCoins)
        return
    end

    local didSpendCoins = true
    local nextCoins = currentCoins
    if self._currencyService then
        didSpendCoins, nextCoins = self._currencyService:AddCoins(player, -requiredCoins, "LaunchPowerUpgrade")
    end

    if not didSpendCoins then
        self:PushLaunchPowerState(player)
        self:_pushFeedback(player, "SpendFailed", "", requestId, currentCoins)
        return
    end

    growth.PowerLevel = currentLevel + upgradeCount
    self:_applyPlayerAttributes(player, growth.PowerLevel)
    self:PushLaunchPowerState(player)
    self:_pushFeedback(player, "Success", "", requestId, nextCoins)

    if self._playerDataService then
        task.spawn(function()
            if player.Parent == nil then
                return
            end

            local didSave = self._playerDataService:SavePlayerData(player)
            if not didSave then
                warn(string.format(
                    "[LaunchPowerService] SavePlayerData failed after launch power upgrade for userId=%d",
                    player.UserId
                ))
            end
        end)
    end
end

function LaunchPowerService:SetLaunchPowerLevel(player, level, options)
    local _playerData, growth = self:_getPlayerDataAndGrowth(player)
    if not growth then
        return false, "MissingData"
    end

    local previousLevel = math.max(getDefaultLevel(), math.floor(tonumber(growth.PowerLevel) or getDefaultLevel()))
    local normalizedLevel = math.max(getDefaultLevel(), math.floor(tonumber(level) or getDefaultLevel()))
    growth.PowerLevel = normalizedLevel
    self:_applyPlayerAttributes(player, normalizedLevel)

    if type(options) == "table" and options.ShouldSave == true then
        local didSave = not self._playerDataService or self._playerDataService:SavePlayerData(player)
        if not didSave then
            growth.PowerLevel = previousLevel
            self:_applyPlayerAttributes(player, previousLevel)
            if not (type(options) == "table" and options.SkipPushState == true) then
                self:PushLaunchPowerState(player)
            end
            return false, "SaveFailed"
        end
    end

    if not (type(options) == "table" and options.SkipPushState == true) then
        self:PushLaunchPowerState(player)
    end

    return true, normalizedLevel
end

function LaunchPowerService:ResetLaunchPower(player)
    local didSetLevel, setResult = self:SetLaunchPowerLevel(player, getDefaultLevel(), {
        ShouldSave = true,
    })
    if not didSetLevel then
        return false, setResult
    end

    return true, "StudioResetSuccess"
end

function LaunchPowerService:_handleRequestStudioResetLaunchPower(player)
    if not player then
        return
    end

    if not RunService:IsStudio() then
        self:_pushFeedback(player, "NotStudio", "", "", self._playerDataService and self._playerDataService:GetCoins(player) or 0)
        return
    end

    if not self:_canSendRequest(player) then
        self:_pushFeedback(player, "Debounced", "", "", self._playerDataService and self._playerDataService:GetCoins(player) or 0)
        return
    end

    local success, status = self:ResetLaunchPower(player)
    self:_pushFeedback(player, status, "", "", self._playerDataService and self._playerDataService:GetCoins(player) or 0)
    if not success then
        return
    end
end

function LaunchPowerService:Init(dependencies)
    self._playerDataService = dependencies.PlayerDataService
    self._currencyService = dependencies.CurrencyService

    local remoteEventService = dependencies.RemoteEventService
    self._launchPowerStateSyncEvent = remoteEventService:GetEvent("LaunchPowerStateSync")
    self._requestLaunchPowerStateSyncEvent = remoteEventService:GetEvent("RequestLaunchPowerStateSync")
    self._requestLaunchPowerUpgradeEvent = remoteEventService:GetEvent("RequestLaunchPowerUpgrade")
    self._requestStudioResetLaunchPowerEvent = remoteEventService:GetEvent("RequestStudioResetLaunchPower")
    self._launchPowerFeedbackEvent = remoteEventService:GetEvent("LaunchPowerFeedback")

    if self._requestLaunchPowerStateSyncEvent then
        self._requestLaunchPowerStateSyncEvent.OnServerEvent:Connect(function(player)
            self:_handleRequestLaunchPowerStateSync(player)
        end)
    end

    if self._requestLaunchPowerUpgradeEvent then
        self._requestLaunchPowerUpgradeEvent.OnServerEvent:Connect(function(player, payload)
            self:_handleRequestLaunchPowerUpgrade(player, payload)
        end)
    end

    if self._requestStudioResetLaunchPowerEvent then
        self._requestStudioResetLaunchPowerEvent.OnServerEvent:Connect(function(player)
            self:_handleRequestStudioResetLaunchPower(player)
        end)
    end
end

function LaunchPowerService:OnPlayerReady(player)
    local _playerData, growth = self:_getPlayerDataAndGrowth(player)
    if not growth then
        return
    end

    growth.PowerLevel = math.max(getDefaultLevel(), math.floor(tonumber(growth.PowerLevel) or getDefaultLevel()))
    self:_applyPlayerAttributes(player, growth.PowerLevel)
    self:PushLaunchPowerState(player)
end

function LaunchPowerService:OnPlayerRemoving(player)
    if not player then
        return
    end

    self._lastRequestClockByUserId[player.UserId] = nil
    player:SetAttribute("LaunchPowerLevel", nil)
    player:SetAttribute("LaunchPowerValue", nil)
end

function LaunchPowerService:ProcessReceipt(receiptInfo)
    local upgradeCount = getUpgradeCountByRobuxProductId(receiptInfo and receiptInfo.ProductId)
    if not upgradeCount then
        return false, nil
    end

    local player = Players:GetPlayerByUserId(math.max(0, math.floor(tonumber(receiptInfo and receiptInfo.PlayerId) or 0)))
    if not player then
        return true, Enum.ProductPurchaseDecision.NotProcessedYet
    end

    local _playerData, growth = self:_getPlayerDataAndGrowth(player)
    if not growth then
        return true, Enum.ProductPurchaseDecision.NotProcessedYet
    end

    local purchaseId = tostring(receiptInfo and receiptInfo.PurchaseId or "")
    local processedPurchaseIds = self:_getOrCreateProcessedLaunchPowerPurchaseIds(growth)
    if purchaseId ~= "" and processedPurchaseIds[purchaseId] then
        return true, Enum.ProductPurchaseDecision.PurchaseGranted
    end

    local previousLevel = math.max(getDefaultLevel(), math.floor(tonumber(growth.PowerLevel) or getDefaultLevel()))
    local previousProcessedAt = purchaseId ~= "" and processedPurchaseIds[purchaseId] or nil

    growth.PowerLevel = previousLevel + upgradeCount
    self:_applyPlayerAttributes(player, growth.PowerLevel)
    if purchaseId ~= "" then
        processedPurchaseIds[purchaseId] = os.time()
    end

    local didSave = not self._playerDataService or self._playerDataService:SavePlayerData(player)
    if not didSave then
        growth.PowerLevel = previousLevel
        self:_applyPlayerAttributes(player, previousLevel)
        if purchaseId ~= "" then
            if previousProcessedAt ~= nil then
                processedPurchaseIds[purchaseId] = previousProcessedAt
            else
                processedPurchaseIds[purchaseId] = nil
            end
        end
        self:PushLaunchPowerState(player)
        self:_pushFeedback(player, "SaveFailed", "", "", self._playerDataService and self._playerDataService:GetCoins(player) or 0)
        return true, Enum.ProductPurchaseDecision.NotProcessedYet
    end

    self:PushLaunchPowerState(player)
    self:_pushFeedback(player, "Success", "", "", self._playerDataService and self._playerDataService:GetCoins(player) or 0)
    return true, Enum.ProductPurchaseDecision.PurchaseGranted
end

return LaunchPowerService
