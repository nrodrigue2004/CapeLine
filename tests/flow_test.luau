-- fix-flow (nate's playtest of gaps7, 2026-11-19 16:45Z): the first-time flow (exposition, creator, then the
-- prologue after PLAY), the rooftop chase's quick-time prompts, Skylance untouchable until the fight, the Body
-- step back (gender, build, height) and its save, and GO TO THE STAGE. Called from tests/run.luau:
--   require("./flow_test")({ test = test, check = check, Config = Config, place = process.args[1] })

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local FlowPlan = require("../src/shared/FlowPlan")
	local QtePlan = require("../src/shared/QtePlan")
	local OpeningPlan = require("../src/shared/OpeningPlan")
	local EnemySim = require("../src/shared/EnemySim")
	local LookCodec = require("../src/shared/LookCodec")
	local CreatorRules = require("../src/shared/CreatorRules")
	local ProfileSchema = require("../src/shared/ProfileSchema")
	local BodyShape = require("../src/shared/BodyShape")
	local BodyFit = require("../src/shared/BodyFit")
	local ContestRules = require("../src/shared/ContestRules")
	local Travel = require("../src/shared/Travel")
	local CinemaPlan = require("../src/shared/CinemaPlan")
	local function src(path: string): string
		return fs.readFile(path)
	end

	test("fix-flow: the first-time flow is exposition, creator, then the prologue after PLAY", function()
		-- a brand-new character on a new account starts on the exposition, then the creator
		check(FlowPlan.phase({ created = 0, opening = 0 }) == "intro", "a brand-new hero sees the exposition")
		check(FlowPlan.introFirst({ created = 0, opening = 0 }), "the exposition comes first")
		check(FlowPlan.next("intro", "introDone") == "creator", "then the creator")
		check(FlowPlan.next("intro", "created") == nil, "nothing saves a hero during the exposition")
		check(FlowPlan.next("intro", "started") == nil, "no prologue during the exposition")
		-- an account that saw it goes straight to the creator
		check(
			FlowPlan.phase({ created = 0, opening = 0, introSeen = true }) == "creator",
			"seen: the creator"
		)
		check(FlowPlan.next("creator", "started") == nil, "no prologue while the creator is open")
		check(FlowPlan.next("creator", "created") == "prologue", "PLAY starts the prologue")
		-- the prologue may never start while the creator is open or before PLAY saved the hero
		check(
			not FlowPlan.prologueOk({ created = 0, opening = 0 }, "creator", false),
			"not behind the creator"
		)
		check(not FlowPlan.prologueOk({ created = 0, opening = 0 }, nil, false), "not for an unmade hero")
		check(
			not FlowPlan.prologueOk({ created = 1, opening = 0 }, "creator", false),
			"never in the creator scene"
		)
		check(FlowPlan.prologueOk({ created = 1, opening = 0 }, nil, false), "a made hero's prologue starts")
		check(not FlowPlan.prologueOk({ created = 1, opening = 1 }, nil, false), "never twice by itself")
		check(
			not FlowPlan.prologueOk({ created = 1, opening = 0, running = true }, nil, false),
			"not twice at once"
		)
		check(
			FlowPlan.prologueOk({ created = 1, opening = 1 }, nil, true),
			"a Journal replay out in the city"
		)
		check(
			not FlowPlan.prologueOk({ created = 1, opening = 1 }, "mission", true),
			"no replay from a mission"
		)
		check(FlowPlan.next("prologue", "finished") == "play", "the prologue ends in the game")
		-- returning players skip both
		check(
			FlowPlan.phase({ created = 1, opening = 1 }) == "play",
			"a returning hero goes straight to play"
		)
		check(FlowPlan.next("play", "replay") == "intro", "the Journal replay plays the exposition first")
		check(
			FlowPlan.phase({ created = 0, opening = 1 }) == "play",
			"a pre-creator hero is out of the story"
		)
		check(
			FlowPlan.phase({ created = 1, opening = 0, running = true, held = true }) == "menu",
			"a held ceremony is the main menu's pick"
		)
		check(FlowPlan.next("menu", "playPrologue") == "prologue", "PLAY THE PROLOGUE")
		check(FlowPlan.next("menu", "createFirst") == "play", "CREATE FIRST")
		check(not FlowPlan.creatorOk({ created = 0, opening = 0 }, false), "no creator over the exposition")
		check(FlowPlan.creatorOk({ created = 0, opening = 0 }, true), "the creator once it is over")

		-- the exposition: a real comic page and a named scene a device may mark seen, skippable at once
		local I = Config.Story.opening.intro
		local sc = Config.Cinema.scenes[I.scene]
		check(sc ~= nil and sc.comic == I.page, "the intro scene plays the intro page")
		check(
			CinemaPlan.namedBit(Config, sc.bit) and CinemaPlan.clientBit(Config, sc.bit),
			"its seen bit is valid"
		)
		local used = {}
		for id, s in Config.Cinema.scenes do
			check(used[s.bit] == nil, "scene bits are unique: " .. id)
			used[s.bit] = true
		end
		local page = Config.Cinema.comic.pages[I.page]
		check(page ~= nil and #page.panels >= 3 and #page.panels <= 4, "a few beats")
		for i, p in page.panels do
			check(type(p.caption) == "string" and #p.caption <= 100, "panel " .. i .. " has a short caption")
			check(p.at < sc.seconds - 3, "panel " .. i .. " shows with time to read it")
		end
		check(I.skipAfter < 3 and I.timeout >= sc.seconds + 10, "skippable at once; the server waits past it")

		-- the server's wiring (the order Studio runs)
		local creator = src("src/server/Services/CreatorService.luau")
		local opening = src("src/server/Services/OpeningService.luau")
		local cf = string.match(creator, "function CreatorService.createFirst.-\nend\n") or ""
		check(string.find(cf, "FlowPlan.introFirst", 1, true) ~= nil, "createFirst asks FlowPlan")
		local introAt = string.find(cf, '"OpeningIntro"', 1, true) or math.huge
		local openAt = string.find(cf, "openCreate(player)\nend", 1, true) or 0
		check(introAt < openAt, "the exposition is sent before the creator opens")
		check(
			string.find(creator, "OpeningService.IntroDone:Connect", 1, true) ~= nil,
			"its end opens the creator"
		)
		local st = string.match(opening, "function OpeningService.start.-\nend\n") or ""
		check(string.find(st, 'hero.scene == "creator"', 1, true) ~= nil, "start refuses behind the creator")
		check(string.find(st, "FlowPlan.prologueOk", 1, true) ~= nil, "start asks FlowPlan")
		local onCreate = string.match(creator, "local function onCreate.-\nend\n") or ""
		local scene = string.find(onCreate, "hero.scene = nil", 1, true) or math.huge
		local start = string.find(onCreate, "task.defer(OpeningService.start", 1, true) or 0
		check(scene < start, "PLAY leaves the creator scene before the prologue starts")
		local dev = src("src/server/Services/DevService.luau")
		check(
			string.find(
				dev,
				"OpeningService.stop(player)\n\t\tlocal profile = DataService.resetProfile",
				1,
				true
			) ~= nil,
			"DEV Wipe stops a running prologue first"
		)
		-- the device: a held ceremony is not a playing scene; the creator's last button is PLAY
		local sc2 = src("src/client/Controllers/StoryClient.luau")
		check(
			string.find(sc2, "if StoryClient.opening.hold then\n\t\treturn nil", 1, true) ~= nil,
			"held: no scene"
		)
		local cs = src("src/client/Ui/CreatorScreen.luau")
		check(string.find(cs, '(if mode == "create" then "PLAY" else "DONE")', 1, true) ~= nil, "PLAY")
		local remotes = require("../src/shared/Remotes")
		check(remotes.OpeningIntro and remotes.OpeningIntro.dir == "S2C", "OpeningIntro is a remote")
	end)

	test("fix-flow: the rooftop chase's quick-time prompts: timing, results and no dead ends", function()
		local Q = Config.Story.opening.qte
		local O = Config.Story.opening
		for step in Q.beats do
			check(
				QtePlan.on(Config, step) and QtePlan.camera(Config, step),
				step .. " is a prompt beat on camera"
			)
			check(OpeningPlan.HOPS[step] == true, step .. " is a guided hop beat")
		end
		check(
			not QtePlan.on(Config, "fight") and not QtePlan.camera(Config, "fight"),
			"the fight is a normal fight"
		)
		check(not QtePlan.on(Config, "tunnel") and not QtePlan.on(Config, nil), "no prompts off the roofs")
		-- the prompts
		check(#QtePlan.prompts(Config, "leap", 3) == 1, "the leap: one JUMP")
		check(QtePlan.prompts(Config, "leap", 3)[1].action == "Leap", "JUMP is the Leap key")
		local dodges = 0
		for hop = 3, O.roofs.count do
			local list = QtePlan.prompts(Config, "chase", hop)
			check(list[#list].action == "Leap", "every chase hop ends in a JUMP")
			if Q.dodge[hop] then
				dodges += 1
				check(#list == 2 and list[1].action == "Block", "a DODGE first on roof " .. hop)
			end
		end
		check(dodges >= 1, "Skylance's spears are dodged at least once")
		check(QtePlan.prompts(Config, "descend", 0)[1].word == Q.words.drop, "the drop to the subway")
		-- timing
		local w = QtePlan.window(Config, 0)
		check(
			QtePlan.judge(Config, "Leap", "Leap", -0.1, 0) == nil,
			"a press before the prompt shows is ignored"
		)
		check(QtePlan.judge(Config, "Leap", "Leap", 0.05, 0) == "hit", "a quick press hits")
		check(QtePlan.judge(Config, "Leap", "Leap", w - 0.01, 0) == "hit", "a press at the window's end hits")
		check(QtePlan.judge(Config, "Leap", "Leap", w + 0.01, 0) == "miss", "too late misses")
		check(QtePlan.judge(Config, "Leap", "Block", 0.3, 0) == "miss", "the wrong prompt key misses")
		check(QtePlan.judge(Config, "Leap", "Map", 0.3, 0) == nil, "other keys are ignored")
		check(QtePlan.window(Config, 1) > w, "the window is longer after a miss")
		check(
			QtePlan.judge(Config, "Leap", "Leap", w + 0.01, 1) == "hit",
			"so a slower press hits on the retry"
		)
		check(not QtePlan.expired(Config, w - 0.01, 0) and QtePlan.expired(Config, w + 0.01, 0), "it expires")
		check(w >= 1.5, "a generous window for kids")
		-- results: a hit goes on, a miss retries, the assist-th miss does it for you
		local a = QtePlan.after(Config, "hit", 0)
		check(a.go == "next" and a.misses == 0, "a hit moves on")
		local m = 0
		local gone = false
		for i = 1, Q.assist do
			local r = QtePlan.after(Config, "miss", m)
			if i < Q.assist then
				check(r.go == "retry" and r.misses == i and r.wait > 0, "miss " .. i .. " retries")
			else
				check(r.go == "assist", "miss " .. i .. " does the move by itself")
				gone = true
			end
			m = r.misses
		end
		check(gone, "no dead end")
		-- worst case: every prompt missed until the assist; the beat still ends inside its stuck timer
		local function worst(n: number): number
			local per = Q.lead
			for k = 0, Q.assist - 1 do
				per += QtePlan.window(Config, k) + (if k < Q.assist - 1 then Q.retry else 0)
			end
			return n * per
		end
		check(worst(1) + 2.2 < O.stuck.leap, "the leap's worst case fits its timer")
		local chasePrompts = 0
		for hop = 3, O.roofs.count do
			chasePrompts += #QtePlan.prompts(Config, "chase", hop)
		end
		check(worst(chasePrompts) + (O.roofs.count - 2) * 2.2 < O.stuck.chase, "the chase's worst case fits")
		check(worst(1) + 2.2 < O.stuck.descend, "the drop's worst case fits")
		-- the camera sits off to the side of the hop, above, looking ahead
		local c, l = QtePlan.camera3(Config, { 0, 100, 0 }, { 0, 100, -50 })
		check(
			math.abs(c[1]) > 10 and c[2] > 100 and l[3] < 0,
			"the chase camera frames the hop from the side"
		)
		-- the device runner and HUD: the HUD's verbs rest on those beats (the prompt is the button)
		for step in Q.beats do
			check(#Config.Ui.prologue.verbs[step] == 0, step .. ": no HUD buttons over the prompts")
		end
		local run = src("src/client/Fx/PrologueQte.luau")
		check(string.find(run, "InputController.freeze(on)", 1, true) ~= nil, "the hero's controls rest")
		check(string.find(run, "MoveController.arcTo", 1, true) ~= nil, "JUMP is the guided arc")
		check(string.find(run, "MoveController.Leaped:Fire", 1, true) ~= nil, "the slow-mo leap still plays")
		check(
			string.find(src("src/client/init.client.luau"), "PrologueQte.init()", 1, true) ~= nil,
			"it runs"
		)
	end)

	test("fix-flow: Skylance cannot be touched until the scripted fight", function()
		local sim = EnemySim.new(Config, {
			heightAt = function()
				return 0
			end,
			random = function()
				return 0.5
			end,
		})
		local e = EnemySim.spawn(sim, "Skylance", 0, 30, 0, 3) :: any
		check(e ~= nil, "Skylance spawns")
		e.untouchable = true
		local hp = e.health
		local killed, _, dealt = EnemySim.damage(sim, e.id, 1e6, 1, 5, 5)
		check(not killed and dealt == 0 and e.health == hp, "no damage while untouchable")
		check(not EnemySim.knock(sim, e.id, 1, 0, 30), "no knockback")
		check(EnemySim.applyStatus(sim, e.id, "stun", 2) == 0, "no stun")
		EnemySim.hold(sim, e.id, 1)
		check(e.held == nil, "no grab")
		for _, c in EnemySim.candidates(sim) do
			check(c.id ~= e.id, "never a hit candidate")
		end
		e.untouchable = nil -- the fight's Skylance is a normal robot
		local _, _, dealt2 = EnemySim.damage(sim, e.id, 10, 1, 5, 5)
		check(dealt2 > 0, "a normal robot once the fight starts")
		local opening = src("src/server/Services/OpeningService.luau")
		local leap = string.match(opening, 'elseif step == "leap" then.-elseif step == "chase"') or ""
		check(
			string.find(leap, "untouchable = true", 1, true) ~= nil,
			"the rooftop Skylance is spawned untouchable"
		)
		local fight = string.match(opening, 'elseif step == "fight" then.-elseif step == "swarm"') or ""
		check(string.find(fight, "clearEnemies(r)", 1, true) ~= nil, "the fight spawns a new Skylance")
		check(string.find(fight, "untouchable", 1, true) == nil, "who can be fought")
	end)

	test("fix-flow: the Body step is back: gender, build and height, saved and worn", function()
		local C = Config.Creator
		check(C.bodyStep == true, "the Body step is on")
		check(
			string.find(src("src/client/Ui/CreatorScreen.luau"), "if AVATAR or not C.bodyStep then", 1, true)
				~= nil,
			"the creator shows the step when on"
		)
		-- the save: every gender, build and height round-trips through the look record and validates
		local profile = ProfileSchema.default()
		for g = 1, #C.body.genders do
			for b = 1, #C.body.builds do
				for h = 1, #C.body.heights do
					local look = CreatorRules.defaultLook(Config)
					look.gender, look.build, look.height = g, b, h
					local back = LookCodec.decode(LookCodec.encode(look)) :: any
					check(
						back.gender == g and back.build == b and back.height == h,
						string.format("saved %d/%d/%d", g, b, h)
					)
					local words = LookCodec.toWords(LookCodec.encode(look))
					local read = LookCodec.read(words) :: any
					check(read and read.build == b, "the saved words read back")
					local ok, why = CreatorRules.validate(Config, profile, back, 1)
					check(ok, "valid body: " .. tostring(why))
				end
			end
		end
		local bad = CreatorRules.defaultLook(Config)
		bad.build = 9
		check(not CreatorRules.validate(Config, profile, bad, 1), "an unknown build is refused")
		-- the 8 body sets: their torsos are in the built place and fill Roblox's own torso boxes
		local game = roblox.deserializePlace(fs.readFile(T.place or "build/Capeline.rbxl"))
		local bodies = game:GetService("ReplicatedStorage"):FindFirstChild("Art")
		bodies = bodies and bodies:FindFirstChild("Bodies")
		check(bodies ~= nil, "Art.Bodies is in the build")
		local R = Config.RobloxRig.parts
		for _, g in { 1, 2 } do
			for b = 1, 4 do
				local key = BodyShape.setKey(Config, { gender = g, build = b, height = 3 })
				for _, part in { "UpperTorso", "LowerTorso" } do
					local m = bodies and bodies:FindFirstChild(key .. "_" .. part, true)
					if m then
						check(
							string.match(m.MeshId, "^rbxassetid://%d+$") ~= nil,
							key .. " " .. part .. " uploaded"
						)
						local s, r = m.Size, R[part].size
						check(
							math.abs(s.X - r[1]) < 0.25
								and math.abs(s.Y - r[2]) < 0.1
								and math.abs(s.Z - r[3]) < 0.1,
							key .. " " .. part .. " fills Roblox's torso box"
						)
					end
				end
			end
		end
		check(
			bodies and bodies:FindFirstChild("FemaleMedium_UpperTorso", true) ~= nil,
			"the female torso is there"
		)
		-- BodyFit tells the rig from the first size, so a Titan's thick upper arm keeps Roblox's fit
		local f = BodyShape.factors(Config, { gender = 1, build = 4, height = 1 })
		local base = R.LeftUpperArm.size
		local size = { base[1] * f.LeftUpperArm[1], base[2] * f.LeftUpperArm[2], base[3] * f.LeftUpperArm[3] }
		local shift = BodyFit.frame(Config, "LeftUpperArm", size, base)
		local wrong = BodyFit.frame(Config, "LeftUpperArm", size)
		check(math.abs(shift[2]) > 0.05, "a Titan's arm piece keeps Roblox's shift")
		check(math.abs(wrong[2]) < 1e-6, "(without the first size it was read as the other rig)")
		-- the device wears it: the set's torsos on Roblox's body, then the shape
		local kit = src("src/shared/LookKit.luau")
		check(string.find(kit, 'local SET_TORSO = { "UpperTorso", "LowerTorso" }', 1, true) ~= nil, "torsos")
		check(
			string.find(kit, "if not avatar and C.bodyStep then", 1, true) ~= nil,
			"build() shapes the body"
		)
	end)

	test("fix-flow: GO TO THE STAGE flies you there, then ENTER", function()
		local K = Config.Contest
		check(ContestRules.goPlan(K, "call", {}, 7, 10) == "enter", "near: ENTER")
		check(ContestRules.goPlan(K, "call", {}, 7, K.enterRange + 500) == "travel", "away: fly there")
		local full = {}
		for i = 1, K.maxEntries do
			full[i] = 100 + i
		end
		local how, why = ContestRules.goPlan(K, "call", full, 7, 900)
		check(how == false and why == "full", "a full stage says so")
		check(select(2, ContestRules.goPlan(K, "show", {}, 7, 900)) == "closed", "only during the call")
		check(select(2, ContestRules.goPlan(K, "call", { 7 }, 7, 900)) == "in", "already on")
		local s = { beacons = 0, inCombat = false, traveling = false, readyAt = 0, now = 10, scene = nil }
		check(Travel.canGo(s), "the flight's own rules")
		s.inCombat = true
		check(select(2, Travel.canGo(s)) == "combat", "not mid-fight")
		local hud = src("src/client/Ui/ContestHud.luau")
		check(
			string.find(hud, 'Net.send("ContestGo")', 1, true) ~= nil,
			"the button asks the server when away"
		)
		local svc = src("src/server/Services/ContestService.luau")
		check(string.find(svc, "BeaconService.travelTo", 1, true) ~= nil, "the server fast travels the hero")
		check(string.find(svc, "if landed then%s+enter%(player%)") ~= nil, "and steps them on")
	end)
end
