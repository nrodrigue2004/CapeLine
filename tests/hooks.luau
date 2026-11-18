-- WP4 and WP5 (gap check 2026-11-18): the MMO funnel steps, the favorite prompt, the REMATCH ping and the
-- Suspicious Hero incident. Run by tests/run.luau (ONLY=WP4 or ONLY=WP5 runs one package).

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")

	local function source(path: string): string
		return fs.readFile(path)
	end
	local function has(text: string, needle: string): boolean
		return string.find(text, needle, 1, true) ~= nil
	end

	local AnalyticsSchema = require("../src/shared/AnalyticsSchema")
	local FunnelDef = require("../src/shared/FunnelDef")
	local ProfileSchema = require("../src/shared/ProfileSchema")
	local NetSchema = require("../src/shared/NetSchema")
	local Remotes = require("../src/shared/Remotes")
	local RematchRules = require("../src/shared/RematchRules")

	---------------------------------------------------------------------------
	-- WP4 (a): the Hero MMO firsts (gap G6)
	---------------------------------------------------------------------------

	local MMO_STEPS =
		{ "first_block", "first_throw", "first_nemesis", "first_taskforce", "first_badge", "pass_bought" }

	test("WP4: the MMO funnel has the spec's six firsts, as a lifetime funnel", function()
		local F = AnalyticsSchema.FUNNELS.MMO
		check(F ~= nil and #F == #MMO_STEPS, "six steps")
		for i, step in MMO_STEPS do
			check(F[i] == step and AnalyticsSchema.stepOf("MMO", step) == i, step .. " is step " .. i)
			check(string.match(step, "^[a-z0-9_]+$") ~= nil, step .. " is dashboard-safe")
		end
		check(FunnelDef.lifetime.MMO == true, "FunnelDef lists it as a lifetime funnel")
		local n = 0
		for _ in AnalyticsSchema.FUNNELS do
			n += 1
		end
		-- Roblox allows 10 funnels: these 6, Progress and Returns (FunnelKit) and the onboarding funnel
		check(n + 2 <= 10, "inside Roblox's funnel limit (" .. n + 2 .. ")")
	end)

	test("WP4: each first fires once per account, in any order", function()
		local mask = 0
		local seen = {}
		for _, step in { "first_badge", "first_block", "pass_bought", "first_throw", "first_nemesis" } do
			local i, m = AnalyticsSchema.first(mask, "MMO", step)
			check(i == AnalyticsSchema.stepOf("MMO", step), step .. " fires the first time")
			check(m ~= mask, step .. " sets its bit")
			mask = m
			seen[step] = true
		end
		for step in seen do
			local i, m = AnalyticsSchema.first(mask, "MMO", step)
			check(i == nil and m == mask, step .. " never fires twice")
		end
		local i = AnalyticsSchema.first(mask, "MMO", "first_taskforce")
		check(i == 4, "the one left still fires")
		check((AnalyticsSchema.first(0, "MMO", "made_up")) == nil, "an unknown step never fires")
		check((AnalyticsSchema.first(0, "Nope", "first_block")) == nil, "an unknown funnel never fires")
		-- the save: no new version, repair fills and clamps the bits
		local p = ProfileSchema.default()
		check(p.analytics.mmo == 0 and p.analytics.fav == 0, "a new account has none")
		local old = ProfileSchema.default()
		old.analytics = { onboard = 3, firstSeen = 10, d1 = 1 }
		local loaded = ProfileSchema.load(old)
		check(loaded.analytics.mmo == 0 and loaded.analytics.fav == 0, "an older save gets them")
		check(loaded.analytics.onboard == 3, "and keeps its onboarding step")
		old = ProfileSchema.default()
		old.analytics.mmo = 2 ^ 40
		old.analytics.fav = "yes"
		loaded = ProfileSchema.load(old)
		check(loaded.analytics.mmo == 2 ^ 16 - 1 and loaded.analytics.fav == 0, "bad values are repaired")
		check(ProfileSchema.clientView(ProfileSchema.default()).analytics == nil, "never in the client view")
	end)

	test("WP4: the firsts stay inside the per-minute analytics budget", function()
		local B = Config.Analytics.budget
		local b = AnalyticsSchema.newBudget()
		local cap = B.base + B.perPlayer * 2
		local sent = 0
		for _ = 1, cap + 25 do
			if AnalyticsSchema.take(b, B, 100, 2, false) then
				sent += 1
			end
		end
		check(sent == cap, "a minute holds base + perPlayer x players (" .. sent .. ")")
		check(b.dropped == 25, "the rest are dropped and counted")
		check(AnalyticsSchema.take(b, B, 160, 2, false), "a new minute has room again")
		local low = AnalyticsSchema.newBudget()
		local lowSent = 0
		for _ = 1, cap do
			if AnalyticsSchema.take(low, B, 0, 2, true) then
				lowSent += 1
			end
		end
		check(lowSent == math.ceil(cap * B.lowShare), "busy events stop at their share first")
		check(AnalyticsSchema.take(low, B, 1, 2, false), "a first still gets a slot after busy events stop")
		-- the server: a first takes a budget slot like any event, saves its bit only once sent, and waits
		local an = source("src/server/Services/Analytics.luau")
		local fn = string.match(an, "function Analytics%.first(.-)\nend") or ""
		check(has(fn, "takeBudget(false)"), "Analytics.first takes a budget slot")
		check(
			(string.find(fn, "takeBudget", 1, true) or 0)
				< (string.find(fn, "analytics.mmo = mask", 1, true) or 0),
			"the bit is saved only after the slot was taken"
		)
		check(has(fn, "FunnelKit.LIFE_SESSION"), "on the lifetime session id, like Progress")
		check(has(an, "AnalyticsSchema.take(budget"), "one budget rule for every event (Shared, tested)")
		local hooks = source("src/server/Services/AnalyticsHooks.luau")
		check(has(hooks, "retryFirsts()"), "a refused first is tried again with the funnel checks")
	end)

	test("WP4: every first is wired to its game signal", function()
		local hooks = source("src/server/Services/AnalyticsHooks.luau")
		local wires = {
			first_block = "BlockService.Outcome:Connect",
			first_throw = "ThrowService.Thrown:Connect",
			first_nemesis = "NemesisService.Met:Connect",
			first_taskforce = "TaskForceService.Done:Connect",
			first_badge = "BadgeService.Earned:Connect",
			pass_bought = "PurchaseService.Landed:Connect",
		}
		for step, signal in wires do
			local at = string.find(hooks, signal, 1, true)
			local stepAt = string.find(hooks, '"' .. step .. '"', 1, true)
			check(at ~= nil and stepAt ~= nil and stepAt > at, step .. " fires from " .. signal)
		end
		check(has(hooks, 'outcome == "blocked" or outcome == "perfect"'), "a block that stopped a hit")
		check(has(hooks, 'kind == "heroPass"'), "pass_bought is the Hero Pass")
		local ps = source("src/server/Services/PurchaseService.luau")
		check(has(ps, "PurchaseService.Landed:Fire(player, got.key, got.kind)"), "a purchase that landed")
	end)

	---------------------------------------------------------------------------
	-- WP4 (b): the favorite prompt (gap G7)
	---------------------------------------------------------------------------

	test("WP4: the favorite prompt: Roblox's API, once per account, after a boss win, no reward", function()
		local client = source("src/client/Controllers/FavoritePrompt.luau")
		check(
			has(client, "PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)"),
			"AvatarEditorService:PromptSetFavorite on the place (an asset)"
		)
		local call = string.match(client, "pcall%(function%(%)(.-)end%)") or ""
		check(has(call, "PromptSetFavorite"), "inside a pcall")
		check(
			(string.find(client, 'Net.send("FavoriteShown")', 1, true) or 1e9)
				< (string.find(client, "PromptSetFavorite(game", 1, true) or 0),
			"the flag is saved before the prompt opens"
		)
		local server = source("src/server/Services/FavoriteService.luau")
		check(
			has(server, "BossService.Rewarded:Connect(won)") and has(server, "if defeated"),
			"after a boss win"
		)
		check(has(server, "profile.analytics.fav == 0"), "only an account never shown it")
		check(
			has(server, "profile.analytics.fav = 1") and has(server, "DataService.saveSoon"),
			"the flag is saved"
		)
		for _, pay in { "addCredits", "addRenown", "grant", "Bits.set", "Earned" } do
			check(not has(server, pay) and not has(client, pay), "no reward: no " .. pay)
		end
		check(Remotes.FavoriteAsk.dir == "S2C", "FavoriteAsk to the device")
		local shown = Remotes.FavoriteShown
		check(shown.dir == "C2S" and #shown.schema == 0 and shown.rate <= 0.1, "FavoriteShown: no args, rare")
		local boot = source("src/server/init.server.luau")
		check(has(boot, 'boot("FavoriteService", FavoriteService.init)'), "the server boots it")
		check(has(source("src/client/init.client.luau"), "FavoritePrompt.init()"), "the device starts it")
		local F = Config.Analytics.favorite
		check(F.wait >= 5 and F.calm >= 3 and F.giveUp >= 60, "it waits for a quiet moment")
	end)

	---------------------------------------------------------------------------
	-- WP4 (c): the REMATCH ping (gap G8)
	---------------------------------------------------------------------------

	local R = Config.Pvp.rematch

	test("WP4: rematch: a defeat gives one ping; ACCEPT needs both flagged", function()
		local st = RematchRules.new()
		local yes = { flagged = true, here = true }
		check(select(2, RematchRules.ask(R, st, 1, 0, yes)) == "none", "no defeat, no ping")
		RematchRules.defeat(R, st, 1, 2, 0)
		local w, why = RematchRules.ask(R, st, 1, 1, { flagged = false, here = true })
		check(w == nil and why == "flag", "the loser must be flagged")
		w, why = RematchRules.ask(R, st, 1, 2, yes)
		check(w == 2 and why == nil, "the ping goes to the winner")
		check(select(2, RematchRules.ask(R, st, 1, 3, yes)) == "none", "one ping per defeat")
		local ok, r = RematchRules.accept(R, st, 2, 1, 3, false)
		check(not ok and r == "flag", "ACCEPT needs both flagged")
		ok, r = RematchRules.accept(R, st, 2, 1, 4, true)
		check(ok and r == nil, "both flagged: a rematch")
		check(select(2, RematchRules.accept(R, st, 2, 1, 5, true)) == "late", "an answered ping is gone")
		-- the pair gap: a second defeat soon after cannot ping again yet
		RematchRules.defeat(R, st, 1, 2, 10)
		check(select(2, RematchRules.ask(R, st, 1, 11, yes)) == "wait", "one ping per pair per gap")
		w = RematchRules.ask(R, st, 1, 2 + R.pairGap, { flagged = true, here = true })
		check(w == nil, "the second defeat's offer ran out before the gap")
		RematchRules.defeat(R, st, 1, 2, 2 + R.pairGap)
		check(RematchRules.ask(R, st, 1, 3 + R.pairGap, yes) == 2, "after the gap it may ping again")
		check(
			select(2, RematchRules.accept(R, st, 2, 1, 4 + R.pairGap + R.answer, true)) == "late",
			"ran out"
		)
	end)

	test("WP4: rematch: offers run out, a gone winner, NO and leaving", function()
		local st = RematchRules.new()
		RematchRules.defeat(R, st, 5, 6, 0)
		check(
			select(2, RematchRules.ask(R, st, 5, R.offer + 1, { flagged = true, here = true })) == "none",
			"late"
		)
		RematchRules.defeat(R, st, 5, 6, 100)
		check(select(2, RematchRules.ask(R, st, 5, 101, { flagged = true, here = false })) == "gone", "gone")
		RematchRules.defeat(R, st, 7, 8, 200)
		check(RematchRules.ask(R, st, 7, 201, { flagged = true, here = true }) == 8, "pinged")
		RematchRules.decline(st, 8, 7)
		check(select(2, RematchRules.accept(R, st, 8, 7, 202, true)) == "late", "NO ends it")
		RematchRules.defeat(R, st, 9, 10, 300)
		RematchRules.forget(R, st, 10, 301)
		check(st.offers[9] == nil, "a winner who left takes the offer along")
		RematchRules.defeat(R, st, 9, 9, 302)
		check(st.offers[9] == nil, "never a ping at yourself")
		check(R.offer >= 30 and R.answer >= 10 and R.pairGap >= 60, "the timings")
	end)

	test("WP4: rematch: one rate-limited remote of fixed buttons, no free text", function()
		local r = Remotes.PvpRematch
		check(r.dir == "C2S" and r.rate ~= nil and r.rate <= 1 and r.burst <= 3, "rate-limited")
		check(NetSchema.validate(r.schema, { 1 }, 1), "REMATCH")
		check(NetSchema.validate(r.schema, { 2, 12345 }, 2), "ACCEPT a user")
		check(NetSchema.validate(r.schema, { 3, 12345 }, 2), "NO")
		check(not NetSchema.validate(r.schema, { 4 }, 1), "no other act")
		check(not NetSchema.validate(r.schema, { "gg ez" }, 1), "no text")
		check(not NetSchema.validate(r.schema, { 2, "x" }, 2), "no text as the user")
		check(not NetSchema.validate(r.schema, { 1, 1, 1 }, 3), "no extra arguments")
		check(Remotes.RematchAsk.dir == "S2C", "the winner's card")
		local flag = source("src/server/Services/FlagService.luau")
		check(has(flag, 'Net.on("PvpRematch", onRematch)'), "FlagService answers it")
		check(
			has(flag, "DeathService.PvpDefeat:Connect(FlagService.rematchOffer)"),
			"offered on a PvP defeat"
		)
		check(has(flag, "table.find(profile.mutes, player.UserId)"), "a muted loser is never heard")
		check(
			not has(flag, "SafehouseService.place(winner") and not has(flag, "TeleportService"),
			"no teleport"
		)
		local hud = source("src/client/Ui/PvpHud.luau")
		check(has(hud, '"REMATCH"') and has(hud, '" WANTS A REMATCH"'), "fixed button and card text")
		check(has(hud, '"ACCEPT"') and has(hud, '"NO"'), "fixed answers")
		local toasts = source("src/client/Ui/Toasts.luau")
		for _, id in { "rematchSent", "rematchOn", "rematchRefused" } do
			check(has(toasts, 'id == "' .. id .. '"'), id .. " has a fixed line")
		end
	end)

	---------------------------------------------------------------------------
	-- WP5: the Suspicious Hero incident (gap G13)
	---------------------------------------------------------------------------

	local IncidentPlan = require("../src/shared/IncidentPlan")
	local FakeRules = require("../src/shared/FakeRules")
	local NewsPlan = require("../src/shared/NewsPlan")
	local Rng = require("../src/shared/Rng")
	local IC = Config.Incidents
	local SH = IC.templates.SuspiciousHero

	test("WP5: the Suspicious Hero: both sides, a crowd, an unmask, then each side's goal", function()
		check(SH ~= nil and table.find(IC.order, "SuspiciousHero") ~= nil, "in the rotation")
		check(
			SH.side == "both" and SH.where == "street" and SH.villainName ~= nil,
			"both sides, in the street"
		)
		check(SH.time >= 30 and SH.time <= 120, "30 s to 2 min")
		check(table.find(IncidentPlan.KINDS, "unmask") ~= nil and IC.kinds.unmask ~= nil, "a step kind")
		local hero = IncidentPlan.rows(SH, "hero")
		local villain = IncidentPlan.rows(SH, "villain")
		check(
			#hero == 2 and hero[1].kind == "unmask" and hero[2].kind == "defeat" and hero[2].keep,
			"Vigil: scrap it"
		)
		check(
			#villain == 2 and villain[1].kind == "unmask" and villain[2].kind == "hold" and villain[2].panic,
			"Syndicate: hold the square while the panic spreads"
		)
		check(hero[1].crowd >= 4 and hero[1].hpMult < 1, "a crowd to search, a street-sized fake")
		-- the plan per side
		local rng = Rng.new(5)
		local h = IncidentPlan.new(IC, rng, "SuspiciousHero", 20, 0, { config = Config, side = "hero" })
		check(#h.steps == 2 and h.steps[1].need == 1 and h.steps[2].need == 1, "Vigil: two steps")
		check(IncidentPlan.advance(h, "defeat", 1) == nil, "beating it before the crack is not the goal")
		check(IncidentPlan.advance(h, "unmask", 1) == "step", "the crack ends step 1")
		check(IncidentPlan.advance(h, "defeat", 1) == "done", "scrapped: done")
		local v = IncidentPlan.new(IC, rng, "SuspiciousHero", 20, 0, { config = Config, side = "villain" })
		check(#v.steps == 2 and v.steps[2].kind == "hold" and v.steps[2].need == 8, "Syndicate: hold 8 s")
		check(IncidentPlan.advance(v, "unmask", 1) == "step", "the crack ends step 1")
		check(IncidentPlan.advance(v, "hold", 8) == "done", "held: done")
		-- the tracker lines are each side's own, in order
		check(IncidentPlan.stepText(IC, "SuspiciousHero", 2, "hero") == hero[2].text, "Vigil's line 2")
		check(
			IncidentPlan.stepText(IC, "SuspiciousHero", 2, "villain") == villain[2].villainText,
			"Syndicate's"
		)
		local hn, ht = IncidentPlan.title(IC, "SuspiciousHero", "hero")
		local vn, vt = IncidentPlan.title(IC, "SuspiciousHero", "villain")
		check(hn ~= vn and ht ~= vt, "each side has its own banner")
		-- a template without side rows is unchanged
		check(
			#IncidentPlan.rows(IC.templates.VaultBreach, "villain") == 2,
			"other templates keep their steps"
		)
		-- Heroic still works: robots up, more time
		local heroic = IncidentPlan.new(IC, rng, "SuspiciousHero", 45, 0, { config = Config, heroic = true })
		check(heroic.heroic and heroic.deadline > SH.time, "it can roll Heroic")
	end)

	test("WP5: the fakes are generic costumes over a fake's suit, never the famous three", function()
		local unmask = IncidentPlan.rows(SH, "hero")[1]
		local famousNames = {}
		for _, kind in { "Radiant", "Bulwark", "Skylance", "HeadmasterHalo" } do
			famousNames[string.upper(Config.Enemies[kind].name)] = true
		end
		check(#unmask.dress >= 2, "more than one costume")
		for _, id in unmask.dress do
			local d = IC.dress[id]
			check(d ~= nil, id .. " is a costume")
			check(Config.SideQuests.dress[id] == nil, id .. " does not repeat a side quest dress id")
			local suit = Config.Enemies[d.suit]
			check(
				suit and suit.fake and not suit.fake.costumed and not suit.twin,
				id .. " goes over a fake's suit (its face cracks)"
			)
			local ident = FakeRules.dress(Config, id) :: any
			check(
				ident ~= nil and ident.famous == true and ident.dress == true,
				id .. " builds (valid pieces)"
			)
			check(not famousNames[string.upper(d.name)], id .. " is not a famous fake")
			check(#d.name <= 20 and #d.title <= 24, id .. " name and title are short")
			local plate = FakeRules.plate(Config, d.suit, false, ident)
			check(
				plate.name == string.upper(d.name) and not plate.red,
				id .. " reads like a hero until cracked"
			)
			plate = FakeRules.plate(Config, d.suit, true, ident)
			check(plate.name == Config.Enemies.fakes.word and plate.red, id .. " reads FAKE once cracked")
		end
		check(
			FakeRules.cracked(Config, 0.5) and not FakeRules.cracked(Config, 0.51),
			"the existing 50% crack"
		)
		-- costumes whose suit is off are skipped; all off and the incident is skipped
		local function off(kinds: { string }): any
			local c = table.clone(Config)
			c.Enemies = table.clone(Config.Enemies)
			for _, k in kinds do
				c.Enemies[k] = table.clone(Config.Enemies[k])
				c.Enemies[k].on = false
			end
			return c
		end
		local some = IncidentPlan.dresses(off({ "Radiant" }), unmask, 20)
		check(#some == #unmask.dress - 1 and not table.find(some, "Gleam"), "a switched-off suit is skipped")
		local none = off({ "Radiant", "Bulwark", "Skylance" })
		check(not IncidentPlan.available(IC, none, "SuspiciousHero", 20), "no suit on: no Suspicious Hero")
		check(IncidentPlan.available(IC, Config, "SuspiciousHero", 20), "on at level 20")
		check(
			not IncidentPlan.available(IC, Config, "SuspiciousHero", SH.minLevel - 1),
			"not before its level"
		)
	end)

	test("WP5: the news and the badge count it; the beats are fixed lines", function()
		for _, kind in { "fakeVigil", "fakeSyndicate" } do
			local code = NewsPlan.CODE[kind]
			check(code ~= nil and code > NewsPlan.CODE.sideDraw, kind .. " is added at the end (codes kept)")
			local line = NewsPlan.text(Config, { k = code, a = 0 }, "Bolt Kid")
			check(line ~= nil and has(line, "BOLT KID"), kind .. " names the hero")
			check(not NewsPlan.flash(Config, { k = code }), kind .. " is ticker news, not a flash")
			check(not has(string.upper(line or ""), "CRANE"), kind .. " stays generic")
		end
		check(NewsPlan.CODE.sideDraw == 16, "older codes unchanged")
		local news = source("src/server/Services/NewsService.luau")
		check(has(news, "IncidentService.FakeUnmasked:Connect"), "NewsService posts it")
		check(has(news, '"fakeSyndicate" else "fakeVigil"'), "with the side's own line")
		local badge
		for _, g in Config.Badges.groups do
			for _, b in g.badges do
				if b.key == "fakes" then
					badge = b
				end
			end
		end
		check(badge ~= nil and badge.n >= 1, "a badge counts unmasked fakes")
		check(has(source("src/server/Services/BadgeService.luau"), '"fakes"'), "BadgeService bumps it")
		for _, key in { "fakeCracked", "fakeScrapped", "panicSpread" } do
			local b = IC.beats[key]
			check(
				b ~= nil and Config.Audio.sounds[b.juice] ~= nil and b.text ~= "",
				key .. " has a sound and a line"
			)
		end
		local all = SH.text .. SH.villainText .. SH.name .. SH.villainName
		for _, row in SH.steps do
			all ..= (row.text or "") .. (row.villainText or "")
		end
		for _, banned in { "Crane", "Null", "Halcyon", "Vale", "Radiant", "Bulwark", "Skylance" } do
			check(not has(all, banned), "no story names in the incident's text: " .. banned)
		end
	end)

	test("WP5: IncidentService runs it in its own functions", function()
		local svc = source("src/server/Services/IncidentService.luau")
		for _, hook in
			{
				"startFake(inc, step, here)",
				"stepFake(inc, now)",
				"panicWave(inc, step, now)",
				"fakeFell(inc, step, by, pos)",
				"fakeHit(inc, enemyId, heroId)",
			}
		do
			check(has(svc, hook), "wired: " .. hook)
		end
		check(
			has(svc, "EnemyService.spawnAt(IC.dress[dressId].suit, at, robotLevel(inc), inc.id, true)"),
			"poses"
		)
		check(has(svc, "e.scripted = false"), "a hit wakes it")
		check(has(svc, "if not EnemyService.dress(id, dressId) then"), "always dressed")
		check(has(svc, "EnemyService.remove(id)"), "an undressed suit never stays out")
		check(has(svc, "e.unmasked"), "the existing crack ends the unmask step")
		check(has(svc, "IncidentService.FakeUnmasked:Fire(inc, f.by)"), "the signal for the news and badge")
		check(has(svc, "side = hero.side"), "each side gets its own steps")
	end)
end
