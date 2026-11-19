--!strict
-- HqRules: the Hero HQ, offline drones, trophies and Legacy rebirth (spec: Hero HQ; Legacy rebirth;
-- Economy > Sinks "HQ levels"). Pure, so Lune tests it.
-- * cell(slot): where a hero's solo HQ cell is (one per hero slot, far above the map).
-- * heroDoor(world): the Vigil's stairwell at the plaza's edge; hideout() and wallKit(length): the Vigil HQ's
--   underground look (the cell and mission 2's Safehouse pocket share the wall kit).
-- * upgradeCost(level), and what each level opens (mannequins, dummies, boss sim, trophies, drones).
-- * drones(level, awaySeconds): offline Credits, 8 hours at most.
-- * trophies(profile): the trophies this account has earned (shown on the wall, 3 or 12 picked).
-- * canRetire / retire: Legacy at the level cap (Config.Stats.levelCap, 50). The hero becomes a statue;
--   the slot restarts at level 1 and keeps every unlock (account-wide already), reputation, Fame, story, beacons and its HQ; gear goes back to the
--   stash (wearable again at item level minus 5, the existing equip slack).

local ProfileSchema = if script
	then require(script.Parent.ProfileSchema)
	else (require :: any)("./ProfileSchema")
local StoryPlan = if script then require(script.Parent.StoryPlan) else (require :: any)("./StoryPlan")
local PvpRules = if script then require(script.Parent.PvpRules) else (require :: any)("./PvpRules")
local MentorRules = if script then require(script.Parent.MentorRules) else (require :: any)("./MentorRules")
local SideQuestPlan = if script
	then require(script.Parent.SideQuestPlan)
	else (require :: any)("./SideQuestPlan")
local AbilityRules = if script
	then require(script.Parent.AbilityRules)
	else (require :: any)("./AbilityRules")

local Bits = ProfileSchema.Bits

local HqRules = {}

function HqRules.cell(Config: any, slot: number): (number, number, number)
	local c = Config.Hq.cell
	local i = math.max(slot, 1) - 1
	return c.x0 + (i % c.perRow) * c.gap, c.y, c.z0 + (i // c.perRow) * c.gap
end

-- Which cell a point is in (any slot), or nil
function HqRules.cellAt(Config: any, x: number, y: number, z: number): number?
	local c = Config.Hq.cell
	if y < c.y - 60 or y > c.y + 200 then
		return nil
	end
	local col = math.floor((x - c.x0) / c.gap + 0.5)
	local row = math.floor((z - c.z0) / c.gap + 0.5)
	if col < 0 or col >= c.perRow or row < 0 then
		return nil
	end
	local cx, cz = c.x0 + col * c.gap, c.z0 + row * c.gap
	if math.abs(x - cx) > c.size / 2 + 10 or math.abs(z - cz) > c.size / 2 + 10 then
		return nil
	end
	return row * c.perRow + col + 1
end

-- The Vigil's way in (nate's lore plan Q2, 2026-11-17): a maintenance stairwell at the edge of the Downtown plaza
-- (Config.Hq.door), never in Crane's Hero Hall. Its foot (x, z) and the way its door faces (into the plaza), or
-- nil for a world without a Downtown.
function HqRules.heroDoor(Config: any, world: any): { x: number, z: number, fx: number, fz: number }?
	local bt = world and world.downtown and world.downtown.beacon
	if not bt then
		return nil
	end
	local D = Config.Hq.door
	local ex, ez = D.edge[1], D.edge[2]
	local sx, sz = -ez, ex -- along the edge
	local out = Config.City.downtown.block / 2 - D.inset
	return {
		x = bt.x + ex * out + sx * D.along,
		z = bt.z + ez * out + sz * D.along,
		fx = -ex,
		fz = -ez,
	}
end

-- One piece of the Vigil hideout's look: a box at (x, y, z) (y from the floor) in some frame, a City palette
-- key, an optional Material name, a turn about z in degrees (rz), a lit face (glow) and a light's range.
export type Piece = {
	name: string,
	x: number,
	y: number,
	z: number,
	sx: number,
	sy: number,
	sz: number,
	color: string,
	mat: string?,
	rz: number?,
	glow: boolean?,
	light: number?,
	run: Run?, -- the wall-kit run a piece belongs to (placeKit): Shared.HideoutKit dresses each run in modules
}

-- One wall-kit run as placed (placeKit): the wall face's middle (x, z), its length and the turn about up (degrees)
-- that faces a look's front (-z) into the room
export type Run = { x: number, z: number, len: number, ry: number }

local function piece(list: { Piece }, name: string, x, y, z, sx, sy, sz, color: string, mat: string?): Piece
	local p: Piece = {
		name = name,
		x = x,
		y = y,
		z = z,
		sx = sx,
		sy = sy,
		sz = sz,
		color = color,
		mat = mat,
	}
	table.insert(list, p)
	return p
end

-- The hideout's wall dressing, shared by the HQ cell and mission 2's Safehouse pocket so they read as one
-- place: two pipes and a cable tray under the ceiling, work lamps (every other one lit), a hazard stripe at
-- the foot. In the wall's own frame: x along the wall (-length/2 to length/2), z out from its face into the
-- room, y up from the floor.
function HqRules.wallKit(Config: any, length: number): { Piece }
	local K = Config.Hq.hideout
	local C, h = K.colors, K.height
	local out = {}
	piece(out, "pipe", 0, h - 3.5, 1.2, length, 1.4, 1.4, C.pipe, "Metal")
	piece(out, "pipe", 0, h - 5.5, 1.1, length, 0.9, 0.9, C.pipeB, "Metal")
	piece(out, "cableTray", 0, h - 8, 2.4, length, 0.25, 2.4, C.tray, "DiamondPlate")
	piece(out, "cableTray", 0, h - 7.6, 3.6, length, 0.8, 0.2, C.tray, "DiamondPlate")
	piece(out, "stripe", 0, 1.2, 0.2, length, 0.6, 0.3, C.stripe)
	local n = math.max(1, math.floor(length / K.lampEvery))
	for i = 1, n do
		local x = -length / 2 + (i - 0.5) * (length / n)
		piece(out, "lampHousing", x, h - 11, 0.8, 2.4, 1.4, 1.6, C.tray, "Metal")
		local face = piece(out, "workLamp", x, h - 11.4, 1.65, 1.8, 0.7, 0.1, C.lamp, "Neon")
		face.glow = true
		face.light = if i % 2 == 1 then 26 else nil
	end
	return out
end

-- Pieces of a wall kit moved into a room frame: the wall's middle at (ox, oz), running along (ux, uz) with the
-- room on the (nx, nz) side (axis-aligned walls only)
function HqRules.placeKit(
	list: { Piece },
	kit: { Piece },
	ox: number,
	oz: number,
	ux: number,
	uz: number,
	nx: number,
	nz: number
)
	local alongX = ux ~= 0
	local len = 0
	for _, p in kit do
		len = math.max(len, p.sx)
	end
	local run: Run = { x = ox, z = oz, len = len, ry = math.deg(math.atan2(-nx, -nz)) }
	for _, p in kit do
		local q = table.clone(p)
		q.run = run
		q.x = ox + ux * p.x + nx * p.z
		q.z = oz + uz * p.x + nz * p.z
		q.sx = if alongX then p.sx else p.sz
		q.sz = if alongX then p.sz else p.sx
		table.insert(list, q)
	end
end

-- The Vigil's HQ cell drawn as the hideout under the plaza (nate's lore plan Q2): concrete walls, pillars and
-- beams, a ceiling, the wall kit, monitors and a city map wall where the old sky windows were, and the service
-- stair arriving from above at the entrance (beside the Exit, up through a shaft in the ceiling). Offsets from
-- the cell centre, y from the floor; the stations, rooms and budgets are the same as ever.
function HqRules.hideout(Config: any): { Piece }
	local K = Config.Hq.hideout
	local C, h = K.colors, K.height
	local s = Config.Hq.cell.size
	local half = s / 2
	local out = {}
	piece(out, "floor", 0, 0.15, 0, s - 4, 0.2, s - 4, C.floor, "Concrete")
	-- the walls
	for _, k in { -1, 1 } do
		piece(out, "wall", 0, h / 2, k * half, s, h, 2, C.wall, "Concrete")
		piece(out, "wall", k * half, h / 2, 0, 2, h, s, C.wall, "Concrete")
	end
	-- the stair (12 steps up along the north wall from beside the Exit) and its shaft through the ceiling
	local steps, run, rise = 12, 3, h / 12
	local x0, sz = 10, 8
	local zc = -half + 1 + sz / 2
	for i = 1, steps do
		local x = x0 + (i - 0.5) * run
		piece(out, "stairStep", x, i * rise / 2, zc, run, i * rise, sz, C.pillar, "Concrete")
		piece(out, "stairNosing", x - run / 2 + 0.25, i * rise + 0.05, zc, 0.5, 0.15, sz, C.stripe)
	end
	local len = math.sqrt((steps * run) ^ 2 + h ^ 2)
	local rail = piece(
		out,
		"stairRail",
		x0 + steps * run / 2,
		h / 2 + 3.4,
		zc + sz / 2 + 0.4,
		len,
		0.3,
		0.3,
		C.tray,
		"Metal"
	)
	rail.rz = math.deg(math.atan2(h, steps * run))
	for i = 3, steps, 3 do
		piece(
			out,
			"stairPost",
			x0 + (i - 0.5) * run,
			i * rise + 1.7,
			zc + sz / 2 + 0.4,
			0.3,
			3.4,
			0.3,
			C.tray,
			"Metal"
		)
	end
	-- the ceiling, open over the stair's top (hole: hx0..hx1 by the stair's depth)
	local hx0, hx1 = x0 + steps * run - 12, x0 + steps * run + 2
	local hz1 = -half + 1 + sz + 1
	local rest = s - (hz1 + half)
	piece(out, "ceiling", 0, h + 0.5, hz1 + rest / 2, s, 1, rest, C.wall, "Concrete")
	piece(
		out,
		"ceiling",
		(-half + hx0) / 2,
		h + 0.5,
		(-half + hz1) / 2,
		hx0 + half,
		1,
		hz1 + half,
		C.wall,
		"Concrete"
	)
	piece(
		out,
		"ceiling",
		(hx1 + half) / 2,
		h + 0.5,
		(-half + hz1) / 2,
		half - hx1,
		1,
		hz1 + half,
		C.wall,
		"Concrete"
	)
	local sh, hw, hd = 10, hx1 - hx0, hz1 + half
	local hcx, hcz = (hx0 + hx1) / 2, (-half + hz1) / 2
	piece(out, "shaft", hx0, h + sh / 2, hcz, 1, sh, hd, C.wall, "Concrete")
	piece(out, "shaft", hx1, h + sh / 2, hcz, 1, sh, hd, C.wall, "Concrete")
	piece(out, "shaft", hcx, h + sh / 2, hz1, hw, sh, 1, C.wall, "Concrete")
	piece(out, "shaft", hcx, h + sh / 2, -half, hw, sh, 1, C.wall, "Concrete")
	piece(out, "shaft", hcx, h + sh, hcz, hw + 1, 1, hd + 1, C.wall, "Concrete")
	local shaftLamp = piece(out, "workLamp", hcx, h + sh - 1, hcz, 1.8, 0.4, 1.8, C.lamp, "Neon")
	shaftLamp.glow = true
	shaftLamp.light = 18
	-- pillars, pilasters and beams
	for _, k in { -1, 1 } do
		piece(out, "pillar", k * 20, h / 2, 0, 4, h, 4, C.pillar, "Concrete")
		for _, z in { -48, -24, 24, 48 } do
			piece(out, "pilaster", k * (half - 2.5), h / 2, z, 3, h, 4, C.pillar, "Concrete")
		end
		piece(out, "pilaster", k * 24, h / 2, half - 2.5, 4, h, 3, C.pillar, "Concrete")
	end
	for _, z in { 0, 30 } do
		piece(out, "beam", 0, h - 1, z, s - 2, 2, 3, C.pillar, "Concrete")
	end
	-- the wall kit along the east, west and south walls, and the north wall's open end (the stair takes the rest)
	local inner = half - 1
	HqRules.placeKit(out, HqRules.wallKit(Config, s - 2), -inner, 0, 0, 1, 1, 0)
	HqRules.placeKit(out, HqRules.wallKit(Config, s - 2), inner, 0, 0, 1, -1, 0)
	HqRules.placeKit(out, HqRules.wallKit(Config, s - 2), 0, inner, 1, 0, 0, -1)
	local northLen = x0 + half - 1
	HqRules.placeKit(out, HqRules.wallKit(Config, northLen), -half + 1 + northLen / 2, -inner, 1, 0, 0, 1)
	-- the city map wall behind the command table: a dark board, the districts lit on it, a frame
	local mx, my, mz, mw, mh = -24, 11, -inner + 0.3, 34, 12
	piece(out, "mapBoard", mx, my, mz, mw + 1.6, mh + 1.6, 0.4, C.tray, "Metal")
	piece(out, "mapScreen", mx, my, mz + 0.3, mw, mh, 0.2, "road")
	for i = 0, 8 do
		local col, row = i % 3, i // 3
		local d = piece(
			out,
			"mapDistrict",
			mx + (col - 1) * (mw / 3),
			my + (1 - row) * (mh / 3),
			mz + 0.45,
			mw / 3 - 2,
			mh / 3 - 1.6,
			0.1,
			C.screen,
			"Neon"
		)
		d.glow = true
	end
	-- monitor banks on the east and west walls (three screens each, over the side-wall props)
	for _, k in { -1, 1 } do
		for _, z in { -8, 0, 8 } do
			piece(out, "monitorBezel", k * (inner - 0.6), 12, z, 0.6, 4.4, 6.4, "roof", "Metal")
			local sc = piece(out, "monitorScreen", k * (inner - 1), 12, z, 0.2, 3.6, 5.6, C.screen, "Neon")
			sc.glow = true
		end
	end
	return out
