-- poses.luau: writes the weapons and the hero poses they are held in as JSON for art/blender/weapons.py, straight
-- from the game's own data (Config.Weapons, Shared.HeroAnim), so the previews pose the blocky body exactly as
-- HeroAnimator does: each weapon's ready stance (HeroAnim.holdClip) and the swing, shot or guard its moves play.
-- Run: lune run art/weapons/poses.luau   (writes art/export/weapons/poses.json; tiny, but share the Lune lock:
-- flock /tmp/capeline-lune.lock lune run art/weapons/poses.luau)
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Config = require("../../src/config")
local HeroAnim = require("../../src/shared/HeroAnim")

-- the moment of each action clip the preview shows (seconds into the clip): the hit, the aim, the guard
local MOMENT = {
	punch = 0.1,
	slash = 0.06,
	heavy = 0.3,
	heavyOver = 0.36,
	thrust = 0.15,
	bash = 0.18,
	block = 0.4,
	shoot = 0.2,
	bow = 0.2,
	throw = 0.08,
	lash = 0.2,
	spin = 0.12,
}

local out = { weapons = {}, poses = {} }
local used: { [string]: number } = {}
for _, w in Config.Weapons.list do
	local id, family = w[1], w[2]
	local hold = HeroAnim.holdClip(id, family)
	local per = HeroAnim.WEAPON_CLIPS[id] or HeroAnim.HOLD_CLIPS[family].combo
	local action = per[1]
	if family == "shield" then
		action = "block"
	end
	table.insert(out.weapons, { id = id, family = family, name = w[3], hold = hold, action = action })
	if hold then
		used[hold] = 0
	end
	used[action] = MOMENT[action] or 0.1
end
for clip, t in used do
	local angles = {}
	for joint, a in HeroAnim.sample(clip, t) do
		angles[joint] = { a[1], a[2], a[3] }
	end
	out.poses[clip] = angles
end
fs.writeDir("art/export/weapons")
fs.writeFile("art/export/weapons/poses.json", serde.encode("json", out, true))
print("wrote art/export/weapons/poses.json: " .. #out.weapons .. " weapons")
