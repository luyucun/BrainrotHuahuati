--[[
脚本名字: JetpackService
脚本文件: JetpackService.lua
脚本类型: ModuleScript
Studio放置路径: ServerScriptService/Services/JetpackService
]]

local Players = game:GetService("Players")
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
        "[JetpackService] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local JetpackConfig = requireSharedModule("JetpackConfig")

local JetpackService = {}
JetpackService._playerDataService = nil
JetpackService._currencyService = nil
JetpackService._jetpackStateSyncEvent = nil
JetpackService._requestJetpackStateSyncEvent = nil
JetpackService._requestJetpackCoinPurchaseEvent = nil
JetpackService._requestJetpackEquipEvent = nil
JetpackService._jetpackFeedbackEvent = nil
JetpackService._lastRequestClockByUserId = {}
JetpackService._characterAddedConnectionsByUserId = {}
JetpackService._applySerialByUserId = {}
JetpackService._didWarnMissingAssetByPath = {}

local function normalizeJetpackId(value)
    return math.max(0, math.floor(tonumber(value) or 0))
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

local function findReplicatedStoragePath(pathText)
    local segments = splitSlashPath(pathText)
    if #segments <= 0 then
        return nil
    end

    local current = ReplicatedStorage
    local startIndex = 1
    if segments[1] == "ReplicatedStorage" then
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

local function normalizeOwnedJetpackIds(sourceValue)
    local ownedJetpackIds = {}
    if type(sourceValue) == "table" then
        for key, value in pairs(sourceValue) do
            local jetpackId = 0
            if value == true then
                jetpackId = normalizeJetpackId(key)
            elseif type(value) == "number" or type(value) == "string" then
                jetpackId = normalizeJetpackId(value)
            elseif type(value) == "table" then
                jetpackId = normalizeJetpackId(value.Id or value.id)
            end

            if JetpackConfig.EntriesById[jetpackId] then
                ownedJetpackIds[jetpackId] = true
            end
        end
    end

    for _, entry in ipairs(JetpackConfig.Entries) do
        if entry.IsDefaultUnlocked then
            ownedJetpackIds[entry.Id] = true
        end
    end

    return ownedJetpackIds
end

local function normalizeProcessedPurchaseIds(sourceValue)
    local processedPurchaseIds = {}
    if type(sourceValue) ~= "table" then
        return processedPurchaseIds
    end

    for key, value in pairs(sourceValue) do
        local purchaseId = tostring(key or "")
        if purchaseId ~= "" then
            processedPurchaseIds[purchaseId] = math.max(0, math.floor(tonumber(value) or os.time()))
        end
    end

    return processedPurchaseIds
end

local function copyFlatMap(sourceValue)
    local copy = {}
    if type(sourceValue) ~= "table" then
        return copy
    end

    for key, value in pairs(sourceValue) do
        copy[key] = value
    end

    return copy
end

local function buildOwnedJetpackIdList(ownedJetpackIds)
    local ownedIdList = {}
    if type(ownedJetpackIds) ~= "table" then
        return ownedIdList
    end

    for jetpackId, isOwned in pairs(ownedJetpackIds) do
        if isOwned == true then
            table.insert(ownedIdList, normalizeJetpackId(jetpackId))
        end
    end

    table.sort(ownedIdList)
    return ownedIdList
end

local function getFallbackEquippedJetpackId(ownedJetpackIds)
    local defaultEntryId = normalizeJetpackId(JetpackConfig.DefaultEntryId)
    if defaultEntryId > 0 and type(ownedJetpackIds) == "table" and ownedJetpackIds[defaultEntryId] == true then
        return defaultEntryId
    end

    local smallestOwnedId = 0
    if type(ownedJetpackIds) == "table" then
        for jetpackId, isOwned in pairs(ownedJetpackIds) do
            local parsedJetpackId = normalizeJetpackId(jetpackId)
            if isOwned == true and parsedJetpackId > 0 and (smallestOwnedId <= 0 or parsedJetpackId < smallestOwnedId) then
                smallestOwnedId = parsedJetpackId
            end
        end
    end

    return smallestOwnedId
end

