项目概述与简介
1.这是一款基于roblox的游戏项目，大致是一个增量模拟器类似的玩法，玩家通过获取对应的脑红或者其他什么养成维度的东西，来获取金币，使用金币来提升自己的能力
2.大框架大概是：每个玩家有自己的基地，有自己的金币数据，玩家可以取对应区域拿起脑红放置到自己的基地，脑红每秒会为玩家产出一定数量的金币，玩家获取金币后可以提升自身能力
3.每个玩家的金币和能力或者养成维度都是自己的，互相与其他玩家不干扰

详细需求：

需求V1.0 
玩家出生家园分配：

1.在我们的游戏中，目前设定为一个服务器最多容纳5个玩家
2.在我们的游戏设定中，每个玩家都有一个自己的家园，具体的结构是下面这样的：
    2.1在Workspace下，有一个叫PlayerHome的总文件夹，用于存放每个玩家自己的基地，比如PlayerHome下有Home01到Home05共5个文件夹
    2.2每个文件夹下都有一个叫HomeBase的，然后在HomeBase下有一个叫SpawnLocation的出生点，玩家出生时就出生在自己基地的SpawnLocation这个位置
    2.3当有玩家进入游戏时，系统会从Home01到Home05当前空闲的基地中随机分配一个给玩家，然后加载玩家的对应数据即可，注意这里一定不要给两个玩家分配到同一个基地里
    2.4至于玩家的基地里的数据，后续随着我们的版本开发，会逐步丰富各种数据，这里要做好拓展，为后续的各种功能开发做好准备

玩家基础数据：金币

1.每个玩家都有一个基础的金币数据，玩家的初始的金币数据暂时设定为：0
2.StarterGui - Main - Cash - CoinNum是一个textlabel，用于显示玩家的金币数值，这个数值不使用大数值缩写，是多少就显示多少，但是要注意：这里需要显示的大数值需要是欧美的那种计数法，比如每3个数值后面就得有个逗号这种
3.玩家的金币数值发生变化的时候，这里的数值需要实时发生变化，并且变化时需要有个变化动效，具体表现效果逻辑是：
    3.1CoinNum自身的数值发生滚动变化，大概在0.6秒内完成数字的滚动变化
    3.2在滚动变化的过程中，CoinNum需要2次快速的小幅度的放大然后缩回原来大小，连续抖动2次，代表代表我的数字发生了变化
    3.3在变化开始的时候，需要立刻把Main - Cash - CoinAdd的visible属性改成true，然后把文本内容改成+$xxx,xxx是本次变化数值，显示格式和CoinNum一样。在显示出来的时候，需要有个从左下角往右上角小幅度冒出来的动效，大概是冒出来然后回弹到目标位置，弹出时长大概0.3秒左右完成，弹出结束后立刻开始让CoinAdd的透明度在0.6秒内从0变成1消失不可见，然后这条出现的再移除即可
    3.4在变化时，如果短期内快速发生了金币数值变化，也就是连续弹出两个CoinAdd（注意这是个模板，每次变化都需要弹出一个），每次弹出时都把上一个未消失的顶到更高的位置，不要重叠

Gm需求：
1.增加一个命令，/addcoins xxxx
2.这个命令只有开发者可以使用，且只有在studio环境下可以使用，使用效果是增加对应数值的金币

注意：
关于玩家数据：studio中测试数据要与线上的玩家的数据要进行隔离互不干扰，这里要打好基底


需求文档V1.1 脑红基础逻辑

基础概念：
1.在我们的游戏中，设定一种叫脑红的道具，可以理解为传统游戏中的宠物系统或者宝可梦系统，一个脑红就是一个宠物或者一个宝可梦

脑红基础属性
1.我们会设定一张基础的脑红表配置，里面有一些基础的脑红配置：脑红的id/脑红的模型名字/脑红的图标等内容
2.脑红基础产速：每个脑红都会每秒产出一定数值的金币，不同的脑红每秒产出金币数值不同
3.脑红的品质：每个脑红都有一个基础的品质属性，目前我们设定品质从低到高：Common/Uncommon/rare/Epic/Legendary/Mythic/Secret/God/OG这几种，在脑红表中用数字1到9代表这9种品质
4.脑红的稀有度：每个脑红都有一个基础的稀有度属性，目前我们设定稀有度从低到高：Normal/Gold/Diamond/Lava/Galaxy/Hacker/Rainbow这几种，在脑红表种用数字1到7代表这七种稀有度
5.脑红的模型路径是：我们在ReplicatedStorage - Model下放着Common/Uncommon/Rare/Epic/Legendary/Mythic/Secret/God/OG这些文件夹，每个文件夹下放着对应的脑红的模型，在我们的配置表中，每个脑红的模型路径配置格式为：文件夹/脑红模型名，比如Common/Biiiibala，就代表在ReplicatedStorage - Model - Common下有个叫Biiiibala的脑红模型

脑红在背包：
1.每个脑红玩家在获取后，会出现在玩家的背包中，玩家点击背包中的脑红，可以触发拿起脑红的动作
2.具体逻辑就是：玩家点击背包中的脑红，脑红出现在玩家的手中，再点击下脑红，脑红从手中消失放回背包

展示平台：
概念：每个玩家家里都有一定数量的脑红展示平台，每个展示平台上都可以放置一个脑红

详细逻辑：
1.我们以PlayerHome - Home01举例，这是其中一个玩家的完整家园
2.PlayerHome - Home01 - HomeBase - Position1是一个Part，其中Position下有个子节点叫Platform，在Platform下有个Attachment，是放置脑红时候脑红的挂载点
3.每个脑红都有PrimaryPart，挂载脑红的时候把PrimaryPart放在Attachment上，给一个参数是朝上的偏移参数，用来控制脑红基础PrimaryPart，参数需要可调

放置操作：
1.玩家靠近PlatForm，PlatForm下有ProximityPrompt，靠近后出现交互按钮，玩家长按交互按钮1秒，触发把脑红放置到位置上

我们的脑红第一版测试配置是：

脑红id	脑红名字	脑红品质	脑红稀有度	脑红模型	基础产出速度/秒	图标
10001	测试脑红01	1	1	Common/67	5	rbxassetid://92295649647469
10002	测试脑红02	2	1	Common/67	5	rbxassetid://92295649647469
10003	测试脑红03	3	1	Common/67	5	rbxassetid://92295649647469
10004	测试脑红04	4	1	Common/67	5	rbxassetid://92295649647469

需求文档V1.2 关于金币的产出表现与领取

1.我们的脑红只有在放置在对应的台子上时，才会开始产出金币，每秒产出一次
2.每个台子上只能同时放置一个脑红
3.我们以Home01举例，Home01 - HomeBase - Claim1是我们的金币展示信息挂载的Part，同时也是我们触发领取金币操作的Part：
    3.1Home01 - HomeBase - Claim1是位置1的金币领取按钮，对应的位置1是Position1，这二者互相绑定，Position1下的脑红产出的金币只能被Claim1领取，Claim1也只能领取Position1下的脑红产出的金币
    3.2Home01 - HomeBase - Claim1 - GoldInfo是一个BillboardGui，当对应的Position上没有被放置脑红时，GoldInfo的Enable属性应该被设定为false，当有脑红时，再把Enable属性改成true
    3.3GoldInfo - Money - CurrentGold是一个texelabel，用于显示这个脑红当前产出的待玩家领取的金币，格式固定是$xxxx，这里固定也是显示欧美那种三个数字一个逗号那种显示方式
    3.4GoldInfo - Money - OfflineGold是一个texelabel，用于显示这个脑红在玩家离线后，累计产出的金币，格式固定是Offline:$xxxx，这里固定也是显示欧美那种三个数字一个逗号那种显示方式
    3.5注意：金币数值实时更新，发生变化时，也要有我们主界面StarterGui - Main - Cash - CoinNum这个数量变化时的效果
    3.6注意：玩家在线时，如果是新玩家，从未产出离线金币，那需要把OfflineGold隐藏，玩家离线在上线，有产出的离线金币，显示出来OfflineGold，玩家领取完后，就立刻隐藏

关于金币产出累计：
1.只要玩家在线，脑红就会不断产出金币
2.玩家离线后，会累计一定的离线金币，最多累计1小时的金币，可以做成玩家再次上线时，去判定本次时间与离线时间之间的差值，计算产出数值，超过一小时最多只算一小时的金币

关于金币领取：
1.玩家触碰Claim1按钮，可以触发对Position1下摆放的脑红产出的金币数值的领取，包括对当前在线产出的金币和离线产出的金币的领取

需求文档V1.2.1  补丁内容
1.我们需要给每个模型加一个待机动画，我希望模型放在platform上后，可以默认不断循环播放这个模型的待机动画，在配置表中增加待机动画字段，也就是说我们目前的测试表改成：
脑红id	脑红名字	脑红品质	脑红稀有度	脑红模型	基础产出速度/秒	图标	待机动画id
10001	测试脑红01	1	1	Common/67	5	rbxassetid://92295649647469	123010310858935
10002	测试脑红02	2	1	Common/67	5	rbxassetid://92295649647469	123010310858935
10003	测试脑红03	3	1	Common/67	5	rbxassetid://92295649647469	123010310858935
10004	测试脑红04	4	1	Common/67	5	rbxassetid://92295649647469	123010310858935

2.补充一些限制：
    2.1当模型拿在手里的时候，玩家不与模型自身带的ProximityPrompt交互，这个也不出现
    2.2当Platform上有放置的脑红模型时，玩家不与platform自身带的ProximityPrompt交互，这个也不出现
3.检查一个bug：为什么玩家的背包数据，有时候关闭游戏会自动清空，有时候不清空？请分析bug原因，我要的是不清空，如果要清理数据我自己会使用gm命令/clear进行操作


需求文档V1.3 玩家信息与点赞操作

概述：
我们需要在玩家的信息板上显示玩家的名字/头像信息，并且可以为玩家点赞

详细规则：
玩家信息显示：
1.我们以Home01举例，Home01 - HomeBase - Information - InfoPart - SurfaceGui01 - Frame - PlayerAvatar - ImageLabel是一个imagelabel，用于显示玩家的头像信息
2.Home01 - HomeBase - Information - InfoPart - SurfaceGui01 - Frame - PlayerName用于显示玩家的名字，如果一个基地没人的时候，默认的信息是显示为：Empty
3.Home01 - HomeBase - Information - InfoPart - ProximityPrompt是交互触发，玩家靠近时，触发交互界面，玩家长按完成交互，可以给该玩家进行点赞：
    3.1玩家靠近自己家园的Information不显示交互按钮
    3.2玩家已经点赞过某个玩家后，再靠近该玩家的Information不显示点赞交互按钮
    3.3玩家A给玩家B点赞时：需要弹出提示：
        3.3.1被点赞者玩家B需要弹出提示：把StarterGui - LikeTips的Visible属性改成true，同时把StarterGui - LikeTips - Text的文本改成[PlayerName] gave you a like!，其中[PlayerName]里面是点赞者的名字，弹出时要有动效，从下方滑到目标位置，然后停留2秒左右消失
        3.3.2点赞者玩家A需要弹出提示，把StarterGui - LikeTips的Visible属性改成true，同时把StarterGui - LikeTips - Text的文本改成：You liked this home!同时弹出效果和消失时间也一致

4.Home01 - HomeBase - Information - InfoPart - SurfaceGui01 - Frame - PlayerLike - Num是用来显示玩家累计获得的点赞数，这个是永久数据，不断累加的，格式固定为：xx Like!注意这里要用单数复数，1个就是1 Like！多个就是xx Likes!

需求文档V1.4 同服务器好友产速加成

概述：当同一个服务器有自己的好友一起在时，玩家的脑红产速会获得加成

详细规则：
1.当服务器有1/2/3/4个共同好友时，玩家的脑红产出速度加10%/20%/30%/40%，也就是每有一个好友在服务器，产出速度就加10%
2.当好友进入游戏后产速立刻开始算，好友离线后立刻移除对应的产速加成

玩家离线后再进来算离线收入时，要按无好友的逻辑来算，只有实时产出的金币每秒产出时才计算加成

客户端规则是：
1.StarterGui - Main - Cash - FriendBonus是一个textlabel，默认文本内容是Friend Bonus: +0%，当有好友加成时需要及时更改文本，比如有1个好友时，文本就是：Friend Bonus: +10%


V1.5 部分小型快捷功能开发

快速回家：
1.玩家点击界面按钮：StarterGui - Main - Top - Home按钮，立刻把玩家传送回家中，也就是自己家里出生点spawnlocation的位置

快速到达商店1：
1.玩家点击界面按钮：StarterGui - Main - Top - Shop按钮，将玩家快速传送至：Workspace - Shop01 - PrisonerTouch的位置，传送时：获取PrisonerTouch的坐标，在
轴高度上加5，让玩家出现在对应的位置即可，我要的效果是玩家传送到对应的天上然后掉下来，这个5这个值应该是可调整的

