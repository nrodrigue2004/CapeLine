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
local BodyFit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BodyFit"))
local MeshFix = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MeshFix"))
local TetherMath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TetherMath"))

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

local G = -0.15 -- the grip line: the hand's grip attachment (hands are 1 x 0.3 x 1; pt-fit: was -0.2, under the fist)
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

-- the fit's boxes are on Config.HeroRig's classic blocks; Shared.BodyFit maps them onto the body worn (Roblox's own
-- blocky body: a shield on the forearm keeps its place and size instead of stretching x1.24 down the arm)
local function fitFrame(part: BasePart): (Vector3, Vector3)
	local s = part.Size
	local b = part:GetAttribute("BaseSize") -- a body the Body step shaped: the rig is told from its first size
	local base = if typeof(b) == "Vector3" then { b.X, b.Y, b.Z } else nil
	local shift, f = BodyFit.frame(Config, part.Name, { s.X, s.Y, s.Z }, base)
	return V(shift[1], shift[2], shift[3]), V(f[1], f[2], f[3])
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
	local turn = MeshFix.turn("Weapons")
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
		local shift, f = fitFrame(part)
		local m = src:Clone()
		for _, c in m:GetChildren() do
			c:Destroy()
		end
		m.Name = "Weapon"
		m:SetAttribute("Piece", p.mesh) -- which mesh it is (TetherFx swings the line weapons' lines and tips)
		if p.emblem then
			m:SetAttribute("Emblem", true) -- the hero's symbol shows here (LookKit, WeaponKit.emblemPiece)
		end
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
		-- the box's centre on the body part, then the import's own turn (Shared.MeshFix: Open Cloud turned every weapon
		-- mesh 180 degrees about y inside its box; unturned, diagonal blades and hafts cross and float off the grip)
		m.CFrame = part.CFrame * offset * CF(shift + V(p.offset[1], p.offset[2], p.offset[3]) * f) * turn
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = part
		weld.Part1 = m
		weld.Parent = m
		m.Parent = folder
	end
	return true
end

-- Swing trails (list-combat 2026-11-20; Config.Weapons.swingTrail): on each hand (and foot) that holds a piece, a
-- Trail between two Attachments along the outer part of the piece reaching farthest from that body part (the
-- blade's last two thirds; across the knuckles or the boot when nothing reaches past the fist), named SwingTrail,
-- off until Fx.SwingTrailFx lights it during a weapon move. Its look is the weapon look's trail (0: the thin base
-- slash in the look's colour). Ranged families draw none; the line weapons trail from the grip (their tips are
-- drawn by Fx.TetherFx). Returns the trails made.
local TRAIL_ROOTS = { RightHand = true, LeftHand = true, RightFoot = true, LeftFoot = true }
local AXES = { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }

local function trailColor(c: any, colors: { [string]: Color3 }, lookColor: Color3): Color3
	if type(c) == "table" then
		return Color3.fromRGB(c[1], c[2], c[3])
	elseif c == "white" then
		return Color3.fromRGB(250, 250, 255)
	elseif c == "look" then
		return lookColor
	end
	return colors[c] or colors.a
end

function WeaponKit.trails(_char: Model, folder: Instance, look: any, colors: { [string]: Color3 }): { Trail }
	local W = Config.Weapons
	local ST = W.swingTrail
	local w = W.list[look.id]
	local made: { Trail } = {}
	if not (ST and w and ST.families[w[2]]) then
		return made
	end
	local row = if (look.trail or 0) > 0 then ST.looks[look.trail] else nil
	local t = row or ST.base
	local wl = Config.Fx.weaponLooks
	local lookName = wl and ((wl.weapon and wl.weapon[look.id]) or (wl.family and wl.family[w[2]]))
	local lc = lookName and wl.looks[lookName] and wl.looks[lookName].color
	local lookColor = if lc then Color3.fromRGB(lc[1], lc[2], lc[3]) else colors.a
	local tether = TetherMath.SPECS[look.id] ~= nil
	-- the farthest-reaching piece on each root: (body part, piece, tip and base in the piece's frame)
	local best: { [BasePart]: { piece: BasePart, reach: number, tip: Vector3, base: Vector3, long: number } } =
		{}
	for _, p in folder:GetChildren() do
		local weld = p:FindFirstChildOfClass("WeldConstraint")
		local root = weld and weld.Part0
		if
			p:IsA("BasePart")
			and root
			and (TRAIL_ROOTS[root.Name] or (w[2] == "shield" and root.Name == "LeftLowerArm"))
			and p.Material ~= Enum.Material.Neon
		then
			local size = p.Size
			local k = if size.X >= size.Y and size.X >= size.Z then 1 elseif size.Y >= size.Z then 2 else 3
			local half = AXES[k] * (({ size.X, size.Y, size.Z })[k] / 2)
			local a, b = p.CFrame:PointToWorldSpace(half), p.CFrame:PointToWorldSpace(-half)
			local rp = root.CFrame.Position
			local ra, rb = (a - rp).Magnitude, (b - rp).Magnitude
			local tipL = if ra >= rb then half else -half
			local reach = math.max(ra, rb)
			local cur = best[root.Name]
			local long = ({ size.X, size.Y, size.Z })[k]
			-- small studs and caps never win over a real blade or face
			local score = if long >= 0.6 then reach else reach - 100
			if not cur or score > cur.score then
				best[root.Name] =
					{ root = root, piece = p, reach = reach, score = score, tip = tipL, base = -tipL * 0.33 }
			end
		end
	end
	for _, b in best do
		local root = b.root
		local holder: BasePart, p0: Vector3, p1: Vector3
		if (b.reach < 1.6 or tether) and TRAIL_ROOTS[root.Name] then
			-- nothing past the fist: across the knuckles (or the boot's toe), a short wide slash
			holder = root
			local s = root.Size
			local fwd = if string.find(root.Name, "Foot")
				then Vector3.new(0, 0, -s.Z * 0.45)
				else Vector3.new(0, -s.Y * 0.5, 0)
			p0, p1 = fwd + Vector3.new(s.X * 0.45, 0, 0), fwd - Vector3.new(s.X * 0.45, 0, 0)
		else
			holder, p0, p1 = b.piece, b.base, b.tip
		end
		local a0 = Instance.new("Attachment")
		a0.Name = "SwingTrailA"
		a0.Position = p0
		a0.Parent = holder
		local a1 = Instance.new("Attachment")
		a1.Name = "SwingTrailB"
		a1.Position = p1
		a1.Parent = holder
		local tr = Instance.new("Trail")
		tr.Name = "SwingTrail"
		tr.Attachment0 = a0
		tr.Attachment1 = a1
		tr.Enabled = false
		tr.FaceCamera = false
		tr.Lifetime = t.life
		tr.MinLength = 0.05
		tr.LightEmission = t.light
		tr.LightInfluence = 1 - t.light
		tr.WidthScale = NumberSequence.new(t.width or 1, 0.2)
		tr.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, t.alpha),
			NumberSequenceKeypoint.new(0.6, math.min(1, t.alpha + 0.35)),
			NumberSequenceKeypoint.new(1, 1),
		})
		tr.Color = ColorSequence.new(trailColor(t.c0, colors, lookColor), trailColor(t.c1, colors, lookColor))
		local tf = Config.Creator.trailFx
		local tex = row and tf and tf.on == true and tf.kits[row.kit]
		if tex and tex.id ~= 0 then
			tr.Texture = "rbxassetid://" .. tostring(tex.id)
			tr.TextureMode = if tex.mode == "Wrap" then Enum.TextureMode.Wrap else Enum.TextureMode.Stretch
			tr.TextureLength = tex.length or 1
		end
		tr:SetAttribute("Trail", look.trail or 0)
		tr.Parent = holder
		-- a trail on the body (fists) is cleared with the weapon: the folder keeps a reference
		if holder == root then
			for _, inst in { a0, a1, tr } do
				local ref = Instance.new("ObjectValue")
				ref.Name = "TrailRef"
				ref.Value = inst
				ref.Parent = folder
			end
		end
		table.insert(made, tr)
	end
	return made
