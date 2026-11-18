-- HeroBody: every hero on the same base body, on the standard Roblox R15 rig (nate, 2026-11-16: "All humanoid
-- models should follow that basic r15 roblox model" ... "i want the blocky version"): the classic blocky Roblox
-- body on the R15 rig. The 15 meshes come from art/blender/hero.py (imported
-- into ReplicatedStorage.Art.Hero); Config.HeroRig has each part's size, centre and attachments. At boot this
-- builds StarterPlayer.StarterCharacter from them: a HumanoidRootPart, the 15 MeshParts, every R15 rig and
-- accessory attachment, a Humanoid (R15) and the Motor6Ds from Humanoid:BuildRigFromAttachments, so Roblox's
-- R15 animations, emotes and the creator's pieces (LookKit, by part name) all work on it.
-- Until the meshes are imported nothing changes: heroes keep the player's own avatar body.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local NpcRig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("NpcRig"))
local AvatarRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AvatarRules"))

local HeroBody = {}

local RIG = Config.HeroRig
-- the parts the Humanoid lets collide (like Roblox's own R15 rig); limbs pass through
local SOLID = { Head = true, UpperTorso = true, LowerTorso = true }
-- grips point the way tools expect (standard R15: turned -90 degrees about X)
local GRIP = CFrame.Angles(-math.pi / 2, 0, 0)

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

-- The imported meshes, by part name, or nil while any of the 15 is missing (shared with NpcRig, which puts
-- robots and citizens on the same body)
HeroBody.meshes = NpcRig.meshes

local function attach(part: BasePart, list: { [string]: { number } })
	for name, at in list do
		local a = Instance.new("Attachment")
		a.Name = name
		a.CFrame = CFrame.new(v3(at))
			* (if string.find(name, "GripAttachment", 1, true) then GRIP else CFrame.identity)
		a.Parent = part
	end
end

-- The character model: standing on y = 0 at the origin (spawning moves it)
function HeroBody.build(meshes: { [string]: MeshPart }): Model
	local model = Instance.new("Model")
	model.Name = "StarterCharacter"

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = v3(RIG.root.size)
	root.CFrame = CFrame.new(v3(RIG.root.centre))
	root.Transparency = 1
	root.CanCollide = false
	attach(root, RIG.root.attachments)
	root.Parent = model
	model.PrimaryPart = root

	for name, def in RIG.parts do
		local p = meshes[name]:Clone()
		p.Name = name
		for _, c in p:GetChildren() do
			c:Destroy() -- the importer's own children; the rig's attachments replace them
		end
		p.Size = v3(def.size)
		p.CFrame = CFrame.new(v3(def.centre))
		p.Anchored = false
		p.CanCollide = SOLID[name] == true
		p.CastShadow = true
		attach(p, def.attachments)
		p.Parent = model
	end

	local face = Instance.new("Decal")
	face.Name = "face"
	face.Texture = "rbxasset://textures/face.png" -- Roblox's built-in default face
	face.Face = Enum.NormalId.Front
	face.Parent = model:FindFirstChild("Head")

	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R15
	hum.HipHeight = RIG.hipHeight
	hum.Parent = model
	hum:BuildRigFromAttachments() -- the Motor6Ds (Root, Waist, Neck, shoulders, elbows, ...) from the attachments
	return model
end

-- Roblox's own blocky R15 body (nate's playtest, 2026-11-18: "Clothes still dont look right ... none of them look
-- or fit right", "the hair isnt fitting"). A blank HumanoidDescription at the classic scales gives the default
-- blocky R15 character with Roblox's own meshes, which map classic Shirt and Pants exactly as on any avatar and
-- carry the standard accessory attachments catalog hair and faces are made for. Config.Creator.robloxBody
-- switches it; the Blender hero body (below) stays the fallback if the description cannot load.
function HeroBody.robloxBody(): Model?
	local desc = Instance.new("HumanoidDescription")
	for field, value in AvatarRules.SCALES do
		(desc :: any)[field] = value
	end
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	desc:Destroy()
	if not ok or not model then
		warn("[HeroBody] Roblox's blocky body did not load:", model)
		return nil
	end
	for _, d in model:GetDescendants() do
		if
			d:IsA("LuaSourceContainer")
			or d:IsA("Accessory")
			or d:IsA("Clothing")
			or d:IsA("ShirtGraphic")
			or d:IsA("BodyColors")
		then
			d:Destroy() -- the creator builds every look; Roblox's default scripts are added on spawn as before
		end
	end
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.CanCollide = SOLID[p.Name] == true
		end
	end
	model.Name = "StarterCharacter"
	return model
end

function HeroBody.init()
	if Config.Creator.robloxBody then
		local body = HeroBody.robloxBody()
		if body then
			local old = StarterPlayer:FindFirstChild("StarterCharacter")
			if old then
				old:Destroy()
			end
			body.Parent = StarterPlayer
			StarterPlayer.LoadCharacterAppearance = false
			print("[HeroBody] every hero uses Roblox's own blocky R15 body")
			return
		end
	end
	local meshes = HeroBody.meshes()
	if not meshes then
		print("[HeroBody] Art.Hero is not imported yet: heroes keep the player's own avatar body")
		return
	end
	local old = StarterPlayer:FindFirstChild("StarterCharacter")
	if old then
		old:Destroy()
	end
	HeroBody.build(meshes).Parent = StarterPlayer
	-- the creator builds every look, so the avatar's own clothes, accessories and scales stay off
	StarterPlayer.LoadCharacterAppearance = false
	print(string.format("[HeroBody] every hero uses the R15 hero body (%d triangles)", RIG.triangles))
end

return HeroBody