快速到达商店2：
1.玩家点击界面按钮：StarterGui - Main - Top - Sell按钮，将玩家快速传送至：Workspace - Shop02 - PrisonerTouch的位置，传送时：获取PrisonerTouch的坐标，在
轴高度上加5，让玩家出现在对应的位置即可，我要的效果是玩家传送到对应的天上然后掉下来，这个5这个值应该是可调整的

1.6 脑红信息显示

1.我们在之前的文档中已经说明了，我们的脑红有品质和稀有度两个维度的区分
2.品质从低到高分别是：Common/Uncommon/rare/Epic/Legendary/Mythic/Secret/God/OG，然后稀有度从低到高分别是Normal/Gold/Diamond/Lava/Galaxy/Hacker/Rainbow

头顶信息显示
1.在我们的所有脑红模型中，以Brainrot01举例，ReplicatedStorage - Model - Common - Brainrot01这是脑红的模型路径，这个会配置在脑红对应的路径字段里
    1.1严格地，每个脑红模型下都有一样的结构：（以Brainrot01举例）Brainrot01 - BrainrotModel - RootPart - Info，Info是一个Attachment，用来挂载脑红地ui信息
    1.2ReplicatedStorage - UI - BaseInfo是一个BillboardGui，是用来显示脑红信息地模板，其中
        1.2.1BaseInfo - Title - Name是一个textlabel，用于显示脑红地名字；当前当脑红被放在PlatForm上时，这里的显示格式固定为：脑红名字[Lv.x]，例如BrainrotName[Lv.99]
        1.2.2BaseInfo - Title - Quality是一个textlabel，用于显示脑红的品质名字
        1.2.3BaseInfo - Title - Rarity是一个textlabel，用于显示脑红的稀有度名字
        1.2.4BaseInfo - Title - Speed是一个textlabel，用于显示这个脑红的金币产速，格式固定是：$xxx/S
2.当脑红被玩家拿在手里的时候，不需要给脑红挂载BaseInfo，但是当脑红被放在PlatForm上或者后面我们做规则出现在地上时，都需要给这个脑红挂载一份BaseInfo，然后更改其对应的信息显示出来
3.我们最好是做一张单独的表，用于给每个品质和每个稀有度的名字做显示，显示名字时直接读这个表里的名字即可
4.补充一个：如果一个脑红的稀有度是1也就是Normal，那么不显示Rarity，visible设置为false

品质名与稀有度名字对应
1.我们是想给游戏中的不同品质和稀有度的名字做一个额外的表现，比如赋予一些渐变效果
2.我在下面的品质表和稀有度表中，给每个品质或者稀有度设置了要赋予的渐变效果的路径，需要赋予时，去对应路径下copy一份赋予即可

品质id	名字	渐变路径
1	Common	StarterGui/Gradients/Animation/Quality/Common
2	Uncommon	StarterGui/Gradients/Animation/Quality/Uncommon
3	Rare	StarterGui/Gradients/Animation/Quality/Rare
4	Epic	StarterGui/Gradients/Animation/Quality/Epic
5	Legendary	StarterGui/Gradients/Animation/Quality/Legendary
6	Mythic	StarterGui/Gradients/Animation/Quality/Mythic
7	Secret	StarterGui/Gradients/Animation/Quality/Secret
8	God	StarterGui/Gradients/Animation/Quality/Secret
9	OG	StarterGui/Gradients/Animation/Quality/Secret

稀有度ID	名字	渐变路径
1	Normal	StarterGui/Gradients/Animation/Rarity/Common
2	Gold	StarterGui/Gradients/Animation/Rarity/Gold
3	Diamond	StarterGui/Gradients/Animation/Rarity/Diamond
4	Lava	StarterGui/Gradients/Animation/Rarity/Lava
5	Galaxy	StarterGui/Gradients/Animation/Rarity/Galaxy
6	Hacker	StarterGui/Gradients/Animation/Rarity/Hacker
7	Rainbow	StarterGui/Gradients/Animation/Rarity/Rainbow


我们做一版测试脑红表，具体表是这样的：
脑红id	脑红名字	脑红品质	脑红稀有度	脑红模型	基础产出速度/秒	图标
10001	测试脑红01	1	1	Common/Brainrot01	5	rbxassetid://92295649647469
10002	测试脑红02	2	2	Common/Brainrot02	5	rbxassetid://92295649647469
10003	测试脑红03	3	3	Common/Brainrot03	5	rbxassetid://92295649647469
10004	测试脑红04	4	4	Common/Brainrot01	5	rbxassetid://92295649647469
10005	测试脑红05	5	5	Common/Brainrot02	10	rbxassetid://92295649647469
10006	测试脑红06	6	1	Common/Brainrot03	15	rbxassetid://92295649647469
10007	测试脑红07	7	2	Common/Brainrot01	20	rbxassetid://92295649647469
10008	测试脑红08	8	3	Common/Brainrot02	100	rbxassetid://92295649647469
10009	测试脑红09	9	4	Common/Brainrot03	300	rbxassetid://92295649647469
10010	测试脑红10	9	5	Common/Brainrot01	1000	rbxassetid://92295649647469
10011	测试脑红11	9	6	Common/Brainrot02	15000	rbxassetid://92295649647469
10012	测试脑红12	9	7	Common/Brainrot03	600000	rbxassetid://92295649647469

需求文档V1.7 总产速与服务器内排行榜
1.我们需要给每个玩家计算出一个当前的总产速数值，具体数值就是每个玩家当前摆在展台上的所有的脑红当前的产出速度之和
2.比如A20/s，B是15/S，C是100/S，那么总产速是135/s
3.如果有好友加成，总产速是计算后的数值*加成值

其他：
1.我们在这里定义好我们每个脑红的产速计算公式：最终产速=基础产速*（1+加成1+加成2+加成x...），比如一个好友加10%，然后我们的后面系统中出了某个特权+50%，另一个药水+20%，那么总产速就是基础产速*（1+0.1+0.5+0.2）=基础产速*1.8
2.最终的产速就是所有的摆出来的脑红的产速加和就是总产速

内置排行榜：
1.我们需要给单个服务器内做一个内置排行榜（默认电脑端点tab调起来那个单服内置榜单）
2.这个榜单的排名依据是玩家当前拥有的总的现金数，注意是当前拥有的，字段名就用Cash
3.显示内容就是：排名/玩家名字/现金数
4.这里需要搞一套大数值显示规则，显示在这里，其他地方不用大数值，但是这里是要显示大数值的，K/M/B 等这套大数值体系

需求文档V1.8 关于领取金币时的表现
概述：我们需要在玩家领取金币时做出一些表现来

详细规则：
1.目前的逻辑是：玩家触碰Claim按钮会触发领取金币，比如触碰Claim5会触发对Position5下放置的脑红的金币的领取
2.在领取时我们做一些表现：
    2.1以Claim1举例，玩家触碰到Claim1时，CLaim1这这part需要往下移动一下然后再快速恢复，看起来像是被按压了一下
    2.2触碰到CLaim1时，在播放按压的时候，需要同步播放一个音频，注意只有玩家自己能听到玩家自己客户端的音效，音效资源id是：rbxassetid://139922061047157，路径是SoundService - Audio - ADDCash
    2.3当触碰到Claim1时，需要把放在Platform上当前展示的脑红往上弹一下然后再掉回原位，类似我踩了一下claim按钮，然后脑红自己小幅度被弹起来，然后恢复原位
    2.4注意在按钮被按下和脑红被弹起的效果，感觉都做得Q弹一点，有点缓动，不要生硬的匀速直线上下
    2.5在触碰Claim1 的时候，还需要播放粒子特效，具体逻辑是：
        2.5.1去ReplicatedStorage - Effect下找一个叫EffectTouchMoney的Part，复制出来放在Claim1上
        2.5.2EffectTouchMoney - Attachment - Glow是一个ParticleEmitter，在EffectTouchMoney被复制出来的瞬间，需要让Glow迅速立刻发射1次粒子，类似语法是emitter:Emit(1)，这个你可以自己查怎么写
        2.5.3EffectTouchMoney - Attachment - Smoke和Glow是同一层级，然后按同样的方式来播一次粒子
        2.5.4在Smoke和Glow发射一次粒子后，0.3秒，立刻把Attachment及子节点全部移除
        2.5.5EffectTouchMoney - Money也是一个ParticleEmitter，EffectTouchMoney - Stars也是ParticleEmitter，就按正常效果播放粒子即可
        2.5.6在EffectTouchMoney被复制出来1秒后，移除EffectTouchMoney及所有子节点
        2.5.7如果玩家快速多次触碰Claim1，那么再次触碰的时候，需要先立刻把原来还未移除的EffectTouchMoney移除并立刻重新走一遍复制生成流程

    2.6玩家如果一直站在claim1上不动，那最多只算一次领取，但是如果站在CLaim上移动，只要移动了那么每秒最多可以触发一次领取流程，至于玩家离开按钮再触碰就不做限制只要离开再触碰就算立刻触发一次领取

需求文档V1.8.1  关于特效实现的修改
1.我们把特效的实现逻辑统一修改为：每次触碰Touch时，都去ReplicatedStorage - Effect - Claim下复制Glow和Smoke，然后挂载给Touch，控制Glow和Smoke，每个都Emit（1），也就是各自只播放一次，等播放完成后销毁，要等粒子的生命周期结束后再销毁
2.同时还要在ReplicatedStorage - Effect - Claim下复制Money和Stars，也挂载给Touch，这个是每个固定1.5秒后移除

需求文档V1.8.2  新增领取金币时的动画需求

概述：就是玩家触碰Touch的时候，在Touch上瞬间爆开一批金币图标然后飞向玩家，下面是具体需求

1.1 效果目标
当玩家角色触碰并触发按压板后，立即出现一组金币图标特效。
 这组金币图标需要呈现出如下完整观感：
. 从触发点上方瞬间出现
. 先向周围短距离爆裂式散开
. 随后快速转向并飞向触发玩家身体
. 接近玩家身体时逐个消失
. 配合“奖励被吸收到角色身上”的明确视觉反馈
最终视觉目标不是普通掉落物，也不是简单直线飞行，而是：
“先炸开，再回收吸附到玩家身上”的奖励收集动效。

---
2. 使用素材
2.1 图标资源
所有飞行动画中的奖励图标统一使用以下图片资源：
rbxassetid://92295649647469
2.2 图标表现形式
图标必须使用始终朝向摄像机的2D图标表现，不要使用会因视角变化而明显变薄或侧翻的普通3D网格表现。
建议形式：
- BillboardGui + ImageLabel
或等价实现，只要满足以下结果：
- 图标始终正面朝向当前玩家摄像机
- 从任何视角看都能清楚识别该图标
- 不出现明显“侧过来变成一条线”的情况
3. 触发条件
3.1 触发对象
效果由按压板/踩踏板触发。
3.2 触发时机
当玩家成功触碰按压板并判定为一次有效触发后，立即播放一次该效果。
3.3 绑定玩家
该效果必须明确绑定到触发该按压板的玩家。
 后续所有图标的回收终点必须指向该玩家，而不是最近玩家，也不是所有玩家。

---
4. 整体效果流程
整组特效分为四个阶段：
阶段 A：生成
- 在按压板上方某个固定空间点生成一批奖励图标
- 所有图标在极短时间内同时出现
- 视觉上看起来像“从触发点一下子喷出来”
阶段 B：爆裂散开
- 生成后的图标先进行一次向外扩散
- 扩散距离不大，但要明显形成“爆裂”感
- 每个图标的散开方向和距离略有不同
- 散开不要求真实物理，只要求视觉清晰、节奏利落
阶段 C：吸附回收
- 爆裂阶段结束后，所有图标迅速开始朝玩家身体飞行
- 飞行时需要具有明确的“被吸过去”的感觉
- 可以允许不同图标稍有先后，但整体上必须是同一波奖励被回收
阶段 D：到达销毁
- 图标到达角色吸附点附近后逐个消失
- 消失必须干净利落，不要停留、不要弹开
- 角色获得奖励的反馈应与图标到达节奏同步或近似同步

---
5. 空间定位要求
5.1 起始点位置
图标起始生成点必须位于：
按压板中心点上方
建议偏移高度：
- 距按压板表面上方 2.5 ~ 4.5 studs
目标观感：
- 图标不是从地面里钻出来
- 也不是从屏幕中央平空生成
- 而是看起来像“触发点上方喷出奖励”
5.2 吸附终点位置
所有图标最终吸附到触发玩家角色身上的一个固定位置。
建议终点挂点优先级：
1448. HumanoidRootPart 上方偏移
1449. UpperTorso
1450. Head 下方/胸口附近的自定义 Attachment
推荐最终终点位置：
- 相对 HumanoidRootPart 偏移 (0, 1.5 ~ 2.5, 0)
目标观感：
- 看起来像“飞到玩家身上”
- 不要飞到脚底
- 不要飞到角色太高的位置
- 不要在角色面前停住
- 不要飞回按压板

