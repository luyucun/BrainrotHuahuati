--[[
脚本名字: CoinDisplayController
脚本文件: CoinDisplayController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/CoinDisplayController
]]

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
		"[CoinDisplayController] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
		moduleName
	))
end

local FormatUtil = requireSharedModule("FormatUtil")
local RemoteNames = requireSharedModule("RemoteNames")

local eventsRoot = ReplicatedStorage:WaitForChild(RemoteNames.RootFolder)
local currencyEventsFolder = eventsRoot:WaitForChild(RemoteNames.CurrencyEventsFolder)
local coinChangedEvent = currencyEventsFolder:WaitForChild(RemoteNames.Currency.CoinChanged)
local requestCoinSyncEvent = currencyEventsFolder:WaitForChild(RemoteNames.Currency.RequestCoinSync)

local CoinDisplayController = {}
CoinDisplayController.__index = CoinDisplayController

local WATCHED_UI_NAMES = {
	Main = true,
	Cash = true,
	CoinNum = true,
	CoinAdd = true,
}

function CoinDisplayController.new()
	local self = setmetatable({}, CoinDisplayController)
	self._coinNumLabel = nil
	self._coinAddTemplate = nil
	self._coinNumScale = nil
	self._displayValue = 0
	self._activePopups = {}
	self._rollNumberValue = nil
	self._didWarnMissingUi = {}
	self._playerGuiDescendantAddedConnection = nil
	self._startupWarnAt = os.clock() + 14
	return self
end

function CoinDisplayController:_warnMissingUiOnce(key, message)
	if self._didWarnMissingUi[key] then
		return
	end

	if os.clock() < (tonumber(self._startupWarnAt) or 0) then
		return
	end

	self._didWarnMissingUi[key] = true
	warn(message)
end

local function getPlayerGui()
	return localPlayer:FindFirstChildOfClass("PlayerGui")
		or localPlayer:FindFirstChild("PlayerGui")
		or localPlayer:WaitForChild("PlayerGui", 5)
end

local function findMainGui(playerGui)
	if not playerGui then
		return nil
	end

	local mainGui = playerGui:FindFirstChild("Main") or playerGui:FindFirstChild("Main", true)
	if mainGui then
		return mainGui
	end

	return playerGui:WaitForChild("Main", 5)
end

local function getCashUiNodes(controller)
	local playerGui = getPlayerGui()
	if not playerGui then
		controller:_warnMissingUiOnce("PlayerGui", "[CoinDisplayController] 找不到 PlayerGui，金币 UI 同步已跳过。")
		return nil, nil
	end

	local mainGui = findMainGui(playerGui)
	if not (mainGui and mainGui:IsA("LayerCollector")) then
		controller:_warnMissingUiOnce("Main", "[CoinDisplayController] 找不到 Main UI，金币 UI 同步已跳过。")
		return nil, nil
	end

	local cashFrame = mainGui:FindFirstChild("Cash") or mainGui:FindFirstChild("Cash", true) or mainGui:WaitForChild("Cash", 5)
	if not cashFrame then
		controller:_warnMissingUiOnce("Cash", "[CoinDisplayController] 找不到 Cash UI，金币 UI 同步已跳过。")
		return nil, nil
	end

	local coinNum = cashFrame:FindFirstChild("CoinNum") or cashFrame:FindFirstChild("CoinNum", true) or cashFrame:WaitForChild("CoinNum", 5)
	if not (coinNum and coinNum:IsA("TextLabel")) then
		controller:_warnMissingUiOnce("CoinNum", "[CoinDisplayController] 找不到 Cash/CoinNum 文本标签。")
		return nil, nil
	end

	local coinAdd = cashFrame:FindFirstChild("CoinAdd") or cashFrame:FindFirstChild("CoinAdd", true) or cashFrame:WaitForChild("CoinAdd", 5)
	if not (coinAdd and coinAdd:IsA("TextLabel")) then
		controller:_warnMissingUiOnce("CoinAdd", "[CoinDisplayController] 找不到 Cash/CoinAdd 文本标签。")
		return nil, nil
	end

	return coinNum, coinAdd
end

function CoinDisplayController:_setCoinNumText(value)
	if not (self._coinNumLabel and self._coinNumLabel.Parent) then
		return
	end

	self._coinNumLabel.Text = FormatUtil.FormatWithCommasCeil(value)
end

function CoinDisplayController:_ensureUiNodes()
	if self._coinNumLabel and self._coinNumLabel.Parent and self._coinAddTemplate and self._coinAddTemplate.Parent then
		return true
	end

	local coinNumLabel, coinAddTemplate = getCashUiNodes(self)
	if not (coinNumLabel and coinAddTemplate) then
		return false
	end

	self._coinNumLabel = coinNumLabel
	self._coinAddTemplate = coinAddTemplate
	self._coinAddTemplate.Visible = false
	self._coinAddTemplate.TextTransparency = 0

	self._coinNumScale = self._coinNumLabel:FindFirstChildOfClass("UIScale")
	if not self._coinNumScale then
		self._coinNumScale = Instance.new("UIScale")
		self._coinNumScale.Parent = self._coinNumLabel
	end
	self._coinNumScale.Scale = 1

	self:_setCoinNumText(self._displayValue)
	return true
end

function CoinDisplayController:_bindGuiObservers()
	if self._playerGuiDescendantAddedConnection then
		return
	end

	local playerGui = getPlayerGui()
	if not playerGui then
		return
	end

	self._playerGuiDescendantAddedConnection = playerGui.DescendantAdded:Connect(function(descendant)
		if not descendant or not WATCHED_UI_NAMES[descendant.Name] then
			return
		end

		task.defer(function()
			if self:_ensureUiNodes() then
				self:_setCoinNumText(self._displayValue)
			end
		end)
	end)
