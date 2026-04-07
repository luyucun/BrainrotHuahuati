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
local RunService = game:GetService("RunService")

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
WeaponKnockbackService._knockdownSerialByHumanoid = setmetatable({}, { __mode = "k" })
WeaponKnockbackService._knockdownBaselineByHumanoid = setmetatable({}, { __mode = "k" })
WeaponKnockbackService._isInitialized = false

local function enforceAssemblyVelocityForDuration(rootPart, desiredVelocity, duration)
    if duration <= 0 or not (rootPart and rootPart.Parent) then
        return
    end

    local endAt = os.clock() + duration
    local connection
    connection = RunService.Heartbeat:Connect(function()
        if not (rootPart and rootPart.Parent) or os.clock() >= endAt then
            if connection then
                connection:Disconnect()
            end
            return
        end

        local currentVelocity = rootPart.AssemblyLinearVelocity
        rootPart.AssemblyLinearVelocity = Vector3.new(
            desiredVelocity.X,
            math.max(currentVelocity.Y, desiredVelocity.Y),
            desiredVelocity.Z
        )
    end)
end

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

local function getKnockbackSourceCFrame(attackerSource)
    if not attackerSource then
        return nil
    end

    if attackerSource:IsA("BasePart") then
        return attackerSource.CFrame
    end

    if attackerSource:IsA("Model") then
        local attackerRootPart = getRootPartFromCharacter(attackerSource)
        if attackerRootPart then
            return attackerRootPart.CFrame
        end

        local ok, pivot = pcall(function()
            return attackerSource:GetPivot()
        end)
        if ok then
            return pivot
        end
    end

    return nil
end

local function resolveHorizontalDirectionFromCFrame(sourceCFrame, targetRootPart)
    local rawDirection = nil
    if sourceCFrame and targetRootPart then
        rawDirection = targetRootPart.Position - sourceCFrame.Position
    end

    if not rawDirection or rawDirection.Magnitude <= 0.001 then
        rawDirection = sourceCFrame and sourceCFrame.LookVector or Vector3.new(0, 0, -1)
    end

    local horizontal = Vector3.new(rawDirection.X, 0, rawDirection.Z)
    if horizontal.Magnitude <= 0.001 then
        local fallback = sourceCFrame and sourceCFrame.LookVector or Vector3.new(0, 0, -1)
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
        UseImpulse = weaponConfig.KnockbackUseImpulse ~= false,
        PlatformStandDuration = math.max(0, tonumber(weaponConfig.KnockbackPlatformStandDuration) or 0),
        PlatformStandDelay = math.max(0, tonumber(weaponConfig.KnockbackPlatformStandDelay) or 0),
        RagdollDuration = math.max(0, tonumber(weaponConfig.KnockbackRagdollDuration) or tonumber(weaponConfig.KnockbackFallingDownDuration) or 0.75),
        FallingDownPulseDuration = math.max(0, tonumber(weaponConfig.KnockbackFallingDownPulseDuration) or 0.16),
        RecoveryGroundWaitSeconds = math.max(0, tonumber(weaponConfig.KnockbackRecoveryGroundWaitSeconds) or 0.45),
        RecoverySettleTimeoutSeconds = math.max(0.05, tonumber(weaponConfig.KnockbackRecoverySettleTimeoutSeconds) or 1.0),
        RecoveryMaxLinearSpeed = math.max(0, tonumber(weaponConfig.KnockbackRecoveryMaxLinearSpeed) or 6),
        RecoveryMaxAngularSpeed = math.max(0, tonumber(weaponConfig.KnockbackRecoveryMaxAngularSpeed) or 8),
        VelocityEnforceDuration = math.max(0, tonumber(weaponConfig.KnockbackVelocityEnforceDuration) or 0.16),
        HorizontalVelocity = math.max(0, tonumber(weaponConfig.KnockbackHorizontalVelocity) or 75),
        VerticalVelocity = tonumber(weaponConfig.KnockbackVerticalVelocity) or 35,
        AngularVelocity = math.max(0, tonumber(weaponConfig.KnockbackAngularVelocity) or 0),
        ServerOwnsPhysics = weaponConfig.KnockbackServerOwnsPhysics ~= false,
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

    local knockbackConfig = self:_getConfig()
    self:ApplyCharacterKnockback(attackerPlayer.Character, targetCharacter, knockbackConfig)
