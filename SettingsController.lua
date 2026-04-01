--[[
脚本名字: SettingsController
脚本文件: SettingsController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/SettingsController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

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
		"[SettingsController] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
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
	error("[SettingsController] 找不到 IndexController，无法复用按钮动效逻辑。")
end

local IndexController = require(indexControllerModule)

local SettingsController = {}
SettingsController.__index = SettingsController

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

local function buildGradient(startColor, endColor)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, startColor),
		ColorSequenceKeypoint.new(1, endColor),
	})
end

function SettingsController.new(modalController)
	local self = setmetatable({}, SettingsController)
	local settingsConfig = GameConfig.SETTINGS or {}

	self._modalController = modalController
	self._started = false
	self._startupWarnAt = 0
	self._rebindQueued = false
	self._persistentConnections = {}
	self._uiConnections = {}
	self._soundStatesBySound = {}
	self._didWarnByKey = {}
	self._stateSyncEvent = nil
	self._requestStateSyncEvent = nil
	self._requestUpdateEvent = nil
	self._mainGui = nil
	self._optionRoot = nil
	self._openButtonRoot = nil
	self._openButton = nil
	self._closeButton = nil
	self._musicRoot = nil
	self._musicToggleRoot = nil
	self._musicToggleButton = nil
	self._musicTextLabel = nil
	self._musicGradient = nil
	self._sfxRoot = nil
	self._sfxToggleRoot = nil
	self._sfxToggleButton = nil
	self._sfxTextLabel = nil
	self._sfxGradient = nil
	self._musicEnabled = settingsConfig.DefaultMusicEnabled ~= false
	self._sfxEnabled = settingsConfig.DefaultSfxEnabled ~= false
	self._modalKey = tostring(settingsConfig.ModalKey or "Option")
	self._indexHelper = IndexController.new(nil)
	return self
end

function SettingsController:_warnOnce(key, message)
	if self._didWarnByKey[key] then
		return
	end

	self._didWarnByKey[key] = true
	warn(message)
end

function SettingsController:_shouldWarnBindingIssues()
	return os.clock() >= (self._startupWarnAt or 0)
end

