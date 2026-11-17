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

	---------------------------------------------------------------------------
	-- H2: charge-up powers
	---------------------------------------------------------------------------
	local ChargeRules = require("../src/shared/ChargeRules")

	test("H2: about 24 charge-up powers, 1 or 2 a path, every archetype has them", function()
		local A = Config.Abilities
		local perSet, n = {}, 0
		for _, row in A.list do
			if row.charge then
				n += 1
				perSet[row.set] = (perSet[row.set] or 0) + 1
				check(ChargeRules.power(row), row.id .. " charges as a power")
				check(
					row.slot == "skill" and not row.channel and (row.coeff or 0) > 0,
					row.id .. " is a damaging skill"
				)
				local ch = row.charge
				check(ch.max == 1.2 and ch.mult == 2.2 and ch.grow == 1.5, row.id .. " uses the spec numbers")
			end
		end
		check(n >= 22 and n <= 26, string.format("about 24 (%d)", n))
		for _, set in A.sets do
			local k = perSet[set] or 0
			check(k >= 1 and k <= 2, set .. " has 1 or 2 charge powers")
		end
		for _, cls in Config.Classes.order do
			local any = false
			for _, path in Config.Classes[cls].paths do
				any = any or (perSet[path] or 0) > 0
			end
			check(any, cls .. " has a charge power")
		end
		-- the spec's examples
		for _, id in { "ChainLightning", "GroundSlam", "TrickShot", "Repulse" } do
			check(A.list[id].charge ~= nil, id .. " charges (a spec example)")
		end
		check(Config.Combat.charge.powerSlow == 0.6, "charging slows you to 60%")
	end)

	test("H2: charge scaling, full is a breaker, the other skills keep the modest charge", function()
		local CC = Config.Combat
		local row = Config.Abilities.list.ChainLightning
		check(ChargeRules.level(CC, 0.2, row) == 0, "a tap does not charge")
		check(ChargeRules.level(CC, 1.2, row) == 1, "full at 1.2 s")
		near(ChargeRules.level(CC, (CC.charge.start + 1.2) / 2, row), 0.5, 1e-6, "half way is half")
		local tap = ChargeRules.apply(CC, table.clone(row), 0)
		check(tap.coeff == row.coeff and not tap.breaker, "a tap fires as now")
		local half = ChargeRules.apply(CC, table.clone(row), 0.5)
		near(half.coeff, row.coeff * 1.6, 1e-6, "half a charge: 1.6x")
		check(
			not half.breaker and not GuardMath.isBreaker(G, { coeff = 1, charged = half.chargedBig }),
			"half is no breaker"
		)
		local full = ChargeRules.apply(CC, table.clone(row), 1)
		near(full.coeff, row.coeff * 2.2, 1e-6, "full: 2.2x damage")
		near(full.range, row.range * 1.5, 1e-6, "the shape grows 1.5x")
		near(full.cone, math.min(170, row.cone * 1.5), 1e-6, "a cone grows too, never past 170")
		check(full.breaker == true and full.chargedBig == 1, "a full charge is a breaker")
		check(
			GuardMath.isBreaker(G, { coeff = full.coeff, charged = full.chargedBig, breaker = full.breaker }),
			"and breaks a block"
		)
		local nova = Config.Abilities.list.GroundSlam
		local big = ChargeRules.apply(CC, table.clone(nova), 1)
		near(big.radius, nova.radius * 1.5, 1e-6, "a nova grows")
		-- a skill without a charge row keeps the 2026-11-17 modest charge and is never a breaker
		local plain
		for _, id in Config.Abilities.order do
			local r = Config.Abilities.list[id]
			if not plain and r.charge == nil and ChargeRules.chargeable(r) and (r.coeff or 0) > 0 then
				plain = r
			end
		end
		check(plain ~= nil and not ChargeRules.power(plain), "other aimed skills only charge a little")
		local m = ChargeRules.apply(CC, table.clone(plain), 1)
		near(m.coeff, plain.coeff * (1 + CC.charge.damage), 1e-6, "+20% at full")
		check(not m.breaker and m.chargedBig == nil, "never a breaker")
		-- Telekinesis throws: a charge row makes a throw chargeable
		check(ChargeRules.power(Config.Abilities.list.Telekinesis), "Telekinesis charges its throw")
		-- the server's cap uses the row's own time
		check(ChargeRules.allowed(CC, 100, 10, 10 + 1.2, 0, row) == 1, "a real 1.2 s hold is full")
		check(ChargeRules.allowed(CC, 100, 10, 10.3, 0, row) < 0.25, "a claim beyond the timed hold is cut")
	end)

	test("H2: an interrupt cancels a charge and costs half its cooldown", function()
		local row = Config.Abilities.list.Crush
		check(GuardMath.interrupts(G, { coeff = 0.5 }, true), "a light hit cancels a charge in progress")
		check(GuardMath.interrupts(G, { coeff = 2, status = "knockback" }, true), "a knock cancels it")
		check(not GuardMath.interrupts(G, { coeff = 2 }, true), "a heavy does not (it is blocked or traded)")
		near(GuardMath.refund(G, row.cd), row.cd / 2, 1e-9, "the power goes on half its cooldown")
		local block = source("src/server/Services/BlockService.luau")
		check(
			string.find(block, "ChargeRules.power(row)", 1, true) ~= nil,
			"only charge-up powers are cut, not aiming"
		)
		local combat = source("src/server/Services/CombatService.luau")
		check(string.find(combat, 'SetAttribute("Charging", num)', 1, true) ~= nil, "others see the glow")
		check(
			string.find(combat, "HeroService.speedHooks.charge", 1, true) ~= nil,
			"the server slows a charging hero"
		)
		local client = source("src/client/Controllers/CombatClient.luau")
		check(
			string.find(client, 'setScale("charge", C.charge.powerSlow)', 1, true) ~= nil,
			"and so does the client"
		)
		local hud = source("src/client/Ui/Hud.luau")
		check(string.find(hud, "ChargeFill", 1, true) ~= nil, "the ring fills on the button")
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

	---------------------------------------------------------------------------
	-- H3: pick up and throw
	---------------------------------------------------------------------------
	local ThrowMath = require("../src/shared/ThrowMath")
	local TW = Config.Throw

	test("H3: weights, who lifts what, never citizens or heroes", function()
		check(
			TW.reach == 10 and TW.liftTime == 0.3 and TW.carrySpeed == 0.8 and TW.carryMax == 8,
			"spec numbers"
		)
		check(TW.respawn == 60 and TW.titan.reach == 20, "props back in 60 s; Titan reaches 20")
		local W = TW.weights
		check(W.light.coeff == 0.8 and W.medium.coeff == 1.6 and W.heavy.coeff == 3.0, "0.8, 1.6, 3.0")
		check(W.heavy.breaker and not W.light.breaker and not W.medium.breaker, "only heavy is a breaker")
		for kind, want in
			{
				bench = "light",
				trashCan = "light",
				mailbox = "light",
				sign = "light",
				rubble = "light",
				lampPost = "medium",
				dumpster = "medium",
				vending = "medium",
				car = "heavy",
				truck = "heavy",
				slab = "heavy",
			}
		do
			check(ThrowMath.weight(TW, kind) == want, kind .. " is " .. want)
		end
		for _, cls in Config.Classes.order do
			check(ThrowMath.canLift(TW, "bench", cls, false), cls .. " lifts a bench")
			check(ThrowMath.canLift(TW, "dumpster", cls, false), cls .. " lifts a dumpster")
			check(
				ThrowMath.canLift(TW, "car", cls, false) == (cls == "Powerhouse"),
				cls .. ": cars only for Powerhouse"
			)
			check(ThrowMath.canLift(TW, "car", cls, true), cls .. " lifts a car while Awakened")
		end
		check(ThrowMath.canLift(TW, "slab", "Mystic", false, true), "Lift and Throw lifts any weight")
		for _, kind in { "citizen", "hero", "player", "tram", "nothing" } do
			check(not ThrowMath.canLift(TW, kind, "Powerhouse", true, true), kind .. " is never lifted")
		end
	end)

	test("H3: the nearest liftable in reach, busy ones skipped", function()
		local items = {
			{ id = 1, kind = "bench", x = 5, y = 0, z = 0 },
			{ id = 2, kind = "car", x = 3, y = 0, z = 0 },
			{ id = 3, kind = "trashCan", x = 2, y = 0, z = 0, busy = true },
			{ id = 4, kind = "mailbox", x = 11, y = 0, z = 0 },
			{ id = 5, kind = "sign", x = 1, y = 30, z = 0 },
		}
		local function rogue(kind: string)
			return ThrowMath.canLift(TW, kind, "Rogue", false)
		end
		local function titan(kind: string)
			return ThrowMath.canLift(TW, kind, "Powerhouse", false)
		end
		check(
			ThrowMath.nearest(items, 0, 0, 0, TW.reach, rogue) == 1,
			"a Rogue gets the bench (no car, no busy bin)"
		)
		check(ThrowMath.nearest(items, 0, 0, 0, TW.reach, titan) == 2, "a Powerhouse gets the nearer car")
		check(ThrowMath.nearest(items, 20, 0, 0, TW.reach, rogue) == 4, "the mailbox from the other side")
		check(ThrowMath.nearest(items, 40, 0, 0, TW.reach, rogue) == nil, "nothing in reach")
		check(
			ThrowMath.nearest(items, 30, 0, 0, TW.titan.reach, rogue) == 4,
			"19 studs is inside Lift and Throw's 20"
		)
	end)

	test("H3: arcs: range per weight, the same parabola everywhere, landing hits", function()
		local tx, ty, tz, time, peak = ThrowMath.arc(TW, "light", 0, 10, 0, 0, 10, -500)
		near(tz, -TW.weights.light.range, 1e-6, "a long aim is cut to the weight's range")
		check(tx == 0 and ty == 10, "along the aim")
		near(time, TW.weights.light.range / TW.weights.light.speed, 1e-6, "flight time from the speed")
		near(peak, TW.weights.light.range * TW.weights.light.arc, 1e-6, "peak from the distance")
		local _, _, hz = ThrowMath.arc(TW, "heavy", 0, 10, 0, 0, 10, -500)
		check(-hz < -tz, "heavy things fly shorter")
		local _, _, _, short = ThrowMath.arc(TW, "medium", 0, 0, 0, 1, 0, 0)
		check(short == TW.minFlight, "never shorter than the minimum flight")
		local x0, y0, z0 = ThrowMath.arcPoint(0, 10, 0, 0, 0, -40, 8, 0)
		local x1, y1, z1 = ThrowMath.arcPoint(0, 10, 0, 0, 0, -40, 8, 1)
		local _, ym = ThrowMath.arcPoint(0, 10, 0, 0, 0, -40, 8, 0.5)
		check(
			x0 == 0 and y0 == 10 and z0 == 0 and x1 == 0 and y1 == 0 and z1 == -40,
			"starts at the hand, ends where it lands"
		)
		near(ym, 5 + 8, 1e-6, "the peak rides on the middle of the line")
		local light, heavy = ThrowMath.hit(TW, "light"), ThrowMath.hit(TW, "heavy")
		check(
			light.coeff == 0.8 and light.structDmg == nil and not light.breaker,
			"light: 0.8, small knock, no blast"
		)
		check(
			heavy.coeff == 3.0 and heavy.breaker and heavy.structDmg >= Config.Destruction.structure.chunkCost,
			"heavy breaks wall panels"
		)
		check(ThrowMath.hit(TW, "medium").structKind == 2, "medium: a small blast on walls")
		check(
			GuardMath.isBreaker(G, { coeff = heavy.coeff, breaker = heavy.breaker }),
			"a heavy throw breaks a block"
		)
		check(not GuardMath.isBreaker(G, { coeff = light.coeff }), "a light one is blocked")
		near(
			ThrowMath.hit(TW, "heavy", true).radius,
			heavy.radius * TW.titan.radiusMult,
			1e-6,
			"Lift and Throw: a bigger nova"
		)
	end)

	test("H3: carry, lift and respawn timers; props stand on Downtown's sidewalks", function()
		check(not ThrowMath.lifted(TW, 10, 10.2) and ThrowMath.lifted(TW, 10, 10.3), "no throw before 0.3 s")
		check(not ThrowMath.carryOver(TW, 0, 7.9) and ThrowMath.carryOver(TW, 0, 8), "set down after 8 s")
		check(not ThrowMath.respawnReady(TW, 0, 59, 500), "not before 60 s")
		check(not ThrowMath.respawnReady(TW, 0, 120, 50), "not while someone is looking")
		check(ThrowMath.respawnReady(TW, 0, 61, 500), "back once nobody is near")
		local spots = ThrowMath.place(TW, Config)
		local again = ThrowMath.place(TW, Config)
		check(
			#spots >= 40 and #spots == #again,
			string.format("about 80 props (%d), the same every time", #spots)
		)
		local kinds, d, same = {}, Config.City.districts.Downtown, true
		for i, s in spots do
			kinds[s.kind] = true
			same = same and again[i].kind == s.kind and again[i].x == s.x and again[i].z == s.z
			check(s.x > d.minX and s.x < d.maxX and s.z > d.minZ and s.z < d.maxZ, "inside Downtown")
			check(TW.kinds[s.kind] ~= nil and not TW.kinds[s.kind].vehicle, "a prop kind")
		end
		check(same, "a fixed seed: every server matches")
		check(kinds.bench and kinds.dumpster and kinds.slab, "light, medium and heavy props all show up")
	end)

	test("H3: wiring: remotes, flag rule, cars through the reset, no casting while carrying", function()
		local R = require("../src/shared/Remotes")
		check(R.WorldGrab.rate == 4 and R.WorldThrow.rate == 4, "4 a second")
		local combat = source("src/server/Services/CombatService.luau")
		check(
			string.find(combat, "function CombatService.thrown", 1, true) ~= nil,
			"the landing hits through CombatService"
		)
		check(
			string.find(combat, "hitArea(hero, eff, r, land, hit.radius, hit.coeff)", 1, true) ~= nil,
			"hitArea's cands: only heroes flagged against the thrower"
		)
		check(
			string.find(combat, "BlockService%.blocking%(hero%)%s+or hero%.carry%s+then") ~= nil,
			"no casting with your hands full"
		)
		local throw = source("src/server/Services/ThrowService.luau")
		check(string.find(throw, "VehicleService.drop(", 1, true) ~= nil, "cars land through VehicleService")
		check(string.find(throw, "HeroService.speedHooks.carry", 1, true) ~= nil, "80% while carrying")
		check(
			string.find(throw, "CombatService.titanLift = titanLift", 1, true) ~= nil,
			"Lift and Throw lifts world things"
		)
		local client = source("src/client/Controllers/ThrowClient.luau")
		check(
			string.find(client, 'setScale("carry"', 1, true) ~= nil,
			"the client slows too (no boost below 1)"
		)
		local block = source("src/server/Services/BlockService.luau")
		check(string.find(block, "hero.carry) then", 1, true) ~= nil, "no block with your hands full")
	end)

	---------------------------------------------------------------------------
	-- H4: sidekicking (missions only) and task forces
	---------------------------------------------------------------------------
	local SidekickRules = require("../src/shared/SidekickRules")
	local TaskForcePlan = require("../src/shared/TaskForcePlan")
	local SK, TF = Config.Sidekick, Config.TaskForce

	test(
		"H4: mission level is the top member's; sidekicks are raised to it minus 1, never lowered",
		function()
			check(SidekickRules.missionLevel({ 5, 30, 12 }) == 30, "the highest member")
			check(SidekickRules.missionLevel({ 3, 4 }, 6) == 6, "never below the mission's floor")
			check(SidekickRules.raised(SK, 5, 30) == 29, "a level 5 counts as 29 with a level 30")
			check(SidekickRules.raised(SK, 29, 30) == 29, "1 below: not a sidekick")
			check(SidekickRules.raised(SK, 30, 30) == 30, "the top member is unchanged")
			check(SidekickRules.raised(SK, 28, 30) == 29, "2 below is raised")
			check(
				not SidekickRules.isSidekick(SK, 29, 30) and SidekickRules.isSidekick(SK, 28, 30),
				"the gap is 1"
			)
			check(SidekickRules.raised(SK, 35, 30) == 35, "never lowered")
			check(SidekickRules.level(5, 29, true) == 29, "the raise counts in the pocket")
			check(SidekickRules.level(5, 29, false) == 5, "and never outside it")
			check(SidekickRules.level(5, nil, true) == 5, "no raise, no change")
			local worn = {
				{ id = 1, ilvl = 5, main = 10, bonus = { { 2, 4 } } },
				{ id = 2, ilvl = 31, main = 60, bonus = {} },
			}
			local up = SidekickRules.raiseGear(worn, 29)
			check(
				up[1].ilvl == 29 and up[1].main == 58 and up[1].bonus[1][2] == 23,
				"a level 5 piece counts at 29"
			)
			check(up[2] == worn[2], "a piece above the raise is unchanged")
			check(worn[1].ilvl == 5 and worn[1].main == 10, "the saved piece never changes")
			check(SidekickRules.raiseGear(worn, nil) == worn, "no raise: the same list")
			local F = require("../src/shared/Formulas")
			check(F.health(Config, 29, 0, "Mystic") > F.health(Config, 5, 0, "Mystic") * 2, "raised health")
		end
	)

	test("H4: pay at your own level, +20% Renown as a sidekick, +10% as a mentor", function()
		local m, mentor, side = SidekickRules.renown(SK, 5, { 5, 30 })
		near(m, 1.2, 1e-9, "a sidekick: +20% Renown")
		check(side and not mentor, "counts as a sidekick clear")
		m, mentor = SidekickRules.renown(SK, 30, { 5, 30 })
		near(m, 1.1, 1e-9, "the top member: +10% with a sidekick 5+ levels lower")
		check(mentor, "counts toward the Mentor badges")
		m, mentor = SidekickRules.renown(SK, 30, { 27, 30 })
		near(m, 1, 1e-9, "3 levels lower is no mentor bonus")
		check(not mentor, "and no mentor clear")
		check(SidekickRules.partyHp(SK, 1) == 1, "solo: as now")
		check(SidekickRules.partyHp(SK, 4) > SidekickRules.partyHp(SK, 2), "more health per player")
		check(SidekickRules.partyHp(SK, 9) == SK.partyHp[#SK.partyHp], "capped at 4")
		local ms = source("src/server/Services/MissionService.luau")
		check(
			string.find(ms, 'EconomyService.reward(player, "mission", own)', 1, true) ~= nil,
			"pay at your own level"
		)
		check(string.find(ms, "GearService.grant(player, m.loot, own)", 1, true) ~= nil, "and gear drops")
		check(
			string.find(ms, "SidekickRules.missionLevel(list, m.minLevel)", 1, true) ~= nil,
			"the top member's level"
		)
		check(string.find(ms, "SquadRules.median", 1, true) == nil, "the median is gone from missions")
		check(string.find(ms, "MissionService.setRaise(hero, nil)", 1, true) ~= nil, "leaving ends the raise")
		local hero = source("src/server/Services/HeroService.luau")
		check(
			string.find(hero, 'hero.scene == "mission"', 1, true) ~= nil,
			"stats read the raise only in a pocket"
		)
		for _, f in { "IncidentService", "ContractService", "EventService", "BossService", "FlagService" } do
			local src = source("src/server/Services/" .. f .. ".luau")
			check(string.find(src, "setRaise", 1, true) == nil, f .. " never raises anyone (missions only)")
		end
	end)

	test("H4: task forces: 2 at launch, legs from existing steps, who may start or join", function()
		check(#TF.list == 2 and TF.floor == 12 and TF.maxPlayers == 4 and TF.rejoin == 180, "spec numbers")
		local sides = {}
		local kinds = {
			hold = true,
			["break"] = true,
			chase = true,
			reach = true,
			defeat = true,
			boss = true,
			warframe = true,
		}
		local layouts = { station = true, tower = true, rooftops = true, dungeon = true, arena = true }
		for i, t in TF.list do
			sides[t.side] = true
			check(#t.legs >= 4 and #t.legs <= 5, t.id .. ": 4 or 5 missions")
			for li, l in t.legs do
				check(layouts[l.layout] == true, t.id .. " leg " .. li .. " on an existing pocket layout")
				for _, st in l.steps do
					check(kinds[st.kind] == true, t.id .. " uses existing step kinds (" .. st.kind .. ")")
				end
				local leg = TaskForcePlan.leg(TF, i, li)
				check(leg ~= nil and leg.num == TF.numBase + i, "a mission-shaped leg")
				check(
					leg ~= nil and leg.legs == #t.legs and leg.leg == li and leg.minLevel == TF.floor,
					"its place"
				)
			end
			check(TaskForcePlan.leg(TF, i, #t.legs + 1) == nil, "no leg past the end")
		end
		check(sides.hero and sides.villain, "one per side")
		check(TF.numBase > #Config.Story.missions, "task force runs never clash with Act 1 mission numbers")
		check(TaskForcePlan.canStart(TF, 1, 12, "hero", true), "level 12 after Act 1 starts one")
		check(not TaskForcePlan.canStart(TF, 1, 11, "hero", true), "not at 11")
		check(not TaskForcePlan.canStart(TF, 1, 20, "hero", false), "not before Act 1 is done")
		check(not TaskForcePlan.canStart(TF, 1, 20, "villain", true), "not the other side's")
		local l = { id = 1, tf = 1, side = "hero", members = { 1 }, locked = false, running = false }
		check(
			TaskForcePlan.canJoin(TF, l, 10, "hero", true),
			"Looking takes you within 2 levels of the floor"
		)
		check(not TaskForcePlan.canJoin(TF, l, 9, "hero", true), "but not 3 below")
		check(not TaskForcePlan.canJoin(TF, l, 20, "villain", true), "never the other side")
	end)

	test("H4: quick join, rejoin within 3 minutes, leader hand-off, weekly double Renown", function()
		local function friendOf(uid: number)
			return uid == 7
		end
		local lobbies = {
			{ id = 1, tf = 1, side = "hero", members = { 1 }, locked = false, running = false },
			{ id = 2, tf = 1, side = "hero", members = { 2, 3, 4 }, locked = false, running = false },
			{ id = 3, tf = 1, side = "hero", members = { 5, 6, 8 }, locked = true, running = false },
			{ id = 4, tf = 2, side = "villain", members = { 9, 10, 11 }, locked = false, running = false },
			{ id = 5, tf = 1, side = "hero", members = { 7, 12 }, locked = true, running = false },
			{ id = 6, tf = 1, side = "hero", members = { 13, 14, 15 }, locked = false, running = true },
		}
		local best = TaskForcePlan.match(TF, lobbies, 14, "hero", true, friendOf)
		check(
			best ~= nil and best.id == 2,
			"the fullest open squad of your side (locked and running skipped)"
		)
		table.insert(lobbies[2].members, 16)
		best = TaskForcePlan.match(TF, lobbies, 14, "hero", true, friendOf)
		check(best ~= nil and best.id == 5, "a full squad is skipped; a friend's locked squad is open to you")
		check(TaskForcePlan.match(TF, lobbies, 14, "hero", false, friendOf) == nil, "nothing before Act 1")
		check(
			TaskForcePlan.canRejoin(TF, 100, 279) and not TaskForcePlan.canRejoin(TF, 100, 281),
			"3 minutes"
		)
		check(not TaskForcePlan.canRejoin(TF, nil, 5), "only if you were in it")
		check(TaskForcePlan.nextLeader({ "a", "b", "c" }, "a") == "b", "the next member leads")
		check(TaskForcePlan.nextLeader({ "a" }, "a") == nil, "nobody left: the run ends")
		local w = TaskForcePlan.week(1700000000)
		check(TaskForcePlan.week(1700000000 + 7 * 86400) == w + 1, "a week apart")
		-- 2024-01-01 00:00 UTC was a Monday: the week turns over there
		check(
			TaskForcePlan.week(1704067200) == TaskForcePlan.week(1704067200 - 1) + 1,
			"weeks start on Monday"
		)
		check(TaskForcePlan.weeklyMult(TF, w - 1, w) == 2, "double Renown on the first clear each week")
		check(TaskForcePlan.weeklyMult(TF, w, w) == 1, "once a week")
		local P = require("../src/shared/ProfileSchema")
		check(#P.newCharacter().mmo.tfWeek == 4, "the week of each task force's last clear is saved")
		local loaded = P.load({ version = P.VERSION, characters = { { level = 3 } } })
		check(loaded.characters[1].mmo and #loaded.characters[1].mmo.tfWeek == 4, "old saves get it")
		local R = require("../src/shared/Remotes")
		check(
			R.TaskForceList.rate == 1 and R.TaskForceJoin.rate == 1 and R.TaskForceLook.rate == 1,
			"1 a second"
		)
		local ms = source("src/server/Services/MissionService.luau")
		check(
			string.find(ms, "TaskForcePlan.nextLeader(run.members, player)", 1, true) ~= nil,
			"leader hand-off"
		)
		check(
			string.find(ms, "PLACEHOLDER CONTENT: lore thread to fill", 1, true) ~= nil,
			"leg panels wait on lore"
		)
	end)

	---------------------------------------------------------------------------
	-- H5: Nemesis
	---------------------------------------------------------------------------
	local NemesisMath = require("../src/shared/NemesisMath")
	local NM = Config.Nemesis

	test("H5: the same nemesis from the same seed; names from fixed lists; a hunter for villains", function()
		local a = NemesisMath.make(NM, 123456, 1, "hero")
		local b = NemesisMath.make(NM, 123456, 1, "hero")
		check(
			a.seed == b.seed and a.name == b.name and a.build == b.build and a.signature == b.signature,
			"same every server"
		)
		check(
			a.colors == b.colors and a.head == b.head and a.cape == b.cape and a.pitch == b.pitch,
			"same look"
		)
		local c = NemesisMath.make(NM, 123457, 1, "hero")
		check(c.seed ~= a.seed, "another player, another nemesis")
		check(NemesisMath.make(NM, 123456, 2, "hero").seed ~= a.seed, "a new one each rank")
		local v = NemesisMath.make(NM, 123456, 1, "villain")
		check(
			string.sub(v.name, 1, #NM.hunterWord) == NM.hunterWord,
			"a villain's nemesis is a League hunter"
		)
		local names, sigs = {}, {}
		for uid = 1, 300 do
			local w = NemesisMath.make(NM, uid * 7919, 1, "hero")
			local first, second = string.match(w.name, "^(%S+) (%S+)$")
			check(
				first ~= nil and table.find(NM.first, first) ~= nil and table.find(NM.second, second) ~= nil,
				"two words from the lists"
			)
			check(first ~= second, "never the same word twice")
			names[w.name] = true
			sigs[w.signature] = true
			check(
				table.find(NM.builds, w.build) ~= nil
					and NM.colors[w.colors] ~= nil
					and table.find(NM.heads, w.head) ~= nil,
				"a look from the parts"
			)
			check(w.pitch >= NM.pitch[1] and w.pitch <= NM.pitch[2], "a voice pitch")
			local seen = {}
			for _, t in w.order do
				seen[t] = true
			end
			check(
				#w.order == 5 and seen[1] and seen[2] and seen[3] and seen[4] and seen[5],
				"every trait in its order"
			)
		end
		local n = 0
		for _ in names do
			n += 1
		end
		check(n > 150, "plenty of different names")
		for _, s in NM.signatureOrder do
			check(sigs[s] == true, s .. " shows up")
		end
		check(
			#NM.signatureOrder == 6 and #NM.builds == 4 and #NM.traits == 5,
			"6 signatures, 4 builds, 5 traits"
		)
		check(#NM.taunts + #NM.gloats + #NM.escapes == 40, "40 fixed lines")
		local line = NemesisMath.line(NM, "taunt", a.seed, 1, "Storm Falcon")
		check(
			string.find(line, "Storm Falcon", 1, true) ~= nil and string.find(line, "{hero}", 1, true) == nil,
			"filled with your hero name"
		)
	end)

	test("H5: spawn rules", function()
		local ok = {
			level = 8,
			session = 15 * 60,
			since = math.huge,
			now = 1000,
			readyAt = 0,
			intel = 0,
			inPocket = false,
			inSafehouse = false,
			inCrater = false,
			bossFight = false,
		}
		check(NemesisMath.canAppear(NM, ok), "level 8, 15 minutes in: it may show up")
		local function with(k: string, v: any): boolean
			local w = table.clone(ok)
			w[k] = v
			return (NemesisMath.canAppear(NM, w :: any))
		end
		check(not with("level", 7), "not below level 8")
		check(not with("session", 14 * 60), "not in the first 15 minutes of a session")
		check(not with("since", 29 * 60), "at most once per 30 minutes")
		check(with("since", 30 * 60), "after 30 minutes again")
		check(not with("inPocket", true), "never in a mission pocket")
		check(not with("inSafehouse", true), "never in a safehouse")
		check(not with("inCrater", true), "never in the Crater")
		check(not with("bossFight", true), "never during a world boss")
		check(not with("readyAt", 2000), "a new one waits a day after a Showdown")
		check(not with("intel", 3), "with 3 Intel it waits for the Showdown")
	end)

	test("H5: it grows to 5 traits, Intel opens the Showdown, rank up after a win", function()
		local who = NemesisMath.make(NM, 42, 1, "hero")
		local st = NemesisMath.fresh(NM, 42, "hero")
		check(st.seed == who.seed and st.rank == 1 and st.traits == 0 and st.intel == 0, "a fresh one")
		check(
			NemesisMath.escapes(NM, 1) and NemesisMath.escapes(NM, 3) and not NemesisMath.escapes(NM, 4),
			"escapes in encounters 1 to 3"
		)
		local t1 = NemesisMath.escaped(NM, who, st)
		check(
			t1 == who.order[1] and st.intel == 1 and NemesisMath.traitCount(st.traits) == 1,
			"an escape: a trait and an Intel"
		)
		check(not NemesisMath.showdownOpen(NM, st), "not yet")
		NemesisMath.grow(NM, who, st) -- it Downs you
		check(NemesisMath.traitCount(st.traits) == 2 and st.intel == 1, "a Down: a trait, no Intel")
		NemesisMath.escaped(NM, who, st)
		NemesisMath.escaped(NM, who, st)
		check(st.intel == 3 and NemesisMath.showdownOpen(NM, st), "3 Intel open the Showdown")
		NemesisMath.grow(NM, who, st)
		check(NemesisMath.traitCount(st.traits) == 5, "5 traits")
		check(
			NemesisMath.grow(NM, who, st) == nil and NemesisMath.traitCount(st.traits) == 5,
			"never more than 5"
		)
		NemesisMath.escaped(NM, who, st)
		check(st.intel == 3, "Intel stops at 3")
		local sigs = NemesisMath.signatures(NM, who, st.traits)
		check(
			#sigs == 2 and sigs[1] == who.signature and sigs[2] ~= sigs[1],
			"the Second Signature trait adds one"
		)
		check(#NemesisMath.signatures(NM, who, 0) == 1, "one signature at first")
		local nextOne = NemesisMath.afterWin(NM, st, 42, "hero", 5000)
		check(
			nextOne.rank == 2 and nextOne.traits == 0 and nextOne.intel == 0 and nextOne.met == 0,
			"one rank tougher, fresh"
		)
		check(
			nextOne.readyAt == 5000 + NM.rankUpWait
				and nextOne.seed == NemesisMath.make(NM, 42, 2, "hero").seed,
			"a day later, a new one"
		)
		local top = NemesisMath.afterWin(
			NM,
			{ seed = 1, rank = 5, traits = 0, met = 0, intel = 3, readyAt = 0 },
			42,
			"hero",
			0
		)
		check(top.rank == 5, "ranks go up to 5")
		near(NemesisMath.hpMult(NM, false, 1) * 600, 12 * 100, 1e-6, "12x a Spark Trooper solo")
		near(NemesisMath.hpMult(NM, true, 1) * 600, 18 * 100, 1e-6, "18x in a squad")
		check(
			Config.Enemies[NM.body].hp == 600 and Config.Enemies.SparkDrone.hp == 100,
			"the multipliers' base health"
		)
		check(NemesisMath.hpMult(NM, false, 3) > NemesisMath.hpMult(NM, false, 1), "tougher each rank")
		check(
			NM.payMult == 3 and NM.escapeAt == 0.3 and NM.weakMult == 2,
			"3x an incident, 30%, double on the weak point"
		)
	end)

	test("H5: signature areas, the Showdown and the saved record", function()
		local line = NemesisMath.areas(NM, "sniperLine", 0, 0, 0, -50, 1)[1]
		check(
			NemesisMath.inArea(line, 0, -40) and not NemesisMath.inArea(line, 0, 10),
			"a line toward the target, not behind"
		)
		check(not NemesisMath.inArea(line, 5, -40), "and narrow")
		local nova = NemesisMath.areas(NM, "groundSlam", 0, 0, 30, 0, 1)[1]
		check(NemesisMath.inArea(nova, 10, 0) and not NemesisMath.inArea(nova, 20, 0), "a slam around it")
		local cone = NemesisMath.areas(NM, "shieldWall", 0, 0, 0, -20, 1)[1]
		check(NemesisMath.inArea(cone, 0, -10) and not NemesisMath.inArea(cone, 0, 10), "a cone in front")
		local mines = NemesisMath.areas(NM, "mineField", 0, 0, 40, 40, 9)
		check(#mines == NM.signatures.mineField.count, "mines around the target")
		check(
			#NemesisMath.areas(NM, "mineField", 0, 0, 40, 40, 9) == #mines,
			"the same mines from the same seed"
		)
		check(NemesisMath.areas(NM, "droneSwarm", 0, 0, 30, 0, 1)[1].x == 30, "drones swarm the target")
		local P = require("../src/shared/ProfileSchema")
		local c = P.newCharacter()
		check(
			c.mmo.nemesis.seed == 0 and c.mmo.nemesis.rank == 1 and c.mmo.cores == 0 and c.mmo.heads == 0,
			"saved record"
		)
		local bad = P.load({
			version = P.VERSION,
			characters = { { mmo = { nemesis = { rank = 99, intel = -4 }, banes = { 1, "x" } } } },
		})
		local m = bad.characters[1].mmo
		check(m.nemesis.rank == 5 and m.nemesis.intel == 0 and #m.banes == 1, "bad saves are repaired")
		check(
			NM.showdown.num > Config.TaskForce.numBase + #Config.TaskForce.list,
			"a Showdown has its own mission number"
		)
		local src = source("src/server/Services/NemesisService.luau")
		check(
			string.find(src, "MissionService.enterCustom(players, m)", 1, true) ~= nil,
			"the Showdown is a pocket mission (sidekicking applies)"
		)
		check(
			string.find(src, "GearService.grantPiece(player, tier, own)", 1, true) ~= nil,
			"a Rare or better roll at your level"
		)
		check(string.find(src, "BlockService.robotMults", 1, true) ~= nil, "plates, cloak and the weak point")
		local R = require("../src/shared/Remotes")
		check(R.NemesisState.dir == "S2C" and R.NemesisShowdown.rate == 1, "remotes")
	end)

	test("H5: analytics events for task forces and the nemesis; a Studio command", function()
		local AS = require("../src/shared/AnalyticsSchema")
		for _, e in
			{
				"taskforce_open",
				"taskforce_start",
				"taskforce_done",
				"nemesis_met",
				"nemesis_showdown_start",
				"nemesis_showdown",
			}
		do
			check(AS.EVENTS[e] ~= nil and #AS.EVENTS[e] <= 3, "the schema has " .. e)
		end
		check(
			string.find(
				source("src/server/Services/DevService.luau"),
				"NemesisService.dev(player, what)",
				1,
				true
			) ~= nil,
			"Dev: nemesis 0/1"
		)
	end)
end
