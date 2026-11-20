-- The sounds pass (2026-11-19, nate's playtest: "need better sounds badly"): every Config.Audio and Config.Life row
-- plays a recorded, uploaded clip (Config.AudioClips, Shared.SoundPick, AudioController), with variants, groups,
-- ducking, the city bed and the music. Called from tests/run.luau:
--   require("./sounds_test")({ test = test, check = check, Config = Config, placePath = process.args[1] })
-- ONLY="Sounds" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local roblox = require("@lune/roblox")
	local SoundPick = require("../src/shared/SoundPick")
	local A, L, Clips = Config.Audio, Config.Life, Config.AudioClips

	local function src(path: string): string
		return fs.readFile(path)
	end

	-- every row in the game's sound tables, with a name for the message
	local function rows(): { { name: string, row: any } }
		local out = {}
		for k, r in A.sounds do
			table.insert(out, { name = "sounds." .. k, row = r })
		end
		for k, r in A.impact do
			table.insert(out, { name = "impact." .. k, row = r })
		end
		for p, set in A.paths do
			for m, r in set do
				table.insert(out, { name = "paths." .. p .. "." .. m, row = r })
			end
		end
		for k, r in A.music do
			if type(r) == "table" then
				table.insert(out, { name = "music." .. k, row = r })
			end
		end
		for k, r in L.sounds do
			if k ~= "bed" then
				table.insert(out, { name = "life." .. k, row = r })
			end
		end
		for k, r in L.sounds.bed do
			table.insert(out, { name = "bed." .. k, row = r })
		end
		return out
	end

	test(
		"Sounds: every Config.Audio and Config.Life row plays an uploaded clip (no silent or placeholder row)",
		function()
			local ids = serde.decode("json", src("art/audio/ids.json"))
			for atlas, id in Clips.atlases do
				check(id > 0, atlas .. " atlas has an uploaded id")
				check(ids[atlas] == id, atlas .. " id matches art/audio/ids.json")
			end
			local n = 0
			for _, e in rows() do
				local p = SoundPick.resolve(Config, e.row)
				check(
					p ~= nil and string.match(p.id, "^rbxassetid://%d+$") ~= nil,
					e.name .. " resolves to an uploaded clip"
				)
				n += 1
			end
			check(n >= 170, "all " .. n .. " rows checked")
			-- and the juice table: every action's sound is a recorded one
			for _, j in A.juice do
				check(SoundPick.resolve(Config, A.sounds[j.id]) ~= nil, "juice " .. j.id .. " has its clip")
			end
		end
	)

	test(
		"Sounds: clip regions sit inside their atlases, loops are loops, and the files are on disk",
		function()
			local meta = serde.decode("json", src("art/export/audio/clips.json"))
			local music = serde.decode("json", src("art/export/audio/music.json"))
			meta.Music = music
			for name, c in Clips.clips do
				local m = meta[c[1]] and meta[c[1]][name]
				check(m ~= nil, name .. " is in the built atlas " .. tostring(c[1]))
				check(c[2] >= 0 and c[3] > 0.02, name .. " has a real region")
				if m then
					check(
						math.abs(m[1] - c[2]) < 1e-3 and math.abs(m[2] - c[3]) < 1e-3,
						name .. " region matches the build"
					)
				end
			end
			for atlas in Clips.atlases do
				check(fs.isFile("art/export/audio/" .. atlas .. ".ogg"), atlas .. ".ogg is built")
			end
			for _, id in { "flyCruise", "downed", "speedRun" } do
				local p = SoundPick.resolve(Config, A.sounds[id])
				check(p ~= nil and p.loop, id .. " is a seamless loop")
			end
			for k, r in L.sounds.bed do
				local p = SoundPick.resolve(Config, r)
				check(p ~= nil and p.loop and p.regions[1].length >= 20, "bed " .. k .. " is a long loop")
			end
			for _, k in { "patrolDay", "patrolNight", "boss" } do
				local p = SoundPick.resolve(Config, A.music[k])
				check(p ~= nil and p.loop and p.regions[1].length >= 20, k .. " music loops")
			end
			local v = SoundPick.resolve(Config, A.music.victory)
			check(v ~= nil and not v.loop, "the victory sting plays once")
		end
	)

	test("Sounds: common sounds have 2 to 4 variants; every power path has its four layers", function()
		for _, id in
			{
				"basic",
				"cast",
				"land",
				"leap",
				"defeat",
				"block",
				"wallSmash",
				"throwLand",
				"boost",
				"super",
				"crit",
			}
		do
			local p = SoundPick.resolve(Config, A.sounds[id])
			check(p ~= nil and #p.regions >= 2 and #p.regions <= 4, id .. " has variants")
		end
		for _, id in { "hit", "heavy", "clank" } do
			local p = SoundPick.resolve(Config, A.impact[id])
			check(p ~= nil and #p.regions >= 3, "impact " .. id .. " has 3+ variants")
		end
		local paths = 0
		for path, set in A.paths do
			paths += 1
			for _, m in { "cast", "super", "hit", "charge" } do
				check(set[m] and SoundPick.resolve(Config, set[m]) ~= nil, path .. " " .. m)
			end
			local hit = SoundPick.resolve(Config, set.hit)
			check(hit ~= nil and #hit.regions >= 2, path .. " hits vary")
		end
		check(paths == 17, "17 paths")
		-- no two paths share a clip: each element sounds like itself
		local seen = {}
		for path, set in A.paths do
			for m, r in set do
				check(not seen[r.clip], path .. " " .. m .. " has its own clip")
				seen[r.clip] = true
			end
		end
	end)

	test("Sounds: SoundPick picks without repeats and keeps chimes in tune", function()
		for n = 2, 4 do
			for last = 1, n do
				for i = 0, 19 do
					local k = SoundPick.choose(n, last, i / 20)
					check(
						k >= 1 and k <= n and k ~= last,
						"variant " .. k .. " of " .. n .. " after " .. last
					)
				end
			end
		end
		check(SoundPick.choose(1, 1, 0.5) == 1, "one clip: always it")
		local row = { pitch = 1.8, clip = "gearDrop" }
		check(
			math.abs(SoundPick.pitch(row, 1.8 * 1.2, 0.3) - 1.2) < 1e-9,
			"an asked pitch is a ratio of the row's"
		)
		check(SoundPick.pitch({ clip = "x" }, nil, 0.9) == 1, "2D rows are not detuned")
		local p = SoundPick.pitch({ clip = "x", range = 90, vary = 0.1 }, nil, 1)
		check(math.abs(p - 1.1) < 1e-9, "3D rows spread by vary")
		check(SoundPick.resolve(Config, { clip = "noSuchClip" }) == nil, "an unknown clip falls back")
	end)

	test(
		"Sounds: the AudioController plays regions in groups, ducks big booms and runs the city bed",
		function()
			local ac = src("src/client/Controllers/AudioController.luau")
			for _, needle in
				{
					"PlaybackRegionsEnabled = true",
					"PlaybackRegion = NumberRange.new",
					"LoopRegion = NumberRange.new",
					"CompressorSoundEffect",
					"SoundPick.choose",
					"PreloadAsync",
					"duckFx()",
					"bedTick()",
					"LifePlan.districtAt",
					"DeepLayout.underwater",
				}
			do
				check(string.find(ac, needle, 1, true) ~= nil, "AudioController: " .. needle)
			end
			for _, id in A.mix.duck.ids do
				check(A.sounds[id] ~= nil, "duck id " .. id .. " is a row")
			end
			for _, id in A.mix.ui do
				check(A.sounds[id] ~= nil, "ui id " .. id .. " is a row")
			end
			-- the bed picks: Downtown traffic, the Docks, open air; nothing underwater or up in the pockets
			local LifePlan = require("../src/shared/LifePlan")
			local d = Config.City.districts.Docks
			check(
				LifePlan.districtAt(Config, (d.minX + d.maxX) / 2, (d.minZ + d.maxZ) / 2) == "Docks",
				"the Docks have their bed"
			)
			check(L.sounds.bed[LifePlan.districtAt(Config, 2300, 2300)] ~= nil, "the outskirts have a bed")
			check(A.bed.maxY < 3000, "the pockets (y 3,000) are above the beds")
			-- Roblox knows every Sound property the controller sets (checked against the engine's own API)
			local s = roblox.Instance.new("Sound")
			s.PlaybackRegionsEnabled = true
			s.PlaybackRegion = roblox.NumberRange.new(1.5, 2)
			s.LoopRegion = roblox.NumberRange.new(1.5, 2)
			s.TimePosition = 1.5
			s.RollOffMinDistance = 10
			check(s.PlaybackRegion.Min == 1.5 and s.LoopRegion.Max == 2, "Sound regions set")
			local c = roblox.Instance.new("CompressorSoundEffect")
			c.Threshold = A.mix.compressor.threshold
			c.Ratio = A.mix.compressor.ratio
			c.GainMakeup = A.mix.compressor.makeup
			check(c.Ratio == A.mix.compressor.ratio, "compressor set")
		end
	)

	test("Sounds: MoveAudio plays the new movement rows, and the client starts it", function()
		local ma = src("src/client/Fx/MoveAudio.luau")
		for _, id in { "pound", "bounce", "splash", "dash", "sonicBoom", "speedRun" } do
			check(A.sounds[id] ~= nil, id .. " is a row")
			check(string.find(ma, '"' .. id .. '"', 1, true) ~= nil, "MoveAudio plays " .. id)
		end
		local init = src("src/client/init.client.luau")
		check(string.find(init, "MoveAudio.init()", 1, true) ~= nil, "the client starts MoveAudio")
		local M = A.move
		check(M.boomSpeed <= Config.Move.mobility.speed.sprint, "a Super Speed sprint reaches the sonic boom")
		check(M.boomSpeed <= Config.Move.flight.boost, "a flight boost reaches the sonic boom")
		check(M.boomReset < M.boomSpeed, "the boom re-arms below its speed")
	end)

	test("Sounds: the build carries AudioClips, SoundPick and MoveAudio", function()
		local game = roblox.deserializePlace(fs.readFile(T.placePath or "build/Capeline.rbxl"))
		local rs = game:GetService("ReplicatedStorage")
		local cfg = rs:FindFirstChild("Config")
		check(cfg ~= nil and cfg:FindFirstChild("AudioClips") ~= nil, "Config.AudioClips is in the place")
		local sh = rs:FindFirstChild("Shared")
		check(sh ~= nil and sh:FindFirstChild("SoundPick") ~= nil, "Shared.SoundPick is in the place")
		local sps = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
		check(
			sps ~= nil and sps:FindFirstChild("MoveAudio", true) ~= nil,
			"Client Fx.MoveAudio is in the place"
		)
	end)
end
