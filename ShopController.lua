--[[
脚本名字: ShopController
脚本文件: ShopController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/ShopController
]]

local Players = game:GetService("Players")

local localPlayer = Players.LocalPlayer

local function requireControllerModule(moduleName)
    local controllersFolder = script.Parent
    if controllersFolder then
        local moduleInControllers = controllersFolder:FindFirstChild(moduleName)
        if moduleInControllers and moduleInControllers:IsA("ModuleScript") then
            return require(moduleInControllers)
        end
    end

    error(string.format("[ShopController] Missing controller module %s.", tostring(moduleName)))
end

local IndexController = requireControllerModule("IndexController")

local ShopController = {}
ShopController.__index = ShopController

local STARTUP_WARNING_GRACE_SECONDS = 2
local SHOP_MODAL_KEY = "Shop"

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

local function isNestedUnderGuiButton(node, root)
    local current = node and node.Parent or nil
    while current and current ~= root do
        if current:IsA("GuiButton") then
            return true
        end
        current = current.Parent
    end

    return false
end

function ShopController.new(modalController)
    local self = setmetatable({}, ShopController)
    self._modalController = modalController
    self._indexHelper = IndexController.new(nil)
    self._started = false
    self._startupWarnAt = 0
    self._rebindQueued = false
    self._persistentConnections = {}
    self._uiConnections = {}
    self._didWarnByKey = {}
    self._mainGui = nil
    self._leftRoot = nil
    self._leftShopRoot = nil
    self._openButton = nil
    self._shopRoot = nil
    self._closeButton = nil
    return self
end

function ShopController:_warnOnce(key, message)
    if self._didWarnByKey[key] then
        return
    end

    self._didWarnByKey[key] = true
    warn(message)
end

function ShopController:_shouldWarnBindingIssues()
    return os.clock() >= (self._startupWarnAt or 0)
end

