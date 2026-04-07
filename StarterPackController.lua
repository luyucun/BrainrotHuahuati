--[[
脚本名字: StarterPackController
脚本文件: StarterPackController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/StarterPackController
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

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
		"[StarterPackController] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
		moduleName
	))
end

local GameConfig = requireSharedModule("GameConfig")
local BrainrotConfig = requireSharedModule("BrainrotConfig")
local FormatUtil = requireSharedModule("FormatUtil")
local RemoteNames = requireSharedModule("RemoteNames")
local IndexController = require(
	(script.Parent:FindFirstChild("IndexController") or script.Parent.Parent:FindFirstChild("IndexController"))
)

local MODAL_KEY = tostring((GameConfig.STARTER_PACK and GameConfig.STARTER_PACK.ModalKey) or "NewplayerPack")
local POLL_INTERVAL = math.max(
	0.25,
	tonumber(GameConfig.STARTER_PACK and GameConfig.STARTER_PACK.PurchaseSyncRetrySeconds or 0.8) or 0.8
)
local POLL_MAX = math.max(
	1,
	math.floor(tonumber(GameConfig.STARTER_PACK and GameConfig.STARTER_PACK.PurchaseSyncMaxAttempts or 8) or 8)
)
local GENERATED_ATTR = "StarterPackGeneratedItem"
local ENTRY_LIGHT_ROTATION_SECONDS = 7.5
local ENTRY_LIGHT_ROTATION_DEGREES_PER_SECOND = 360 / ENTRY_LIGHT_ROTATION_SECONDS

local function getStarterPackConfig()
	return GameConfig.STARTER_PACK or {}
end

local function isLive(instance)
	return instance and instance.Parent ~= nil
end

local function setVis(instance, value)
	if not instance then
		return
	end

	if instance:IsA("LayerCollector") then
		instance.Enabled = value == true
		return
	end

	if instance:IsA("GuiObject") then
		instance.Visible = value == true
	end
end

local function ensureUiScale(guiObject)
	if not (guiObject and guiObject:IsA("GuiObject")) then
		return nil
	end

	local uiScale = guiObject:FindFirstChildOfClass("UIScale")
	if uiScale then
		return uiScale
	end

	uiScale = Instance.new("UIScale")
	uiScale.Scale = 1
	uiScale.Parent = guiObject
	return uiScale
end

local function disconnectAll(connectionList)
	for _, connection in ipairs(connectionList) do
		if connection then
			connection:Disconnect()
		end
	end

	table.clear(connectionList)
end

local function stopTween(tween)
	if tween then
		tween:Cancel()
	end
end

local function offsetPosition(basePosition, scaleX, offsetX, scaleY, offsetY)
	return UDim2.new(
		basePosition.X.Scale + (tonumber(scaleX) or 0),
		basePosition.X.Offset + (tonumber(offsetX) or 0),
		basePosition.Y.Scale + (tonumber(scaleY) or 0),
		basePosition.Y.Offset + (tonumber(offsetY) or 0)
	)
end

local function rememberTransparencyTarget(targets, instance, propertyName)
	local success, currentValue = pcall(function()
		return instance[propertyName]
	end)

	if success then
		targets[#targets + 1] = {
			instance = instance,
			propertyName = propertyName,
			baseValue = currentValue,
		}
	end
end

local function collectTransparencyTargets(root)
	local targets = {}

	local function visit(node)
		if not node then
			return
		end

		if node:IsA("GuiObject") then
			rememberTransparencyTarget(targets, node, "BackgroundTransparency")
		end

		if node:IsA("ImageLabel") or node:IsA("ImageButton") then
			rememberTransparencyTarget(targets, node, "ImageTransparency")
		end

		if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
			rememberTransparencyTarget(targets, node, "TextTransparency")
			rememberTransparencyTarget(targets, node, "TextStrokeTransparency")
		end

		if node:IsA("ScrollingFrame") then
			rememberTransparencyTarget(targets, node, "ScrollBarImageTransparency")
		end

		if node:IsA("UIStroke") then
			rememberTransparencyTarget(targets, node, "Transparency")
		end

		for _, child in ipairs(node:GetChildren()) do
			visit(child)
		end
	end

	visit(root)
	return targets
end

