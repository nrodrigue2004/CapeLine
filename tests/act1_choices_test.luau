-- act1-choices (nate, 2026-11-19: "every mission should get a choice, for act 1 too"): the lore doc's approved
-- rows for The Ceremony, Safehouse and Live, the Act 1 hints at Lodestar's secret and the Chairman. Run by
-- tests/run.luau (ONLY=Act1Choices runs this file):
--   require("./act1_choices_test")({ test = test, check = check, Config = Config })

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local StoryPlan = require("../src/shared/StoryPlan")
	local GuidePlan = require("../src/shared/GuidePlan")
	local OpeningPlan = require("../src/shared/OpeningPlan")
	local PrologueCine = require("../src/shared/PrologueCine")
	local ProfileSchema = require("../src/shared/ProfileSchema")
	local PeopleLooks = require("../src/shared/PeopleLooks")
	local PocketLayout = require("../src/shared/PocketLayout")
	local RepTiers = require("../src/shared/RepTiers")
	local S = Config.Story

	local function has(text: string, needle: string): boolean
		return string.find(text, needle, 1, true) ~= nil
	end
	local function read(path: string): string
		return fs.readFile(path)
	end
	local function choiceStep(num: number, side: string): any
		for _, st in S.missions[num][side] or {} do
			if st.kind == "choice" then
				return st
			end
		end
		return nil
	end
	local function lineTexts(step: any, side: string, choices: { number }?): string
		local out = {}
		for _, l in StoryPlan.sceneLines(step, side, choices) do
			table.insert(out, l.who .. ": " .. l.text)
		end
		return table.concat(out, " | ")
	end

	test("Act1Choices: every Act 1 mission has one choice for each side, in the doc's words", function()
		local problems = StoryPlan.validate(Config)
		check(#problems == 0, "the story data is valid: " .. table.concat(problems, "; "))
		local guide = GuidePlan.validate(Config)
		check(#guide == 0, "every line is well formed: " .. table.concat(guide, "; "))
		local byMission = {}
		for n, c in S.choices do
			check(byMission[c.mission] == nil, "one choice for mission " .. c.mission)
			byMission[c.mission] = n
			for _, side in { "hero", "villain" } do
				check(#c[side] == 2, string.format("choice %d: two %s options", n, side))
			end
		end
		for _, num in StoryPlan.actMissions(Config, 1) do
			check(byMission[num] ~= nil, S.missions[num].name .. " has a choice")
		end
		check(byMission[1] == 4 and byMission[2] == 5 and byMission[6] == 6, "the new slots: 4, 5 and 6")
		check(
			byMission[3] == 1 and byMission[5] == 2 and byMission[4] == 3,
			"the old slots keep their missions"
		)
		-- the doc's rows (Story choices draft 1-1, 1-2, 1-6)
		local L = function(n: number, side: string): { string }
			return StoryPlan.labels(Config, n, side)
		end
		check(
			L(4, "hero")[1] == "Pull the Kid Clear" and L(4, "hero")[2] == "Catch the News Crew",
			"Ceremony, Vigil"
		)
		check(
			L(4, "villain")[1] == "Grab the Medal" and L(4, "villain")[2] == "Grab the Keycard",
			"Ceremony, Syndicate"
		)
		check(
			L(5, "hero")[1] == "Tell Your Real Name" and L(5, "hero")[2] == "Keep It Secret",
			"Safehouse, Vigil"
		)
		check(
			L(5, "villain")[1] == "Take the Deal" and L(5, "villain")[2] == "Demand a Bigger Cut",
			"Safehouse, Syndicate"
		)
		check(L(6, "hero")[1] == "Show Your Face" and L(6, "hero")[2] == "Keep the Mask On", "Live, Vigil")
		check(
			L(6, "villain")[1] == "Threaten Crane" and L(6, "villain")[2] == "Sell the Footage",
			"Live, Syndicate"
		)
		-- the missions ask them: a choice stage on each side (the Ceremony asks in the prologue's spark beat)
		for _, row in { { 2, 5 }, { 6, 6 } } do
			for _, side in { "hero", "villain" } do
				local st = choiceStep(row[1], side)
				check(
					st ~= nil and st.choice == row[2],
					S.missions[row[1]].name .. " asks choice " .. row[2] .. " as " .. side
				)
				check(st ~= nil and type(st.text) == "string" and #st.text > 0, "with its tracker words")
			end
		end
		check(
			S.missions[1].opening == true and S.opening.pick.choice == 4,
			"the Ceremony's is the prologue's"
		)
	end)

	test(
		"Act1Choices: each pick pays rep and a title or Credits only, once, and keeps Act 1's pacing",
		function()
			local titles = {}
			for n = 4, 6 do
				local c = S.choices[n]
				check(c.act == 1 and c.skillPoints == 0, "choice " .. n .. ": Act 1, no Skill Points")
				for _, side in { "hero", "villain" } do
					local sideRep = 0
					for o, opt in c[side] do
						check(
							opt.rep ~= nil and opt.rep[2] > 0,
							opt.label .. ": trust, fear or city reputation"
						)
						if opt.rep[1] == "side" then
							sideRep += 1
						end
						local rw = opt.reward
						check(type(rw) == "table", opt.label .. ": a reward")
						local keys = 0
						for k, v in rw do
							keys += 1
							check(k == "title" or k == "credits", opt.label .. ": a title or Credits only")
							if k == "title" then
								local bit = S.unlocks.titles[v]
								check(bit ~= nil and bit < 100, opt.label .. ": " .. v .. " is a story title")
								check(titles[v] == nil, v .. " is its own title")
								titles[v] = true
							end
						end
						check(keys == 1, opt.label .. ": one reward")
						local story = ProfileSchema.newCharacter(side).story
						local ok, fx = StoryPlan.pick(Config, story, n, o, side)
						check(
							ok and fx and fx.reward == rw and fx.skillPoints == 0,
							opt.label .. ": picks and pays"
						)
						check(story.choices[n] == o, opt.label .. ": saved in slot " .. n)
						check(
							StoryPlan.flag(Config, story, side, opt.flag),
							opt.label .. ": its flag reads back"
						)
						check(not StoryPlan.pick(Config, story, n, 3 - o, side), opt.label .. ": once only")
					end
					if side == "villain" or n ~= 5 then
						check(
							sideRep == 1,
							string.format("choice %d %s: one option pays the side's own track", n, side)
						)
					end
				end
			end
			check(StoryPlan.actSkillPoints(Config, 1) == 8, "Act 1 still grants 8 Skill Points")
			local lo = RepTiers.act1(Config, "villain")
			check(lo == 570, "the Syndicate's least Act 1 Fear is unchanged (" .. lo .. ")")
			local hlo, hhi = RepTiers.act1(Config, "hero")
			check(
				hlo == 420 and hhi < S.rep.ranks[5],
				"the Vigil's Act 1 Trust range (" .. hlo .. " to " .. hhi .. ")"
			)
			-- the server pays the reward (StoryService.pay: titles and Credits)
			local svc = read("src/server/Services/StoryService.luau")
			check(
				has(svc, "StoryService.pay(player, fx.reward, hero.level)"),
				"StoryService.choose pays the reward"
			)
		end
	)

	test("Act1Choices: old saves keep their meaning (the new slots read not yet)", function()
		local p = ProfileSchema.default()
		local c = p.characters[1]
		c.story.choices = { 2, 1, 2 } -- a save from before act1-choices
		c.story.missions = 63
		local loaded = ProfileSchema.load(p).characters[1].story
		check(#loaded.choices == 6, "padded to today's 6 slots")
		check(loaded.choices[1] == 2 and loaded.choices[2] == 1 and loaded.choices[3] == 2, "old picks kept")
		check(
			loaded.choices[4] == 0 and loaded.choices[5] == 0 and loaded.choices[6] == 0,
			"new slots not yet"
		)
		local flags = StoryPlan.flags(Config, loaded, "hero")
		check(
			flags.fakeChased and flags.insiderTrusted and flags.twinDestroyed,
			"the old flags read the same"
		)
		check(
			not flags.kidPulled and not flags.nameTold and not flags.faceShown,
			"no new flag from an old save"
		)
		check(
			ProfileSchema.VERSION >= 14,
			"no save version bump from the choices (the slots had room; 14 is side-content's lore and mobility ranks)"
		)
		check(#S.choices <= S.saveRoom.choices, "inside the save's 12 slots")
	end)

	test(
		"Act1Choices: lines change by side and pick (Safehouse and Live), and say lines after a pick",
		function()
			local offer, after
			for _, st in S.missions[2].hero do
				if st.kind == "scene" and st.lodestar == "door" and st.seconds == 20 then
					offer = st
				elseif st.kind == "scene" and st.seconds == 13 then
					after = st
				end
			end
			check(offer ~= nil and after ~= nil, "Safehouse: the offer and the after scenes")
			check(
				rawequal(after, S.missions[2].villain[7]),
				"the after scene is shared (both sides watch it)"
			)
			local ho, vo = lineTexts(offer, "hero"), lineTexts(offer, "villain")
			check(
				has(ho, "lodestar: One more thing") and not has(ho, "chairman"),
				"the Vigil hears Lodestar ask"
			)
			check(
				has(vo, "chairman: This is the Chairman") and not has(vo, "real name"),
				"the offer is the Chairman's"
			)
			check(
				has(lineTexts(after, "hero", { 0, 0, 0, 0, 1 }), "A real name"),
				"told: Lodestar thanks you"
			)
			check(has(lineTexts(after, "hero", { 0, 0, 0, 0, 2 }), "Keep it, then"), "kept: he understands")
			local none = lineTexts(after, "hero", { 0, 0, 0, 0, 0 })
			check(not has(none, "A real name") and not has(none, "Keep it, then"), "no pick: neither line")
			check(
				has(lineTexts(after, "villain", { 0, 0, 0, 0, 2 }), "A bigger cut"),
				"the Chairman answers the cut"
			)
			check(
				not has(lineTexts(after, "villain", { 0, 0, 0, 0, 1 }), "Lodestar thanks"),
				"no Vigil line for a villain"
			)
			-- Live: Crane's TV hint, and Patch on the pick
			local live = S.missions[6].hero[#S.missions[6].hero]
			check(
				live.kind == "scene" and rawequal(live, S.missions[6].villain[#S.missions[6].villain]),
				"Live ends on a shared scene"
			)
			local lh = lineTexts(live, "hero", { 0, 0, 0, 0, 0, 1 })
			check(
				has(lh, "crane:") and has(lh, "the Vigil buries its mistakes"),
				"Crane on air: the Vigil buries its mistakes"
			)
			check(has(lh, "You took the mask off"), "shown face: Patch")
			check(has(lineTexts(live, "villain", { 0, 0, 0, 0, 0, 2 }), "Footage sold"), "sold: Patch")
			-- the Ceremony's say lines (each option's own)
			for _, side in { "hero", "villain" } do
				for o = 1, 2 do
					local opt = StoryPlan.option(Config, 4, side, o)
					check(opt.say and #opt.say >= 1, opt.label .. ": says something after the pick")
				end
			end
			local hud = read("src/client/Ui/StoryHud.luau")
			check(
				has(hud, "StoryClient.Picked:Connect") and has(hud, "o and o.say"),
				"StoryHud says the option's lines"
			)
			check(
				has(hud, "StoryPlan.sceneLines(st, side, choices)"),
				"and reads scene lines by the hero's picks"
			)
			check(
				has(read("src/client/Controllers/StoryClient.luau"), "StoryClient.Picked:Fire(c.id, option)"),
				"the pick signal"
			)
		end
	)

	test("Act1Choices: Act 1 hints at Lodestar's secret (the torn photo, the dodge, the TV line)", function()
		local l = PocketLayout.build(Config, 1, "dungeon")
		local photo, card = nil, 0
		for _, b in l.boxes do
			if b.ref == "tornPhoto" then
				photo = b
			end
			if b.color == "white" and b.tag == "decor" then
				card += 1
			end
		end
		check(
			photo ~= nil and photo.ghost == true,
			"the torn photo's frame by the safehouse door (ghost decor)"
		)
		check(card == 2, "its print in two halves (plain cards, nothing drawn)")
		local door = l.points.door
		check(photo ~= nil and math.abs(photo.cx - door[1]) < 16, "near the door the camera looks at")
		local after = S.missions[2].hero[7]
		local h = lineTexts(after, "hero", {})
		check(
			has(h, "torn photo") and has(h, "old students"),
			"Patch asks about the photo and his old students"
		)
		check(has(h, "lodestar: Old friends. A long time ago."), "and Lodestar dodges")
		check(has(lineTexts(after, "villain", {}), "torn photo"), "the Syndicate sees the photo too")
	end)

	test(
		"Act1Choices: the Chairman, the Syndicate's masked boss, wears a catalog face under a creator mask",
		function()
			local sp = S.guides.speakers.chairman
			check(sp ~= nil and sp.name == "THE CHAIRMAN" and sp.style == "radio", "a radio speaker")
			local face, hair, err = PeopleLooks.catalogPick(Config, "chairman")
			check(face == "Sinister" and hair == false and err == nil, "a catalog face, no hair (hairless)")
			check(sp.look.pieces.head == "Full Face Plate", "masked with a creator mask piece")
			check(sp.look.pieces.hair == nil and sp.look.pieces.beard == nil, "no modelled hair or beard")
			local cov = GuidePlan.coverage(Config, 2, "villain")
			check((cov.chairman or 0) >= 3, "he speaks to the Syndicate in Safehouse")
			check((GuidePlan.coverage(Config, 2, "hero").chairman or 0) == 0, "never to the Vigil")
		end
	)

	test(
		"Act1Choices: the Ceremony's choice moment: after the Spark, never on the quick-time prompts",
		function()
			local P = S.opening.pick
			check(P.delay > 0 and P.wait >= 10 and P.after > 0, "a delay, a wait and a beat after")
			local f = function(...)
				return OpeningPlan.sparkPick(Config, ...)
			end
			check(f(nil, 0, nil, nil) == "wait", "nothing before the Spark")
			check(f(P.delay * 0.5, 0, nil, nil) == "wait", "the shield pops first")
			check(f(P.delay, 0, nil, nil) == "ask", "then the card")
			check(f(P.delay, 2, nil, nil) == "skip", "a replay with a pick is not asked again")
			check(f(5, 0, 1, nil) == "hold", "the card holds the beat")
			check(f(30, 0, P.wait, nil) == "close", "no pick in time: the card goes, the slot stays open")
			check(f(30, 1, P.wait + 1, P.after * 0.5) == "wait", "the pick's lines play")
			check(f(30, 1, 2, P.after) == "leap", "then the leap")
			-- prologue-cine (2026-11-20): the Spark itself is the beat's one prompt; the card comes after it
			local sparkSegs = PrologueCine.beat(Config, { spark = { 0, 0, 0 }, kid = { 2, 0, 0 } }, "spark")
			local prompts, last = 0, nil
			for _, seg in sparkSegs do
				if seg.prompt then
					prompts += 1
					last = seg
				end
			end
			check(
				prompts == 1 and last.spark == true and not OpeningPlan.HOPS.spark,
				"the spark beat's only prompt is the Spark, before the card"
			)
			local svc = read("src/server/Services/OpeningService.luau")
			check(has(svc, "OpeningPlan.sparkPick("), "OpeningService runs the moment")
			check(
				has(svc, "StoryService.ask(r.player, n, StoryPlan.labels(Config, n, r.side)"),
				"with the side's own labels"
			)
			check(has(svc, "StoryService.choose(r.player, n, option)"), "and pays through StoryService")
			check(has(svc, "local held = r.paused"), "the stuck clock is held while the card is up")
			local fx = read("src/client/Fx/PrologueFx.luau")
			check(has(fx, 'if step == "spark" and o.choosing then'), "the device plays it as a camera beat")
			check(
				has(fx, 'CinemaClient.play({\n\t\towner = "prologue",\n\t\tkey = PICK_KEY'),
				"through CinemaClient"
			)
		end
	)
end
