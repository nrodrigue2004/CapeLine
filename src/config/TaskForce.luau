-- Task forces (spec: Hero MMO features > Task forces; H4). Pure data, tuned in the playtest.
-- A task force is a chain of 4 or 5 missions in a row in the pockets, built from the step kinds that already
-- exist (hold, break, chase, reach, defeat, boss, warframe), with a comic panel between legs. 1 to 4 players,
-- level 12 or more, after Act 1. Sidekicking applies (Config.Sidekick). Rules: Shared.TaskForcePlan; runs:
-- MissionService; the board and quick join: TaskForceService.
-- PLACEHOLDER CONTENT: lore thread to fill. The legs below are generic robot pockets on the existing layouts
-- (no story characters); the panels between legs are placeholders, and the names are the spec's working
-- titles. The lore thread replaces the panels' ids with real comic panels and may rename the runs.
return {
	floor = 12, -- level to start one (and Act 1 done)
	lookSlack = 2, -- Looking can put you in a squad whose task force floor is up to 2 levels above you
	maxPlayers = 4,
	rejoin = 180, -- seconds a member who left or dropped keeps their place
	numBase = 100, -- MissionState num for a task force run: numBase + its index
	panelTime = 4, -- seconds on the comic panel between legs
	speedClear = 1200, -- a clear under 20 minutes earns the speed badge and patch (H7)
	legMinutes = 8, -- a leg's expected length (25 to 40 minutes a run)
	epicTier = "Epic", -- the guaranteed roll at the end, at your own level
	weeklyRenownMult = 2, -- the first clear each week (per task force) pays double Renown
	listRate = 1, -- TaskForceList / TaskForceJoin / TaskForceLook per second (Remotes)
	list = {
		{
			id = "LongNight",
			name = "Meridian's Long Night", -- spec working title (hero side)
			side = "hero",
			mentor = "CaptainMeridian", -- H6
			-- PLACEHOLDER CONTENT: lore thread to fill (panels and step text)
			legs = {
				{
					layout = "station",
					panel = "LongNight1",
					waves = { { "SparkDrone", 5 }, { "BurglarBot", 4 }, { "SparkDrone", 6 } },
					waveGap = 12,
					steps = {
						{
							kind = "hold",
							points = 3,
							seconds = 12,
							radius = 12,
							text = "Hold the three relays",
						},
						{
							kind = "break",
							points = 3,
							hits = 16,
							guards = { "Turret", 2 },
							text = "Smash the robot crates",
						},
					},
				},
				{
					layout = "dungeon",
					panel = "LongNight2",
					steps = {
						{
							kind = "defeat",
							squads = { { "BurglarBot", 5 }, { "SparkDrone", 3 } },
							room = 1,
							text = "Clear the loading bay",
						},
						{
							kind = "reach",
							at = "gauntletEnd",
							turrets = 5,
							room = 2,
							text = "Run the turret hall",
						},
						{
							kind = "defeat",
							squads = { { "BurglarBot", 6 } },
							room = 3,
							text = "Stop the assembly line",
						},
					},
				},
				{
					layout = "rooftops",
					panel = "LongNight3",
					steps = {
						{ kind = "reach", at = "contact", text = "Reach the signal" },
						{
							kind = "chase",
							enemy = "SneakBot",
							hops = 9,
							speed = 28,
							text = "Catch the courier bot",
						},
					},
				},
				{
					layout = "tower",
					panel = "LongNight4",
					steps = {
						{ kind = "reach", at = "top", text = "Climb the factory stack" },
						{
							kind = "boss",
							enemy = "NullSentinel",
							hpMult = 10,
							adds = { "SparkDrone", 4 },
							text = "Beat the foreman bot",
						},
					},
				},
				{
					layout = "arena",
					panel = "LongNight5",
					steps = { { kind = "warframe", text = "Beat the battle form again" } },
				},
			},
		},
		{
			id = "Heist",
			name = "The Margrave's Heist", -- spec working title (villain side)
			side = "villain",
			mentor = "TheMargrave", -- H6
			-- PLACEHOLDER CONTENT: lore thread to fill (panels and step text)
			legs = {
				{
					layout = "rooftops",
					panel = "Heist1",
					steps = {
						{ kind = "reach", at = "contact", text = "Meet the crew" },
						{
							kind = "chase",
							enemy = "SneakBot",
							hops = 8,
							speed = 26,
							text = "Grab the vault key bot",
						},
					},
				},
				{
					layout = "station",
					panel = "Heist2",
					waves = { { "SparkDrone", 5 }, { "Turret", 2 }, { "SparkDrone", 6 } },
					waveGap = 12,
					steps = {
						{
							kind = "break",
							points = 3,
							hits = 18,
							guards = { "Turret", 2 },
							text = "Crack the power boxes",
						},
						{
							kind = "hold",
							points = 3,
							seconds = 10,
							radius = 12,
							text = "Hold the cut-off switches",
						},
					},
				},
				{
					layout = "dungeon",
					panel = "Heist3",
					steps = {
						{
							kind = "defeat",
							squads = { { "BurglarBot", 4 }, { "SparkDrone", 3 } },
							room = 1,
							text = "Get past the guard bots",
						},
						{
							kind = "reach",
							at = "gauntletEnd",
							turrets = 6,
							room = 2,
							text = "Through the laser hall",
						},
						{
							kind = "boss",
							enemy = "NullSentinel",
							hpMult = 10,
							adds = { "Turret", 2 },
							room = 3,
							text = "Beat the vault keeper",
						},
					},
				},
				{
					layout = "arena",
					panel = "Heist4",
					steps = {
						{
							kind = "defeat",
							squads = { { "BurglarBot", 6 }, { "SparkDrone", 4 } },
							text = "Fight off the hunter squad",
						},
					},
				},
			},
		},
	},
}