---
6. 图标数量需求
6.1 单次生成数量
每次触发时生成一组图标，数量要求：
- 默认数量：8 个
- 可配置范围：6 ~ 12 个
6.2 数量观感要求
数量必须满足以下效果：
- 足够形成“炸开”的感觉
- 又不能多到像粒子烟花
- 重点是“奖励收集反馈”，不是大范围粒子爆炸
推荐默认值：
- 8 个或 10 个

---
7. 图标初始尺寸与缩放
7.1 初始显示尺寸
每个图标在出现时应具备统一基础尺寸，但允许轻微随机差异。
建议基础尺寸：
- BillboardGui 显示尺寸约等价于 1.2 ~ 1.8 studs 的视觉宽度
如果用 UI 尺寸表达，则要求观感满足：
- 不会太小看不清
- 不会大到遮挡角色主体
7.2 随机尺寸扰动
每个图标允许有轻微随机缩放差异：
- 随机比例范围：0.9 ~ 1.1
7.3 动画缩放反馈
图标生成时需要带有极轻微的弹出感：
- 出现瞬间可从 0.8 倍 放大到 1.0 倍
- 时间极短，避免夸张卡通感

---
8. 图标朝向要求
这是关键要求之一。
8.1 始终朝向本地玩家摄像机
图标必须在整个生命周期中：
- 始终正面面向摄像机
- 不因轨迹运动发生明显翻面、横侧、背面朝向
8.2 不做真实翻滚
图标本体不要做真实 3D 翻滚旋转。
 允许做的是：
- 轻微平面旋转
- 少量角度摆动
- 缩放脉冲
不允许做的是：
- 像硬币那样绕 X / Y 轴持续翻滚
- 导致图案难以看清

---
9. 爆裂阶段需求
9.1 爆裂目标
爆裂阶段要让玩家第一眼感受到“奖励被释放出来”，而不是直接吸附。
9.2 爆裂持续时间
爆裂阶段总时长：
- 0.12 ~ 0.20 秒
推荐默认值：
- 0.16 秒
9.3 爆裂轨迹要求
每个图标从起始点移动到自己的散开点。
 散开点由随机偏移决定，但偏移要满足以下约束：
水平散开半径
- 2.0 ~ 5.0 studs
垂直偏移范围
- -0.5 ~ +1.5 studs
观感要求：
- 主要是向四周散开
- 可以略微向上或略微向下
- 不要有明显图标飞进地下
- 不要有太大高度分层
9.4 爆裂分布形状
爆裂必须是“较均匀的环状/扇状随机散开”，而不是所有图标只往一个方向弹。
目标观感：
- 一眼看上去是围绕起点炸开
- 即使镜头角度变化，也仍然觉得炸开是饱满的
9.5 爆裂缓动
爆裂阶段需要具备轻快弹出的节奏。
 推荐缓动：
- QuadOut
- BackOut（幅度轻微）
要求：
- 起步快
- 末端略带停顿
- 不要拖泥带水

---
10. 吸附回收阶段需求
10.1 吸附开始时机
当某个图标完成爆裂阶段后，立即进入回收阶段。
 不需要额外停顿。
10.2 回收总时长
每个图标从散开点飞到角色吸附点的时间：
- 0.22 ~ 0.45 秒
推荐默认值：
- 0.30 ~ 0.36 秒
10.3 回收速度变化
回收飞行必须体现“被吸走”的感觉。
 建议速度感：
- 前半段正常推进
- 后半段明显加速接近终点
推荐缓动：
- QuadIn
- CubicIn
禁止：
- 匀速直线像漂浮物移动
- 末端减速悬停
10.4 飞行路径要求
回收轨迹不能显得过于机械。
 允许以下方式实现：
- 两段式 Tween
- 二次贝塞尔曲线
- 手动插值轨迹
目标表现必须是：
- 从散开点自然转向角色
- 路径带一点弧线感
- 不要每个图标都像完全同模同轨的复制品
11. 随机性需求
为了让效果像视频里那样自然，必须存在轻微随机差异，但整体仍然规整可控。
11.1 每个图标允许随机的参数
每个图标需要随机以下内容：
- 爆裂方向
- 爆裂距离
- 轻微高度差
- 图标基础尺寸微差
- 回收时长微差
- 起始延迟微差（非常小）
11.2 起始延迟
允许每个图标在生成后有轻微错峰：
- 0 ~ 0.04 秒
这样可以让一整组图标不至于过于死板同步。
11.3 禁止过度随机
不允许出现以下情况：
- 个别图标飞得特别远
- 个别图标速度极慢或极快
- 个别图标回收方向反常
- 个别图标明显落在地上或穿地

---
12. 消失规则
12.1 消失判定
当图标与角色吸附终点距离足够近时，立即销毁。
建议距离阈值：
- 0.5 ~ 1.2 studs
12.2 消失方式
图标到达终点时可以：
- 直接隐藏并销毁
- 或在 0.03 ~ 0.08 秒 内快速淡出并缩小销毁
要求：
- 足够利落
- 不拖尾
- 不在角色身上停住可见
12.3 销毁后状态
销毁后该图标不再参与任何更新，不得残留 BillboardGui、连接、Tween、Attachment 或临时实例。

---
13. 奖励反馈同步需求
13.1 视觉反馈与奖励结算关系
玩家获得奖励的视觉时机应与金币吸附过程相关联，而不是在踩板瞬间就完全结算完毕。
推荐方式：
- 可以在第一枚或前几枚图标开始接近玩家时开始更新数值
- 或在最后一枚图标到达时完成最终数值结算显示
13.2 听觉反馈
建议每个图标回收到玩家时触发轻微拾取音效，或一组快速连续的奖励音。
要求：
- 节奏清脆
- 与图标到达时机匹配
- 不要过大音量
- 不要拖成长音

---
14. 视觉附加要求
这些不是绝对核心，但为了接近视频效果，建议加入。
14.1 图标透明度
图标主体保持清晰可见，不建议半透明开场。
 推荐：
- 出现时透明度从 0.15 -> 0
- 回收末端可从 0 -> 0.2/0.3
- 不要做明显的幽灵式半透明飞行
14.2 发光/描边
允许给图标添加轻微视觉增强，但必须克制：
- 轻微外发光感
- 或浅色边缘描边
- 不要夸张 Bloom 风格
14.3 尾迹
默认不需要长拖尾。
 如果加尾迹，只允许非常短、非常淡，不能抢过主体图标。

---
15. 多次触发时的表现要求
15.1 连续触发
如果玩家快速重复触发按压板，新的金币飞散效果必须可以再次生成。
15.2 多组并存
允许多组特效在短时间内同时存在，但要求：
- 每组都正确绑定自己的触发玩家
- 不串目标
- 不共享错误终点
- 不因上一组未结束而阻止下一组出现
15.3 性能控制
当短时间内并发组数过多时，需要保证：
- 总实例数量可控
- 不因残留对象导致卡顿
- 有明确生命周期清理

---
16. 客户端表现要求
16.1 特效应以本地视觉流畅为主
该效果属于强视觉反馈特效，要求主要在客户端表现流畅。
16.2 本地玩家视角优先
由于图标需要始终朝向摄像机，因此其可见性和朝向应优先服务于本地玩家的观看体验。
16.3 网络同步目标
需要保证以下逻辑准确：
- 哪个玩家触发了按压板
- 哪个玩家应成为回收目标
- 奖励归属不出错
视觉细节允许在客户端执行。

---
17. 镜头适配要求
17.1 不同高度/俯视角都要成立
在以下镜头条件下，效果都必须保持合理观感：
- 正常第三人称视角
- 略高角度俯视
- 略低角度仰视
- 镜头拉近时
- 镜头拉远时
17.2 观感目标
无论镜头角度怎么变，玩家都应看到：
- 起点确实来自按压板附近
- 散开方向饱满
- 最终确实吸到角色身上
不能出现：
- 看起来像从屏幕固定点生成
- 侧视时图标不可见
- 飞行时图标大面积重叠成一团

---
18. 层次与遮挡要求
18.1 可见性要求
图标在绝大多数正常视角下应尽量可见。
18.2 遮挡策略
允许图标处于3D世界中，但为了保证反馈明确，需尽量避免：
- 一生成就被按压板模型挡住
- 飞向角色时长时间被角色身体完全挡住
建议：
- 生成点稍微抬高
- 回收终点偏向角色胸口上方
- 图标尺寸足够清晰

---
19. 参数推荐默认值
下面是一套可直接作为默认实现的参数要求。
19.1 默认参数
- 图标数量：8
- 生成高度：按压板中心上方 3.2 studs
- 爆裂时间：0.16 秒
- 爆裂水平半径：2.5 ~ 4.2 studs
- 爆裂垂直偏移：-0.2 ~ +1.0 studs
- 回收时间：0.32 秒
- 图标尺寸随机：0.9 ~ 1.1
- 起始错峰：0 ~ 0.03 秒
- 回收终点：HumanoidRootPart + Vector3.new(0, 2, 0)
- 到达销毁阈值：0.8 studs
19.2 推荐总时长
整组效果单个图标从出现到销毁的总时长应大致在：
- 0.45 ~ 0.65 秒
整组看上去要短促、有力、爽快。
20. 禁止事项
为了保证和目标效果一致，以下表现不允许出现：
5623. 图标从纯屏幕 UI 中央固定喷出
5624. 图标使用真实刚体乱飞
5625. 图标做大幅 3D 翻滚导致正面不可见
5626. 图标直接一条直线飞到玩家，没有先爆开
5627. 爆裂阶段过长，像慢动作烟花
5628. 回收阶段过慢，像漂浮物
5629. 到达玩家后停在身上不消失
5630. 奖励图标终点不是触发玩家而是其他玩家
5631. 多次触发时出现串组、串目标、实例残留
5632. 某些视角下效果看起来完全错位

需求V1.9 增加头顶高品质和高稀有度的动态渐变效果

我们依次来进行开发吧，主要是每个渐变效果我都想单独开发做出不一样的感觉

效果1：品质中的Mythic，路径是StarterGui - Gradients - Animation - Quality - Mythic
描述：这个Mythic是一个UIgradient，里面有几个渐变节点，效果就是始终缓慢地左右不断循环移动，做成一个动态渐变效果

继续补充效果：品质中的Secret也是一样的表现逻辑，请实现

需求V2.0 ui界面效果开发
1.每个主界面地按钮，需要动态效果，具体逻辑是：
    1.1以这个按钮举例：StarterGui - Main - Left - Index，这个是Index按钮入口，其中Left - Index - TextButton是一个button，Left - Index - TextLabel是文本，Left - Index - Icon是图标
    1.2当鼠标移动到Index上，或者在移动端就是按住Index，那么需要把Icon放大1.1倍，然后旋转20度，同时把TextLabel也放大1.1倍，然后鼠标移开时恢复正常，或者松手时恢复正常
    1.3当按下时，逻辑上是先触发摸到，然后再按下，在按下时，需要有点击效果，也就是按下时把TextLabel和Icon同时缩小到0.9倍，所以是先放大，然后按下后缩小，松手后恢复正常这样地逻辑
2.以下按钮是一样地逻辑，都要实现：
    2.1.StarterGui - Main - Left - Rebirth，以及StarterGui - Main - Left - Shop，这俩也是一样的，子结构都和刚才说的Index一样

3.StarterGui - Main - Top - Home，这个按钮也是，鼠标移动到时放大1.1倍，按下去时缩小到0.9倍，松手后恢复正常
    3.1同样的StarterGui - Main - Top - Sell以及StarterGui - Main - Top - Shop也是一样的需求


需求文档V2.0.1 补充一些小细节
1.我们的脑红信息模板ReplicatedStorage - UI - BaseInfo - Title - Quality这个文本，我们在Quality下默认有加的一个UIStroke，我们需要做的是，当一个脑红的品质是Secret的时候，需要把UIStroke的颜色改成纯白，但是其他的都保持默认不变
2.我们需要补充一些新的渐变效果，具体是Gradients - Animation - Quality - God以及Gradients - Animation - Quality - OG，同时还有Gradients - Animation - Rarity - Lava以及Gradients - Animation - Rarity - Hacker以及Gradients - Animation - Rarity - Lava以及Gradients - Animation - Rarity - Rainbow，注意这些渐变效果也都要每个都单独控制参数
3.在我们的加金币的动画效果表现时，Cash - CoinAdd出现后会透明度逐渐变成1隐藏，然后在隐藏过程中，明明字体是纯绿，然后描边是黑色，在透明度变化过程中不知道为什么看着字体中间一部分变成了白色，分析下原因

V2.0.2 做一个小修改：
关于ReplicatedStorage - UI - BaseInfo - Title - Quality里面的Secret这个品质，我们需要改下逻辑，当生成时，需要赋予两个渐变Gradients - Animation - Quality - Secret1和Gradients - Animation - Quality - Secret2，两个渐变同时生效，移除对之前Gradients - Animation - Quality - Secret的引用，两个渐变同时生效并且同参数情况下同时播渐变动画效果

