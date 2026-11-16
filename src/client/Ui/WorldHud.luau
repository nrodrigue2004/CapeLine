-- WorldHud: what the city is doing, on screen (spec: Screens and UI > HUD "incident tracker"; World boss
-- "shared bar"; Juice: boss banner, result card). Reads WorldClient.
-- * Tracker (right side): the 3 nearest incidents, accepted contracts (Shard recovery shows its radar) and
--   running events, each with a progress bar and the time left.
-- * Markers in the world: incidents (blue League, red Syndicate) within 450 studs, events and the boss.
-- * Boss: a countdown banner from T minus 60 s, then the shared HP bar with the phase marks, the time left
--   and the hero's own tier and rank. The result card shows for 5 s (tap to close).
-- PLACEHOLDER look until the UI pass (M10).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local IncidentPlan = require(Shared:WaitForChild("IncidentPlan"))

local Kit = require(script.Parent.Kit)
local Shapes = require(script.Parent.Shapes)
local State = require(script.Parent.Parent.State)
local WorldClient = require(script.Parent.Parent.Controllers.WorldClient)

local WorldHud = {}

local U = Config.Ui
local IC = Config.Incidents
local gui: ScreenGui
local tracker: Frame
local rows: { Frame } = {}
local bossPanel: Frame
local bossName: TextLabel
local bossFill: Frame
local bossText: TextLabel
local bossMine: TextLabel
local banner: TextLabel
local markerFolder: Folder
local markers: { [string]: BillboardGui } = {}
local resultCard: Frame? = nil

local MAX_ROWS = 6
local TIER_NAME =
	{ mvp = "MVP", contributor = "Contributor", participant = "Participant", floor = "Took part" }

local function sideColor(side: string): Color3
	return if side == "villain" then Kit.color.syndicate else Kit.color.league
end

local function myPos(): Vector3?
	local char = Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root and root.Position
end

---------------------------------------------------------------------------
-- Tracker
---------------------------------------------------------------------------

local function makeRow(i: number): Frame
	local f = Kit.frame({
		Name = "Row" .. i,
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = Kit.color.night,
		BackgroundTransparency = 0.25,
		LayoutOrder = i,
		Visible = false,
	})
	Kit.round(f, 8)
	local title = Kit.label({
		Name = "Title",
		Size = UDim2.new(1, -12, 0, 20),
		Position = UDim2.fromOffset(6, 2),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.paper,
		maxText = 18,
	})
	title.Parent = f
	local sub = Kit.label({
		Name = "Sub",
		Size = UDim2.new(1, -12, 0, 14),
		Position = UDim2.fromOffset(6, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.muted,
		Font = Kit.bodyFont,
		maxText = 12,
	})
	sub.Parent = f
	local bar = Kit.frame({
		Name = "Bar",
		Size = UDim2.new(1, -12, 0, 5),
		Position = UDim2.new(0, 6, 1, -8),
		BackgroundColor3 = Kit.color.ink,
	})
	bar.Parent = f
	local fill = Kit.frame({ Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = Kit.color.gold })
	fill.Parent = bar
	f.Parent = tracker
	return f
end

local function setRow(f: Frame, title: string, sub: string, frac: number, color: Color3)
	f.Visible = true
	local t = f:FindFirstChild("Title") :: TextLabel
	t.Text = title
	t.TextColor3 = color
	local subLabel = f:FindFirstChild("Sub") :: TextLabel
	subLabel.Text = sub
	local fill = (f:FindFirstChild("Bar") :: Frame):FindFirstChild("Fill") :: Frame
	fill.Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1)
	fill.BackgroundColor3 = color
end

-- An arrow for the radar: "N", "NE" and so on from a direction (x, z; north is -z)
local function compass(dx: number, dz: number): string
	if dx == 0 and dz == 0 then
		return ""
	end
	local names = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
	local a = math.atan2(dx, -dz) -- 0 = north, clockwise
	local i = math.floor((a / (math.pi * 2) * 8 + 0.5)) % 8 + 1
	return names[i]
end

