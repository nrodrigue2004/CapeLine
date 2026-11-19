-- The story art pass (gap-story, 2026-11-19): art/blender/story.py's looks over a mission's unchanged break targets
-- and runaway train (Shared.StoryArtKit, Fx.StoryProps), the trapped people at the bridge's rings, the reach goal
-- beacon and the Echo Drone (Fx.StoryFx), with the plain parts and every hit exactly as before.
-- Called from tests/run.luau:
--   require("./story_art_test")({ test = test, check = check, Config = Config, placePath = placePath })
-- ONLY="Story art" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local StoryArtKit = require("../src/shared/StoryArtKit")

	local function has(text: string, needle: string): boolean
		return string.find(text, needle, 1, true) ~= nil
	end

	test("Story art: every look is built on its boxes, inside its frame, with its moving meshes", function()
		local bad = StoryArtKit.check(Config)
		check(#bad == 0, "StoryArtKit.check: " .. table.concat(bad, "; "))
		local total = 0
		for look, fit in Config.StoryArt do
			local tris = 0
			for name, m in fit.meshes do
				tris += m.tris or 0
				local low = string.lower(name)
				-- people's faces and hair are catalog items: nothing here models one
				check(
					not string.find(low, "face", 1, true) or name == "StoryScreenFace",
					look .. " draws no face: " .. name
				)
				check(not string.find(low, "hair", 1, true), look .. " draws no hair: " .. name)
			end
			check(tris > 0 and tris <= 6000, look .. " is phone-light: " .. tris .. " tris")
			total += tris
		end
		check(total <= 24000, "the whole set is light: " .. total)
		check(
			Config.StoryArt.EchoDrone.meshes.EchoDroneEye.mat == "Neon",
			"the drone's eye glows (it blinks)"
		)
		check(
			Config.StoryArt.StoryTrap.meshes.StoryTrapGirder ~= nil,
			"the girder is its own mesh (it lifts)"
		)
		-- all or nothing
		check(not StoryArtKit.ready(Config, "StoryTrain", function()
			return false
		end), "nothing imported: today's parts")
		local first = true
		check(not StoryArtKit.ready(Config, "StoryTrain", function()
			local was = first
			first = false
			return was
		end), "half imported: today's parts")
		check(
			StoryArtKit.ready(Config, "StoryTrain", function()
				return true
			end),
			"all imported: the look"
		)
	end)

	test("Story art: the break targets' and the train's plain parts are exactly as before", function()
		local B = StoryArtKit.BOXES
		local function same(a: { number }, b: { number }): boolean
			return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
		end
		check(
			#B.train == 2 and same(B.train[1].size, { 10, 9, 26 }) and same(B.train[1].at, { 0, 4.5, 0 }),
			"train body"
		)
		check(same(B.train[2].size, { 10.4, 2, 26.4 }) and same(B.train[2].at, { 0, 7, 0 }), "train roof")
		check(
			#B.crate == 2 and same(B.crate[1].size, { 5, 4, 5 }) and same(B.crate[1].at, { 0, 2, 0 }),
			"crate box"
		)
		check(
			same(B.crate[2].size, { 1.5, 3, 1.5 }) and same(B.crate[2].at, { 0, 5, 0 }) and B.crate[2].neon,
			"crystal"
		)
		local ms = fs.readFile("src/server/Services/MissionService.luau")
		check(
			has(ms, 'storyParts(m, "train", st)') and has(ms, 'storyParts(m, "crate", st)'),
			"built from BOXES"
		)
		check(
			has(ms, "SiteKit.part(") and has(ms, 'm:SetAttribute("StoryLook"'),
			"plain parts, tagged with the look"
		)
		-- the combat targets (lift, radius) and the hit counts are MissionService's, unchanged
		check(
			has(ms, '"RunawayTrain",\n\t\t\t\tfrom,\n\t\t\t\t4,\n\t\t\t\t10,'),
			"the train's target: lift 4, radius 10"
		)
		check(
			has(ms, '"StoryCrate",\n\t\t\t\t\t\tv3(p),\n\t\t\t\t\t\t2,\n\t\t\t\t\t\t5,'),
			"a crate's target: lift 2, radius 5"
		)
		local sk = fs.readFile("src/server/Services/SiteKit.luau")
		local a = string.find(sk, "function SiteKit.part(", 1, true) or 0
		local body = string.sub(sk, a, a + 600)
		check(
			has(body, "p.CanCollide = false") and has(body, "p.CanQuery = false"),
			"the parts never collide or query"
		)
		local props = fs.readFile("src/client/Fx/StoryProps.luau")
		check(has(props, "LocalTransparencyModifier = 1"), "hidden on this device only, never removed")
		check(
			has(props, "p.CanCollide = false") and has(props, "p.CanQuery = false"),
			"the meshes are ghosts"
		)
	end)

	test("Story art: each break step picks its look; the bridge has its people", function()
		local seen: { [string]: boolean } = {}
		local people = 0
		local function walk(steps: any)
			for _, st in steps or {} do
				if type(st) == "table" and st.kind == "break" then
					local look = StoryArtKit.lookFor(st)
					check(Config.StoryArt[look] ~= nil, "a known look: " .. look)
					seen[look] = true
				elseif type(st) == "table" and st.kind == "hold" and st.people then
					people += 1
				end
			end
		end
		for _, m in Config.Story.missions do
			walk(m.hero)
			walk(m.villain)
			for _, side in m.branches or {} do
				walk(side)
			end
		end
		for _, look in { "StoryTrain", "StoryRelay", "StoryScreen", "StoryVan" } do
			check(seen[look] == true, "a mission uses " .. look)
		end
		check(StoryArtKit.lookFor({ kind = "break" }) == "StoryCrate", "the shard crate by default")
		check(people == 1, "the bridge ring step has its people: " .. people)
		local ms = fs.readFile("src/server/Services/MissionService.luau")
		check(
			has(ms, "out.people = st.people or nil") and has(ms, "out.seconds = st.seconds"),
			"the device knows"
		)
	end)

	test("Story art: the drone bobs, blinks briefly; the girder lifts; budgets by preset", function()
		local closed, open = 0, 0
		for i = 0, 2000 do
			local t = i * 0.01
			local k = StoryArtKit.blink(t, 4242)
			check(k >= StoryArtKit.DRONE.blinkMin - 1e-6 and k <= 1, "blink share in range")
			if k < 1 then
				closed += 1
			else
				open += 1
			end
			check(math.abs(StoryArtKit.bob(t, 4242)) <= StoryArtKit.DRONE.bob + 1e-6, "bob in range")
		end
		check(closed > 0 and closed < open / 10, "it blinks, briefly: " .. closed .. "/" .. open)
		check(
			StoryArtKit.lift(0) == 0 and math.abs(StoryArtKit.lift(1) - StoryArtKit.LIFT) < 1e-6,
			"lift 0 to LIFT"
		)
		check(StoryArtKit.lift(0.5) > StoryArtKit.lift(0.25), "lifts as the ring is held")
		local last = -1
		for _, name in Config.Presets.order do
			local s = Config.Presets[name].story
			check(s ~= nil and s.radius > 0 and s.looks > 0 and s.drones > 0, name .. " has a story budget")
			check(s.looks >= last, "more looks on better presets")
			last = s.looks
		end
		check(Config.Presets.low.story.rings == false, "phones keep the beacon's rings still")
		local fx = fs.readFile("src/client/Fx/StoryFx.luau")
		check(has(fx, 'FrameProf.wrap("StoryFx"'), "StoryFx's loop is profiled")
		check(has(fx, "NpcRig.person("), "the trapped people are Roblox's own body (catalog face and hair)")
		check(has(fx, "PLACEHOLDER ART"), "the fallbacks are labelled")
	end)

	if T.placePath then
		test("Story art: Art.Story is in the place, every mesh uploaded, textures kept", function()
			local roblox = require("@lune/roblox")
			local game = roblox.deserializePlace(fs.readFile(T.placePath))
			local art = game:GetService("ReplicatedStorage"):FindFirstChild("Art")
			local set = art and art:FindFirstChild("Story")
			check(set ~= nil, "ReplicatedStorage.Art.Story")
			if not set then
				return
			end
			for look, fit in Config.StoryArt do
				for name, row in fit.meshes do
					local m = set:FindFirstChild(name, true)
					check(m ~= nil and m:IsA("MeshPart"), "Art.Story has " .. name)
					if m and m:IsA("MeshPart") then
						check(string.match(m.MeshId, "^rbxassetid://%d+$") ~= nil, name .. " is uploaded")
						if row.maps then
							local sa = m:FindFirstChildOfClass("SurfaceAppearance")
							check(
								sa ~= nil and string.match(sa.ColorMap, "%d+") ~= nil,
								look .. " " .. name .. " keeps its maps"
							)
						end
					end
				end
			end
		end)
	end
end