V2.0.3 再次修改Secret渐变
改成：不要同时给两个渐变，而是把Secret1赋予描边，把Secret2赋予文本，然后其他不变，同时播渐变动效



V2.1 图鉴系统（Index系统）
概述：玩家可以在此处预览所有已经解锁的脑红，并随着脑红收集完成获得一定的收益

详细规则：
功能入口相关的规则：
1.玩家点击StarterGui - Main - Left - Index - TextButton这个按钮，打开Index界面（把StarterGui - Main - Index的Visible改成True）
2.玩家点击StarterGui - Main - Index - Title - CloseButton按钮，关闭Index界面（把StarterGui - Main - Index的Visible改成False）
这里我们需要做一个补充，关于我们做弹框打开和弹框关闭时，我们需要做一个对应的表现，在这个功能中我们先实现出来，然后后续开发的新的弹框，打开时都要有同样的表现，这个你得记住，具体打开弹框时的表现是：
1.打开弹框时，需要一个打开动效，弹框丝滑放大显示出来，而不是凭空显示，应该是有个打开的过程，最好有个缓动曲线，比如先放大然后缩小到正常大小，像果冻一样Q弹
2.弹框打开时，需要把Lighting - Blur的显示出来（enable改成True），同时打开时，把StarterGui - Main - Left以及StarterGui - Main - Top以及StarterGui - Main - Cash以及StarterGui - Main - TopRightGui这些Frame的Visible都改成False，也就是都隐藏起来
3.弹框关闭时，同样是先放大再缩小到消失，也是一个Q弹的缓动效果，关闭后把之前隐藏的那些Frame显示出来，然后把Blur也给关掉
4.注意我再补充一下：这个功能我们先做出来，后续每个新功能开发好涉及到弹框显示消失的，都需要这样有这个通用的显示隐藏和Blur效果

接下来是关于图鉴功能的系统规则：
1.在之前的规则中，我们就对我们的脑红进行过分类：品质以及稀有度，每个脑红都有其品质与稀有度划分
2.在Index图鉴中，我们的规则是：有多个页签，页签以稀有度为划分依据，同一个稀有度的脑红全部显示在一个页签下的列表中，然后按照品质从低到高依次显示即可，比如Normal稀有度页签下，显示的都是Normal稀有度的脑红，然后Gold稀有度页签下都是Gold稀有度的脑红
3.同稀有度下，按表中脑红的顺序显示即可
4.每个脑红都有一个对应的解锁状态：玩家是否获得过这个脑红，如果获得过（不论从什么渠道获得的，比如后面要做的别人送的礼物还是直接购买还是系统奖励等都算，只要获得过就行），就视为解锁了这个脑红，如果从未获得过就是未解锁状态

接下来是关于脑红图鉴显示的客户端规则：
1.StarterGui - Main - Index - TabList是页签列表，用于展示我们有哪些稀有度页签，具体逻辑是：
    1.1.TabList - ScrollingFrame是用来承载页签列表按钮的
    1.2TabList - ScrollingFrame - Template是页签按钮模板，默认隐藏，当打开页面时，需要去根据游戏当前开放的稀有度表，来生成对应的稀有度页签，去复制Template并改成Visible即可
    1.3Template - Name是一个Textlabel，用于显示稀有度名字
    1.4Template - Bg是一个Imagelabel，当按钮生成时，需要去按之前的类似头顶Info一样的逻辑，去StarterGui - Gradients - Animation - Rarity下复制同名稀有度的渐变，挂到Bg下，同时把Bg下之前就存在的叫Common的渐变删除
    1.5按钮生成后，点击对应的稀有度按钮，来打开对应的稀有度的脑红图鉴界面
    1.6注意这里的页签按钮点击时，也要有按下的效果，和Main - Top里那几个按钮一样的效果
    1.7再补充一个需求：鼠标移动到StarterGui - Main - Index - Title - CloseButton，也要把CloseButton放大，然后给CloseButton做旋转，类似之前Main - Left下的Index按钮一样的效果
2.关于脑红信息的显示：
    2.1Main - Index - Indexinfo - ScrollingFrame - Template是脑红信息显示的模板，默认的Visible属性是false，生成脑红信息时，去复制一份出来改成显示，并修改对应的信息然后生成对应的脑红信息
    2.2Template - Icon是imagelabel，用于显示脑红的图标，注意：这里如果脑红已经解锁了，就正常显示，如果脑红没有解锁，这个图标要显示成黑色剪影，只能看到轮廓那种
    2.3Template - Name用于显示脑红的名字，这是个Texlabel
    2.4Template - Quality是Textlabel，用于显示这个品质的品质名字，注意这里生成品质名字时，需要去按我们之前显示在脑红头顶显示品质名字一样的逻辑，去对应路径下复制对应的渐变挂给Quality，并且还要有渐变动效
    2.5Template - Bg是脑红的背景板，生成脑红信息时，也是去复制对应的品质的渐变挂给Bg，同时需要把Bg下原本自带的叫Common的渐变给删掉，注意，这里暂时我们先不做动效，只复制渐变过来即可

关于脑红的解锁收集进度：
1.我们需要给当前我们有多少个脑红做一个总数汇总，比如Normal一共10个，Gold10个，Diamond10个，那么我们总共的脑红数量就是30，然后Normal里解锁了3个，Gold里解锁了两个，那么总共的当前的解锁总数就是3
2.Main - Index - Title - Discovered是一个TExtlabel，用于显示玩家当前的解锁进度，内容固定是：xx/yy Discovered     ，其中xx就是当前解锁的数量，yy是总数，比如按上面的说法就是3/30 Discovered
3.Main - Index - Title - Progress是一个Textlabel，用于显示玩家的当前的解锁进度，和上面第二条类似，不过这里显示百分比，最多显示为整数并且始终向上取整，比如0.5%就是1%，3.9%就是4%，这里内容固定是：xx%Complete

我们的数据表在："D:\RobloxGame\BrainrotsTemplate\BrainrotsTemplate\数据表基础.xlsx"这个表中，其中“脑红基础”这个页签下就放着目前的所有的脑红的配置，你可以自主读取表

需求文档V2.1.1  修改部分细节
我们需要对家里的金币的显示逻辑做个修改：
1.以前我们的逻辑是，以Home01下的CLaim1举例，以前是在Claim1上生成一个Billboard用于显示金币数值以及离线金币数值，现在我们不再用这套来显示，改成其他方式
2.我们的新的逻辑是：Claim1 - Touch - Money是一个Frame，在这个编号对应的Platform上没有放置脑红之前，这个Frame不显示（Money的Visible=false），如果有脑红放置，才显示出来
3.Money - CurrentGold是当前已经积累的待领取的金币数值，格式固定是$xxx，Money - CurrentGold是离线产出的金币，如果未领取Money - CurrentGold的visible就是true，领取后就是false，格式固定是：IdleEarnings $xxxx

需求文档V2.2 重生系统
概述：玩家可以通过重生，来提升自己的基础的金币产出速度，重生时有要求，符合要求才能重生

详细规则：
重生要求：
1.目前我们设定的重生要求是玩家当前拥有的金币数值，比如要求有1000金币，那么玩家重生时必须要拥有大于1000金币才可重生
2.这个重生要求目前就先只设定金币数值，后续可能会拓展或者更改其他要求

重生结果1：
1.玩家会获得金币产速提升，比如第一次重生，玩家获得0.5倍产速提升，比如原来每秒产出1，现在就变成1.5
2.不同重生等级的产速加成是替换制，比如1级提升0.5，2级提升至1，3级提升至1.5，那么玩家基础产速是1的情况下，完成3次重生后，实际的产速是1*（1+1.5）=1*2.5=2.5
3.我们在之前的产速公式中曾经定义过，具体需求是这样的：

“1.我们在这里定义好我们每个脑红的产速计算公式：最终产速=基础产速*（1+加成1+加成2+加成x...），比如一个好友加10%，然后我们的后面系统中出了某个特权+50%，另一个药水+20%，那么总产速就是基础产速*（1+0.1+0.5+0.2）=基础产速*1.8
2.最终的产速就是所有的摆出来的脑红的产速加和就是总产速”

4.我们的重生带来的产速加成比例也是一样的规则，一起加到括号内，算一个新的加成维度，比如药水+0.2，重生+1.5，VIP+0.8，那么最终产速就是1*（1+0.2+1.5+0.8）

重生结果2：清零玩家当前的金币
1.重生完成后，将玩家当前的金币数据全部清零，包括自己当前已经有的金币和家园中放置的脑红已经产出的未领取的金币全部清零
2.重生后脑红再产出金币就要按新的产速加成比例来实现了

重生相关客户端规则：
1.玩家点击StarterGui - Main - Left - Rebirth - TextButton按钮，来打开重生界面（把StarterGui - Main - Rebirth的visible属性改成True）
2.玩家点击StarterGui - Main - Rebirth - Title - CloseButton按钮，关闭重生界面（把StarterGui - Main - Rebirth的visible属性改成false）
3.注意打开关闭弹框的时候，要有我们之前已经做好的关闭ui/打开关闭动效/打开Blur的逻辑，这些都是通用表现
4.鼠标移动到StarterGui - Main - Rebirth - Title - CloseButton时，要给CloseButton做放大旋转，点下去时要有按下的效果反馈。这些之前在做Index界面时都做过，都一样的效果
5.StarterGui - Main - Left - Rebirth - Time是一个Textlabel，用于显示玩家当前的重生次数，格式固定是[x]，x就是重生次数数值，随着玩家的重生次数更新这个要实时变化
6.玩家重生时，需要弹出系统提示，也就是把StarterGui - Main - RebirthTips显示出来，注意显示出来的时候要有弹出动画，具体的效果要和玩家点赞家园时的系统提示效果一致
7.玩家点击StarterGui - Main - Rebirth - Rebirthinfo - RebirthBtn按钮，可以触发重生，如果玩家重生条件不满足，则需要播放音效rbxassetid://118029437877580，路径是SoundService - Audio - Wrong
8.如果条件满足，则弹出提示，然后更新重生界面信息，更新成重生之后再次重生所要求的内容
9.StarterGui - Main - Rebirth - Rebirthinfo - ProgressBg是当前重生要求的进度条，具体逻辑是：
    9.1Rebirthinfo - ProgressBg - Progress是进度条，Progress的Size的Scale值代表进度，比如值是0就代表进度是0，值是0.5代表当前进度是50%，1就代表进度百分百，进度最多到100%
    9.2Rebirthinfo - ProgressBg - Num是具体的金币数值，格式是x/y，x是当前拥有的金币，y是需要的金币，数字格式固定都是$xxxx，这里不用大数值，就用原本的数值显示，但是也要有每3位一个逗号的显示逻辑
10.如果达到了最高的重生次数，那么重生成功后，就始终显示最高次数的重生要求就行了，然后隐藏重生按钮即可

我们的具体的重生的表的初始测试配置是："D:\RobloxGame\BrainrotsTemplate\BrainrotsTemplate\数据表基础.xlsx"，这个表里重生基础配置这个页签，请用这个表里的内容转换为我们的数据配置


需求文档V2.3 全局排行榜

概述：我们需要做一套全局排行榜，注意是全局的，所有服务器通用的总排行，不是单服务器内的排行榜

排行维度：
1.总游戏时长
2.当前金币总产速

总游戏时长：
1.是一个永久的玩家的数据，玩家每次进来后都会叠加一些时长，是永久叠加的，任何情况下这个数据都不会被清除，代表在玩家在这个游戏内的总游戏时长

总金币产速：
1.玩家当前的总的金币产出速度，是计算加成后的总的金币产速，比如3个脑红，各自的速度加成后就是总的金币产出速度

注意：以上排行榜，需要每2分钟更新一轮（开发系统时可以评估这个时长是否太短或者太长可以与我沟通调整这个时间频率）

