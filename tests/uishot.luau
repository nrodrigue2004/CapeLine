-- UiShot: a picture of the real UI without Studio (the comic UI pass, 2026-11-18). Runs the game's own HUD
-- and panels headless through tests/uisim.luau and writes every drawn GuiObject (box, fill, corner, strokes,
-- text, font, rotation, draw order) to JSON; tests/uishot.py draws that JSON to a PNG. Approximate: the sim's
-- layout and text sizes, no images but Kit's halftone and the icon sheets, no UIGradient.
--
--   lune run tests/uishot.luau build/Capeline.rbxl out.json [scene ...]
--   python3 tests/uishot.py out.json out_dir [--fonts DIR]
--
-- Scenes: loading (the ReplicatedFirst loading card alone), hud (HUD and toasts), menu (the HUD with its MENU drawer open), gear, loadout, shop, settings, journal, map, creator, pass (each panel over
-- the HUD), world (the HUD with incidents, an event, a contract, a boss fight and its result card), contracts
-- (the Contract Board), badges (the Badge Book), daily (the daily card), screen:<ScreenGui name> (a card screen with all its parts shown),
-- emotes (the emote picker), photo (Photo Mode on a pose), shop:emotes (the shop's Emotes tab),
-- comic:<page id> (a comic page from Config.Cinema.comic.pages with every panel in), guide:<speaker> (the guide line
-- box with that speaker's portrait), news:<boss id> or news:double (the corner TV and a name card), villain:<card name, _ for spaces> (a side quest finale's name card). UISHOT_IMAGES=<ids.json> lets tests/uishot.py draw uploaded images from their local files.

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local UiSim = require("./uisim")

local Enum = roblox.Enum

local placePath = process.args[1] or "build/Capeline.rbxl"
local outPath = process.args[2] or "build/uishot.json"
local scenes = { table.unpack(process.args, 3) }
if #scenes == 0 then
	scenes = { "hud", "gear", "loadout", "shop", "settings" }
end

local DEVICE =
	{ name = "PC 720p", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = true }
-- UISHOT_SIZE=667x375 draws another screen size (under 500 px tall is a phone: the compact HUD)
local size = process.env.UISHOT_SIZE
if size then
	local w, h = string.match(size, "^(%d+)x(%d+)$")
	if w then
		DEVICE.w, DEVICE.h = tonumber(w) :: number, tonumber(h) :: number
	end
end
-- UISHOT_PC=1 draws a mouse-and-keyboard screen (no touch buttons); UISHOT_ALL=0 leaves the action buttons as
-- the game shows them (else every one is shown: the most crowded HUD)
DEVICE.touch = process.env.UISHOT_PC ~= "1"
local showAll = process.env.UISHOT_ALL ~= "0"

local trees = UiSim.load(roblox.deserializePlace(fs.readFile(placePath)))

local function rgb(c: any): { number }
	return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end

local function prop(inst: any, key: string): any
	local ok, v = pcall(function()
		return inst[key]
	end)
	return if ok then v else nil
end

local function enumName(v: any): string?
	if v == nil then
		return nil
	end
	return tostring(v):match("([^%.]+)$")
end

-- One drawn object as plain data
local function node(b: any): { [string]: any }
	local i = b.inst
	local n: { [string]: any } = {
		name = i.Name,
		class = i._class,
		x = b.x,
		y = b.y,
		w = b.w,
		h = b.h,
		scale = b.scale,
		z = prop(i, "ZIndex") or 1,
		rot = prop(i, "Rotation") or 0,
		clip = prop(i, "ClipsDescendants") == true,
		deco = b.deco == true,
		bg = rgb(prop(i, "BackgroundColor3") or roblox.Color3.new(1, 1, 1)),
		bgT = prop(i, "BackgroundTransparency") or 0,
		kids = {},
	}
	for _, c in i._children do
		if c._class == "UICorner" then
			local r = c.CornerRadius
			n.corner = { r.Scale, r.Offset }
		elseif c._class == "UIStroke" and c.Enabled ~= false and c.Thickness > 0 then
			n.strokes = n.strokes or {}
			table.insert(n.strokes, {
				color = rgb(c.Color),
				t = c.Thickness,
				tr = c.Transparency,
				mode = enumName(c.ApplyStrokeMode),
			})
		elseif c._class == "UIGradient" and c.Enabled ~= false then
			n.gradient = true
		end
	end
	if b.text then
		n.text = prop(i, "Text")
		n.size = b.text
		n.font = enumName(prop(i, "Font"))
		n.color = rgb(prop(i, "TextColor3"))
		n.textT = prop(i, "TextTransparency") or 0
		n.strokeT = prop(i, "TextStrokeTransparency") or 1
		n.strokeC = rgb(prop(i, "TextStrokeColor3") or roblox.Color3.new())
		n.ax = enumName(prop(i, "TextXAlignment"))
		n.ay = enumName(prop(i, "TextYAlignment"))
		n.wrap = prop(i, "TextWrapped") == true
		local pad = nil
		for _, c in i._children do
			if c._class == "UIPadding" then
				pad = c
			end
		end
		if pad then
			n.pad = {
				pad.PaddingLeft.Offset * b.scale,
				pad.PaddingTop.Offset * b.scale,
				pad.PaddingRight.Offset * b.scale,
				pad.PaddingBottom.Offset * b.scale,
			}
		end
	end
	if i:IsA("ImageLabel") or i:IsA("ImageButton") then
		n.image = prop(i, "Image")
		n.imageT = prop(i, "ImageTransparency") or 0
		n.imageC = rgb(prop(i, "ImageColor3") or roblox.Color3.new(1, 1, 1))
		n.tile = prop(i, "ScaleType") == Enum.ScaleType.Tile
		local t = prop(i, "TileSize")
		if t then
			n.tileSize = { t.X.Offset, t.Y.Offset }
			n.tileScale = { t.X.Scale, t.Y.Scale }
		end
		n.halftone = i:GetAttribute("Halftone") == true
		n.crop = prop(i, "ScaleType") == Enum.ScaleType.Crop
		-- a sprite sheet cell (the icon set, gap-icons): uishot.py draws it from art/export/icons
		-- or a picture tile's cell of a sheet (Ui.Thumb): drawn by uishot.py --images from the local sheet
		local ro, rs = prop(i, "ImageRectOffset"), prop(i, "ImageRectSize")
		if ro and rs and rs.X > 0 then
			n.rect = { ro.X, ro.Y, rs.X, rs.Y }
		end
		n.visible = prop(i, "Visible") ~= false
		n.fit = prop(i, "ScaleType") == Enum.ScaleType.Fit
		if prop(i, "ScaleType") == Enum.ScaleType.Slice then
			local sc = prop(i, "SliceCenter")
			n.slice = { sc.Min.X, sc.Min.Y, sc.Max.X, sc.Max.Y }
			n.sliceScale = (prop(i, "SliceScale") or 1) * (b.scale or 1)
		end
	end
	if i:IsA("ViewportFrame") then
		n.viewport = true
	end
	return n
end

-- The boxes as a tree in draw order (screens by DisplayOrder, siblings by ZIndex then order)
local function capture(sim: any): { [string]: any }
	local boxes = sim:boxes()
	local byInst = {}
	local roots = {}
	for idx, b in boxes do
		local n = node(b)
		n.order = idx
		byInst[b.inst] = n
	end
	for _, b in boxes do
		local n = byInst[b.inst]
		local p = b.inst._parent
		while p and not byInst[p] and not p:IsA("ScreenGui") do
			p = p._parent
		end
		if p and byInst[p] then
			table.insert(byInst[p].kids, n)
		else
			n.screen = b.screen.Name
			n.displayOrder = b.screen.DisplayOrder
			table.insert(roots, n)
		end
	end
	local function sortKids(list: { any })
		table.sort(list, function(a, b)
			if a.z ~= b.z then
				return a.z < b.z
			end
			return a.order < b.order
		end)
		for _, k in list do
			sortKids(k.kids)
		end
	end
	sortKids(roots)
	table.sort(roots, function(a, b)
		if a.displayOrder ~= b.displayOrder then
			return a.displayOrder < b.displayOrder
		end
		if a.screen ~= b.screen then
			return a.screen < b.screen
		end
		if a.z ~= b.z then
			return a.z < b.z
		end
		return a.order < b.order
	end)
	return { w = DEVICE.w, h = DEVICE.h, roots = roots }
end

local MODULES = {
	"Hud",
	"Toasts",
	"Radar",
	"WorldHud",
	"GearScreen",
	"LoadoutScreen",
	"ShopHud",
	"SettingsMenu",
	"Journal",
	"MapScreen",
	"CreatorScreen",
	"PassHud",
	"StoryHud",
	"PvpHud",
	"DailyHud",
	"BoardHud",
	"SquadHud",
	"MainMenu",
	"ContractBoard",
	"BadgeHud",
}
-- a scene's panel and what its open() takes
local PANEL = {
	gear = { "GearScreen" },
	loadout = { "LoadoutScreen" },
	shop = { "ShopHud" },
	settings = { "SettingsMenu" },
	journal = { "Journal" },
	map = { "MapScreen" },
	creator = { "CreatorScreen", { mode = "create" } },
	-- the creator's APPEARANCE step on one slot's picture tiles (2026-11-19 thumbnails)
	["creator:suit"] = { "CreatorScreen", { mode = "create", step = "appearance", slot = "suit" } },
	["creator:head"] = { "CreatorScreen", { mode = "create", step = "appearance", slot = "head" } },
	["creator:visage"] = { "CreatorScreen", { mode = "create", step = "appearance", slot = "visage" } },
	["creator:hair"] = { "CreatorScreen", { mode = "create", step = "appearance", slot = "hair" } },
	["creator:weapon"] = { "CreatorScreen", { mode = "create", step = "weapon" } },
	-- fix-flow (2026-11-19): the Body step back (gender, build, height)
	["creator:body"] = { "CreatorScreen", { mode = "create", step = "body" } },
	pass = { "PassHud" },
	-- the shop's Emotes tab (2026-11-19 pose tiles)
	["shop:emotes"] = { "ShopHud", "emotes" },
}

-- The map scene (the map pass, 2026-11-19): the server's WorldInfo for one seed, built the way CityBuilder
-- publishes it, some beacons and safehouses found, and the map's pictures from art/export/map (their real ids
-- once uploaded, else stand-in ids) so uishot.py draws them. UISHOT_MAPZOOM=2.5 shows the map zoomed in on you.
local mapImages: { [string]: string } = {}
local function mapWorld(sim: any)
	local Config = require("../src/config")
	local WorldMap = require("../src/shared/WorldMap")
	local world = WorldMap.build(Config, 202647)
	local info = { seed = world.seed, safehouses = {}, beacons = {}, landmarks = {}, hq = {} }
	for id, sh in world.safehouses do
		table.insert(info.safehouses, { id = id, name = sh.name, x = sh.x, z = sh.z })
	end
	for id, b in world.beacons do
		table.insert(info.beacons, { id = id, name = b.name, x = b.x, y = b.y, z = b.z })
	end
	for _, lm in world.landmarks do
		table.insert(info.landmarks, { id = lm.id, x = lm.centre.x, z = lm.centre.z, size = lm.size })
	end
	info.hq = {
		{ side = "hero", x = world.downtown.beacon.x - 80, z = world.downtown.beacon.z },
		{ side = "villain", x = world.spots.foundry.x, z = world.spots.foundry.z },
	}
	local s = UiSim.newInstance("StringValue")
	s.Name = "WorldInfo"
	s.Value = serde.encode("json", info)
	s.Parent = sim.service("ReplicatedStorage")
	-- some found: beacons 1 to 4, safehouses 1 to 6
	local State = sim:require("Client.State")
	State.profile.beacons = 15
	State.profile.safehouses = 63
	local cfg = sim:require("Config")
	local fakeId = 990000
	local function wire(tbl: any, key: string, file: string)
		local id = tbl[key]
		if id == 0 then
			fakeId += 1
			id = fakeId
			tbl[key] = id
		end
		mapImages["rbxassetid://" .. id] = "art/export/map/" .. file
	end
	wire(cfg.MapArt.city, "Hub", "Hub.png")
	wire(cfg.MapArt.city, "Uptown", "Uptown.png")
	for key, file in
		{ suburbs = "Suburbs.png", farmland = "Farmland.png", coast = "Coast.png", landmark = "Landmark.png" }
	do
		wire(cfg.MapArt.patterns, key, file)
	end