function ShopController:_getPlayerGui()
    return localPlayer:FindFirstChild("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
end

function ShopController:_getMainGui()
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

function ShopController:_findDirectChildByName(root, childName)
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

function ShopController:_findDescendantByNames(root, names)
    return self._indexHelper:_findDescendantByNames(root, names)
end

function ShopController:_resolveInteractiveNode(node)
    return self._indexHelper:_resolveInteractiveNode(node)
end

function ShopController:_bindButtonFx(interactiveNode, options, connectionBucket)
    self._indexHelper:_bindButtonFx(interactiveNode, options, connectionBucket)
end

function ShopController:_isShopModalOpen()
    if self._modalController and self._modalController.IsModalOpen then
        return self._modalController:IsModalOpen(SHOP_MODAL_KEY)
    end

    return isLiveInstance(self._shopRoot) and self._shopRoot.Visible == true
end

function ShopController:_getHiddenNodesForModal()
    local hiddenNodes = {}
    if not self._mainGui then
        return hiddenNodes
    end

    for _, node in ipairs(self._mainGui:GetChildren()) do
        if node and node ~= self._shopRoot then
            table.insert(hiddenNodes, node)
        end
    end

    return hiddenNodes
end

function ShopController:_collectActionButtons(closeInteractive)
    local result = {}
    if not self._shopRoot then
        return result
    end

    for _, descendant in ipairs(self._shopRoot:GetDescendants()) do
        if descendant:IsA("GuiButton")
            and descendant ~= closeInteractive
            and not isNestedUnderGuiButton(descendant, self._shopRoot)
        then
            table.insert(result, descendant)
        end
    end

    return result
end

function ShopController:_clearUiBindings()
    disconnectAll(self._uiConnections)
end

function ShopController:_bindMainUi()
    local mainGui = self:_getMainGui()
    if not mainGui then
        if self:_shouldWarnBindingIssues() then
            self:_warnOnce("MissingMain", "[ShopController] Main UI is missing, shop panel is unavailable.")
        end
        self:_clearUiBindings()
        return false
    end

    self._mainGui = mainGui
    self._leftRoot = self:_findDirectChildByName(mainGui, "Left")
    self._leftShopRoot = self._leftRoot and self:_findDescendantByNames(self._leftRoot, { "Shop" }) or nil
    self._openButton = self._leftShopRoot and self:_resolveInteractiveNode(
        self:_findDescendantByNames(self._leftShopRoot, { "TextButton", "Button" }) or self._leftShopRoot
    ) or nil
    self._shopRoot = self:_findDirectChildByName(mainGui, "Shop")

    if not self._shopRoot then
        if self:_shouldWarnBindingIssues() then
            self:_warnOnce("MissingShopRoot", "[ShopController] Main/Shop is missing, shop panel did not bind.")
        end
        self:_clearUiBindings()
        return false
    end

    local titleRoot = self:_findDirectChildByName(self._shopRoot, "Title")
    self._closeButton = titleRoot and self:_findDescendantByNames(titleRoot, { "CloseButton" }) or nil

    self:_clearUiBindings()

    if self._openButton then
        table.insert(self._uiConnections, self._openButton.Activated:Connect(function()
            self:OpenShop()
        end))
    elseif self:_shouldWarnBindingIssues() then
        self:_warnOnce("MissingOpenButton", "[ShopController] Main/Left/Shop/TextButton is missing.")
    end

    local closeInteractive = self:_resolveInteractiveNode(self._closeButton)
    if closeInteractive then
        table.insert(self._uiConnections, closeInteractive.Activated:Connect(function()
            self:CloseShop()
        end))
        self:_bindButtonFx(closeInteractive, {
            ScaleTarget = self._closeButton,
            RotationTarget = self._closeButton,
            HoverScale = 1.12,
            PressScale = 0.92,
            HoverRotation = 20,
        }, self._uiConnections)
    elseif self:_shouldWarnBindingIssues() then
        self:_warnOnce("MissingCloseButton", "[ShopController] Main/Shop/Title/CloseButton is missing.")
    end

    for _, button in ipairs(self:_collectActionButtons(closeInteractive)) do
        self:_bindButtonFx(button, {
            ScaleTarget = button,
            HoverScale = 1.05,
            PressScale = 0.94,
        }, self._uiConnections)
    end

    if self._shopRoot:IsA("GuiObject") and not self:_isShopModalOpen() then
        self._shopRoot.Visible = false
    end

    return true
end

function ShopController:_queueRebind()
    if self._rebindQueued then
        return
    end

    self._rebindQueued = true
    task.defer(function()
        self._rebindQueued = false
        self:_bindMainUi()
    end)
end

function ShopController:_scheduleRetryBind()
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

function ShopController:OpenShop()
    if not isLiveInstance(self._shopRoot) and not self:_bindMainUi() then
        return
    end

    if self._modalController then
        if not self:_isShopModalOpen() then
            self._modalController:OpenModal(SHOP_MODAL_KEY, self._shopRoot, {
                HiddenNodes = self:_getHiddenNodesForModal(),
            })
        end
    elseif self._shopRoot and self._shopRoot:IsA("GuiObject") then
        self._shopRoot.Visible = true
    end
end

function ShopController:CloseShop(immediate)
    if not isLiveInstance(self._shopRoot) then
        return
    end

    if self._modalController then
        self._modalController:CloseModal(SHOP_MODAL_KEY, {
            Immediate = immediate == true,
        })
    elseif self._shopRoot and self._shopRoot:IsA("GuiObject") then
        self._shopRoot.Visible = false
    end
end

function ShopController:Start()
    if self._started then
        return
    end

    self._started = true
    self._startupWarnAt = os.clock() + STARTUP_WARNING_GRACE_SECONDS

    local playerGui = self:_getPlayerGui()
    if playerGui then
        table.insert(self._persistentConnections, playerGui.DescendantAdded:Connect(function(descendant)
            local watchedNames = {
                Main = true,
                Left = true,
                Shop = true,
                Title = true,
                CloseButton = true,
                TextButton = true,
                Button = true,
                BuyButton = true,
                ScrollingFrame = true,
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
end

return ShopController
