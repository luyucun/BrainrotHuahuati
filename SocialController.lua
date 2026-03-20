--[[
脚本名字: SocialController
脚本文件: SocialController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/SocialController
]]

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
        "[SocialController] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local RemoteNames = requireSharedModule("RemoteNames")

local SocialController = {}
SocialController.__index = SocialController

local function offsetY(position, yOffset)
    return UDim2.new(
        position.X.Scale,
        position.X.Offset,
        position.Y.Scale,
        position.Y.Offset + yOffset
    )
end

function SocialController.new()
    local self = setmetatable({}, SocialController)
    self._likeTipsRoot = nil
    self._likeTipsTextLabel = nil
    self._likeTipsBasePosition = nil
    self._likeTipQueue = {}
    self._isShowingLikeTip = false
    self._didWarnLikeTipsMissing = false
    self._didWarnLikeTipsTextMissing = false
    self._likedOwnerUserIds = {}
    self._promptConnectionsByPrompt = {}
    self._workspaceDescendantAddedConnection = nil
    self._promptShownConnection = nil
    return self
end

local function isLikeTipsRoot(node)
    if not node then
        return false
    end

    return node:IsA("ScreenGui") or node:IsA("GuiObject")
end

local function findLikeTipsRoot(playerGui)
    if not playerGui then
        return nil
    end

    local direct = playerGui:FindFirstChild("LikeTips")
    if direct and isLikeTipsRoot(direct) then
        return direct
    end

    local nested = playerGui:FindFirstChild("LikeTips", true)
    if nested and isLikeTipsRoot(nested) then
        return nested
    end

    return nil
end

function SocialController:_setLikeTipsVisible(visible)
    if not self._likeTipsRoot then
        return
    end

    if self._likeTipsRoot:IsA("ScreenGui") then
        self._likeTipsRoot.Enabled = visible
        return
    end

    if self._likeTipsRoot:IsA("GuiObject") then
        self._likeTipsRoot.Visible = visible
    end
end

function SocialController:_setLikeTipsTextAppearance(textTransparency, strokeTransparency)
    local label = self._likeTipsTextLabel
    if not label then
        return
    end

    label.TextTransparency = textTransparency
    label.TextStrokeTransparency = strokeTransparency
end

function SocialController:_ensureLikeTipsNodes()
    if self._likeTipsRoot and self._likeTipsRoot.Parent and self._likeTipsTextLabel and self._likeTipsTextLabel.Parent then
        return true
    end

    local playerGui = localPlayer:FindFirstChild("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
    if not playerGui then
        if not self._didWarnLikeTipsMissing then
            warn("[SocialController] 找不到 PlayerGui，LikeTips 提示功能暂不可用。")
            self._didWarnLikeTipsMissing = true
        end
        return false
    end

    local likeTipsRoot = findLikeTipsRoot(playerGui)
    if not likeTipsRoot then
        if not self._didWarnLikeTipsMissing then
            warn("[SocialController] 找不到 LikeTips UI（支持 PlayerGui/LikeTips 或嵌套同名节点）。")
            self._didWarnLikeTipsMissing = true
        end
        return false
    end

    local textLabel = likeTipsRoot:FindFirstChild("Text", true)
    if not (textLabel and textLabel:IsA("TextLabel")) then
        textLabel = likeTipsRoot:FindFirstChildWhichIsA("TextLabel", true)
    end

    if not textLabel then
        if not self._didWarnLikeTipsTextMissing then
            warn("[SocialController] LikeTips 节点存在但缺少 TextLabel（建议检查 LikeTips/Text）。")
            self._didWarnLikeTipsTextMissing = true
        end
        return false
    end

    self._didWarnLikeTipsMissing = false
    self._didWarnLikeTipsTextMissing = false
    self._likeTipsRoot = likeTipsRoot
    self._likeTipsTextLabel = textLabel
    self._likeTipsBasePosition = textLabel.Position
    self:_setLikeTipsVisible(false)
    return true
end

function SocialController:_showNextLikeTip()
    if self._isShowingLikeTip then
        return
    end

    if #self._likeTipQueue <= 0 then
        self:_setLikeTipsVisible(false)
        return
    end

    self._isShowingLikeTip = true
    local message = table.remove(self._likeTipQueue, 1)

    if not self:_ensureLikeTipsNodes() then
        self._isShowingLikeTip = false
        table.insert(self._likeTipQueue, 1, message)
        task.delay(1, function()
            if not self._isShowingLikeTip and #self._likeTipQueue > 0 then
                self:_showNextLikeTip()
            end
        end)
        return
    end

    local label = self._likeTipsTextLabel
    local basePosition = self._likeTipsBasePosition
    if not label or not basePosition then
        self._isShowingLikeTip = false
        self:_setLikeTipsVisible(false)
        return
    end

    self:_setLikeTipsVisible(true)
    label.Text = tostring(message or "")
    label.Position = offsetY(basePosition, 40)
    self:_setLikeTipsTextAppearance(0, 0)

    local enterTween = TweenService:Create(label, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = basePosition,
    })

    enterTween.Completed:Connect(function()
        task.delay(2, function()
            if not label or not label.Parent then
                self._isShowingLikeTip = false
                self:_showNextLikeTip()
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
                    self:_setLikeTipsTextAppearance(0, 0)
                end

                self._isShowingLikeTip = false
                if #self._likeTipQueue <= 0 then
                    self:_setLikeTipsVisible(false)
                end
                self:_showNextLikeTip()
            end)

            fadeTween:Play()
        end)
    end)

    enterTween:Play()
