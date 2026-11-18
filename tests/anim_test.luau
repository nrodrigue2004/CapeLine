-- Hero animations for every power (nate's playtest 2026-11-18: "animations for all attacks/powers too... my
-- character should have an animation"). Each power path has its own whole-body moves (Shared.HeroAnim
-- PATH_CLIPS); a cast that leaves the legs alone gets the standing brace (HeroAnimator). Called from
-- tests/run.luau; ONLY="Power anims" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local HeroAnim = require("../src/shared/HeroAnim")
	local JOINTS = {
		Root = true,
		Waist = true,
		Neck = true,
		RightShoulder = true,
		RightElbow = true,
		RightWrist = true,
		LeftShoulder = true,
		LeftElbow = true,
		LeftWrist = true,
		RightHip = true,
		RightKnee = true,
		RightAnkle = true,
		LeftHip = true,
		LeftKnee = true,
		LeftAnkle = true,
	}

	test("Power anims: every path has its own moves and every skill and super plays one", function()
		local paths = {}
		for _, arch in Config.Classes.order do
			for _, path in Config.Classes[arch].paths do
				table.insert(paths, path)
			end
		end
		check(#paths == 17, "17 paths")
		local perPath: { [string]: { [string]: boolean } } = {}
		for _, id in Config.Abilities.order do
			local row = Config.Abilities.list[id]
			if not row.weapon and row.slot ~= "basic" then
				local clip = HeroAnim.castClip(row, nil, 1)
				check(HeroAnim.CLIPS[clip] ~= nil, id .. " plays a clip")
				perPath[row.set] = perPath[row.set] or {}
				perPath[row.set][clip] = true
				if row.set ~= "Blade" then
					check(HeroAnim.PATH_CLIPS[row.set] ~= nil, id .. "'s path has its own moves")
				end
			end
		end
		for _, path in paths do
			local n = 0
			for _ in perPath[path] or {} do
				n += 1
			end
			check(n >= 2, string.format("%s's skills use %d different moves", path, n))
		end
	end)

	test("Power anims: the new clips are whole-body, in time and on real joints", function()
		for _, name in
			{
				"palmPush",
				"hurl",
				"stomp",
				"sweep",
				"quickDraw",
				"vanish",
				"combo3",
				"charge2",
				"temple",
				"raise",
				"ground",
			}
		do
			local clip = HeroAnim.CLIPS[name]
			check(clip ~= nil, name .. " exists")
			if clip then
				check(HeroAnim.movesLegs(name), name .. " moves the legs too")
				check(clip.joints.Waist ~= nil, name .. " moves the chest")
				check(clip.dur >= 0.4, name .. " lasts long enough to read")
				for joint, keys in clip.joints do
					check(JOINTS[joint] == true, name .. ": " .. joint .. " is an R15 joint")
					for _, k in keys do
						check(k[1] >= 0 and k[1] <= clip.dur + 1e-6, name .. ": keys inside the clip")
					end
				end
				-- the release pose differs from the start (it visibly moves)
				local a, b = HeroAnim.sample(name, 0), HeroAnim.sample(name, clip.dur * 0.45)
				local moved = 0
				for j, v in b do
					local w = a[j]
					if w then
						moved = math.max(
							moved,
							math.abs(v[1] - w[1]),
							math.abs(v[2] - w[2]),
							math.abs(v[3] - w[3])
						)
					end
				end
				check(moved >= 40, string.format("%s swings at least 40 degrees (%.0f)", name, moved))
			end
		end
		check(not HeroAnim.movesLegs("blast") and HeroAnim.CLIPS.brace ~= nil, "arm-only casts get the brace")
	end)

	test("Power anims: HeroAnimator braces arm-only casts when the hero stands", function()
		local src = fs.readFile("src/client/Controllers/HeroAnimator.luau")
		check(string.find(src, "HeroAnim.movesLegs", 1, true) ~= nil, "it asks the clip")
		check(string.find(src, 'HeroAnim.sample("brace", 0)', 1, true) ~= nil, "and blends the brace")
	end)
end
