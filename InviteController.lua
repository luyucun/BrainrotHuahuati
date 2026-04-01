--[[
脚本名字: InviteController
脚本文件: InviteController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/InviteController
]]

local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")

local localPlayer = Players.LocalPlayer

local InviteController = {}
InviteController.__index = InviteController

function InviteController.new()
	local self = setmetatable({}, InviteController)
	self._inviteButton = nil
	self._inviteButtonConnection = nil
	self._playerGuiConnection = nil
	self._warnedKeys = {}
	self._isPromptBusy = false
	return self
end

function InviteController:_warnOnce(key, message)
	if self._warnedKeys[key] then
		return
	end

	self._warnedKeys[key] = true
	warn(message)
end

function InviteController:_getPlayerGui()
	return localPlayer:FindFirstChild("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
end

function InviteController:_getTopRightRoot()
	local playerGui = self:_getPlayerGui()
	if not playerGui then
		return nil
	end

	local mainGui = playerGui:FindFirstChild("Main")
	if not mainGui then
		return nil
	end

	return mainGui:FindFirstChild("TopRightGui") or mainGui:FindFirstChild("TopRightGui", true)
end

function InviteController:_promptInvite()
	if self._isPromptBusy then
		return
	end

	self._isPromptBusy = true
	task.spawn(function()
		local okCanSend, canSend = pcall(function()
			return SocialService:CanSendGameInviteAsync(localPlayer)
		end)

		if okCanSend and canSend ~= true then
			self._isPromptBusy = false
			return
		end

		local okPrompt, promptError = pcall(function()
			SocialService:PromptGameInvite(localPlayer)
		end)
		if not okPrompt then
			warn(string.format("[InviteController] 打开系统邀请界面失败: %s", tostring(promptError)))
		end

		self._isPromptBusy = false
	end)
end

function InviteController:_bindInviteButton()
	local topRightRoot = self:_getTopRightRoot()
	if not topRightRoot then
		self:_warnOnce("TopRightGui", "[InviteController] 找不到 Main/TopRightGui，邀请按钮暂不可用。")
		return false
	end

	local inviteRoot = topRightRoot:FindFirstChild("Invite") or topRightRoot:FindFirstChild("Invite", true)
	if not inviteRoot then
		self:_warnOnce("Invite", "[InviteController] 找不到 Main/TopRightGui/Invite，邀请按钮暂不可用。")
		return false
	end

	local inviteButton = nil
	if inviteRoot:IsA("GuiButton") then
		inviteButton = inviteRoot
	else
		inviteButton = inviteRoot:FindFirstChild("Button") or inviteRoot:FindFirstChild("Button", true)
		if not (inviteButton and inviteButton:IsA("GuiButton")) then
			inviteButton = inviteRoot:FindFirstChildWhichIsA("GuiButton", true)
		end
	end

	if not inviteButton then
		self:_warnOnce("InviteButton", "[InviteController] 找不到 Main/TopRightGui/Invite/Button，邀请按钮暂不可用。")
		return false
	end

	if not inviteButton:IsA("GuiButton") then
		self:_warnOnce("InviteType", string.format(
			"[InviteController] Invite/Button 节点不是 GuiButton: %s (%s)",
			inviteButton:GetFullName(),
			inviteButton.ClassName
		))
		return false
	end

	if self._inviteButton == inviteButton and self._inviteButtonConnection then
		return true
	end

	if self._inviteButtonConnection then
		self._inviteButtonConnection:Disconnect()
		self._inviteButtonConnection = nil
	end

	self._inviteButton = inviteButton
	self._inviteButtonConnection = inviteButton.Activated:Connect(function()
		self:_promptInvite()
	end)

	return true
end

function InviteController:_scheduleRebind()
	task.spawn(function()
		local deadline = os.clock() + 12
		repeat
			if self:_bindInviteButton() then
				return
			end

			task.wait(1)
		until os.clock() >= deadline
	end)
end

function InviteController:Start()
	self:_scheduleRebind()

	local playerGui = self:_getPlayerGui()
	if playerGui then
		self._playerGuiConnection = playerGui.DescendantAdded:Connect(function(descendant)
			if descendant.Name == "Main" or descendant.Name == "TopRightGui" or descendant.Name == "Invite" or descendant.Name == "Button" then
				task.defer(function()
					self:_bindInviteButton()
				end)
			end
		end)
	end

	localPlayer.CharacterAdded:Connect(function()
		task.defer(function()
			self:_scheduleRebind()
		end)
	end)
end

return InviteController