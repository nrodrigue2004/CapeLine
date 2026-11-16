--!strict
-- Remotes: every remote in one table (spec: Remote events). Net creates them in ReplicatedStorage/Remotes,
-- checks every client argument against `schema` and rate-limits each player with a token bucket (`rate` per
-- second, `burst` max). Server-to-client remotes have no schema. Handlers still check state, cooldowns,
-- range and line of sight themselves (the spec's "Server validation" column).
-- Milestone 1 declares only what M1 uses; later milestones add their rows here.

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
}

return Remotes
