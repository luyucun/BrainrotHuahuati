--[[
脚本名字: BrainrotService
脚本文件: BrainrotService.lua
脚本类型: ModuleScript
Studio放置路径: ServerScriptService/Services/BrainrotService
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local Workspace = game:GetService("Workspace")

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

local sharedModuleLoader = nil
local function requireSharedModule(moduleName)
	if moduleName ~= "ModuleLoader" and not sharedModuleLoader then
		local moduleLoaderScript = resolveSharedModuleScript("ModuleLoader")
		if moduleLoaderScript then
			sharedModuleLoader = require(moduleLoaderScript)
		end
	end

	if sharedModuleLoader and moduleName ~= "ModuleLoader" then
		return sharedModuleLoader.requireSharedModule("BrainrotService", moduleName)
	end

	local moduleScript = resolveSharedModuleScript(moduleName)
	if moduleScript then
		return require(moduleScript)
	end

	error(string.format(
		"[BrainrotService] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
		moduleName
		))
end

local GameConfig = requireSharedModule("GameConfig")
local BrainrotConfig = requireSharedModule("BrainrotConfig")
local BrainrotDisplayConfig = requireSharedModule("BrainrotDisplayConfig")
local FormatUtil = requireSharedModule("FormatUtil")
local CarryConfig = requireSharedModule("CarryConfig")
local RemoteNames = requireSharedModule("RemoteNames")
local BrainrotInventoryService = require(script.Parent:WaitForChild("BrainrotInventoryService"))
local BrainrotPlacementService = require(script.Parent:WaitForChild("BrainrotPlacementService"))
local BrainrotStateStore = require(script.Parent:WaitForChild("BrainrotStateStore"))

local BrainrotService = {}
BrainrotService._playerDataService = nil
BrainrotService._homeService = nil
BrainrotService._currencyService = nil
BrainrotService._friendBonusService = nil
BrainrotService._gmCommandService = nil
BrainrotService._specialEventService = nil
BrainrotService._inventoryService = nil
BrainrotService._placementService = nil
BrainrotService._stateStore = nil
BrainrotService._remoteEventService = nil
BrainrotService._brainrotStateSyncEvent = nil
BrainrotService._requestBrainrotStateSyncEvent = nil
BrainrotService._requestBrainrotUpgradeEvent = nil
BrainrotService._brainrotUpgradeFeedbackEvent = nil
BrainrotService._requestBrainrotSellEvent = nil
BrainrotService._brainrotSellFeedbackEvent = nil
BrainrotService._requestStudioBrainrotGrantEvent = nil
BrainrotService._studioBrainrotGrantFeedbackEvent = nil
BrainrotService._claimCashFeedbackEvent = nil
BrainrotService._promptBrainrotStealPurchaseEvent = nil
BrainrotService._requestBrainrotStealPurchaseClosedEvent = nil
BrainrotService._brainrotStealFeedbackEvent = nil
BrainrotService._requestCarryUpgradeEvent = nil
BrainrotService._carryUpgradeFeedbackEvent = nil
BrainrotService._bossStateSyncEvent = nil
BrainrotService._requestDropCarriedWorldBrainrotEvent = nil
BrainrotService._bossWarningEvent = nil
BrainrotService._bossKnockbackEvent = nil
BrainrotService._stealTipEvent = nil
BrainrotService._brainrotClaimTipEvent = nil
BrainrotService._previousMarketplaceProcessReceiptHandler = nil
BrainrotService._processReceiptDispatcher = nil
BrainrotService._promptConnectionsByUserId = {}
BrainrotService._placedPromptStateByUserId = {}
BrainrotService._placedStealPromptStateByUserId = {}
BrainrotService._toolConnectionsByUserId = {}
BrainrotService._toolRefreshConnectionsByUserId = {}
BrainrotService._toolRefreshBurstSerialByUserId = {}
BrainrotService._claimConnectionsByUserId = {}
BrainrotService._claimTouchDebounceByUserId = {}
BrainrotService._upgradeRequestClockByUserId = {}
BrainrotService._sellRequestClockByUserId = {}
BrainrotService._carryUpgradeRequestClockByUserId = {}
BrainrotService._claimEffectByUserId = {}
BrainrotService._claimBounceStateByUserId = {}
BrainrotService._platformsByUserId = {}
BrainrotService._claimsByUserId = {}
BrainrotService._brandsByUserId = {}
BrainrotService._runtimePlacedByUserId = {}
BrainrotService._runtimeIdleTracksByUserId = {}
BrainrotService._pendingStealPurchaseByBuyerUserId = {}
BrainrotService._brainrotStealProductIds = {}
BrainrotService._productionThread = nil
BrainrotService._worldSpawnThread = nil
BrainrotService._bossThread = nil
BrainrotService._worldSpawnEntriesById = {}
BrainrotService._worldSpawnGroupEntriesByGroupId = {}
BrainrotService._worldSpawnGroupConfigById = {}
BrainrotService._worldSpawnBossRuntimeByGroupId = {}
BrainrotService._worldSpawnNextEntryId = 0
BrainrotService._carriedWorldBrainrotByUserId = {}
BrainrotService._carriedWorldBrainrotRuntimeByUserId = {}
BrainrotService._worldSpawnIdleTracksByEntryId = {}
BrainrotService._worldSpawnRng = Random.new()
BrainrotService._missingDisplayPathWarned = {}
BrainrotService._didWarnMissingBaseInfoTemplate = false
BrainrotService._didWarnMissingInfoAttachmentByModelPath = {}
BrainrotService._didWarnMissingClaimEffectTemplate = false
BrainrotService._didWarnMissingWorldSpawnLand = false
BrainrotService._didWarnMissingWorldSpawnPartByName = {}
BrainrotService._didWarnMissingWorldSpawnPoolByGroupId = {}
BrainrotService._didWarnMissingBossModelByGroupId = {}
BrainrotService._didWarnMissingSpecialEventMutationRarityByName = {}

local function findOrCreateFolder(parent, folderName)
	local folder = parent:FindFirstChild(folderName)
	if folder and folder:IsA("Folder") then
		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = folderName
	folder.Parent = parent
	return folder
end

function BrainrotService:_requirePlacementService()
	local placementService = self._placementService
	if not placementService then
		error("[BrainrotService] BrainrotPlacementService has not been initialized")
	end

	return placementService
end

function BrainrotService:_requireInventoryService()
	local inventoryService = self._inventoryService
	if not inventoryService then
		error("[BrainrotService] BrainrotInventoryService has not been initialized")
	end

	return inventoryService
end

function BrainrotService:_requireStateStore()
	local stateStore = self._stateStore
	if not stateStore then
		error("[BrainrotService] BrainrotStateStore has not been initialized")
	end

	return stateStore
end

local function findOrCreateRemoteEvent(parent, eventName)
	local remoteEvent = parent:FindFirstChild(eventName)
	if remoteEvent and remoteEvent:IsA("RemoteEvent") then
		return remoteEvent
	end

	remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = eventName
	remoteEvent.Parent = parent
	return remoteEvent
end

function BrainrotService:_resolveRemoteEvent(eventKey, eventFolderName, remoteName)
	local remoteEvent = self._remoteEventService and self._remoteEventService:GetEvent(eventKey) or nil
	if remoteEvent and remoteEvent:IsA("RemoteEvent") then
		return remoteEvent
	end

	local normalizedName = tostring(remoteName or "")
	if normalizedName == "" then
		return nil
	end

	local eventsRoot = findOrCreateFolder(ReplicatedStorage, RemoteNames.RootFolder)
	local eventFolder = findOrCreateFolder(eventsRoot, eventFolderName)
	remoteEvent = findOrCreateRemoteEvent(eventFolder, normalizedName)

	local remoteEventService = self._remoteEventService
	if remoteEventService and type(remoteEventService._events) == "table" then
		remoteEventService._events[eventKey] = remoteEvent
	end

	return remoteEvent
end

function BrainrotService:_resolveSystemEvent(eventKey)
	return self:_resolveRemoteEvent(eventKey, RemoteNames.SystemEventsFolder, RemoteNames.System[eventKey])
end

function BrainrotService:_resolveBrainrotEvent(eventKey)
	return self:_resolveRemoteEvent(eventKey, RemoteNames.BrainrotEventsFolder, RemoteNames.Brainrot[eventKey])
end
local HOME_EXPANSION_ORIGINAL_TRANSPARENCY_ATTRIBUTE = "HomeExpansionOriginalTransparency"
local HOME_EXPANSION_ORIGINAL_CAN_QUERY_ATTRIBUTE = "HomeExpansionOriginalCanQuery"
local BRAINROT_BRAND_ORIGINAL_TRANSPARENCY_ATTRIBUTE = "BrainrotBrandOriginalTransparency"
local BRAINROT_BRAND_ORIGINAL_CAN_QUERY_ATTRIBUTE = "BrainrotBrandOriginalCanQuery"
local BRAINROT_PLATFORM_PROMPT_ATTRIBUTE = "BrainrotPlatformPrompt"
local BRAINROT_PLATFORM_HOME_ID_ATTRIBUTE = "BrainrotPlatformHomeId"
local BRAINROT_PLATFORM_OWNER_USER_ID_ATTRIBUTE = "BrainrotPlatformOwnerUserId"
local BRAINROT_PLATFORM_POSITION_KEY_ATTRIBUTE = "BrainrotPlatformPositionKey"
local BRAINROT_PLATFORM_SERVER_ENABLED_ATTRIBUTE = "BrainrotPlatformServerEnabled"
local BRAINROT_PLACED_PICKUP_PROMPT_ATTRIBUTE = "BrainrotPlacedPickupPrompt"
local BRAINROT_PLACED_PICKUP_OWNER_USER_ID_ATTRIBUTE = "BrainrotPlacedPickupOwnerUserId"
local BRAINROT_PLACED_PICKUP_SERVER_ENABLED_ATTRIBUTE = "BrainrotPlacedPickupServerEnabled"
local BRAINROT_STEAL_PROMPT_ATTRIBUTE = "BrainrotStealPrompt"
local BRAINROT_STEAL_OWNER_USER_ID_ATTRIBUTE = "BrainrotStealOwnerUserId"
local BRAINROT_STEAL_SERVER_ENABLED_ATTRIBUTE = "BrainrotStealServerEnabled"
local BRAINROT_STEAL_INSTANCE_ID_ATTRIBUTE = "BrainrotStealInstanceId"
local WORLD_SPAWN_EXPIRE_AT_ATTRIBUTE = "BrainrotWorldSpawnExpireAt"
local BOSS_HOME_UNLOCK_AT_ATTRIBUTE = "BossHomeUnlockAt"
local BOSS_RUNTIME_ATTRIBUTE = "BrainrotBossRuntime"
local BOSS_GROUP_ID_ATTRIBUTE = "BrainrotBossGroupId"
local BOSS_TARGET_POSITION_ATTRIBUTE = "BrainrotBossTargetPosition"
local BOSS_TARGET_LOOK_VECTOR_ATTRIBUTE = "BrainrotBossTargetLookVector"
local BOSS_STATE_ATTRIBUTE = "BrainrotBossState"
local BOSS_MOVE_SPEED_ATTRIBUTE = "BrainrotBossMoveSpeed"
local BOSS_SERVER_UPDATED_AT_ATTRIBUTE = "BrainrotBossServerUpdatedAt"

local function ensureTable(parentTable, key)
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

local function normalizeTimestamp(value)
	return math.max(0, math.floor(tonumber(value) or 0))
end

local function getPlayerMetaSessionTimestamps(playerData)
	local meta = type(playerData) == "table" and type(playerData.Meta) == "table" and playerData.Meta or nil
	return normalizeTimestamp(meta and meta.LastLoginAt), normalizeTimestamp(meta and meta.LastLogoutAt)
end

local function parseModelPath(modelPath)
	if type(modelPath) ~= "string" then
		return nil, nil
	end

	return string.match(modelPath, "^([^/]+)/(.+)$")
end

local function getFirstBasePart(instance)
	if not instance then
		return nil
	end

	if instance:IsA("BasePart") then
		return instance
	end

	return instance:FindFirstChildWhichIsA("BasePart", true)
end

local function getPreferredModelBasePart(model)
	if not model or not model:IsA("Model") then
		return nil
	end

	local primaryPart = model.PrimaryPart
	if primaryPart and primaryPart:IsA("BasePart") then
		return primaryPart
	end

	local humanoidRootPart = model:FindFirstChild("HumanoidRootPart", true)
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	local rootPart = model:FindFirstChild("RootPart", true)
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	local handle = model:FindFirstChild("Handle", true)
	if handle and handle:IsA("BasePart") then
		return handle
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function getTemplateToolHandlePart(toolTemplate)
	if not toolTemplate or not toolTemplate:IsA("Tool") then
		return nil
	end

	local directHandle = toolTemplate:FindFirstChild("Handle")
	if directHandle and directHandle:IsA("BasePart") then
		return directHandle
	end

	local nestedHandle = toolTemplate:FindFirstChild("Handle", true)
	if nestedHandle and nestedHandle:IsA("BasePart") then
		return nestedHandle
	end

	return toolTemplate:FindFirstChildWhichIsA("BasePart", true)
end

local function getModelPivotCFrame(model)
	if not model or not model:IsA("Model") then
		return nil, nil
	end

	local primaryPart = getPreferredModelBasePart(model)
	if not primaryPart then
		return nil, nil
	end

	model.PrimaryPart = primaryPart
	return model:GetPivot(), primaryPart
end

local function getInstancePivotCFrame(instance)
	if not instance then
		return nil, nil
	end

	if instance:IsA("Model") then
		return getModelPivotCFrame(instance)
	end

	if instance:IsA("BasePart") then
		return instance.CFrame, instance
	end

	return nil, nil
end

local function setInstancePivotCFrame(instance, targetCFrame)
	if not instance or not targetCFrame then
		return
	end

	if instance:IsA("Model") then
		instance:PivotTo(targetCFrame)
		return
	end

	if instance:IsA("BasePart") then
		instance.CFrame = targetCFrame
	end
end

local function setCFramePosition(sourceCFrame, targetPosition)
	if not sourceCFrame or not targetPosition then
		return nil
	end

	return CFrame.new(targetPosition) * (sourceCFrame - sourceCFrame.Position)
end

local function getInstanceBoundingBox(instance)
	if not instance then
		return nil, nil
	end

	if instance:IsA("Model") then
		return instance:GetBoundingBox()
	end

	if instance:IsA("BasePart") then
		return instance.CFrame, instance.Size
	end

	return nil, nil
end

local function snapInstanceBottomToY(instance, targetY)
	if not instance or type(targetY) ~= "number" then
		return false
	end

	local currentPivotCFrame = select(1, getInstancePivotCFrame(instance))
	local boundingBoxCFrame, boundingBoxSize = getInstanceBoundingBox(instance)
	if not (currentPivotCFrame and boundingBoxCFrame and boundingBoxSize) then
		return false
	end

	local currentBottomY = boundingBoxCFrame.Position.Y - (boundingBoxSize.Y * 0.5)
	local adjustedPivotCFrame = setCFramePosition(
		currentPivotCFrame,
		currentPivotCFrame.Position + Vector3.new(0, targetY - currentBottomY, 0)
	)
	if not adjustedPivotCFrame then
		return false
	end

	setInstancePivotCFrame(instance, adjustedPivotCFrame)
	return true
end

local function isValidGroundHit(result)
	local hitInstance = result and result.Instance or nil
	return hitInstance
		and hitInstance:IsA("BasePart")
		and hitInstance.CanCollide == true
end

local function resolveGroundDropPosition(worldPosition, ignoredInstances)
	if typeof(worldPosition) ~= "Vector3" then
		return nil, false
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.IgnoreWater = true
	raycastParams.FilterDescendantsInstances = {}

	if type(ignoredInstances) == "table" then
		for _, ignoredInstance in ipairs(ignoredInstances) do
			if typeof(ignoredInstance) == "Instance" then
				table.insert(raycastParams.FilterDescendantsInstances, ignoredInstance)
			end
		end
	end

	local castHeight = math.min(4096, math.max(128, math.abs(worldPosition.Y) + 256))
	local origin = Vector3.new(worldPosition.X, worldPosition.Y + castHeight, worldPosition.Z)
	local direction = Vector3.new(0, -(castHeight + 4096), 0)
	for _ = 1, 12 do
		local result = Workspace:Raycast(origin, direction, raycastParams)
		if not result then
			break
		end

		if isValidGroundHit(result) then
			return Vector3.new(worldPosition.X, result.Position.Y, worldPosition.Z), true
		end

		local hitInstance = result.Instance
		if typeof(hitInstance) ~= "Instance" then
			break
		end

		table.insert(raycastParams.FilterDescendantsInstances, hitInstance)
	end

	return worldPosition, false
end

local function getHorizontalLookVectorFromCFrame(sourceCFrame, fallbackLookVector)
	if sourceCFrame then
		local horizontalLook = Vector3.new(sourceCFrame.LookVector.X, 0, sourceCFrame.LookVector.Z)
		if horizontalLook.Magnitude > 0.0001 then
			return horizontalLook.Unit
		end

		local horizontalRight = Vector3.new(sourceCFrame.RightVector.X, 0, sourceCFrame.RightVector.Z)
		if horizontalRight.Magnitude > 0.0001 then
			return horizontalRight.Unit
		end
	end

	if fallbackLookVector then
		local fallbackHorizontal = Vector3.new(fallbackLookVector.X, 0, fallbackLookVector.Z)
		if fallbackHorizontal.Magnitude > 0.0001 then
			return fallbackHorizontal.Unit
		end
	end

	return Vector3.new(0, 0, -1)
end

local function makeYawOnlyCFrame(sourceCFrame, targetPosition, fallbackLookVector)
	if not sourceCFrame or not targetPosition then
		return nil
	end

	local horizontalLook = getHorizontalLookVectorFromCFrame(sourceCFrame, fallbackLookVector)
	return CFrame.lookAt(targetPosition, targetPosition + horizontalLook, Vector3.new(0, 1, 0))
end
local function getToolPivotCFrame(tool, preferredModelName)
	if not tool or not tool:IsA("Tool") then
		return nil, nil
	end

	local function tryGetModelPivot(modelInstance)
		if not modelInstance or not modelInstance:IsA("Model") then
			return nil, nil
		end

		return getModelPivotCFrame(modelInstance)
	end

	local directBrainrotModel = tool:FindFirstChild("BrainrotModel")
	local brainrotPivot, brainrotPivotPart = tryGetModelPivot(directBrainrotModel)
	if brainrotPivot then
		return brainrotPivot, brainrotPivotPart
	end

	local nestedBrainrotModel = tool:FindFirstChild("BrainrotModel", true)
	if nestedBrainrotModel ~= directBrainrotModel then
		local nestedBrainrotPivot, nestedBrainrotPivotPart = tryGetModelPivot(nestedBrainrotModel)
		if nestedBrainrotPivot then
			return nestedBrainrotPivot, nestedBrainrotPivotPart
		end
	end

	if type(preferredModelName) == "string" and preferredModelName ~= "" then
		local directPreferredModel = tool:FindFirstChild(preferredModelName)
		local directPivot, directPivotPart = tryGetModelPivot(directPreferredModel)
		if directPivot then
			return directPivot, directPivotPart
		end

		local nestedPreferredModel = tool:FindFirstChild(preferredModelName, true)
		local nestedPivot, nestedPivotPart = tryGetModelPivot(nestedPreferredModel)
		if nestedPivot then
			return nestedPivot, nestedPivotPart
		end
	end

	local directSameNameModel = tool:FindFirstChild(tool.Name)
	local sameNamePivot, sameNamePivotPart = tryGetModelPivot(directSameNameModel)
	if sameNamePivot then
		return sameNamePivot, sameNamePivotPart
	end

	local nestedSameNameModel = tool:FindFirstChild(tool.Name, true)
	local nestedSameNamePivot, nestedSameNamePivotPart = tryGetModelPivot(nestedSameNameModel)
	if nestedSameNamePivot then
		return nestedSameNamePivot, nestedSameNamePivotPart
	end

	local directHandle = tool:FindFirstChild("Handle")
	if directHandle and directHandle:IsA("BasePart") then
		return directHandle.CFrame, directHandle
	end

	local nestedHandle = tool:FindFirstChild("Handle", true)
	if nestedHandle and nestedHandle:IsA("BasePart") then
		return nestedHandle.CFrame, nestedHandle
	end

	local fallbackPart = tool:FindFirstChildWhichIsA("BasePart", true)
	if fallbackPart then
		return fallbackPart.CFrame, fallbackPart
	end

	return nil, nil
end

local function setToolVisualPart(part)
	if not part or not part:IsA("BasePart") then
		return
	end

	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.Massless = true
end

local function findInventoryIndexByInstanceId(inventory, instanceId)
	for index, inventoryItem in ipairs(inventory) do
		if tonumber(inventoryItem.InstanceId) == instanceId then
			return index
		end
	end

	return nil
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
local function isPlatformPart(part)
	if not part:IsA("BasePart") then
		return false
	end

	local lowerName = string.lower(part.Name)
	return lowerName == "platform" or lowerName == "platformpart" or string.find(lowerName, "platform", 1, true) ~= nil
end

local function getCharacterRootPart(character)
	if not character then
		return nil
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	local primaryPart = character.PrimaryPart
	if primaryPart and primaryPart:IsA("BasePart") then
		return primaryPart
	end

	local fallbackPart = character:FindFirstChildWhichIsA("BasePart")
	if fallbackPart and fallbackPart:IsA("BasePart") then
		return fallbackPart
	end

	return nil
end

local function isPointInsidePartBounds(part, worldPoint)
	if not (part and part:IsA("BasePart") and typeof(worldPoint) == "Vector3") then
		return false
	end

	local localPoint = part.CFrame:PointToObjectSpace(worldPoint)
	local halfSize = part.Size * 0.5
	return math.abs(localPoint.X) <= halfSize.X
		and math.abs(localPoint.Y) <= halfSize.Y
		and math.abs(localPoint.Z) <= halfSize.Z
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

local function getSharedClock()
	local ok, serverNow = pcall(function()
		return Workspace:GetServerTimeNow()
	end)
	if ok and type(serverNow) == "number" then
		return serverNow
	end

	return os.clock()
end

local function getAliveHumanoid(character)
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end

	return humanoid
end

local function resolveHorizontalDirection(fromPosition, toPosition, fallbackLookVector)
	local rawDirection = nil
	if typeof(fromPosition) == "Vector3" and typeof(toPosition) == "Vector3" then
		rawDirection = toPosition - fromPosition
	end

	if not rawDirection or rawDirection.Magnitude <= 0.001 then
		rawDirection = fallbackLookVector or Vector3.new(0, 0, -1)
	end

	local horizontal = Vector3.new(rawDirection.X, 0, rawDirection.Z)
	if horizontal.Magnitude <= 0.001 then
		local fallback = fallbackLookVector or Vector3.new(0, 0, -1)
		horizontal = Vector3.new(fallback.X, 0, fallback.Z)
	end

	if horizontal.Magnitude <= 0.001 then
		return Vector3.new(0, 0, -1)
	end

	return horizontal.Unit
end

local function isCharacterNearPart(character, part)
	if not (character and part and part.Parent and part:IsA("BasePart")) then
		return false
	end

	local rootPart = getCharacterRootPart(character)
	if not (rootPart and rootPart.Parent) then
		return false
	end

	local localPosition = part.CFrame:PointToObjectSpace(rootPart.Position)
	local size = part.Size
	local xLimit = (size.X * 0.5) + 1
	local zLimit = (size.Z * 0.5) + 1
	local yUpperLimit = (size.Y * 0.5) + 6
	local yLowerLimit = (size.Y * 0.5) + 3

	return math.abs(localPosition.X) <= xLimit
		and math.abs(localPosition.Z) <= zLimit
		and localPosition.Y <= yUpperLimit
		and localPosition.Y >= -yLowerLimit
end

local function isCharacterTouchingPart(character, part)
	if not (character and character.Parent and part and part.Parent and part:IsA("BasePart")) then
		return false
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = { character }
	overlapParams.MaxParts = 1

	local success, touchedParts = pcall(function()
		return workspace:GetPartsInPart(part, overlapParams)
	end)

	return success and type(touchedParts) == "table" and #touchedParts > 0
end

local function isCharacterOccupyingPart(character, part)
	return isCharacterTouchingPart(character, part) or isCharacterNearPart(character, part)
end

local function getBrainrotDisplayDecimals()
	return math.max(0, math.floor(tonumber((GameConfig.BRAINROT or {}).UpgradeValueDisplayDecimals) or 1))
end

local function roundBrainrotEconomicValue(value)
	local precision = math.max(0, math.floor(tonumber((GameConfig.BRAINROT or {}).UpgradeInternalPrecisionDecimals) or 4))
	return math.max(0, FormatUtil.RoundToDecimals(value, precision))
end

local function getBaseBrainrotLevel()
	return math.max(1, math.floor(tonumber((GameConfig.BRAINROT or {}).BaseLevel) or 1))
end

local function normalizeBrainrotLevel(level)
	return math.max(getBaseBrainrotLevel(), math.floor(tonumber(level) or getBaseBrainrotLevel()))
end

local function getBaseCarryCount()
	return math.max(1, math.floor(tonumber(CarryConfig.BaseCarryCount) or 1))
end

local function normalizeCarryUpgradeLevel(level)
	return math.clamp(math.max(0, math.floor(tonumber(level) or 0)), 0, math.max(0, math.floor(tonumber(CarryConfig.MaxLevel) or 0)))
end

local function formatPlacedBrainrotDisplayName(brainrotDefinition, level)
	local baseName = tostring(type(brainrotDefinition) == "table" and brainrotDefinition.Name or "Unknown")
	return string.format("%s[Lv.%d]", baseName, normalizeBrainrotLevel(level))
end

local function buildInventoryItemSnapshot(instanceId, brainrotId, level)
	return {
		InstanceId = math.max(0, math.floor(tonumber(instanceId) or 0)),
		BrainrotId = math.max(0, math.floor(tonumber(brainrotId) or 0)),
		Level = normalizeBrainrotLevel(level),
	}
end

local function getBrainrotDeveloperProductInfo(brainrotDefinition)
	local developerProduct = type(brainrotDefinition) == "table" and brainrotDefinition.DeveloperProduct or nil
	local productId = math.max(0, math.floor(tonumber(developerProduct and developerProduct.ProductId) or 0))
	if productId <= 0 then
		return nil, 0
	end

	return developerProduct, productId
end

local function getStealPendingTimeoutSeconds()
	return math.max(60, math.floor(tonumber((GameConfig.BRAINROT or {}).StealPendingTimeoutSeconds) or 900))
end

local function getStealOfflineOwnerGraceSeconds()
	return math.max(3, math.floor(tonumber((GameConfig.BRAINROT or {}).StealOfflineOwnerGraceSeconds) or 8))
end

local function buildStealRequestId(buyerUserId, ownerUserId, instanceId)
	return string.format(
		"Steal_%d_%d_%d_%d",
		math.max(0, math.floor(tonumber(buyerUserId) or 0)),
		math.max(0, math.floor(tonumber(ownerUserId) or 0)),
		math.max(0, math.floor(tonumber(instanceId) or 0)),
		math.max(0, math.floor(os.clock() * 1000))
	)
end

local function getBrainrotBaseProductionSpeed(brainrotDefinition)
	return math.max(0, tonumber(brainrotDefinition and brainrotDefinition.CoinPerSecond) or 0)
end

local function getBrainrotProductionSpeed(brainrotDefinition, level)
	local baseSpeed = getBrainrotBaseProductionSpeed(brainrotDefinition)
	local normalizedLevel = normalizeBrainrotLevel(level)
	local exponent = math.max(0, normalizedLevel - getBaseBrainrotLevel())
	local multiplier = math.max(0, tonumber((GameConfig.BRAINROT or {}).UpgradeProductionMultiplier) or 1.25)
	return roundBrainrotEconomicValue(baseSpeed * (multiplier ^ exponent))
end

local function getBrainrotUpgradeCost(brainrotDefinition, level)
	local baseSpeed = getBrainrotBaseProductionSpeed(brainrotDefinition)
	local normalizedLevel = normalizeBrainrotLevel(level)
	local exponent = math.max(0, normalizedLevel - getBaseBrainrotLevel())
	local multiplier = math.max(0, tonumber((GameConfig.BRAINROT or {}).UpgradeCostMultiplier) or 1.5)
	return roundBrainrotEconomicValue(baseSpeed * (multiplier ^ exponent))
end

local function getBrainrotSellPrice(brainrotDefinition)
	local baseSpeed = getBrainrotBaseProductionSpeed(brainrotDefinition)
	local multiplier = math.max(0, tonumber((GameConfig.BRAINROT or {}).SellPriceMultiplier) or 15)
	return roundBrainrotEconomicValue(baseSpeed * multiplier)
end

local function formatBrainrotNumber(value)
	return FormatUtil.FormatWithCommas(roundBrainrotEconomicValue(value), getBrainrotDisplayDecimals())
end

local function formatBrainrotCurrency(value)
	return "$" .. formatBrainrotNumber(value)
end

local function formatBrainrotCompactCurrency(value)
	return FormatUtil.FormatCompactCurrencyCeil(roundBrainrotEconomicValue(value))
end

local function formatBrainrotSpeed(value)
	return string.format("$%s/S", formatBrainrotNumber(value))
end

local function formatCurrentGoldText(value)
	return formatBrainrotCompactCurrency(value)
end

local function formatOfflineGoldText(value)
	return "IdleEarnings " .. formatBrainrotCompactCurrency(value)
end

local function normalizeAnimationId(animationId)
	if type(animationId) == "number" then
		animationId = tostring(math.floor(animationId))
	end

	if type(animationId) ~= "string" then
		return nil
	end

	local trimmed = string.gsub(animationId, "^%s*(.-)%s*$", "%1")
	if trimmed == "" then
		return nil
	end

	if string.match(trimmed, "^rbxassetid://") then
		return trimmed
	end

	if string.match(trimmed, "^%d+$") then
		return "rbxassetid://" .. trimmed
	end

	return nil
end

local function resolveQualityDisplayInfo(qualityId)
	local parsedId = math.floor(tonumber(qualityId) or 0)
	local displayEntry = type(BrainrotDisplayConfig.Quality) == "table" and BrainrotDisplayConfig.Quality[parsedId] or nil
	local displayName = (type(displayEntry) == "table" and tostring(displayEntry.Name or "")) or ""
	if displayName == "" then
		displayName = BrainrotConfig.QualityNames[parsedId] or "Unknown"
	end

	local gradientPathOrList = nil
	if type(displayEntry) == "table" then
		if type(displayEntry.GradientPaths) == "table" then
			gradientPathOrList = displayEntry.GradientPaths
		else
			gradientPathOrList = displayEntry.GradientPath
		end
	end

	return displayName, gradientPathOrList
end

local function resolveRarityDisplayInfo(rarityId)
	local parsedId = math.floor(tonumber(rarityId) or 0)
	local displayEntry = type(BrainrotDisplayConfig.Rarity) == "table" and BrainrotDisplayConfig.Rarity[parsedId] or nil
	local displayName = (type(displayEntry) == "table" and tostring(displayEntry.Name or "")) or ""
	if displayName == "" then
		displayName = BrainrotConfig.RarityNames[parsedId] or "Unknown"
	end

	local gradientPathOrList = nil
	if type(displayEntry) == "table" then
		if type(displayEntry.GradientPaths) == "table" then
			gradientPathOrList = displayEntry.GradientPaths
		else
			gradientPathOrList = displayEntry.GradientPath
		end
	end

	return displayName, gradientPathOrList
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

local function findInstanceBySlashPath(pathText)
	local segments = splitSlashPath(pathText)
	if #segments <= 0 then
		return nil
	end

	local current = nil
	for index, segment in ipairs(segments) do
		if index == 1 then
			if segment == "StarterGui" then
				current = StarterGui
			elseif segment == "ReplicatedStorage" then
				current = ReplicatedStorage
			elseif segment == "Workspace" then
				current = game:GetService("Workspace")
			else
				current = game:FindFirstChild(segment)
			end
		else
			current = current and current:FindFirstChild(segment) or nil
		end

		if not current then
			return nil
		end
	end

	return current
end

local function findFirstTextLabelByName(root, nodeName)
	if not root then
		return nil
	end

	local node = root:FindFirstChild(nodeName, true)
	if node and node:IsA("TextLabel") then
		return node
	end

	return nil
end

local function findFirstGuiObjectByName(root, nodeName)
	if not root then
		return nil
	end

	local node = root:FindFirstChild(nodeName, true)
	if node and node:IsA("GuiObject") then
		return node
	end

	return nil
end

local function markManagedDisplayNode(node)
	if not node then
		return
	end

	node:SetAttribute("BrainrotInfoGradient", true)
	for _, descendant in ipairs(node:GetDescendants()) do
		descendant:SetAttribute("BrainrotInfoGradient", true)
	end
end

local function clearManagedDisplayNodes(parentNode)
	if not parentNode then
		return
	end

	for _, child in ipairs(parentNode:GetChildren()) do
		if child:GetAttribute("BrainrotInfoGradient") == true then
			child:Destroy()
		end
	end
end
local SECRET_QUALITY_STROKE_COLOR = Color3.fromRGB(255, 255, 255)

local function applyQualityStrokeColorRule(qualityLabel, qualityId)
	if not (qualityLabel and qualityLabel:IsA("TextLabel")) then
		return
	end

	local isSecretQuality = math.floor(tonumber(qualityId) or 0) == 7
	for _, stroke in ipairs(qualityLabel:GetChildren()) do
		if stroke:IsA("UIStroke") and stroke:GetAttribute("BrainrotInfoGradient") ~= true then
			local defaultColor = stroke:GetAttribute("BrainrotDefaultStrokeColor")
			if typeof(defaultColor) ~= "Color3" then
				stroke:SetAttribute("BrainrotDefaultStrokeColor", stroke.Color)
				defaultColor = stroke.Color
			end

			if isSecretQuality then
				stroke.Color = SECRET_QUALITY_STROKE_COLOR
			elseif typeof(defaultColor) == "Color3" then
				stroke.Color = defaultColor
			end
		end
	end
end
local function modulo01(value)
	local parsed = tonumber(value) or 0
	parsed = parsed % 1
	if parsed < 0 then
		parsed = parsed + 1
	end
	return parsed
end

local function collectRotatedInteriorPositions(baseKeypoints, shift)
	local positions = {}
	for _, keypoint in ipairs(baseKeypoints) do
		local rotatedTime = modulo01((tonumber(keypoint.Time) or 0) + shift)
		if rotatedTime > 0.0001 and rotatedTime < 0.9999 then
			table.insert(positions, rotatedTime)
		end
	end

	table.sort(positions)

	local deduplicated = {}
	local lastTime = nil
	for _, timeValue in ipairs(positions) do
		if not lastTime or math.abs(timeValue - lastTime) > 0.0001 then
			table.insert(deduplicated, timeValue)
			lastTime = timeValue
		end
	end

	return deduplicated
end

local function sampleColorSequencePeriodic(baseKeypoints, timeValue)
	local count = #baseKeypoints
	if count <= 0 then
		return Color3.new(1, 1, 1)
	end

	if count == 1 then
		return baseKeypoints[1].Value
	end

	local targetTime = modulo01(timeValue)

	for index = 1, count - 1 do
		local left = baseKeypoints[index]
		local right = baseKeypoints[index + 1]
		if targetTime >= left.Time and targetTime <= right.Time then
			local span = math.max(0.000001, right.Time - left.Time)
			local alpha = math.clamp((targetTime - left.Time) / span, 0, 1)
			return left.Value:Lerp(right.Value, alpha)
		end
	end

	local last = baseKeypoints[count]
	local first = baseKeypoints[1]
	local wrappedTime = targetTime
	if wrappedTime < first.Time then
		wrappedTime = wrappedTime + 1
	end

	local span = math.max(0.000001, (first.Time + 1) - last.Time)
	local alpha = math.clamp((wrappedTime - last.Time) / span, 0, 1)
	return last.Value:Lerp(first.Value, alpha)
end

local function sampleNumberSequencePeriodic(baseKeypoints, timeValue)
	local count = #baseKeypoints
	if count <= 0 then
		return 0, 0
	end

	if count == 1 then
		return baseKeypoints[1].Value, baseKeypoints[1].Envelope
	end

	local targetTime = modulo01(timeValue)

	for index = 1, count - 1 do
		local left = baseKeypoints[index]
		local right = baseKeypoints[index + 1]
		if targetTime >= left.Time and targetTime <= right.Time then
			local span = math.max(0.000001, right.Time - left.Time)
			local alpha = math.clamp((targetTime - left.Time) / span, 0, 1)
			local value = left.Value + ((right.Value - left.Value) * alpha)
			local envelope = left.Envelope + ((right.Envelope - left.Envelope) * alpha)
			return value, envelope
		end
	end

	local last = baseKeypoints[count]
	local first = baseKeypoints[1]
	local wrappedTime = targetTime
	if wrappedTime < first.Time then
		wrappedTime = wrappedTime + 1
	end

	local span = math.max(0.000001, (first.Time + 1) - last.Time)
	local alpha = math.clamp((wrappedTime - last.Time) / span, 0, 1)
	local value = last.Value + ((first.Value - last.Value) * alpha)
	local envelope = last.Envelope + ((first.Envelope - last.Envelope) * alpha)
	return value, envelope
end

local function buildRotatedColorSequence(baseKeypoints, shift)
	local keypoints = {
		ColorSequenceKeypoint.new(0, sampleColorSequencePeriodic(baseKeypoints, -shift)),
	}

	for _, position in ipairs(collectRotatedInteriorPositions(baseKeypoints, shift)) do
		table.insert(keypoints, ColorSequenceKeypoint.new(position, sampleColorSequencePeriodic(baseKeypoints, position - shift)))
	end

	table.insert(keypoints, ColorSequenceKeypoint.new(1, sampleColorSequencePeriodic(baseKeypoints, 1 - shift)))
	return ColorSequence.new(keypoints)
end

local function buildRotatedNumberSequence(baseKeypoints, shift)
	local startValue, startEnvelope = sampleNumberSequencePeriodic(baseKeypoints, -shift)
	local keypoints = {
		NumberSequenceKeypoint.new(0, startValue, startEnvelope),
	}

	for _, position in ipairs(collectRotatedInteriorPositions(baseKeypoints, shift)) do
		local value, envelope = sampleNumberSequencePeriodic(baseKeypoints, position - shift)
		table.insert(keypoints, NumberSequenceKeypoint.new(position, value, envelope))
	end

	local endValue, endEnvelope = sampleNumberSequencePeriodic(baseKeypoints, 1 - shift)
	table.insert(keypoints, NumberSequenceKeypoint.new(1, endValue, endEnvelope))
	return NumberSequence.new(keypoints)
end

local function resolveAnimatedQualityGradientProfile(pathKey, gradientPath)
	local key = tostring(pathKey or "")
	if key == "Quality:6" then
		return "MythicQualityGradient"
	end
	if key == "Quality:7" then
		return "SecretQualityGradient"
	end
	if key == "Quality:8" then
		return "GodQualityGradient"
	end
	if key == "Quality:9" then
		return "OGQualityGradient"
	end
	if key == "Rarity:5" then
		return "LavaRarityGradient"
	end
	if key == "Rarity:6" then
		return "RainbowRarityGradient"
	end
	if key == "Rarity:7" then
		return "HackerRarityGradient"
	end

	if type(gradientPath) ~= "string" then
		return nil
	end

	local lowerPath = string.lower(gradientPath)
	if string.find(lowerPath, "startergui/gradients/animation/quality/mythic", 1, true) ~= nil then
		return "MythicQualityGradient"
	end
	if string.find(lowerPath, "startergui/gradients/animation/quality/secret", 1, true) ~= nil then
		return "SecretQualityGradient"
	end
	if string.find(lowerPath, "startergui/gradients/animation/quality/god", 1, true) ~= nil then
		return "GodQualityGradient"
	end
	if string.find(lowerPath, "startergui/gradients/animation/quality/og", 1, true) ~= nil then
		return "OGQualityGradient"
	end
	if string.find(lowerPath, "startergui/gradients/animation/rarity/lava", 1, true) ~= nil then
		return "LavaRarityGradient"
	end
	if string.find(lowerPath, "startergui/gradients/animation/rarity/hacker", 1, true) ~= nil then
		return "HackerRarityGradient"
	end
	if string.find(lowerPath, "startergui/gradients/animation/rarity/rainbow", 1, true) ~= nil then
		return "RainbowRarityGradient"
	end

	return nil
end
local function resolveAnimatedQualityGradientConfig(profileName)
	local configRoot = GameConfig.BRAINROT or {}
	local prefix = tostring(profileName or "")
	if prefix == "" then
		return nil
	end

	local enabledKey = prefix .. "AnimationEnabled"
	local offsetRangeKey = prefix .. "OffsetRange"
	local oneWayDurationKey = prefix .. "OneWayDuration"
	local updateIntervalKey = prefix .. "UpdateInterval"

	local config = {
		Enabled = configRoot[enabledKey] ~= false,
		OffsetRange = math.max(0.05, tonumber(configRoot[offsetRangeKey]) or 1),
		OneWayDuration = math.max(0.2, tonumber(configRoot[oneWayDurationKey]) or 2.4),
		UpdateInterval = math.max(1 / 120, tonumber(configRoot[updateIntervalKey]) or (1 / 30)),
	}

	return config
end
function BrainrotService:_tryStartDisplayGradientAnimation(node, gradientPath, pathKey)
	if not (node and node:IsA("UIGradient")) then
		return
	end

	local profileName = resolveAnimatedQualityGradientProfile(pathKey, gradientPath)
	if not profileName then
		return
	end

	local animationConfig = resolveAnimatedQualityGradientConfig(profileName)
	if not animationConfig or animationConfig.Enabled == false then
		return
	end

	if node:GetAttribute("BrainrotInfoGradientAnimated") == true then
		return
	end
	node:SetAttribute("BrainrotInfoGradientAnimated", true)

	local baseColorKeypoints = node.Color.Keypoints
	if type(baseColorKeypoints) ~= "table" or #baseColorKeypoints <= 0 then
		return
	end

	local baseTransparencyKeypoints = node.Transparency.Keypoints
	local cycleScale = animationConfig.OffsetRange
	local cycleDuration = animationConfig.OneWayDuration
	local updateInterval = animationConfig.UpdateInterval

	task.spawn(function()
		local elapsed = 0
		local elapsedSinceUpdate = 0

		while node and node.Parent do
			local delta = task.wait()
			elapsed = elapsed + delta
			elapsedSinceUpdate = elapsedSinceUpdate + delta

			if elapsedSinceUpdate >= updateInterval then
				elapsedSinceUpdate = 0
				local shift = modulo01((elapsed / cycleDuration) * cycleScale)

				local okColor, rotatedColor = pcall(function()
					return buildRotatedColorSequence(baseColorKeypoints, shift)
				end)
				if okColor and rotatedColor then
					node.Color = rotatedColor
				end

				if type(baseTransparencyKeypoints) == "table" and #baseTransparencyKeypoints > 0 then
					local okTransparency, rotatedTransparency = pcall(function()
						return buildRotatedNumberSequence(baseTransparencyKeypoints, shift)
					end)
					if okTransparency and rotatedTransparency then
						node.Transparency = rotatedTransparency
					end
				end
			end
		end
	end)
end

function BrainrotService:_warnMissingDisplayPath(pathKey, pathText)
	local key = tostring(pathKey or "")
	if key == "" then
		return
	end

	if self._missingDisplayPathWarned[key] then
		return
	end

	self._missingDisplayPathWarned[key] = true
	warn(string.format(
		"[BrainrotService] 渐变节点缺失或不可用: %s（路径=%s）",
		key,
		tostring(pathText)
		))
end

local function normalizeGradientPathList(gradientPathOrList)
	local result = {}

	if type(gradientPathOrList) == "string" then
		if gradientPathOrList ~= "" then
			table.insert(result, gradientPathOrList)
		end
		return result
	end

	if type(gradientPathOrList) ~= "table" then
		return result
	end

	for _, value in ipairs(gradientPathOrList) do
		if type(value) == "string" and value ~= "" then
			table.insert(result, value)
		end
	end

	return result
end

local function findDisplayTargetStroke(label)
	if not (label and label:IsA("TextLabel")) then
		return nil
	end

	local directStroke = label:FindFirstChildWhichIsA("UIStroke")
	if directStroke and directStroke:GetAttribute("BrainrotInfoGradient") ~= true then
		return directStroke
	end

	for _, descendant in ipairs(label:GetDescendants()) do
		if descendant:IsA("UIStroke") and descendant:GetAttribute("BrainrotInfoGradient") ~= true then
			return descendant
		end
	end

	return nil
end

function BrainrotService:_applyDisplayGradientToNode(targetNode, gradientPath, pathKey, pathWarnKey)
	if not targetNode then
		return false
	end

	local sourceNode = findInstanceBySlashPath(gradientPath)
	if not sourceNode then
		self:_warnMissingDisplayPath(pathWarnKey, gradientPath)
		return false
	end

	local gradientNodes = {}
	if sourceNode:IsA("UIGradient") or sourceNode:IsA("UIStroke") then
		table.insert(gradientNodes, sourceNode)
	else
		for _, descendant in ipairs(sourceNode:GetDescendants()) do
			if descendant:IsA("UIGradient") or descendant:IsA("UIStroke") then
				table.insert(gradientNodes, descendant)
			end
		end
	end

	if #gradientNodes <= 0 then
		self:_warnMissingDisplayPath(pathWarnKey, gradientPath)
		return false
	end

	for _, gradientNode in ipairs(gradientNodes) do
		local clonedNode = gradientNode:Clone()
		markManagedDisplayNode(clonedNode)

		local ok = pcall(function()
			clonedNode.Parent = targetNode
		end)

		if not ok then
			clonedNode:Destroy()
			self:_warnMissingDisplayPath(pathWarnKey, gradientPath)
		else
			self:_tryStartDisplayGradientAnimation(clonedNode, gradientPath, pathKey)
		end
	end

	return true
end

function BrainrotService:_applyDisplayGradient(label, gradientPathOrList, pathKey)
	if not (label and label:IsA("TextLabel")) then
		return
	end

	clearManagedDisplayNodes(label)
	for _, descendant in ipairs(label:GetDescendants()) do
		if descendant:IsA("UIStroke") and descendant:GetAttribute("BrainrotInfoGradient") ~= true then
			clearManagedDisplayNodes(descendant)
		end
	end

	local gradientPathList = normalizeGradientPathList(gradientPathOrList)
	if #gradientPathList <= 0 then
		return
	end

	local baseWarnKey = tostring(pathKey or "Unknown")
	local isSecretQuality = baseWarnKey == "Quality:7"

	if isSecretQuality and #gradientPathList >= 2 then
		local strokeTarget = findDisplayTargetStroke(label)
		if strokeTarget then
			self:_applyDisplayGradientToNode(strokeTarget, gradientPathList[1], pathKey, string.format("%s:Stroke", baseWarnKey))
		else
			self:_warnMissingDisplayPath(string.format("%s:StrokeTarget", baseWarnKey), "UIStroke target missing for Secret1")
		end

		self:_applyDisplayGradientToNode(label, gradientPathList[2], pathKey, string.format("%s:Text", baseWarnKey))

		for pathIndex = 3, #gradientPathList do
			self:_applyDisplayGradientToNode(label, gradientPathList[pathIndex], pathKey, string.format("%s:%d", baseWarnKey, pathIndex))
		end
		return
	end

	for pathIndex, gradientPath in ipairs(gradientPathList) do
		self:_applyDisplayGradientToNode(label, gradientPath, pathKey, string.format("%s:%d", baseWarnKey, pathIndex))
	end
end
function BrainrotService:_findInfoAttachment(placedInstance)
	if not placedInstance then
		return nil
	end

	local infoAttachmentName = tostring(GameConfig.BRAINROT.InfoAttachmentName or "Info")
	local infoAttachment = placedInstance:FindFirstChild(infoAttachmentName, true)
	if infoAttachment and infoAttachment:IsA("Attachment") then
		return infoAttachment
	end

	return nil
end

function BrainrotService:_attachPlacedInfoUi(placedInstance, brainrotDefinition, brainrotLevel)
	if not placedInstance or type(brainrotDefinition) ~= "table" then
		return
	end

	local infoTemplateRootName = tostring(GameConfig.BRAINROT.InfoTemplateRootName or "UI")
	local infoTemplateName = tostring(GameConfig.BRAINROT.InfoTemplateName or "BaseInfo")
	local infoTitleRootName = tostring(GameConfig.BRAINROT.InfoTitleRootName or "Title")
	local infoNameLabelName = tostring(GameConfig.BRAINROT.InfoNameLabelName or "Name")
	local infoQualityLabelName = tostring(GameConfig.BRAINROT.InfoQualityLabelName or "Quality")
	local infoRarityLabelName = tostring(GameConfig.BRAINROT.InfoRarityLabelName or "Rarity")
	local infoSpeedLabelName = tostring(GameConfig.BRAINROT.InfoSpeedLabelName or "Speed")
	local infoTimeRootName = tostring(GameConfig.BRAINROT.InfoTimeRootName or "Time")
	local infoTimeLabelName = tostring(GameConfig.BRAINROT.InfoTimeLabelName or "Time")

	local infoTemplateRoot = ReplicatedStorage:FindFirstChild(infoTemplateRootName)
	local infoTemplate = infoTemplateRoot and infoTemplateRoot:FindFirstChild(infoTemplateName) or nil
	if not (infoTemplate and infoTemplate:IsA("BillboardGui")) then
		if not self._didWarnMissingBaseInfoTemplate then
			warn(string.format(
				"[BrainrotService] ?????????ReplicatedStorage/%s/%s",
				tostring(infoTemplateRootName),
				tostring(infoTemplateName)
			))
			self._didWarnMissingBaseInfoTemplate = true
		end
		return
	end

	local infoAttachment = self:_findInfoAttachment(placedInstance)
	if not infoAttachment then
		local modelPathKey = tostring(brainrotDefinition.ModelPath or "UnknownModelPath")
		if not self._didWarnMissingInfoAttachmentByModelPath[modelPathKey] then
			warn(string.format(
				"[BrainrotService] ?????? Info Attachment????? BaseInfo?ModelPath=%s?",
				modelPathKey
			))
			self._didWarnMissingInfoAttachmentByModelPath[modelPathKey] = true
		end
		return
	end

	local existingInfo = infoAttachment:FindFirstChild(infoTemplateName)
	if existingInfo and existingInfo:IsA("BillboardGui") then
		existingInfo:Destroy()
	end

	local infoGui = infoTemplate:Clone()
	infoGui.Name = infoTemplateName
	infoGui.Adornee = infoAttachment
	infoGui.Parent = infoAttachment

	local titleRoot = infoGui:FindFirstChild(infoTitleRootName, true)
	local searchRoot = titleRoot or infoGui

	local nameLabel = findFirstTextLabelByName(searchRoot, infoNameLabelName) or findFirstTextLabelByName(infoGui, infoNameLabelName)
	local qualityLabel = findFirstTextLabelByName(searchRoot, infoQualityLabelName) or findFirstTextLabelByName(infoGui, infoQualityLabelName)
	local rarityLabel = findFirstTextLabelByName(searchRoot, infoRarityLabelName) or findFirstTextLabelByName(infoGui, infoRarityLabelName)
	local speedLabel = findFirstTextLabelByName(searchRoot, infoSpeedLabelName) or findFirstTextLabelByName(infoGui, infoSpeedLabelName)
	local timeRoot = searchRoot:FindFirstChild(infoTimeRootName, true) or infoGui:FindFirstChild(infoTimeRootName, true)
	local timeLabel = findFirstTextLabelByName(timeRoot or searchRoot, infoTimeLabelName) or findFirstTextLabelByName(infoGui, infoTimeLabelName)

	local qualityId = math.floor(tonumber(brainrotDefinition.Quality) or 0)
	local rarityId = math.floor(tonumber(brainrotDefinition.Rarity) or 0)
	local qualityName, qualityGradientPath = resolveQualityDisplayInfo(qualityId)
	local rarityName, rarityGradientPath = resolveRarityDisplayInfo(rarityId)
	local coinPerSecond = getBrainrotProductionSpeed(brainrotDefinition, brainrotLevel)

	if nameLabel then
		nameLabel.Text = formatPlacedBrainrotDisplayName(brainrotDefinition, brainrotLevel)
	end

	if qualityLabel then
		qualityLabel.Visible = true
		qualityLabel.Text = tostring(qualityName)
		applyQualityStrokeColorRule(qualityLabel, qualityId)
		self:_applyDisplayGradient(qualityLabel, qualityGradientPath, "Quality:" .. tostring(qualityId))
	end

	if rarityLabel then
		local hideNormalRarity = GameConfig.BRAINROT.HideNormalRarity ~= false
		local shouldShowRarity = (not hideNormalRarity) or rarityId > 1
		rarityLabel.Visible = shouldShowRarity
		rarityLabel.Text = tostring(rarityName)

		if shouldShowRarity then
			self:_applyDisplayGradient(rarityLabel, rarityGradientPath, "Rarity:" .. tostring(rarityId))
		else
			clearManagedDisplayNodes(rarityLabel)
		end
	end

	if speedLabel then
		speedLabel.Text = formatBrainrotSpeed(coinPerSecond)
	end

	if timeRoot and timeRoot:IsA("GuiObject") then
		timeRoot.Visible = false
	end
	if timeRoot and timeRoot:IsA("LayerCollector") then
		timeRoot.Enabled = false
	end
	if timeLabel then
		timeLabel.Visible = false
		timeLabel.Text = ""
	end
end
local function getOrCreatePulseScale(label)
	if not label or not label:IsA("TextLabel") then
		return nil
	end

	local pulseScale = label:FindFirstChild("GoldPulseScale")
	if pulseScale and pulseScale:IsA("UIScale") then
		return pulseScale
	end

	pulseScale = Instance.new("UIScale")
	pulseScale.Name = "GoldPulseScale"
	pulseScale.Scale = 1
	pulseScale.Parent = label
	return pulseScale
end

function BrainrotService:_disconnectConnections(connectionList)
	if type(connectionList) ~= "table" then
		return
	end

	for _, connection in ipairs(connectionList) do
		if connection and connection.Disconnect then
			connection:Disconnect()
		end
	end
end

function BrainrotService:_clearPlacedPromptForPosition(userId, positionKey)
	local promptStateByPosition = self._placedPromptStateByUserId[userId]
	if type(promptStateByPosition) ~= "table" then
		return
	end

	local promptState = promptStateByPosition[positionKey]
	if type(promptState) ~= "table" then
		return
	end

	if promptState.Connection and promptState.Connection.Disconnect then
		promptState.Connection:Disconnect()
		promptState.Connection = nil
	end

	if promptState.Prompt and promptState.Prompt.Parent then
		promptState.Prompt:Destroy()
	end

	promptStateByPosition[positionKey] = nil
	if next(promptStateByPosition) == nil then
		self._placedPromptStateByUserId[userId] = nil
	end
end

function BrainrotService:_clearPlacedPromptState(player)
	if not player then
		return
	end

	local userId = player.UserId
	local promptStateByPosition = self._placedPromptStateByUserId[userId]
	if type(promptStateByPosition) ~= "table" then
		return
	end

	local pendingPositionKeys = {}
	for positionKey in pairs(promptStateByPosition) do
		table.insert(pendingPositionKeys, positionKey)
	end

	for _, positionKey in ipairs(pendingPositionKeys) do
		self:_clearPlacedPromptForPosition(userId, positionKey)
	end

	self._placedPromptStateByUserId[userId] = nil
end

function BrainrotService:_clearPlacedStealPromptForPosition(userId, positionKey)
	local promptStateByPosition = self._placedStealPromptStateByUserId[userId]
	if type(promptStateByPosition) ~= "table" then
		return
	end

	local promptState = promptStateByPosition[positionKey]
	if type(promptState) ~= "table" then
		return
	end

	if promptState.Connection and promptState.Connection.Disconnect then
		promptState.Connection:Disconnect()
		promptState.Connection = nil
	end

	if promptState.Prompt and promptState.Prompt.Parent then
		promptState.Prompt:Destroy()
	end

	promptStateByPosition[positionKey] = nil
	if next(promptStateByPosition) == nil then
		self._placedStealPromptStateByUserId[userId] = nil
	end
end

function BrainrotService:_clearPlacedStealPromptState(player)
	if not player then
		return
	end

	local userId = player.UserId
	local promptStateByPosition = self._placedStealPromptStateByUserId[userId]
	if type(promptStateByPosition) ~= "table" then
		return
	end

	local pendingPositionKeys = {}
	for positionKey in pairs(promptStateByPosition) do
		table.insert(pendingPositionKeys, positionKey)
	end

	for _, positionKey in ipairs(pendingPositionKeys) do
		self:_clearPlacedStealPromptForPosition(userId, positionKey)
	end

	self._placedStealPromptStateByUserId[userId] = nil
end

function BrainrotService:_clearPromptConnections(player)
	local userId = player.UserId
	local platformsByPositionKey = self._platformsByUserId[userId]
	if type(platformsByPositionKey) == "table" then
		for _, platformInfo in pairs(platformsByPositionKey) do
			local prompt = platformInfo and platformInfo.Prompt
			if prompt and prompt:IsA("ProximityPrompt") then
				prompt:SetAttribute(BRAINROT_PLATFORM_SERVER_ENABLED_ATTRIBUTE, false)
				prompt.Enabled = false
			end
		end
	end

	self:_disconnectConnections(self._promptConnectionsByUserId[userId])
	self._promptConnectionsByUserId[userId] = nil
	self:_clearPlacedPromptState(player)
	self:_clearPlacedStealPromptState(player)
	self._platformsByUserId[userId] = nil
end

function BrainrotService:_clearClaimConnections(player)
	local userId = player.UserId
	self:_disconnectConnections(self._claimConnectionsByUserId[userId])
	self._claimConnectionsByUserId[userId] = nil
	self._claimTouchDebounceByUserId[userId] = nil

	local claimsByPositionKey = self._claimsByUserId[userId]
	if type(claimsByPositionKey) == "table" then
		for _, claimInfo in pairs(claimsByPositionKey) do
			if claimInfo and claimInfo._currentPressTween then
				claimInfo._currentPressTween:Cancel()
				claimInfo._currentPressTween = nil
			end

			if claimInfo and claimInfo._touchHighlightTween then
				claimInfo._touchHighlightTween:Cancel()
				claimInfo._touchHighlightTween = nil
			end

			if claimInfo and claimInfo._touchHighlight then
				claimInfo._touchHighlight:Destroy()
				claimInfo._touchHighlight = nil
			end

			local pressPart = claimInfo.TouchPart or claimInfo.ClaimPart
			local pressBaseCFrame = claimInfo.TouchPart and claimInfo.TouchBaseCFrame or claimInfo.ClaimBaseCFrame
			if pressPart and pressPart.Parent and pressBaseCFrame then
				pressPart.CFrame = pressBaseCFrame
			end
		end
	end

	local claimEffectByPosition = self._claimEffectByUserId[userId]
	if type(claimEffectByPosition) == "table" then
		local pendingEffectKeys = {}
		for positionKey in pairs(claimEffectByPosition) do
			table.insert(pendingEffectKeys, positionKey)
		end

		for _, positionKey in ipairs(pendingEffectKeys) do
			self:_destroyClaimTouchEffectForPosition(userId, positionKey)
		end
	end
	self._claimEffectByUserId[userId] = nil

	local claimBounceByPosition = self._claimBounceStateByUserId[userId]
	if type(claimBounceByPosition) == "table" then
		local pendingKeys = {}
		for positionKey in pairs(claimBounceByPosition) do
			table.insert(pendingKeys, positionKey)
		end

		for _, positionKey in ipairs(pendingKeys) do
			self:_clearClaimBounceState(userId, positionKey, true)
		end
	end
	self._claimBounceStateByUserId[userId] = nil

	self._claimsByUserId[userId] = nil
end
function BrainrotService:_clearToolConnections(player)
	local userId = player.UserId
	self:_disconnectConnections(self._toolConnectionsByUserId[userId])
	self._toolConnectionsByUserId[userId] = nil
end

function BrainrotService:_clearToolRefreshWatchers(player)
	local userId = player.UserId
	self:_disconnectConnections(self._toolRefreshConnectionsByUserId[userId])
	self._toolRefreshConnectionsByUserId[userId] = nil
	self._toolRefreshBurstSerialByUserId[userId] = (self._toolRefreshBurstSerialByUserId[userId] or 0) + 1
end

function BrainrotService:_countBrainrotTools(player)
	local toolCount = 0
	for _, container in ipairs({
		player and player:FindFirstChild("Backpack") or nil,
		player and player.Character or nil,
	}) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") and child:GetAttribute("BrainrotTool") == true then
					toolCount += 1
				end
			end
		end
	end

	return toolCount
end

function BrainrotService:_ensureBrainrotToolsSynced(player)
	if not (player and player.Parent) then
		return false
	end

	local _playerData, brainrotData = self:_getOrCreateDataContainers(player)
	if not brainrotData then
		return false
	end

	local expectedToolCount = #brainrotData.Inventory
	local actualToolCount = self:_countBrainrotTools(player)
	if expectedToolCount == actualToolCount then
		return false
	end

	local equippedInstanceId = math.max(0, math.floor(tonumber(brainrotData.EquippedInstanceId) or 0))
	self:_refreshBrainrotTools(player)

	if equippedInstanceId > 0 then
		task.defer(function()
			self:_equipBrainrotToolByInstanceId(player, equippedInstanceId)
		end)
	end

	self:PushBrainrotState(player)
	return true
end

function BrainrotService:_scheduleToolRefreshBurst(player, durationSeconds, intervalSeconds)
	if not (player and player.Parent) then
		return
	end

	local userId = player.UserId
	local duration = math.max(0, tonumber(durationSeconds) or 0)
	local interval = math.max(0.1, tonumber(intervalSeconds) or 0.5)
	self._toolRefreshBurstSerialByUserId[userId] = (self._toolRefreshBurstSerialByUserId[userId] or 0) + 1
	local burstSerial = self._toolRefreshBurstSerialByUserId[userId]

	task.spawn(function()
		local deadline = os.clock() + duration
		repeat
			if not player.Parent or self._toolRefreshBurstSerialByUserId[userId] ~= burstSerial then
				return
			end

			self:_ensureBrainrotToolsSynced(player)
			task.wait(interval)
		until os.clock() >= deadline
	end)
end

function BrainrotService:_bindToolRefreshWatchers(player)
	self:_clearToolRefreshWatchers(player)

	local userId = player.UserId
	local connectionList = {}
	self._toolRefreshConnectionsByUserId[userId] = connectionList

	table.insert(connectionList, player.CharacterAdded:Connect(function()
		task.defer(function()
			self:_scheduleToolRefreshBurst(player, 8, 0.5)
		end)
	end))

	table.insert(connectionList, player.ChildAdded:Connect(function(child)
		if child and (child.Name == "Backpack" or child:IsA("Backpack")) then
			self:_scheduleToolRefreshBurst(player, 8, 0.5)
		end
	end))
end

function BrainrotService:_clearRuntimePlaced(player)
	self:_stopAllIdleTracks(player)
	self:_clearPlacedPromptState(player)
	self:_clearPlacedStealPromptState(player)

	local userId = player.UserId
	local runtimePlaced = self._runtimePlacedByUserId[userId]
	if type(runtimePlaced) ~= "table" then
		return
	end

	for _, modelOrPart in pairs(runtimePlaced) do
		if modelOrPart and modelOrPart.Parent then
			modelOrPart:Destroy()
		end
	end

	local claimBounceByPosition = self._claimBounceStateByUserId[userId]
	if type(claimBounceByPosition) == "table" then
		local pendingKeys = {}
		for positionKey in pairs(claimBounceByPosition) do
			table.insert(pendingKeys, positionKey)
		end

		for _, positionKey in ipairs(pendingKeys) do
			self:_clearClaimBounceState(userId, positionKey, false)
		end
	end
	self._claimBounceStateByUserId[userId] = nil

	self._runtimePlacedByUserId[userId] = nil
end

function BrainrotService:_getBrainrotModelTemplate(modelPath)
	local qualityFolderName, modelName = parseModelPath(modelPath)
	if not qualityFolderName or not modelName then
		return nil
	end

	local modelRoot = ReplicatedStorage:FindFirstChild(GameConfig.BRAINROT.ModelRootFolderName)
	if not modelRoot then
		return nil
	end

	local qualityFolder = modelRoot:FindFirstChild(qualityFolderName)
	if not qualityFolder then
		return nil
	end

	local template = qualityFolder:FindFirstChild(modelName)
	if template and (template:IsA("Model") or template:IsA("BasePart") or template:IsA("Tool")) then
		return template
	end

	return nil
end

function BrainrotService:_getOrCreateDataContainersFromPlayerData(playerData)
	return self:_requireStateStore():GetOrCreateDataContainersFromPlayerData(playerData)
end

function BrainrotService:_getOrCreateDataContainers(player)
	return self:_requireStateStore():GetOrCreateDataContainers(player)
end

function BrainrotService:_getOrCreateProcessedStealPurchaseIds(brainrotData)
	return self:_requireStateStore():GetOrCreateProcessedStealPurchaseIds(brainrotData)
end

function BrainrotService:_getOrCreateProcessedCarryPurchaseIds(brainrotData)
	return self:_requireStateStore():GetOrCreateProcessedCarryPurchaseIds(brainrotData)
end

function BrainrotService:_buildCarryUpgradeStatePayload(brainrotData)
	local currentLevel = normalizeCarryUpgradeLevel(type(brainrotData) == "table" and brainrotData.CarryUpgradeLevel or 0)
	local currentEntry = CarryConfig.EntriesByLevel[currentLevel]
	local nextEntry = CarryConfig.EntriesByLevel[currentLevel + 1]
	local currentCarryCount = math.max(getBaseCarryCount(), math.floor(tonumber(currentEntry and currentEntry.CarryCount) or getBaseCarryCount()))
	local nextCarryCount = math.max(currentCarryCount, math.floor(tonumber(nextEntry and nextEntry.CarryCount) or currentCarryCount))

	return {
		currentLevel = currentLevel,
		currentCarryCount = currentCarryCount,
		nextLevel = nextEntry and nextEntry.Level or currentLevel,
		nextCarryCount = nextCarryCount,
		nextCoinPrice = math.max(0, math.floor(tonumber(nextEntry and nextEntry.CoinPrice) or 0)),
		nextRobuxPrice = math.max(0, math.floor(tonumber(nextEntry and nextEntry.RobuxPrice) or 0)),
		nextProductId = math.max(0, math.floor(tonumber(nextEntry and nextEntry.ProductId) or 0)),
		isMax = nextEntry == nil,
	}
end

function BrainrotService:_getCarryCapacity(player)
	local _playerData, brainrotData = self:_getOrCreateDataContainers(player)
	local carryState = self:_buildCarryUpgradeStatePayload(brainrotData)
	return math.max(getBaseCarryCount(), math.floor(tonumber(carryState.currentCarryCount) or getBaseCarryCount()))
end

function BrainrotService:_normalizePendingStealPurchase(source)
	if type(source) ~= "table" then
		return nil
	end

	local requestId = tostring(source.RequestId or source.requestId or "")
	local productId = math.max(0, math.floor(tonumber(source.ProductId or source.productId) or 0))
	local brainrotId = math.max(0, math.floor(tonumber(source.BrainrotId or source.brainrotId) or 0))
	local instanceId = math.max(0, math.floor(tonumber(source.InstanceId or source.instanceId) or 0))
	local ownerUserId = math.max(0, math.floor(tonumber(source.OwnerUserId or source.ownerUserId) or 0))
	local ownerLastLoginAt = normalizeTimestamp(source.OwnerLastLoginAt or source.ownerLastLoginAt)
	if requestId == "" or productId <= 0 or brainrotId <= 0 or instanceId <= 0 or ownerUserId <= 0 then
		return nil
	end

	return {
		RequestId = requestId,
		BuyerUserId = math.max(0, math.floor(tonumber(source.BuyerUserId or source.buyerUserId) or 0)),
		OwnerUserId = ownerUserId,
		OwnerName = tostring(source.OwnerName or source.ownerName or ""),
		OwnerLastLoginAt = ownerLastLoginAt,
		InstanceId = instanceId,
		BrainrotId = brainrotId,
		BrainrotName = tostring(source.BrainrotName or source.brainrotName or "Brainrot"),
		Level = normalizeBrainrotLevel(source.Level or source.level),
		ProductId = productId,
		PriceRobux = math.max(0, math.floor(tonumber(source.PriceRobux or source.priceRobux) or 0)),
		Quality = math.max(0, math.floor(tonumber(source.Quality or source.quality) or 0)),
		CreatedAt = math.max(0, math.floor(tonumber(source.CreatedAt or source.createdAt) or 0)),
	}
end

function BrainrotService:_writePendingStealPurchase(brainrotData, pending)
	if type(brainrotData) ~= "table" then
		return
	end

	local normalizedPending = self:_normalizePendingStealPurchase(pending)
	if not normalizedPending then
		brainrotData.PendingStealPurchase = {}
		return
	end

	brainrotData.PendingStealPurchase = {
		RequestId = normalizedPending.RequestId,
		BuyerUserId = normalizedPending.BuyerUserId,
		OwnerUserId = normalizedPending.OwnerUserId,
		OwnerName = normalizedPending.OwnerName,
		OwnerLastLoginAt = normalizedPending.OwnerLastLoginAt,
		InstanceId = normalizedPending.InstanceId,
		BrainrotId = normalizedPending.BrainrotId,
		BrainrotName = normalizedPending.BrainrotName,
		Level = normalizedPending.Level,
		ProductId = normalizedPending.ProductId,
		PriceRobux = normalizedPending.PriceRobux,
		Quality = normalizedPending.Quality,
		CreatedAt = normalizedPending.CreatedAt,
	}
end

function BrainrotService:_snapshotBrainrotState(brainrotData, placedBrainrots, productionState)
	return self:_requireStateStore():Snapshot(brainrotData, placedBrainrots, productionState)
end

function BrainrotService:_restoreBrainrotState(brainrotData, placedBrainrots, productionState, snapshot)
	self:_requireStateStore():Restore(brainrotData, placedBrainrots, productionState, snapshot)
end

function BrainrotService:CreatePlayerStateSnapshot(player)
	local _playerData, brainrotData, placedBrainrots, productionState = self:_getOrCreateDataContainers(player)
	if not (brainrotData and type(placedBrainrots) == "table" and type(productionState) == "table") then
		return nil
	end

	return self:_snapshotBrainrotState(brainrotData, placedBrainrots, productionState)
end

function BrainrotService:RestorePlayerStateSnapshot(player, snapshot)
	if not (player and type(snapshot) == "table") then
		return false
	end

	local _playerData, brainrotData, placedBrainrots, productionState = self:_getOrCreateDataContainers(player)
	if not (brainrotData and type(placedBrainrots) == "table" and type(productionState) == "table") then
		return false
	end

	self:_restoreBrainrotState(brainrotData, placedBrainrots, productionState, snapshot)

	local equippedInstanceId = math.max(0, math.floor(tonumber(brainrotData.EquippedInstanceId) or 0))
	if player.Parent then
		self:_refreshBrainrotTools(player)
		brainrotData.EquippedInstanceId = equippedInstanceId
		if equippedInstanceId > 0 then
			task.defer(function()
				self:_equipBrainrotToolByInstanceId(player, equippedInstanceId)
			end)
		end
	end

	self:_refreshAllClaimUi(player, placedBrainrots, productionState)
	self:_refreshAllBrandUi(player, placedBrainrots)
	self:_refreshAllPlatformPrompts(player, placedBrainrots)
	self:_updatePlayerTotalProductionSpeed(player, placedBrainrots)
	self:PushBrainrotState(player)
	return true
end

function BrainrotService:_shouldDeferOfflineOwnerMutation(pending, ownerData)
	local createdAt = normalizeTimestamp(pending and pending.CreatedAt)
	if createdAt > 0 and (os.time() - createdAt) < getStealOfflineOwnerGraceSeconds() then
		return true, "GraceWindow"
	end

	local pendingOwnerLastLoginAt = normalizeTimestamp(pending and pending.OwnerLastLoginAt)
	local storedLastLoginAt, storedLastLogoutAt = getPlayerMetaSessionTimestamps(ownerData)
	if pendingOwnerLastLoginAt > 0 and storedLastLoginAt > pendingOwnerLastLoginAt then
		return true, "OwnerJoinedAnotherServer"
	end

	if createdAt > 0 and storedLastLogoutAt < createdAt then
		return true, "OwnerSessionNotClosed"
	end

	return false, nil
end

function BrainrotService:_isPendingStealPurchaseStale(pending)
	local createdAt = math.max(0, math.floor(tonumber(pending and pending.CreatedAt) or 0))
	if createdAt <= 0 then
		return false
	end

	return (os.time() - createdAt) > getStealPendingTimeoutSeconds()
end

function BrainrotService:_getPendingStealPurchase(player, allowStale)
	local _playerData, brainrotData = self:_getOrCreateDataContainers(player)
	if not brainrotData then
		return nil, nil
	end

	local userId = player.UserId
	local pending = self:_normalizePendingStealPurchase(self._pendingStealPurchaseByBuyerUserId[userId])
	if not pending then
		pending = self:_normalizePendingStealPurchase(brainrotData.PendingStealPurchase)
	end

	if not pending then
		self._pendingStealPurchaseByBuyerUserId[userId] = nil
		self:_writePendingStealPurchase(brainrotData, nil)
		return nil, brainrotData
	end

	if allowStale ~= true and self:_isPendingStealPurchaseStale(pending) then
		self._pendingStealPurchaseByBuyerUserId[userId] = nil
		self:_writePendingStealPurchase(brainrotData, nil)
		return nil, brainrotData
	end

	self._pendingStealPurchaseByBuyerUserId[userId] = pending
	self:_writePendingStealPurchase(brainrotData, pending)
	return pending, brainrotData
end

function BrainrotService:_setPendingStealPurchase(player, pending)
	local _playerData, brainrotData = self:_getOrCreateDataContainers(player)
	if not brainrotData then
		return nil
	end

	local normalizedPending = self:_normalizePendingStealPurchase(pending)
	if not normalizedPending then
		return nil
	end

	self._pendingStealPurchaseByBuyerUserId[player.UserId] = normalizedPending
	self:_writePendingStealPurchase(brainrotData, normalizedPending)
	return normalizedPending, brainrotData
end

function BrainrotService:_clearPendingStealPurchase(player, expectedRequestId)
	local _playerData, brainrotData = self:_getOrCreateDataContainers(player)
	if not brainrotData then
		self._pendingStealPurchaseByBuyerUserId[player.UserId] = nil
		return
	end

	local currentPending = self:_normalizePendingStealPurchase(brainrotData.PendingStealPurchase)
	if expectedRequestId and expectedRequestId ~= "" then
		local cachedPending = self:_normalizePendingStealPurchase(self._pendingStealPurchaseByBuyerUserId[player.UserId])
		local currentRequestId = currentPending and currentPending.RequestId or (cachedPending and cachedPending.RequestId) or ""
		if currentRequestId ~= expectedRequestId then
			return
		end
	end

	self._pendingStealPurchaseByBuyerUserId[player.UserId] = nil
	self:_writePendingStealPurchase(brainrotData, nil)
end

function BrainrotService:_rebuildBrainrotStealProductIdLookup()
	self._brainrotStealProductIds = {}
	for _, developerProduct in pairs(BrainrotConfig.DeveloperProducts or {}) do
		local productId = math.max(0, math.floor(tonumber(type(developerProduct) == "table" and developerProduct.ProductId or 0) or 0))
		if productId > 0 then
			self._brainrotStealProductIds[productId] = true
		end
	end
end

function BrainrotService:_isBrainrotStealProductId(productId)
	local parsedProductId = math.max(0, math.floor(tonumber(productId) or 0))
	return self._brainrotStealProductIds[parsedProductId] == true
end

function BrainrotService:_pushBrainrotStealFeedback(player, status, payload)
	if not (player and self._brainrotStealFeedbackEvent) then
		return
	end

	local normalizedPayload = type(payload) == "table" and payload or {}
	self._brainrotStealFeedbackEvent:FireClient(player, {
		status = tostring(status or normalizedPayload.status or "Unknown"),
		message = tostring(normalizedPayload.message or ""),
		requestId = tostring(normalizedPayload.requestId or ""),
		productId = math.max(0, math.floor(tonumber(normalizedPayload.productId) or 0)),
		brainrotId = math.max(0, math.floor(tonumber(normalizedPayload.brainrotId) or 0)),
		brainrotName = tostring(normalizedPayload.brainrotName or ""),
		timestamp = os.clock(),
	})
end

function BrainrotService:_pushStealTip(ownerPlayer, thiefPlayerName, brainrotName)
	if not (ownerPlayer and self._stealTipEvent) then
		return
	end

	self._stealTipEvent:FireClient(ownerPlayer, {
		message = string.format("[%s] steal your [%s]!", tostring(thiefPlayerName or "Someone"), tostring(brainrotName or "Brainrot")),
		timestamp = os.clock(),
	})
end

function BrainrotService:_promptBrainrotStealPurchase(player, pending)
	if not (player and self._promptBrainrotStealPurchaseEvent and pending) then
		return false
	end

	self._promptBrainrotStealPurchaseEvent:FireClient(player, {
		requestId = pending.RequestId,
		productId = pending.ProductId,
		brainrotId = pending.BrainrotId,
		brainrotName = pending.BrainrotName,
		ownerUserId = pending.OwnerUserId,
		ownerName = pending.OwnerName,
		priceRobux = pending.PriceRobux,
		quality = pending.Quality,
		timestamp = os.clock(),
	})
	return true
end

function BrainrotService:_handleRequestBrainrotStealPurchaseClosed(player, payload)
	if not player then
		return
	end

	local requestId = ""
	local isPurchased = false
	if type(payload) == "table" then
		requestId = tostring(payload.requestId or "")
		isPurchased = payload.isPurchased == true
	end

	if isPurchased then
		return
	end

	self:_clearPendingStealPurchase(player, requestId)
	self:_pushBrainrotStealFeedback(player, "Cancelled", {
		requestId = requestId,
		message = "",
	})
end

function BrainrotService:_processBrainrotStealReceipt(receiptInfo)
	local productId = math.max(0, math.floor(tonumber(receiptInfo and receiptInfo.ProductId) or 0))
	if not self:_isBrainrotStealProductId(productId) then
		return false, nil
	end

	local buyerPlayer = Players:GetPlayerByUserId(math.max(0, math.floor(tonumber(receiptInfo and receiptInfo.PlayerId) or 0)))
	if not buyerPlayer then
		return true, Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local _buyerPlayerData, buyerBrainrotData = self:_getOrCreateDataContainers(buyerPlayer)
	if not buyerBrainrotData then
		return true, Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseId = tostring(receiptInfo and receiptInfo.PurchaseId or "")
	local processedPurchaseIds = self:_getOrCreateProcessedStealPurchaseIds(buyerBrainrotData)
	if purchaseId ~= "" and processedPurchaseIds[purchaseId] then
		return true, Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local pending = self:_getPendingStealPurchase(buyerPlayer, true)
	if not pending or pending.ProductId ~= productId then
		warn(string.format("[BrainrotService] received unmatched steal receipt buyer=%d productId=%d", buyerPlayer.UserId, productId))
		return true, Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ownerPlayer = Players:GetPlayerByUserId(pending.OwnerUserId)
	local wasReplacementGrant = true
	if ownerPlayer then
		local _ownerPlayerData, ownerBrainrotData, ownerPlacedBrainrots, ownerProductionState = self:_getOrCreateDataContainers(ownerPlayer)
		if not ownerBrainrotData or not ownerPlacedBrainrots or not ownerProductionState then
			return true, Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local ownerSnapshot = self:_snapshotBrainrotState(ownerBrainrotData, ownerPlacedBrainrots, ownerProductionState)
		local removeSuccess, _removeReason, removeResult = self:_consumeBrainrotInstanceFromDataContainers(ownerBrainrotData, ownerPlacedBrainrots, ownerProductionState, pending.InstanceId, "Stolen")
		wasReplacementGrant = not removeSuccess
		if removeSuccess then
			local ownerSaveSucceeded = self._playerDataService and self._playerDataService:SavePlayerData(ownerPlayer)
			if not ownerSaveSucceeded then
				self:_restoreBrainrotState(ownerBrainrotData, ownerPlacedBrainrots, ownerProductionState, ownerSnapshot)
				warn(string.format("[BrainrotService] failed to save owner steal removal owner=%d productId=%d", ownerPlayer.UserId, productId))
				return true, Enum.ProductPurchaseDecision.NotProcessedYet
			end

			self:_applyConsumedBrainrotMutation(ownerPlayer, ownerBrainrotData, ownerPlacedBrainrots, ownerProductionState, removeResult)
			self:_pushStealTip(ownerPlayer, buyerPlayer.Name, pending.BrainrotName)
		end
	elseif self._playerDataService and type(self._playerDataService.LoadStoredDataByUserId) == "function" and type(self._playerDataService.SaveStoredDataByUserId) == "function" then
		local ownerData, loadReason = self._playerDataService:LoadStoredDataByUserId(pending.OwnerUserId)
		if not ownerData then
			warn(string.format("[BrainrotService] failed to load offline owner data owner=%d productId=%d reason=%s", pending.OwnerUserId, productId, tostring(loadReason)))
			return true, Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local shouldDefer, deferReason = self:_shouldDeferOfflineOwnerMutation(pending, ownerData)
		if shouldDefer then
			warn(string.format("[BrainrotService] deferring offline owner steal mutation owner=%d buyer=%d productId=%d reason=%s", pending.OwnerUserId, buyerPlayer.UserId, productId, tostring(deferReason)))
			return true, Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local _ownerPlayerData, ownerBrainrotData, ownerPlacedBrainrots, ownerProductionState = self:_getOrCreateDataContainersFromPlayerData(ownerData)
		if not ownerBrainrotData or not ownerPlacedBrainrots or not ownerProductionState then
			return true, Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local removeSuccess = self:_consumeBrainrotInstanceFromDataContainers(ownerBrainrotData, ownerPlacedBrainrots, ownerProductionState, pending.InstanceId, "Stolen")
		wasReplacementGrant = not removeSuccess
		if removeSuccess then
			local saveSuccess, saveReason = self._playerDataService:SaveStoredDataByUserId(pending.OwnerUserId, ownerData)
			if not saveSuccess then
				warn(string.format("[BrainrotService] failed to save offline owner data owner=%d productId=%d reason=%s", pending.OwnerUserId, productId, tostring(saveReason)))
				return true, Enum.ProductPurchaseDecision.NotProcessedYet
			end
		end
	end

	local buyerBrainrotSnapshot = deepCopy(buyerBrainrotData)
	local grantSuccess, grantReason, grantResult = self:_grantBrainrotInstanceToData(buyerBrainrotData, pending.BrainrotId, pending.Level, "Steal")
	if not grantSuccess then
		warn(string.format("[BrainrotService] failed to grant stolen brainrot buyer=%d productId=%d reason=%s", buyerPlayer.UserId, productId, tostring(grantReason)))
		return true, Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if purchaseId ~= "" then
		processedPurchaseIds[purchaseId] = os.time()
	end
	self:_writePendingStealPurchase(buyerBrainrotData, nil)

	local buyerSaveSucceeded = self._playerDataService and self._playerDataService:SavePlayerData(buyerPlayer)
	if not buyerSaveSucceeded then
		replaceTableContents(buyerBrainrotData, buyerBrainrotSnapshot)
		warn(string.format("[BrainrotService] failed to save buyer steal grant buyer=%d productId=%d", buyerPlayer.UserId, productId))
		return true, Enum.ProductPurchaseDecision.NotProcessedYet
	end

	self._pendingStealPurchaseByBuyerUserId[buyerPlayer.UserId] = nil
	self:_applyGrantedBrainrotMutation(buyerPlayer, grantResult)
	self:_pushGrantedBrainrotFeedback(buyerPlayer, grantResult, "Steal")
	self:_pushBrainrotStealFeedback(buyerPlayer, "Success", {
		requestId = pending.RequestId,
		productId = pending.ProductId,
		brainrotId = pending.BrainrotId,
		brainrotName = pending.BrainrotName,
		message = "",
		wasReplacement = wasReplacementGrant,
		grantedInstanceId = type(grantResult) == "table" and grantResult.instanceId or 0,
	})

	return true, Enum.ProductPurchaseDecision.PurchaseGranted
end

function BrainrotService:_getOrCreateUnlockedBrainrotMap(brainrotData)
	return self:_requireInventoryService():GetOrCreateUnlockedBrainrotMap(brainrotData)
end

function BrainrotService:_markBrainrotUnlocked(brainrotData, brainrotId)
	return self:_requireInventoryService():MarkBrainrotUnlocked(brainrotData, brainrotId)
end

function BrainrotService:_syncUnlockedBrainrots(brainrotData, placedBrainrots)
	return self:_requireInventoryService():SyncUnlockedBrainrots(brainrotData, placedBrainrots)
end

function BrainrotService:_buildUnlockedBrainrotPayload(brainrotData, placedBrainrots)
	local unlockedMap = self:_syncUnlockedBrainrots(brainrotData, placedBrainrots)
	local unlockedBrainrotIds = {}
	local discoveredCount = 0
	local discoverableCount = 0

	for _, brainrotDefinition in ipairs(BrainrotConfig.Entries) do
		local parsedBrainrotId = math.floor(tonumber(brainrotDefinition.Id) or 0)
		if parsedBrainrotId > 0 then
			discoverableCount += 1
			if unlockedMap[tostring(parsedBrainrotId)] == true then
				discoveredCount += 1
			end
		end
	end

	for brainrotIdText, unlocked in pairs(unlockedMap) do
		local parsedBrainrotId = math.floor(tonumber(brainrotIdText) or 0)
		if unlocked == true and parsedBrainrotId > 0 and BrainrotConfig.ById[parsedBrainrotId] then
			table.insert(unlockedBrainrotIds, parsedBrainrotId)
		end
	end

	table.sort(unlockedBrainrotIds)
	return unlockedBrainrotIds, discoveredCount, discoverableCount
end

function BrainrotService:_getOrCreateProductionSlot(productionState, positionKey)
	return self:_requirePlacementService():GetOrCreateProductionSlot(productionState, positionKey)
end

function BrainrotService:_resetProductionSlotValues(slot)
	self:_requirePlacementService():ResetProductionSlotValues(slot)
end

function BrainrotService:_collectProductionBonusRates(player)
	local rates = {}

	local friendBonusPercent = 0
	if self._friendBonusService then
		friendBonusPercent = math.max(0, math.floor(tonumber(self._friendBonusService:GetBonusPercent(player)) or 0))
	end

	if friendBonusPercent > 0 then
		table.insert(rates, {
			Source = "FriendBonus",
			Rate = friendBonusPercent / 100,
		})
	end

	local rebirthBonusRate = math.max(0, tonumber(player:GetAttribute("RebirthBonusRate")) or 0)
	if rebirthBonusRate > 0 then
		table.insert(rates, {
			Source = "Rebirth",
			Rate = rebirthBonusRate,
		})
	end

	local vipBonusRate = math.max(0, tonumber(player:GetAttribute("VipProductionBonusRate")) or 0)
	if vipBonusRate > 0 then
		table.insert(rates, {
			Source = "VIP",
			Rate = vipBonusRate,
		})
	end

	local extraBonusPercent = math.max(0, tonumber(player:GetAttribute("ExtraProductionBonusPercent")) or 0)
	if extraBonusPercent > 0 then
		table.insert(rates, {
			Source = "ExtraProductionBonus",
			Rate = extraBonusPercent / 100,
		})
	end

	return rates
end

function BrainrotService:_resolveProductionMultiplier(player)
	local totalBonusRate = 0
	for _, bonusInfo in ipairs(self:_collectProductionBonusRates(player)) do
		totalBonusRate += math.max(0, tonumber(bonusInfo.Rate) or 0)
	end

	return 1 + totalBonusRate, totalBonusRate
end

function BrainrotService:_resolveOfflineProductionMultiplier(player)
	local rebirthBonusRate = math.max(0, tonumber(player:GetAttribute("RebirthBonusRate")) or 0)
	local vipBonusRate = math.max(0, tonumber(player:GetAttribute("VipProductionBonusRate")) or 0)
	return 1 + rebirthBonusRate + vipBonusRate
end

function BrainrotService:_computePlacedBaseProductionSpeed(placedBrainrots)
	return self:_requirePlacementService():ComputePlacedBaseProductionSpeed(placedBrainrots)
end

function BrainrotService:_updatePlayerTotalProductionSpeed(player, placedBrainrots)
	if not player then
		return 0, 1, 0
	end

	local resolvedPlacedBrainrots = placedBrainrots
	if type(resolvedPlacedBrainrots) ~= "table" then
		local _playerData, _brainrotData
		_playerData, _brainrotData, resolvedPlacedBrainrots = self:_getOrCreateDataContainers(player)
	end

	local baseSpeed = self:_computePlacedBaseProductionSpeed(resolvedPlacedBrainrots)
	local multiplier, totalBonusRate = self:_resolveProductionMultiplier(player)
	local finalSpeed = roundBrainrotEconomicValue(baseSpeed * multiplier)

	player:SetAttribute("TotalProductionSpeedBase", baseSpeed)
	player:SetAttribute("TotalProductionBonusRate", totalBonusRate)
	player:SetAttribute("TotalProductionMultiplier", multiplier)
	player:SetAttribute("TotalProductionSpeed", finalSpeed)

	return baseSpeed, multiplier, finalSpeed
end

function BrainrotService:_ensureStarterInventory(playerData, brainrotData, placedBrainrots)
	local _unusedPlayerData = playerData
	self:_requireInventoryService():EnsureStarterInventory(brainrotData, placedBrainrots)
end

function BrainrotService:_createToolHandle(_brainrotDefinition)
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

function BrainrotService:_findToolVisualSource(template, preferredModelName)
	if not template then
		return nil
	end

	if template:IsA("Tool") then
		if type(preferredModelName) == "string" and preferredModelName ~= "" then
			local directPreferred = template:FindFirstChild(preferredModelName)
			if directPreferred and (directPreferred:IsA("Model") or directPreferred:IsA("BasePart")) then
				return directPreferred
			end

			local nestedPreferred = template:FindFirstChild(preferredModelName, true)
			if nestedPreferred and (nestedPreferred:IsA("Model") or nestedPreferred:IsA("BasePart")) then
				return nestedPreferred
			end
		end

		local directSameName = template:FindFirstChild(template.Name)
		if directSameName and (directSameName:IsA("Model") or directSameName:IsA("BasePart")) then
			return directSameName
		end

		local nestedSameName = template:FindFirstChild(template.Name, true)
		if nestedSameName and (nestedSameName:IsA("Model") or nestedSameName:IsA("BasePart")) then
			return nestedSameName
		end

		for _, child in ipairs(template:GetChildren()) do
			if child:IsA("Model") or child:IsA("BasePart") then
				if not (child:IsA("BasePart") and child.Name == "Handle") then
					return child
				end
			end
		end
	elseif template:IsA("Model") then
		return template
	elseif template:IsA("BasePart") then
		return nil
	end

	return nil
end

function BrainrotService:_attachToolVisual(tool, brainrotDefinition, handle)
	if not tool or not handle then
		return
	end

	local template = self:_getBrainrotModelTemplate(brainrotDefinition.ModelPath)
	if not template then
		return
	end

	local _qualityFolderName, preferredModelName = parseModelPath(brainrotDefinition.ModelPath)
	local visualSource = self:_findToolVisualSource(template, preferredModelName)
	if not visualSource then
		return
	end

	local targetVisualPivotCFrame = handle.CFrame
	if template:IsA("Tool") then
		local templateHandle = getTemplateToolHandlePart(template)
		local sourcePivotCFrame = getInstancePivotCFrame(visualSource)
		if templateHandle and sourcePivotCFrame then
			local relativeOffset = templateHandle.CFrame:ToObjectSpace(sourcePivotCFrame)
			targetVisualPivotCFrame = handle.CFrame * relativeOffset
		end
	end

	local visualClone = visualSource:Clone()
	visualClone.Name = "VisualModel"
	visualClone.Parent = tool

	if visualClone:IsA("Model") then
		local modelPrimary = visualClone.PrimaryPart or visualClone:FindFirstChildWhichIsA("BasePart", true)
		if modelPrimary then
			visualClone.PrimaryPart = modelPrimary
			visualClone:PivotTo(targetVisualPivotCFrame)
		end
	elseif visualClone:IsA("BasePart") then
		visualClone.CFrame = targetVisualPivotCFrame
	end

	local visualParts = {}

	if visualClone:IsA("BasePart") then
		table.insert(visualParts, visualClone)
	end

	for _, descendant in ipairs(visualClone:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(visualParts, descendant)
		elseif descendant:IsA("ProximityPrompt") then
			descendant.Enabled = false
		elseif descendant:IsA("JointInstance") or descendant:IsA("Constraint") then
			descendant:Destroy()
		elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant.Disabled = true
		end
	end

	for _, visualPart in ipairs(visualParts) do
		setToolVisualPart(visualPart)
		if visualPart ~= handle then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = visualPart
			weld.Parent = visualPart
		end
	end
end

function BrainrotService:_attachWorldCarryVisual(tool, brainrotDefinition, handle)
	if not (tool and handle and type(brainrotDefinition) == "table") then
		return false
	end

	local visualModel = self:_createWorldSpawnModelAtCFrame(brainrotDefinition, CFrame.new())
	if not visualModel then
		return false
	end

	visualModel.Name = "VisualModel"
	visualModel.Parent = tool

	local config = self:_getWorldSpawnConfig()
	local carryRotation = config.carryGripRotation or Vector3.new(0, 0, -90)
	local targetPivot = handle.CFrame * CFrame.Angles(
		math.rad(carryRotation.X),
		math.rad(carryRotation.Y),
		math.rad(carryRotation.Z)
	)
	local modelPrimary = visualModel.PrimaryPart or visualModel:FindFirstChildWhichIsA("BasePart", true)
	if modelPrimary then
		visualModel.PrimaryPart = modelPrimary
		visualModel:PivotTo(targetPivot)
	end

	local visualParts = {}
	for _, descendant in ipairs(visualModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(visualParts, descendant)
		elseif descendant:IsA("ProximityPrompt") or descendant:IsA("BillboardGui") then
			descendant:Destroy()
		elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant.Disabled = true
		end
	end

	local directInfoAttachment = visualModel:FindFirstChild(tostring(GameConfig.BRAINROT.InfoAttachmentName or "Info"), true)
	if directInfoAttachment and directInfoAttachment:IsA("Attachment") then
		for _, child in ipairs(directInfoAttachment:GetChildren()) do
			if child:IsA("BillboardGui") then
				child:Destroy()
			end
		end
	end

	for _, visualPart in ipairs(visualParts) do
		visualPart.Anchored = false
		setToolVisualPart(visualPart)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = visualPart
		weld.Parent = visualPart
	end

	return true
end

function BrainrotService:_onToolEquipped(player, tool)
	local _playerData, brainrotData = self:_getOrCreateDataContainers(player)
	if not brainrotData then
		return
	end

	local config = self:_getWorldSpawnConfig()
	if tool:GetAttribute(config.temporaryCarryAttributeName) ~= true then
		local carryList = self._carriedWorldBrainrotByUserId[player.UserId]
		if type(carryList) == "table" and #carryList > 0 then
			local rootPart = getCharacterRootPart(player.Character)
			local dropPosition = rootPart and rootPart.Position or carryList[1].LastKnownPosition
			self:_dropCarriedWorldBrainrot(player, "EquippedOwnedBrainrot", dropPosition)
		end
	end

	brainrotData.EquippedInstanceId = tonumber(tool:GetAttribute("BrainrotInstanceId")) or 0
	self:PushBrainrotState(player)
end

function BrainrotService:_onToolUnequipped(player, tool)
	local _playerData, brainrotData = self:_getOrCreateDataContainers(player)
	if not brainrotData then
		return
	end

	local unequippedInstanceId = tonumber(tool:GetAttribute("BrainrotInstanceId")) or 0
	if brainrotData.EquippedInstanceId == unequippedInstanceId then
		brainrotData.EquippedInstanceId = 0
		self:PushBrainrotState(player)
	end
end

function BrainrotService:_onToolActivated(player)
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:UnequipTools()
	end
end

function BrainrotService:_createBrainrotTool(player, inventoryItem)
	local brainrotId = tonumber(inventoryItem.BrainrotId)
	local instanceId = tonumber(inventoryItem.InstanceId)
	local brainrotDefinition = brainrotId and BrainrotConfig.ById[brainrotId] or nil
	if not brainrotDefinition or not instanceId then
		return nil
	end

	local tool = Instance.new("Tool")
	tool.Name = brainrotDefinition.Name
	tool.CanBeDropped = false
	tool.TextureId = brainrotDefinition.Icon or ""
	tool.RequiresHandle = true
	tool.ManualActivationOnly = true
	tool:SetAttribute("BrainrotTool", true)
	tool:SetAttribute("BrainrotId", brainrotId)
	tool:SetAttribute("BrainrotInstanceId", instanceId)
	tool:SetAttribute("BrainrotModelPath", brainrotDefinition.ModelPath)

	local handle = self:_createToolHandle(brainrotDefinition)
	handle.Parent = tool
	self:_attachToolVisual(tool, brainrotDefinition, handle)

	local userId = player.UserId
	local connectionList = ensureTable(self._toolConnectionsByUserId, userId)
	table.insert(connectionList, tool.Equipped:Connect(function()
		self:_onToolEquipped(player, tool)
	end))
	table.insert(connectionList, tool.Unequipped:Connect(function()
		self:_onToolUnequipped(player, tool)
	end))
	table.insert(connectionList, tool.Activated:Connect(function()
		self:_onToolActivated(player)
	end))

	return tool
end

function BrainrotService:_removeBrainrotTools(player)
	local backpack = player:FindFirstChild("Backpack")
	local character = player.Character

	local containers = { backpack, character }
	for _, container in ipairs(containers) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") and child:GetAttribute("BrainrotTool") then
					child:Destroy()
				end
			end
		end
	end
end

function BrainrotService:_refreshBrainrotTools(player)
	self:_clearToolConnections(player)
	self:_removeBrainrotTools(player)

	local _playerData, brainrotData = self:_getOrCreateDataContainers(player)
	if not brainrotData then
		return
	end

	brainrotData.EquippedInstanceId = 0
	local backpack = player:FindFirstChild("Backpack") or player:WaitForChild("Backpack")

	table.sort(brainrotData.Inventory, function(a, b)
		return (tonumber(a.InstanceId) or 0) < (tonumber(b.InstanceId) or 0)
	end)

	for _, inventoryItem in ipairs(brainrotData.Inventory) do
		local tool = self:_createBrainrotTool(player, inventoryItem)
		if tool then
			tool.Parent = backpack
		end
	end
end

function BrainrotService:_findBrainrotToolByInstanceId(player, instanceId)
	local targetInstanceId = tonumber(instanceId)
	if not targetInstanceId then
		return nil
	end

	local backpack = player and player:FindFirstChild("Backpack") or nil
	local character = player and player.Character or nil
	for _, container in ipairs({ backpack, character }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") and child:GetAttribute("BrainrotTool") and tonumber(child:GetAttribute("BrainrotInstanceId")) == targetInstanceId then
					return child
				end
			end
		end
	end

	return nil
end

function BrainrotService:_equipBrainrotToolByInstanceId(player, instanceId)
	local tool = self:_findBrainrotToolByInstanceId(player, instanceId)
	if not tool then
		return false
	end

	local character = player and player.Character or nil
	local humanoid = character and character:FindFirstChildOfClass("Humanoid") or nil
	if not humanoid then
		return false
	end

	humanoid:EquipTool(tool)
	return true
end

function BrainrotService:GetEquippedGiftBrainrotInfo(player)
	local equippedTool = self:_getEquippedBrainrotTool(player)
	if not equippedTool then
		return nil
	end

	local instanceId = math.max(0, math.floor(tonumber(equippedTool:GetAttribute("BrainrotInstanceId")) or 0))
	local brainrotId = math.max(0, math.floor(tonumber(equippedTool:GetAttribute("BrainrotId")) or 0))
	if instanceId <= 0 or brainrotId <= 0 then
		return nil
	end

	local _playerData, brainrotData = self:_getOrCreateDataContainers(player)
	if not brainrotData then
		return nil
	end

	local inventoryIndex = findInventoryIndexByInstanceId(brainrotData.Inventory, instanceId)
	if not inventoryIndex then
		return nil
	end

	local inventoryItem = brainrotData.Inventory[inventoryIndex]
	local brainrotDefinition = BrainrotConfig.ById[brainrotId]
	if not (inventoryItem and brainrotDefinition) then
		return nil
	end

	return {
		instanceId = instanceId,
		brainrotId = brainrotId,
		brainrotName = tostring(brainrotDefinition.Name or equippedTool.Name or "Brainrot"),
		level = normalizeBrainrotLevel(inventoryItem.Level),
	}
end

function BrainrotService:TransferBrainrotInstance(senderPlayer, recipientPlayer, instanceId, reason)
	if not (senderPlayer and recipientPlayer) then
		return false, "InvalidPlayers", nil
	end

	if senderPlayer == recipientPlayer or senderPlayer.UserId == recipientPlayer.UserId then
		return false, "CannotGiftSelf", nil
	end

	local _senderPlayerData, senderBrainrotData = self:_getOrCreateDataContainers(senderPlayer)
	local _recipientPlayerData, recipientBrainrotData = self:_getOrCreateDataContainers(recipientPlayer)
	if not senderBrainrotData or not recipientBrainrotData then
		return false, "PlayerDataNotReady", nil
	end

	local inventoryService = self:_requireInventoryService()
	local success, resolvedReason, result = inventoryService:TransferBrainrotInstanceData(
		senderBrainrotData,
		recipientBrainrotData,
		instanceId,
		reason
	)
	if not success then
		return false, resolvedReason, result
	end

	self:_refreshBrainrotTools(senderPlayer)
	self:_refreshBrainrotTools(recipientPlayer)
	if result.reEquipInstanceId > 0 then
		task.defer(function()
			self:_equipBrainrotToolByInstanceId(senderPlayer, result.reEquipInstanceId)
		end)
	end

	self:PushBrainrotState(senderPlayer)
	self:PushBrainrotState(recipientPlayer)

	return true, resolvedReason, result
end

function BrainrotService:_grantBrainrotInstanceToData(brainrotData, brainrotId, level, reason)
	return self:_requireInventoryService():GrantBrainrotInstanceToData(brainrotData, brainrotId, level, reason)
end

function BrainrotService:_applyGrantedBrainrotMutation(player, grantResult)
	if not player then
		return
	end

	local inventoryItem = type(grantResult) == "table" and grantResult.inventoryItem or nil
	local instanceId = math.max(0, math.floor(tonumber(inventoryItem and inventoryItem.InstanceId) or 0))
	local backpack = player and (player:FindFirstChild("Backpack") or player:WaitForChild("Backpack", 2)) or nil
	if backpack and inventoryItem and instanceId > 0 and not self:_findBrainrotToolByInstanceId(player, instanceId) then
		local tool = self:_createBrainrotTool(player, inventoryItem)
		if tool then
			tool.Parent = backpack
		end
	end

	self:PushBrainrotState(player)
end

function BrainrotService:GrantBrainrotInstance(player, brainrotId, level, reason)
	local _playerData, brainrotData = self:_getOrCreateDataContainers(player)
	if not brainrotData then
		return false, "PlayerDataNotReady", nil
	end

	local success, resolvedReason, result = self:_grantBrainrotInstanceToData(brainrotData, brainrotId, level, reason)
	if not success then
		return success, resolvedReason, result
	end

	self:_applyGrantedBrainrotMutation(player, result)
	self:_pushGrantedBrainrotFeedback(player, result, resolvedReason)
	return success, resolvedReason, result
end

function BrainrotService:_consumeBrainrotInstanceFromDataContainers(brainrotData, placedBrainrots, productionState, instanceId, reason)
	return self:_requireInventoryService():ConsumeBrainrotInstanceFromDataContainers(brainrotData, placedBrainrots, productionState, instanceId, reason)
end

function BrainrotService:_applyConsumedBrainrotMutation(player, brainrotData, placedBrainrots, productionState, result)
	if not player then
		return
	end

	if result and result.source == "Placed" then
		self:_destroyRuntimePlacedAtPosition(player, result.positionKey)
		self:_refreshClaimUiForPosition(player, result.positionKey, placedBrainrots, productionState)
		self:_refreshBrandUiForPosition(player, result.positionKey, placedBrainrots)
		self:_refreshPlatformPromptState(player, result.positionKey, placedBrainrots)
		self:_updatePlayerTotalProductionSpeed(player, placedBrainrots)
	else
		local targetInstanceId = math.max(0, math.floor(tonumber(result and result.instanceId) or 0))
		local previousEquippedInstanceId = result and result.source == "Equipped" and targetInstanceId or 0
		local reEquipInstanceId = 0
		if previousEquippedInstanceId <= 0 then
			local currentEquippedInstanceId = math.max(0, math.floor(tonumber(brainrotData and brainrotData.EquippedInstanceId) or 0))
			if currentEquippedInstanceId > 0 and currentEquippedInstanceId ~= targetInstanceId then
				if findInventoryIndexByInstanceId(brainrotData.Inventory, currentEquippedInstanceId) then
					reEquipInstanceId = currentEquippedInstanceId
				end
			end
		end

		self:_refreshBrainrotTools(player)
		if reEquipInstanceId > 0 then
			task.defer(function()
				self:_equipBrainrotToolByInstanceId(player, reEquipInstanceId)
			end)
		end
	end

	self:PushBrainrotState(player)
end

function BrainrotService:ConsumeBrainrotInstance(player, instanceId, reason)
	local _playerData, brainrotData, placedBrainrots, productionState = self:_getOrCreateDataContainers(player)
	local success, resolvedReason, result = self:_consumeBrainrotInstanceFromDataContainers(brainrotData, placedBrainrots, productionState, instanceId, reason)
	if not success then
		return success, resolvedReason, result
	end

	self:_applyConsumedBrainrotMutation(player, brainrotData, placedBrainrots, productionState, result)
	return success, resolvedReason, result
end

function BrainrotService:GrantBrainrot(player, brainrotId, quantity, reason)
	local _playerData, brainrotData = self:_getOrCreateDataContainers(player)
	if not brainrotData then
		return false, "PlayerDataNotReady", 0
	end

	local inventoryService = self:_requireInventoryService()
	local success, resolvedReason, result = inventoryService:GrantBrainrotInstancesToData(
		brainrotData,
		brainrotId,
		quantity,
		getBaseBrainrotLevel(),
		reason
	)
	if not success then
		return false, resolvedReason, 0
	end

	local backpack = player:FindFirstChild("Backpack") or player:WaitForChild("Backpack", 2)
	for _, inventoryItem in ipairs(result.inventoryItems or {}) do
		if backpack then
			local tool = self:_createBrainrotTool(player, inventoryItem)
			if tool then
				tool.Parent = backpack
			end
		end
	end

	local grantedCount = math.max(0, math.floor(tonumber(result.grantedCount) or 0))
	if grantedCount > 0 then
		self:PushBrainrotState(player)
		self:_pushGrantedBrainrotFeedback(player, result, resolvedReason)
		return true, resolvedReason, grantedCount
	end

	return false, "GrantFailed", 0
end

function BrainrotService:_getWorldSpawnConfig()
	local config = GameConfig.BRAINROT or {}
	return {
		landFolderName = tostring(config.WorldSpawnLandFolderName or "Land"),
		runtimeFolderName = tostring(config.WorldSpawnRuntimeFolderName or "WorldSpawnedBrainrots"),
		promptName = tostring(config.WorldSpawnPromptName or "WorldBrainrotPickupPrompt"),
		promptActionText = tostring(config.WorldSpawnPromptActionText or "Pick Up"),
		promptObjectText = tostring(config.WorldSpawnPromptObjectText or "Brainrot"),
		holdDuration = math.max(0, tonumber(config.WorldSpawnPromptHoldDuration) or tonumber(config.PromptHoldDuration) or 1),
		maxActivationDistance = math.max(0, tonumber(config.WorldSpawnPromptMaxActivationDistance) or 10),
		requiresLineOfSight = config.WorldSpawnPromptRequiresLineOfSight == true,
		lifetimeMin = math.max(1, tonumber(config.WorldSpawnLifetimeMin) or 70),
		lifetimeMax = math.max(1, tonumber(config.WorldSpawnLifetimeMax) or 90),
		carryAnimationId = normalizeAnimationId(config.WorldSpawnCarryAnimationId),
		carryToolName = tostring(config.WorldSpawnCarryToolName or "WorldCarryBrainrot"),
		hideFromBackpackAttributeName = tostring(config.WorldSpawnCarryToolHideAttributeName or "HideFromCustomBackpack"),
		temporaryCarryAttributeName = tostring(config.WorldSpawnCarryToolTemporaryAttributeName or "BrainrotTemporaryCarrier"),
		carryGripRotation = typeof(config.WorldSpawnCarryGripRotationDegrees) == "Vector3" and config.WorldSpawnCarryGripRotationDegrees or Vector3.new(0, 0, -90),
		dropStates = type(config.WorldSpawnCarryDropStates) == "table" and config.WorldSpawnCarryDropStates or {},
		idleAnimationEnabled = config.WorldSpawnIdleAnimationEnabled == true,
		claimSceneFolderName = tostring(config.WorldSpawnClaimSceneFolderName or "Scene"),
		claimGroundFolderName = tostring(config.WorldSpawnClaimGroundFolderName or "Grond"),
		claimHomelandPartName = tostring(config.WorldSpawnClaimHomelandPartName or "Homeland"),
		edgePadding = math.max(0, tonumber(config.WorldSpawnPartEdgePadding) or 1),
		heightOffset = tonumber(config.WorldSpawnHeightOffset) or 0.25,
		checkInterval = math.max(0.1, tonumber(config.WorldSpawnCheckInterval) or 0.5),
		countdownUpdateInterval = math.max(0.05, tonumber(config.WorldSpawnCountdownUpdateInterval) or 0.1),
	}
end

function BrainrotService:_getBossConfig()
	local config = GameConfig.BRAINROT or {}
	local worldSpawnConfig = self:_getWorldSpawnConfig()
	return {
		runtimeFolderName = tostring(config.WorldSpawnBossRuntimeFolderName or "WorldSpawnBosses"),
		tickInterval = math.max(0.05, tonumber(config.BossTickInterval) or 0.1),
		aggroRange = math.max(0.5, tonumber(config.BossAggroRange) or 1),
		homeUnlockDelay = math.max(0, tonumber(config.BossHomeUnlockDelay) or 5),
		patrolRetargetMin = math.max(0.2, tonumber(config.BossPatrolRetargetMin) or 2.5),
		patrolRetargetMax = math.max(0.2, tonumber(config.BossPatrolRetargetMax) or 4.5),
		patrolIdleChance = math.clamp(tonumber(config.BossPatrolIdleChance) or 0.35, 0, 1),
		patrolIdleDurationMin = math.max(0, tonumber(config.BossPatrolIdleDurationMin) or 0.45),
		patrolIdleDurationMax = math.max(0, tonumber(config.BossPatrolIdleDurationMax) or 1.1),
		patrolReachedDistance = math.max(0.1, tonumber(config.BossPatrolReachedDistance) or 0.75),
		targetRefreshInterval = math.max(0.05, tonumber(config.BossTargetRefreshInterval) or 0.2),
		attackCooldown = math.max(0.1, tonumber(config.BossAttackCooldown) or 1.25),
		attackRecoveryDuration = math.max(0.05, tonumber(config.BossAttackRecoveryDuration) or 0.8),
		knockbackHorizontalMultiplier = math.max(0.1, tonumber(config.BossKnockbackHorizontalMultiplier) or 1.2),
		knockbackVerticalMultiplier = math.max(0.1, tonumber(config.BossKnockbackVerticalMultiplier) or 1.15),
		knockbackAngularMultiplier = math.max(0, tonumber(config.BossKnockbackAngularMultiplier) or 1.15),
		knockbackRagdollDuration = math.max(0, tonumber(config.BossKnockbackRagdollDuration) or 1.25),
		knockbackVelocityEnforceDuration = math.max(0, tonumber(config.BossKnockbackVelocityEnforceDuration) or 0.24),
		knockbackPlatformStandDuration = math.max(0, tonumber(config.BossKnockbackPlatformStandDuration) or 0.65),
		warningBlinkCount = math.max(1, math.floor(tonumber(config.BossWarningBlinkCount) or 3)),
		warningFadeTime = math.max(0.05, tonumber(config.BossWarningFadeTime) or 0.18),
		edgePadding = worldSpawnConfig.edgePadding,
		heightOffset = worldSpawnConfig.heightOffset,
	}
end

function BrainrotService:_getWorldSpawnBossRuntimeFolder()
	local folderName = tostring((self:_getBossConfig()).runtimeFolderName or "WorldSpawnBosses")
	local runtimeFolder = Workspace:FindFirstChild(folderName)
	if runtimeFolder and runtimeFolder:IsA("Folder") then
		return runtimeFolder
	end

	if runtimeFolder then
		runtimeFolder:Destroy()
	end

	runtimeFolder = Instance.new("Folder")
	runtimeFolder.Name = folderName
	runtimeFolder.Parent = Workspace
	return runtimeFolder
end

function BrainrotService:_groupHasBoss(groupConfig)
	if type(groupConfig) ~= "table" then
		return false
	end

	local hasBoss = groupConfig.HasBoss
	return hasBoss == true or tonumber(hasBoss) == 1
end

function BrainrotService:_getBossModelPath(groupConfig)
	local modelPath = type(groupConfig) == "table" and tostring(groupConfig.BossModelPath or "") or ""
	if modelPath == "" then
		return nil
	end

	return modelPath
end

function BrainrotService:_getBossDisplayName(groupConfig)
	local modelPath = self:_getBossModelPath(groupConfig)
	if not modelPath then
		return ""
	end

	local _categoryName, itemName = parseModelPath(modelPath)
	if type(itemName) == "string" and itemName ~= "" then
		return itemName
	end

	return modelPath
end

function BrainrotService:_getBossMoveSpeed(groupConfig)
	local explicitMoveSpeed = type(groupConfig) == "table" and tonumber(groupConfig.BossMoveSpeed) or nil
	return math.max(0.1, explicitMoveSpeed or 1)
end

function BrainrotService:_syncBossRuntimeModelAttributes(runtime, now)
	if type(runtime) ~= "table" then
		return
	end

	local model = runtime.Model
	if not (model and model.Parent) then
		return
	end

	local pivotCFrame = select(1, getInstancePivotCFrame(model))
	if not pivotCFrame then
		return
	end

	local horizontalLook = getHorizontalLookVectorFromCFrame(pivotCFrame, Vector3.new(0, 0, -1))
	model:SetAttribute(BOSS_RUNTIME_ATTRIBUTE, true)
	model:SetAttribute(BOSS_GROUP_ID_ATTRIBUTE, math.max(0, math.floor(tonumber(runtime.GroupId) or 0)))
	model:SetAttribute(BOSS_TARGET_POSITION_ATTRIBUTE, pivotCFrame.Position)
	model:SetAttribute(BOSS_TARGET_LOOK_VECTOR_ATTRIBUTE, horizontalLook)
	model:SetAttribute(BOSS_STATE_ATTRIBUTE, tostring(runtime.State or "Idle"))
	model:SetAttribute(BOSS_MOVE_SPEED_ATTRIBUTE, math.max(0.1, tonumber(runtime.MoveSpeed) or self:_getBossMoveSpeed(runtime.GroupConfig)))
	model:SetAttribute(BOSS_SERVER_UPDATED_AT_ATTRIBUTE, math.max(0, tonumber(now) or getSharedClock()))
end

function BrainrotService:_getPlayerGroupCarryFirstPickupAt(userId, groupId)
	local carryList = self._carriedWorldBrainrotByUserId[userId]
	if type(carryList) ~= "table" then
		return 0
	end

	local parsedGroupId = math.max(0, math.floor(tonumber(groupId) or 0))
	local firstPickupAt = 0
	for _, carryData in ipairs(carryList) do
		if math.max(0, math.floor(tonumber(type(carryData) == "table" and carryData.GroupId or 0) or 0)) == parsedGroupId then
			local pickedAt = math.max(0, tonumber(carryData.PickedAt) or 0)
			if pickedAt > 0 and (firstPickupAt <= 0 or pickedAt < firstPickupAt) then
				firstPickupAt = pickedAt
			end
		end
	end

	return firstPickupAt
end

function BrainrotService:_playerHasCarriedWorldBrainrotForGroup(userId, groupId)
	return self:_getPlayerGroupCarryFirstPickupAt(userId, groupId) > 0
end

function BrainrotService:_getCarriedWorldBrainrotHomeUnlockAt(carryList)
	if type(carryList) ~= "table" or #carryList <= 0 then
		return 0
	end

	local latestPickupAt = 0
	for _, carryData in ipairs(carryList) do
		local pickedAt = math.max(0, tonumber(type(carryData) == "table" and carryData.PickedAt or 0) or 0)
		if pickedAt > latestPickupAt then
			latestPickupAt = pickedAt
		end
	end

	if latestPickupAt <= 0 then
		return 0
	end

	return latestPickupAt + (self:_getBossConfig().homeUnlockDelay or 0)
end

function BrainrotService:_isAnyBossTargetingUserId(userId)
	local parsedUserId = math.max(0, math.floor(tonumber(userId) or 0))
	if parsedUserId <= 0 then
		return false
	end

	for _, runtime in pairs(self._worldSpawnBossRuntimeByGroupId) do
		if type(runtime) == "table" and math.max(0, math.floor(tonumber(runtime.TargetUserId) or 0)) == parsedUserId then
			return true
		end
	end

	return false
end

function BrainrotService:_pushBossStateSync(player)
	if not (player and self._bossStateSyncEvent) then
		return
	end

	local carryList = self._carriedWorldBrainrotByUserId[player.UserId]
	local carriedCount = type(carryList) == "table" and #carryList or 0
	local now = getSharedClock()
	local homeUnlockAt = self:_getCarriedWorldBrainrotHomeUnlockAt(carryList)
	self._bossStateSyncEvent:FireClient(player, {
		visible = carriedCount > 0,
		carriedCount = carriedCount,
		homeUnlockAt = homeUnlockAt,
		countdownRemaining = math.max(0, homeUnlockAt - now),
		canTeleportHome = carriedCount > 0 and now >= homeUnlockAt,
		isChased = self:_isAnyBossTargetingUserId(player.UserId),
		timestamp = now,
	})
end

function BrainrotService:_refreshBossCarryStateForPlayer(player)
	if not player then
		return
	end

	local carryList = self._carriedWorldBrainrotByUserId[player.UserId]
	local homeUnlockAt = self:_getCarriedWorldBrainrotHomeUnlockAt(carryList)
	if homeUnlockAt > 0 then
		player:SetAttribute(BOSS_HOME_UNLOCK_AT_ATTRIBUTE, homeUnlockAt)
	else
		player:SetAttribute(BOSS_HOME_UNLOCK_AT_ATTRIBUTE, nil)
	end

	self:_pushBossStateSync(player)
end

function BrainrotService:_pushBossWarning(player, groupId)
	if not (player and self._bossWarningEvent) then
		return
	end

	local bossConfig = self:_getBossConfig()
	self._bossWarningEvent:FireClient(player, {
		groupId = math.max(0, math.floor(tonumber(groupId) or 0)),
		blinkCount = bossConfig.warningBlinkCount,
		fadeTime = bossConfig.warningFadeTime,
		timestamp = getSharedClock(),
	})
end

function BrainrotService:_clearBossAnimationTrack(runtime)
	if type(runtime) ~= "table" then
		return
	end

	local track = runtime.AnimationTrack
	if track then
		pcall(function()
			track:Stop(0.1)
		end)
		pcall(function()
			track:Destroy()
		end)
	end

	runtime.AnimationTrack = nil
	runtime.AnimationKind = "None"
end

function BrainrotService:_loadAnimationTrackForInstance(instance, modelPath, animationId, shouldLoop, priority)
	local normalizedAnimationId = normalizeAnimationId(animationId)
	if not normalizedAnimationId or not instance then
		return nil
	end

	local animationRoot = self:_resolveIdleAnimationRoot(instance, {
		ModelPath = modelPath,
	})
	if not animationRoot then
		return nil
	end

	local animator = nil
	local humanoid = animationRoot:FindFirstChildWhichIsA("Humanoid", true)
	if humanoid then
		pcall(function()
			humanoid.PlatformStand = false
			if humanoid:GetState() == Enum.HumanoidStateType.Physics then
				humanoid:ChangeState(Enum.HumanoidStateType.Running)
			end
		end)

		animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
	else
		local animationController = animationRoot:FindFirstChildWhichIsA("AnimationController", true)
		if not animationController then
			animationController = Instance.new("AnimationController")
			animationController.Name = "BrainrotBossAnimationController"
			animationController.Parent = animationRoot
		end

		animator = animationController:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = animationController
		end
	end

	if not animator then
		return nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = normalizedAnimationId
	local ok, trackOrError = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()
	if not (ok and trackOrError) then
		return nil
	end

	local track = trackOrError
	track.Looped = shouldLoop == true
	pcall(function()
		track.Priority = priority or Enum.AnimationPriority.Movement
	end)
	track:Play(0.1)
	return track
end

function BrainrotService:_setBossAnimation(runtime, animationKind)
	if type(runtime) ~= "table" then
		return
	end

	local desiredKind = tostring(animationKind or "None")
	local currentTrack = runtime.AnimationTrack
	if desiredKind == runtime.AnimationKind and currentTrack then
		local isPlaying = false
		local ok = pcall(function()
			isPlaying = currentTrack.IsPlaying
		end)
		if ok and isPlaying then
			return
		end
	end

	self:_clearBossAnimationTrack(runtime)
	if desiredKind == "None" then
		return
	end

	local animationId = nil
	local looped = false
	local priority = Enum.AnimationPriority.Movement
	if desiredKind == "Walk" then
		animationId = runtime.WalkAnimationId
		looped = true
		priority = Enum.AnimationPriority.Movement
	elseif desiredKind == "Attack" then
		animationId = runtime.AttackAnimationId
		looped = false
		priority = Enum.AnimationPriority.Action
	end

	local track = self:_loadAnimationTrackForInstance(runtime.Model, runtime.BossModelPath, animationId, looped, priority)
	if track then
		runtime.AnimationKind = desiredKind
		runtime.AnimationTrack = track
	end
end

function BrainrotService:_clearBossInfoUi(instance)
	local infoAttachment = self:_findInfoAttachment(instance)
	if not infoAttachment then
		return
	end

	for _, child in ipairs(infoAttachment:GetChildren()) do
		if child:IsA("BillboardGui") then
			child:Destroy()
		end
	end
end

function BrainrotService:_buildBossPseudoBrainrotDefinition(groupConfig)
	local groupId = math.max(0, math.floor(tonumber(type(groupConfig) == "table" and groupConfig.Id or 0) or 0))
	return {
		Id = groupId,
		Name = string.format("%sBoss", tostring(type(groupConfig) == "table" and groupConfig.PartName or "Brainrot")),
		ModelPath = self:_getBossModelPath(groupConfig),
		Quality = 0,
		Rarity = 0,
		CoinPerSecond = 0,
	}
end

function BrainrotService:_clampBossWorldPosition(spawnPart, worldPosition, targetY)
	if not (spawnPart and spawnPart:IsA("BasePart") and typeof(worldPosition) == "Vector3") then
		return worldPosition
	end

	local edgePadding = self:_getBossConfig().edgePadding
	local localPoint = spawnPart.CFrame:PointToObjectSpace(worldPosition)
	local halfX = math.max(0, (spawnPart.Size.X * 0.5) - edgePadding)
	local halfZ = math.max(0, (spawnPart.Size.Z * 0.5) - edgePadding)
	local clampedLocal = Vector3.new(
		math.clamp(localPoint.X, -halfX, halfX),
		(targetY or worldPosition.Y) - spawnPart.Position.Y,
		math.clamp(localPoint.Z, -halfZ, halfZ)
	)
	return spawnPart.CFrame:PointToWorldSpace(clampedLocal)
end

function BrainrotService:_getRandomBossPatrolPosition(spawnPart, targetY)
	if not (spawnPart and spawnPart:IsA("BasePart")) then
		return nil
	end

	local edgePadding = self:_getBossConfig().edgePadding
	local halfX = math.max(0, (spawnPart.Size.X * 0.5) - edgePadding)
	local halfZ = math.max(0, (spawnPart.Size.Z * 0.5) - edgePadding)
	local offsetX = halfX > 0 and self._worldSpawnRng:NextNumber(-halfX, halfX) or 0
	local offsetZ = halfZ > 0 and self._worldSpawnRng:NextNumber(-halfZ, halfZ) or 0
	local localPosition = Vector3.new(offsetX, (targetY or spawnPart.Position.Y) - spawnPart.Position.Y, offsetZ)
	return spawnPart.CFrame:PointToWorldSpace(localPosition)
end

function BrainrotService:_moveBossTowards(runtime, targetWorldPosition, deltaTime)
	if type(runtime) ~= "table" or not (runtime.Model and runtime.Model.Parent) then
		return false, 0
	end

	local currentCFrame = select(1, getInstancePivotCFrame(runtime.Model))
	if not currentCFrame then
		return false, 0
	end

	local currentPosition = currentCFrame.Position
	local moveHeight = tonumber(runtime.MoveHeight) or currentPosition.Y
	local clampedTarget = self:_clampBossWorldPosition(runtime.SpawnPart, targetWorldPosition, moveHeight)
	local horizontalDirection = Vector3.new(clampedTarget.X - currentPosition.X, 0, clampedTarget.Z - currentPosition.Z)
	local distance = horizontalDirection.Magnitude
	if distance <= 0.001 then
		return true, 0
	end

	local moveSpeed = math.max(0.1, tonumber(runtime.MoveSpeed) or self:_getBossMoveSpeed(runtime.GroupConfig))
	local stepDistance = math.min(distance, moveSpeed * math.max(0, tonumber(deltaTime) or 0))
	if stepDistance <= 0 then
		return false, distance
	end

	local moveDirection = horizontalDirection.Unit
	local nextPosition = currentPosition + (moveDirection * stepDistance)
	nextPosition = Vector3.new(nextPosition.X, moveHeight, nextPosition.Z)
	local nextCFrame = CFrame.lookAt(nextPosition, nextPosition + moveDirection, Vector3.new(0, 1, 0))
	setInstancePivotCFrame(runtime.Model, nextCFrame)
	return distance <= (stepDistance + 0.01), distance
end

function BrainrotService:_createWorldSpawnBossForGroup(groupConfig)
	local groupId = math.max(0, math.floor(tonumber(type(groupConfig) == "table" and groupConfig.Id or 0) or 0))
	if groupId <= 0 then
		return nil
	end

	local spawnPart = self:_getWorldSpawnPart(groupConfig)
	local bossModelPath = self:_getBossModelPath(groupConfig)
	if not (spawnPart and bossModelPath) then
		if not self._didWarnMissingBossModelByGroupId[groupId] then
			self._didWarnMissingBossModelByGroupId[groupId] = true
			warn(string.format("[BrainrotService] Boss 配置缺失（GroupId=%d, ModelPath=%s）", groupId, tostring(bossModelPath)))
		end
		return nil
	end

	local runtimeFolder = self:_getWorldSpawnBossRuntimeFolder()
	local spawnCFrame = self:_getWorldSpawnSpawnCFrame(spawnPart)
	if not spawnCFrame then
		return nil
	end

	local tempPart = Instance.new("Part")
	tempPart.Name = "WorldSpawnBossAnchor"
	tempPart.Transparency = 1
	tempPart.CanCollide = false
	tempPart.CanTouch = false
	tempPart.CanQuery = false
	tempPart.Anchored = true
	tempPart.Size = Vector3.new(1, 1, 1)
	tempPart.CFrame = spawnCFrame
	tempPart.Parent = runtimeFolder

	local tempAttachment = Instance.new("Attachment")
	tempAttachment.Name = "WorldSpawnBossAttachment"
	tempAttachment.Parent = tempPart

	local bossDefinition = self:_buildBossPseudoBrainrotDefinition(groupConfig)
	local bossInstance = self:_createPlacedModel(tempAttachment, bossDefinition, getBaseBrainrotLevel())
	if not bossInstance then
		tempPart:Destroy()
		return nil
	end

	bossInstance.Name = string.format("WorldSpawnBoss_%d", groupId)
	bossInstance.Parent = runtimeFolder
	tempPart:Destroy()
	self:_clearBossInfoUi(bossInstance)

	local bossScale = math.max(0.1, tonumber(groupConfig.BossScale) or 1)
	if math.abs(bossScale - 1) > 0.001 then
		pcall(function()
			if bossInstance:IsA("Model") then
				bossInstance:ScaleTo(bossScale)
			elseif bossInstance:IsA("BasePart") then
				bossInstance.Size *= bossScale
			end
		end)
	end
	snapInstanceBottomToY(bossInstance, spawnCFrame.Position.Y)

	local pivotCFrame = select(1, getInstancePivotCFrame(bossInstance))
	local moveHeight = pivotCFrame and pivotCFrame.Position.Y or spawnCFrame.Position.Y
	local runtime = {
		GroupId = groupId,
		GroupConfig = groupConfig,
		SpawnPart = spawnPart,
		Model = bossInstance,
		BossModelPath = bossModelPath,
		WalkAnimationId = groupConfig.BossWalkAnimationId,
		AttackAnimationId = groupConfig.BossAttackAnimationId,
		MoveSpeed = self:_getBossMoveSpeed(groupConfig),
		MoveHeight = moveHeight,
		State = "Patrol",
		TargetUserId = 0,
		PatrolTargetPosition = nil,
		NextPatrolDecisionAt = 0,
		IdleUntil = 0,
		LastTargetRefreshAt = 0,
		AttackCooldownAt = 0,
		AttackRecoveryEndsAt = 0,
		LastTickAt = getSharedClock(),
		AnimationKind = "None",
		AnimationTrack = nil,
	}
	self:_syncBossRuntimeModelAttributes(runtime, runtime.LastTickAt)
	return runtime
end

function BrainrotService:_destroyWorldSpawnBossRuntime(groupId)
	local parsedGroupId = math.max(0, math.floor(tonumber(groupId) or 0))
	local runtime = self._worldSpawnBossRuntimeByGroupId[parsedGroupId]
	if type(runtime) ~= "table" then
		return
	end

	self:_clearBossAnimationTrack(runtime)
	if runtime.Model and runtime.Model.Parent then
		runtime.Model:Destroy()
	end
	self._worldSpawnBossRuntimeByGroupId[parsedGroupId] = nil
end

function BrainrotService:_ensureWorldSpawnBossRuntime(groupConfig)
	local groupId = math.max(0, math.floor(tonumber(type(groupConfig) == "table" and groupConfig.Id or 0) or 0))
	if groupId <= 0 or not self:_groupHasBoss(groupConfig) then
		self:_destroyWorldSpawnBossRuntime(groupId)
		return nil
	end

	local runtime = self._worldSpawnBossRuntimeByGroupId[groupId]
	if type(runtime) == "table" and runtime.Model and runtime.Model.Parent then
		runtime.GroupConfig = groupConfig
		runtime.SpawnPart = self:_getWorldSpawnPart(groupConfig) or runtime.SpawnPart
		runtime.BossModelPath = self:_getBossModelPath(groupConfig) or runtime.BossModelPath
		runtime.WalkAnimationId = groupConfig.BossWalkAnimationId
		runtime.AttackAnimationId = groupConfig.BossAttackAnimationId
		runtime.MoveSpeed = self:_getBossMoveSpeed(groupConfig)
		self:_syncBossRuntimeModelAttributes(runtime, getSharedClock())
		return runtime
	end

	self:_destroyWorldSpawnBossRuntime(groupId)
	runtime = self:_createWorldSpawnBossForGroup(groupConfig)
	if runtime then
		self._worldSpawnBossRuntimeByGroupId[groupId] = runtime
	end
	return runtime
end

function BrainrotService:_selectBossTargetForGroup(groupId)
	local bestPlayer = nil
	local bestPickupAt = 0
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if getAliveHumanoid(character) and getCharacterRootPart(character) then
			local pickupAt = self:_getPlayerGroupCarryFirstPickupAt(player.UserId, groupId)
			if pickupAt > 0 and (not bestPlayer or pickupAt < bestPickupAt or (pickupAt == bestPickupAt and player.UserId < bestPlayer.UserId)) then
				bestPlayer = player
				bestPickupAt = pickupAt
			end
		end
	end

	return bestPlayer
end

function BrainrotService:_isBossTargetValid(runtime, player)
	if type(runtime) ~= "table" or not (player and player.Parent) then
		return false
	end

	if not self:_playerHasCarriedWorldBrainrotForGroup(player.UserId, runtime.GroupId) then
		return false
	end

	local character = player.Character
	return getAliveHumanoid(character) ~= nil and getCharacterRootPart(character) ~= nil
end

function BrainrotService:_setBossTarget(runtime, player)
	if type(runtime) ~= "table" then
		return
	end

	local previousTargetUserId = math.max(0, math.floor(tonumber(runtime.TargetUserId) or 0))
	local nextTargetUserId = player and player.UserId or 0
	if previousTargetUserId == nextTargetUserId then
		return
	end

	runtime.TargetUserId = nextTargetUserId
	runtime.LastTargetRefreshAt = getSharedClock()
	runtime.PatrolTargetPosition = nil
	runtime.IdleUntil = 0
	runtime.NextPatrolDecisionAt = runtime.LastTargetRefreshAt

	local previousTargetPlayer = previousTargetUserId > 0 and Players:GetPlayerByUserId(previousTargetUserId) or nil
	if previousTargetPlayer then
		self:_pushBossStateSync(previousTargetPlayer)
	end

	if player then
		self:_pushBossWarning(player, runtime.GroupId)
		self:_pushBossStateSync(player)
	end
end

function BrainrotService:_updateBossTarget(runtime, now)
	if type(runtime) ~= "table" then
		return nil
	end

	local currentTarget = math.max(0, math.floor(tonumber(runtime.TargetUserId) or 0))
	local targetPlayer = currentTarget > 0 and Players:GetPlayerByUserId(currentTarget) or nil
	if self:_isBossTargetValid(runtime, targetPlayer) then
		return targetPlayer
	end

	local selectedPlayer = self:_selectBossTargetForGroup(runtime.GroupId)
	self:_setBossTarget(runtime, selectedPlayer)
	runtime.LastTargetRefreshAt = now
	return selectedPlayer
end

function BrainrotService:_applyBossKnockback(runtime, targetPlayer)
	if not (type(runtime) == "table" and targetPlayer) then
		return
	end

	local bossConfig = self:_getBossConfig()
	local character = targetPlayer.Character
	local humanoid = getAliveHumanoid(character)
	local targetRootPart = getCharacterRootPart(character)
	local bossCFrame = runtime.Model and select(1, getInstancePivotCFrame(runtime.Model)) or nil
	if not (humanoid and targetRootPart and bossCFrame) then
		return
	end

	local weaponConfig = GameConfig.WEAPON or {}
	local sharedHorizontalVelocity = math.max(0, tonumber(weaponConfig.KnockbackHorizontalVelocity) or 75)
	local sharedVerticalVelocity = tonumber(weaponConfig.KnockbackVerticalVelocity) or 35
	local sharedAngularVelocity = math.max(0, tonumber(weaponConfig.KnockbackAngularVelocity) or 0)
	local sharedRagdollDuration = math.max(
		0,
		tonumber(weaponConfig.KnockbackRagdollDuration) or tonumber(weaponConfig.KnockbackFallingDownDuration) or 0.75
	)
	local sharedVelocityEnforceDuration = math.max(0, tonumber(weaponConfig.KnockbackVelocityEnforceDuration) or 0.16)
	local sharedPlatformStandDuration = math.max(0, tonumber(weaponConfig.KnockbackPlatformStandDuration) or 0)
	local bossKnockbackConfig = {
		HorizontalVelocity = math.max(sharedHorizontalVelocity, sharedHorizontalVelocity * bossConfig.knockbackHorizontalMultiplier),
		VerticalVelocity = math.max(sharedVerticalVelocity, sharedVerticalVelocity * bossConfig.knockbackVerticalMultiplier),
		AngularVelocity = math.max(sharedAngularVelocity, sharedAngularVelocity * bossConfig.knockbackAngularMultiplier),
		RagdollDuration = math.max(sharedRagdollDuration, bossConfig.knockbackRagdollDuration),
		VelocityEnforceDuration = math.max(sharedVelocityEnforceDuration, bossConfig.knockbackVelocityEnforceDuration),
		PlatformStandDuration = math.max(sharedPlatformStandDuration, bossConfig.knockbackPlatformStandDuration),
	}

	local knockbackService = self._weaponKnockbackService
	if knockbackService and type(knockbackService.ApplyCharacterKnockback) == "function" then
		local ok, applied = pcall(function()
			return knockbackService:ApplyCharacterKnockback(runtime.Model, character, bossKnockbackConfig)
		end)
		if ok and applied then
			return
		end
		if not ok then
			warn(string.format("[BrainrotService] Boss knockback fallback triggered: %s", tostring(applied)))
		end
	end

	local horizontalDirection = resolveHorizontalDirection(bossCFrame.Position, targetRootPart.Position, bossCFrame.LookVector)
	local desiredVelocity = (horizontalDirection * bossKnockbackConfig.HorizontalVelocity)
		+ Vector3.new(0, bossKnockbackConfig.VerticalVelocity, 0)
	local currentVelocity = targetRootPart.AssemblyLinearVelocity

	humanoid:ChangeState(Enum.HumanoidStateType.FallingDown)
	targetRootPart.AssemblyLinearVelocity = Vector3.new(
		desiredVelocity.X,
		math.max(currentVelocity.Y, desiredVelocity.Y),
		desiredVelocity.Z
	)
	if bossKnockbackConfig.AngularVelocity > 0 then
		local tumbleAxis = Vector3.new(horizontalDirection.Z, 0, -horizontalDirection.X)
		if tumbleAxis.Magnitude <= 0.001 then
			tumbleAxis = Vector3.new(1, 0, 0)
		else
			tumbleAxis = tumbleAxis.Unit
		end
		targetRootPart.AssemblyAngularVelocity = tumbleAxis * bossKnockbackConfig.AngularVelocity
	end
end

function BrainrotService:_performBossAttack(runtime, targetPlayer, now)
	if not (type(runtime) == "table" and targetPlayer) then
		return
	end

	local bossConfig = self:_getBossConfig()
	runtime.State = "Attack"
	runtime.AttackCooldownAt = now + bossConfig.attackCooldown
	runtime.AttackRecoveryEndsAt = now + bossConfig.attackRecoveryDuration
	self:_setBossAnimation(runtime, "Attack")
	self:_applyBossKnockback(runtime, targetPlayer)

	local targetRootPart = getCharacterRootPart(targetPlayer.Character)
	local dropPosition = targetRootPart and targetRootPart.Position or nil
	self:_dropCarriedWorldBrainrot(targetPlayer, "BossAttack", dropPosition)
end

function BrainrotService:_tickBossRuntime(runtime, now, deltaTime)
	if type(runtime) ~= "table" or not (runtime.Model and runtime.Model.Parent and runtime.SpawnPart and runtime.SpawnPart.Parent) then
		return
	end

	local bossConfig = self:_getBossConfig()

	if now < (tonumber(runtime.AttackRecoveryEndsAt) or 0) then
		runtime.State = "Attack"
		return
	end

	if now - (tonumber(runtime.LastTargetRefreshAt) or 0) >= bossConfig.targetRefreshInterval or math.max(0, math.floor(tonumber(runtime.TargetUserId) or 0)) <= 0 then
		self:_updateBossTarget(runtime, now)
	end

	local targetPlayer = math.max(0, math.floor(tonumber(runtime.TargetUserId) or 0)) > 0
		and Players:GetPlayerByUserId(runtime.TargetUserId)
		or nil
	if not self:_isBossTargetValid(runtime, targetPlayer) then
		targetPlayer = nil
		self:_setBossTarget(runtime, nil)
	end

	if targetPlayer then
		local currentCFrame = select(1, getInstancePivotCFrame(runtime.Model))
		local targetRootPart = getCharacterRootPart(targetPlayer.Character)
		if currentCFrame and targetRootPart then
			local horizontalDistance = (Vector3.new(targetRootPart.Position.X, 0, targetRootPart.Position.Z)
				- Vector3.new(currentCFrame.Position.X, 0, currentCFrame.Position.Z)).Magnitude

			if horizontalDistance <= bossConfig.aggroRange and now >= (tonumber(runtime.AttackCooldownAt) or 0) then
				self:_performBossAttack(runtime, targetPlayer, now)
				return
			end

			runtime.State = "Chase"
			runtime.IdleUntil = 0
			runtime.PatrolTargetPosition = nil
			self:_setBossAnimation(runtime, "Walk")
			self:_moveBossTowards(runtime, targetRootPart.Position, deltaTime)
			return
		end
	end

	if now < (tonumber(runtime.IdleUntil) or 0) then
		runtime.State = "Idle"
		self:_setBossAnimation(runtime, "None")
		return
	end

	if not runtime.PatrolTargetPosition or now >= (tonumber(runtime.NextPatrolDecisionAt) or 0) then
		if self._worldSpawnRng:NextNumber() < bossConfig.patrolIdleChance then
			runtime.PatrolTargetPosition = nil
			runtime.IdleUntil = now + self._worldSpawnRng:NextNumber(
				bossConfig.patrolIdleDurationMin,
				math.max(bossConfig.patrolIdleDurationMin, bossConfig.patrolIdleDurationMax)
			)
			runtime.State = "Idle"
			self:_setBossAnimation(runtime, "None")
			return
		end

		runtime.IdleUntil = 0
		runtime.PatrolTargetPosition = self:_getRandomBossPatrolPosition(runtime.SpawnPart, runtime.MoveHeight)
		runtime.NextPatrolDecisionAt = now + self._worldSpawnRng:NextNumber(
			bossConfig.patrolRetargetMin,
			math.max(bossConfig.patrolRetargetMin, bossConfig.patrolRetargetMax)
		)
	end

	if runtime.PatrolTargetPosition then
		runtime.State = "Patrol"
		self:_setBossAnimation(runtime, "Walk")
		local reached = self:_moveBossTowards(runtime, runtime.PatrolTargetPosition, deltaTime)
		if reached then
			runtime.PatrolTargetPosition = nil
			runtime.NextPatrolDecisionAt = now
		end
		return
	end

	runtime.State = "Idle"
	self:_setBossAnimation(runtime, "None")
end

function BrainrotService:_refreshBossTargetsForPlayer(player)
	if not player then
		return
	end

	local now = getSharedClock()
	for _, runtime in pairs(self._worldSpawnBossRuntimeByGroupId) do
		if type(runtime) == "table" then
			if math.max(0, math.floor(tonumber(runtime.TargetUserId) or 0)) == player.UserId
				or self:_playerHasCarriedWorldBrainrotForGroup(player.UserId, runtime.GroupId) then
				self:_updateBossTarget(runtime, now)
			end
		end
	end

	self:_pushBossStateSync(player)
end

function BrainrotService:_tickWorldSpawnBosses(now)
	local activeBossGroupIds = {}
	for _, groupConfig in ipairs(BrainrotConfig.WorldSpawnGroups or {}) do
		local groupId = math.max(0, math.floor(tonumber(type(groupConfig) == "table" and groupConfig.Id or 0) or 0))
		if groupId > 0 and self:_groupHasBoss(groupConfig) then
			activeBossGroupIds[groupId] = true
			self:_ensureWorldSpawnBossRuntime(groupConfig)
		end
	end

	for groupId, runtime in pairs(self._worldSpawnBossRuntimeByGroupId) do
		if not activeBossGroupIds[groupId] then
			self:_destroyWorldSpawnBossRuntime(groupId)
		elseif type(runtime) == "table" then
			local deltaTime = math.max(0, now - (tonumber(runtime.LastTickAt) or now))
			runtime.LastTickAt = now
			self:_tickBossRuntime(runtime, now, deltaTime)
			self:_syncBossRuntimeModelAttributes(runtime, now)
		end
	end
end

function BrainrotService:_getWorldSpawnGroupConfigById(groupId)
	local parsedGroupId = math.max(0, math.floor(tonumber(groupId) or 0))
	if parsedGroupId <= 0 then
		return nil
	end

	if type(self._worldSpawnGroupConfigById[parsedGroupId]) == "table" then
		return self._worldSpawnGroupConfigById[parsedGroupId]
	end

	for _, groupConfig in ipairs(BrainrotConfig.WorldSpawnGroups or {}) do
		local currentGroupId = math.max(0, math.floor(tonumber(type(groupConfig) == "table" and groupConfig.Id or 0) or 0))
		if currentGroupId > 0 then
			self._worldSpawnGroupConfigById[currentGroupId] = groupConfig
			if currentGroupId == parsedGroupId then
				return groupConfig
			end
		end
	end

	return nil
end

function BrainrotService:_getWorldSpawnClaimPart()
	local config = self:_getWorldSpawnConfig()
	local scene = Workspace:FindFirstChild(config.claimSceneFolderName)
	local ground = scene and scene:FindFirstChild(config.claimGroundFolderName)
	local homeland = ground and ground:FindFirstChild(config.claimHomelandPartName)
	if homeland and homeland:IsA("BasePart") then
		return homeland
	end

	return nil
end

function BrainrotService:_getWorldSpawnRuntimeFolder()
	local config = self:_getWorldSpawnConfig()
	local folderName = tostring(config.runtimeFolderName or "WorldSpawnedBrainrots")
	local runtimeFolder = Workspace:FindFirstChild(folderName)
	if runtimeFolder and runtimeFolder:IsA("Folder") then
		return runtimeFolder
	end

	if runtimeFolder then
		runtimeFolder:Destroy()
	end

	runtimeFolder = Instance.new("Folder")
	runtimeFolder.Name = folderName
	runtimeFolder.Parent = Workspace
	return runtimeFolder
end

function BrainrotService:_getWorldSpawnLandFolder()
	local config = self:_getWorldSpawnConfig()
	local landFolder = Workspace:FindFirstChild(config.landFolderName)
	if landFolder then
		return landFolder
	end

	if not self._didWarnMissingWorldSpawnLand then
		self._didWarnMissingWorldSpawnLand = true
		warn(string.format("[BrainrotService] 找不到场景脑红刷新根目录: Workspace.%s", tostring(config.landFolderName)))
	end

	return nil
end

function BrainrotService:_getWorldSpawnPart(groupConfig)
	if type(groupConfig) ~= "table" then
		return nil
	end

	local partName = tostring(groupConfig.PartName or "")
	if partName == "" then
		return nil
	end

	local landFolder = self:_getWorldSpawnLandFolder()
	if not landFolder then
		return nil
	end

	local spawnPart = nil
	if string.find(partName, "/") then
		local current = landFolder
		for segment in string.gmatch(partName, "[^/]+") do
			if not current then
				break
			end
			current = current:FindFirstChild(segment)
		end
		spawnPart = current
	else
		spawnPart = landFolder:FindFirstChild(partName) or landFolder:FindFirstChild(partName, true)
	end

	if spawnPart and spawnPart:IsA("BasePart") then
		return spawnPart
	end

	if not self._didWarnMissingWorldSpawnPartByName[partName] then
		self._didWarnMissingWorldSpawnPartByName[partName] = true
		warn(string.format("[BrainrotService] 找不到场景脑红刷新区域 Part: Workspace.%s.%s", tostring(landFolder.Name), partName))
	end

	return nil
end

function BrainrotService:_getWorldSpawnSpawnCFrame(spawnPart)
	if not (spawnPart and spawnPart:IsA("BasePart")) then
		return nil
	end

	local config = self:_getWorldSpawnConfig()
	local halfX = math.max(0, (spawnPart.Size.X * 0.5) - config.edgePadding)
	local halfZ = math.max(0, (spawnPart.Size.Z * 0.5) - config.edgePadding)
	local offsetX = halfX > 0 and self._worldSpawnRng:NextNumber(-halfX, halfX) or 0
	local offsetZ = halfZ > 0 and self._worldSpawnRng:NextNumber(-halfZ, halfZ) or 0
	local worldOffset = (spawnPart.CFrame.RightVector * offsetX) + (spawnPart.CFrame.LookVector * offsetZ)
	local samplePosition = spawnPart.Position + worldOffset
	local fallbackGroundY = spawnPart.Position.Y + (spawnPart.Size.Y * 0.5)
	local groundPosition, didHitGround = resolveGroundDropPosition(samplePosition)
	groundPosition = groundPosition or samplePosition
	local targetBottomY = ((didHitGround and groundPosition.Y) or fallbackGroundY) + config.heightOffset
	local targetPosition = Vector3.new(samplePosition.X, targetBottomY, samplePosition.Z)
	local yawDegrees = self._worldSpawnRng:NextNumber(-180, 180)
	return CFrame.new(targetPosition) * CFrame.Angles(0, math.rad(yawDegrees), 0)
end

function BrainrotService:GetWorldSpawnGroupConfig(groupId)
	return self:_getWorldSpawnGroupConfigById(groupId)
end

function BrainrotService:GetWorldSpawnBossDisplayName(groupId)
	local groupConfig = self:_getWorldSpawnGroupConfigById(groupId)
	if not groupConfig then
		return ""
	end

	return self:_getBossDisplayName(groupConfig)
end

function BrainrotService:TeleportPlayerToWorldSpawnGroup(player, groupId)
	if not player then
		return false, "InvalidPlayer"
	end

	local groupConfig = self:_getWorldSpawnGroupConfigById(groupId)
	if not groupConfig then
		return false, "GroupNotFound"
	end

	local character = player.Character
	if not (character and character.Parent) then
		return false, "CharacterNotReady"
	end

	local humanoid = getAliveHumanoid(character)
	local rootPart = getCharacterRootPart(character)
	if not (humanoid and rootPart) then
		return false, "CharacterNotReady"
	end

	local spawnPart = self:_getWorldSpawnPart(groupConfig)
	if not spawnPart then
		return false, "SpawnPartNotFound"
	end

	local worldSpawnConfig = self:_getWorldSpawnConfig()
	local liftHeight = (spawnPart.Size.Y * 0.5) + math.max(2, tonumber(worldSpawnConfig.heightOffset) or 0.25) + 3
	local targetPosition = spawnPart.Position + Vector3.new(0, liftHeight, 0)
	local lookVector = Vector3.new(spawnPart.CFrame.LookVector.X, 0, spawnPart.CFrame.LookVector.Z)
	if lookVector.Magnitude <= 0.001 then
		lookVector = Vector3.new(0, 0, -1)
	else
		lookVector = lookVector.Unit
	end

	local targetCFrame = CFrame.lookAt(targetPosition, targetPosition + lookVector, Vector3.new(0, 1, 0))
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero

	local ok = pcall(function()
		character:PivotTo(targetCFrame)
	end)
	if not ok then
		return false, "TeleportFailed"
	end

	rootPart = getCharacterRootPart(character) or rootPart
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

	return true, {
		groupId = math.max(0, math.floor(tonumber(groupConfig.Id) or 0)),
		partName = tostring(groupConfig.PartName or ""),
		bossName = self:_getBossDisplayName(groupConfig),
	}
end

function BrainrotService:SetWorldSpawnBossMoveSpeed(groupId, moveSpeed)
	local groupConfig = self:_getWorldSpawnGroupConfigById(groupId)
	if not groupConfig then
		return false, "GroupNotFound"
	end

	if not self:_groupHasBoss(groupConfig) then
		return false, "GroupHasNoBoss"
	end

	local parsedMoveSpeed = tonumber(moveSpeed)
	if type(parsedMoveSpeed) ~= "number" then
		return false, "InvalidMoveSpeed"
	end

	local normalizedMoveSpeed = math.clamp(parsedMoveSpeed, 0.1, 200)
	groupConfig.BossMoveSpeed = normalizedMoveSpeed

	local parsedGroupId = math.max(0, math.floor(tonumber(groupConfig.Id) or 0))
	local runtime = self._worldSpawnBossRuntimeByGroupId[parsedGroupId]
	if not (type(runtime) == "table" and runtime.Model and runtime.Model.Parent) then
		runtime = self:_ensureWorldSpawnBossRuntime(groupConfig)
	end

	if type(runtime) == "table" then
		runtime.GroupConfig = groupConfig
		runtime.MoveSpeed = normalizedMoveSpeed
		self:_syncBossRuntimeModelAttributes(runtime, getSharedClock())
	end

	return true, {
		groupId = parsedGroupId,
		partName = tostring(groupConfig.PartName or ""),
		bossName = self:_getBossDisplayName(groupConfig),
		moveSpeed = normalizedMoveSpeed,
		runtimeReady = runtime ~= nil,
	}
end

function BrainrotService:_countWorldSpawnEntriesForGroup(groupId)
	local groupEntries = self._worldSpawnGroupEntriesByGroupId[groupId]
	if type(groupEntries) ~= "table" then
		return 0
	end

	local activeCount = 0
	local staleEntryIds = {}
	for entryId in pairs(groupEntries) do
		local entry = self._worldSpawnEntriesById[entryId]
		if entry and entry.Instance and entry.Instance.Parent then
			activeCount += 1
		else
			table.insert(staleEntryIds, entryId)
		end
	end

	for _, entryId in ipairs(staleEntryIds) do
		self:_destroyWorldSpawnEntry(entryId)
	end

	return activeCount
end

function BrainrotService:_selectWorldSpawnBrainrotId(groupId)
	local poolEntries = BrainrotConfig.WorldSpawnPoolEntriesByGroupId[groupId]
	if type(poolEntries) ~= "table" or #poolEntries <= 0 then
		if not self._didWarnMissingWorldSpawnPoolByGroupId[groupId] then
			self._didWarnMissingWorldSpawnPoolByGroupId[groupId] = true
			warn(string.format("[BrainrotService] 脑红刷新组缺少生成池配置: %s", tostring(groupId)))
		end
		return nil
	end

	local totalWeight = 0
	for _, poolEntry in ipairs(poolEntries) do
		totalWeight += math.max(0, tonumber(poolEntry.Weight) or 0)
	end
	if totalWeight <= 0 then
		return nil
	end

	local roll = self._worldSpawnRng:NextNumber(0, totalWeight)
	local accumulated = 0
	for _, poolEntry in ipairs(poolEntries) do
		accumulated += math.max(0, tonumber(poolEntry.Weight) or 0)
		if roll <= accumulated then
			return math.max(0, math.floor(tonumber(poolEntry.BrainrotId) or 0))
		end
	end

	return math.max(0, math.floor(tonumber(poolEntries[#poolEntries].BrainrotId) or 0))
end

local function getServerLuckyExpireAtAttributeName()
	local shopConfig = GameConfig.SHOP or {}
	return tostring(shopConfig.ServerLuckyExpireAtAttributeName or "ServerLuckyExpireAt")
end

local function getSharedServerTimeNow()
	local ok, serverTimeNow = pcall(function()
		return Workspace:GetServerTimeNow()
	end)
	if ok then
		return math.max(0, tonumber(serverTimeNow) or 0)
	end

	return math.max(0, tonumber(os.time()) or 0)
end

local function normalizeRarityLookupKey(value)
	local text = string.lower(tostring(value or ""))
	text = string.gsub(text, "%s+", "")
	text = string.gsub(text, "_", "")
	text = string.gsub(text, "-", "")
	return text
end

local WORLD_SPAWN_MUTATION_RARITY_ID_BY_KEY = {}
do
	local rarityNames = BrainrotConfig.RarityNames
	if type(rarityNames) == "table" then
		for rarityId, rarityName in pairs(rarityNames) do
			local parsedRarityId = math.max(0, math.floor(tonumber(rarityId) or 0))
			if parsedRarityId > 0 then
				WORLD_SPAWN_MUTATION_RARITY_ID_BY_KEY[tostring(parsedRarityId)] = parsedRarityId
				local lookupKey = normalizeRarityLookupKey(rarityName)
				if lookupKey ~= "" then
					WORLD_SPAWN_MUTATION_RARITY_ID_BY_KEY[lookupKey] = parsedRarityId
				end
			end
		end
	end
end

function BrainrotService:_isServerLuckyActive()
	local expireAt = math.max(0, tonumber(ReplicatedStorage:GetAttribute(getServerLuckyExpireAtAttributeName())) or 0)
	return expireAt > getSharedServerTimeNow()
end

function BrainrotService:_getSpecialEventForcedMutationRarityId()
	local specialEventService = self._specialEventService
	if not (specialEventService and type(specialEventService.GetForcedWorldSpawnMutationRarityName) == "function") then
		return nil
	end

	local ok, forcedRarityName = pcall(function()
		return specialEventService:GetForcedWorldSpawnMutationRarityName()
	end)
	if not ok then
		return nil
	end

	local parsedRarityId = math.max(0, math.floor(tonumber(forcedRarityName) or 0))
	if parsedRarityId > 0 then
		return parsedRarityId
	end

	local lookupKey = normalizeRarityLookupKey(forcedRarityName)
	if lookupKey == "" then
		return nil
	end

	local rarityId = WORLD_SPAWN_MUTATION_RARITY_ID_BY_KEY[lookupKey]
	if rarityId and rarityId > 0 then
		return rarityId
	end

	if not self._didWarnMissingSpecialEventMutationRarityByName[lookupKey] then
		self._didWarnMissingSpecialEventMutationRarityByName[lookupKey] = true
		warn(string.format(
			"[BrainrotService] 特殊事件配置了未知突变稀有度: %s",
			tostring(forcedRarityName)
		))
	end

	return nil
end

function BrainrotService:_selectWorldSpawnMutationRarity()
	local forcedRarityId = self:_getSpecialEventForcedMutationRarityId()
	if forcedRarityId and forcedRarityId > 0 then
		return forcedRarityId
	end

	local mutationEntries = BrainrotConfig.WorldSpawnMutationWeightsByRarity
	local totalWeight = math.max(0, tonumber(BrainrotConfig.WorldSpawnMutationTotalWeight) or 0)
	if self:_isServerLuckyActive() then
		mutationEntries = BrainrotConfig.WorldSpawnServerLuckyMutationWeightsByRarity
		totalWeight = math.max(0, tonumber(BrainrotConfig.WorldSpawnServerLuckyMutationTotalWeight) or 0)
	end

	if type(mutationEntries) ~= "table" or #mutationEntries <= 0 or totalWeight <= 0 then
		return nil
	end

	local roll = self._worldSpawnRng:NextNumber(0, totalWeight)
	local accumulated = 0
	for _, mutationEntry in ipairs(mutationEntries) do
		accumulated += math.max(0, tonumber(mutationEntry.Weight) or 0)
		if roll <= accumulated then
			return math.max(0, math.floor(tonumber(mutationEntry.Rarity) or 0))
		end
	end

	return math.max(0, math.floor(tonumber(mutationEntries[#mutationEntries].Rarity) or 0))
end

function BrainrotService:_resolveWorldSpawnMutatedBrainrotId(baseBrainrotId)
	local parsedBrainrotId = math.max(0, math.floor(tonumber(baseBrainrotId) or 0))
	if parsedBrainrotId <= 0 then
		return nil
	end

	if type(BrainrotConfig.ById[parsedBrainrotId]) ~= "table" then
		return nil
	end

	local mutationRarityId = self:_selectWorldSpawnMutationRarity()
	if not mutationRarityId or mutationRarityId <= 0 then
		return parsedBrainrotId
	end

	local familyKey = parsedBrainrotId % 10000
	if familyKey <= 0 then
		return parsedBrainrotId
	end

	local familyEntries = BrainrotConfig.EntriesByFamilyKey[familyKey]
	if type(familyEntries) ~= "table" then
		return parsedBrainrotId
	end

	local mutatedDefinition = familyEntries[mutationRarityId]
	if type(mutatedDefinition) ~= "table" then
		return parsedBrainrotId
	end

	local mutatedBrainrotId = math.max(0, math.floor(tonumber(mutatedDefinition.Id) or 0))
	if mutatedBrainrotId <= 0 then
		return parsedBrainrotId
	end

	return mutatedBrainrotId
end

local function formatWorldSpawnCountdownText(remainingSeconds)
	local config = GameConfig.BRAINROT or {}
	local decimals = math.max(0, math.floor(tonumber(config.WorldSpawnCountdownDecimals) or 1))
	local suffix = tostring(config.WorldSpawnCountdownSuffix or "S")
	local safeRemaining = math.max(0, tonumber(remainingSeconds) or 0)
	return string.format("%0." .. tostring(decimals) .. "f%s", safeRemaining, suffix)
end

local function normalizeWorldSpawnExpireAt(expireAt)
	local numericExpireAt = math.max(0, tonumber(expireAt) or 0)
	if numericExpireAt <= 0 then
		return 0, false
	end

	if numericExpireAt >= 1000000000 then
		return numericExpireAt, false
	end

	-- Legacy world spawns stored expireAt as os.clock()-relative time; upgrade them in place.
	local remainingSeconds = math.max(0, numericExpireAt - os.clock())
	return getSharedServerTimeNow() + remainingSeconds, true
end

local function getWorldSpawnCountdownInstance(entry)
	if type(entry) ~= "table" then
		return nil
	end

	local instance = entry.Instance
	if instance and instance.Parent then
		return instance
	end

	local model = entry.Model
	if model and model.Parent then
		return model
	end

	return instance or model
end

local function setWorldSpawnExpireAtAttribute(instance, expireAt)
	if not instance then
		return
	end

	local normalizedExpireAt = select(1, normalizeWorldSpawnExpireAt(expireAt))
	instance:SetAttribute(WORLD_SPAWN_EXPIRE_AT_ATTRIBUTE, normalizedExpireAt)
end

function BrainrotService:_resolveWorldSpawnCountdownUi(entry)
	if type(entry) ~= "table" then
		return nil
	end

	local cachedUi = entry.CountdownUi
	if type(cachedUi) == "table" then
		local cachedTimeLabel = cachedUi.TimeLabel
		if cachedTimeLabel and cachedTimeLabel.Parent then
			return cachedUi
		end
	end

	local instance = getWorldSpawnCountdownInstance(entry)
	if not (instance and instance.Parent) then
		return nil
	end

	local infoAttachment = self:_findInfoAttachment(instance)
	if not infoAttachment then
		return nil
	end

	local infoTemplateName = tostring(GameConfig.BRAINROT.InfoTemplateName or "BaseInfo")
	local infoTitleRootName = tostring(GameConfig.BRAINROT.InfoTitleRootName or "Title")
	local infoTimeRootName = tostring(GameConfig.BRAINROT.InfoTimeRootName or "Time")
	local infoTimeLabelName = tostring(GameConfig.BRAINROT.InfoTimeLabelName or "Time")
	local infoGui = infoAttachment:FindFirstChild(infoTemplateName)
	if not (infoGui and infoGui:IsA("BillboardGui")) then
		return nil
	end

	local titleRoot = infoGui:FindFirstChild(infoTitleRootName, true) or infoGui
	local timeRoot = titleRoot:FindFirstChild(infoTimeRootName, true) or infoGui:FindFirstChild(infoTimeRootName, true)
	local timeLabel = findFirstTextLabelByName(timeRoot or titleRoot, infoTimeLabelName) or findFirstTextLabelByName(infoGui, infoTimeLabelName)
	if not timeLabel then
		return nil
	end

	local resolvedUi = {
		TimeRoot = timeRoot,
		TimeLabel = timeLabel,
	}
	entry.CountdownUi = resolvedUi
	return resolvedUi
end

function BrainrotService:_updateWorldSpawnCountdownUi(entry)
	if type(entry) ~= "table" then
		return
	end

	local normalizedExpireAt, didNormalizeExpireAt = normalizeWorldSpawnExpireAt(entry.ExpireAt)
	if normalizedExpireAt > 0 then
		entry.ExpireAt = normalizedExpireAt
		if didNormalizeExpireAt then
			local countdownInstance = getWorldSpawnCountdownInstance(entry)
			if countdownInstance and countdownInstance.Parent then
				setWorldSpawnExpireAtAttribute(countdownInstance, normalizedExpireAt)
			end
		end
	end

	local countdownUi = self:_resolveWorldSpawnCountdownUi(entry)
	if type(countdownUi) ~= "table" then
		return
	end

	local timeRoot = countdownUi.TimeRoot
	local timeLabel = countdownUi.TimeLabel
	if not timeLabel then
		return
	end

	if timeRoot and timeRoot:IsA("GuiObject") then
		timeRoot.Visible = true
	end
	if timeRoot and timeRoot:IsA("LayerCollector") then
		timeRoot.Enabled = true
	end

	timeLabel.Visible = true
	timeLabel.Text = formatWorldSpawnCountdownText(normalizedExpireAt - getSharedServerTimeNow())
end
function BrainrotService:_createWorldSpawnModelAtCFrame(brainrotDefinition, spawnCFrame)
	if not (brainrotDefinition and spawnCFrame) then
		return nil
	end

	local runtimeFolder = self:_getWorldSpawnRuntimeFolder()
	local tempPart = Instance.new("Part")
	tempPart.Name = "WorldSpawnAnchor"
	tempPart.Transparency = 1
	tempPart.CanCollide = false
	tempPart.CanTouch = false
	tempPart.CanQuery = false
	tempPart.Anchored = true
	tempPart.Size = Vector3.new(1, 1, 1)
	tempPart.CFrame = spawnCFrame
	tempPart.Parent = runtimeFolder

	local tempAttachment = Instance.new("Attachment")
	tempAttachment.Name = "WorldSpawnAttachment"
	tempAttachment.Parent = tempPart

	local worldInstance = self:_createPlacedModel(tempAttachment, brainrotDefinition, getBaseBrainrotLevel())
	if not worldInstance then
		tempPart:Destroy()
		return nil
	end

	worldInstance.Name = string.format("WorldSpawnBrainrot_%d", math.max(0, tonumber(brainrotDefinition.Id) or 0))
	worldInstance.Parent = runtimeFolder
	tempPart:Destroy()
	return worldInstance
end

function BrainrotService:_createWorldSpawnModel(spawnPart, brainrotDefinition)
	local spawnCFrame = self:_getWorldSpawnSpawnCFrame(spawnPart)
	if not spawnCFrame then
		return nil
	end

	local worldInstance = self:_createWorldSpawnModelAtCFrame(brainrotDefinition, spawnCFrame)
	if not worldInstance then
		return nil
	end
	snapInstanceBottomToY(worldInstance, spawnCFrame.Position.Y)

	local temporaryRuntimeFolder = spawnPart:FindFirstChild(GameConfig.BRAINROT.RuntimeFolderName)
	if temporaryRuntimeFolder and temporaryRuntimeFolder:IsA("Folder") and #temporaryRuntimeFolder:GetChildren() <= 0 then
		temporaryRuntimeFolder:Destroy()
	end

	return worldInstance
end

function BrainrotService:_createTemporaryCarryTool(brainrotDefinition, brainrotId)
	local config = self:_getWorldSpawnConfig()
	local tool = Instance.new("Tool")
	tool.Name = tostring(brainrotDefinition and brainrotDefinition.Name or config.carryToolName or "WorldCarryBrainrot")
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ManualActivationOnly = true
	tool.TextureId = tostring(brainrotDefinition and brainrotDefinition.Icon or "")
	tool:SetAttribute(config.hideFromBackpackAttributeName, true)
	tool:SetAttribute(config.temporaryCarryAttributeName, true)
	tool:SetAttribute("BrainrotId", math.max(0, math.floor(tonumber(brainrotId) or 0)))

	local handle = self:_createToolHandle(brainrotDefinition)
	handle.Parent = tool
	local attachedWorldCarryVisual = self:_attachWorldCarryVisual(tool, brainrotDefinition, handle)
	if not attachedWorldCarryVisual then
		local infoAttachment = Instance.new("Attachment")
		infoAttachment.Name = tostring(GameConfig.BRAINROT.InfoAttachmentName or "Info")
		infoAttachment.Parent = handle
		self:_attachToolVisual(tool, brainrotDefinition, handle)
	end
	self:_attachPlacedInfoUi(tool, brainrotDefinition, getBaseBrainrotLevel())
	return tool
end

function BrainrotService:_getCarriedWorldBrainrotRuntime(playerUserId)
	local userId = math.max(0, math.floor(tonumber(playerUserId) or 0))
	if userId <= 0 then
		return nil
	end

	local runtime = self._carriedWorldBrainrotRuntimeByUserId[userId]
	if type(runtime) ~= "table" then
		runtime = {
			Connections = {},
			AnimationTrack = nil,
		}
		self._carriedWorldBrainrotRuntimeByUserId[userId] = runtime
	end

	return runtime
end

function BrainrotService:_setCarriedWorldBrainrotAnimation(player, userId, shouldPlay)
	local runtime = self:_getCarriedWorldBrainrotRuntime(userId)
	if not runtime then
		return
	end

	if runtime.AnimationTrack then
		pcall(function()
			runtime.AnimationTrack:Stop(0.1)
		end)
		pcall(function()
			runtime.AnimationTrack:Destroy()
		end)
		runtime.AnimationTrack = nil
	end

	if shouldPlay ~= true then
		return
	end

	local config = self:_getWorldSpawnConfig()
	local animationId = config.carryAnimationId
	if not animationId then
		return
	end

	local character = player and player.Character or nil
	local humanoid = character and character:FindFirstChildOfClass("Humanoid") or nil
	if not humanoid then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()
	if not (ok and track) then
		return
	end

	track.Priority = Enum.AnimationPriority.Action
	track.Looped = true
	track:Play(0.1)
	runtime.AnimationTrack = track
end

function BrainrotService:_clearCarriedWorldBrainrotRuntime(carryData)
	if type(carryData) ~= "table" then
		return
	end

	if carryData.Model and carryData.Model.Parent then
		carryData.Model:Destroy()
	end
	carryData.Model = nil
end

function BrainrotService:_clearCarriedWorldBrainrotPlayerRuntime(userId)
	local runtime = self._carriedWorldBrainrotRuntimeByUserId[userId]
	if type(runtime) ~= "table" then
		return
	end

	self:_disconnectConnections(runtime.Connections)
	self:_setCarriedWorldBrainrotAnimation(nil, userId, false)
	self._carriedWorldBrainrotRuntimeByUserId[userId] = nil
end

function BrainrotService:_prepareCarriedWorldBrainrotModel(model, headPart)
	if not (model and headPart) then
		return false
	end

	local modelPrimary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not modelPrimary then
		return false
	end
	model.PrimaryPart = modelPrimary

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		elseif descendant:IsA("ProximityPrompt") then
			descendant:Destroy()
		elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant.Disabled = true
		end
	end

	return true
end

function BrainrotService:_refreshCarriedWorldBrainrotVisuals(player)
	local userId = player and player.UserId or 0
	local carryList = self._carriedWorldBrainrotByUserId[userId]
	if type(carryList) ~= "table" or #carryList <= 0 then
		self:_clearCarriedWorldBrainrotPlayerRuntime(userId)
		return
	end

	local character = player.Character
	local headPart = character and (character:FindFirstChild("Head") or getCharacterRootPart(character)) or nil
	if not headPart then
		return
	end

	local runtime = self:_getCarriedWorldBrainrotRuntime(userId)
	if runtime and #runtime.Connections <= 0 then
		local humanoid = character and character:FindFirstChildOfClass("Humanoid") or nil
		local config = self:_getWorldSpawnConfig()
		if humanoid then
			table.insert(runtime.Connections, humanoid.StateChanged:Connect(function(_, newState)
				if config.dropStates[newState] == true then
					local rootPart = getCharacterRootPart(player.Character)
					local dropPosition = rootPart and rootPart.Position or headPart.Position
					-- 如果玩家已在 Homeland 范围内（例如传送回家后落地触发 FallingDown），
					-- 直接 claim 而不是 drop，避免传送回家时丢失携带的脑红。
					local homelandPart = self:_getWorldSpawnClaimPart()
					if homelandPart and rootPart and isPointInsidePartHorizontalBounds(homelandPart, rootPart.Position) then
						self:_claimAllCarriedWorldBrainrots(player)
					else
						self:_dropCarriedWorldBrainrot(player, "HumanoidStateChanged", dropPosition)
					end
				end
			end))
			table.insert(runtime.Connections, humanoid.Died:Connect(function()
				local rootPart = getCharacterRootPart(player.Character)
				local dropPosition = rootPart and rootPart.Position or headPart.Position
				self:_dropCarriedWorldBrainrot(player, "Died", dropPosition)
			end))
		end
	end

	for index, carryData in ipairs(carryList) do
		local model = carryData.Model
		if model and model.Parent ~= character then
			model.Parent = character
		end
		if model and self:_prepareCarriedWorldBrainrotModel(model, headPart) then
			local modelAnchorPart = model.PrimaryPart or getPreferredModelBasePart(model) or model:FindFirstChildWhichIsA("BasePart", true)
			if modelAnchorPart then
				model.PrimaryPart = modelAnchorPart
			end

			local targetPosition = headPart.Position + Vector3.new(0, (headPart.Size.Y * 0.5) + 0.6 + ((index - 1) * 0.02), 0)
			local currentPivot = model:GetPivot()
			local targetCFrame = setCFramePosition(currentPivot, targetPosition) or CFrame.new(targetPosition)
			local anchorWeld = nil
			for _, descendant in ipairs(model:GetDescendants()) do
				if descendant:IsA("BasePart") then
					local existingWeld = descendant:FindFirstChild("WorldCarryWeld")
					if existingWeld and not existingWeld:IsA("WeldConstraint") then
						existingWeld:Destroy()
						existingWeld = nil
					end
					if descendant == modelAnchorPart then
						anchorWeld = existingWeld
					elseif existingWeld then
						existingWeld:Destroy()
					end
				end
			end

			local shouldReattach = carryData.CarryVisualIndex ~= index
				or carryData.CarryVisualHeadPart ~= headPart
				or anchorWeld == nil
				or anchorWeld.Part0 ~= headPart
				or anchorWeld.Part1 ~= modelAnchorPart

			if shouldReattach and modelAnchorPart then
				if anchorWeld then
					anchorWeld:Destroy()
				end

				model:PivotTo(targetCFrame)

				anchorWeld = Instance.new("WeldConstraint")
				anchorWeld.Name = "WorldCarryWeld"
				anchorWeld.Part0 = headPart
				anchorWeld.Part1 = modelAnchorPart
				anchorWeld.Parent = modelAnchorPart
			end

			carryData.CarryVisualIndex = index
			carryData.CarryVisualHeadPart = headPart
		end
	end

	self:_setCarriedWorldBrainrotAnimation(player, userId, true)
end

function BrainrotService:_registerWorldSpawnEntry(groupId, brainrotId, worldInstance, expireAt)
	local brainrotDefinition = BrainrotConfig.ById[brainrotId]
	if not (groupId and brainrotDefinition and worldInstance) then
		return nil
	end

	local promptParent = self:_resolvePlacedPromptParent(worldInstance) or getFirstBasePart(worldInstance)
	if not promptParent then
		if worldInstance.Parent then
			worldInstance:Destroy()
		end
		return nil
	end

	local config = self:_getWorldSpawnConfig()
	self._worldSpawnNextEntryId += 1
	local entryId = self._worldSpawnNextEntryId

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = config.promptName
	prompt.ActionText = config.promptActionText
	prompt.ObjectText = tostring(brainrotDefinition.Name or config.promptObjectText or "Brainrot")
	prompt.HoldDuration = config.holdDuration
	prompt.MaxActivationDistance = config.maxActivationDistance
	prompt.RequiresLineOfSight = config.requiresLineOfSight
	prompt.Parent = promptParent

	local entry = {
		EntryId = entryId,
		GroupId = math.max(0, math.floor(tonumber(groupId) or 0)),
		BrainrotId = math.max(0, math.floor(tonumber(brainrotId) or 0)),
		Instance = worldInstance,
		Prompt = prompt,
		ExpireAt = select(1, normalizeWorldSpawnExpireAt(expireAt)),
		IsCollecting = false,
	}
	if entry.ExpireAt <= 0 then
		entry.ExpireAt = getSharedServerTimeNow() + config.lifetimeMin
	end
	self._worldSpawnEntriesById[entryId] = entry
	ensureTable(self._worldSpawnGroupEntriesByGroupId, entry.GroupId)[entryId] = true
	setWorldSpawnExpireAtAttribute(worldInstance, entry.ExpireAt)
	self:_updateWorldSpawnCountdownUi(entry)
	self:_playWorldSpawnIdleAnimation(entry)

	entry.Connection = prompt.Triggered:Connect(function(player)
		if entry.IsCollecting or self._worldSpawnEntriesById[entryId] ~= entry then
			return
		end

		entry.IsCollecting = true
		local success = self:_startCarryingWorldBrainrot(player, entry)
		if not success then
			entry.IsCollecting = false
		end
	end)

	return entry
end

function BrainrotService:_destroyWorldSpawnEntry(entryId)
	local entry = self._worldSpawnEntriesById[entryId]
	if not entry then
		return
	end

	self._worldSpawnEntriesById[entryId] = nil
	self:_stopWorldSpawnIdleAnimation(entryId)

	local groupEntries = self._worldSpawnGroupEntriesByGroupId[entry.GroupId]
	if type(groupEntries) == "table" then
		groupEntries[entryId] = nil
		if next(groupEntries) == nil then
			self._worldSpawnGroupEntriesByGroupId[entry.GroupId] = nil
		end
	end

	if entry.Connection and entry.Connection.Disconnect then
		entry.Connection:Disconnect()
		entry.Connection = nil
	end

	if entry.Prompt and entry.Prompt.Parent then
		entry.Prompt:Destroy()
	end

	if entry.Instance and entry.Instance.Parent then
		entry.Instance:Destroy()
	end
end

function BrainrotService:_pushBrainrotGainFeedback(player, brainrotName, options)
	if not (player and self._brainrotClaimTipEvent) then
		return
	end

	local normalizedOptions = type(options) == "table" and options or {}
	local resolvedMessage = normalizedOptions.message
	if resolvedMessage == nil then
		resolvedMessage = string.format("You Claimed a %s!", tostring(brainrotName or "Brainrot"))
	end

	self._brainrotClaimTipEvent:FireClient(player, {
		message = tostring(resolvedMessage or ""),
		playConfetti = normalizedOptions.playConfetti ~= false,
		playSound = normalizedOptions.playSound ~= false,
		timestamp = os.clock(),
	})
end

function BrainrotService:_pushBrainrotClaimTip(player, brainrotName)
	self:_pushBrainrotGainFeedback(player, brainrotName, {
		playConfetti = true,
		playSound = true,
	})
end

function BrainrotService:_pushGrantedBrainrotFeedback(player, grantResult, reason)
	local brainrotName = type(grantResult) == "table" and tostring(grantResult.brainrotName or "") or ""
	if brainrotName == "" then
		return
	end

	if tostring(reason or "") == "WorldSpawnClaim" then
		self:_pushBrainrotClaimTip(player, brainrotName)
		return
	end

	self:_pushBrainrotGainFeedback(player, brainrotName, {
		message = "",
		playConfetti = false,
		playSound = true,
	})
end
function BrainrotService:_pushCarryUpgradeFeedback(player, status, payload)
	if not (player and self._carryUpgradeFeedbackEvent) then
		return
	end

	local normalizedPayload = type(payload) == "table" and payload or {}
	self._carryUpgradeFeedbackEvent:FireClient(player, {
		status = tostring(status or normalizedPayload.status or "Unknown"),
		message = tostring(normalizedPayload.message or ""),
		timestamp = os.clock(),
	})
end

function BrainrotService:_handleRequestCarryUpgrade(player, payload)
	if not player then
		return
	end

	local debounceSeconds = math.max(0.05, tonumber(CarryConfig.RequestDebounceSeconds) or 0.2)
	local userId = player.UserId
	local nowClock = os.clock()
	local lastClock = tonumber(self._carryUpgradeRequestClockByUserId[userId]) or 0
	if nowClock - lastClock < debounceSeconds then
		self:_pushCarryUpgradeFeedback(player, "Debounced", {})
		return
	end
	self._carryUpgradeRequestClockByUserId[userId] = nowClock

	local purchaseType = type(payload) == "table" and tostring(payload.purchaseType or "") or ""
	if purchaseType ~= "Coin" then
		self:_pushCarryUpgradeFeedback(player, "InvalidPurchaseType", {})
		return
	end

	local _playerData, brainrotData = self:_getOrCreateDataContainers(player)
	if not brainrotData then
		self:_pushCarryUpgradeFeedback(player, "MissingData", {})
		return
	end

	local currentLevel = normalizeCarryUpgradeLevel(brainrotData.CarryUpgradeLevel)
	local nextEntry = CarryConfig.EntriesByLevel[currentLevel + 1]
	if not nextEntry then
		self:PushBrainrotState(player)
		self:_pushCarryUpgradeFeedback(player, "AlreadyMax", {})
		return
	end

	local requiredCoins = math.max(0, math.floor(tonumber(nextEntry.CoinPrice) or 0))
	local currentCoins = self._playerDataService and self._playerDataService:GetCoins(player) or 0
	if currentCoins < requiredCoins then
		self:PushBrainrotState(player)
		self:_pushCarryUpgradeFeedback(player, "InsufficientCoins", {})
		return
	end

	local spendSuccess = true
	if requiredCoins > 0 and self._currencyService then
		spendSuccess = select(1, self._currencyService:AddCoins(player, -requiredCoins, "CarryUpgradePurchase"))
	end
	if spendSuccess ~= true then
		self:PushBrainrotState(player)
		self:_pushCarryUpgradeFeedback(player, "SpendFailed", {})
		return
	end

	brainrotData.CarryUpgradeLevel = normalizeCarryUpgradeLevel(nextEntry.Level)
	local didSave = not self._playerDataService or self._playerDataService:SavePlayerData(player)
	if not didSave then
		brainrotData.CarryUpgradeLevel = currentLevel
		if requiredCoins > 0 and self._currencyService then
			self._currencyService:AddCoins(player, requiredCoins, "CarryUpgradePurchaseRollback")
		end
		self:PushBrainrotState(player)
		self:_pushCarryUpgradeFeedback(player, "SaveFailed", {})
		return
	end

	self:PushBrainrotState(player)
	self:_pushCarryUpgradeFeedback(player, "CoinPurchased", {
		message = tostring(CarryConfig.PurchaseSuccessTipText or "Purchase Successful?"),
	})
end

function BrainrotService:_processCarryUpgradeReceipt(receiptInfo)
	local productId = math.max(0, math.floor(tonumber(receiptInfo and receiptInfo.ProductId) or 0))
	local entry = CarryConfig.EntriesByProductId[productId]
	if not entry then
		return false, nil
	end

	local player = Players:GetPlayerByUserId(math.max(0, math.floor(tonumber(receiptInfo and receiptInfo.PlayerId) or 0)))
	if not player then
		return true, Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local _playerData, brainrotData = self:_getOrCreateDataContainers(player)
	if not brainrotData then
		return true, Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseId = tostring(receiptInfo and receiptInfo.PurchaseId or "")
	local processedPurchaseIds = self:_getOrCreateProcessedCarryPurchaseIds(brainrotData)
	if purchaseId ~= "" and processedPurchaseIds[purchaseId] then
		return true, Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local previousLevel = normalizeCarryUpgradeLevel(brainrotData.CarryUpgradeLevel)
	local previousProcessedAt = purchaseId ~= "" and processedPurchaseIds[purchaseId] or nil
	brainrotData.CarryUpgradeLevel = math.max(previousLevel, normalizeCarryUpgradeLevel(entry.Level))
	if purchaseId ~= "" then
		processedPurchaseIds[purchaseId] = os.time()
	end

	local didSave = not self._playerDataService or self._playerDataService:SavePlayerData(player)
	if not didSave then
		brainrotData.CarryUpgradeLevel = previousLevel
		if purchaseId ~= "" then
			if previousProcessedAt ~= nil then
				processedPurchaseIds[purchaseId] = previousProcessedAt
			else
				processedPurchaseIds[purchaseId] = nil
			end
		end
		self:PushBrainrotState(player)
		self:_pushCarryUpgradeFeedback(player, "SaveFailed", {})
		return true, Enum.ProductPurchaseDecision.NotProcessedYet
	end

	self:PushBrainrotState(player)
	self:_pushCarryUpgradeFeedback(player, "RobuxPurchaseGranted", {
		message = tostring(CarryConfig.PurchaseSuccessTipText or "Purchase Successful?"),
	})
	return true, Enum.ProductPurchaseDecision.PurchaseGranted
end

function BrainrotService:_spawnDroppedCarriedWorldBrainrot(carryData, worldPosition, ignoredInstances)
	if type(carryData) ~= "table" then
		return false
	end

	local groupConfig = self:_getWorldSpawnGroupConfigById(carryData.GroupId)
	local brainrotDefinition = BrainrotConfig.ById[carryData.BrainrotId]
	if not (groupConfig and brainrotDefinition) then
		return false
	end

	local config = self:_getWorldSpawnConfig()
	local requestedPosition = typeof(worldPosition) == "Vector3" and worldPosition or carryData.LastKnownPosition or Vector3.new()
	local groundPosition = resolveGroundDropPosition(requestedPosition, ignoredInstances) or requestedPosition
	local targetBottomY = groundPosition.Y + (tonumber(config.heightOffset) or 0.25)
	local spawnCFrame = CFrame.new(Vector3.new(groundPosition.X, targetBottomY, groundPosition.Z))
	local worldInstance = self:_createWorldSpawnModelAtCFrame(brainrotDefinition, spawnCFrame)
	if not worldInstance then
		return false
	end
	snapInstanceBottomToY(worldInstance, targetBottomY)

	local lifetimeMax = math.max(config.lifetimeMin, config.lifetimeMax)
	local expireAt = tonumber(carryData.ExpireAt)
	if not expireAt then
		expireAt = getSharedServerTimeNow() + self._worldSpawnRng:NextNumber(config.lifetimeMin, lifetimeMax)
	end
	return self:_registerWorldSpawnEntry(carryData.GroupId, carryData.BrainrotId, worldInstance, expireAt) ~= nil
end

function BrainrotService:_dropCarriedWorldBrainrotByIndex(player, itemIndex, reason, worldPosition)
	local userId = player and player.UserId or 0
	local carryList = self._carriedWorldBrainrotByUserId[userId]
	if type(carryList) ~= "table" then
		return false
	end

	local carryData = carryList[itemIndex]
	if type(carryData) ~= "table" then
		return false
	end

	table.remove(carryList, itemIndex)
	local dropPosition = worldPosition or carryData.LastKnownPosition
	if not dropPosition then
		local rootPart = getCharacterRootPart(player and player.Character)
		dropPosition = rootPart and rootPart.Position or Vector3.new()
	end

	self:_clearCarriedWorldBrainrotRuntime(carryData)
	local ignoredInstances = {}
	if player and player.Character then
		table.insert(ignoredInstances, player.Character)
	end
	local dropped = self:_spawnDroppedCarriedWorldBrainrot(carryData, dropPosition, ignoredInstances)
	if not dropped then
		local groupConfig = self:_getWorldSpawnGroupConfigById(carryData.GroupId)
		if groupConfig then
			task.defer(function()
				self:_fillWorldSpawnGroup(groupConfig)
			end)
		end
	end

	if #carryList <= 0 then
		self._carriedWorldBrainrotByUserId[userId] = nil
		self:_clearCarriedWorldBrainrotPlayerRuntime(userId)
	else
		self:_refreshCarriedWorldBrainrotVisuals(player)
	end

	self:_refreshBossCarryStateForPlayer(player)
	self:_refreshBossTargetsForPlayer(player)

	return dropped, reason
end

function BrainrotService:_dropCarriedWorldBrainrot(player, reason, worldPosition)
	local userId = player and player.UserId or 0
	local carryList = self._carriedWorldBrainrotByUserId[userId]
	if type(carryList) ~= "table" or #carryList <= 0 then
		return false
	end

	local droppedAny = false
	for index = #carryList, 1, -1 do
		local dropped = self:_dropCarriedWorldBrainrotByIndex(player, index, reason, worldPosition)
		if dropped then
			droppedAny = true
		end
	end

	return droppedAny, reason
end

function BrainrotService:_claimCarriedWorldBrainrotByIndex(player, itemIndex)
	local userId = player and player.UserId or 0
	local carryList = self._carriedWorldBrainrotByUserId[userId]
	if type(carryList) ~= "table" then
		return false
	end

	local carryData = carryList[itemIndex]
	if not (player and type(carryData) == "table") then
		return false
	end

	local success, _reason, result = self:GrantBrainrotInstance(player, carryData.BrainrotId, getBaseBrainrotLevel(), "WorldSpawnClaim")
	if not success then
		return false
	end

	table.remove(carryList, itemIndex)
	self:_clearCarriedWorldBrainrotRuntime(carryData)

	local groupConfig = self:_getWorldSpawnGroupConfigById(carryData.GroupId)
	if groupConfig then
		task.defer(function()
			self:_fillWorldSpawnGroup(groupConfig)
		end)
	end

	if #carryList <= 0 then
		self._carriedWorldBrainrotByUserId[userId] = nil
		self:_clearCarriedWorldBrainrotPlayerRuntime(userId)
	else
		self:_refreshCarriedWorldBrainrotVisuals(player)
	end

	self:_refreshBossCarryStateForPlayer(player)
	self:_refreshBossTargetsForPlayer(player)

	return true, result
end

function BrainrotService:_claimAllCarriedWorldBrainrots(player)
	local userId = player and player.UserId or 0
	local carryList = self._carriedWorldBrainrotByUserId[userId]
	if type(carryList) ~= "table" or #carryList <= 0 then
		return false
	end

	local claimedAny = false
	for index = #carryList, 1, -1 do
		local claimed = self:_claimCarriedWorldBrainrotByIndex(player, index)
		if claimed then
			claimedAny = true
		end
	end

	if claimedAny and self._playerDataService then
		task.spawn(function()
			self._playerDataService:SavePlayerData(player)
		end)
	end

	return claimedAny
end

function BrainrotService:_startCarryingWorldBrainrot(player, entry)
	if not (player and entry and entry.Instance and entry.Instance.Parent) then
		return false
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid") or nil
	if not humanoid then
		return false
	end

	local brainrotDefinition = BrainrotConfig.ById[entry.BrainrotId]
	if not brainrotDefinition then
		return false
	end

	local carryList = self._carriedWorldBrainrotByUserId[player.UserId]
	if type(carryList) ~= "table" then
		carryList = {}
		self._carriedWorldBrainrotByUserId[player.UserId] = carryList
	end

	local carryCapacity = self:_getCarryCapacity(player)
	if #carryList >= carryCapacity and #carryList > 0 then
		local rootPart = getCharacterRootPart(player.Character)
		local dropPosition = rootPart and rootPart.Position or carryList[1].LastKnownPosition
		self:_dropCarriedWorldBrainrotByIndex(player, 1, "PickupAnotherWorldBrainrot", dropPosition)
		carryList = self._carriedWorldBrainrotByUserId[player.UserId] or {}
		self._carriedWorldBrainrotByUserId[player.UserId] = carryList
	end

	local pivotCFrame = select(1, getInstancePivotCFrame(entry.Instance))
	local carryModel = entry.Instance and entry.Instance:Clone() or nil
	if carryModel and pivotCFrame then
		local hiddenPivot = setCFramePosition(pivotCFrame, Vector3.new(0, -1000, 0))
		if hiddenPivot then
			setInstancePivotCFrame(carryModel, hiddenPivot)
		end
	end
	if not carryModel then
		carryModel = self:_createWorldSpawnModelAtCFrame(brainrotDefinition, CFrame.new(0, -1000, 0))
	end
	if not carryModel then
		return false
	end

	local lastKnownPosition = pivotCFrame and pivotCFrame.Position or (getCharacterRootPart(character) and getCharacterRootPart(character).Position) or Vector3.new()
	local carryData = {
		GroupId = entry.GroupId,
		BrainrotId = entry.BrainrotId,
		BrainrotName = tostring(brainrotDefinition.Name or "Brainrot"),
		ExpireAt = select(1, normalizeWorldSpawnExpireAt(entry.ExpireAt)),
		PickedAt = getSharedClock(),
		Model = carryModel,
		LastKnownPosition = lastKnownPosition,
		CountdownUi = nil,
	}
	setWorldSpawnExpireAtAttribute(carryModel, carryData.ExpireAt)
	self:_updateWorldSpawnCountdownUi(carryData)

	self:_destroyWorldSpawnEntry(entry.EntryId)
	table.insert(carryList, carryData)
	self:_refreshCarriedWorldBrainrotVisuals(player)
	self:_refreshBossCarryStateForPlayer(player)
	self:_refreshBossTargetsForPlayer(player)
	return true
end

function BrainrotService:_tickCarriedWorldBrainrots()
	local homelandPart = self:_getWorldSpawnClaimPart()
	local now = getSharedServerTimeNow()
	for userId, carryList in pairs(self._carriedWorldBrainrotByUserId) do
		local player = Players:GetPlayerByUserId(userId)
		if not player or not player.Parent then
			for index = #carryList, 1, -1 do
				self:_clearCarriedWorldBrainrotRuntime(carryList[index])
			end
			self._carriedWorldBrainrotByUserId[userId] = nil
			self:_clearCarriedWorldBrainrotPlayerRuntime(userId)
		else
			local rootPart = getCharacterRootPart(player.Character)
			if rootPart and rootPart.Parent then
				local shouldClaim = homelandPart and isPointInsidePartHorizontalBounds(homelandPart, rootPart.Position)
				for index = #carryList, 1, -1 do
					local carryData = carryList[index]
					carryData.LastKnownPosition = rootPart.Position
					local normalizedExpireAt, didNormalizeExpireAt = normalizeWorldSpawnExpireAt(carryData.ExpireAt)
					if normalizedExpireAt > 0 then
						carryData.ExpireAt = normalizedExpireAt
						if didNormalizeExpireAt and carryData.Model and carryData.Model.Parent then
							setWorldSpawnExpireAtAttribute(carryData.Model, normalizedExpireAt)
						end
					end
					if now >= (tonumber(carryData.ExpireAt) or math.huge) then
						self:_dropCarriedWorldBrainrotByIndex(player, index, "Expired", rootPart.Position)
					end
				end
				if shouldClaim then
					self:_claimAllCarriedWorldBrainrots(player)
				elseif self._carriedWorldBrainrotByUserId[userId] then
					self:_refreshCarriedWorldBrainrotVisuals(player)
				end
			end
		end
	end
end

function BrainrotService:_spawnWorldBrainrotForGroup(groupConfig)
	local groupId = math.max(0, math.floor(tonumber(groupConfig and groupConfig.Id) or 0))
	if groupId <= 0 then
		return false
	end

	self._worldSpawnGroupConfigById[groupId] = groupConfig

	local spawnPart = self:_getWorldSpawnPart(groupConfig)
	if not spawnPart then
		return false
	end

	local baseBrainrotId = self:_selectWorldSpawnBrainrotId(groupId)
	local brainrotId = self:_resolveWorldSpawnMutatedBrainrotId(baseBrainrotId)
	local brainrotDefinition = brainrotId and BrainrotConfig.ById[brainrotId] or nil
	if not brainrotDefinition then
		return false
	end

	local worldInstance = self:_createWorldSpawnModel(spawnPart, brainrotDefinition)
	if not worldInstance then
		return false
	end

	local config = self:_getWorldSpawnConfig()
	local lifetimeMax = math.max(config.lifetimeMin, config.lifetimeMax)
	local expireAt = getSharedServerTimeNow() + self._worldSpawnRng:NextNumber(config.lifetimeMin, lifetimeMax)
	return self:_registerWorldSpawnEntry(groupId, brainrotId, worldInstance, expireAt) ~= nil
end

function BrainrotService:_fillWorldSpawnGroup(groupConfig)
	if type(groupConfig) ~= "table" then
		return
	end

	local groupId = math.max(0, math.floor(tonumber(groupConfig.Id) or 0))
	local maxActiveCount = math.max(0, math.floor(tonumber(groupConfig.MaxActiveCount) or 0))
	if groupId <= 0 or maxActiveCount <= 0 then
		return
	end

	while self:_countWorldSpawnEntriesForGroup(groupId) < maxActiveCount do
		if not self:_spawnWorldBrainrotForGroup(groupConfig) then
			break
		end
	end
end

function BrainrotService:_tickWorldSpawnSystem()
	self:_tickCarriedWorldBrainrots()

	local now = getSharedServerTimeNow()
	local expiredEntryIds = {}
	for entryId, entry in pairs(self._worldSpawnEntriesById) do
		if not entry or not entry.Instance or not entry.Instance.Parent then
			table.insert(expiredEntryIds, entryId)
		else
			local normalizedExpireAt, didNormalizeExpireAt = normalizeWorldSpawnExpireAt(entry.ExpireAt)
			if normalizedExpireAt > 0 then
				entry.ExpireAt = normalizedExpireAt
				if didNormalizeExpireAt then
					setWorldSpawnExpireAtAttribute(entry.Instance, normalizedExpireAt)
				end
			end
			if now >= (tonumber(entry.ExpireAt) or 0) and not entry.IsCollecting then
				table.insert(expiredEntryIds, entryId)
			end
		end
	end

	for _, entryId in ipairs(expiredEntryIds) do
		self:_destroyWorldSpawnEntry(entryId)
	end

	for _, groupConfig in ipairs(BrainrotConfig.WorldSpawnGroups or {}) do
		self:_fillWorldSpawnGroup(groupConfig)
	end
end

function BrainrotService:_restorePlacedFromData(player)
	self:_clearRuntimePlaced(player)

	local playerData, _brainrotData, placedBrainrots = self:_getOrCreateDataContainers(player)
	if not playerData or not placedBrainrots then
		return
	end

	local platformsByPositionKey = self._platformsByUserId[player.UserId] or {}

	for positionKey, placedData in pairs(placedBrainrots) do
		local platformInfo = platformsByPositionKey[positionKey]
		local brainrotId = tonumber(placedData.BrainrotId)
		local brainrotDefinition = brainrotId and BrainrotConfig.ById[brainrotId] or nil

		if platformInfo and brainrotDefinition then
			local placedModel = self:_createPlacedModel(platformInfo.Attachment, brainrotDefinition, placedData.Level)
			if placedModel then
				self:_registerPlacedRuntime(player, positionKey, placedModel, brainrotDefinition)
			end
		end
	end
end

function BrainrotService:_applyOfflineProduction(player, playerData, placedBrainrots, productionState)
	local meta = type(playerData.Meta) == "table" and playerData.Meta or nil
	if not meta then
		return
	end

	local lastLogoutAt = math.floor(tonumber(meta.LastLogoutAt) or 0)
	if lastLogoutAt <= 0 then
		return
	end

	local now = os.time()
	local elapsed = now - lastLogoutAt
	if elapsed <= 0 then
		meta.LastLogoutAt = 0
		return
	end

	local capSeconds = math.max(0, math.floor(tonumber(GameConfig.BRAINROT.OfflineProductionCapSeconds) or 3600))
	local effectiveSeconds = math.min(elapsed, capSeconds)
	if effectiveSeconds <= 0 then
		meta.LastLogoutAt = 0
		return
	end

	local offlineMultiplier = self:_resolveOfflineProductionMultiplier(player)

	self:_requirePlacementService():ApplyOfflineProductionState(
		placedBrainrots,
		productionState,
		effectiveSeconds * offlineMultiplier
	)

	meta.LastLogoutAt = 0
end

function BrainrotService:PushBrainrotState(player)
	if not self._brainrotStateSyncEvent then
		return
	end

	local playerData, brainrotData, placedBrainrots = self:_getOrCreateDataContainers(player)
	if not playerData or not brainrotData or not placedBrainrots then
		return
	end

	local inventoryPayload = {}
	for _, inventoryItem in ipairs(brainrotData.Inventory) do
		local brainrotId = tonumber(inventoryItem.BrainrotId)
		local instanceId = tonumber(inventoryItem.InstanceId)
		local brainrotDefinition = brainrotId and BrainrotConfig.ById[brainrotId] or nil
		if brainrotDefinition and instanceId then
			local level = normalizeBrainrotLevel(inventoryItem.Level)
			table.insert(inventoryPayload, {
				instanceId = instanceId,
				brainrotId = brainrotDefinition.Id,
				name = brainrotDefinition.Name,
				icon = brainrotDefinition.Icon,
				quality = brainrotDefinition.Quality,
				qualityName = select(1, resolveQualityDisplayInfo(brainrotDefinition.Quality)),
				rarity = brainrotDefinition.Rarity,
				rarityName = select(1, resolveRarityDisplayInfo(brainrotDefinition.Rarity)),
				level = level,
				baseCoinPerSecond = getBrainrotBaseProductionSpeed(brainrotDefinition),
				coinPerSecond = getBrainrotProductionSpeed(brainrotDefinition, level),
				nextUpgradeCost = getBrainrotUpgradeCost(brainrotDefinition, level),
				sellPrice = getBrainrotSellPrice(brainrotDefinition),
				modelPath = brainrotDefinition.ModelPath,
			})
		end
	end

	table.sort(inventoryPayload, function(a, b)
		return a.instanceId < b.instanceId
	end)

	local placedPayload = {}
	for positionKey, placedData in pairs(placedBrainrots) do
		local brainrotId = tonumber(placedData.BrainrotId)
		local brainrotDefinition = brainrotId and BrainrotConfig.ById[brainrotId] or nil
		if brainrotDefinition then
			local level = normalizeBrainrotLevel(placedData.Level)
			table.insert(placedPayload, {
				positionKey = positionKey,
				instanceId = tonumber(placedData.InstanceId) or 0,
				brainrotId = brainrotDefinition.Id,
				name = brainrotDefinition.Name,
				level = level,
				baseCoinPerSecond = getBrainrotBaseProductionSpeed(brainrotDefinition),
				coinPerSecond = getBrainrotProductionSpeed(brainrotDefinition, level),
				nextUpgradeCost = getBrainrotUpgradeCost(brainrotDefinition, level),
				quality = brainrotDefinition.Quality,
				rarity = brainrotDefinition.Rarity,
			})
		end
	end

	table.sort(placedPayload, function(a, b)
		return a.positionKey < b.positionKey
	end)

	local unlockedBrainrotIds, discoveredCount, discoverableCount = self:_buildUnlockedBrainrotPayload(brainrotData, placedBrainrots)
	local totalBaseSpeed, totalMultiplier, totalFinalSpeed = self:_updatePlayerTotalProductionSpeed(player, placedBrainrots)

	self._brainrotStateSyncEvent:FireClient(player, {
		inventory = inventoryPayload,
		placed = placedPayload,
		equippedInstanceId = tonumber(brainrotData.EquippedInstanceId) or 0,
		unlockedBrainrotIds = unlockedBrainrotIds,
		discoveredCount = discoveredCount,
		discoverableCount = discoverableCount,
		totalProductionBaseSpeed = totalBaseSpeed,
		totalProductionMultiplier = totalMultiplier,
		totalProductionSpeed = totalFinalSpeed,
		carryUpgrade = self:_buildCarryUpgradeStatePayload(brainrotData),
	})
end

function BrainrotService:_tickProduction()
	for _, player in ipairs(Players:GetPlayers()) do
		local playerData, _brainrotData, placedBrainrots, productionState = self:_getOrCreateDataContainers(player)
		if playerData and type(placedBrainrots) == "table" and type(productionState) == "table" then
			local bonusMultiplier = select(1, self:_resolveProductionMultiplier(player))
			local changedPositions = self:_requirePlacementService():TickProductionState(placedBrainrots, productionState, bonusMultiplier)

			for positionKey in pairs(changedPositions) do
				self:_refreshClaimUiForPosition(player, positionKey, placedBrainrots, productionState)
			end

			self:_updatePlayerTotalProductionSpeed(player, placedBrainrots)
		end
	end
end
function BrainrotService:OnPlayerReady(player, assignedHome)
	local playerData, brainrotData, placedBrainrots, productionState = self:_getOrCreateDataContainers(player)
	if not playerData or not brainrotData or not placedBrainrots or not productionState then
		return
	end

	self:_bindToolRefreshWatchers(player)
	self:_ensureStarterInventory(playerData, brainrotData, placedBrainrots)
	self:_syncUnlockedBrainrots(brainrotData, placedBrainrots)
	self:_getPendingStealPurchase(player, false)

	local targetHome = assignedHome or self._homeService:GetAssignedHome(player)
	if targetHome then
		self:_bindHomePrompts(player, targetHome)
		self:_bindHomeClaims(player, targetHome)
		self:_bindHomeBrands(player, targetHome)
	else
		self:_clearPromptConnections(player)
		self:_clearClaimConnections(player)
		self:_clearBrandState(player)
	end

	self:_restorePlacedFromData(player)
	self:_applyOfflineProduction(player, playerData, placedBrainrots, productionState)
	self:_refreshBrainrotTools(player)
	self:_refreshBossCarryStateForPlayer(player)
	self:PushBrainrotState(player)
	self:_refreshAllClaimUi(player, placedBrainrots, productionState)
	self:_refreshAllBrandUi(player, placedBrainrots)
	self:_refreshAllPlatformPrompts(player, placedBrainrots)
	self:_updatePlayerTotalProductionSpeed(player, placedBrainrots)
	self:_scheduleToolRefreshBurst(player, 8, 0.5)
end

function BrainrotService:OnHomeLayoutChanged(player, assignedHome)
	local _playerData, _brainrotData, placedBrainrots, productionState = self:_getOrCreateDataContainers(player)
	local targetHome = assignedHome or self._homeService:GetAssignedHome(player)
	if targetHome then
		self:_bindHomePrompts(player, targetHome)
		self:_bindHomeClaims(player, targetHome)
		self:_bindHomeBrands(player, targetHome)
	else
		self:_clearPromptConnections(player)
		self:_clearClaimConnections(player)
		self:_clearBrandState(player)
	end

	self:_restorePlacedFromData(player)
	self:_refreshAllClaimUi(player, placedBrainrots, productionState)
	self:_refreshAllBrandUi(player, placedBrainrots)
	self:_refreshAllPlatformPrompts(player, placedBrainrots)
	self:_updatePlayerTotalProductionSpeed(player, placedBrainrots)
	self:PushBrainrotState(player)
end

function BrainrotService:OnPlayerRemoving(player)
	local carryList = self._carriedWorldBrainrotByUserId[player.UserId]
	if type(carryList) == "table" and #carryList > 0 then
		local rootPart = getCharacterRootPart(player.Character)
		local position = rootPart and rootPart.Position or carryList[1].LastKnownPosition
		self:_dropCarriedWorldBrainrot(player, "PlayerRemoving", position)
	end

	self:_clearPromptConnections(player)
	self:_clearClaimConnections(player)
	self:_clearToolConnections(player)
	self:_clearToolRefreshWatchers(player)
	self:_clearBrandState(player)
	self:_clearRuntimePlaced(player)
	self._sellRequestClockByUserId[player.UserId] = nil
	self._carryUpgradeRequestClockByUserId[player.UserId] = nil
	self._pendingStealPurchaseByBuyerUserId[player.UserId] = nil
	self:_clearCarriedWorldBrainrotPlayerRuntime(player.UserId)
	player:SetAttribute(BOSS_HOME_UNLOCK_AT_ATTRIBUTE, nil)

	for _, runtime in pairs(self._worldSpawnBossRuntimeByGroupId) do
		if type(runtime) == "table" and math.max(0, math.floor(tonumber(runtime.TargetUserId) or 0)) == player.UserId then
			self:_setBossTarget(runtime, nil)
		end
	end

	player:SetAttribute("TotalProductionSpeedBase", nil)
	player:SetAttribute("TotalProductionBonusRate", nil)
	player:SetAttribute("TotalProductionMultiplier", nil)
	player:SetAttribute("TotalProductionSpeed", nil)
end

function BrainrotService:Init(dependencies)
	self._playerDataService = dependencies.PlayerDataService
	self._homeService = dependencies.HomeService
	self._currencyService = dependencies.CurrencyService
	self._friendBonusService = dependencies.FriendBonusService
	self._gmCommandService = dependencies.GMCommandService
	self._specialEventService = dependencies.SpecialEventService
	self._placementService = BrainrotPlacementService.new({
		brainrotById = BrainrotConfig.ById,
		normalizeBrainrotLevel = normalizeBrainrotLevel,
		roundEconomicValue = roundBrainrotEconomicValue,
		getProductionSpeed = getBrainrotProductionSpeed,
		getUpgradeCost = getBrainrotUpgradeCost,
		buildInventoryItemSnapshot = buildInventoryItemSnapshot,
		getPlacedAt = function()
			return os.time()
		end,
	})
	self._inventoryService = BrainrotInventoryService.new({
		brainrotById = BrainrotConfig.ById,
		starterBrainrotIds = BrainrotConfig.StarterBrainrotIds,
		getBaseBrainrotLevel = getBaseBrainrotLevel,
		normalizeBrainrotLevel = normalizeBrainrotLevel,
		findInventoryIndexByInstanceId = findInventoryIndexByInstanceId,
		buildInventoryItemSnapshot = buildInventoryItemSnapshot,
		getOrCreateProductionSlot = function(productionState, positionKey)
			return self:_getOrCreateProductionSlot(productionState, positionKey)
		end,
		resetProductionSlotValues = function(slot)
			self:_resetProductionSlotValues(slot)
		end,
	})
	self._stateStore = BrainrotStateStore.new({
		playerDataService = self._playerDataService,
		normalizeBrainrotLevel = normalizeBrainrotLevel,
		normalizeCarryUpgradeLevel = normalizeCarryUpgradeLevel,
		hydrateUnlockedBrainrotMap = function(brainrotData)
			self:_getOrCreateUnlockedBrainrotMap(brainrotData)
		end,
	})
	self._remoteEventService = dependencies.RemoteEventService
	self._weaponKnockbackService = dependencies.WeaponKnockbackService
	self._receiptHandlers = type(dependencies.ReceiptHandlers) == "table" and dependencies.ReceiptHandlers or {}

	self._brainrotStateSyncEvent = self:_resolveBrainrotEvent("BrainrotStateSync")
	self._requestBrainrotStateSyncEvent = self:_resolveBrainrotEvent("RequestBrainrotStateSync")
	self._requestBrainrotUpgradeEvent = self:_resolveBrainrotEvent("RequestBrainrotUpgrade")
	self._brainrotUpgradeFeedbackEvent = self:_resolveBrainrotEvent("BrainrotUpgradeFeedback")
	self._requestBrainrotSellEvent = self:_resolveBrainrotEvent("RequestBrainrotSell")
	self._brainrotSellFeedbackEvent = self:_resolveBrainrotEvent("BrainrotSellFeedback")
	self._requestStudioBrainrotGrantEvent = self:_resolveBrainrotEvent("RequestStudioBrainrotGrant")
	self._studioBrainrotGrantFeedbackEvent = self:_resolveBrainrotEvent("StudioBrainrotGrantFeedback")
	self._claimCashFeedbackEvent = self:_resolveSystemEvent("ClaimCashFeedback")
	self._promptBrainrotStealPurchaseEvent = self:_resolveBrainrotEvent("PromptBrainrotStealPurchase")
	self._requestBrainrotStealPurchaseClosedEvent = self:_resolveBrainrotEvent("RequestBrainrotStealPurchaseClosed")
	self._brainrotStealFeedbackEvent = self:_resolveBrainrotEvent("BrainrotStealFeedback")
	self._requestCarryUpgradeEvent = self:_resolveBrainrotEvent("RequestCarryUpgrade")
	self._carryUpgradeFeedbackEvent = self:_resolveBrainrotEvent("CarryUpgradeFeedback")
	self._bossStateSyncEvent = self:_resolveBrainrotEvent("BossStateSync")
	self._requestDropCarriedWorldBrainrotEvent = self:_resolveBrainrotEvent("RequestDropCarriedWorldBrainrot")
	self._bossWarningEvent = self:_resolveBrainrotEvent("BossWarning")
	self._bossKnockbackEvent = self:_resolveBrainrotEvent("BossKnockback")
	self._stealTipEvent = self:_resolveSystemEvent("StealTip")
	self._brainrotClaimTipEvent = self:_resolveSystemEvent("BrainrotClaimTip")
	self:_rebuildBrainrotStealProductIdLookup()

	if self._requestBrainrotStateSyncEvent then
		self._requestBrainrotStateSyncEvent.OnServerEvent:Connect(function(player)
			self:PushBrainrotState(player)
			self:_pushBossStateSync(player)
		end)
	end

	if self._requestBrainrotUpgradeEvent then
		self._requestBrainrotUpgradeEvent.OnServerEvent:Connect(function(player, payload)
			self:_handleRequestBrainrotUpgrade(player, payload)
		end)
	end

	if self._requestBrainrotSellEvent then
		self._requestBrainrotSellEvent.OnServerEvent:Connect(function(player, payload)
			self:_handleRequestBrainrotSell(player, payload)
		end)
	end

	if self._requestStudioBrainrotGrantEvent then
		self._requestStudioBrainrotGrantEvent.OnServerEvent:Connect(function(player, payload)
			self:_handleRequestStudioBrainrotGrant(player, payload)
		end)
	end

	if self._requestBrainrotStealPurchaseClosedEvent then
		self._requestBrainrotStealPurchaseClosedEvent.OnServerEvent:Connect(function(player, payload)
			self:_handleRequestBrainrotStealPurchaseClosed(player, payload)
		end)
	end

	if self._requestCarryUpgradeEvent then
		self._requestCarryUpgradeEvent.OnServerEvent:Connect(function(player, payload)
			self:_handleRequestCarryUpgrade(player, payload)
		end)
	end

	if self._requestDropCarriedWorldBrainrotEvent then
		self._requestDropCarriedWorldBrainrotEvent.OnServerEvent:Connect(function(player)
			local rootPart = getCharacterRootPart(player and player.Character)
			local dropPosition = rootPart and rootPart.Position or nil
			self:_dropCarriedWorldBrainrot(player, "ManualDropButton", dropPosition)
			self:_refreshBossCarryStateForPlayer(player)
			self:_refreshBossTargetsForPlayer(player)
		end)
	end

	if not self._processReceiptDispatcher then
		self._processReceiptDispatcher = function(receiptInfo)
			local handled, decision = self:_processBrainrotStealReceipt(receiptInfo)
			if handled then
				return decision
			end

			handled, decision = self:_processCarryUpgradeReceipt(receiptInfo)
			if handled then
				return decision
			end

			for _, receiptHandler in ipairs(self._receiptHandlers or {}) do
				if type(receiptHandler) == "table" and type(receiptHandler.ProcessReceipt) == "function" then
					local externalHandled, externalDecision = receiptHandler:ProcessReceipt(receiptInfo)
					if externalHandled then
						return externalDecision
					end
				end
			end

			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end
	MarketplaceService.ProcessReceipt = self._processReceiptDispatcher

	if not self._productionThread then
		self._productionThread = task.spawn(function()
			while true do
				task.wait(1)
				self:_tickProduction()
			end
		end)
	end

	if not self._worldSpawnThread then
		self._worldSpawnThread = task.spawn(function()
			-- 启动时清理上次 playtest 遗留的孤儿 WorldSpawn 实例。
			-- 这些实例不在 _worldSpawnEntriesById 中，tick 循环无法感知它们，
			-- 会导致旧 brainrot 永远不消失且不断累积。
			local runtimeFolder = Workspace:FindFirstChild(self:_getWorldSpawnConfig().runtimeFolderName)
			if runtimeFolder then
				for _, child in ipairs(runtimeFolder:GetChildren()) do
					child:Destroy()
				end
			end

			self:_tickWorldSpawnSystem()

			while true do
				task.wait(self:_getWorldSpawnConfig().checkInterval)
				self:_tickWorldSpawnSystem()
			end
		end)
	end

	if not self._bossThread then
		self._bossThread = task.spawn(function()
			self:_tickWorldSpawnBosses(getSharedClock())

			while true do
				task.wait(self:_getBossConfig().tickInterval)
				self:_tickWorldSpawnBosses(getSharedClock())
			end
		end)
	end
end

function BrainrotService:SetGMCommandService(gmCommandService)
	self._gmCommandService = gmCommandService
end

function BrainrotService:SetSpecialEventService(specialEventService)
	self._specialEventService = specialEventService
end

local function shouldUseSingleAnchorForAnimation(instance)
	if not instance then
		return false
	end

	-- 只要存在可动画骨架（Motor6D/Bone），就允许单锚点。
	-- 这样 Humanoid 与 AnimationController 两种动画路径都能正常驱动。
	local hasAnyBasePart = instance:FindFirstChildWhichIsA("BasePart", true) ~= nil
	if not hasAnyBasePart then
		return false
	end

	local hasMotor6D = false
	local hasBone = false
	for _, descendant in ipairs(instance:GetDescendants()) do
		if not hasMotor6D and descendant:IsA("Motor6D") then
			hasMotor6D = true
		end
		if not hasBone and descendant:IsA("Bone") then
			hasBone = true
		end

		if hasMotor6D and hasBone then
			break
		end
	end

	return hasMotor6D or hasBone
end

local function disablePlacedDirectInteraction(instance)
	if not instance then
		return
	end

	local nodes = { instance }
	for _, descendant in ipairs(instance:GetDescendants()) do
		table.insert(nodes, descendant)
	end

	for _, node in ipairs(nodes) do
		if node:IsA("ProximityPrompt") then
			node.Enabled = false
		elseif node:IsA("ClickDetector") then
			node.MaxActivationDistance = 0
		end
	end
end

local function convertPlacedToolCloneToModel(toolClone, preferredModelName)
	if not (toolClone and toolClone:IsA("Tool")) then
		return toolClone
	end

	local model = Instance.new("Model")
	model.Name = toolClone.Name

	for attributeName, attributeValue in pairs(toolClone:GetAttributes()) do
		model:SetAttribute(attributeName, attributeValue)
	end

	for _, child in ipairs(toolClone:GetChildren()) do
		child.Parent = model
	end

	local primaryPart = nil
	if type(preferredModelName) == "string" and preferredModelName ~= "" then
		local preferredNode = model:FindFirstChild(preferredModelName, true)
		if preferredNode and preferredNode:IsA("Model") then
			primaryPart = getPreferredModelBasePart(preferredNode)
		elseif preferredNode and preferredNode:IsA("BasePart") then
			primaryPart = preferredNode
		end
	end

	if not primaryPart then
		local brainrotModel = model:FindFirstChild("BrainrotModel", true)
		if brainrotModel and brainrotModel:IsA("Model") then
			primaryPart = getPreferredModelBasePart(brainrotModel)
		end
	end

	if not primaryPart then
		primaryPart = getPreferredModelBasePart(model)
	end

	if primaryPart then
		model.PrimaryPart = primaryPart
	end

	toolClone:Destroy()
	return model
end

function BrainrotService:_createPlacedModel(attachment, brainrotDefinition, brainrotLevel)
	local template = self:_getBrainrotModelTemplate(brainrotDefinition.ModelPath)
	if not template then
		warn(string.format("[BrainrotService] 找不到脑红模型: %s", tostring(brainrotDefinition.ModelPath)))
		return nil
	end

	local runtimeFolder = attachment.Parent:FindFirstChild(GameConfig.BRAINROT.RuntimeFolderName)
	if not runtimeFolder then
		runtimeFolder = Instance.new("Folder")
		runtimeFolder.Name = GameConfig.BRAINROT.RuntimeFolderName
		runtimeFolder.Parent = attachment.Parent
	end

	local placedInstance = template:Clone()
	local offsetY = tonumber(GameConfig.BRAINROT.ModelPlacementOffsetY) or 0
	local targetPosition = attachment.WorldPosition + Vector3.new(0, offsetY, 0)
	local targetYawCFrame = makeYawOnlyCFrame(attachment.WorldCFrame, targetPosition)
	if not targetYawCFrame then
		placedInstance:Destroy()
		warn(string.format("[BrainrotService] 无法计算目标朝向: %s", tostring(brainrotDefinition.ModelPath)))
		return nil
	end

	if placedInstance:IsA("Tool") then
		local _qualityFolderName, preferredModelName = parseModelPath(brainrotDefinition.ModelPath)
		local pivotCFrame, pivotPart = getToolPivotCFrame(placedInstance, preferredModelName)
		if not pivotCFrame then
			placedInstance:Destroy()
			warn(string.format("[BrainrotService] Tool 模型缺少有效轴点（子Model/Handle/BasePart）: %s", tostring(brainrotDefinition.ModelPath)))
			return nil
		end

		local baseParts = {}
		for _, descendant in ipairs(placedInstance:GetDescendants()) do
			if descendant:IsA("BasePart") then
				table.insert(baseParts, descendant)
			elseif descendant:IsA("ProximityPrompt") then
				descendant.Enabled = false
			elseif descendant:IsA("ClickDetector") then
				descendant.MaxActivationDistance = 0
			elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
				descendant.Disabled = true
			end
		end

		if #baseParts == 0 then
			placedInstance:Destroy()
			warn(string.format("[BrainrotService] Tool 模型内无可放置 BasePart: %s", tostring(brainrotDefinition.ModelPath)))
			return nil
		end

		local sourceYawCFrame = makeYawOnlyCFrame(pivotCFrame, pivotCFrame.Position, targetYawCFrame.LookVector)
		if not sourceYawCFrame then
			placedInstance:Destroy()
			warn(string.format("[BrainrotService] Tool 模型无法计算源朝向: %s", tostring(brainrotDefinition.ModelPath)))
			return nil
		end

		local deltaCFrame = targetYawCFrame * sourceYawCFrame:Inverse()
		for _, basePart in ipairs(baseParts) do
			basePart.CFrame = deltaCFrame * basePart.CFrame
		end

		local anchorPart = nil
		if pivotPart and pivotPart:IsA("BasePart") then
			anchorPart = pivotPart
		end
		if not anchorPart then
			local humanoidRootPart = placedInstance:FindFirstChild("HumanoidRootPart", true)
			if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
				anchorPart = humanoidRootPart
			end
		end
		if not anchorPart then
			local rootPart = placedInstance:FindFirstChild("RootPart", true)
			if rootPart and rootPart:IsA("BasePart") then
				anchorPart = rootPart
			end
		end
		if not anchorPart then
			local handle = placedInstance:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				anchorPart = handle
			end
		end
		if not anchorPart then
			anchorPart = baseParts[1]
		end

		local useSingleAnchor = shouldUseSingleAnchorForAnimation(placedInstance)
		for _, basePart in ipairs(baseParts) do
			basePart.CanCollide = false
			basePart.CanTouch = false
			basePart.CanQuery = false
			basePart.Anchored = not useSingleAnchor or (basePart == anchorPart)
		end

		-- 放在场景里的脑红必须是纯展示实例，不能保留 Tool 类，否则玩家靠近 Handle 会触发 Roblox 默认拾取。
		placedInstance = convertPlacedToolCloneToModel(placedInstance, preferredModelName)
	elseif placedInstance:IsA("Model") then
		local primaryPart = getPreferredModelBasePart(placedInstance)
		if not primaryPart then
			placedInstance:Destroy()
			warn(string.format("[BrainrotService] 脑红模型缺少 BasePart: %s", tostring(brainrotDefinition.ModelPath)))
			return nil
		end

		placedInstance.PrimaryPart = primaryPart

		local useSingleAnchor = shouldUseSingleAnchorForAnimation(placedInstance)
		for _, descendant in ipairs(placedInstance:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.CanCollide = false
				descendant.CanTouch = false
				descendant.CanQuery = false
				descendant.Anchored = not useSingleAnchor or (descendant == primaryPart)
			elseif descendant:IsA("ProximityPrompt") then
				descendant.Enabled = false
			elseif descendant:IsA("ClickDetector") then
				descendant.MaxActivationDistance = 0
			elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
				descendant.Disabled = true
			end
		end

		local currentPivot = placedInstance:GetPivot()
		local sourceYawCFrame = makeYawOnlyCFrame(currentPivot, currentPivot.Position, targetYawCFrame.LookVector)
		if sourceYawCFrame then
			local deltaCFrame = targetYawCFrame * sourceYawCFrame:Inverse()
			placedInstance:PivotTo(deltaCFrame * currentPivot)
		else
			local positionedPivot = setCFramePosition(currentPivot, targetPosition)
			if positionedPivot then
				placedInstance:PivotTo(positionedPivot)
			end
		end
	elseif placedInstance:IsA("BasePart") then
		placedInstance.Anchored = true
		placedInstance.CanCollide = false
		placedInstance.CanTouch = false
		placedInstance.CanQuery = false
		local partYawCFrame = makeYawOnlyCFrame(placedInstance.CFrame, targetPosition, targetYawCFrame.LookVector)
		if partYawCFrame then
			placedInstance.CFrame = partYawCFrame
		else
			local positionedPartCFrame = setCFramePosition(placedInstance.CFrame, targetPosition)
			if positionedPartCFrame then
				placedInstance.CFrame = positionedPartCFrame
			end
		end
		for _, descendant in ipairs(placedInstance:GetDescendants()) do
			if descendant:IsA("ProximityPrompt") then
				descendant.Enabled = false
			elseif descendant:IsA("ClickDetector") then
				descendant.MaxActivationDistance = 0
			elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
				descendant.Disabled = true
			end
		end
	else
		placedInstance:Destroy()
		warn(string.format("[BrainrotService] 不支持放置的脑红实例类型: %s", placedInstance.ClassName))
		return nil
	end

	disablePlacedDirectInteraction(placedInstance)

	placedInstance.Name = string.format("PlacedBrainrot_%d", brainrotDefinition.Id)
	placedInstance.Parent = runtimeFolder

	self:_attachPlacedInfoUi(placedInstance, brainrotDefinition, brainrotLevel)

	return placedInstance
end

function BrainrotService:_resolvePlacedPromptParent(placedInstance)
	if not placedInstance then
		return nil
	end

	if placedInstance:IsA("Model") then
		local primaryPart = placedInstance.PrimaryPart
		if primaryPart and primaryPart:IsA("BasePart") then
			return primaryPart
		end

		local humanoidRootPart = placedInstance:FindFirstChild("HumanoidRootPart", true)
		if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
			return humanoidRootPart
		end

		local rootPart = placedInstance:FindFirstChild("RootPart", true)
		if rootPart and rootPart:IsA("BasePart") then
			return rootPart
		end
	end

	return getFirstBasePart(placedInstance)
end

function BrainrotService:_handlePlacedBrainrotPromptTriggered(player, positionKey)
	local platformsByPositionKey = self._platformsByUserId[player.UserId]
	local platformInfo = platformsByPositionKey and platformsByPositionKey[positionKey] or nil
	if not platformInfo then
		return
	end

	if self:_getEquippedBrainrotTool(player) then
		self:_swapEquippedBrainrotWithPlaced(player, platformInfo)
	else
		self:_pickupPlacedBrainrot(player, positionKey, false)
	end
end

function BrainrotService:_handlePlacedBrainrotStealTriggered(ownerPlayer, positionKey, triggerPlayer)
	if not (ownerPlayer and triggerPlayer and positionKey) then
		return
	end

	if triggerPlayer == ownerPlayer or triggerPlayer.UserId == ownerPlayer.UserId then
		return
	end

	local existingPending = self:_getPendingStealPurchase(triggerPlayer, false)
	if existingPending then
		self:_pushBrainrotStealFeedback(triggerPlayer, "PurchasePending", {
			requestId = existingPending.RequestId,
			productId = existingPending.ProductId,
			brainrotId = existingPending.BrainrotId,
			brainrotName = existingPending.BrainrotName,
			message = "Please finish your current steal purchase first.",
		})
		return
	end

	local ownerPlayerData, _brainrotData, placedBrainrots = self:_getOrCreateDataContainers(ownerPlayer)
	if not placedBrainrots then
		self:_pushBrainrotStealFeedback(triggerPlayer, "TargetNotReady", {
			message = "The target brainrot is not ready yet.",
		})
		return
	end

	local placedData = placedBrainrots[positionKey]
	if type(placedData) ~= "table" then
		self:_pushBrainrotStealFeedback(triggerPlayer, "BrainrotUnavailable", {
			message = "This brainrot is no longer available here.",
		})
		return
	end

	local brainrotId = math.max(0, math.floor(tonumber(placedData.BrainrotId) or 0))
	local brainrotDefinition = BrainrotConfig.ById[brainrotId]
	if not brainrotDefinition then
		self:_pushBrainrotStealFeedback(triggerPlayer, "BrainrotConfigMissing", {
			brainrotId = brainrotId,
			message = "The brainrot config is missing.",
		})
		return
	end

	local developerProduct, productId = getBrainrotDeveloperProductInfo(brainrotDefinition)
	if not developerProduct then
		self:_pushBrainrotStealFeedback(triggerPlayer, "ProductMissing", {
			brainrotId = brainrotId,
			brainrotName = brainrotDefinition.Name,
			message = "This brainrot does not have a developer product yet.",
		})
		return
	end

	local ownerLastLoginAt = getPlayerMetaSessionTimestamps(ownerPlayerData)
	local pending = self:_setPendingStealPurchase(triggerPlayer, {
		RequestId = buildStealRequestId(triggerPlayer.UserId, ownerPlayer.UserId, placedData.InstanceId),
		BuyerUserId = triggerPlayer.UserId,
		OwnerUserId = ownerPlayer.UserId,
		OwnerName = ownerPlayer.Name,
		OwnerLastLoginAt = ownerLastLoginAt,
		InstanceId = math.max(0, math.floor(tonumber(placedData.InstanceId) or 0)),
		BrainrotId = brainrotId,
		BrainrotName = tostring(brainrotDefinition.Name or "Brainrot"),
		Level = normalizeBrainrotLevel(placedData.Level),
		ProductId = productId,
		PriceRobux = math.max(0, math.floor(tonumber(developerProduct.PriceRobux) or 0)),
		Quality = math.max(0, math.floor(tonumber(brainrotDefinition.Quality) or 0)),
		CreatedAt = os.time(),
	})
	if not pending then
		self:_pushBrainrotStealFeedback(triggerPlayer, "PendingCreateFailed", {
			brainrotId = brainrotId,
			brainrotName = brainrotDefinition.Name,
			message = "Unable to create the steal order right now.",
		})
		return
	end

	if not self:_promptBrainrotStealPurchase(triggerPlayer, pending) then
		self:_clearPendingStealPurchase(triggerPlayer, pending.RequestId)
		self:_pushBrainrotStealFeedback(triggerPlayer, "PromptUnavailable", {
			requestId = pending.RequestId,
			productId = pending.ProductId,
			brainrotId = pending.BrainrotId,
			brainrotName = pending.BrainrotName,
			message = "Unable to open the purchase prompt right now.",
		})
		return
	end

	if self._playerDataService then
		task.spawn(function()
			self._playerDataService:SavePlayerData(triggerPlayer)
		end)
	end
end

function BrainrotService:_attachPlacedPickupPrompt(player, positionKey, placedInstance, brainrotDefinition)
	if not (player and positionKey and placedInstance) then
		return nil
	end

	local promptParent = self:_resolvePlacedPromptParent(placedInstance)
	if not (promptParent and promptParent:IsA("BasePart")) then
		return nil
	end

	local userId = player.UserId
	self:_clearPlacedPromptForPosition(userId, positionKey)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = tostring((GameConfig.BRAINROT or {}).PlacedPickupPromptName or "PlacedPickupPrompt")
	prompt.ActionText = tostring((GameConfig.BRAINROT or {}).PlacedPickupPromptActionText or "Pick Up")
	prompt.ObjectText = tostring((brainrotDefinition and brainrotDefinition.Name) or (GameConfig.BRAINROT or {}).PlacedPickupPromptObjectText or "Brainrot")
	prompt.HoldDuration = tonumber((GameConfig.BRAINROT or {}).PromptHoldDuration) or 1
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 10
	prompt:SetAttribute(BRAINROT_PLACED_PICKUP_PROMPT_ATTRIBUTE, true)
	prompt:SetAttribute(BRAINROT_PLACED_PICKUP_OWNER_USER_ID_ATTRIBUTE, userId)
	prompt:SetAttribute(BRAINROT_PLACED_PICKUP_SERVER_ENABLED_ATTRIBUTE, true)
	prompt.Parent = promptParent

	local connection = prompt.Triggered:Connect(function(triggerPlayer)
		if triggerPlayer ~= player then
			return
		end

		self:_handlePlacedBrainrotPromptTriggered(player, positionKey)
	end)

	local promptStateByPosition = ensureTable(self._placedPromptStateByUserId, userId)
	promptStateByPosition[positionKey] = {
		Prompt = prompt,
		Connection = connection,
	}

	return prompt
end

function BrainrotService:_attachPlacedStealPrompt(player, positionKey, placedInstance, brainrotDefinition)
	if not (player and positionKey and placedInstance and brainrotDefinition) then
		return nil
	end

	local _playerData, _brainrotData, placedBrainrots = self:_getOrCreateDataContainers(player)
	local placedData = placedBrainrots and placedBrainrots[positionKey] or nil
	if type(placedData) ~= "table" then
		return nil
	end

	local _developerProduct, productId = getBrainrotDeveloperProductInfo(brainrotDefinition)
	if productId <= 0 then
		return nil
	end

	local promptParent = self:_resolvePlacedPromptParent(placedInstance)
	if not (promptParent and promptParent:IsA("BasePart")) then
		return nil
	end

	local userId = player.UserId
	self:_clearPlacedStealPromptForPosition(userId, positionKey)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = tostring((GameConfig.BRAINROT or {}).PlacedStealPromptName or "PlacedStealPrompt")
	prompt.ActionText = tostring((GameConfig.BRAINROT or {}).PlacedStealPromptActionText or "Steal")
	prompt.ObjectText = tostring((brainrotDefinition and brainrotDefinition.Name) or (GameConfig.BRAINROT or {}).PlacedStealPromptObjectText or "Brainrot")
	prompt.HoldDuration = tonumber((GameConfig.BRAINROT or {}).PlacedStealPromptHoldDuration)
		or tonumber((GameConfig.BRAINROT or {}).PromptHoldDuration)
		or 1
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = tonumber((GameConfig.BRAINROT or {}).PlacedStealPromptMaxActivationDistance) or 10
	prompt:SetAttribute(BRAINROT_STEAL_PROMPT_ATTRIBUTE, true)
	prompt:SetAttribute(BRAINROT_STEAL_OWNER_USER_ID_ATTRIBUTE, userId)
	prompt:SetAttribute(BRAINROT_STEAL_SERVER_ENABLED_ATTRIBUTE, true)
	prompt:SetAttribute(BRAINROT_STEAL_INSTANCE_ID_ATTRIBUTE, math.max(0, math.floor(tonumber(placedData.InstanceId) or 0)))
	prompt.Parent = promptParent

	local connection = prompt.Triggered:Connect(function(triggerPlayer)
		self:_handlePlacedBrainrotStealTriggered(player, positionKey, triggerPlayer)
	end)

	local promptStateByPosition = ensureTable(self._placedStealPromptStateByUserId, userId)
	promptStateByPosition[positionKey] = {
		Prompt = prompt,
		Connection = connection,
	}

	return prompt
end

function BrainrotService:_registerPlacedRuntime(player, positionKey, placedInstance, brainrotDefinition)
	if not (player and positionKey and placedInstance) then
		return
	end

	local runtimePlaced = ensureTable(self._runtimePlacedByUserId, player.UserId)
	runtimePlaced[positionKey] = placedInstance
	self:_playIdleAnimationForPlaced(player, positionKey, placedInstance, brainrotDefinition)
	self:_attachPlacedPickupPrompt(player, positionKey, placedInstance, brainrotDefinition)
	self:_attachPlacedStealPrompt(player, positionKey, placedInstance, brainrotDefinition)
end

function BrainrotService:_destroyRuntimePlacedAtPosition(player, positionKey)
	if not (player and positionKey) then
		return
	end

	local userId = player.UserId
	self:_stopIdleTrack(player, positionKey)
	self:_clearPlacedPromptForPosition(userId, positionKey)
	self:_clearPlacedStealPromptForPosition(userId, positionKey)
	self:_clearClaimBounceState(userId, positionKey, false)

	local runtimePlaced = self._runtimePlacedByUserId[userId]
	if type(runtimePlaced) ~= "table" then
		return
	end

	local runtimeInstance = runtimePlaced[positionKey]
	if runtimeInstance and runtimeInstance.Parent then
		runtimeInstance:Destroy()
	end
	runtimePlaced[positionKey] = nil
	if next(runtimePlaced) == nil then
		self._runtimePlacedByUserId[userId] = nil
	end
end

function BrainrotService:_pickupPlacedBrainrot(player, positionKey, shouldEquipAfterRefresh)
	local _playerData, brainrotData, placedBrainrots, productionState = self:_getOrCreateDataContainers(player)
	if not brainrotData or not placedBrainrots or not productionState then
		return false, nil
	end

	local success, reason, pickupResult = self:_requirePlacementService():PickupPlacedBrainrotData(
		brainrotData,
		placedBrainrots,
		productionState,
		positionKey
	)

	if not success then
		if reason == "NoBrainrot" or placedBrainrots[positionKey] == nil then
			self:_refreshPlatformPromptState(player, positionKey, placedBrainrots)
		end
		return false, nil
	end

	local inventoryItem = pickupResult and pickupResult.inventoryItem or nil
	if type(inventoryItem) ~= "table" then
		return false, nil
	end

	self:_destroyRuntimePlacedAtPosition(player, positionKey)
	self:_refreshBrainrotTools(player)

	if shouldEquipAfterRefresh == true then
		task.defer(function()
			self:_equipBrainrotToolByInstanceId(player, inventoryItem.InstanceId)
		end)
	end

	self:PushBrainrotState(player)
	self:_refreshClaimUiForPosition(player, positionKey, placedBrainrots, productionState)
	self:_refreshBrandUiForPosition(player, positionKey, placedBrainrots)
	self:_refreshPlatformPromptState(player, positionKey, placedBrainrots)
	self:_updatePlayerTotalProductionSpeed(player, placedBrainrots)
	return true, inventoryItem
end

function BrainrotService:_swapEquippedBrainrotWithPlaced(player, platformInfo)
	local _playerData, brainrotData, placedBrainrots, productionState = self:_getOrCreateDataContainers(player)
	if not brainrotData or not placedBrainrots or not productionState then
		return false
	end

	local positionKey = platformInfo and platformInfo.PositionKey or nil
	local placedData = positionKey and placedBrainrots[positionKey] or nil
	if type(placedData) ~= "table" then
		return false
	end

	local equippedTool = self:_getEquippedBrainrotTool(player)
	if not equippedTool then
		return false
	end

	local equippedInstanceId = tonumber(equippedTool:GetAttribute("BrainrotInstanceId"))
	local equippedBrainrotId = tonumber(equippedTool:GetAttribute("BrainrotId"))
	if not equippedInstanceId or not equippedBrainrotId then
		return false
	end

	local inventoryIndex = findInventoryIndexByInstanceId(brainrotData.Inventory, equippedInstanceId)
	if not inventoryIndex then
		return false
	end

	local equippedInventoryItem = brainrotData.Inventory[inventoryIndex]
	if tonumber(equippedInventoryItem.BrainrotId) ~= equippedBrainrotId then
		return false
	end

	local equippedDefinition = BrainrotConfig.ById[equippedBrainrotId]
	local placedBrainrotId = tonumber(placedData.BrainrotId)
	local placedDefinition = placedBrainrotId and BrainrotConfig.ById[placedBrainrotId] or nil
	if not equippedDefinition or not placedDefinition then
		return false
	end

	local pickupInventoryItem = buildInventoryItemSnapshot(placedData.InstanceId, placedData.BrainrotId, placedData.Level)
	self:_destroyRuntimePlacedAtPosition(player, positionKey)

	local placedModel = self:_createPlacedModel(platformInfo.Attachment, equippedDefinition, equippedInventoryItem.Level)
	if not placedModel then
		local restoredModel = self:_createPlacedModel(platformInfo.Attachment, placedDefinition, placedData.Level)
		if restoredModel then
			self:_registerPlacedRuntime(player, positionKey, restoredModel, placedDefinition)
		end
		self:_refreshClaimUiForPosition(player, positionKey, placedBrainrots, productionState)
		self:_refreshBrandUiForPosition(player, positionKey, placedBrainrots)
		self:_refreshPlatformPromptState(player, positionKey, placedBrainrots)
		return false
	end

	local swapSuccess, _swapReason, swapResult = self:_requirePlacementService():SwapPlacedWithInventoryItem(
		brainrotData,
		placedBrainrots,
		productionState,
		inventoryIndex,
		positionKey
	)

	if not swapSuccess then
		placedModel:Destroy()
		local restoredModel = self:_createPlacedModel(platformInfo.Attachment, placedDefinition, placedData.Level)
		if restoredModel then
			self:_registerPlacedRuntime(player, positionKey, restoredModel, placedDefinition)
		end
		self:_refreshClaimUiForPosition(player, positionKey, placedBrainrots, productionState)
		self:_refreshBrandUiForPosition(player, positionKey, placedBrainrots)
		self:_refreshPlatformPromptState(player, positionKey, placedBrainrots)
		return false
	end

	local swapPickupItem = swapResult and swapResult.pickupInventoryItem or pickupInventoryItem
	self:_registerPlacedRuntime(player, positionKey, placedModel, equippedDefinition)
	self:_refreshBrainrotTools(player)

	task.defer(function()
		self:_equipBrainrotToolByInstanceId(player, swapPickupItem.InstanceId)
	end)

	self:PushBrainrotState(player)
	self:_refreshClaimUiForPosition(player, positionKey, placedBrainrots, productionState)
	self:_refreshBrandUiForPosition(player, positionKey, placedBrainrots)
	self:_refreshPlatformPromptState(player, positionKey, placedBrainrots)
	self:_updatePlayerTotalProductionSpeed(player, placedBrainrots)
	return true
end

function BrainrotService:_placeEquippedBrainrot(player, platformInfo)
	local playerData, brainrotData, placedBrainrots, productionState = self:_getOrCreateDataContainers(player)
	if not playerData or not brainrotData or not placedBrainrots or not productionState then
		return
	end

	local positionKey = platformInfo.PositionKey
	local existingPlaced = placedBrainrots[positionKey]
	if existingPlaced then
		local runtimePlaced = self._runtimePlacedByUserId[player.UserId]
		local runtimeInstance = runtimePlaced and runtimePlaced[positionKey] or nil
		local existingBrainrotId = tonumber(existingPlaced.BrainrotId)
		local existingDefinition = existingBrainrotId and BrainrotConfig.ById[existingBrainrotId] or nil
		if runtimeInstance and runtimeInstance.Parent then
			if existingDefinition then
				self:_attachPlacedPickupPrompt(player, positionKey, runtimeInstance, existingDefinition)
				self:_attachPlacedStealPrompt(player, positionKey, runtimeInstance, existingDefinition)
			end
			self:_refreshPlatformPromptState(player, positionKey, placedBrainrots)
			return
		end

		if existingDefinition then
			local recoveredModel = self:_createPlacedModel(platformInfo.Attachment, existingDefinition, existingPlaced.Level)
			if recoveredModel then
				self:_registerPlacedRuntime(player, positionKey, recoveredModel, existingDefinition)
				self:_refreshClaimUiForPosition(player, positionKey, placedBrainrots, productionState)
				self:_refreshBrandUiForPosition(player, positionKey, placedBrainrots)
				self:_refreshPlatformPromptState(player, positionKey, placedBrainrots)
				return
			end
		end

		-- 兜底：旧脏数据阻塞放置时，自动清理占位，避免永远无法放置
		self:_requirePlacementService():ClearPlacedPositionState(placedBrainrots, productionState, positionKey)
		self:_refreshBrandUiForPosition(player, positionKey, placedBrainrots)
		self:_refreshPlatformPromptState(player, positionKey, placedBrainrots)
	end

	local equippedTool = self:_getEquippedBrainrotTool(player)
	if not equippedTool then
		return
	end

	local instanceId = tonumber(equippedTool:GetAttribute("BrainrotInstanceId"))
	local brainrotId = tonumber(equippedTool:GetAttribute("BrainrotId"))
	if not instanceId or not brainrotId then
		return
	end

	local inventoryIndex = findInventoryIndexByInstanceId(brainrotData.Inventory, instanceId)
	if not inventoryIndex then
		return
	end

	local inventoryItem = brainrotData.Inventory[inventoryIndex]
	if tonumber(inventoryItem.BrainrotId) ~= brainrotId then
		return
	end

	local brainrotDefinition = BrainrotConfig.ById[brainrotId]
	if not brainrotDefinition then
		return
	end

	local placedModel = self:_createPlacedModel(platformInfo.Attachment, brainrotDefinition, inventoryItem.Level)
	if not placedModel then
		return
	end

	local didPlaceData = select(1, self:_requirePlacementService():PlaceInventoryItemAtPosition(
		brainrotData,
		placedBrainrots,
		productionState,
		inventoryIndex,
		positionKey
	))

	if not didPlaceData then
		placedModel:Destroy()
		return
	end

	self:_registerPlacedRuntime(player, positionKey, placedModel, brainrotDefinition)

	equippedTool:Destroy()
	self:PushBrainrotState(player)
	self:_refreshClaimUiForPosition(player, positionKey, placedBrainrots, productionState)
	self:_refreshBrandUiForPosition(player, positionKey, placedBrainrots)
	self:_refreshPlatformPromptState(player, positionKey, placedBrainrots)
	self:_updatePlayerTotalProductionSpeed(player, placedBrainrots)
end

function BrainrotService:_clearClaimBounceState(userId, positionKey, restoreToBase)
	local claimBounceByPosition = self._claimBounceStateByUserId[userId]
	if type(claimBounceByPosition) ~= "table" then
		return
	end

	local state = claimBounceByPosition[positionKey]
	if type(state) ~= "table" then
		return
	end

	claimBounceByPosition[positionKey] = nil

	if state.CurrentTween then
		state.CurrentTween:Cancel()
		state.CurrentTween = nil
	end

	if state.Connection then
		state.Connection:Disconnect()
		state.Connection = nil
	end

	if restoreToBase and state.Target and state.Target.Parent and state.BasePivot then
		setInstancePivotCFrame(state.Target, state.BasePivot)
	end

	if state.PivotValue then
		state.PivotValue:Destroy()
		state.PivotValue = nil
	end
end

function BrainrotService:_getClaimTouchEffectTemplate()
	local rootName = tostring(GameConfig.BRAINROT.ClaimTouchEffectRootName or "Effect")
	local claimFolderName = tostring(GameConfig.BRAINROT.ClaimTouchEffectFolderName or "Claim")

	local effectRoot = ReplicatedStorage:FindFirstChild(rootName)
	local claimFolder = effectRoot and effectRoot:FindFirstChild(claimFolderName) or nil
	if claimFolder then
		return claimFolder
	end

	if not self._didWarnMissingClaimEffectTemplate then
		warn(string.format("[BrainrotService] 找不到领取特效模板目录: ReplicatedStorage/%s/%s", rootName, claimFolderName))
		self._didWarnMissingClaimEffectTemplate = true
	end

	return nil
end

function BrainrotService:_destroyClaimTouchEffectForPosition(userId, positionKey)
	local claimEffectByPosition = self._claimEffectByUserId[userId]
	if type(claimEffectByPosition) ~= "table" then
		return
	end

	local runtimeNodes = claimEffectByPosition[positionKey]
	if type(runtimeNodes) == "table" then
		for _, node in pairs(runtimeNodes) do
			if node and node.Parent then
				node:Destroy()
			end
		end
	elseif runtimeNodes and runtimeNodes.Parent then
		runtimeNodes:Destroy()
	end

	claimEffectByPosition[positionKey] = nil
end

function BrainrotService:_playClaimPressAnimation(claimInfo)
	local pressPart = claimInfo and (claimInfo.TouchPart or claimInfo.ClaimPart)
	if not (pressPart and pressPart.Parent and pressPart:IsA("BasePart")) then
		return
	end

	local isTouchPart = claimInfo and claimInfo.TouchPart == pressPart
	local baseCFrame = nil
	if isTouchPart then
		baseCFrame = claimInfo.TouchBaseCFrame or pressPart.CFrame
		claimInfo.TouchBaseCFrame = baseCFrame
	else
		baseCFrame = claimInfo.ClaimBaseCFrame or pressPart.CFrame
		claimInfo.ClaimBaseCFrame = baseCFrame
	end

	claimInfo._pressAnimationToken = (tonumber(claimInfo._pressAnimationToken) or 0) + 1
	local currentToken = claimInfo._pressAnimationToken

	if claimInfo._currentPressTween then
		claimInfo._currentPressTween:Cancel()
		claimInfo._currentPressTween = nil
	end

	if claimInfo._touchHighlightTween then
		claimInfo._touchHighlightTween:Cancel()
		claimInfo._touchHighlightTween = nil
	end

	if claimInfo._touchHighlight then
		claimInfo._touchHighlight:Destroy()
		claimInfo._touchHighlight = nil
	end

	local highlight = nil
	if isTouchPart and GameConfig.BRAINROT.ClaimTouchHighlightEnabled ~= false then
		highlight = Instance.new("Highlight")
		highlight.Name = "ClaimTouchHighlight"
		highlight.Adornee = pressPart
		highlight.DepthMode = GameConfig.BRAINROT.ClaimTouchHighlightAlwaysOnTop == true
			and Enum.HighlightDepthMode.AlwaysOnTop
			or Enum.HighlightDepthMode.Occluded
		highlight.FillColor = GameConfig.BRAINROT.ClaimTouchHighlightFillColor or Color3.fromRGB(255, 235, 130)
		highlight.FillTransparency = math.clamp(tonumber(GameConfig.BRAINROT.ClaimTouchHighlightFillTransparency) or 0.55, 0, 1)
		highlight.OutlineColor = GameConfig.BRAINROT.ClaimTouchHighlightOutlineColor or Color3.fromRGB(255, 255, 255)
		highlight.OutlineTransparency = math.clamp(tonumber(GameConfig.BRAINROT.ClaimTouchHighlightOutlineTransparency) or 0.08, 0, 1)
		highlight.Parent = pressPart
		claimInfo._touchHighlight = highlight
	end

	pressPart.CFrame = baseCFrame

	local pressOffset = math.max(0.05, tonumber(GameConfig.BRAINROT.ClaimPressOffsetY) or 0.2)
	local downDuration = math.max(0.03, tonumber(GameConfig.BRAINROT.ClaimPressDownDuration) or 0.08)
	local upDuration = math.max(0.03, tonumber(GameConfig.BRAINROT.ClaimPressUpDuration) or 0.14)

	local downTween = TweenService:Create(pressPart, TweenInfo.new(downDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = baseCFrame * CFrame.new(0, -pressOffset, 0),
	})
	claimInfo._currentPressTween = downTween
	downTween:Play()

	task.spawn(function()
		downTween.Completed:Wait()
		if claimInfo._pressAnimationToken ~= currentToken then
			return
		end

		local upTween = TweenService:Create(pressPart, TweenInfo.new(upDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			CFrame = baseCFrame,
		})
		claimInfo._currentPressTween = upTween
		upTween:Play()
		upTween.Completed:Wait()

		if claimInfo._pressAnimationToken ~= currentToken then
			return
		end

		claimInfo._currentPressTween = nil
		if pressPart.Parent then
			pressPart.CFrame = baseCFrame
		end

		local activeHighlight = claimInfo._touchHighlight
		if activeHighlight and activeHighlight.Parent then
			local fadeOutDuration = math.max(0.03, tonumber(GameConfig.BRAINROT.ClaimTouchHighlightFadeOutDuration) or 0.12)
			local fadeTween = TweenService:Create(activeHighlight, TweenInfo.new(fadeOutDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				FillTransparency = 1,
				OutlineTransparency = 1,
			})
			claimInfo._touchHighlightTween = fadeTween
			fadeTween:Play()
			fadeTween.Completed:Wait()

			if claimInfo._touchHighlightTween == fadeTween then
				claimInfo._touchHighlightTween = nil
			end
		end

		if claimInfo._touchHighlight == activeHighlight then
			claimInfo._touchHighlight = nil
		end
		if activeHighlight and activeHighlight.Parent then
			activeHighlight:Destroy()
		end
	end)
end

function BrainrotService:_playClaimBounceAnimation(player, positionKey)
	local userId = player.UserId
	local runtimePlaced = self._runtimePlacedByUserId[userId]
	if type(runtimePlaced) ~= "table" then
		return
	end

	local target = runtimePlaced[positionKey]
	if not target then
		return
	end

	self:_clearClaimBounceState(userId, positionKey, true)

	local basePivot = select(1, getInstancePivotCFrame(target))
	if not basePivot then
		return
	end

	local claimBounceByPosition = ensureTable(self._claimBounceStateByUserId, userId)
	local state = {
		Target = target,
		BasePivot = basePivot,
		CurrentTween = nil,
		Connection = nil,
		PivotValue = nil,
	}
	claimBounceByPosition[positionKey] = state

	local pivotValue = Instance.new("CFrameValue")
	pivotValue.Value = basePivot
	state.PivotValue = pivotValue
	state.Connection = pivotValue:GetPropertyChangedSignal("Value"):Connect(function()
		if state.Target and state.Target.Parent then
			setInstancePivotCFrame(state.Target, pivotValue.Value)
		end
	end)

	local bounceOffset = math.max(0.05, tonumber(GameConfig.BRAINROT.ClaimBrainrotBounceOffsetY) or 0.75)
	local upDuration = math.max(0.03, tonumber(GameConfig.BRAINROT.ClaimBrainrotBounceUpDuration) or 0.1)
	local downDuration = math.max(0.03, tonumber(GameConfig.BRAINROT.ClaimBrainrotBounceDownDuration) or 0.18)

	local upTween = TweenService:Create(pivotValue, TweenInfo.new(upDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Value = setCFramePosition(basePivot, basePivot.Position + Vector3.new(0, bounceOffset, 0)),
	})
	state.CurrentTween = upTween
	upTween:Play()

	task.spawn(function()
		upTween.Completed:Wait()
		local activeByPosition = self._claimBounceStateByUserId[userId]
		if not (activeByPosition and activeByPosition[positionKey] == state) then
			return
		end

		local downTween = TweenService:Create(pivotValue, TweenInfo.new(downDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Value = basePivot,
		})
		state.CurrentTween = downTween
		downTween:Play()
		downTween.Completed:Wait()

		local latestByPosition = self._claimBounceStateByUserId[userId]
		if latestByPosition and latestByPosition[positionKey] == state then
			self:_clearClaimBounceState(userId, positionKey, true)
		end
	end)
end

function BrainrotService:_playClaimTouchEffect(player, claimInfo)
	local effectAnchorPart = claimInfo and claimInfo.TouchPart
	if not (effectAnchorPart and effectAnchorPart.Parent and effectAnchorPart:IsA("BasePart") and claimInfo and claimInfo.PositionKey) then
		return
	end

	local userId = player.UserId
	local positionKey = tostring(claimInfo.PositionKey)
	self:_destroyClaimTouchEffectForPosition(userId, positionKey)

	local templateFolder = self:_getClaimTouchEffectTemplate()
	if not templateFolder then
		return
	end

	local claimEffectByPosition = ensureTable(self._claimEffectByUserId, userId)
	local runtimeNodes = {}
	claimEffectByPosition[positionKey] = runtimeNodes

	local function trackRuntimeNode(node)
		if node then
			table.insert(runtimeNodes, node)
		end
		return node
	end

	local function findTemplateEmitter(emitterName)
		local direct = templateFolder:FindFirstChild(emitterName)
		if direct and direct:IsA("ParticleEmitter") then
			return direct
		end

		local nested = templateFolder:FindFirstChild(emitterName, true)
		if nested and nested:IsA("ParticleEmitter") then
			return nested
		end

		return nil
	end

	local function cloneEmitterToTouch(emitterName)
		local templateEmitter = findTemplateEmitter(emitterName)
		if not templateEmitter then
			return nil
		end

		local emitter = templateEmitter:Clone()
		emitter.Enabled = false
		emitter.Parent = effectAnchorPart
		return trackRuntimeNode(emitter)
	end

	local function destroyIfCurrent(emitter)
		local latestByPosition = self._claimEffectByUserId[userId]
		if not (latestByPosition and latestByPosition[positionKey] == runtimeNodes) then
			return
		end

		if emitter and emitter.Parent then
			emitter:Destroy()
		end
	end

	local function emitOnceAndDestroyByLifetime(emitter)
		if not (emitter and emitter:IsA("ParticleEmitter")) then
			return
		end

		emitter:Emit(1)
		emitter.Enabled = false

		local maxLifetime = 0.05
		if emitter.Lifetime then
			maxLifetime = math.max(maxLifetime, tonumber(emitter.Lifetime.Max) or 0)
		end

		task.delay(maxLifetime + 0.03, function()
			destroyIfCurrent(emitter)
		end)
	end

	local function playTimedEmitter(emitter, duration)
		if not (emitter and emitter:IsA("ParticleEmitter")) then
			return
		end

		local lifetime = math.max(0.05, tonumber(duration) or 1.5)
		emitter.Enabled = true

		task.delay(lifetime, function()
			if emitter and emitter.Parent then
				emitter.Enabled = false
			end
			destroyIfCurrent(emitter)
		end)
	end

	local glowName = tostring(GameConfig.BRAINROT.ClaimTouchEffectGlowName or "Glow")
	local smokeName = tostring(GameConfig.BRAINROT.ClaimTouchEffectSmokeName or "Smoke")
	local moneyName = tostring(GameConfig.BRAINROT.ClaimTouchEffectMoneyName or "Money")
	local starsName = tostring(GameConfig.BRAINROT.ClaimTouchEffectStarsName or "Stars")
	local moneyStarsLifetime = math.max(0.1, tonumber(GameConfig.BRAINROT.ClaimTouchEffectMoneyStarsLifetime) or 1.5)

	emitOnceAndDestroyByLifetime(cloneEmitterToTouch(glowName))
	emitOnceAndDestroyByLifetime(cloneEmitterToTouch(smokeName))
	playTimedEmitter(cloneEmitterToTouch(moneyName), moneyStarsLifetime)
	playTimedEmitter(cloneEmitterToTouch(starsName), moneyStarsLifetime)

	task.delay(moneyStarsLifetime + 0.2, function()
		local latestByPosition = self._claimEffectByUserId[userId]
		if latestByPosition and latestByPosition[positionKey] == runtimeNodes then
			latestByPosition[positionKey] = nil
		end
	end)
end
function BrainrotService:_pushClaimCashFeedback(player, claimInfo)
	if not self._claimCashFeedbackEvent then
		return
	end

	local touchPart = claimInfo and claimInfo.TouchPart
	local touchPosition = (touchPart and touchPart.Parent and touchPart:IsA("BasePart")) and touchPart.Position or nil
	local touchUpVector = (touchPart and touchPart.Parent and touchPart:IsA("BasePart")) and touchPart.CFrame.UpVector or Vector3.new(0, 1, 0)
	local touchSize = (touchPart and touchPart.Parent and touchPart:IsA("BasePart")) and touchPart.Size or nil

	self._claimCashFeedbackEvent:FireClient(player, {
		positionKey = claimInfo and claimInfo.PositionKey or nil,
		claimKey = claimInfo and claimInfo.ClaimKey or nil,
		touchPosition = touchPosition,
		touchUpVector = touchUpVector,
		touchSize = touchSize,
		timestamp = os.clock(),
	})
end

function BrainrotService:_hasPlacedBrainrotAtPosition(player, positionKey)
	local _playerData, _brainrotData, placedBrainrots = self:_getOrCreateDataContainers(player)
	return type(placedBrainrots) == "table" and placedBrainrots[positionKey] ~= nil
end

function BrainrotService:_playClaimRewardFeedback(player, claimInfo)
	self:_playClaimTouchEffect(player, claimInfo)
	self:_pushClaimCashFeedback(player, claimInfo)
end

function BrainrotService:_shouldTriggerClaimByTouch(claimState, character, hitPart)
	if type(claimState.TouchingParts) ~= "table" then
		claimState.TouchingParts = {}
	end

	if not hitPart then
		return false
	end

	claimState.Character = character or claimState.Character

	if claimState.TouchingParts[hitPart] then
		return false
	end

	claimState.TouchingParts[hitPart] = true
	claimState.TouchingCount = (tonumber(claimState.TouchingCount) or 0) + 1

	-- 同一轮占用期间只允许触发一次，避免 Touch 按压动画导致的断触重触二次触发
	if claimState.IsTriggeredWhileOccupied == true then
		return false
	end

	local nowClock = os.clock()
	local lastClock = tonumber(claimState.LastTriggerClock) or 0
	local touchDebounce = math.max(0.05, tonumber(GameConfig.BRAINROT.ClaimTouchDebounceSeconds) or 0.35)
	if nowClock - lastClock < touchDebounce then
		return false
	end

	claimState.LastTriggerClock = nowClock
	claimState.IsTriggeredWhileOccupied = true
	return true
end

function BrainrotService:_handleClaimTouchEnded(claimState, hitPart)
	if type(claimState.TouchingParts) ~= "table" then
		claimState.TouchingParts = {}
	end

	if hitPart and claimState.TouchingParts[hitPart] then
		claimState.TouchingParts[hitPart] = nil
		claimState.TouchingCount = math.max(0, (tonumber(claimState.TouchingCount) or 0) - 1)
	end

	if (tonumber(claimState.TouchingCount) or 0) > 0 then
		return
	end

	claimState.TouchingParts = {}
	claimState.TouchingCount = 0

	local unlockGeneration = (tonumber(claimState.UnlockGeneration) or 0) + 1
	claimState.UnlockGeneration = unlockGeneration

	local checkInterval = 0.03

	task.spawn(function()
		while true do
			if (tonumber(claimState.UnlockGeneration) or 0) ~= unlockGeneration then
				return
			end

			if (tonumber(claimState.TouchingCount) or 0) > 0 then
				return
			end

			local triggerPart = claimState.TriggerPart
			local character = claimState.Character
			if not (triggerPart and triggerPart.Parent and character and character.Parent) then
				claimState.IsTriggeredWhileOccupied = false
				claimState.LastTriggerClock = 0
				return
			end

			if not isCharacterOccupyingPart(character, triggerPart) then
				claimState.IsTriggeredWhileOccupied = false
				claimState.LastTriggerClock = 0
				return
			end

			task.wait(checkInterval)
		end
	end)
end

function BrainrotService:_claimPositionGold(player, positionKey)
	local playerData, _brainrotData, placedBrainrots, productionState = self:_getOrCreateDataContainers(player)
	if not playerData or not placedBrainrots or not productionState then
		return false, 0
	end

	local claimSuccess, claimReason, claimResult = self:_requirePlacementService():ClaimPositionGoldState(
		placedBrainrots,
		productionState,
		positionKey
	)

	if not claimSuccess then
		if claimReason == "NoBrainrot" then
			self:_refreshClaimUiForPosition(player, positionKey, placedBrainrots, productionState)
		end
		return false, 0
	end

	local claimAmount = claimResult and claimResult.claimAmount or 0
	local success = self._currencyService and self._currencyService:AddCoins(player, claimAmount, "BrainrotClaim")
	if not success then
		self:_requirePlacementService():RollbackPositionGoldClaim(claimResult)
		return false, 0
	end

	self:_refreshClaimUiForPosition(player, positionKey, placedBrainrots, productionState)
	return true, claimAmount
end

function BrainrotService:GetTotalOfflineGold(player)
	local _playerData, _brainrotData, _placedBrainrots, productionState = self:_getOrCreateDataContainers(player)
	if type(productionState) ~= "table" then
		return 0
	end

	local totalOfflineGold = 0
	for _, slot in pairs(productionState) do
		if type(slot) == "table" then
			totalOfflineGold += math.max(0, tonumber(slot.OfflineGold) or 0)
		end
	end

	return roundBrainrotEconomicValue(totalOfflineGold)
end

function BrainrotService:ClaimAllOfflineGold(player, multiplier, reason)
	local normalizedMultiplier = math.max(1, math.floor(tonumber(multiplier) or 1))
	local playerData, _brainrotData, placedBrainrots, productionState = self:_getOrCreateDataContainers(player)
	if not playerData or type(placedBrainrots) ~= "table" or type(productionState) ~= "table" then
		return false, 0, 0
	end

	local claimSuccess, _claimReason, claimResult = self:_requirePlacementService():ClaimAllOfflineGoldState(productionState)

	local totalOfflineGold = claimResult and claimResult.totalOfflineGold or 0
	if not claimSuccess or totalOfflineGold <= 0 then
		return false, 0, 0
	end

	local grantAmount = roundBrainrotEconomicValue(totalOfflineGold * normalizedMultiplier)
	local didGrant = self._currencyService and select(1, self._currencyService:AddCoins(player, grantAmount, reason or "IdleCoinClaim")) or false
	if not didGrant then
		self:_requirePlacementService():RollbackClaimAllOfflineGoldState(claimResult)
		return false, totalOfflineGold, 0
	end

	self:_refreshAllClaimUi(player, placedBrainrots, productionState)
	return true, totalOfflineGold, grantAmount
end

function BrainrotService:ResetProductionForRebirth(player)
	local playerData, _brainrotData, placedBrainrots, productionState = self:_getOrCreateDataContainers(player)
	if not playerData or type(placedBrainrots) ~= "table" or type(productionState) ~= "table" then
		return false
	end

	self:_requirePlacementService():ResetAllProductionState(placedBrainrots, productionState)

	self:_refreshAllClaimUi(player, placedBrainrots, productionState)
	self:_updatePlayerTotalProductionSpeed(player, placedBrainrots)
	self:PushBrainrotState(player)
	return true
end

function BrainrotService:_bindHomePrompts(player, homeModel)
	self:_clearPromptConnections(player)
	local userId = player.UserId
	local homeId = tostring(homeModel and homeModel.Name or "")

	local platformsByPositionKey = self:_scanHomePlatforms(homeModel)
	self._platformsByUserId[userId] = platformsByPositionKey
	local connectionList = {}
	self._promptConnectionsByUserId[userId] = connectionList

	for _, platformInfo in pairs(platformsByPositionKey) do
		local prompt = platformInfo.Prompt
		prompt:SetAttribute(BRAINROT_PLATFORM_PROMPT_ATTRIBUTE, true)
		prompt:SetAttribute(BRAINROT_PLATFORM_HOME_ID_ATTRIBUTE, homeId)
		prompt:SetAttribute(BRAINROT_PLATFORM_OWNER_USER_ID_ATTRIBUTE, userId)
		prompt:SetAttribute(BRAINROT_PLATFORM_POSITION_KEY_ATTRIBUTE, tostring(platformInfo.PositionKey or ""))
		prompt:SetAttribute(BRAINROT_PLATFORM_SERVER_ENABLED_ATTRIBUTE, false)
		prompt.HoldDuration = tonumber(GameConfig.BRAINROT.PromptHoldDuration) or 1
		prompt.ActionText = "Place Brainrot"
		prompt.ObjectText = "Brainrot Platform"
		prompt.Enabled = false

		table.insert(connectionList, prompt.Triggered:Connect(function(triggerPlayer)
			if triggerPlayer ~= player then
				return
			end

			self:_placeEquippedBrainrot(player, platformInfo)
		end))
	end
end

function BrainrotService:_bindHomeClaims(player, homeModel)
	self:_clearClaimConnections(player)
	local userId = player.UserId

	local claimsByPositionKey = self:_scanHomeClaims(homeModel)
	self._claimsByUserId[userId] = claimsByPositionKey

	local connectionList = {}
	self._claimConnectionsByUserId[userId] = connectionList

	local claimStateByClaimKey = ensureTable(self._claimTouchDebounceByUserId, userId)

	for _, claimInfo in pairs(claimsByPositionKey) do
		local triggerPart = claimInfo.TouchPart
		if not (triggerPart and triggerPart:IsA("BasePart")) then
			warn(string.format("[BrainrotService] Claim 触碰节点缺失，已跳过: %s（需要 Touch/BasePart）", tostring(claimInfo and claimInfo.ClaimKey or "Unknown")))
			continue
		end

		local claimKey = tostring(claimInfo.ClaimKey)
		local claimState = ensureTable(claimStateByClaimKey, claimKey)
		if type(claimState.TouchingParts) ~= "table" then
			claimState.TouchingParts = {}
		end
		claimState.TouchingCount = tonumber(claimState.TouchingCount) or 0
		claimState.LastTriggerClock = tonumber(claimState.LastTriggerClock) or 0
		claimState.IsTriggeredWhileOccupied = claimState.IsTriggeredWhileOccupied == true
		claimState.UnlockGeneration = tonumber(claimState.UnlockGeneration) or 0
		claimState.TriggerPart = triggerPart
		claimState.Character = player.Character

		table.insert(connectionList, triggerPart.Touched:Connect(function(hitPart)
			local character = hitPart and hitPart.Parent
			if not character then
				return
			end

			local touchedPlayer = Players:GetPlayerFromCharacter(character)
			if touchedPlayer ~= player then
				return
			end

			if not self:_shouldTriggerClaimByTouch(claimState, character, hitPart) then
				return
			end

			self:_playClaimPressAnimation(claimInfo)

			if not self:_hasPlacedBrainrotAtPosition(player, claimInfo.PositionKey) then
				self:_claimPositionGold(player, claimInfo.PositionKey)
				return
			end

			self:_playClaimBounceAnimation(player, claimInfo.PositionKey)

			local didClaim = self:_claimPositionGold(player, claimInfo.PositionKey)
			if didClaim then
				self:_playClaimRewardFeedback(player, claimInfo)
			end
		end))

		table.insert(connectionList, triggerPart.TouchEnded:Connect(function(hitPart)
			local character = hitPart and hitPart.Parent
			if not character then
				return
			end

			local touchedPlayer = Players:GetPlayerFromCharacter(character)
			if touchedPlayer ~= player then
				return
			end

			self:_handleClaimTouchEnded(claimState, hitPart)
		end))
	end
end
function BrainrotService:_getEquippedBrainrotTool(player)
	local character = player.Character
	if not character then
		return nil
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("BrainrotTool") then
			return child
		end
	end

	return nil
end

function BrainrotService:_buildPositionKey(platformPart)
	local parentPart = platformPart and platformPart.Parent or nil
	local positionPrefix = tostring((GameConfig.BRAINROT or {}).PositionPrefix or "Position")
	local positionKey = resolveHomeSlotPositionKey(parentPart or platformPart, positionPrefix, parentPart)
	if positionKey then
		return positionKey
	end

	if parentPart and parentPart.Name then
		return parentPart.Name
	end

	return platformPart.Name
end

function BrainrotService:_scanHomePlatforms(homeModel)
	local platforms = {}
	local homeBase = homeModel and homeModel:FindFirstChild(GameConfig.HOME.HomeBaseName)
	if not homeBase then
		return platforms
	end

	local attachmentName = tostring(GameConfig.BRAINROT.PlatformAttachmentName or "BrainrotAttachment")
	local triggerName = tostring(GameConfig.BRAINROT.PlatformTriggerName or "Trigger")

	for _, descendant in ipairs(homeModel:GetDescendants()) do
		if isPlatformPart(descendant) and isHomeSlotUnlocked(descendant) then
			local positionRoot = descendant.Parent

			local attachment = descendant:FindFirstChild(attachmentName)
			if attachment and not attachment:IsA("Attachment") then
				attachment = nil
			end
			if not attachment then
				attachment = descendant:FindFirstChild(attachmentName, true)
				if attachment and not attachment:IsA("Attachment") then
					attachment = nil
				end
				if not attachment then
					attachment = positionRoot and positionRoot:FindFirstChild(attachmentName, true) or nil
				end
				if attachment and not attachment:IsA("Attachment") then
					attachment = nil
				end

				if not attachment then
					local fallbackAttachment = descendant:FindFirstChild("Attachment", true)
					if fallbackAttachment and fallbackAttachment:IsA("Attachment") then
						attachment = fallbackAttachment
					end
				end

				if not attachment and positionRoot then
					local fallbackAttachment = positionRoot:FindFirstChild("Attachment", true)
					if fallbackAttachment and fallbackAttachment:IsA("Attachment") then
						attachment = fallbackAttachment
					end
				end
			end

			local triggerNode = descendant:FindFirstChild(triggerName)
			local proximityPrompt = nil
			if triggerNode then
				local triggerPrompt = triggerNode:FindFirstChild("ProximityPrompt", true)
				if triggerPrompt and triggerPrompt:IsA("ProximityPrompt") then
					proximityPrompt = triggerPrompt
				else
					local directTriggerPrompt = triggerNode:FindFirstChildOfClass("ProximityPrompt")
					if directTriggerPrompt then
						proximityPrompt = directTriggerPrompt
					end
				end
			end

			if not proximityPrompt then
				local platformPrompt = descendant:FindFirstChild("ProximityPrompt", true)
				if platformPrompt and platformPrompt:IsA("ProximityPrompt") then
					proximityPrompt = platformPrompt
				else
					local directPlatformPrompt = descendant:FindFirstChildOfClass("ProximityPrompt")
					if directPlatformPrompt then
						proximityPrompt = directPlatformPrompt
					end
				end
			end

			if not proximityPrompt and positionRoot then
				local positionPrompt = positionRoot:FindFirstChild("ProximityPrompt", true)
				if positionPrompt and positionPrompt:IsA("ProximityPrompt") then
					proximityPrompt = positionPrompt
				else
					local directPositionPrompt = positionRoot:FindFirstChildOfClass("ProximityPrompt")
					if directPositionPrompt then
						proximityPrompt = directPositionPrompt
					end
				end
			end

			if attachment and proximityPrompt then
				local positionKey = self:_buildPositionKey(descendant)
				platforms[positionKey] = {
					PositionKey = positionKey,
					Platform = descendant,
					Attachment = attachment,
					Prompt = proximityPrompt,
				}
			else
				warn(string.format(
					"[BrainrotService] Platform missing nodes, skipped: %s (Attachment=%s, Trigger=%s, Prompt=%s)",
					descendant:GetFullName(),
					tostring(attachment ~= nil),
					tostring(triggerNode ~= nil),
					tostring(proximityPrompt ~= nil)
					))
			end
		end
	end

	if next(platforms) == nil then
		warn(string.format(
			"[BrainrotService] No valid platforms scanned under: %s",
			homeModel:GetFullName()
			))
	end

	return platforms
end
function BrainrotService:_scanHomeClaims(homeModel)
	local claimsByPositionKey = {}
	local homeBase = homeModel and homeModel:FindFirstChild(GameConfig.HOME.HomeBaseName)
	if not homeBase then
		return claimsByPositionKey
	end

	local claimPrefix = tostring(GameConfig.BRAINROT.ClaimPrefix or "Claim")
	local moneyFrameName = tostring(GameConfig.BRAINROT.MoneyFrameName or "Money")
	local currentGoldLabelName = tostring(GameConfig.BRAINROT.CurrentGoldLabelName or "CurrentGold")
	local offlineGoldLabelName = tostring(GameConfig.BRAINROT.OfflineGoldLabelName or "OfflineGold")

	for _, descendant in ipairs(homeModel:GetDescendants()) do
		local claimIndex = descendant:IsA("BasePart") and parseTrailingIndex(descendant.Name, claimPrefix) or nil
		if claimIndex and isHomeSlotUnlocked(descendant) then
			local positionKey = resolveHomeSlotPositionKey(descendant, claimPrefix, descendant)
			if positionKey then
				local touchPart = descendant:FindFirstChild("Touch")
				if touchPart and not touchPart:IsA("BasePart") then
					touchPart = nil
				end
				if not touchPart then
					local touchCandidate = descendant:FindFirstChild("Touch", true)
					if touchCandidate and touchCandidate:IsA("BasePart") then
						touchPart = touchCandidate
					end
				end

				local moneyFrame = findFirstGuiObjectByName(touchPart, moneyFrameName)
				local currentGoldLabel = findFirstTextLabelByName(moneyFrame, currentGoldLabelName)
				local offlineGoldLabel = findFirstTextLabelByName(moneyFrame, offlineGoldLabelName)

				claimsByPositionKey[positionKey] = {
					PositionKey = positionKey,
					ClaimPart = descendant,
					TouchPart = touchPart,
					ClaimKey = string.format("%s:%s", descendant.Name, positionKey),
					ClaimBaseCFrame = descendant.CFrame,
					TouchBaseCFrame = touchPart and touchPart.CFrame or nil,
					MoneyFrame = moneyFrame,
					CurrentGoldLabel = currentGoldLabel,
					OfflineGoldLabel = offlineGoldLabel,
				}
			end
		end
	end

	return claimsByPositionKey

end

function BrainrotService:_clearBrandState(player)
	if not player then
		return
	end

	self._brandsByUserId[player.UserId] = nil
	self._upgradeRequestClockByUserId[player.UserId] = nil
end

function BrainrotService:_bindHomeBrands(player, homeModel)
	if not player then
		return
	end

	self._brandsByUserId[player.UserId] = self:_scanHomeBrands(homeModel)
end

function BrainrotService:_scanHomeBrands(homeModel)
	local brandsByPositionKey = {}
	local homeBase = homeModel and homeModel:FindFirstChild(GameConfig.HOME.HomeBaseName)
	if not homeBase then
		return brandsByPositionKey
	end

	local brandPrefix = tostring(GameConfig.BRAINROT.BrandPrefix or "Brand")
	local surfaceGuiName = tostring(GameConfig.BRAINROT.BrandSurfaceGuiName or "SurfaceGui")
	local frameName = tostring(GameConfig.BRAINROT.BrandFrameName or "Frame")
	local moneyRootName = tostring(GameConfig.BRAINROT.BrandMoneyRootName or "Money")
	local costLabelName = tostring(GameConfig.BRAINROT.BrandCostLabelName or "CurrentGold")
	local levelLabelName = tostring(GameConfig.BRAINROT.BrandLevelLabelName or "Level")

	for _, descendant in ipairs(homeModel:GetDescendants()) do
		local brandIndex = descendant:IsA("BasePart") and parseTrailingIndex(descendant.Name, brandPrefix) or nil
		if brandIndex and isHomeSlotUnlocked(descendant) then
			local positionKey = resolveHomeSlotPositionKey(descendant, brandPrefix, descendant)
			if positionKey then
				local surfaceGui = descendant:FindFirstChild(surfaceGuiName)
				if not (surfaceGui and surfaceGui:IsA("SurfaceGui")) then
					local nestedSurfaceGui = descendant:FindFirstChild(surfaceGuiName, true)
					if nestedSurfaceGui and nestedSurfaceGui:IsA("SurfaceGui") then
						surfaceGui = nestedSurfaceGui
					else
						surfaceGui = descendant:FindFirstChildWhichIsA("SurfaceGui", true)
					end
				end
				local originalTransparency = descendant:GetAttribute(BRAINROT_BRAND_ORIGINAL_TRANSPARENCY_ATTRIBUTE)
				if originalTransparency == nil or tonumber(originalTransparency) >= 1 then
					originalTransparency = descendant:GetAttribute(HOME_EXPANSION_ORIGINAL_TRANSPARENCY_ATTRIBUTE)
					if originalTransparency == nil then
						originalTransparency = descendant.Transparency
						if tonumber(originalTransparency) == nil or tonumber(originalTransparency) >= 1 then
							originalTransparency = 0
						end
					end
					descendant:SetAttribute(BRAINROT_BRAND_ORIGINAL_TRANSPARENCY_ATTRIBUTE, originalTransparency)
				end

				local originalCanQuery = descendant:GetAttribute(BRAINROT_BRAND_ORIGINAL_CAN_QUERY_ATTRIBUTE)
				if originalCanQuery == nil or originalCanQuery == false then
					local homeExpansionOriginalCanQuery = descendant:GetAttribute(HOME_EXPANSION_ORIGINAL_CAN_QUERY_ATTRIBUTE)
					if homeExpansionOriginalCanQuery ~= nil then
						originalCanQuery = homeExpansionOriginalCanQuery
					else
						originalCanQuery = descendant.CanQuery ~= false
						if originalCanQuery == false then
							originalCanQuery = true
						end
					end
					descendant:SetAttribute(BRAINROT_BRAND_ORIGINAL_CAN_QUERY_ATTRIBUTE, originalCanQuery)
				end

				local frame = findFirstGuiObjectByName(surfaceGui, frameName)
				local moneyRoot = findFirstGuiObjectByName(frame or surfaceGui, moneyRootName)
				local costLabel = findFirstTextLabelByName(moneyRoot or frame or surfaceGui, costLabelName)
				local levelLabel = findFirstTextLabelByName(frame or surfaceGui, levelLabelName)
				brandsByPositionKey[positionKey] = {
					PositionKey = positionKey,
					BrandKey = string.format("%s:%s", descendant.Name, positionKey),
					BrandPart = descendant,
					BrandPartOriginalTransparency = tonumber(originalTransparency) or 0,
					BrandPartOriginalCanCollide = descendant.CanCollide,
					BrandPartOriginalCanTouch = descendant.CanTouch,
					BrandPartOriginalCanQuery = originalCanQuery == true,
					SurfaceGui = surfaceGui,
					Frame = frame,
					CostLabel = costLabel,
					LevelLabel = levelLabel,
				}
			end
		end
	end

	return brandsByPositionKey
end

function BrainrotService:_applyBrandUi(brandInfo, enabled, currentLevel, upgradeCost)
	if not brandInfo then
		return
	end

	local isVisible = enabled == true
	local normalizedLevel = normalizeBrainrotLevel(currentLevel)
	if brandInfo.BrandPart and brandInfo.BrandPart:IsA("BasePart") then
		brandInfo.BrandPart.Transparency = isVisible and (tonumber(brandInfo.BrandPartOriginalTransparency) or 0) or 1
		brandInfo.BrandPart.CanCollide = isVisible and (brandInfo.BrandPartOriginalCanCollide ~= false) or false
		brandInfo.BrandPart.CanTouch = isVisible and (brandInfo.BrandPartOriginalCanTouch ~= false) or false
		brandInfo.BrandPart.CanQuery = isVisible and (brandInfo.BrandPartOriginalCanQuery ~= false) or false
	end


	if brandInfo.SurfaceGui and brandInfo.SurfaceGui:IsA("SurfaceGui") then
		brandInfo.SurfaceGui.Enabled = isVisible
		brandInfo.SurfaceGui.AlwaysOnTop = (GameConfig.BRAINROT.BrandSurfaceGuiAlwaysOnTop == true)
		brandInfo.SurfaceGui.LightInfluence = tonumber(GameConfig.BRAINROT.BrandSurfaceGuiLightInfluence) or 0
		brandInfo.SurfaceGui.ZOffset = tonumber(GameConfig.BRAINROT.BrandSurfaceGuiZOffset) or 0.18
	end

	if brandInfo.Frame and brandInfo.Frame:IsA("GuiObject") then
		brandInfo.Frame.Visible = isVisible
	end

	if brandInfo.CostLabel then
		brandInfo.CostLabel.Text = isVisible and formatBrainrotCompactCurrency(upgradeCost) or formatBrainrotCompactCurrency(0)
		brandInfo.CostLabel.Visible = isVisible
	end

	if brandInfo.LevelLabel then
		brandInfo.LevelLabel.Text = isVisible and string.format("Lv.%d>Lv.%d", normalizedLevel, normalizedLevel + 1) or "Lv.-->Lv.--"
		brandInfo.LevelLabel.Visible = isVisible
	end
end

function BrainrotService:_refreshBrandUiForPosition(player, positionKey, placedBrainrots)
	local brandsByPositionKey = self._brandsByUserId[player.UserId]
	local brandInfo = brandsByPositionKey and brandsByPositionKey[positionKey] or nil
	if not brandInfo then
		return
	end

	local resolvedPlacedBrainrots = placedBrainrots
	if type(resolvedPlacedBrainrots) ~= "table" then
		local _playerData, _brainrotData
		_playerData, _brainrotData, resolvedPlacedBrainrots = self:_getOrCreateDataContainers(player)
	end

	local placedData = resolvedPlacedBrainrots and resolvedPlacedBrainrots[positionKey] or nil
	if type(placedData) ~= "table" then
		self:_applyBrandUi(brandInfo, false, getBaseBrainrotLevel(), 0)
		return
	end

	local brainrotId = tonumber(placedData.BrainrotId)
	local brainrotDefinition = brainrotId and BrainrotConfig.ById[brainrotId] or nil
	if not brainrotDefinition then
		self:_applyBrandUi(brandInfo, false, getBaseBrainrotLevel(), 0)
		return
	end

	local currentLevel = normalizeBrainrotLevel(placedData.Level)
	self:_applyBrandUi(brandInfo, true, currentLevel, getBrainrotUpgradeCost(brainrotDefinition, currentLevel))
end

function BrainrotService:_refreshAllBrandUi(player, placedBrainrots)
	local brandsByPositionKey = self._brandsByUserId[player.UserId]
	if type(brandsByPositionKey) ~= "table" then
		return
	end

	for positionKey in pairs(brandsByPositionKey) do
		self:_refreshBrandUiForPosition(player, positionKey, placedBrainrots)
	end
end

function BrainrotService:ResetHomeWorldUi(homeModel)
	if not homeModel then
		return
	end

	local claimsByPositionKey = self:_scanHomeClaims(homeModel)
	for _, claimInfo in pairs(claimsByPositionKey) do
		self:_applyClaimUi(claimInfo, false, 0, 0)
	end

	local brandsByPositionKey = self:_scanHomeBrands(homeModel)
	for _, brandInfo in pairs(brandsByPositionKey) do
		self:_applyBrandUi(brandInfo, false, getBaseBrainrotLevel(), 0)
	end
end

function BrainrotService:_pushBrainrotUpgradeFeedback(player, status, positionKey, currentLevel, upgradeCost, currentCoins)
	if not (player and self._brainrotUpgradeFeedbackEvent) then
		return
	end

	local normalizedLevel = normalizeBrainrotLevel(currentLevel)
	self._brainrotUpgradeFeedbackEvent:FireClient(player, {
		status = tostring(status or "Unknown"),
		positionKey = tostring(positionKey or ""),
		currentLevel = normalizedLevel,
		nextLevel = normalizedLevel + 1,
		upgradeCost = roundBrainrotEconomicValue(upgradeCost),
		currentCoins = roundBrainrotEconomicValue(currentCoins),
		timestamp = os.clock(),
	})
end

function BrainrotService:_canHandleUpgradeRequest(player)
	if not player then
		return false
	end

	local debounceSeconds = math.max(0.05, tonumber((GameConfig.BRAINROT or {}).UpgradeRequestDebounceSeconds) or 0.2)
	local nowClock = os.clock()
	local lastClock = tonumber(self._upgradeRequestClockByUserId[player.UserId]) or 0
	if nowClock - lastClock < debounceSeconds then
		return false
	end

	self._upgradeRequestClockByUserId[player.UserId] = nowClock
	return true
end

function BrainrotService:_upgradePlacedBrainrot(player, positionKey)
	local _playerData, _brainrotData, placedBrainrots = self:_getOrCreateDataContainers(player)
	if not placedBrainrots then
		return false
	end

	local quoteSuccess, quoteReason, upgradeQuote = self:_requirePlacementService():GetPlacedUpgradeQuote(placedBrainrots, positionKey)

	if not quoteSuccess and quoteReason == "NoBrainrot" then
		self:_pushBrainrotUpgradeFeedback(player, "NoBrainrot", positionKey, getBaseBrainrotLevel(), 0, self._playerDataService and self._playerDataService:GetCoins(player) or 0)
		self:_refreshBrandUiForPosition(player, positionKey, placedBrainrots)
		return false
	end

	if not quoteSuccess then
		local currentLevel = upgradeQuote and upgradeQuote.currentLevel or getBaseBrainrotLevel()
		self:_pushBrainrotUpgradeFeedback(player, "BrainrotNotFound", positionKey, currentLevel, 0, self._playerDataService and self._playerDataService:GetCoins(player) or 0)
		return false
	end

	local brainrotDefinition = upgradeQuote.brainrotDefinition
	local currentLevel = upgradeQuote.currentLevel
	local upgradeCost = upgradeQuote.upgradeCost
	local currentCoins = self._playerDataService and self._playerDataService:GetCoins(player) or 0
	if currentCoins + 0.0001 < upgradeCost then
		self:_pushBrainrotUpgradeFeedback(player, "NotEnoughCoins", positionKey, currentLevel, upgradeCost, currentCoins)
		self:_refreshBrandUiForPosition(player, positionKey, placedBrainrots)
		return false
	end

	local success = false
	local nextCoins = currentCoins
	if self._currencyService then
		success, nextCoins = self._currencyService:AddCoins(player, -upgradeCost, "BrainrotUpgrade")
	end
	if not success then
		self:_pushBrainrotUpgradeFeedback(player, "CurrencyFailed", positionKey, currentLevel, upgradeCost, currentCoins)
		return false
	end

	self:_requirePlacementService():ApplyPlacedUpgradeQuote(upgradeQuote)

	local runtimePlaced = self._runtimePlacedByUserId[player.UserId]
	local runtimeInstance = runtimePlaced and runtimePlaced[positionKey] or nil
	if runtimeInstance and runtimeInstance.Parent then
		self:_attachPlacedInfoUi(runtimeInstance, brainrotDefinition, upgradeQuote.placedData.Level)
	end

	self:_refreshBrandUiForPosition(player, positionKey, placedBrainrots)
	self:_updatePlayerTotalProductionSpeed(player, placedBrainrots)
	self:PushBrainrotState(player)
	self:_pushBrainrotUpgradeFeedback(player, "Success", positionKey, upgradeQuote.placedData.Level, upgradeCost, nextCoins)
	return true
end

function BrainrotService:_isOwnedPositionKey(player, positionKey)
	if not (player and type(positionKey) == "string" and positionKey ~= "") then
		return false
	end

	local platformsByPositionKey = self._platformsByUserId[player.UserId]
	if type(platformsByPositionKey) == "table" and platformsByPositionKey[positionKey] ~= nil then
		return true
	end

	local homeModel = self._homeService and self._homeService:GetAssignedHome(player) or nil
	if not homeModel then
		return false
	end

	platformsByPositionKey = self:_scanHomePlatforms(homeModel)
	self._platformsByUserId[player.UserId] = platformsByPositionKey
	return type(platformsByPositionKey) == "table" and platformsByPositionKey[positionKey] ~= nil
end

function BrainrotService:_handleRequestBrainrotUpgrade(player, payload)
	if not self:_canHandleUpgradeRequest(player) then
		return
	end

	local positionKey = nil
	if type(payload) == "table" then
		positionKey = tostring(payload.positionKey or "")
	else
		positionKey = tostring(payload or "")
	end

	if positionKey == "" then
		return
	end

	if not self:_isOwnedPositionKey(player, positionKey) then
		self:_pushBrainrotUpgradeFeedback(
			player,
			"InvalidPositionKey",
			positionKey,
			getBaseBrainrotLevel(),
			0,
			self._playerDataService and self._playerDataService:GetCoins(player) or 0
		)
		return
	end

	self:_upgradePlacedBrainrot(player, positionKey)
end

function BrainrotService:_pushStudioBrainrotGrantFeedback(player, status, brainrotId, grantedCount)
	if not (player and self._studioBrainrotGrantFeedbackEvent) then
		return
	end

	local parsedBrainrotId = math.max(0, math.floor(tonumber(brainrotId) or 0))
	local brainrotDefinition = BrainrotConfig.ById[parsedBrainrotId]
	self._studioBrainrotGrantFeedbackEvent:FireClient(player, {
		status = tostring(status or "Unknown"),
		brainrotId = parsedBrainrotId,
		brainrotName = brainrotDefinition and tostring(brainrotDefinition.Name or "") or "",
		grantedCount = math.max(0, math.floor(tonumber(grantedCount) or 0)),
		timestamp = os.clock(),
	})
end

function BrainrotService:_handleRequestStudioBrainrotGrant(player, payload)
	if not player then
		return
	end

	if not RunService:IsStudio() then
		self:_pushStudioBrainrotGrantFeedback(player, "NotStudio", 0, 0)
		return
	end

	if self._gmCommandService and player.UserId > 0 and not self._gmCommandService:IsDeveloper(player) then
		self:_pushStudioBrainrotGrantFeedback(player, "NotAllowed", 0, 0)
		return
	end

	local brainrotId = nil
	if type(payload) == "table" then
		brainrotId = payload.brainrotId
	else
		brainrotId = payload
	end

	local parsedBrainrotId = math.floor(tonumber(brainrotId) or 0)
	if parsedBrainrotId <= 0 then
		self:_pushStudioBrainrotGrantFeedback(player, "InvalidBrainrotId", 0, 0)
		return
	end

	if not BrainrotConfig.ById[parsedBrainrotId] then
		self:_pushStudioBrainrotGrantFeedback(player, "BrainrotNotFound", parsedBrainrotId, 0)
		return
	end

	local success, status, grantedCount = self:GrantBrainrot(player, parsedBrainrotId, 1, "StudioDebug")
	if not success then
		self:_pushStudioBrainrotGrantFeedback(player, status or "GrantFailed", parsedBrainrotId, grantedCount or 0)
		return
	end

	self:_pushStudioBrainrotGrantFeedback(player, "Success", parsedBrainrotId, grantedCount)
end

function BrainrotService:_pushBrainrotSellFeedback(player, status, soldCount, soldValue, remainingInventoryCount, mode, currentCoins, soldInstanceId, requestId)
	if not (player and self._brainrotSellFeedbackEvent) then
		return
	end

	self._brainrotSellFeedbackEvent:FireClient(player, {
		status = tostring(status or "Unknown"),
		soldCount = math.max(0, math.floor(tonumber(soldCount) or 0)),
		soldValue = roundBrainrotEconomicValue(soldValue),
		remainingInventoryCount = math.max(0, math.floor(tonumber(remainingInventoryCount) or 0)),
		mode = tostring(mode or "Single"),
		currentCoins = roundBrainrotEconomicValue(currentCoins),
		soldInstanceId = math.max(0, math.floor(tonumber(soldInstanceId) or 0)),
		requestId = tostring(requestId or ""),
		timestamp = os.clock(),
	})
end

function BrainrotService:_canHandleSellRequest(player)
	if not player then
		return false
	end

	local debounceSeconds = math.max(0.05, tonumber((GameConfig.BRAINROT or {}).SellRequestDebounceSeconds) or 0.2)
	local nowClock = os.clock()
	local lastClock = tonumber(self._sellRequestClockByUserId[player.UserId]) or 0
	if nowClock - lastClock < debounceSeconds then
		return false
	end

	self._sellRequestClockByUserId[player.UserId] = nowClock
	return true
end

function BrainrotService:_sellBrainrotByInstanceId(player, instanceId, requestId)
	local _playerData, brainrotData = self:_getOrCreateDataContainers(player)
	if not brainrotData then
		return false
	end

	local targetInstanceId = math.floor(tonumber(instanceId) or 0)
	if targetInstanceId <= 0 then
		self:_pushBrainrotSellFeedback(player, "InvalidInstanceId", 0, 0, #(brainrotData.Inventory or {}), "Single", self._playerDataService and self._playerDataService:GetCoins(player) or 0, 0, requestId)
		return false
	end

	local inventoryIndex = findInventoryIndexByInstanceId(brainrotData.Inventory, targetInstanceId)
	if not inventoryIndex then
		self:_pushBrainrotSellFeedback(player, "BrainrotNotFound", 0, 0, #(brainrotData.Inventory or {}), "Single", self._playerDataService and self._playerDataService:GetCoins(player) or 0, targetInstanceId, requestId)
		return false
	end

	local inventoryItem = brainrotData.Inventory[inventoryIndex]
	local brainrotId = tonumber(inventoryItem and inventoryItem.BrainrotId)
	local brainrotDefinition = brainrotId and BrainrotConfig.ById[brainrotId] or nil
	if not brainrotDefinition then
		self:_pushBrainrotSellFeedback(player, "BrainrotConfigMissing", 0, 0, #(brainrotData.Inventory or {}), "Single", self._playerDataService and self._playerDataService:GetCoins(player) or 0, targetInstanceId, requestId)
		return false
	end

	local sellPrice = getBrainrotSellPrice(brainrotDefinition)
	if sellPrice <= 0 then
		self:_pushBrainrotSellFeedback(player, "SellValueInvalid", 0, 0, #(brainrotData.Inventory or {}), "Single", self._playerDataService and self._playerDataService:GetCoins(player) or 0, targetInstanceId, requestId)
		return false
	end

	local success = false
	local nextCoins = 0
	local previousEquippedInstanceId = math.max(0, math.floor(tonumber(brainrotData.EquippedInstanceId) or 0))
	local removedInventoryItem = table.remove(brainrotData.Inventory, inventoryIndex)
	if previousEquippedInstanceId == targetInstanceId then
		brainrotData.EquippedInstanceId = 0
	end

	if self._currencyService then
		success, nextCoins = self._currencyService:AddCoins(player, sellPrice, "BrainrotSellSingle")
	end
	if not success then
		table.insert(brainrotData.Inventory, inventoryIndex, removedInventoryItem)
		brainrotData.EquippedInstanceId = previousEquippedInstanceId
		self:_pushBrainrotSellFeedback(player, "CurrencyFailed", 0, 0, #(brainrotData.Inventory or {}), "Single", self._playerDataService and self._playerDataService:GetCoins(player) or 0, targetInstanceId, requestId)
		return false
	end

	local reEquipInstanceId = 0
	if previousEquippedInstanceId > 0 and previousEquippedInstanceId ~= targetInstanceId then
		if findInventoryIndexByInstanceId(brainrotData.Inventory, previousEquippedInstanceId) then
			reEquipInstanceId = previousEquippedInstanceId
		end
	end

	self:_refreshBrainrotTools(player)
	if reEquipInstanceId > 0 then
		task.defer(function()
			self:_equipBrainrotToolByInstanceId(player, reEquipInstanceId)
		end)
	end

	self:PushBrainrotState(player)
	self:_pushBrainrotSellFeedback(player, "Success", 1, sellPrice, #brainrotData.Inventory, "Single", nextCoins, targetInstanceId, requestId)
	return true
end

function BrainrotService:_sellAllBrainrots(player, requestId)
	local _playerData, brainrotData = self:_getOrCreateDataContainers(player)
	if not brainrotData then
		return false
	end

	local inventory = brainrotData.Inventory or {}
	if #inventory <= 0 then
		self:_pushBrainrotSellFeedback(player, "InventoryEmpty", 0, 0, 0, "All", self._playerDataService and self._playerDataService:GetCoins(player) or 0, 0, requestId)
		return false
	end

	local totalSellValue = 0
	local soldCount = 0
	local remainingInventory = {}
	for _, inventoryItem in ipairs(inventory) do
		local brainrotId = tonumber(inventoryItem and inventoryItem.BrainrotId)
		local brainrotDefinition = brainrotId and BrainrotConfig.ById[brainrotId] or nil
		if brainrotDefinition then
			totalSellValue = roundBrainrotEconomicValue(totalSellValue + getBrainrotSellPrice(brainrotDefinition))
			soldCount += 1
		else
			table.insert(remainingInventory, inventoryItem)
		end
	end

	if soldCount <= 0 or totalSellValue <= 0 then
		self:_pushBrainrotSellFeedback(player, "InventoryEmpty", 0, 0, #inventory, "All", self._playerDataService and self._playerDataService:GetCoins(player) or 0, 0, requestId)
		return false
	end

	local success = false
	local nextCoins = 0
	local previousEquippedInstanceId = math.max(0, math.floor(tonumber(brainrotData.EquippedInstanceId) or 0))
	brainrotData.Inventory = remainingInventory
	brainrotData.EquippedInstanceId = 0

	if self._currencyService then
		success, nextCoins = self._currencyService:AddCoins(player, totalSellValue, "BrainrotSellAll")
	end
	if not success then
		brainrotData.Inventory = inventory
		brainrotData.EquippedInstanceId = previousEquippedInstanceId
		self:_pushBrainrotSellFeedback(player, "CurrencyFailed", 0, 0, #inventory, "All", self._playerDataService and self._playerDataService:GetCoins(player) or 0, 0, requestId)
		return false
	end

	self:_refreshBrainrotTools(player)
	self:PushBrainrotState(player)
	self:_pushBrainrotSellFeedback(player, "Success", soldCount, totalSellValue, #brainrotData.Inventory, "All", nextCoins, 0, requestId)
	return true
end

function BrainrotService:_handleRequestBrainrotSell(player, payload)
	if not self:_canHandleSellRequest(player) then
		return
	end

	local requestId = ""
	if type(payload) == "table" then
		requestId = tostring(payload.requestId or "")
	end

	if type(payload) == "table" and payload.sellAll == true then
		self:_sellAllBrainrots(player, requestId)
		return
	end

	local instanceId = nil
	if type(payload) == "table" then
		instanceId = payload.instanceId
	else
		instanceId = payload
	end

	self:_sellBrainrotByInstanceId(player, instanceId, requestId)
end

function BrainrotService:_pulseLabel(label)
	local pulseScale = getOrCreatePulseScale(label)
	if not pulseScale then
		return
	end

	if pulseScale:GetAttribute("IsPulsing") then
		return
	end

	pulseScale:SetAttribute("IsPulsing", true)
	task.spawn(function()
		for _ = 1, 2 do
			local growTween = TweenService:Create(pulseScale, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Scale = 1.08,
			})
			local shrinkTween = TweenService:Create(pulseScale, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Scale = 1,
			})

			growTween:Play()
			growTween.Completed:Wait()
			shrinkTween:Play()
			shrinkTween.Completed:Wait()
		end

		pulseScale.Scale = 1
		pulseScale:SetAttribute("IsPulsing", false)
	end)
end

function BrainrotService:_applyClaimUi(claimInfo, enabled, currentGold, offlineGold)
	local previousCurrentGold = tonumber(claimInfo._lastCurrentGold) or 0
	local previousOfflineGold = tonumber(claimInfo._lastOfflineGold) or 0

	if claimInfo.MoneyFrame and claimInfo.MoneyFrame:IsA("GuiObject") then
		claimInfo.MoneyFrame.Visible = enabled == true
	end

	if claimInfo.CurrentGoldLabel then
		claimInfo.CurrentGoldLabel.Text = formatCurrentGoldText(currentGold)
		claimInfo.CurrentGoldLabel.Visible = enabled == true
		if enabled and currentGold ~= previousCurrentGold then
			self:_pulseLabel(claimInfo.CurrentGoldLabel)
		end
	end

	if claimInfo.OfflineGoldLabel then
		claimInfo.OfflineGoldLabel.Text = formatOfflineGoldText(offlineGold)
		claimInfo.OfflineGoldLabel.Visible = enabled and offlineGold > 0
		if enabled and offlineGold > 0 and offlineGold ~= previousOfflineGold then
			self:_pulseLabel(claimInfo.OfflineGoldLabel)
		end
	end

	claimInfo._lastCurrentGold = currentGold
	claimInfo._lastOfflineGold = offlineGold
end

function BrainrotService:_refreshClaimUiForPosition(player, positionKey, placedBrainrots, productionState)
	local claimsByPositionKey = self._claimsByUserId[player.UserId]
	local claimInfo = claimsByPositionKey and claimsByPositionKey[positionKey] or nil
	if not claimInfo then
		return
	end

	local resolvedPlaced = placedBrainrots
	local resolvedProduction = productionState
	if type(resolvedPlaced) ~= "table" or type(resolvedProduction) ~= "table" then
		local _playerData, _brainrotData
		_playerData, _brainrotData, resolvedPlaced, resolvedProduction = self:_getOrCreateDataContainers(player)
	end

	local hasPlaced = resolvedPlaced and resolvedPlaced[positionKey] ~= nil
	if not hasPlaced then
		self:_applyClaimUi(claimInfo, false, 0, 0)
		return
	end

	local slot = self:_getOrCreateProductionSlot(resolvedProduction, positionKey)
	self:_applyClaimUi(claimInfo, true, slot.CurrentGold, slot.OfflineGold)
end

function BrainrotService:_refreshAllClaimUi(player, placedBrainrots, productionState)
	local claimsByPositionKey = self._claimsByUserId[player.UserId]
	if type(claimsByPositionKey) ~= "table" then
		return
	end

	for positionKey in pairs(claimsByPositionKey) do
		self:_refreshClaimUiForPosition(player, positionKey, placedBrainrots, productionState)
	end
end

function BrainrotService:_refreshPlatformPromptState(player, positionKey, placedBrainrots)
	local platformsByPositionKey = self._platformsByUserId[player.UserId]
	if type(platformsByPositionKey) ~= "table" then
		return
	end

	local platformInfo = platformsByPositionKey[positionKey]
	if not platformInfo or not platformInfo.Prompt then
		return
	end

	local resolvedPlacedBrainrots = placedBrainrots
	if type(resolvedPlacedBrainrots) ~= "table" then
		local _playerData, _brainrotData
		_playerData, _brainrotData, resolvedPlacedBrainrots = self:_getOrCreateDataContainers(player)
	end

	local occupied = resolvedPlacedBrainrots and resolvedPlacedBrainrots[positionKey] ~= nil
	local serverEnabled = not occupied
	platformInfo.Prompt:SetAttribute(BRAINROT_PLATFORM_SERVER_ENABLED_ATTRIBUTE, serverEnabled)
	platformInfo.Prompt.Enabled = false
end

function BrainrotService:_refreshAllPlatformPrompts(player, placedBrainrots)
	local platformsByPositionKey = self._platformsByUserId[player.UserId]
	if type(platformsByPositionKey) ~= "table" then
		return
	end

	for positionKey in pairs(platformsByPositionKey) do
		self:_refreshPlatformPromptState(player, positionKey, placedBrainrots)
	end
end

function BrainrotService:_stopIdleTrack(player, positionKey)
	local tracksByPosition = self._runtimeIdleTracksByUserId[player.UserId]
	if type(tracksByPosition) ~= "table" then
		return
	end

	local track = tracksByPosition[positionKey]
	if not track then
		return
	end

	pcall(function()
		track:Stop(0)
	end)
	pcall(function()
		track:Destroy()
	end)
	tracksByPosition[positionKey] = nil
end

function BrainrotService:_stopAllIdleTracks(player)
	local tracksByPosition = self._runtimeIdleTracksByUserId[player.UserId]
	if type(tracksByPosition) ~= "table" then
		return
	end

	for positionKey, track in pairs(tracksByPosition) do
		pcall(function()
			track:Stop(0)
		end)
		pcall(function()
			track:Destroy()
		end)
		tracksByPosition[positionKey] = nil
	end

	self._runtimeIdleTracksByUserId[player.UserId] = nil
end

function BrainrotService:_stopWorldSpawnIdleAnimation(entryId)
	local track = self._worldSpawnIdleTracksByEntryId[entryId]
	if not track then
		return
	end

	pcall(function()
		track:Stop(0)
	end)
	pcall(function()
		track:Destroy()
	end)
	self._worldSpawnIdleTracksByEntryId[entryId] = nil
end

function BrainrotService:_playWorldSpawnIdleAnimation(entry)
	if type(entry) ~= "table" then
		return
	end

	local config = self:_getWorldSpawnConfig()
	if config.idleAnimationEnabled ~= true then
		return
	end

	self:_stopWorldSpawnIdleAnimation(entry.EntryId)

	local brainrotDefinition = BrainrotConfig.ById[entry.BrainrotId]
	if type(brainrotDefinition) ~= "table" then
		return
	end

	local animationId = normalizeAnimationId(brainrotDefinition.IdleAnimationId)
	if not animationId then
		return
	end

	local animationRoot = self:_resolveIdleAnimationRoot(entry.Instance, brainrotDefinition)
	if not animationRoot then
		return
	end

	local animator = nil
	local humanoid = animationRoot:FindFirstChildWhichIsA("Humanoid", true)
	if humanoid then
		pcall(function()
			humanoid.PlatformStand = false
			if humanoid:GetState() == Enum.HumanoidStateType.Physics then
				humanoid:ChangeState(Enum.HumanoidStateType.Running)
			end
		end)

		animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
	else
		local animationController = animationRoot:FindFirstChildWhichIsA("AnimationController", true)
		if not animationController then
			animationController = Instance.new("AnimationController")
			animationController.Name = "BrainrotAnimationController"
			animationController.Parent = animationRoot
		end

		animator = animationController:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = animationController
		end
	end

	if not animator then
		return
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animationId

	local ok, trackOrError = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	animation:Destroy()

	if ok and trackOrError then
		local track = trackOrError
		track.Looped = true
		pcall(function()
			track.Priority = Enum.AnimationPriority.Idle
		end)
		track:Play(0)
		self._worldSpawnIdleTracksByEntryId[entry.EntryId] = track
	end
end

function BrainrotService:_resolveIdleAnimationRoot(placedInstance, brainrotDefinition)
	if not placedInstance then
		return nil
	end

	if placedInstance:IsA("Tool") then
		local _folderName, preferredModelName = parseModelPath(brainrotDefinition.ModelPath)
		if preferredModelName and preferredModelName ~= "" then
			local preferredModel = placedInstance:FindFirstChild(preferredModelName, true)
			if preferredModel and preferredModel:IsA("Model") then
				return preferredModel
			end
		end

		local sameNameModel = placedInstance:FindFirstChild(placedInstance.Name, true)
		if sameNameModel and sameNameModel:IsA("Model") then
			return sameNameModel
		end

		local allModels = {}
		for _, descendant in ipairs(placedInstance:GetDescendants()) do
			if descendant:IsA("Model") then
				table.insert(allModels, descendant)
			end
		end

		local bestModel = nil
		local bestScore = -1

		for _, model in ipairs(allModels) do
			local score = 0
			if model:FindFirstChildWhichIsA("Humanoid", true) then
				score += 8
			end
			if model:FindFirstChildWhichIsA("AnimationController", true) then
				score += 6
			end
			if model:FindFirstChildWhichIsA("Motor6D", true) then
				score += 4
			end
			if model:FindFirstChildWhichIsA("Bone", true) then
				score += 2
			end
			if model:FindFirstChildWhichIsA("BasePart", true) then
				score += 1
			end

			if score > bestScore then
				bestScore = score
				bestModel = model
			end
		end

		return bestModel
	end

	if placedInstance:IsA("Model") then
		return placedInstance
	end

	return nil
end

function BrainrotService:_playIdleAnimationForPlaced(player, positionKey, placedInstance, brainrotDefinition)
	self:_stopIdleTrack(player, positionKey)

	if type(brainrotDefinition) ~= "table" then
		return
	end

	local animationId = normalizeAnimationId(brainrotDefinition.IdleAnimationId)
	if not animationId then
		return
	end

	local animationRoot = self:_resolveIdleAnimationRoot(placedInstance, brainrotDefinition)
	if not animationRoot then
		warn(string.format(
			"[BrainrotService] 待机动画播放失败：未找到动画根节点（BrainrotId=%s, ModelPath=%s）",
			tostring(brainrotDefinition.Id),
			tostring(brainrotDefinition.ModelPath)
			))
		return
	end

	local animator = nil
	local humanoid = animationRoot:FindFirstChildWhichIsA("Humanoid", true)
	if humanoid then
		pcall(function()
			humanoid.PlatformStand = false
			if humanoid:GetState() == Enum.HumanoidStateType.Physics then
				humanoid:ChangeState(Enum.HumanoidStateType.Running)
			end
		end)

		animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
	else
		local animationController = animationRoot:FindFirstChildWhichIsA("AnimationController", true)
		if not animationController then
			animationController = Instance.new("AnimationController")
			animationController.Name = "BrainrotAnimationController"
			animationController.Parent = animationRoot
		end

		animator = animationController:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = animationController
		end
	end

	if not animator then
		warn(string.format(
			"[BrainrotService] 待机动画播放失败：未找到/创建 Animator（BrainrotId=%s）",
			tostring(brainrotDefinition.Id)
			))
		return
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animationId

	local ok, trackOrError = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	animation:Destroy()

	if ok and trackOrError then
		local track = trackOrError
		track.Looped = true
		pcall(function()
			track.Priority = Enum.AnimationPriority.Idle
		end)
		track:Play(0)
		local tracksByPosition = ensureTable(self._runtimeIdleTracksByUserId, player.UserId)
		tracksByPosition[positionKey] = track
	elseif not ok then
		warn(string.format(
			"[BrainrotService] 待机动画 LoadAnimation 失败（BrainrotId=%s, AnimationId=%s）: %s",
			tostring(brainrotDefinition.Id),
			tostring(animationId),
			tostring(trackOrError)
			))
	else
		warn(string.format(
			"[BrainrotService] 待机动画播放失败：LoadAnimation 返回空 Track（BrainrotId=%s, AnimationId=%s）",
			tostring(brainrotDefinition.Id),
			tostring(animationId)
			))
	end
end
return BrainrotService
