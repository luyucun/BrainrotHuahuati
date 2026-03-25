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
		"[BrainrotService] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
		moduleName
		))
end

local GameConfig = requireSharedModule("GameConfig")
local BrainrotConfig = requireSharedModule("BrainrotConfig")
local BrainrotDisplayConfig = requireSharedModule("BrainrotDisplayConfig")
local FormatUtil = requireSharedModule("FormatUtil")

local BrainrotService = {}
BrainrotService._playerDataService = nil
BrainrotService._homeService = nil
BrainrotService._currencyService = nil
BrainrotService._friendBonusService = nil
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
BrainrotService._stealTipEvent = nil
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
BrainrotService._missingDisplayPathWarned = {}
BrainrotService._didWarnMissingBaseInfoTemplate = false
BrainrotService._didWarnMissingInfoAttachmentByModelPath = {}
BrainrotService._didWarnMissingClaimEffectTemplate = false

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

local function ensureTable(parentTable, key)
	if type(parentTable[key]) ~= "table" then
		parentTable[key] = {}
	end

	return parentTable[key]
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

	local primaryPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
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
	return FormatUtil.FormatCompactCurrency(roundBrainrotEconomicValue(value), getBrainrotDisplayDecimals())
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

	local infoTemplateRoot = ReplicatedStorage:FindFirstChild(infoTemplateRootName)
	local infoTemplate = infoTemplateRoot and infoTemplateRoot:FindFirstChild(infoTemplateName) or nil
	if not (infoTemplate and infoTemplate:IsA("BillboardGui")) then
		if not self._didWarnMissingBaseInfoTemplate then
			warn(string.format(
				"[BrainrotService] 缺少脑红信息模板：ReplicatedStorage/%s/%s",
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
				"[BrainrotService] 脑红模型缺少 Info Attachment，无法挂载 BaseInfo（ModelPath=%s）",
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

	local qualityId = math.floor(tonumber(brainrotDefinition.Quality) or 0)
	local rarityId = math.floor(tonumber(brainrotDefinition.Rarity) or 0)
	local qualityName, qualityGradientPath = resolveQualityDisplayInfo(qualityId)
	local rarityName, rarityGradientPath = resolveRarityDisplayInfo(rarityId)
	local coinPerSecond = getBrainrotProductionSpeed(brainrotDefinition, brainrotLevel)

	if nameLabel then
		nameLabel.Text = tostring(brainrotDefinition.Name or "Unknown")
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

function BrainrotService:_getOrCreateDataContainers(player)
	local playerData = self._playerDataService:GetPlayerData(player)
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

	local maxInstanceId = 0
	for index = #brainrotData.Inventory, 1, -1 do
		local inventoryItem = brainrotData.Inventory[index]
		if type(inventoryItem) ~= "table" then
			table.remove(brainrotData.Inventory, index)
		else
			inventoryItem.InstanceId = math.max(0, math.floor(tonumber(inventoryItem.InstanceId) or 0))
			inventoryItem.BrainrotId = math.max(0, math.floor(tonumber(inventoryItem.BrainrotId) or 0))
			inventoryItem.Level = normalizeBrainrotLevel(inventoryItem.Level)

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
			placedData.Level = normalizeBrainrotLevel(placedData.Level)
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
	self:_getOrCreateUnlockedBrainrotMap(brainrotData)

	return playerData, brainrotData, placedBrainrots, productionState
end

function BrainrotService:_getOrCreateProcessedStealPurchaseIds(brainrotData)
	if type(brainrotData) ~= "table" then
		return nil
	end

	if type(brainrotData.ProcessedStealPurchaseIds) ~= "table" then
		brainrotData.ProcessedStealPurchaseIds = {}
	end

	return brainrotData.ProcessedStealPurchaseIds
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
	if requestId == "" or productId <= 0 or brainrotId <= 0 or instanceId <= 0 or ownerUserId <= 0 then
		return nil
	end

	return {
		RequestId = requestId,
		BuyerUserId = math.max(0, math.floor(tonumber(source.BuyerUserId or source.buyerUserId) or 0)),
		OwnerUserId = ownerUserId,
		OwnerName = tostring(source.OwnerName or source.ownerName or ""),
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

	local _playerData, buyerBrainrotData = self:_getOrCreateDataContainers(buyerPlayer)
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

	local grantSuccess = false
	local grantReason = nil
	local grantResult = nil
	grantSuccess, grantReason, grantResult = self:GrantBrainrotInstance(buyerPlayer, pending.BrainrotId, pending.Level, "Steal")
	if not grantSuccess then
		warn(string.format("[BrainrotService] failed to grant stolen brainrot buyer=%d productId=%d reason=%s", buyerPlayer.UserId, productId, tostring(grantReason)))
		return true, Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ownerPlayer = Players:GetPlayerByUserId(pending.OwnerUserId)
	local wasReplacementGrant = true
	if ownerPlayer then
		local removeSuccess = self:ConsumeBrainrotInstance(ownerPlayer, pending.InstanceId, "Stolen")
		wasReplacementGrant = not removeSuccess
		if removeSuccess then
			self:_pushStealTip(ownerPlayer, buyerPlayer.Name, pending.BrainrotName)
		end
	end

	if purchaseId ~= "" then
		processedPurchaseIds[purchaseId] = os.time()
	end

	self:_clearPendingStealPurchase(buyerPlayer, pending.RequestId)
	self:_pushBrainrotStealFeedback(buyerPlayer, "Success", {
		requestId = pending.RequestId,
		productId = pending.ProductId,
		brainrotId = pending.BrainrotId,
		brainrotName = pending.BrainrotName,
		message = "",
		wasReplacement = wasReplacementGrant,
		grantedInstanceId = type(grantResult) == "table" and grantResult.instanceId or 0,
	})

	if self._playerDataService then
		task.spawn(function()
			self._playerDataService:SavePlayerData(buyerPlayer)
			if ownerPlayer and ownerPlayer.Parent and ownerPlayer ~= buyerPlayer then
				self._playerDataService:SavePlayerData(ownerPlayer)
			end
		end)
	end

	return true, Enum.ProductPurchaseDecision.PurchaseGranted
end

function BrainrotService:_getOrCreateUnlockedBrainrotMap(brainrotData)
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

			if parsedBrainrotId > 0 and BrainrotConfig.ById[parsedBrainrotId] then
				unlockedMap[tostring(parsedBrainrotId)] = true
			end
		end
	end

	brainrotData.UnlockedBrainrotIds = unlockedMap
	return unlockedMap
end

function BrainrotService:_markBrainrotUnlocked(brainrotData, brainrotId)
	local parsedBrainrotId = math.floor(tonumber(brainrotId) or 0)
	if parsedBrainrotId <= 0 or not BrainrotConfig.ById[parsedBrainrotId] then
		return false
	end

	local unlockedMap = self:_getOrCreateUnlockedBrainrotMap(brainrotData)
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

function BrainrotService:_syncUnlockedBrainrots(brainrotData, placedBrainrots)
	local unlockedMap = self:_getOrCreateUnlockedBrainrotMap(brainrotData)
	if not unlockedMap then
		return {}
	end

	if type(brainrotData.Inventory) == "table" then
		for _, inventoryItem in ipairs(brainrotData.Inventory) do
			local brainrotId = math.floor(tonumber(inventoryItem.BrainrotId) or 0)
			if brainrotId > 0 and BrainrotConfig.ById[brainrotId] then
				unlockedMap[tostring(brainrotId)] = true
			end
		end
	end

	if type(placedBrainrots) == "table" then
		for _, placedData in pairs(placedBrainrots) do
			local brainrotId = math.floor(tonumber(placedData.BrainrotId) or 0)
			if brainrotId > 0 and BrainrotConfig.ById[brainrotId] then
				unlockedMap[tostring(brainrotId)] = true
			end
		end
	end

	return unlockedMap
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
	local slot = ensureTable(productionState, positionKey)
	slot.CurrentGold = roundBrainrotEconomicValue(slot.CurrentGold)
	slot.OfflineGold = roundBrainrotEconomicValue(slot.OfflineGold)
	slot.FriendBonusRemainder = roundBrainrotEconomicValue(slot.FriendBonusRemainder)

	if slot.FriendBonusRemainder > 0 then
		slot.CurrentGold = roundBrainrotEconomicValue(slot.CurrentGold + slot.FriendBonusRemainder)
		slot.FriendBonusRemainder = 0
	end

	return slot
end

function BrainrotService:_resetProductionSlotValues(slot)
	if type(slot) ~= "table" then
		return
	end

	slot.CurrentGold = 0
	slot.OfflineGold = 0
	slot.FriendBonusRemainder = 0
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
	return 1 + rebirthBonusRate
end

function BrainrotService:_computePlacedBaseProductionSpeed(placedBrainrots)
	local baseSpeed = 0
	if type(placedBrainrots) ~= "table" then
		return 0
	end

	for _, placedData in pairs(placedBrainrots) do
		local brainrotId = tonumber(placedData.BrainrotId)
		local brainrotDefinition = brainrotId and BrainrotConfig.ById[brainrotId] or nil
		if brainrotDefinition then
			baseSpeed += getBrainrotProductionSpeed(brainrotDefinition, placedData.Level)
		end
	end

	return roundBrainrotEconomicValue(baseSpeed)
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
	self:_syncUnlockedBrainrots(brainrotData, placedBrainrots)

	if brainrotData.StarterGranted then
		return
	end

	local hasPlaced = next(placedBrainrots) ~= nil
	if #brainrotData.Inventory > 0 or hasPlaced then
		brainrotData.StarterGranted = true
		return
	end

	for _, brainrotId in ipairs(BrainrotConfig.StarterBrainrotIds) do
		if BrainrotConfig.ById[brainrotId] then
			local instanceId = brainrotData.NextInstanceId
			brainrotData.NextInstanceId += 1

			table.insert(brainrotData.Inventory, {
				InstanceId = instanceId,
				BrainrotId = brainrotId,
				Level = getBaseBrainrotLevel(),
			})
			self:_markBrainrotUnlocked(brainrotData, brainrotId)
		end
	end

	brainrotData.StarterGranted = true
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

function BrainrotService:_onToolEquipped(player, tool)
	local _playerData, brainrotData = self:_getOrCreateDataContainers(player)
	if not brainrotData then
		return
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

	local targetInstanceId = math.max(0, math.floor(tonumber(instanceId) or 0))
	if targetInstanceId <= 0 then
		return false, "InvalidInstanceId", nil
	end

	local inventoryIndex = findInventoryIndexByInstanceId(senderBrainrotData.Inventory, targetInstanceId)
	if not inventoryIndex then
		return false, "BrainrotNotFound", nil
	end

	local inventoryItem = senderBrainrotData.Inventory[inventoryIndex]
	local brainrotId = math.max(0, math.floor(tonumber(inventoryItem and inventoryItem.BrainrotId) or 0))
	local level = normalizeBrainrotLevel(inventoryItem and inventoryItem.Level)
	local brainrotDefinition = BrainrotConfig.ById[brainrotId]
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
	self:_markBrainrotUnlocked(recipientBrainrotData, brainrotId)
	table.insert(recipientBrainrotData.Inventory, {
		InstanceId = recipientInstanceId,
		BrainrotId = brainrotId,
		Level = level,
	})

	local reEquipInstanceId = 0
	if previousEquippedInstanceId > 0 and previousEquippedInstanceId ~= targetInstanceId then
		if findInventoryIndexByInstanceId(senderBrainrotData.Inventory, previousEquippedInstanceId) then
			reEquipInstanceId = previousEquippedInstanceId
		end
	end

	self:_refreshBrainrotTools(senderPlayer)
	self:_refreshBrainrotTools(recipientPlayer)
	if reEquipInstanceId > 0 then
		task.defer(function()
			self:_equipBrainrotToolByInstanceId(senderPlayer, reEquipInstanceId)
		end)
	end

	self:PushBrainrotState(senderPlayer)
	self:PushBrainrotState(recipientPlayer)

	return true, tostring(reason or "Gift"), {
		brainrotId = brainrotId,
		brainrotName = tostring(brainrotDefinition.Name or "Brainrot"),
		level = level,
		senderInstanceId = targetInstanceId,
		recipientInstanceId = recipientInstanceId,
	}
end

function BrainrotService:GrantBrainrotInstance(player, brainrotId, level, reason)
	local parsedBrainrotId = math.floor(tonumber(brainrotId) or 0)
	if parsedBrainrotId <= 0 then
		return false, "InvalidBrainrotId", nil
	end

	local brainrotDefinition = BrainrotConfig.ById[parsedBrainrotId]
	if not brainrotDefinition then
		return false, "BrainrotNotFound", nil
	end

	local _playerData, brainrotData = self:_getOrCreateDataContainers(player)
	if not brainrotData then
		return false, "PlayerDataNotReady", nil
	end

	brainrotData.StarterGranted = true
	self:_markBrainrotUnlocked(brainrotData, parsedBrainrotId)

	local instanceId = math.max(1, math.floor(tonumber(brainrotData.NextInstanceId) or 1))
	brainrotData.NextInstanceId = instanceId + 1

	local inventoryItem = {
		InstanceId = instanceId,
		BrainrotId = parsedBrainrotId,
		Level = normalizeBrainrotLevel(level),
	}
	table.insert(brainrotData.Inventory, inventoryItem)

	local backpack = player and (player:FindFirstChild("Backpack") or player:WaitForChild("Backpack", 2)) or nil
	if backpack then
		local tool = self:_createBrainrotTool(player, inventoryItem)
		if tool then
			tool.Parent = backpack
		end
	end

	self:PushBrainrotState(player)
	return true, tostring(reason or "Unknown"), {
		instanceId = instanceId,
		brainrotId = parsedBrainrotId,
		brainrotName = tostring(brainrotDefinition.Name or "Brainrot"),
		level = inventoryItem.Level,
	}
end

function BrainrotService:ConsumeBrainrotInstance(player, instanceId, reason)
	local _playerData, brainrotData, placedBrainrots, productionState = self:_getOrCreateDataContainers(player)
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
			local brainrotDefinition = BrainrotConfig.ById[brainrotId]
			local level = normalizeBrainrotLevel(placedData and placedData.Level)

			placedBrainrots[positionKey] = nil
			self:_destroyRuntimePlacedAtPosition(player, positionKey)
			local productionSlot = self:_getOrCreateProductionSlot(productionState, positionKey)
			self:_resetProductionSlotValues(productionSlot)
			self:PushBrainrotState(player)
			self:_refreshClaimUiForPosition(player, positionKey, placedBrainrots, productionState)
			self:_refreshBrandUiForPosition(player, positionKey, placedBrainrots)
			self:_refreshPlatformPromptState(player, positionKey, placedBrainrots)
			self:_updatePlayerTotalProductionSpeed(player, placedBrainrots)

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

	local inventoryIndex = findInventoryIndexByInstanceId(brainrotData.Inventory, targetInstanceId)
	if not inventoryIndex then
		return false, "BrainrotNotFound", nil
	end

	local inventoryItem = brainrotData.Inventory[inventoryIndex]
	local brainrotId = math.max(0, math.floor(tonumber(inventoryItem and inventoryItem.BrainrotId) or 0))
	local brainrotDefinition = BrainrotConfig.ById[brainrotId]
	local level = normalizeBrainrotLevel(inventoryItem and inventoryItem.Level)
	local previousEquippedInstanceId = math.max(0, math.floor(tonumber(brainrotData.EquippedInstanceId) or 0))

	table.remove(brainrotData.Inventory, inventoryIndex)

	local reEquipInstanceId = 0
	if previousEquippedInstanceId > 0 and previousEquippedInstanceId ~= targetInstanceId then
		if findInventoryIndexByInstanceId(brainrotData.Inventory, previousEquippedInstanceId) then
			reEquipInstanceId = previousEquippedInstanceId
		end
	elseif previousEquippedInstanceId == targetInstanceId then
		brainrotData.EquippedInstanceId = 0
	end

	self:_refreshBrainrotTools(player)
	if reEquipInstanceId > 0 then
		task.defer(function()
			self:_equipBrainrotToolByInstanceId(player, reEquipInstanceId)
		end)
	end

	self:PushBrainrotState(player)
	return true, tostring(reason or "Consumed"), {
		source = previousEquippedInstanceId == targetInstanceId and "Equipped" or "Inventory",
		instanceId = targetInstanceId,
		brainrotId = brainrotId,
		brainrotName = brainrotDefinition and tostring(brainrotDefinition.Name or "Brainrot") or "Brainrot",
		level = level,
	}
end

function BrainrotService:GrantBrainrot(player, brainrotId, quantity, reason)
	local parsedBrainrotId = math.floor(tonumber(brainrotId) or 0)
	local parsedQuantity = math.floor(tonumber(quantity) or 0)
	if parsedBrainrotId <= 0 or parsedQuantity <= 0 then
		return false, "InvalidParams", 0
	end

	local brainrotDefinition = BrainrotConfig.ById[parsedBrainrotId]
	if not brainrotDefinition then
		return false, "BrainrotNotFound", 0
	end

	local _playerData, brainrotData = self:_getOrCreateDataContainers(player)
	if not brainrotData then
		return false, "PlayerDataNotReady", 0
	end

	brainrotData.StarterGranted = true
	self:_markBrainrotUnlocked(brainrotData, parsedBrainrotId)

	local backpack = player:FindFirstChild("Backpack") or player:WaitForChild("Backpack", 2)
	local grantedCount = 0

	for _ = 1, parsedQuantity do
		local instanceId = brainrotData.NextInstanceId
		brainrotData.NextInstanceId += 1

		local inventoryItem = {
			InstanceId = instanceId,
			BrainrotId = parsedBrainrotId,
			Level = getBaseBrainrotLevel(),
		}
		table.insert(brainrotData.Inventory, inventoryItem)
		grantedCount += 1

		if backpack then
			local tool = self:_createBrainrotTool(player, inventoryItem)
			if tool then
				tool.Parent = backpack
			end
		end
	end

	if grantedCount > 0 then
		self:PushBrainrotState(player)
		return true, tostring(reason or "Unknown"), grantedCount
	end

	return false, "GrantFailed", 0
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

	for positionKey, placedData in pairs(placedBrainrots) do
		local brainrotId = tonumber(placedData.BrainrotId)
		local brainrotDefinition = brainrotId and BrainrotConfig.ById[brainrotId] or nil
		if brainrotDefinition then
			local coinPerSecond = getBrainrotProductionSpeed(brainrotDefinition, placedData.Level)
			if coinPerSecond > 0 then
				local slot = self:_getOrCreateProductionSlot(productionState, positionKey)
				local producedExact = coinPerSecond * effectiveSeconds * offlineMultiplier
				slot.OfflineGold = roundBrainrotEconomicValue(slot.OfflineGold + producedExact)
			end
		end
	end

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
	})
end

function BrainrotService:_tickProduction()
	for _, player in ipairs(Players:GetPlayers()) do
		local playerData, _brainrotData, placedBrainrots, productionState = self:_getOrCreateDataContainers(player)
		if playerData and type(placedBrainrots) == "table" and type(productionState) == "table" then
			local changedPositions = {}
			local bonusMultiplier = select(1, self:_resolveProductionMultiplier(player))

			for positionKey, placedData in pairs(placedBrainrots) do
				local brainrotId = tonumber(placedData.BrainrotId)
				local brainrotDefinition = brainrotId and BrainrotConfig.ById[brainrotId] or nil
				if brainrotDefinition then
					local coinPerSecond = getBrainrotProductionSpeed(brainrotDefinition, placedData.Level)
					if coinPerSecond > 0 then
						local slot = self:_getOrCreateProductionSlot(productionState, positionKey)
						local producedExact = coinPerSecond * bonusMultiplier
						slot.CurrentGold = roundBrainrotEconomicValue(slot.CurrentGold + producedExact)
						changedPositions[positionKey] = true
					end
				end
			end

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
	self:_clearPromptConnections(player)
	self:_clearClaimConnections(player)
	self:_clearToolConnections(player)
	self:_clearToolRefreshWatchers(player)
	self:_clearBrandState(player)
	self:_clearRuntimePlaced(player)
	self._sellRequestClockByUserId[player.UserId] = nil
	self._pendingStealPurchaseByBuyerUserId[player.UserId] = nil

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
	self._remoteEventService = dependencies.RemoteEventService
	self._receiptHandlers = type(dependencies.ReceiptHandlers) == "table" and dependencies.ReceiptHandlers or {}

	self._brainrotStateSyncEvent = self._remoteEventService:GetEvent("BrainrotStateSync")
	self._requestBrainrotStateSyncEvent = self._remoteEventService:GetEvent("RequestBrainrotStateSync")
	self._requestBrainrotUpgradeEvent = self._remoteEventService:GetEvent("RequestBrainrotUpgrade")
	self._brainrotUpgradeFeedbackEvent = self._remoteEventService:GetEvent("BrainrotUpgradeFeedback")
	self._requestBrainrotSellEvent = self._remoteEventService:GetEvent("RequestBrainrotSell")
	self._brainrotSellFeedbackEvent = self._remoteEventService:GetEvent("BrainrotSellFeedback")
	self._requestStudioBrainrotGrantEvent = self._remoteEventService:GetEvent("RequestStudioBrainrotGrant")
	self._studioBrainrotGrantFeedbackEvent = self._remoteEventService:GetEvent("StudioBrainrotGrantFeedback")
	self._claimCashFeedbackEvent = self._remoteEventService:GetEvent("ClaimCashFeedback")
	self._promptBrainrotStealPurchaseEvent = self._remoteEventService:GetEvent("PromptBrainrotStealPurchase")
	self._requestBrainrotStealPurchaseClosedEvent = self._remoteEventService:GetEvent("RequestBrainrotStealPurchaseClosed")
	self._brainrotStealFeedbackEvent = self._remoteEventService:GetEvent("BrainrotStealFeedback")
	self._stealTipEvent = self._remoteEventService:GetEvent("StealTip")
	self:_rebuildBrainrotStealProductIdLookup()

	if self._requestBrainrotStateSyncEvent then
		self._requestBrainrotStateSyncEvent.OnServerEvent:Connect(function(player)
			self:PushBrainrotState(player)
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

	if not self._processReceiptDispatcher then
		self._processReceiptDispatcher = function(receiptInfo)
			local handled, decision = self:_processBrainrotStealReceipt(receiptInfo)
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
			primaryPart = preferredNode.PrimaryPart or preferredNode:FindFirstChildWhichIsA("BasePart", true)
		elseif preferredNode and preferredNode:IsA("BasePart") then
			primaryPart = preferredNode
		end
	end

	if not primaryPart then
		local brainrotModel = model:FindFirstChild("BrainrotModel", true)
		if brainrotModel and brainrotModel:IsA("Model") then
			primaryPart = brainrotModel.PrimaryPart or brainrotModel:FindFirstChildWhichIsA("BasePart", true)
		end
	end

	if not primaryPart then
		local humanoidRootPart = model:FindFirstChild("HumanoidRootPart", true)
		if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
			primaryPart = humanoidRootPart
		end
	end

	if not primaryPart then
		local rootPart = model:FindFirstChild("RootPart", true)
		if rootPart and rootPart:IsA("BasePart") then
			primaryPart = rootPart
		end
	end

	if not primaryPart then
		local handle = model:FindFirstChild("Handle", true)
		if handle and handle:IsA("BasePart") then
			primaryPart = handle
		end
	end

	if not primaryPart then
		primaryPart = model:FindFirstChildWhichIsA("BasePart", true)
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
		local primaryPart = placedInstance.PrimaryPart or placedInstance:FindFirstChildWhichIsA("BasePart", true)
		if not primaryPart then
			placedInstance:Destroy()
			warn(string.format("[BrainrotService] 脑红模型缺少 BasePart: %s", tostring(brainrotDefinition.ModelPath)))
			return nil
		end

		-- 优先使用 HumanoidRootPart/RootPart 作为锚点，避免锚在头部等节点导致模型跑偏看不见。
		local humanoidRootPart = placedInstance:FindFirstChild("HumanoidRootPart", true)
		if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
			primaryPart = humanoidRootPart
		else
			local rootPart = placedInstance:FindFirstChild("RootPart", true)
			if rootPart and rootPart:IsA("BasePart") then
				primaryPart = rootPart
			end
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

	local _playerData, _brainrotData, placedBrainrots = self:_getOrCreateDataContainers(ownerPlayer)
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

	local pending = self:_setPendingStealPurchase(triggerPlayer, {
		RequestId = buildStealRequestId(triggerPlayer.UserId, ownerPlayer.UserId, placedData.InstanceId),
		BuyerUserId = triggerPlayer.UserId,
		OwnerUserId = ownerPlayer.UserId,
		OwnerName = ownerPlayer.Name,
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

	local placedData = placedBrainrots[positionKey]
	if type(placedData) ~= "table" then
		self:_refreshPlatformPromptState(player, positionKey, placedBrainrots)
		return false, nil
	end

	local inventoryItem = buildInventoryItemSnapshot(placedData.InstanceId, placedData.BrainrotId, placedData.Level)
	if inventoryItem.InstanceId <= 0 or inventoryItem.BrainrotId <= 0 then
		return false, nil
	end

	placedBrainrots[positionKey] = nil
	table.insert(brainrotData.Inventory, inventoryItem)
	brainrotData.EquippedInstanceId = 0

	self:_destroyRuntimePlacedAtPosition(player, positionKey)
	local productionSlot = self:_getOrCreateProductionSlot(productionState, positionKey)
	self:_resetProductionSlotValues(productionSlot)
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

	table.remove(brainrotData.Inventory, inventoryIndex)
	table.insert(brainrotData.Inventory, pickupInventoryItem)
	brainrotData.EquippedInstanceId = 0

	placedBrainrots[positionKey] = {
		InstanceId = equippedInstanceId,
		BrainrotId = equippedBrainrotId,
		Level = normalizeBrainrotLevel(equippedInventoryItem.Level),
		PlacedAt = os.time(),
	}

	local productionSlot = self:_getOrCreateProductionSlot(productionState, positionKey)
	self:_resetProductionSlotValues(productionSlot)
	self:_registerPlacedRuntime(player, positionKey, placedModel, equippedDefinition)
	self:_refreshBrainrotTools(player)

	task.defer(function()
		self:_equipBrainrotToolByInstanceId(player, pickupInventoryItem.InstanceId)
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
		placedBrainrots[positionKey] = nil
		local productionSlot = self:_getOrCreateProductionSlot(productionState, positionKey)
		self:_resetProductionSlotValues(productionSlot)
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

	table.remove(brainrotData.Inventory, inventoryIndex)
	brainrotData.EquippedInstanceId = 0

	placedBrainrots[positionKey] = {
		InstanceId = instanceId,
		BrainrotId = brainrotId,
		Level = normalizeBrainrotLevel(inventoryItem.Level),
		PlacedAt = os.time(),
	}

	local productionSlot = self:_getOrCreateProductionSlot(productionState, positionKey)
	self:_resetProductionSlotValues(productionSlot)
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

	if not placedBrainrots[positionKey] then
		self:_refreshClaimUiForPosition(player, positionKey, placedBrainrots, productionState)
		return false, 0
	end

	local slot = self:_getOrCreateProductionSlot(productionState, positionKey)
	local currentGold = slot.CurrentGold
	local offlineGold = slot.OfflineGold
	local claimAmount = currentGold + offlineGold
	if claimAmount <= 0 then
		return false, 0
	end

	slot.CurrentGold = 0
	slot.OfflineGold = 0

	local success = self._currencyService and self._currencyService:AddCoins(player, claimAmount, "BrainrotClaim")
	if not success then
		slot.CurrentGold = currentGold
		slot.OfflineGold = offlineGold
		return false, 0
	end

	self:_refreshClaimUiForPosition(player, positionKey, placedBrainrots, productionState)
	return true, claimAmount
end

function BrainrotService:ResetProductionForRebirth(player)
	local playerData, _brainrotData, placedBrainrots, productionState = self:_getOrCreateDataContainers(player)
	if not playerData or type(placedBrainrots) ~= "table" or type(productionState) ~= "table" then
		return false
	end

	for _, slot in pairs(productionState) do
		if type(slot) == "table" then
			slot.CurrentGold = 0
			slot.OfflineGold = 0
			slot.FriendBonusRemainder = 0
		end
	end

	for positionKey in pairs(placedBrainrots) do
		local slot = self:_getOrCreateProductionSlot(productionState, positionKey)
		slot.CurrentGold = 0
		slot.OfflineGold = 0
		slot.FriendBonusRemainder = 0
	end

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
		prompt.ActionText = "放置脑红"
		prompt.ObjectText = "脑红平台"
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

	local placedData = placedBrainrots[positionKey]
	if type(placedData) ~= "table" then
		self:_pushBrainrotUpgradeFeedback(player, "NoBrainrot", positionKey, getBaseBrainrotLevel(), 0, self._playerDataService and self._playerDataService:GetCoins(player) or 0)
		self:_refreshBrandUiForPosition(player, positionKey, placedBrainrots)
		return false
	end

	local brainrotId = tonumber(placedData.BrainrotId)
	local brainrotDefinition = brainrotId and BrainrotConfig.ById[brainrotId] or nil
	if not brainrotDefinition then
		self:_pushBrainrotUpgradeFeedback(player, "BrainrotNotFound", positionKey, placedData.Level, 0, self._playerDataService and self._playerDataService:GetCoins(player) or 0)
		return false
	end

	local currentLevel = normalizeBrainrotLevel(placedData.Level)
	local upgradeCost = getBrainrotUpgradeCost(brainrotDefinition, currentLevel)
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

	placedData.Level = currentLevel + 1

	local runtimePlaced = self._runtimePlacedByUserId[player.UserId]
	local runtimeInstance = runtimePlaced and runtimePlaced[positionKey] or nil
	if runtimeInstance and runtimeInstance.Parent then
		self:_attachPlacedInfoUi(runtimeInstance, brainrotDefinition, placedData.Level)
	end

	self:_refreshBrandUiForPosition(player, positionKey, placedBrainrots)
	self:_updatePlayerTotalProductionSpeed(player, placedBrainrots)
	self:PushBrainrotState(player)
	self:_pushBrainrotUpgradeFeedback(player, "Success", positionKey, placedData.Level, upgradeCost, nextCoins)
	return true
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

function BrainrotService:_pushBrainrotSellFeedback(player, status, soldCount, soldValue, remainingInventoryCount, mode, currentCoins, soldInstanceId)
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

function BrainrotService:_sellBrainrotByInstanceId(player, instanceId)
	local _playerData, brainrotData = self:_getOrCreateDataContainers(player)
	if not brainrotData then
		return false
	end

	local targetInstanceId = math.floor(tonumber(instanceId) or 0)
	if targetInstanceId <= 0 then
		self:_pushBrainrotSellFeedback(player, "InvalidInstanceId", 0, 0, #(brainrotData.Inventory or {}), "Single", self._playerDataService and self._playerDataService:GetCoins(player) or 0, 0)
		return false
	end

	local inventoryIndex = findInventoryIndexByInstanceId(brainrotData.Inventory, targetInstanceId)
	if not inventoryIndex then
		self:_pushBrainrotSellFeedback(player, "BrainrotNotFound", 0, 0, #(brainrotData.Inventory or {}), "Single", self._playerDataService and self._playerDataService:GetCoins(player) or 0, targetInstanceId)
		return false
	end

	local inventoryItem = brainrotData.Inventory[inventoryIndex]
	local brainrotId = tonumber(inventoryItem and inventoryItem.BrainrotId)
	local brainrotDefinition = brainrotId and BrainrotConfig.ById[brainrotId] or nil
	if not brainrotDefinition then
		self:_pushBrainrotSellFeedback(player, "BrainrotConfigMissing", 0, 0, #(brainrotData.Inventory or {}), "Single", self._playerDataService and self._playerDataService:GetCoins(player) or 0, targetInstanceId)
		return false
	end

	local sellPrice = getBrainrotSellPrice(brainrotDefinition)
	if sellPrice <= 0 then
		self:_pushBrainrotSellFeedback(player, "SellValueInvalid", 0, 0, #(brainrotData.Inventory or {}), "Single", self._playerDataService and self._playerDataService:GetCoins(player) or 0, targetInstanceId)
		return false
	end

	local success = false
	local nextCoins = 0
	local previousEquippedInstanceId = math.max(0, math.floor(tonumber(brainrotData.EquippedInstanceId) or 0))
	if self._currencyService then
		success, nextCoins = self._currencyService:AddCoins(player, sellPrice, "BrainrotSellSingle")
	end
	if not success then
		self:_pushBrainrotSellFeedback(player, "CurrencyFailed", 0, 0, #(brainrotData.Inventory or {}), "Single", self._playerDataService and self._playerDataService:GetCoins(player) or 0, targetInstanceId)
		return false
	end

	table.remove(brainrotData.Inventory, inventoryIndex)

	local reEquipInstanceId = 0
	if previousEquippedInstanceId > 0 and previousEquippedInstanceId ~= targetInstanceId then
		if findInventoryIndexByInstanceId(brainrotData.Inventory, previousEquippedInstanceId) then
			reEquipInstanceId = previousEquippedInstanceId
		end
	elseif previousEquippedInstanceId == targetInstanceId then
		brainrotData.EquippedInstanceId = 0
	end

	self:_refreshBrainrotTools(player)
	if reEquipInstanceId > 0 then
		task.defer(function()
			self:_equipBrainrotToolByInstanceId(player, reEquipInstanceId)
		end)
	end

	self:PushBrainrotState(player)
	self:_pushBrainrotSellFeedback(player, "Success", 1, sellPrice, #brainrotData.Inventory, "Single", nextCoins, targetInstanceId)
	return true
end

function BrainrotService:_sellAllBrainrots(player)
	local _playerData, brainrotData = self:_getOrCreateDataContainers(player)
	if not brainrotData then
		return false
	end

	local inventory = brainrotData.Inventory or {}
	if #inventory <= 0 then
		self:_pushBrainrotSellFeedback(player, "InventoryEmpty", 0, 0, 0, "All", self._playerDataService and self._playerDataService:GetCoins(player) or 0, 0)
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
		self:_pushBrainrotSellFeedback(player, "InventoryEmpty", 0, 0, #inventory, "All", self._playerDataService and self._playerDataService:GetCoins(player) or 0, 0)
		return false
	end

	local success = false
	local nextCoins = 0
	if self._currencyService then
		success, nextCoins = self._currencyService:AddCoins(player, totalSellValue, "BrainrotSellAll")
	end
	if not success then
		self:_pushBrainrotSellFeedback(player, "CurrencyFailed", 0, 0, #inventory, "All", self._playerDataService and self._playerDataService:GetCoins(player) or 0, 0)
		return false
	end

	brainrotData.Inventory = remainingInventory
	brainrotData.EquippedInstanceId = 0

	self:_refreshBrainrotTools(player)
	self:PushBrainrotState(player)
	self:_pushBrainrotSellFeedback(player, "Success", soldCount, totalSellValue, #brainrotData.Inventory, "All", nextCoins, 0)
	return true
end

function BrainrotService:_handleRequestBrainrotSell(player, payload)
	if not self:_canHandleSellRequest(player) then
		return
	end

	if type(payload) == "table" and payload.sellAll == true then
		self:_sellAllBrainrots(player)
		return
	end

	local instanceId = nil
	if type(payload) == "table" then
		instanceId = payload.instanceId
	else
		instanceId = payload
	end

	self:_sellBrainrotByInstanceId(player, instanceId)
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
	platformInfo.Prompt.Enabled = serverEnabled
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
