--[[
脚本名字: BrainrotBossController
脚本文件: BrainrotBossController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/BrainrotBossController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

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
        "[BrainrotBossController] Missing shared module %s (expected in ReplicatedStorage/Shared or ReplicatedStorage root)",
        moduleName
    ))
end

local GameConfig = requireSharedModule("GameConfig")
local BrainrotConfig = requireSharedModule("BrainrotConfig")
local RemoteNames = requireSharedModule("RemoteNames")
local BOSS_RUNTIME_ATTRIBUTE = "BrainrotBossRuntime"
local BOSS_TARGET_POSITION_ATTRIBUTE = "BrainrotBossTargetPosition"
local BOSS_TARGET_LOOK_VECTOR_ATTRIBUTE = "BrainrotBossTargetLookVector"
local BOSS_STATE_ATTRIBUTE = "BrainrotBossState"
local BOSS_SERVER_UPDATED_AT_ATTRIBUTE = "BrainrotBossServerUpdatedAt"

local BrainrotBossController = {}
BrainrotBossController.__index = BrainrotBossController

local function getSharedClock()
    local ok, serverNow = pcall(function()
        return Workspace:GetServerTimeNow()
    end)
    if ok and type(serverNow) == "number" then
        return serverNow
    end

    return os.clock()
end

local function formatCountdownText(remainingSeconds)
    local safeRemaining = math.max(0, tonumber(remainingSeconds) or 0)
    return string.format("%.1fS", safeRemaining)
end

local function setGuiVisible(node, visible)
    if not node then
        return
    end

    if node:IsA("ScreenGui") then
        node.Enabled = visible
    elseif node:IsA("GuiObject") then
        node.Visible = visible
    end
end

local function collectGuiDescendantsByName(root, targetName)
    local result = {}
    if not root then
        return result
    end

    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant.Name == targetName and descendant:IsA("GuiObject") then
            table.insert(result, descendant)
        end
    end

    return result
end

local function getBossRuntimeFolderName()
    return tostring((GameConfig.BRAINROT or {}).WorldSpawnBossRuntimeFolderName or "WorldSpawnBosses")
end

local function getWorldSpawnLandFolderName()
    return tostring((GameConfig.BRAINROT or {}).WorldSpawnLandFolderName or "Land")
end

local function findDescendantByPath(root, relativePath)
    if not root or type(relativePath) ~= "string" or relativePath == "" then
        return nil
    end

    local current = root
    for segment in string.gmatch(relativePath, "[^/]+") do
        current = current and current:FindFirstChild(segment) or nil
        if not current then
            return nil
        end
    end

    return current
end

local function getHorizontalLookVector(rawLookVector, fallbackLookVector)
    local candidate = typeof(rawLookVector) == "Vector3"
        and Vector3.new(rawLookVector.X, 0, rawLookVector.Z)
        or Vector3.zero
    if candidate.Magnitude > 0.001 then
        return candidate.Unit
    end

    local fallback = typeof(fallbackLookVector) == "Vector3"
        and Vector3.new(fallbackLookVector.X, 0, fallbackLookVector.Z)
        or Vector3.new(0, 0, -1)
    if fallback.Magnitude > 0.001 then
        return fallback.Unit
    end

    return Vector3.new(0, 0, -1)
end

local function buildBossTargetCFrame(position, lookVector, fallbackLookVector)
    local targetPosition = typeof(position) == "Vector3" and position or Vector3.zero
    local horizontalLook = getHorizontalLookVector(lookVector, fallbackLookVector)
    return CFrame.lookAt(targetPosition, targetPosition + horizontalLook, Vector3.new(0, 1, 0))
end