end

-- Where the hero's emblem goes on a built weapon (list-combat 2026-11-20): the piece the art marks (emblem), else the
-- broadest solid piece (a blade's flat, a shield's face, a gauntlet's back). Returns the piece, the plate's CFrame
-- (its z through the piece's thinnest side) and the plate's size (a square on the face, thickness just past it).
function WeaponKit.emblemPiece(folder: Instance): (BasePart?, CFrame?, Vector3?)
	local pick: BasePart? = nil
	local score = -1
	for _, p in folder:GetChildren() do
		if
			p:IsA("BasePart")
			and p.Name == "Weapon"
			and p.Material ~= Enum.Material.Neon
			and p.Transparency < 0.5
		then
			local s = p.Size
			local dims = { s.X, s.Y, s.Z }
			table.sort(dims)
			local area = dims[2] * dims[3]
			local sc = (if p:GetAttribute("Emblem") == true then 1000 else 0) + area
			if dims[2] >= 0.3 and sc > score then
				pick, score = p, sc
			end
		end
	end
	if not pick then
		return nil, nil, nil
	end
	local s = pick.Size
	local k = if s.X <= s.Y and s.X <= s.Z then 1 elseif s.Y <= s.Z then 2 else 3
	local thin = ({ s.X, s.Y, s.Z })[k]
	local a, b = ({ s.Y, s.X, s.X })[k], ({ s.Z, s.Z, s.Y })[k]
	local side = math.clamp(math.min(a, b) * 0.62, 0.25, 1.4)
	-- turn the plate so its z is the thin axis
	local turn = if k == 1
		then CFrame.Angles(0, math.rad(90), 0)
		elseif k == 2 then CFrame.Angles(math.rad(90), 0, 0)
		else CFrame.identity
	return pick, pick.CFrame * turn, Vector3.new(side, side, thin + 0.04)
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
	folder:SetAttribute("Trail", look.trail or 0)
	if meshed then
		WeaponKit.trails(char, folder, look, colors)
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
	WeaponKit.trails(char, folder, look, colors)
end

return WeaponKit
