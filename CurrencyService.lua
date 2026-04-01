--[[
脚本名字: CurrencyService
脚本文件: CurrencyService.lua
脚本类型: ModuleScript
Studio放置路径: ServerScriptService/Services/CurrencyService
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
        "[CurrencyService] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local FormatUtil = requireSharedModule("FormatUtil")

local CurrencyService = {}
CurrencyService._playerDataService = nil
CurrencyService._coinChangedEvent = nil
CurrencyService._requestCoinSyncEvent = nil

local function formatCompactNumber(value)
    return FormatUtil.FormatCompactNumberCeil(value)
end

function CurrencyService:_ensureLeaderstats(player)
    if not player then
        return nil, nil
    end

    local leaderstats = player:FindFirstChild("leaderstats")
    if leaderstats and not leaderstats:IsA("Folder") then
        leaderstats:Destroy()
        leaderstats = nil
    end

    if not leaderstats then
        leaderstats = Instance.new("Folder")
        leaderstats.Name = "leaderstats"
        leaderstats.Parent = player
    end

    local cashValue = leaderstats:FindFirstChild("Cash")
    if cashValue and not cashValue:IsA("StringValue") then
        cashValue:Destroy()
        cashValue = nil
    end

    if not cashValue then
        cashValue = Instance.new("StringValue")
        cashValue.Name = "Cash"
        cashValue.Value = "0"
        cashValue.Parent = leaderstats
    end

    local legacyRankValue = leaderstats:FindFirstChild("Rank")
    if legacyRankValue then
        legacyRankValue:Destroy()
    end

    return leaderstats, cashValue
end

function CurrencyService:_updateCashStat(player, totalCoins)
    local _leaderstats, cashValue = self:_ensureLeaderstats(player)
    local safeCoins = math.max(0, tonumber(totalCoins) or 0)
    if cashValue then
        cashValue.Value = formatCompactNumber(safeCoins)
    end

    if player then
        player:SetAttribute("CashRaw", safeCoins)
    end
end

function CurrencyService:Init(dependencies)
    self._playerDataService = dependencies.PlayerDataService

    local remoteEventService = dependencies.RemoteEventService
    self._coinChangedEvent = remoteEventService:GetEvent("CoinChanged")
    self._requestCoinSyncEvent = remoteEventService:GetEvent("RequestCoinSync")

    if self._requestCoinSyncEvent then
        self._requestCoinSyncEvent.OnServerEvent:Connect(function(player)
            self:PushCoinState(player, 0, "ClientSync")
        end)
    end
end

function CurrencyService:PushCoinState(player, delta, reason)
    local totalCoins = self._playerDataService:GetCoins(player)

    self:_updateCashStat(player, totalCoins)

    if self._coinChangedEvent then
        self._coinChangedEvent:FireClient(player, {
            total = totalCoins,
            delta = tonumber(delta) or 0,
            reason = tostring(reason or "Unknown"),
            timestamp = os.clock(),
        })
    end
end

function CurrencyService:OnPlayerReady(player)
    self:_ensureLeaderstats(player)
    self:PushCoinState(player, 0, "InitialSync")
end

function CurrencyService:OnPlayerRemoving(player)
    if player then
        player:SetAttribute("CashRaw", nil)
    end
end

function CurrencyService:AddCoins(player, amount, reason)
    local numericAmount = tonumber(amount) or 0
    if math.abs(numericAmount) < 0.0001 then
        return false, self._playerDataService:GetCoins(player)
    end

    local previous, nextValue = self._playerDataService:ChangeCoins(player, numericAmount)
    if previous == nil then
        return false, 0
    end

    local delta = nextValue - previous
    if math.abs(delta) >= 0.0001 then
        self:PushCoinState(player, delta, reason or "AddCoins")
    end

    return true, nextValue
end

function CurrencyService:SetCoins(player, amount, reason)
    local previous, nextValue = self._playerDataService:SetCoins(player, amount)
    if previous == nil then
        return false, 0
    end

    local delta = nextValue - previous
    self:PushCoinState(player, delta, reason or "SetCoins")
    return true, nextValue
end

return CurrencyService


