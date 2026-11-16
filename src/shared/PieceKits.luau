-- PieceKits: the part specs for the hero creator plan's new slots (2026-11-16: facial hair, face, makeup,
-- headwear, ears, shoulders, neck, arms, rings and bracelets, belt, legs, back bling) and the extra hair
-- styles. LookKit builds them like its own kits: each spec is a small welded part on a body part (by role),
-- sized for the standard blocky R15 rig (Config.HeroRig) and scaled with the hero's build.
-- Colours: p, s, a are the slot's main, trim and glow colours (the whole-hero colours unless the slot has
-- its own); hair, skin, dark, white, gold are fixed roles. `eye = true` marks a face's plain eyes (skipped
-- when a glowing Eyes piece is worn).
-- PLACEHOLDER ART: blocks, wedges, balls and cylinders until the Blender piece sets replace them.

local V, CF = Vector3.new, CFrame.new
local function rz(d: number): CFrame
	return CFrame.Angles(0, 0, math.rad(d))
end
local function rx(d: number): CFrame
	return CFrame.Angles(math.rad(d), 0, 0)
end
local ROT_Y = CFrame.Angles(0, math.rad(90), 0)
local FLAT = rz(90) -- a cylinder standing up (its axis along Y): a flat disc

type Spec = { [string]: any }

-- the spec and its mirror image (x and the rotation flipped) on another role, or the same role
local function both(spec: Spec, left: string?, right: string?): { Spec }
	local l = table.clone(spec)
	l.at = left or spec.at
	local r = table.clone(spec)
	r.at = right or spec.at
	local p = spec.cf.Position
	local rot = spec.cf - p
	local rx_, ry, rz_ = rot:ToEulerAnglesXYZ()
	r.cf = CF(-p.X, p.Y, p.Z) * CFrame.fromEulerAnglesXYZ(rx_, -ry, -rz_)
	return { l, r }
end

local function cat(...: any): { Spec }
	local out = {}
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if v.at then
			table.insert(out, v)
		else
			for _, s in v do
				table.insert(out, s)
			end
		end
	end
	return out
end

local function S(at: string, size: Vector3, cf: CFrame, color: string?, extra: Spec?): Spec
	local s: Spec = { at = at, size = size, cf = cf, color = color or "p" }
	local more: Spec = extra or {}
	for k, v in more do
		s[k] = v
	end
	return s
end

-- the head is 1.19 x 1.28 x 1.19: its face is at z = -0.6, the top at y = 0.64
local FZ = -0.6
local function eyes(w: number?, h: number?): { Spec }
	return both(S("head", V(w or 0.14, h or 0.2, 0.04), CF(-0.22, 0.1, FZ - 0.01), "dark", { eye = true }))
end
local function brows(angle: number, y: number?): { Spec }
	return both(S("head", V(0.3, 0.07, 0.04), CF(-0.22, y or 0.32, FZ - 0.01) * rz(angle), "dark"))
end
local function mouth(w: number, h: number, x: number?, angle: number?): Spec
	return S("head", V(w, h, 0.04), CF(x or 0, -0.24, FZ - 0.01) * rz(angle or 0), "dark")
end
local MUSTACHE = S("head", V(0.5, 0.09, 0.07), CF(0, -0.12, FZ - 0.02), "hair")

local face = {
	smile = cat(
		eyes(),
		brows(0),
		mouth(0.36, 0.07),
		both(S("head", V(0.12, 0.06, 0.04), CF(-0.2, -0.2, FZ - 0.01) * rz(-30), "dark"))
	),
	calm = cat(eyes(), brows(0), mouth(0.28, 0.06)),
	grin = cat(
		eyes(),
		brows(-5),
		S("head", V(0.5, 0.16, 0.04), CF(0, -0.24, FZ - 0.015), "white"),
		S("head", V(0.56, 0.22, 0.03), CF(0, -0.24, FZ - 0.005), "dark")
	),
	smirk = cat(eyes(), brows(0), brows(-12, 0.36)[2], mouth(0.32, 0.07, 0.08, 12)),
	focused = cat(eyes(0.18, 0.1), brows(15), mouth(0.24, 0.06)),
	frown = cat(
		eyes(),
		brows(-10),
		mouth(0.32, 0.07),
		both(S("head", V(0.1, 0.06, 0.04), CF(-0.19, -0.29, FZ - 0.01) * rz(35), "dark"))
	),
	shout = cat(
		eyes(0.16, 0.16),
		brows(18),
		S("head", V(0.36, 0.26, 0.04), CF(0, -0.27, FZ - 0.01), "dark"),
		S("head", V(0.34, 0.06, 0.045), CF(0, -0.17, FZ - 0.015), "white")
	),
	snarl = cat(
		eyes(0.16, 0.12),
		brows(20),
		S("head", V(0.42, 0.1, 0.04), CF(0, -0.24, FZ - 0.015), "white"),
		S("head", V(0.48, 0.16, 0.03), CF(0, -0.24, FZ - 0.005), "dark")
	),
	fangs = cat(
		eyes(),
		brows(10),
		mouth(0.4, 0.07),
		both(S("head", V(0.06, 0.12, 0.045), CF(-0.12, -0.31, FZ - 0.015), "white"))
	),
	scar = cat(
		eyes(),
		brows(0),
		mouth(0.3, 0.06),
		S("head", V(0.05, 0.55, 0.045), CF(0.22, 0.12, FZ - 0.02) * rz(18), "glowRed", { alpha = 0.35 })
	),
}

