--[[
Script: BrainrotStateStore
Type: ModuleScript
Studio path: ServerScriptService/Services/BrainrotStateStore
]]

local BrainrotStateStore = {}
BrainrotStateStore.__index = BrainrotStateStore

local function ensureTable(parentTable, key)
	if type(parentTable) ~= "table" then
		return nil
	end

	if type(parentTable[key]) ~= "table" then
		parentTable[key] = {}
	end

	return parentTable[key]
end

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, nestedValue in pairs(value) do
		copy[key] = deepCopy(nestedValue)
	end

	return copy
end

local function replaceTableContents(targetTable, sourceTable)
	if type(targetTable) ~= "table" then
		return
	end

	for key in pairs(targetTable) do
		targetTable[key] = nil
	end

	if type(sourceTable) ~= "table" then
		return
	end

	for key, value in pairs(sourceTable) do
		targetTable[key] = deepCopy(value)
	end
end

function BrainrotStateStore.new(config)
	local self = setmetatable({}, BrainrotStateStore)
	config = type(config) == "table" and config or {}
	self._playerDataService = config.playerDataService
	self._normalizeBrainrotLevel = type(config.normalizeBrainrotLevel) == "function" and config.normalizeBrainrotLevel or function(level)
		return math.max(1, math.floor(tonumber(level) or 1))
	end
	self._normalizeCarryUpgradeLevel = type(config.normalizeCarryUpgradeLevel) == "function" and config.normalizeCarryUpgradeLevel or function(level)
		return math.max(0, math.floor(tonumber(level) or 0))
	end
	self._hydrateUnlockedBrainrotMap = type(config.hydrateUnlockedBrainrotMap) == "function" and config.hydrateUnlockedBrainrotMap or nil
	return self
end

function BrainrotStateStore:GetOrCreateDataContainersFromPlayerData(playerData)
	if type(playerData) ~= "table" then
		return nil, nil, nil, nil
	end

	local homeState = ensureTable(playerData, "HomeState")
	local placedBrainrots = ensureTable(homeState, "PlacedBrainrots")
	local productionState = ensureTable(homeState, "ProductionState")

	local brainrotData = ensureTable(playerData, "BrainrotData")
	if type(brainrotData.Inventory) ~= "table" then
		brainrotData.Inventory = {}
	end
	if type(brainrotData.NextInstanceId) ~= "number" then
		brainrotData.NextInstanceId = 1
	end
	if type(brainrotData.EquippedInstanceId) ~= "number" then
		brainrotData.EquippedInstanceId = 0
	end
	if type(brainrotData.StarterGranted) ~= "boolean" then
		brainrotData.StarterGranted = false
	end
	if type(brainrotData.UnlockedBrainrotIds) ~= "table" then
		brainrotData.UnlockedBrainrotIds = {}
	end
	if type(brainrotData.PendingStealPurchase) ~= "table" then
		brainrotData.PendingStealPurchase = {}
	end
	if type(brainrotData.ProcessedStealPurchaseIds) ~= "table" then
		brainrotData.ProcessedStealPurchaseIds = {}
	end
	if type(brainrotData.CarryUpgradeLevel) ~= "number" then
		brainrotData.CarryUpgradeLevel = 0
	end
	if type(brainrotData.ProcessedCarryPurchaseIds) ~= "table" then
		brainrotData.ProcessedCarryPurchaseIds = {}
	end

	local maxInstanceId = 0
	for index = #brainrotData.Inventory, 1, -1 do
		local inventoryItem = brainrotData.Inventory[index]
		if type(inventoryItem) ~= "table" then
			table.remove(brainrotData.Inventory, index)
		else
			inventoryItem.InstanceId = math.max(0, math.floor(tonumber(inventoryItem.InstanceId) or 0))
			inventoryItem.BrainrotId = math.max(0, math.floor(tonumber(inventoryItem.BrainrotId) or 0))
			inventoryItem.Level = self._normalizeBrainrotLevel(inventoryItem.Level)

			if inventoryItem.InstanceId <= 0 or inventoryItem.BrainrotId <= 0 then
				table.remove(brainrotData.Inventory, index)
			else
				maxInstanceId = math.max(maxInstanceId, inventoryItem.InstanceId)
			end
		end
	end

	for positionKey, placedData in pairs(placedBrainrots) do
		if type(placedData) ~= "table" then
			placedBrainrots[positionKey] = nil
		else
			placedData.InstanceId = math.max(0, math.floor(tonumber(placedData.InstanceId) or 0))
			placedData.BrainrotId = math.max(0, math.floor(tonumber(placedData.BrainrotId) or 0))
			placedData.Level = self._normalizeBrainrotLevel(placedData.Level)
			placedData.PlacedAt = math.max(0, math.floor(tonumber(placedData.PlacedAt) or 0))

			if placedData.InstanceId <= 0 or placedData.BrainrotId <= 0 then
				placedBrainrots[positionKey] = nil
			else
				maxInstanceId = math.max(maxInstanceId, placedData.InstanceId)
			end
		end
	end

	brainrotData.NextInstanceId = math.max(math.floor(tonumber(brainrotData.NextInstanceId) or 1), maxInstanceId + 1, 1)
	brainrotData.EquippedInstanceId = math.max(0, math.floor(tonumber(brainrotData.EquippedInstanceId) or 0))
	brainrotData.CarryUpgradeLevel = self._normalizeCarryUpgradeLevel(brainrotData.CarryUpgradeLevel)
	if type(brainrotData.ProcessedCarryPurchaseIds) ~= "table" then
		brainrotData.ProcessedCarryPurchaseIds = {}
	end
	if self._hydrateUnlockedBrainrotMap then
		self._hydrateUnlockedBrainrotMap(brainrotData)
	end

	return playerData, brainrotData, placedBrainrots, productionState
end

function BrainrotStateStore:GetOrCreateDataContainers(player)
	local playerData = self._playerDataService and self._playerDataService:GetPlayerData(player) or nil
	return self:GetOrCreateDataContainersFromPlayerData(playerData)
end

function BrainrotStateStore:GetOrCreateProcessedStealPurchaseIds(brainrotData)
	if type(brainrotData) ~= "table" then
		return nil
	end

	if type(brainrotData.ProcessedStealPurchaseIds) ~= "table" then
		brainrotData.ProcessedStealPurchaseIds = {}
	end

	return brainrotData.ProcessedStealPurchaseIds
end

function BrainrotStateStore:GetOrCreateProcessedCarryPurchaseIds(brainrotData)
	if type(brainrotData) ~= "table" then
		return nil
	end

	if type(brainrotData.ProcessedCarryPurchaseIds) ~= "table" then
		brainrotData.ProcessedCarryPurchaseIds = {}
	end

	return brainrotData.ProcessedCarryPurchaseIds
end

function BrainrotStateStore:Snapshot(brainrotData, placedBrainrots, productionState)
	return {
		BrainrotData = deepCopy(brainrotData),
		PlacedBrainrots = deepCopy(placedBrainrots),
		ProductionState = deepCopy(productionState),
	}
end

function BrainrotStateStore:Restore(brainrotData, placedBrainrots, productionState, snapshot)
	if type(snapshot) ~= "table" then
		return
	end

	replaceTableContents(brainrotData, snapshot.BrainrotData)
	replaceTableContents(placedBrainrots, snapshot.PlacedBrainrots)
	replaceTableContents(productionState, snapshot.ProductionState)
end

return BrainrotStateStore
