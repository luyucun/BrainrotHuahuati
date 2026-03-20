--[[
脚本名字: ClaimFeedbackController
脚本文件: ClaimFeedbackController.lua
脚本类型: ModuleScript
本地路径: D:/RobloxGame/BrainrotsTemplate/ClaimFeedbackController.lua
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/ClaimFeedbackController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

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
        "[ClaimFeedbackController] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local GameConfig = requireSharedModule("GameConfig")
local RemoteNames = requireSharedModule("RemoteNames")

local randomGenerator = Random.new()

local function randomRange(minValue, maxValue)
    local minNumber = tonumber(minValue) or 0
    local maxNumber = tonumber(maxValue) or minNumber
    if maxNumber < minNumber then
        minNumber, maxNumber = maxNumber, minNumber
    end

    return randomGenerator:NextNumber(minNumber, maxNumber)
end

local function getCharacterRootPart(character)
    if not character then
        return nil
    end

    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
        return humanoidRootPart
    end

    local primaryPart = character.PrimaryPart
    if primaryPart and primaryPart:IsA("BasePart") then
        return primaryPart
    end

    local fallbackPart = character:FindFirstChildWhichIsA("BasePart")
    if fallbackPart and fallbackPart:IsA("BasePart") then
        return fallbackPart
    end

    return nil
end

local ClaimFeedbackController = {}
ClaimFeedbackController.__index = ClaimFeedbackController

function ClaimFeedbackController.new()
    local self = setmetatable({}, ClaimFeedbackController)
    self._claimCashFeedbackEvent = nil
    self._soundTemplate = nil
    self._didWarnMissingSound = false
    self._activeCoinFxParts = {}
    return self
end

function ClaimFeedbackController:_trackCoinFxPart(part)
    if not part then
        return
    end

    self._activeCoinFxParts[part] = true
end

function ClaimFeedbackController:_destroyCoinFxPart(part)
    if not part then
        return
    end

    self._activeCoinFxParts[part] = nil
    if part.Parent then
        part:Destroy()
    end
end

function ClaimFeedbackController:_getSoundTemplate()
    if self._soundTemplate and self._soundTemplate.Parent then
        return self._soundTemplate
    end

    local audioRoot = SoundService:FindFirstChild("Audio")
    local addCashSound = audioRoot and (audioRoot:FindFirstChild("ADDCash") or audioRoot:FindFirstChild("ADDCash", true)) or nil
    if addCashSound and addCashSound:IsA("Sound") then
        self._soundTemplate = addCashSound
        return addCashSound
    end

    if not self._didWarnMissingSound then
        warn("[ClaimFeedbackController] 找不到 SoundService/Audio/ADDCash，使用回退音频资源。")
        self._didWarnMissingSound = true
    end

    local fallbackSound = SoundService:FindFirstChild("_ADDCashFallback")
    if fallbackSound and fallbackSound:IsA("Sound") then
        self._soundTemplate = fallbackSound
        return fallbackSound
    end

    fallbackSound = Instance.new("Sound")
    fallbackSound.Name = "_ADDCashFallback"
    fallbackSound.SoundId = "rbxassetid://139922061047157"
    fallbackSound.Volume = 1
    fallbackSound.RollOffMaxDistance = 80
    fallbackSound.Parent = SoundService

    self._soundTemplate = fallbackSound
    return fallbackSound
end

function ClaimFeedbackController:_playAddCashSound()
    local template = self:_getSoundTemplate()
    if not template then
        return
    end

    local soundToPlay = template:Clone()
    soundToPlay.Looped = false
    soundToPlay.Parent = template.Parent or SoundService
    if soundToPlay.SoundId == "" then
        soundToPlay.SoundId = "rbxassetid://139922061047157"
    end
    soundToPlay:Play()

    task.delay(3, function()
        if soundToPlay and soundToPlay.Parent then
            soundToPlay:Destroy()
        end
    end)
end

function ClaimFeedbackController:_getCoinFxRuntimeFolder()
    local runtimeFolderName = tostring(GameConfig.BRAINROT.ClaimCoinCollectRuntimeFolderName or "ClaimCoinCollectFx")
    local runtimeFolder = workspace:FindFirstChild(runtimeFolderName)
    if runtimeFolder and runtimeFolder:IsA("Folder") then
        return runtimeFolder
    end

    runtimeFolder = Instance.new("Folder")
    runtimeFolder.Name = runtimeFolderName
    runtimeFolder.Parent = workspace
    return runtimeFolder
end

function ClaimFeedbackController:_resolveTouchSpawnPosition(payload, spawnHeight)
    local touchPosition = type(payload) == "table" and payload.touchPosition or nil
    if typeof(touchPosition) ~= "Vector3" then
        return nil
    end

    local touchUpVector = type(payload) == "table" and payload.touchUpVector or nil
    if typeof(touchUpVector) ~= "Vector3" or touchUpVector.Magnitude <= 0.001 then
        touchUpVector = Vector3.new(0, 1, 0)
    else
        touchUpVector = touchUpVector.Unit
    end

    local touchSize = type(payload) == "table" and payload.touchSize or nil
    local touchHalfHeight = (typeof(touchSize) == "Vector3") and (touchSize.Y * 0.5) or 0

    return touchPosition + touchUpVector * (touchHalfHeight + spawnHeight)
end

function ClaimFeedbackController:_playClaimCoinCollectEffect(payload)
    local config = GameConfig.BRAINROT or {}
    local iconAssetId = tostring(config.ClaimCoinCollectIconAssetId or "rbxassetid://92295649647469")

    local iconCountMin = math.max(1, math.floor(tonumber(config.ClaimCoinCollectIconCountMin) or 6))
    local iconCountMax = math.max(iconCountMin, math.floor(tonumber(config.ClaimCoinCollectIconCountMax) or 12))
    local iconCount = math.floor(tonumber(config.ClaimCoinCollectIconCount) or 8)
    iconCount = math.clamp(iconCount, iconCountMin, iconCountMax)
    if iconCount <= 0 then
        return
    end

    local spawnHeight = math.max(0.5, tonumber(config.ClaimCoinCollectSpawnHeight) or 3.2)
    local spawnPosition = self:_resolveTouchSpawnPosition(payload, spawnHeight)
    if typeof(spawnPosition) ~= "Vector3" then
        return
    end

    local popFromScale = math.max(0.1, tonumber(config.ClaimCoinCollectPopFromScale) or 0.8)
    local popDuration = math.max(0.03, tonumber(config.ClaimCoinCollectPopDuration) or 0.08)
    local baseIconSizeStuds = math.max(0.25, tonumber(config.ClaimCoinCollectIconSizeStuds) or 1.5)
    local iconSizeScaleMin = math.max(0.1, tonumber(config.ClaimCoinCollectIconSizeScaleMin) or 0.9)
    local iconSizeScaleMax = math.max(iconSizeScaleMin, tonumber(config.ClaimCoinCollectIconSizeScaleMax) or 1.1)

    local burstDuration = math.max(0.05, tonumber(config.ClaimCoinCollectBurstDuration) or 0.16)
    local burstRadiusMin = math.max(0.1, tonumber(config.ClaimCoinCollectBurstRadiusMin) or 2.5)
    local burstRadiusMax = math.max(burstRadiusMin, tonumber(config.ClaimCoinCollectBurstRadiusMax) or 4.2)
    local burstVerticalMin = tonumber(config.ClaimCoinCollectBurstVerticalOffsetMin) or -0.2
    local burstVerticalMax = tonumber(config.ClaimCoinCollectBurstVerticalOffsetMax) or 1.0
    if burstVerticalMax < burstVerticalMin then
        burstVerticalMin, burstVerticalMax = burstVerticalMax, burstVerticalMin
    end

    local attractDurationMin = math.max(0.05, tonumber(config.ClaimCoinCollectAttractDurationMin) or 0.3)
    local attractDurationMax = math.max(attractDurationMin, tonumber(config.ClaimCoinCollectAttractDurationMax) or 0.36)
    local startDelayMax = math.max(0, tonumber(config.ClaimCoinCollectStartDelayMax) or 0.03)
    local targetOffsetY = tonumber(config.ClaimCoinCollectTargetOffsetY) or 2
    local arcHeightMin = tonumber(config.ClaimCoinCollectArcHeightMin) or 0.25
    local arcHeightMax = tonumber(config.ClaimCoinCollectArcHeightMax) or 0.8
    if arcHeightMax < arcHeightMin then
        arcHeightMin, arcHeightMax = arcHeightMax, arcHeightMin
    end

    local arcHorizontalJitter = math.max(0, tonumber(config.ClaimCoinCollectArcHorizontalJitter) or 0.75)
    local destroyDistance = math.max(0.05, tonumber(config.ClaimCoinCollectDestroyDistance) or 0.8)
    local fadeOutDuration = math.max(0.01, tonumber(config.ClaimCoinCollectFadeOutDuration) or 0.05)

    local localPlayer = Players.LocalPlayer
    local effectParent = self:_getCoinFxRuntimeFolder()

    local rootPart = getCharacterRootPart(localPlayer and localPlayer.Character or nil)
    local lastTargetPosition = rootPart and rootPart.Position + Vector3.new(0, targetOffsetY, 0) or (spawnPosition + Vector3.new(0, targetOffsetY, 0))

    local function getTargetPosition()
        local currentRoot = getCharacterRootPart(localPlayer and localPlayer.Character or nil)
        if currentRoot and currentRoot.Parent then
            lastTargetPosition = currentRoot.Position + Vector3.new(0, targetOffsetY, 0)
        end
        return lastTargetPosition
    end

    for iconIndex = 1, iconCount do
        local iconPart = Instance.new("Part")
        iconPart.Name = "ClaimCoinCollectIcon"
        iconPart.Anchored = true
        iconPart.CanCollide = false
        iconPart.CanTouch = false
        iconPart.CanQuery = false
        iconPart.CastShadow = false
        iconPart.Transparency = 1
        iconPart.Size = Vector3.new(0.15, 0.15, 0.15)
        iconPart.CFrame = CFrame.new(spawnPosition)
        iconPart.Parent = effectParent
        self:_trackCoinFxPart(iconPart)

        local randomSizeScale = randomRange(iconSizeScaleMin, iconSizeScaleMax)

        local iconGui = Instance.new("BillboardGui")
        iconGui.Name = "CoinIconGui"
        iconGui.Adornee = iconPart
        iconGui.AlwaysOnTop = true
        iconGui.LightInfluence = 0
        iconGui.MaxDistance = 200
        iconGui.Size = UDim2.new(baseIconSizeStuds * randomSizeScale, 0, baseIconSizeStuds * randomSizeScale, 0)
        iconGui.Parent = iconPart

        local iconLabel = Instance.new("ImageLabel")
        iconLabel.Name = "Icon"
        iconLabel.BackgroundTransparency = 1
        iconLabel.Size = UDim2.fromScale(1, 1)
        iconLabel.Image = iconAssetId
        iconLabel.ImageTransparency = 0.15
        iconLabel.Rotation = randomRange(-10, 10)
        iconLabel.Parent = iconGui

        local iconScale = Instance.new("UIScale")
        iconScale.Scale = popFromScale
        iconScale.Parent = iconLabel

        task.spawn(function()
            local startDelay = randomRange(0, startDelayMax)
            if startDelay > 0 then
                task.wait(startDelay)
            end

            if not (iconPart and iconPart.Parent) then
                self:_destroyCoinFxPart(iconPart)
                return
            end

            local popTween = TweenService:Create(iconScale, TweenInfo.new(popDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
                Scale = 1,
            })
            local appearTween = TweenService:Create(iconLabel, TweenInfo.new(popDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                ImageTransparency = 0,
            })
            popTween:Play()
            appearTween:Play()

            local fullCircle = math.pi * 2
            local baseAngle = ((iconIndex - 1) / iconCount) * fullCircle
            local angleJitter = randomRange(-fullCircle / (iconCount * 1.5), fullCircle / (iconCount * 1.5))
            local angle = baseAngle + angleJitter
            local radius = randomRange(burstRadiusMin, burstRadiusMax)
            local verticalOffset = randomRange(burstVerticalMin, burstVerticalMax)
            local burstOffset = Vector3.new(math.cos(angle) * radius, verticalOffset, math.sin(angle) * radius)
            local scatterPosition = spawnPosition + burstOffset

            local burstTween = TweenService:Create(iconPart, TweenInfo.new(burstDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Position = scatterPosition,
            })
            burstTween:Play()
            task.wait(burstDuration)

            if not (iconPart and iconPart.Parent) then
                self:_destroyCoinFxPart(iconPart)
                return
            end

            local attractDuration = randomRange(attractDurationMin, attractDurationMax)
            local arcHeight = randomRange(arcHeightMin, arcHeightMax)
            local arcOffset = Vector3.new(
                randomRange(-arcHorizontalJitter, arcHorizontalJitter),
                arcHeight,
                randomRange(-arcHorizontalJitter, arcHorizontalJitter)
            )

            local attractStartPosition = iconPart.Position
            local elapsed = 0
            while elapsed < attractDuration do
                if not (iconPart and iconPart.Parent) then
                    self:_destroyCoinFxPart(iconPart)
                    return
                end

                local deltaTime = RunService.Heartbeat:Wait()
                elapsed = elapsed + deltaTime

                local progress = math.clamp(elapsed / attractDuration, 0, 1)
                local easedProgress = progress * progress
                local targetPosition = getTargetPosition()
                local controlPosition = ((attractStartPosition + targetPosition) * 0.5) + arcOffset

                local oneMinus = 1 - easedProgress
                local bezierPosition = (attractStartPosition * (oneMinus * oneMinus))
                    + (controlPosition * (2 * oneMinus * easedProgress))
                    + (targetPosition * (easedProgress * easedProgress))
                iconPart.Position = bezierPosition

                if (targetPosition - bezierPosition).Magnitude <= destroyDistance then
                    break
                end
            end

            if not (iconPart and iconPart.Parent) then
                self:_destroyCoinFxPart(iconPart)
                return
            end

            local fadeTween = TweenService:Create(iconLabel, TweenInfo.new(fadeOutDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                ImageTransparency = 1,
            })
            local shrinkTween = TweenService:Create(iconScale, TweenInfo.new(fadeOutDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                Scale = 0.65,
            })
            fadeTween:Play()
            shrinkTween:Play()
            task.wait(fadeOutDuration)
            self:_destroyCoinFxPart(iconPart)
        end)
    end
end

function ClaimFeedbackController:Start()
    local eventsRoot = ReplicatedStorage:WaitForChild(RemoteNames.RootFolder)
    local systemEvents = eventsRoot:WaitForChild(RemoteNames.SystemEventsFolder)

    self._claimCashFeedbackEvent = systemEvents:FindFirstChild(RemoteNames.System.ClaimCashFeedback)
    if not (self._claimCashFeedbackEvent and self._claimCashFeedbackEvent:IsA("RemoteEvent")) then
        self._claimCashFeedbackEvent = systemEvents:WaitForChild(RemoteNames.System.ClaimCashFeedback, 10)
    end

    if not (self._claimCashFeedbackEvent and self._claimCashFeedbackEvent:IsA("RemoteEvent")) then
        warn("[ClaimFeedbackController] 找不到 ClaimCashFeedback 事件，领取反馈未启动。")
        return
    end

    self._claimCashFeedbackEvent.OnClientEvent:Connect(function(payload)
        self:_playAddCashSound()
        self:_playClaimCoinCollectEffect(payload)
    end)
end

return ClaimFeedbackController
