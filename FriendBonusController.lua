--[[
脚本名字: FriendBonusController
脚本文件: FriendBonusController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/FriendBonusController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
        "[FriendBonusController] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local RemoteNames = requireSharedModule("RemoteNames")

local FriendBonusController = {}
FriendBonusController.__index = FriendBonusController

function FriendBonusController.new()
    local self = setmetatable({}, FriendBonusController)
    self._friendBonusLabel = nil
    self._currentBonusPercent = 0
    return self
end

function FriendBonusController:_formatBonusText(percent)
    local safePercent = math.max(0, math.floor(tonumber(percent) or 0))
    return string.format("Friend Bonus: +%d%%", safePercent)
end

function FriendBonusController:_setBonusPercent(percent)
    self._currentBonusPercent = math.max(0, math.floor(tonumber(percent) or 0))
    if self._friendBonusLabel and self._friendBonusLabel.Parent then
        self._friendBonusLabel.Text = self:_formatBonusText(self._currentBonusPercent)
    end
end

function FriendBonusController:_ensureUiNodes()
    if self._friendBonusLabel and self._friendBonusLabel.Parent then
        return true
    end

    local playerGui = localPlayer:WaitForChild("PlayerGui")
    local mainGui = playerGui:FindFirstChild("Main") or playerGui:WaitForChild("Main", 5)
    if not mainGui then
        warn("[FriendBonusController] 找不到 Main UI，FriendBonus 同步已跳过。")
        return false
    end

    local cashFrame = mainGui:FindFirstChild("Cash") or mainGui:WaitForChild("Cash", 5)
    if not cashFrame then
        warn("[FriendBonusController] 找不到 Cash UI，FriendBonus 同步已跳过。")
        return false
    end

    local friendBonusLabel = cashFrame:FindFirstChild("FriendBonus")
    if not (friendBonusLabel and friendBonusLabel:IsA("TextLabel")) then
        warn("[FriendBonusController] 找不到 Cash/FriendBonus 文本节点（TextLabel）。")
        return false
    end

    self._friendBonusLabel = friendBonusLabel
    self._friendBonusLabel.Text = self:_formatBonusText(self._currentBonusPercent)
    return true
end

function FriendBonusController:Start()
    self:_setBonusPercent(0)
    self:_ensureUiNodes()

    local eventsRoot = ReplicatedStorage:WaitForChild(RemoteNames.RootFolder)
    local systemEvents = eventsRoot:WaitForChild(RemoteNames.SystemEventsFolder)
    local friendBonusSyncEvent = systemEvents:FindFirstChild(RemoteNames.System.FriendBonusSync)
    local requestFriendBonusSyncEvent = systemEvents:FindFirstChild(RemoteNames.System.RequestFriendBonusSync)

    if friendBonusSyncEvent and friendBonusSyncEvent:IsA("RemoteEvent") then
        friendBonusSyncEvent.OnClientEvent:Connect(function(payload)
            local bonusPercent = type(payload) == "table" and payload.bonusPercent or payload
            self:_setBonusPercent(bonusPercent)
            self:_ensureUiNodes()
        end)
    end

    localPlayer.CharacterAdded:Connect(function()
        task.defer(function()
            if self:_ensureUiNodes() then
                self:_setBonusPercent(self._currentBonusPercent)
            end
        end)
    end)

    if requestFriendBonusSyncEvent and requestFriendBonusSyncEvent:IsA("RemoteEvent") then
        requestFriendBonusSyncEvent:FireServer()
    end
end

return FriendBonusController
