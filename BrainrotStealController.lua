--[[
ScriptName: BrainrotStealController
FileName: BrainrotStealController.lua
ScriptType: ModuleScript
StudioPath: StarterPlayer/StarterPlayerScripts/Controllers/BrainrotStealController
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
        "[BrainrotStealController] Missing shared module %s (expected in ReplicatedStorage/Shared or ReplicatedStorage root)",
        moduleName
    ))
end

local RemoteNames = requireSharedModule("RemoteNames")

local BRAINROT_PLACED_PICKUP_PROMPT_ATTRIBUTE = "BrainrotPlacedPickupPrompt"
local BRAINROT_PLACED_PICKUP_OWNER_USER_ID_ATTRIBUTE = "BrainrotPlacedPickupOwnerUserId"
local BRAINROT_PLACED_PICKUP_SERVER_ENABLED_ATTRIBUTE = "BrainrotPlacedPickupServerEnabled"
local BRAINROT_STEAL_PROMPT_ATTRIBUTE = "BrainrotStealPrompt"
local BRAINROT_STEAL_OWNER_USER_ID_ATTRIBUTE = "BrainrotStealOwnerUserId"
local BRAINROT_STEAL_SERVER_ENABLED_ATTRIBUTE = "BrainrotStealServerEnabled"

local BrainrotStealController = {}
BrainrotStealController.__index = BrainrotStealController

local function offsetY(position, yOffset)
    return UDim2.new(
        position.X.Scale,
        position.X.Offset,
        position.Y.Scale,
        position.Y.Offset + yOffset
    )
end

local function isTipsRoot(node)
    if not node then
        return false
    end

    return node:IsA("ScreenGui") or node:IsA("GuiObject")
end

local function findStealTipsRoot(playerGui)
    if not playerGui then
        return nil
    end

    local direct = playerGui:FindFirstChild("StealTips")
    if direct and isTipsRoot(direct) then
        return direct
    end

    local nested = playerGui:FindFirstChild("StealTips", true)
    if nested and isTipsRoot(nested) then
        return nested
    end

    return nil
end

function BrainrotStealController.new()
    local self = setmetatable({}, BrainrotStealController)
    self._stealTipsRoot = nil
    self._stealTipsTextLabel = nil
    self._stealTipsBasePosition = nil
    self._stealTipQueue = {}
    self._isShowingStealTip = false
    self._didWarnStealTipsMissing = false
    self._didWarnStealTipsTextMissing = false
    self._promptConnectionsByPrompt = {}
    self._workspaceDescendantAddedConnection = nil
    self._promptShownConnection = nil
    self._activePurchaseRequestId = ""
    self._activePurchaseProductId = 0
    self._requestBrainrotStealPurchaseClosedEvent = nil
    return self
end

function BrainrotStealController:_setStealTipsVisible(visible)
    if not self._stealTipsRoot then
        return
    end

    if self._stealTipsRoot:IsA("ScreenGui") then
        self._stealTipsRoot.Enabled = visible
        return
    end

    if self._stealTipsRoot:IsA("GuiObject") then
        self._stealTipsRoot.Visible = visible
    end
end

function BrainrotStealController:_setStealTipsTextAppearance(textTransparency, strokeTransparency)
    local label = self._stealTipsTextLabel
    if not label then
        return
    end

    label.TextTransparency = textTransparency
    label.TextStrokeTransparency = strokeTransparency
end

