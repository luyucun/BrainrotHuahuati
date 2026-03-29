--[[
脚本名字: LaunchPowerService
脚本文件: LaunchPowerService.lua
脚本类型: ModuleScript
Studio放置路径: ServerScriptService/Services/LaunchPowerService
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
    local normalizedLevel = math.max(getDefaultLevel(), math.floor(tonumber(currentLevel) or getDefaultLevel()))
    local config = getConfig()
    local baseUpgradeCost = math.max(0, tonumber(config.BaseUpgradeCost) or 200)
    local multiplier = math.max(1, tonumber(config.UpgradeCostMultiplier) or 1.08)
    local exponent = math.max(0, normalizedLevel - getDefaultLevel())
    local rawCost = baseUpgradeCost * (multiplier ^ exponent)
    return math.max(0, math.ceil(rawCost - 1e-6))
end

function LaunchPowerService:GetUpgradePackageCostByLevel(currentLevel, upgradeCount)
    local normalizedLevel = math.max(getDefaultLevel(), math.floor(tonumber(currentLevel) or getDefaultLevel()))
    local normalizedUpgradeCount = math.max(1, math.floor(tonumber(upgradeCount) or 1))
    local totalCost = 0

    for offset = 0, normalizedUpgradeCount - 1 do
        totalCost += self:GetNextUpgradeCostByLevel(normalizedLevel + offset)
    end

    return math.max(0, totalCost)
end

function LaunchPowerService:_normalizeRequestedUpgradeCount(payload)
    local requestedCount = 1
    if type(payload) == "table" then
        requestedCount = math.max(1, math.floor(tonumber(payload.upgradeCount) or 1))
    end

    if requestedCount == 1 then
        return 1
    end

    if requestedCount == getBulkUpgradeLevelCount() then
        return requestedCount
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
    local nextLevel = currentLevel + 1
    local nextValue = self:GetLaunchPowerValueByLevel(nextLevel)
    local bulkUpgradeCount = getBulkUpgradeLevelCount()
    local bulkNextLevel = currentLevel + bulkUpgradeCount
    local bulkNextValue = self:GetLaunchPowerValueByLevel(bulkNextLevel)
    local currentCoins = self._playerDataService and self._playerDataService:GetCoins(player) or 0
    local config = getConfig()

    return {
        currentLevel = currentLevel,
        currentValue = currentValue,
        nextLevel = nextLevel,
        nextValue = nextValue,
        nextCost = self:GetNextUpgradeCostByLevel(currentLevel),
        bulkUpgradeCount = bulkUpgradeCount,
        bulkNextLevel = bulkNextLevel,
        bulkNextValue = bulkNextValue,
        bulkNextCost = self:GetUpgradePackageCostByLevel(currentLevel, bulkUpgradeCount),
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

function LaunchPowerService:_pushFeedback(player, status, message)
    if not (player and self._launchPowerFeedbackEvent) then
        return
    end

    self._launchPowerFeedbackEvent:FireClient(player, {
        status = tostring(status or "Unknown"),
        message = tostring(message or ""),
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

    if not self:_canSendRequest(player) then
        self:_pushFeedback(player, "Debounced", "")
        return
    end

    local _playerData, growth = self:_getPlayerDataAndGrowth(player)
    if not growth then
        self:_pushFeedback(player, "MissingData", "")
        return
    end

    local currentLevel = math.max(getDefaultLevel(), math.floor(tonumber(growth.PowerLevel) or getDefaultLevel()))
    growth.PowerLevel = currentLevel

    local upgradeCount = self:_normalizeRequestedUpgradeCount(payload)
    if not upgradeCount then
        self:PushLaunchPowerState(player)
        self:_pushFeedback(player, "InvalidUpgradeCount", "")
        return
    end

    local requiredCoins = self:GetUpgradePackageCostByLevel(currentLevel, upgradeCount)
    local currentCoins = self._playerDataService and self._playerDataService:GetCoins(player) or 0
    if currentCoins < requiredCoins then
        self:PushLaunchPowerState(player)
        self:_pushFeedback(player, "InsufficientCoins", "")
        return
    end

    local didSpendCoins = true
    if self._currencyService then
        didSpendCoins = select(1, self._currencyService:AddCoins(player, -requiredCoins, "LaunchPowerUpgrade"))
    end

    if not didSpendCoins then
        self:PushLaunchPowerState(player)
        self:_pushFeedback(player, "SpendFailed", "")
        return
    end

    growth.PowerLevel = currentLevel + upgradeCount
    self:_applyPlayerAttributes(player, growth.PowerLevel)

    local didSave = not self._playerDataService or self._playerDataService:SavePlayerData(player)
    self:PushLaunchPowerState(player)
    if not didSave then
        self:_pushFeedback(player, "SaveFailed", "")
        return
    end

    self:_pushFeedback(player, "Success", "")
end

function LaunchPowerService:Init(dependencies)
    self._playerDataService = dependencies.PlayerDataService
    self._currencyService = dependencies.CurrencyService

    local remoteEventService = dependencies.RemoteEventService
    self._launchPowerStateSyncEvent = remoteEventService:GetEvent("LaunchPowerStateSync")
    self._requestLaunchPowerStateSyncEvent = remoteEventService:GetEvent("RequestLaunchPowerStateSync")
    self._requestLaunchPowerUpgradeEvent = remoteEventService:GetEvent("RequestLaunchPowerUpgrade")
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

return LaunchPowerService
