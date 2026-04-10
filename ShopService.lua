--[[
Script: ShopService
Type: ModuleScript
Studio path: ServerScriptService/Services/ShopService
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local VIP_ICON_MARKER_ATTRIBUTE = "ShopVipIcon"

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
        "[ShopService] Missing shared module %s",
        moduleName
    ))
end

local GameConfig = requireSharedModule("GameConfig")

local ShopService = {}
ShopService._playerDataService = nil
ShopService._remoteEventService = nil
ShopService._currencyService = nil
ShopService._brainrotService = nil
ShopService._luckyBlockService = nil
ShopService._requestShopStateSyncEvent = nil
ShopService._lastRequestClockByUserId = {}
ShopService._lastOwnershipCheckClockByUserId = {}
ShopService._characterConnectionsByUserId = {}
ShopService._serverLuckyExpiresAt = 0
ShopService._serverLuckyPurchaseSerial = 0

local function getShopConfig()
    return GameConfig.SHOP or {}
end

local function getRequestDebounceSeconds()
    return math.max(0.05, tonumber(getShopConfig().RequestDebounceSeconds) or 0.2)
end

local function getOwnershipRefreshCooldownSeconds()
    return math.max(0.1, tonumber(getShopConfig().OwnershipRefreshCooldownSeconds) or 0.75)
end

local function getServerLuckyProductId()
    return math.max(0, math.floor(tonumber(getShopConfig().ServerLuckyProductId) or 0))
end

local function getServerLuckyDurationSeconds()
    return math.max(1, math.floor(tonumber(getShopConfig().ServerLuckyDurationSeconds) or 300))
end

local function getServerLuckyExpireAtAttributeName()
    return tostring(getShopConfig().ServerLuckyExpireAtAttributeName or "ServerLuckyExpireAt")
end

local function getServerLuckyLastBuyerNameAttributeName()
    return tostring(getShopConfig().ServerLuckyLastBuyerNameAttributeName or "ServerLuckyLastBuyerName")
end

local function getServerLuckyPurchaseSerialAttributeName()
    return tostring(getShopConfig().ServerLuckyPurchaseSerialAttributeName or "ServerLuckyPurchaseSerial")
end

local function getNormalizedLuckyBlockOfferByProductId(productId)
    local normalizedProductId = math.max(0, math.floor(tonumber(productId) or 0))
    if normalizedProductId <= 0 then
        return nil
    end

    local rawOffers = getShopConfig().LuckyBlockBundleOffers
    if type(rawOffers) ~= "table" then
        return nil
    end

    for offerKey, rawOffer in pairs(rawOffers) do
        if type(rawOffer) == "table" then
            local candidateProductId = math.max(0, math.floor(tonumber(rawOffer.ProductId) or 0))
            if candidateProductId == normalizedProductId then
                return {
                    OfferKey = tostring(rawOffer.ButtonName or offerKey or ""),
                    ProductId = candidateProductId,
                    BlockId = math.max(0, math.floor(tonumber(rawOffer.BlockId) or 0)),
                    Quantity = math.max(0, math.floor(tonumber(rawOffer.Quantity) or 0)),
                }
            end
        end
    end

    return nil
end

local function getVipGamePassId()
    return math.max(0, math.floor(tonumber(getShopConfig().VipGamePassId) or 0))
end

local function getVipOwnedAttributeName()
    return tostring(getShopConfig().VipOwnedAttributeName or "VipOwned")
end

local function getVipProductionBonusAttributeName()
    return tostring(getShopConfig().VipProductionBonusAttributeName or "VipProductionBonusRate")
end

local function getVipProductionBonusRate()
    return math.max(0, tonumber(getShopConfig().VipProductionBonusRate) or 1)
end

local function getVipIconTemplateName()
    return tostring(getShopConfig().VipIconTemplateName or "VipIcon")
end

local function getVipIconInstanceName()
    return tostring(getShopConfig().VipIconInstanceName or getVipIconTemplateName())
end

