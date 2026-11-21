-- CreatorScreen: "Who are you?" The old-RPG style creator from nate's hero creator plan (2026-11-16,
-- https://claude.ai/artifact/VeuJPWz6kKE6gGsUBmqQC9): tabs along the top (BODY > SIDE > ORIGIN > MOBILITY >
-- POWERS > WEAPON > APPEARANCE > PLAY), the choices on the left, the hero big in the middle showing each choice live
-- (hovering previews it), and a detail card on the right with a Complexity rating, a short description and
-- the keys; pieces, colours and the weapon's look are picked on the right too. Back, Randomize and Next sit
-- along the bottom. On phones the list moves to a drawer along the bottom.
-- * BODY: gender, build (Small, Medium, Large, Titan) and height; looks only.
-- * SIDE: The Vigil or The Dread Syndicate (new heroes only). ORIGIN (lore step 2): how the Spark woke, 5
--   picks, each a fixed line, a title and its crest (looks only; any hero changes it free). MOBILITY: 5 picks.
--   POWERS: archetype, path, Comic or Anime.
-- * WEAPON: a family, then a weapon; a new hero takes any playable Rack weapon free; its style, finish,
--   colours, glow and emblem.
-- * APPEARANCE: 23 slots in body areas, each with its pieces (locked ones say how to get them), its own
--   main, trim and glow colour (AUTO = the whole-hero colour) and a material; SKIN; COLORS (match all).
-- * PLAY: a Title and a Noun from two wheels, never typed; then DONE sends Hero.Create.
-- Modes: "create" (a brand-new character, before any story: creator first), "first" (a hero made before the
-- creator), "edit" (HQ or a safehouse).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
local Thumb = require(script.Parent.Thumb)
local Preview = require(script.Parent.Preview)
local State = require(script.Parent.Parent.State)

local CreatorScreen = {}

local C = Config.Creator
local B = C.body
local W = Config.Weapons
local T = Config.Ui.touchTarget
-- heroes wear the player's own avatar (Config.Creator.avatar, off since nate's 2026-11-17 call); the Body
-- step (gender, build, height) shows only with Config.Creator.bodyStep
local AVATAR = C.avatar.on == true
local STEPS = {
	{ id = "body", name = "Body" },
	{ id = "side", name = "Side" },
	{ id = "origin", name = "Origin" },
	{ id = "mobility", name = "Mobility" },
	{ id = "powers", name = "Powers" },
	{ id = "weapon", name = "Weapon" },
	{ id = "appearance", name = "Appearance", short = "Looks" }, -- short: the tab on a narrow screen (8 tabs)
	{ id = "play", name = "Play" },
}
-- the appearance list: body areas, then their slots (tab ids from Config.Creator, plus skin and colours)
local AREAS = {
	{ "BODY", { "skin", "colors" } },
	{ "HEAD", { "visage", "hair", "beard", "eyes", "face", "makeup", "head", "hat", "ears" } },
	{ "TORSO", { "shirt", "suit", "shoulders", "neck", "emblem" } },
	{ "ARMS", { "arms", "hands", "wrist" } },
	{ "WAIST AND LEGS", { "pants", "belt", "legs", "feet" } },
	{ "BACK", { "backpack", "back" } },
	{ "EXTRAS", { "aura", "trail", "voice" } },
}
local SLOT_NAMES = {
	skin = "Skin",
	colors = "Colours (match all)",
	suit = "Top",
	shirt = "Shirt",
	pants = "Pants",
	visage = "Face",
	face = "Face details",
	back = "Cape",
	head = "Mask",
	hands = "Gloves",
	feet = "Shoes",
	emblem = "Symbol",
	trail = "Flight trail",
	backpack = "Back bling",
	hat = "Headwear",
}
local FACE_SLOTS =
	{ visage = true, hair = true, beard = true, eyes = true, face = true, makeup = true, ears = true }
local BACK_SLOTS = { back = true, backpack = true }
-- slots with no NONE choice (every hero has a flight trail and a voice; a top too, unless heroes wear their
-- own avatar, whose clothes show with no suit)
local REQUIRED = {
	suit = not AVATAR and not C.clothes.on, -- with no suit, our classic Shirt and Pants show
	shirt = true,
	pants = true,
	visage = true,
	trail = true,
	voice = true,
}
-- on the player's own avatar, an empty slot shows the avatar's own item there (Shared.AvatarRules)
local OWN = {
	suit = true,
	legs = true,
	feet = true,
	hair = true,
	hat = true,
	face = true,
	beard = true,
	back = true,
	backpack = true,
	shoulders = true,
	neck = true,
	belt = true,
}
-- nate's playtest 4 (2026-11-20 22:04Z): "Shirts and pants merge into tops and legs". The everyday Shirt and
-- Pants show first in the Top and Legs lists; picking one takes the suit or legs piece off (it would cover it),
-- picking a suit or legs piece keeps the everyday one under it. The shirt and pants rows leave the list.
local MERGE: { [string]: string } = if not AVATAR and C.clothes.on
	then { suit = "shirt", legs = "pants" }
	else {}
local MERGED = {}
for top, under in MERGE do
	MERGED[under] = top
end
if AVATAR or not C.bodyStep then
	table.remove(STEPS, 1)