end

-- gap-icons2: sample world state (3 incidents, an event, a contract and a boss fight) for the world and map scenes;
-- result: also fire the boss result card
local function worldData(sim: any, result: boolean)
	local WC = sim:require("Client.Controllers.WorldClient")
	local cfg = sim:require("Config")
	local num = function(tbl: any, id: string): number
		return tbl[id].num
	end
	local V3 = roblox.Vector3
	local tids = { "TowerFire", "RobotHeist", "CatOnCrane" }
	for i, tid in tids do
		WC.incidents[i] = {
			id = i,
			num = num(cfg.Incidents.templates, tid),
			tid = tid,
			pos = V3.new(20 * i, 0, -40 * i),
			side = if i == 2 then "villain" else "hero",
			level = 5,
			deadline = os.clock() + 80,
			own = i == 1,
			steps = 2,
			step = 1,
			frac = 0.4,
			have = 1,
			need = 3,
			state = WC.ACTIVE,
			medal = 0,
		}
	end
	WC.events[1] = {
		id = "TidalSurge",
		state = 0,
		x = 120,
		z = -200,
		have = 4,
		need = 12,
		ends = os.clock() + 200,
	}
	WC.contracts = { { num(cfg.Contracts.types, "VaultJob"), 1, 2, 120, 30, -40, 0, 0, 0 } }
	WC.boss = {
		state = 3,
		id = "RustjawPrime",
		num = 1,
		x = -100,
		y = 0,
		z = 150,
		hp = 600000,
		max = 1000000,
		phase = 2,
		level = 30,
		at = 300,
		received = os.clock(),
		objectives = { 1, 1, 0 },
	}
	if not result then
		return
	end
	WC.BossResult:Fire({
		num = cfg.Boss.bosses.RustjawPrime.num,
		defeated = true,
		tier = "mvp",
		rank = 2,
		credits = 1200,
		renown = 300,
		drops = 1,
	})