客户端规则：
1.在我们的游戏场景内，Workspace - Leaderboard01是一个模型，用来承载总产出速度的排行榜，Workspace - Leaderboard02也是一个模型，用来承载玩家的总游戏时长排行榜
2.我们以Leaderboard01举例：
    2.1Leaderboard01 - Main - SurfaceGui - Frame - Player - Avatar用于显示玩家自己的头像
    2.2Leaderboard01 - Main - SurfaceGui - Frame - Player - Name用于显示玩家自己的名字
    2.3Leaderboard01 - Main - SurfaceGui - Frame - Player - Num用于显示玩家的这个排行榜的数值，也就是总产出速度，格式固定时：$xx/S,注意这里要用我们游戏通用的大数值格式
    2.4Leaderboard01 - Main - SurfaceGui - Frame - Player - Rank用于显示玩家的排名信息，如果玩家的排名在50名之外，那么固定这里显示为50+，如果在50名以内，则显示具体名次
    2.5Leaderboard01 - Main - SurfaceGui - Frame - ScrollingFrame - Rank01 - Avatar用于显示排行榜第一名的头像
    2.6Leaderboard01 - Main - SurfaceGui - Frame - ScrollingFrame - Rank01 - Name用于显示排行榜第一名的名字
    2.7Leaderboard01 - Main - SurfaceGui - Frame - ScrollingFrame - Rank01 - Num，用于显示产出速度
    2.8Leaderboard01 - Main - SurfaceGui - Frame - ScrollingFrame - Rank02和Leaderboard01 - Main - SurfaceGui - Frame - ScrollingFrame - Rank03下面的结构和01时一样的，分别用于显示第二名和第三名的信息
    2.9在第四名之后的玩家的信息，显示时，都去复制Leaderboard01 - Main - SurfaceGui - Frame - ScrollingFrame - RankTemplate，这个结构和Rank01下面结构也是一样的，但是RankTemplate的默认visible是false，复制出来时需要改成true，然后生成对应的等级信息，同时RankTemplate - Rank用于显示具体的排名名次

3.注意：排行榜最多只显示前50名的信息，超出50名之外的玩家就不显示了

补充一点，关于总游戏时长的信息显示，固定为：xx:yy:zz,xx是天，yy是小时，zz是分钟，比如以下：
一共玩了305分钟，则显示00:05:05,如果完了15天14小时，则显示为：15:14：00

需求文档V2.4：特殊事件
概述：我们在游戏中会设定一些基础的游戏事件，不定时发生的，目前这个版本我们先只做一个事件

详细规则：
1.我们在游戏中设定每30分钟，会从我们的事件库中生成一个特殊事件，所有服务器公用一个倒计时
2.这个倒计时就是每个UTC的整点和30分，就触发一次事件，跟服务器什么时候开起来的无关

我们做了一个事件表（临时配置，先用来实现功能）：
特殊事件Id	事件名	发生权重	持续时间（秒）	ReplicatedStorage中的名字
1001	骇客事件	100	300	EventHacker
1002	熔岩事件	100	300	EventLava


1.每个事件都有一个特殊id
2.每次事件发生时，都需要从事件表中根据权重，随机一个事件出现
3.要求本次发生的事件和上次发生的事件不能重复

事件的表现：
1.骇客事件：
    1.1去ReplicatedStorage - Event下复制EventHacker，挂载给玩家，并始终绑定在玩家身上，链接好即可，注意复制的时候要把EventHacker下的所有子节点全部复制过来
2.熔岩事件：
    1.1去ReplicatedStorage - Event下复制EventLava，挂载给玩家，也是链接好，然后复制所有的子节点

注意：事件期间只要玩家在服务器内，就要有这个表现，事件结束后把复制出来的事件再从玩家身上移除

同时Gm中需要增加命令：/event 1001  按这个格式填事件id，即可触发一次事件，当新的事件触发时，要把已经存在的老同id事件移除掉，如果id不同则不需要移除

需求文档V2.4.1 对事件功能的补充：
1.注意我们事件的这些逻辑都是玩家自己客户端的，比如加EventHacker这种，都是玩家客户端自己的，不要做成整个服务器逻辑
2.我们再补充一个功能：在事件触发的时候，需要同步对天空盒进行处理，具体逻辑是：
    2.1骇客事件：去Lighting - Hacker下复制所有子节点，变成Lighting的直接子节点，当事件结束后移除
    2.2熔岩事件：去Lighting - Lava下复制所有子节点，变成Lighting的直接子节点，当事件结束后移除
    2.3后续我们也会拓展其他事件，然后需要在这里使用类似的逻辑 
    2.4注意天空盒也是玩家自己客户端的逻辑，不要做成服务端逻辑

我们对配置表加了个新的字段：天空盒路径：
特殊事件Id	事件名	发生权重	持续时间（秒）	ReplicatedStorage中的名字	天空盒路径
1001	骇客事件	100	300	EventHacker	Lighting/Hacker
1002	熔岩事件	100	300	EventLava	Lighting/Lava

补充个需求：关于Index界面，我们之前的逻辑是：给Index界面的Indexinfo - ScrollingFrame - Template - Bg也挂载了渐变色，现在我要求把这个逻辑给去掉，不给Bg挂渐变了

需求文档V2.5 关于脑红升级的功能开发

概述：我们目前的脑红是没有等级这个概念的，我们目前要做的是：我们要给脑红加一个等级概念并且可以升级

详细规则：
1.所有的脑红在玩家刚获得的时候，默认都是1级
2.脑红可以消耗金币来提升等级，等级提升后可以提升这个脑红的产速
3.脑红升级时所需要消耗的金币数值是：所需金币=基础产速*1.5^(当前等级 - 1)，比如3级脑红升级，基础产速是10，那么所需消耗金币=10*1.5^(3-1)=22.5,消耗22.5金币可以升级至4级
4.脑红升级后带来的产速加成变化是：升级后金币产速=基础产速*1.25^(当前等级-1)
5.如果扣除金币后玩家当前拥有的金币数值变成了小数，则在main -Cash -  CoinNum处也显示为整数，向上取整
6.如果消耗或者产出速度算完后出现了多位小数，则最多显示1位小数，四舍五入，比如1.325显示为1.3
7.脑红如果在平台上被拿走了，储存在背包里时依然要保留等级信息

客户端规则：
1.我们以Home01 - HomeBase - Brand1举例，对应位置1的脑红：
    1.1Brand1 - SurfaceGui - Frame - Money - CurrentGold是一个textlabel，用于显示当前升级所需要消耗的金币数值
    1.2Brand1 - SurfaceGui - Frame - Money- Level是当前等级信息，格式固定是：Lv.x>Lv.y，分别代表当前等级>下一等级
    1.3Brand1 - SurfaceGui - Frame - Arrow是一个Imagelabel，是一个箭头，你要给这个箭头做不断地缓慢上下移动地循环动画效果
    1.4玩家点击Brand1 - SurfaceGui - Frame来触发升级

2.玩家点击升级时，如果金币充足则升级成功，扣除金币升级成功然后播放音效：rbxassetid://72535887807534，路径是SoundService - Audio - MoneyTouch，如果金币不足则无法升级并播放音效rbxassetid://118029437877580，路径是SoundService - Audio - Wrong


需求文档V2.6  脑红出售

概述：玩家背包中的脑红除了可以放置在Platform上赚金币，也能够直接出售

在做功能前我们先补充一个规则：移除放在Platform上的脑红，具体规则是：
1.如果脑红放在Platform上，玩家靠近脑红后，需要在脑红上出现交互按钮，玩家长按交互按钮可以将脑红从platform上移除，放到玩家的背包中。
2.脑红上出现的交互按钮文本是：Pick Up，长按交互时间和放在Platform上长按的时间是一致的
3.如果玩家在手中拿着一个脑红的情况下，长按Platform上的脑红交互，走替换逻辑，比如拿的A，长按与放置好的B交互，就把B换到手里，A放到位置上即可

出售脑红规则：
1.玩家可以出售背包中的拥有的脑红
2.脑红出售价格=脑红1级时的基础产速*15，也就是基础产速产出15秒的总的金币数值

出售相关客户端规则：
1.玩家点击StarterGui - Main - Top - Sell按钮，除了现在移动到目的地外，也顺路打开Sell界面，也就是把StarterGui - Main - SellBrainrots的Visible改成true
2.补充下，打开Sell界面的逻辑应该是：玩家与Shop02 - PrisonerTouch触碰，就打开Sell界面
3.玩家点击StarterGui - Main - SellBrainrots - Title - CloseButton按钮，关闭界面就是把StarterGui - Main - SellBrainrots的Visible改成false
4.注意：打开弹框时，打开关闭都要有动效，有通用的blur效果，隐藏ui这些逻辑都要有，然后鼠标移动到StarterGui - Main - SellBrainrots - Title - CloseButton，也要有给CloseButton的旋转放大效果

5.Main - SellBrainrots - Sellinfo - ScrollingFrame - Template是可出售脑红的信息模板，默认是隐藏的，生成对应信息时复制出来更改对应信息然后显示出来即可
6.生成脑红列表时，按照背包中的顺序显示即可
7.ScrollingFrame - Template - HeadTemplate - Icon是用于显示这个脑红的图标
8.ScrollingFrame - Template - HeadTemplate - Level是textlabel，用于显示这个脑红的等级信息，格式固定是Lv.x
9.ScrollingFrame - Template - Money是textlabel，用于显示脑红的出售价格，格式固定是$xxx，注意这里用我们的大数值显示逻辑
10.ScrollingFrame - Template - Name是textlabel，用于显示脑红的名字
11.ScrollingFrame - Template - Quality是textlabel，用于显示脑红的品质名字，注意这里要挂对应的渐变并且要有渐变效果，类似脑红头顶的品质效果还有Index界面处的品质显示渐变效果，都是一套
12.ScrollingFrame - Template - SellButton是出售按钮，点击后可出售这个脑红，注意出售后把金币加给玩家
13.玩家点击SellBrainrots - Sellinfo - SellButton按钮，可以一键全部出售所有的脑红
14.注意出售脑红后，要有和按下按钮领取金币时一样的音效，每次点击按钮出售后都播一次音效
15.点击ScrollingFrame - Template - SellButton和SellBrainrots - Sellinfo - SellButton这俩按钮都要有按下效果反馈
16.SellBrainrots - Sellinfo - InventoryValue是textlabel，用于显示当前出售所有的脑红所可以获得的所有金币，格式固定是：Inventory value: $xxxx，xxx是金币数值，这里要用大数值显示
17.如果玩家点击ScrollingFrame - Template - SellButton或者SellBrainrots - Sellinfo - SellButton，点击出售后，如果已经没有脑红可以出售了，就自动关闭界面

需求文档V2.7 家园拓展

概述：我们玩家的家园初始只有10组可以放置脑红的点位（一组包括Platform/Claim/brand三个位置，用于放脑红/领金币/升级脑红）

详细规则：
1.玩家可以花费金币，来拓展家里的放置脑红的点位数量，每次可以拓展1个
2.我们按顺序进行拓展，每个拓展点位都有对应的金币价格
3.由于我们的初始基地一层最多能放下10个点位，所以拓展新的点位要给基地新加一层，但是也只有拓展第二层的第一个点位和第三层的第一个点位的时候，需要把额外的层数加好，其他的都只控制点位出现即可
4.我们做一张这样的表：
ID	第几个位置	层数	解锁价格
1001	1	2	100
1002	2	2	200
1003	3	2	300
1004	4	2	400
1005	5	2	500
1006	6	2	600
1007	7	2	700
1008	8	2	800
1009	9	2	900
1010	10	2	1000
2001	1	3	1100
2002	2	3	1200
2003	3	3	1300
2004	4	3	1400
2005	5	3	1500
2006	6	3	1600
2007	7	3	1700
2008	8	3	1800
2009	9	3	1900
2010	10	3	2000


当需要生成层数时：去ReplicatedStorage下寻找HomeFloor，复制一份，放到玩家的基地上，这样就形成了一层新的楼层，其中HomeFloor下也有Position1/Claim1/Brand1这些，比如第二层就对应第二层的第一个第二个位置这样
由于我们是一个一个解锁的，所以比如上来第二层只解锁了第一组，那么其他9组的Part需要都给隐藏掉，不能用，等解锁了之后再显示出来
上面的表中当层数那一列出现新的层数时，就意味着需要加一层新的楼了

客户端规则：
1.我们以Home01举例，PlayerHome - Home01 - HomeBase下有个节点Part叫BaseUpgrade
2.BaseUpgrade - SurfaceGui - Frame - Money - Frame - CurrentGold是textlabel，用于代表解锁下一个格子所需要花费的金币数
3.BaseUpgrade - SurfaceGui - Frame - Money - Frame - Level是用于显示解锁进度，格式是x/y,x代表当前已经解锁了几个，y代表总共可以解锁几个，比如刚才表中我们解锁到1003时，代表已经解锁了三个，那这里就是3/20
4.当全部解锁完成后，CurrentGold显示为Max，然后Level显示为x/x,比如20/20
5.玩家点击BaseUpgrade - SurfaceGui - Frame - Money即可触发解锁，消耗金币解锁位置

V2.7.1 关于家园生成的修改

概述：我们之前的去ReplicatedStorage下寻找HomeFloor并复制生成的逻辑实在是太麻烦了，我改成了直接在Workspace下做好，用代码去控制显示与隐藏即可

以Home01举例：
Home01 - HomeBase是第一层，默认显示出来；Home01 - HomeFloor1是第二层，玩家未解锁之前，是默认全部隐藏，Home01 - HomeFloor3是第三层，玩家未解锁之前，也是默认全部隐藏
以HomeFloor1举例，HomeFloor1下的所有的组都应该默认隐藏，解锁后，再显示出来，比如解锁了第二层的第一组位置，就把第二层的第一组的Position1/claim1/brand1都显示出来，其他的还是保持隐藏
其他逻辑保持不变，主要就是从复制生成逻辑改成隐藏显示逻辑。

