--[[
脚本名字: ProgressController
脚本文件: ProgressController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/ProgressController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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
        "[ProgressController] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local GameConfig = requireSharedModule("GameConfig")

local ProgressController = {}
ProgressController.__index = ProgressController

local function disconnectAll(connectionList)
    for _, connection in ipairs(connectionList or {}) do
        connection:Disconnect()
    end
    table.clear(connectionList)
end

local function getConfig()
    return GameConfig.PROGRESS or {}
end

local function getPlayerAttributeName()
    return tostring(getConfig().PlayerAttributeName or "ProgressLevel")
end

local function getFloatLandCount()
    return math.max(0, math.floor(tonumber(getConfig().FloatLandCount) or 9))
end

local function clampProgressLevel(level)
    return math.clamp(math.floor(tonumber(level) or 0), 0, getFloatLandCount())
end

local function getFloatLandPartName()
    return tostring(getConfig().FloatLandPartName or "Land")
end

local function getFloatLandBoundsPaddingXZ()
    return math.max(0, tonumber(getConfig().FloatLandBoundsPaddingXZ) or 18)
end

local function getFloatLandBoundsPaddingY()
    return math.max(0, tonumber(getConfig().FloatLandBoundsPaddingY) or 180)
end

local function getHomeBoundsPaddingXZ()
    return math.max(0, tonumber(getConfig().HomeBoundsPaddingXZ) or 18)
end

local function getHomeBoundsPaddingY()
    return math.max(0, tonumber(getConfig().HomeBoundsPaddingY) or 40)
end

local function getLocalRegionUpdateIntervalSeconds()
    return math.clamp(math.min(tonumber(getConfig().UpdateIntervalSeconds) or 0.25, 0.1), 0.05, 0.1)
end

local function getLandRootFolder()
    local folderName = tostring(getConfig().LandRootFolderName or "Land")
    local direct = Workspace:FindFirstChild(folderName)
    if direct then
        return direct
    end

    return Workspace:FindFirstChild(folderName, true)
end

local function getHomesRootFolder()
    local homeConfig = GameConfig.HOME or {}
    local folderName = tostring(homeConfig.ContainerName or "PlayerHome")
    local direct = Workspace:FindFirstChild(folderName)
    if direct then
        return direct
    end

    return Workspace:FindFirstChild(folderName, true)
end

local function parseFloatLandLevel(folderName)
    local name = tostring(folderName or "")
    local prefix = tostring(getConfig().FloatLandFolderPrefix or "FloatLand")
    if string.sub(name, 1, #prefix) ~= prefix then
        return 0
    end

    local suffix = string.sub(name, #prefix + 1)
    local firstDigit = string.match(suffix, "^(%d)")
    return clampProgressLevel(firstDigit)
end

local function isPointInsidePartBounds(point, part, paddingXZ, paddingY)
    if not (part and part:IsA("BasePart") and typeof(point) == "Vector3") then
        return false
    end

    local localPoint = part.CFrame:PointToObjectSpace(point)
    local halfSize = part.Size * 0.5
    return math.abs(localPoint.X) <= (halfSize.X + paddingXZ)
        and math.abs(localPoint.Z) <= (halfSize.Z + paddingXZ)
        and math.abs(localPoint.Y) <= (halfSize.Y + paddingY)
end

local function computeBoundsFromDescendants(root)
    if not root then
        return nil
    end

    local minVector = nil
    local maxVector = nil

    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant:IsA("BasePart") then
            local halfSize = descendant.Size * 0.5
            local partMin = descendant.Position - halfSize
            local partMax = descendant.Position + halfSize
            if not minVector then
                minVector = partMin
                maxVector = partMax
            else
                minVector = Vector3.new(
                    math.min(minVector.X, partMin.X),
                    math.min(minVector.Y, partMin.Y),
                    math.min(minVector.Z, partMin.Z)
                )
                maxVector = Vector3.new(
                    math.max(maxVector.X, partMax.X),
                    math.max(maxVector.Y, partMax.Y),
                    math.max(maxVector.Z, partMax.Z)
                )
            end
        end
    end

    if not (minVector and maxVector) then
        return nil
    end

    return {
        min = minVector,
        max = maxVector,
    }
end

local function isPointInsideBounds(point, bounds, paddingXZ, paddingY)
    if typeof(point) ~= "Vector3" or type(bounds) ~= "table" or not (bounds.min and bounds.max) then
        return false
    end

    return point.X >= (bounds.min.X - paddingXZ)
        and point.X <= (bounds.max.X + paddingXZ)
        and point.Z >= (bounds.min.Z - paddingXZ)
        and point.Z <= (bounds.max.Z + paddingXZ)
        and point.Y >= (bounds.min.Y - paddingY)
        and point.Y <= (bounds.max.Y + paddingY)
end

function ProgressController.new()
    local self = setmetatable({}, ProgressController)
    self._started = false
    self._persistentConnections = {}
    self._uiConnections = {}
    self._worldConnections = {}
    self._playerConnectionsByUserId = {}
    self._iconByUserId = {}
    self._thumbnailByUserId = {}
    self._didWarnByKey = {}
    self._rebindQueued = false
    self._mainGui = nil
    self._progressRoot = nil
    self._progressBar = nil
    self._playerTemplate = nil
    self._playerTemplateBasePosition = nil
    self._topRoot = nil
    self._rarityNodeByLevel = {}
    self._topHiddenByProgress = false
    self._localFlightProgressOverrideActive = false
    self._localFlightProgressOverrideRatio = 0
    self._localDetectedProgressLevel = 0
    self._localInsideHome = false
    self._zonePartsByLevel = {}
    self._homeBoundsByName = {}
    self._regionUpdateAccumulator = 0
    return self
end

function ProgressController:_warnOnce(key, message)
    if self._didWarnByKey[key] then
        return
    end

    self._didWarnByKey[key] = true
    warn(message)
end

function ProgressController:_getPlayerGui()
    return localPlayer:FindFirstChild("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
end

function ProgressController:_getMainGui()
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

function ProgressController:_findDescendantByNames(root, names)
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

function ProgressController:_clearUiBindings()
    disconnectAll(self._uiConnections)
end

function ProgressController:_clearWorldBindings()
    disconnectAll(self._worldConnections)
end

function ProgressController:_disconnectPlayerConnections(userId)
    local bucket = self._playerConnectionsByUserId[userId]
    if bucket then
        disconnectAll(bucket)
        self._playerConnectionsByUserId[userId] = nil
    end
end

function ProgressController:_destroyPlayerIcon(userId)
    local icon = self._iconByUserId[userId]
    if icon then
        icon:Destroy()
        self._iconByUserId[userId] = nil
    end
end

function ProgressController:_destroyAllIcons()
    for userId, icon in pairs(self._iconByUserId) do
        if icon then
            icon:Destroy()
        end
        self._iconByUserId[userId] = nil
    end
end

function ProgressController:_bindMainUi()
    local mainGui = self:_getMainGui()
    if not mainGui then
        self:_warnOnce("MissingMain", "[ProgressController] Missing Main UI; progress UI is temporarily unavailable.")
        self:_clearUiBindings()
        return false
    end

    self._mainGui = mainGui
    self._progressRoot = self:_findDescendantByNames(mainGui, { "Progress" })
    self._progressBar = self._progressRoot and self:_findDescendantByNames(self._progressRoot, { "ProgressBar" }) or nil
    self._playerTemplate = self._progressRoot and self:_findDescendantByNames(self._progressRoot, { "Player" }) or nil
    self._playerTemplateBasePosition = self._playerTemplate and self._playerTemplate.Position or nil
    self._topRoot = self:_findDescendantByNames(mainGui, { "Top" })
    table.clear(self._rarityNodeByLevel)

    if not (self._progressRoot and self._progressRoot:IsA("GuiObject")) then
        self:_warnOnce("MissingProgressRoot", "[ProgressController] Missing Main/Progress.")
        self:_clearUiBindings()
        return false
    end

    if not (self._progressBar and self._progressBar:IsA("GuiObject")) then
        self:_warnOnce("MissingProgressBar", "[ProgressController] Missing Main/Progress/ProgressBar.")
        self:_clearUiBindings()
        return false
    end

    if not (self._playerTemplate and self._playerTemplate:IsA("ImageLabel")) then
        self:_warnOnce("MissingProgressPlayerTemplate", "[ProgressController] Missing Main/Progress/Player icon template.")
        self:_clearUiBindings()
        return false
    end

    for level = 1, getFloatLandCount() do
        local rarityNode = self._progressBar:FindFirstChild(string.format("Rarity%d", level))
        if rarityNode and rarityNode:IsA("GuiObject") then
            self._rarityNodeByLevel[level] = rarityNode
        end
    end

    self._playerTemplate.Visible = false
    self._progressRoot.Visible = false

    self:_clearUiBindings()
    table.insert(self._uiConnections, self._progressRoot:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        self:_renderAll()
    end))
    table.insert(self._uiConnections, self._progressRoot:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
        self:_renderAll()
    end))
    table.insert(self._uiConnections, self._progressBar:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        self:_renderAll()
    end))
    table.insert(self._uiConnections, self._progressBar:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
        self:_renderAll()
    end))
    if self._topRoot and self._topRoot:IsA("GuiObject") then
        table.insert(self._uiConnections, self._topRoot:GetPropertyChangedSignal("Visible"):Connect(function()
            if self:_getDisplayProgressLevel(localPlayer) > 0 and self._topRoot.Visible then
                self._topRoot.Visible = false
            end
        end))
    end

    self:_destroyAllIcons()
    self:_renderAll()
    return true
end

function ProgressController:_queueRebind()
    if self._rebindQueued then
        return
    end

    self._rebindQueued = true
    task.defer(function()
        self._rebindQueued = false
        self:_bindMainUi()
    end)
end

function ProgressController:_scheduleRetryBind()
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

function ProgressController:_getThumbnailForUserId(userId)
    local cachedThumbnail = self._thumbnailByUserId[userId]
    if cachedThumbnail then
        return cachedThumbnail
    end

    local ok, thumbnail = pcall(function()
        return Players:GetUserThumbnailAsync(
            userId,
            Enum.ThumbnailType.HeadShot,
            Enum.ThumbnailSize.Size100x100
        )
    end)
    if ok and type(thumbnail) == "string" and thumbnail ~= "" then
        self._thumbnailByUserId[userId] = thumbnail
        return thumbnail
    end

    return nil
end

function ProgressController:_getAssignedHomeId()
    return tostring(localPlayer:GetAttribute("HomeId") or "")
end

function ProgressController:_getAssignedHomeModel()
    local homeId = self:_getAssignedHomeId()
    if homeId == "" then
        return nil
    end

    local homesRoot = getHomesRootFolder()
    if not homesRoot then
        return nil
    end

    local direct = homesRoot:FindFirstChild(homeId)
    if direct then
        return direct
    end

    return homesRoot:FindFirstChild(homeId, true)
end

function ProgressController:_getAssignedHomeBounds()
    local homeId = self:_getAssignedHomeId()
    if homeId == "" then
        return nil
    end

    local cachedBounds = self._homeBoundsByName[homeId]
    if cachedBounds then
        return cachedBounds
    end

    local computedBounds = computeBoundsFromDescendants(self:_getAssignedHomeModel())
    self._homeBoundsByName[homeId] = computedBounds
    return computedBounds
end

function ProgressController:_rebuildFloatLandZoneParts()
    table.clear(self._zonePartsByLevel)

    local landRoot = getLandRootFolder()
    if not landRoot then
        return
    end

    local landPartName = getFloatLandPartName()
    for _, child in ipairs(landRoot:GetChildren()) do
        if child:IsA("Folder") then
            local level = parseFloatLandLevel(child.Name)
            local zonePart = level > 0 and child:FindFirstChild(landPartName) or nil
            if zonePart and zonePart:IsA("BasePart") then
                local bucket = self._zonePartsByLevel[level]
                if not bucket then
                    bucket = {}
                    self._zonePartsByLevel[level] = bucket
                end
                table.insert(bucket, zonePart)
            end
        end
    end
end

function ProgressController:_resolveDetectedProgressLevel(rootPosition)
    for level = 1, getFloatLandCount() do
        local bucket = self._zonePartsByLevel[level]
        if bucket then
            for _, zonePart in ipairs(bucket) do
                if zonePart.Parent and isPointInsidePartBounds(
                    rootPosition,
                    zonePart,
                    getFloatLandBoundsPaddingXZ(),
                    getFloatLandBoundsPaddingY()
                ) then
                    return level
                end
            end
        end
    end

    return 0
end

function ProgressController:_refreshLocalRegionState(forceRender)
    if next(self._zonePartsByLevel) == nil then
        self:_rebuildFloatLandZoneParts()
    end

    local character = localPlayer.Character
    local rootPart = character and character:FindFirstChild("HumanoidRootPart") or nil
    local nextDetectedProgressLevel = 0
    local nextInsideHome = false

    if rootPart and rootPart:IsA("BasePart") then
        local rootPosition = rootPart.Position
        local homeBounds = self:_getAssignedHomeBounds()
        nextInsideHome = isPointInsideBounds(
            rootPosition,
            homeBounds,
            getHomeBoundsPaddingXZ(),
            getHomeBoundsPaddingY()
        )
        if not nextInsideHome then
            nextDetectedProgressLevel = self:_resolveDetectedProgressLevel(rootPosition)
        end
    end

    local didChange = self._localDetectedProgressLevel ~= nextDetectedProgressLevel
        or self._localInsideHome ~= nextInsideHome
    self._localDetectedProgressLevel = nextDetectedProgressLevel
    self._localInsideHome = nextInsideHome

    if forceRender or didChange then
        self:_renderAll()
    end
end

function ProgressController:_ensureIconForPlayer(player)
    if not (self._progressRoot and self._playerTemplate) then
        return nil
    end

    local icon = self._iconByUserId[player.UserId]
    if icon and icon.Parent == self._progressRoot then
        return icon
    end

    icon = self._playerTemplate:Clone()
    icon.Name = string.format("Player_%d", player.UserId)
    icon.Visible = true
    icon.Parent = self._progressRoot
    self._iconByUserId[player.UserId] = icon

    local thumbnail = self:_getThumbnailForUserId(player.UserId)
    if thumbnail then
        icon.Image = thumbnail
    end

    return icon
end

function ProgressController:_getOrderedPlayers()
    local orderedPlayers = {}
    local otherPlayers = {}

    for _, player in ipairs(Players:GetPlayers()) do
        if player == localPlayer then
            table.insert(orderedPlayers, player)
        else
            table.insert(otherPlayers, player)
        end
    end

    table.sort(otherPlayers, function(left, right)
        local leftId = math.max(0, tonumber(left and left.UserId) or 0)
        local rightId = math.max(0, tonumber(right and right.UserId) or 0)
        if leftId == rightId then
            return tostring(left and left.Name or "") < tostring(right and right.Name or "")
        end

        return leftId < rightId
    end)

    for _, player in ipairs(otherPlayers) do
        table.insert(orderedPlayers, player)
    end

    return orderedPlayers
end

function ProgressController:_getHorizontalSlotOffset(slotIndex, iconWidth)
    if slotIndex <= 1 then
        return 0
    end

    local spacingScale = math.max(0.4, tonumber(getConfig().IconSpacingScale) or 0.72)
    local directionIndex = slotIndex - 1
    local step = math.ceil(directionIndex / 2)
    local direction = (directionIndex % 2 == 1) and -1 or 1
    return direction * step * math.max(10, iconWidth * spacingScale)
end

function ProgressController:_getTargetTopOffsetY(icon, progressLevel)
    if not (self._progressRoot and self._playerTemplateBasePosition) then
        return 0
    end

    local rootAbsoluteY = self._progressRoot.AbsolutePosition.Y
    local homeTopOffsetY = self._playerTemplate.AbsolutePosition.Y - rootAbsoluteY
    if clampProgressLevel(progressLevel) <= 0 then
        return math.floor(homeTopOffsetY + 0.5)
    end

    local rarityNode = self._rarityNodeByLevel[clampProgressLevel(progressLevel)]
    if not rarityNode then
        return math.floor(homeTopOffsetY + 0.5)
    end

    local targetCenterY = rarityNode.AbsolutePosition.Y + (rarityNode.AbsoluteSize.Y * 0.5)
    local iconHeight = icon and icon.AbsoluteSize.Y or self._playerTemplate.AbsoluteSize.Y
    return math.floor((targetCenterY - rootAbsoluteY) - (iconHeight * 0.5) + 0.5)
end

function ProgressController:_getTargetTopOffsetYByRatio(icon, ratio)
    local clampedRatio = math.clamp(tonumber(ratio) or 0, 0, 1)
    local startTopOffsetY = self:_getTargetTopOffsetY(icon, 0)
    local endTopOffsetY = self:_getTargetTopOffsetY(icon, getFloatLandCount())
    return math.floor(startTopOffsetY + ((endTopOffsetY - startTopOffsetY) * clampedRatio) + 0.5)
end

function ProgressController:_getPlayerProgressLevel(player)
    if not player then
        return 0
    end

    return clampProgressLevel(player:GetAttribute(getPlayerAttributeName()))
end

function ProgressController:_getLocalEffectiveProgressLevel()
    if self._localInsideHome then
        return 0
    end

    if self._localDetectedProgressLevel > 0 then
        return self._localDetectedProgressLevel
    end

    return self:_getPlayerProgressLevel(localPlayer)
end

function ProgressController:_getDisplayProgressLevel(player)
    if player == localPlayer then
        return self:_getLocalEffectiveProgressLevel()
    end

    return self:_getPlayerProgressLevel(player)
end

function ProgressController:_updateRootVisibility()
    if not self._progressRoot then
        return
    end

    self._progressRoot.Visible = self._localFlightProgressOverrideActive
        or self:_getDisplayProgressLevel(localPlayer) > 0
end

function ProgressController:_setTopVisible(visible)
    local topRoot = self._topRoot
    if not (topRoot and topRoot.Parent and topRoot:IsA("GuiObject")) then
        local mainGui = self._mainGui or self:_getMainGui()
        topRoot = mainGui and self:_findDescendantByNames(mainGui, { "Top" }) or nil
        self._topRoot = topRoot
    end

    if topRoot and topRoot:IsA("GuiObject") then
        topRoot.Visible = visible == true
    end
end

function ProgressController:_updateTopVisibility()
    local shouldHideTop = self._localFlightProgressOverrideActive
        or self:_getDisplayProgressLevel(localPlayer) > 0
    if shouldHideTop then
        self._topHiddenByProgress = true
        self:_setTopVisible(false)
    elseif self._topHiddenByProgress then
        self._topHiddenByProgress = false
        self:_setTopVisible(true)
    end
end

function ProgressController:_renderAll()
    if not (self._progressRoot and self._playerTemplate and self._playerTemplateBasePosition) then
        return
    end

    self:_updateRootVisibility()
    self:_updateTopVisibility()

    local orderedPlayers = self:_getOrderedPlayers()
    local activeUserIds = {}
    for slotIndex, player in ipairs(orderedPlayers) do
        activeUserIds[player.UserId] = true
        local icon = self:_ensureIconForPlayer(player)
        if icon then
            local horizontalOffset = self:_getHorizontalSlotOffset(slotIndex, icon.AbsoluteSize.X)
            local targetY = nil
            if player == localPlayer and self._localFlightProgressOverrideActive then
                targetY = self:_getTargetTopOffsetYByRatio(icon, self._localFlightProgressOverrideRatio)
            else
                targetY = self:_getTargetTopOffsetY(icon, self:_getDisplayProgressLevel(player))
            end
            icon.Position = UDim2.new(
                self._playerTemplateBasePosition.X.Scale,
                self._playerTemplateBasePosition.X.Offset + horizontalOffset,
                0,
                targetY
            )
            icon.ZIndex = player == localPlayer and 3 or 2
            icon.Visible = true
        end
    end

    for userId, _icon in pairs(self._iconByUserId) do
        if not activeUserIds[userId] then
            self:_destroyPlayerIcon(userId)
        end
    end
end

function ProgressController:_bindPlayer(player)
    if not player then
        return
    end

    self:_disconnectPlayerConnections(player.UserId)
    local connections = {}
    self._playerConnectionsByUserId[player.UserId] = connections
    table.insert(connections, player:GetAttributeChangedSignal(getPlayerAttributeName()):Connect(function()
        self:_renderAll()
    end))
end

function ProgressController:SetLocalFlightProgressOverride(isActive, ratio)
    local nextActive = isActive == true
    local nextRatio = nextActive and math.clamp(tonumber(ratio) or 0, 0, 1) or 0
    local ratioChanged = math.abs((self._localFlightProgressOverrideRatio or 0) - nextRatio) >= 0.001
    if self._localFlightProgressOverrideActive == nextActive and not ratioChanged then
        return
    end

    self._localFlightProgressOverrideActive = nextActive
    self._localFlightProgressOverrideRatio = nextRatio

    self:_renderAll()
end

function ProgressController:Start()
    if self._started then
        return
    end
    self._started = true

    for _, player in ipairs(Players:GetPlayers()) do
        self:_bindPlayer(player)
    end

    table.insert(self._persistentConnections, Players.PlayerAdded:Connect(function(player)
        self:_bindPlayer(player)
        self:_renderAll()
    end))
    table.insert(self._persistentConnections, Players.PlayerRemoving:Connect(function(player)
        self:_disconnectPlayerConnections(player.UserId)
        self:_destroyPlayerIcon(player.UserId)
        self:_renderAll()
    end))

    local playerGui = self:_getPlayerGui()
    if playerGui then
        table.insert(self._persistentConnections, playerGui.ChildAdded:Connect(function(child)
            if child.Name == "Main" then
                self:_queueRebind()
            end
        end))
        table.insert(self._persistentConnections, playerGui.ChildRemoved:Connect(function(child)
            if child.Name == "Main" then
                self:_queueRebind()
            end
        end))
    end

    table.insert(self._persistentConnections, localPlayer.CharacterAdded:Connect(function()
        task.defer(function()
            self._regionUpdateAccumulator = 0
            self:_refreshLocalRegionState(true)
        end)
    end))
    table.insert(self._persistentConnections, localPlayer:GetAttributeChangedSignal("HomeId"):Connect(function()
        local homeId = self:_getAssignedHomeId()
        if homeId == "" then
            table.clear(self._homeBoundsByName)
        else
            self._homeBoundsByName[homeId] = nil
        end
        self:_refreshLocalRegionState(true)
    end))

    self:_rebuildFloatLandZoneParts()
    self:_clearWorldBindings()
    local landRoot = getLandRootFolder()
    if landRoot then
        table.insert(self._worldConnections, landRoot.ChildAdded:Connect(function()
            self:_rebuildFloatLandZoneParts()
            self:_refreshLocalRegionState(true)
        end))
        table.insert(self._worldConnections, landRoot.ChildRemoved:Connect(function()
            self:_rebuildFloatLandZoneParts()
            self:_refreshLocalRegionState(true)
        end))
    end
    local homesRoot = getHomesRootFolder()
    if homesRoot then
        table.insert(self._worldConnections, homesRoot.ChildAdded:Connect(function()
            table.clear(self._homeBoundsByName)
            self:_refreshLocalRegionState(true)
        end))
        table.insert(self._worldConnections, homesRoot.ChildRemoved:Connect(function()
            table.clear(self._homeBoundsByName)
            self:_refreshLocalRegionState(true)
        end))
    end
    table.insert(self._persistentConnections, RunService.Heartbeat:Connect(function(deltaTime)
        self._regionUpdateAccumulator += math.max(0, tonumber(deltaTime) or 0)
        if self._regionUpdateAccumulator < getLocalRegionUpdateIntervalSeconds() then
            return
        end

        self._regionUpdateAccumulator = 0
        self:_refreshLocalRegionState(false)
    end))

    self:_scheduleRetryBind()
    self:_refreshLocalRegionState(true)
end

return ProgressController
