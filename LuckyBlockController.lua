--[[
脚本名字: LuckyBlockController
脚本文件: LuckyBlockController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/LuckyBlockController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")

local localPlayer = Players.LocalPlayer

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
        "[LuckyBlockController] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local RemoteNames = requireSharedModule("RemoteNames")
local LuckyBlockConfig = requireSharedModule("LuckyBlockConfig")
local BrainrotConfig = requireSharedModule("BrainrotConfig")

local LuckyBlockController = {}
LuckyBlockController.__index = LuckyBlockController

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

local function findPathFromRoot(root, pathText)
    if not root then
        return nil
    end

    local segments = splitSlashPath(pathText)
    if #segments <= 0 then
        return nil
    end

    local current = root
    local startIndex = 1
    if segments[1] == root.Name then
        startIndex = 2
    end

    for index = startIndex, #segments do
        current = current and current:FindFirstChild(segments[index]) or nil
        if not current then
            return nil
        end
    end

    return current
end

local function findReplicatedStoragePath(pathText)
    return findPathFromRoot(ReplicatedStorage, pathText)
end

local function getInputScreenPosition(inputObject)
    if inputObject and typeof(inputObject.Position) == "Vector3" then
        return Vector2.new(inputObject.Position.X, inputObject.Position.Y)
    end

    local mouseLocation = UserInputService:GetMouseLocation()
    return Vector2.new(mouseLocation.X, mouseLocation.Y)
end

local function getPrimaryBasePart(instance)
    if not instance then
        return nil
    end

    if instance:IsA("BasePart") then
        return instance
    end

    if instance:IsA("Model") then
        return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
    end

    return nil
end

local function moveInstanceToCFrame(instance, targetCFrame)
    if not (instance and targetCFrame) then
        return false
    end

    if instance:IsA("Model") then
        local primaryPart = getPrimaryBasePart(instance)
        if not primaryPart then
            return false
        end

        if instance.PrimaryPart ~= primaryPart then
            instance.PrimaryPart = primaryPart
        end
        instance:PivotTo(targetCFrame)
        return true
    end

    if instance:IsA("BasePart") then
        instance.CFrame = targetCFrame
        return true
    end

    return false
end

local function destroyInstance(instance)
    if instance and instance.Parent then
        instance:Destroy()
    end
end

local function lerp(fromValue, toValue, alpha)
    return fromValue + (toValue - fromValue) * math.clamp(alpha, 0, 1)
end

function LuckyBlockController.new()
    local self = setmetatable({}, LuckyBlockController)
    self._requestOpenEvent = nil
    self._feedbackEvent = nil
    self._persistentConnections = {}
    self._activeRequest = nil
    self._fxRoot = nil
    self._boundActionName = "LuckyBlockUseAction"
    self._rewardNotificationsShown = {}
    return self
end

function LuckyBlockController:_getPlayerGui()
    return localPlayer:FindFirstChildOfClass("PlayerGui") or localPlayer:FindFirstChild("PlayerGui")
end

function LuckyBlockController:_getEquippedLuckyBlockTool()
    local character = localPlayer.Character
    if not character then
        return nil
    end

    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("Tool") and child:GetAttribute(LuckyBlockConfig.ToolAttributeName) == true then
            return child
        end
    end

    return nil
end

function LuckyBlockController:_isPointerOverInteractiveGui(screenPosition)
    local playerGui = self:_getPlayerGui()
    if not playerGui then
        return false
    end

    local guiObjects = playerGui:GetGuiObjectsAtPosition(screenPosition.X, screenPosition.Y)
    for _, guiObject in ipairs(guiObjects) do
        if guiObject.Visible ~= false and (
            guiObject:IsA("GuiButton")
            or guiObject:IsA("TextBox")
            or guiObject:IsA("ScrollingFrame")
        ) then
            return true
        end
    end

    return false
end

function LuckyBlockController:_setToolHiddenLocally(tool, isHidden)
    if not tool then
        return
    end

    local hiddenAlpha = isHidden == true and 1 or 0
    for _, descendant in ipairs(tool:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.LocalTransparencyModifier = hiddenAlpha
        end
    end
end

function LuckyBlockController:_getFxRoot()
    if self._fxRoot and self._fxRoot.Parent then
        return self._fxRoot
    end

    local folder = Instance.new("Folder")
    folder.Name = "LuckyBlockClientFx"
    folder.Parent = Workspace
    self._fxRoot = folder
    return folder
end

function LuckyBlockController:_getHomelandPart()
    local homelandPart = findPathFromRoot(Workspace, tostring(LuckyBlockConfig.HomelandPath or ""))
    if homelandPart and homelandPart:IsA("BasePart") then
        return homelandPart
    end
    return nil
end

function LuckyBlockController:_resolveBrainrotTemplate(brainrotId)
    local brainrotDefinition = BrainrotConfig.ById[math.max(0, math.floor(tonumber(brainrotId) or 0))]
    if type(brainrotDefinition) ~= "table" then
        return nil, nil
    end

    local modelRoot = findReplicatedStoragePath(tostring(LuckyBlockConfig.BrainrotModelRootPath or "ReplicatedStorage/Model"))
    if not modelRoot then
        return nil, brainrotDefinition
    end

    local template = findPathFromRoot(modelRoot, tostring(brainrotDefinition.ModelPath or ""))
    return template, brainrotDefinition
end

function LuckyBlockController:_extractVisualSource(template)
    if not template then
        return nil
    end

    if template:IsA("Tool") then
        local preferredName = tostring(LuckyBlockConfig.BrainrotModelVisualName or "BrainrotModel")
        local preferredChild = template:FindFirstChild(preferredName)
        if preferredChild and (preferredChild:IsA("Model") or preferredChild:IsA("BasePart")) then
            return preferredChild
        end

        local firstModel = template:FindFirstChildWhichIsA("Model")
        if firstModel then
            return firstModel
        end

        return template:FindFirstChildWhichIsA("BasePart")
    end

    if template:IsA("Model") or template:IsA("BasePart") then
        return template
    end

    return nil
end

function LuckyBlockController:_sanitizeDisplayInstance(instance)
    if not instance then
        return {}
    end

    local anchorPart = nil
    if instance:IsA("Model") then
        anchorPart = instance.PrimaryPart
            or instance:FindFirstChild("HumanoidRootPart", true)
            or instance:FindFirstChild("RootPart", true)
            or instance:FindFirstChildWhichIsA("BasePart", true)
        if anchorPart then
            instance.PrimaryPart = anchorPart
        end
    elseif instance:IsA("BasePart") then
        anchorPart = instance
    end

    local parts = {}
    if instance:IsA("BasePart") then
        instance.Anchored = true
        instance.CanCollide = false
        instance.CanTouch = false
        instance.CanQuery = false
        table.insert(parts, instance)
    end

    for _, descendant in ipairs(instance:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.Anchored = (descendant == anchorPart)
            descendant.CanCollide = false
            descendant.CanTouch = false
            descendant.CanQuery = false
            table.insert(parts, descendant)
        elseif descendant:IsA("Motor6D") then
        elseif descendant:IsA("JointInstance") or descendant:IsA("Constraint") then
            descendant:Destroy()
        elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
            descendant.Disabled = true
        elseif descendant:IsA("ProximityPrompt")
            or descendant:IsA("BillboardGui")
            or descendant:IsA("ClickDetector")
            or descendant:IsA("TouchTransmitter")
        then
            descendant:Destroy()
        elseif descendant:IsA("Humanoid") then
            descendant.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        elseif descendant:IsA("Animator") or descendant:IsA("AnimationController") then
            descendant:Destroy()
        end
    end

    return parts
end

function LuckyBlockController:_applySilhouetteStyle(instance, _parts)
    if not instance then
        return
    end

    for _, descendant in ipairs(instance:GetDescendants()) do
        if descendant:IsA("SurfaceAppearance")
            or descendant:IsA("Decal")
            or descendant:IsA("Texture")
        then
            descendant:Destroy()
        end
    end

    local highlight = Instance.new("Highlight")
    highlight.Name = "SilhouetteHighlight"
    highlight.FillColor = Color3.new(0, 0, 0)
    highlight.FillTransparency = 0
    highlight.OutlineColor = Color3.new(0, 0, 0)
    highlight.OutlineTransparency = 1
    highlight.DepthMode = Enum.HighlightDepthMode.Occluded
    highlight.Parent = instance
end

local function getHorizontalLookVector(cf)
    if not cf then
        return Vector3.new(0, 0, -1)
    end

    local look = cf.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    if flat.Magnitude > 0.001 then
        return flat.Unit
    end

    local right = cf.RightVector
    local flatRight = Vector3.new(right.X, 0, right.Z)
    if flatRight.Magnitude > 0.001 then
        return flatRight.Unit
    end

    return Vector3.new(0, 0, -1)
end

local function makeYawOnlyCFrame(cf, position)
    local look = getHorizontalLookVector(cf)
    local pos = position or cf.Position
    return CFrame.lookAt(pos, pos + look, Vector3.new(0, 1, 0))
end

function LuckyBlockController:_getInstanceFootOffset(instance)
    if not instance then
        return nil
    end

    if instance:IsA("Model") then
        local currentPivot = instance:GetPivot()
        local boundingBoxCFrame, size = instance:GetBoundingBox()
        local bottomY = boundingBoxCFrame.Position.Y - size.Y * 0.5
        return currentPivot.Position.Y - bottomY
    end

    if instance:IsA("BasePart") then
        return instance.Size.Y * 0.5
    end

    return nil
end

function LuckyBlockController:_placeInstanceOnGround(instance, worldPosition, yawDegrees, extraHeight, cachedFootOffset)
    if not (instance and instance.Parent and typeof(worldPosition) == "Vector3") then
        return false
    end

    if instance:IsA("Model") then
        local currentPivot = instance:GetPivot()
        local footOffset = cachedFootOffset
        if type(footOffset) ~= "number" then
            footOffset = self:_getInstanceFootOffset(instance)
        end
        if type(footOffset) ~= "number" then
            return false
        end
        local targetPosition = worldPosition + Vector3.new(0, footOffset + (extraHeight or 0), 0)
        local targetCFrame = CFrame.new(targetPosition) * CFrame.Angles(0, math.rad(yawDegrees or 0), 0)
        local sourceYaw = makeYawOnlyCFrame(currentPivot, currentPivot.Position)
        local delta = targetCFrame * sourceYaw:Inverse()
        instance:PivotTo(delta * currentPivot)
        return true
    end

    if instance:IsA("BasePart") then
        local halfHeight = instance.Size.Y * 0.5
        local targetPosition = worldPosition + Vector3.new(0, halfHeight + (extraHeight or 0), 0)
        instance.CFrame = CFrame.new(targetPosition) * CFrame.Angles(0, math.rad(yawDegrees or 0), 0)
        return true
    end

    return false
end

function LuckyBlockController:_buildBlockVisualClone(tool)
    if not tool then
        return nil
    end

    local visualClone = nil
    local visualName = tostring(LuckyBlockConfig.RuntimeVisualName or "VisualModel")
    local toolVisual = tool:FindFirstChild(visualName)
    if toolVisual and (toolVisual:IsA("Model") or toolVisual:IsA("BasePart")) then
        visualClone = toolVisual:Clone()
    end

    if not visualClone then
        local modelPath = tostring(tool:GetAttribute(LuckyBlockConfig.ToolModelPathAttributeName) or "")
        local template = findReplicatedStoragePath(modelPath)
        if template and (template:IsA("Model") or template:IsA("BasePart")) then
            visualClone = template:Clone()
        end
    end

    return visualClone
end

function LuckyBlockController:_buildBrainrotPreviewClone(brainrotId, useSilhouette)
    local template = self:_resolveBrainrotTemplate(brainrotId)
    local visualSource = self:_extractVisualSource(template)
    if not visualSource then
        return nil, nil, nil
    end

    local previewClone = visualSource:Clone()
    local previewParts = self:_sanitizeDisplayInstance(previewClone)
    local previewFootOffset = self:_getInstanceFootOffset(previewClone)
    if useSilhouette == true then
        self:_applySilhouetteStyle(previewClone, previewParts)
    end

    return previewClone, previewParts, previewFootOffset
end

function LuckyBlockController:_createRequestFlash(parent)
    local flash = Instance.new("Part")
    flash.Name = "LuckyBlockFlash"
    flash.Shape = Enum.PartType.Ball
    flash.Material = Enum.Material.Neon
    flash.Color = Color3.fromRGB(255, 244, 120)
    flash.Transparency = 1
    flash.Anchored = true
    flash.CanCollide = false
    flash.CanTouch = false
    flash.CanQuery = false
    flash.Size = Vector3.new(0.2, 0.2, 0.2)
    flash.Parent = parent
    return flash
end

function LuckyBlockController:_pulseFlash(activeRequest, color, size, duration)
    if not (activeRequest and activeRequest.flashPart and activeRequest.flashPart.Parent) then
        return
    end

    local flashPart = activeRequest.flashPart
    flashPart.Color = color or flashPart.Color
    flashPart.Size = Vector3.new(0.2, 0.2, 0.2)
    flashPart.Transparency = 0.1
    flashPart.CFrame = CFrame.new(activeRequest.worldPosition + Vector3.new(0, 2.8, 0))

    TweenService:Create(
        flashPart,
        TweenInfo.new(duration or 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {
            Size = Vector3.new(size or 2.2, size or 2.2, size or 2.2),
            Transparency = 1,
        }
    ):Play()
end

function LuckyBlockController:_emitBurstCubes(activeRequest, color, burstCount)
    if not (activeRequest and activeRequest.folder and activeRequest.folder.Parent) then
        return
    end

    local count = math.max(1, math.floor(tonumber(burstCount) or tonumber(LuckyBlockConfig.BurstCubeCount) or 8))
    local lifeTime = math.max(0.1, tonumber(LuckyBlockConfig.BurstCubeLifetimeSeconds) or 0.45)
    local origin = activeRequest.worldPosition + Vector3.new(0, 1.6, 0)

    for _ = 1, count do
        local cube = Instance.new("Part")
        cube.Name = "LuckyBlockBurstCube"
        cube.Material = Enum.Material.Neon
        cube.Color = color or Color3.fromRGB(255, 245, 120)
        cube.Size = Vector3.new(0.28, 0.28, 0.28)
        cube.Anchored = true
        cube.CanCollide = false
        cube.CanTouch = false
        cube.CanQuery = false
        cube.CFrame = CFrame.new(origin)
        cube.Parent = activeRequest.folder

        local targetOffset = Vector3.new(
            math.random(-20, 20) * 0.12,
            math.random(8, 20) * 0.1,
            math.random(-20, 20) * 0.12
        )
        TweenService:Create(
            cube,
            TweenInfo.new(lifeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {
                CFrame = CFrame.new(origin + targetOffset),
                Transparency = 1,
                Size = Vector3.new(0.08, 0.08, 0.08),
            }
        ):Play()
        task.delay(lifeTime + 0.05, function()
            destroyInstance(cube)
        end)
    end
end

function LuckyBlockController:_setPreviewModel(activeRequest, brainrotId, useSilhouette)
    if not (activeRequest and activeRequest.folder and activeRequest.folder.Parent) then
        return false
    end

    destroyInstance(activeRequest.previewRoot)
    activeRequest.previewRoot = nil
    activeRequest.previewParts = nil

    local previewClone, previewParts, previewFootOffset = self:_buildBrainrotPreviewClone(brainrotId, useSilhouette)
    if not previewClone then
        return false
    end

    previewClone.Name = useSilhouette == true and "LuckyBlockPreviewShadow" or "LuckyBlockPreviewFinal"
    previewClone.Parent = activeRequest.folder
    activeRequest.previewRoot = previewClone
    activeRequest.previewParts = previewParts
    activeRequest.previewFootOffset = previewFootOffset
    activeRequest.previewBrainrotId = brainrotId
    activeRequest.previewYawDegrees = math.random(0, 359)
    return true
end

function LuckyBlockController:_updateDisplayTransforms(activeRequest)
    if not activeRequest then
        return
    end

    local elapsed = os.clock() - activeRequest.startedAt
    if activeRequest.blockRoot and activeRequest.blockRoot.Parent then
        self:_placeInstanceOnGround(
            activeRequest.blockRoot,
            activeRequest.worldPosition,
            activeRequest.blockYawDegrees + elapsed * (tonumber(LuckyBlockConfig.BlockSpinDegreesPerSecond) or 28),
            math.sin(elapsed * (tonumber(LuckyBlockConfig.BlockFloatSpeed) or 3.2))
                * (tonumber(LuckyBlockConfig.BlockFloatAmplitude) or 0.12),
            activeRequest.blockFootOffset
        )
    end

    if activeRequest.previewRoot and activeRequest.previewRoot.Parent then
        local previewExtraHeight
        if activeRequest.revealPhase == "final" then
            previewExtraHeight = (tonumber(LuckyBlockConfig.PreviewHeight) or 5.4)
                + math.sin(elapsed * (tonumber(LuckyBlockConfig.PreviewFloatSpeed) or 6))
                    * (tonumber(LuckyBlockConfig.PreviewFloatAmplitude) or 0.22)
        else
            previewExtraHeight = math.sin(elapsed * (tonumber(LuckyBlockConfig.PreviewFloatSpeed) or 6))
                * (tonumber(LuckyBlockConfig.PreviewFloatAmplitude) or 0.22)
        end

        self:_placeInstanceOnGround(
            activeRequest.previewRoot,
            activeRequest.worldPosition,
            activeRequest.previewYawDegrees + elapsed * (tonumber(LuckyBlockConfig.PreviewSpinDegreesPerSecond) or 150),
            previewExtraHeight,
            activeRequest.previewFootOffset
        )
    end
end

function LuckyBlockController:_createPendingFx(tool, worldPosition)
    local blockClone = self:_buildBlockVisualClone(tool)
    if not blockClone then
        return nil
    end

    local folder = Instance.new("Folder")
    folder.Name = "LuckyBlockRequestFx"
    folder.Parent = self:_getFxRoot()

    blockClone.Name = "LuckyBlockPlaced"
    blockClone.Parent = folder
    local _blockParts = self:_sanitizeDisplayInstance(blockClone)

    local activeRequest = {
        folder = folder,
        tool = tool,
        worldPosition = worldPosition,
        blockRoot = blockClone,
        blockFootOffset = self:_getInstanceFootOffset(blockClone),
        previewRoot = nil,
        previewParts = nil,
        previewFootOffset = nil,
        flashPart = self:_createRequestFlash(folder),
        blockYawDegrees = math.random(0, 359),
        previewYawDegrees = 0,
        revealPhase = "rolling",
        startedAt = os.clock(),
        finished = false,
        requestId = "",
        acceptedPayload = nil,
        timeoutThread = nil,
        sequenceThread = nil,
        revealComplete = false,
        successPayload = nil,
    }

    self:_updateDisplayTransforms(activeRequest)
    activeRequest.renderConnection = RunService.RenderStepped:Connect(function()
        if activeRequest.finished then
            return
        end
        self:_updateDisplayTransforms(activeRequest)
    end)

    return activeRequest
end

function LuckyBlockController:_showNotification(text)
    local message = tostring(text or "")
    if message == "" then
        return
    end

    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "Lucky Block",
            Text = message,
            Duration = 2,
        })
    end)
end

function LuckyBlockController:_showRewardNotification(payload)
    local requestId = tostring(type(payload) == "table" and payload.requestId or "")
    if requestId ~= "" and self._rewardNotificationsShown[requestId] == true then
        return
    end

    local brainrotName = tostring(type(payload) == "table" and payload.brainrotName or "")
    if brainrotName ~= "" then
        self:_showNotification(string.format("You got %s", brainrotName))
    end

    if requestId ~= "" then
        self._rewardNotificationsShown[requestId] = true
    end
end

function LuckyBlockController:_clearActiveRequest(shouldRestoreTool)
    local activeRequest = self._activeRequest
    self._activeRequest = nil
    if not activeRequest then
        return
    end

    activeRequest.finished = true

    if activeRequest.renderConnection then
        activeRequest.renderConnection:Disconnect()
        activeRequest.renderConnection = nil
    end

    if activeRequest.timeoutThread then
        pcall(task.cancel, activeRequest.timeoutThread)
        activeRequest.timeoutThread = nil
    end

    if activeRequest.sequenceThread and activeRequest.sequenceThread ~= coroutine.running() then
        pcall(task.cancel, activeRequest.sequenceThread)
    end
    activeRequest.sequenceThread = nil

    if shouldRestoreTool == true and activeRequest.tool and activeRequest.tool.Parent then
        self:_setToolHiddenLocally(activeRequest.tool, false)
    end

    destroyInstance(activeRequest.folder)
end

function LuckyBlockController:_buildRouletteSequence(activeRequest)
    local acceptedPayload = activeRequest and activeRequest.acceptedPayload
    local blockId = math.max(0, math.floor(tonumber(type(acceptedPayload) == "table" and acceptedPayload.blockId) or 0))
    local blockEntry = LuckyBlockConfig.EntriesById[blockId]
    local poolEntries = LuckyBlockConfig.Pools[math.max(0, math.floor(tonumber(blockEntry and blockEntry.PoolId) or 0))]

    local candidateIds = {}
    local seenIds = {}
    if type(poolEntries) == "table" then
        for _, poolEntry in ipairs(poolEntries) do
            local candidateId = math.max(0, math.floor(tonumber(poolEntry and poolEntry.BrainrotId) or 0))
            if candidateId > 0 and BrainrotConfig.ById[candidateId] and not seenIds[candidateId] then
                seenIds[candidateId] = true
                table.insert(candidateIds, candidateId)
            end
        end
    end

    local finalBrainrotId = math.max(0, math.floor(tonumber(type(acceptedPayload) == "table" and acceptedPayload.brainrotId) or 0))
    if #candidateIds <= 0 and finalBrainrotId > 0 then
        table.insert(candidateIds, finalBrainrotId)
    end

    local rounds = math.max(1, math.floor(tonumber(LuckyBlockConfig.RouletteRounds) or 2))
    local sequence = {}
    for _ = 1, rounds do
        for _, candidateId in ipairs(candidateIds) do
            table.insert(sequence, candidateId)
        end
    end

    return sequence
end

function LuckyBlockController:_completeReveal(activeRequest)
    if self._activeRequest ~= activeRequest then
        return
    end

    if activeRequest.successPayload then
        self:_showRewardNotification(activeRequest.successPayload)
    end

    self:_clearActiveRequest(false)
end

function LuckyBlockController:_startRevealSequence(activeRequest)
    if not (activeRequest and activeRequest.acceptedPayload) then
        return
    end

    if activeRequest.sequenceThread then
        return
    end

    activeRequest.sequenceThread = task.spawn(function()
        local sequence = self:_buildRouletteSequence(activeRequest)
        local startInterval = math.max(0.02, tonumber(LuckyBlockConfig.RouletteStartIntervalSeconds) or 0.18)
        local endInterval = math.max(0.02, tonumber(LuckyBlockConfig.RouletteEndIntervalSeconds) or 0.045)
        activeRequest.revealPhase = "rolling"

        if activeRequest.blockRoot then
            destroyInstance(activeRequest.blockRoot)
            activeRequest.blockRoot = nil
            activeRequest.blockFootOffset = nil
        end

        for index, brainrotId in ipairs(sequence) do
            if self._activeRequest ~= activeRequest or activeRequest.finished then
                return
            end

            self:_setPreviewModel(activeRequest, brainrotId, true)
            self:_pulseFlash(activeRequest, Color3.fromRGB(255, 244, 120), 1.8, 0.16)
            if index == 1 or index % 2 == 0 then
                self:_emitBurstCubes(activeRequest, Color3.fromRGB(255, 244, 120), 4)
            end

            local alpha = (#sequence <= 1) and 1 or ((index - 1) / (#sequence - 1))
            task.wait(lerp(startInterval, endInterval, alpha * alpha))
        end

        if self._activeRequest ~= activeRequest or activeRequest.finished then
            return
        end

        local finalBrainrotId = math.max(0, math.floor(tonumber(activeRequest.acceptedPayload.brainrotId) or 0))
        activeRequest.revealPhase = "final"
        self:_setPreviewModel(activeRequest, finalBrainrotId, false)
        self:_pulseFlash(activeRequest, Color3.fromRGB(255, 255, 255), 3.6, 0.26)
        self:_emitBurstCubes(activeRequest, Color3.fromRGB(255, 248, 162), LuckyBlockConfig.BurstCubeCount)

        task.wait(math.max(0.1, tonumber(LuckyBlockConfig.FinalRevealHoldSeconds) or 1))
        if self._activeRequest ~= activeRequest or activeRequest.finished then
            return
        end

        activeRequest.revealComplete = true
        self:_completeReveal(activeRequest)
    end)
end

function LuckyBlockController:_handleFeedback(payload)
    local requestId = tostring(type(payload) == "table" and payload.requestId or "")
    local status = tostring(type(payload) == "table" and payload.status or "")
    local activeRequest = self._activeRequest

    if status == "Success" then
        if activeRequest and requestId ~= "" and requestId == activeRequest.requestId then
            activeRequest.successPayload = payload
            if activeRequest.revealComplete then
                self:_completeReveal(activeRequest)
            end
            return
        end

        self:_showRewardNotification(payload)
        return
    end

    if not activeRequest then
        return
    end

    if requestId == "" or requestId ~= activeRequest.requestId then
        return
    end

    if status == "Accepted" then
        activeRequest.acceptedPayload = payload
        if activeRequest.timeoutThread then
            pcall(task.cancel, activeRequest.timeoutThread)
            activeRequest.timeoutThread = nil
        end
        self:_startRevealSequence(activeRequest)
        return
    end

    if status == "GrantFailed" then
        self:_clearActiveRequest(false)
        self:_showNotification("Lucky Block reward failed and the block was returned")
        return
    end

    self:_clearActiveRequest(true)
    if status == "InvalidTarget" then
        self:_showNotification("Lucky Block can only be opened inside Homeland")
    elseif status == "NotEquipped" then
        self:_showNotification("Equip the Lucky Block first")
    elseif status == "BlockNotOwned" then
        self:_showNotification("This Lucky Block is no longer available")
    elseif status == "EmptyPool" then
        self:_showNotification("Lucky Block pool is empty")
    end
end

function LuckyBlockController:_tryOpenLuckyBlock(inputObject)
    if self._activeRequest then
        return false
    end

    local tool = self:_getEquippedLuckyBlockTool()
    if not tool then
        return false
    end

    local homelandPart = self:_getHomelandPart()
    if not homelandPart then
        return false
    end

    local camera = Workspace.CurrentCamera
    if not camera then
        return false
    end

    local screenPosition = getInputScreenPosition(inputObject)
    if self:_isPointerOverInteractiveGui(screenPosition) then
        return false
    end

    local ray = camera:ViewportPointToRay(screenPosition.X, screenPosition.Y)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Include
    raycastParams.FilterDescendantsInstances = { homelandPart }
    raycastParams.IgnoreWater = true

    local result = Workspace:Raycast(ray.Origin, ray.Direction * 1024, raycastParams)
    if not result or result.Instance ~= homelandPart then
        return false
    end

    local blockInstanceId = math.max(
        0,
        math.floor(tonumber(tool:GetAttribute(LuckyBlockConfig.ToolInstanceIdAttributeName)) or 0)
    )
    if blockInstanceId <= 0 then
        return false
    end

    local requestId = string.format("%d_%d", math.floor(os.clock() * 1000), math.random(1000, 9999))
    local activeRequest = self:_createPendingFx(tool, result.Position)
    if not activeRequest then
        return false
    end

    activeRequest.requestId = requestId
    activeRequest.tool = tool
    self._activeRequest = activeRequest
    self:_setToolHiddenLocally(tool, true)
    self:_pulseFlash(activeRequest, Color3.fromRGB(255, 244, 120), 1.4, 0.14)
    self:_emitBurstCubes(activeRequest, Color3.fromRGB(255, 244, 120), 5)

    activeRequest.timeoutThread = task.delay(
        math.max(1, tonumber(LuckyBlockConfig.OpenTimeoutSeconds) or 8),
        function()
            if self._activeRequest == activeRequest then
                self:_clearActiveRequest(true)
            end
        end
    )

    self._requestOpenEvent:FireServer({
        requestId = requestId,
        blockInstanceId = blockInstanceId,
        position = result.Position,
    })
    return true
end

function LuckyBlockController:_handleLuckyBlockAction(_actionName, inputState, inputObject)
    if inputState ~= Enum.UserInputState.Begin then
        return Enum.ContextActionResult.Pass
    end

    if UserInputService:GetFocusedTextBox() then
        return Enum.ContextActionResult.Pass
    end

    if self._activeRequest then
        return Enum.ContextActionResult.Sink
    end

    local tool = self:_getEquippedLuckyBlockTool()
    if not tool then
        return Enum.ContextActionResult.Pass
    end

    local screenPosition = getInputScreenPosition(inputObject)
    if self:_isPointerOverInteractiveGui(screenPosition) then
        return Enum.ContextActionResult.Pass
    end

    if self:_tryOpenLuckyBlock(inputObject) then
        return Enum.ContextActionResult.Sink
    end

    return Enum.ContextActionResult.Pass
end

function LuckyBlockController:Start()
    local eventsRoot = ReplicatedStorage:WaitForChild(RemoteNames.RootFolder)
    local systemEvents = eventsRoot:WaitForChild(RemoteNames.SystemEventsFolder)
    self._requestOpenEvent = systemEvents:FindFirstChild(RemoteNames.System.RequestLuckyBlockOpen)
        or systemEvents:WaitForChild(RemoteNames.System.RequestLuckyBlockOpen, 10)
    self._feedbackEvent = systemEvents:FindFirstChild(RemoteNames.System.LuckyBlockFeedback)
        or systemEvents:WaitForChild(RemoteNames.System.LuckyBlockFeedback, 10)

    if self._feedbackEvent then
        table.insert(self._persistentConnections, self._feedbackEvent.OnClientEvent:Connect(function(payload)
            self:_handleFeedback(payload)
        end))
    end

    ContextActionService:UnbindAction(self._boundActionName)
    ContextActionService:BindActionAtPriority(
        self._boundActionName,
        function(actionName, inputState, inputObject)
            return self:_handleLuckyBlockAction(actionName, inputState, inputObject)
        end,
        false,
        Enum.ContextActionPriority.High.Value,
        Enum.UserInputType.MouseButton1,
        Enum.UserInputType.Touch
    )

    table.insert(self._persistentConnections, localPlayer.CharacterAdded:Connect(function()
        self:_clearActiveRequest(false)
    end))
end

return LuckyBlockController
