--!strict
-- TetherMath: swing physics for the weapons on a line (the weapons polish pass, 2026-11-19; the follow-up "whip,
-- nunchucks, yo-yo and rope dart have no swing physics"). A small verlet rope from the hand: gravity hangs it,
-- the hand's own motion drags it (so a swing makes it lag and then crack), and during an attack the line pays
-- out to the move's reach along the arm and reels back in. The nunchucks are a one-link pendulum: the whole
-- weapon swings round the grip. TetherFx (client) draws it with the weapon's own meshes on every device.
-- Vectors are plain { x, y, z } arrays. Pure: no Roblox types, so Lune tests it.

local TetherMath = {}

export type Vec = { number }
export type Spec = {
	mode: string, -- "rope" (a line and a tip) or "pendulum" (the whole weapon swings round the grip)
	segs: number, -- links in the line
	reach: number, -- how far the line pays out on an attack (studs)
	line: { string }, -- the meshes that are the line (hidden: the rope is drawn instead)
	tip: { string }, -- the meshes that ride the end of the line
	width: number, -- the drawn line's thickness
	stiff: number, -- how hard an attack drives the tip out along the arm (per second squared, per stud)
	link: string?, -- the segment's mesh in Art.Tether (art/blender/tether.py; list-combat 2026-11-20): a rope or chain
}
export type State = { p: { Vec }, q: { Vec } }

-- by weapon id (Config.Weapons.list); the mesh names are Config.WeaponArt's (a style's _B or _J mesh counts too)
TetherMath.SPECS = {
	[21] = { -- Nunchucks
		mode = "pendulum",
		segs = 1,
		reach = 1.2,
		line = {},
		tip = { "W21_Sticks", "W21_Rings", "W21_Chain", "W21_Caps" },
		width = 0,
		stiff = 260,
	},
	[32] = { -- Chain Whip
		mode = "rope",
		segs = 8,
		reach = 11,
		line = { "W32_Chain" },
		tip = { "W32_Barb" },
		link = "TetherChain",
		width = 0.16,
		stiff = 420,
	},
	[34] = { -- Yo-yo
		mode = "rope",
		segs = 6,
		reach = 9,
		line = { "W34_String" },
		link = "TetherRope",
		tip = { "W34_Halves", "W34_Caps", "W34_Glow" },
		width = 0.05,
		stiff = 520,
	},
	[35] = { -- Rope Dart
		mode = "rope",
		segs = 8,
		reach = 12,
		line = { "W35_Rope" },
		link = "TetherRope",
		tip = { "W35_Dart", "W35_Ring", "W35_Ribbon" },
		width = 0.1,
		stiff = 460,
	},
} :: { [number]: Spec }

TetherMath.gravity = 120 -- studs a second squared (a little heavier than the world's, so lines hang snappy)
TetherMath.damp = 0.9 -- velocity kept each step
TetherMath.iterations = 4 -- length passes a step
TetherMath.maxStep = 1 / 30 -- longer frames are split

-- the base mesh name (a style's Broad or Jagged version is the same piece)
function TetherMath.baseName(mesh: string): string
	local tail = string.sub(mesh, -2)
	if tail == "_B" or tail == "_J" then
		return string.sub(mesh, 1, -3)
	end
	return mesh
end

-- what a weapon piece is to its tether: "line", "tip" or nil (it stays welded)
function TetherMath.role(spec: Spec, mesh: string): string?
	local base = TetherMath.baseName(mesh)
	for _, n in spec.line do
		if n == base then
			return "line"
		end
	end
	for _, n in spec.tip do
		if n == base then
			return "tip"
		end
	end
	return nil
end

-- the line's length at a moment of an attack (u: 0 to 1 through the clip): it pays out from `rest` to the
-- spec's reach by the contact, holds a beat, and reels back in by the end (rest outside an attack)
function TetherMath.lengthAt(spec: Spec, rest: number, u: number?): number
	if not u or u <= 0 or u >= 1 then
		return rest
	end
	local reach = math.max(rest, spec.reach)
	local out
	if u < 0.4 then
		local f = u / 0.4
		out = f * f * (3 - 2 * f)
	elseif u < 0.6 then
		out = 1
	else
		local f = (u - 0.6) / 0.4
		out = 1 - f * f * (3 - 2 * f)
	end
	return rest + (reach - rest) * out
end

local function v(x: number, y: number, z: number): Vec
	return { x, y, z }
end

-- a line hanging straight down from the anchor
function TetherMath.new(spec: Spec, anchor: Vec, rest: number): State
	local p, q = {}, {}
	for i = 0, spec.segs do
		local y = anchor[2] - rest * i / spec.segs
		p[i + 1] = v(anchor[1], y, anchor[3])
		q[i + 1] = v(anchor[1], y, anchor[3])
	end
	return { p = p, q = q }
end

-- One step. anchor: the grip in the world; aim: the unit direction the arm points (the attack drives the tip
-- out along it, nil at rest); length: the line's length now (lengthAt); dt: seconds.
function TetherMath.step(state: State, spec: Spec, anchor: Vec, aim: Vec?, length: number, dt: number)
	local left = math.min(dt, 0.25)
	while left > 1e-5 do
		local h = math.min(left, TetherMath.maxStep)
		left -= h
		local p, q = state.p, state.q
		local n = #p
		p[1][1], p[1][2], p[1][3] = anchor[1], anchor[2], anchor[3]
		q[1][1], q[1][2], q[1][3] = anchor[1], anchor[2], anchor[3]
		for i = 2, n do
			local a, b = p[i], q[i]
			local ax, ay, az = 0, -TetherMath.gravity, 0
			if aim then
				-- the attack: each link is pulled toward its place on a straight line along the arm (the tip most)
				local share = (i - 1) / (n - 1)
				local k = spec.stiff * share
				local tx = anchor[1] + aim[1] * length * share
				local ty = anchor[2] + aim[2] * length * share
				local tz = anchor[3] + aim[3] * length * share
				ax += (tx - a[1]) * k
				ay += (ty - a[2]) * k + TetherMath.gravity * share
				az += (tz - a[3]) * k
			end
			local d = TetherMath.damp
			local nx = a[1] + (a[1] - b[1]) * d + ax * h * h
			local ny = a[2] + (a[2] - b[2]) * d + ay * h * h
			local nz = a[3] + (a[3] - b[3]) * d + az * h * h
			b[1], b[2], b[3] = a[1], a[2], a[3]
			a[1], a[2], a[3] = nx, ny, nz
		end
		-- keep every link its length (the anchor never moves)
		local seg = length / (n - 1)
		for _ = 1, TetherMath.iterations do
			for i = 1, n - 1 do
				local a, b = p[i], p[i + 1]
				local dx, dy, dz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
				local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
				if dist > 1e-6 then
					local diff = (dist - seg) / dist
					if i == 1 then
						b[1] -= dx * diff
						b[2] -= dy * diff
						b[3] -= dz * diff
					else
						local half = diff * 0.5
						a[1] += dx * half
						a[2] += dy * half
						a[3] += dz * half
						b[1] -= dx * half
						b[2] -= dy * half
						b[3] -= dz * half
					end
				end
			end
		end
	end
end

-- the tip and the direction of the last link (for placing the tip's meshes)
function TetherMath.tip(state: State): (Vec, Vec)
	local p = state.p
	local n = #p
	local a, b = p[n - 1], p[n]
	local dx, dy, dz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
	local len = math.sqrt(dx * dx + dy * dy + dz * dz)
	if len < 1e-6 then
		return b, v(0, -1, 0)
	end
	return b, v(dx / len, dy / len, dz / len)
end

return TetherMath
