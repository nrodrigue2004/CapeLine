-- bodies.luau (fix-respawn, 2026-11-19; nate's playtest: "Clothes dont fit on certain body sizes", "i died and
-- respawn and my gear didnt really fit me"): every gender x build x height (2 x 4 x 5 = 40 bodies) dressed by the
-- GAME's own code from the built place, for art/blender/fit_bodies.py. On Roblox's own blocky R15 body
-- (Config.RobloxRig: 15 parts, their attachments and joints) it runs LookKit.build (the Body step's shapeBody,
-- then every creator piece and the weapon through BodyFit, as LookService runs it on the server) and the server's
-- own LookService.apply for the gear styles, then stands the shaped body up by its joints (each part where its
-- Motor6D's C0 and C1 put it, feet on the ground) and moves every welded piece with its part. It writes each body
-- part (which mesh: Roblox's own, or the body set's torso, LookKit.wearBodySet), each piece's mesh, set, CFrame,
-- size and colour, and the outfit (the classic Shirt and Pants kits and their tints).
-- Run from the repo root: ~/tools/lune run art/fit/bodies.luau build/Capeline.rbxl build/fit/bodies.json
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local WeaponSim = require("../../tests/weaponsim")

local placePath, outPath = process.args[1], process.args[2]
local place = roblox.deserializePlace(fs.readFile(placePath))
local sim = WeaponSim.new(place)
local CFrame, Vector3, Instance = roblox.CFrame, roblox.Vector3, roblox.Instance
local Config = sim:module("Config")
local BodyShape = sim:module("Shared.BodyShape")
local MeshFix = sim:module("Shared.MeshFix")
local CreatorRules = sim:module("Shared.CreatorRules")
local LookKit = sim:module("Shared.LookKit")
-- each clone remembers its source mesh (LookKit names a worn piece for its slot; the render needs the mesh)
local clone = MeshFix.clone
MeshFix.clone = function(src)
	local p = clone(src)
	p:SetAttribute("SrcMesh", src.Name)
	return p
end
local server = place:GetService("ServerScriptService")
local LookService = sim:require(server.Server.Services.LookService)
LookService.guardShape = function() end -- (property signals do not exist here; the guard is the server's)

-- R15 joints: child part -> parent part and joint name
local JOINT = {
	UpperTorso = { "LowerTorso", "Waist" },
	Head = { "UpperTorso", "Neck" },
	LeftUpperArm = { "UpperTorso", "LeftShoulder" },
	LeftLowerArm = { "LeftUpperArm", "LeftElbow" },
	LeftHand = { "LeftLowerArm", "LeftWrist" },
	RightUpperArm = { "UpperTorso", "RightShoulder" },
	RightLowerArm = { "RightUpperArm", "RightElbow" },
	RightHand = { "RightLowerArm", "RightWrist" },
	LeftUpperLeg = { "LowerTorso", "LeftHip" },
	LeftLowerLeg = { "LeftUpperLeg", "LeftKnee" },
	LeftFoot = { "LeftLowerLeg", "LeftAnkle" },
	RightUpperLeg = { "LowerTorso", "RightHip" },
	RightLowerLeg = { "RightUpperLeg", "RightKnee" },
	RightFoot = { "RightLowerLeg", "RightAnkle" },
}
local ORDER = {
	"UpperTorso",
	"Head",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
}

local function body(): any
	local char = sim:body()
	for child, j in JOINT do
		local p0, p1 = char:FindFirstChild(j[1]), char:FindFirstChild(child)
		local m = Instance.new("Motor6D")
		m.Name = j[2]
		m.Part0, m.Part1 = p0, p1
		local a0 = p0:FindFirstChild(j[2] .. "RigAttachment")
		local a1 = p1:FindFirstChild(j[2] .. "RigAttachment")
		m.C0 = if a0 then a0.CFrame else CFrame.new()
		m.C1 = if a1 then a1.CFrame else CFrame.new()
		m.Parent = p1
	end
	return char
end

-- stand the body up by its joints (LowerTorso fixed), feet on y = 0, pieces moved with their welded part
local function stand(char: any, folders: { any })
	local rel = {}
	for _, f in folders do
		for _, d in f:GetDescendants() do
			if d:IsA("BasePart") then
				local w = d:FindFirstChildOfClass("WeldConstraint")
				local p0 = w and w.Part0
				if p0 then
					table.insert(rel, { p = d, part = p0, off = p0.CFrame:Inverse() * d.CFrame })
				end
			end
		end
	end
	local lower = char:FindFirstChild("LowerTorso")
	for _, name in ORDER do
		local p1 = char:FindFirstChild(name)
		local m = p1:FindFirstChildOfClass("Motor6D")
		-- (C0 and C1 are the two RigAttachments, as shapeBody sets them; Lune keeps an Attachment's CFrame apart
		-- from its Position, so the Positions are read)
		local a0 = m.Part0:FindFirstChild(m.Name .. "RigAttachment")
		local a1 = p1:FindFirstChild(m.Name .. "RigAttachment")
		p1.CFrame = m.Part0.CFrame * CFrame.new(a0.Position) * CFrame.new(a1.Position):Inverse()
	end
	local low = math.huge
	for _, n in { "LeftFoot", "RightFoot" } do
		local f = char:FindFirstChild(n)
		low = math.min(low, f.CFrame.Position.Y - f.Size.Y / 2)
	end
	local shift = CFrame.new(0, -low, 0)
	for _, p in char:GetChildren() do
		if p:IsA("BasePart") then
			p.CFrame = shift * p.CFrame
		end
	end
	for _, r in rel do
		r.p.CFrame = r.part.CFrame * r.off
	end
	local _ = lower
end

local function comps(cf: any): { number }
	return { cf:GetComponents() }
end
local function rgb(c: any): { number }
	return { c.R, c.G, c.B }
end

-- the outfits: a classic shirt and pants only, then two gear sets (creator pieces, gear styles, a weapon)
local function pieceIndex(tab: string, kit: string): number
	for i = 1, 120 do
		local p = CreatorRules.piece(Config, tab, i)
		if p and p.kit == kit then
			return i
		end
	end
	return 0
end
local OUTFITS = {
	{
		name = "Clothes",
		pieces = { shirt = "Hoodie", pants = "Cargo" },
	},
	{
		name = "Set A",
		pieces = {
			shirt = "TrackTop",
			pants = "Joggers",
			head = "visor",
			hands = "gauntlet",
			feet = "boot",
			belt = "utility",
			shoulders = "pads",
			back = "cape:classic",
		},
		styles = { 0, 0, 0, 0, 0, 0 },
		weapon = 1,
	},
	{
		name = "Set B",
		pieces = {
			shirt = "ZipJacket",
			pants = "Jeans",
			hat = "goggles",
			hands = "glove",
			feet = "armored",
			arms = "bracers",
			neck = "chain",
			backpack = "jetpack",
		},
		gear = true,
		weapon = 11,
	},
}

local out = { bodies = {}, outfits = {} }
local B = Config.Creator.body
for oi, outfit in OUTFITS do
	table.insert(out.outfits, outfit.name)
	for g = 1, #B.genders do
		for b = 1, #B.builds do
			for h = 1, #B.heights do
				local look = CreatorRules.defaultLook(Config)
				look.gender, look.build, look.height = g, b, h
				look.pieces = { visage = 7, hair = 42 }
				for tab, kit in outfit.pieces do
					look.pieces[tab] = pieceIndex(tab, kit)
				end
				local char = body()
				local weapon = nil
				if outfit.weapon then
					weapon = {
						id = outfit.weapon,
						style = 1,
						finish = 1,
						main = 1,
						trim = 2,
						glow = 3,
						glowLevel = 1,
					}
				end
				local ok, err = pcall(LookKit.build, char, look, weapon)
				if not ok then
					print("LookKit.build", outfit.name, g, b, h, err)
				end
				pcall(LookKit.showWeapon, char, true)
				if outfit.gear then
					-- the server's gear styles over the look (LookService.apply: one style id a slot)
					local styles = {}
					for i, slot in Config.Gear.slotOrder do
						local id = 0
						for sid, row in Config.Gear.styles or {} do
							if row.slot == slot and row.shape == "set" then
								id = if type(sid) == "number" then sid else 0
								break
							end
						end
						styles[i] = id
					end
					local okG, errG = pcall(LookService.apply, { Character = char }, styles, nil, nil, false)
					if not okG then
						print("LookService.apply", errG)
					end
				end
				local folders = {}
				for _, n in { "HeroLook", "GearLook" } do
					local f = char:FindFirstChild(n)
					if f then
						table.insert(folders, f)
					end
				end
				stand(char, folders)
				local key = BodyShape.setKey(Config, look)
				local row =
					{ gender = g, build = b, height = h, set = key, outfit = oi, parts = {}, pieces = {} }
				for _, p in char:GetChildren() do
					if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
						local torso = (p.Name == "UpperTorso" or p.Name == "LowerTorso")
							and LookKit.setMesh(key, p.Name) ~= nil
						table.insert(row.parts, {
							name = p.Name,
							mesh = if torso then key .. "_" .. p.Name else nil,
							cf = comps(p.CFrame),
							size = { p.Size.X, p.Size.Y, p.Size.Z },
							color = rgb(p.Color),
						})
					end
				end
				for _, c in char:GetChildren() do
					if c:IsA("Shirt") then
						row.shirt = { kit = outfit.pieces.shirt, color = rgb(c.Color3) }
					elseif c:IsA("Pants") then
						row.pants = { kit = outfit.pieces.pants, color = rgb(c.Color3) }
					end
				end
				for _, f in folders do
					for _, d in f:GetDescendants() do
						if d:IsA("MeshPart") and d.Transparency < 1 then
							table.insert(row.pieces, {
								name = d:GetAttribute("SrcMesh") or d.Name,
								set = MeshFix.setOf(d),
								cf = comps(d.CFrame),
								size = { d.Size.X, d.Size.Y, d.Size.Z },
								color = rgb(d.Color),
								neon = d.Material == roblox.Enum.Material.Neon,
								maps = d:FindFirstChildOfClass("SurfaceAppearance") ~= nil,
							})
						end
					end
				end
				table.insert(out.bodies, row)
				char:Destroy()
			end
		end
	end
end
fs.writeDir("build/fit")
fs.writeFile(outPath, serde.encode("json", out))
print("wrote", outPath, #out.bodies, "bodies")