function BrainrotBossController.new()
    local self = setmetatable({}, BrainrotBossController)
    self._bossStateSyncEvent = nil
    self._requestDropCarriedWorldBrainrotEvent = nil
    self._bossWarningEvent = nil
    self._requestQuickTeleportEvent = nil
    self._dropRoot = nil
    self._dropButton = nil
    self._homeButton = nil
    self._countdownLabel = nil
    self._homeReadyNodes = {}
    self._homeLockedNodes = {}
    self._warningRoot = nil
    self._warningText = nil
    self._dropButtonConnection = nil
    self._homeButtonConnection = nil
    self._warningAlpha = 1
    self._warningSerial = 0
    self._homeEnabled = false
    self._started = false
    self._updateInterval = math.max(0.05, tonumber((GameConfig.BRAINROT or {}).BossTickInterval) or 0.1)
    self._bossRuntimeFolderName = getBossRuntimeFolderName()
    self._bossRuntimeFolder = nil
    self._trackedBosses = {}
    self._worldSpawnLandFolderName = getWorldSpawnLandFolderName()
    self._worldSpawnLandFolder = nil
    self._worldSpawnLandParts = {}
    self._worldSpawnLandLookup = {}
    self._landBarrierEnabled = (GameConfig.BRAINROT or {}).WorldSpawnLandBarrierEnabled ~= false
    self._barrierFolderName = string.format("LocalWorldSpawnLandBarrier_%s", tostring(localPlayer.UserId or 0))
    self._airWallFolder = nil
    self._activeBarrierLand = nil
    self._activeBarrierParts = {}
    self._barrierCollisionPending = false
    self._barrierHeight = math.max(48, tonumber((GameConfig.BRAINROT or {}).WorldSpawnLandBarrierHeight) or 180)
    self._barrierThickness = math.max(2, tonumber((GameConfig.BRAINROT or {}).WorldSpawnLandBarrierThickness) or 10)
    self._barrierPadding = math.max(0, tonumber((GameConfig.BRAINROT or {}).WorldSpawnLandBarrierPadding) or 4)
    self._barrierTransparency = math.clamp(tonumber((GameConfig.BRAINROT or {}).WorldSpawnLandBarrierTransparency) or 0.7, 0, 1)
    self._barrierCollisionClearance = math.max(0.5, tonumber((GameConfig.BRAINROT or {}).WorldSpawnLandBarrierCollisionClearance) or 1.5)
    self._barrierGroundInset = math.max(0, tonumber((GameConfig.BRAINROT or {}).WorldSpawnLandBarrierGroundInset) or 2)
    self._barrierRaycastDistance = math.max(6, tonumber((GameConfig.BRAINROT or {}).WorldSpawnLandBarrierRaycastDistance) or 10)
    self._barrierStickyDistance = math.max(8, tonumber((GameConfig.BRAINROT or {}).WorldSpawnLandBarrierStickyDistance) or 24)
    self._bossVisualSmoothingEnabled = (GameConfig.BRAINROT or {}).BossClientVisualSmoothingEnabled ~= false
    self._bossInterpolationWindow = math.max(
        1 / 120,
        tonumber((GameConfig.BRAINROT or {}).BossClientVisualInterpolationWindow)
            or tonumber((GameConfig.BRAINROT or {}).BossTickInterval)
            or 0.1
    )
    self._bossSnapDistance = math.max(1, tonumber((GameConfig.BRAINROT or {}).BossClientVisualSnapDistance) or 8)
    self._bossRenderConnection = nil
    self._state = {
        visible = false,
        carriedCount = 0,
        homeUnlockAt = 0,
        isChased = false,
    }
    self._homeDefaultBackgroundColor = nil
    self._homeDefaultTextColor = nil
    self._countdownDefaultTextColor = nil
    return self
end

