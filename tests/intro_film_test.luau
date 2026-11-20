-- The intro film (list-combat 2026-11-20, nate: "the first 30 seconds are almost as important as the first 30
-- minutes"; "make sure it looks very nice and isn't boring"): Shared.IntroFilm on the real world for the test seed,
-- from every spawn. ONLY="Intro film" runs these.
return function(T: any)
	local test, check, Config, world = T.test, T.check, T.Config, T.world
	local IntroFilm = require("../src/shared/IntroFilm")
	local F = Config.Story.opening.film

	local function inside(p: { number }, margin: number): any
		for _, b in world.buildings do
			if
				math.abs(p[1] - b.x) < b.sx / 2 - margin
				and math.abs(p[3] - b.z) < b.sz / 2 - margin
				and p[2] > b.base + margin
				and p[2] < b.top - margin
			then
				return b
			end
		end
		return nil
	end

	test("Intro film: a stage near every spawn, cut every 2 to 4 s, never inside a building", function()
		local staged, clear = 0, 0
		for i, sp in world.spawns do
			local st = IntroFilm.stage(Config, world, sp.x, sp.z)
			check(st ~= nil, "a stage near spawn " .. i)
			if st then
				staged += 1
				if (st.blocked or 0) == 0 then
					clear += 1
				end
				local film = IntroFilm.film(Config, st)
				check(film.seconds >= 40 and film.seconds <= 50, "about 45 s in all")
				check(film.coldOpen >= 10 and film.coldOpen <= 15, "a 10 to 15 s cold open")
				local last = 0
				for k, s in film.shots do
					check(math.abs(s.t0 - last) < 1e-6, "shot " .. k .. " follows the last")
					local len = s.t1 - s.t0
					check(
						len >= 2 and len <= 4,
						string.format("shot %d is %.1f s (a cut every 2 to 4 s)", k, len)
					)
					last = s.t1
				end
				check(math.abs(last - film.seconds) < 1e-6, "the shots fill the film")
				local bad = {}
				for t = 0, film.seconds - 0.05, 0.1 do
					local pos = IntroFilm.camera(film, t)
					local b = inside(pos, 0.5)
					if b then
						table.insert(bad, string.format("%.1f in %d", t, b.id))
					end
					local d = math.sqrt((pos[1] - sp.x) ^ 2 + (pos[3] - sp.z) ^ 2)
					if d > F.reach + 260 then
						table.insert(bad, string.format("%.1f far %d", t, d))
					end
				end
				check(
					#bad == 0,
					"the camera stays outside and near ("
						.. table.concat(bad, ", ", 1, math.min(#bad, 6))
						.. ")"
				)
			end
		end
		check(staged >= 1, "staged")
		check(
			clear >= staged * 0.8,
			string.format("the cast stays in the open at %d of %d stages", clear, staged)
		)
	end)

	test("Intro film: captions in order and short, lore words or marked draft", function()
		local sp = world.spawns[1]
		local film = IntroFilm.film(Config, IntroFilm.stage(Config, world, sp.x, sp.z) :: any)
		local last = 0
		for _, c in film.captions do
			check(c.t0 >= last and c.t1 > c.t0, c.text .. ": in order")
			check(#c.text <= 64, c.text .. ": short")
			check(c.draft == true or c.from == "lore" or c.from == "game", c.text .. ": lore, game or DRAFT")
			last = c.t1
		end
		local kinds = {}
		for _, e in film.events do
			kinds[e.kind] = true
		end
		for _, k in { "smash", "title", "land", "crack", "spark", "shot", "boom" } do
			check(kinds[k] == true, "the film has its " .. k)
		end
		check(#film.words >= 6, "comic sound words on screen")
	end)

	test("Intro film: the client plays every actor and event, and the runtime path is wired", function()
		local fs = require("@lune/fs")
		local fx = fs.readFile("src/client/Fx/IntroFilm.luau")
		local sp = world.spawns[1]
		local film = IntroFilm.film(Config, IntroFilm.stage(Config, world, sp.x, sp.z) :: any)
		local seen = {}
		for _, tr in film.tracks do
			if not seen[tr.kind] then
				seen[tr.kind] = true
				check(
					tr.kind == "citizen" or string.find(fx, 'tr.kind == "' .. tr.kind .. '"', 1, true) ~= nil,
					"the player builds a " .. tr.kind
				)
			end
			for _, k in tr.keys do
				check(
					k.clip == nil
						or k.clip == "walk"
						or k.clip == "sprint"
						or k.clip == "fly"
						or k.clip == "pound"
						or k.clip == "hover",
					tr.id .. " clip " .. tostring(k.clip)
				)
			end
		end
		for _, e in film.events do
			check(
				string.find(fx, 'kind == "' .. e.kind .. '"', 1, true) ~= nil,
				"the player fires " .. e.kind
			)
		end
		for _, e in film.events do
			if e.kind == "music" then
				check(Config.Audio.music[e.text] ~= nil, "music " .. tostring(e.text) .. " is a track")
			end
		end
		-- every sound the player names is a sound row
		for id in string.gmatch(fx, 'AudioController.play%("([%w]+)"') do
			check(Config.Audio.sounds[id] ~= nil, "sound " .. id .. " is a row")
		end
		-- the Syndicate crook's look is made of real creator pieces
		local FakeRules = require("../src/shared/FakeRules")
		local ok, err = pcall(FakeRules.lookFrom, Config, Config.Story.opening.film.syndicate, "Syndicate")
		check(ok, "the Syndicate look builds (" .. tostring(err) .. ")")
		-- the wire: the server sends the stage, StoryClient hands it to the film, the client boots it
		local os_ = fs.readFile("src/server/Services/OpeningService.luau")
		local cs = fs.readFile("src/server/Services/CreatorService.luau")
		local sc = fs.readFile("src/client/Controllers/StoryClient.luau")
		local init = fs.readFile("src/client/init.client.luau")
		check(
			string.find(cs, "stage = OpeningService.introStage(player)", 1, true) ~= nil,
			"the creator sends the stage"
		)
		check(
			string.find(os_, "replay = true, stage = OpeningService.introStage(player)", 1, true) ~= nil,
			"a replay sends it too"
		)
		check(
			string.find(sc, "StoryClient.filmScene(stage, base)", 1, true) ~= nil,
			"StoryClient plays the film"
		)
		check(string.find(init, "IntroFilmFx.init()", 1, true) ~= nil, "the client boots the film")
		check(string.find(fx, 'FrameProf.wrap("IntroFilm"', 1, true) ~= nil, "its step is profiled")
		-- the server's stage call on the real world is quick enough for a join (one pick per new account)
		local t0 = os.clock()
		for _, s in world.spawns do
			IntroFilm.stage(Config, world, s.x, s.z)
		end
		local per = (os.clock() - t0) / math.max(1, #world.spawns)
		check(per < 0.25, string.format("a stage pick takes %.3f s", per))
	end)

	test("Intro film: the loading card plays the real music at once", function()
		-- (LoadingCard needs Roblox's Color3 at load, so its MUSIC row is read from the source)
		local card = require("@lune/fs").readFile("src/first/LoadingCard.luau")
		local row = string.match(card, "LoadingCard%.MUSIC = (%b{})") or "{}"
		local M = {}
		for k, val in string.gmatch(row, "(%w+) = ([%d%.]+)") do
			M[k] = tonumber(val)
		end
		local far = string.match(card, "far = (%b{})") or ""
		local near = string.match(card, "near = (%b{})") or ""
		local LoadingCard = {
			SKYLINE = { far = string.split(far, ","), near = string.split(near, ",") },
		}
		local clip = Config.AudioClips.clips.patrolDay
		check(M.atlas == Config.AudioClips.atlases[clip[1]], "the Music atlas id")
		check(
			math.abs(M.start - clip[2]) < 1e-6 and math.abs(M.length - clip[3]) < 1e-6,
			"the day patrol's region"
		)
		check(math.abs(M.volume - Config.Audio.music.patrolDay.volume) < 1e-6, "its volume")
		check(
			math.abs(M.group - require("../src/shared/SettingsRules").defaults(Config).music / 10) < 1e-6,
			"the default music level"
		)
		local src = require("@lune/fs").readFile("src/first/LoadingScreen.client.luau")
		check(string.find(src, "music.SoundGroup = musicGroup", 1, true) ~= nil, "in the Music group")
		check(#LoadingCard.SKYLINE.far >= 8 and #LoadingCard.SKYLINE.near >= 8, "a skyline on the card")
	end)
end