local function getVipIconStudsOffsetWorldSpace()
    local configuredOffset = getShopConfig().VipIconStudsOffsetWorldSpace
    if typeof(configuredOffset) == "Vector3" then
        return configuredOffset
    end

    return Vector3.new(0, 3.25, 0)
end

local function normalizeProcessedPurchaseIds(sourceValue)
    local processedPurchaseIds = {}
    if type(sourceValue) ~= "table" then
        return processedPurchaseIds
    end

    for key, value in pairs(sourceValue) do
        local purchaseId = tostring(key or "")
        if purchaseId ~= "" then
            processedPurchaseIds[purchaseId] = math.max(0, math.floor(tonumber(value) or os.time()))
        end
    end

    return processedPurchaseIds
end

local function getServerTimeNow()
    local ok, serverTimeNow = pcall(function()
        return Workspace:GetServerTimeNow()
    end)
    if ok then
        return math.max(0, tonumber(serverTimeNow) or 0)
    end

    return math.max(0, tonumber(os.time()) or 0)
end

local function ensureShopState(playerData)
    if type(playerData) ~= "table" then
        return nil
    end

    local shopState = playerData.ShopState
    if type(shopState) ~= "table" then
        shopState = {}
        playerData.ShopState = shopState
    end

    shopState.VipOwned = shopState.VipOwned == true
    shopState.ProcessedCashPurchaseIds = normalizeProcessedPurchaseIds(shopState.ProcessedCashPurchaseIds)
    shopState.ProcessedServerLuckyPurchaseIds = normalizeProcessedPurchaseIds(shopState.ProcessedServerLuckyPurchaseIds)
    shopState.ProcessedLuckyBlockPurchaseIds = normalizeProcessedPurchaseIds(shopState.ProcessedLuckyBlockPurchaseIds)
    return shopState
end

local function getNormalizedCashOfferByProductId(productId)
    local normalizedProductId = math.max(0, math.floor(tonumber(productId) or 0))
    if normalizedProductId <= 0 then
        return nil
    end

    local cashOffers = getShopConfig().CashOffers
    if type(cashOffers) ~= "table" then
        return nil
    end

    for offerKey, rawOffer in pairs(cashOffers) do
        if type(rawOffer) == "table" then
            local candidateProductId = math.max(0, math.floor(tonumber(rawOffer.ProductId) or 0))
            if candidateProductId == normalizedProductId then
                return {
                    OfferKey = tostring(rawOffer.NodeName or offerKey or ""),
                    ProductId = candidateProductId,
                    CoinAmount = math.max(0, tonumber(rawOffer.CoinAmount) or 0),
                }
            end
        end
    end

    return nil
end

function ShopService:_syncServerLuckyAttributes(lastBuyerName)
    local expireAtAttributeName = getServerLuckyExpireAtAttributeName()
    local lastBuyerAttributeName = getServerLuckyLastBuyerNameAttributeName()
    local purchaseSerialAttributeName = getServerLuckyPurchaseSerialAttributeName()
    local normalizedExpireAt = math.max(0, tonumber(self._serverLuckyExpiresAt) or 0)
    local normalizedPurchaseSerial = math.max(0, math.floor(tonumber(self._serverLuckyPurchaseSerial) or 0))

    ReplicatedStorage:SetAttribute(expireAtAttributeName, normalizedExpireAt)
    if type(lastBuyerName) == "string" then
        ReplicatedStorage:SetAttribute(lastBuyerAttributeName, lastBuyerName)
    elseif ReplicatedStorage:GetAttribute(lastBuyerAttributeName) == nil then
        ReplicatedStorage:SetAttribute(lastBuyerAttributeName, "")
    end
    ReplicatedStorage:SetAttribute(purchaseSerialAttributeName, normalizedPurchaseSerial)
end

function ShopService:GetServerLuckyExpireAt()
    return math.max(0, tonumber(self._serverLuckyExpiresAt) or 0)
end

function ShopService:GetServerLuckyRemainingSeconds()
    return math.max(0, self:GetServerLuckyExpireAt() - getServerTimeNow())
