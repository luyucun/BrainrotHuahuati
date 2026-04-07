--[[
脚本名字: RebirthService
脚本文件: RebirthService.lua
脚本类型: ModuleScript
Studio放置路径: ServerScriptService/Services/RebirthService
]]

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
        "[RebirthService] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local GameConfig = requireSharedModule("GameConfig")
local RebirthConfig = requireSharedModule("RebirthConfig")

local RebirthService = {}
RebirthService._playerDataService = nil
RebirthService._currencyService = nil
RebirthService._launchPowerService = nil
RebirthService._rebirthStateSyncEvent = nil
RebirthService._requestRebirthStateSyncEvent = nil
RebirthService._requestRebirthEvent = nil
RebirthService._rebirthFeedbackEvent = nil
RebirthService._lastRequestClockByUserId = {}

local function getDefaultLaunchPowerLevel()
    return math.max(1, math.floor(tonumber((GameConfig.LAUNCH_POWER or {}).DefaultLevel) or 1))
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

    if growth.PowerLevel == nil then
        growth.PowerLevel = getDefaultLaunchPowerLevel()
    end

    growth.RebirthLevel = math.max(0, math.floor(tonumber(growth.RebirthLevel) or 0))
    return growth
end

local function normalizeRebirthLevel(level)
    return RebirthConfig.NormalizeLevel(level)
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

local function ensureRebirthState(playerData)
    if type(playerData) ~= "table" then
        return nil
    end

    local rebirthState = playerData.RebirthState
    if type(rebirthState) ~= "table" then
        rebirthState = {}
        playerData.RebirthState = rebirthState
    end

    rebirthState.ProcessedPurchaseIds = normalizeProcessedPurchaseIds(rebirthState.ProcessedPurchaseIds)
    return rebirthState
end

local function copyFlatMap(sourceValue)
    local copy = {}
    if type(sourceValue) ~= "table" then
        return copy
    end

    for key, value in pairs(sourceValue) do
        copy[key] = value
    end

    return copy
end

function RebirthService:_getPlayerDataAndState(player)
    if not (self._playerDataService and player) then
        return nil, nil, nil
    end

    local playerData = self._playerDataService:GetPlayerData(player)
    if type(playerData) ~= "table" then
        return nil, nil, nil
    end

    return playerData, ensureGrowthTable(playerData), ensureRebirthState(playerData)
end

function RebirthService:GetRebirthLevel(player)
    local _playerData, growth = self:_getPlayerDataAndState(player)
    if not growth then
        return 0
    end

    local rebirthLevel = normalizeRebirthLevel(growth.RebirthLevel)
    growth.RebirthLevel = rebirthLevel
    return rebirthLevel
end

function RebirthService:GetRebirthBonusRateByLevel(rebirthLevel)
    return math.max(0, tonumber(RebirthConfig.GetBonusRateByLevel(rebirthLevel)) or 0)
end

function RebirthService:GetRebirthBonusRate(player)
    return self:GetRebirthBonusRateByLevel(self:GetRebirthLevel(player))
end

function RebirthService:GetNextRequiredCoinsByLevel(rebirthLevel)
    return math.max(0, math.floor(tonumber(RebirthConfig.GetRequiredCoinsForNextLevel(rebirthLevel)) or 0))
end

function RebirthService:_applyPlayerAttributes(player, rebirthLevel)
    if not player then
        return 0
    end

    local normalizedLevel = normalizeRebirthLevel(rebirthLevel)
    local bonusRate = self:GetRebirthBonusRateByLevel(normalizedLevel)
    player:SetAttribute("RebirthLevel", normalizedLevel)
    player:SetAttribute("RebirthBonusRate", bonusRate)
    return bonusRate
end

function RebirthService:_buildStatePayload(player)
    local rebirthLevel = self:GetRebirthLevel(player)
    local currentCoins = self._playerDataService and self._playerDataService:GetCoins(player) or 0
    local nextRebirthLevel = RebirthConfig.GetNextLevel(rebirthLevel)
    local currentBonusRate = self:GetRebirthBonusRateByLevel(rebirthLevel)
    local nextBonusRate = self:GetRebirthBonusRateByLevel(nextRebirthLevel)
    local nextRequiredCoins = self:GetNextRequiredCoinsByLevel(rebirthLevel)

    return {
        rebirthLevel = rebirthLevel,
        currentBonusRate = currentBonusRate,
        nextRebirthLevel = nextRebirthLevel,
        nextRequiredCoins = nextRequiredCoins,
        nextBonusRate = nextBonusRate,
        maxRebirthLevel = 0,
        isMaxLevel = false,
        currentCoins = math.max(0, tonumber(currentCoins) or 0),
        developerProductId = math.max(0, math.floor(tonumber(RebirthConfig.SkipProductId) or 0)),
        timestamp = os.clock(),
    }
end

