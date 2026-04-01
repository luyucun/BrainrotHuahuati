--[[
脚本名字: GroupRewardController
脚本文件: GroupRewardController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/GroupRewardController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
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
		"[GroupRewardController] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
		moduleName
	))
end

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
	error("[GroupRewardController] 找不到 IndexController，无法复用按钮动效逻辑。")
end

local IndexController = require(indexControllerModule)

local GroupRewardController = {}
GroupRewardController.__index = GroupRewardController

local STARTUP_WARNING_GRACE_SECONDS = 2

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

local function getRewardConfig()
	return GameConfig.GROUP_REWARD or {}
end

function GroupRewardController.new(modalController)
	local self = setmetatable({}, GroupRewardController)
	self._modalController = modalController
	self._started = false
	self._startupWarnAt = 0
	self._rebindQueued = false
	self._persistentConnections = {}
	self._uiConnections = {}
	self._didWarnByKey = {}
	self._stateSyncEvent = nil
	self._requestStateSyncEvent = nil
	self._requestClaimEvent = nil
	self._feedbackEvent = nil
	self._mainGui = nil
	self._topRightGui = nil
	self._entryRoot = nil
	self._openButton = nil
	self._groupRewardRoot = nil
	self._closeButton = nil
	self._claimButton = nil
	self._claimedLabel = nil
	self._rewardTipRoot = nil
	self._rewardTipTitleLabel = nil
	self._rewardTipMessageLabel = nil
	self._rewardTipRootScale = nil
	self._rewardTipCloseButton = nil
	self._rewardTipOptionalNodes = {}
	self._tipQueue = {}
	self._isShowingTip = false
	self._wrongSoundTemplate = nil
	self._didWarnMissingWrongSound = false
	self._state = {
		hasClaimed = false,
		showEntry = true,
	}
	self._indexHelper = IndexController.new(nil)
	return self
end

function GroupRewardController:_warnOnce(key, message)
	if self._didWarnByKey[key] then
		return
	end

	self._didWarnByKey[key] = true
	warn(message)
end

function GroupRewardController:_shouldWarnBindingIssues()
	return os.clock() >= (self._startupWarnAt or 0)
end

