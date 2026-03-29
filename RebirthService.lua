--[[
脚本名字: RebirthService
脚本文件: RebirthService.lua
脚本类型: ModuleScript
Studio放置路径: ServerScriptService/Services/RebirthService
]]

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
        "[RebirthService] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local GameConfig = requireSharedModule("GameConfig")
local RebirthConfig = requireSharedModule("RebirthConfig")

local RebirthService = {}
RebirthService._playerDataService = nil
RebirthService._currencyService = nil
RebirthService._brainrotService = nil
RebirthService._rebirthStateSyncEvent = nil
RebirthService._requestRebirthStateSyncEvent = nil
RebirthService._requestRebirthEvent = nil
RebirthService._rebirthFeedbackEvent = nil
RebirthService._lastRequestClockByUserId = {}

local function ensureGrowthTable(playerData)
    if type(playerData) ~= "table" then
        return nil
    end

    local growth = playerData.Growth
    if type(growth) ~= "table" then
        growth = {}
        playerData.Growth = growth
    end

    if growth.PowerLevel == nil then
        growth.PowerLevel = 1
    end

    growth.RebirthLevel = math.max(0, math.floor(tonumber(growth.RebirthLevel) or 0))
    return growth
end

local function clampRebirthLevel(level)
    return math.clamp(math.max(0, math.floor(tonumber(level) or 0)), 0, RebirthConfig.MaxLevel)
end

function RebirthService:_getPlayerDataAndGrowth(player)
    if not (self._playerDataService and player) then
        return nil, nil
    end

    local playerData = self._playerDataService:GetPlayerData(player)
    if type(playerData) ~= "table" then
        return nil, nil
    end

    return playerData, ensureGrowthTable(playerData)
end

function RebirthService:GetRebirthLevel(player)
    local _playerData, growth = self:_getPlayerDataAndGrowth(player)
    if not growth then
        return 0
    end

    local rebirthLevel = clampRebirthLevel(growth.RebirthLevel)
    growth.RebirthLevel = rebirthLevel
    return rebirthLevel
end

function RebirthService:GetRebirthBonusRateByLevel(rebirthLevel)
    local entry = RebirthConfig.ByLevel[clampRebirthLevel(rebirthLevel)]
    return entry and math.max(0, tonumber(entry.BonusRate) or 0) or 0
end

function RebirthService:GetRebirthBonusRate(player)
    return self:GetRebirthBonusRateByLevel(self:GetRebirthLevel(player))
end

function RebirthService:_applyPlayerAttributes(player, rebirthLevel)
    if not player then
        return 0
    end

    local normalizedLevel = clampRebirthLevel(rebirthLevel)
    local bonusRate = self:GetRebirthBonusRateByLevel(normalizedLevel)
    player:SetAttribute("RebirthLevel", normalizedLevel)
    player:SetAttribute("RebirthBonusRate", bonusRate)
    return bonusRate
end

function RebirthService:_buildStatePayload(player)
    local rebirthLevel = self:GetRebirthLevel(player)
    local currentEntry = RebirthConfig.ByLevel[rebirthLevel]
    local nextEntry = RebirthConfig.ByLevel[rebirthLevel + 1]
    local displayEntry = nextEntry or currentEntry
    local currentCoins = self._playerDataService and self._playerDataService:GetCoins(player) or 0
    local currentBonusRate = currentEntry and math.max(0, tonumber(currentEntry.BonusRate) or 0) or 0

    return {
        rebirthLevel = rebirthLevel,
        currentBonusRate = currentBonusRate,
        nextRebirthLevel = displayEntry and displayEntry.Level or rebirthLevel,
        nextRequiredCoins = displayEntry and displayEntry.RequiredCoins or 0,
        nextBonusRate = displayEntry and displayEntry.BonusRate or currentBonusRate,
        maxRebirthLevel = RebirthConfig.MaxLevel,
        isMaxLevel = nextEntry == nil,
        currentCoins = math.max(0, math.floor(tonumber(currentCoins) or 0)),
        timestamp = os.clock(),
    }
end
function RebirthService:PushRebirthState(player)
    if not (player and self._rebirthStateSyncEvent) then
        return
    end

    self._rebirthStateSyncEvent:FireClient(player, self:_buildStatePayload(player))
