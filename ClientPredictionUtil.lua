--[[
脚本名字: ClientPredictionUtil
脚本文件: ClientPredictionUtil.lua
脚本类型: ModuleScript
Studio放置路径: ReplicatedStorage/Shared/ClientPredictionUtil
]]

local HttpService = game:GetService("HttpService")

local ClientPredictionUtil = {}

ClientPredictionUtil._coinChangedEvent = Instance.new("BindableEvent")
ClientPredictionUtil._pendingChangedEvent = Instance.new("BindableEvent")
ClientPredictionUtil._authoritativeCoins = 0
ClientPredictionUtil._pendingByRequestId = {}
ClientPredictionUtil._pendingKeyByRequestId = {}

local function normalizeRequestId(requestId)
    return tostring(requestId or "")
end

local function normalizeRequestKey(requestKey)
    return tostring(requestKey or "")
end

local function normalizeCoinValue(value)
    return tonumber(value) or 0
end

local function cloneMetadata(metadata)
    if type(metadata) ~= "table" then
        return nil
    end

    return table.clone(metadata)
end

function ClientPredictionUtil:_getUnacknowledgedPredictedCoinDelta()
    local totalDelta = 0
    for _, pendingRequest in pairs(self._pendingByRequestId) do
        if pendingRequest.CoinDelta ~= 0 and pendingRequest.IsCoinDeltaAcknowledged ~= true then
            totalDelta += pendingRequest.CoinDelta
        end
    end

    return totalDelta
end

function ClientPredictionUtil:GetAuthoritativeCoins()
    return self._authoritativeCoins
end

function ClientPredictionUtil:GetEffectiveCoins()
    return self._authoritativeCoins + self:_getUnacknowledgedPredictedCoinDelta()
end

function ClientPredictionUtil:_buildCoinSnapshot(source, extra)
    local snapshot = {
        source = tostring(source or ""),
        authoritativeCoins = self._authoritativeCoins,
        predictedCoinDelta = self:_getUnacknowledgedPredictedCoinDelta(),
        effectiveCoins = self:GetEffectiveCoins(),
    }

    if type(extra) == "table" then
        for key, value in pairs(extra) do
            snapshot[key] = value
        end
    end

    return snapshot
end

function ClientPredictionUtil:_fireCoinChanged(source, extra)
    local snapshot = self:_buildCoinSnapshot(source, extra)
    self._coinChangedEvent:Fire(snapshot)
    return snapshot
end

function ClientPredictionUtil:_firePendingChanged()
    self._pendingChangedEvent:Fire()
end

function ClientPredictionUtil:ConnectCoinChanged(callback)
    return self._coinChangedEvent.Event:Connect(callback)
end

function ClientPredictionUtil:ConnectPendingChanged(callback)
    return self._pendingChangedEvent.Event:Connect(callback)
end

function ClientPredictionUtil:GetPendingRequest(requestId)
    return self._pendingByRequestId[normalizeRequestId(requestId)]
end

function ClientPredictionUtil:HasPendingKey(requestKey)
    local normalizedKey = normalizeRequestKey(requestKey)
    if normalizedKey == "" then
        return false
    end

    for pendingRequestId, pendingKey in pairs(self._pendingKeyByRequestId) do
        if pendingKey == normalizedKey and self._pendingByRequestId[pendingRequestId] ~= nil then
            return true
        end
    end

    return false
end

function ClientPredictionUtil:GenerateRequestId(prefix)
    local safePrefix = tostring(prefix or "Request")
    return string.format("%s_%s", safePrefix, HttpService:GenerateGUID(false))
end

