-- WeaponKit: builds a weapon on a hero (nate's hero creator plan, 2026-11-16: 36 weapons, each with 4 model
-- styles, a finish, main/trim/glow colours, a glow strength and the hero's emblem). The server builds it on
-- every hero so everyone sees it; the creator's preview builds the same model. Not pure (makes Instances).
-- Specs are small welded parts on body parts by role (the LookKit roles), written for the standard blocky
-- rig and scaled with the hero's build. A weapon points along the hand's -Z (forward from a hanging arm).
-- Flags on a spec: blade (takes the finish and the style's changes), glow (a glowing edge, shown by glow
-- strength), emblem (where the hero's symbol will show: drawn with the weapon step's emblem pass). Styles: 1 Classic as written, 2 broader blades,
-- 3 jagged teeth along the blades, 4 Energy (blades become glowing light).
-- Meshes (2026-11-18): art/blender/weapons.py draws all 36 in Blender (Config.WeaponArt; Shared.WeaponMesh picks
-- them per style). Once nate imports art/export/Weapons.fbx as ReplicatedStorage.Art.Weapons, a weapon whose
-- every mesh is there is welded from its meshes; any missing mesh and that weapon keeps the parts below.
-- Holds: the meshes are turned to sit in HeroAnim's weapon stances (blades up and forward, blasters and spears
-- along the arm, shields on the back of the forearm, the bow upright), and the parts below are turned by the same
-- hold (Config.WeaponArt[id].hold), so the fallback is held the same way.
-- PLACEHOLDER ART: the parts are blocks, balls and cylinders until the meshes are imported.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local WeaponMesh = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeaponMesh"))

local WeaponKit = {}

local V, CF = Vector3.new, CFrame.new
local function rz(d: number): CFrame
	return CFrame.Angles(0, 0, math.rad(d))
end
local function rx(d: number): CFrame
	return CFrame.Angles(math.rad(d), 0, 0)
end

type Spec = { [string]: any }

local function S(at: string, size: Vector3, cf: CFrame, color: string?, flags: Spec?): Spec
	local s: Spec = { at = at, size = size, cf = cf, color = color or "p" }
	for k, v in flags or {} do
		s[k] = v
	end
	return s
end

-- the same specs on the other hand (or forearm, foot), mirrored across x
local LEFT =
	{ rhand = "lhand", rlarm = "llarm", rfoot = "lfoot", lhand = "rhand", llarm = "rlarm", lfoot = "rfoot" }
local function mirror(list: { Spec }): { Spec }
	local out = {}
	for _, s in list do
		table.insert(out, s)
		local m = table.clone(s)
		m.at = LEFT[s.at] or s.at
		local p = s.cf.Position
		local rx_, ry, rz_ = (s.cf - p):ToEulerAnglesXYZ()
		m.cf = CF(-p.X, p.Y, p.Z) * CFrame.fromEulerAnglesXYZ(rx_, -ry, -rz_)
		table.insert(out, m)
	end
	return out
end

local function cat(...: { Spec }): { Spec }
	local out = {}
	for i = 1, select("#", ...) do
		for _, s in (select(i, ...)) do
			table.insert(out, s)
		end
	end
	return out
end

local G = -0.2 -- the grip line inside the hand (hands are 1 x 0.3 x 1)
local BLADE = { blade = true }
local METAL = { mat = Enum.Material.Metal }

local function swordish(at: string, len: number, width: number, gripLen: number, guard: number): { Spec }
	return {
		S(at, V(0.2, 0.2, gripLen), CF(0, G, 0), "s"),
		S(at, V(guard, 0.2, 0.22), CF(0, G, -gripLen / 2 - 0.1), "s", METAL),
		S(at, V(0.12, width, len), CF(0, G, -gripLen / 2 - 0.2 - len / 2), "p", BLADE),
		S(
			at,
			V(0.14, 0.05, len * 0.9),
			CF(0, G + width / 2, -gripLen / 2 - 0.2 - len / 2),
			"a",
			{ glow = true }
		),
	}
