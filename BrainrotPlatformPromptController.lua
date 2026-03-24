--[[
脚本名字: BrainrotPlatformPromptController
脚本文件: BrainrotPlatformPromptController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/BrainrotPlatformPromptController
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer

local BRAINROT_PLATFORM_PROMPT_ATTRIBUTE = "BrainrotPlatformPrompt"
local BRAINROT_PLATFORM_HOME_ID_ATTRIBUTE = "BrainrotPlatformHomeId"
local BRAINROT_PLATFORM_OWNER_USER_ID_ATTRIBUTE = "BrainrotPlatformOwnerUserId"
local BRAINROT_PLATFORM_SERVER_ENABLED_ATTRIBUTE = "BrainrotPlatformServerEnabled"

local BrainrotPlatformPromptController = {}
BrainrotPlatformPromptController.__index = BrainrotPlatformPromptController

function BrainrotPlatformPromptController.new()
    local self = setmetatable({}, BrainrotPlatformPromptController)
    self._homeId = tostring(localPlayer:GetAttribute("HomeId") or "")
    self._promptConnectionsByPrompt = {}
    self._workspaceDescendantAddedConnection = nil
    self._promptShownConnection = nil
    self._homeIdChangedConnection = nil
    return self
end

function BrainrotPlatformPromptController:_getAssignedHomeId()
    self._homeId = tostring(localPlayer:GetAttribute("HomeId") or "")
    return self._homeId
end

function BrainrotPlatformPromptController:_shouldShowPrompt(prompt)
    local ownerUserId = math.floor(tonumber(prompt:GetAttribute(BRAINROT_PLATFORM_OWNER_USER_ID_ATTRIBUTE)) or 0)
    if ownerUserId <= 0 then
        return false
    end

    local promptHomeId = tostring(prompt:GetAttribute(BRAINROT_PLATFORM_HOME_ID_ATTRIBUTE) or "")
    if promptHomeId == "" then
        return false
    end

    if prompt:GetAttribute(BRAINROT_PLATFORM_SERVER_ENABLED_ATTRIBUTE) ~= true then
        return false
    end

    return promptHomeId == self:_getAssignedHomeId()
end

function BrainrotPlatformPromptController:_applyPromptVisibility(prompt)
    if not (prompt and prompt:IsA("ProximityPrompt")) then
        return
    end

    if prompt:GetAttribute(BRAINROT_PLATFORM_PROMPT_ATTRIBUTE) ~= true then
        return
    end

    local shouldShow = self:_shouldShowPrompt(prompt)
    if prompt.Enabled ~= shouldShow then
        prompt.Enabled = shouldShow
    end
end

function BrainrotPlatformPromptController:_disconnectPrompt(prompt)
    local connectionList = self._promptConnectionsByPrompt[prompt]
    if type(connectionList) ~= "table" then
        return
    end

    for _, connection in ipairs(connectionList) do
        if connection and connection.Disconnect then
            connection:Disconnect()
        end
    end

    self._promptConnectionsByPrompt[prompt] = nil
end

function BrainrotPlatformPromptController:_trackPrompt(prompt)
    if not (prompt and prompt:IsA("ProximityPrompt")) then
        return
    end

    if self._promptConnectionsByPrompt[prompt] then
        self:_applyPromptVisibility(prompt)
        return
    end

    local connectionList = {}
    self._promptConnectionsByPrompt[prompt] = connectionList

    table.insert(connectionList, prompt:GetAttributeChangedSignal(BRAINROT_PLATFORM_PROMPT_ATTRIBUTE):Connect(function()
        self:_applyPromptVisibility(prompt)
    end))
    table.insert(connectionList, prompt:GetAttributeChangedSignal(BRAINROT_PLATFORM_HOME_ID_ATTRIBUTE):Connect(function()
        self:_applyPromptVisibility(prompt)
    end))
    table.insert(connectionList, prompt:GetAttributeChangedSignal(BRAINROT_PLATFORM_OWNER_USER_ID_ATTRIBUTE):Connect(function()
        self:_applyPromptVisibility(prompt)
    end))
    table.insert(connectionList, prompt:GetAttributeChangedSignal(BRAINROT_PLATFORM_SERVER_ENABLED_ATTRIBUTE):Connect(function()
        self:_applyPromptVisibility(prompt)
    end))
    table.insert(connectionList, prompt.AncestryChanged:Connect(function(_, parent)
        if not parent then
            self:_disconnectPrompt(prompt)
        end
    end))

    self:_applyPromptVisibility(prompt)
end

function BrainrotPlatformPromptController:_refreshAllPrompts()
    for _, descendant in ipairs(Workspace:GetDescendants()) do
        if descendant:IsA("ProximityPrompt") then
            self:_trackPrompt(descendant)
        end
    end

    for prompt in pairs(self._promptConnectionsByPrompt) do
        if not prompt.Parent then
            self:_disconnectPrompt(prompt)
        else
            self:_applyPromptVisibility(prompt)
        end
    end
end

function BrainrotPlatformPromptController:Start()
    self:_getAssignedHomeId()

    self._workspaceDescendantAddedConnection = Workspace.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("ProximityPrompt") then
            self:_trackPrompt(descendant)
        end
    end)

    self._promptShownConnection = ProximityPromptService.PromptShown:Connect(function(prompt)
        self:_trackPrompt(prompt)
        self:_applyPromptVisibility(prompt)
    end)

    self._homeIdChangedConnection = localPlayer:GetAttributeChangedSignal("HomeId"):Connect(function()
        self:_getAssignedHomeId()
        self:_refreshAllPrompts()
    end)

    self:_refreshAllPrompts()
end

return BrainrotPlatformPromptController
