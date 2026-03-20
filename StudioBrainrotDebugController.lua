--[[
脚本名字: StudioBrainrotDebugController
脚本文件: StudioBrainrotDebugController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/StudioBrainrotDebugController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
local TOGGLE_KEY = Enum.KeyCode.V
local GUI_NAME = "StudioBrainrotDebugGui"

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
        "[StudioBrainrotDebugController] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local BrainrotConfig = requireSharedModule("BrainrotConfig")
local FormatUtil = requireSharedModule("FormatUtil")
local RemoteNames = requireSharedModule("RemoteNames")

local StudioBrainrotDebugController = {}
StudioBrainrotDebugController.__index = StudioBrainrotDebugController

local function disconnectAll(connectionList)
    for _, connection in ipairs(connectionList) do
        if connection then
            connection:Disconnect()
        end
    end
    table.clear(connectionList)
end

local function makeCorner(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = parent
    return corner
end

local function makeStroke(parent, color, thickness, transparency)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color
    stroke.Thickness = thickness or 1
    stroke.Transparency = transparency or 0
    stroke.Parent = parent
    return stroke
end

local function makeTextLabel(name, parent, size, position, text, textSize, font, color, xAlignment)
    local label = Instance.new("TextLabel")
    label.Name = name
    label.BackgroundTransparency = 1
    label.Size = size
    label.Position = position
    label.Font = font or Enum.Font.Gotham
    label.Text = text or ""
    label.TextColor3 = color or Color3.fromRGB(255, 255, 255)
    label.TextSize = textSize or 14
    label.TextWrapped = false
    label.TextXAlignment = xAlignment or Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.Parent = parent
    return label
end

local function makeTextButton(name, parent, size, position, text, textSize, backgroundColor, textColor)
    local button = Instance.new("TextButton")
    button.Name = name
    button.Size = size
    button.Position = position
    button.AutoButtonColor = true
    button.BackgroundColor3 = backgroundColor or Color3.fromRGB(76, 170, 255)
    button.Font = Enum.Font.GothamBold
    button.Text = text or ""
    button.TextColor3 = textColor or Color3.fromRGB(255, 255, 255)
    button.TextSize = textSize or 16
    button.Parent = parent
    makeCorner(button, 10)
    makeStroke(button, Color3.fromRGB(255, 255, 255), 1, 0.8)
    return button
end

local function formatQualityName(qualityId)
    local parsedQualityId = math.floor(tonumber(qualityId) or 0)
    return BrainrotConfig.QualityNames[parsedQualityId] or string.format("Quality %d", parsedQualityId)
end

local function formatRarityName(rarityId)
    local parsedRarityId = math.floor(tonumber(rarityId) or 0)
    return BrainrotConfig.RarityNames[parsedRarityId] or string.format("Rarity %d", parsedRarityId)
end

local function formatSpeed(coinPerSecond)
    return FormatUtil.FormatCompactCurrencyPerSecond(coinPerSecond, 1)
end

function StudioBrainrotDebugController.new()
    local self = setmetatable({}, StudioBrainrotDebugController)
    self._started = false
    self._connections = {}
    self._screenGui = nil
    self._statusLabel = nil
    self._scrollingFrame = nil
    self._requestGrantEvent = nil
    self._feedbackEvent = nil
    self._feedbackBound = false
    self._didWarnMissingRemote = false
    return self
end

function StudioBrainrotDebugController:_warnMissingRemote()
    if self._didWarnMissingRemote then
        return
    end

    self._didWarnMissingRemote = true
    warn("[StudioBrainrotDebugController] Studio 调试脑红 RemoteEvent 缺失，无法发送测试发放请求。")
end

function StudioBrainrotDebugController:_getPlayerGui()
    return localPlayer:FindFirstChild("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
end

function StudioBrainrotDebugController:_setStatus(message, color)
    if not self._statusLabel then
        return
    end

    self._statusLabel.Text = tostring(message or "")
    self._statusLabel.TextColor3 = color or Color3.fromRGB(201, 214, 228)
end

function StudioBrainrotDebugController:_refreshCanvasSize()
    if not (self._scrollingFrame and self._scrollingFrame.Parent) then
        return
    end

    local layout = self._scrollingFrame:FindFirstChildOfClass("UIListLayout")
    if not layout then
        return
    end

    self._scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 14)
end

function StudioBrainrotDebugController:_resolveEvents()
    if self._requestGrantEvent and self._feedbackEvent then
        return true
    end

    local eventsRoot = ReplicatedStorage:FindFirstChild(RemoteNames.RootFolder) or ReplicatedStorage:WaitForChild(RemoteNames.RootFolder, 5)
    if not eventsRoot then
        return false
    end

    local brainrotEvents = eventsRoot:FindFirstChild(RemoteNames.BrainrotEventsFolder) or eventsRoot:WaitForChild(RemoteNames.BrainrotEventsFolder, 5)
    if not brainrotEvents then
        return false
    end

    local requestEvent = brainrotEvents:FindFirstChild(RemoteNames.Brainrot.RequestStudioBrainrotGrant)
        or brainrotEvents:WaitForChild(RemoteNames.Brainrot.RequestStudioBrainrotGrant, 5)
    local feedbackEvent = brainrotEvents:FindFirstChild(RemoteNames.Brainrot.StudioBrainrotGrantFeedback)
        or brainrotEvents:WaitForChild(RemoteNames.Brainrot.StudioBrainrotGrantFeedback, 5)

    if requestEvent and requestEvent:IsA("RemoteEvent") then
        self._requestGrantEvent = requestEvent
    end

    if feedbackEvent and feedbackEvent:IsA("RemoteEvent") then
        self._feedbackEvent = feedbackEvent
    end

    return self._requestGrantEvent ~= nil and self._feedbackEvent ~= nil
end

function StudioBrainrotDebugController:_bindFeedbackEventIfNeeded()
    if self._feedbackBound or not self._feedbackEvent then
        return
    end

    self._feedbackBound = true
    table.insert(self._connections, self._feedbackEvent.OnClientEvent:Connect(function(payload)
        self:_handleFeedback(payload)
    end))
end

function StudioBrainrotDebugController:_sendBrainrot(entry)
    if type(entry) ~= "table" then
        return
    end

    if not self:_resolveEvents() then
        self:_warnMissingRemote()
        self:_setStatus("Studio 调试 Remote 未就绪，无法发送。", Color3.fromRGB(255, 170, 115))
        return
    end

    self:_setStatus(string.format("正在发送 %s ...", tostring(entry.Name or entry.Id)), Color3.fromRGB(123, 210, 255))
    self._requestGrantEvent:FireServer({
        brainrotId = entry.Id,
    })
end

function StudioBrainrotDebugController:_handleFeedback(payload)
    if type(payload) ~= "table" then
        return
    end

    local status = tostring(payload.status or "Unknown")
    local brainrotName = tostring(payload.brainrotName or "")
    local grantedCount = math.max(0, math.floor(tonumber(payload.grantedCount) or 0))
    if brainrotName == "" then
        local definition = BrainrotConfig.ById[math.floor(tonumber(payload.brainrotId) or 0)]
        brainrotName = definition and tostring(definition.Name or "") or "Unknown"
    end

    if status == "Success" then
        self:_setStatus(string.format("已为当前玩家发放 %d 个 %s。", math.max(1, grantedCount), brainrotName), Color3.fromRGB(127, 226, 156))
        return
    end

    if status == "NotStudio" then
        self:_setStatus("当前不是 Studio 环境，调试发放已被服务端拒绝。", Color3.fromRGB(255, 136, 136))
        return
    end

    if status == "BrainrotNotFound" or status == "InvalidBrainrotId" then
        self:_setStatus("目标脑红配置不存在，发放失败。", Color3.fromRGB(255, 170, 115))
        return
    end

    if status == "PlayerDataNotReady" then
        self:_setStatus("玩家数据尚未准备完成，请稍后再试。", Color3.fromRGB(255, 170, 115))
        return
    end

    self:_setStatus(string.format("发放失败：%s", status), Color3.fromRGB(255, 170, 115))
end

function StudioBrainrotDebugController:_buildEntryRow(entry, layoutOrder)
    local row = Instance.new("Frame")
    row.Name = string.format("Brainrot_%d", math.floor(tonumber(entry.Id) or 0))
    row.LayoutOrder = layoutOrder or 0
    row.BackgroundColor3 = Color3.fromRGB(20, 29, 43)
    row.BorderSizePixel = 0
    row.Size = UDim2.new(1, 0, 0, 76)
    row.Parent = self._scrollingFrame
    makeCorner(row, 12)
    makeStroke(row, Color3.fromRGB(113, 134, 163), 1, 0.65)

    local nameLabel = makeTextLabel(
        "Name",
        row,
        UDim2.new(1, -140, 0, 24),
        UDim2.new(0, 14, 0, 10),
        tostring(entry.Name or entry.Id),
        18,
        Enum.Font.GothamBold,
        Color3.fromRGB(255, 255, 255),
        Enum.TextXAlignment.Left
    )
    nameLabel.TextTruncate = Enum.TextTruncate.AtEnd

    local metaLabel = makeTextLabel(
        "Meta",
        row,
        UDim2.new(1, -140, 0, 18),
        UDim2.new(0, 14, 0, 38),
        string.format("品质: %s    稀有度: %s", formatQualityName(entry.Quality), formatRarityName(entry.Rarity)),
        13,
        Enum.Font.Gotham,
        Color3.fromRGB(176, 193, 214),
        Enum.TextXAlignment.Left
    )
    metaLabel.TextTruncate = Enum.TextTruncate.AtEnd

    local speedLabel = makeTextLabel(
        "Speed",
        row,
        UDim2.new(1, -140, 0, 18),
        UDim2.new(0, 14, 0, 55),
        string.format("产速: %s", formatSpeed(entry.CoinPerSecond or 0)),
        13,
        Enum.Font.GothamMedium,
        Color3.fromRGB(120, 225, 178),
        Enum.TextXAlignment.Left
    )
    speedLabel.TextTruncate = Enum.TextTruncate.AtEnd

    local sendButton = makeTextButton(
        "SendButton",
        row,
        UDim2.new(0, 96, 0, 38),
        UDim2.new(1, -110, 0.5, -19),
        "Send",
        16,
        Color3.fromRGB(62, 154, 255),
        Color3.fromRGB(255, 255, 255)
    )
    sendButton.Activated:Connect(function()
        self:_sendBrainrot(entry)
    end)
end

function StudioBrainrotDebugController:_buildGui()
    local playerGui = self:_getPlayerGui()
    if not playerGui then
        return
    end

    local existingGui = playerGui:FindFirstChild(GUI_NAME)
    if existingGui and existingGui:IsA("ScreenGui") then
        existingGui:Destroy()
    end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = GUI_NAME
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.DisplayOrder = 2500
    screenGui.Enabled = false
    screenGui.Parent = playerGui
    self._screenGui = screenGui

    local overlay = Instance.new("Frame")
    overlay.Name = "Overlay"
    overlay.BackgroundColor3 = Color3.fromRGB(7, 10, 16)
    overlay.BackgroundTransparency = 0.2
    overlay.BorderSizePixel = 0
    overlay.Size = UDim2.fromScale(1, 1)
    overlay.Parent = screenGui

    local panel = Instance.new("Frame")
    panel.Name = "Panel"
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.fromScale(0.5, 0.5)
    panel.Size = UDim2.new(0.76, 0, 0.8, 0)
    panel.BackgroundColor3 = Color3.fromRGB(12, 18, 27)
    panel.BorderSizePixel = 0
    panel.Parent = overlay
    makeCorner(panel, 18)
    makeStroke(panel, Color3.fromRGB(137, 167, 203), 1, 0.35)

    local titleLabel = makeTextLabel(
        "Title",
        panel,
        UDim2.new(1, -160, 0, 32),
        UDim2.new(0, 18, 0, 14),
        "Studio Brainrot Debug",
        24,
        Enum.Font.GothamBold,
        Color3.fromRGB(255, 255, 255),
        Enum.TextXAlignment.Left
    )
    titleLabel.TextTruncate = Enum.TextTruncate.AtEnd

    local hintLabel = makeTextLabel(
        "Hint",
        panel,
        UDim2.new(0, 120, 0, 24),
        UDim2.new(1, -176, 0, 18),
        "[V] Toggle",
        14,
        Enum.Font.GothamMedium,
        Color3.fromRGB(157, 177, 201),
        Enum.TextXAlignment.Right
    )
    hintLabel.TextTruncate = Enum.TextTruncate.AtEnd

    local closeButton = makeTextButton(
        "DebugCloseButton",
        panel,
        UDim2.new(0, 34, 0, 34),
        UDim2.new(1, -52, 0, 14),
        "X",
        16,
        Color3.fromRGB(120, 72, 72),
        Color3.fromRGB(255, 255, 255)
    )
    closeButton.Activated:Connect(function()
        if self._screenGui then
            self._screenGui.Enabled = false
        end
    end)

    local statusLabel = makeTextLabel(
        "Status",
        panel,
        UDim2.new(1, -36, 0, 22),
        UDim2.new(0, 18, 0, 52),
        "按 V 打开或关闭，点击 Send 给当前玩家补 1 个指定脑红。",
        14,
        Enum.Font.Gotham,
        Color3.fromRGB(201, 214, 228),
        Enum.TextXAlignment.Left
    )
    statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
    self._statusLabel = statusLabel

    local scrollingFrame = Instance.new("ScrollingFrame")
    scrollingFrame.Name = "BrainrotList"
    scrollingFrame.Active = true
    scrollingFrame.BackgroundColor3 = Color3.fromRGB(15, 23, 33)
    scrollingFrame.BorderSizePixel = 0
    scrollingFrame.Position = UDim2.new(0, 18, 0, 84)
    scrollingFrame.Size = UDim2.new(1, -36, 1, -102)
    scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollingFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 153, 219)
    scrollingFrame.ScrollBarThickness = 8
    scrollingFrame.Parent = panel
    makeCorner(scrollingFrame, 14)
    makeStroke(scrollingFrame, Color3.fromRGB(87, 108, 132), 1, 0.55)
    self._scrollingFrame = scrollingFrame

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 10)
    padding.PaddingBottom = UDim.new(0, 10)
    padding.PaddingLeft = UDim.new(0, 10)
    padding.PaddingRight = UDim.new(0, 10)
    padding.Parent = scrollingFrame

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 8)
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = scrollingFrame

    table.insert(self._connections, layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        self:_refreshCanvasSize()
    end))

    for index, entry in ipairs(BrainrotConfig.Entries or {}) do
        self:_buildEntryRow(entry, index)
    end

    self:_refreshCanvasSize()
