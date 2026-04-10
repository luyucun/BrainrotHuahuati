--[[
Script: BrainrotInventoryService
Type: ModuleScript
Studio path: ServerScriptService/Services/BrainrotInventoryService
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function resolveSharedModuleScript(moduleName)
	local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
	if sharedFolder then
		local moduleInShared = sharedFolder:FindFirstChild(moduleName)
		if moduleInShared and moduleInShared:IsA("ModuleScript") then
			return moduleInShared
		end
	end

	local moduleInRoot = ReplicatedStorage:FindFirstChild(moduleName)
	if moduleInRoot and moduleInRoot:IsA("ModuleScript") then
		return moduleInRoot
	end

	return nil
end

local moduleLoaderScript = resolveSharedModuleScript("ModuleLoader")
if not moduleLoaderScript then
	error("[BrainrotInventoryService] Missing shared module ModuleLoader")
end

local ModuleLoader = require(moduleLoaderScript)
local BrainrotConfig = ModuleLoader.requireSharedModule("BrainrotInventoryService", "BrainrotConfig")

local BrainrotInventoryService = {}
BrainrotInventoryService.__index = BrainrotInventoryService

function BrainrotInventoryService.new(config)
	local self = setmetatable({}, BrainrotInventoryService)
	config = type(config) == "table" and config or {}
	self._brainrotById = type(config.brainrotById) == "table" and config.brainrotById or BrainrotConfig.ById
	self._starterBrainrotIds = type(config.starterBrainrotIds) == "table" and config.starterBrainrotIds or BrainrotConfig.StarterBrainrotIds or {}
	self._getBaseBrainrotLevel = type(config.getBaseBrainrotLevel) == "function" and config.getBaseBrainrotLevel or function()
		return 1
	end
	self._normalizeBrainrotLevel = type(config.normalizeBrainrotLevel) == "function" and config.normalizeBrainrotLevel or function(level)
		return math.max(self._getBaseBrainrotLevel(), math.floor(tonumber(level) or self._getBaseBrainrotLevel()))
	end
	self._findInventoryIndexByInstanceId = type(config.findInventoryIndexByInstanceId) == "function" and config.findInventoryIndexByInstanceId or function()
		return nil
	end
	self._buildInventoryItemSnapshot = type(config.buildInventoryItemSnapshot) == "function" and config.buildInventoryItemSnapshot or function(instanceId, brainrotId, level)
		return {
			InstanceId = instanceId,
			BrainrotId = brainrotId,
			Level = self._normalizeBrainrotLevel(level),
		}
	end
	self._getOrCreateProductionSlot = type(config.getOrCreateProductionSlot) == "function" and config.getOrCreateProductionSlot or function(_productionState, _positionKey)
		return nil
	end
	self._resetProductionSlotValues = type(config.resetProductionSlotValues) == "function" and config.resetProductionSlotValues or function(_slot)
	end
	return self
end

function BrainrotInventoryService:GetOrCreateUnlockedBrainrotMap(brainrotData)
	if type(brainrotData) ~= "table" then
		return nil
	end

	local sourceValue = brainrotData.UnlockedBrainrotIds
	local unlockedMap = {}
	if type(sourceValue) == "table" then
		for key, value in pairs(sourceValue) do
			local parsedBrainrotId = 0
			if value == true then
				parsedBrainrotId = math.floor(tonumber(key) or 0)
			elseif type(value) == "number" or type(value) == "string" then
				parsedBrainrotId = math.floor(tonumber(value) or 0)
			elseif value ~= false and value ~= nil then
				parsedBrainrotId = math.floor(tonumber(key) or 0)
			end

			if parsedBrainrotId > 0 and self._brainrotById[parsedBrainrotId] then
				unlockedMap[tostring(parsedBrainrotId)] = true
			end
		end
	end

	brainrotData.UnlockedBrainrotIds = unlockedMap
	return unlockedMap
end

function BrainrotInventoryService:MarkBrainrotUnlocked(brainrotData, brainrotId)
	local parsedBrainrotId = math.floor(tonumber(brainrotId) or 0)
	if parsedBrainrotId <= 0 or not self._brainrotById[parsedBrainrotId] then
		return false
	end

	local unlockedMap = self:GetOrCreateUnlockedBrainrotMap(brainrotData)
	if not unlockedMap then
		return false
	end

	local unlockKey = tostring(parsedBrainrotId)
	if unlockedMap[unlockKey] == true then
		return false
	end

	unlockedMap[unlockKey] = true
	return true
end

function BrainrotInventoryService:SyncUnlockedBrainrots(brainrotData, placedBrainrots)
	local unlockedMap = self:GetOrCreateUnlockedBrainrotMap(brainrotData)
	if not unlockedMap then
		return {}
	end

	if type(brainrotData.Inventory) == "table" then
		for _, inventoryItem in ipairs(brainrotData.Inventory) do
			local brainrotId = math.floor(tonumber(inventoryItem.BrainrotId) or 0)
			if brainrotId > 0 and self._brainrotById[brainrotId] then
				unlockedMap[tostring(brainrotId)] = true
			end
		end
	end

	if type(placedBrainrots) == "table" then
		for _, placedData in pairs(placedBrainrots) do
			local brainrotId = math.floor(tonumber(placedData.BrainrotId) or 0)
			if brainrotId > 0 and self._brainrotById[brainrotId] then
				unlockedMap[tostring(brainrotId)] = true
			end
		end
	end

	return unlockedMap
end

function BrainrotInventoryService:EnsureStarterInventory(brainrotData, placedBrainrots)
	if type(brainrotData) ~= "table" or type(placedBrainrots) ~= "table" then
		return false
	end

	self:SyncUnlockedBrainrots(brainrotData, placedBrainrots)

	if brainrotData.StarterGranted then
		return false
	end

	local hasPlaced = next(placedBrainrots) ~= nil
	if #brainrotData.Inventory > 0 or hasPlaced then
		brainrotData.StarterGranted = true
		return false
	end

	local didGrant = false
	for _, brainrotId in ipairs(self._starterBrainrotIds) do
		if self._brainrotById[brainrotId] then
			local instanceId = brainrotData.NextInstanceId
			brainrotData.NextInstanceId += 1

			table.insert(brainrotData.Inventory, self._buildInventoryItemSnapshot(instanceId, brainrotId, self._getBaseBrainrotLevel()))
			self:MarkBrainrotUnlocked(brainrotData, brainrotId)
			didGrant = true
		end
	end

	brainrotData.StarterGranted = true
	return didGrant
end

function BrainrotInventoryService:GrantBrainrotInstanceToData(brainrotData, brainrotId, level, reason)
	local parsedBrainrotId = math.floor(tonumber(brainrotId) or 0)
	if parsedBrainrotId <= 0 then
		return false, "InvalidBrainrotId", nil
	end

	local brainrotDefinition = self._brainrotById[parsedBrainrotId]
	if not brainrotDefinition then
		return false, "BrainrotNotFound", nil
	end
	if not brainrotData then
		return false, "PlayerDataNotReady", nil
	end

	brainrotData.StarterGranted = true
	self:MarkBrainrotUnlocked(brainrotData, parsedBrainrotId)

	local instanceId = math.max(1, math.floor(tonumber(brainrotData.NextInstanceId) or 1))
	brainrotData.NextInstanceId = instanceId + 1

	local inventoryItem = self._buildInventoryItemSnapshot(instanceId, parsedBrainrotId, level)
	table.insert(brainrotData.Inventory, inventoryItem)

	return true, tostring(reason or "Unknown"), {
		instanceId = instanceId,
		brainrotId = parsedBrainrotId,
		brainrotName = tostring(brainrotDefinition.Name or "Brainrot"),
		level = inventoryItem.Level,
		inventoryItem = self._buildInventoryItemSnapshot(instanceId, parsedBrainrotId, inventoryItem.Level),
	}
end

function BrainrotInventoryService:GrantBrainrotInstancesToData(brainrotData, brainrotId, quantity, level, reason)
	local parsedBrainrotId = math.floor(tonumber(brainrotId) or 0)
	local parsedQuantity = math.floor(tonumber(quantity) or 0)
	if parsedBrainrotId <= 0 or parsedQuantity <= 0 then
		return false, "InvalidParams", nil
	end

	local brainrotDefinition = self._brainrotById[parsedBrainrotId]
	if not brainrotDefinition then
		return false, "BrainrotNotFound", nil
	end
	if not brainrotData then
		return false, "PlayerDataNotReady", nil
	end

	brainrotData.StarterGranted = true
	self:MarkBrainrotUnlocked(brainrotData, parsedBrainrotId)

	local inventoryItems = {}
	for _ = 1, parsedQuantity do
		local instanceId = math.max(1, math.floor(tonumber(brainrotData.NextInstanceId) or 1))
		brainrotData.NextInstanceId = instanceId + 1

		local inventoryItem = self._buildInventoryItemSnapshot(instanceId, parsedBrainrotId, level)
		table.insert(brainrotData.Inventory, inventoryItem)
		table.insert(inventoryItems, self._buildInventoryItemSnapshot(instanceId, parsedBrainrotId, inventoryItem.Level))
	end

	if #inventoryItems <= 0 then
		return false, "GrantFailed", nil
	end

	return true, tostring(reason or "Unknown"), {
		grantedCount = #inventoryItems,
		brainrotId = parsedBrainrotId,
		brainrotName = tostring(brainrotDefinition.Name or "Brainrot"),
		inventoryItems = inventoryItems,
	}
end

function BrainrotInventoryService:TransferBrainrotInstanceData(senderBrainrotData, recipientBrainrotData, instanceId, reason)
	if not senderBrainrotData or not recipientBrainrotData then
		return false, "PlayerDataNotReady", nil
	end

	local targetInstanceId = math.max(0, math.floor(tonumber(instanceId) or 0))
	if targetInstanceId <= 0 then
		return false, "InvalidInstanceId", nil
	end

	local inventoryIndex = self._findInventoryIndexByInstanceId(senderBrainrotData.Inventory, targetInstanceId)
	if not inventoryIndex then
		return false, "BrainrotNotFound", nil
	end

	local inventoryItem = senderBrainrotData.Inventory[inventoryIndex]
	local brainrotId = math.max(0, math.floor(tonumber(inventoryItem and inventoryItem.BrainrotId) or 0))
	local level = self._normalizeBrainrotLevel(inventoryItem and inventoryItem.Level)
	local brainrotDefinition = self._brainrotById[brainrotId]
	if not brainrotDefinition then
		return false, "BrainrotConfigMissing", nil
	end

	local previousEquippedInstanceId = math.max(0, math.floor(tonumber(senderBrainrotData.EquippedInstanceId) or 0))
	table.remove(senderBrainrotData.Inventory, inventoryIndex)
	if previousEquippedInstanceId == targetInstanceId then
		senderBrainrotData.EquippedInstanceId = 0
	end

	local recipientInstanceId = math.max(1, math.floor(tonumber(recipientBrainrotData.NextInstanceId) or 1))
	recipientBrainrotData.NextInstanceId = recipientInstanceId + 1
	recipientBrainrotData.StarterGranted = true
	self:MarkBrainrotUnlocked(recipientBrainrotData, brainrotId)
	table.insert(recipientBrainrotData.Inventory, self._buildInventoryItemSnapshot(recipientInstanceId, brainrotId, level))

	local reEquipInstanceId = 0
	if previousEquippedInstanceId > 0 and previousEquippedInstanceId ~= targetInstanceId then
		if self._findInventoryIndexByInstanceId(senderBrainrotData.Inventory, previousEquippedInstanceId) then
			reEquipInstanceId = previousEquippedInstanceId
		end
	end

	return true, tostring(reason or "Gift"), {
		brainrotId = brainrotId,
		brainrotName = tostring(brainrotDefinition.Name or "Brainrot"),
		level = level,
		senderInstanceId = targetInstanceId,
		recipientInstanceId = recipientInstanceId,
		reEquipInstanceId = reEquipInstanceId,
	}
end

function BrainrotInventoryService:ConsumeBrainrotInstanceFromDataContainers(brainrotData, placedBrainrots, productionState, instanceId, reason)
	if not brainrotData or not placedBrainrots or not productionState then
		return false, "PlayerDataNotReady", nil
	end

	local targetInstanceId = math.max(0, math.floor(tonumber(instanceId) or 0))
	if targetInstanceId <= 0 then
		return false, "InvalidInstanceId", nil
	end

	for positionKey, placedData in pairs(placedBrainrots) do
		if math.max(0, math.floor(tonumber(placedData and placedData.InstanceId) or 0)) == targetInstanceId then
			local brainrotId = math.max(0, math.floor(tonumber(placedData and placedData.BrainrotId) or 0))
			local brainrotDefinition = self._brainrotById[brainrotId]
			local level = self._normalizeBrainrotLevel(placedData and placedData.Level)

			placedBrainrots[positionKey] = nil
			local productionSlot = self._getOrCreateProductionSlot(productionState, positionKey)
			self._resetProductionSlotValues(productionSlot)

			return true, tostring(reason or "Consumed"), {
				source = "Placed",
				positionKey = positionKey,
				instanceId = targetInstanceId,
				brainrotId = brainrotId,
				brainrotName = brainrotDefinition and tostring(brainrotDefinition.Name or "Brainrot") or "Brainrot",
				level = level,
			}
		end
	end

	local inventoryIndex = self._findInventoryIndexByInstanceId(brainrotData.Inventory, targetInstanceId)
	if not inventoryIndex then
		return false, "BrainrotNotFound", nil
	end

	local inventoryItem = brainrotData.Inventory[inventoryIndex]
	local brainrotId = math.max(0, math.floor(tonumber(inventoryItem and inventoryItem.BrainrotId) or 0))
	local brainrotDefinition = self._brainrotById[brainrotId]
	local level = self._normalizeBrainrotLevel(inventoryItem and inventoryItem.Level)
	local previousEquippedInstanceId = math.max(0, math.floor(tonumber(brainrotData.EquippedInstanceId) or 0))

	table.remove(brainrotData.Inventory, inventoryIndex)
	if previousEquippedInstanceId == targetInstanceId then
		brainrotData.EquippedInstanceId = 0
	end

	return true, tostring(reason or "Consumed"), {
		source = previousEquippedInstanceId == targetInstanceId and "Equipped" or "Inventory",
		instanceId = targetInstanceId,
		brainrotId = brainrotId,
		brainrotName = brainrotDefinition and tostring(brainrotDefinition.Name or "Brainrot") or "Brainrot",
		level = level,
	}
end

return BrainrotInventoryService
