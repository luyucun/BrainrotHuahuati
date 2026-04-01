local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

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
		"[IdleCoinController] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
		moduleName
	))
end

local FormatUtil = requireSharedModule("FormatUtil")
local GameConfig = requireSharedModule("GameConfig")
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
	error("[IdleCoinController] 找不到 IndexController，无法复用按钮动效逻辑。")
end

local IndexController = require(indexControllerModule)

local IdleCoinController = {}
IdleCoinController.__index = IdleCoinController

local MODAL_KEY = tostring((GameConfig.IDLE_COIN and GameConfig.IDLE_COIN.ModalKey) or "Idlecoin")
local SEVEN_DAY_MODAL_KEY = tostring((GameConfig.SEVEN_DAY_LOGIN_REWARD and GameConfig.SEVEN_DAY_LOGIN_REWARD.ModalKey) or "Sevendays")
local AUTO_OPEN_GRACE_SECONDS = 0.6
local CLAIM10_SWEEP_NAME = "_IdleCoinClaim10Sweep"
local WATCHED_NAMES = {
	Main = true,
	Idlecoin = true,
	Title = true,
	CloseButton = true,
	CurrentCash = true,
	Number = true,
	Claim = true,
	Claim10 = true,
	CashNum = true,
}

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

local function formatFullNumber(value, includeCurrencySymbol)
	local text = FormatUtil.FormatWithCommasCeil(value)
	if includeCurrencySymbol then
		return "$" .. text
	end
	return text
end

function IdleCoinController.new(modalController)
	local self = setmetatable({}, IdleCoinController)
	self._modalController = modalController
	self._started = false
	self._connections = {}
	self._uiConnections = {}
	self._mainGui = nil
	self._root = nil
	self._closeButton = nil
	self._numberLabel = nil
	self._claimButton = nil
	self._claim10Button = nil
	self._claim10CashNumLabel = nil
	self._claim10Gradient = nil
	self._claim10GradientTween = nil
	self._claim10SweepSerial = 0
	self._hasAutoOpened = false
	self._autoOpenUnlockAt = os.clock() + AUTO_OPEN_GRACE_SECONDS
	self._autoOpenRetryScheduled = false
	self._activePurchaseRequestId = ""
	self._activePurchaseProductId = 0
	self._isPromptingPurchase = false
	self._stateSyncEvent = nil
	self._requestStateSyncEvent = nil
	self._requestClaimEvent = nil
	self._requestClaim10PurchaseEvent = nil
	self._promptClaim10PurchaseEvent = nil
	self._requestClaim10PurchaseClosedEvent = nil
	self._feedbackEvent = nil
	self._state = {
		idleCoins = 0,
		claim10Coins = 0,
		canClaim = false,
		shouldAutoOpen = false,
		isPurchasePending = false,
		productId = math.max(0, math.floor(tonumber(GameConfig.IDLE_COIN and GameConfig.IDLE_COIN.DeveloperProductId or 0) or 0)),
	}
	self._indexHelper = IndexController.new(nil)
	return self
end