function GroupRewardController:_getPlayerGui()
	return localPlayer:FindFirstChild("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
end

function GroupRewardController:_getMainGui()
	local playerGui = self:_getPlayerGui()
	if not playerGui then
		return nil
	end

	local mainGui = playerGui:FindFirstChild("Main")
	if mainGui then
		return mainGui
	end

	return playerGui:FindFirstChild("Main", true)
end

function GroupRewardController:_findDirectChildByName(root, childName)
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

function GroupRewardController:_findDescendantByNames(root, names)
	return self._indexHelper:_findDescendantByNames(root, names)
end

function GroupRewardController:_resolveInteractiveNode(node)
	return self._indexHelper:_resolveInteractiveNode(node)
end

function GroupRewardController:_bindButtonFx(interactiveNode, options, connectionBucket)
	self._indexHelper:_bindButtonFx(interactiveNode, options, connectionBucket)
end

function GroupRewardController:_isGroupRewardModalOpen()
	local modalKey = tostring(getRewardConfig().ModalKey or "GroupReward")
	if self._modalController and self._modalController.IsModalOpen then
		return self._modalController:IsModalOpen(modalKey)
	end

	return isLiveInstance(self._groupRewardRoot) and self._groupRewardRoot.Visible == true
end

function GroupRewardController:_getHiddenNodesForModal()
	local hiddenNodes = {}
	if not self._mainGui then
		return hiddenNodes
	end

	for _, node in ipairs(self._mainGui:GetChildren()) do
		if node and node ~= self._groupRewardRoot and node ~= self._rewardTipRoot then
			table.insert(hiddenNodes, node)
		end
	end

	return hiddenNodes
end

function GroupRewardController:_clearUiBindings()
	disconnectAll(self._uiConnections)
end

function GroupRewardController:_applyStatePayload(payload)
	if type(payload) ~= "table" then
		return
	end

	self._state.hasClaimed = payload.hasClaimed == true
	self._state.showEntry = payload.showEntry ~= false

	self:_renderAll()
end

function GroupRewardController:_renderEntryVisibility()
	local shouldShowEntry = self._state.hasClaimed ~= true and self._state.showEntry == true
	setVisibility(self._entryRoot, shouldShowEntry)

	local redPoint = self._entryRoot and self:_findDescendantByNames(self._entryRoot, { "RedPoint" }) or nil
	setVisibility(redPoint, shouldShowEntry)
end

function GroupRewardController:_renderClaimState()
	local hasClaimed = self._state.hasClaimed == true
	setVisibility(self._claimButton, not hasClaimed)
	setVisibility(self._claimedLabel, hasClaimed)
end

function GroupRewardController:_renderAll()
	self:_renderEntryVisibility()
	self:_renderClaimState()
end

function GroupRewardController:OpenGroupReward()
	if not isLiveInstance(self._groupRewardRoot) and not self:_bindMainUi() then
		return
	end

	self:_renderAll()
	if self._requestStateSyncEvent and self._requestStateSyncEvent:IsA("RemoteEvent") then
		self._requestStateSyncEvent:FireServer()
	end

	local modalKey = tostring(getRewardConfig().ModalKey or "GroupReward")
	if self._modalController then
		if not self:_isGroupRewardModalOpen() then
			self._modalController:OpenModal(modalKey, self._groupRewardRoot, {
				HiddenNodes = self:_getHiddenNodesForModal(),
			})
		end
	elseif self._groupRewardRoot and self._groupRewardRoot:IsA("GuiObject") then
		self._groupRewardRoot.Visible = true
	end
end

function GroupRewardController:CloseGroupReward()
	if not isLiveInstance(self._groupRewardRoot) then
		return
	end

	local modalKey = tostring(getRewardConfig().ModalKey or "GroupReward")
	if self._modalController then
		self._modalController:CloseModal(modalKey)
	elseif self._groupRewardRoot and self._groupRewardRoot:IsA("GuiObject") then
		self._groupRewardRoot.Visible = false
	end
end

function GroupRewardController:_findRewardTipRoot(mainGui, playerGui)
	if mainGui then
		local direct = mainGui:FindFirstChild("RewardClaimTips")
		if direct and direct:IsA("GuiObject") then
			return direct
		end

		local nested = mainGui:FindFirstChild("RewardClaimTips", true)
		if nested and nested:IsA("GuiObject") then
			return nested
		end
	end

	if playerGui then
		local direct = playerGui:FindFirstChild("RewardClaimTips")
		if direct and direct:IsA("GuiObject") then
			return direct
		end

		local nested = playerGui:FindFirstChild("RewardClaimTips", true)
		if nested and nested:IsA("GuiObject") then
			return nested
		end
	end

	return nil
end

function GroupRewardController:_ensureRewardTipNodes()
	if self._rewardTipRoot
		and self._rewardTipRoot.Parent
		and self._rewardTipTitleLabel
		and self._rewardTipTitleLabel.Parent
		and self._rewardTipMessageLabel
		and self._rewardTipMessageLabel.Parent
	then
		return true
	end

	local playerGui = self:_getPlayerGui()
	local mainGui = self._mainGui or self:_getMainGui()
	local rewardTipRoot = self:_findRewardTipRoot(mainGui, playerGui)
	if not rewardTipRoot then
		if self:_shouldWarnBindingIssues() then
			self:_warnOnce("MissingRewardTipRoot", "[GroupRewardController] 找不到 Main/RewardClaimTips，领取提示将被跳过。")
		end
		return false
	end

	local titleRoot = self:_findDescendantByNames(rewardTipRoot, { "Title" })
	local infoRoot = self:_findDescendantByNames(rewardTipRoot, { "Rebirthinfo", "RebirthInfo" }) or rewardTipRoot
	local titleLabel = titleRoot and self:_findDescendantByNames(titleRoot, { "Title" }) or nil
	local messageLabel = self:_findDescendantByNames(infoRoot, { "Warning" })
	if not (titleLabel and titleLabel:IsA("TextLabel")) then
		if self:_shouldWarnBindingIssues() then
			self:_warnOnce("MissingRewardTipTitle", "[GroupRewardController] RewardClaimTips 缺少 Title 文本。")
		end
		return false
	end
	if not (messageLabel and messageLabel:IsA("TextLabel")) then
		if self:_shouldWarnBindingIssues() then
			self:_warnOnce("MissingRewardTipMessage", "[GroupRewardController] RewardClaimTips 缺少 Warning 文本。")
		end
		return false
	end

	self._rewardTipRoot = rewardTipRoot
	self._rewardTipTitleLabel = titleLabel
	self._rewardTipMessageLabel = messageLabel
	self._rewardTipRootScale = ensureUiScale(rewardTipRoot)
	self._rewardTipCloseButton = titleRoot and self:_findDescendantByNames(titleRoot, { "CloseButton" }) or nil
	self._rewardTipOptionalNodes = {
		self:_findDescendantByNames(infoRoot, { "DescribeBg" }),
		self:_findDescendantByNames(infoRoot, { "Title1" }),
		self:_findDescendantByNames(infoRoot, { "RewardBg" }),
		self:_findDescendantByNames(infoRoot, { "Title2" }),
		self:_findDescendantByNames(infoRoot, { "ProgressBg" }),
		self:_findDescendantByNames(infoRoot, { "SpendBg" }),
		self:_findDescendantByNames(infoRoot, { "RebirthBtn" }),
	}

	setVisibility(self._rewardTipRoot, false)
	return true
end

function GroupRewardController:_prepareRewardTipLayout(message, isError)
	if not self:_ensureRewardTipNodes() then
		return false
	end

	self._rewardTipTitleLabel.Text = tostring(getRewardConfig().TipTitleText or "Group Reward")
	self._rewardTipMessageLabel.Text = tostring(message or "")
	self._rewardTipMessageLabel.TextColor3 = isError and Color3.fromRGB(255, 95, 95) or Color3.fromRGB(85, 255, 0)

	local gradient = self:_findDescendantByNames(self._rewardTipMessageLabel, { "FontRed" })
	if gradient and gradient:IsA("UIGradient") then
		gradient.Enabled = isError
	end

	setVisibility(self._rewardTipCloseButton, false)
	for _, node in ipairs(self._rewardTipOptionalNodes) do
		if node and node:IsA("GuiObject") then
			node.Visible = false
		end
	end

	return true
end

function GroupRewardController:_showNextTip()
	if self._isShowingTip then
		return
	end

	if #self._tipQueue <= 0 then
		setVisibility(self._rewardTipRoot, false)
		return
	end

	local nextTip = table.remove(self._tipQueue, 1)
	if type(nextTip) ~= "table" then
		return
	end

	if not self:_prepareRewardTipLayout(nextTip.message, nextTip.isError == true) then
		return
	end

	local root = self._rewardTipRoot
	local uiScale = self._rewardTipRootScale or ensureUiScale(root)
	if not (root and uiScale) then
		return
	end

	self._isShowingTip = true
	local uiConfig = GameConfig.UI or {}
	local openFromScale = tonumber(uiConfig.ModalOpenFromScale) or 0.82
	local overshootScale = tonumber(uiConfig.ModalOpenOvershootScale) or 1.06
	local overshootDuration = tonumber(uiConfig.ModalOpenOvershootDuration) or 0.18
	local settleDuration = tonumber(uiConfig.ModalOpenSettleDuration) or 0.12
	local closeOvershootScale = tonumber(uiConfig.ModalCloseOvershootScale) or 1.04
	local closeOvershootDuration = tonumber(uiConfig.ModalCloseOvershootDuration) or 0.1
	local closeToScale = tonumber(uiConfig.ModalCloseToScale) or 0.78
	local closeShrinkDuration = tonumber(uiConfig.ModalCloseShrinkDuration) or 0.14
	local holdSeconds = math.max(0.2, tonumber(getRewardConfig().TipsDisplaySeconds) or 2)

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
		self._isShowingTip = false
		self:_showNextTip()
	end)