local function applyTransparencyAlpha(targets, alpha)
	local clampedAlpha = math.clamp(tonumber(alpha) or 1, 0, 1)

	for _, entry in ipairs(targets) do
		local nextValue = 1 - ((1 - entry.baseValue) * clampedAlpha)
		pcall(function()
			entry.instance[entry.propertyName] = nextValue
		end)
	end
end

local function tweenTransparencyAlpha(targets, duration, easingStyle, easingDirection, startAlpha, endAlpha)
	local alphaDriver = Instance.new("NumberValue")
	local startValue = math.clamp(tonumber(startAlpha) or 0, 0, 1)
	local endValue = math.clamp(tonumber(endAlpha) or 1, 0, 1)
	alphaDriver.Value = startValue

	local connection = alphaDriver:GetPropertyChangedSignal("Value"):Connect(function()
		applyTransparencyAlpha(targets, alphaDriver.Value)
	end)

	applyTransparencyAlpha(targets, startValue)

	local tween = TweenService:Create(alphaDriver, TweenInfo.new(duration, easingStyle, easingDirection), {
		Value = endValue,
	})

	tween.Completed:Connect(function(playbackState)
		if connection then
			connection:Disconnect()
		end

		if playbackState == Enum.PlaybackState.Completed then
			applyTransparencyAlpha(targets, endValue)
		end

		alphaDriver:Destroy()
	end)

	return tween
end

local function rewardDisplays()
	local displays = {}
	local rewardConfig = getStarterPackConfig()
	local rewardList = type(rewardConfig.Rewards) == "table" and rewardConfig.Rewards or {}

	for index, rewardDefinition in ipairs(rewardList) do
		local rewardTypeText = string.lower(tostring(rewardDefinition.RewardType or rewardDefinition.Type or "Brainrot"))
		local rewardType = (rewardTypeText == "coin" or rewardTypeText == "coins") and "Coins" or "Brainrot"
		local rewardId = math.max(
			0,
			math.floor(tonumber(rewardDefinition.RewardId or rewardDefinition.BrainrotId or rewardDefinition.Id) or 0)
		)
		local amount = math.max(1, math.floor(tonumber(rewardDefinition.Amount or rewardDefinition.Count) or 1))
		local icon = tostring(rewardConfig.CoinRewardIcon or "")
		local name = tostring(rewardConfig.CoinRewardName or "Coins")

		if rewardType ~= "Coins" then
			local definition = BrainrotConfig.ById[rewardId]
			icon = definition and tostring(definition.Icon or "") or ""
			name = definition and tostring(definition.Name or "Brainrot") or "Brainrot"
		end

		displays[#displays + 1] = {
			index = index,
			icon = icon,
			name = name,
			amountText = rewardType == "Coins" and FormatUtil.FormatWithCommasCeil(amount) or tostring(amount),
		}
	end

	return displays
end

local StarterPackController = {}
StarterPackController.__index = StarterPackController

function StarterPackController.new(modalController)
	local self = setmetatable({}, StarterPackController)
	self._modalController = modalController
	self._indexHelper = IndexController.new(nil)
	self._connections = {}
	self._uiConnections = {}
	self._mainGui = nil
	self._entryRoot = nil
	self._entryLight = nil
	self._openButton = nil
	self._root = nil
	self._closeButton = nil
	self._buyButton = nil
	self._entryFloatDriver = nil
	self._entryFloatConnection = nil
	self._entryFloatTween = nil
	self._entryLightRotateConnection = nil
	self._entryRootBasePosition = nil
	self._entryRootBaseRotation = 0
	self._entryLightBaseRotation = 0
	self._entryAmbientStartClock = 0
	self._claimRoot = nil
	self._claimBg = nil
	self._claimList = nil
	self._claimTemplate = nil
	self._claimBgScale = nil
	self._claimOriginalPosition = nil
	self._claimOriginalRotation = 0
	self._claimAnimSerial = 0
	self._stateSyncEvent = nil
	self._requestStateSyncEvent = nil
	self._activeGamePassId = 0
	self._isPrompting = false
	self._claimVisible = false
	self._claimCanCloseAt = 0
	self._lastShownSuccessToken = 0
	self._pollSerial = 0
	self._state = {
		showEntry = true,
		isOwned = false,
		hasGranted = false,
		gamePassId = math.max(0, math.floor(tonumber(getStarterPackConfig().GamePassId) or 0)),
		successToken = 0,
		shouldShowClaimSuccess = false,
	}
	return self