local beard = {
	stubble = { S("head", V(0.95, 0.34, 0.04), CF(0, -0.42, FZ), "hair", { alpha = 0.45 }) },
	goatee = cat(S("head", V(0.28, 0.32, 0.1), CF(0, -0.5, FZ - 0.01), "hair"), MUSTACHE),
	full = cat(
		S("head", V(1.15, 0.5, 0.16), CF(0, -0.42, FZ + 0.03), "hair"),
		S("head", V(0.9, 0.22, 0.32), CF(0, -0.66, -0.48), "hair"),
		both(S("head", V(0.1, 0.62, 0.7), CF(-0.6, -0.18, -0.22), "hair")),
		MUSTACHE
	),
	strap = cat(
		S("head", V(1.1, 0.1, 0.3), CF(0, -0.64, -0.45), "hair"),
		both(S("head", V(0.08, 0.55, 0.12), CF(-0.6, -0.35, -0.45), "hair"))
	),
	chops = cat(both(S("head", V(0.12, 0.62, 0.55), CF(-0.6, -0.22, -0.25), "hair")), MUSTACHE),
	handlebar = cat(
		S("head", V(0.6, 0.1, 0.08), CF(0, -0.13, FZ - 0.02), "hair"),
		both(S("head", V(0.16, 0.16, 0.16), CF(-0.36, -0.05, FZ - 0.02), "hair", { shape = "Ball" }))
	),
	braid = cat(
		S("head", V(1.0, 0.4, 0.14), CF(0, -0.45, FZ + 0.02), "hair"),
		S("head", V(0.18, 0.6, 0.18), CF(0, -0.9, -0.55), "hair"),
		S("head", V(0.24, 0.08, 0.24), CF(0, -1.12, -0.55), "gold", { mat = Enum.Material.Metal }),
		MUSTACHE
	),
	long = cat(
		S("head", V(1.05, 1.0, 0.22), CF(0, -0.72, -0.5), "hair"),
		both(S("head", V(0.1, 0.62, 0.7), CF(-0.6, -0.18, -0.22), "hair")),
		MUSTACHE
	),
}

local MZ = FZ - 0.003 -- makeup sits on the skin, under the face pieces
local makeup = {
	liner = cat(
		both(S("head", V(0.26, 0.03, 0.03), CF(-0.22, -0.01, MZ), "dark")),
		both(S("head", V(0.1, 0.03, 0.03), CF(-0.37, 0.03, MZ) * rz(30), "dark"))
	),
	lips = { S("head", V(0.34, 0.1, 0.03), CF(0, -0.24, MZ), "p") },
	blush = both(S("head", V(0.2, 0.1, 0.03), CF(-0.34, -0.08, MZ), "a", { alpha = 0.5 })),
	freckles = cat(
		both(S("head", V(0.04, 0.04, 0.03), CF(-0.3, -0.04, MZ), "dark", { alpha = 0.4 })),
		both(S("head", V(0.04, 0.04, 0.03), CF(-0.36, -0.1, MZ), "dark", { alpha = 0.4 })),
		both(S("head", V(0.04, 0.04, 0.03), CF(-0.24, -0.1, MZ), "dark", { alpha = 0.4 }))
	),
	war = { S("head", V(1.02, 0.2, 0.03), CF(0, 0.1, MZ), "p") },
	lines = both(S("head", V(0.06, 0.34, 0.03), CF(-0.32, -0.16, MZ), "a")),
	tears = both(S("head", V(0.05, 0.3, 0.03), CF(-0.22, -0.13, MZ), "dark")),
	half = { S("head", V(0.6, 1.22, 0.03), CF(0.3, 0, MZ), "white") },
}