V2.8 自定义背包

概述：我们现在的背包是使用的系统背包，但是我们需要改成自定义的背包

1.StarterGui - Main - Backpack是个frame，默认Visible是false，当背包中有内容时改成true
2.Backpack - ItemListFrame - ArmyTemplate是背包内容模板，ArmyTemplate - Icon是图标，ArmyTemplate - Name是名字

V2.9 赠送礼物功能
概述：玩家可以在游戏中赠送其他玩家礼物，注意只能赠送脑红

核心逻辑是：
1.玩家如果手中拿着脑红的情况下（注意这个是大前提），靠近其他玩家，需要在其他玩家身上出现交互按钮，长按E键1秒完成赠送请求，交互文本是固定的Gift
2.玩家向其他玩家发起赠送后，需要强制在其他玩家的界面弹出弹框：
    2.1StarterGui - Main - Gift显示出来（visible改成true），注意显示出来时要有打开动效，关闭时也要有关闭动效，打开状态下隐藏ui并显示blur，这都是项目现在内置的统一的表现逻辑
    2.2玩家点击Gift - Window - Title - CloseButton是关闭按钮，点击关闭弹框，注意鼠标移动到按钮上的时候，按钮要放大旋转，然后按下的时候有按下效果
    2.3Gift - Window - ButtonsAcceptButton是接受按钮，点击后接受礼物，如果接受礼物，则立刻关闭弹框，并获得这个脑红，从对方背包中扣除
    2.4Gift - Window - DeclineButton是拒绝按钮，点击后拒绝接受礼物，关闭弹框即可
    2.5注意：如果对方拒绝了接受礼物，比如A赠送B，B拒绝了，那么5分钟内A再靠近B，在B身上不再出现按钮，注意是5分钟内
    2.6Gift - Window - Content - PortraitFrame - PortraitImage是用来显示赠送者的头像的，替换成赠送者的头像
    2.7Gift - Window - Content - PortraitFrame - Info - SenderText是textlabel，用于显示赠送者的玩家名字
    2.8Gift - Window - Content - PortraitFrame - Info - MessageText是赠送文本，内容固定是：xxxx wants to give you: [yyyy]! Do you accept?其中xxxx是赠送者的名字，yyy是赠送的脑红的名字

V3.0滑滑梯功能
概述：玩家可以在场景中进行滑滑梯

详细逻辑：
1.Workspace - SlideRainbow01 - Empty下是一群Part的集合，这些Part组成了滑滑梯，滑梯判定也只认Empty下的这些Part
2.玩家站在滑滑梯上，可以自动向下滑动，有滑滑梯的效果，我需要有个统一参数，用来控制站在滑滑梯上的滑行速度或者摩擦力这些，总之就是用来控制站在滑滑梯上的滑动效果
3.玩家在滑滑梯上滑动时，滑动动作固定为：111214448809248
4.玩家在滑滑梯末端，由于速度刹不住，会被抛物线抛出去，抛物线你先做个基础的逻辑，后面我们会做一些维度来控制抛出去的力度

V3.0.1  对滑梯功能的补充
当前我们已经完成了滑梯功能的初版以及控制抛出去的力度的功能，但是有以下问题需求修正：
1.现在我如果加大了我的冲击力这个数值，在我重新到滑梯起点往下滑的时候，会突然速度变快地往下滑，这明显不对，我需要的是不论我怎么调我的推动力，在滑梯上往下滑地速度都是一致的，只是最终抛出去的时候的力度不一样而已
2.总体来说：就是我希望我的冲击力数值大小只会影响最后冲出滑梯那一下的力度，而不是影响我滑动的速度
3.现在滑动到后半部分不知道为什么角色的角会插在滑梯的部分Part里面，找出问题并修复
4.当推动力为0时，玩家在滑梯末端应该完全按照当前滑动速度自然冲出去，不要再额外补一个默认前向弹射速度

V3.0.2 商店功能补充
1.Sell功能：玩家靠近Workspace - Madudung，在Madudung身上出现交互按钮，我在模型里有加的ProximityPrompt，交互即可打开Sell商店界面
2.Workspace - Madudung以及Workspace - Garamararam在游戏运行后，要始终默认循环播放待机动作，这俩人的动作在玩家客户端播放即可，不用在服务端播

V3.0.3 滑梯路径调整
1.滑梯有效路径调整为：Workspace - SlideRainbow01 - Empty，只有Empty下的Part才算滑梯表面
2.SlideRainbow01模型下其他不在Empty里的Part，不再参与滑梯检测与滑行逻辑

V3.1 弹射力系统

概述：我们需要把现在的飞出去的力做成一个游戏内的玩家属性，统一定义叫弹射力，英文名叫Launch Power

详细规则：
1.弹射力是玩家的一个永久属性，下次进来游戏后，还是需要继承之前的数值的，不要我一退游戏就清零
2.玩家可以花费金币来提升自己的弹射力，每提升一点需要消耗对应的金币数值
3.我们设定一个升级时的基础金币数值：200，也就是玩家基础的1级升2级的时候，需要消耗200点金币，然后加1点弹射力，玩家默认1级，1级时的弹射力数值为0
4.之后每次升级时，都固定加1点弹射力，升级费用改为分段递增，所有计算结果都向上取整
    4.1玩家1级升2级时，固定消耗200金币
    4.2后续当目标等级处于2级到20级时，每升1级，下一档升级费用=上一档升级费用*1.08
    4.3当目标等级处于21级到50级时，每升1级，下一档升级费用=上一档升级费用*1.11
    4.4当目标等级处于51级到80级时，每升1级，下一档升级费用=上一档升级费用*1.14
    4.5当目标等级处于81级及以上时，每升1级，下一档升级费用=上一档升级费用*1.18
    4.6举例：如果某一档升级费用算出来是108.32，则本档实际显示和实际扣除都按109处理
    4.7十连升级的总消耗，不允许直接拿当前单次费用乘10，而是必须把接下来10次单次升级费用逐档计算后相加

客户端规则：
1.玩家点击Main - Top - Shop按钮，立刻打开弹射力升级界面，或者与Workspace - Garamararam交互，打开弹射力升级界面（把StarterGui - Main - Upgrade的visible改成true）
2.玩家点击StarterGui - Main - Upgrade - Title - CloseButton，关闭弹射力升级界面。注意打开和关闭时都要走通用的效果，鼠标移动到CloseButton也要有放大旋转效果
3.StarterGui - Main - Upgrade - Title - CashNum用于显示玩家拥有的金币数，这里注意要用大数值逻辑来显示
4.玩家点击Main - Upgrade - Equipinfo - ScrollingFrame - Upgrade1 - BuyButton触发对弹射力的升级购买，购买成功则提升1级，其中：
    4.1Main - Upgrade - Equipinfo - ScrollingFrame - Upgrade1 - BuyButton - Text用于显示升级所需要消耗的金币数值，这里要用大数值显示
    4.2Main - Upgrade - Equipinfo - ScrollingFrame - Upgrade1 - Num1Bg - Num用于显示当前的弹射力数值，Main - Upgrade - Equipinfo - ScrollingFrame - Upgrade1 - Num2Bg - Num用于显示下一级的弹射力数值

需求文档V3.1.1  快速升级推动力
1.玩家点击Main - Upgrade - Equipinfo - ScrollingFrame - Upgrade2 - BuyButton触发对弹射力的升级购买，购买成功则提升10级，这个按钮是一次购买10级
    1.1Main - Upgrade - Equipinfo - ScrollingFrame - Upgrade2 - BuyButton - Text用于显示升级所需要消耗的金币数值，注意这里是未来10级所需要消耗的金币总额，比如1级时，这里就是未来10级的总消耗金币数值
    1.2Main - Upgrade - Equipinfo - ScrollingFrame - Upgrade2 - Num1Bg - Num用于显示当前的弹射力数值，Main - Upgrade - Equipinfo - ScrollingFrame - Upgrade2 - Num2Bg - Num用于显示加10级后的的弹射力数值

需求文档V3.1.2 补充一个偷取别人的脑红的功能

1.玩家靠近别人家基地的放置在地上的脑红，需要在脑红身上出现交互按钮，交互文本是Steal，完成交互需要长按交互键一秒完成交互
2.长按完成后触发对敌方这个脑红的偷取，也就是调出对对应开发者商品的购买
3.购买完成后，可以直接获得对方的这个脑红，这个脑红从对方基地和背包消失
4.这里有个注意点：在付款过程中如果被第三个玩家偷走了，则补发一个这个脑红给玩家；如果在付款过程中，这个脑红被主人收到了自己背包里或者手里，也依然完成偷取，如果购买的时候脑红被主人直接卖掉了，那也补发一个脑红给付款者，避免又付款又没有脑红获得
5.偷取完成后，需要给被偷者（主人）弹出系统提示，也就是把Main - StealTips显示出来，文本固定是[xxxx] steal your [yyy]!其中xxxx是偷盗者的名字，yyy是被偷取脑红的名字

需求文档V3.1.3 滑梯功能修改
概述：我们想要对现有的滑梯功能进行修改，主要是修改一些实现逻辑

详细需求：
1.修改为只有在Workspace - SlideRainbow01 - Collide1 - Slide上才能滑动，也就是站在这个上就开始加速往下滑动
2.滑动过程中玩家无法控制角色，比如不能控制移动，不能控制跳跃/减速/奔跑等
3.玩家滑动过程中到了底部，会触碰到Workspace - SlideRainbow01 - Collide1 - Up这个Part，当玩家触碰到Part的时候，会向45度斜上方跳起（看起来是被蹦床弹射起来的），弹射力度还是沿用现在的弹射力的逻辑

需求文档V3.2 喷气背包系统
概述：玩家可以花费金币购买喷气背包，然后选择装备的喷气背吧是什么

详细规则：
1.我们定义一个体力系统：这个数值决定了玩家在弹射起飞后，可以多少秒内不受到重力加速度的影响，比如现在我们弹射后，其实是起飞后在纵向的速度就受到重力加速度影响不断减速，减速成0后开始下落，然后下落的过程又不断加速
2.我们再定义一个减速系数，也就是玩家在下落过程种，只要按住对应按钮，即可进入“子弹时间”，此时玩家下落变慢，玩家可以调整下落的飞行方向，松开手后退出子弹时间，再继续以原来的速度继续前进
3.我对以上两个属性的总结就是：前一个属性决定了玩家能跳多高多远，后面一个参数决定了玩家能否控制角色准确地落到目的地
4.我再补充下对子弹时间属性地说明，按住对应按钮，玩家地下降速度立刻变成对应的背包地属性地速度，松手后恢复原来的速度和保持加速效果

我增加了一张喷气背包表：
ID	金币价格	罗布币价格	开发者商品id	是否默认解锁	喷气背包名字	喷气背包icon	喷气背包路径	不受重力影响时长（秒）	子弹时间减速为xx下落速度（米/秒）
1001	0	0	3562613109	1	Takekopter	rbxassetid://138477934814998	ReplicatedStorage/Jetpack/Takekopter	3	2
1002	1000	19	3562613276	0	StarBackpack	rbxassetid://107730139753375	ReplicatedStorage/Jetpack/StarBackpack	5	1.8
1003	20000	29	3562613455	0	FireRocket	rbxassetid://136689093387925	ReplicatedStorage/Jetpack/FireRocket	7	1.6
1004	300000	39	3562613596	0	Cola	rbxassetid://122686478401756	ReplicatedStorage/Jetpack/Cola	9	1.4
1005	6000000	49	3562613719	0	Keyboard	rbxassetid://118959317539160	ReplicatedStorage/Jetpack/Keyboard	11	1.2


喷气背包说明：
以ReplicatedStorage - Jetpack - Cola为例子说明：这是一个饰品，玩家装备后，根据饰品规则装备给玩家，比如Cola - Handle - BodyBackAttachment，这些节点按逻辑就会出现在玩家的身后

补充：玩家默认解锁1001这个喷气背包，也就是玩家重生时就默认装备的这个喷气背包

