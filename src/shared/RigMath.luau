--!strict
-- RigMath: the blocky R15 rig as numbers, for every character in the game (nate, 2026-11-16: "literally
-- everyone should be r15. enemies too"). Heroes, robots and citizens all use Config.HeroRig: the same 15
-- parts, the same R15 joint names and the same attachments. A layout scales that rig for one body (the
-- creator's BodyShape factors per part, then one overall scale) and works out where each part rests, how
-- high the root stands above the feet and how tall the body is. NpcRig turns a layout into a real R15 model.
-- Pure: no Roblox instances, so Lune tests it.

local RigMath = {}

export type Vec = { number }
export type Joint = { name: string, part0: string, part1: string, c0: Vec, c1: Vec }
export type Layout = {
	root: { size: Vec, attachments: { [string]: Vec } },
	parts: { [string]: { size: Vec, attachments: { [string]: Vec } } },
	joints: { Joint },
	centres: { [string]: Vec }, -- each part's rest centre from the root's centre
	ground: number, -- the root's centre above the soles at rest
	height: number, -- soles to the top of the head
	hip: number, -- the root's centre above the hip joints at rest
}

-- The standard R15 Motor6Ds, parent first (the names Roblox's R15 rig and its animations use). Each joint
-- meets at the attachment named after it plus "RigAttachment" on both parts.
RigMath.JOINTS = {
	{ "Root", "HumanoidRootPart", "LowerTorso" },
	{ "Waist", "LowerTorso", "UpperTorso" },
	{ "Neck", "UpperTorso", "Head" },
	{ "LeftShoulder", "UpperTorso", "LeftUpperArm" },
	{ "LeftElbow", "LeftUpperArm", "LeftLowerArm" },
	{ "LeftWrist", "LeftLowerArm", "LeftHand" },
	{ "RightShoulder", "UpperTorso", "RightUpperArm" },
	{ "RightElbow", "RightUpperArm", "RightLowerArm" },
	{ "RightWrist", "RightLowerArm", "RightHand" },
	{ "LeftHip", "LowerTorso", "LeftUpperLeg" },
	{ "LeftKnee", "LeftUpperLeg", "LeftLowerLeg" },
	{ "LeftAnkle", "LeftLowerLeg", "LeftFoot" },
	{ "RightHip", "LowerTorso", "RightUpperLeg" },
	{ "RightKnee", "RightUpperLeg", "RightLowerLeg" },
	{ "RightAnkle", "RightLowerLeg", "RightFoot" },
}

local function mul(v: Vec, f: Vec, s: number): Vec
	return { v[1] * f[1] * s, v[2] * f[2] * s, v[3] * f[3] * s }
end

-- One body's rig: `factors` are BodyShape's per-part x, y, z factors (nil for the standard body), `scale`
-- sizes the whole body (1 is a hero)
function RigMath.layout(rig: any, factors: { [string]: Vec }?, scale: number?): Layout
	local s = scale or 1
	local one = { 1, 1, 1 }
	local out: any = { parts = {}, joints = {}, centres = {} }
	local rootAt = {}
	for name, at in rig.root.attachments do
		rootAt[name] = mul(at, one, s)
	end
	out.root = { size = mul(rig.root.size, one, s), attachments = rootAt }
	for name, def in rig.parts do
		local f = (factors and factors[name]) or one
		local at = {}
		for an, v in def.attachments do
			at[an] = mul(v, f, s)
		end
		out.parts[name] = { size = mul(def.size, f, s), attachments = at }
	end
	-- rest centres down the chain: a child's centre is its parent's centre plus the parent's joint attachment
	-- less its own
	local centres: { [string]: Vec } = { HumanoidRootPart = { 0, 0, 0 } }
	for _, j in RigMath.JOINTS do
		local name, p0, p1 = j[1], j[2], j[3]
		local key = name .. "RigAttachment"
		local a0 = (if p0 == "HumanoidRootPart" then out.root else out.parts[p0]).attachments[key]
		local a1 = out.parts[p1].attachments[key]
		assert(a0 and a1, "R15 rig attachment missing: " .. key)
		local c = centres[p0]
		centres[p1] = { c[1] + a0[1] - a1[1], c[2] + a0[2] - a1[2], c[3] + a0[3] - a1[3] }
		table.insert(out.joints, { name = name, part0 = p0, part1 = p1, c0 = a0, c1 = a1 })
	end
	out.centres = centres
	local low, high = math.huge, -math.huge
	for name, p in out.parts do
		local c = centres[name]
		low = math.min(low, c[2] - p.size[2] * 0.5)
		high = math.max(high, c[2] + p.size[2] * 0.5)
	end
	out.ground = -low
	out.height = high - low
	local hipAt = out.parts.LowerTorso.attachments.LeftHipRigAttachment
	out.hip = -(centres.LowerTorso[2] + hipAt[2])
	return out :: Layout
end

return RigMath
