--[[
脚本名字: HomeExpansionController
脚本文件: HomeExpansionController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/HomeExpansionController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

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
        "[HomeExpansionController] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local GameConfig = requireSharedModule("GameConfig")
local ClientPredictionUtil = requireSharedModule("ClientPredictionUtil")
local FormatUtil = requireSharedModule("FormatUtil")
local RemoteNames = requireSharedModule("RemoteNames")

local HomeExpansionController = {}
HomeExpansionController.__index = HomeExpansionController

local function getHomeExpansionConfig()
    return GameConfig.HOME_EXPANSION or {}
end

local function getUnlockEntries()
    local entries = getHomeExpansionConfig().UnlockEntries
    return type(entries) == "table" and entries or {}
end

local function getMaxExpansionCount()
    return #getUnlockEntries()
end

local function clampExpansionCount(value)
    local maxCount = getMaxExpansionCount()
    return math.clamp(math.max(0, math.floor(tonumber(value) or 0)), 0, maxCount)
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

local function findFirstTextLabelByName(root, name)
    local node = root and findFirstDescendantByNames(root, { name }) or nil
    if node and node:IsA("TextLabel") then
        return node
    end

    if node then
        return node:FindFirstChildWhichIsA("TextLabel", true)
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

function HomeExpansionController.new()
    local self = setmetatable({}, HomeExpansionController)
    self._homeId = tostring(localPlayer:GetAttribute("HomeId") or "")
    self._persistentConnections = {}
    self._bindingConnections = {}
    self._soundTemplateByKey = {}
    self._didWarnMissingSoundByKey = {}
    self._requestHomeExpansionEvent = nil
    self._homeExpansionFeedbackEvent = nil
    self._homeAssignedEvent = nil
    self._lastRequestClock = 0
    self._rebindQueued = false
    self._started = false
    self._baseUpgradeNodes = nil
    self._currentUnlockedExpansionCount = 0
    self._predictedUnlockedExpansionCount = nil
    self._pendingHomeExpansionRequestId = nil
    self._baseUpgradeOriginalTransparencyByInstance = setmetatable({}, { __mode = "k" })
    self._baseUpgradeOriginalEnabledByInstance = setmetatable({}, { __mode = "k" })
    return self
end

function HomeExpansionController:_getPlayerHomesRoot()
    local rootName = tostring((GameConfig.HOME or {}).ContainerName or "PlayerHome")
    return Workspace:FindFirstChild(rootName)
end

function HomeExpansionController:_getAssignedHomeId()
    local attributeHomeId = tostring(localPlayer:GetAttribute("HomeId") or "")
    if attributeHomeId ~= "" then
        self._homeId = attributeHomeId
    end

    return self._homeId
end

function HomeExpansionController:_getAssignedHomeModel()
    local homesRoot = self:_getPlayerHomesRoot()
    local homeId = self:_getAssignedHomeId()
    if not (homesRoot and homeId ~= "") then
        return nil
    end

    return homesRoot:FindFirstChild(homeId)
end

function HomeExpansionController:_clearBindings()
    disconnectConnections(self._bindingConnections)
end


function HomeExpansionController:_findBaseUpgradeNodes(homeModel)
    local homeBase = homeModel and homeModel:FindFirstChild(tostring((GameConfig.HOME or {}).HomeBaseName or "HomeBase")) or nil
    if not homeBase then
        return nil
    end

    local config = GameConfig.HOME_EXPANSION or {}
    local baseUpgradePart = findFirstDescendantByNames(homeBase, {
        tostring(config.BaseUpgradePartName or "BaseUpgrade"),
    })
    if not baseUpgradePart then
        return nil
    end

    local surfaceGui = findFirstDescendantByNames(baseUpgradePart, {
        tostring(config.BaseUpgradeSurfaceGuiName or "SurfaceGui"),
    })
    local frame = findFirstGuiObjectByName(surfaceGui, tostring(config.BaseUpgradeFrameName or "Frame"))
    local moneyRoot = findFirstGuiObjectByName(frame or surfaceGui, tostring(config.BaseUpgradeMoneyRootName or "Money"))
    local innerFrame = findFirstGuiObjectByName(moneyRoot, tostring(config.BaseUpgradeInnerFrameName or "Frame"))
    local currentGoldLabel = findFirstTextLabelByName(innerFrame or moneyRoot, tostring(config.BaseUpgradeCostLabelName or "CurrentGold"))
    local levelLabel = findFirstTextLabelByName(innerFrame or frame or surfaceGui, tostring(config.BaseUpgradeLevelLabelName or "Level"))

    return {
        HomeModel = homeModel,
        HomeBase = homeBase,
        BaseUpgradePart = baseUpgradePart,
        SurfaceGui = surfaceGui,
        Frame = frame,
        MoneyRoot = moneyRoot,
        InnerFrame = innerFrame,
        CurrentGoldLabel = currentGoldLabel,
        LevelLabel = levelLabel,
    }
end

function HomeExpansionController:_setBaseUpgradeVisible(baseUpgradeNodes, isVisible)
    if not baseUpgradeNodes then
        return
    end

    local enabled = isVisible == true
    local baseUpgradePart = baseUpgradeNodes.BaseUpgradePart
    if not baseUpgradePart then
        return
    end

    if baseUpgradePart:IsA("BasePart") then
        baseUpgradePart.LocalTransparencyModifier = enabled and 0 or 1
    end

    local nodes = { baseUpgradePart }
    for _, descendant in ipairs(baseUpgradePart:GetDescendants()) do
        table.insert(nodes, descendant)
    end

    for _, node in ipairs(nodes) do
        if node ~= baseUpgradePart and node:IsA("BasePart") then
            node.LocalTransparencyModifier = enabled and 0 or 1
        elseif node:IsA("Decal") or node:IsA("Texture") then
            if self._baseUpgradeOriginalTransparencyByInstance[node] == nil then
                self._baseUpgradeOriginalTransparencyByInstance[node] = node.Transparency
            end
            node.Transparency = enabled and (tonumber(self._baseUpgradeOriginalTransparencyByInstance[node]) or 0) or 1
        elseif node:IsA("LayerCollector") then
            if self._baseUpgradeOriginalEnabledByInstance[node] == nil then
                self._baseUpgradeOriginalEnabledByInstance[node] = node.Enabled
            end
            node.Enabled = enabled and (self._baseUpgradeOriginalEnabledByInstance[node] ~= false) or false
        end
    end
end

function HomeExpansionController:_estimateUnlockedExpansionCount()
    local homeModel = self:_getAssignedHomeModel()
    if not homeModel then
        return clampExpansionCount(self._currentUnlockedExpansionCount)
    end

    local config = getHomeExpansionConfig()
    local positionPrefix = tostring((GameConfig.BRAINROT or {}).PositionPrefix or "Position")
    local unlockedAttributeName = tostring(config.RuntimeUnlockedAttributeName or "HomeExpansionUnlocked")
    local globalSlotAttributeName = tostring(config.RuntimeGlobalSlotIndexAttributeName or "HomeExpansionGlobalSlotIndex")
    local baseSlotCount = math.max(0, math.floor(tonumber(config.BaseSlotCount) or 10))
    local unlockedSlotsByIndex = {}

    for _, descendant in ipairs(homeModel:GetDescendants()) do
        if string.match(descendant.Name, "^" .. positionPrefix .. "%d+$") then
            local globalSlotIndex = math.max(0, math.floor(tonumber(descendant:GetAttribute(globalSlotAttributeName)) or 0))
            if globalSlotIndex > baseSlotCount and descendant:GetAttribute(unlockedAttributeName) == true then
                unlockedSlotsByIndex[globalSlotIndex] = true
            end
        end
    end

    local unlockedCount = 0
    for _ in pairs(unlockedSlotsByIndex) do
        unlockedCount += 1
    end

    return clampExpansionCount(unlockedCount)
end

function HomeExpansionController:_refreshBaseUpgradeUi()
    local baseUpgradeNodes = self._baseUpgradeNodes
    if not baseUpgradeNodes then
        return
    end

    local unlockedExpansionCount = clampExpansionCount(
        self._predictedUnlockedExpansionCount ~= nil and self._predictedUnlockedExpansionCount or self._currentUnlockedExpansionCount
    )
    local nextEntry = getUnlockEntries()[unlockedExpansionCount + 1]

    if baseUpgradeNodes.CurrentGoldLabel and baseUpgradeNodes.CurrentGoldLabel:IsA("TextLabel") then
        baseUpgradeNodes.CurrentGoldLabel.Text = nextEntry and FormatUtil.FormatWithCommasCeil(nextEntry.UnlockPrice) or "Max"
    end

    if baseUpgradeNodes.LevelLabel and baseUpgradeNodes.LevelLabel:IsA("TextLabel") then
        baseUpgradeNodes.LevelLabel.Text = string.format("%d/%d", unlockedExpansionCount, getMaxExpansionCount())
    end

    local canRequestNextExpansion = nextEntry ~= nil and self._pendingHomeExpansionRequestId == nil
    local moneyRoot = baseUpgradeNodes.MoneyRoot
    if moneyRoot and moneyRoot:IsA("GuiButton") then
        moneyRoot.Active = canRequestNextExpansion
        moneyRoot.AutoButtonColor = canRequestNextExpansion
        moneyRoot.Selectable = canRequestNextExpansion
    elseif moneyRoot and moneyRoot:IsA("GuiObject") then
        moneyRoot.Active = canRequestNextExpansion
    end
end

function HomeExpansionController:_rollbackPendingHomeExpansion(request, shouldQueueRebind)
    self._pendingHomeExpansionRequestId = nil
    self._predictedUnlockedExpansionCount = nil

    if request and request.Metadata and request.Metadata.previousUnlockedExpansionCount ~= nil then
        self._currentUnlockedExpansionCount = clampExpansionCount(request.Metadata.previousUnlockedExpansionCount)
    else
        self._currentUnlockedExpansionCount = self:_estimateUnlockedExpansionCount()
    end

    self:_refreshBaseUpgradeUi()
    if shouldQueueRebind == true then
        self:_queueRebind()
    end
end

function HomeExpansionController:_refreshBaseUpgradeVisibility()
    local homesRoot = self:_getPlayerHomesRoot()
    if not homesRoot then
        return false
    end

    local assignedHomeId = self:_getAssignedHomeId()
    local foundAssignedHome = false

    for _, homeModel in ipairs(homesRoot:GetChildren()) do
        local baseUpgradeNodes = self:_findBaseUpgradeNodes(homeModel)
        if baseUpgradeNodes then
            local isAssignedHome = assignedHomeId ~= "" and homeModel.Name == assignedHomeId
            self:_setBaseUpgradeVisible(baseUpgradeNodes, isAssignedHome)
            if isAssignedHome then
                foundAssignedHome = true
            end
        end
    end

    return foundAssignedHome
end

function HomeExpansionController:_resolveInteractiveNode(node)
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

function HomeExpansionController:_requestHomeExpansion()
    if self._pendingHomeExpansionRequestId ~= nil then
        return
    end
    if not (self._requestHomeExpansionEvent and self._requestHomeExpansionEvent:IsA("RemoteEvent")) then
        return
    end

    local debounceSeconds = math.max(0.05, tonumber(getHomeExpansionConfig().RequestDebounceSeconds) or 0.2)
    local nowClock = os.clock()
    if nowClock - self._lastRequestClock < debounceSeconds then
        return
    end

    self._currentUnlockedExpansionCount = self:_estimateUnlockedExpansionCount()
    local nextEntry = getUnlockEntries()[self._currentUnlockedExpansionCount + 1]
    if not nextEntry then
        self:_refreshBaseUpgradeUi()
        return
    end

    local requestId = ClientPredictionUtil:BeginRequest({
        key = "HomeExpansionUnlock",
        prefix = "HomeExpansionUnlock",
        coinDelta = -math.max(0, tonumber(nextEntry.UnlockPrice) or 0),
        timeoutSeconds = 5,
        metadata = {
            previousUnlockedExpansionCount = self._currentUnlockedExpansionCount,
        },
        onTimeout = function(request)
            self:_rollbackPendingHomeExpansion(request, true)
        end,
    })
    if not requestId then
        return
    end

    self._lastRequestClock = nowClock
    self._pendingHomeExpansionRequestId = requestId
    self._predictedUnlockedExpansionCount = clampExpansionCount(self._currentUnlockedExpansionCount + 1)
    self:_refreshBaseUpgradeUi()
    self._requestHomeExpansionEvent:FireServer({
        requestId = requestId,
    })
end

function HomeExpansionController:_bindMoneyClick(node)
    local interactiveNode = self:_resolveInteractiveNode(node)
    if not interactiveNode then
        return
    end

    if interactiveNode:IsA("GuiButton") then
        table.insert(self._bindingConnections, interactiveNode.Activated:Connect(function()
            self:_requestHomeExpansion()
        end))
        return
    end

    if interactiveNode:IsA("GuiObject") then
        interactiveNode.Active = true
        table.insert(self._bindingConnections, interactiveNode.InputBegan:Connect(function(inputObject)
            if isUpgradeInput(inputObject) then
                self:_requestHomeExpansion()
            end
        end))
    end
end

function HomeExpansionController:_bindHomeBaseUpgrade()
    self:_clearBindings()
    self:_refreshBaseUpgradeVisibility()

    local homeModel = self:_getAssignedHomeModel()
    local baseUpgradeNodes = self:_findBaseUpgradeNodes(homeModel)
    self._baseUpgradeNodes = baseUpgradeNodes
    self._currentUnlockedExpansionCount = self:_estimateUnlockedExpansionCount()
    self:_refreshBaseUpgradeUi()
    local moneyRoot = baseUpgradeNodes and baseUpgradeNodes.MoneyRoot or nil
    if not moneyRoot then
        return false
    end

    self:_bindMoneyClick(moneyRoot)
    return true
end

function HomeExpansionController:_queueRebind()
    if self._rebindQueued then
        return
    end

    self._rebindQueued = true
    task.defer(function()
        self._rebindQueued = false
        self:_refreshBaseUpgradeVisibility()
        self:_scheduleRetryBind()
    end)
end

function HomeExpansionController:_scheduleRetryBind()
    task.spawn(function()
        local deadline = os.clock() + 12
        repeat
            if self:_bindHomeBaseUpgrade() then
                return
            end
            task.wait(1)
        until os.clock() >= deadline
    end)
end

function HomeExpansionController:_getSoundTemplate(cacheKey, templateName, assetId)
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
        warn(string.format("[HomeExpansionController] 找不到 SoundService/Audio/%s，使用回退音频资源。", tostring(templateName)))
        self._didWarnMissingSoundByKey[cacheKey] = true
    end

    local fallbackName = string.format("_HomeExpansion%sFallback", cacheKey)
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

function HomeExpansionController:_playSound(cacheKey, templateName, assetId)
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

function HomeExpansionController:_playWrongSound()
    self:_playSound(
        "Wrong",
        tostring((GameConfig.HOME_EXPANSION or {}).FeedbackWrongSoundTemplateName or "Wrong"),
        tostring((GameConfig.HOME_EXPANSION or {}).FeedbackWrongSoundAssetId or "rbxassetid://118029437877580")
    )
end

function HomeExpansionController:_handleHomeExpansionFeedback(payload)
    if type(payload) ~= "table" then
        return
    end

    local status = tostring(payload.status or "")
    local requestId = tostring(payload.requestId or self._pendingHomeExpansionRequestId or "")
    if payload.unlockedExpansionCount ~= nil then
        self._currentUnlockedExpansionCount = clampExpansionCount(payload.unlockedExpansionCount)
    else
        self._currentUnlockedExpansionCount = self:_estimateUnlockedExpansionCount()
    end

    if status == "Success" or status == "SaveFailed" then
        if requestId ~= "" then
            ClientPredictionUtil:ResolveRequest(requestId, {
                acknowledgeCoinDelta = true,
                authoritativeCoins = payload.currentCoins,
            })
        end
        if requestId == self._pendingHomeExpansionRequestId then
            self._pendingHomeExpansionRequestId = nil
        end
        self._predictedUnlockedExpansionCount = nil
        self:_refreshBaseUpgradeUi()
        return
    end

    local rejectedRequest = nil
    if requestId ~= "" then
        rejectedRequest = ClientPredictionUtil:RejectRequest(requestId, {
            authoritativeCoins = payload.currentCoins,
        })
    end

    if requestId == self._pendingHomeExpansionRequestId then
        self:_rollbackPendingHomeExpansion(rejectedRequest, false)
    else
        self._predictedUnlockedExpansionCount = nil
        self:_refreshBaseUpgradeUi()
    end

    if status ~= "" and status ~= "Success" then
        self:_playWrongSound()
    end
end

function HomeExpansionController:Start()
    if self._started then
        return
    end
    self._started = true

    local eventsRoot = ReplicatedStorage:WaitForChild(RemoteNames.RootFolder)
    local systemEvents = eventsRoot:WaitForChild(RemoteNames.SystemEventsFolder)

    self._requestHomeExpansionEvent = systemEvents:FindFirstChild(RemoteNames.System.RequestHomeExpansion)
        or systemEvents:WaitForChild(RemoteNames.System.RequestHomeExpansion, 10)
    self._homeExpansionFeedbackEvent = systemEvents:FindFirstChild(RemoteNames.System.HomeExpansionFeedback)
        or systemEvents:WaitForChild(RemoteNames.System.HomeExpansionFeedback, 10)
    self._homeAssignedEvent = systemEvents:FindFirstChild(RemoteNames.System.HomeAssigned)
        or systemEvents:WaitForChild(RemoteNames.System.HomeAssigned, 10)

    if self._homeExpansionFeedbackEvent and self._homeExpansionFeedbackEvent:IsA("RemoteEvent") then
        table.insert(self._persistentConnections, self._homeExpansionFeedbackEvent.OnClientEvent:Connect(function(payload)
            self:_handleHomeExpansionFeedback(payload)
        end))
    end

    if self._homeAssignedEvent and self._homeAssignedEvent:IsA("RemoteEvent") then
        table.insert(self._persistentConnections, self._homeAssignedEvent.OnClientEvent:Connect(function(payload)
            local homeId = type(payload) == "table" and tostring(payload.homeId or "") or ""
            if homeId ~= "" then
                self._homeId = homeId
                self:_refreshBaseUpgradeVisibility()
                self:_queueRebind()
            end
        end))
    end

    table.insert(self._persistentConnections, localPlayer:GetAttributeChangedSignal("HomeId"):Connect(function()
        self._homeId = tostring(localPlayer:GetAttribute("HomeId") or "")
        self:_refreshBaseUpgradeVisibility()
        self:_queueRebind()
    end))

    table.insert(self._persistentConnections, Workspace.DescendantAdded:Connect(function(descendant)
        local config = GameConfig.HOME_EXPANSION or {}
        local watchedNames = {
            [tostring(config.BaseUpgradePartName or "BaseUpgrade")] = true,
            [tostring(config.BaseUpgradeMoneyRootName or "Money")] = true,
            [tostring(config.BaseUpgradeSurfaceGuiName or "SurfaceGui")] = true,
        }
        if descendant and watchedNames[descendant.Name] then
            self:_refreshBaseUpgradeVisibility()
            self:_queueRebind()
        end
    end))

    self:_refreshBaseUpgradeVisibility()
    self:_scheduleRetryBind()
end

return HomeExpansionController