end

function GroupRewardController:_enqueueTip(message, isError)
	local finalMessage = tostring(message or "")
	if finalMessage == "" then
		return
	end

	table.insert(self._tipQueue, {
		message = finalMessage,
		isError = isError == true,
	})
	self:_showNextTip()
end

function GroupRewardController:_getWrongSoundTemplate()
	if self._wrongSoundTemplate and self._wrongSoundTemplate.Parent then
		return self._wrongSoundTemplate
	end

	local soundName = tostring(getRewardConfig().WrongSoundTemplateName or "Wrong")
	local audioRoot = SoundService:FindFirstChild("Audio")
	local wrongSound = audioRoot and (audioRoot:FindFirstChild(soundName) or audioRoot:FindFirstChild(soundName, true)) or nil
	if wrongSound and wrongSound:IsA("Sound") then
		self._wrongSoundTemplate = wrongSound
		return wrongSound
	end

	if not self._didWarnMissingWrongSound then
		warn("[GroupRewardController] 找不到 SoundService/Audio/Wrong，使用回退音频资源。")
		self._didWarnMissingWrongSound = true
	end

	local fallbackSound = SoundService:FindFirstChild("_GroupRewardWrongFallback")
	if fallbackSound and fallbackSound:IsA("Sound") then
		self._wrongSoundTemplate = fallbackSound
		return fallbackSound
	end

	fallbackSound = Instance.new("Sound")
	fallbackSound.Name = "_GroupRewardWrongFallback"
	fallbackSound.SoundId = tostring(getRewardConfig().WrongSoundAssetId or "rbxassetid://118029437877580")
	fallbackSound.Volume = 1
	fallbackSound.Parent = SoundService
	self._wrongSoundTemplate = fallbackSound
	return fallbackSound