local function ensureJetpackState(playerData)
    if type(playerData) ~= "table" then
        return nil
    end

    local jetpackState = playerData.JetpackState
    if type(jetpackState) ~= "table" then
        jetpackState = {}
        playerData.JetpackState = jetpackState
    end

    local ownedJetpackIds = normalizeOwnedJetpackIds(jetpackState.OwnedJetpackIds)
    local processedPurchaseIds = normalizeProcessedPurchaseIds(jetpackState.ProcessedPurchaseIds)
    local equippedJetpackId = normalizeJetpackId(jetpackState.EquippedJetpackId)
    if not ownedJetpackIds[equippedJetpackId] then
        equippedJetpackId = getFallbackEquippedJetpackId(ownedJetpackIds)
    end

    jetpackState.OwnedJetpackIds = ownedJetpackIds
    jetpackState.ProcessedPurchaseIds = processedPurchaseIds
    jetpackState.EquippedJetpackId = equippedJetpackId
    return jetpackState
end

function JetpackService:_getPlayerDataAndState(player)
    if not (self._playerDataService and player) then
        return nil, nil
    end

    local playerData = self._playerDataService:GetPlayerData(player)
    if type(playerData) ~= "table" then
        return nil, nil
    end

    return playerData, ensureJetpackState(playerData)
end

function JetpackService:_applyPlayerAttributes(player, equippedJetpackId)
    if not player then
        return
    end

    local normalizedJetpackId = normalizeJetpackId(equippedJetpackId)
    local entry = JetpackConfig.EntriesById[normalizedJetpackId]
    player:SetAttribute("EquippedJetpackId", normalizedJetpackId > 0 and normalizedJetpackId or nil)
    player:SetAttribute("EquippedJetpackName", entry and entry.Name or nil)
end

function JetpackService:_buildStatePayload(player)
    local _playerData, jetpackState = self:_getPlayerDataAndState(player)
    local ownedJetpackIds = jetpackState and jetpackState.OwnedJetpackIds or normalizeOwnedJetpackIds(nil)
    local equippedJetpackId = jetpackState and normalizeJetpackId(jetpackState.EquippedJetpackId) or getFallbackEquippedJetpackId(ownedJetpackIds)

    return {
        ownedJetpackIds = buildOwnedJetpackIdList(ownedJetpackIds),
        equippedJetpackId = equippedJetpackId,
        timestamp = os.clock(),
    }
end

function JetpackService:PushJetpackState(player)
    if not (player and self._jetpackStateSyncEvent) then
        return
    end

    self._jetpackStateSyncEvent:FireClient(player, self:_buildStatePayload(player))
end

function JetpackService:_pushFeedback(player, status, jetpackId, message)
    if not (player and self._jetpackFeedbackEvent) then
        return
    end

    self._jetpackFeedbackEvent:FireClient(player, {
        status = tostring(status or "Unknown"),
        jetpackId = normalizeJetpackId(jetpackId),
        message = tostring(message or ""),
        timestamp = os.clock(),
    })
end

function JetpackService:_canSendRequest(player)
    if not player then
        return false
    end

    local debounceSeconds = math.max(0.05, tonumber(JetpackConfig.RequestDebounceSeconds) or 0.2)
    local userId = player.UserId
    local nowClock = os.clock()
    local lastClock = tonumber(self._lastRequestClockByUserId[userId]) or 0
    if nowClock - lastClock < debounceSeconds then
        return false
    end

    self._lastRequestClockByUserId[userId] = nowClock
    return true
end

function JetpackService:_savePlayerDataAsync(player)
    if not (self._playerDataService and player) then
        return
    end

    task.spawn(function()
        self._playerDataService:SavePlayerData(player)
    end)
end
function JetpackService:_resolveAccessoryTemplate(entry)
    if type(entry) ~= "table" then
        return nil
    end

    local assetPath = tostring(entry.AssetPath or "")
    local accessoryTemplate = findReplicatedStoragePath(assetPath)
    if accessoryTemplate and accessoryTemplate:IsA("Accessory") then
        return accessoryTemplate
    end

    if assetPath ~= "" and not self._didWarnMissingAssetByPath[assetPath] then
        self._didWarnMissingAssetByPath[assetPath] = true
        warn(string.format("[JetpackService] 找不到喷气背包饰品 %s", assetPath))
    end

    return nil
