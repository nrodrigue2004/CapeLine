-- Pocket kit (2026-11-19, the pocket kit pass): every mission and side quest pocket wears the cartoon kit
-- (Config.PocketKit, Shared.PocketDress) without moving a single colliding thing. Checked here:
--   * looks() changes only the look fields (kit, tint, mat) of PocketLayout's boxes: every box keeps its kind,
--     place, size, turn, shape, tag and ghost, so walls, doors, spawns, steps, heights and ceilings are the same
--   * every dressing piece is a ghost (no collision, no queries, no touch) tagged "dress", inside the pocket,
--     with a tier 1 to 3; every kit texture and colour it names exists (Config.City.kit, palette, MaterialService)
--   * the dressing fits each preset's budget (Config.Presets <preset>.pockets: parts and lights), phones low
--   * every sign board's text is fixed and fits its board (no typed text anywhere)
--   * the Crater ruins wear the kit too, their colliding boxes unchanged in size
-- Called from tests/run.luau. ONLY="Pocket kit" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local PocketLayout = require("../src/shared/PocketLayout")
	local PocketDress = require("../src/shared/PocketDress")
	local fs = require("@lune/fs")

	local LAYOUTS = {
		"station",
		"tower",
		"rooftops",
		"dungeon",
		"arena",
		"bridge",
		"subway",
		"academy",
		"toyshop",
		"seacave",
		"velmara",
		"pit",
		"ashlab",
		"ironhall",
		"pound",
	}
	local GEOM =
		{ "kind", "cx", "cy", "cz", "sx", "sy", "sz", "shape", "ry", "tag", "ghost", "ref", "art", "color" }

	local function build(name: string): any
		local i = if name == "subway" then PocketLayout.subwayIndex(Config) else 1
		return PocketLayout.build(Config, i, name)
	end

	test("Pocket kit: every pocket keeps its colliding geometry exactly", function()
		for _, name in LAYOUTS do
			check(Config.PocketKit.pockets[name] ~= nil, name .. " has a kit look")
			local plain = build(name)
			local dressed = build(name)
			local n = PocketDress.looks(Config, dressed, name)
			local solid = 0
			for _, b in dressed.boxes do
				if b.kind ~= "glow" and b.kind ~= "ledge" then
					solid += 1
				end
			end
			check(n > solid / 2, name .. " most boxes take a kit look (" .. n .. "/" .. solid .. ")")
			check(#plain.boxes == #dressed.boxes, name .. " same box count")
			local same = true
			for i, b in plain.boxes do
				local d = dressed.boxes[i] :: any
				for _, f in GEOM do
					if (b :: any)[f] ~= d[f] then
						same = false
						print("   ", name, i, f, (b :: any)[f], d[f])
					end
				end
				for k in d do
					if (b :: any)[k] == nil and not PocketDress.LOOK_FIELDS[k] then
						same = false
						print("   ", name, i, "new field", k)
					end
				end
			end
			check(same, name .. " every box keeps its kind, place, size, turn, shape, tag and solidity")
			-- the dressing never joins the layout: heights and ceilings read the same boxes
			PocketDress.dress(Config, dressed, name)
			check(#dressed.boxes == #plain.boxes, name .. " dressing is not added to the layout's boxes")
			PocketLayout.heights(plain)
			PocketLayout.heights(dressed)
			local diff = 0
			for x = -195, 195, 15 do
				for z = -195, 195, 15 do
					local wx, wz = plain.cx + x, plain.cz + z
					if PocketLayout.heightAt(plain, wx, wz) ~= PocketLayout.heightAt(dressed, wx, wz) then
						diff += 1
					end
				end
			end
			check(diff == 0, name .. " heights unchanged")
		end
	end)

	test(
		"Pocket kit: dressing is ghost, inside the pocket, tiered, and names real textures and colours",
		function()
			local K = Config.City.kit
			local project = fs.readFile("default.project.json")
			for _, name in LAYOUTS do
				local l = build(name)
				local d = PocketDress.apply(Config, l, name)
				check(#d.extras > 20, name .. " has dressing (" .. #d.extras .. ")")
				check(#d.lights > 0, name .. " has lights")
				local half = Config.Story.pockets.size / 2 + 2
				local ok, inside, tiers, colours = true, true, true, true
				for _, e in d.extras do
					ok = ok and e.ghost == true and e.tag == "dress"
					inside = inside
						and math.abs(e.cx - l.cx) <= half + math.max(e.sx, e.sz) / 2
						and math.abs(e.cz - l.cz) <= half + math.max(e.sx, e.sz) / 2
					tiers = tiers and (e.tier == 1 or e.tier == 2 or e.tier == 3)
					colours = colours and Config.City.palette[e.color] ~= nil
					if e.tint then
						colours = colours and Config.City.palette[e.tint] ~= nil
					end
				end
				check(ok, name .. " every dressing piece is a ghost tagged dress")
				check(inside, name .. " dressing stays inside the pocket")
				check(tiers, name .. " every piece has tier 1, 2 or 3")
				check(colours, name .. " every dressing colour is in the palette")
				local kits = true
				for _, b in l.boxes do
					local bb = b :: any
					if bb.kit then
						kits = kits
							and K.baseMaterial[bb.kit] ~= nil
							and K.studsPerTile[bb.kit] ~= nil
							and string.find(project, '"Kit' .. bb.kit .. '"', 1, true) ~= nil
					end
					if bb.tint then
						kits = kits and Config.City.palette[bb.tint] ~= nil
					end
					if bb.mat then
						kits = kits and type(bb.mat) == "string"
					end
				end
				check(kits, name .. " every kit look is a MaterialVariant in the project with a palette tint")
				for _, p in d.props do
					check(K.props[p.name] ~= nil, name .. " prop " .. p.name .. " is a street prop")
				end
				for _, li in d.lights do
					check(Config.City.palette[li.color] ~= nil, name .. " light colour " .. li.color)
				end
			end
		end
	)

	test("Pocket kit: dressing fits every preset's budget (phones low)", function()
		local low, med, high =
			Config.Presets.low.pockets, Config.Presets.medium.pockets, Config.Presets.high.pockets
		check(low.parts < med.parts and med.parts < high.parts, "budgets grow low to high")
		check(low.lights <= 4, "phones get at most 4 pocket lights")
		for _, name in LAYOUTS do
			local l = build(name)
			local d = PocketDress.apply(Config, l, name)
			local t1, t2, t3 =
				PocketDress.parts(Config, d, 1),
				PocketDress.parts(Config, d, 2),
				PocketDress.parts(Config, d, 3)
			check(t1 <= low.parts, string.format("%s tier 1 %d parts within low %d", name, t1, low.parts))
			check(t2 <= med.parts, string.format("%s tier 2 %d parts within medium %d", name, t2, med.parts))
			check(t3 <= high.parts, string.format("%s tier 3 %d parts within high %d", name, t3, high.parts))
			for _, pn in { "low", "medium", "high" } do
				local b = Config.Presets[pn].pockets
				local ex, pr, li, used = PocketDress.pick(Config, d, b, 2)
				check(used <= b.parts, name .. " " .. pn .. " pick within parts")
				check(#li <= b.lights, name .. " " .. pn .. " pick within lights")
				if pn == "low" then
					check(#ex == 0, name .. " low builds no tier 2 boxes")
				end
				for _, p in pr do
					check(p.tier >= 2 or pn == "low", "props")
				end
			end
		end
	end)

	test("Pocket kit: sign boards have fixed short text that fits", function()
		for name, K in Config.PocketKit.pockets do
			for key, s in K.signs or {} do
				check(
					type(s.text) == "string" and #s.text > 0 and #s.text <= 16,
					name .. " sign " .. key .. " short text"
				)
				check(s.text == string.upper(s.text), name .. " sign " .. key .. " is comic capitals")
				check(
					Config.City.palette[s.board] ~= nil and Config.City.palette[s.ink] ~= nil,
					name .. " sign colours"
				)
			end
		end
		local seen = 0
		for _, name in LAYOUTS do
			local l = build(name)
			for _, e in PocketDress.apply(Config, l, name).extras do
				if e.sign then
					seen += 1
					-- a board's width over its height fits the text at a readable size (about 0.6 of the height a letter)
					local w = math.max(e.sx, e.sz)
					check(
						#e.sign.text * e.sy * 0.55 <= w + 0.5,
						name .. " sign text fits its board: " .. e.sign.text
					)
				end
			end
		end
		check(seen >= 11, "the pockets put up their sign boards (" .. seen .. ")")
	end)

	test("Pocket kit: the Crater ruins wear the kit and keep their solid boxes", function()
		local WorldGen = require("../src/shared/WorldGen")
		local W = Config.World
		local idx
		for i, lm in W.landmarks do
			if lm.id == "CometCrater" then
				idx = i
			end
		end
		check(idx ~= nil, "the Crater landmark")
		local lm = WorldGen.landmark(Config.City, W, idx)
		local kits, solid, dress = 0, 0, 0
		for _, b in lm.boxes do
			if (b :: any).kit then
				kits += 1
			end
			if b.ghost then
				dress += 1
			else
				solid += 1
			end
		end
		check(
			kits >= 20,
			"the ruins' walls, towers, foundation, rocks and husks take kit textures (" .. kits .. ")"
		)
		check(dress >= 7, "fallen wall chunks added as ghosts (" .. dress .. ")")
	end)
end
