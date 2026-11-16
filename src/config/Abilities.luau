-- The launch abilities (spec: Classes and power sets > The 32 launch abilities, plus the Blade set added by
-- nate on 2026-11-16 for the anime side). Coeff is the multiplier in the damage formula (per hit unless
-- noted); cd is seconds before Focus; pts is the loadout budget cost. `num` is the network id.
-- `shape` tells CombatService how the ability finds targets and what it does:
--   bolt   single target along the aim (hitscan with a fat radius and the target hint)
--   chain  first target in a cone, then jumps to the nearest new target within `jump`
--   dash   the hero dashes `range` along the aim and hits everything within `width` of the path
--   cone   everything in a cone of `cone` degrees and `range`
--   arc    melee: everything within `range` in front (`cone` wide); `hits` lists combo coefficients
--   nova   everything within `radius` of the hero, at once
--   field  an area that lasts `duration` and ticks every `tick` s; `at` = "self" (follows), "here" or "aim"
--   line   everything within `width` of a line of `range` along the aim (blocked by buildings)
--   leap   the hero leaps to the aim point (up to `range`) and lands with a nova of `radius`
--   throw  lift the nearest machine within 12 studs (or a prop) and throw it at the aim; landing nova
--   buff   a timed effect on the hero (and allies within `radius` when `allies`)
--   wall   blocking pieces in front for `duration` (stop enemy shots)
--   ramp   a skatable ramp along the aim for `duration`
-- `status` on a hit: stun, root, slow (with `slow` multiplier), knockup, knockback (`knock` studs), pull
-- (toward the hero), float, blind. `cast` is a windup before the effect. `channel` repeats ticks on one target.
-- mods: rank 3 picks one of two; cap: the rank 5 capstone. Each is { name, add = {...}, mul = {...}, set = {...} }
-- applied to this row's numbers (AbilityRules.effective).

local A = {}

local function add(num: number, id: string, row: { [string]: any })
	row.num = num
	row.id = id
	A[id] = row
end

