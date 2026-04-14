--[[
脚本名字: GiftService
脚本文件: GiftService.lua
脚本类型: ModuleScript
Studio放置路径: ServerScriptService/Services/GiftService
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
        "[GiftService] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local GameConfig = requireSharedModule("GameConfig")

local GiftService = {}
GiftService._brainrotService = nil
GiftService._playerDataService = nil
GiftService._remoteEventService = nil
GiftService._brainrotGiftOfferEvent = nil
GiftService._requestBrainrotGiftDecisionEvent = nil
GiftService._brainrotGiftFeedbackEvent = nil
GiftService._promptByUserId = {}
GiftService._promptConnectionsByUserId = {}
GiftService._characterConnectionsByUserId = {}
GiftService._requestClockBySenderUserId = {}
GiftService._declineCooldownBySenderUserId = {}
GiftService._pendingRequestById = {}
GiftService._pendingRequestIdBySenderUserId = {}
GiftService._pendingRequestIdByRecipientUserId = {}
GiftService._nextRequestId = 0

local function disconnectConnections(connectionList)
    if type(connectionList) ~= "table" then
        return
    end

    for _, connection in ipairs(connectionList) do
        if connection and connection.Disconnect then
            connection:Disconnect()
        end
    end

    table.clear(connectionList)
end

local function ensureTable(parentTable, key)
    if type(parentTable[key]) ~= "table" then
        parentTable[key] = {}
    end

    return parentTable[key]
end

local function normalizeRequestId(requestId)
    return math.max(0, math.floor(tonumber(requestId) or 0))
end

local function normalizeUserId(userId)
    return math.floor(tonumber(userId) or 0)
end

local function findPlayerByNormalizedUserId(userId)
    local normalizedUserId = normalizeUserId(userId)
    if normalizedUserId == 0 then
        return nil
    end

    local ok, player = pcall(function()
        return Players:GetPlayerByUserId(normalizedUserId)
    end)
    if ok and player then
        return player
    end

    for _, candidate in ipairs(Players:GetPlayers()) do
        if normalizeUserId(candidate.UserId) == normalizedUserId then
            return candidate
        end
    end

    return nil
end

local function normalizeDecision(decision)
    local lowered = string.lower(tostring(decision or ""))
    if lowered == "accept" then
        return "Accept"
    end
    if lowered == "decline" then
        return "Decline"
    end
    if lowered == "close" then
        return "Close"
    end
    return ""
end

function GiftService:_getConfig()
    return GameConfig.GIFT or {}
end

function GiftService:_allocateRequestId()
    self._nextRequestId = normalizeRequestId(self._nextRequestId) + 1
    return self._nextRequestId
end

function GiftService:_pushFeedback(player, status, payload)
    if not (player and self._brainrotGiftFeedbackEvent) then
        return
    end

    local data = type(payload) == "table" and payload or {}
    self._brainrotGiftFeedbackEvent:FireClient(player, {
        status = tostring(status or "Unknown"),
        requestId = normalizeRequestId(data.requestId),
        targetUserId = normalizeUserId(data.targetUserId),
        senderUserId = normalizeUserId(data.senderUserId),
        recipientUserId = normalizeUserId(data.recipientUserId),
        cooldownExpiresAt = math.max(0, math.floor(tonumber(data.cooldownExpiresAt) or 0)),
        brainrotName = tostring(data.brainrotName or ""),
        timestamp = os.clock(),
    })
end

function GiftService:_pushOffer(recipientPlayer, request)
    if not (recipientPlayer and self._brainrotGiftOfferEvent and type(request) == "table") then
        return
    end

    local senderPlayer = findPlayerByNormalizedUserId(request.SenderUserId)
    self._brainrotGiftOfferEvent:FireClient(recipientPlayer, {
        requestId = normalizeRequestId(request.Id),
        senderUserId = normalizeUserId(request.SenderUserId),
        senderName = senderPlayer and senderPlayer.Name or tostring(request.SenderName or ""),
        brainrotId = math.max(0, math.floor(tonumber(request.BrainrotId) or 0)),
        brainrotLevel = math.max(1, math.floor(tonumber(request.BrainrotLevel) or 1)),
        brainrotName = tostring(request.BrainrotName or ""),
        createdAt = math.max(0, math.floor(tonumber(request.CreatedAt) or 0)),
        timestamp = os.clock(),
    })
end

function GiftService:_getPromptPart(character)
    if not character then
        return nil
    end

    local head = character:FindFirstChild("Head") or character:WaitForChild("Head", 5)
    if head and head:IsA("BasePart") then
        return head
    end

    local rootPart = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 5)
    if rootPart and rootPart:IsA("BasePart") then
        return rootPart
    end

    return character:FindFirstChildWhichIsA("BasePart")
end

function GiftService:_disconnectPrompt(userId)
    disconnectConnections(self._promptConnectionsByUserId[userId])
    self._promptConnectionsByUserId[userId] = nil

    local prompt = self._promptByUserId[userId]
    if prompt and prompt.Parent then
        prompt:Destroy()
    end
    self._promptByUserId[userId] = nil
end

function GiftService:_applyPromptConfig(prompt, targetPlayer)
    local config = self:_getConfig()
    prompt.Name = tostring(config.PromptName or "GiftPrompt")
    prompt.ActionText = tostring(config.PromptActionText or "Gift")
    prompt.ObjectText = tostring(config.PromptObjectText or "")
    prompt.HoldDuration = math.max(0.1, tonumber(config.PromptHoldDuration) or 1)
    prompt.MaxActivationDistance = math.max(4, tonumber(config.PromptMaxActivationDistance) or 10)
    prompt.RequiresLineOfSight = config.PromptRequiresLineOfSight == true
    prompt.KeyboardKeyCode = Enum.KeyCode.E
    prompt.Style = Enum.ProximityPromptStyle.Default
    prompt.Enabled = true
    prompt:SetAttribute("GiftPrompt", true)
    prompt:SetAttribute("GiftTargetUserId", targetPlayer.UserId)
    prompt:SetAttribute("GiftTargetName", targetPlayer.Name)
end

function GiftService:_attachPromptToCharacter(targetPlayer, character)
    local userId = targetPlayer.UserId
    self:_disconnectPrompt(userId)

    local promptPart = self:_getPromptPart(character)
    if not promptPart then
        warn(string.format("[GiftService] 找不到 %s 的角色提示挂点，Gift Prompt 未创建。", targetPlayer.Name))
        return
    end

    local prompt = Instance.new("ProximityPrompt")
    self:_applyPromptConfig(prompt, targetPlayer)
    prompt.Parent = promptPart
    self._promptByUserId[userId] = prompt

    local connectionList = {}
    self._promptConnectionsByUserId[userId] = connectionList
    table.insert(connectionList, prompt.Triggered:Connect(function(senderPlayer)
        self:_handlePromptTriggered(senderPlayer, targetPlayer)
    end))
    table.insert(connectionList, prompt.AncestryChanged:Connect(function(_, parent)
        if not parent then
            self:_disconnectPrompt(userId)
        end
    end))
end

function GiftService:_getDeclineCooldownExpiresAt(senderUserId, targetUserId)
    local senderCooldowns = self._declineCooldownBySenderUserId[normalizeUserId(senderUserId)]
    if type(senderCooldowns) ~= "table" then
        return 0
    end

    return math.max(0, math.floor(tonumber(senderCooldowns[normalizeUserId(targetUserId)]) or 0))
end

function GiftService:_setDeclineCooldown(senderUserId, targetUserId, expiresAt)
    local parsedSenderUserId = normalizeUserId(senderUserId)
    local parsedTargetUserId = normalizeUserId(targetUserId)
    local parsedExpiresAt = math.max(0, math.floor(tonumber(expiresAt) or 0))
    if parsedSenderUserId == 0 or parsedTargetUserId == 0 then
        return
    end

    local senderCooldowns = ensureTable(self._declineCooldownBySenderUserId, parsedSenderUserId)
    senderCooldowns[parsedTargetUserId] = parsedExpiresAt
end

function GiftService:_clearDeclineCooldownsForUser(userId)
    local parsedUserId = normalizeUserId(userId)
    self._declineCooldownBySenderUserId[parsedUserId] = nil

    for senderUserId, senderCooldowns in pairs(self._declineCooldownBySenderUserId) do
        if type(senderCooldowns) == "table" then
            senderCooldowns[parsedUserId] = nil
            if next(senderCooldowns) == nil then
                self._declineCooldownBySenderUserId[senderUserId] = nil
            end
        end
    end
end

function GiftService:_clearPendingRequestById(requestId)
    local parsedRequestId = normalizeRequestId(requestId)
    local request = self._pendingRequestById[parsedRequestId]
    if not request then
        return nil
    end

    self._pendingRequestById[parsedRequestId] = nil

    local senderUserId = normalizeUserId(request.SenderUserId)
    local recipientUserId = normalizeUserId(request.RecipientUserId)
    if self._pendingRequestIdBySenderUserId[senderUserId] == parsedRequestId then
        self._pendingRequestIdBySenderUserId[senderUserId] = nil
    end
    if self._pendingRequestIdByRecipientUserId[recipientUserId] == parsedRequestId then
        self._pendingRequestIdByRecipientUserId[recipientUserId] = nil
    end

    return request
end

function GiftService:_scheduleRequestExpiry(requestId)
    local expireSeconds = math.max(5, tonumber((self:_getConfig().RequestExpireSeconds)) or 30)
    task.delay(expireSeconds, function()
        local activeRequest = self._pendingRequestById[normalizeRequestId(requestId)]
        if not activeRequest then
            return
        end

        local request = self:_clearPendingRequestById(requestId)
        if not request then
            return
        end

        local senderPlayer = findPlayerByNormalizedUserId(request.SenderUserId)
        local recipientPlayer = findPlayerByNormalizedUserId(request.RecipientUserId)
        if senderPlayer then
            self:_pushFeedback(senderPlayer, "Expired", {
                requestId = request.Id,
                targetUserId = request.RecipientUserId,
                recipientUserId = request.RecipientUserId,
                brainrotName = request.BrainrotName,
            })
        end
        if recipientPlayer then
            self:_pushFeedback(recipientPlayer, "Expired", {
                requestId = request.Id,
                senderUserId = request.SenderUserId,
                recipientUserId = request.RecipientUserId,
                brainrotName = request.BrainrotName,
            })
        end
    end)
end

function GiftService:_canHandlePromptTrigger(senderPlayer)
    if not senderPlayer then
        return false
    end

    local debounceSeconds = math.max(0.05, tonumber((self:_getConfig().RequestDebounceSeconds)) or 0.2)
    local nowClock = os.clock()
    local senderUserId = senderPlayer.UserId
    local lastClock = tonumber(self._requestClockBySenderUserId[senderUserId]) or 0
    if nowClock - lastClock < debounceSeconds then
        return false
    end

    self._requestClockBySenderUserId[senderUserId] = nowClock
    return true
end

function GiftService:_handlePromptTriggered(senderPlayer, targetPlayer)
    if not (senderPlayer and targetPlayer) then
        return
    end

    if not self:_canHandlePromptTrigger(senderPlayer) then
        return
    end

    if senderPlayer == targetPlayer or senderPlayer.UserId == targetPlayer.UserId then
        return
    end

    local senderUserId = normalizeUserId(senderPlayer.UserId)
    local targetUserId = normalizeUserId(targetPlayer.UserId)

    local cooldownExpiresAt = self:_getDeclineCooldownExpiresAt(senderUserId, targetUserId)
    if cooldownExpiresAt > os.time() then
        self:_pushFeedback(senderPlayer, "Declined", {
            targetUserId = targetUserId,
            recipientUserId = targetUserId,
            cooldownExpiresAt = cooldownExpiresAt,
        })
        return
    end

    if self._pendingRequestIdBySenderUserId[senderUserId] then
        self:_pushFeedback(senderPlayer, "SenderBusy", {
            targetUserId = targetUserId,
            recipientUserId = targetUserId,
        })
        return
    end

    if self._pendingRequestIdByRecipientUserId[targetUserId] then
        self:_pushFeedback(senderPlayer, "TargetBusy", {
            targetUserId = targetUserId,
            recipientUserId = targetUserId,
        })
        return
    end

    local giftInfo = self._brainrotService and self._brainrotService.GetEquippedGiftBrainrotInfo and self._brainrotService:GetEquippedGiftBrainrotInfo(senderPlayer) or nil
    if type(giftInfo) ~= "table" then
        self:_pushFeedback(senderPlayer, "SenderNotHoldingBrainrot", {
            targetUserId = targetUserId,
            recipientUserId = targetUserId,
        })
        return
    end

    local requestId = self:_allocateRequestId()
    local request = {
        Id = requestId,
        SenderUserId = senderUserId,
        SenderName = senderPlayer.Name,
        RecipientUserId = targetUserId,
        BrainrotInstanceId = math.max(0, math.floor(tonumber(giftInfo.instanceId) or 0)),
        BrainrotId = math.max(0, math.floor(tonumber(giftInfo.brainrotId) or 0)),
        BrainrotLevel = math.max(1, math.floor(tonumber(giftInfo.level) or 1)),
        BrainrotName = tostring(giftInfo.brainrotName or "Brainrot"),
        CreatedAt = os.time(),
    }

    self._pendingRequestById[requestId] = request
    self._pendingRequestIdBySenderUserId[senderUserId] = requestId
    self._pendingRequestIdByRecipientUserId[targetUserId] = requestId

    self:_pushOffer(targetPlayer, request)
    self:_pushFeedback(senderPlayer, "Requested", {
        requestId = requestId,
        targetUserId = targetUserId,
        recipientUserId = targetUserId,
        brainrotName = request.BrainrotName,
    })
    self:_scheduleRequestExpiry(requestId)
end

function GiftService:_resolveDecline(request, recipientPlayer)
    local requestId = normalizeRequestId(request and request.Id)
    local targetUserId = normalizeUserId(recipientPlayer and recipientPlayer.UserId)
    local senderPlayer = request and findPlayerByNormalizedUserId(request.SenderUserId) or nil
    local cooldownExpiresAt = os.time() + math.max(1, math.floor(tonumber((self:_getConfig().DeclineCooldownSeconds)) or 300))

    self:_setDeclineCooldown(request.SenderUserId, targetUserId, cooldownExpiresAt)

    if senderPlayer then
        self:_pushFeedback(senderPlayer, "Declined", {
            requestId = requestId,
            targetUserId = targetUserId,
            recipientUserId = targetUserId,
            cooldownExpiresAt = cooldownExpiresAt,
            brainrotName = request.BrainrotName,
        })
    end

    if recipientPlayer then
        self:_pushFeedback(recipientPlayer, "Declined", {
            requestId = requestId,
            senderUserId = request.SenderUserId,
            recipientUserId = targetUserId,
            cooldownExpiresAt = cooldownExpiresAt,
            brainrotName = request.BrainrotName,
        })
    end
end

function GiftService:_resolveClose(request, recipientPlayer)
    local requestId = normalizeRequestId(request and request.Id)
    local senderPlayer = request and findPlayerByNormalizedUserId(request.SenderUserId) or nil
    local recipientUserId = normalizeUserId(recipientPlayer and recipientPlayer.UserId or request and request.RecipientUserId)

    if senderPlayer then
        self:_pushFeedback(senderPlayer, "Closed", {
            requestId = requestId,
            targetUserId = recipientUserId,
            recipientUserId = recipientUserId,
            brainrotName = request and request.BrainrotName or "",
        })
    end

    if recipientPlayer then
        self:_pushFeedback(recipientPlayer, "Closed", {
            requestId = requestId,
            senderUserId = request and request.SenderUserId or 0,
            recipientUserId = recipientUserId,
            brainrotName = request and request.BrainrotName or "",
        })
    end
end

function GiftService:_resolveAccept(request, recipientPlayer)
    local senderPlayer = request and findPlayerByNormalizedUserId(request.SenderUserId) or nil
    if not (senderPlayer and recipientPlayer) then
        if recipientPlayer then
            self:_pushFeedback(recipientPlayer, "Cancelled", {
                requestId = request and request.Id or 0,
                senderUserId = request and request.SenderUserId or 0,
                recipientUserId = recipientPlayer.UserId,
                brainrotName = request and request.BrainrotName or "",
            })
        end
        if senderPlayer then
            self:_pushFeedback(senderPlayer, "Cancelled", {
                requestId = request and request.Id or 0,
                targetUserId = recipientPlayer and recipientPlayer.UserId or 0,
                recipientUserId = recipientPlayer and recipientPlayer.UserId or 0,
                brainrotName = request and request.BrainrotName or "",
            })
        end
        return
    end

    local senderSnapshot = self._brainrotService and self._brainrotService.CreatePlayerStateSnapshot
        and self._brainrotService:CreatePlayerStateSnapshot(senderPlayer)
        or nil
    local recipientSnapshot = self._brainrotService and self._brainrotService.CreatePlayerStateSnapshot
        and self._brainrotService:CreatePlayerStateSnapshot(recipientPlayer)
        or nil

    local transferSucceeded = false
    if self._brainrotService and self._brainrotService.TransferBrainrotInstance then
        transferSucceeded = select(1, self._brainrotService:TransferBrainrotInstance(senderPlayer, recipientPlayer, request.BrainrotInstanceId, "Gift"))
    end

    local status = transferSucceeded and "Accepted" or "Cancelled"
    if transferSucceeded then
        local senderSaved = not self._playerDataService or self._playerDataService:SavePlayerData(senderPlayer)
        local recipientSaved = senderSaved and (not self._playerDataService or self._playerDataService:SavePlayerData(recipientPlayer))
        if not senderSaved or not recipientSaved then
            if self._brainrotService and self._brainrotService.RestorePlayerStateSnapshot then
                if senderSnapshot then
                    self._brainrotService:RestorePlayerStateSnapshot(senderPlayer, senderSnapshot)
                end
                if recipientSnapshot then
                    self._brainrotService:RestorePlayerStateSnapshot(recipientPlayer, recipientSnapshot)
                end
            end
            if self._playerDataService then
                if senderSnapshot then
                    self._playerDataService:SavePlayerData(senderPlayer)
                end
                if recipientSnapshot then
                    self._playerDataService:SavePlayerData(recipientPlayer)
                end
            end
            status = "SaveFailed"
        end
    end

    self:_pushFeedback(senderPlayer, status, {
        requestId = request.Id,
        targetUserId = recipientPlayer.UserId,
        recipientUserId = recipientPlayer.UserId,
        brainrotName = request.BrainrotName,
    })
    self:_pushFeedback(recipientPlayer, status, {
        requestId = request.Id,
        senderUserId = request.SenderUserId,
        recipientUserId = recipientPlayer.UserId,
        brainrotName = request.BrainrotName,
    })
end

function GiftService:_handleRequestBrainrotGiftDecision(recipientPlayer, payload)
    if not recipientPlayer then
        return
    end

    local requestId = 0
    local decision = ""
    if type(payload) == "table" then
        requestId = normalizeRequestId(payload.requestId)
        decision = normalizeDecision(payload.decision)
    else
        requestId = normalizeRequestId(payload)
    end

    if requestId <= 0 or decision == "" then
        self:_pushFeedback(recipientPlayer, "InvalidRequest", {
            requestId = requestId,
            recipientUserId = recipientPlayer.UserId,
        })
        return
    end

    local activeRequest = self._pendingRequestById[requestId]
    if not activeRequest or normalizeUserId(activeRequest.RecipientUserId) ~= normalizeUserId(recipientPlayer.UserId) then
        self:_pushFeedback(recipientPlayer, "InvalidRequest", {
            requestId = requestId,
            recipientUserId = recipientPlayer.UserId,
        })
        return
    end

    local request = self:_clearPendingRequestById(requestId)
    if not request then
        self:_pushFeedback(recipientPlayer, "InvalidRequest", {
            requestId = requestId,
            recipientUserId = recipientPlayer.UserId,
        })
        return
    end

    if decision == "Accept" then
        self:_resolveAccept(request, recipientPlayer)
        return
    end

    if decision == "Close" then
        self:_resolveClose(request, recipientPlayer)
        return
    end

    self:_resolveDecline(request, recipientPlayer)
end

function GiftService:OnPlayerReady(player)
    if not player then
        return
    end

    local userId = player.UserId
    disconnectConnections(self._characterConnectionsByUserId[userId])

    local connectionList = {}
    self._characterConnectionsByUserId[userId] = connectionList
    table.insert(connectionList, player.CharacterAdded:Connect(function(character)
        task.defer(function()
            self:_attachPromptToCharacter(player, character)
        end)
    end))

    if player.Character then
        task.defer(function()
            self:_attachPromptToCharacter(player, player.Character)
        end)
    end
end

function GiftService:OnPlayerRemoving(player)
    if not player then
        return
    end

    local userId = normalizeUserId(player.UserId)

    disconnectConnections(self._characterConnectionsByUserId[userId])
    self._characterConnectionsByUserId[userId] = nil
    self:_disconnectPrompt(userId)

    self._requestClockBySenderUserId[userId] = nil
    self:_clearDeclineCooldownsForUser(userId)

    local senderRequestId = self._pendingRequestIdBySenderUserId[userId]
    if senderRequestId then
        local request = self:_clearPendingRequestById(senderRequestId)
        local recipientPlayer = request and findPlayerByNormalizedUserId(request.RecipientUserId) or nil
        if recipientPlayer and request then
            self:_pushFeedback(recipientPlayer, "Cancelled", {
                requestId = request.Id,
                senderUserId = request.SenderUserId,
                recipientUserId = request.RecipientUserId,
                brainrotName = request.BrainrotName,
            })
        end
    end

    local recipientRequestId = self._pendingRequestIdByRecipientUserId[userId]
    if recipientRequestId then
        local request = self:_clearPendingRequestById(recipientRequestId)
        local senderPlayer = request and findPlayerByNormalizedUserId(request.SenderUserId) or nil
        if senderPlayer and request then
            self:_pushFeedback(senderPlayer, "Cancelled", {
                requestId = request.Id,
                targetUserId = request.RecipientUserId,
                recipientUserId = request.RecipientUserId,
                brainrotName = request.BrainrotName,
            })
        end
    end
end

function GiftService:Init(dependencies)
    self._brainrotService = dependencies.BrainrotService
    self._playerDataService = dependencies.PlayerDataService
    self._remoteEventService = dependencies.RemoteEventService

    self._brainrotGiftOfferEvent = self._remoteEventService:GetEvent("BrainrotGiftOffer")
    self._requestBrainrotGiftDecisionEvent = self._remoteEventService:GetEvent("RequestBrainrotGiftDecision")
    self._brainrotGiftFeedbackEvent = self._remoteEventService:GetEvent("BrainrotGiftFeedback")

    if self._requestBrainrotGiftDecisionEvent then
        self._requestBrainrotGiftDecisionEvent.OnServerEvent:Connect(function(player, payload)
            self:_handleRequestBrainrotGiftDecision(player, payload)
        end)
    end
end

return GiftService

