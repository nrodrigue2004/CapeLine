-- The 32 launch abilities (spec: Classes and power sets > The 32 launch abilities). Coeff is the multiplier
-- in the damage formula (per hit unless noted); cd is seconds before Focus; pts is the loadout budget cost.
-- `num` is the network id sent in Combat.Use. `shape` tells the Combat service how to find targets:
--   bolt  = fast single-target shot along the aim (hitscan with a fat radius and the target hint)
--   chain = first target in a cone, then jumps to the nearest new target within `jump` studs
--   dash  = the hero dashes `range` studs along the aim and hits everything within `width` of the path
-- `built` marks what the current milestone implements; the rest are data waiting for M2.
local A = {}

local function add(num: number, id: string, row: { [string]: any })
	row.num = num
	row.id = id
	A[id] = row
end

-- Volt (unlocked at start): clears groups
add(1, "ZapBolt", {
	set = "Volt",
	slot = "basic",
	name = "Zap Bolt",
	shape = "bolt",
	coeff = 0.6,
	cd = 0.5, -- 2 per second; the spec's 0 cooldown means "no skill cooldown", the fire rate still applies
	range = 45,
	radius = 3,
	pts = 0,
	built = true,
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
	built = true,
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
	built = true,
})
add(
	4,
	"StaticField",
	{ set = "Volt", slot = "skill", name = "Static Field", coeff = 0.3, cd = 12, radius = 15, pts = 12 }
)
add(
	5,
	"ArcFlash",
	{ set = "Volt", slot = "skill", name = "Arc Flash", coeff = 0.5, cd = 14, cone = 20, pts = 10 }
)
add(6, "Overcharge", { set = "Volt", slot = "skill", name = "Overcharge", coeff = 0, cd = 20, pts = 9 })
add(
	7,
	"GroundSpark",
	{ set = "Volt", slot = "skill", name = "Ground Spark", coeff = 1.0, cd = 5, range = 60, pts = 8 }
)
add(
	8,
	"ThunderDrop",
	{ set = "Volt", slot = "super", name = "Thunder Drop", coeff = 4.0, cd = 90, radius = 25, pts = 20 }
)
-- Frost (level 6)
add(
	9,
	"IceShard",
	{ set = "Frost", slot = "basic", name = "Ice Shard", coeff = 0.55, cd = 0.5, range = 45, pts = 0 }
)
add(
	10,
	"FreezeBeam",
	{ set = "Frost", slot = "skill", name = "Freeze Beam", coeff = 0.35, cd = 10, range = 40, pts = 12 }
)
add(
	11,
	"IceSlide",
	{ set = "Frost", slot = "skill", name = "Ice Slide", coeff = 0, cd = 10, range = 40, pts = 8 }
)
add(
	12,
	"FrostNova",
	{ set = "Frost", slot = "skill", name = "Frost Nova", coeff = 1.0, cd = 12, radius = 18, pts = 13 }
)
add(
	13,
	"SnowWall",
	{ set = "Frost", slot = "skill", name = "Snow Wall", coeff = 0, cd = 16, range = 20, pts = 10 }
)
add(
	14,
	"GlacierArmor",
	{ set = "Frost", slot = "skill", name = "Glacier Armor", coeff = 0, cd = 18, pts = 11 }
)
add(
	15,
	"Shatter",
	{ set = "Frost", slot = "skill", name = "Shatter", coeff = 2.2, cd = 8, range = 40, pts = 14 }
)
add(
	16,
	"BlizzardDome",
	{ set = "Frost", slot = "super", name = "Blizzard Dome", coeff = 0.5, cd = 100, radius = 30, pts = 20 }
)
-- Titan (level 10)
add(
	17,
	"PunchCombo",
	{ set = "Titan", slot = "basic", name = "Punch Combo", coeff = 0.7, cd = 0.4, range = 8, pts = 0 }
)
add(
	18,
	"LiftAndThrow",
	{ set = "Titan", slot = "skill", name = "Lift and Throw", coeff = 2.0, cd = 7, range = 30, pts = 12 }
)
add(
	19,
	"GroundSlam",
	{ set = "Titan", slot = "skill", name = "Ground Slam", coeff = 1.6, cd = 9, radius = 14, pts = 12 }
)
add(
	20,
	"ShoulderCharge",
	{ set = "Titan", slot = "skill", name = "Shoulder Charge", coeff = 1.3, cd = 10, range = 40, pts = 11 }
)
add(21, "Brace", { set = "Titan", slot = "skill", name = "Brace", coeff = 0, cd = 14, radius = 25, pts = 10 })
add(
	22,
	"Haymaker",
	{ set = "Titan", slot = "skill", name = "Haymaker", coeff = 3.0, cd = 12, range = 10, pts = 14 }
)
add(
	23,
	"RallyRoar",
	{ set = "Titan", slot = "skill", name = "Rally Roar", coeff = 0, cd = 24, radius = 30, pts = 10 }
)
add(
	24,
	"MeteorLeap",
	{ set = "Titan", slot = "super", name = "Meteor Leap", coeff = 4.5, cd = 90, radius = 22, pts = 20 }
)
-- Pulse (level 14)
add(
	25,
	"PushWave",
	{ set = "Pulse", slot = "basic", name = "Push Wave", coeff = 0.5, cd = 0.5, range = 30, pts = 0 }
)
add(26, "Pull", { set = "Pulse", slot = "skill", name = "Pull", coeff = 0.6, cd = 7, range = 50, pts = 10 })
add(27, "Float", { set = "Pulse", slot = "skill", name = "Float", coeff = 0, cd = 10, range = 40, pts = 9 })
add(
	28,
	"GravityWell",
	{ set = "Pulse", slot = "skill", name = "Gravity Well", coeff = 0.4, cd = 14, radius = 16, pts = 13 }
)
add(
	29,
	"Repulse",
	{ set = "Pulse", slot = "skill", name = "Repulse", coeff = 1.2, cd = 9, radius = 14, pts = 11 }
)
add(
	30,
	"Weightless",
	{ set = "Pulse", slot = "skill", name = "Weightless", coeff = 0, cd = 20, radius = 20, pts = 9 }
)
add(
	31,
	"Crush",
	{ set = "Pulse", slot = "skill", name = "Crush", coeff = 2.4, cd = 11, range = 40, pts = 14 }
)
add(
	32,
	"Singularity",
	{ set = "Pulse", slot = "super", name = "Singularity", coeff = 3.5, cd = 100, radius = 35, pts = 20 }
)

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
	sets = { "Volt", "Frost", "Titan", "Pulse" },
	setUnlockLevel = { Volt = 1, Frost = 6, Titan = 10, Pulse = 14 },
	loadoutCap = 52, -- the four skills may total at most 52 points; the super is a fixed 20 outside it
	superPts = 20,
	-- M1 slice loadout (basic + 2 skills). The full 4-skill loadout and the super come in M2.
	defaultLoadout = { basic = "ZapBolt", skills = { "ChainLightning", "DashStrike" } },
}
