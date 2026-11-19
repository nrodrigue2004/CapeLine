-- pt-ui (nate's playtest 2026-11-19): the popup line (Shared.PopupQueue, Ui.Popups), every card closes, the
-- costume contest's skipped card, and every building part the city builds wears a textured kit material.
-- Called from tests/run.luau:
--   require("./pt_ui_test")({ test = test, check = check, Config = Config, world = world, placePath = placePath })
-- ONLY="pt-ui" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local PopupQueue = require("../src/shared/PopupQueue")
	local ContestRules = require("../src/shared/ContestRules")
	local PocketLayout = require("../src/shared/PocketLayout")
	local PocketDress = require("../src/shared/PocketDress")
	local P = Config.Ui.popups

	local function ctx(o: { [string]: any }?): PopupQueue.Ctx
		local c = { fighting = false, calmFor = 999, blocked = false, freeFor = 999, phone = false }
		for k, v in o or {} do
			(c :: any)[k] = v
		end
		return c
	end
	local function shown(q: PopupQueue.Queue, kind: string): number
		local n = 0
		for _, s in q.showing do
			if s.kind == kind then
				n += 1
			end
		end
		return n
	end

	test("pt-ui: at most 1 card and 2 toasts at once (1 toast on a phone, none over a card there)", function()
		local q = PopupQueue.new(P)
		for i = 1, 3 do
			PopupQueue.push(q, { kind = "card", name = "c" .. i, pri = 50, life = 5 }, 0)
		end
		for _ = 1, 5 do
			PopupQueue.push(q, { kind = "toast", pri = 70, life = 3 }, 0)
		end
		PopupQueue.step(q, 0, ctx())
		check(shown(q, "card") == P.maxCards and P.maxCards == 1, "one card")
		check(shown(q, "toast") == P.maxToasts and P.maxToasts == 2, "two toasts")
		local ph = PopupQueue.new(P)
		for _ = 1, 3 do
			PopupQueue.push(ph, { kind = "toast", pri = 70, life = 3 }, 0)
		end
		PopupQueue.step(ph, 0, ctx({ phone = true }))
		check(shown(ph, "toast") == 1 and P.phoneToasts == 1, "one toast on a phone")
		local pc = PopupQueue.new(P)
		PopupQueue.push(pc, { kind = "card", name = "r", pri = 70, life = 5 }, 0)
		PopupQueue.push(pc, { kind = "toast", pri = 90, urgent = true, life = 3 }, 0)
		PopupQueue.step(pc, 0, ctx({ phone = true }))
		check(shown(pc, "card") == 1 and shown(pc, "toast") == 0, "a phone shows no toast over a card")
		PopupQueue.step(pc, 5, ctx({ phone = true }))
		check(shown(pc, "card") == 0 and shown(pc, "toast") == 1, "the toast comes when the card goes")
	end)

	test(
		"pt-ui: priority first, bursts merge into +N more, rewards add up, nothing important is dropped",
		function()
			local q = PopupQueue.new(P)
			PopupQueue.push(q, { kind = "toast", pri = P.pri.minor, life = 3 }, 0)
			PopupQueue.push(q, { kind = "toast", pri = P.pri.minor, life = 3 }, 0)
			PopupQueue.step(q, 0, ctx())
			local big = PopupQueue.push(q, { kind = "toast", pri = P.pri.result, life = 3 }, 0.1)
			local sum = function(a: any, b: any): any
				return { n = a.n + b.n }
			end
			local r1 = PopupQueue.push(
				q,
				{ kind = "toast", pri = P.pri.minor, group = "reward", data = { n = 1 }, merge = sum },
				0.1
			)
			local r2, merged = PopupQueue.push(
				q,
				{ kind = "toast", pri = P.pri.minor, group = "reward", data = { n = 2 }, merge = sum },
				0.2
			)
			check(
				merged and r1 == r2 and r1.count == 2 and r1.data.n == 3,
				"a waiting burst merges and adds up"
			)
			-- while toasts wait, the ones up are cut to `hurry`
			local out = PopupQueue.step(q, P.hurry, ctx())
			check(#out.close == 2, "toasts up are hurried while others wait")
			check(out.show[1] == big, "the big moment shows before the small notes")
			-- a big moment never folds away, however long it waits
			local q2 = PopupQueue.new(P)
			local imp = PopupQueue.push(q2, { kind = "card", name = "boss", pri = P.pri.result, life = 5 }, 0)
			PopupQueue.step(q2, 0, ctx({ blocked = true }))
			PopupQueue.step(q2, 400, ctx({ blocked = true }))
			check(table.find(q2.waiting, imp) ~= nil, "an important card waits out a long scene")
			PopupQueue.step(q2, 402, ctx())
			check(PopupQueue.up(q2, "boss"), "and shows after it")
		end
	)

	test("pt-ui: the answer to a tap pushes off a small note, never a big moment", function()
		local q = PopupQueue.new(P)
		PopupQueue.push(q, { kind = "toast", pri = P.pri.result, life = 4 }, 0)
		PopupQueue.push(q, { kind = "toast", pri = P.pri.minor, life = 4 }, 0)
		PopupQueue.step(q, 0, ctx())
		local u = PopupQueue.push(q, { kind = "toast", pri = P.pri.story, urgent = true, life = 3 }, 0.1)
		local out = PopupQueue.step(q, 0.1, ctx())
		check(out.show[1] == u and #out.close == 1 and out.close[1].pri == P.pri.minor, "the small note goes")
		local q2 = PopupQueue.new(P)
		PopupQueue.push(q2, { kind = "toast", pri = P.pri.result, life = 4 }, 0)
		PopupQueue.push(q2, { kind = "toast", pri = P.pri.result, life = 4 }, 0)
		PopupQueue.step(q2, 0, ctx())
		local u2 = PopupQueue.push(q2, { kind = "toast", pri = P.pri.story, urgent = true, life = 3 }, 0.1)
		local out2 = PopupQueue.step(q2, 0.1, ctx())
		check(#out2.close == 0 and q2.waiting[1] == u2, "two big moments stay; the answer is first in line")
	end)

	test(
		"pt-ui: combat quieting: cards wait in a fight, timed asks do not, offers never interrupt one",
		function()
			local q = PopupQueue.new(P)
			local card =
				PopupQueue.push(q, { kind = "card", name = "result", pri = P.pri.result, life = 5 }, 0)
			PopupQueue.step(q, 1, ctx({ fighting = true, calmFor = 1 }))
			check(not PopupQueue.up(q, "result"), "a result card waits while fighting")
			PopupQueue.step(q, P.combatHold, ctx({ fighting = true, calmFor = 0.5 }))
			check(
				PopupQueue.up(q, "result") and card.shown ~= nil,
				"a long fight: it shows anyway after combatHold"
			)
			local q2 = PopupQueue.new(P)
			PopupQueue.push(
				q2,
				{ kind = "card", name = "invite", pri = P.pri.social, life = 31, fightOk = true },
				0
			)
			PopupQueue.step(q2, 0, ctx({ fighting = true, calmFor = 0 }))
			check(PopupQueue.up(q2, "invite"), "a timed ask may show in a fight")
			local q3 = PopupQueue.new(P)
			PopupQueue.push(q3, { kind = "card", name = "starter", pri = P.pri.offer, offer = true }, 0)
			PopupQueue.step(q3, 100, ctx({ fighting = true, calmFor = 0 }))
			check(not PopupQueue.up(q3, "starter"), "an offer never shows in a fight, however long")
			PopupQueue.step(q3, 101, ctx({ calmFor = P.offerCalm - 1 }))
			check(not PopupQueue.up(q3, "starter"), "nor right after one")
			PopupQueue.step(q3, 102, ctx({ calmFor = P.offerCalm }))
			check(PopupQueue.up(q3, "starter"), "it shows after offerCalm s of calm")
			check(P.cards.starter.offer == true, "the starter offer is an offer")
			-- a menu or scene: no new card, then settle s of calm first
			local q4 = PopupQueue.new(P)
			PopupQueue.push(q4, { kind = "card", name = "daily", pri = P.pri.join }, 0)
			PopupQueue.step(q4, 0, ctx({ blocked = true }))
			PopupQueue.step(q4, 1, ctx({ freeFor = P.settle / 2 }))
			check(not PopupQueue.up(q4, "daily"), "join cards wait settle s after a scene")
			PopupQueue.step(q4, 2, ctx({ freeFor = P.settle }))
			check(PopupQueue.up(q4, "daily"), "then show")
		end
	)

	test("pt-ui: stale juice folds into +N more, a run-out ask is dropped, every life ends", function()
		local q = PopupQueue.new(P)
		PopupQueue.push(q, { kind = "card", name = "boss", pri = P.pri.result, life = 8 }, 0)
		PopupQueue.push(q, { kind = "card", name = "stamp", pri = P.pri.juice, life = 2.4, stale = 3 }, 0)
		PopupQueue.push(q, { kind = "card", name = "ask", pri = P.pri.social, life = 30, expires = 4 }, 0)
		PopupQueue.step(q, 0, ctx())
		PopupQueue.step(q, 5, ctx())
		check(PopupQueue.takeMore(q) == 1, "the stamp that waited too long counts in +N more")
		check(#q.waiting == 0, "the run-out ask is gone")
		local out = PopupQueue.step(q, 8, ctx())
		check(
			#out.close == 1 and out.close[1].name == "boss",
			"the card is taken down at the end of its life"
		)
	end)

	test(
		"pt-ui: every card that pops by itself is in the line and closes (life or a close button)",
		function()
			local src = ""
			for _, dir in { "src/client/Ui", "src/client/Fx" } do
				for _, f in fs.readDir(dir) do
					if string.sub(f, -5) == ".luau" then
						src ..= fs.readFile(dir .. "/" .. f)
					end
				end
			end
			local tapClose = {
				contestVote = true,
				drones = true,
				daily = true,
				mentorPick = true,
				episode = true,
				board = true,
				starter = true,
			}
			for name, c in P.cards do
				check(P.pri[c.pri] ~= nil, name .. ": a known priority")
				local wired = string.find(src, 'Popups.show("' .. name .. '"', 1, true) ~= nil
					or string.find(src, 'PopupGate.later("' .. name .. '"', 1, true) ~= nil
				check(wired, name .. ": goes through the line")
				check(
					(c.life ~= nil and c.life > 0 and c.life <= 60) or tapClose[name] == true,
					name .. ": has a life or a close"
				)
			end
			-- the server-side join cards' own close buttons and the sources that must not show by themselves
			check(
				string.find(src, 'PopupGate.card("starter"', 1, true) ~= nil,
				"the starter offer says when it is up"
			)
		end
	)

	test("pt-ui: the costume contest's skipped banner closes (server goes idle; device times out)", function()
		local K = Config.Contest
		check(ContestRules.announce(true, "results", "idle"), "a skipped contest still says it is over")
		check(ContestRules.announce(true, "call", "show"), "and that it was skipped")
		check(not ContestRules.announce(true, "show", "show"), "but not every spotlight step")
		check(ContestRules.announce(false, "results", "idle"), "a normal contest's end goes out")
		local svc = fs.readFile("src/server/Services/ContestService.luau")
		check(
			string.find(svc, 'phase = if s.skipped and phase ~= "idle" then "skipped" else phase', 1, true)
				~= nil,
			"idle is never sent as skipped"
		)
		check(K.results > 0 and K.results < 60, "the results banner has a life")
	end)

	-- The real UI, headless: each card opens and closes
	if T.placePath and fs.isFile(T.placePath) then
		local roblox = require("@lune/roblox")
		local UiSim = require("./uisim")
		local trees = UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath)))
		local DEVICE =
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		local function newSim(): (any, any)
			local sim = UiSim.new(trees, DEVICE)
			sim:run("InputController", sim:require("Client.Controllers.InputController").init)
			for _, m in { "Hud", "Toasts", "WorldHud", "SquadHud", "HqHud", "PvpHud", "StoryHud" } do
				sim:run(m, sim:require("Client.Ui." .. m).init)
			end
			sim:run("JuiceFx", sim:require("Client.Fx.JuiceFx").init)
			sim:run("GuideHud", sim:require("Client.Ui.GuideHud").init)
			sim:run("CinemaHud", sim:require("Client.Ui.CinemaHud").init)
			sim:run("ContestHud", sim:require("Client.Ui.ContestHud").init)
			return sim, sim:require("Client.Ui.Popups")
		end
		-- time passes for the cards' own timers and the line both
		local function pass(sim: any, Popups: any, seconds: number)
			local t = 0
			while t < seconds do
				sim:advance(0.25)
				sim:run("tick", function()
					Popups.advance(0.25)
				end)
				t += 0.25
			end
		end
		local function fire(sim: any, name: string, data: any)
			sim:run(name, function()
				sim.service("ReplicatedStorage")
					:WaitForChild("Remotes")
					:WaitForChild(name).OnClientEvent
					:Fire(data)
			end)
		end
		local function visible(sim: any, screen: string, name: string?): boolean
			local g = sim.playerGui:FindFirstChild(screen)
			if not g then
				return false
			end
			for _, d in g:GetDescendants() do
				if d:IsA("GuiObject") and (name == nil or d.Name == name) and d.Visible then
					local ok = true
					local p = d.Parent
					while p and p ~= g do
						if p:IsA("GuiObject") and not p.Visible then
							ok = false
						end
						p = p.Parent
					end
					if ok and name ~= nil then
						return true
					end
				end
			end
			return false
		end

		test(
			"pt-ui: the real cards close (boss result, stamp, level badge, name card, invite, drones, toasts)",
			function()
				local sim, Popups = newSim()
				local WC = sim:require("Client.Controllers.WorldClient")
				sim:run("boss", function()
					WC.BossResult:Fire({
						num = 1,
						defeated = true,
						tier = "mvp",
						rank = 2,
						credits = 100,
						renown = 10,
					})
				end)
				check(visible(sim, "WorldHud", "BossResult"), "the boss result card shows")
				sim:run("stamp", function()
					sim:require("Client.Fx.Juice").fire("contractDone", nil, { name = "X" })
				end)
				check(#Popups.queue.waiting >= 1, "a stamp behind a card waits in line")
				pass(sim, Popups, 9)
				check(not visible(sim, "WorldHud", "BossResult"), "the boss result card closes")
				check(#Popups.queue.waiting == 0, "the stale stamp left the line")
				-- the name card
				sim:run("name", function()
					sim:require("Client.Ui.CinemaHud").nameCard("RustjawPrime")
				end)
				check(Popups.cardUp("nameCard"), "the name card is up")
				pass(sim, Popups, 5)
				check(not Popups.cardUp("nameCard"), "the name card closes")
				-- a squad invite runs out
				sim:run("invite", function()
					sim:require("Client.Controllers.SquadClient").Invited
						:Fire({ from = 9, name = "Tempest", size = 1 })
				end)
				check(Popups.cardUp("squadInvite"), "the invite is up")
				pass(sim, Popups, 32)
				check(not Popups.cardUp("squadInvite"), "the invite closes when it runs out")
				-- the drones' card closes on COLLECT
				fire(sim, "DronesReady", { credits = 300, minutes = 90 })
				check(Popups.cardUp("drones"), "the drones card is up")
				local g = sim.playerGui:FindFirstChild("HqHud")
				for _, d in (g and g:GetDescendants() or {}) do
					if d:IsA("TextButton") and d.Text == "COLLECT" then
						sim:run("collect", function()
							d.Activated:Fire()
						end)
					end
				end
				pass(sim, Popups, 0.5)
				check(not Popups.cardUp("drones"), "COLLECT closes the drones card")
				-- a burst of toasts all ends
				local Toasts = sim:require("Client.Ui.Toasts")
				sim:run("toasts", function()
					for i = 1, 8 do
						Toasts.show({ id = "reward", credits = i, renown = i })
						Toasts.show({ id = "incident", name = "Fire " .. i, medal = "gold" })
					end
				end)
				local up = 0
				for _, s in Popups.queue.showing do
					if s.kind == "toast" then
						up += 1
					end
				end
				check(up <= P.maxToasts, "no more than 2 toasts")
				pass(sim, Popups, 40)
				check(#Popups.queue.showing == 0 and #Popups.queue.waiting == 0, "every toast is done")
				check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, "; "))
			end
		)

		test("pt-ui: the contest's skipped and results banners close; the vote card has an X", function()
			local sim, Popups = newSim()
			local g = sim.playerGui:FindFirstChild("ContestHud")
			local banner = g and g:FindFirstChildWhichIsA("Frame")
			fire(sim, "ContestState", {
				phase = "skipped",
				theme = "Neon",
				entries = {},
				endsAt = os.time() + 5,
				now = os.time(),
				top = {},
			})
			check(banner ~= nil and banner.Visible, "the skipped banner shows")
			-- the server never says anything more (the old bug): the device closes it
			pass(sim, Popups, Config.Contest.results + 0.5)
			check(banner ~= nil and not banner.Visible, "the skipped banner closes by itself")
			-- the X closes a results banner at once
			fire(sim, "ContestState", {
				phase = "results",
				theme = "Neon",
				entries = { { id = 7, name = "Bolt" } },
				top = { 7 },
				endsAt = os.time() + 12,
				now = os.time(),
			})
			check(banner ~= nil and banner.Visible, "the results banner shows")
			local x = banner and banner:FindFirstChild("Close")
			check(x ~= nil, "the banner has an X")
			if x then
				sim:run("x", function()
					x.Activated:Fire()
				end)
			end
			check(banner ~= nil and not banner.Visible, "the X closes it")
			-- the vote card: up through the vote, X closes it
			fire(sim, "ContestState", {
				phase = "vote",
				theme = "Neon",
				entries = { { id = 7, name = "Bolt" } },
				top = {},
				endsAt = os.time() + 15,
				now = os.time(),
			})
			check(Popups.cardUp("contestVote"), "the vote card is up")
			local vc
			for _, d in g:GetDescendants() do
				if d:IsA("TextButton") and d.Name == "Close" and d.Parent ~= banner then
					vc = d
				end
			end
			check(vc ~= nil, "the vote card has an X")
			if vc then
				sim:run("vx", function()
					vc.Activated:Fire()
				end)
			end
			pass(sim, Popups, 0.5)
			check(not Popups.cardUp("contestVote"), "its X closes it")
			fire(
				sim,
				"ContestState",
				{ phase = "idle", entries = {}, top = {}, endsAt = os.time() + 900, now = os.time() }
			)
			check(banner ~= nil and not banner.Visible, "idle shows nothing")
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, "; "))
		end)
	end

	-- Missing building textures (nate: "some buildings don't have textures")
	test("pt-ui: every building part the city builds wears a textured kit material variant", function()
		local K = Config.City.kit
		local NO_VARIANT = { Glass = true, Neon = true, ForceField = true, Air = true, Water = true }
		local project = serde.decode("json", fs.readFile("default.project.json"))
		local ms = project.tree.MaterialService
		local files: { [string]: any } = {}
		for name in K.baseMaterial do
			local node = ms and ms["Kit" .. name]
			check(node ~= nil, "Kit" .. name .. " is in MaterialService")
			if node then
				local v = serde.decode("json", fs.readFile(node["$path"]))
				files[name] = v
				local p = v.properties
				check(p.BaseMaterial == K.baseMaterial[name], name .. ": base material matches Config")
				check(
					not NO_VARIANT[p.BaseMaterial],
					name .. ": its base material can show a MaterialVariant"
				)
				for _, map in { "ColorMap", "NormalMap", "RoughnessMap" } do
					local id = tonumber(string.match(tostring(p[map] or ""), "rbxassetid://(%d+)")) or 0
					check(id > 0, name .. " " .. map .. " is an uploaded image")
				end
			end
		end
		local function scan(list: { any }, where: string)
			local bad = {}
			for _, b in list do
				if b.kind == "building" or b.kind == "tier" or (b.kind == "beacon" and b.shape == nil) then
					local kit = if b.ground and files[b.ground] then b.ground else b.kit
					if not (kit and files[kit]) then
						local key = tostring(b.color) .. "/" .. tostring(b.shape)
						bad[key] = (bad[key] or 0) + 1
					end
				end
			end
			for key, n in bad do
				check(false, string.format("%s: %d plain building parts (%s)", where, n, key))
			end
		end
		local world = T.world
		scan(world.hubBoxes, "hub")
		for _, plan in world.tilePlans do
			scan(plan.boxes, "outskirts")
		end
		for _, lm in world.landmarks do
			scan(lm.boxes, "landmark " .. lm.id)
		end
		for name in Config.PocketKit.pockets do
			if PocketLayout.known(name) then
				local l = PocketLayout.build(Config, 1, name)
				PocketDress.apply(Config, l, name)
				scan(l.boxes, "pocket " .. name)
			end
		end
		-- a broken kit building's pillars, slabs and rubble keep a kit texture (Fx.BuildingFx)
		local fx = fs.readFile("src/client/Fx/BuildingFx.luau")
		check(
			string.find(fx, 'if c.kind == "wall" then variant else inner', 1, true) ~= nil,
			"pillars and slabs wear the wreck kit"
		)
		check(K.wreck ~= nil and files[K.wreck] ~= nil, "the wreck kit is a real texture")
	end)
end
