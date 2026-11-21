--!strict
-- LabRules: the Studio Test Lab's rules (nate, 2026-11-21: "Need a way for me to test out all the
-- weapons/powers/abolities/mobilies in an easier way"). Pure, so DevService, the Dev panel's Test Lab page and the
-- Lune tests share one answer. Studio only: DevService refuses every lab command outside Studio, and nothing here
-- is reachable in a live game.
-- * The lab is a session table on the hero (hero.lab). Opening it snapshots the hero's build (HOME: level, path,
--   ranks, mods, loadouts, mobility and its ranks and moves); while it is open HeroService.writeBack saves that
--   snapshot, never the lab's build, and "Leave lab" puts it back on the hero. A wipe or a character switch
--   (HeroService.applyProfile) ends it.
-- * Weapons: any of the 36 is carried for the session (weaponOf) with every Mastery skill open (weaponMastery);
--   nothing is bought or granted, and the lab earns no Mastery.
-- * Powers: a path's every ability learned at max rank, a loadout filled from the path inside the real budget
--   (pathKit, checked by AbilityRules.validate), and try(): one ability onto the first skill key (a super onto the
--   super), borrowed skills of the same archetype too, still inside the slots, the budget and the borrow limit.
-- * Mobility: any pick at any rank, both choice ranks' moves switchable (mobility, choice).
-- * Cheats: cooldowns cut to Config.Dev.lab.cooldown (basics keep theirs: the held M1 fires every frame) and
--   stamina never drains.

local AbilityRules = if script
	then require(script.Parent.AbilityRules)
	else (require :: any)("./AbilityRules")
local MoveRanks = if script then require(script.Parent.MoveRanks) else (require :: any)("./MoveRanks")

local LabRules = {}

export type Loadout = { set: string, basic: string?, skills: { string }, super: string? } -- as AbilityRules.Loadout

export type Lab = {
	home: { [string]: any },
	weapon: number?, -- the weapon carried for the session (any of Config.Weapons.list)
	noCd: boolean, -- cooldowns cut to Config.Dev.lab.cooldown
	stamina: boolean, -- stamina never drains
	reset: number, -- bumped by "supers ready": the device clears its own cooldown copy
}

-- The build the lab may change, saved as it was while the lab is open
LabRules.HOME = {
	"level",
	"xp",
	"classId",
	"startSet",
	"setId",
	"mobility",
	"mobRanks",
	"mobMoves",
	"ranks",
	"mods",
	"bonusPoints",
	"loadouts",
	"loadoutIndex",
}

