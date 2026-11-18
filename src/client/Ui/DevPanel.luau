-- DevPanel: Studio-only test buttons and the server frame report (spec: Performance budgets). Never built
-- in a live game. Buttons: 30 load bots, clear bots, 5 drones, clear drones, spawner, god, class, level,
-- Comic/Anime style, robots, levels, skill points, Awakening, loot by source, Renown, Credits, Dust, find all
-- beacons, wreck here, repair city, flip cars, save, wipe, and (M6) incident by template, clear incidents,
-- event by type, boss now, boss to 1 HP, finish contract, clock phase, hero or villain side, and (M7) the
-- Ceremony prologue as the Vigil or the Syndicate and a jump to each of its beats (lore step 3), each Act 1 mission as each side and a jump to each of its stages (lore step 5), finish the step, leave, the side quest framework (lore step 10: give the sample chain, start, restart and finish steps, finish the chain, forget it, try each step kind alone), clear
-- Act 1 and reset the story, a sample line per guide and Lodestar beside you (lore step 6), and (M9) the creator, enter HQ, HQ level, 8 h away, all pieces, a test buy
-- (twice grants once) and the level cap, the daily streak (a day passes, skip a day, finish the quests, start
-- over; WP1), and (2026-11-17) the next incident, event or contract to try (the
-- "Inc:", "Ev:" and "Con:" buttons start the one named, "next" picks another), and a Heroic switch for them.
-- The stats line shows the server frame, script time per service, enemies, bots, send
-- rate and memory, plus the client fps and preset.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local AbilityRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityRules"))
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local ShopRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ShopRules"))
local EnemySim = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EnemySim"))
local OpeningPlan = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("OpeningPlan"))

local Kit = require(script.Parent.Kit)
local State = require(script.Parent.Parent.State)
local QualityController = require(script.Parent.Parent.Controllers.QualityController)
local Telemetry = require(script.Parent.Parent.Controllers.Telemetry)
local SettingsClient = require(script.Parent.Parent.Controllers.SettingsClient)
local EnemyRenderer = require(script.Parent.Parent.Controllers.EnemyRenderer)
local StoryClient = require(script.Parent.Parent.Controllers.StoryClient)
local GuideClient = require(script.Parent.Parent.Controllers.GuideClient)
local GuideHud = require(script.Parent.GuideHud)
local NewsHud = require(script.Parent.NewsHud)
local CinemaClient = require(script.Parent.Parent.Controllers.CinemaClient)
local FinisherFx = require(script.Parent.Parent.Fx.FinisherFx)
local Players = game:GetService("Players")

local DevPanel = {}