end

local out = {}
for _, scene in scenes do
	local sim = UiSim.new(trees, DEVICE)
	if scene == "loading" then
		-- the loading splash on its own (gap polish 2026-11-19), as LoadingScreen builds it
		sim:run("loading", function()
			local gui = UiSim.newInstance("ScreenGui")
			gui.Name = "Loading"
			gui.IgnoreGuiInset = true
			gui.DisplayOrder = 100
			sim:require("First.LoadingCard").build(gui)
			gui.Parent = sim.playerGui
		end)
	else
		local M = {}
		sim:run("InputController", sim:require("Client.Controllers.InputController").init)
		for _, m in MODULES do
			M[m] = sim:require("Client.Ui." .. m)
			sim:run(m, M[m].init)
		end
		sim:advance(0.5)
		-- every action button shown (the most crowded HUD, as tests/phone_test.luau checks it)
		for _, c in sim.playerGui:FindFirstChild("Hud").Cluster:GetChildren() do
			if showAll and c:IsA("GuiButton") and c.Name ~= "Catch" then
				c.Visible = true
			end
		end
		if scene == "hud" then
			sim:run("toasts", function()
				M.Toasts.show({ id = "levelUp", level = 12 })
				M.Toasts.show({ id = "pvpOff" })
				M.Toasts.show({
					id = "loot",
					piece = {
						id = 9,
						slot = 2,
						tier = 4,
						ilvl = 21,
						up = 0,
						main = 2,
						bonus = {},
						set = 0,
						perk = 0,
						gadget = 0,
						style = 0,
						retunes = 0,
						seed = 9,
					},
				})
			end)
		elseif scene == "busy" then
			-- pt-ui (2026-11-19, nate: "too many popups at once"): the busiest moment: a world boss falls while a
			-- contest votes, a squad invite and a news name card come in, the level goes up, three drops, rewards,
			-- an incident clears and the stamps fly, all in the same second
			sim:run("busy", function()
				sim:require("Client.Fx.JuiceFx").init()
				sim:require("Client.Ui.GuideHud").init()
				sim:require("Client.Ui.CinemaHud").init()
				sim:require("Client.Ui.NewsHud").init()
				sim:require("Client.Ui.ContestHud").init()
				worldData(sim, true)
				local remotes = sim.service("ReplicatedStorage"):WaitForChild("Remotes")
				local ev = remotes:FindFirstChild("ContestState")
				if ev then
					ev.OnClientEvent:Fire({
						phase = "vote",
						theme = "Neon Nights",
						entries = { { id = 7, name = "Bolt" }, { id = 8, name = "Nova" } },
						endsAt = os.time() + 15,
						now = os.time(),
						top = {},
					})
				end
				sim:require("Client.Controllers.SquadClient").Invited
					:Fire({ from = 9, name = "Tempest", size = 2 })
				sim:require("Client.Ui.NewsHud").nameCard("RustjawPrime")
				local function piece(id: number, tier: number): { [string]: any }
					return {
						id = id,
						slot = id % 8 + 1,
						tier = tier,
						ilvl = 20 + id,
						up = 0,
						main = 1,
						bonus = {},
						set = 0,
						perk = 0,
						gadget = 0,
						style = 0,
						retunes = 0,
						seed = id,
					}
				end
				M.Toasts.show({ id = "levelUp", level = 12 })
				M.Toasts.show({ id = "incident", name = "Tower Fire", medal = "gold" })
				for i = 1, 3 do
					M.Toasts.show({ id = "loot", piece = piece(i, if i == 1 then 4 else 2) })
					M.Toasts.show({ id = "reward", credits = 120 * i, renown = 30 * i })
				end
				M.Toasts.show({ id = "sqStep", bit = 1, step = 2 })
				M.Toasts.show({ id = "badgeMate", who = "Nova", name = "First Flight" })
				M.Toasts.show({ id = "pvpOff" })
				sim:require("Client.Fx.Juice").fire("contractDone", nil, { name = "VAULT JOB" })
				sim:require("Client.Fx.Juice").fire("badgeEarned", nil, { name = "Night Owl", mine = true })
			end)
		elseif scene == "world" or scene == "contracts" or scene == "badges" or scene == "daily" then
			-- gap-icons2: the open world and the books with sample data (their comic icons)
			sim:run(scene, function()
				local cfg = sim:require("Config")
				local num = function(tbl: any, id: string): number
					return tbl[id].num
				end
				if scene == "world" then
					worldData(sim, true)
					-- a hero standing at the origin, so the radar and the distances have a centre
					local char = UiSim.newInstance("Model")
					char.Name = "Tester"
					local root = UiSim.newInstance("Part")
					root.Name = "HumanoidRootPart"
					root.CFrame = roblox.CFrame.new(0, 0, 0)
					root.Parent = char
					char.Parent = sim.service("Workspace")
					sim.player.Character = char
					local rs = sim.service("RunService")
					rs.Heartbeat:Fire(0.3)
					rs.RenderStepped:Fire(0.2)
				elseif scene == "contracts" then
					local CT = cfg.Contracts.types
					M.ContractBoard.open({
						offers = {
							{ num(CT, "DroneSweep"), 12, 800, 120, 0, 0, 0 },
							{ num(CT, "RescueRun"), 12, 900, 140, 0, 1, 0 },
							{ num(CT, "PhotoRecon"), 12, 700, 110, 1, 0, 0 },
						},
						active = { { num(CT, "GeneratorHold"), 20, 60, 12, 0, 0 } },
						done = 2,
					})
				elseif scene == "badges" then
					M.BadgeHud.apply({
						bits = { 0, 1, 2, 40 },
						progress = {},
						collect = { 0, 1, 2 },
						titles = {},
						accolades = { 1, 3 },
						aura = 1,
						trim = 0,
						scanner = 0,
					})
					M.BadgeHud.open(process.env.UISHOT_BADGES or "badges")
				else
					local days = {}
					for i, r in
						{
							{ credits = 500 },
							{ renown = 50 },
							{ dust = 20 },
							{ credits = 800 },
							{ renown = 100 },
							{ dust = 40 },
							{ title = 1, renown = 200 },
						}
					do
						r.state = if i < 4 then "got" elseif i == 4 then "ready" else "later"
						days[i] = r
					end
					M.DailyHud.open({ streak = 3, best = 5, day = 4, days = days, owed = true, quests = {} })
				end
			end)
		elseif string.sub(scene, 1, 7) == "screen:" then
			-- a card screen shown whole, every part at once (as tests/phone_test.luau's cards check)
			local g = sim.playerGui:FindFirstChild(string.sub(scene, 8))
			if g then
				g.Enabled = true
				for _, c in g:GetChildren() do
					if c:IsA("GuiObject") then
						c.Visible = true
					end
				end
			end
		elseif string.sub(scene, 1, 6) == "comic:" or string.sub(scene, 1, 8) == "villain:" then
			-- a comic page with every panel in (as CinemaHud slides them in over the scene's seconds); or
			-- (gap-villains) a side quest finale's name card, villain:<card name, _ for spaces>, with its portrait
			-- (opened after the drawn frame below: with no scene playing, CinemaHud's frame closes a page)
			sim:run(scene, function()
				sim:require("Client.Ui.GuideHud").init()
				sim:require("Client.Ui.CinemaHud").init()
			end)
		elseif string.sub(scene, 1, 5) == "news:" then
			-- gap-news: the corner TV and a name card (news:<boss id> its card, news:double Your double's)
			sim:run(scene, function()
				sim:require("Client.Ui.GuideHud").init()
				sim:require("Client.Ui.CinemaHud").init()
				sim:require("Client.Ui.NewsHud").init()
			end)
		elseif scene == "qte" then
			-- fix-flow (2026-11-19): a quick-time prompt of the prologue's rooftop chase over the HUD (a DODGE half way)
			sim:run("qte", function()
				local QteHud = sim:require("Client.Ui.QteHud")
				QteHud.init()
				QteHud.sample()
			end)
		elseif string.sub(scene, 1, 6) == "guide:" then
			sim:run(scene, function()
				local GuideHud = sim:require("Client.Ui.GuideHud")
				GuideHud.init()
				GuideHud.sample(string.sub(scene, 7))
			end)
		elseif scene == "emotes" or scene == "photo" then
			-- the emote picker with a few owned emotes, or Photo Mode on its third pose (2026-11-19 pose tiles)
			local State = sim:require("Client.State")
			State.profile.emotes = { 1, 3, 5, 8, 11, 18 }
			if scene == "emotes" then
				local EmoteFx = sim:require("Client.Fx.EmoteFx")
				sim:run("EmoteFx", EmoteFx.init)
				sim:run("picker", EmoteFx.toggle)
			else
				local PhotoMode = sim:require("Client.Ui.PhotoMode")
				sim:run("PhotoMode", PhotoMode.init)
				-- (no hero in the sim, so open() stays shut: show its bar the way open() does)
				local g = sim.playerGui:FindFirstChild("Photo")
				for _, d in (g and g:GetDescendants() or {}) do
					if d:IsA("GuiObject") then
						d.Visible = d.Name ~= "PHOTO" and not (d:IsA("TextButton") and d.Text == "PHOTO")
					end
				end
				for _, d in (g and g:GetDescendants() or {}) do
					if d:IsA("TextButton") and d.Text == "POSE" then
						sim:run("pose", function()
							for _ = 1, 3 do
								d.Activated:Fire()
							end
						end)
						break
					end
				end
			end
		elseif PANEL[scene] then
			local p = PANEL[scene]
			if scene == "map" then
				mapWorld(sim)
				worldData(sim, false)
			end
			if scene == "gear" then
				-- a few pieces in the stash, two worn, one picked (the gear cards' icons, gap-icons)
				local State = sim:require("Client.State")
				local function piece(id: number, slot: number, tier: number): { [string]: any }
					return {
						id = id,
						slot = slot,
						tier = tier,
						ilvl = 10 + id,
						up = 0,
						main = 1,
						bonus = {},
						set = 0,
						perk = 0,
						gadget = if slot == 8 then 1 else 0,
						style = 0,
						retunes = 0,
						seed = id,
					}
				end
				State.profile.stash = {
					piece(1, 1, 5),
					piece(2, 2, 4),
					piece(3, 3, 3),
					piece(4, 5, 2),
					piece(5, 6, 1),
					piece(6, 8, 3),
				}
				State.profile.equipment[1] = 1
				State.profile.equipment[2] = 2
			end
			sim:run(scene, function()
				M[p[1]].open(p[2])
			end)
		end
		sim:advance(1)
		-- one drawn frame, so the per-frame HUD (bars, situational buttons, the key line) is as the game shows it
		sim:run("frame", function()
			sim.service("RunService").RenderStepped:Fire(1 / 60)
		end)
		sim:run("dock", sim:require("Client.Ui.Kit").layoutDock)
		if string.sub(scene, 1, 6) == "comic:" then
			sim:run("page", function()
				sim:require("Client.Ui.CinemaHud").showPage(string.sub(scene, 7))
			end)
			local g = sim.playerGui:FindFirstChild("ComicPage")
			for _, c in (g and g:FindFirstChild("Page") or sim.playerGui):GetChildren() do
				if c:IsA("Frame") and string.sub(c.Name, 1, 5) == "Panel" then
					c.Visible = true
				end
			end
		end
		if string.sub(scene, 1, 5) == "news:" then
			sim:run("news", function()
				local NewsHud = sim:require("Client.Ui.NewsHud")
				local who = string.sub(scene, 6)
				NewsHud.crane()
				if who == "double" then
					NewsHud.card("events", "YourDouble")
				else
					NewsHud.nameCard(who)
				end
			end)
			sim:advance(0.5)
			-- one more drawn frame: NewsHud keeps the corner TV clear of the name card on its frame
			sim:run("newsframe", function()
				sim.service("RunService").RenderStepped:Fire(1 / 60)
			end)
		end
		if string.sub(scene, 1, 8) == "villain:" then
			sim:run("villain", function()
				local name = string.gsub(string.sub(scene, 9), "_", " ")
				local title = ""
				for _, chain in sim:require("Config").SideQuests.chains do
					if type(chain.villain) == "table" and chain.villain.name == name then
						title = chain.villain.title
					end
				end
				sim:require("Client.Ui.CinemaHud").nameCard("", name, title)
			end)
			sim:advance(0.5)
		end
		if scene == "menu" then
			sim:run("menu", function()
				sim:require("Client.Ui.Kit").dockDrawer(true)
			end)
		end
	end
	if scene == "map" and process.env.UISHOT_MAPZOOM then
		sim:run("zoom", function()
			local MS = sim:require("Client.Ui.MapScreen")
			-- over the plaza, between Downtown, Old Town and the Docks
			MS.lookAt(-150, 0, tonumber(process.env.UISHOT_MAPZOOM) or 2)
		end)
	end
	local shot = capture(sim)
	shot.images = if scene == "map" then mapImages else nil
	shot.scene = string.gsub(scene, ":", "_")
	shot.errors = {}
	for _, e in sim.errors do
		table.insert(shot.errors, tostring(e))
	end
	table.insert(out, shot)
	print(string.format("%s: %d roots, %d errors", scene, #shot.roots, #shot.errors))
end
fs.writeFile(outPath, serde.encode("json", out))
