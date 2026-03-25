--[[
脚本名字: GameConfig
脚本文件: GameConfig.lua
脚本类型: ModuleScript
Studio放置路径: ReplicatedStorage/Shared/GameConfig
]]

local RunService = game:GetService("RunService")

local GameConfig = {}

GameConfig.VERSION = "V3.2.0"

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
		{ Id = 1001, LocalSlotIndex = 1, FloorLevel = 2, UnlockPrice = 100 },
		{ Id = 1002, LocalSlotIndex = 2, FloorLevel = 2, UnlockPrice = 200 },
		{ Id = 1003, LocalSlotIndex = 3, FloorLevel = 2, UnlockPrice = 300 },
		{ Id = 1004, LocalSlotIndex = 4, FloorLevel = 2, UnlockPrice = 400 },
		{ Id = 1005, LocalSlotIndex = 5, FloorLevel = 2, UnlockPrice = 500 },
		{ Id = 1006, LocalSlotIndex = 6, FloorLevel = 2, UnlockPrice = 600 },
		{ Id = 1007, LocalSlotIndex = 7, FloorLevel = 2, UnlockPrice = 700 },
		{ Id = 1008, LocalSlotIndex = 8, FloorLevel = 2, UnlockPrice = 800 },
		{ Id = 1009, LocalSlotIndex = 9, FloorLevel = 2, UnlockPrice = 900 },
		{ Id = 1010, LocalSlotIndex = 10, FloorLevel = 2, UnlockPrice = 1000 },
		{ Id = 2001, LocalSlotIndex = 1, FloorLevel = 3, UnlockPrice = 1100 },
		{ Id = 2002, LocalSlotIndex = 2, FloorLevel = 3, UnlockPrice = 1200 },
		{ Id = 2003, LocalSlotIndex = 3, FloorLevel = 3, UnlockPrice = 1300 },
		{ Id = 2004, LocalSlotIndex = 4, FloorLevel = 3, UnlockPrice = 1400 },
		{ Id = 2005, LocalSlotIndex = 5, FloorLevel = 3, UnlockPrice = 1500 },
		{ Id = 2006, LocalSlotIndex = 6, FloorLevel = 3, UnlockPrice = 1600 },
		{ Id = 2007, LocalSlotIndex = 7, FloorLevel = 3, UnlockPrice = 1700 },
		{ Id = 2008, LocalSlotIndex = 8, FloorLevel = 3, UnlockPrice = 1800 },
		{ Id = 2009, LocalSlotIndex = 9, FloorLevel = 3, UnlockPrice = 1900 },
		{ Id = 2010, LocalSlotIndex = 10, FloorLevel = 3, UnlockPrice = 2000 },
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
	KnockbackActiveWindowSeconds = 0.35,
	KnockbackHitCooldownSeconds = 0.45,
	KnockbackHorizontalVelocity = 75,
	KnockbackVerticalVelocity = 35,
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

GameConfig.REBIRTH = {
	RequestDebounceSeconds = 0.35,
	SuccessTipText = "Rebirth successful!",
	TipsDisplaySeconds = 2,
	TipsEnterOffsetY = 40,
	TipsFadeOffsetY = -8,
	WrongSoundTemplateName = "Wrong",
	WrongSoundAssetId = "rbxassetid://118029437877580",
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
	ClaimCoinCollectIconAssetId = "rbxassetid://92295649647469", -- V1.8.2 金币图标资源
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
	EntrySpeed = 36, -- 刚进入滑梯状态时的起步速度
	Acceleration = 240, -- 顺坡方向的基础加速度，决定站上去后往下滑有多快
	MaxSpeed = 165, -- 滑行阶段允许达到的最大速度上限
	AnimationId = "111214448809248", -- 滑梯动作动画资源 ID
	AnimationPlaybackSpeed = 1, -- 滑梯动作播放速度
	AnimationFadeTime = 0.15, -- 进入/退出滑梯动作时的淡入淡出时间
	LaunchAngleDegrees = 45, -- 触碰 Up 时的弹射角度；45 度表示水平与竖直速度相等
}
GameConfig.LAUNCH_POWER = {
	DefaultLevel = 1,
	BaseUpgradeCost = 200,
	UpgradeCostMultiplier = 1.08,
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
	AttachPartNames = {
		"HumanoidRootPart",
		"UpperTorso",
		"Torso",
		"Head",
	},
	Entries = {
		{
			Id = 1001,
			Name = "骇客事件",
			Weight = 100,
			DurationSeconds = 300,
			TemplateName = "EventHacker",
			LightingPath = "Lighting/Hacker",		},
		{
			Id = 1002,
			Name = "熔岩事件",
			Weight = 100,
			DurationSeconds = 300,
			TemplateName = "EventLava",
			LightingPath = "Lighting/Lava",		},
	},
}

GameConfig.DEFAULT_PLAYER_DATA = {
	Version = 6,
	Currency = {
		Coins = 0,
	},
	Growth = {
		PowerLevel = 1,
		RebirthLevel = 0,
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