end

function StarterPackController:_playerGui()
	return localPlayer:FindFirstChild("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
end

function StarterPackController:_mainGuiNode()
	local playerGui = self:_playerGui()
	if not playerGui then
		return nil
	end

	return playerGui:FindFirstChild("Main") or playerGui:FindFirstChild("Main", true)
end

function StarterPackController:_find(root, names)
	return self._indexHelper:_findDescendantByNames(root, names)
end

function StarterPackController:_button(node)
	return self._indexHelper:_resolveInteractiveNode(node)
end

function StarterPackController:_fx(button, options, bucket)
	self._indexHelper:_bindButtonFx(button, options, bucket)
end

function StarterPackController:_isOpen()
	if self._modalController and self._modalController.IsModalOpen then
		return self._modalController:IsModalOpen(MODAL_KEY)
	end

	return isLive(self._root) and self._root.Visible == true
end

function StarterPackController:_hiddenNodes()
	local nodes = {}
	if not self._mainGui then
		return nodes
	end

	for _, node in ipairs(self._mainGui:GetChildren()) do
		if node and node ~= self._root then
			nodes[#nodes + 1] = node
		end
	end

	return nodes
end

function StarterPackController:_requestState(reason, forceOwnershipRefresh, consumePendingSuccess)
	if self._requestStateSyncEvent and self._requestStateSyncEvent:IsA("RemoteEvent") then
		self._requestStateSyncEvent:FireServer({
			reason = tostring(reason or "Sync"),
			forceOwnershipRefresh = forceOwnershipRefresh == true,
			consumePendingSuccess = consumePendingSuccess == true,
		})
	end
end

function StarterPackController:_render()
	setVis(self._entryRoot, self._state.showEntry == true)

	local button = self:_button(self._buyButton)
	local canBuy = self._state.showEntry == true
		and self._state.isOwned ~= true
		and self._state.gamePassId > 0
		and self._isPrompting ~= true

	if button and button:IsA("GuiButton") then
		button.Active = canBuy
		button.AutoButtonColor = canBuy
		button.Selectable = canBuy
	end
end

function StarterPackController:_stopEntryAmbientMotion()
	stopTween(self._entryFloatTween)
	self._entryFloatTween = nil

	stopTween(self._entryFloatDriver)
	self._entryFloatDriver = nil

	if self._entryFloatConnection then
		self._entryFloatConnection:Disconnect()
		self._entryFloatConnection = nil
	end

	if self._entryLightRotateConnection then
		self._entryLightRotateConnection:Disconnect()
		self._entryLightRotateConnection = nil
	end

	if self._entryRoot and self._entryRootBasePosition and self._entryRoot:IsA("GuiObject") then
		self._entryRoot.Position = self._entryRootBasePosition
		self._entryRoot.Rotation = self._entryRootBaseRotation
	end

	if self._entryLight and self._entryLight:IsA("GuiObject") then
		self._entryLight.Rotation = self._entryLightBaseRotation
	end
	self._entryRootBasePosition = nil
	self._entryRootBaseRotation = 0
	self._entryAmbientStartClock = 0
end

function StarterPackController:_startEntryAmbientMotion()
	self:_stopEntryAmbientMotion()

	if self._entryRoot and self._entryRoot:IsA("GuiObject") then
		self._entryRootBasePosition = self._entryRoot.Position
		self._entryRootBaseRotation = tonumber(self._entryRoot.Rotation) or 0
	end

	if self._entryLight and self._entryLight:IsA("GuiObject") then
		self._entryLightBaseRotation = tonumber(self._entryLight.Rotation) or 0
	end

	if not (self._entryLight and self._entryLight:IsA("GuiObject")) then
		return
	end

	self._entryAmbientStartClock = os.clock()
	self._entryLight.Rotation = self._entryLightBaseRotation
	self._entryLightRotateConnection = RunService.RenderStepped:Connect(function()
		local light = self._entryLight
		if not (light and light.Parent and light:IsA("GuiObject")) then
			self:_stopEntryAmbientMotion()
			return
		end

		local elapsed = math.max(0, os.clock() - self._entryAmbientStartClock)
		light.Rotation = self._entryLightBaseRotation + ((elapsed * ENTRY_LIGHT_ROTATION_DEGREES_PER_SECOND) % 360)
	end)
end

function StarterPackController:_clearClaimItems()
	if not self._claimList then
		return
	end

	for _, child in ipairs(self._claimList:GetChildren()) do
		if child ~= self._claimTemplate and child:GetAttribute(GENERATED_ATTR) == true then
			child:Destroy()
		end
	end
end

function StarterPackController:_ensureClaimNodes()
	if self._claimRoot
		and self._claimBg
		and self._claimList
		and self._claimTemplate
		and self._claimTemplate.Parent
	then
		return true
	end

	local playerGui = self:_playerGui()
	local mainGui = self._mainGui or self:_mainGuiNode()

	self._claimRoot = (playerGui and (playerGui:FindFirstChild("ClaimSuccessful") or playerGui:FindFirstChild("ClaimSuccessful", true)))
		or (mainGui and (mainGui:FindFirstChild("ClaimSuccessful") or mainGui:FindFirstChild("ClaimSuccessful", true)))

	if not self._claimRoot then
		return false
	end

	self._claimBg = self:_find(self._claimRoot, { "Bg", "Background", "Panel", "Content" })
	if not self._claimBg and self._claimRoot:IsA("GuiObject") then
		self._claimBg = self._claimRoot
	end

	self._claimList = self._claimBg and self:_find(self._claimBg, {
		"ItemListFrame",
		"ItemList",
		"RewardList",
		"Rewards",
		"List",
		"Items",
	}) or nil

	self._claimTemplate = self._claimList and self:_find(self._claimList, {
		"ItemTemplate",
		"RewardTemplate",
		"Template",
	}) or nil

	if not (self._claimBg and self._claimList and self._claimTemplate) then
		return false
	end

	self._claimBgScale = ensureUiScale(self._claimBg)
	self._claimOriginalPosition = self._claimBg.Position
	self._claimOriginalRotation = tonumber(self._claimBg.Rotation) or 0

	if self._claimTemplate:IsA("GuiObject") then
		self._claimTemplate.Visible = false
		self._claimTemplate.Rotation = 0
	end

	if self._claimBgScale then
		self._claimBgScale.Scale = 1
	end

	setVis(self._claimRoot, false)
	if self._claimBg ~= self._claimRoot then
		setVis(self._claimBg, false)
	end

	return true
end

function StarterPackController:_resetClaimVisuals()
	if self._claimBg and self._claimOriginalPosition then
		self._claimBg.Position = self._claimOriginalPosition
		self._claimBg.Rotation = self._claimOriginalRotation
	end

	if self._claimBgScale then
		self._claimBgScale.Scale = 1
	end
end

function StarterPackController:_hideClaim()
	self._claimAnimSerial += 1
	self._claimVisible = false
	self._claimCanCloseAt = 0

	self:_resetClaimVisuals()
	self:_clearClaimItems()

	setVis(self._claimRoot, false)
	if self._claimBg and self._claimBg ~= self._claimRoot then
		setVis(self._claimBg, false)
	end
end

function StarterPackController:_buildClaimItemNodes()
	local itemNodes = {}

	for _, reward in ipairs(rewardDisplays()) do
		local clone = self._claimTemplate:Clone()
		clone.Name = string.format("StarterPackReward_%02d", reward.index)
		clone.LayoutOrder = reward.index
		clone:SetAttribute(GENERATED_ATTR, true)

		local icon = self:_find(clone, { "Icon", "ItemIcon" })
		local numberLabel = self:_find(clone, { "Number", "Num" })
		local nameLabel = self:_find(clone, { "Name" })

		if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
			icon.Image = reward.icon
		end

		if numberLabel and numberLabel:IsA("TextLabel") then
			numberLabel.Text = reward.amountText
		end

		if nameLabel and nameLabel:IsA("TextLabel") then
			nameLabel.Text = reward.name
		end

		local scale = ensureUiScale(clone)
		if scale then
			scale.Scale = reward.index == 1 and 0.66 or 0.72
		end

		if clone:IsA("GuiObject") then
			clone.Visible = true
			clone.Rotation = reward.index == 1 and -6 or -3
		end

		local transparencyTargets = collectTransparencyTargets(clone)
		applyTransparencyAlpha(transparencyTargets, 0)

		clone.Parent = self._claimList
		itemNodes[#itemNodes + 1] = {
			root = clone,
			scale = scale,
			transparencyTargets = transparencyTargets,
		}
	end

	return itemNodes
end

function StarterPackController:_revealClaimItems(itemNodes, token, animSerial)
	local revealInterval = math.max(0.03, tonumber(getStarterPackConfig().SuccessItemRevealInterval) or 0.08)

	task.spawn(function()
		for itemIndex, node in ipairs(itemNodes) do
			if animSerial ~= self._claimAnimSerial
				or self._claimVisible ~= true
				or self._lastShownSuccessToken ~= token
			then
				return
			end

			local revealDuration = itemIndex == 1 and 0.18 or 0.15

			if node.root and node.root:IsA("GuiObject") then
				node.root.Visible = true
			end

			local fadeTween = tweenTransparencyAlpha(
				node.transparencyTargets,
				revealDuration,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out,
				0,
				1
			)
			fadeTween:Play()

			if node.scale then
				TweenService:Create(node.scale, TweenInfo.new(revealDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Scale = 1,
				}):Play()
			end

			if node.root and node.root:IsA("GuiObject") then
				TweenService:Create(node.root, TweenInfo.new(revealDuration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
					Rotation = 0,
				}):Play()
			end

			task.wait(revealInterval)
		end
	end)
end

function StarterPackController:_pulseClaimReady(token, animSerial)
	local lockSeconds = math.max(1, tonumber(getStarterPackConfig().SuccessLockSeconds) or 1)

	task.delay(lockSeconds, function()
		if animSerial ~= self._claimAnimSerial
			or self._claimVisible ~= true
			or self._lastShownSuccessToken ~= token
			or not self._claimBgScale
		then
			return
		end

		local growTween = TweenService:Create(
			self._claimBgScale,
			TweenInfo.new(0.09, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ Scale = 1.03 }
		)
		local settleTween = TweenService:Create(
			self._claimBgScale,
			TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ Scale = 1 }
		)

		growTween:Play()
		growTween.Completed:Connect(function(playbackState)
			if playbackState == Enum.PlaybackState.Completed
				and animSerial == self._claimAnimSerial
				and self._claimVisible == true
			then
				settleTween:Play()
			end
		end)
	end)
end

function StarterPackController:_showClaim(token)
	token = math.max(0, math.floor(tonumber(token) or 0))
	if token <= 0 or token == self._lastShownSuccessToken or not self:_ensureClaimNodes() then
		return
	end

	self._lastShownSuccessToken = token
	self:CloseStarterPack(true)
	self:_hideClaim()

	self._claimAnimSerial += 1
	local animSerial = self._claimAnimSerial
	local slideDuration = math.max(0.16, tonumber(getStarterPackConfig().SuccessSlideDuration) or 0.28)
	local settleDuration = math.max(0.1, slideDuration * 0.55)
	local startPosition = offsetPosition(self._claimOriginalPosition, -0.85, -120, 0, 0)
	local overshootPosition = offsetPosition(self._claimOriginalPosition, 0.02, 16, 0, 0)
	local itemNodes = self:_buildClaimItemNodes()

	setVis(self._claimRoot, true)
	if self._claimBg ~= self._claimRoot then
		setVis(self._claimBg, true)
	end

	self._claimVisible = true
	self._claimCanCloseAt = os.clock() + math.max(1, tonumber(getStarterPackConfig().SuccessLockSeconds) or 1)
	self._claimBg.Position = startPosition
	self._claimBg.Rotation = self._claimOriginalRotation - 8

	if self._claimBgScale then
		self._claimBgScale.Scale = 0.92
	end

	local enterTween = TweenService:Create(
		self._claimBg,
		TweenInfo.new(slideDuration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{
			Position = overshootPosition,
			Rotation = self._claimOriginalRotation + 1.5,
		}
	)
	local settleTween = TweenService:Create(
		self._claimBg,
		TweenInfo.new(settleDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{
			Position = self._claimOriginalPosition,
			Rotation = self._claimOriginalRotation,
		}
	)
	local enterScaleTween = self._claimBgScale and TweenService:Create(
		self._claimBgScale,
		TweenInfo.new(slideDuration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Scale = 1.03 }
	) or nil
	local settleScaleTween = self._claimBgScale and TweenService:Create(
		self._claimBgScale,
		TweenInfo.new(settleDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	) or nil

	enterTween:Play()
	if enterScaleTween then
		enterScaleTween:Play()
	end

	task.spawn(function()
		enterTween.Completed:Wait()

		if animSerial ~= self._claimAnimSerial
			or self._claimVisible ~= true
			or self._lastShownSuccessToken ~= token
		then
			return
		end

		settleTween:Play()
		if settleScaleTween then
			settleScaleTween:Play()
		end

		self:_revealClaimItems(itemNodes, token, animSerial)
	end)

	self:_pulseClaimReady(token, animSerial)
end

function StarterPackController:_bindUi()
	self:_stopEntryAmbientMotion()

	self._mainGui = self:_mainGuiNode()
	if not self._mainGui then
		return false
	end

	self._entryRoot = self._mainGui:FindFirstChild("StarterPack") or self._mainGui:FindFirstChild("StarterPack", true)
	self._entryLight = self._entryRoot and self:_find(self._entryRoot, { "Light" }) or nil
	self._openButton = self._entryRoot and self:_button(
		self:_find(self._entryRoot, { "TextButton", "Button" }) or self._entryRoot
	) or nil
	self._root = self._mainGui:FindFirstChild("NewplayerPack") or self._mainGui:FindFirstChild("NewplayerPack", true)
	if not self._root then
		return false
	end

	self._closeButton = self:_find(self._root, { "CloseButton" })
	self._buyButton = self:_find(self._root, { "BuyButton" })

	disconnectAll(self._uiConnections)

	if self._openButton then
		table.insert(self._uiConnections, self._openButton.Activated:Connect(function()
			self:OpenStarterPack()
		end))
		self:_fx(self._openButton, {
			ScaleTarget = self._entryRoot or self._openButton,
			HoverScale = 1.05,
			PressScale = 0.94,
		}, self._uiConnections)
	end

	local closeButton = self:_button(self._closeButton)
	if closeButton then
		table.insert(self._uiConnections, closeButton.Activated:Connect(function()
			self:CloseStarterPack()
		end))
		self:_fx(closeButton, {
			ScaleTarget = self._closeButton,
			RotationTarget = self._closeButton,
			HoverScale = 1.12,
			PressScale = 0.92,
			HoverRotation = 20,
		}, self._uiConnections)
	end

	local buyButton = self:_button(self._buyButton)
	if buyButton then
		table.insert(self._uiConnections, buyButton.Activated:Connect(function()
			self:_promptPurchase()
		end))
		self:_fx(buyButton, {
			ScaleTarget = self._buyButton,
			HoverScale = 1.05,
			PressScale = 0.94,
		}, self._uiConnections)
	end

	self:_ensureClaimNodes()

	if self._root and self._root:IsA("GuiObject") and not self:_isOpen() then
		self._root.Visible = false
	end

	self:_startEntryAmbientMotion()
	self:_render()
	return true
end

function StarterPackController:_stopPolling()
	self._pollSerial = (tonumber(self._pollSerial) or 0) + 1
end

function StarterPackController:_startPolling()
	self:_stopPolling()

	local serial = self._pollSerial
	local remaining = POLL_MAX

	local function step()
		if serial ~= self._pollSerial or self._state.hasGranted == true or remaining <= 0 then
			return
		end

		remaining -= 1
		self:_requestState("PurchaseFinished", true, true)
		if remaining > 0 then
			task.delay(POLL_INTERVAL, step)
		end
	end

	step()
end

function StarterPackController:_promptPurchase()
	local gamePassId = math.max(0, math.floor(tonumber(self._state.gamePassId) or 0))
	if gamePassId <= 0 or self._isPrompting == true then
		return
	end

	self._activeGamePassId = gamePassId
	self._isPrompting = true
	self:_render()

	local ok, err = pcall(function()
		MarketplaceService:PromptGamePassPurchase(localPlayer, gamePassId)
	end)

	if not ok then
		warn(string.format(
			"[StarterPackController] 拉起新手礼包通行证购买失败 gamePassId=%d err=%s",
			gamePassId,
			tostring(err)
		))
		self._activeGamePassId = 0
		self._isPrompting = false
		self:_render()
	end
end

function StarterPackController:_applyState(payload)
	if type(payload) ~= "table" then
		return
	end

	self._state.showEntry = payload.showEntry == true
	self._state.isOwned = payload.isOwned == true
	self._state.hasGranted = payload.hasGranted == true
	self._state.gamePassId = math.max(0, math.floor(tonumber(payload.gamePassId) or self._state.gamePassId or 0))
	self._state.successToken = math.max(0, math.floor(tonumber(payload.successToken) or 0))
	self._state.shouldShowClaimSuccess = payload.shouldShowClaimSuccess == true

	self:_render()

	if self._state.showEntry ~= true and self:_isOpen() then
		self:CloseStarterPack(true)
	end

	if self._state.hasGranted == true then
		self:_stopPolling()
	end

	if self._state.shouldShowClaimSuccess == true then
		self:_showClaim(self._state.successToken)
	end
end

function StarterPackController:OpenStarterPack()
	if not isLive(self._root) and not self:_bindUi() then
		return
	end

	self:_render()
	self:_requestState("Open", false, true)

	if self._modalController then
		if not self:_isOpen() then
			self._modalController:OpenModal(MODAL_KEY, self._root, {
				HiddenNodes = self:_hiddenNodes(),
			})
		end
	elseif self._root and self._root:IsA("GuiObject") then
		self._root.Visible = true
	end
end

function StarterPackController:CloseStarterPack(immediate)
	if not isLive(self._root) then
		return
	end

	if self._modalController then
		self._modalController:CloseModal(MODAL_KEY, { Immediate = immediate == true })
	else
		self._root.Visible = false
	end
end

function StarterPackController:Start()
	if self._started then
		return
	end
	self._started = true

	local eventsRoot = ReplicatedStorage:WaitForChild(RemoteNames.RootFolder)
	local systemEvents = eventsRoot:WaitForChild(RemoteNames.SystemEventsFolder)
	self._stateSyncEvent = systemEvents:WaitForChild(RemoteNames.System.StarterPackStateSync, 10)
	self._requestStateSyncEvent = systemEvents:WaitForChild(RemoteNames.System.RequestStarterPackStateSync, 10)

	if self._stateSyncEvent and self._stateSyncEvent:IsA("RemoteEvent") then
		table.insert(self._connections, self._stateSyncEvent.OnClientEvent:Connect(function(payload)
			self:_applyState(payload)
		end))
	end

	table.insert(self._connections, MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
		if player ~= localPlayer then
			return
		end

		local parsedId = math.max(0, math.floor(tonumber(gamePassId) or 0))
		if self._activeGamePassId <= 0 or parsedId ~= self._activeGamePassId then
			return
		end

		self._activeGamePassId = 0
		self._isPrompting = false
		self:_render()

		if wasPurchased == true then
			self:_startPolling()
		end
	end))

	table.insert(self._connections, UserInputService.InputBegan:Connect(function(inputObject)
		if self._claimVisible ~= true or os.clock() < (tonumber(self._claimCanCloseAt) or 0) then
			return
		end

		local inputType = inputObject.UserInputType
		if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch then
			self:_hideClaim()
		end
	end))

	local playerGui = self:_playerGui()
	if playerGui then
		table.insert(self._connections, playerGui.DescendantAdded:Connect(function(descendant)
			if descendant and (
				descendant.Name == "Main"
				or descendant.Name == "StarterPack"
				or descendant.Name == "NewplayerPack"
				or descendant.Name == "ClaimSuccessful"
			) then
				task.defer(function()
					self:_bindUi()
				end)
			end
		end))
	end

	table.insert(self._connections, localPlayer.CharacterAdded:Connect(function()
		task.defer(function()
			self:_bindUi()
		end)
	end))

	task.spawn(function()
		local deadline = os.clock() + 12
		repeat
			if self:_bindUi() then
				return
			end
			task.wait(1)
		until os.clock() >= deadline
	end)

	self:_requestState("Startup", false, true)
end

return StarterPackController


