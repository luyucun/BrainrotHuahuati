--[[
脚本名字: CoinDisplayController
脚本文件: CoinDisplayController.lua
脚本类型: ModuleScript
本地路径: D:/RobloxGame/BrainrotsTemplate/CoinDisplayController.lua
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

function CoinDisplayController.new()
	local self = setmetatable({}, CoinDisplayController)
	self._coinNumLabel = nil
	self._coinAddTemplate = nil
	self._coinNumScale = nil
	self._displayValue = 0
	self._activePopups = {}
	self._rollNumberValue = nil
	return self
end

local function getCashUiNodes()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local mainGui = playerGui:WaitForChild("Main")
	local cashFrame = mainGui:WaitForChild("Cash")
	local coinNum = cashFrame:WaitForChild("CoinNum")
	local coinAdd = cashFrame:WaitForChild("CoinAdd")
	return coinNum, coinAdd
end

function CoinDisplayController:_setCoinNumText(value)
	self._coinNumLabel.Text = FormatUtil.FormatWithCommas(value)
end

function CoinDisplayController:_ensureUiNodes()
	if self._coinNumLabel and self._coinNumLabel.Parent and self._coinAddTemplate and self._coinAddTemplate.Parent then
		return
	end

	self._coinNumLabel, self._coinAddTemplate = getCashUiNodes()
	self._coinAddTemplate.Visible = false
	self._coinAddTemplate.TextTransparency = 0

	self._coinNumScale = self._coinNumLabel:FindFirstChildOfClass("UIScale")
	if not self._coinNumScale then
		self._coinNumScale = Instance.new("UIScale")
		self._coinNumScale.Parent = self._coinNumLabel
	end
	self._coinNumScale.Scale = 1

	self:_setCoinNumText(self._displayValue)
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
		local rounded = math.floor(numberValue.Value + 0.5)
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
	if delta == 0 then
		return
	end

	self:_pushExistingPopupsUp()

	local popup = self._coinAddTemplate:Clone()
	popup.Name = "CoinAddPopup"
	popup.Visible = true
	popup.TextTransparency = 0
	popup.TextStrokeTransparency = 0
	popup.BackgroundTransparency = self._coinAddTemplate.BackgroundTransparency
	popup.Text = string.format("%s$%s", delta >= 0 and "+" or "-", FormatUtil.FormatWithCommas(math.abs(delta), 1))
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
	self:_ensureUiNodes()

	if type(payload) ~= "table" then
		return
	end

	local total = FormatUtil.CeilNonNegative(payload.total)
	local delta = tonumber(payload.delta) or 0

	if delta == 0 and self._displayValue == 0 then
		self._displayValue = total
		self:_setCoinNumText(total)
		return
	end

	self:_animateRoll(total)

	if delta ~= 0 then
		self:_pulseCoinNum()
		self:_spawnCoinAdd(delta)
	end
end

function CoinDisplayController:Start()
	self:_ensureUiNodes()

	coinChangedEvent.OnClientEvent:Connect(function(payload)
		self:_onCoinChanged(payload)
	end)

	localPlayer.CharacterAdded:Connect(function()
		task.defer(function()
			self:_ensureUiNodes()
			self:_setCoinNumText(self._displayValue)
		end)
	end)

	requestCoinSyncEvent:FireServer()
end

return CoinDisplayController


