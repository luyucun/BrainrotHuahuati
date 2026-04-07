--[[
脚本名字: HomeExpansionService
脚本文件: HomeExpansionService.lua
脚本类型: ModuleScript
Studio放置路径: ServerScriptService/Services/HomeExpansionService
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
        "[HomeExpansionService] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local GameConfig = requireSharedModule("GameConfig")
local FormatUtil = requireSharedModule("FormatUtil")

local HomeExpansionService = {}
HomeExpansionService._playerDataService = nil
HomeExpansionService._homeService = nil
HomeExpansionService._currencyService = nil
HomeExpansionService._remoteEventService = nil
HomeExpansionService._brainrotService = nil
HomeExpansionService._requestHomeExpansionEvent = nil
HomeExpansionService._homeExpansionFeedbackEvent = nil
HomeExpansionService._lastRequestClockByUserId = {}
HomeExpansionService._didWarnMissingStaticFloorByLevel = {}

local ORIGINAL_TRANSPARENCY_ATTRIBUTE = "HomeExpansionOriginalTransparency"
local ORIGINAL_CAN_COLLIDE_ATTRIBUTE = "HomeExpansionOriginalCanCollide"
local ORIGINAL_CAN_TOUCH_ATTRIBUTE = "HomeExpansionOriginalCanTouch"
local ORIGINAL_CAN_QUERY_ATTRIBUTE = "HomeExpansionOriginalCanQuery"
local ORIGINAL_ENABLED_ATTRIBUTE = "HomeExpansionOriginalEnabled"
local ORIGINAL_DECAL_TRANSPARENCY_ATTRIBUTE = "HomeExpansionOriginalDecalTransparency"

local function ensureTable(parentTable, key)
    if type(parentTable[key]) ~= "table" then
        parentTable[key] = {}
    end

    return parentTable[key]
end

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

local function getInstancePivotCFrame(instance)
    if not instance then
        return nil
    end

    if instance:IsA("Model") then
        local primaryPart = instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
        if not primaryPart then
            return nil
        end

        instance.PrimaryPart = primaryPart
        return instance:GetPivot()
    end

    if instance:IsA("BasePart") then
        return instance.CFrame
    end

    local firstPart = instance:FindFirstChildWhichIsA("BasePart", true)
    if firstPart then
        return firstPart.CFrame
    end

    return nil
end

local function setInstancePivotCFrame(instance, targetCFrame)
    if not (instance and targetCFrame) then
        return
    end

    if instance:IsA("Model") then
        instance:PivotTo(targetCFrame)
        return
    end

    if instance:IsA("BasePart") then
        instance.CFrame = targetCFrame
        return
    end

    local currentPivot = getInstancePivotCFrame(instance)
    if not currentPivot then
        return
    end

    local delta = targetCFrame * currentPivot:Inverse()
    for _, descendant in ipairs(instance:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.CFrame = delta * descendant.CFrame
        end
    end
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

local function getHomeExpansionConfig()
    return GameConfig.HOME_EXPANSION or {}
end

local function getUnlockEntries()
    local entries = getHomeExpansionConfig().UnlockEntries
    if type(entries) ~= "table" then
        return {}
    end

    return entries
end

local function getMaxExpansionCount()
    return #getUnlockEntries()
end

local function clampExpansionCount(value)
    return math.clamp(math.max(0, math.floor(tonumber(value) or 0)), 0, getMaxExpansionCount())
end

function HomeExpansionService:_getOrCreateHomeState(player)
    if not self._playerDataService then
        return nil
    end

    local playerData = self._playerDataService:GetPlayerData(player)
    if type(playerData) ~= "table" then
        return nil
    end

    local homeState = ensureTable(playerData, "HomeState")
    homeState.HomeId = tostring(homeState.HomeId or "")
    if type(homeState.PlacedBrainrots) ~= "table" then
        homeState.PlacedBrainrots = {}
    end
    if type(homeState.ProductionState) ~= "table" then
        homeState.ProductionState = {}
    end
    homeState.UnlockedExpansionCount = clampExpansionCount(homeState.UnlockedExpansionCount)

    return homeState
end

function HomeExpansionService:_getAssignedHome(player, assignedHome)
    if assignedHome and assignedHome.Parent then
        return assignedHome
    end

    if self._homeService then
        return self._homeService:GetAssignedHome(player)
    end

    return nil
end

function HomeExpansionService:_getHomeBase(homeModel)
    if not homeModel then
        return nil
    end

    return homeModel:FindFirstChild(tostring((GameConfig.HOME or {}).HomeBaseName or "HomeBase"))
end

function HomeExpansionService:_getGlobalSlotIndex(floorLevel, localSlotIndex)
    local slotsPerFloor = math.max(1, math.floor(tonumber(getHomeExpansionConfig().SlotsPerFloor) or 10))
    local parsedFloorLevel = math.max(1, math.floor(tonumber(floorLevel) or 1))
    local parsedLocalSlotIndex = math.max(1, math.floor(tonumber(localSlotIndex) or 1))
    return ((parsedFloorLevel - 1) * slotsPerFloor) + parsedLocalSlotIndex
end

function HomeExpansionService:_buildPositionKey(globalSlotIndex)
    local positionPrefix = tostring((GameConfig.BRAINROT or {}).PositionPrefix or "Position")
    return string.format("%s%d", positionPrefix, math.max(1, math.floor(tonumber(globalSlotIndex) or 1)))
end

function HomeExpansionService:_buildUnlockedLocalSlotMap(unlockedExpansionCount)
    local unlockedLocalSlotMap = {}
    local entries = getUnlockEntries()
    local clampedCount = clampExpansionCount(unlockedExpansionCount)

    for expansionIndex = 1, clampedCount do
        local entry = entries[expansionIndex]
        if entry then
            local floorLevel = math.max(1, math.floor(tonumber(entry.FloorLevel) or 1))
            local localSlotIndex = math.max(1, math.floor(tonumber(entry.LocalSlotIndex) or 1))
            ensureTable(unlockedLocalSlotMap, floorLevel)[localSlotIndex] = true
        end
    end

    return unlockedLocalSlotMap
end
function HomeExpansionService:_getStaticFloorNameCandidates(floorLevel)
    local parsedFloorLevel = math.max(2, math.floor(tonumber(floorLevel) or 2))
    local config = getHomeExpansionConfig()
    local result = {}
    local seen = {}

    local function pushName(name)
        if type(name) ~= "string" or name == "" or seen[name] then
            return
        end

        seen[name] = true
        table.insert(result, name)
    end

    local configuredNamesByLevel = config.StaticFloorNameByLevel
    local configuredNames = type(configuredNamesByLevel) == "table" and configuredNamesByLevel[parsedFloorLevel] or nil
    if type(configuredNames) == "string" then
        pushName(configuredNames)
    elseif type(configuredNames) == "table" then
        for _, configuredName in ipairs(configuredNames) do
            pushName(configuredName)
        end
    end

    if parsedFloorLevel == 2 then
        pushName("HomeFloor1")
        pushName("HomeFloor01")
    elseif parsedFloorLevel == 3 then
        pushName("HomeFloor2")
        pushName("HomeFloor02")
        pushName("HomeFloor3")
        pushName("HomeFloor03")
    else
        local staticFloorIndex = parsedFloorLevel - 1
        pushName(string.format("HomeFloor%d", staticFloorIndex))
        pushName(string.format("HomeFloor%02d", staticFloorIndex))
    end

    return result
end

function HomeExpansionService:_findRuntimeFloor(homeModel, floorLevel, suppressWarn)
    if not homeModel then
        return nil
    end

    local parsedFloorLevel = math.max(2, math.floor(tonumber(floorLevel) or 2))
    local candidateNames = self:_getStaticFloorNameCandidates(parsedFloorLevel)
    for _, candidateName in ipairs(candidateNames) do
        local direct = homeModel:FindFirstChild(candidateName)
        if direct then
            return direct
        end
    end

    for _, candidateName in ipairs(candidateNames) do
        local nested = homeModel:FindFirstChild(candidateName, true)
        if nested then
            return nested
        end
    end

    if suppressWarn ~= true and self._didWarnMissingStaticFloorByLevel[parsedFloorLevel] ~= true then
        self._didWarnMissingStaticFloorByLevel[parsedFloorLevel] = true
        warn(string.format(
            "[HomeExpansionService] 找不到预摆楼层模型（FloorLevel=%d, Candidates=%s, Home=%s）",
            parsedFloorLevel,
            table.concat(candidateNames, ", "),
            tostring(homeModel.Name)
        ))
    end

    return nil
end

function HomeExpansionService:_destroyRuntimeFloor(homeModel, floorLevel)
    local floorRoot = self:_findRuntimeFloor(homeModel, floorLevel, true)
    if floorRoot then
        self:_applySlotVisibility(floorRoot, false)
    end
end

function HomeExpansionService:_clearRuntimeFloors(homeModel)
    if not homeModel then
        return
    end

    local maxFloorLevel = math.max(1, math.floor(tonumber(getHomeExpansionConfig().MaxFloorLevel) or 3))
    for floorLevel = 2, maxFloorLevel do
        self:_destroyRuntimeFloor(homeModel, floorLevel)
    end
end

function HomeExpansionService:_ensureRuntimeFloor(homeModel, floorLevel)
    return self:_findRuntimeFloor(homeModel, floorLevel, false)
end

function HomeExpansionService:_configureStaticFloor(homeModel, floorLevel, unlockedLocalSlotMap)
    local floorRoot = self:_ensureRuntimeFloor(homeModel, floorLevel)
    if not floorRoot then
        return nil
    end

    local hasUnlockedSlots = type(unlockedLocalSlotMap) == "table" and next(unlockedLocalSlotMap) ~= nil
    self:_applySlotVisibility(floorRoot, hasUnlockedSlots)
    self:_configureRuntimeFloor(floorRoot, floorLevel, unlockedLocalSlotMap)
    return floorRoot
end

function HomeExpansionService:_isInsideGeneratedFloor(root, descendant)
    local generatedAttributeName = tostring(getHomeExpansionConfig().RuntimeGeneratedFloorAttributeName or "HomeExpansionGeneratedFloor")
    local current = descendant and descendant.Parent or nil
    while current and current ~= root do
        if current:GetAttribute(generatedAttributeName) == true then
            return true
        end
        current = current.Parent
    end

    return false
end

function HomeExpansionService:_collectSlotRoots(root, skipGeneratedFloors)
    local slotRoots = {
        Position = {},
        Claim = {},
        Brand = {},
    }

    if not root then
        return slotRoots
    end

    local positionPrefix = tostring((GameConfig.BRAINROT or {}).PositionPrefix or "Position")
    local claimPrefix = tostring((GameConfig.BRAINROT or {}).ClaimPrefix or "Claim")
    local brandPrefix = tostring((GameConfig.BRAINROT or {}).BrandPrefix or "Brand")

    for _, descendant in ipairs(root:GetDescendants()) do
        if skipGeneratedFloors and self:_isInsideGeneratedFloor(root, descendant) then
            continue
        end

        local positionIndex = parseTrailingIndex(descendant.Name, positionPrefix)
        if positionIndex and slotRoots.Position[positionIndex] == nil then
            slotRoots.Position[positionIndex] = descendant
        end

        local claimIndex = parseTrailingIndex(descendant.Name, claimPrefix)
        if claimIndex and slotRoots.Claim[claimIndex] == nil then
            slotRoots.Claim[claimIndex] = descendant
        end

        local brandIndex = parseTrailingIndex(descendant.Name, brandPrefix)
        if brandIndex and slotRoots.Brand[brandIndex] == nil then
            slotRoots.Brand[brandIndex] = descendant
        end
    end

    return slotRoots
end

function HomeExpansionService:_applySlotMetadata(slotRoot, floorLevel, localSlotIndex, isUnlocked)
    if not slotRoot then
        return
    end

    local globalSlotIndex = self:_getGlobalSlotIndex(floorLevel, localSlotIndex)
    local config = getHomeExpansionConfig()
    slotRoot:SetAttribute(tostring(config.RuntimeFloorLevelAttributeName or "HomeExpansionFloorLevel"), floorLevel)
    slotRoot:SetAttribute(tostring(config.RuntimeLocalSlotIndexAttributeName or "HomeExpansionLocalSlotIndex"), localSlotIndex)
    slotRoot:SetAttribute(tostring(config.RuntimeGlobalSlotIndexAttributeName or "HomeExpansionGlobalSlotIndex"), globalSlotIndex)
    slotRoot:SetAttribute(tostring(config.RuntimePositionKeyAttributeName or "HomeExpansionPositionKey"), self:_buildPositionKey(globalSlotIndex))
    slotRoot:SetAttribute(tostring(config.RuntimeUnlockedAttributeName or "HomeExpansionUnlocked"), isUnlocked == true)
end

function HomeExpansionService:_applySlotVisibility(slotRoot, isUnlocked)
    if not slotRoot then
        return
    end

    local enabled = isUnlocked == true
    local config = getHomeExpansionConfig()
    slotRoot:SetAttribute(tostring(config.RuntimeUnlockedAttributeName or "HomeExpansionUnlocked"), enabled)

    local nodes = { slotRoot }
    for _, descendant in ipairs(slotRoot:GetDescendants()) do
        table.insert(nodes, descendant)
    end

    for _, node in ipairs(nodes) do
        if node:IsA("BasePart") then
            if node:GetAttribute(ORIGINAL_TRANSPARENCY_ATTRIBUTE) == nil then
                node:SetAttribute(ORIGINAL_TRANSPARENCY_ATTRIBUTE, node.Transparency)
            end
            if node:GetAttribute(ORIGINAL_CAN_COLLIDE_ATTRIBUTE) == nil then
                node:SetAttribute(ORIGINAL_CAN_COLLIDE_ATTRIBUTE, node.CanCollide)
            end
            if node:GetAttribute(ORIGINAL_CAN_TOUCH_ATTRIBUTE) == nil then
                node:SetAttribute(ORIGINAL_CAN_TOUCH_ATTRIBUTE, node.CanTouch)
            end
            if node:GetAttribute(ORIGINAL_CAN_QUERY_ATTRIBUTE) == nil then
                node:SetAttribute(ORIGINAL_CAN_QUERY_ATTRIBUTE, node.CanQuery)
            end

            if enabled then
                node.Transparency = tonumber(node:GetAttribute(ORIGINAL_TRANSPARENCY_ATTRIBUTE)) or 0
                node.CanCollide = node:GetAttribute(ORIGINAL_CAN_COLLIDE_ATTRIBUTE) ~= false
                node.CanTouch = node:GetAttribute(ORIGINAL_CAN_TOUCH_ATTRIBUTE) ~= false
                node.CanQuery = node:GetAttribute(ORIGINAL_CAN_QUERY_ATTRIBUTE) ~= false
            else
                node.Transparency = 1
                node.CanCollide = false
                node.CanTouch = false
                node.CanQuery = false
            end
        elseif node:IsA("Decal") or node:IsA("Texture") then
            if node:GetAttribute(ORIGINAL_DECAL_TRANSPARENCY_ATTRIBUTE) == nil then
                node:SetAttribute(ORIGINAL_DECAL_TRANSPARENCY_ATTRIBUTE, node.Transparency)
            end

            if enabled then
                node.Transparency = tonumber(node:GetAttribute(ORIGINAL_DECAL_TRANSPARENCY_ATTRIBUTE)) or 0
            else
                node.Transparency = 1
            end
        elseif node:IsA("LayerCollector") then
            if node:GetAttribute(ORIGINAL_ENABLED_ATTRIBUTE) == nil then
                node:SetAttribute(ORIGINAL_ENABLED_ATTRIBUTE, node.Enabled)
            end

            if enabled then
                node.Enabled = node:GetAttribute(ORIGINAL_ENABLED_ATTRIBUTE) ~= false
            else
                node.Enabled = false
            end
        elseif node:IsA("ProximityPrompt") then
            if node:GetAttribute(ORIGINAL_ENABLED_ATTRIBUTE) == nil then
                node:SetAttribute(ORIGINAL_ENABLED_ATTRIBUTE, node.Enabled)
            end

            if enabled then
                node.Enabled = node:GetAttribute(ORIGINAL_ENABLED_ATTRIBUTE) ~= false
            else
                node.Enabled = false
            end
        end
    end
end

function HomeExpansionService:_configureBaseFloor(homeBase)
    local slotRoots = self:_collectSlotRoots(homeBase, true)
    local baseSlotCount = math.max(0, math.floor(tonumber(getHomeExpansionConfig().BaseSlotCount) or 10))
    for localSlotIndex = 1, baseSlotCount do
        self:_applySlotMetadata(slotRoots.Position[localSlotIndex], 1, localSlotIndex, true)
        self:_applySlotMetadata(slotRoots.Claim[localSlotIndex], 1, localSlotIndex, true)
        self:_applySlotMetadata(slotRoots.Brand[localSlotIndex], 1, localSlotIndex, true)
    end
end

function HomeExpansionService:_configureRuntimeFloor(floorRoot, floorLevel, unlockedLocalSlotMap)
    if not floorRoot then
        return
    end

    local slotRoots = self:_collectSlotRoots(floorRoot, false)
    local slotsPerFloor = math.max(1, math.floor(tonumber(getHomeExpansionConfig().SlotsPerFloor) or 10))
    for localSlotIndex = 1, slotsPerFloor do
        local isUnlocked = type(unlockedLocalSlotMap) == "table" and unlockedLocalSlotMap[localSlotIndex] == true or false
        self:_applySlotMetadata(slotRoots.Position[localSlotIndex], floorLevel, localSlotIndex, isUnlocked)
        self:_applySlotMetadata(slotRoots.Claim[localSlotIndex], floorLevel, localSlotIndex, isUnlocked)
        self:_applySlotMetadata(slotRoots.Brand[localSlotIndex], floorLevel, localSlotIndex, isUnlocked)
        self:_applySlotVisibility(slotRoots.Position[localSlotIndex], isUnlocked)
        self:_applySlotVisibility(slotRoots.Claim[localSlotIndex], isUnlocked)
        self:_applySlotVisibility(slotRoots.Brand[localSlotIndex], isUnlocked)
    end
end

function HomeExpansionService:_findBaseUpgradeNodes(homeBase)
    local config = getHomeExpansionConfig()
    local baseUpgradePart = findFirstDescendantByNames(homeBase, {
        tostring(config.BaseUpgradePartName or "BaseUpgrade"),
    })
    local surfaceGui = baseUpgradePart and findFirstDescendantByNames(baseUpgradePart, {
        tostring(config.BaseUpgradeSurfaceGuiName or "SurfaceGui"),
    }) or nil
    local frame = findFirstGuiObjectByName(surfaceGui, tostring(config.BaseUpgradeFrameName or "Frame"))
    local moneyRoot = findFirstGuiObjectByName(frame or surfaceGui, tostring(config.BaseUpgradeMoneyRootName or "Money"))
    local innerFrame = findFirstGuiObjectByName(moneyRoot, tostring(config.BaseUpgradeInnerFrameName or "Frame"))
    local currentGoldLabel = findFirstTextLabelByName(innerFrame or moneyRoot, tostring(config.BaseUpgradeCostLabelName or "CurrentGold"))
    local levelLabel = findFirstTextLabelByName(innerFrame or frame or surfaceGui, tostring(config.BaseUpgradeLevelLabelName or "Level"))

    return {
        BaseUpgradePart = baseUpgradePart,
        SurfaceGui = surfaceGui,
        Frame = frame,
        MoneyRoot = moneyRoot,
        InnerFrame = innerFrame,
        CurrentGoldLabel = currentGoldLabel,
        LevelLabel = levelLabel,
    }
end

function HomeExpansionService:_refreshBaseUpgradeUiForCount(homeBase, unlockedExpansionCount)
    if not homeBase then
        return
    end

    local nodes = self:_findBaseUpgradeNodes(homeBase)
    local clampedCount = clampExpansionCount(unlockedExpansionCount)
    local maxExpansionCount = getMaxExpansionCount()
    local nextEntry = getUnlockEntries()[clampedCount + 1]
    local nextPriceText = nextEntry and FormatUtil.FormatWithCommasCeil(nextEntry.UnlockPrice) or "Max"

    if nodes.CurrentGoldLabel then
        nodes.CurrentGoldLabel.Text = nextPriceText
    end

    if nodes.LevelLabel then
        nodes.LevelLabel.Text = string.format("%d/%d", clampedCount, maxExpansionCount)
    end

    if nodes.MoneyRoot and nodes.MoneyRoot:IsA("GuiButton") then
        nodes.MoneyRoot.Active = nextEntry ~= nil
        nodes.MoneyRoot.AutoButtonColor = nextEntry ~= nil
    elseif nodes.MoneyRoot and nodes.MoneyRoot:IsA("GuiObject") then
        nodes.MoneyRoot.Active = nextEntry ~= nil
    end
end

function HomeExpansionService:_pushFeedback(player, status, unlockedExpansionCount, nextUnlockPrice, currentCoins, requestId)
    if not (player and self._homeExpansionFeedbackEvent) then
        return
    end

    self._homeExpansionFeedbackEvent:FireClient(player, {
        status = tostring(status or "Unknown"),
        unlockedExpansionCount = clampExpansionCount(unlockedExpansionCount),
        nextUnlockPrice = math.max(0, tonumber(nextUnlockPrice) or 0),
        currentCoins = math.max(0, tonumber(currentCoins) or 0),
        requestId = tostring(requestId or ""),
        timestamp = os.clock(),
    })
end

function HomeExpansionService:_notifyHomeLayoutChanged(player, assignedHome)
    if self._brainrotService and self._brainrotService.OnHomeLayoutChanged then
        self._brainrotService:OnHomeLayoutChanged(player, assignedHome)
    end
end

function HomeExpansionService:ApplyHomeLayout(player, assignedHome)
    local homeState = self:_getOrCreateHomeState(player)
    local homeModel = self:_getAssignedHome(player, assignedHome)
    local homeBase = self:_getHomeBase(homeModel)
    if not (homeState and homeBase) then
        return false
    end

    local unlockedExpansionCount = clampExpansionCount(homeState.UnlockedExpansionCount)
    homeState.UnlockedExpansionCount = unlockedExpansionCount

    self:_configureBaseFloor(homeBase)
    self:_clearRuntimeFloors(homeModel)

    local unlockedLocalSlotMap = self:_buildUnlockedLocalSlotMap(unlockedExpansionCount)
    local maxFloorLevel = math.max(1, math.floor(tonumber(getHomeExpansionConfig().MaxFloorLevel) or 3))

    for floorLevel = 2, maxFloorLevel do
        self:_configureStaticFloor(homeModel, floorLevel, unlockedLocalSlotMap[floorLevel])
    end

    self:_refreshBaseUpgradeUiForCount(homeBase, unlockedExpansionCount)
    return true
end

function HomeExpansionService:_canHandleRequest(player)
    if not player then
        return false
    end

    local debounceSeconds = math.max(0.05, tonumber(getHomeExpansionConfig().RequestDebounceSeconds) or 0.2)
    local nowClock = os.clock()
    local lastClock = tonumber(self._lastRequestClockByUserId[player.UserId]) or 0
    if nowClock - lastClock < debounceSeconds then
        return false
    end

    self._lastRequestClockByUserId[player.UserId] = nowClock
    return true
end

function HomeExpansionService:_handleRequestHomeExpansion(player, payload)
    if not self:_canHandleRequest(player) then
        return
    end

    local requestId = type(payload) == "table" and tostring(payload.requestId or "") or ""
    local homeState = self:_getOrCreateHomeState(player)
    local homeModel = self:_getAssignedHome(player)
    local homeBase = self:_getHomeBase(homeModel)
    local currentCoins = self._playerDataService and self._playerDataService:GetCoins(player) or 0
    if not (homeState and homeBase) then
        self:_pushFeedback(player, "MissingHome", 0, 0, currentCoins, requestId)
        return
    end

    local unlockedExpansionCount = clampExpansionCount(homeState.UnlockedExpansionCount)
    local nextEntry = getUnlockEntries()[unlockedExpansionCount + 1]
    if not nextEntry then
        self:_refreshBaseUpgradeUiForCount(homeBase, unlockedExpansionCount)
        self:_pushFeedback(player, "AlreadyMax", unlockedExpansionCount, 0, currentCoins, requestId)
        return
    end

    local unlockPrice = math.max(0, tonumber(nextEntry.UnlockPrice) or 0)
    if currentCoins + 0.0001 < unlockPrice then
        self:_refreshBaseUpgradeUiForCount(homeBase, unlockedExpansionCount)
        self:_pushFeedback(player, "NotEnoughCoins", unlockedExpansionCount, unlockPrice, currentCoins, requestId)
        return
    end

    local success = false
    local nextCoins = currentCoins
    if self._currencyService then
        success, nextCoins = self._currencyService:AddCoins(player, -unlockPrice, "HomeExpansionUnlock")
    end
    if not success then
        self:_pushFeedback(player, "CurrencyFailed", unlockedExpansionCount, unlockPrice, currentCoins, requestId)
        return
    end

    homeState.UnlockedExpansionCount = clampExpansionCount(unlockedExpansionCount + 1)
    self:ApplyHomeLayout(player, homeModel)
    self:_notifyHomeLayoutChanged(player, homeModel)

    local didSave = not self._playerDataService or self._playerDataService:SavePlayerData(player)
    local followingEntry = getUnlockEntries()[homeState.UnlockedExpansionCount + 1]
    self:_pushFeedback(
        player,
        didSave and "Success" or "SaveFailed",
        homeState.UnlockedExpansionCount,
        followingEntry and followingEntry.UnlockPrice or 0,
        nextCoins,
        requestId
    )
end

function HomeExpansionService:Init(dependencies)
    self._playerDataService = dependencies.PlayerDataService
    self._homeService = dependencies.HomeService
    self._currencyService = dependencies.CurrencyService
    self._remoteEventService = dependencies.RemoteEventService
    self._brainrotService = dependencies.BrainrotService

    self._requestHomeExpansionEvent = self._remoteEventService:GetEvent("RequestHomeExpansion")
    self._homeExpansionFeedbackEvent = self._remoteEventService:GetEvent("HomeExpansionFeedback")

    if self._requestHomeExpansionEvent then
        self._requestHomeExpansionEvent.OnServerEvent:Connect(function(player, payload)
            self:_handleRequestHomeExpansion(player, payload)
        end)
    end

    local allHomes = self._homeService and self._homeService.GetAllHomes and self._homeService:GetAllHomes() or {}
    for _, homeModel in ipairs(allHomes) do
        local homeBase = self:_getHomeBase(homeModel)
        if homeBase then
            self:_clearRuntimeFloors(homeModel)
            self:_configureBaseFloor(homeBase)
            self:_refreshBaseUpgradeUiForCount(homeBase, 0)
        end

        if self._brainrotService and self._brainrotService.ResetHomeWorldUi then
            self._brainrotService:ResetHomeWorldUi(homeModel)
        end
    end
end

function HomeExpansionService:OnPlayerReady(player, assignedHome)
    self:ApplyHomeLayout(player, assignedHome)
end

function HomeExpansionService:OnPlayerRemoving(player, assignedHome)
    if player then
        self._lastRequestClockByUserId[player.UserId] = nil
    end

    local homeModel = self:_getAssignedHome(player, assignedHome)
    local homeBase = self:_getHomeBase(homeModel)
    if not homeBase then
        return
    end

    self:_clearRuntimeFloors(homeModel)
    self:_configureBaseFloor(homeBase)
    self:_refreshBaseUpgradeUiForCount(homeBase, 0)

    if self._brainrotService and self._brainrotService.ResetHomeWorldUi then
        self._brainrotService:ResetHomeWorldUi(homeModel)
    end
end

return HomeExpansionService
