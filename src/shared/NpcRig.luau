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
-- nate's playtest (2026-11-19): "Npcs and enemies still don't wear clothes properly", "there are still npcs that
-- don't look like Roblox avatars". Like the heroes (HeroBody.robloxBody), every rig now uses Roblox's own blocky
-- R15 meshes (ReplicatedStorage.RobloxBody, published by HeroBody at boot) with an inert Humanoid (no state
-- machine, no name or health), so real Shirt and Pants composite onto the meshes' own UVs exactly as on any
-- avatar (NpcRig.setClothes; Config.ClothesSplit gives each side by side clothes image its Shirt and Pants).
-- Faces come from Roblox's catalog (Config.CatalogLooks) and hair from catalog accessories
-- (ReplicatedStorage.CatalogLooks). Until RobloxBody is there, the old Texture clothes stay the fallback.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RigMath = require(script.Parent.RigMath)
local ClothesMap = require(script.Parent.ClothesMap)

local NpcRig = {}

-- Config, found once (NpcRig runs on the server and every device; the Config folder is in ReplicatedStorage)
local cfgCache: any = nil
local function config(): any
	if cfgCache == nil then
		local c = ReplicatedStorage:FindFirstChild("Config")
		cfgCache = if c then require(c :: any) else false
	end
	return cfgCache or nil
end