end

function GroupRewardController:_playWrongSound()
	local template = self:_getWrongSoundTemplate()
	if not template then
		return
	end

	local soundToPlay = template:Clone()
	soundToPlay.Looped = false
	soundToPlay.Parent = template.Parent or SoundService
	if soundToPlay.SoundId == "" then
		soundToPlay.SoundId = tostring(getRewardConfig().WrongSoundAssetId or "rbxassetid://118029437877580")
	end
	soundToPlay:Play()

	task.delay(3, function()
		if soundToPlay and soundToPlay.Parent then
			soundToPlay:Destroy()
		end
	end)
end

function GroupRewardController:_handleFeedback(payload)
	if type(payload) ~= "table" then
		return
	end

	local status = tostring(payload.status or "")
	local message = tostring(payload.message or "")
	if status == "Success" then
		self:_enqueueTip(message, false)
		return
	end

	if status == "NotInGroup" or status == "CheckFailed" then
		self:_enqueueTip(message, true)
		self:_playWrongSound()
	end
end

function GroupRewardController:_bindMainUi()
	local mainGui = self:_getMainGui()
	if not mainGui then
		if self:_shouldWarnBindingIssues() then
			self:_warnOnce("MissingMain", "[GroupRewardController] 找不到 Main UI，加群领奖面板暂不可用。")
		end
		self:_clearUiBindings()
		return false
	end

	self._mainGui = mainGui
	self._topRightGui = self:_findDirectChildByName(mainGui, "TopRightGui")
	self._entryRoot = self._topRightGui and self:_findDirectChildByName(self._topRightGui, "GroupReward") or nil
	self._openButton = self._entryRoot and self:_resolveInteractiveNode(
		self:_findDescendantByNames(self._entryRoot, { "Button" }) or self._entryRoot
	) or nil
	self._groupRewardRoot = self:_findDirectChildByName(mainGui, "GroupReward")
	self._rewardTipRoot = self:_findRewardTipRoot(mainGui, self:_getPlayerGui())

	if not self._groupRewardRoot then
		if self:_shouldWarnBindingIssues() then
			self:_warnOnce("MissingGroupRewardRoot", "[GroupRewardController] 找不到 Main/GroupReward。")
		end
		self:_clearUiBindings()
		return false
	end

	local titleRoot = self:_findDescendantByNames(self._groupRewardRoot, { "Title" })
	self._closeButton = titleRoot and self:_findDescendantByNames(titleRoot, { "CloseButton" }) or nil
	self._claimButton = self:_findDescendantByNames(self._groupRewardRoot, { "Claim" })
	self._claimedLabel = self:_findDescendantByNames(self._groupRewardRoot, { "Claimed" })

	self:_clearUiBindings()

	if self._openButton then
		table.insert(self._uiConnections, self._openButton.Activated:Connect(function()
			self:OpenGroupReward()
		end))
		self:_bindButtonFx(self._openButton, {
			ScaleTarget = self._entryRoot or self._openButton,
			HoverScale = 1.05,
			PressScale = 0.94,
		}, self._uiConnections)
	else
		if self:_shouldWarnBindingIssues() then
			self:_warnOnce("MissingGroupRewardOpenButton", "[GroupRewardController] 找不到 Main/TopRightGui/GroupReward/Button。")
		end
	end

	local closeInteractive = self:_resolveInteractiveNode(self._closeButton)
	if closeInteractive then
		table.insert(self._uiConnections, closeInteractive.Activated:Connect(function()
			self:CloseGroupReward()
		end))
		self:_bindButtonFx(closeInteractive, {
			ScaleTarget = self._closeButton,
			RotationTarget = self._closeButton,
			HoverScale = 1.12,
			PressScale = 0.92,
			HoverRotation = 20,
		}, self._uiConnections)
	else
		if self:_shouldWarnBindingIssues() then
			self:_warnOnce("MissingGroupRewardCloseButton", "[GroupRewardController] 找不到 Main/GroupReward/Title/CloseButton。")
		end
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
	else
		if self:_shouldWarnBindingIssues() then
			self:_warnOnce("MissingGroupRewardClaimButton", "[GroupRewardController] 找不到 Main/GroupReward/Claim。")
		end
	end

	self:_ensureRewardTipNodes()
	self:_renderAll()
	return true