end
local function pistol(at: string): { Spec }
	return {
		S(at, V(0.2, 0.5, 0.25), CF(0, G - 0.15, 0.05), "s"),
		S(at, V(0.26, 0.36, 1.1), CF(0, G + 0.05, -0.4), "p", BLADE),
		S(at, V(0.18, 0.18, 0.08), CF(0, G + 0.08, -1.0), "a", { neon = true, glow = true }),
		S(at, V(0.04, 0.2, 0.5), CF(0.14, G + 0.05, -0.35), "a", { glow = true, emblem = true }),
	}
end
local function shield(width: number, height: number): { Spec }
	return {
		S(
			"llarm",
			V(0.15, height, width),
			CF(-0.62, 0, 0),
			"p",
			{ blade = true, shape = "Cylinder", emblem = true }
		),
		S(
			"llarm",
			V(0.18, height * 1.04, width * 1.04),
			CF(-0.6, 0, 0),
			"s",
			{ shape = "Cylinder", mat = Enum.Material.Metal }
		),
		S("llarm", V(0.3, 0.4, 0.4), CF(-0.75, 0, 0), "a", { shape = "Ball", glow = true }),
	}
end
local function wrap(at: string, color: string): Spec
	return S(at, V(1.04, 0.34, 1.04), CF(0, 0, 0), color, { mat = Enum.Material.Fabric })
end

