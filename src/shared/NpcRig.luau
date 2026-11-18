-- NpcRig: builds a real R15 rig for the characters the game draws itself, robots and citizens (nate,
-- 2026-11-16: "literally everyone should be r15. enemies too"). It is the heroes' rig (Config.HeroRig, the
-- same one HeroBody turns into StarterCharacter): a HumanoidRootPart, the 15 R15 parts with every rig and
-- accessory attachment, the 15 standard Motor6Ds (Root, Waist, Neck, LeftShoulder, ...) and an
-- AnimationController, so the creator's pieces and Roblox R15 animations fit every body. A rig has no
-- Humanoid (a hundred of them on a phone would cost too much) and is drawn on the device only:
-- * the root is anchored and moved with BulkMoveTo, the limbs follow through the joints;
-- * poses are set on the Motor6Ds' Transform (NpcRig.turn), written only when they change.
-- The 15 parts use the hero meshes (ReplicatedStorage.Art.Hero, reshaped per body set from Art.Bodies) once
-- nate imports them, else plain blocks of the same sizes, which is the same blocky body.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RigMath = require(script.Parent.RigMath)
local ClothesMap = require(script.Parent.ClothesMap)

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

-- the clothes Textures on a face the body hides at rest (ClothesMap.tucked), drawn only up close
local tucked: { [Texture]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

-- The imported meshes by part name for one body set (BodyShape.setKey; nil is the hero body, "MaleMedium"):
-- each part from ReplicatedStorage.Art.Bodies["<set>_<part>"] when the set reshapes it, else the hero's own
-- part from Art.Hero. Nil while any of the 15 hero parts is missing (plain blocks then). Found once per set.
-- `look` names a whole shell set instead (ReplicatedStorage.Art[look], e.g. "Trooper": a remade robot's
-- armour, its 15 parts filling the same boxes); nil while it is not imported, and the caller falls back.
local meshCache: { [string]: { [string]: MeshPart } | false } = {}
function NpcRig.meshes(set: string?, look: string?): { [string]: MeshPart }?
	local key = if look then "look:" .. look else set or "MaleMedium"
	local cached = meshCache[key]
	if cached ~= nil then
		return cached or nil
	end
	local art = ReplicatedStorage:FindFirstChild("Art")
	if look then
		local lf = art and art:FindFirstChild(look)
		local out = {}
		local ok = lf ~= nil
		if lf then
			for _, j in RigMath.JOINTS do
				local found = lf:FindFirstChild(j[3], true)
				if found and found:IsA("MeshPart") then
					out[j[3]] = found
				else
					ok = false
				end
			end
		end
		meshCache[key] = if ok then out else false
		return if ok then out else nil
	end
	local folder = art and art:FindFirstChild("Hero")
	local bodies = art and art:FindFirstChild("Bodies")
	local out = {}
	local ok = folder ~= nil
	if folder then
		for _, j in RigMath.JOINTS do
			local name = j[3]
			local shaped = bodies and key ~= "MaleMedium" and bodies:FindFirstChild(key .. "_" .. name, true)
			local found = if shaped and shaped:IsA("MeshPart")
				then shaped
				else folder:FindFirstChild(name, true)
			if found and found:IsA("MeshPart") then
				out[name] = found
			else
				ok = false
			end
		end
	end
	meshCache[key] = if ok then out else false
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

-- Keep a mesh's textures (its SurfaceAppearance) and drop the importer's other children. The colour map's
-- alpha lets the part's own Color show through (Overlay), so tints and hit flashes still work.
function NpcRig.keepLook(p: BasePart)
	for _, c in p:GetChildren() do
		if c:IsA("SurfaceAppearance") then
			c.AlphaMode = Enum.AlphaMode.Overlay
		else
			c:Destroy()
		end
	end
end

-- A rig for one body. `colors` paints each of the 15 parts by name (a missing name stays grey); `set` picks the
-- body set's meshes (BodyShape.setKey: use the gender and build the layout's factors came from); `look` a
-- whole shell set (NpcRig.meshes), when imported.
function NpcRig.build(
	layout: RigMath.Layout,
	name: string,
	colors: { [string]: Color3 },
	material: Enum.Material?,
	shadows: boolean?,
	set: string?,
	look: string?
): Rig
	local meshes = (look and NpcRig.meshes(set, look)) or NpcRig.meshes(set)
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
			NpcRig.keepLook(p) -- the importer's own children go; the rig's attachments replace them
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

