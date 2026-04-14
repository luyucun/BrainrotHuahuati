--[[
脚本名字: IndexController
脚本文件: IndexController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/IndexController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer
local SECRET_QUALITY_STROKE_COLOR = Color3.fromRGB(255, 255, 255)
local MANAGED_GRADIENT_ATTRIBUTE = "IndexGradientManaged"
local UI_CLICK_SOUND_TEMPLATE_FOLDER_NAME = "UI"
local UI_CLICK_SOUND_TEMPLATE_NAME = "Click Sound"
local UI_CLICK_SOUND_ASSET_ID = "rbxassetid://139421450430380"
local UI_CLICK_SOUND_FALLBACK_NAME = "_UiClickSoundFallback"
local BUTTON_CLICK_SOUND_DISABLED_ATTRIBUTE = "DisableUiClickSound"

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
        "[IndexController] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local GameConfig = requireSharedModule("GameConfig")
local BrainrotConfig = requireSharedModule("BrainrotConfig")
local BrainrotDisplayConfig = requireSharedModule("BrainrotDisplayConfig")
local RemoteNames = requireSharedModule("RemoteNames")

local function ensureUiScale(guiObject)
    if not (guiObject and guiObject:IsA("GuiObject")) then
        return nil
    end

    local uiScale = guiObject:FindFirstChildOfClass("UIScale")
    if uiScale then
        return uiScale
    end

    uiScale = Instance.new("UIScale")
    uiScale.Scale = 1
    uiScale.Parent = guiObject
    return uiScale
end

local function disconnectAll(connectionList)
    for _, connection in ipairs(connectionList) do
        connection:Disconnect()
    end
    table.clear(connectionList)
end

local function resolveSoundTemplate(soundFolderName, soundName)
    local soundFolder = SoundService:FindFirstChild(soundFolderName)
    local soundTemplate = soundFolder and (soundFolder:FindFirstChild(soundName) or soundFolder:FindFirstChild(soundName, true)) or nil
    if soundTemplate and soundTemplate:IsA("Sound") then
        return soundTemplate
    end

    return nil
end

local function splitSlashPath(pathText)
    local result = {}
    if type(pathText) ~= "string" then
        return result
    end

    for segment in string.gmatch(pathText, "[^/]+") do
        if segment ~= "" then
            table.insert(result, segment)
        end
    end

    return result
end

local function findInstanceBySegments(rootInstance, segments, startIndex)
    local current = rootInstance
    for index = startIndex, #segments do
        current = current and current:FindFirstChild(segments[index]) or nil
        if not current then
            return nil
        end
    end

    return current
end

local function modulo01(value)
    local parsed = tonumber(value) or 0
    parsed = parsed % 1
    if parsed < 0 then
        parsed = parsed + 1
    end
    return parsed
end

local function collectRotatedInteriorPositions(baseKeypoints, shift)
    local positions = {}
    for _, keypoint in ipairs(baseKeypoints) do
        local rotatedTime = modulo01((tonumber(keypoint.Time) or 0) + shift)
        if rotatedTime > 0.0001 and rotatedTime < 0.9999 then
            table.insert(positions, rotatedTime)
        end
    end

    table.sort(positions)

    local deduplicated = {}
    local lastTime = nil
    for _, timeValue in ipairs(positions) do
        if not lastTime or math.abs(timeValue - lastTime) > 0.0001 then
            table.insert(deduplicated, timeValue)
            lastTime = timeValue
        end
    end

    return deduplicated
end

local function sampleColorSequencePeriodic(baseKeypoints, timeValue)
    local count = #baseKeypoints
    if count <= 0 then
        return Color3.new(1, 1, 1)
    end

    if count == 1 then
        return baseKeypoints[1].Value
    end

    local targetTime = modulo01(timeValue)

    for index = 1, count - 1 do
        local left = baseKeypoints[index]
        local right = baseKeypoints[index + 1]
        if targetTime >= left.Time and targetTime <= right.Time then
            local span = math.max(0.000001, right.Time - left.Time)
            local alpha = math.clamp((targetTime - left.Time) / span, 0, 1)
            return left.Value:Lerp(right.Value, alpha)
        end
    end

    local last = baseKeypoints[count]
    local first = baseKeypoints[1]
    local wrappedTime = targetTime
    if wrappedTime < first.Time then
        wrappedTime = wrappedTime + 1
    end

    local span = math.max(0.000001, (first.Time + 1) - last.Time)
    local alpha = math.clamp((wrappedTime - last.Time) / span, 0, 1)
    return last.Value:Lerp(first.Value, alpha)
end

local function sampleNumberSequencePeriodic(baseKeypoints, timeValue)
    local count = #baseKeypoints
    if count <= 0 then
        return 0, 0
    end

    if count == 1 then
        return baseKeypoints[1].Value, baseKeypoints[1].Envelope
    end

    local targetTime = modulo01(timeValue)

    for index = 1, count - 1 do
        local left = baseKeypoints[index]
        local right = baseKeypoints[index + 1]
        if targetTime >= left.Time and targetTime <= right.Time then
            local span = math.max(0.000001, right.Time - left.Time)
            local alpha = math.clamp((targetTime - left.Time) / span, 0, 1)
            local value = left.Value + ((right.Value - left.Value) * alpha)
            local envelope = left.Envelope + ((right.Envelope - left.Envelope) * alpha)
            return value, envelope
        end
    end

    local last = baseKeypoints[count]
    local first = baseKeypoints[1]
    local wrappedTime = targetTime
    if wrappedTime < first.Time then
        wrappedTime = wrappedTime + 1
    end

    local span = math.max(0.000001, (first.Time + 1) - last.Time)
    local alpha = math.clamp((wrappedTime - last.Time) / span, 0, 1)
    local value = last.Value + ((first.Value - last.Value) * alpha)
    local envelope = last.Envelope + ((first.Envelope - last.Envelope) * alpha)
    return value, envelope
end

local function buildRotatedColorSequence(baseKeypoints, shift)
    local keypoints = {
        ColorSequenceKeypoint.new(0, sampleColorSequencePeriodic(baseKeypoints, -shift)),
    }

    for _, position in ipairs(collectRotatedInteriorPositions(baseKeypoints, shift)) do
        table.insert(keypoints, ColorSequenceKeypoint.new(position, sampleColorSequencePeriodic(baseKeypoints, position - shift)))
    end

    table.insert(keypoints, ColorSequenceKeypoint.new(1, sampleColorSequencePeriodic(baseKeypoints, 1 - shift)))
    return ColorSequence.new(keypoints)
end

local function buildRotatedNumberSequence(baseKeypoints, shift)
    local startValue, startEnvelope = sampleNumberSequencePeriodic(baseKeypoints, -shift)
    local keypoints = {
        NumberSequenceKeypoint.new(0, startValue, startEnvelope),
    }

    for _, position in ipairs(collectRotatedInteriorPositions(baseKeypoints, shift)) do
        local value, envelope = sampleNumberSequencePeriodic(baseKeypoints, position - shift)
        table.insert(keypoints, NumberSequenceKeypoint.new(position, value, envelope))
    end

    local endValue, endEnvelope = sampleNumberSequencePeriodic(baseKeypoints, 1 - shift)
    table.insert(keypoints, NumberSequenceKeypoint.new(1, endValue, endEnvelope))
    return NumberSequence.new(keypoints)
end

local function resolveAnimatedGradientProfile(pathKey, gradientPath)
    local key = tostring(pathKey or "")
    if key == "Quality:6" then
        return "MythicQualityGradient"
    end
    if key == "Quality:7" then
        return "SecretQualityGradient"
    end
    if key == "Quality:8" then
        return "GodQualityGradient"
    end
    if key == "Quality:9" then
        return "OGQualityGradient"
    end
    if key == "Rarity:4" then
        return "LavaRarityGradient"
    end
    if key == "Rarity:6" then
        return "HackerRarityGradient"
    end
    if key == "Rarity:7" then
        return "RainbowRarityGradient"
    end

    if type(gradientPath) ~= "string" then
        return nil
    end

    local lowerPath = string.lower(gradientPath)
    if string.find(lowerPath, "startergui/gradients/animation/quality/mythic", 1, true) then
        return "MythicQualityGradient"
    end
    if string.find(lowerPath, "startergui/gradients/animation/quality/secret", 1, true) then
        return "SecretQualityGradient"
    end
    if string.find(lowerPath, "startergui/gradients/animation/quality/god", 1, true) then
        return "GodQualityGradient"
    end
    if string.find(lowerPath, "startergui/gradients/animation/quality/og", 1, true) then
        return "OGQualityGradient"
    end
    if string.find(lowerPath, "startergui/gradients/animation/rarity/lava", 1, true) then
        return "LavaRarityGradient"
    end
    if string.find(lowerPath, "startergui/gradients/animation/rarity/hacker", 1, true) then
        return "HackerRarityGradient"
    end
    if string.find(lowerPath, "startergui/gradients/animation/rarity/rainbow", 1, true) then
        return "RainbowRarityGradient"
    end

    return nil
end

local function resolveAnimatedGradientConfig(profileName)
    local configRoot = GameConfig.BRAINROT or {}
    local prefix = tostring(profileName or "")
    if prefix == "" then
        return nil
    end

    return {
        Enabled = configRoot[prefix .. "AnimationEnabled"] ~= false,
        OffsetRange = math.max(0.05, tonumber(configRoot[prefix .. "OffsetRange"]) or 1),
        OneWayDuration = math.max(0.2, tonumber(configRoot[prefix .. "OneWayDuration"]) or 2.4),
        UpdateInterval = math.max(1 / 120, tonumber(configRoot[prefix .. "UpdateInterval"]) or (1 / 30)),
    }
end

local function normalizeGradientPathList(gradientPathOrList)
    local result = {}
    if type(gradientPathOrList) == "string" then
        if gradientPathOrList ~= "" then
            table.insert(result, gradientPathOrList)
        end
        return result
    end

    if type(gradientPathOrList) ~= "table" then
        return result
    end

    for _, value in ipairs(gradientPathOrList) do
        if type(value) == "string" and value ~= "" then
            table.insert(result, value)
        end
    end

    return result
end

local function resolveQualityDisplayInfo(qualityId)
    local parsedId = math.floor(tonumber(qualityId) or 0)
    local displayEntry = type(BrainrotDisplayConfig.Quality) == "table" and BrainrotDisplayConfig.Quality[parsedId] or nil
    local displayName = (type(displayEntry) == "table" and tostring(displayEntry.Name or "")) or ""
    if displayName == "" then
        displayName = BrainrotConfig.QualityNames[parsedId] or "Unknown"
    end

    local gradientPathOrList = nil
    if type(displayEntry) == "table" then
        if type(displayEntry.GradientPaths) == "table" then
            gradientPathOrList = displayEntry.GradientPaths
        else
            gradientPathOrList = displayEntry.GradientPath
        end
    end

    return displayName, gradientPathOrList
end

local function resolveRarityDisplayInfo(rarityId)
    local parsedId = math.floor(tonumber(rarityId) or 0)
    local displayEntry = type(BrainrotDisplayConfig.Rarity) == "table" and BrainrotDisplayConfig.Rarity[parsedId] or nil
    local displayName = (type(displayEntry) == "table" and tostring(displayEntry.Name or "")) or ""
    if displayName == "" then
        displayName = BrainrotConfig.RarityNames[parsedId] or "Unknown"
    end

    local gradientPathOrList = nil
    if type(displayEntry) == "table" then
        if type(displayEntry.GradientPaths) == "table" then
            gradientPathOrList = displayEntry.GradientPaths
        else
            gradientPathOrList = displayEntry.GradientPath
        end
    end

    return displayName, gradientPathOrList
end

local function buildRarityBuckets()
    local entriesByRarity = {}
    for _, brainrotDefinition in ipairs(BrainrotConfig.Entries) do
        local rarityId = math.floor(tonumber(brainrotDefinition.Rarity) or 0)
        if rarityId > 0 then
            if type(entriesByRarity[rarityId]) ~= "table" then
                entriesByRarity[rarityId] = {}
            end
            table.insert(entriesByRarity[rarityId], brainrotDefinition)
        end
    end

    local rarityOrder = {}
    local maxRarityId = 0
    for rarityId in pairs(entriesByRarity) do
        if rarityId > maxRarityId then
            maxRarityId = rarityId
        end
    end

    for rarityId = 1, maxRarityId do
        if entriesByRarity[rarityId] then
            table.insert(rarityOrder, rarityId)
        end
    end

    return rarityOrder, entriesByRarity
end

local IndexController = {}
IndexController.__index = IndexController

function IndexController.new(modalController)
    local rarityOrder, entriesByRarity = buildRarityBuckets()

    local self = setmetatable({}, IndexController)
    self._modalController = modalController
    self._brainrotStateSyncEvent = nil
    self._didWarnByKey = {}
    self._uiConnections = {}
    self._persistentConnections = {}
    self._tabButtonConnections = {}
    self._playerGuiAddedConnection = nil
    self._playerGuiRemovingConnection = nil
    self._characterAddedConnection = nil
    self._rebindQueued = false
    self._started = false
    self._mainGui = nil
    self._leftSection = nil
    self._leftIndexRoot = nil
    self._indexRoot = nil
    self._tabScrollingFrame = nil
    self._tabTemplate = nil
    self._entryScrollingFrame = nil
    self._entryTemplate = nil
    self._discoveredLabel = nil
    self._progressLabel = nil
    self._closeButton = nil
    self._openButton = nil
    self._selectedRarityId = rarityOrder[1]
    self._rarityOrder = rarityOrder
    self._entriesByRarity = entriesByRarity
    self._discoverableCount = #BrainrotConfig.Entries
    self._canvasRefreshSerialByFrame = setmetatable({}, { __mode = "k" })
    self._buttonClickConnectionsByButton = setmetatable({}, { __mode = "k" })
    self._uiClickSoundTemplate = nil
    self._didWarnMissingUiClickSound = false
    self._state = {
        unlockedBrainrotIdMap = {},
        discoveredCount = 0,
        discoverableCount = #BrainrotConfig.Entries,
    }
    return self
end

function IndexController:_warnOnce(key, message)
    if self._didWarnByKey[key] then
        return
    end

    self._didWarnByKey[key] = true
    warn(message)
end

function IndexController:_getUiClickSoundTemplate()
    if self._uiClickSoundTemplate and self._uiClickSoundTemplate.Parent then
        return self._uiClickSoundTemplate
    end

    local soundTemplate = resolveSoundTemplate(UI_CLICK_SOUND_TEMPLATE_FOLDER_NAME, UI_CLICK_SOUND_TEMPLATE_NAME)
    if soundTemplate then
        self._uiClickSoundTemplate = soundTemplate
        return soundTemplate
    end

    if not self._didWarnMissingUiClickSound then
        warn(string.format(
            "[IndexController] 找不到 SoundService/%s/%s，使用回退音频资源。",
            UI_CLICK_SOUND_TEMPLATE_FOLDER_NAME,
            UI_CLICK_SOUND_TEMPLATE_NAME
        ))
        self._didWarnMissingUiClickSound = true
    end

    local fallbackSound = SoundService:FindFirstChild(UI_CLICK_SOUND_FALLBACK_NAME, true)
    if fallbackSound and fallbackSound:IsA("Sound") then
        self._uiClickSoundTemplate = fallbackSound
        return fallbackSound
    end

    local soundFolder = SoundService:FindFirstChild(UI_CLICK_SOUND_TEMPLATE_FOLDER_NAME)
    fallbackSound = Instance.new("Sound")
    fallbackSound.Name = UI_CLICK_SOUND_FALLBACK_NAME
    fallbackSound.SoundId = UI_CLICK_SOUND_ASSET_ID
    fallbackSound.Volume = 1
    fallbackSound.Parent = soundFolder or SoundService
    self._uiClickSoundTemplate = fallbackSound
    return fallbackSound
end

function IndexController:_playUiClickSound()
    local template = self:_getUiClickSoundTemplate()
    if not template then
        return
    end

    local soundToPlay = template:Clone()
    soundToPlay.Looped = false
    soundToPlay.Parent = template.Parent or SoundService
    if soundToPlay.SoundId == "" then
        soundToPlay.SoundId = UI_CLICK_SOUND_ASSET_ID
    end
    soundToPlay:Play()

    task.delay(math.max(4, (tonumber(soundToPlay.TimeLength) or 0) + 1), function()
        if soundToPlay and soundToPlay.Parent then
            soundToPlay:Destroy()
        end
    end)
end

function IndexController:_bindButtonClickSound(button)
    if not (button and button:IsA("GuiButton")) then
        return
    end

    if self._buttonClickConnectionsByButton[button] then
        return
    end

    self._buttonClickConnectionsByButton[button] = button.Activated:Connect(function()
        if button:GetAttribute(BUTTON_CLICK_SOUND_DISABLED_ATTRIBUTE) == true then
            return
        end

        self:_playUiClickSound()
    end)
end

function IndexController:_bindExistingButtonClickSounds(root)
    if not root then
        return
    end

    if root:IsA("GuiButton") then
        self:_bindButtonClickSound(root)
    end

    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant:IsA("GuiButton") then
            self:_bindButtonClickSound(descendant)
        end
    end
end

function IndexController:_getPlayerGui()
    return localPlayer:FindFirstChild("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
end

function IndexController:_getMainGui()
    local playerGui = self:_getPlayerGui()
    if not playerGui then
        return nil
    end

    local mainGui = playerGui:FindFirstChild("Main")
    if mainGui then
        return mainGui
    end

    return playerGui:FindFirstChild("Main", true)
end

function IndexController:_findDescendantByNames(root, names)
    if not root then
        return nil
    end

    for _, name in ipairs(names) do
        local directChild = root:FindFirstChild(name)
        if directChild then
            return directChild
        end
    end

    for _, name in ipairs(names) do
        local nestedChild = root:FindFirstChild(name, true)
        if nestedChild then
            return nestedChild
        end
    end

    return nil
end

function IndexController:_resolveInteractiveNode(node)
    if not node then
        return nil
    end

    if node:IsA("GuiButton") then
        return node
    end

    local textButton = node:FindFirstChild("TextButton")
    if textButton and textButton:IsA("GuiButton") then
        return textButton
    end

    local imageButton = node:FindFirstChild("ImageButton")
    if imageButton and imageButton:IsA("GuiButton") then
        return imageButton
    end

    return node:FindFirstChildWhichIsA("GuiButton", true)
end

function IndexController:_findIndexRoot(mainGui, leftIndexRoot)
    if not mainGui then
        return nil
    end

    local directIndex = mainGui:FindFirstChild("Index")
    if directIndex and directIndex ~= leftIndexRoot then
        return directIndex
    end

    for _, descendant in ipairs(mainGui:GetDescendants()) do
        if descendant.Name == "Index" and descendant ~= leftIndexRoot then
            if not (self._leftSection and descendant:IsDescendantOf(self._leftSection)) then
                return descendant
            end
        end
    end

    return nil
end

function IndexController:_findGradientSource(pathText)
    local segments = splitSlashPath(pathText)
    if #segments <= 0 then
        return nil
    end

    if segments[1] == "StarterGui" then
        local playerGui = self:_getPlayerGui()
        local inPlayerGui = findInstanceBySegments(playerGui, segments, 2)
        if inPlayerGui then
            return inPlayerGui
        end
        return findInstanceBySegments(StarterGui, segments, 2)
    end

    if segments[1] == "ReplicatedStorage" then
        return findInstanceBySegments(ReplicatedStorage, segments, 2)
    end

    local root = game:FindFirstChild(segments[1])
    return findInstanceBySegments(root, segments, 2)
end

function IndexController:_markManagedDisplayNode(node)
    if not node then
        return
    end

    node:SetAttribute(MANAGED_GRADIENT_ATTRIBUTE, true)
    for _, descendant in ipairs(node:GetDescendants()) do
        descendant:SetAttribute(MANAGED_GRADIENT_ATTRIBUTE, true)
    end
end

function IndexController:_clearManagedDisplayNodes(parentNode)
    if not parentNode then
        return
    end

    for _, child in ipairs(parentNode:GetChildren()) do
        if child:GetAttribute(MANAGED_GRADIENT_ATTRIBUTE) == true then
            child:Destroy()
        end
    end
end

function IndexController:_removeDefaultCommonGradients(parentNode)
    if not parentNode then
        return
    end

    for _, descendant in ipairs(parentNode:GetDescendants()) do
        if (descendant:IsA("UIGradient") or descendant:IsA("UIStroke"))
            and descendant.Name == "Common"
            and descendant:GetAttribute(MANAGED_GRADIENT_ATTRIBUTE) ~= true
        then
            descendant:Destroy()
        end
    end

    for _, child in ipairs(parentNode:GetChildren()) do
        if (child:IsA("UIGradient") or child:IsA("UIStroke"))
            and child.Name == "Common"
            and child:GetAttribute(MANAGED_GRADIENT_ATTRIBUTE) ~= true
        then
            child:Destroy()
        end
    end
end

function IndexController:_tryStartGradientAnimation(node, gradientPath, pathKey)
    if not (node and node:IsA("UIGradient")) then
        return
    end

    local profileName = resolveAnimatedGradientProfile(pathKey, gradientPath)
    if not profileName then
        return
    end

    local animationConfig = resolveAnimatedGradientConfig(profileName)
    if not animationConfig or animationConfig.Enabled == false then
        return
    end

    if node:GetAttribute("IndexGradientAnimated") == true then
        return
    end
    node:SetAttribute("IndexGradientAnimated", true)

    local baseColorKeypoints = node.Color.Keypoints
    if type(baseColorKeypoints) ~= "table" or #baseColorKeypoints <= 0 then
        return
    end

    local baseTransparencyKeypoints = node.Transparency.Keypoints
    local cycleScale = animationConfig.OffsetRange
    local cycleDuration = animationConfig.OneWayDuration
    local updateInterval = animationConfig.UpdateInterval

    task.spawn(function()
        local elapsed = 0
        local elapsedSinceUpdate = 0

        while node and node.Parent do
            local delta = task.wait()
            elapsed += delta
            elapsedSinceUpdate += delta

            if elapsedSinceUpdate >= updateInterval then
                elapsedSinceUpdate = 0
                local shift = modulo01((elapsed / cycleDuration) * cycleScale)

                local okColor, rotatedColor = pcall(function()
                    return buildRotatedColorSequence(baseColorKeypoints, shift)
                end)
                if okColor and rotatedColor then
                    node.Color = rotatedColor
                end

                if type(baseTransparencyKeypoints) == "table" and #baseTransparencyKeypoints > 0 then
                    local okTransparency, rotatedTransparency = pcall(function()
                        return buildRotatedNumberSequence(baseTransparencyKeypoints, shift)
                    end)
                    if okTransparency and rotatedTransparency then
                        node.Transparency = rotatedTransparency
                    end
                end
            end
        end
    end)
end

function IndexController:_findDisplayTargetStroke(label)
    if not (label and label:IsA("TextLabel")) then
        return nil
    end

    local directStroke = label:FindFirstChildWhichIsA("UIStroke")
    if directStroke and directStroke:GetAttribute(MANAGED_GRADIENT_ATTRIBUTE) ~= true then
        return directStroke
    end

    for _, descendant in ipairs(label:GetDescendants()) do
        if descendant:IsA("UIStroke") and descendant:GetAttribute(MANAGED_GRADIENT_ATTRIBUTE) ~= true then
            return descendant
        end
    end

    return nil
end

function IndexController:_applyQualityStrokeColorRule(qualityLabel, qualityId)
    if not (qualityLabel and qualityLabel:IsA("TextLabel")) then
        return
    end

    local isSecretQuality = math.floor(tonumber(qualityId) or 0) == 7
    for _, stroke in ipairs(qualityLabel:GetChildren()) do
        if stroke:IsA("UIStroke") and stroke:GetAttribute(MANAGED_GRADIENT_ATTRIBUTE) ~= true then
            local defaultColor = stroke:GetAttribute("IndexDefaultStrokeColor")
            if typeof(defaultColor) ~= "Color3" then
                stroke:SetAttribute("IndexDefaultStrokeColor", stroke.Color)
                defaultColor = stroke.Color
            end

            if isSecretQuality then
                stroke.Color = SECRET_QUALITY_STROKE_COLOR
            elseif typeof(defaultColor) == "Color3" then
                stroke.Color = defaultColor
            end
        end
    end
end

function IndexController:_applyGradientToNode(targetNode, gradientPath, pathKey, allowAnimation, warnKey)
    if not targetNode then
        return false
    end

    local sourceNode = self:_findGradientSource(gradientPath)
    if not sourceNode then
        self:_warnOnce(warnKey, string.format("[IndexController] 渐变节点缺失: %s（路径=%s）", tostring(warnKey), tostring(gradientPath)))
        return false
    end

    local gradientNodes = {}
    if sourceNode:IsA("UIGradient") or sourceNode:IsA("UIStroke") then
        table.insert(gradientNodes, sourceNode)
    else
        for _, descendant in ipairs(sourceNode:GetDescendants()) do
            if descendant:IsA("UIGradient") or descendant:IsA("UIStroke") then
                table.insert(gradientNodes, descendant)
            end
        end
    end

    if #gradientNodes <= 0 then
        self:_warnOnce(warnKey, string.format("[IndexController] 渐变节点为空: %s（路径=%s）", tostring(warnKey), tostring(gradientPath)))
        return false
    end

    for _, gradientNode in ipairs(gradientNodes) do
        local clonedNode = gradientNode:Clone()
        self:_markManagedDisplayNode(clonedNode)
        clonedNode.Parent = targetNode
        if allowAnimation == true then
            self:_tryStartGradientAnimation(clonedNode, gradientPath, pathKey)
        end
    end

    return true
end

function IndexController:_applyDisplayGradient(targetNode, gradientPathOrList, pathKey, allowAnimation)
    if not targetNode then
        return
    end

    self:_clearManagedDisplayNodes(targetNode)
    self:_removeDefaultCommonGradients(targetNode)

    if targetNode:IsA("TextLabel") then
        for _, descendant in ipairs(targetNode:GetDescendants()) do
            if descendant:IsA("UIStroke") and descendant:GetAttribute(MANAGED_GRADIENT_ATTRIBUTE) ~= true then
                self:_clearManagedDisplayNodes(descendant)
            end
        end
    end

    local gradientPathList = normalizeGradientPathList(gradientPathOrList)
    if #gradientPathList <= 0 then
        return
    end

    local baseWarnKey = tostring(pathKey or "Unknown")
    local isSecretQualityText = targetNode:IsA("TextLabel") and baseWarnKey == "Quality:7"

    if isSecretQualityText and #gradientPathList >= 2 then
        local strokeTarget = self:_findDisplayTargetStroke(targetNode)
        if strokeTarget then
            self:_applyGradientToNode(strokeTarget, gradientPathList[1], pathKey, allowAnimation, baseWarnKey .. ":Stroke")
        else
            self:_warnOnce(baseWarnKey .. ":StrokeTarget", "[IndexController] Secret 品质缺少可挂载的 UIStroke。")
        end

        self:_applyGradientToNode(targetNode, gradientPathList[2], pathKey, allowAnimation, baseWarnKey .. ":Text")
        for pathIndex = 3, #gradientPathList do
            self:_applyGradientToNode(targetNode, gradientPathList[pathIndex], pathKey, allowAnimation, string.format("%s:%d", baseWarnKey, pathIndex))
        end
        return
    end

    for pathIndex, gradientPath in ipairs(gradientPathList) do
        self:_applyGradientToNode(targetNode, gradientPath, pathKey, allowAnimation, string.format("%s:%d", baseWarnKey, pathIndex))
    end
end

function IndexController:_bindButtonFx(interactiveNode, options, connectionBucket)
    if not (interactiveNode and interactiveNode:IsA("GuiButton")) then
        return
    end

    local disableClickSound = type(options) == "table" and options.DisableClickSound == true
    if disableClickSound then
        interactiveNode:SetAttribute(BUTTON_CLICK_SOUND_DISABLED_ATTRIBUTE, true)
    elseif interactiveNode:GetAttribute(BUTTON_CLICK_SOUND_DISABLED_ATTRIBUTE) ~= nil then
        interactiveNode:SetAttribute(BUTTON_CLICK_SOUND_DISABLED_ATTRIBUTE, nil)
    end

    local scaleTarget = (type(options) == "table" and options.ScaleTarget) or interactiveNode
    local rotationTarget = (type(options) == "table" and options.RotationTarget) or nil
    local hoverScale = (type(options) == "table" and tonumber(options.HoverScale)) or 1.06
    local pressScale = (type(options) == "table" and tonumber(options.PressScale)) or 0.92
    local hoverRotation = (type(options) == "table" and tonumber(options.HoverRotation)) or 0
    local uiScale = ensureUiScale(scaleTarget)
    if not uiScale then
        return
    end

    local baseScale = uiScale.Scale
    local baseRotation = rotationTarget and rotationTarget.Rotation or 0
    local state = {
        isHovered = false,
        isPressed = false,
        scaleTween = nil,
        rotationTween = nil,
    }

    local function cancelTween(tweenKey)
        local tween = state[tweenKey]
        if tween then
            tween:Cancel()
            state[tweenKey] = nil
        end
    end

    local function playTween(instance, tweenInfo, goal, tweenKey)
        cancelTween(tweenKey)
        local tween = TweenService:Create(instance, tweenInfo, goal)
        state[tweenKey] = tween
        tween.Completed:Connect(function()
            if state[tweenKey] == tween then
                state[tweenKey] = nil
            end
        end)
        tween:Play()
    end

    local function applyVisualState()
        local targetScale = baseScale
        local targetRotation = baseRotation
        local tweenInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

        if state.isPressed then
            targetScale = baseScale * pressScale
            targetRotation = baseRotation + hoverRotation
            tweenInfo = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        elseif state.isHovered then
            targetScale = baseScale * hoverScale
            targetRotation = baseRotation + hoverRotation
            tweenInfo = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        end

        playTween(uiScale, tweenInfo, { Scale = targetScale }, "scaleTween")
        if rotationTarget then
            playTween(rotationTarget, tweenInfo, { Rotation = targetRotation }, "rotationTween")
        end
    end

    table.insert(connectionBucket, interactiveNode.MouseEnter:Connect(function()
        state.isHovered = true
        applyVisualState()
    end))
    table.insert(connectionBucket, interactiveNode.MouseLeave:Connect(function()
        state.isHovered = false
        state.isPressed = false
        applyVisualState()
    end))
    table.insert(connectionBucket, interactiveNode.InputBegan:Connect(function(inputObject)
        local inputType = inputObject.UserInputType
        if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch then
            state.isPressed = true
            if inputType == Enum.UserInputType.Touch then
                state.isHovered = true
            end
            applyVisualState()
        end
    end))
    table.insert(connectionBucket, interactiveNode.InputEnded:Connect(function(inputObject)
        local inputType = inputObject.UserInputType
        if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch then
            state.isPressed = false
            if inputType == Enum.UserInputType.Touch then
                state.isHovered = false
            end
            applyVisualState()
        end
    end))
end

function IndexController:_clearUiBindings()
    disconnectAll(self._uiConnections)
    disconnectAll(self._tabButtonConnections)
end

function IndexController:_bindMainUi()
    local mainGui = self:_getMainGui()
    if not mainGui then
        self:_warnOnce("MissingMain", "[IndexController] 找不到 Main UI，图鉴系统暂不可用。")
        self:_clearUiBindings()
        return false
    end

    self._mainGui = mainGui
    self._leftSection = self:_findDescendantByNames(mainGui, { "Left" })
    self._leftIndexRoot = self._leftSection and self:_findDescendantByNames(self._leftSection, { "Index" }) or nil
    self._openButton = self:_resolveInteractiveNode(self._leftIndexRoot)
    self._indexRoot = self:_findIndexRoot(mainGui, self._leftIndexRoot)

    if not self._indexRoot then
        self:_warnOnce("MissingIndexRoot", "[IndexController] 找不到 Main/Index，图鉴面板未启动。")
        self:_clearUiBindings()
        return false
    end

    local titleRoot = self:_findDescendantByNames(self._indexRoot, { "Title" })
    local tabListRoot = self:_findDescendantByNames(self._indexRoot, { "TabList" })
    local indexInfoRoot = self:_findDescendantByNames(self._indexRoot, { "Indexinfo", "IndexInfo" })

    self._closeButton = titleRoot and self:_findDescendantByNames(titleRoot, { "CloseButton" }) or nil
    self._discoveredLabel = titleRoot and self:_findDescendantByNames(titleRoot, { "Discovered" }) or nil
    self._progressLabel = titleRoot and self:_findDescendantByNames(titleRoot, { "Progress" }) or nil
    self._tabScrollingFrame = tabListRoot and self:_findDescendantByNames(tabListRoot, { "ScrollingFrame" }) or nil
    self._tabTemplate = self._tabScrollingFrame and self:_findDescendantByNames(self._tabScrollingFrame, { "Template" }) or nil
    self._entryScrollingFrame = indexInfoRoot and self:_findDescendantByNames(indexInfoRoot, { "ScrollingFrame" }) or nil
    self._entryTemplate = self._entryScrollingFrame and self:_findDescendantByNames(self._entryScrollingFrame, { "Template" }) or nil

    self:_clearUiBindings()

    if self._openButton then
        self._openButton:SetAttribute(BUTTON_CLICK_SOUND_DISABLED_ATTRIBUTE, true)
        table.insert(self._uiConnections, self._openButton.Activated:Connect(function()
            self:OpenIndex()
        end))
    else
        self:_warnOnce("MissingOpenButton", "[IndexController] 找不到 Main/Left/Index/TextButton，图鉴打开按钮未绑定。")
    end

    local closeInteractive = self:_resolveInteractiveNode(self._closeButton)
    if closeInteractive then
        table.insert(self._uiConnections, closeInteractive.Activated:Connect(function()
            self:CloseIndex()
        end))
        self:_bindButtonFx(closeInteractive, {
            ScaleTarget = self._closeButton,
            RotationTarget = self._closeButton,
            HoverScale = 1.12,
            PressScale = 0.92,
            HoverRotation = 20,
            DisableClickSound = true,
        }, self._uiConnections)
    else
        self:_warnOnce("MissingCloseButton", "[IndexController] 找不到 Main/Index/Title/CloseButton，图鉴关闭按钮未绑定。")
    end

    if not self._tabScrollingFrame or not self._tabTemplate then
        self:_warnOnce("MissingTabTemplate", "[IndexController] 找不到图鉴页签模板 Main/Index/TabList/ScrollingFrame/Template。")
    end

    if not self._entryScrollingFrame or not self._entryTemplate then
        self:_warnOnce("MissingEntryTemplate", "[IndexController] 找不到图鉴条目模板 Main/Index/Indexinfo/ScrollingFrame/Template。")
    end

    self:_stabilizeScrollingLayout(self._tabScrollingFrame)
    self:_stabilizeScrollingLayout(self._entryScrollingFrame)

    self:_renderAll()
    return true
end

function IndexController:_queueRebind()
    if self._rebindQueued then
        return
    end

    self._rebindQueued = true
    task.defer(function()
        self._rebindQueued = false
        self:_bindMainUi()
    end)
end

function IndexController:_scheduleRetryBind()
    task.spawn(function()
        local deadline = os.clock() + 12
        repeat
            if self:_bindMainUi() then
                return
            end
            task.wait(1)
        until os.clock() >= deadline
    end)
end

function IndexController:_getHiddenNodesForModal()
    local hiddenNodes = {}
    if not self._mainGui then
        return hiddenNodes
    end

    for _, name in ipairs({ "Left", "Top", "Cash", "TopRightGui", "Backpack" }) do
        local node = self:_findDescendantByNames(self._mainGui, { name })
        if node and node ~= self._indexRoot then
            table.insert(hiddenNodes, node)
        end
    end

    return hiddenNodes
end

function IndexController:_getDiscoveredCountFromMap(unlockedMap)
    local discoveredCount = 0
    for _, brainrotDefinition in ipairs(BrainrotConfig.Entries) do
        local brainrotId = math.floor(tonumber(brainrotDefinition.Id) or 0)
        if brainrotId > 0 and unlockedMap[tostring(brainrotId)] == true then
            discoveredCount += 1
        end
    end
    return discoveredCount
end

function IndexController:_applyStatePayload(payload)
    local unlockedMap = {}
    local unlockedIds = type(payload) == "table" and payload.unlockedBrainrotIds or nil
    if type(unlockedIds) == "table" then
        for _, brainrotId in ipairs(unlockedIds) do
            local parsedId = math.floor(tonumber(brainrotId) or 0)
            if parsedId > 0 then
                unlockedMap[tostring(parsedId)] = true
            end
        end
    end

    if next(unlockedMap) == nil and type(payload) == "table" and type(payload.inventory) == "table" then
        for _, inventoryItem in ipairs(payload.inventory) do
            local brainrotId = math.floor(tonumber(inventoryItem.brainrotId) or 0)
            if brainrotId > 0 then
                unlockedMap[tostring(brainrotId)] = true
            end
        end
    end

    if next(unlockedMap) == nil and type(payload) == "table" and type(payload.placed) == "table" then
        for _, placedItem in ipairs(payload.placed) do
            local brainrotId = math.floor(tonumber(placedItem.brainrotId) or 0)
            if brainrotId > 0 then
                unlockedMap[tostring(brainrotId)] = true
            end
        end
    end

    local discoveredCount = type(payload) == "table" and math.floor(tonumber(payload.discoveredCount) or -1) or -1
    if discoveredCount < 0 then
        discoveredCount = self:_getDiscoveredCountFromMap(unlockedMap)
    end

    local discoverableCount = type(payload) == "table" and math.floor(tonumber(payload.discoverableCount) or self._discoverableCount) or self._discoverableCount
    if discoverableCount <= 0 then
        discoverableCount = self._discoverableCount
    end

    self._state.unlockedBrainrotIdMap = unlockedMap
    self._state.discoveredCount = math.max(0, discoveredCount)
    self._state.discoverableCount = math.max(0, discoverableCount)
    self:_renderAll()
end

function IndexController:_ensureSelectedRarity()
    if self._selectedRarityId and self._entriesByRarity[self._selectedRarityId] then
        return
    end

    self._selectedRarityId = self._rarityOrder[1]
end

function IndexController:_updateProgressLabels()
    local discoveredCount = math.max(0, tonumber(self._state.discoveredCount) or 0)
    local discoverableCount = math.max(0, tonumber(self._state.discoverableCount) or self._discoverableCount)
    local progressPercent = 0
    if discoverableCount > 0 and discoveredCount > 0 then
        progressPercent = math.clamp(math.ceil((discoveredCount / discoverableCount) * 100), 0, 100)
    end

    if self._discoveredLabel and self._discoveredLabel:IsA("TextLabel") then
        self._discoveredLabel.Text = string.format("%d/%d Discovered", discoveredCount, discoverableCount)
    end

    if self._progressLabel and self._progressLabel:IsA("TextLabel") then
        self._progressLabel.Text = string.format("%d%%Complete", progressPercent)
    end
end

function IndexController:_stabilizeScrollingLayout(scrollingFrame)
    if not scrollingFrame then
        return nil
    end

    local layout = scrollingFrame:FindFirstChildWhichIsA("UIGridLayout")
        or scrollingFrame:FindFirstChildWhichIsA("UIListLayout")
        or scrollingFrame:FindFirstChildWhichIsA("UIPageLayout")
    if not layout then
        return nil
    end

    if layout:IsA("UIGridLayout") then
        layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
        layout.VerticalAlignment = Enum.VerticalAlignment.Top
        layout.StartCorner = Enum.StartCorner.TopLeft
        layout.SortOrder = Enum.SortOrder.LayoutOrder
    elseif layout:IsA("UIListLayout") then
        layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
        layout.VerticalAlignment = Enum.VerticalAlignment.Top
        layout.SortOrder = Enum.SortOrder.LayoutOrder
    end

    return layout
end

local function udimToPixels(udimValue, axisSize)
    if typeof(udimValue) ~= "UDim" then
        return 0
    end

    return math.max(0, math.floor((udimValue.Scale * axisSize) + udimValue.Offset + 0.5))
end

function IndexController:_applyCanvasSizeNow(scrollingFrame)
    if not scrollingFrame then
        return
    end

    if not (scrollingFrame and scrollingFrame.Parent) then
        return
    end

    local layout = self:_stabilizeScrollingLayout(scrollingFrame)
    if not layout then
        return
    end

    local contentSize = layout.AbsoluteContentSize
    local absoluteSize = scrollingFrame.AbsoluteSize
    local paddingNode = scrollingFrame:FindFirstChildWhichIsA("UIPadding")
    local horizontalPadding = 0
    local verticalPadding = 0
    if paddingNode then
        horizontalPadding = udimToPixels(paddingNode.PaddingLeft, absoluteSize.X)
            + udimToPixels(paddingNode.PaddingRight, absoluteSize.X)
        verticalPadding = udimToPixels(paddingNode.PaddingTop, absoluteSize.Y)
            + udimToPixels(paddingNode.PaddingBottom, absoluteSize.Y)
    end

    local bottomSafeInset = 18
    scrollingFrame.CanvasSize = UDim2.new(
        0,
        contentSize.X + horizontalPadding,
        0,
        contentSize.Y + verticalPadding + bottomSafeInset
    )
end

function IndexController:_updateCanvasSize(scrollingFrame)
    self:_applyCanvasSizeNow(scrollingFrame)
end

function IndexController:_scheduleCanvasRefresh(scrollingFrame, delaySeconds)
    if not scrollingFrame then
        return
    end

    local refreshDelay = math.max(0, tonumber(delaySeconds) or 0)
    local refreshSerial = (tonumber(self._canvasRefreshSerialByFrame[scrollingFrame]) or 0) + 1
    self._canvasRefreshSerialByFrame[scrollingFrame] = refreshSerial

    task.delay(refreshDelay, function()
        if self._canvasRefreshSerialByFrame[scrollingFrame] ~= refreshSerial then
            return
        end

        self:_applyCanvasSizeNow(scrollingFrame)
    end)
end

function IndexController:_clearGeneratedItems(scrollingFrame, template)
    if not scrollingFrame then
        return
    end

    for _, child in ipairs(scrollingFrame:GetChildren()) do
        if child ~= template and child:GetAttribute("IndexGeneratedItem") == true then
            child:Destroy()
        end
    end
end

function IndexController:_renderTabs()
    if not (self._tabScrollingFrame and self._tabTemplate) then
        return
    end

    self:_clearGeneratedItems(self._tabScrollingFrame, self._tabTemplate)
    disconnectAll(self._tabButtonConnections)

    for rarityOrderIndex, rarityId in ipairs(self._rarityOrder) do
        local tabClone = self._tabTemplate:Clone()
        tabClone.Name = string.format("RarityTab_%d", rarityId)
        tabClone.LayoutOrder = rarityOrderIndex
        tabClone.Visible = true
        tabClone:SetAttribute("IndexGeneratedItem", true)

        local nameLabel = self:_findDescendantByNames(tabClone, { "Name" })
        local bgNode = self:_findDescendantByNames(tabClone, { "Bg" })
        local interactiveNode = self:_resolveInteractiveNode(tabClone)
        local rarityName, rarityGradientPath = resolveRarityDisplayInfo(rarityId)

        if nameLabel and nameLabel:IsA("TextLabel") then
            nameLabel.Text = rarityName
        end

        if bgNode then
            self:_applyDisplayGradient(bgNode, rarityGradientPath, "Rarity:" .. tostring(rarityId), true)
        end

        if interactiveNode then
            self:_bindButtonFx(interactiveNode, {
                ScaleTarget = tabClone,
                HoverScale = 1.05,
                PressScale = 0.93,
                HoverRotation = 0,
            }, self._tabButtonConnections)
            table.insert(self._tabButtonConnections, interactiveNode.Activated:Connect(function()
                if self._selectedRarityId == rarityId then
                    return
                end

                self._selectedRarityId = rarityId
                if self._entryScrollingFrame then
                    self._entryScrollingFrame.CanvasPosition = Vector2.new(0, 0)
                end
                self:_renderTabs()
                self:_renderEntries()
            end))
        end

        if rarityId == self._selectedRarityId then
            local selectedScale = ensureUiScale(tabClone)
            if selectedScale then
                selectedScale.Scale = 1.04
            end
        end

        tabClone.Parent = self._tabScrollingFrame
    end

    self:_updateCanvasSize(self._tabScrollingFrame)
end

function IndexController:_renderEntries()
    if not (self._entryScrollingFrame and self._entryTemplate) then
        return
    end

    self:_clearGeneratedItems(self._entryScrollingFrame, self._entryTemplate)

    self:_stabilizeScrollingLayout(self._entryScrollingFrame)

    local entries = self._entriesByRarity[self._selectedRarityId] or {}
    for entryIndex, brainrotDefinition in ipairs(entries) do
        local itemClone = self._entryTemplate:Clone()
        itemClone.Name = string.format("Brainrot_%s", tostring(brainrotDefinition.Id))
        itemClone.LayoutOrder = entryIndex
        itemClone.Visible = true
        itemClone:SetAttribute("IndexGeneratedItem", true)

        local iconNode = self:_findDescendantByNames(itemClone, { "Icon" })
        local nameLabel = self:_findDescendantByNames(itemClone, { "Name" })
        local qualityLabel = self:_findDescendantByNames(itemClone, { "Quality" })
        local bgNode = self:_findDescendantByNames(itemClone, { "Bg" })

        local brainrotId = math.floor(tonumber(brainrotDefinition.Id) or 0)
        local qualityId = math.floor(tonumber(brainrotDefinition.Quality) or 0)
        local qualityName, qualityGradientPath = resolveQualityDisplayInfo(qualityId)
        local isUnlocked = self._state.unlockedBrainrotIdMap[tostring(brainrotId)] == true

        if iconNode and (iconNode:IsA("ImageLabel") or iconNode:IsA("ImageButton")) then
            iconNode.Image = tostring(brainrotDefinition.Icon or "")
            iconNode.ImageColor3 = isUnlocked and Color3.new(1, 1, 1) or Color3.new(0, 0, 0)
            iconNode.ImageTransparency = 0
        end

        if nameLabel and nameLabel:IsA("TextLabel") then
            nameLabel.Text = tostring(brainrotDefinition.Name or "Unknown")
        end

        if qualityLabel and qualityLabel:IsA("TextLabel") then
            qualityLabel.Text = qualityName
            self:_applyQualityStrokeColorRule(qualityLabel, qualityId)
            self:_applyDisplayGradient(qualityLabel, qualityGradientPath, "Quality:" .. tostring(qualityId), true)
        end

        if bgNode then
            self:_clearManagedDisplayNodes(bgNode)
        end

        itemClone.Parent = self._entryScrollingFrame
    end

    self:_updateCanvasSize(self._entryScrollingFrame)

    local isIndexOpen = false
    if self._modalController then
        isIndexOpen = self._modalController:IsModalOpen("Index")
    elseif self._indexRoot and self._indexRoot:IsA("GuiObject") then
        isIndexOpen = self._indexRoot.Visible == true
    end

    if isIndexOpen then
        self:_scheduleCanvasRefresh(self._entryScrollingFrame, 0.05)
    end
end

function IndexController:_renderAll()
    if not self._indexRoot then
        return
    end

    self:_ensureSelectedRarity()
    self:_updateProgressLabels()
    self:_renderTabs()
    self:_renderEntries()
end

function IndexController:OpenIndex()
    if not self._indexRoot then
        return
    end

    self:_renderAll()
    if self._modalController then
        self._modalController:OpenModal("Index", self._indexRoot, {
            HiddenNodes = self:_getHiddenNodesForModal(),
        })

        local uiConfig = GameConfig.UI or {}
        local refreshDelay = math.max(
            0.05,
            (tonumber(uiConfig.ModalOpenOvershootDuration) or 0.18)
                + (tonumber(uiConfig.ModalOpenSettleDuration) or 0.12)
                + 0.05
        )
        self:_scheduleCanvasRefresh(self._entryScrollingFrame, refreshDelay)
    elseif self._indexRoot:IsA("GuiObject") then
        self._indexRoot.Visible = true
        self:_scheduleCanvasRefresh(self._entryScrollingFrame, 0.05)
    end
end

function IndexController:CloseIndex()
    if not self._indexRoot then
        return
    end

    if self._modalController then
        self._modalController:CloseModal("Index")
    elseif self._indexRoot:IsA("GuiObject") then
        self._indexRoot.Visible = false
    end
end

function IndexController:Start()
    if self._started then
        return
    end
    self._started = true

    local eventsRoot = ReplicatedStorage:WaitForChild(RemoteNames.RootFolder)
    local brainrotEvents = eventsRoot:WaitForChild(RemoteNames.BrainrotEventsFolder)
    self._brainrotStateSyncEvent = brainrotEvents:FindFirstChild(RemoteNames.Brainrot.BrainrotStateSync)
    if not (self._brainrotStateSyncEvent and self._brainrotStateSyncEvent:IsA("RemoteEvent")) then
        self._brainrotStateSyncEvent = brainrotEvents:WaitForChild(RemoteNames.Brainrot.BrainrotStateSync, 10)
    end

    if self._brainrotStateSyncEvent and self._brainrotStateSyncEvent:IsA("RemoteEvent") then
        table.insert(self._persistentConnections, self._brainrotStateSyncEvent.OnClientEvent:Connect(function(payload)
            self:_applyStatePayload(payload)
        end))
    else
        self:_warnOnce("MissingBrainrotStateSync", "[IndexController] 找不到 BrainrotStateSync，图鉴状态不会自动刷新。")
    end

    self:_scheduleRetryBind()

    local playerGui = self:_getPlayerGui()
    if playerGui then
        self._playerGuiAddedConnection = playerGui.ChildAdded:Connect(function(child)
            if child.Name == "Main" then
                self:_queueRebind()
            end
        end)
        self._playerGuiRemovingConnection = playerGui.ChildRemoved:Connect(function(child)
            if child.Name == "Main" then
                self:_queueRebind()
            end
        end)
    end

    self._characterAddedConnection = localPlayer.CharacterAdded:Connect(function()
        task.defer(function()
            self:_queueRebind()
        end)
    end)
end

return IndexController