end

function StudioBrainrotDebugController:_toggleUi()
    if not self._screenGui then
        self:_buildGui()
    end

    if not self._screenGui then
        return
    end

    self._screenGui.Enabled = not self._screenGui.Enabled

    task.defer(function()
        if not self._feedbackEvent then
            self:_resolveEvents()
        end
        self:_bindFeedbackEventIfNeeded()
    end)
    if self._screenGui.Enabled then
        self:_setStatus("Studio 调试面板已打开，点击 Send 立即发放 1 个脑红。", Color3.fromRGB(201, 214, 228))
    end
end

function StudioBrainrotDebugController:Start()
    if self._started then
        return
    end

    self._started = true
    if not RunService:IsStudio() then
        return
    end

    table.insert(self._connections, UserInputService.InputBegan:Connect(function(inputObject, gameProcessedEvent)
        if gameProcessedEvent then
            return
        end

        if UserInputService:GetFocusedTextBox() then
            return
        end

        if inputObject.KeyCode ~= TOGGLE_KEY then
            return
        end

        self:_toggleUi()
    end))

    task.defer(function()
        if not self:_resolveEvents() then
            self:_warnMissingRemote()
            return
        end

        self:_bindFeedbackEventIfNeeded()
    end)
end

function StudioBrainrotDebugController:Destroy()
    disconnectAll(self._connections)
    if self._screenGui then
        self._screenGui:Destroy()
        self._screenGui = nil
    end
end

return StudioBrainrotDebugController