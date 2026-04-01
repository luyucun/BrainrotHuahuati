--[[
脚本名字: CarryUpgradeController
脚本文件: CarryUpgradeController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/CarryUpgradeController
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
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
        "[CarryUpgradeController] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
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

local function splitSlashPath(pathText)
    local result = {}
    if type(pathText) ~= "string" then
        return result
    end

    for segment in string.gmatch(pathText, "[^/]+") do
        if segment ~= "" then
            table.insert(result, segment)
        end
    end

    return result
end

local function findWorkspacePath(pathText)
    local segments = splitSlashPath(pathText)
    if #segments <= 0 then
        return nil
    end

    local current = Workspace
    local startIndex = 1
    if segments[1] == "Workspace" then
        startIndex = 2
    end

    for index = startIndex, #segments do
        current = current and current:FindFirstChild(segments[index]) or nil
        if not current then
            return nil
        end
    end

    return current
end

local FormatUtil = requireSharedModule("FormatUtil")
local CarryConfig = requireSharedModule("CarryConfig")
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
    error("[CarryUpgradeController] 找不到 IndexController，无法复用按钮动效逻辑。")
end

local IndexController = require(indexControllerModule)

local CarryUpgradeController = {}
CarryUpgradeController.__index = CarryUpgradeController

local STARTUP_WARNING_GRACE_SECONDS = 2
local CARRY_MODAL_KEY = "Carry"

function CarryUpgradeController.new(modalController)
    local self = setmetatable({}, CarryUpgradeController)
    self._modalController = modalController
    self._started = false
    self._persistentConnections = {}
    self._uiConnections = {}
    self._touchConnections = {}
    self._didWarnByKey = {}
    self._rebindQueued = false
    self._startupWarnAt = 0
    self._stateSyncEvent = nil
    self._requestStateSyncEvent = nil
    self._requestUpgradeEvent = nil
    self._feedbackEvent = nil
    self._mainGui = nil
    self._carryRoot = nil
    self._closeButton = nil
    self._equipInfoRoot = nil
    self._equipTemplate = nil
    self._maxTips = nil
    self._num1Label = nil
    self._num2Label = nil
    self._goldButtonRoot = nil
    self._goldButton = nil
    self._goldMoneyLabel = nil
    self._robuxButtonRoot = nil
    self._robuxButton = nil
    self._robuxMoneyLabel = nil
    self._touchOpenPart = nil
    self._touchLatchActive = false
    self._touchReleaseSerial = 0
    self._state = {
        currentLevel = 0,
        currentCarryCount = math.max(1, math.floor(tonumber(CarryConfig.BaseCarryCount) or 1)),
        nextLevel = 1,
        nextCarryCount = math.max(2, math.floor(tonumber(CarryConfig.BaseCarryCount) or 1) + 1),
        nextCoinPrice = 0,
        nextRobuxPrice = 0,
        nextProductId = 0,
        isMax = false,
    }
    self._indexHelper = IndexController.new(nil)
    return self
end

function CarryUpgradeController:_warnOnce(key, message)
    if self._didWarnByKey[key] then
        return
    end

    self._didWarnByKey[key] = true
    warn(message)
end

function CarryUpgradeController:_shouldWarnBindingIssues()
    return os.clock() >= (self._startupWarnAt or 0)
end

function CarryUpgradeController:_getPlayerGui()
    return localPlayer:FindFirstChild("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
end

function CarryUpgradeController:_getMainGui()
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

function CarryUpgradeController:_findDescendantByNames(root, names)
    return self._indexHelper:_findDescendantByNames(root, names)
end

function CarryUpgradeController:_findByPath(root, pathNames)
    if not root then
        return nil
    end

    local current = root
    for _, name in ipairs(pathNames) do
        current = current and current:FindFirstChild(name) or nil
        if not current then
            return nil
        end
    end

    return current
end

function CarryUpgradeController:_resolveInteractiveNode(node)
    return self._indexHelper:_resolveInteractiveNode(node)
end

function CarryUpgradeController:_bindButtonFx(interactiveNode, options, connectionBucket)
    self._indexHelper:_bindButtonFx(interactiveNode, options, connectionBucket)
end

function CarryUpgradeController:_isCarryModalOpen()
    if self._modalController and self._modalController.IsModalOpen then
        return self._modalController:IsModalOpen(CARRY_MODAL_KEY)
    end

    return isLiveInstance(self._carryRoot) and self._carryRoot.Visible == true
end

function CarryUpgradeController:_getHiddenNodesForModal()
    local hiddenNodes = {}
    if not self._mainGui then
        return hiddenNodes
    end

    for _, node in ipairs(self._mainGui:GetChildren()) do
        if node and node ~= self._carryRoot then
            table.insert(hiddenNodes, node)
        end
    end

    return hiddenNodes
end

function CarryUpgradeController:_clearUiBindings()
    disconnectAll(self._uiConnections)
end

function CarryUpgradeController:_clearTouchBindings()
    disconnectAll(self._touchConnections)
    self._touchOpenPart = nil
    self._touchLatchActive = false
    self._touchReleaseSerial = 0
end

function CarryUpgradeController:_formatCurrency(value)
    return FormatUtil.FormatCompactCurrencyCeil(math.max(0, tonumber(value) or 0))
end

function CarryUpgradeController:_applyStatePayload(payload)
    local carryState = payload
    if type(payload) == "table" and type(payload.carryUpgrade) == "table" then
        carryState = payload.carryUpgrade
    end

    if type(carryState) ~= "table" then
        return
    end

    self._state.currentLevel = math.max(0, math.floor(tonumber(carryState.currentLevel) or 0))
    self._state.currentCarryCount = math.max(1, math.floor(tonumber(carryState.currentCarryCount) or CarryConfig.BaseCarryCount or 1))
    self._state.nextLevel = math.max(self._state.currentLevel + 1, math.floor(tonumber(carryState.nextLevel) or (self._state.currentLevel + 1)))
    self._state.nextCarryCount = math.max(self._state.currentCarryCount, math.floor(tonumber(carryState.nextCarryCount) or self._state.currentCarryCount))
    self._state.nextCoinPrice = math.max(0, math.floor(tonumber(carryState.nextCoinPrice) or 0))
    self._state.nextRobuxPrice = math.max(0, math.floor(tonumber(carryState.nextRobuxPrice) or 0))
    self._state.nextProductId = math.max(0, math.floor(tonumber(carryState.nextProductId) or 0))
    self._state.isMax = carryState.isMax == true
    self:_renderAll()
end

function CarryUpgradeController:_renderAll()
    if self._num1Label and self._num1Label:IsA("TextLabel") then
        self._num1Label.Text = tostring(self._state.currentCarryCount)
    end

    if self._num2Label and self._num2Label:IsA("TextLabel") then
        self._num2Label.Text = tostring(self._state.isMax and self._state.currentCarryCount or self._state.nextCarryCount)
    end

    if self._goldMoneyLabel and self._goldMoneyLabel:IsA("TextLabel") then
        self._goldMoneyLabel.Text = self:_formatCurrency(self._state.nextCoinPrice)
    end

    if self._robuxMoneyLabel and self._robuxMoneyLabel:IsA("TextLabel") then
        self._robuxMoneyLabel.Text = tostring(math.max(0, tonumber(self._state.nextRobuxPrice) or 0))
    end

    if self._equipTemplate and self._equipTemplate:IsA("GuiObject") then
        self._equipTemplate.Visible = self._state.isMax ~= true
    end

    if self._maxTips then
        if self._maxTips:IsA("GuiObject") then
            self._maxTips.Visible = self._state.isMax == true
        elseif self._maxTips:IsA("LayerCollector") then
            self._maxTips.Enabled = self._state.isMax == true
        end
    end
end

function CarryUpgradeController:OpenCarryModal()
    if not isLiveInstance(self._carryRoot) and not self:_bindMainUi() then
        return
    end

    self:_renderAll()

    if self._modalController then
        if not self:_isCarryModalOpen() then
            self._modalController:OpenModal(CARRY_MODAL_KEY, self._carryRoot, {
                HiddenNodes = self:_getHiddenNodesForModal(),
            })
        end
    elseif self._carryRoot and self._carryRoot:IsA("GuiObject") then
        self._carryRoot.Visible = true
    end
end

function CarryUpgradeController:CloseCarryModal()
    if not isLiveInstance(self._carryRoot) then
        return
    end

    if self._modalController then
        self._modalController:CloseModal(CARRY_MODAL_KEY)
    elseif self._carryRoot and self._carryRoot:IsA("GuiObject") then
        self._carryRoot.Visible = false
    end
end

function CarryUpgradeController:_resolveCharacterFromTouchPart(hitPart)
    local current = hitPart
    while current do
        if current:IsA("Model") and Players:GetPlayerFromCharacter(current) == localPlayer then
            return current
        end
        current = current.Parent
    end

    return nil
end

function CarryUpgradeController:_isCharacterTouchingTouchPart(touchPart)
    local character = localPlayer.Character
    if not (character and touchPart and touchPart:IsA("BasePart") and touchPart.Parent) then
        return false
    end

    local overlapParams = OverlapParams.new()
    overlapParams.FilterType = Enum.RaycastFilterType.Include
    overlapParams.FilterDescendantsInstances = { character }

    local success, overlappingParts = pcall(function()
        return Workspace:GetPartsInPart(touchPart, overlapParams)
    end)
    if success and type(overlappingParts) == "table" then
        for _, part in ipairs(overlappingParts) do
            if part and part:IsDescendantOf(character) then
                return true
            end
        end
        return false
    end

    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("BasePart") then
            for _, touchingPart in ipairs(descendant:GetTouchingParts()) do
                if touchingPart == touchPart then
                    return true
                end
            end
        end
    end

    return false
end

function CarryUpgradeController:_queueTouchReleaseCheck()
    local trackedTouchPart = self._touchOpenPart
    if not trackedTouchPart then
        self._touchLatchActive = false
        return
    end

    self._touchReleaseSerial += 1
    local releaseSerial = self._touchReleaseSerial
    task.delay(0.1, function()
        if releaseSerial ~= self._touchReleaseSerial then
            return
        end

        if not self:_isCharacterTouchingTouchPart(trackedTouchPart) then
            self._touchLatchActive = false
            self._touchOpenPart = nil
        end
    end)
end

function CarryUpgradeController:_findTouchOpenPart()
    local part = findWorkspacePath(CarryConfig.TouchOpenPartPath)
    if part and part:IsA("BasePart") then
        return part
    end

    local fallback = Workspace:FindFirstChild("UpgradeCarry") or Workspace:FindFirstChild("UpgradeCarry", true)
    if fallback and fallback:IsA("BasePart") then
        return fallback
    end

    return nil
end

function CarryUpgradeController:_bindTouchOpen()
    self:_clearTouchBindings()

    local touchPart = self:_findTouchOpenPart()
    if not touchPart then
        if self:_shouldWarnBindingIssues() then
            self:_warnOnce("MissingTouchPart", "[CarryUpgradeController] 找不到 Workspace/Scene/UpgradeCarry，携带升级触碰打开未绑定。")
        end
        return false
    end

    self._touchOpenPart = touchPart
    self._touchLatchActive = self:_isCharacterTouchingTouchPart(touchPart)

    table.insert(self._touchConnections, touchPart.Touched:Connect(function(hitPart)
        if self._touchLatchActive then
            return
        end

        if not self:_resolveCharacterFromTouchPart(hitPart) then
            return
        end

        self._touchOpenPart = touchPart
        self._touchLatchActive = true
        self:OpenCarryModal()
    end))

    table.insert(self._touchConnections, touchPart.TouchEnded:Connect(function(hitPart)
        if not self:_resolveCharacterFromTouchPart(hitPart) then
            return
        end

        self:_queueTouchReleaseCheck()
    end))

    return true
end

function CarryUpgradeController:_bindMainUi()
    local mainGui = self:_getMainGui()
    if not mainGui then
        if self:_shouldWarnBindingIssues() then
            self:_warnOnce("MissingMain", "[CarryUpgradeController] 找不到 Main UI，携带升级面板暂不可用。")
        end
        self:_clearUiBindings()
        return false
    end

    self._mainGui = mainGui
    self._carryRoot = self:_findDescendantByNames(mainGui, { "Carry" })
    if not self._carryRoot then
        if self:_shouldWarnBindingIssues() then
            self:_warnOnce("MissingCarryRoot", "[CarryUpgradeController] 找不到 Main/Carry，携带升级面板未启动。")
        end
        self:_clearUiBindings()
        return false
    end

    local titleRoot = self:_findByPath(self._carryRoot, { "Title" }) or self:_findDescendantByNames(self._carryRoot, { "Title" })
    self._equipInfoRoot = self:_findByPath(self._carryRoot, { "Equipinfo" })
        or self:_findByPath(self._carryRoot, { "EquipInfo" })
        or self:_findDescendantByNames(self._carryRoot, { "Equipinfo", "EquipInfo" })
    self._closeButton = titleRoot and (self:_findByPath(titleRoot, { "CloseButton" }) or self:_findDescendantByNames(titleRoot, { "CloseButton" })) or nil
    self._equipTemplate = self._equipInfoRoot and (self:_findByPath(self._equipInfoRoot, { "EquipTemplate" }) or self:_findDescendantByNames(self._equipInfoRoot, { "EquipTemplate" })) or nil
    self._maxTips = self._equipInfoRoot and (self:_findByPath(self._equipInfoRoot, { "MaxTips" }) or self:_findDescendantByNames(self._equipInfoRoot, { "MaxTips" })) or nil
    self._num1Label = self._equipTemplate and (self:_findByPath(self._equipTemplate, { "Num1" }) or self:_findDescendantByNames(self._equipTemplate, { "Num1" })) or nil
    self._num2Label = self._equipTemplate and (self:_findByPath(self._equipTemplate, { "Num2" }) or self:_findDescendantByNames(self._equipTemplate, { "Num2" })) or nil
    self._goldButtonRoot = self._equipTemplate and (self:_findByPath(self._equipTemplate, { "GoldButton" }) or self:_findDescendantByNames(self._equipTemplate, { "GoldButton" })) or nil
    self._goldButton = self:_resolveInteractiveNode(self._goldButtonRoot)
    self._goldMoneyLabel = self._goldButtonRoot and (self:_findByPath(self._goldButtonRoot, { "Frame", "GoldMoney" }) or self:_findDescendantByNames(self._goldButtonRoot, { "GoldMoney" })) or nil
    self._robuxButtonRoot = self._equipTemplate and (self:_findByPath(self._equipTemplate, { "RobuxBuyButton" }) or self:_findDescendantByNames(self._equipTemplate, { "RobuxBuyButton" })) or nil
    self._robuxButton = self:_resolveInteractiveNode(self._robuxButtonRoot)
    self._robuxMoneyLabel = self._robuxButtonRoot and (self:_findByPath(self._robuxButtonRoot, { "Frame", "RMoney" }) or self:_findDescendantByNames(self._robuxButtonRoot, { "RMoney" })) or nil

    self:_clearUiBindings()

    local closeInteractive = self:_resolveInteractiveNode(self._closeButton)
    if closeInteractive then
        table.insert(self._uiConnections, closeInteractive.Activated:Connect(function()
            self:CloseCarryModal()
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
            self:_warnOnce("MissingCloseButton", "[CarryUpgradeController] 找不到 Main/Carry/Title/CloseButton。")
        end
    end

    if self._goldButton then
        table.insert(self._uiConnections, self._goldButton.Activated:Connect(function()
            if self._state.isMax ~= true and self._requestUpgradeEvent then
                self._requestUpgradeEvent:FireServer({
                    purchaseType = "Coin",
                })
            end
        end))
        self:_bindButtonFx(self._goldButton, {
            ScaleTarget = self._goldButtonRoot or self._goldButton,
            HoverScale = 1.05,
            PressScale = 0.93,
            HoverRotation = 0,
        }, self._uiConnections)
    end

    if self._robuxButton then
        table.insert(self._uiConnections, self._robuxButton.Activated:Connect(function()
            if self._state.isMax == true or self._state.nextProductId <= 0 then
                return
            end

            local success, err = pcall(function()
                MarketplaceService:PromptProductPurchase(localPlayer, self._state.nextProductId)
            end)
            if not success then
                warn(string.format("[CarryUpgradeController] 打开携带升级购买弹窗失败 productId=%d err=%s", self._state.nextProductId, tostring(err)))
            end
        end))
        self:_bindButtonFx(self._robuxButton, {
            ScaleTarget = self._robuxButtonRoot or self._robuxButton,
            HoverScale = 1.05,
            PressScale = 0.93,
            HoverRotation = 0,
        }, self._uiConnections)
    end

    self:_renderAll()
    return true
end

function CarryUpgradeController:_queueRebind()
    if self._rebindQueued then
        return
    end

    self._rebindQueued = true
    task.defer(function()
        self._rebindQueued = false
        self:_bindMainUi()
        self:_bindTouchOpen()
    end)
end

function CarryUpgradeController:_scheduleRetryBind()
    task.spawn(function()
        local deadline = os.clock() + 12
        repeat
            local didBindUi = self:_bindMainUi()
            local didBindTouch = self:_bindTouchOpen()
            if didBindUi and didBindTouch then
                return
            end
            task.wait(1)
        until os.clock() >= deadline
    end)
end

function CarryUpgradeController:Start()
    if self._started then
        return
    end

    self._started = true
    self._startupWarnAt = os.clock() + STARTUP_WARNING_GRACE_SECONDS

    local eventsRoot = ReplicatedStorage:WaitForChild(RemoteNames.RootFolder)
    local brainrotEvents = eventsRoot:WaitForChild(RemoteNames.BrainrotEventsFolder)

    self._stateSyncEvent = brainrotEvents:FindFirstChild(RemoteNames.Brainrot.BrainrotStateSync)
        or brainrotEvents:WaitForChild(RemoteNames.Brainrot.BrainrotStateSync, 10)
    self._requestStateSyncEvent = brainrotEvents:FindFirstChild(RemoteNames.Brainrot.RequestBrainrotStateSync)
        or brainrotEvents:WaitForChild(RemoteNames.Brainrot.RequestBrainrotStateSync, 10)
    self._requestUpgradeEvent = brainrotEvents:FindFirstChild(RemoteNames.Brainrot.RequestCarryUpgrade)
        or brainrotEvents:WaitForChild(RemoteNames.Brainrot.RequestCarryUpgrade, 10)
    self._feedbackEvent = brainrotEvents:FindFirstChild(RemoteNames.Brainrot.CarryUpgradeFeedback)
        or brainrotEvents:WaitForChild(RemoteNames.Brainrot.CarryUpgradeFeedback, 10)

    if self._stateSyncEvent and self._stateSyncEvent:IsA("RemoteEvent") then
        table.insert(self._persistentConnections, self._stateSyncEvent.OnClientEvent:Connect(function(payload)
            self:_applyStatePayload(payload)
        end))
    end

    if self._feedbackEvent and self._feedbackEvent:IsA("RemoteEvent") then
        table.insert(self._persistentConnections, self._feedbackEvent.OnClientEvent:Connect(function(_payload)
            if self._requestStateSyncEvent then
                self._requestStateSyncEvent:FireServer()
            end
        end))
    end

    table.insert(self._persistentConnections, MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, isPurchased)
        if userId ~= localPlayer.UserId or isPurchased ~= true then
            return
        end

        if not CarryConfig.EntriesByProductId[math.max(0, math.floor(tonumber(productId) or 0))] then
            return
        end

        if self._requestStateSyncEvent then
            task.delay(1, function()
                self._requestStateSyncEvent:FireServer()
            end)
        end
    end))

    local playerGui = self:_getPlayerGui()
    if playerGui then
        table.insert(self._persistentConnections, playerGui.DescendantAdded:Connect(function(descendant)
            local watchedNames = {
                Main = true,
                Carry = true,
                Title = true,
                CloseButton = true,
                Equipinfo = true,
                EquipInfo = true,
                EquipTemplate = true,
                MaxTips = true,
                Num1 = true,
                Num2 = true,
                GoldButton = true,
                GoldMoney = true,
                RobuxBuyButton = true,
                RMoney = true,
            }
            if watchedNames[descendant.Name] then
                self:_queueRebind()
            end
        end))
    end

    table.insert(self._persistentConnections, Workspace.DescendantAdded:Connect(function(descendant)
        if descendant.Name == "UpgradeCarry" or descendant.Name == "Scene" then
            task.defer(function()
                self:_bindTouchOpen()
            end)
        end
    end))

    table.insert(self._persistentConnections, localPlayer.CharacterAdded:Connect(function()
        task.defer(function()
            self:_bindTouchOpen()
        end)
    end))

    self:_scheduleRetryBind()
end

return CarryUpgradeController