end

function ShopService:IsServerLuckyActive()
    return self:GetServerLuckyRemainingSeconds() > 0
end

function ShopService:_grantServerLuckyDuration(player)
    local now = getServerTimeNow()
    local nextExpireAt = math.max(now, self:GetServerLuckyExpireAt()) + getServerLuckyDurationSeconds()
    self._serverLuckyExpiresAt = nextExpireAt
    self._serverLuckyPurchaseSerial = math.max(0, math.floor(tonumber(self._serverLuckyPurchaseSerial) or 0)) + 1
    self:_syncServerLuckyAttributes(player and player.Name or "")
end

function ShopService:_savePlayerDataAsync(player)
    if not (self._playerDataService and player) then
        return
    end

    task.spawn(function()
        self._playerDataService:SavePlayerData(player)
    end)
end

function ShopService:_getPlayerDataAndState(player)
    if not (self._playerDataService and player) then
        return nil, nil
    end

    local playerData = self._playerDataService:GetPlayerData(player)
    if type(playerData) ~= "table" then
        return nil, nil
    end

    return playerData, ensureShopState(playerData)
end

function ShopService:_canProcessRequest(player)
    if not player then
        return false
    end

    local nowClock = os.clock()
    local lastClock = tonumber(self._lastRequestClockByUserId[player.UserId]) or 0
    if nowClock - lastClock < getRequestDebounceSeconds() then
        return false
    end

    self._lastRequestClockByUserId[player.UserId] = nowClock
    return true
end

function ShopService:_clearVipIcon(character)
    if not character then
        return
    end

    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("BillboardGui")
            and (
                descendant:GetAttribute(VIP_ICON_MARKER_ATTRIBUTE) == true
                or descendant.Name == getVipIconInstanceName()
            )
        then
            descendant:Destroy()
        end
    end
end

function ShopService:_getVipIconTemplate()
    local templateName = getVipIconTemplateName()
    if templateName == "" then
        return nil
    end

    local template = ReplicatedStorage:FindFirstChild(templateName)
        or ReplicatedStorage:FindFirstChild(templateName, true)
    if template and template:IsA("BillboardGui") then
        return template
    end

    return nil
end

function ShopService:_applyVipIcon(player, character)
    if not (player and character) then
        return
    end

    self:_clearVipIcon(character)
    if player:GetAttribute(getVipOwnedAttributeName()) ~= true then
        return
    end

    local template = self:_getVipIconTemplate()
    if not template then
        return
    end

    local head = character:FindFirstChild("Head") or character:WaitForChild("Head", 5)
    if not (head and head:IsA("BasePart")) then
        return
    end

    local clone = template:Clone()
    clone.Name = getVipIconInstanceName()
    clone:SetAttribute(VIP_ICON_MARKER_ATTRIBUTE, true)
    clone.Adornee = head
    clone.Enabled = true
    clone.AlwaysOnTop = true
    clone.StudsOffsetWorldSpace = getVipIconStudsOffsetWorldSpace()
    clone.Parent = head
end

function ShopService:_setVipAttributes(player, isVipOwned)
    if not player then
        return
    end

    player:SetAttribute(getVipOwnedAttributeName(), isVipOwned == true)
    if isVipOwned == true then
        player:SetAttribute(getVipProductionBonusAttributeName(), getVipProductionBonusRate())
    else
        player:SetAttribute(getVipProductionBonusAttributeName(), nil)
    end
end

function ShopService:_refreshBrainrotProduction(player)
    if self._brainrotService and type(self._brainrotService.PushBrainrotState) == "function" then
        self._brainrotService:PushBrainrotState(player)
    end
end

function ShopService:_applyVipState(player, isVipOwned, options)
    if not player then
        return
    end

    local previousOwned = player:GetAttribute(getVipOwnedAttributeName()) == true
    self:_setVipAttributes(player, isVipOwned)

    if player.Character then
        self:_applyVipIcon(player, player.Character)
    end

    if previousOwned ~= (isVipOwned == true)
        and not (type(options) == "table" and options.SkipProductionRefresh == true)
    then
        self:_refreshBrainrotProduction(player)
    end
