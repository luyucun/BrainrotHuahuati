--[[
脚本名字: SevenDayLoginRewardController
脚本文件: SevenDayLoginRewardController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/SevenDayLoginRewardController
]]

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
		"[SevenDayLoginRewardController] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
		moduleName
	))
end

local FormatUtil = requireSharedModule("FormatUtil")
local GameConfig = requireSharedModule("GameConfig")
local BrainrotConfig = requireSharedModule("BrainrotConfig")
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
	error("[SevenDayLoginRewardController] 找不到 IndexController，无法复用按钮动效逻辑。")
end

local IndexController = require(indexControllerModule)

local SevenDayLoginRewardController = {}
SevenDayLoginRewardController.__index = SevenDayLoginRewardController

local MODAL_KEY = tostring((GameConfig.SEVEN_DAY_LOGIN_REWARD and GameConfig.SEVEN_DAY_LOGIN_REWARD.ModalKey) or "Sevendays")
local REWARD_FRAME_NAMES = {
	"Reward01",
	"Reward02",
	"Reward03",
	"Reward04",
	"Reward05",
	"Reward06",
	"Reward07",
}
local WATCHED_NAMES = {
	Main = true,
	TopRightGui = true,
	SevenDays = true,
	Sevendays = true,
    SevendaysClaim = true,
	Title = true,
	CloseButton = true,
	NextReward = true,
	UnlockAll = true,
	RedPoint = true,
	Button = true,
	Reward01 = true,
	Reward02 = true,
	Reward03 = true,
	Reward04 = true,
	Reward05 = true,
	Reward06 = true,
	Reward07 = true,
	Claim = true,
	Claimed = true,
	DayNum = true,
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

local function setVisibility(instance, isVisible)
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

local function getUtcDayKey(timestamp)
	local safeTimestamp = math.max(0, math.floor(tonumber(timestamp) or 0))
	return math.floor(safeTimestamp / 86400)
end

local function getNextUtcTimestamp(timestamp)
	local safeTimestamp = math.max(0, math.floor(tonumber(timestamp) or 0))
	return (getUtcDayKey(safeTimestamp) + 1) * 86400
end

local function formatRewardAmount(rewardType, amount)
	local safeAmount = math.max(0, math.floor(tonumber(amount) or 0))
	if rewardType == "Coins" then
		return FormatUtil.FormatCompactCurrencyCeil(safeAmount)
	end

	return tostring(math.max(1, safeAmount))
end

function SevenDayLoginRewardController.new(modalController)
	local self = setmetatable({}, SevenDayLoginRewardController)
	self._modalController = modalController
	self._started = false
	self._connections = {}
	self._uiConnections = {}
	self._mainGui = nil
	self._topRightGui = nil
	self._entryRoot = nil
	self._entryRedPoint = nil
	self._openButton = nil
	self._root = nil
	self._closeButton = nil
	self._nextRewardLabel = nil
	self._unlockAllButton = nil
	self._claimSuccessRoot = nil
	self._claimSuccessText = nil
	self._claimSuccessScale = nil
	self._rewardNodes = {}
	self._stateSyncEvent = nil
	self._requestStateSyncEvent = nil
	self._requestClaimEvent = nil
	self._state = {
		rewards = {},
		hasClaimableReward = false,
		shouldAutoOpen = false,
		canUnlockAll = false,
		productId = math.max(0, math.floor(tonumber(GameConfig.SEVEN_DAY_LOGIN_REWARD and GameConfig.SEVEN_DAY_LOGIN_REWARD.DeveloperProductId or 0) or 0)),
		pendingCycleReset = false,
		nextRefreshAt = 0,
	}
	self._didRequestInitialSync = false
	self._activePromptProductId = 0
	self._isPromptingUnlockAll = false
	self._hasAutoOpened = false
	self._pendingClaimDayIndex = 0
	self._pendingClaimDeadline = 0
	self._claimTipQueue = {}
	self._isShowingClaimTip = false
	self._lastObservedUtcDay = getUtcDayKey(os.time())
	self._redPointShakeSerial = 0
	self._indexHelper = IndexController.new(nil)
	return self
end

function SevenDayLoginRewardController:_getPlayerGui()
	return localPlayer:FindFirstChild("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
end

function SevenDayLoginRewardController:_getMainGui()
	local playerGui = self:_getPlayerGui()
	if not playerGui then
		return nil
	end

	return playerGui:FindFirstChild("Main") or playerGui:FindFirstChild("Main", true)
end

function SevenDayLoginRewardController:_findDirectChildByName(root, childName)
	if not root then
		return nil
	end

	local child = root:FindFirstChild(childName)
	if child then
		return child
	end

	for _, descendant in ipairs(root:GetChildren()) do
		if descendant.Name == childName then
			return descendant
		end
	end

	return nil
end

function SevenDayLoginRewardController:_findDescendantByNames(root, names)
	return self._indexHelper:_findDescendantByNames(root, names)
end

function SevenDayLoginRewardController:_resolveInteractiveNode(node)
	return self._indexHelper:_resolveInteractiveNode(node)
end

function SevenDayLoginRewardController:_bindButtonFx(interactiveNode, options, connectionBucket)
	self._indexHelper:_bindButtonFx(interactiveNode, options, connectionBucket)
end

function SevenDayLoginRewardController:_isOpen()
	if self._modalController and self._modalController.IsModalOpen then
		return self._modalController:IsModalOpen(MODAL_KEY)
	end

	return isLiveInstance(self._root) and self._root.Visible == true
end

function SevenDayLoginRewardController:_getHiddenNodesForModal()
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

function SevenDayLoginRewardController:_requestStateSync(reason, allowCycleReset)
	if self._requestStateSyncEvent and self._requestStateSyncEvent:IsA("RemoteEvent") then
		self._requestStateSyncEvent:FireServer({
			reason = tostring(reason or "Sync"),
			allowCycleReset = allowCycleReset == true,
		})
	end
end

function SevenDayLoginRewardController:_findClaimSuccessRoot(mainGui, playerGui)
	if mainGui then
		local direct = mainGui:FindFirstChild("SevendaysClaim")
		if direct and direct:IsA("GuiObject") then
			return direct
		end

		local nested = mainGui:FindFirstChild("SevendaysClaim", true)
		if nested and nested:IsA("GuiObject") then
			return nested
		end
	end

	if playerGui then
		local direct = playerGui:FindFirstChild("SevendaysClaim")
		if direct and direct:IsA("GuiObject") then
			return direct
		end

		local nested = playerGui:FindFirstChild("SevendaysClaim", true)
		if nested and nested:IsA("GuiObject") then
			return nested
		end
	end

	return nil
end

function SevenDayLoginRewardController:_ensureClaimSuccessTipNodes()
	if self._claimSuccessRoot
		and self._claimSuccessRoot.Parent
		and self._claimSuccessText
		and self._claimSuccessText.Parent
	then
		return true
	end

	local playerGui = self:_getPlayerGui()
	local mainGui = self._mainGui or self:_getMainGui()
	local claimSuccessRoot = self:_findClaimSuccessRoot(mainGui, playerGui)
	if not claimSuccessRoot then
		return false
	end

	local claimSuccessText = self:_findDescendantByNames(claimSuccessRoot, { "Text" })
	if not (claimSuccessText and claimSuccessText:IsA("TextLabel")) then
		return false
	end

	self._claimSuccessRoot = claimSuccessRoot
	self._claimSuccessText = claimSuccessText
	self._claimSuccessScale = ensureUiScale(claimSuccessRoot)
	setVisibility(self._claimSuccessRoot, false)
	return true
end

function SevenDayLoginRewardController:_prepareClaimSuccessTip()
	if not self:_ensureClaimSuccessTipNodes() then
		return false
	end

	if self._claimSuccessText and self._claimSuccessText:IsA("TextLabel") then
		self._claimSuccessText.Text = tostring(GameConfig.SEVEN_DAY_LOGIN_REWARD and GameConfig.SEVEN_DAY_LOGIN_REWARD.SuccessTipText or "Claim Successful!")
	end

	return true
end

function SevenDayLoginRewardController:_showNextClaimSuccessTip()
	if self._isShowingClaimTip then
		return
	end

	if #self._claimTipQueue <= 0 then
		setVisibility(self._claimSuccessRoot, false)
		return
	end

	if not self:_prepareClaimSuccessTip() then
		return
	end

	table.remove(self._claimTipQueue, 1)

	local root = self._claimSuccessRoot
	local uiScale = self._claimSuccessScale or ensureUiScale(root)
	if not (root and uiScale) then
		return
	end

	self._isShowingClaimTip = true
	local uiConfig = GameConfig.UI or {}
	local openFromScale = tonumber(uiConfig.ModalOpenFromScale) or 0.82
	local overshootScale = tonumber(uiConfig.ModalOpenOvershootScale) or 1.06
	local overshootDuration = tonumber(uiConfig.ModalOpenOvershootDuration) or 0.18
	local settleDuration = tonumber(uiConfig.ModalOpenSettleDuration) or 0.12
	local closeOvershootScale = tonumber(uiConfig.ModalCloseOvershootScale) or 1.04
	local closeOvershootDuration = tonumber(uiConfig.ModalCloseOvershootDuration) or 0.1
	local closeToScale = tonumber(uiConfig.ModalCloseToScale) or 0.78
	local closeShrinkDuration = tonumber(uiConfig.ModalCloseShrinkDuration) or 0.14
	local holdSeconds = math.max(0.2, tonumber(GameConfig.SEVEN_DAY_LOGIN_REWARD and GameConfig.SEVEN_DAY_LOGIN_REWARD.SuccessTipDisplaySeconds or 1.8))

	setVisibility(root, true)
	uiScale.Scale = openFromScale

	local openOvershootTween = TweenService:Create(uiScale, TweenInfo.new(overshootDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = overshootScale,
	})
	local openSettleTween = TweenService:Create(uiScale, TweenInfo.new(settleDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Scale = 1,
	})
	local closeOvershootTween = TweenService:Create(uiScale, TweenInfo.new(closeOvershootDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Scale = closeOvershootScale,
	})
	local closeShrinkTween = TweenService:Create(uiScale, TweenInfo.new(closeShrinkDuration, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Scale = closeToScale,
	})

	task.spawn(function()
		openOvershootTween:Play()
		openOvershootTween.Completed:Wait()
		openSettleTween:Play()
		openSettleTween.Completed:Wait()

		task.wait(holdSeconds)

		closeOvershootTween:Play()
		closeOvershootTween.Completed:Wait()
		closeShrinkTween:Play()
		closeShrinkTween.Completed:Wait()

		uiScale.Scale = 1
		setVisibility(root, false)
		self._isShowingClaimTip = false
		self:_showNextClaimSuccessTip()
	end)
end

function SevenDayLoginRewardController:_enqueueClaimSuccessTip()
	table.insert(self._claimTipQueue, true)
	self:_showNextClaimSuccessTip()
end

function SevenDayLoginRewardController:_resolvePendingClaimSuccess(rewards)
	local pendingClaimDayIndex = math.max(0, math.floor(tonumber(self._pendingClaimDayIndex) or 0))
	if pendingClaimDayIndex <= 0 then
		return
	end

	local reward = type(rewards) == "table" and rewards[pendingClaimDayIndex] or nil
	if type(reward) == "table" and reward.isClaimed == true then
		self._pendingClaimDayIndex = 0
		self._pendingClaimDeadline = 0
		self:_enqueueClaimSuccessTip()
		return
	end

	if os.clock() >= (tonumber(self._pendingClaimDeadline) or 0) then
		self._pendingClaimDayIndex = 0
		self._pendingClaimDeadline = 0
	end
end

function SevenDayLoginRewardController:_bindRemoteEvents()
	local eventsRoot = ReplicatedStorage:FindFirstChild(RemoteNames.RootFolder)
	if not eventsRoot then
		return false
	end

	local systemEvents = eventsRoot:FindFirstChild(RemoteNames.SystemEventsFolder)
	if not systemEvents then
		return false
	end

	local stateSyncEvent = systemEvents:FindFirstChild(RemoteNames.System.SevenDayLoginRewardStateSync)
	if stateSyncEvent and stateSyncEvent:IsA("RemoteEvent") and self._stateSyncEvent ~= stateSyncEvent then
		self._stateSyncEvent = stateSyncEvent
		table.insert(self._connections, stateSyncEvent.OnClientEvent:Connect(function(payload)
			self:_applyState(payload)
		end))
	end

	local requestStateSyncEvent = systemEvents:FindFirstChild(RemoteNames.System.RequestSevenDayLoginRewardStateSync)
	if requestStateSyncEvent and requestStateSyncEvent:IsA("RemoteEvent") then
		self._requestStateSyncEvent = requestStateSyncEvent
	end

	local requestClaimEvent = systemEvents:FindFirstChild(RemoteNames.System.RequestSevenDayLoginRewardClaim)
	if requestClaimEvent and requestClaimEvent:IsA("RemoteEvent") then
		self._requestClaimEvent = requestClaimEvent
	end

	if self._requestStateSyncEvent and self._didRequestInitialSync ~= true then
		self._didRequestInitialSync = true
		self:_requestStateSync("Startup", false)
	end

	return self._stateSyncEvent ~= nil and self._requestStateSyncEvent ~= nil and self._requestClaimEvent ~= nil
end

function SevenDayLoginRewardController:_resolveRewardDisplay(reward, dayIndex)
	local configuredReward = nil
	local rewardConfig = GameConfig.SEVEN_DAY_LOGIN_REWARD
	if type(rewardConfig) == "table" and type(rewardConfig.Rewards) == "table" then
		configuredReward = rewardConfig.Rewards[dayIndex]
	end

	local rewardType = type(reward) == "table" and tostring(reward.rewardType or "") or ""
	local rewardId = math.max(0, math.floor(tonumber(type(reward) == "table" and reward.rewardId or 0) or 0))
	local amount = math.max(0, math.floor(tonumber(type(reward) == "table" and reward.amount or 0) or 0))
	if type(configuredReward) == "table" then
		rewardType = tostring(configuredReward.RewardType or configuredReward.Type or rewardType)
		rewardId = math.max(0, math.floor(tonumber(configuredReward.RewardId or configuredReward.BrainrotId or configuredReward.Id or rewardId) or 0))
		amount = math.max(0, math.floor(tonumber(configuredReward.Amount or configuredReward.Count or amount) or 0))
	end

	rewardType = string.lower(rewardType)
	if rewardType == "coin" or rewardType == "coins" then
		return {
			name = tostring(GameConfig.SEVEN_DAY_LOGIN_REWARD and GameConfig.SEVEN_DAY_LOGIN_REWARD.CoinRewardName or "Coins"),
			icon = tostring(GameConfig.SEVEN_DAY_LOGIN_REWARD and GameConfig.SEVEN_DAY_LOGIN_REWARD.CoinRewardIcon or ""),
			amountText = formatRewardAmount("Coins", amount),
		}
	end

	local brainrotDefinition = BrainrotConfig.ById[rewardId]
	return {
		name = brainrotDefinition and tostring(brainrotDefinition.Name or "Brainrot") or tostring(type(reward) == "table" and reward.name or "Brainrot"),
		icon = brainrotDefinition and tostring(brainrotDefinition.Icon or "") or tostring(type(reward) == "table" and reward.icon or ""),
		amountText = formatRewardAmount("Brainrot", amount),
	}
end

function SevenDayLoginRewardController:_renderEntry()
	setVisibility(self._entryRedPoint, self._state.hasClaimableReward == true)
end

function SevenDayLoginRewardController:_renderUnlockAllButton()
	local canUnlockAll = self._state.canUnlockAll == true and self._state.productId > 0 and self._isPromptingUnlockAll ~= true
	local interactive = self:_resolveInteractiveNode(self._unlockAllButton)
	if interactive and interactive:IsA("GuiButton") then
		interactive.Active = canUnlockAll
		interactive.AutoButtonColor = canUnlockAll
		interactive.Selectable = canUnlockAll
	end
	if self._unlockAllButton and self._unlockAllButton:IsA("GuiObject") then
		self._unlockAllButton.Active = canUnlockAll
	end
end

function SevenDayLoginRewardController:_renderCountdown(nowTimestamp)
	if not (self._nextRewardLabel and self._nextRewardLabel:IsA("TextLabel")) then
		return
	end

	local now = math.max(0, math.floor(tonumber(nowTimestamp) or os.time()))
	local nextRefreshAt = getNextUtcTimestamp(now)
	local secondsLeft = math.max(0, nextRefreshAt - now)
	local hours = math.floor(secondsLeft / 3600)
	local minutes = math.floor((secondsLeft % 3600) / 60)
	self._nextRewardLabel.Text = string.format("Refresh In:%02d:%02d", hours, minutes)
end

function SevenDayLoginRewardController:_renderRewardFrame(dayIndex)
	local rewardNode = self._rewardNodes[dayIndex]
	if type(rewardNode) ~= "table" then
		return
	end

	local reward = self._state.rewards[dayIndex] or {}
	local rewardDisplay = self:_resolveRewardDisplay(reward, dayIndex)
	local isClaimed = reward.isClaimed == true
	local isClaimable = reward.isClaimable == true
	local isLocked = not isClaimed and not isClaimable

	if rewardNode.nameLabel and rewardNode.nameLabel:IsA("TextLabel") then
		rewardNode.nameLabel.Text = rewardDisplay.name
	end

	if rewardNode.iconLabel and (rewardNode.iconLabel:IsA("ImageLabel") or rewardNode.iconLabel:IsA("ImageButton")) then
		rewardNode.iconLabel.Image = rewardDisplay.icon
	end

	if rewardNode.numLabel and rewardNode.numLabel:IsA("TextLabel") then
		rewardNode.numLabel.Text = rewardDisplay.amountText
	end

	setVisibility(rewardNode.dayNumLabel, isLocked)
	setVisibility(rewardNode.claimButton, isClaimable)
	setVisibility(rewardNode.claimedLabel, isClaimed)
	setVisibility(rewardNode.claimedBg, isClaimed)

	for _, extraNode in ipairs(rewardNode.optionalNodes or {}) do
		setVisibility(extraNode, false)
	end

	local claimInteractive = self:_resolveInteractiveNode(rewardNode.claimButton)
	if claimInteractive and claimInteractive:IsA("GuiButton") then
		claimInteractive.Active = isClaimable
		claimInteractive.AutoButtonColor = isClaimable
		claimInteractive.Selectable = isClaimable
	end
end

function SevenDayLoginRewardController:_renderAll()
	self:_renderEntry()
	self:_renderUnlockAllButton()
	self:_renderCountdown(os.time())
	for dayIndex = 1, #REWARD_FRAME_NAMES do
		self:_renderRewardFrame(dayIndex)
	end
end

function SevenDayLoginRewardController:_applyState(payload)
	if type(payload) ~= "table" then
		return
	end

	local rewards = {}
	if type(payload.rewards) == "table" then
		for _, reward in ipairs(payload.rewards) do
			local dayIndex = math.max(0, math.floor(tonumber(type(reward) == "table" and reward.dayIndex or 0) or 0))
			if dayIndex >= 1 and dayIndex <= #REWARD_FRAME_NAMES then
				rewards[dayIndex] = reward
			end
		end
	end

	self._state.rewards = rewards
	self._state.hasClaimableReward = payload.hasClaimableReward == true
	self._state.shouldAutoOpen = payload.shouldAutoOpen == true
	self._state.canUnlockAll = payload.canUnlockAll == true
	self._state.productId = math.max(0, math.floor(tonumber(payload.productId) or self._state.productId or 0))
	self._state.pendingCycleReset = payload.pendingCycleReset == true
	self._state.nextRefreshAt = math.max(0, math.floor(tonumber(payload.nextRefreshAt) or 0))
	self:_resolvePendingClaimSuccess(rewards)
	self:_renderAll()
	self:_tryAutoOpen()
end

function SevenDayLoginRewardController:_tryAutoOpen()
	if self._hasAutoOpened == true or self._state.shouldAutoOpen ~= true or self._state.hasClaimableReward ~= true then
		return
	end

	if not isLiveInstance(self._root) and not self:_bindUi() then
		return
	end

	self._hasAutoOpened = true
	self._state.shouldAutoOpen = false
	self:OpenSevenDayLoginReward()
end

function SevenDayLoginRewardController:OpenSevenDayLoginReward()
	if not isLiveInstance(self._root) and not self:_bindUi() then
		return
	end

	self:_renderAll()
	self:_requestStateSync("Open", true)
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

function SevenDayLoginRewardController:CloseSevenDayLoginReward()
	if not isLiveInstance(self._root) then
		return
	end

	if self._modalController then
		self._modalController:CloseModal(MODAL_KEY)
	elseif self._root and self._root:IsA("GuiObject") then
		self._root.Visible = false
	end
end

function SevenDayLoginRewardController:_promptUnlockAllPurchase()
	local productId = math.max(0, math.floor(tonumber(self._state.productId) or 0))
	if productId <= 0 or self._isPromptingUnlockAll == true then
		return
	end

	self._activePromptProductId = productId
	self._isPromptingUnlockAll = true
	self:_renderUnlockAllButton()

	local didPrompt, promptError = pcall(function()
		MarketplaceService:PromptProductPurchase(localPlayer, productId)
	end)
	if didPrompt then
		return
	end

	warn(string.format(
		"[SevenDayLoginRewardController] 拉起七日登录奖励一键解锁失败 productId=%d err=%s",
		productId,
		tostring(promptError)
	))
	self._activePromptProductId = 0
	self._isPromptingUnlockAll = false
	self:_renderUnlockAllButton()
end

function SevenDayLoginRewardController:_bindRewardFrame(frame, dayIndex)
	if not frame then
		return nil
	end

	local contentRoot = self:_findDescendantByNames(frame, { "Content" })
	local rewardNode = {
		root = frame,
		dayNumLabel = self:_findDescendantByNames(frame, { "DayNum" }),
		claimButton = self:_findDescendantByNames(frame, { "Claim" }),
		claimedLabel = self:_findDescendantByNames(frame, { "Claimed" }),
		claimedBg = self:_findDescendantByNames(frame, { "Bg" }),
		nameLabel = self:_findDescendantByNames(frame, { "Name" }),
		iconLabel = (contentRoot and self:_findDescendantByNames(contentRoot, { "ItemIcon" })) or self:_findDescendantByNames(frame, { "ItemIcon" }),
		numLabel = (contentRoot and self:_findDescendantByNames(contentRoot, { "Num" })) or self:_findDescendantByNames(frame, { "Num" }),
		optionalNodes = {
			self:_findDescendantByNames(frame, { "Godly" }),
			self:_findDescendantByNames(frame, { "ATK" }),
			self:_findDescendantByNames(frame, { "HP" }),
		},
	}

	local claimInteractive = self:_resolveInteractiveNode(rewardNode.claimButton)
	if claimInteractive then
		table.insert(self._uiConnections, claimInteractive.Activated:Connect(function()
			if self._requestClaimEvent and self._requestClaimEvent:IsA("RemoteEvent") then
				self._pendingClaimDayIndex = dayIndex
				self._pendingClaimDeadline = os.clock() + 5
				self._requestClaimEvent:FireServer({
					dayIndex = dayIndex,
				})
			end
		end))
		self:_bindButtonFx(claimInteractive, {
			ScaleTarget = rewardNode.claimButton,
			HoverScale = 1.05,
			PressScale = 0.94,
		}, self._uiConnections)
	end

	return rewardNode
end

function SevenDayLoginRewardController:_bindUi()
	local mainGui = self:_getMainGui()
	if not mainGui then
		return false
	end

	self._mainGui = mainGui
	self._topRightGui = self:_findDirectChildByName(mainGui, "TopRightGui")
	self._entryRoot = self._topRightGui and self:_findDirectChildByName(self._topRightGui, "SevenDays") or nil
	self._entryRedPoint = self._entryRoot and self:_findDescendantByNames(self._entryRoot, { "RedPoint" }) or nil
	self._openButton = self._entryRoot and self:_resolveInteractiveNode(
		self:_findDescendantByNames(self._entryRoot, { "Button" }) or self._entryRoot
	) or nil
	self._root = self:_findDirectChildByName(mainGui, "Sevendays")
	self._claimSuccessRoot = self:_findClaimSuccessRoot(mainGui, self:_getPlayerGui())
	if not (self._entryRoot and self._root) then
		return false
	end

	local titleRoot = self:_findDescendantByNames(self._root, { "Title" })
	self._closeButton = titleRoot and self:_findDescendantByNames(titleRoot, { "CloseButton" }) or nil
	self._nextRewardLabel = self:_findDescendantByNames(self._root, { "NextReward" })
	self._unlockAllButton = self:_findDescendantByNames(self._root, { "UnlockAll" })
	self._rewardNodes = {}

	disconnectAll(self._uiConnections)

	if self._openButton then
		table.insert(self._uiConnections, self._openButton.Activated:Connect(function()
			self:OpenSevenDayLoginReward()
		end))
		self:_bindButtonFx(self._openButton, {
			ScaleTarget = self._entryRoot or self._openButton,
			HoverScale = 1.05,
			PressScale = 0.94,
		}, self._uiConnections)
	end

	local closeInteractive = self:_resolveInteractiveNode(self._closeButton)
	if closeInteractive then
		table.insert(self._uiConnections, closeInteractive.Activated:Connect(function()
			self:CloseSevenDayLoginReward()
		end))
		self:_bindButtonFx(closeInteractive, {
			ScaleTarget = self._closeButton,
			RotationTarget = self._closeButton,
			HoverScale = 1.12,
			PressScale = 0.92,
			HoverRotation = 20,
		}, self._uiConnections)
	end

	local unlockAllInteractive = self:_resolveInteractiveNode(self._unlockAllButton)
	if unlockAllInteractive then
		table.insert(self._uiConnections, unlockAllInteractive.Activated:Connect(function()
			self:_promptUnlockAllPurchase()
		end))
		self:_bindButtonFx(unlockAllInteractive, {
			ScaleTarget = self._unlockAllButton,
			HoverScale = 1.05,
			PressScale = 0.94,
		}, self._uiConnections)
	end

	for dayIndex, frameName in ipairs(REWARD_FRAME_NAMES) do
		local frame = self:_findDirectChildByName(self._root, frameName)
		self._rewardNodes[dayIndex] = self:_bindRewardFrame(frame, dayIndex)
	end

	if self._root and self._root:IsA("GuiObject") and not self:_isOpen() then
		self._root.Visible = false
	end

	self:_ensureClaimSuccessTipNodes()
	self:_renderAll()
	self:_showNextClaimSuccessTip()
	self:_tryAutoOpen()
	return true
end

function SevenDayLoginRewardController:_startRedPointShakeLoop()
	self._redPointShakeSerial = (tonumber(self._redPointShakeSerial) or 0) + 1
	local shakeSerial = self._redPointShakeSerial
	task.spawn(function()
		while self._started and self._redPointShakeSerial == shakeSerial do
			local redPoint = self._entryRedPoint
			if redPoint and redPoint:IsA("GuiObject") and isLiveInstance(redPoint) and redPoint.Visible == true then
				local baseRotation = redPoint.Rotation
				local offsets = { -10, 10, -6, 6, 0 }
				for _, offset in ipairs(offsets) do
					if not (self._started and self._redPointShakeSerial == shakeSerial and isLiveInstance(redPoint) and redPoint.Visible == true) then
						break
					end
					local tween = TweenService:Create(redPoint, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						Rotation = baseRotation + offset,
					})
					tween:Play()
					tween.Completed:Wait()
				end
				if isLiveInstance(redPoint) then
					redPoint.Rotation = baseRotation
				end
			end
			task.wait(2)
		end
	end)
end

function SevenDayLoginRewardController:_startClockLoop()
	task.spawn(function()
		while self._started do
			local nowTimestamp = os.time()
			self:_renderCountdown(nowTimestamp)
			local utcDay = getUtcDayKey(nowTimestamp)
			if utcDay ~= self._lastObservedUtcDay then
				self._lastObservedUtcDay = utcDay
				self:_requestStateSync("UtcRefresh", false)
			end
			task.wait(1)
		end
	end)
end

function SevenDayLoginRewardController:Start()
	if self._started then
		return
	end

	self._started = true
	self:_bindUi()
	self:_bindRemoteEvents()

	table.insert(self._connections, ReplicatedStorage.DescendantAdded:Connect(function(descendant)
		if not descendant then
			return
		end

		local watchedRemoteNames = {
			[RemoteNames.RootFolder] = true,
			[RemoteNames.SystemEventsFolder] = true,
			[RemoteNames.System.SevenDayLoginRewardStateSync] = true,
			[RemoteNames.System.RequestSevenDayLoginRewardStateSync] = true,
			[RemoteNames.System.RequestSevenDayLoginRewardClaim] = true,
		}
		if watchedRemoteNames[descendant.Name] then
			task.defer(function()
				self:_bindRemoteEvents()
			end)
		end
	end))

	table.insert(self._connections, MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, isPurchased)
		if userId ~= localPlayer.UserId then
			return
		end

		if self._activePromptProductId <= 0 or productId ~= self._activePromptProductId then
			return
		end

		self._activePromptProductId = 0
		self._isPromptingUnlockAll = false
		self:_renderUnlockAllButton()
		if isPurchased then
			task.delay(0.25, function()
				self:_requestStateSync("PurchaseFinished", false)
			end)
		end
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
			local didBindUi = self:_bindUi()
			self:_bindRemoteEvents()
			if didBindUi then
				return
			end
			task.wait(1)
		until os.clock() >= deadline
	end)

	self:_startRedPointShakeLoop()
	self:_startClockLoop()
end

return SevenDayLoginRewardController

