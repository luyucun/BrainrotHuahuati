--[[
脚本名字: CustomBackpackController
脚本文件: CustomBackpackController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/CustomBackpackController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

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
        "[CustomBackpackController] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local GameConfig = requireSharedModule("GameConfig")

local CustomBackpackController = {}
CustomBackpackController.__index = CustomBackpackController
local MAX_NUMBERED_SLOT_COUNT = 10

local SLOT_INDEX_BY_KEY_CODE = {
    [Enum.KeyCode.One] = 1,
    [Enum.KeyCode.Two] = 2,
    [Enum.KeyCode.Three] = 3,
    [Enum.KeyCode.Four] = 4,
    [Enum.KeyCode.Five] = 5,
    [Enum.KeyCode.Six] = 6,
    [Enum.KeyCode.Seven] = 7,
    [Enum.KeyCode.Eight] = 8,
    [Enum.KeyCode.Nine] = 9,
    [Enum.KeyCode.Zero] = 10,
    [Enum.KeyCode.KeypadOne] = 1,
    [Enum.KeyCode.KeypadTwo] = 2,
    [Enum.KeyCode.KeypadThree] = 3,
    [Enum.KeyCode.KeypadFour] = 4,
    [Enum.KeyCode.KeypadFive] = 5,
    [Enum.KeyCode.KeypadSix] = 6,
    [Enum.KeyCode.KeypadSeven] = 7,
    [Enum.KeyCode.KeypadEight] = 8,
    [Enum.KeyCode.KeypadNine] = 9,
    [Enum.KeyCode.KeypadZero] = 10,
}

local function disconnectConnections(connectionList)
    for _, connection in ipairs(connectionList) do
        if connection then
            connection:Disconnect()
        end
    end
    table.clear(connectionList)
end

local function isLiveInstance(instance)
    return instance and instance.Parent ~= nil
end

local function findFirstDescendantByNames(root, names)
    if not root then
        return nil
    end

    for _, name in ipairs(names or {}) do
        local direct = root:FindFirstChild(name)
        if direct then
            return direct
        end
    end

    for _, name in ipairs(names or {}) do
        local nested = root:FindFirstChild(name, true)
        if nested then
            return nested
        end
    end

    return nil
end

local function findFirstGuiObjectByName(root, name)
    local node = root and findFirstDescendantByNames(root, { name }) or nil
    if node and node:IsA("GuiObject") then
        return node
    end

    if node then
        return node:FindFirstChildWhichIsA("GuiObject", true)
    end

    return nil
end

local function resolveInteractiveNode(node)
    if not node then
        return nil
    end

    if node:IsA("GuiButton") then
        return node
    end

    local textButton = node:FindFirstChild("TextButton")
    if textButton and textButton:IsA("GuiButton") then
        return textButton
    end

    local imageButton = node:FindFirstChild("ImageButton")
    if imageButton and imageButton:IsA("GuiButton") then
        return imageButton
    end

    return node:FindFirstChildWhichIsA("GuiButton", true) or node
end

local function isActivateInput(inputObject)
    if not inputObject then
        return false
    end

    return inputObject.UserInputType == Enum.UserInputType.MouseButton1
        or inputObject.UserInputType == Enum.UserInputType.Touch
end

local function appendUniqueGuiObject(targetList, seen, node)
    if not (node and node:IsA("GuiObject")) then
        return
    end

    if seen[node] then
        return
    end

    seen[node] = true
    table.insert(targetList, node)
end

local function shouldShowKeyboardSlotNumber()
    local hasDesktopLikePointer = UserInputService.MouseEnabled or not UserInputService.TouchEnabled
    return UserInputService.KeyboardEnabled and hasDesktopLikePointer
end

local function getKeyboardSlotNumberText(slotIndex)
    if type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > MAX_NUMBERED_SLOT_COUNT then
        return ""
    end

    if slotIndex == MAX_NUMBERED_SLOT_COUNT then
        return "0"
    end

    return tostring(slotIndex)
end

function CustomBackpackController.new(modalController)
    local self = setmetatable({}, CustomBackpackController)
    self._persistentConnections = {}
    self._toolWatcherConnections = {}
    self._entryConnections = {}
    self._entryClones = {}
    self._entryToolEntryByClone = {}
    self._renderedToolEntries = {}
    self._didWarnByKey = {}
    self._modalController = modalController
    self._backpackRoot = nil
    self._itemListRoot = nil
    self._entryTemplate = nil
    self._rebindQueued = false
    self._refreshQueued = false
    self._coreBackpackHidden = false
    self._lastGuiActivationClock = 0
    self._lastGuiActivationKey = nil
    self._refreshBurstToken = 0
    self._started = false
    return self
end

function CustomBackpackController:_warnOnce(key, message)
    if self._didWarnByKey[key] then
        return
    end

    self._didWarnByKey[key] = true
    warn(message)
end

function CustomBackpackController:_getPlayerGui()
    return localPlayer:FindFirstChildOfClass("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
end

function CustomBackpackController:_getMainGui()
    local playerGui = self:_getPlayerGui()
    return playerGui and playerGui:FindFirstChild("Main") or nil
end

function CustomBackpackController:_setCoreBackpackEnabled(enabled)
    local success = pcall(function()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, enabled == true)
    end)

    if success then
        self._coreBackpackHidden = enabled ~= true
    end

    return success
end

function CustomBackpackController:_ensureCoreBackpackHidden()
    if self._coreBackpackHidden then
        return true
    end

    if self:_setCoreBackpackEnabled(false) then
        return true
    end

    task.defer(function()
        local deadline = os.clock() + 10
        repeat
            if self:_setCoreBackpackEnabled(false) then
                return
            end
            task.wait(0.5)
        until os.clock() >= deadline
    end)

    return false
end

function CustomBackpackController:_clearEntryBindings()
    disconnectConnections(self._entryConnections)

    for _, clone in ipairs(self._entryClones) do
        if clone and clone.Parent then
            clone:Destroy()
        end
    end

    table.clear(self._entryClones)
    table.clear(self._entryToolEntryByClone)
    table.clear(self._renderedToolEntries)
end

function CustomBackpackController:_getToolSortKey(tool)
    local isBrainrotTool = tool:GetAttribute("BrainrotTool") == true
    local weaponFlagName = tostring((GameConfig.WEAPON or {}).ToolIsWeaponAttributeName or "IsWeaponTool")
    local isWeaponTool = tool:GetAttribute(weaponFlagName) == true

    -- Keep slot order stable after equip/unequip instead of moving equipped tools to the front.
    local typeOrder = 2
    if isWeaponTool then
        typeOrder = 0
    elseif isBrainrotTool then
        typeOrder = 1
    end

    local explicitOrder = math.max(0, math.floor(tonumber(tool:GetAttribute("BrainrotInstanceId")) or 0))
    if explicitOrder <= 0 then
        explicitOrder = math.max(0, math.floor(tonumber(tool:GetAttribute("WeaponSlotIndex")) or 0))
    end

    return typeOrder, explicitOrder
end

function CustomBackpackController:_getToolUniqueKey(tool)
    local brainrotInstanceId = math.max(0, math.floor(tonumber(tool:GetAttribute("BrainrotInstanceId")) or 0))
    if brainrotInstanceId > 0 then
        return string.format("Brainrot:%d", brainrotInstanceId)
    end

    local weaponIdAttributeName = tostring((GameConfig.WEAPON or {}).ToolWeaponIdAttributeName or "WeaponId")
    local weaponId = tostring(tool:GetAttribute(weaponIdAttributeName) or "")
    if weaponId ~= "" then
        return string.format("Weapon:%s", weaponId)
    end

    return string.format("Tool:%s", tool:GetDebugId())
end

function CustomBackpackController:_collectTools()
    local entries = {}
    local seen = {}

    local function addTool(tool)
        if not (tool and tool:IsA("Tool")) then
            return
        end

        if tool:GetAttribute("HideFromCustomBackpack") == true then
            return
        end

        local uniqueKey = self:_getToolUniqueKey(tool)
        if seen[uniqueKey] then
            return
        end
        seen[uniqueKey] = true

        local sortTypeOrder, explicitOrder = self:_getToolSortKey(tool)
        table.insert(entries, {
            key = uniqueKey,
            tool = tool,
            name = tostring(tool.Name or "Tool"),
            icon = tostring(tool.TextureId or ""),
            isEquipped = localPlayer.Character and tool.Parent == localPlayer.Character,
            sortTypeOrder = sortTypeOrder,
            explicitOrder = explicitOrder,
        })
    end

    local backpack = localPlayer:FindFirstChild("Backpack")
    local character = localPlayer.Character

    if backpack then
        for _, child in ipairs(backpack:GetChildren()) do
            addTool(child)
        end
    end

    if character then
        for _, child in ipairs(character:GetChildren()) do
            addTool(child)
        end
    end

    table.sort(entries, function(a, b)
        if a.sortTypeOrder ~= b.sortTypeOrder then
            return a.sortTypeOrder < b.sortTypeOrder
        end

        if a.explicitOrder ~= b.explicitOrder then
            return a.explicitOrder < b.explicitOrder
        end

        local lowerNameA = string.lower(a.name)
        local lowerNameB = string.lower(b.name)
        if lowerNameA ~= lowerNameB then
            return lowerNameA < lowerNameB
        end

        return a.key < b.key
    end)

    return entries
end

function CustomBackpackController:_refreshCanvasSize()
    local itemListRoot = self._itemListRoot
    if not (itemListRoot and itemListRoot:IsA("ScrollingFrame")) then
        return
    end

    local layout = itemListRoot:FindFirstChildWhichIsA("UIListLayout")
    if not layout then
        return
    end

    local paddingOffset = 0
    local topPadding = itemListRoot:FindFirstChildWhichIsA("UIPadding")
    if topPadding then
        paddingOffset += topPadding.PaddingTop.Offset + topPadding.PaddingBottom.Offset
    end

    itemListRoot.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + paddingOffset)
end

function CustomBackpackController:_applyEntryVisual(clone, toolEntry)
    local iconNode = findFirstDescendantByNames(clone, { "Icon" })
    if iconNode and (iconNode:IsA("ImageLabel") or iconNode:IsA("ImageButton")) then
        iconNode.Image = toolEntry.icon
    end

    local nameNode = findFirstDescendantByNames(clone, { "Name" })
    if nameNode and (nameNode:IsA("TextLabel") or nameNode:IsA("TextButton")) then
        nameNode.Text = toolEntry.name
    end

    local numberNode = findFirstDescendantByNames(clone, { "Number" })
    if numberNode and (numberNode:IsA("TextLabel") or numberNode:IsA("TextButton")) then
        local slotNumberText = getKeyboardSlotNumberText(toolEntry.slotIndex)
        local shouldShowNumber = shouldShowKeyboardSlotNumber() and slotNumberText ~= ""
        numberNode.Visible = shouldShowNumber
        numberNode.Text = shouldShowNumber and slotNumberText or ""
    end
end

function CustomBackpackController:_consumeGuiActivation(toolKey)
    local nowClock = os.clock()
    if self._lastGuiActivationKey == toolKey and (nowClock - self._lastGuiActivationClock) <= 0.12 then
        return false
    end

    self._lastGuiActivationKey = toolKey
    self._lastGuiActivationClock = nowClock
    return true
end
function CustomBackpackController:_equipOrUnequipTool(tool, shouldUnequip)
    if not (tool and tool.Parent and tool:IsA("Tool")) then
        return
    end

    local character = localPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid") or nil
    if not humanoid then
        return
    end

    if shouldUnequip == true then
        humanoid:UnequipTools()
    else
        humanoid:EquipTool(tool)
    end

    self:_queueRefresh()
end

function CustomBackpackController:_activateToolEntry(toolEntry, useGuiDebounce)
    if type(toolEntry) ~= "table" then
        return
    end

    if useGuiDebounce and not self:_consumeGuiActivation(toolEntry.key) then
        return
    end

    self:_equipOrUnequipTool(toolEntry.tool, toolEntry.isEquipped == true)
end

function CustomBackpackController:_resolveToolEntryFromGuiObject(guiObject)
    local node = guiObject
    while node and node ~= self._itemListRoot and node ~= self._backpackRoot do
        local toolEntry = self._entryToolEntryByClone[node]
        if type(toolEntry) == "table" then
            return toolEntry
        end
        node = node.Parent
    end

    return nil
end

function CustomBackpackController:_findToolEntryAtScreenPosition(screenPosition)
    if not (screenPosition and self._backpackRoot and self._backpackRoot.Visible) then
        return nil
    end

    local playerGui = self:_getPlayerGui()
    if not playerGui then
        return nil
    end

    local success, guiObjects = pcall(function()
        return playerGui:GetGuiObjectsAtPosition(screenPosition.X, screenPosition.Y)
    end)
    if not success or type(guiObjects) ~= "table" then
        return nil
    end

    for _, guiObject in ipairs(guiObjects) do
        local toolEntry = self:_resolveToolEntryFromGuiObject(guiObject)
        if toolEntry then
            return toolEntry
        end
    end

    return nil
end

function CustomBackpackController:_handlePointerInputEnded(inputObject)
    if UserInputService:GetFocusedTextBox() then
        return
    end

    if not isActivateInput(inputObject) then
        return
    end

    local toolEntry = self:_findToolEntryAtScreenPosition(inputObject.Position)
    if not toolEntry then
        return
    end

    self:_activateToolEntry(toolEntry, true)
end

function CustomBackpackController:_collectInteractiveNodes(clone)
    local nodes = {}
    local seen = {}

    if clone:IsA("GuiObject") then
        appendUniqueGuiObject(nodes, seen, clone)
    else
        appendUniqueGuiObject(nodes, seen, clone:FindFirstChildWhichIsA("GuiObject", true))
    end

    local resolvedNode = resolveInteractiveNode(clone)
    appendUniqueGuiObject(nodes, seen, resolvedNode)

    for _, descendant in ipairs(clone:GetDescendants()) do
        if descendant:IsA("GuiObject") then
            appendUniqueGuiObject(nodes, seen, descendant)
        end
    end

    return nodes
end

function CustomBackpackController:_bindEntry(clone, toolEntry)
    local interactiveNodes = self:_collectInteractiveNodes(clone)
    if #interactiveNodes <= 0 then
        return
    end

    for _, interactiveNode in ipairs(interactiveNodes) do
        if interactiveNode:IsA("GuiButton") then
            interactiveNode.Active = true
            table.insert(self._entryConnections, interactiveNode.Activated:Connect(function()
                self:_activateToolEntry(toolEntry, true)
            end))
            table.insert(self._entryConnections, interactiveNode.MouseButton1Click:Connect(function()
                self:_activateToolEntry(toolEntry, true)
            end))
        elseif interactiveNode:IsA("GuiObject") then
            interactiveNode.Active = true
            table.insert(self._entryConnections, interactiveNode.InputBegan:Connect(function(inputObject)
                if isActivateInput(inputObject) then
                    self:_activateToolEntry(toolEntry, true)
                end
            end))
        end
    end
end

function CustomBackpackController:_isBackpackHiddenByModal()
    return self._modalController
        and self._modalController.IsNodeHiddenByModal
        and self._modalController:IsNodeHiddenByModal(self._backpackRoot) == true
end

function CustomBackpackController:_renderEntries()
    if not (isLiveInstance(self._backpackRoot) and isLiveInstance(self._itemListRoot) and isLiveInstance(self._entryTemplate)) then
        return false
    end

    self:_clearEntryBindings()

    local toolEntries = self:_collectTools()
    self._renderedToolEntries = toolEntries
    local shouldShowBackpack = #toolEntries > 0
    if shouldShowBackpack and self:_isBackpackHiddenByModal() then
        shouldShowBackpack = false
    end
    self._backpackRoot.Visible = shouldShowBackpack

    for index, toolEntry in ipairs(toolEntries) do
        toolEntry.slotIndex = index
        local clone = self._entryTemplate:Clone()
        clone.Name = string.format("BackpackEntry_%d", index)
        clone.Visible = true
        if clone:IsA("GuiObject") then
            clone.LayoutOrder = index
        end

        self:_applyEntryVisual(clone, toolEntry)
        clone.Parent = self._entryTemplate.Parent or self._itemListRoot
        table.insert(self._entryClones, clone)
        self._entryToolEntryByClone[clone] = toolEntry
        self:_bindEntry(clone, toolEntry)
    end

    self:_refreshCanvasSize()
    return true
end

function CustomBackpackController:_handleInputBegan(inputObject, gameProcessedEvent)
    if gameProcessedEvent then
        return
    end

    if UserInputService:GetFocusedTextBox() then
        return
    end

    local slotIndex = SLOT_INDEX_BY_KEY_CODE[inputObject.KeyCode]
    if not slotIndex then
        return
    end

    local toolEntry = self._renderedToolEntries[slotIndex]
    if not toolEntry then
        return
    end

    self:_activateToolEntry(toolEntry, false)
end

function CustomBackpackController:_bindMainUi()
    local mainGui = self:_getMainGui()
    if not mainGui then
        self:_warnOnce("MissingMain", "[CustomBackpackController] 找不到 Main UI，自定义背包未启动。")
        return false
    end

    local backpackRoot = findFirstGuiObjectByName(mainGui, "Backpack")
    local itemListRoot = backpackRoot and findFirstGuiObjectByName(backpackRoot, "ItemListFrame") or nil
    local entryTemplate = itemListRoot and findFirstGuiObjectByName(itemListRoot, "ArmyTemplate") or nil
    if not (backpackRoot and itemListRoot and entryTemplate) then
        self:_warnOnce("MissingBackpackUi", "[CustomBackpackController] 找不到 Main/Backpack/ItemListFrame/ArmyTemplate，自定义背包未绑定。")
        return false
    end

    self._backpackRoot = backpackRoot
    self._itemListRoot = itemListRoot
    self._entryTemplate = entryTemplate
    self._entryTemplate.Visible = false
    self:_ensureCoreBackpackHidden()
    return true
end

function CustomBackpackController:_bindToolWatchers()
    disconnectConnections(self._toolWatcherConnections)

    local function watchContainer(container)
        if not container then
            return
        end

        table.insert(self._toolWatcherConnections, container.ChildAdded:Connect(function(child)
            if child and child:IsA("Tool") then
                self:_queueRefresh()
            end
        end))

        table.insert(self._toolWatcherConnections, container.ChildRemoved:Connect(function(child)
            if child and child:IsA("Tool") then
                self:_queueRefresh()
            end
        end))
    end

    watchContainer(localPlayer:FindFirstChild("Backpack"))
    watchContainer(localPlayer.Character)
end

function CustomBackpackController:_queueRefresh()
    if self._refreshQueued then
        return
    end

    self._refreshQueued = true
    task.defer(function()
        self._refreshQueued = false
        if not self:_bindMainUi() then
            return
        end
        self:_renderEntries()
    end)
end

function CustomBackpackController:_scheduleRefreshBurst(durationSeconds, intervalSeconds)
    local duration = math.max(0, tonumber(durationSeconds) or 0)
    local interval = math.max(0.1, tonumber(intervalSeconds) or 0.5)
    if duration <= 0 then
        self:_queueRefresh()
        return
    end

    self._refreshBurstToken += 1
    local burstToken = self._refreshBurstToken

    task.spawn(function()
        local deadline = os.clock() + duration
        repeat
            if burstToken ~= self._refreshBurstToken then
                return
            end

            self:_queueRefresh()
            task.wait(interval)
        until os.clock() >= deadline
    end)
end

function CustomBackpackController:_queueRebind()
    if self._rebindQueued then
        return
    end

    self._rebindQueued = true
    task.defer(function()
        self._rebindQueued = false
        self:_bindToolWatchers()
        self:_queueRefresh()
        self:_scheduleRetryBind()
        self:_scheduleRefreshBurst(6, 0.5)
    end)
end

function CustomBackpackController:_scheduleRetryBind()
    task.spawn(function()
        local deadline = os.clock() + 12
        repeat
            if self:_bindMainUi() and self:_renderEntries() then
                self:_bindToolWatchers()
                return
            end
            task.wait(1)
        until os.clock() >= deadline
    end)
end

function CustomBackpackController:Start()
    if self._started then
        return
    end
    self._started = true

    table.insert(self._persistentConnections, UserInputService.InputBegan:Connect(function(inputObject, gameProcessedEvent)
        self:_handleInputBegan(inputObject, gameProcessedEvent)
    end))

    table.insert(self._persistentConnections, UserInputService.InputEnded:Connect(function(inputObject)
        self:_handlePointerInputEnded(inputObject)
    end))

    if self._modalController and self._modalController.GetVisibilityChangedEvent then
        local visibilityChangedEvent = self._modalController:GetVisibilityChangedEvent()
        if visibilityChangedEvent then
            table.insert(self._persistentConnections, visibilityChangedEvent:Connect(function()
                self:_queueRefresh()
            end))
        end
    end

    table.insert(self._persistentConnections, localPlayer.CharacterAdded:Connect(function()
        self:_bindToolWatchers()
        self:_queueRefresh()
        self:_scheduleRefreshBurst(6, 0.5)
    end))

    table.insert(self._persistentConnections, localPlayer.ChildAdded:Connect(function(child)
        if child and (child.Name == "Backpack" or child:IsA("Backpack")) then
            self:_queueRebind()
        end
    end))

    local playerGui = self:_getPlayerGui()
    if playerGui then
        table.insert(self._persistentConnections, playerGui.DescendantAdded:Connect(function(descendant)
            if not descendant or not descendant.Name then
                return
            end

            local watchedNames = {
                Backpack = true,
                ItemListFrame = true,
                ArmyTemplate = true,
            }
            if watchedNames[descendant.Name] then
                self:_queueRebind()
            end
        end))
    end

    self:_scheduleRetryBind()
    self:_scheduleRefreshBurst(6, 0.5)
end

return CustomBackpackController
