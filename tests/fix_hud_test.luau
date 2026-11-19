-- fix-hud (nate's playtest of gaps7, 2026-11-19): "need a way to get rid of popups shit is just on my screen. Why
-- is the boss bar above my screen if im not even near it?" and "Player should have like double the stamina".
-- ONLY="fix-hud". The real client UI runs headless in tests/uisim.luau (the game's own modules from the built
-- place): every popup gets an X and a tap, Backspace clears them all and the line, the Settings "Popups" mode
-- filters, and the boss bar shows only near the fight.

local fs = require("@lune/fs")

return function(T: { [string]: any })
	local test, check, Config = T.test, T.check, T.Config
	local BossRange = require("../src/shared/BossRange")
	local P = Config.Ui.popups

	test("fix-hud: the boss bar only near the fight (BossRange.hudNear)", function()
		local def = Config.Boss.bosses.RustjawPrime
		local s = { state = 3, num = def.num, x = 0, z = 0 }
		local r = math.max(Config.Boss.hud.near, def.arenaRadius)
		check(r >= 400, "near is at least 400 studs")
		check(BossRange.hudNear(Config, s, r - 5, 0, false, false) == "bar", "inside the radius: the bar")
		check(
			BossRange.hudNear(Config, s, r + 5, 0, false, false) == "corner",
			"just outside: the corner timer"
		)
		check(
			BossRange.hudNear(Config, s, r + 5, 0, false, true) == "bar",
			"once shown it leaves only past the margin (no flicker)"
		)
		check(
			BossRange.hudNear(Config, s, 3000, 0, true, false) == "bar",
			"on the contribution list: the bar"
		)
		check(BossRange.hudNear(Config, s, nil, nil, false, false) == "corner", "no hero yet: the corner")
		check(BossRange.hudNear(Config, { state = 0 }, 0, 0, true, true) == "none", "no boss: nothing")
		local banner = { state = 1, num = def.num, x = 0, z = 0 }
		check(
			BossRange.hudNear(Config, banner, 5000, 0, false, false) == "corner",
			"a far countdown: corner only"
		)
		check(
			BossRange.hudNear(Config, banner, 5000, 0, true, false) == "corner",
			"the list counts in the fight only (a stale tier never brings the banner)"
		)
		local src = fs.readFile("src/client/Ui/Radar.luau")
		check(string.find(src, "BOSS FIGHT!", 1, true) ~= nil, "the radar keeps the corner timer")
	end)

	test("fix-hud: Settings Popups (All, Important only, Off) and every card has a life or its X", function()
		local idx, key
		for i, k in Config.Settings.keys do
			if k.id == "popups" then
				idx, key = i, k
			end
		end
		check(idx ~= nil and idx <= 16, "its own key inside Settings.Set's range")
		check(
			key and key.kind == "choice" and #key.options == 3 and key.default == 0,
			"three options, All first"
		)
		check(
			key and key.options[1] == "All" and key.options[2] == "Important only" and key.options[3] == "Off",
			"named as nate asked"
		)
		check(P.modes.all == 0 and P.modes.important == 1 and P.modes.off == 2, "modes follow the options")
		for name, c in P.cards do
			check(
				(c.life ~= nil and c.life <= 45) or name == "contestVote",
				name .. ": a short life (the contest vote closes with the vote)"
			)
		end
		check(P.cards.squadInvite.important == "card", "an invite still shows when Important only")
		check(P.cards.bossResult.important == "toast", "a result card becomes a small toast")
		check(table.find(P.dismiss.keys, "Backspace") ~= nil, "Backspace clears")
		check(Config.Move.stamina.max == 200, "nate: double the stamina")
	end)

	if not (T.placePath and fs.isFile(T.placePath)) then
		return
	end
	local roblox = require("@lune/roblox")
	local UiSim = require("./uisim")
	local trees = UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath)))
	local DEVICE =
		{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
	local function newSim(): (any, any)
		local sim = UiSim.new(trees, DEVICE)
		sim:run("InputController", sim:require("Client.Controllers.InputController").init)
		for _, m in { "Hud", "Toasts", "WorldHud", "SquadHud", "HqHud", "PvpHud", "StoryHud", "Radar" } do
			sim:run(m, sim:require("Client.Ui." .. m).init)
		end
		sim:run("JuiceFx", sim:require("Client.Fx.JuiceFx").init)
		sim:run("GuideHud", sim:require("Client.Ui.GuideHud").init)
		sim:run("CinemaHud", sim:require("Client.Ui.CinemaHud").init)
		sim:run("ContestHud", sim:require("Client.Ui.ContestHud").init)
		sim:run("NewsHud", sim:require("Client.Ui.NewsHud").init)
		return sim, sim:require("Client.Ui.Popups")
	end
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
	-- the HUD's own Heartbeat loops (WorldHud's tracker and boss bar, the radar): one frame of 0.3 s
	local function beat(sim: any)
		sim:run("beat", function()
			sim.service("RunService").Heartbeat:Fire(0.3)
			sim.service("RunService").RenderStepped:Fire(0.3)
		end)
	end
	local function fire(sim: any, name: string, data: any)
		sim:run(name, function()
			sim.service("ReplicatedStorage")
				:WaitForChild("Remotes")
				:WaitForChild(name).OnClientEvent
				:Fire(data)
		end)
	end
	local function shown(obj: any): boolean
		local p = obj
		while p do
			if p:IsA("GuiObject") and not p.Visible then
				return false
			end
			if p:IsA("ScreenGui") then
				return p.Enabled
			end
			p = p.Parent
		end
		return false
	end
	local function find(sim: any, screen: string, name: string): any
		local g = sim.playerGui:FindFirstChild(screen)
		for _, d in (g and g:GetDescendants() or {}) do
			if d.Name == name then
				return d
			end
		end
		return nil
	end
	local function xOf(obj: any): any
		local f = obj and obj:FindFirstChild("Dismiss")
		local top = f and f:FindFirstChild("DismissTop")
		return top and top:FindFirstChild("DismissX")
	end
	local function tapOf(obj: any): any
		local f = obj and obj:FindFirstChild("Dismiss")
		return f and f:FindFirstChild("DismissTap")
	end
	local function press(sim: any, key: any)
		sim:run("key", function()
			sim.service("UserInputService").InputBegan:Fire({
				KeyCode = key,
				UserInputType = roblox.Enum.UserInputType.Keyboard,
				UserInputState = roblox.Enum.UserInputState.Begin,
			}, false)
		end)
	end
	local function bossResult(sim: any)
		sim:run("boss", function()
			sim:require("Client.Controllers.WorldClient").BossResult:Fire({
				num = 1,
				defeated = true,
				tier = "mvp",
				rank = 2,
				credits = 100,
				renown = 10,
			})
		end)
	end

	test("fix-hud: the real popups have an X and a tap that take them down (headless client UI)", function()
		local sim, Popups = newSim()
		-- the boss result card: its X
		bossResult(sim)
		local card = find(sim, "WorldHud", "BossResult")
		check(card ~= nil and shown(card), "the boss result card shows")
		local x = xOf(card)
		check(x ~= nil and shown(x), "it wears an X")
		check(x and x.Size.X.Offset >= Config.Ui.phone.minTap, "the X is tap-sized for a phone")
		local face = x and x:FindFirstChild("Face")
		check(face and face.Text == "X" and face.Size.X.Offset == P.dismiss.cardX, "wearing a 30 px X")
		if x then
			sim:tap(x)
		end
		check(not Popups.cardUp("bossResult"), "the X frees its slot at once")
		check(card.Parent == nil, "and the card is gone")
		-- a toast: its small X and a tap anywhere on it
		local Toasts = sim:require("Client.Ui.Toasts")
		sim:run("toast", function()
			Toasts.show({ id = "incident", name = "Fire", medal = "gold" })
		end)
		local stack = find(sim, "Toasts", "Stack")
		local toast
		for _, c in stack:GetChildren() do
			if c:IsA("TextLabel") and c.Name ~= "More" then
				toast = c
			end
		end
		check(toast ~= nil, "the toast shows")
		check(
			xOf(toast) == nil,
			"a toast has no X (too small for a phone's thumb): the whole bubble is its tap"
		)
		local tap = tapOf(toast)
		check(tap ~= nil and tap.ZIndex == 0, "and a tap layer under its words")
		if tap then
			sim:tap(tap)
		end
		check(toast.Parent == nil, "a tap anywhere on the toast takes it down")
		-- the name card (a card that toggles its panel): a tap on it (after the incident's stamp)
		pass(sim, Popups, 3)
		sim:run("name", function()
			sim:require("Client.Ui.CinemaHud").nameCard("RustjawPrime")
		end)
		check(
			Popups.cardUp("nameCard"),
			"the name card is up: " .. #Popups.queue.waiting .. " waiting, " .. #Popups.queue.showing .. " up"
		)
		local nc = find(sim, "CinemaHud", "NameCard")
		check(nc ~= nil and tapOf(nc) ~= nil, "the name card's panel took the X and tap")
		if nc then
			sim:tap(tapOf(nc))
		end
		check(not Popups.cardUp("nameCard") and nc and not shown(nc), "a tap on the name card closes it")
		-- the drones card: its X collects too (the haul is never lost)
		local sent = 0
		sim:run("hook", function()
			local r = sim.service("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("HqCollect")
			r._props.FireServer = function()
				sent += 1
			end
		end)
		fire(sim, "DronesReady", { credits = 300, minutes = 90 })
		check(Popups.cardUp("drones"), "the drones card is up")
		local dx
		for _, d in sim.playerGui:FindFirstChild("HqHud"):GetDescendants() do
			if d.Name == "DismissX" then
				dx = d
			end
		end
		check(dx ~= nil, "the drones card has an X")
		if dx then
			sim:tap(dx)
		end
		check(not Popups.cardUp("drones") and sent == 1, "its X collects and closes")
		-- by itself: it collects at the end of its life too
		fire(sim, "DronesReady", { credits = 300, minutes = 90 })
		pass(sim, Popups, P.cards.drones.life + 0.5)
		check(not Popups.cardUp("drones") and sent == 2, "its life ends it, collected")
		check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, "; "))
	end)

	test("fix-hud: Backspace clears every popup on screen and the waiting line", function()
		local sim, Popups = newSim()
		bossResult(sim)
		local Toasts = sim:require("Client.Ui.Toasts")
		sim:run("toasts", function()
			for i = 1, 6 do
				Toasts.show({ id = "incident", name = "Fire " .. i, medal = "gold" })
			end
			sim:require("Client.Fx.Juice").fire("contractDone", nil, { name = "X" })
		end)
		check(#Popups.queue.showing >= 2 and #Popups.queue.waiting >= 1, "a card, toasts and a line")
		-- the trackers fold too: a contract in the world tracker
		local WC = sim:require("Client.Controllers.WorldClient")
		sim:run("contract", function()
			WC.contracts = { { 1, 1, 5, 0, 0, 0, 0, 1, 0 } }
		end)
		beat(sim)
		local tracker = find(sim, "WorldHud", "Tracker")
		check(tracker and shown(tracker) and xOf(tracker) ~= nil, "the tracker shows with its X")
		press(sim, roblox.Enum.KeyCode.Backspace)
		check(#Popups.queue.showing == 0 and #Popups.queue.waiting == 0, "nothing up, nothing waiting")
		check(find(sim, "WorldHud", "BossResult") == nil, "the boss card went")
		beat(sim)
		check(tracker and not shown(tracker), "the tracker folded")
		-- it comes back when something new joins it
		sim:run("contract2", function()
			WC.contracts = { { 2, 0, 3, 0, 0, 0, 0, 1, 0 } } -- (a phone-sized tracker may show one row only)
		end)
		beat(sim)
		local rowsUp = 0
		for _, r in tracker:GetChildren() do
			if r:IsA("Frame") and r.Visible then
				rowsUp += 1
			end
		end
		check(tracker and shown(tracker), "a new row brings the tracker back (" .. rowsUp .. " rows)")
		-- keyboard B is GRAB: it does not clear
		bossResult(sim)
		press(sim, roblox.Enum.KeyCode.B)
		check(Popups.cardUp("bossResult"), "B is GRAB and the prompts' key: it leaves popups alone")
		-- the answer to a tap stays through Backspace
		sim:run("refused", function()
			Toasts.show({ id = "contractRefused", reason = "combat" })
		end)
		press(sim, roblox.Enum.KeyCode.Backspace)
		check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, "; "))
	end)

	test(
		"fix-hud: Settings Popups: Important only keeps rewards and invites as small toasts, Off nothing",
		function()
			local sim, Popups = newSim()
			local SC = sim:require("Client.Controllers.SettingsClient")
			sim:run("mode", function()
				SC.set("popups", 1)
			end)
			check(Popups.mode == 1, "Settings reaches the line")
			local Toasts = sim:require("Client.Ui.Toasts")
			sim:run("minor", function()
				Toasts.show({ id = "skillPoint" })
				Toasts.show({ id = "beacon", name = "North" })
			end)
			check(#Popups.queue.showing == 0 and #Popups.queue.waiting == 0, "small notes are left out")
			sim:run("reward", function()
				Toasts.show({ id = "reward", credits = 50, renown = 5 })
			end)
			check(#Popups.queue.showing == 1, "a reward still shows")
			pass(sim, Popups, 6)
			bossResult(sim)
			check(not Popups.cardUp("bossResult"), "no big boss card")
			local line = false
			for _, s in Popups.queue.showing do
				line = line or s.kind == "toast"
			end
			check(line, "the boss result comes as one small toast")
			local stack = find(sim, "Toasts", "Stack")
			local text = ""
			for _, c in stack:GetChildren() do
				if c:IsA("TextLabel") and c.Name ~= "More" then
					text ..= c.Text
				end
			end
			check(
				string.find(text, "DEFEATED", 1, true) ~= nil and string.find(text, "+100", 1, true) ~= nil,
				text
			)
			pass(sim, Popups, 6)
			sim:run("invite", function()
				sim:require("Client.Controllers.SquadClient").Invited
					:Fire({ from = 9, name = "Tempest", size = 1 })
			end)
			check(Popups.cardUp("squadInvite"), "an invite still asks")
			-- Off: only the answer to your own tap
			sim:run("off", function()
				SC.set("popups", 2)
			end)
			check(#Popups.queue.showing == 0, "switching to Off takes down what is up")
			sim:run("off2", function()
				Toasts.show({ id = "reward", credits = 50, renown = 5 })
				sim:require("Client.Ui.CinemaHud").nameCard("RustjawPrime")
			end)
			bossResult(sim)
			check(#Popups.queue.showing == 0 and #Popups.queue.waiting == 0, "Off: nothing shows")
			sim:run("refused", function()
				Toasts.show({ id = "contractRefused", reason = "combat" })
			end)
			check(#Popups.queue.showing == 1, "but the answer to a tap does")
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, "; "))
		end
	)

	test("fix-hud: the boss bar and banner show only near the fight (headless WorldHud)", function()
		local sim = newSim()
		local WC = sim:require("Client.Controllers.WorldClient")
		local WorldHud = sim:require("Client.Ui.WorldHud")
		local boss = find(sim, "WorldHud", "Boss")
		local banner = find(sim, "WorldHud", "BossBanner")
		-- a hero standing somewhere
		local root
		sim:run("hero", function()
			local m = UiSim.newInstance("Model")
			root = UiSim.newInstance("Part")
			root.Name = "HumanoidRootPart"
			root.Position = roblox.Vector3.new(0, 10, 0)
			root.Parent = m
			m.Parent = sim.service("Workspace")
			sim.player._props.Character = m
		end)
		local function state(s: any)
			sim:run("state", function()
				s.id = WC.bossByNum[s.num]
				WC.boss = s
			end)
			beat(sim)
		end
		state({
			state = 3,
			num = 1,
			x = 2000,
			y = 0,
			z = 0,
			hp = 50,
			max = 100,
			phase = 1,
			at = 200,
			level = 20,
		})
		check(WorldHud.bossMode == "corner", "a fight 2,000 studs off: corner mode")
		check(not shown(boss), "no boss bar at the top of the screen")
		local radar = ""
		for _, d in sim.playerGui:GetDescendants() do
			if d:IsA("TextLabel") and string.find(d.Text, "BOSS FIGHT", 1, true) then
				radar = d.Text
			end
		end
		check(string.find(radar, "2,000 studs", 1, true) ~= nil, "the radar's corner says how far: " .. radar)
		state({
			state = 3,
			num = 1,
			x = 150,
			y = 0,
			z = 0,
			hp = 50,
			max = 100,
			phase = 1,
			at = 200,
			level = 20,
		})
		check(WorldHud.bossMode == "bar" and shown(boss), "near the fight: the bar")
		-- on its list, far away: still the bar
		sim:run("mine", function()
			WC.mine = { score = 10, tier = "participant", rank = 3, heroes = 5 }
		end)
		state({
			state = 3,
			num = 1,
			x = 3000,
			y = 0,
			z = 0,
			hp = 50,
			max = 100,
			phase = 1,
			at = 200,
			level = 20,
		})
		check(shown(boss), "on the contribution list: the bar anywhere")
		-- a countdown far away: no big banner
		sim:run("mine0", function()
			WC.mine = { score = 0, tier = "", rank = 0, heroes = 0 }
		end)
		state({ state = 1, num = 1, x = 3000, y = 0, z = 0, at = 40 })
		check(not shown(banner), "a far countdown: no banner over the screen")
		state({ state = 1, num = 1, x = 100, y = 0, z = 0, at = 40 })
		check(shown(banner), "near: the countdown banner")
		check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, "; "))
	end)
end
