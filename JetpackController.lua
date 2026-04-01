--[[
脚本名字: JetpackController
脚本文件: JetpackController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/JetpackController
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
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
        "[JetpackController] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
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

local function setVisibility(instance, isVisible)
    if not instance then
        return
    end

    if instance:IsA("ScreenGui") then
        instance.Enabled = isVisible == true
        return
    end

    if instance:IsA("GuiObject") then
        instance.Visible = isVisible == true
    end
end

local function offsetY(position, yOffset)
    return UDim2.new(
        position.X.Scale,
        position.X.Offset,
        position.Y.Scale,
        position.Y.Offset + yOffset
    )
end

local function isGuiRoot(instance)
    if not instance then
        return false
    end

    return instance:IsA("ScreenGui") or instance:IsA("GuiObject")
end

local function trimTrailingZeros(numberText)
    local trimmed = string.gsub(tostring(numberText or ""), "(%..-)0+$", "%1")
    trimmed = string.gsub(trimmed, "%.$", "")
    return trimmed
end

local FormatUtil = requireSharedModule("FormatUtil")
local JetpackConfig = requireSharedModule("JetpackConfig")
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
    error("[JetpackController] 找不到 IndexController，无法复用按钮动效逻辑。")
end

local IndexController = require(indexControllerModule)

local JetpackController = {}
JetpackController.__index = JetpackController

local STARTUP_WARNING_GRACE_SECONDS = 2
local JETPACK_MODAL_KEY = "Jetpack"
local JETPACK_TELEPORT_TARGET = "Jetpack"
local JETPACK_PROMPT_MODEL_NAME = "Madudung"
local JETPACK_PROMPT_NAME = "ProximityPrompt"
local COIN_ICON_ASSET_ID = "rbxassetid://137339026279273"
local ROBUX_ICON_ASSET_ID = "rbxassetid://125986474223018"

local function normalizeJetpackId(value)
    return math.max(0, math.floor(tonumber(value) or 0))
end

local function normalizeOwnedJetpackIds(ownedIdList)
    local ownedJetpackIds = {}
    if type(ownedIdList) == "table" then
        for _, value in ipairs(ownedIdList) do
            local jetpackId = normalizeJetpackId(value)
            if JetpackConfig.EntriesById[jetpackId] then
                ownedJetpackIds[jetpackId] = true
            end
        end
    end

    for _, entry in ipairs(JetpackConfig.Entries) do
        if entry.IsDefaultUnlocked then
            ownedJetpackIds[entry.Id] = true
        end
    end

    return ownedJetpackIds
end

local function getFallbackEquippedJetpackId(ownedJetpackIds)
    local defaultEntryId = normalizeJetpackId(JetpackConfig.DefaultEntryId)
    if defaultEntryId > 0 and type(ownedJetpackIds) == "table" and ownedJetpackIds[defaultEntryId] == true then
        return defaultEntryId
    end

    local smallestOwnedId = 0
    if type(ownedJetpackIds) == "table" then
        for jetpackId, isOwned in pairs(ownedJetpackIds) do
            local parsedJetpackId = normalizeJetpackId(jetpackId)
            if isOwned == true and parsedJetpackId > 0 and (smallestOwnedId <= 0 or parsedJetpackId < smallestOwnedId) then
                smallestOwnedId = parsedJetpackId
            end
        end
    end

    return smallestOwnedId
end

function JetpackController.new(modalController)
    local self = setmetatable({}, JetpackController)
    self._modalController = modalController
    self._started = false
    self._persistentConnections = {}
    self._uiConnections = {}
    self._entryConnections = {}
    self._didWarnByKey = {}
    self._rebindQueued = false
    self._startupWarnAt = 0
    self._stateSyncEvent = nil
    self._requestStateSyncEvent = nil
    self._requestCoinPurchaseEvent = nil
    self._requestEquipEvent = nil
    self._feedbackEvent = nil
    self._requestQuickTeleportEvent = nil
    self._mainGui = nil
    self._leftRoot = nil
    self._leftJetpackRoot = nil
    self._openButton = nil
    self._jetpackRoot = nil
    self._closeButton = nil
    self._equipInfoRoot = nil
    self._scrollingFrame = nil
    self._entryTemplate = nil
    self._purchaseTipsRoot = nil
    self._purchaseTipsTextLabel = nil
    self._purchaseTipsBasePosition = nil
    self._purchaseTipQueue = {}
    self._isShowingPurchaseTip = false
    self._ownedJetpackIds = normalizeOwnedJetpackIds({ JetpackConfig.DefaultEntryId })
    self._equippedJetpackId = getFallbackEquippedJetpackId(self._ownedJetpackIds)
    self._indexHelper = IndexController.new(nil)
    return self
end

function JetpackController:_warnOnce(key, message)
    if self._didWarnByKey[key] then
        return
    end

    self._didWarnByKey[key] = true
    warn(message)
end

function JetpackController:_shouldWarnBindingIssues()
    return os.clock() >= (self._startupWarnAt or 0)
end

function JetpackController:_getPlayerGui()
    return localPlayer:FindFirstChild("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
end

function JetpackController:_getMainGui()
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

function JetpackController:_findDirectChildByName(root, childName)
    if not root then
        return nil
    end

    local child = root:FindFirstChild(childName)
    if child then
        return child
    end

    for _, descendant in ipairs(root:GetChildren()) do
        if descendant.Name == childName then
            return descendant
        end
    end

    return nil
end

function JetpackController:_findDescendantByNames(root, names)
    return self._indexHelper:_findDescendantByNames(root, names)
end

function JetpackController:_findByPath(root, pathNames)
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

function JetpackController:_resolveInteractiveNode(node)
    return self._indexHelper:_resolveInteractiveNode(node)
end

function JetpackController:_bindButtonFx(interactiveNode, options, connectionBucket)
    self._indexHelper:_bindButtonFx(interactiveNode, options, connectionBucket)
end

function JetpackController:_isJetpackModalOpen()
    if self._modalController and self._modalController.IsModalOpen then
        return self._modalController:IsModalOpen(JETPACK_MODAL_KEY)
    end

    return isLiveInstance(self._jetpackRoot) and self._jetpackRoot.Visible == true
end

function JetpackController:_getHiddenNodesForModal()
    local hiddenNodes = {}
    if not self._mainGui then
        return hiddenNodes
    end

    for _, node in ipairs(self._mainGui:GetChildren()) do
        if node and node ~= self._jetpackRoot and node ~= self._purchaseTipsRoot then
            table.insert(hiddenNodes, node)
        end
    end

    return hiddenNodes
end

function JetpackController:_clearUiBindings()
    disconnectAll(self._uiConnections)
    self:_clearEntryBindings()
end

function JetpackController:_clearEntryBindings()
    disconnectAll(self._entryConnections)

    if not self._scrollingFrame then
        return
    end

    for _, child in ipairs(self._scrollingFrame:GetChildren()) do
        if child ~= self._entryTemplate and not child:IsA("UIGridLayout") and not child:IsA("UIPadding") then
            child:Destroy()
        end
    end
end

function JetpackController:_formatCompactNumber(value)
    return FormatUtil.FormatCompactNumberCeil(tonumber(value) or 0)
end

function JetpackController:_formatDisplayNumber(value, decimals)
    local numericValue = tonumber(value) or 0
    local precision = math.max(0, math.floor(tonumber(decimals) or 0))
    local roundedValue = FormatUtil.RoundToDecimals(numericValue, precision)
    local formatString = string.format("%%.%df", precision)
    return trimTrailingZeros(string.format(formatString, roundedValue))
end

function JetpackController:_applyStatePayload(payload)
    if type(payload) ~= "table" then
        return
    end

    local ownedJetpackIds = normalizeOwnedJetpackIds(payload.ownedJetpackIds)
    local equippedJetpackId = normalizeJetpackId(payload.equippedJetpackId)
    if not ownedJetpackIds[equippedJetpackId] then
        equippedJetpackId = getFallbackEquippedJetpackId(ownedJetpackIds)
    end

    self._ownedJetpackIds = ownedJetpackIds
    self._equippedJetpackId = equippedJetpackId
    self:_renderEntries()
end

function JetpackController:OpenJetpackModal()
    if not isLiveInstance(self._jetpackRoot) and not self:_bindMainUi() then
        return
    end

    self:_renderEntries()
    if self._requestStateSyncEvent then
        self._requestStateSyncEvent:FireServer()
    end

    if self._modalController then
        if not self:_isJetpackModalOpen() then
            self._modalController:OpenModal(JETPACK_MODAL_KEY, self._jetpackRoot, {
                HiddenNodes = self:_getHiddenNodesForModal(),
            })
        end
    elseif self._jetpackRoot and self._jetpackRoot:IsA("GuiObject") then
        self._jetpackRoot.Visible = true
    end
end

function JetpackController:CloseJetpackModal()
    if not isLiveInstance(self._jetpackRoot) then
        return
    end

    if self._modalController then
        self._modalController:CloseModal(JETPACK_MODAL_KEY)
    elseif self._jetpackRoot and self._jetpackRoot:IsA("GuiObject") then
        self._jetpackRoot.Visible = false
    end
end

function JetpackController:_findPromptModel()
    local model = Workspace:FindFirstChild(JETPACK_PROMPT_MODEL_NAME) or Workspace:FindFirstChild(JETPACK_PROMPT_MODEL_NAME, true)
    if model and model:IsA("Model") then
        return model
    end

    return nil
end

function JetpackController:_isJetpackOpenPrompt(prompt)
    if not (prompt and prompt:IsA("ProximityPrompt")) then
        return false
    end

    if prompt.Name ~= JETPACK_PROMPT_NAME then
        return false
    end

    local promptModel = self:_findPromptModel()
    if not promptModel then
        return false
    end

    return prompt:IsDescendantOf(promptModel)
end

function JetpackController:_requestTeleportToJetpackShop()
    if self._requestQuickTeleportEvent and self._requestQuickTeleportEvent:IsA("RemoteEvent") then
        self._requestQuickTeleportEvent:FireServer({
            target = JETPACK_TELEPORT_TARGET,
        })
    end
end

function JetpackController:_findPurchaseTipsRoot(mainGui, playerGui)
    if mainGui then
        local nested = mainGui:FindFirstChild("PurchaseSuccessfulTips", true)
        if nested and isGuiRoot(nested) then
            return nested
        end
    end

    if playerGui then
        local direct = playerGui:FindFirstChild("PurchaseSuccessfulTips")
        if direct and isGuiRoot(direct) then
            return direct
        end

        local nested = playerGui:FindFirstChild("PurchaseSuccessfulTips", true)
        if nested and isGuiRoot(nested) then
            return nested
        end
    end

    return nil
end

function JetpackController:_ensurePurchaseTipNodes()
    if self._purchaseTipsRoot and self._purchaseTipsRoot.Parent and self._purchaseTipsTextLabel and self._purchaseTipsTextLabel.Parent then
        return true
    end

    local playerGui = self:_getPlayerGui()
    local mainGui = self._mainGui or self:_getMainGui()
    local tipsRoot = self:_findPurchaseTipsRoot(mainGui, playerGui)
    if not tipsRoot then
        if self:_shouldWarnBindingIssues() then
            self:_warnOnce("MissingPurchaseTips", "[JetpackController] 找不到 PurchaseSuccessfulTips，购买成功提示将被跳过。")
        end
        return false
    end

    local textLabel = tipsRoot:FindFirstChild("Text", true)
    if not (textLabel and textLabel:IsA("TextLabel")) then
        textLabel = tipsRoot:FindFirstChildWhichIsA("TextLabel", true)
    end
    if not textLabel then
        if self:_shouldWarnBindingIssues() then
            self:_warnOnce("MissingPurchaseTipsText", "[JetpackController] PurchaseSuccessfulTips 存在但缺少 TextLabel。")
        end
        return false
    end

    self._purchaseTipsRoot = tipsRoot
    self._purchaseTipsTextLabel = textLabel
    self._purchaseTipsBasePosition = textLabel.Position
    setVisibility(self._purchaseTipsRoot, false)
    return true
end

function JetpackController:_setPurchaseTipTextAppearance(textTransparency, strokeTransparency)
    if not self._purchaseTipsTextLabel then
        return
    end

    self._purchaseTipsTextLabel.TextTransparency = textTransparency
    self._purchaseTipsTextLabel.TextStrokeTransparency = strokeTransparency
end

function JetpackController:_showNextPurchaseTip()
    if self._isShowingPurchaseTip then
        return
    end

    if #self._purchaseTipQueue <= 0 then
        setVisibility(self._purchaseTipsRoot, false)
        return
    end

    self._isShowingPurchaseTip = true
    local message = table.remove(self._purchaseTipQueue, 1)
    if not self:_ensurePurchaseTipNodes() then
        self._isShowingPurchaseTip = false
        return
    end

    local label = self._purchaseTipsTextLabel
    local basePosition = self._purchaseTipsBasePosition
    if not (label and basePosition) then
        self._isShowingPurchaseTip = false
        setVisibility(self._purchaseTipsRoot, false)
        return
    end

    local enterOffsetY = math.floor(tonumber(JetpackConfig.PurchaseSuccessTipEnterOffsetY) or 40)
    local fadeOffsetY = math.floor(tonumber(JetpackConfig.PurchaseSuccessTipFadeOffsetY) or -8)
    local holdSeconds = math.max(0.2, tonumber(JetpackConfig.PurchaseSuccessTipDisplaySeconds) or 2)

    setVisibility(self._purchaseTipsRoot, true)
    label.Text = tostring(message or JetpackConfig.PurchaseSuccessTipText or "Purchase Successful！")
    label.Position = offsetY(basePosition, enterOffsetY)
    self:_setPurchaseTipTextAppearance(0, 0)

    local enterTween = TweenService:Create(label, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = basePosition,
    })

    enterTween.Completed:Connect(function()
        task.delay(holdSeconds, function()
            if not (label and label.Parent) then
                self._isShowingPurchaseTip = false
                self:_showNextPurchaseTip()
                return
            end

            local fadeTween = TweenService:Create(label, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                TextTransparency = 1,
                TextStrokeTransparency = 1,
                Position = offsetY(basePosition, fadeOffsetY),
            })

            fadeTween.Completed:Connect(function()
                if label and label.Parent then
                    label.Position = basePosition
                    self:_setPurchaseTipTextAppearance(0, 0)
                end

                self._isShowingPurchaseTip = false
                if #self._purchaseTipQueue <= 0 then
                    setVisibility(self._purchaseTipsRoot, false)
                end
                self:_showNextPurchaseTip()
            end)

            fadeTween:Play()
        end)
    end)

    enterTween:Play()
end

function JetpackController:_enqueuePurchaseTip(message)
    local finalMessage = tostring(message or "")
    if finalMessage == "" then
        finalMessage = tostring(JetpackConfig.PurchaseSuccessTipText or "Purchase Successful！")
    end

    table.insert(self._purchaseTipQueue, finalMessage)
    self:_showNextPurchaseTip()
end

function JetpackController:_renderEntries()
    if not (isLiveInstance(self._jetpackRoot) and isLiveInstance(self._scrollingFrame) and isLiveInstance(self._entryTemplate)) then
        return
    end

    self:_clearEntryBindings()
    self:_ensurePurchaseTipNodes()

    for _, entry in ipairs(JetpackConfig.Entries) do
        local clone = self._entryTemplate:Clone()
        clone.Name = string.format("JetpackEntry_%d", entry.Id)
        clone.LayoutOrder = math.max(1, tonumber(entry.SortOrder) or entry.Id)
        clone.Visible = true
        clone.Parent = self._scrollingFrame

        local nameLabel = self:_findDescendantByNames(clone, { "Name" })
        if nameLabel and nameLabel:IsA("TextLabel") then
            nameLabel.Text = tostring(entry.Name or "Jetpack")
        end

        local iconNode = self:_findByPath(clone, { "ItemTemplate", "ItemIcon" })
        if iconNode and (iconNode:IsA("ImageLabel") or iconNode:IsA("ImageButton")) then
            iconNode.Image = tostring(entry.Icon or "")
        end

        local title1Label = self:_findDescendantByNames(clone, { "Title1" })
        if title1Label and title1Label:IsA("TextLabel") then
            title1Label.Text = self:_formatDisplayNumber(entry.NoGravityDuration, 1) .. "S"
        end

        local title2Label = self:_findDescendantByNames(clone, { "Title2" })
        if title2Label and title2Label:IsA("TextLabel") then
            title2Label.Text = self:_formatDisplayNumber(entry.BulletTimeFallSpeed, 1)
        end

        local goldButtonRoot = self:_findDescendantByNames(clone, { "GoldButton" })
        local goldMoneyLabel = goldButtonRoot and self:_findByPath(goldButtonRoot, { "Frame", "RMoney" }) or nil
        local goldMoneyIcon = goldButtonRoot and self:_findByPath(goldButtonRoot, { "Frame", "ImageLabel" }) or nil
        if goldMoneyLabel and goldMoneyLabel:IsA("TextLabel") then
            goldMoneyLabel.Text = self:_formatCompactNumber(entry.CoinPrice)
        end
        if goldMoneyIcon and (goldMoneyIcon:IsA("ImageLabel") or goldMoneyIcon:IsA("ImageButton")) then
            goldMoneyIcon.Image = COIN_ICON_ASSET_ID
        end

        local robuxButtonRoot = self:_findDescendantByNames(clone, { "RobuxBuyButton" })
        local robuxMoneyLabel = robuxButtonRoot and self:_findByPath(robuxButtonRoot, { "Frame", "RMoney" }) or nil
        local robuxMoneyIcon = robuxButtonRoot and self:_findByPath(robuxButtonRoot, { "Frame", "ImageLabel" }) or nil

        local equipButtonRoot = self:_findDescendantByNames(clone, { "EquipButton" })
        local equippedLabel = self:_findDescendantByNames(clone, { "Equiped" })
        local isOwned = self._ownedJetpackIds[entry.Id] == true
        local isEquipped = isOwned and self._equippedJetpackId == entry.Id
        local robuxPrice = math.max(0, math.floor(tonumber(entry.RobuxPrice) or 0))
        local productId = math.max(0, math.floor(tonumber(entry.ProductId) or 0))
        local canBuyRobux = (not isOwned) and robuxPrice > 0 and productId > 0
        if robuxMoneyLabel and robuxMoneyLabel:IsA("TextLabel") then
            robuxMoneyLabel.Text = tostring(robuxPrice)
        end
        if robuxMoneyIcon and (robuxMoneyIcon:IsA("ImageLabel") or robuxMoneyIcon:IsA("ImageButton")) then
            robuxMoneyIcon.Image = ROBUX_ICON_ASSET_ID
        end

        if goldButtonRoot and goldButtonRoot:IsA("GuiObject") then
            goldButtonRoot.Visible = not isOwned
        end

        if robuxButtonRoot and robuxButtonRoot:IsA("GuiObject") then
            robuxButtonRoot.Visible = canBuyRobux
        end

        if equipButtonRoot and equipButtonRoot:IsA("GuiObject") then
            equipButtonRoot.Visible = isOwned and not isEquipped
        end

        if equippedLabel and equippedLabel:IsA("GuiObject") then
            equippedLabel.Visible = isEquipped
        end

        local goldInteractive = self:_resolveInteractiveNode(goldButtonRoot)
        if goldInteractive and not isOwned then
            table.insert(self._entryConnections, goldInteractive.Activated:Connect(function()
                if self._requestCoinPurchaseEvent then
                    self._requestCoinPurchaseEvent:FireServer({
                        jetpackId = entry.Id,
                    })
                end
            end))
            self:_bindButtonFx(goldInteractive, {
                ScaleTarget = goldButtonRoot,
                HoverScale = 1.04,
                PressScale = 0.94,
                HoverRotation = 0,
            }, self._entryConnections)
        end

        local robuxInteractive = self:_resolveInteractiveNode(robuxButtonRoot)
        if robuxInteractive and canBuyRobux then
            table.insert(self._entryConnections, robuxInteractive.Activated:Connect(function()
                local success, err = pcall(function()
                    MarketplaceService:PromptProductPurchase(localPlayer, productId)
                end)
                if not success then
                    warn(string.format("[JetpackController] 打开喷气背包购买弹窗失败 jetpackId=%d productId=%d err=%s", entry.Id, productId, tostring(err)))
                end
            end))
            self:_bindButtonFx(robuxInteractive, {
                ScaleTarget = robuxButtonRoot,
                HoverScale = 1.04,
                PressScale = 0.94,
                HoverRotation = 0,
            }, self._entryConnections)
        end

        local equipInteractive = self:_resolveInteractiveNode(equipButtonRoot)
        if equipInteractive and isOwned and not isEquipped then
            table.insert(self._entryConnections, equipInteractive.Activated:Connect(function()
                if self._requestEquipEvent then
                    self._requestEquipEvent:FireServer({
                        jetpackId = entry.Id,
                    })
                end
            end))
            self:_bindButtonFx(equipInteractive, {
                ScaleTarget = equipButtonRoot,
                HoverScale = 1.04,
                PressScale = 0.94,
                HoverRotation = 0,
            }, self._entryConnections)
        end
    end
end
function JetpackController:_bindMainUi()
    local mainGui = self:_getMainGui()
    if not mainGui then
        if self:_shouldWarnBindingIssues() then
            self:_warnOnce("MissingMain", "[JetpackController] 找不到 Main UI，喷气背包面板暂不可用。")
        end
        self:_clearUiBindings()
        return false
    end

    self._mainGui = mainGui
    self._leftRoot = self:_findDirectChildByName(mainGui, "Left")
    self._leftJetpackRoot = self._leftRoot and self:_findDirectChildByName(self._leftRoot, "Jetpack") or nil
    self._openButton = self:_resolveInteractiveNode(self._leftJetpackRoot)
    self._jetpackRoot = self:_findDirectChildByName(mainGui, "Jetpack")
    self._purchaseTipsRoot = self:_findDirectChildByName(mainGui, "PurchaseSuccessfulTips")

    if not self._jetpackRoot or self._jetpackRoot == self._leftJetpackRoot then
        if self:_shouldWarnBindingIssues() then
            self:_warnOnce("MissingJetpackRoot", "[JetpackController] 找不到 Main/Jetpack，喷气背包面板未启动。")
        end
        self:_clearUiBindings()
        return false
    end

    local titleRoot = self:_findDirectChildByName(self._jetpackRoot, "Title")
    self._closeButton = titleRoot and self:_findDescendantByNames(titleRoot, { "CloseButton" }) or nil
    self._equipInfoRoot = self:_findDirectChildByName(self._jetpackRoot, "Equipinfo") or self:_findDirectChildByName(self._jetpackRoot, "EquipInfo")
    self._scrollingFrame = self._equipInfoRoot and self:_findDescendantByNames(self._equipInfoRoot, { "ScrollingFrame" }) or nil
    self._entryTemplate = self._scrollingFrame and self:_findDescendantByNames(self._scrollingFrame, { "EquipTemplate" }) or nil

    if not (self._scrollingFrame and self._entryTemplate) then
        if self:_shouldWarnBindingIssues() then
            self:_warnOnce("MissingJetpackTemplate", "[JetpackController] 找不到 Main/Jetpack/Equipinfo/ScrollingFrame/EquipTemplate。")
        end
        self:_clearUiBindings()
        return false
    end

    self._entryTemplate.Visible = false
    self:_ensurePurchaseTipNodes()
    self:_clearUiBindings()

    if self._openButton then
        table.insert(self._uiConnections, self._openButton.Activated:Connect(function()
            self:_requestTeleportToJetpackShop()
            self:OpenJetpackModal()
        end))
    else
        if self:_shouldWarnBindingIssues() then
            self:_warnOnce("MissingJetpackOpenButton", "[JetpackController] 找不到 Main/Left/Jetpack/TextButton，喷气背包入口未绑定。")
        end
    end

    local closeInteractive = self:_resolveInteractiveNode(self._closeButton)
    if closeInteractive then
        table.insert(self._uiConnections, closeInteractive.Activated:Connect(function()
            self:CloseJetpackModal()
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
            self:_warnOnce("MissingJetpackCloseButton", "[JetpackController] 找不到 Main/Jetpack/Title/CloseButton。")
        end
    end

    self:_renderEntries()
    return true
end

function JetpackController:_queueRebind()
    if self._rebindQueued then
        return
    end

    self._rebindQueued = true
    task.defer(function()
        self._rebindQueued = false
        self:_bindMainUi()
    end)
end

function JetpackController:_scheduleRetryBind()
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

function JetpackController:Start()
    if self._started then
        return
    end

    self._started = true
    self._startupWarnAt = os.clock() + STARTUP_WARNING_GRACE_SECONDS

    local eventsRoot = ReplicatedStorage:WaitForChild(RemoteNames.RootFolder)
    local systemEvents = eventsRoot:WaitForChild(RemoteNames.SystemEventsFolder)

    self._stateSyncEvent = systemEvents:FindFirstChild(RemoteNames.System.JetpackStateSync)
        or systemEvents:WaitForChild(RemoteNames.System.JetpackStateSync, 10)
    self._requestStateSyncEvent = systemEvents:FindFirstChild(RemoteNames.System.RequestJetpackStateSync)
        or systemEvents:WaitForChild(RemoteNames.System.RequestJetpackStateSync, 10)
    self._requestCoinPurchaseEvent = systemEvents:FindFirstChild(RemoteNames.System.RequestJetpackCoinPurchase)
        or systemEvents:WaitForChild(RemoteNames.System.RequestJetpackCoinPurchase, 10)
    self._requestEquipEvent = systemEvents:FindFirstChild(RemoteNames.System.RequestJetpackEquip)
        or systemEvents:WaitForChild(RemoteNames.System.RequestJetpackEquip, 10)
    self._feedbackEvent = systemEvents:FindFirstChild(RemoteNames.System.JetpackFeedback)
        or systemEvents:WaitForChild(RemoteNames.System.JetpackFeedback, 10)
    self._requestQuickTeleportEvent = systemEvents:FindFirstChild(RemoteNames.System.RequestQuickTeleport)
        or systemEvents:WaitForChild(RemoteNames.System.RequestQuickTeleport, 10)

    if self._stateSyncEvent and self._stateSyncEvent:IsA("RemoteEvent") then
        table.insert(self._persistentConnections, self._stateSyncEvent.OnClientEvent:Connect(function(payload)
            self:_applyStatePayload(payload)
        end))
    end

    if self._feedbackEvent and self._feedbackEvent:IsA("RemoteEvent") then
        table.insert(self._persistentConnections, self._feedbackEvent.OnClientEvent:Connect(function(payload)
            if type(payload) ~= "table" then
                return
            end

            local status = tostring(payload.status or "")
            if status == "CoinPurchased" or status == "RobuxPurchaseGranted" then
                self:_enqueuePurchaseTip(payload.message)
                return
            end

            if status ~= "" and status ~= "Equipped" and self._requestStateSyncEvent then
                self._requestStateSyncEvent:FireServer()
            end
        end))
    end

    table.insert(self._persistentConnections, MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, isPurchased)
        if userId ~= localPlayer.UserId or isPurchased ~= true then
            return
        end

        if not JetpackConfig.EntriesByProductId[normalizeJetpackId(productId)] then
            return
        end

        if self._requestStateSyncEvent then
            task.delay(1, function()
                self._requestStateSyncEvent:FireServer()
            end)
        end
    end))

    table.insert(self._persistentConnections, ProximityPromptService.PromptTriggered:Connect(function(prompt)
        if self:_isJetpackOpenPrompt(prompt) then
            self:OpenJetpackModal()
        end
    end))

    local playerGui = self:_getPlayerGui()
    if playerGui then
        table.insert(self._persistentConnections, playerGui.DescendantAdded:Connect(function(descendant)
            local watchedNames = {
                Main = true,
                Left = true,
                Jetpack = true,
                Title = true,
                CloseButton = true,
                Equipinfo = true,
                EquipInfo = true,
                ScrollingFrame = true,
                EquipTemplate = true,
                PurchaseSuccessfulTips = true,
            }
            if watchedNames[descendant.Name] then
                self:_queueRebind()
            end
        end))
    end

    self:_scheduleRetryBind()

    if self._requestStateSyncEvent then
        self._requestStateSyncEvent:FireServer()
    end
end

return JetpackController





