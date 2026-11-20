-- Boss fights pass (2026-11-20, coordinator: the first world boss lands inside a new player's first 30 minutes, so
-- it has to be a highlight). Every one of the 6 world bosses on the real code paths:
-- * a new level 6 hero fighting beside four heroes at the boss's level (35): it takes part (a tier), spends little of
--   the fight Downed (BossMath.newHeroHit caps one boss hit on a hero far below it), and there is never a quiet
--   stretch (the longest gap between warnings and strikes);
-- * every attack shape has its telegraph, every boss its name card title and news portrait;
-- * hits read on the boss (a pale flash, chunks breaking off every few % of its hp) and a phase hits the arena.
-- Called from tests/run.luau. ONLY="Boss fights" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local BossSim = require("../src/shared/BossSim")
	local BossMath = require("../src/shared/BossMath")
	local Formulas = require("../src/shared/Formulas")
	local Rng = require("../src/shared/Rng")
	local B = Config.Boss

	local function has(path: string, needle: string): boolean
		return string.find(fs.readFile(path), needle, 1, true) ~= nil
	end

	test("Boss fights: a new hero's boss hits are capped, everyone else's are not", function()
		local N = B.newHero
		check(N ~= nil and N.gap > 0 and N.maxHit > 0 and N.maxHit < 1, "newHero is tuned")
		local hp = Formulas.health(Config, 6, 0, Config.Classes.default)
		check(
			BossMath.newHeroHit(Config, 400, 6, 35, hp) == hp * N.maxHit,
			"a level 6 hero by a level 35 boss"
		)
		check(BossMath.newHeroHit(Config, 50, 6, 35, hp) == 50, "a small hit stays as it is")
		check(
			BossMath.newHeroHit(Config, 400, 30, 35, hp) == 400,
			"a hero near the boss's level takes it all"
		)
		check(
			BossMath.newHeroHit(Config, 400, 35 - N.gap, 35, hp) == hp * N.maxHit,
			"from `gap` levels below"
		)
		local src = fs.readFile("src/server/Services/BossService.luau")
		local n = 0
		for _ in string.gmatch(src, "HeroService%.damage%(hero, newHeroHit%(f, hero, hit%[2%]%)") do
			n += 1
		end
		check(n == 2, "strikes and lingering zones both go through it (" .. n .. ")")
	end)

	-- one fight: four heroes at the boss's level (two on the ground by its legs, two flying high and far) and a new
	-- level 6 hero on the ground; half the warnings dodged 70 studs, a hero at 0 HP down for 20 s
	local function fight(id: string, bossLevel: number, newLevel: number): { [string]: any }
		local def = B.bosses[id]
		local maxHp = BossMath.maxHp(Config, 5, bossLevel, 0)
		local sim = BossSim.new(Config, id, 0, 0, 0, maxHp, bossLevel, 0, Rng.new(19))
		local rng = Rng.new(7)
		BossSim.step(sim, 6, {})
		local heroes, st = {}, {}
		for i = 1, 5 do
			local lvl = if i == 5 then newLevel else bossLevel
			local a = (i - 1) / 5 * math.pi * 2 + 0.4
			local r = if i % 2 == 0 then 120 else 20
			local y = if i % 2 == 0 then def.height + 20 else 0
			heroes[i] = { id = i, x = math.cos(a) * r, y = y, z = math.sin(a) * r, alive = true }
			local hpMax = Formulas.health(Config, lvl, 0, Config.Classes.default)
			st[i] = {
				ax = math.cos(a) * r,
				az = math.sin(a) * r,
				ay = y,
				hp = hpMax,
				hpMax = hpMax,
				downUntil = 0,
				downT = 0,
				lvl = lvl,
				dps = Config.Stats.power.base + Config.Stats.power.perLevel * lvl,
				dealt = 0,
				worst = 0,
			}
		end
		local bodyKey
		for _, tg in def.targets do
			if not tg.weak and not bodyKey then
				bodyKey = tg.id
			end
		end
		local t, dt = 6, 0.1
		local lastAct, gap = 6, 0
		while t < sim.endsAt and sim.state == "fight" do
			t += dt
			for i, h in heroes do
				local s = st[i]
				h.alive = t >= s.downUntil
				if not h.alive then
					s.downT += dt
					continue
				end
				if s.hp <= 0 then
					s.hp = s.hpMax
				end
				local dx, dz = 0, 0
				if s.dodge and t < s.dodge.untilT then
					dx, dz = s.dodge.x, s.dodge.z
				end
				local ax, az = s.ax, s.az
				if s.ay == 0 then
					ax, az = sim.x + s.ax, sim.z + s.az
				end
				h.x, h.y, h.z = ax + dx, s.ay, az + dz
			end
			BossSim.step(sim, t, heroes)
			for _, ev in BossSim.drain(sim) do
				if ev.k == "warn" or ev.k == "strike" then
					gap = math.max(gap, t - lastAct)
					lastAct = t
				end
				if ev.k == "warn" then
					for i, h in heroes do
						if h.alive and rng:chance(0.5) then
							local ux, uz = h.x - ev.x, h.z - ev.z
							if
								ev.shape == "homing"
								or ev.shape == "tether"
								or ev.shape == "circles"
								or ev.shape == "lines"
							then
								ux, uz = -(h.z - sim.z), h.x - sim.x
							end
							local l = math.sqrt(ux * ux + uz * uz)
							if l < 1e-3 then
								ux, uz, l = 1, 0, 1
							end
							st[i].dodge = { x = ux / l * 70, z = uz / l * 70, untilT = t + ev.t + 0.3 }
						end
					end
				elseif ev.k == "strike" or ev.k == "tick" then
					for _, hit in ev.hits or {} do
						local s = st[hit[1]]
						local amt = BossMath.newHeroHit(Config, hit[2], s.lvl, bossLevel, s.hpMax)
						s.hp -= amt
						s.worst = math.max(s.worst, amt / s.hpMax)
						if s.hp <= 0 then
							s.downUntil = t + 20
						end
					end
				end
			end
			for i, h in heroes do
				if h.alive then
					local key = bodyKey
					for _, ob in sim.objectives do
						if ob.alive then
							key = "obj" .. ob.idx
							break
						end
					end
					local d, o = BossSim.damage(sim, key, st[i].dps * dt)
					st[i].dealt += d + o
				end
			end
		end
		local ledger = {}
		for i, s in st do
			ledger[i] = { damage = s.dealt, support = 0, objectives = 0 }
		end
		local tiers = BossMath.tiers(Config, BossMath.scores(Config, ledger))
		local secs = t - 6
		return {
			won = sim.state == "dead",
			secs = secs,
			gap = gap,
			down = st[5].downT / secs,
			worst = st[5].worst,
			dealt = st[5].dealt / sim.maxHp,
			tier = tiers[5],
		}
	end

	test(
		"Boss fights: a level 6 hero's first boss: it takes part, keeps fighting and is never idle",
		function()
			for _, id in B.order do
				local r = fight(id, 35, 6)
				print(
					string.format(
						"  [Boss fights] %-16s %s in %3.0f s, longest quiet %.1f s | level 6 hero: %2.0f%% of it Downed, worst hit %2.0f%% HP, %4.1f%% of the damage, %s",
						id,
						if r.won then "won" else "LOST",
						r.secs,
						r.gap,
						r.down * 100,
						r.worst * 100,
						r.dealt * 100,
						tostring(r.tier)
					)
				)
				check(r.won, id .. ": the party wins")
				check(
					BossMath.tookPart(r.tier),
					id .. ": the new hero takes part (" .. tostring(r.tier) .. ")"
				)
				check(
					r.down <= 0.25,
					string.format("%s: the new hero is Downed %.0f%% of the fight", id, r.down * 100)
				)
				check(r.worst <= B.newHero.maxHit + 1e-6, id .. ": no hit takes more than newHero.maxHit")
				check(
					r.gap <= 6,
					string.format("%s: never more than 6 s without a warning or a strike (%.1f)", id, r.gap)
				)
			end
		end
	)

	test("Boss fights: every boss's entrance card, every attack's telegraph, hits and phases read", function()
		local tele = fs.readFile("src/client/Fx/BossTelegraph.luau")
		local titles = Config.Cinema.nameCard.titles
		for _, id in B.order do
			local def = B.bosses[id]
			check(titles[id] ~= nil and titles[id] ~= "", id .. " has a name card title")
			check(Config.NewsArt.cards.at[id] ~= nil, id .. " has its name card portrait")
			for _, a in def.attacks do
				local shape = a.shape
				check(
					string.find(tele, 'shape == "' .. shape .. '"', 1, true) ~= nil,
					id .. " " .. a.id .. ": its " .. shape .. " has a telegraph"
				)
			end
		end
		local wfx = "src/client/Fx/WorldFx.luau"
		check(has(wfx, "hitFeedback(sh, s.hp, s.max)"), "hp lost on the boss shows on it")
		check(has(wfx, "DebrisBudget.lease(want, FB.life)"), "its chunks break off inside the debris budget")
		check(has(wfx, "CombatFx.reduceFlashing or FxLib.reduceFlashing"), "the flash obeys Reduce flashing")
		check(has(wfx, "Vector3.new(feet.X, gy + 0.6, feet.Z),"), "a phase sends a shockwave over the arena")
		local FB = Config.Fx.boss
		check(FB.chunkEvery > 0 and FB.chunkEvery <= 0.1, "chunks every few % of its hp")
		for _, q in Config.Presets.order do
			check((FB.chunks[q] or 0) > 0 and FB.chunks[q] <= 6, q .. " chunks a break")
		end
		check(
			has("src/client/Fx/FinisherFx.luau", '"bossDead" else "bossPhase"'),
			"the phase and the kill slow time"
		)
	end)
end
