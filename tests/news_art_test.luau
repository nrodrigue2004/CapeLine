-- The in-city news's art pass (gap-news, 2026-11-19): the big screens' Blender looks over NewsService's plain
-- parts (art/blender/screens.py, Config.ScreenArt, Shared.NewsArtKit, Art.News) and the HUD's comic art (the boss
-- name card portraits and plate, the corner TV case, the channel's mark: art/news/post.py, Config.NewsArt).
-- Called from tests/run.luau:
--   require("./news_art_test")({ test = test, check = check, Config = Config, placePath = placePath })
-- ONLY="News art" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local NewsArtKit = require("../src/shared/NewsArtKit")
	local FIT = Config.ScreenArt
	local A = Config.NewsArt

	local function src(path: string): string
		return fs.readFile(path)
	end
	local function has(text: string, needle: string): boolean
		return string.find(text, needle, 1, true) ~= nil
	end
	-- a number assigned in a Python script (NAME = (a, b) or NAME = a)
	local function pyNums(text: string, name: string): { number }
		local line = string.match(text, "\n" .. name .. " = ([^\n]+)") or ""
		local out = {}
		for n in string.gmatch(line, "[%d%.]+") do
			table.insert(out, tonumber(n) :: number)
		end
		return out
	end

	test("News art: every screen kind has a look with fit data, in the phone budget", function()
		check(type(FIT) == "table", "Config.ScreenArt is indexed")
		local total = 0
		for kind, row in NewsArtKit.LOOKS do
			local fit = FIT and FIT[row.look]
			check(type(fit) == "table" and next(fit) ~= nil, kind .. " has its look " .. row.look)
			local textured = 0
			for name, m in fit or {} do
				check(string.sub(name, 1, #row.look) == row.look, name .. " is named after its look")
				check(type(m.tris) == "number" and m.tris > 0, name .. " has triangles")
				total += m.tris or 0
				if m.maps then
					textured += 1
				end
			end
			check(textured >= 1, row.look .. " has a baked texture set")
		end
		-- five screens a server (1 plaza, 3 towers, 1 Uptown): every look's triangles under 8k, all under 32k
		for _, row in NewsArtKit.LOOKS do
			local n = 0
			for _, m in FIT[row.look] or {} do
				n += m.tris
			end
			check(n < 8000, string.format("%s: %d triangles (8k a look)", row.look, n))
		end
		check(total < 20000, string.format("%d triangles in all", total))
		local bad = NewsArtKit.check(Config)
		check(#bad == 0, "the looks fit their screens: " .. table.concat(bad, "; "))
	end)

	test("News art: the script's numbers still match Config's screens", function()
		local py = src("art/blender/screens.py")
		local S = Config.Cinema.news.screens
		local p, t, u = pyNums(py, "PLAZA"), pyNums(py, "TOWER"), pyNums(py, "UPTOWN")
		check(p[1] == S.plaza.size[1] and p[2] == S.plaza.size[2], "the plaza screen's size")
		check(pyNums(py, "PLAZA_HEIGHT")[1] == S.plaza.height, "the plaza screen's height")
		check(t[1] == S.size[1] and t[2] == S.size[2], "a tower screen's size")
		check(u[1] == S.uptown.size[1] and u[2] == S.uptown.size[2], "the Uptown billboard's size")
		check(pyNums(py, "WALL")[1] == NewsArtKit.WALL, "the wall behind")
		-- NewsPlan.screens still hangs a screen half + 1 off its building and the plaza's legs 1.5 in from its sides
		local plan = src("src/shared/NewsPlan.luau")
		check(has(plan, "x = b.x + nx * (half + 1),"), "a tower screen 1 stud off the wall")
		local svc = src("src/server/Services/NewsService.luau")
		check(has(svc, "side * (s.w / 2 - 1.5)"), "the plaza's legs where the pillars stand")
		check(pyNums(py, "LEG_X")[1] == 1.5, "the script's pillars")
	end)

	test("News art: NewsService dresses the screens without changing them", function()
		local svc = src("src/server/Services/NewsService.luau")
		check(has(svc, "NewsArtKit.ready(Config, look"), "a look only once every mesh is there")
		check(has(svc, "p.CanCollide = false") and has(svc, "p.CanQuery = false"), "the meshes never collide")
		check(has(svc, "p.CanTouch = false"), "or touch")
		check(not has(svc, "CanCollide = true"), "nothing made solid")
		check(has(svc, "if #dressed > 0 then"), "the plain frame and legs hide only when drawn")
		-- the screen part itself is untouched: same size, the Kind attribute NewsHud attaches to, the dark collapse
		check(has(svc, 'screen:SetAttribute("Kind", s.kind)'), "the screen keeps its Kind")
		check(has(svc, "s.part.Transparency = if down then 1 else 0"), "a collapse still darkens the screen")
		check(has(svc, "for _, p in s.dressed do"), "and its look")
		local hud = src("src/client/Ui/NewsHud.luau")
		check(has(hud, 'p:IsA("BasePart") and p:GetAttribute("Kind")'), "NewsHud attaches only to screens")
	end)

	test("News art: the HUD's images, their fallbacks and no words baked in", function()
		check(type(A) == "table", "Config.NewsArt is indexed")
		-- every boss on Config.Cinema.nameCard has a portrait cell
		for id in Config.Cinema.nameCard.titles do
			check(A.cards.at[id] ~= nil, id .. " has a card portrait")
		end
		check(
			A.cards.sheet > 0 and A.plate.id > 0 and A.tv.id > 0 and A.ident.id > 0,
			"every image is uploaded"
		)
		local cell = NewsArtKit.portrait(Config, "LumenMaw")
		check(cell ~= nil and cell.size[1] == A.cards.cell, "a portrait's cell")
		-- every place card has its picture (list-combat, Everything Left 403), in a cell no boss uses
		for id in Config.Cinema.nameCard.places do
			local pc = NewsArtKit.place(Config, id)
			check(pc ~= nil and pc.size[1] == A.cards.cell, id .. " has its place picture")
			local at = A.cards.places[id]
			for bid, bat in A.cards.at do
				check(
					not (at and bat[1] == at[1] and bat[2] == at[2] and (bat[3] or 1) == (at[3] or 1)),
					id .. " does not share " .. bid .. "'s cell"
				)
			end
		end
		check(
			string.find(src("src/client/Ui/NewsHud.luau"), '{ kind = "place", id = id }', 1, true) ~= nil,
			"a place's card asks for its picture"
		)
		local img, size, win = NewsArtKit.tv(Config)
		check(img ~= nil and size ~= nil and win ~= nil, "the TV case")
		if win then
			check(
				win[1] > 0 and win[2] > 0 and win[1] + win[3] < 1 and win[2] + win[4] < 1,
				"its window inside"
			)
			-- the window keeps today's screen's shape (230 x 122) within a tenth
			local aspect = (win[3] * A.tv.size[1]) / (win[4] * A.tv.size[2])
			check(math.abs(aspect - 230 / 122) < 0.19, string.format("the window's shape %.2f", aspect))
		end
		local _, psize, slice = NewsArtKit.plate(Config)
		check(psize ~= nil and slice ~= nil and slice[1] + slice[3] < psize[1], "the plate's 9-slice")
		-- an id of 0 answers nil (today's frames)
		local zero = { NewsArt = { cards = { sheet = 0, cell = 512, at = A.cards.at }, plate = { id = 0 } } }
		check(NewsArtKit.portrait(zero, "LumenMaw") == nil, "no sheet, no portrait")
		check(NewsArtKit.plate(zero) == nil, "no plate")
		check(NewsArtKit.ident(zero) == nil and NewsArtKit.tv(zero) == nil, "no TV art")
		-- the backdrop colours are the bosses' card colours (Config.BossArt theme)
		local post = src("art/news/post.py")
		for id, art in Config.BossArt do
			if type(art) == "table" and art.theme then
				local t = art.theme
				check(
					has(post, string.format('("%s", (%d, %d, %d))', id, t[1], t[2], t[3])),
					id .. "'s portrait in its card colour"
				)
			end
		end
		-- the pictures carry no words (the channel name and every line stay UI text) and draw no person
		check(not has(post, "d.text("), "post.py draws no text")
		check(not has(src("art/blender/screens.py"), "body.text"), "the screens' meshes carry no text")
		-- the HUD keeps today's frames when an id is 0
		local cine = src("src/client/Ui/CinemaHud.luau")
		check(has(cine, "if plate and size and slice then"), "the plain card without the plate")
		check(has(cine, "cardPic.Visible = shown"), "no picture, no gap")
		local hud = src("src/client/Ui/NewsHud.luau")
		check(has(hud, "if case and caseSize and window then"), "the plain TV without the case")
		check(has(hud, "tvScreen = tv"), "today's TV is its own screen")
	end)

	if T.placePath then
		test("News art: Art.News is in the place, every mesh uploaded, textures kept", function()
			local roblox = require("@lune/roblox")
			local game = roblox.deserializePlace(fs.readFile(T.placePath))
			local art = game:GetService("ReplicatedStorage"):FindFirstChild("Art")
			local set = art and art:FindFirstChild("News")
			check(set ~= nil, "ReplicatedStorage.Art.News")
			if not set then
				return
			end
			for look, fit in FIT do
				for name, row in fit do
					local m = set:FindFirstChild(name, true)
					check(m ~= nil and m:IsA("MeshPart"), "Art.News has " .. name)
					if m and m:IsA("MeshPart") then
						check(string.match(m.MeshId, "^rbxassetid://%d+$") ~= nil, name .. " is uploaded")
						if row.maps then
							local sa = m:FindFirstChildOfClass("SurfaceAppearance")
							check(
								sa ~= nil and string.match(sa.ColorMap, "%d+") ~= nil,
								look .. " " .. name .. " keeps its baked texture set"
							)
						end
					end
				end
			end
		end)
	end
end