end

function SocialController:_enqueueLikeTip(message)
    if tostring(message or "") == "" then
        return
    end

    table.insert(self._likeTipQueue, tostring(message))
    self:_showNextLikeTip()
end

function SocialController:_shouldShowPrompt(prompt)
    local ownerUserId = math.floor(tonumber(prompt:GetAttribute("InfoOwnerUserId")) or 0)
    if ownerUserId <= 0 then
        return false
    end

    if ownerUserId == localPlayer.UserId then
        return false
    end

    if self._likedOwnerUserIds[ownerUserId] then
        return false
    end

    return true
end

function SocialController:_applyPromptVisibility(prompt)
    if not (prompt and prompt:IsA("ProximityPrompt")) then
        return
    end

    if prompt:GetAttribute("SocialLikePrompt") ~= true then
        return
    end

    local shouldShow = self:_shouldShowPrompt(prompt)
    if prompt.Enabled ~= shouldShow then
        prompt.Enabled = shouldShow
    end
end

function SocialController:_disconnectPrompt(prompt)
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

function SocialController:_trackPrompt(prompt)
    if not (prompt and prompt:IsA("ProximityPrompt")) then
        return
    end

    if prompt:GetAttribute("SocialLikePrompt") ~= true then
        return
    end

    if self._promptConnectionsByPrompt[prompt] then
        self:_applyPromptVisibility(prompt)
        return
    end

    local connectionList = {}
    self._promptConnectionsByPrompt[prompt] = connectionList

    table.insert(connectionList, prompt:GetAttributeChangedSignal("SocialLikePrompt"):Connect(function()
        if prompt:GetAttribute("SocialLikePrompt") ~= true then
            self:_disconnectPrompt(prompt)
            return
        end
        self:_applyPromptVisibility(prompt)
    end))
    table.insert(connectionList, prompt:GetAttributeChangedSignal("InfoOwnerUserId"):Connect(function()
        self:_applyPromptVisibility(prompt)
    end))
    table.insert(connectionList, prompt.AncestryChanged:Connect(function(_, parent)
        if not parent then
            self:_disconnectPrompt(prompt)
        end
    end))

    self:_applyPromptVisibility(prompt)
end

function SocialController:_refreshAllPrompts()
    for _, descendant in ipairs(Workspace:GetDescendants()) do
        if descendant:IsA("ProximityPrompt") and descendant:GetAttribute("SocialLikePrompt") == true then
            self:_trackPrompt(descendant)
        end
    end

    for prompt in pairs(self._promptConnectionsByPrompt) do
        if not prompt.Parent or prompt:GetAttribute("SocialLikePrompt") ~= true then
            self:_disconnectPrompt(prompt)
        else
            self:_applyPromptVisibility(prompt)
        end
    end
end

function SocialController:_setLikedOwnerUserIds(ownerUserIds)
    self._likedOwnerUserIds = {}
    if type(ownerUserIds) == "table" then
        for _, ownerUserId in ipairs(ownerUserIds) do
            local parsed = math.floor(tonumber(ownerUserId) or 0)
            if parsed > 0 then
                self._likedOwnerUserIds[parsed] = true
            end
        end
    end

    for prompt in pairs(self._promptConnectionsByPrompt) do
        self:_applyPromptVisibility(prompt)
    end
end

function SocialController:Start()
    self:_ensureLikeTipsNodes()

    local eventsRoot = ReplicatedStorage:WaitForChild(RemoteNames.RootFolder)
    local systemEvents = eventsRoot:WaitForChild(RemoteNames.SystemEventsFolder)

    local likeTipEvent = systemEvents:FindFirstChild(RemoteNames.System.LikeTip)
    local socialStateSyncEvent = systemEvents:FindFirstChild(RemoteNames.System.SocialStateSync)
    local requestSocialStateSyncEvent = systemEvents:FindFirstChild(RemoteNames.System.RequestSocialStateSync)

    if likeTipEvent and likeTipEvent:IsA("RemoteEvent") then
        likeTipEvent.OnClientEvent:Connect(function(payload)
            local message = type(payload) == "table" and payload.message or payload
            self:_enqueueLikeTip(message)
        end)
    end

    if socialStateSyncEvent and socialStateSyncEvent:IsA("RemoteEvent") then
        socialStateSyncEvent.OnClientEvent:Connect(function(payload)
            local likedOwnerUserIds = type(payload) == "table" and payload.likedOwnerUserIds or nil
            self:_setLikedOwnerUserIds(likedOwnerUserIds)
        end)
    end

    self._workspaceDescendantAddedConnection = Workspace.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("ProximityPrompt") and descendant:GetAttribute("SocialLikePrompt") == true then
            self:_trackPrompt(descendant)
        end
    end)

    self._promptShownConnection = ProximityPromptService.PromptShown:Connect(function(prompt)
        self:_trackPrompt(prompt)
        self:_applyPromptVisibility(prompt)
    end)

    self:_refreshAllPrompts()

    if requestSocialStateSyncEvent and requestSocialStateSyncEvent:IsA("RemoteEvent") then
        requestSocialStateSyncEvent:FireServer()
    end
end

return SocialController
