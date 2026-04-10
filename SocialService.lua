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
        InfoPart = infoPart,
        Prompt = prompt,
        PlayerNameLabel = playerNameLabel,
        PlayerAvatarImage = playerAvatarImage,
        PlayerLikeNumLabel = playerLikeNumLabel,
        AvatarToken = 0,
    }
end

function SocialService:_setPromptOwner(homeInfo, ownerUserId)
    local prompt = homeInfo and homeInfo.Prompt
    if not prompt then
        return
    end

    local resolvedOwnerUserId = asNonNegativeInteger(ownerUserId)
    prompt:SetAttribute("SocialLikePrompt", true)
    prompt:SetAttribute("InfoHomeId", homeInfo.HomeName)
    prompt:SetAttribute("InfoOwnerUserId", resolvedOwnerUserId)
    prompt.ActionText = "点赞"
    prompt.ObjectText = "家园信息"
    prompt.HoldDuration = tonumber(GameConfig.SOCIAL.PromptHoldDuration) or 1
    prompt.Enabled = resolvedOwnerUserId > 0
end

function SocialService:_setHomeInfoEmpty(homeInfo)
    if not homeInfo then
        return
    end

    if homeInfo.PlayerNameLabel then
        homeInfo.PlayerNameLabel.Text = "Empty"
    end
    if homeInfo.PlayerAvatarImage then
        homeInfo.PlayerAvatarImage.Image = ""
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

    if homeInfo.PlayerNameLabel then
        homeInfo.PlayerNameLabel.Text = ownerPlayer.Name
    end
    if homeInfo.PlayerLikeNumLabel then
        homeInfo.PlayerLikeNumLabel.Text = formatLikeText(likesReceived)
    end
    if homeInfo.PlayerAvatarImage then
        homeInfo.PlayerAvatarImage.Image = ""
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
        end)
    end

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
