--[[
Script: BrainrotPlacementService
Type: ModuleScript
Studio path: ServerScriptService/Services/BrainrotPlacementService
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
	error("[BrainrotPlacementService] Missing shared module ModuleLoader")
end

local ModuleLoader = require(moduleLoaderScript)
local BrainrotConfig = ModuleLoader.requireSharedModule("BrainrotPlacementService", "BrainrotConfig")

local BrainrotPlacementService = {}
BrainrotPlacementService.__index = BrainrotPlacementService

local function ensureTable(parentTable, key)
	if type(parentTable) ~= "table" then
		return nil
	end

	if type(parentTable[key]) ~= "table" then
		parentTable[key] = {}
	end

	return parentTable[key]
end

function BrainrotPlacementService.new(config)
	local self = setmetatable({}, BrainrotPlacementService)
	config = type(config) == "table" and config or {}
	self._brainrotById = type(config.brainrotById) == "table" and config.brainrotById or BrainrotConfig.ById
	self._normalizeBrainrotLevel = type(config.normalizeBrainrotLevel) == "function" and config.normalizeBrainrotLevel or function(level)
		return math.max(1, math.floor(tonumber(level) or 1))
	end
	self._roundEconomicValue = type(config.roundEconomicValue) == "function" and config.roundEconomicValue or function(value)
		local numericValue = tonumber(value) or 0
		return math.floor(numericValue * 10000 + 0.5) / 10000
	end
	self._getProductionSpeed = type(config.getProductionSpeed) == "function" and config.getProductionSpeed or function(_brainrotDefinition, _level)
		return 0
	end
	self._getUpgradeCost = type(config.getUpgradeCost) == "function" and config.getUpgradeCost or function(_brainrotDefinition, _level)
		return 0
	end
	self._buildInventoryItemSnapshot = type(config.buildInventoryItemSnapshot) == "function" and config.buildInventoryItemSnapshot or function(instanceId, brainrotId, level)
		return {
			InstanceId = math.max(0, math.floor(tonumber(instanceId) or 0)),
			BrainrotId = math.max(0, math.floor(tonumber(brainrotId) or 0)),
			Level = self._normalizeBrainrotLevel(level),
		}
	end
	self._getPlacedAt = type(config.getPlacedAt) == "function" and config.getPlacedAt or function()
		return os.time()
	end
	return self
end

function BrainrotPlacementService:GetOrCreateProductionSlot(productionState, positionKey)
	local slot = ensureTable(productionState, positionKey)
	if type(slot) ~= "table" then
		return nil
	end

	slot.CurrentGold = self._roundEconomicValue(slot.CurrentGold)
	slot.OfflineGold = self._roundEconomicValue(slot.OfflineGold)
	slot.FriendBonusRemainder = self._roundEconomicValue(slot.FriendBonusRemainder)

	if slot.FriendBonusRemainder > 0 then
		slot.CurrentGold = self._roundEconomicValue(slot.CurrentGold + slot.FriendBonusRemainder)
		slot.FriendBonusRemainder = 0
	end

	return slot
end

function BrainrotPlacementService:ResetProductionSlotValues(slot)
	if type(slot) ~= "table" then
		return
	end

	slot.CurrentGold = 0
	slot.OfflineGold = 0
	slot.FriendBonusRemainder = 0
end

function BrainrotPlacementService:ComputePlacedBaseProductionSpeed(placedBrainrots)
	local baseSpeed = 0
	if type(placedBrainrots) ~= "table" then
		return 0
	end

	for _, placedData in pairs(placedBrainrots) do
		local brainrotId = tonumber(placedData.BrainrotId)
		local brainrotDefinition = brainrotId and self._brainrotById[brainrotId] or nil
		if brainrotDefinition then
			baseSpeed += self._getProductionSpeed(brainrotDefinition, placedData.Level)
		end
	end

	return self._roundEconomicValue(baseSpeed)
end

function BrainrotPlacementService:_accumulateProductionState(placedBrainrots, productionState, productionScale, goldFieldName)
	local changedPositions = {}
	if type(placedBrainrots) ~= "table" or type(productionState) ~= "table" then
		return changedPositions
	end

	local normalizedScale = tonumber(productionScale) or 0
	if normalizedScale <= 0 then
		return changedPositions
	end

	for positionKey, placedData in pairs(placedBrainrots) do
		local brainrotId = tonumber(placedData.BrainrotId)
		local brainrotDefinition = brainrotId and self._brainrotById[brainrotId] or nil
		if brainrotDefinition then
			local coinPerSecond = self._getProductionSpeed(brainrotDefinition, placedData.Level)
			if coinPerSecond > 0 then
				local slot = self:GetOrCreateProductionSlot(productionState, positionKey)
				if type(slot) == "table" then
					local currentValue = tonumber(slot[goldFieldName]) or 0
					local producedExact = coinPerSecond * normalizedScale
					slot[goldFieldName] = self._roundEconomicValue(currentValue + producedExact)
					changedPositions[positionKey] = true
				end
			end
		end
	end

	return changedPositions
end

function BrainrotPlacementService:TickProductionState(placedBrainrots, productionState, bonusMultiplier)
	return self:_accumulateProductionState(placedBrainrots, productionState, bonusMultiplier, "CurrentGold")
end

function BrainrotPlacementService:ApplyOfflineProductionState(placedBrainrots, productionState, productionScale)
	return self:_accumulateProductionState(placedBrainrots, productionState, productionScale, "OfflineGold")
end

function BrainrotPlacementService:PickupPlacedBrainrotData(brainrotData, placedBrainrots, productionState, positionKey)
	if type(brainrotData) ~= "table" or type(brainrotData.Inventory) ~= "table" then
		return false, "PlayerDataNotReady", nil
	end
	if type(placedBrainrots) ~= "table" or type(productionState) ~= "table" then
		return false, "PlayerDataNotReady", nil
	end

	local placedData = placedBrainrots[positionKey]
	if type(placedData) ~= "table" then
		return false, "NoBrainrot", nil
	end

	local inventoryItem = self._buildInventoryItemSnapshot(placedData.InstanceId, placedData.BrainrotId, placedData.Level)
	if inventoryItem.InstanceId <= 0 or inventoryItem.BrainrotId <= 0 then
		return false, "InvalidPlacedBrainrot", nil
	end

	placedBrainrots[positionKey] = nil
	table.insert(brainrotData.Inventory, inventoryItem)
	brainrotData.EquippedInstanceId = 0

	local slot = self:GetOrCreateProductionSlot(productionState, positionKey)
	self:ResetProductionSlotValues(slot)

	return true, "Success", {
		positionKey = positionKey,
		placedData = placedData,
		inventoryItem = inventoryItem,
		productionSlot = slot,
	}
end

function BrainrotPlacementService:ClearPlacedPositionState(placedBrainrots, productionState, positionKey)
	if type(placedBrainrots) ~= "table" or type(productionState) ~= "table" then
		return false
	end

	placedBrainrots[positionKey] = nil
	local slot = self:GetOrCreateProductionSlot(productionState, positionKey)
	self:ResetProductionSlotValues(slot)
	return true
end

function BrainrotPlacementService:PlaceInventoryItemAtPosition(brainrotData, placedBrainrots, productionState, inventoryIndex, positionKey, placedAt)
	if type(brainrotData) ~= "table" or type(brainrotData.Inventory) ~= "table" then
		return false, "PlayerDataNotReady", nil
	end
	if type(placedBrainrots) ~= "table" or type(productionState) ~= "table" then
		return false, "PlayerDataNotReady", nil
	end

	local normalizedInventoryIndex = math.floor(tonumber(inventoryIndex) or 0)
	local inventoryItem = brainrotData.Inventory[normalizedInventoryIndex]
	if type(inventoryItem) ~= "table" then
		return false, "InventoryItemNotFound", nil
	end

	local instanceId = math.max(0, math.floor(tonumber(inventoryItem.InstanceId) or 0))
	local brainrotId = math.max(0, math.floor(tonumber(inventoryItem.BrainrotId) or 0))
	if instanceId <= 0 or brainrotId <= 0 then
		return false, "InvalidInventoryItem", nil
	end

	table.remove(brainrotData.Inventory, normalizedInventoryIndex)
	brainrotData.EquippedInstanceId = 0

	local normalizedPlacedAt = math.max(0, math.floor(tonumber(placedAt) or self._getPlacedAt()))
	local placedData = {
		InstanceId = instanceId,
		BrainrotId = brainrotId,
		Level = self._normalizeBrainrotLevel(inventoryItem.Level),
		PlacedAt = normalizedPlacedAt,
	}

	placedBrainrots[positionKey] = placedData

	local slot = self:GetOrCreateProductionSlot(productionState, positionKey)
	self:ResetProductionSlotValues(slot)

	return true, "Success", {
		positionKey = positionKey,
		placedData = placedData,
		inventoryItem = self._buildInventoryItemSnapshot(instanceId, brainrotId, placedData.Level),
		productionSlot = slot,
	}
end

function BrainrotPlacementService:SwapPlacedWithInventoryItem(brainrotData, placedBrainrots, productionState, inventoryIndex, positionKey, placedAt)
	if type(brainrotData) ~= "table" or type(brainrotData.Inventory) ~= "table" then
		return false, "PlayerDataNotReady", nil
	end
	if type(placedBrainrots) ~= "table" or type(productionState) ~= "table" then
		return false, "PlayerDataNotReady", nil
	end

	local currentPlacedData = placedBrainrots[positionKey]
	if type(currentPlacedData) ~= "table" then
		return false, "NoBrainrot", nil
	end

	local normalizedInventoryIndex = math.floor(tonumber(inventoryIndex) or 0)
	local inventoryItem = brainrotData.Inventory[normalizedInventoryIndex]
	if type(inventoryItem) ~= "table" then
		return false, "InventoryItemNotFound", nil
	end

	local instanceId = math.max(0, math.floor(tonumber(inventoryItem.InstanceId) or 0))
	local brainrotId = math.max(0, math.floor(tonumber(inventoryItem.BrainrotId) or 0))
	if instanceId <= 0 or brainrotId <= 0 then
		return false, "InvalidInventoryItem", nil
	end

	local pickupInventoryItem = self._buildInventoryItemSnapshot(currentPlacedData.InstanceId, currentPlacedData.BrainrotId, currentPlacedData.Level)
	if pickupInventoryItem.InstanceId <= 0 or pickupInventoryItem.BrainrotId <= 0 then
		return false, "InvalidPlacedBrainrot", nil
	end

	table.remove(brainrotData.Inventory, normalizedInventoryIndex)
	table.insert(brainrotData.Inventory, pickupInventoryItem)
	brainrotData.EquippedInstanceId = 0

	local normalizedPlacedAt = math.max(0, math.floor(tonumber(placedAt) or self._getPlacedAt()))
	local placedData = {
		InstanceId = instanceId,
		BrainrotId = brainrotId,
		Level = self._normalizeBrainrotLevel(inventoryItem.Level),
		PlacedAt = normalizedPlacedAt,
	}

	placedBrainrots[positionKey] = placedData

	local slot = self:GetOrCreateProductionSlot(productionState, positionKey)
	self:ResetProductionSlotValues(slot)

	return true, "Success", {
		positionKey = positionKey,
		placedData = placedData,
		previousPlacedData = currentPlacedData,
		pickupInventoryItem = pickupInventoryItem,
		inventoryItem = self._buildInventoryItemSnapshot(instanceId, brainrotId, placedData.Level),
		productionSlot = slot,
	}
end

function BrainrotPlacementService:ClaimPositionGoldState(placedBrainrots, productionState, positionKey)
	if type(placedBrainrots) ~= "table" or type(productionState) ~= "table" then
		return false, "PlayerDataNotReady", nil
	end

	if not placedBrainrots[positionKey] then
		return false, "NoBrainrot", nil
	end

	local slot = self:GetOrCreateProductionSlot(productionState, positionKey)
	if type(slot) ~= "table" then
		return false, "ProductionSlotUnavailable", nil
	end

	local currentGold = tonumber(slot.CurrentGold) or 0
	local offlineGold = tonumber(slot.OfflineGold) or 0
	local claimAmount = self._roundEconomicValue(currentGold + offlineGold)
	if claimAmount <= 0 then
		return false, "NoGold", nil
	end

	slot.CurrentGold = 0
	slot.OfflineGold = 0

	return true, "Success", {
		positionKey = positionKey,
		slot = slot,
		currentGold = currentGold,
		offlineGold = offlineGold,
		claimAmount = claimAmount,
	}
end

function BrainrotPlacementService:RollbackPositionGoldClaim(claimResult)
	if type(claimResult) ~= "table" then
		return
	end

	local slot = claimResult.slot
	if type(slot) ~= "table" then
		return
	end

	slot.CurrentGold = self._roundEconomicValue(claimResult.currentGold)
	slot.OfflineGold = self._roundEconomicValue(claimResult.offlineGold)
end

function BrainrotPlacementService:ClaimAllOfflineGoldState(productionState)
	if type(productionState) ~= "table" then
		return false, "PlayerDataNotReady", nil
	end

	local previousOfflineGoldBySlot = {}
	local totalOfflineGold = 0
	for _, slot in pairs(productionState) do
		if type(slot) == "table" then
			local slotOfflineGold = math.max(0, tonumber(slot.OfflineGold) or 0)
			if slotOfflineGold > 0 then
				previousOfflineGoldBySlot[slot] = slotOfflineGold
				totalOfflineGold = self._roundEconomicValue(totalOfflineGold + slotOfflineGold)
				slot.OfflineGold = 0
			end
		end
	end

	if totalOfflineGold <= 0 then
		return false, "NoOfflineGold", nil
	end

	return true, "Success", {
		totalOfflineGold = totalOfflineGold,
		previousOfflineGoldBySlot = previousOfflineGoldBySlot,
	}
end

function BrainrotPlacementService:RollbackClaimAllOfflineGoldState(claimResult)
	if type(claimResult) ~= "table" or type(claimResult.previousOfflineGoldBySlot) ~= "table" then
		return
	end

	for slot, previousOfflineGold in pairs(claimResult.previousOfflineGoldBySlot) do
		if type(slot) == "table" then
			slot.OfflineGold = self._roundEconomicValue(previousOfflineGold)
		end
	end
end

function BrainrotPlacementService:ResetAllProductionState(placedBrainrots, productionState)
	if type(productionState) ~= "table" then
		return false
	end

	for _, slot in pairs(productionState) do
		if type(slot) == "table" then
			self:ResetProductionSlotValues(slot)
		end
	end

	if type(placedBrainrots) == "table" then
		for positionKey in pairs(placedBrainrots) do
			local slot = self:GetOrCreateProductionSlot(productionState, positionKey)
			self:ResetProductionSlotValues(slot)
		end
	end

	return true
end

function BrainrotPlacementService:GetPlacedUpgradeQuote(placedBrainrots, positionKey)
	if type(placedBrainrots) ~= "table" then
		return false, "PlayerDataNotReady", nil
	end

	local placedData = placedBrainrots[positionKey]
	if type(placedData) ~= "table" then
		return false, "NoBrainrot", nil
	end

	local brainrotId = tonumber(placedData.BrainrotId)
	local brainrotDefinition = brainrotId and self._brainrotById[brainrotId] or nil
	local currentLevel = self._normalizeBrainrotLevel(placedData.Level)
	if not brainrotDefinition then
		return false, "BrainrotNotFound", {
			positionKey = positionKey,
			placedData = placedData,
			currentLevel = currentLevel,
		}
	end

	local upgradeCost = self._roundEconomicValue(self._getUpgradeCost(brainrotDefinition, currentLevel))
	return true, "Success", {
		positionKey = positionKey,
		placedData = placedData,
		brainrotId = brainrotId,
		brainrotDefinition = brainrotDefinition,
		currentLevel = currentLevel,
		nextLevel = currentLevel + 1,
		upgradeCost = upgradeCost,
	}
end

function BrainrotPlacementService:ApplyPlacedUpgradeQuote(quote)
	if type(quote) ~= "table" or type(quote.placedData) ~= "table" then
		return false, "InvalidQuote", nil
	end

	local nextLevel = self._normalizeBrainrotLevel(quote.nextLevel or ((tonumber(quote.currentLevel) or 0) + 1))
	quote.placedData.Level = nextLevel
	quote.nextLevel = nextLevel
	return true, "Success", quote
end

return BrainrotPlacementService