客户端规则：
1.玩家点击Main - Left - Jetpack - TextButton按钮，打开喷气背包界面（把StarterGui - Main - Jetpack的Visible改成True），注意打开时要有通用的打开动效，以及隐藏ui和显示出来Blur
2.玩家点击Main - Left - Jetpack - Title - CloseButton按钮关闭喷气背包界面，注意关闭的时候也要有关闭动效，另外鼠标移动到CloseButton也要有对应效果
3.Jetpack - Equipinfo - ScrollingFrame - EquipTemplate是喷气背包的信息的模板，默认是隐藏的，打开背包的时候去复制一份修改对应子节点信息并显示出来
    3.1EquipTemplate - ItemTemplate - ItemIcon是用于显示喷气背包的icon
    3.2EquipTemplate - Name是Textlabel，用于显示背包的名字
    3.3EquipTemplate - Title1用于显示属性1的具体数值，格式是XS，代表多少秒
    3.4EquipTemplate - Title2用于显示属性2的具体数值，具体数值就用数据表中的数值即可
    3.5EquipTemplate - GoldButton是用于金币购买的，EquipTemplate - GoldButton - Frame - RMoney用于显示金币数值，这里要用大数值显示逻辑
    3.6EquipTemplate - RobuxBuyButton是用于罗布币购买的，EquipTemplate - RobuxBuyButton - Frame - RMoney是用于显示罗布币价格
    3.7以上两个购买按钮，在玩家没有获得这个喷气背包的情况下，需要显示出来，如果玩家拥有了这个背包，就把这俩按钮隐藏
    3.8EquipTemplate - EquipButton是装备按钮，玩家点击这个按钮可以切换至装备这个按钮，默认按钮是隐藏的，如果玩家获得了这个背包但是没装备，则显示出来，点击按钮可以进行装备
    3.9EquipTemplate - Equiped是一个textlabel，如果玩家未装备的情况下，隐藏起来，如果玩家装备了这个背包就把这个显示出来
    3.10如果玩家购买了喷气背包，购买成功要弹出系统提示：把StarterGui - Main - PurchaseSuccessfulTips显示出来，注意显示出来的时候要有弹出动效，类似其他tips

    注意：这个版本只用来实现对应的背包的装备/解锁获得以及客户端逻辑这些，先不用开发两个属性，后续版本开发

需求文档V3.2.1 加速时间效果实现

概述：我们目前起跳后在垂直方向的速度是受重力影响的，如果不受到重力影响的情况下，在起飞后在垂直方向应该始终保持同一个速度

详细规则：
1.我们的背包属性1：体力，这个属性就是控制玩家在起飞后，可以多少秒内不受重力影响，当倒计时结束后，才开始手重力影响产生垂直方向的减速
2.玩家起飞后，逻辑上立刻开始StarterGui - Main - FlyProgress这段不受重力影响的倒计时；FlyProgress - Bar刚开始时Size是1（scale），当倒计时结束后长度变成0，在这个过程中缓慢变短。当前版本由于滑行中和起飞上升/无重力阶段会统一隐藏所有玩家UI，所以这段倒计时不会直接显示给玩家。
3.倒计时结束后把StarterGui - Main - FlyProgress隐藏
4.我们的不同背包对应的体力属性数值就是不受重力影响的时间

需求文档V3.2.2 减速效果实现
概述：我们之前定义的第二种属性：减速属性，也就是为了达成林克时间的效果的属性我们需要实现

详细规则：
1.我们的属性是：玩家在空中的时候，可以按住对应按钮，进入“子弹时间”，在子弹时间内，玩家的下降速度减缓，玩家可以操控角色在空中移动从而来调整落点
2.在玩家进入下落阶段后，需要把StarterGui - Main - FlyButton显示出来，也就是Visible属性改成true，然后落地后，再隐藏起来
3.玩家在下落过程中，可以按住FlyButton - Hold按钮，来减速，降低的速度就是数据中配置的速度；当前版本会把角色切到一个非常慢、接近悬停的空中状态，这个速度值同时也会显著压低当前空中的前进速度，用来强化“空中定点修正落点”的手感。
4.当前版本在松开 FlyButton - Hold 后，需要立刻恢复到“本次按下 Hold 之前记录的那一份空中速度快照”，方便玩家通过多次按下/松开做分段停顿式修正；这里不要求继续沿松手瞬间的真实重力加速度接续计算。
5.玩家点击FlyButton - Left按钮，可以把玩家向左移动，也可以长按，持续向左移动，玩家点击FlyButton - Right按钮，可以把玩家向右移动，也可以长按，持续向右移动
6.玩家在一次下落过程中，可以反复多次按下/松开 Hold，以及配合 Left / Right 做横向微调，整体目标是更接近“近似悬停 + 修正落点”的体验，而不是只做一个轻微减速。
7.玩家在Slide上滑行，以及从Up弹出后的起飞上升/无重力阶段，需要统一隐藏所有玩家UI；当进入可操作下落阶段后，再恢复这些UI，此时FlyButton继续按本节规则显示/隐藏。

需求文档V3.3 脑红生成规则

概述：我们在游戏中，要在指定范围内生成对应的脑红，玩家可以通过与脑红交互获得脑红

详细规则：
1.在Workspace - Land下有一堆part,这些Part是用来生成脑红的区域，每个Part上只会生成对应组的脑红
2.以Workspace - Land - Common1这个Part举例，这个Part上应该是用来生成对应组里的脑红的，比如我的数据表是："D:\RobloxGame\BrainrotHuahuati\BrainrotHuahuati\数据表基础.xlsx"，具体的逻辑是：
    2.1这张表下的脑红生成组配置这个页签，是放置着脑红组的配置，左边的生成组对应着右边的Part名字，每个Part生成脑红使用的组就用左边对应的id
    2.2这张表下脑红生成池这个页签下，放着每个组对应的脑红生成国际，比如以下这个配置：最左边的id是独立的，脑红生成组的id是与脑红生成组配置这个页签里的脑红生成组配置id对应的，脑红id是我们的脑红id配置，出现权重是用来计算出现概率的，一个组的所有权重相加就是分母，每个的权重除以分母就是这个脑红的刷新概率
    ID	脑红生成组	脑红Id	出现权重
    100001	1001	10001	40
    100002	1001	10002	30
    100003	1001	10003	20
    100004	1001	10004	15
    100005	1001	10005	10
    100006	1001	10006	8

3.游戏刚创建时，需要立刻全局执行一次脑红生成
4.脑红生成组配置中有个字段是同时存在脑红数量上限，每次第一次生成时生成对应数量的脑红
5.每个生成出来的脑红上，都要加一个ProximityPrompt，玩家交互长按1秒，可以把脑红拿起来，按钮上出现的文本是Pick Up
6.每个脑红出现后有一定的存在时间，存在时间做一个范围：25-30秒内随机，倒计时结束后脑红如果没有被任意玩家拿起来，就消失，然后立刻执行一次重新刷新，每消失一个就刷一个出来

需求文档V3.3.1 脑红生成后倒计时表现
脑红在生成后，需要在头顶显示这个脑红消失的倒计时，具体逻辑是：
在脑红头顶信息生成时，ReplicatedStorage - UI - BaseInfo - Title - Time的Visible属性要改成true，然后BaseInfo - Title - Time - Time这个textlabel用于显示倒计时时间，格式固定是xxS,xx是剩余的秒数，要精确到小数点后一位，比如24.5S代表还有24.5秒消失



需求文档V3.3.2 特殊事件客户端逻辑显示
概述：这里主要是接需求文档V2.4部分关于特殊事件的显示的逻辑

详细规则：
1.Workspace - Scene - Billboard - SurfaceGui - Frame是一个用于显示特殊事件相关时间的一个Frame，其子节点有一些textlabel用于显示特殊事件相关的倒计时的逻辑
2.我们在数据表中加入了文本显示名字的字段，现在的数据表是：
特殊事件Id	事件名	发生权重	持续时间（秒）	ReplicatedStorage中的名字	天空盒路径	文本显示名字
1001	骇客事件	100	300	EventHacker	Lighting/Hacker	TimeHacker
1002	熔岩事件	100	300	EventLava	Lighting/Lava	TimeLava

注意比如骇客事件的文本显示名字是：TimeHacker，也就是Workspace - Scene - Billboard - SurfaceGui - Frame - TimeHacker这个textlabel
客户端显示的逻辑是：
1.显示当前事件与下一个事件的Textlabel，也就是比如到了某个事件了，就把对应的textlabel显示出来
2.当前正在进行的事件显示倒计时：内容格式固定是：xx End In: mm:nn,其中xx是事件名字，mm:nn是分和秒
3.即将生成的事件显示倒计时，内容格式固定是：xx Event In: mm:nn其中xx是事件名字，mm:nn是分和秒

需求文档V3.3.3 脑红获取
1.我们现在的脑红是，在地上与脑红交互后，立刻就获得了脑红，这个逻辑还不够，我们要对这个逻辑进行优化，修改为后面的这些逻辑：
2.玩家与脑红交互后，可以拿起脑红，注意这个拿起脑红是指玩家使用动作：135438263083349 ，这个动作是把脑红拿在手里，举过头顶那个，这个用和背包交互后把脑红拿在手里一样的交互逻辑即可
3.玩家把脑红拿起来，这时候是不进入背包的，因为这个脑红还没有属于玩家只是暂时被控制了，如果玩家此时被其他玩家攻击导致摔倒，那脑红要在原地落地，解除在玩家头顶拿着的状态
4.Workspace - Scene - Grond - Homeland是我们的家园的Part，玩家只有拿着脑红进入Homeland的范围内，才算玩家成功获得了这个脑红
5.当玩家成功获得脑红后：
    5.1解除脑红在手里拿着的状态，解除举脑红的动作
    5.2脑红归属于玩家，出现在玩家的背包
    5.3弹出系统提示：把StarterGui - Main - BrainrotGetTips 的Visible改成ture显示出来，文本内容是You Claimed a [脑红名字]！，注意弹出tips的时候要有现在那些通用的弹出的tips的效果

需求文档V3.3.4 补充一些拿脑红的规则：
1.脑红在地上刷新出来后，需要重复不断原地播放待机动效
2.玩家拿起脑红后，脑红头顶的信息不要消失（我是指没回家之前），这个脑红的倒计时要继续，倒计时结束时如果玩家还没回到家，那么这个脑红要消失
3.玩家在目标区域举起脑红的情况下点击背包中的其他脑红，要把当前拿着的脑红解除拿起状态，重新在地上出现然后再拿起自己背包里的
4.玩家举着未获得的脑红的时候，与地上其他的脑红再交互拿起，需要把原来的脑红放地上，把新交互的脑红拿起来

需求文档V3.3.5  提升一次性可拿脑红的数量
1.我们现在的游戏中，玩家一次只能拿起一个脑红，我们这个版本要做的就是：玩家可以一次携带多个脑红，可以通过升级来提升一次携带脑红的数量
2.我们的携带表是这样的：
id	一次携带数量	金币价格	罗布币价格	开发者商品id
101	2	5000000	19	3565743552
102	3	20000000	19	3565743801
103	4	600000000	19	3565744240
104	5	600000000	19	3565744441

详细规则：
1.玩家可以同时携带多个时，多个脑红直接重叠在玩家头顶即可，注意这里说的是去刷新区域拿起脑红时，可以一次拿多个，而不是在家里点背包能同时拿多个，这个一定要注意
2.如果拿着多个脑红但是又到了上限，然后又与场中的脑红交互，就把最早拿的拿个丢下，拿起新交互的这个
3.玩家触碰Workspace - Scene - UpgradeCarry，触发打开携带升级界面，也就是把StarterGui - Main - Carry的Visible改成true，注意打开时也要有现在通用的打开效果和隐藏ui这些基础逻辑
4.鼠标移动到StarterGui - Main - Carry - Title - CloseButton也要有放大旋转的效果，玩家点击CloseButton可以关闭携带升级界面
5.StarterGui - Main - Carry - Equipinfo - EquipTemplate - Num1是当前可携带的值，StarterGui - Main - Carry - Equipinfo - EquipTemplate - Num2是升级后可携带的数值
6.StarterGui - Main - Carry - Equipinfo - EquipTemplate - GoldButton是金币购买按钮，其中GoldButton - Frame - GoldMoney用于显示金币价格数值，这里要用大数值逻辑
7.StarterGui - Main - Carry - Equipinfo - EquipTemplate - RobuxBuyButton是罗布币购买按钮，其中RobuxBuyButton - Frame - RMoney用于显示罗布币价格
8.每个携带升级都配了对应的开发者商品id，升级时直接调用对应开发者商品的购买
9.如果升级已经到了最高值，则隐藏EquipTemplate，显示出来StarterGui - Main - Carry - Equipinfo - MaxTips


需求文档V3.4 一些小零碎功能
1.玩家点击StarterGui - Main - TopRightGui - Invite按钮，可以打开默认的系统的邀请好友界面
2.玩家触碰到Workspace - Ice，直接触发死亡
3.玩家死亡后，需要立刻重生，现在死亡后还是会延迟一会儿才重生

需求文档V3.5 新增特殊事件：钻石事件
1.这个特殊事件实现逻辑和以前的两种不一样，要求共存
2.钻石事件发生时，是去ReplicatedStorage - EventScene下寻找Diamond这个文件夹，复制一份，把复制出来的Diamond加到Workspace下变成Workspace的子集。时间到了后，移除Diamond，其他保持不变
修改后的事件表是：
特殊事件Id	事件名	发生权重	持续时间（秒）	ReplicatedStorage中的名字	天空盒路径	文本显示名字
1001	Hacker	100	300	EventHacker	Lighting/Hacker	HackerEvent
1002	Lava	100	300	EventLava	Lighting/Lava	LavaEvent
1003	Diamond	100	300	EventScene/Diamond	Lighting/Diamond	DiamondEvent

