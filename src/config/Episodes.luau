-- Episodes: the weekly episode (spec: Hero MMO features > Weekly episodes; H8). Pure data: a new episode is a
-- config change and a playtest, not new code. Free for everyone, standalone (never the main story).
-- Every Monday 00:00 UTC (the world seed's week) the next episode goes live: season s, week w of the Hero Pass
-- season (Config.Pass.startWeek, 8 weeks) plays seasons[s][w]; a season with no episodes written yet replays
-- the last written season's list.
-- Each episode:
--   panels: the 3 panel comic intro from the mentors, a line each for heroes (who[1], a Config.Mentors index)
--     and for villains (who[2]);
--   events: the week's theme on the random events' mix (Config.Events ids, a weight; others weigh 1);
--   steps: 3 themed contracts and a task force or mission step: key counted by PassService (incident,
--     incident:<template>, contract, rescue, kill, kill:<robot kind>, find, contest, boss, mission, taskForce),
--     n, and the text on the Episode card;
--   each step pays stepRenown and stepXp (Pass XP); all four add doneRenown, doneXp and the week's badge
--   (Config.Badges group "episodes": episode number e within the season list).
-- PLACEHOLDER CONTENT: the panel lines are drafts for the lore thread to rewrite.
return {
	stepRenown = 600,
	stepXp = 750,
	doneRenown = 1500,
	doneXp = 1000,
	seasons = {
		{
			{
				name = "Opening Night",
				theme = "The city throws a street party and the robots crash it",
				panels = {
					{
						who = { 1, 3 },
						hero = "Big crowds tonight. Keep the streets clear.",
						villain = "Big crowds tonight. Big pockets.",
					},
					{
						who = { 2, 4 },
						hero = "Watch the parade route, kid.",
						villain = "Nobody watches the rooftops at a parade.",
					},
					{
						who = { 1, 3 },
						hero = "Make it a night they remember for the right reasons.",
						villain = "Make it a night they remember.",
					},
				},
				events = { ParadeGoneWrong = 4, StadiumLockdown = 2 },
				steps = {
					{ key = "incident", n = 6, text = "Clear 6 incidents" },
					{ key = "rescue", n = 10, text = "Get 10 citizens to safety" },
					{ key = "contest", n = 1, text = "Step on the stage in a costume contest" },
					{ key = "taskForce", n = 1, text = "Clear a task force" },
				},
			},
			{
				name = "Lights Out",
				theme = "Blackouts roll across the districts",
				panels = {
					{
						who = { 1, 3 },
						hero = "The grid keeps dropping. That is no accident.",
						villain = "Somebody is cutting the power. Not us. Yet.",
					},
					{
						who = { 2, 4 },
						hero = "In the dark you listen. The robots are loud.",
						villain = "Dark streets, open doors. I love a blackout.",
					},
					{
						who = { 1, 3 },
						hero = "Find who is behind it.",
						villain = "Find who is behind it and send them a bill.",
					},
				},
				events = { Blackout = 4, PowerPlantOverload = 3 },
				steps = {
					{ key = "incident:SignalJam", n = 2, text = "Clear 2 Signal Jam incidents" },
					{ key = "kill:SneakBot", n = 15, text = "Defeat 15 Sneak Bots" },
					{ key = "contract", n = 3, text = "Finish 3 contracts" },
					{ key = "mission", n = 1, text = "Clear a mission" },
				},
			},
			{
				name = "High Tide",
				theme = "Strange tides wash robots up on the Docks",
				panels = {
					{
						who = { 1, 3 },
						hero = "The sea is pushing robots ashore.",
						villain = "The tide brought presents.",
					},
					{
						who = { 2, 4 },
						hero = "Mind the water, it bites this week.",
						villain = "Salvage rights: whoever grabs it first.",
					},
					{ who = { 1, 3 }, hero = "Hold the harbour.", villain = "Take the harbour." },
				},
				events = { TidalSurge = 4, HarbourFog = 3 },
				steps = {
					{ key = "kill:Diver", n = 12, text = "Defeat 12 Divers" },
					{ key = "find", n = 3, text = "Find 3 collection items" },
					{ key = "incident", n = 8, text = "Clear 8 incidents" },
					{ key = "taskForce", n = 1, text = "Clear a task force" },
				},
			},
			{
				name = "Sky Freight",
				theme = "Airships drop crates over the city all week",
				panels = {
					{
						who = { 1, 3 },
						hero = "Crates falling out of the sky. Catch what you can.",
						villain = "Free deliveries. Sign for nothing.",
					},
					{
						who = { 2, 4 },
						hero = "Look up before you step out.",
						villain = "I call dibs on the shiny ones.",
					},
					{
						who = { 1, 3 },
						hero = "Keep the drops away from people.",
						villain = "Keep the drops away from the Vigil.",
					},
				},
				events = { AirshipDrop = 4, MeteorShower = 2 },
				steps = {
					{ key = "kill", n = 60, text = "Defeat 60 robots" },
					{ key = "boss", n = 1, text = "Take part in a world boss fight" },
					{ key = "contract", n = 3, text = "Finish 3 contracts" },
					{ key = "mission", n = 1, text = "Clear a mission" },
				},
			},
			{
				name = "Vault Week",
				theme = "Every vault in the city is a target",
				panels = {
					{
						who = { 1, 3 },
						hero = "Every vault in town is lit up on the board.",
						villain = "Every vault in town. Every one.",
					},
					{
						who = { 2, 4 },
						hero = "Guard the doors, not the money.",
						villain = "I only take what glitters.",
					},
					{
						who = { 1, 3 },
						hero = "No one gets hurt over a vault.",
						villain = "Nobody gets hurt. It is bad for business.",
					},
				},
				events = { VaultBreach = 4, TrainHijack = 2 },
				steps = {
					{ key = "incident:VaultBreach", n = 2, text = "Clear 2 Vault Breach incidents" },
					{ key = "incident:RobotHeist", n = 3, text = "Clear 3 Robot Heist incidents" },
					{ key = "contract", n = 4, text = "Finish 4 contracts" },
					{ key = "taskForce", n = 1, text = "Clear a task force" },
				},
			},
			{
				name = "Bridge Out",
				theme = "The bridges are under siege",
				panels = {
					{
						who = { 1, 3 },
						hero = "They are cutting the city in half.",
						villain = "Close the bridges, and the city is ours to split.",
					},
					{
						who = { 2, 4 },
						hero = "Two sides of one river, kid. Keep them joined.",
						villain = "A toll bridge. I like the sound of that.",
					},
					{ who = { 1, 3 }, hero = "Reopen the crossings.", villain = "Own the crossings." },
				},
				events = { BridgeSiege = 4, RobotRampage = 2 },
				steps = {
					{ key = "kill:BruteBot", n = 10, text = "Defeat 10 Brute Bots" },
					{ key = "rescue", n = 12, text = "Get 12 citizens to safety" },
					{ key = "incident", n = 8, text = "Clear 8 incidents" },
					{ key = "mission", n = 1, text = "Clear a mission" },
				},
			},
			{
				name = "Rooftop Season",
				theme = "Chases and ambushes across the skyline",
				panels = {
					{
						who = { 1, 3 },
						hero = "The fight moved up. Follow it.",
						villain = "The rooftops are the fast lane.",
					},
					{
						who = { 2, 4 },
						hero = "Mind the edges.",
						villain = "Never look down. Look at the loot.",
					},
					{ who = { 1, 3 }, hero = "Own the skyline.", villain = "Own the skyline." },
				},
				events = { AirshipDrop = 2, StadiumLockdown = 2 },
				steps = {
					{ key = "incident:RooftopChase", n = 3, text = "Clear 3 Rooftop Chase incidents" },
					{ key = "incident:SkyAmbush", n = 2, text = "Clear 2 Sky Ambush incidents" },
					{ key = "find", n = 3, text = "Find 3 collection items" },
					{ key = "taskForce", n = 1, text = "Clear a task force" },
				},
			},
			{
				name = "Finale Week",
				theme = "Everything at once for the season's last week",
				panels = {
					{
						who = { 1, 3 },
						hero = "Last week of the season. Give it everything.",
						villain = "Last week of the season. Take everything.",
					},
					{
						who = { 2, 4 },
						hero = "Proud of you, kid. Now go.",
						villain = "One last job. Then another.",
					},
					{
						who = { 1, 3 },
						hero = "See you at the top.",
						villain = "See you at the top. I will be there first.",
					},
				},
				events = { RobotRampage = 3, MeteorShower = 2, ParadeGoneWrong = 2 },
				steps = {
					{ key = "kill", n = 100, text = "Defeat 100 robots" },
					{ key = "boss", n = 2, text = "Take part in 2 world boss fights" },
					{ key = "contest", n = 1, text = "Step on the stage in a costume contest" },
					{ key = "taskForce", n = 1, text = "Clear a task force" },
				},
			},
		},
	},
}