function ClientPredictionUtil:BeginRequest(options)
    local requestOptions = type(options) == "table" and options or {}
    local requestKey = normalizeRequestKey(requestOptions.key)
    if requestKey ~= "" and self:HasPendingKey(requestKey) then
        return nil, "Pending"
    end

    local requestId = normalizeRequestId(requestOptions.requestId)
    if requestId == "" then
        requestId = self:GenerateRequestId(requestOptions.prefix or requestKey or "Request")
    end

    if self._pendingByRequestId[requestId] ~= nil then
        return nil, "Duplicate"
    end

    local previousEffectiveCoins = self:GetEffectiveCoins()
    local pendingRequest = {
        RequestId = requestId,
        Key = requestKey,
        CoinDelta = normalizeCoinValue(requestOptions.coinDelta),
        CreatedAt = os.clock(),
        Metadata = cloneMetadata(requestOptions.metadata),
        OnTimeout = requestOptions.onTimeout,
        IsCoinDeltaAcknowledged = false,
    }

    self._pendingByRequestId[requestId] = pendingRequest
    if requestKey ~= "" then
        self._pendingKeyByRequestId[requestId] = requestKey
    end

    local timeoutSeconds = math.max(0, tonumber(requestOptions.timeoutSeconds) or 0)
    if timeoutSeconds > 0 then
        task.delay(timeoutSeconds, function()
            local activeRequest = self._pendingByRequestId[requestId]
            if activeRequest ~= pendingRequest then
                return
            end

            local timedOutRequest = self:RejectRequest(requestId)
            if timedOutRequest and type(timedOutRequest.OnTimeout) == "function" then
                timedOutRequest.OnTimeout(timedOutRequest)
            end
        end)
    end

    self:_firePendingChanged()
    self:_fireCoinChanged("prediction_begin", {
        requestId = requestId,
        previousEffectiveCoins = previousEffectiveCoins,
    })

    return requestId, pendingRequest
end

function ClientPredictionUtil:_removePendingRequest(requestId, source, extra)
    local normalizedRequestId = normalizeRequestId(requestId)
    local pendingRequest = self._pendingByRequestId[normalizedRequestId]
    if not pendingRequest then
        if type(extra) == "table" and extra.authoritativeCoins ~= nil then
            local previousEffectiveCoins = self:GetEffectiveCoins()
            self._authoritativeCoins = math.max(0, normalizeCoinValue(extra.authoritativeCoins))
            self:_fireCoinChanged(source, {
                requestId = normalizedRequestId,
                previousEffectiveCoins = previousEffectiveCoins,
                suppressPopup = true,
            })
        end
        return nil
    end

    local previousEffectiveCoins = self:GetEffectiveCoins()
    if type(extra) == "table" and extra.acknowledgeCoinDelta == true then
        pendingRequest.IsCoinDeltaAcknowledged = true
    end
    if type(extra) == "table" and extra.authoritativeCoins ~= nil then
        self._authoritativeCoins = math.max(0, normalizeCoinValue(extra.authoritativeCoins))
    end

    self._pendingByRequestId[normalizedRequestId] = nil
    self._pendingKeyByRequestId[normalizedRequestId] = nil

    self:_firePendingChanged()
    self:_fireCoinChanged(source, {
        requestId = normalizedRequestId,
        previousEffectiveCoins = previousEffectiveCoins,
        suppressPopup = true,
    })

    return pendingRequest
end

function ClientPredictionUtil:ResolveRequest(requestId, options)
    return self:_removePendingRequest(requestId, "prediction_resolve", options)
end

function ClientPredictionUtil:RejectRequest(requestId, options)
    return self:_removePendingRequest(requestId, "prediction_reject", options)
end

function ClientPredictionUtil:SetAuthoritativeCoins(totalCoins, serverDelta)
    local previousEffectiveCoins = self:GetEffectiveCoins()
    local matchedRequestId = ""
    local normalizedServerDelta = normalizeCoinValue(serverDelta)

    self._authoritativeCoins = math.max(0, normalizeCoinValue(totalCoins))

    if normalizedServerDelta ~= 0 then
        local bestRequest = nil
        for _, pendingRequest in pairs(self._pendingByRequestId) do
            if pendingRequest.CoinDelta == normalizedServerDelta and pendingRequest.IsCoinDeltaAcknowledged ~= true then
                if not bestRequest or pendingRequest.CreatedAt < bestRequest.CreatedAt then
                    bestRequest = pendingRequest
                end
            end
        end

        if bestRequest then
            bestRequest.IsCoinDeltaAcknowledged = true
            matchedRequestId = bestRequest.RequestId
        end
    end

    return self:_fireCoinChanged("authoritative", {
        serverDelta = normalizedServerDelta,
        matchedRequestId = matchedRequestId,
        previousEffectiveCoins = previousEffectiveCoins,
        suppressPopup = matchedRequestId ~= "",
    })
end

return ClientPredictionUtil