function IdleCoinController:_getPlayerGui()
	return localPlayer:FindFirstChild("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
end

function IdleCoinController:_getMainGui()
	local playerGui = self:_getPlayerGui()
	if not playerGui then
		return nil
	end

	return playerGui:FindFirstChild("Main") or playerGui:FindFirstChild("Main", true)
end

function IdleCoinController:_findDirectChildByName(root, childName)
	if not root then
		return nil
	end

	return root:FindFirstChild(childName)
end

function IdleCoinController:_findDescendantByNames(root, names)
	return self._indexHelper:_findDescendantByNames(root, names)
end

function IdleCoinController:_resolveInteractiveNode(node)
	return self._indexHelper:_resolveInteractiveNode(node)
end

function IdleCoinController:_bindButtonFx(interactiveNode, options, connectionBucket)
	self._indexHelper:_bindButtonFx(interactiveNode, options, connectionBucket)
end
function IdleCoinController:_isOpen()
	if self._modalController and self._modalController.IsModalOpen then
		return self._modalController:IsModalOpen(MODAL_KEY)
	end

	return isLiveInstance(self._root) and self._root.Visible == true
end

function IdleCoinController:_getHiddenNodesForModal()
	local hiddenNodes = {}
	if not self._mainGui then
		return hiddenNodes
	end

	for _, node in ipairs(self._mainGui:GetChildren()) do
		if node and node ~= self._root then
			table.insert(hiddenNodes, node)
		end
	end

	return hiddenNodes
end

function IdleCoinController:_isSevenDayModalBlockingAutoOpen()
	if not (self._modalController and self._modalController.IsModalOpen) then
		return false
	end

	return self._modalController:IsModalOpen(SEVEN_DAY_MODAL_KEY)
end

function IdleCoinController:_scheduleAutoOpenRetry(delaySeconds)
	if self._autoOpenRetryScheduled == true then
		return
	end

	self._autoOpenRetryScheduled = true
	task.delay(math.max(0, tonumber(delaySeconds) or 0), function()
		self._autoOpenRetryScheduled = false
		self:_tryAutoOpen()
	end)
end

function IdleCoinController:_tryAutoOpen()
	if self._state.shouldAutoOpen ~= true or self._state.idleCoins < 1 or self._hasAutoOpened then
		return
	end

	local unlockAt = tonumber(self._autoOpenUnlockAt) or 0
	if os.clock() < unlockAt then
		self:_scheduleAutoOpenRetry(unlockAt - os.clock())
		return
	end

	if self:_isSevenDayModalBlockingAutoOpen() then
		return
	end

	if not isLiveInstance(self._root) and not self:_bindUi() then
		return
	end

	self._hasAutoOpened = true
	self._state.shouldAutoOpen = false
	self:OpenIdleCoin()
end

function IdleCoinController:_render()
	if self._numberLabel and self._numberLabel:IsA("TextLabel") then
		self._numberLabel.Text = formatFullNumber(self._state.idleCoins, false)
	end

	if self._claim10CashNumLabel and self._claim10CashNumLabel:IsA("TextLabel") then
		self._claim10CashNumLabel.Text = formatFullNumber(self._state.claim10Coins, true)
	end

	local canClickClaim = self._state.canClaim == true and self._state.isPurchasePending ~= true and self._isPromptingPurchase ~= true
	local claimInteractive = self:_resolveInteractiveNode(self._claimButton)
	if claimInteractive and claimInteractive:IsA("GuiButton") then
		claimInteractive.Active = canClickClaim
		claimInteractive.AutoButtonColor = canClickClaim
		claimInteractive.Selectable = canClickClaim
	end

	local claim10Interactive = self:_resolveInteractiveNode(self._claim10Button)
	if claim10Interactive and claim10Interactive:IsA("GuiButton") then
		claim10Interactive.Active = canClickClaim
		claim10Interactive.AutoButtonColor = canClickClaim
		claim10Interactive.Selectable = canClickClaim
	end
end

function IdleCoinController:_applyState(payload)
	if type(payload) ~= "table" then
		return
	end

	self._state.idleCoins = math.max(0, tonumber(payload.idleCoins) or 0)
	self._state.claim10Coins = math.max(0, tonumber(payload.claim10Coins) or (self._state.idleCoins * 10))
	self._state.canClaim = payload.canClaim == true
	self._state.shouldAutoOpen = payload.shouldAutoOpen == true
	self._state.isPurchasePending = payload.isPurchasePending == true
	self._state.productId = math.max(0, math.floor(tonumber(payload.productId) or self._state.productId or 0))
	self:_render()
	self:_tryAutoOpen()
end

function IdleCoinController:OpenIdleCoin()
	if not isLiveInstance(self._root) and not self:_bindUi() then
		return
	end

	self:_render()
	if self._modalController then
		if not self:_isOpen() then
			self._modalController:OpenModal(MODAL_KEY, self._root, {
				HiddenNodes = self:_getHiddenNodesForModal(),
			})
		end
	elseif self._root and self._root:IsA("GuiObject") then
		self._root.Visible = true
	end
end

function IdleCoinController:CloseIdleCoin(immediate)
	if not isLiveInstance(self._root) then
		return
	end

	if self._modalController then
		self._modalController:CloseModal(MODAL_KEY, {
			Immediate = immediate == true,
		})
	elseif self._root and self._root:IsA("GuiObject") then
		self._root.Visible = false
	end
end

function IdleCoinController:_ensureSweepLayer()
	if not (self._claim10Button and self._claim10Button:IsA("GuiObject")) then
		return nil
	end

	self._claim10Button.ClipsDescendants = true
	local sweep = self._claim10Button:FindFirstChild(CLAIM10_SWEEP_NAME)
	if sweep and sweep:IsA("Frame") then
		return sweep
	end

	sweep = Instance.new("Frame")
	sweep.Name = CLAIM10_SWEEP_NAME
	sweep.AnchorPoint = Vector2.new(0.5, 0.5)
	sweep.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	sweep.BackgroundTransparency = 0.3
	sweep.BorderSizePixel = 0
	sweep.Rotation = 18
	sweep.Size = UDim2.fromScale(0.18, 1.7)
	sweep.Position = UDim2.fromScale(-0.35, 0.5)
	sweep.Visible = false
	sweep.ZIndex = math.max(10, self._claim10Button.ZIndex + 10)
	sweep.Parent = self._claim10Button

	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.75),
		NumberSequenceKeypoint.new(0.5, 0.15),
		NumberSequenceKeypoint.new(0.8, 0.75),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = sweep
	return sweep
