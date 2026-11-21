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
-- headwear that covers the hair (and the knight helm the face too). pt-fit (2026-11-19): the crowned hats (cap,
-- brim, tophat, beret) too, as Roblox catalog hair rises 0.15 to 0.9 studs over the head and swallowed them
local hatHidesHair = {
	beanie = true,
	streethood = true,
	kabuto = true,
	knight = true,
	tophat = true,
	cap = true,
	brim = true,
	beret = true,
}
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
	-- the fallback parts before Art.Backs' meshes load (backs.py angel and devil)
	angel = wingPair("white", { mat = Enum.Material.Fabric }),
	devil = wingPair("dark", { mat = Enum.Material.Leather }),
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

-- 2026-11-17: toward the creator plan's launch counts (head area). Same blocky style and roles as above.
-- PLACEHOLDER ART like the rest.
local CAP = S("head", V(1.28, 0.3, 1.28), CF(0, TOP - 0.08, 0.02), "hair")
local function spike(x: number, y: number, z: number, h: number, tilt: number, lean: number): Spec
	return S("head", V(0.32, h, 0.32), CF(x, y, z) * rz(tilt) * rx(lean), "hair", { shape = "Wedge" })
end

-- hair: 20 more styles
hair.spikes = cat(
	CAP,
	spike(0, TOP + 0.25, 0.1, 0.6, 0, -25),
	spike(-0.35, TOP + 0.18, 0.05, 0.5, 25, -20),
	spike(0.35, TOP + 0.18, 0.05, 0.5, -25, -20),
	spike(-0.2, TOP + 0.1, 0.45, 0.5, 15, -50),
	spike(0.2, TOP + 0.1, 0.45, 0.5, -15, -50)
)
hair.quiff = cat(CAP, S("head", V(1.0, 0.4, 0.55), CF(0, TOP + 0.12, -0.35) * rx(-20), "hair"))
hair.sidepart = cat(
	S("head", V(1.3, 0.3, 1.3), CF(0, TOP - 0.06, 0.02), "hair"),
	S("head", V(0.8, 0.14, 0.4), CF(0.2, TOP + 0.08, -0.4) * rz(-8), "hair"),
	both(S("head", V(0.12, 0.5, 0.9), CF(-0.64, 0.25, 0.15), "hair"))
)
hair.bangs = cat(
	CAP,
	S("head", V(0.7, 0.55, 0.12), CF(-0.18, 0.28, FZ - 0.04) * rz(-12), "hair"),
	both(S("head", V(0.12, 0.7, 0.9), CF(-0.64, 0.15, 0.15), "hair"))
)
hair.messy = cat(
	CAP,
	S("head", V(0.4, 0.3, 0.4), CF(-0.3, TOP + 0.12, -0.2) * rz(20), "hair"),
	S("head", V(0.45, 0.3, 0.4), CF(0.25, TOP + 0.14, 0.1) * rz(-15), "hair"),
	S("head", V(0.35, 0.28, 0.35), CF(0, TOP + 0.1, 0.45) * rx(25), "hair"),
	S("head", V(0.3, 0.25, 0.3), CF(0.35, TOP + 0.05, -0.35) * rz(-30), "hair")
)
hair.braids = cat(
	CAP,
	both(S("head", V(0.2, 1.3, 0.2), CF(-0.5, -0.45, 0.25), "hair")),
	both(S("head", V(0.24, 0.1, 0.24), CF(-0.5, -1.12, 0.25), "a"))
)
hair.rows = cat(
	S("head", V(1.24, 0.12, 1.24), CF(0, TOP - 0.02, 0.02), "hair"),
	S("head", V(0.12, 0.08, 1.2), CF(-0.3, TOP + 0.06, 0.02), "hair"),
	S("head", V(0.12, 0.08, 1.2), CF(0, TOP + 0.06, 0.02), "hair"),
	S("head", V(0.12, 0.08, 1.2), CF(0.3, TOP + 0.06, 0.02), "hair")
)
hair.buzz = { S("head", V(1.22, 0.12, 1.22), CF(0, TOP - 0.02, 0.01), "hair", { alpha = 0.15 }) }
hair.topbun = cat(CAP, S("head", V(0.5, 0.45, 0.5), CF(0, TOP + 0.28, 0.1), "hair", { shape = "Ball" }))
hair.pigs = cat(
	CAP,
	both(S("head", V(0.32, 0.32, 0.32), CF(-0.68, 0.2, 0.25), "a", { shape = "Ball" })),
	both(S("head", V(0.3, 1.0, 0.3), CF(-0.85, -0.2, 0.3) * rz(-15), "hair"))
)
hair.shaggy = cat(
	S("head", V(1.34, 0.36, 1.34), CF(0, TOP - 0.06, 0.02), "hair"),
	S("head", V(1.34, 0.7, 0.3), CF(0, 0.05, 0.6), "hair"),
	both(S("head", V(0.16, 0.6, 1.0), CF(-0.66, 0.15, 0.1), "hair")),
	S("head", V(1.1, 0.22, 0.14), CF(0, 0.42, -0.62) * rx(10), "hair")
)
hair.slick = cat(
	S("head", V(1.26, 0.22, 1.3), CF(0, TOP - 0.02, 0.04), "hair"),
	S("head", V(1.2, 0.45, 0.2), CF(0, 0.3, 0.64), "hair")
)
hair.wolf = cat(
	CAP,
	S("head", V(1.2, 0.5, 0.3), CF(0, 0.2, 0.62), "hair"),
	S("head", V(0.9, 0.5, 0.25), CF(0, -0.25, 0.66) * rx(10), "hair"),
	both(S("head", V(0.14, 0.75, 0.8), CF(-0.66, 0.05, 0.2), "hair")),
	S("head", V(0.9, 0.2, 0.12), CF(0, 0.45, -0.62), "hair")
)
hair.hime = cat(
	CAP,
	S("head", V(1.22, 0.22, 0.1), CF(0, 0.42, -0.63), "hair"),
	both(S("head", V(0.14, 1.1, 0.35), CF(-0.66, -0.15, -0.35), "hair")),
	S("head", V(1.3, 2.0, 0.28), CF(0, -0.5, 0.62), "hair")
)
hair.flame = cat(
	CAP,
	spike(0, TOP + 0.35, 0.05, 0.8, 0, -8),
	spike(-0.32, TOP + 0.25, 0.1, 0.6, 18, -10),
	spike(0.32, TOP + 0.25, 0.1, 0.6, -18, -10),
	spike(0, TOP + 0.2, 0.45, 0.6, 0, -30)
)
hair.super = cat(
	CAP,
	spike(0, TOP + 0.45, 0.05, 1.0, 0, -5),
	spike(-0.4, TOP + 0.35, 0, 0.85, 30, -5),
	spike(0.4, TOP + 0.35, 0, 0.85, -30, -5),
	spike(-0.25, TOP + 0.3, 0.45, 0.8, 18, -35),
	spike(0.25, TOP + 0.3, 0.45, 0.8, -18, -35),
	spike(0, TOP + 0.05, -0.55, 0.35, 0, 30)
)
hair.sidebraid = cat(
	CAP,
	S("head", V(0.24, 1.3, 0.24), CF(0.55, -0.45, -0.1), "hair"),
	S("head", V(0.28, 0.1, 0.28), CF(0.55, -1.12, -0.1), "a")
)
hair.fauxhawk = cat(
	S("head", V(1.1, 0.16, 1.24), CF(0, TOP - 0.02, 0.02), "hair"),
	S("head", V(0.4, 0.35, 1.0), CF(0, TOP + 0.15, -0.05), "hair")
)
hair.drills = cat(
	CAP,
	S("head", V(1.22, 0.2, 0.1), CF(0, 0.42, -0.63), "hair"),
	both(S("head", V(0.36, 0.36, 1.2), CF(-0.75, -0.35, 0.1) * rx(90), "hair", { shape = "Cylinder" }))
)

hair.crownbraid = cat(
	S("head", V(1.26, 0.22, 1.26), CF(0, TOP - 0.04, 0.02), "hair"),
	S("head", V(1.36, 0.18, 1.36), CF(0, 0.38, 0.02), "hair", { mat = Enum.Material.Fabric })
)

-- facial hair: 7 more
beard.soul = { S("head", V(0.12, 0.14, 0.06), CF(0, -0.38, FZ - 0.02), "hair") }
beard.pencil = { S("head", V(0.42, 0.04, 0.05), CF(0, -0.13, FZ - 0.02), "hair") }
beard.horseshoe = cat(
	S("head", V(0.5, 0.09, 0.07), CF(0, -0.12, FZ - 0.02), "hair"),
	both(S("head", V(0.09, 0.3, 0.07), CF(-0.22, -0.3, FZ - 0.02), "hair"))
)
beard.anchor = cat(
	MUSTACHE,
	S("head", V(0.5, 0.1, 0.08), CF(0, -0.44, FZ - 0.01), "hair"),
	S("head", V(0.14, 0.24, 0.08), CF(0, -0.55, FZ - 0.01), "hair")
)
beard.boxed = cat(S("head", V(1.12, 0.42, 0.16), CF(0, -0.44, FZ + 0.03), "hair"), MUSTACHE)
beard.forked = cat(
	S("head", V(1.0, 0.36, 0.14), CF(0, -0.44, FZ + 0.03), "hair"),
	both(S("head", V(0.18, 0.4, 0.14), CF(-0.16, -0.78, FZ + 0.05) * rz(10), "hair")),
	MUSTACHE
)
beard.wizard = cat(
	S("head", V(1.1, 0.5, 0.18), CF(0, -0.42, FZ + 0.03), "hair"),
	S("head", V(0.6, 0.9, 0.18), CF(0, -1.05, FZ + 0.06), "hair", { shape = "Wedge" }),
	MUSTACHE
)

