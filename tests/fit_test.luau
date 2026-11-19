-- The fit pass (pt-fit, nate's playtest 2026-11-19: "a lot of weapons and just customization things aren't modeled
-- properly or aren't on the player properly"): heroes, robots and citizens stand on Roblox's own blocky R15 body
-- (Config.RobloxRig), while every piece's fit is written on the classic blocks of Config.HeroRig. Shared.BodyFit
-- maps one onto the other; these checks hold every creator piece, gear look and weapon to the Roblox body's own
-- attachment points. Called from tests/run.luau:
--   require("./fit_test")({ test = test, check = check, Config = Config })

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local BodyFit = require("../src/shared/BodyFit")
	local R = Config.RobloxRig.parts
	local H = Config.HeroRig.parts

	local PART = {
		head = "Head",
		torso = "UpperTorso",
		waist = "LowerTorso",
		luarm = "LeftUpperArm",
		ruarm = "RightUpperArm",
		llarm = "LeftLowerArm",
		rlarm = "RightLowerArm",
		lhand = "LeftHand",
		rhand = "RightHand",
		lthigh = "LeftUpperLeg",
		rthigh = "RightUpperLeg",
		lshin = "LeftLowerLeg",
		rshin = "RightLowerLeg",
		lfoot = "LeftFoot",
		rfoot = "RightFoot",
	}
	local JOINTS = {
		{ "Waist", "LowerTorso", "UpperTorso" },
		{ "Neck", "UpperTorso", "Head" },
		{ "LeftShoulder", "UpperTorso", "LeftUpperArm" },
		{ "LeftElbow", "LeftUpperArm", "LeftLowerArm" },
		{ "LeftWrist", "LeftLowerArm", "LeftHand" },
		{ "RightShoulder", "UpperTorso", "RightUpperArm" },
		{ "RightElbow", "RightUpperArm", "RightLowerArm" },
		{ "RightWrist", "RightLowerArm", "RightHand" },
		{ "LeftHip", "LowerTorso", "LeftUpperLeg" },
		{ "LeftKnee", "LeftUpperLeg", "LeftLowerLeg" },
		{ "LeftAnkle", "LeftLowerLeg", "LeftFoot" },
		{ "RightHip", "LowerTorso", "RightUpperLeg" },
		{ "RightKnee", "RightUpperLeg", "RightLowerLeg" },
		{ "RightAnkle", "RightLowerLeg", "RightFoot" },
	}

	-- a part's attachment in the world at rest
	local function world(part: string, att: string): { number }
		local p = R[part]
		local a = p.attachments[att]
		assert(a, part .. "." .. att)
		return { p.centre[1] + a[1], p.centre[2] + a[2], p.centre[3] + a[3] }
	end
	local function dist(a: { number }, b: { number }): number
		return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
	end
	-- a fit box on Roblox's body at rest, in the world: lo and hi corners, and its scale
	local function placed(at: string, offset: { number }, size: { number })
		local name = PART[at]
		local o, s = BodyFit.place(Config, name, R[name].size, offset, size)
		local c = R[name].centre
		local lo = { c[1] + o[1] - s[1] / 2, c[2] + o[2] - s[2] / 2, c[3] + o[3] - s[3] / 2 }
		local hi = { c[1] + o[1] + s[1] / 2, c[2] + o[2] + s[2] / 2, c[3] + o[3] + s[3] / 2 }
		return lo, hi, s
	end
	-- the classic block a part shows (HeroRig's box, where the fit was drawn), in the world
	local function shown(name: string, pad: number)
		local h = H[name]
		local lo, hi = {}, {}
		for i = 1, 3 do
			lo[i] = h.centre[i] - h.size[i] / 2 - pad
			hi[i] = h.centre[i] + h.size[i] / 2 + pad
		end
		return lo, hi
	end
	local function overlaps(alo, ahi, blo, bhi): boolean
		for i = 1, 3 do
			if ahi[i] < blo[i] or alo[i] > bhi[i] then
				return false
			end
		end
		return true
	end

	test("Fit: Roblox's blocky body is one connected rig standing on the ground", function()
		local n = 0
		for name in R do
			n += 1
			check(H[name] ~= nil, name .. " is a HeroRig part too")
		end
		check(n == 15, "the 15 R15 parts")
		for _, j in JOINTS do
			local a = world(j[2], j[1] .. "RigAttachment")
			local b = world(j[3], j[1] .. "RigAttachment")
			check(dist(a, b) < 0.005, j[1] .. " meets on both parts at rest")
		end
		check(math.abs(R.LeftFoot.centre[2] - R.LeftFoot.size[2] / 2) < 0.005, "the soles are on y = 0")
		-- the shown classic blocks agree with Roblox's: the same torso, hands and feet, arms 2 tall from y 2 to 4
		for _, name in { "UpperTorso", "LowerTorso", "LeftHand", "RightFoot" } do
			check(dist(R[name].size, H[name].size) < 0.005, name .. " is the same box on both bodies")
			check(dist(R[name].centre, H[name].centre) < 0.005, name .. " rests in the same place on both")
		end
	end)

	test("Fit: BodyFit tells the two bodies apart and never stretches a limb piece on Roblox's", function()
		for name, r in R do
			local shift, f = BodyFit.frame(Config, name, r.size)
			if name == "Head" then
				check(math.abs(f[2] - r.size[2] / H.Head.size[2]) < 1e-6, "the head maps box onto box")
			else
				for i = 1, 3 do
					check(math.abs(f[i] - 1) < 1e-6, name .. ": no stretch on the standard Roblox body")
				end
				-- the fit's frame lands on the classic block's centre
				local c = { r.centre[1] + shift[1], r.centre[2] + shift[2], r.centre[3] + shift[3] }
				check(dist(c, H[name].centre) < 1e-6, name .. ": the fit frame is the shown block's centre")
			end
			local hs, hf = BodyFit.frame(Config, name, H[name].size)
			check(
				dist(hs, { 0, 0, 0 }) < 1e-9 and dist(hf, { 1, 1, 1 }) < 1e-9,
				name .. ": the Blender body is unchanged"
			)
			-- a bigger build scales with the part
			local big = { r.size[1] * 1.2, r.size[2] * 1.05, r.size[3] * 1.15 }
			local _, bf = BodyFit.frame(Config, name, big)
			check(bf[1] > 1.15 and bf[1] < 1.25 and bf[3] > 1.1, name .. ": a big build scales the piece")
		end
	end)

	local SETS = {
		"CapeArt",
		"HeadArt",
		"GloveArt",
		"BootArt",
		"CoatArt",
		"BeltArt",
		"ShoulderArt",
		"BackArt",
		"HatArt",
		"EarArt",
		"NeckArt",
		"WristArt",
		"ArmArt",
	}

	-- pieces that hover on purpose (orbs circling the back): they still have to stay within a stud of the body
	local HOVER = { Back_orbs_Top = true, Back_orbs_Rings = true, Back_orbs_Orbs = true }

	test(
		"Fit: every creator piece sits on its own body part on Roblox's body (none floating or stretched)",
		function()
			local pieces = 0
			for _, set in SETS do
				for kit, fit in (Config :: any)[set] do
					local boxes = {}
					for i, p in fit.pieces do
						local at = p.at or "torso"
						check(PART[at] ~= nil, set .. " " .. kit .. ": a real body part " .. tostring(at))
						if PART[at] then
							local lo, hi, s = placed(at, p.offset, p.size)
							boxes[i] = { lo, hi, s }
						end
					end
					for i, p in fit.pieces do
						local b = boxes[i]
						if not b then
							continue
						end
						pieces += 1
						local name = PART[p.at or "torso"]
						local slo, shi = shown(name, if HOVER[p.mesh] then 1.0 else 0.45)
						-- on its body part's shown block, or held by another piece of the same kit that is
						local held = overlaps(b[1], b[2], slo, shi)
						if not held then
							for j, o in boxes do
								local olo = { o[1][1] - 0.05, o[1][2] - 0.05, o[1][3] - 0.05 }
								local ohi = { o[2][1] + 0.05, o[2][2] + 0.05, o[2][3] + 0.05 }
								local jlo, jhi = shown(PART[fit.pieces[j].at or "torso"], 0.45)
								if
									j ~= i
									and overlaps(b[1], b[2], olo, ohi)
									and overlaps(o[1], o[2], jlo, jhi)
								then
									held = true
									break
								end
							end
						end
						check(
							held,
							string.format("%s %s %s: on its %s, not floating", set, kit, p.mesh, name)
						)
						if name ~= "Head" then
							for k = 1, 3 do
								check(
									math.abs(b[3][k] - p.size[k]) < 1e-6,
									string.format("%s %s %s: drawn size, not stretched", set, kit, p.mesh)
								)
							end
						end
					end
				end
			end
			check(pieces > 800, "every piece was checked (" .. pieces .. ")")
		end
	)

	-- Roblox catalog hair rises 0.15 to 0.9 studs over the head (art/preview/fit_hats.png): a hat with a crown over the
	-- top of the head would sink into it, so those hide the hair as the helmets do (creator_art_test holds PieceKits
	-- hatHidesHair to the same flags)
	test("Fit: hats that crown the head hide the catalog hair instead of sinking into it", function()
		for _, kit in
			{ "cap", "brim", "tophat", "beret", "beanie", "bucket", "aviator", "dorag", "kabuto", "knight" }
		do
			check(
				Config.HatArt[kit] ~= nil and Config.HatArt[kit].hair == false,
				kit .. " hides the catalog hair"
			)
		end
		-- the halo floats over a typical catalog hair (median 0.34 studs over the head top)
		local top = R.Head.centre[2] + R.Head.size[2] / 2
		for _, p in Config.HatArt.halo.pieces do
			local lo = placed(p.at or "head", p.offset, p.size)
			check(lo[2] > top + 0.25, p.mesh .. " floats over the hair")
		end
	end)

	-- the hand's grip attachment on Roblox's body: where a Roblox tool's handle sits
	local GRIP = { rhand = "RightGripAttachment", lhand = "LeftGripAttachment" }

	test(
		"Fit: every weapon's grip sits at the hand's grip attachment and its pieces on their body parts",
		function()
			local n = 0
			for _, w in Config.Weapons.list do
				local id = w[1]
				local fit = Config.WeaponArt[id]
				local g = fit.grip
				local name = PART[g.at]
				local o = BodyFit.place(Config, name, R[name].size, g.pos, { 0, 0, 0 })
				local c = R[name].centre
				local at = { c[1] + o[1], c[2] + o[2], c[3] + o[3] }
				if GRIP[g.at] then
					n += 1
					local want = world(name, GRIP[g.at])
					check(
						dist(at, want) <= 0.03,
						string.format(
							"%d %s: the grip is in the palm (%.2f studs from %s)",
							id,
							w[3],
							dist(at, want),
							GRIP[g.at]
						)
					)
				else
					-- a forearm or foot weapon: its grip on that part's shown block
					local lo, hi = shown(name, 0.05)
					check(
						overlaps(at, at, lo, hi),
						string.format("%d %s: the grip is on the %s", id, w[3], name)
					)
				end
				for _, p in fit.pieces do
					local lo, hi, s = placed(p.at, p.offset, p.size)
					local slo, shi = shown(PART[p.at], 5.5) -- a spear or staff reaches 5 studs
					check(
						overlaps(lo, hi, slo, shi),
						string.format("%d %s %s: near its %s", id, w[3], p.mesh, p.at)
					)
					for k = 1, 3 do
						check(
							math.abs(s[k] - p.size[k]) < 1e-6,
							string.format("%d %s %s: not stretched", id, w[3], p.mesh)
						)
					end
				end
			end
			check(n >= 30, "every hand weapon's grip was checked (" .. n .. ")")
		end
	)
end
