--[[
脚本名字: GameConfig
脚本文件: GameConfig.lua
脚本类型: ModuleScript
Studio放置路径: ReplicatedStorage/Shared/GameConfig
]]

local RunService = game:GetService("RunService")

local GameConfig = {}

GameConfig.VERSION = "V4.0.0"

GameConfig.MAX_SERVER_PLAYERS = 5

GameConfig.HOME = {
	ContainerName = "PlayerHome",
	Prefix = "Home",
	Count = 5,
	HomeBaseName = "HomeBase",
	SpawnLocationName = "SpawnLocation",
}

GameConfig.HOME_EXPANSION = {
	BaseSlotCount = 10,
	SlotsPerFloor = 10,
	MaxFloorLevel = 3,
	StaticFloorNameByLevel = {
		[2] = { "HomeFloor1", "HomeFloor01" },
		[3] = { "HomeFloor2", "HomeFloor02", "HomeFloor3", "HomeFloor03" },
	},
	TemplateName = "HomeFloor",
	RuntimeFloorPrefix = "HomeFloorRuntime",
	RuntimeFloorLevelAttributeName = "HomeExpansionFloorLevel",
	RuntimeLocalSlotIndexAttributeName = "HomeExpansionLocalSlotIndex",
	RuntimeGlobalSlotIndexAttributeName = "HomeExpansionGlobalSlotIndex",
	RuntimePositionKeyAttributeName = "HomeExpansionPositionKey",
	RuntimeUnlockedAttributeName = "HomeExpansionUnlocked",
	RuntimeGeneratedFloorAttributeName = "HomeExpansionGeneratedFloor",
	BaseUpgradePartName = "BaseUpgrade",
	BaseUpgradeSurfaceGuiName = "SurfaceGui",
	BaseUpgradeFrameName = "Frame",
	BaseUpgradeMoneyRootName = "Money",
	BaseUpgradeInnerFrameName = "Frame",
	BaseUpgradeCostLabelName = "CurrentGold",
	BaseUpgradeLevelLabelName = "Level",
	FeedbackWrongSoundTemplateName = "Wrong",
	FeedbackWrongSoundAssetId = "rbxassetid://118029437877580",
	RequestDebounceSeconds = 0.2,
	FloorVerticalOffset = 32,
	UnlockEntries = {
		{ Id = 1001, LocalSlotIndex = 1, FloorLevel = 2, UnlockPrice = 1000000 },
		{ Id = 1002, LocalSlotIndex = 2, FloorLevel = 2, UnlockPrice = 2000000 },
		{ Id = 1003, LocalSlotIndex = 3, FloorLevel = 2, UnlockPrice = 4000000 },
		{ Id = 1004, LocalSlotIndex = 4, FloorLevel = 2, UnlockPrice = 8000000 },
		{ Id = 1005, LocalSlotIndex = 5, FloorLevel = 2, UnlockPrice = 16000000 },
		{ Id = 1006, LocalSlotIndex = 6, FloorLevel = 2, UnlockPrice = 32000000 },
		{ Id = 1007, LocalSlotIndex = 7, FloorLevel = 2, UnlockPrice = 64000000 },
		{ Id = 1008, LocalSlotIndex = 8, FloorLevel = 2, UnlockPrice = 128000000 },
		{ Id = 1009, LocalSlotIndex = 9, FloorLevel = 2, UnlockPrice = 256000000 },
		{ Id = 1010, LocalSlotIndex = 10, FloorLevel = 2, UnlockPrice = 512000000 },
		{ Id = 2001, LocalSlotIndex = 1, FloorLevel = 3, UnlockPrice = 1024000000 },
		{ Id = 2002, LocalSlotIndex = 2, FloorLevel = 3, UnlockPrice = 2048000000 },
		{ Id = 2003, LocalSlotIndex = 3, FloorLevel = 3, UnlockPrice = 4096000000 },
		{ Id = 2004, LocalSlotIndex = 4, FloorLevel = 3, UnlockPrice = 8192000000 },
		{ Id = 2005, LocalSlotIndex = 5, FloorLevel = 3, UnlockPrice = 16384000000 },
		{ Id = 2006, LocalSlotIndex = 6, FloorLevel = 3, UnlockPrice = 32768000000 },
		{ Id = 2007, LocalSlotIndex = 7, FloorLevel = 3, UnlockPrice = 65536000000 },
		{ Id = 2008, LocalSlotIndex = 8, FloorLevel = 3, UnlockPrice = 131072000000 },
		{ Id = 2009, LocalSlotIndex = 9, FloorLevel = 3, UnlockPrice = 262144000000 },
		{ Id = 2010, LocalSlotIndex = 10, FloorLevel = 3, UnlockPrice = 524288000000 },
	},
}
GameConfig.DATASTORE = {
	StudioName = "Brainrots_PlayerData_STUDIO_V1",
	LiveName = "Brainrots_PlayerData_LIVE_V1",
	EnableInStudio = true,
	AutoSaveInterval = 60,
	MaxRetries = 3,
	RetryDelay = 1.5,
}

GameConfig.DATASTORE.ActiveName = RunService:IsStudio()
	and GameConfig.DATASTORE.StudioName
	or GameConfig.DATASTORE.LiveName

