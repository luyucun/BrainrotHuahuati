--[[
脚本名字: ProgressService
脚本文件: ProgressService.lua
脚本类型: ModuleScript
Studio放置路径: ServerScriptService/Services/ProgressService
]]

local Players = game:GetService("Players")
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
        "[ProgressService] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local GameConfig = requireSharedModule("GameConfig")

local ProgressService = {}
ProgressService._homeService = nil
ProgressService._zonePartByLevel = {}
ProgressService._homeBoundsByName = {}
ProgressService._currentLevelByUserId = {}
ProgressService._started = false

local function getConfig()
    return GameConfig.PROGRESS or {}
end

local function getPlayerAttributeName()
    return tostring(getConfig().PlayerAttributeName or "ProgressLevel")
end

local function getUpdateIntervalSeconds()
    return math.max(0.1, tonumber(getConfig().UpdateIntervalSeconds) or 0.25)
end

local function getFloatLandCount()
    return math.max(0, math.floor(tonumber(getConfig().FloatLandCount) or 9))
end

local function clampProgressLevel(level)
    return math.clamp(math.floor(tonumber(level) or 0), 0, getFloatLandCount())
end

local function parseFloatLandLevel(folderName)
    local name = tostring(folderName or "")
    local prefix = tostring(getConfig().FloatLandFolderPrefix or "FloatLand")
    if string.sub(name, 1, #prefix) ~= prefix then
        return 0
    end

    local suffix = string.sub(name, #prefix + 1)
    local firstDigit = string.match(suffix, "^(%d)")
    return clampProgressLevel(firstDigit)
end

local function getLandRootFolder()
    local folderName = tostring(getConfig().LandRootFolderName or "Land")
    local direct = Workspace:FindFirstChild(folderName)
    if direct then
        return direct
    end

    return Workspace:FindFirstChild(folderName, true)
end

local function getCharacterRootPart(player)
    local character = player and player.Character
    if not (character and character.Parent) then
        return nil
    end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if rootPart and rootPart:IsA("BasePart") then
        return rootPart
    end

    return nil
end

local function isPointInsidePartBounds(point, part, paddingXZ, paddingY)
    if not (part and part:IsA("BasePart")) then
        return false
    end

    local localPoint = part.CFrame:PointToObjectSpace(point)
    local halfSize = part.Size * 0.5
    return math.abs(localPoint.X) <= (halfSize.X + paddingXZ)
        and math.abs(localPoint.Z) <= (halfSize.Z + paddingXZ)
        and math.abs(localPoint.Y) <= (halfSize.Y + paddingY)
end

local function computeBoundsFromDescendants(root)
    if not root then
        return nil
    end

    local minVector = nil
    local maxVector = nil

    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant:IsA("BasePart") then
            local halfSize = descendant.Size * 0.5
            local partMin = descendant.Position - halfSize
            local partMax = descendant.Position + halfSize

            if not minVector then
                minVector = partMin
                maxVector = partMax
            else
                minVector = Vector3.new(
                    math.min(minVector.X, partMin.X),
                    math.min(minVector.Y, partMin.Y),
                    math.min(minVector.Z, partMin.Z)
                )
                maxVector = Vector3.new(
                    math.max(maxVector.X, partMax.X),
                    math.max(maxVector.Y, partMax.Y),
                    math.max(maxVector.Z, partMax.Z)
                )
            end
        end
    end

    if not (minVector and maxVector) then
        return nil
    end

    return {
        min = minVector,
        max = maxVector,
    }
end

local function isPointInsideBounds(point, bounds, paddingXZ, paddingY)
    if type(bounds) ~= "table" or not (bounds.min and bounds.max) then
        return false
    end

    return point.X >= (bounds.min.X - paddingXZ)
        and point.X <= (bounds.max.X + paddingXZ)
        and point.Z >= (bounds.min.Z - paddingXZ)
        and point.Z <= (bounds.max.Z + paddingXZ)
        and point.Y >= (bounds.min.Y - paddingY)
        and point.Y <= (bounds.max.Y + paddingY)
end

function ProgressService:_warnMissingFloatLand(level)
    warn(string.format("[ProgressService] Missing FloatLand%d/Land; progress zones will skip this level.", level))
end

function ProgressService:_rebuildFloatLandParts()
    table.clear(self._zonePartByLevel)

    local landRoot = getLandRootFolder()
    if not landRoot then
        warn("[ProgressService] Missing Workspace/Land; progress service is disabled.")
        return
    end

    local landPartName = tostring(getConfig().FloatLandPartName or "Land")
    for _, child in ipairs(landRoot:GetChildren()) do
        if child:IsA("Folder") then
            local level = parseFloatLandLevel(child.Name)
            local zonePart = level > 0 and child:FindFirstChild(landPartName) or nil
            if zonePart and zonePart:IsA("BasePart") then
                local bucket = self._zonePartByLevel[level]
                if not bucket then
                    bucket = {}
                    self._zonePartByLevel[level] = bucket
                end
                table.insert(bucket, zonePart)
            end
        end
    end

    for level = 1, getFloatLandCount() do
        local bucket = self._zonePartByLevel[level]
        if not bucket or #bucket <= 0 then
            self:_warnMissingFloatLand(level)
        end
    end
end

function ProgressService:_getHomeBounds(player)
    local home = self._homeService and self._homeService:GetAssignedHome(player) or nil
    if not home then
        return nil
    end

    local homeName = tostring(home.Name or "")
    local cachedBounds = self._homeBoundsByName[homeName]
    if cachedBounds then
        return cachedBounds
    end

    local computedBounds = computeBoundsFromDescendants(home)
    self._homeBoundsByName[homeName] = computedBounds
    return computedBounds
end

function ProgressService:_resolveTargetLevel(player)
    local rootPart = getCharacterRootPart(player)
    if not rootPart then
        return 0
    end

    local rootPosition = rootPart.Position
    local homeBounds = self:_getHomeBounds(player)
    if isPointInsideBounds(
        rootPosition,
        homeBounds,
        math.max(0, tonumber(getConfig().HomeBoundsPaddingXZ) or 18),
        math.max(0, tonumber(getConfig().HomeBoundsPaddingY) or 40)
    ) then
        return 0
    end

    local floatLandPaddingXZ = math.max(0, tonumber(getConfig().FloatLandBoundsPaddingXZ) or 18)
    local floatLandPaddingY = math.max(0, tonumber(getConfig().FloatLandBoundsPaddingY) or 180)
    for level = 1, getFloatLandCount() do
        local bucket = self._zonePartByLevel[level]
        if bucket then
            for _, zonePart in ipairs(bucket) do
                if isPointInsidePartBounds(rootPosition, zonePart, floatLandPaddingXZ, floatLandPaddingY) then
                    return level
                end
            end
        end
    end

    return clampProgressLevel(self._currentLevelByUserId[player.UserId])
end

function ProgressService:_applyLevel(player, level)
    if not player then
        return
    end

    local normalizedLevel = clampProgressLevel(level)
    self._currentLevelByUserId[player.UserId] = normalizedLevel
    player:SetAttribute(getPlayerAttributeName(), normalizedLevel)
end

function ProgressService:_refreshPlayer(player)
    if not player then
        return
    end

    local currentLevel = clampProgressLevel(self._currentLevelByUserId[player.UserId])
    local nextLevel = self:_resolveTargetLevel(player)
    if currentLevel ~= nextLevel or player:GetAttribute(getPlayerAttributeName()) == nil then
        self:_applyLevel(player, nextLevel)
    end
end

function ProgressService:_startUpdateLoop()
    if self._started then
        return
    end

    self._started = true
    task.spawn(function()
        while true do
            task.wait(getUpdateIntervalSeconds())
            for _, player in ipairs(Players:GetPlayers()) do
                self:_refreshPlayer(player)
            end
        end
    end)
end

function ProgressService:Init(dependencies)
    self._homeService = dependencies.HomeService
    self:_rebuildFloatLandParts()
    self:_startUpdateLoop()
end

function ProgressService:OnPlayerReady(player)
    self:_applyLevel(player, 0)
end

function ProgressService:OnPlayerRemoving(player)
    if not player then
        return
    end

    self._currentLevelByUserId[player.UserId] = nil
    player:SetAttribute(getPlayerAttributeName(), nil)
end

return ProgressService
