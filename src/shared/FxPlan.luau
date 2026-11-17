--!strict
-- FxPlan: the effects library's rules (overhaul plan step 3), kept pure so Lune tests them. FxLib (client)
-- draws what these say.
-- * elementOf: a power set's element (electric, ice, fire...), which picks the particles it adds.
-- * plan: the particle kinds and counts for one moment (an impact, a trail point or a burst), scaled by the
--   device preset and the style (Comic draws fewer, chunkier ones; Anime the full count).
-- * the budget: particles a second this device may emit; a burst over it is trimmed, never queued.
-- * shockRadius: shockwave rings come in a few sizes so each size keeps its own emitter.
-- * textureOf: the uploaded sheet when nate has put its id in Config, else Roblox's built-in image.

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

return FxPlan