function RebirthService:PushRebirthState(player)
    if not (player and self._rebirthStateSyncEvent) then
        return
    end

    self._rebirthStateSyncEvent:FireClient(player, self:_buildStatePayload(player))
end

function RebirthService:_pushFeedback(player, status, message)
    if not (player and self._rebirthFeedbackEvent) then
        return
    end

    self._rebirthFeedbackEvent:FireClient(player, {
        status = tostring(status or "Unknown"),
        message = tostring(message or ""),
        timestamp = os.clock(),
    })
end

function RebirthService:_canSendRequest(player)
    if not player then
        return false
    end

    local debounceSeconds = math.max(0.05, tonumber((GameConfig.REBIRTH or {}).RequestDebounceSeconds) or 0.35)
    local userId = player.UserId
    local nowClock = os.clock()
    local lastClock = tonumber(self._lastRequestClockByUserId[userId]) or 0
    if nowClock - lastClock < debounceSeconds then
        return false
    end

    self._lastRequestClockByUserId[userId] = nowClock
    return true
end

function RebirthService:_getLaunchPowerLevel(growth, player)
    local defaultLevel = getDefaultLaunchPowerLevel()
    if self._launchPowerService and type(self._launchPowerService.GetLaunchPowerLevel) == "function" then
        return math.max(defaultLevel, math.floor(tonumber(self._launchPowerService:GetLaunchPowerLevel(player)) or defaultLevel))
    end

    return math.max(defaultLevel, math.floor(tonumber(growth and growth.PowerLevel) or defaultLevel))
end

function RebirthService:_setLaunchPowerLevel(player, growth, powerLevel)
    local defaultLevel = getDefaultLaunchPowerLevel()
    local normalizedLevel = math.max(defaultLevel, math.floor(tonumber(powerLevel) or defaultLevel))

    if growth then
        growth.PowerLevel = normalizedLevel
    end

    if self._launchPowerService and type(self._launchPowerService.SetLaunchPowerLevel) == "function" then
        return self._launchPowerService:SetLaunchPowerLevel(player, normalizedLevel)
    end

    if player then
        player:SetAttribute("LaunchPowerLevel", normalizedLevel)
        player:SetAttribute("LaunchPowerValue", math.max(0, normalizedLevel - defaultLevel))
    end

    return true, normalizedLevel
end

function RebirthService:_grantRebirth(player, options)
    if not player then
        return false, "PlayerMissing"
    end

    local playerData, growth, rebirthState = self:_getPlayerDataAndState(player)
    if not (playerData and growth and rebirthState) then
        return false, "DataMissing"
    end

    local currentLevel = normalizeRebirthLevel(growth.RebirthLevel)
    growth.RebirthLevel = currentLevel

    local requiredCoins = math.max(0, math.floor(tonumber(type(options) == "table" and options.requiredCoins or 0) or 0))
    local shouldSpendCoins = requiredCoins > 0
    local purchaseId = type(options) == "table" and tostring(options.purchaseId or "") or ""
    local purchaseTimestamp = os.time()
    local previousCoins = self._playerDataService and self._playerDataService:GetCoins(player) or 0
    local previousLevel = currentLevel
    local previousPowerLevel = self:_getLaunchPowerLevel(growth, player)
    local previousProcessedPurchaseIds = copyFlatMap(rebirthState.ProcessedPurchaseIds)

    local function rollbackGrant()
        growth.RebirthLevel = previousLevel
        rebirthState.ProcessedPurchaseIds = previousProcessedPurchaseIds

        if shouldSpendCoins then
            if self._currencyService then
                self._currencyService:SetCoins(player, previousCoins, "RebirthRollback")
            elseif self._playerDataService then
                self._playerDataService:SetCoins(player, previousCoins)
            end
        end

        self:_setLaunchPowerLevel(player, growth, previousPowerLevel)
        self:_applyPlayerAttributes(player, previousLevel)
        self:PushRebirthState(player)
    end

    if shouldSpendCoins then
        local didSpendCoins = false
        if self._currencyService then
            didSpendCoins = self._currencyService:AddCoins(player, -requiredCoins, "RebirthCost")
        elseif self._playerDataService then
            local beforeCoins, nextCoins = self._playerDataService:SetCoins(player, previousCoins - requiredCoins)
            didSpendCoins = beforeCoins ~= nil and nextCoins ~= nil
        end

        if not didSpendCoins then
            self:PushRebirthState(player)
            return false, "SpendFailed"
        end
    end

    local nextLevel = RebirthConfig.GetNextLevel(currentLevel)
    growth.RebirthLevel = nextLevel
    if purchaseId ~= "" then
        rebirthState.ProcessedPurchaseIds[purchaseId] = purchaseTimestamp
    end
    local didResetLaunchPower, launchPowerStatus = self:_setLaunchPowerLevel(player, growth, getDefaultLaunchPowerLevel())
    if not didResetLaunchPower then
        rollbackGrant()
        return false, launchPowerStatus or "LaunchPowerResetFailed"
    end

    self:_applyPlayerAttributes(player, nextLevel)

    local didSave = not self._playerDataService or self._playerDataService:SavePlayerData(player)
    if not didSave then
        rollbackGrant()
        return false, "SaveFailed"
    end

    self:PushRebirthState(player)
    return true, "Success"
