-- The missing sounds (alive-world round 3, 2026-11-20): the Ambient atlas (art/audio/build.py build_ambient, CC0
-- sources in notes/Tools.md plus our own synth) and where each clip plays: the Ceremony crowd's applause and gasp
-- and the scanner's hum (Fx.PrologueFx), Patch's radio key-up, harbour gulls and the crane's winch (Fx.CityLife),
-- the park's birdsong bed (AudioController's beds) and the rain bed (Fx.WeatherFx). Called from tests/run.luau:
--   require("./alive3_test")({ test = test, check = check, Config = Config })
-- ONLY="Alive" runs these with the other alive tests.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local SoundPick = require("../src/shared/SoundPick")
	local Clips = Config.AudioClips
	local A = Config.Audio.sounds
	local LS = Config.Life.sounds

	local function has(path: string, needle: string): boolean
		return string.find(fs.readFile(path), needle, 1, true) ~= nil
	end

	local function resolves(row: any, name: string, loop: boolean?, n: number?)
		local pick = SoundPick.resolve(Config, row)
		check(pick ~= nil, name .. " resolves to an uploaded clip")
		if pick then
			check(pick.atlas == "Ambient", name .. " is in the Ambient atlas")
			if loop ~= nil then
				check(pick.loop == loop, name .. (if loop then " loops" else " plays once"))
			end
			if n then
				check(#pick.regions == n, name .. " has " .. n .. " takes (" .. #pick.regions .. ")")
			end
		end
	end

	test("Alive3: the Ambient atlas is uploaded and its regions are in the file", function()
		check((Clips.atlases.Ambient or 0) > 0, "the Ambient atlas has an asset id")
		local ids = serde.decode("json", fs.readFile("art/audio/ids.json"))
		check(ids.Ambient == Clips.atlases.Ambient, "AudioClips carries art/audio/ids.json's id")
		local meta = serde.decode("json", fs.readFile("art/export/audio/clips.json"))
		local last = 0
		for name, r in meta.Ambient do
			local c = Clips.clips[name]
			check(c ~= nil and c[1] == "Ambient", name .. " is in AudioClips")
			check(r[2] > 0.1, name .. " is not empty")
			last = math.max(last, r[1] + r[2])
		end
		check(last < 120, "the atlas is short (" .. last .. " s)")
		-- the other atlases' regions untouched by this --only build
		for _, atlas in { "Hits", "World", "Ui", "Loops" } do
			check(meta[atlas] ~= nil, atlas .. " regions kept in clips.json")
		end
	end)

	test("Alive3: every new sound resolves where it plays", function()
		resolves(A.crowdCheer, "crowdCheer", true)
		resolves(A.crowdGasp, "crowdGasp", false, 2)
		resolves(A.scanHum, "scanHum", true)
		resolves(A.rain, "rain", true)
		resolves(A.radio, "radio (Patch)", false)
		resolves(LS.gull, "gull", false, 3)
		resolves(LS.winch, "winch", false)
		resolves(LS.bed.Park, "the park bed", true)
		for _, k in { "crowdCheer", "crowdGasp", "scanHum", "rain" } do
			check(
				A[k].fallback == nil,
				k .. " has no built-in fallback (silent without the atlas, never a looped ping)"
			)
		end
		check(LS.gull.range and LS.winch.range, "gulls and the winch are heard where they are")
	end)

	test("Alive3: the winch lasts one run of the crane's trolley", function()
		local CR = Config.Life.cranes
		local run = math.abs(CR.b - CR.a) / CR.speed * 1.5
		local c = Clips.clips.winch
		check(math.abs(c[3] - run) < 0.3, "winch " .. c[3] .. " s for a " .. run .. " s run")
	end)

	test("Alive3: the sounds are wired into their places", function()
		check(
			has("src/client/Fx/PrologueFx.luau", 'AudioController.loop("crowdCheer", cheer)'),
			"the crowd cheers"
		)
		check(
			has("src/client/Fx/PrologueFx.luau", 'AudioController.play("crowdGasp")'),
			"the crowd gasps once"
		)
		check(
			has("src/client/Fx/PrologueFx.luau", 'AudioController.loop("scanHum", hum)'),
			"the scanner hums"
		)
		check(
			has("src/client/Fx/PrologueFx.luau", "crowdSound(false, false)"),
			"both stop when the prologue ends"
		)
		check(
			has("src/client/Fx/WeatherFx.luau", 'AudioController.loop("rain", wet > 0.02'),
			"rain follows the rain"
		)
		check(Config.Weather.rain.sound > 0 and Config.Weather.rain.sound <= 0.6, "rain bed volume")
		check(has("src/client/Fx/CityLife.luau", "L.sounds.gull"), "gull colonies cry")
		check(has("src/client/Fx/CityLife.luau", "L.sounds.winch"), "the trolley's winch")
		check(
			has("src/client/Controllers/AudioController.luau", 'if inPark then "Park"'),
			"the park has its bed"
		)
		check(
			Config.Life.gulls.cry[1] >= 4 and Config.Life.gulls.cry[2] > Config.Life.gulls.cry[1],
			"cries now and then"
		)
	end)

	test("Alive3: the sources are CC0 and noted in Tools.md", function()
		local tools = fs.readFile("notes/Tools.md")
		for _, needle in
			{
				"gasp1.opus",
				"solo-clap.opus",
				"wolf-whistle.opus",
				"Loops/rain.opus",
				"loop_rain.opus",
				"space_engine_low_002.ogg",
				"engine_circular_001.ogg",
			}
		do
			check(string.find(tools, needle, 1, true) ~= nil, needle .. " is in Tools.md")
		end
	end)
end
