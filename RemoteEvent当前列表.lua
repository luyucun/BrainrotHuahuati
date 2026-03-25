--[[
=====================================================
RemoteEvent 当前列表（V3.2.0）
=====================================================

文档更新时间: 2026-03-24
说明:
- V3.1 新增 4 个 Launch Power 相关 RemoteEvent，用于弹射力状态同步、升级请求与本地反馈。
- V3.1.2 新增 4 个 Steal 相关 RemoteEvent / 提示事件，用于偷取 Developer Product 购买链路和被偷提示。
- V3.2 新增 5 个 Jetpack 相关 RemoteEvent，用于喷气背包状态同步、金币购买、装备切换与本地反馈。
- 滑梯功能继续完全本地处理，不新增 RemoteEvent。
- /event <事件Id> 仍为 GM 聊天命令，由服务端直接处理。

一、事件树
ReplicatedStorage
- Events
  - CurrencyEvents
    - CoinChanged
    - RequestCoinSync
  - SystemEvents
    - HomeAssigned
    - LikeTip
    - SocialStateSync
    - RequestSocialStateSync
    - FriendBonusSync
    - RequestFriendBonusSync
    - RequestQuickTeleport
    - ClaimCashFeedback
    - RebirthStateSync
    - RequestRebirthStateSync
    - RequestRebirth
    - RebirthFeedback
    - RequestHomeExpansion
    - HomeExpansionFeedback
    - SpecialEventStateSync
    - RequestSpecialEventStateSync
    - LaunchPowerStateSync [V3.1]
    - RequestLaunchPowerStateSync [V3.1]
    - RequestLaunchPowerUpgrade [V3.1]
    - LaunchPowerFeedback [V3.1]
    - JetpackStateSync [V3.2]
    - RequestJetpackStateSync [V3.2]
    - RequestJetpackCoinPurchase [V3.2]
    - RequestJetpackEquip [V3.2]
    - JetpackFeedback [V3.2]
    - StealTip [V3.1.2]
  - BrainrotEvents
    - BrainrotStateSync
    - RequestBrainrotStateSync
    - RequestBrainrotUpgrade
    - BrainrotUpgradeFeedback
    - RequestBrainrotSell
    - BrainrotSellFeedback
    - BrainrotGiftOffer
    - RequestBrainrotGiftDecision
    - BrainrotGiftFeedback
    - RequestStudioBrainrotGrant
    - StudioBrainrotGrantFeedback
    - PromptBrainrotStealPurchase [V3.1.2]
    - RequestBrainrotStealPurchaseClosed [V3.1.2]
    - BrainrotStealFeedback [V3.1.2]

二、事件详情
1. CoinChanged（S -> C）
- 参数: total / delta / reason / timestamp
- 用途: 金币数值同步，并驱动本地金币滚动反馈。
- 备注: total / delta 允许小数；主界面 CoinNum 仍显示整数且向上取整。

2. RequestCoinSync（C -> S）
- 参数: 无
- 用途: 客户端主动请求最新金币数据。

3. HomeAssigned（S -> C）
- 参数: homeId
- 用途: 告知客户端当前玩家被分配到哪个家园。

4. LikeTip（S -> C）
- 参数: message / timestamp
- 用途: 给点赞发送方或被点赞方弹出提示。

5. SocialStateSync（S -> C）
- 参数: likedOwnerUserIds
- 用途: 同步当前玩家已经点过赞的家园主人列表，用于 Prompt 可见性过滤。

6. RequestSocialStateSync（C -> S）
- 参数: 无
- 用途: 客户端主动请求社交状态。

7. FriendBonusSync（S -> C）
- 参数: friendCount / bonusPercent / timestamp
- 用途: 同步当前同服好友数量与加成百分比。

8. RequestFriendBonusSync（C -> S）
- 参数: 无
- 用途: 客户端主动请求好友加成状态。

9. RequestQuickTeleport（C -> S）
- 参数: payload.target（Home / Shop / Sell）
- 用途: 请求服务端执行快捷传送。
- 校验: 仅允许固定枚举目标，坐标始终由服务端解析。

10. ClaimCashFeedback（S -> C）
- 参数: positionKey / claimKey / timestamp
- 用途: 只通知触发领取的玩家，在本地播放领取音效与金币飞散回收特效。
- 规则: 仅当该位置确实有已放置脑红且本次真实领取到金币时才下发。

11. RebirthStateSync（S -> C）
- 参数: rebirthLevel / currentBonusRate / nextRebirthLevel / nextRequiredCoins / nextBonusRate / maxRebirthLevel / isMaxLevel / currentCoins / timestamp
- 用途: 刷新 Rebirth 面板和主界面 Rebirth 显示。

12. RequestRebirthStateSync（C -> S）
- 参数: 无
- 用途: 客户端主动请求最新 Rebirth 状态。

13. RequestRebirth（C -> S）
- 参数: 无
- 用途: 发起一次 Rebirth 请求。
- 校验: 服务端根据当前玩家真实数据判断是否满足条件。

14. RebirthFeedback（S -> C）
- 参数: status / message / timestamp
- 用途: 返回成功提示或失败原因。
- 状态值: Success / RequirementNotMet / AlreadyMax

15. RequestHomeExpansion（C -> S）
- 参数: 无
- 用途: 请求购买“下一个”家园拓展格子。
- 校验: 服务端重新校验当前已解锁数量、下一档价格、金币余额与请求频率，不接受客户端指定楼层、位置或价格。

16. HomeExpansionFeedback（S -> C）
- 参数: status / unlockedExpansionCount / nextUnlockPrice / currentCoins / timestamp
- 用途: 返回家园拓展购买结果，供客户端播放失败音效或刷新本地文案。
- 状态值: Success / MissingHome / AlreadyMax / NotEnoughCoins / CurrencyFailed

17. SpecialEventStateSync（S -> C）
- 参数: activeEvents / serverTime / timestamp
- activeEvents[i]: runtimeKey / eventId / name / templateName / lightingPath / startedAt / endsAt / source
- 用途: 同步当前服务器正在生效的特殊事件列表，供客户端在本地挂角色事件模板和本地切换天空盒。

18. RequestSpecialEventStateSync（C -> S）
- 参数: 无
- 用途: 客户端主动请求当前特殊事件状态，避免本地启动晚于首次服务端推送时漏掉事件。

19. LaunchPowerStateSync（S -> C）
- 参数: currentLevel / currentValue / nextLevel / nextValue / nextCost / bulkUpgradeCount / bulkNextLevel / bulkNextValue / bulkNextCost / currentCoins / speedPerPoint / timestamp
- 用途: 刷新弹射力升级面板与玩家本地 Launch Power Attribute 对应的界面表现。
- 版本: V3.1 新增。

20. RequestLaunchPowerStateSync（C -> S）
- 参数: 无
- 用途: 客户端主动请求当前 Launch Power 状态。
- 版本: V3.1 新增。

21. RequestLaunchPowerUpgrade（C -> S）
- 参数: payload.upgradeCount
- 用途: 请求购买 1 级或 10 级 Launch Power。
- 校验: 服务端只接受 upgradeCount = 1 或 10，并重新校验金币余额与请求频率。
- 版本: V3.1 新增。

22. LaunchPowerFeedback（S -> C）
- 参数: status / message / timestamp
- 用途: 返回弹射力升级结果，供客户端做本地提示或错误处理。
- 状态值: Success / Debounced / MissingData / InvalidUpgradeCount / InsufficientCoins / SpendFailed
- 版本: V3.1 新增。

23. JetpackStateSync（S -> C）
- 参数: ownedJetpackIds / equippedJetpackId / timestamp
- 用途: 同步喷气背包拥有列表与当前装备项，供客户端渲染 Main/Jetpack 面板。
- 规则: ownedJetpackIds 为已拥有背包 Id 数组；1001 默认会被服务端视为已解锁。
- 版本: V3.2 新增。

24. RequestJetpackStateSync（C -> S）
- 参数: 无
- 用途: 客户端主动请求最新喷气背包拥有/装备状态。
- 版本: V3.2 新增。

25. RequestJetpackCoinPurchase（C -> S）
- 参数: payload.jetpackId
- 用途: 请求使用金币购买指定喷气背包。
- 校验: 服务端重新校验 jetpackId 是否存在、是否已拥有、金币余额是否足够，以及请求频率是否合法。
- 版本: V3.2 新增。

26. RequestJetpackEquip（C -> S）
- 参数: payload.jetpackId
- 用途: 请求把指定已拥有喷气背包装备到当前角色。
- 校验: 服务端重新校验 jetpackId 是否真实存在且玩家已拥有，不相信客户端本地 UI 状态。
- 版本: V3.2 新增。

27. JetpackFeedback（S -> C）
- 参数: status / jetpackId / message / timestamp
- 用途: 返回喷气背包购买、装备和失败反馈，供客户端刷新面板或播放购买成功提示。
- 状态值: CoinPurchased / RobuxPurchaseGranted / Equipped / Debounced / InvalidJetpack / MissingData / AlreadyOwned / InsufficientCoins / SpendFailed / NotOwned
- 版本: V3.2 新增。

28. StealTip（S -> C）
- 参数: message / timestamp
- 用途: 只发给被偷者本人，显示“[xxx] steal your [yyy]!”提示。
- 版本: V3.1.2 新增。

29. BrainrotStateSync（S -> C）
- 参数: inventory / placed / equippedInstanceId / unlockedBrainrotIds / discoveredCount / discoverableCount / totalProductionBaseSpeed / totalProductionMultiplier / totalProductionSpeed
- inventory[i]: instanceId / brainrotId / name / icon / quality / qualityName / rarity / rarityName / level / baseCoinPerSecond / coinPerSecond / nextUpgradeCost / sellPrice / modelPath
- placed[i]: positionKey / instanceId / brainrotId / name / level / baseCoinPerSecond / coinPerSecond / nextUpgradeCost / quality / rarity
- 用途: 同步脑红背包、放置状态、图鉴解锁历史，以及当前总产速汇总信息。

30. RequestBrainrotStateSync（C -> S）
- 参数: 无
- 用途: 客户端主动请求脑红与图鉴状态。

31. RequestBrainrotUpgrade（C -> S）
- 参数: positionKey
- 用途: 请求升级指定 Position 上当前已放置的脑红。
- 校验: 服务端重新校验脑红存在、金币余额与请求频率。

32. BrainrotUpgradeFeedback（S -> C）
- 参数: status / positionKey / currentLevel / nextLevel / upgradeCost / currentCoins / timestamp
- 用途: 返回脑红升级结果，供客户端播放成功/失败音效。
- 状态值: Success / NotEnoughCoins / NoBrainrot / BrainrotNotFound / CurrencyFailed

33. RequestBrainrotSell（C -> S）
- 参数: payload.instanceId 或 payload.sellAll
- 用途: 请求出售单个脑红，或一键出售全部背包脑红。
- 校验: 服务端重新校验实例是否真实存在于玩家背包、售价是否有效、请求频率是否合法。

34. BrainrotSellFeedback（S -> C）
- 参数: status / soldCount / soldValue / remainingInventoryCount / mode / currentCoins / soldInstanceId / timestamp
- 用途: 返回出售结果，供客户端播放出售成功音效，并在背包为空时自动关闭出售面板。
- 状态值: Success / InvalidInstanceId / BrainrotNotFound / BrainrotConfigMissing / SellValueInvalid / InventoryEmpty / CurrencyFailed

35. BrainrotGiftOffer（S -> C）
- 参数: requestId / senderUserId / senderName / brainrotId / brainrotLevel / brainrotName / createdAt / timestamp
- 用途: 向接收方强制弹出 Gift 确认弹窗，并提供赠送者头像、名字和脑红名称渲染所需信息。

36. RequestBrainrotGiftDecision（C -> S）
- 参数: payload.requestId / payload.decision
- 用途: 接收方提交 Accept / Decline / Close 决策。
- 校验: 服务端必须重新校验 requestId 真实存在、接收方身份匹配、赠送实例仍在发送方背包中。

37. BrainrotGiftFeedback（S -> C）
- 参数: status / requestId / targetUserId / senderUserId / recipientUserId / cooldownExpiresAt / brainrotName / timestamp
- 用途: 同步赠送发起、接受、拒绝、取消、过期与拒绝冷却，供发起方隐藏 Prompt、供接收方关闭弹窗。
- 状态值: Requested / Accepted / Declined / Cancelled / Expired / SenderBusy / TargetBusy / SenderNotHoldingBrainrot / InvalidRequest

38. RequestStudioBrainrotGrant（C -> S）
- 参数: payload.brainrotId
- 用途: 仅供 Studio 环境下的本地调试面板请求给当前玩家发放 1 个指定脑红。
- 校验: 服务端必须校验当前运行环境为 Studio，且 brainrotId 必须真实存在于 BrainrotConfig.ById。

39. StudioBrainrotGrantFeedback（S -> C）
- 参数: status / brainrotId / brainrotName / grantedCount / timestamp
- 用途: 返回 Studio 调试发放结果，供本地测试面板显示成功或失败提示。
- 状态值: Success / NotStudio / InvalidBrainrotId / BrainrotNotFound / PlayerDataNotReady / GrantFailed

40. PromptBrainrotStealPurchase（S -> C）
- 参数: requestId / productId / brainrotId / brainrotName / ownerUserId / ownerName / priceRobux / quality / timestamp
- 用途: 要求客户端弹出对应 Developer Product 的购买界面。
- 版本: V3.1.2 新增。

41. RequestBrainrotStealPurchaseClosed（C -> S）
- 参数: payload.requestId / payload.productId / payload.isPurchased / payload.status
- 用途: 告知服务端购买弹窗是否关闭，以及客户端是否认为已购买。
- 规则: status 只可能作为本地失败补充字段上传；服务端可信判断只看 pending request 与 Marketplace receipt，不以这里的 isPurchased 直接发货。
- 版本: V3.1.2 新增。

42. BrainrotStealFeedback（S -> C）
- 参数: status / message / requestId / productId / brainrotId / brainrotName / timestamp
- 用途: 同步偷取流程的阶段结果、失败原因和最终成功状态。
- 状态值: PurchasePending / TargetNotReady / BrainrotUnavailable / BrainrotConfigMissing / ProductMissing / PendingCreateFailed / PromptUnavailable / Cancelled / Success
- 版本: V3.1.2 新增。

三、行为补充说明
1. Index 界面继续复用 BrainrotStateSync，不额外新增 Index 专属 RemoteEvent。
2. Claim UI 路径已切换为 ClaimX/Touch/.../Money(Frame)，但网络事件结构不变。
3. Rebirth 成功后会重新下发 RebirthStateSync 与 BrainrotStateSync，以刷新前端表现。
4. 全局排行榜公共榜单由服务端直接渲染到场景 UI，底部个人卡使用玩家 Attribute，不通过 RemoteEvent 驱动。
5. Launch Power 面板的打开逻辑不新增专属 Remote:
- 顶部 Shop 按钮仍继续复用 RequestQuickTeleport 处理传送。
- 面板开关、Garamararam Prompt、本地按钮动效全部由客户端控制。
6. 脑红出售面板的打开逻辑同样不新增专属 Remote:
- 顶部 Sell 按钮继续复用 RequestQuickTeleport 处理传送。
- 面板开关、Madudung Prompt、本地按钮动效全部由客户端控制。
7. Jetpack 的 Robux 购买弹窗由客户端直接调用 MarketplaceService:PromptProductPurchase 打开，不额外新增“打开购买弹窗”的 Remote。
8. Jetpack 真正的 Robux 发货只发生在服务端 Marketplace receipt 成功结算后；客户端本地 PromptProductPurchaseFinished 只用于补发一次状态刷新请求。
9. 当前 Jetpack 只实现解锁、装备、饰品挂载与 UI 反馈；NoGravityDuration / BulletTimeFallSpeed 只作为配置和界面展示，不通过任何 Remote 驱动玩法。
10. 偷取脑红真正发货只发生在 Marketplace receipt 成功结算后；RequestBrainrotStealPurchaseClosed 绝不能被当成发货真值。
11. StealTip 必须继续保持只发给被偷者本人，不可广播。
12. 滑梯功能当前完全本地实现，不通过任何 RemoteEvent 驱动。

四、维护约束
1. 当 RemoteEvent 发生变化时，必须同步更新:
- 本文件
- 架构设计文档.lua
- RemoteNames.lua
- RemoteEventService.lua

2. 所有客户端 -> 服务端请求都必须保留服务端校验。
3. ClaimCashFeedback 必须继续保持 FireClient 给触发者本人，不可广播。
4. RequestLaunchPowerUpgrade 不能直接相信客户端提交的任意升级数量，服务端必须只接受 1 或 10。
5. RequestJetpackCoinPurchase 不能直接相信客户端提交的 jetpackId、价格或拥有状态，服务端必须重新校验。
6. RequestJetpackEquip 不能直接相信客户端提交的装备结果，服务端必须只按真实已拥有背包处理。
7. RequestBrainrotUpgrade 不能直接相信客户端提交的等级、费用或金币，服务端必须重新计算。
8. RequestBrainrotSell 不能直接相信客户端提交的售价、脑红等级、脑红配置或金币结果，服务端必须重新计算。
9. RequestHomeExpansion 不能直接相信客户端提交的楼层、价格、位置或已解锁数量，服务端必须只按下一档配置顺序处理。
10. RequestBrainrotGiftDecision 不能直接相信客户端提交的赠送者、脑红名字、脑红等级或结果状态，服务端必须只按 pending request 和真实背包实例处理。
11. RequestBrainrotStealPurchaseClosed 不能直接相信客户端提交的 isPurchased 或 status，服务端必须只按 pending request 和 Marketplace receipt 处理。
12. RequestStudioBrainrotGrant 只允许用于 Studio 调试，不可作为正式玩法逻辑入口。

=====================================================
列表结束
=====================================================
]]