local function deep(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = deep(x)
	end
	return out
end

function LabRules.snapshot(hero: any): { [string]: any }
	local home = {}
	for _, k in LabRules.HOME do
		home[k] = deep(hero[k])
	end
	return home
end

-- Put the snapshot back on the hero (the loadout in use is the saved index's)
function LabRules.restore(hero: any, home: { [string]: any })
	for _, k in LabRules.HOME do
		hero[k] = deep(home[k])
	end
	hero.loadout = hero.loadouts[hero.loadoutIndex] or hero.loadouts[1]
end

function LabRules.new(hero: any): Lab
	return { home = LabRules.snapshot(hero), weapon = nil, noCd = false, stamina = false, reset = 0 }
end

-- What the hero's HeroState carries about the lab (always a table, so the device's merge clears it)
function LabRules.view(lab: Lab?, god: boolean?): { [string]: any }
	if not lab then
		return { on = false, god = god == true }
	end
	return {
		on = true,
		weapon = lab.weapon or 0,
		noCd = lab.noCd,
		stamina = lab.stamina,
		reset = lab.reset,
		god = god == true,
	}
end

---------------------------------------------------------------------------
-- Weapons
---------------------------------------------------------------------------

-- Mastery points that open every skill key (Z X C V)
function LabRules.masteryPoints(Config: any): number
	local M = Config.Weapons.mastery
	local need = 0
	for _, key in Config.Weapons.keys do
		need = math.max(need, M.skills[key] or 0)
	end
	return need * M.perLevel
end

-- The weapon in play: the lab's pick, else the carried one
function LabRules.weaponOf(lab: any, carried: number): number
	local w = lab and lab.weapon
	return if type(w) == "number" and w > 0 then w else carried
end

-- The Mastery points the kit reads: every key open while the lab carries a weapon
function LabRules.weaponMastery(Config: any, lab: any, points: number): number
	if lab and lab.weapon then
		return math.max(points, LabRules.masteryPoints(Config))
	end
	return points
end

-- May the lab carry weapon `id`? (any weapon in the list that has its moves)
function LabRules.weaponOk(Config: any, id: number): boolean
	for _, row in Config.Weapons.list do
		if row[1] == id then
			return table.find(Config.Weapons.playable, id) ~= nil
		end
	end
	return false
end

---------------------------------------------------------------------------
-- Powers
---------------------------------------------------------------------------

-- A path's abilities: its basic, its skills in order, its super
function LabRules.pathAbilities(
	Config: any,
	set: string
): { basic: string?, skills: { string }, super: string? }
	local skills = {}
	for _, id in Config.Abilities.order do
		local row = Config.Abilities.list[id]
		if row.set == set and row.slot == "skill" then
			table.insert(skills, id)
		end
	end
	return {
		basic = AbilityRules.basicOf(Config, set),
		skills = skills,
		super = AbilityRules.superOf(Config, set),
	}
end

-- The other paths of a path's archetype (where borrowed skills come from)
function LabRules.borrowPaths(Config: any, set: string): { string }
	local out = {}
	local arch = AbilityRules.archetypeOf(Config, set)
	for _, s in (if arch then AbilityRules.paths(Config, arch) else {}) do
		if s ~= set then
			table.insert(out, s)
		end
	end
	return out
end

-- Fill skill slots in order, inside the slots and the budget (a skill that does not fit is skipped)
local function fill(Config: any, wanted: { string }, slots: number): { string }
	local out = {}
	for _, id in wanted do
		if #out >= slots then
			break
		end
		local try = table.clone(out)
		table.insert(try, id)
		if AbilityRules.loadoutPoints(Config, try) <= Config.Abilities.loadoutCap then
			out = try
		end
	end
	return out
end

-- A path in the lab: every ability of it learned at max rank, a loadout filled from it (the starters first, then
-- the rest in order), its super. Returns ranks and the loadout.
function LabRules.pathKit(Config: any, set: string, level: number): ({ [string]: number }, Loadout)
	local p = LabRules.pathAbilities(Config, set)
	local ranks: { [string]: number } = {}
	for _, id in Config.Abilities.order do
		local row = Config.Abilities.list[id]
		if row.set == set then
			ranks[id] = AbilityRules.maxRank(row)
		end
	end
	local wanted = table.clone(Config.Abilities.starter[set] or {})
	for _, id in p.skills do
		if not table.find(wanted, id) then
			table.insert(wanted, id)
		end
	end
	local loadout = {
		set = set,
		basic = p.basic,
		skills = fill(Config, wanted, AbilityRules.skillSlots(Config, level)),
		super = if AbilityRules.superUnlocked(Config, level) then p.super else nil,
	}
	return ranks, loadout
end

export type HeroView = {
	level: number,
	startSet: string?,
	ranks: { [string]: number },
	loadout: Loadout,
}

-- Try one ability: a skill goes on the first skill key (the others move along; the last falls off when the
-- slots or the budget run out), a super on the super. A borrowed skill (another path of the archetype) is learned
-- at max rank; borrowed skills no longer in the loadout are unlearned, so the borrow limit holds. Returns ok, the
-- reason, the new ranks and the new loadout (AbilityRules.validate has passed them).
function LabRules.try(
	Config: any,
	hero: HeroView,
	id: string
): (boolean, string?, { [string]: number }?, Loadout?)
	local A = Config.Abilities
	local row = A.list[id]
	if not row or row.set == "Weapon" then
		return false, "ability", nil, nil
	end
	local main = hero.startSet or A.defaultLoadout.set
	local l = hero.loadout
	local ranks = table.clone(hero.ranks)
	local loadout = { set = main, basic = l.basic, skills = table.clone(l.skills), super = l.super }
	if row.slot == "basic" then
		return false, "basic", nil, nil -- the path's basic is always on M1
	end
	if not AbilityRules.setUnlocked(Config, hero.level, row.set, main) then
		return false, "set locked", nil, nil
	end
	ranks[id] = AbilityRules.maxRank(row)
	if row.slot == "super" then
		if row.set ~= main then
			return false, "main path only", nil, nil
		end
		loadout.super = id
	else
		local i = table.find(loadout.skills, id)
		if i then
			table.remove(loadout.skills, i)
		end
		table.insert(loadout.skills, 1, id)
		local slots = AbilityRules.skillSlots(Config, hero.level)
		while
			#loadout.skills > 1
			and (#loadout.skills > slots or AbilityRules.loadoutPoints(Config, loadout.skills) > A.loadoutCap)
		do
			table.remove(loadout.skills)
		end
	end
	-- borrowed skills: only the ones in the loadout stay learned
	for rid in table.clone(ranks) do
		local r = A.list[rid]
		if r and r.set ~= main and not table.find(loadout.skills, rid) then
			ranks[rid] = nil
		end
	end
	if AbilityRules.borrowed(Config, ranks, main) > A.borrowMax then
		return false, "borrow limit", nil, nil
	end
	local ok, why = AbilityRules.validate(
		Config,
		{ level = hero.level, startSet = main, ranks = ranks },
		loadout :: Loadout
	)
	if not ok then
		return false, why, nil, nil
	end
	return true, nil, ranks, loadout :: Loadout
end

-- The cooldown a use starts: cut to Config.Dev.lab.cooldown with the lab's switch on (never a basic's)
function LabRules.cooldown(Config: any, lab: any, slot: string?, full: number): number
	if lab and lab.noCd and slot ~= "basic" then
		return math.min(full, Config.Dev.lab.cooldown)
	end
	return full
end

-- Stamina never drains with the lab's switch on
function LabRules.freeStamina(lab: any): boolean
	return lab ~= nil and lab.stamina == true
end

---------------------------------------------------------------------------
-- Mobility
---------------------------------------------------------------------------

-- A pick in the lab at `rank` (default: its last): the ranks list with it, and the moves list with every choice
-- rank it reaches given a move (option 1 where none is picked yet)
function LabRules.mobility(
	base: any,
	ranks: any,
	moves: any,
	pick: string,
	rank: number?
): ({ number }, { number })
	local r = math.clamp(math.floor(rank or MoveRanks.max(base, pick)), 0, MoveRanks.max(base, pick))
	local outRanks = MoveRanks.withRank(base, ranks, pick, r)
	local outMoves = MoveRanks.withChoice(base, moves, pick, 0, 0) -- a clean copy
	for _, c in base.choices or {} do
		if c <= r and MoveRanks.picked(base, outMoves, pick, c) == 0 then
			outMoves = MoveRanks.withChoice(base, outMoves, pick, c, 1)
		end
	end
	return outRanks, outMoves
end

-- A choice value on the wire: rank x 10 + option (31, 32, 51, 52)
function LabRules.choiceValue(rank: number, option: number): number
	return rank * 10 + option
end

function LabRules.choiceOf(value: number): (number, number)
	return value // 10, value % 10
end

---------------------------------------------------------------------------
-- Targets
---------------------------------------------------------------------------

-- The robot kinds the lab spawns one of (by their index in Config.Enemies.order): every kind that is switched on.
-- The evil twin copies its hero, so it has its own command (twin).
function LabRules.robots(Config: any): { { index: number, kind: string, name: string } }
	local out = {}
	for i, kind in Config.Enemies.order do
		local e = Config.Enemies[kind]
		if e and e.on ~= false and kind ~= "EvilTwin" then
			table.insert(out, { index = i, kind = kind, name = e.name or kind })
		end
	end
	return out
end

-- Where the lab puts something `ahead` studs in front of the hero (flat look direction), spread sideways by its
-- place in a row of `count`
function LabRules.spot(
	x: number,
	z: number,
	lookX: number,
	lookZ: number,
	ahead: number,
	slot: number,
	count: number,
	gap: number
): (number, number)
	local m = math.sqrt(lookX * lookX + lookZ * lookZ)
	local fx, fz = if m > 1e-3 then lookX / m else 0, if m > 1e-3 then lookZ / m else -1
	local side = (slot - (count + 1) / 2) * gap
	return x + fx * ahead - fz * side, z + fz * ahead + fx * side
end

return LabRules
