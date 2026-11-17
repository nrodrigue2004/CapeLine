--!strict
-- FxPlan: the effects library's rules (overhaul plan step 3), kept pure so Lune tests them. FxLib (client)
-- draws what these say.
-- * elementOf: a power set's element (electric, ice, fire...), which picks the particles it adds.
-- * plan: the particle kinds and counts for one moment (an impact, a trail point or a burst), scaled by the
--   device preset and the style (Comic draws fewer, chunkier ones; Anime the full count).
-- * the budget: particles a second this device may emit; a burst over it is trimmed, never queued.
-- * shockRadius: shockwave rings come in a few sizes so each size keeps its own emitter.
-- * textureOf: the uploaded sheet when nate has put its id in Config, else Roblox's built-in image.
-- * Every power path's own look (overhaul plan step 6): the names a Config.Fx.paths row may use (CombatFx
--   draws each), the cost of a moment and of a whole super, piece counts per preset and the charge motes' orbit.

local FxPlan = {}

export type Budget = { perSecond: number, tokens: number, at: number }
export type Emit = { kind: string, count: number }

function FxPlan.elementOf(L: any, set: string?): string
	return L.setElement[set or "Volt"] or "energy"
end

-- the kinds and counts for an element's moment ("impact", "trail" or "burst"), scaled by the preset share
-- and a size factor (a crit or a super draws more). Kinds are sorted so the plan is the same every time.
function FxPlan.plan(L: any, element: string, moment: string, share: number, scale: number?): { Emit }
	local e = L.elements[element] or L.elements.energy
	local list = e[moment] or {}
	local out: { Emit } = {}
	local kinds = {}
	for kind in list do
		table.insert(kinds, kind)
	end
	table.sort(kinds)
	for _, kind in kinds do
		local base = list[kind]
		-- one-off kinds (a single glow, ring or core) always show; the rest scale
		local n = if base <= 1 then base else math.max(1, math.floor(base * share * (scale or 1) + 0.5))
		table.insert(out, { kind = kind, count = n })
	end
	return out
end

function FxPlan.newBudget(perSecond: number, now: number): Budget
	return { perSecond = perSecond, tokens = perSecond, at = now }
end

-- take up to n particles from the budget; returns how many may be drawn
function FxPlan.take(b: Budget, n: number, now: number): number
	local dt = math.max(0, now - b.at)
	b.at = now
	b.tokens = math.min(b.perSecond, b.tokens + dt * b.perSecond)
	local got = math.min(n, math.floor(b.tokens))
	b.tokens -= got
	return math.max(0, got)
end

function FxPlan.shockRadius(L: any, radius: number): number
	local best, gap = L.shockRadii[1], math.huge
	for _, r in L.shockRadii do
		local d = math.abs(r - radius)
		if d < gap then
			best, gap = r, d
		end
	end
	return best
end

-- the points along a path where a trail emits (at most trailMax, spread evenly, ends excluded)
function FxPlan.trailPoints(L: any, length: number): { number }
	local n = math.clamp(math.floor(length / L.trailStep), 1, L.trailMax)
	local out = {}
	for i = 1, n do
		table.insert(out, i / (n + 1))
	end
	return out
end

-- the texture a kind draws with: the uploaded sheet (and its flipbook grid) or the built-in image
function FxPlan.textureOf(L: any, kind: string): (string, number?)
	local k = L.kinds[kind]
	local t = k and L.textures[k.tex]
	if not t then
		return "", nil
	end
	if t.id and t.id > 0 then
		return "rbxassetid://" .. tostring(t.id), t.flip
	end
	return t.builtin, nil
end

-- kinds that flash bright (skipped with Reduce flashing on)
FxPlan.FLASHY = { glow = true, core = true, crackle = true }

---------------------------------------------------------------------------
-- Every path's own look (overhaul plan step 6; Config.Fx.paths, drawn by CombatFx's path section)
---------------------------------------------------------------------------