GameConfig.WEAPON = {
	ToolsRootFolderName = "Tools",
	StarterWeaponFolderName = "StarterWeapon",
	DefaultWeaponId = "Bat",
	SwingAttackAnimationId = "79436155132033",
	SlotCount = 1, -- Reserved: currently fixed to one weapon slot
	ToolIsWeaponAttributeName = "IsWeaponTool",
	ToolWeaponIdAttributeName = "WeaponId",
	KnockbackEnabled = true,
	KnockbackRequireToolEquipped = true,
	-- Boss 命中玩家和玩家棒球棒命中，统一共用这一套击飞参数。
	KnockbackActiveWindowSeconds = 0.32,
	KnockbackHitCooldownSeconds = 0.45,
	KnockbackUseImpulse = true,
	KnockbackVelocityEnforceDuration = 0.16,
	KnockbackHorizontalVelocity = 132,
	KnockbackVerticalVelocity = 28,
	KnockbackAngularVelocity = 20,
	KnockbackRagdollDuration = 1.05,
	KnockbackFallingDownPulseDuration = 0.18,
	KnockbackPlatformStandDelay = 0.08,
	KnockbackPlatformStandDuration = 0.45,
	KnockbackRecoveryGroundWaitSeconds = 0.2,
	KnockbackRecoverySettleTimeoutSeconds = 1.25,
	KnockbackRecoveryMaxLinearSpeed = 11,
	KnockbackRecoveryMaxAngularSpeed = 14,
	KnockbackServerOwnsPhysics = true,
	KnockbackHitboxForwardOffset = 3.5,
	KnockbackHitboxSize = Vector3.new(5.5, 5.5, 6.5),
	KnockbackHitboxScanInterval = 0.05,
}

GameConfig.UI = {
	ModalBlurName = "Blur",
	ModalOpenFromScale = 0.82,
	ModalOpenOvershootScale = 1.06,
	ModalOpenOvershootDuration = 0.18,
	ModalOpenSettleDuration = 0.12,
	ModalCloseOvershootScale = 1.04,
	ModalCloseOvershootDuration = 0.1,
	ModalCloseToScale = 0.78,
	ModalCloseShrinkDuration = 0.14,
}

GameConfig.SETTINGS = {
	ModalKey = "Option",
	DefaultMusicEnabled = true,
	DefaultSfxEnabled = true,
	MusicFolderName = "BGM",
	SfxFolderName = "Audio",
	CategoryAttributeName = "SettingsAudioCategory",
	MusicCategoryValue = "Music",
	SfxCategoryValue = "Sfx",
	RequestDebounceSeconds = 0.15,
	ToggleOnText = "On",
	ToggleOffText = "Off",
	ToggleOnStartColor = Color3.fromRGB(85, 255, 0),
	ToggleOnEndColor = Color3.fromRGB(255, 255, 0),
	ToggleOffStartColor = Color3.fromRGB(203, 0, 14),
	ToggleOffEndColor = Color3.fromRGB(255, 93, 53),
}
GameConfig.REBIRTH = {
	RequestDebounceSeconds = 0.35,
	SuccessTipText = "Rebirth successful!",
	TipsDisplaySeconds = 2,
	TipsEnterOffsetY = 40,
	TipsFadeOffsetY = -8,
	WrongSoundTemplateName = "Wrong",
	WrongSoundAssetId = "rbxassetid://118029437877580",
}

GameConfig.GROUP_REWARD = {
	GroupId = 438450096,
	RewardBrainrotId = 10022,
	RewardCount = 1,
	RequestDebounceSeconds = 0.2,
	SuccessTipText = "Claim Successful!",
	RequirementTipText = "Join the group for rewards!",
	VerifyFailedTipText = "Unable to verify group membership. Try again.",
	TipTitleText = "Group Reward",
	TipsDisplaySeconds = 2,
	WrongSoundTemplateName = "Wrong",
	WrongSoundAssetId = "rbxassetid://118029437877580",
	ModalKey = "GroupReward",
}
GameConfig.IDLE_COIN = {
	ModalKey = "Idlecoin",
	DeveloperProductId = 3566656890,
	RequestDebounceSeconds = 0.2,
}
GameConfig.SEVEN_DAY_LOGIN_REWARD = {
	ModalKey = "Sevendays",
	DeveloperProductId = 3567064046,
	RequestDebounceSeconds = 0.2,
	CoinRewardName = "Coins",
	CoinRewardIcon = "rbxassetid://92295649647469",
	SuccessTipText = "Claim Successful!",
	SuccessTipDisplaySeconds = 1.8,
	Rewards = {
		{ RewardType = "Coins", Amount = 500 },
		{ RewardType = "Brainrot", RewardId = 10024, Amount = 1 },
		{ RewardType = "Coins", Amount = 100000 },
		{ RewardType = "Brainrot", RewardId = 10038, Amount = 1 },
		{ RewardType = "Coins", Amount = 500000000 },
		{ RewardType = "Brainrot", RewardId = 10047, Amount = 1 },
		{ RewardType = "Brainrot", RewardId = 10055, Amount = 1 },
	},
}
GameConfig.STARTER_PACK = {
	ModalKey = "NewplayerPack",
	GamePassId = 1779916806,
	RequestDebounceSeconds = 0.2,
	OwnershipRefreshCooldownSeconds = 0.75,
	PurchaseSyncRetrySeconds = 0.8,
	PurchaseSyncMaxAttempts = 8,
	SuccessLockSeconds = 1,
	SuccessSlideDuration = 0.28,
	SuccessItemRevealInterval = 0.08,
	CoinRewardName = "Coins",
	CoinRewardIcon = "rbxassetid://92295649647469",
	Rewards = {
		{ RewardType = "Brainrot", RewardId = 10032, Amount = 1 },
		{ RewardType = "Brainrot", RewardId = 10036, Amount = 1 },
		{ RewardType = "Coins", Amount = 100000 },
	},
}
GameConfig.GM = {
	EnabledOnlyInStudio = true,
	AllowAllUsers = true,
	DeveloperUserIds = {
		-- [123456789] = true,
	},
	GroupAdminRankThreshold = 254,
}