---------------------------------------------------------------------------
-- Volt (start): clears groups
---------------------------------------------------------------------------
add(1, "ZapBolt", {
	set = "Volt",
	slot = "basic",
	name = "Zap Bolt",
	shape = "bolt",
	coeff = 0.6,
	cd = 0.5,
	range = 45,
	radius = 3,
	pts = 0,
})
add(2, "ChainLightning", {
	set = "Volt",
	slot = "skill",
	name = "Chain Lightning",
	shape = "chain",
	coeff = 1.2,
	cd = 6,
	range = 50,
	cone = 30,
	targets = 3,
	jump = 18,
	pts = 12,
	mods = {
		{ name = "Five Targets", add = { targets = 2 } },
		{ name = "Stunning Arc", set = { status = "stun", statusDur = 1, firstOnly = true } },
	},
	cap = { name = "Overload", add = { jump = 8 }, mul = { coeff = 1.25 } },
})
add(3, "DashStrike", {
	set = "Volt",
	slot = "skill",
	name = "Dash Strike",
	shape = "dash",
	coeff = 1.5,
	cd = 8,
	range = 30,
	width = 6,
	time = 0.18,
	pts = 11,
	mods = {
		{ name = "Long Dash", mul = { range = 1.4 } },
		{ name = "Static Wake", set = { status = "stun", statusDur = 0.6 } },
	},
	cap = { name = "Double Back", set = { recast = true } },
})
add(4, "StaticField", {
	set = "Volt",
	slot = "skill",
	name = "Static Field",
	shape = "field",
	at = "here",
	coeff = 0.3,
	cd = 12,
	radius = 15,
	duration = 4,
	tick = 0.25,
	pts = 12,
	mods = {
		{ name = "Wide Field", mul = { radius = 1.3 } },
		{ name = "Lasting Field", add = { duration = 2 } },
	},
	cap = { name = "Sticky Static", set = { status = "slow", slow = 0.7, statusDur = 0.5 } },
})
add(5, "ArcFlash", {
	set = "Volt",
	slot = "skill",
	name = "Arc Flash",
	shape = "cone",
	coeff = 0.5,
	cd = 14,
	range = 20,
	cone = 60,
	status = "stun",
	statusDur = 0.8,
	pts = 10,
	mods = {
		{ name = "Long Flash", add = { statusDur = 0.4 } },
		{ name = "Wide Flash", mul = { cone = 1.5 } },
	},
	cap = { name = "Blinding Arc", set = { status2 = "blind", status2Dur = 3 } },
})
add(6, "Overcharge", {
	set = "Volt",
	slot = "skill",
	name = "Overcharge",
	shape = "buff",
	coeff = 0,
	cd = 20,
	buff = "attackSpeed",
	value = 0.25,
	duration = 6,
	pts = 9,
	mods = {
		{ name = "Longer Charge", add = { duration = 3 } },
		{ name = "Hotter Charge", add = { value = 0.1 } },
	},
	cap = { name = "Shared Charge", set = { allies = true, radius = 20 } },
})
add(7, "GroundSpark", {
	set = "Volt",
	slot = "skill",
	name = "Ground Spark",
	shape = "line",
	ground = true, -- runs along the street
	coeff = 1.0,
	cd = 5,
	range = 60,
	width = 5,
	pts = 8,
	mods = {
		{ name = "Long Spark", mul = { range = 1.3 } },
		{ name = "Jolting Spark", set = { status = "slow", slow = 0.6, statusDur = 1.5 } },
	},
	cap = { name = "Twin Spark", set = { twin = true } },
})
add(8, "ThunderDrop", {
	set = "Volt",
	slot = "super",
	name = "Thunder Drop",
	shape = "nova",
	slam = true, -- dives to the ground below first
	coeff = 4.0,
	cd = 90,
	radius = 25,
	status = "stun",
	statusDur = 1,
	structDmg = 3000,
	pts = 20,
	mods = { { name = "Wide Ring", mul = { radius = 1.2 } }, { name = "Quick Charge", mul = { cd = 0.85 } } },
	cap = { name = "Aftershock", set = { echo = 0.5 } },
})

