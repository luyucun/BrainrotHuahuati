--[[
Script: StudioBossDebugController
Type: ModuleScript
Studio path: StarterPlayer/StarterPlayerScripts/Controllers/StudioBossDebugController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local TOGGLE_KEY = Enum.KeyCode.C
local GUI_NAME = "StudioBossDebugGui"
local SPEED_INPUT_DEBOUNCE = 0.15
local DETAIL_REFRESH_INTERVAL = 0.2

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

	error(string.format("[StudioBossDebugController] Missing shared module %s", moduleName))
end

local BrainrotConfig = requireSharedModule("BrainrotConfig")
local GameConfig = requireSharedModule("GameConfig")
local RemoteNames = requireSharedModule("RemoteNames")

local StudioBossDebugController = {}
StudioBossDebugController.__index = StudioBossDebugController

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

local function makeTextBox(name, parent, size, position, placeholderText)
	local textBox = Instance.new("TextBox")
	textBox.Name = name
	textBox.Size = size
	textBox.Position = position
	textBox.BackgroundColor3 = Color3.fromRGB(11, 18, 28)
	textBox.BorderSizePixel = 0
	textBox.ClearTextOnFocus = false
	textBox.Font = Enum.Font.Gotham
	textBox.PlaceholderColor3 = Color3.fromRGB(136, 153, 172)
	textBox.PlaceholderText = placeholderText or ""
	textBox.Text = ""
	textBox.TextColor3 = Color3.fromRGB(244, 247, 250)
	textBox.TextSize = 18
	textBox.TextXAlignment = Enum.TextXAlignment.Left
	textBox.Parent = parent
	makeCorner(textBox, 10)
	makeStroke(textBox, Color3.fromRGB(112, 139, 171), 1, 0.45)
	return textBox
end

local function parseBossName(groupConfig)
	local modelPath = type(groupConfig) == "table" and tostring(groupConfig.BossModelPath or "") or ""
	local bossName = string.match(modelPath, "([^/]+)$")
	if type(bossName) == "string" and bossName ~= "" then
		return bossName
	end

	return modelPath ~= "" and modelPath or "None"
end

local function formatSpeedText(value)
	local numericValue = tonumber(value)
	if type(numericValue) ~= "number" then
		return "--"
	end

	local text = string.format("%.2f", numericValue)
	text = string.gsub(text, "%.00$", "")
	text = string.gsub(text, "(%..-)0+$", "%1")
	return text
end

local function parseMoveSpeedText(text)
	local sanitizedText = string.gsub(tostring(text or ""), "%s+", "")
	local numericValue = tonumber(sanitizedText)
	if type(numericValue) ~= "number" then
		return nil
	end

	return numericValue
end

local function getRuntimeFolderName()
	local brainrotConfig = GameConfig.BRAINROT or {}
	return tostring(brainrotConfig.WorldSpawnBossRuntimeFolderName or "WorldSpawnBosses")
end

local function getSpawnDisplayName(groupConfig)
	local partName = type(groupConfig) == "table" and tostring(groupConfig.PartName or "") or ""
	local displayName = string.match(partName, "^([^/]+)/")
	if type(displayName) == "string" and displayName ~= "" then
		return displayName
	end

	return partName ~= "" and partName or "Unknown"
end

function StudioBossDebugController.new()
	local self = setmetatable({}, StudioBossDebugController)
	self._started = false
	self._connections = {}
	self._screenGui = nil
	self._scrollingFrame = nil
	self._statusLabel = nil
	self._selectedPointValue = nil
	self._bossNameValue = nil
	self._currentSpeedValue = nil
	self._speedInput = nil
	self._requestActionEvent = nil
	self._feedbackEvent = nil
	self._feedbackBound = false
	self._didWarnMissingRemote = false
	self._selectedGroupId = 0
	self._groupButtonsById = {}
	self._speedDebounceToken = 0
	self._refreshAccumulator = 0
	self._isSyncingSpeedText = false
	self._lastConfirmedSpeedByGroupId = {}
	return self
end

function StudioBossDebugController:_warnMissingRemote()
	if self._didWarnMissingRemote then
		return
	end

	self._didWarnMissingRemote = true
	warn("[StudioBossDebugController] Missing Studio boss debug remotes")
end

function StudioBossDebugController:_getPlayerGui()
	return localPlayer:FindFirstChild("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
end

function StudioBossDebugController:_setStatus(message, color)
	if not self._statusLabel then
		return
	end

	self._statusLabel.Text = tostring(message or "")
	self._statusLabel.TextColor3 = color or Color3.fromRGB(201, 214, 228)
end

function StudioBossDebugController:_refreshCanvasSize()
	if not (self._scrollingFrame and self._scrollingFrame.Parent) then
		return
	end

	local layout = self._scrollingFrame:FindFirstChildOfClass("UIListLayout")
	if not layout then
		return
	end

	self._scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 12)
end

function StudioBossDebugController:_resolveEvents()
	if self._requestActionEvent and self._feedbackEvent then
		return true
	end

	local eventsRoot = ReplicatedStorage:FindFirstChild(RemoteNames.RootFolder) or ReplicatedStorage:WaitForChild(RemoteNames.RootFolder, 5)
	if not eventsRoot then
		return false
	end

	local systemEvents = eventsRoot:FindFirstChild(RemoteNames.SystemEventsFolder) or eventsRoot:WaitForChild(RemoteNames.SystemEventsFolder, 5)
	if not systemEvents then
		return false
	end

	local requestEvent = systemEvents:FindFirstChild(RemoteNames.System.RequestStudioBossDebugAction)
		or systemEvents:WaitForChild(RemoteNames.System.RequestStudioBossDebugAction, 5)
	local feedbackEvent = systemEvents:FindFirstChild(RemoteNames.System.StudioBossDebugFeedback)
		or systemEvents:WaitForChild(RemoteNames.System.StudioBossDebugFeedback, 5)

	if requestEvent and requestEvent:IsA("RemoteEvent") then
		self._requestActionEvent = requestEvent
	end

	if feedbackEvent and feedbackEvent:IsA("RemoteEvent") then
		self._feedbackEvent = feedbackEvent
	end

	return self._requestActionEvent ~= nil and self._feedbackEvent ~= nil
end

function StudioBossDebugController:_bindFeedbackEventIfNeeded()
	if self._feedbackBound or not self._feedbackEvent then
		return
	end

	self._feedbackBound = true
	table.insert(self._connections, self._feedbackEvent.OnClientEvent:Connect(function(payload)
		self:_handleFeedback(payload)
	end))
end

function StudioBossDebugController:_getGroupList()
	local groupList = {}
	for _, groupConfig in ipairs(BrainrotConfig.WorldSpawnGroups or {}) do
		if type(groupConfig) == "table" then
			table.insert(groupList, groupConfig)
		end
	end

	table.sort(groupList, function(left, right)
		local leftId = math.max(0, math.floor(tonumber(left and left.Id) or 0))
		local rightId = math.max(0, math.floor(tonumber(right and right.Id) or 0))
		return leftId < rightId
	end)

	return groupList
end

function StudioBossDebugController:_getSelectedGroupConfig()
	return BrainrotConfig.WorldSpawnGroupsById and BrainrotConfig.WorldSpawnGroupsById[self._selectedGroupId] or nil
end

function StudioBossDebugController:_findRuntimeModelForGroup(groupId)
	local runtimeFolder = Workspace:FindFirstChild(getRuntimeFolderName())
	if not runtimeFolder then
		return nil
	end

	for _, child in ipairs(runtimeFolder:GetChildren()) do
		if child:GetAttribute("BrainrotBossGroupId") == groupId then
			return child
		end
	end

	return nil
end

function StudioBossDebugController:_setSpeedTextSilently(text)
	if not self._speedInput then
		return
	end

	self._isSyncingSpeedText = true
	self._speedInput.Text = tostring(text or "")
	self._isSyncingSpeedText = false
end

function StudioBossDebugController:_refreshSelectionStyles()
	for groupId, button in pairs(self._groupButtonsById) do
		if button and button.Parent then
			local isSelected = groupId == self._selectedGroupId
			button.BackgroundColor3 = isSelected and Color3.fromRGB(76, 170, 255) or Color3.fromRGB(29, 42, 58)
			button.TextColor3 = isSelected and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(215, 226, 237)
		end
	end
end

function StudioBossDebugController:_refreshSelectedGroupDetails()
	local groupConfig = self:_getSelectedGroupConfig()
	if not groupConfig then
		if self._selectedPointValue then
			self._selectedPointValue.Text = "--"
		end
		if self._bossNameValue then
			self._bossNameValue.Text = "--"
		end
		if self._currentSpeedValue then
			self._currentSpeedValue.Text = "--"
		end
		return
	end

	local runtimeModel = self:_findRuntimeModelForGroup(self._selectedGroupId)
	local configuredSpeed = tonumber(groupConfig.BossMoveSpeed) or 0
	local runtimeSpeed = runtimeModel and runtimeModel:GetAttribute("BrainrotBossMoveSpeed") or nil
	local currentSpeed = tonumber(runtimeSpeed) or configuredSpeed

	self._selectedPointValue.Text = string.format("%s  (#%d)", tostring(groupConfig.PartName or "--"), self._selectedGroupId)
	self._bossNameValue.Text = parseBossName(groupConfig)
	self._currentSpeedValue.Text = formatSpeedText(currentSpeed)

	local focusedTextBox = UserInputService:GetFocusedTextBox()
	if self._speedInput and focusedTextBox ~= self._speedInput then
		self:_setSpeedTextSilently(formatSpeedText(currentSpeed))
	end
end

function StudioBossDebugController:_selectGroup(groupId)
	local parsedGroupId = math.max(0, math.floor(tonumber(groupId) or 0))
	if parsedGroupId <= 0 then
		return
	end

	self._selectedGroupId = parsedGroupId
	self:_refreshSelectionStyles()
	self:_refreshSelectedGroupDetails()
	self:_setStatus(string.format("Selected group %d", parsedGroupId), Color3.fromRGB(123, 210, 255))
end

function StudioBossDebugController:_sendAction(payload)
	if not self:_resolveEvents() then
		self:_warnMissingRemote()
		self:_setStatus("Studio boss debug remotes are not ready", Color3.fromRGB(255, 170, 115))
		return false
	end

	self:_bindFeedbackEventIfNeeded()
	self._requestActionEvent:FireServer(payload)
	return true
end

function StudioBossDebugController:_teleportToSelectedGroup()
	if self._selectedGroupId <= 0 then
		self:_setStatus("Select a spawn group first", Color3.fromRGB(255, 170, 115))
		return
	end

	local groupConfig = self:_getSelectedGroupConfig()
	local displayName = groupConfig and getSpawnDisplayName(groupConfig) or tostring(self._selectedGroupId)
	if self:_sendAction({
		action = "TeleportToGroup",
		groupId = self._selectedGroupId,
	}) then
		self:_setStatus(string.format("Teleporting to %s ...", displayName), Color3.fromRGB(123, 210, 255))
	end
end

function StudioBossDebugController:_sendSelectedMoveSpeed()
	if self._selectedGroupId <= 0 or not self._speedInput then
		return
	end

	local moveSpeed = parseMoveSpeedText(self._speedInput.Text)
	if type(moveSpeed) ~= "number" then
		return
	end

	local confirmedSpeed = self._lastConfirmedSpeedByGroupId[self._selectedGroupId]
	if type(confirmedSpeed) == "number" and math.abs(confirmedSpeed - moveSpeed) <= 0.001 then
		return
	end

	if self:_sendAction({
		action = "SetBossMoveSpeed",
		groupId = self._selectedGroupId,
		moveSpeed = moveSpeed,
	}) then
		self:_setStatus(string.format("Updating move speed to %s ...", formatSpeedText(moveSpeed)), Color3.fromRGB(123, 210, 255))
	end
end

function StudioBossDebugController:_scheduleMoveSpeedSend()
	self._speedDebounceToken += 1
	local currentToken = self._speedDebounceToken
	task.delay(SPEED_INPUT_DEBOUNCE, function()
		if not self._started or currentToken ~= self._speedDebounceToken then
			return
		end

		self:_sendSelectedMoveSpeed()
	end)
end

function StudioBossDebugController:_buildGroupButton(groupConfig)
	local groupId = math.max(0, math.floor(tonumber(groupConfig and groupConfig.Id) or 0))
	local displayName = getSpawnDisplayName(groupConfig)
	local button = makeTextButton(
		string.format("Group_%d", groupId),
		self._scrollingFrame,
		UDim2.new(1, -8, 0, 44),
		UDim2.new(0, 4, 0, 0),
		string.format("#%d  %s", groupId, displayName),
		16,
		Color3.fromRGB(29, 42, 58),
		Color3.fromRGB(215, 226, 237)
	)
	button.TextXAlignment = Enum.TextXAlignment.Left
	table.insert(self._connections, button.MouseButton1Click:Connect(function()
		self:_selectGroup(groupId)
	end))

	self._groupButtonsById[groupId] = button
end

function StudioBossDebugController:_ensureGui()
	if self._screenGui and self._screenGui.Parent then
		return
	end

	local playerGui = self:_getPlayerGui()
	if not playerGui then
		return
	end

	local existingGui = playerGui:FindFirstChild(GUI_NAME)
	if existingGui then
		existingGui:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = GUI_NAME
	screenGui.DisplayOrder = 60
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.Enabled = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui
	self._screenGui = screenGui

	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.BackgroundColor3 = Color3.fromRGB(5, 9, 14)
	overlay.BackgroundTransparency = 0.2
	overlay.BorderSizePixel = 0
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0, 780, 0, 540)
	panel.BackgroundColor3 = Color3.fromRGB(11, 18, 28)
	panel.BorderSizePixel = 0
	panel.Parent = overlay
	makeCorner(panel, 18)
	makeStroke(panel, Color3.fromRGB(119, 150, 183), 1, 0.35)

	makeTextLabel(
		"Title",
		panel,
		UDim2.new(1, -32, 0, 36),
		UDim2.new(0, 16, 0, 14),
		"Studio Boss GM",
		26,
		Enum.Font.GothamBold,
		Color3.fromRGB(244, 247, 250),
		Enum.TextXAlignment.Left
	)
	makeTextLabel(
		"Hint",
		panel,
		UDim2.new(1, -32, 0, 24),
		UDim2.new(0, 16, 0, 46),
		"Toggle with C. Select a spawn point, teleport, and tune boss speed.",
		14,
		Enum.Font.Gotham,
		Color3.fromRGB(163, 182, 203),
		Enum.TextXAlignment.Left
	)

	local listCard = makeCardFrame("ListCard", panel, UDim2.new(0, 292, 0, 434), UDim2.new(0, 16, 0, 88))
	makeTextLabel(
		"ListTitle",
		listCard,
		UDim2.new(1, -20, 0, 24),
		UDim2.new(0, 12, 0, 10),
		"World spawn groups",
		18,
		Enum.Font.GothamBold,
		Color3.fromRGB(236, 241, 246),
		Enum.TextXAlignment.Left
	)

	local scrollingFrame = Instance.new("ScrollingFrame")
	scrollingFrame.Name = "List"
	scrollingFrame.Active = true
	scrollingFrame.BackgroundTransparency = 1
	scrollingFrame.BorderSizePixel = 0
	scrollingFrame.Position = UDim2.new(0, 8, 0, 42)
	scrollingFrame.Size = UDim2.new(1, -16, 1, -52)
	scrollingFrame.ScrollBarThickness = 6
	scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollingFrame.Parent = listCard
	self._scrollingFrame = scrollingFrame

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 8)
	listLayout.Parent = scrollingFrame
	table.insert(self._connections, listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		self:_refreshCanvasSize()
	end))

	local detailCard = makeCardFrame("DetailCard", panel, UDim2.new(0, 456, 0, 434), UDim2.new(0, 308, 0, 88))
	makeTextLabel(
		"DetailTitle",
		detailCard,
		UDim2.new(1, -24, 0, 24),
		UDim2.new(0, 12, 0, 10),
		"Selected group details",
		18,
		Enum.Font.GothamBold,
		Color3.fromRGB(236, 241, 246),
		Enum.TextXAlignment.Left
	)

	makeTextLabel("SelectedPointTitle", detailCard, UDim2.new(1, -24, 0, 22), UDim2.new(0, 12, 0, 54), "Spawn point", 14, Enum.Font.GothamMedium, Color3.fromRGB(163, 182, 203))
	self._selectedPointValue = makeTextLabel("SelectedPointValue", detailCard, UDim2.new(1, -24, 0, 28), UDim2.new(0, 12, 0, 78), "--", 18, Enum.Font.GothamBold, Color3.fromRGB(244, 247, 250))
	self._selectedPointValue.TextWrapped = true

	makeTextLabel("BossNameTitle", detailCard, UDim2.new(1, -24, 0, 22), UDim2.new(0, 12, 0, 126), "Boss name", 14, Enum.Font.GothamMedium, Color3.fromRGB(163, 182, 203))
	self._bossNameValue = makeTextLabel("BossNameValue", detailCard, UDim2.new(1, -24, 0, 28), UDim2.new(0, 12, 0, 150), "--", 18, Enum.Font.GothamBold, Color3.fromRGB(244, 247, 250))

	makeTextLabel("CurrentSpeedTitle", detailCard, UDim2.new(1, -24, 0, 22), UDim2.new(0, 12, 0, 198), "Current move speed", 14, Enum.Font.GothamMedium, Color3.fromRGB(163, 182, 203))
	self._currentSpeedValue = makeTextLabel("CurrentSpeedValue", detailCard, UDim2.new(1, -24, 0, 28), UDim2.new(0, 12, 0, 222), "--", 18, Enum.Font.GothamBold, Color3.fromRGB(127, 226, 156))

	makeTextLabel("SpeedInputTitle", detailCard, UDim2.new(1, -24, 0, 22), UDim2.new(0, 12, 0, 270), "Live move speed override", 14, Enum.Font.GothamMedium, Color3.fromRGB(163, 182, 203))
	self._speedInput = makeTextBox("SpeedInput", detailCard, UDim2.new(1, -24, 0, 44), UDim2.new(0, 12, 0, 296), "Example: 15 / 25 / 40")
	table.insert(self._connections, self._speedInput:GetPropertyChangedSignal("Text"):Connect(function()
		if self._isSyncingSpeedText then
			return
		end

		self:_scheduleMoveSpeedSend()
	end))
	table.insert(self._connections, self._speedInput.FocusLost:Connect(function()
		local moveSpeed = parseMoveSpeedText(self._speedInput.Text)
		if type(moveSpeed) ~= "number" then
			self:_setStatus("Move speed must be a number", Color3.fromRGB(255, 170, 115))
			self:_refreshSelectedGroupDetails()
			return
		end

		self:_sendSelectedMoveSpeed()
	end))

	local teleportButton = makeTextButton(
		"TeleportButton",
		detailCard,
		UDim2.new(0, 208, 0, 44),
		UDim2.new(0, 12, 0, 360),
		"Teleport to group",
		16,
		Color3.fromRGB(76, 170, 255),
		Color3.fromRGB(255, 255, 255)
	)
	table.insert(self._connections, teleportButton.MouseButton1Click:Connect(function()
		self:_teleportToSelectedGroup()
	end))

	self._statusLabel = makeTextLabel(
		"Status",
		detailCard,
		UDim2.new(1, -24, 0, 44),
		UDim2.new(0, 12, 0, 382),
		"Pick a group to start debugging",
		14,
		Enum.Font.Gotham,
		Color3.fromRGB(201, 214, 228),
		Enum.TextXAlignment.Left
	)
	self._statusLabel.TextWrapped = true

	for _, groupConfig in ipairs(self:_getGroupList()) do
		self:_buildGroupButton(groupConfig)
	end
	self:_refreshCanvasSize()

	if self._selectedGroupId <= 0 then
		local groupList = self:_getGroupList()
		if groupList[1] then
			self._selectedGroupId = math.max(0, math.floor(tonumber(groupList[1].Id) or 0))
		end
	end

	self:_refreshSelectionStyles()
	self:_refreshSelectedGroupDetails()