GameConfig.BRAINROT = {
	ModelRootFolderName = "Model",
	RuntimeFolderName = "PlacedBrainrots",
	PromptHoldDuration = 1,
	WorldSpawnLandFolderName = "Land",
	WorldSpawnRuntimeFolderName = "WorldSpawnedBrainrots",
	WorldSpawnPromptName = "WorldBrainrotPickupPrompt",
	WorldSpawnPromptActionText = "Pick Up",
	WorldSpawnPromptObjectText = "Brainrot",
	WorldSpawnPromptHoldDuration = 1,
	WorldSpawnPromptMaxActivationDistance = 10,
	WorldSpawnPromptRequiresLineOfSight = false,
	WorldSpawnLifetimeMin = 25,
	WorldSpawnLifetimeMax = 30,
	WorldSpawnCarryAnimationId = "135438263083349",
	WorldSpawnCarryToolName = "WorldCarryBrainrot",
	WorldSpawnCarryToolHideAttributeName = "HideFromCustomBackpack",
	WorldSpawnCarryToolTemporaryAttributeName = "BrainrotTemporaryCarrier",
	WorldSpawnCarryGripRotationDegrees = Vector3.new(0, 0, -90), -- ???????????????????????
	WorldSpawnIdleAnimationEnabled = true,
	WorldSpawnCarryDropStates = {
		[Enum.HumanoidStateType.FallingDown] = true,
		[Enum.HumanoidStateType.Ragdoll] = true,
		[Enum.HumanoidStateType.Physics] = true,
	},
	WorldSpawnClaimSceneFolderName = "Scene",
	WorldSpawnClaimGroundFolderName = "Grond",
	WorldSpawnClaimHomelandPartName = "Homeland",
	WorldSpawnPartEdgePadding = 1,
	WorldSpawnHeightOffset = 0.25,
	WorldSpawnCheckInterval = 0.5,
	WorldSpawnCountdownUpdateInterval = 0.1,
	WorldSpawnBossRuntimeFolderName = "WorldSpawnBosses",
	WorldSpawnLandBarrierEnabled = true,
	WorldSpawnLandBarrierHeight = 180,
	WorldSpawnLandBarrierThickness = 10,
	WorldSpawnLandBarrierPadding = 0,
	WorldSpawnLandBarrierTransparency = 0.7,
	WorldSpawnLandBarrierCollisionClearance = 1.5,
	WorldSpawnLandBarrierGroundInset = 0,
	WorldSpawnLandBarrierRaycastDistance = 10,
	WorldSpawnLandBarrierStickyDistance = 24,
	BossTickInterval = 0.1,
	BossClientVisualSmoothingEnabled = true,
	BossClientVisualInterpolationWindow = 0.1,
	BossClientVisualSnapDistance = 8,
	BossAggroRange = 1,
	BossHomeUnlockDelay = 5,
	BossPatrolRetargetMin = 2.5,
	BossPatrolRetargetMax = 4.5,
	BossPatrolIdleChance = 0.35,
	BossPatrolIdleDurationMin = 0.45,
	BossPatrolIdleDurationMax = 1.1,
	BossPatrolReachedDistance = 0.75,
	BossTargetRefreshInterval = 0.2,
	BossAttackCooldown = 1.25,
	BossAttackRecoveryDuration = 0.8,
	BossWarningBlinkCount = 3,
	BossWarningFadeTime = 0.18,
	WorldSpawnClaimConfettiEnabled = true, -- 带世界脑红回家成功时，是否播放满屏彩纸爆散反馈
	WorldSpawnClaimConfettiPieceCount = 72, -- 单次爆散生成的彩纸数量
	WorldSpawnClaimConfettiMaxActivePieces = 180, -- 同屏最多保留的彩纸数量，避免多次连续触发过载
	WorldSpawnClaimConfettiOriginXScale = 0.5, -- 爆散中心点的屏幕 X 比例
	WorldSpawnClaimConfettiOriginYScale = 0.38, -- 爆散中心点的屏幕 Y 比例
	WorldSpawnClaimConfettiOriginJitterXPx = 120, -- 爆散中心点 X 方向随机抖动（像素）
	WorldSpawnClaimConfettiOriginJitterYPx = 36, -- 爆散中心点 Y 方向随机抖动（像素）
	WorldSpawnClaimConfettiPieceSizePxMin = 10, -- 彩纸最小尺寸（像素）
	WorldSpawnClaimConfettiPieceSizePxMax = 24, -- 彩纸最大尺寸（像素）
	WorldSpawnClaimConfettiPieceAspectMin = 0.7, -- 彩纸长宽比最小值
	WorldSpawnClaimConfettiPieceAspectMax = 1.8, -- 彩纸长宽比最大值
	WorldSpawnClaimConfettiHorizontalSpeedMin = 420, -- 彩纸水平初速度最小值（像素/秒）
	WorldSpawnClaimConfettiHorizontalSpeedMax = 1100, -- 彩纸水平初速度最大值（像素/秒）
	WorldSpawnClaimConfettiUpwardSpeedMin = 420, -- 彩纸向上初速度最小值（像素/秒）
	WorldSpawnClaimConfettiUpwardSpeedMax = 1180, -- 彩纸向上初速度最大值（像素/秒）
	WorldSpawnClaimConfettiGravity = 1850, -- 彩纸下落重力（像素/秒^2）
	WorldSpawnClaimConfettiRotationSpeedMin = -540, -- 彩纸旋转角速度最小值（度/秒）
	WorldSpawnClaimConfettiRotationSpeedMax = 540, -- 彩纸旋转角速度最大值（度/秒）
	WorldSpawnClaimConfettiLifetimeMin = 0.9, -- 彩纸最短存活时间（秒）
	WorldSpawnClaimConfettiLifetimeMax = 1.35, -- 彩纸最长存活时间（秒）
	WorldSpawnClaimConfettiFadeOutDuration = 0.22, -- 彩纸尾段淡出时长（秒）
	WorldSpawnClaimConfettiColors = {
		Color3.fromRGB(255, 70, 70),
		Color3.fromRGB(255, 208, 58),
		Color3.fromRGB(102, 255, 102),
		Color3.fromRGB(72, 230, 255),
		Color3.fromRGB(255, 128, 48),
		Color3.fromRGB(186, 110, 255),
	},
	ModelPlacementOffsetY = 0,
	PlatformAttachmentName = "BrainrotAttachment",
	PlatformTriggerName = "Trigger",
	PositionPrefix = "Position",
	ClaimPrefix = "Claim",
	MoneyFrameName = "Money",
	CurrentGoldLabelName = "CurrentGold",
	OfflineGoldLabelName = "OfflineGold",
	OfflineProductionCapSeconds = 3600,
	ClaimTouchDebounceSeconds = 0.3, -- 再次触碰触发的最小间隔（秒，需先离开 Claim/Touch）
	ClaimPressOffsetY = 0.65, -- Claim 按压位移量（Y 轴向下，单位 Stud；优先作用在 Claim/Touch）
	ClaimPressDownDuration = 0.15, -- Claim 按下阶段时长（秒）
	ClaimPressUpDuration = 0.3, -- Claim 回弹阶段时长（秒）
	ClaimTouchHighlightEnabled = true, -- Touch 按压弹起期间启用高亮
	ClaimTouchHighlightAlwaysOnTop = false, -- Touch 高亮是否始终显示在前（减少遮挡）
	ClaimTouchHighlightFillColor = Color3.fromRGB(255, 235, 130), -- Touch 高亮填充颜色
	ClaimTouchHighlightFillTransparency = 0.55, -- Touch 高亮填充透明度
	ClaimTouchHighlightOutlineColor = Color3.fromRGB(255, 255, 255), -- Touch 高亮描边颜色
	ClaimTouchHighlightOutlineTransparency = 1, -- Touch 高亮描边透明度
	ClaimTouchHighlightFadeOutDuration = 0.12, -- Touch 回弹结束后高亮淡出时长（秒）
	ClaimBrainrotBounceOffsetY = 4, -- 领取时脑红弹跳高度（Y 轴向上，单位 Stud）
	ClaimBrainrotBounceUpDuration = 0.3, -- 脑红上升阶段时长（秒）
	ClaimBrainrotBounceDownDuration = 0.2, -- 脑红回落阶段时长（秒）
	ClaimTouchEffectRootName = "Effect", -- 领取特效模板所在的根目录（ReplicatedStorage 下）
	ClaimTouchEffectFolderName = "Claim", -- 领取特效发射器模板目录（ReplicatedStorage/Effect/Claim）
	ClaimTouchEffectGlowName = "Glow", -- Claim 目录下 Glow 粒子发射器（Emit(1) 后按生命周期销毁）
	ClaimTouchEffectSmokeName = "Smoke", -- Claim 目录下 Smoke 粒子发射器（Emit(1) 后按生命周期销毁）
	ClaimTouchEffectMoneyName = "Money", -- Claim 目录下 Money 粒子发射器（挂载后持续 1.5 秒）
	ClaimTouchEffectStarsName = "Stars", -- Claim 目录下 Stars 粒子发射器（挂载后持续 1.5 秒）
	ClaimTouchEffectMoneyStarsLifetime = 1.5, -- Money/Stars 挂载后保留时长（秒）
	ClaimCoinCollectRuntimeFolderName = "ClaimCoinCollectFx", -- 金币图标特效运行时容器（Workspace 下）
	ClaimCoinCollectIconAssetId = "rbxassetid://114660279658559", -- V1.8.2 金币图标资源
	ClaimCoinCollectIconCount = 8, -- 单次默认生成图标数（会被 Min/Max 约束）
	ClaimCoinCollectIconCountMin = 6, -- 单次最少生成图标数
	ClaimCoinCollectIconCountMax = 12, -- 单次最多生成图标数
	ClaimCoinCollectSpawnHeight = 3.2, -- 起始点位于 Touch 顶部上方高度（Stud）
	ClaimCoinCollectIconSizeStuds = 1.5, -- 图标基础显示尺寸（BillboardGui 尺寸）
	ClaimCoinCollectIconSizeScaleMin = 0.9, -- 图标尺寸随机缩放最小值
	ClaimCoinCollectIconSizeScaleMax = 1.1, -- 图标尺寸随机缩放最大值
	ClaimCoinCollectPopFromScale = 0.8, -- 图标出现时起始缩放
	ClaimCoinCollectPopDuration = 0.12, -- 图标出现弹出时长（秒）
	ClaimCoinCollectBurstDuration = 0.24, -- 爆裂阶段时长（秒）
	ClaimCoinCollectBurstRadiusMin = 5.0, -- 爆裂水平半径最小值（Stud）
	ClaimCoinCollectBurstRadiusMax = 16.8, -- 爆裂水平半径最大值（Stud）
	ClaimCoinCollectBurstVerticalOffsetMin = -0.2, -- 爆裂阶段垂直偏移最小值（Stud）
	ClaimCoinCollectBurstVerticalOffsetMax = 1.0, -- 爆裂阶段垂直偏移最大值（Stud）
	ClaimCoinCollectStartDelayMax = 0.045, -- 每个图标起始错峰最大延迟（秒）
	ClaimCoinCollectAttractDurationMin = 0.45, -- 吸附阶段最短时长（秒）
	ClaimCoinCollectAttractDurationMax = 0.54, -- 吸附阶段最长时长（秒）
	ClaimCoinCollectTargetOffsetY = 2, -- 吸附终点相对 HumanoidRootPart 的 Y 偏移
	ClaimCoinCollectArcHeightMin = 0.25, -- 吸附弧线高度最小值（Stud）
	ClaimCoinCollectArcHeightMax = 0.8, -- 吸附弧线高度最大值（Stud）
	ClaimCoinCollectArcHorizontalJitter = 0.75, -- 吸附弧线水平抖动范围（Stud）
	ClaimCoinCollectDestroyDistance = 0.8, -- 接近终点后判定销毁的距离阈值（Stud）
	ClaimCoinCollectFadeOutDuration = 0.075, -- 到达终点时淡出缩小时长（秒）
	BaseLevel = 1, -- 脑红默认等级
	PlacedPickupPromptName = "PlacedPickupPrompt", -- V2.6: 放置脑红上的拾取 Prompt 名称
	PlacedPickupPromptActionText = "Pick Up", -- V2.6: 已放置脑红拾取 Prompt 文案
	PlacedPickupPromptObjectText = "Brainrot", -- V2.6: 已放置脑红拾取 Prompt 目标文案
	PlacedStealPromptName = "PlacedStealPrompt", -- V3.1.2: placed brainrot steal prompt name
	PlacedStealPromptActionText = "Steal", -- V3.1.2: placed brainrot steal prompt action text
	PlacedStealPromptObjectText = "Brainrot", -- V3.1.2: placed brainrot steal prompt object text
	PlacedStealPromptHoldDuration = 1, -- V3.1.2: hold for 1 second to steal
	PlacedStealPromptMaxActivationDistance = 10, -- V3.1.2: steal prompt max activation distance
	StealPendingTimeoutSeconds = 900, -- V3.1.2: pending steal snapshot timeout seconds
	SellPriceMultiplier = 15, -- V2.6: 出售价格倍率，price = 基础产速 * 15
	SellRequestDebounceSeconds = 0.2, -- V2.6: 出售请求服务端防抖
	SellTouchOpenEnabled = false, -- V3.1.2+: 是否允许玩家触碰 Shop02/PrisonerTouch 时自动打开出售界面
	SellShopModelName = "Shop02", -- V2.6: 触碰打开出售界面的场景模型
	SellShopTouchPartName = "PrisonerTouch", -- V2.6: 触碰打开出售界面的触碰节点
	SellPromptModelName = "Tung Sahur", -- 场景交互打开出售界面的 NPC 模型
	SellPromptName = "ProximityPrompt", -- V3.0.2: 打开出售界面的 Prompt 名称
	AmbientNpcIdleModelNames = { "Madudung", "Garamararam" }, -- V3.0.2: 客户端常驻播放待机动画的场景 NPC
	SellSuccessSoundTemplateName = "ADDCash", -- V2.6: 出售成功音效模板（与领取金币一致）
	SellSuccessSoundAssetId = "rbxassetid://139922061047157", -- V2.6: 出售成功音效资源
	UpgradeCostMultiplier = 1.5, -- V2.5: 升级费用倍率，cost = baseSpeed * 1.5^(level-1)
	UpgradeProductionMultiplier = 1.25, -- V2.5: 升级后产速倍率，speed = baseSpeed * 1.25^(level-1)
	UpgradeValueDisplayDecimals = 1, -- V2.5: 升级费用/产速/UI 文案最多显示 1 位小数
	UpgradeInternalPrecisionDecimals = 4, -- V2.5: 内部经济数值保留精度
	UpgradeRequestDebounceSeconds = 0.2, -- V2.5: 客户端升级点击请求防抖
	BrandPrefix = "Brand", -- V2.5: 升级台命名前缀
	BrandSurfaceGuiName = "SurfaceGui", -- V2.5: 升级台 SurfaceGui 名称
	BrandFrameName = "Frame", -- V2.5: 升级台主框体名称
	BrandMoneyRootName = "Money", -- V2.5: 升级台费用信息根节点
	BrandCostLabelName = "CurrentGold", -- V2.5: 升级费用文本节点
	BrandLevelLabelName = "Level", -- V2.5: 升级等级文本节点
	BrandArrowName = "Arrow", -- V2.5: 升级箭头图片节点
	UpgradeSuccessSoundTemplateName = "MoneyTouch", -- V2.5: 升级成功音效模板
	UpgradeSuccessSoundAssetId = "rbxassetid://72535887807534", -- V2.5: 升级成功音效资源
	UpgradeWrongSoundTemplateName = "Wrong", -- V2.5: 升级失败音效模板
	UpgradeWrongSoundAssetId = "rbxassetid://118029437877580", -- V2.5: 升级失败音效资源
	BrandArrowFloatOffset = 8, -- V2.5: 箭头上下浮动像素偏移
	BrandArrowFloatDuration = 0.9, -- V2.5: 箭头单程浮动时长
	BrandSurfaceGuiAlwaysOnTop = false, -- V2.8: 升级台 UI 不再永久顶层显示，避免压在角色/脑红前面
	BrandSurfaceGuiLightInfluence = 0, -- V2.8: 升级台 UI 不受场景光照影响，保持稳定可读
	BrandSurfaceGuiZOffset = 0.18, -- V2.8: 升级台 UI 轻微离开牌面，既更好点到也不会明显悬浮
	InfoTemplateRootName = "UI",
	InfoTemplateName = "BaseInfo",
	InfoAttachmentName = "Info",
	InfoTitleRootName = "Title",
	InfoNameLabelName = "Name",
	InfoQualityLabelName = "Quality",
	InfoRarityLabelName = "Rarity",
	InfoSpeedLabelName = "Speed",
	InfoTimeRootName = "Time",
	InfoTimeLabelName = "Time",
	WorldSpawnCountdownSuffix = "S",
	WorldSpawnCountdownDecimals = 1,
	HideNormalRarity = true,
	MythicQualityGradientAnimationEnabled = true, -- V1.9: Mythic 品质渐变左右循环动画开关
	MythicQualityGradientOffsetRange = 1, -- V1.9: Mythic 渐变左右偏移范围（UIGradient.Offset.X）
	MythicQualityGradientOneWayDuration = 2.4, -- V1.9: Mythic 渐变单程移动时长（秒）
	MythicQualityGradientUpdateInterval = 0.033, -- V1.9: Mythic 渐变刷新间隔（秒，越小越平滑）
	SecretQualityGradientAnimationEnabled = true, -- V1.9: Secret 品质渐变左右循环动画开关（独立于 Mythic）
	SecretQualityGradientOffsetRange = 1, -- V1.9: Secret 渐变左右偏移范围（UIGradient.Offset.X）
	SecretQualityGradientOneWayDuration = 2.4, -- V1.9: Secret 渐变单程移动时长（秒）
	SecretQualityGradientUpdateInterval = 0.033, -- V1.9: Secret 渐变刷新间隔（秒，越小越平滑）
	GodQualityGradientAnimationEnabled = true, -- V2.0.1: God 品质渐变左右循环动画开关（独立参数）
	GodQualityGradientOffsetRange = 1, -- V2.0.1: God 渐变左右偏移范围（UIGradient.Offset.X）
	GodQualityGradientOneWayDuration = 2.4, -- V2.0.1: God 渐变单程移动时长（秒）
	GodQualityGradientUpdateInterval = 0.033, -- V2.0.1: God 渐变刷新间隔（秒）
	OGQualityGradientAnimationEnabled = true, -- V2.0.1: OG 品质渐变左右循环动画开关（独立参数）
	OGQualityGradientOffsetRange = 1, -- V2.0.1: OG 渐变左右偏移范围（UIGradient.Offset.X）
	OGQualityGradientOneWayDuration = 2.4, -- V2.0.1: OG 渐变单程移动时长（秒）
	OGQualityGradientUpdateInterval = 0.033, -- V2.0.1: OG 渐变刷新间隔（秒）
	LavaRarityGradientAnimationEnabled = true, -- V2.0.1: Lava 稀有度渐变左右循环动画开关（独立参数）
	LavaRarityGradientOffsetRange = 1, -- V2.0.1: Lava 渐变左右偏移范围（UIGradient.Offset.X）
	LavaRarityGradientOneWayDuration = 2.4, -- V2.0.1: Lava 渐变单程移动时长（秒）
	LavaRarityGradientUpdateInterval = 0.033, -- V2.0.1: Lava 渐变刷新间隔（秒）
	HackerRarityGradientAnimationEnabled = true, -- V2.0.1: Hacker 稀有度渐变左右循环动画开关（独立参数）
	HackerRarityGradientOffsetRange = 1, -- V2.0.1: Hacker 渐变左右偏移范围（UIGradient.Offset.X）
	HackerRarityGradientOneWayDuration = 2.4, -- V2.0.1: Hacker 渐变单程移动时长（秒）
	HackerRarityGradientUpdateInterval = 0.033, -- V2.0.1: Hacker 渐变刷新间隔（秒）
	RainbowRarityGradientAnimationEnabled = true, -- V2.0.1: Rainbow 稀有度渐变左右循环动画开关（独立参数）
	RainbowRarityGradientOffsetRange = 1, -- V2.0.1: Rainbow 渐变左右偏移范围（UIGradient.Offset.X）
	RainbowRarityGradientOneWayDuration = 2.4, -- V2.0.1: Rainbow 渐变单程移动时长（秒）
	RainbowRarityGradientUpdateInterval = 0.033, -- V2.0.1: Rainbow 渐变刷新间隔（秒）
	ClaimTipDisplaySeconds = 2,
	ClaimTipEnterOffsetY = 40,
	ClaimTipFadeOffsetY = -8,
}

