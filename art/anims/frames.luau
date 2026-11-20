-- art/anims/frames.luau: the contact sheet's poses (pt-anims, 2026-11-19). Samples the game's own clips
-- (Shared.HeroAnim, Shared.NpcAnim) at their key beats and writes art/anims/frames.json for
-- art/blender/clips.py, which poses the blocky body from it. Mid-air cells compose a clip over a travel pose
-- the way HeroAnimator does (the upper-body layer: the travel pose keeps its legs and the Root its pitch).
-- Run: lune run art/anims/frames.luau && $HOME/tools/bpyenv/bin/python art/blender/clips.py
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local HeroAnim = require("../../src/shared/HeroAnim")
local NpcAnim = require("../../src/shared/NpcAnim")

type Cell = { label: string, joints: { [string]: { number } }, air: boolean?, weapon: string?, robot: boolean? }

local function hero(name: string, f: number, mode: string?): { [string]: { number } }
	local clip = HeroAnim.CLIPS[name]
	assert(clip, name)
	local act = HeroAnim.sample(name, clip.dur * f)
	if not mode then
		return act
	end
	local base = HeroAnim.sample(mode, 0.4)
	local lw, upper = HeroAnim.layer(mode, 30)
	local out = table.clone(base)
	for joint, a in act do
		if HeroAnim.LEGS[joint] then
			if lw > 0 then
				out[joint] = a
			end
		elseif joint == "Root" and upper then
			out[joint] = HeroAnim.upperRoot(a)
		else
			out[joint] = a
		end
	end
	return out
end

local function cellsOf(list: { any }, page: { Cell })
	for _, e in list do
		local name, beats, class, mode = e[1], e[2], e[3], e[4]
		for _, f in beats do
			table.insert(page, {
				label = string.format("%s %d%%%s", name, math.floor(f * 100), if mode then " / " .. mode else ""),
				joints = hero(name, f, mode),
				air = mode ~= nil,
				weapon = class,
			})
		end
	end
end

local pages: { { Cell } } = {}

-- 1: two-handed weapons and the grabbed robot (ground)
local p1 = {}
cellsOf({
	{ "holdTwo@hilt", { 0 }, "hilt" },
	{ "heavy@hilt", { 0.3, 0.45, 0.7 }, "hilt" },
	{ "chargedOver@hilt", { 0.55, 0.7 }, "hilt" },
	{ "heavyOver@hilt", { 0.3, 0.5 }, "hilt" },
	{ "holdPole@pole", { 0 }, "pole" },
	{ "thrust@pole", { 0.3, 0.5 }, "pole" },
	{ "staffSpin@pole", { 0.3, 0.6 }, "pole" },
	{ "holdLong", { 0 }, "long" },
	{ "rifleShot@long", { 0.4 }, "long" },
	{ "robotHold", { 0 }, "hilt" },
	{ "robotSwing", { 0.35, 0.55, 0.78 }, "hilt" },
	{ "robotSlam", { 0.45, 0.65 }, "hilt" },
	{ "poundLandHeavy", { 0.16, 0.6 } },
}, p1)
table.insert(pages, p1)

-- 2: casts and swings in the air (each ground cell next to its mid-air one)
local p2 = {}
local castPairs = {
	{ "hurl", 0.45 },
	{ "stomp", 0.5 },
	{ "groundPound", 0.6 },
	{ "heavy@hilt", 0.45 },
	{ "thrust@pole", 0.5 },
	{ "blast", 0.45 },
	{ "landHard", 0.4 },
	{ "rifleShot@long", 0.4 },
	{ "robotSwing", 0.55 },
	{ "spin", 0.5 },
	{ "uppercut", 0.45 },
	{ "slash", 0.45 },
}
local modes = { "hover", "air", "glide", "swim", "hover", "air", "hover", "glide", "air", "hover", "swim", "air" }
for i, e in castPairs do
	local class = if string.find(e[1], "@hilt") or e[1] == "robotSwing" then "hilt"
		elseif string.find(e[1], "@pole") then "pole"
		elseif string.find(e[1], "@long") then "long"
		else nil
	cellsOf({ { e[1], { e[2] }, class } }, p2)
	cellsOf({ { e[1], { e[2] }, class, modes[i] } }, p2)
