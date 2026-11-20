-- WorldHud: what the city is doing, on screen (spec: Screens and UI > HUD "incident tracker"; World boss
-- "shared bar"; Juice: boss banner, result card). Reads WorldClient.
-- * Tracker (right side): the 3 nearest incidents, accepted contracts (Shard recovery shows its radar) and
--   running events, each with a progress bar and the time left. An incident shows its current step's line
--   (Config.Incidents); a contract its radar and clock; anything Heroic (Config.Heroic) is tagged HEROIC in
--   the Heroic colour.
-- * Markers in the world: incidents (blue Vigil, red Syndicate) within 450 studs, events and the boss.
-- * Boss: a countdown banner from T minus 60 s, then the shared HP bar with the phase marks, the time left
--   and the hero's own tier and rank. The result card shows for 5 s (tap to close).
-- gap-icons2 (2026-11-19): every incident, event, contract and boss shows its comic symbol on its colorblind
-- shape (Kit.showMark: circle incident, star event, hex contract, diamond boss) on the markers, the tracker
-- rows, the boss bar and the result card; without the uploaded sheets they keep today's "!" and shapes.
-- PLACEHOLDER look until the UI pass (M10).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local IncidentPlan = require(Shared:WaitForChild("IncidentPlan"))
local ContractPlan = require(Shared:WaitForChild("ContractPlan"))
local BossRange = require(Shared:WaitForChild("BossRange"))
local TouchLayout = require(Shared:WaitForChild("TouchLayout"))

local Kit = require(script.Parent.Kit)
local Popups = require(script.Parent.Popups) -- pt-ui: one line for every popup
local Dismiss = require(script.Parent.Dismiss) -- fix-hud
local Shapes = require(script.Parent.Shapes)
local State = require(script.Parent.Parent.State)
local WorldClient = require(script.Parent.Parent.Controllers.WorldClient)

local WorldHud = {}
WorldHud.bossMode = "none" -- fix-hud: "bar" near the fight, "corner" (radar timer and marker only), "none"

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
local shownRows = MAX_ROWS -- the rows that fit this screen (Kit.hudBoxes)
local TIER_NAME =
	{ mvp = "MVP", contributor = "Contributor", participant = "Participant", floor = "Took part" }

local function sideColor(side: string): Color3
	return if side == "villain" then Kit.color.syndicate else Kit.color.vigil
end

local HC = Config.Heroic
local HEROIC_COLOR = Color3.fromRGB(HC.color[1], HC.color[2], HC.color[3])
local ready = ContractPlan.readyFor(Config)

-- "HEROIC " in front of a title when it is Heroic (fixed text)
local function heroicTitle(title: string, heroic: boolean?): string
	return if heroic then HC.tag .. " " .. title else title
end

local function enemyName(kind: string): string
	local e = Config.Enemies[kind]
	return e and e.name or kind
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
	-- gap-icons2: the row's symbol on its shape at the left (hidden with no icon; the texts then move back)
	local mark = Instance.new("Frame")
	mark.Name = "Mark"
	mark.BackgroundTransparency = 1
	mark.Size = UDim2.fromOffset(34, 34)
	mark.Position = UDim2.fromOffset(4, 2)
	mark.Parent = f
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

-- mark: { shape, group, key } of the row's symbol (Kit.showMark), or nil
local function setRow(f: Frame, title: string, sub: string, frac: number, color: Color3, mark: { any }?)
	f.Visible = true
	local holder = f:FindFirstChild("Mark") :: Frame
	local on = mark ~= nil and Kit.showMark(holder, mark[1], color, mark[2], mark[3])
	if not on then
		Kit.showMark(holder, "circle", color, nil, nil)
	end
	local x = if on then 42 else 6
	local t = f:FindFirstChild("Title") :: TextLabel
	t.Text = title
	t.TextColor3 = color
	t.Position = UDim2.fromOffset(x, 2)
	t.Size = UDim2.new(1, -(x + 6), 0, 20)
	local subLabel = f:FindFirstChild("Sub") :: TextLabel
	subLabel.Text = sub
	subLabel.Position = UDim2.fromOffset(x, 22)
	subLabel.Size = UDim2.new(1, -(x + 6), 0, 14)
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

-- fix-hud (nate, gaps7: "need a way to get rid of popups"): the tracker's X (or Backspace) folds it away until
-- something new joins it (a new event, contract or incident row)
local trackerHidden = false
local hiddenKeys: { [string]: boolean } = {}
local shownKeys: { [string]: boolean } = {}

