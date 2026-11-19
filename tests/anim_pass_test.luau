-- The animation and weapons polish pass (nate's playtest, 2026-11-19: "Animation for EVERYTHING. Every attack,
-- power, mobility, every button" and "a lot of weapons need a polish pass"). Every ability and weapon move has
-- its own whole-body clip (Shared.HeroMoves), every mobility mode and button its pose or one-shot, the line
-- weapons swing (Shared.TetherMath, Fx.TetherFx) and weapon hits draw their own look (Config.Fx.weaponLooks).
-- ONLY="Anim pass" runs just these. Called from tests/run.luau.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local HeroAnim = require("../src/shared/HeroAnim")
	local HeroMoves = require("../src/shared/HeroMoves")
	local TetherMath = require("../src/shared/TetherMath")
	local FxPlan = require("../src/shared/FxPlan")
	local A, W = Config.Abilities, Config.Weapons

	local function src(path: string): string
		return fs.readFile(path)
	end

	test("Anim pass: every ability has its own clip in its path", function()
		local per: { [string]: { [string]: string } } = {}
		local n = 0
		for _, id in A.order do
			local row = A.list[id]
			local clip = HeroAnim.castClip(row, nil, 1)
			check(HeroAnim.CLIPS[clip] ~= nil, id .. " plays a real clip (" .. clip .. ")")
			if row.slot ~= "basic" then
				n += 1
				local seen = per[row.set] or {}
				per[row.set] = seen
				check(seen[clip] == nil, string.format("%s and %s share %s", id, tostring(seen[clip]), clip))
				seen[clip] = id
				check(HeroAnim.ABILITY_CLIPS[id] ~= nil, id .. " has its own entry")
			end
		end
		check(n >= 100, "the skills and supers are all checked (" .. n .. ")")
		-- the basic attack runs a combo of at least two different swings
		for set, seq in HeroAnim.BASIC_CLIPS do
			check(#seq >= 2 and seq[1] ~= seq[2], set .. "'s basic combo varies")
			for _, c in seq do
				check(HeroAnim.CLIPS[c] ~= nil, set .. " basic " .. c .. " exists")
			end
		end
	end)

	test("Anim pass: every weapon has a 4-hit combo and four different skill moves", function()
		for id, w in W.list do
			local m = HeroAnim.WEAPON_MOVES[id]
			check(m ~= nil, w[3] .. " has moves")
			if m then
				check(#m.combo == 4, w[3] .. " combo has 4 hits")
				local distinct = {}
				local nd = 0
				for _, c in m.combo do
					check(HeroAnim.CLIPS[c] ~= nil, w[3] .. " combo " .. c .. " exists")
					if not distinct[c] then
						distinct[c] = true
						nd += 1
					end
				end
				local need = if w[2] == "ranged" then 2 else 3
				check(nd >= need, string.format("%s combo has %d different swings (%d)", w[3], need, nd))
				local keys = {}
				for _, k in W.keys do
					local c = (m :: any)[k]
					check(HeroAnim.CLIPS[c] ~= nil, w[3] .. " " .. k .. " " .. tostring(c) .. " exists")
					check(keys[c] == nil, w[3] .. " " .. k .. " differs from the other keys")
					keys[c] = true
				end
				-- the ability rows really play them
				local m1 = A.list["W" .. id .. "M1"]
				if m1 then
					check(HeroAnim.castClip(m1, w[2], 1) == m.combo[1], w[3] .. " M1 step 1")
					check(HeroAnim.castClip(m1, w[2], 2) == m.combo[2], w[3] .. " M1 step 2")
					check(HeroAnim.castClip(m1, w[2], 5) == m.combo[1], w[3] .. " combo loops")
				end
				for _, k in W.keys do
					local row = A.list["W" .. id .. k]
					if row then
						check(HeroAnim.castClip(row, w[2], 1) == (m :: any)[k], w[3] .. " " .. k .. " row")
					end
				end
			end
		end
	end)

	local LEG = { "RightHip", "LeftHip", "RightKnee", "LeftKnee" }
	local function strikes(): { [string]: boolean }
		local out = {}
		for id, c in HeroAnim.ABILITY_CLIPS do
			local row = A.list[id]
			if row and not row.channel then
				out[c] = true
			end
		end
		for _, m in HeroAnim.WEAPON_MOVES do
			for _, c in m.combo do
				out[c] = true
			end
			for _, k in W.keys do
				out[(m :: any)[k]] = true
			end
		end
		return out
	end

	test("Anim pass: attacks are whole-body with a wind-up, contact and recovery", function()
		for name in strikes() do
			local clip = HeroAnim.CLIPS[name]
			if clip and not clip.loop then
				local j = clip.joints
				local legs = false
				for _, n in LEG do
					legs = legs or j[n] ~= nil
				end
				check(legs or HeroAnim.movesLegs(name), name .. " moves the legs")
				check(j.Waist ~= nil, name .. " moves the waist")
				local most = 0
				for _, n in { "RightShoulder", "LeftShoulder", "Waist", "Root" } do
					most = math.max(most, j[n] and #j[n] or 0)
				end
				check(most >= 4, name .. " has at least 4 beats on a main joint (" .. most .. ")")
				check(clip.dur >= 0.25, name .. " lasts long enough to read")
			end
		end
	end)

	test("Anim pass: spins and flips land facing the way they started", function()
		for name, clip in HeroAnim.CLIPS do
			local root = clip.joints.Root
			if root and not clip.loop then
				local last = root[#root]
				for i = 2, 4 do
					local r = math.abs(last[i]) % 360
					check(r < 1 or r > 359 or math.abs(last[i]) < 90, name .. " Root ends on a whole turn")
				end
			end
		end
	end)

	test("Anim pass: the new clips keep the clip rules", function()
		local R15 = { Root = true, Waist = true, Neck = true }
		for _, side in { "Right", "Left" } do
			for _, j in { "Shoulder", "Elbow", "Wrist", "Hip", "Knee", "Ankle" } do
				R15[side .. j] = true
			end
		end
		for name, clip in HeroAnim.CLIPS do
			for joint in clip.joints do
				check(R15[joint] == true, name .. ": " .. joint .. " is an R15 joint")
			end
		end
		for name, clip in HeroMoves.CLIPS do
			check(clip.dur > 0 and clip.dur <= 3, name .. " dur")
			for joint, keys in clip.joints do
				local prev = -1
				for _, k in keys do
					check(k[1] > prev, name .. " " .. joint .. " keys increase")
					prev = k[1]
					for i = 2, 4 do
						check(math.abs(k[i]) <= 360, name .. " angle in range")
					end
					check((k[5] or 0) == 0 or joint == "Root", name .. " py only on Root")
				end
			end
		end
		check(HeroMoves.CLIPS.slashL ~= nil or HeroMoves.CLIPS.flickL ~= nil, "mirrored clips are made")
	end)

	test("Anim pass: gadgets, buttons and transitions have clips", function()
		for _, g in Config.Gear.gadgetOrder do
			local c = HeroAnim.GADGET_CLIPS[g]
			check(c ~= nil and HeroAnim.CLIPS[c] ~= nil, g .. " has a clip")
		end
		for _, n in
			{
				"guard",
				"guardShield",
				"blockHit",
				"parry",
				"guardBreak",
				"interrupted",
				"carry",
				"lift",
				"catch",
				"interact",
				"interactHold",
				"revive",
				"giveUp",
				"awaken",
				"powerCharge",
				"windupBoth",
				"windupHeavy",
				"flinchL",
				"flinchR",
				"flinchHeavy",
				"emoteBob",
			}
		do
			check(HeroAnim.CLIPS[n] ~= nil, n .. " exists")
		end
		local tr = HeroAnim.transition
		check(tr("ground", "fly", 0, 0) == "takeoff", "take off")
		check(tr("air", "glide", 0, 0) == "glideOpen", "glide opens")
		check(tr("air", "swing", 0, 0) == "swingCatch", "swing catch")
		check(tr("swing", "air", 0, 0) == "swingRelease", "swing release")
		check(tr("ground", "dash", 0, 0) == "dashStart", "dash start")
		check(tr("air", "wall", 0, 0) == "wallGrab", "wall grab")
		check(tr("wall", "air", 0, 0) == "wallKick", "wall kick")
		check(tr("charge", "air", 0, 0) == "leapOff", "leap off")
		check(tr("fly", "air", 0, 0) == "flyStop", "fly stop")
		check(tr("pound", "ground", 0, 0) == "poundLand", "pound landing")
		check(tr("air", "ground", 5, 0) == nil, "a small hop lands quietly")
		check(tr("air", "ground", HeroAnim.landSpeed + 1, 0) == "land", "land")
		check(tr("air", "ground", HeroAnim.landSpeed + 1, HeroAnim.rollSpeed + 1) == "landRoll", "roll")
		check(tr("fly", "ground", HeroAnim.landHardSpeed + 1, 0) == "landHard", "hard landing")
		check(tr("ground", "ground", 99, 0) == nil, "no change, no clip")
		for _, c in { "takeoff", "glideOpen", "swingCatch", "landHard", "landRoll", "poundLand", "airFlip" } do
			check(HeroAnim.CLIPS[c] ~= nil, c .. " exists")
		end
	end)

	test("Anim pass: mobility poses by speed, fall, path and Give Up", function()
		local mc = HeroAnim.modeClip
		check(mc("ground", 30, false, nil) == nil, "a run is Roblox's own")
		check(mc("ground", HeroAnim.sprintSpeed + 1, false, nil) == "sprint", "sprint")
		check(mc("ground", HeroAnim.sprintSpeed - 3, false, "sprint") == "sprint", "sprint holds")
		check(mc("fly", 80, false, nil, { vy = -70 }) == "dive", "dive")
		check(mc("fly", HeroAnim.flyFastSpeed + 1, false, nil) == "flyFast", "boost")
		check(mc("fly", HeroAnim.flyFastSpeed - 5, false, "flyFast") == "flyFast", "boost holds")
		check(mc("charge", 0, false, nil) == "leapCrouch", "leap crouch")
		check(mc("water", 60, false, nil) == "waterRun", "water run")
		check(mc("swim", 10, false, nil) == "swim", "swim")
		check(mc("dash", 10, false, nil) ~= nil, "dash")
		check(mc("arc", 10, false, nil) == "arc", "arc")
		for path, c in HeroAnim.RIDE_CLIPS do
			check(mc("ride", 50, false, nil, { ride = path }) == c, path .. " rides its own way")
			check(HeroAnim.CLIPS[c] ~= nil, c .. " exists")
		end
		check(mc("ride", 50, false, nil) == "ride", "ride default")
		check(mc("fly", 0, true, nil, { giveUp = true }) == "giveUp", "Give Up slump")
		check(mc("fly", 0, true, nil) == "downed", "Downed")
		check(
			#HeroAnim.MODES == 15 and table.find(HeroAnim.MODES, "swim") ~= nil,
			"15 modes with swim and arc"
		)
	end)

	test("Anim pass: wind-ups by move", function()
		local wc = HeroAnim.windupClip
		check(wc(nil, nil) == "windup", "no row")
		check(wc({ weapon = 11, shape = "arc" }, "two") == "windupHeavy", "heavy weapon")
		check(wc({ weapon = 25, shape = "bolt" }, "ranged") == "windup", "aimed shot")
		check(wc({ set = "Volt", slot = "super", shape = "bolt" }, nil) == "windupBoth", "super")
		check(wc({ set = "Titan", slot = "skill", shape = "arc" }, nil) == "windupHeavy", "heavy path melee")
		check(wc({ set = "Volt", slot = "skill", shape = "bolt" }, nil) == "windup", "bolt")
		for _, c in { "windup", "windupBoth", "windupHeavy" } do
			check(HeroAnim.CLIPS[c] ~= nil, c .. " exists")
		end
	end)

	test("Anim pass: the line weapons swing (TetherMath)", function()
		local spec = TetherMath.SPECS[32]
		check(
			spec ~= nil and TetherMath.SPECS[21] and TetherMath.SPECS[34] and TetherMath.SPECS[35],
			"4 weapons"
		)
		check(TetherMath.lengthAt(spec, 2, nil) == 2, "rest outside an attack")
		check(TetherMath.lengthAt(spec, 2, 0.5) == spec.reach, "full reach at the contact")
		local a, b = TetherMath.lengthAt(spec, 2, 0.2), TetherMath.lengthAt(spec, 2, 0.9)
		check(a > 2 and a < spec.reach and b > 2 and b < spec.reach, "pays out and reels in")
		check(TetherMath.baseName("W32_Chain_B") == "W32_Chain", "style suffix")
		check(TetherMath.role(spec, "W32_Chain_J") == "line", "line role")
		check(TetherMath.role(spec, "W32_Barb") == "tip", "tip role")
		check(TetherMath.role(spec, "W32_Handle") == nil, "the grip stays welded")
		-- a rope hangs below the anchor and keeps its links
		local st = TetherMath.new(spec, { 0, 10, 0 }, 3)
		for _ = 1, 60 do
			TetherMath.step(st, spec, { 1, 10, 0 }, nil, 3, 1 / 60)
		end
		local tip = TetherMath.tip(st)
		check(tip[2] < 10 - 2, "the rope hangs")
		local seg = 3 / spec.segs
		for i = 1, #st.p - 1 do
			local p, q = st.p[i], st.p[i + 1]
			local d = math.sqrt((p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2 + (p[3] - q[3]) ^ 2)
			check(math.abs(d - seg) < seg * 0.2, "link " .. i .. " keeps its length")
		end
		-- an attack drives the tip out along the arm
		for _ = 1, 30 do
			TetherMath.step(st, spec, { 0, 10, 0 }, { 0, 0, -1 }, spec.reach, 1 / 60)
		end
		tip = TetherMath.tip(st)
		check(tip[3] < -spec.reach * 0.6, "the tip lashes out forward")
		-- every spec piece is a real Config.WeaponArt mesh
		for id, s in TetherMath.SPECS do
			local art = Config.WeaponArt[id]
			check(art ~= nil, "weapon " .. id .. " has art")
			if art then
				local names = {}
				for _, p in art.pieces or {} do
					names[p.mesh or p.name or ""] = true
				end
				for _, n in s.tip do
					check(names[n] == true, n .. " is a mesh of weapon " .. id)
				end
				for _, n in s.line do
					check(names[n] == true, n .. " is a mesh of weapon " .. id)
				end
			end
		end
	end)

	test("Anim pass: weapon hits draw their own look", function()
		local F = Config.Fx
		local cfx = src("src/client/Fx/CombatFx.luau")
		local TABLE = { mark = "MARK", head = "HEAD", dash = "DASH", piece = "PIECE" }
		for look, row in F.weaponLooks.looks do
			local set = "Weapon:" .. look
			check(FxPlan.weaponLook(set) == look, look .. " parses")
			local path = FxPlan.pathOf(F, set)
			check(path ~= nil and path.piece == row.piece, look .. " is a path row")
			check(#row.words >= 3, look .. " has its words")
			for _, k in { "mark", "head", "dash", "piece" } do
				local v = row[k]
				local def = "\n" .. TABLE[k] .. "." .. v .. " = "
				check(string.find(cfx, def, 1, true) ~= nil, look .. " " .. k .. " " .. v .. " is drawn")
			end
			check(F.lib.weaponElement[look] ~= nil, look .. " has an element")
		end
		for id, w in W.list do
			local set = FxPlan.weaponSet(F, id, w[2])
			check(FxPlan.weaponLook(set) ~= nil, w[3] .. " has a look")
		end
		check(FxPlan.weaponSet(F, 32, "exotic") == "Weapon:tether", "the whip cracks")
		check(FxPlan.weaponSet(F, 8, "one") == "Weapon:blunt", "a club bonks")
		check(FxPlan.pathOf(F, "Weapon") == nil, "the bare Weapon set stays empty")
	end)

	test("Anim pass: every device plays the hooks", function()
		local gadget = src("src/client/Controllers/GadgetClient.luau")
		check(string.find(gadget, "HeroAnimator.gadget(", 1, true) ~= nil, "gadgets animate")
		check(
			string.find(src("src/client/Fx/GuardFx.luau"), "HeroAnimator.guardEvent(", 1, true) ~= nil,
			"guard"
		)
		check(string.find(src("src/client/Fx/EmoteFx.luau"), "HeroAnimator.emote(", 1, true) ~= nil, "emotes")
		local death = src("src/server/Services/DeathService.luau")
		check(string.find(death, 'SetAttribute("Reviving"', 1, true) ~= nil, "Reviving replicates")
		check(string.find(death, 'SetAttribute("GiveUp"', 1, true) ~= nil, "GiveUp replicates")
		check(
			string.find(src("src/client/Controllers/CombatClient.luau"), '"interrupted"', 1, true) ~= nil,
			"cancel"
		)
		local anim = src("src/client/Controllers/HeroAnimator.luau")
		check(string.find(anim, "PromptTriggered", 1, true) ~= nil, "interact")
		check(string.find(anim, '"Catch"', 1, true) ~= nil, "catch")
		check(
			string.find(anim, "Reviving", 1, true) ~= nil and string.find(anim, "Carrying", 1, true) ~= nil,
			"states"
		)
		check(
			string.find(src("src/shared/WeaponKit.luau"), 'SetAttribute("Piece"', 1, true) ~= nil,
			"pieces named"
		)
		local init = src("src/client/init.client.luau")
		check(string.find(init, "TetherFx.init()", 1, true) ~= nil, "TetherFx runs")
		-- perf: both are timed and kept near the camera
		local tfx = src("src/client/Fx/TetherFx.luau")
		check(string.find(tfx, 'FrameProf.wrap("TetherFx"', 1, true) ~= nil, "TetherFx is timed")
		check(string.find(tfx, "HeroAnim.nearRange", 1, true) ~= nil, "TetherFx only near")
		check(string.find(anim, 'FrameProf.wrap("HeroAnimator"', 1, true) ~= nil, "HeroAnimator is timed")
		check(
			string.find(src("src/shared/HeroMoves.luau"), "PLACEHOLDER ANIMATION", 1, true) ~= nil,
			"labelled"
		)
	end)
end
