--[[
脚本名字: GiftController
脚本文件: GiftController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/GiftController
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
        "[GiftController] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local function requireControllerModule(moduleName)
    local controllersFolder = script.Parent
    if controllersFolder then
        local moduleInControllers = controllersFolder:FindFirstChild(moduleName)
        if moduleInControllers and moduleInControllers:IsA("ModuleScript") then
            return require(moduleInControllers)
        end
    end

    error(string.format("[GiftController] 缺少控制器模块 %s。", moduleName))
end

local GameConfig = requireSharedModule("GameConfig")
local RemoteNames = requireSharedModule("RemoteNames")
local IndexController = requireControllerModule("IndexController")

local GiftController = {}
GiftController.__index = GiftController

local function disconnectAll(connectionList)
    for _, connection in ipairs(connectionList or {}) do
        if connection and connection.Disconnect then
            connection:Disconnect()
        end
    end
    table.clear(connectionList)
end

local function isLiveInstance(instance)
    return instance and instance.Parent ~= nil
end

local function normalizeUserId(userId)
    return math.floor(tonumber(userId) or 0)
end

local function normalizeRequestId(requestId)
    return math.max(0, math.floor(tonumber(requestId) or 0))
end

local function isVisibilityNode(instance)
    return instance and (instance:IsA("GuiObject") or instance:IsA("LayerCollector"))
end

local function isGuiObject(instance)
    return instance and instance:IsA("GuiObject")
end

local function getVisibilityValue(instance)
    if not instance then
        return nil
    end

    if instance:IsA("LayerCollector") then
        return instance.Enabled
    end

    if instance:IsA("GuiObject") then
        return instance.Visible
    end

    return nil
end

local function setVisibilityValue(instance, isVisible)
    if not instance then
        return
    end

    if instance:IsA("LayerCollector") then
        instance.Enabled = isVisible == true
        return
    end

    if instance:IsA("GuiObject") then
        instance.Visible = isVisible == true
    end
end

local function isSameOrDescendant(instance, ancestor)
    if not (instance and ancestor) then
        return false
    end

    return instance == ancestor or instance:IsDescendantOf(ancestor)
end

function GiftController.new(modalController)
    local self = setmetatable({}, GiftController)
    self._modalController = modalController
    self._indexHelper = IndexController.new(nil)
    self._persistentConnections = {}
    self._uiConnections = {}
    self._characterConnections = {}
    self._promptConnectionsByPrompt = {}
    self._didWarnByKey = {}
    self._mainGui = nil
    self._giftRoot = nil
    self._windowRoot = nil
    self._closeButton = nil
    self._acceptButton = nil
    self._declineButton = nil
    self._portraitImage = nil
    self._senderText = nil
    self._messageText = nil
    self._rebindQueued = false
    self._started = false
    self._isHoldingBrainrot = false
    self._currentOffer = nil
    self._avatarRequestToken = 0
    self._brainrotGiftOfferEvent = nil
    self._requestGiftDecisionEvent = nil
    self._brainrotGiftFeedbackEvent = nil
    self._pendingOutgoingByTargetUserId = {}
    self._declineCooldownByTargetUserId = {}
    self._cooldownTokenByTargetUserId = {}
    self._forcedVisibleStateByNode = {}
    self._forcedVisibilityRestoreToken = 0
    return self
end

function GiftController:_warnOnce(key, message)
    if self._didWarnByKey[key] then
        return
    end

    self._didWarnByKey[key] = true
    warn(message)
end

function GiftController:_getPlayerGui()
    return localPlayer:FindFirstChild("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
end

function GiftController:_getMainGui()
    local playerGui = self:_getPlayerGui()
    if not playerGui then
        return nil
    end

    return playerGui:FindFirstChild("Main") or playerGui:FindFirstChild("Main", true)
end

function GiftController:_findDescendantByNames(root, names)
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

function GiftController:_resolveInteractiveNode(node)
    return self._indexHelper:_resolveInteractiveNode(node)
end

function GiftController:_bindButtonFx(interactiveNode, options, connectionBucket)
    self._indexHelper:_bindButtonFx(interactiveNode, options, connectionBucket)
end

function GiftController:_isGiftModalOpen()
    local modalRoot = self:_getModalRoot()
    if self._modalController and self._modalController.IsModalOpen then
        return self._modalController:IsModalOpen("Gift")
    end

    return isLiveInstance(modalRoot) and getVisibilityValue(modalRoot) == true
end

function GiftController:_getModalRoot()
    if isGuiObject(self._giftRoot) then
        return self._giftRoot
    end

    if isGuiObject(self._windowRoot) then
        return self._windowRoot
    end

    if isVisibilityNode(self._giftRoot) then
        return self._giftRoot
    end

    if isVisibilityNode(self._windowRoot) then
        return self._windowRoot
    end

    return self._giftRoot or self._windowRoot
end

function GiftController:_bumpForcedVisibilityRestoreToken()
    self._forcedVisibilityRestoreToken = (tonumber(self._forcedVisibilityRestoreToken) or 0) + 1
    return self._forcedVisibilityRestoreToken
end

function GiftController:_ensureGiftVisibilityChain()
    self:_bumpForcedVisibilityRestoreToken()

    local current = self._windowRoot or self._giftRoot
    while current and current ~= self._mainGui do
        if isVisibilityNode(current) then
            if self._forcedVisibleStateByNode[current] == nil then
                self._forcedVisibleStateByNode[current] = getVisibilityValue(current)
            end
            setVisibilityValue(current, true)
        end

        current = current.Parent
    end
end

function GiftController:_restoreForcedGiftVisibility()
    for node, originalVisible in pairs(self._forcedVisibleStateByNode) do
        if node and node.Parent ~= nil and originalVisible ~= nil then
            setVisibilityValue(node, originalVisible)
        end
    end

    table.clear(self._forcedVisibleStateByNode)
end

function GiftController:_scheduleRestoreForcedGiftVisibility()
    local uiConfig = GameConfig.UI or {}
    local restoreToken = self:_bumpForcedVisibilityRestoreToken()
    local delaySeconds = math.max(
        0.05,
        (tonumber(uiConfig.ModalCloseOvershootDuration) or 0.1)
            + (tonumber(uiConfig.ModalCloseShrinkDuration) or 0.14)
            + 0.05
    )

    task.delay(delaySeconds, function()
        if self._forcedVisibilityRestoreToken ~= restoreToken then
            return
        end

        if self:_isGiftModalOpen() then
            return
        end

        self:_restoreForcedGiftVisibility()
    end)
end

function GiftController:_resolveGiftRoot(mainGui)
    if not mainGui then
        return nil
    end

    local directGift = mainGui:FindFirstChild("Gift")
    if directGift then
        return directGift
    end

    local fallbackGift = nil
    for _, descendant in ipairs(mainGui:GetDescendants()) do
        if descendant.Name == "Gift" then
            if descendant:FindFirstChild("Window", true) or descendant:FindFirstChild("CloseButton", true) then
                return descendant
            end

            if not fallbackGift then
                fallbackGift = descendant
            end
        end
    end

    return fallbackGift
end

function GiftController:_getHiddenNodesForModal()
    local hiddenNodes = {}
    if not (self._mainGui and self._giftRoot) then
        return hiddenNodes
    end

    local hiddenNodeSet = {}
    local function addHiddenNode(node)
        if not (node and isVisibilityNode(node)) then
            return
        end

        if hiddenNodeSet[node] then
            return
        end

        hiddenNodeSet[node] = true
        table.insert(hiddenNodes, node)
    end

    for _, node in ipairs(self._mainGui:GetChildren()) do
        if node and not isSameOrDescendant(self._giftRoot, node) then
            addHiddenNode(node)
        end
    end

    local current = self._giftRoot
    while current and current ~= self._mainGui do
        local parent = current.Parent
        if not parent then
            break
        end

        for _, sibling in ipairs(parent:GetChildren()) do
            if sibling ~= current and not isSameOrDescendant(self._giftRoot, sibling) then
                addHiddenNode(sibling)
            end
        end

        current = parent
    end

    return hiddenNodes
end

function GiftController:_closeGiftModal()
    local modalRoot = self:_getModalRoot()
    if not modalRoot then
        return
    end

    if self._modalController then
        self._modalController:CloseModal("Gift")
        self:_scheduleRestoreForcedGiftVisibility()
    else
        setVisibilityValue(modalRoot, false)
        self:_restoreForcedGiftVisibility()
    end
end

function GiftController:_openGiftModal()
    local modalRoot = self:_getModalRoot()
    if not modalRoot then
        return
    end

    self:_ensureGiftVisibilityChain()

    if self._modalController then
        self._modalController:OpenModal("Gift", modalRoot, {
            HiddenNodes = self:_getHiddenNodesForModal(),
        })
    else
        setVisibilityValue(modalRoot, true)
    end
end

function GiftController:_computeHoldingBrainrot()
    local character = localPlayer.Character
    if not character then
        return false
    end

    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("Tool") and child:GetAttribute("BrainrotTool") == true then
            return true
        end
    end

    return false
end

function GiftController:_refreshHoldingBrainrotState()
    local previousState = self._isHoldingBrainrot
    self._isHoldingBrainrot = self:_computeHoldingBrainrot()
    if previousState ~= self._isHoldingBrainrot then
        self:_refreshAllPrompts()
    end
end

function GiftController:_bindCharacterWatchers(character)
    disconnectAll(self._characterConnections)
    if not character then
        self._isHoldingBrainrot = false
        self:_refreshAllPrompts()
        return
    end

    table.insert(self._characterConnections, character.ChildAdded:Connect(function(child)
        if child and child:IsA("Tool") then
            self:_refreshHoldingBrainrotState()
        end
    end))
    table.insert(self._characterConnections, character.ChildRemoved:Connect(function(child)
        if child and child:IsA("Tool") then
            self:_refreshHoldingBrainrotState()
        end
    end))
    table.insert(self._characterConnections, character.AncestryChanged:Connect(function(_, parent)
        if not parent then
            self:_refreshHoldingBrainrotState()
        end
    end))

    self:_refreshHoldingBrainrotState()
end

function GiftController:_setDeclineCooldown(targetUserId, expiresAt)
    local parsedTargetUserId = normalizeUserId(targetUserId)
    local parsedExpiresAt = math.max(0, math.floor(tonumber(expiresAt) or 0))
    if parsedTargetUserId == 0 then
        return
    end

    if parsedExpiresAt <= os.time() then
        self._declineCooldownByTargetUserId[parsedTargetUserId] = nil
        self._cooldownTokenByTargetUserId[parsedTargetUserId] = nil
        self:_refreshAllPrompts()
        return
    end

    self._declineCooldownByTargetUserId[parsedTargetUserId] = parsedExpiresAt
    local nextToken = (tonumber(self._cooldownTokenByTargetUserId[parsedTargetUserId]) or 0) + 1
    self._cooldownTokenByTargetUserId[parsedTargetUserId] = nextToken

    local delaySeconds = math.max(0.05, parsedExpiresAt - os.time() + 0.05)
    task.delay(delaySeconds, function()
        if self._cooldownTokenByTargetUserId[parsedTargetUserId] ~= nextToken then
            return
        end

        local activeExpiresAt = math.max(0, math.floor(tonumber(self._declineCooldownByTargetUserId[parsedTargetUserId]) or 0))
        if activeExpiresAt <= os.time() then
            self._declineCooldownByTargetUserId[parsedTargetUserId] = nil
            self._cooldownTokenByTargetUserId[parsedTargetUserId] = nil
            self:_refreshAllPrompts()
        end
    end)
end

function GiftController:_isTargetCoolingDown(targetUserId)
    local parsedTargetUserId = normalizeUserId(targetUserId)
    if parsedTargetUserId == 0 then
        return false
    end

    local expiresAt = math.max(0, math.floor(tonumber(self._declineCooldownByTargetUserId[parsedTargetUserId]) or 0))
    if expiresAt <= os.time() then
        self._declineCooldownByTargetUserId[parsedTargetUserId] = nil
        self._cooldownTokenByTargetUserId[parsedTargetUserId] = nil
        return false
    end

    return true
end

function GiftController:_shouldShowPrompt(prompt)
    local targetUserId = normalizeUserId(prompt and prompt:GetAttribute("GiftTargetUserId"))
    if targetUserId == 0 or targetUserId == localPlayer.UserId then
        return false
    end

    if not self._isHoldingBrainrot then
        return false
    end

    if self._pendingOutgoingByTargetUserId[targetUserId] == true then
        return false
    end

    if self:_isTargetCoolingDown(targetUserId) then
        return false
    end

    return true
end

function GiftController:_applyPromptVisibility(prompt)
    if not (prompt and prompt:IsA("ProximityPrompt")) then
        return
    end

    if prompt:GetAttribute("GiftPrompt") ~= true then
        return
    end

    local shouldShow = self:_shouldShowPrompt(prompt)
    if prompt.Enabled ~= shouldShow then
        prompt.Enabled = shouldShow
    end
end

function GiftController:_disconnectPrompt(prompt)
    local connectionList = self._promptConnectionsByPrompt[prompt]
    if type(connectionList) ~= "table" then
        return
    end

    disconnectAll(connectionList)
    self._promptConnectionsByPrompt[prompt] = nil
end

function GiftController:_trackPrompt(prompt)
    if not (prompt and prompt:IsA("ProximityPrompt")) then
        return
    end

    if prompt:GetAttribute("GiftPrompt") ~= true then
        return
    end

    if self._promptConnectionsByPrompt[prompt] then
        self:_applyPromptVisibility(prompt)
        return
    end

    local connectionList = {}
    self._promptConnectionsByPrompt[prompt] = connectionList
    table.insert(connectionList, prompt:GetAttributeChangedSignal("GiftPrompt"):Connect(function()
        if prompt:GetAttribute("GiftPrompt") ~= true then
            self:_disconnectPrompt(prompt)
            return
        end
        self:_applyPromptVisibility(prompt)
    end))
    table.insert(connectionList, prompt:GetAttributeChangedSignal("GiftTargetUserId"):Connect(function()
        self:_applyPromptVisibility(prompt)
    end))
    table.insert(connectionList, prompt.AncestryChanged:Connect(function(_, parent)
        if not parent then
            self:_disconnectPrompt(prompt)
        end
    end))

    self:_applyPromptVisibility(prompt)
end

function GiftController:_refreshAllPrompts()
    for _, descendant in ipairs(Workspace:GetDescendants()) do
        if descendant:IsA("ProximityPrompt") and descendant:GetAttribute("GiftPrompt") == true then
            self:_trackPrompt(descendant)
        end
    end

    for prompt in pairs(self._promptConnectionsByPrompt) do
        if not prompt.Parent or prompt:GetAttribute("GiftPrompt") ~= true then
            self:_disconnectPrompt(prompt)
        else
            self:_applyPromptVisibility(prompt)
        end
    end
end

function GiftController:_applyOfferText(offer)
    if type(offer) ~= "table" then
        return
    end

    if self._senderText and self._senderText:IsA("TextLabel") then
        self._senderText.Text = tostring(offer.senderName or "Unknown")
    end
    if self._messageText and self._messageText:IsA("TextLabel") then
        self._messageText.Text = string.format(
            "%s wants to give you: [%s]! Do you accept?",
            tostring(offer.senderName or "Unknown"),
            tostring(offer.brainrotName or "Brainrot")
        )
    end

    if self._portraitImage and (self._portraitImage:IsA("ImageLabel") or self._portraitImage:IsA("ImageButton")) then
        self._portraitImage.Image = ""
        self._avatarRequestToken += 1
        local avatarToken = self._avatarRequestToken
        local senderUserId = normalizeUserId(offer.senderUserId)
        if senderUserId > 0 then
            task.spawn(function()
                local success, image = pcall(function()
                    local thumbnail, _isReady = Players:GetUserThumbnailAsync(
                        senderUserId,
                        Enum.ThumbnailType.HeadShot,
                        Enum.ThumbnailSize.Size420x420
                    )
                    return thumbnail
                end)
                if not success or type(image) ~= "string" then
                    return
                end
                if self._avatarRequestToken ~= avatarToken then
                    return
                end
                if self._portraitImage and self._portraitImage.Parent then
                    self._portraitImage.Image = image
                end
            end)
        end
    end
end

function GiftController:_openOffer(offer)
    self._currentOffer = {
        requestId = normalizeRequestId(type(offer) == "table" and offer.requestId),
        senderUserId = normalizeUserId(type(offer) == "table" and offer.senderUserId),
        senderName = tostring(type(offer) == "table" and offer.senderName or ""),
        brainrotName = tostring(type(offer) == "table" and offer.brainrotName or "Brainrot"),
    }

    if self._currentOffer.requestId <= 0 then
        self._currentOffer = nil
        return
    end

    if not self:_bindMainUi() then
        self:_queueRebind()
        return
    end

    self:_applyOfferText(self._currentOffer)
    self:_openGiftModal()
end

function GiftController:_respondToCurrentOffer(decision)
    local offer = self._currentOffer
    if not offer then
        return
    end

    self._currentOffer = nil
    self:_closeGiftModal()

    if self._requestGiftDecisionEvent then
        self._requestGiftDecisionEvent:FireServer({
            requestId = offer.requestId,
            decision = tostring(decision or "Close"),
        })
    end
end

function GiftController:_handleGiftFeedback(payload)
    local status = tostring(type(payload) == "table" and payload.status or "")
    local targetUserId = normalizeUserId(type(payload) == "table" and payload.targetUserId)
    local requestId = normalizeRequestId(type(payload) == "table" and payload.requestId)
    local cooldownExpiresAt = math.max(0, math.floor(tonumber(type(payload) == "table" and payload.cooldownExpiresAt or 0) or 0))

    if targetUserId ~= 0 then
        if status == "Requested" then
            self._pendingOutgoingByTargetUserId[targetUserId] = true
        elseif status == "Declined" then
            self._pendingOutgoingByTargetUserId[targetUserId] = nil
            self:_setDeclineCooldown(targetUserId, cooldownExpiresAt)
        elseif status == "Accepted" or status == "Cancelled" or status == "Closed" or status == "SaveFailed" or status == "Expired" or status == "SenderBusy" or status == "TargetBusy" or status == "SenderNotHoldingBrainrot" then
            self._pendingOutgoingByTargetUserId[targetUserId] = nil
        end
    end

    if self._currentOffer and self._currentOffer.requestId == requestId then
        if status == "Cancelled" or status == "Closed" or status == "SaveFailed" or status == "Expired" or status == "InvalidRequest" then
            self._currentOffer = nil
            self:_closeGiftModal()
        end
    end

    self:_refreshAllPrompts()
end

function GiftController:_clearUiBindings()
    disconnectAll(self._uiConnections)
end

function GiftController:_bindMainUi()
    local mainGui = self:_getMainGui()
    if not mainGui then
        self:_warnOnce("MissingMain", "[GiftController] 找不到 Main UI，Gift 面板暂不可用。")
        self:_clearUiBindings()
        return false
    end

    self._mainGui = mainGui
    self._giftRoot = self:_resolveGiftRoot(mainGui)
    if not self._giftRoot then
        self:_warnOnce("MissingGiftRoot", "[GiftController] 找不到 Main/Gift，赠送弹窗未绑定。")
        self:_clearUiBindings()
        return false
    end

    self._windowRoot = self:_findDescendantByNames(self._giftRoot, { "Window", "GiftWindow" }) or self._giftRoot
    local titleRoot = self:_findDescendantByNames(self._windowRoot, { "Title" }) or self._windowRoot
    local buttonsRoot = self:_findDescendantByNames(self._windowRoot, { "Buttons", "ButtonGroup", "Btns" }) or self._windowRoot
    local contentRoot = self:_findDescendantByNames(self._windowRoot, { "Content" }) or self._windowRoot
    local portraitFrame = self:_findDescendantByNames(contentRoot, { "PortraitFrame" }) or contentRoot
    local infoRoot = self:_findDescendantByNames(portraitFrame, { "Info" })
        or self:_findDescendantByNames(contentRoot, { "Info" })
        or contentRoot

    self._closeButton = self:_findDescendantByNames(titleRoot, { "CloseButton" })
    self._acceptButton = self:_findDescendantByNames(buttonsRoot, { "AcceptButton", "ButtonsAcceptButton", "Accept" })
        or self:_findDescendantByNames(self._windowRoot, { "AcceptButton", "ButtonsAcceptButton", "Accept" })
    self._declineButton = self:_findDescendantByNames(buttonsRoot, { "DeclineButton", "ButtonsDeclineButton", "Decline" })
        or self:_findDescendantByNames(self._windowRoot, { "DeclineButton", "ButtonsDeclineButton", "Decline" })
    self._portraitImage = self:_findDescendantByNames(portraitFrame, { "PortraitImage" })
    self._senderText = self:_findDescendantByNames(infoRoot, { "SenderText" })
    self._messageText = self:_findDescendantByNames(infoRoot, { "MessageText" })

    self:_clearUiBindings()

    local closeInteractive = self:_resolveInteractiveNode(self._closeButton)
    if closeInteractive then
        table.insert(self._uiConnections, closeInteractive.Activated:Connect(function()
            self:_respondToCurrentOffer("Close")
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
        self:_warnOnce("MissingGiftCloseButton", "[GiftController] 找不到 Gift/Window/Title/CloseButton。")
    end

    local acceptInteractive = self:_resolveInteractiveNode(self._acceptButton)
    if acceptInteractive then
        table.insert(self._uiConnections, acceptInteractive.Activated:Connect(function()
            self:_respondToCurrentOffer("Accept")
        end))
        self:_bindButtonFx(acceptInteractive, {
            ScaleTarget = self._acceptButton,
            HoverScale = 1.05,
            PressScale = 0.93,
            HoverRotation = 0,
        }, self._uiConnections)
    else
        self:_warnOnce("MissingGiftAcceptButton", "[GiftController] 找不到 Gift/Window/Buttons/AcceptButton。")
    end

    local declineInteractive = self:_resolveInteractiveNode(self._declineButton)
    if declineInteractive then
        table.insert(self._uiConnections, declineInteractive.Activated:Connect(function()
            self:_respondToCurrentOffer("Decline")
        end))
        self:_bindButtonFx(declineInteractive, {
            ScaleTarget = self._declineButton,
            HoverScale = 1.05,
            PressScale = 0.93,
            HoverRotation = 0,
        }, self._uiConnections)
    else
        self:_warnOnce("MissingGiftDeclineButton", "[GiftController] 找不到 Gift/Window/Buttons/DeclineButton。")
    end

    if self._currentOffer then
        self:_applyOfferText(self._currentOffer)
        if not self:_isGiftModalOpen() then
            self:_openGiftModal()
        end
    end

    return true
end

function GiftController:_queueRebind()
    if self._rebindQueued then
        return
    end

    self._rebindQueued = true
    task.defer(function()
        self._rebindQueued = false
        self:_bindMainUi()
    end)
end

function GiftController:_scheduleRetryBind()
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

function GiftController:Start()
    if self._started then
        return
    end
    self._started = true

    local eventsRoot = ReplicatedStorage:WaitForChild(RemoteNames.RootFolder)
    local brainrotEvents = eventsRoot:WaitForChild(RemoteNames.BrainrotEventsFolder)
    self._brainrotGiftOfferEvent = brainrotEvents:FindFirstChild(RemoteNames.Brainrot.BrainrotGiftOffer)
        or brainrotEvents:WaitForChild(RemoteNames.Brainrot.BrainrotGiftOffer, 10)
    self._requestGiftDecisionEvent = brainrotEvents:FindFirstChild(RemoteNames.Brainrot.RequestBrainrotGiftDecision)
        or brainrotEvents:WaitForChild(RemoteNames.Brainrot.RequestBrainrotGiftDecision, 10)
    self._brainrotGiftFeedbackEvent = brainrotEvents:FindFirstChild(RemoteNames.Brainrot.BrainrotGiftFeedback)
        or brainrotEvents:WaitForChild(RemoteNames.Brainrot.BrainrotGiftFeedback, 10)

    if self._brainrotGiftOfferEvent and self._brainrotGiftOfferEvent:IsA("RemoteEvent") then
        table.insert(self._persistentConnections, self._brainrotGiftOfferEvent.OnClientEvent:Connect(function(payload)
            self:_openOffer(payload)
        end))
    else
        self:_warnOnce("MissingGiftOfferEvent", "[GiftController] 找不到 BrainrotGiftOffer，Gift 面板不会自动弹出。")
    end

    if self._brainrotGiftFeedbackEvent and self._brainrotGiftFeedbackEvent:IsA("RemoteEvent") then
        table.insert(self._persistentConnections, self._brainrotGiftFeedbackEvent.OnClientEvent:Connect(function(payload)
            self:_handleGiftFeedback(payload)
        end))
    else
        self:_warnOnce("MissingGiftFeedbackEvent", "[GiftController] 找不到 BrainrotGiftFeedback，Gift Prompt 冷却不会自动刷新。")
    end

    table.insert(self._persistentConnections, localPlayer.CharacterAdded:Connect(function(character)
        self:_bindCharacterWatchers(character)
    end))

    self:_bindCharacterWatchers(localPlayer.Character)

    local playerGui = self:_getPlayerGui()
    if playerGui then
        table.insert(self._persistentConnections, playerGui.DescendantAdded:Connect(function(descendant)
            local watchedNames = {
                Main = true,
                Gift = true,
                Window = true,
                GiftWindow = true,
                Buttons = true,
                ButtonGroup = true,
                Btns = true,
                AcceptButton = true,
                ButtonsAcceptButton = true,
                Accept = true,
                DeclineButton = true,
                ButtonsDeclineButton = true,
                Decline = true,
                Title = true,
                CloseButton = true,
                Content = true,
                PortraitFrame = true,
                PortraitImage = true,
                Info = true,
                SenderText = true,
                MessageText = true,
            }
            if watchedNames[descendant.Name] then
                self:_queueRebind()
            end
        end))
    end

    table.insert(self._persistentConnections, Workspace.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("ProximityPrompt") and descendant:GetAttribute("GiftPrompt") == true then
            self:_trackPrompt(descendant)
        end
    end))

    table.insert(self._persistentConnections, ProximityPromptService.PromptShown:Connect(function(prompt)
        self:_trackPrompt(prompt)
        self:_applyPromptVisibility(prompt)
    end))

    self:_refreshAllPrompts()
    self:_scheduleRetryBind()
end

return GiftController