GameConfig.SOCIAL = {
	InfoRootName = "Information",
	InfoPartName = "InfoPart",
	SurfaceGuiName = "SurfaceGui01",
	PromptHoldDuration = 1,
}


GameConfig.GIFT = {
	PromptName = "GiftPrompt",
	PromptActionText = "Gift",
	PromptObjectText = "",
	PromptHoldDuration = 1,
	PromptMaxActivationDistance = 10,
	PromptRequiresLineOfSight = false,
	RequestDebounceSeconds = 0.2,
	RequestExpireSeconds = 30,
	DeclineCooldownSeconds = 300,
}

GameConfig.FRIEND_BONUS = {
	PercentPerFriend = 10,
	MaxFriendCount = 4,
}

GameConfig.QUICK_TELEPORT = {
	RequestDebounceSeconds = 0.25,
	DefaultYOffset = 5,
	Shop01 = {
		ModelName = "Shop01",
		TouchPartName = "PrisonerTouch",
		YOffset = 5,
	},
	Shop02 = {
		ModelName = "Shop02",
		TouchPartName = "PrisonerTouch",
		YOffset = 5,
	},
	Shop03 = {
		ModelName = "Shop03",
		TouchPartName = "PrisonerTouch",
		YOffset = 5,
	},
}


GameConfig.SLIDE = {
	ModelName = "SlideRainbow01", -- 滑梯模型名称（在 Workspace 下查找）
	SurfaceContainerName = "Collide1", -- 滑梯碰撞节点所在容器；只会读取其中指定的 Slide / Up Part
	SurfacePartName = "Slide", -- 只有这个 Part 会触发滑行
	LaunchPartName = "Up", -- 触碰这个 Part 时会触发底部弹射
	RaycastStartOffsetY = 2.5, -- 地面检测起点相对角色根部向上的偏移
	RaycastLength = 8, -- 向下检测 Slide 表面的射线长度
	EntrySpeed = 10, -- 刚进入滑梯状态时的起步速度
	Acceleration = 60, -- 顺坡方向的基础加速度，决定站上去后往下滑有多快
	MaxSpeed = 150, -- 滑行阶段允许达到的最大速度上限
	AirControlEnabled = true, -- 起飞/下落阶段是否允许空中修正轨迹
	AirControlMaxSpeed = 72, -- 空中控制可额外提供的最大平面速度
	AirControlAcceleration = 220, -- 有输入时向目标轨迹加速的速度
	AirControlDeceleration = 260, -- 松手后空中控制速度回收的速度
	AirControlTurnResponsiveness = 5.5, -- 快速切向时的响应倍率，越高越利落
	AirControlKeyboardInfluence = 1, -- 键盘/方向键输入权重
	AirControlTouchSensitivity = 1.2, -- 移动端拖拽灵敏度
	AirControlTouchDeadzone = 0.08, -- 移动端拖拽死区，避免轻触误触发
	AirControlTouchMaxDragPixels = 180, -- 达到最大空中输入所需的拖拽像素
	AirControlMomentumBlend = 1.15, -- 空中控制速度叠加到原始抛射轨迹上的权重
	AirControlVerticalLock = true, -- 空中控制只改水平轨迹，不改竖直坠落
	AnimationId = "92575341155576", -- 滑梯滑行动作动画资源 ID
	SlideAnimationId = "92575341155576", -- 滑梯贴地滑行动作动画资源 ID
	LaunchAnimationId = "119731095592081", -- 滑梯起飞上升阶段动作动画资源 ID
	FallAnimationId = "113889435877616", -- 滑梯腾空下降阶段动作动画资源 ID
	LandingAnimationId = "73247765805128", -- 落地瞬间播放的落地动作动画资源 ID
	LandingRecoveryHorizontalSpeed = 6, -- 落地后保留的最大水平残余速度，避免角色乱滚
	AnimationPlaybackSpeed = 1, -- 滑梯动作播放速度
	AnimationFadeTime = 0.15, -- 进入/退出滑梯动作时的淡入淡出时间
	LaunchAngleDegrees = 45, -- 触碰 Up 时的弹射角度；45 度表示水平与竖直速度相等
	FastLandFallSpeed = 900, -- 点击 Main/FlyButton/Land 后的强制垂直下坠速度
	LandingBurstEnabled = true, -- 起飞落地时是否播放裂地碎块特效
	LandingBurstRootName = "SlideLandingFx", -- 客户端落地碎块容器名称
	LandingBurstPartCount = 18, -- 每次落地炸开的绿色小方块数量
	LandingBurstLifetime = 2, -- 碎块存在时间
	LandingBurstMinSize = 1.6, -- 单个碎块最小边长
	LandingBurstMaxSize = 3.2, -- 单个碎块最大边长
	LandingBurstRadiusMin = 12, -- 目标散落最小半径
	LandingBurstRadiusMax = 16, -- 目标散落最大半径
	LandingBurstSpawnRadiusMin = 0, -- 出生点离落点的最小半径（0 就是脚底同点起爆）
	LandingBurstSpawnRadiusMax = 0, -- 出生点离落点的最大半径（0 就是全部从脚底同点起爆）
	LandingBurstLaunchAngleMinDegrees = 35, -- 炸开抛射最小角度
	LandingBurstLaunchAngleMaxDegrees = 35, -- 炸开抛射最大角度
	LandingBurstForceMin = 2.1, -- 炸开力度最小倍率（1 是当前基础力度，越大越猛）
	LandingBurstForceMax = 2.5, -- 炸开力度最大倍率（1 是当前基础力度，越大越猛）
	LandingBurstCollisionEnableDelay = 0.12, -- 碎块起爆后延迟多久再开启场景碰撞，避免把玩家首帧顶翻
	LandingBurstFadeDelayRatioMin = 0.78, -- 至少停留多久后才开始淡出（占总时长比例）
	LandingBurstFadeDelayRatioMax = 0.9, -- 最多停留多久后才开始淡出（占总时长比例）
	LandingBurstColor = Color3.fromRGB(0, 255, 0), -- 纯绿色裂地碎块颜色
	LandingShakeEnabled = true, -- 滑梯飞行落地时是否触发本地震屏
	LandingShakeDuration = 0.55, -- 震屏持续时间（秒）
	LandingShakeFrequency = 17, -- 震屏基础频率，越高越密
	LandingShakeDamping = 8, -- 震屏衰减速度，越高收得越快
	LandingShakeAmplitudeX = 2, -- 左右晃动幅度
	LandingShakeAmplitudeY = 0.9, -- 上下晃动幅度
	LandingShakeAmplitudeZ = 2, -- 朝里/朝外晃动幅度
}
GameConfig.LAUNCH_POWER = {
	DefaultLevel = 1,
	BaseUpgradeCost = 200,
	UpgradeCostSegments = {
		{ MaxTargetLevel = 20, Multiplier = 1.08 },
		{ MaxTargetLevel = 50, Multiplier = 1.11 },
		{ MaxTargetLevel = 80, Multiplier = 1.14 },
		{ Multiplier = 1.18 },
	},
	BulkUpgradeLevelCount = 10,
	SpeedPerPoint = 1.0,
	RequestDebounceSeconds = 0.35,
}