local TOP = 0.64 -- the head's top
local hat = {
	cap = cat(
		S("head", V(1.25, 0.36, 1.25), CF(0, TOP - 0.06, 0), "p"),
		S("head", V(1.0, 0.08, 0.6), CF(0, TOP - 0.18, -0.82), "s")
	),
	beanie = cat(
		S("head", V(1.28, 0.55, 1.28), CF(0, TOP - 0.08, 0), "p", { mat = Enum.Material.Fabric }),
		S("head", V(1.32, 0.18, 1.32), CF(0, TOP - 0.32, 0), "s", { mat = Enum.Material.Fabric })
	),
	headband = cat(
		S("head", V(1.24, 0.18, 1.24), CF(0, 0.36, 0), "p", { mat = Enum.Material.Fabric }),
		S("head", V(0.1, 0.42, 0.06), CF(0.16, 0.15, 0.66) * rx(20), "p", { mat = Enum.Material.Fabric })
	),
	shades = cat(
		both(S("head", V(0.36, 0.2, 0.06), CF(-0.22, 0.12, FZ - 0.04), "dark", { mat = Enum.Material.Glass })),
		S("head", V(0.12, 0.05, 0.05), CF(0, 0.16, FZ - 0.04), "dark"),
		both(S("head", V(0.05, 0.05, 0.9), CF(-0.62, 0.15, -0.18), "dark"))
	),
	goggles = cat(
		S("head", V(1.26, 0.12, 1.26), CF(0, 0.44, 0), "dark"),
		both(
			S(
				"head",
				V(0.3, 0.3, 0.16),
				CF(-0.24, 0.46, FZ - 0.05),
				"a",
				{ shape = "Ball", mat = Enum.Material.Glass }
			)
		)
	),
	visor = cat(
		S("head", V(1.25, 0.18, 1.25), CF(0, 0.12, 0.02), "dark"),
		S("head", V(1.0, 0.16, 0.06), CF(0, 0.12, FZ - 0.04), "a", { neon = true })
	),
	phones = cat(
		S("head", V(1.42, 0.1, 0.18), CF(0, TOP + 0.03, 0), "dark"),
		both(S("head", V(0.16, 0.42, 0.42), CF(-0.66, 0.05, 0), "p"))
	),
	brim = cat(
		S("head", V(0.9, 0.45, 0.9), CF(0, TOP + 0.16, 0), "p"),
		S("head", V(1.9, 0.07, 1.9), CF(0, TOP - 0.04, 0), "p"),
		S("head", V(0.92, 0.1, 0.92), CF(0, TOP + 0.0, 0), "s")
	),
	tophat = cat(
		S("head", V(0.85, 0.85, 0.85), CF(0, TOP + 0.4, 0), "dark"),
		S("head", V(1.35, 0.07, 1.35), CF(0, TOP, 0), "dark"),
		S("head", V(0.87, 0.14, 0.87), CF(0, TOP + 0.08, 0), "p")
	),
	streethood = cat(
		S("head", V(1.4, 0.18, 1.4), CF(0, TOP + 0.06, 0.05), "p", { mat = Enum.Material.Fabric }),
		S("head", V(1.4, 1.3, 0.16), CF(0, 0.05, 0.72), "p", { mat = Enum.Material.Fabric }),
		both(S("head", V(0.14, 1.3, 1.3), CF(-0.7, 0.05, 0.05), "p", { mat = Enum.Material.Fabric }))
	),
	crown = cat(
		S("head", V(1.25, 0.22, 1.25), CF(0, TOP - 0.02, 0), "gold", { mat = Enum.Material.Metal }),
		S("head", V(0.16, 0.3, 0.16), CF(0, TOP + 0.2, -0.55), "gold", { mat = Enum.Material.Metal }),
		both(
			S(
				"head",
				V(0.16, 0.26, 0.16),
				CF(-0.42, TOP + 0.18, -0.42),
				"gold",
				{ mat = Enum.Material.Metal }
			)
		),
		both(
			S("head", V(0.16, 0.26, 0.16), CF(-0.55, TOP + 0.18, 0.1), "gold", { mat = Enum.Material.Metal })
		),
		S("head", V(0.14, 0.14, 0.06), CF(0, TOP - 0.02, -0.64), "a", { neon = true })
	),
	horns = cat(
		both(S("head", V(0.2, 0.55, 0.2), CF(-0.45, TOP + 0.12, -0.05) * rz(25), "white")),
		both(S("head", V(0.12, 0.3, 0.12), CF(-0.62, TOP + 0.42, -0.05) * rz(50), "white"))
	),
	halo = {
		S(
			"head",
			V(0.06, 1.1, 1.1),
			CF(0, TOP + 0.45, 0) * FLAT,
			"a",
			{ shape = "Cylinder", neon = true, alpha = 0.2 }
		),
	},
	kabuto = cat(
		S("head", V(1.34, 0.5, 1.34), CF(0, TOP - 0.12, 0), "dark", { mat = Enum.Material.Metal }),
		both(S("head", V(0.14, 0.55, 0.95), CF(-0.7, 0.02, 0.12), "dark", { mat = Enum.Material.Metal })),
		S("head", V(0.9, 0.5, 0.06), CF(0, TOP + 0.3, -0.6), "gold", { mat = Enum.Material.Metal })
	),
	knight = cat(
		S("head", V(1.34, 1.42, 1.34), CF(0, 0.04, 0), "s", { mat = Enum.Material.Metal }),
		S("head", V(0.9, 0.08, 0.05), CF(0, 0.12, -0.69), "dark"),
		S("head", V(0.12, 0.4, 0.9), CF(0, TOP + 0.2, 0), "p")
	),
}
-- headwear that covers the hair (and the knight helm the face too)
local hatHidesHair = { beanie = true, streethood = true, kabuto = true, knight = true, tophat = false }
local hatHidesFace = { knight = true }