---------------------------------------------------------------------------
-- Frost (level 6): slows, roots, shields, puts out fires
---------------------------------------------------------------------------
add(9, "IceShard", {
	set = "Frost",
	slot = "basic",
	name = "Ice Shard",
	shape = "bolt",
	coeff = 0.55,
	cd = 0.5,
	range = 45,
	radius = 3,
	status = "slow",
	slow = 0.85,
	statusDur = 1,
	pts = 0,
})
add(10, "FreezeBeam", {
	set = "Frost",
	slot = "skill",
	name = "Freeze Beam",
	shape = "bolt",
	channel = 12, -- ticks (3 s)
	tick = 0.25,
	coeff = 0.35,
	cd = 10,
	range = 40,
	radius = 3.5,
	status = "slow",
	slow = 0.6,
	statusDur = 0.5,
	pts = 12,
	mods = { { name = "Deep Freeze", set = { slow = 0.45 } }, { name = "Long Beam", mul = { range = 1.3 } } },
	cap = { name = "Frozen Solid", set = { endStatus = "root", endStatusDur = 1.5 } },
})
add(11, "IceSlide", {
	set = "Frost",
	slot = "skill",
	name = "Ice Slide",
	shape = "ramp",
	coeff = 0,
	cd = 10,
	range = 40,
	duration = 6,
	pts = 8,
	mods = {
		{ name = "Long Slide", mul = { range = 1.4 } },
		{ name = "Lasting Ice", add = { duration = 3 } },
	},
	cap = { name = "Chill Trail", set = { slowTouch = true } },
})
add(12, "FrostNova", {
	set = "Frost",
	slot = "skill",
	name = "Frost Nova",
	shape = "nova",
	coeff = 1.0,
	cd = 12,
	radius = 18,
	status = "root",
	statusDur = 1.5,
	pts = 13,
	mods = {
		{ name = "Wide Nova", mul = { radius = 1.25 } },
		{ name = "Long Root", add = { statusDur = 0.75 } },
	},
	cap = { name = "Frost Shell", set = { selfShield = 0.08 } },
})
add(13, "SnowWall", {
	set = "Frost",
	slot = "skill",
	name = "Snow Wall",
	shape = "wall",
	coeff = 0,
	cd = 16,
	range = 20,
	pieces = 3,
	duration = 5,
	pts = 10,
	mods = { { name = "Five Pieces", add = { pieces = 2 } }, { name = "Thick Snow", add = { duration = 3 } } },
	cap = { name = "Ice Spikes", set = { touchCoeff = 0.5 } },
})
add(14, "GlacierArmor", {
	set = "Frost",
	slot = "skill",
	name = "Glacier Armor",
	shape = "buff",
	coeff = 0,
	cd = 18,
	buff = "shield",
	value = 0.20,
	duration = 6,
	pts = 11,
	mods = {
		{ name = "Thick Armor", add = { value = 0.08 } },
		{ name = "Long Armor", add = { duration = 3 } },
	},
	cap = { name = "Shatter Shell", set = { burst = 1.0, radius = 12 } },
})
add(15, "Shatter", {
	set = "Frost",
	slot = "skill",
	name = "Shatter",
	shape = "bolt",
	coeff = 2.2,
	cd = 8,
	range = 40,
	radius = 3,
	bonusVs = "slow",
	bonus = 0.5,
	pts = 14,
	mods = { { name = "Brittle", add = { bonus = 0.3 } }, { name = "Quick Shatter", mul = { cd = 0.8 } } },
	cap = { name = "Splinters", set = { splash = 0.5, radius = 8 } },
})
add(16, "BlizzardDome", {
	set = "Frost",
	slot = "super",
	name = "Blizzard Dome",
	shape = "field",
	at = "here",
	coeff = 0.5,
	cd = 100,
	radius = 30,
	duration = 8,
	tick = 1,
	status = "slow",
	slow = 0.5,
	statusDur = 1.2,
	allyResist = 0.15,
	pts = 20,
	mods = { { name = "Big Dome", mul = { radius = 1.2 } }, { name = "Long Storm", add = { duration = 3 } } },
	cap = { name = "Whiteout Core", set = { endStatus = "root", endStatusDur = 2 } },
})