end

function RebirthService:_handleRequestRebirth(player)
    if not (player and self:_canSendRequest(player)) then
        return
    end

    local _playerData, growth = self:_getPlayerDataAndState(player)
    if not growth then
        return
    end

    local currentLevel = normalizeRebirthLevel(growth.RebirthLevel)
    growth.RebirthLevel = currentLevel

    local currentCoins = self._playerDataService and self._playerDataService:GetCoins(player) or 0
    local requiredCoins = self:GetNextRequiredCoinsByLevel(currentLevel)
    if currentCoins < requiredCoins then
        self:PushRebirthState(player)
        self:_pushFeedback(player, "RequirementNotMet", "")
        return
    end

    local didGrant, grantStatus = self:_grantRebirth(player, {
        requiredCoins = requiredCoins,
    })
    if not didGrant then
        self:_pushFeedback(player, grantStatus, "")
        return
    end

    self:_pushFeedback(player, "Success", tostring((GameConfig.REBIRTH or {}).SuccessTipText or "Rebirth successful!"))
end

function RebirthService:Init(dependencies)
    self._playerDataService = dependencies.PlayerDataService
    self._currencyService = dependencies.CurrencyService
    self._launchPowerService = dependencies.LaunchPowerService

    local remoteEventService = dependencies.RemoteEventService
    self._rebirthStateSyncEvent = remoteEventService:GetEvent("RebirthStateSync")
    self._requestRebirthStateSyncEvent = remoteEventService:GetEvent("RequestRebirthStateSync")
    self._requestRebirthEvent = remoteEventService:GetEvent("RequestRebirth")
    self._rebirthFeedbackEvent = remoteEventService:GetEvent("RebirthFeedback")

    if self._requestRebirthStateSyncEvent then
        self._requestRebirthStateSyncEvent.OnServerEvent:Connect(function(player)
            self:PushRebirthState(player)
        end)
    end

    if self._requestRebirthEvent then
        self._requestRebirthEvent.OnServerEvent:Connect(function(player)
            self:_handleRequestRebirth(player)
        end)
    end
end

function RebirthService:OnPlayerReady(player)
    local _playerData, growth = self:_getPlayerDataAndState(player)
    if not growth then
        return
    end

    growth.RebirthLevel = normalizeRebirthLevel(growth.RebirthLevel)
    self:_applyPlayerAttributes(player, growth.RebirthLevel)
    self:PushRebirthState(player)
end

function RebirthService:OnPlayerRemoving(player)
    if not player then
        return
    end

    self._lastRequestClockByUserId[player.UserId] = nil
    player:SetAttribute("RebirthLevel", nil)
    player:SetAttribute("RebirthBonusRate", nil)
end

function RebirthService:ProcessReceipt(receiptInfo)
    local productId = math.max(0, math.floor(tonumber(receiptInfo and receiptInfo.ProductId) or 0))
    local rebirthProductId = math.max(0, math.floor(tonumber(RebirthConfig.SkipProductId) or 0))
    if productId ~= rebirthProductId then
        return false, nil
    end

    local player = Players:GetPlayerByUserId(math.max(0, math.floor(tonumber(receiptInfo and receiptInfo.PlayerId) or 0)))
    if not player then
        return true, Enum.ProductPurchaseDecision.NotProcessedYet
    end

    local _playerData, _growth, rebirthState = self:_getPlayerDataAndState(player)
    if not rebirthState then
        return true, Enum.ProductPurchaseDecision.NotProcessedYet
    end

    local purchaseId = tostring(receiptInfo and receiptInfo.PurchaseId or "")
    local processedPurchaseIds = rebirthState.ProcessedPurchaseIds or {}
    if purchaseId ~= "" and processedPurchaseIds[purchaseId] then
        return true, Enum.ProductPurchaseDecision.PurchaseGranted
    end

    local didGrant, grantStatus = self:_grantRebirth(player, {
        purchaseId = purchaseId,
    })
    if not didGrant then
        if grantStatus == "SaveFailed" then
            return true, Enum.ProductPurchaseDecision.NotProcessedYet
        end

        self:_pushFeedback(player, "SaveFailed", "")
        return true, Enum.ProductPurchaseDecision.NotProcessedYet
    end

    self:_pushFeedback(player, "Success", tostring((GameConfig.REBIRTH or {}).SuccessTipText or "Rebirth successful!"))
    return true, Enum.ProductPurchaseDecision.PurchaseGranted
end

return RebirthService
