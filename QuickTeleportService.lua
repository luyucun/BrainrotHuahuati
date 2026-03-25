--[[
脚本名字: QuickTeleportService
脚本文件: QuickTeleportService.lua
脚本类型: ModuleScript
Studio放置路径: ServerScriptService/Services/QuickTeleportService
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
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
        "[QuickTeleportService] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local GameConfig = requireSharedModule("GameConfig")

local QuickTeleportService = {}
QuickTeleportService._homeService = nil
QuickTeleportService._remoteEventService = nil
QuickTeleportService._requestQuickTeleportEvent = nil
QuickTeleportService._lastRequestClockByUserId = {}
QuickTeleportService._playerRemovingConnection = nil

local DESTINATION_HOME = "Home"
local DESTINATION_SHOP = "Shop"
local DESTINATION_SELL = "Sell"
local DESTINATION_JETPACK = "Jetpack"

local function normalizeDestination(payload)
    local raw = payload
    if type(payload) == "table" then
        raw = payload.target or payload.destination
    end

    local text = string.lower(tostring(raw or ""))
    if text == "home" then
        return DESTINATION_HOME
    end
    if text == "shop" or text == "shop1" or text == "shop01" then
        return DESTINATION_SHOP
    end
    if text == "sell" or text == "shop2" or text == "shop02" then
        return DESTINATION_SELL
    end
    if text == "jetpack" or text == "shop3" or text == "shop03" then
        return DESTINATION_JETPACK
    end

    return nil
end

local function resolveYOffset(config)
    local configured = type(config) == "table" and tonumber(config.YOffset) or nil
    if configured ~= nil then
        return configured
    end

    local fallback = tonumber(GameConfig.QUICK_TELEPORT.DefaultYOffset)
    if fallback ~= nil then
        return fallback
    end

    return 5
end

local function findTouchPart(modelName, touchPartName)
    if type(modelName) ~= "string" or modelName == "" then
        return nil
    end

    local touchName = tostring(touchPartName or "PrisonerTouch")

    local model = Workspace:FindFirstChild(modelName)
    if not model then
        model = Workspace:FindFirstChild(modelName, true)
    end
    if not model then
        return nil
    end

    local directTouch = model:FindFirstChild(touchName)
    if directTouch and directTouch:IsA("BasePart") then
        return directTouch
    end

    local nestedTouch = model:FindFirstChild(touchName, true)
    if nestedTouch and nestedTouch:IsA("BasePart") then
        return nestedTouch
    end

    if model:IsA("BasePart") and model.Name == touchName then
        return model
    end

    return nil
end

function QuickTeleportService:_teleportToCFrame(player, targetCFrame)
    local character = player.Character
    if not character then
        return false
    end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if rootPart and rootPart:IsA("BasePart") then
        rootPart.CFrame = targetCFrame
    else
        character:PivotTo(targetCFrame)
    end

    return true
end

function QuickTeleportService:_teleportToShop(player, shopConfig, destinationLabel)
    local modelName = type(shopConfig) == "table" and shopConfig.ModelName or nil
    local touchPartName = type(shopConfig) == "table" and shopConfig.TouchPartName or nil

    local touchPart = findTouchPart(modelName, touchPartName)
    if not touchPart then
        warn(string.format(
            "[QuickTeleportService] 传送失败，找不到目标节点: %s/%s",
            tostring(modelName),
            tostring(touchPartName or "PrisonerTouch")
        ))
        return false
    end

    local yOffset = resolveYOffset(shopConfig)
    local targetPosition = touchPart.Position + Vector3.new(0, yOffset, 0)

    local lookVector = touchPart.CFrame.LookVector
    local horizontalLook = Vector3.new(lookVector.X, 0, lookVector.Z)
    if horizontalLook.Magnitude <= 0.001 then
        horizontalLook = Vector3.new(0, 0, -1)
    else
        horizontalLook = horizontalLook.Unit
    end

    local targetCFrame = CFrame.new(targetPosition, targetPosition + horizontalLook)
    local success = self:_teleportToCFrame(player, targetCFrame)
    if success then
        return true
    end

    warn(string.format(
        "[QuickTeleportService] 传送失败，角色不存在: %s -> %s",
        tostring(player.Name),
        tostring(destinationLabel)
    ))
    return false
end

function QuickTeleportService:_isRequestTooFrequent(player)
    local debounceSeconds = tonumber(GameConfig.QUICK_TELEPORT.RequestDebounceSeconds) or 0.25
    if debounceSeconds <= 0 then
        return false
    end

    local userId = player.UserId
    local nowClock = os.clock()
    local lastClock = tonumber(self._lastRequestClockByUserId[userId]) or 0
    if nowClock - lastClock < debounceSeconds then
        return true
    end

    self._lastRequestClockByUserId[userId] = nowClock
    return false
end

function QuickTeleportService:_handleTeleportRequest(player, payload)
    if not player or not player.Parent then
        return
    end

    if self:_isRequestTooFrequent(player) then
        return
    end

    local destination = normalizeDestination(payload)
    if not destination then
        return
    end

    if destination == DESTINATION_HOME then
        self._homeService:TeleportPlayerToHomeSpawn(player)
        return
    end

    if destination == DESTINATION_SHOP then
        self:_teleportToShop(player, GameConfig.QUICK_TELEPORT.Shop01, "Shop01")
        return
    end

    if destination == DESTINATION_SELL then
        self:_teleportToShop(player, GameConfig.QUICK_TELEPORT.Shop02, "Shop02")
        return
    end

    if destination == DESTINATION_JETPACK then
        self:_teleportToShop(player, GameConfig.QUICK_TELEPORT.Shop03, "Shop03")
        return
    end
end

function QuickTeleportService:Init(dependencies)
    self._homeService = dependencies.HomeService
    self._remoteEventService = dependencies.RemoteEventService
    self._requestQuickTeleportEvent = self._remoteEventService:GetEvent("RequestQuickTeleport")

    if self._requestQuickTeleportEvent then
        self._requestQuickTeleportEvent.OnServerEvent:Connect(function(player, payload)
            self:_handleTeleportRequest(player, payload)
        end)
    end

    if not self._playerRemovingConnection then
        self._playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
            self._lastRequestClockByUserId[player.UserId] = nil
        end)
    end
end

return QuickTeleportService
