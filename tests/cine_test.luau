-- prologue-cine (nate, 2026-11-20: "dont have the player run to the gold marker. whole prologue needs to be cutscene
-- with qtes until subway"): the Ceremony prologue from the run off the plaza to the subway fight as a directed
-- cinematic (Shared.PrologueCine, Shared.QtePlan, Fx.PrologueQte, OpeningService). Beat plan sims over many weekly
-- seeds: every beat is reachable by the authored motion (each move ends where the server's own check moves the
-- story on), no marker steps are left, every beat's worst case fits its stuck timer and the whole prologue fits its
-- timeout, the prompts cover JUMP, DODGE, GRAB, SHIELD or SMASH, a mash and a hold, every clip is a real HeroAnim
-- clip, and the built place carries the scripts. Called from tests/run.luau:
--   require("./cine_test")({ test = test, check = check, Config = Config, place = process.args[1] })

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local OpeningPlan = require("../src/shared/OpeningPlan")
	local PrologueCine = require("../src/shared/PrologueCine")
	local QtePlan = require("../src/shared/QtePlan")
	local HeroAnim = require("../src/shared/HeroAnim")
	local WorldMap = require("../src/shared/WorldMap")
	local Rng = require("../src/shared/Rng")
	local O = Config.Story.opening
	local Q = O.qte
	local function src(path: string): string
		return fs.readFile(path)
	end
	local function flat(a: { number }, b: { number }): number
		return math.sqrt((a[1] - b[1]) ^ 2 + (a[3] - b[3]) ^ 2)
	end

	-- the routes the sims run on: several weekly seeds, a few starts each, both sides
	local cases = {}
	for _, seed in { 202647, 11, 777, 31337, 2026 } do
		local w = WorldMap.build(Config, seed)
		for k = 1, 3 do
			local r = OpeningPlan.route(Config, w, Rng.new(seed * 7 + k))
			if r then
				table.insert(cases, { seed = seed, world = w, route = r, lane = OpeningPlan.lane(Config, k) })
			end
		end
	end

	-- the state the device gets (OpeningService.send): the route's points and the lane
	local function state(c: any, side: string): any
		local r = c.route
		return {
			start = r.start,
			spark = r.spark,
			kid = r.kid,
			roofs = r.roofs,
			roofHalf = r.roofHalf,
			runPath = r.runPath,
			entrance = r.entrance,
			lane = c.lane,
			side = side,
		}
	end

	local DIRECTED = { "run", "spark", "leap", "chase", "suit", "descend", "tunnel" }

	local function segsOf(o: any, step: string): { any }
		if step == "chase" then
			return PrologueCine.chase(Config, o)
		end
		return PrologueCine.beat(Config, o, step)
	end

	test(
		"prologue-cine: every beat to the subway fight is directed, with no marker and no free control",
		function()
			check(#cases >= 12, "routes to sim (" .. #cases .. ")")
			for _, step in OpeningPlan.STEPS do
				local before = OpeningPlan.CODE[step] < OpeningPlan.CODE.fight
				check(
					PrologueCine.frozen(step) == before,
					step .. ": the controls rest exactly until the fight"
				)
				if before then
					check(
						OpeningPlan.CUT[step] or PrologueCine.directed(Config, step),
						step .. " is a camera beat or a directed beat"
					)
					check(Config.Ui.prologue.goals[step] == nil, step .. ": no marker word")
					check(#(Config.Ui.prologue.verbs[step] or {}) == 0, step .. ": no HUD buttons")
				end
			end
			check(not PrologueCine.directed(Config, "fight"), "the fight is the player's")
			check(#Config.Ui.prologue.verbs.fight > 0, "and the fight's buttons come back")
			local hud = src("src/client/Ui/StoryHud.luau")
			check(
				string.find(hud, "if directed then nil else o.target", 1, true) ~= nil,
				"StoryHud draws no gold marker on a directed beat"
			)
			for _, step in DIRECTED do
				for _, side in { "hero", "villain" } do
					local segs = segsOf(state(cases[1], side), step)
					check(#segs > 0, step .. " has authored segments (" .. side .. ")")
					for _, s in segs do
						check(
							s.move == "run" or s.move == "arc" or s.move == "stand",
							step .. "." .. s.id .. ": a move"
						)
						check(s.time > 0, step .. "." .. s.id .. ": takes time")
					end
				end
			end
		end
	)

	test("prologue-cine: every authored move ends where the server moves the story on", function()
		local reach = O.spark.reach
		for _, c in cases do
			local tag = " (seed " .. c.seed .. ")"
			local o = state(c, "hero")
			local r = c.route
			-- the run: its path stays in the street, and it ends at the spark point
			for i = 2, #r.runPath do
				check(
					OpeningPlan.clearLine(Config, c.world, r.runPath[i - 1], r.runPath[i]),
					"the run's street is open" .. tag
				)
			end
			local run = PrologueCine.beat(Config, o, "run")
			local last = run[#run]
			local stop = PrologueCine.at(last, 1)
			check(
				OpeningPlan.at(Config, r.spark, stop[1], stop[2] + 3, stop[3], reach),
				"the run ends at the spark point" .. tag
			)
			-- each move starts where the one before ends (a roll's side-step is the only gap: 4 studs)
			for i = 2, #run do
				check(
					flat(PrologueCine.at(run[i - 1], 1), run[i].from) <= 4.5,
					"the run is one piece at " .. run[i].id .. tag
				)
			end
			-- the Spark: stood within the kid's reach (OpeningAct 1's check)
			local sp = PrologueCine.beat(Config, o, "spark")[1]
			check(flat(sp.from, r.kid) <= reach + 12, "the Spark fires in reach of the kid" .. tag)
			-- the leap ends on roof 2 (the server's 30-stud check)
			local leap = PrologueCine.beat(Config, o, "leap")
			local l = PrologueCine.at(leap[#leap], 1)
			check(
				OpeningPlan.at(Config, r.roofs[2], l[1], l[2] + 3, l[3], 30),
				"the leap lands on roof 2" .. tag
			)
			-- every chase hop ends on its roof; the ledge hang is not counted as there until the climb
			for hop = 3, #r.roofs do
				local segs = PrologueCine.beat(Config, o, "chase", hop)
				local e = PrologueCine.at(segs[#segs], 1)
				check(
					OpeningPlan.at(Config, r.roofs[hop], e[1], e[2] + 3, e[3], 30),
					"hop " .. hop .. " lands" .. tag
				)
				check(
					flat(segs[1].from, r.roofs[hop - 1]) < 1,
					"hop " .. hop .. " leaves from the roof before" .. tag
				)
				for _, s in segs do
					if s.id == "grab" then
						local h = s.from
						check(
							not OpeningPlan.at(Config, r.roofs[hop], h[1], h[2] + 3, h[3], 30),
							"the hang is below the roof" .. tag
						)
						check(h[2] < r.roofs[hop][2] - 4, "hanging off the ledge" .. tag)
					end
				end
			end
			-- the drop ends at the subway steps (24 studs, low)
			local d = PrologueCine.beat(Config, o, "descend")[1]
			local de = PrologueCine.at(d, 1)
			check(
				flat(de, r.entrance) <= 24 and de[2] + 3 <= r.entrance[2] + 30,
				"the drop reaches the subway steps" .. tag
			)
			-- the tunnel ends in the fight chamber, past the server's line
			local tun = PrologueCine.beat(Config, o, "tunnel")
			local te = PrologueCine.at(tun[#tun], 1)
			check(te[3] <= c.lane.z1 - 4, "the tunnel run ends in the chamber" .. tag)
			check(math.abs(te[1] - c.lane.x) < 1, "down the middle of the lane" .. tag)
			for _, s in tun do
				local p = PrologueCine.at(s, 1)
				check(
					math.abs(p[1] - c.lane.x) <= O.subway.width / 2 - 2,
					"inside the tunnel's walls: " .. s.id .. tag
				)
			end
		end
	end)

	test(
		"prologue-cine: timers: every beat's worst case fits its stuck timer, the prologue its timeout",
		function()
			local whole = 0
			for _, step in OpeningPlan.STEPS do
				if OpeningPlan.CUT[step] then
					whole += OpeningPlan.limit(Config, step)
				end
			end
			local worstAll = 0
			for _, c in cases do
				for _, side in { "hero", "villain" } do
					local o = state(c, side)
					local sum = 0
					for _, step in DIRECTED do
						local segs = segsOf(o, step)
						local worst = PrologueCine.worst(Config, segs)
						if step == "chase" then
							-- each hop's server count lands a little after the body (0.2 s ticks) and each hop shows its first
							-- prompt `lead` s after the landing
							worst += (#o.roofs - 2) * (Q.lead + 0.4)
						end
						check(
							worst < O.stuck[step],
							step .. " fits its timer: " .. math.floor(worst) .. " < " .. O.stuck[step]
						)
						check(
							PrologueCine.quickest(Config, segs) < worst,
							step .. ": the quick way is quicker"
						)
						if step == "spark" then
							-- the server fires the Spark by itself only after the prompt's worst case
							check(
								QtePlan.worst(Config, "press") + Q.lead < O.spark.auto,
								"the Spark's prompt has its time"
							)
							-- the choice holds the stuck clock; then `after` s to the leap
							worst += O.pick.wait + O.pick.after + O.pick.delay
						end
						sum += worst
					end
					worstAll = math.max(worstAll, sum)
				end
			end
			local after = O.stuck.fight + O.stuck.swarm
			check(
				whole + worstAll + after < O.timeout,
				"a player who misses every prompt still gets the fight and the end"
			)
			for step, t in O.stuck do
				check(OpeningPlan.limit(Config, step) == t, step .. "'s stuck timer is its limit")
			end
			check(not OpeningPlan.timed(Config, "suit"), "the suit waits for its HOLD (not the clock)")
		end
	)

	test("prologue-cine: the prompts cover every kind and action, with real clips", function()
		local o = state(cases[1], "hero")
		local ov = state(cases[1], "villain")
		local actions, kinds, words, fx = {}, {}, {}, {}
		local segs = {}
		for _, step in DIRECTED do
			for _, s in segsOf(o, step) do
				table.insert(segs, s)
			end
		end
		for _, s in PrologueCine.beat(Config, ov, "spark") do
			table.insert(segs, s)
		end
		local prompts = 0
		for _, s in segs do
			for _, clip in { s.clip, s.start, s.land, s.wait } do
				check(HeroAnim.CLIPS[clip] ~= nil, s.id .. ": " .. tostring(clip) .. " is a HeroAnim clip")
			end
			check(Q.shot[s.shot] ~= nil or s.shot == "side", s.id .. ": " .. s.shot .. " is a shot")
			if s.prompt then
				prompts += 1
				local p = s.prompt
				check(QtePlan.KEYS[p.action] == true, s.id .. ": " .. p.action .. " is a prompt key")
				check(p.kind == "press" or p.kind == "mash" or p.kind == "hold", s.id .. ": a prompt kind")
				check(type(p.word) == "string" and #p.word > 0, s.id .. ": a word")
				check(s.near ~= nil, s.id .. ": a miss has a near-miss look")
				actions[p.action], kinds[p.kind], words[p.word] = true, true, true
			end
			if s.fx then
				fx[s.fx] = true
			end
		end
		check(prompts >= 14, "plenty of prompts to the subway fight (" .. prompts .. ")")
		for _, a in { "Leap", "Block", "Basic", "Catch" } do
			check(actions[a], "a prompt on " .. a)
		end
		for _, k in { "press", "mash", "hold" } do
			check(kinds[k], "a " .. k .. " prompt")
		end
		local W = Q.words
		for _, w in { W.Leap, W.Block, W.Catch, W.shield, W.smash, W.mash, W.suit, W.drop } do
			check(words[w], "the prompt " .. w)
		end
		local fxSrc = src("src/client/Fx/PrologueFx.luau")
		for k in fx do
			check(
				string.find(fxSrc, 'kind == "' .. k .. '"', 1, true) ~= nil,
				"PrologueFx draws the " .. k .. " moment"
			)
		end
		-- the rules of a mash and a hold (the timed rules: qte.wait = false; first-30 makes prompts wait)
		local Config = { Story = { opening = { qte = setmetatable({ wait = false }, { __index = Q }) } } }
		local mash = { action = "Basic", word = W.mash, kind = "mash" }
		local n, done = 0, false
		for _ = 1, Q.mash.count do
			n, done = QtePlan.mashStep(Config, mash, n)
		end
		check(done and n == Q.mash.count, "a mash is done after its presses")
		check(Q.mash.count / Q.mash.window <= 2.5, "a mash a kid can do (presses a second)")
		local hold = { action = "Block", word = W.suit, kind = "hold" }
		local f, ok = QtePlan.holdStep(Config, hold, Q.hold.seconds * 0.5)
		check(math.abs(f - 0.5) < 1e-6 and not ok, "a hold half way")
		check(select(2, QtePlan.holdStep(Config, hold, Q.hold.seconds)), "a hold done")
		check(QtePlan.window(Config, 0, "hold") > Q.hold.seconds + 1, "the hold's window outlasts the hold")
		check(QtePlan.judge(Config, "Catch", "Catch", 0.2, 0) == "hit", "GRAB is a prompt key")
		check(QtePlan.worst(Config, "mash") > QtePlan.worst(Config, "press"), "a mash's worst case is longer")
		-- a miss retries and the 3rd does it: no dead end on any kind
		check(QtePlan.after(Config, "miss", Q.assist - 1).go == "assist", "the 3rd miss does it")
	end)

	test("prologue-cine: the directed camera frames the hero on every shot", function()
		for _, c in cases do
			for _, step in DIRECTED do
				for _, s in segsOf(state(c, "hero"), step) do
					for _, u in { 0, 0.5, 1 } do
						local p = PrologueCine.at(s, u)
						local cam, look = PrologueCine.camera(Config, s.shot, p, s, u)
						local d = math.sqrt((cam[1] - p[1]) ^ 2 + (cam[2] - p[2]) ^ 2 + (cam[3] - p[3]) ^ 2)
						check(
							d == d and d > 2 and d < 140,
							step .. "." .. s.id .. ": the camera is near (" .. math.floor(d) .. ")"
						)
						local ld = math.sqrt(
							(cam[1] - look[1]) ^ 2 + (cam[2] - look[2]) ^ 2 + (cam[3] - look[3]) ^ 2
						)
						check(ld > 1, step .. "." .. s.id .. ": it looks somewhere")
					end
				end
			end
		end
		-- the big leap is the slow-motion shot
		local leap = PrologueCine.beat(Config, state(cases[1], "hero"), "leap")
		check(leap[#leap].slow == true and leap[#leap].shot == "wide", "the leap: slow motion, the wide shot")
	end)

	test(
		"prologue-cine: the runtime path: the device runner, the server's beats and the built place",
		function()
			local run = src("src/client/Fx/PrologueQte.luau")
			for _, needle in
				{
					"InputController.freeze(on)",
					"MoveController.travel(at, seg.time, true)",
					"PrologueCine.beat(Config, o, step, o.hop)",
					'Net.send("OpeningAct", 7)',
					"StoryClient.spark()",
					"HeroAnimator.cineMode = seg.clip",
					"handoff()",
					"QteHud.Held:Connect",
					"InputController.alsoOf",
				}
			do
				check(string.find(run, needle, 1, true) ~= nil, "PrologueQte: " .. needle)
			end
			check(string.find(run, "arcTo", 1, true) == nil, "no free physics hops left")
			local server = src("src/server/Services/OpeningService.luau")
			check(
				string.find(server, 'act == 7 and r.step == "suit"', 1, true) ~= nil,
				"the server takes the suit's cue"
			)
			check(
				string.find(server, "MoveGuard.grant(hero, O.qte.grantRate * dt)", 1, true) ~= nil,
				"and grants the travel"
			)
			check(
				string.find(server, "OpeningPlan.at(Config, route.spark", 1, true) ~= nil,
				"the run is counted where the body is"
			)
			local remotes = require("../src/shared/Remotes")
			check(remotes.OpeningAct.schema[1].max == 9, "OpeningAct takes 1-9 (8 and 9: a prompt waits)")
			local fx = src("src/client/Fx/PrologueFx.luau")
			local slow = string.match(fx, "local function slowLeap.-\nend\n") or ""
			check(
				#slow > 0 and string.find(slow, "arcTo", 1, true) == nil,
				"the slow-mo leap only looks; the runner moves"
			)
			check(
				string.find(src("src/client/Controllers/HeroAnimator.luau"), "HeroAnimator.cineMode", 1, true)
					~= nil,
				"the clips"
			)
			-- the built place has every script on the path
			local game = roblox.deserializePlace(fs.readFile(T.place or "build/Capeline.rbxl"))
			local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
			check(
				shared and shared:FindFirstChild("PrologueCine") ~= nil,
				"Shared.PrologueCine is in the place"
			)
			check(shared and shared:FindFirstChild("QtePlan") ~= nil, "Shared.QtePlan is in the place")
			local sps = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
			local client = sps and sps:FindFirstChild("Client")
			local fxf = client and client:FindFirstChild("Fx")
			check(fxf and fxf:FindFirstChild("PrologueQte") ~= nil, "Client.Fx.PrologueQte is in the place")
			check(fxf and fxf:FindFirstChild("PrologueFx") ~= nil, "Client.Fx.PrologueFx is in the place")
			local ui = client and client:FindFirstChild("Ui")
			check(ui and ui:FindFirstChild("QteHud") ~= nil, "Client.Ui.QteHud is in the place")
			local init = client and client:FindFirstChild("init") or client
			check(init ~= nil, "the client script")
			check(
				string.find(src("src/client/init.client.luau"), "PrologueQte.init()", 1, true) ~= nil,
				"the runner starts"
			)
		end
	)
end
