--[[
脚本名字: LaunchPowerUpgradeController
脚本文件: LaunchPowerUpgradeController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/LaunchPowerUpgradeController
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer

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
        "[LaunchPowerUpgradeController] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local function disconnectAll(connectionList)
    if type(connectionList) ~= "table" then
        return
    end

    for _, connection in ipairs(connectionList) do
        if connection then
            connection:Disconnect()
        end
    end
    table.clear(connectionList)
end

local function isLiveInstance(instance)
    return instance ~= nil and instance.Parent ~= nil
end

local ClientPredictionUtil = requireSharedModule("ClientPredictionUtil")
local FormatUtil = requireSharedModule("FormatUtil")
local GameConfig = requireSharedModule("GameConfig")
local RemoteNames = requireSharedModule("RemoteNames")

local indexControllerModule = script.Parent:FindFirstChild("IndexController")
if not (indexControllerModule and indexControllerModule:IsA("ModuleScript")) then
    local parentNode = script.Parent.Parent
    if parentNode then
        local fallbackModule = parentNode:FindFirstChild("IndexController")
        if fallbackModule and fallbackModule:IsA("ModuleScript") then
            indexControllerModule = fallbackModule
        end
    end
end

if not (indexControllerModule and indexControllerModule:IsA("ModuleScript")) then
    error("[LaunchPowerUpgradeController] 找不到 IndexController，无法复用渐变与按钮动效逻辑。")
end

local IndexController = require(indexControllerModule)

local LaunchPowerUpgradeController = {}
LaunchPowerUpgradeController.__index = LaunchPowerUpgradeController

local STARTUP_WARNING_GRACE_SECONDS = 2
local UPGRADE_MODAL_KEY = "Upgrade"
local PROMPT_MODEL_NAME = "Garamararam"
local PROMPT_NAME = "ProximityPrompt"
local UPGRADE_TIER_CONFIGS = {
    {
        RootName = "Upgrade1",
        CountField = "upgrade1Count",
        NextLevelField = "upgrade1NextLevel",
        NextValueField = "upgrade1NextValue",
        NextCostField = "upgrade1NextCost",
        ProductIdField = "upgrade1ProductId",
    },
    {
        RootName = "Upgrade2",
        CountField = "upgrade2Count",
        NextLevelField = "upgrade2NextLevel",
        NextValueField = "upgrade2NextValue",
        NextCostField = "upgrade2NextCost",
        ProductIdField = "upgrade2ProductId",
    },
    {
        RootName = "Upgrade3",
        CountField = "upgrade3Count",
        NextLevelField = "upgrade3NextLevel",
        NextValueField = "upgrade3NextValue",
        NextCostField = "upgrade3NextCost",
        ProductIdField = "upgrade3ProductId",
    },
}

local function setGuiButtonEnabled(button, enabled)
    if not (button and button:IsA("GuiButton")) then
        return
    end

    button.Active = enabled == true
    button.AutoButtonColor = enabled == true
    button.Selectable = enabled == true
end

local function getLaunchPowerConfig()
    return GameConfig.LAUNCH_POWER or {}
end

local function getDefaultLevel()
    return math.max(1, math.floor(tonumber(getLaunchPowerConfig().DefaultLevel) or 1))
end

local function getBulkUpgradeLevelCount()
    return math.max(1, math.floor(tonumber(getLaunchPowerConfig().BulkUpgradeLevelCount) or 10))
end

local function getMiddleUpgradeLevelCount()
    return math.max(1, math.floor(tonumber(getLaunchPowerConfig().MiddleUpgradeLevelCount) or 5))
end

local function getLargeUpgradeLevelCount()
    local configuredLarge = math.max(1, math.floor(tonumber(getLaunchPowerConfig().LargeUpgradeLevelCount) or getBulkUpgradeLevelCount()))
    return math.max(configuredLarge, getMiddleUpgradeLevelCount())
end

local function getRobuxProductIdByUpgradeCount(upgradeCount)
    local products = getLaunchPowerConfig().RobuxUpgradeProducts
    if type(products) ~= "table" then
        return 0
    end

    return math.max(
        0,
        math.floor(tonumber(products[math.max(1, math.floor(tonumber(upgradeCount) or 1))]) or 0)
    )
end

local function getSortedUniqueUpgradeCounts()
    local countMap = {}
    countMap[1] = true
    countMap[getMiddleUpgradeLevelCount()] = true
    countMap[getLargeUpgradeLevelCount()] = true

    local counts = {}
    for count in pairs(countMap) do
        table.insert(counts, count)
    end

    table.sort(counts, function(left, right)
        return left < right
    end)
    return counts
end

local function isLaunchPowerRobuxProductId(productId)
    local normalizedProductId = math.max(0, math.floor(tonumber(productId) or 0))
    if normalizedProductId <= 0 then
        return false
    end

    for _, count in ipairs(getSortedUniqueUpgradeCounts()) do
        if getRobuxProductIdByUpgradeCount(count) == normalizedProductId then
            return true
        end
    end

    return false
end

local function getBaseUpgradeCost()
    return math.max(0, math.ceil((tonumber(getLaunchPowerConfig().BaseUpgradeCost) or 200) - 1e-6))
end

local function getUpgradeCostSegments()
    local defaultLevel = getDefaultLevel()
    local baseTargetLevel = defaultLevel + 1
    local rawSegments = getLaunchPowerConfig().UpgradeCostSegments
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
            Multiplier = math.max(1, tonumber(getLaunchPowerConfig().UpgradeCostMultiplier) or 1.08),
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

local function getLaunchPowerValueByLevel(level)
    local normalizedLevel = math.max(getDefaultLevel(), math.floor(tonumber(level) or getDefaultLevel()))
    return math.max(0, normalizedLevel - getDefaultLevel())
end

local function getNextUpgradeCostByLevel(currentLevel)
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

local function getUpgradePackageCostByLevel(currentLevel, upgradeCount)
    local defaultLevel = getDefaultLevel()
    local normalizedLevel = math.max(defaultLevel, math.floor(tonumber(currentLevel) or defaultLevel))
    local normalizedUpgradeCount = math.max(1, math.floor(tonumber(upgradeCount) or 1))
    local totalCost = 0
    local nextUpgradeCost = getNextUpgradeCostByLevel(normalizedLevel)
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

local function cloneState(state)
    local currentLevel = math.max(getDefaultLevel(), math.floor(tonumber(state.currentLevel) or getDefaultLevel()))
    local currentValue = math.max(0, math.floor(tonumber(state.currentValue) or getLaunchPowerValueByLevel(currentLevel)))
    local upgrade2Count = math.max(1, math.floor(tonumber(state.upgrade2Count) or getMiddleUpgradeLevelCount()))
    local upgrade3Count = math.max(upgrade2Count, math.floor(tonumber(state.upgrade3Count) or getLargeUpgradeLevelCount()))
    local upgrade1Count = 1

    local upgrade1NextLevel = math.max(
        currentLevel + upgrade1Count,
        math.floor(tonumber(state.upgrade1NextLevel) or tonumber(state.nextLevel) or (currentLevel + upgrade1Count))
    )
    local upgrade2NextLevel = math.max(
        currentLevel + upgrade2Count,
        math.floor(tonumber(state.upgrade2NextLevel) or (currentLevel + upgrade2Count))
    )
    local upgrade3NextLevel = math.max(
        currentLevel + upgrade3Count,
        math.floor(tonumber(state.upgrade3NextLevel) or tonumber(state.bulkNextLevel) or (currentLevel + upgrade3Count))
    )

    return {
        currentLevel = currentLevel,
        currentValue = currentValue,
        nextLevel = upgrade1NextLevel,
        nextValue = math.max(
            getLaunchPowerValueByLevel(upgrade1NextLevel),
            math.floor(tonumber(state.upgrade1NextValue) or tonumber(state.nextValue) or getLaunchPowerValueByLevel(upgrade1NextLevel))
        ),
        nextCost = math.max(
            0,
            math.floor(tonumber(state.upgrade1NextCost) or tonumber(state.nextCost) or getUpgradePackageCostByLevel(currentLevel, upgrade1Count))
        ),
        bulkUpgradeCount = upgrade3Count,
        bulkNextLevel = upgrade3NextLevel,
        bulkNextValue = math.max(
            getLaunchPowerValueByLevel(upgrade3NextLevel),
            math.floor(tonumber(state.upgrade3NextValue) or tonumber(state.bulkNextValue) or getLaunchPowerValueByLevel(upgrade3NextLevel))
        ),
        bulkNextCost = math.max(
            0,
            math.floor(tonumber(state.upgrade3NextCost) or tonumber(state.bulkNextCost) or getUpgradePackageCostByLevel(currentLevel, upgrade3Count))
        ),
        upgrade1Count = upgrade1Count,
        upgrade1NextLevel = upgrade1NextLevel,
        upgrade1NextValue = math.max(
            getLaunchPowerValueByLevel(upgrade1NextLevel),
            math.floor(tonumber(state.upgrade1NextValue) or tonumber(state.nextValue) or getLaunchPowerValueByLevel(upgrade1NextLevel))
        ),
        upgrade1NextCost = math.max(
            0,
            math.floor(tonumber(state.upgrade1NextCost) or tonumber(state.nextCost) or getUpgradePackageCostByLevel(currentLevel, upgrade1Count))
        ),
        upgrade1ProductId = math.max(0, math.floor(tonumber(state.upgrade1ProductId) or getRobuxProductIdByUpgradeCount(upgrade1Count))),
        upgrade2Count = upgrade2Count,
        upgrade2NextLevel = upgrade2NextLevel,
        upgrade2NextValue = math.max(
            getLaunchPowerValueByLevel(upgrade2NextLevel),
            math.floor(tonumber(state.upgrade2NextValue) or getLaunchPowerValueByLevel(upgrade2NextLevel))
        ),
        upgrade2NextCost = math.max(
            0,
            math.floor(tonumber(state.upgrade2NextCost) or getUpgradePackageCostByLevel(currentLevel, upgrade2Count))
        ),
        upgrade2ProductId = math.max(0, math.floor(tonumber(state.upgrade2ProductId) or getRobuxProductIdByUpgradeCount(upgrade2Count))),
        upgrade3Count = upgrade3Count,
        upgrade3NextLevel = upgrade3NextLevel,
        upgrade3NextValue = math.max(
            getLaunchPowerValueByLevel(upgrade3NextLevel),
            math.floor(tonumber(state.upgrade3NextValue) or tonumber(state.bulkNextValue) or getLaunchPowerValueByLevel(upgrade3NextLevel))
        ),
        upgrade3NextCost = math.max(
            0,
            math.floor(tonumber(state.upgrade3NextCost) or tonumber(state.bulkNextCost) or getUpgradePackageCostByLevel(currentLevel, upgrade3Count))
        ),
        upgrade3ProductId = math.max(0, math.floor(tonumber(state.upgrade3ProductId) or getRobuxProductIdByUpgradeCount(upgrade3Count))),
        speedPerPoint = math.max(0, tonumber(state.speedPerPoint) or 1),
    }
end

function LaunchPowerUpgradeController.new(modalController)
    local self = setmetatable({}, LaunchPowerUpgradeController)
    self._modalController = modalController
    self._started = false
    self._persistentConnections = {}
    self._uiConnections = {}
    self._didWarnByKey = {}
    self._rebindQueued = false
    self._startupWarnAt = 0
    self._stateSyncEvent = nil
    self._requestStateSyncEvent = nil
    self._requestUpgradeEvent = nil
    self._feedbackEvent = nil
    self._coinChangedEvent = nil
    self._mainGui = nil
    self._topShopRoot = nil
    self._openButton = nil
    self._upgradeRoot = nil
    self._closeButton = nil
    self._cashNumLabel = nil
    self._scrollingFrame = nil
    self._upgradeCards = {}
    local defaultLevel = getDefaultLevel()
    local defaultValue = getLaunchPowerValueByLevel(defaultLevel)
    local middleUpgradeCount = getMiddleUpgradeLevelCount()
    local largeUpgradeCount = getLargeUpgradeLevelCount()
    self._state = {
        currentLevel = defaultLevel,
        currentValue = defaultValue,
        nextLevel = defaultLevel + 1,
        nextValue = getLaunchPowerValueByLevel(defaultLevel + 1),
        nextCost = getUpgradePackageCostByLevel(defaultLevel, 1),
        bulkUpgradeCount = largeUpgradeCount,
        bulkNextLevel = defaultLevel + largeUpgradeCount,
        bulkNextValue = getLaunchPowerValueByLevel(defaultLevel + largeUpgradeCount),
        bulkNextCost = getUpgradePackageCostByLevel(defaultLevel, largeUpgradeCount),
        upgrade1Count = 1,
        upgrade1NextLevel = defaultLevel + 1,
        upgrade1NextValue = getLaunchPowerValueByLevel(defaultLevel + 1),
        upgrade1NextCost = getUpgradePackageCostByLevel(defaultLevel, 1),
        upgrade1ProductId = getRobuxProductIdByUpgradeCount(1),
        upgrade2Count = middleUpgradeCount,
        upgrade2NextLevel = defaultLevel + middleUpgradeCount,
        upgrade2NextValue = getLaunchPowerValueByLevel(defaultLevel + middleUpgradeCount),
        upgrade2NextCost = getUpgradePackageCostByLevel(defaultLevel, middleUpgradeCount),
        upgrade2ProductId = getRobuxProductIdByUpgradeCount(middleUpgradeCount),
        upgrade3Count = largeUpgradeCount,
        upgrade3NextLevel = defaultLevel + largeUpgradeCount,
        upgrade3NextValue = getLaunchPowerValueByLevel(defaultLevel + largeUpgradeCount),
        upgrade3NextCost = getUpgradePackageCostByLevel(defaultLevel, largeUpgradeCount),
        upgrade3ProductId = getRobuxProductIdByUpgradeCount(largeUpgradeCount),
        speedPerPoint = 1,
    }
    self._currentCoins = 0
    self._pendingUpgradeRequestId = nil
    self._indexHelper = IndexController.new(nil)
    return self
end

function LaunchPowerUpgradeController:_warnOnce(key, message)
    if self._didWarnByKey[key] then
        return
    end

    self._didWarnByKey[key] = true
    warn(message)
end

function LaunchPowerUpgradeController:_shouldWarnBindingIssues()
    return os.clock() >= (self._startupWarnAt or 0)
end

function LaunchPowerUpgradeController:_getPlayerGui()
    return localPlayer:FindFirstChild("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
end

function LaunchPowerUpgradeController:_getMainGui()
    local playerGui = self:_getPlayerGui()
    if not playerGui then
        return nil
    end

    local mainGui = playerGui:FindFirstChild("Main")
    if mainGui then
        return mainGui
    end

    return playerGui:FindFirstChild("Main", true)
end

function LaunchPowerUpgradeController:_findDescendantByNames(root, names)
    return self._indexHelper:_findDescendantByNames(root, names)
end

function LaunchPowerUpgradeController:_resolveInteractiveNode(node)
    return self._indexHelper:_resolveInteractiveNode(node)
end

function LaunchPowerUpgradeController:_bindButtonFx(interactiveNode, options, connectionBucket)
    self._indexHelper:_bindButtonFx(interactiveNode, options, connectionBucket)
end

function LaunchPowerUpgradeController:_isUpgradeModalOpen()
    if self._modalController and self._modalController.IsModalOpen then
        return self._modalController:IsModalOpen(UPGRADE_MODAL_KEY)
    end

    return isLiveInstance(self._upgradeRoot) and self._upgradeRoot.Visible == true
end

function LaunchPowerUpgradeController:_getHiddenNodesForModal()
    local hiddenNodes = {}
    if not self._mainGui then
        return hiddenNodes
    end

    for _, node in ipairs(self._mainGui:GetChildren()) do
        if node and node ~= self._upgradeRoot then
            table.insert(hiddenNodes, node)
        end
    end

    return hiddenNodes
end

function LaunchPowerUpgradeController:_clearUiBindings()
    disconnectAll(self._uiConnections)
end

function LaunchPowerUpgradeController:_formatCurrency(value)
    return FormatUtil.FormatCompactCurrencyCeil(tonumber(value) or 0)
end

function LaunchPowerUpgradeController:_hasPendingUpgrade()
    return type(self._pendingUpgradeRequestId) == "string" and self._pendingUpgradeRequestId ~= ""
end

function LaunchPowerUpgradeController:_getTierDefaultCountByIndex(tierIndex)
    if tierIndex == 1 then
        return 1
    end
    if tierIndex == 2 then
        return getMiddleUpgradeLevelCount()
    end
    return getLargeUpgradeLevelCount()
end

function LaunchPowerUpgradeController:_getNormalizedUpgradeCountForTier(tierIndex)
    local tierConfig = UPGRADE_TIER_CONFIGS[tierIndex]
    if not tierConfig then
        return nil
    end

    return math.max(
        1,
        math.floor(
            tonumber(self._state[tierConfig.CountField]) or self:_getTierDefaultCountByIndex(tierIndex)
        )
    )
end

function LaunchPowerUpgradeController:_getTierConfigByUpgradeCount(upgradeCount)
    local normalizedUpgradeCount = math.max(1, math.floor(tonumber(upgradeCount) or 1))
    for tierIndex, tierConfig in ipairs(UPGRADE_TIER_CONFIGS) do
        if normalizedUpgradeCount == self:_getNormalizedUpgradeCountForTier(tierIndex) then
            return tierConfig, tierIndex
        end
    end

    return nil, nil
end

function LaunchPowerUpgradeController:_getRequiredCoinsForUpgradeCount(upgradeCount)
    local tierConfig = self:_getTierConfigByUpgradeCount(upgradeCount)
    if not tierConfig then
        return nil
    end

    return math.max(0, math.floor(tonumber(self._state[tierConfig.NextCostField]) or 0))
end

function LaunchPowerUpgradeController:_getProductIdForUpgradeCount(upgradeCount)
    local tierConfig = self:_getTierConfigByUpgradeCount(upgradeCount)
    if not tierConfig then
        return 0
    end

    return math.max(0, math.floor(tonumber(self._state[tierConfig.ProductIdField]) or 0))
end

function LaunchPowerUpgradeController:_promptRobuxUpgrade(upgradeCount)
    if self:_hasPendingUpgrade() then
        return
    end

    local productId = self:_getProductIdForUpgradeCount(upgradeCount)
    if productId <= 0 then
        return
    end

    local success, err = pcall(function()
        MarketplaceService:PromptProductPurchase(localPlayer, productId)
    end)
    if not success then
        warn(string.format(
            "[LaunchPowerUpgradeController] 打开弹射力升级购买弹窗失败 productId=%d err=%s",
            productId,
            tostring(err)
        ))
    end
end

function LaunchPowerUpgradeController:_applyCoinSnapshot(snapshot)
    if type(snapshot) ~= "table" then
        return
    end

    self._currentCoins = math.max(0, tonumber(snapshot.effectiveCoins) or 0)
    self:_renderCashLabel()
    self:_renderUpgradeCard()
end

function LaunchPowerUpgradeController:_buildPredictedState(upgradeCount)
    local currentLevel = math.max(getDefaultLevel(), math.floor(tonumber(self._state.currentLevel) or getDefaultLevel()))
    local normalizedUpgradeCount = math.max(1, math.floor(tonumber(upgradeCount) or 1))
    local upgradedLevel = currentLevel + normalizedUpgradeCount
    local upgrade1Count = 1
    local upgrade2Count = math.max(1, math.floor(tonumber(self._state.upgrade2Count) or getMiddleUpgradeLevelCount()))
    local upgrade3Count = math.max(upgrade2Count, math.floor(tonumber(self._state.upgrade3Count) or getLargeUpgradeLevelCount()))
    local upgrade1NextLevel = upgradedLevel + upgrade1Count
    local upgrade2NextLevel = upgradedLevel + upgrade2Count
    local upgrade3NextLevel = upgradedLevel + upgrade3Count

    return {
        currentLevel = upgradedLevel,
        currentValue = getLaunchPowerValueByLevel(upgradedLevel),
        nextLevel = upgrade1NextLevel,
        nextValue = getLaunchPowerValueByLevel(upgrade1NextLevel),
        nextCost = getUpgradePackageCostByLevel(upgradedLevel, upgrade1Count),
        bulkUpgradeCount = upgrade3Count,
        bulkNextLevel = upgrade3NextLevel,
        bulkNextValue = getLaunchPowerValueByLevel(upgrade3NextLevel),
        bulkNextCost = getUpgradePackageCostByLevel(upgradedLevel, upgrade3Count),
        upgrade1Count = upgrade1Count,
        upgrade1NextLevel = upgrade1NextLevel,
        upgrade1NextValue = getLaunchPowerValueByLevel(upgrade1NextLevel),
        upgrade1NextCost = getUpgradePackageCostByLevel(upgradedLevel, upgrade1Count),
        upgrade1ProductId = getRobuxProductIdByUpgradeCount(upgrade1Count),
        upgrade2Count = upgrade2Count,
        upgrade2NextLevel = upgrade2NextLevel,
        upgrade2NextValue = getLaunchPowerValueByLevel(upgrade2NextLevel),
        upgrade2NextCost = getUpgradePackageCostByLevel(upgradedLevel, upgrade2Count),
        upgrade2ProductId = getRobuxProductIdByUpgradeCount(upgrade2Count),
        upgrade3Count = upgrade3Count,
        upgrade3NextLevel = upgrade3NextLevel,
        upgrade3NextValue = getLaunchPowerValueByLevel(upgrade3NextLevel),
        upgrade3NextCost = getUpgradePackageCostByLevel(upgradedLevel, upgrade3Count),
        upgrade3ProductId = getRobuxProductIdByUpgradeCount(upgrade3Count),
        speedPerPoint = math.max(0, tonumber(self._state.speedPerPoint) or 1),
    }
end

function LaunchPowerUpgradeController:_rollbackPendingUpgrade(request, shouldRequestStateSync)
    if request and request.Metadata and request.Metadata.previousState then
        self._state = cloneState(request.Metadata.previousState)
    end

    self._pendingUpgradeRequestId = nil
    self:_renderAll()

    if shouldRequestStateSync == true and self._requestStateSyncEvent then
        self._requestStateSyncEvent:FireServer()
    end
end

function LaunchPowerUpgradeController:_renderCashLabel()
    if self._cashNumLabel and self._cashNumLabel:IsA("TextLabel") then
        self._cashNumLabel.Text = self:_formatCurrency(self._currentCoins)
    end
end

function LaunchPowerUpgradeController:_renderUpgradeCard()
    local currentValue = tostring(math.max(0, math.floor(tonumber(self._state.currentValue) or 0)))
    local hasPendingUpgrade = self:_hasPendingUpgrade()

    for tierIndex, tierConfig in ipairs(UPGRADE_TIER_CONFIGS) do
        local card = self._upgradeCards[tierIndex]
        if card then
            local nextCost = math.max(0, math.floor(tonumber(self._state[tierConfig.NextCostField]) or 0))
            local nextValue = tostring(math.max(0, math.floor(tonumber(self._state[tierConfig.NextValueField]) or 0)))
            local productId = math.max(0, math.floor(tonumber(self._state[tierConfig.ProductIdField]) or 0))

            if card.CoinButtonTextLabel and card.CoinButtonTextLabel:IsA("TextLabel") then
                card.CoinButtonTextLabel.Text = self:_formatCurrency(nextCost)
            elseif card.CoinButtonRoot and card.CoinButtonRoot:IsA("TextButton") then
                card.CoinButtonRoot.Text = self:_formatCurrency(nextCost)
            end

            if card.CurrentNumLabel and card.CurrentNumLabel:IsA("TextLabel") then
                card.CurrentNumLabel.Text = currentValue
            end

            if card.NextNumLabel and card.NextNumLabel:IsA("TextLabel") then
                card.NextNumLabel.Text = nextValue
            end

            setGuiButtonEnabled(
                card.CoinButton,
                not hasPendingUpgrade and self._currentCoins >= nextCost
            )
            setGuiButtonEnabled(
                card.RobuxButton,
                not hasPendingUpgrade and productId > 0
            )
        end
    end
end

function LaunchPowerUpgradeController:_renderAll()
    self:_renderCashLabel()
    self:_renderUpgradeCard()
end

function LaunchPowerUpgradeController:_applyStatePayload(payload)
    if type(payload) ~= "table" then
        return
    end

    self._state.currentLevel = math.max(getDefaultLevel(), math.floor(tonumber(payload.currentLevel) or getDefaultLevel()))
    self._state.currentValue = math.max(
        getLaunchPowerValueByLevel(self._state.currentLevel),
        math.floor(tonumber(payload.currentValue) or getLaunchPowerValueByLevel(self._state.currentLevel))
    )

    local upgrade1Count = 1
    local upgrade2Count = math.max(
        1,
        math.floor(tonumber(payload.upgrade2Count) or getMiddleUpgradeLevelCount())
    )
    local upgrade3Count = math.max(
        upgrade2Count,
        math.floor(
            tonumber(payload.upgrade3Count)
                or tonumber(payload.bulkUpgradeCount)
                or getLargeUpgradeLevelCount()
        )
    )

    self._state.upgrade1Count = upgrade1Count
    self._state.upgrade2Count = upgrade2Count
    self._state.upgrade3Count = upgrade3Count

    self._state.upgrade1NextLevel = math.max(
        self._state.currentLevel + upgrade1Count,
        math.floor(tonumber(payload.upgrade1NextLevel) or tonumber(payload.nextLevel) or (self._state.currentLevel + upgrade1Count))
    )
    self._state.upgrade2NextLevel = math.max(
        self._state.currentLevel + upgrade2Count,
        math.floor(tonumber(payload.upgrade2NextLevel) or (self._state.currentLevel + upgrade2Count))
    )
    self._state.upgrade3NextLevel = math.max(
        self._state.currentLevel + upgrade3Count,
        math.floor(tonumber(payload.upgrade3NextLevel) or tonumber(payload.bulkNextLevel) or (self._state.currentLevel + upgrade3Count))
    )

    self._state.upgrade1NextValue = math.max(
        getLaunchPowerValueByLevel(self._state.upgrade1NextLevel),
        math.floor(
            tonumber(payload.upgrade1NextValue)
                or tonumber(payload.nextValue)
                or getLaunchPowerValueByLevel(self._state.upgrade1NextLevel)
        )
    )
    self._state.upgrade2NextValue = math.max(
        getLaunchPowerValueByLevel(self._state.upgrade2NextLevel),
        math.floor(tonumber(payload.upgrade2NextValue) or getLaunchPowerValueByLevel(self._state.upgrade2NextLevel))
    )
    self._state.upgrade3NextValue = math.max(
        getLaunchPowerValueByLevel(self._state.upgrade3NextLevel),
        math.floor(
            tonumber(payload.upgrade3NextValue)
                or tonumber(payload.bulkNextValue)
                or getLaunchPowerValueByLevel(self._state.upgrade3NextLevel)
        )
    )

    self._state.upgrade1NextCost = math.max(
        0,
        math.floor(
            tonumber(payload.upgrade1NextCost)
                or tonumber(payload.nextCost)
                or getUpgradePackageCostByLevel(self._state.currentLevel, upgrade1Count)
        )
    )
    self._state.upgrade2NextCost = math.max(
        0,
        math.floor(tonumber(payload.upgrade2NextCost) or getUpgradePackageCostByLevel(self._state.currentLevel, upgrade2Count))
    )
    self._state.upgrade3NextCost = math.max(
        0,
        math.floor(
            tonumber(payload.upgrade3NextCost)
                or tonumber(payload.bulkNextCost)
                or getUpgradePackageCostByLevel(self._state.currentLevel, upgrade3Count)
        )
    )

    self._state.upgrade1ProductId = math.max(0, math.floor(tonumber(payload.upgrade1ProductId) or getRobuxProductIdByUpgradeCount(upgrade1Count)))
    self._state.upgrade2ProductId = math.max(0, math.floor(tonumber(payload.upgrade2ProductId) or getRobuxProductIdByUpgradeCount(upgrade2Count)))
    self._state.upgrade3ProductId = math.max(0, math.floor(tonumber(payload.upgrade3ProductId) or getRobuxProductIdByUpgradeCount(upgrade3Count)))

    self._state.nextLevel = self._state.upgrade1NextLevel
    self._state.nextValue = self._state.upgrade1NextValue
    self._state.nextCost = self._state.upgrade1NextCost
    self._state.bulkUpgradeCount = self._state.upgrade3Count
    self._state.bulkNextLevel = self._state.upgrade3NextLevel
    self._state.bulkNextValue = self._state.upgrade3NextValue
    self._state.bulkNextCost = self._state.upgrade3NextCost
    self._state.speedPerPoint = math.max(0, tonumber(payload.speedPerPoint) or 1)

    self:_renderAll()
end

function LaunchPowerUpgradeController:_requestUpgrade(upgradeCount)
    if self:_hasPendingUpgrade() then
        return
    end
    if not (self._requestUpgradeEvent and self._requestUpgradeEvent:IsA("RemoteEvent")) then
        return
    end

    local normalizedUpgradeCount = math.max(1, math.floor(tonumber(upgradeCount) or 1))
    local requiredCoins = self:_getRequiredCoinsForUpgradeCount(normalizedUpgradeCount)
    if requiredCoins == nil then
        return
    end

    if requiredCoins > math.max(0, tonumber(self._currentCoins) or 0) then
        return
    end

    local requestId = ClientPredictionUtil:BeginRequest({
        key = "LaunchPowerUpgrade",
        prefix = "LaunchPowerUpgrade",
        coinDelta = -requiredCoins,
        timeoutSeconds = 5,
        metadata = {
            previousState = cloneState(self._state),
        },
        onTimeout = function(request)
            self:_rollbackPendingUpgrade(request, true)
        end,
    })
    if not requestId then
        return
    end

    self._pendingUpgradeRequestId = requestId
    self._state = self:_buildPredictedState(normalizedUpgradeCount)
    self:_renderAll()

    self._requestUpgradeEvent:FireServer({
        requestId = requestId,
        upgradeCount = normalizedUpgradeCount,
    })
end

function LaunchPowerUpgradeController:_handleFeedback(payload)
    if type(payload) ~= "table" then
        return
    end

    local status = tostring(payload.status or "")
    local requestId = tostring(payload.requestId or self._pendingUpgradeRequestId or "")
    local isSuccessLike = status == "Success" or status == "RobuxPurchaseGranted"
    if isSuccessLike then
        if requestId ~= "" then
            ClientPredictionUtil:ResolveRequest(requestId, {
                acknowledgeCoinDelta = true,
                authoritativeCoins = payload.currentCoins,
            })
        end

        if requestId == self._pendingUpgradeRequestId then
            self._pendingUpgradeRequestId = nil
            self:_renderAll()
        end
        return
    end

    local rejectedRequest = nil
    if requestId ~= "" then
        rejectedRequest = ClientPredictionUtil:RejectRequest(requestId, {
            authoritativeCoins = payload.currentCoins,
        })
    end

    if requestId == self._pendingUpgradeRequestId then
        self:_rollbackPendingUpgrade(rejectedRequest, false)
    end

    if self._requestStateSyncEvent then
        self._requestStateSyncEvent:FireServer()
    end
end

function LaunchPowerUpgradeController:OpenUpgradeModal()
    if not isLiveInstance(self._upgradeRoot) and not self:_bindMainUi() then
        return
    end

    self:_renderAll()

    if self._modalController then
        if not self:_isUpgradeModalOpen() then
            self._modalController:OpenModal(UPGRADE_MODAL_KEY, self._upgradeRoot, {
                HiddenNodes = self:_getHiddenNodesForModal(),
            })
        end
    elseif self._upgradeRoot and self._upgradeRoot:IsA("GuiObject") then
        self._upgradeRoot.Visible = true
    end
end

function LaunchPowerUpgradeController:CloseUpgradeModal()
    if not isLiveInstance(self._upgradeRoot) then
        return
    end

    if self._modalController then
        self._modalController:CloseModal(UPGRADE_MODAL_KEY)
    elseif self._upgradeRoot and self._upgradeRoot:IsA("GuiObject") then
        self._upgradeRoot.Visible = false
    end
end

function LaunchPowerUpgradeController:_findUpgradePromptModel()
    local model = Workspace:FindFirstChild(PROMPT_MODEL_NAME) or Workspace:FindFirstChild(PROMPT_MODEL_NAME, true)
    if model and model:IsA("Model") then
        return model
    end

    return nil
end

function LaunchPowerUpgradeController:_isUpgradeOpenPrompt(prompt)
    if not (prompt and prompt:IsA("ProximityPrompt")) then
        return false
    end

    if prompt.Name ~= PROMPT_NAME then
        return false
    end

    local promptModel = self:_findUpgradePromptModel()
    if not promptModel then
        return false
    end

    return prompt:IsDescendantOf(promptModel)
end

function LaunchPowerUpgradeController:_bindMainUi()
    local mainGui = self:_getMainGui()
    if not mainGui then
        if self:_shouldWarnBindingIssues() then
            self:_warnOnce("MissingMain", "[LaunchPowerUpgradeController] 找不到 Main UI，弹射力升级面板暂不可用。")
        end
        self:_clearUiBindings()
        return false
    end

    self._mainGui = mainGui
    local topRoot = self:_findDescendantByNames(mainGui, { "Top" })
    self._topShopRoot = topRoot and self:_findDescendantByNames(topRoot, { "Shop" }) or nil
    self._openButton = self:_resolveInteractiveNode(self._topShopRoot)
    self._upgradeRoot = self:_findDescendantByNames(mainGui, { "Upgrade" })
    if not self._upgradeRoot then
        if self:_shouldWarnBindingIssues() then
            self:_warnOnce("MissingUpgradeRoot", "[LaunchPowerUpgradeController] 找不到 Main/Upgrade，弹射力升级面板未启动。")
        end
        self:_clearUiBindings()
        return false
    end

    local titleRoot = self:_findDescendantByNames(self._upgradeRoot, { "Title" })
    local equipInfoRoot = self:_findDescendantByNames(self._upgradeRoot, { "Equipinfo", "EquipInfo" })
    self._closeButton = titleRoot and self:_findDescendantByNames(titleRoot, { "CloseButton" }) or nil
    self._cashNumLabel = titleRoot and self:_findDescendantByNames(titleRoot, { "CashNum" }) or nil
    self._scrollingFrame = equipInfoRoot and self:_findDescendantByNames(equipInfoRoot, { "ScrollingFrame" }) or nil
    self._upgradeCards = {}
    for tierIndex, tierConfig in ipairs(UPGRADE_TIER_CONFIGS) do
        local cardRoot = self._scrollingFrame and self:_findDescendantByNames(self._scrollingFrame, { tierConfig.RootName }) or nil
        local coinButtonRoot = cardRoot and self:_findDescendantByNames(cardRoot, { "BuyButton" }) or nil
        local coinButton = self:_resolveInteractiveNode(coinButtonRoot)
        local coinButtonTextLabel = coinButtonRoot and self:_findDescendantByNames(coinButtonRoot, { "Text" }) or nil
        local robuxButtonRoot = cardRoot and self:_findDescendantByNames(cardRoot, { "RBuyButton" }) or nil
        local robuxButton = self:_resolveInteractiveNode(robuxButtonRoot)
        local currentNumRoot = cardRoot and self:_findDescendantByNames(cardRoot, { "Num1Bg" }) or nil
        local nextNumRoot = cardRoot and self:_findDescendantByNames(cardRoot, { "Num2Bg" }) or nil
        local currentNumLabel = currentNumRoot and self:_findDescendantByNames(currentNumRoot, { "Num" }) or nil
        local nextNumLabel = nextNumRoot and self:_findDescendantByNames(nextNumRoot, { "Num" }) or nil
        self._upgradeCards[tierIndex] = {
            Root = cardRoot,
            CoinButtonRoot = coinButtonRoot,
            CoinButton = coinButton,
            CoinButtonTextLabel = coinButtonTextLabel,
            RobuxButtonRoot = robuxButtonRoot,
            RobuxButton = robuxButton,
            CurrentNumLabel = currentNumLabel,
            NextNumLabel = nextNumLabel,
        }
    end

    self:_clearUiBindings()

    if self._openButton then
        self._openButton:SetAttribute("DisableUiClickSound", true)
        table.insert(self._uiConnections, self._openButton.Activated:Connect(function()
            self:OpenUpgradeModal()
        end))
    else
        if self:_shouldWarnBindingIssues() then
            self:_warnOnce("MissingShopButton", "[LaunchPowerUpgradeController] 找不到 Main/Top/Shop，弹射力升级入口未绑定。")
        end
    end

    local closeInteractive = self:_resolveInteractiveNode(self._closeButton)
    if closeInteractive then
        table.insert(self._uiConnections, closeInteractive.Activated:Connect(function()
            self:CloseUpgradeModal()
        end))
        self:_bindButtonFx(closeInteractive, {
            ScaleTarget = self._closeButton,
            RotationTarget = self._closeButton,
            HoverScale = 1.12,
            PressScale = 0.92,
            HoverRotation = 20,
            DisableClickSound = true,
        }, self._uiConnections)
    else
        if self:_shouldWarnBindingIssues() then
            self:_warnOnce("MissingCloseButton", "[LaunchPowerUpgradeController] 找不到 Main/Upgrade/Title/CloseButton。")
        end
    end

    for tierIndex, tierConfig in ipairs(UPGRADE_TIER_CONFIGS) do
        local card = self._upgradeCards[tierIndex]
        local capturedTierIndex = tierIndex
        local tierLabel = tierConfig.RootName
        if card and card.CoinButton then
            table.insert(self._uiConnections, card.CoinButton.Activated:Connect(function()
                self:_requestUpgrade(self:_getNormalizedUpgradeCountForTier(capturedTierIndex))
            end))
            self:_bindButtonFx(card.CoinButton, {
                ScaleTarget = card.CoinButtonRoot or card.CoinButton,
                HoverScale = 1.05,
                PressScale = 0.93,
                HoverRotation = 0,
            }, self._uiConnections)
        else
            if self:_shouldWarnBindingIssues() then
                self:_warnOnce(
                    string.format("MissingCoinBuyButton_%s", tierLabel),
                    string.format("[LaunchPowerUpgradeController] 找不到 Main/Upgrade/.../%s/BuyButton。", tierLabel)
                )
            end
        end

        if card and card.RobuxButton then
            table.insert(self._uiConnections, card.RobuxButton.Activated:Connect(function()
                self:_promptRobuxUpgrade(self:_getNormalizedUpgradeCountForTier(capturedTierIndex))
            end))
            self:_bindButtonFx(card.RobuxButton, {
                ScaleTarget = card.RobuxButtonRoot or card.RobuxButton,
                HoverScale = 1.05,
                PressScale = 0.93,
                HoverRotation = 0,
            }, self._uiConnections)
        else
            if self:_shouldWarnBindingIssues() then
                self:_warnOnce(
                    string.format("MissingRobuxBuyButton_%s", tierLabel),
                    string.format("[LaunchPowerUpgradeController] 找不到 Main/Upgrade/.../%s/RBuyButton。", tierLabel)
                )
            end
        end
    end

    self:_renderAll()
    return true
end

function LaunchPowerUpgradeController:_queueRebind()
    if self._rebindQueued then
        return
    end

    self._rebindQueued = true
    task.defer(function()
        self._rebindQueued = false
        self:_bindMainUi()
    end)
end

function LaunchPowerUpgradeController:_scheduleRetryBind()
    task.spawn(function()
        local deadline = os.clock() + 12
        repeat
            if self:_bindMainUi() then
                return
            end
            task.wait(1)
        until os.clock() >= deadline
    end)
end

function LaunchPowerUpgradeController:Start()
    if self._started then
        return
    end

    self._started = true
    self._startupWarnAt = os.clock() + STARTUP_WARNING_GRACE_SECONDS

    local eventsRoot = ReplicatedStorage:WaitForChild(RemoteNames.RootFolder)
    local systemEvents = eventsRoot:WaitForChild(RemoteNames.SystemEventsFolder)
    local currencyEvents = eventsRoot:WaitForChild(RemoteNames.CurrencyEventsFolder)

    self._stateSyncEvent = systemEvents:FindFirstChild(RemoteNames.System.LaunchPowerStateSync)
        or systemEvents:WaitForChild(RemoteNames.System.LaunchPowerStateSync, 10)
    self._requestStateSyncEvent = systemEvents:FindFirstChild(RemoteNames.System.RequestLaunchPowerStateSync)
        or systemEvents:WaitForChild(RemoteNames.System.RequestLaunchPowerStateSync, 10)
    self._requestUpgradeEvent = systemEvents:FindFirstChild(RemoteNames.System.RequestLaunchPowerUpgrade)
        or systemEvents:WaitForChild(RemoteNames.System.RequestLaunchPowerUpgrade, 10)
    self._feedbackEvent = systemEvents:FindFirstChild(RemoteNames.System.LaunchPowerFeedback)
        or systemEvents:WaitForChild(RemoteNames.System.LaunchPowerFeedback, 10)
    self._coinChangedEvent = currencyEvents:FindFirstChild(RemoteNames.Currency.CoinChanged)
        or currencyEvents:WaitForChild(RemoteNames.Currency.CoinChanged, 10)

    if self._stateSyncEvent and self._stateSyncEvent:IsA("RemoteEvent") then
        table.insert(self._persistentConnections, self._stateSyncEvent.OnClientEvent:Connect(function(payload)
            self:_applyStatePayload(payload)
        end))
    end

    if self._feedbackEvent and self._feedbackEvent:IsA("RemoteEvent") then
        table.insert(self._persistentConnections, self._feedbackEvent.OnClientEvent:Connect(function(payload)
            self:_handleFeedback(payload)
        end))
    end

    table.insert(self._persistentConnections, MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, isPurchased)
        if userId ~= localPlayer.UserId or isPurchased ~= true then
            return
        end

        if not isLaunchPowerRobuxProductId(productId) then
            return
        end

        if self._requestStateSyncEvent then
            task.delay(1, function()
                self._requestStateSyncEvent:FireServer()
            end)
        end
    end))

    self._currentCoins = math.max(0, tonumber(ClientPredictionUtil:GetEffectiveCoins()) or 0)
    table.insert(self._persistentConnections, ClientPredictionUtil:ConnectCoinChanged(function(snapshot)
        self:_applyCoinSnapshot(snapshot)
    end))

    table.insert(self._persistentConnections, ProximityPromptService.PromptTriggered:Connect(function(prompt)
        if self:_isUpgradeOpenPrompt(prompt) then
            self:OpenUpgradeModal()
        end
    end))

    local playerGui = self:_getPlayerGui()
    if playerGui then
        table.insert(self._persistentConnections, playerGui.DescendantAdded:Connect(function(descendant)
            local watchedNames = {
                Main = true,
                Top = true,
                Shop = true,
                Upgrade = true,
                Title = true,
                CloseButton = true,
                CashNum = true,
                Equipinfo = true,
                EquipInfo = true,
                ScrollingFrame = true,
                Upgrade1 = true,
                Upgrade2 = true,
                Upgrade3 = true,
                BuyButton = true,
                RBuyButton = true,
                Num1Bg = true,
                Num2Bg = true,
                Num = true,
            }
            if watchedNames[descendant.Name] then
                self:_queueRebind()
            end
        end))
    end

    table.insert(self._persistentConnections, localPlayer.CharacterAdded:Connect(function()
        task.defer(function()
            self:_queueRebind()
        end)
    end))

    self:_scheduleRetryBind()

    if self._requestStateSyncEvent then
        self._requestStateSyncEvent:FireServer()
    end
end

return LaunchPowerUpgradeController
