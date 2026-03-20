--[[
脚本名字: CurrencyService
脚本文件: CurrencyService.lua
脚本类型: ModuleScript
本地路径: D:/RobloxGame/BrainrotsTemplate/CurrencyService.lua
Studio放置路径: ServerScriptService/Services/CurrencyService
]]

local CurrencyService = {}
CurrencyService._playerDataService = nil
CurrencyService._coinChangedEvent = nil
CurrencyService._requestCoinSyncEvent = nil

local COMPACT_NUMBER_UNITS = {
    { Value = 1e30, Suffix = "No" },
    { Value = 1e27, Suffix = "Oc" },
    { Value = 1e24, Suffix = "Sp" },
    { Value = 1e21, Suffix = "Sx" },
    { Value = 1e18, Suffix = "Qi" },
    { Value = 1e15, Suffix = "Qa" },
    { Value = 1e12, Suffix = "T" },
    { Value = 1e9, Suffix = "B" },
    { Value = 1e6, Suffix = "M" },
    { Value = 1e3, Suffix = "K" },
}

local function trimTrailingZeros(numberText)
    local trimmed = string.gsub(numberText, "(%..-)0+$", "%1")
    trimmed = string.gsub(trimmed, "%.$", "")
    return trimmed
end

local function formatCompactNumber(value)
    local numericValue = math.max(0, tonumber(value) or 0)
    if numericValue < 1000 then
        return tostring(math.floor(numericValue))
    end

    for _, unit in ipairs(COMPACT_NUMBER_UNITS) do
        if numericValue >= unit.Value then
            local scaled = numericValue / unit.Value
            local decimals = 2
            if scaled >= 100 then
                decimals = 0
            elseif scaled >= 10 then
                decimals = 1
            end

            local formatString = string.format("%%.%df", decimals)
            local numberText = trimTrailingZeros(string.format(formatString, scaled))
            return numberText .. unit.Suffix
        end
    end

    return tostring(math.floor(numericValue))
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
        player:SetAttribute("CashRaw", math.max(0, math.floor(safeCoins)))
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