local GOLD = { mat = Enum.Material.Metal }
local ears = {
	studs = both(
		S(
			"head",
			V(0.08, 0.08, 0.08),
			CF(-0.61, -0.05, 0),
			"gold",
			{ shape = "Ball", mat = Enum.Material.Metal }
		)
	),
	hoops = both(
		S(
			"head",
			V(0.04, 0.24, 0.24),
			CF(-0.62, -0.2, 0),
			"gold",
			{ shape = "Cylinder", mat = Enum.Material.Metal }
		)
	),
	comms = cat(
		S("head", V(0.1, 0.26, 0.2), CF(0.63, 0.05, 0), "dark"),
		S("head", V(0.04, 0.06, 0.06), CF(0.69, 0.1, 0), "a", { neon = true }),
		S("head", V(0.04, 0.04, 0.5), CF(0.6, -0.16, -0.3), "dark")
	),
	dangles = cat(
		both(S("head", V(0.05, 0.3, 0.05), CF(-0.62, -0.22, 0), "gold", GOLD)),
		both(S("head", V(0.1, 0.1, 0.1), CF(-0.62, -0.4, 0), "a", { shape = "Ball", neon = true }))
	),
	cuffs = both(S("head", V(0.06, 0.3, 0.14), CF(-0.62, 0.1, 0.05), "s", { mat = Enum.Material.Metal })),
	wings = both(S("head", V(0.04, 0.3, 0.26), CF(-0.63, 0.16, 0.1) * rx(-20), "gold", GOLD)),
}

-- shoulders sit on the upper arms (left arm on -x: "outside" is -x; the mirror makes the right one)
local AT = 0.42 -- the upper arm's top
local function arms(spec: Spec): { Spec }
	return both(spec, "luarm", "ruarm")
end
local shoulders = {
	pads = arms(S("luarm", V(1.15, 0.3, 1.15), CF(0, AT + 0.04, 0), "p")),
	studded = cat(
		arms(S("luarm", V(1.15, 0.3, 1.15), CF(0, AT + 0.04, 0), "p")),
		arms(
			S(
				"luarm",
				V(0.12, 0.12, 0.12),
				CF(-0.3, AT + 0.22, 0),
				"gold",
				{ shape = "Ball", mat = Enum.Material.Metal }
			)
		),
		arms(
			S(
				"luarm",
				V(0.12, 0.12, 0.12),
				CF(0, AT + 0.22, 0),
				"gold",
				{ shape = "Ball", mat = Enum.Material.Metal }
			)
		)
	),
	epaulettes = cat(
		arms(S("luarm", V(1.0, 0.12, 0.85), CF(0, AT + 0.06, 0), "gold", GOLD)),
		arms(S("luarm", V(0.08, 0.26, 0.85), CF(-0.5, AT - 0.08, 0), "gold", GOLD))
	),
	fur = { S("torso", V(2.4, 0.38, 1.35), CF(0, 0.72, 0), "s", { mat = Enum.Material.Fabric }) },
	spikes = cat(
		arms(S("luarm", V(1.15, 0.3, 1.15), CF(0, AT + 0.04, 0), "p")),
		arms(S("luarm", V(0.14, 0.36, 0.14), CF(-0.2, AT + 0.3, 0) * rz(20), "white")),
		arms(S("luarm", V(0.14, 0.3, 0.14), CF(0.15, AT + 0.28, 0), "white"))
	),
	single = cat(
		S("luarm", V(1.32, 0.42, 1.32), CF(-0.05, AT + 0.06, 0), "s", { mat = Enum.Material.Metal }),
		S("luarm", V(1.36, 0.08, 1.36), CF(-0.05, AT - 0.14, 0), "a")
	),
	layered = cat(
		arms(S("luarm", V(1.2, 0.16, 1.2), CF(0, AT + 0.08, 0), "s", { mat = Enum.Material.Metal })),
		arms(
			S(
				"luarm",
				V(1.16, 0.16, 1.16),
				CF(-0.06, AT - 0.08, 0) * rz(12),
				"s",
				{ mat = Enum.Material.Metal }
			)
		),
		arms(
			S(
				"luarm",
				V(1.12, 0.16, 1.12),
				CF(-0.12, AT - 0.24, 0) * rz(24),
				"s",
				{ mat = Enum.Material.Metal }
			)
		)
	),
	pauldrons = cat(
		arms(S("luarm", V(1.5, 0.5, 1.42), CF(-0.15, AT + 0.08, 0), "s", { mat = Enum.Material.Metal })),
		arms(S("luarm", V(1.54, 0.08, 1.46), CF(-0.15, AT - 0.18, 0), "a"))
	),
	coils = cat(
		arms(
			S(
				"luarm",
				V(0.1, 1.16, 1.16),
				CF(0, AT - 0.1, 0) * FLAT,
				"a",
				{ shape = "Cylinder", neon = true }
			)
		),
		arms(
			S(
				"luarm",
				V(0.1, 1.16, 1.16),
				CF(0, AT - 0.3, 0) * FLAT,
				"a",
				{ shape = "Cylinder", neon = true }
			)
		)
	),
	crystal = cat(
		arms(
			S(
				"luarm",
				V(0.2, 0.55, 0.2),
				CF(-0.25, AT + 0.25, 0) * rz(25),
				"a",
				{ mat = Enum.Material.Glass }
			)
		),
		arms(
			S(
				"luarm",
				V(0.16, 0.45, 0.16),
				CF(0.05, AT + 0.22, 0.2) * rz(-10),
				"a",
				{ mat = Enum.Material.Glass }
			)
		),
		arms(
			S(
				"luarm",
				V(0.16, 0.4, 0.16),
				CF(0, AT + 0.2, -0.25) * rx(-15),
				"a",
				{ mat = Enum.Material.Glass }
			)
		)
	),
}