-- faces: 15 more (brows, eyes and mouth together)
face.happy = cat(
	eyes(0.16, 0.08),
	brows(0),
	mouth(0.4, 0.08),
	both(S("head", V(0.1, 0.06, 0.04), CF(-0.22, -0.19, FZ - 0.01) * rz(-35), "dark"))
)
face.wink = cat(
	eyes()[1],
	S("head", V(0.18, 0.05, 0.04), CF(0.22, 0.08, FZ - 0.01), "dark"),
	brows(0),
	mouth(0.3, 0.07, 0.06, 10)
)
face.tired = cat(eyes(0.16, 0.08), brows(-8, 0.24), mouth(0.26, 0.05))
face.surprised =
	cat(eyes(0.16, 0.24), brows(0, 0.4), S("head", V(0.18, 0.2, 0.04), CF(0, -0.27, FZ - 0.01), "dark"))
face.angry = cat(
	eyes(0.16, 0.12),
	brows(25),
	mouth(0.34, 0.06),
	both(S("head", V(0.08, 0.06, 0.04), CF(-0.2, -0.28, FZ - 0.01) * rz(30), "dark"))
)
face.smug = cat(eyes(0.16, 0.1), brows(-15), mouth(0.3, 0.06, 0.1, 18))
face.determined = cat(eyes(0.18, 0.12), brows(18), mouth(0.36, 0.05))
face.sleepy = cat(
	both(S("head", V(0.18, 0.04, 0.04), CF(-0.22, 0.08, FZ - 0.01), "dark", { eye = true })),
	brows(-5, 0.26),
	mouth(0.16, 0.08)
)
face.toothy = cat(
	eyes(),
	brows(0),
	S("head", V(0.46, 0.12, 0.04), CF(0, -0.24, FZ - 0.015), "white"),
	S("head", V(0.02, 0.12, 0.045), CF(0, -0.24, FZ - 0.02), "dark")
)
face.stern = cat(eyes(0.16, 0.12), brows(8, 0.28), mouth(0.4, 0.05))
face.cheeky = cat(
	eyes(),
	brows(-5),
	mouth(0.3, 0.07),
	S("head", V(0.1, 0.1, 0.045), CF(0.05, -0.32, FZ - 0.015), "glowRed")
)
face.battle = cat(
	eyes(0.16, 0.12),
	brows(22),
	mouth(0.34, 0.06),
	S("head", V(0.3, 0.05, 0.045), CF(-0.22, 0.32, FZ - 0.02) * rz(-40), "glowRed", { alpha = 0.3 })
)
face.cool = cat(eyes(0.2, 0.08), brows(-3), mouth(0.24, 0.05, 0.05, 6))
face.stitched = cat(
	eyes(),
	brows(0),
	mouth(0.36, 0.05),
	S("head", V(0.04, 0.3, 0.045), CF(-0.1, -0.24, FZ - 0.02), "dark"),
	S("head", V(0.04, 0.3, 0.045), CF(0.1, -0.24, FZ - 0.02), "dark")
)
face.joker = cat(
	eyes(0.18, 0.18),
	brows(-20),
	mouth(0.5, 0.08),
	both(S("head", V(0.12, 0.06, 0.04), CF(-0.27, -0.18, FZ - 0.01) * rz(-35), "dark"))
)

-- makeup: 12 more
makeup.shadow = both(S("head", V(0.28, 0.12, 0.03), CF(-0.22, 0.2, MZ), "p", { alpha = 0.3 }))
makeup.wing = cat(
	both(S("head", V(0.26, 0.03, 0.03), CF(-0.22, -0.01, MZ), "dark")),
	both(S("head", V(0.16, 0.04, 0.03), CF(-0.4, 0.06, MZ) * rz(40), "dark"))
)
makeup.mask = { S("head", V(1.04, 0.24, 0.03), CF(0, 0.1, MZ), "dark") }
makeup.stripes = cat(
	both(S("head", V(0.3, 0.06, 0.03), CF(-0.32, -0.04, MZ) * rz(10), "p")),
	both(S("head", V(0.3, 0.06, 0.03), CF(-0.32, -0.16, MZ) * rz(10), "p"))
)
makeup.dots = cat(
	both(S("head", V(0.06, 0.06, 0.03), CF(-0.22, 0.34, MZ), "a")),
	both(S("head", V(0.06, 0.06, 0.03), CF(-0.32, 0.3, MZ), "a")),
	S("head", V(0.08, 0.08, 0.03), CF(0, 0.4, MZ), "a")
)
makeup.mark = { S("head", V(0.12, 0.16, 0.03), CF(0, 0.38, MZ) * rz(45), "a", { neon = true }) }
makeup.star = { S("head", V(0.16, 0.16, 0.03), CF(0.3, 0.12, MZ) * rz(45), "a") }
makeup.tribal = cat(
	both(S("head", V(0.05, 0.4, 0.03), CF(-0.42, 0.1, MZ) * rz(20), "p")),
	both(S("head", V(0.05, 0.3, 0.03), CF(-0.32, -0.25, MZ) * rz(-25), "p"))
)
makeup.clown = cat(
	S("head", V(0.14, 0.14, 0.03), CF(0, -0.1, MZ - 0.01), "glowRed"),
	both(S("head", V(0.14, 0.26, 0.03), CF(-0.22, 0.12, MZ), "p"))
)
makeup.glitter = cat(
	both(S("head", V(0.05, 0.05, 0.03), CF(-0.3, 0.02, MZ), "a", { neon = true })),
	both(S("head", V(0.04, 0.04, 0.03), CF(-0.38, -0.06, MZ), "a", { neon = true })),
	both(S("head", V(0.04, 0.04, 0.03), CF(-0.28, -0.12, MZ), "a", { neon = true }))
)
makeup.lightning = { S("head", V(0.08, 0.5, 0.03), CF(-0.25, 0.1, MZ) * rz(20), "a", { neon = true }) }
makeup.skull = cat(
	both(S("head", V(0.3, 0.26, 0.03), CF(-0.22, 0.1, MZ), "dark")),
	S("head", V(0.1, 0.1, 0.03), CF(0, -0.08, MZ), "dark"),
	S("head", V(0.5, 0.06, 0.03), CF(0, -0.26, MZ), "dark")
)

-- ears: 4 more
ears.gauges =
	both(S("head", V(0.08, 0.2, 0.2), CF(-0.62, -0.05, 0.05) * rz(90), "dark", { shape = "Cylinder" }))
ears.chain = cat(
	both(
		S(
			"head",
			V(0.06, 0.06, 0.06),
			CF(-0.62, -0.1, 0),
			"gold",
			{ shape = "Ball", mat = Enum.Material.Metal }
		)
	),
	both(S("head", V(0.04, 0.4, 0.04), CF(-0.64, -0.32, 0.05), "gold", { mat = Enum.Material.Metal }))
)
ears.gems =
	both(S("head", V(0.1, 0.1, 0.1), CF(-0.62, -0.08, 0), "a", { shape = "Ball", mat = Enum.Material.Glass }))
ears.fins = both(S("head", V(0.06, 0.4, 0.5), CF(-0.66, 0.1, 0.1), "p", { shape = "Wedge" }))

-- headwear: 10 more (the head top is y = 0.64)
hat.dorag = cat(
	S("head", V(1.28, 0.42, 1.3), CF(0, TOP - 0.12, 0.02), "p", { mat = Enum.Material.Fabric }),
	S("head", V(0.3, 0.5, 0.08), CF(0, 0.05, 0.66) * rx(15), "p", { mat = Enum.Material.Fabric })
)
hat.beret = {
	S("head", V(1.3, 0.24, 1.25), CF(0.12, TOP + 0.04, 0.05) * rz(-10), "p", { mat = Enum.Material.Fabric }),
}
hat.bucket = cat(
	S("head", V(1.26, 0.42, 1.26), CF(0, TOP - 0.02, 0), "p", { mat = Enum.Material.Fabric }),
	S("head", V(1.6, 0.08, 1.6), CF(0, TOP - 0.22, 0), "p", { mat = Enum.Material.Fabric })
)
hat.catears = cat(
	S("head", V(1.24, 0.1, 0.16), CF(0, TOP - 0.02, 0.05), "dark"),
	both(S("head", V(0.1, 0.38, 0.32), CF(-0.38, TOP + 0.18, 0.05) * rz(12), "p", { shape = "Wedge" }))
)
hat.antlers = cat(
	both(S("head", V(0.1, 0.6, 0.1), CF(-0.35, TOP + 0.25, 0.05) * rz(25), "s")),
	both(S("head", V(0.08, 0.3, 0.08), CF(-0.52, TOP + 0.45, 0.05) * rz(-20), "s")),
	both(S("head", V(0.08, 0.28, 0.08), CF(-0.28, TOP + 0.52, 0.05) * rz(40), "s"))
)
hat.hachimaki = cat(
	S("head", V(1.25, 0.16, 1.25), CF(0, 0.34, 0), "white", { mat = Enum.Material.Fabric }),
	S("head", V(0.22, 0.12, 0.05), CF(0, 0.34, -0.64), "glowRed"),
	both(
		S("head", V(0.08, 0.5, 0.06), CF(-0.1, 0.12, 0.67) * rz(15), "white", { mat = Enum.Material.Fabric })
	)
)
hat.tiara = cat(
	S("head", V(1.22, 0.08, 1.22), CF(0, 0.42, 0), "gold", { mat = Enum.Material.Metal }),
	S("head", V(0.2, 0.25, 0.06), CF(0, 0.52, -0.62) * rz(45), "a", { mat = Enum.Material.Glass })
)
hat.laurel = cat(
	both(S("head", V(0.12, 0.14, 1.0), CF(-0.58, 0.4, 0.05) * rx(8), "gold", { mat = Enum.Material.Metal })),
	both(S("head", V(0.18, 0.08, 0.3), CF(-0.62, 0.48, -0.25), "gold", { mat = Enum.Material.Metal }))
)
hat.lens = cat(
	S("head", V(0.08, 0.1, 0.9), CF(0.63, 0.1, -0.15), "dark"),
	S("head", V(0.32, 0.26, 0.05), CF(0.38, 0.12, FZ - 0.06), "a", { neon = true, alpha = 0.3 })
)
hat.aviator = cat(
	S("head", V(1.3, 0.4, 1.3), CF(0, TOP - 0.1, 0.02), "s", { mat = Enum.Material.Leather }),
	both(S("head", V(0.12, 0.6, 0.45), CF(-0.64, 0.05, 0.05), "s", { mat = Enum.Material.Leather })),
	both(
		S(
			"head",
			V(0.3, 0.3, 0.14),
			CF(-0.24, TOP - 0.04, -0.6),
			"a",
			{ shape = "Ball", mat = Enum.Material.Glass }
		)
	)
)
hatHidesHair.dorag = true
hatHidesHair.bucket = true
hatHidesHair.aviator = true

