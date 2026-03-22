--[[
脚本名字: NpcIdleAnimationController
脚本文件: NpcIdleAnimationController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/NpcIdleAnimationController
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

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
        "[NpcIdleAnimationController] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local BrainrotConfig = requireSharedModule("BrainrotConfig")
local GameConfig = requireSharedModule("GameConfig")

local NpcIdleAnimationController = {}
NpcIdleAnimationController.__index = NpcIdleAnimationController

local function disconnectConnection(connection)
    if connection then
        connection:Disconnect()
    end
end

local function normalizeAnimationId(animationId)
    local text = tostring(animationId or "")
    if text == "" then
        return nil
    end

    if string.find(text, "rbxassetid://", 1, true) then
        return text
    end

    return "rbxassetid://" .. text
end

local function buildBrainrotDefinitionsByName()
    local definitions = {}
    local entries = type(BrainrotConfig) == "table" and BrainrotConfig.Entries or nil
    if type(entries) ~= "table" then
        return definitions
    end

    for _, entry in ipairs(entries) do
        if type(entry) == "table" then
            local name = tostring(entry.Name or "")
            if name ~= "" and definitions[name] == nil then
                definitions[name] = entry
            end
        end
    end
    return definitions
end

local BRAINROT_DEFINITIONS_BY_NAME = buildBrainrotDefinitionsByName()
local FALLBACK_TARGET_MODEL_NAMES = { "Madudung", "Garamararam" }

function NpcIdleAnimationController.new()
    local self = setmetatable({}, NpcIdleAnimationController)
    self._started = false
    self._persistentConnections = {}
    self._targetStates = {}
    self._didWarnByKey = {}
    return self
end

function NpcIdleAnimationController:_warnOnce(key, message)
    if self._didWarnByKey[key] then
        return
    end

    self._didWarnByKey[key] = true
    warn(message)
end

function NpcIdleAnimationController:_getTargetModelNames()
    local configuredNames = (GameConfig.BRAINROT or {}).AmbientNpcIdleModelNames
    if type(configuredNames) == "table" and #configuredNames > 0 then
        return configuredNames
    end

    return FALLBACK_TARGET_MODEL_NAMES
end

function NpcIdleAnimationController:_getState(modelName)
    local key = tostring(modelName or "")
    local state = self._targetStates[key]
    if state then
        return state
    end

    state = {
        model = nil,
        animator = nil,
        track = nil,
        stoppedConnection = nil,
    }
    self._targetStates[key] = state
    return state
end

function NpcIdleAnimationController:_stopState(state)
    if not state then
        return
    end

    disconnectConnection(state.stoppedConnection)
    state.stoppedConnection = nil

    if state.track then
        pcall(function()
            state.track:Stop(0)
        end)
    end

    state.track = nil
    state.model = nil
    state.animator = nil
end

function NpcIdleAnimationController:_resolveBrainrotDefinition(modelName)
    return BRAINROT_DEFINITIONS_BY_NAME[tostring(modelName or "")]
end

function NpcIdleAnimationController:_resolveNpcModel(modelName)
    local targetName = tostring(modelName or "")
    if targetName == "" then
        return nil
    end

    local directModel = Workspace:FindFirstChild(targetName)
    if directModel and directModel:IsA("Model") then
        return directModel
    end

    local nestedModel = Workspace:FindFirstChild(targetName, true)
    if nestedModel and nestedModel:IsA("Model") then
        return nestedModel
    end

    return nil
end

function NpcIdleAnimationController:_resolveAnimator(model)
    if not (model and model:IsA("Model")) then
        return nil
    end

    local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
    if humanoid then
        local humanoidAnimator = humanoid:FindFirstChildOfClass("Animator")
        if not humanoidAnimator then
            humanoidAnimator = Instance.new("Animator")
            humanoidAnimator.Parent = humanoid
        end
        return humanoidAnimator
    end

    local animationController = model:FindFirstChildWhichIsA("AnimationController", true)
    if not animationController then
        animationController = Instance.new("AnimationController")
        animationController.Name = "NpcIdleAnimationController"
        animationController.Parent = model
    end

    local animator = animationController:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = animationController
    end

    return animator
end

function NpcIdleAnimationController:_ensureIdleTrack(modelName)
    local state = self:_getState(modelName)
    local definition = self:_resolveBrainrotDefinition(modelName)
    if type(definition) ~= "table" then
        self:_warnOnce(
            string.format("MissingDefinition:%s", tostring(modelName)),
            string.format("[NpcIdleAnimationController] 找不到 %s 对应的 BrainrotConfig 配置，待机动画未播放。", tostring(modelName))
        )
        self:_stopState(state)
        return false
    end

    local animationId = normalizeAnimationId(definition.IdleAnimationId)
    if not animationId then
        self:_warnOnce(
            string.format("MissingAnimation:%s", tostring(modelName)),
            string.format("[NpcIdleAnimationController] %s 缺少 IdleAnimationId，待机动画未播放。", tostring(modelName))
        )
        self:_stopState(state)
        return false
    end

    local model = self:_resolveNpcModel(modelName)
    if not model then
        self:_stopState(state)
        return false
    end

    local animator = self:_resolveAnimator(model)
    if not animator then
        self:_warnOnce(
            string.format("MissingAnimator:%s", tostring(modelName)),
            string.format("[NpcIdleAnimationController] 无法为 %s 找到 Animator，待机动画未播放。", tostring(modelName))
        )
        self:_stopState(state)
        return false
    end

    local hasPlayingTrack = false
    if state.model == model and state.animator == animator and state.track then
        local ok, isPlaying = pcall(function()
            return state.track.IsPlaying
        end)
        hasPlayingTrack = ok and isPlaying == true
    end

    if hasPlayingTrack then
        return true
    end

    self:_stopState(state)

    local animation = Instance.new("Animation")
    animation.AnimationId = animationId

    local ok, loadedTrack = pcall(function()
        return animator:LoadAnimation(animation)
    end)

    animation:Destroy()

    if not ok or not loadedTrack then
        self:_warnOnce(
            string.format("LoadFailed:%s", tostring(modelName)),
            string.format("[NpcIdleAnimationController] %s 的待机动画加载失败：%s", tostring(modelName), tostring(loadedTrack))
        )
        return false
    end

    loadedTrack.Looped = true
    pcall(function()
        loadedTrack.Priority = Enum.AnimationPriority.Idle
    end)
    loadedTrack:Play(0)

    state.model = model
    state.animator = animator
    state.track = loadedTrack
    state.stoppedConnection = loadedTrack.Stopped:Connect(function()
        if not self._started then
            return
        end

        task.defer(function()
            if not self._started then
                return
            end

            self:_ensureIdleTrack(modelName)
        end)
    end)

    return true
end

function NpcIdleAnimationController:Start()
    if self._started then
        return
    end
    self._started = true

    table.insert(self._persistentConnections, Workspace.DescendantAdded:Connect(function(descendant)
        if not descendant:IsA("Model") then
            return
        end

        local descendantName = descendant.Name
        for _, targetName in ipairs(self:_getTargetModelNames()) do
            if descendantName == targetName then
                task.defer(function()
                    self:_ensureIdleTrack(targetName)
                end)
                return
            end
        end
    end))

    task.spawn(function()
        while self._started do
            for _, modelName in ipairs(self:_getTargetModelNames()) do
                self:_ensureIdleTrack(modelName)
            end
            task.wait(1)
        end
    end)

    for _, modelName in ipairs(self:_getTargetModelNames()) do
        self:_ensureIdleTrack(modelName)
    end
end

return NpcIdleAnimationController