end

function ShopService:_refreshVipOwnership(player, shopState, forceRefresh)
    if not (player and shopState) then
        return false
    end

    local gamePassId = getVipGamePassId()
    if gamePassId <= 0 then
        return false
    end

    local nowClock = os.clock()
    local lastCheckClock = tonumber(self._lastOwnershipCheckClockByUserId[player.UserId]) or 0
    if nowClock - lastCheckClock < getOwnershipRefreshCooldownSeconds() then
        return false
    end

    if forceRefresh ~= true and shopState.VipOwned == true then
        return false
    end

    self._lastOwnershipCheckClockByUserId[player.UserId] = nowClock
    local success, ownsGamePass = pcall(function()
        return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamePassId)
    end)

    if not success then
        warn(string.format(
            "[ShopService] Failed to refresh VIP game pass ownership userId=%d gamePassId=%d err=%s",
            player.UserId,
            gamePassId,
            tostring(ownsGamePass)
        ))
        return false
    end

    local normalizedOwned = ownsGamePass == true
    if shopState.VipOwned ~= normalizedOwned then
        shopState.VipOwned = normalizedOwned
        return true
    end

    return false
end

function ShopService:_refreshPlayerState(player, options)
    local _playerData, shopState = self:_getPlayerDataAndState(player)
    if not shopState then
        return false
    end

    local didChange = self:_refreshVipOwnership(
        player,
        shopState,
        type(options) == "table" and options.ForceOwnershipRefresh == true
    )

    self:_applyVipState(player, shopState.VipOwned, options)

    if didChange and not (type(options) == "table" and options.SkipSave == true) then
        self:_savePlayerDataAsync(player)
    end

    return didChange
end

function ShopService:_bindCharacter(player)
    if not player then
        return
    end

    local userId = player.UserId
    local existingConnection = self._characterConnectionsByUserId[userId]
    if existingConnection then
        existingConnection:Disconnect()
        self._characterConnectionsByUserId[userId] = nil
    end

    self._characterConnectionsByUserId[userId] = player.CharacterAdded:Connect(function(character)
        task.defer(function()
            self:_applyVipState(player, player:GetAttribute(getVipOwnedAttributeName()) == true, {
                SkipProductionRefresh = true,
            })
            self:_applyVipIcon(player, character)
        end)
    end)
end

function ShopService:SetBrainrotService(brainrotService)
    self._brainrotService = brainrotService
end

function ShopService:SetLuckyBlockService(luckyBlockService)
    self._luckyBlockService = luckyBlockService
end

function ShopService:IsVipOwned(player)
    if not player then
        return false
    end

    local _playerData, shopState = self:_getPlayerDataAndState(player)
    if shopState then
        return shopState.VipOwned == true
    end

    return player:GetAttribute(getVipOwnedAttributeName()) == true
end

function ShopService:Init(dependencies)
    self._playerDataService = dependencies.PlayerDataService
    self._remoteEventService = dependencies.RemoteEventService
    self._currencyService = dependencies.CurrencyService
    self._luckyBlockService = dependencies.LuckyBlockService
    self._lastRequestClockByUserId = {}
    self._lastOwnershipCheckClockByUserId = {}
    self._characterConnectionsByUserId = {}
    self._serverLuckyExpiresAt = 0
    self._serverLuckyPurchaseSerial = 0
    self:_syncServerLuckyAttributes("")
    self._requestShopStateSyncEvent = self._remoteEventService:GetEvent("RequestShopStateSync")

    if self._requestShopStateSyncEvent then
        self._requestShopStateSyncEvent.OnServerEvent:Connect(function(player, payload)
            local forceOwnershipRefresh = type(payload) == "table" and payload.forceOwnershipRefresh == true
            if self:_canProcessRequest(player) then
                self:_refreshPlayerState(player, {
                    ForceOwnershipRefresh = forceOwnershipRefresh,
                })
                return
            end

            self:_applyVipState(player, self:IsVipOwned(player), {
                SkipProductionRefresh = true,
            })
        end)
    end
