--[[
脚本名字: GlobalLeaderboardController
脚本文件: GlobalLeaderboardController.lua
脚本类型: ModuleScript
Studio放置路径: StarterPlayer/StarterPlayerScripts/Controllers/GlobalLeaderboardController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
        "[GlobalLeaderboardController] 缺少共享模块 %s（应放在 ReplicatedStorage/Shared 或 ReplicatedStorage 根目录）",
        moduleName
    ))
end

local GameConfig = requireSharedModule("GameConfig")
local FormatUtil = requireSharedModule("FormatUtil")

local GlobalLeaderboardController = {}
GlobalLeaderboardController.__index = GlobalLeaderboardController

local STARTUP_SILENT_REFRESH_DELAYS = { 0, 0.25, 1, 2 }
local STARTUP_WARNING_GRACE_SECONDS = STARTUP_SILENT_REFRESH_DELAYS[#STARTUP_SILENT_REFRESH_DELAYS]

local function findFirstDescendantByNames(root, names)
    if not root then
        return nil
    end

    for _, name in ipairs(names or {}) do
        local direct = root:FindFirstChild(name)
        if direct then
            return direct
        end
    end

    for _, name in ipairs(names or {}) do
        local nested = root:FindFirstChild(name, true)
        if nested then
            return nested
        end
    end

    return nil
end

local function findFirstTextLabel(root, name)
    local node = root and findFirstDescendantByNames(root, { name }) or nil
    if node and node:IsA("TextLabel") then
        return node
    end

    if node then
        local nested = node:FindFirstChildWhichIsA("TextLabel", true)
        if nested then
            return nested
        end
    end

    return root and root:FindFirstChildWhichIsA("TextLabel", true) or nil
end

local function findFirstImageLabel(root, name)
    local node = root and findFirstDescendantByNames(root, { name }) or nil
    if node and node:IsA("ImageLabel") then
        return node
    end

    if node then
        local nested = node:FindFirstChildWhichIsA("ImageLabel", true)
        if nested then
            return nested
        end
    end

    return root and root:FindFirstChildWhichIsA("ImageLabel", true) or nil
end

function GlobalLeaderboardController.new()
    local self = setmetatable({}, GlobalLeaderboardController)
    self._started = false
    self._connections = {}
    self._didWarnByKey = {}
    self._localAvatarImage = nil
    self._startupWarnAt = 0
    return self
end

function GlobalLeaderboardController:_warnOnce(key, message)
    if self._didWarnByKey[key] then
        return
    end

    self._didWarnByKey[key] = true
    warn(message)
end

function GlobalLeaderboardController:_getConfig()
    return GameConfig.LEADERBOARD or {}
end

function GlobalLeaderboardController:_getBoardModelName(boardKey)
    local config = self:_getConfig()
    local boardModels = type(config.BoardModels) == "table" and config.BoardModels or {}
    return tostring(boardModels[boardKey] or (boardKey == "Production" and "Leaderboard01" or "Leaderboard02"))
end

function GlobalLeaderboardController:_getAttributeName(attributeKey)
    local config = self:_getConfig()
    local attributes = type(config.PlayerAttributes) == "table" and config.PlayerAttributes or {}
    return tostring(attributes[attributeKey] or "")
end

function GlobalLeaderboardController:_shouldWarnBoardIssues()
    return os.clock() >= (self._startupWarnAt or 0)
end

function GlobalLeaderboardController:_getPlayerFrame(boardKey, allowWarn)
    local boardModelName = self:_getBoardModelName(boardKey)
    local boardModel = Workspace:FindFirstChild(boardModelName) or Workspace:FindFirstChild(boardModelName, true)
    if not boardModel then
        if allowWarn then
            self:_warnOnce("MissingBoardModel:" .. tostring(boardKey), "[GlobalLeaderboardController] 找不到排行榜模型 " .. boardModelName .. "。")
        end
        return nil
    end

    local mainNode = findFirstDescendantByNames(boardModel, { "Main" })
    local surfaceGui = mainNode and findFirstDescendantByNames(mainNode, { "SurfaceGui" }) or nil
    local frame = surfaceGui and findFirstDescendantByNames(surfaceGui, { "Frame" }) or nil
    local playerFrame = frame and findFirstDescendantByNames(frame, { "Player" }) or nil
    if not playerFrame then
        if allowWarn then
            self:_warnOnce("MissingPlayerFrame:" .. tostring(boardKey), "[GlobalLeaderboardController] " .. boardModelName .. " 缺少 Frame/Player 结构。")
        end
        return nil
    end

    return playerFrame
end

function GlobalLeaderboardController:_getLocalAvatarImage()
    if self._localAvatarImage then
        return self._localAvatarImage
    end

    local success, image = pcall(function()
        local thumbnail, _isReady = Players:GetUserThumbnailAsync(localPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
        return thumbnail
    end)
    if success and type(image) == "string" then
        self._localAvatarImage = image
        return image
    end

    return ""
end

function GlobalLeaderboardController:_formatBoardValue(boardKey, rawValue)
    if boardKey == "Playtime" then
        return FormatUtil.FormatDurationDaysHoursMinutes(rawValue)
    end

    return FormatUtil.FormatCompactCurrencyPerSecond(rawValue)
end

function GlobalLeaderboardController:_refreshBoard(boardKey, allowWarn)
    if allowWarn == nil then
        allowWarn = self:_shouldWarnBoardIssues()
    end

    local playerFrame = self:_getPlayerFrame(boardKey, allowWarn)
    if not playerFrame then
        return
    end

    local avatarLabel = findFirstImageLabel(playerFrame, "Avatar")
    local nameLabel = findFirstTextLabel(playerFrame, "Name")
    local numLabel = findFirstTextLabel(playerFrame, "Num")
    local rankLabel = findFirstTextLabel(playerFrame, "Rank")

    if avatarLabel then
        avatarLabel.Image = self:_getLocalAvatarImage()
    end
    if nameLabel then
        nameLabel.Text = localPlayer.Name
    end

    local valueAttributeName = self:_getAttributeName(boardKey == "Production" and "ProductionValue" or "PlaytimeValue")
    local rankAttributeName = self:_getAttributeName(boardKey == "Production" and "ProductionRank" or "PlaytimeRank")
    local value = valueAttributeName ~= "" and localPlayer:GetAttribute(valueAttributeName) or 0
    local rankText = rankAttributeName ~= "" and localPlayer:GetAttribute(rankAttributeName) or nil

    if numLabel then
        numLabel.Text = self:_formatBoardValue(boardKey, value or 0)
    end
    if rankLabel then
        rankLabel.Text = tostring(rankText or (self:_getConfig().PendingRankText or "--"))
    end
end

function GlobalLeaderboardController:_refreshAllBoards(allowWarn)
    self:_refreshBoard("Production", allowWarn)
    self:_refreshBoard("Playtime", allowWarn)
end

function GlobalLeaderboardController:_scheduleStartupRefreshes()
    for _, delaySeconds in ipairs(STARTUP_SILENT_REFRESH_DELAYS) do
        task.delay(delaySeconds, function()
            if self._started then
                self:_refreshAllBoards()
            end
        end)
    end
end

function GlobalLeaderboardController:Start()
    if self._started then
        return
    end
    self._started = true
    self._startupWarnAt = os.clock() + STARTUP_WARNING_GRACE_SECONDS

    for _, attributeKey in ipairs({ "ProductionValue", "ProductionRank", "PlaytimeValue", "PlaytimeRank" }) do
        local attributeName = self:_getAttributeName(attributeKey)
        if attributeName ~= "" then
            table.insert(self._connections, localPlayer:GetAttributeChangedSignal(attributeName):Connect(function()
                self:_refreshAllBoards()
            end))
        end
    end

    table.insert(self._connections, Workspace.ChildAdded:Connect(function(child)
        if child.Name == self:_getBoardModelName("Production") or child.Name == self:_getBoardModelName("Playtime") then
            task.defer(function()
                self:_refreshAllBoards()
            end)
        end
    end))

    self:_scheduleStartupRefreshes()
end

return GlobalLeaderboardController