end

function JetpackService:_clearRuntimeAccessories(character)
    if not character then
        return
    end

    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("Accessory") and child:GetAttribute(JetpackConfig.RuntimeAccessoryAttributeName) == true then
            child:Destroy()
        end
    end
end

function JetpackService:_applyEquippedJetpackToCharacter(player, character)
    if not (player and character and character.Parent) then
        return
    end

    local _playerData, jetpackState = self:_getPlayerDataAndState(player)
    if not jetpackState then
        return
    end

    local equippedJetpackId = normalizeJetpackId(jetpackState.EquippedJetpackId)
    local ownedJetpackIds = jetpackState.OwnedJetpackIds or {}
    if not ownedJetpackIds[equippedJetpackId] then
        equippedJetpackId = getFallbackEquippedJetpackId(ownedJetpackIds)
        jetpackState.EquippedJetpackId = equippedJetpackId
        self:_applyPlayerAttributes(player, equippedJetpackId)
    end

    self:_clearRuntimeAccessories(character)

    local entry = JetpackConfig.EntriesById[equippedJetpackId]
    if not entry then
        return
    end

    local accessoryTemplate = self:_resolveAccessoryTemplate(entry)
    if not accessoryTemplate then
        return
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
    if not humanoid then
        return
    end

    local accessoryClone = accessoryTemplate:Clone()
    accessoryClone:SetAttribute(JetpackConfig.RuntimeAccessoryAttributeName, true)
    accessoryClone:SetAttribute(JetpackConfig.RuntimeJetpackIdAttributeName, entry.Id)

    local success, err = pcall(function()
        humanoid:AddAccessory(accessoryClone)
    end)
    if success then
        return
    end

    warn(string.format("[JetpackService] 装备喷气背包失败 id=%d err=%s", entry.Id, tostring(err)))
    accessoryClone.Parent = character
end

function JetpackService:_scheduleApplyEquippedJetpack(player, character)
    if not player then
        return
    end

    local userId = player.UserId
    local serial = (tonumber(self._applySerialByUserId[userId]) or 0) + 1
    self._applySerialByUserId[userId] = serial

    task.defer(function()
        task.wait()
        if self._applySerialByUserId[userId] ~= serial then
            return
        end

        if not (player.Parent and character and character.Parent) then
            return
        end

        if player.Character ~= character then
            return
        end

        self:_applyEquippedJetpackToCharacter(player, character)
    end)
end

function JetpackService:_bindCharacterWatcher(player)
    if not player then
        return
    end

    local userId = player.UserId
    local previousConnection = self._characterAddedConnectionsByUserId[userId]
    if previousConnection then
        previousConnection:Disconnect()
        self._characterAddedConnectionsByUserId[userId] = nil
    end

    self._characterAddedConnectionsByUserId[userId] = player.CharacterAdded:Connect(function(character)
        self:_scheduleApplyEquippedJetpack(player, character)
    end)

    if player.Character then
        self:_scheduleApplyEquippedJetpack(player, player.Character)
    end
end

function JetpackService:_handleRequestJetpackStateSync(player)
    if not player then
        return
    end

    self:PushJetpackState(player)
end

