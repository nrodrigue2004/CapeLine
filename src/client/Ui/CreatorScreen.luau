-- CreatorScreen: "Who are you?" The old-RPG style creator from nate's hero creator plan (2026-11-16,
-- https://claude.ai/artifact/VeuJPWz6kKE6gGsUBmqQC9): tabs along the top (BODY > SIDE > MOBILITY > POWERS >
-- WEAPON > APPEARANCE > PLAY), the choices on the left, the hero big in the middle showing each choice live
-- (hovering previews it), and a detail card on the right with a Complexity rating, a short description and
-- the keys; pieces, colours and the weapon's look are picked on the right too. Back, Randomize and Next sit
-- along the bottom. On phones the list moves to a drawer along the bottom.
-- * BODY: gender, build (Small, Medium, Large, Titan) and height; looks only.
-- * SIDE: Hero or Villain (new heroes only). MOBILITY: 5 picks. POWERS: archetype, path, Comic or Anime.
-- * WEAPON: a family, then a weapon; a new hero takes any playable Rack weapon free; its style, finish,
--   colours, glow and emblem.
-- * APPEARANCE: 23 slots in body areas, each with its pieces (locked ones say how to get them), its own
--   main, trim and glow colour (AUTO = the whole-hero colour) and a material; SKIN; COLORS (match all).
-- * PLAY: a Title and a Noun from two wheels, never typed; then DONE sends Hero.Create.
-- Modes: "create" (Suit Up), "first" (a hero made before the creator), "edit" (HQ or a safehouse).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Rng = require(Shared:WaitForChild("Rng"))
local LookCodec = require(Shared:WaitForChild("LookCodec"))
local AbilityRules = require(Shared:WaitForChild("AbilityRules"))
local CreatorRules = require(Shared:WaitForChild("CreatorRules"))
local WeaponRules = require(Shared:WaitForChild("WeaponRules"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))

local Kit = require(script.Parent.Kit)
local Preview = require(script.Parent.Preview)
local State = require(script.Parent.Parent.State)

local CreatorScreen = {}

local C = Config.Creator
local B = C.body
local W = Config.Weapons
local T = Config.Ui.touchTarget
local STEPS = {
	{ id = "body", name = "Body" },
	{ id = "side", name = "Side" },
	{ id = "mobility", name = "Mobility" },
	{ id = "powers", name = "Powers" },
	{ id = "weapon", name = "Weapon" },
	{ id = "appearance", name = "Appearance" },
	{ id = "play", name = "Play" },
}
-- the appearance list: body areas, then their slots (tab ids from Config.Creator, plus skin and colours)
local AREAS = {
	{ "BODY", { "skin", "colors" } },
	{ "HEAD", { "hair", "beard", "eyes", "face", "makeup", "head", "hat", "ears" } },
	{ "TORSO", { "suit", "shoulders", "neck", "emblem" } },
	{ "ARMS", { "arms", "hands", "wrist" } },
	{ "WAIST AND LEGS", { "belt", "legs", "feet" } },
	{ "BACK", { "backpack", "back" } },
	{ "EXTRAS", { "aura", "trail", "voice" } },
}
local SLOT_NAMES = {
	skin = "Skin",
	colors = "Colours (match all)",
	suit = "Top",
	back = "Cape",
	head = "Mask",
	hands = "Gloves",
	feet = "Shoes",
	emblem = "Symbol",
	trail = "Flight trail",
	backpack = "Back bling",
	hat = "Headwear",
}
local FACE_SLOTS = { hair = true, beard = true, eyes = true, face = true, makeup = true, ears = true }
local BACK_SLOTS = { back = true, backpack = true }
-- slots with no NONE choice (every hero has a top, a flight trail and a voice)
local REQUIRED = { suit = true, trail = true, voice = true }
local REASONS = {
	locked = "That piece is not unlocked yet",
	piece = "That piece does not exist",
	color = "Pick colours from the palette",
	material = "Pick a material from the list",
	body = "Pick a gender, build and height",
	name = "Pick another name pair",
	pick = "Pick an archetype, a path and a mobility",
	path = "Your archetype and path are set (one free change before level 10)",
	look = "Something went wrong: try again",
	scene = "Finish what you are doing first",
	combat = "Not during a fight",
	safehouse = "Change your look at HQ or a safehouse",
	weapon = "Get that weapon at a Weapon Rack first",
	style = "Pick one of the weapon's styles",
	finish = "Pick a finish",
	glow = "Pick a glow strength",
	trail = "Pick a swing trail",
}

local gui: ScreenGui
local panel: Frame
local stepRow: Frame
local list: ScrollingFrame
local detail: ScrollingFrame
local card: Frame
local cardTitle: TextLabel
local cardSub: TextLabel
local cardBody: TextLabel
local grid: Frame
local nameLabel: TextLabel
local status: TextLabel
local backButton: TextButton
local nextButton: TextButton
local cancelButton: TextButton
local preview: Preview.Handle

