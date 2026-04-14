--[[
脚本名字: SocialService
脚本文件: SocialService.lua
脚本类型: ModuleScript
Studio放置路径: ServerScriptService/Services/SocialService
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
        "[SocialService] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local GameConfig = requireSharedModule("GameConfig")
local FormatUtil = requireSharedModule("FormatUtil")

local SocialService = {}
SocialService._playerDataService = nil
SocialService._homeService = nil
SocialService._remoteEventService = nil
SocialService._likeTipEvent = nil
SocialService._socialStateSyncEvent = nil
SocialService._requestSocialStateSyncEvent = nil
SocialService._homeInfoByName = {}
SocialService._promptConnectionsByHomeName = {}
SocialService._likeDebounceByUserId = {}

local function ensureTable(parentTable, key)
    if type(parentTable[key]) ~= "table" then
        parentTable[key] = {}
    end
    return parentTable[key]
end

local function asNonNegativeInteger(value)
    return math.max(0, math.floor(tonumber(value) or 0))
end

local function formatLikeText(totalLikes)
    local count = asNonNegativeInteger(totalLikes)
    local suffix = count == 1 and "Like!" or "Likes!"
    return string.format("%s %s", FormatUtil.FormatWithCommas(count), suffix)
end

local function findFirstTextLabel(root, name)
    if not root then
        return nil
    end

    local node = root:FindFirstChild(name, true)
    if node and node:IsA("TextLabel") then
        return node
    end

    return nil
end

local function findPlayerNameLabel(root)
    if not root then
        return nil
    end

    local playerNameNode = root:FindFirstChild("PlayerName", true)
    if playerNameNode then
        if playerNameNode:IsA("TextLabel") then
            return playerNameNode
        end

        local nameNode = playerNameNode:FindFirstChild("Name")
        if nameNode and nameNode:IsA("TextLabel") then
            return nameNode
        end

        local nestedNameNode = playerNameNode:FindFirstChild("Name", true)
        if nestedNameNode and nestedNameNode:IsA("TextLabel") then
            return nestedNameNode
        end

        local nestedTextLabel = playerNameNode:FindFirstChildWhichIsA("TextLabel", true)
        if nestedTextLabel then
            return nestedTextLabel
        end
    end

    return nil
end

local function findFirstImageLabel(root, name)
    if not root then
        return nil
    end

    local node = root:FindFirstChild(name, true)
    if node and node:IsA("ImageLabel") then
        return node
    end

    return nil
end

local function getUserAvatarImage(userId)
	local success, content, _isReady = pcall(function()
		return Players:GetUserThumbnailAsync(
            userId,
            Enum.ThumbnailType.HeadShot,
            Enum.ThumbnailSize.Size180x180
        )
    end)

    if success and type(content) == "string" then
        return content
    end

	return ""
end

local function computeBoundsFromParts(root, predicate)
	if not root then
		return nil, nil, nil
	end

	local minVector = nil
	local maxVector = nil

	local function includePart(part)
		if not part or not part:IsA("BasePart") then
			return false
		end
		if predicate then
			return predicate(part) == true
		end
		return true
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if not includePart(descendant) then
			continue
		end

		local halfSize = descendant.Size * 0.5
		local offsets = {
			Vector3.new(halfSize.X, halfSize.Y, halfSize.Z),
			Vector3.new(halfSize.X, halfSize.Y, -halfSize.Z),
			Vector3.new(halfSize.X, -halfSize.Y, halfSize.Z),
			Vector3.new(halfSize.X, -halfSize.Y, -halfSize.Z),
			Vector3.new(-halfSize.X, halfSize.Y, halfSize.Z),
			Vector3.new(-halfSize.X, halfSize.Y, -halfSize.Z),
			Vector3.new(-halfSize.X, -halfSize.Y, halfSize.Z),
			Vector3.new(-halfSize.X, -halfSize.Y, -halfSize.Z),
		}

		for _, offset in ipairs(offsets) do
			local position = descendant.CFrame:PointToWorldSpace(offset)
			if not minVector then
				minVector = position
				maxVector = position
			else
				minVector = Vector3.new(
					math.min(minVector.X, position.X),
					math.min(minVector.Y, position.Y),
					math.min(minVector.Z, position.Z)
				)
				maxVector = Vector3.new(
					math.max(maxVector.X, position.X),
					math.max(maxVector.Y, position.Y),
					math.max(maxVector.Z, position.Z)
				)
			end
		end
	end

	if not minVector or not maxVector then
		return nil, nil, nil
	end

	return (minVector + maxVector) * 0.5, maxVector - minVector, maxVector.Y
end

local function createGuiObject(className, properties)
	local instance = Instance.new(className)
	for propertyName, propertyValue in pairs(properties) do
		instance[propertyName] = propertyValue
	end
	return instance
end

function SocialService:_getOrCreateSocialState(player)
    local playerData = self._playerDataService:GetPlayerData(player)
    if type(playerData) ~= "table" then
        return nil
    end

    local socialState = ensureTable(playerData, "SocialState")
    socialState.LikesReceived = asNonNegativeInteger(socialState.LikesReceived)

    if type(socialState.LikedPlayerUserIds) ~= "table" then
        socialState.LikedPlayerUserIds = {}
    end

    return socialState
end

function SocialService:_collectLikedOwnerUserIds(player)
    local socialState = self:_getOrCreateSocialState(player)
    if not socialState then
        return {}
    end

    local likedOwnerUserIds = {}
    for key, isLiked in pairs(socialState.LikedPlayerUserIds) do
        if isLiked then
            local targetUserId = tonumber(key)
            if targetUserId and targetUserId > 0 then
                table.insert(likedOwnerUserIds, targetUserId)
            end
        end
    end

    table.sort(likedOwnerUserIds, function(a, b)
        return a < b
    end)

    return likedOwnerUserIds
end

function SocialService:_hasLikedTargetUser(socialState, targetUserId)
    if type(socialState) ~= "table" or type(socialState.LikedPlayerUserIds) ~= "table" then
        return false
    end

    return socialState.LikedPlayerUserIds[tostring(targetUserId)] == true
end

function SocialService:_markLikedTargetUser(socialState, targetUserId)
    if type(socialState) ~= "table" then
        return
    end

    local likedMap = ensureTable(socialState, "LikedPlayerUserIds")
    likedMap[tostring(targetUserId)] = true
end

local function cloneLikedPlayerUserIds(sourceMap)
    local likedMap = {}
    if type(sourceMap) ~= "table" then
        return likedMap
    end

    for key, isLiked in pairs(sourceMap) do
        if isLiked then
            local normalizedUserId = math.max(0, math.floor(tonumber(key) or 0))
            if normalizedUserId > 0 then
                likedMap[tostring(normalizedUserId)] = true
            end
        end
    end

    return likedMap
end

local function snapshotSocialState(socialState)
    if type(socialState) ~= "table" then
        return nil
    end

    return {
        LikesReceived = asNonNegativeInteger(socialState.LikesReceived),
        LikedPlayerUserIds = cloneLikedPlayerUserIds(socialState.LikedPlayerUserIds),
    }
end

local function restoreSocialState(socialState, snapshot)
    if not (type(socialState) == "table" and type(snapshot) == "table") then
        return
    end

    socialState.LikesReceived = asNonNegativeInteger(snapshot.LikesReceived)
    socialState.LikedPlayerUserIds = cloneLikedPlayerUserIds(snapshot.LikedPlayerUserIds)
end

function SocialService:PushSocialState(player)
    if not self._socialStateSyncEvent then
        return
    end

    self._socialStateSyncEvent:FireClient(player, {
        likedOwnerUserIds = self:_collectLikedOwnerUserIds(player),
    })
end

function SocialService:_pushLikeTip(player, message)
    if not self._likeTipEvent then
        return
    end

    self._likeTipEvent:FireClient(player, {
        message = tostring(message or ""),
        timestamp = os.clock(),
    })
end

function SocialService:_savePlayerDataSync(player)
    if not (self._playerDataService and player) then
        return false
    end

    return self._playerDataService:SavePlayerData(player, {
        SkipCommitPlaytime = true,
    })
end

function SocialService:_scanHomeInfo(homeModel)
	local homeName = homeModel and homeModel.Name or "UnknownHome"
    local homeBase = homeModel and homeModel:FindFirstChild(GameConfig.HOME.HomeBaseName)
    if not homeBase then
        return nil, string.format("缺少 HomeBase 节点（期望: %s/%s）", homeName, tostring(GameConfig.HOME.HomeBaseName))
    end

    local infoRootName = tostring(GameConfig.SOCIAL.InfoRootName or "Information")
    local infoPartName = tostring(GameConfig.SOCIAL.InfoPartName or "InfoPart")
    local surfaceGuiName = tostring(GameConfig.SOCIAL.SurfaceGuiName or "SurfaceGui01")

    local infoRoot = homeBase:FindFirstChild(infoRootName) or homeBase:FindFirstChild(infoRootName, true)
    local infoPart = nil
    if infoRoot then
        infoPart = infoRoot:FindFirstChild(infoPartName) or infoRoot:FindFirstChild(infoPartName, true)
    end
    if not infoPart then
        infoPart = homeBase:FindFirstChild(infoPartName, true)
    end
    if not (infoPart and infoPart:IsA("BasePart")) then
        local foundInfoPart = infoRoot and (infoRoot:FindFirstChild(infoPartName) or infoRoot:FindFirstChild(infoPartName, true)) or nil
        if foundInfoPart then
            return nil, string.format(
                "InfoPart 类型错误（期望 BasePart，实际 %s，节点: %s）",
                foundInfoPart.ClassName,
                foundInfoPart:GetFullName()
            )
        end
        return nil, string.format(
            "缺少 Information/InfoPart（期望路径: %s/%s/%s）",
            homeBase:GetFullName(),
            infoRootName,
            infoPartName
        )
    end

    local prompt = infoPart:FindFirstChildOfClass("ProximityPrompt")
    if not prompt then
        local nestedPrompt = infoPart:FindFirstChild("ProximityPrompt", true)
        if nestedPrompt and nestedPrompt:IsA("ProximityPrompt") then
            prompt = nestedPrompt
        end
    end
    if not prompt then
        return nil, string.format(
            "缺少 ProximityPrompt（搜索范围: %s）",
            infoPart:GetFullName()
        )
    end

    local surfaceGui = infoPart:FindFirstChild(surfaceGuiName)
    if not (surfaceGui and surfaceGui:IsA("SurfaceGui")) then
        local nestedSurfaceGui = infoPart:FindFirstChild(surfaceGuiName, true)
        if nestedSurfaceGui and nestedSurfaceGui:IsA("SurfaceGui") then
            surfaceGui = nestedSurfaceGui
        else
            surfaceGui = infoPart:FindFirstChildWhichIsA("SurfaceGui", true)
        end
    end
    if not surfaceGui then
        return nil, string.format(
            "缺少 SurfaceGui（优先节点名: %s，搜索范围: %s）",
            surfaceGuiName,
            infoPart:GetFullName()
        )
    end

    local frameRoot = surfaceGui:FindFirstChild("Frame") or surfaceGui:FindFirstChild("Frame", true)
    local searchRoot = frameRoot or surfaceGui

    local playerNameLabel = findPlayerNameLabel(searchRoot)
    if not playerNameLabel then
        playerNameLabel = findFirstTextLabel(searchRoot, "PlayerName")
    end

    local playerAvatarRoot = searchRoot:FindFirstChild("PlayerAvatar", true)
    local playerAvatarImage = nil
    if playerAvatarRoot then
        playerAvatarImage = findFirstImageLabel(playerAvatarRoot, "ImageLabel")
    end
    if not playerAvatarImage then
        playerAvatarImage = findFirstImageLabel(searchRoot, "ImageLabel")
    end

    local playerLikeRoot = searchRoot:FindFirstChild("PlayerLike", true)
    local playerLikeNumLabel = nil
    if playerLikeRoot then
        playerLikeNumLabel = findFirstTextLabel(playerLikeRoot, "Num")
    end
    if not playerLikeNumLabel then
        playerLikeNumLabel = findFirstTextLabel(searchRoot, "Num")
    end

    if not playerNameLabel or not playerAvatarImage or not playerLikeNumLabel then
        local missingParts = {}
        if not playerNameLabel then
            table.insert(missingParts, "PlayerName/Name(TextLabel)")
        end
        if not playerAvatarImage then
            table.insert(missingParts, "PlayerAvatar/ImageLabel(ImageLabel)")
        end
        if not playerLikeNumLabel then
            table.insert(missingParts, "PlayerLike/Num(TextLabel)")
        end
        return nil, string.format(
            "信息板 UI 子节点缺失: %s（搜索范围: %s）",
            table.concat(missingParts, ", "),
            searchRoot:GetFullName()
        )
    end

	return {
		HomeName = homeModel.Name,
		HomeModel = homeModel,
		InfoPart = infoPart,
		Prompt = prompt,
		PlayerNameLabel = playerNameLabel,
		PlayerAvatarImage = playerAvatarImage,
		PlayerLikeNumLabel = playerLikeNumLabel,
		FloatingAnchorPart = nil,
		FloatingBillboard = nil,
		FloatingNameLabel = nil,
		FloatingAvatarImage = nil,
		AvatarToken = 0,
	}
end

function SocialService:_findHighestFloatingTopBounds(homeModel)
	local socialConfig = GameConfig.SOCIAL or {}
	local topModelName = tostring(socialConfig.FloatingTopModelName or "TOP")
	local anchorName = tostring(socialConfig.FloatingAnchorName or "HomeOwnerBillboardAnchor")

	local bestCenter = nil
	local bestSize = nil
	local bestTopY = nil

	local function isVisibleTopPart(part)
		if not part or not part:IsA("BasePart") then
			return false
		end
		if part.Name == anchorName or part:GetAttribute("SocialOwnerBillboardAnchor") == true then
			return false
		end
		return part.Transparency < 0.95
	end

	for _, descendant in ipairs(homeModel:GetDescendants()) do
		if descendant:IsA("Model") and descendant.Name == topModelName then
			local center, size, topY = computeBoundsFromParts(descendant, isVisibleTopPart)
			if center and topY and (not bestTopY or topY > bestTopY) then
				bestCenter = center
				bestSize = size
				bestTopY = topY
			end
		end
	end

	if bestCenter and bestTopY then
		return bestCenter, bestSize, bestTopY
	end

	return computeBoundsFromParts(homeModel, function(part)
		if part.Name == anchorName or part:GetAttribute("SocialOwnerBillboardAnchor") == true then
			return false
		end
		return part.Transparency < 0.95
	end)
end

function SocialService:_resolveFloatingAnchorCFrame(homeInfo)
	if not (homeInfo and homeInfo.HomeModel) then
		return nil
	end

	local socialConfig = GameConfig.SOCIAL or {}
	local center, _size, topY = self:_findHighestFloatingTopBounds(homeInfo.HomeModel)
	local heightOffset = tonumber(socialConfig.FloatingHeightOffset) or 4
	local horizontalPosition = nil
	local homeBase = homeInfo.HomeModel:FindFirstChild(GameConfig.HOME.HomeBaseName)
	local spawnLocation = homeBase and homeBase:FindFirstChild(GameConfig.HOME.SpawnLocationName)
	if spawnLocation and spawnLocation:IsA("BasePart") then
		horizontalPosition = Vector3.new(spawnLocation.Position.X, 0, spawnLocation.Position.Z)
	elseif homeInfo.InfoPart then
		horizontalPosition = Vector3.new(homeInfo.InfoPart.Position.X, 0, homeInfo.InfoPart.Position.Z)
	elseif center then
		horizontalPosition = Vector3.new(center.X, 0, center.Z)
	end

	if horizontalPosition and topY then
		return CFrame.new(horizontalPosition.X, topY + heightOffset, horizontalPosition.Z)
	end

	if homeInfo.InfoPart then
		return CFrame.new(homeInfo.InfoPart.Position + Vector3.new(0, heightOffset + 12, 0))
	end

	return nil
end

function SocialService:_ensureFloatingBillboard(homeInfo)
	if not (homeInfo and homeInfo.HomeModel) then
		return nil
	end

	local socialConfig = GameConfig.SOCIAL or {}
	local anchorName = tostring(socialConfig.FloatingAnchorName or "HomeOwnerBillboardAnchor")
	local billboardName = tostring(socialConfig.FloatingBillboardName or "HomeOwnerBillboard")

	local anchorPart = homeInfo.FloatingAnchorPart
	if not (anchorPart and anchorPart.Parent) then
		local existingAnchor = homeInfo.HomeModel:FindFirstChild(anchorName)
		if existingAnchor and existingAnchor:IsA("BasePart") then
			anchorPart = existingAnchor
		else
			anchorPart = createGuiObject("Part", {
				Name = anchorName,
				Anchored = true,
				CanCollide = false,
				CanTouch = false,
				CanQuery = false,
				Transparency = 1,
				Size = Vector3.new(1, 1, 1),
				CastShadow = false,
			})
			anchorPart:SetAttribute("SocialOwnerBillboardAnchor", true)
			anchorPart.Parent = homeInfo.HomeModel
		end
		homeInfo.FloatingAnchorPart = anchorPart
	end

	local existingBillboard = anchorPart:FindFirstChild(billboardName)
	if existingBillboard and not existingBillboard:IsA("BillboardGui") then
		existingBillboard:Destroy()
		existingBillboard = nil
	end

	local billboard = existingBillboard
	local nameLabel = nil
	local avatarImage = nil
	if billboard and billboard:IsA("BillboardGui") then
		nameLabel = billboard:FindFirstChild("PlayerNameLabel", true)
		avatarImage = billboard:FindFirstChild("PlayerAvatarImage", true)
	end

	if not (billboard and nameLabel and avatarImage) then
		if billboard then
			billboard:Destroy()
		end

		billboard = createGuiObject("BillboardGui", {
			Name = billboardName,
			AlwaysOnTop = true,
			LightInfluence = 0,
			MaxDistance = tonumber(socialConfig.FloatingMaxDistance) or 240,
			Size = socialConfig.FloatingSize or UDim2.fromScale(20, 6.4),
			Enabled = false,
		})
		billboard.Adornee = anchorPart
		billboard.Parent = anchorPart

		local frame = createGuiObject("Frame", {
			Name = "Frame",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
		})
		frame.Parent = billboard

		avatarImage = createGuiObject("ImageLabel", {
			Name = "PlayerAvatarImage",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromScale(0.22, 0.7),
			ScaleType = Enum.ScaleType.Crop,
			Image = "",
		})
		avatarImage.Parent = frame

		createGuiObject("UICorner", {
			CornerRadius = UDim.new(1, 0),
		}).Parent = avatarImage

		nameLabel = createGuiObject("TextLabel", {
			Name = "PlayerNameLabel",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0.27, 0.5),
			Size = UDim2.fromScale(0.73, 0.8),
			Font = Enum.Font.GothamBold,
			Text = "Empty",
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextScaled = true,
			TextStrokeTransparency = 1,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
		})
		nameLabel.Parent = frame

		createGuiObject("UITextSizeConstraint", {
			MaxTextSize = 44,
			MinTextSize = 20,
		}).Parent = nameLabel
	end

	homeInfo.FloatingBillboard = billboard
	homeInfo.FloatingNameLabel = nameLabel
	homeInfo.FloatingAvatarImage = avatarImage

	return billboard
end

function SocialService:_refreshFloatingBillboardTransform(homeInfo)
	local billboard = self:_ensureFloatingBillboard(homeInfo)
	local anchorPart = homeInfo and homeInfo.FloatingAnchorPart or nil
	if not (billboard and anchorPart) then
		return
	end

	local anchorCFrame = self:_resolveFloatingAnchorCFrame(homeInfo)
	if anchorCFrame then
		anchorPart.CFrame = anchorCFrame
	end
	billboard.Adornee = anchorPart
end

function SocialService:_setPromptOwner(homeInfo, ownerUserId)
	local prompt = homeInfo and homeInfo.Prompt
    if not prompt then
        return
    end

    local socialConfig = GameConfig.SOCIAL or {}
    local resolvedOwnerUserId = asNonNegativeInteger(ownerUserId)
    prompt:SetAttribute("SocialLikePrompt", true)
    prompt:SetAttribute("InfoHomeId", homeInfo.HomeName)
    prompt:SetAttribute("InfoOwnerUserId", resolvedOwnerUserId)
    prompt.ActionText = tostring(socialConfig.PromptActionText or "Like")
    prompt.ObjectText = tostring(socialConfig.PromptObjectText or "Home Info")
    prompt.HoldDuration = tonumber(socialConfig.PromptHoldDuration) or 1
    prompt.Enabled = resolvedOwnerUserId > 0
end

function SocialService:_setHomeInfoEmpty(homeInfo)
	if not homeInfo then
		return
	end

	self:_refreshFloatingBillboardTransform(homeInfo)

	if homeInfo.PlayerNameLabel then
		homeInfo.PlayerNameLabel.Text = "Empty"
	end
	if homeInfo.PlayerAvatarImage then
		homeInfo.PlayerAvatarImage.Image = ""
	end
	if homeInfo.FloatingNameLabel then
		homeInfo.FloatingNameLabel.Text = "Empty"
	end
	if homeInfo.FloatingAvatarImage then
		homeInfo.FloatingAvatarImage.Image = ""
	end
	if homeInfo.FloatingBillboard then
		homeInfo.FloatingBillboard.Enabled = false
	end
	if homeInfo.PlayerLikeNumLabel then
		homeInfo.PlayerLikeNumLabel.Text = formatLikeText(0)
	end

    self:_setPromptOwner(homeInfo, 0)
end

function SocialService:_setHomeInfoOwner(homeInfo, ownerPlayer)
	if not homeInfo then
		return
	end
	if not ownerPlayer then
        self:_setHomeInfoEmpty(homeInfo)
        return
    end

	local ownerSocialState = self:_getOrCreateSocialState(ownerPlayer)
	local likesReceived = ownerSocialState and ownerSocialState.LikesReceived or 0

	self:_refreshFloatingBillboardTransform(homeInfo)

	if homeInfo.PlayerNameLabel then
		homeInfo.PlayerNameLabel.Text = ownerPlayer.Name
	end
	if homeInfo.FloatingNameLabel then
		homeInfo.FloatingNameLabel.Text = ownerPlayer.Name
	end
	if homeInfo.PlayerLikeNumLabel then
		homeInfo.PlayerLikeNumLabel.Text = formatLikeText(likesReceived)
	end
	if homeInfo.FloatingBillboard then
		homeInfo.FloatingBillboard.Enabled = true
	end
	if homeInfo.PlayerAvatarImage then
		homeInfo.PlayerAvatarImage.Image = ""
	end
	if homeInfo.FloatingAvatarImage then
		homeInfo.FloatingAvatarImage.Image = ""
	end

	homeInfo.AvatarToken += 1
	local avatarToken = homeInfo.AvatarToken
	local ownerUserId = ownerPlayer.UserId
	task.spawn(function()
		local avatarImage = getUserAvatarImage(ownerUserId)
		if homeInfo.AvatarToken ~= avatarToken then
			return
		end
		if homeInfo.PlayerAvatarImage and homeInfo.PlayerAvatarImage.Parent then
			homeInfo.PlayerAvatarImage.Image = avatarImage
		end
		if homeInfo.FloatingAvatarImage and homeInfo.FloatingAvatarImage.Parent then
			homeInfo.FloatingAvatarImage.Image = avatarImage
		end
	end)

	self:_setPromptOwner(homeInfo, ownerPlayer.UserId)
end

function SocialService:_refreshHomeInfoByName(homeName)
    local homeInfo = self._homeInfoByName[homeName]
    if not homeInfo then
        return
    end

    local ownerUserId = self._homeService:GetHomeOwnerUserId(homeName)
    local ownerPlayer = nil
    if ownerUserId and ownerUserId > 0 then
        ownerPlayer = Players:GetPlayerByUserId(ownerUserId)
    end

    if ownerPlayer then
        self:_setHomeInfoOwner(homeInfo, ownerPlayer)
    else
        self:_setHomeInfoEmpty(homeInfo)
    end
end

function SocialService:_refreshAllHomeInfos()
    for homeName in pairs(self._homeInfoByName) do
        self:_refreshHomeInfoByName(homeName)
    end
end

function SocialService:_bindHomePrompt(homeInfo)
    local homeName = homeInfo.HomeName
    local prompt = homeInfo.Prompt
    if not prompt then
        return
    end

    local previousConnection = self._promptConnectionsByHomeName[homeName]
    if previousConnection then
        previousConnection:Disconnect()
        self._promptConnectionsByHomeName[homeName] = nil
    end

    self._promptConnectionsByHomeName[homeName] = prompt.Triggered:Connect(function(triggerPlayer)
        self:_onLikePromptTriggered(triggerPlayer, homeName)
    end)
end

function SocialService:_registerHome(homeName, homeModel)
	local homeInfo, missingReason = self:_scanHomeInfo(homeModel)
    if not homeInfo then
        warn(string.format(
            "[SocialService] 家园信息节点不完整，已跳过: %s，原因: %s",
            tostring(homeName),
            tostring(missingReason or "未知")
        ))
        return
	end

	self._homeInfoByName[homeName] = homeInfo
	self:_refreshFloatingBillboardTransform(homeInfo)
	self:_bindHomePrompt(homeInfo)
end

function SocialService:_onLikePromptTriggered(likerPlayer, homeName)
    if not likerPlayer then
        return
    end

    local nowClock = os.clock()
    local lastClock = tonumber(self._likeDebounceByUserId[likerPlayer.UserId]) or 0
    if nowClock - lastClock < 0.2 then
        return
    end
    self._likeDebounceByUserId[likerPlayer.UserId] = nowClock

    local ownerUserId = self._homeService:GetHomeOwnerUserId(homeName)
    if not ownerUserId or ownerUserId <= 0 then
        return
    end

    if likerPlayer.UserId == ownerUserId then
        self:PushSocialState(likerPlayer)
        return
    end

    local ownerPlayer = Players:GetPlayerByUserId(ownerUserId)
    if not ownerPlayer then
        return
    end

    local likerSocialState = self:_getOrCreateSocialState(likerPlayer)
    local ownerSocialState = self:_getOrCreateSocialState(ownerPlayer)
    if not likerSocialState or not ownerSocialState then
        return
    end

    if self:_hasLikedTargetUser(likerSocialState, ownerUserId) then
        self:PushSocialState(likerPlayer)
        return
    end

    local likerSocialSnapshot = snapshotSocialState(likerSocialState)
    local ownerSocialSnapshot = snapshotSocialState(ownerSocialState)

    self:_markLikedTargetUser(likerSocialState, ownerUserId)
    ownerSocialState.LikesReceived = asNonNegativeInteger(ownerSocialState.LikesReceived) + 1

    local didSaveLiker = self:_savePlayerDataSync(likerPlayer)
    local didSaveOwner = self:_savePlayerDataSync(ownerPlayer)
    if not (didSaveLiker and didSaveOwner) then
        restoreSocialState(likerSocialState, likerSocialSnapshot)
        restoreSocialState(ownerSocialState, ownerSocialSnapshot)

        local didRollbackLikerSave = self:_savePlayerDataSync(likerPlayer)
        local didRollbackOwnerSave = self:_savePlayerDataSync(ownerPlayer)
        if didRollbackLikerSave ~= true or didRollbackOwnerSave ~= true then
            warn(string.format(
                "[SocialService] rollback save failed likerUserId=%d ownerUserId=%d rollbackLiker=%s rollbackOwner=%s",
                likerPlayer.UserId,
                ownerPlayer.UserId,
                tostring(didRollbackLikerSave),
                tostring(didRollbackOwnerSave)
            ))
        end

        self:_refreshHomeInfoByName(homeName)
        self:PushSocialState(likerPlayer)
        self:PushSocialState(ownerPlayer)
        self:_pushLikeTip(likerPlayer, "Like failed, please retry.")
        return
    end

    self:_refreshHomeInfoByName(homeName)
    self:PushSocialState(likerPlayer)
    self:PushSocialState(ownerPlayer)

    self:_pushLikeTip(likerPlayer, "You liked this home!")
    self:_pushLikeTip(ownerPlayer, string.format("%s gave you a like!", likerPlayer.Name))
end

function SocialService:OnPlayerReady(player, assignedHome)
    self:_getOrCreateSocialState(player)

    local home = assignedHome or self._homeService:GetAssignedHome(player)
    if home then
        self:_refreshHomeInfoByName(home.Name)
    end

    self:PushSocialState(player)
end

function SocialService:OnPlayerRemoving(player, assignedHome)
	self._likeDebounceByUserId[player.UserId] = nil

    local home = assignedHome or self._homeService:GetAssignedHome(player)
    if home then
        local homeInfo = self._homeInfoByName[home.Name]
        self:_setHomeInfoEmpty(homeInfo)
	end
end

function SocialService:OnHomeLayoutChanged(player, assignedHome)
	local home = assignedHome or self._homeService:GetAssignedHome(player)
	if home then
		self:_refreshHomeInfoByName(home.Name)
	end
end

function SocialService:Init(dependencies)
    self._playerDataService = dependencies.PlayerDataService
    self._homeService = dependencies.HomeService
    self._remoteEventService = dependencies.RemoteEventService

    self._likeTipEvent = self._remoteEventService:GetEvent("LikeTip")
    self._socialStateSyncEvent = self._remoteEventService:GetEvent("SocialStateSync")
    self._requestSocialStateSyncEvent = self._remoteEventService:GetEvent("RequestSocialStateSync")

    if self._requestSocialStateSyncEvent then
        self._requestSocialStateSyncEvent.OnServerEvent:Connect(function(player)
            self:PushSocialState(player)
        end)
    end

    self._homeInfoByName = {}
    self._promptConnectionsByHomeName = {}

    for index = 1, GameConfig.HOME.Count do
        local homeName = string.format("%s%02d", GameConfig.HOME.Prefix, index)
        local homeModel = self._homeService:GetHomeByName(homeName)
        if homeModel then
            self:_registerHome(homeName, homeModel)
        else
            warn(string.format("[SocialService] 找不到家园模型: %s", homeName))
        end
    end

    self:_refreshAllHomeInfos()
end

return SocialService
