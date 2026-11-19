-- The 36 weapons' Blender meshes (2026-11-18): art/blender/weapons.py's fit (Config.WeaponArt), Shared.WeaponMesh's
-- all-or-nothing pick, and the weapon stances in Shared.HeroAnim: the blocky rig is posed in each weapon's stance
-- and its key swing, shot or guard (forward kinematics on Config.HeroRig's joints, as HeroAnimator writes them) and
-- every weapon must clear the ground and the head, blasters and spears must aim forward, shields face forward and
-- the bow stand upright. Called from tests/run.luau:
--   require("./weapon_art_test")({ test = test, check = check, Config = Config })
-- ONLY="Weapon art" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local WeaponMesh = require("../src/shared/WeaponMesh")
	local HeroAnim = require("../src/shared/HeroAnim")
	local FIT = Config.WeaponArt
	local W = Config.Weapons

	-- ---------------------------------------------------------------- a tiny CFrame (3x3 rows + position)
	type M3 = { { number } }
	local function mul(a: M3, b: M3): M3
		local out = {}
		for i = 1, 3 do
			out[i] = {}
			for j = 1, 3 do
				out[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j]
			end
		end
		return out
	end
	local function apply(m: M3, v: { number }): { number }
		return {
			m[1][1] * v[1] + m[1][2] * v[2] + m[1][3] * v[3],
			m[2][1] * v[1] + m[2][2] * v[2] + m[2][3] * v[3],
			m[3][1] * v[1] + m[3][2] * v[2] + m[3][3] * v[3],
		}
	end
	local function add(a: { number }, b: { number }): { number }
		return { a[1] + b[1], a[2] + b[2], a[3] + b[3] }
	end
	local function sub(a: { number }, b: { number }): { number }
		return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
	end
	-- Roblox's CFrame.Angles(rx, ry, rz) in degrees: Rx * Ry * Rz
	local function angles(a: { number }?): M3
		local rx, ry, rz = math.rad(a and a[1] or 0), math.rad(a and a[2] or 0), math.rad(a and a[3] or 0)
		local cx, sx, cy, sy, cz, sz =
			math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
		local X = { { 1, 0, 0 }, { 0, cx, -sx }, { 0, sx, cx } }
		local Y = { { cy, 0, sy }, { 0, 1, 0 }, { -sy, 0, cy } }
		local Z = { { cz, -sz, 0 }, { sz, cz, 0 }, { 0, 0, 1 } }
		return mul(mul(X, Y), Z)
	end

	-- the arm chain on the standard rig: each part's world rotation and centre for a pose (joint -> angles)
	local P = Config.HeroRig.parts
	local function att(part: string, name: string): { number }
		return P[part].attachments[name]
	end
	local ROLE = {
		rhand = "RightHand",
		lhand = "LeftHand",
		rlarm = "RightLowerArm",
		llarm = "LeftLowerArm",
		rfoot = "RightFoot",
		lfoot = "LeftFoot",
		rshin = "RightLowerLeg",
		lshin = "LeftLowerLeg",
	}
	local function pose(angs: { [string]: { number } }): { [string]: { R: M3, c: { number } } }
		local I = angles(nil)
		local out = {}
		local function joint(name: string, parent: string, child: string, c0: { number }, c1: { number })
			local pr = out[parent]
			local R = mul(pr.R, angles(angs[name]))
			-- child centre = parent centre + parentR * c0 - childR * c1
			out[child] = { R = R, c = sub(add(pr.c, apply(pr.R, c0)), apply(R, c1)) }
		end
		out.LowerTorso = { R = I, c = { 0, P.LowerTorso.centre[2], 0 } }
		joint(
			"Waist",
			"LowerTorso",
			"UpperTorso",
			att("LowerTorso", "WaistRigAttachment"),
			att("UpperTorso", "WaistRigAttachment")
		)
		joint(
			"Neck",
			"UpperTorso",
			"Head",
			att("UpperTorso", "NeckRigAttachment"),
			att("Head", "NeckRigAttachment")
		)
		for _, side in { "Right", "Left" } do
			joint(
				side .. "Shoulder",
				"UpperTorso",
				side .. "UpperArm",
				att("UpperTorso", side .. "ShoulderRigAttachment"),
				att(side .. "UpperArm", side .. "ShoulderRigAttachment")
			)
			joint(
				side .. "Elbow",
				side .. "UpperArm",
				side .. "LowerArm",
				att(side .. "UpperArm", side .. "ElbowRigAttachment"),
				att(side .. "LowerArm", side .. "ElbowRigAttachment")
			)
			joint(
				side .. "Wrist",
				side .. "LowerArm",
				side .. "Hand",
				att(side .. "LowerArm", side .. "WristRigAttachment"),
				att(side .. "Hand", side .. "WristRigAttachment")
			)
			-- the legs stand still in every stance and swing checked here
			for _, leg in { "UpperLeg", "LowerLeg", "Foot" } do
				out[side .. leg] = { R = I, c = P[side .. leg].centre }
			end
		end
		return out
	end
	local function clipPose(clip: string, t: number): { [string]: { R: M3, c: { number } } }
		local a = HeroAnim.sample(clip, t)
		a.Root = nil -- the whole-body turn (spins) is not part of the hold
		return pose(a)
	end

	-- a weapon's mesh box corners in the world for a pose
	local function corners(fit: any, posed: any): { { number } }
		local out = {}
		for _, p in fit.pieces do
			local part = posed[ROLE[p.at]]
			for dx = -1, 1, 2 do
				for dy = -1, 1, 2 do
					for dz = -1, 1, 2 do
						local l = {
							p.offset[1] + dx * p.size[1] / 2,
							p.offset[2] + dy * p.size[2] / 2,
							p.offset[3] + dz * p.size[3] / 2,
						}
						table.insert(out, add(part.c, apply(part.R, l)))
					end
				end
			end
		end
		return out
	end
	local function dirIn(fit: any, posed: any, v: { number }): { number }
		return apply(posed[ROLE[fit.aim.at]].R, v)
	end
	local function angleTo(a: { number }, b: { number }): number
		local la = math.sqrt(a[1] ^ 2 + a[2] ^ 2 + a[3] ^ 2)
		local lb = math.sqrt(b[1] ^ 2 + b[2] ^ 2 + b[3] ^ 2)
		local d = (a[1] * b[1] + a[2] * b[2] + a[3] * b[3]) / (la * lb)
		return math.deg(math.acos(math.clamp(d, -1, 1)))
	end
	local FORWARD, UP = { 0, 0, -1 }, { 0, 1, 0 }

	test("Weapon art: the fit covers all 36 weapons, ids and names unchanged, in the phone budget", function()
		check(type(FIT) == "table", "Config.WeaponArt is indexed")
		check(#W.list == 36, "still 36 weapons")
		for i, w in W.list do
			check(w[1] == i, "weapon ids stay in order")
		end
		local problems = WeaponMesh.check(Config)
		for _, p in problems do
			check(false, p)
		end
		check(#problems == 0, "the fit table is sound")
		local total, meshes = 0, 0
		for id, fit in FIT do
			check(W.list[id] ~= nil, "fit " .. tostring(id) .. " is a weapon")
			total += fit.triangles
			meshes += #WeaponMesh.names(Config, id)
			local blade = false
			for _, p in fit.pieces do
				blade = blade or p.blade == true
			end
			-- the fist weapons are wraps and knuckles: no blade to finish
			check(blade or id <= 2, fit.name .. " has a piece that takes the finish")
		end
		check(
			total > 10000 and total <= 36 * WeaponMesh.budget,
			"about 30k Classic triangles in all: " .. total
		)
		check(meshes >= 200, "every weapon in several meshes: " .. meshes)
		-- glow parts are their own meshes, so the game tints them: every weapon but the plain wraps has one
		for id, fit in FIT do
			local glow = false
			for _, p in fit.pieces do
				glow = glow or p.glow or p.neon
			end
			check(glow or id == 2, fit.name .. " has a glow mesh")
		end
	end)

	test("Weapon art: all or nothing, and the styles swap in their own meshes", function()
		for id in FIT do
			local names = WeaponMesh.names(Config, id)
			check(not WeaponMesh.ready(Config, id, function()
				return false
			end), "nothing imported: parts")
			check(
				WeaponMesh.ready(Config, id, function()
					return true
				end),
				"everything imported: meshes"
			)
			-- one missing mesh, even a style's, and the whole weapon stays parts
			for _, missing in { names[1], names[#names] } do
				check(not WeaponMesh.ready(Config, id, function(n)
					return n ~= missing
				end), FIT[id].name .. " without " .. missing .. " is parts")
			end
			local classic = WeaponMesh.pieces(Config, id, 1)
			check(#classic == #FIT[id].pieces, "one mesh a piece")
			for st = 2, 4 do
				local list = WeaponMesh.pieces(Config, id, st)
				check(#list == #classic, "every style has every piece")
				for i, p in list do
					local row = FIT[id].pieces[i]
					local want = if st == 2 and row.broad
						then row.broad.mesh
						elseif st == 3 and row.jag then row.jag.mesh
						else row.mesh
					check(p.mesh == want, FIT[id].name .. " style " .. st .. " picks " .. want)
					check(p.energy == (st == 4 and row.blade == true), "Energy lights only the blades")
				end
			end
		end
		check(not WeaponMesh.ready(Config, 99, function()
			return true
		end), "an unknown weapon has no meshes")
		check(#WeaponMesh.pieces(Config, nil, 1) == 0, "no weapon, no pieces")
		-- the blades change with the styles
		local swaps = 0
		for _, fit in FIT do
			for _, p in fit.pieces do
				if p.broad or p.jag then
					swaps += 1
				end
			end
		end
		check(swaps >= 40, "Broad and Jagged have their own meshes on most blades: " .. swaps)
	end)

	test("Weapon art: every weapon has a ready stance and holds of the right kind", function()
		for _, w in W.list do
			local id, family = w[1], w[2]
			local clip = HeroAnim.holdClip(id, family)
			check(clip ~= nil and HeroAnim.CLIPS[clip] ~= nil, w[3] .. " has a stance clip")
			if clip then
				local c = HeroAnim.CLIPS[clip]
				check(c.loop == true, clip .. " loops")
				for joint in c.joints do
					check(
						string.find(joint, "Shoulder")
							or string.find(joint, "Elbow")
							or (string.find(clip, "@", 1, true) and string.find(joint, "Wrist")), -- two-handed (pt-anims)
						clip .. " moves only the arms"
					)
				end
			end
			-- the hold turns about the grip line in the hand (WeaponKit's G, the grip attachment since pt-fit), a shield about its forearm's centre
			for at, h in FIT[id].hold do
				if at == "rhand" or at == "lhand" then
					check(
						h.pivot[2] == -0.15 and h.pivot[1] == 0 and h.pivot[3] == 0,
						w[3] .. " turns about the grip"
					)
				else
					check(
						h.pivot[1] == 0 and h.pivot[2] == 0 and h.pivot[3] == 0,
						w[3] .. " turns about the forearm"
					)
				end
			end
		end
		check(HeroAnim.holdClip(nil, nil) == nil, "no weapon, no stance")
		-- (pt-anims: the two-handed copy of the pole stance)
		check(
			string.sub(HeroAnim.holdClip(14, "two") or "", 1, 8) == "holdPole",
			"the spear levels its own way"
		)
		check(
			HeroAnim.holdsIn(nil) and HeroAnim.holdsIn("air"),
			"the stance shows standing, running and jumping"
		)
		check(
			not HeroAnim.holdsIn("fly") and not HeroAnim.holdsIn("downed"),
			"flying and Downed keep their own arms"
		)
		check(
			HeroAnim.holdWeight > 0.5 and HeroAnim.holdWeight <= 1 and HeroAnim.holdBlend > 0,
			"the stance blend"
		)
	end)

	test("Weapon art: held right in the stances and swings (posed rig)", function()
		local head = P.Head
		local hc, hs = head.centre, head.size
		for _, w in W.list do
			local id, family, name = w[1], w[2], w[3]
			local fit = FIT[id]
			local stance = clipPose(HeroAnim.holdClip(id, family) :: string, 0)
			-- in the stance: off the ground (the arm pieces: Strikers' boot plates sit on the feet), out of the head
			local arms = { pieces = {} }
			for _, p in fit.pieces do
				if p.at ~= "rfoot" and p.at ~= "lfoot" and p.at ~= "rshin" and p.at ~= "lshin" then
					table.insert(arms.pieces, p)
				end
			end
			for _, p in fit.pieces do
				if p.at == "rfoot" or p.at == "lfoot" then
					-- a boot plate's sole may sink a hair into the floor, never through it
					local bottom = P[ROLE[p.at]].centre[2] + p.offset[2] - p.size[2] / 2
					check(bottom > -0.05, name .. " " .. p.mesh .. " stands on the floor")
				end
			end
			for _, c in corners(arms, stance) do
				check(c[2] > 0.05, name .. " clears the ground in its stance")
				local inHead = math.abs(c[1] - hc[1]) < hs[1] / 2 - 0.1
					and math.abs(c[2] - hc[2]) < hs[2] / 2 - 0.1
					and math.abs(c[3] - hc[3]) < hs[3] / 2 - 0.1
				check(not inHead, name .. " stays out of the head in its stance")
			end
			local aim = dirIn(fit, stance, fit.aim.dir)
			if family == "one" or family == "two" or family == "dual" then
				if id ~= 20 and id ~= 21 then
					check(aim[3] < -0.3, name .. " points forward in its stance")
					check(aim[2] > -0.35, name .. " is not pointed at the floor in its stance")
				end
			end
			-- blasters and crossbows aim where the arm points
			if id == 25 or id == 26 or id == 27 or id == 29 or id == 30 then
				local shot = clipPose("shoot", 0.2)
				check(
					angleTo(dirIn(fit, shot, fit.aim.dir), FORWARD) < 22,
					name .. " aims forward when it shoots"
				)
				check(angleTo(aim, FORWARD) < 50, name .. " points ahead at low ready")
			end
			if id == 14 or id == 16 then
				local thrust = clipPose("thrust", 0.12)
				check(angleTo(dirIn(fit, thrust, fit.aim.dir), FORWARD) < 25, name .. " thrusts forward")
				check(angleTo(aim, FORWARD) < 20, name .. " is levelled forward in its stance")
			end
			if family == "shield" then
				-- the face is in its shield's forearm frame (Sword and Shield aims with the sword hand)
				check(fit.aim.faceAt == "llarm", name .. " is strapped to the left forearm")
				local function face(posed: any): { number }
					return apply(posed[ROLE[fit.aim.faceAt]].R, fit.aim.face)
				end
				local block = clipPose("block", 0.4)
				check(angleTo(face(block), FORWARD) < 45, name .. " faces forward in a block")
				check(angleTo(face(stance), FORWARD) < 45, name .. " faces forward in its stance")
			end
			if id == 28 then
				local draw = clipPose("bow", 0.2)
				check(
					angleTo(dirIn(fit, draw, fit.aim.dir), UP) < 20
						or angleTo(dirIn(fit, draw, fit.aim.dir), { 0, -1, 0 }) < 20,
					"the bow stands upright when drawn"
				)
				check(
					angleTo(aim, UP) < 40 or angleTo(aim, { 0, -1, 0 }) < 40,
					"the bow is nearly upright in its stance"
				)
			end
			-- the grip sits in (or just under) the hand
			local g = fit.grip.pos
			if fit.grip.at == "rhand" or fit.grip.at == "lhand" then
				check(
					math.abs(g[1]) <= 0.5 and math.abs(g[2]) <= 0.4 and math.abs(g[3]) <= 0.5,
					name .. " is gripped in the hand"
				)
			end
		end
	end)
end
