-- storyboard.luau: the directed prologue's camera shots as data for art/blender/storyboard.py (prologue-cine,
-- 2026-11-20). Straight from the game's own rules: the world for a weekly seed (WorldMap), the prologue's route
-- (OpeningPlan.route), the authored segments (Shared.PrologueCine.beat) and each shot's camera
-- (PrologueCine.camera, the place the device's camera eases to; a cut snaps there). One frame per segment (at the
-- prompt for a prompt segment, mid-move for the rest), with the hero's feet, Skylance, the kid and the moment's prop.
-- Run: lune run art/prologue/storyboard.luau   (writes art/export/prologue/storyboard.json)
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Config = require("../../src/config")
local WorldMap = require("../../src/shared/WorldMap")
local OpeningPlan = require("../../src/shared/OpeningPlan")
local PrologueCine = require("../../src/shared/PrologueCine")
local Rng = require("../../src/shared/Rng")

local SEED = 202647
local world = WorldMap.build(Config, SEED)
local route = OpeningPlan.route(Config, world, Rng.new(SEED * 7 + 1)) :: any
local lane = OpeningPlan.lane(Config, 1)
local O = Config.Story.opening

local function o(side: string): any
	return {
		start = route.start,
		spark = route.spark,
		kid = route.kid,
		roofs = route.roofs,
		roofHalf = route.roofHalf,
		runPath = route.runPath,
		entrance = route.entrance,
		lane = lane,
		side = side,
	}
end

-- the buildings round the route (boxes: centre x, z, sizes, top)
local near = {}
local cx, cz = route.hall[1], route.hall[3]
for _, b in world.buildings do
	local d = math.sqrt((b.x - cx) ^ 2 + (b.z - cz) ^ 2)
	if d < 420 then
		table.insert(near, { b.x, b.z, b.sx, b.sz, b.top })
	end
end

-- the device's camera pull (Fx.PrologueQte): a building between the look point and the shot brings the camera in
-- front of it (a ray against the buildings' boxes)
local gy = Config.City.ground.y
local function occlude(look: { number }, cam: { number }): { number }
	local d = { cam[1] - look[1], cam[2] - look[2], cam[3] - look[3] }
	local best = 1
	for _, b in near do
		local lo = { b[1] - b[3] / 2, gy, b[2] - b[4] / 2 }
		local hi = { b[1] + b[3] / 2, b[5], b[2] + b[4] / 2 }
		local t0, t1 = 0, 1
		local ok = true
		for k = 1, 3 do
			if math.abs(d[k]) < 1e-6 then
				if look[k] < lo[k] or look[k] > hi[k] then
					ok = false
				end
			else
				local a = (lo[k] - look[k]) / d[k]
				local c = (hi[k] - look[k]) / d[k]
				t0 = math.max(t0, math.min(a, c))
				t1 = math.min(t1, math.max(a, c))
			end
		end
		if ok and t0 <= t1 and t0 > 0.02 and t0 < best then
			best = t0
		end
	end
	if best >= 1 then
		return cam
	end
	local l = math.sqrt(d[1] ^ 2 + d[2] ^ 2 + d[3] ^ 2)
	local t = math.max(0, best - 1.5 / l)
	return { look[1] + d[1] * t, look[2] + d[2] * t, look[3] + d[3] * t }
end

local frames = {}
local function add(beat: string, seg: any, u: number, note: string, extra: any?)
	local p = PrologueCine.at(seg, u)
	local cam, look = PrologueCine.camera(Config, seg.shot, p, seg, u)
	if beat == "tunnel" then
		local half = O.subway.width / 2 - 2
		cam[1] = math.clamp(cam[1], lane.x - half, lane.x + half)
		cam[2] = math.min(cam[2], lane.floorY + O.subway.height - 2)
	end
	if beat ~= "tunnel" then
		cam = occlude(look, cam)
	end
	local dx, dz = seg.to[1] - seg.from[1], seg.to[3] - seg.from[3]
	if seg.move == "stand" and seg.at then
		dx, dz = seg.at[1] - p[1], seg.at[3] - p[3]
	end
	table.insert(frames, {
		beat = beat,
		id = seg.id,
		shot = seg.shot,
		cut = seg.cut == true,
		slow = seg.slow == true,
		prompt = seg.prompt and seg.prompt.word or nil,
		kind = seg.prompt and seg.prompt.kind or nil,
		clip = if u == 0 and seg.prompt then seg.wait else seg.clip or seg.start,
		note = note,
		hero = p,
		yaw = math.atan2(dx, dz),
		cam = cam,
		look = look,
		fx = seg.fx,
		at = seg.at,
		extra = extra or {},
	})
end

local function beat(step: string, side: string, extra: (any) -> any)
	for _, seg in PrologueCine.beat(Config, o(side), step) do
		if seg.prompt then
			add(step, seg, 0, "prompt", extra(seg))
		end
		if seg.move ~= "stand" or not seg.prompt then
			add(step, seg, 0.5, "move", extra(seg))
		end
	end
end

local function none(_: any): any
	return {}
end

beat("run", "hero", none)
beat("spark", "hero", function()
	return { kid = route.kid }
end)
beat("leap", "hero", none)
for hop = 3, #route.roofs do
	for _, seg in PrologueCine.beat(Config, o("hero"), "chase", hop) do
		local back = route.roofs[math.max(1, hop - 2)]
		local ex = { skylance = { back[1], back[2] - 1.5, back[3] } }
		if seg.prompt then
			add("chase", seg, 0, "prompt", ex)
		end
		add("chase", seg, 0.5, "move", ex)
	end
end
beat("suit", "hero", none)
beat("descend", "hero", none)
beat("tunnel", "hero", none)

fs.writeDir("art/export/prologue")
fs.writeFile(
	"art/export/prologue/storyboard.json",
	serde.encode("json", {
		seed = SEED,
		ground = Config.City.ground.y,
		buildings = near,
		roofs = route.roofs,
		runPath = route.runPath,
		entrance = route.entrance,
		stage = route.stage,
		lane = {
			x = lane.x,
			z0 = lane.z0,
			z1 = lane.z1,
			floorY = lane.floorY,
			width = O.subway.width,
			height = O.subway.height,
			chamber = O.subway.chamber,
		},
		frames = frames,
	})
)
print("storyboard: " .. #frames .. " frames")