-- Classic specs, by weapon id (Config.Weapons.list)
local SPECS: { [number]: { Spec } } = {
	[1] = mirror({ wrap("rhand", "s") }), -- Bare Fists: hand tape
	[2] = cat(
		mirror({ wrap("rhand", "white") }),
		mirror({ S("rlarm", V(1.04, 0.4, 1.04), CF(0, -0.25, 0), "white", { mat = Enum.Material.Fabric }) })
	),
	[3] = cat(
		mirror({
			S("rhand", V(1.3, 0.6, 1.3), CF(0, -0.05, 0), "p", { blade = true, mat = Enum.Material.Metal }),
		}),
		mirror({ S("rlarm", V(1.16, 0.6, 1.16), CF(0, -0.15, 0), "s", METAL) }),
		mirror({ S("rhand", V(1.0, 0.16, 0.14), CF(0, -0.05, -0.66), "a", { glow = true, neon = true }) })
	),
	[4] = mirror({
		S("rfoot", V(1.15, 0.45, 1.2), CF(0, 0.05, -0.05), "p", { blade = true, mat = Enum.Material.Metal }),
	}),
	[5] = swordish("rhand", 3.0, 0.45, 0.8, 0.9),
	[6] = cat(
		swordish("rhand", 3.4, 0.3, 1.0, 0.45),
		{ S("rhand", V(0.24, 0.5, 0.5), CF(0, G, -0.62), "s", { shape = "Cylinder" }) }
	),
	[7] = {
		S("rhand", V(0.18, 0.18, 2.2), CF(0, G, -0.7), "s"),
		S("rhand", V(0.12, 1.0, 0.7), CF(0, G - 0.35, -1.55), "p", BLADE),
		S("rhand", V(0.14, 0.08, 0.7), CF(0, G - 0.85, -1.55), "a", { glow = true }),
	},
	[8] = {
		S("rhand", V(0.2, 0.2, 2.0), CF(0, G, -0.6), "s"),
		S("rhand", V(0.8, 0.8, 0.8), CF(0, G, -1.85), "p", { blade = true, shape = "Ball" }),
		S("rhand", V(0.2, 1.1, 0.2), CF(0, G, -1.85), "s", METAL),
		S("rhand", V(1.1, 0.2, 0.2), CF(0, G, -1.85), "s", METAL),
	},
	[9] = {
		S("rhand", V(0.24, 0.24, 0.6), CF(0, G, 0), "s"),
		S("rhand", V(0.2, 0.2, 2.0), CF(0, G, -1.25), "p", BLADE),
		S("rhand", V(0.22, 0.22, 0.2), CF(0, G, -2.3), "a", { glow = true, neon = true }),
	},
	[10] = swordish("rhand", 1.2, 0.3, 0.6, 0.45),
	[11] = swordish("rhand", 4.6, 0.8, 1.4, 1.4),
	[12] = {
		S("rhand", V(0.22, 0.22, 4.2), CF(0, G, -1.4), "s"),
		S("rhand", V(0.14, 1.8, 1.2), CF(0, G - 0.7, -3.0), "p", BLADE),
		S("rhand", V(0.14, 1.0, 0.8), CF(0, G + 0.55, -3.0), "p", BLADE),
		S("rhand", V(0.16, 0.08, 1.2), CF(0, G - 1.6, -3.0), "a", { glow = true }),
	},
	[13] = {
		S("rhand", V(0.22, 0.22, 4.0), CF(0, G, -1.3), "s"),
		S("rhand", V(0.9, 1.6, 0.9), CF(0, G, -3.4), "p", { blade = true, emblem = true }),
		S("rhand", V(0.95, 0.12, 0.95), CF(0, G + 0.5, -3.4), "a", { glow = true }),
	},
	[14] = {
		S("rhand", V(0.18, 0.18, 6.0), CF(0, G, -1.8), "s"),
		S("rhand", V(0.1, 0.42, 1.0), CF(0, G, -5.3), "p", BLADE),
		S("rhand", V(0.3, 0.12, 0.12), CF(0, G, -4.8), "a", { glow = true }),
	},
	[15] = {
		S("rhand", V(0.18, 0.18, 5.5), CF(0, G, -1.6), "s"),
		S("rhand", V(0.1, 2.6, 0.5), CF(0, G - 1.2, -4.3) * rx(15), "p", BLADE),
		S("rhand", V(0.12, 2.4, 0.08), CF(0, G - 1.2, -4.05) * rx(15), "a", { glow = true }),
	},
	[16] = {
		S("rhand", V(0.2, 0.2, 6.5), CF(0, G, -1.2), "p", BLADE),
		S("rhand", V(0.24, 0.24, 0.4), CF(0, G, 2.0), "s", METAL),
		S("rhand", V(0.24, 0.24, 0.4), CF(0, G, -4.4), "s", METAL),
	},
	[17] = mirror(swordish("rhand", 2.2, 0.4, 0.6, 0.6)),
	[18] = mirror({
		S("rhand", V(0.06, 0.08, 1.0), CF(-0.3, -0.1, -0.9), "p", BLADE),
		S("rhand", V(0.06, 0.08, 1.1), CF(0, -0.1, -0.95), "p", BLADE),
		S("rhand", V(0.06, 0.08, 1.0), CF(0.3, -0.1, -0.9), "p", BLADE),
		S("rhand", V(1.0, 0.2, 0.3), CF(0, -0.1, -0.45), "s", METAL),
	}),
	[19] = mirror({
		S("rhand", V(0.16, 0.16, 0.6), CF(0, G, 0), "s"),
		S("rhand", V(0.08, 0.08, 1.6), CF(0, G, -1.1), "p", BLADE),
		S("rhand", V(0.06, 0.06, 0.6), CF(0.22, G, -0.55) * CFrame.Angles(0, math.rad(-30), 0), "p", BLADE),
		S("rhand", V(0.06, 0.06, 0.6), CF(-0.22, G, -0.55) * CFrame.Angles(0, math.rad(30), 0), "p", BLADE),
	}),
	[20] = mirror({
		S("rhand", V(0.16, 0.16, 0.5), CF(0, G, 0), "s"),
		S("rhand", V(0.22, 1.9, 0.22), CF(0, 0.75, 0.32), "p", BLADE),
	}),
	[21] = {
		S("rhand", V(0.2, 0.2, 1.0), CF(0, G, -0.4), "p", BLADE),
		S("rhand", V(0.05, 0.05, 0.3), CF(0, G, -1.05), "s", METAL),
		S("rhand", V(0.2, 1.0, 0.2), CF(0, G - 0.55, -1.2), "p", BLADE),
	},
	[22] = shield(2.2, 2.2),
	[23] = {
		S("llarm", V(0.15, 3.4, 2.0), CF(-0.62, -0.3, 0), "p", { blade = true, emblem = true }),
		S("llarm", V(0.18, 3.5, 0.12), CF(-0.6, -0.3, -1.0), "s", METAL),
		S("llarm", V(0.18, 3.5, 0.12), CF(-0.6, -0.3, 1.0), "s", METAL),
		S("llarm", V(0.2, 0.12, 2.0), CF(-0.66, 0.6, 0), "a", { glow = true }),
	},
	[24] = cat(shield(1.7, 1.7), swordish("rhand", 2.6, 0.4, 0.7, 0.8)),
	[25] = pistol("rhand"),
	[26] = cat(pistol("rhand"), pistol("lhand")),
	[27] = {
		S("rhand", V(0.3, 0.45, 2.6), CF(0, G + 0.05, -0.9), "p", BLADE),
		S("rhand", V(0.2, 0.55, 0.3), CF(0, G - 0.3, 0.1), "s"),
		S("rhand", V(0.15, 0.15, 0.6), CF(0, G + 0.35, -0.8), "s", METAL),
		S("rhand", V(0.22, 0.22, 0.08), CF(0, G + 0.05, -2.24), "a", { neon = true, glow = true }),
	},
	[28] = {
		S("lhand", V(0.1, 4.0, 0.2), CF(0, G, -0.2), "p", BLADE),
		S("lhand", V(0.02, 3.9, 0.02), CF(0, G, 0.45), "white"),
		S("lhand", V(0.2, 0.6, 0.3), CF(0, G, -0.2), "s"),
	},
	[29] = {
		S("rhand", V(0.25, 0.3, 2.0), CF(0, G, -0.7), "s"),
		S("rhand", V(2.4, 0.12, 0.2), CF(0, G + 0.1, -1.5), "p", BLADE),
		S("rhand", V(0.12, 0.12, 0.8), CF(0, G + 0.2, -1.2), "a", { glow = true }),
	},
	[30] = {
		S(
			"rlarm",
			V(1.0, 1.8, 1.0),
			CF(0, -0.5, 0),
			"p",
			{ blade = true, mat = Enum.Material.Metal, emblem = true }
		),
		S("rlarm", V(0.7, 0.12, 0.7), CF(0, -1.42, 0), "a", { neon = true, glow = true }),
		S("rlarm", V(1.1, 0.2, 1.1), CF(0, 0.25, 0), "s", METAL),
	},
	[31] = {
		S("rhand", V(0.7, 0.06, 0.16), CF(0, G, -0.45) * rz(45), "p", BLADE),
		S("rhand", V(0.7, 0.06, 0.16), CF(0, G, -0.45) * rz(-45), "p", BLADE),
		S("rhand", V(0.16, 0.08, 0.16), CF(0, G, -0.45), "a", { glow = true }),
	},
	[32] = {
		S("rhand", V(0.2, 0.2, 0.8), CF(0, G, -0.2), "s"),
		S("rhand", V(0.1, 0.1, 0.5), CF(0, G - 0.2, -0.75) * rx(30), "p", BLADE),
		S("rhand", V(0.1, 0.5, 0.1), CF(0, G - 0.65, -0.95), "p", BLADE),
		S("rhand", V(0.1, 0.5, 0.1), CF(0, G - 1.15, -0.95), "p", BLADE),
		S("rhand", V(0.1, 0.5, 0.1), CF(0, G - 1.65, -0.95), "p", BLADE),
	},
	[33] = {
		S("rhand", V(1.6, 0.06, 1.2), CF(0, G, -0.9), "p", { blade = true, emblem = true }),
		S("rhand", V(1.62, 0.07, 0.08), CF(0, G, -1.5), "a", { glow = true }),
		S("rhand", V(0.16, 0.12, 0.5), CF(0, G, -0.15), "s"),
	},
	[34] = {
		S("rhand", V(0.3, 0.7, 0.7), CF(0, G - 1.1, -0.2), "p", { blade = true, shape = "Cylinder" }),
		S("rhand", V(0.32, 0.3, 0.3), CF(0, G - 1.1, -0.2), "a", { shape = "Cylinder", glow = true }),
		S("rhand", V(0.02, 0.9, 0.02), CF(0, G - 0.5, -0.2), "white"),
	},
	[35] = {
		S("rhand", V(0.3, 0.6, 0.6), CF(0, G, -0.1), "s", { shape = "Cylinder" }),
		S("rhand", V(0.04, 1.0, 0.04), CF(0, G - 0.6, -0.2), "white"),
		S("rhand", V(0.12, 0.6, 0.12), CF(0, G - 1.3, -0.2), "p", BLADE),
	},
	[36] = {
		S("rhand", V(0.14, 0.12, 1.0), CF(0.25, G, -0.5) * CFrame.Angles(0, math.rad(-35), 0), "p", BLADE),
		S("rhand", V(0.14, 0.12, 1.0), CF(-0.25, G, -0.5) * CFrame.Angles(0, math.rad(35), 0), "p", BLADE),
		S("rhand", V(0.16, 0.14, 0.16), CF(0, G, -0.9), "a", { glow = true }),
	},
}
WeaponKit.SPECS = SPECS