---------------------------------------------------------------------------
-- Titan (level 10): melee, lifting, holding trams
---------------------------------------------------------------------------
add(17, "PunchCombo", {
	set = "Titan",
	slot = "basic",
	name = "Punch Combo",
	shape = "arc",
	coeff = 0.7,
	hits = { 0.7, 0.7, 1.1 },
	cd = 0.5,
	range = 9,
	cone = 90,
	pts = 0,
})
add(18, "LiftAndThrow", {
	set = "Titan",
	slot = "skill",
	name = "Lift and Throw",
	shape = "throw",
	coeff = 2.0,
	cd = 7,
	range = 30,
	radius = 8,
	structDmg = 1200,
	pts = 12,
	mods = { { name = "Far Throw", mul = { range = 1.5 } }, { name = "Big Impact", mul = { radius = 1.4 } } },
	cap = { name = "Double Toss", set = { recast = true } },
})
add(19, "GroundSlam", {
	set = "Titan",
	slot = "skill",
	name = "Ground Slam",
	shape = "nova",
	coeff = 1.6,
	cd = 9,
	radius = 14,
	status = "knockup",
	statusDur = 0.8,
	structDmg = 800,
	pts = 12,
	mods = {
		{ name = "Wide Slam", mul = { radius = 1.25 } },
		{ name = "High Toss", add = { statusDur = 0.4 } },
	},
	cap = { name = "Shockwave", set = { echo = 0.5 } },
})
add(20, "ShoulderCharge", {
	set = "Titan",
	slot = "skill",
	name = "Shoulder Charge",
	shape = "dash",
	coeff = 1.3,
	cd = 10,
	range = 40,
	width = 7,
	time = 0.3,
	status = "knockback",
	knock = 14,
	pts = 11,
	mods = {
		{ name = "Freight Train", mul = { range = 1.3 } },
		{ name = "Bowling Ball", add = { knock = 10 } },
	},
	cap = { name = "Wall Breaker", set = { stunOnWall = 1.5 } },
})
add(21, "Brace", {
	set = "Titan",
	slot = "skill",
	name = "Brace",
	shape = "buff",
	coeff = 0,
	cd = 14,
	buff = "mitigation",
	value = 0.40,
	duration = 3,
	taunt = 25,
	pts = 10,
	mods = {
		{ name = "Long Brace", add = { duration = 1.5 } },
		{ name = "Loud Taunt", mul = { taunt = 1.4 } },
	},
	cap = { name = "Thorns", set = { reflect = 0.3 } },
})
add(22, "Haymaker", {
	set = "Titan",
	slot = "skill",
	name = "Haymaker",
	shape = "arc",
	cast = 1,
	coeff = 3.0,
	cd = 12,
	range = 10,
	cone = 60,
	maxTargets = 1,
	status = "knockback",
	knock = 24,
	structDmg = 1200,
	pts = 14,
	mods = {
		{ name = "Quick Wind", mul = { cast = 0.6 } },
		{ name = "Sweeping Blow", set = { maxTargets = 4 } },
	},
	cap = { name = "Sky Launcher", set = { status = "knockup", statusDur = 1.4 } },
})
add(23, "RallyRoar", {
	set = "Titan",
	slot = "skill",
	name = "Rally Roar",
	shape = "buff",
	coeff = 0,
	cd = 24,
	buff = "power",
	value = 0.10,
	duration = 8,
	allies = true,
	radius = 30,
	pts = 10,
	mods = { { name = "Battle Cry", add = { value = 0.05 } }, { name = "Long Roar", add = { duration = 4 } } },
	cap = { name = "Second Breath", set = { heal = 0.1 } },
})
add(24, "MeteorLeap", {
	set = "Titan",
	slot = "super",
	name = "Meteor Leap",
	shape = "leap",
	coeff = 4.5,
	cd = 90,
	range = 100,
	radius = 22,
	status = "knockup",
	statusDur = 1,
	structDmg = 3000,
	time = 1.1,
	pts = 20,
	mods = { { name = "Far Leap", mul = { range = 1.3 } }, { name = "Quick Charge", mul = { cd = 0.85 } } },
	cap = { name = "Molten Crater", set = { fieldCoeff = 0.4, fieldDur = 3 } },
})