end
function IdleCoinController:_startClaim10Animations()
	if self._claim10GradientTween then
		self._claim10GradientTween:Cancel()
		self._claim10GradientTween = nil
	end

	if self._claim10Gradient and self._claim10Gradient:IsA("UIGradient") then
		self._claim10Gradient.Offset = Vector2.new(-1, 0)
		self._claim10GradientTween = TweenService:Create(
			self._claim10Gradient,
			TweenInfo.new(2.2, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1, false, 0),
			{ Offset = Vector2.new(1, 0) }
		)
		self._claim10GradientTween:Play()
	end

	local claim10Button = self._claim10Button
	local sweep = self:_ensureSweepLayer()
	if not (claim10Button and sweep) then
		return
	end

	self._claim10SweepSerial = (tonumber(self._claim10SweepSerial) or 0) + 1
	local sweepSerial = self._claim10SweepSerial
	task.spawn(function()
		while self._started and self._claim10SweepSerial == sweepSerial and self._claim10Button == claim10Button and isLiveInstance(claim10Button) and isLiveInstance(sweep) do
			sweep.Visible = true
			sweep.Position = UDim2.fromScale(-0.35, 0.5)
			sweep.BackgroundTransparency = 0.3

			local travelTween = TweenService:Create(sweep, TweenInfo.new(0.55, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
				Position = UDim2.fromScale(1.35, 0.5),
			})
			local fadeTween = TweenService:Create(sweep, TweenInfo.new(0.55, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
				BackgroundTransparency = 0.85,
			})
			travelTween:Play()
			fadeTween:Play()
			travelTween.Completed:Wait()
			if not (self._claim10SweepSerial == sweepSerial and self._claim10Button == claim10Button and isLiveInstance(sweep)) then
				break
			end

			sweep.Visible = false
			task.wait(1.45)
		end

		if isLiveInstance(sweep) then
			sweep.Visible = false
		end
	end)
end

