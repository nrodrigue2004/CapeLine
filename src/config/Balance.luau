-- Live tuning (spec: Global data, "Balance_v<N>": gap check G11, WP8). At boot the server reads one key from
-- the DataStore named store .. Config.Version.balance (Balance_v1 today) and lays its numbers over this
-- bundled Config before any other service starts (BalanceService, Shared.BalanceMerge). No key, any error, a
-- slow read, an unpublished place or Studio without API access: the bundled Config runs as it is.
-- * Only the paths in `keys` can change, each inside its own range. "*" stands for any key that already
--   exists at that spot in the bundled Config (never a new one). `min`/`max` are absolute; `rel` = { lo, hi }
--   is a share of the bundled number (a robot's hp at 0.5 to 2x its own); `int` wants a whole number.
-- * The list holds only numbers the SERVER alone reads (pay, robot and boss toughness, the boss clock).
--   Devices keep the bundled Config, so nothing a device shows or simulates is on it: no drop odds (the Loot
--   Info tab shows them), no Heroic pay tag, no level curve (it would move saved levels), no cooldowns or
--   speeds. Never ids, bits or orders (the wire and the save use them), never a price or anything sold.
--   Shared.BalanceMerge refuses a path in a `locked` section or with a `locked` word even if listed here.
-- * Bump Config.Version.balance whenever bundled numbers change: the store name moves with it, so an old
--   live key never lands on top of new bundled numbers.
return {
	on = true, -- the switch: on, it only reads (with no key written, nothing changes)
	store = "Balance_v", -- the DataStore's name before the version number
	key = "live", -- the one key nate writes in it
	timeout = 4, -- seconds the boot waits for the read before it runs on the bundled Config
	tries = 2, -- reads inside that time (the second after `retryWait` s)
	retryWait = 1,
	maxEntries = 200, -- a key with more numbers than this is refused whole
	maxDepth = 8,
	-- never tunable live, whatever `keys` says
	locked = {
		sections = {
			"Version",
			"Balance",
			"Data",
			"Net",
			"Places",
			"Safety",
			"Shop",
			"Pass",
			"Creator",
			"Weapons",
			"Hq",
			"Analytics",
			"Loot",
			"Settings",
		},
		words = {
			"id",
			"num",
			"typeId",
			"bit",
			"bits",
			"rogues",
			"order",
			"price",
			"robux",
			"product",
			"cost",
		},
	},
	keys = {
		-- pay: the two balance knobs over every Credit and Renown reward, then each source's own formula
		-- (value = base + perLevel x zone level: index 1 the base, 2 the per-level step)
		{ path = "Economy.scale.credits", min = 0.2, max = 4 },
		{ path = "Economy.scale.renown", min = 0.05, max = 1.5 },
		{ path = "Economy.earn.*.credits.1", min = 0, max = 2000 },
		{ path = "Economy.earn.*.credits.2", min = 0, max = 100 },
		{ path = "Economy.earn.*.renown.1", min = 0, max = 3000 },
		{ path = "Economy.earn.*.renown.2", min = 0, max = 100 },
		{ path = "Contracts.types.*.credits.1", min = 0, max = 1000 },
		{ path = "Contracts.types.*.credits.2", min = 0, max = 50 },
		{ path = "Contracts.types.*.renown.1", min = 0, max = 1000 },
		{ path = "Contracts.types.*.renown.2", min = 0, max = 50 },
		-- robots: the level scaling every robot shares, then each kind's hp and hit size
		{ path = "Enemies.scale.hpPerLevel", min = 0.02, max = 0.25 },
		{ path = "Enemies.scale.dmgBase", min = 5, max = 60 },
		{ path = "Enemies.scale.dmgPerLevel", min = 1, max = 12 },
		{ path = "Enemies.*.hp", rel = { 0.5, 2 }, int = true },
		{ path = "Enemies.*.coeff", rel = { 0.5, 2 } },
		-- the world boss: its HP and how long the city waits between bosses (seconds, shortest then longest)
		{ path = "Boss.hp.base", min = 20000, max = 300000, int = true },
		{ path = "Boss.hp.perHero", min = 0, max = 20000, int = true },
		{ path = "Boss.schedule.every.1", min = 600, max = 3600, int = true },
		{ path = "Boss.schedule.every.2", min = 600, max = 3600, int = true },
	},
	-- after the merge, each pair must read first <= second, or both of its live numbers are refused
	pairs = {
		{ "Boss.schedule.every.1", "Boss.schedule.every.2" },
	},
}