local function refreshTracker()
	local now = os.clock()
	local pos = myPos()
	local n = 0
	-- events first: they are server-wide
	for _, ev in WorldClient.events do
		if n < MAX_ROWS and ev.state == 0 and ev.id then
			n += 1
			local def = Config.Events.events[ev.id]
			local villain = State.hero.side == "villain"
			local name = if villain and def.villainName then def.villainName else def.name
			local dist = if pos then math.floor((Vector3.new(ev.x, pos.Y, ev.z) - pos).Magnitude) else 0
			setRow(
				rows[n],
				"EVENT: " .. string.upper(name),
				string.format(
					"%s / %s   %s   %d studs",
					tostring(ev.have),
					tostring(ev.need),
					Kit.time(ev.ends - now),
					dist
				),
				if ev.need > 0 then ev.have / ev.need else 0,
				Kit.color.gold
			)
		end
	end
	for _, c in WorldClient.contracts do
		if n < MAX_ROWS then
			n += 1
			local id = WorldClient.contractByNum[c[1]]
			local def = id and Config.Contracts.types[id]
			local sub = string.format("%d / %d", c[2], c[3])
			if id == "Escort" then
				sub = string.format("%d%% of the route", math.floor(c[2] / math.max(1, c[3]) * 100))
			end
			if c[4] and c[4] > 0 then
				sub ..= string.format("   shard %d studs %s", c[4], compass(c[5], c[6]))
			end
			setRow(
				rows[n],
				"CONTRACT: " .. string.upper(if def then def.name else "?"),
				sub,
				c[2] / math.max(1, c[3]),
				Color3.fromRGB(255, 150, 70)
			)
		end
	end
	-- the nearest active incidents
	local list = {}
	for _, inc in WorldClient.incidents do
		if inc.state == WorldClient.ACTIVE and inc.tid then
			local d = if pos then (inc.pos - pos).Magnitude else 0
			table.insert(list, { inc = inc, d = d })
		end
	end
	table.sort(list, function(a, b)
		if a.inc.own ~= b.inc.own then
			return a.inc.own
		end
		return a.d < b.d
	end)
	for i = 1, math.min(3, #list) do
		if n < MAX_ROWS then
			n += 1
			local inc, d = list[i].inc, list[i].d
			local name = IncidentPlan.title(IC, inc.tid, inc.side)
			local sub = string.format("%s   %d studs", Kit.time(inc.deadline - now), math.floor(d))
			if inc.steps > 1 then
				sub = string.format("Step %d/%d   ", inc.step, inc.steps) .. sub
			end
			setRow(rows[n], string.upper(name), sub, inc.frac, sideColor(inc.side))
		end
	end
	for i = n + 1, MAX_ROWS do
		rows[i].Visible = false
	end
end

---------------------------------------------------------------------------
-- Markers in the world
---------------------------------------------------------------------------

local function marker(
	key: string,
	pos: Vector3,
	text: string,
	color: Color3,
	maxDist: number,
	shape: string?
): BillboardGui
	local b = markers[key]
	if not b then
		local anchor = Instance.new("Part")
		anchor.Name = key
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.one
		anchor.Parent = markerFolder
		b = Instance.new("BillboardGui")
		b.Name = "Marker"
		b.AlwaysOnTop = true
		b.LightInfluence = 0
		b.Size = UDim2.fromOffset(150, 46)
		b.StudsOffsetWorldSpace = Vector3.new(0, 14, 0)
		b.MaxDistance = maxDist
		local icon = Kit.label({
			Name = "Icon",
			Text = "!",
			Size = UDim2.fromOffset(26, 26),
			Position = UDim2.new(0.5, -13, 0, 0),
			BackgroundTransparency = 0,
			BackgroundColor3 = color,
			TextColor3 = Kit.color.paper,
			maxText = 22,
		})
		Kit.round(icon, 13)
		Kit.stroke(icon, Kit.color.ink, 2)
		icon.Parent = b
		local l = Kit.label({
			Name = "Text",
			Size = UDim2.new(1, 0, 0, 18),
			Position = UDim2.fromOffset(0, 27),
			TextColor3 = Kit.color.paper,
			TextStrokeTransparency = 0.2,
			Font = Kit.bodyFont,
			maxText = 12,
		})
		l.Parent = b
		b.Adornee = anchor
		b.Parent = anchor
		markers[key] = b
	end
	local anchor = b.Adornee :: BasePart
	anchor.CFrame = CFrame.new(pos)
	local textLabel = b:FindFirstChild("Text") :: TextLabel
	textLabel.Text = text
	local icon = b:FindFirstChild("Icon") :: TextLabel
	Shapes.apply(icon, shape or "circle", color) -- M10: colorblind-safe shapes
	if shape == "diamond" or shape == "circle" or not shape then
		icon.Text = "!"
	end
	return b
end

local function refreshMarkers()
	local pos = myPos()
	local keep = {}
	for id, inc in WorldClient.incidents do
		if inc.state == WorldClient.ACTIVE and inc.tid then
			local key = "i" .. id
			keep[key] = true
			local d = if pos then math.floor((inc.pos - pos).Magnitude) else 0
			local name = IncidentPlan.title(IC, inc.tid, inc.side)
			marker(
				key,
				inc.pos,
				string.format("%s  %dm", name, d),
				sideColor(inc.side),
				IC.spawner.sendRadius
			)
		end
	end
	for num, ev in WorldClient.events do
		if ev.state == 0 and ev.id then
			local key = "e" .. num
			keep[key] = true
			local def = Config.Events.events[ev.id]
			local at = Vector3.new(ev.x, Config.City.ground.y + 2, ev.z)
			local b = marker(key, at, string.upper(def.name), Kit.color.gold, 3000, "star")
			b.StudsOffsetWorldSpace = Vector3.new(0, 30, 0)
		end
	end
	local s = WorldClient.boss
	if (s.state == 1 or s.state == 2 or s.state == 3) and s.id then
		keep.boss = true
		local def = Config.Boss.bosses[s.id]
		local b = marker(
			"boss",
			Vector3.new(s.x, s.y, s.z),
			string.upper(def.name),
			Color3.fromRGB(255, 90, 60),
			5000,
			"diamond"
		)
		b.StudsOffsetWorldSpace = Vector3.new(0, def.height + 12, 0)
	end
	for key, b in markers do
		if not keep[key] then
			(b.Adornee :: Instance):Destroy()
			markers[key] = nil
		end
	end
end

---------------------------------------------------------------------------
-- The world boss
---------------------------------------------------------------------------

local function refreshBoss()
	local s = WorldClient.boss
	local def = s.id and Config.Boss.bosses[s.id]
	local left = (s.at or 0) - (os.clock() - (s.received or os.clock()))
	if s.state == 1 and def then
		banner.Visible = true
		banner.Text = string.format("WORLD BOSS: %s arrives in %s!", string.upper(def.name), Kit.time(left))
		bossPanel.Visible = false
		return
	end
	banner.Visible = false
	if (s.state == 2 or s.state == 3) and def then
		bossPanel.Visible = true
		bossName.Text = string.upper(def.name) .. string.format("   LV %d", s.level or 1)
		local share = if (s.max or 0) > 0 then s.hp / s.max else 1
		bossFill.Size = UDim2.fromScale(math.clamp(share, 0, 1), 1)
		local objectives = s.objectives or {}
		local standing = 0
		for _, v in objectives do
			if v > 0 then
				standing += 1
			end
		end
		local objName = if def.objectives.kind == "cannon" then "cannons" else "generators"
		if s.state == 2 then
			bossText.Text = "IT'S LANDING!"
		else
			bossText.Text = string.format(
				"%s / %s   phase %d   %s   %d %s up",
				Kit.comma(s.hp or 0),
				Kit.comma(s.max or 0),
				s.phase or 1,
				Kit.time(left),
				standing,
				objName
			)
		end
		local m = WorldClient.mine
		if m.tier ~= "" then
			bossMine.Text =
				string.format("YOU: %s   #%d of %d", TIER_NAME[m.tier] or m.tier, m.rank, m.heroes)
		else
			bossMine.Text = "Hit it, break its " .. objName .. ", heal or rescue to take part"
		end
	else
		bossPanel.Visible = false
	end
end

local function closeResult()
	if resultCard then
		resultCard:Destroy()
		resultCard = nil
	end
end

local function showResult(r: { [string]: any })
	closeResult()
	local id = WorldClient.bossByNum[r.num]
	local def = id and Config.Boss.bosses[id]
	local card = Kit.frame({
		Name = "BossResult",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(380, 250),
		BackgroundColor3 = Kit.color.night,
		BackgroundTransparency = 0.05,
	})
	Kit.stroke(card, if r.defeated then Kit.color.gold else Kit.color.muted, 3)
	local lines = {
		{
			string.format(
				"%s %s",
				string.upper(if def then def.name else "Boss"),
				if r.defeated then "DEFEATED!" else "RETREATED"
			),
			if r.defeated then Kit.color.gold else Kit.color.paper,
			30,
		},
		{
			string.format("%s   #%d", TIER_NAME[r.tier] or "", r.rank or 0),
			Kit.color.paper,
			22,
		},
		{
			string.format("+%s CREDITS   +%s RENOWN", Kit.comma(r.credits or 0), Kit.comma(r.renown or 0)),
			Kit.color.gold,
			20,
		},
	}
	if (r.drops or 0) > 0 then
		table.insert(
			lines,
			{ string.format("%d gear drop%s", r.drops, if r.drops > 1 then "s" else ""), Kit.color.volt, 18 }
		)
	end
	if (r.style or 0) > 0 then
		table.insert(lines, {
			if r.shiny then "SHINY BOSS STYLE UNLOCKED!" else "Boss style unlocked! (GEAR > Styles)",
			Color3.fromRGB(255, 120, 220),
			20,
		})
	end
	if r.mvps and #r.mvps > 0 then
		table.insert(lines, { "MVP: " .. table.concat(r.mvps, ", "), Kit.color.muted, 15 })
	end
	if not r.defeated then
		table.insert(lines, { "It got away: a small Credits consolation only", Kit.color.muted, 15 })
	end
	local y = 14
	for _, row in lines do
		local l = Kit.label({
			Text = row[1],
			Size = UDim2.new(1, -24, 0, row[3] + 6),
			Position = UDim2.fromOffset(12, y),
			TextColor3 = row[2],
			maxText = row[3],
		})
		l.Parent = card
		y += row[3] + 12
	end
	local tap = Instance.new("TextButton")
	tap.BackgroundTransparency = 1
	tap.Text = ""
	tap.Size = UDim2.fromScale(1, 1)
	tap.Parent = card
	tap.Activated:Connect(closeResult)
	card.Parent = gui
	Kit.pulse(card, 0.2)
	resultCard = card
	task.delay(5, function()
		if resultCard == card then
			closeResult()
		end
	end)
end

---------------------------------------------------------------------------

function WorldHud.init()
	gui = Kit.screen("WorldHud", 3)
	tracker = Instance.new("Frame")
	tracker.Name = "Tracker"
	tracker.BackgroundTransparency = 1
	tracker.AnchorPoint = Vector2.new(1, 0)
	tracker.Position = UDim2.new(1, -U.safe, 0, U.safe + U.touchTarget + 30)
	tracker.Size = UDim2.fromOffset(250, 6 * 52)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = tracker
	tracker.Parent = gui
	for i = 1, MAX_ROWS do
		rows[i] = makeRow(i)
	end

	bossPanel = Kit.frame({
		Name = "Boss",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.new(0.5, 0, 0, 62),
		BackgroundColor3 = Kit.color.night,
		BackgroundTransparency = 0.2,
		Visible = false,
	})
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(300, 62)
	limit.MaxSize = Vector2.new(560, 62)
	limit.Parent = bossPanel
	bossName = Kit.label({
		Size = UDim2.new(1, -12, 0, 18),
		Position = UDim2.fromOffset(6, 2),
		TextColor3 = Color3.fromRGB(255, 120, 90),
		maxText = 18,
	})
	bossName.Parent = bossPanel
	local bar = Kit.frame({
		Size = UDim2.new(1, -12, 0, 12),
		Position = UDim2.fromOffset(6, 22),
		BackgroundColor3 = Kit.color.ink,
	})
	bar.Parent = bossPanel
	bossFill = Kit.frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(235, 70, 60) })
	bossFill.Parent = bar
	for _, mark in Config.Boss.phases do
		local tick = Kit.frame({
			Size = UDim2.new(0, 2, 1, 4),
			Position = UDim2.new(mark, -1, 0, -2),
			BackgroundColor3 = Kit.color.paper,
			round = false,
		})
		tick.Parent = bar
	end
	bossText = Kit.label({
		Size = UDim2.new(1, -12, 0, 12),
		Position = UDim2.fromOffset(6, 36),
		TextColor3 = Kit.color.paper,
		Font = Kit.bodyFont,
		maxText = 11,
	})
	bossText.Parent = bossPanel
	bossMine = Kit.label({
		Size = UDim2.new(1, -12, 0, 12),
		Position = UDim2.fromOffset(6, 48),
		TextColor3 = Kit.color.gold,
		Font = Kit.bodyFont,
		maxText = 11,
	})
	bossMine.Parent = bossPanel
	bossPanel.Parent = gui

	banner = Kit.label({
		Name = "BossBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(0.6, 0, 0, 40),
		BackgroundTransparency = 0.15,
		BackgroundColor3 = Color3.fromRGB(120, 20, 20),
		TextColor3 = Kit.color.gold,
		TextStrokeTransparency = 0.3,
		Visible = false,
		maxText = 26,
	})
	Kit.round(banner, 8)
	banner.Parent = gui

	markerFolder = Instance.new("Folder")
	markerFolder.Name = "WorldMarkers"
	markerFolder.Parent = workspace

	WorldClient.BossResult:Connect(showResult)
	WorldClient.IncidentEnded:Connect(function(inc)
		-- a flash on the tracker when a nearby incident clears
		if inc.state == WorldClient.DONE then
			Kit.pulse(tracker, 0.05)
		end
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.25 then
			return
		end
		acc = 0
		refreshTracker()
		refreshMarkers()
		refreshBoss()
	end)
	-- the banner throbs while it counts down
	task.spawn(function()
		while true do
			task.wait(1)
			if banner.Visible then
				TweenService:Create(banner, TweenInfo.new(0.5), { BackgroundTransparency = 0.45 }):Play()
				task.wait(0.5)
				TweenService:Create(banner, TweenInfo.new(0.5), { BackgroundTransparency = 0.15 }):Play()
			end
		end
	end)
end

return WorldHud
