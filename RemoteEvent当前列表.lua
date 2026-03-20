--[[
=====================================================
RemoteEvent 当前列表（V2.9）
=====================================================

文档更新时间: 2026-03-20
说明:
- V2.3 全局排行榜未新增 RemoteEvent。
- V2.4.1 特殊事件新增 2 个 RemoteEvent，用于同步客户端本地表现。
- V2.5 脑红升级新增 2 个 RemoteEvent，用于客户端点击升级与本地音效反馈。
- V2.6 脑红出售新增 2 个 RemoteEvent，用于客户端出售单个/全部脑红与本地成功音效反馈。
- V2.7 家园拓展新增 2 个 RemoteEvent，用于客户端请求购买下一个拓展格子与本地失败音效反馈。
- V2.7 Studio 调试面板新增 2 个 RemoteEvent，仅 Studio 环境下用于测试发放脑红。
- V2.9 赠送礼物新增 3 个 RemoteEvent，用于发送赠送请求、接收方确认，以及发起方/接收方反馈同步。
- /event <事件Id> 为 GM 聊天命令，由服务端直接处理。

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
    - RequestHomeExpansion [V2.7]
    - HomeExpansionFeedback [V2.7]
    - SpecialEventStateSync
    - RequestSpecialEventStateSync
  - BrainrotEvents
    - BrainrotStateSync
    - RequestBrainrotStateSync
    - RequestBrainrotUpgrade
    - BrainrotUpgradeFeedback
    - RequestBrainrotSell  [V2.6]
    - BrainrotSellFeedback [V2.6]
    - BrainrotGiftOffer [V2.9]
    - RequestBrainrotGiftDecision [V2.9]
    - BrainrotGiftFeedback [V2.9]
    - RequestStudioBrainrotGrant [Studio Only]
    - StudioBrainrotGrantFeedback [Studio Only]

二、事件详情
1. CoinChanged（S -> C）
- 参数: total / delta / reason / timestamp
- 用途: 金币数值同步，并驱动本地金币滚动反馈。
- 备注: V2.5 起 total / delta 允许小数；主界面 CoinNum 仍显示整数且向上取整。

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
- 用途: 刷新 Rebirth 面板和主界面左侧 Rebirth 显示。

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

15. SpecialEventStateSync（S -> C）
- 参数: activeEvents / serverTime / timestamp
- activeEvents[i]: runtimeKey / eventId / name / templateName / lightingPath / startedAt / endsAt / source
- 用途: 同步当前服务器正在生效的特殊事件列表，供客户端在本地挂角色事件模板和本地切换天空盒。

16. RequestSpecialEventStateSync（C -> S）
- 参数: 无
- 用途: 客户端主动请求当前特殊事件状态，避免本地启动晚于首次服务端推送时漏掉事件。

17. BrainrotStateSync（S -> C）
- 参数: inventory / placed / equippedInstanceId / unlockedBrainrotIds / discoveredCount / discoverableCount / totalProductionBaseSpeed / totalProductionMultiplier / totalProductionSpeed
- inventory[i]: instanceId / brainrotId / name / icon / quality / qualityName / rarity / rarityName / level / baseCoinPerSecond / coinPerSecond / nextUpgradeCost / sellPrice / modelPath
- placed[i]: positionKey / instanceId / brainrotId / name / level / baseCoinPerSecond / coinPerSecond / nextUpgradeCost / quality / rarity
- 用途: 同步脑红背包、放置状态、图鉴解锁历史，以及当前总产速汇总信息。
- 备注: V2.6 起 inventory[i] 新增 sellPrice，供出售界面直接渲染单个脑红售价。

18. RequestBrainrotStateSync（C -> S）
- 参数: 无
- 用途: 客户端主动请求脑红与图鉴状态。

19. RequestBrainrotUpgrade（C -> S）
- 参数: positionKey
- 用途: 请求升级指定 Position 上当前已放置的脑红。
- 校验: 服务端校验位置是否存在脑红、金币是否足够、请求频率是否合法。
- 版本: V2.5 新增。

20. BrainrotUpgradeFeedback（S -> C）
- 参数: status / positionKey / currentLevel / nextLevel / upgradeCost / currentCoins / timestamp
- 用途: 返回脑红升级结果，供客户端播放成功/失败音效。
- 状态值: Success / NotEnoughCoins / NoBrainrot / BrainrotNotFound / CurrencyFailed
- 版本: V2.5 新增。

21. RequestBrainrotSell（C -> S）
- 参数: payload.instanceId 或 payload.sellAll
- 用途: 请求出售单个脑红，或一键出售全部背包脑红。
- 校验: 服务端重新校验实例是否真实存在于玩家背包、售价是否有效、请求频率是否合法。
- 版本: V2.6 新增。

22. BrainrotSellFeedback（S -> C）
- 参数: status / soldCount / soldValue / remainingInventoryCount / mode / currentCoins / soldInstanceId / timestamp
- 用途: 返回出售结果，供客户端播放出售成功音效，并在背包为空时自动关闭出售面板。
- 状态值: Success / InvalidInstanceId / BrainrotNotFound / BrainrotConfigMissing / SellValueInvalid / InventoryEmpty / CurrencyFailed
- 版本: V2.6 新增。

23. RequestHomeExpansion（C -> S）
- 参数: 无
- 用途: 请求购买“下一个”家园拓展格子。
- 校验: 服务端重新校验当前已解锁数量、下一档价格、金币余额与请求频率，不接受客户端指定楼层、位置或价格。
- 版本: V2.7 新增。

24. HomeExpansionFeedback（S -> C）
- 参数: status / unlockedExpansionCount / nextUnlockPrice / currentCoins / timestamp
- 用途: 返回家园拓展购买结果，供客户端播放失败音效。
- 状态值: Success / MissingHome / AlreadyMax / NotEnoughCoins / CurrencyFailed
- 版本: V2.7 新增。

25. BrainrotGiftOffer（S -> C）
- 参数: requestId / senderUserId / senderName / brainrotId / brainrotLevel / brainrotName / createdAt / timestamp
- 用途: 向接收方强制弹出 Gift 确认弹窗，并提供赠送者头像、名字和脑红名称渲染所需信息。
- 版本: V2.9 新增。

26. RequestBrainrotGiftDecision（C -> S）
- 参数: payload.requestId / payload.decision
- 用途: 接收方提交 Accept / Decline / Close 决策。
- 校验: 服务端必须重新校验 requestId 真实存在、接收方身份匹配、赠送实例仍在发送方背包中，且不能把 Close 当成绕过校验的成功路径。
- 版本: V2.9 新增。

27. BrainrotGiftFeedback（S -> C）
- 参数: status / requestId / targetUserId / senderUserId / recipientUserId / cooldownExpiresAt / brainrotName / timestamp
- 用途: 同步赠送发起、接受、拒绝、取消、过期与 5 分钟拒绝冷却，供发起方隐藏 Prompt、供接收方关闭弹窗。
- 状态值: Requested / Accepted / Declined / Cancelled / Expired / SenderBusy / TargetBusy / SenderNotHoldingBrainrot / InvalidRequest
- 版本: V2.9 新增。

28. RequestStudioBrainrotGrant（C -> S）
- 参数: payload.brainrotId
- 用途: 仅供 Studio 环境下的本地调试面板请求给当前玩家发放 1 个指定脑红。
- 校验: 服务端必须校验当前运行环境为 Studio，且 brainrotId 必须真实存在于 BrainrotConfig.ById。
- 版本: V2.7 开发调试新增。

29. StudioBrainrotGrantFeedback（S -> C）
- 参数: status / brainrotId / brainrotName / grantedCount / timestamp
- 用途: 返回 Studio 调试发放结果，供本地测试面板显示成功或失败提示。
- 状态值: Success / NotStudio / InvalidBrainrotId / BrainrotNotFound / PlayerDataNotReady / GrantFailed
- 版本: V2.7 开发调试新增。

三、行为补充说明
1. Index 界面继续复用 BrainrotStateSync，不额外新增 Index 专属 RemoteEvent。
2. Claim UI 路径已切换为 ClaimX/Touch/.../Money(Frame)，但网络事件结构不变。
3. Rebirth 成功后会重新下发 RebirthStateSync 与 BrainrotStateSync，以刷新前端表现。
4. 全局排行榜公共榜单由服务端直接渲染到场景 UI，底部个人卡使用玩家 Attribute，不通过 RemoteEvent 驱动。
5. TotalPlaySeconds 为永久数据，其更新逻辑不依赖新增 RemoteEvent。
6. V2.4.1 起，特殊事件改为“服务端调度 + 客户端本地表现”。
7. V2.5 起，脑红升级台 BrandX 的文本内容由服务端直接刷新，箭头动画与音效由客户端本地负责。
8. V2.6 的出售界面打开逻辑不新增专属 RemoteEvent：
- 顶部 Sell 按钮继续复用 RequestQuickTeleport 处理传送。
- 打开/关闭 SellBrainrots 面板、Shop02/PrisonerTouch 触碰检测，全部在客户端本地处理。
9. 脑红出售成功后，服务端会先加金币，再刷新 BrainrotStateSync；客户端仅根据 BrainrotSellFeedback 播放本地音效和自动关闭面板。
10. V2.7 的 BaseUpgrade 世界 UI 文案由服务端直接刷新；客户端只发送 RequestHomeExpansion，并根据 HomeExpansionFeedback 做本地失败反馈。
11. V2.9 的 Gift 弹窗强制由服务端赠送请求驱动；客户端只负责本地 UI 表现、Prompt 过滤和把 Accept / Decline / Close 决策回传。
12. Studio 调试面板只允许在 Studio 环境下使用；即便客户端错误触发，请求也会被服务端以 NotStudio 拒绝。

四、维护约束
1. 当 RemoteEvent 发生变化时，必须同步更新：
- 本文件
- 架构设计文档.lua
- RemoteNames.lua
- RemoteEventService.lua

2. 所有客户端 -> 服务端请求都必须保留服务端校验。
3. ClaimCashFeedback 必须继续保持 FireClient 给触发者本人，不可广播。
4. 特殊事件当前只同步“事件状态”，不直接同步具体本地实例；客户端负责根据状态自己生成和移除本地表现。
5. RequestBrainrotUpgrade 不能直接相信客户端提交的等级、费用或金币，服务端必须重新计算。
6. RequestBrainrotSell 不能直接相信客户端提交的售价、脑红等级、脑红配置或金币结果，服务端必须重新计算。
7. RequestHomeExpansion 不能直接相信客户端提交的楼层、价格、位置或已解锁数量，服务端必须只按下一档配置顺序处理。
8. RequestBrainrotGiftDecision 不能直接相信客户端提交的赠送者、脑红名字、脑红等级或结果状态，服务端必须只按 pending request 和真实背包实例处理。
9. RequestStudioBrainrotGrant 只允许用于 Studio 调试，不可作为正式玩法逻辑入口。

=====================================================
列表结束
=====================================================
]]




