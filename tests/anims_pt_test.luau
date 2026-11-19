-- pt-anims (nate's playtest 2026-11-19: "we need weapon and power animations that the player does. Make sure it
-- works even if player is flying or mid air. Some of them might need two handed animations" and "don't forget
-- about ... npcs, enemies, bosses"): the upper-body layer, two-handed holds (Shared.AnimIK), the robots' attack,
-- hit and stagger clips and the people's gestures (Shared.NpcAnim), and the robot swing and heavy landing clips
-- for pt-combat. ONLY="PT anims" runs just these. Called from tests/run.luau.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local HeroAnim = require("../src/shared/HeroAnim")
	local AnimIK = require("../src/shared/AnimIK")
	local NpcAnim = require("../src/shared/NpcAnim")
	local BossPose = require("../src/shared/BossPose")
	local A, W = Config.Abilities, Config.Weapons
	local arm = AnimIK.arm(Config.HeroRig)

	-- a clip samples cleanly: every value finite at every 1/60 s, keys in time order
	local function clean(name: string, clip: any, sample: (string, number) -> any)
		for joint, keys in clip.joints do
			for i = 2, #keys do
				check(keys[i][1] >= keys[i - 1][1], name .. " " .. joint .. " keys in order")
			end
			check(keys[#keys][1] <= clip.dur + 1e-6, name .. " " .. joint .. " keys inside the clip")
		end
		local n = math.max(2, math.floor(clip.dur * 60))
		for i = 0, n do
			for joint, a in sample(name, clip.dur * i / n) do
				for k = 1, 4 do
					local v = a[k]
					if not (v == v and v > -1e5 and v < 1e5) then
						check(false, string.format("%s %s sample %d is %s", name, joint, k, tostring(v)))
						return
					end
				end
			end
		end
	end

	test(
		"PT anims: every ability, weapon move and robot attack maps to a clip that samples cleanly",
		function()
			local used: { [string]: boolean } = {}
			for _, id in A.order do
				local row = A.list[id]
				local fam = nil
				if row.weapon then
					for _, w in W.list do
						if w[1] == row.weapon then
							fam = w[2]
						end
					end
				end
				for step = 1, 4 do
					local clip = HeroAnim.castClip(row, fam, step)
					check(HeroAnim.CLIPS[clip] ~= nil, id .. " step " .. step .. " plays " .. clip)
					used[clip] = true
				end
				used[HeroAnim.windupClip(row, fam)] = true
			end
			local nw = 0
			for wid, m in HeroAnim.WEAPON_MOVES do
				for _, c in m.combo do
					used[c] = true
				end
				for _, k in { "Z", "X", "C", "V" } do
					check(HeroAnim.CLIPS[m[k]] ~= nil, "weapon " .. wid .. " " .. k .. " has a clip")
					used[m[k]] = true
				end
				nw += 1
			end
			check(nw == 36, "all 36 weapons have moves (" .. nw .. ")")
			for name in HeroAnim.CLIPS do
				used[name] = true
			end
			local n = 0
			for name in used do
				local clip = HeroAnim.CLIPS[name]
				check(clip ~= nil, name .. " exists")
				if clip then
					clean(name, clip, HeroAnim.sample)
					n += 1
				end
			end
			check(n >= 395, "hero clips checked (" .. n .. ")")
			-- every robot kind's AI has a clip for each event, the hit reacts and the stagger
			local ais: { [string]: boolean } = {}
			for kind, row in Config.Enemies do
				if type(row) == "table" and type(row.ai) == "string" then
					ais[row.ai] = true
					check(NpcAnim.AI[row.ai] ~= nil, kind .. "'s AI " .. row.ai .. " has its own clips")
				end
			end
			for ai in ais do
				for _, ev in NpcAnim.EVENTS do
					local c = NpcAnim.robotClip(ai, ev)
					check(c ~= nil and NpcAnim.CLIPS[c] ~= nil, ai .. " " .. ev .. " plays a clip")
				end
				for _, ev in { "hit", "hitHeavy", "stagger" } do
					check(NpcAnim.CLIPS[NpcAnim.robotClip(ai, ev) :: string] ~= nil, ai .. " " .. ev)
				end
				check(
					NpcAnim.CLIPS[NpcAnim.robotClip(ai, "windup") :: string].loop == true,
					ai .. "'s wind-up loops (held while the flag is up)"
				)
			end
			check(next(ais) ~= nil, "robot AI kinds found")
			for name, clip in NpcAnim.CLIPS do
				clean(name, clip, function(nm, t)
					return NpcAnim.sample(nm, t)
				end)
			end
			-- every robot strike has a wind-up, a hit and a recovery back to rest
			for _, name in
				{
					"hammer",
					"haymaker",
					"stab",
					"sweep",
					"shieldBash",
					"snatch",
					"claw",
					"lobThrow",
					"hookThrow",
				}
			do
				local c = NpcAnim.CLIPS[name]
				for joint, keys in c.joints do
					check(#keys >= 5, name .. " " .. joint .. " has wind-up, hit, follow and recovery")
					local last = keys[#keys]
					check(
						last[2] == keys[1][2] and last[3] == keys[1][3],
						name .. " " .. joint .. " ends where it began"
					)
				end
			end
			-- the people's gestures
			for kind, P in NpcAnim.PEOPLE do
				for _, e in P.idle do
					check(NpcAnim.CLIPS[e[1]] ~= nil, kind .. " idle " .. e[1])
				end
				for _, k in { "near", "talk", "far" } do
					if P[k] then
						check(NpcAnim.CLIPS[P[k]] ~= nil, kind .. " " .. k .. " " .. P[k])
					end
				end
			end
			check(NpcAnim.gesture("giver", 15, false, 0.9) == "wave", "a hero walking up gets a wave")
			check(NpcAnim.gesture("giver", 6, true, 0.9) == "talk", "and the talk once greeted")
			check(NpcAnim.gesture("giver", 200, false, 0.3) ~= "wave", "no one near: an idle gesture")
			-- bosses: every telegraphed attack has its own wind-up (BossPose, the boss pass)
			local nb = 0
			for boss, B in Config.Boss.bosses or {} do
				local set = BossPose.SETS and BossPose.SETS[boss]
				if set and B.attacks then
					for _, atk in B.attacks do
						check(set.attacks[atk.id] ~= nil, boss .. " animates " .. tostring(atk.id))
						nb += 1
					end
				end
			end
			check(nb == 0 or nb >= 8, "boss attacks checked (" .. nb .. ")")
		end
	)

	test("PT anims: the upper-body layer leaves the travel pose's legs alone", function()
		local legs = HeroAnim.LEGS
		local travel =
			{ "fly", "hover", "flyFast", "dive", "glide", "air", "dash", "arc", "swing", "wall", "wallrun" }
		table.insert(travel, "swim")
		table.insert(travel, "leapCrouch")
		table.insert(travel, "rideJet")
		for _, mode in travel do
			check(HeroAnim.CLIPS[mode] ~= nil, mode .. " is a mode pose")
			local lw, upper = HeroAnim.layer(mode, 30)
			check(
				lw == 0 and upper == true,
				mode .. ": an action shows none of its legs and only the Root's turn"
			)
		end
		local lw, upper = HeroAnim.layer(nil, 0)
		check(lw == 1 and upper == false, "standing: the whole body moves")
		lw = HeroAnim.layer(nil, 20)
		check(lw > 0 and lw < 1, "running: a little of the legs, the stride carries on")
		lw = HeroAnim.layer("sprint", 60)
		check(lw > 0 and lw < 1, "sprinting keeps its stride")
		-- a whole-body strike in the air: what HeroAnimator writes on the legs and the Root
		local root = HeroAnim.upperRoot({ 30, 180, -20, -1.2 })
		check(
			root[1] == 0 and root[2] == 180 and root[3] == 0 and root[4] == 0,
			"the Root keeps only the turn"
		)
		local act = HeroAnim.sample("groundPound", 0.5)
		check(act.RightKnee ~= nil and act.RightShoulder ~= nil, "a whole-body clip moves legs and arms")
		local lwF = HeroAnim.layer("fly", 50)
		for joint in act do
			local w = if legs[joint] then lwF else 1
			if legs[joint] then
				check(w == 0, "flying: " .. joint .. " is the flight pose's")
			else
				check(w == 1, "flying: " .. joint .. " still plays the cast")
			end
		end
		-- HeroAnimator uses the layer
		local src = fs.readFile("src/client/Controllers/HeroAnimator.luau")
		check(
			string.find(src, "HeroAnim.layer(r.modeTo, flat)", 1, true) ~= nil,
			"HeroAnimator layers by mode"
		)
		check(
			string.find(src, "HeroAnim.upperRoot", 1, true) ~= nil,
			"HeroAnimator trims the Root in the air"
		)
	end)

	test("PT anims: two-handed weapons keep both hands on the weapon", function()
		local n = 0
		for id, class in HeroAnim.TWO_HAND_WEAPON do
			local h = HeroAnim.TWO_HAND[class]
			local fit = Config.WeaponArt[id]
			-- the class's line matches the weapon mesh's own aim in the right hand
			if fit and fit.aim and fit.aim.at == "rhand" then
				local d = fit.aim.dir
				local dd = math.abs(d[1] - h.aim[1]) + math.abs(d[2] - h.aim[2]) + math.abs(d[3] - h.aim[3])
				check(dd < 0.05, "weapon " .. id .. "'s grip line matches its mesh")
			end
			local m = HeroAnim.WEAPON_MOVES[id]
			local list = table.clone(m.combo)
			for _, k in { "Z", "X", "C", "V" } do
				table.insert(list, m[k])
			end
			if class ~= "long" then
				table.insert(list, HeroAnim.HOLD_WEAPON[id]) -- the rifle's stance keeps its own arms (head clearance)
			end
			for _, name in list do
				if HeroAnim.ONE_HAND_MOVES[name] then
					continue
				end
				check(
					string.find(name, "@" .. class, 1, true) ~= nil,
					id .. " " .. name .. " is a two-handed copy"
				)
				local clip = HeroAnim.CLIPS[name]
				local worst, sum, k = 0, 0, 0
				local steps = math.max(8, math.floor(clip.dur * 60))
				for i = 0, steps do
					local miss = AnimIK.miss(arm, HeroAnim.sample(name, clip.dur * i / steps), h.aim, h.gap)
					worst = math.max(worst, miss)
					sum += miss
					k += 1
				end
				check(
					sum / k < 0.3,
					string.format("%d %s: the off hand stays on the weapon (mean %.2f)", id, name, sum / k)
				)
				check(worst < 0.9, string.format("%d %s: never far off it (worst %.2f)", id, name, worst))
				n += 1
			end
		end
		check(n >= 50, "two-handed moves checked (" .. n .. ")")
		-- the grabbed-robot clips for pt-combat: both hands on the robot, the heavy landing whole-body
		for _, name in HeroAnim.ROBOT_SWINGS do
			local clip = HeroAnim.CLIPS[name]
			check(clip ~= nil, name .. " exists")
			local h = HeroAnim.TWO_HAND.hilt
			local worst = 0
			for i = 0, 30 do
				worst =
					math.max(worst, AnimIK.miss(arm, HeroAnim.sample(name, clip.dur * i / 30), h.aim, h.gap))
			end
			check(worst < 0.9, string.format("%s holds the robot in both hands (worst %.2f)", name, worst))
		end
		check(HeroAnim.CLIPS.robotHold.loop == true, "the robot hold loops")
		check(
			HeroAnim.CLIPS.poundLandHeavy.joints.RightKnee ~= nil,
			"the heavy pound landing bends the knees"
		)
		local src = fs.readFile("src/client/Controllers/HeroAnimator.luau")
		check(string.find(src, '"robotHold"', 1, true) ~= nil, "a club carry shows the robot hold")
		check(
			string.find(src, "function HeroAnimator.robotSwing", 1, true) ~= nil,
			"pt-combat can play the swings"
		)
	end)

	test("PT anims: robots and people play their clips under the frame budget", function()
		local er = fs.readFile("src/client/Controllers/EnemyRenderer.luau")
		check(string.find(er, "npcLayer(", 1, true) ~= nil, "EnemyRenderer layers NpcAnim over the pose")
		check(string.find(er, "function EnemyRenderer.act", 1, true) ~= nil, "attack events reach the robot")
		local cc = fs.readFile("src/client/Controllers/CombatClient.luau")
		for _, ev in { '"shot"', '"slam"', '"lob"', '"rally"', '"mend"' } do
			check(string.find(cc, ev, 1, true) ~= nil, "CombatClient sends " .. ev)
		end
		local ng = fs.readFile("src/client/Controllers/NpcGestures.luau")
		check(string.find(ng, "FrameProf.wrap", 1, true) ~= nil, "NpcGestures is under FrameProf")
		for _, preset in { "low", "medium", "high" } do
			local Q = Config.Presets[preset] or (Config.Presets.list and Config.Presets.list[preset])
			if Q then
				check(
					type(Q.gestureNear) == "number" and type(Q.gestureMax) == "number",
					preset .. " gesture budget"
				)
			end
		end
		local sq = fs.readFile("src/server/Services/SideQuestService.luau")
		check(select(2, string.gsub(sq, '"NpcGesture"', "")) >= 2, "givers and helpers are tagged")
	end)
end