-- A plain person on the rig (citizens, quest givers, the stranded at incidents): the shirt on the torso and
-- upper arms, skin on the forearms, hands and head with Roblox's classic face, pants, darker shoes and blocky
-- hair (Hair, fixed to the head; nil hair leaves it off). `set` is the body set (BodyShape.setKey) whose
-- factors made `layout`.
function NpcRig.person(
	layout: RigMath.Layout,
	name: string,
	shirt: Color3,
	pants: Color3,
	skin: Color3,
	hair: Color3?,
	set: string?
): Rig
	local shoes = pants:Lerp(Color3.new(0, 0, 0), 0.5)
	local colors: { [string]: Color3 } = { Head = skin, UpperTorso = shirt, LowerTorso = pants }
	for _, s in { "Left", "Right" } do
		colors[s .. "UpperArm"] = shirt
		colors[s .. "LowerArm"] = skin
		colors[s .. "Hand"] = skin
		colors[s .. "UpperLeg"] = pants
		colors[s .. "LowerLeg"] = pants
		colors[s .. "Foot"] = shoes
	end
	local rig = NpcRig.build(layout, name, colors, nil, nil, set)
	local head = rig.parts.Head
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Texture = "rbxasset://textures/face.png" -- Roblox's built-in default face, like the heroes
	face.Face = Enum.NormalId.Front
	face.Parent = head
	if hair then
		local h = Instance.new("Part")
		h.Name = "Hair"
		h.Size = head.Size * Vector3.new(1.06, 0.3, 1.06)
		h.Color = hair
		h.Material = Enum.Material.SmoothPlastic
		h.TopSurface = Enum.SurfaceType.Smooth
		h.BottomSurface = Enum.SurfaceType.Smooth
		h.CastShadow = false
		NpcRig.fix(rig, "Head", h, CFrame.new(0, head.Size.Y * 0.45, head.Size.Z * 0.04))
	end
	return rig
end

-- Classic Roblox clothes on the rig (no Humanoid needed): one clothes image (the shirt over the pants on the
-- classic template) shown on every face of the torso, arms and legs with a Texture cut to that face's piece of
-- the template (Shared.ClothesMap). `sign` is Config.NpcLooks.offsetSign. Returns the Textures by part, so the
-- caller can hide a part's clothes with it.
function NpcRig.dress(rig: Rig, image: string, sign: number?): { [string]: { Texture } }
	local out: { [string]: { Texture } } = {}
	for pname, p in rig.parts do
		local list = {}
		for _, face in ClothesMap.FACES do
			local r = ClothesMap.rect(pname, face)
			if r then
				local fw, fh = ClothesMap.faceSize({ p.Size.X, p.Size.Y, p.Size.Z }, face)
				local su, sv, ou, ov = ClothesMap.texture(r, fw, fh, sign)
				local t = Instance.new("Texture")
				t.Name = "Clothes"
				t.Texture = image
				t.Face = (Enum.NormalId :: any)[face]
				t.StudsPerTileU = su
				t.StudsPerTileV = sv
				t.OffsetStudsU = ou
				t.OffsetStudsV = ov
				t.Parent = p
				if ClothesMap.tucked(pname, face) then
					tucked[t] = true
				end
				table.insert(list, t)
			end
		end
		out[pname] = list
	end
	return out
end

-- Classic clothes from a separate Shirt and Pants image (585 x 559 each, like real Roblox clothing): the upper
-- torso and arms show the shirt, the lower torso and legs the pants. Returns the Textures by part (swap their
-- Texture and Color3 to re-dress a pooled rig: ClothesMap.half says which image a part shows).
function NpcRig.dressPair(rig: Rig, shirt: string, pants: string, sign: number?): { [string]: { Texture } }
	local out: { [string]: { Texture } } = {}
	for pname, p in rig.parts do
		local list = {}
		local image = if ClothesMap.half(pname) == 0 then shirt else pants
		for _, face in ClothesMap.FACES do
			local r = ClothesMap.rect(pname, face, true)
			if r then
				local fw, fh = ClothesMap.faceSize({ p.Size.X, p.Size.Y, p.Size.Z }, face)
				local su, sv, ou, ov = ClothesMap.texture(r, fw, fh, sign, ClothesMap.TEMPLATE_W)
				local t = Instance.new("Texture")
				t.Name = "Clothes"
				t.Texture = image
				t.Face = (Enum.NormalId :: any)[face]
				t.StudsPerTileU = su
				t.StudsPerTileV = sv
				t.OffsetStudsU = ou
				t.OffsetStudsV = ov
				t.Parent = p
				if ClothesMap.tucked(pname, face) then
					tucked[t] = true
				end
				table.insert(list, t)
			end
		end
		out[pname] = list
	end
	return out