function BrainrotStealController:_ensureStealTipsNodes()
    if self._stealTipsRoot and self._stealTipsRoot.Parent and self._stealTipsTextLabel and self._stealTipsTextLabel.Parent then
        return true
    end

    local playerGui = localPlayer:FindFirstChild("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
    if not playerGui then
        if not self._didWarnStealTipsMissing then
            warn("[BrainrotStealController] PlayerGui not found; StealTips is unavailable.")
            self._didWarnStealTipsMissing = true
        end
        return false
    end

    local stealTipsRoot = findStealTipsRoot(playerGui)
    if not stealTipsRoot then
        if not self._didWarnStealTipsMissing then
            warn("[BrainrotStealController] StealTips UI not found.")
            self._didWarnStealTipsMissing = true
        end
        return false
    end

    local textLabel = stealTipsRoot:FindFirstChild("Text", true)
    if not (textLabel and textLabel:IsA("TextLabel")) then
        textLabel = stealTipsRoot:FindFirstChildWhichIsA("TextLabel", true)
    end

    if not textLabel then
        if not self._didWarnStealTipsTextMissing then
            warn("[BrainrotStealController] StealTips exists but is missing a TextLabel.")
            self._didWarnStealTipsTextMissing = true
        end
        return false
    end

    self._didWarnStealTipsMissing = false
    self._didWarnStealTipsTextMissing = false
    self._stealTipsRoot = stealTipsRoot
    self._stealTipsTextLabel = textLabel
    self._stealTipsBasePosition = textLabel.Position
    self:_setStealTipsVisible(false)
    return true
end

function BrainrotStealController:_showNextStealTip()
    if self._isShowingStealTip then
        return
    end

    if #self._stealTipQueue <= 0 then
        self:_setStealTipsVisible(false)
        return
    end

    self._isShowingStealTip = true
    local message = table.remove(self._stealTipQueue, 1)

    if not self:_ensureStealTipsNodes() then
        self._isShowingStealTip = false
        table.insert(self._stealTipQueue, 1, message)
        task.delay(1, function()
            if not self._isShowingStealTip and #self._stealTipQueue > 0 then
                self:_showNextStealTip()
            end
        end)
        return
    end

    local label = self._stealTipsTextLabel
    local basePosition = self._stealTipsBasePosition
    if not label or not basePosition then
        self._isShowingStealTip = false
        self:_setStealTipsVisible(false)
        return
    end

    self:_setStealTipsVisible(true)
    label.Text = tostring(message or "")
    label.Position = offsetY(basePosition, 40)
    self:_setStealTipsTextAppearance(0, 0)

    local enterTween = TweenService:Create(label, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = basePosition,
    })

    enterTween.Completed:Connect(function()
        task.delay(2, function()
            if not label or not label.Parent then
                self._isShowingStealTip = false
                self:_showNextStealTip()
                return
            end

            local fadeTween = TweenService:Create(label, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                TextTransparency = 1,
                TextStrokeTransparency = 1,
                Position = offsetY(basePosition, -8),
            })

            fadeTween.Completed:Connect(function()
                if label and label.Parent then
                    label.Position = basePosition
                    self:_setStealTipsTextAppearance(0, 0)
                end

                self._isShowingStealTip = false
                if #self._stealTipQueue <= 0 then
                    self:_setStealTipsVisible(false)
                end
                self:_showNextStealTip()
            end)

            fadeTween:Play()
        end)
    end)

    enterTween:Play()
end

function BrainrotStealController:_enqueueStealTip(message)
    if tostring(message or "") == "" then
        return
    end

    table.insert(self._stealTipQueue, tostring(message))
    self:_showNextStealTip()
end

function BrainrotStealController:_isManagedPrompt(prompt)
    if not (prompt and prompt:IsA("ProximityPrompt")) then
        return false
    end

    return prompt:GetAttribute(BRAINROT_PLACED_PICKUP_PROMPT_ATTRIBUTE) == true
        or prompt:GetAttribute(BRAINROT_STEAL_PROMPT_ATTRIBUTE) == true
end