-- the names a path row may use; CombatFx has one drawing for each (tests check both sides)
FxPlan.HEADS = {
	"none",
	"spike",
	"fireball",
	"rock",
	"glob",
	"tracer",
	"plasma",
	"kunai",
	"kiorb",
	"boulder",
	"lens",
	"psiring",
	"wisp",
	"lance",
}
FxPlan.MARKS = {
	"none",
	"crystals",
	"puff",
	"rubble",
	"crown",
	"cross",
	"ricochet",
	"hexes",
	"ink",
	"pow",
	"kiring",
	"clang",
	"quake",
	"warp",
	"sigil",
	"soulflare",
	"prism",
}
FxPlan.CASTS = {
	"none",
	"frostring",
	"flare",
	"stomp",
	"swirl",
	"glint",
	"muzzle",
	"reticle",
	"smoke",
	"crack",
	"aura",
	"steam",
	"footprint",
	"rings",
	"eye",
	"guardian",
	"halo",
}
FxPlan.DASHES = { "none", "afterimage", "plow", "trail", "smoke" }
FxPlan.MOTIONS = { "fall", "rise", "swirl", "orbit", "pop" }
FxPlan.PIECES = {
	"none",
	"ball",
	"spike",
	"shard",
	"rock",
	"drop",
	"ember",
	"kunai",
	"plate",
	"tri",
	"ring",
	"flame",
	"flake",
}
FxPlan.SUPERS = {
	"none",
	"icecrown",
	"sunfall",
	"overgrowth",
	"tsunami",
	"splitter",
	"highnoon",
	"mechdrop",
	"eclipse",
	"meteor",
	"heavenfall",
	"siege",
	"titanrise",
	"singularity",
	"psistorm",
	"ascend",
	"dawn",
}

-- a path's look row, or nil (weapon moves and unknown sets keep the shapes alone)
function FxPlan.pathOf(F: any, set: string?): any?
	return set and F.paths[set] or nil
end

-- how many particles one moment draws (the sum of its plan)
function FxPlan.cost(L: any, element: string, moment: string, share: number, scale: number?): number
	local n = 0
	for _, e in FxPlan.plan(L, element, moment, share, scale) do
		n += e.count
	end
	return n
end

-- a super's whole moment: its burst (big), its own particles and a crit on superTargets robots
function FxPlan.superCost(L: any, element: string, share: number): number
	return FxPlan.cost(L, element, "burst", share, 1.6)
		+ FxPlan.cost(L, element, "super", share, 1)
		+ L.superTargets * FxPlan.cost(L, element, "impact", share, 1.5)
end

-- how many part-built pieces an accent draws on this preset (a share of n, at least one)
function FxPlan.pieces(L: any, preset: string, n: number, scale: number?): number
	local share = L.scale[preset] or L.scale.medium
	return math.max(1, math.floor(n * share * (scale or 1) + 0.5))
end

-- where charge mote i of n sits around the hand: wide and slow when the charge starts, tight, quick and big
-- at full (level 0 to 1, t in seconds). Returns the offset (x, y, z) and the mote's size.
function FxPlan.orbit(charge: any, level: number, t: number, i: number): (number, number, number, number)
	local k = math.clamp(level, 0, 1)
	local n = math.max(1, charge.n)
	local r = charge.radius * (1.6 - 0.9 * k)
	local a = t * charge.spin * (1 + k) + (i - 1) / n * math.pi * 2
	-- each mote on its own tilted circle, so rings of motes read as an orb rather than a flat disc
	local tilt = ((i - 1) % 3 - 1) * 0.5
	local x = math.cos(a) * r
	local z = math.sin(a) * r
	local y = math.sin(a) * r * tilt + math.sin(t * 3 + i) * 0.3 * (1 - k)
	return x, y, z * math.cos(tilt), 0.3 + 0.5 * k
end

return FxPlan
