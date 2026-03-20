--[[
脚本名字: FriendBonusService
脚本文件: FriendBonusService.lua
脚本类型: ModuleScript
Studio放置路径: ServerScriptService/Services/FriendBonusService
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
        "[FriendBonusService] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local GameConfig = requireSharedModule("GameConfig")

local FriendBonusService = {}
FriendBonusService._remoteEventService = nil
FriendBonusService._friendBonusSyncEvent = nil
FriendBonusService._requestFriendBonusSyncEvent = nil
FriendBonusService._stateByUserId = {}
FriendBonusService._friendshipCache = {}

local function makePairKey(userIdA, userIdB)
    local a = math.floor(tonumber(userIdA) or 0)
    local b = math.floor(tonumber(userIdB) or 0)
    if a <= b then
        return string.format("%d:%d", a, b)
    end
    return string.format("%d:%d", b, a)
end

local function resolveBonusPercent(friendCount)
    local perFriend = math.max(0, math.floor(tonumber(GameConfig.FRIEND_BONUS.PercentPerFriend) or 10))
    local maxFriendCount = math.max(0, math.floor(tonumber(GameConfig.FRIEND_BONUS.MaxFriendCount) or 4))
    local clampedCount = math.max(0, math.min(maxFriendCount, math.floor(tonumber(friendCount) or 0)))
    return clampedCount * perFriend, clampedCount
end

function FriendBonusService:_pushBonusState(player, friendCount, bonusPercent)
    if not self._friendBonusSyncEvent then
        return
    end

    self._friendBonusSyncEvent:FireClient(player, {
        friendCount = math.max(0, math.floor(tonumber(friendCount) or 0)),
        bonusPercent = math.max(0, math.floor(tonumber(bonusPercent) or 0)),
        timestamp = os.clock(),
    })
end

function FriendBonusService:_arePlayersFriends(playerA, playerB)
    if not playerA or not playerB or playerA == playerB then
        return false
    end

    local pairKey = makePairKey(playerA.UserId, playerB.UserId)
    local cached = self._friendshipCache[pairKey]
    if type(cached) == "boolean" then
        return cached
    end

    local success, result = pcall(function()
        return playerA:IsFriendsWith(playerB.UserId)
    end)
    local areFriends = success and result == true
    if not success then
        warn(string.format(
            "[FriendBonusService] IsFriendsWith 失败: %s(%d) -> %s(%d)",
            tostring(playerA.Name),
            tonumber(playerA.UserId) or 0,
            tostring(playerB.Name),
            tonumber(playerB.UserId) or 0
        ))
        return false
    end

    self._friendshipCache[pairKey] = areFriends
    return areFriends
end

function FriendBonusService:_computeOnlineFriendCount(player, onlinePlayers, excludedUserId)
    local count = 0
    for _, otherPlayer in ipairs(onlinePlayers) do
        if otherPlayer ~= player and otherPlayer.UserId ~= excludedUserId then
            if self:_arePlayersFriends(player, otherPlayer) then
                count += 1
            end
        end
    end
    return count
end

function FriendBonusService:_setPlayerState(player, friendCount, forcePush)
    if not player then
        return
    end

    local bonusPercent, clampedCount = resolveBonusPercent(friendCount)
    local userId = player.UserId
    local previous = self._stateByUserId[userId]
    local previousPercent = previous and previous.BonusPercent or nil
    local previousCount = previous and previous.FriendCount or nil

    self._stateByUserId[userId] = {
        BonusPercent = bonusPercent,
        FriendCount = clampedCount,
    }

    local changed = previousPercent ~= bonusPercent or previousCount ~= clampedCount
    if changed or forcePush then
        self:_pushBonusState(player, clampedCount, bonusPercent)
    end
end

function FriendBonusService:RefreshAllPlayersBonus(excludedUserId, forcePush)
    local onlinePlayers = Players:GetPlayers()
    local onlineByUserId = {}

    for _, player in ipairs(onlinePlayers) do
        onlineByUserId[player.UserId] = true
    end

    for _, player in ipairs(onlinePlayers) do
        if player.UserId ~= excludedUserId then
            local friendCount = self:_computeOnlineFriendCount(player, onlinePlayers, excludedUserId)
            self:_setPlayerState(player, friendCount, forcePush == true)
        end
    end

    for userId in pairs(self._stateByUserId) do
        if userId == excludedUserId or not onlineByUserId[userId] then
            self._stateByUserId[userId] = nil
        end
    end
end

function FriendBonusService:PushBonusState(player)
    if not player then
        return
    end

    local state = self._stateByUserId[player.UserId]
    if state then
        self:_pushBonusState(player, state.FriendCount, state.BonusPercent)
        return
    end

    self:_pushBonusState(player, 0, 0)
end

function FriendBonusService:GetBonusPercent(player)
    if not player then
        return 0
    end

    local state = self._stateByUserId[player.UserId]
    if not state then
        return 0
    end

    return math.max(0, math.floor(tonumber(state.BonusPercent) or 0))
end

function FriendBonusService:OnPlayerReady(_player)
    self:RefreshAllPlayersBonus(nil, false)
end

function FriendBonusService:OnPlayerRemoving(player)
    if not player then
        return
    end

    local userId = player.UserId
    self._stateByUserId[userId] = nil

    for pairKey in pairs(self._friendshipCache) do
        local leftIdText, rightIdText = string.match(pairKey, "^(%-?%d+):(%-?%d+)$")
        local leftId = tonumber(leftIdText)
        local rightId = tonumber(rightIdText)
        if leftId == userId or rightId == userId then
            self._friendshipCache[pairKey] = nil
        end
    end

    self:RefreshAllPlayersBonus(userId, false)
end

function FriendBonusService:Init(dependencies)
    self._remoteEventService = dependencies.RemoteEventService
    self._friendBonusSyncEvent = self._remoteEventService:GetEvent("FriendBonusSync")
    self._requestFriendBonusSyncEvent = self._remoteEventService:GetEvent("RequestFriendBonusSync")

    if self._requestFriendBonusSyncEvent then
        self._requestFriendBonusSyncEvent.OnServerEvent:Connect(function(player)
            self:PushBonusState(player)
        end)
    end
end

return FriendBonusService
