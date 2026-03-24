--[[
脚本名字: StudioSlideDebugController
脚本文件: StudioSlideDebugController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/StudioSlideDebugController
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
local TOGGLE_KEY = Enum.KeyCode.B
local GUI_NAME = "StudioSlideDebugGui"
local LAUNCH_POWER_ATTRIBUTE = "StudioSlideLaunchPower"
local MIN_LAUNCH_POWER = 0
local DEFAULT_LAUNCH_POWER = 0

local StudioSlideDebugController = {}
StudioSlideDebugController.__index = StudioSlideDebugController

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

local function clampLaunchPower(value)
    return math.max(MIN_LAUNCH_POWER, math.floor(tonumber(value) or 0))
end

function StudioSlideDebugController.new()
    local self = setmetatable({}, StudioSlideDebugController)
    self._started = false
    self._connections = {}
    self._screenGui = nil
    self._statusLabel = nil
    self._valueLabel = nil
    self._valueBox = nil
    return self
end

function StudioSlideDebugController:_getPlayerGui()
    return localPlayer:FindFirstChild("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
end

function StudioSlideDebugController:_getCurrentPower()
    return clampLaunchPower(localPlayer:GetAttribute(LAUNCH_POWER_ATTRIBUTE))
end

function StudioSlideDebugController:_setStatus(message, color)
    if not self._statusLabel then
        return
    end

    self._statusLabel.Text = tostring(message or "")
    self._statusLabel.TextColor3 = color or Color3.fromRGB(201, 214, 228)
end

function StudioSlideDebugController:_refreshDisplay(customMessage, customColor)
    local currentPower = self:_getCurrentPower()

    if self._valueLabel then
        self._valueLabel.Text = tostring(currentPower)
    end

    if self._valueBox then
        self._valueBox.Text = tostring(currentPower)
    end

    if customMessage then
        self:_setStatus(customMessage, customColor)
        return
    end

    if currentPower <= 0 then
        self:_setStatus("当前 Studio 覆盖值为 0，会回退到正式弹射力；若正式值也为 0，则按当前滑行速度自然冲出。", Color3.fromRGB(201, 214, 228))
        return
    end

    self:_setStatus(string.format("当前 Studio 覆盖值为 %d。只覆盖末端额外前向速度，不改变起飞角度。", currentPower), Color3.fromRGB(133, 228, 169))
end

function StudioSlideDebugController:_setLaunchPower(value)
    local normalized = clampLaunchPower(value)
    localPlayer:SetAttribute(LAUNCH_POWER_ATTRIBUTE, normalized)
    self:_refreshDisplay(string.format("已将推动力设置为 %d。", normalized), Color3.fromRGB(133, 228, 169))
end

function StudioSlideDebugController:_adjustLaunchPower(delta)
    self:_setLaunchPower(self:_getCurrentPower() + (tonumber(delta) or 0))
end

function StudioSlideDebugController:_applyInputValue()
    if not self._valueBox then
        return
    end

    local parsedValue = tonumber(self._valueBox.Text)
    if not parsedValue then
        self:_refreshDisplay("请输入有效数字。", Color3.fromRGB(255, 170, 115))
        return
    end

    self:_setLaunchPower(parsedValue)
end

function StudioSlideDebugController:_buildGui()
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
    screenGui.DisplayOrder = 2510
    screenGui.Enabled = false
    screenGui.Parent = playerGui
    self._screenGui = screenGui

    local overlay = Instance.new("Frame")
    overlay.Name = "Overlay"
    overlay.BackgroundColor3 = Color3.fromRGB(7, 10, 16)
    overlay.BackgroundTransparency = 0.3
    overlay.BorderSizePixel = 0
    overlay.Size = UDim2.fromScale(1, 1)
    overlay.Parent = screenGui

    local panel = Instance.new("Frame")
    panel.Name = "Panel"
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.fromScale(0.5, 0.5)
    panel.Size = UDim2.new(0, 430, 0, 280)
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
        "Studio Slide Debug",
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
        "[B] Toggle",
        14,
        Enum.Font.GothamMedium,
        Color3.fromRGB(157, 177, 201),
        Enum.TextXAlignment.Right
    )
    hintLabel.TextTruncate = Enum.TextTruncate.AtEnd

    local closeButton = makeTextButton(
        "CloseButton",
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
        "这个面板只在 Studio 生效，用来调滑梯末端推动力。",
        14,
        Enum.Font.Gotham,
        Color3.fromRGB(201, 214, 228),
        Enum.TextXAlignment.Left
    )
    statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
    self._statusLabel = statusLabel

    local valueTitle = makeTextLabel(
        "ValueTitle",
        panel,
        UDim2.new(1, -36, 0, 18),
        UDim2.new(0, 18, 0, 92),
        "当前推动力",
        15,
        Enum.Font.GothamMedium,
        Color3.fromRGB(157, 177, 201),
        Enum.TextXAlignment.Center
    )

    local valueLabel = makeTextLabel(
        "ValueLabel",
        panel,
        UDim2.new(1, -36, 0, 48),
        UDim2.new(0, 18, 0, 112),
        tostring(DEFAULT_LAUNCH_POWER),
        42,
        Enum.Font.GothamBold,
        Color3.fromRGB(115, 207, 255),
        Enum.TextXAlignment.Center
    )
    self._valueLabel = valueLabel

    local inputBox = Instance.new("TextBox")
    inputBox.Name = "ValueBox"
    inputBox.Size = UDim2.new(0, 120, 0, 40)
    inputBox.Position = UDim2.new(0.5, -100, 0, 168)
    inputBox.BackgroundColor3 = Color3.fromRGB(18, 28, 41)
    inputBox.BorderSizePixel = 0
    inputBox.ClearTextOnFocus = false
    inputBox.Font = Enum.Font.GothamBold
    inputBox.PlaceholderText = "0+"
    inputBox.Text = tostring(DEFAULT_LAUNCH_POWER)
    inputBox.TextColor3 = Color3.fromRGB(255, 255, 255)
    inputBox.TextSize = 18
    inputBox.Parent = panel
    makeCorner(inputBox, 10)
    makeStroke(inputBox, Color3.fromRGB(112, 139, 171), 1, 0.45)
    self._valueBox = inputBox

    local applyButton = makeTextButton(
        "ApplyButton",
        panel,
        UDim2.new(0, 80, 0, 40),
        UDim2.new(0.5, 24, 0, 168),
        "应用",
        16,
        Color3.fromRGB(62, 154, 255),
        Color3.fromRGB(255, 255, 255)
    )
    applyButton.Activated:Connect(function()
        self:_applyInputValue()
    end)

    local minusFiftyButton = makeTextButton(
        "MinusFiftyButton",
        panel,
        UDim2.new(0, 78, 0, 38),
        UDim2.new(0.5, -168, 0, 222),
        "-50",
        16,
        Color3.fromRGB(135, 87, 87),
        Color3.fromRGB(255, 255, 255)
    )
    minusFiftyButton.Activated:Connect(function()
        self:_adjustLaunchPower(-50)
    end)

    local minusTenButton = makeTextButton(
        "MinusTenButton",
        panel,
        UDim2.new(0, 78, 0, 38),
        UDim2.new(0.5, -84, 0, 222),
        "-10",
        16,
        Color3.fromRGB(154, 109, 109),
        Color3.fromRGB(255, 255, 255)
    )
    minusTenButton.Activated:Connect(function()
        self:_adjustLaunchPower(-10)
    end)

    local plusTenButton = makeTextButton(
        "PlusTenButton",
        panel,
        UDim2.new(0, 78, 0, 38),
        UDim2.new(0.5, 0, 0, 222),
        "+10",
        16,
        Color3.fromRGB(74, 142, 109),
        Color3.fromRGB(255, 255, 255)
    )
    plusTenButton.Activated:Connect(function()
        self:_adjustLaunchPower(10)
    end)

    local plusFiftyButton = makeTextButton(
        "PlusFiftyButton",
        panel,
        UDim2.new(0, 78, 0, 38),
        UDim2.new(0.5, 84, 0, 222),
        "+50",
        16,
        Color3.fromRGB(67, 165, 101),
        Color3.fromRGB(255, 255, 255)
    )
    plusFiftyButton.Activated:Connect(function()
        self:_adjustLaunchPower(50)
    end)

    local resetButton = makeTextButton(
        "ResetButton",
        panel,
        UDim2.new(0, 78, 0, 38),
        UDim2.new(0.5, 168, 0, 222),
        "重置",
        16,
        Color3.fromRGB(92, 118, 146),
        Color3.fromRGB(255, 255, 255)
    )
    resetButton.Activated:Connect(function()
        self:_setLaunchPower(DEFAULT_LAUNCH_POWER)
    end)

    inputBox.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            self:_applyInputValue()
        end
    end)

    local noteLabel = makeTextLabel(
        "Note",
        panel,
        UDim2.new(1, -36, 0, 18),
        UDim2.new(0, 18, 0, 186),
        "只增加末端发射速度，起飞角度始终跟随滑梯末端角度。",
        13,
        Enum.Font.Gotham,
        Color3.fromRGB(157, 177, 201),
        Enum.TextXAlignment.Center
    )
    noteLabel.TextTruncate = Enum.TextTruncate.AtEnd

    valueTitle.Parent = panel
    self:_refreshDisplay()
end

function StudioSlideDebugController:_toggleUi()
    if not self._screenGui then
        self:_buildGui()
    end

    if not self._screenGui then
        return
    end

    self._screenGui.Enabled = not self._screenGui.Enabled
    if self._screenGui.Enabled then
        self:_refreshDisplay("Studio 滑梯调试面板已打开。", Color3.fromRGB(201, 214, 228))
    end
end

function StudioSlideDebugController:Start()
    if self._started then
        return
    end

    self._started = true
    if not RunService:IsStudio() then
        return
    end

    if localPlayer:GetAttribute(LAUNCH_POWER_ATTRIBUTE) == nil then
        localPlayer:SetAttribute(LAUNCH_POWER_ATTRIBUTE, DEFAULT_LAUNCH_POWER)
    end

    table.insert(self._connections, localPlayer:GetAttributeChangedSignal(LAUNCH_POWER_ATTRIBUTE):Connect(function()
        self:_refreshDisplay()
    end))

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
end

function StudioSlideDebugController:Destroy()
    disconnectAll(self._connections)
    if self._screenGui then
        self._screenGui:Destroy()
        self._screenGui = nil
    end
end

return StudioSlideDebugController


