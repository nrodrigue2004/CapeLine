-- swing_sim: a bot that swings down a street over the game's own buildings with Shared.SwingMath, the way
-- MoveController does (hold Fly, let go on the rising half, hold Fly again to catch the next line, the leap's
-- airGravity and the Swing's air steer in between, bumping off walls). Used by tests/swing_test.luau (the
-- speed budget and the feel numbers) and art/swing/path.luau (the preview). Pure: no Roblox.
local SwingMath = require("../src/shared/SwingMath")
local MoveMath = require("../src/shared/MoveMath")

export type Sample = { t: number, x: number, y: number, z: number, mode: string, speed: number, phase: number }
export type Result = {
	path: { Sample },
	lines: {
		{
			t0: number,
			t1: number,
			ax: number,
			ay: number,
			az: number,
			edge: boolean,
			speedIn: number,
			speedOut: number,
		}
	},
	releases: { { t: number, x: number, y: number, z: number, speed: number, sweet: boolean } },
	bumps: number,
	misses: number,
	lowest: number,
}

-- boxes: { x, z, sx, sz, base, top }; start (x, y, z); dir: the street's flat direction (unit); seconds
return function(
	Config: any,
	boxes: { any },
	groundY: number,
	start: { number },
	dir: { number },
	seconds: number,
	releaseAt: number?
): Result
	local M = Config.Move
	local sw = M.mobility.swing
	local cast = SwingMath.boxCast(boxes, groundY)
	local range = SwingMath.range(Config.Move, 1)
	local dt = 1 / 60
	local px, py, pz = start[1], start[2], start[3]
	local vx, vy, vz = dir[1] * M.run.speed, 0, dir[2] * M.run.speed
	local mode = "ground"
	local ax, ay, az, len, target = 0, 0, 0, 0, 0
	local edge = false
	local releasedAt, missedAt = -math.huge, -math.huge
	local out: Result = { path = {}, lines = {}, releases = {}, bumps = 0, misses = 0, lowest = math.huge }
	local cur: any = nil
	local let = releaseAt or 0.55

	-- the bot's camera looks along the street, a little up
	local lx, ly, lz = dir[1], 0.3, dir[2]

	local function inside(x: number, y: number, z: number): any
		for _, b in boxes do
			if
				y > b.base
				and y < b.top
				and math.abs(x - b.x) < b.sx / 2 + 1
				and math.abs(z - b.z) < b.sz / 2 + 1
			then
				return b
			end
		end
		return nil
	end

	local function attach(t: number): boolean
		local a = SwingMath.findAnchor(Config.Move, px, py, pz, lx, ly, lz, vx, vz, range, cast)
		if not a then
			missedAt = t
			out.misses += 1
			return false
		end
		edge = a.edge
		local fl = math.sqrt(vx * vx + vz * vz)
		local tx, tz = if fl > 10 then vx else lx, if fl > 10 then vz else lz
		ax, ay, az = SwingMath.pivot(Config.Move, px, pz, a.x, a.y, a.z, tx, tz)
		len = SwingMath.rope(Config.Move, px, py, pz, ax, ay, az, nil)
		target = SwingMath.rope(Config.Move, px, py, pz, ax, ay, az, groundY)
		if mode == "ground" then
			vy = sw.groundPop
		end
		mode = "swing"
		cur = {
			t0 = t,
			t1 = t,
			ax = a.x,
			ay = a.y,
			az = a.z,
			qx = ax,
			qz = az,
			edge = edge,
			speedIn = SwingMath.len3(vx, vy, vz),
			speedOut = 0,
		}
		table.insert(out.lines, cur)
		return true
	end

	local function release(t: number)
		local phase = SwingMath.phase(px, py, pz, ax, ay, az, vy)
		local sweet
		vx, vy, vz, sweet = SwingMath.release(Config.Move, vx, vy, vz, phase)
		mode = "air"
		releasedAt = t
		cur.t1 = t
		cur.speedOut = SwingMath.len3(vx, vy, vz)
		table.insert(
			out.releases,
			{ t = t, x = px, y = py, z = pz, speed = SwingMath.len3(vx, vy, vz), sweet = sweet }
		)
	end

	-- the bot's stick: along the street, steering back toward its middle line
	local sx0, sz0 = start[1], start[3]
	local function stick(): (number, number)
		local ox, oz = px - sx0, pz - sz0
		local along = ox * dir[1] + oz * dir[2]
		local offX, offZ = ox - dir[1] * along, oz - dir[2] * along
		local cx, cz = dir[1] - offX / 12, dir[2] - offZ / 12
		local l = math.sqrt(cx * cx + cz * cz)
		return cx / l, cz / l
	end

	local t = 0
	while t < seconds do
		local wx, wz = stick()
		local phase = 0
		if mode == "ground" then
			-- run, then swing off the street or the roof (Fly on the ground with nothing to zip to: a line)
			px += vx * dt
			pz += vz * dt
			if py > groundY + 3.5 and not inside(px, py - 1.5, pz) then
				mode = "air" -- ran off the roof
			end
			if t - missedAt > 0.3 then
				attach(t)
			end
		elseif mode == "swing" then
			local nx, ny, nz
			nx, ny, nz, vx, vy, vz, len =
				SwingMath.step(Config.Move, px, py, pz, vx, vy, vz, ax, ay, az, len, target, wx, wz, dt)
			-- the controller drives the body onto the rope's point
			px, py, pz = nx, ny, nz
			phase = SwingMath.phase(px, py, pz, ax, ay, az, vy)
			if SwingMath.atTop(Config.Move, py, ay, vy) or phase >= let then
				release(t)
			end
		else
			vx, vy, vz = MoveMath.airStep(M, vx, vy, vz, dt)
			vx, vz = MoveMath.airSteer(vx, vz, wx, wz, sw.steer, M.caps.glide * 0.5, dt)
			px, py, pz = px + vx * dt, py + vy * dt, pz + vz * dt
			if vy < 0 and t - releasedAt >= sw.rearm and t - missedAt >= 0.3 then
				attach(t)
			end
		end
		-- walls: bounce off (the controller lets go and pushes off, keeping the speed along the wall)
		local b = inside(px, py, pz)
		if b then
			out.bumps += 1
			local ox = b.sx / 2 + 1 - math.abs(px - b.x)
			local oz = b.sz / 2 + 1 - math.abs(pz - b.z)
			local oy = b.top - py
			if oy < math.min(ox, oz) and vy <= 0 then
				py = b.top -- landed on a roof: run on
				vy = 0
				mode = "ground"
			elseif ox < oz then
				px = b.x + (b.sx / 2 + 1.01) * (if px > b.x then 1 else -1)
				vx = (if px > b.x then 1 else -1) * 15
				vz *= 0.8
				vy = sw.release.up
				mode = "air"
				releasedAt = t
			else
				pz = b.z + (b.sz / 2 + 1.01) * (if pz > b.z then 1 else -1)
				vz = (if pz > b.z then 1 else -1) * 15
				vx *= 0.8
				vy = sw.release.up
				mode = "air"
				releasedAt = t
			end
			if cur and cur.speedOut == 0 then
				cur.t1 = t
				cur.speedOut = SwingMath.len3(vx, vy, vz)
			end
		end
		if py < groundY + 3 then
			py = groundY + 3
			vy = 0
			if mode ~= "ground" then
				mode = "ground"
				local fl = math.sqrt(vx * vx + vz * vz)
				local k = if fl > M.run.speed then M.run.speed / fl else 1
				vx, vz = vx * k, vz * k
				missedAt = t
			end
		end
		out.lowest = math.min(out.lowest, py)
		table.insert(
			out.path,
			{ t = t, x = px, y = py, z = pz, mode = mode, speed = SwingMath.len3(vx, vy, vz), phase = phase }
		)
		t += dt
	end
	return out
end