function BrainrotStealController:_shouldShowPrompt(prompt)
    if prompt:GetAttribute(BRAINROT_STEAL_PROMPT_ATTRIBUTE) == true then
        local ownerUserId = math.floor(tonumber(prompt:GetAttribute(BRAINROT_STEAL_OWNER_USER_ID_ATTRIBUTE)) or 0)
        if ownerUserId <= 0 then
            return false
        end

        return ownerUserId ~= localPlayer.UserId
            and prompt:GetAttribute(BRAINROT_STEAL_SERVER_ENABLED_ATTRIBUTE) == true
    end

    if prompt:GetAttribute(BRAINROT_PLACED_PICKUP_PROMPT_ATTRIBUTE) == true then
        local ownerUserId = math.floor(tonumber(prompt:GetAttribute(BRAINROT_PLACED_PICKUP_OWNER_USER_ID_ATTRIBUTE)) or 0)
        if ownerUserId <= 0 then
            return false
        end

        return ownerUserId == localPlayer.UserId
            and prompt:GetAttribute(BRAINROT_PLACED_PICKUP_SERVER_ENABLED_ATTRIBUTE) == true
    end

    return true
end

function BrainrotStealController:_applyPromptVisibility(prompt)
    if not self:_isManagedPrompt(prompt) then
        return
    end

    local shouldShow = self:_shouldShowPrompt(prompt)
    if prompt.Enabled ~= shouldShow then
        prompt.Enabled = shouldShow
    end
end

function BrainrotStealController:_disconnectPrompt(prompt)
    local connectionList = self._promptConnectionsByPrompt[prompt]
    if type(connectionList) ~= "table" then
        return
    end

    for _, connection in ipairs(connectionList) do
        if connection and connection.Disconnect then
            connection:Disconnect()
        end
    end

    self._promptConnectionsByPrompt[prompt] = nil
end

function BrainrotStealController:_trackPrompt(prompt)
    if not (prompt and prompt:IsA("ProximityPrompt")) then
        return
    end

    if not self:_isManagedPrompt(prompt) then
        self:_disconnectPrompt(prompt)
        return
    end

    if self._promptConnectionsByPrompt[prompt] then
        self:_applyPromptVisibility(prompt)
        return
    end

    local connectionList = {}
    self._promptConnectionsByPrompt[prompt] = connectionList

    local function connectAttribute(attributeName)
        table.insert(connectionList, prompt:GetAttributeChangedSignal(attributeName):Connect(function()
            if not self:_isManagedPrompt(prompt) then
                self:_disconnectPrompt(prompt)
                return
            end
            self:_applyPromptVisibility(prompt)
        end))
    end

    connectAttribute(BRAINROT_PLACED_PICKUP_PROMPT_ATTRIBUTE)
    connectAttribute(BRAINROT_PLACED_PICKUP_OWNER_USER_ID_ATTRIBUTE)
    connectAttribute(BRAINROT_PLACED_PICKUP_SERVER_ENABLED_ATTRIBUTE)
    connectAttribute(BRAINROT_STEAL_PROMPT_ATTRIBUTE)
    connectAttribute(BRAINROT_STEAL_OWNER_USER_ID_ATTRIBUTE)
    connectAttribute(BRAINROT_STEAL_SERVER_ENABLED_ATTRIBUTE)

    table.insert(connectionList, prompt.AncestryChanged:Connect(function(_, parent)
        if not parent then
            self:_disconnectPrompt(prompt)
        end
    end))

    self:_applyPromptVisibility(prompt)
end

function BrainrotStealController:_refreshAllPrompts()
    for _, descendant in ipairs(Workspace:GetDescendants()) do
        if descendant:IsA("ProximityPrompt") then
            self:_trackPrompt(descendant)
        end
    end

    for prompt in pairs(self._promptConnectionsByPrompt) do
        if not prompt.Parent or not self:_isManagedPrompt(prompt) then
            self:_disconnectPrompt(prompt)
        else
            self:_applyPromptVisibility(prompt)
        end
    end
end

