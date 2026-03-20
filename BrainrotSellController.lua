--[[
脚本名字: BrainrotSellController
脚本文件: BrainrotSellController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/BrainrotSellController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
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
        "[BrainrotSellController] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
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

local GameConfig = requireSharedModule("GameConfig")
local BrainrotConfig = requireSharedModule("BrainrotConfig")
local BrainrotDisplayConfig = requireSharedModule("BrainrotDisplayConfig")
local FormatUtil = requireSharedModule("FormatUtil")
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
    error("[BrainrotSellController] 找不到 IndexController，无法复用渐变与按钮动效逻辑。")
end

local IndexController = require(indexControllerModule)

local BrainrotSellController = {}
BrainrotSellController.__index = BrainrotSellController

local STARTUP_WARNING_GRACE_SECONDS = 2

local function resolveQualityDisplayInfo(qualityId)
    local parsedId = math.floor(tonumber(qualityId) or 0)
    local displayEntry = type(BrainrotDisplayConfig.Quality) == "table" and BrainrotDisplayConfig.Quality[parsedId] or nil
    local displayName = (type(displayEntry) == "table" and tostring(displayEntry.Name or "")) or ""
    if displayName == "" then
        displayName = BrainrotConfig.QualityNames[parsedId] or "Unknown"
    end

    local gradientPathOrList = nil
    if type(displayEntry) == "table" then
        gradientPathOrList = displayEntry.GradientPaths or displayEntry.GradientPath
    end

    return displayName, gradientPathOrList
end

local function formatSellCurrency(value)
    return FormatUtil.FormatCompactCurrency(tonumber(value) or 0, 1)
end

function BrainrotSellController.new(modalController)
    local self = setmetatable({}, BrainrotSellController)
    self._modalController = modalController
    self._started = false
    self._persistentConnections = {}
    self._uiConnections = {}
    self._entryConnections = {}
    self._shopTouchConnections = {}
    self._entryClones = {}
    self._didWarnByKey = {}
    self._brainrotStateSyncEvent = nil
    self._requestSellEvent = nil
    self._sellFeedbackEvent = nil
    self._mainGui = nil
    self._sellRoot = nil
    self._topSellRoot = nil
    self._openButton = nil
    self._closeButton = nil
    self._sellInfoRoot = nil
    self._scrollingFrame = nil
    self._template = nil
    self._inventoryValueLabel = nil
    self._allSellButtonRoot = nil
    self._allSellButton = nil
    self._inventory = {}
    self._rebindQueued = false
    self._shopTouchPart = nil
    self._shopTouchLatchActive = false
    self._shopTouchReleaseSerial = 0
    self._successSoundTemplate = nil
    self._didWarnMissingSound = false
    self._startupWarnAt = 0
    self._indexHelper = IndexController.new(nil)
    return self
end

function BrainrotSellController:_warnOnce(key, message)
    if self._didWarnByKey[key] then
        return
    end

    self._didWarnByKey[key] = true
    warn(message)
end

function BrainrotSellController:_shouldWarnBindingIssues()
    return os.clock() >= (self._startupWarnAt or 0)
end

function BrainrotSellController:_getPlayerGui()
    return localPlayer:FindFirstChild("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
end

function BrainrotSellController:_getMainGui()
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

function BrainrotSellController:_findDescendantByNames(root, names)
    return self._indexHelper:_findDescendantByNames(root, names)
end

function BrainrotSellController:_resolveInteractiveNode(node)
    return self._indexHelper:_resolveInteractiveNode(node)
end

function BrainrotSellController:_bindButtonFx(interactiveNode, options, connectionBucket)
    self._indexHelper:_bindButtonFx(interactiveNode, options, connectionBucket)
end

function BrainrotSellController:_isSellModalOpen()
    if self._modalController and self._modalController.IsModalOpen then
        return self._modalController:IsModalOpen("SellBrainrots")
    end

    return isLiveInstance(self._sellRoot) and self._sellRoot.Visible == true
end

function BrainrotSellController:_getHiddenNodesForModal()
    local hiddenNodes = {}
    if not self._mainGui then
        return hiddenNodes
    end

    for _, node in ipairs(self._mainGui:GetChildren()) do
        if node and node ~= self._sellRoot then
            table.insert(hiddenNodes, node)
        end
    end

    return hiddenNodes
end

function BrainrotSellController:_clearUiBindings()
    disconnectAll(self._uiConnections)
end

function BrainrotSellController:_clearEntryBindings()
    disconnectAll(self._entryConnections)
    for _, clone in ipairs(self._entryClones) do
        if clone and clone.Parent then
            clone:Destroy()
        end
    end
    table.clear(self._entryClones)
end

function BrainrotSellController:_clearShopTouchBindings()
    disconnectAll(self._shopTouchConnections)
    self._shopTouchPart = nil
    self._shopTouchLatchActive = false
    self._shopTouchReleaseSerial = 0
end

function BrainrotSellController:_refreshCanvasSize()
    if not isLiveInstance(self._scrollingFrame) then
        return
    end

    local layout = self._scrollingFrame:FindFirstChildWhichIsA("UIListLayout")
    if layout then
        self._scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 12)
    end
end

function BrainrotSellController:_scheduleCanvasRefresh(delaySeconds)
    task.delay(math.max(0.03, tonumber(delaySeconds) or 0.05), function()
        self:_refreshCanvasSize()
    end)
end

function BrainrotSellController:_canRenderEntries()
    return isLiveInstance(self._scrollingFrame) and isLiveInstance(self._template)
end

function BrainrotSellController:_resolveCharacterFromTouchPart(hitPart)
    local current = hitPart
    while current do
        if current:IsA("Model") and Players:GetPlayerFromCharacter(current) == localPlayer then
            return current
        end
        current = current.Parent
    end

    return nil
end

function BrainrotSellController:_isCharacterTouchingTouchPart(touchPart)
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

    local touchingSuccess, touchingParts = pcall(function()
        return touchPart:GetTouchingParts()
    end)
    if not touchingSuccess or type(touchingParts) ~= "table" then
        return false
    end

    for _, part in ipairs(touchingParts) do
        if part and part:IsDescendantOf(character) then
            return true
        end
    end

    return false
end

function BrainrotSellController:_queueShopTouchReleaseCheck()
    local trackedTouchPart = self._shopTouchPart
    local releaseSerial = (tonumber(self._shopTouchReleaseSerial) or 0) + 1
    self._shopTouchReleaseSerial = releaseSerial

    task.delay(0.05, function()
        if self._shopTouchReleaseSerial ~= releaseSerial then
            return
        end

        if not self:_isCharacterTouchingTouchPart(trackedTouchPart) then
            self._shopTouchLatchActive = false
            self._shopTouchPart = nil
        end
    end)
end

function BrainrotSellController:_computeSellPrice(item)
    local explicitValue = tonumber(item and item.sellPrice)
    if explicitValue and explicitValue > 0 then
        return explicitValue
    end

    local baseSpeed = math.max(0, tonumber(item and item.baseCoinPerSecond) or 0)
    local multiplier = math.max(0, tonumber((GameConfig.BRAINROT or {}).SellPriceMultiplier) or 15)
    return baseSpeed * multiplier
end

function BrainrotSellController:_getSuccessSoundTemplate()
    if self._successSoundTemplate and self._successSoundTemplate.Parent then
        return self._successSoundTemplate
    end

    local soundName = tostring((GameConfig.BRAINROT or {}).SellSuccessSoundTemplateName or "ADDCash")
    local audioRoot = SoundService:FindFirstChild("Audio")
    local successSound = audioRoot and (audioRoot:FindFirstChild(soundName) or audioRoot:FindFirstChild(soundName, true)) or nil
    if successSound and successSound:IsA("Sound") then
        self._successSoundTemplate = successSound
        return successSound
    end

    if not self._didWarnMissingSound then
        warn(string.format("[BrainrotSellController] 找不到 SoundService/Audio/%s，使用回退音频资源。", soundName))
        self._didWarnMissingSound = true
    end

    local fallbackName = "_BrainrotSellSuccessFallback"
    local fallbackSound = SoundService:FindFirstChild(fallbackName)
    if fallbackSound and fallbackSound:IsA("Sound") then
        self._successSoundTemplate = fallbackSound
        return fallbackSound
    end

    fallbackSound = Instance.new("Sound")
    fallbackSound.Name = fallbackName
    fallbackSound.SoundId = tostring((GameConfig.BRAINROT or {}).SellSuccessSoundAssetId or "rbxassetid://139922061047157")
    fallbackSound.Volume = 1
    fallbackSound.Parent = SoundService
    self._successSoundTemplate = fallbackSound
    return fallbackSound
end

function BrainrotSellController:_playSuccessSound()
    local template = self:_getSuccessSoundTemplate()
    if not template then
        return
    end

    local soundToPlay = template:Clone()
    soundToPlay.Looped = false
    soundToPlay.Parent = template.Parent or SoundService
    if soundToPlay.SoundId == "" then
        soundToPlay.SoundId = tostring((GameConfig.BRAINROT or {}).SellSuccessSoundAssetId or "rbxassetid://139922061047157")
    end
    soundToPlay:Play()

    task.delay(3, function()
        if soundToPlay and soundToPlay.Parent then
            soundToPlay:Destroy()
        end
    end)
end

function BrainrotSellController:_requestSellOne(instanceId)
    if self._requestSellEvent and self._requestSellEvent:IsA("RemoteEvent") then
        self._requestSellEvent:FireServer({ instanceId = instanceId })
    end
end

function BrainrotSellController:_requestSellAll()
    if self._requestSellEvent and self._requestSellEvent:IsA("RemoteEvent") then
        self._requestSellEvent:FireServer({ sellAll = true })
    end
end

function BrainrotSellController:_applyQualityVisual(label, item)
    if not (label and label:IsA("TextLabel")) then
        return
    end

    local displayName, gradientPathOrList = resolveQualityDisplayInfo(item.quality)
    label.Text = tostring(item.qualityName or displayName or "Unknown")
    self._indexHelper:_applyQualityStrokeColorRule(label, item.quality)
    self._indexHelper:_applyDisplayGradient(label, gradientPathOrList, string.format("Quality:%d", math.floor(tonumber(item.quality) or 0)), true)
end

function BrainrotSellController:_createEntry(item, layoutOrder)
    if not self:_canRenderEntries() then
        return
    end

    local clone = self._template:Clone()
    clone.Name = string.format("SellEntry_%s", tostring(item.instanceId or #self._entryClones + 1))
    clone.LayoutOrder = math.max(1, math.floor(tonumber(layoutOrder) or (#self._entryClones + 1)))
    clone.Visible = true
    clone.Parent = self._scrollingFrame
    table.insert(self._entryClones, clone)

    local headTemplate = self:_findDescendantByNames(clone, { "HeadTemplate" }) or clone
    local icon = self:_findDescendantByNames(headTemplate, { "Icon" })
    local levelLabel = self:_findDescendantByNames(headTemplate, { "Level" })
    local moneyLabel = self:_findDescendantByNames(clone, { "Money" })
    local nameLabel = self:_findDescendantByNames(clone, { "Name" })
    local qualityLabel = self:_findDescendantByNames(clone, { "Quality" })
    local sellButtonRoot = clone:FindFirstChild("SellButton") or self:_findDescendantByNames(clone, { "SellButton" })
    local sellButton = self:_resolveInteractiveNode(sellButtonRoot)

    if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
        icon.Image = tostring(item.icon or "")
    end
    if levelLabel and levelLabel:IsA("TextLabel") then
        levelLabel.Text = string.format("Lv.%d", math.max(1, math.floor(tonumber(item.level) or 1)))
    end
    if moneyLabel and moneyLabel:IsA("TextLabel") then
        moneyLabel.Text = formatSellCurrency(self:_computeSellPrice(item))
    end
    if nameLabel and nameLabel:IsA("TextLabel") then
        nameLabel.Text = tostring(item.name or "Unknown")
    end
    self:_applyQualityVisual(qualityLabel, item)

    if sellButton then
        table.insert(self._entryConnections, sellButton.Activated:Connect(function()
            self:_requestSellOne(tonumber(item.instanceId) or 0)
        end))
        self:_bindButtonFx(sellButton, {
            ScaleTarget = sellButtonRoot or sellButton,
            HoverScale = 1.05,
            PressScale = 0.93,
            HoverRotation = 0,
        }, self._entryConnections)
    end
end

function BrainrotSellController:_updateInventoryValueLabel()
    if not (self._inventoryValueLabel and self._inventoryValueLabel:IsA("TextLabel")) then
        return
    end

    local totalValue = 0
    for _, item in ipairs(self._inventory) do
        totalValue += self:_computeSellPrice(item)
    end
    self._inventoryValueLabel.Text = string.format("Inventory value: %s", formatSellCurrency(totalValue))
end

function BrainrotSellController:_renderAll()
    if not self:_canRenderEntries() then
        return
    end

    if self._template and self._template:IsA("GuiObject") then
        self._template.Visible = false
    end

    self:_clearEntryBindings()
    for index, item in ipairs(self._inventory) do
        self:_createEntry(item, index)
    end
    self:_updateInventoryValueLabel()
    self:_scheduleCanvasRefresh(0.03)
end

function BrainrotSellController:OpenSellModal()
    if not isLiveInstance(self._sellRoot) and not self:_bindMainUi() then
        return
    end

    self:_renderAll()
    self:_refreshCanvasSize()

    if self._modalController then
        if not (self._modalController.IsModalOpen and self._modalController:IsModalOpen("SellBrainrots")) then
            self._modalController:OpenModal("SellBrainrots", self._sellRoot, {
                HiddenNodes = self:_getHiddenNodesForModal(),
            })
        end
    elseif self._sellRoot:IsA("GuiObject") then
        self._sellRoot.Visible = true
    end

    self:_scheduleCanvasRefresh(0.05)
    self:_scheduleCanvasRefresh(0.2)
end

function BrainrotSellController:CloseSellModal()
    if not isLiveInstance(self._sellRoot) then
        return
    end

    if self._modalController then
        self._modalController:CloseModal("SellBrainrots")
    elseif self._sellRoot:IsA("GuiObject") then
        self._sellRoot.Visible = false
    end
end

function BrainrotSellController:_findShopTouchPart()
    local shopModelName = tostring((GameConfig.BRAINROT or {}).SellShopModelName or "Shop02")
    local touchPartName = tostring((GameConfig.BRAINROT or {}).SellShopTouchPartName or "PrisonerTouch")
    local shopModel = Workspace:FindFirstChild(shopModelName) or Workspace:FindFirstChild(shopModelName, true)
    if not shopModel then
        return nil
    end

    local touchPart = shopModel:FindFirstChild(touchPartName) or shopModel:FindFirstChild(touchPartName, true)
    if touchPart and touchPart:IsA("BasePart") then
        return touchPart
    end

    return nil
end

function BrainrotSellController:_bindShopTouch()
    self:_clearShopTouchBindings()

    return true
end

function BrainrotSellController:_bindMainUi()
    local mainGui = self:_getMainGui()
    if not mainGui then
        if self:_shouldWarnBindingIssues() then
            self:_warnOnce("MissingMain", "[BrainrotSellController] 找不到 Main UI，出售面板暂不可用。")
        end
        self:_clearUiBindings()
        return false
    end

    self._mainGui = mainGui
    local topRoot = self:_findDescendantByNames(mainGui, { "Top" })
    self._topSellRoot = topRoot and self:_findDescendantByNames(topRoot, { "Sell" }) or nil
    self._openButton = self:_resolveInteractiveNode(self._topSellRoot)
    self._sellRoot = self:_findDescendantByNames(mainGui, { "SellBrainrots" })
    if not self._sellRoot then
        if self:_shouldWarnBindingIssues() then
            self:_warnOnce("MissingSellRoot", "[BrainrotSellController] 找不到 Main/SellBrainrots，出售面板未启动。")
        end
        self:_clearUiBindings()
        return false
    end

    local titleRoot = self:_findDescendantByNames(self._sellRoot, { "Title" })
    self._sellInfoRoot = self:_findDescendantByNames(self._sellRoot, { "Sellinfo", "SellInfo" })
    self._closeButton = titleRoot and self:_findDescendantByNames(titleRoot, { "CloseButton" }) or nil
    self._scrollingFrame = self._sellInfoRoot and self:_findDescendantByNames(self._sellInfoRoot, { "ScrollingFrame" }) or nil
    self._template = self._scrollingFrame and self:_findDescendantByNames(self._scrollingFrame, { "Template" }) or nil
    self._inventoryValueLabel = self._sellInfoRoot and self:_findDescendantByNames(self._sellInfoRoot, { "InventoryValue" }) or nil
    self._allSellButtonRoot = self._sellInfoRoot and self:_findDescendantByNames(self._sellInfoRoot, { "SellButton" }) or nil
    self._allSellButton = self:_resolveInteractiveNode(self._allSellButtonRoot)

    self:_clearUiBindings()

    if self._openButton then
        table.insert(self._uiConnections, self._openButton.Activated:Connect(function()
            self:OpenSellModal()
        end))
    else
        if self:_shouldWarnBindingIssues() then
            self:_warnOnce("MissingOpenButton", "[BrainrotSellController] 找不到 Main/Top/Sell，顶部出售按钮未绑定。")
        end
    end

    local closeInteractive = self:_resolveInteractiveNode(self._closeButton)
    if closeInteractive then
        table.insert(self._uiConnections, closeInteractive.Activated:Connect(function()
            self:CloseSellModal()
        end))
        self:_bindButtonFx(closeInteractive, {
            ScaleTarget = self._closeButton,
            RotationTarget = self._closeButton,
            HoverScale = 1.12,
            PressScale = 0.92,
            HoverRotation = 20,
        }, self._uiConnections)
    end

    if self._allSellButton then
        table.insert(self._uiConnections, self._allSellButton.Activated:Connect(function()
            self:_requestSellAll()
        end))
        self:_bindButtonFx(self._allSellButton, {
            ScaleTarget = self._allSellButtonRoot or self._allSellButton,
            HoverScale = 1.05,
            PressScale = 0.93,
            HoverRotation = 0,
        }, self._uiConnections)
    end

    if self:_canRenderEntries() then
        self:_renderAll()
    else
        self:_clearEntryBindings()
        self:_updateInventoryValueLabel()
    end
    return true
end

function BrainrotSellController:_queueRebind()
    if self._rebindQueued then
        return
    end

    self._rebindQueued = true
    task.defer(function()
        self._rebindQueued = false
        self:_bindMainUi()
        self:_bindShopTouch()
    end)
end

function BrainrotSellController:_scheduleRetryBind()
    task.spawn(function()
        local deadline = os.clock() + 12
        repeat
            local didBindUi = self:_bindMainUi()
            local didBindShopTouch = self:_bindShopTouch()
            if didBindUi and didBindShopTouch then
                return
            end
            task.wait(1)
        until os.clock() >= deadline
    end)
end

function BrainrotSellController:Start()
    if self._started then
        return
    end
    self._started = true
    self._startupWarnAt = os.clock() + STARTUP_WARNING_GRACE_SECONDS

    local eventsRoot = ReplicatedStorage:WaitForChild(RemoteNames.RootFolder)
    local brainrotEvents = eventsRoot:WaitForChild(RemoteNames.BrainrotEventsFolder)
    self._brainrotStateSyncEvent = brainrotEvents:FindFirstChild(RemoteNames.Brainrot.BrainrotStateSync)
        or brainrotEvents:WaitForChild(RemoteNames.Brainrot.BrainrotStateSync, 10)
    self._requestSellEvent = brainrotEvents:FindFirstChild(RemoteNames.Brainrot.RequestBrainrotSell)
        or brainrotEvents:WaitForChild(RemoteNames.Brainrot.RequestBrainrotSell, 10)
    self._sellFeedbackEvent = brainrotEvents:FindFirstChild(RemoteNames.Brainrot.BrainrotSellFeedback)
        or brainrotEvents:WaitForChild(RemoteNames.Brainrot.BrainrotSellFeedback, 10)

    if self._brainrotStateSyncEvent and self._brainrotStateSyncEvent:IsA("RemoteEvent") then
        table.insert(self._persistentConnections, self._brainrotStateSyncEvent.OnClientEvent:Connect(function(payload)
            local inventory = type(payload) == "table" and payload.inventory or nil
            self._inventory = type(inventory) == "table" and inventory or {}
            if self:_canRenderEntries() then
                self:_renderAll()
            else
                self:_updateInventoryValueLabel()
            end
        end))
    end

    if self._sellFeedbackEvent and self._sellFeedbackEvent:IsA("RemoteEvent") then
        table.insert(self._persistentConnections, self._sellFeedbackEvent.OnClientEvent:Connect(function(payload)
            local status = type(payload) == "table" and tostring(payload.status or "") or ""
            if status == "Success" then
                self:_playSuccessSound()
                if math.max(0, math.floor(tonumber(payload.remainingInventoryCount) or 0)) <= 0 then
                    self:CloseSellModal()
                end
            end
        end))
    end

    local playerGui = self:_getPlayerGui()
    if playerGui then
        table.insert(self._persistentConnections, playerGui.DescendantAdded:Connect(function(descendant)
            local watchedNames = {
                Main = true,
                Top = true,
                Sell = true,
                SellBrainrots = true,
                Sellinfo = true,
                SellInfo = true,
                ScrollingFrame = true,
                Template = true,
                InventoryValue = true,
            }
            if watchedNames[descendant.Name] then
                self:_queueRebind()
            end
        end))
    end

    table.insert(self._persistentConnections, Workspace.DescendantAdded:Connect(function(descendant)
        local shopModelName = tostring((GameConfig.BRAINROT or {}).SellShopModelName or "Shop02")
        local touchPartName = tostring((GameConfig.BRAINROT or {}).SellShopTouchPartName or "PrisonerTouch")
        if descendant.Name == shopModelName or descendant.Name == touchPartName then
            task.defer(function()
                self:_bindShopTouch()
            end)
        end
    end))

    table.insert(self._persistentConnections, localPlayer.CharacterAdded:Connect(function()
        self._shopTouchPart = nil
        self._shopTouchLatchActive = false
        self._shopTouchReleaseSerial = 0
        task.defer(function()
            self:_bindShopTouch()
        end)
    end))

    self:_scheduleRetryBind()
end

return BrainrotSellController