function IdleCoinController:_promptClaim10Purchase(payload)
	local requestId = type(payload) == "table" and tostring(payload.requestId or "") or ""
	local productId = math.max(0, math.floor(tonumber(type(payload) == "table" and payload.productId or 0) or 0))
	if requestId == "" or productId <= 0 then
		return
	end

	self._activePurchaseRequestId = requestId
	self._activePurchaseProductId = productId
	self._isPromptingPurchase = true
	self:_render()

	local didPrompt, promptError = pcall(function()
		MarketplaceService:PromptProductPurchase(localPlayer, productId)
	end)
	if didPrompt then
		return
	end

	warn(string.format("[IdleCoinController] 拉起挂机奖励 10 倍购买失败 productId=%d err=%s", productId, tostring(promptError)))
	if self._requestClaim10PurchaseClosedEvent and self._requestClaim10PurchaseClosedEvent:IsA("RemoteEvent") then
		self._requestClaim10PurchaseClosedEvent:FireServer({
			requestId = requestId,
			productId = productId,
			isPurchased = false,
			status = "PromptFailed",
		})
	end

	self._activePurchaseRequestId = ""
	self._activePurchaseProductId = 0
	self._isPromptingPurchase = false
	self._state.isPurchasePending = false
	self:_render()
end

function IdleCoinController:_handleFeedback(payload)
	if type(payload) ~= "table" then
		return
	end

	local status = tostring(payload.status or "")
	if status == "Success" then
		self._activePurchaseRequestId = ""
		self._activePurchaseProductId = 0
		self._isPromptingPurchase = false
		self._state.isPurchasePending = false
		self:_render()
		self:CloseIdleCoin()
		return
	end

	if status == "PromptFailed" then
		self._state.isPurchasePending = false
		self:_render()
	end
end
function IdleCoinController:_bindUi()
	local mainGui = self:_getMainGui()
	if not mainGui then
		return false
	end

	self._mainGui = mainGui
	self._root = self:_findDirectChildByName(mainGui, "Idlecoin")
	if not self._root then
		return false
	end

	local titleRoot = self:_findDescendantByNames(self._root, { "Title" })
	local currentCashRoot = self:_findDescendantByNames(self._root, { "CurrentCash" })
	self._closeButton = titleRoot and self:_findDescendantByNames(titleRoot, { "CloseButton" }) or nil
	self._numberLabel = currentCashRoot and self:_findDescendantByNames(currentCashRoot, { "Number" }) or nil
	self._claimButton = self:_findDescendantByNames(self._root, { "Claim" })
	self._claim10Button = self:_findDescendantByNames(self._root, { "Claim10" })
	self._claim10CashNumLabel = self._claim10Button and self:_findDescendantByNames(self._claim10Button, { "CashNum" }) or nil
	self._claim10Gradient = self._claim10Button and self:_findDescendantByNames(self._claim10Button, { "UIGradient" }) or nil

	disconnectAll(self._uiConnections)

	local closeInteractive = self:_resolveInteractiveNode(self._closeButton)
	if closeInteractive then
		table.insert(self._uiConnections, closeInteractive.Activated:Connect(function()
			self:CloseIdleCoin()
		end))
		self:_bindButtonFx(closeInteractive, {
			ScaleTarget = self._closeButton,
			RotationTarget = self._closeButton,
			HoverScale = 1.12,
			PressScale = 0.92,
			HoverRotation = 20,
		}, self._uiConnections)
	end

	local claimInteractive = self:_resolveInteractiveNode(self._claimButton)
	if claimInteractive then
		table.insert(self._uiConnections, claimInteractive.Activated:Connect(function()
			if self._requestClaimEvent and self._requestClaimEvent:IsA("RemoteEvent") then
				self._requestClaimEvent:FireServer()
			end
		end))
		self:_bindButtonFx(claimInteractive, {
			ScaleTarget = self._claimButton,
			HoverScale = 1.05,
			PressScale = 0.94,
		}, self._uiConnections)
	end

	local claim10Interactive = self:_resolveInteractiveNode(self._claim10Button)
	if claim10Interactive then
		table.insert(self._uiConnections, claim10Interactive.Activated:Connect(function()
			if self._requestClaim10PurchaseEvent and self._requestClaim10PurchaseEvent:IsA("RemoteEvent") then
				self._requestClaim10PurchaseEvent:FireServer()
			end
		end))
		self:_bindButtonFx(claim10Interactive, {
			ScaleTarget = self._claim10Button,
			HoverScale = 1.05,
			PressScale = 0.94,
		}, self._uiConnections)
	end

	if self._root and self._root:IsA("GuiObject") and not self:_isOpen() then
		self._root.Visible = false
	end

	self:_startClaim10Animations()
	self:_render()
	self:_tryAutoOpen()
	return true
