--[[
Script Name: SpecialEventService
Script File: SpecialEventService.lua
Script Type: ModuleScript
Local Path: D:/RobloxGame/BrainrotsTemplate/SpecialEventService.lua
Studio Path: ServerScriptService/Services/SpecialEventService
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
        "[SpecialEventService] Missing shared module %s (expected in ReplicatedStorage/Shared or ReplicatedStorage root)",
        moduleName
    ))
end

local GameConfig = requireSharedModule("GameConfig")

local SpecialEventService = {}
SpecialEventService._activeEventsByRuntimeKey = {}
SpecialEventService._didWarnByKey = {}
SpecialEventService._scheduleThread = nil
SpecialEventService._scheduleState = nil
SpecialEventService._manualSerial = 0
SpecialEventService._eventConfigById = nil
SpecialEventService._sortedEventConfigs = nil
SpecialEventService._remoteEventService = nil
SpecialEventService._specialEventStateSyncEvent = nil
SpecialEventService._requestSpecialEventStateSyncEvent = nil
SpecialEventService._requestStateSyncConnection = nil

local function clampNonNegativeInteger(value)
    return math.max(0, math.floor(tonumber(value) or 0))
end

local function getPositiveIntegerOrDefault(value, defaultValue)
    local numericValue = math.floor(tonumber(value) or 0)
    if numericValue <= 0 then
        return math.max(1, math.floor(tonumber(defaultValue) or 1))
    end

    return numericValue
end

