-- TestLab: the Dev panel's one-stop test page (nate, 2026-11-21: "Need a way for me to test out all the
-- weapons/powers/abolities/mobilies in an easier way. If I go through the creator in dev console it brings me to
-- prologue."). Studio only: never built in a live game, and DevService refuses every lab command outside Studio.
-- The LAB button (top right, beside DEV) opens six tabs:
--   WEAPONS  tap any of the 36: carried and held at once with Z X C V open (nothing bought; no Mastery earned);
--            HOLD POWER / HOLD WEAPON swap keys 1 and 2 (the game's WeaponHold)
--   POWERS   an archetype, then a path: loaded at the level cap, every ability at max rank, a loadout filled from
--            it; each ability's TRY puts it on skill key 1 (a super on the super), MOD flips its rank-3 pick (the
--            game's SkillsMod); BORROW lists the archetype's other paths' skills with TRY too
--   MOVES    any mobility at its last rank, any rank 0 to 5, both choice moves at ranks 3 and 5
--   CHEATS   god mode, cooldowns off, infinite stamina, supers ready (+ Awakening full), heal, level cap, style
--   TARGETS  training dummies (the HQ's, with a damage readout), every robot kind one at a time in front, the
--            famous fakes and the evil twin, each world boss, the HQ boss sim
--   START    "Skip prologue" (finishing the creator drops a new hero straight into the city), the creator, wipe,
--            and LEAVE LAB (your own build back; the save keeps it the whole time)
-- Phone sizes: buttons are Config.Ui.phone.minPrimary tall, text stays at minText or more, the page scrolls.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local AbilityRules = require(Shared:WaitForChild("AbilityRules"))
local MoveRanks = require(Shared:WaitForChild("MoveRanks"))
local WeaponRules = require(Shared:WaitForChild("WeaponRules"))
local LabRules = require(Shared:WaitForChild("LabRules"))

local Kit = require(script.Parent.Kit)
local State = require(script.Parent.Parent.State)

local TestLab = {}

local P = Config.Ui.phone
local A = Config.Abilities
local ROW = P.minPrimary -- every button's height
local GAP = 6
local PAD = 10

TestLab.TABS = {
	{ id = "weapons", text = "WEAPONS" },
	{ id = "powers", text = "POWERS" },
	{ id = "moves", text = "MOVES" },
	{ id = "cheats", text = "CHEATS" },
	{ id = "targets", text = "TARGETS" },
	{ id = "start", text = "START" },
}

local function send(name: string, value: number?)
	Net.send("DevCommand", name, value)
end

local function lab(): { [string]: any }
	return State.hero.lab or { on = false }
end

local gui: ScreenGui
local panel: Frame
local toggle: TextButton
local page: ScrollingFrame
local status: TextLabel
local tabButtons: { [string]: TextButton } = {}
local tab = "weapons"
-- the device's own picks (what the page shows; the server holds the hero)
local pick = {
	classId = nil :: string?,
	borrow = nil :: string?,
	skip = false,
	style = false,
}

local render: () -> ()

---------------------------------------------------------------------------
-- Page building: headings, grids of buttons and ability rows, laid out by hand top to bottom
---------------------------------------------------------------------------
local y = 0
local width = 300

local function heading(text: string)
	local l = Kit.label({
		Name = "Heading",
		Text = text,
		Size = UDim2.fromOffset(width, 26),
		Position = UDim2.fromOffset(0, y),
		TextColor3 = Kit.color.paper,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		maxText = 18,
		ink = false,
	})
	l.Parent = page
	y += 26 + GAP
end

local function note(text: string)
	local l = Kit.label({
		Name = "Note",
		Text = text,
		Size = UDim2.fromOffset(width, 34),
		Position = UDim2.fromOffset(0, y),
		Font = Kit.bodyFont,
		TextColor3 = Kit.color.paper,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextScaled = false,
		TextSize = 13,
		TextWrapped = true,
		maxText = 14,
		ink = false,
	})
	l.Parent = page
	y += 34 + GAP
end

type Item = { name: string, text: string, on: boolean?, fn: () -> () }

local function grid(items: { Item }, cellW: number?)
	local want = cellW or 150
	local cols = math.max(2, math.floor((width + GAP) / (want + GAP)))
	local w = math.floor((width - (cols - 1) * GAP) / cols)
	for i, it in items do
		local col, row = (i - 1) % cols, (i - 1) // cols
		local b = Kit.button({
			Name = it.name,
			Text = it.text,
			Size = UDim2.fromOffset(w, ROW),
			Position = UDim2.fromOffset(col * (w + GAP), y + row * (ROW + GAP)),
			BackgroundColor3 = if it.on then Kit.color.gold else Kit.color.paper,
			maxText = 18,
		}, it.fn)
		b:SetAttribute("On", it.on == true)
		b.Parent = page
	end
	y += math.ceil(#items / cols) * (ROW + GAP)
end

-- An ability row: its name and where it sits, then its buttons (TRY, MOD)
local function abilityRow(text: string, buttons: { Item })
	local bw = 86
	local lw = width - #buttons * (bw + GAP)
	local l = Kit.label({
		Name = "Ability",
		Text = text,
		Size = UDim2.fromOffset(lw, ROW),
		Position = UDim2.fromOffset(0, y),
		Font = Kit.bodyFont,
		TextColor3 = Kit.color.paper,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		maxText = 15,
		ink = false,
	})
	l.Parent = page
	for i, it in buttons do
		local b = Kit.button({
			Name = it.name,
			Text = it.text,
			Size = UDim2.fromOffset(bw, ROW),
			Position = UDim2.fromOffset(lw + GAP + (i - 1) * (bw + GAP), y),
			BackgroundColor3 = if it.on then Kit.color.gold else Kit.color.paper,
			maxText = 18,
		}, it.fn)
		b.Parent = page
	end
	y += ROW + GAP
end

local function abilityName(id: string?): string
	local row = id and A.list[id]
	return if row then row.name or row.id else "-"
end

-- Where an ability sits in the loadout now: "key 1" to "key 4", "SUPER", "M1", or ""
local function slotText(id: string): string
	local l = State.hero.loadout or {}
	if l.basic == id then
		return "M1"
	end
	local i = table.find(l.skills or {}, id)
	if i then
		return "key " .. i
	end
	if l.super == id then
		return "SUPER"
	end
	return ""
end

---------------------------------------------------------------------------
-- The pages
---------------------------------------------------------------------------
local function weaponsPage()
	local L = lab()
	local held = State.hero.held == "weapon"
	grid({
		{
			name = "HoldPower",
			text = "HOLD POWER",
			on = not held,
			fn = function()
				Net.send("WeaponHold", 1)
			end,
		},
		{
			name = "HoldWeapon",
			text = "HOLD WEAPON",
			on = held,
			fn = function()
				Net.send("WeaponHold", 2)
			end,
		},
	})
	note(
		"Tap a weapon: you carry and hold it now, Z X C V all open. Nothing is bought; no Mastery is earned."
	)
	local byFamily: { [string]: { Item } } = {}
	for _, row in Config.Weapons.list do
		local id = row[1]
		local list = byFamily[row[2]] or {}
		byFamily[row[2]] = list
		table.insert(list, {
			name = "Weapon_" .. id,
			text = row[3],
			on = L.on and L.weapon == id,
			fn = function()
				send("labweapon", id)
			end,
		})
	end
	for _, f in Config.Weapons.families do
		if byFamily[f.id] then
			heading(string.upper(f.name))
			grid(byFamily[f.id])
		end
	end
end

local function powersPage()
	local classId = pick.classId or State.hero.classId or Config.Classes.default
	pick.classId = classId
	heading("ARCHETYPE")
	local arch = {}
	for _, id in Config.Classes.order do
		table.insert(arch, {
			name = "Class_" .. id,
			text = Config.Classes[id].name or id,
			on = id == classId,
			fn = function()
				pick.classId = id
				pick.borrow = nil
				render()
			end,
		})
	end
	grid(arch)
	heading("PATH (loads it at the level cap, every ability at max rank)")
	local paths = {}
	for _, set in AbilityRules.paths(Config, classId) do
		table.insert(paths, {
			name = "Path_" .. set,
			text = A.setName[set] or set,
			on = State.hero.startSet == set,
			fn = function()
				pick.borrow = nil
				send("labpath", table.find(A.sets, set) or 1)
			end,
		})
	end
	grid(paths)
	local main = State.hero.startSet
	if not main or AbilityRules.archetypeOf(Config, main) ~= classId then
		note("Pick a path above to load it and try its abilities.")
		return
	end
	local l = State.hero.loadout or {}
	local keys = {}
	for i = 1, 4 do
		table.insert(keys, string.format("%d %s", i, abilityName((l.skills or {})[i])))
	end
	note("NOW: " .. table.concat(keys, " | ") .. " | SUPER " .. abilityName(l.super))
	heading(string.upper(A.setName[main] or main) .. ": TRY puts it on key 1")
	local p = LabRules.pathAbilities(Config, main)
	local function row(id: string?)
		local r = id and A.list[id]
		if not r then
			return
		end
		local where = slotText(r.id)
		local text =
			string.format("%s (%s)%s", r.name or r.id, r.slot, if where ~= "" then ": " .. where else "")
		local buttons: { Item } = {}
		if r.slot ~= "basic" then
			table.insert(buttons, {
				name = "Try_" .. r.id,
				text = "TRY",
				on = where ~= "",
				fn = function()
					send("labtry", r.num)
				end,
			})
		end
		if r.mods then
			local now = (State.hero.mods or {})[r.id]
			local nextPick = if now == 1 then 2 else 1
			table.insert(buttons, {
				name = "Mod_" .. r.id,
				text = if now then "MOD " .. now else "MOD -",
				on = now ~= nil,
				fn = function()
					Net.send("SkillsMod", r.num, nextPick)
				end,
			})
		end
		abilityRow(text, buttons)
	end
	row(p.basic)
	for _, id in p.skills do
		row(id)
	end
	row(p.super)
	-- borrowed skills: the archetype's other paths
	local others = LabRules.borrowPaths(Config, main)
	if #others == 0 then
		return
	end
	local borrow = pick.borrow
	if not borrow or not table.find(others, borrow) then
		borrow = others[1]
		pick.borrow = borrow
	end
	heading(string.format("BORROW (up to %d skills from the same archetype)", A.borrowMax))
	local tabs = {}
	for _, set in others do
		table.insert(tabs, {
			name = "Borrow_" .. set,
			text = A.setName[set] or set,
			on = set == borrow,
			fn = function()
				pick.borrow = set
				render()
			end,
		})
	end
	grid(tabs)
	for _, id in LabRules.pathAbilities(Config, borrow :: string).skills do
		row(id)
	end
end

local function movesPage()
	local M = Config.Move
	local mob = State.hero.mobility or "flight"
	heading("MOBILITY (at its last rank, both moves picked)")
	local picks = {}
	for i, id in M.mobilityOrder do
		table.insert(picks, {
			name = "Move_" .. id,
			text = M.mobility[id].name or id,
			on = id == mob,
			fn = function()
				send("labmove", i)
			end,
		})
	end
	grid(picks)
	local max = MoveRanks.max(M, mob)
	local rank = MoveRanks.rankOf(M, State.hero.mobRanks, mob)
	heading(string.format("RANK (now %d of %d)", rank, max))
	local ranks = {}
	for r = 0, max do
		table.insert(ranks, {
			name = "Rank_" .. r,
			text = "RANK " .. r,
			on = r == rank,
			fn = function()
				send("labrank", r)
			end,
		})
	end
	grid(ranks, 96)
	for _, c in M.choices or {} do
		local opts = MoveRanks.options(M, mob, c)
		if opts then
			local now = MoveRanks.picked(M, State.hero.mobMoves, mob, c)
			heading(string.format("RANK %d MOVE%s", c, if rank < c then " (needs rank " .. c .. ")" else ""))
			local items = {}
			for k, moveId in opts do
				local mv = M.moves[moveId]
				table.insert(items, {
					name = string.format("Choice_%d_%d", c, k),
					text = if mv then mv.name else moveId,
					on = now == k,
					fn = function()
						send("labchoice", LabRules.choiceValue(c, k))
					end,
				})
			end
			grid(items)
		end
	end
end

local function cheatsPage()
	local L = lab()
	heading("SWITCHES")
	grid({
		{
			name = "God",
			text = if L.god then "GOD ON" else "GOD OFF",
			on = L.god == true,
			fn = function()
				send("god", if L.god then 0 else 1)
			end,
		},
		{
			name = "NoCooldowns",
			text = if L.noCd then "COOLDOWNS OFF" else "COOLDOWNS ON",
			on = L.noCd == true,
			fn = function()
				send("labnocd", if L.noCd then 0 else 1)
			end,
		},
		{
			name = "Stamina",
			text = if L.stamina then "STAMINA: ENDLESS" else "STAMINA: NORMAL",
			on = L.stamina == true,
			fn = function()
				send("labstamina", if L.stamina then 0 else 1)
			end,
		},
		{
			name = "Style",
			text = if State.hero.fxStyle == "Anime" then "STYLE: ANIME" else "STYLE: COMIC",
			on = State.hero.fxStyle == "Anime",
			fn = function()
				send("style", if State.hero.fxStyle == "Anime" then 0 else 1)
			end,
		},
	})
	heading("NOW")
	grid({
		{
			name = "Ready",
			text = "SUPERS READY",
			fn = function()
				send("labready")
			end,
		},
		{
			name = "Awaken",
			text = "AWAKENING FULL",
			fn = function()
				send("meter")
			end,
		},
		{
			name = "Heal",
			text = "HEAL",
			fn = function()
				send("heal")
			end,
		},
		{
			name = "LevelCap",
			text = "LEVEL " .. Config.Stats.levelCap,
			fn = function()
				send("level", Config.Stats.levelCap)
			end,
		},
	})
	note(
		string.format(
			"Cooldowns off: every skill and super is ready again after %.2f s (M1 keeps its own rate). Supers ready also fills Awakening.",
			Config.Dev.lab.cooldown
		)
	)
end

local function targetsPage()
	heading("TRAINING DUMMIES (they show the damage you deal)")
	grid({
		{
			name = "Dummy",
			text = "DUMMY",
			fn = function()
				send("labdummy", 0)
			end,
		},
		{
			name = "BigDummy",
			text = "BIG DUMMY",
			fn = function()
				send("labdummy", 1)
			end,
		},
		{
			name = "ClearDummies",
			text = "CLEAR DUMMIES",
			fn = function()
				send("labdummy", 2)
			end,
		},
		{
			name = "ClearRobots",
			text = "CLEAR ROBOTS",
			fn = function()
				send("cleardrones")
			end,
		},
	})
	heading("ROBOTS (one in front of you, at your level)")
	local robots = {}
	for _, r in LabRules.robots(Config) do
		table.insert(robots, {
			name = "Robot_" .. r.kind,
			text = r.name,
			fn = function()
				send("labrobot", r.index)
			end,
		})
	end
	table.insert(robots, {
		name = "Twin",
		text = "MY EVIL TWIN",
		fn = function()
			send("twin")
		end,
	})
	grid(robots)
	heading("WORLD BOSSES (lands in 3 s; everyone in the server sees it)")
	local bosses = {}
	for i, id in Config.Boss.order do
		local b = Config.Boss.bosses[id]
		table.insert(bosses, {
			name = "Boss_" .. id,
			text = if b then b.name or id else id,
			fn = function()
				send("labboss", i)
			end,
		})
	end
	table.insert(bosses, {
		name = "BossLow",
		text = "BOSS TO 1 HP",
		fn = function()
			send("bosskill")
		end,
	})
	grid(bosses)
	heading("BOSS PRACTICE")
	grid({
		{
			name = "BossSim",
			text = "HQ BOSS SIM",
			fn = function()
				send("hqlevel", Config.Hq.levels.bossSim)
				send("hq")
			end,
		},
	})
	note("HQ BOSS SIM takes you into your HQ (at the HQ level the sim needs): use its Boss Sim station.")
end

local function startPage()
	heading("THE CREATOR")
	grid({
		{
			name = "Skip",
			text = if pick.skip then "SKIP PROLOGUE: ON" else "SKIP PROLOGUE: OFF",
			on = pick.skip,
			fn = function()
				pick.skip = not pick.skip
				send("labskip", if pick.skip then 1 else 0)
				render()
			end,
		},
		{
			name = "Creator",
			text = "OPEN CREATOR",
			fn = function()
				send("creator")
			end,
		},
		{
			name = "Wipe",
			text = "WIPE: NEW HERO",
			fn = function()
				send("wipe")
			end,
		},
	})
	note(
		"Skip prologue ON: finishing the creator puts a new hero straight into the city (the prologue counts as done)."
	)
	heading("THE LAB")
	grid({
		{
			name = "Leave",
			text = "LEAVE LAB",
			on = lab().on == true,
			fn = function()
				send("lableave")
			end,
		},
	})
	note("While the lab is on, your save keeps the build you had before it. LEAVE LAB puts that build back.")
end

local PAGES: { [string]: () -> () } = {
	weapons = weaponsPage,
	powers = powersPage,
	moves = movesPage,
	cheats = cheatsPage,
	targets = targetsPage,
	start = startPage,
}

-- One line: what the hero carries and has now
local function statusText(): string
	local h = State.hero
	local L = lab()
	local w = WeaponRules.get(Config, h.weapon or 0)
	local mob = Config.Move.mobility[h.mobility or "flight"]
	return string.format(
		"%s%s | %s %s | %s rank %d | %s%s%s",
		if h.held == "weapon" then "HOLDING " else "",
		if w then w.name else "-",
		A.setName[h.startSet or ""] or "-",
		if h.classId then "(" .. h.classId .. ")" else "",
		if mob then mob.name else "-",
		MoveRanks.rankOf(Config.Move, h.mobRanks, h.mobility),
		if L.god then "GOD " else "",
		if L.noCd then "NO CD " else "",
		if L.on then "LAB ON" else "LAB OFF"
	)
end

function render()
	if not panel or not panel.Visible then
		return
	end
	for _, c in page:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	for id, b in tabButtons do
		b.BackgroundColor3 = if id == tab then Kit.color.gold else Kit.color.paper
	end
	status.Text = statusText()
	y = 0
	width = math.max(200, panel.Size.X.Offset - 2 * PAD - 8)
	PAGES[tab]()
	page.CanvasSize = UDim2.fromOffset(0, y + PAD)
end

-- Lay the header and tabs out for the panel's width (one row of six when it is wide, two rows of three if not)
local function layout()
	local w = panel.Size.X.Offset
	local wide = w >= 600
	local close = panel:FindFirstChild("Close") :: TextButton
	close.Position = UDim2.fromOffset(w - PAD - ROW, PAD)
	local title = panel:FindFirstChild("Title") :: TextLabel
	local titleW = if wide then 70 else w - 2 * PAD - ROW - GAP
	title.Size = UDim2.fromOffset(titleW, ROW)
	local x0 = if wide then PAD + titleW + GAP else PAD
	local top = if wide then PAD else PAD + ROW + GAP
	local span = if wide then w - x0 - PAD - ROW - GAP else w - 2 * PAD
	local cols = if wide then #TestLab.TABS else 3
	local bw = math.floor((span - (cols - 1) * GAP) / cols)
	for i, t in TestLab.TABS do
		local b = tabButtons[t.id]
		local col, row = (i - 1) % cols, (i - 1) // cols
		b.Size = UDim2.fromOffset(bw, ROW)
		b.Position = UDim2.fromOffset(x0 + col * (bw + GAP), top + row * (ROW + GAP))
	end
	local below = top + (if wide then 1 else 2) * (ROW + GAP)
	status.Position = UDim2.fromOffset(PAD, below)
	status.Size = UDim2.fromOffset(w - 2 * PAD, 30)
	page.Position = UDim2.fromOffset(PAD, below + 30 + GAP)
	page.Size = UDim2.new(1, -2 * PAD, 1, -(below + 30 + GAP + PAD))
	render()
end

function TestLab.open(which: string?)
	if not panel then
		return
	end
	if which and PAGES[which] then
		tab = which
	end
	panel.Visible = true
	toggle.Visible = false -- the panel's own X closes it (LAB would sit over its tabs on a phone)
	layout()
end

function TestLab.close()
	if panel then
		panel.Visible = false
		toggle.Visible = true
	end
end

function TestLab.tab(): string
	return tab
end

function TestLab.init()
	if not RunService:IsStudio() then
		return
	end
	gui = Kit.screen("TestLab", 21)
	panel = Kit.frame({
		Name = "Panel",
		BackgroundColor3 = Kit.color.night,
		BackgroundTransparency = 0.08,
		Visible = false,
	})
	panel.Parent = gui
	Kit.fit(panel, 360, 280, 760, 640)
	toggle = Kit.button({
		Name = "LabToggle",
		Text = "LAB",
		Size = UDim2.fromOffset(72, ROW),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -88, 0, 12),
	}, function()
		if panel.Visible then
			TestLab.close()
		else
			TestLab.open()
		end
	end)
	toggle.Parent = gui
	local title = Kit.label({
		Name = "Title",
		Text = "TEST LAB",
		Position = UDim2.fromOffset(PAD, PAD),
		TextColor3 = Kit.color.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		maxText = 22,
		ink = false,
	})
	title.Parent = panel
	local close = Kit.button({
		Name = "Close",
		Text = "X",
		Size = UDim2.fromOffset(ROW, ROW),
		BackgroundColor3 = Kit.color.red,
	}, TestLab.close)
	close.Parent = panel
	for _, t in TestLab.TABS do
		local b = Kit.button({ Name = "Tab_" .. t.id, Text = t.text, maxText = 18 }, function()
			tab = t.id
			render()
		end)
		b.Parent = panel
		tabButtons[t.id] = b
	end
	status = Kit.label({
		Name = "Status",
		Text = "",
		Font = Kit.bodyFont,
		TextColor3 = Kit.color.paper,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		maxText = 15,
		ink = false,
	})
	status.Parent = panel
	page = Instance.new("ScrollingFrame")
	page.Name = "Page"
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ScrollBarThickness = 6
	page.CanvasSize = UDim2.new()
	page.Parent = panel
	panel:GetPropertyChangedSignal("Size"):Connect(function()
		if panel.Visible then
			layout()
		end
	end)
	State.Changed:Connect(render)
end

return TestLab