end

function WeaponKnockbackService:ApplyCharacterKnockback(attackerCharacter, targetCharacter, knockbackConfig)
    if not targetCharacter then
        return false
    end

    local targetHumanoid = targetCharacter:FindFirstChildOfClass("Humanoid")
    if not targetHumanoid or targetHumanoid.Health <= 0 then
        return false
    end

    local attackerSourceCFrame = getKnockbackSourceCFrame(attackerCharacter)
    local targetRootPart = getRootPartFromCharacter(targetCharacter)
    if not targetRootPart then
        return false
    end

    local baseConfig = self:_getConfig()
    local resolvedConfig = type(knockbackConfig) == "table" and knockbackConfig or baseConfig
    local horizontalVelocity = math.max(
        0,
        tonumber(resolvedConfig.HorizontalVelocity)
            or tonumber(resolvedConfig.horizontalVelocity)
            or tonumber(baseConfig.HorizontalVelocity)
            or 75
    )
    local verticalVelocity = tonumber(resolvedConfig.VerticalVelocity)
    local useImpulseValue = resolvedConfig.UseImpulse
    if useImpulseValue == nil then
        useImpulseValue = resolvedConfig.useImpulse
    end
    if useImpulseValue == nil then
        useImpulseValue = baseConfig.UseImpulse
    end
    local useImpulse = useImpulseValue == true
    local platformStandDuration = math.max(
        0,
        tonumber(resolvedConfig.PlatformStandDuration)
            or tonumber(resolvedConfig.platformStandDuration)
            or tonumber(baseConfig.PlatformStandDuration)
            or 0
    )
    local platformStandDelay = math.max(
        0,
        tonumber(resolvedConfig.PlatformStandDelay)
            or tonumber(resolvedConfig.platformStandDelay)
            or tonumber(baseConfig.PlatformStandDelay)
            or 0
    )
    local ragdollDuration = math.max(
        0,
        tonumber(resolvedConfig.RagdollDuration)
            or tonumber(resolvedConfig.ragdollDuration)
            or tonumber(baseConfig.RagdollDuration)
            or 0
    )
    local fallingDownPulseDuration = math.max(
        0,
        tonumber(resolvedConfig.FallingDownPulseDuration)
            or tonumber(resolvedConfig.fallingDownPulseDuration)
            or tonumber(baseConfig.FallingDownPulseDuration)
            or 0.16
    )
    local recoveryGroundWaitSeconds = math.max(
        0,
        tonumber(resolvedConfig.RecoveryGroundWaitSeconds)
            or tonumber(resolvedConfig.recoveryGroundWaitSeconds)
            or tonumber(baseConfig.RecoveryGroundWaitSeconds)
            or 0
    )
    local recoverySettleTimeoutSeconds = math.max(
        0.05,
        tonumber(resolvedConfig.RecoverySettleTimeoutSeconds)
            or tonumber(resolvedConfig.recoverySettleTimeoutSeconds)
            or tonumber(baseConfig.RecoverySettleTimeoutSeconds)
            or 1.0
    )
    local recoveryMaxLinearSpeed = math.max(
        0,
        tonumber(resolvedConfig.RecoveryMaxLinearSpeed)
            or tonumber(resolvedConfig.recoveryMaxLinearSpeed)
            or tonumber(baseConfig.RecoveryMaxLinearSpeed)
            or 0
    )
    local recoveryMaxAngularSpeed = math.max(
        0,
        tonumber(resolvedConfig.RecoveryMaxAngularSpeed)
            or tonumber(resolvedConfig.recoveryMaxAngularSpeed)
            or tonumber(baseConfig.RecoveryMaxAngularSpeed)
            or 0
    )
    local velocityEnforceDuration = math.max(
        0,
        tonumber(resolvedConfig.VelocityEnforceDuration)
            or tonumber(resolvedConfig.velocityEnforceDuration)
            or tonumber(baseConfig.VelocityEnforceDuration)
            or 0
    )
    local angularVelocity = math.max(
        0,
        tonumber(resolvedConfig.AngularVelocity)
            or tonumber(resolvedConfig.angularVelocity)
            or tonumber(baseConfig.AngularVelocity)
            or 0
    )
    local serverOwnsPhysicsValue = resolvedConfig.ServerOwnsPhysics
    if serverOwnsPhysicsValue == nil then
        serverOwnsPhysicsValue = resolvedConfig.serverOwnsPhysics
    end
    if serverOwnsPhysicsValue == nil then
        serverOwnsPhysicsValue = baseConfig.ServerOwnsPhysics
    end
    local serverOwnsPhysics = serverOwnsPhysicsValue ~= false
    if verticalVelocity == nil then
        verticalVelocity = tonumber(resolvedConfig.verticalVelocity)
            or tonumber(baseConfig.VerticalVelocity)
            or 35
    end

    local horizontalDirection = resolveHorizontalDirectionFromCFrame(attackerSourceCFrame, targetRootPart)
    local desiredVelocity = (horizontalDirection * horizontalVelocity) + Vector3.new(0, verticalVelocity, 0)
    local tumbleAxis = Vector3.new(horizontalDirection.Z, 0, -horizontalDirection.X)
    if tumbleAxis.Magnitude <= 0.001 then
        tumbleAxis = Vector3.new(1, 0, 0)
    else
        tumbleAxis = tumbleAxis.Unit
    end
    local desiredAngularVelocity = tumbleAxis * angularVelocity + Vector3.new(0, angularVelocity * 0.25, 0)

    pcall(function()
        targetHumanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
        targetHumanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
    end)
    targetHumanoid:ChangeState(Enum.HumanoidStateType.Freefall)
    local currentVelocity = targetRootPart.AssemblyLinearVelocity
    if useImpulse then
        local assemblyMass = math.max(1, tonumber(targetRootPart.AssemblyMass) or 1)
        targetRootPart:ApplyImpulse(desiredVelocity * assemblyMass)
    end
    targetRootPart.AssemblyLinearVelocity = Vector3.new(
        desiredVelocity.X,
        math.max(currentVelocity.Y, desiredVelocity.Y),
        desiredVelocity.Z
    )
    enforceAssemblyVelocityForDuration(targetRootPart, desiredVelocity, velocityEnforceDuration)
    if angularVelocity > 0 then
        targetRootPart.AssemblyAngularVelocity = desiredAngularVelocity
    end

    local lockDuration = math.max(ragdollDuration, platformStandDelay + platformStandDuration)
    if lockDuration > 0 then
        local knockdownSerial = (tonumber(self._knockdownSerialByHumanoid[targetHumanoid]) or 0) + 1
        self._knockdownSerialByHumanoid[targetHumanoid] = knockdownSerial
        if type(self._knockdownBaselineByHumanoid[targetHumanoid]) ~= "table" then
            local baselineGettingUpEnabled = true
            local baselineFallingDownEnabled = true
            local baselineRagdollEnabled = true
            pcall(function()
                baselineGettingUpEnabled = targetHumanoid:GetStateEnabled(Enum.HumanoidStateType.GettingUp)
                baselineFallingDownEnabled = targetHumanoid:GetStateEnabled(Enum.HumanoidStateType.FallingDown)
                baselineRagdollEnabled = targetHumanoid:GetStateEnabled(Enum.HumanoidStateType.Ragdoll)
            end)
            self._knockdownBaselineByHumanoid[targetHumanoid] = {
                AutoRotate = targetHumanoid.AutoRotate,
                PlatformStand = targetHumanoid.PlatformStand,
                GettingUpEnabled = baselineGettingUpEnabled,
                FallingDownEnabled = baselineFallingDownEnabled,
                RagdollEnabled = baselineRagdollEnabled,
                NetworkOwnershipPinned = false,
            }
        end
        local baseline = self._knockdownBaselineByHumanoid[targetHumanoid]
        if serverOwnsPhysics and type(baseline) == "table" and baseline.NetworkOwnershipPinned ~= true then
            pcall(function()
                targetRootPart:SetNetworkOwner(nil)
                baseline.NetworkOwnershipPinned = true
            end)
        end
        task.spawn(function()
            local startedAt = os.clock()
            local ragdollEndsAt = startedAt + ragdollDuration
            local platformStandStartsAt = startedAt + platformStandDelay
            local platformStandEndsAt = platformStandStartsAt + platformStandDuration
            local settleDeadlineAt = ragdollEndsAt + recoverySettleTimeoutSeconds
            local groundedStableSince = nil
            local activeStateMode = nil

            while self._knockdownSerialByHumanoid[targetHumanoid] == knockdownSerial do
                if not (targetHumanoid and targetHumanoid.Parent and targetHumanoid.Health > 0 and targetRootPart and targetRootPart.Parent) then
                    break
                end

                local now = os.clock()
                if now < ragdollEndsAt then
                    local stateMode = "freefall"
                    if (now - startedAt) <= fallingDownPulseDuration then
                        stateMode = "fallingdown"
                    elseif now >= platformStandStartsAt and now < platformStandEndsAt then
                        stateMode = "platform"
                    end

                    pcall(function()
                        targetHumanoid.AutoRotate = false
                        targetHumanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
                        targetHumanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
                        targetHumanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)

                        if stateMode ~= activeStateMode then
                            if stateMode == "platform" then
                                targetHumanoid.PlatformStand = true
                                targetHumanoid:ChangeState(Enum.HumanoidStateType.Physics)
                            elseif stateMode == "fallingdown" then
                                targetHumanoid.PlatformStand = false
                                targetHumanoid:ChangeState(Enum.HumanoidStateType.FallingDown)
                            else
                                targetHumanoid.PlatformStand = false
                                targetHumanoid:ChangeState(Enum.HumanoidStateType.Freefall)
                            end
                            activeStateMode = stateMode
                        end

                        if angularVelocity > 0 then
                            targetRootPart.AssemblyAngularVelocity = desiredAngularVelocity
                        end
                    end)
                else
                    if activeStateMode ~= "recovery" then
                        pcall(function()
                            targetHumanoid.PlatformStand = false
                            targetHumanoid:ChangeState(Enum.HumanoidStateType.Freefall)
                        end)
                        activeStateMode = "recovery"
                    end

                    local linearSpeed = targetRootPart.AssemblyLinearVelocity.Magnitude
                    local angularSpeed = targetRootPart.AssemblyAngularVelocity.Magnitude
                    local isGrounded = targetHumanoid.FloorMaterial ~= Enum.Material.Air
                    local isSettled = isGrounded
                        and linearSpeed <= recoveryMaxLinearSpeed
                        and angularSpeed <= recoveryMaxAngularSpeed

                    if isSettled then
                        if not groundedStableSince then
                            groundedStableSince = now
                        elseif now - groundedStableSince >= recoveryGroundWaitSeconds then
                            break
                        end
                    else
                        groundedStableSince = nil
                    end

                    if now >= settleDeadlineAt then
                        break
                    end
                end

                RunService.Heartbeat:Wait()
            end

            if self._knockdownSerialByHumanoid[targetHumanoid] ~= knockdownSerial then
                return
            end

            self._knockdownSerialByHumanoid[targetHumanoid] = nil
            local baseline = self._knockdownBaselineByHumanoid[targetHumanoid]
            self._knockdownBaselineByHumanoid[targetHumanoid] = nil
            if not (targetHumanoid and targetHumanoid.Parent and targetHumanoid.Health > 0) then
                return
            end

            pcall(function()
                local restoredAutoRotate = true
                local restoredPlatformStand = false
                local restoredGettingUpEnabled = true
                local restoredFallingDownEnabled = true
                local restoredRagdollEnabled = true
                local shouldRestoreNetworkOwnership = false
                if type(baseline) == "table" then
                    restoredAutoRotate = baseline.AutoRotate ~= false
                    restoredPlatformStand = baseline.PlatformStand == true
                    restoredGettingUpEnabled = baseline.GettingUpEnabled ~= false
                    restoredFallingDownEnabled = baseline.FallingDownEnabled ~= false
                    restoredRagdollEnabled = baseline.RagdollEnabled ~= false
                    shouldRestoreNetworkOwnership = baseline.NetworkOwnershipPinned == true
                end
                if shouldRestoreNetworkOwnership and targetRootPart and targetRootPart.Parent then
                    pcall(function()
                        targetRootPart:SetNetworkOwnershipAuto()
                    end)
                end
                targetHumanoid.AutoRotate = restoredAutoRotate
                targetHumanoid.PlatformStand = restoredPlatformStand
                targetHumanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, restoredGettingUpEnabled)
                targetHumanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, restoredFallingDownEnabled)
                targetHumanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, restoredRagdollEnabled)
                if targetHumanoid.FloorMaterial ~= Enum.Material.Air then
                    targetHumanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
                else
                    targetHumanoid:ChangeState(Enum.HumanoidStateType.Freefall)
                end
            end)
        end)
    end

    return true
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
