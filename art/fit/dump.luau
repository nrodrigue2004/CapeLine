-- dump.luau: writes build/fit/fits.json for the fit renders (art/blender/fit.py): every creator piece's and weapon's
-- box on Roblox's own blocky R15 body at rest, worked out by the game's own placement code (Shared.BodyFit, the
-- same call LookKit, WeaponKit and LookService make), plus the old placement ("before": each box scaled by the
-- part's box against Config.HeroRig, as the game did until pt-fit) so the sheets can show both. Also the rig and
-- the weapon poses (HeroAnim's ready stance and one action moment per weapon, as art/weapons/poses.luau).
-- Run from the repo root: flock /tmp/capeline-lune.lock ~/tools/lune run art/fit/dump.luau
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Config = require("../../src/config")
local BodyFit = require("../../src/shared/BodyFit")
local HeroAnim = require("../../src/shared/HeroAnim")

local PART = {
	head = "Head",
	torso = "UpperTorso",
	waist = "LowerTorso",
	luarm = "LeftUpperArm",
	ruarm = "RightUpperArm",
	llarm = "LeftLowerArm",
	rlarm = "RightLowerArm",
	lhand = "LeftHand",
	rhand = "RightHand",
	lthigh = "LeftUpperLeg",
	rthigh = "RightUpperLeg",
	lshin = "LeftLowerLeg",
	rshin = "RightLowerLeg",
	lfoot = "LeftFoot",
	rfoot = "RightFoot",
}

local R = Config.RobloxRig.parts
local H = Config.HeroRig.parts

-- the old way: offset and size times the part's box over HeroRig's
local function before(name: string, offset: { number }, size: { number })
	local r, h = R[name].size, H[name].size
	local f = { r[1] / h[1], r[2] / h[2], r[3] / h[3] }
	return { offset[1] * f[1], offset[2] * f[2], offset[3] * f[3] }, {
		size[1] * f[1],
		size[2] * f[2],
		size[3] * f[3],
	}
end

local function row(at: string, mesh: string, offset: { number }, size: { number }, extra: { [string]: any })
	local name = PART[at]
	assert(name, "no body part for " .. tostring(at))
	local bo, bs = before(name, offset, size)
	local ao, as = BodyFit.place(Config, name, R[name].size, offset, size)
	local out = { mesh = mesh, at = at, part = name, before = { bo, bs }, after = { ao, as } }
	for k, v in extra do
		out[k] = v
	end
	return out
end

local SETS = {
	{ "capes", "CapeArt", "Capes" },
	{ "heads", "HeadArt", "Heads" },
	{ "gloves", "GloveArt", "Gloves" },
	{ "boots", "BootArt", "Boots" },
	{ "coats", "CoatArt", "Coats" },
	{ "belts", "BeltArt", "Belts" },
	{ "shoulders", "ShoulderArt", "Shoulders" },
	{ "backs", "BackArt", "Backs" },
	{ "hats", "HatArt", "Hats" },
	{ "ears", "EarArt", "Ears" },
	{ "necks", "NeckArt", "Necks" },
	{ "wrists", "WristArt", "Wrists" },
	{ "arms", "ArmArt", "Arms" },
}

local out: any =
	{ sets = {}, rig = Config.RobloxRig.parts, hero = Config.HeroRig.parts, weapons = {}, poses = {} }
for _, s in SETS do
	local fits = (Config :: any)[s[2]]
	local kits = {}
	local keys = {}
	for k in fits do
		table.insert(keys, k)
	end
	table.sort(keys)
	for _, k in keys do
		local fit = fits[k]
		local pieces = {}
		for _, p in fit.pieces do
			table.insert(
				pieces,
				row(
					p.at or "torso",
					p.mesh,
					p.offset,
					p.size,
					{ role = p.role, glow = p.glow == true, alpha = p.alpha }
				)
			)
		end
		table.insert(kits, { key = k, hair = fit.hair ~= false, pieces = pieces })
	end
	table.insert(out.sets, { name = s[1], fbx = s[3], kits = kits })
end

-- the gear looks: LookService's own frame (each slot's reference box; a shin between the knee and ankle joints)
do
	local GA = Config.GearArt
	local kits = {}
	local keys = {}
	for k in GA.looks do
		table.insert(keys, k)
	end
	table.sort(keys)
	for _, k in keys do
		local fit = GA.looks[k]
		local pieces = {}
		for _, p in fit.pieces do
			local name = PART[p.at]
			local ref = GA.ref[p.at]
			local r = R[name]
			local f = { r.size[1] / ref[1], r.size[2] / ref[2], r.size[3] / ref[3] }
			local mid = 0
			if p.at == "lshin" or p.at == "rshin" then
				local side = if p.at == "lshin" then "Left" else "Right"
				local knee = r.attachments[side .. "KneeRigAttachment"][2]
				local ankle = r.attachments[side .. "AnkleRigAttachment"][2]
				mid = (knee + ankle) / 2
				f[2] = (knee - ankle) / ref[2]
			end
			local o = { p.offset[1] * f[1], mid + p.offset[2] * f[2], p.offset[3] * f[3] }
			local sz = { p.size[1] * f[1], p.size[2] * f[2], p.size[3] * f[3] }
			table.insert(pieces, {
				mesh = p.mesh,
				at = p.at,
				part = name,
				role = p.role,
				glow = p.glow == true,
				alpha = p.alpha,
				before = { o, sz },
				after = { o, sz },
			})
		end
		table.insert(kits, { key = k, hair = fit.hair ~= false, pieces = pieces })
	end
	table.insert(out.sets, { name = "gear", fbx = "Gear", kits = kits })
end

-- the weapons (WeaponMesh.pieces style 1) and their grips
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
local used: { [string]: number } = {}
for _, w in Config.Weapons.list do
	local id, family = w[1], w[2]
	local fit = Config.WeaponArt[id]
	local pieces = {}
	for _, p in fit.pieces do
		table.insert(
			pieces,
			row(p.at, p.mesh, p.offset, p.size, {
				role = p.role,
				glow = p.glow == true or p.neon == true,
				blade = p.blade == true,
				mat = p.mat,
			})
		)
	end
	local gname = PART[fit.grip.at]
	local gbo = before(gname, fit.grip.pos, { 0, 0, 0 })
	local gao = BodyFit.place(Config, gname, R[gname].size, fit.grip.pos, { 0, 0, 0 })
	local hold = HeroAnim.holdClip(id, family)
	local per = HeroAnim.WEAPON_CLIPS[id] or HeroAnim.HOLD_CLIPS[family].combo
	local action = if family == "shield" then "block" else per[1]
	-- pt-anims' two-handed weapons play IK-pinned copies of their moves (HeroAnim.pinned, "@hilt", "@pole", "@long")
	local two = HeroAnim.TWO_HAND_WEAPON and HeroAnim.TWO_HAND_WEAPON[id]
	local base = action
	if two and HeroAnim.pinned and not HeroAnim.ONE_HAND_MOVES[action] then
		action = HeroAnim.pinned(action, two)
	end
	if hold then
		used[hold] = 0
	end
	used[action] = MOMENT[base] or 0.1
	table.insert(out.weapons, {
		id = id,
		name = w[3],
		family = family,
		hold = hold,
		action = action,
		grip = { at = fit.grip.at, part = gname, before = gbo, after = gao },
		grip2 = if fit.grip2 then { part = PART[fit.grip2.at], pos = fit.grip2.pos } else nil,
		pieces = pieces,
	})
end
for clip, t in used do
	local angles = {}
	for joint, a in HeroAnim.sample(clip, t) do
		angles[joint] = { a[1], a[2], a[3] }
	end
	out.poses[clip] = angles
end

fs.writeDir("build/fit")
fs.writeFile("build/fit/fits.json", serde.encode("json", out, false))
local n = 0
for _, s in out.sets do
	n += #s.kits
end
print(string.format("wrote build/fit/fits.json: %d sets, %d kits, %d weapons", #out.sets, n, #out.weapons))