-- A weapon look's specs with its style applied (1 Classic, 2 broad, 3 jagged, 4 energy)
function WeaponKit.specs(id: number, style: number): { Spec }
	local out = {}
	for _, s in SPECS[id] or {} do
		local t = table.clone(s)
		if s.blade and style == 2 then
			t.size = Vector3.new(s.size.X * 1.25, s.size.Y * 1.35, s.size.Z)
		elseif s.blade and style == 4 then
			t.energy = true
		end
		table.insert(out, t)
		if s.blade and style == 3 and s.size.Z > 0.9 then
			-- three teeth along the blade's top edge
			for k = -1, 1 do
				local z = k * s.size.Z * 0.3
				table.insert(out, {
					at = s.at,
					size = Vector3.new(s.size.X * 0.9, 0.18, 0.18),
					cf = s.cf * CFrame.new(0, s.size.Y / 2 + 0.06, z) * CFrame.Angles(math.rad(45), 0, 0),
					color = s.color,
					blade = true,
				})
			end
		end
	end
	return out
end

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

-- The colours a weapon look draws with: main (p), trim (s), glow (a); 0 = the finish's own or the hero's
function WeaponKit.colors(look: any, heroColors: { [string]: Color3 }): { [string]: Color3 }
	local W = Config.Weapons
	local pal = Config.Creator.palette
	local finish = W.finishes[look.finish] or W.finishes[1]
	local steel = if finish.tint then rgb(finish.tint) else Color3.fromRGB(190, 195, 205)
	return {
		p = if pal[look.main] then rgb(pal[look.main]) else steel,
		s = if pal[look.trim] then rgb(pal[look.trim]) else Color3.fromRGB(60, 50, 45),
		a = if pal[look.glow] then rgb(pal[look.glow]) else (heroColors.a or Color3.fromRGB(255, 210, 70)),
		white = Color3.fromRGB(240, 240, 245),
		dark = Color3.fromRGB(34, 38, 52),
	}
