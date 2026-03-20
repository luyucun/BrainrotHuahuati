--[[
脚本名字: QuickTeleportController
脚本文件: QuickTeleportController.lua
脚本类型: ModuleScript
本地路径: D:/RobloxGame/BrainrotsTemplate/QuickTeleportController.lua
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/QuickTeleportController
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
        "[QuickTeleportController] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local RemoteNames = requireSharedModule("RemoteNames")

local QuickTeleportController = {}
QuickTeleportController.__index = QuickTeleportController

function QuickTeleportController.new()
    local self = setmetatable({}, QuickTeleportController)
    self._requestQuickTeleportEvent = nil
    self._buttonByDestination = {}
    self._connectionByDestination = {}
    self._didWarnMissingNode = {}
    self._playerGuiConnection = nil
    return self
end

function QuickTeleportController:_getTopRoot()
    local playerGui = localPlayer:FindFirstChild("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
    if not playerGui then
        return nil
    end

    local mainGui = playerGui:FindFirstChild("Main")
    if not mainGui then
        return nil
    end

    local topRoot = mainGui:FindFirstChild("Top") or mainGui:FindFirstChild("Top", true)
    return topRoot
end

function QuickTeleportController:_warnOnce(key, message)
    if self._didWarnMissingNode[key] then
        return
    end

    self._didWarnMissingNode[key] = true
    warn(message)
end

function QuickTeleportController:_bindButton(topRoot, buttonName, destination)
    if not topRoot then
        return false
    end

    local button = topRoot:FindFirstChild(buttonName) or topRoot:FindFirstChild(buttonName, true)
    if not button then
        self:_warnOnce(buttonName, string.format(
            "[QuickTeleportController] 找不到按钮: Main/Top/%s",
            tostring(buttonName)
        ))
        return false
    end

    if not button:IsA("GuiButton") then
        self:_warnOnce(buttonName .. "_Type", string.format(
            "[QuickTeleportController] 节点不是 GuiButton: %s (%s)",
            tostring(button:GetFullName()),
            tostring(button.ClassName)
        ))
        return false
    end

    local existingButton = self._buttonByDestination[destination]
    if existingButton == button and self._connectionByDestination[destination] then
        return true
    end

    local existingConnection = self._connectionByDestination[destination]
    if existingConnection then
        existingConnection:Disconnect()
        self._connectionByDestination[destination] = nil
    end

    self._buttonByDestination[destination] = button
    self._connectionByDestination[destination] = button.Activated:Connect(function()
        if self._requestQuickTeleportEvent then
            self._requestQuickTeleportEvent:FireServer({
                target = destination,
            })
        end
    end)

    return true
end

function QuickTeleportController:_tryBindAllButtons()
    local topRoot = self:_getTopRoot()
    if not topRoot then
        self:_warnOnce("Top", "[QuickTeleportController] 找不到 Main/Top，快捷传送按钮暂不可用。")
        return false
    end

    local homeBound = self:_bindButton(topRoot, "Home", "Home")
    local shopBound = self:_bindButton(topRoot, "Shop", "Shop")
    local sellBound = self:_bindButton(topRoot, "Sell", "Sell")

    return homeBound and shopBound and sellBound
end

function QuickTeleportController:_scheduleRebind()
    task.spawn(function()
        local deadline = os.clock() + 12
        repeat
            if self:_tryBindAllButtons() then
                return
            end
            task.wait(1)
        until os.clock() >= deadline
    end)
end

function QuickTeleportController:Start()
    local eventsRoot = ReplicatedStorage:WaitForChild(RemoteNames.RootFolder)
    local systemEvents = eventsRoot:WaitForChild(RemoteNames.SystemEventsFolder)

    self._requestQuickTeleportEvent = systemEvents:FindFirstChild(RemoteNames.System.RequestQuickTeleport)
    if not (self._requestQuickTeleportEvent and self._requestQuickTeleportEvent:IsA("RemoteEvent")) then
        self._requestQuickTeleportEvent = systemEvents:WaitForChild(RemoteNames.System.RequestQuickTeleport, 10)
    end

    if not (self._requestQuickTeleportEvent and self._requestQuickTeleportEvent:IsA("RemoteEvent")) then
        warn("[QuickTeleportController] 找不到 RequestQuickTeleport 事件，快捷传送功能未启动。")
        return
    end

    self:_scheduleRebind()

    local playerGui = localPlayer:FindFirstChild("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
    if playerGui then
        self._playerGuiConnection = playerGui.DescendantAdded:Connect(function(descendant)
            if descendant.Name == "Main" or descendant.Name == "Top" or descendant.Name == "Home" or descendant.Name == "Shop" or descendant.Name == "Sell" then
                task.defer(function()
                    self:_tryBindAllButtons()
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

return QuickTeleportController