function BrainrotBossController:_getPlayerGui()
    return localPlayer:FindFirstChildOfClass("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
end

function BrainrotBossController:_getCurrentCharacter()
    local character = localPlayer.Character
    if character and character.Parent then
        return character
    end

    return nil
end

function BrainrotBossController:_getCharacterRootPart(character)
    local currentCharacter = character or self:_getCurrentCharacter()
    if not currentCharacter then
        return nil
    end

    local rootPart = currentCharacter:FindFirstChild("HumanoidRootPart")
    if rootPart and rootPart:IsA("BasePart") then
        return rootPart
    end

    return nil
end

function BrainrotBossController:_isHomeLocked()
    if not self._landBarrierEnabled then
        return false
    end

    if self._state.visible ~= true or (tonumber(self._state.carriedCount) or 0) <= 0 then
        return false
    end

    return ((tonumber(self._state.homeUnlockAt) or 0) - getSharedClock()) > 0
end

function BrainrotBossController:_disconnectButtonConnections()
    if self._dropButtonConnection then
        self._dropButtonConnection:Disconnect()
        self._dropButtonConnection = nil
    end
    if self._homeButtonConnection then
        self._homeButtonConnection:Disconnect()
        self._homeButtonConnection = nil
    end
end

function BrainrotBossController:_bindButtons()
    self:_disconnectButtonConnections()

    if self._dropButton then
        self._dropButtonConnection = self._dropButton.Activated:Connect(function()
            if self._requestDropCarriedWorldBrainrotEvent then
                self._requestDropCarriedWorldBrainrotEvent:FireServer()
            end
        end)
    end

    if self._homeButton then
        self._homeButtonConnection = self._homeButton.Activated:Connect(function()
            if not self._homeEnabled then
                return
            end

            if self._requestQuickTeleportEvent then
                self._requestQuickTeleportEvent:FireServer({
                    target = "Home",
                })
            end
        end)
    end
end

function BrainrotBossController:_ensureUiNodes()
    local playerGui = self:_getPlayerGui()
    if not playerGui then
        return false
    end

    local mainGui = playerGui:FindFirstChild("Main")
    if not mainGui then
        return false
    end

    local dropRoot = mainGui:FindFirstChild("Drop", true)
    local dropButton = dropRoot and dropRoot:FindFirstChild("DropButton", true) or nil
    local homeButton = dropRoot and dropRoot:FindFirstChild("Home", true) or nil
    local countdownLabel = homeButton and homeButton:FindFirstChild("CountDownTime", true) or nil
    local homeReadyNodes = collectGuiDescendantsByName(homeButton, "Home")
    local homeLockedNodes = collectGuiDescendantsByName(homeButton, "NoHome")
    local warningRoot = mainGui:FindFirstChild("Warning", true)
    local warningText = warningRoot and warningRoot:FindFirstChild("Text", true) or nil

    local didChange = dropRoot ~= self._dropRoot
        or dropButton ~= self._dropButton
        or homeButton ~= self._homeButton
        or countdownLabel ~= self._countdownLabel
        or warningRoot ~= self._warningRoot
        or warningText ~= self._warningText

    self._dropRoot = dropRoot
    self._dropButton = dropButton
    self._homeButton = homeButton
    self._countdownLabel = countdownLabel
    self._homeReadyNodes = homeReadyNodes
    self._homeLockedNodes = homeLockedNodes
    self._warningRoot = warningRoot
    self._warningText = warningText

    if self._homeButton and not self._homeDefaultBackgroundColor then
        self._homeDefaultBackgroundColor = self._homeButton.BackgroundColor3
        self._homeDefaultTextColor = self._homeButton.TextColor3
    end
    if self._countdownLabel and not self._countdownDefaultTextColor then
        self._countdownDefaultTextColor = self._countdownLabel.TextColor3
    end

    if didChange then
        self:_bindButtons()
        setGuiVisible(self._warningRoot, false)
        self:_setWarningAlpha(1)
    end

    return self._dropRoot ~= nil
end

function BrainrotBossController:_applyHomeAvailabilityVisuals(isUnlocked, showCountdown)
    local shouldShowHome = isUnlocked == true
    local shouldShowCountdown = showCountdown == true

    for _, node in ipairs(self._homeReadyNodes or {}) do
        setGuiVisible(node, shouldShowHome)
    end

    for _, node in ipairs(self._homeLockedNodes or {}) do
        setGuiVisible(node, not shouldShowHome)
    end

    if self._countdownLabel then
        setGuiVisible(self._countdownLabel, shouldShowCountdown)
    end
end

function BrainrotBossController:_applyHomeButtonEnabled(enabled)
    self._homeEnabled = enabled == true
    if not self._homeButton then
        return
    end

    local backgroundColor = self._homeDefaultBackgroundColor or self._homeButton.BackgroundColor3
    local textColor = self._homeDefaultTextColor or self._homeButton.TextColor3
    local countdownTextColor = self._countdownDefaultTextColor or (self._countdownLabel and self._countdownLabel.TextColor3) or textColor

    self._homeButton.Active = self._homeEnabled
    self._homeButton.AutoButtonColor = self._homeEnabled
    self._homeButton.Selectable = self._homeEnabled
    self._homeButton.BackgroundColor3 = self._homeEnabled and backgroundColor or Color3.fromRGB(110, 110, 110)
    self._homeButton.TextColor3 = self._homeEnabled and textColor or Color3.fromRGB(220, 220, 220)

    if self._countdownLabel then
        self._countdownLabel.TextColor3 = self._homeEnabled and countdownTextColor or Color3.fromRGB(220, 220, 220)
    end
end

function BrainrotBossController:_refreshDropUi()
    self:_ensureUiNodes()
    if not self._dropRoot then
        return
    end

    local shouldShow = self._state.visible == true and (tonumber(self._state.carriedCount) or 0) > 0
    setGuiVisible(self._dropRoot, shouldShow)

    if not shouldShow then
        self:_applyHomeButtonEnabled(false)
        self:_applyHomeAvailabilityVisuals(false, false)
        if self._countdownLabel then
            self._countdownLabel.Text = ""
        end
        return
    end

    local remaining = math.max(0, (tonumber(self._state.homeUnlockAt) or 0) - getSharedClock())
    local isUnlocked = remaining <= 0
    self:_applyHomeButtonEnabled(isUnlocked)
    self:_applyHomeAvailabilityVisuals(isUnlocked, not isUnlocked)
    if self._countdownLabel then
        self._countdownLabel.Text = isUnlocked and "" or formatCountdownText(remaining)
    end
end

function BrainrotBossController:_ensureWorldSpawnLandParts()
    local folder = Workspace:FindFirstChild(self._worldSpawnLandFolderName)
    local shouldRefresh = folder ~= self._worldSpawnLandFolder or #self._worldSpawnLandParts == 0

    if not shouldRefresh then
        for _, landPart in ipairs(self._worldSpawnLandParts) do
            if not (landPart and landPart.Parent) then
                shouldRefresh = true
                break
            end
        end
    end

    if not shouldRefresh then
        return self._worldSpawnLandParts
    end

    self._worldSpawnLandFolder = folder
    self._worldSpawnLandParts = {}
    self._worldSpawnLandLookup = {}

    if not folder then
        return self._worldSpawnLandParts
    end

    for _, groupConfig in ipairs(BrainrotConfig.WorldSpawnGroups or {}) do
        local relativePartName = tostring(type(groupConfig) == "table" and groupConfig.PartName or "")
        local landPart = findDescendantByPath(folder, relativePartName)
        if landPart and landPart:IsA("BasePart") and not self._worldSpawnLandLookup[landPart] then
            table.insert(self._worldSpawnLandParts, landPart)
            self._worldSpawnLandLookup[landPart] = true
        end
    end

    return self._worldSpawnLandParts
end

function BrainrotBossController:_ensureBarrierFolder()
    local folder = self._airWallFolder
    if folder and folder.Parent then
        return folder
    end

    folder = Workspace:FindFirstChild(self._barrierFolderName)
    if folder and not folder:IsA("Folder") then
        folder:Destroy()
        folder = nil
    end

    if not folder then
        folder = Instance.new("Folder")
        folder.Name = self._barrierFolderName
        folder.Parent = Workspace
    end

    self._airWallFolder = folder
    return folder
end

function BrainrotBossController:_clearActiveLandBarrier()
    self._activeBarrierLand = nil
    self._activeBarrierParts = {}
    self._barrierCollisionPending = false

    local folder = self._airWallFolder
    if not (folder and folder.Parent) then
        return
    end

    for _, child in ipairs(folder:GetChildren()) do
        child:Destroy()
    end
end

function BrainrotBossController:_isPositionOnLand(position, landPart, horizontalPadding, belowTopTolerance, aboveTopTolerance)
    if typeof(position) ~= "Vector3" or not (landPart and landPart:IsA("BasePart")) then
        return false
    end

    local localPosition = landPart.CFrame:PointToObjectSpace(position)
    local halfSize = landPart.Size * 0.5
    return math.abs(localPosition.X) <= (halfSize.X + (horizontalPadding or 0))
        and math.abs(localPosition.Z) <= (halfSize.Z + (horizontalPadding or 0))
        and localPosition.Y >= (halfSize.Y - (belowTopTolerance or 0))
        and localPosition.Y <= (halfSize.Y + (aboveTopTolerance or 0))
end

function BrainrotBossController:_isPositionInsideBarrierBounds(position, landPart)
    if typeof(position) ~= "Vector3" or not (landPart and landPart:IsA("BasePart")) then
        return false
    end

    local localPosition = landPart.CFrame:PointToObjectSpace(position)
    local halfSize = landPart.Size * 0.5
    local horizontalPadding = self._barrierPadding + self._barrierThickness + self._barrierStickyDistance
    local minY = -halfSize.Y - self._barrierStickyDistance
    local maxY = halfSize.Y + self._barrierHeight + self._barrierStickyDistance

    return math.abs(localPosition.X) <= (halfSize.X + horizontalPadding)
        and math.abs(localPosition.Z) <= (halfSize.Z + horizontalPadding)
        and localPosition.Y >= minY
        and localPosition.Y <= maxY
end

function BrainrotBossController:_getTouchedWorldSpawnLand()
    self:_ensureWorldSpawnLandParts()

    local character = self:_getCurrentCharacter()
    local rootPart = self:_getCharacterRootPart(character)
    if not (character and rootPart) then
        return nil
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Health <= 0 then
        return nil
    end

    local filterInstances = { character }
    if self._airWallFolder and self._airWallFolder.Parent then
        table.insert(filterInstances, self._airWallFolder)
    end

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = filterInstances
    raycastParams.IgnoreWater = false

    local rayOrigin = rootPart.Position + Vector3.new(0, 2, 0)
    local rayDirection = Vector3.new(0, -self._barrierRaycastDistance, 0)
    local result = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
    if result and self._worldSpawnLandLookup[result.Instance] then
        return result.Instance
    end

    for _, landPart in ipairs(self._worldSpawnLandParts) do
        if landPart and landPart.Parent and self:_isPositionOnLand(rootPart.Position, landPart, 3, 6, 8) then
            return landPart
        end
    end

    return nil
end

function BrainrotBossController:_createBarrierPart(folder, name, size, cframe, canCollide)
    local wall = Instance.new("Part")
    wall.Name = name
    wall.Anchored = true
    wall.CanCollide = canCollide == true
    wall.CanTouch = false
    wall.CanQuery = false
    wall.CastShadow = false
    wall.Transparency = self._barrierTransparency
    wall.Material = Enum.Material.Plastic
    wall.TopSurface = Enum.SurfaceType.Smooth
    wall.BottomSurface = Enum.SurfaceType.Smooth
    wall.Size = size
    wall.CFrame = cframe
    wall.Parent = folder
    return wall
end

function BrainrotBossController:_setBarrierPartsCollidable(canCollide)
    for _, wall in ipairs(self._activeBarrierParts) do
        if wall and wall.Parent then
            wall.CanCollide = canCollide == true
        end
    end
end

function BrainrotBossController:_isCharacterClearOfBarrierOverlap(rootPart, landPart)
    if not (rootPart and rootPart.Parent and landPart and landPart.Parent) then
        return false
    end

    local localPosition = landPart.CFrame:PointToObjectSpace(rootPart.Position)
    local halfSize = landPart.Size * 0.5
    local rootRadius = math.max(rootPart.Size.X, rootPart.Size.Z) * 0.5
    local edgeClearance = self._barrierCollisionClearance + rootRadius

    return math.abs(localPosition.X) <= math.max(0, halfSize.X - edgeClearance)
        and math.abs(localPosition.Z) <= math.max(0, halfSize.Z - edgeClearance)
end

function BrainrotBossController:_tryEnableBarrierCollision(rootPart)
    if not self._barrierCollisionPending then
        return
    end

    local activeLand = self._activeBarrierLand
    if not (activeLand and activeLand.Parent) then
        self._barrierCollisionPending = false
        return
    end

    if not self:_isCharacterClearOfBarrierOverlap(rootPart, activeLand) then
        self:_setBarrierPartsCollidable(false)
        return
    end

    self:_setBarrierPartsCollidable(true)
    self._barrierCollisionPending = false
end

function BrainrotBossController:_createBarrierForLand(landPart)
    if not (landPart and landPart:IsA("BasePart") and landPart.Parent) then
        self:_clearActiveLandBarrier()
        return
    end

    self:_clearActiveLandBarrier()

    local folder = self:_ensureBarrierFolder()
    local halfSize = landPart.Size * 0.5
    local centerYOffset = halfSize.Y + (self._barrierHeight * 0.5) - self._barrierGroundInset
    local expandedHalfX = halfSize.X + self._barrierPadding
    local expandedHalfZ = halfSize.Z + self._barrierPadding
    local frontBackSize = Vector3.new(landPart.Size.X + (self._barrierPadding * 2) + (self._barrierThickness * 2), self._barrierHeight, self._barrierThickness)
    local leftRightSize = Vector3.new(self._barrierThickness, self._barrierHeight, landPart.Size.Z + (self._barrierPadding * 2) + (self._barrierThickness * 2))

    table.insert(self._activeBarrierParts, self:_createBarrierPart(
        folder,
        "FrontWall",
        frontBackSize,
        landPart.CFrame * CFrame.new(0, centerYOffset, -(expandedHalfZ + (self._barrierThickness * 0.5))),
        false
    ))
    table.insert(self._activeBarrierParts, self:_createBarrierPart(
        folder,
        "BackWall",
        frontBackSize,
        landPart.CFrame * CFrame.new(0, centerYOffset, expandedHalfZ + (self._barrierThickness * 0.5)),
        false
    ))
    table.insert(self._activeBarrierParts, self:_createBarrierPart(
        folder,
        "LeftWall",
        leftRightSize,
        landPart.CFrame * CFrame.new(-(expandedHalfX + (self._barrierThickness * 0.5)), centerYOffset, 0),
        false
    ))
    table.insert(self._activeBarrierParts, self:_createBarrierPart(
        folder,
        "RightWall",
        leftRightSize,
        landPart.CFrame * CFrame.new(expandedHalfX + (self._barrierThickness * 0.5), centerYOffset, 0),
        false
    ))

    self._activeBarrierLand = landPart
    self._barrierCollisionPending = true
end

function BrainrotBossController:_refreshLandBarrier()
    if not self:_isHomeLocked() then
        self:_clearActiveLandBarrier()
        return
    end

    local character = self:_getCurrentCharacter()
    local rootPart = self:_getCharacterRootPart(character)
    if not (character and rootPart) then
        self:_clearActiveLandBarrier()
        return
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Health <= 0 then
        self:_clearActiveLandBarrier()
        return
    end

    local targetLand = self:_getTouchedWorldSpawnLand()
    if not targetLand and self._activeBarrierLand and self._activeBarrierLand.Parent then
        if self:_isPositionInsideBarrierBounds(rootPart.Position, self._activeBarrierLand) then
            targetLand = self._activeBarrierLand
        end
    end

    if not targetLand then
        self:_clearActiveLandBarrier()
        return
    end

    local needsRebuild = self._activeBarrierLand ~= targetLand
    local folder = self._airWallFolder
    if not needsRebuild then
        needsRebuild = not (folder and folder.Parent and #folder:GetChildren() >= 4)
    end

    if needsRebuild then
        self:_createBarrierForLand(targetLand)
    end

    self:_tryEnableBarrierCollision(rootPart)
end

function BrainrotBossController:_setWarningAlpha(alpha)
    self._warningAlpha = math.clamp(tonumber(alpha) or 1, 0, 1)
    if self._warningText and self._warningText:IsA("TextLabel") then
        self._warningText.TextTransparency = self._warningAlpha
        self._warningText.TextStrokeTransparency = math.clamp(self._warningAlpha + 0.1, 0, 1)

        local uiStroke = self._warningText:FindFirstChildWhichIsA("UIStroke")
        if uiStroke then
            uiStroke.Transparency = math.clamp(self._warningAlpha + 0.1, 0, 1)
        end
    end
end

function BrainrotBossController:_tweenWarningAlpha(targetAlpha, duration)
    self:_ensureUiNodes()
    if not self._warningRoot then
        return
    end

    setGuiVisible(self._warningRoot, true)

    local driver = Instance.new("NumberValue")
    driver.Value = self._warningAlpha
    local connection = driver:GetPropertyChangedSignal("Value"):Connect(function()
        self:_setWarningAlpha(driver.Value)
    end)

    local tween = TweenService:Create(driver, TweenInfo.new(math.max(0.05, duration), Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
        Value = math.clamp(targetAlpha, 0, 1),
    })
    tween:Play()
    tween.Completed:Wait()

    connection:Disconnect()
    driver:Destroy()
end

function BrainrotBossController:_playWarningBlink(payload)
    self._warningSerial += 1
    local serial = self._warningSerial
    local blinkCount = math.max(1, math.floor(tonumber(type(payload) == "table" and payload.blinkCount or 0) or tonumber((GameConfig.BRAINROT or {}).BossWarningBlinkCount) or 3))
    local fadeTime = math.max(0.05, tonumber(type(payload) == "table" and payload.fadeTime or 0) or tonumber((GameConfig.BRAINROT or {}).BossWarningFadeTime) or 0.18)

    task.spawn(function()
        self:_ensureUiNodes()
        if not self._warningRoot then
            return
        end

        setGuiVisible(self._warningRoot, true)
        self:_setWarningAlpha(1)

        for _ = 1, blinkCount do
            if serial ~= self._warningSerial then
                return
            end
            self:_tweenWarningAlpha(0, fadeTime)
            if serial ~= self._warningSerial then
                return
            end
            self:_tweenWarningAlpha(1, fadeTime)
        end

        if serial == self._warningSerial then
            self:_setWarningAlpha(1)
            setGuiVisible(self._warningRoot, false)
        end
    end)
end

function BrainrotBossController:_handleBossStateSync(payload)
    local normalizedPayload = type(payload) == "table" and payload or {}
    self._state.visible = normalizedPayload.visible == true
    self._state.carriedCount = math.max(0, math.floor(tonumber(normalizedPayload.carriedCount) or 0))
    self._state.homeUnlockAt = math.max(0, tonumber(normalizedPayload.homeUnlockAt) or 0)
    self._state.isChased = normalizedPayload.isChased == true
    self:_refreshDropUi()
    self:_refreshLandBarrier()
end

function BrainrotBossController:_ensureBossRuntimeFolder()
    local folder = Workspace:FindFirstChild(self._bossRuntimeFolderName)
    if folder and folder:IsA("Folder") then
        self._bossRuntimeFolder = folder
        return folder
    end

    self._bossRuntimeFolder = nil
    return nil
end

function BrainrotBossController:_isBossRuntimeModel(model)
    if not (model and model:IsA("Model")) then
        return false
    end

    return model:GetAttribute(BOSS_RUNTIME_ATTRIBUTE) == true
        or string.sub(model.Name, 1, #"WorldSpawnBoss_") == "WorldSpawnBoss_"
end

function BrainrotBossController:_readBossTargetCFrame(model, fallbackCFrame)
    local fallback = fallbackCFrame
    if not fallback then
        local ok, pivotOrError = pcall(function()
            return model:GetPivot()
        end)
        fallback = ok and pivotOrError or CFrame.new()
    end

    local targetPosition = model:GetAttribute(BOSS_TARGET_POSITION_ATTRIBUTE)
    if typeof(targetPosition) ~= "Vector3" then
        targetPosition = fallback.Position
    end

    local targetLookVector = model:GetAttribute(BOSS_TARGET_LOOK_VECTOR_ATTRIBUTE)
    return buildBossTargetCFrame(targetPosition, targetLookVector, fallback.LookVector)
end

function BrainrotBossController:_trackBossModel(model)
    if not self:_isBossRuntimeModel(model) or self._trackedBosses[model] then
        return
    end

    local initialTarget = self:_readBossTargetCFrame(model)
    local initialUpdatedAt = math.max(0, tonumber(model:GetAttribute(BOSS_SERVER_UPDATED_AT_ATTRIBUTE) or 0) or 0)
    self._trackedBosses[model] = {
        previousServerCFrame = initialTarget,
        latestServerCFrame = initialTarget,
        currentCFrame = initialTarget,
        receiveAt = os.clock(),
        interpolationWindow = self._bossInterpolationWindow,
        lastServerUpdatedAt = initialUpdatedAt,
        lastState = tostring(model:GetAttribute(BOSS_STATE_ATTRIBUTE) or "Idle"),
    }
end

function BrainrotBossController:_refreshTrackedBosses()
    local folder = self:_ensureBossRuntimeFolder()
    local seen = {}
    if folder then
        for _, child in ipairs(folder:GetChildren()) do
            if self:_isBossRuntimeModel(child) then
                seen[child] = true
                self:_trackBossModel(child)
            end
        end
    end

    for model in pairs(self._trackedBosses) do
        if not seen[model] or not model.Parent then
            self._trackedBosses[model] = nil
        end
    end
end

function BrainrotBossController:_updateBossVisual(model, trackedBoss)
    local latestTargetCFrame = self:_readBossTargetCFrame(model, trackedBoss.latestServerCFrame or trackedBoss.currentCFrame)
    local currentState = tostring(model:GetAttribute(BOSS_STATE_ATTRIBUTE) or "Idle")
    local serverUpdatedAt = math.max(0, tonumber(model:GetAttribute(BOSS_SERVER_UPDATED_AT_ATTRIBUTE) or 0) or 0)

    if serverUpdatedAt > 0 and serverUpdatedAt ~= trackedBoss.lastServerUpdatedAt then
        local previousServerCFrame = trackedBoss.latestServerCFrame or latestTargetCFrame
        local jumpDistance = (latestTargetCFrame.Position - previousServerCFrame.Position).Magnitude
        local shouldSnap = currentState == "Attack" or jumpDistance >= self._bossSnapDistance
        local serverDelta = trackedBoss.lastServerUpdatedAt > 0
            and math.max(0, serverUpdatedAt - trackedBoss.lastServerUpdatedAt)
            or self._bossInterpolationWindow

        trackedBoss.previousServerCFrame = shouldSnap and latestTargetCFrame or previousServerCFrame
        trackedBoss.latestServerCFrame = latestTargetCFrame
        trackedBoss.receiveAt = os.clock()
        trackedBoss.interpolationWindow = shouldSnap
            and (1 / 120)
            or math.clamp(math.max(self._bossInterpolationWindow, serverDelta), 1 / 120, 0.35)
        trackedBoss.lastServerUpdatedAt = serverUpdatedAt
    elseif not trackedBoss.latestServerCFrame then
        trackedBoss.previousServerCFrame = latestTargetCFrame
        trackedBoss.latestServerCFrame = latestTargetCFrame
        trackedBoss.receiveAt = os.clock()
        trackedBoss.interpolationWindow = self._bossInterpolationWindow
        trackedBoss.lastServerUpdatedAt = serverUpdatedAt
    else
        trackedBoss.latestServerCFrame = latestTargetCFrame
    end

    local visualCFrame = trackedBoss.latestServerCFrame or latestTargetCFrame
    if currentState ~= "Attack" then
        local interpolationWindow = math.max(1 / 120, trackedBoss.interpolationWindow or self._bossInterpolationWindow)
        local alpha = math.clamp((os.clock() - (trackedBoss.receiveAt or os.clock())) / interpolationWindow, 0, 1)
        local fromCFrame = trackedBoss.previousServerCFrame or visualCFrame
        visualCFrame = fromCFrame:Lerp(visualCFrame, alpha)
    end

    trackedBoss.currentCFrame = visualCFrame
    trackedBoss.lastState = currentState
    pcall(function()
        model:PivotTo(visualCFrame)
    end)
end

function BrainrotBossController:_updateBossVisuals()
    if not self._bossVisualSmoothingEnabled then
        return
    end

    self:_refreshTrackedBosses()
    for model, trackedBoss in pairs(self._trackedBosses) do
        if model and model.Parent and self:_isBossRuntimeModel(model) then
            self:_updateBossVisual(model, trackedBoss)
        else
            self._trackedBosses[model] = nil
        end
    end
end

function BrainrotBossController:Start()
    if self._started then
        return
    end

    self._started = true

    local eventsRoot = ReplicatedStorage:WaitForChild(RemoteNames.RootFolder)
    local brainrotEvents = eventsRoot:WaitForChild(RemoteNames.BrainrotEventsFolder)
    local systemEvents = eventsRoot:WaitForChild(RemoteNames.SystemEventsFolder)

    self._bossStateSyncEvent = brainrotEvents:WaitForChild(RemoteNames.Brainrot.BossStateSync, 10)
    self._requestDropCarriedWorldBrainrotEvent = brainrotEvents:WaitForChild(RemoteNames.Brainrot.RequestDropCarriedWorldBrainrot, 10)
    self._bossWarningEvent = brainrotEvents:WaitForChild(RemoteNames.Brainrot.BossWarning, 10)
    self._requestQuickTeleportEvent = systemEvents:WaitForChild(RemoteNames.System.RequestQuickTeleport, 10)

    if self._bossStateSyncEvent and self._bossStateSyncEvent:IsA("RemoteEvent") then
        self._bossStateSyncEvent.OnClientEvent:Connect(function(payload)
            self:_handleBossStateSync(payload)
        end)
    end

    if self._bossWarningEvent and self._bossWarningEvent:IsA("RemoteEvent") then
        self._bossWarningEvent.OnClientEvent:Connect(function(payload)
            self:_playWarningBlink(payload)
        end)
    end

    if self._bossVisualSmoothingEnabled and not self._bossRenderConnection then
        self._bossRenderConnection = RunService.RenderStepped:Connect(function()
            self:_updateBossVisuals()
        end)
    end

    task.spawn(function()
        while self._started do
            task.wait(self._updateInterval)
            self:_refreshDropUi()
            self:_refreshLandBarrier()
        end
    end)

    self:_refreshDropUi()
    self:_refreshLandBarrier()
end

return BrainrotBossController
