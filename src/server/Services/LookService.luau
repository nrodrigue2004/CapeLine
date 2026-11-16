-- LookService: the gear look on each hero (spec: Style collection: any unlocked style shows on its slot over
-- any gear). Built on the server so every player sees it. Each style is a few small welded parts on the
-- body (PLACEHOLDER ART: blocks, balls, wedges and cylinders until the M9 accessory meshes). The parts are
-- massless and never collide, touch or block raycasts. Works on R15 and R6 bodies. GearService calls apply()
-- on join, on respawn and after every gear or style change.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GearMath = require(Shared:WaitForChild("GearMath"))

local LookService = {}

local G = Config.Gear
local GOLD = Color3.fromRGB(255, 200, 60)
local DARK = Color3.fromRGB(34, 38, 52)

-- body part by role, R15 first, R6 second, with an offset for R6 (one part per limb)
local ATTACH = {
	head = { "Head", "Head", CFrame.new() },
	torso = { "UpperTorso", "Torso", CFrame.new(0, 0.3, 0) },
	waist = { "LowerTorso", "Torso", CFrame.new(0, -0.8, 0) },
	lhand = { "LeftHand", "Left Arm", CFrame.new(0, -0.8, 0) },
	rhand = { "RightHand", "Right Arm", CFrame.new(0, -0.8, 0) },
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
	trim: boolean?, -- the style colour (else the dark base)
	neon: boolean?,
	alpha: number?,
}

local function both(spec: Spec, left: string, right: string): { Spec }
	local l = table.clone(spec)
	l.at = left
	local r = table.clone(spec)
	r.at = right
	return { l, r }
end

local function join(...: { Spec }): { Spec }
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

local V, C = Vector3.new, CFrame.new
local ROT_Z = CFrame.Angles(0, 0, math.rad(90))
local ROT_Y = CFrame.Angles(0, math.rad(90), 0)