其中：1003是钻石事件，不同的是ReplicatedStorage中的名字这个字段下配置的是路径，也就是ReplicatedStorage - EventScene - Diamond这个文件夹
钻石事件发生的时候天空盒也得按一样的逻辑展示
注意这里有个新改变：当特殊事件发生的时候，需要把现在默认的天空盒屏蔽。结束后再拿回来，默认的是Lighting - Atmosphere和Lighting - DefaultSky这俩

需求文档V3.6 设置功能
1.玩家点击StarterGui - Main - TopRightGui - Options - Button按钮，打开设置界面（把StarterGui - Main - Option显示出来），点击StarterGui - Main - Option - Title - CloseButton关闭界面
2.注意打开关闭时都要走当前的通用弹框效果以及鼠标移动到关闭按钮的时候的效果也要
3.设置功能，主要是用来控制游戏内的音效和音量的播放：

共两个设置选项：Music和Sfx，Music控制BGM是否播放，Sfx控制音效是否播放。
    a.常规状态下，BGM和音效都是默认开启的，也就是播放状态
    b.玩家的音乐音效设置，要在下次登录的时候，保持这个状态，当然可以只记录在当前设备中即可，不用在服务端记录，如果在服务端记录也可以

以音效举例：Options - Bg - Music - CloseButton就是控制开关的按钮，CloseButton下有个叫Text的textlabel，用于显示当前音效播放状态，如果是开启播放，文本就是On，如果是关闭状态，文本就是Off
CloseButton下有个子节点是控制渐变的叫UIGradient，开启的状态下，渐变起始颜色是#55ff00，渐变终止颜色是#ffff00，关闭状态下渐变起始颜色是#cb000e，渐变终止颜色是#ff5d35，所以当玩家点击按钮切换状态时，也要同步修改按钮的状态

如果关闭Bgm播放，就是把游戏内默认的Bgm以都不播放，再开启来后就根据当前状态重新开始播即可，尽管我们目前还没做bgm但是要预留好接口
如果关闭音效播放，就是把游戏内默认的各类非BGM的音效播放全部不播放，再开启后再根据触发条件再播放即可

需求文档V3.7 加群组领奖励功能

概述：玩家加入我们游戏的群组，可以领一份奖励

详细规则是：

1.玩家点击StarterGui - Main - TopRightGui - GroupReward  - Button这个按钮，打开奖励领取界面（把StarterGui -  Main - GroupReward的visible属性改成true）
2.玩家点击StarterGui -  Main - GroupReward -  Title - CloseButton按钮，关闭界面，注意打开关闭的时候都要有通用效果包括鼠标移动到关闭按钮的时候也要有对应效果
3.玩家点击StarterGui -  Main - GroupReward - Claim这个按钮，触发领取验证，如果验证成功，则为玩家发放奖励，需要弹出系统飘字提示：Claim Successful!（把Main - RewardClaimTips显示出来，一样的逻辑都是，把文本改成Claim Successful!即可，参考重生或者偷脑红这些时候的提示），同时领取成功后把Claim这个按钮的Visible属性改成false，然后把StarterGui -  Main - GroupReward - Claimed这个textlabel的visible属性改成True
4.玩家领取成功后，需要把TopRightGui - GroupReward的Visible属性改成False，永久不再出现了。
5.玩家如果点击领取时，不满足领取条件，则无法领取，飘字提示：Join the group for rewards!（使用Main - RewardClaimTips），然后需要播放一下我们系统的警告音，如果我们还没做或者警告音那在开发最后告诉我

我们的奖励领取条件是：
1.玩家一定要加入我们游戏的群组，这个应该在roblox有提供的官方验证接口，直接用这个接口判断玩家是否加入了群组
2.玩家在点击领取奖励的那一刻只要玩家在群组中，即可领取成功

奖励内容是为玩家发放1个10015这个脑红

我们的群组id是：438450096

需求文档V3.8   关于挂机奖励的领取

1.在玩家离线后再次登录时，需要主动触发弹框弹出，让玩家点击领取，具体规则见下面：

关于挂机金币弹框的规则：

1.当玩家离线后再次登录时，如果玩家未领取的挂机金币数值大于等于1，那么需要主动弹出挂机金币领取弹框，也就是主动把StarterGui - Main - Idlecoin的Visible属性改成True
2.玩家点击StarterGui - Main - Idlecoin - Title - CloseButton这个按钮，可以关闭弹框，注意，关闭弹框只是关闭，不要触发给玩家领金币的操作，点这个只是意味着玩家暂时先不领取
3.StarterGui - Main - Idlecoin - CurrentCash - Number是一个textlabel，用于显示玩家当前挂机金币已经积累的总金币，这里不使用大叔数值，就是多少就显示多少  
4.StarterGui - Main - Idlecoin - Claim是一个按钮，玩家点击后，可以直接领取当前已经积累的挂机金币，点击领取后发放金币，播放金币数字变化的动画并且同步关闭弹框，另外也要同步播放我们游戏中领金币时的音效
5.StarterGui - Main - Idlecoin - Claim10是一个按钮，玩家点击后，直接触发对开发者商品：3566656890的购买，这个开发者商品作用是：直接为玩家发放10倍的当前数值的挂机金币，比如当前积累了100金币，那购买商品后玩家实际可以获得1000金币
    a.玩家点击按钮触发开发者商品购买，如果购买成功则发放金币并关闭界面
    b.玩家如果触发商品购买但是又没购买，关闭了购买弹框，则不关闭这个界面，保持原状即可
    c.StarterGui - Main - Idlecoin - Claim10 - CashNum是一个textlabel，用于显示玩家当前挂机金币累计数值乘10后的数值，比如挂机金币积累了100，那这里的数值就显示是$1000
6.玩家点击CloseButton/Claim/Claim10这三个按钮时，都需要有对应的点击效果
7.tarterGui - Main - Idlecoin - Claim10是一个imageButton，我加入了渐变子节点UIGradient用来控制渐变，现在的这个渐变是静态的，我需要你帮我做成动态的，那种循环从左到右的动态效果，同时还要每2秒，给整个按钮一个白色的扫光从按钮上扫过


需求文档V3.9 七日登录奖励
概述：我们需要开发一套“七日登录奖励”系统，玩家可以每天登录领取一份奖励

基础逻辑简单来说就是：只要玩家登录，就可以领取一份今日的登录奖励，然后明天再登录就可以领下一天的奖励，如果明天没登录，后天登录了，也是领的第二天的奖励

详细规则是：

1.玩家登录的第一天触发七日奖励的第一天的奖励领取，所以新玩家第一天的时候的奖励是默认解锁可以领取的
2.每天utc0点是登录奖励刷新的节点，奖励刷新后，只要玩家再次登录，就可以领取这份奖励（当然如果玩家在线并且奖励刷新了不用下线可以直接领），所以只要玩家登录了，就可以领新刷新的这份奖励，哪怕是好几天不登陆，再次登录也是领这份奖励，因为状态已经变成了可领取
3.具体逻辑我建议做成玩家上线时去判定奖励刷新即可，比如玩家好几天不登陆，突然登录了，判断这个时间点跟上一份奖励领取时的中间是否存在一个utc0点，如果有则认为就是跨天了，就应该能领取最新一份的登录奖励了。
4.所以极限情况是玩家23点59分登录领了第一天的登录奖励然后过了utc0点，又能立刻领第二天的登录奖励，然后过了好几天才再次登录后，可以领第三天的登录奖励
5.所以我们这个本质是累计登录奖励，而不是登陆一次过七天再登录就能领全部7天的奖励

奖励类型有：
1.发放指定Id的脑红
2.发放指定数量的金币

具体客户端逻辑是：
1.玩家点击StarterGui - Main - TopRightGui - SevenDays - Button这个按钮，可以打开七日登录奖励界面（也就是把StarterGui - Main -  Sevendays的Visible属性改成True）
2.玩家点击SevenDays - Title - CloseButton这个按钮可以关闭七日登录奖励界面
3.SevenDays  - NextReward是一个TextLabel，用于显示下一个奖励的刷新倒计时格式固定就是：Refresh In:XX:YY,XX:YY就是小时：分钟，也就是距离下个UTC0点的倒计时
4.点击StarterGui - SevenDays - UnlockAll这个按钮，直接触发对开发者商品：3489888670的购买，购买成功后，立刻解锁本轮7天奖励中的所有奖励，全部变成可领取状态
    a.这里需要有一些特殊处理：当玩家购买这个商品后，会把当前剩余的未购买的奖励全部变成可领取状态。
    b.玩家如果把所有奖励都领取了，那么关闭这个界面，再次打开后，会重新刷新一份新的7天奖励，注意这是一份新的7天奖励，其中第一天的奖励是不能领的，要等下一个utc0点刷新才能领第一天的奖励，其实可以视为第8天的奖励，后面都是一样的逻辑
    c.同样的，玩家通过登录7天领取了所有奖励后，关闭界面，再打开也是会重新刷新一份新的7天奖励出来
    d.玩家可以通不断购买开发者商品3489888670，来不断解锁当前轮次的7天奖励

5.Bg下有Reward01到Reward07共7个Frame ，每个都是代表某天的奖励，我们以Reward01举例来说明规则，Reward01就是第一天的奖励，Reward02就是第二天的奖励，以此类推
    a.Reward01 - DayNum是代表当前是第几天的文本，在这种状态下，当一个奖励还未解锁还不能领取时，DayNum的visible属性应该设置为True，也就是显示为第几天，你不用去设定DayNum的文本内容，只需要控制是否显示即可
    b.Reward01 - Claim是一个按钮，是领取按钮，如果某个奖励已经变成了可领取状态，则把Claim的Visible属性改成True，把上面的DayNum的Visible属性改成False，点击Claim可以领取奖励，注意点击的时候需要有一个点击效果
    c.Reward01 - Claimed是一个textlabel文本，用于领取完奖励后显示出来代表奖励已经领取了，领完奖励后，需要把Claimed的visible属性改成True，把Claim的visible属性改成False
    d.奖励领取成功后，需要把Reward01 - Bg的Visible属性改成True

    e.注意默认状态下，只有DayNum的Visible属性是默认true的，其他都是false
    f.当刷新了一轮新的奖励后，需要把所有奖励的状态全部改成默认状态
7.StarterGui Main - TopRightGui - SevenDays - RedPoint是红点，默认的Visible属性是False，当有可领取但是玩家未领取的七日登录奖励时，需要把红点显示出来，并且红点在显示状态下，需要每2秒给红点一个小动效，左右抖动一下，每2秒播一次，提醒玩家看到

暂时我们的测试数值就是：7天奖励就是10001 到 10007 这七个脑红每天发一个，接下来的版本我们再做具体的奖励配置

V3.9.1 补充关于七日奖励的 
1.玩家领取奖励后，需要弹出提示，Main - SevendaysClaim改成Visible，弹出时用我们现在游戏内那些通用的效果
2.玩家每次登录时，如果有未领取的可领取的七日登录奖励，要弹出弹框，注意：先弹出这个弹框，还有挂机奖励弹框也要弹出，再弹出挂机奖励弹框
3.我们的奖励内容是：
天数	奖励类型	参数
1	金币	500
2	脑红	10024
3	金币	100000
4	脑红	10038
5	金币	500000000
6	脑红	10047
7	脑红	10055

V4.0 新手礼包
概述：这是个通行证功能，玩家只能买一次，走的是通行证逻辑

详细规则：
1.玩家点击StarterGui - Main - StarterPack - TextButton这个按钮，打开新手礼包界面（把StarterGui - Main - NewplayerPack的visible改成true）
2.玩家点击StarterGui - Main - NewplayerPack - Title - CloseButton关闭弹框
3.玩家点击StarterGui - Main - NewplayerPack - BuyButton按钮，触发对新手礼包通行证的购买，通行证id是：1779916806
4.玩家购买成功后，需要弹出对应的购买成功弹框，具体逻辑是：
    4.1先关闭StarterGui - Main - NewplayerPack
    4.2显示出来StarterGui - StarterGui - ClaimSuccessful
    4.3ClaimSuccessful - Bg - ItemListFrame - ItemTemplate是奖励内容模板，默认是隐藏的，生成的时候复制一份修改信息显示出来，变成对应的奖励信息
    4.4ItemTemplate - Icon是奖励图标
    4.5ItemTemplate - Number是奖励数量显示的textlabel
    4.6给这个弹框一个出现的效果，具体大概就是：ClaimSuccessful先从左到右滑出来，然后ItemTemplate奖励一个个快速出现
    4.7ClaimSuccessful出现后至少锁定1秒，1秒后玩家点击屏幕任意区域可以关闭ClaimSuccessful
5.我们的新手奖励内容是：
脑红10032  1个，脑红10036   1个，金币一共 100000
