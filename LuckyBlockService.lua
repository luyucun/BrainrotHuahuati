--[[
脚本名字: LuckyBlockService
脚本文件: LuckyBlockService.lua
脚本类型: ModuleScript
Studio放置路径: ServerScriptService/Services/LuckyBlockService
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

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
        "[LuckyBlockService] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local LuckyBlockConfig = requireSharedModule("LuckyBlockConfig")
local BrainrotConfig = requireSharedModule("BrainrotConfig")

local LuckyBlockService = {}
LuckyBlockService._playerDataService = nil
LuckyBlockService._brainrotService = nil
LuckyBlockService._requestLuckyBlockOpenEvent = nil
LuckyBlockService._luckyBlockFeedbackEvent = nil
LuckyBlockService._lastRequestClockByUserId = {}
LuckyBlockService._toolConnectionsByUserId = {}
LuckyBlockService._characterAddedConnectionsByUserId = {}
LuckyBlockService._didWarnMissingAssetByPath = {}
LuckyBlockService._pendingRewardsByUserId = {}
LuckyBlockService._pendingRewardThreadsByRequestId = {}
LuckyBlockService._random = Random.new()

local function normalizeInteger(value, minimum)
    local normalized = math.floor(tonumber(value) or 0)
    if type(minimum) == "number" then
        return math.max(minimum, normalized)
    end
    return normalized
end

local function splitSlashPath(pathText)
    local result = {}
    if type(pathText) ~= "string" then
        return result
    end

    for segment in string.gmatch(pathText, "[^/]+") do
        if segment ~= "" then
            table.insert(result, segment)
        end
    end

    return result
end

local function findPathFromRoot(root, pathText)
    if not root then
        return nil
    end

    local segments = splitSlashPath(pathText)
    if #segments <= 0 then
        return nil
    end

    local current = root
    local startIndex = 1
    if segments[1] == root.Name then
        startIndex = 2
    end

    for index = startIndex, #segments do
        current = current and current:FindFirstChild(segments[index]) or nil
        if not current then
            return nil
        end
    end

    return current
end

local function findReplicatedStoragePath(pathText)
    return findPathFromRoot(ReplicatedStorage, pathText)
end

local function setVisualPartProperties(part)
    part.Anchored = false
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.Massless = true
end

local function getPrimaryBasePart(instance)
    if not instance then
        return nil
    end

    if instance:IsA("BasePart") then
        return instance
    end

    if instance:IsA("Model") then
        return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
    end

    return nil
end

local function moveInstanceToCFrame(instance, targetCFrame)
    if not (instance and targetCFrame) then
        return false
    end

    if instance:IsA("Model") then
        local primaryPart = getPrimaryBasePart(instance)
        if not primaryPart then
            return false
        end

        if instance.PrimaryPart ~= primaryPart then
            instance.PrimaryPart = primaryPart
        end
        instance:PivotTo(targetCFrame)
        return true
    end

    if instance:IsA("BasePart") then
        instance.CFrame = targetCFrame
        return true
    end

    return false
end

local function isPointInsidePartHorizontalBounds(part, worldPoint)
    if not (part and part:IsA("BasePart") and typeof(worldPoint) == "Vector3") then
        return false
    end

    local localPoint = part.CFrame:PointToObjectSpace(worldPoint)
    local halfSize = part.Size * 0.5
    return math.abs(localPoint.X) <= halfSize.X
        and math.abs(localPoint.Z) <= halfSize.Z
end

local function ensureConnectionBucket(storage, userId)
    local bucket = storage[userId]
    if type(bucket) ~= "table" then
        bucket = {}
        storage[userId] = bucket
    end
    return bucket
end

local function disconnectConnectionList(connectionList)
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

local function ensureLuckyBlockState(playerData)
    if type(playerData) ~= "table" then
        return nil
    end

    local luckyBlockState = playerData.LuckyBlockState
    if type(luckyBlockState) ~= "table" then
        luckyBlockState = {}
        playerData.LuckyBlockState = luckyBlockState
    end

    local inventory = {}
    local seenInstanceIds = {}
    local maxInstanceId = 0
    if type(luckyBlockState.Inventory) == "table" then
        for _, item in ipairs(luckyBlockState.Inventory) do
            local blockId = normalizeInteger(type(item) == "table" and item.BlockId, 0)
            local instanceId = normalizeInteger(type(item) == "table" and item.InstanceId, 0)
            if blockId > 0 and instanceId > 0 and LuckyBlockConfig.EntriesById[blockId] and not seenInstanceIds[instanceId] then
                seenInstanceIds[instanceId] = true
                maxInstanceId = math.max(maxInstanceId, instanceId)
                table.insert(inventory, {
                    BlockId = blockId,
                    InstanceId = instanceId,
                })
            end
        end
    end

    table.sort(inventory, function(left, right)
        return normalizeInteger(left and left.InstanceId, 0) < normalizeInteger(right and right.InstanceId, 0)
    end)

    luckyBlockState.Inventory = inventory
    luckyBlockState.NextInstanceId = math.max(
        maxInstanceId + 1,
        normalizeInteger(luckyBlockState.NextInstanceId, 1)
    )
    luckyBlockState.EquippedInstanceId = normalizeInteger(luckyBlockState.EquippedInstanceId, 0)
    return luckyBlockState
end

local function findInventoryIndexByInstanceId(inventory, targetInstanceId)
    if type(inventory) ~= "table" or targetInstanceId <= 0 then
        return nil
    end

    for index, item in ipairs(inventory) do
        if normalizeInteger(item and item.InstanceId, 0) == targetInstanceId then
            return index
        end
    end

    return nil
end

local function cloneLuckyBlockInventory(inventory)
    local cloned = {}
    if type(inventory) ~= "table" then
        return cloned
    end

    for _, item in ipairs(inventory) do
        table.insert(cloned, {
            BlockId = normalizeInteger(type(item) == "table" and item.BlockId, 0),
            InstanceId = normalizeInteger(type(item) == "table" and item.InstanceId, 0),
        })
    end

    table.sort(cloned, function(left, right)
        return normalizeInteger(left and left.InstanceId, 0) < normalizeInteger(right and right.InstanceId, 0)
    end)
    return cloned
end

function LuckyBlockService:_getPlayerDataAndState(player)
    if not (self._playerDataService and player) then
        return nil, nil
    end

    local playerData = self._playerDataService:GetPlayerData(player)
    if type(playerData) ~= "table" then
        return nil, nil
    end

    return playerData, ensureLuckyBlockState(playerData)
end

function LuckyBlockService:_createStateSnapshot(luckyBlockState)
    if type(luckyBlockState) ~= "table" then
        return nil
    end

    return {
        Inventory = cloneLuckyBlockInventory(luckyBlockState.Inventory),
        NextInstanceId = math.max(1, normalizeInteger(luckyBlockState.NextInstanceId, 1)),
        EquippedInstanceId = normalizeInteger(luckyBlockState.EquippedInstanceId, 0),
    }
end

function LuckyBlockService:_restoreStateSnapshot(player, luckyBlockState, snapshot)
    if not (player and luckyBlockState and type(snapshot) == "table") then
        return false
    end

    luckyBlockState.Inventory = cloneLuckyBlockInventory(snapshot.Inventory)
    luckyBlockState.NextInstanceId = math.max(1, normalizeInteger(snapshot.NextInstanceId, 1))
    luckyBlockState.EquippedInstanceId = normalizeInteger(snapshot.EquippedInstanceId, 0)

    local equippedInstanceId = luckyBlockState.EquippedInstanceId
    self:_refreshLuckyBlockTools(player)
    luckyBlockState.EquippedInstanceId = equippedInstanceId
    if equippedInstanceId > 0 then
        task.defer(function()
            self:_equipLuckyBlockToolByInstanceId(player, equippedInstanceId)
        end)
    end

    return true
end

function LuckyBlockService:CreatePlayerStateSnapshot(player)
    local _playerData, luckyBlockState = self:_getPlayerDataAndState(player)
    if not luckyBlockState then
        return nil
    end

    return self:_createStateSnapshot(luckyBlockState)
end

function LuckyBlockService:RestorePlayerStateSnapshot(player, snapshot)
    local _playerData, luckyBlockState = self:_getPlayerDataAndState(player)
    if not luckyBlockState then
        return false
    end

    return self:_restoreStateSnapshot(player, luckyBlockState, snapshot)
end

function LuckyBlockService:_savePlayerDataAsync(player)
    if not (self._playerDataService and player) then
        return
    end

    task.spawn(function()
        self._playerDataService:SavePlayerData(player)
    end)
end

function LuckyBlockService:_pushFeedback(player, payload)
    if not (player and self._luckyBlockFeedbackEvent) then
        return
    end

    local normalizedPayload = type(payload) == "table" and payload or {}
    normalizedPayload.timestamp = os.clock()
    self._luckyBlockFeedbackEvent:FireClient(player, normalizedPayload)
end

function LuckyBlockService:_applyEquippedAttributes(player, blockId, instanceId)
    if not player then
        return
    end

    local normalizedBlockId = normalizeInteger(blockId, 0)
    local normalizedInstanceId = normalizeInteger(instanceId, 0)
    player:SetAttribute(
        LuckyBlockConfig.PlayerEquippedBlockIdAttributeName,
        normalizedBlockId > 0 and normalizedBlockId or nil
    )
    player:SetAttribute(
        LuckyBlockConfig.PlayerEquippedBlockInstanceIdAttributeName,
        normalizedInstanceId > 0 and normalizedInstanceId or nil
    )
end

function LuckyBlockService:_clearToolConnections(player)
    if not player then
        return
    end

    local connectionList = self._toolConnectionsByUserId[player.UserId]
    if connectionList then
        disconnectConnectionList(connectionList)
        self._toolConnectionsByUserId[player.UserId] = nil
    end
end

function LuckyBlockService:_createToolHandle()
    local handle = Instance.new("Part")
    handle.Name = "Handle"
    handle.Size = Vector3.new(1, 1, 1)
    handle.Transparency = 1
    handle.Anchored = false
    handle.CanCollide = false
    handle.CanTouch = false
    handle.CanQuery = false
    handle.Massless = true
    return handle
end

function LuckyBlockService:_resolveBlockTemplate(blockEntry)
    if type(blockEntry) ~= "table" then
        return nil
    end

    local modelPath = tostring(blockEntry.ModelPath or "")
    local template = findReplicatedStoragePath(modelPath)
    if template and (template:IsA("Model") or template:IsA("BasePart")) then
        return template
    end

    if modelPath ~= "" and not self._didWarnMissingAssetByPath[modelPath] then
        self._didWarnMissingAssetByPath[modelPath] = true
        warn(string.format("[LuckyBlockService] 找不到幸运方块模型 %s", modelPath))
    end

    return nil
end

function LuckyBlockService:_attachToolVisual(tool, blockEntry, handle)
    if not (tool and handle) then
        return false
    end

    local template = self:_resolveBlockTemplate(blockEntry)
    if not template then
        return false
    end

    local visualClone = template:Clone()
    visualClone.Name = tostring(LuckyBlockConfig.RuntimeVisualName or "VisualModel")
    visualClone.Parent = tool
    moveInstanceToCFrame(visualClone, handle.CFrame)

    local visualParts = {}
    if visualClone:IsA("BasePart") then
        table.insert(visualParts, visualClone)
    end

    for _, descendant in ipairs(visualClone:GetDescendants()) do
        if descendant:IsA("BasePart") then
            table.insert(visualParts, descendant)
        elseif descendant:IsA("ProximityPrompt") or descendant:IsA("BillboardGui") then
            descendant:Destroy()
        elseif descendant:IsA("JointInstance") or descendant:IsA("Constraint") then
            descendant:Destroy()
        elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
            descendant.Disabled = true
        end
    end

    for _, visualPart in ipairs(visualParts) do
        setVisualPartProperties(visualPart)
        local weld = Instance.new("WeldConstraint")
        weld.Part0 = handle
        weld.Part1 = visualPart
        weld.Parent = visualPart
    end

    return true
end

function LuckyBlockService:_onToolEquipped(player, tool)
    local _playerData, luckyBlockState = self:_getPlayerDataAndState(player)
    if not luckyBlockState then
        return
    end

    luckyBlockState.EquippedInstanceId = normalizeInteger(
        tool and tool:GetAttribute(LuckyBlockConfig.ToolInstanceIdAttributeName),
        0
    )
    self:_applyEquippedAttributes(
        player,
        tool and tool:GetAttribute(LuckyBlockConfig.ToolBlockIdAttributeName),
        luckyBlockState.EquippedInstanceId
    )
end

function LuckyBlockService:_onToolUnequipped(player, tool)
    local _playerData, luckyBlockState = self:_getPlayerDataAndState(player)
    if not luckyBlockState then
        return
    end

    local instanceId = normalizeInteger(
        tool and tool:GetAttribute(LuckyBlockConfig.ToolInstanceIdAttributeName),
        0
    )
    if luckyBlockState.EquippedInstanceId == instanceId then
        luckyBlockState.EquippedInstanceId = 0
        self:_applyEquippedAttributes(player, 0, 0)
    end
end

function LuckyBlockService:_createLuckyBlockTool(player, inventoryItem)
    local blockId = normalizeInteger(inventoryItem and inventoryItem.BlockId, 0)
    local instanceId = normalizeInteger(inventoryItem and inventoryItem.InstanceId, 0)
    local blockEntry = LuckyBlockConfig.EntriesById[blockId]
    if not blockEntry or instanceId <= 0 then
        return nil
    end

    local tool = Instance.new("Tool")
    tool.Name = tostring(blockEntry.Name or "Lucky Block")
    tool.CanBeDropped = false
    tool.TextureId = tostring(blockEntry.Icon or "")
    tool.RequiresHandle = true
    tool.ManualActivationOnly = true
    tool:SetAttribute(LuckyBlockConfig.ToolAttributeName, true)
    tool:SetAttribute(LuckyBlockConfig.ToolBlockIdAttributeName, blockId)
    tool:SetAttribute(LuckyBlockConfig.ToolInstanceIdAttributeName, instanceId)
    tool:SetAttribute(LuckyBlockConfig.ToolModelPathAttributeName, tostring(blockEntry.ModelPath or ""))

    local handle = self:_createToolHandle()
    handle.Parent = tool
    self:_attachToolVisual(tool, blockEntry, handle)

    local connectionList = ensureConnectionBucket(self._toolConnectionsByUserId, player.UserId)
    table.insert(connectionList, tool.Equipped:Connect(function()
        self:_onToolEquipped(player, tool)
    end))
    table.insert(connectionList, tool.Unequipped:Connect(function()
        self:_onToolUnequipped(player, tool)
    end))

    return tool
end

function LuckyBlockService:_removeLuckyBlockTools(player)
    if not player then
        return
    end

    local containers = {
        player:FindFirstChild("Backpack"),
        player.Character,
    }

    for _, container in ipairs(containers) do
        if container then
            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("Tool") and child:GetAttribute(LuckyBlockConfig.ToolAttributeName) == true then
                    child:Destroy()
                end
            end
        end
    end
end

function LuckyBlockService:_refreshLuckyBlockTools(player)
    local _playerData, luckyBlockState = self:_getPlayerDataAndState(player)
    if not luckyBlockState then
        return
    end

    self:_clearToolConnections(player)
    self:_removeLuckyBlockTools(player)
    luckyBlockState.EquippedInstanceId = 0
    self:_applyEquippedAttributes(player, 0, 0)

    local backpack = player:FindFirstChild("Backpack") or player:WaitForChild("Backpack", 2)
    if not backpack then
        return
    end

    for _, inventoryItem in ipairs(luckyBlockState.Inventory or {}) do
        local tool = self:_createLuckyBlockTool(player, inventoryItem)
        if tool then
            tool.Parent = backpack
        end
    end
end

function LuckyBlockService:_findLuckyBlockToolByInstanceId(player, instanceId)
    local targetInstanceId = normalizeInteger(instanceId, 0)
    if not player or targetInstanceId <= 0 then
        return nil
    end

    local containers = {
        player:FindFirstChild("Backpack"),
        player.Character,
    }
    for _, container in ipairs(containers) do
        if container then
            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("Tool")
                    and child:GetAttribute(LuckyBlockConfig.ToolAttributeName) == true
                    and normalizeInteger(child:GetAttribute(LuckyBlockConfig.ToolInstanceIdAttributeName), 0) == targetInstanceId
                then
                    return child
                end
            end
        end
    end

    return nil
end

function LuckyBlockService:_equipLuckyBlockToolByInstanceId(player, instanceId)
    local tool = self:_findLuckyBlockToolByInstanceId(player, instanceId)
    if not tool then
        return false
    end

    local character = player and player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return false
    end

    humanoid:EquipTool(tool)
    return true
end

function LuckyBlockService:_getEquippedLuckyBlockTool(player)
    local character = player and player.Character
    if not character then
        return nil
    end

    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("Tool") and child:GetAttribute(LuckyBlockConfig.ToolAttributeName) == true then
            return child
        end
    end

    return nil
end

function LuckyBlockService:_bindCharacterWatcher(player)
    if not player then
        return
    end

    local userId = player.UserId
    local previousConnection = self._characterAddedConnectionsByUserId[userId]
    if previousConnection then
        previousConnection:Disconnect()
        self._characterAddedConnectionsByUserId[userId] = nil
    end

    self._characterAddedConnectionsByUserId[userId] = player.CharacterAdded:Connect(function()
        task.defer(function()
            if player.Parent then
                self:_refreshLuckyBlockTools(player)
            end
        end)
    end)
end

function LuckyBlockService:_canSendRequest(player)
    if not player then
        return false
    end

    local debounceSeconds = math.max(0.05, tonumber(LuckyBlockConfig.RequestDebounceSeconds) or 0.35)
    local userId = player.UserId
    local nowClock = os.clock()
    local lastClock = tonumber(self._lastRequestClockByUserId[userId]) or 0
    if nowClock - lastClock < debounceSeconds then
        return false
    end

    self._lastRequestClockByUserId[userId] = nowClock
    return true
end

function LuckyBlockService:_getHomelandPart()
    local homelandPart = findPathFromRoot(Workspace, tostring(LuckyBlockConfig.HomelandPath or ""))
    if homelandPart and homelandPart:IsA("BasePart") then
        return homelandPart
    end
    return nil
end

function LuckyBlockService:_resolveHomelandGroundPosition(requestedPosition)
    if typeof(requestedPosition) ~= "Vector3" then
        return nil, nil
    end

    local homelandPart = self:_getHomelandPart()
    if not homelandPart then
        return nil, nil
    end

    if not isPointInsidePartHorizontalBounds(homelandPart, requestedPosition) then
        return nil, homelandPart
    end

    local groundY = homelandPart.Position.Y + (homelandPart.Size.Y * 0.5)
    return Vector3.new(requestedPosition.X, groundY, requestedPosition.Z), homelandPart
end

function LuckyBlockService:_rollBrainrotId(poolId)
    local poolEntries = LuckyBlockConfig.Pools[normalizeInteger(poolId, 0)]
    if type(poolEntries) ~= "table" or #poolEntries <= 0 then
        return 0
    end

    local totalWeight = 0
    for _, entry in ipairs(poolEntries) do
        if BrainrotConfig.ById[normalizeInteger(entry and entry.BrainrotId, 0)] then
            totalWeight += math.max(0, tonumber(entry and entry.Weight) or 0)
        end
    end

    if totalWeight <= 0 then
        return 0
    end

    local roll = self._random:NextNumber(0, totalWeight)
    local cursor = 0
    for _, entry in ipairs(poolEntries) do
        local brainrotId = normalizeInteger(entry and entry.BrainrotId, 0)
        local weight = math.max(0, tonumber(entry and entry.Weight) or 0)
        if BrainrotConfig.ById[brainrotId] and weight > 0 then
            cursor += weight
            if roll <= cursor then
                return brainrotId
            end
        end
    end

    local lastEntry = poolEntries[#poolEntries]
    return normalizeInteger(lastEntry and lastEntry.BrainrotId, 0)
end

function LuckyBlockService:_getPendingRewardBucket(userId)
    local bucket = self._pendingRewardsByUserId[userId]
    if type(bucket) ~= "table" then
        bucket = {}
        self._pendingRewardsByUserId[userId] = bucket
    end
    return bucket
end

function LuckyBlockService:_removePendingReward(pendingReward, shouldCancelThread)
    if type(pendingReward) ~= "table" then
        return
    end

    local userId = normalizeInteger(pendingReward.UserId, 0)
    local requestId = tostring(pendingReward.RequestId or "")
    if userId > 0 then
        local bucket = self._pendingRewardsByUserId[userId]
        if type(bucket) == "table" then
            bucket[requestId] = nil
            if next(bucket) == nil then
                self._pendingRewardsByUserId[userId] = nil
            end
        end
    end

    if requestId ~= "" then
        local scheduledThread = self._pendingRewardThreadsByRequestId[requestId]
        self._pendingRewardThreadsByRequestId[requestId] = nil
        if shouldCancelThread == true and scheduledThread then
            pcall(task.cancel, scheduledThread)
        end
    end
end

function LuckyBlockService:_restoreConsumedBlock(player, luckyBlockState, pendingReward)
    if not (player and luckyBlockState and type(pendingReward) == "table") then
        return
    end

    local restoreItem = pendingReward.RemovedItem
    local restoreInstanceId = normalizeInteger(type(restoreItem) == "table" and restoreItem.InstanceId, 0)
    local restoreBlockId = normalizeInteger(type(restoreItem) == "table" and restoreItem.BlockId, 0)
    if restoreInstanceId <= 0 or restoreBlockId <= 0 then
        return
    end

    if findInventoryIndexByInstanceId(luckyBlockState.Inventory, restoreInstanceId) then
        return
    end

    local insertIndex = math.clamp(
        normalizeInteger(pendingReward.InventoryIndex, #luckyBlockState.Inventory + 1),
        1,
        #luckyBlockState.Inventory + 1
    )
    table.insert(luckyBlockState.Inventory, insertIndex, {
        BlockId = restoreBlockId,
        InstanceId = restoreInstanceId,
    })

    if player.Parent then
        local backpack = player:FindFirstChild("Backpack") or player:WaitForChild("Backpack", 2)
        if backpack then
            local tool = self:_createLuckyBlockTool(player, restoreItem)
            if tool then
                tool.Parent = backpack
            end
        else
            self:_refreshLuckyBlockTools(player)
        end
    end
end

function LuckyBlockService:_completePendingReward(pendingReward, suppressClientFeedback)
    if type(pendingReward) ~= "table" or pendingReward.Completed == true then
        return
    end

    pendingReward.Completed = true
    self:_removePendingReward(pendingReward, false)

    local player = pendingReward.Player
    local requestId = tostring(pendingReward.RequestId or "")
    if not player then
        return
    end

    local _playerData, luckyBlockState = self:_getPlayerDataAndState(player)
    if not luckyBlockState then
        return
    end

    local luckyBlockSnapshot = type(pendingReward.LuckyBlockSnapshot) == "table"
        and pendingReward.LuckyBlockSnapshot
        or self:_createStateSnapshot(luckyBlockState)
    local brainrotSnapshot = self._brainrotService and self._brainrotService.CreatePlayerStateSnapshot
        and self._brainrotService:CreatePlayerStateSnapshot(player)
        or nil

    local grantSuccess, grantStatus, grantedCount = self._brainrotService:GrantBrainrot(
        player,
        normalizeInteger(pendingReward.BrainrotId, 0),
        1,
        tostring(LuckyBlockConfig.GrantReason or "LuckyBlockOpen")
    )

    if not grantSuccess or normalizeInteger(grantedCount, 0) <= 0 then
        if brainrotSnapshot and self._brainrotService and self._brainrotService.RestorePlayerStateSnapshot then
            self._brainrotService:RestorePlayerStateSnapshot(player, brainrotSnapshot)
        end
        if luckyBlockSnapshot then
            self:_restoreStateSnapshot(player, luckyBlockState, luckyBlockSnapshot)
        else
            self:_restoreConsumedBlock(player, luckyBlockState, pendingReward)
        end

        if suppressClientFeedback ~= true and player.Parent then
            self:_pushFeedback(player, {
                requestId = requestId,
                status = "GrantFailed",
                blockId = normalizeInteger(pendingReward.BlockId, 0),
                blockInstanceId = normalizeInteger(pendingReward.BlockInstanceId, 0),
                brainrotId = normalizeInteger(pendingReward.BrainrotId, 0),
                brainrotName = tostring(pendingReward.BrainrotName or ""),
                errorReason = tostring(grantStatus or "GrantFailed"),
            })
        end
        return
    end

    local didSave = not self._playerDataService or self._playerDataService:SavePlayerData(player)
    if not didSave then
        if brainrotSnapshot and self._brainrotService and self._brainrotService.RestorePlayerStateSnapshot then
            self._brainrotService:RestorePlayerStateSnapshot(player, brainrotSnapshot)
        end
        if luckyBlockSnapshot then
            self:_restoreStateSnapshot(player, luckyBlockState, luckyBlockSnapshot)
        else
            self:_restoreConsumedBlock(player, luckyBlockState, pendingReward)
        end

        if suppressClientFeedback ~= true and player.Parent then
            self:_pushFeedback(player, {
                requestId = requestId,
                status = "GrantFailed",
                blockId = normalizeInteger(pendingReward.BlockId, 0),
                blockInstanceId = normalizeInteger(pendingReward.BlockInstanceId, 0),
                brainrotId = normalizeInteger(pendingReward.BrainrotId, 0),
                brainrotName = tostring(pendingReward.BrainrotName or ""),
                errorReason = "SaveFailed",
            })
        end
        return
    end

    if suppressClientFeedback ~= true and player.Parent then
        self:_pushFeedback(player, {
            requestId = requestId,
            status = "Success",
            blockId = normalizeInteger(pendingReward.BlockId, 0),
            blockInstanceId = normalizeInteger(pendingReward.BlockInstanceId, 0),
            brainrotId = normalizeInteger(pendingReward.BrainrotId, 0),
            brainrotName = tostring(pendingReward.BrainrotName or "Brainrot"),
            worldPosition = pendingReward.WorldPosition,
        })
    end
end

function LuckyBlockService:_schedulePendingReward(player, pendingReward)
    if not (player and type(pendingReward) == "table") then
        return
    end

    local requestId = tostring(pendingReward.RequestId or "")
    if requestId == "" then
        return
    end

    local bucket = self:_getPendingRewardBucket(player.UserId)
    bucket[requestId] = pendingReward

    local grantDelaySeconds = math.max(
        0.1,
        tonumber(pendingReward.GrantDelaySeconds)
            or tonumber(LuckyBlockConfig.FinalRevealHoldSeconds)
            or 1
    )

    self._pendingRewardThreadsByRequestId[requestId] = task.delay(grantDelaySeconds, function()
        self:_completePendingReward(pendingReward, false)
    end)
end

function LuckyBlockService:GrantBlock(player, blockId, quantity, _reason, options)
    local _playerData, luckyBlockState = self:_getPlayerDataAndState(player)
    if not luckyBlockState then
        return false, "MissingData", 0
    end

    local normalizedBlockId = normalizeInteger(blockId, 0)
    local normalizedQuantity = normalizeInteger(quantity, 0)
    if normalizedBlockId <= 0 or normalizedQuantity <= 0 then
        return false, "InvalidArguments", 0
    end

    local blockEntry = LuckyBlockConfig.EntriesById[normalizedBlockId]
    if not blockEntry then
        return false, "InvalidBlock", 0
    end

    local grantedItems = {}
    for _ = 1, normalizedQuantity do
        local nextInstanceId = math.max(1, normalizeInteger(luckyBlockState.NextInstanceId, 1))
        luckyBlockState.NextInstanceId = nextInstanceId + 1
        local inventoryItem = {
            BlockId = normalizedBlockId,
            InstanceId = nextInstanceId,
        }
        table.insert(luckyBlockState.Inventory, inventoryItem)
        table.insert(grantedItems, inventoryItem)
    end

    local backpack = player:FindFirstChild("Backpack") or player:WaitForChild("Backpack", 2)
    if backpack then
        for _, inventoryItem in ipairs(grantedItems) do
            local tool = self:_createLuckyBlockTool(player, inventoryItem)
            if tool then
                tool.Parent = backpack
            end
        end
    else
        self:_refreshLuckyBlockTools(player)
    end

    if not (type(options) == "table" and options.SkipSave == true) then
        self:_savePlayerDataAsync(player)
    end
    return true, "Success", #grantedItems
end

function LuckyBlockService:_handleRequestLuckyBlockOpen(player, payload)
    if not player then
        return
    end

    local requestId = tostring(type(payload) == "table" and payload.requestId or "")
    if not self:_canSendRequest(player) then
        self:_pushFeedback(player, {
            requestId = requestId,
            status = "Debounced",
        })
        return
    end

    local requestedPosition = type(payload) == "table" and payload.position or nil
    if typeof(requestedPosition) ~= "Vector3" then
        requestedPosition = nil
    end

    local blockInstanceId = normalizeInteger(type(payload) == "table" and payload.blockInstanceId, 0)
    local _playerData, luckyBlockState = self:_getPlayerDataAndState(player)
    if not luckyBlockState then
        self:_pushFeedback(player, {
            requestId = requestId,
            status = "MissingData",
        })
        return
    end

    local inventoryIndex = findInventoryIndexByInstanceId(luckyBlockState.Inventory, blockInstanceId)
    local inventoryItem = inventoryIndex and luckyBlockState.Inventory[inventoryIndex] or nil
    local blockId = normalizeInteger(inventoryItem and inventoryItem.BlockId, 0)
    local blockEntry = LuckyBlockConfig.EntriesById[blockId]
    if not inventoryItem or not blockEntry then
        self:_pushFeedback(player, {
            requestId = requestId,
            status = "BlockNotOwned",
            blockInstanceId = blockInstanceId,
        })
        return
    end

    local equippedTool = self:_getEquippedLuckyBlockTool(player)
    if not equippedTool
        or normalizeInteger(equippedTool:GetAttribute(LuckyBlockConfig.ToolInstanceIdAttributeName), 0) ~= blockInstanceId
    then
        self:_pushFeedback(player, {
            requestId = requestId,
            status = "NotEquipped",
            blockId = blockId,
            blockInstanceId = blockInstanceId,
        })
        return
    end

    local groundPosition, homelandPart = self:_resolveHomelandGroundPosition(requestedPosition)
    if not groundPosition or not homelandPart then
        self:_pushFeedback(player, {
            requestId = requestId,
            status = "InvalidTarget",
            blockId = blockId,
            blockInstanceId = blockInstanceId,
        })
        return
    end

    local grantedBrainrotId = self:_rollBrainrotId(blockEntry.PoolId)
    local grantedBrainrotDefinition = BrainrotConfig.ById[grantedBrainrotId]
    if not grantedBrainrotDefinition then
        self:_pushFeedback(player, {
            requestId = requestId,
            status = "EmptyPool",
            blockId = blockId,
            blockInstanceId = blockInstanceId,
        })
        return
    end

    local luckyBlockSnapshot = self:_createStateSnapshot(luckyBlockState)
    local removedItem = table.remove(luckyBlockState.Inventory, inventoryIndex)
    if normalizeInteger(luckyBlockState.EquippedInstanceId, 0) == blockInstanceId then
        luckyBlockState.EquippedInstanceId = 0
        self:_applyEquippedAttributes(player, 0, 0)
    end

    if equippedTool and equippedTool.Parent then
        equippedTool:Destroy()
    else
        local staleTool = self:_findLuckyBlockToolByInstanceId(player, blockInstanceId)
        if staleTool and staleTool.Parent then
            staleTool:Destroy()
        end
    end


    local grantDelaySeconds = math.max(
        0.1,
        (
            math.max(1, normalizeInteger(LuckyBlockConfig.RouletteRounds, 1))
            * (
                math.max(0.01, tonumber(LuckyBlockConfig.RouletteStartIntervalSeconds) or 0.18)
                + math.max(0.01, tonumber(LuckyBlockConfig.RouletteEndIntervalSeconds) or 0.045)
            )
            * 3
        )
            + math.max(0.1, tonumber(LuckyBlockConfig.FinalRevealHoldSeconds) or 1)
            + math.max(0, tonumber(LuckyBlockConfig.ServerGrantBufferSeconds) or 0.15)
    )

    local pendingReward = {
        Player = player,
        UserId = player.UserId,
        RequestId = requestId,
        BlockId = blockId,
        BlockInstanceId = blockInstanceId,
        BrainrotId = grantedBrainrotId,
        BrainrotName = tostring(grantedBrainrotDefinition.Name or "Brainrot"),
        WorldPosition = groundPosition,
        InventoryIndex = inventoryIndex,
        RemovedItem = removedItem,
        LuckyBlockSnapshot = luckyBlockSnapshot,
        GrantDelaySeconds = grantDelaySeconds,
        Completed = false,
    }

    self:_schedulePendingReward(player, pendingReward)
    self:_pushFeedback(player, {
        requestId = requestId,
        status = "Accepted",
        blockId = blockId,
        blockInstanceId = blockInstanceId,
        brainrotId = grantedBrainrotId,
        brainrotName = tostring(grantedBrainrotDefinition.Name or "Brainrot"),
        worldPosition = groundPosition,
        grantDelaySeconds = grantDelaySeconds,
    })
end

function LuckyBlockService:Init(dependencies)
    self._playerDataService = dependencies.PlayerDataService
    self._brainrotService = dependencies.BrainrotService

    local remoteEventService = dependencies.RemoteEventService
    self._requestLuckyBlockOpenEvent = remoteEventService:GetEvent("RequestLuckyBlockOpen")
    self._luckyBlockFeedbackEvent = remoteEventService:GetEvent("LuckyBlockFeedback")

    if self._requestLuckyBlockOpenEvent then
        self._requestLuckyBlockOpenEvent.OnServerEvent:Connect(function(player, payload)
            self:_handleRequestLuckyBlockOpen(player, payload)
        end)
    end
end

function LuckyBlockService:OnPlayerReady(player)
    local _playerData, luckyBlockState = self:_getPlayerDataAndState(player)
    if not luckyBlockState then
        return
    end

    self:_bindCharacterWatcher(player)
    self:_refreshLuckyBlockTools(player)
end

function LuckyBlockService:OnPlayerRemoving(player)
    if not player then
        return
    end

    local userId = player.UserId
    local pendingRewards = self._pendingRewardsByUserId[userId]
    if type(pendingRewards) == "table" then
        local snapshot = {}
        for _, pendingReward in pairs(pendingRewards) do
            table.insert(snapshot, pendingReward)
        end
        for _, pendingReward in ipairs(snapshot) do
            self:_completePendingReward(pendingReward, true)
        end
    end

    self._lastRequestClockByUserId[userId] = nil
    self:_applyEquippedAttributes(player, 0, 0)
    self:_clearToolConnections(player)

    local characterAddedConnection = self._characterAddedConnectionsByUserId[userId]
    if characterAddedConnection then
        characterAddedConnection:Disconnect()
        self._characterAddedConnectionsByUserId[userId] = nil
    end
end

return LuckyBlockService
