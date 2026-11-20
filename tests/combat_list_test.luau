-- list-combat (2026-11-20): nate's two asks while playing gaps11 and the checklist's sections 6 Combat and 8 Weapons.
-- Called from tests/run.luau; ONLY="List combat" runs just these.
--   * "a lot of noises going on plus the music": music 2 and effects 5 by default, old saves moved, every sound
--     in a group.
--   * "weapons/powers aren't really causing any sort of destruction": every damaging power and weapon move breaks
--     walls in proportion to its damage, at the wall it meets (Shared.BuildingState.wallPoint and abilityStruct,
--     the same modules CombatService and BuildingService run).

return function(T: any)
	local test, check, Config, world = T.test, T.check, T.Config, T.world
	local fs = require("@lune/fs")
	local BuildingState = require("../src/shared/BuildingState")
	local SettingsRules = require("../src/shared/SettingsRules")
	local ProfileSchema = require("../src/shared/ProfileSchema")
	local D = Config.Destruction
	local A = Config.Abilities

	test("List combat: music 2 and sound effects 5 by default, old defaults moved, picks kept", function()
		local d = SettingsRules.defaults(Config)
		check(d.music == 2, "music starts at 2 of 10")
		check(d.sfx == 5, "sound effects start at 5 of 10")
		local old = ProfileSchema.load({ version = 14, settings = { music = 7, sfx = 8 } })
		check(
			old.settings.music == 2 and old.settings.sfx == 5,
			"a save on the old defaults takes the new ones"
		)
		local picked = ProfileSchema.load({ version = 14, settings = { music = 9, sfx = 3 } })
		check(picked.settings.music == 9 and picked.settings.sfx == 3, "a volume the player picked is kept")
		local fresh = ProfileSchema.load(nil)
		local s = SettingsRules.clean(Config, fresh.settings)
		check(s.music == 2 and s.sfx == 5, "a new player hears the new defaults")
		-- every Sound the game makes plays inside a SoundGroup, so the two settings turn everything down
		local bad = {}
		local function scan(dir: string)
			for _, name in fs.readDir(dir) do
				local path = dir .. "/" .. name
				if fs.isDir(path) then
					scan(path)
				elseif string.sub(name, -5) == ".luau" then
					local src = fs.readFile(path)
					local _, made = string.gsub(src, 'Instance%.new%("Sound"%)', "")
					if made > 0 and not string.find(src, "SoundGroup", 1, true) then
						table.insert(bad, path)
					end
				end
			end
		end
		scan("src")
		check(
			#bad == 0,
			"every file that makes a Sound puts it in a group (" .. table.concat(bad, ", ") .. ")"
		)
	end)

	test("List combat: every damaging power and weapon move breaks walls, more for harder hits", function()
		local n, zero = 0, {}
		for id, row in A.list do
			if (row.coeff or 0) > 0 and not row.allyHeal then
				n += 1
				local s = BuildingState.abilityStruct(D, row)
				if s <= 0 then
					table.insert(zero, id)
				end
				if not row.structDmg and row.slot ~= "super" then
					local per = D.structPerCoeff[row.slot]
					check(
						s == math.max(D.slotStruct[row.slot], math.floor(per * row.coeff)),
						id .. " breaks in proportion to its damage"
					)
				end
			end
		end
		check(n > 250, "every damaging row counted (" .. n .. ")")
		check(#zero == 0, "none breaks nothing (" .. table.concat(zero, ", ") .. ")")
		local finisher = { slot = "basic", coeff = 1.0 }
		check(
			BuildingState.abilityStruct(D, finisher) >= D.structure.chunkCost,
			"a combo finisher knocks a piece out"
		)
		local skill = { slot = "skill", coeff = 1.6 }
		check(
			BuildingState.abilityStruct(D, skill) >= 2 * D.structure.chunkCost,
			"a 1.6 skill knocks two pieces or more"
		)
		local charged = { slot = "skill", coeff = 1.6, structDmg = 700, chargeLevel = 1 }
		check(
			BuildingState.abilityStruct(D, charged) > 700,
			"a full charge breaks more than its row's number"
		)
		check(
			BuildingState.abilityStruct(D, { slot = "super", coeff = 3 }) == D.superStruct,
			"supers keep their big number"
		)
	end)

	test("List combat: a slash at a wall breaks the wall, not the floors behind it", function()
		local book = BuildingState.new(D, world.buildings)
		-- the server's rayDist: the Workspace ray stops on a whole building's body (the city's parts: its box
		-- here), then BuildingService.ray on a Damaged one's standing pieces
		local function boxHit(b: any, ox, oy, oz, dx, dy, dz, max): number
			local lo, hi = 0, max
			local mins = { b.x - b.sx / 2, b.base, b.z - b.sz / 2 }
			local maxs = { b.x + b.sx / 2, b.top, b.z + b.sz / 2 }
			local o, d = { ox, oy, oz }, { dx, dy, dz }
			for a = 1, 3 do
				if math.abs(d[a]) < 1e-9 then
					if o[a] < mins[a] or o[a] > maxs[a] then
						return max
					end
				else
					local t1, t2 = (mins[a] - o[a]) / d[a], (maxs[a] - o[a]) / d[a]
					lo, hi = math.max(lo, math.min(t1, t2)), math.min(hi, math.max(t1, t2))
				end
			end
			return if lo <= hi then lo else max
		end
		local function ray(ox, oy, oz, dx, dy, dz, max)
			local best = max
			for _, b in world.buildings do
				if b.sx and (book.state[b.id] or 0) == 0 then
					best = math.min(best, boxHit(b, ox, oy, oz, dx, dy, dz, best))
				end
			end
			return BuildingState.ray(D, book, ox, oy, oz, dx, dy, dz, best)
		end
		local sword = A.list.W5M1 -- the Sword's combo (an arc: basic, range 9)
		local slash = A.list.W5X or A.list.W5Z
		check(sword ~= nil and sword.shape == "arc", "the sword's combo is an arc")
		local tried, oldWalls, newWalls, newSkill = 0, 0, 0, 0
		local cone, coneOld, coneNew = nil, 0, 0
		for _, row in A.list do
			if
				row.shape == "cone"
				and (row.range or 0) >= 20
				and not row.structDmg
				and row.slot == "skill"
			then
				if not cone or row.id < cone.id then
					cone = row
				end
			end
		end
		check(cone ~= nil, "a long cone power to try")
		for k = 1, #world.buildings, 7 do
			local b = world.buildings[k]
			local grid = b and BuildingState.grid(D, book, b.id)
			if grid and b.sz > 14 and b.sx > 14 and not BuildingState.pinned(book, b.id) and tried < 12 then
				tried += 1
				local ox, oy, oz = b.x, b.base + 4, b.z - b.sz / 2 - 1 -- 1 stud in front of the -z face
				local ax, ay, az = ox, oy, oz + sword.range
				local wx, wy, wz = BuildingState.wallPoint(D, ox, oy, oz, ax, ay, az, ray)
				check(
					math.abs(wz - (b.z - b.sz / 2)) < 1,
					string.format(
						"the slash lands on the face (building %d: %.2f vs face %.2f, reach end %.2f)",
						b.id,
						wz,
						b.z - b.sz / 2,
						az
					)
				)
				local function walls(x, y, z, eff, times): number
					local bk = BuildingState.new(D, world.buildings)
					local dmg = BuildingState.abilityStruct(D, eff)
					local radius = math.min(eff.radius or 12, D.basicStructRadius)
					if eff.slot ~= "basic" then
						radius = eff.radius or 12
					end
					local count = 0
					for t = 1, times do
						local r =
							BuildingState.blast(D, bk, b.id, x, BuildingState.blastY(b, y), z, radius, dmg, t)
						local g = BuildingState.grid(D, bk, b.id)
						for _, i in r.hit do
							if g.pieces[i].kind == "wall" then
								count += 1
							end
						end
					end
					return count
				end
				local o, w = walls(ax, ay, az, sword, 4), walls(wx, wy, wz, sword, 4)
				oldWalls += o -- before: the blast at full reach, 7 studs inside
				newWalls += w
				if slash then
					newSkill += walls(wx, wy, wz, slash, 1)
				end
				-- a cone power (its reach far inside the building before)
				if cone then
					local cx, cy, cz = BuildingState.wallPoint(D, ox, oy, oz, ox, oy, oz + cone.range, ray)
					coneOld += walls(ox, oy, oz + cone.range, cone, 1)
					coneNew += walls(cx, cy, cz, cone, 1)
				end
			end
		end
		check(tried >= 6, "buildings tried (" .. tried .. ")")
		check(
			newWalls >= tried,
			string.format("four slashes open every wall (%d walls on %d)", newWalls, tried)
		)
		check(
			newWalls > oldWalls,
			string.format("more than at full reach (%d now, %d before)", newWalls, oldWalls)
		)
		check(
			coneNew >= tried and coneOld < coneNew,
			string.format(
				"a cone power breaks the wall it meets (%d walls, %d at full reach)",
				coneNew,
				coneOld
			)
		)
		check(newSkill >= tried, string.format("one sword skill breaks the wall too (%d)", newSkill))
		-- the server runs the same: CombatService.wallPoint over BuildingState.wallPoint; chips show (kind 4)
		local cs = fs.readFile("src/server/Services/CombatService.luau")
		check(
			string.find(cs, "at = wallPoint(origin, at)", 1, true) ~= nil,
			"casts blast where they meet a wall"
		)
		local bs = fs.readFile("src/server/Services/BuildingService.luau")
		check(
			string.find(bs, "chip(center, radius)", 1, true) ~= nil,
			"a hit that breaks nothing yet sends a chip"
		)
		local fx = fs.readFile("src/client/Fx/BuildingFx.luau")
		check(string.find(fx, "if kind == 4 then", 1, true) ~= nil, "devices draw the chip")
		check(
			string.find(fx, 'AudioController.play("wallSmash", knockAt', 1, true) ~= nil,
			"a knocked piece crunches"
		)
	end)

	test("List combat: every weapon look has its own swing and hit sound from the atlases (202)", function()
		local SoundPick = require("../src/shared/SoundPick")
		local fs = require("@lune/fs")
		for look in Config.Fx.weaponLooks.looks do
			local row = Config.Audio.weapons[look]
			check(row ~= nil, look .. " has sounds")
			if row then
				for _, moment in { "cast", "hit" } do
					local spec = row[moment]
					check(spec ~= nil, look .. " " .. moment)
					if spec then
						local regions = SoundPick.variants(Config.AudioClips, spec.clip)
						check(
							#regions > 0,
							look .. " " .. moment .. " clip " .. tostring(spec.clip) .. " is recorded"
						)
						check(
							spec.volume > 0 and spec.volume <= 0.5,
							look .. " " .. moment .. " sits under the hit thud"
						)
					end
				end
			end
		end
		local juice = fs.readFile("src/client/Fx/Juice.luau")
		check(
			string.find(juice, "A.weapons[string.sub(set, 8)]", 1, true) ~= nil,
			"Juice.path plays Weapon:<look>"
		)
		local cc = fs.readFile("src/client/Controllers/CombatClient.luau")
		check(
			string.find(cc, 'Juice.path(CombatFx.setOf(eff), "cast", origin)', 1, true) ~= nil,
			"your swing"
		)
		check(string.find(cc, 'Juice.path(fxSet, "cast", r.o)', 1, true) ~= nil, "others' swings")
		check(
			string.find(cc, "CombatFx.setOf(row), -- a weapon move's own hit sound", 1, true) ~= nil,
			"the hit"
		)
	end)
end
