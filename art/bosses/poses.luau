-- poses.luau: the boss pass's render check (2026-11-19). Samples Shared.BossPose's key poses for every boss (the idle,
-- each attack's anticipation peak and strike, flinch, weak, stagger, enrage, defeat, land) with the same segment maths
-- as Fx.BossAnim, and writes each segment's frame from the boss's feet as JSON for art/blender/boss_poses.py, which
-- renders the game's own meshes (art/export/Bosses.fbx) posed: art/preview/boss_poses_<Boss>.png.
-- Run from the repo root: lune run art/bosses/poses.luau   (writes build/boss_poses.json)
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3

local Config = require("../../src/config")
local BossPose = require("../../src/shared/BossPose")

local function angles(v: { number }): any
	return CFrame.Angles(math.rad(v[1]), math.rad(v[2]), math.rad(v[3]))
end

local function frames(id: string, pose: any): any
	local xf = {}
	local r = pose.Root
	xf.Root = if r then CFrame.new(r[4], r[5], r[6]) * angles(r) else CFrame.new()
	for _, seg in Config.BossArt[id].rig do
		local v = pose[seg.name] or { 0, 0, 0, 0, 0, 0 }
		local p = Vector3.new(seg.pivot[1], seg.pivot[2], seg.pivot[3])
		local l = CFrame.new(p.X + v[4], p.Y + v[5], p.Z + v[6]) * angles(v) * CFrame.new(-p.X, -p.Y, -p.Z)
		xf[seg.name] = xf[seg.parent] * l
	end
	local out = {}
	for name, cf in xf do
		out[name] = { cf:GetComponents() }
	end
	return out
end

local out = {}
for id, set in BossPose.SETS do
	local list = {}
	local function add(name: string, pose: any)
		table.insert(list, { name = name, segs = frames(id, pose) })
	end
	add("idle", BossPose.sample(set.clips.idle, set.clips.idle.dur * 0.25))
	local def = Config.Boss.bosses[id]
	for _, atk in def.attacks do
		local tm = BossPose.timing(id, atk.id, atk.warn) :: any
		add(atk.id .. " wind-up", (BossPose.attack(id, atk.id, tm.peak, atk.warn)))
		add(atk.id .. " strike", (BossPose.attack(id, atk.id, atk.warn, atk.warn)))
	end
	if set.clips.walk then
		add("walk", BossPose.sample(set.clips.walk, 0))
	end
	add("flinch", BossPose.sample(set.clips.flinch, set.clips.flinch.keys[2].t))
	add("weak exposed", BossPose.sample(set.clips.weak, 1))
	add("plate stagger", BossPose.sample(set.clips.stagger, set.clips.stagger.keys[2].t))
	add("enrage", BossPose.sample(set.clips.enrage, 1))
	add("defeat", BossPose.sample(set.clips.defeat, set.clips.defeat.dur))
	add("land", BossPose.sample(set.clips.land, 0))
	local art = Config.BossArt[id]
	local anchors = {}
	for _, row in def.objectives.list do
		if row.at then
			table.insert(anchors, row.at)
		end
	end
	out[id] = {
		frames = list,
		pieces = art.pieces,
		objective = art.objective,
		anchors = anchors,
		glow = art.glow,
		height = def.height,
	}
end
fs.writeDir("build")
fs.writeFile("build/boss_poses.json", serde.encode("json", out, true))
print("wrote build/boss_poses.json")