-- the upper torso is 2 x 1.6 x 1: its front at z = -0.5, its top at y = 0.8
local TZ = -0.52
local chainV = both(S("torso", V(0.06, 0.62, 0.06), CF(-0.2, 0.5, TZ) * rz(-30), "gold", GOLD))
local neck = {
	chain = chainV,
	pendant = cat(chainV, S("torso", V(0.2, 0.2, 0.2), CF(0, 0.2, TZ - 0.02), "a", { shape = "Ball" })),
	choker = { S("torso", V(0.7, 0.14, 0.6), CF(0, 0.86, 0), "dark") },
	tags = cat(
		chainV,
		S(
			"torso",
			V(0.16, 0.24, 0.03),
			CF(-0.04, 0.18, TZ - 0.02) * rz(8),
			"white",
			{ mat = Enum.Material.Metal }
		),
		S(
			"torso",
			V(0.16, 0.24, 0.03),
			CF(0.05, 0.16, TZ - 0.03) * rz(-6),
			"white",
			{ mat = Enum.Material.Metal }
		)
	),
	beads = cat(
		both(S("torso", V(0.12, 0.12, 0.12), CF(-0.3, 0.66, TZ), "a", { shape = "Ball" })),
		both(S("torso", V(0.12, 0.12, 0.12), CF(-0.2, 0.48, TZ), "s", { shape = "Ball" })),
		both(S("torso", V(0.12, 0.12, 0.12), CF(-0.1, 0.33, TZ), "a", { shape = "Ball" })),
		S("torso", V(0.14, 0.14, 0.14), CF(0, 0.26, TZ), "s", { shape = "Ball" })
	),
	collar = cat(
		S("torso", V(1.6, 0.6, 0.12), CF(0, 1.0, 0.45), "p"),
		both(S("torso", V(0.12, 0.5, 0.8), CF(-0.76, 0.95, 0.05), "p"))
	),
	amulet = cat(
		chainV,
		S("torso", V(0.26, 0.26, 0.06), CF(0, 0.22, TZ - 0.02) * rz(45), "a", { neon = true })
	),
	torc = { S("torso", V(1.0, 0.12, 0.76), CF(0, 0.8, -0.06), "gold", GOLD) },
}

local function forearms(spec: Spec): { Spec }
	return both(spec, "llarm", "rlarm")
end
local armsKit = {
	bracers = cat(
		forearms(S("llarm", V(1.08, 0.55, 1.08), CF(0, -0.1, 0), "s")),
		forearms(S("llarm", V(1.1, 0.08, 1.1), CF(0, 0.16, 0), "a"))
	),
	sleeves = arms(S("luarm", V(1.06, 0.87, 1.06), CF(0, 0, 0), "s", { mat = Enum.Material.Fabric })),
	wraps = cat(
		forearms(S("llarm", V(1.04, 0.72, 1.04), CF(0, -0.04, 0), "white", { mat = Enum.Material.Fabric })),
		forearms(S("llarm", V(1.06, 0.06, 1.06), CF(0, 0.05, 0) * rz(15), "dark"))
	),
	bands = cat(
		arms(S("luarm", V(1.06, 0.12, 1.06), CF(0, 0.12, 0), "a")),
		arms(S("luarm", V(1.06, 0.12, 1.06), CF(0, -0.08, 0), "a"))
	),
	tattoo = cat(
		arms(S("luarm", V(0.03, 0.62, 0.3), CF(-0.505, 0, 0), "dark", { alpha = 0.15 })),
		arms(S("luarm", V(0.03, 0.08, 0.6), CF(-0.505, 0.1, 0), "dark", { alpha = 0.15 }))
	),
	spikes = cat(
		forearms(S("llarm", V(0.12, 0.12, 0.32), CF(-0.56, 0.15, 0), "white")),
		forearms(S("llarm", V(0.12, 0.12, 0.32), CF(-0.56, -0.1, 0), "white"))
	),
	armor = cat(
		arms(S("luarm", V(1.1, 0.6, 1.1), CF(0, 0.02, 0), "s", { mat = Enum.Material.Metal })),
		forearms(S("llarm", V(1.1, 0.6, 1.1), CF(0, -0.05, 0), "s", { mat = Enum.Material.Metal }))
	),
	coils = cat(
		forearms(
			S("llarm", V(0.1, 1.12, 1.12), CF(0, 0.12, 0) * FLAT, "a", { shape = "Cylinder", neon = true })
		),
		forearms(
			S("llarm", V(0.1, 1.12, 1.12), CF(0, -0.15, 0) * FLAT, "a", { shape = "Cylinder", neon = true })
		)
	),
}