-- Shape builders by slot. "set" and "gilded" reuse the slot's strongest shape.
local SHAPES: { [string]: { [string]: { Spec } } } = {
	head = {
		visor = one({
			at = "head",
			size = V(1.3, 0.35, 0.2),
			cf = C(0, 0.15, -0.6),
			trim = true,
			neon = true,
		}),
		cap = join(
			one({ at = "head", size = V(1.3, 0.3, 1.3), cf = C(0, 0.62, 0), trim = true }),
			one({ at = "head", size = V(1.3, 0.08, 0.5), cf = C(0, 0.5, -0.8), trim = true })
		),
		mask = one({ at = "head", size = V(1.25, 0.4, 0.15), cf = C(0, 0.15, -0.6), trim = true }),
		fin = join(
			one({ at = "head", size = V(1.32, 0.9, 1.32), cf = C(0, 0.25, 0) }),
			one({ at = "head", shape = "Wedge", size = V(0.2, 0.6, 1.2), cf = C(0, 0.95, 0), trim = true })
		),
		horns = join(
			one({ at = "head", size = V(1.32, 0.9, 1.32), cf = C(0, 0.25, 0) }),
			one({ at = "head", shape = "Wedge", size = V(0.2, 0.7, 0.4), cf = C(-0.5, 0.95, 0), trim = true }),
			one({ at = "head", shape = "Wedge", size = V(0.2, 0.7, 0.4), cf = C(0.5, 0.95, 0), trim = true })
		),
		halo = one({
			at = "head",
			shape = "Cylinder",
			size = V(0.1, 1.5, 1.5),
			cf = C(0, 1.15, 0) * ROT_Z,
			trim = true,
			neon = true,
		}),
		set = join(
			one({ at = "head", shape = "Ball", size = V(1.45, 1.45, 1.45), cf = C(0, 0.05, 0.05) }),
			one({ at = "head", size = V(1.2, 0.3, 0.2), cf = C(0, 0.1, -0.68), trim = true, neon = true })
		),
		gilded = join(
			one({
				at = "head",
				shape = "Cylinder",
				size = V(0.35, 1.32, 1.32),
				cf = C(0, 0.75, 0) * ROT_Z,
				trim = true,
			}),
			one({ at = "head", size = V(1.3, 0.3, 0.2), cf = C(0, 0.15, -0.6), trim = true, neon = true })
		),
	},
	chest = {
		vest = one({ at = "torso", size = V(2.08, 1.5, 1.16), cf = C(0, 0, 0) }),
		plate = join(
			one({ at = "torso", size = V(1.6, 1.0, 0.25), cf = C(0, 0.15, -0.55), trim = true }),
			one({
				at = "torso",
				shape = "Ball",
				size = V(0.45, 0.45, 0.2),
				cf = C(0, 0.2, -0.7),
				neon = true,
				trim = true,
			})
		),
		harness = join(
			one({ at = "torso", size = V(0.3, 1.6, 1.2), cf = C(-0.55, 0, 0), trim = true }),
			one({ at = "torso", size = V(0.3, 1.6, 1.2), cf = C(0.55, 0, 0), trim = true })
		),
		core = join(
			one({ at = "torso", size = V(1.6, 1.0, 0.25), cf = C(0, 0.15, -0.55) }),
			one({
				at = "torso",
				shape = "Cylinder",
				size = V(0.2, 0.7, 0.7),
				cf = C(0, 0.2, -0.7) * ROT_Y,
				trim = true,
				neon = true,
			})
		),
		set = join(
			one({ at = "torso", size = V(2.08, 1.5, 1.16), cf = C(0, 0, 0) }),
			one({ at = "torso", size = V(0.5, 0.5, 0.1), cf = C(0, 0.2, -0.62), trim = true, neon = true })
		),
		gilded = join(
			one({ at = "torso", size = V(1.7, 1.1, 0.25), cf = C(0, 0.15, -0.55), trim = true }),
			one({ at = "torso", shape = "Ball", size = V(0.5, 0.5, 0.2), cf = C(0, 0.2, -0.7), neon = true })
		),
	},
	hands = {
		wraps = both(
			{ at = "", size = V(0.45, 0.3, 0.45), cf = C(0, 0.15, 0), trim = true },
			"lhand",
			"rhand"
		),
		gauntlet = both({ at = "", size = V(0.55, 0.55, 0.55), cf = C(0, 0.1, 0) }, "lhand", "rhand"),
		spikes = join(
			both({ at = "", size = V(0.55, 0.55, 0.55), cf = C(0, 0.1, 0) }, "lhand", "rhand"),
			both(
				{ at = "", shape = "Wedge", size = V(0.15, 0.3, 0.3), cf = C(0, 0.1, -0.4), trim = true },
				"lhand",
				"rhand"
			)
		),
		coil = both({
			at = "",
			shape = "Cylinder",
			size = V(0.3, 0.6, 0.6),
			cf = C(0, 0.25, 0) * ROT_Z,
			trim = true,
			neon = true,
		}, "lhand", "rhand"),
		set = both({ at = "", size = V(0.58, 0.6, 0.58), cf = C(0, 0.1, 0), trim = true }, "lhand", "rhand"),
		gilded = both(
			{ at = "", size = V(0.58, 0.6, 0.58), cf = C(0, 0.1, 0), trim = true },
			"lhand",
			"rhand"
		),
	},
	legs = {
		shins = both(
			{ at = "", size = V(0.5, 0.9, 0.22), cf = C(0, 0, -0.35), trim = true },
			"lshin",
			"rshin"
		),
		stripes = both(
			{ at = "", size = V(0.12, 1.1, 0.64), cf = C(0.28, 0, 0), trim = true },
			"lshin",
			"rshin"
		),
		greaves = both({ at = "", size = V(0.62, 1.0, 0.62), cf = C(0, 0, 0) }, "lshin", "rshin"),
		set = both({ at = "", size = V(0.62, 1.0, 0.62), cf = C(0, 0, 0), trim = true }, "lshin", "rshin"),
		gilded = both({ at = "", size = V(0.62, 1.0, 0.62), cf = C(0, 0, 0), trim = true }, "lshin", "rshin"),
	},
	feet = {
		boots = both({ at = "", size = V(0.66, 0.45, 1.0), cf = C(0, -0.05, -0.1) }, "lfoot", "rfoot"),
		jets = join(
			both({ at = "", size = V(0.66, 0.45, 1.0), cf = C(0, -0.05, -0.1) }, "lfoot", "rfoot"),
			both({
				at = "",
				shape = "Cylinder",
				size = V(0.3, 0.35, 0.35),
				cf = C(0, -0.1, 0.5) * ROT_Y,
				trim = true,
				neon = true,
			}, "lfoot", "rfoot")
		),
		wings = join(
			both(
				{ at = "", size = V(0.66, 0.45, 1.0), cf = C(0, -0.05, -0.1), trim = true },
				"lfoot",
				"rfoot"
			),
			both(
				{ at = "", shape = "Wedge", size = V(0.1, 0.5, 0.6), cf = C(0.4, 0.2, 0.1), trim = true },
				"lfoot",
				"rfoot"
			)
		),
		set = both(
			{ at = "", size = V(0.68, 0.5, 1.02), cf = C(0, -0.05, -0.1), trim = true },
			"lfoot",
			"rfoot"
		),
		gilded = both(
			{ at = "", size = V(0.68, 0.5, 1.02), cf = C(0, -0.05, -0.1), trim = true },
			"lfoot",
			"rfoot"
		),
	},
	back = {
		cape = one({ at = "torso", size = V(1.8, 2.6, 0.08), cf = C(0, -0.8, 0.62), trim = true }),
		longcape = one({ at = "torso", size = V(1.9, 3.8, 0.08), cf = C(0, -1.4, 0.64), trim = true }),
		jetpack = join(
			one({ at = "torso", size = V(1.2, 1.3, 0.6), cf = C(0, 0, 0.85) }),
			one({
				at = "torso",
				shape = "Cylinder",
				size = V(0.6, 0.4, 0.4),
				cf = C(-0.35, -0.8, 0.85) * ROT_Z,
				trim = true,
				neon = true,
			}),
			one({
				at = "torso",
				shape = "Cylinder",
				size = V(0.6, 0.4, 0.4),
				cf = C(0.35, -0.8, 0.85) * ROT_Z,
				trim = true,
				neon = true,
			})
		),
		lightwings = join(
			one({
				at = "torso",
				shape = "Wedge",
				size = V(0.1, 1.8, 1.4),
				cf = C(-0.9, 0.3, 0.9) * CFrame.Angles(0, math.rad(-30), 0),
				trim = true,
				neon = true,
				alpha = 0.3,
			}),
			one({
				at = "torso",
				shape = "Wedge",
				size = V(0.1, 1.8, 1.4),
				cf = C(0.9, 0.3, 0.9) * CFrame.Angles(0, math.rad(30), 0),
				trim = true,
				neon = true,
				alpha = 0.3,
			})
		),
		set = one({ at = "torso", size = V(1.9, 3.0, 0.08), cf = C(0, -1.0, 0.62), trim = true }),
		gilded = one({ at = "torso", size = V(1.9, 3.4, 0.08), cf = C(0, -1.2, 0.62), trim = true }),
	},
	belt = {
		belt = one({ at = "waist", size = V(2.08, 0.3, 1.16), cf = C(0, 0.25, 0), trim = true }),
		buckle = join(
			one({ at = "waist", size = V(2.08, 0.3, 1.16), cf = C(0, 0.25, 0) }),
			one({ at = "waist", size = V(0.5, 0.36, 0.1), cf = C(0, 0.25, -0.62), trim = true, neon = true })
		),
		sash = one({
			at = "torso",
			size = V(0.3, 2.3, 1.2),
			cf = C(0, -0.2, 0) * CFrame.Angles(0, 0, math.rad(35)),
			trim = true,
		}),
		set = one({ at = "waist", size = V(2.08, 0.34, 1.16), cf = C(0, 0.25, 0), trim = true }),
		gilded = one({ at = "waist", size = V(2.08, 0.34, 1.16), cf = C(0, 0.25, 0), trim = true }),
	},
}
LookService.SHAPES = SHAPES