end

-- A spec turned by its weapon's hold on its body part (about the grip line, or a shield's forearm centre)
local function held(id: number, s: Spec): Spec
	local rx, ry, pivot = WeaponMesh.hold(Config, id, s.at)
	if not (rx and ry and pivot) then
		return s
	end
	local t = table.clone(s)
	local pv = CF(pivot[1], pivot[2], pivot[3])
	t.cf = pv * CFrame.Angles(math.rad(rx), math.rad(ry), 0) * pv:Inverse() * s.cf
	return t
end
WeaponKit.held = held

-- the standard blocky rig's part sizes (the fit's boxes are on these; a bigger body scales them)
local RIG_SIZE: { [string]: Vector3 } = {}
for name, def in Config.HeroRig.parts do
	RIG_SIZE[name] = V(def.size[1], def.size[2], def.size[3])
end

-- The imported weapon meshes (ReplicatedStorage.Art.Weapons), or nil
local function library(): Instance?
	local art = ReplicatedStorage:FindFirstChild("Art")
	return art and art:FindFirstChild("Weapons")
end

local function meshIn(lib: Instance, name: string): MeshPart?
	local found = lib:FindFirstChild(name, true)
	return if found and found:IsA("MeshPart") then found else nil
end

-- Does this weapon draw from its meshes (every one imported)?
function WeaponKit.meshed(id: number): boolean
	local lib = library()
	return lib ~= nil
		and WeaponMesh.ready(Config, id, function(n)
			return meshIn(lib :: Instance, n) ~= nil
		end)
end