---------------------------------------------------------------------------
-- Pulse (level 14): gravity, floats citizens and objects
---------------------------------------------------------------------------
add(25, "PushWave", {
	set = "Pulse",
	slot = "basic",
	name = "Push Wave",
	shape = "cone",
	coeff = 0.5,
	cd = 0.5,
	range = 30,
	cone = 40,
	status = "knockback",
	knock = 8,
	pts = 0,
})
add(26, "Pull", {
	set = "Pulse",
	slot = "skill",
	name = "Pull",
	shape = "bolt",
	coeff = 0.6,
	cd = 7,
	range = 50,
	radius = 4,
	status = "pull",
	pts = 10,
	mods = {
		{ name = "Two Pulls", set = { targets = 2 } },
		{ name = "Dizzy Pull", set = { status2 = "stun", status2Dur = 0.8 } },
	},
	cap = { name = "Yank", mul = { coeff = 2 } },
})
add(27, "Float", {
	set = "Pulse",
	slot = "skill",
	name = "Float",
	shape = "bolt",
	coeff = 0,
	cd = 10,
	range = 40,
	radius = 4,
	status = "float",
	statusDur = 3,
	pts = 9,
	mods = {
		{ name = "Long Float", add = { statusDur = 1.5 } },
		{ name = "Group Float", set = { splash = 0, radius = 8 } },
	},
	cap = { name = "Drop", set = { endCoeff = 1.5 } },
})
add(28, "GravityWell", {
	set = "Pulse",
	slot = "skill",
	name = "Gravity Well",
	shape = "field",
	at = "aim",
	coeff = 0.2, -- per tick (0.4 per second)
	cd = 14,
	range = 50,
	radius = 16,
	duration = 2,
	tick = 0.5,
	status = "pull",
	pts = 13,
	mods = {
		{ name = "Deep Well", mul = { radius = 1.3 } },
		{ name = "Long Well", add = { duration = 1.5 } },
	},
	cap = { name = "Collapse", set = { endCoeff = 1.5 } },
})
add(29, "Repulse", {
	set = "Pulse",
	slot = "skill",
	name = "Repulse",
	shape = "nova",
	coeff = 1.2,
	cd = 9,
	radius = 14,
	status = "knockback",
	knock = 18,
	pts = 11,
	mods = {
		{ name = "Wide Repulse", mul = { radius = 1.3 } },
		{ name = "Hard Repulse", add = { knock = 10 } },
	},
	cap = { name = "Rebound", set = { echo = 0.5 } },
})
add(30, "Weightless", {
	set = "Pulse",
	slot = "skill",
	name = "Weightless",
	shape = "buff",
	coeff = 0,
	cd = 20,
	buff = "speed",
	value = 0.30,
	duration = 6,
	allies = true,
	radius = 20,
	pts = 9,
	mods = { { name = "Feather", add = { value = 0.1 } }, { name = "Long Float", add = { duration = 3 } } },
	cap = { name = "Zero G", set = { staminaFree = true } },
})
add(31, "Crush", {
	set = "Pulse",
	slot = "skill",
	name = "Crush",
	shape = "bolt",
	cast = 1,
	coeff = 2.4,
	cd = 11,
	range = 40,
	radius = 4,
	pts = 14,
	mods = {
		{ name = "Quick Crush", mul = { cast = 0.5 } },
		{ name = "Heavy Crush", set = { status = "stun", statusDur = 1 } },
	},
	cap = { name = "Implode", set = { splash = 0.6, radius = 10 } },
})
add(32, "Singularity", {
	set = "Pulse",
	slot = "super",
	name = "Singularity",
	shape = "field",
	at = "aim",
	coeff = 0.1, -- per tick; the burst is endCoeff
	cd = 100,
	range = 60,
	radius = 35,
	duration = 3,
	tick = 0.5,
	status = "pull",
	endCoeff = 3.5,
	pts = 20,
	mods = {
		{ name = "Event Horizon", mul = { radius = 1.2 } },
		{ name = "Quick Charge", mul = { cd = 0.85 } },
	},
	cap = { name = "Big Bang", set = { endStatus = "stun", endStatusDur = 1.5 } },
})