end

function CoinDisplayController:_scheduleRetryEnsureUi()
	task.spawn(function()
		local deadline = os.clock() + 12
		repeat
			if self:_ensureUiNodes() then
				return
			end

			task.wait(1)
		until os.clock() >= deadline
	end)
end

function CoinDisplayController:_cleanupRollValue()
	if self._rollNumberValue then
		self._rollNumberValue:Destroy()
		self._rollNumberValue = nil
	end
end

function CoinDisplayController:_animateRoll(targetValue)
	local startValue = self._displayValue
	self:_cleanupRollValue()

	local numberValue = Instance.new("NumberValue")
	numberValue.Value = startValue
	self._rollNumberValue = numberValue

	local valueChangedConnection
	valueChangedConnection = numberValue:GetPropertyChangedSignal("Value"):Connect(function()
		local rounded = FormatUtil.CeilNonNegative(numberValue.Value)
		self._displayValue = rounded
		self:_setCoinNumText(rounded)
	end)

	local tween = TweenService:Create(numberValue, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Value = targetValue,
	})

	tween.Completed:Connect(function()
		if valueChangedConnection then
			valueChangedConnection:Disconnect()
		end

		if self._rollNumberValue == numberValue then
			self._rollNumberValue = nil
		end

		numberValue:Destroy()
		self._displayValue = targetValue
		self:_setCoinNumText(targetValue)
	end)

	tween:Play()
end

function CoinDisplayController:_pulseCoinNum()
	if not (self._coinNumScale and self._coinNumScale.Parent) then
		return
	end

	task.spawn(function()
		for _ = 1, 2 do
			local growTween = TweenService:Create(self._coinNumScale, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Scale = 1.08,
			})
			local shrinkTween = TweenService:Create(self._coinNumScale, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Scale = 1,
			})

			growTween:Play()
			growTween.Completed:Wait()
			shrinkTween:Play()
			shrinkTween.Completed:Wait()
		end
	end)
end

function CoinDisplayController:_pushExistingPopupsUp()
	for _, popup in ipairs(self._activePopups) do
		if popup and popup.Parent then
			local current = popup.Position
			local target = UDim2.new(current.X.Scale, current.X.Offset, current.Y.Scale, current.Y.Offset - 18)
			local tween = TweenService:Create(popup, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = target,
			})
			tween:Play()
		end
	end
end

function CoinDisplayController:_removePopup(popup)
	for index, activePopup in ipairs(self._activePopups) do
		if activePopup == popup then
			table.remove(self._activePopups, index)
			break
		end
	end
end

function CoinDisplayController:_spawnCoinAdd(delta)
	if delta == 0 or not (self._coinAddTemplate and self._coinAddTemplate.Parent) then
		return
	end

	self:_pushExistingPopupsUp()

	local popup = self._coinAddTemplate:Clone()
	popup.Name = "CoinAddPopup"
	popup.Visible = true
	popup.TextTransparency = 0
	popup.TextStrokeTransparency = 0
	popup.BackgroundTransparency = self._coinAddTemplate.BackgroundTransparency
	popup.Text = string.format("%s$%s", delta >= 0 and "+" or "-", FormatUtil.FormatWithCommasCeil(math.abs(delta)))
	popup.Parent = self._coinAddTemplate.Parent

	local finalPosition = self._coinAddTemplate.Position
	popup.Position = UDim2.new(finalPosition.X.Scale, finalPosition.X.Offset - 18, finalPosition.Y.Scale, finalPosition.Y.Offset + 14)

	table.insert(self._activePopups, popup)

	local popTween = TweenService:Create(popup, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = finalPosition,
	})

	popTween.Completed:Connect(function()
		local fadeTweenInfo = TweenInfo.new(0.6, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)

		local textFadeTween = TweenService:Create(popup, fadeTweenInfo, {
			TextTransparency = 1,
			BackgroundTransparency = 1,
		})

		local strokeFadeTween = TweenService:Create(popup, fadeTweenInfo, {
			TextStrokeTransparency = 1,
		})

		for _, descendant in ipairs(popup:GetDescendants()) do
			if descendant:IsA("UIStroke") then
				TweenService:Create(descendant, fadeTweenInfo, {
					Transparency = 1,
				}):Play()
			end
		end

		textFadeTween.Completed:Connect(function()
			self:_removePopup(popup)
			popup.Visible = false
			popup:Destroy()
		end)

		strokeFadeTween:Play()
		textFadeTween:Play()
	end)

	popTween:Play()
end

function CoinDisplayController:_onCoinChanged(payload)
	if type(payload) ~= "table" then
		return
	end

	local total = FormatUtil.CeilNonNegative(payload.total)
	local delta = tonumber(payload.delta) or 0
	local hasUi = self:_ensureUiNodes()

	if delta == 0 and self._displayValue == 0 then
		self._displayValue = total
		if hasUi then
			self:_setCoinNumText(total)
		end
		return
	end

	if not hasUi then
		self._displayValue = total
		return
	end

	self:_animateRoll(total)

	if delta ~= 0 then
		self:_pulseCoinNum()
		self:_spawnCoinAdd(delta)
	end
end

function CoinDisplayController:Start()
	self:_bindGuiObservers()
	if not self:_ensureUiNodes() then
		self:_scheduleRetryEnsureUi()
	end

	coinChangedEvent.OnClientEvent:Connect(function(payload)
		self:_onCoinChanged(payload)
	end)

	localPlayer.CharacterAdded:Connect(function()
		task.defer(function()
			if self:_ensureUiNodes() then
				self:_setCoinNumText(self._displayValue)
			else
				self:_scheduleRetryEnsureUi()
			end
		end)
	end)

	requestCoinSyncEvent:FireServer()
end

return CoinDisplayController
