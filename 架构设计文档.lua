--[[
=====================================================
游戏整体架构设计文档（V3.2.0）
=====================================================

项目名称: BrainrotsTemplate
当前版本: V3.2.0
文档更新时间: 2026-03-24

一、核心分层
1. Shared 配置层（ReplicatedStorage/Shared）
- GameConfig: 全局配置，集中管理家园、DataStore、脑红、武器、Rebirth、家园拓展、全局排行榜、特殊事件、赠送礼物、弹射力、滑梯等参数。
- JetpackConfig: 喷气背包静态配置表，定义 1001~1005 的金币价、Robux 价、Developer Product Id、默认解锁标记、饰品路径，以及当前仅用于 UI 展示的两项未来玩法参数。
- BrainrotConfig: 脑红静态配置表，来源于 Excel 脑红表同步结果。
- RebirthConfig: Rebirth 静态配置表。
- BrainrotDisplayConfig: 脑红品质/稀有度展示名与渐变路径映射。
- RemoteNames / FormatUtil: RemoteEvent 名称与格式化工具。

2. 服务层（ServerScriptService/Services）
- PlayerDataService: 玩家数据读写、默认值合并、会话缓存、自动保存、排行榜快照持久化；Studio 与正式服 DataStore 分离，读档连续失败时会禁止本次会话写回。
- HomeService: 从当前空闲家园中随机分配一个给玩家，负责家园占用、回收、出生点绑定与回家传送。
- CurrencyService: 金币增减、同步，以及默认玩家列表 Cash 展示。
- BrainrotService: 脑红背包、装备、放置、已放置脑红拾取/替换、产金、领取、出售、世界模型运行态、Index 解锁历史、Claim UI 刷新、Brand 升级台刷新、升级与出售服务端校验、多楼层 PositionKey 映射、Studio 调试脑红发放，以及 V3.1.2 偷取购买与 Receipt 结算链路；当前还负责统一接管 MarketplaceService.ProcessReceipt，并把非脑红购买分发给外部 ReceiptHandlers。已放置脑红挂载 BaseInfo 时，名字显示格式统一为 `脑红名[Lv.X]`。
- HomeExpansionService: 家园拓展价格表、预置楼层显隐、锁定点位显隐、BaseUpgrade 文案刷新、拓展购买请求与反馈；当前基于 Workspace 下已有的 HomeFloor 节点做显隐，不再克隆楼层模板。
- RebirthService: Rebirth 条件校验、执行、状态同步、产速倍率更新。
- LaunchPowerService: 弹射力等级与数值的持久化、属性同步、单次/十连升级请求校验与扣费。
- JetpackService: 喷气背包拥有/装备状态持久化、默认解锁修正、金币购买校验、饰品挂载、重生后自动重挂、Robux receipt 发货、状态同步与反馈下发。
- FriendBonusService: 同服好友数量统计与好友产速加成同步。
- QuickTeleportService: Home / Shop / Sell 快捷传送请求。
- GMCommandService: GM 命令入口，当前支持 /addcoins /addbrainrot /clear /event。
- RemoteEventService: 统一创建和获取 RemoteEvent。
- SocialService: 家园信息板、点赞交互、点赞提示与状态同步。
- WeaponService: 武器拥有/装备状态管理，当前固定 1 个武器槽位。
- WeaponKnockbackService: 挥击命中后的击飞逻辑，不扣血、不击杀。
- GlobalLeaderboardService: 全局总产速榜/总时长榜刷新、榜单 UI 填充、玩家个人卡片属性同步。
- SpecialEventService: 特殊事件调度、跨服统一时间片选取、客户端状态同步、GM 手动触发。
- GiftService: 角色 Gift Prompt 挂载、赠送请求生命周期、拒绝冷却、接受/拒绝服务端校验与脑红转移。

3. 客户端层（StarterPlayerScripts）
- MainClient: 客户端启动入口，统一启动全部控制器，并在启动后主动请求一次 BrainrotStateSync。
- CoinDisplayController: 金币滚动、抖动、浮字反馈；主界面 CoinNum 显示向上取整，浮字最多 1 位小数。
- FriendBonusController: Friend Bonus 文本更新。
- SocialController: 点赞提示、点赞状态过滤、Prompt 本地可见性处理。
- QuickTeleportController: 顶部 Home / Shop / Sell 按钮继续向服务端发快捷传送请求。
- MainButtonFxController: 主界面按钮 Hover / Press 动效。
- ClaimFeedbackController: 仅本地播放领取音效与金币飞散回收特效。
- ModalController: 通用弹窗开关与 Blur 动效。
- IndexController: 图鉴界面、分类页签、条目渲染、渐变展示、进度统计。
- BrainrotUpgradeController: 扫描自己家园的 BrandX 升级台，绑定点击升级、箭头上下循环动画、升级成功/失败音效，并兼容多楼层重复 Brand 命名。
- BrainrotPlatformPromptController: 只让玩家看到自己家园内可交互的脑红放置 Prompt，本地根据 HomeId 与服务端 Attribute 过滤可见性。
- BrainrotStealController: 管理已放置脑红偷取 Prompt 的本地可见性、Developer Product 购买弹窗、购买关闭回传，以及 StealTips 提示表现。
- HomeExpansionController: 扫描自己家园的 BaseUpgrade 世界 UI，发送拓展请求，并处理拓展失败音效。
- RebirthController: Rebirth 面板、进度、请求与反馈表现。
- LaunchPowerUpgradeController: 弹射力升级面板控制器；顶部 Shop 按钮和 Workspace/Garamararam 的 Prompt 都会打开 Main/Upgrade，支持购买 1 级或 10 级。
- JetpackController: 喷气背包面板控制器；管理 Main/Left/Jetpack 入口、Main/Jetpack 面板开关、EquipTemplate 列表渲染、金币购买、Robux Prompt、本地购买成功 Tips，以及装备切换后的界面刷新。
- BrainrotSellController: 出售面板控制器；顶部 Sell 按钮会在请求快捷传送到 Sell 点的同时打开面板，Workspace/Madudung 的 Prompt 也会打开面板；Shop02/PrisonerTouch 的本地触碰打开逻辑仍保留，但当前由配置关闭。
- NpcIdleAnimationController: 在客户端为 Workspace/Madudung 与 Workspace/Garamararam 常驻播放待机动画。
- GlobalLeaderboardController: 本地玩家卡片刷新，读取玩家 Attribute 更新两个排行榜下方个人信息区域。
- SpecialEventController: 监听特殊事件同步，在本地给自己角色挂事件模板，并本地复制 Lighting 事件天空盒子节点。
- GiftController: Gift Prompt 本地可见性过滤、Gift 弹窗绑定、头像/文案渲染，以及拒绝冷却隐藏逻辑。
- CustomBackpackController: 隐藏 Roblox 原生 Backpack，渲染 Main/Backpack 的自定义工具列表，并保持武器/脑红槽位排序稳定。
- SlideController: 简化后的彩虹滑梯本地控制器；只认 Workspace/SlideRainbow01/Collide1/Slide 与 Up，进入 Slide 后持续加速下滑，碰到 Up 后按当前滑行速度和 Launch Power 立刻起飞，不新增 RemoteEvent；当前在滑行中与起飞后的整个空中阶段（上升/无重力/下降）都会临时隐藏大部分本地 UI，但保留 Main/FlyButton 按规则单独显示，落地后会播放一圈纯绿色的小方块裂地特效，再恢复其余 UI。
- StudioSlideDebugController: 仅 Studio 环境下生效；按 B 打开调试面板，只覆盖 Up 末端弹射力，不影响 Slide 上的下滑速度。
- StudioBrainrotDebugController: 仅 Studio 环境下生效；按 V 打开脑红测试面板，可直接给当前玩家补发脑红。

二、近阶段功能要点
1. V2.1 / V2.1.1
- Index 界面复用 BrainrotStateSync 的解锁历史数据。
- Claim 显示路径统一为 ClaimX/Touch/.../Money(Frame)，不再使用旧 BillboardGui 路径。

2. V2.2
- Rebirth 等级为永久玩家数据。
- Rebirth 成功后清空当前金币与待领取金币，并重新应用 Rebirth 产速倍率。

3. V2.3
- 新增全局总产速排行榜与全局总游玩时长排行榜。
- 公共 Top50 榜单由服务端直接驱动场景内 UI。
- 玩家自己的底部个人卡片由客户端读取玩家 Attribute 驱动。
- TotalPlaySeconds 为永久数据，/clear 不清空该字段。

4. V2.4 / V2.4.1 特殊事件
- 每 30 分钟触发一次特殊事件，按 UTC 整点和 30 分对齐，与服务器开启时间无关。
- 事件从 GameConfig.SPECIAL_EVENT.Entries 中按权重选择，且本次事件不能与上次调度事件重复。
- 服务端负责调度和状态同步；客户端负责本地角色挂件和本地 Lighting 表现。
- GM 可通过 /event <事件Id> 在当前服务器手动触发事件。

5. V2.5 脑红升级
- 所有脑红在首次获得时默认 Level=1。
- 脑红升级费用: baseCoinPerSecond * 1.5^(currentLevel-1)。
- 脑红当前产速: baseCoinPerSecond * 1.25^(currentLevel-1)。
- BrainrotService 在服务端刷新 BrandX 升级台文案，并把升级后的等级与产速写回运行态和存档。
- BrainrotUpgradeController 负责 BrandX 点击请求、Arrow 循环动画、升级成功/失败音效。

6. V2.6 脑红出售
- 已放置脑红会挂载 Pick Up 长按 Prompt；空手长按时回收到背包，手持脑红长按时触发“手里 A 与台上 B”替换。
- 脑红出售价格: baseCoinPerSecond * 15，只看 1 级基础产速，不看当前等级产速。
- BrainrotSellController 负责出售列表、Inventory value 汇总、品质渐变展示和出售成功音效。
- 顶部 Sell 按钮会同时触发 RequestQuickTeleport(Sell) 和本地打开出售面板。

7. V2.7 / V2.7.1 家园拓展
- 玩家默认拥有 10 个基础脑红位；额外 20 个拓展位按配置表顺序逐个购买，价格从 100 到 2000。
- 当前使用 Workspace 中预置的 HomeFloor1/HomeFloor2/HomeFloor3 节点做显隐；未解锁的 Position / Claim / Brand 会被服务端隐藏并禁用。
- BaseUpgrade 世界 UI 的 CurrentGold / Level 文案由服务端直接刷新；客户端只负责点击请求和失败音效表现。
- BrainrotService 与 BrainrotUpgradeController 优先读取楼层属性，把二层三层重复的 Position1/Claim1/Brand1 映射为全局 Position11~30。

8. V2.8 自定义背包
- CoreGui Backpack 被隐藏，Main/Backpack 成为唯一玩家可见背包。
- 自定义背包直接从 Backpack 与 Character 中的 Tool 生成条目，点击条目只做装备/卸下，不自行维护另一套背包数据。

9. V2.9 赠送礼物
- 只有手持脑红的玩家靠近其他玩家时，Gift Prompt 才会在本地显示，并要求长按 E 1 秒发起赠送。
- GiftService 负责维护 pending request、30 秒过期、接收方 Accept / Decline / Close 决策，以及 5 分钟拒绝冷却。
- GiftController 负责强制打开 Main/Gift、复用 ModalController 的打开/关闭与 Blur 表现、渲染赠送者头像/名字/固定文案，并在拒绝冷却期间隐藏对应目标的 Prompt。

10. V3.0.2 商店补充
- Workspace/Madudung 的 Prompt 打开 Sell 脑红面板。
- Workspace/Madudung 与 Workspace/Garamararam 的待机动画只在客户端播放。

11. V3.1 弹射力系统
- Launch Power 为永久玩家数据，存放在 Growth.PowerLevel，并同步为玩家 Attribute: LaunchPowerLevel / LaunchPowerValue。
- LaunchPowerUpgradeController 支持购买 1 级或 10 级；服务端只接受 1 或 10 两种 upgradeCount。
- 顶部 Shop 按钮存在复合入口：既会继续走快捷传送请求，也会本地打开 Launch Power 升级面板。

12. V3.1.2 偷取脑红
- 已放置在别人基地中的脑红会挂 Steal Prompt；真正发起购买、补发脑红、移除原脑红、给被偷者弹 StealTips，都只以服务端当前 pending request 与 Marketplace receipt 为准。
- BrainrotService 负责 pending steal snapshot、Developer Product 对照表、ProcessReceipt 结算，以及“原脑红已被第三方拿走/卖掉时补发同脑红”这套兜底逻辑。

13. V3.1.3 滑梯简化
- 只有 Workspace/SlideRainbow01/Collide1/Slide 会触发滑行，只有 Workspace/SlideRainbow01/Collide1/Up 会触发起飞。
- SlideController 现在是单一状态机：Idle -> Sliding -> Idle。
- 玩家在 Slide 上的下滑速度完全不受 Launch Power 影响；Launch Power 只影响碰到 Up 后的那一下弹射。
- 离开 Slide 后立刻退出滑行，恢复控制，停止动画，不再保留额外的 launch carry、方向锁定、容错窗口或下落动画状态。
- 当前真正受支持的 GameConfig.SLIDE 配置包括路径、射线、EntrySpeed、Acceleration、MaxSpeed、滑行动画、淡入淡出、LaunchAngleDegrees，以及落地裂地碎块效果（数量、尺寸、半径、速度、持续时间、颜色）；旧的 carry / 容错 / 下落动画 / 横向混合参数已停止使用。

14. V3.2 喷气背包
- JetpackConfig 定义 1001~1005 五个喷气背包条目，其中 1001 为默认解锁项；玩家重生后会按当前 EquippedJetpackId 自动重新挂载对应 Accessory。
- JetpackService 负责 JetpackState 的持久化、默认解锁补正、金币购买、Developer Product receipt 发货，以及通过 Humanoid:AddAccessory 把 ReplicatedStorage/Jetpack 下的饰品挂到角色身上。
- JetpackController 负责 Main/Left/Jetpack 的入口、Main/Jetpack 面板开关、EquipTemplate 列表复制渲染、Gold/Robux/Equip 三类按钮可见性切换，以及 PurchaseSuccessfulTips 弹出动效。
- Jetpack 的 Robux 购买不新增专属 RemoteEvent；客户端直接调用 MarketplaceService:PromptProductPurchase，服务端只在 Marketplace receipt 成功后发货并同步 JetpackStateSync / JetpackFeedback。
- 当前版本已实现“解锁 / 购买 / 装备 / 重生重挂 / UI 表现 / 滑梯起飞后的 NoGravityDuration 无重力时间 / FlyProgress 倒计时逻辑 / FlyButton 子弹时间与左右横移微调 / 落地纯绿色裂地碎块特效”；BulletTimeFallSpeed 已接入 SlideController，本地用于近似悬停式下落减速；松开 Hold 后会恢复到按下前记录的空中速度快照。当前滑行中与滑梯起飞后的整个空中阶段都会统一隐藏大部分 UI，但会保留 Main/FlyButton 在可操作下落阶段单独显示，其他 UI 仍在落地后恢复。

三、关键数据结构
1. 持久化 PlayerData
- Currency.Coins
- Growth.PowerLevel
- Growth.RebirthLevel
- HomeState.HomeId
- HomeState.PlacedBrainrots[positionKey] -> InstanceId / BrainrotId / Level / PlacedAt
- HomeState.ProductionState[positionKey] -> CurrentGold / OfflineGold / FriendBonusRemainder
- HomeState.UnlockedExpansionCount
- BrainrotData.Inventory[{ InstanceId, BrainrotId, Level }]
- BrainrotData.EquippedInstanceId / NextInstanceId / StarterGranted / UnlockedBrainrotIds
- BrainrotData.PendingStealPurchase / ProcessedStealPurchaseIds
- WeaponState.StarterWeaponGranted / OwnedWeaponIds / EquippedWeaponId
- JetpackState.OwnedJetpackIds / EquippedJetpackId / ProcessedPurchaseIds
- LeaderboardState.TotalPlaySeconds / ProductionSpeedSnapshot
- SocialState.LikesReceived / LikedPlayerUserIds
- Meta.CreatedAt / LastLoginAt / LastLogoutAt / LastSaveAt

2. 运行态数据（不入档）
- BrainrotService._runtimePlacedByUserId
- BrainrotService._runtimeIdleTracksByUserId
- BrainrotService._placedPromptStateByUserId / _placedStealPromptStateByUserId
- BrainrotService._claimTouchDebounceByUserId / _claimEffectByUserId / _claimBounceStateByUserId
- BrainrotService._brandsByUserId / _upgradeRequestClockByUserId / _sellRequestClockByUserId
- BrainrotService._pendingStealPurchaseByBuyerUserId / _brainrotStealProductIds
- BrainrotService._receiptHandlers / _processReceiptDispatcher
- HomeExpansionService._lastRequestClockByUserId
- FriendBonusService._stateByUserId
- RebirthService._lastRequestClockByUserId
- LaunchPowerService._lastRequestClockByUserId
- JetpackService._lastRequestClockByUserId / _characterAddedConnectionsByUserId / _applySerialByUserId
- QuickTeleportService._lastRequestClockByUserId
- GlobalLeaderboardService._memoryScoresByBoardKey / _cachedEntriesByBoardKey / _userInfoByUserId
- SpecialEventService._activeEventsByRuntimeKey / _scheduleState
- GiftService._promptByUserId / _pendingRequestById / _pendingRequestIdBySenderUserId / _pendingRequestIdByRecipientUserId / _declineCooldownBySenderUserId

四、关键同步协议
1. CoinChanged
- 服务端下发 total / delta / reason / timestamp。
- total 与 delta 可带小数；CoinDisplayController 决定展示策略。

2. BrainrotStateSync
- inventory[i] 包含 level / baseCoinPerSecond / coinPerSecond / nextUpgradeCost / sellPrice。
- placed[i] 包含 level / baseCoinPerSecond / coinPerSecond / nextUpgradeCost。
- totalProductionBaseSpeed / totalProductionMultiplier / totalProductionSpeed 反映真实产速。

3. LaunchPowerStateSync / RequestLaunchPowerUpgrade / LaunchPowerFeedback
- LaunchPowerStateSync 下发当前等级、当前弹射力、下一档与十连购买价格、当前金币、speedPerPoint。
- RequestLaunchPowerUpgrade 只接受 upgradeCount = 1 或 10。
- LaunchPowerFeedback 只负责返回 Success / Debounced / MissingData / InvalidUpgradeCount / InsufficientCoins / SpendFailed，不承载可信经济真值。

4. JetpackStateSync / RequestJetpackCoinPurchase / RequestJetpackEquip / JetpackFeedback
- JetpackStateSync 下发 ownedJetpackIds / equippedJetpackId / timestamp。
- RequestJetpackCoinPurchase 只上传 jetpackId；服务端重新校验拥有状态、金币余额与请求频率。
- RequestJetpackEquip 只上传 jetpackId；服务端重新校验玩家是否真实拥有该喷气背包。
- JetpackFeedback 用于同步 CoinPurchased / RobuxPurchaseGranted / Equipped / Debounced / InvalidJetpack / MissingData / AlreadyOwned / InsufficientCoins / SpendFailed / NotOwned。
- Jetpack 的 Robux 打开购买弹窗完全本地处理，真正发货只以服务端 receipt 为准。

5. RequestBrainrotUpgrade / BrainrotUpgradeFeedback
- 客户端只上传 positionKey。
- 服务端重新校验脑红存在、等级、费用、金币余额与请求频率。

6. RequestBrainrotSell / BrainrotSellFeedback
- 客户端上传 instanceId 或 sellAll=true。
- 服务端重新校验实例是否真实位于玩家背包、售价是否有效、请求频率是否合法，并重新结算金币。

7. RequestHomeExpansion / HomeExpansionFeedback
- 客户端不上传价格、楼层或目标格子，只发起“购买下一个拓展位”的请求。
- 服务端重新校验当前已解锁数量、下一档价格、玩家金币余额和请求频率。

8. RequestStudioBrainrotGrant / StudioBrainrotGrantFeedback
- 只允许在 Studio 环境下使用，正式服即便存在同名 Remote 也必须由服务端拒绝。

9. BrainrotGiftOffer / RequestBrainrotGiftDecision / BrainrotGiftFeedback
- BrainrotGiftOffer 由服务端发给接收方，强制打开 Gift 弹窗，并同步 senderUserId / senderName / brainrotName 等只读展示数据。
- RequestBrainrotGiftDecision 只接受 requestId 与 decision；服务端重新校验 request 是否仍有效、接收方是否匹配、赠送实例是否仍存在。
- BrainrotGiftFeedback 用于同步 Requested / Accepted / Declined / Cancelled / Expired / SenderBusy / TargetBusy / SenderNotHoldingBrainrot / InvalidRequest 等状态。

10. PromptBrainrotStealPurchase / RequestBrainrotStealPurchaseClosed / BrainrotStealFeedback / StealTip
- PromptBrainrotStealPurchase 由服务端要求客户端弹出 Developer Product 购买。
- RequestBrainrotStealPurchaseClosed 只用于告知购买弹窗关闭与是否已购买，真实发货仍只以 Marketplace receipt 为准。
- BrainrotStealFeedback 用于同步 PurchasePending / TargetNotReady / BrainrotUnavailable / BrainrotConfigMissing / ProductMissing / PendingCreateFailed / PromptUnavailable / Cancelled / Success。
- StealTip 只发给被偷者本人，用于显示“[xxx] steal your [yyy]!”提示。

五、服务端初始化顺序（MainServer）
1. RemoteEventService:Init()
2. PlayerDataService:Init()
3. WeaponService:Init(...)
4. WeaponKnockbackService:Init()
5. HomeService:Init()
6. CurrencyService:Init(...)
7. FriendBonusService:Init(...)
8. QuickTeleportService:Init(...)
9. JetpackService:Init(...)
10. BrainrotService:Init(...)
11. HomeExpansionService:Init(...)
12. RebirthService:Init(...)
13. LaunchPowerService:Init(...)
14. GMCommandService:Init(...)
15. SocialService:Init(...)
16. GlobalLeaderboardService:Init(...)
17. SpecialEventService:Init(...)
18. GiftService:Init(...)
19. PlayerAdded 流程: 随机分配家园 -> 读档 -> 恢复武器 -> 初始化好友加成 -> 初始化 Rebirth 属性 -> 初始化 Launch Power 属性 -> 初始化 Jetpack 属性与角色挂件监听 -> 应用家园拓展楼层与 BaseUpgrade UI -> 恢复脑红/离线收益/图鉴历史/Brand 升级台/偷取运行态 -> 挂载 Gift Prompt -> 社交同步 -> 同步当前活跃特殊事件状态 -> 金币同步 -> 排行榜个人卡刷新
20. PlayerRemoving 流程: 解绑 -> 武器清理 -> 排行榜快照刷新 -> 好友加成重算 -> 脑红运行态清理 -> 清理 Gift 请求与 Prompt -> 回收家园拓展运行态 -> Rebirth 清理 -> Launch Power 清理 -> Jetpack 清理 -> 金币收尾 -> 社交清理 -> 特殊事件清理 -> 回收家园 -> 保存数据
21. BindToClose: 先刷新全局排行榜快照，再保存所有玩家数据

六、维护约束
1. 未来若新增或修改 RemoteEvent，必须同步更新:
- RemoteEvent当前列表.lua
- 架构设计文档.lua
- RemoteNames.lua
- RemoteEventService.lua

2. 所有客户端 -> 服务端请求都必须继续做服务端校验。
3. 所有产出相关状态统一维护在 HomeState.ProductionState。
4. 点赞、图鉴解锁历史、Rebirth 等级、Launch Power 等级、Jetpack 拥有/装备状态、总游玩时长均属于永久数据。
5. /clear 不得清空 TotalPlaySeconds。
6. Claim 音效继续保持“仅触发者自己本地可听见”。
7. 公共排行榜行内容由服务端驱动，底部个人卡片由客户端驱动。
8. 顶部 Shop / Sell 按钮当前是复合入口；若后续改按钮职责，必须同步检查 QuickTeleportController、LaunchPowerUpgradeController、BrainrotSellController 三者关系。
9. 滑梯功能继续完全本地处理，不新增 RemoteEvent；Launch Power 只影响 Up 末端弹射，不影响 Slide 上的下滑速度。
10. RequestLaunchPowerUpgrade 不能直接相信客户端提交的任意数量，服务端必须只接受 1 或 10。
11. RequestJetpackCoinPurchase / RequestJetpackEquip 不能直接相信客户端本地 UI 状态、价格或装备结果，服务端必须重新校验。
12. Jetpack 的 NoGravityDuration 与 BulletTimeFallSpeed 都已接入 SlideController，用于滑梯起飞后的本地无重力时间与空中运动参数；当前滑梯起飞流程会在整个空中阶段隐藏大部分 UI，但会保留 Main/FlyButton 在可操作下落阶段单独显示。后续若继续调整这套飞行手感，必须同步更新 JetpackController、JetpackService、SlideController、GameConfig 与本文档。
13. RequestBrainrotStealPurchaseClosed 不能作为发货依据，真正发货只以 pending request 与 Marketplace receipt 为准。
14. 当前家园拓展基于 Workspace 预置楼层显隐；若未来恢复克隆楼层方案，必须同步更新 HomeExpansionService 与本文档。

=====================================================
文档结束
=====================================================
]]




