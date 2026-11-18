-- Phone pass tests (overhaul plan step 8): the touch layout's maths, the device presets, the Button size
-- setting, and, with a built place, every screen run headless (tests/uisim.luau) at phone, tablet and PC
-- sizes with no off-screen, overlapping, tiny or thumb-blocked controls.
-- Called from tests/run.luau: require("./phone_test")(test, check, Config, placePath)

local TouchLayout = require("../src/shared/TouchLayout")
local QualityRules = require("../src/shared/QualityRules")
local SettingsRules = require("../src/shared/SettingsRules")
local Remotes = require("../src/shared/Remotes")

-- Screen sizes in GUI pixels: the safe area after Roblox's top bar (58 px at worst) and the notch insets
local DEVICES = {
	{ name = "iPhone SE", w = 667, h = 375, top = 58, left = 0, right = 0, bottom = 0, touch = true },
	{ name = "iPhone 14", w = 844, h = 390, top = 58, left = 47, right = 47, bottom = 0, touch = true },
	{ name = "Android 20:9", w = 800, h = 360, top = 58, left = 32, right = 32, bottom = 0, touch = true },
	{ name = "iPad", w = 1024, h = 768, top = 58, left = 0, right = 0, bottom = 0, touch = true },
	{ name = "PC 1080p", w = 1920, h = 1080, top = 58, left = 0, right = 0, bottom = 0, touch = false },
}

local function overlaps(a: any, b: any): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local function circleBox(p: any): any
	return { x = p.x - p.size / 2, y = p.y - p.size / 2, w = p.size, h = p.size }
end

local function circlesOverlap(a: any, b: any): boolean
	local dx, dy = a.x - b.x, a.y - b.y
	return math.sqrt(dx * dx + dy * dy) < (a.size + b.size) / 2 - 0.5
end