GameConfig.LEADERBOARD = {
	CashStatName = "Cash",
	RefreshIntervalSeconds = 120,
	MaxEntries = 50,
	PendingRankText = "--",
	OverflowRankText = "50+",
	EnableOrderedDataStoreInStudio = true,
	OrderedDataStores = {
		Production = {
			StudioName = "Brainrots_GlobalLeaderboard_Production_STUDIO_V1",
			LiveName = "Brainrots_GlobalLeaderboard_Production_LIVE_V1",
		},
		Playtime = {
			StudioName = "Brainrots_GlobalLeaderboard_Playtime_STUDIO_V1",
			LiveName = "Brainrots_GlobalLeaderboard_Playtime_LIVE_V1",
		},
	},
	BoardModels = {
		Production = "Leaderboard01",
		Playtime = "Leaderboard02",
	},
	PlayerAttributes = {
		ProductionValue = "GlobalLeaderboardProductionValue",
		ProductionRank = "GlobalLeaderboardProductionRankDisplay",
		PlaytimeValue = "GlobalLeaderboardPlaytimeSeconds",
		PlaytimeRank = "GlobalLeaderboardPlaytimeRankDisplay",
	},
}

GameConfig.SPECIAL_EVENT = {
	ScheduleIntervalSeconds = 30 * 60,
	SchedulerCheckIntervalSeconds = 1,
	ScheduleAnchorUnix = 1735689600, -- 2025-01-01 00:00:00 UTC
	TemplateRootFolderName = "Event",
	RuntimeFolderName = "SpecialEventsRuntime",
	StartTipDisplaySeconds = 2,
	StartTipFadeInSeconds = 0.25,
	StartTipFadeOutSeconds = 0.35,
	StartTipScaleFrom = 0.88,
	StartTipScaleTo = 1,
	StartTipScaleOut = 1.04,
	DefaultLightingNodeNames = {
		"Atmosphere",
		"DefaultSky",
	},
	AttachPartNames = {
		"HumanoidRootPart",
		"UpperTorso",
		"Torso",
		"Head",
	},
	Entries = {
		{
			Id = 1001,
			Name = "Hacker",
			Weight = 100,
			DurationSeconds = 300,
			TemplateName = "EventHacker",
			RenderMode = "CharacterAttachment",
			LightingPath = "Lighting/Hacker",
			DisplayLabelName = "HackerEvent",
		},
		{
			Id = 1002,
			Name = "Lava",
			Weight = 100,
			DurationSeconds = 300,
			TemplateName = "EventLava",
			RenderMode = "CharacterAttachment",
			LightingPath = "Lighting/Lava",
			DisplayLabelName = "LavaEvent",
		},
		{
			Id = 1003,
			Name = "Diamond",
			Weight = 100,
			DurationSeconds = 300,
			TemplateName = "EventScene/Diamond",
			RenderMode = "WorkspaceScene",
			LightingPath = "Lighting/Diamond",
			DisplayLabelName = "DiamondEvent",
		},
	},
}