-- hands are 1 x 0.3 x 1; a ring sits on the front of the hand
local WB = -0.38 -- the bottom of the forearm (the wrist)
local wrist = {
	ring = { S("rhand", V(0.26, 0.1, 0.26), CF(0.2, -0.04, -0.42), "gold", GOLD) },
	bracelet = { S("llarm", V(1.08, 0.12, 1.08), CF(0, WB, 0), "gold", GOLD) },
	rings = both(S("lhand", V(0.26, 0.1, 0.26), CF(-0.2, -0.04, -0.42), "gold", GOLD), "lhand", "rhand"),
	cuffs = forearms(
		S("llarm", V(1.12, 0.26, 1.12), CF(0, WB + 0.06, 0), "s", { mat = Enum.Material.Metal })
	),
	beads = cat(
		S("llarm", V(1.08, 0.1, 1.08), CF(0, WB, 0), "a"),
		S("llarm", V(0.14, 0.14, 0.14), CF(0, WB, -0.55), "s", { shape = "Ball" })
	),
	power = forearms(S("llarm", V(1.1, 0.12, 1.1), CF(0, WB, 0), "a", { neon = true })),
}

-- the lower torso is 2 x 0.4 x 1 (the belt line)
local BZ = -0.54
local belt = {
	plain = cat(
		S("waist", V(2.06, 0.18, 1.06), CF(0, 0.05, 0), "dark", { mat = Enum.Material.Fabric }),
		S("waist", V(0.3, 0.2, 0.05), CF(0, 0.05, BZ), "gold", GOLD)
	),
	utility = cat(
		S("waist", V(2.06, 0.2, 1.06), CF(0, 0.05, 0), "s"),
		both(S("waist", V(0.3, 0.3, 0.2), CF(-0.7, 0, BZ - 0.06), "s")),
		both(S("waist", V(0.3, 0.3, 0.2), CF(-0.32, 0, BZ - 0.06), "s")),
		S("waist", V(0.26, 0.22, 0.06), CF(0, 0.05, BZ - 0.02), "a")
	),
	sash = cat(
		S("waist", V(2.08, 0.3, 1.08), CF(0, 0.05, 0), "p", { mat = Enum.Material.Fabric }),
		S(
			"waist",
			V(0.25, 0.7, 0.08),
			CF(0.7, -0.35, BZ - 0.02) * rz(10),
			"p",
			{ mat = Enum.Material.Fabric }
		)
	),
	rope = cat(
		S("waist", V(2.06, 0.12, 1.06), CF(0, 0.05, 0), "s", { mat = Enum.Material.Fabric }),
		S(
			"waist",
			V(0.2, 0.2, 0.2),
			CF(-0.5, 0.05, BZ - 0.04),
			"s",
			{ shape = "Ball", mat = Enum.Material.Fabric }
		),
		S("waist", V(0.08, 0.5, 0.08), CF(-0.5, -0.25, BZ - 0.04), "s", { mat = Enum.Material.Fabric })
	),
	chain = { S("waist", V(2.06, 0.1, 1.06), CF(0, 0.05, 0), "white", { mat = Enum.Material.Metal }) },
	holsters = cat(
		S("waist", V(2.06, 0.18, 1.06), CF(0, 0.05, 0), "dark"),
		both(S("lthigh", V(1.06, 0.12, 1.06), CF(0, 0.1, 0), "dark"), "lthigh", "rthigh"),
		both(S("lthigh", V(0.14, 0.5, 0.32), CF(-0.56, -0.02, 0), "s"), "lthigh", "rthigh")
	),
	tech = cat(
		S("waist", V(2.06, 0.2, 1.06), CF(0, 0.05, 0), "dark"),
		S("waist", V(0.36, 0.22, 0.06), CF(0, 0.05, BZ - 0.02), "a", { neon = true }),
		both(S("waist", V(0.1, 0.1, 0.05), CF(-0.6, 0.05, BZ - 0.01), "a", { neon = true }))
	),
	champion = cat(
		S("waist", V(2.06, 0.3, 1.06), CF(0, 0.05, 0), "gold", GOLD),
		S("waist", V(0.8, 0.5, 0.08), CF(0, 0.05, BZ - 0.04), "gold", GOLD),
		S("waist", V(0.2, 0.2, 0.06), CF(0, 0.05, BZ - 0.1), "a", { neon = true })
	),
}

-- legs: paint the upper and lower legs (colour roles), then add parts. Upper legs are "lthigh", lower "lshin".
local function thighs(spec: Spec): { Spec }
	return both(spec, "lthigh", "rthigh")
end
local function shins(spec: Spec): { Spec }
	return both(spec, "lshin", "rshin")