---------------------------------------------------------------------------
-- Blade (level 18, added 2026-11-16): energy sword dashes, combos and slash waves (the anime side; all
-- original moves, nothing named or shaped after a real show)
---------------------------------------------------------------------------
add(33, "BladeSlash", {
	set = "Blade",
	slot = "basic",
	name = "Blade Slash",
	shape = "arc",
	coeff = 0.65,
	hits = { 0.65, 0.65, 1.0 },
	cd = 0.5,
	range = 11,
	cone = 120,
	pts = 0,
})
add(34, "FlashStep", {
	set = "Blade",
	slot = "skill",
	name = "Flash Step",
	shape = "dash",
	coeff = 1.4,
	cd = 8,
	range = 35,
	width = 6,
	time = 0.1,
	pts = 11,
	mods = { { name = "Far Step", mul = { range = 1.3 } }, { name = "Afterimage", set = { echo = 0.5 } } },
	cap = { name = "Twin Step", set = { recast = true } },
})
add(35, "CrescentWave", {
	set = "Blade",
	slot = "skill",
	name = "Crescent Wave",
	shape = "line",
	coeff = 1.3,
	cd = 7,
	range = 50,
	width = 8,
	pts = 11,
	mods = { { name = "Long Wave", mul = { range = 1.3 } }, { name = "Wide Wave", mul = { width = 1.5 } } },
	cap = { name = "Cross Wave", set = { twin = true } },
})
add(36, "RisingBlade", {
	set = "Blade",
	slot = "skill",
	name = "Rising Blade",
	shape = "arc",
	coeff = 1.5,
	cd = 9,
	range = 10,
	cone = 90,
	status = "knockup",
	statusDur = 0.8,
	pts = 12,
	mods = { { name = "High Rise", add = { statusDur = 0.4 } }, { name = "Wide Rise", mul = { cone = 1.5 } } },
	cap = { name = "Sky Cut", set = { followUp = 1.0 } },
})
add(37, "ThousandCuts", {
	set = "Blade",
	slot = "skill",
	name = "Thousand Cuts",
	shape = "arc",
	maxTargets = 1,
	coeff = 0.35,
	channel = 8, -- ticks (1.2 s flurry on the locked target)
	cd = 12,
	range = 10,
	cone = 90,
	tick = 0.15,
	pts = 14,
	mods = {
		{ name = "Ten Cuts", add = { channel = 2 } },
		{ name = "Sweeping Cuts", set = { maxTargets = 3 } },
	},
	cap = { name = "Final Cut", set = { endCoeff = 1.2 } },
})
add(38, "ParryStance", {
	set = "Blade",
	slot = "skill",
	name = "Parry Stance",
	shape = "buff",
	coeff = 2.0,
	cd = 14,
	buff = "parry",
	value = 1,
	duration = 1,
	pts = 10,
	mods = {
		{ name = "Patient Guard", add = { duration = 0.5 } },
		{ name = "Sharp Riposte", mul = { coeff = 1.3 } },
	},
	cap = { name = "Perfect Guard", set = { refund = 0.5 } },
})
add(39, "BladeStorm", {
	set = "Blade",
	slot = "skill",
	name = "Blade Storm",
	shape = "field",
	at = "self",
	coeff = 0.35,
	cd = 16,
	radius = 10,
	duration = 4,
	tick = 0.33,
	pts = 12,
	mods = {
		{ name = "Wide Storm", mul = { radius = 1.3 } },
		{ name = "Long Storm", add = { duration = 2 } },
	},
	cap = { name = "Cutting Wind", set = { status = "slow", slow = 0.7, statusDur = 0.5 } },
})
add(40, "HeavenSplitter", {
	set = "Blade",
	slot = "super",
	name = "Heaven Splitter",
	shape = "line",
	cast = 0.6,
	coeff = 4.2,
	cd = 95,
	range = 80,
	width = 14,
	structDmg = 3000,
	pts = 20,
	mods = { { name = "Long Split", mul = { range = 1.25 } }, { name = "Quick Charge", mul = { cd = 0.85 } } },
	cap = { name = "Second Cut", set = { echo = 0.6 } },
})

local byNum = {}
local order = {}
for _, row in A do
	byNum[row.num] = row
end
for num = 1, #byNum do
	table.insert(order, byNum[num].id)
end