function BrainrotStealController:_promptStealPurchase(payload)
    local requestId = type(payload) == "table" and tostring(payload.requestId or "") or ""
    local productId = type(payload) == "table" and math.floor(tonumber(payload.productId) or 0) or 0
    if requestId == "" or productId <= 0 then
        return
    end

    self._activePurchaseRequestId = requestId
    self._activePurchaseProductId = productId

    local success, err = pcall(function()
        MarketplaceService:PromptProductPurchase(localPlayer, productId)
    end)
    if success then
        return
    end

    warn(string.format("[BrainrotStealController] Failed to prompt steal purchase productId=%d requestId=%s err=%s", productId, requestId, tostring(err)))
    if self._requestBrainrotStealPurchaseClosedEvent then
        self._requestBrainrotStealPurchaseClosedEvent:FireServer({
            requestId = requestId,
            productId = productId,
            isPurchased = false,
            status = "PromptFailed",
        })
    end
    self._activePurchaseRequestId = ""
    self._activePurchaseProductId = 0
end

function BrainrotStealController:Start()
    self:_ensureStealTipsNodes()

    local eventsRoot = ReplicatedStorage:WaitForChild(RemoteNames.RootFolder)
    local systemEvents = eventsRoot:WaitForChild(RemoteNames.SystemEventsFolder)
    local brainrotEvents = eventsRoot:WaitForChild(RemoteNames.BrainrotEventsFolder)

    local stealTipEvent = systemEvents:FindFirstChild(RemoteNames.System.StealTip)
    local promptBrainrotStealPurchaseEvent = brainrotEvents:FindFirstChild(RemoteNames.Brainrot.PromptBrainrotStealPurchase)
    local requestBrainrotStealPurchaseClosedEvent = brainrotEvents:FindFirstChild(RemoteNames.Brainrot.RequestBrainrotStealPurchaseClosed)
    local brainrotStealFeedbackEvent = brainrotEvents:FindFirstChild(RemoteNames.Brainrot.BrainrotStealFeedback)

    self._requestBrainrotStealPurchaseClosedEvent = requestBrainrotStealPurchaseClosedEvent

    if stealTipEvent and stealTipEvent:IsA("RemoteEvent") then
        stealTipEvent.OnClientEvent:Connect(function(payload)
            local message = type(payload) == "table" and payload.message or payload
            self:_enqueueStealTip(message)
        end)
    end

    if promptBrainrotStealPurchaseEvent and promptBrainrotStealPurchaseEvent:IsA("RemoteEvent") then
        promptBrainrotStealPurchaseEvent.OnClientEvent:Connect(function(payload)
            self:_promptStealPurchase(payload)
        end)
    end

    if brainrotStealFeedbackEvent and brainrotStealFeedbackEvent:IsA("RemoteEvent") then
        brainrotStealFeedbackEvent.OnClientEvent:Connect(function(payload)
            if type(payload) ~= "table" then
                return
            end

            local status = tostring(payload.status or "")
            local message = tostring(payload.message or "")
            if status ~= "" and status ~= "Success" and status ~= "Cancelled" and message ~= "" then
                warn(string.format("[BrainrotStealController] %s: %s", status, message))
            end
        end)
    end

    MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, isPurchased)
        if userId ~= localPlayer.UserId then
            return
        end

        local requestId = self._activePurchaseRequestId
        local activeProductId = self._activePurchaseProductId
        if requestId == "" or activeProductId <= 0 or productId ~= activeProductId then
            return
        end

        if self._requestBrainrotStealPurchaseClosedEvent then
            self._requestBrainrotStealPurchaseClosedEvent:FireServer({
                requestId = requestId,
                productId = productId,
                isPurchased = isPurchased == true,
            })
        end

        self._activePurchaseRequestId = ""
        self._activePurchaseProductId = 0
    end)

    self._workspaceDescendantAddedConnection = Workspace.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("ProximityPrompt") then
            self:_trackPrompt(descendant)
        end
    end)

    self._promptShownConnection = ProximityPromptService.PromptShown:Connect(function(prompt)
        self:_trackPrompt(prompt)
        self:_applyPromptVisibility(prompt)
    end)

    self:_refreshAllPrompts()
end

return BrainrotStealController
