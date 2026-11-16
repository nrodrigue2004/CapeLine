-- NpcRig: builds a real R15 rig for the characters the game draws itself, robots and citizens (nate,
-- 2026-11-16: "literally everyone should be r15. enemies too"). It is the heroes' rig (Config.HeroRig, the
-- same one HeroBody turns into StarterCharacter): a HumanoidRootPart, the 15 R15 parts with every rig and
-- accessory attachment, the 15 standard Motor6Ds (Root, Waist, Neck, LeftShoulder, ...) and an
-- AnimationController, so the creator's pieces and Roblox R15 animations fit every body. A rig has no
-- Humanoid (a hundred of them on a phone would cost too much) and is drawn on the device only:
-- * the root is anchored and moved with BulkMoveTo, the limbs follow through the joints;
-- * poses are set on the Motor6Ds' Transform (NpcRig.turn), written only when they change.
-- The 15 parts use the hero meshes (ReplicatedStorage.Art.Hero) once nate imports them, else plain blocks of
-- the same sizes, which is the same blocky body.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RigMath = require(script.Parent.RigMath)

local NpcRig = {}

export type Rig = {
	model: Model,
	root: BasePart,
	parts: { [string]: BasePart },
	motors: { [string]: Motor6D },
	last: { [string]: CFrame },
	layout: RigMath.Layout,
}

local GRIP = CFrame.Angles(-math.pi / 2, 0, 0)

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

-- The imported hero meshes by part name, or nil while any of the 15 is missing (found once)
local meshCache: { [string]: MeshPart } | false | nil = nil
function NpcRig.meshes(): { [string]: MeshPart }?
	if meshCache ~= nil then
		return meshCache or nil
	end
	local art = ReplicatedStorage:FindFirstChild("Art")
	local folder = art and art:FindFirstChild("Hero")
	local out = {}
	local ok = folder ~= nil
	if folder then
		for _, j in RigMath.JOINTS do
			local name = j[3]
			local found = folder:FindFirstChild(name, true)
			if found and found:IsA("MeshPart") then
				out[name] = found
			else
				ok = false
			end
		end
	end
	meshCache = if ok then out else false
	return if ok then out else nil
end

local function attach(part: BasePart, list: { [string]: { number } })
	for name, at in list do
		local a = Instance.new("Attachment")
		a.Name = name
		a.CFrame = CFrame.new(v3(at))
			* (if string.find(name, "GripAttachment", 1, true) then GRIP else CFrame.identity)
		a.Parent = part
	end
end

local function quiet(p: BasePart)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
end

-- A rig for one body. `colors` paints each of the 15 parts by name (a missing name stays grey).
function NpcRig.build(
	layout: RigMath.Layout,
	name: string,
	colors: { [string]: Color3 },
	material: Enum.Material?,
	shadows: boolean?
): Rig
	local meshes = NpcRig.meshes()
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = v3(layout.root.size)
	root.Transparency = 1
	root.Anchored = true
	root.CastShadow = false
	quiet(root)
	attach(root, layout.root.attachments)
	root.Parent = model
	model.PrimaryPart = root
	local parts: { [string]: BasePart } = {}
	for pname, def in layout.parts do
		local mesh = meshes and meshes[pname]
		local p: BasePart
		if mesh then
			p = mesh:Clone()
			for _, c in p:GetChildren() do
				c:Destroy() -- the importer's own children; the rig's attachments replace them
			end
		else
			local part = Instance.new("Part")
			part.TopSurface = Enum.SurfaceType.Smooth
			part.BottomSurface = Enum.SurfaceType.Smooth
			p = part
		end
		p.Name = pname
		p.Size = v3(def.size)
		p.CFrame = CFrame.new(v3(layout.centres[pname]))
		p.Color = colors[pname] or Color3.fromRGB(163, 162, 165)
		p.Material = material or Enum.Material.SmoothPlastic
		p.Anchored = false
		p.CastShadow = shadows == true
		quiet(p)
		attach(p, def.attachments)
		p.Parent = model
		parts[pname] = p
	end
	local motors: { [string]: Motor6D } = {}
	for _, j in layout.joints do
		local m = Instance.new("Motor6D")
		m.Name = j.name
		m.Part0 = if j.part0 == "HumanoidRootPart" then root else parts[j.part0]
		m.Part1 = parts[j.part1]
		m.C0 = CFrame.new(v3(j.c0))
		m.C1 = CFrame.new(v3(j.c1))
		m.Parent = parts[j.part1] -- where Roblox's own R15 rig keeps each joint
		motors[j.name] = m
	end
	local ac = Instance.new("AnimationController")
	ac.Parent = model
	return { model = model, root = root, parts = parts, motors = motors, last = {}, layout = layout }
end

-- Fix an extra piece (a bone, a cape, a helmet) to one of the rig's parts, `c0` from that part's centre;
-- the joint gets `name` so NpcRig.turn can move it. Returns the joint.
function NpcRig.fix(
	rig: Rig,
	parent: string,
	piece: BasePart,
	c0: CFrame,
	name: string?,
	c1: CFrame?
): Motor6D
	local p0 = if parent == "HumanoidRootPart" then rig.root else rig.parts[parent]
	piece.Anchored = false
	quiet(piece)
	piece.CFrame = p0.CFrame * c0 * (c1 or CFrame.identity):Inverse()
	local m = Instance.new("Motor6D")
	m.Name = name or piece.Name
	m.Part0 = p0
	m.Part1 = piece
	m.C0 = c0
	m.C1 = c1 or CFrame.identity
	m.Parent = piece
	if name then
		rig.motors[name] = m
	end
	piece.Parent = rig.model
	return m
end

-- Set one joint's pose (its Transform), skipped when it has not changed since the last frame
function NpcRig.turn(rig: Rig, joint: string, cf: CFrame)
	local last = rig.last[joint]
	if last and last == cf then
		return
	end
	local m = rig.motors[joint]
	if m then
		m.Transform = cf
		rig.last[joint] = cf
	end
end

-- Back to the rest pose (a pooled body given to someone new)
function NpcRig.rest(rig: Rig)
	for joint, m in rig.motors do
		m.Transform = CFrame.identity
		rig.last[joint] = CFrame.identity
	end
end

return NpcRig
