-- DevPanel: Studio-only test buttons and the server frame report (spec: Performance budgets). Never built
-- in a live game. Buttons: 30 load bots, clear bots, 5 drones, clear drones, spawner, god, class, level,
-- Comic/Anime style, robots, levels, skill points, Awakening, loot by source, Renown, Credits, Dust, save,
-- wipe. The stats line shows the server frame, script time per service, enemies, bots, send
-- rate and memory, plus the client fps and preset.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local Kit = require(script.Parent.Kit)
local State = require(script.Parent.Parent.State)
local QualityController = require(script.Parent.Parent.Controllers.QualityController)

local DevPanel = {}

function DevPanel.init()
	if not RunService:IsStudio() then
		return
	end
	local gui = Kit.screen("DevPanel", 20)
	local panel = Kit.frame({
		Size = UDim2.fromOffset(300, 590),
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
	grid.CellSize = UDim2.fromOffset(136, 34)
	grid.CellPadding = UDim2.fromOffset(8, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, -16, 0, 470)
	holder.Position = UDim2.fromOffset(8, 8)
	grid.Parent = holder
	holder.Parent = panel

	local spawner, god, classIdx, anime =
		true, false, table.find(Config.Classes.order, Config.Classes.default) or 1, false
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
	add("Spawner ON", function(b)
		spawner = not spawner
		b.Text = if spawner then "Spawner ON" else "Spawner OFF"
		Net.send("DevCommand", "spawner", if spawner then 1 else 0)
	end)
	add("God OFF", function(b)
		god = not god
		b.Text = if god then "God ON" else "God OFF"
		Net.send("DevCommand", "god", if god then 1 else 0)
	end)
	add("Class: " .. Config.Classes.order[classIdx], function(b)
		classIdx = classIdx % #Config.Classes.order + 1
		b.Text = "Class: " .. Config.Classes.order[classIdx]
		Net.send("DevCommand", "class", classIdx)
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
	add("Save now", function()
		Net.send("DevCommand", "save")
	end)
	add("Wipe profile", function()
		Net.send("DevCommand", "wipe")
	end)

	local stats = Kit.label({
		Text = "waiting for server stats",
		Size = UDim2.new(1, -16, 0, 100),
		Position = UDim2.fromOffset(8, 482),
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
			"server frame %.1f ms (worst %.1f)\nscripts ms avg/worst: %s\nenemies %s  ai %s  bots %s  players %d\nsend %.0f kbps  mem %.0f MB\nclient %.0f fps  preset %s",
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
			QualityController.name
		)
	end)
end

return DevPanel
