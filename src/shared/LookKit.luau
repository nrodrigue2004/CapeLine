-- LookKit: builds a creator look on a character (spec: Hero creator "Pieces are accessories on a standard
-- Roblox rig"). The server builds it on every hero so everyone sees it (LookService); the creator screen
-- builds the same look on its preview dummy. Not pure (makes Instances), so Lune only checks it exists.
-- * strip(char): the avatar's own accessories and clothes come off (a standard rig), the face stays.
-- * build(char, folder, look): body colours from the suit, then every piece as small welded parts,
--   the emblem as a glyph on the chest, the aura as one emitter, the flight trail as one Trail.
-- Parts are massless and never collide, touch or block raycasts. Works on R15 and R6 bodies.
-- PLACEHOLDER ART: blocks, wedges, balls and cylinders until the accessory meshes, generated emblem
-- textures and cape sway (M11) replace them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CreatorRules = require(Shared:WaitForChild("CreatorRules"))
local BodyShape = require(Shared:WaitForChild("BodyShape"))
local PieceKits = require(Shared:WaitForChild("PieceKits"))

local LookKit = {}

local C = Config.Creator

-- body part by role, R15 first, R6 second, with an offset for R6 (one part per limb)
local ATTACH = {
	head = { "Head", "Head", CFrame.new() },
	torso = { "UpperTorso", "Torso", CFrame.new(0, 0.3, 0) },
	waist = { "LowerTorso", "Torso", CFrame.new(0, -0.8, 0) },
	luarm = { "LeftUpperArm", "Left Arm", CFrame.new(0, 0.4, 0) },
	ruarm = { "RightUpperArm", "Right Arm", CFrame.new(0, 0.4, 0) },
	llarm = { "LeftLowerArm", "Left Arm", CFrame.new(0, -0.3, 0) },
	rlarm = { "RightLowerArm", "Right Arm", CFrame.new(0, -0.3, 0) },
	lhand = { "LeftHand", "Left Arm", CFrame.new(0, -0.8, 0) },
	rhand = { "RightHand", "Right Arm", CFrame.new(0, -0.8, 0) },
	lthigh = { "LeftUpperLeg", "Left Leg", CFrame.new(0, 0.4, 0) },
	rthigh = { "RightUpperLeg", "Right Leg", CFrame.new(0, 0.4, 0) },
	lshin = { "LeftLowerLeg", "Left Leg", CFrame.new(0, -0.3, 0) },
	rshin = { "RightLowerLeg", "Right Leg", CFrame.new(0, -0.3, 0) },
	lfoot = { "LeftFoot", "Left Leg", CFrame.new(0, -0.8, 0) },
	rfoot = { "RightFoot", "Right Leg", CFrame.new(0, -0.8, 0) },
}

type Spec = {
	at: string,
	shape: string?, -- "Block" (default), "Ball", "Cylinder", "Wedge"
	size: Vector3,
	cf: CFrame,
	color: string?, -- p, s, a, skin, hair, dark, white (default p)
	neon: boolean?,
	alpha: number?,
	mat: Enum.Material?,
	eye: boolean?, -- a face's plain eyes (PieceKits), skipped under a glowing Eyes piece
}

-- the standard blocky rig's part sizes: specs are written for these and scale with the hero's build
local RIG_SIZE: { [string]: Vector3 } = {}
for name, def in Config.HeroRig.parts do
	RIG_SIZE[name] = Vector3.new(def.size[1], def.size[2], def.size[3])
end

local V, CF = Vector3.new, CFrame.new
local ROT_Z = CFrame.Angles(0, 0, math.rad(90))
local ROT_Y = CFrame.Angles(0, math.rad(90), 0)
local function rz(d: number): CFrame
	return CFrame.Angles(0, 0, math.rad(d))
end
local function rx(d: number): CFrame
	return CFrame.Angles(math.rad(d), 0, 0)
end

local function pair(spec: Spec, left: string, right: string, mirror: boolean?): { Spec }
	local l = table.clone(spec)
	l.at = left
	local r = table.clone(spec)
	r.at = right
	if mirror then
		local p = spec.cf.Position
		r.cf = CF(-p.X, p.Y, p.Z) * (spec.cf - p).Rotation:Inverse()
	end
	return { l, r }
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

local function one(spec: Spec): { Spec }
	return { spec }
end

-- Suits: how the body is coloured (torso, arms, legs) plus overlay parts
local SUIT_COLORS: { [string]: { string } } = {
	-- torso, arms, legs
	plain = { "p", "p", "s" },
	stripe = { "p", "p", "s" },
	split = { "p", "s", "s" },
	chevron = { "p", "p", "p" },
	jacket = { "s", "p", "dark" },
	armor = { "p", "s", "s" },
	core = { "p", "p", "s" },
	circuit = { "dark", "dark", "dark" },
	sash = { "p", "p", "s" },
	ribs = { "dark", "p", "dark" },
	panel = { "p", "s", "p" },
	bolt = { "p", "s", "p" },
	bulwark = { "s", "p", "s" },
	neon = { "dark", "dark", "dark" },
	chrome = { "p", "p", "p" },
}

local KITS: { [string]: { [string]: { Spec } } } = {
	suit = {
		plain = {},
		stripe = one({ at = "torso", size = V(0.35, 1.62, 1.06), cf = CF(0, 0, 0), color = "a" }),
		split = one({ at = "waist", size = V(2.06, 0.25, 1.06), cf = CF(0, 0.3, 0), color = "a" }),
		chevron = cat(
			one({
				at = "torso",
				shape = "Wedge",
				size = V(0.1, 0.6, 1.0),
				cf = CF(-0.45, 0.25, -0.55) * rz(-35) * ROT_Y,
				color = "a",
			}),
			one({
				at = "torso",
				shape = "Wedge",
				size = V(0.1, 0.6, 1.0),
				cf = CF(0.45, 0.25, -0.55) * rz(35) * ROT_Y,
				color = "a",
			})
		),
		jacket = cat(
			one({ at = "torso", size = V(0.6, 1.6, 0.12), cf = CF(-0.7, 0, -0.55), color = "p" }),
			one({ at = "torso", size = V(0.6, 1.6, 0.12), cf = CF(0.7, 0, -0.55), color = "p" }),
			one({ at = "torso", size = V(2.1, 0.3, 1.15), cf = CF(0, 0.75, 0), color = "p" })
		),
		armor = cat(
			one({ at = "torso", size = V(1.6, 1.0, 0.25), cf = CF(0, 0.15, -0.55), color = "s" }),
			pair(
				{ at = "", shape = "Ball", size = V(1.0, 0.7, 1.0), cf = CF(0, 0.45, 0), color = "s" },
				"luarm",
				"ruarm"
			)
		),
		core = one({
			at = "torso",
			shape = "Cylinder",
			size = V(0.15, 0.7, 0.7),
			cf = CF(0, 0.2, -0.55) * ROT_Y,
			color = "a",
			neon = true,
		}),
		circuit = cat(
			one({ at = "torso", size = V(0.08, 1.4, 0.05), cf = CF(-0.5, 0, -0.54), color = "a", neon = true }),
			one({ at = "torso", size = V(0.08, 1.4, 0.05), cf = CF(0.5, 0, -0.54), color = "a", neon = true }),
			one({
				at = "torso",
				size = V(1.08, 0.08, 0.05),
				cf = CF(0, -0.3, -0.54),
				color = "a",
				neon = true,
			}),
			pair(
				{ at = "", size = V(0.08, 1.0, 0.05), cf = CF(0, 0, -0.52), color = "a", neon = true },
				"lshin",
				"rshin"
			)
		),
		sash = one({ at = "torso", size = V(0.35, 2.3, 1.15), cf = CF(0, 0, 0) * rz(35), color = "a" }),
		ribs = cat(
			one({ at = "torso", size = V(1.5, 0.12, 0.05), cf = CF(0, 0.4, -0.54), color = "white" }),
			one({ at = "torso", size = V(1.3, 0.12, 0.05), cf = CF(0, 0.1, -0.54), color = "white" }),
			one({ at = "torso", size = V(1.1, 0.12, 0.05), cf = CF(0, -0.2, -0.54), color = "white" })
		),
		panel = cat(
			one({ at = "torso", size = V(0.4, 1.6, 1.12), cf = CF(-0.83, 0, 0), color = "s" }),
			one({ at = "torso", size = V(0.4, 1.6, 1.12), cf = CF(0.83, 0, 0), color = "s" })
		),
		bolt = cat(
			one({ at = "torso", size = V(0.18, 0.7, 0.05), cf = CF(0.15, 0.35, -0.54) * rz(25), color = "a" }),
			one({ at = "torso", size = V(0.6, 0.15, 0.05), cf = CF(0, 0.02, -0.54) * rz(-15), color = "a" }),
			one({ at = "torso", size = V(0.18, 0.7, 0.05), cf = CF(-0.15, -0.3, -0.54) * rz(25), color = "a" })
		),
		bulwark = cat(
			pair(
				{ at = "", size = V(1.2, 0.4, 1.3), cf = CF(0, 0.6, 0) * rz(12), color = "a" },
				"luarm",
				"ruarm",
				true
			),
			one({ at = "torso", size = V(1.8, 1.2, 0.3), cf = CF(0, 0.15, -0.55), color = "a" })
		),
		neon = cat(
			pair(
				{ at = "", size = V(0.06, 1.1, 1.06), cf = CF(0.5, 0, 0), color = "a", neon = true },
				"luarm",
				"ruarm"
			),
			pair(
				{ at = "", size = V(0.06, 1.1, 1.06), cf = CF(0.5, 0, 0), color = "a", neon = true },
				"lshin",
				"rshin"
			)
		),
		chrome = {},
	},
	back = {
		["cape:short"] = one({ at = "torso", size = V(1.8, 1.8, 0.08), cf = CF(0, -0.4, 0.6) }),
		["cape:classic"] = one({ at = "torso", size = V(1.9, 2.8, 0.08), cf = CF(0, -0.9, 0.62) }),
		["cape:collar"] = cat(
			one({ at = "torso", size = V(1.9, 2.8, 0.08), cf = CF(0, -0.9, 0.62) }),
			one({ at = "torso", size = V(2.0, 0.7, 0.08), cf = CF(0, 1.0, 0.45) * rx(-20), color = "s" })
		),
		["cape:long"] = one({ at = "torso", size = V(2.0, 4.0, 0.08), cf = CF(0, -1.5, 0.64) }),
		["cape:tattered"] = cat(
			one({ at = "torso", size = V(1.9, 2.4, 0.08), cf = CF(0, -0.7, 0.62) }),
			one({
				at = "torso",
				shape = "Wedge",
				size = V(0.08, 0.8, 0.6),
				cf = CF(-0.6, -2.3, 0.62) * ROT_Y * rx(180),
			}),
			one({
				at = "torso",
				shape = "Wedge",
				size = V(0.08, 0.8, 0.6),
				cf = CF(0.3, -2.3, 0.62) * ROT_Y * rx(180),
			})
		),
		["cape:split"] = cat(
			one({ at = "torso", size = V(0.9, 3.0, 0.08), cf = CF(-0.5, -1.0, 0.64) * rz(4) }),
			one({ at = "torso", size = V(0.9, 3.0, 0.08), cf = CF(0.5, -1.0, 0.64) * rz(-4), color = "s" })
		),
		["cape:comet"] = cat(
			one({ at = "torso", size = V(1.9, 3.0, 0.08), cf = CF(0, -1.0, 0.62) }),
			one({ at = "torso", size = V(1.7, 0.12, 0.1), cf = CF(0, -2.4, 0.63), color = "a", neon = true })
		),
		["cape:mantle"] = cat(
			one({ at = "torso", size = V(2.2, 3.4, 0.1), cf = CF(0, -1.2, 0.64) }),
			one({ at = "torso", size = V(2.5, 0.35, 1.4), cf = CF(0, 0.85, 0), color = "a" })
		),
		-- anime: long coats and trailing scarves
		["coat:short"] = cat(
			one({ at = "torso", size = V(2.15, 1.7, 1.2), cf = CF(0, 0, 0.02) }),
			one({ at = "waist", size = V(2.15, 0.9, 1.2), cf = CF(0, -0.4, 0.02) })
		),
		["coat:long"] = cat(
			one({ at = "torso", size = V(2.15, 1.7, 1.2), cf = CF(0, 0, 0.02) }),
			one({ at = "waist", size = V(2.15, 2.6, 0.1), cf = CF(0, -1.3, 0.58) }),
			one({ at = "waist", size = V(0.1, 2.6, 1.0), cf = CF(-1.05, -1.3, 0.1), color = "s" }),
			one({ at = "waist", size = V(0.1, 2.6, 1.0), cf = CF(1.05, -1.3, 0.1), color = "s" })
		),
		["coat:shoulder"] = cat(
			one({ at = "torso", size = V(2.6, 1.6, 1.4), cf = CF(0, 0.15, 0.1), alpha = 0 }),
			one({ at = "waist", size = V(2.4, 2.2, 0.1), cf = CF(0, -1.0, 0.7) }),
			one({ at = "torso", size = V(2.6, 0.15, 1.45), cf = CF(0, 0.9, 0.1), color = "a" })
		),
		["coat:shadow"] = cat(
			one({ at = "torso", size = V(2.15, 1.7, 1.2), cf = CF(0, 0, 0.02), color = "dark" }),
			one({ at = "waist", size = V(2.15, 3.0, 0.1), cf = CF(0, -1.5, 0.58), color = "dark" }),
			one({ at = "torso", size = V(2.2, 0.5, 1.25), cf = CF(0, 0.85, 0), color = "a" })
		),
		["scarf:one"] = cat(
			one({
				at = "torso",
				shape = "Cylinder",
				size = V(0.45, 1.5, 1.5),
				cf = CF(0, 0.95, 0) * ROT_Z,
				color = "a",
			}),
			one({ at = "torso", size = V(0.4, 1.8, 0.08), cf = CF(0.45, -0.1, 0.75) * rx(-15), color = "a" })
		),
		["scarf:two"] = cat(
			one({
				at = "torso",
				shape = "Cylinder",
				size = V(0.45, 1.5, 1.5),
				cf = CF(0, 0.95, 0) * ROT_Z,
				color = "a",
			}),
			one({
				at = "torso",
				size = V(0.35, 2.0, 0.08),
				cf = CF(0.35, -0.2, 0.75) * rx(-18) * rz(-8),
				color = "a",
			}),
			one({
				at = "torso",
				size = V(0.35, 1.7, 0.08),
				cf = CF(-0.35, -0.05, 0.75) * rx(-18) * rz(8),
				color = "a",
			})
		),
		["scarf:long"] = cat(
			one({
				at = "torso",
				shape = "Cylinder",
				size = V(0.5, 1.55, 1.55),
				cf = CF(0, 0.95, 0) * ROT_Z,
				color = "a",
			}),
			one({ at = "torso", size = V(0.45, 3.4, 0.08), cf = CF(0.3, -0.6, 1.1) * rx(-35), color = "a" })
		),
		["scarf:spirit"] = cat(
			one({
				at = "torso",
				shape = "Cylinder",
				size = V(0.45, 1.5, 1.5),
				cf = CF(0, 0.95, 0) * ROT_Z,
				color = "a",
				neon = true,
				alpha = 0.2,
			}),
			one({
				at = "torso",
				size = V(0.45, 3.0, 0.08),
				cf = CF(0.3, -0.5, 1.0) * rx(-30),
				color = "a",
				neon = true,
				alpha = 0.35,
			})
		),
	},
	head = {
		domino = one({ at = "head", size = V(1.25, 0.3, 0.12), cf = CF(0, 0.15, -0.6), color = "dark" }),
		cowl = cat(
			one({ at = "head", size = V(1.3, 1.0, 1.3), cf = CF(0, 0.3, 0.02) }),
			one({ at = "head", shape = "Wedge", size = V(0.15, 0.45, 0.3), cf = CF(-0.45, 0.95, 0) }),
			one({ at = "head", shape = "Wedge", size = V(0.15, 0.45, 0.3), cf = CF(0.45, 0.95, 0) })
		),
		visor = one({
			at = "head",
			size = V(1.3, 0.32, 0.18),
			cf = CF(0, 0.15, -0.6),
			color = "a",
			neon = true,
		}),
		half = one({ at = "head", size = V(1.28, 0.55, 0.15), cf = CF(0, -0.28, -0.58) }),
		bandana = one({ at = "head", size = V(1.28, 0.5, 1.28), cf = CF(0, -0.28, 0), color = "s" }),
		helm = cat(
			one({ at = "head", shape = "Ball", size = V(1.5, 1.5, 1.5), cf = CF(0, 0.08, 0.04) }),
			one({ at = "head", size = V(1.1, 0.22, 0.2), cf = CF(0, 0.12, -0.7), color = "dark" })
		),
		crest = cat(
			one({ at = "head", shape = "Ball", size = V(1.5, 1.5, 1.5), cf = CF(0, 0.08, 0.04) }),
			one({ at = "head", size = V(1.1, 0.22, 0.2), cf = CF(0, 0.12, -0.7), color = "a", neon = true }),
			one({ at = "head", shape = "Wedge", size = V(0.15, 0.7, 1.3), cf = CF(0, 0.95, 0.1), color = "a" })
		),
		horns = cat(
			one({ at = "head", shape = "Ball", size = V(1.5, 1.5, 1.5), cf = CF(0, 0.08, 0.04) }),
			one({
				at = "head",
				shape = "Wedge",
				size = V(0.2, 0.8, 0.4),
				cf = CF(-0.55, 0.95, 0) * rz(15),
				color = "a",
			}),
			one({
				at = "head",
				shape = "Wedge",
				size = V(0.2, 0.8, 0.4),
				cf = CF(0.55, 0.95, 0) * rz(-15),
				color = "a",
			})
		),
		antenna = cat(
			one({ at = "head", shape = "Ball", size = V(1.5, 1.5, 1.5), cf = CF(0, 0.08, 0.04) }),
			one({
				at = "head",
				shape = "Cylinder",
				size = V(0.9, 0.08, 0.08),
				cf = CF(-0.4, 1.0, 0) * rz(70),
				color = "a",
			}),
			one({
				at = "head",
				shape = "Cylinder",
				size = V(0.9, 0.08, 0.08),
				cf = CF(0.4, 1.0, 0) * rz(110),
				color = "a",
			})
		),
		hood = one({ at = "head", size = V(1.5, 1.4, 1.5), cf = CF(0, 0.2, 0.12), color = "s" }),
		frame = cat(
			one({ at = "head", size = V(1.45, 1.45, 1.45), cf = CF(0, 0.08, 0.02), color = "s" }),
			one({ at = "head", size = V(1.2, 0.15, 0.1), cf = CF(0, 0.15, -0.74), color = "a", neon = true })
		),
		crown = cat(
			one({
				at = "head",
				shape = "Cylinder",
				size = V(0.3, 1.35, 1.35),
				cf = CF(0, 0.72, 0) * ROT_Z,
				color = "a",
			}),
			one({ at = "head", shape = "Wedge", size = V(0.12, 0.5, 0.3), cf = CF(0, 1.1, -0.6), color = "a" }),
			one({ at = "head", size = V(1.25, 0.3, 0.12), cf = CF(0, 0.15, -0.6), color = "dark" })
		),
	},
	hands = {
		glove = pair(
			{ at = "", size = V(0.55, 0.5, 0.55), cf = CF(0, 0.05, 0), color = "s" },
			"lhand",
			"rhand"
		),
		cuff = cat(
			pair({ at = "", size = V(0.55, 0.5, 0.55), cf = CF(0, 0.05, 0), color = "s" }, "lhand", "rhand"),
			pair({ at = "", size = V(0.62, 0.5, 0.62), cf = CF(0, -0.3, 0), color = "s" }, "llarm", "rlarm")
		),
		fingerless = pair(
			{ at = "", size = V(0.55, 0.28, 0.55), cf = CF(0, 0.18, 0), color = "s" },
			"lhand",
			"rhand"
		),
		spiked = cat(
			pair(
				{ at = "", size = V(0.55, 0.5, 0.55), cf = CF(0, 0.05, 0), color = "dark" },
				"lhand",
				"rhand"
			),
			pair(
				{ at = "", shape = "Wedge", size = V(0.12, 0.3, 0.3), cf = CF(0, 0.1, -0.4), color = "a" },
				"lhand",
				"rhand"
			)
		),
		gauntlet = cat(
			pair({ at = "", size = V(0.62, 0.6, 0.62), cf = CF(0, 0.05, 0), color = "s" }, "lhand", "rhand"),
			pair({ at = "", size = V(0.66, 0.8, 0.66), cf = CF(0, -0.15, 0), color = "s" }, "llarm", "rlarm")
		),
		spark = pair(
			{ at = "", size = V(0.56, 0.5, 0.56), cf = CF(0, 0.05, 0), color = "a", neon = true },
			"lhand",
			"rhand"
		),
		claws = cat(
			pair(
				{ at = "", size = V(0.55, 0.5, 0.55), cf = CF(0, 0.05, 0), color = "dark" },
				"lhand",
				"rhand"
			),
			pair({
				at = "",
				shape = "Wedge",
				size = V(0.08, 0.7, 0.2),
				cf = CF(0, -0.45, -0.2) * rx(180),
				color = "a",
				neon = true,
			}, "lhand", "rhand")
		),
		wraps = pair(
			{ at = "", size = V(0.52, 0.22, 0.52), cf = CF(0, 0.12, 0), color = "white" },
			"lhand",
			"rhand"
		),
		["wraps:long"] = cat(
			pair(
				{ at = "", size = V(0.52, 0.22, 0.52), cf = CF(0, 0.12, 0), color = "white" },
				"lhand",
				"rhand"
			),
			pair(
				{ at = "", size = V(0.58, 0.18, 0.58), cf = CF(0, 0.1, 0), color = "white" },
				"llarm",
				"rlarm"
			),
			pair(
				{ at = "", size = V(0.58, 0.18, 0.58), cf = CF(0, -0.25, 0), color = "white" },
				"llarm",
				"rlarm"
			)
		),
		["wraps:glow"] = cat(
			pair(
				{ at = "", size = V(0.52, 0.22, 0.52), cf = CF(0, 0.12, 0), color = "a", neon = true },
				"lhand",
				"rhand"
			),
			pair(
				{ at = "", size = V(0.58, 0.18, 0.58), cf = CF(0, 0, 0), color = "a", neon = true },
				"llarm",
				"rlarm"
			)
		),
		["wraps:dark"] = cat(
			pair(
				{ at = "", size = V(0.52, 0.22, 0.52), cf = CF(0, 0.12, 0), color = "dark" },
				"lhand",
				"rhand"
			),
			pair({ at = "", size = V(0.58, 0.18, 0.58), cf = CF(0, 0, 0), color = "dark" }, "llarm", "rlarm")
		),
	},
	feet = {
		boot = pair(
			{ at = "", size = V(0.66, 0.45, 1.0), cf = CF(0, -0.05, -0.1), color = "s" },
			"lfoot",
			"rfoot"
		),
		tall = cat(
			pair(
				{ at = "", size = V(0.66, 0.45, 1.0), cf = CF(0, -0.05, -0.1), color = "s" },
				"lfoot",
				"rfoot"
			),
			pair({ at = "", size = V(0.64, 1.0, 0.64), cf = CF(0, 0, 0), color = "s" }, "lshin", "rshin")
		),
		sneaker = cat(
			pair(
				{ at = "", size = V(0.62, 0.38, 0.95), cf = CF(0, 0, -0.1), color = "white" },
				"lfoot",
				"rfoot"
			),
			pair(
				{ at = "", size = V(0.64, 0.12, 0.97), cf = CF(0, -0.18, -0.1), color = "a" },
				"lfoot",
				"rfoot"
			)
		),
		winged = cat(
			pair(
				{ at = "", size = V(0.66, 0.45, 1.0), cf = CF(0, -0.05, -0.1), color = "s" },
				"lfoot",
				"rfoot"
			),
			pair(
				{ at = "", shape = "Wedge", size = V(0.1, 0.5, 0.6), cf = CF(0.4, 0.2, 0.1), color = "a" },
				"lfoot",
				"rfoot",
				true
			)
		),
		jet = cat(
			pair(
				{ at = "", size = V(0.66, 0.45, 1.0), cf = CF(0, -0.05, -0.1), color = "s" },
				"lfoot",
				"rfoot"
			),
			pair({
				at = "",
				shape = "Cylinder",
				size = V(0.3, 0.35, 0.35),
				cf = CF(0, -0.1, 0.5) * ROT_Y,
				color = "a",
				neon = true,
			}, "lfoot", "rfoot")
		),
		armored = cat(
			pair(
				{ at = "", size = V(0.7, 0.5, 1.05), cf = CF(0, -0.05, -0.1), color = "s" },
				"lfoot",
				"rfoot"
			),
			pair({ at = "", size = V(0.55, 0.9, 0.2), cf = CF(0, 0, -0.35), color = "a" }, "lshin", "rshin")
		),
	},
	hair = {
		spiky = cat(
			one({ at = "head", size = V(1.3, 0.35, 1.3), cf = CF(0, 0.6, 0.05), color = "hair" }),
			one({
				at = "head",
				shape = "Wedge",
				size = V(0.3, 0.6, 0.5),
				cf = CF(-0.35, 0.95, 0.1) * rz(20),
				color = "hair",
			}),
			one({
				at = "head",
				shape = "Wedge",
				size = V(0.3, 0.7, 0.5),
				cf = CF(0, 1.0, 0.1),
				color = "hair",
			}),
			one({
				at = "head",
				shape = "Wedge",
				size = V(0.3, 0.6, 0.5),
				cf = CF(0.35, 0.95, 0.1) * rz(-20),
				color = "hair",
			})
		),
		swept = cat(
			one({ at = "head", size = V(1.32, 0.4, 1.32), cf = CF(0, 0.6, 0.05), color = "hair" }),
			one({
				at = "head",
				shape = "Wedge",
				size = V(1.2, 0.35, 0.8),
				cf = CF(0.1, 0.55, -0.55) * rz(-12),
				color = "hair",
			})
		),
		crop = one({ at = "head", size = V(1.3, 0.3, 1.3), cf = CF(0, 0.58, 0.03), color = "hair" }),
		tail = cat(
			one({ at = "head", size = V(1.32, 0.4, 1.32), cf = CF(0, 0.6, 0.05), color = "hair" }),
			one({
				at = "head",
				shape = "Cylinder",
				size = V(1.4, 0.35, 0.35),
				cf = CF(0, -0.1, 0.75) * rz(80),
				color = "hair",
			})
		),
		twin = cat(
			one({ at = "head", size = V(1.32, 0.4, 1.32), cf = CF(0, 0.6, 0.05), color = "hair" }),
			one({
				at = "head",
				shape = "Cylinder",
				size = V(1.4, 0.3, 0.3),
				cf = CF(-0.7, -0.1, 0.3) * rz(75),
				color = "hair",
			}),
			one({
				at = "head",
				shape = "Cylinder",
				size = V(1.4, 0.3, 0.3),
				cf = CF(0.7, -0.1, 0.3) * rz(105),
				color = "hair",
			})
		),
		mane = cat(
			one({ at = "head", size = V(1.45, 0.5, 1.45), cf = CF(0, 0.55, 0.08), color = "hair" }),
			one({ at = "head", size = V(1.5, 1.4, 0.4), cf = CF(0, -0.1, 0.62), color = "hair" })
		),
		topknot = cat(
			one({ at = "head", size = V(1.3, 0.3, 1.3), cf = CF(0, 0.58, 0.03), color = "hair" }),
			one({
				at = "head",
				shape = "Ball",
				size = V(0.5, 0.5, 0.5),
				cf = CF(0, 0.95, 0.15),
				color = "hair",
			})
		),
		flare = cat(
			one({ at = "head", size = V(1.32, 0.4, 1.32), cf = CF(0, 0.6, 0.05), color = "hair" }),
			one({
				at = "head",
				shape = "Wedge",
				size = V(0.8, 1.2, 0.9),
				cf = CF(0, 1.2, 0.15) * rx(-25),
				color = "hair",
			})
		),
		sky = cat(
			one({ at = "head", size = V(1.32, 0.4, 1.32), cf = CF(0, 0.6, 0.05), color = "hair" }),
			one({
				at = "head",
				shape = "Wedge",
				size = V(0.3, 1.1, 0.5),
				cf = CF(-0.4, 1.2, 0.1) * rz(25),
				color = "hair",
			}),
			one({
				at = "head",
				shape = "Wedge",
				size = V(0.35, 1.3, 0.5),
				cf = CF(0, 1.3, 0.1),
				color = "hair",
			}),
			one({
				at = "head",
				shape = "Wedge",
				size = V(0.3, 1.1, 0.5),
				cf = CF(0.4, 1.2, 0.1) * rz(-25),
				color = "hair",
			})
		),
		flow = cat(
			one({ at = "head", size = V(1.4, 0.45, 1.4), cf = CF(0, 0.58, 0.05), color = "hair" }),
			one({ at = "head", size = V(1.4, 2.2, 0.25), cf = CF(0, -0.5, 0.65), color = "hair" })
		),
	},
}
LookKit.KITS = KITS

-- Full helmets and hoods hide the hair (no clipping)
local HIDES_HAIR =
	{ cowl = true, helm = true, crest = true, horns = true, antenna = true, hood = true, frame = true }
local EYE_COLORS = {
	gold = { 255, 210, 70 },
	ice = { 200, 245, 255 },
	ember = { 255, 110, 40 },
	spirit = { 170, 255, 255 },
}
local AURAS = {
	ember = { rate = 10, speed = 3, life = 1.0, size = 0.5, light = 1, colors = { "a", "glowRed" } },
	mist = { rate = 6, speed = 0.6, life = 2.2, size = 1.6, light = 0.3, colors = { "ice", "white" } },
	static = { rate = 8, speed = 4, life = 0.4, size = 0.25, light = 1, colors = { "a", "white" } },
	spirit = { rate = 14, speed = 5, life = 0.7, size = 0.9, light = 1, colors = { "a", "white" } },
	shimmer = { rate = 6, speed = 0.4, life = 1.5, size = 0.4, light = 0.8, colors = { "white", "a" } },
	solar = { rate = 10, speed = 2, life = 1.2, size = 0.7, light = 1, colors = { "gold", "a" } },
}
local TRAILS = {
	ribbon = { width = 1.2, life = 0.5, alpha = 0.3, light = 0.4 },
	streak = { width = 0.4, life = 0.35, alpha = 0.1, light = 1 },
	twin = { width = 0.6, life = 0.5, alpha = 0.3, light = 0.6, hands = true },
	sparkle = { width = 0.8, life = 0.6, alpha = 0.2, light = 1 },
	comet = { width = 2.0, life = 0.7, alpha = 0.2, light = 1 },
	smoke = { width = 1.6, life = 0.9, alpha = 0.5, light = 0, grey = true },
	storm = { width = 1.0, life = 0.5, alpha = 0.15, light = 1 },
	neon = { width = 0.8, life = 0.45, alpha = 0.05, light = 1 },
}

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

export type Colors = { [string]: Color3 }

function LookKit.colors(look: any): Colors
	local pal = C.palette
	local a = rgb(pal[look.colors[3]] or pal[4])
	return {
		p = rgb(pal[look.colors[1]] or pal[10]),
		s = rgb(pal[look.colors[2]] or pal[1]),
		a = a,
		hair = rgb(pal[look.hair] or pal[22]),
		skin = rgb(C.skins[look.skin] or C.skins[3]),
		dark = Color3.fromRGB(34, 38, 52),
		white = Color3.fromRGB(240, 240, 245),
		ice = Color3.fromRGB(200, 245, 255),
		gold = Color3.fromRGB(255, 210, 70),
		glowRed = Color3.fromRGB(255, 80, 40),
		eyeOverride = if (look.eyeColor or 0) ~= 0 and pal[look.eyeColor]
			then rgb(pal[look.eyeColor])
			else nil,
	} :: any
end

local function bodyPart(char: Model, role: string): (BasePart?, CFrame)
	local a = ATTACH[role]
	local p = char:FindFirstChild(a[1])
	if p and p:IsA("BasePart") then
		return p, CFrame.new()
	end
	local r6 = char:FindFirstChild(a[2])
	if r6 and r6:IsA("BasePart") then
		return r6, a[3]
	end
	return nil, CFrame.new()
end
LookKit.bodyPart = bodyPart

local function make(
	char: Model,
	folder: Instance,
	name: string,
	spec: Spec,
	colors: Colors,
	mat: Enum.Material?
)
	local part, offset = bodyPart(char, spec.at)
	if not part then
		return
	end
	-- a wider or taller body part (the build, or another avatar's sizes) scales the piece with it
	local ref = RIG_SIZE[part.Name]
	local f = if ref then part.Size / ref else Vector3.one
	local size = spec.size * f
	local cf = CFrame.new(spec.cf.Position * f) * spec.cf.Rotation
	local p: BasePart
	if spec.shape == "Wedge" then
		p = Instance.new("WedgePart")
	else
		local pp = Instance.new("Part")
		if spec.shape == "Ball" then
			pp.Shape = Enum.PartType.Ball
		elseif spec.shape == "Cylinder" then
			pp.Shape = Enum.PartType.Cylinder
		end
		p = pp
	end
	p.Name = name
	p.Size = size
	p.Color = colors[spec.color or "p"] or colors.p
	p.Material = if spec.neon then Enum.Material.Neon else (mat or spec.mat or Enum.Material.SmoothPlastic)
	p.Transparency = spec.alpha or 0
	p.Massless = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.CFrame = part.CFrame * offset * cf
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part
	weld.Part1 = p
	weld.Parent = p
	p.Parent = folder
end

-- A slot's own colours (main, trim, glow over p, s, a) and material, from the look's per-slot picks
local function slotColors(base: Colors, look: any, slot: string): (Colors, Enum.Material?)
	local t = look.tints and look.tints[slot]
	local out = base
	if t then
		out = table.clone(base)
		local pal = C.palette
		for i, key in { "p", "s", "a" } do
			local c = pal[t[i] or 0]
			if c then
				out[key] = rgb(c)
			end
		end
	end
	local m = look.mats and look.mats[slot]
	local mat = if m and C.materials[m] then (Enum.Material :: any)[C.materials[m]] else nil
	return out, mat
end

local function addSpecs(
	char: Model,
	folder: Instance,
	name: string,
	specs: { Spec }?,
	colors: Colors,
	mat: Enum.Material?,
	skipEyes: boolean?
)
	for _, s in specs or {} do
		if not (skipEyes and s.eye) then
			make(char, folder, name, s, colors, mat)
		end
	end
end

-- Shape the body for the look's gender, build and height (BodyShape): every body part and its attachments
-- scale from their first-seen size, the joints follow the moved attachments, and the hip height follows the
-- legs. The HumanoidRootPart (the collider and hit capsule) never changes. Safe to call again on a new look.
function LookKit.shapeBody(char: Model, look: any)
	local factors, tall = BodyShape.factors(Config, look)
	for name, f in factors do
		local p = char:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			local base = p:GetAttribute("BaseSize")
			if typeof(base) ~= "Vector3" then
				base = p.Size
				p:SetAttribute("BaseSize", base)
			end
			local k = Vector3.new(f[1], f[2], f[3])
			p.Size = (base :: Vector3) * k
			for _, a in p:GetChildren() do
				if a:IsA("Attachment") then
					local bp = a:GetAttribute("BasePos")
					if typeof(bp) ~= "Vector3" then
						bp = a.Position
						a:SetAttribute("BasePos", bp)
					end
					a.Position = (bp :: Vector3) * k
				end
			end
		end
	end
	-- each joint (Motor6D "Neck" etc.) meets at its two "<name>RigAttachment"s
	for _, p in char:GetChildren() do
		if p:IsA("BasePart") then
			for _, m in p:GetChildren() do
				if m:IsA("Motor6D") and m.Part0 and m.Part1 then
					local a0 = m.Part0:FindFirstChild(m.Name .. "RigAttachment")
					local a1 = m.Part1:FindFirstChild(m.Name .. "RigAttachment")
					if a0 and a1 and a0:IsA("Attachment") and a1:IsA("Attachment") then
						m.C0 = a0.CFrame
						m.C1 = a1.CFrame
					end
				end
			end
		end
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		local baseHip = hum:GetAttribute("BaseHip")
		if type(baseHip) ~= "number" then
			baseHip = hum.HipHeight
			hum:SetAttribute("BaseHip", baseHip)
		end
		hum.HipHeight = (baseHip :: number) * tall
	end
end

-- The avatar's own accessories and clothes come off (the face stays)
function LookKit.strip(char: Model)
	for _, d in char:GetChildren() do
		if
			d:IsA("Accessory")
			or d:IsA("Shirt")
			or d:IsA("Pants")
			or d:IsA("ShirtGraphic")
			or d:IsA("CharacterMesh")
		then
			d:Destroy()
		end
	end
end

local function paintBody(
	char: Model,
	pattern: string,
	colors: Colors,
	skinMat: Enum.Material?,
	legPaint: { Color3 }?
)
	local roles = SUIT_COLORS[pattern] or SUIT_COLORS.plain
	local torso, arms, legs = colors[roles[1]], colors[roles[2]], colors[roles[3]]
	if legPaint then
		legs = legPaint[1]
	end
	local bc = char:FindFirstChildOfClass("BodyColors") or Instance.new("BodyColors")
	bc.HeadColor3 = colors.skin
	bc.TorsoColor3 = torso
	bc.LeftArmColor3 = arms
	bc.RightArmColor3 = arms
	bc.LeftLegColor3 = legs
	bc.RightLegColor3 = legs
	bc.Parent = char
	-- the parts themselves too, so a preview dummy (no Humanoid appearance pass) shows it at once
	local finish = if pattern == "chrome" then Enum.Material.Foil else Enum.Material.SmoothPlastic
	for _, p in char:GetChildren() do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			local n = p.Name
			if n == "Head" then
				p.Color = colors.skin
				p.Material = skinMat or Enum.Material.SmoothPlastic
			elseif legPaint and string.find(n, "LowerLeg") then
				p.Color = legPaint[2]
				p.Material = if legPaint[2] == colors.skin then (skinMat or finish) else finish
			elseif string.find(n, "Torso") then
				p.Color = torso
				p.Material = finish
			elseif string.find(n, "Arm") or string.find(n, "Hand") then
				p.Color = arms
				p.Material = finish
			elseif string.find(n, "Leg") or string.find(n, "Foot") then
				p.Color = legs
				p.Material = finish
			end
		end
	end
end

local function emblem(char: Model, folder: Instance, kit: string, colors: Colors)
	local torso, offset = bodyPart(char, "torso")
	if not torso then
		return
	end
	local bits = string.split(kit, ":")
	local glyph = C.shapes[bits[1]] or "★"
	local backing = bits[2] or "none"
	local plate = Instance.new("Part")
	plate.Name = "Emblem"
	plate.Size = Vector3.new(0.9, 0.9, 0.05)
	plate.Transparency = 1
	plate.Massless = true
	plate.CanCollide = false
	plate.CanTouch = false
	plate.CanQuery = false
	plate.CFrame = torso.CFrame * offset * CFrame.new(0, 0.25, -torso.Size.Z / 2 - 0.06)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso
	weld.Part1 = plate
	weld.Parent = plate
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(100, 100)
	gui.LightInfluence = 0.6
	gui.Parent = plate
	if backing ~= "none" then
		local back = Instance.new("Frame")
		back.AnchorPoint = Vector2.new(0.5, 0.5)
		back.Position = UDim2.fromScale(0.5, 0.5)
		back.Size =
			UDim2.fromScale(if backing == "gem" then 0.72 else 0.95, if backing == "gem" then 0.72 else 0.95)
		back.Rotation = if backing == "gem" then 45 else 0
		back.BackgroundColor3 = colors.s
		back.BorderSizePixel = 0
		back.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = if backing == "badge" then UDim.new(0.5, 0) else UDim.new(0.25, 0)
		corner.Parent = back
		local stroke = Instance.new("UIStroke")
		stroke.Color = colors.a
		stroke.Thickness = 4
		stroke.Parent = back
	end
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = glyph
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = colors.a
	label.TextStrokeTransparency = 0.4
	label.Parent = gui
	plate.Parent = folder
end

local function eyes(char: Model, folder: Instance, kit: string, colors: Colors)
	local head = bodyPart(char, "head")
	if not head then
		return
	end
	local left = if kit == "accent" or kit == "prism"
		then colors.a
		else rgb(EYE_COLORS[kit] or { 255, 255, 255 })
	local right = if kit == "prism" then colors.p else left
	if colors.eyeOverride then
		left, right = colors.eyeOverride, colors.eyeOverride
	end
	for i, x in { -0.22, 0.22 } do
		make(char, folder, "Eye", {
			at = "head",
			size = Vector3.new(0.2, 0.09, 0.05),
			cf = CFrame.new(x, 0.12, -head.Size.Z / 2 - 0.01),
			color = "eye" .. i,
			neon = true,
		}, { ["eye1"] = left, ["eye2"] = right, p = left } :: any)
	end
end

local function aura(char: Model, folder: Instance, kit: string, colors: Colors)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local a = AURAS[kit]
	if not root or not a then
		return
	end
	local att = Instance.new("Attachment")
	att.Name = "AuraPoint"
	att.Parent = root
	local e = Instance.new("ParticleEmitter")
	e.Name = "CreatorAura"
	e.Rate = a.rate
	e.Lifetime = NumberRange.new(a.life * 0.7, a.life)
	e.Speed = NumberRange.new(a.speed * 0.5, a.speed)
	e.SpreadAngle = Vector2.new(25, 25)
	e.Acceleration = Vector3.new(0, a.speed, 0)
	e.EmissionDirection = Enum.NormalId.Top
	e.LightEmission = a.light
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, a.size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	e.Color = ColorSequence.new(colors[a.colors[1]] or colors.a, colors[a.colors[2]] or colors.white)
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.Parent = att
	-- the attachment lives on the root, so the folder tracks it for cleanup
	local tag = Instance.new("ObjectValue")
	tag.Name = "AuraRef"
	tag.Value = att
	tag.Parent = folder
end

local function trail(char: Model, folder: Instance, kit: string, colors: Colors)
	local t = TRAILS[kit]
	if not t then
		return
	end
	local function one(partRole: string, top: Vector3, bottom: Vector3)
		local part = bodyPart(char, partRole)
		if not part then
			return
		end
		local a0 = Instance.new("Attachment")
		a0.Name = "TrailTop"
		a0.Position = top
		a0.Parent = part
		local a1 = Instance.new("Attachment")
		a1.Name = "TrailBottom"
		a1.Position = bottom
		a1.Parent = part
		local tr = Instance.new("Trail")
		tr.Name = "CreatorTrail"
		tr.Attachment0 = a0
		tr.Attachment1 = a1
		tr.Lifetime = t.life
		tr.MinLength = 0.2
		tr.LightEmission = t.light
		tr.FaceCamera = true
		tr.WidthScale = NumberSequence.new(1, 0.1)
		tr.Transparency = NumberSequence.new(t.alpha, 1)
		local c0 = if t.grey then Color3.fromRGB(150, 150, 160) else colors.a
		local c1 = if t.grey then Color3.fromRGB(90, 90, 100) else colors.p
		tr.Color = ColorSequence.new(c0, c1)
		tr.Parent = part
		for _, inst in { a0, a1 } do
			local tag = Instance.new("ObjectValue")
			tag.Name = "TrailRef"
			tag.Value = inst
			tag.Parent = folder
		end
	end
	if t.hands then
		one("lhand", Vector3.new(0, 0.2, 0), Vector3.new(0, -0.2, 0))
		one("rhand", Vector3.new(0, 0.2, 0), Vector3.new(0, -0.2, 0))
	else
		one("torso", Vector3.new(0, t.width / 2, 0.5), Vector3.new(0, -t.width / 2, 0.5))
	end
end

-- Remove a look built by build() (the folder and the emitters and trails it made on body parts)
function LookKit.clear(char: Model)
	local old = char:FindFirstChild("HeroLook")
	if old then
		for _, ref in old:GetChildren() do
			if ref:IsA("ObjectValue") and ref.Value then
				local v = ref.Value
				-- a trail on the body part goes with its attachments
				local parent = v.Parent
				if parent then
					for _, tr in parent:GetChildren() do
						if tr:IsA("Trail") and (tr.Attachment0 == v or tr.Attachment1 == v) then
							tr:Destroy()
						end
					end
				end
				v:Destroy()
			end
		end
		old:Destroy()
	end
end

-- Build a whole look (LookService adds the gear styles the look does not cover). Returns the folder.
-- The body is shaped first (build, height, gender), so every piece is sized for it.
local NEW_SLOTS =
	{ "beard", "face", "makeup", "hat", "ears", "shoulders", "neck", "arms", "wrist", "belt", "backpack" }
function LookKit.build(char: Model, look: any): Folder
	LookKit.clear(char)
	LookKit.shapeBody(char, look)
	local folder = Instance.new("Folder")
	folder.Name = "HeroLook"
	local colors = LookKit.colors(look)
	local function kitOf(tab: string): string?
		local i = look.pieces[tab] or 0
		local p = if i > 0 then CreatorRules.piece(Config, tab, i) else nil
		return p and p.kit
	end
	-- the body: suit colours, skin (a fantasy skin has its own material), and the legs piece's paint
	local fantasy = C.fantasySkins[look.skin]
	local skinMat: Enum.Material? = if fantasy then (Enum.Material :: any)[fantasy.mat] else nil
	local legsKit = kitOf("legs")
	local legDef = legsKit and PieceKits.legs[legsKit]
	local legColors, legMat = slotColors(colors, look, "legs")
	local legPaint = if legDef
		then { legColors[legDef.paint[1]] or legColors.s, legColors[legDef.paint[2]] or legColors.s }
		else nil
	local suit = kitOf("suit") or "plain"
	local suitColors, suitMat = slotColors(colors, look, "suit")
	paintBody(char, suit, suitColors, skinMat, legPaint)
	addSpecs(char, folder, "Suit", KITS.suit[suit], suitColors, suitMat)
	for _, tab in { "back", "head", "hands", "feet" } do
		local kit = kitOf(tab)
		local c, m = slotColors(colors, look, tab)
		addSpecs(char, folder, tab, kit and KITS[tab][kit], c, m)
	end
	if legDef then
		addSpecs(char, folder, "legs", legDef.parts, legColors, legMat)
	end
	-- headwear and masks may hide the hair (and a closed helm the face)
	local headKit = kitOf("head")
	local hatKit = kitOf("hat")
	local hidesHair = (headKit and HIDES_HAIR[headKit]) or (hatKit and PieceKits.hatHidesHair[hatKit])
	local hidesFace = hatKit ~= nil and PieceKits.hatHidesFace[hatKit] == true
	local hairKit = kitOf("hair")
	if hairKit and not hidesHair then
		addSpecs(char, folder, "Hair", KITS.hair[hairKit] or PieceKits.hair[hairKit], colors)
	end
	local eyeKit = kitOf("eyes")
	for _, slot in NEW_SLOTS do
		local kit = kitOf(slot)
		local covered = hidesFace and (slot == "face" or slot == "makeup" or slot == "beard")
		if kit and not covered then
			local c, m = slotColors(colors, look, slot)
			addSpecs(
				char,
				folder,
				slot,
				(PieceKits :: any)[slot][kit],
				c,
				m,
				slot == "face" and eyeKit ~= nil
			)
		end
	end
	-- the default face decal steps aside for a Face piece or a closed helm
	local head = char:FindFirstChild("Head")
	local decal = head and head:FindFirstChild("face")
	if decal and decal:IsA("Decal") then
		decal.Transparency = if kitOf("face") or hidesFace then 1 else 0
	end
	local e = kitOf("emblem")
	if e then
		emblem(char, folder, e, (slotColors(colors, look, "emblem")))
	end
	if eyeKit and not hidesFace then
		eyes(char, folder, eyeKit, colors)
	end
	local auraKit = kitOf("aura")
	if auraKit then
		aura(char, folder, auraKit, colors)
	end
	local trailKit = kitOf("trail")
	if trailKit then
		trail(char, folder, trailKit, colors)
	end
	folder.Parent = char
	return folder
end

return LookKit
