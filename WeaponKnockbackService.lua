--[[
脚本名字: WeaponKnockbackService
脚本文件: WeaponKnockbackService.lua
脚本类型: ModuleScript
Studio放置路径: ServerScriptService/Services/WeaponKnockbackService
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
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
        "[WeaponKnockbackService] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local GameConfig = requireSharedModule("GameConfig")

local WeaponKnockbackService = {}
WeaponKnockbackService._playerRuntimeByUserId = {}
WeaponKnockbackService._toolRuntimeByTool = setmetatable({}, { __mode = "k" })
WeaponKnockbackService._isInitialized = false

local function getWeaponConfig()
    if type(GameConfig.WEAPON) == "table" then
        return GameConfig.WEAPON
    end

    return {}
end

local function getCharacterModelFromPart(part)
    local current = part
    while current and current ~= Workspace do
        if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
            return current
        end
        current = current.Parent
    end

    return nil
end

local function getRootPartFromCharacter(character)
    if not character then
        return nil
    end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if rootPart and rootPart:IsA("BasePart") then
        return rootPart
    end

    local primaryPart = character.PrimaryPart
    if primaryPart and primaryPart:IsA("BasePart") then
        return primaryPart
    end

    local fallback = character:FindFirstChildWhichIsA("BasePart")
    if fallback and fallback:IsA("BasePart") then
        return fallback
    end

    return nil
end

local function resolveHorizontalDirection(attackerRootPart, targetRootPart)
    local rawDirection = nil
    if attackerRootPart and targetRootPart then
        rawDirection = targetRootPart.Position - attackerRootPart.Position
    end

    if not rawDirection or rawDirection.Magnitude <= 0.001 then
        rawDirection = attackerRootPart and attackerRootPart.CFrame.LookVector or Vector3.new(0, 0, -1)
    end

    local horizontal = Vector3.new(rawDirection.X, 0, rawDirection.Z)
    if horizontal.Magnitude <= 0.001 then
        local fallback = attackerRootPart and attackerRootPart.CFrame.LookVector or Vector3.new(0, 0, -1)
        horizontal = Vector3.new(fallback.X, 0, fallback.Z)
    end

    if horizontal.Magnitude <= 0.001 then
        return Vector3.new(0, 0, -1)
    end

    return horizontal.Unit
end

local function normalizeHitboxSize(rawSize)
    if typeof(rawSize) == "Vector3" then
        return Vector3.new(
            math.max(1, tonumber(rawSize.X) or 1),
            math.max(1, tonumber(rawSize.Y) or 1),
            math.max(1, tonumber(rawSize.Z) or 1)
        )
    end

    return Vector3.new(5.5, 5.5, 6.5)
end

local function buildForwardHitboxCFrame(rootPart, forwardOffset)
    if not rootPart then
        return nil
    end

    local lookVector = rootPart.CFrame.LookVector
    local horizontalLook = Vector3.new(lookVector.X, 0, lookVector.Z)
    if horizontalLook.Magnitude <= 0.001 then
        horizontalLook = Vector3.new(0, 0, -1)
    else
        horizontalLook = horizontalLook.Unit
    end

    local centerPosition = rootPart.Position + Vector3.new(0, 1.5, 0) + (horizontalLook * forwardOffset)
    return CFrame.lookAt(centerPosition, centerPosition + horizontalLook, Vector3.new(0, 1, 0))
end

local function resolveSwingAnimationId()
    local weaponConfig = getWeaponConfig()
    local animationId = weaponConfig.SwingAttackAnimationId

    if type(animationId) == "number" then
        animationId = tostring(math.floor(animationId))
    end

    if type(animationId) ~= "string" then
        return "rbxassetid://79436155132033"
    end

    local trimmed = string.gsub(animationId, "^%s*(.-)%s*$", "%1")
    if trimmed == "" then
        return "rbxassetid://79436155132033"
    end

    if string.match(trimmed, "^rbxassetid://%d+$") then
        return trimmed
    end

    if string.match(trimmed, "^%d+$") then
        return "rbxassetid://" .. trimmed
    end

    return "rbxassetid://79436155132033"
end

local function playDefaultSwingAnimation(tool)
    if not tool then
        return
    end

    local character = tool.Parent
    if character and character:IsA("Model") then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            local animator = humanoid:FindFirstChildOfClass("Animator")
            if not animator then
                animator = Instance.new("Animator")
                animator.Parent = humanoid
            end

            local animation = Instance.new("Animation")
            animation.AnimationId = resolveSwingAnimationId()

            local ok, track = pcall(function()
                return animator:LoadAnimation(animation)
            end)
            animation:Destroy()

            if ok and track then
                track.Priority = Enum.AnimationPriority.Action
                track:Play(0.05, 1, 1)
                return
            end
        end
    end

    local marker = Instance.new("StringValue")
    marker.Name = "toolanim"
    marker.Value = "Slash"
    marker.Parent = tool
    Debris:AddItem(marker, 0.15)
end

function WeaponKnockbackService:_getToolMarkerAttributeNames()
    local weaponConfig = getWeaponConfig()
    local isWeaponAttributeName = tostring(weaponConfig.ToolIsWeaponAttributeName or "IsWeaponTool")
    local weaponIdAttributeName = tostring(weaponConfig.ToolWeaponIdAttributeName or "WeaponId")
    return isWeaponAttributeName, weaponIdAttributeName
end

function WeaponKnockbackService:_getConfig()
    local weaponConfig = getWeaponConfig()

    return {
        Enabled = weaponConfig.KnockbackEnabled ~= false,
        RequireToolEquipped = weaponConfig.KnockbackRequireToolEquipped ~= false,
        ActiveWindowSeconds = math.max(0.05, tonumber(weaponConfig.KnockbackActiveWindowSeconds) or 0.35),
        HitCooldownSeconds = math.max(0.05, tonumber(weaponConfig.KnockbackHitCooldownSeconds) or 0.45),
        HorizontalVelocity = math.max(0, tonumber(weaponConfig.KnockbackHorizontalVelocity) or 75),
        VerticalVelocity = tonumber(weaponConfig.KnockbackVerticalVelocity) or 35,
        HitboxForwardOffset = math.max(1.5, tonumber(weaponConfig.KnockbackHitboxForwardOffset) or 3.5),
        HitboxSize = normalizeHitboxSize(weaponConfig.KnockbackHitboxSize),
        HitboxScanInterval = math.max(0.02, tonumber(weaponConfig.KnockbackHitboxScanInterval) or 0.05),
    }
end

function WeaponKnockbackService:_isWeaponTool(tool)
    if not (tool and tool:IsA("Tool")) then
        return false
    end

    local isWeaponAttributeName, weaponIdAttributeName = self:_getToolMarkerAttributeNames()
    if tool:GetAttribute(isWeaponAttributeName) == true then
        return true
    end

    local weaponId = tool:GetAttribute(weaponIdAttributeName)
    return type(weaponId) == "string" and weaponId ~= ""
end

function WeaponKnockbackService:_disconnectConnectionList(connectionList)
    if type(connectionList) ~= "table" then
        return
    end

    for _, connection in ipairs(connectionList) do
        if connection then
            connection:Disconnect()
        end
    end
end

function WeaponKnockbackService:_unbindTool(tool)
    local runtime = self._toolRuntimeByTool[tool]
    if not runtime then
        return
    end

    runtime.ActiveScanSerial = (tonumber(runtime.ActiveScanSerial) or 0) + 1
    self._toolRuntimeByTool[tool] = nil
    self:_disconnectConnectionList(runtime.Connections)

    local playerRuntime = runtime.PlayerRuntime
    if playerRuntime and type(playerRuntime.ToolSet) == "table" then
        playerRuntime.ToolSet[tool] = nil
    end
end

function WeaponKnockbackService:_applyKnockback(attackerPlayer, targetCharacter)
    if not (attackerPlayer and targetCharacter) then
        return
    end

    local targetHumanoid = targetCharacter:FindFirstChildOfClass("Humanoid")
    if not targetHumanoid or targetHumanoid.Health <= 0 then
        return
    end

    local attackerRootPart = getRootPartFromCharacter(attackerPlayer.Character)
    local targetRootPart = getRootPartFromCharacter(targetCharacter)
    if not targetRootPart then
        return
    end

    local knockbackConfig = self:_getConfig()
    local horizontalDirection = resolveHorizontalDirection(attackerRootPart, targetRootPart)
    local desiredVelocity = (horizontalDirection * knockbackConfig.HorizontalVelocity) + Vector3.new(0, knockbackConfig.VerticalVelocity, 0)

    local currentVelocity = targetRootPart.AssemblyLinearVelocity
    targetRootPart.AssemblyLinearVelocity = Vector3.new(
        desiredVelocity.X,
        math.max(currentVelocity.Y, desiredVelocity.Y),
        desiredVelocity.Z
    )

    targetHumanoid:ChangeState(Enum.HumanoidStateType.FallingDown)
end

function WeaponKnockbackService:_getActiveOwnerCharacter(ownerPlayer, tool, toolRuntime, config, nowClock)
    if not (ownerPlayer and tool and toolRuntime and config) then
        return nil
    end

    local lastActivatedClock = tonumber(toolRuntime.LastActivatedClock) or 0
    if lastActivatedClock <= 0 or (nowClock - lastActivatedClock) > config.ActiveWindowSeconds then
        return nil
    end

    local ownerCharacter = ownerPlayer.Character
    if config.RequireToolEquipped then
        if not ownerCharacter or tool.Parent ~= ownerCharacter then
            return nil
        end
    end

    return ownerCharacter
end

function WeaponKnockbackService:_tryApplyHitToTarget(ownerPlayer, toolRuntime, targetCharacter, nowClock, config)
    if not (ownerPlayer and toolRuntime and targetCharacter) then
        return false
    end

    local targetPlayer = Players:GetPlayerFromCharacter(targetCharacter)
    if not targetPlayer or targetPlayer == ownerPlayer then
        return false
    end

    local targetUserId = targetPlayer.UserId
    local hitCooldownByTargetUserId = toolRuntime.HitCooldownByTargetUserId
    local lastHitClock = tonumber(hitCooldownByTargetUserId[targetUserId]) or 0
    if nowClock - lastHitClock < config.HitCooldownSeconds then
        return false
    end

    hitCooldownByTargetUserId[targetUserId] = nowClock
    self:_applyKnockback(ownerPlayer, targetCharacter)
    return true
end

function WeaponKnockbackService:_scanSwingHitbox(ownerPlayer, tool, toolRuntime)
    local config = self:_getConfig()
    if not config.Enabled then
        return
    end

    local nowClock = os.clock()
    local ownerCharacter = self:_getActiveOwnerCharacter(ownerPlayer, tool, toolRuntime, config, nowClock)
    if not ownerCharacter then
        return
    end

    local ownerRootPart = getRootPartFromCharacter(ownerCharacter)
    if not ownerRootPart then
        return
    end

    local hitboxCFrame = buildForwardHitboxCFrame(ownerRootPart, config.HitboxForwardOffset)
    if not hitboxCFrame then
        return
    end

    local overlapParams = OverlapParams.new()
    overlapParams.FilterType = Enum.RaycastFilterType.Exclude
    overlapParams.FilterDescendantsInstances = { ownerCharacter }
    overlapParams.MaxParts = 32

    local success, parts = pcall(function()
        return Workspace:GetPartBoundsInBox(hitboxCFrame, config.HitboxSize, overlapParams)
    end)
    if not success or type(parts) ~= "table" then
        return
    end

    local seenTargetCharacter = {}
    for _, part in ipairs(parts) do
        if part:IsA("BasePart") then
            local targetCharacter = getCharacterModelFromPart(part)
            if targetCharacter and not seenTargetCharacter[targetCharacter] then
                seenTargetCharacter[targetCharacter] = true
                self:_tryApplyHitToTarget(ownerPlayer, toolRuntime, targetCharacter, nowClock, config)
            end
        end
    end
end

function WeaponKnockbackService:_startSwingHitboxScan(ownerPlayer, tool, toolRuntime)
    local config = self:_getConfig()
    toolRuntime.ActiveScanSerial = (tonumber(toolRuntime.ActiveScanSerial) or 0) + 1
    local scanSerial = toolRuntime.ActiveScanSerial

    self:_scanSwingHitbox(ownerPlayer, tool, toolRuntime)

    task.spawn(function()
        local deadline = (tonumber(toolRuntime.LastActivatedClock) or os.clock()) + config.ActiveWindowSeconds
        while self._toolRuntimeByTool[tool] == toolRuntime and toolRuntime.ActiveScanSerial == scanSerial do
            if os.clock() >= deadline then
                return
            end

            task.wait(config.HitboxScanInterval)
            self:_scanSwingHitbox(ownerPlayer, tool, toolRuntime)
        end
    end)
end

function WeaponKnockbackService:_onWeaponHandleTouched(ownerPlayer, tool, hitPart)
    if not (ownerPlayer and tool and hitPart and hitPart:IsA("BasePart")) then
        return
    end

    local config = self:_getConfig()
    if not config.Enabled then
        return
    end

    local toolRuntime = self._toolRuntimeByTool[tool]
    if not toolRuntime then
        return
    end

    local nowClock = os.clock()
    local ownerCharacter = self:_getActiveOwnerCharacter(ownerPlayer, tool, toolRuntime, config, nowClock)
    if not ownerCharacter then
        return
    end

    local targetCharacter = getCharacterModelFromPart(hitPart)
    if not targetCharacter or targetCharacter == ownerCharacter then
        return
    end

    self:_tryApplyHitToTarget(ownerPlayer, toolRuntime, targetCharacter, nowClock, config)
end

function WeaponKnockbackService:_bindToolHandleTouch(ownerPlayer, tool, toolRuntime)
    local handle = tool:FindFirstChild("Handle")
    if handle and handle:IsA("BasePart") then
        table.insert(toolRuntime.Connections, handle.Touched:Connect(function(hitPart)
            self:_onWeaponHandleTouched(ownerPlayer, tool, hitPart)
        end))
        return
    end

    table.insert(toolRuntime.Connections, tool.ChildAdded:Connect(function(child)
        if child.Name == "Handle" and child:IsA("BasePart") then
            table.insert(toolRuntime.Connections, child.Touched:Connect(function(hitPart)
                self:_onWeaponHandleTouched(ownerPlayer, tool, hitPart)
            end))
        end
    end))
end

function WeaponKnockbackService:_bindTool(ownerPlayer, playerRuntime, tool)
    if not self:_isWeaponTool(tool) then
        return
    end

    if self._toolRuntimeByTool[tool] then
        return
    end

    local toolRuntime = {
        PlayerRuntime = playerRuntime,
        Connections = {},
        LastActivatedClock = 0,
        ActiveScanSerial = 0,
        HitCooldownByTargetUserId = {},
    }

    self._toolRuntimeByTool[tool] = toolRuntime
    playerRuntime.ToolSet[tool] = true

    table.insert(toolRuntime.Connections, tool.Activated:Connect(function()
        toolRuntime.LastActivatedClock = os.clock()
        playDefaultSwingAnimation(tool)
        self:_startSwingHitboxScan(ownerPlayer, tool, toolRuntime)
    end))

    table.insert(toolRuntime.Connections, tool.AncestryChanged:Connect(function(_, parent)
        if not parent then
            self:_unbindTool(tool)
        end
    end))

    self:_bindToolHandleTouch(ownerPlayer, tool, toolRuntime)
end

function WeaponKnockbackService:_scanContainerTools(ownerPlayer, playerRuntime, container)
    if not container then
        return
    end

    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("Tool") then
            self:_bindTool(ownerPlayer, playerRuntime, child)
        end
    end
end

function WeaponKnockbackService:_bindContainerWatcher(ownerPlayer, playerRuntime, container)
    if not container then
        return
    end

    table.insert(playerRuntime.Connections, container.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then
            self:_bindTool(ownerPlayer, playerRuntime, child)
        end
    end))

    table.insert(playerRuntime.Connections, container.ChildRemoved:Connect(function(child)
        if child:IsA("Tool") then
            self:_unbindTool(child)
        end
    end))
end

function WeaponKnockbackService:_bindPlayerRuntime(player)
    local userId = player.UserId
    self:OnPlayerRemoving(player)

    local playerRuntime = {
        Connections = {},
        ToolSet = {},
    }
    self._playerRuntimeByUserId[userId] = playerRuntime

    local backpack = player:FindFirstChild("Backpack") or player:WaitForChild("Backpack", 5)
    self:_scanContainerTools(player, playerRuntime, backpack)
    self:_bindContainerWatcher(player, playerRuntime, backpack)

    local character = player.Character
    if character then
        self:_scanContainerTools(player, playerRuntime, character)
        self:_bindContainerWatcher(player, playerRuntime, character)
    end

    table.insert(playerRuntime.Connections, player.CharacterAdded:Connect(function(newCharacter)
        self:_scanContainerTools(player, playerRuntime, newCharacter)
        self:_bindContainerWatcher(player, playerRuntime, newCharacter)
    end))
end

function WeaponKnockbackService:Init()
    if self._isInitialized then
        return
    end

    self._isInitialized = true
end

function WeaponKnockbackService:OnPlayerReady(player)
    if not player then
        return
    end

    local config = self:_getConfig()
    if not config.Enabled then
        return
    end

    self:_bindPlayerRuntime(player)
end

function WeaponKnockbackService:OnPlayerRemoving(player)
    if not player then
        return
    end

    local userId = player.UserId
    local playerRuntime = self._playerRuntimeByUserId[userId]
    if not playerRuntime then
        return
    end

    self._playerRuntimeByUserId[userId] = nil
    self:_disconnectConnectionList(playerRuntime.Connections)

    for tool, _ in pairs(playerRuntime.ToolSet) do
        self:_unbindTool(tool)
    end
end

return WeaponKnockbackService