local function normalizeMutationRarityName(value)
    local text = tostring(value or "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

local function hashUnit(slotIndex, salt)
    local base = ((math.floor(slotIndex) + 1) * 48271 + (math.floor(salt) + 11) * 7841) % 2147483647
    local mixed = (base * 16807 + 97) % 2147483647
    return mixed / 2147483647
end

function SpecialEventService:_warnOnce(key, message)
    if self._didWarnByKey[key] then
        return
    end

    self._didWarnByKey[key] = true
    warn(message)
end

function SpecialEventService:_getConfig()
    return GameConfig.SPECIAL_EVENT or {}
end

function SpecialEventService:_bindRemoteEvents(remoteEventService)
    if remoteEventService then
        self._remoteEventService = remoteEventService
    end

    if not self._remoteEventService then
        self:_warnOnce("MissingRemoteEventService", "[SpecialEventService] RemoteEventService 未注入，事件状态无法同步到客户端。")
        return
    end

    self._specialEventStateSyncEvent = self._remoteEventService:GetEvent("SpecialEventStateSync")
    self._requestSpecialEventStateSyncEvent = self._remoteEventService:GetEvent("RequestSpecialEventStateSync")

    if self._requestSpecialEventStateSyncEvent and not self._requestStateSyncConnection then
        self._requestStateSyncConnection = self._requestSpecialEventStateSyncEvent.OnServerEvent:Connect(function(player)
            self:_syncActiveEventStateToPlayer(player)
        end)
    end
end

function SpecialEventService:_ensureEventConfigs()
    if self._eventConfigById and self._sortedEventConfigs then
        return
    end

    local byId = {}
    local sorted = {}
    local entries = self:_getConfig().Entries
    if type(entries) == "table" then
        for _, rawEntry in ipairs(entries) do
            if type(rawEntry) == "table" then
                local eventId = clampNonNegativeInteger(rawEntry.Id)
                local durationSeconds = getPositiveIntegerOrDefault(rawEntry.DurationSeconds, 300)
                local templateName = tostring(rawEntry.TemplateName or rawEntry.ReplicatedStorageName or "")
                local renderMode = tostring(rawEntry.RenderMode or rawEntry.TemplateRenderMode or "")
                if renderMode == "" then
                    if string.find(templateName, "/", 1, true) then
                        renderMode = "WorkspaceScene"
                    else
                        renderMode = "CharacterAttachment"
                    end
                end

                if eventId > 0 and templateName ~= "" then
                    local eventConfig = {
                        Id = eventId,
                        Name = tostring(rawEntry.Name or eventId),
                        Weight = math.max(0, tonumber(rawEntry.Weight) or 0),
                        DurationSeconds = durationSeconds,
                        TemplateName = templateName,
                        RenderMode = renderMode,
                        LightingPath = tostring(rawEntry.LightingPath or rawEntry.SkyboxPath or ""),
                        DisplayLabelName = tostring(rawEntry.DisplayLabelName or rawEntry.TextDisplayName or ""),
                        MutationRarityName = normalizeMutationRarityName(
                            rawEntry.MutationRarityName
                                or rawEntry.BrainrotMutationRarityName
                                or rawEntry.BrainrotRarityName
                                or rawEntry.BrainrotRarity
                                or rawEntry.RarityName
                        ),
                    }
                    byId[eventId] = eventConfig
                    table.insert(sorted, eventConfig)
                end
            end
        end
    end

    table.sort(sorted, function(a, b)
        return a.Id < b.Id
    end)

    self._eventConfigById = byId
    self._sortedEventConfigs = sorted
end

function SpecialEventService:_getSortedEventConfigs()
    self:_ensureEventConfigs()
    return self._sortedEventConfigs or {}
end

function SpecialEventService:_getEventConfigById(eventId)
    self:_ensureEventConfigs()
    return (self._eventConfigById or {})[clampNonNegativeInteger(eventId)]
end

function SpecialEventService:_serializeEventState(runtimeKey, eventId, eventConfig, startedAt, endsAt, source)
    if type(eventConfig) ~= "table" then
        return nil
    end

    return {
        runtimeKey = tostring(runtimeKey or ""),
        eventId = clampNonNegativeInteger(eventId),
        name = tostring(eventConfig.Name or eventId or ""),
        templateName = tostring(eventConfig.TemplateName or ""),
        renderMode = tostring(eventConfig.RenderMode or ""),
        lightingPath = tostring(eventConfig.LightingPath or ""),
        displayLabelName = tostring(eventConfig.DisplayLabelName or ""),
        mutationRarityName = tostring(eventConfig.MutationRarityName or ""),
        startedAt = clampNonNegativeInteger(startedAt),
        endsAt = clampNonNegativeInteger(endsAt),
        source = tostring(source or "Unknown"),
    }
end

function SpecialEventService:_serializeActiveEvent(activeEvent)
    if type(activeEvent) ~= "table" or type(activeEvent.EventConfig) ~= "table" then
        return nil
    end

    return self:_serializeEventState(
        activeEvent.RuntimeKey,
        activeEvent.EventId,
        activeEvent.EventConfig,
        activeEvent.StartedAt,
        activeEvent.EndsAt,
        activeEvent.Source
    )
end

function SpecialEventService:_createStatePayload()
    local activeEvents = {}
    for _, activeEvent in pairs(self._activeEventsByRuntimeKey) do
        local serializedEvent = self:_serializeActiveEvent(activeEvent)
        if serializedEvent then
            table.insert(activeEvents, serializedEvent)
        end
    end

    table.sort(activeEvents, function(a, b)
        if a.startedAt ~= b.startedAt then
            return a.startedAt < b.startedAt
        end

        return a.runtimeKey < b.runtimeKey
    end)

    local now = os.time()
    local currentScheduledEvent, nextScheduledEvent = self:_getScheduledTimeline(now)
    return {
        activeEvents = activeEvents,
        currentScheduledEvent = currentScheduledEvent and self:_serializeActiveEvent(currentScheduledEvent) or nil,
        nextScheduledEvent = nextScheduledEvent and self:_serializeActiveEvent(nextScheduledEvent) or nil,
        serverTime = now,
        timestamp = now,
    }
end

function SpecialEventService:_broadcastActiveEventState()
    if not (self._specialEventStateSyncEvent and self._specialEventStateSyncEvent:IsA("RemoteEvent")) then
        return
    end

    self._specialEventStateSyncEvent:FireAllClients(self:_createStatePayload())
end

function SpecialEventService:_syncActiveEventStateToPlayer(player)
    if not (player and player.Parent) then
        return
    end

    if not (self._specialEventStateSyncEvent and self._specialEventStateSyncEvent:IsA("RemoteEvent")) then
        return
    end

    self._specialEventStateSyncEvent:FireClient(player, self:_createStatePayload())
end

function SpecialEventService:_activateEvent(eventConfig, runtimeKey, endsAt, source, startedAt)
    if not (eventConfig and runtimeKey) then
        return nil
    end

    local activeEvent = {
        RuntimeKey = tostring(runtimeKey),
        EventId = eventConfig.Id,
        EventConfig = eventConfig,
        EndsAt = math.max(os.time(), clampNonNegativeInteger(endsAt)),
        StartedAt = clampNonNegativeInteger(startedAt),
        Source = tostring(source or "Unknown"),
    }
    self._activeEventsByRuntimeKey[activeEvent.RuntimeKey] = activeEvent
    self:_broadcastActiveEventState()
    return activeEvent
end

function SpecialEventService:_removeActiveEventByRuntimeKey(runtimeKey, suppressSync)
    local activeEvent = self._activeEventsByRuntimeKey[runtimeKey]
    if not activeEvent then
        return false
    end

    self._activeEventsByRuntimeKey[runtimeKey] = nil
    if suppressSync ~= true then
        self:_broadcastActiveEventState()
    end
    return true
end

function SpecialEventService:_removeActiveEventsByEventId(eventId, suppressSync)
    local removedAny = false
    local runtimeKeys = {}
    for runtimeKey, activeEvent in pairs(self._activeEventsByRuntimeKey) do
        if activeEvent.EventId == eventId then
            table.insert(runtimeKeys, runtimeKey)
        end
    end

    for _, runtimeKey in ipairs(runtimeKeys) do
        if self:_removeActiveEventByRuntimeKey(runtimeKey, true) then
            removedAny = true
        end
    end

    if removedAny and suppressSync ~= true then
        self:_broadcastActiveEventState()
    end

    return removedAny
end

function SpecialEventService:_hasActiveEventWithEventId(eventId)
    for _, activeEvent in pairs(self._activeEventsByRuntimeKey) do
        if activeEvent.EventId == eventId then
            return true
        end
    end

    return false
end

function SpecialEventService:_cleanupExpiredEvents(now)
    local runtimeKeys = {}
    for runtimeKey, activeEvent in pairs(self._activeEventsByRuntimeKey) do
        if now >= activeEvent.EndsAt then
            table.insert(runtimeKeys, runtimeKey)
        end
    end

    local removedAny = false
    for _, runtimeKey in ipairs(runtimeKeys) do
        if self:_removeActiveEventByRuntimeKey(runtimeKey, true) then
            removedAny = true
        end
    end

    if removedAny then
        self:_broadcastActiveEventState()
    end
end

function SpecialEventService:_getSortedActiveEvents()
    local activeEvents = {}
    for _, activeEvent in pairs(self._activeEventsByRuntimeKey) do
        table.insert(activeEvents, activeEvent)
    end

    table.sort(activeEvents, function(a, b)
        if a.StartedAt ~= b.StartedAt then
            return a.StartedAt < b.StartedAt
        end

        return tostring(a.RuntimeKey) < tostring(b.RuntimeKey)
    end)

    return activeEvents
end

function SpecialEventService:_getPrimaryActiveEvent()
    local activeEvents = self:_getSortedActiveEvents()
    return activeEvents[1]
end

function SpecialEventService:_getScheduleIntervalSeconds()
    return math.max(60, getPositiveIntegerOrDefault(self:_getConfig().ScheduleIntervalSeconds, 1800))
end

function SpecialEventService:_getScheduleAnchorUnix()
    return getPositiveIntegerOrDefault(self:_getConfig().ScheduleAnchorUnix, 1735689600)
end

function SpecialEventService:_ensureScheduleState()
    local anchorUnix = self:_getScheduleAnchorUnix()
    if self._scheduleState and self._scheduleState.AnchorUnix == anchorUnix then
        return self._scheduleState
    end

    self._scheduleState = {
        AnchorUnix = anchorUnix,
        LastComputedSlotIndex = -1,
        LastComputedEventId = nil,
    }
    return self._scheduleState
end

function SpecialEventService:_chooseScheduledEventId(slotIndex, previousEventId)
    local candidates = {}
    local totalWeight = 0
    local weightedEntries = {}

    for _, eventConfig in ipairs(self:_getSortedEventConfigs()) do
        if eventConfig.Weight > 0 then
            table.insert(weightedEntries, eventConfig)
        end
    end

    if #weightedEntries <= 0 then
        return nil
    end

    for _, eventConfig in ipairs(weightedEntries) do
        if #weightedEntries <= 1 or eventConfig.Id ~= previousEventId then
            table.insert(candidates, eventConfig)
            totalWeight += eventConfig.Weight
        end
    end

    if #candidates <= 0 then
        candidates = weightedEntries
        totalWeight = 0
        for _, eventConfig in ipairs(candidates) do
            totalWeight += eventConfig.Weight
        end
    end

    if totalWeight <= 0 then
        local fallbackIndex = (math.floor(slotIndex) % #candidates) + 1
        return candidates[fallbackIndex].Id
    end

    local roll = hashUnit(slotIndex, previousEventId or 0) * totalWeight
    local accumulated = 0
    for _, eventConfig in ipairs(candidates) do
        accumulated += eventConfig.Weight
        if roll < accumulated then
            return eventConfig.Id
        end
    end

    return candidates[#candidates].Id
end

function SpecialEventService:_advanceScheduleStateTo(slotIndex)
    local state = self:_ensureScheduleState()
    local targetSlotIndex = math.max(0, math.floor(tonumber(slotIndex) or 0))
    if targetSlotIndex < state.LastComputedSlotIndex then
        state.LastComputedSlotIndex = -1
        state.LastComputedEventId = nil
    end

    for nextSlotIndex = state.LastComputedSlotIndex + 1, targetSlotIndex do
        state.LastComputedEventId = self:_chooseScheduledEventId(nextSlotIndex, state.LastComputedEventId)
        state.LastComputedSlotIndex = nextSlotIndex
    end

    return state.LastComputedEventId
end

function SpecialEventService:_buildScheduledEvent(slotIndex, slotStartAt, eventId)
    local eventConfig = self:_getEventConfigById(eventId)
    if not eventConfig then
        return nil
    end

    return {
        RuntimeKey = string.format("Schedule_%d", slotIndex),
        EventId = eventId,
        EventConfig = eventConfig,
        StartedAt = slotStartAt,
        EndsAt = slotStartAt + eventConfig.DurationSeconds,
        Source = "Schedule",
    }
end

function SpecialEventService:_getScheduledTimeline(now)
    local sortedEventConfigs = self:_getSortedEventConfigs()
    if #sortedEventConfigs <= 0 then
        return nil, nil
    end

    local currentUnix = clampNonNegativeInteger(now)
    local intervalSeconds = self:_getScheduleIntervalSeconds()
    local anchorUnix = self:_getScheduleAnchorUnix()
    if currentUnix < anchorUnix then
        anchorUnix = 0
    end

    local elapsedSinceAnchor = math.max(0, currentUnix - anchorUnix)
    local slotIndex = math.floor(elapsedSinceAnchor / intervalSeconds)
    local slotStartAt = anchorUnix + slotIndex * intervalSeconds
    local eventId = self:_advanceScheduleStateTo(slotIndex)
    local currentScheduledEvent = self:_buildScheduledEvent(slotIndex, slotStartAt, eventId)
    if currentScheduledEvent and currentUnix >= currentScheduledEvent.EndsAt then
        currentScheduledEvent = nil
    end

    local nextSlotIndex = slotIndex + 1
    local nextSlotStartAt = anchorUnix + nextSlotIndex * intervalSeconds
    local nextEventId = self:_chooseScheduledEventId(nextSlotIndex, eventId)
    local nextScheduledEvent = self:_buildScheduledEvent(nextSlotIndex, nextSlotStartAt, nextEventId)
    return currentScheduledEvent, nextScheduledEvent
end

function SpecialEventService:_getCurrentScheduledEvent(now)
    local currentScheduledEvent = self:_getScheduledTimeline(now)
    return currentScheduledEvent
end

function SpecialEventService:_schedulerStep()
    local now = os.time()
    self:_cleanupExpiredEvents(now)

    local scheduledEvent = self:_getCurrentScheduledEvent(now)
    if not scheduledEvent then
        return
    end

    if self._activeEventsByRuntimeKey[scheduledEvent.RuntimeKey] then
        return
    end

    if self:_hasActiveEventWithEventId(scheduledEvent.EventId) then
        return
    end

    self:_activateEvent(
        scheduledEvent.EventConfig,
        scheduledEvent.RuntimeKey,
        scheduledEvent.EndsAt,
        scheduledEvent.Source,
        scheduledEvent.StartedAt
    )
end

function SpecialEventService:Init(dependencies)
    if type(dependencies) == "table" then
        self:_bindRemoteEvents(dependencies.RemoteEventService)
    else
        self:_bindRemoteEvents(dependencies)
    end

    if self._scheduleThread then
        return
    end

    self:_ensureEventConfigs()
    self:_ensureScheduleState()
    self:_schedulerStep()

    self._scheduleThread = task.spawn(function()
        local checkIntervalSeconds = getPositiveIntegerOrDefault(self:_getConfig().SchedulerCheckIntervalSeconds, 1)
        while true do
            self:_schedulerStep()
            task.wait(checkIntervalSeconds)
        end
    end)
end

function SpecialEventService:OnPlayerReady(player)
    self:_syncActiveEventStateToPlayer(player)
end

function SpecialEventService:OnPlayerRemoving(player)
    if not player then
        return
    end
end

function SpecialEventService:TriggerManualEventById(eventId)
    local eventConfig = self:_getEventConfigById(eventId)
    if not eventConfig then
        return false, "InvalidEventId"
    end

    self:_removeActiveEventsByEventId(eventConfig.Id, true)

    self._manualSerial += 1
    local now = os.time()
    local runtimeKey = string.format("Manual_%d_%d_%d", eventConfig.Id, now, self._manualSerial)
    local activeEvent = self:_activateEvent(
        eventConfig,
        runtimeKey,
        now + eventConfig.DurationSeconds,
        "GM",
        now
    )
    return activeEvent ~= nil, nil, activeEvent
end

function SpecialEventService:GetForcedWorldSpawnMutationRarityName()
    local activeEvent = self:_getPrimaryActiveEvent()
    if type(activeEvent) ~= "table" then
        return nil
    end

    local eventConfig = activeEvent.EventConfig
    if type(eventConfig) ~= "table" then
        return nil
    end

    local rarityName = normalizeMutationRarityName(eventConfig.MutationRarityName)
    if rarityName == "" then
        return nil
    end

    return rarityName
end

return SpecialEventService
