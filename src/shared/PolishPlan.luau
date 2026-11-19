--!strict
-- PolishPlan: the pure numbers behind the gap polish looks (2026-11-19, notes/Tasks.md "Placeholder art"):
-- the decoy hologram's flicker, the shield drone's orbit, the smoke cloud's puffs, which landing crack decal a
-- spot gets and how it fades, the Snow Wall's ice shards and the thrown crate's planks. No Roblox types, so
-- Lune tests them; the client (GadgetFx, IceFx, MoveFx, CombatFx.throwArc) draws from them. Looks only:
-- nothing here changes a collision box, a hit or a timing.

local PolishPlan = {}

-- a small deterministic hash to 0..1 (the same on every device)
local function hash(a: number, b: number?): number
	local h = math.floor(a) * 374761393 + math.floor(b or 0) * 668265263
	h = bit32.bxor(h % 4294967296, bit32.rshift(h % 4294967296, 13))
	h = (h * 1274126177) % 4294967296
	return (h % 100000) / 100000
end
PolishPlan.hash = hash

-- The decoy hologram's extra transparency at time t of its dur seconds: a steady faint shimmer, with short
-- drop-outs (about 12 a second are tested) that come more often after `from` of its life, so it reads as
-- breaking up before it pops. 0..0.9.
function PolishPlan.flicker(t: number, dur: number, from: number): number
	if t <= 0 or dur <= 0 then
		return 0.15
	end
	local life = math.clamp(t / dur, 0, 1)
	local slot = math.floor(t * 12)
	local chance = if life < from then 0.08 else 0.08 + 0.5 * (life - from) / math.max(1e-3, 1 - from)
	if hash(slot, 7) < chance then
		return 0.75 + 0.15 * hash(slot, 11)
	end
	return 0.15 + 0.1 * math.sin(t * 9)
end

-- Where the shield drone is at time t: an offset from the hero's root (x, y, z) on a bobbing circle
function PolishPlan.droneAt(t: number, radius: number, height: number, spin: number): (number, number, number)
	local a = t * spin * math.pi * 2
	return math.cos(a) * radius, height + math.sin(t * 3.1) * 0.35, math.sin(a) * radius
end

-- The smoke cloud's puff times (seconds after the throw) while it lasts
function PolishPlan.smokePuffs(dur: number, every: number): { number }
	local out = {}
	local t = 0
	while t < dur - 0.2 and #out < 32 do
		table.insert(out, t)
		t += math.max(0.1, every)
	end
	return out
end

-- Where n puffs of one smoke top-up go: inside radius around the centre (x, z offsets, then a size share),
-- spread over the disc so the cloud fills the area the robots are blinded in
function PolishPlan.smokeSpots(n: number, radius: number, seed: number): { { number } }
	local out = {}
	for i = 1, n do
		local a = (i / n + hash(seed, i) * 0.3) * math.pi * 2
		local r = radius * (0.25 + 0.65 * math.sqrt(hash(seed + 17, i)))
		table.insert(out, { math.cos(a) * r, math.sin(a) * r, 0.7 + 0.6 * hash(seed + 31, i) })
	end
	return out
end

-- Which of n crack decals a landing at (x, z) shows, and its turn in degrees (the same spot, the same crack)
function PolishPlan.crackPick(n: number, x: number, z: number): (number, number)
	if n <= 0 then
		return 0, 0
	end
	local h = hash(math.floor(x * 3), math.floor(z * 3))
	return 1 + math.floor(h * n) % n, math.floor(hash(math.floor(z * 5), math.floor(x * 7)) * 360)
end

-- A crack's transparency at an age: `base` until the last `fade` seconds of life, then out to 1
function PolishPlan.crackAlpha(age: number, life: number, fade: number, base: number): number
	local start = life - fade
	if age <= start then
		return base
	end
	return math.clamp(base + (1 - base) * (age - start) / math.max(1e-3, fade), base, 1)
end

export type Box = { x: number, y: number, z: number, w: number, h: number, d: number, rz: number }

-- The Snow Wall slab's ice shards on its top edge, in the slab's own space (centre at 0): n jagged spikes
-- that never stick out past the slab's ends. sx, sy, sz: the slab's size. Looks only (no collision).
function PolishPlan.wallShards(sx: number, sy: number, sz: number, n: number, seed: number): { Box }
	local out = {}
	for i = 1, n do
		local w = sx / (n + 1) * (0.7 + 0.3 * hash(seed, i))
		local h = sy * (0.22 + 0.2 * hash(seed + 3, i))
		local x = -sx / 2 + sx * (i / (n + 1))
		x = math.clamp(x, -sx / 2 + w / 2, sx / 2 - w / 2)
		table.insert(out, {
			x = x,
			y = sy / 2 + h * 0.35,
			z = 0,
			w = w,
			h = h,
			d = sz * 0.8,
			rz = (hash(seed + 5, i) - 0.5) * 24,
		})
	end
	return out
end

-- The thrown crate's planks in its own space: the 12 edge beams and a cross plank on each side face, all
-- inside the crate's box (sx, sy, sz), so the crate keeps its size. kind: "edge" or "plank".
function PolishPlan.crateBoxes(sx: number, sy: number, sz: number): { { any } }
	local t = math.min(sx, sy, sz) * 0.11
	local out = {}
	local hx, hy, hz = sx / 2 - t / 2, sy / 2 - t / 2, sz / 2 - t / 2
	-- the edges along x, y and z
	for _, a in { -1, 1 } do
		for _, b in { -1, 1 } do
			table.insert(out, { "edge", 0, a * hy, b * hz, sx, t, t })
			table.insert(out, { "edge", a * hx, 0, b * hz, t, sy, t })
			table.insert(out, { "edge", a * hx, b * hy, 0, t, t, sz })
		end
	end
	-- a middle plank across each side face, just proud of the body but inside the box
	local p = t * 0.5
	for _, a in { -1, 1 } do
		table.insert(out, { "plank", 0, 0, a * (sz / 2 - p / 2), sx - 2 * t, t * 1.2, p })
		table.insert(out, { "plank", a * (sx / 2 - p / 2), 0, 0, p, t * 1.2, sz - 2 * t })
	end
	return out
end

-- The fast-travel flight's ease on this device (the server's arc is Travel.flightPath): it starts from still
-- and ends at full speed, so the hero dives into the landing instead of floating down
function PolishPlan.travelEase(f: number): number
	f = math.clamp(f, 0, 1)
	return f * f * (2 - f)
end

return PolishPlan
