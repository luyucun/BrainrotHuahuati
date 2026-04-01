--[[
ScriptName: JetpackConfig
FileName: JetpackConfig.lua
ScriptType: ModuleScript
StudioPath: ReplicatedStorage/Shared/JetpackConfig
]]

local JetpackConfig = {}

JetpackConfig.RequestDebounceSeconds = 0.2
JetpackConfig.PurchaseSuccessTipText = "Purchase Successful!"
JetpackConfig.PurchaseSuccessTipDisplaySeconds = 2
JetpackConfig.PurchaseSuccessTipEnterOffsetY = 40
JetpackConfig.PurchaseSuccessTipFadeOffsetY = -8
JetpackConfig.RuntimeAccessoryAttributeName = "JetpackRuntimeAccessory"
JetpackConfig.RuntimeJetpackIdAttributeName = "JetpackId"

JetpackConfig.Entries = {
	{
		Id = 1001,
		CoinPrice = 0,
		RobuxPrice = 0,
		ProductId = 3562613109,
		IsDefaultUnlocked = true,
		Name = "Takekopter",
		Icon = "rbxassetid://138477934814998",
		AssetPath = "ReplicatedStorage/Jetpack/Takekopter",
		NoGravityDuration = 0.5,
		BulletTimeFallSpeed = 2.2,
	},
	{
		Id = 1002,
		CoinPrice = 2000,
		RobuxPrice = 0,
		ProductId = 3566382877,
		IsDefaultUnlocked = false,
		Name = "BlueFirework",
		Icon = "rbxassetid://104781872805135",
		AssetPath = "ReplicatedStorage/Jetpack/BlueFirework",
		NoGravityDuration = 1,
		BulletTimeFallSpeed = 2,
	},
	{
		Id = 1003,
		CoinPrice = 50000,
		RobuxPrice = 0,
		ProductId = 3562613276,
		IsDefaultUnlocked = false,
		Name = "StarBackpack",
		Icon = "rbxassetid://107730139753375",
		AssetPath = "ReplicatedStorage/Jetpack/StarBackpack",
		NoGravityDuration = 1.5,
		BulletTimeFallSpeed = 1.8,
	},
	{
		Id = 1004,
		CoinPrice = 2500000,
		RobuxPrice = 0,
		ProductId = 3566383188,
		IsDefaultUnlocked = false,
		Name = "BuzzLightyear",
		Icon = "rbxassetid://121547731358867",
		AssetPath = "ReplicatedStorage/Jetpack/BuzzLightyear",
		NoGravityDuration = 2,
		BulletTimeFallSpeed = 1.6,
	},
	{
		Id = 1005,
		CoinPrice = 125000000,
		RobuxPrice = 0,
		ProductId = 3566383337,
		IsDefaultUnlocked = false,
		Name = "Peace&Love",
		Icon = "rbxassetid://105773511185843",
		AssetPath = "ReplicatedStorage/Jetpack/Peace&Love",
		NoGravityDuration = 2.5,
		BulletTimeFallSpeed = 1.4,
	},
	{
		Id = 1006,
		CoinPrice = 6250000000,
		RobuxPrice = 0,
		ProductId = 3562613455,
		IsDefaultUnlocked = false,
		Name = "FireRocket",
		Icon = "rbxassetid://136689093387925",
		AssetPath = "ReplicatedStorage/Jetpack/FireRocket",
		NoGravityDuration = 3,
		BulletTimeFallSpeed = 1.2,
	},
	{
		Id = 1007,
		CoinPrice = 312500000000,
		RobuxPrice = 0,
		ProductId = 3562613596,
		IsDefaultUnlocked = false,
		Name = "Cola",
		Icon = "rbxassetid://122686478401756",
		AssetPath = "ReplicatedStorage/Jetpack/Cola",
		NoGravityDuration = 3.5,
		BulletTimeFallSpeed = 1,
	},
	{
		Id = 1008,
		CoinPrice = 15625000000000,
		RobuxPrice = 0,
		ProductId = 3566383560,
		IsDefaultUnlocked = false,
		Name = "Praetorian",
		Icon = "rbxassetid://102301594315481",
		AssetPath = "ReplicatedStorage/Jetpack/Praetorian",
		NoGravityDuration = 4,
		BulletTimeFallSpeed = 0.8,
	},
	{
		Id = 1009,
		CoinPrice = 781250000000000,
		RobuxPrice = 0,
		ProductId = 3562613719,
		IsDefaultUnlocked = false,
		Name = "Keyboard",
		Icon = "rbxassetid://118959317539160",
		AssetPath = "ReplicatedStorage/Jetpack/Keyboard",
		NoGravityDuration = 4.5,
		BulletTimeFallSpeed = 0.6,
	},
	{
		Id = 1010,
		CoinPrice = 39062500000000000,
		RobuxPrice = 79,
		ProductId = 3566383805,
		IsDefaultUnlocked = false,
		Name = "Infrared",
		Icon = "rbxassetid://81265005840593",
		AssetPath = "ReplicatedStorage/Jetpack/Infrared",
		NoGravityDuration = 5,
		BulletTimeFallSpeed = 0.3,
	},
	{
		Id = 1011,
		CoinPrice = 1953125000000000000,
		RobuxPrice = 239,
		ProductId = 3566383964,
		IsDefaultUnlocked = false,
		Name = "Bubble",
		Icon = "rbxassetid://78883633915494",
		AssetPath = "ReplicatedStorage/Jetpack/Bubble",
		NoGravityDuration = 5.5,
		BulletTimeFallSpeed = 0.2,
	},
	{
		Id = 1012,
		CoinPrice = 97656250000000000000,
		RobuxPrice = 499,
		ProductId = 3566384171,
		IsDefaultUnlocked = false,
		Name = "EMP",
		Icon = "rbxassetid://138565059274915",
		AssetPath = "ReplicatedStorage/Jetpack/EMP",
		NoGravityDuration = 6,
		BulletTimeFallSpeed = 0.1,
	},
}

JetpackConfig.EntriesById = {}
JetpackConfig.EntriesByProductId = {}
JetpackConfig.DefaultEntryId = 0

for index, entry in ipairs(JetpackConfig.Entries) do
	entry.SortOrder = index
	JetpackConfig.EntriesById[entry.Id] = entry

	local productId = math.max(0, math.floor(tonumber(entry.ProductId) or 0))
	if productId > 0 then
		JetpackConfig.EntriesByProductId[productId] = entry
	end

	if entry.IsDefaultUnlocked and JetpackConfig.DefaultEntryId <= 0 then
		JetpackConfig.DefaultEntryId = entry.Id
	end
end

return JetpackConfig
