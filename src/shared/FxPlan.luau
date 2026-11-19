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
	local look = FxPlan.weaponLook(set)
	if look then
		return L.weaponElement and L.weaponElement[look] or L.setElement.Weapon or "energy"
	end
	return L.setElement[set or "Volt"] or "energy"
end

-- Weapon moves' looks (Config.Fx.weaponLooks): the effects set a weapon draws with is "Weapon:<look>"
local WEAPON_PREFIX = "Weapon:"
function FxPlan.weaponLook(set: string?): string?
	if set and string.sub(set, 1, #WEAPON_PREFIX) == WEAPON_PREFIX then
		return string.sub(set, #WEAPON_PREFIX + 1)
	end
	return nil
end

-- the effects set for a weapon move: its own look, else its family's (family: Config.Weapons family id)
function FxPlan.weaponSet(F: any, weaponId: number?, family: string?): string
	local W = F.weaponLooks
	local look = W and ((weaponId and W.weapon[weaponId]) or (family and W.family[family]))
	return if look and W.looks[look] then WEAPON_PREFIX .. look else "Weapon"
end

-- a weapon look as a full path row (every field CombatFx reads; nothing draws on casts, fields or supers)
local weaponRows: { [string]: any } = {}
local function weaponRow(F: any, look: string): any?
	local src = F.weaponLooks and F.weaponLooks.looks[look]
	if not src then
		return nil
	end
	local row = weaponRows[look]
	if not row then
		row = {
			piece = src.piece,
			accent = src.accent or { 255, 255, 255 },
			head = src.head or "none",
			mark = src.mark or "none",
			cast = "none",
			dash = src.dash or "none",
			field = { piece = "none", motion = "rise" },
			charge = { piece = src.piece, n = 4, radius = 2.4, spin = 6 },
			super = { look = "none", tint = src.color },
		}
		weaponRows[look] = row
	end
	return row
end
FxPlan.weaponRow = weaponRow

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
	local look = FxPlan.weaponLook(set)
	if look then
		return weaponRow(F, look)
	end
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

---------------------------------------------------------------------------
-- Every ability's own look (nate's playtest 2026-11-19: "Need more unique effects"; Config.FxMoves, drawn by
-- the client's Fx/AbilityFx on top of the path's look). Tests: tests/fx_unique_test.luau.
---------------------------------------------------------------------------

-- the names a recipe may use; AbilityFx has one drawing for each (tests check both sides)
FxPlan.TRAILS = { "none", "ribbon", "spiral", "beads", "zigzag", "twin", "comet", "wake", "sparkle", "smoke" }
FxPlan.HITS = {
	"none",
	"ring",
	"crater",
	"sparks",
	"shards",
	"splash",
	"pillar",
	"starburst",
	"petals",
	"spiral",
	"cross",
	"bloom",
	"shatter",
	"bubble",
	"rays",
	"cage",
	"rune",
}
FxPlan.FLAIRS = {
	"none",
	"sigil",
	"crack",
	"burst",
	"spin",
	"pillar",
	"fan",
	"orbs",
	"vent",
	"halo",
	"flash",
	"wings",
	"lines",
	"rune",
	"dust",
}
FxPlan.SCREENS = { "none", "flash", "bars", "vignette", "lines", "slash", "invert", "pulse" }
-- screen moments that flash the whole screen (skipped with Reduce flashing on)
FxPlan.FLASHY_SCREENS = { flash = true, invert = true, pulse = true }
-- the shapes where something flies, so the move has a trail
FxPlan.TRAVEL = { bolt = true, chain = true, line = true, dash = true, leap = true }

-- an ability's recipe, or nil (weapon moves and unknown ids keep the path's look alone)
function FxPlan.recipeOf(M: any, id: string?): any?
	return id and M.moves[id] or nil
end

-- one particle count, scaled like FxPlan.plan (a one-off kind always shows; the rest scale, at least one)
function FxPlan.count(base: number, share: number, scale: number?): number
	if base <= 1 then
		return base
	end
	return math.max(1, math.floor(base * share * (scale or 1) + 0.5))
end

-- what one recipe moment draws on a preset: particles (each kind scaled) and pieces (FxPlan.pieces), times
-- `times` (a trail's points). kind is "trail", "hit" or "flair".
function FxPlan.momentCost(
	L: any,
	M: any,
	kind: string,
	name: string?,
	preset: string,
	scale: number?,
	times: number?
): (number, number)
	local row = name and M.kit[kind][name]
	if not row then
		return 0, 0
	end
	local share = L.scale[preset] or L.scale.medium
	local particles = 0
	for _, n in row.fx do
		particles += FxPlan.count(n, share, scale)
	end
	local parts = if row.parts > 0 then FxPlan.pieces(L, preset, row.parts, scale) else 0
	local k = times or 1
	return particles * k, parts
end

-- a whole move on a preset: its flair, its trail and its hit on `targets` robots (particles, pieces)
function FxPlan.moveCost(
	L: any,
	M: any,
	recipe: any,
	preset: string,
	targets: number,
	scale: number?
): (number, number)
	local p1, q1 = FxPlan.momentCost(L, M, "flair", recipe.flair, preset, scale)
	local p2, q2 = FxPlan.momentCost(L, M, "trail", recipe.trail, preset, scale, M.kit.trailPoints)
	local p3, q3 = FxPlan.momentCost(L, M, "hit", recipe.hit, preset, scale)
	return p1 + p2 + p3 * targets, q1 + q2 + q3 * targets
end

-- the draw size of a recipe for a slot (a basic draws smaller), clamped so no move outgrows its path
function FxPlan.recipeSize(M: any, recipe: any, slot: string?): number
	local s = math.clamp(recipe.size or 1, 0.6, 1.6)
	return if slot == "basic" then s * M.kit.basicScale else s
end

-- what makes a recipe look like itself, for the "no two the same" checks
function FxPlan.recipeKey(recipe: any): string
	return table.concat({
		recipe.flair or "none",
		recipe.hit or "none",
		recipe.trail or "none",
		recipe.head or "-",
		recipe.mark or "-",
		recipe.cast or "-",
		recipe.screen or "none",
	}, "/")
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
