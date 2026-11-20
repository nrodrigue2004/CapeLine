-- The mobility upgrade rework (nate, 2026-11-20): ranks 3 and 5 of each pick are a choice of two moves (Config.Move
-- moves and each rank row's `choice`; Shared.MoveRanks; save v16 mobMoves). Called from tests/run.luau;
-- ONLY="Mobility moves" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local MoveRanks = require("../src/shared/MoveRanks")
	local ProfileSchema = require("../src/shared/ProfileSchema")
	local M = Config.Move

	test(
		"Mobility moves: ranks 3 and 5 offer two moves each, 20 in all, every number inside the caps",
		function()
			check(#MoveRanks.check(M) == 0, "MoveRanks.check: " .. table.concat(MoveRanks.check(M), "; "))
			local seen = {}
			for _, pick in M.mobilityOrder do
				for _, r in M.choices do
					local opts = MoveRanks.options(M, pick, r)
					check(opts ~= nil and #opts == 2, pick .. " rank " .. r .. " offers two")
					for _, id in opts or {} do
						check(not seen[id], id .. " belongs to one rank")
						seen[id] = true
					end
				end
				for _, r in { 1, 2, 4 } do
					check(
						MoveRanks.options(M, pick, r) == nil,
						pick .. " rank " .. r .. " stays a number bump"
					)
				end
			end
			local n = 0
			for id in M.moves do
				n += 1
				check(seen[id], id .. " is offered somewhere")
			end
			check(n == 20, "20 moves (" .. n .. ")")
			check(MoveRanks.slots(M) == 10, "10 saved picks")
		end
	)

	test("Mobility moves: picking, the first pick anywhere, swaps at a safehouse, kept per pick", function()
		local ranks = MoveRanks.withRank(M, nil, "flight", 3)
		local moves = MoveRanks.withChoice(M, nil, "flight", 3, 0)
		check(MoveRanks.moveOf(M, ranks, moves, "flight", 3) == nil, "nothing until picked")
		local ok, why = MoveRanks.canChoose(M, ranks, moves, "flight", 5, 1, true)
		check(not ok and why == "rank", "rank 5 is not trained")
		ok = MoveRanks.canChoose(M, ranks, moves, "flight", 3, 2, false)
		check(ok, "the first pick needs no safehouse")
		moves = MoveRanks.withChoice(M, moves, "flight", 3, 2)
		check(MoveRanks.moveOf(M, ranks, moves, "flight", 3) == "slipstream", "Slipstream picked")
		ok, why = MoveRanks.canChoose(M, ranks, moves, "flight", 3, 1, false)
		check(not ok and why == "safehouse", "a swap away from a safehouse is refused")
		ok = MoveRanks.canChoose(M, ranks, moves, "flight", 3, 1, true)
		check(ok, "a swap at a safehouse is fine")
		ok, why = MoveRanks.canChoose(M, ranks, moves, "flight", 3, 2, true)
		check(not ok and why == "same", "the same pick again")
		ok, why = MoveRanks.canChoose(M, ranks, moves, "flight", 3, 3, true)
		check(not ok and why == "option", "only options 1 and 2")
		check(MoveRanks.active(M, ranks, moves, "flight").slipstream == true, "active on its pick")
		check(next(MoveRanks.active(M, ranks, moves, "speed")) == nil, "not on another pick")
		-- the speed pick's slots are its own
		local both = MoveRanks.withChoice(M, moves, "speed", 5, 1)
		check(
			MoveRanks.picked(M, both, "flight", 3) == 2 and MoveRanks.picked(M, both, "speed", 5) == 1,
			"kept per pick"
		)
		-- untrained back down (a stale save): the pick does nothing
		check(
			MoveRanks.moveOf(M, { 2, 0, 0, 0, 0 }, moves, "flight", 3) == nil,
			"a pick past the trained rank is off"
		)
	end)

	test("Mobility moves: save v16 keeps a pick per hero and cleans bad ones", function()
		check(ProfileSchema.VERSION >= 16, "save v16")
		local fresh = ProfileSchema.load(nil)
		local c = fresh.characters[1]
		check(type(c.mobMoves) == "table" and #c.mobMoves == 10, "ten zeros on a new hero")
		local old = ProfileSchema.load({ version = 15, characters = { { mobRanks = { 3, 0, 0, 0, 0 } } } })
		check(
			#old.characters[1].mobMoves == 10 and old.characters[1].mobMoves[1] == 0,
			"a v15 save starts unpicked"
		)
		local bad = ProfileSchema.load({
			version = 16,
			characters = { { mobMoves = { 1, 9, -1, "x", 2, 0, 0, 0, 0, 0, 7 } } },
		})
		local mm = bad.characters[1].mobMoves
		check(
			#mm == 10 and mm[1] == 1 and mm[2] == 0 and mm[3] == 0 and mm[4] == 0 and mm[5] == 2,
			"repaired"
		)
	end)

	test("Mobility moves: the server path and the LOADOUT cards", function()
		local remotes = fs.readFile("src/shared/Remotes.luau")
		check(string.find(remotes, "MoveChoose = {", 1, true) ~= nil, "MoveChoose remote")
		local ab = fs.readFile("src/server/Services/AbilityService.luau")
		check(string.find(ab, 'Net.on("MoveChoose"', 1, true) ~= nil, "handled")
		check(string.find(ab, "SafehouseService.canSwap(hero)", 1, true) ~= nil, "swaps at a safehouse")
		local hs = fs.readFile("src/server/Services/HeroService.luau")
		check(string.find(hs, "function HeroService.hasMove(", 1, true) ~= nil, "HeroService.hasMove")
		check(string.find(hs, "char.mobMoves = table.clone(hero.mobMoves)", 1, true) ~= nil, "saved")
		local ui = fs.readFile("src/client/Ui/LoadoutScreen.luau")
		check(string.find(ui, 'Net.send("MoveChoose", rank, k)', 1, true) ~= nil, "the PICK button")
		check(string.find(ui, 'Kit.icon("mobmove", id', 1, true) ~= nil, "with the move's icon")
	end)
	test("Mobility moves: the MOBILITY tab shows each choice rank's two moves as cards with icons", function()
		if not T.placePath then
			return
		end
		local roblox = require("@lune/roblox")
		local UiSim = require("./uisim")
		local sim = UiSim.new(
			UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		)
		sim:run("InputController", sim:require("Client.Controllers.InputController").init)
		local State = sim:require("Client.State")
		local Loadout = sim:require("Client.Ui.LoadoutScreen")
		sim:run("LoadoutScreen", Loadout.init)
		State.hero.mobility = "flight"
		State.hero.mobRanks = { 3, 0, 0, 0, 0 }
		State.hero.mobMoves = { 2, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
		State.hero.level = 25
		local sent = {}
		local remote = sim.service("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("MoveChoose")
		remote._props.FireServer = function(_, ...)
			table.insert(sent, { ... })
		end
		sim:run("open", Loadout.open)
		local panel = sim.playerGui:FindFirstChild("Loadout")
		local tab = panel and panel:FindFirstChild("MobilityTab", true)
		check(tab ~= nil, "the MOBILITY tab")
		if not tab then
			return
		end
		sim:run("tab", function()
			sim:tap(tab)
		end)
		local function card(name: string)
			return panel:FindFirstChild(name, true)
		end
		local a, b = card("Move3_1"), card("Move3_2")
		check(a ~= nil and b ~= nil, "rank 3's two move cards")
		check(card("Move5_1") ~= nil and card("Move5_2") ~= nil, "rank 5's two move cards")
		if a and b then
			check(a:FindFirstChild("MoveIcon") ~= nil, "with the move's icon")
			check(string.find(a:FindFirstChild("MoveName").Text, "SONIC BOOM DIVE", 1, true) ~= nil, "named")
			check(a:FindFirstChild("MoveText").Text == M.moves.sonicDive.text, "and what it does")
			-- Slipstream is picked; tapping Sonic Boom Dive asks the server for option 1
			local buttons = {}
			for _, d in a:GetChildren() do
				if d.ClassName == "TextButton" then
					table.insert(buttons, d)
				end
			end
			check(#buttons == 1 and buttons[1].Text == "SWAP", "the other move offers a swap")
			sim:run("pick", function()
				sim:tap(buttons[1])
			end)
			check(#sent == 1 and sent[1][1] == 3 and sent[1][2] == 1, "MoveChoose 3, 1 sent")
		end
		local five = card("Move5_1")
		if five then
			for _, d in five:GetChildren() do
				if d.ClassName == "TextButton" then
					check(d.Text == "RANK 5 FIRST", "rank 5 waits for its training")
				end
			end
		end
		check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
	end)
	-- the 20 moves (MoveActs, MoveActService, MoveActClient, MoveController's hooks)
	local MoveActs = require("../src/shared/MoveActs")
	local MoveMath = require("../src/shared/MoveMath")
	local MoveCheck = require("../src/shared/MoveCheck")
	local MV = M.moves
	local function has(path: string, needle: string): boolean
		return string.find(fs.readFile(path), needle, 1, true) ~= nil
	end
	-- a straight run at `speed` for `time` s through MoveCheck at 10 Hz, with a burst of `burst` studs in `burstTime`
	-- s at the start (granted `grant` studs first); returns the pull-backs
	local function run(
		cap: number,
		speed: number,
		time: number,
		burst: number?,
		burstTime: number?,
		grant: number?
	): number
		local st = MoveCheck.new(0, 10, 0, 0)
		if grant then
			MoveCheck.grant(st, grant, 0)
		end
		local fails = 0
		local x, t = 0, 0
		local bt = burstTime or 0
		while t < time + bt - 1e-6 do
			t += 0.1
			if t <= bt + 1e-6 and burst then
				x = burst * math.min(1, t / bt)
			else
				x += speed * 0.1
			end
			local ok, _, wait = MoveCheck.sample(st, x, 10, 0, t, cap, M, Config.Safety)
			if not ok and not wait then
				fails += 1
			end
		end
		return fails
	end
	local function capOf(pick: string, opts: any?): number
		local cfg = MoveRanks.config(M, pick, 5)
		return MoveMath.guardCap(cfg, { [pick] = true, flight = pick == "flight" or nil }, false, opts or {})
	end

	test("Mobility moves: the wire numbers every move once, in pick, rank and option order", function()
		local ids = MoveActs.ids(M)
		check(#ids == 20, "20 ids")
		for i, id in ids do
			check(MoveActs.num(M, id) == i and MoveActs.idOf(M, i) == id, id .. " round trips")
			check(MV[id] ~= nil, id .. " has its numbers")
		end
		check(ids[1] == "sonicDive" and ids[20] == "skyHook", "flight first, swing last")
		check(
			MoveActs.pickOf(M, "blink") == "speed" and MoveActs.pickOf(M, "yank") == "swing",
			"each knows its pick"
		)
		local R = require("../src/shared/Remotes")
		check(
			R.MoveAct and R.MoveAct.dir == "C2S" and R.MoveAct.schema[1].max >= 20,
			"MoveAct carries every num"
		)
		check((R.MoveAct.rate or 99) <= 10, "rate-limited")
		check(R.MoveActFx and R.MoveActFx.dir == "S2C", "MoveActFx for other devices")
		local book = {}
		check(MoveActs.ready(book, "blink", 0), "ready at first")
		MoveActs.start(book, "blink", 0, 6, 0.85)
		check(not MoveActs.ready(book, "blink", 5), "the server's cooldown holds")
		check(MoveActs.ready(book, "blink", 5.2), "with its lag leeway")
		check(not MoveActs.idOf(M, 21), "nothing past 20")
	end)

	test("Mobility moves: Flight's Sonic Boom Dive, Slipstream, Phase and Blazing Ram", function()
		local d = MV.sonicDive
		check(MoveActs.dive(d, 60, 90), "a high fast landing booms")
		check(
			not MoveActs.dive(d, 20, 90) and not MoveActs.dive(d, 60, 40),
			"a hop or a slow landing does not"
		)
		local s = MV.slipstream
		-- the leader at the origin flying +Z: an ally 20 behind and 5 off the line is in the wake
		check(MoveActs.inWake(s, 0, 50, 0, 0, 0, 1, 5, 50, -20), "behind and close: in the wake")
		check(not MoveActs.inWake(s, 0, 50, 0, 0, 0, 1, 0, 50, 20), "ahead: not")
		check(not MoveActs.inWake(s, 0, 50, 0, 0, 0, 1, 30, 50, -20), "far off the line: not")
		check(not MoveActs.inWake(s, 0, 50, 0, 0, 0, 1, 0, 50, -(s.length + 5)), "too far back: not")
		local cfg = MoveRanks.config(M, "flight", 5)
		local wake = MoveActs.wakeCruise(s, cfg.flight.cruise, cfg.flight.boost)
		check(
			wake > cfg.flight.cruise and wake <= cfg.flight.boost,
			"the wake's cruise: faster, never past boost"
		)
		-- an ally cruising in the wake passes MoveGuard with the slip buff, and is pulled back without it
		local base = MoveMath.guardCap(M, { flight = true }, false, {})
		local slip = MoveMath.guardCap(M, { flight = true }, false, { slip = s.ally })
		local allyWake = MoveActs.wakeCruise(s, M.flight.cruise, M.flight.boost)
		check(
			run(slip, allyWake, 3) == 0,
			string.format("a wake cruise at %.0f passes with the buff", allyWake)
		)
		check(
			slip >= allyWake and slip >= base,
			"the slip buff's cap covers the wake (never under the plain cap)"
		)
		local ph = MV.phase
		check(MoveActs.phaseOn(ph, -math.huge, 0, 50), "Phase is ready at first")
		check(not MoveActs.phaseOn(ph, 0, ph.cooldown - 0.1, 50), "and waits its cooldown after one ends")
		check(not MoveActs.phaseOn(ph, -math.huge, 0, 0), "and needs stamina")
		check(MoveActs.phaseHolds(ph, 0, ph.time - 0.1, false), "it holds its time")
		check(not MoveActs.phaseHolds(ph, 0, ph.time + 0.1, false), "then ends in the open")
		check(MoveActs.phaseHolds(ph, 0, ph.time + 0.1, true), "but holds on while still inside")
		check(not MoveActs.phaseHolds(ph, 0, ph.time * 2 + 0.1, true), "never past twice its time")
		-- a Phase is a boost: inside the boost cap
		local boost = MoveMath.guardCap(cfg, { flight = true }, true, {})
		check(run(boost, cfg.flight.boost, 2) == 0, "a boost through a building passes the speed check")
		local b = MV.blazeRam
		check(
			MoveActs.blazeDamage(b, 1000) > 1000 and b.throw > 1 and b.stamina > 0,
			"Blazing Ram: more, further, dearer"
		)
		check(
			has("src/server/Services/ImpactService.luau", "ImpactService.ramHook(hero, at, dir.Unit)"),
			"its ram hook"
		)
		check(
			has("src/client/Fx/ImpactFx.luau", 'MoveController.has("blazeRam")'),
			"the device blows the wall out too"
		)
	end)

	test("Mobility moves: Super-speed's Tornado Run, Afterimage, Sonic Wake and Blink", function()
		local m = MV.tornadoRun
		-- a run circling a point at 60 studs/s, radius 16, sampled at 30 Hz for 3.5 s
		local samples = {}
		local w = 60 / 16
		for i = 0, 105 do
			local t = i / 30
			table.insert(
				samples,
				{ x = 100 + math.cos(w * t) * 16, z = 50 + math.sin(w * t) * 16, t = t, s = 60 }
			)
		end
		local ok, cx, cz = MoveActs.circled(m, samples, 3.5)
		check(ok, "a tight fast circle raises the whirlwind")
		check(math.abs(cx - 100) < 3 and math.abs(cz - 50) < 3, "at its middle")
		local line = {}
		for i = 0, 105 do
			table.insert(line, { x = i * 2, z = 0, t = i / 30, s = 60 })
		end
		check(not MoveActs.circled(m, line, 3.5), "a straight run does not")
		local slow = table.clone(samples)
		slow[50] = { x = slow[50].x, z = slow[50].z, t = slow[50].t, s = 20 }
		check(not MoveActs.circled(m, slow, 3.5), "nor a circle that slowed down")
		local a = MV.afterimage
		check(MoveActs.stopped(a, 90, 0.3, 5), "a hard stop from top speed leaves the decoy")
		check(not MoveActs.stopped(a, 40, 0.3, 5), "a stop from a jog does not")
		check(not MoveActs.stopped(a, 90, 2, 5), "nor a slow stop")
		local cfg = MoveRanks.config(M, "speed", 5)
		local wake = MV.sonicWake
		check(MoveActs.wakeSpeed(wake, cfg.mobility.speed.sprint), "Sonic Wake goes off at the top sprint")
		check(not MoveActs.wakeSpeed(wake, 60), "not at a run")
		local bl = MV.blink
		check(MoveActs.blinkReach(bl, nil) == bl.range, "Blink goes its full range in the open")
		check(MoveActs.blinkReach(bl, 12) == 10, "and stops short of a wall")
		-- the blink is faster than any cap: a granted distance, never a pull-back
		local cap = capOf("speed")
		check(bl.range / bl.time > cap, "a blink is faster than the Super-speed cap")

		check(run(cap, 60, 1, bl.range, bl.time, bl.range + 6) == 0, "granted (MoveActService), it passes")
		check(
			has("src/server/Services/MoveActService.luau", "MoveGuard.grant(hero, dir.Magnitude + 6)"),
			"the grant"
		)
	end)

	test("Mobility moves: Leaping's Impact Landing, Wall Crusher, Meteor Strike and Moon Jump", function()
		local m = MV.impactLanding
		check(MoveActs.impact(m, m.minFall - 1) == nil, "a small drop does nothing")
		local r1, c1 = MoveActs.impact(m, m.minFall)
		local r2, c2 = MoveActs.impact(m, m.fullFall + 50)
		check(r1 == m.radius[1] and r2 == m.radius[2], "the stun grows with the drop")
		check(not c1 and c2, "and craters the street from high up")
		local wc = MV.wallCrusher
		check(wc.bite > 1 and wc.kick > 0, "Wall Crusher bites harder and kicks the panel out")
		check(
			has("src/server/Services/ImpactService.luau", "B.dmg * mult"),
			"its bites through ImpactService"
		)
		local mt = MV.meteorStrike
		check(MoveActs.apex(mt, 5) and not MoveActs.apex(mt, 60), "only near the top of a leap")
		local x, y, z, t = MoveActs.meteorAim(mt, 0, 100, 0, 0, 0, 500)
		check(math.abs(math.sqrt(x * x + (y - 100) ^ 2 + z * z) - mt.range) < 1e-6, "pulled in to its range")
		check(math.abs(t - mt.range / mt.speed) < 1e-6, "at its speed")
		local cfg = MoveRanks.config(M, "leap", 5)
		local cap = capOf("leap")
		check(
			mt.speed <= cap,
			string.format("the aimed pound (%d) sits inside the Leaping cap (%.0f)", mt.speed, cap)
		)
		check(run(cap, mt.speed, 1) == 0, "and passes the speed check")
		local vx, vy, vz = MoveActs.moonLeap(cfg, MoveMath.superLeapLaunch, 1, 0)
		local fx, fy, fz = MoveMath.superLeapLaunch(cfg, 1, 0, 1)
		local moon = math.sqrt(vx * vx + vy * vy + vz * vz)
		check(
			vy > 0 and math.abs(moon / math.sqrt(fx * fx + fy * fy + fz * fz) - MV.moonJump.share) < 1e-6,
			"Moon Jump: a share of a full leap"
		)
		check(moon <= cap, "inside the cap")
	end)

	test("Mobility moves: Acrobat's Kick Chain, Ceiling Drop, Shadow Flip and Slingshot", function()
		local k = MV.kickChain
		local chain = 0
		chain = MoveActs.chainStep(k, chain, 99)
		check(chain == 1 and MoveActs.kickMult(k, chain) == 1, "the first kick is a plain one")
		for _ = 1, 10 do
			chain = MoveActs.chainStep(k, chain, 0.5)
		end
		check(chain == k.most, "the chain stops at its most")
		check(math.abs(MoveActs.kickMult(k, chain) - (1 + k.step * (k.most - 1))) < 1e-9, "the fastest kick")
		check(MoveActs.chainStep(k, chain, k.within + 0.1) == 1, "a slow kick starts again")
		check(
			has("src/client/Controllers/MoveController.luau", "capTo(M.mobility.acrobat.cap)"),
			"kicks never pass the cap"
		)
		local cd = MV.ceilingDrop
		local cands = {
			{ id = 1, x = 0, y = 0, z = 0 },
			{ id = 2, x = 30, y = 0, z = 0 },
			{ id = 3, x = 0, y = 40, z = 0 },
		}
		local c = MoveActs.dropPick(cd, 2, 20, 0, cands)
		check(c ~= nil and c.id == 1, "the robot straight below")
		check(MoveActs.dropPick(cd, 2, 2, 0, cands) == nil, "nothing beside or above")
		local cap = capOf("acrobat")
		check(
			run(cap, M.mobility.acrobat.cap * 0.95, 1) == 0,
			"the drop's dash sits inside the Acrobat's cap"
		)
		local sf = MV.shadowFlip
		check(sf.life > 0 and sf.taunt > 0 and sf.cooldown > 0, "Shadow Flip leaves a clone that draws fire")
		check(
			has("src/server/Services/MoveActService.luau", "os.clock() - (hero.flipAt or -math.huge) > 1"),
			"only right after a real flip"
		)
		local sl = MV.slingshot
		-- on a wall facing +X, looking straight at the wall: the launch still goes away from it
		local dx, dz, t, up = MoveActs.slingPlan(sl, 1, 0, -1, 0.2)
		check(dx > 0, "never back into the wall")
		check(math.abs(math.sqrt(dx * dx + dz * dz) - sl.range) < 1e-6, "its range")
		local peak = MoveActs.arcPeak(dx, 0, dz, t, up)
		check(peak > cap, "a launch faster than the cap ...")
		check(
			run(cap, peak, t, nil, nil, sl.range + up * 2 + 10) == 0,
			"... is a granted arc, never pulled back"
		)
	end)

	test("Mobility moves: Swing's Double Zip, Yank, Wrecking Kick and Sky Hook", function()
		local dz = MV.doubleZip
		local sx, sz = MoveActs.secondLine(dz, 0, 1, 1)
		check(
			math.abs(math.deg(math.acos(sz)) - dz.spread) < 1e-6 and math.abs(sx) > 0,
			"the second line, spread off"
		)
		local cap = capOf("swing")
		local t = MoveActs.dashTime(dz, M.mobility.swing.zip, dz.range)
		check(
			MoveActs.arcPeak(0, 0, dz.range, t, math.min(8, dz.range * 0.08)) <= cap,
			"the shot forward sits inside the cap"
		)
		local y = MV.yank
		local cands = {
			{ id = 4, x = 0, y = 0, z = 40 },
			{ id = 5, x = 40, y = 0, z = 0 },
			{ id = 6, x = 0, y = 0, z = 200 },
		}
		local c = MoveActs.aimPick(y, 0, 0, 0, 0, 0, 1, cands)
		check(c ~= nil and c.id == 4, "Yank takes what the aim is on")
		check(MoveActs.aimPick(y, 0, 0, 0, 0, 1, 0, cands) == nil, "nothing off the aim or out of range")
		check(
			has("src/server/Services/ThrowService.luau", "function ThrowService.yank("),
			"then held like any grab"
		)
		local wk = MV.wreckingKick
		check(
			MoveActs.wallKick(wk, wk.speed) and not MoveActs.wallKick(wk, wk.speed - 1),
			"a fast swing kicks walls"
		)
		check(wk.speed >= Config.Combat.impact.ram.minSpeed, "fast enough for the server's ram check")
		check(MoveActs.bowl(wk, wk.bowl) and not MoveActs.bowl(wk, 40), "a fast release bowls robots")
		check(MV.skyHook.cooldown > 0, "Sky Hook: a full line from the sky, now and then")
		check(
			has("src/client/Controllers/MoveController.luau", 'if anchor and sky and canUse("skyHook") then'),
			"on the device"
		)
	end)

	test("Mobility moves: the server checks every move and PvP knocks follow compression", function()
		local path = "src/server/Services/MoveActService.luau"
		local src = fs.readFile(path)
		for _, id in MoveActs.ids(M) do
			local server = string.find(src, "ACTS." .. id .. " = function", 1, true) ~= nil
				or string.find(src, 'hasMove(hero, "' .. id .. '")', 1, true) ~= nil
			local device = id == "skyHook" or id == "moonJump" or id == "kickChain" -- the device's own feel
			check(server or device, id .. " is handled")
		end
		check(has(path, "HeroService.hasMove(hero, id)"), "only for a hero who picked it")
		check(has(path, "MoveActs.ready(b, id, now)"), "on the server's cooldown")
		check(has(path, "CombatService.moveHit("), "hits through CombatService")
		local cs = fs.readFile("src/server/Services/CombatService.luau")
		check(string.find(cs, "function CombatService.moveHit(", 1, true) ~= nil, "moveHit")
		check(
			string.find(cs, "pvpStatus(hero, eff, kind, dur, target, at, from, knockDir)", 1, true) ~= nil,
			"PvP control through pvpStatus"
		)
		check(
			string.find(cs, "math.min(eff.knock or 8, K8.maxDistance)", 1, true) ~= nil,
			"PvP knocks capped"
		)
		check(has(path, "local function mayBreak("), "no breaking in safe areas or story scenes")
		check(has("src/server/init.server.luau", 'boot("MoveActService", MoveActService.init)'), "it runs")
		check(has(path, 'FrameProf.wrap("MoveActService"'), "its frame loop is profiled")
		check(
			has("src/client/Controllers/MoveActClient.luau", 'FrameProf.wrap("MoveActClient"'),
			"and the device's"
		)
		check(
			has("src/server/Services/MoveGuard.luau", 'slip = Status.value(hero.status, "slip", now, 0)'),
			"the wake in the cap"
		)
	end)

	test("Mobility moves: the device sets them off, tells the server and draws them", function()
		if not T.placePath then
			return
		end
		local roblox = require("@lune/roblox")
		local UiSim = require("./uisim")
		local sim = UiSim.new(
			UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		)
		local char = UiSim.newInstance("Model")
		local root = UiSim.newInstance("Part")
		root.Name = "HumanoidRootPart"
		root.Parent = char
		char.Parent = sim.workspace
		sim.player.Character = char
		local State = sim:require("Client.State")
		local MC = sim:require("Client.Controllers.MoveController")
		local MAC = sim:require("Client.Controllers.MoveActClient")
		sim:run("MoveActClient", MAC.init)
		local sent = {}
		local remotes = sim.service("ReplicatedStorage"):WaitForChild("Remotes")
		remotes:WaitForChild("MoveAct")._props.FireServer = function(_, ...)
			table.insert(sent, { ... })
		end
		local function pick(p: string, rank3: number, rank5: number)
			local i = table.find(M.mobilityOrder, p) :: number
			State.hero.mobility = p
			State.hero.level = 40
			local ranks = { 0, 0, 0, 0, 0 }
			ranks[i] = 5
			State.hero.mobRanks = ranks
			local moves = table.create(10, 0)
			moves[(i - 1) * 2 + 1], moves[(i - 1) * 2 + 2] = rank3, rank5
			State.hero.mobMoves = moves
			sim:run("retune", MC.retune)
			table.clear(MC.moveBook)
			table.clear(sent)
		end
		local function last(): string?
			local s = sent[#sent]
			return s and MoveActs.idOf(M, s[1])
		end
		-- Flight: a landing after a big fall booms
		pick("flight", 1, 1)
		check(MC.has("sonicDive") and MC.has("phase") and not MC.has("slipstream"), "the picked moves are on")
		root.CFrame = roblox.CFrame.new(0, -80, 0)
		root.Position = roblox.Vector3.new(0, -80, 0)
		sim:run("land", function()
			MC.Landed:Fire(roblox.Vector3.new(0, -80, 0), 95)
		end)
		check(last() == "sonicDive", "Sonic Boom Dive went to the server")
		check(not MC.canUse("sonicDive"), "and is on its cooldown")
		-- Leaping: Impact Landing on the same drop, Wall Crusher on a climb kick
		pick("leap", 1, 2)
		sim:run("land", function()
			MC.Landed:Fire(roblox.Vector3.new(0, -80, 0), 95)
		end)
		check(last() == "impactLanding" and sent[#sent][3].Y > 0, "Impact Landing with its drop")
		pick("leap", 2, 2)
		sim:run("kick", function()
			MC.Kicked:Fire(roblox.Vector3.new(0, 5, 0), roblox.Vector3.new(1, 0, 0), "climb", 0)
		end)
		check(last() == "wallCrusher", "Wall Crusher on a kick off the climb")
		-- Acrobat: a flip leaves a clone
		pick("acrobat", 1, 1)
		sim:run("flip", function()
			MC.Flipped:Fire(roblox.Vector3.new(0, 5, 0))
		end)
		check(last() == "shadowFlip", "Shadow Flip on a flip")
		-- Swing: a fast release bowls
		pick("swing", 1, 1)
		sim:run("release", function()
			MC.SwingReleased:Fire(roblox.Vector3.new(0, 0, 120), true)
		end)
		check(last() == "wreckingKick", "Wrecking Kick's bowl on a fast release")
		-- every move draws, this device's and another hero's (MoveActFx), with no errors
		for i, id in MoveActs.ids(M) do
			sim:run("draw " .. id, function()
				MAC.draw(id, roblox.Vector3.new(0, 5, 0), roblox.Vector3.new(0, 0, 20), 1, sim.player, true)
				remotes
					:WaitForChild("MoveActFx").OnClientEvent
					:Fire(i, roblox.Vector3.new(4, 5, 0), roblox.Vector3.new(0, 0, 10), 1, 0)
			end)
		end
		sim:run("frames", function()
			for _ = 1, 5 do
				sim.service("RunService").Heartbeat:Fire(1 / 30)
			end
		end)
		check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
	end)
end