GameConfig.DEFAULT_PLAYER_DATA = {
	Version = 11,
	Currency = {
		Coins = 0,
	},
	Growth = {
		PowerLevel = 1,
		RebirthLevel = 0,
	},
	RebirthState = {
		ProcessedPurchaseIds = {},
	},
	HomeState = {
		HomeId = "",
		PlacedBrainrots = {},
		ProductionState = {},
		UnlockedExpansionCount = 0,
	},
	BrainrotData = {
		NextInstanceId = 1,
		EquippedInstanceId = 0,
		StarterGranted = false,
		Inventory = {},
		UnlockedBrainrotIds = {},
		PendingStealPurchase = {},
		ProcessedStealPurchaseIds = {},
		CarryUpgradeLevel = 0,
		ProcessedCarryPurchaseIds = {},
	},
	WeaponState = {
		StarterWeaponGranted = false,
		OwnedWeaponIds = {},
		EquippedWeaponId = "",
	},
	JetpackState = {
		OwnedJetpackIds = {},
		EquippedJetpackId = 0,
		ProcessedPurchaseIds = {},
	},
	SettingsState = {
		MusicEnabled = true,
		SfxEnabled = true,
	},
	GroupRewardState = {
		Claimed = false,
		ClaimedAt = 0,
	},
	IdleCoinState = {
		ProcessedPurchaseIds = {},
	},
	SevenDayLoginRewardState = {
		CycleId = 0,
		UnlockedDays = {},
		ClaimedDays = {},
		LastClaimAt = 0,
		LastSequentialUnlockDay = 0,
		CycleStartUtcDay = 0,
		CycleStartsLockedUntilNextUtc = false,
		PendingCycleReset = false,
		ProcessedPurchaseIds = {},
	},
	StarterPackState = {
		Owned = false,
		Granted = false,
		GrantedAt = 0,
		GrantedRewardIndexes = {},
	},
	LeaderboardState = {
		TotalPlaySeconds = 0,
		ProductionSpeedSnapshot = 0,
	},
	Meta = {
		CreatedAt = 0,
		LastLoginAt = 0,
		LastLogoutAt = 0,
		LastSaveAt = 0,
	},
	SocialState = {
		LikesReceived = 0,
		LikedPlayerUserIds = {},
	},
}

return GameConfig