end
local legs = {
	pants = { paint = { "s", "s" }, parts = {} },
	shorts = {
		paint = { "s", "skin" },
		parts = thighs(S("lthigh", V(1.04, 0.1, 1.04), CF(0, -0.38, 0), "s")),
	},
	joggers = {
		paint = { "s", "s" },
		parts = shins(S("lshin", V(1.06, 0.14, 1.06), CF(0, -0.36, 0), "white")),
	},
	track = {
		paint = { "s", "s" },
		parts = cat(
			thighs(S("lthigh", V(0.04, 0.87, 0.3), CF(-0.51, 0, 0), "a")),
			shins(S("lshin", V(0.04, 0.87, 0.3), CF(-0.51, 0, 0), "a"))
		),
	},
	cargo = {
		paint = { "s", "s" },
		parts = thighs(S("lthigh", V(0.12, 0.36, 0.42), CF(-0.54, -0.1, 0), "s")),
	},
	kneepads = {
		paint = { "s", "s" },
		parts = shins(S("lshin", V(0.72, 0.3, 0.12), CF(0, 0.34, -0.53), "dark")),
	},
	ripped = {
		paint = { "s", "s" },
		parts = cat(
			S("lthigh", V(0.4, 0.15, 0.03), CF(0.1, -0.1, -0.505), "skin"),
			S("rshin", V(0.32, 0.12, 0.03), CF(-0.05, 0.2, -0.505), "skin")
		),
	},
	skirt = {
		paint = { "dark", "dark" },
		parts = { S("waist", V(2.2, 0.9, 1.25), CF(0, -0.55, 0), "p", { mat = Enum.Material.Fabric }) },
	},
	hakama = {
		paint = { "p", "p" },
		parts = cat(
			thighs(S("lthigh", V(1.25, 0.9, 1.25), CF(-0.08, 0, 0), "p", { mat = Enum.Material.Fabric })),
			shins(S("lshin", V(1.35, 0.9, 1.3), CF(-0.1, 0, 0), "p", { mat = Enum.Material.Fabric }))
		),
	},
	greaves = {
		paint = { "s", "s" },
		parts = shins(S("lshin", V(1.1, 0.75, 1.1), CF(0, -0.02, 0), "p", { mat = Enum.Material.Metal })),
	},
	legwraps = {
		paint = { "s", "s" },
		parts = shins(S("lshin", V(1.05, 0.8, 1.05), CF(0, 0, 0), "white", { mat = Enum.Material.Fabric })),
	},
	armored = {
		paint = { "dark", "dark" },
		parts = cat(
			thighs(S("lthigh", V(1.1, 0.6, 1.1), CF(0, 0.05, 0), "s", { mat = Enum.Material.Metal })),
			shins(S("lshin", V(1.1, 0.65, 1.1), CF(0, 0, 0), "s", { mat = Enum.Material.Metal }))
		),
	},
}

-- back bling sits on the upper torso's back (z = +0.5)
local KZ = 0.55
local function wingPair(color: string, extra: Spec?): { Spec }
	return cat(
		both(S("torso", V(0.1, 1.6, 0.9), CF(-0.8, 0.4, KZ + 0.3) * rz(-40), color, extra)),
		both(S("torso", V(0.1, 1.2, 0.7), CF(-1.35, 0.05, KZ + 0.35) * rz(-60), color, extra))
	)
end
local backpack = {
	backpack = cat(
		S("torso", V(1.4, 1.2, 0.6), CF(0, -0.05, KZ + 0.3), "s"),
		S("torso", V(1.42, 0.35, 0.62), CF(0, 0.45, KZ + 0.3), "p"),
		both(S("torso", V(0.15, 1.5, 0.06), CF(-0.5, 0, TZ), "s"))
	),
	sheath = cat(
		S("torso", V(0.3, 2.6, 0.25), CF(0, 0.1, KZ + 0.15) * rz(35), "dark"),
		S("torso", V(0.5, 0.08, 0.16), CF(-0.75, 1.17, KZ + 0.15) * rz(35), "gold", GOLD),
		S("torso", V(0.12, 0.55, 0.12), CF(-0.92, 1.42, KZ + 0.15) * rz(35), "s")
	),
	quiver = cat(
		S("torso", V(0.45, 1.5, 0.45), CF(0.5, 0.2, KZ + 0.25) * rz(-20), "s"),
		S("torso", V(0.08, 0.3, 0.08), CF(0.72, 1.05, KZ + 0.25) * rz(-20), "white"),
		S("torso", V(0.08, 0.3, 0.08), CF(0.6, 1.08, KZ + 0.25) * rz(-20), "white")
	),
	tanks = cat(
		both(
			S(
				"torso",
				V(1.4, 0.45, 0.45),
				CF(-0.3, 0, KZ + 0.25) * FLAT,
				"white",
				{ shape = "Cylinder", mat = Enum.Material.Metal }
			)
		),
		S("torso", V(0.7, 0.1, 0.1), CF(0, 0.6, KZ + 0.25), "dark")
	),
	jetpack = cat(
		S("torso", V(1.1, 1.2, 0.55), CF(0, 0, KZ + 0.28), "dark", { mat = Enum.Material.Metal }),
		both(S("torso", V(0.5, 0.36, 0.36), CF(-0.4, -0.75, KZ + 0.3) * FLAT, "s", { shape = "Cylinder" })),
		both(S("torso", V(0.2, 0.3, 0.2), CF(-0.4, -1.08, KZ + 0.3), "a", { neon = true, alpha = 0.2 }))
	),
	shield = cat(
		S("torso", V(0.15, 1.8, 1.8), CF(0, 0.1, KZ + 0.12) * ROT_Y, "p", { shape = "Cylinder" }),
		S("torso", V(0.4, 0.4, 0.4), CF(0, 0.1, KZ + 0.22), "a", { shape = "Ball" })
	),
	drone = cat(
		S(
			"torso",
			V(0.7, 0.7, 0.7),
			CF(0.9, 1.3, KZ + 0.4),
			"dark",
			{ shape = "Ball", mat = Enum.Material.Metal }
		),
		S("torso", V(0.22, 0.22, 0.1), CF(0.9, 1.3, KZ + 0.04), "a", { neon = true }),
		S("torso", V(0.08, 0.6, 0.08), CF(0.6, 0.85, KZ + 0.2) * rz(-35), "dark")
	),
	wings = wingPair("white", { mat = Enum.Material.Fabric }),
	bat = wingPair("dark"),
	ring = {
		S(
			"torso",
			V(0.08, 2.2, 2.2),
			CF(0, 0.6, KZ + 0.4) * ROT_Y,
			"a",
			{ shape = "Cylinder", neon = true, alpha = 0.25 }
		),
	},
	energy = wingPair("a", { neon = true, alpha = 0.35 }),
	rack = cat(
		S("torso", V(1.2, 1.6, 0.2), CF(0, 0, KZ + 0.15), "dark", { mat = Enum.Material.Metal }),
		S("torso", V(0.3, 1.0, 0.3), CF(-0.35, 0.2, KZ + 0.4), "s"),
		S("torso", V(0.5, 0.5, 0.3), CF(0.3, -0.1, KZ + 0.4), "a")
	),
}

