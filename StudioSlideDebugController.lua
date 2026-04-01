--[[
脚本名字: StudioSlideDebugController
脚本文件: StudioSlideDebugController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/StudioSlideDebugController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
local TOGGLE_KEY = Enum.KeyCode.B
local GUI_NAME = "StudioSlideDebugGui"
local LAUNCH_POWER_ATTRIBUTE = "StudioSlideLaunchPower"
local STUDIO_DEBUG_LAST_LAUNCH_HORIZONTAL_SPEED_ATTRIBUTE = "StudioSlideLastLaunchHorizontalSpeed"
local STUDIO_DEBUG_LAST_LAUNCH_VERTICAL_SPEED_ATTRIBUTE = "StudioSlideLastLaunchVerticalSpeed"
local STUDIO_DEBUG_LAST_LAUNCH_TOTAL_SPEED_ATTRIBUTE = "StudioSlideLastLaunchTotalSpeed"
local STUDIO_DEBUG_LAST_LAUNCH_POWER_USED_ATTRIBUTE = "StudioSlideLastLaunchPowerUsed"
local STUDIO_DEBUG_LAST_LAUNCH_SLIDE_SPEED_ATTRIBUTE = "StudioSlideLastLaunchSlideSpeed"
local MIN_LAUNCH_POWER = 0
local DEFAULT_LAUNCH_POWER = 0
local TAB_OVERRIDE = "Override"
local TAB_COST = "Cost"

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
        "[StudioSlideDebugController] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local FormatUtil = requireSharedModule("FormatUtil")
local GameConfig = requireSharedModule("GameConfig")
local RemoteNames = requireSharedModule("RemoteNames")

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

local function makeCardFrame(name, parent, size, position)
    local frame = Instance.new("Frame")
    frame.Name = name
    frame.Size = size
    frame.Position = position
    frame.BackgroundColor3 = Color3.fromRGB(18, 28, 41)
    frame.BorderSizePixel = 0
    frame.Parent = parent
    makeCorner(frame, 14)
    makeStroke(frame, Color3.fromRGB(112, 139, 171), 1, 0.55)
    return frame
end

local function clampLaunchPower(value)
    return math.max(MIN_LAUNCH_POWER, math.floor(tonumber(value) or 0))
end

local function getLaunchPowerConfig()
    return GameConfig.LAUNCH_POWER or {}
end

local function getDefaultLevel()
    return math.max(1, math.floor(tonumber(getLaunchPowerConfig().DefaultLevel) or 1))
end

local function clampPersistentLevel(value)
    return math.max(getDefaultLevel(), math.floor(tonumber(value) or getDefaultLevel()))
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

local function getTotalUpgradeCostFromDefaultToLevel(targetLevel)
    local defaultLevel = getDefaultLevel()
    local normalizedTargetLevel = clampPersistentLevel(targetLevel)
    local requiredUpgradeCount = math.max(0, normalizedTargetLevel - defaultLevel)
    if requiredUpgradeCount <= 0 then
        return 0
    end

    return getUpgradePackageCostByLevel(defaultLevel, requiredUpgradeCount)
end
function StudioSlideDebugController.new()
    local self = setmetatable({}, StudioSlideDebugController)
    self._started = false
    self._connections = {}
    self._screenGui = nil
    self._statusLabel = nil
    self._valueLabel = nil
    self._valueBox = nil
    self._persistentPowerLabel = nil
    self._persistentLevelLabel = nil
    self._lastLaunchHorizontalSpeedLabel = nil
    self._lastLaunchVerticalSpeedLabel = nil
    self._lastLaunchTotalSpeedLabel = nil
    self._lastLaunchPowerUsedLabel = nil
    self._lastLaunchSlideSpeedLabel = nil
    self._overridePage = nil
    self._costPage = nil
    self._tabButtons = {}
    self._activeTab = TAB_OVERRIDE
    self._targetLevelBox = nil
    self._costRangeLabel = nil
    self._targetPowerLabel = nil
    self._costCompactLabel = nil
    self._costRawLabel = nil
    self._requestStudioResetLaunchPowerEvent = nil
    self._launchPowerFeedbackEvent = nil
    self._calculatorTargetLevel = nil
    return self
end

function StudioSlideDebugController:_getPlayerGui()
    return localPlayer:FindFirstChild("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
end

function StudioSlideDebugController:_getCurrentPower()
    return clampLaunchPower(localPlayer:GetAttribute(LAUNCH_POWER_ATTRIBUTE))
end

function StudioSlideDebugController:_getPersistentPower()
    return math.max(0, math.floor(tonumber(localPlayer:GetAttribute("LaunchPowerValue")) or 0))
end

function StudioSlideDebugController:_getPersistentLevel()
    return clampPersistentLevel(localPlayer:GetAttribute("LaunchPowerLevel"))
end

function StudioSlideDebugController:_formatCompactCurrency(value)
    return FormatUtil.FormatCompactCurrencyCeil(tonumber(value) or 0)
end

function StudioSlideDebugController:_formatRawCurrency(value)
    return "$" .. FormatUtil.FormatWithCommasCeil(tonumber(value) or 0)
end

function StudioSlideDebugController:_getLaunchDebugValue(attributeName)
    local rawValue = localPlayer:GetAttribute(attributeName)
    if rawValue == nil then
        return nil
    end

    local numericValue = tonumber(rawValue)
    if numericValue == nil then
        return nil
    end

    return numericValue
end

function StudioSlideDebugController:_formatLaunchDebugSpeed(value)
    if value == nil then
        return "--"
    end

    return string.format("%.2f", value)
end

function StudioSlideDebugController:_formatLaunchDebugPower(value)
    if value == nil then
        return "--"
    end

    return tostring(math.max(0, math.floor(value + 0.5)))
end

function StudioSlideDebugController:_refreshLastLaunchStats()
    local horizontalSpeed = self:_getLaunchDebugValue(STUDIO_DEBUG_LAST_LAUNCH_HORIZONTAL_SPEED_ATTRIBUTE)
    local verticalSpeed = self:_getLaunchDebugValue(STUDIO_DEBUG_LAST_LAUNCH_VERTICAL_SPEED_ATTRIBUTE)
    local totalSpeed = self:_getLaunchDebugValue(STUDIO_DEBUG_LAST_LAUNCH_TOTAL_SPEED_ATTRIBUTE)
    local powerUsed = self:_getLaunchDebugValue(STUDIO_DEBUG_LAST_LAUNCH_POWER_USED_ATTRIBUTE)
    local slideSpeed = self:_getLaunchDebugValue(STUDIO_DEBUG_LAST_LAUNCH_SLIDE_SPEED_ATTRIBUTE)

    if self._lastLaunchHorizontalSpeedLabel then
        self._lastLaunchHorizontalSpeedLabel.Text = string.format("水平速度 %s", self:_formatLaunchDebugSpeed(horizontalSpeed))
    end

    if self._lastLaunchVerticalSpeedLabel then
        self._lastLaunchVerticalSpeedLabel.Text = string.format("竖直速度 %s", self:_formatLaunchDebugSpeed(verticalSpeed))
    end

    if self._lastLaunchTotalSpeedLabel then
        self._lastLaunchTotalSpeedLabel.Text = string.format("总速度 %s", self:_formatLaunchDebugSpeed(totalSpeed))
    end

    if self._lastLaunchPowerUsedLabel then
        self._lastLaunchPowerUsedLabel.Text = string.format("使用弹射力 %s", self:_formatLaunchDebugPower(powerUsed))
    end

    if self._lastLaunchSlideSpeedLabel then
        self._lastLaunchSlideSpeedLabel.Text = string.format("起飞前滑行速度 %s", self:_formatLaunchDebugSpeed(slideSpeed))
    end
end
function StudioSlideDebugController:_setStatus(message, color)
    if not self._statusLabel then
        return
    end

    self._statusLabel.Text = tostring(message or "")
    self._statusLabel.TextColor3 = color or Color3.fromRGB(201, 214, 228)
end

function StudioSlideDebugController:_refreshOverrideLabels()
    local currentPower = self:_getCurrentPower()
    local persistentPower = self:_getPersistentPower()
    local persistentLevel = self:_getPersistentLevel()

    if self._valueLabel then
        self._valueLabel.Text = tostring(currentPower)
    end

    if self._valueBox and not self._valueBox:IsFocused() then
        self._valueBox.Text = tostring(currentPower)
    end

    if self._persistentPowerLabel then
        self._persistentPowerLabel.Text = tostring(persistentPower)
    end

    if self._persistentLevelLabel then
        self._persistentLevelLabel.Text = string.format("正式等级 Lv.%d", persistentLevel)
    end

    self:_refreshLastLaunchStats()
end

function StudioSlideDebugController:_refreshCalculatorDisplay()
    local targetLevel = clampPersistentLevel(self._calculatorTargetLevel or self:_getPersistentLevel())
    local targetPower = math.max(0, targetLevel - getDefaultLevel())
    local totalCost = getTotalUpgradeCostFromDefaultToLevel(targetLevel)
    self._calculatorTargetLevel = targetLevel

    if self._costRangeLabel then
        self._costRangeLabel.Text = string.format("Lv.%d -> Lv.%d", getDefaultLevel(), targetLevel)
    end

    if self._targetPowerLabel then
        self._targetPowerLabel.Text = string.format("对应弹射力 %d", targetPower)
    end

    if self._costCompactLabel then
        self._costCompactLabel.Text = self:_formatCompactCurrency(totalCost)
    end

    if self._costRawLabel then
        self._costRawLabel.Text = string.format("原始数值 %s", self:_formatRawCurrency(totalCost))
    end
end

function StudioSlideDebugController:_setDefaultStatusForActiveTab()
    if self._activeTab == TAB_COST then
        self:_setStatus(
            "累计升级页会按当前正式规则，把 Lv.1 到目标等级之间每一档升级费用逐档向上取整后再累计。",
            Color3.fromRGB(201, 214, 228)
        )
        return
    end

    local currentPower = self:_getCurrentPower()
    local persistentPower = self:_getPersistentPower()
    local persistentLevel = self:_getPersistentLevel()

    if currentPower <= 0 then
        if persistentPower <= 0 then
            self:_setStatus("当前 Studio 覆盖值为 0，正式弹射力也为 0，会只按当前滑行速度从 Up 自然飞出。", Color3.fromRGB(201, 214, 228))
            return
        end

        self:_setStatus(
            string.format("当前 Studio 覆盖值为 0，正在使用正式弹射力 %d（Lv.%d）。", persistentPower, persistentLevel),
            Color3.fromRGB(201, 214, 228)
        )
        return
    end

    self:_setStatus(
        string.format("当前 Studio 覆盖值为 %d；正式弹射力为 %d（Lv.%d）。", currentPower, persistentPower, persistentLevel),
        Color3.fromRGB(133, 228, 169)
    )
end

function StudioSlideDebugController:_refreshDisplay(customMessage, customColor)
    self:_refreshOverrideLabels()
    self:_refreshCalculatorDisplay()

    if customMessage then
        self:_setStatus(customMessage, customColor)
        return
    end

    self:_setDefaultStatusForActiveTab()
end
function StudioSlideDebugController:_styleTabButton(button, isActive)
    if not button then
        return
    end

    if isActive then
        button.BackgroundColor3 = Color3.fromRGB(62, 154, 255)
        button.TextColor3 = Color3.fromRGB(255, 255, 255)
        local stroke = button:FindFirstChildOfClass("UIStroke")
        if stroke then
            stroke.Color = Color3.fromRGB(201, 225, 255)
            stroke.Transparency = 0.2
        end
        return
    end

    button.BackgroundColor3 = Color3.fromRGB(27, 39, 55)
    button.TextColor3 = Color3.fromRGB(184, 204, 228)
    local stroke = button:FindFirstChildOfClass("UIStroke")
    if stroke then
        stroke.Color = Color3.fromRGB(112, 139, 171)
        stroke.Transparency = 0.55
    end
end

function StudioSlideDebugController:_setActiveTab(tabKey)
    self._activeTab = tabKey == TAB_COST and TAB_COST or TAB_OVERRIDE

    if self._overridePage then
        self._overridePage.Visible = self._activeTab == TAB_OVERRIDE
    end

    if self._costPage then
        self._costPage.Visible = self._activeTab == TAB_COST
    end

    self:_styleTabButton(self._tabButtons[TAB_OVERRIDE], self._activeTab == TAB_OVERRIDE)
    self:_styleTabButton(self._tabButtons[TAB_COST], self._activeTab == TAB_COST)
    self:_refreshDisplay()
end

function StudioSlideDebugController:_setLaunchPower(value)
    local normalized = clampLaunchPower(value)
    localPlayer:SetAttribute(LAUNCH_POWER_ATTRIBUTE, normalized)
    self:_refreshDisplay(string.format("已将 Up 末端弹射覆盖值设置为 %d。", normalized), Color3.fromRGB(133, 228, 169))
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

function StudioSlideDebugController:_applyUpgradeCostCalculation()
    if not self._targetLevelBox then
        return
    end

    local parsedLevel = tonumber(self._targetLevelBox.Text)
    if not parsedLevel then
        self:_refreshDisplay("请输入有效的目标等级。", Color3.fromRGB(255, 170, 115))
        return
    end

    local targetLevel = clampPersistentLevel(parsedLevel)
    self._calculatorTargetLevel = targetLevel
    self._targetLevelBox.Text = tostring(targetLevel)
    self:_refreshCalculatorDisplay()

    local totalCost = getTotalUpgradeCostFromDefaultToLevel(targetLevel)
    self:_refreshDisplay(
        string.format(
            "已计算 Lv.%d -> Lv.%d 的累计金币，共 %s（%s）。",
            getDefaultLevel(),
            targetLevel,
            self:_formatCompactCurrency(totalCost),
            self:_formatRawCurrency(totalCost)
        ),
        Color3.fromRGB(133, 228, 169)
    )
end

function StudioSlideDebugController:_resetPersistentLaunchPower()
    self:_setLaunchPower(DEFAULT_LAUNCH_POWER)

    if self._requestStudioResetLaunchPowerEvent and self._requestStudioResetLaunchPowerEvent:IsA("RemoteEvent") then
        self._requestStudioResetLaunchPowerEvent:FireServer()
        self:_refreshDisplay("已清空 Studio 覆盖值，并请求服务端重置正式弹射力。", Color3.fromRGB(133, 228, 169))
        return
    end

    self:_refreshDisplay(
        "已清空 Studio 覆盖值，但找不到服务端重置事件，正式弹射力未改动。",
        Color3.fromRGB(255, 170, 115)
    )
end

function StudioSlideDebugController:_handleLaunchPowerFeedback(payload)
    if type(payload) ~= "table" then
        return
    end

    local status = tostring(payload.status or "")
    if status == "StudioResetSuccess" then
        self:_refreshDisplay("已将正式弹射力重置为默认值，并保存到当前 Studio 数据。", Color3.fromRGB(133, 228, 169))
    elseif status == "NotStudio" then
        self:_refreshDisplay("正式弹射力重置只允许在 Studio 里使用。", Color3.fromRGB(255, 170, 115))
    elseif status == "MissingData" then
        self:_refreshDisplay("正式弹射力重置失败：玩家数据还没准备好。", Color3.fromRGB(255, 170, 115))
    elseif status == "SaveFailed" then
        self:_refreshDisplay("正式弹射力已回到默认值，但保存失败了，请再试一次确认。", Color3.fromRGB(255, 170, 115))
    elseif status == "Debounced" then
        self:_refreshDisplay("操作太快了，稍等一下再点重置。", Color3.fromRGB(255, 170, 115))
    end
end

function StudioSlideDebugController:_bindRemoteEvents()
    local eventsRoot = ReplicatedStorage:FindFirstChild(RemoteNames.RootFolder)
        or ReplicatedStorage:WaitForChild(RemoteNames.RootFolder, 10)
    if not eventsRoot then
        return
    end

    local systemEvents = eventsRoot:FindFirstChild(RemoteNames.SystemEventsFolder)
        or eventsRoot:WaitForChild(RemoteNames.SystemEventsFolder, 10)
    if not systemEvents then
        return
    end

    self._requestStudioResetLaunchPowerEvent = systemEvents:FindFirstChild(RemoteNames.System.RequestStudioResetLaunchPower)
        or systemEvents:WaitForChild(RemoteNames.System.RequestStudioResetLaunchPower, 10)
    self._launchPowerFeedbackEvent = systemEvents:FindFirstChild(RemoteNames.System.LaunchPowerFeedback)
        or systemEvents:WaitForChild(RemoteNames.System.LaunchPowerFeedback, 10)

    if self._launchPowerFeedbackEvent and self._launchPowerFeedbackEvent:IsA("RemoteEvent") then
        table.insert(self._connections, self._launchPowerFeedbackEvent.OnClientEvent:Connect(function(payload)
            self:_handleLaunchPowerFeedback(payload)
        end))
    end
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
    panel.Size = UDim2.new(0, 540, 0, 586)
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
        UDim2.new(1, -36, 0, 40),
        UDim2.new(0, 18, 0, 52),
        "这个面板只在 Studio 生效，用来调滑梯末端推动力。",
        14,
        Enum.Font.Gotham,
        Color3.fromRGB(201, 214, 228),
        Enum.TextXAlignment.Left
    )
    statusLabel.TextWrapped = true
    statusLabel.TextYAlignment = Enum.TextYAlignment.Top
    self._statusLabel = statusLabel

    local tabBar = Instance.new("Frame")
    tabBar.Name = "TabBar"
    tabBar.BackgroundTransparency = 1
    tabBar.Size = UDim2.new(1, -36, 0, 38)
    tabBar.Position = UDim2.new(0, 18, 0, 100)
    tabBar.Parent = panel

    local overrideTabButton = makeTextButton(
        "OverrideTabButton",
        tabBar,
        UDim2.new(0, 170, 1, 0),
        UDim2.new(0, 0, 0, 0),
        "覆盖调试",
        15,
        Color3.fromRGB(62, 154, 255),
        Color3.fromRGB(255, 255, 255)
    )
    overrideTabButton.Activated:Connect(function()
        self:_setActiveTab(TAB_OVERRIDE)
    end)
    self._tabButtons[TAB_OVERRIDE] = overrideTabButton

    local costTabButton = makeTextButton(
        "CostTabButton",
        tabBar,
        UDim2.new(0, 170, 1, 0),
        UDim2.new(0, 182, 0, 0),
        "累计升级",
        15,
        Color3.fromRGB(27, 39, 55),
        Color3.fromRGB(184, 204, 228)
    )
    costTabButton.Activated:Connect(function()
        self:_setActiveTab(TAB_COST)
    end)
    self._tabButtons[TAB_COST] = costTabButton

    local contentFrame = Instance.new("Frame")
    contentFrame.Name = "Content"
    contentFrame.BackgroundTransparency = 1
    contentFrame.Size = UDim2.new(1, -36, 0, 430)
    contentFrame.Position = UDim2.new(0, 18, 0, 146)
    contentFrame.Parent = panel

    local overridePage = Instance.new("Frame")
    overridePage.Name = "OverridePage"
    overridePage.BackgroundTransparency = 1
    overridePage.Size = UDim2.fromScale(1, 1)
    overridePage.Parent = contentFrame
    self._overridePage = overridePage

    local persistentTitle = makeTextLabel(
        "PersistentTitle",
        overridePage,
        UDim2.new(1, 0, 0, 18),
        UDim2.new(0, 0, 0, 0),
        "正式弹射力（存档值）",
        15,
        Enum.Font.GothamMedium,
        Color3.fromRGB(157, 177, 201),
        Enum.TextXAlignment.Center
    )
    persistentTitle.TextTruncate = Enum.TextTruncate.AtEnd

    local persistentPowerLabel = makeTextLabel(
        "PersistentPowerLabel",
        overridePage,
        UDim2.new(1, 0, 0, 34),
        UDim2.new(0, 0, 0, 20),
        "0",
        30,
        Enum.Font.GothamBold,
        Color3.fromRGB(255, 216, 102),
        Enum.TextXAlignment.Center
    )
    self._persistentPowerLabel = persistentPowerLabel

    local persistentLevelLabel = makeTextLabel(
        "PersistentLevelLabel",
        overridePage,
        UDim2.new(1, 0, 0, 18),
        UDim2.new(0, 0, 0, 56),
        "正式等级 Lv.1",
        13,
        Enum.Font.Gotham,
        Color3.fromRGB(201, 214, 228),
        Enum.TextXAlignment.Center
    )
    persistentLevelLabel.TextTruncate = Enum.TextTruncate.AtEnd
    self._persistentLevelLabel = persistentLevelLabel

    local valueTitle = makeTextLabel(
        "ValueTitle",
        overridePage,
        UDim2.new(1, 0, 0, 18),
        UDim2.new(0, 0, 0, 96),
        "当前 Studio 覆盖值",
        15,
        Enum.Font.GothamMedium,
        Color3.fromRGB(157, 177, 201),
        Enum.TextXAlignment.Center
    )
    valueTitle.TextTruncate = Enum.TextTruncate.AtEnd

    local valueLabel = makeTextLabel(
        "ValueLabel",
        overridePage,
        UDim2.new(1, 0, 0, 46),
        UDim2.new(0, 0, 0, 118),
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
    inputBox.Position = UDim2.new(0.5, -100, 0, 182)
    inputBox.BackgroundColor3 = Color3.fromRGB(18, 28, 41)
    inputBox.BorderSizePixel = 0
    inputBox.ClearTextOnFocus = false
    inputBox.Font = Enum.Font.GothamBold
    inputBox.PlaceholderText = "0+"
    inputBox.Text = tostring(DEFAULT_LAUNCH_POWER)
    inputBox.TextColor3 = Color3.fromRGB(255, 255, 255)
    inputBox.TextSize = 18
    inputBox.Parent = overridePage
    makeCorner(inputBox, 10)
    makeStroke(inputBox, Color3.fromRGB(112, 139, 171), 1, 0.45)
    self._valueBox = inputBox
    local applyButton = makeTextButton(
        "ApplyButton",
        overridePage,
        UDim2.new(0, 80, 0, 40),
        UDim2.new(0.5, 24, 0, 182),
        "应用",
        16,
        Color3.fromRGB(62, 154, 255),
        Color3.fromRGB(255, 255, 255)
    )
    applyButton.Activated:Connect(function()
        self:_applyInputValue()
    end)

    local noteLabel = makeTextLabel(
        "Note",
        overridePage,
        UDim2.new(1, 0, 0, 32),
        UDim2.new(0, 0, 0, 228),
        "重置会同时清空 Studio 覆盖值，并在 Studio 下把正式弹射力回到默认等级。",
        13,
        Enum.Font.Gotham,
        Color3.fromRGB(157, 177, 201),
        Enum.TextXAlignment.Center
    )
    noteLabel.TextWrapped = true

    local lastLaunchCard = makeCardFrame(
        "LastLaunchCard",
        overridePage,
        UDim2.new(1, 0, 0, 96),
        UDim2.new(0, 0, 0, 268)
    )

    local lastLaunchTitle = makeTextLabel(
        "LastLaunchTitle",
        lastLaunchCard,
        UDim2.new(1, -24, 0, 16),
        UDim2.new(0, 12, 0, 10),
        "最近一次真实起飞数据",
        13,
        Enum.Font.GothamMedium,
        Color3.fromRGB(157, 177, 201),
        Enum.TextXAlignment.Left
    )
    lastLaunchTitle.TextTruncate = Enum.TextTruncate.AtEnd

    local lastLaunchHorizontalSpeedLabel = makeTextLabel(
        "LastLaunchHorizontalSpeedLabel",
        lastLaunchCard,
        UDim2.new(0.5, -18, 0, 16),
        UDim2.new(0, 12, 0, 32),
        "水平速度 --",
        13,
        Enum.Font.Gotham,
        Color3.fromRGB(255, 255, 255),
        Enum.TextXAlignment.Left
    )
    self._lastLaunchHorizontalSpeedLabel = lastLaunchHorizontalSpeedLabel

    local lastLaunchVerticalSpeedLabel = makeTextLabel(
        "LastLaunchVerticalSpeedLabel",
        lastLaunchCard,
        UDim2.new(0.5, -18, 0, 16),
        UDim2.new(0.5, 6, 0, 32),
        "竖直速度 --",
        13,
        Enum.Font.Gotham,
        Color3.fromRGB(255, 255, 255),
        Enum.TextXAlignment.Left
    )
    self._lastLaunchVerticalSpeedLabel = lastLaunchVerticalSpeedLabel

    local lastLaunchTotalSpeedLabel = makeTextLabel(
        "LastLaunchTotalSpeedLabel",
        lastLaunchCard,
        UDim2.new(0.5, -18, 0, 16),
        UDim2.new(0, 12, 0, 54),
        "总速度 --",
        13,
        Enum.Font.Gotham,
        Color3.fromRGB(115, 207, 255),
        Enum.TextXAlignment.Left
    )
    self._lastLaunchTotalSpeedLabel = lastLaunchTotalSpeedLabel

    local lastLaunchPowerUsedLabel = makeTextLabel(
        "LastLaunchPowerUsedLabel",
        lastLaunchCard,
        UDim2.new(0.5, -18, 0, 16),
        UDim2.new(0.5, 6, 0, 54),
        "使用弹射力 --",
        13,
        Enum.Font.Gotham,
        Color3.fromRGB(255, 216, 102),
        Enum.TextXAlignment.Left
    )
    self._lastLaunchPowerUsedLabel = lastLaunchPowerUsedLabel

    local lastLaunchSlideSpeedLabel = makeTextLabel(
        "LastLaunchSlideSpeedLabel",
        lastLaunchCard,
        UDim2.new(1, -24, 0, 16),
        UDim2.new(0, 12, 0, 76),
        "起飞前滑行速度 --",
        13,
        Enum.Font.Gotham,
        Color3.fromRGB(201, 214, 228),
        Enum.TextXAlignment.Left
    )
    self._lastLaunchSlideSpeedLabel = lastLaunchSlideSpeedLabel
    local minusFiftyButton = makeTextButton(
        "MinusFiftyButton",
        overridePage,
        UDim2.new(0, 92, 0, 38),
        UDim2.new(0.5, -202, 0, 374),
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
        overridePage,
        UDim2.new(0, 92, 0, 38),
        UDim2.new(0.5, -104, 0, 374),
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
        overridePage,
        UDim2.new(0, 92, 0, 38),
        UDim2.new(0.5, -6, 0, 374),
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
        overridePage,
        UDim2.new(0, 92, 0, 38),
        UDim2.new(0.5, 92, 0, 374),
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
        overridePage,
        UDim2.new(0, 92, 0, 38),
        UDim2.new(0.5, 190, 0, 374),
        "重置",
        16,
        Color3.fromRGB(92, 118, 146),
        Color3.fromRGB(255, 255, 255)
    )
    resetButton.Activated:Connect(function()
        self:_resetPersistentLaunchPower()
    end)

    inputBox.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            self:_applyInputValue()
        end
    end)

    local costPage = Instance.new("Frame")
    costPage.Name = "CostPage"
    costPage.BackgroundTransparency = 1
    costPage.Size = UDim2.fromScale(1, 1)
    costPage.Visible = false
    costPage.Parent = contentFrame
    self._costPage = costPage

    local costIntroLabel = makeTextLabel(
        "CostIntro",
        costPage,
        UDim2.new(1, 0, 0, 38),
        UDim2.new(0, 0, 0, 0),
        "输入目标等级后点击计算，即可查看从 1 级一路升到该等级，按当前分段倍率和逐档向上取整规则累计需要多少金币。",
        14,
        Enum.Font.Gotham,
        Color3.fromRGB(201, 214, 228),
        Enum.TextXAlignment.Left
    )
    costIntroLabel.TextWrapped = true
    costIntroLabel.TextYAlignment = Enum.TextYAlignment.Top

    local targetLevelTitle = makeTextLabel(
        "TargetLevelTitle",
        costPage,
        UDim2.new(1, 0, 0, 18),
        UDim2.new(0, 0, 0, 52),
        "目标正式等级",
        15,
        Enum.Font.GothamMedium,
        Color3.fromRGB(157, 177, 201),
        Enum.TextXAlignment.Center
    )
    targetLevelTitle.TextTruncate = Enum.TextTruncate.AtEnd

    local targetLevelBox = Instance.new("TextBox")
    targetLevelBox.Name = "TargetLevelBox"
    targetLevelBox.Size = UDim2.new(0, 140, 0, 40)
    targetLevelBox.Position = UDim2.new(0.5, -112, 0, 78)
    targetLevelBox.BackgroundColor3 = Color3.fromRGB(18, 28, 41)
    targetLevelBox.BorderSizePixel = 0
    targetLevelBox.ClearTextOnFocus = false
    targetLevelBox.Font = Enum.Font.GothamBold
    targetLevelBox.PlaceholderText = "Lv.1+"
    targetLevelBox.TextColor3 = Color3.fromRGB(255, 255, 255)
    targetLevelBox.TextSize = 18
    targetLevelBox.Parent = costPage
    makeCorner(targetLevelBox, 10)
    makeStroke(targetLevelBox, Color3.fromRGB(112, 139, 171), 1, 0.45)
    self._targetLevelBox = targetLevelBox

    local calculateButton = makeTextButton(
        "CalculateButton",
        costPage,
        UDim2.new(0, 100, 0, 40),
        UDim2.new(0.5, 20, 0, 78),
        "计算",
        16,
        Color3.fromRGB(62, 154, 255),
        Color3.fromRGB(255, 255, 255)
    )
    calculateButton.Activated:Connect(function()
        self:_applyUpgradeCostCalculation()
    end)

    targetLevelBox.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            self:_applyUpgradeCostCalculation()
        end
    end)

    local targetSummaryCard = makeCardFrame(
        "TargetSummaryCard",
        costPage,
        UDim2.new(1, 0, 0, 72),
        UDim2.new(0, 0, 0, 136)
    )

    local targetSummaryTitle = makeTextLabel(
        "TargetSummaryTitle",
        targetSummaryCard,
        UDim2.new(1, -24, 0, 16),
        UDim2.new(0, 12, 0, 10),
        "累计区间",
        13,
        Enum.Font.GothamMedium,
        Color3.fromRGB(157, 177, 201),
        Enum.TextXAlignment.Left
    )
    targetSummaryTitle.TextTruncate = Enum.TextTruncate.AtEnd

    local costRangeLabel = makeTextLabel(
        "CostRangeLabel",
        targetSummaryCard,
        UDim2.new(1, -24, 0, 26),
        UDim2.new(0, 12, 0, 28),
        "Lv.1 -> Lv.1",
        24,
        Enum.Font.GothamBold,
        Color3.fromRGB(255, 255, 255),
        Enum.TextXAlignment.Left
    )
    costRangeLabel.TextTruncate = Enum.TextTruncate.AtEnd
    self._costRangeLabel = costRangeLabel

    local targetPowerLabel = makeTextLabel(
        "TargetPowerLabel",
        targetSummaryCard,
        UDim2.new(1, -24, 0, 18),
        UDim2.new(0, 12, 0, 50),
        "对应弹射力 0",
        13,
        Enum.Font.Gotham,
        Color3.fromRGB(201, 214, 228),
        Enum.TextXAlignment.Left
    )
    targetPowerLabel.TextTruncate = Enum.TextTruncate.AtEnd
    self._targetPowerLabel = targetPowerLabel
    local totalCostCard = makeCardFrame(
        "TotalCostCard",
        costPage,
        UDim2.new(1, 0, 0, 92),
        UDim2.new(0, 0, 0, 220)
    )

    local totalCostTitle = makeTextLabel(
        "TotalCostTitle",
        totalCostCard,
        UDim2.new(1, -24, 0, 16),
        UDim2.new(0, 12, 0, 10),
        "累计金币消耗",
        13,
        Enum.Font.GothamMedium,
        Color3.fromRGB(157, 177, 201),
        Enum.TextXAlignment.Left
    )
    totalCostTitle.TextTruncate = Enum.TextTruncate.AtEnd

    local costCompactLabel = makeTextLabel(
        "CostCompactLabel",
        totalCostCard,
        UDim2.new(1, -24, 0, 32),
        UDim2.new(0, 12, 0, 24),
        "$0",
        30,
        Enum.Font.GothamBold,
        Color3.fromRGB(115, 207, 255),
        Enum.TextXAlignment.Left
    )
    costCompactLabel.TextTruncate = Enum.TextTruncate.AtEnd
    self._costCompactLabel = costCompactLabel

    local costRawLabel = makeTextLabel(
        "CostRawLabel",
        totalCostCard,
        UDim2.new(1, -24, 0, 18),
        UDim2.new(0, 12, 0, 60),
        "原始数值 $0",
        13,
        Enum.Font.Gotham,
        Color3.fromRGB(201, 214, 228),
        Enum.TextXAlignment.Left
    )
    costRawLabel.TextTruncate = Enum.TextTruncate.AtEnd
    self._costRawLabel = costRawLabel

    self._calculatorTargetLevel = self:_getPersistentLevel()
    targetLevelBox.Text = tostring(self._calculatorTargetLevel)
    self:_styleTabButton(costTabButton, false)
    self:_styleTabButton(overrideTabButton, true)
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

    self:_bindRemoteEvents()

    if localPlayer:GetAttribute(LAUNCH_POWER_ATTRIBUTE) == nil then
        localPlayer:SetAttribute(LAUNCH_POWER_ATTRIBUTE, DEFAULT_LAUNCH_POWER)
    end

    table.insert(self._connections, localPlayer:GetAttributeChangedSignal(LAUNCH_POWER_ATTRIBUTE):Connect(function()
        self:_refreshDisplay()
    end))
    table.insert(self._connections, localPlayer:GetAttributeChangedSignal("LaunchPowerValue"):Connect(function()
        self:_refreshDisplay()
    end))
    table.insert(self._connections, localPlayer:GetAttributeChangedSignal("LaunchPowerLevel"):Connect(function()
        if self._targetLevelBox and self._targetLevelBox.Text == "" then
            self._calculatorTargetLevel = self:_getPersistentLevel()
        end
        self:_refreshDisplay()
    end))
    table.insert(self._connections, localPlayer:GetAttributeChangedSignal(STUDIO_DEBUG_LAST_LAUNCH_HORIZONTAL_SPEED_ATTRIBUTE):Connect(function()
        self:_refreshDisplay()
    end))
    table.insert(self._connections, localPlayer:GetAttributeChangedSignal(STUDIO_DEBUG_LAST_LAUNCH_VERTICAL_SPEED_ATTRIBUTE):Connect(function()
        self:_refreshDisplay()
    end))
    table.insert(self._connections, localPlayer:GetAttributeChangedSignal(STUDIO_DEBUG_LAST_LAUNCH_TOTAL_SPEED_ATTRIBUTE):Connect(function()
        self:_refreshDisplay()
    end))
    table.insert(self._connections, localPlayer:GetAttributeChangedSignal(STUDIO_DEBUG_LAST_LAUNCH_POWER_USED_ATTRIBUTE):Connect(function()
        self:_refreshDisplay()
    end))
    table.insert(self._connections, localPlayer:GetAttributeChangedSignal(STUDIO_DEBUG_LAST_LAUNCH_SLIDE_SPEED_ATTRIBUTE):Connect(function()
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
