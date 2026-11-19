-- art/carry/frames.luau: the carry preview's cells (fix-carry, 2026-11-19). Poses the game's body (Config.HeroRig,
-- the joints HeroBody builds) in the game's hold clips and puts each carried thing where Shared.CarryPose puts it
-- (the same sums ThrowService welds with and ThrowClient draws robots with), and writes art/carry/frames.json
-- for art/blender/carry.py. Each part's move is from its rest place, in the root's frame (Roblox axes).
-- Run: lune run art/carry/frames.luau && $HOME/tools/bpyenv/bin/python art/blender/carry.py
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Config = require("../../src/config")
local HeroAnim = require("../../src/shared/HeroAnim")
local CP = require("../../src/shared/CarryPose")

local T = Config.Throw
local body = CP.bodyFromRig(Config.HeroRig)
local rest = CP.parts(body, {})

-- the pose: a mode clip (or none), the state pose over it, an action at full weight over that
local function pose(mode: string?, state: string, action: string?, at: number?): { [string]: { number } }
	local out: { [string]: { number } } = if mode then HeroAnim.sample(mode, 0.3) else {}
	for j, a in HeroAnim.sample(state, 0) do
		out[j] = a
	end
	if action then
		for j, a in HeroAnim.sample(action, at or 0) do
			if not (mode and HeroAnim.LEGS[j]) then
				out[j] = if mode and j == "Root" then HeroAnim.upperRoot(a) else a
			end
		end
	end
	return out
end

local function flat(c: CP.CF): { number }
	return CP.components(c)
end

local cells = {}
local function cell(label: string, kind: string, size: { number }, grip: string, opts: any?)
	local o = opts or {}
	local clip = CP.CLIP[grip]
	local h = CP.hold(T, body, grip, HeroAnim.sample(clip, 0), size, o.robot, o.upright)
	local P = CP.parts(body, pose(o.mode, clip, o.action, o.at))
	local deltas = {}
	for name, cf in P do
		if rest[name] then
			deltas[name] = flat(CP.mul(cf, CP.inv(rest[name])))
		end
	end
	local part = P[h.part]
	local inPart = h.c0
	if o.action and CP.FOLLOW[o.action] then
		inPart = CP.mul(CP.mul(CP.inv(part), P.RightHand), h.hand) -- full weight: in the right hand
	end
	local box = CP.mul(part, inPart)
	table.insert(cells, {
		label = label,
		kind = kind,
		size = size,
		box = flat(box),
		deltas = deltas,
		glow = grip == "mind",
		air = o.mode ~= nil,
	})
end

cell("Car overhead (Powerhouse)", "car", { 6.3, 4.8, 11.5 }, "overhead", { upright = true })
cell("Crate (dumpster) overhead", "crate", { 6, 4, 3.5 }, "overhead")
cell("Robot overhead", "robot", CP.robotSize(5.25), "overhead", { robot = true })
cell("Robot swing (follows the hands)", "robot", CP.robotSize(5.25), "overhead", {
	robot = true,
	action = "robotSwing",
	at = HeroAnim.CLIPS.robotSwing.dur * 0.5,
})
cell("Car overhead in flight", "car", { 6.3, 4.8, 11.5 }, "overhead", { upright = true, mode = "fly" })
cell("Bench on one fist", "bench", { 5, 2.6, 1.8 }, "hand")
cell("Lamp post gripped", "pole", { 0.8, 10, 0.8 }, "pole")
cell("Telekinesis: car (Mind)", "car", { 6.3, 4.8, 11.5 }, "mind", { upright = true })
cell("Telekinesis: robot (Gravity)", "robot", CP.robotSize(5.25), "mind", { robot = true })

-- the car's meshes round the box's middle (Config.VehicleArt offsets are from its foot; the box is 4.8 tall)
local car = {}
for name, row in Config.VehicleArt.CarSedan do
	car[name] = { row.offset[1], row.offset[2] - 2.4, row.offset[3] }
end
fs.writeFile("art/carry/frames.json", serde.encode("json", { cells = cells, ground = 3, car = car }, true))
print("wrote art/carry/frames.json", #cells)