end

function IdleCoinController:Start()
	if self._started then
		return
	end

	self._started = true
	local eventsRoot = ReplicatedStorage:WaitForChild(RemoteNames.RootFolder)
	local systemEvents = eventsRoot:WaitForChild(RemoteNames.SystemEventsFolder)
	self._stateSyncEvent = systemEvents:WaitForChild(RemoteNames.System.IdleCoinStateSync, 10)
	self._requestStateSyncEvent = systemEvents:WaitForChild(RemoteNames.System.RequestIdleCoinStateSync, 10)
	self._requestClaimEvent = systemEvents:WaitForChild(RemoteNames.System.RequestIdleCoinClaim, 10)
	self._requestClaim10PurchaseEvent = systemEvents:WaitForChild(RemoteNames.System.RequestIdleCoinClaim10Purchase, 10)
	self._promptClaim10PurchaseEvent = systemEvents:WaitForChild(RemoteNames.System.PromptIdleCoinClaim10Purchase, 10)
	self._requestClaim10PurchaseClosedEvent = systemEvents:WaitForChild(RemoteNames.System.RequestIdleCoinClaim10PurchaseClosed, 10)
	self._feedbackEvent = systemEvents:WaitForChild(RemoteNames.System.IdleCoinFeedback, 10)

	if self._stateSyncEvent and self._stateSyncEvent:IsA("RemoteEvent") then
		table.insert(self._connections, self._stateSyncEvent.OnClientEvent:Connect(function(payload)
			self:_applyState(payload)
		end))
	end

	if self._promptClaim10PurchaseEvent and self._promptClaim10PurchaseEvent:IsA("RemoteEvent") then
		table.insert(self._connections, self._promptClaim10PurchaseEvent.OnClientEvent:Connect(function(payload)
			self:_promptClaim10Purchase(payload)
		end))
	end

	if self._feedbackEvent and self._feedbackEvent:IsA("RemoteEvent") then
		table.insert(self._connections, self._feedbackEvent.OnClientEvent:Connect(function(payload)
			self:_handleFeedback(payload)
		end))
	end

	if self._modalController and self._modalController.GetVisibilityChangedEvent then
		local visibilityChangedEvent = self._modalController:GetVisibilityChangedEvent()
		if visibilityChangedEvent then
			table.insert(self._connections, visibilityChangedEvent:Connect(function(modalKey, isOpen)
				if modalKey == SEVEN_DAY_MODAL_KEY and isOpen ~= true then
					task.defer(function()
						self:_tryAutoOpen()
					end)
				end
			end))
		end
	end

	table.insert(self._connections, MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, isPurchased)
		if userId ~= localPlayer.UserId then
			return
		end

		if self._activePurchaseRequestId == "" or self._activePurchaseProductId <= 0 or productId ~= self._activePurchaseProductId then
			return
		end

		if self._requestClaim10PurchaseClosedEvent and self._requestClaim10PurchaseClosedEvent:IsA("RemoteEvent") then
			self._requestClaim10PurchaseClosedEvent:FireServer({
				requestId = self._activePurchaseRequestId,
				productId = productId,
				isPurchased = isPurchased == true,
			})
		end

		self._activePurchaseRequestId = ""
		self._activePurchaseProductId = 0
		self._isPromptingPurchase = false
		if not isPurchased then
			self._state.isPurchasePending = false
		end
		self:_render()
	end))

	local playerGui = self:_getPlayerGui()
	if playerGui then
		table.insert(self._connections, playerGui.DescendantAdded:Connect(function(descendant)
			if WATCHED_NAMES[descendant.Name] then
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

	if self._requestStateSyncEvent and self._requestStateSyncEvent:IsA("RemoteEvent") then
		self._requestStateSyncEvent:FireServer()
	end
end

return IdleCoinController