-- masks (the Masks slot's 2026-11-17 extras; LookKit falls back here for kits it does not have)
local head = {}
head.ninja = cat(
	S("head", V(1.28, 0.62, 1.28), CF(0, -0.32, 0), "dark", { mat = Enum.Material.Fabric }),
	S("head", V(1.28, 0.24, 1.28), CF(0, 0.45, 0), "dark", { mat = Enum.Material.Fabric })
)
head.skull = cat(
	S("head", V(1.22, 1.3, 0.1), CF(0, 0, FZ - 0.03), "white"),
	both(S("head", V(0.3, 0.26, 0.04), CF(-0.24, 0.12, FZ - 0.09), "dark")),
	S("head", V(0.1, 0.12, 0.04), CF(0, -0.08, FZ - 0.09), "dark"),
	S("head", V(0.5, 0.06, 0.04), CF(0, -0.32, FZ - 0.09), "dark")
)
head.gasmask = cat(
	S("head", V(1.0, 0.75, 0.2), CF(0, -0.05, FZ - 0.05), "dark", { mat = Enum.Material.Rubber }),
	both(
		S(
			"head",
			V(0.3, 0.3, 0.06),
			CF(-0.24, 0.14, FZ - 0.16),
			"a",
			{ shape = "Ball", mat = Enum.Material.Glass }
		)
	),
	S("head", V(0.36, 0.36, 0.3), CF(0, -0.32, FZ - 0.25) * rx(90), "s", { shape = "Cylinder" })
)
head.fullface = cat(
	S("head", V(1.22, 1.3, 0.1), CF(0, 0, FZ - 0.03), "p"),
	S("head", V(0.9, 0.12, 0.04), CF(0, 0.14, FZ - 0.09), "a", { neon = true })
)
head.oni = cat(
	S("head", V(1.15, 1.2, 0.12), CF(0, 0, FZ - 0.04), "glowRed"),
	both(S("head", V(0.16, 0.4, 0.2), CF(-0.42, 0.68, -0.45) * rz(15), "white", { shape = "Wedge" })),
	S("head", V(0.6, 0.1, 0.04), CF(0, -0.28, FZ - 0.11), "white"),
	both(S("head", V(0.28, 0.08, 0.04), CF(-0.24, 0.24, FZ - 0.11) * rz(20), "dark"))
)
head.fox = cat(
	S("head", V(1.1, 1.0, 0.1), CF(0, 0.08, FZ - 0.03), "white"),
	S("head", V(0.4, 0.3, 0.3), CF(0, -0.18, FZ - 0.18), "white", { shape = "Wedge" }),
	both(S("head", V(0.12, 0.42, 0.3), CF(-0.4, 0.68, -0.4) * rz(15), "white", { shape = "Wedge" })),
	both(S("head", V(0.26, 0.05, 0.04), CF(-0.24, 0.16, FZ - 0.09) * rz(-20), "glowRed"))
)
head.nightMask = cat( -- H8: Hero Pass season 1 (Opening Night Mask)
	S("head", V(1.2, 0.36, 0.08), CF(0, 0.16, FZ - 0.03), "dark"),
	S("head", V(1.24, 0.06, 0.08), CF(0, 0.36, FZ - 0.05), "gold", GOLD),
	both(S("head", V(0.24, 0.08, 0.04), CF(-0.24, 0.16, FZ - 0.08), "white", { neon = true })),
	both(S("head", V(0.3, 0.14, 0.06), CF(-0.62, 0.22, FZ + 0.02) * rz(25), "gold", GOLD))
)
head.goalie = cat(
	S("head", V(1.2, 1.28, 0.1), CF(0, 0, FZ - 0.03), "white"),
	S("head", V(0.08, 0.5, 0.04), CF(-0.2, -0.2, FZ - 0.09), "dark"),
	S("head", V(0.08, 0.5, 0.04), CF(0.2, -0.2, FZ - 0.09), "dark"),
	S("head", V(0.08, 0.5, 0.04), CF(0, -0.2, FZ - 0.09), "dark"),
	both(S("head", V(0.26, 0.2, 0.04), CF(-0.24, 0.16, FZ - 0.09), "dark"))
)
head.respirator = cat(
	S("head", V(0.8, 0.45, 0.16), CF(0, -0.3, FZ - 0.04), "s", { mat = Enum.Material.Metal }),
	both(S("head", V(0.24, 0.24, 0.2), CF(-0.38, -0.32, FZ - 0.08) * ROT_Y, "dark", { shape = "Cylinder" }))
)
head.eyepatch = cat(
	S("head", V(0.3, 0.26, 0.06), CF(0.22, 0.12, FZ - 0.03), "dark"),
	S("head", V(1.26, 0.05, 1.26), CF(0, 0.2, 0) * rz(-12), "dark")
)
head.monovisor = cat(
	S("head", V(1.3, 0.5, 1.3), CF(0, 0.12, 0), "p", { mat = Enum.Material.Metal }),
	S("head", V(0.9, 0.08, 0.06), CF(0, 0.12, FZ - 0.07), "a", { neon = true })
)
head.welder = cat(
	S("head", V(1.25, 1.1, 0.14), CF(0, -0.05, FZ - 0.05), "s", { mat = Enum.Material.Metal }),
	S("head", V(0.8, 0.2, 0.05), CF(0, 0.15, FZ - 0.13), "dark", { mat = Enum.Material.Glass })
)
head.masquerade = cat(
	S("head", V(1.0, 0.32, 0.08), CF(0, 0.13, FZ - 0.02), "p"),
	both(S("head", V(0.14, 0.4, 0.06), CF(-0.55, 0.38, FZ - 0.02) * rz(30), "a", { shape = "Wedge" }))
)
head.techmask = cat(
	S("head", V(1.0, 0.5, 0.14), CF(0, -0.28, FZ - 0.04), "dark", { mat = Enum.Material.Metal }),
	both(S("head", V(0.06, 0.2, 0.04), CF(-0.25, -0.28, FZ - 0.12), "a", { neon = true })),
	S("head", V(0.06, 0.2, 0.04), CF(0, -0.28, FZ - 0.12), "a", { neon = true })
)
head.crystal = cat(
	S("head", V(1.18, 0.6, 0.12), CF(0, 0.1, FZ - 0.04), "a", { mat = Enum.Material.Glass, alpha = 0.2 }),
	S("head", V(0.3, 0.5, 0.3), CF(0, 0.72, -0.2) * rz(45), "a", { mat = Enum.Material.Glass, alpha = 0.2 })
)
local maskHidesHair = { ninja = true }

-- tops: the Suits slot's 2026-11-17 extras. Each has its body paint (torso, arms, legs colour roles, like
-- LookKit's SUIT_COLORS) and its parts. The upper torso's front is z = -0.5, its top y = 0.8.
local suitPaint = {}
local suit = {}
local function top(name: string, paint: { string }, parts: { Spec })
	suitPaint[name] = paint
	suit[name] = parts
end
local FABRIC = { mat = Enum.Material.Fabric }
local METAL = { mat = Enum.Material.Metal }
local GLOW = { neon = true }
top("tee", { "p", "skin", "s" }, arms(S("luarm", V(1.08, 0.42, 1.08), CF(0, 0.24, 0), "p", FABRIC)))
top("tank", { "p", "skin", "s" }, {
	S("torso", V(0.8, 0.08, 0.04), CF(0, 0.62, TZ), "s"),
	S("torso", V(1.0, 0.08, 0.04), CF(0, 0.7, -TZ), "s"),
})
top(
	"hoodie",
	{ "p", "p", "s" },
	cat(
		S("torso", V(1.3, 0.5, 0.4), CF(0, 0.75, 0.6), "p", FABRIC),
		S("torso", V(1.2, 0.4, 0.06), CF(0, -0.45, TZ), "p", FABRIC),
		both(S("torso", V(0.05, 0.4, 0.04), CF(-0.15, 0.45, TZ - 0.03), "white"))
	)
)
top(
	"varsity",
	{ "p", "s", "s" },
	cat(
		S("torso", V(0.4, 0.45, 0.04), CF(-0.5, 0.3, TZ), "white"),
		S("waist", V(2.06, 0.14, 1.06), CF(0, 0.12, 0), "s"),
		both(S("llarm", V(1.06, 0.1, 1.06), CF(0, -0.32, 0), "white"), "llarm", "rlarm")
	)
)
top(
	"tracksuit",
	{ "p", "p", "p" },
	cat(
		S("torso", V(0.06, 1.5, 0.04), CF(0, 0, TZ), "white", METAL),
		arms(S("luarm", V(0.04, 0.87, 0.24), CF(-0.51, 0, 0), "white")),
		both(S("llarm", V(0.04, 0.87, 0.24), CF(-0.51, 0, 0), "white"), "llarm", "rlarm")
	)
)
top(
	"trench",
	{ "s", "s", "dark" },
	cat(
		both(S("torso", V(0.55, 1.6, 0.1), CF(-0.72, 0, TZ - 0.02), "s", FABRIC)),
		S("torso", V(2.1, 0.35, 1.12), CF(0, 0.72, 0.02), "s", FABRIC),
		both(S("lthigh", V(1.1, 0.9, 1.1), CF(-0.04, 0.02, 0.02), "s", FABRIC), "lthigh", "rthigh")
	)
)
top(
	"labcoat",
	{ "white", "white", "dark" },
	cat(
		both(
			S("torso", V(0.12, 0.8, 0.35), CF(-0.3, 0.35, TZ - 0.08) * rz(-20), "white", { shape = "Wedge" })
		),
		S("torso", V(0.4, 0.35, 0.04), CF(0.55, 0.2, TZ - 0.02), "white"),
		S("torso", V(0.06, 0.2, 0.04), CF(0.48, 0.32, TZ - 0.05), "a"),
		both(S("lthigh", V(1.08, 0.7, 1.08), CF(0, 0.12, 0), "white", FABRIC), "lthigh", "rthigh")
	)
)
top(
	"tux",
	{ "dark", "dark", "dark" },
	cat(
		S("torso", V(0.55, 1.2, 0.04), CF(0, 0.2, TZ), "white"),
		S("torso", V(0.4, 0.14, 0.08), CF(0, 0.66, TZ - 0.04), "a"),
		S("torso", V(0.08, 0.08, 0.04), CF(0, 0.2, TZ - 0.03), "dark", { shape = "Ball" })
	)
)
-- H8: Hero Pass season 1's Opening Night set (PLACEHOLDER ART until the art pass)
top(
	"nightTux",
	{ "dark", "dark", "dark" },
	cat(
		S("torso", V(0.55, 1.2, 0.04), CF(0, 0.2, TZ), "white"),
		both(S("torso", V(0.12, 0.9, 0.05), CF(-0.32, 0.35, TZ - 0.03) * rz(-15), "gold", GOLD)),
		S("torso", V(0.16, 0.16, 0.05), CF(0.55, 0.45, TZ - 0.04), "gold", { shape = "Ball", neon = true }),
		S("waist", V(2.1, 0.22, 1.1), CF(0, 0.12, 0), "gold", GOLD)
	)
)
-- anime outfits (nate's playtest 4, 2026-11-20: "more anime outfits"; the drawn overlays in art/clothes/suits.py
-- carry the look on Roblox's body, these parts are the fallback before the images load)
top(
	"blazer",
	{ "p", "p", "s" },
	cat(
		S("torso", V(0.36, 0.7, 0.04), CF(0, 0.45, TZ), "white"),
		S("torso", V(0.1, 0.5, 0.05), CF(0, 0.45, TZ - 0.02), "dark")
	)
)
top("sailor", { "white", "white", "s" }, {
	S("torso", V(1.6, 0.5, 0.04), CF(0, 0.55, -TZ), "s", FABRIC),
	S("torso", V(0.3, 0.2, 0.05), CF(0, 0.3, TZ), "s", FABRIC),
})
top(
	"pilot",
	{ "p", "s", "p" },
	cat(
		S("torso", V(1.2, 0.12, 1.1), CF(0, 0.76, 0), "a"),
		both(S("llarm", V(1.08, 0.4, 1.08), CF(0, -0.2, 0), "a"), "llarm", "rlarm")
	)
)
top(
	"haori",
	{ "p", "p", "s" },
	cat(
		both(S("torso", V(0.16, 1.9, 0.05), CF(-0.42, 0.05, TZ), "s", FABRIC)),
		both(S("llarm", V(1.3, 0.8, 1.4), CF(-0.1, -0.1, 0.1), "s", FABRIC), "llarm", "rlarm")
	)
)
top(
	"gakuran",
	{ "p", "p", "p" },
	cat(
		S("torso", V(1.1, 0.16, 1.06), CF(0, 0.8, 0), "p"),
		S("torso", V(0.08, 0.08, 0.04), CF(0.1, 0.4, TZ), "gold", { shape = "Ball" }),
		S("torso", V(0.08, 0.08, 0.04), CF(0.1, 0.1, TZ), "gold", { shape = "Ball" })
	)
)
top(
	"officer",
	{ "p", "p", "s" },
	cat(
		both(S("torso", V(0.5, 0.08, 1.04), CF(-0.75, 0.82, 0), "a")),
		S("torso", V(0.14, 2.1, 0.04), CF(0, 0, TZ) * rz(40), "a", FABRIC)
	)
)
top(
	"vest",
	{ "p", "skin", "s" },
	cat(
		both(S("torso", V(0.75, 1.5, 0.1), CF(-0.6, -0.02, TZ - 0.02), "s")),
		both(S("torso", V(0.75, 1.5, 0.1), CF(-0.6, -0.02, -TZ + 0.02), "s"))
	)
)
top(
	"kimono",
	{ "p", "p", "p" },
	cat(
		S("torso", V(0.3, 1.9, 0.06), CF(0.1, 0.05, TZ) * rz(-30), "s", FABRIC),
		S("waist", V(2.1, 0.32, 1.1), CF(0, 0.08, 0), "s", FABRIC),
		both(S("llarm", V(1.3, 0.8, 1.4), CF(-0.1, -0.1, 0.1), "p", FABRIC), "llarm", "rlarm")
	)
)
top(
	"gi",
	{ "white", "white", "white" },
	cat(
		both(S("torso", V(0.2, 1.3, 0.06), CF(-0.2, 0.2, TZ) * rz(-25), "white", FABRIC)),
		S("waist", V(2.08, 0.16, 1.08), CF(0, 0.1, 0), "dark", FABRIC),
		both(S("waist", V(0.1, 0.45, 0.04), CF(-0.15, -0.2, BZ - 0.02) * rz(-10), "dark", FABRIC))
	)
)
top(
	"spacesuit",
	{ "white", "white", "white" },
	cat(
		S("torso", V(0.9, 0.6, 0.25), CF(0, 0.05, TZ - 0.1), "s", METAL),
		S("torso", V(0.15, 0.15, 0.06), CF(-0.2, 0.1, TZ - 0.25), "a", GLOW),
		S("torso", V(1.3, 0.2, 1.1), CF(0, 0.82, 0), "s", METAL),
		both(S("lshin", V(0.7, 0.35, 0.14), CF(0, 0.3, -0.53), "s"), "lshin", "rshin")
	)
)
top(
	"racing",
	{ "p", "s", "p" },
	cat(
		S("torso", V(2.04, 0.3, 1.04), CF(0, 0.1, 0) * rz(20), "a"),
		both(S("llarm", V(0.6, 0.3, 0.14), CF(0, 0.32, 0.53), "dark"), "llarm", "rlarm"),
		both(S("lthigh", V(0.04, 0.87, 0.24), CF(-0.51, 0, 0), "a"), "lthigh", "rthigh")
	)
)
top(
	"wetsuit",
	{ "dark", "dark", "dark" },
	cat(
		both(S("torso", V(0.04, 1.6, 0.2), CF(-1.01, 0, 0), "a")),
		both(S("lthigh", V(0.04, 0.87, 0.2), CF(-0.51, 0, 0), "a"), "lthigh", "rthigh"),
		S("torso", V(0.06, 0.8, 0.04), CF(0, 0.4, -TZ), "s", METAL)
	)
)
top(
	"plate",
	{ "s", "s", "s" },
	cat(
		S("torso", V(1.7, 1.3, 0.3), CF(0, 0.15, TZ - 0.08), "s", METAL),
		S("torso", V(0.7, 1.4, 0.05), CF(0, -0.2, TZ - 0.25), "p", FABRIC),
		both(S("torso", V(0.4, 0.4, 0.06), CF(-0.6, -0.55, TZ - 0.08), "s", METAL))
	)
)
top(
	"shinobi",
	{ "dark", "dark", "dark" },
	cat(
		S("waist", V(2.08, 0.25, 1.08), CF(0, 0.08, 0), "s", FABRIC),
		both(S("llarm", V(1.05, 0.6, 1.05), CF(0, -0.08, 0), "s", FABRIC), "llarm", "rlarm"),
		both(S("lshin", V(1.05, 0.5, 1.05), CF(0, -0.15, 0), "s", FABRIC), "lshin", "rshin")
	)
)
top(
	"exo",
	{ "dark", "dark", "dark" },
	cat(
		S("torso", V(0.5, 0.5, 0.2), CF(0, 0.2, TZ - 0.08), "a", GLOW),
		both(S("torso", V(0.12, 1.4, 0.12), CF(-0.6, 0, TZ - 0.06), "s", METAL)),
		arms(S("luarm", V(0.12, 0.8, 0.12), CF(-0.52, 0, 0), "s", METAL)),
		both(S("lshin", V(0.12, 0.8, 0.12), CF(-0.52, 0, 0), "s", METAL), "lshin", "rshin")
	)
)
top(
	"royal",
	{ "p", "p", "s" },
	cat(
		S("torso", V(2.04, 0.1, 1.04), CF(0, 0.75, 0), "gold", GOLD),
		S("torso", V(0.08, 1.4, 0.04), CF(0, 0, TZ), "gold", GOLD),
		both(
			S(
				"torso",
				V(0.1, 0.1, 0.06),
				CF(-0.2, 0.3, TZ - 0.02),
				"gold",
				{ shape = "Ball", mat = Enum.Material.Metal }
			)
		),
		both(
			S(
				"torso",
				V(0.1, 0.1, 0.06),
				CF(-0.2, -0.1, TZ - 0.02),
				"gold",
				{ shape = "Ball", mat = Enum.Material.Metal }
			)
		)
	)
)
top(
	"fatigues",
	{ "s", "s", "s" },
	cat(
		both(S("torso", V(0.45, 0.4, 0.08), CF(-0.5, 0.3, TZ - 0.02), "s")),
		S("torso", V(0.6, 0.35, 0.04), CF(0.2, -0.3, TZ - 0.01), "dark", { alpha = 0.3 }),
		S("torso", V(0.4, 0.3, 0.04), CF(-0.5, -0.45, TZ - 0.01), "dark", { alpha = 0.3 })
	)
)
top(
	"puffer",
	{ "p", "p", "s" },
	cat(
		S("torso", V(2.2, 0.42, 1.2), CF(0, 0.5, 0), "p", FABRIC),
		S("torso", V(2.2, 0.42, 1.2), CF(0, 0.04, 0), "p", FABRIC),
		S("torso", V(2.2, 0.42, 1.2), CF(0, -0.42, 0), "p", FABRIC),
		arms(S("luarm", V(1.2, 0.5, 1.2), CF(0, 0.1, 0), "p", FABRIC))
	)
)
top(
	"overalls",
	{ "p", "p", "s" },
	cat(
		S("torso", V(1.2, 0.9, 0.08), CF(0, -0.35, TZ - 0.02), "s", FABRIC),
		both(S("torso", V(0.18, 0.9, 0.06), CF(-0.5, 0.35, TZ - 0.02), "s", FABRIC)),
		both(
			S(
				"torso",
				V(0.12, 0.12, 0.06),
				CF(-0.5, 0.0, TZ - 0.06),
				"gold",
				{ shape = "Ball", mat = Enum.Material.Metal }
			)
		)
	)
)
top(
	"bomber",
	{ "s", "s", "dark" },
	cat(
		S("torso", V(2.1, 0.3, 1.15), CF(0, 0.78, 0), "white", FABRIC),
		S("waist", V(2.06, 0.18, 1.06), CF(0, 0.14, 0), "dark", FABRIC),
		both(S("llarm", V(1.06, 0.14, 1.06), CF(0, -0.34, 0), "dark", FABRIC), "llarm", "rlarm"),
		S("torso", V(0.3, 0.1, 0.04), CF(-0.55, 0.3, TZ - 0.01), "a")
	)
)
top(
	"sweater",
	{ "p", "p", "s" },
	cat(
		S("torso", V(1.4, 0.3, 1.2), CF(0, 0.82, 0), "p", FABRIC),
		S("torso", V(2.04, 0.14, 1.04), CF(0, 0.15, 0), "s"),
		S("torso", V(2.04, 0.14, 1.04), CF(0, -0.15, 0), "white")
	)
)
top(
	"jersey",
	{ "p", "p", "s" },
	cat(
		S("torso", V(0.3, 0.6, 0.04), CF(-0.2, 0.05, TZ), "white"),
		S("torso", V(0.3, 0.6, 0.04), CF(0.2, 0.05, TZ), "white"),
		S("torso", V(0.7, 0.12, 0.3), CF(0, 0.75, TZ + 0.1), "s"),
		arms(S("luarm", V(1.08, 0.1, 1.08), CF(0, 0.05, 0), "s"))
	)
)
top(
	"ranger",
	{ "s", "s", "dark" },
	cat(
		S("torso", V(0.18, 2.2, 0.06), CF(0, 0, TZ - 0.02) * rz(35), "dark", { mat = Enum.Material.Leather }),
		S("torso", V(0.18, 2.2, 0.06), CF(0, 0, TZ - 0.03) * rz(-35), "dark", { mat = Enum.Material.Leather }),
		both(
			S("torso", V(0.28, 0.28, 0.16), CF(-0.65, -0.5, TZ - 0.06), "s", { mat = Enum.Material.Leather })
		)
	)
)
top(
	"robe",
	{ "p", "p", "p" },
	cat(
		S("waist", V(2.3, 1.6, 1.3), CF(0, -0.9, 0.02), "p", FABRIC),
		both(S("llarm", V(1.3, 0.9, 1.4), CF(-0.12, -0.15, 0.1), "p", FABRIC), "llarm", "rlarm"),
		S("torso", V(0.3, 0.3, 0.04), CF(0, 0.2, TZ) * rz(45), "a", GLOW)
	)
)
top(
	"cyber",
	{ "dark", "dark", "dark" },
	cat(
		S("torso", V(0.06, 0.9, 0.04), CF(-0.3, 0.1, TZ) * rz(30), "a", GLOW),
		S("torso", V(0.06, 0.9, 0.04), CF(0.3, 0.1, TZ) * rz(-30), "a", GLOW),
		S("torso", V(0.6, 0.06, 0.04), CF(0, -0.3, TZ), "a", GLOW),
		arms(S("luarm", V(1.06, 0.06, 1.06), CF(0, -0.2, 0), "a", GLOW))
	)
)
top(
	"magma",
	{ "dark", "dark", "dark" },
	cat(
		S("torso", V(0.08, 0.8, 0.04), CF(-0.2, 0.2, TZ) * rz(20), "glowRed", GLOW),
		S("torso", V(0.08, 0.6, 0.04), CF(0.25, -0.2, TZ) * rz(-35), "glowRed", GLOW),
		S("torso", V(0.5, 0.08, 0.04), CF(0.1, -0.45, TZ) * rz(10), "glowRed", GLOW),
		both(S("lthigh", V(0.04, 0.6, 0.08), CF(-0.51, 0, 0) * rx(20), "glowRed", GLOW), "lthigh", "rthigh")
	)
)
top(
	"frost",
	{ "white", "white", "white" },
	cat(
		arms(S("luarm", V(0.2, 0.5, 0.2), CF(-0.3, 0.62, 0) * rz(25), "ice", { mat = Enum.Material.Glass })),
		S("torso", V(0.3, 0.5, 0.15), CF(0, 0.15, TZ - 0.05) * rz(45), "ice", { mat = Enum.Material.Glass }),
		S("waist", V(2.06, 0.1, 1.06), CF(0, 0.15, 0), "ice", { mat = Enum.Material.Glass })
	)
)
top(
	"starfield",
	{ "dark", "dark", "dark" },
	cat(
		S("torso", V(0.1, 0.1, 0.04), CF(-0.5, 0.4, TZ), "white", { shape = "Ball", neon = true }),
		S("torso", V(0.08, 0.08, 0.04), CF(0.3, 0.55, TZ), "white", { shape = "Ball", neon = true }),
		S("torso", V(0.12, 0.12, 0.04), CF(0.15, -0.1, TZ), "a", { shape = "Ball", neon = true }),
		S("torso", V(0.08, 0.08, 0.04), CF(-0.25, -0.4, TZ), "white", { shape = "Ball", neon = true }),
		S("torso", V(0.1, 0.1, 0.04), CF(0.6, -0.35, TZ), "white", { shape = "Ball", neon = true }),
		arms(S("luarm", V(0.04, 0.08, 0.08), CF(-0.51, 0.1, 0), "white", { neon = true }))
	)
)

-- shoulders: 10 more
shoulders.mantle = { S("torso", V(2.5, 0.25, 1.4), CF(0, 0.8, 0.05), "p", FABRIC) }
shoulders.feathers = cat(
	arms(S("luarm", V(0.1, 0.5, 0.5), CF(-0.5, AT, 0) * rz(30), "white", FABRIC)),
	arms(S("luarm", V(0.1, 0.45, 0.45), CF(-0.42, AT + 0.1, 0.25) * rz(40), "a", FABRIC)),
	arms(S("luarm", V(0.1, 0.45, 0.45), CF(-0.42, AT + 0.1, -0.25) * rz(40), "a", FABRIC))
)
shoulders.scales = cat(
	arms(S("luarm", V(1.12, 0.14, 1.12), CF(-0.04, AT + 0.04, 0) * rz(10), "s", METAL)),
	arms(S("luarm", V(1.08, 0.14, 1.08), CF(-0.08, AT - 0.1, 0) * rz(18), "p", METAL))
)
shoulders.riveted = cat(
	arms(S("luarm", V(1.2, 0.36, 1.2), CF(-0.04, AT + 0.04, 0), "s", METAL)),
	arms(S("luarm", V(0.08, 0.08, 0.08), CF(-0.62, AT, 0.3), "white", { shape = "Ball" })),
	arms(S("luarm", V(0.08, 0.08, 0.08), CF(-0.62, AT, -0.3), "white", { shape = "Ball" }))
)
shoulders.plume = cat(
	S("luarm", V(1.2, 0.3, 1.2), CF(0, AT + 0.04, 0), "gold", GOLD),
	S("luarm", V(0.14, 0.7, 0.4), CF(-0.2, AT + 0.5, 0) * rz(15), "a", FABRIC)
)
shoulders.wingtips =
	arms(S("luarm", V(0.1, 0.6, 0.6), CF(-0.35, AT + 0.3, 0.2) * rz(35), "white", { shape = "Wedge" }))
shoulders.shell = arms(S("luarm", V(1.3, 0.7, 1.3), CF(-0.08, AT, 0), "p", { shape = "Ball" }))
shoulders.gears = cat(
	arms(
		S(
			"luarm",
			V(0.12, 0.8, 0.8),
			CF(-0.56, AT - 0.08, 0),
			"s",
			{ shape = "Cylinder", mat = Enum.Material.Metal }
		)
	),
	arms(
		S(
			"luarm",
			V(0.14, 0.3, 0.3),
			CF(-0.6, AT - 0.08, 0),
			"gold",
			{ shape = "Cylinder", mat = Enum.Material.Metal }
		)
	)
)
shoulders.flames = cat(
	arms(
		S(
			"luarm",
			V(0.2, 0.5, 0.2),
			CF(-0.2, AT + 0.2, 0.15) * rz(10),
			"glowRed",
			{ neon = true, alpha = 0.25 }
		)
	),
	arms(
		S(
			"luarm",
			V(0.16, 0.4, 0.16),
			CF(-0.05, AT + 0.18, -0.2) * rz(-10),
			"a",
			{ neon = true, alpha = 0.25 }
		)
	)
)
shoulders.blades = cat(
	arms(S("luarm", V(1.1, 0.24, 1.1), CF(0, AT + 0.04, 0), "dark", METAL)),
	arms(
		S(
			"luarm",
			V(0.06, 0.7, 0.3),
			CF(-0.35, AT + 0.35, 0) * rz(35),
			"white",
			{ shape = "Wedge", mat = Enum.Material.Metal }
		)
	)
)

-- neck: 7 more
neck.scarf = cat(
	S("torso", V(1.0, 0.3, 0.8), CF(0, 0.85, -0.05), "p", FABRIC),
	S("torso", V(0.3, 0.8, 0.08), CF(0.3, 0.3, TZ - 0.05) * rz(8), "p", FABRIC)
)
neck.kerchief = cat(
	S("torso", V(0.8, 0.12, 0.7), CF(0, 0.84, -0.04), "s", FABRIC),
	S("torso", V(0.6, 0.45, 0.05), CF(0, 0.55, TZ - 0.02) * rz(45), "s", FABRIC)
)
neck.medal = cat(
	both(S("torso", V(0.12, 0.6, 0.04), CF(-0.12, 0.55, TZ) * rz(-15), "a", FABRIC)),
	S(
		"torso",
		V(0.3, 0.3, 0.08),
		CF(0, 0.2, TZ - 0.03) * ROT_Y,
		"gold",
		{ shape = "Cylinder", mat = Enum.Material.Metal }
	)
)
neck.whistle = cat(chainV, S("torso", V(0.3, 0.12, 0.12), CF(0, 0.2, TZ - 0.05), "white", METAL))
neck.fang = cat(
	S("torso", V(0.9, 0.06, 0.7), CF(0, 0.82, -0.04), "dark", { mat = Enum.Material.Leather }),
	S("torso", V(0.12, 0.3, 0.1), CF(0, 0.55, TZ - 0.02), "white", { shape = "Wedge" })
)
neck.neckphones = cat(
	S("torso", V(1.0, 0.14, 0.14), CF(0, 0.86, 0.35), "dark"),
	both(S("torso", V(0.22, 0.4, 0.4), CF(-0.48, 0.86, -0.05) * ROT_Y, "s", { shape = "Cylinder" }))
)
neck.ruff = {
	S(
		"torso",
		V(0.3, 1.5, 1.5),
		CF(0, 0.85, 0) * FLAT,
		"white",
		{ shape = "Cylinder", mat = Enum.Material.Fabric }
	),
}

-- arms: 7 more
armsKit.elbowpads =
	forearms(S("llarm", V(0.7, 0.3, 0.14), CF(0, 0.32, 0.53), "dark", { mat = Enum.Material.Rubber }))
armsKit.rolled = cat(
	arms(S("luarm", V(1.06, 0.87, 1.06), CF(0, 0, 0), "white", FABRIC)),
	forearms(S("llarm", V(1.1, 0.2, 1.1), CF(0, 0.32, 0), "white", FABRIC))
)
armsKit.chains = cat(
	forearms(S("llarm", V(1.06, 0.08, 1.06), CF(0, 0.1, 0) * rz(12), "white", METAL)),
	forearms(S("llarm", V(1.06, 0.08, 1.06), CF(0, -0.15, 0) * rz(-12), "white", METAL))
)
armsKit.fins = forearms(S("llarm", V(0.1, 0.7, 0.5), CF(-0.55, 0, 0.2) * rx(15), "a", { shape = "Wedge" }))
armsKit.runes = cat(
	arms(S("luarm", V(1.04, 0.1, 1.04), CF(0, 0.1, 0), "a", GLOW)),
	arms(S("luarm", V(0.03, 0.3, 0.3), CF(-0.52, -0.15, 0) * rx(45), "a", GLOW))
)
armsKit.scales = cat(
	forearms(S("llarm", V(1.08, 0.2, 1.08), CF(0, 0.2, 0) * rz(8), "p", METAL)),
	forearms(S("llarm", V(1.08, 0.2, 1.08), CF(0, 0, 0) * rz(8), "s", METAL)),
	forearms(S("llarm", V(1.08, 0.2, 1.08), CF(0, -0.2, 0) * rz(8), "p", METAL))
)
armsKit.longsleeve = cat(
	arms(S("luarm", V(1.05, 0.87, 1.05), CF(0, 0, 0), "s", FABRIC)),
	forearms(S("llarm", V(1.05, 0.87, 1.05), CF(0, 0, 0), "s", FABRIC))
)

-- gloves: the Gloves slot's 2026-11-17 extras. The hands are 1 x 0.3 x 1 (the wrist is y = 0.15).
local function hands(spec: Spec): { Spec }
	return both(spec, "lhand", "rhand")
end
local GLOVE = V(1.06, 0.34, 1.06)
local handsKit = {
	boxing = cat(
		hands(S("lhand", V(1.3, 0.6, 1.3), CF(0, -0.12, -0.05), "p", { shape = "Ball" })),
		forearms(S("llarm", V(1.08, 0.2, 1.08), CF(0, WB + 0.04, 0), "white"))
	),
	knuckle = cat(
		hands(S("lhand", GLOVE, CF(0, 0, 0), "dark", { mat = Enum.Material.Leather })),
		hands(S("lhand", V(0.9, 0.14, 0.14), CF(0, -0.05, -0.55), "s", METAL))
	),
	mittens = cat(
		hands(S("lhand", V(1.1, 0.4, 1.1), CF(0, -0.02, 0), "p", FABRIC)),
		forearms(S("llarm", V(1.12, 0.14, 1.12), CF(0, WB, 0), "white", FABRIC))
	),
	work = cat(
		hands(S("lhand", GLOVE, CF(0, 0, 0), "s", { mat = Enum.Material.Leather })),
		forearms(S("llarm", V(1.14, 0.3, 1.14), CF(0, WB + 0.08, 0), "s", { mat = Enum.Material.Leather }))
	),
	tech = cat(
		hands(S("lhand", GLOVE, CF(0, 0, 0), "dark")),
		hands(S("lhand", V(0.04, 0.06, 0.9), CF(-0.54, 0, 0), "a", GLOW)),
		hands(S("lhand", V(0.3, 0.06, 0.04), CF(0, 0, -0.54), "a", GLOW))
	),
	crystal = cat(
		hands(S("lhand", GLOVE, CF(0, 0, 0), "s")),
		hands(
			S("lhand", V(0.2, 0.4, 0.2), CF(-0.3, 0.05, -0.45) * rz(30), "a", { mat = Enum.Material.Glass })
		),
		hands(
			S(
				"lhand",
				V(0.16, 0.32, 0.16),
				CF(0.2, 0.05, -0.48) * rz(-20),
				"a",
				{ mat = Enum.Material.Glass }
			)
		)
	),
	talons = cat(
		hands(S("lhand", GLOVE, CF(0, 0, 0), "dark")),
		hands(S("lhand", V(0.08, 0.35, 0.08), CF(-0.3, -0.3, -0.45), "white", { shape = "Wedge" })),
		hands(S("lhand", V(0.08, 0.35, 0.08), CF(0, -0.3, -0.45), "white", { shape = "Wedge" })),
		hands(S("lhand", V(0.08, 0.35, 0.08), CF(0.3, -0.3, -0.45), "white", { shape = "Wedge" }))
	),
	flame = cat(
		hands(S("lhand", GLOVE, CF(0, 0, 0), "dark")),
		hands(
			S(
				"lhand",
				V(0.5, 0.6, 0.5),
				CF(0, -0.3, 0),
				"glowRed",
				{ neon = true, alpha = 0.35, shape = "Ball" }
			)
		)
	),
}

-- shoes: the Boots slot's 2026-11-17 extras. The feet are 1 x 0.3 x 1 (the toe is z = -0.5).
local function feet(spec: Spec): { Spec }
	return both(spec, "lfoot", "rfoot")
end
local SHOE = V(1.06, 0.34, 1.1)
local feetKit = {
	sandals = cat(
		feet(S("lfoot", V(1.04, 0.08, 1.1), CF(0, -0.15, -0.03), "s", { mat = Enum.Material.Leather })),
		feet(S("lfoot", V(1.04, 0.06, 0.12), CF(0, 0.05, -0.3), "s", { mat = Enum.Material.Leather }))
	),
	hightops = cat(
		feet(S("lfoot", SHOE, CF(0, 0, -0.04), "white")),
		feet(S("lfoot", V(1.08, 0.08, 1.12), CF(0, -0.14, -0.04), "dark")),
		shins(S("lshin", V(1.06, 0.35, 1.06), CF(0, -0.26, 0), "white"))
	),
	geta = cat(
		feet(S("lfoot", V(1.0, 0.1, 1.1), CF(0, -0.18, -0.03), "s", { mat = Enum.Material.Wood })),
		feet(S("lfoot", V(0.9, 0.2, 0.15), CF(0, -0.32, -0.3), "s", { mat = Enum.Material.Wood })),
		feet(S("lfoot", V(0.9, 0.2, 0.15), CF(0, -0.32, 0.3), "s", { mat = Enum.Material.Wood }))
	),
	tabi = cat(
		feet(S("lfoot", SHOE, CF(0, 0, -0.04), "dark", FABRIC)),
		feet(S("lfoot", V(0.04, 0.3, 0.3), CF(0.15, 0, -0.45), "s", FABRIC)),
		shins(S("lshin", V(1.06, 0.3, 1.06), CF(0, -0.28, 0), "dark", FABRIC))
	),
	combat = cat(
		feet(S("lfoot", V(1.08, 0.38, 1.14), CF(0, 0, -0.04), "dark", { mat = Enum.Material.Leather })),
		shins(S("lshin", V(1.08, 0.5, 1.08), CF(0, -0.2, 0), "dark", { mat = Enum.Material.Leather })),
		shins(S("lshin", V(1.1, 0.06, 1.1), CF(0, -0.1, 0), "s"))
	),
	moon = cat(
		feet(S("lfoot", V(1.2, 0.45, 1.2), CF(0, 0.02, -0.04), "white")),
		shins(S("lshin", V(1.2, 0.5, 1.2), CF(0, -0.2, 0), "white")),
		shins(S("lshin", V(1.22, 0.08, 1.22), CF(0, 0.05, 0), "a"))
	),
	skates = cat(
		feet(S("lfoot", SHOE, CF(0, 0, -0.04), "p")),
		feet(S("lfoot", V(0.2, 0.2, 0.2), CF(-0.25, -0.25, -0.35) * ROT_Y, "dark", { shape = "Cylinder" })),
		feet(S("lfoot", V(0.2, 0.2, 0.2), CF(-0.25, -0.25, 0.3) * ROT_Y, "dark", { shape = "Cylinder" })),
		feet(S("lfoot", V(0.2, 0.2, 0.2), CF(0.25, -0.25, -0.35) * ROT_Y, "dark", { shape = "Cylinder" })),
		feet(S("lfoot", V(0.2, 0.2, 0.2), CF(0.25, -0.25, 0.3) * ROT_Y, "dark", { shape = "Cylinder" }))
	),
	flippers = cat(
		feet(S("lfoot", SHOE, CF(0, 0, -0.04), "dark", { mat = Enum.Material.Rubber })),
		feet(S("lfoot", V(1.1, 0.06, 1.3), CF(0, -0.15, -1.1), "a", { mat = Enum.Material.Rubber }))
	),
	hover = cat(
		feet(S("lfoot", SHOE, CF(0, 0, -0.04), "s", METAL)),
		feet(
			S(
				"lfoot",
				V(0.06, 0.9, 0.9),
				CF(0, -0.22, 0) * FLAT,
				"a",
				{ shape = "Cylinder", neon = true, alpha = 0.2 }
			)
		)
	),
	spikes = cat(
		feet(S("lfoot", SHOE, CF(0, 0, -0.04), "dark")),
		shins(S("lshin", V(0.12, 0.3, 0.12), CF(0, -0.1, -0.56) * rx(-30), "white", { shape = "Wedge" })),
		shins(S("lshin", V(0.12, 0.3, 0.12), CF(-0.56, -0.1, 0) * rz(30), "white", { shape = "Wedge" }))
	),
	fur = cat(
		feet(S("lfoot", SHOE, CF(0, 0, -0.04), "s", { mat = Enum.Material.Leather })),
		shins(S("lshin", V(1.2, 0.4, 1.2), CF(0, -0.22, 0), "white", FABRIC))
	),
	slippers = cat(
		feet(S("lfoot", V(1.08, 0.36, 1.12), CF(0, 0, -0.04), "p", FABRIC)),
		feet(
			S(
				"lfoot",
				V(0.3, 0.3, 0.3),
				CF(0, 0.15, -0.4),
				"white",
				{ shape = "Ball", mat = Enum.Material.Fabric }
			)
		)
	),
	loafers = cat(
		feet(S("lfoot", SHOE, CF(0, 0, -0.04), "dark", { mat = Enum.Material.Leather })),
		feet(S("lfoot", V(0.5, 0.06, 0.08), CF(0, 0.12, -0.35), "gold", GOLD))
	),
	nightBoots = cat( -- H8: Hero Pass season 1 (Opening Night Boots)
		feet(S("lfoot", SHOE, CF(0, 0, -0.04), "dark", { mat = Enum.Material.Leather })),
		shins(S("lshin", V(1.08, 0.7, 1.08), CF(0, -0.1, 0), "dark", { mat = Enum.Material.Leather })),
		shins(S("lshin", V(1.1, 0.1, 1.1), CF(0, 0.22, 0), "gold", GOLD)),
		feet(S("lfoot", V(0.5, 0.14, 0.2), CF(0, -0.1, 0.45), "a", { neon = true }))
	),
	ice = cat(
		feet(S("lfoot", SHOE, CF(0, 0, -0.04), "ice", { mat = Enum.Material.Glass })),
		shins(S("lshin", V(1.1, 0.5, 1.1), CF(0, -0.2, 0), "ice", { mat = Enum.Material.Glass, alpha = 0.2 }))
	),
}

-- rings and bracelets: 6 more
wrist.watch = cat(
	S("llarm", V(1.08, 0.12, 1.08), CF(0, WB + 0.02, 0), "dark"),
	S("llarm", V(0.3, 0.16, 0.06), CF(0, WB + 0.02, -0.56), "a", GLOW)
)
wrist.bangles = cat(
	S("rlarm", V(1.12, 0.08, 1.12), CF(0, WB, 0), "gold", GOLD),
	S("rlarm", V(1.12, 0.08, 1.12), CF(0, WB + 0.14, 0), "gold", GOLD),
	S("rlarm", V(1.12, 0.08, 1.12), CF(0, WB + 0.28, 0), "s", METAL)
)
wrist.sweatband = forearms(S("llarm", V(1.1, 0.22, 1.1), CF(0, WB + 0.06, 0), "white", FABRIC))
wrist.links = forearms(S("llarm", V(1.1, 0.1, 1.1), CF(0, WB, 0) * rz(8), "white", METAL))
wrist.studs = cat(
	S("rlarm", V(1.1, 0.18, 1.1), CF(0, WB + 0.04, 0), "dark", { mat = Enum.Material.Leather }),
	S("rlarm", V(0.1, 0.1, 0.1), CF(0, WB + 0.04, -0.58), "white", { shape = "Ball" }),
	S("rlarm", V(0.1, 0.1, 0.1), CF(-0.58, WB + 0.04, 0), "white", { shape = "Ball" })
)
wrist.gemring = cat(
	S("lhand", V(0.26, 0.1, 0.26), CF(-0.2, -0.04, -0.42), "gold", GOLD),
	S("lhand", V(0.14, 0.14, 0.14), CF(-0.2, -0.04, -0.56), "a", { mat = Enum.Material.Glass })
)

-- belts: 7 more
belt.studded = cat(
	S("waist", V(2.06, 0.2, 1.06), CF(0, 0.05, 0), "dark", { mat = Enum.Material.Leather }),
	S("waist", V(0.08, 0.08, 0.04), CF(-0.6, 0.05, BZ - 0.01), "white", { shape = "Ball" }),
	S("waist", V(0.08, 0.08, 0.04), CF(-0.3, 0.05, BZ - 0.01), "white", { shape = "Ball" }),
	S("waist", V(0.08, 0.08, 0.04), CF(0.3, 0.05, BZ - 0.01), "white", { shape = "Ball" }),
	S("waist", V(0.08, 0.08, 0.04), CF(0.6, 0.05, BZ - 0.01), "white", { shape = "Ball" })
)
belt.bigbuckle = cat(
	S("waist", V(2.06, 0.18, 1.06), CF(0, 0.05, 0), "s", { mat = Enum.Material.Leather }),
	S("waist", V(0.55, 0.36, 0.08), CF(0, 0.05, BZ - 0.03), "gold", GOLD)
)
belt.fanny = cat(
	S("waist", V(2.06, 0.1, 1.06), CF(0, 0.08, 0), "dark"),
	S("waist", V(0.8, 0.36, 0.3), CF(0.3, 0, BZ - 0.12), "p", FABRIC)
)
belt.toolbelt = cat(
	S("waist", V(2.06, 0.2, 1.06), CF(0, 0.05, 0), "s", { mat = Enum.Material.Leather }),
	S("waist", V(0.08, 0.5, 0.08), CF(-0.75, -0.2, BZ - 0.06), "white", METAL),
	S("waist", V(0.3, 0.12, 0.12), CF(-0.75, 0.05, BZ - 0.06), "dark"),
	S("waist", V(0.35, 0.4, 0.2), CF(0.7, -0.05, BZ - 0.06), "s", { mat = Enum.Material.Leather })
)
belt.obi = cat(
	S("waist", V(2.1, 0.36, 1.1), CF(0, 0.05, 0), "p", FABRIC),
	S("waist", V(0.6, 0.4, 0.2), CF(0, 0.05, -BZ + 0.08), "s", FABRIC)
)
belt.capsules = cat(
	S("waist", V(2.06, 0.18, 1.06), CF(0, 0.05, 0), "dark"),
	S("waist", V(0.16, 0.26, 0.16), CF(-0.6, 0.05, BZ - 0.06), "a", { neon = true }),
	S("waist", V(0.16, 0.26, 0.16), CF(-0.35, 0.05, BZ - 0.06), "a", { neon = true }),
	S("waist", V(0.16, 0.26, 0.16), CF(0.35, 0.05, BZ - 0.06), "a", { neon = true }),
	S("waist", V(0.16, 0.26, 0.16), CF(0.6, 0.05, BZ - 0.06), "a", { neon = true })
)
belt.cord = cat(
	S("waist", V(2.06, 0.1, 1.06), CF(0, 0.05, 0), "gold", FABRIC),
	both(S("waist", V(0.08, 0.5, 0.08), CF(-0.3, -0.25, BZ - 0.04), "gold", FABRIC)),
	both(
		S(
			"waist",
			V(0.14, 0.14, 0.14),
			CF(-0.3, -0.52, BZ - 0.04),
			"gold",
			{ shape = "Ball", mat = Enum.Material.Fabric }
		)
	)
)

-- legs: 18 more
legs.jeans = {
	paint = { "s", "s" },
	parts = cat(
		thighs(S("lthigh", V(0.04, 0.87, 0.06), CF(-0.51, 0, 0), "gold")),
		shins(S("lshin", V(0.04, 0.87, 0.06), CF(-0.51, 0, 0), "gold"))
	),
}
legs.cuffed = { paint = { "s", "s" }, parts = shins(S("lshin", V(1.1, 0.2, 1.1), CF(0, -0.33, 0), "s")) }
legs.capri = { paint = { "s", "skin" }, parts = shins(S("lshin", V(1.04, 0.35, 1.04), CF(0, 0.26, 0), "s")) }
legs.flared =
	{ paint = { "s", "s" }, parts = shins(S("lshin", V(1.3, 0.4, 1.3), CF(0, -0.24, 0), "s", FABRIC)) }
legs.pleated = {
	paint = { "skin", "skin" },
	parts = {
		S("waist", V(2.15, 0.7, 1.2), CF(0, -0.4, 0), "p", FABRIC),
		S("waist", V(2.18, 0.08, 1.22), CF(0, -0.7, 0), "white", FABRIC),
	},
}
legs.leggings = {
	paint = { "dark", "dark" },
	parts = cat(
		thighs(S("lthigh", V(0.04, 0.87, 0.12), CF(-0.51, 0, 0), "a", GLOW)),
		shins(S("lshin", V(0.04, 0.87, 0.12), CF(-0.51, 0, 0), "a", GLOW))
	),
}
legs.camo = {
	paint = { "s", "s" },
	parts = cat(
		S("lthigh", V(0.5, 0.3, 0.03), CF(0.1, 0.1, -0.505), "dark", { alpha = 0.3 }),
		S("rthigh", V(0.4, 0.35, 0.03), CF(-0.15, -0.2, -0.505), "dark", { alpha = 0.3 }),
		S("lshin", V(0.35, 0.3, 0.03), CF(-0.1, 0.1, -0.505), "dark", { alpha = 0.3 }),
		S("rshin", V(0.5, 0.25, 0.03), CF(0.05, -0.15, -0.505), "dark", { alpha = 0.3 })
	),
}
legs.ski = {
	paint = { "p", "p" },
	parts = cat(
		thighs(S("lthigh", V(1.14, 0.87, 1.14), CF(0, 0, 0), "p", FABRIC)),
		shins(S("lshin", V(1.14, 0.87, 1.14), CF(0, 0, 0), "p", FABRIC)),
		thighs(S("lthigh", V(1.16, 0.08, 1.16), CF(0, 0.3, 0), "white"))
	),
}
legs.harem = {
	paint = { "p", "p" },
	parts = cat(
		thighs(S("lthigh", V(1.3, 0.95, 1.3), CF(-0.08, -0.05, 0), "p", FABRIC)),
		shins(S("lshin", V(1.25, 0.6, 1.25), CF(-0.05, 0.12, 0), "p", FABRIC)),
		shins(S("lshin", V(1.06, 0.14, 1.06), CF(0, -0.36, 0), "s", FABRIC))
	),
}
legs.chaps = {
	paint = { "s", "s" },
	parts = cat(
		thighs(S("lthigh", V(0.2, 0.87, 1.08), CF(-0.5, 0, 0), "dark", { mat = Enum.Material.Leather })),
		shins(S("lshin", V(0.2, 0.87, 1.08), CF(-0.5, 0, 0), "dark", { mat = Enum.Material.Leather }))
	),
}
legs.shinguards = {
	paint = { "s", "s" },
	parts = shins(S("lshin", V(0.8, 0.7, 0.14), CF(0, 0, -0.55), "white", { mat = Enum.Material.Rubber })),
}
legs.checkered = {
	paint = { "white", "white" },
	parts = cat(
		thighs(S("lthigh", V(0.5, 0.42, 0.03), CF(-0.25, 0.21, -0.505), "dark")),
		thighs(S("lthigh", V(0.5, 0.42, 0.03), CF(0.25, -0.21, -0.505), "dark")),
		shins(S("lshin", V(0.5, 0.42, 0.03), CF(-0.25, 0.21, -0.505), "dark")),
		shins(S("lshin", V(0.5, 0.42, 0.03), CF(0.25, -0.21, -0.505), "dark"))
	),
}
legs.bandaged = {
	paint = { "s", "s" },
	parts = cat(
		S("lthigh", V(1.06, 0.16, 1.06), CF(0, 0.1, 0) * rz(10), "white", FABRIC),
		S("rshin", V(1.06, 0.16, 1.06), CF(0, 0.15, 0) * rz(-10), "white", FABRIC),
		S("rshin", V(1.06, 0.16, 1.06), CF(0, -0.1, 0) * rz(8), "white", FABRIC)
	),
}
legs.glowlines = {
	paint = { "dark", "dark" },
	parts = cat(
		thighs(S("lthigh", V(0.06, 0.87, 0.04), CF(0, 0, -0.51), "a", GLOW)),
		shins(S("lshin", V(0.06, 0.87, 0.04), CF(0, 0, -0.51), "a", GLOW)),
		shins(S("lshin", V(1.04, 0.06, 1.04), CF(0, 0.35, 0), "a", GLOW))
	),
}
legs.scaled = {
	paint = { "dark", "dark" },
	parts = cat(
		thighs(S("lthigh", V(1.08, 0.2, 1.08), CF(0, 0.2, 0) * rx(8), "p", METAL)),
		thighs(S("lthigh", V(1.08, 0.2, 1.08), CF(0, -0.1, 0) * rx(8), "s", METAL)),
		shins(S("lshin", V(1.08, 0.2, 1.08), CF(0, 0.1, 0) * rx(8), "p", METAL))
	),
}
legs.sarong = {
	paint = { "s", "s" },
	parts = {
		S("waist", V(2.2, 1.4, 1.2), CF(0, -0.75, 0) * rz(4), "p", FABRIC),
		S(
			"waist",
			V(0.3, 0.3, 0.12),
			CF(0.75, -0.05, BZ - 0.06),
			"p",
			{ shape = "Ball", mat = Enum.Material.Fabric }
		),
	},
}
legs.sweats = {
	paint = { "s", "s" },
	parts = cat(
		thighs(S("lthigh", V(1.12, 0.9, 1.12), CF(0, -0.02, 0), "s", FABRIC)),
		shins(S("lshin", V(1.06, 0.16, 1.06), CF(0, -0.35, 0), "s", FABRIC)),
		both(S("waist", V(0.05, 0.3, 0.04), CF(-0.1, -0.1, BZ - 0.02), "white"))
	),
}
legs.moto = {
	paint = { "dark", "dark" },
	parts = cat(
		shins(S("lshin", V(0.85, 0.5, 0.16), CF(0, 0.15, -0.55), "s", METAL)),
		thighs(S("lthigh", V(0.06, 0.87, 0.3), CF(-0.52, 0, 0), "a"))
	),
}

-- back bling: 10 more
backpack.satchel = cat(
	S("torso", V(0.9, 0.7, 0.3), CF(0.3, -0.45, KZ + 0.15), "s", { mat = Enum.Material.Leather }),
	S("torso", V(0.12, 2.4, 0.06), CF(0, 0, TZ - 0.02) * rz(-35), "s", { mat = Enum.Material.Leather })
)
backpack.case = cat(
	S("torso", V(0.7, 2.2, 0.3), CF(0, 0, KZ + 0.15) * rz(-15), "dark"),
	S("torso", V(1.0, 0.9, 0.3), CF(0.3, -0.9, KZ + 0.15) * rz(-15), "dark")
)
backpack.banner = cat(
	S("torso", V(0.08, 2.4, 0.08), CF(0.4, 0.8, KZ + 0.1), "dark", METAL),
	S("torso", V(0.9, 0.8, 0.04), CF(0.0, 1.5, KZ + 0.1), "p", FABRIC)
)
backpack.scroll = cat(
	S("torso", V(1.8, 0.35, 0.35), CF(0, 0.2, KZ + 0.2) * rz(30), "white", { shape = "Cylinder" }),
	both(S("torso", V(0.1, 0.42, 0.42), CF(-0.78, 0.65, KZ + 0.2) * rz(30), "s", { shape = "Cylinder" }))
)
backpack.cogs = cat(
	S(
		"torso",
		V(0.12, 1.2, 1.2),
		CF(-0.35, 0.3, KZ + 0.15) * ROT_Y,
		"gold",
		{ shape = "Cylinder", mat = Enum.Material.Metal }
	),
	S(
		"torso",
		V(0.12, 0.8, 0.8),
		CF(0.45, -0.2, KZ + 0.15) * ROT_Y,
		"s",
		{ shape = "Cylinder", mat = Enum.Material.Metal }
	)
)
backpack.butterfly = cat(
	both(S("torso", V(0.06, 0.9, 0.9), CF(-0.55, 0.45, KZ + 0.15) * rz(-30), "a", { alpha = 0.3 })),
	both(S("torso", V(0.06, 0.6, 0.6), CF(-0.45, -0.3, KZ + 0.15) * rz(20), "s", { alpha = 0.3 }))
)
backpack.fins = cat(
	S("torso", V(0.1, 1.0, 0.7), CF(0, 0.3, KZ + 0.3) * ROT_Y, "a", { shape = "Wedge" }),
	both(S("torso", V(0.1, 0.6, 0.45), CF(-0.5, -0.2, KZ + 0.2) * rz(-30), "a", { shape = "Wedge" }))
)
backpack.antenna = cat(
	S("torso", V(0.9, 0.9, 0.35), CF(0, 0, KZ + 0.18), "s", METAL),
	S("torso", V(0.06, 1.6, 0.06), CF(0.35, 1.1, KZ + 0.25), "dark", METAL),
	S("torso", V(0.14, 0.14, 0.14), CF(0.35, 1.9, KZ + 0.25), "a", { shape = "Ball", neon = true })
)
backpack.umbrella = cat(
	S("torso", V(0.3, 2.2, 0.3), CF(-0.2, 0.1, KZ + 0.15) * rz(15), "p", FABRIC),
	S("torso", V(0.06, 0.5, 0.06), CF(-0.5, 1.3, KZ + 0.15) * rz(15), "dark")
)
backpack.orbs = cat(
	S("torso", V(0.35, 0.35, 0.35), CF(-0.8, 1.2, KZ + 0.4), "a", { shape = "Ball", neon = true }),
	S("torso", V(0.3, 0.3, 0.3), CF(0.9, 1.0, KZ + 0.4), "a", { shape = "Ball", neon = true }),
	S("torso", V(0.25, 0.25, 0.25), CF(0, 1.6, KZ + 0.4), "s", { shape = "Ball", neon = true })
)

-- capes: the Capes slot's 2026-11-17 extras ("cape:style", like LookKit's capes)
local back = {
	["cape:hood"] = cat(
		S("torso", V(1.9, 2.8, 0.08), CF(0, -0.9, 0.62), "p"),
		S("torso", V(1.3, 0.9, 0.5), CF(0, 0.9, 0.62) * rx(-10), "p", FABRIC)
	),
	["cape:feather"] = cat(
		S("torso", V(1.9, 2.4, 0.08), CF(0, -0.7, 0.62), "p", FABRIC),
		both(S("torso", V(0.08, 0.8, 0.5), CF(-0.6, -2.1, 0.62) * ROT_Y * rx(180), "s", { shape = "Wedge" })),
		S("torso", V(0.08, 0.8, 0.5), CF(0, -2.2, 0.62) * ROT_Y * rx(180), "s", { shape = "Wedge" })
	),
	["cape:night"] = cat( -- H8: Hero Pass season 1 (Opening Night Cape)
		S("torso", V(1.9, 2.9, 0.08), CF(0, -0.95, 0.62), "p", FABRIC),
		S("torso", V(1.92, 0.14, 0.1), CF(0, -2.35, 0.62), "gold", GOLD),
		S("torso", V(0.16, 0.16, 0.04), CF(-0.45, -0.6, 0.68), "gold", { shape = "Ball", neon = true }),
		S("torso", V(0.16, 0.16, 0.04), CF(0.45, -1.4, 0.68), "gold", { shape = "Ball", neon = true })
	),
	["cape:star"] = cat(
		S("torso", V(1.9, 3.0, 0.08), CF(0, -1.0, 0.62), "dark"),
		S("torso", V(0.12, 0.12, 0.04), CF(-0.5, -0.5, 0.68), "white", { shape = "Ball", neon = true }),
		S("torso", V(0.1, 0.1, 0.04), CF(0.4, -1.1, 0.68), "white", { shape = "Ball", neon = true }),
		S("torso", V(0.14, 0.14, 0.04), CF(-0.2, -1.8, 0.68), "a", { shape = "Ball", neon = true }),
		S("torso", V(0.1, 0.1, 0.04), CF(0.6, -2.2, 0.68), "white", { shape = "Ball", neon = true })
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
	head = head,
	suit = suit,
	suitPaint = suitPaint,
	hands = handsKit,
	feet = feetKit,
	back = back,
	maskHidesHair = maskHidesHair,
}