end

function RebirthService:_pushFeedback(player, status, message)
    if not (player and self._rebirthFeedbackEvent) then
        return
    end

    self._rebirthFeedbackEvent:FireClient(player, {
        status = tostring(status or "Unknown"),
        message = tostring(message or ""),
        timestamp = os.clock(),
    })
end

function RebirthService:_canSendRequest(player)
    if not player then
        return false
    end

    local debounceSeconds = math.max(0.05, tonumber((GameConfig.REBIRTH or {}).RequestDebounceSeconds) or 0.35)
    local userId = player.UserId
    local nowClock = os.clock()
    local lastClock = tonumber(self._lastRequestClockByUserId[userId]) or 0
    if nowClock - lastClock < debounceSeconds then
        return false
    end

    self._lastRequestClockByUserId[userId] = nowClock
    return true
end

function RebirthService:_handleRequestRebirth(player)
    if not (player and self:_canSendRequest(player)) then
        return
    end

    local playerData, growth = self:_getPlayerDataAndGrowth(player)
    if not (playerData and growth) then
        return
    end

    local currentLevel = clampRebirthLevel(growth.RebirthLevel)
    growth.RebirthLevel = currentLevel

    local nextEntry = RebirthConfig.ByLevel[currentLevel + 1]
    if not nextEntry then
        self:PushRebirthState(player)
        self:_pushFeedback(player, "AlreadyMax", "")
        return
    end

    local currentCoins = self._playerDataService and self._playerDataService:GetCoins(player) or 0
    local requiredCoins = math.max(0, math.floor(tonumber(nextEntry.RequiredCoins) or 0))
    if currentCoins < requiredCoins then
        self:PushRebirthState(player)
        self:_pushFeedback(player, "RequirementNotMet", "")
        return
    end

    growth.RebirthLevel = clampRebirthLevel(nextEntry.Level)
    self:_applyPlayerAttributes(player, growth.RebirthLevel)

    if self._currencyService then
        self._currencyService:SetCoins(player, 0, "RebirthReset")
    end

    if self._brainrotService then
        self._brainrotService:ResetProductionForRebirth(player)
    end

    local didSave = not self._playerDataService or self._playerDataService:SavePlayerData(player)
    self:PushRebirthState(player)
    if not didSave then
        self:_pushFeedback(player, "SaveFailed", "")
        return
    end

    self:_pushFeedback(player, "Success", tostring((GameConfig.REBIRTH or {}).SuccessTipText or "Rebirth successful!"))
end
function RebirthService:Init(dependencies)
    self._playerDataService = dependencies.PlayerDataService
    self._currencyService = dependencies.CurrencyService
    self._brainrotService = dependencies.BrainrotService

    local remoteEventService = dependencies.RemoteEventService
    self._rebirthStateSyncEvent = remoteEventService:GetEvent("RebirthStateSync")
    self._requestRebirthStateSyncEvent = remoteEventService:GetEvent("RequestRebirthStateSync")
    self._requestRebirthEvent = remoteEventService:GetEvent("RequestRebirth")
    self._rebirthFeedbackEvent = remoteEventService:GetEvent("RebirthFeedback")

    if self._requestRebirthStateSyncEvent then
        self._requestRebirthStateSyncEvent.OnServerEvent:Connect(function(player)
            self:PushRebirthState(player)
        end)
    end

    if self._requestRebirthEvent then
        self._requestRebirthEvent.OnServerEvent:Connect(function(player)
            self:_handleRequestRebirth(player)
        end)
    end
end

function RebirthService:OnPlayerReady(player)
    local _playerData, growth = self:_getPlayerDataAndGrowth(player)
    if not growth then
        return
    end

    growth.RebirthLevel = clampRebirthLevel(growth.RebirthLevel)
    self:_applyPlayerAttributes(player, growth.RebirthLevel)
    self:PushRebirthState(player)
end

function RebirthService:OnPlayerRemoving(player)
    if not player then
        return
    end

    self._lastRequestClockByUserId[player.UserId] = nil
    player:SetAttribute("RebirthLevel", nil)
    player:SetAttribute("RebirthBonusRate", nil)
end

return RebirthService