local function refreshTracker()
	local now = os.clock()
	local pos = myPos()
	local n = 0
	table.clear(shownKeys)
	-- events first: they are server-wide
	for _, ev in WorldClient.events do
		if n < shownRows and ev.state == 0 and ev.id then
			n += 1
			shownKeys["e" .. tostring(ev.id) .. ":" .. tostring(ev.ends)] = true
			local def = Config.Events.events[ev.id]
			local villain = State.hero.side == "villain"
			local name = if villain and def.villainName then def.villainName else def.name
			local dist = if pos then math.floor((Vector3.new(ev.x, pos.Y, ev.z) - pos).Magnitude) else 0
			local score = string.format("%s / %s", tostring(ev.have), tostring(ev.need))
			if ev.defend then
				-- lore step 12: a side event shows both sides' scores (crystals, or % of the route, crack or clock)
				local unit = if def.goal == "shards" then "" else "%"
				score =
					string.format("VIGIL %d%s  SYNDICATE %d%s", ev.vigil or 0, unit, ev.syndicate or 0, unit)
			end
			setRow(
				rows[n],
				heroicTitle("EVENT: " .. string.upper(name), ev.heroic),
				string.format("%s   %s   %d studs", score, Kit.time(ev.ends - now), dist),
				if ev.need > 0 then ev.have / ev.need else 0,
				if ev.heroic then HEROIC_COLOR else Kit.color.gold,
				{ "star", "event", ev.id }
			)
		end
	end
	for _, c in WorldClient.contracts do
		if n < shownRows then
			n += 1
			shownKeys["c" .. tostring(c[1])] = true
			local id = WorldClient.contractByNum[c[1]]
			local def = id and Config.Contracts.types[id]
			local sub = string.format("%d / %d", c[2], c[3])
			if id == "Escort" then
				sub = string.format("%d%% of the route", math.floor(c[2] / math.max(1, c[3]) * 100))
			elseif id == "GeneratorHold" then
				sub = string.format("%d / %d s held", c[2], c[3])
			end
			if c[9] and c[9] > 0 then
				sub ..= string.format("   %s left", Kit.time(c[9]))
			end
			if c[4] and c[4] > 0 then
				sub ..= string.format(
					"   %s %d studs %s",
					if id == "ShardRecovery" then "core" else "next",
					c[4],
					compass(c[5], c[6])
				)
			end
			local title = "?"
			if def and id then
				title = ContractPlan.title(
					Config.Contracts,
					{ type = id, seed = 0, level = 1, got = 0, pick = c[8] },
					State.hero.side,
					enemyName,
					ready
				)
			end
			local heroic = c[7] == 1
			setRow(
				rows[n],
				heroicTitle("CONTRACT: " .. string.upper(title), heroic),
				sub,
				c[2] / math.max(1, c[3]),
				if heroic then HEROIC_COLOR else Color3.fromRGB(255, 150, 70),
				if id then { "hex", "contract", id } else nil
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
		if n < shownRows then
			n += 1
			local inc, d = list[i].inc, list[i].d
			shownKeys["i" .. tostring(inc.tid) .. ":" .. tostring(inc.deadline)] = true
			local name = IncidentPlan.title(IC, inc.tid, inc.side)
			local sub = string.format("%s   %d studs", Kit.time(inc.deadline - now), math.floor(d))
			local line = IncidentPlan.stepText(IC, inc.tid, inc.step, inc.side)
			if line ~= "" then
				sub = line .. "   " .. sub
			end
			if inc.steps > 1 then
				sub = string.format("%d/%d ", inc.step, inc.steps) .. sub
			end
			setRow(
				rows[n],
				heroicTitle(string.upper(name), inc.heroic),
				sub,
				inc.frac,
				if inc.heroic then HEROIC_COLOR else sideColor(inc.side),
				{ "circle", "incident", inc.tid }
			)
		end
	end
	for i = n + 1, MAX_ROWS do
		rows[i].Visible = false
	end
	if trackerHidden then
		for k in shownKeys do
			if not hiddenKeys[k] then
				trackerHidden = false -- something new: the tracker comes back
				break
			end
		end
	end
	tracker.Visible = not trackerHidden and n > 0 -- (an empty tracker shows nothing, its X neither)
end

function WorldHud.hideTracker()
	trackerHidden = true
	table.clear(hiddenKeys)
	for k in shownKeys do
		hiddenKeys[k] = true
	end
	tracker.Visible = false
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
	shape: string?,
	group: string?, -- gap-icons2: the symbol on the shape (Config.Icons group and key)
	symKey: any
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
		b.Size = UDim2.fromOffset(150, 58)
		b.StudsOffsetWorldSpace = Vector3.new(0, 14, 0)
		b.MaxDistance = maxDist
		local icon = Kit.label({
			Name = "Icon",
			Text = "!",
			Size = UDim2.fromOffset(36, 36),
			Position = UDim2.new(0.5, -18, 0, 0),
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
			Position = UDim2.fromOffset(0, 39),
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
	local marked = Shapes.apply(icon, shape or "circle", color, group, symKey) -- M10: colorblind-safe shapes
	if not marked and (shape == "diamond" or shape == "circle" or not shape) then
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
				string.format("%s  %dm", heroicTitle(name, inc.heroic), d),
				if inc.heroic then HEROIC_COLOR else sideColor(inc.side),
				IC.spawner.sendRadius,
				"circle",
				"incident",
				inc.tid
			)
		end
	end
	for num, ev in WorldClient.events do
		if ev.state == 0 and ev.id then
			local key = "e" .. num
			keep[key] = true
			local def = Config.Events.events[ev.id]
			local at = Vector3.new(ev.x, Config.City.ground.y + 2, ev.z)
			local b = marker(
				key,
				at,
				heroicTitle(string.upper(def.name), ev.heroic),
				if ev.heroic then HEROIC_COLOR else Kit.color.gold,
				3000,
				"star",
				"event",
				ev.id
			)
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
			"diamond",
			"marker",
			if Kit.iconCell("marker", s.id) then s.id else "boss"
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

-- the boss's marker symbol (its own, else the generic boss)
local function bossKey(id: string?): string
	return if id and Kit.iconCell("marker", id) then id else "boss"
end

local bossNear = false -- fix-hud: the bar showed last time (BossRange.hudNear's margin to leave)

local function refreshBoss()
	local s = WorldClient.boss
	local def = s.id and Config.Boss.bosses[s.id]
	local left = (s.at or 0) - (os.clock() - (s.received or os.clock()))
	-- fix-hud: the banner and the bar only near the fight or once you are on its list; else the radar's timer
	local pos = myPos()
	local mode = BossRange.hudNear(
		Config,
		s,
		pos and pos.X,
		pos and pos.Z,
		(WorldClient.mine.tier or "") ~= "",
		bossNear
	)
	bossNear = mode == "bar"
	WorldHud.bossMode = mode
	if mode ~= "bar" then
		banner.Visible = false
		bossPanel.Visible = false
		return
	end
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
		-- gap-icons2: the boss's own symbol on its diamond, a sticker on the panel's corner
		local sticker = bossPanel:FindFirstChild("BossMark") :: Frame
		local on = Kit.showMark(sticker, "diamond", Color3.fromRGB(255, 90, 60), "marker", bossKey(s.id))
		bossName.Position = UDim2.fromOffset(if on then 30 else 6, 2)
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

local function showResultNow(r: { [string]: any })
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
	-- gap-icons2: the boss's symbol on its diamond, a big sticker on the card's corner
	local sticker = Instance.new("Frame")
	sticker.Name = "BossMark"
	sticker.BackgroundTransparency = 1
	sticker.Size = UDim2.fromOffset(58, 58)
	sticker.Position = UDim2.fromOffset(-34, -34)
	sticker.ZIndex = 3
	sticker.Parent = card
	Kit.showMark(
		sticker,
		"diamond",
		if r.defeated then Kit.color.gold else Color3.fromRGB(255, 90, 60),
		"marker",
		bossKey(id)
	)
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
			Kit.payLine(r.credits or 0, r.renown or 0, 1),
			Kit.color.gold,
			20,
			true, -- counts up
		},
	}
	if r.bounty then
		-- the week's bounty boss (list-combat 2026-11-20): paid twice over plus Dust, once a week
		table.insert(lines, {
			string.format(
				"WEEKLY BOUNTY! x%d pay + %d Dust",
				Config.Boss.bounty.mult,
				Config.Boss.bounty.dust
			),
			Color3.fromRGB(255, 170, 60),
			20,
		})
	end
	if (r.drops or 0) > 0 then
		table.insert(
			lines,
			{ string.format("%d gear drop%s", r.drops, if r.drops > 1 then "s" else ""), Kit.color.volt, 18 }
		)
	end
	if (r.style or 0) > 0 then
		table.insert(lines, {
			if r.shiny then "SHINY BOSS STYLE UNLOCKED!" else "Boss style unlocked! (GEAR > STYLES)",
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
	local finish: (() -> boolean)? = nil
	for _, row in lines do
		local l = Kit.label({
			Text = row[1],
			Size = UDim2.new(1, -24, 0, row[3] + 6),
			Position = UDim2.fromOffset(12, y),
			TextColor3 = row[2],
			maxText = row[3],
		})
		l.Parent = card
		if row[4] then
			finish = Kit.countUp(l, 1.5, function(k)
				return Kit.payLine(r.credits or 0, r.renown or 0, k)
			end)
		end
		y += row[3] + 12
	end
	-- item 247: the card is as tall as its lines and sits under the top row of buttons, shrunk on a phone
	local cardH = y + 4
	card.Size = UDim2.fromOffset(380, cardH)
	local fit = Instance.new("UIScale")
	fit.Parent = card
	local function place()
		local a = Kit.area()
		local k, top = TouchLayout.cardBelowRow(Config, a.X, a.Y, 380, cardH)
		fit.Scale = k
		card.AnchorPoint = Vector2.new(0.5, 0)
		card.Position = UDim2.new(0.5, 0, 0, top)
	end
	place()
	local relayout = Kit.LayoutChanged:Connect(place)
	card.Destroying:Connect(function()
		relayout:Disconnect()
	end)
	local tap = Instance.new("TextButton")
	tap.BackgroundTransparency = 1
	tap.Text = ""
	tap.Size = UDim2.fromScale(1, 1)
	tap.Parent = card
	tap.Activated:Connect(function()
		-- the first tap finishes the count, the next closes the card
		if not (finish and finish()) then
			closeResult()
		end
	end)
	card.Parent = gui
	Kit.pulse(card, 0.2)
	resultCard = card
	task.delay(5, function()
		if resultCard == card then
			closeResult()
		end
	end)
end

-- pt-ui: the boss result card waits its turn (Ui.Popups "bossResult": never over another card, after a fight)
local function showResult(r: { [string]: any })
	-- fix-hud: Settings "Popups: Important only" shows this one line instead (the outcome and the pay)
	Popups.brief("bossResult", function()
		local id = WorldClient.bossByNum[r.num]
		local def = id and Config.Boss.bosses[id]
		return string.format(
			"%s %s  %s",
			string.upper(if def then def.name else "Boss"),
			if r.defeated then "DEFEATED!" else "RETREATED",
			Kit.payLine(r.credits or 0, r.renown or 0, 1)
		)
	end)
	Popups.show("bossResult", function()
		showResultNow(r)
		return resultCard
	end, function()
		return resultCard ~= nil
	end, closeResult)
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
	tracker.Visible = false -- (until a row shows: an empty tracker draws nothing, its X neither)
	tracker.Parent = gui
	for i = 1, MAX_ROWS do
		rows[i] = makeRow(i)
	end
	-- phone pass: the tracker's box and how many rows fit come from the HUD plan (on a phone, 2 rows in the
	-- top-left corner; elsewhere the rows that fit above the action buttons)
	local function place()
		local hb = Kit.hudBoxes()
		local t = hb.tracker
		tracker.AnchorPoint = Vector2.zero
		tracker.Position = UDim2.fromOffset(t.x, t.y)
		tracker.Size = UDim2.fromOffset(t.w, math.max(t.h, 0))
		shownRows = math.clamp(hb.trackerRows, 0, MAX_ROWS)
		for i = shownRows + 1, MAX_ROWS do
			rows[i].Visible = false
		end
	end
	place()
	Kit.LayoutChanged:Connect(place)
	-- fix-hud: the tracker's X (no tap-anywhere: its box is mostly clear screen)
	Dismiss.attach(tracker, WorldHud.hideTracker, { thin = true, tap = false })

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
	local sticker = Instance.new("Frame")
	sticker.Name = "BossMark"
	sticker.BackgroundTransparency = 1
	sticker.Size = UDim2.fromOffset(34, 34)
	sticker.Position = UDim2.fromOffset(-10, -12)
	sticker.ZIndex = 3
	sticker.Parent = bossPanel
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
	RunService.Heartbeat:Connect(FrameProf.wrap("WorldHud", function(dt)
		acc += dt
		if acc < 0.25 then
			return
		end
		acc = 0
		refreshTracker()
		refreshMarkers()
		refreshBoss()
	end))
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
