-- UiShot: a picture of the real UI without Studio (the comic UI pass, 2026-11-18). Runs the game's own HUD
-- and panels headless through tests/uisim.luau and writes every drawn GuiObject (box, fill, corner, strokes,
-- text, font, rotation, draw order) to JSON; tests/uishot.py draws that JSON to a PNG. Approximate: the sim's
-- layout and text sizes, no images but Kit's halftone, no UIGradient.
--
--   lune run tests/uishot.luau build/Capeline.rbxl out.json [scene ...]
--   python3 tests/uishot.py out.json out_dir [--fonts DIR]
--
-- Scenes: hud (HUD and toasts), menu (the HUD with its MENU drawer open), gear, loadout, shop, settings, journal, map, creator, pass (each panel over
-- the HUD), screen:<ScreenGui name> (a card screen with all its parts shown), comic:<page id> (a comic page from
-- Config.Cinema.comic.pages with every panel in), guide:<speaker> (the guide line box with that speaker's
-- portrait). UISHOT_IMAGES=<ids.json> lets tests/uishot.py draw uploaded images from their local files.

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
		end
		n.halftone = i:GetAttribute("Halftone") == true
		n.crop = prop(i, "ScaleType") == Enum.ScaleType.Crop
		local ro, rs = prop(i, "ImageRectOffset"), prop(i, "ImageRectSize")
		if rs and rs.X > 0 then
			n.rect = { ro.X, ro.Y, rs.X, rs.Y }
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
	pass = { "PassHud" },
}

local out = {}
for _, scene in scenes do
	local sim = UiSim.new(trees, DEVICE)
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
	elseif string.sub(scene, 1, 6) == "comic:" then
		-- a comic page with every panel in (as CinemaHud slides them in over the scene's seconds)
		-- (opened after the drawn frame below: with no scene playing, CinemaHud's frame closes a page)
		sim:run(scene, function()
			sim:require("Client.Ui.GuideHud").init()
			sim:require("Client.Ui.CinemaHud").init()
		end)
	elseif string.sub(scene, 1, 6) == "guide:" then
		sim:run(scene, function()
			local GuideHud = sim:require("Client.Ui.GuideHud")
			GuideHud.init()
			GuideHud.sample(string.sub(scene, 7))
		end)
	elseif PANEL[scene] then
		local p = PANEL[scene]
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
	if scene == "menu" then
		sim:run("menu", function()
			sim:require("Client.Ui.Kit").dockDrawer(true)
		end)
	end
	local shot = capture(sim)
	shot.scene = string.gsub(scene, ":", "_")
	shot.errors = {}
	for _, e in sim.errors do
		table.insert(shot.errors, tostring(e))
	end
	table.insert(out, shot)
	print(string.format("%s: %d roots, %d errors", scene, #shot.roots, #shot.errors))
end
fs.writeFile(outPath, serde.encode("json", out))