function JetpackService:_handleRequestJetpackCoinPurchase(player, payload)
    if not player then
        return
    end

    if not self:_canSendRequest(player) then
        self:_pushFeedback(player, "Debounced", 0, "")
        return
    end

    local jetpackId = normalizeJetpackId(type(payload) == "table" and payload.jetpackId or 0)
    local entry = JetpackConfig.EntriesById[jetpackId]
    if not entry then
        self:PushJetpackState(player)
        self:_pushFeedback(player, "InvalidJetpack", jetpackId, "")
        return
    end

    local _playerData, jetpackState = self:_getPlayerDataAndState(player)
    if not jetpackState then
        self:_pushFeedback(player, "MissingData", jetpackId, "")
        return
    end

    local ownedJetpackIds = jetpackState.OwnedJetpackIds or {}
    if ownedJetpackIds[jetpackId] == true then
        self:PushJetpackState(player)
        self:_pushFeedback(player, "AlreadyOwned", jetpackId, "")
        return
    end

    local requiredCoins = math.max(0, tonumber(entry.CoinPrice) or 0)
    if requiredCoins > 0 then
        local currentCoins = self._playerDataService and self._playerDataService:GetCoins(player) or 0
        if currentCoins < requiredCoins then
            self:PushJetpackState(player)
            self:_pushFeedback(player, "InsufficientCoins", jetpackId, "")
            return
        end

        local didSpendCoins = true
        if self._currencyService then
            didSpendCoins = select(1, self._currencyService:AddCoins(player, -requiredCoins, "JetpackCoinPurchase"))
        end

        if not didSpendCoins then
            self:PushJetpackState(player)
            self:_pushFeedback(player, "SpendFailed", jetpackId, "")
            return
        end
    end

    ownedJetpackIds[jetpackId] = true
    jetpackState.OwnedJetpackIds = ownedJetpackIds
    if normalizeJetpackId(jetpackState.EquippedJetpackId) <= 0 then
        jetpackState.EquippedJetpackId = getFallbackEquippedJetpackId(ownedJetpackIds)
        self:_applyPlayerAttributes(player, jetpackState.EquippedJetpackId)
    end

    self:PushJetpackState(player)
    self:_pushFeedback(player, "CoinPurchased", jetpackId, tostring(JetpackConfig.PurchaseSuccessTipText or "Purchase Successful！"))
    self:_savePlayerDataAsync(player)
end

function JetpackService:_handleRequestJetpackEquip(player, payload)
    if not player then
        return
    end

    if not self:_canSendRequest(player) then
        self:_pushFeedback(player, "Debounced", 0, "")
        return
    end

    local jetpackId = normalizeJetpackId(type(payload) == "table" and payload.jetpackId or 0)
    local entry = JetpackConfig.EntriesById[jetpackId]
    if not entry then
        self:PushJetpackState(player)
        self:_pushFeedback(player, "InvalidJetpack", jetpackId, "")
        return
    end

    local _playerData, jetpackState = self:_getPlayerDataAndState(player)
    if not jetpackState then
        self:_pushFeedback(player, "MissingData", jetpackId, "")
        return
    end

    local ownedJetpackIds = jetpackState.OwnedJetpackIds or {}
    if ownedJetpackIds[jetpackId] ~= true then
        self:PushJetpackState(player)
        self:_pushFeedback(player, "NotOwned", jetpackId, "")
        return
    end

    jetpackState.EquippedJetpackId = jetpackId
    self:_applyPlayerAttributes(player, jetpackId)
    if player.Character then
        self:_scheduleApplyEquippedJetpack(player, player.Character)
    end

    self:PushJetpackState(player)
    self:_pushFeedback(player, "Equipped", jetpackId, "")
    self:_savePlayerDataAsync(player)
end
function JetpackService:Init(dependencies)
    self._playerDataService = dependencies.PlayerDataService
    self._currencyService = dependencies.CurrencyService

    local remoteEventService = dependencies.RemoteEventService
    self._jetpackStateSyncEvent = remoteEventService:GetEvent("JetpackStateSync")
    self._requestJetpackStateSyncEvent = remoteEventService:GetEvent("RequestJetpackStateSync")
    self._requestJetpackCoinPurchaseEvent = remoteEventService:GetEvent("RequestJetpackCoinPurchase")
    self._requestJetpackEquipEvent = remoteEventService:GetEvent("RequestJetpackEquip")
    self._jetpackFeedbackEvent = remoteEventService:GetEvent("JetpackFeedback")

    if self._requestJetpackStateSyncEvent then
        self._requestJetpackStateSyncEvent.OnServerEvent:Connect(function(player)
            self:_handleRequestJetpackStateSync(player)
        end)
    end

    if self._requestJetpackCoinPurchaseEvent then
        self._requestJetpackCoinPurchaseEvent.OnServerEvent:Connect(function(player, payload)
            self:_handleRequestJetpackCoinPurchase(player, payload)
        end)
    end

    if self._requestJetpackEquipEvent then
        self._requestJetpackEquipEvent.OnServerEvent:Connect(function(player, payload)
            self:_handleRequestJetpackEquip(player, payload)
        end)
    end
end

