--[[
脚本名字: WeaponService
脚本文件: WeaponService.lua
脚本类型: ModuleScript
本地路径: D:/RobloxGame/BrainrotsTemplate/WeaponService.lua
Studio放置路径: ServerScriptService/Services/WeaponService
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

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
        "[WeaponService] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local GameConfig = requireSharedModule("GameConfig")

local WeaponService = {}
WeaponService._playerDataService = nil
WeaponService._characterConnectionsByUserId = {}
WeaponService._didWarnMissingToolsRoot = false
WeaponService._didWarnMissingStarterFolder = false
WeaponService._didWarnNoWeaponTemplate = false

local function normalizeWeaponId(weaponId)
    local text = tostring(weaponId or "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

local function listContains(list, targetValue)
    if type(list) ~= "table" then
        return false
    end

    for _, value in ipairs(list) do
        if value == targetValue then
            return true
        end
    end

    return false
end

local function getWeaponConfig()
    if type(GameConfig.WEAPON) == "table" then
        return GameConfig.WEAPON
    end

    return {}
end

local function getPlayerContainer(player, containerName)
    if not player then
        return nil
    end

    local container = player:FindFirstChild(containerName)
    if container then
        return container
    end

    local success, waitedContainer = pcall(function()
        return player:WaitForChild(containerName, 5)
    end)

    if success then
        return waitedContainer
    end

    return nil
end

local function configureWeaponToolInstance(tool)
    if not (tool and tool:IsA("Tool")) then
        return
    end

    -- 某些模板会把 ManualActivationOnly 设为 true，导致鼠标点击不触发 Activated。
    -- 统一在发放时改为 false，确保点击可挥击。
    tool.ManualActivationOnly = false
    tool.Enabled = true

    local handle = tool:FindFirstChild("Handle", true)
    if handle and handle:IsA("BasePart") then
        handle.Anchored = false
        handle.CanTouch = true
    end
end

local function normalizeOwnedWeaponIds(rawOwnedWeaponIds)
    local normalizedList = {}
    local lookup = {}

    if type(rawOwnedWeaponIds) ~= "table" then
        return normalizedList, lookup
    end

    for key, value in pairs(rawOwnedWeaponIds) do
        local weaponId = ""

        if type(key) == "number" then
            weaponId = normalizeWeaponId(value)
        elseif value == true then
            weaponId = normalizeWeaponId(key)
        elseif type(value) == "string" then
            weaponId = normalizeWeaponId(value)
        end

        if weaponId ~= "" and not lookup[weaponId] then
            table.insert(normalizedList, weaponId)
            lookup[weaponId] = true
        end
    end

    return normalizedList, lookup
end

function WeaponService:_getOrCreateWeaponState(playerData)
    if type(playerData.WeaponState) ~= "table" then
        playerData.WeaponState = {}
    end

    local weaponState = playerData.WeaponState
    if type(weaponState.StarterWeaponGranted) ~= "boolean" then
        weaponState.StarterWeaponGranted = false
    end

    local ownedWeaponIds = normalizeOwnedWeaponIds(weaponState.OwnedWeaponIds)
    weaponState.OwnedWeaponIds = ownedWeaponIds
    weaponState.EquippedWeaponId = normalizeWeaponId(weaponState.EquippedWeaponId)

    return weaponState
end

function WeaponService:_resolveStarterWeaponContainer()
    local weaponConfig = getWeaponConfig()
    local toolsRootName = tostring(weaponConfig.ToolsRootFolderName or "Tools")
    local starterFolderName = tostring(weaponConfig.StarterWeaponFolderName or "StarterWeapon")

    local toolsRoot = ServerStorage:FindFirstChild(toolsRootName)
    if not toolsRoot then
        if not self._didWarnMissingToolsRoot then
            warn(string.format("[WeaponService] 找不到 ServerStorage/%s，默认武器发放已跳过。", toolsRootName))
            self._didWarnMissingToolsRoot = true
        end
        return nil
    end

    local starterContainer = toolsRoot:FindFirstChild(starterFolderName)
    if not starterContainer then
        if not self._didWarnMissingStarterFolder then
            warn(string.format("[WeaponService] 找不到 ServerStorage/%s/%s，默认武器发放已跳过。", toolsRootName, starterFolderName))
            self._didWarnMissingStarterFolder = true
        end
        return nil
    end

    return starterContainer
end

function WeaponService:_collectWeaponTemplates(starterContainer)
    local templatesById = {}
    local managedNameSet = {}

    local function collectFromInstance(instance)
        if not instance then
            return
        end

        if instance:IsA("Tool") then
            local weaponId = normalizeWeaponId(instance.Name)
            if weaponId ~= "" and not templatesById[weaponId] then
                templatesById[weaponId] = instance
                managedNameSet[weaponId] = true
            end
        end

        for _, child in ipairs(instance:GetChildren()) do
            collectFromInstance(child)
        end
    end

    collectFromInstance(starterContainer)
    return templatesById, managedNameSet
end

function WeaponService:_resolveDefaultWeaponId(templatesById)
    local weaponConfig = getWeaponConfig()
    local configuredWeaponId = normalizeWeaponId(weaponConfig.DefaultWeaponId)
    if configuredWeaponId ~= "" and templatesById[configuredWeaponId] then
        return configuredWeaponId
    end

    local firstWeaponId = nil
    for weaponId, _ in pairs(templatesById) do
        if not firstWeaponId or weaponId < firstWeaponId then
            firstWeaponId = weaponId
        end
    end

    return firstWeaponId
end

function WeaponService:_getWeaponTemplateBundle()
    local starterContainer = self:_resolveStarterWeaponContainer()
    if not starterContainer then
        return nil, {}, {}
    end

    local templatesById, managedNameSet = self:_collectWeaponTemplates(starterContainer)
    if next(templatesById) == nil and not self._didWarnNoWeaponTemplate then
        warn("[WeaponService] StarterWeapon 目录下没有 Tool 模板，默认武器发放已跳过。")
        self._didWarnNoWeaponTemplate = true
    end

    return starterContainer, templatesById, managedNameSet
end

function WeaponService:_getToolMarkerAttributeNames()
    local weaponConfig = getWeaponConfig()
    local isWeaponAttributeName = tostring(weaponConfig.ToolIsWeaponAttributeName or "IsWeaponTool")
    local weaponIdAttributeName = tostring(weaponConfig.ToolWeaponIdAttributeName or "WeaponId")
    return isWeaponAttributeName, weaponIdAttributeName
end

function WeaponService:_markWeaponTool(tool, weaponId)
    if not (tool and tool:IsA("Tool")) then
        return
    end

    local isWeaponAttributeName, weaponIdAttributeName = self:_getToolMarkerAttributeNames()
    tool:SetAttribute(isWeaponAttributeName, true)
    tool:SetAttribute(weaponIdAttributeName, normalizeWeaponId(weaponId))
end

function WeaponService:_isManagedWeaponTool(tool, managedNameSet)
    if not (tool and tool:IsA("Tool")) then
        return false
    end

    local isWeaponAttributeName, weaponIdAttributeName = self:_getToolMarkerAttributeNames()
    if tool:GetAttribute(isWeaponAttributeName) == true then
        return true
    end

    local attributeWeaponId = normalizeWeaponId(tool:GetAttribute(weaponIdAttributeName))
    if attributeWeaponId ~= "" then
        return true
    end

    if type(managedNameSet) == "table" and managedNameSet[tool.Name] then
        return true
    end

    return false
end

function WeaponService:_clearManagedWeaponTools(player, managedNameSet)
    local containers = {
        player and player:FindFirstChild("Backpack") or nil,
        player and player:FindFirstChild("StarterGear") or nil,
        player and player.Character or nil,
    }

    for _, container in ipairs(containers) do
        if container then
            for _, child in ipairs(container:GetChildren()) do
                if self:_isManagedWeaponTool(child, managedNameSet) then
                    child:Destroy()
                end
            end
        end
    end
end

function WeaponService:_applyEquippedWeapon(player, equippedWeaponId, templatesById, managedNameSet)
    local weaponId = normalizeWeaponId(equippedWeaponId)
    if weaponId == "" then
        self:_clearManagedWeaponTools(player, managedNameSet)
        return false
    end

    local template = templatesById[weaponId]
    self:_clearManagedWeaponTools(player, managedNameSet)
    if not (template and template:IsA("Tool")) then
        return false
    end

    local backpack = getPlayerContainer(player, "Backpack")
    local starterGear = getPlayerContainer(player, "StarterGear")

    if backpack then
        local backpackTool = template:Clone()
        configureWeaponToolInstance(backpackTool)
        self:_markWeaponTool(backpackTool, weaponId)
        backpackTool.Parent = backpack
    end

    if starterGear then
        local starterTool = template:Clone()
        configureWeaponToolInstance(starterTool)
        self:_markWeaponTool(starterTool, weaponId)
        starterTool.Parent = starterGear
    end

    return true
end

function WeaponService:_syncPlayerWeaponSlot(player)
    if not self._playerDataService then
        return false, "PlayerDataServiceMissing"
    end

    local playerData = self._playerDataService:GetPlayerData(player)
    if type(playerData) ~= "table" then
        return false, "PlayerDataMissing"
    end

    local _starterContainer, templatesById, managedNameSet = self:_getWeaponTemplateBundle()
    local weaponState = self:_getOrCreateWeaponState(playerData)
    local defaultWeaponId = self:_resolveDefaultWeaponId(templatesById)

    if #weaponState.OwnedWeaponIds <= 0 and defaultWeaponId ~= "" then
        table.insert(weaponState.OwnedWeaponIds, defaultWeaponId)
        weaponState.StarterWeaponGranted = true
    elseif #weaponState.OwnedWeaponIds > 0 and weaponState.StarterWeaponGranted ~= true then
        weaponState.StarterWeaponGranted = true
    end

    local equippedWeaponId = normalizeWeaponId(weaponState.EquippedWeaponId)
    if equippedWeaponId == "" or not listContains(weaponState.OwnedWeaponIds, equippedWeaponId) then
        equippedWeaponId = weaponState.OwnedWeaponIds[1] or ""
    end

    if equippedWeaponId == "" and defaultWeaponId ~= "" then
        equippedWeaponId = defaultWeaponId
        if not listContains(weaponState.OwnedWeaponIds, defaultWeaponId) then
            table.insert(weaponState.OwnedWeaponIds, defaultWeaponId)
        end
        weaponState.StarterWeaponGranted = true
    end

    if equippedWeaponId ~= "" and not templatesById[equippedWeaponId] and defaultWeaponId ~= "" and templatesById[defaultWeaponId] then
        equippedWeaponId = defaultWeaponId
        if not listContains(weaponState.OwnedWeaponIds, defaultWeaponId) then
            table.insert(weaponState.OwnedWeaponIds, defaultWeaponId)
        end
        weaponState.StarterWeaponGranted = true
    end

    weaponState.EquippedWeaponId = equippedWeaponId
    return self:_applyEquippedWeapon(player, equippedWeaponId, templatesById, managedNameSet)
end

function WeaponService:_bindCharacterAdded(player)
    local userId = player.UserId

    local oldConnection = self._characterConnectionsByUserId[userId]
    if oldConnection then
        oldConnection:Disconnect()
        self._characterConnectionsByUserId[userId] = nil
    end

    self._characterConnectionsByUserId[userId] = player.CharacterAdded:Connect(function()
        task.wait(0.1)
        if not player.Parent then
            return
        end

        self:_syncPlayerWeaponSlot(player)
    end)
end

function WeaponService:Init(dependencies)
    self._playerDataService = dependencies.PlayerDataService
end

function WeaponService:OnPlayerReady(player)
    self:_bindCharacterAdded(player)
    self:_syncPlayerWeaponSlot(player)
end

function WeaponService:OnPlayerRemoving(player)
    local connection = self._characterConnectionsByUserId[player.UserId]
    if connection then
        connection:Disconnect()
        self._characterConnectionsByUserId[player.UserId] = nil
    end
end

function WeaponService:GrantWeapon(player, weaponId, options)
    if not self._playerDataService then
        return false, "PlayerDataServiceMissing"
    end

    local normalizedWeaponId = normalizeWeaponId(weaponId)
    if normalizedWeaponId == "" then
        return false, "WeaponIdInvalid"
    end

    local playerData = self._playerDataService:GetPlayerData(player)
    if type(playerData) ~= "table" then
        return false, "PlayerDataMissing"
    end

    local _starterContainer, templatesById = self:_getWeaponTemplateBundle()
    if not templatesById[normalizedWeaponId] then
        return false, "WeaponTemplateMissing"
    end

    local weaponState = self:_getOrCreateWeaponState(playerData)
    if not listContains(weaponState.OwnedWeaponIds, normalizedWeaponId) then
        table.insert(weaponState.OwnedWeaponIds, normalizedWeaponId)
    end

    local shouldAutoEquip = type(options) == "table" and options.AutoEquip == true
    if shouldAutoEquip or normalizeWeaponId(weaponState.EquippedWeaponId) == "" then
        weaponState.EquippedWeaponId = normalizedWeaponId
    end

    if weaponState.StarterWeaponGranted ~= true then
        weaponState.StarterWeaponGranted = true
    end

    self:_syncPlayerWeaponSlot(player)
    return true
end

function WeaponService:EquipWeapon(player, weaponId)
    if not self._playerDataService then
        return false, "PlayerDataServiceMissing"
    end

    local normalizedWeaponId = normalizeWeaponId(weaponId)
    if normalizedWeaponId == "" then
        return false, "WeaponIdInvalid"
    end

    local playerData = self._playerDataService:GetPlayerData(player)
    if type(playerData) ~= "table" then
        return false, "PlayerDataMissing"
    end

    local weaponState = self:_getOrCreateWeaponState(playerData)
    if not listContains(weaponState.OwnedWeaponIds, normalizedWeaponId) then
        return false, "WeaponNotOwned"
    end

    local _starterContainer, templatesById = self:_getWeaponTemplateBundle()
    if not templatesById[normalizedWeaponId] then
        return false, "WeaponTemplateMissing"
    end

    weaponState.EquippedWeaponId = normalizedWeaponId
    self:_syncPlayerWeaponSlot(player)
    return true
end

function WeaponService:GetEquippedWeaponId(player)
    if not self._playerDataService then
        return ""
    end

    local playerData = self._playerDataService:GetPlayerData(player)
    if type(playerData) ~= "table" then
        return ""
    end

    local weaponState = self:_getOrCreateWeaponState(playerData)
    return normalizeWeaponId(weaponState.EquippedWeaponId)
end

function WeaponService:GetOwnedWeaponIds(player)
    if not self._playerDataService then
        return {}
    end

    local playerData = self._playerDataService:GetPlayerData(player)
    if type(playerData) ~= "table" then
        return {}
    end

    local weaponState = self:_getOrCreateWeaponState(playerData)
    local copied = {}
    for _, weaponId in ipairs(weaponState.OwnedWeaponIds) do
        table.insert(copied, weaponId)
    end

    return copied
end


return WeaponService
