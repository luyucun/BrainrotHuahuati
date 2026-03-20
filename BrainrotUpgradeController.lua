--[[
脚本名字: BrainrotUpgradeController
脚本文件: BrainrotUpgradeController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/BrainrotUpgradeController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
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
        "[BrainrotUpgradeController] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local GameConfig = requireSharedModule("GameConfig")
local RemoteNames = requireSharedModule("RemoteNames")

local BrainrotUpgradeController = {}
BrainrotUpgradeController.__index = BrainrotUpgradeController

local function parseTrailingIndex(name, prefix)
    if type(name) ~= "string" or type(prefix) ~= "string" then
        return nil
    end

    local numberText = string.match(name, "^" .. prefix .. "(%d+)$")
    if not numberText then
        return nil
    end

    return tonumber(numberText)
end

local function findHomeExpansionAttribute(instance, attributeName)
    if not (instance and type(attributeName) == "string" and attributeName ~= "") then
        return nil, nil
    end

    local current = instance
    while current do
        local attributeValue = current:GetAttribute(attributeName)
        if attributeValue ~= nil then
            return attributeValue, current
        end
        current = current.Parent
    end

    return nil, nil
end

local function getExpandedPositionKeyFromInstance(instance)
    local expansionConfig = GameConfig.HOME_EXPANSION or {}
    local positionKeyAttributeName = tostring(expansionConfig.RuntimePositionKeyAttributeName or "HomeExpansionPositionKey")
    local positionKey = select(1, findHomeExpansionAttribute(instance, positionKeyAttributeName))
    if type(positionKey) == "string" and positionKey ~= "" then
        return positionKey
    end

    return nil
end

local function buildExpandedPositionKey(localSlotIndex, instance)
    local resolvedLocalSlotIndex = math.floor(tonumber(localSlotIndex) or 0)
    if resolvedLocalSlotIndex <= 0 then
        return nil
    end

    local expansionConfig = GameConfig.HOME_EXPANSION or {}
    local floorLevelAttributeName = tostring(expansionConfig.RuntimeFloorLevelAttributeName or "HomeExpansionFloorLevel")
    local localSlotAttributeName = tostring(expansionConfig.RuntimeLocalSlotIndexAttributeName or "HomeExpansionLocalSlotIndex")
    local slotsPerFloor = math.max(1, math.floor(tonumber(expansionConfig.SlotsPerFloor) or 10))
    local resolvedFloorLevel = math.max(1, math.floor(tonumber(select(1, findHomeExpansionAttribute(instance, floorLevelAttributeName)) or 1)))
    local attributedLocalSlotIndex = math.floor(tonumber(select(1, findHomeExpansionAttribute(instance, localSlotAttributeName)) or resolvedLocalSlotIndex))
    if attributedLocalSlotIndex > 0 then
        resolvedLocalSlotIndex = attributedLocalSlotIndex
    end

    local positionPrefix = tostring((GameConfig.BRAINROT or {}).PositionPrefix or "Position")
    return string.format("%s%d", positionPrefix, ((resolvedFloorLevel - 1) * slotsPerFloor) + resolvedLocalSlotIndex)
end

local function resolveHomeSlotPositionKey(instance, namePrefix, fallbackInstance)
    local directPositionKey = getExpandedPositionKeyFromInstance(instance)
    if directPositionKey then
        return directPositionKey
    end

    if fallbackInstance then
        local fallbackPositionKey = getExpandedPositionKeyFromInstance(fallbackInstance)
        if fallbackPositionKey then
            return fallbackPositionKey
        end
    end

    local localSlotIndex = parseTrailingIndex(instance and instance.Name or nil, namePrefix)
    if not localSlotIndex and fallbackInstance then
        localSlotIndex = parseTrailingIndex(fallbackInstance.Name, namePrefix)
    end
    if not localSlotIndex then
        return nil
    end

    return buildExpandedPositionKey(localSlotIndex, fallbackInstance or instance)
end

local function isHomeSlotUnlocked(instance)
    local expansionConfig = GameConfig.HOME_EXPANSION or {}
    local unlockedAttributeName = tostring(expansionConfig.RuntimeUnlockedAttributeName or "HomeExpansionUnlocked")
    local unlockedValue = select(1, findHomeExpansionAttribute(instance, unlockedAttributeName))
    if unlockedValue == nil then
        return true
    end

    return unlockedValue == true
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

local function findFirstImageLabelByName(root, name)
    local node = root and findFirstDescendantByNames(root, { name }) or nil
    if node and node:IsA("ImageLabel") then
        return node
    end

    if node then
        return node:FindFirstChildWhichIsA("ImageLabel", true)
    end

    return nil
end

local function disconnectConnections(connectionList)
    for _, connection in ipairs(connectionList) do
        if connection then
            connection:Disconnect()
        end
    end
    table.clear(connectionList)
end

local function isUpgradeInput(inputObject)
    if not inputObject then
        return false
    end

    return inputObject.UserInputType == Enum.UserInputType.MouseButton1
        or inputObject.UserInputType == Enum.UserInputType.Touch
end

local function collectGuiObjects(root)
    local nodes = {}
    local seen = {}

    local function addNode(node)
        if not (node and node:IsA("GuiObject")) then
            return
        end

        if seen[node] then
            return
        end

        seen[node] = true
        table.insert(nodes, node)
    end

    addNode(root)
    if root then
        for _, descendant in ipairs(root:GetDescendants()) do
            addNode(descendant)
        end
    end

    return nodes
end

function BrainrotUpgradeController.new()
    local self = setmetatable({}, BrainrotUpgradeController)
    self._homeId = tostring(localPlayer:GetAttribute("HomeId") or "")
    self._brandConnections = {}
    self._persistentConnections = {}
    self._arrowStateByArrow = {}
    self._brandPositionKeyByInstance = setmetatable({}, { __mode = "k" })
    self._brandPositionKeyByGuiObject = setmetatable({}, { __mode = "k" })
    self._soundTemplateByKey = {}
    self._didWarnMissingSoundByKey = {}
    self._lastRequestClockByPositionKey = {}
    self._requestUpgradeEvent = nil
    self._feedbackEvent = nil
    self._homeAssignedEvent = nil
    self._rebindQueued = false
    self._started = false
    return self
end

function BrainrotUpgradeController:_getPlayerHomesRoot()
    local rootName = tostring((GameConfig.HOME or {}).ContainerName or "PlayerHome")
    return Workspace:FindFirstChild(rootName)
end

function BrainrotUpgradeController:_getAssignedHomeId()
    local attributeHomeId = tostring(localPlayer:GetAttribute("HomeId") or "")
    if attributeHomeId ~= "" then
        self._homeId = attributeHomeId
    end

    return self._homeId
end

function BrainrotUpgradeController:_getAssignedHomeModel()
    local homesRoot = self:_getPlayerHomesRoot()
    local homeId = self:_getAssignedHomeId()
    if not (homesRoot and homeId ~= "") then
        return nil
    end

    return homesRoot:FindFirstChild(homeId)
end

function BrainrotUpgradeController:_stopArrowAnimation(arrow)
    local state = self._arrowStateByArrow[arrow]
    if not state then
        return
    end

    self._arrowStateByArrow[arrow] = nil
    if state.Tween then
        state.Tween:Cancel()
        state.Tween = nil
    end

    if arrow and arrow.Parent and state.BasePosition then
        arrow.Position = state.BasePosition
    end
end

function BrainrotUpgradeController:_clearArrowAnimations()
    for arrow in pairs(self._arrowStateByArrow) do
        self:_stopArrowAnimation(arrow)
    end
end

function BrainrotUpgradeController:_startArrowAnimation(arrow)
    if not (arrow and arrow:IsA("GuiObject")) then
        return
    end

    if self._arrowStateByArrow[arrow] then
        return
    end

    local offset = math.max(2, math.floor(tonumber((GameConfig.BRAINROT or {}).BrandArrowFloatOffset) or 8))
    local duration = math.max(0.2, tonumber((GameConfig.BRAINROT or {}).BrandArrowFloatDuration) or 0.9)
    local basePosition = arrow.Position
    local state = {
        BasePosition = basePosition,
        Tween = nil,
    }
    self._arrowStateByArrow[arrow] = state

    task.spawn(function()
        local targets = {
            UDim2.new(basePosition.X.Scale, basePosition.X.Offset, basePosition.Y.Scale, basePosition.Y.Offset - offset),
            UDim2.new(basePosition.X.Scale, basePosition.X.Offset, basePosition.Y.Scale, basePosition.Y.Offset + offset),
        }
        local targetIndex = 1

        while self._arrowStateByArrow[arrow] == state and arrow.Parent do
            local tween = TweenService:Create(arrow, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
                Position = targets[targetIndex],
            })
            state.Tween = tween
            tween:Play()
            tween.Completed:Wait()
            targetIndex = targetIndex == 1 and 2 or 1
        end

        if self._arrowStateByArrow[arrow] == nil and arrow.Parent then
            arrow.Position = basePosition
        end
    end)
end

function BrainrotUpgradeController:_getSoundTemplate(cacheKey, templateName, assetId)
    local cached = self._soundTemplateByKey[cacheKey]
    if cached and cached.Parent then
        return cached
    end

    local audioRoot = SoundService:FindFirstChild("Audio")
    local soundTemplate = audioRoot and (audioRoot:FindFirstChild(templateName) or audioRoot:FindFirstChild(templateName, true)) or nil
    if soundTemplate and soundTemplate:IsA("Sound") then
        self._soundTemplateByKey[cacheKey] = soundTemplate
        return soundTemplate
    end

    if not self._didWarnMissingSoundByKey[cacheKey] then
        warn(string.format("[BrainrotUpgradeController] 找不到 SoundService/Audio/%s，使用回退音频资源。", tostring(templateName)))
        self._didWarnMissingSoundByKey[cacheKey] = true
    end

    local fallbackName = string.format("_BrainrotUpgrade%sFallback", cacheKey)
    local fallbackSound = SoundService:FindFirstChild(fallbackName)
    if not (fallbackSound and fallbackSound:IsA("Sound")) then
        fallbackSound = Instance.new("Sound")
        fallbackSound.Name = fallbackName
        fallbackSound.SoundId = tostring(assetId or "")
        fallbackSound.Volume = 1
        fallbackSound.Parent = SoundService
    end

    self._soundTemplateByKey[cacheKey] = fallbackSound
    return fallbackSound
end

function BrainrotUpgradeController:_playSound(cacheKey, templateName, assetId)
    local template = self:_getSoundTemplate(cacheKey, templateName, assetId)
    if not template then
        return
    end

    local soundToPlay = template:Clone()
    soundToPlay.Looped = false
    soundToPlay.Parent = template.Parent or SoundService
    if soundToPlay.SoundId == "" then
        soundToPlay.SoundId = tostring(assetId or "")
    end
    soundToPlay:Play()

    task.delay(3, function()
        if soundToPlay and soundToPlay.Parent then
            soundToPlay:Destroy()
        end
    end)
end

function BrainrotUpgradeController:_playSuccessSound()
    self:_playSound(
        "Success",
        tostring((GameConfig.BRAINROT or {}).UpgradeSuccessSoundTemplateName or "MoneyTouch"),
        tostring((GameConfig.BRAINROT or {}).UpgradeSuccessSoundAssetId or "rbxassetid://72535887807534")
    )
end

function BrainrotUpgradeController:_playWrongSound()
    self:_playSound(
        "Wrong",
        tostring((GameConfig.BRAINROT or {}).UpgradeWrongSoundTemplateName or "Wrong"),
        tostring((GameConfig.BRAINROT or {}).UpgradeWrongSoundAssetId or "rbxassetid://118029437877580")
    )
end

function BrainrotUpgradeController:_requestUpgrade(positionKey)
    if not (self._requestUpgradeEvent and self._requestUpgradeEvent:IsA("RemoteEvent")) then
        return
    end

    local debounceSeconds = math.max(0.05, tonumber((GameConfig.BRAINROT or {}).UpgradeRequestDebounceSeconds) or 0.2)
    local nowClock = os.clock()
    local lastClock = tonumber(self._lastRequestClockByPositionKey[positionKey]) or 0
    if nowClock - lastClock < debounceSeconds then
        return
    end

    self._lastRequestClockByPositionKey[positionKey] = nowClock
    self._requestUpgradeEvent:FireServer({
        positionKey = positionKey,
    })
end

function BrainrotUpgradeController:_bindBrandClick(positionKey, frame)
    if not frame then
        return
    end

    local guiNodes = collectGuiObjects(frame)
    for _, node in ipairs(guiNodes) do
        if node:IsA("GuiButton") then
            table.insert(self._brandConnections, node.Activated:Connect(function()
                self:_requestUpgrade(positionKey)
            end))
        else
            node.Active = true
            table.insert(self._brandConnections, node.InputBegan:Connect(function(inputObject)
                if isUpgradeInput(inputObject) then
                    self:_requestUpgrade(positionKey)
                end
            end))
        end
    end
end
function BrainrotUpgradeController:_bindBrandDetector(positionKey, brandPart)
    if not (brandPart and brandPart:IsA("BasePart")) then
        return
    end

    local detector = brandPart:FindFirstChild("__BrandUpgradeClickDetector")
    if not (detector and detector:IsA("ClickDetector")) then
        detector = Instance.new("ClickDetector")
        detector.Name = "__BrandUpgradeClickDetector"
        detector.Parent = brandPart
    end

    detector.MaxActivationDistance = 64
    table.insert(self._brandConnections, detector.MouseClick:Connect(function(playerWhoClicked)
        if playerWhoClicked and playerWhoClicked ~= localPlayer then
            return
        end
        self:_requestUpgrade(positionKey)
    end))
end


function BrainrotUpgradeController:_resolveBrandPositionKeyFromInstance(instance)
    local current = instance
    while current do
        local positionKey = self._brandPositionKeyByInstance[current]
        if type(positionKey) == "string" and positionKey ~= "" then
            return positionKey
        end
        current = current.Parent
    end

    return nil
end

function BrainrotUpgradeController:_getInputScreenPosition(inputObject)
    if inputObject and inputObject.Position then
        return Vector2.new(inputObject.Position.X, inputObject.Position.Y)
    end

    local mousePosition = UserInputService:GetMouseLocation()
    return Vector2.new(mousePosition.X, mousePosition.Y)
end

function BrainrotUpgradeController:_registerBrandGuiObjects(positionKey, surfaceGui, frame)
    if type(positionKey) ~= "string" or positionKey == "" then
        return
    end

    local seen = {}
    local function registerNode(node)
        if not (node and node:IsA("GuiObject")) then
            return
        end

        if seen[node] then
            return
        end

        seen[node] = true
        self._brandPositionKeyByGuiObject[node] = positionKey
    end

    registerNode(frame)

    local root = surfaceGui or frame
    if root then
        for _, descendant in ipairs(root:GetDescendants()) do
            registerNode(descendant)
        end
    end
end

function BrainrotUpgradeController:_tryRequestUpgradeFromGuiHit(inputObject)
    local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui") or localPlayer:FindFirstChild("PlayerGui")
    if not playerGui then
        return false
    end

    local screenPosition = self:_getInputScreenPosition(inputObject)
    local guiObjects = playerGui:GetGuiObjectsAtPosition(screenPosition.X, screenPosition.Y)
    for _, guiObject in ipairs(guiObjects) do
        local positionKey = self._brandPositionKeyByGuiObject[guiObject]
        if type(positionKey) == "string" and positionKey ~= "" then
            self:_requestUpgrade(positionKey)
            return true
        end
    end

    return false
end

function BrainrotUpgradeController:_tryRequestUpgradeFromWorldHit(inputObject)
    local camera = Workspace.CurrentCamera
    if not camera then
        return
    end

    local screenPosition = self:_getInputScreenPosition(inputObject)
    local ray = camera:ViewportPointToRay(screenPosition.X, screenPosition.Y)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude

    local filterList = {}
    if localPlayer.Character then
        table.insert(filterList, localPlayer.Character)
    end
    raycastParams.FilterDescendantsInstances = filterList

    local result = Workspace:Raycast(ray.Origin, ray.Direction * 512, raycastParams)
    local hitInstance = result and result.Instance or nil
    local positionKey = self:_resolveBrandPositionKeyFromInstance(hitInstance)
    if positionKey then
        self:_requestUpgrade(positionKey)
    end
end

function BrainrotUpgradeController:_handleGlobalInputBegan(inputObject, _gameProcessedEvent)
    if not isUpgradeInput(inputObject) then
        return
    end

    if UserInputService:GetFocusedTextBox() then
        return
    end

    if self:_tryRequestUpgradeFromGuiHit(inputObject) then
        return
    end

    self:_tryRequestUpgradeFromWorldHit(inputObject)
end

function BrainrotUpgradeController:_bindHomeBrands()
    self:_clearBrandBindings()
    self._brandPositionKeyByInstance = setmetatable({}, { __mode = "k" })
    self._brandPositionKeyByGuiObject = setmetatable({}, { __mode = "k" })

    local homeModel = self:_getAssignedHomeModel()
    local homeBase = homeModel and homeModel:FindFirstChild(tostring((GameConfig.HOME or {}).HomeBaseName or "HomeBase")) or nil
    if not homeBase then
        return false
    end

    local brandPrefix = tostring((GameConfig.BRAINROT or {}).BrandPrefix or "Brand")
    local surfaceGuiName = tostring((GameConfig.BRAINROT or {}).BrandSurfaceGuiName or "SurfaceGui")
    local frameName = tostring((GameConfig.BRAINROT or {}).BrandFrameName or "Frame")
    local arrowName = tostring((GameConfig.BRAINROT or {}).BrandArrowName or "Arrow")

    local foundAny = false
    for _, descendant in ipairs(homeModel:GetDescendants()) do
        local brandIndex = descendant:IsA("BasePart") and parseTrailingIndex(descendant.Name, brandPrefix) or nil
        if brandIndex and isHomeSlotUnlocked(descendant) then
            local positionKey = resolveHomeSlotPositionKey(descendant, brandPrefix, descendant)
            if positionKey then
                foundAny = true
                local surfaceGui = descendant:FindFirstChild(surfaceGuiName)
                if not (surfaceGui and surfaceGui:IsA("SurfaceGui")) then
                    local nestedSurfaceGui = descendant:FindFirstChild(surfaceGuiName, true)
                    if nestedSurfaceGui and nestedSurfaceGui:IsA("SurfaceGui") then
                        surfaceGui = nestedSurfaceGui
                    else
                        surfaceGui = descendant:FindFirstChildWhichIsA("SurfaceGui", true)
                    end
                end
                if surfaceGui then
                    pcall(function()
                        surfaceGui.Active = true
                    end)
                end
                self._brandPositionKeyByInstance[descendant] = positionKey

                local frame = findFirstGuiObjectByName(surfaceGui, frameName)
                self:_bindBrandDetector(positionKey, descendant)
                self:_registerBrandGuiObjects(positionKey, surfaceGui, frame)
                local arrow = findFirstImageLabelByName(frame or surfaceGui, arrowName)
                self:_bindBrandClick(positionKey, frame)
                if arrow then
                    self:_startArrowAnimation(arrow)
                end
            end
        end
    end

    return foundAny
end

function BrainrotUpgradeController:_clearBrandBindings()
    disconnectConnections(self._brandConnections)
    self:_clearArrowAnimations()
end

function BrainrotUpgradeController:_queueRebind()
    if self._rebindQueued then
        return
    end

    self._rebindQueued = true
    task.defer(function()
        self._rebindQueued = false
        self:_scheduleRetryBind()
    end)
end

function BrainrotUpgradeController:_scheduleRetryBind()
    task.spawn(function()
        local deadline = os.clock() + 12
        repeat
            if self:_bindHomeBrands() then
                return
            end
            task.wait(1)
        until os.clock() >= deadline
    end)
end

function BrainrotUpgradeController:Start()
    if self._started then
        return
    end
    self._started = true

    local eventsRoot = ReplicatedStorage:WaitForChild(RemoteNames.RootFolder)
    local brainrotEvents = eventsRoot:WaitForChild(RemoteNames.BrainrotEventsFolder)
    local systemEvents = eventsRoot:WaitForChild(RemoteNames.SystemEventsFolder)

    self._requestUpgradeEvent = brainrotEvents:FindFirstChild(RemoteNames.Brainrot.RequestBrainrotUpgrade)
        or brainrotEvents:WaitForChild(RemoteNames.Brainrot.RequestBrainrotUpgrade, 10)
    self._feedbackEvent = brainrotEvents:FindFirstChild(RemoteNames.Brainrot.BrainrotUpgradeFeedback)
        or brainrotEvents:WaitForChild(RemoteNames.Brainrot.BrainrotUpgradeFeedback, 10)
    self._homeAssignedEvent = systemEvents:FindFirstChild(RemoteNames.System.HomeAssigned)
        or systemEvents:WaitForChild(RemoteNames.System.HomeAssigned, 10)

    if self._feedbackEvent and self._feedbackEvent:IsA("RemoteEvent") then
        table.insert(self._persistentConnections, self._feedbackEvent.OnClientEvent:Connect(function(payload)
            local status = type(payload) == "table" and tostring(payload.status or "") or ""
            if status == "Success" then
                self:_playSuccessSound()
            elseif status == "NotEnoughCoins" then
                self:_playWrongSound()
            end
        end))
    end

    if self._homeAssignedEvent and self._homeAssignedEvent:IsA("RemoteEvent") then
        table.insert(self._persistentConnections, self._homeAssignedEvent.OnClientEvent:Connect(function(payload)
            local homeId = type(payload) == "table" and tostring(payload.homeId or "") or ""
            if homeId ~= "" then
                self._homeId = homeId
                self:_queueRebind()
            end
        end))
    end

    table.insert(self._persistentConnections, localPlayer:GetAttributeChangedSignal("HomeId"):Connect(function()
        self._homeId = tostring(localPlayer:GetAttribute("HomeId") or "")
        self:_queueRebind()
    end))

    table.insert(self._persistentConnections, UserInputService.InputBegan:Connect(function(inputObject, gameProcessedEvent)
        self:_handleGlobalInputBegan(inputObject, gameProcessedEvent)
    end))

    table.insert(self._persistentConnections, Workspace.DescendantAdded:Connect(function(descendant)
        if descendant and descendant.Name then
            local brandPrefix = tostring((GameConfig.BRAINROT or {}).BrandPrefix or "Brand")
            if string.match(descendant.Name, "^" .. brandPrefix .. "%d+$") then
                self:_queueRebind()
            end
        end
    end))

    self:_scheduleRetryBind()
end

return BrainrotUpgradeController