end

HqRules.MAX_LEVEL = 6

-- Credits to go from `level` to level + 1 (nil at the top)
function HqRules.upgradeCost(Config: any, level: number): number?
	return Config.Economy.hqLevels[level]
end

local function at(list: { number }, level: number): number
	return list[math.min(level, #list)]
end

function HqRules.mannequins(Config: any, level: number): number
	return at(Config.Hq.levels.mannequins, level)
end

function HqRules.dummies(Config: any, level: number): number
	return at(Config.Hq.levels.trainingDummies, level)
end

function HqRules.bossSim(Config: any, level: number): boolean
	return level >= Config.Hq.levels.bossSim
end

function HqRules.trophySlots(Config: any, level: number): number
	return at(Config.Hq.levels.trophies, level)
end

function HqRules.mvpCards(Config: any, level: number): boolean
	return level >= Config.Hq.levels.mvpCards
end

function HqRules.dronesOn(Config: any, level: number): boolean
	return level >= Config.Hq.levels.drones
end

function HqRules.dronePerMinute(Config: any, level: number): number
	local best = 0
	for lv, rate in Config.Hq.drones.perMinute do
		if level >= lv and rate > best then
			best = rate
		end
	end
	return best
end

-- Offline drone Credits for time away (whole minutes, capped at 8 hours)
function HqRules.drones(Config: any, level: number, awaySeconds: number): number
	if not HqRules.dronesOn(Config, level) or awaySeconds <= 0 then
		return 0
	end
	local minutes = math.min(awaySeconds, Config.Hq.drones.capHours * 3600) // 60
	return minutes * HqRules.dronePerMinute(Config, level)
end

-- Trophies earned by this account (ids from Config.Hq.trophies)
function HqRules.trophies(Config: any, profile: any): { [string]: boolean }
	local s = profile.stats
	local out: { [string]: boolean } = {}
	local maxLevel, maxFame, maxRep, quests, act1 = 0, 0, 0, false, false
	for _, c in profile.characters do
		maxLevel = math.max(maxLevel, c.level or 1)
		maxFame = math.max(maxFame, PvpRules.fameRank(Config, c.fame or 0))
		for i = 1, 3 do
			maxRep = math.max(maxRep, StoryPlan.repRank(Config, c.rep[i] or 0))
		end
		quests = quests or SideQuestPlan.allDone(Config, c) -- lore step 10: every chain (or every retired arc)
		if StoryPlan.actDone(Config, c.story, 1) then -- WP11: Act 1 itself, whatever acts come after
			act1 = true
		end
	end
	for _, l in profile.legends do
		maxLevel = math.max(maxLevel, l.level or 0)
	end
	out.firstBoss = (s.bossesJoined or 0) >= 1
	out.bossMvp = (s.mvps or 0) >= 1
	out.act1 = act1
	out.allQuests = quests
	out.level20 = maxLevel >= 20
	out.level40 = maxLevel >= 40
	out.legacy1 = #profile.legends >= 1
	out.fame5 = maxFame >= 5
	out.fame10 = maxFame >= 10
	out.rescues100 = (s.rescues or 0) >= 100
	out.contracts50 = (s.contracts or 0) >= 50
	out.repMax = maxRep >= 5
	out.pvp10 = (s.wins or 0) >= 10
	out.styles50 = #Bits.list(profile.styles) >= 50
	out.mentorPride = Config.Mentors ~= nil and MentorRules.pride(Config.Mentors, profile) -- H6
	return out
end

-- Pick trophies for the wall: earned ones only, no repeats, at most the level's slots
function HqRules.pickTrophies(Config: any, profile: any, level: number, picks: { number }): { number }
	local earned = HqRules.trophies(Config, profile)
	local out, seen = {}, {}
	for _, i in picks do
		local t = Config.Hq.trophies[i]
		if t and earned[t.id] and not seen[i] and #out < HqRules.trophySlots(Config, level) then
			seen[i] = true
			table.insert(out, i)
		end
	end
	return out
end

-- City reputation rank -> HQ prop bits to unlock
function HqRules.cityProps(Config: any, cityRank: number): { number }
	local out = {}
	for _, row in Config.Hq.cityProps do
		if cityRank >= row.rank then
			table.insert(out, row.prop)
		end
	end
	return out
end

-- Legacy
function HqRules.canRetire(Config: any, char: any): (boolean, string?)
	if (char.level or 1) < Config.Stats.levelCap then
		return false, "level"
	end
	return true, nil
end

-- Retire the character: returns the statue record. The character restarts at level 1 in place.
function HqRules.retire(Config: any, profile: any, charIndex: number, now: number): any?
	local c = profile.characters[charIndex]
	if not c or not HqRules.canRetire(Config, c) then
		return nil
	end
	local statue = {
		look = table.clone(c.look),
		titleId = c.titleId,
		nounId = c.nounId,
		classId = c.classId,
		side = c.side,
		level = c.level,
		rank = (c.legacy or 0) + 1,
		at = now,
	}
	table.insert(profile.legends, statue)
	while #profile.legends > Config.Hq.legacy.statues do
		table.remove(profile.legends, 1)
	end
	local fresh = ProfileSchema.newCharacter(c.side, c.classId)
	-- kept: who the hero is (origin, mobility, carried weapon, the free path change once used), reputation,
	-- Fame, story and side quest chains, the map, HQ, looks, tint and landing pose, and the MMO record
	-- (nemesis, banes, trophies, mentor, the worn title, aura, trim and travel styles, task force weeks).
	-- A new run: level, XP, ranks, mods, loadouts, gear, contracts and the respec and Second Wind timers.
	for _, key in
		{
			"side",
			"classId",
			"look",
			"looks",
			"titleId",
			"nounId",
			"fxStyle",
			"startSet",
			"fame",
			"rep",
			"hq",
			"story",
			"bonusPoints",
			"beacons",
			"safehouses",
			"lastSafehouse",
			"tint",
			"landing",
			"created",
			"origin",
			"mobility",
			"weapon",
			"pathChanged",
			"sq",
			"mmo",
		}
	do
		fresh[key] = c[key]
	end
	-- a new run starts on its own starting set with fresh ranks
	local ranks, loadout = AbilityRules.starter(Config, c.startSet or "Volt")
	fresh.ranks = ranks
	fresh.loadouts = { loadout, table.clone(loadout) }
	fresh.loadouts[2].skills = table.clone(loadout.skills)
	fresh.legacy = math.min((c.legacy or 0) + 1, 255)
	profile.characters[charIndex] = fresh
	return statue
end

-- Legacy's Renown bonus (+10% a rank, max 5 ranks); the frame keeps growing past 5
function HqRules.legacyBonus(Config: any, ranks: number): number
	local b = Config.Economy.bonus
	return math.min(ranks * b.legacyEach, b.legacyMax)
end

return HqRules