end

function ShopService:OnPlayerReady(player)
    self:_bindCharacter(player)
    self:_refreshPlayerState(player, {
        ForceOwnershipRefresh = true,
    })
end

function ShopService:OnPlayerRemoving(player)
    if not player then
        return
    end

    local userId = player.UserId
    local characterConnection = self._characterConnectionsByUserId[userId]
    if characterConnection then
        characterConnection:Disconnect()
        self._characterConnectionsByUserId[userId] = nil
    end

    if player.Character then
        self:_clearVipIcon(player.Character)
    end

    player:SetAttribute(getVipOwnedAttributeName(), nil)
    player:SetAttribute(getVipProductionBonusAttributeName(), nil)
    self._lastRequestClockByUserId[userId] = nil
    self._lastOwnershipCheckClockByUserId[userId] = nil
end

function ShopService:_savePlayerDataSync(player)
    if not (self._playerDataService and player) then
        return false
    end

    return self._playerDataService:SavePlayerData(player)
end

function ShopService:_createServerLuckySnapshot()
    return {
        ExpiresAt = math.max(0, tonumber(self._serverLuckyExpiresAt) or 0),
        PurchaseSerial = math.max(0, math.floor(tonumber(self._serverLuckyPurchaseSerial) or 0)),
        ReplicatedExpireAt = ReplicatedStorage:GetAttribute(getServerLuckyExpireAtAttributeName()),
        ReplicatedLastBuyerName = ReplicatedStorage:GetAttribute(getServerLuckyLastBuyerNameAttributeName()),
        ReplicatedPurchaseSerial = ReplicatedStorage:GetAttribute(getServerLuckyPurchaseSerialAttributeName()),
    }
end

function ShopService:_restoreServerLuckySnapshot(snapshot)
    if type(snapshot) ~= "table" then
        return
    end

    self._serverLuckyExpiresAt = math.max(0, tonumber(snapshot.ExpiresAt) or 0)
    self._serverLuckyPurchaseSerial = math.max(0, math.floor(tonumber(snapshot.PurchaseSerial) or 0))
    ReplicatedStorage:SetAttribute(getServerLuckyExpireAtAttributeName(), snapshot.ReplicatedExpireAt)
    ReplicatedStorage:SetAttribute(getServerLuckyLastBuyerNameAttributeName(), snapshot.ReplicatedLastBuyerName)
    ReplicatedStorage:SetAttribute(getServerLuckyPurchaseSerialAttributeName(), snapshot.ReplicatedPurchaseSerial)
end

