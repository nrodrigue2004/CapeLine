-- WP11 (gap check 2026-11-18, gap G14): story systems that can hold more acts. Config.Story.acts, the act on
-- every mission and choice, Shared.StoryPlan's act-aware gates, steps and pin, the save's room for later
-- acts, and the Journal's act row with its locked "Act 2: coming soon" rows. Run by tests/run.luau
-- (ONLY=WP11 runs this file):
--   require("./acts_test")({ test = test, check = check, Config = Config, placePath = process.args[1] })
-- The future act built here is test data only (names "Test A" and "Test B"): no Act 2 or 3 story is decided.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local StoryPlan = require("../src/shared/StoryPlan")
	local ProfileSchema = require("../src/shared/ProfileSchema")
	local FunnelDef = require("../src/shared/FunnelDef")
	local S = Config.Story

	local function has(text: string, needle: string): boolean
		return string.find(text, needle, 1, true) ~= nil
	end

	-- a copy of Config whose Story is a deep copy (so a test can add a pretend act)
	local function withStory(edit: (any) -> ()): any
		local story = ProfileSchema.deepCopy(S)
		edit(story)
		return setmetatable({ Story = story }, { __index = Config })
	end

	-- a pretend Act 2: two missions after Act 1's six and one choice in its first (test data, not lore)
	local function actTwo(soon: boolean?): any
		return withStory(function(st)
			st.acts[2].soon = soon
			table.insert(st.missions, { num = 7, act = 2, id = "TestA", name = "Test A", minLevel = 10 })
			table.insert(st.missions, { num = 8, act = 2, id = "TestB", name = "Test B", minLevel = 12 })
			table.insert(st.choices, {
				num = 7,
				act = 2,
				mission = 7,
				skillPoints = 2,
				hero = { { label = "Left", flag = "testLeft" }, { label = "Right", flag = "testRight" } },
				villain = { { label = "Up", flag = "testUp" }, { label = "Down", flag = "testDown" } },
			})
		end)
	end

	local function clearAct1(story: any)
		for n = 1, 6 do
			StoryPlan.clear(story, n)
		end
	end

	test(
		"WP11: Config.Story has three acts: Act 1 out, Acts 2 and 3 coming soon; the data checks out",
		function()
			check(#S.acts == 3, "three acts")
			check(not StoryPlan.soon(Config, 1), "Act 1 is out")
			check(StoryPlan.soon(Config, 2) and StoryPlan.soon(Config, 3), "Acts 2 and 3 are coming soon")
			check(StoryPlan.soon(Config, 4), "an act not listed reads as coming soon")
			local problems = StoryPlan.validate(Config)
			check(#problems == 0, "the act data is valid: " .. table.concat(problems, "; "))
			for num, m in S.missions do
				check(m.act == 1, "mission " .. num .. " names Act 1")
			end
			for n, c in S.choices do
				check(c.act == 1, "choice " .. n .. " names Act 1")
			end
			check(#StoryPlan.actMissions(Config, 1) == 6, "Act 1 holds the 6 missions")
			check(
				#StoryPlan.actChoices(Config, 1) == 6,
				"Act 1 holds the 6 choices (one a mission, act1-choices)"
			)
			for a = 2, 3 do
				check(#StoryPlan.actMissions(Config, a) == 0, "Act " .. a .. " has no missions")
				check(#StoryPlan.actChoices(Config, a) == 0, "Act " .. a .. " has no choices")
			end
			check(
				#S.missions <= S.saveRoom.missions and #S.choices <= S.saveRoom.choices,
				"the save has room for today's missions and choices"
			)
			check(2 ^ S.saveRoom.missions <= 2 ^ 53, "the mission bits stay exact in a number")
		end
	)

	test("WP11 lore rule: a coming-soon act carries no story, only its number and 'coming soon'", function()
		for a, def in S.acts do
			for k in def do
				check(
					k == "num" or k == "soon",
					"act " .. a .. " has only num and soon (" .. tostring(k) .. ")"
				)
			end
		end
		check(string.format(S.actText.soon, 2) == "Act 2: coming soon", "Act 2's row")
		check(string.format(S.actText.soon, 3) == "Act 3: coming soon", "Act 3's row")
		check(string.format(S.actText.tab, 2) == "ACT 2", "Act 2's tab")
		-- nothing in the story data belongs to a later act
		local seen = {}
		local function walk(t: any, path: string)
			if type(t) ~= "table" or seen[t] then
				return
			end
			seen[t] = true
			for k, v in t do
				if k == "act" and path ~= "acts" then
					check(v == 1, path .. ".act is Act 1's (" .. tostring(v) .. ")")
				end
				walk(v, tostring(k))
			end
		end
		walk(S, "Story")
		-- the Journal's coming-soon rows draw only S.actText (no other words for a later act)
		local J = fs.readFile("src/client/Ui/Journal.luau")
		check(has(J, "string.format(S.actText.soon, act)"), "the locked row's words come from actText")
		check(has(J, "string.format(S.actText.tab, a)"), "the act tab's words come from actText")
		local code = string.gsub(J, "%-%-[^\n]*", "") -- the code without its comments
		check(
			not string.find(code, '"[^"\n]*[Aa][Cc][Tt] [23]', 1) and not has(code, "coming soon"),
			"no later-act words hard-coded in the Journal's code"
		)
	end)

	test("WP11: Act 1 plays exactly as before (gates, order, replays, pin, Skill Points)", function()
		local story = ProfileSchema.newCharacter().story
		check(story.act == 1, "a new hero is on Act 1")
		check(StoryPlan.currentAct(Config, story) == 1, "currentAct 1")
		check(StoryPlan.actState(Config, story, 1) == "open", "Act 1 is open")
		check(StoryPlan.actState(Config, story, 2) == "soon", "Act 2 is coming soon")
		for n = 1, 6 do
			check(StoryPlan.missionIndex(Config, n) == n, "mission " .. n .. " reads as " .. n)
			check(StoryPlan.prevMission(Config, n) == (if n == 1 then nil else n - 1), "before " .. n)
			check(StoryPlan.actLast(Config, n) == (n == 6), "the act's last is mission 6")
		end
		check(StoryPlan.state(Config, story, 1, 2) == "locked", "mission 2 waits for the opening")
		check(
			StoryPlan.pinnedText(Config, story, "hero") == "Mission 1: The Ceremony",
			"the pin reads as before"
		)
		StoryPlan.clear(story, 1)
		check(StoryPlan.state(Config, story, 2, 2) == "level", "mission 2 needs level 3")
		check(StoryPlan.state(Config, story, 40, 3) == "locked", "mission 3 waits for mission 2")
		check(
			StoryPlan.pinnedText(Config, story, "hero") == "Mission 2: Safehouse",
			"the next mission is pinned"
		)
		clearAct1(story)
		check(StoryPlan.actDone(Config, story, 1), "Act 1 done")
		check(StoryPlan.actState(Config, story, 1) == "done", "Act 1's state is done")
		check(StoryPlan.nextMission(Config, story) == nil, "nothing next while Act 2 is coming soon")
		check(StoryPlan.pinnedText(Config, story, "hero") == nil, "a coming-soon act is never pinned")
		check(StoryPlan.currentAct(Config, story) == 1, "the hero stays on Act 1")
		check(StoryPlan.canEnter(Config, story, 40, 4), "replays still open")
		check(StoryPlan.actSkillPoints(Config) == 8, "Act 1 grants 8 Skill Points")
		check(StoryPlan.actSkillPoints(Config, 1) == 8, "the same asked by act")
		check(StoryPlan.actSkillPoints(Config, 2) == 0, "Act 2 grants none yet")
		check(StoryPlan.actDone(Config, story, 2) == false, "a coming-soon act is never done")
	end)

	test("WP11: a future act is data only (missions, a choice, the gates and the pin follow)", function()
		local C = actTwo()
		local problems = StoryPlan.validate(C)
		check(#problems == 0, "the pretend Act 2 is valid: " .. table.concat(problems, "; "))
		local story = ProfileSchema.newCharacter().story
		check(StoryPlan.state(C, story, 50, 7) == "locked", "Act 2's first waits for Act 1")
		check(StoryPlan.actState(C, story, 2) == "locked", "Act 2 is locked behind Act 1")
		check(StoryPlan.prevMission(C, 7) == 6, "Act 2's first comes after Live")
		check(StoryPlan.missionIndex(C, 7) == 1 and StoryPlan.missionIndex(C, 8) == 2, "Act 2 counts from 1")
		clearAct1(story)
		check(StoryPlan.actDone(C, story, 1), "Act 1 is still done with Act 2 added")
		check(StoryPlan.currentAct(C, story) == 2, "the hero moves on to Act 2")
		check(StoryPlan.actState(C, story, 2) == "open", "Act 2 opens")
		check(StoryPlan.state(C, story, 9, 7) == "level", "Act 2's first has its own level gate")
		check(StoryPlan.canEnter(C, story, 10, 7), "and opens at its level")
		check(StoryPlan.state(C, story, 50, 8) == "locked", "Act 2's second waits for its first")
		check(StoryPlan.nextMission(C, story) == 7, "the next mission is Act 2's first")
		check(StoryPlan.pinnedText(C, story, "hero") == "Act 2, Mission 1: Test A", "the pin names the act")
		check(StoryPlan.actLast(C, 6) and StoryPlan.actLast(C, 8), "each act has its own last mission")
		check(not StoryPlan.actLast(C, 7), "Act 2's first is not its last")
		-- the choice slot an old 3-slot save lacks reads as not yet, and pays once
		check(#story.choices == 6, "today's save's 6 slots")
		local ok, fx = StoryPlan.pick(C, story, 7, 2, "hero")
		check(ok and fx and fx.flag == "testRight" and fx.skillPoints == 2, "Act 2's choice picks")
		check(not StoryPlan.pick(C, story, 7, 1, "hero"), "and only once")
		check(StoryPlan.actSkillPoints(C, 1) == 8 and StoryPlan.actSkillPoints(C, 2) == 2, "points by act")
		check(#StoryPlan.actChoices(C, 2) == 1 and StoryPlan.actChoices(C, 2)[1] == 7, "Act 2's choice")
		-- Act 1's own numbers do not move with Act 2 added (the rep pace after Act 1)
		local RepTiers = require("../src/shared/RepTiers")
		for _, side in { "hero", "villain" } do
			local a, b = RepTiers.act1(Config, side)
			local c, d = RepTiers.act1(C, side)
			check(a == c and b == d, side .. ": Act 1's rep range is the same with Act 2 added")
		end
		StoryPlan.clear(story, 7)
		StoryPlan.clear(story, 8)
		check(StoryPlan.actDone(C, story, 2) and StoryPlan.currentAct(C, story) == 2, "Act 2 done")
		check(StoryPlan.nextMission(C, story) == nil, "nothing next while Act 3 is coming soon")
		-- the same data while Act 2 is still marked soon: nothing in it opens, pins or picks
		local held = actTwo(true)
		local s2 = ProfileSchema.newCharacter().story
		clearAct1(s2)
		check(StoryPlan.state(held, s2, 50, 7) == "locked", "a coming-soon act's mission is locked")
		check(not StoryPlan.canEnter(held, s2, 50, 7), "and cannot be entered")
		check(
			StoryPlan.nextMission(held, s2) == nil and StoryPlan.pinnedText(held, s2, "hero") == nil,
			"no pin"
		)
		check(not StoryPlan.pick(held, s2, 7, 1, "hero"), "no pick")
		check(StoryPlan.currentAct(held, s2) == 1, "the hero stays on Act 1")
		check(#StoryPlan.validate(held) > 0, "the check catches missions in a coming-soon act")
	end)

	test("WP11: the act check catches bad act data", function()
		local function bad(edit: (any) -> (), why: string)
			check(#StoryPlan.validate(withStory(edit)) > 0, why)
		end
		bad(function(st)
			st.missions[3].act = nil
		end, "a mission without an act")
		bad(function(st)
			st.missions[3].act = 9
		end, "a mission in an act not listed")
		bad(function(st)
			st.acts[3].soon = nil
		end, "an act out after a coming-soon act")
		bad(function(st)
			st.acts[2].soon = nil
		end, "an act out with no missions")
		bad(function(st)
			st.acts[2].soon = nil
			table.insert(st.missions, { num = 7, act = 2, name = "Test A", minLevel = 10 })
			table.insert(st.missions, { num = 8, act = 1, name = "Test B", minLevel = 10 })
		end, "an Act 1 mission after Act 2's")
		bad(function(st)
			st.choices[2].act = 2
		end, "a choice in another act than its mission")
		bad(function(st)
			st.saveRoom = { missions = 5, choices = 12 }
		end, "more missions than the save holds")
	end)

	test("WP11: the save: Act 1's shape unchanged, room for later acts kept (additive)", function()
		local p = ProfileSchema.default()
		local st = p.characters[1].story
		check(st.act == 1 and st.missions == 0 and st.pinned == 0, "a new save starts on Act 1")
		check(
			#st.choices == 6 and st.choices[1] == 0 and st.choices[6] == 0,
			"six choice slots (act1-choices)"
		)
		check(
			ProfileSchema.VERSION >= 14,
			"no save version bump from the acts (14: side-content's lore pages and mobility ranks)"
		)
		-- today's saves load the same
		local back = ProfileSchema.load(ProfileSchema.deepCopy(p))
		local bs = back.characters[1].story
		check(bs.act == 1 and bs.missions == 0 and #bs.choices == 6, "a default save round trips")
		local old = ProfileSchema.default()
		local os_ = old.characters[1].story
		os_.missions = 63
		os_.choices = { 1, 2, 1 }
		os_.act = 1
		local ol = ProfileSchema.load(old).characters[1].story
		check(
			ol.missions == 63
				and ol.choices[1] == 1
				and ol.choices[2] == 2
				and ol.choices[3] == 1
				and #ol.choices == 6
				and ol.choices[4] == 0
				and ol.choices[6] == 0,
			"Act 1 done keeps (an old 3-slot save's new slots read 0, not yet)"
		)
		-- a newer build's later-act clears, picks and act are kept (they were clamped to 6 bits and 3 slots)
		local newer = ProfileSchema.default()
		local ns = newer.characters[1].story
		ns.missions = 2 ^ 8 - 1
		ns.choices = { 1, 2, 1, 2, 1, 2, 2, 1 }
		ns.act = 2
		local nl = ProfileSchema.load(newer).characters[1].story
		check(nl.missions == 255, "mission bits 7 and 8 survive a load")
		check(#nl.choices == 8 and nl.choices[7] == 2 and nl.choices[8] == 1, "choice slots 7 and 8 survive")
		check(nl.act == 2, "the act survives")
		-- junk is repaired inside the room
		local junk = ProfileSchema.default()
		local js = junk.characters[1].story
		js.missions = 2 ^ 40
		js.act = 9
		js.choices = { 7, -1, "x" }
		for i = 4, 20 do
			js.choices[i] = 1
		end
		local jl = ProfileSchema.load(junk).characters[1].story
		check(jl.missions == 2 ^ S.saveRoom.missions - 1, "mission bits clamp to the room")
		check(jl.act == #S.acts, "the act clamps to the acts listed")
		check(jl.choices[1] == 2 and jl.choices[2] == 0 and jl.choices[3] == 0, "bad picks repaired")
		check(#jl.choices == S.saveRoom.choices, "choice slots cut to the room")
		local short = ProfileSchema.default()
		short.characters[1].story.choices = { 1 }
		local sl = ProfileSchema.load(short).characters[1].story
		check(
			#sl.choices == #S.choices and sl.choices[1] == 1 and sl.choices[3] == 0,
			"short lists pad with 0"
		)
	end)

	test(
		"WP11: the Act 1 done funnel step reads Act 1's clears (story.act stays 1 while Act 2 waits)",
		function()
			local stage
			for _, s in FunnelDef.stages do
				if s.name == "Act 1 done" then
					stage = s
				end
			end
			check(stage ~= nil, "the Act 1 done stage")
			if not stage then
				return
			end
			local p = ProfileSchema.default()
			check(not stage.reached(p), "not on a new save")
			clearAct1(p.characters[1].story)
			check(stage.reached(p), "reached once Act 1's missions are cleared")
			check(p.characters[1].story.act == 1, "with the act still 1")
			local q = ProfileSchema.default()
			q.characters[1].story.act = 2
			check(stage.reached(q), "a save on Act 2 has it too")
		end
	)

	test("WP11: the runtime is act-aware (the Journal, the act save, Act 1 done checks)", function()
		local svc = fs.readFile("src/server/Services/StoryService.luau")
		check(
			has(svc, "StoryPlan.currentAct(Config, story)") and has(svc, "act = act,"),
			"StoryState sends the act"
		)
		check(has(svc, "story.act = act"), "the act is saved")
		for _, path in
			{
				"src/shared/HqRules.luau",
				"src/server/Services/BadgeService.luau",
				"src/server/Services/TaskForceService.luau",
			}
		do
			check(has(fs.readFile(path), "StoryPlan.actDone(Config,"), path .. " asks for Act 1 itself")
		end
		check(
			has(fs.readFile("src/server/Services/DevService.luau"), "StoryPlan.actMissions(Config, 1)"),
			"the Dev panel's Act 1 done clears Act 1's missions only"
		)
		check(
			has(fs.readFile("src/server/Services/MissionService.luau"), "StoryPlan.actLast(Config, run.num)"),
			"the act_done step fires on Act 1's last mission"
		)
		-- nothing in src reads "the last mission" as "Act 1 done"
		local function scan(dir: string)
			for _, name in fs.readDir(dir) do
				local path = dir .. "/" .. name
				if fs.isDir(path) then
					scan(path)
				elseif string.match(name, "%.luau$") then
					local text = fs.readFile(path)
					check(
						not string.find(text, "cleared%([^)]*#[%w%.]*missions%)"),
						path .. " checks Act 1 by its last mission number"
					)
				end
			end
		end
		scan("src")
		local J = fs.readFile("src/client/Ui/Journal.luau")
		check(has(J, "StoryPlan.actMissions(Config, shown)"), "the STORY tab lists the shown act's missions")
		check(has(J, "StoryPlan.actChoices(Config, shown)"), "and its choices")
		check(has(J, "StoryPlan.missionIndex(Config, num)"), "missions number within their act")
	end)

	local placePath = T.placePath
	if not placePath then
		return
	end

	test("WP11: the Journal's act row and locked rows at phone, tablet and PC sizes", function()
		local roblox = require("@lune/roblox")
		local UiSim = require("./uisim")
		local trees = UiSim.load(roblox.deserializePlace(fs.readFile(placePath)))
		local P = Config.Ui.phone
		local DEVICES = {
			{ name = "iPhone SE", w = 667, h = 375, top = 58, left = 0, right = 0, bottom = 0, touch = true },
			{
				name = "Android 640",
				w = 640,
				h = 360,
				top = 58,
				left = 0,
				right = 0,
				bottom = 0,
				touch = true,
			},
			{
				name = "iPhone 14",
				w = 844,
				h = 390,
				top = 58,
				left = 47,
				right = 47,
				bottom = 0,
				touch = true,
			},
			{
				name = "PC 1080p",
				w = 1920,
				h = 1080,
				top = 58,
				left = 0,
				right = 0,
				bottom = 0,
				touch = false,
			},
		}
		local story = ProfileSchema.newCharacter().story
		for n = 1, 3 do
			StoryPlan.clear(story, n)
		end
		StoryPlan.pick(Config, story, 1, 1, "hero")
		local states = {}
		for num in S.missions do
			states[num] = StoryPlan.state(Config, story, 12, num)
		end
		local journal = {
			side = "hero",
			act = 1,
			opening = 1,
			missions = story.missions,
			choices = story.choices,
			pinned = 0,
			perks = 0,
			rep = { 120, 0, 40 },
			states = states,
			sq = {},
		}
		for _, d in DEVICES do
			local sim = UiSim.new(trees, d)
			sim:run("InputController", sim:require("Client.Controllers.InputController").init)
			local Journal = sim:require("Client.Ui.Journal")
			sim:run("Journal", Journal.init)
			local StoryClient = sim:require("Client.Controllers.StoryClient")
			StoryClient.journal = journal
			local function report(tag: string)
				for _, issue in
					sim:issues({
						minTap = P.minTap,
						minText = P.minText,
						safe = true,
						minList = 90,
						only = { Journal = true },
					})
				do
					check(false, d.name .. " " .. tag .. ": " .. issue)
				end
			end
			local gui = sim.playerGui:FindFirstChild("Journal")
			local function find(name: string): any
				for _, c in gui:GetDescendants() do
					if c.Name == name then
						return c
					end
				end
				return nil
			end
			local function labels(): { string }
				local out = {}
				for _, c in gui:GetDescendants() do
					if c:IsA("TextLabel") or c:IsA("TextButton") then
						table.insert(out, c.Text)
					end
				end
				return out
			end
			check(
				sim:run("open story", function()
					Journal.open("story")
				end),
				d.name .. ": the Journal opens on STORY"
			)
			report("act 1")
			local row = find("ActTabs")
			check(row ~= nil, d.name .. ": the act row")
			for a = 1, 3 do
				local b = find("Act_" .. a)
				check(b ~= nil and b.Text == "ACT " .. a, d.name .. ": the ACT " .. a .. " tab")
			end
			check(find("ActSoon2") ~= nil and find("ActSoon3") ~= nil, d.name .. ": Acts 2 and 3 locked rows")
			local text = table.concat(labels(), "\n")
			check(
				has(text, "Act 2: coming soon") and has(text, "Act 3: coming soon"),
				d.name .. ": coming soon"
			)
			for num, m in S.missions do
				check(has(text, string.upper(m.name)), d.name .. ": Act 1 lists " .. m.name)
				check(has(text, num .. ". " .. string.upper(m.name)), d.name .. ": numbered as before")
			end
			check(has(text, "YOUR CHOICES") and has(text, "Save the Bridge"), d.name .. ": Act 1's choices")
			-- ACT 2: only its locked row, no story
			sim:tap(find("Act_2"))
			report("act 2")
			text = table.concat(labels(), "\n")
			check(has(text, "Act 2: coming soon"), d.name .. ": ACT 2 shows its locked row")
			check(find("ActSoon3") == nil, d.name .. ": and nothing else")
			for _, m in S.missions do
				check(
					not has(text, string.upper(m.name)),
					d.name .. ": no mission on ACT 2 (" .. m.name .. ")"
				)
			end
			check(
				not has(text, "YOUR CHOICES") and not has(text, "PIN"),
				d.name .. ": no choices or pin on ACT 2"
			)
			sim:tap(find("Act_3"))
			report("act 3")
			text = table.concat(labels(), "\n")
			check(
				has(text, "Act 3: coming soon") and find("ActSoon2") == nil,
				d.name .. ": ACT 3's locked row"
			)
			sim:tap(find("Act_1"))
			check(find("ActSoon2") ~= nil, d.name .. ": back on ACT 1")
			-- the other tabs still open on their own pages
			sim:run("open rep", function()
				Journal.open("rep")
			end)
			check(find("ActTabs") == nil, d.name .. ": the act row is the STORY tab's only")
			sim:run("open story again", function()
				Journal.open("story")
			end)
			for _, e in sim.errors do
				check(false, d.name .. ": " .. tostring(e))
			end
		end
	end)
end
