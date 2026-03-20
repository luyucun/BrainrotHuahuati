--[[
脚本名字: GMCommandService
脚本文件: GMCommandService.lua
脚本类型: ModuleScript
本地路径: D:/RobloxGame/BrainrotsTemplate/GMCommandService.lua
Studio放置路径: ServerScriptService/Services/GMCommandService
]]

local RunService = game:GetService("RunService")
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
        "[GMCommandService] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local GameConfig = requireSharedModule("GameConfig")
local BrainrotConfig = requireSharedModule("BrainrotConfig")

local GMCommandService = {}
GMCommandService._currencyService = nil
GMCommandService._brainrotService = nil
GMCommandService._homeExpansionService = nil
GMCommandService._playerDataService = nil
GMCommandService._homeService = nil
GMCommandService._weaponService = nil
GMCommandService._rebirthService = nil
GMCommandService._globalLeaderboardService = nil
GMCommandService._specialEventService = nil
GMCommandService._connections = {}

local function isPositiveIntegerString(text)
    return type(text) == "string" and text:match("^%d+$") ~= nil
end

local function clearAllTools(player)
    local containers = {
        player:FindFirstChild("Backpack"),
        player.Character,
        player:FindFirstChild("StarterGear"),
    }

    for _, container in ipairs(containers) do
        if container then
            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("Tool") then
                    child:Destroy()
                end
            end
        end
    end
end

function GMCommandService:Init(dependencies, maybeBrainrotService)
    if type(dependencies) == "table" and (dependencies.CurrencyService or dependencies.BrainrotService) then
        self._currencyService = dependencies.CurrencyService
        self._brainrotService = dependencies.BrainrotService
        self._homeExpansionService = dependencies.HomeExpansionService
        self._playerDataService = dependencies.PlayerDataService
        self._homeService = dependencies.HomeService
        self._weaponService = dependencies.WeaponService
        self._rebirthService = dependencies.RebirthService
        self._globalLeaderboardService = dependencies.GlobalLeaderboardService
        self._specialEventService = dependencies.SpecialEventService
        return
    end

    self._currencyService = dependencies
    self._brainrotService = maybeBrainrotService
end

function GMCommandService:IsDeveloper(player)
    if GameConfig.GM.AllowAllUsers then
        return true
    end

    if GameConfig.GM.DeveloperUserIds[player.UserId] then
        return true
    end

    if game.CreatorType == Enum.CreatorType.User then
        return player.UserId == game.CreatorId
    end

    if game.CreatorType == Enum.CreatorType.Group then
        local success, rank = pcall(function()
            return player:GetRankInGroup(game.CreatorId)
        end)
        if success and rank >= GameConfig.GM.GroupAdminRankThreshold then
            return true
        end
    end

    return false
end

