-- Perf pass (2026-11-18): the measured fixes keep what they replace. Each test checks a fast path against the
-- slow one it stands in for (the same props, the same bytes), and the packet and draw caps. Run by run.luau.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local WorldMap = require("../src/shared/WorldMap")

	local function sameProps(a: { any }, b: { any }): boolean
		if #a ~= #b then
			return false
		end
		for i, p in a do
			local q = b[i]
			if
				not (
					q.name == p.name
					and q.x == p.x
					and q.y == p.y
					and q.z == p.z
					and q.ry == p.ry
					and q.d == p.d
				)
			then
				return false
			end
		end
		return true
	end

	test("Perf: the props-only job gives the full build's street props for 3 seeds", function()
		for _, seed in { 202647, 1, 99991 } do
			local full = WorldMap.build(Config, seed).props
			local fast = WorldMap.props(Config, seed)
			check(
				#full > 5000 and sameProps(full, fast),
				string.format("seed %d: same %d props, same order", seed, #full)
			)
			-- a device runs it a few tiles a step: the same list again
			local job = WorldMap.propsJob(Config, seed)
			local steps = 0
			while not WorldMap.propsStep(job, 4) do
				steps += 1
			end
			check(
				steps > 100 and sameProps(full, job.props),
				string.format("seed %d: in %d small steps too", seed, steps)
			)
		end
		local bare = table.clone(Config)
		bare.City = table.clone(Config.City)
		bare.City.kit = nil
		check(#WorldMap.props(bare, 202647) == 0, "no kit, no props")
	end)

	-- The Enemy.Delta encoder before the perf pass, word for word: the new one must give the same bytes
	local function oldEncode(
		sequence: number,
		time: number,
		enemies: { any },
		px: number,
		py: number,
		pz: number,
		radius: number,
		maxCount: number
	): buffer
		local function i16(value: number): number
			return math.clamp(math.floor(value * 10 + 0.5), -32768, 32767)
		end
		local picked = {}
		local r2 = radius * radius
		for _, e in enemies do
			if e.alive then
				local dx, dy, dz = e.x - px, e.y - py, e.z - pz
				local d2 = dx * dx + dy * dy + dz * dz
				if d2 <= r2 then
					table.insert(picked, { e = e, d2 = d2 })
				end
			end
		end
		if #picked > maxCount then
			table.sort(picked, function(a, b)
				return a.d2 < b.d2
			end)
		end
		local count = math.min(#picked, maxCount)
		local b = buffer.create(10 + 13 * count)
		buffer.writeu32(b, 0, sequence % 4294967296)
		buffer.writef32(b, 4, time)
		buffer.writeu16(b, 8, count)
		local offset = 10
		for i = 1, count do
			local e = picked[i].e
			buffer.writeu16(b, offset, e.id)
			buffer.writei16(b, offset + 2, i16(e.x))
			buffer.writei16(b, offset + 4, i16(e.y))
			buffer.writei16(b, offset + 6, i16(e.z))
			buffer.writeu8(
				b,
				offset + 8,
				math.floor(math.clamp(e.health / math.max(1, e.maxHealth), 0, 1) * 255 + 0.5)
			)
			buffer.writeu8(b, offset + 9, (e.state % 8) + (e.typeId % 32) * 8)
			buffer.writeu8(b, offset + 10, (e.flags or 0) % 256)
			buffer.writeu8(
				b,
				offset + 11,
				math.floor(((e.yaw or 0) % (2 * math.pi)) / (2 * math.pi) * 256) % 256
			)
			buffer.writeu8(b, offset + 12, (e.extra or 0) % 256)
			offset += 13
		end
		return b
	end

	local EnemyBuffer = require("../src/shared/EnemyBuffer")
	local Rng = require("../src/shared/Rng")
	local function scene(seed: number, n: number, grid: boolean): { any }
		local rng = Rng.new(seed)
		local list = {}
		for i = 1, n do
			local x, y, z
			if grid then
				-- whole studs on a small grid: many robots exactly as far as each other (ties)
				x, y, z = rng:int(-20, 20) * 5, 3, rng:int(-20, 20) * 5
			else
				x, y, z = (rng:next() - 0.5) * 900, rng:next() * 60, (rng:next() - 0.5) * 900
			end
			table.insert(list, {
				id = i,
				alive = rng:next() > 0.1,
				x = x,
				y = y,
				z = z,
				health = rng:int(0, 400),
				maxHealth = 400,
				state = rng:int(0, 7),
				typeId = rng:int(1, 31),
				flags = rng:int(0, 255),
				yaw = rng:next() * 7,
				extra = rng:int(0, 255),
			})
		end
		return list
	end

	test("Perf: Enemy.Delta packs the same bytes as before (scratch arrays, no closure sort)", function()
		local cases, same, tied = 0, 0, 0
		for seed = 1, 40 do
			local grid = seed % 2 == 0
			local list = scene(seed, if seed % 3 == 0 then 140 else 90, grid)
			for _, cap in { 0, 1, 20, 24, 44, 60, 64 } do
				for _, at in { { 0, 0, 0 }, { 120, 10, -80 }, { -400, 0, 300 } } do
					for _, radius in { 450, 120 } do
						cases += 1
						local a = oldEncode(seed, seed * 0.1, list, at[1], at[2], at[3], radius, cap)
						local b =
							EnemyBuffer.encodeFor(seed, seed * 0.1, list, at[1], at[2], at[3], radius, cap)
						if buffer.tostring(a) == buffer.tostring(b) then
							same += 1
						end
						if grid then
							tied += 1
						end
					end
				end
			end
		end
		check(
			same == cases,
			string.format("%d of %d packets byte for byte (%d with tied distances)", same, cases, tied)
		)
		-- a shorter list after a longer one: nothing left over from the last call leaks into the packet
		local long = scene(7, 140, false)
		local short = scene(8, 30, false)
		EnemyBuffer.encodeFor(1, 0, long, 0, 0, 0, 450, 20)
		check(
			buffer.tostring(EnemyBuffer.encodeFor(2, 0, short, 0, 0, 0, 450, 20))
				== buffer.tostring(oldEncode(2, 0, short, 0, 0, 0, 450, 20)),
			"a short list after a long one"
		)
		check(
			buffer.len(EnemyBuffer.encodeFor(3, 0, {}, 0, 0, 0, 450, 20)) == EnemyBuffer.HEADER,
			"an empty list"
		)
	end)

	test("Perf: an Enemy.Delta packet never passes the 900-byte unreliable limit", function()
		local list = scene(3, 400, false)
		for _, cap in { 60, 65, 66, 100, 1000 } do
			local b = EnemyBuffer.encodeFor(1, 0, list, 0, 0, 0, 5000, cap)
			check(
				buffer.len(b) <= EnemyBuffer.LIMIT - EnemyBuffer.MARGIN,
				string.format("asked for %d: %d B, at most %d robots", cap, buffer.len(b), EnemyBuffer.MAX)
			)
			local alive = 0
			for _, e in list do
				if e.alive then
					alive += 1
				end
			end
			local _, _, rows = EnemyBuffer.decode(b)
			check(#rows == math.min(cap, EnemyBuffer.MAX, alive), "and it decodes")
		end
		-- past the cap it still sends the nearest, nearest first
		local b = EnemyBuffer.encodeFor(1, 0, list, 0, 0, 0, 5000, 1000)
		local _, _, rows = EnemyBuffer.decode(b)
		local inOrder = true
		for i = 2, #rows do
			local p, q = rows[i - 1], rows[i]
			if p.x * p.x + p.y * p.y + p.z * p.z > q.x * q.x + q.y * q.y + q.z * q.z + 1 then
				inOrder = false
			end
		end
		check(inOrder, "the nearest robots, nearest first")
		check(
			EnemyBuffer.MAX >= 60 and EnemyBuffer.LIMIT == 900,
			"the limit leaves room for the high preset's 60"
		)
	end)

	test("Perf: Enemy.Delta sends each player what its device draws", function()
		local QualityRules = require("../src/shared/QualityRules")
		local P = Config.Presets
		local spare = Config.Net.enemySpare
		local function n(device: string?, chosen: number?): number
			return QualityRules.enemiesFor(P, device, chosen, spare)
		end
		check(n("phone", 0) == P.low.enemiesDrawn + spare, "a phone on Auto: low's 20 and the spare")
		check(n("tablet", 0) == P.medium.enemiesDrawn + spare, "a tablet on Auto: medium (it never steps up)")
		check(n("pc", 0) == P.high.enemiesDrawn + spare, "a PC on Auto may step up to high")
		check(n("console", nil) == P.high.enemiesDrawn + spare, "a console too")
		check(n(nil, 0) == P.high.enemiesDrawn + spare, "no hello yet: high")
		check(n("phone", 3) == P.high.enemiesDrawn + spare, "a phone set to High gets high's")
		check(n("pc", 1) == P.low.enemiesDrawn + spare, "a PC set to Low gets low's")
		local worst = 0
		for _, device in { "phone", "tablet", "pc", "console" } do
			for chosen = 0, #P.order do
				worst = math.max(worst, n(device, chosen))
			end
		end
		check(
			worst <= EnemyBuffer.MAX
				and EnemyBuffer.HEADER + worst * EnemyBuffer.PER <= EnemyBuffer.LIMIT - EnemyBuffer.MARGIN,
			string.format("the most any device is sent (%d) fits one packet", worst)
		)
		print(
			string.format(
				"  Enemy.Delta: phone %d B, PC %d B a packet",
				EnemyBuffer.HEADER + n("phone", 0) * EnemyBuffer.PER,
				EnemyBuffer.HEADER + worst * EnemyBuffer.PER
			)
		)
	end)

	test("Perf: clothes Textures drop with distance per preset, the tucked faces first", function()
		local ClothesMap = require("../src/shared/ClothesMap")
		local parts = { "Head", "UpperTorso", "LowerTorso" }
		for _, side in { "Left", "Right" } do
			for _, p in { "UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot" } do
				table.insert(parts, side .. p)
			end
		end
		local all, tucked = 0, 0
		for _, p in parts do
			for _, f in ClothesMap.FACES do
				if ClothesMap.rect(p, f) then
					all += 1
					if ClothesMap.tucked(p, f) then
						tucked += 1
					end
				end
			end
		end
		check(all == 66 and tucked == 21, string.format("%d Textures a rig, %d tucked", all, tucked))
		-- never a face the camera sees head on: every part's front and back stay
		for _, p in parts do
			check(
				not ClothesMap.tucked(p, "Front") and not ClothesMap.tucked(p, "Back"),
				p .. " front and back stay"
			)
		end
		check(
			ClothesMap.tucked("LeftUpperLeg", "Right") and ClothesMap.tucked("RightUpperLeg", "Left"),
			"inner thighs"
		)
		check(
			not ClothesMap.tucked("LeftUpperLeg", "Left") and not ClothesMap.tucked("RightLowerArm", "Right"),
			"outer sides stay"
		)
		-- levels, with a 10% hold so a rig on an edge never flickers
		check(
			ClothesMap.level(10, 25, 80) == 2
				and ClothesMap.level(50, 25, 80) == 1
				and ClothesMap.level(90, 25, 80) == 0,
			"near, mid, far"
		)
		check(ClothesMap.level(26, 25, 80, 2) == 2 and ClothesMap.level(28, 25, 80, 2) == 1, "held past near")
		check(ClothesMap.level(85, 25, 80, 1) == 1 and ClothesMap.level(89, 25, 80, 1) == 0, "held past far")
		check(ClothesMap.level(85, 25, 80, 0) == 0 and ClothesMap.level(79, 25, 80, 0) == 1, "coming back in")
		local P = Config.Presets
		local last = nil
		for _, name in P.order do
			local q = P[name]
			check(q.clothesNear > 0 and q.clothesNear < q.clothesFar, name .. ": near inside far")
			if last then
				check(
					q.clothesFar >= last.clothesFar and q.clothesNear >= last.clothesNear,
					name .. " draws at least the preset below"
				)
			end
			last = q
		end
		check(P.medium.clothesFar == 80, "about 80 studs on medium")
		-- a crowd: rigs past clothesFar draw none
		local function textures(preset: any, dists: { number }): number
			local n = 0
			for _, d in dists do
				local lv = ClothesMap.level(d, preset.clothesNear, preset.clothesFar)
				n += if lv == 2 then all elseif lv == 1 then all - tucked else 0
			end
			return n
		end
		local crowd = {}
		for i = 1, 50 do
			table.insert(crowd, i * 8) -- 8 to 400 studs
		end
		print(
			string.format(
				"  clothes Textures, 50 rigs 8 to 400 studs: low %d, high %d (were %d)",
				textures(P.low, crowd),
				textures(P.high, crowd),
				50 * all
			)
		)
	end)

	test("Perf: robot poses and the body pool are set per preset", function()
		local P = Config.Presets
		for _, name in P.order do
			local q = P[name]
			check(q.enemyPoseNear > 0 and q.enemyPoseEvery >= 1, name .. " poses robots")
			check(q.enemyPool.keep >= 1 and q.enemyPool.idle > 0, name .. " keeps a few spare bodies")
		end
		check(
			P.low.enemyPoseNear < P.high.enemyPoseNear and P.low.enemyPoseEvery > P.high.enemyPoseEvery,
			"phones pose fewer"
		)
		check(
			P.high.enemyPoseNear == Config.Enemies.look.poseNear
				and P.high.enemyPoseEvery == Config.Enemies.look.poseEvery,
			"high keeps what every device drew before"
		)
	end)

	test("Perf: every face decal is exported at 256 px", function()
		local fs = require("@lune/fs")
		local n, bad = 0, {}
		for _, dir in { "art/export/clothes/faces", "art/export/clothes/people" } do
			for _, f in fs.readDir(dir) do
				if string.match(f, "^Face_.*%.png$") then
					n += 1
					local png = buffer.fromstring(fs.readFile(dir .. "/" .. f))
					local w, h =
						bit32.byteswap(buffer.readu32(png, 16)), bit32.byteswap(buffer.readu32(png, 20))
					if w ~= 256 or h ~= 256 then
						table.insert(bad, f .. " " .. w .. "x" .. h)
					end
				end
			end
		end
		check(
			n == 35 and #bad == 0,
			string.format("%d faces, %d not 256 px %s", n, #bad, table.concat(bad, ", "))
		)
	end)
end
