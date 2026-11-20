-- The onboarding check (overnight queue item 8, 2026-11-18): a brand-new player's first 60 seconds, from join
-- through the loading screen, the creator and the Ceremony prologue to first_spark and the first incident.
-- The timeline is a pure sim (tests/onboarding_sim.luau) on the real numbers; the fixes that only the
-- services can hold are checked in their source, as the other audits do. Called from tests/run.luau:
--   require("./onboarding_test")({ test = test, check = check, Config = Config, world = world })
-- ONLY="Onboarding" runs just these; ONBOARD_PRINT=1 also prints the timeline (today's and the old numbers').

return function(T: any)
	local test, check, Config, world = T.test, T.check, T.Config, T.world
	local fs = require("@lune/fs")
	local process = require("@lune/process")
	local OpeningPlan = require("../src/shared/OpeningPlan")
	local GuidePlan = require("../src/shared/GuidePlan")
	local ProfileSchema = require("../src/shared/ProfileSchema")
	local Rng = require("../src/shared/Rng")
	local Sim = require("./onboarding_sim")
	local PrologueRow = require("../src/shared/PrologueRow")
	local BuildingState = require("../src/shared/BuildingState")

	local O = Config.Story.opening
	local P = Config.Ui.prologue
	local LIMIT = 3 -- the longest stretch with nothing to do or watch (the brief: waits over about 3 s)
	local SIDES = { "hero", "villain" }

	local function src(path: string): string
		return fs.readFile(path)
	end
	local function has(path: string, needle: string): boolean
		return string.find(src(path), needle, 1, true) ~= nil
	end

	-- the numbers before this check (for the printed comparison only)
	local function oldConfig(): any
		local C = table.clone(Config)
		local S = table.clone(Config.Story)
		local OO = table.clone(O)
		OO.beats = { ceremony = 30, scan = 8, suit = 3.5, rescue = 9, title = 10 }
		local lines = table.clone(O.lines)
		local function at(beat: string, times: { number })
			local l = {}
			for i, row in O.lines[beat] do
				local r = table.clone(row)
				r.at = times[i]
				l[i] = r
			end
			lines[beat] = l
		end
		at("ceremony", { 1, 6.5, 12, 16, 22 })
		at("scan", { 0.5, 4.5 })
		at("rescue", { 1.2, 5.5, 7 })
		OO.lines = lines
		S.opening = OO
		C.Story = S
		local U = table.clone(Config.Ui)
		local PP = table.clone(P)
		PP.goals = {}
		U.prologue = PP
		C.Ui = U
		return C
	end

	if process.env.ONBOARD_PRINT then
		for _, side in SIDES do
			print(
				"\n[onboarding] BEFORE ("
					.. side
					.. ")\n"
					.. Sim.format(Sim.timeline(oldConfig(), side, { carry = false }))
			)
			print("\n[onboarding] AFTER (" .. side .. ")\n" .. Sim.format(Sim.timeline(Config, side)))
		end
	end

	---------------------------------------------------------------------------
	-- The timeline
	---------------------------------------------------------------------------

	test("Onboarding: the first 60 s have no gap over 3 s and every beat has a goal on screen", function()
		for _, side in SIDES do
			local tl = Sim.timeline(Config, side)
			for _, r in tl.rows do
				if r.t0 - tl.prologueAt < 60 or r.t0 < 60 then
					check(r.gap <= LIMIT, string.format("%s (%s): gap %.1f s", r.name, side, r.gap))
				end
				-- every row asks for something: watch, a marker word, a fight, the creator, or the spinner
				if r.kind ~= "wait" then
					check(r.goal ~= nil and r.goal ~= "", r.name .. " (" .. side .. "): a goal on screen")
				end
			end
			-- the brief's beats in order: the creator, the prologue, the Spark, the first incident
			check(tl.prologueAt > 0, "the creator comes before the prologue")
			check(
				(tl.firstControl :: number) - tl.prologueAt <= 30,
				string.format(
					"the hero has control by 30 s into the prologue (%.1f)",
					tl.firstControl - tl.prologueAt
				)
			)
			check(
				(tl.sparkAt :: number) - tl.prologueAt <= 40,
				string.format("first_spark well inside the KPI's 60 s (%.1f)", tl.sparkAt - tl.prologueAt)
			)
			check(tl.incidentAt > tl.prologueAt + tl.total, "the first incident after the title")
		end
	end)

	test("Onboarding: every play beat with a place to reach names it under the marker", function()
		for step in Sim.TARGETS do
			local w = P.goals[step]
			if Config.Story.opening.qte.beats[step] then
				-- prologue-cine (2026-11-20): a directed beat shows its prompts, never a marker or its word
				check(w == nil, step .. ": no marker word on a directed beat")
			else
				check(type(w) == "string" and #w > 0 and #w <= 12, step .. ": a short goal word")
				check(w == string.upper(w), step .. ": in capitals like the verb buttons")
			end
		end
		for step in P.goals do
			check(Sim.TARGETS[step] == true, step .. ": a goal word only where the server sends a target")
			check(not OpeningPlan.CUT[step], step .. ": never on a camera beat")
		end
		-- the fights have their verbs; the camera beats none
		for _, step in OpeningPlan.STEPS do
			local v = P.verbs[step]
			check(type(v) == "table", step .. ": verbs listed")
			if OpeningPlan.CUT[step] then
				check(#v == 0, step .. ": no buttons on a camera beat")
			end
		end
		check(
			table.find(P.verbs.fight, "Basic") ~= nil and table.find(P.verbs.swarm, "Basic") ~= nil,
			"fight verbs"
		)
		local server = src("src/server/Services/OpeningService.luau")
		for step in Sim.TARGETS do
			check(
				string.find(server, 's == "' .. step .. '"', 1, true) ~= nil,
				"OpeningService sends a target on " .. step
			)
		end
		check(
			has("src/client/Ui/StoryHud.luau", "U.prologue.goals[step]"),
			"StoryHud puts the word under the prologue's marker"
		)
		check(
			has("src/client/Controllers/StoryClient.luau", "StoryClient.VERBS = Config.Ui.prologue.verbs"),
			"the client's verbs are the ones checked here"
		)
	end)

	test("Onboarding: every camera-beat line stays up for its reading time", function()
		for _, side in SIDES do
			for _, step in OpeningPlan.STEPS do
				if OpeningPlan.CUT[step] then
					local dur = OpeningPlan.limit(Config, step)
					local lines = Sim.beatLines(Config, step, side, dur)
					for _, l in lines do
						check(
							l.shown >= l.read * 0.97,
							string.format(
								"%s (%s) %q: %.1f s of %.1f",
								step,
								side,
								string.sub(l.text, 1, 24),
								l.shown,
								l.read
							)
						)
					end
				end
			end
		end
	end)

	test(
		"Onboarding: a quick player still hears Patch's first words (lines carry to the next beat)",
		function()
			for _, side in SIDES do
				local tl = Sim.timeline(Config, side)
				-- the leap beat ends about 3 s in for a quick player: both its lines still play
				for _, l in OpeningPlan.lines(Config, "leap", side) do
					check(
						(tl.heard[l.text] or 0) >= P.heard * GuidePlan.duration(Config, l.text),
						"heard: " .. string.sub(l.text, 1, 30)
					)
				end
				-- the suit beat (3.5 s) cuts its line short; it plays again at the start of the descent
				for _, l in OpeningPlan.lines(Config, "suit", side) do
					check(
						(tl.heard[l.text] or 0) >= P.heard * GuidePlan.duration(Config, l.text),
						"heard after the suit: " .. string.sub(l.text, 1, 30)
					)
				end
				-- and the carry never pushes a beat's own first line more than one carried pair later
				for _, r in tl.rows do
					if r.kind == "play" and r.lines then
						local own = OpeningPlan.lines(Config, r.name, side)[1]
						for _, l in r.lines do
							if own and l.text == own.text then
								check(l.at - own.at <= 9.5, r.name .. ": its first line comes soon enough")
							end
						end
					end
				end
				-- without the carry the old run lost them (the bug this fixes)
				local old = Sim.timeline(Config, side, { carry = false })
				local lost = false
				for _, l in OpeningPlan.lines(Config, "leap", side) do
					lost = lost or (old.heard[l.text] or 0) < P.heard * GuidePlan.duration(Config, l.text)
				end
				check(lost, "the leap beat's lines were cut short for a quick player before")
			end
		end
	)

	test("Onboarding: GuidePlan's carry rules", function()
		local list = {
			{ at = 1, who = "patch", text = "One line of some length here." },
			{ at = 5, who = "patch", text = "A second line, a little longer than the first." },
		}
		check(#GuidePlan.unheard(Config, list, 20, 0.7, 2) == 0, "a beat that ran its course: all heard")
		local u = GuidePlan.unheard(Config, list, 2, 0.7, 2)
		check(
			#u == 2 and u[1].text == list[1].text,
			"ended at 2 s: the first cut short, the second never said"
		)
		check(#GuidePlan.unheard(Config, list, 2, 0.7, 1) == 1, "at most `max`")
		local merged = GuidePlan.withCarry(Config, u, { { at = 0.5, who = "crane", text = "Own line." } })
		check(#merged == 3 and merged[1].at == 0.3, "the carried first, from 0.3 s")
		check(
			merged[3].at >= merged[2].at + GuidePlan.duration(Config, merged[2].text) - 1e-6,
			"the beat's own line waits for the carried one's reading time"
		)
		local same = GuidePlan.withCarry(Config, {}, { { at = 0.5, who = "crane", text = "Own line." } })
		check(same[1].at == 0.5, "nothing carried: the beat's own timing")
		check(P.carry >= 1 and P.carry <= 3 and P.heard > 0.4 and P.heard < 1, "carry numbers in range")
	end)

	test("Onboarding: the retimed camera beats keep every line and their order", function()
		for _, side in SIDES do
			for _, step in { "ceremony", "scan", "rescue" } do
				local l = OpeningPlan.lines(Config, step, side)
				for i = 2, #l do
					check(l[i].at > l[i - 1].at, step .. ": lines in order")
				end
			end
			check(#OpeningPlan.lines(Config, "ceremony", side) == 5, "Crane's five ceremony lines")
			check(#OpeningPlan.lines(Config, "rescue", side) == 3, "the rescue's three lines")
		end
		check(O.beats.ceremony <= 24, "the ceremony is no longer the old 30 s")
		-- the camera shots are shares of the beat (PrologueFx), so they shrink with it
		check(has("src/client/Fx/PrologueFx.luau", "t1 = B * 0.25"), "the ceremony's shots follow its length")
	end)

	---------------------------------------------------------------------------
	-- The bugs (each fails on the code before its fix)
	---------------------------------------------------------------------------

	test(
		"Onboarding: a rejoin mid-prologue gets no PLAY menu over the ceremony (and never a stuck hold)",
		function()
			local p = ProfileSchema.default()
			local c = ProfileSchema.active(p)
			c.created = 1
			c.story.opening = 0
			check(
				ProfileSchema.clientView(p).opening == 0,
				"the client view says the prologue is still to finish"
			)
			c.story.opening = 1
			check(ProfileSchema.clientView(p).opening == 1, "and when it is done")
			local menu = src("src/client/Ui/MainMenu.luau")
			check(
				string.find(menu, "made and p.opening ~= 0", 1, true) ~= nil,
				"MainMenu: returning only past the prologue"
			)
			check(
				string.find(menu, 'kind == "createFirst" and mode == "returning"', 1, true) ~= nil,
				"MainMenu: Create First may replace the returning menu"
			)
			check(
				type(O.holdMax) == "number" and O.holdMax >= 60 and O.holdMax <= 300,
				"a held ceremony's cap"
			)
			check(
				has("src/server/Services/OpeningService.luau", "now - r.heldAt > O.holdMax"),
				"OpeningService: a hold that never hears back takes the Create First path"
			)
		end
	)

	test("Onboarding: the mentor picker waits for the prologue's end, not its level-up", function()
		local mentor = src("src/server/Services/MentorService.luau")
		local at = string.find(mentor, "local function maybeAsk", 1, true) or 0
		local stop = string.find(mentor, "\nend\n", at, true) or #mentor
		check(
			string.find(string.sub(mentor, at, stop), "OpeningService.running(player)", 1, true) ~= nil,
			"maybeAsk (HeroService.Leveled calls it as the title pays level 3) skips a running prologue"
		)
		check(Config.Mentors.afterOpening >= 4, "the picker's own delay after the title")
	end)

	test("Onboarding: the daily card is not lost to a long creator plus the prologue", function()
		local daily = src("src/server/Services/DailyService.luau")
		check(
			string.find(daily, 'hero.scene == "creator" or hero.scene == "opening"', 1, true) ~= nil,
			"the creator and the prologue do not use up the card's wait"
		)
		check(
			string.find(daily, "if not free(player) then", 1, true) == nil
				and string.find(daily, "or not free(player) then", 1, true) ~= nil,
			"the card still waits for a free hero"
		)
	end)

	test("Onboarding: join cards wait their turn (loading, menu, creator, prologue, each other)", function()
		local gate = src("src/client/Ui/PopupGate.luau")
		for _, needle in
			{
				"MainMenu.isOpen()",
				"CreatorScreen.isOpen()",
				"StoryClient.inOpening()",
				"CinemaClient.playing()",
				'"Loading"',
			}
		do
			check(string.find(gate, needle, 1, true) ~= nil, "PopupGate waits on " .. needle)
		end
		for path, name in
			{
				["src/client/Ui/DailyHud.luau"] = "daily",
				["src/client/Ui/MentorHud.luau"] = "mentorPick",
				["src/client/Ui/BoardHud.luau"] = "board",
			}
		do
			local s = src(path)
			check(string.find(s, 'PopupGate.later("' .. name .. '"', 1, true) ~= nil, path .. ": waits")
			check(
				string.find(s, 'PopupGate.card("' .. name .. '"', 1, true) ~= nil,
				path .. ": counts as a card"
			)
		end
		check(Config.Ui.popups.settle > 0 and Config.Ui.popups.giveUp >= 120, "popup numbers")
	end)

	test("Onboarding: a missed hop goes back to the last roof, not a 90 s street wait", function()
		local F = O.fall
		check(type(F) == "table" and F.drop >= 6 and F.after > 0 and F.after <= 2, "fall numbers")
		local server = src("src/server/Services/OpeningService.luau")
		check(string.find(server, "O.fall.drop", 1, true) ~= nil, "OpeningService watches for a fall")
		check(string.find(server, "lastRoof(r)", 1, true) ~= nil, "and respawns on the last roof reached")
		-- for many routes: a good hop never dips under the floor (the lower roof's top less the drop), and the
		-- street is always far below it
		local gy = Config.City.ground.y
		for k = 1, 12 do
			local r = OpeningPlan.route(Config, world, Rng.new(k * 31))
			if r then
				for i = 1, #r.roofs - 1 do
					local a, b = r.roofs[i], r.roofs[i + 1]
					local floor = math.min(a[2], b[2]) - F.drop
					check(floor > gy + 6, "route " .. k .. " hop " .. i .. ": the street is below the floor")
				end
			end
		end
	end)

	test("Onboarding: with every subway lane busy the fight is at the subway steps", function()
		local server = src("src/server/Services/OpeningService.luau")
		check(
			string.find(server, "return r.route.entrance", 1, true) ~= nil,
			"startAt: the steps when laneless"
		)
		check(
			string.find(server, "OpeningPlan.startPoint(", 1, true) ~= nil
				and select(2, string.gsub(server, "OpeningPlan%.startPoint%(", "")) == 1,
			"every other place goes through startAt"
		)
	end)

	test("Onboarding: first_spark's value is seconds into the prologue (the KPI's clock)", function()
		check(
			has(
				"src/server/Services/OpeningService.luau",
				"Analytics.event(r.player, name, math.floor(os.clock() - r.startedAt))"
			),
			"the prologue's funnel events count from the prologue's start"
		)
	end)

	test("Onboarding: controllers can work the main menu, the creator and SKIP", function()
		check(
			has("src/client/Ui/MainMenu.luau", "Kit.padFocus(gui)"),
			"the main menu selects its first button"
		)
		check(
			has("src/client/Ui/CreatorScreen.luau", "Kit.padFocus(gui)"),
			"the creator selects its first button"
		)
		check(has("src/client/Ui/Hud.luau", "Kit.modalButton()"), "Select goes back into an open pick")
		local cinema = src("src/client/Ui/CinemaHud.luau")
		check(string.find(cinema, '"SKIP (B)"', 1, true) ~= nil, "SKIP names its pad button")
		check(
			string.find(cinema, 'action == "Down" and InputController.device == "gamepad"', 1, true) ~= nil,
			"B skips"
		)
	end)

	test("Onboarding: the loading screen stays up until the hero is loaded, with a status line", function()
		local ls = src("src/first/LoadingScreen.client.luau")
		check(string.find(ls, 'GetAttribute("HeroLoaded")', 1, true) ~= nil, "it waits for the hero")
		check(string.find(ls, "os.clock() - start < 12", 1, true) ~= nil, "never past 12 s")
		check(string.find(ls, '"LOADING YOUR HERO"', 1, true) ~= nil, "it says what it is loading")
		-- (Everything Left 420) it preloads the first minutes' art and waits for it at most `grace` past the hero
		local P = Config.Ui.preload
		check(
			P ~= nil and #P.sets >= 5 and P.grace > 0 and P.grace <= 4,
			"the preload list and its short grace"
		)
		for _, name in P.sets do
			check(fs.isFile("art/models/" .. name .. ".rbxm"), name .. " is an imported art set")
		end
		check(string.find(ls, "PreloadAsync(list)", 1, true) ~= nil, "it preloads them")
		check(
			string.find(ls, "os.clock() - heroAt < grace and os.clock() - start < 12", 1, true) ~= nil,
			"a short wait, inside the cap"
		)
		check(
			has("src/server/Services/HeroService.luau", 'SetAttribute("HeroLoaded", true)'),
			"HeroService sets it once the save is on the hero"
		)
	end)

	test("Onboarding: the chase row is held whole only while a prologue is on it", function()
		local DS = Config.Destruction
		local route = nil
		for k = 1, 20 do
			route = route or OpeningPlan.route(Config, world, Rng.new(k * 17))
		end
		check(route ~= nil, "a route")
		local r = route :: any
		local ids = PrologueRow.ids(world, r.roofs)
		check(
			#ids == #r.roofs,
			"every roof of the chase is a building (" .. #ids .. " of " .. #r.roofs .. ")"
		)
		check(#ids == O.roofs.count, "the rooftop row's six roofs")
		-- the beats that hold it: the leap, the chase and the suit on the last roof; never the plaza or the subway
		for _, step in OpeningPlan.STEPS do
			local want = step == "leap" or step == "chase" or step == "suit"
			check(PrologueRow.holds(Config, step) == want, step .. ": holds the row " .. tostring(want))
		end
		-- two heroes' prologues on one server, through the same pin rule as the side quest roofs
		local book = BuildingState.new(DS, world.buildings)
		local function pin(id: number, on: boolean)
			BuildingState.pin(book, id, on)
		end
		local function idsFn()
			return PrologueRow.ids(world, r.roofs)
		end
		local a = PrologueRow.sync(nil, PrologueRow.holds(Config, "leap"), idsFn, pin) -- A reaches the roofs
		local b = PrologueRow.sync(nil, PrologueRow.holds(Config, "chase"), idsFn, pin) -- B too
		local first = ids[1]
		check(BuildingState.pinned(book, first), "held while a prologue is on the row")
		local st = BuildingState.hit(DS, book, first, 1e9, 10)
		check(st == BuildingState.INTACT, "a huge hit knocks nothing out of a held roof")
		a = PrologueRow.sync(a, PrologueRow.holds(Config, "chase"), idsFn, pin) -- A stays: no second pin
		check(book.pins[first] == 2, "one hold per run, not per beat")
		a = PrologueRow.sync(a, PrologueRow.holds(Config, "descend"), idsFn, pin) -- A goes down to the subway
		check(a == nil and BuildingState.pinned(book, first), "still held while B is on it")
		b = PrologueRow.sync(b, false, idsFn, pin) -- B finishes (or leaves)
		check(b == nil and not BuildingState.pinned(book, first), "released once no prologue is on it")
		local after = BuildingState.hit(DS, book, first, 1e9, 20)
		check(after ~= BuildingState.INTACT, "and breakable again")
		-- the server lets go on every way out
		local server = src("src/server/Services/OpeningService.luau")
		check(
			select(2, string.gsub(server, "holdRow%(r, false%)", "")) >= 3,
			"OpeningService releases it in finish, stop and on leaving"
		)
		check(
			string.find(server, "holdRow(r, PrologueRow.holds(Config, step))", 1, true) ~= nil,
			"and follows each beat"
		)
		check(string.find(server, "BuildingService.pin", 1, true) ~= nil, "through BuildingService.pin")
	end)

	test("Onboarding: a prologue's start repairs the chase row's wrecked buildings (interim pick)", function()
		local DS = Config.Destruction
		check(DS.repair.prologueRow == true, "on (Config.Destruction.repair.prologueRow)")
		local route = nil
		for k = 1, 20 do
			route = route or OpeningPlan.route(Config, world, Rng.new(k * 17))
		end
		check(route ~= nil, "a route")
		local r = route :: any
		local ids = PrologueRow.ids(world, r.roofs)
		check(#ids == O.roofs.count, "the six roofs")
		-- another player's fight collapsed one roof and damaged another before this prologue began
		local book = BuildingState.new(DS, world.buildings)
		BuildingState.hit(DS, book, ids[2], 1e9, 5)
		BuildingState.hit(DS, book, ids[4], book.maxHp[ids[4]] * (DS.damagedAt + 0.05), 5)
		check(book.state[ids[2]] == BuildingState.COLLAPSED, "roof 2 collapsed")
		check(book.state[ids[4]] == BuildingState.DAMAGED, "roof 4 damaged")
		local function state(id: number): number
			return book.state[id] or 0
		end
		local function repair(id: number)
			BuildingState.repair(book, id)
		end
		-- the switch off: drones only, as before
		local off = table.clone(Config)
		off.Destruction = table.clone(DS)
		off.Destruction.repair = table.clone(DS.repair)
		off.Destruction.repair.prologueRow = false
		check(#PrologueRow.mend(off, ids, state, repair) == 0, "off: nothing repaired")
		check(book.state[ids[2]] == BuildingState.COLLAPSED, "off: still rubble")
		-- on: both are whole again (through the drones' repair: full HP, sent to devices as fixed), the rest untouched
		local fixed = PrologueRow.mend(Config, ids, state, repair)
		check(
			#fixed == 2 and table.find(fixed, ids[2]) and table.find(fixed, ids[4]),
			"the two wrecked roofs"
		)
		for _, id in ids do
			check(book.state[id] == BuildingState.INTACT, "roof building " .. id .. " whole")
			check(book.hp[id] == book.maxHp[id], "roof building " .. id .. " at full health")
		end
		local sent = BuildingState.takeFixed(book)
		check(#sent == 2, "devices hear of both repairs")
		check(#PrologueRow.mend(Config, ids, state, repair) == 0, "a whole row needs nothing")
		-- the server: on start (before the run exists, so before any beat) and as the hold begins (the leap)
		local server = src("src/server/Services/OpeningService.luau")
		local startAt = string.find(server, "function OpeningService.start", 1, true) or 0
		local mendAt = string.find(server, "mendRow(route)", startAt, true)
		local runAt = string.find(server, "runs[player] = r", startAt, true)
		check(
			mendAt ~= nil and runAt ~= nil and mendAt < runAt,
			"start() mends the row before the run begins"
		)
		check(
			string.find(server, "if want and not r.row then\n\t\tmendRow(r.route)", 1, true) ~= nil,
			"and again as the hold begins"
		)
		check(string.find(server, "BuildingService.repair", 1, true) ~= nil, "through BuildingService.repair")
		local bs = src("src/server/Services/BuildingService.luau")
		local fn = string.match(bs, "function BuildingService%.repair%(.-\nend") or ""
		check(
			string.find(fn, "BuildingState.repair(book, id)", 1, true) ~= nil
				and string.find(fn, "setWrecked(id, false)", 1, true) ~= nil,
			"BuildingService.repair is the drones' path (state and the server's collision)"
		)
	end)
end