end

-- Perf pass (2026-11-18): how much of a rig's clothes are drawn, by ClothesMap.level (2 every face, 1 all but
-- the tucked faces, 0 none: the part colours under them match). A Texture is taken off its part (Parent nil)
-- and put back, never remade, so re-dressing a pooled rig (Texture, Color3, Transparency) still works while it
-- is off. `clothes` is what dress or dressPair returned (nil does nothing).
function NpcRig.showClothes(rig: Rig, clothes: { [string]: { Texture } }?, level: number)
	if not clothes then
		return
	end
	for pname, list in clothes do
		local p = rig.parts[pname]
		for _, t in list do
			local parent = if level >= 2 or (level == 1 and not tucked[t]) then p else nil
			if t.Parent ~= parent then
				t.Parent = parent
			end
		end
	end
end

-- A side quest person's own outfit (Shared.PeopleLooks.outfit): its clothes image on the body (NpcRig.dress) and
-- its face on the head's face decal (a new decal when the head has none). Either may be missing. Returns the
-- clothes Textures by part (nil without a clothes image).
function NpcRig.wearOutfit(
	rig: Rig,
	fit: { clothes: string?, face: string? },
	sign: number?
): { [string]: { Texture } }?
	local clothes = if fit.clothes then NpcRig.dress(rig, fit.clothes, sign) else nil
	if fit.face then
		local d = rig.parts.Head:FindFirstChild("face")
		if d and d:IsA("Decal") then
			d.Texture = fit.face
		else
			NpcRig.face(rig, fit.face)
		end
	end
	return clothes
end

-- A face decal on the head (a Roblox face; swap its Texture to change the face)
function NpcRig.face(rig: Rig, image: string): Decal
	local d = Instance.new("Decal")
	d.Name = "face"
	d.Texture = image
	d.Face = Enum.NormalId.Front
	d.Parent = rig.parts.Head
	return d
end

-- Wear a Roblox accessory (hair, a hat) without a Humanoid: its handle is scaled from Roblox's standard 1.2 stud
-- head to this rig's head and fixed where its attachment meets the rig's attachment of the same name (the
-- rig has every R15 accessory attachment). Returns the handle (named `name`), or nil if it cannot fit.
function NpcRig.wear(rig: Rig, accessory: Accessory, name: string): BasePart?
	local src = accessory:FindFirstChild("Handle")
	if not (src and src:IsA("BasePart")) then
		return nil
	end
	local handle = src:Clone()
	local att = handle:FindFirstChildWhichIsA("Attachment")
	if not att then
		handle:Destroy()
		return nil
	end
	local target: Attachment?, parent: string? = nil, nil
	for pname, p in rig.parts do
		local a = p:FindFirstChild(att.Name)
		if a and a:IsA("Attachment") then
			target, parent = a, pname
			break
		end
	end
	if not (target and parent) then
		handle:Destroy()
		return nil
	end
	local k = rig.parts.Head.Size.Y / 1.2
	local mesh = handle:FindFirstChildWhichIsA("SpecialMesh")
	if mesh then
		mesh.Scale *= k
		mesh.Offset *= k
	end
	handle.Size *= k
	for _, d in handle:GetDescendants() do
		if d:IsA("Attachment") then
			d.Position *= k
		elseif d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	handle.Name = name
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	handle.CastShadow = false
	NpcRig.fix(rig, parent :: string, handle, (target :: Attachment).CFrame * att.CFrame:Inverse())
	return handle
end

-- Stand the rig with its soles on `feet` (a position and facing)
function NpcRig.place(rig: Rig, feet: CFrame)
	rig.model:PivotTo(feet * CFrame.new(0, rig.layout.ground, 0))
end

-- A held pose for a still figure, set on the joint's C0 so the server's pose reaches every player (Transform
-- stays on the device that sets it)
function NpcRig.bend(rig: Rig, joint: string, cf: CFrame)
	local m = rig.motors[joint]
	if m then
		m.C0 = CFrame.new(m.C0.Position) * cf
	end
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