local mode = "edit"
local look: LookCodec.Look = CreatorRules.defaultLook(Config)
local weaponLook: WeaponRules.WeaponLook = WeaponRules.lookOf(nil, W.defaultWeapon)
local titleId, nounId, classIdx, sideIdx, setIdx = 0, 0, 0, 1, 1
local mobIdx = 1
local pathOpen = true
local step = 1
local slot = "suit" -- the appearance slot open on the right
local family = "fists" -- the weapon family open on the left
local colorTarget = 1 -- the slot colour being edited: 1 main, 2 trim, 3 glow (COLORS: 1-3 hero, 4 hair, 5 eyes)
local weaponTarget = 1 -- the weapon colour being edited: 1 main, 2 trim, 3 glow
local cardFor: (() -> ())? = nil -- redraws the card for the current pick (after a hover ends)
local pending = false
local saveSent = 0
local rng = Rng.new(os.time() % 100000 + 3)

-- the client's copy of the unlocks as a profile-shaped table (the server checks everything again)
local function profileView(): any
	local pieces = table.create(ProfileSchema.PIECE_WORDS, 0)
	for _, id in State.profile.pieces or {} do
		local k = id // 32 + 1
		if pieces[k] then
			pieces[k] = bit32.bor(pieces[k], bit32.lshift(1, id % 32))
		end
	end
	local owned = table.create(ProfileSchema.WEAPON_WORDS, 0)
	for _, id in State.profile.weaponsOwned or {} do
		local k = id // 32 + 1
		if owned[k] then
			owned[k] = bit32.bor(owned[k], bit32.lshift(1, id % 32))
		end
	end
	return { pieces = pieces, weaponsOwned = owned, weapons = State.profile.weapons or {} }
end

local function sourceText(p: CreatorRules.Piece): string
	local s = p.source
	local k = s.kind
	if k == "lvl" then
		return "Level " .. (s.n or 0)
	elseif k == "rep" then
		return (if s.a == "league" then "League" elseif s.a == "syndicate" then "Syndicate" else "City")
			.. " rank "
			.. (s.n or 0)
	elseif k == "fame" then
		return "Fame rank " .. (s.n or 0)
	elseif k == "boss" then
		local b = Config.Boss.bosses[s.a or ""]
		local tier = ({ "join", "contributor", "MVP" })[s.n or 1]
		return (if b then b.name else "World boss") .. ": " .. tier
	elseif k == "mission" then
		local m = Config.Story.missions[s.n or 0]
		return "Mission: " .. (if m then m.name else "?")
	elseif k == "quest" then
		local q = Config.Story.quests[s.n or 0]
		return "Side quest: " .. (if q then q.npc else "?")
	elseif k == "legacy" then
		return "Legacy rank " .. (s.n or 0)
	elseif k == "drop" then
		return "Epic drops"
	elseif k == "pack" then
		local pk = Config.Shop.packs[s.n or 0]
		return "Pack: " .. (if pk then pk.name else "?")
	elseif k == "starter" then
		return "Starter pack"
	end
	return ""
end

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function slotName(id: string): string
	if SLOT_NAMES[id] then
		return SLOT_NAMES[id]
	end
	for _, t in C.tabs do
		if t.id == id then
			return t.name
		end
	end
	return id
end

local function heroName(): string
	return CreatorRules.heroName(Config, titleId, nounId) or "PICK A NAME"
end

local function weaponStatus(id: number): (boolean, string)
	-- can this weapon be carried out of the creator, and the line that says so
	local w = WeaponRules.get(Config, id)
	if not w then
		return false, ""
	end
	if not WeaponRules.playable(Config, id) then
		return false, "Coming soon"
	end
	if WeaponRules.owned(Config, profileView(), id) then
		return true, "Owned"
	end
	if mode ~= "edit" and WeaponRules.freePickOk(Config, id) then
		return true, "Free pick for a new hero"
	end
	if w.robux then
		local row = Config.Shop.products[w.robux]
		return false, "Robux shop: " .. (if row then row.robux else "?") .. " R$"
	end
	return false, Kit.comma(w.price or 0) .. " Credits at a Weapon Rack"
end

local function canFinish(): (boolean, string?)
	if titleId == 0 or nounId == 0 then
		return false, "Pick a Title and a Noun (PLAY)"
	end
	if not CreatorRules.nameOk(Config, titleId, nounId) then
		return false, REASONS.name
	end
	if classIdx == 0 then
		return false, "Pick an archetype (POWERS)"
	end
	local ok, why = weaponStatus(weaponLook.id)
	if not ok then
		local w = WeaponRules.get(Config, weaponLook.id)
		return false,
			(if w then w.name .. ": " else "") .. (if why ~= "" then why else "Pick a weapon (WEAPON)")
	end
	return true, nil
end

local function clear(frame: Instance)
	for _, c in frame:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local refresh: () -> ()

-- the hero in the middle: the current look, or a look being hovered
local function showPreview(l: any?, wl: any?)
	preview.set(l or look, wl or weaponLook)
end

local function setCard(title: string, sub: string?, body: string?)
	cardTitle.Text = string.upper(title)
	cardSub.Text = sub or ""
	cardBody.Text = body or ""
end

-- A row in the left list. hover (optional) previews the choice on the hero and on the card.
local rowOrder = 0
local function header(text: string)
	rowOrder += 1
	local l = Kit.label({
		Text = text,
		Size = UDim2.new(1, -8, 0, 24),
		LayoutOrder = rowOrder,
		TextColor3 = Kit.color.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		maxText = 18,
	})
	l.Parent = list
