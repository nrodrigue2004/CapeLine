-- Hero MMO features (spec: Hero MMO features, milestones H1 to H8): the pure rules, run by tests/run.luau.
-- Each milestone's tests follow its "Done when (tests)" line in the build spec.

return function(T: any)
	local test, check, near, Config = T.test, T.check, T.near, T.Config
	local fs = require("@lune/fs")

	local function source(path: string): string
		return fs.readFile(path)
	end

	---------------------------------------------------------------------------
	-- H1: block, breaker, interrupt, perfect block
	---------------------------------------------------------------------------
	local GuardMath = require("../src/shared/GuardMath")
	local G = Config.Guard

	test("H1: spec numbers for block, breakers, interrupts and the perfect block", function()
		check(
			G.block.cut == 0.7 and G.block.moveMult == 0.5 and G.block.front == 180,
			"70% less, half speed, front half"
		)
		check(
			G.block.guardMax == 100 and G.block.refill == 25 and G.block.refillDelay == 1,
			"Guard 100, +25/s after 1 s"
		)
		check(
			G.breaker.coeff == Config.Combat.heavyCoeff and G.breaker.stagger == 1,
			"breakers at the heavy line, 1 s stagger"
		)
		check(
			G.interrupt.coeff == 0.8 and G.interrupt.refund == 0.5,
			"light under 0.8, half the cooldown back"
		)
		check(
			G.perfect.window == 0.2 and G.perfect.stagger == 0.6 and G.perfect.meter == 10,
			"perfect: 0.2 s, 0.6 s, +10"
		)
	end)

	test("H1: the triangle: block beats hits, breakers beat block, interrupts beat breakers", function()
		local st = GuardMath.new(G, 0)
		check(GuardMath.setBlock(G, st, true, 0) == true, "block starts")
		-- a normal hit after the perfect window: 70% less, no knockback, Guard drains
		local r = GuardMath.resolve(G, st, { damage = 100, maxHealth = 1000, coeff = 1.2, front = true }, 1)
		check(r.outcome == "blocked", "a normal hit is blocked")
		near(r.mult, 0.3, 1e-9, "70% less damage")
		check(r.noKnock, "no knockback when blocked")
		near(GuardMath.guard(G, st, 1), 90, 1e-9, "Guard drains by the hit's share of health x 100")
		-- from behind: a plain hit
		local back =
			GuardMath.resolve(G, st, { damage = 100, maxHealth = 1000, coeff = 1.2, front = false }, 1.1)
		check(back.outcome == "hit" and back.mult == 1, "a hit from behind gets through")
		-- a breaker shatters: full hit, 1 s stagger, the block ends
		local b = GuardMath.resolve(G, st, { damage = 300, maxHealth = 1000, coeff = 2.5, front = true }, 1.2)
		check(b.outcome == "shatter" and b.mult == 1 and b.stagger == 1, "a heavy hit shatters the block")
		check(not st.on and GuardMath.staggered(st, 1.5), "the block is down and the hero reels")
		check(select(2, GuardMath.setBlock(G, st, true, 1.5)) == "broken", "no new block while staggered")
		check(GuardMath.setBlock(G, st, true, 2.3) == true, "a block again after the stagger")
		-- a full charge and a grab are breakers too
		check(GuardMath.isBreaker(G, { coeff = 1, charged = 1 }), "a full charge breaks")
		check(not GuardMath.isBreaker(G, { coeff = 1, charged = 0.9 }), "a part charge does not")
		check(GuardMath.isBreaker(G, { grab = true }), "a grab breaks")
		check(GuardMath.isBreaker(G, { breaker = true }), "a robot heavy breaks")
		-- interrupts: light hits, stuns and knocks cancel a heavy wind-up or a charge
		check(GuardMath.isInterrupt(G, { coeff = 0.5 }), "a light hit interrupts")
		check(not GuardMath.isInterrupt(G, { coeff = 0.8 }), "0.8 is not light")
		check(GuardMath.isInterrupt(G, { coeff = 1.5, status = "stun" }), "a stun interrupts")
		check(GuardMath.isInterrupt(G, { coeff = 2, status2 = "knockback" }), "a knock interrupts")
		check(not GuardMath.isInterrupt(G, { coeff = 2, status = "slow" }), "a slow does not")
		check(GuardMath.interrupts(G, { coeff = 0.4 }, true), "it cancels a wind-up in progress")
		check(not GuardMath.interrupts(G, { coeff = 0.4 }, false), "nothing to cancel when not winding up")
		check(GuardMath.heavyWindup(G, { cast = 0.6, coeff = 3 }), "a heavy with a wind-up can be cut")
		check(not GuardMath.heavyWindup(G, { cast = 0.6, coeff = 1 }), "a light wind-up is not a heavy")
		near(GuardMath.refund(G, 12), 6, 1e-9, "an interrupted move costs half its cooldown")
	end)

	test("H1: Guard drain, Guard at 0 shatters, refill after 1 s at 25 a second", function()
		local st = GuardMath.new(G, 0)
		GuardMath.setBlock(G, st, true, 0)
		local r
		for i = 1, 3 do
			r = GuardMath.resolve(G, st, { damage = 300, maxHealth = 1000, coeff = 1, front = true }, i)
		end
		check(r.outcome == "blocked", "three 30% hits are blocked")
		near(GuardMath.guard(G, st, 3), 10, 1e-9, "Guard at 10")
		r = GuardMath.resolve(G, st, { damage = 300, maxHealth = 1000, coeff = 1, front = true }, 4)
		check(r.outcome == "shatter" and r.guardOut == true and r.mult == 1, "Guard at 0 shatters")
		near(GuardMath.guard(G, st, 4.9), 0, 1e-9, "no refill inside the 1 s delay")
		near(GuardMath.guard(G, st, 5.0), 0, 1e-9, "refill starts after 1 s")
		near(GuardMath.guard(G, st, 6.0), 25, 1e-9, "25 a second")
		near(GuardMath.guard(G, st, 20), 100, 1e-9, "capped at 100")
		check(select(2, GuardMath.setBlock(G, st, true, 5.1)) == "low", "too little Guard to start a block")
		local st2 = GuardMath.new(G, 0)
		GuardMath.setBlock(G, st2, true, 0)
		GuardMath.resolve(G, st2, { damage = 200, maxHealth = 1000, coeff = 1, front = true }, 1)
		near(GuardMath.guard(G, st2, 5), 80, 1e-9, "no refill while the block is held")
		GuardMath.setBlock(G, st2, false, 5)
		near(GuardMath.guard(G, st2, 6.5), 80 + 0.5 * 25, 1e-9, "refills 1 s after letting go")
		check(
			select(2, GuardMath.setBlock(G, GuardMath.new(G), true, 0, { safe = true })) == "safe",
			"no block in a safehouse"
		)
	end)

	test("H1: the perfect block window", function()
		local st = GuardMath.new(G, 0)
		GuardMath.setBlock(G, st, true, 10)
		local r = GuardMath.resolve(G, st, { damage = 500, maxHealth = 1000, coeff = 3, front = true }, 10.2)
		check(r.outcome == "perfect" and r.mult == 0, "within 0.2 s: no damage, even from a heavy")
		check(r.attackerStagger == 0.6 and r.meter == 10, "the attacker reels 0.6 s, +10 Awakening")
		near(GuardMath.guard(G, st, 10.2), 100, 1e-9, "a perfect block costs no Guard")
		local st2 = GuardMath.new(G, 0)
		GuardMath.setBlock(G, st2, true, 10)
		local late =
			GuardMath.resolve(G, st2, { damage = 100, maxHealth = 1000, coeff = 1, front = true }, 10.21)
		check(late.outcome == "blocked", "0.21 s is an ordinary block")
		local st3 = GuardMath.new(G, 0)
		GuardMath.setBlock(G, st3, true, 10)
		local grab =
			GuardMath.resolve(G, st3, { damage = 100, maxHealth = 1000, grab = true, front = true }, 10.05)
		check(grab.outcome == "shatter", "a grab is never perfect-blocked")
		local st4 = GuardMath.new(G, 0)
		GuardMath.setBlock(G, st4, true, 10)
		local behind =
			GuardMath.resolve(G, st4, { damage = 100, maxHealth = 1000, coeff = 1, front = false }, 10.05)
		check(behind.outcome == "hit", "no perfect block from behind")
	end)

	test("H1: front half and PvP compression", function()
		check(GuardMath.front(180, 0, -1, 0, 0, 0, -10), "straight ahead is the front")
		check(GuardMath.front(180, 0, -1, 0, 0, 10, -0.01), "just ahead of the side is the front")
		check(not GuardMath.front(180, 0, -1, 0, 0, 10, 0.5), "just behind the side is not")
		check(not GuardMath.front(180, 0, -1, 0, 0, 0, 10), "behind is not")
		check(GuardMath.front(180, 0, -1, 0, 0, 0.1, 0.1), "point blank counts as the front")
		-- PvP: the same rules on the compressed damage (FlagService.damage runs first)
		local PvpRules = require("../src/shared/PvpRules")
		local raw = 400
		local compressed = PvpRules.damage(Config, raw, {
			power = 300,
			pvpPower = PvpRules.power(Config, 30, 0),
			maxHealth = 3000,
			pvpHealth = PvpRules.health(Config, 30, 0, "Powerhouse"),
			super = false,
		})
		check(compressed > 0 and compressed ~= raw, "compression changes the hit")
		local st = GuardMath.new(G, 0)
		GuardMath.setBlock(G, st, true, 0)
		local r =
			GuardMath.resolve(G, st, { damage = compressed, maxHealth = 1000, coeff = 1.2, front = true }, 1)
		check(r.outcome == "blocked", "a compressed PvP hit is blocked like any other")
		near(
			GuardMath.guard(G, st, 1),
			100 - compressed / 1000 * 100,
			1e-6,
			"Guard drains by the compressed hit"
		)
	end)

	test("H1: robots block on a timer and shatter on breakers", function()
		local rb = G.robotBlocks.BruteBot
		check(rb ~= nil and Config.Enemies.BruteBot ~= nil, "Brute Bots block on a timer")
		check(
			G.robotBreakers.brute and G.robotBreakers.guard,
			"Brute slams and Sentinel sweeps break a hero's block"
		)
		local rs = GuardMath.robotNew(rb, 0)
		check(GuardMath.robotStep(rb, rs, rb.first - 0.1, true, false) == nil, "waits `first` seconds")
		check(GuardMath.robotStep(rb, rs, rb.first, true, false) == "start", "then blocks")
		check(GuardMath.robotBlocking(rs, rb.first + 0.5), "blocking")
		local out, mult = GuardMath.robotHit(G, rb, rs, { coeff = 1, front = true }, rb.first + 0.5)
		check(out == "blocked", "a normal hit is blocked")
		near(mult, 1 - rb.cut, 1e-9, "for less damage")
		out = GuardMath.robotHit(G, rb, rs, { coeff = 1, front = false }, rb.first + 0.6)
		check(out == "hit", "around the shield gets through")
		out, mult = GuardMath.robotHit(G, rb, rs, { coeff = 3, front = true }, rb.first + 0.7)
		check(out == "shatter" and mult == 1, "a heavy shatters it")
		check(not GuardMath.robotBlocking(rs, rb.first + 0.8), "the block is gone")
		check(GuardMath.robotStep(rb, rs, rb.first + 0.8, true, false) == nil, "no stop twice")
		check(
			GuardMath.robotStep(rb, rs, rb.first + 0.7 + rb.brokenFor - 0.1, true, false) == nil,
			"no new block while broken"
		)
		check(
			GuardMath.robotStep(rb, rs, rb.first + 0.7 + rb.brokenFor, true, false) == "start",
			"blocks again later"
		)
		check(
			GuardMath.robotStep(rb, rs, rb.first + 0.7 + rb.brokenFor + 0.1, true, true) == "stop",
			"a wind-up drops it"
		)
		local rs2 = GuardMath.robotNew(rb, 0)
		check(GuardMath.robotStep(rb, rs2, 100, false, false) == nil, "only while fighting")
		check(
			GuardMath.robotStep(rb, rs2, 100 + rb.first, true, false) == "start",
			"fighting: blocks after `first`"
		)
		check(
			GuardMath.robotStep(rb, rs2, 100 + rb.first + rb.time, true, false) == "stop",
			"holds `time` seconds"
		)
	end)

	test("H1: wiring: remotes, Block on every input, juice rows, and the server hooks", function()
		local Remotes = require("../src/shared/Remotes")
		check(Remotes.CombatBlock.dir == "C2S" and Remotes.CombatBlock.rate == 10, "Combat.Block 10/s")
		check(Remotes.CombatBlock.schema[1].t == "boolean", "Block takes on/off")
		check(Remotes.GuardState.dir == "S2C" and Remotes.GuardEvent.dir == "S2C", "guard state and words")
		local input = source("src/client/Controllers/InputController.luau")
		check(
			string.find(input, '%[Enum.KeyCode.LeftAlt%] = "Block"') ~= nil,
			"Alt blocks on PC (F stays Fly)"
		)
		check(string.find(input, '%[Enum.KeyCode.ButtonL1%] = "Block"') ~= nil, "LB blocks on a gamepad")
		check(string.find(input, '%[Enum.KeyCode.F%] = "Fly"') ~= nil, "F is still Fly")
		local hud = source("src/client/Ui/Hud.luau")
		check(string.find(hud, '"Block",', 1, true) ~= nil, "the shield button on the HUD (phones)")
		local juice = {}
		for _, row in Config.Audio.juice do
			juice[row.id] = row.visual
		end
		for _, id in { "block", "perfectBlock", "shatter", "interrupt" } do
			check(juice[id] == "GuardFx", id .. " is a juice row drawn by GuardFx")
		end
		local combat = source("src/server/Services/CombatService.luau")
		check(string.find(combat, "BlockService.resolveHero", 1, true) ~= nil, "PvP hits meet the block")
		check(string.find(combat, "BlockService.robotHit", 1, true) ~= nil, "robot hits meet robot blocks")
		check(string.find(combat, "BlockService.blocking(hero)", 1, true) ~= nil, "no casting while blocking")
		local hero = source("src/server/Services/HeroService.luau")
		check(
			string.find(hero, "HeroService.guardHook(hero, amount, source)", 1, true) ~= nil,
			"robot hits meet the block"
		)
	end)
end