return {
	list = A,
	byNum = byNum,
	order = order,
	sets = { "Volt", "Frost", "Titan", "Pulse", "Blade" },
	-- Sets unlock by level (spec: Rookie Trials finish the unlock; trials arrive with M7's content)
	setUnlockLevel = { Volt = 1, Frost = 6, Titan = 10, Pulse = 14, Blade = 18 },
	setColor = {
		Volt = { 120, 210, 255 },
		Frost = { 190, 235, 255 },
		Titan = { 255, 150, 60 },
		Pulse = { 190, 120, 255 },
		Blade = { 255, 70, 90 },
	},
	loadoutCap = 52, -- the four skills may total at most 52 points; the super is a fixed 20 outside it
	superPts = 20,
	-- skill slots by level (spec: Levels: 2 slots at 1, slot 3 at 5, slot 4 at 10, super at 20)
	slotLevels = { 1, 1, 5, 10 },
	superLevel = 20,
	secondLoadoutLevel = 15,
	-- ranks (spec: Skill points, ranks and respec)
	rankPoints = { 1, 1, 2, 2, 3 },
	rankCredits = { 100, 250, 600, 1400, 3200 },
	superRankPoints = { 2, 3, 4 },
	superRankCredits = { 300, 900, 2400 }, -- spec: Sinks
	rankCoeff = 0.10, -- rank 2: +10% coeff
	rankCooldown = 0.08, -- rank 4: -8% cooldown
	pointsPerLevel = 1,
	respecCooldown = 600,
	-- every new hero starts with its set's basic and these two skills learned at rank 1
	starter = {
		Volt = { "ChainLightning", "DashStrike" },
		Frost = { "FreezeBeam", "FrostNova" },
		Titan = { "GroundSlam", "ShoulderCharge" },
		Pulse = { "Pull", "Repulse" },
		Blade = { "FlashStep", "CrescentWave" },
	},
	defaultLoadout = {
		set = "Volt",
		basic = "ZapBolt",
		skills = { "ChainLightning", "DashStrike" },
		super = nil,
	},
	-- Awakening (nate, 2026-11-16): a meter fills from fighting; when full, 15 s of power for every hero
	awakening = {
		max = 100,
		gain = { basicHit = 1.5, skillHit = 4, superHit = 8, kill = 6, hurtPerPct = 0.5 },
		duration = 15,
		damage = 0.20, -- +20% damage
		cooldownRate = 1.35, -- skill cooldowns run 35% faster
		superCharge = 0.5, -- the super's cooldown is halved when used while awakened
		superCoeff = 0.30, -- a super cast while awakened hits 30% harder
		pvpDamage = 0.10, -- halved in PvP (M8)
	},
	-- Team-up combos (spec: 6 at launch): two supers within 3 s and 30 studs
	combos = {
		window = 3,
		distance = 30,
		renownBonus = 0.25,
		bonusTime = 10,
		pairs = {
			{
				sets = { "Frost", "Volt" },
				id = "Storm",
				name = "Storm",
				radius = 20,
				coeff = 2.0,
				status = "slow",
				slow = 0.5,
				statusDur = 3,
			},
			{ sets = { "Titan", "Pulse" }, id = "Landslide", name = "Landslide", radius = 18, coeff = 3.0 },
			{
				sets = { "Volt", "Pulse" },
				id = "IonWell",
				name = "Ion Well",
				radius = 16,
				coeff = 1.5,
				status = "stun",
				statusDur = 1.5,
			},
			{
				sets = { "Frost", "Titan" },
				id = "GlacierThrow",
				name = "Glacier Throw",
				radius = 12,
				coeff = 2.2,
				status = "root",
				statusDur = 2,
			},
			{
				sets = { "Frost", "Pulse" },
				id = "Whiteout",
				name = "Whiteout",
				radius = 18,
				coeff = 1.2,
				status = "slow",
				slow = 0.4,
				statusDur = 3,
			},
			{
				sets = { "Volt", "Titan" },
				id = "ThunderFist",
				name = "Thunder Fist",
				radius = 16,
				coeff = 2.5,
			},
			-- Blade pairs (added with the set)
			{ sets = { "Blade", "Volt" }, id = "StormEdge", name = "Storm Edge", radius = 18, coeff = 2.4 },
			{
				sets = { "Blade", "Frost" },
				id = "IceBloom",
				name = "Ice Bloom",
				radius = 16,
				coeff = 2.0,
				status = "root",
				statusDur = 1.5,
			},
			{
				sets = { "Blade", "Titan" },
				id = "SkyBreaker",
				name = "Sky Breaker",
				radius = 16,
				coeff = 2.8,
				status = "knockup",
				statusDur = 1,
			},
			{
				sets = { "Blade", "Pulse" },
				id = "VoidCut",
				name = "Void Cut",
				radius = 20,
				coeff = 2.2,
				status = "pull",
			},
		},
	},
	-- status effect caps (spec: CC duration x Resolve; PvP diminishing returns in M8)
	status = { knockupHeight = 8, floatHeight = 6, pullSpeed = 40 },
}