end
local function row(
	text: string,
	sub: string?,
	on: boolean,
	locked: boolean,
	pick: () -> (),
	hover: (() -> ())?
)
	rowOrder += 1
	local b = Kit.button({
		Text = "",
		Size = UDim2.new(1, -8, 0, T),
		LayoutOrder = rowOrder,
		BackgroundColor3 = if on then Kit.color.gold elseif locked then Kit.color.muted else Kit.color.paper,
	}, pick)
	local l = Kit.label({
		Text = text,
		Size = UDim2.new(if sub then 0.58 else 1, -12, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		TextColor3 = Kit.color.ink,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Kit.bodyFont,
		maxText = 16,
	})
	l.Parent = b
	if sub then
		local s = Kit.label({
			Text = sub,
			Size = UDim2.new(0.42, -10, 1, 0),
			Position = UDim2.fromScale(0.58, 0),
			TextColor3 = if locked then Kit.color.paper else Kit.color.ink,
			TextXAlignment = Enum.TextXAlignment.Right,
			Font = Kit.bodyFont,
			maxText = 11,
		})
		s.Parent = b
	end
	if hover then
		b.MouseEnter:Connect(hover)
		b.MouseLeave:Connect(function()
			showPreview()
			if cardFor then
				cardFor()
			end
		end)
	end
	b.Parent = list
	return b
end

-- Tiles and swatches on the right (the grid under the card)
local tileOrder = 0
local function tile(
	text: string,
	sub: string?,
	on: boolean,
	locked: boolean,
	pick: () -> (),
	hover: (() -> ())?
)
	tileOrder += 1
	local b = Kit.button({
		Text = "",
		LayoutOrder = tileOrder,
		BackgroundColor3 = if on then Kit.color.gold elseif locked then Kit.color.muted else Kit.color.paper,
	}, pick)
	local l = Kit.label({
		Text = text,
		Size = UDim2.new(1, -6, if sub then 0.6 else 1, 0),
		Position = UDim2.fromOffset(3, 0),
		TextColor3 = if locked then Kit.color.paper else Kit.color.ink,
		Font = Kit.bodyFont,
		maxText = 14,
	})
	l.Parent = b
	if sub then
		local s = Kit.label({
			Text = sub,
			Size = UDim2.new(1, -6, 0.4, 0),
			Position = UDim2.new(0, 3, 0.6, 0),
			TextColor3 = if locked then Kit.color.gold else Kit.color.ink,
			Font = Kit.bodyFont,
			maxText = 10,
		})
		s.Parent = b
	end
	if hover then
		b.MouseEnter:Connect(hover)
		b.MouseLeave:Connect(function()
			showPreview()
		end)
	end
	b.Parent = grid
	return b
end
local function swatch(color: Color3?, on: boolean, pick: () -> (), label: string?)
	tileOrder += 1
	local b = Kit.button({
		Text = if on then "✓" else (label or ""),
		LayoutOrder = tileOrder,
		BackgroundColor3 = color or Kit.color.paper,
		maxText = 12,
	}, pick)
	Kit.stroke(b, if on then Kit.color.gold else Kit.color.ink, if on then 4 else 2)
	b.Parent = grid
end
-- a ◀ value ▶ cycler across the grid
local function cycler(label: string, value: string, change: (number) -> ())
	tileOrder += 1
	local f = Kit.frame({ LayoutOrder = tileOrder, BackgroundColor3 = Kit.color.paper })
	local l = Kit.label({
		Text = label .. ": " .. value,
		Size = UDim2.new(1, -2 * T, 1, 0),
		Position = UDim2.fromOffset(T, 0),
		TextColor3 = Kit.color.ink,
		Font = Kit.bodyFont,
		maxText = 13,
	})
	l.Parent = f
	for i, dir in { -1, 1 } do
		local b = Kit.button({
			Text = if dir < 0 then "◀" else "▶",
			Size = UDim2.new(0, T, 1, 0),
			Position = if i == 1 then UDim2.new() else UDim2.new(1, -T, 0, 0),
			BackgroundColor3 = Kit.color.gold,
		}, function()
			change(dir)
		end)
		b.Parent = f
	end
	f.Parent = grid
end
local function wrapIndex(i: number, n: number): number
	return (i - 1) % n + 1
end

local function hoverLook(edit: (any) -> ()): () -> ()
	return function()
		local l = LookCodec.copy(look)
		edit(l)
		showPreview(l, nil)
	end
end

----------------------------------------------------------------------------------------------- BODY
local function drawBody()
	preview.focus("full")
	header("GENDER")
	for i, g in B.genders do
		row(
			g,
			nil,
			look.gender == i,
			false,
			function()
				look.gender = i
				refresh()
			end,
			hoverLook(function(l)
				l.gender = i
			end)
		)
	end
	header("BUILD")
	for i, b in B.builds do
		row(b.name, nil, look.build == i, false, function()
			look.build = i
			refresh()
		end, function()
			hoverLook(function(l)
				l.build = i
			end)()
			setCard(b.name, B.note, b.text)
		end)
	end
	header("HEIGHT")
	for i, h in B.heightNames do
		row(
			h,
			nil,
			look.height == i,
			false,
			function()
				look.height = i
				refresh()
			end,
			hoverLook(function(l)
				l.height = i
			end)
		)
	end
	cardFor = function()
		local b = B.builds[look.build] or B.builds[2]
		setCard(
			b.name,
			B.note,
			string.format(
				"%s\n\n%s, %s\nEvery piece and weapon fits every body.",
				b.text,
				B.genders[look.gender] or "",
				B.heightNames[look.height] or ""
			)
		)
	end
	cardFor()
end

----------------------------------------------------------------------------------------------- SIDE
local SIDES = {
	{ "Hero", "Earn League reputation, protect the city. Bright skies." },
	{ "Villain", "Earn Syndicate reputation, rule the city. Storm-red skies." },
}
local function drawSide()
	preview.focus("full")
	local creating = mode == "create"
	header("SIDE")
	for i, s in SIDES do
		row(s[1], if creating then nil else "set by your story", sideIdx == i, not creating, function()
			if creating then
				sideIdx = i
				refresh()
			else
				status.Text = "Your side is set by your story"
			end
		end, function()
			setCard(s[1], nil, s[2])
		end)
	end
	cardFor = function()
		local s = SIDES[sideIdx]
		setCard(s[1], if creating then "Pick once for this hero" else "Set by your story", s[2])
	end
	cardFor()
end

----------------------------------------------------------------------------------------------- MOBILITY
local function mobilityCard(i: number)
	local id = Config.Move.mobilityOrder[i]
	local m = id and Config.Move.mobility[id]
	if m then
		setCard(m.name, "Change it free at any safehouse", m.text)
	end
end
local function drawMobility()
	preview.focus("full")
	header("HOW YOU GET AROUND")
	for i, id in Config.Move.mobilityOrder do
		local m = Config.Move.mobility[id]
		row(m.name, nil, mobIdx == i, false, function()
			mobIdx = i
			refresh()
		end, function()
			mobilityCard(i)
		end)
	end
	cardFor = function()
		mobilityCard(mobIdx)
	end
	cardFor()
end

----------------------------------------------------------------------------------------------- POWERS
local function pathCard(classId: string?, set: string?)
	if not classId then
		setCard("Pick an archetype", nil, "Then pick one of its paths")
		return
	end
	local cls = Config.Classes[classId]
	if not set then
		setCard(cls.name, cls.role, "Pick a path")
		return
	end
	local names = {}
	for _, id in Config.Abilities.order do
		local r = Config.Abilities.list[id]
		if r.set == set then
			table.insert(names, r.name)
		end
	end
	setCard(
		Config.Abilities.setName[set] or set,
		cls.name .. ": " .. cls.role,
		table.concat(names, ", ") .. "\n\nWorks with any weapon."
	)
end
local function drawPowers()
	preview.focus("full")
	header("ARCHETYPE")
	for i, id in Config.Classes.order do
		local cls = Config.Classes[id]
		row(cls.name, nil, classIdx == i, not pathOpen and classIdx ~= i, function()
			if pathOpen then
				if classIdx ~= i then
					setIdx = 1
				end
				classIdx = i
				refresh()
			else
				status.Text = REASONS.path
			end
		end, function()
			pathCard(id, nil)
		end)
	end
	local classId = Config.Classes.order[classIdx]
	if classId then
		header("PATH")
		for i, set in AbilityRules.paths(Config, classId) do
			row(
				Config.Abilities.setName[set] or set,
				nil,
				setIdx == i,
				not pathOpen and setIdx ~= i,
				function()
					if pathOpen then
						setIdx = i
						refresh()
					else
						status.Text = REASONS.path
					end
				end,
				function()
					pathCard(classId, set)
				end
			)
		end
	end
	header("EFFECT STYLE")
	for i, style in { "Comic", "Anime" } do
		row(style, nil, (look.anime and i == 2) or (not look.anime and i == 1), false, function()
			look.anime = i == 2
			refresh()
		end)
	end
	cardFor = function()
		local cls = Config.Classes.order[classIdx]
		local paths = if cls then AbilityRules.paths(Config, cls) else {}
		pathCard(cls, paths[setIdx])
	end
	cardFor()
end

----------------------------------------------------------------------------------------------- WEAPON
local function weaponCard(id: number)
	local w = WeaponRules.get(Config, id)
	if not w then
		return
	end
	local _, line = weaponStatus(id)
	setCard(
		w.name,
		"Complexity: " .. (W.complexity[w.complexity] or ""),
		w.text .. "\nM1: a 4-hit combo. Z X C V: skills (X, C, V open with Mastery).\n" .. line
	)
end
local function hoverWeapon(id: number): () -> ()
	return function()
		local wl = WeaponRules.lookOf(profileView(), id)
		showPreview(nil, wl)
		weaponCard(id)
	end
end
local function drawWeaponLook()
	local wl = weaponLook
	local w = WeaponRules.get(Config, wl.id)
	if not w then
		return
	end
	local styles = W.styles[w.family]
	cycler("STYLE", styles[wl.style] or "", function(d)
		wl.style = wrapIndex(wl.style + d, #styles)
		refresh()
	end)
	cycler("FINISH", (W.finishes[wl.finish] or W.finishes[1]).name, function(d)
		wl.finish = wrapIndex(wl.finish + d, #W.finishes)
		refresh()
	end)
	cycler("GLOW", tostring(wl.glowLevel), function(d)
		wl.glowLevel = math.clamp(wl.glowLevel + d, 0, W.glowLevels)
		refresh()
	end)
	tile("EMBLEM", if wl.emblem then "on" else "off", wl.emblem, false, function()
		wl.emblem = not wl.emblem
		refresh()
	end)
	for i, n in { "MAIN", "TRIM", "GLOW COLOUR" } do
		tile(n, nil, weaponTarget == i, false, function()
			weaponTarget = i
			refresh()
		end)
	end
	local key = ({ "main", "trim", "glow" })[weaponTarget]
	local cur = (wl :: any)[key]
	swatch(nil, cur == 0, function()
		(wl :: any)[key] = 0
		refresh()
	end, "AUTO")
	for i, c in C.palette do
		swatch(rgb(c), cur == i, function()
			(wl :: any)[key] = i
			refresh()
		end)
	end
end
local function drawWeapon()
	preview.focus("weapon")
	header("FAMILY")
	for _, f in W.families do
		row(f.name, nil, family == f.id, false, function()
			family = f.id
			refresh()
		end, function()
			setCard(f.name, nil, f.text)
		end)
	end
	header("WEAPONS")
	for _, w in WeaponRules.list(Config) do
		if w.family == family then
			local ok, line = weaponStatus(w.id)
			row(w.name, if ok then nil else line, weaponLook.id == w.id, not ok, function()
				-- previewing any weapon is fine; Done checks it can be carried
				weaponLook = WeaponRules.lookOf(profileView(), w.id)
				refresh()
			end, hoverWeapon(w.id))
		end
	end
	cardFor = function()
		weaponCard(weaponLook.id)
	end
	cardFor()
	drawWeaponLook()
end

----------------------------------------------------------------------------------------------- APPEARANCE
local function drawSlotColors()
	-- the slot's own main, trim and glow colour (AUTO = the whole-hero colour) and its material
	look.tints = look.tints or {}
	local t = look.tints[slot] or { 0, 0, 0 }
	for i, n in { "MAIN", "TRIM", "GLOW" } do
		tile(n, nil, colorTarget == i, false, function()
			colorTarget = i
			refresh()
		end)
	end
	local mats = look.mats or {}
	local m = mats[slot] or 0
	cycler("MATERIAL", if m == 0 then "Own" else C.materialNames[m], function(d)
		look.mats = look.mats or {}
		look.mats[slot] = (m + d) % (#C.materials + 1)
		refresh()
	end)
	local target = math.clamp(colorTarget, 1, 3)
	swatch(nil, (t[target] or 0) == 0, function()
		local nt = table.clone(t)
		nt[target] = 0
		look.tints[slot] = if nt[1] == 0 and nt[2] == 0 and nt[3] == 0 then nil else nt
		refresh()
	end, "AUTO")
	for i, c in C.palette do
		swatch(rgb(c), t[target] == i, function()
			local nt = table.clone(t)
			nt[target] = i
			look.tints[slot] = nt
			refresh()
		end)
	end
end
local function drawSkin()
	for i, c in C.skins do
		local fantasy = C.fantasySkins[i]
		swatch(rgb(c), look.skin == i, function()
			look.skin = i
			refresh()
		end, if fantasy then fantasy.name else nil)
	end
end
local function drawMatchAll()
	local names = { "PRIMARY", "SECONDARY", "ACCENT", "HAIR", "EYES" }
	for i, n in names do
		tile(n, nil, colorTarget == i, false, function()
			colorTarget = i
			refresh()
		end)
	end
	local cur = if colorTarget <= 3
		then look.colors[colorTarget]
		elseif colorTarget == 4 then look.hair
		else look.eyeColor
	if colorTarget == 5 then
		swatch(nil, cur == 0, function()
			look.eyeColor = 0
			refresh()
		end, "AUTO")
	end
	for i, c in C.palette do
		swatch(rgb(c), cur == i, function()
			if colorTarget <= 3 then
				look.colors[colorTarget] = i
			elseif colorTarget == 4 then
				look.hair = i
			else
				look.eyeColor = i
			end
			refresh()
		end)
	end
end
local function drawPieces()
	local pv = profileView()
	local cur = look.pieces[slot] or 0
	if not REQUIRED[slot] then
		tile(
			"NONE",
			nil,
			cur == 0,
			false,
			function()
				look.pieces[slot] = 0
				refresh()
			end,
			hoverLook(function(l)
				l.pieces[slot] = 0
			end)
		)
	end
	for _, p in CreatorRules.index(Config).byTab[slot] or {} do
		local have = CreatorRules.owned(Config, pv, p)
		tile(
			p.name,
			if have then nil else sourceText(p),
			cur == p.index,
			not have,
			function()
				if have then
					look.pieces[slot] = p.index
					refresh()
				else
					status.Text = p.name .. ": " .. sourceText(p)
				end
			end,
			hoverLook(function(l)
				l.pieces[slot] = p.index
			end)
		)
	end
end
local function drawAppearance()
	preview.focus(if FACE_SLOTS[slot] then "face" elseif BACK_SLOTS[slot] then "back" else "full")
	for _, area in AREAS do
		header(area[1])
		for _, id in area[2] do
			row(slotName(id), nil, slot == id, false, function()
				if slot ~= id then
					colorTarget = 1
				end
				slot = id
				refresh()
			end)
		end
	end
	cardFor = function()
		local count = #(CreatorRules.index(Config).byTab[slot] or {})
		local sub = if slot == "skin"
			then "24 tones and 6 fantasy skins"
			elseif slot == "colors" then "Sets the whole hero; any slot can then have its own"
			else count .. " styles. Tap a colour square for this slot's own colours."
		setCard(slotName(slot), sub, nil)
	end
	cardFor()
	if slot == "skin" then
		drawSkin()
	elseif slot == "colors" then
		drawMatchAll()
	else
		drawPieces()
		if slot ~= "voice" and slot ~= "aura" and slot ~= "trail" then
			drawSlotColors()
		end
	end
end

----------------------------------------------------------------------------------------------- PLAY
local function drawPlay()
	preview.focus("full")
	header("TITLE")
	for i, t in C.titles do
		row(t, nil, titleId == i, false, function()
			titleId = i
			refresh()
		end)
	end
	header("NOUN")
	for i, n in C.nouns do
		local blocked = titleId > 0 and not CreatorRules.nameOk(Config, titleId, i)
		row(n, if blocked then "taken" else nil, nounId == i, blocked, function()
			if not blocked then
				nounId = i
				refresh()
			end
		end)
	end
	cardFor = function()
		local b = B.builds[look.build] or B.builds[2]
		local cls = Config.Classes.order[classIdx]
		local paths = if cls then AbilityRules.paths(Config, cls) else {}
		local set = paths[setIdx]
		local mob = Config.Move.mobility[Config.Move.mobilityOrder[mobIdx] or "flight"]
		local w = WeaponRules.get(Config, weaponLook.id)
		setCard(
			heroName(),
			Players.LocalPlayer.DisplayName,
			string.format(
				"%s %s, %s\n%s, %s\n%s\n%s",
				B.genders[look.gender] or "",
				b.name,
				string.lower(B.heightNames[look.height] or ""),
				SIDES[sideIdx][1],
				if mob then mob.name else "",
				if set
					then (Config.Abilities.setName[set] or set) .. " (" .. Config.Classes[cls].name .. ")"
					else "Pick a power",
				if w then w.name else ""
			)
		)
	end
	cardFor()
end

local DRAW = {
	body = drawBody,
	side = drawSide,
	mobility = drawMobility,
	powers = drawPowers,
	weapon = drawWeapon,
	appearance = drawAppearance,
	play = drawPlay,
}

refresh = function()
	clear(list)
	clear(grid)
	rowOrder, tileOrder = 0, 0
	cardFor = nil
	for _, b in stepRow:GetChildren() do
		if b:IsA("TextButton") then
			b.BackgroundColor3 = if b.Name == STEPS[step].id then Kit.color.gold else Kit.color.paper
		end
	end
	DRAW[STEPS[step].id]()
	grid.Visible = #grid:GetChildren() > 1
	nameLabel.Text = string.upper(heroName())
	local ok, why = canFinish()
	local last = step == #STEPS
	nextButton.Text = if last then "DONE" else "NEXT"
	nextButton.BackgroundColor3 = if not last or (ok and not pending) then Kit.color.gold else Kit.color.muted
	backButton.Visible = step > 1
	if not pending then
		status.Text = if ok or not last then "" else (why or "")
	end
	showPreview()
end

local function finish()
	local ok, why = canFinish()
	if not ok then
		status.Text = why or ""
		return
	end
	if pending then
		return
	end
	pending = true
	status.Text = "Saving..."
	Net.send(
		"HeroCreate",
		LookCodec.encode(look),
		sideIdx,
		classIdx,
		setIdx,
		titleId,
		nounId,
		mobIdx,
		WeaponRules.encodeLook(weaponLook)
	)
	refresh()
	-- no answer: let them try again (spec: every remote call has an error state)
	local sentAt = os.clock()
	saveSent = sentAt
	task.delay(8, function()
		if pending and saveSent == sentAt and gui.Enabled then
			pending = false
			refresh()
			status.Text = "Could not save. Try again"
		end
	end)
end

-- Randomize: this step only (the plan: "Randomize (this tab only)")
local function randomize()
	local id = STEPS[step].id
	local l, t, n = CreatorRules.randomize(Config, profileView(), rng)
	if id == "body" then
		look.gender, look.build, look.height = l.gender, l.build, l.height
	elseif id == "side" then
		if mode == "create" then
			sideIdx = rng:int(1, 2)
		end
	elseif id == "mobility" then
		mobIdx = rng:int(1, #Config.Move.mobilityOrder)
	elseif id == "powers" then
		if pathOpen then
			classIdx = rng:int(1, #Config.Classes.order)
			setIdx = rng:int(1, math.max(1, #AbilityRules.paths(Config, Config.Classes.order[classIdx])))
		end
		look.anime = l.anime
	elseif id == "weapon" then
		local pool = {}
		for _, w in WeaponRules.list(Config) do
			if weaponStatus(w.id) then
				table.insert(pool, w.id)
			end
		end
		if #pool > 0 then
			local pick = pool[rng:int(1, #pool)]
			family = (WeaponRules.get(Config, pick) :: WeaponRules.Weapon).family
			weaponLook = WeaponRules.lookOf(profileView(), pick)
			weaponLook.style = rng:int(1, #W.styles[family])
			weaponLook.finish = rng:int(1, #W.finishes)
			weaponLook.main = rng:int(0, #C.palette)
			weaponLook.glowLevel = rng:int(0, W.glowLevels)
		end
	elseif id == "appearance" then
		local keep = { gender = look.gender, build = look.build, height = look.height, anime = look.anime }
		look = l
		look.gender, look.build, look.height, look.anime = keep.gender, keep.build, keep.height, keep.anime
	elseif id == "play" then
		titleId, nounId = t, n
	end
	refresh()
end

-- Phones: the list becomes a drawer along the bottom, the hero and card share the top
local function layout()
	local vp = (Workspace.CurrentCamera :: Camera).ViewportSize
	local phone = vp.X < 820
	local top = 50 + T + 12
	local bottom = T + 40
	if phone then
		list.Size = UDim2.new(1, -20, 0.34, -bottom)
		list.Position = UDim2.new(0, 10, 0.66, 0)
		preview.frame.Size = UDim2.new(0.45, -10, 0.66, -top - 40)
		preview.frame.Position = UDim2.fromOffset(10, top)
		detail.Size = UDim2.new(0.55, -20, 0.66, -top - 6)
		detail.Position = UDim2.new(0.45, 10, 0, top)
		nameLabel.Position = UDim2.new(0, 10, 0.66, -8)
		nameLabel.Size = UDim2.new(0.45, -10, 0, 30)
	else
		list.Size = UDim2.new(0.26, -10, 1, -top - bottom)
		list.Position = UDim2.fromOffset(10, top)
		preview.frame.Size = UDim2.new(0.36, -10, 1, -top - bottom - 40)
		preview.frame.Position = UDim2.new(0.26, 5, 0, top)
		detail.Size = UDim2.new(0.38, -15, 1, -top - bottom)
		detail.Position = UDim2.new(0.62, 5, 0, top)
		nameLabel.Position = UDim2.new(0.26, 5, 1, -bottom - 4)
		nameLabel.Size = UDim2.new(0.36, -10, 0, 34)
	end
	local g = grid:FindFirstChildOfClass("UIGridLayout")
	if g then
		g.CellSize = UDim2.fromOffset(if phone then 96 else 118, T + 12)
	end
end

local function build()
	gui = Kit.screen("Creator", 20)
	gui.Enabled = false
	panel = Kit.frame({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Kit.color.night,
		round = false,
	})
	panel.Parent = gui
	local title = Kit.label({
		Text = "WHO ARE YOU?",
		Size = UDim2.new(0, 260, 0, 40),
		Position = UDim2.fromOffset(10, 6),
		TextColor3 = Kit.color.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		maxText = 34,
	})
	title.Parent = panel
	-- the step tabs (BODY > SIDE > ... > PLAY)
	stepRow = Instance.new("Frame")
	stepRow.BackgroundTransparency = 1
	stepRow.Size = UDim2.new(1, -20, 0, T)
	stepRow.Position = UDim2.fromOffset(10, 50)
	stepRow.Parent = panel
	local sl = Instance.new("UIListLayout")
	sl.FillDirection = Enum.FillDirection.Horizontal
	sl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	sl.Padding = UDim.new(0, 6)
	sl.SortOrder = Enum.SortOrder.LayoutOrder
	sl.Parent = stepRow
	for i, s in STEPS do
		local b = Kit.button({
			Name = s.id,
			Text = string.upper(s.name),
			Size = UDim2.new(1 / #STEPS, -6, 1, 0),
			LayoutOrder = i,
			BackgroundColor3 = Kit.color.paper,
			maxText = 18,
		}, function()
			step = i
			refresh()
		end)
		b.Parent = stepRow
	end
	-- the choices (left)
	list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = 6
	list.Parent = panel
	local ll = Instance.new("UIListLayout")
	ll.Padding = UDim.new(0, 4)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Parent = list
	-- the hero (middle)
	preview = Preview.new(panel, UDim2.fromScale(0.3, 0.6), UDim2.fromOffset(0, 0))
	nameLabel = Kit.label({
		Text = "",
		TextColor3 = Kit.color.paper,
		maxText = 30,
	})
	nameLabel.Parent = panel
	-- the detail card and the grid of pieces, colours and weapon looks (right)
	detail = Instance.new("ScrollingFrame")
	detail.BackgroundTransparency = 1
	detail.AutomaticCanvasSize = Enum.AutomaticSize.Y
	detail.CanvasSize = UDim2.new()
	detail.ScrollBarThickness = 6
	detail.Parent = panel
	local dl = Instance.new("UIListLayout")
	dl.Padding = UDim.new(0, 8)
	dl.SortOrder = Enum.SortOrder.LayoutOrder
	dl.Parent = detail
	card = Kit.frame({
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		BackgroundColor3 = Kit.color.ink,
	})
	card.Parent = detail
	local cp = Instance.new("UIPadding")
	cp.PaddingLeft, cp.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
	cp.PaddingTop, cp.PaddingBottom = UDim.new(0, 10), UDim.new(0, 12)
	cp.Parent = card
	local cl = Instance.new("UIListLayout")
	cl.Padding = UDim.new(0, 4)
	cl.SortOrder = Enum.SortOrder.LayoutOrder
	cl.Parent = card
	cardTitle = Kit.label({
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 1,
		TextColor3 = Kit.color.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		maxText = 28,
	})
	cardTitle.Parent = card
	cardSub = Kit.label({
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = 2,
		TextColor3 = Kit.color.muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Kit.bodyFont,
		maxText = 14,
	})
	cardSub.Parent = card
	cardBody = Kit.label({
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3,
		TextColor3 = Kit.color.paper,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		TextScaled = false,
		TextSize = 15,
		Font = Kit.bodyFont,
	})
	cardBody.Parent = card
	grid = Instance.new("Frame")
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.new(1, -8, 0, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.LayoutOrder = 2
	grid.Parent = detail
	local g = Instance.new("UIGridLayout")
	g.CellPadding = UDim2.fromOffset(6, 6)
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.Parent = grid
	-- the bottom bar
	status = Kit.label({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.new(0.5, 0, 0, 20),
		Position = UDim2.new(0.5, 0, 1, -T - 30),
		TextColor3 = Kit.color.paper,
		Font = Kit.bodyFont,
		maxText = 16,
	})
	status.Parent = panel
	backButton = Kit.button({
		Text = "BACK",
		AnchorPoint = Vector2.new(0, 1),
		Size = UDim2.fromOffset(140, T),
		Position = UDim2.new(0, 10, 1, -20),
		BackgroundColor3 = Kit.color.paper,
	}, function()
		step = math.max(1, step - 1)
		refresh()
	end)
	backButton.Parent = panel
	cancelButton = Kit.button({
		Text = "CANCEL",
		AnchorPoint = Vector2.new(0, 1),
		Size = UDim2.fromOffset(140, T),
		Position = UDim2.new(0, 160, 1, -20),
		BackgroundColor3 = Kit.color.paper,
	}, function()
		CreatorScreen.close()
	end)
	cancelButton.Parent = panel
	local rand = Kit.button({
		Text = "RANDOMIZE",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(170, T),
		Position = UDim2.new(0.5, 0, 1, -20),
		BackgroundColor3 = Kit.color.paper,
	}, randomize)
	rand.Parent = panel
	nextButton = Kit.button({
		Text = "NEXT",
		AnchorPoint = Vector2.new(1, 1),
		Size = UDim2.fromOffset(170, T),
		Position = UDim2.new(1, -16, 1, -20),
	}, function()
		if step < #STEPS then
			step += 1
			refresh()
		else
			finish()
		end
	end)
	nextButton.Parent = panel
	layout()
	local cam = Workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	end
end

-- opts: { mode, side, classIdx, pathOpen, step (a STEPS id) }
function CreatorScreen.open(opts: { [string]: any })
	mode = opts.mode or "edit"
	pending = false
	local p = State.profile
	look = LookCodec.read(p.look) or CreatorRules.defaultLook(Config)
	look.anime = State.hero.fxStyle == "Anime"
	titleId, nounId = p.titleId or 0, p.nounId or 0
	sideIdx = if (opts.side or State.hero.side) == "villain" then 2 else 1
	classIdx = if mode == "create"
		then 0
		else (opts.classIdx or table.find(Config.Classes.order, State.hero.classId) or 1)
	local cls = Config.Classes.order[classIdx]
	setIdx = if cls then table.find(AbilityRules.paths(Config, cls), p.startSet or "Volt") or 1 else 1
	mobIdx = table.find(Config.Move.mobilityOrder, State.hero.mobility or "flight") or 1
	pathOpen = if opts.pathOpen == nil then mode ~= "edit" else opts.pathOpen == true
	local carried = if (p.weapon or 0) ~= 0 then p.weapon else W.defaultWeapon
	weaponLook = WeaponRules.lookOf(profileView(), carried)
	family = (WeaponRules.get(Config, carried) or WeaponRules.get(Config, W.defaultWeapon)).family
	-- a new hero starts at the body; an edit opens on the looks (or the step asked for: the Weapon Rack)
	step = if mode == "edit" then 6 else 1
	for i, st in STEPS do
		if st.id == opts.step then
			step = i
		end
	end
	slot = "suit"
	colorTarget, weaponTarget = 1, 1
	cancelButton.Visible = mode == "edit"
	gui.Enabled = true
	layout()
	refresh()
end

function CreatorScreen.close()
	gui.Enabled = false
	pending = false
end

-- close only if it is open in this mode (the opening's Suit Up ending)
function CreatorScreen.closeMode(m: string)
	if gui.Enabled and mode == m then
		CreatorScreen.close()
	end
end

function CreatorScreen.isOpen(): boolean
	return gui ~= nil and gui.Enabled
end

function CreatorScreen.init()
	build()
	Net.listen("CreatorOpen", function(data)
		CreatorScreen.open(data)
	end)
	Net.listen("CreatorResult", function(data)
		pending = false
		if data.ok then
			CreatorScreen.close()
		else
			refresh()
			status.Text = REASONS[data.reason] or "Try again"
		end
	end)
	State.ProfileChanged:Connect(function()
		if gui.Enabled and not pending then
			refresh()
		end
	end)
end

return CreatorScreen
