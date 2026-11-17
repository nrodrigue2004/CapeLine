-- DevPanel: Studio-only test buttons and the server frame report (spec: Performance budgets). Never built
-- in a live game. Buttons: 30 load bots, clear bots, 5 drones, clear drones, spawner, god, class, level,
-- Comic/Anime style, robots, levels, skill points, Awakening, loot by source, Renown, Credits, Dust, find all
-- beacons, wreck here, repair city, flip cars, save, wipe, and (M6) incident by template, clear incidents,
-- event by type, boss now, boss to 1 HP, finish contract, clock phase, hero or villain side, and (M7) replay
-- the opening, jump to an opening step, enter a mission, finish the step, leave, start a side quest, clear
-- Act 1 and reset the story, and (M9) the creator, enter HQ, HQ level, 8 h away, all pieces, a test buy
-- (twice grants once) and level 40. The stats line shows the server frame, script time per service, enemies, bots, send
-- rate and memory, plus the client fps and preset.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local AbilityRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AbilityRules"))
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local ShopRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ShopRules"))

local Kit = require(script.Parent.Kit)
local State = require(script.Parent.Parent.State)
local QualityController = require(script.Parent.Parent.Controllers.QualityController)
local Telemetry = require(script.Parent.Parent.Controllers.Telemetry)
local SettingsClient = require(script.Parent.Parent.Controllers.SettingsClient)
local EnemyRenderer = require(script.Parent.Parent.Controllers.EnemyRenderer)

local DevPanel = {}

function DevPanel.init()
	if not RunService:IsStudio() then
		return
	end
	local gui = Kit.screen("DevPanel", 20)
	local panel = Kit.frame({
		Size = UDim2.fromOffset(300, 815),
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
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, -16, 0, 680)
	holder.Position = UDim2.fromOffset(8, 8)
	grid.Parent = holder
	holder.Parent = panel

	local spawner, god, anime = false, false, false
	local function add(text: string, fn: (TextButton) -> ())
		local b: TextButton
		b = Kit.button({ Text = text, maxText = 18 }, function()
			fn(b)
		end)
		b.LayoutOrder = #holder:GetChildren()
		b.Parent = holder
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
	local robotIdx = 1
	add("3x " .. Config.Enemies[Config.Enemies.order[1]].name, function(b)
		Net.send("DevCommand", "robot", robotIdx)
		robotIdx = robotIdx % #Config.Enemies.order + 1
		b.Text = "3x " .. Config.Enemies[Config.Enemies.order[robotIdx]].name
	end)
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
	add("Level 40", function()
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
	add("Inc: " .. Config.Incidents.order[1], function(b)
		Net.send("DevCommand", "incident", incIdx)
		incIdx = incIdx % #Config.Incidents.order + 1
		b.Text = "Inc: " .. Config.Incidents.order[incIdx]
	end)
	add("Clear incidents", function()
		Net.send("DevCommand", "clearincidents")
	end)
	local evIdx = 1
	add("Ev: " .. Config.Events.order[1], function(b)
		Net.send("DevCommand", "event", evIdx)
		evIdx = evIdx % #Config.Events.order + 1
		b.Text = "Ev: " .. Config.Events.order[evIdx]
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
	add("Opening", function()
		Net.send("DevCommand", "opening", 0)
	end)
	local openStep = 1
	add("Open step: leap", function(b)
		openStep = openStep % 9 + 1
		local names = { "leap", "glide", "catch", "blast", "choice", "save", "grab", "suitup", "flight" }
		b.Text = "Open step: " .. names[openStep]
		Net.send("DevCommand", "opening", openStep)
	end)
	local missionIdx = 2
	add("Mission 2", function(b)
		Net.send("DevCommand", "mission", missionIdx)
		missionIdx = missionIdx % 6 + 1
		missionIdx = math.max(2, missionIdx)
		b.Text = "Mission " .. missionIdx
	end)
	add("Finish step", function()
		Net.send("DevCommand", "finishstep")
	end)
	add("Leave mission", function()
		Net.send("DevCommand", "leavemission")
	end)
	local questIdx = 1
	add("Quest: " .. Config.Story.quests[1].id, function(b)
		Net.send("DevCommand", "quest", questIdx)
		questIdx = questIdx % #Config.Story.quests + 1
		b.Text = "Quest: " .. Config.Story.quests[questIdx].id
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
	add("+200 Fame", function()
		Net.send("DevCommand", "fame", 5)
	end)
	-- M9: the creator, HQ, shops and Legacy
	add("Creator", function()
		Net.send("DevCommand", "creator")
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
	add("Level 40", function()
		Net.send("DevCommand", "legacy")
	end)
	-- Hero MMO
	add("Nemesis now", function()
		Net.send("DevCommand", "nemesis", 0)
	end)
	add("Nemesis Intel", function()
		Net.send("DevCommand", "nemesis", 1)
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

	local stats = Kit.label({
		Text = "waiting for server stats",
		Size = UDim2.new(1, -16, 0, 100),
		Position = UDim2.fromOffset(8, 693),
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
