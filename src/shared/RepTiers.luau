--!strict
-- RepTiers: "The city remembers" (nate's lore, build plan step 12; Config.Remembers). Pure, so Lune tests it.
-- Vigil Trust (heroes) and Syndicate Fear (villains) open side cosmetics by tier. Nothing here changes a stat:
-- styles are looks (Gizmo's bench, earned Credits only), titles are words, the hideout dressing is props.
-- * Tiers are the 5 reputation ranks (Config.Story.rep.ranks) on the hero's own side's track.
-- * styles / style / canBuy: the side styles (Config.Gear.styles rows with tier "Rep") and their gate: your
--   own side's track only, at its tier.
-- * titles: the tier titles a character holds (ids titleBase + track index x 10 + tier).
-- * unlocks: what reaching a tier opens (for the toast and the tests).
-- * dressing: the HQ cell's tiered props by side (the Safehouse's thank-you notes, Patch's hacking rig and the
--   hero relic case; the Foundry's loot vault, trophy screen and captured Crane robot). Offsets from the cell's
--   centre, y up from its floor. PLACEHOLDER ART: part-built.
-- * reaction: how a citizen reacts to a hero near it (cheer, flinch or nothing), by side, tier and distance.
-- * radioSelf / radioAbout: Patch's fixed lines with a safe hero name put in; mention: who the news names.
-- * act1 / perHour / pace: the pacing check (hours of open-world play to each tier after Act 1).

local StoryPlan = if script then require(script.Parent.StoryPlan) else (require :: any)("./StoryPlan")
local GearMath = if script then require(script.Parent.GearMath) else (require :: any)("./GearMath")

local RepTiers = {}

RepTiers.MAX = 5

function RepTiers.side(side: string?): string
	return if side == "villain" then "villain" else "hero"
end

-- The track a side earns ("vigil" or "syndicate")
function RepTiers.track(Config: any, side: string?): string
	return Config.Remembers.tracks[RepTiers.side(side)]
end

-- The side a track belongs to
function RepTiers.sideOf(Config: any, track: string): string?
	for side, t in Config.Remembers.tracks do
		if t == track then
			return side
		end
	end
	return nil
end

function RepTiers.points(Config: any, char: any, track: string): number
	local rep = char and char.rep
	local n = rep and rep[StoryPlan.repIndex(Config, track)]
	return if type(n) == "number" then n else 0
end

function RepTiers.tierOf(Config: any, points: number): number
	return StoryPlan.repRank(Config, points)
end

-- A character's tier on one track (default: its own side's)
function RepTiers.tier(Config: any, char: any, track: string?): number
	local t = track or RepTiers.track(Config, char and char.side)
	return RepTiers.tierOf(Config, RepTiers.points(Config, char, t))
end

-- Points to reach a tier (0 for tier 0)
function RepTiers.need(Config: any, tier: number): number
	return Config.Story.rep.ranks[tier] or 0
end

---------------------------------------------------------------------------
-- Gizmo's side styles
---------------------------------------------------------------------------

export type Style = { id: number, price: number, row: any, track: string, tier: number }

-- Every side style, by track then tier then slot order
function RepTiers.styles(Config: any): { Style }
	local G = Config.Gear
	local out: { Style } = {}
	for slotIdx, slot in G.slotOrder do
		for _, row in G.styles[slot] or {} do
			if row.tier == "Rep" and type(row.rep) == "table" then
				table.insert(out, {
					id = GearMath.styleId(slotIdx, row.n),
					price = row.price,
					row = row,
					track = row.rep[1],
					tier = row.rep[2],
				})
			end
		end
	end
	table.sort(out, function(a, b)
		if a.track ~= b.track then
			return a.track > b.track -- vigil first
		end
		if a.tier ~= b.tier then
			return a.tier < b.tier
		end
		return a.id < b.id
	end)
	return out
end

function RepTiers.style(Config: any, id: number): Style?
	for _, s in RepTiers.styles(Config) do
		if s.id == id then
			return s
		end
	end
	return nil
end

-- May this character buy side style `id`? Its own side's track only, at that track's tier. Returns ok, reason
-- ("item": not a side style, "side": the other side's, "tier": not there yet) and the style.
function RepTiers.canBuy(Config: any, char: any, id: number): (boolean, string?, Style?)
	local s = RepTiers.style(Config, id)
	if not s then
		return false, "item", nil
	end
	if s.track ~= RepTiers.track(Config, char and char.side) then
		return false, "side", s
	end
	if RepTiers.tier(Config, char, s.track) < s.tier then
		return false, "tier", s
	end
	return true, nil, s
end

---------------------------------------------------------------------------
-- Titles and what each tier opens
---------------------------------------------------------------------------

function RepTiers.titleId(Config: any, track: string, tier: number): number
	return Config.Remembers.titleBase + StoryPlan.repIndex(Config, track) * 10 + tier
end

-- The tier titles this character holds: { id, name }
function RepTiers.titles(Config: any, char: any): { { id: number, name: string } }
	local R = Config.Remembers
	local out = {}
	for _, track in { "vigil", "syndicate" } do
		local tier = RepTiers.tier(Config, char, track)
		for t = 1, tier do
			local name = R.titles[track][t]
			if name then
				table.insert(out, { id = RepTiers.titleId(Config, track, t), name = name })
			end
		end
	end
	return out
end

-- What reaching `tier` on `track` opens: { styles = { names }, title, hideout }
function RepTiers.unlocks(
	Config: any,
	track: string,
	tier: number
): { styles: { string }, title: string?, hideout: string? }
	local R = Config.Remembers
	local styles = {}
	for _, s in RepTiers.styles(Config) do
		if s.track == track and s.tier == tier then
			table.insert(styles, s.row.name)
		end
	end
	return {
		styles = styles,
		title = R.titles[track] and R.titles[track][tier],
		hideout = R.hideout[track][tier],
	}
end

---------------------------------------------------------------------------
-- The hideout's tiered dressing (PLACEHOLDER ART)
---------------------------------------------------------------------------

export type Piece = {
	name: string,
	tier: number,
	x: number,
	y: number,
	z: number,
	sx: number,
	sy: number,
	sz: number,
	rgb: { number },
	mat: string?,
	shape: string?, -- "Ball", "Cylinder", "Wedge"; a box when nil
	glow: boolean?,
	light: number?,
	clear: number?, -- transparency
	ry: number?, -- degrees about y
	rz: number?, -- degrees about z
}

local function add(
	list: { Piece },
	tier: number,
	name: string,
	x,
	y,
	z,
	sx,
	sy,
	sz,
	rgb: { number },
	mat: string?
): Piece
	local p: Piece = {
		name = name,
		tier = tier,
		x = x,
		y = y,
		z = z,
		sx = sx,
		sy = sy,
		sz = sz,
		rgb = rgb,
		mat = mat,
	}
	table.insert(list, p)
	return p
end

local GOLD = { 255, 200, 60 }
local STEEL = { 120, 126, 138 }
local DARK = { 34, 36, 44 }

-- Every piece of a side's dressing, each with the tier it comes at
local function vigilPieces(Config: any): { Piece }
	local R = Config.Remembers.hideout
	local out: { Piece } = {}
	-- 1: the thank-you wall: a cork board on the south wall's west end, notes with fixed icons (never text)
	local bx, by, bz = -41, 11, 58.4
	add(out, 1, "noteBoard", bx, by, bz, 26, 12, 0.4, { 170, 120, 70 }, "Wood")
	local per = R.notesPerTier
	for i = 1, per * RepTiers.MAX do
		local col, row = (i - 1) % 6, (i - 1) // 6
		local tier = (i - 1) // per + 1
		local x, y = bx - 10.5 + col * 4.2, by + 4.4 - row * 2.2
		add(out, tier, "note", x, y, bz - 0.25, 3, 1.8, 0.1, { 250, 246, 230 })
		local icon = R.icons[(i - 1) % #R.icons + 1]
		local p = add(out, tier, "noteIcon", x, y, bz - 0.35, 0.8, 0.8, 0.1, icon[1], "Neon")
		if icon[2] ~= "Block" then
			p.shape = icon[2]
		end
	end
	-- 2: Patch's hacking rig: a desk on the south wall's east end, three screens, a keyboard, a rack and a stool
	add(out, 2, "rigDesk", 41, 3, 55, 14, 0.6, 4, DARK, "Metal")
	for _, x in { 35, 47 } do
		add(out, 2, "rigLeg", x, 1.4, 55, 0.6, 2.8, 3.4, STEEL, "Metal")
	end
	for i, x in { 36, 41, 46 } do
		add(out, 2, "rigBezel", x, 5.6, 56.2, 4.4, 3.2, 0.3, DARK, "Metal")
		local sc = add(out, 2, "rigScreen", x, 5.6, 56, 3.8, 2.6, 0.1, { 90, 230, 170 }, "Neon")
		sc.glow = true
		sc.light = if i == 2 then 14 else nil
	end
	add(out, 2, "rigKeys", 41, 3.4, 53.8, 4, 0.2, 1.2, { 60, 64, 76 }, "SmoothPlastic")
	add(out, 2, "rigRack", 51, 4, 56, 3, 8, 3, DARK, "Metal")
	for k = 1, 3 do
		local led = add(out, 2, "rigLed", 51, 2 + k * 1.8, 54.45, 2, 0.25, 0.1, { 90, 230, 170 }, "Neon")
		led.glow = true
	end
	local stool = add(out, 2, "rigStool", 41, 1.2, 51.5, 2.4, 2.4, 2.4, STEEL, "Metal")
	stool.shape = "Cylinder"
	stool.rz = 90
	-- 3: the hero relic display: a plinth and a glass case by the east pillar, the torn red cape and the cracked
	-- blue shield with its gold chevron (the old heroes' relics from the Crater)
	add(out, 3, "relicPlinth", 20, 1, 7, 6, 2, 4, { 170, 170, 176 }, "Concrete")
	local glass = add(out, 3, "relicGlass", 20, 4.6, 7, 5.6, 5.2, 3.6, { 200, 230, 255 }, "Glass")
	glass.clear = 0.7
	add(out, 3, "relicCape", 18.8, 4.4, 7, 1.6, 3, 0.2, { 200, 40, 50 }, "Fabric")
	local shield = add(out, 3, "relicShield", 21.3, 4.6, 7, 0.3, 2.4, 2.4, { 50, 90, 200 }, "Metal")
	shield.shape = "Cylinder"
	shield.ry = 90
	local chev = add(out, 3, "relicChevron", 21.3, 4.6, 6.8, 1, 0.8, 0.1, GOLD, "Neon")
	chev.shape = "Wedge"
	-- 4: the relic spotlight: the dented gold helmet joins the case, a lamp above it lights it
	local helm = add(out, 4, "relicHelmet", 20, 2.9, 7, 1.6, 1.4, 1.6, GOLD, "Foil")
	helm.shape = "Ball"
	add(out, 4, "spotHousing", 20, 24, 7, 2.4, 1.4, 2.4, DARK, "Metal")
	local spot = add(out, 4, "spotLamp", 20, 23.2, 7, 1.8, 0.3, 1.8, { 255, 240, 200 }, "Neon")
	spot.glow = true
	spot.light = 22
	-- 5: the city's thanks: a gold banner over the full wall and a lit frame round it
	add(out, 5, "thanksBanner", bx, by + 8, bz - 0.1, 26, 2.6, 0.3, GOLD, "Foil")
	for _, f in
		{
			{ bx, by + 6.4, 27, 0.4 },
			{ bx, by - 6.4, 27, 0.4 },
			{ bx - 13.4, by, 0.4, 13 },
			{ bx + 13.4, by, 0.4, 13 },
		}
	do
		local fr = add(out, 5, "thanksFrame", f[1], f[2], bz - 0.2, f[3], f[4], 0.2, GOLD, "Neon")
		fr.glow = true
	end
	return out
end

local function syndicatePieces(_Config: any): { Piece }
	local out: { Piece } = {}
	local RED = { 210, 50, 60 }
	-- 1: the loot vault: a round vault door in a steel frame on the south wall's west end, gold bar stacks
	local vx, vy, vz = -41, 9, 58.6
	add(out, 1, "vaultFrame", vx, vy, vz, 16, 16, 0.8, STEEL, "DiamondPlate")
	local door = add(out, 1, "vaultDoor", vx, vy, vz - 0.8, 1, 12, 12, { 150, 156, 168 }, "Metal")
	door.shape = "Cylinder"
	door.ry = 90
	local hub = add(out, 1, "vaultWheel", vx, vy, vz - 1.5, 0.6, 4, 4, GOLD, "Metal")
	hub.shape = "Cylinder"
	hub.ry = 90
	for k = 1, 5 do
		local tier = if k <= 2 then 1 else 4
		local x = -50 + (k - 1) * 4.5
		add(out, tier, "goldBar", x - 0.6, 0.6, 54, 1.1, 0.8, 2.2, GOLD, "Foil")
		add(out, tier, "goldBar", x + 0.6, 0.6, 54, 1.1, 0.8, 2.2, GOLD, "Foil")
		add(out, tier, "goldBar", x, 1.4, 54, 1.1, 0.8, 2.2, GOLD, "Foil")
	end
	-- 2: the trophy screen: a big screen on the south wall's east end with a gold crown icon (no text)
	add(out, 2, "trophyFrame", 41, 13, 58.6, 23, 13, 0.4, DARK, "Metal")
	local scr = add(out, 2, "trophyScreen", 41, 13, 58.3, 21, 11, 0.2, { 120, 30, 60 }, "Neon")
	scr.glow = true
	scr.light = 18
	local crown = add(out, 2, "trophyCrown", 41, 13.5, 58.1, 6, 4, 0.2, GOLD, "Neon")
	crown.shape = "Wedge"
	crown.glow = true
	-- 3: a captured Crane robot on a hook: a chain from the ceiling, a navy shell with the Crane C plate, limp
	-- arms and legs, eyes gone dim
	local rx, rz = -20, 8
	add(out, 3, "hookChain", rx, 24.5, rz, 0.4, 9, 0.4, STEEL, "Metal")
	add(out, 3, "hook", rx, 19.8, rz, 1.4, 0.5, 0.5, STEEL, "Metal")
	local NAVY = { 36, 48, 92 }
	add(out, 3, "robotHead", rx, 18.2, rz, 2.4, 2.4, 2.4, NAVY, "Metal")
	for _, s in { -0.5, 0.5 } do
		local eye = add(out, 3, "robotEye", rx + s, 18.4, rz - 1.25, 0.4, 0.3, 0.1, { 120, 40, 40 }, "Neon")
		eye.glow = true
	end
	add(out, 3, "robotTorso", rx, 14.8, rz, 3.4, 4, 2, NAVY, "Metal")
	-- the Crane C: three white bars on the chest plate
	add(out, 3, "craneC", rx, 16.0, rz - 1.05, 1.6, 0.35, 0.1, { 245, 245, 250 })
	add(out, 3, "craneC", rx - 0.65, 15.1, rz - 1.05, 0.35, 1.8, 0.1, { 245, 245, 250 })
	add(out, 3, "craneC", rx, 14.2, rz - 1.05, 1.6, 0.35, 0.1, { 245, 245, 250 })
	for _, s in { -1, 1 } do
		add(out, 3, "robotArm", rx + s * 2.2, 14.3, rz, 1, 3.6, 1, NAVY, "Metal")
		add(out, 3, "robotLeg", rx + s * 0.8, 11, rz, 1.2, 3.4, 1.2, NAVY, "Metal")
	end
	-- 4: the vault expansion: three more bar stacks (above), two cash crates and a lit trim round the door
	for i, x in { -52, -30 } do
		add(out, 4, "cashCrate", x, 1.5, 50 + i, 3, 3, 3, { 70, 120, 60 }, "Wood")
	end
	local trim = add(out, 4, "vaultTrim", vx, vy, vz - 0.5, 0.3, 13.2, 13.2, GOLD, "Neon")
	trim.shape = "Cylinder"
	trim.ry = 90
	trim.glow = true
	-- 5: the kingpin's spotlight: a gold frame on the screen, a red carpet up to it and a lamp over it
	for _, f in { { 41, 19.8, 24, 0.6 }, { 41, 6.2, 24, 0.6 }, { 28.8, 13, 0.6, 14 }, { 53.2, 13, 0.6, 14 } } do
		local fr = add(out, 5, "kingpinFrame", f[1], f[2], 58.2, f[3], f[4], 0.3, GOLD, "Neon")
		fr.glow = true
	end
	add(out, 5, "carpet", 41, 0.3, 49, 8, 0.1, 12, RED, "Fabric")
	add(out, 5, "spotHousing", 41, 26, 50, 2.4, 1.4, 2.4, DARK, "Metal")
	local lamp = add(out, 5, "spotLamp", 41, 25.2, 50, 1.8, 0.3, 1.8, { 255, 230, 200 }, "Neon")
	lamp.glow = true
	lamp.light = 26
	return out
end

-- The dressing for a side's HQ at a tier: every piece of that tier and below
function RepTiers.dressing(Config: any, side: string?, tier: number): { Piece }
	local all: { Piece } = if RepTiers.side(side) == "villain"
		then syndicatePieces(Config)
		else vigilPieces(Config)
	local out = {}
	for _, p in all do
		if p.tier <= tier then
			table.insert(out, p)
		end
	end
	return out
end

---------------------------------------------------------------------------
-- The city reacts
---------------------------------------------------------------------------

-- How a citizen at `dist` studs reacts to a hero of `side` at `tier`: "cheer" (the Vigil), "flinch" (the
-- Syndicate) or nil (too far, too low a tier, or the citizen is fleeing)
function RepTiers.reaction(Config: any, side: string?, tier: number, dist: number, fleeing: boolean?): string?
	local C = Config.Remembers.citizens
	if fleeing or tier < C.minTier then
		return nil
	end
	local range = if tier >= C.highTier then C.highRange else C.range
	if dist > range then
		return nil
	end
	return if RepTiers.side(side) == "villain" then "flinch" else "cheer"
end

---------------------------------------------------------------------------
-- Patch's radio and the news
---------------------------------------------------------------------------

local function fill(text: string?, name: string?): string?
	if not text then
		return nil
	end
	local who = if name and name ~= "" then name else "rookie"
	return (string.gsub(text :: string, "%%s", function()
		return who
	end))
end

-- Patch on your own tier-up (side-flavoured), with your safe name
function RepTiers.radioSelf(Config: any, side: string?, tier: number, name: string?): string?
	return fill(Config.Remembers.radio.self[RepTiers.side(side)][tier], name)
end

-- Patch about a high-tier hero in the server: a listener of `side` hearing about a hero on `track`
function RepTiers.radioAbout(Config: any, side: string?, track: string, name: string?): string?
	local s = RepTiers.side(side)
	local same = RepTiers.sideOf(Config, track) == s
	return fill(Config.Remembers.radio.about[s][if same then "same" else "other"], name)
end

-- Does the news (and the radio) name a hero at this tier?
function RepTiers.mention(Config: any, tier: number): boolean
	return tier >= Config.Remembers.mention.tier
end

---------------------------------------------------------------------------
-- Pacing
---------------------------------------------------------------------------

-- Act 1's own-side points for a side: the fewest and the most (missions 2 on pay the mission points and their
-- own; each choice pays its option's points when the option is the side's own track)
function RepTiers.act1(Config: any, side: string?): (number, number)
	local S = Config.Story
	local s = RepTiers.side(side)
	local base = 0
	for i, m in S.missions do
		if i >= 2 then
			base += S.rep.mission + (m.rep or 0)
		end
	end
	local lo, hi = base, base
	for _, c in S.choices or {} do
		local opts = c[s]
		if opts then
			local least, most = math.huge, 0
			for _, o in opts do
				local n = if o.rep and o.rep[1] == "side" then o.rep[2] else 0
				least, most = math.min(least, n), math.max(most, n)
			end
			lo += if least == math.huge then 0 else least
			hi += most
		end
	end
	return lo, hi
end

-- Own-side points an hour of open-world play earns (the pace model)
function RepTiers.perHour(Config: any): number
	local R = Config.Remembers
	local E, P = R.earn, R.pace
	return P.incidents * E.incident
		+ P.contracts * E.contract
		+ P.events * E.event
		+ P.sideEvents * (E.sideEvent + P.winShare * E.sideWin)
		+ P.sideSteps * E.sideStep
end

-- Hours of open-world play after Act 1 (with its fewest points) to reach each tier: { [tier] = hours }
function RepTiers.pace(Config: any, side: string?): { number }
	local lo = RepTiers.act1(Config, side)
	local rate = RepTiers.perHour(Config)
	local out = {}
	for t = 1, RepTiers.MAX do
		out[t] = math.max(0, RepTiers.need(Config, t) - lo) / rate
	end
	return out
end

return RepTiers