export type Rig = {
	model: Model,
	root: BasePart,
	parts: { [string]: BasePart },
	motors: { [string]: Motor6D },
	last: { [string]: CFrame },
	layout: RigMath.Layout,
	-- poses written over an Animator (NpcRig.over) and the Animator's own pose under each (NpcRig.animBase)
	wrote: { [string]: CFrame },
	base: { [string]: CFrame },
	-- on Roblox's own body: the inert Humanoid that lets real Shirt and Pants show, and those two
	humanoid: Humanoid?,
	shirt: Shirt?,
	pants: Pants?,
	-- catalog hair accessories worn (NpcRig.showHair shows one) and the blocky hair they replace
	hairs: { BasePart }?,
	-- true once NpcRig.wearCast put a named person's own catalog hair on (showHair then leaves it)
	castHair: boolean?,
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
-- Roblox's own blocky R15 meshes (ReplicatedStorage.RobloxBody, from HeroBody.init), or nil while they are not
-- there or Config.NpcLooks.robloxBody is off. Not cached until found (they arrive at boot).
local robloxCache: { [string]: MeshPart }? = nil
function NpcRig.robloxMeshes(): { [string]: MeshPart }?
	if robloxCache then
		return robloxCache
	end
	local cfg = config()
	if cfg and cfg.NpcLooks.robloxBody == false then
		return nil
	end
	local folder = ReplicatedStorage:FindFirstChild("RobloxBody")
	if not folder then
		return nil
	end
	local out = {}
	for _, j in RigMath.JOINTS do
		local found = folder:FindFirstChild(j[3])
		if not (found and found:IsA("MeshPart")) then
			return nil
		end
		out[j[3]] = found
	end
	robloxCache = out
	return out
end

function NpcRig.meshes(set: string?, look: string?): { [string]: MeshPart }?
	if not look then
		local rb = NpcRig.robloxMeshes()
		if rb then
			return rb -- every body set on Roblox's own body (its sizes still come from the layout)
		end
	end
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
	local hum: Humanoid? = nil
	if meshes and meshes == NpcRig.robloxMeshes() then
		-- inert: no states, physics, name or health; it is only there so Shirt and Pants composite (the root
		-- stays anchored and the joints are posed as before)
		local h = Instance.new("Humanoid")
		h.RigType = Enum.HumanoidRigType.R15
		h.EvaluateStateMachine = false
		h.RequiresNeck = false
		h.BreakJointsOnDeath = false
		h.AutomaticScalingEnabled = false
		h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		h.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		h.NameDisplayDistance = 0
		h.HealthDisplayDistance = 0
		h.Parent = model
		hum = h
	end
	return {
		model = model,
		root = root,
		parts = parts,
		motors = motors,
		last = {},
		layout = layout,
		wrote = {},
		base = {},
		humanoid = hum,
	}
end

-- Real Roblox clothes on a rig on Roblox's own body (a no-op without its Humanoid): the Shirt and Pants
-- templates (image content ids; nil takes that piece off). Re-dressing a pooled rig just sets them again.
function NpcRig.setClothes(rig: Rig, shirt: string?, pants: string?)
	if not rig.humanoid then
		return
	end
	if shirt then
		local s = rig.shirt or Instance.new("Shirt")
		s.Name = "NpcShirt"
		if s.ShirtTemplate ~= shirt then
			s.ShirtTemplate = shirt
		end
		s.Parent = rig.model
		rig.shirt = s
	elseif rig.shirt then
		rig.shirt.Parent = nil
	end
	if pants then
		local p = rig.pants or Instance.new("Pants")
		p.Name = "NpcPants"
		if p.PantsTemplate ~= pants then
			p.PantsTemplate = pants
		end
		p.Parent = rig.model
		rig.pants = p
	elseif rig.pants then
		rig.pants.Parent = nil
	end
end

-- Tint the real clothes (a citizen's shirt and pants colours, a frozen robot's ice); nil pants takes the shirt's
function NpcRig.tintClothes(rig: Rig, shirt: Color3, pants: Color3?)
	if rig.shirt and rig.shirt.Color3 ~= shirt then
		rig.shirt.Color3 = shirt
	end
	local p = pants or shirt
	if rig.pants and rig.pants.Color3 ~= p then
		rig.pants.Color3 = p
	end
end

-- Whether the rig wears real Shirt and Pants (so per-part clothes Textures are not used)
function NpcRig.realClothes(rig: Rig): boolean
	return rig.humanoid ~= nil
end

-- A side by side clothes image's own Shirt and Pants (Config.ClothesSplit), as content ids
function NpcRig.split(image: string): (string?, string?)
	local cfg = config()
	local map = cfg and cfg.ClothesSplit
	local n = tonumber(string.match(image, "(%d+)%s*$"))
	local pair = map and n and map[n]
	if pair then
		return "rbxassetid://" .. pair[1], "rbxassetid://" .. pair[2]
	end
	return nil, nil
end

-- An empty Textures table by part (what dress and dressPair return on a rig in real clothes)
local function noTextures(rig: Rig): { [string]: { Texture } }
	local out = {}
	for pname in rig.parts do
		out[pname] = {}
	end
	return out
end

-- Re-dress a pooled rig with a side by side clothes image (its real Shirt and Pants, or its Textures)
function NpcRig.redress(rig: Rig, clothes: { [string]: { Texture } }?, image: string)
	if rig.humanoid then
		local s, p = NpcRig.split(image)
		if s then
			NpcRig.setClothes(rig, s, p)
			return
		end
	end
	for _, list in clothes or {} do
		for _, t in list do
			t.Texture = image
		end
	end
end

-- Re-dress a pooled rig with a separate Shirt and Pants image and their tints (white keeps the image's colours)
function NpcRig.redressPair(
	rig: Rig,
	clothes: { [string]: { Texture } }?,
	shirt: string,
	pants: string,
	top: Color3?,
	bottom: Color3?
)
	if rig.humanoid then
		NpcRig.setClothes(rig, shirt, pants)
		NpcRig.tintClothes(rig, top or Color3.new(1, 1, 1), bottom or Color3.new(1, 1, 1))
		return
	end
	for pname, list in clothes or {} do
		local upper = ClothesMap.half(pname) == 0
		for _, t in list do
			t.Texture = if upper then shirt else pants
			if top and bottom then
				t.Color3 = if upper then top else bottom
			end
		end
	end
end

-- A Roblox catalog face's image (Config.CatalogLooks.faces) picked by `h`, or nil when there are none
function NpcRig.catalogFace(h: number): string?
	local cfg = config()
	local faces = cfg and cfg.CatalogLooks and cfg.CatalogLooks.faces
	if not faces or #faces == 0 then
		return nil
	end
	return "rbxassetid://" .. faces[h % #faces + 1][3]
end

-- Every catalog face image, in Config order (the same on every device)
function NpcRig.catalogFaces(): { string }
	local cfg = config()
	local out = {}
	for _, f in (cfg and cfg.CatalogLooks and cfg.CatalogLooks.faces) or {} do
		table.insert(out, "rbxassetid://" .. f[3])
	end
	return out
end

local HAIR_SLOTS = 3
-- Catalog hair (ReplicatedStorage.CatalogLooks, loaded by the server at boot): a rig wears up to three hairs
-- picked by `seed` and shows the one `h` picks; the blocky "Hair" part hides once one is worn. Hairs that have
-- not loaded yet are tried again on the next call, so a rig built early still gets one.
function NpcRig.showHair(rig: Rig, seed: number, h: number)
	if rig.castHair then
		return -- a named person's own catalog hair (NpcRig.wearCast)
	end
	local hairs = rig.hairs or {}
	rig.hairs = hairs
	if #hairs == 0 then
		local lib = ReplicatedStorage:FindFirstChild("CatalogLooks")
		local list = {}
		for _, c in if lib then lib:GetChildren() else {} do
			if c:IsA("Accessory") and c:GetAttribute("Kind") ~= "beard" then
				table.insert(list, c)
			end
		end
		table.sort(list, function(a, b)
			return a.Name < b.Name -- the same pick on every device
		end)
		for i = 1, math.min(HAIR_SLOTS, #list) do
			local acc = list[(seed + (i - 1) * 17) % #list + 1]
			local handle = NpcRig.wear(rig, acc :: Accessory, "CatHair" .. i)
			if handle then
				table.insert(hairs, handle)
			end
		end
	end
	if #hairs == 0 then
		return
	end
	local pick = h % #hairs + 1
	for i, handle in hairs do
		handle.Transparency = if i == pick then 0 else 1
	end
	local blocky = rig.model:FindFirstChild("Hair")
	if blocky and blocky:IsA("BasePart") then
		blocky.Transparency = 1
	end
end

-- A named person's explicit Roblox catalog pick (Shared.PeopleLooks.castPick, Config.NpcLooks.cast; 2026-11-19,
-- the hair fit pass): the face decal shows the picked catalog face, and the picked catalog hair replaces the hairs
-- showHair hung on the rig (it goes on once CatalogLookService has loaded it); bald takes every hair off.
function NpcRig.wearCast(rig: Rig, pick: { face: string?, hair: number?, bald: boolean?, beard: number? }?)
	if not pick then
		return
	end
	if pick.face then
		local d = rig.parts.Head:FindFirstChild("face")
		if d and d:IsA("Decal") then
			d.Texture = pick.face
		else
			NpcRig.face(rig, pick.face)
		end
	end
	-- the person's catalog beard (gap-villains, 2026-11-19), on its own face attachment once loaded
	local beard = pick.beard
	if beard and not rig.model:FindFirstChild("CatBeard", true) then
		local lib = ReplicatedStorage:FindFirstChild("CatalogLooks")
		local src = lib and lib:FindFirstChild(tostring(beard))
		if src and src:IsA("Accessory") then
			NpcRig.wear(rig, src, "CatBeard")
		elseif lib then
			local conn: RBXScriptConnection? = nil
			conn = lib.ChildAdded:Connect(function(c)
				if not rig.model.Parent then
					(conn :: RBXScriptConnection):Disconnect()
				elseif c.Name == tostring(beard) and c:IsA("Accessory") then
					(conn :: RBXScriptConnection):Disconnect()
					NpcRig.wear(rig, c, "CatBeard")
				end
			end)
		end
	end
	if not pick.hair and not pick.bald then
		return
	end
	for _, h in (rig.hairs or {}) :: { BasePart } do
		h:Destroy()
	end
	rig.hairs = {}
	rig.castHair = true -- showHair leaves this rig alone from now on
	local blocky = rig.model:FindFirstChild("Hair")
	if blocky and blocky:IsA("BasePart") then
		blocky.Transparency = if pick.bald then 1 else 0 -- the blocky cap stays only until the catalog hair is in
	end
	local id = pick.hair
	if not id then
		return
	end
	local function put(acc: Instance): boolean
		if not acc:IsA("Accessory") then
			return false
		end
		local handle = NpcRig.wear(rig, acc, "CatHair1")
		if handle then
			rig.hairs = { handle }
			if blocky and blocky:IsA("BasePart") then
				blocky.Transparency = 1
			end
		end
		return true
	end
	local lib = ReplicatedStorage:FindFirstChild("CatalogLooks")
	local src = lib and lib:FindFirstChild(tostring(id))
	if src then
		put(src)
	elseif lib then
		local conn: RBXScriptConnection? = nil
		conn = lib.ChildAdded:Connect(function(c)
			if not rig.model.Parent then
				(conn :: RBXScriptConnection):Disconnect()
			elseif c.Name == tostring(id) then
				(conn :: RBXScriptConnection):Disconnect()
				put(c)
			end
		end)
	end
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
	-- a Roblox catalog face picked by the name (citizens re-pick theirs by id), else Roblox's default face
	local seed = 0
	for i = 1, #name do
		seed = (seed * 31 + string.byte(name, i)) % 1000003
	end
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Texture = NpcRig.catalogFace(seed) or "rbxasset://textures/face.png"
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
		-- catalog hair over it once loaded (the blocky cap is only the fallback)
		NpcRig.showHair(rig, seed, seed // 7)
	end
	return rig
end

-- Classic Roblox clothes on the rig (no Humanoid needed): one clothes image (the shirt over the pants on the
-- classic template) shown on every face of the torso, arms and legs with a Texture cut to that face's piece of
-- the template (Shared.ClothesMap). `sign` is Config.NpcLooks.offsetSign. Returns the Textures by part, so the
-- caller can hide a part's clothes with it.
function NpcRig.dress(rig: Rig, image: string, sign: number?): { [string]: { Texture } }
	if rig.humanoid then
		local s, p = NpcRig.split(image)
		if s then
			NpcRig.setClothes(rig, s, p)
			return noTextures(rig)
		end
	end
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
	if rig.humanoid then
		NpcRig.setClothes(rig, shirt, pants)
		return noTextures(rig)
	end
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
	table.clear(rig.wrote)
	table.clear(rig.base)
end

-- Over an Animator (NpcLoco plays Roblox's own idle, walk and run on the rig; poses go on in PreSimulation,
-- after the Animator): the joint's pose as the Animator set it this frame, or the last one it set when it
-- left our own pose in place (so an offset on top never stacks up frame after frame)
function NpcRig.animBase(rig: Rig, joint: string): CFrame
	local m = rig.motors[joint]
	if not m then
		return CFrame.identity
	end
	local now = m.Transform
	local wrote = rig.wrote[joint]
	if wrote and now == wrote then
		return rig.base[joint] or CFrame.identity
	end
	rig.base[joint] = now
	return now
end

-- Write a joint's pose over the Animator: every frame (the Animator rewrites the joints it plays each frame,
-- so NpcRig.turn's skip-if-unchanged would let its pose show through)
function NpcRig.over(rig: Rig, joint: string, cf: CFrame)
	local m = rig.motors[joint]
	if m then
		m.Transform = cf
		rig.wrote[joint] = cf
		rig.last[joint] = cf
	end
end

-- The Animator stopped: forget what was written over it, so NpcRig.turn writes every joint again
function NpcRig.overDone(rig: Rig)
	table.clear(rig.wrote)
	table.clear(rig.base)
	table.clear(rig.last)
end

return NpcRig