function ShopService:ProcessReceipt(receiptInfo)
    local serverLuckyProductId = getServerLuckyProductId()
    local productId = math.max(0, math.floor(tonumber(receiptInfo and receiptInfo.ProductId) or 0))
    local cashOffer = getNormalizedCashOfferByProductId(receiptInfo and receiptInfo.ProductId)
    local luckyBlockOffer = getNormalizedLuckyBlockOfferByProductId(receiptInfo and receiptInfo.ProductId)
    if not cashOffer and not luckyBlockOffer and productId ~= serverLuckyProductId then
        return false, nil
    end

    local player = Players:GetPlayerByUserId(math.max(0, math.floor(tonumber(receiptInfo and receiptInfo.PlayerId) or 0)))
    if not player then
        return true, Enum.ProductPurchaseDecision.NotProcessedYet
    end

    local _playerData, shopState = self:_getPlayerDataAndState(player)
    if not shopState then
        return true, Enum.ProductPurchaseDecision.NotProcessedYet
    end

    local purchaseId = tostring(receiptInfo and receiptInfo.PurchaseId or "")
    local processedPurchaseIds = nil
    if cashOffer then
        processedPurchaseIds = shopState.ProcessedCashPurchaseIds or {}
    elseif luckyBlockOffer then
        processedPurchaseIds = shopState.ProcessedLuckyBlockPurchaseIds or {}
    else
        processedPurchaseIds = shopState.ProcessedServerLuckyPurchaseIds or {}
    end

    if purchaseId ~= "" and processedPurchaseIds[purchaseId] then
        return true, Enum.ProductPurchaseDecision.PurchaseGranted
    end

    local previousProcessedAt = purchaseId ~= "" and processedPurchaseIds[purchaseId] or nil
    local previousCoins = 0
    local luckyBlockSnapshot = nil
    local serverLuckySnapshot = nil
    if cashOffer then
        previousCoins = self._playerDataService and self._playerDataService:GetCoins(player) or 0
    elseif luckyBlockOffer then
        if not (self._luckyBlockService and self._luckyBlockService.GrantBlock) then
            return true, Enum.ProductPurchaseDecision.NotProcessedYet
        end
        if not (self._luckyBlockService.CreatePlayerStateSnapshot and self._luckyBlockService.RestorePlayerStateSnapshot) then
            return true, Enum.ProductPurchaseDecision.NotProcessedYet
        end
        luckyBlockSnapshot = self._luckyBlockService:CreatePlayerStateSnapshot(player)
        if type(luckyBlockSnapshot) ~= "table" then
            return true, Enum.ProductPurchaseDecision.NotProcessedYet
        end
    else
        serverLuckySnapshot = self:_createServerLuckySnapshot()
    end

    if cashOffer then
        if not self._currencyService then
            return true, Enum.ProductPurchaseDecision.NotProcessedYet
        end

        local didGrantCoins = select(1, self._currencyService:AddCoins(player, cashOffer.CoinAmount, "ShopCashPurchase"))
        if didGrantCoins ~= true then
            return true, Enum.ProductPurchaseDecision.NotProcessedYet
        end
    elseif luckyBlockOffer then
        if not self._luckyBlockService then
            return true, Enum.ProductPurchaseDecision.NotProcessedYet
        end

        local didGrantBlock = select(
            1,
            self._luckyBlockService:GrantBlock(
                player,
                luckyBlockOffer.BlockId,
                luckyBlockOffer.Quantity,
                "ShopLuckyBlockBundle",
                {
                    SkipSave = true,
                }
            )
        )
        if didGrantBlock ~= true then
            return true, Enum.ProductPurchaseDecision.NotProcessedYet
        end
    else
        self:_grantServerLuckyDuration(player)
    end

    if purchaseId ~= "" then
        processedPurchaseIds[purchaseId] = os.time()
    end

    if cashOffer then
        shopState.ProcessedCashPurchaseIds = processedPurchaseIds
    elseif luckyBlockOffer then
        shopState.ProcessedLuckyBlockPurchaseIds = processedPurchaseIds
    else
        shopState.ProcessedServerLuckyPurchaseIds = processedPurchaseIds
    end

    local didSave = self:_savePlayerDataSync(player)
    if not didSave then
        if purchaseId ~= "" then
            if previousProcessedAt ~= nil then
                processedPurchaseIds[purchaseId] = previousProcessedAt
            else
                processedPurchaseIds[purchaseId] = nil
            end
        end

        if cashOffer then
            local currentCoins = self._playerDataService and self._playerDataService:GetCoins(player) or previousCoins
            local rollbackCoins = math.max(0, currentCoins - previousCoins)
            if rollbackCoins > 0 and self._currencyService then
                self._currencyService:AddCoins(player, -rollbackCoins, "ShopCashPurchaseRollback")
            end
        elseif luckyBlockOffer then
            if luckyBlockSnapshot and self._luckyBlockService and self._luckyBlockService.RestorePlayerStateSnapshot then
                self._luckyBlockService:RestorePlayerStateSnapshot(player, luckyBlockSnapshot)
            end
        else
            self:_restoreServerLuckySnapshot(serverLuckySnapshot)
        end

        return true, Enum.ProductPurchaseDecision.NotProcessedYet
    end

    return true, Enum.ProductPurchaseDecision.PurchaseGranted
end

return ShopService