function JetpackService:OnPlayerReady(player)
    local _playerData, jetpackState = self:_getPlayerDataAndState(player)
    if not jetpackState then
        return
    end

    local ownedJetpackIds = jetpackState.OwnedJetpackIds or normalizeOwnedJetpackIds(nil)
    local equippedJetpackId = normalizeJetpackId(jetpackState.EquippedJetpackId)
    if not ownedJetpackIds[equippedJetpackId] then
        equippedJetpackId = getFallbackEquippedJetpackId(ownedJetpackIds)
    end

    jetpackState.EquippedJetpackId = equippedJetpackId
    self:_applyPlayerAttributes(player, jetpackState.EquippedJetpackId)
    self:_bindCharacterWatcher(player)
    self:PushJetpackState(player)
end

function JetpackService:OnPlayerRemoving(player)
    if not player then
        return
    end

    local userId = player.UserId
    local characterAddedConnection = self._characterAddedConnectionsByUserId[userId]
    if characterAddedConnection then
        characterAddedConnection:Disconnect()
        self._characterAddedConnectionsByUserId[userId] = nil
    end

    self._lastRequestClockByUserId[userId] = nil
    self._applySerialByUserId[userId] = nil
    player:SetAttribute("EquippedJetpackId", nil)
    player:SetAttribute("EquippedJetpackName", nil)
end

function JetpackService:ProcessReceipt(receiptInfo)
    local productId = normalizeJetpackId(receiptInfo and receiptInfo.ProductId)
    local entry = JetpackConfig.EntriesByProductId[productId]
    if not entry then
        return false, nil
    end

    local player = Players:GetPlayerByUserId(normalizeJetpackId(receiptInfo and receiptInfo.PlayerId))
    if not player then
        return true, Enum.ProductPurchaseDecision.NotProcessedYet
    end

    local _playerData, jetpackState = self:_getPlayerDataAndState(player)
    if not jetpackState then
        return true, Enum.ProductPurchaseDecision.NotProcessedYet
    end

    local purchaseId = tostring(receiptInfo and receiptInfo.PurchaseId or "")
    local processedPurchaseIds = jetpackState.ProcessedPurchaseIds or {}
    if purchaseId ~= "" and processedPurchaseIds[purchaseId] then
        return true, Enum.ProductPurchaseDecision.PurchaseGranted
    end

    local previousOwnedJetpackIds = copyFlatMap(jetpackState.OwnedJetpackIds)
    local previousProcessedPurchaseIds = copyFlatMap(processedPurchaseIds)
    local previousEquippedJetpackId = normalizeJetpackId(jetpackState.EquippedJetpackId)

    local ownedJetpackIds = jetpackState.OwnedJetpackIds or {}
    ownedJetpackIds[entry.Id] = true
    jetpackState.OwnedJetpackIds = ownedJetpackIds
    if purchaseId ~= "" then
        processedPurchaseIds[purchaseId] = os.time()
    end
    jetpackState.ProcessedPurchaseIds = processedPurchaseIds

    if not ownedJetpackIds[normalizeJetpackId(jetpackState.EquippedJetpackId)] then
        jetpackState.EquippedJetpackId = getFallbackEquippedJetpackId(ownedJetpackIds)
    end

    local saveSucceeded = self._playerDataService and self._playerDataService:SavePlayerData(player)
    if not saveSucceeded then
        jetpackState.OwnedJetpackIds = previousOwnedJetpackIds
        jetpackState.ProcessedPurchaseIds = previousProcessedPurchaseIds
        jetpackState.EquippedJetpackId = previousEquippedJetpackId
        self:PushJetpackState(player)
        return true, Enum.ProductPurchaseDecision.NotProcessedYet
    end

    self:_applyPlayerAttributes(player, jetpackState.EquippedJetpackId)
    if player.Character and normalizeJetpackId(jetpackState.EquippedJetpackId) == entry.Id then
        self:_scheduleApplyEquippedJetpack(player, player.Character)
    end

    self:PushJetpackState(player)
    self:_pushFeedback(player, "RobuxPurchaseGranted", entry.Id, tostring(JetpackConfig.PurchaseSuccessTipText or "Purchase Successful！"))
    return true, Enum.ProductPurchaseDecision.PurchaseGranted
end

return JetpackService