end

function GroupRewardController:_queueRebind()
	if self._rebindQueued then
		return
	end

	self._rebindQueued = true
	task.defer(function()
		self._rebindQueued = false
		self:_bindMainUi()
	end)
end

function GroupRewardController:_scheduleRetryBind()
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

function GroupRewardController:Start()
	if self._started then
		return
	end

	self._started = true
	self._startupWarnAt = os.clock() + STARTUP_WARNING_GRACE_SECONDS

	local eventsRoot = ReplicatedStorage:WaitForChild(RemoteNames.RootFolder)
	local systemEvents = eventsRoot:WaitForChild(RemoteNames.SystemEventsFolder)
	self._stateSyncEvent = systemEvents:FindFirstChild(RemoteNames.System.GroupRewardStateSync)
		or systemEvents:WaitForChild(RemoteNames.System.GroupRewardStateSync, 10)
	self._requestStateSyncEvent = systemEvents:FindFirstChild(RemoteNames.System.RequestGroupRewardStateSync)
		or systemEvents:WaitForChild(RemoteNames.System.RequestGroupRewardStateSync, 10)
	self._requestClaimEvent = systemEvents:FindFirstChild(RemoteNames.System.RequestGroupRewardClaim)
		or systemEvents:WaitForChild(RemoteNames.System.RequestGroupRewardClaim, 10)
	self._feedbackEvent = systemEvents:FindFirstChild(RemoteNames.System.GroupRewardFeedback)
		or systemEvents:WaitForChild(RemoteNames.System.GroupRewardFeedback, 10)

	if self._stateSyncEvent and self._stateSyncEvent:IsA("RemoteEvent") then
		table.insert(self._persistentConnections, self._stateSyncEvent.OnClientEvent:Connect(function(payload)
			self:_applyStatePayload(payload)
		end))
	else
		self:_warnOnce("MissingGroupRewardStateSync", "[GroupRewardController] 找不到 GroupRewardStateSync，领奖状态不会自动同步。")
	end

	if self._feedbackEvent and self._feedbackEvent:IsA("RemoteEvent") then
		table.insert(self._persistentConnections, self._feedbackEvent.OnClientEvent:Connect(function(payload)
			self:_handleFeedback(payload)
		end))
	else
		self:_warnOnce("MissingGroupRewardFeedback", "[GroupRewardController] 找不到 GroupRewardFeedback，领取提示不会自动播放。")
	end

	local playerGui = self:_getPlayerGui()
	if playerGui then
		table.insert(self._persistentConnections, playerGui.DescendantAdded:Connect(function(descendant)
			local watchedNames = {
				Main = true,
				TopRightGui = true,
				GroupReward = true,
				Button = true,
				Title = true,
				CloseButton = true,
				Claim = true,
				Claimed = true,
				RewardClaimTips = true,
			}
			if watchedNames[descendant.Name] then
				self:_queueRebind()
			end
		end))
	end

	table.insert(self._persistentConnections, localPlayer.CharacterAdded:Connect(function()
		task.defer(function()
			self:_queueRebind()
		end)
	end))

	self:_scheduleRetryBind()

	if self._requestStateSyncEvent and self._requestStateSyncEvent:IsA("RemoteEvent") then
		self._requestStateSyncEvent:FireServer()
	end
end

return GroupRewardController