function SettingsController:_getPlayerGui()
	return localPlayer:FindFirstChild("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
end

function SettingsController:_getMainGui()
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

function SettingsController:_findDirectChildByName(root, childName)
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

function SettingsController:_findDescendantByNames(root, names)
	return self._indexHelper:_findDescendantByNames(root, names)
end

function SettingsController:_resolveInteractiveNode(node)
	return self._indexHelper:_resolveInteractiveNode(node)
end

function SettingsController:_bindButtonFx(interactiveNode, options, connectionBucket)
	self._indexHelper:_bindButtonFx(interactiveNode, options, connectionBucket)
end

function SettingsController:_isOptionModalOpen()
	if self._modalController and self._modalController.IsModalOpen then
		return self._modalController:IsModalOpen(self._modalKey)
	end

	return isLiveInstance(self._optionRoot) and self._optionRoot.Visible == true
end

function SettingsController:_getHiddenNodesForModal()
	local hiddenNodes = {}
	if not self._mainGui then
		return hiddenNodes
	end

	for _, node in ipairs(self._mainGui:GetChildren()) do
		if node and node ~= self._optionRoot then
			table.insert(hiddenNodes, node)
		end
	end

	return hiddenNodes
end

function SettingsController:_applyToggleVisuals(toggleRoot, textLabel, gradient, isEnabled)
	local settingsConfig = GameConfig.SETTINGS or {}
	local textValue = isEnabled and tostring(settingsConfig.ToggleOnText or "On") or tostring(settingsConfig.ToggleOffText or "Off")
	local gradientStartColor = isEnabled and (settingsConfig.ToggleOnStartColor or Color3.fromRGB(85, 255, 0))
		or (settingsConfig.ToggleOffStartColor or Color3.fromRGB(203, 0, 14))
	local gradientEndColor = isEnabled and (settingsConfig.ToggleOnEndColor or Color3.fromRGB(255, 255, 0))
		or (settingsConfig.ToggleOffEndColor or Color3.fromRGB(255, 93, 53))

	if textLabel and textLabel:IsA("TextLabel") then
		textLabel.Text = textValue
	end

	if toggleRoot and toggleRoot:IsA("TextButton") then
		toggleRoot.Text = textValue
	end

	if gradient and gradient:IsA("UIGradient") then
		gradient.Color = buildGradient(gradientStartColor, gradientEndColor)
	end
end

function SettingsController:_renderSettingsUi()
	self:_applyToggleVisuals(self._musicToggleRoot, self._musicTextLabel, self._musicGradient, self._musicEnabled)
	self:_applyToggleVisuals(self._sfxToggleRoot, self._sfxTextLabel, self._sfxGradient, self._sfxEnabled)
end

function SettingsController:_getSoundCategory(sound)
	if not (sound and sound:IsA("Sound")) then
		return nil
	end

	local settingsConfig = GameConfig.SETTINGS or {}
	local categoryAttributeName = tostring(settingsConfig.CategoryAttributeName or "")
	if categoryAttributeName ~= "" then
		local categoryValue = tostring(sound:GetAttribute(categoryAttributeName) or "")
		local musicCategoryValue = tostring(settingsConfig.MusicCategoryValue or "Music")
		local sfxCategoryValue = tostring(settingsConfig.SfxCategoryValue or "Sfx")
		if categoryValue == musicCategoryValue then
			return "Music"
		end
		if categoryValue == sfxCategoryValue then
			return "Sfx"
		end
	end

	local musicFolderName = tostring(settingsConfig.MusicFolderName or "BGM")
	local musicFolder = SoundService:FindFirstChild(musicFolderName)
	if musicFolder and sound:IsDescendantOf(musicFolder) then
		return "Music"
	end

	return "Sfx"
end

function SettingsController:_setManagedSoundVolume(soundState, targetVolume)
	local sound = soundState and soundState.Sound
	if not isLiveInstance(sound) then
		return
	end

	soundState.IsApplyingVolume = true
	sound.Volume = math.max(0, tonumber(targetVolume) or 0)
	soundState.IsApplyingVolume = false
end

function SettingsController:_applySoundPreferenceToSound(soundState)
	local sound = soundState and soundState.Sound
	if not isLiveInstance(sound) then
		return
	end

	local category = self:_getSoundCategory(sound)
	if category == "Music" then
		if self._musicEnabled then
			self:_setManagedSoundVolume(soundState, soundState.BaseVolume)
			if soundState.ShouldResumeMusic then
				soundState.ShouldResumeMusic = false
				if not sound.IsPlaying then
					task.defer(function()
						if isLiveInstance(sound) then
							pcall(function()
								sound:Play()
							end)
						end
					end)
				end
			end
		else
			if sound.IsPlaying then
				soundState.ShouldResumeMusic = true
			end
			self:_setManagedSoundVolume(soundState, 0)
			if sound.IsPlaying then
				pcall(function()
					sound:Stop()
				end)
			end
		end
		return
	end

	if self._sfxEnabled then
		self:_setManagedSoundVolume(soundState, soundState.BaseVolume)
		return
	end

	self:_setManagedSoundVolume(soundState, 0)
	if sound.Looped and sound.IsPlaying then
		pcall(function()
			sound:Stop()
		end)
	end
end

function SettingsController:_applySoundPreferences()
	for _, soundState in pairs(self._soundStatesBySound) do
		self:_applySoundPreferenceToSound(soundState)
	end
end

function SettingsController:_untrackSound(sound)
	local soundState = self._soundStatesBySound[sound]
	if not soundState then
		return
	end

	if soundState.VolumeChangedConnection then
		soundState.VolumeChangedConnection:Disconnect()
		soundState.VolumeChangedConnection = nil
	end

	if soundState.AncestryChangedConnection then
		soundState.AncestryChangedConnection:Disconnect()
		soundState.AncestryChangedConnection = nil
	end

	if soundState.PlayingChangedConnection then
		soundState.PlayingChangedConnection:Disconnect()
		soundState.PlayingChangedConnection = nil
	end

	self._soundStatesBySound[sound] = nil
end

function SettingsController:_trackSound(sound)
	if not (sound and sound:IsA("Sound")) then
		return
	end

	local soundState = self._soundStatesBySound[sound]
	if soundState then
		self:_applySoundPreferenceToSound(soundState)
		return
	end

	soundState = {
		Sound = sound,
		BaseVolume = math.max(0, tonumber(sound.Volume) or 0),
		IsApplyingVolume = false,
		ShouldResumeMusic = false,
		VolumeChangedConnection = nil,
		AncestryChangedConnection = nil,
		PlayingChangedConnection = nil,
	}
	self._soundStatesBySound[sound] = soundState

	soundState.VolumeChangedConnection = sound:GetPropertyChangedSignal("Volume"):Connect(function()
		if soundState.IsApplyingVolume then
			return
		end

		soundState.BaseVolume = math.max(0, tonumber(sound.Volume) or 0)
		local category = self:_getSoundCategory(sound)
		if (category == "Music" and not self._musicEnabled) or (category ~= "Music" and not self._sfxEnabled) then
			self:_setManagedSoundVolume(soundState, 0)
		end
	end)

	soundState.AncestryChangedConnection = sound.AncestryChanged:Connect(function()
		if not isLiveInstance(sound) then
			self:_untrackSound(sound)
			return
		end

		self:_applySoundPreferenceToSound(soundState)
	end)

	local okPlayingSignal, playingSignal = pcall(function()
		return sound:GetPropertyChangedSignal("IsPlaying")
	end)
	if okPlayingSignal and playingSignal then
		soundState.PlayingChangedConnection = playingSignal:Connect(function()
			local category = self:_getSoundCategory(sound)
			if category == "Music" and not self._musicEnabled and sound.IsPlaying then
				soundState.ShouldResumeMusic = true
				self:_setManagedSoundVolume(soundState, 0)
				pcall(function()
					sound:Stop()
				end)
				return
			end

			if category ~= "Music" and not self._sfxEnabled and sound.Looped and sound.IsPlaying then
				self:_setManagedSoundVolume(soundState, 0)
				pcall(function()
					sound:Stop()
				end)
			end
		end)
	end

	self:_applySoundPreferenceToSound(soundState)
end

function SettingsController:_trackExistingSounds()
	for _, descendant in ipairs(game:GetDescendants()) do
		if descendant:IsA("Sound") then
			self:_trackSound(descendant)
		end
	end
end

function SettingsController:_clearUiBindings()
	disconnectAll(self._uiConnections)
end

function SettingsController:_bindMainUi()
	local mainGui = self:_getMainGui()
	if not mainGui then
		if self:_shouldWarnBindingIssues() then
			self:_warnOnce("MissingMain", "[SettingsController] 找不到 Main UI，设置面板暂不可用。")
		end
		self:_clearUiBindings()
		return false
	end

	self._mainGui = mainGui
	self._optionRoot = self:_findDirectChildByName(mainGui, "Option")

	local topRightGui = self:_findDirectChildByName(mainGui, "TopRightGui")
	local optionsRoot = topRightGui and self:_findDirectChildByName(topRightGui, "Options") or nil
	self._openButtonRoot = optionsRoot
	self._openButton = optionsRoot and self:_resolveInteractiveNode(
		self:_findDescendantByNames(optionsRoot, { "Button" }) or optionsRoot
	) or nil

	if not self._optionRoot then
		if self:_shouldWarnBindingIssues() then
			self:_warnOnce("MissingOptionRoot", "[SettingsController] 找不到 Main/Option，设置面板未启动。")
		end
		self:_clearUiBindings()
		return false
	end

	local titleRoot = self:_findDirectChildByName(self._optionRoot, "Title")
	self._closeButton = titleRoot and self:_findDescendantByNames(titleRoot, { "CloseButton" }) or nil

	self._musicRoot = self:_findDescendantByNames(self._optionRoot, { "Music" })
	self._musicToggleRoot = self._musicRoot and self:_findDescendantByNames(self._musicRoot, { "CloseButton" }) or nil
	self._musicToggleButton = self:_resolveInteractiveNode(self._musicToggleRoot)
	self._musicTextLabel = self._musicToggleRoot and self:_findDescendantByNames(self._musicToggleRoot, { "Text" }) or nil
	self._musicGradient = self._musicToggleRoot and self:_findDescendantByNames(self._musicToggleRoot, { "UIGradient" }) or nil

	self._sfxRoot = self:_findDescendantByNames(self._optionRoot, { "Sfx" })
	self._sfxToggleRoot = self._sfxRoot and self:_findDescendantByNames(self._sfxRoot, { "CloseButton" }) or nil
	self._sfxToggleButton = self:_resolveInteractiveNode(self._sfxToggleRoot)
	self._sfxTextLabel = self._sfxToggleRoot and self:_findDescendantByNames(self._sfxToggleRoot, { "Text" }) or nil
	self._sfxGradient = self._sfxToggleRoot and self:_findDescendantByNames(self._sfxToggleRoot, { "UIGradient" }) or nil

	self:_clearUiBindings()

	if self._openButton then
		table.insert(self._uiConnections, self._openButton.Activated:Connect(function()
			self:OpenOptions()
		end))
	else
		if self:_shouldWarnBindingIssues() then
			self:_warnOnce("MissingOptionsOpenButton", "[SettingsController] 找不到 Main/TopRightGui/Options/Button。")
		end
	end

	local closeInteractive = self:_resolveInteractiveNode(self._closeButton)
	if closeInteractive then
		table.insert(self._uiConnections, closeInteractive.Activated:Connect(function()
			self:CloseOptions()
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
			self:_warnOnce("MissingOptionsCloseButton", "[SettingsController] 找不到 Main/Option/Title/CloseButton。")
		end
	end

	if self._musicToggleButton then
		table.insert(self._uiConnections, self._musicToggleButton.Activated:Connect(function()
			self:SetMusicEnabled(not self._musicEnabled)
		end))
		self:_bindButtonFx(self._musicToggleButton, {
			ScaleTarget = self._musicToggleRoot or self._musicToggleButton,
			HoverScale = 1.05,
			PressScale = 0.94,
		}, self._uiConnections)
	else
		if self:_shouldWarnBindingIssues() then
			self:_warnOnce("MissingMusicToggle", "[SettingsController] 找不到 Main/Option/Music/CloseButton。")
		end
	end

	if self._sfxToggleButton then
		table.insert(self._uiConnections, self._sfxToggleButton.Activated:Connect(function()
			self:SetSfxEnabled(not self._sfxEnabled)
		end))
		self:_bindButtonFx(self._sfxToggleButton, {
			ScaleTarget = self._sfxToggleRoot or self._sfxToggleButton,
			HoverScale = 1.05,
			PressScale = 0.94,
		}, self._uiConnections)
	else
		if self:_shouldWarnBindingIssues() then
			self:_warnOnce("MissingSfxToggle", "[SettingsController] 找不到 Main/Option/Sfx/CloseButton。")
		end
	end

	self:_renderSettingsUi()
	return true
end

function SettingsController:_queueRebind()
	if self._rebindQueued then
		return
	end

	self._rebindQueued = true
	task.defer(function()
		self._rebindQueued = false
		self:_bindMainUi()
	end)
end

function SettingsController:_scheduleRetryBind()
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

function SettingsController:_submitSettingsUpdate()
	self:_renderSettingsUi()
	self:_applySoundPreferences()

	if self._requestUpdateEvent and self._requestUpdateEvent:IsA("RemoteEvent") then
		self._requestUpdateEvent:FireServer({
			musicEnabled = self._musicEnabled,
			sfxEnabled = self._sfxEnabled,
		})
	end
end

function SettingsController:_applyStatePayload(payload)
	if type(payload) ~= "table" then
		return
	end

	if payload.musicEnabled ~= nil then
		self._musicEnabled = payload.musicEnabled == true
	end
	if payload.sfxEnabled ~= nil then
		self._sfxEnabled = payload.sfxEnabled == true
	end

	self:_renderSettingsUi()
	self:_applySoundPreferences()
end

function SettingsController:SetMusicEnabled(isEnabled)
	self._musicEnabled = isEnabled == true
	self:_submitSettingsUpdate()
end

function SettingsController:SetSfxEnabled(isEnabled)
	self._sfxEnabled = isEnabled == true
	self:_submitSettingsUpdate()
end

function SettingsController:OpenOptions()
	if not isLiveInstance(self._optionRoot) and not self:_bindMainUi() then
		return
	end

	self:_renderSettingsUi()
	if self._requestStateSyncEvent and self._requestStateSyncEvent:IsA("RemoteEvent") then
		self._requestStateSyncEvent:FireServer()
	end

	if self._modalController then
		if not self:_isOptionModalOpen() then
			self._modalController:OpenModal(self._modalKey, self._optionRoot, {
				HiddenNodes = self:_getHiddenNodesForModal(),
			})
		end
	elseif self._optionRoot and self._optionRoot:IsA("GuiObject") then
		self._optionRoot.Visible = true
	end
end

function SettingsController:CloseOptions()
	if not isLiveInstance(self._optionRoot) then
		return
	end

	if self._modalController then
		self._modalController:CloseModal(self._modalKey)
	elseif self._optionRoot and self._optionRoot:IsA("GuiObject") then
		self._optionRoot.Visible = false
	end
end

function SettingsController:Start()
	if self._started then
		return
	end

	self._started = true
	self._startupWarnAt = os.clock() + STARTUP_WARNING_GRACE_SECONDS

	local eventsRoot = ReplicatedStorage:WaitForChild(RemoteNames.RootFolder)
	local systemEvents = eventsRoot:WaitForChild(RemoteNames.SystemEventsFolder)

	self._stateSyncEvent = systemEvents:FindFirstChild(RemoteNames.System.SettingsStateSync)
		or systemEvents:WaitForChild(RemoteNames.System.SettingsStateSync, 10)
	self._requestStateSyncEvent = systemEvents:FindFirstChild(RemoteNames.System.RequestSettingsStateSync)
		or systemEvents:WaitForChild(RemoteNames.System.RequestSettingsStateSync, 10)
	self._requestUpdateEvent = systemEvents:FindFirstChild(RemoteNames.System.RequestSettingsUpdate)
		or systemEvents:WaitForChild(RemoteNames.System.RequestSettingsUpdate, 10)

	if self._stateSyncEvent and self._stateSyncEvent:IsA("RemoteEvent") then
		table.insert(self._persistentConnections, self._stateSyncEvent.OnClientEvent:Connect(function(payload)
			self:_applyStatePayload(payload)
		end))
	else
		self:_warnOnce("MissingSettingsStateSync", "[SettingsController] 找不到 SettingsStateSync，设置不会自动同步。")
	end

	local playerGui = self:_getPlayerGui()
	if playerGui then
		table.insert(self._persistentConnections, playerGui.DescendantAdded:Connect(function(descendant)
			local watchedNames = {
				Main = true,
				TopRightGui = true,
				Options = true,
				Button = true,
				Option = true,
				Title = true,
				CloseButton = true,
				Music = true,
				Sfx = true,
				Text = true,
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

	table.insert(self._persistentConnections, game.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("Sound") then
			self:_trackSound(descendant)
		end
	end))

	self:_trackExistingSounds()
	self:_applySoundPreferences()
	self:_scheduleRetryBind()

	if self._requestStateSyncEvent and self._requestStateSyncEvent:IsA("RemoteEvent") then
		self._requestStateSyncEvent:FireServer()
	end
end

return SettingsController