function DevPanel.init()
	if not RunService:IsStudio() then
		return
	end
	local gui = Kit.screen("DevPanel", 20)
	local panel = Kit.frame({
		Size = UDim2.fromOffset(300, 885),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 60),
		BackgroundColor3 = Kit.color.night,
		BackgroundTransparency = 0.15,
		Visible = false,
	})
	panel.Parent = gui
	local toggle = Kit.button({
		Text = "DEV",
		Size = UDim2.fromOffset(64, 36),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
	}, function()
		panel.Visible = not panel.Visible
	end)
	toggle.Parent = gui

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(90, 30)
	grid.CellPadding = UDim2.fromOffset(5, 5)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	-- (lore step 7: a scrolling list now that the buttons outgrow the panel)
	local holder = Instance.new("ScrollingFrame")
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.ScrollBarThickness = 6
	holder.CanvasSize = UDim2.new()
	holder.AutomaticCanvasSize = Enum.AutomaticSize.Y
	holder.Size = UDim2.new(1, -8, 0, 750)
	holder.Position = UDim2.fromOffset(8, 8)
	grid.Parent = holder
	holder.Parent = panel

	local spawner, god, anime = false, false, false
	local function add(text: string, fn: (TextButton) -> ()): TextButton
		local b: TextButton
		b = Kit.button({ Text = text, maxText = 18 }, function()
			fn(b)
		end)
		b.LayoutOrder = #holder:GetChildren()
		b.Parent = holder
		return b
	end
	add("30 bots", function()
		Net.send("DevCommand", "bots", Config.Dev.loadBots.max)
	end)
	add("Clear bots", function()
		Net.send("DevCommand", "clearbots")
	end)
	add("5 drones", function()
		Net.send("DevCommand", "drones", 5)
	end)
	add("Clear drones", function()
		Net.send("DevCommand", "cleardrones")
	end)
	add("Spawner OFF", function(b)
		spawner = not spawner
		b.Text = if spawner then "Spawner ON" else "Spawner OFF"
		Net.send("DevCommand", "spawner", if spawner then 1 else 0)
	end)
	add("God OFF", function(b)
		god = not god
		b.Text = if god then "God ON" else "God OFF"
		Net.send("DevCommand", "god", if god then 1 else 0)
	end)
	-- every path in turn (its archetype comes with it), and every mobility
	local paths = {}
	for _, set in Config.Abilities.sets do
		if AbilityRules.pathReady(Config, set) then
			table.insert(paths, set)
		end
	end
	local pathIdx = table.find(paths, State.hero.startSet or "Volt") or 1
	add("Path: " .. (Config.Abilities.setName[paths[pathIdx]] or "?"), function(b)
		pathIdx = pathIdx % #paths + 1
		b.Text = "Path: " .. Config.Abilities.setName[paths[pathIdx]]
		Net.send("DevCommand", "class", table.find(Config.Abilities.sets, paths[pathIdx]) or 1)
	end)
	local mobIdx = 1
	add("Move: " .. Config.Move.mobility[Config.Move.mobilityOrder[1]].name, function(b)
		mobIdx = mobIdx % #Config.Move.mobilityOrder + 1
		b.Text = "Move: " .. Config.Move.mobility[Config.Move.mobilityOrder[mobIdx]].name
		Net.send("DevCommand", "mobility", mobIdx)
	end)
	add("Level +5", function()
		Net.send("DevCommand", "level", math.min(Config.Stats.levelCap, State.hero.level + 5))
	end)
	add("Style: Comic", function(b)
		anime = not anime
		b.Text = if anime then "Style: Anime" else "Style: Comic"
		Net.send("DevCommand", "style", if anime then 1 else 0)
	end)
	add("Heal", function()
		Net.send("DevCommand", "heal")
	end)
	-- cycles the robot types that are switched on (Config.Enemies.<Kind>.on), by their index in the order; the
	-- famous fakes and the twin have their own buttons below
	local function nextRobot(i: number): number
		local n = EnemySim.nextEnabled(Config, i)
		for _ = 1, #Config.Enemies.order do
			if not Config.Enemies[Config.Enemies.order[n]].fake then
				break
			end
			n = EnemySim.nextEnabled(Config, n)
		end
		return n
	end
	local robotIdx = nextRobot(0)
	add("3x " .. Config.Enemies[Config.Enemies.order[robotIdx]].name, function(b)
		Net.send("DevCommand", "robot", robotIdx)
		robotIdx = nextRobot(robotIdx)
		b.Text = "3x " .. Config.Enemies[Config.Enemies.order[robotIdx]].name
	end)
	-- lore step 4: each famous fake, and an evil twin of your own hero (25 studs in front, at your level)
	for i, kind in { "Radiant", "Bulwark", "Skylance" } do
		add("Fake: " .. Config.Enemies[kind].name, function()
			Net.send("DevCommand", "fake", i)
		end)
	end
	add("My evil twin", function()
		Net.send("DevCommand", "twin")
	end)
	-- lore step 9: the rare Your double world event on you now (Output says if the rare tier would pick you)
	add("Event: my double", function()
		Net.send("DevCommand", "double")
	end)
	-- lore step 12 (the city remembers): your own side's reputation tier, and each side-vs-side event now
	local repTier = 0
	add("Rep tier: set 1", function(b)
		repTier = repTier % 5 + 1
		Net.send("DevCommand", "reptier", repTier)
		b.Text = string.format("Rep tier: set %d (now %d)", repTier % 5 + 1, repTier)
	end)
	add("Rep tier: 0", function()
		repTier = 0
		Net.send("DevCommand", "reptier", 0)
	end)
	for i, id in Config.Events.side do
		add("Side event: " .. Config.Events.events[id].name, function()
			Net.send("DevCommand", "sideevent", i)
		end)
	end

	-- the robots' look, to compare the two styles live (nate, 2026-11-17): Auto, Roblox (classic clothes and
	-- catalog hair), Shell (the Blender superhero meshes), Plain
	local STYLES = { "auto", "roblox", "shell", "plain" }
	local styleIdx = table.find(STYLES, Config.NpcLooks.style) or 1
	local LABEL =
		{ auto = "Robots: Auto", roblox = "Robots: Roblox", shell = "Robots: Shell", plain = "Robots: Plain" }
	add(LABEL[STYLES[styleIdx]], function(b)
		styleIdx = styleIdx % #STYLES + 1
		b.Text = LABEL[EnemyRenderer.setStyle(STYLES[styleIdx])]
	end)
	add("Level " .. Config.Stats.levelCap, function()
		Net.send("DevCommand", "level", Config.Stats.levelCap)
	end)
	add("+10 Skill Pts", function()
		Net.send("DevCommand", "points", 10)
	end)
	add("Fill Awakening", function()
		Net.send("DevCommand", "meter")
	end)
	local lootIdx = 1
	add("Loot: " .. Config.Loot.order[1], function(b)
		Net.send("DevCommand", "loot", lootIdx)
		lootIdx = lootIdx % #Config.Loot.order + 1
		b.Text = "Loot: " .. Config.Loot.order[lootIdx]
	end)
	add("+500 Renown", function()
		Net.send("DevCommand", "renown", 500)
	end)
	add("+1000 Credits", function()
		Net.send("DevCommand", "credits", 1000)
	end)
	add("+500 Dust", function()
		Net.send("DevCommand", "dust", 500)
	end)
	add("Find all beacons", function()
		Net.send("DevCommand", "map")
	end)
	add("Wreck here", function()
		Net.send("DevCommand", "wreck", 3000)
	end)
	add("Repair city", function()
		Net.send("DevCommand", "repair")
	end)
	add("Flip cars", function()
		Net.send("DevCommand", "flip")
	end)
	add("Save now", function()
		Net.send("DevCommand", "save")
	end)
	add("Wipe profile", function()
		Net.send("DevCommand", "wipe")
	end)
	-- M6: world activity
	local incIdx = 1
	local incButton = add("Inc: " .. Config.Incidents.order[1], function(b)
		Net.send("DevCommand", "incident", incIdx)
		incIdx = incIdx % #Config.Incidents.order + 1
		b.Text = "Inc: " .. Config.Incidents.order[incIdx]
	end)
	add("Inc next", function()
		incIdx = incIdx % #Config.Incidents.order + 1
		incButton.Text = "Inc: " .. Config.Incidents.order[incIdx]
	end)
	add("Clear incidents", function()
		Net.send("DevCommand", "clearincidents")
	end)
	local evIdx = 1
	local evButton = add("Ev: " .. Config.Events.order[1], function(b)
		Net.send("DevCommand", "event", evIdx)
		evIdx = evIdx % #Config.Events.order + 1
		b.Text = "Ev: " .. Config.Events.order[evIdx]
	end)
	add("Ev next", function()
		evIdx = evIdx % #Config.Events.order + 1
		evButton.Text = "Ev: " .. Config.Events.order[evIdx]
	end)
	local conIdx = 1
	local conButton = add("Con: " .. Config.Contracts.order[1], function(b)
		Net.send("DevCommand", "contractstart", conIdx)
		conIdx = conIdx % #Config.Contracts.order + 1
		b.Text = "Con: " .. Config.Contracts.order[conIdx]
	end)
	add("Con next", function()
		conIdx = conIdx % #Config.Contracts.order + 1
		conButton.Text = "Con: " .. Config.Contracts.order[conIdx]
	end)
	local heroic = false
	add("Heroic OFF", function(b)
		heroic = not heroic
		b.Text = if heroic then "Heroic ON" else "Heroic OFF"
		Net.send("DevCommand", "heroic", if heroic then 1 else 0)
	end)
	add("Boss now", function()
		Net.send("DevCommand", "boss")
	end)
	add("Boss to 1 HP", function()
		Net.send("DevCommand", "bosskill")
	end)
	add("Finish contract", function()
		Net.send("DevCommand", "contract")
	end)
	local clockIdx = 0
	add("Clock: dusk", function(b)
		clockIdx = (clockIdx + 1) % 4
		Net.send("DevCommand", "clock", clockIdx)
		b.Text = "Clock: " .. ({ "day", "dusk", "night", "dawn" })[(clockIdx + 1) % 4 + 1]
	end)
	local villain = false
	add("Side: hero", function(b)
		villain = not villain
		b.Text = if villain then "Side: villain" else "Side: hero"
		Net.send("DevCommand", "side", if villain then 1 else 0)
	end)
	-- M7: the story
	-- lore step 3: the Ceremony prologue as either side, and a jump to each beat (tap again for the next)
	add("Prologue: Vigil", function()
		Net.send("DevCommand", "prologue", 0)
	end)
	add("Prologue: Syndicate", function()
		Net.send("DevCommand", "prologue", 1)
	end)
	local beat = 0
	add("Beat: ceremony", function(b)
		beat = beat % #OpeningPlan.STEPS + 1
		Net.send("DevCommand", "opening", beat)
		b.Text = "Beat: " .. OpeningPlan.STEPS[beat % #OpeningPlan.STEPS + 1]
	end)
	-- lore step 5: each Act 1 mission as each side (tap again for the next), and a jump to each of its stages
	local runs = {}
	for n = 2, #Config.Story.missions do
		table.insert(runs, { n, 0 })
		table.insert(runs, { n, 1 })
	end
	local runIdx = 1
	local function runName(i: number): string
		local r = runs[i]
		return string.format(
			"%s: %s",
			Config.Story.missions[r[1]].name,
			if r[2] == 1 then "Syndicate" else "Vigil"
		)
	end
	add(runName(1), function(b)
		local r = runs[runIdx]
		Net.send("DevCommand", "missionas", r[1] * 10 + r[2])
		runIdx = runIdx % #runs + 1
		b.Text = runName(runIdx)
	end)
	local stageIdx = 1
	add("Mission stage 1", function(b)
		Net.send("DevCommand", "missionstep", stageIdx)
		local m = StoryClient.mission
		local count = 1
		if (m.num or 0) > 0 then
			count = m.steps or 1
		end
		stageIdx = stageIdx % math.max(1, count) + 1
		b.Text = "Mission stage " .. stageIdx
	end)
	add("Finish step", function()
		Net.send("DevCommand", "finishstep")
	end)
	add("Leave mission", function()
		Net.send("DevCommand", "leavemission")
	end)
	-- lore step 6: a sample line per guide (tap again for the next speaker), and Lodestar beside you
	local guideIdx = 1
	local guides = Config.Story.guides.guides
	add("Guide: " .. guides[1], function(b)
		GuideHud.sample(guides[guideIdx])
		guideIdx = guideIdx % #guides + 1
		b.Text = "Guide: " .. guides[guideIdx]
	end)
	add("Spawn Lodestar", function()
		GuideClient.spawnLodestar()
	end)
	-- lore step 10: the side quest framework (the sample chain, steps, and every step kind alone)
	add("SQ: give sample chain", function()
		Net.send("DevCommand", "sidequest", 1)
	end)
	local sqStep = 1
	add("SQ: start step 1", function(b)
		Net.send("DevCommand", "sidequest", 100 + sqStep)
		sqStep = sqStep % Config.SideQuests.maxSteps + 1
		b.Text = "SQ: start step " .. sqStep
	end)
	-- lore step 11: start any real chain at step 1 (tap again for the next chain), then "SQ: start step" jumps
	-- through it
	local sqChains = {}
	for i, ch in Config.SideQuests.chains do
		if not ch.dev then
			table.insert(sqChains, i)
		end
	end
	if #sqChains > 0 then
		local chainIdx = 1
		local function chainName(n: number): string
			return Config.SideQuests.chains[sqChains[n]].name
		end
		add("SQ chain: " .. chainName(1), function(b)
			Net.send("DevCommand", "sidequest", 300 + sqChains[chainIdx])
			chainIdx = chainIdx % #sqChains + 1
			b.Text = "SQ chain: " .. chainName(chainIdx)
		end)
	end
	add("SQ: restart step", function()
		Net.send("DevCommand", "sidequest", 2)
	end)
	add("SQ: finish step", function()
		Net.send("DevCommand", "sidequest", 3)
	end)
	add("SQ: finish chain", function()
		Net.send("DevCommand", "sidequest", 4)
	end)
	add("SQ: forget sample", function()
		Net.send("DevCommand", "sidequest", 5)
	end)
	local kinds = Config.SideQuests.devKinds
	local kindIdx = 1
	add("SQ kind: " .. kinds[1].kind, function(b)
		Net.send("DevCommand", "sidequest", 200 + kindIdx)
		kindIdx = kindIdx % #kinds + 1
		b.Text = "SQ kind: " .. kinds[kindIdx].kind
	end)
	add("Act 1 done", function()
		Net.send("DevCommand", "actdone")
	end)
	add("Reset story", function()
		Net.send("DevCommand", "resetstory")
	end)
	-- M8: PvP and death
	local pvpOn = false
	add("Force PvP on", function(b)
		pvpOn = not pvpOn
		Net.send("DevCommand", "pvp", if pvpOn then 1 else 0)
		b.Text = if pvpOn then "Force PvP off" else "Force PvP on"
	end)
	add("Down me", function()
		Net.send("DevCommand", "downme")
	end)
	add("Go to the Crater", function()
		Net.send("DevCommand", "crater")
	end)
	add("Crater card", function()
		NewsHud.card("places", "crater")
	end)
	add("+200 Fame", function()
		Net.send("DevCommand", "fame", 5)
	end)
	-- M9: the creator, HQ, shops and Legacy
	add("Creator", function()
		Net.send("DevCommand", "creator")
	end)
	local street = false
	add("Street outfit: off", function(b)
		street = not street
		b.Text = if street then "Street outfit: on" else "Street outfit: off"
		Net.send("DevCommand", "street", if street then 1 else 0)
	end)
	add("Enter HQ", function()
		Net.send("DevCommand", "hq")
	end)
	local hqLevel = 1
	add("HQ level 1", function(b)
		hqLevel = hqLevel % 6 + 1
		b.Text = "HQ level " .. hqLevel
		Net.send("DevCommand", "hqlevel", hqLevel)
	end)
	add("Away 8 h", function()
		Net.send("DevCommand", "away", 8)
	end)
	add("All pieces", function()
		Net.send("DevCommand", "pieces")
	end)
	local keys = ShopRules.keys(Config)
	local buyIdx = 1
	add("Buy " .. keys[1], function(b)
		-- tap: grant the shown item with a fixed test receipt (a second tap grants nothing), then step on
		Net.send("DevCommand", "buy", buyIdx)
		buyIdx = buyIdx % #keys + 1
		b.Text = "Buy " .. keys[buyIdx]
	end)
	add("Level " .. Config.Stats.levelCap, function()
		Net.send("DevCommand", "legacy")
	end)
	-- Hero MMO
	add("Nemesis now", function()
		Net.send("DevCommand", "nemesis", 0)
	end)
	add("Nemesis Intel", function()
		Net.send("DevCommand", "nemesis", 1)
	end)
	-- WP1: the daily streak and quests
	add("Daily: next day", function()
		Net.send("DevCommand", "daily", 1)
	end)
	add("Daily: skip a day", function()
		Net.send("DevCommand", "daily", 2)
	end)
	add("Daily: finish quests", function()
		Net.send("DevCommand", "daily", 3)
	end)
	add("Daily: start over", function()
		Net.send("DevCommand", "daily", 4)
	end)
	-- M10: settings and accessibility
	add("Reset settings", function()
		for _, k in Config.Settings.keys do
			SettingsClient.set(k.id, k.default)
		end
	end)
	add("Text 160% / 100%", function()
		SettingsClient.set("textSize", if SettingsClient.get("textSize") >= 160 then 100 else 160)
	end)
	-- lore step 7: the cinematic layer (each piece has a button)
	add("Scene: city", function(b)
		local ok, why = CinemaClient.playScene("cityWatch")
		b.Text = if ok then "Scene: city" else "Scene waits: " .. tostring(why)
	end)
	add("Comic: last stand", function(b)
		local ok, why = CinemaClient.playScene("lastStand")
		b.Text = if ok then "Comic: last stand" else "Comic waits: " .. tostring(why)
	end)
	local newsKinds = { "boss", "boss down", "unmask", "streak", "heist", "act 1" }
	local newsIdx = 1
	add("News: boss", function(b)
		Net.send("DevCommand", "news", newsIdx)
		newsIdx = newsIdx % #newsKinds + 1
		b.Text = "News: " .. newsKinds[newsIdx]
	end)
	add("Crane on TV", function()
		NewsHud.crane()
	end)
	local cardIdx = 1
	local cardIds = table.clone(Config.Boss.order)
	table.insert(cardIds, "NullWarFrame")
	add("Name card", function()
		NewsHud.nameCard(cardIds[cardIdx])
		cardIdx = cardIdx % #cardIds + 1
	end)
	add("Finisher (mine)", function()
		local c = Players.LocalPlayer.Character
		local r = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
		if r then
			FinisherFx.play(
				"bossDead",
				r.Position + r.CFrame.LookVector * 12,
				Players.LocalPlayer.UserId,
				os.clock()
			)
		end
	end)
	add("Finisher (nearby)", function()
		local c = Players.LocalPlayer.Character
		local r = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
		if r then
			FinisherFx.play("bossPhase", r.Position + r.CFrame.LookVector * 30, 0, os.clock())
		end
	end)
	local motionNames = Config.Cinema.camera.options
	add("Camera: " .. motionNames[SettingsClient.get("cameraMotion") + 1], function(b)
		local v = (SettingsClient.get("cameraMotion") + 1) % #motionNames
		SettingsClient.set("cameraMotion", v)
		b.Text = "Camera: " .. motionNames[v + 1]
	end)

	add("Boards: test rows", function() -- WP2: 40 test heroes on every weekly board, you at #6
		Net.send("DevCommand", "boardrows")
	end)
	add("Boards: end week", function() -- WP2: roll the board week now (the claim runs)
		Net.send("DevCommand", "boardroll")
	end)

	local stats = Kit.label({
		Text = "waiting for server stats",
		Size = UDim2.new(1, -16, 0, 100),
		Position = UDim2.fromOffset(8, 763),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Kit.color.paper,
		TextScaled = false,
		TextSize = 13,
		TextWrapped = true,
		Font = Enum.Font.Code,
		maxText = 13,
	})
	stats.Parent = panel
	Net.listen("DevStats", function(r)
		local parts = {}
		for name, s in r.services do
			table.insert(parts, string.format("%s %.2f/%.2f", name, s.avg, s.worst))
		end
		table.sort(parts)
		stats.Text = string.format(
			"server frame %.1f ms (worst %.1f)\nscripts ms avg/worst: %s\nenemies %s  ai %s  bots %s  players %d\nsend %.0f kbps  mem %.0f MB\nclient %.0f fps  preset %s\nidle waits >5 s: server %s\nanalytics events %s  perf sample %s (%d/%d fps)\nserver script errors %s",
			r.frameMs,
			r.frameWorstMs,
			table.concat(parts, ", "),
			tostring(r.extra.enemies),
			tostring(r.extra.aiTicks),
			tostring(r.extra.bots),
			r.players,
			r.sendKbps,
			r.memoryMb,
			QualityController.fps,
			QualityController.name,
			tostring(r.extra["idle>5s"]),
			tostring(r.extra.analytics),
			if Telemetry.sampled then "on" else "off",
			Telemetry.lastMedian,
			Telemetry.lastP5,
			tostring(r.extra.errors)
		)
	end)
end

return DevPanel