return function(
	test: (string, () -> ()) -> (),
	check: (boolean, string) -> (),
	Config: any,
	placePath: string?
)
	local P = Config.Ui.phone
	local primary = {}
	for _, id in TouchLayout.PRIMARY do
		primary[id] = true
	end

	test("Phone: the action cluster fits every screen, big enough and clear of the move stick", function()
		for _, d in DEVICES do
			local w, h = d.w - d.left - d.right, d.h - d.top - d.bottom
			for _, left in { false, true } do
				for _, user in { 0.8, 1, 1.3 } do
					local o = { touch = d.touch, leftHanded = left, user = user }
					local tag =
						string.format("%s%s at %d%%", d.name, if left then " left-handed" else "", user * 100)
					local placed = TouchLayout.cluster(Config, w, h, o)
					local zone = TouchLayout.stickZone(w, h, if left then "left" else "default")
					local top = TouchLayout.topReserve(Config, w, h)
					for id, p in placed do
						local slot = TouchLayout.SLOTS[id]
						if not slot.optional then
							local b = circleBox(p)
							check(
								b.x >= 0
									and b.x + b.w <= w + 0.5
									and b.y >= top - 0.5
									and b.y + b.h <= h + 0.5,
								tag .. ": " .. id .. " inside the safe area, under the top row"
							)
							if d.touch then
								check(not overlaps(b, zone), tag .. ": " .. id .. " clear of the move stick")
								local want = if primary[id] then P.minPrimary else P.minTap
								check(
									p.size >= want - 0.5,
									tag .. ": " .. id .. " at least " .. want .. " px"
								)
							end
							for other, q in placed do
								local shared = TouchLayout.SHARED[id] == other
									or TouchLayout.SHARED[other] == id
								if other < id and not TouchLayout.SLOTS[other].optional and not shared then
									check(
										not circlesOverlap(p, q),
										tag .. ": " .. id .. " and " .. other .. " apart"
									)
								end
							end
						end
					end
				end
			end
		end
	end)

	test("Phone: left-handed mirrors the cluster; Button size grows it until it would not fit", function()
		local w, h = 844 - 94, 390 - 58
		local right = TouchLayout.cluster(Config, w, h, { touch = true })
		local left = TouchLayout.cluster(Config, w, h, { touch = true, leftHanded = true })
		for id, p in right do
			check(math.abs(left[id].x - (w - p.x)) < 1e-6 and left[id].y == p.y, id .. " mirrored")
		end
		local big = TouchLayout.clusterScale(Config, 1920, 1080, { touch = true, user = 1.3 })
		local normal = TouchLayout.clusterScale(Config, 1920, 1080, { touch = true, user = 1 })
		check(big > normal and big <= P.maxScale, "a roomy screen takes the bigger buttons")
		local phoneBig = TouchLayout.clusterScale(Config, 667, 317, { touch = true, user = 1.3 })
		local phone = TouchLayout.clusterScale(Config, 667, 317, { touch = true, user = 1 })
		check(phoneBig == phone, "a phone already at its fit stays at its fit")
		check(
			TouchLayout.clusterScale(Config, 1920, 1080, { touch = false }) < normal,
			"mouse and gamepad draw it a little smaller"
		)
	end)

	test("Phone: the top row fits between the status card and the edge; the rest goes in MORE", function()
		local items = {}
		for i, t in
			{ "POWERS", "GEAR", "MAP", "SHOP", "PING", "PVP", "JOURNAL", "SQUAD", "EMOTE", "PHOTO", "⚙" }
		do
			table.insert(items, { id = "b" .. i, text = t, order = i })
		end
		for _, d in DEVICES do
			local w, h = d.w - d.left - d.right, d.h - d.top - d.bottom
			for _, left in { false, true } do
				local hb = TouchLayout.hud(Config, w, h, { touch = d.touch, leftHanded = left })
				local plan = TouchLayout.dock(Config, items, hb.dockLo, hb.dockHi, w, h, hb.dockFromLo)
				local boxes = {}
				for _, b in plan.row do
					table.insert(boxes, b)
				end
				if plan.more then
					table.insert(boxes, plan.more)
				end
				check(#boxes >= 3, d.name .. ": at least two buttons and MORE in the row")
				check(#plan.drawer == 0 or plan.more ~= nil, d.name .. ": a drawer always has its MORE")
				for i, b in boxes do
					check(
						b.x >= hb.dockLo - 0.5 and b.x + b.w <= hb.dockHi + 0.5,
						d.name .. ": row button in its span"
					)
					check(b.h >= P.minTap, d.name .. ": row buttons are tap-sized")
					for j = i + 1, #boxes do
						check(not overlaps(b, boxes[j]), d.name .. ": row buttons apart")
					end
					for _, key in { "status", "radar", "wallet", "buffs" } do
						check(not overlaps(b, (hb :: any)[key]), d.name .. ": the row clears the " .. key)
					end
				end
				-- the display parts never sit on an action button (each button's own box, not the cluster's)
				local placed = TouchLayout.cluster(Config, w, h, { touch = d.touch, leftHanded = left })
				local side = d.name .. (if left then " left" else "")
				for _, key in { "status", "radar", "tracker", "squad", "wallet", "buffs" } do
					local b = (hb :: any)[key]
					if b.h > 0 then
						for id, p in placed do
							if not TouchLayout.SLOTS[id].optional then
								check(
									not overlaps(b, circleBox(p)),
									side .. ": " .. key .. " clear of " .. id
								)
							end
						end
					end
				end
				-- the radar is the only part a thumb could hit; on a phone it does not take taps at all
				if d.touch and hb.radarTaps then
					local zone = TouchLayout.stickZone(w, h, if left then "left" else "default")
					check(not overlaps(hb.radar, zone), side .. ": a tappable radar is out of the stick zone")
				end
				if hb.compact then
					check(not hb.radarTaps, side .. ": the phone radar takes no taps (MAP opens the map)")
				end
			end
		end
	end)

	test("Phone: device presets: phones start on low, the slow watch steps down, never up", function()
		local Pr = Config.Presets
		check(QualityRules.device(true, false, false, 844, 390) == "phone", "a touch phone")
		check(QualityRules.device(true, false, false, 1024, 768) == "tablet", "a touch tablet")
		check(QualityRules.device(false, true, false, 1920, 1080) == "pc", "a PC")
		check(QualityRules.device(true, true, false, 1366, 768) == "pc", "a touch laptop")
		check(QualityRules.device(false, false, true, 1920, 1080) == "console", "a console")
		check(QualityRules.auto(Pr, "phone") == "low", "phones start on low")
		for _, dev in { "tablet", "pc", "console" } do
			check(QualityRules.auto(Pr, dev) == "medium", dev .. " starts on medium")
		end
		check(QualityRules.frameStep(Pr, "low", 30, "phone") == "low", "low is the floor")
		check(QualityRules.frameStep(Pr, "medium", 30, "pc") == "low", "slow test steps down")
		check(QualityRules.frameStep(Pr, "medium", 70, "pc") == "high", "a fast PC steps up")
		check(QualityRules.frameStep(Pr, "medium", 70, "tablet") == "medium", "touch devices never step up")
		check(QualityRules.frameStep(Pr, "low", 70, "phone") == "low", "a fast phone stays on low")
		local watch = QualityRules.newWatch()
		local name = "medium"
		for _ = 1, Pr.watch.seconds - 1 do
			name = QualityRules.watchStep(Pr, watch, name, Pr.watch.below - 1, 1)
		end
		check(name == "medium", "not before the watch time")
		name = QualityRules.watchStep(Pr, watch, name, 60, 1)
		for _ = 1, Pr.watch.seconds - 1 do
			name = QualityRules.watchStep(Pr, watch, name, Pr.watch.below - 1, 1)
		end
		check(name == "medium", "a fast second resets the count")
		name = QualityRules.watchStep(Pr, watch, name, Pr.watch.below - 1, 1)
		check(name == "low", "sustained slow frames step down")
		for _ = 1, 100 do
			name = QualityRules.watchStep(Pr, watch, name, 120, 1)
		end
		check(name == "low", "the watch never steps up")
	end)

	test(
		"Phone: every preset has every field; low draws the least; medium and high keep today's numbers",
		function()
			local Pr = Config.Presets
			local keys = {}
			for k in Pr.high do
				keys[k] = true
			end
			for _, name in Pr.order do
				for k in keys do
					check(Pr[name][k] ~= nil, name .. "." .. k)
				end
			end
			local fewerIsMore = { citizenPoseEvery = true } -- a frame count between poses: low waits longer
			for k, v in Pr.low do
				if type(v) == "number" then
					local lo, mid, hi = v, Pr.medium[k], Pr.high[k]
					if fewerIsMore[k] then
						lo, hi = hi, lo
					end
					check(lo <= mid and mid <= hi, k .. " costs more from low to high")
				end
			end
			local C = Config.Destruction.citizens
			check(
				Pr.medium.citizensDrawn >= C.max and Pr.high.citizensDrawn >= C.max,
				"medium and high draw every citizen"
			)
			check(Pr.low.citizensDrawn < C.max, "low draws fewer citizens")
			check(
				Pr.medium.citizenPoseNear == C.poseNear and Pr.medium.citizenPoseEvery == C.poseEvery,
				"medium poses as before"
			)
			check(
				Pr.low.bloom == false and Pr.low.sunRays == false and Pr.low.shadows == false,
				"low drops the glow"
			)
			check(Pr.medium.bloom and Pr.medium.sunRays, "medium keeps bloom and sun rays")
			check(Config.Fx.lib.budget.low < Config.Fx.lib.budget.medium, "FxLib's budget is smaller on low")
			for _, name in Pr.order do
				check(
					Config.Fx.lib.budget[name] ~= nil and Config.Fx.lib.scale[name] ~= nil,
					"FxLib has a " .. name .. " share"
				)
			end
		end
	)

	test("Phone: nearest citizens: the limit nearest drawn, ones already drawn kept at the cut", function()
		local rows = {}
		for i = 1, 60 do
			rows[i] = { x = i * 10, z = 0 }
		end
		local all = QualityRules.nearest(rows, 0, 0, 60)
		check(all == rows, "all fit: the same table")
		local some = QualityRules.nearest(rows, 0, 0, 30)
		local n = 0
		for id in some do
			n += 1
			check(id <= 30, "only the nearest")
		end
		check(n == 30, "30 drawn")
		local kept = QualityRules.nearest(rows, 0, 0, 30, { [31] = true })
		check(kept[31] ~= nil and kept[30] == nil, "a drawn citizen just past the cut stays")
	end)

	test("Phone: the Button size setting is saved, in range and fits the settings remote", function()
		local idx, key
		for i, k in Config.Settings.keys do
			if k.id == "buttonSize" then
				idx, key = i, k
			end
		end
		check(key ~= nil, "a buttonSize key")
		if not key then
			return
		end
		check(key.default == 100 and key.lo <= 80 and key.hi >= 130, "80% to 130%, 100% by default")
		local schema = Remotes.SettingsSet.schema
		check(idx <= schema[1].max, "its key number fits Settings.Set")
		check(SettingsRules.defaults(Config).buttonSize == 100, "default on a new save")
		check(1.3 <= P.maxScale and 0.8 >= P.minScale - 1e-9, "the cluster scale range holds the setting")
	end)

	test("Phone: every gui the client puts in PlayerGui survives a respawn (ResetOnSpawn off)", function()
		-- a ScreenGui, SurfaceGui or BillboardGui in PlayerGui with ResetOnSpawn on is wiped by the first
		-- respawn (the news screens were); the code makes them once, so each must turn it off
		local fs = require("@lune/fs")
		local n = 0
		local function walk(dir: string)
			for _, name in fs.readDir(dir) do
				local path = dir .. "/" .. name
				if fs.isDir(path) then
					walk(path)
				elseif string.match(name, "%.luau$") then
					local src = fs.readFile(path)
					for line in string.gmatch(src, "[^\n]+") do
						local var = string.match(line, "^%s*([%w_]+)%.Parent = .*PlayerGui")
						if var then
							n += 1
							check(
								string.find(src, var .. ".ResetOnSpawn = false", 1, true) ~= nil,
								path .. ": " .. var .. " goes in PlayerGui with ResetOnSpawn off"
							)
						end
					end
				end
			end
		end
		walk("src/client")
		walk("src/first")
		check(n >= 8, "found the guis put in PlayerGui")
	end)

	if not placePath then
		return
	end

	test(
		"Phone: every screen at phone, tablet and PC sizes: on screen, readable, tappable, clear of the stick",
		function()
			local fs = require("@lune/fs")
			local roblox = require("@lune/roblox")
			local UiSim = require("./uisim")
			local placeGame = roblox.deserializePlace(fs.readFile(placePath))
			local trees = UiSim.load(placeGame)
			local MODULES = {
				"Hud",
				"LoadoutScreen",
				"GearScreen",
				"ContractBoard",
				"Toasts",
				"MapScreen",
				"WorldHud",
				"CreatorScreen",
				"WeaponRack",
				"StoryHud",
				"Journal",
				"PvpHud",
				"Plates",
				"ShopHud",
				"HqHud",
				"SettingsMenu",
				"SquadHud",
				"Radar",
				"MainMenu",
				"PhotoMode",
				-- the Hero MMO screens, the guide, the cutscene player and the news (every module in Ui but
				-- Kit, the helpers Preview and Shapes, and the DevPanel)
				"TaskForceHud",
				"NemesisHud",
				"MentorHud",
				"BadgeHud",
				"ContestHud",
				"PassHud",
				"GuideHud",
				"CinemaHud",
				"NewsHud",
				"BoardHud", -- WP2
			}
			-- the panels a player opens, their ScreenGui and what open() takes
			local PANELS = {
				{ "LoadoutScreen", "Loadout" },
				{ "GearScreen", "Gear" },
				{ "MapScreen", "Map" },
				{ "Journal", "Journal" },
				{ "ShopHud", "Shop" },
				{ "SettingsMenu", "Settings" },
				{ "SquadHud", "Squad" },
				{ "WeaponRack", "WeaponRack" },
				{ "PhotoMode", "Photo" },
				{ "ContractBoard", "ContractBoard", { offers = {}, active = {} } },
				{ "HqHud", "HqHud", "trophies" },
				{ "CreatorScreen", "Creator", { mode = "create" } },
				{ "TaskForceHud", "TaskForceHud" },
				{ "NemesisHud", "NemesisHud" },
				{ "MentorHud", "MentorHud" },
				{ "BadgeHud", "BadgeHud" },
				{ "PassHud", "PassHud" },
				{ "BoardHud", "BoardHud" }, -- WP2: the weekly boards
			}
			-- the cards and banners the game shows on its own (each shown alone)
			local CARDS = {
				"MainMenu",
				"PvpHud",
				"Downed",
				"StoryHud",
				"WorldHud",
				"Toasts",
				"Plates",
				"Squad",
				"BoardReward",
			}
			-- parts placed only while they show, which a deep walk sees unplaced: the move stick's ring (at the
			-- finger), the guide's speaker tag (laid out with its line), the news ticker (scrolls past its TV's
			-- edge), the finisher's speed lines (drawn from the centre outwards)
			local DEEP_SKIP = { "StickRing", "Tag", "Ticker", "Line%d+" }
			local runs = table.clone(DEVICES)
			-- the smallest phone screen the reviewers check (a 640 x 360 Android)
			table.insert(runs, {
				name = "Android 640",
				w = 640,
				h = 360,
				top = 58,
				left = 0,
				right = 0,
				bottom = 0,
				touch = true,
			})
			table.insert(runs, {
				name = "iPhone 14 left-handed",
				w = 844,
				h = 390,
				top = 58,
				left = 47,
				right = 47,
				bottom = 0,
				touch = true,
				leftHanded = true,
			})
			for _, d in runs do
				local sim = UiSim.new(trees, d)
				local M = {}
				sim:run("InputController", sim:require("Client.Controllers.InputController").init)
				for _, m in MODULES do
					M[m] = sim:require("Client.Ui." .. m)
					sim:run(m, M[m].init)
				end
				if d.leftHanded then
					sim:run("leftHanded", function()
						M.Hud.setLeftHanded(true)
					end)
				end
				-- every action button shown at once (the most crowded HUD: Awaken ready, a gadget, Down in flight)
				for _, c in sim.playerGui:FindFirstChild("Hud").Cluster:GetChildren() do
					if c:IsA("GuiButton") and c.Name ~= "Catch" then
						c.Visible = true
					end
				end
				local base = { minTap = P.minTap, minText = P.minText, safe = true, textOverlap = true }
				local function report(tag: string, opts: { [string]: any })
					local o = table.clone(base)
					for k, v in opts do
						o[k] = v
					end
					for _, issue in sim:issues(o) do
						check(false, d.name .. " " .. tag .. ": " .. issue)
					end
				end
				report("HUD", {
					thumb = if d.touch
						then (if d.leftHanded then { 0.55, 0.4, 1, 1 } else { 0, 1 / 3, 0.4, 1 })
						else nil,
				})
				for _, p in PANELS do
					local args = if p[3] ~= nil then { p[3] } else {}
					local ok = sim:run(p[1] .. ".open", function()
						M[p[1]].open(table.unpack(args))
					end)
					check(ok, d.name .. ": " .. p[1] .. " opens")
					local g = sim.playerGui:FindFirstChild(p[2])
					check(g ~= nil, d.name .. ": " .. p[2] .. " screen")
					report(p[1], { minList = 90, minOrder = g and g.DisplayOrder })
					if M[p[1]].close then
						sim:run(p[1] .. ".close", M[p[1]].close)
					end
				end
				for _, screenName in CARDS do
					local g = sim.playerGui:FindFirstChild(screenName)
					check(g ~= nil, d.name .. ": " .. screenName .. " screen")
					if g then
						local was = g.Enabled
						g.Enabled = true
						report(screenName, { only = { [screenName] = true } })
						for _, c in g:GetChildren() do
							if c:IsA("GuiObject") and not c.Visible then
								c.Visible = true
								report(screenName .. "." .. c.Name, { only = { [screenName] = true } })
								c.Visible = false
							end
						end
						g.Enabled = was
					end
				end
				-- WP2: the boards screen full (50 rows, 20-character display names, you pinned), empty and
				-- in its error state, and the reward card
				local boardRows = {}
				for i = 1, 50 do
					table.insert(boardRows, {
						rank = i,
						name = string.sub("WWWWWWWWWWWWWWWWWW" .. i, 1, 20),
						value = 1000 * (60 - i),
						me = i == 7,
						friend = i % 5 == 0,
					})
				end
				local boardStates = {
					{
						"rows",
						{
							rows = boardRows,
							mine = { rank = 7, value = 123456 },
							endsIn = 300000,
							owned = true,
						},
					},
					{ "empty", { rows = {}, endsIn = 100 } },
					{ "error", { error = true } },
				}
				for _, st in boardStates do
					local ok = sim:run("BoardHud " .. st[1], function()
						M.BoardHud.open(1)
						local d = table.clone(st[2])
						d.board, d.filter = 1, 0
						M.BoardHud.receive(d)
					end)
					check(ok, d.name .. ": the boards screen draws " .. st[1])
					report("BoardHud " .. st[1], { minList = 90, minOrder = 6 })
				end
				sim:run("BoardHud.close", M.BoardHud.close)
				check(
					sim:run("BoardHud reward", function()
						M.BoardHud.reward({ board = "BossMvp", rank = 3, title = "Boss Breaker", new = true })
						M.BoardHud.reward({
							board = "PvpWins",
							rank = 10,
							title = "Crater Champion",
							new = true,
						})
					end),
					d.name .. ": the reward card draws"
				)
				report("BoardReward card", { only = { BoardReward = true } })
				sim:run("drawer", function()
					sim:require("Client.Ui.Kit").dockDrawer(true)
				end)
				report("MORE drawer", { only = { Dock = true } })
				sim:run("drawer", function()
					sim:require("Client.Ui.Kit").dockDrawer(false)
				end)
				-- every screen's hidden parts (cards, rows, sub-panels, loading and error notes), each shown with
				-- its hidden parents, inside the screen and the safe area
				if d.touch then
					for _, g in sim.playerGui:GetChildren() do
						if g:IsA("ScreenGui") and g.Name ~= "DevPanel" and g.Name ~= "KitArea" then
							local deep = sim:deepIssues(
								g,
								{ minTap = P.minTap, minText = P.minText, safe = true },
								DEEP_SKIP
							)
							for _, issue in deep do
								check(false, d.name .. " deep " .. g.Name .. ": " .. issue)
							end
						end
					end
				end
				for _, e in sim.errors do
					check(false, d.name .. ": " .. tostring(e))
				end
			end
		end
	)

	test(
		"Phone: one main panel at a time, Downed on top, pending taps, Photo Mode's key and refusals",
		function()
			local fs = require("@lune/fs")
			local roblox = require("@lune/roblox")
			local UiSim = require("./uisim")
			local Enum, Vector3 = roblox.Enum, roblox.Vector3
			local trees = UiSim.load(roblox.deserializePlace(fs.readFile(placePath)))
			local sim = UiSim.new(trees, DEVICES[1])
			local M = {}
			sim:run("InputController", sim:require("Client.Controllers.InputController").init)
			for _, m in
				{
					"Hud",
					"LoadoutScreen",
					"GearScreen",
					"MapScreen",
					"Journal",
					"PassHud",
					"ShopHud",
					"PvpHud",
					"PhotoMode",
				}
			do
				M[m] = sim:require("Client.Ui." .. m)
				sim:run(m, M[m].init)
			end
			local Kit = sim:require("Client.Ui.Kit")
			local function isOpen(m: string): boolean
				if M[m].isOpen then
					return M[m].isOpen()
				end
				return sim.playerGui:FindFirstChild("Loadout").Panel.Visible
			end
			-- GEAR and POWERS both sat at DisplayOrder 5: opening one closes the other
			sim:run("gear", M.GearScreen.open)
			sim:run("loadout", M.LoadoutScreen.open)
			check(isOpen("LoadoutScreen") and not isOpen("GearScreen"), "POWERS closes GEAR")
			sim:run("gear", M.GearScreen.open)
			check(isOpen("GearScreen") and not isOpen("LoadoutScreen"), "GEAR closes POWERS")
			sim:run("journal", M.Journal.open)
			check(isOpen("Journal") and not isOpen("GearScreen"), "JOURNAL closes GEAR")
			-- an overlay opens on top and closes nothing (the Hero Pass's BUY opens the shop)
			sim:run("pass", M.PassHud.open)
			sim:run("shop", M.ShopHud.open)
			check(
				isOpen("PassHud") and isOpen("ShopHud") and not isOpen("Journal"),
				"the shop opens over the pass"
			)
			-- going Downed closes every panel, and the Downed screen draws over the shop and settings
			sim:run("down", Kit.closePanels)
			check(not isOpen("PassHud") and not isOpen("ShopHud"), "Downed closes the panels")
			local downed = sim.playerGui:FindFirstChild("Downed")
			check(downed ~= nil and downed.DisplayOrder > 22, "the Downed screen is over settings (22)")
			-- a pending button: an earlier tap's 5 s timer leaves a later tap alone
			local b
			sim:run("button", function()
				b = Kit.button({ Text = "BUY", pending = true }, function() end)
				b.Parent = sim.playerGui:FindFirstChild("Shop")
			end)
			sim:tap(b)
			check(b.Text == "..." and b:GetAttribute("Pending") == true, "a tap waits")
			sim:advance(3)
			sim:run("settle", Kit.settle)
			check(b.Text == "BUY" and b:GetAttribute("Pending") == nil, "an answer settles it")
			sim:tap(b)
			sim:advance(2.5) -- the first tap's timer comes due here
			check(
				b.Text == "..." and b:GetAttribute("Pending") == true,
				"the old timer leaves the new tap waiting"
			)
			sim:advance(3) -- the second tap's own 5 s
			check(b.Text == "TRY AGAIN", "no answer in 5 s: TRY AGAIN")
			sim:advance(2)
			check(b.Text == "BUY" and b:GetAttribute("Pending") == nil, "then it can be tapped again")
			-- Photo Mode: its own key (K is the Task Force board), never in a cutscene or while Downed
			local char = UiSim.newInstance("Model")
			local root = UiSim.newInstance("Part")
			root.Name = "HumanoidRootPart"
			root.Parent = char
			sim.player.Character = char
			check(M.PhotoMode.KEY ~= Enum.KeyCode.K, "Photo Mode is off K")
			local uis = sim.service("UserInputService")
			local function press(key: any)
				sim:run("key", function()
					uis.InputBegan:Fire({
						KeyCode = key,
						UserInputType = Enum.UserInputType.Keyboard,
						Position = Vector3.zero,
					}, false)
				end)
			end
			press(Enum.KeyCode.K)
			check(not M.PhotoMode.isOpen(), "K does not open Photo Mode")
			local Cinema = sim:require("Client.Controllers.CinemaClient")
			Cinema.current = { owner = "test", shots = {} }
			press(M.PhotoMode.KEY)
			check(not M.PhotoMode.isOpen(), "no Photo Mode during a cutscene")
			Cinema.current = nil
			sim.player:SetAttribute("Downed", true)
			press(M.PhotoMode.KEY)
			check(not M.PhotoMode.isOpen(), "no Photo Mode while Downed")
			sim.player:SetAttribute("Downed", nil)
			press(M.PhotoMode.KEY)
			check(M.PhotoMode.isOpen(), "its key opens Photo Mode")
			sim:run("photo close", M.PhotoMode.close)
			for _, e in sim.errors do
				check(false, tostring(e))
			end
		end
	)
end