end
table.insert(pages, p2)

-- 3: robots: wind-ups, strikes at contact, hit reacts, stagger
local p3 = {}
local robo = {
	{ "windupOverhead", 0.1 },
	{ "hammer", 0.5 },
	{ "haymaker", 0.3 },
	{ "haymaker", 0.5 },
	{ "stab", 0.55 },
	{ "sweep", 0.55 },
	{ "windupShield", 0.1 },
	{ "shieldBash", 0.5 },
	{ "snatch", 0.5 },
	{ "windupClaw", 0.1 },
	{ "claw", 0.5 },
	{ "zap", 0.2 },
	{ "rifleKick", 0.2 },
	{ "braceShot", 0.2 },
	{ "windupThrow", 0.1 },
	{ "lobThrow", 0.58 },
	{ "command", 0.4 },
	{ "hookThrow", 0.5 },
	{ "yank", 0.55 },
	{ "mendHand", 0.5 },
	{ "hit", 0.18 },
	{ "hitHeavy", 0.15 },
	{ "stagger", 0.25 },
	{ "windupAim", 0.1 },
}
for _, e in robo do
	local c = NpcAnim.CLIPS[e[1]]
	table.insert(p3, {
		label = string.format("%s %d%%", e[1], math.floor(e[2] * 100)),
		joints = NpcAnim.sample(e[1], c.dur * e[2]),
		robot = true,
	})
end
table.insert(pages, p3)

-- 4: people's gestures and the pound landing and robot backhand
local p4 = {}
local ppl = {
	{ "talk", 0.25 },
	{ "talk", 0.75 },
	{ "wave", 0.33 },
	{ "wave", 0.5 },
	{ "point", 0.5 },
	{ "beckon", 0.33 },
	{ "beckon", 0.5 },
	{ "shrug", 0.5 },
	{ "armsCrossed", 0.3 },
	{ "lookAround", 0.3 },
	{ "lookAround", 0.7 },
	{ "checkTime", 0.5 },
}
for _, e in ppl do
	local c = NpcAnim.CLIPS[e[1]]
	table.insert(p4, { label = string.format("%s %d%%", e[1], math.floor(e[2] * 100)), joints = NpcAnim.sample(e[1], c.dur * e[2]) })
end
cellsOf({
	{ "poundLandHeavy", { 0.04, 0.16, 0.45 } },
	{ "robotSwingBack", { 0.32, 0.52, 0.76 }, "hilt" },
	{ "robotSlam", { 0.62 }, "hilt", "air" },
}, p4)
table.insert(pages, p4)

-- 5 (move-2, 2026-11-19): the Hulk climb, the Acrobat's crawl and flip, everyone's sprint
local p5 = {}
cellsOf({
	{ "leapGrab", { 0.25, 1 } },
	{ "climb", { 0, 0.5 } },
	{ "bound", { 0, 0.5 } },
	{ "leapRegrab", { 0.3 } },
	{ "climbVault", { 0, 0.33, 0.8 } },
	{ "crawlLand", { 0.3 } },
	{ "crawl", { 0, 0.25, 0.5, 0.75 } },
	{ "flip", { 0, 0.25, 0.5, 0.75 } },
	{ "runFast", { 0, 0.25, 0.5, 0.75 } },
}, p5)
for _, c in p5 do
	c.air = true -- every one of these is off the ground (the sprint's ring marks the stride too)
end
table.insert(pages, p5)

fs.writeFile("art/anims/frames.json", serde.encode("json", { pages = pages }, false))
print("pages", #pages, #p1, #p2, #p3, #p4, #p5)