function GMCommandService:_handleCommand(player, message)
    if GameConfig.GM.EnabledOnlyInStudio and not RunService:IsStudio() then
        return
    end

    local normalizedMessage = string.lower(tostring(message))
    local amountText = string.match(normalizedMessage, "^/addcoins%s+([%-%d]+)$")
    local brainrotIdText, quantityText = string.match(normalizedMessage, "^/addbrainrot%s+([%-%d]+)%s+([%-%d]+)$")
    local clearCommand = string.match(normalizedMessage, "^/clear%s*$")
    local eventIdText = string.match(normalizedMessage, "^/event%s+([%-%d]+)$")
    if not amountText and not brainrotIdText and not clearCommand and not eventIdText then
        return
    end

    if not self:IsDeveloper(player) then
        warn(string.format("[GMCommandService] %s(%d) 无权限执行 GM 命令", player.Name, player.UserId))
        return
    end

    if amountText then
        if not self._currencyService then
            warn("[GMCommandService] CurrencyService 未初始化，/addcoins 无法执行")
            return
        end

        if not isPositiveIntegerString(amountText) then
            warn(string.format("[GMCommandService] /addcoins 参数非法: %s", tostring(amountText)))
            return
        end

        local amount = tonumber(amountText)
        if not amount or amount <= 0 then
            return
        end

        local success = self._currencyService:AddCoins(player, amount, "GMCommand")
        if success then
            print(string.format("[GMCommandService] %s 执行 /addcoins %d 成功", player.Name, amount))
        end
        return
    end

    if eventIdText then
        if not self._specialEventService then
            warn("[GMCommandService] SpecialEventService 未初始化，/event 无法执行")
            return
        end

        if not isPositiveIntegerString(eventIdText) then
            warn(string.format("[GMCommandService] /event 参数非法: %s", tostring(eventIdText)))
            return
        end

        local eventId = tonumber(eventIdText)
        if not eventId or eventId <= 0 then
            return
        end

        local success, errCode, activeEvent = self._specialEventService:TriggerManualEventById(eventId)
        if success then
            print(string.format(
                "[GMCommandService] %s 执行 /event %d 成功（事件=%s 持续=%ds）",
                player.Name,
                eventId,
                tostring(activeEvent and activeEvent.EventConfig and activeEvent.EventConfig.Name or eventId),
                tonumber(activeEvent and activeEvent.EventConfig and activeEvent.EventConfig.DurationSeconds) or 0
            ))
        else
            warn(string.format(
                "[GMCommandService] %s 执行 /event %d 失败 err=%s",
                player.Name,
                eventId,
                tostring(errCode)
            ))
        end
        return
    end

    if clearCommand then
        if not self._playerDataService then
            warn("[GMCommandService] PlayerDataService 未初始化，/clear 无法执行")
            return
        end

        local assignedHome = self._homeService and self._homeService:GetAssignedHome(player) or nil

        if self._brainrotService then
            self._brainrotService:OnPlayerRemoving(player)
        end
        if self._homeExpansionService then
            self._homeExpansionService:OnPlayerRemoving(player, assignedHome)
        end
        if self._rebirthService then
            self._rebirthService:OnPlayerRemoving(player)
        end
        clearAllTools(player)

        local resetData = self._playerDataService:ResetPlayerData(player)
        if not resetData then
            warn(string.format("[GMCommandService] %s 执行 /clear 失败：重置数据返回空", player.Name))
            return
        end

        if type(resetData.BrainrotData) == "table" then
            resetData.BrainrotData.StarterGranted = true
            resetData.BrainrotData.Inventory = {}
            resetData.BrainrotData.EquippedInstanceId = 0
            resetData.BrainrotData.NextInstanceId = 1
        end

        if assignedHome then
            self._playerDataService:SetHomeId(player, assignedHome.Name)
        end

        if self._rebirthService then
            self._rebirthService:OnPlayerReady(player)
        end
        if self._homeExpansionService then
            self._homeExpansionService:OnPlayerReady(player, assignedHome)
        end

        if self._brainrotService then
            self._brainrotService:OnPlayerReady(player, assignedHome)
        end

        clearAllTools(player)

        if self._weaponService then
            self._weaponService:OnPlayerReady(player)
        end

        if self._currencyService then
            self._currencyService:OnPlayerReady(player)
        end

        if self._globalLeaderboardService then
            self._globalLeaderboardService:OnPlayerReady(player)
        end

        local saved = self._playerDataService:SavePlayerData(player, {
            ForceDataStoreWrite = true,
        })
        if saved then
            print(string.format("[GMCommandService] %s 执行 /clear 成功（已清空个人数据）", player.Name))
        else
            warn(string.format("[GMCommandService] %s 执行 /clear 完成但保存失败", player.Name))
        end
        return
    end

    if not self._brainrotService then
        warn("[GMCommandService] BrainrotService 未初始化，/addbrainrot 无法执行")
        return
    end

    if not isPositiveIntegerString(brainrotIdText) or not isPositiveIntegerString(quantityText) then
        warn(string.format(
            "[GMCommandService] /addbrainrot 参数非法: id=%s quantity=%s",
            tostring(brainrotIdText),
            tostring(quantityText)
        ))
        return
    end

    local brainrotId = tonumber(brainrotIdText)
    local quantity = tonumber(quantityText)
    if not brainrotId or not quantity or brainrotId <= 0 or quantity <= 0 then
        return
    end

    if not BrainrotConfig.ById[brainrotId] then
        warn(string.format("[GMCommandService] /addbrainrot 脑红ID不存在: %d", brainrotId))
        return
    end

    local success, errCode, grantedCount = self._brainrotService:GrantBrainrot(player, brainrotId, quantity, "GMCommand")
    if success then
        print(string.format(
            "[GMCommandService] %s 执行 /addbrainrot %d %d 成功（实际发放=%d）",
            player.Name,
            brainrotId,
            quantity,
            grantedCount or 0
        ))
    else
        warn(string.format(
            "[GMCommandService] %s 执行 /addbrainrot %d %d 失败 err=%s",
            player.Name,
            brainrotId,
            quantity,
            tostring(errCode)
        ))
    end
end

function GMCommandService:BindPlayer(player)
    if self._connections[player.UserId] then
        self._connections[player.UserId]:Disconnect()
    end

    self._connections[player.UserId] = player.Chatted:Connect(function(message)
        self:_handleCommand(player, message)
    end)
end

function GMCommandService:UnbindPlayer(player)
    local connection = self._connections[player.UserId]
    if connection then
        connection:Disconnect()
        self._connections[player.UserId] = nil
    end
end

return GMCommandService