end
local REASONS = {
	locked = "That piece is not unlocked yet",
	piece = "That piece does not exist",
	color = "Pick colours from the palette",
	material = "Pick a material from the list",
	body = "Pick a gender, build and height",
	name = "Pick another name pair",
	pick = "Pick an archetype, a path and a mobility",
	origin = "Pick an origin",
	path = "Your archetype and path are set (one free change before level 10)",
	look = "Something went wrong: try again",
	scene = "Finish what you are doing first",
	loading = "Your hero is still loading. Tap again in a moment",
	combat = "Not during a fight",
	safehouse = "Change your look at your HQ or a safehouse",
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
local pieceGrid: Frame -- the slot's pieces as picture tiles (Thumb), above the colour grid
local tileParent: Frame? = nil -- where tile() puts its tile (nil: the colour grid)
local layoutPieces: () -> () -- sizes the piece grid's cells (pictures or text)
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
local originIdx = 0 -- Config.Creator.origins index (0 = not picked yet)
local pathOpen = true
local step = 1
local slot = "suit" -- the appearance slot open on the right
local family = "fists" -- the weapon family open on the left
local colorTarget = 1 -- the slot colour being edited: 1 main, 2 trim, 3 glow (COLORS: 1-3 hero, 4 hair, 5 eyes)
local weaponTarget = 1 -- the weapon colour being edited: 1 main, 2 trim, 3 glow
local cardFor: (() -> ())? = nil -- redraws the card for the current pick (after a hover ends)
local pending = false
local saveSent = 0
local statusHold = 0 -- a refusal stays on screen until then (os.clock)
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
		return (Config.Story.rep.labels[s.a :: string] or "City Reputation") .. " rank " .. (s.n or 0)
	elseif k == "fame" then
		return "Fame rank " .. (s.n or 0)
	elseif k == "boss" then
		local b = Config.Boss.bosses[s.a or ""]
		local tier = ({ "join", "contributor", "MVP" })[s.n or 1]
		return (if b then b.name else "World boss") .. ": " .. tier
	elseif k == "mission" then
		local m = Config.Story.missions[s.n or 0]
		return "Mission: " .. (if m then m.name else "?")
	elseif k == "chains" then
		local n = s.n or 1
		return if n == 1 then "Finish a side quest chain" else string.format("Finish %d side quest chains", n)
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

-- Can DONE save, and if not: why, and the step that fixes it (DONE jumps there; nate's playtest 2026-11-18,
-- "the play/done button dont work sometimes": a grey DONE with a small line under it read as broken)
local function canFinish(): (boolean, string?, string?)
	if titleId == 0 or nounId == 0 then
		return false, "Pick a Title and a Noun for your hero name", "play"
	end
	if not CreatorRules.nameOk(Config, titleId, nounId) then
		return false, REASONS.name, "play"
	end
	if not CreatorRules.originOk(Config, originIdx) then
		return false, "Pick how your Spark woke (ORIGIN)", "origin"
	end
	if classIdx == 0 then
		return false, "Pick an archetype and a path (POWERS)", "powers"
	end
	local ok, why = weaponStatus(weaponLook.id)
	if not ok then
		local w = WeaponRules.get(Config, weaponLook.id)
		return false,
			(if w then w.name .. ": " else "") .. (if why ~= "" then why else "Pick a weapon (WEAPON)"),
			"weapon"
	end
	return true, nil, nil
end

-- first-30 (2026-11-20): what the step on screen still needs before NEXT, or nil. Pressing NEXT through ORIGIN
-- with nothing picked used to carry on and then bounce the player back from PLAY; now NEXT says why there.
local function stepWhy(id: string): string?
	if id == "origin" and not CreatorRules.originOk(Config, originIdx) then
		return "Pick how your Spark woke to go on"
	elseif id == "powers" and classIdx == 0 then
		return "Pick an archetype and a path to go on"
	end
	return nil
end

local function clear(frame: Instance)
	for _, c in frame:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local refresh: () -> ()
local refuse: (why: string, fix: string?) -> ()
local goStep: (i: number) -> ()

-- the hero in the middle: the current look, or a look being hovered
local hoverToken = 0
local function showPreview(l: any?, wl: any?)
	hoverToken += 1 -- a hover still waiting is overtaken by this look
	preview.set(l or look, wl or weaponLook)
end
-- A hover (or its end) previews once the pointer rests HOVER_REST s: sweeping over the rows and tiles on the way
-- to NEXT builds nothing (fix-respawn, 2026-11-19: each hover rebuilt the whole hero at once, so the press felt
-- dead); Preview builds the last ask once per frame and skips a look it already wears.
local HOVER_REST = 0.08
local function hoverPreview(l: any?, wl: any?)
	hoverToken += 1
	local my = hoverToken
	task.delay(HOVER_REST, function()
		if my == hoverToken and gui.Enabled then
			preview.set(l or look, wl or weaponLook)
		end
	end)
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
	hover: (() -> ())?,
	pic: Thumb.Pic?
)
	rowOrder += 1
	local b = Kit.button({
		Text = "",
		Size = UDim2.new(1, -8, 0, T),
		LayoutOrder = rowOrder,
		BackgroundColor3 = if on then Kit.color.gold elseif locked then Kit.color.muted else Kit.color.paper,
	}, pick)
	-- a weapon row's picture at its left (2026-11-19 thumbnails), the name beside it
	local inset = 0
	if pic then
		local img = Thumb.image(pic, {
			Size = UDim2.new(0, T - 8, 1, 4),
			Position = UDim2.fromOffset(-4, -2),
			ImageTransparency = if locked then 0.4 else 0,
		})
		img.Parent = b
		inset = T - 8
	end
	local l = Kit.label({
		Text = text,
		Size = UDim2.new(if sub then 0.58 else 1, -12 - inset, 1, 0),
		Position = UDim2.fromOffset(10 + inset, 0),
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
			hoverPreview()
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
local PIC_CAPTION = 22 -- a picture tile's name line under its picture
local function tile(
	text: string,
	sub: string?,
	on: boolean,
	locked: boolean,
	pick: () -> (),
	hover: (() -> ())?,
	pic: Thumb.Pic?
)
	tileOrder += 1
	local b = Kit.button({
		Text = "",
		LayoutOrder = tileOrder,
		BackgroundColor3 = if on then Kit.color.gold elseif locked then Kit.color.muted else Kit.color.paper,
	}, pick)
	if pic then
		-- a picture tile (2026-11-19): the piece's thumbnail, its name under it, how to get it if locked
		Thumb.fill(b, pic, text, sub, locked, PIC_CAPTION)
		if hover then
			b.MouseEnter:Connect(hover)
			b.MouseLeave:Connect(function()
				hoverPreview()
			end)
		end
		b.Parent = tileParent or grid
		return b
	end
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
			hoverPreview()
		end)
	end
	b.Parent = tileParent or grid
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
	-- nate's playtest (2026-11-21: "the customization stuff that has the arrows next to it ... i cant see the text
	-- in the middle"): two 56 px arrow buttons left about 6 px of a 118 px tile for the words. Now the words fill
	-- the tile (what it changes on top, the pick under it), thin arrows sit at its edges, and each outer third of
	-- the tile is the tap for that arrow (tap targets stay thumb-sized; the words are never covered).
	tileOrder += 1
	local f = Kit.frame({ LayoutOrder = tileOrder, BackgroundColor3 = Kit.color.paper })
	local EDGE = 14
	local top = Kit.label({
		Text = label,
		Size = UDim2.new(1, -2 * EDGE, 0.4, 0),
		Position = UDim2.new(0, EDGE, 0, 2),
		TextColor3 = Kit.color.muted,
		Font = Kit.bodyFont,
		maxText = 11,
	})
	top.Parent = f
	local l = Kit.label({
		Text = value,
		Size = UDim2.new(1, -2 * EDGE, 0.55, -2),
		Position = UDim2.new(0, EDGE, 0.42, 0),
		TextColor3 = Kit.color.ink,
		Font = Kit.bodyFont,
		maxText = 15,
	})
	l.Parent = f
	for i, dir in { -1, 1 } do
		local glyph = Kit.label({
			Text = if dir < 0 then "◀" else "▶",
			Size = UDim2.new(0, EDGE, 1, 0),
			Position = if i == 1 then UDim2.new() else UDim2.new(1, -EDGE, 0, 0),
			TextColor3 = Kit.color.gold,
			maxText = 14,
		})
		glyph.Parent = f
		local b = Kit.button({
			Text = "",
			BackgroundTransparency = 1,
			Size = UDim2.new(0.34, 0, 1, 0),
			Position = if i == 1 then UDim2.new() else UDim2.new(0.66, 0, 0, 0),
			ZIndex = 3,
			ink = false,
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
		hoverPreview(l, nil)
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
	{ "Hero", "Join The Vigil: earn Trust, protect the city. Bright skies." },
	{ "Villain", "Join The Dread Syndicate: earn Fear, rule the city. Storm-red skies." },
}
local function drawSide()
	preview.focus("full")
	local creating = mode == "create"
	header("SIDE")
	for i, s in SIDES do
		row(s[1], if creating then nil else "picked at the start", sideIdx == i, not creating, function()
			if creating then
				sideIdx = i
				refresh()
			else
				status.Text = "Your side was picked when this hero was made"
			end
		end, function()
			setCard(s[1], nil, s[2])
		end)
	end
	cardFor = function()
		local s = SIDES[sideIdx]
		setCard(s[1], if creating then "Pick once for this hero" else "Picked when this hero was made", s[2])
	end
	cardFor()
end

----------------------------------------------------------------------------------------------- ORIGIN
-- How the Spark woke (lore step 2): a fixed line, a title and the origin's crest, which picking puts on the
-- Symbol slot (change it under APPEARANCE). Looks only; any hero changes it free.
local function originCard(i: number)
	local o = C.origins[i]
	local crest = CreatorRules.originPiece(Config, i)
	setCard(
		o.name,
		"Title: " .. o.title,
		string.format("%s\n\nLook: %s\n%s", o.line, if crest then crest.name else "", C.originNote)
	)
end
local function drawOrigin()
	preview.focus("full")
	header("HOW YOUR SPARK WOKE")
	for i, o in C.origins do
		local crest = CreatorRules.originPiece(Config, i)
		row(o.name, o.title, originIdx == i, false, function()
			originIdx = i
			if crest then
				look.pieces.emblem = crest.index
			end
			refresh()
		end, function()
			originCard(i)
			if crest then
				hoverLook(function(l)
					l.pieces.emblem = crest.index
				end)()
			end
		end)
	end
	cardFor = function()
		if C.origins[originIdx] then
			originCard(originIdx)
		else
			setCard("Origin", "Pick how your Spark woke", C.originNote)
		end
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
		local b = row(m.name, nil, mobIdx == i, false, function()
			mobIdx = i
			refresh()
		end, function()
			mobilityCard(i)
		end)
		-- gap-icons2: the pick's comic icon before its name (text only while the sheet is not uploaded)
		local l = b:FindFirstChildOfClass("TextLabel")
		if l then
			Kit.lead(l, "mobility", id, T - 16)
		end
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
		hoverPreview(nil, wl)
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
	-- the swing trail (list-combat 2026-11-20): only the ones this weapon's Mastery has earned; the next to earn
	-- shows its level
	local fam = W.list[wl.id] and W.list[wl.id][2]
	if W.swingTrail.families[fam] then
		local points = WeaponRules.state(profileView(), wl.id).mastery or 0
		local open = {}
		for i = 0, #W.swingTrail.looks do
			if WeaponRules.trailOpen(Config, points, i) then
				table.insert(open, i)
			end
		end
		local nextRow = W.swingTrail.looks[#open]
		local name = W.trails[(wl.trail or 0) + 1] or "None"
		if nextRow then
			name ..= "  (next: Mastery " .. nextRow.level .. ")"
		end
		cycler("SWING TRAIL", name, function(d)
			local at = table.find(open, wl.trail or 0) or 1
			wl.trail = open[wrapIndex(at + d, #open)]
			refresh()
		end)
	end
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
			end, hoverWeapon(w.id), Thumb.key(Thumb.weaponKey(w.id)))
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
	-- the slot's own main, trim and glow colour (AUTO = the whole-hero colour) and its material; on a merged
	-- Top or Legs with no suit or legs piece on, the everyday Shirt or Pants under it
	local tslot = if MERGE[slot] and (look.pieces[slot] or 0) == 0 then MERGE[slot] else slot
	look.tints = look.tints or {}
	local t = look.tints[tslot] or { 0, 0, 0 }
	for i, n in { "MAIN", "TRIM", "GLOW" } do
		tile(n, nil, colorTarget == i, false, function()
			colorTarget = i
			refresh()
		end)
	end
	local mats = look.mats or {}
	local m = mats[tslot] or 0
	cycler("MATERIAL", if m == 0 then "Own" else C.materialNames[m], function(d)
		look.mats = look.mats or {}
		look.mats[tslot] = (m + d) % (#C.materials + 1)
		refresh()
	end)
	local target = math.clamp(colorTarget, 1, 3)
	swatch(nil, (t[target] or 0) == 0, function()
		local nt = table.clone(t)
		nt[target] = 0
		look.tints[tslot] = if nt[1] == 0 and nt[2] == 0 and nt[3] == 0 then nil else nt
		refresh()
	end, "AUTO")
	for i, c in C.palette do
		swatch(rgb(c), t[target] == i, function()
			local nt = table.clone(t)
			nt[target] = i
			look.tints[tslot] = nt
			refresh()
		end)
	end
end
local function drawSkin()
	if AVATAR then
		-- the avatar's own skin colour (0)
		tile("MY OWN", nil, (look.skin or 0) == 0, false, function()
			look.skin = 0
			refresh()
		end)
	end
	for i, c in C.skins do
		local fantasy = C.fantasySkins[i]
		swatch(rgb(c), look.skin == i, function()
			look.skin = i
			refresh()
		end, if fantasy then fantasy.name else nil)
	end
end
local function drawMatchAll()
	-- catalog hair and faces carry their own colours (no HAIR or EYES tint since 2026-11-18)
	local names = { "PRIMARY", "SECONDARY", "ACCENT" }
	colorTarget = math.min(colorTarget, 3)
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
-- A Robux pack piece's tile (nate's playtest 4: "Robux items should look higher quality than everything else"):
-- a thick gold edge and a gold star in the corner, so premium pieces stand out in every list
local function premiumBadge(b: GuiObject)
	Kit.stroke(b, Kit.color.gold, 3)
	local star = Kit.label({
		Text = "★",
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(20, 20),
		Position = UDim2.new(1, -2, 0, 2),
		TextColor3 = Kit.color.gold,
		ZIndex = 4,
		maxText = 18,
	})
	star.Parent = b
end
local function drawPieces()
	local pv = profileView()
	local cur = look.pieces[slot] or 0
	tileParent = pieceGrid
	local under = MERGE[slot]
	if under then
		-- the everyday clothes first (always free), lit while no suit or legs piece covers them
		local curUnder = look.pieces[under] or 0
		for _, p in CreatorRules.index(Config).byTab[under] or {} do
			if not CreatorRules.offered(Config, p) then
				continue
			end
			tile(
				p.name,
				nil,
				cur == 0 and curUnder == p.index,
				false,
				function()
					look.pieces[under] = p.index
					look.pieces[slot] = 0
					refresh()
				end,
				hoverLook(function(l)
					l.pieces[under] = p.index
					l.pieces[slot] = 0
				end),
				Thumb.creator(p)
			)
		end
	elseif not REQUIRED[slot] then
		tile(
			if AVATAR and OWN[slot] then "MY OWN" else "NONE",
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
		if not CreatorRules.offered(Config, p) then
			continue -- a drawn style kept for NPCs (catalog tabs) or a retired tab
		end
		local have = CreatorRules.wearable(Config, pv, p, originIdx)
		local glyph = Thumb.glyph(p)
		local t = tile(
			if glyph then glyph .. " " .. p.name else p.name,
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
			end),
			Thumb.creator(p)
		)
		if p.source.kind == "pack" or p.source.kind == "starter" then
			premiumBadge(t)
		end
	end
	tileParent = nil
	-- the slot's pieces show as pictures once any has one (taller cells), else as today's text tiles
	local g = pieceGrid:FindFirstChildOfClass("UIGridLayout")
	if g then
		local pics = false
		for _, c in pieceGrid:GetChildren() do
			if c:FindFirstChild("Thumb") then
				pics = true
				break
			end
		end
		pieceGrid:SetAttribute("Pictures", pics)
		layoutPieces()
	end
end
local function drawAppearance()
	preview.focus(if FACE_SLOTS[slot] then "face" elseif BACK_SLOTS[slot] then "back" else "full")
	for _, area in AREAS do
		header(area[1])
		for _, id in area[2] do
			if CreatorRules.hidden(Config, id) or MERGED[id] then
				continue -- retired (our own eyes, face details, makeup), or merged into Top and Legs
			end
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
		local count = 0
		for _, q in CreatorRules.index(Config).byTab[slot] or {} do
			if CreatorRules.offered(Config, q) then
				count += 1
			end
		end
		local under = MERGE[slot]
		if under then
			for _, q in CreatorRules.index(Config).byTab[under] or {} do
				if CreatorRules.offered(Config, q) then
					count += 1
				end
			end
		end
		local natural = C.naturalSkins or #C.skins
		local sub = if slot == "skin"
			then string.format("%d tones and %d fantasy skins", natural, #C.skins - natural)
			elseif
				slot == "colors"
			then "Sets the whole hero; any slot can then have its own" -- facial hair is Roblox catalog items only (gap-villains, 2026-11-19), free, in their own colours

			elseif slot == "beard" then count .. " Roblox catalog items, free. Each keeps its own colours."
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
		if
			slot ~= "voice"
			and slot ~= "aura"
			and slot ~= "trail"
			and slot ~= "hair"
			and slot ~= "visage"
			and slot ~= "beard"
		then
			drawSlotColors()
		end
	end
end

----------------------------------------------------------------------------------------------- PLAY
-- the classic clothes in words ("Hoodie and Jeans", or the suit's name over them)
local function clothesLine(): string
	local function name(tab: string): string?
		local i = look.pieces[tab] or 0
		local p = if i > 0 then CreatorRules.piece(Config, tab, i) else nil
		return p and p.name
	end
	local top = name("suit") or name("shirt") or ""
	local bottom = name("legs") or name("pants") or ""
	return top .. (if top ~= "" and bottom ~= "" then " and " else "") .. bottom
end
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
				"%s\n%s, %s, %s\n%s\n%s",
				if AVATAR
					then "Your own avatar"
					elseif not C.bodyStep then clothesLine()
					else string.format(
						"%s %s, %s",
						B.genders[look.gender] or "",
						b.name,
						string.lower(B.heightNames[look.height] or "")
					),
				SIDES[sideIdx][1],
				if C.origins[originIdx] then C.origins[originIdx].title else "no origin",
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
	origin = drawOrigin,
	mobility = drawMobility,
	powers = drawPowers,
	weapon = drawWeapon,
	appearance = drawAppearance,
	play = drawPlay,
}

-- A step's list or the hero preview that fails to draw never stops the rest of the redraw (nate's playtest,
-- 2026-11-19: "next button in character creator still requires me to keep hitting it": an error part way
-- through left the old step on screen, so a press looked lost)
local function safely(label: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn("[CreatorScreen] " .. label .. ": " .. tostring(err))
	end
end

-- Change step (NEXT, BACK, the step row). fix-respawn (nate, 2026-11-19: "Next button in character creator is
-- still super unresponsive"): the press shows at once (the step row's gold, NEXT's text, BACK; Kit's bounce and
-- click already ran), and the step's lists (up to 500 picture tiles) and the hero draw on the next frame, so the
-- change is on screen before the heavy draw. Presses while it waits each still count (two NEXTs: two steps).
local stepQueued = false
local function markStep()
	for _, b in stepRow:GetChildren() do
		if b:IsA("TextButton") then
			b.BackgroundColor3 = if b.Name == STEPS[step].id then Kit.color.gold else Kit.color.paper
		end
	end
	local last = step == #STEPS
	nextButton.Text = if pending
		then "SAVING..."
		elseif last then (if mode == "create" then "PLAY" else "DONE")
		else "NEXT"
	backButton.Visible = step > 1
end
goStep = function(i: number)
	step = math.clamp(i, 1, #STEPS)
	markStep()
	if stepQueued then
		return
	end
	stepQueued = true
	task.delay(0, function()
		stepQueued = false
		if gui.Enabled then
			refresh()
		end
	end)
end

refresh = function()
	stepQueued = false
	clear(list)
	clear(grid)
	clear(pieceGrid)
	pieceGrid:SetAttribute("Pictures", false)
	rowOrder, tileOrder = 0, 0
	tileParent = nil
	cardFor = nil
	for _, b in stepRow:GetChildren() do
		if b:IsA("TextButton") then
			b.BackgroundColor3 = if b.Name == STEPS[step].id then Kit.color.gold else Kit.color.paper
		end
	end
	safely(STEPS[step].id, DRAW[STEPS[step].id])
	grid.Visible = #grid:GetChildren() > 1
	pieceGrid.Visible = #pieceGrid:GetChildren() > 1
	layoutPieces()
	nameLabel.Text = string.upper(heroName())
	local ok, why = canFinish()
	local last = step == #STEPS
	-- a new hero's last button is PLAY: the prologue starts once it saves (fix-flow, 2026-11-19)
	nextButton.Text = if pending
		then "SAVING..."
		elseif last then (if mode == "create" then "PLAY" else "DONE")
		else "NEXT"
	local need = if last then nil else stepWhy(STEPS[step].id)
	nextButton.BackgroundColor3 = if (not last and not need) or (last and ok and not pending)
		then Kit.color.gold
		else Kit.color.muted
	backButton.Visible = step > 1
	if not pending and os.clock() > statusHold then
		status.Text = if need then need elseif ok or not last then "" else (why or "")
		status.TextColor3 = Kit.color.paper
	end
	safely("preview", function()
		showPreview()
	end)
end

-- A DONE that cannot save yet: say why in gold, and open the step that fixes it
refuse = function(why: string, fix: string?)
	if fix then
		for i, st in STEPS do
			if st.id == fix and i ~= step then
				step = i
				refresh()
			end
		end
	end
	status.Text = why
	status.TextColor3 = Kit.color.gold
	statusHold = os.clock() + 4
	Kit.bounce(status)
end

local function finish()
	local ok, why, fix = canFinish()
	if not ok then
		refuse(why or "", fix)
		return
	end
	if pending then
		-- a press while the save is on its way: say so (never a silent press)
		status.Text = "Saving... one moment"
		status.TextColor3 = Kit.color.gold
		Kit.bounce(status)
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
		WeaponRules.encodeLook(weaponLook),
		originIdx
	)
	refresh()
	-- no answer: let them try again (spec: every remote call has an error state)
	local sentAt = os.clock()
	saveSent = sentAt
	task.delay(6, function()
		if pending and saveSent == sentAt and gui.Enabled then
			pending = false
			refresh()
			refuse("Could not save. Tap DONE again", nil)
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
	elseif id == "origin" then
		originIdx = rng:int(1, #C.origins)
		local crest = CreatorRules.originPiece(Config, originIdx)
		if crest then
			look.pieces.emblem = crest.index
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
		local keep = {
			gender = look.gender,
			build = look.build,
			height = look.height,
			anime = look.anime,
			skin = look.skin,
		}
		look = l
		look.gender, look.build, look.height, look.anime = keep.gender, keep.build, keep.height, keep.anime
		if AVATAR then
			look.skin = keep.skin -- randomizing the look keeps your own skin
		end
	elseif id == "play" then
		titleId, nounId = t, n
	end
	refresh()
end

-- Layout (phone pass): landscape phones keep the three columns (choices, hero, card) and slim the chrome
-- (no title, 40 px step tabs, 44 px bottom buttons); only a narrow (portrait) screen gets the bottom drawer.
local titleLabel: TextLabel
local randButton: TextButton
local function layout()
	local area = Kit.area()
	local tight = Kit.compact()
	local narrow = area.X < 560
	local tab = if tight then 40 else T
	local bar = if tight then 44 else T
	local below = if tight then 8 else 20 -- the bottom bar's gap to the screen edge
	titleLabel.Visible = not tight
	stepRow.Position = UDim2.fromOffset(10, if tight then 6 else 50)
	stepRow.Size = UDim2.new(1, -20, 0, tab)
	-- with the Body step's 8 tabs a long name gets its short form on a narrow screen (fix-flow, the phone pass)
	for _, st in STEPS do
		local b = stepRow:FindFirstChild(st.id)
		if b and b:IsA("TextButton") then
			b.Text = string.upper(if area.X < 700 and st.short then st.short else st.name)
		end
	end
	local top = (if tight then 6 else 50) + tab + (if tight then 8 else 12)
	local bottom = bar + below + (if tight then 24 else 20)
	status.Position = UDim2.new(0.5, 0, 1, -bar - below - 2)
	local bw, rw = if tight then 110 else 140, if tight then 140 else 170
	for i, b in { backButton, cancelButton, randButton, nextButton } do
		b.Size = UDim2.fromOffset(if i <= 2 then bw else rw, bar)
	end
	backButton.Position = UDim2.new(0, 10, 1, -below)
	cancelButton.Position = UDim2.new(0, 20 + bw, 1, -below)
	randButton.Position = UDim2.new(0.5, if tight then 50 else 0, 1, -below)
	nextButton.Position = UDim2.new(1, -16, 1, -below)
	if narrow then
		list.Size = UDim2.new(1, -20, 0.34, -bottom)
		list.Position = UDim2.new(0, 10, 0.66, 0)
		preview.frame.Size = UDim2.new(0.45, -10, 0.66, -top - 40)
		preview.frame.Position = UDim2.fromOffset(10, top)
		detail.Size = UDim2.new(0.55, -20, 0.66, -top - 6)
		detail.Position = UDim2.new(0.45, 10, 0, top)
		nameLabel.Position = UDim2.new(0, 10, 0.66, -8)
		nameLabel.Size = UDim2.new(0.45, -10, 0, 30)
	else
		local nameH = if tight then 28 else 34
		list.Size = UDim2.new(0.26, -10, 1, -top - bottom)
		list.Position = UDim2.fromOffset(10, top)
		preview.frame.Size = UDim2.new(0.36, -10, 1, -top - bottom - nameH - 6)
		preview.frame.Position = UDim2.new(0.26, 5, 0, top)
		detail.Size = UDim2.new(0.38, -15, 1, -top - bottom)
		detail.Position = UDim2.new(0.62, 5, 0, top)
		nameLabel.Position = UDim2.new(0.26, 5, 1, -bottom - nameH)
		nameLabel.Size = UDim2.new(0.36, -10, 0, nameH)
	end
	local g = grid:FindFirstChildOfClass("UIGridLayout")
	if g then
		g.CellSize = UDim2.fromOffset(if narrow or tight then 96 else 118, (if tight then 44 else T) + 12)
	end
	layoutPieces()
end

-- picture tiles are square pictures over a name line (phones: 84 wide, PC 104); text tiles keep the colour grid's
layoutPieces = function()
	local g = pieceGrid and pieceGrid:FindFirstChildOfClass("UIGridLayout")
	if not g then
		return
	end
	local tight = Kit.compact()
	local narrow = Kit.area().X < 560
	local small = narrow or tight
	if pieceGrid:GetAttribute("Pictures") then
		local w = if small then 84 else 104
		g.CellSize = UDim2.fromOffset(w, w + PIC_CAPTION - 4)
	else
		g.CellSize = UDim2.fromOffset(if small then 96 else 118, (if tight then 44 else T) + 12)
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
	titleLabel = Kit.label({
		Text = "WHO ARE YOU?",
		Size = UDim2.new(0, 260, 0, 40),
		Position = UDim2.fromOffset(10, 6),
		TextColor3 = Kit.color.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		maxText = 34,
	})
	titleLabel.Parent = panel
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
			onDown = true,
		}, function()
			goStep(i)
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
	-- turn the hero (nate's playtest, 2026-11-18: "allow me to rotate character"): drag it, or tap these; a
	-- controller's shoulder buttons turn it too
	for i, dir in { -1, 1 } do
		local b = Kit.button({
			Name = if dir < 0 then "TurnLeft" else "TurnRight",
			Text = if dir < 0 then "⟲" else "⟳",
			AnchorPoint = Vector2.new(if dir < 0 then 0 else 1, 1),
			Size = UDim2.fromOffset(T, T),
			Position = UDim2.new(if dir < 0 then 0 else 1, if dir < 0 then 6 else -6, 1, -6),
			BackgroundColor3 = Kit.color.paper,
			LayoutOrder = i,
			maxText = 26,
		}, function()
			preview.turn(dir * math.pi / 4)
		end)
		b.Parent = preview.frame
	end
	local hint = Kit.label({
		Text = "Drag to turn",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.new(1, -2 * T - 24, 0, 18),
		Position = UDim2.new(0.5, 0, 1, -10),
		TextColor3 = Kit.color.muted,
		Font = Kit.bodyFont,
		maxText = 14,
	})
	hint.Parent = preview.frame
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
	pieceGrid = Instance.new("Frame")
	pieceGrid.Name = "Pieces"
	pieceGrid.BackgroundTransparency = 1
	pieceGrid.Size = UDim2.new(1, -8, 0, 0)
	pieceGrid.AutomaticSize = Enum.AutomaticSize.Y
	pieceGrid.LayoutOrder = 2
	pieceGrid.Parent = detail
	local pg = Instance.new("UIGridLayout")
	pg.CellPadding = UDim2.fromOffset(6, 6)
	pg.SortOrder = Enum.SortOrder.LayoutOrder
	pg.Parent = pieceGrid
	grid = Instance.new("Frame")
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.new(1, -8, 0, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.LayoutOrder = 3
	grid.Parent = detail
	local g = Instance.new("UIGridLayout")
	g.CellPadding = UDim2.fromOffset(6, 6)
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.Parent = grid
	-- the bottom bar
	status = Kit.label({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.new(0.6, 0, 0, 26),
		Position = UDim2.new(0.5, 0, 1, -T - 30),
		TextColor3 = Kit.color.paper,
		TextStrokeTransparency = 0.4,
		Font = Kit.bodyFont,
		maxText = 20,
	})
	status.Parent = panel
	backButton = Kit.button({
		Text = "BACK",
		onDown = true, -- fix-respawn: a press counts on the way down (nothing before the release can lose it)
		AnchorPoint = Vector2.new(0, 1),
		Size = UDim2.fromOffset(140, T),
		Position = UDim2.new(0, 10, 1, -20),
		BackgroundColor3 = Kit.color.paper,
	}, function()
		goStep(math.max(1, step - 1))
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
	randButton = Kit.button({
		Text = "RANDOMIZE",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(170, T),
		Position = UDim2.new(0.5, 0, 1, -20),
		BackgroundColor3 = Kit.color.paper,
	}, randomize)
	randButton.Parent = panel
	nextButton = Kit.button({
		Text = "NEXT",
		onDown = true, -- fix-respawn: a press counts on the way down (nothing before the release can lose it)
		AnchorPoint = Vector2.new(1, 1),
		Size = UDim2.fromOffset(170, T),
		Position = UDim2.new(1, -16, 1, -20),
	}, function()
		local need = if step < #STEPS then stepWhy(STEPS[step].id) else nil
		if need then
			refuse(need, nil) -- (first-30) stay and say what to pick
		elseif step < #STEPS then
			goStep(step + 1)
		else
			finish()
		end
	end)
	nextButton.Parent = panel
	layout()
	Kit.LayoutChanged:Connect(layout)
end

-- opts: { mode, side, classIdx, pathOpen, origin, step (a STEPS id), slot (an appearance slot) }
function CreatorScreen.open(opts: { [string]: any })
	mode = opts.mode or "edit"
	pending = false
	local p = State.profile
	look = CreatorRules.offeredLook(Config, LookCodec.read(p.look) or CreatorRules.defaultLook(Config))
	look.anime = State.hero.fxStyle == "Anime"
	titleId, nounId = p.titleId or 0, p.nounId or 0
	if titleId == 0 or nounId == 0 or not CreatorRules.nameOk(Config, titleId, nounId) then
		-- a new hero starts with a random name pair (changed any time on PLAY), so DONE never waits on it
		local _, t, n = CreatorRules.randomize(Config, profileView(), rng)
		titleId, nounId = t, n
	end
	sideIdx = if (opts.side or State.hero.side) == "villain" then 2 else 1
	classIdx = if mode == "create"
		then 0
		else (opts.classIdx or table.find(Config.Classes.order, State.hero.classId) or 1)
	local cls = Config.Classes.order[classIdx]
	setIdx = if cls then table.find(AbilityRules.paths(Config, cls), p.startSet or "Volt") or 1 else 1
	mobIdx = table.find(Config.Move.mobilityOrder, State.hero.mobility or "flight") or 1
	-- a new hero picks an origin; anyone else starts on their saved one
	originIdx = if mode == "create" then 0 else (opts.origin or p.origin or 0)
	pathOpen = if opts.pathOpen == nil then mode ~= "edit" else opts.pathOpen == true
	local carried = if (p.weapon or 0) ~= 0 then p.weapon else W.defaultWeapon
	weaponLook = WeaponRules.lookOf(profileView(), carried)
	family = (WeaponRules.get(Config, carried) or WeaponRules.get(Config, W.defaultWeapon)).family
	-- a new hero starts at the first step; an edit opens on the looks (or the step asked for: the Weapon Rack)
	local want = opts.step or (if mode == "edit" then "appearance" else nil)
	step = 1
	for i, st in STEPS do
		if st.id == want then
			step = i
		end
	end
	slot = opts.slot or (if C.clothes.on then "shirt" else "suit") -- opts.slot: an appearance slot to open on
	colorTarget, weaponTarget = 1, 1
	cancelButton.Visible = mode == "edit"
	gui.Enabled = true
	layout()
	refresh()
	Kit.padFocus(gui) -- a controller starts on the first button (onboarding check)
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
	-- catalog hair arrives a few seconds after boot (CatalogLookService): redraw the hero once it lands
	task.spawn(function()
		local lib = ReplicatedStorage:WaitForChild("CatalogLooks", 60)
		if not lib then
			return
		end
		local queued = false
		lib.ChildAdded:Connect(function()
			if queued then
				return
			end
			queued = true
			task.delay(0.5, function()
				queued = false
				if gui.Enabled and not pending then
					showPreview()
				end
			end)
		end)
	end)
	-- a controller's shoulder buttons turn the hero
	game:GetService("UserInputService").InputBegan:Connect(function(input, _processed)
		if not gui.Enabled then
			return
		end
		if input.KeyCode == Enum.KeyCode.ButtonL1 then
			preview.turn(-math.pi / 4)
		elseif input.KeyCode == Enum.KeyCode.ButtonR1 then
			preview.turn(math.pi / 4)
		end
	end)
	Net.listen("CreatorOpen", function(data)
		CreatorScreen.open(data)
	end)
	Net.listen("CreatorResult", function(data)
		pending = false
		if data.ok then
			CreatorScreen.close()
		else
			refresh()
			refuse(REASONS[data.reason] or "Try again", nil)
		end
	end)
	-- a profile sync redraws the lists, but never under a press that is still held (the tile or row being
	-- pressed would be rebuilt and the tap lost): it waits for the release
	local redrawQueued = false
	State.ProfileChanged:Connect(function()
		-- fix-respawn (2026-11-19): a wallet-only sync (Credits, Renown, XP: any reward, any kill) redrew the whole
		-- creator, its up to 500 tiles and the hero, under the player's pointer; the creator reads no wallet, so
		-- only a level change (level-gated pieces) redraws it
		if State.syncWalletOnly and not State.syncLevelChanged then
			return
		end
		if redrawQueued then
			return
		end
		redrawQueued = true
		task.spawn(function()
			local UIS = game:GetService("UserInputService")
			local t0 = os.clock()
			local function held(): boolean
				local ok, down = pcall(function()
					return UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
				end)
				return ok and down == true
			end
			while held() and os.clock() - t0 < 3 do
				task.wait(0.05)
			end
			redrawQueued = false
			if gui.Enabled and not pending then
				refresh()
			end
		end)
	end)
end

return CreatorScreen
