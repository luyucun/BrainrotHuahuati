--[[
脚本名字: LaunchPowerUpgradeController
脚本文件: LaunchPowerUpgradeController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/LaunchPowerUpgradeController
]]

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
    return {
        currentLevel = math.max(1, math.floor(tonumber(state.currentLevel) or 1)),
        currentValue = math.max(0, math.floor(tonumber(state.currentValue) or 0)),
        nextLevel = math.max(1, math.floor(tonumber(state.nextLevel) or 1)),
        nextValue = math.max(0, math.floor(tonumber(state.nextValue) or 0)),
        nextCost = math.max(0, math.floor(tonumber(state.nextCost) or 0)),
        bulkUpgradeCount = math.max(1, math.floor(tonumber(state.bulkUpgradeCount) or getBulkUpgradeLevelCount())),
        bulkNextLevel = math.max(1, math.floor(tonumber(state.bulkNextLevel) or 1)),
        bulkNextValue = math.max(0, math.floor(tonumber(state.bulkNextValue) or 0)),
        bulkNextCost = math.max(0, math.floor(tonumber(state.bulkNextCost) or 0)),
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
    self._upgrade1Root = nil
    self._buyButtonRoot = nil
    self._buyButton = nil
    self._buyButtonTextLabel = nil
    self._upgrade2Root = nil
    self._bulkBuyButtonRoot = nil
    self._bulkBuyButton = nil
    self._bulkBuyButtonTextLabel = nil
    self._currentNumLabel = nil
    self._nextNumLabel = nil
    self._bulkCurrentNumLabel = nil
    self._bulkNextNumLabel = nil
    self._state = {
        currentLevel = 1,
        currentValue = 0,
        nextLevel = 2,
        nextValue = 1,
        nextCost = 200,
        bulkUpgradeCount = 10,
        bulkNextLevel = 11,
        bulkNextValue = 10,
        bulkNextCost = 2901,
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
    local nextLevel = currentLevel + normalizedUpgradeCount
    local bulkUpgradeCount = getBulkUpgradeLevelCount()

    return {
        currentLevel = nextLevel,
        currentValue = getLaunchPowerValueByLevel(nextLevel),
        nextLevel = nextLevel + 1,
        nextValue = getLaunchPowerValueByLevel(nextLevel + 1),
        nextCost = getNextUpgradeCostByLevel(nextLevel),
        bulkUpgradeCount = bulkUpgradeCount,
        bulkNextLevel = nextLevel + bulkUpgradeCount,
        bulkNextValue = getLaunchPowerValueByLevel(nextLevel + bulkUpgradeCount),
        bulkNextCost = getUpgradePackageCostByLevel(nextLevel, bulkUpgradeCount),
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
    if self._buyButtonTextLabel and self._buyButtonTextLabel:IsA("TextLabel") then
        self._buyButtonTextLabel.Text = self:_formatCurrency(self._state.nextCost)
    elseif self._buyButtonRoot and self._buyButtonRoot:IsA("TextButton") then
        self._buyButtonRoot.Text = self:_formatCurrency(self._state.nextCost)
    end

    if self._currentNumLabel and self._currentNumLabel:IsA("TextLabel") then
        self._currentNumLabel.Text = tostring(math.max(0, math.floor(tonumber(self._state.currentValue) or 0)))
    end

    if self._nextNumLabel and self._nextNumLabel:IsA("TextLabel") then
        self._nextNumLabel.Text = tostring(math.max(0, math.floor(tonumber(self._state.nextValue) or 0)))
    end

    if self._bulkBuyButtonTextLabel and self._bulkBuyButtonTextLabel:IsA("TextLabel") then
        self._bulkBuyButtonTextLabel.Text = self:_formatCurrency(self._state.bulkNextCost)
    elseif self._bulkBuyButtonRoot and self._bulkBuyButtonRoot:IsA("TextButton") then
        self._bulkBuyButtonRoot.Text = self:_formatCurrency(self._state.bulkNextCost)
    end

    if self._bulkCurrentNumLabel and self._bulkCurrentNumLabel:IsA("TextLabel") then
        self._bulkCurrentNumLabel.Text = tostring(math.max(0, math.floor(tonumber(self._state.currentValue) or 0)))
    end

    if self._bulkNextNumLabel and self._bulkNextNumLabel:IsA("TextLabel") then
        self._bulkNextNumLabel.Text = tostring(math.max(0, math.floor(tonumber(self._state.bulkNextValue) or 0)))
    end

    setGuiButtonEnabled(
        self._buyButton,
        not self:_hasPendingUpgrade() and self._currentCoins >= math.max(0, tonumber(self._state.nextCost) or 0)
    )
    setGuiButtonEnabled(
        self._bulkBuyButton,
        not self:_hasPendingUpgrade() and self._currentCoins >= math.max(0, tonumber(self._state.bulkNextCost) or 0)
    )
end

function LaunchPowerUpgradeController:_renderAll()
    self:_renderCashLabel()
    self:_renderUpgradeCard()
end

function LaunchPowerUpgradeController:_applyStatePayload(payload)
    if type(payload) ~= "table" then
        return
    end

    self._state.currentLevel = math.max(1, math.floor(tonumber(payload.currentLevel) or 1))
    self._state.currentValue = math.max(0, math.floor(tonumber(payload.currentValue) or 0))
    self._state.nextLevel = math.max(self._state.currentLevel + 1, math.floor(tonumber(payload.nextLevel) or (self._state.currentLevel + 1)))
    self._state.nextValue = math.max(self._state.currentValue + 1, math.floor(tonumber(payload.nextValue) or (self._state.currentValue + 1)))
    self._state.nextCost = math.max(0, math.floor(tonumber(payload.nextCost) or 0))
    self._state.bulkUpgradeCount = math.max(1, math.floor(tonumber(payload.bulkUpgradeCount) or self._state.bulkUpgradeCount or 10))
    self._state.bulkNextLevel = math.max(self._state.currentLevel + self._state.bulkUpgradeCount, math.floor(tonumber(payload.bulkNextLevel) or (self._state.currentLevel + self._state.bulkUpgradeCount)))
    self._state.bulkNextValue = math.max(self._state.currentValue + self._state.bulkUpgradeCount, math.floor(tonumber(payload.bulkNextValue) or (self._state.currentValue + self._state.bulkUpgradeCount)))
    self._state.bulkNextCost = math.max(0, math.floor(tonumber(payload.bulkNextCost) or 0))
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
    local requiredCoins = 0
    if normalizedUpgradeCount == 1 then
        requiredCoins = math.max(0, math.floor(tonumber(self._state.nextCost) or 0))
    elseif normalizedUpgradeCount == math.max(1, math.floor(tonumber(self._state.bulkUpgradeCount) or getBulkUpgradeLevelCount())) then
        requiredCoins = math.max(0, math.floor(tonumber(self._state.bulkNextCost) or 0))
    else
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
    local isSuccessLike = status == "Success" or status == "SaveFailed"
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
    self._upgrade1Root = self._scrollingFrame and self:_findDescendantByNames(self._scrollingFrame, { "Upgrade1" }) or nil
    self._buyButtonRoot = self._upgrade1Root and self:_findDescendantByNames(self._upgrade1Root, { "BuyButton" }) or nil
    self._buyButton = self:_resolveInteractiveNode(self._buyButtonRoot)
    self._buyButtonTextLabel = self._buyButtonRoot and self:_findDescendantByNames(self._buyButtonRoot, { "Text" }) or nil
    self._upgrade2Root = self._scrollingFrame and self:_findDescendantByNames(self._scrollingFrame, { "Upgrade2" }) or nil
    self._bulkBuyButtonRoot = self._upgrade2Root and self:_findDescendantByNames(self._upgrade2Root, { "BuyButton" }) or nil
    self._bulkBuyButton = self:_resolveInteractiveNode(self._bulkBuyButtonRoot)
    self._bulkBuyButtonTextLabel = self._bulkBuyButtonRoot and self:_findDescendantByNames(self._bulkBuyButtonRoot, { "Text" }) or nil
    local currentNumRoot = self._upgrade1Root and self:_findDescendantByNames(self._upgrade1Root, { "Num1Bg" }) or nil
    local nextNumRoot = self._upgrade1Root and self:_findDescendantByNames(self._upgrade1Root, { "Num2Bg" }) or nil
    self._currentNumLabel = currentNumRoot and self:_findDescendantByNames(currentNumRoot, { "Num" }) or nil
    self._nextNumLabel = nextNumRoot and self:_findDescendantByNames(nextNumRoot, { "Num" }) or nil
    local bulkCurrentNumRoot = self._upgrade2Root and self:_findDescendantByNames(self._upgrade2Root, { "Num1Bg" }) or nil
    local bulkNextNumRoot = self._upgrade2Root and self:_findDescendantByNames(self._upgrade2Root, { "Num2Bg" }) or nil
    self._bulkCurrentNumLabel = bulkCurrentNumRoot and self:_findDescendantByNames(bulkCurrentNumRoot, { "Num" }) or nil
    self._bulkNextNumLabel = bulkNextNumRoot and self:_findDescendantByNames(bulkNextNumRoot, { "Num" }) or nil

    self:_clearUiBindings()

    if self._openButton then
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
        }, self._uiConnections)
    else
        if self:_shouldWarnBindingIssues() then
            self:_warnOnce("MissingCloseButton", "[LaunchPowerUpgradeController] 找不到 Main/Upgrade/Title/CloseButton。")
        end
    end

    if self._buyButton then
        table.insert(self._uiConnections, self._buyButton.Activated:Connect(function()
            self:_requestUpgrade(1)
        end))
        self:_bindButtonFx(self._buyButton, {
            ScaleTarget = self._buyButtonRoot or self._buyButton,
            HoverScale = 1.05,
            PressScale = 0.93,
            HoverRotation = 0,
        }, self._uiConnections)
    else
        if self:_shouldWarnBindingIssues() then
            self:_warnOnce("MissingBuyButton", "[LaunchPowerUpgradeController] 找不到 Main/Upgrade/.../Upgrade1/BuyButton。")
        end
    end

    if self._bulkBuyButton then
        table.insert(self._uiConnections, self._bulkBuyButton.Activated:Connect(function()
            self:_requestUpgrade(self._state.bulkUpgradeCount)
        end))
        self:_bindButtonFx(self._bulkBuyButton, {
            ScaleTarget = self._bulkBuyButtonRoot or self._bulkBuyButton,
            HoverScale = 1.05,
            PressScale = 0.93,
            HoverRotation = 0,
        }, self._uiConnections)
    else
        if self:_shouldWarnBindingIssues() then
            self:_warnOnce("MissingBulkBuyButton", "[LaunchPowerUpgradeController] 找不到 Main/Upgrade/.../Upgrade2/BuyButton。")
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
                BuyButton = true,
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

