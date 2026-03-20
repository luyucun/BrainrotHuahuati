--[[
脚本名字: HomeService
脚本文件: HomeService.lua
脚本类型: ModuleScript
本地路径: D:/RobloxGame/BrainrotsTemplate/HomeService.lua
Studio放置路径: ServerScriptService/Services/HomeService
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
        "[HomeService] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local GameConfig = requireSharedModule("GameConfig")

local HomeService = {}
HomeService._homeByName = {}
HomeService._playerHomeByUserId = {}
HomeService._occupiedByHomeName = {}
HomeService._characterConnections = {}
HomeService._rng = Random.new()

local function buildHomeName(index)
    return string.format("%s%02d", GameConfig.HOME.Prefix, index)
end

local function getSpawnLocationFromHome(homeModel)
    if not homeModel then
        return nil
    end

    local homeBase = homeModel:FindFirstChild(GameConfig.HOME.HomeBaseName)
    if not homeBase then
        return nil
    end

    local spawnLocation = homeBase:FindFirstChild(GameConfig.HOME.SpawnLocationName)
    if spawnLocation and spawnLocation:IsA("SpawnLocation") then
        return spawnLocation
    end

    return nil
end

function HomeService:Init()
    local container = Workspace:WaitForChild(GameConfig.HOME.ContainerName)
    for index = 1, GameConfig.HOME.Count do
        local homeName = buildHomeName(index)
        local homeModel = container:FindFirstChild(homeName)
        if homeModel then
            self._homeByName[homeName] = homeModel
        else
            warn(string.format("[HomeService] 缺少家园模型: %s", homeName))
        end
    end
end

function HomeService:_bindCharacterSpawn(player)
    local userId = player.UserId
    if self._characterConnections[userId] then
        self._characterConnections[userId]:Disconnect()
    end

    self._characterConnections[userId] = player.CharacterAdded:Connect(function()
        task.wait(0.05)
        self:TeleportPlayerToHomeSpawn(player)
    end)
end

function HomeService:AssignHome(player)
    if self._playerHomeByUserId[player.UserId] then
        return self._playerHomeByUserId[player.UserId]
    end

    local availableHomeNames = {}
    for index = 1, GameConfig.HOME.Count do
        local homeName = buildHomeName(index)
        if not self._occupiedByHomeName[homeName] then
            local homeModel = self._homeByName[homeName]
            if homeModel then
                table.insert(availableHomeNames, homeName)
            end
        end
    end

    if #availableHomeNames <= 0 then
        return nil
    end

    local selectedIndex = self._rng:NextInteger(1, #availableHomeNames)
    local selectedHomeName = availableHomeNames[selectedIndex]
    local selectedHomeModel = self._homeByName[selectedHomeName]
    if not selectedHomeModel then
        return nil
    end

    self._occupiedByHomeName[selectedHomeName] = player.UserId
    self._playerHomeByUserId[player.UserId] = selectedHomeModel
    player:SetAttribute("HomeId", selectedHomeName)

    local spawnLocation = getSpawnLocationFromHome(selectedHomeModel)
    if spawnLocation then
        player.RespawnLocation = spawnLocation
    else
        warn(string.format("[HomeService] %s 缺少 SpawnLocation", selectedHomeName))
    end

    self:_bindCharacterSpawn(player)
    return selectedHomeModel
end

function HomeService:GetAssignedHome(player)
    return self._playerHomeByUserId[player.UserId]
end

function HomeService:GetHomeByName(homeName)
    return self._homeByName[tostring(homeName or "")]
end

function HomeService:GetAllHomes()
    local homes = {}
    for index = 1, GameConfig.HOME.Count do
        local homeName = buildHomeName(index)
        local homeModel = self._homeByName[homeName]
        if homeModel then
            table.insert(homes, homeModel)
        end
    end

    return homes
end

function HomeService:GetHomeOwnerUserId(homeOrName)
    local homeName = nil
    if typeof(homeOrName) == "Instance" then
        homeName = homeOrName.Name
    else
        homeName = tostring(homeOrName or "")
    end

    local ownerUserId = self._occupiedByHomeName[homeName]
    if type(ownerUserId) ~= "number" then
        return nil
    end

    return ownerUserId
end

function HomeService:TeleportPlayerToHomeSpawn(player)
    local home = self:GetAssignedHome(player)
    local spawnLocation = getSpawnLocationFromHome(home)
    local character = player.Character
    if not spawnLocation or not character then
        return
    end

    local targetCFrame = spawnLocation.CFrame + Vector3.new(0, 3, 0)
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if rootPart then
        rootPart.CFrame = targetCFrame
    else
        character:PivotTo(targetCFrame)
    end
end

function HomeService:ReleaseHome(player)
    local userId = player.UserId
    local home = self._playerHomeByUserId[userId]
    if home then
        self._occupiedByHomeName[home.Name] = nil
        self._playerHomeByUserId[userId] = nil
    end

    if self._characterConnections[userId] then
        self._characterConnections[userId]:Disconnect()
        self._characterConnections[userId] = nil
    end

    player.RespawnLocation = nil
    player:SetAttribute("HomeId", nil)
end

function HomeService:GetRemainingHomeCount()
    local occupiedCount = 0
    for _homeName, _userId in pairs(self._occupiedByHomeName) do
        occupiedCount += 1
    end

    return math.max(0, GameConfig.HOME.Count - occupiedCount)
end

return HomeService
