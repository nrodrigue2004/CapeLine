--!strict
-- Remotes: every remote in one table (spec: Remote events). Net creates them in ReplicatedStorage/Remotes,
-- checks every client argument against `schema` and rate-limits each player with a token bucket (`rate` per
-- second, `burst` max). Server-to-client remotes have no schema. Handlers still check state, cooldowns,
-- range and line of sight themselves (the spec's "Server validation" column).
-- Each milestone adds its rows here.

export type RemoteDef = {
	dir: string, -- "C2S" or "S2C"
	unreliable: boolean?,
	schema: { any }?,
	rate: number?,
	burst: number?,
}

local INT = "integer"
local function n(lo: number, hi: number, optional: boolean?)
	return { t = INT, min = lo, max = hi, optional = optional }
end
local V3 = { t = "Vector3" }

local Remotes: { [string]: RemoteDef } = {
	-- Combat (spec: Hit resolution). abilityNum, aimDir, targetHint (enemy id or 0), seq, the hero's own
	-- position as the client saw it (used only to pick the rewind time, never trusted for range)
	CombatUse = { dir = "C2S", schema = { n(1, 64), V3, n(0, 65535), n(0, 2 ^ 31) }, rate = 12, burst = 12 },
	CombatResult = { dir = "S2C" }, -- batched hits, 10 Hz, to players within 150 studs
	CombatEvents = { dir = "S2C" }, -- enemy shots, deaths and hero hits for the effects, 10 Hz batches

	CombatCancel = { dir = "C2S", schema = { n(0, 2 ^ 31) }, rate = 4, burst = 4 }, -- stop a channel (seq)
	Awaken = { dir = "C2S", schema = {}, rate = 1, burst = 2 }, -- spend a full Awakening meter

	-- Abilities (spec: Hero.Loadout, Skills.Rank, Skills.Mod, Skills.Respec). Ability numbers, 0 = empty.
	-- HeroLoadout: loadout index (1-2), primary set (1-5), skills 1-4, super
	HeroLoadout = {
		dir = "C2S",
		schema = { n(1, 2), n(1, 5), n(0, 64), n(0, 64), n(0, 64), n(0, 64), n(0, 64) },
		rate = 2,
		burst = 3,
	},
	SkillsRank = { dir = "C2S", schema = { n(1, 64) }, rate = 4, burst = 4 },
	SkillsMod = { dir = "C2S", schema = { n(1, 64), n(1, 2) }, rate = 2, burst = 4 },
	SkillsRespec = { dir = "C2S", schema = {}, rate = 1, burst = 1 },
	HeroStatus = { dir = "S2C" }, -- { meter, awakeLeft, buffs = { kind = { left, value } } }
	AbilityNotice = { dir = "S2C" }, -- { ok, reason } after a rank, mod, loadout or respec request

	-- Movement (spec: Move.Boost, Move.Correct)
	MoveBoost = { dir = "C2S", schema = { { t = "boolean" } }, rate = 4, burst = 4 },
	MoveCorrect = { dir = "S2C" }, -- position: sent when a speed or position check fails

	-- Enemies (not in the spec's list; see EnemyBuffer and Decisions.md)
	EnemyDelta = { dir = "S2C", unreliable = true },

	-- Hero state the HUD needs that attributes do not carry well
	HeroState = { dir = "S2C" }, -- { level, classId, power, maxHealth, styles, loadout }

	-- Studio only: test commands and server frame stats (DevService refuses them in live servers)
	DevCommand = {
		dir = "C2S",
		schema = { { t = "string", max = 24 }, n(0, 1000, true) },
		rate = 4,
		burst = 6,
	},
	DevStats = { dir = "S2C" },

	-- Saves, gear and economy (spec: Profile.Sync, Gear.Equip, Gear.Upgrade, Gear.Salvage, Gear.Retune,
	-- Style.Apply, Toast). Piece ids are numbers; the server checks ownership, level and the wallet.
	ProfileSync = { dir = "S2C" }, -- ProfileSchema.clientView
	Toast = { dir = "S2C" }, -- { id = "levelUp" | "reward" | "saveDown" | "secondWind" | "gear", ... }
	LootDrop = { dir = "S2C" }, -- { piece, kind = "stashed" | "salvaged", dust }
	CooldownCut = { dir = "S2C" }, -- ability num, seconds (Cooling Kill)
	GearEquip = { dir = "C2S", schema = { n(0, 2 ^ 31), n(1, 8) }, rate = 4, burst = 6 }, -- piece id (0 = take off), slot
	GearUpgrade = { dir = "C2S", schema = { n(1, 2 ^ 31) }, rate = 4, burst = 6 },
	-- up to 20 piece ids; GearService checks each
	GearSalvage = {
		dir = "C2S",
		schema = { { t = "intList", maxLen = 20, min = 1, max = 2 ^ 31 } },
		rate = 1,
		burst = 2,
	},
	GearRetune = { dir = "C2S", schema = { n(1, 2 ^ 31), n(1, 3) }, rate = 1, burst = 2 },
	StyleApply = { dir = "C2S", schema = { n(1, 8), n(0, 511) }, rate = 4, burst = 6 }, -- slot, style (0 = the gear's own)
	GadgetUse = { dir = "C2S", schema = { V3 }, rate = 2, burst = 2 }, -- aim direction
	GadgetResult = { dir = "S2C" }, -- { kind, target, cd }

	-- World (M4; spec: Move.FastTravel at 1 per 20 s; the skip is the "skippable" part of the 3 s flight)
	MoveFastTravel = { dir = "C2S", schema = { n(1, 12) }, rate = 0.5, burst = 2 },
	MoveTravelSkip = { dir = "C2S", schema = {}, rate = 1, burst = 2 },
	FastTravel = { dir = "S2C" }, -- { ok, id, from, to, time } or { ok = false, reason, wait }
	FastTravelDone = { dir = "S2C" }, -- beacon id: the hero has landed

	-- Destruction (M5; spec: Building.Diff 2 Hz batched, Building.Snapshot on join). The client asks for the
	-- snapshot once its effects are ready, so it never misses the first diffs.
	BuildingSync = { dir = "C2S", schema = {}, rate = 0.2, burst = 2 },
	BuildingSnapshot = { dir = "S2C" }, -- { s = packed 2-bit states, n, dr = drone jobs }
	BuildingDiff = { dir = "S2C" }, -- { d = { id, state, ... }, dr = { { drone, building, seconds } } }
	BuildingImpact = { dir = "S2C" }, -- center, radius, kind (1 crater, 2 cracks)
	VehicleFlip = { dir = "S2C" }, -- vehicle id, push x, push z
	VehicleReset = { dir = "S2C" }, -- vehicle id
	CitizenDelta = { dir = "S2C", unreliable = true }, -- CitizenBuffer packet, 4 Hz

	-- World activity (M6; spec: Incident.Spawn/Update, Contract.Accept/Abandon/Update, Boss.State/
	-- Contribution/Result, Event.State, World.Clock). Rescues and the board open use ProximityPrompts (the
	-- server's own check), so Rescue.Pick and Rescue.Drop have no remotes (Decisions.md).
	IncidentSpawn = { dir = "S2C" }, -- { id, num, x, y, z, side, level, left, own, steps, kind }: one incident
	IncidentUpdate = { dir = "S2C" }, -- array of { id, frac, step, have, need, left, state, medal }, 2 Hz
	ContractBoard = { dir = "S2C" }, -- { offers, active, done, level }: the board screen
	ContractAccept = { dir = "C2S", schema = { n(1, 3) }, rate = 2, burst = 3 }, -- offer index
	ContractAbandon = { dir = "C2S", schema = { n(1, 3) }, rate = 2, burst = 3 }, -- active index
	ContractUpdate = { dir = "S2C" }, -- { list = { num, got, goal, dist, dx, dz } }, 2 Hz
	EventState = { dir = "S2C" }, -- { list = { num, x, z, left, have, need, state } }
	BossState = { dir = "S2C" }, -- { state, num, x, y, z, yaw, hp, max, phase, at, objectives }, 2 Hz
	BossAttack = { dir = "S2C" }, -- { kind, shape, x, z, yaw, r, warn }: telegraphs and strikes
	BossContribution = { dir = "S2C" }, -- { score, tier, rank, heroes }, 1 Hz to each fighter
	BossResult = { dir = "S2C" }, -- { defeated, tier, rank, credits, renown, drops, style, mvp }
	WorldClock = { dir = "S2C" }, -- { start, cycle }: the client works out the time of day
}

return Remotes
