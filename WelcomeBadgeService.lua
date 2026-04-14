--[[
Script: WelcomeBadgeService
Type: ModuleScript
Studio path: ServerScriptService/Services/WelcomeBadgeService
]]

local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FIRST_JOIN_BADGE_ID = 2016530467612071
local MAX_AWARD_ATTEMPTS = 3

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
		"[WelcomeBadgeService] Missing shared module %s",
		moduleName
	))
end

local GameConfig = requireSharedModule("GameConfig")

local WelcomeBadgeService = {}
WelcomeBadgeService._playerDataService = nil
WelcomeBadgeService._attemptedAwardByUserId = {}

local function waitForRetry(attempt)
	task.wait(math.max(0.5, tonumber((GameConfig.DATASTORE or {}).RetryDelay) or 0.5) * attempt)
end

function WelcomeBadgeService:Init(dependencies)
	self._playerDataService = type(dependencies) == "table" and dependencies.PlayerDataService or nil
end

function WelcomeBadgeService:_playerHasBadge(player)
	local ok, hasBadge = pcall(function()
		return BadgeService:UserHasBadgeAsync(player.UserId, FIRST_JOIN_BADGE_ID)
	end)
	if ok then
		return hasBadge == true, nil
	end

	return nil, tostring(hasBadge)
end

function WelcomeBadgeService:_awardFirstJoinBadge(player)
	for attempt = 1, MAX_AWARD_ATTEMPTS do
		local ok, result = pcall(function()
			return BadgeService:AwardBadge(player.UserId, FIRST_JOIN_BADGE_ID)
		end)
		if ok and result == true then
			return true
		end

		local hasBadge, hasBadgeErr = self:_playerHasBadge(player)
		if hasBadge == true then
			return true
		end

		if attempt < MAX_AWARD_ATTEMPTS then
			waitForRetry(attempt)
		else
			warn(string.format(
				"[WelcomeBadgeService] Failed to award first-join badge userId=%d badgeId=%d attempt=%d awardResult=%s hasBadgeErr=%s",
				player.UserId,
				FIRST_JOIN_BADGE_ID,
				attempt,
				tostring(result),
				tostring(hasBadgeErr)
			))
		end
	end

	return false
end

function WelcomeBadgeService:OnPlayerReady(player)
	if not (player and self._playerDataService) then
		return
	end

	if RunService:IsStudio() then
		return
	end

	if self._attemptedAwardByUserId[player.UserId] then
		return
	end
	self._attemptedAwardByUserId[player.UserId] = true

	if not self._playerDataService:WasProfileCreatedThisSession(player) then
		return
	end

	task.spawn(function()
		self:_awardFirstJoinBadge(player)
	end)
end

function WelcomeBadgeService:OnPlayerRemoving(player)
	if not player then
		return
	end

	self._attemptedAwardByUserId[player.UserId] = nil
end

return WelcomeBadgeService