-- extra hair styles (the head top is y = 0.64)
local hair = {
	afro = { S("head", V(1.75, 1.3, 1.65), CF(0, 0.5, 0.12), "hair", { shape = "Ball" }) },
	buns = cat(
		S("head", V(1.28, 0.3, 1.28), CF(0, TOP - 0.1, 0.02), "hair"),
		both(S("head", V(0.5, 0.5, 0.5), CF(-0.42, TOP + 0.14, 0.1), "hair", { shape = "Ball" }))
	),
	mohawk = { S("head", V(0.22, 0.55, 1.2), CF(0, TOP + 0.2, 0.05), "hair") },
	undercut = cat(
		S("head", V(1.0, 0.32, 1.26), CF(0, TOP - 0.02, 0), "hair"),
		S("head", V(0.9, 0.18, 0.5), CF(0.1, TOP + 0.1, -0.35) * rz(-10), "hair")
	),
	long = cat(
		S("head", V(1.3, 0.32, 1.3), CF(0, TOP - 0.08, 0.02), "hair"),
		S("head", V(1.3, 1.9, 0.3), CF(0, -0.45, 0.62), "hair"),
		both(S("head", V(0.14, 1.2, 0.8), CF(-0.66, -0.15, 0.2), "hair"))
	),
	bob = cat(
		S("head", V(1.32, 0.34, 1.32), CF(0, TOP - 0.1, 0.02), "hair"),
		S("head", V(1.32, 0.9, 0.3), CF(0, -0.05, 0.6), "hair"),
		both(S("head", V(0.16, 0.85, 1.0), CF(-0.66, 0, 0.1), "hair")),
		S("head", V(1.2, 0.2, 0.12), CF(0, 0.45, -0.62), "hair")
	),
	locs = cat(
		S("head", V(1.3, 0.3, 1.3), CF(0, TOP - 0.08, 0.02), "hair"),
		both(S("head", V(0.16, 1.2, 0.16), CF(-0.55, -0.2, 0.3), "hair")),
		both(S("head", V(0.16, 1.3, 0.16), CF(-0.3, -0.25, 0.6), "hair")),
		S("head", V(0.16, 1.3, 0.16), CF(0, -0.25, 0.65), "hair")
	),
	pony = cat(
		S("head", V(1.28, 0.3, 1.28), CF(0, TOP - 0.08, 0.02), "hair"),
		S("head", V(0.3, 0.3, 0.3), CF(0, TOP + 0.05, 0.5), "hair", { shape = "Ball" }),
		S("head", V(0.3, 1.2, 0.3), CF(0, 0.2, 0.75) * rx(-20), "hair")
	),
	curly = cat(
		S("head", V(1.3, 0.3, 1.3), CF(0, TOP - 0.08, 0.02), "hair"),
		S("head", V(0.45, 0.45, 0.45), CF(-0.3, TOP + 0.08, -0.2), "hair", { shape = "Ball" }),
		S("head", V(0.5, 0.5, 0.5), CF(0.2, TOP + 0.12, 0), "hair", { shape = "Ball" }),
		S("head", V(0.45, 0.45, 0.45), CF(-0.1, TOP + 0.08, 0.35), "hair", { shape = "Ball" })
	),
	sideshave = cat(
		S("head", V(0.7, 0.36, 1.28), CF(0.28, TOP - 0.04, 0), "hair"),
		S("head", V(0.2, 0.9, 1.0), CF(0.62, 0.05, 0.1), "hair")
	),
}

return {
	beard = beard,
	face = face,
	makeup = makeup,
	hat = hat,
	ears = ears,
	shoulders = shoulders,
	neck = neck,
	arms = armsKit,
	wrist = wrist,
	belt = belt,
	legs = legs,
	backpack = backpack,
	hair = hair,
	hatHidesHair = hatHidesHair,
	hatHidesFace = hatHidesFace,
}