-- The weapon from its meshes, welded to the body parts (bodyPart: LookKit's role to body part); false when a
-- mesh or a body part is missing (then nothing is made and the parts are built instead)
local function buildMeshes(
	char: Model,
	folder: Instance,
	look: any,
	colors: { [string]: Color3 },
	bodyPart: (Model, string) -> (BasePart?, CFrame)
): boolean
	local lib = library()
	if not lib or not WeaponKit.meshed(look.id) then
		return false
	end
	local W = Config.Weapons
	local finish = W.finishes[look.finish] or W.finishes[1]
	local finishMat = (Enum.Material :: any)[finish.mat] or Enum.Material.Metal
	local glow = math.clamp(look.glowLevel or 0, 0, W.glowLevels)
	local mastered = look.mastered == true
	local list = WeaponMesh.pieces(Config, look.id, look.style or 1)
	local parts = {}
	for i, p in list do
		local part, offset = bodyPart(char, p.at)
		if not part then
			return false
		end
		parts[i] = { part, offset }
	end
	for i, p in list do
		local src = meshIn(lib, p.mesh)
		if not src then
			return false
		end
		local neon, alpha, color = p.neon, 0, colors[p.role] or colors.p
		local mat = if p.mat then (Enum.Material :: any)[p.mat] else Enum.Material.SmoothPlastic
		if p.glow then
			if glow == 0 and not mastered then
				continue -- a glow piece shows only with a glow strength (or the Mastered glow)
			end
			neon, color = true, colors.a
			alpha = if mastered then 0 else 0.6 - 0.2 * glow
		elseif p.energy or (p.blade and finish.mat == "Neon") then
			neon, color, alpha = true, colors.a, 0.15
		elseif p.blade then
			mat = finishMat
		end
		if neon then
			color = colors.a
		end
		local part, offset = parts[i][1], parts[i][2]
		local ref = RIG_SIZE[part.Name]
		local f = if ref then part.Size / ref else Vector3.one
		local m = src:Clone()
		for _, c in m:GetChildren() do
			c:Destroy()
		end
		m.Name = "Weapon"
		m:SetAttribute("Piece", p.mesh) -- which mesh it is (TetherFx swings the line weapons' lines and tips)
		m.Size = V(p.size[1], p.size[2], p.size[3]) * f
		m.Color = color
		m.Material = if neon then Enum.Material.Neon else mat
		m.Transparency = alpha
		m.Anchored = false
		m.Massless = true
		m.CanCollide = false
		m.CanTouch = false
		m.CanQuery = false
		m.CastShadow = false
		m.CFrame = part.CFrame * offset * CF(V(p.offset[1], p.offset[2], p.offset[3]) * f)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = part
		weld.Part1 = m
		weld.Parent = m
		m.Parent = folder
	end
	return true
end

-- Build the weapon: from its meshes once imported (buildMeshes), else its specs as parts with LookKit's maker:
-- make(char, folder, name, spec, colors, mat). Either way the folder carries the weapon's id (WeaponId: the
-- stance HeroAnimator poses the arms in) and whether meshes drew it (Meshed).
function WeaponKit.build(
	char: Model,
	folder: Instance,
	look: any,
	heroColors: { [string]: Color3 },
	make: (Model, Instance, string, any, any, Enum.Material?) -> (),
	bodyPart: ((Model, string) -> (BasePart?, CFrame))?
)
	local W = Config.Weapons
	local finish = W.finishes[look.finish] or W.finishes[1]
	local finishMat = (Enum.Material :: any)[finish.mat] or Enum.Material.Metal
	local colors = WeaponKit.colors(look, heroColors)
	local glow = math.clamp(look.glowLevel or 0, 0, W.glowLevels)
	local mastered = look.mastered == true
	folder:SetAttribute("WeaponId", look.id)
	local meshed = bodyPart ~= nil and buildMeshes(char, folder, look, colors, bodyPart :: any)
	folder:SetAttribute("Meshed", meshed)
	if meshed then
		return
	end
	for _, raw in WeaponKit.specs(look.id, look.style or 1) do
		local s = held(look.id, raw)
		local spec = s
		if s.glow then
			if glow == 0 and not mastered then
				continue
			end
			spec = table.clone(s)
			spec.neon = true
			spec.color = "a"
			spec.alpha = if mastered then 0 else 0.6 - 0.2 * glow
		elseif s.energy or (s.blade and finish.mat == "Neon") then
			spec = table.clone(s)
			spec.neon = true
			spec.color = "a"
			spec.alpha = 0.15
		end
		make(char, folder, "Weapon", spec, colors, if s.blade and not spec.neon then finishMat else nil)
	end
end

return WeaponKit