end

function StudioBossDebugController:_toggleGui()
	self:_ensureGui()
	if not self._screenGui then
		return
	end

	local nextEnabled = not self._screenGui.Enabled
	self._screenGui.Enabled = nextEnabled
	if nextEnabled then
		self:_refreshSelectionStyles()
		self:_refreshSelectedGroupDetails()
		if self:_resolveEvents() then
			self:_bindFeedbackEventIfNeeded()
		end
	end
end

function StudioBossDebugController:_handleFeedback(payload)
	if type(payload) ~= "table" then
		return
	end

	local status = tostring(payload.status or "Unknown")
	local action = tostring(payload.action or "")
	local groupId = math.max(0, math.floor(tonumber(payload.groupId) or 0))
	local partName = tostring(payload.partName or "")
	local bossName = tostring(payload.bossName or "")
	local moveSpeed = tonumber(payload.moveSpeed)

	if action == "TeleportToGroup" and status == "Success" then
		self:_setStatus(string.format("Teleported to %s", partName ~= "" and partName or tostring(groupId)), Color3.fromRGB(127, 226, 156))
		return
	end

	if action == "SetBossMoveSpeed" and status == "Success" then
		if groupId > 0 then
			self._lastConfirmedSpeedByGroupId[groupId] = moveSpeed
		end
		if groupId == self._selectedGroupId then
			self:_refreshSelectedGroupDetails()
			if type(moveSpeed) == "number" then
				self:_setSpeedTextSilently(formatSpeedText(moveSpeed))
			end
		end
		self:_setStatus(
			string.format("%s speed updated to %s", bossName ~= "" and bossName or tostring(groupId), formatSpeedText(moveSpeed)),
			Color3.fromRGB(127, 226, 156)
		)
		return
	end

	if status == "NotStudio" then
		self:_setStatus("Server rejected the request outside Studio", Color3.fromRGB(255, 136, 136))
		return
	end

	if status == "NotAllowed" then
		self:_setStatus("This player is not allowed to use Studio boss debug", Color3.fromRGB(255, 136, 136))
		return
	end

	if status == "InvalidGroupId" or status == "GroupNotFound" then
		self:_setStatus("The selected group does not exist", Color3.fromRGB(255, 170, 115))
		return
	end

	if status == "InvalidMoveSpeed" then
		self:_setStatus("Move speed must be a valid number", Color3.fromRGB(255, 170, 115))
		return
	end

	if status == "CharacterNotReady" then
		self:_setStatus("Character is not ready yet", Color3.fromRGB(255, 170, 115))
		return
	end

	if status == "SpawnPartNotFound" then
		self:_setStatus("The selected group is missing its land part", Color3.fromRGB(255, 170, 115))
		return
	end

	if status == "GroupHasNoBoss" then
		self:_setStatus("This group currently has no boss", Color3.fromRGB(255, 170, 115))
		return
	end

	self:_setStatus(string.format("Request failed: %s", status), Color3.fromRGB(255, 170, 115))
end

function StudioBossDebugController:Start()
	if self._started then
		return
	end

	self._started = true
	if not RunService:IsStudio() then
		return
	end

	self:_ensureGui()
	table.insert(self._connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end

		if UserInputService:GetFocusedTextBox() then
			return
		end

		if input.KeyCode == TOGGLE_KEY then
			self:_toggleGui()
		end
	end))

	table.insert(self._connections, RunService.Heartbeat:Connect(function(deltaTime)
		if not (self._screenGui and self._screenGui.Enabled) then
			return
		end

		self._refreshAccumulator += math.max(0, tonumber(deltaTime) or 0)
		if self._refreshAccumulator < DETAIL_REFRESH_INTERVAL then
			return
		end

		self._refreshAccumulator = 0
		self:_refreshSelectedGroupDetails()
	end))

	if self:_resolveEvents() then
		self:_bindFeedbackEventIfNeeded()
	end
end

function StudioBossDebugController:Destroy()
	self._started = false
	disconnectAll(self._connections)
	if self._screenGui then
		self._screenGui:Destroy()
		self._screenGui = nil
	end
end

return StudioBossDebugController