local function colorOf(row: any): Color3
	if row.shape == "gilded" then
		return GOLD
	end
	if row.shape == "set" then
		local power = G.sets[row.set].power
		local c = Config.Abilities.setColor[power]
		return Color3.fromRGB(c[1], c[2], c[3])
	end
	return Color3.fromRGB(row.color[1], row.color[2], row.color[3])
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

local function build(char: Model, folder: Folder, slot: string, row: any)
	local specs = SHAPES[slot] and SHAPES[slot][row.shape]
	if not specs then
		return
	end
	local trim = colorOf(row)
	for _, spec in specs do
		local part, offset = bodyPart(char, spec.at)
		if part then
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
			p.Name = slot
			p.Size = spec.size
			p.Color = if spec.trim then trim else DARK
			p.Material = if spec.neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
			p.Transparency = spec.alpha or 0
			p.Massless = true
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
			p.CastShadow = false
			p.CFrame = part.CFrame * offset * spec.cf
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = part
			weld.Part1 = p
			weld.Parent = p
			p.Parent = folder
		end
	end
end

-- Show these styles (one id per slot, 0 = nothing) on the player's character
function LookService.apply(player: Player, styles: { number })
	local char = player.Character
	if not char then
		return
	end
	local old = char:FindFirstChild("GearLook")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "GearLook"
	for slotIdx, id in styles do
		local slot = G.slotOrder[slotIdx]
		if id ~= 0 and slot then
			local row = GearMath.styleRow(Config, id)
			if row then
				build(char, folder, slot, row)
			end
		end
	end
	folder.Parent = char
end

return LookService
