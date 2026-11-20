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

	test("List combat: the held guard is a built energy shield", function()
		local S = Config.Guard.shield
		check(S.sides >= 6 and S.raise > 0 and S.raise < 0.3 and S.kick > 1, "the shield's shape and timing")
		-- each rim piece sits on the edge, tangent to it, and the pieces meet: rotate about x, push up by the
		-- apothem, the piece's long axis (z) along the edge
		local r = S.size / 2
		local ap = r * math.cos(math.pi / S.sides)
		local side = 2 * r * math.tan(math.pi / S.sides) + 0.05
		for i = 1, S.sides do
			local a = (i - 0.5) / S.sides * 2 * math.pi
			local cy, cz = ap * math.cos(a), ap * math.sin(a) -- the piece's centre (Angles(a,0,0) * (0, ap, 0))
			local ty, tz = -math.sin(a), math.cos(a) -- its long axis
			check(math.abs(cy * ty + cz * tz) < 1e-6, "rim piece " .. i .. " is tangent")
			local ey, ez = cy + ty * side / 2, cz + tz * side / 2
			check(math.sqrt(ey * ey + ez * ez) >= r - 0.01, "rim piece " .. i .. " reaches the corner")
		end
		local fx = fs.readFile("src/client/Fx/GuardFx.luau")
		for _, needle in
			{
				"buildShield()",
				"Workspace:BulkMoveTo(hs.parts, cfs",
				"BlockClient.guard()",
				"hs.hitAt = os.clock()",
				'FrameProf.wrap("GuardFx", step)',
				"CFrame.Angles(a, 0, 0) * CFrame.new(0, r * math.cos(math.pi / S.sides), 0)",
			}
		do
			check(string.find(fx, needle, 1, true) ~= nil, "GuardFx: " .. needle)
		end
		-- the body's guard pose is played while Blocking (HeroAnimator), so the hero is not just walking
		local ha = fs.readFile("src/client/Controllers/HeroAnimator.luau")
		check(
			string.find(ha, 'return if shield then "guardShield" else "guard"', 1, true) ~= nil,
			"the guard pose"
		)
		check(Config.Guard.block.moveMult <= 0.5, "blocking slows you to half speed or less")
	end)

	test("List combat: throwables look like what they are", function()
		local Th = Config.Throw
		local n = 0
		for kind, K in Th.kinds do
			if K.wreck or K.vehicle or kind == "robot" or not K.size then
				continue
			end
			local d = Th.dress[kind]
			check(d ~= nil, kind .. " has a look")
			if not d then
				continue
			end
			n += 1
			if d.mesh then
				local def = Config.City.kit.props[d.mesh]
				check(def ~= nil, kind .. ": " .. d.mesh .. " is a kit prop")
				local fit = Config.StreetArt[d.mesh] or Config.LifeArt[d.mesh]
				for piece in (if def then def.pieces else {}) do
					check(fit ~= nil and fit[piece] ~= nil, kind .. ": " .. piece .. " has its fit")
				end
			end
			for i, p in d.parts or {} do
				-- every piece stays in or near its box (the box keeps the hits)
				local r = 0
				for j = 1, 3 do
					r = math.max(r, math.abs(p.at[j]) - K.size[j] / 2)
				end
				check(r <= 0.65, string.format("%s piece %d sits on its box (%.2f out)", kind, i, r))
				check(p.color and #p.color == 3 and #p.size == 3, kind .. " piece " .. i .. " is complete")
			end
		end
		check(n >= 9, "every street throwable has a look (" .. n .. ")")
		-- the runtime path: ThrowFx dresses each Throwables model; the place has the meshes it uses
		local fx = fs.readFile("src/client/Fx/ThrowFx.luau")
		check(
			string.find(fx, "CityProps.dress(d.mesh, body, T.kinds[kind].size[2])", 1, true) ~= nil,
			"mesh path"
		)
		check(string.find(fx, "body.LocalTransparencyModifier = 1", 1, true) ~= nil, "the box hides here")
		check(string.find(fx, "CityProps.dressParts(body, d.parts)", 1, true) ~= nil, "part path")
		check(string.find(fx, "props.ChildAdded:Connect(added)", 1, true) ~= nil, "new props are dressed")
		if T.placePath then
			local roblox = require("@lune/roblox")
			local game = roblox.deserializePlace(fs.readFile(T.placePath))
			local art = game:GetService("ReplicatedStorage"):FindFirstChild("Art")
			for kind, d in Th.dress do
				if d.mesh then
					local fromLife = Config.LifeArt[d.mesh] ~= nil and Config.StreetArt[d.mesh] == nil
					local root = art and art:FindFirstChild(if fromLife then Config.Life.set else "Street")
					for piece in Config.City.kit.props[d.mesh].pieces do
						local m = root and root:FindFirstChild(piece, true)
						check(m ~= nil and m:IsA("MeshPart"), kind .. ": the place has " .. piece)
					end
				end
			end
		end
	end)

	test("List combat: powers' props and Bullet Time's screen", function()
		local cf = fs.readFile("src/client/Fx/CombatFx.luau")
		-- 176: the thrown crate wears the street kit's Crate mesh, its planks burst on landing
		check(
			string.find(cf, 'CityProps.dress("Crate", body, body.Size.Y)', 1, true) ~= nil,
			"the crate mesh"
		)
		check(Config.City.kit.props.Crate ~= nil and Config.StreetArt.Crate ~= nil, "Crate is a kit prop")
		-- 178: Girder Swing swings a girder in the right hand
		check(string.find(cf, 'if row.id == "GirderSwing" then', 1, true) ~= nil, "the held girder")
		-- 181: Psi Platform's slab carries a crate and a barrel (kit meshes), faded with the ride
		check(
			string.find(cf, 'for i, name in { [3] = "Crate", [4] = "Barrel" } do', 1, true) ~= nil,
			"psi junk"
		)
		check(
			string.find(cf, "CityProps.dress(name, holder, holder.Size.Y, dressed)", 1, true) ~= nil,
			"dressed"
		)
		check(Config.City.kit.props.Barrel ~= nil and Config.StreetArt.Barrel ~= nil, "Barrel is a kit prop")
		check(Config.Abilities.list.GirderSwing ~= nil, "Girder Swing exists")
		-- 173: Bullet Time's own screen for its whole field, on the caster's screen only
		check(Config.FxMoves.moves.BulletTime.screen == "slowmo", "Bullet Time has its screen")
		check(Config.Abilities.list.BulletTime.duration > 0, "it lasts the field's time")
		local af = fs.readFile("src/client/Fx/AbilityFx.luau")
		check(string.find(af, "SCREEN.slowmo = function", 1, true) ~= nil, "slowmo is drawn")
		check(
			string.find(cf, 'row.slot == "skill" and userId == Players.LocalPlayer.UserId', 1, true) ~= nil,
			"skills' screens play for the caster"
		)
	end)

	test("List combat: a giant looks and walks like one", function()
		local G = Config.Fx.giant
		local A = Config.Abilities.list
		check(G.forms.giant == A.Grow.scale and A.Grow.form == "giant", "Grow's scale")
		check(G.forms.titan == A.TitanForm.scale and A.TitanForm.form == "titan", "Titan Form's scale")
		check(G.crushAt > G.forms.giant and G.crushAt <= G.forms.titan, "only the titan crushes underfoot")
		check(G.shake.range > 0 and G.stride > 2, "steps and shake")
		local src = fs.readFile("src/client/Fx/FormFx.luau")
		for _, needle in
			{
				'p:GetAttribute("Form")',
				'Instance.new("Highlight")',
				"FormFx.stride(g.form)",
				"BuildingFx.smashAt(at, 3 * scale)",
				'FrameProf.wrap("FormFx", step)',
			}
		do
			check(string.find(src, needle, 1, true) ~= nil, "FormFx: " .. needle)
		end
		local init = fs.readFile("src/client/init.client.luau")
		check(string.find(init, "FormFx.init()", 1, true) ~= nil, "FormFx runs")
		local hs = fs.readFile("src/server/Services/HeroService.luau")
		check(string.find(hs, 'player:SetAttribute("Form", form)', 1, true) ~= nil, "the server sets Form")
	end)

	test("List combat: capes sway with the hero", function()
		local K = Config.Fx.cape
		check(K.lift > 30 and K.max <= 90 and K.follow > 0 and K.count >= 8, "the sway's numbers")
		-- the turn CapeSway uses, CFrame.Angles(-lift, 0, side), carries the hanging drape (0, -1, 0) backward (+z)
		-- and up, and a strafe to the right swings it left
		local lift = math.rad(40)
		local y, z = -math.cos(-lift), -math.sin(-lift) -- Rx(a) * (0, -1, 0) = (0, -cos a, -sin a)
		check(z > 0.5 and y > -0.9, "lift swings the cape back and up")
		local side = math.rad(-K.side) -- a strafe right gives side < 0
		check(math.sin(side) < 0, "a strafe right swings it left") -- Rz(b) * (0, -1, 0) = (sin b, -cos b, 0)
		local src = fs.readFile("src/client/Fx/CapeSway.luau")
		for _, needle in
			{
				'd:GetAttribute("Sway") == true',
				"wc.Enabled = false",
				"CFrame.Angles(-math.rad(r.lift), 0, math.rad(r.side))",
				'FrameProf.wrap("CapeSway", step)',
				"math.min(#near, K.count)",
			}
		do
			check(string.find(src, needle, 1, true) ~= nil, "CapeSway: " .. needle)
		end
		local lk = fs.readFile("src/shared/LookKit.luau")
		check(string.find(lk, 'p:SetAttribute("Sway", true)', 1, true) ~= nil, "LookKit marks the drape")
		check(
			string.find(lk, 'if tab == "back" and kit and string.sub(kit, 1, 5) == "cape:" then', 1, true)
				~= nil,
			"capes only"
		)
		local init = fs.readFile("src/client/init.client.luau")
		check(string.find(init, "CapeSway.init()", 1, true) ~= nil, "CapeSway runs")
	end)

	test("List combat: the place's LookKit marks only a cape's drape to sway", function()
		if not T.placePath then
			return
		end
		local roblox = require("@lune/roblox")
		local WeaponSim = require("./weaponsim")
		local sim = WeaponSim.new(roblox.deserializePlace(fs.readFile(T.placePath)))
		local Cfg = sim:module("Config")
		local LookKit = sim:module("Shared.LookKit")
		local CreatorRules = sim:module("Shared.CreatorRules")
		local capes = 0
		for i, piece in CreatorRules.index(Cfg).byTab.back or {} do
			if string.sub(piece.kit or "", 1, 5) ~= "cape:" then
				continue
			end
			capes += 1
			local look = CreatorRules.defaultLook(Cfg)
			look.pieces.back = i
			local char = sim:body()
			LookKit.build(char, look)
			local torso = char:FindFirstChild("UpperTorso")
			local swung, kept = 0, 0
			for _, d in char:GetDescendants() do
				if d:IsA("BasePart") and d.Name == "back" then
					local y = torso.CFrame:PointToObjectSpace(d.CFrame.Position).Y - d.Size.Y / 2 -- its lowest edge
					if d:GetAttribute("Sway") == true then
						swung += 1
						check(y < 0, piece.kit .. ": a swung piece hangs past the middle")
					else
						kept += 1
						check(y >= 0, piece.kit .. ": a piece left still sits up on the shoulders")
					end
				end
			end
			check(swung >= 1, piece.kit .. " has a drape that sways (" .. swung .. ", " .. kept .. " kept)")
		end
		check(capes >= 6, "capes checked: " .. capes)
		-- a look without a cape marks nothing
		local plain = CreatorRules.defaultLook(Cfg)
		plain.pieces.back = 0
		local char = sim:body()
		LookKit.build(char, plain)
		local any = false
		for _, d in char:GetDescendants() do
			any = any or d:GetAttribute("Sway") == true
		end
		check(not any, "no cape, nothing sways")
	end)

	test("List combat: the boss result card stays under the top row of buttons", function()
		local TouchLayout = require("../src/shared/TouchLayout")
		local P = Config.Ui.phone
		for _, screen in { { 800, 360 }, { 667, 300 }, { 1280, 720 }, { 1920, 1080 }, { 390, 800 } } do
			for _, cardH in { 200, 250, 320, 380 } do
				local w, h = screen[1], screen[2]
				local k, top = TouchLayout.cardBelowRow(Config, w, h, 380, cardH)
				local row = if math.min(w, h) < P.compactBelow then P.rowCompact else P.row
				local tag = string.format("%dx%d card %d", w, h, cardH)
				check(top >= row + P.gap - 1e-6, tag .. ": below the row")
				check(top + cardH * k <= h + 1e-6 or k == 0.5, tag .. ": on screen")
				check(380 * k <= w, tag .. ": fits across")
				check(k <= 1 and k >= 0.5, tag .. ": scale " .. k)
			end
		end
		local hud = fs.readFile("src/client/Ui/WorldHud.luau")
		check(
			string.find(hud, "TouchLayout.cardBelowRow(Config, a.X, a.Y, 380, cardH)", 1, true) ~= nil,
			"used"
		)
	end)

	test("List combat: the drawn logo is on the loading card and the menu", function()
		local card = fs.readFile("src/first/LoadingCard.luau")
		local id = tonumber(string.match(card, "LoadingCard.LOGO = (%d+)"))
		check(id ~= nil and id > 0, "the loading card has the logo's id")
		check(Config.Ui.logo == id, "the menu shows the same logo")
		check(
			string.find(card, "if drawn.IsLoaded then", 1, true) ~= nil,
			"the typed title stays until it loads"
		)
		local menu = fs.readFile("src/client/Ui/MainMenu.luau")
		check(string.find(menu, '"rbxassetid://" .. Config.Ui.logo', 1, true) ~= nil, "the menu draws it")
		check(fs.isFile("art/ui/logo.py") and fs.isFile("art/preview/logo.png"), "its source and preview")
	end)

	test("List combat: HOW TO PLAY covers the deeper systems", function()
		local pages = Config.Ui.help
		local want =
			{ MOVE = true, FIGHT = true, BLOCK = true, POWERS = true, GEAR = true, ["HERO PASS"] = true }
		for _, p in pages do
			want[p.title] = nil
			check(#p.lines >= 3 and #p.lines <= 4, p.title .. " has 3 or 4 lines (they fit the page)")
			for _, l in p.lines do
				check(#l <= 90, p.title .. ": a line fits two rows: " .. l)
			end
		end
		check(next(want) == nil, "every topic has a page")
		-- the lines say what the game does
		check(
			Config.Abilities.borrowLevel == 15 and Config.Abilities.borrowMax == 5,
			"borrowing: level 15, 5 skills"
		)
		check(Config.Abilities.respecCooldown == 600, "respec every 10 minutes")
		check(Config.Gear.upgrade.max == 10, "upgrade to +10")
		check(Config.Guard.block.moveMult == 0.5, "half speed while blocking")
		local input = fs.readFile("src/client/Controllers/InputController.luau")
		for _, k in { '[Enum.KeyCode.Q] = "Block"', '[Enum.KeyCode.F] = "Fly"', '[Enum.KeyCode.G] = "Super"' } do
			check(string.find(input, k, 1, true) ~= nil, "the keys: " .. k)
		end
		local init = fs.readFile("src/client/init.client.luau")
		check(string.find(init, "HelpHud.init()", 1, true) ~= nil, "HelpHud runs")
		local hud = fs.readFile("src/client/Ui/HelpHud.luau")
		check(string.find(hud, 'Kit.dock(open, "Help", 19)', 1, true) ~= nil, "it is in the MENU drawer")
	end)

	test("List combat: HOW TO PLAY opens and turns pages in the place's client", function()
		if not T.placePath then
			return
		end
		local roblox = require("@lune/roblox")
		local UiSim = require("./uisim")
		local trees = UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath)))
		for _, device in
			{
				{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false },
				{
					name = "Phone",
					w = 812,
					h = 375,
					top = 0,
					left = 44,
					right = 44,
					bottom = 21,
					touch = true,
				},
			}
		do
			local sim = UiSim.new(trees, device)
			sim:run("InputController", sim:require("Client.Controllers.InputController").init)
			sim:run("Hud", sim:require("Client.Ui.Hud").init)
			sim:run("HelpHud", sim:require("Client.Ui.HelpHud").init)
			local gui = sim.playerGui:FindFirstChild("HelpHud")
			local function find(name: string): any
				for _, d in (gui and gui:GetDescendants() or {}) do
					if d.Name == name then
						return d
					end
				end
				return nil
			end
			local open = sim.playerGui:FindFirstChild("HelpButton", true)
			check(open ~= nil, device.name .. ": the HOW TO PLAY button is made")
			sim:run("open", function()
				sim:require("Client.Ui.HelpHud").open()
			end)
			local page = find("Page")
			local panel = page and page.Parent
			check(panel ~= nil and panel.Visible, device.name .. ": the panel shows")
			local function texts(): { string }
				local out = {}
				for _, c in (page and page:GetChildren() or {}) do
					if c:IsA("TextLabel") then
						table.insert(out, c.Text)
					end
				end
				return out
			end
			local first = texts()
			check(#first == 1 + #Config.Ui.help[1].lines, device.name .. ": the first page's title and lines")
			-- tap the GEAR tab
			local gearTab = nil
			for _, d in panel and panel:GetChildren() or {} do
				if d:IsA("TextButton") and d.Text == "GEAR" then
					gearTab = d
				end
			end
			check(gearTab ~= nil, device.name .. ": a GEAR tab")
			if gearTab then
				sim:tap(gearTab)
			end
			check(table.find(texts(), "GEAR") ~= nil, device.name .. ": the GEAR page shows")
			check(#sim.errors == 0, device.name .. ": no errors: " .. table.concat(sim.errors, "; "))
		end
	end)

	test("List combat: the car flip's effects are library particles", function()
		local src = fs.readFile("src/client/Fx/VehicleFx.luau")
		check(not string.find(src, 'Instance.new("Part")', 1, true), "no plain parts left")
		for _, kind in { "spark", "chip", "shard" } do
			check(string.find(src, 'FxLib.emit("' .. kind .. '"', 1, true) ~= nil, "emits " .. kind)
			check(Config.Fx.lib.kinds[kind] ~= nil, kind .. " is a library kind")
		end
	end)

	test("List combat: PC keys can be rebound and are saved", function()
		local SettingsRules = require("../src/shared/SettingsRules")
		local roblox = require("@lune/roblox")
		local S = Config.Settings
		-- every bindable key's saved number is Roblox's own KeyCode value
		for name, n in S.bindable do
			local ok, code = pcall(function()
				return (roblox.Enum.KeyCode :: any)[name]
			end)
			check(ok and code and code.Value == n, name .. " is KeyCode " .. n)
		end
		for _, bad in { "Escape", "Return", "Backspace", "Slash", "F9", "LeftAlt" } do
			check(S.bindable[bad] == nil, bad .. " can't be bound")
		end
		-- every bind's default key is a bindable one and the action is the one InputController maps it to
		local input = fs.readFile("src/client/Controllers/InputController.luau")
		for _, b in S.binds do
			check(S.bindable[b.key] ~= nil, b.action .. "'s default is bindable")
			check(
				string.find(input, "[Enum.KeyCode." .. b.key .. '] = "' .. b.action .. '"', 1, true) ~= nil,
				b.action .. " is on " .. b.key .. " today"
			)
		end
		check(#S.keys <= 64, "the Settings.Set key number fits the remote")
		-- the save: defaults, a valid rebind, a refused one, and the binds in force
		local s = SettingsRules.defaults(Config)
		local function idx(id: string): number
			for i, k in S.keys do
				if k.id == id then
					return i
				end
			end
			return -1
		end
		check(SettingsRules.binds(Config, s).Leap == "Space", "Leap is Space by default")
		check(SettingsRules.set(Config, s, idx("bind_Leap"), S.bindable.E), "Leap to E is saved")
		check(SettingsRules.binds(Config, s).Leap == "E", "Leap is on E")
		check(not SettingsRules.set(Config, s, idx("bind_Fly"), 27), "Escape (27) is refused")
		check(not SettingsRules.set(Config, s, idx("bind_Fly"), 98.5), "a non-key number is refused")
		local cleaned = SettingsRules.clean(Config, { bind_Boost = 999, bind_Down = S.bindable.Q })
		check(cleaned.bind_Boost == 0 and cleaned.bind_Down == S.bindable.Q, "an old save cleans")
		local remotes = fs.readFile("src/shared/Remotes.luau")
		check(
			string.find(remotes, 'SettingsSet = { dir = "C2S", schema = { n(1, 64)', 1, true) ~= nil,
			"64 keys"
		)
		local menu = fs.readFile("src/client/Ui/SettingsMenu.luau")
		check(string.find(menu, "keyRows()", 1, true) ~= nil, "the KEYS rows draw")
		local sc = fs.readFile("src/client/Controllers/SettingsClient.luau")
		check(
			string.find(
				sc,
				"InputController.applyBinds(SettingsRules.binds(Config, SettingsClient.values))",
				1,
				true
			) ~= nil,
			"applied"
		)
	end)

	test("List combat: INVITE FRIENDS opens Roblox's invite prompt", function()
		local src = fs.readFile("src/client/Ui/InviteHud.luau")
		check(
			string.find(src, "SocialService:CanSendGameInviteAsync(player)", 1, true) ~= nil,
			"asks Roblox first"
		)
		check(string.find(src, "SocialService:PromptGameInvite(player)", 1, true) ~= nil, "the prompt")
		check(string.find(src, 'Kit.dock(open, "Invite", 12)', 1, true) ~= nil, "in the MENU drawer")
		local init = fs.readFile("src/client/init.client.luau")
		check(string.find(init, "InviteHud.init()", 1, true) ~= nil, "InviteHud runs")
		if T.placePath then
			local roblox = require("@lune/roblox")
			local UiSim = require("./uisim")
			local sim = UiSim.new(
				UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
				{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
			)
			sim:run("Hud", sim:require("Client.Ui.Hud").init)
			sim:run("InviteHud", sim:require("Client.Ui.InviteHud").init)
			check(sim.playerGui:FindFirstChild("InviteButton", true) ~= nil, "the button is made")
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, "; "))
		end
	end)

	test("List combat: weather, the same sky for everyone (rain, storms, fog banks)", function()
		local WeatherPlan = require("../src/shared/WeatherPlan")
		local W = Config.Weather
		check(W ~= nil and W.on, "Config.Weather is on")
		local counts = {}
		for _, name in W.order do
			check(W.kinds[name] ~= nil and W.kinds[name].weight > 0, name .. " has a weight")
			counts[name] = 0
		end
		local N = 3000
		local fails, follows, storms = 0, 0, 0
		for s = 1, N do
			local prev, cur = WeatherPlan.run(W, s)
			counts[cur] += 1
			if cur == prev and cur ~= "clear" then
				fails += 1
			end
			if cur == "storm" then
				storms += 1
				if prev ~= "rain" then
					fails += 1
				end
			end
			local _, before = WeatherPlan.run(W, s - 1)
			if before == prev then
				follows += 1
			end
		end
		check(fails == 0, "no weather twice in a row and a storm always follows rain: " .. fails)
		check(follows >= N * 0.97, "a slot's 'before' is the slot before it: " .. follows .. "/" .. N)
		check(counts.clear >= N * 0.3, "clear most of the time: " .. counts.clear)
		check(
			counts.rain > 0 and storms > 0 and counts.fog > 0 and counts.overcast > 0,
			"every kind comes up"
		)
		-- the blend: none at a slot's start, all of it after the fade
		local _, _, k0 = WeatherPlan.at(W, 10 * W.slot)
		local _, _, k1 = WeatherPlan.at(W, 10 * W.slot + W.fade + 1)
		check(k0 == 0 and k1 == 1, "the fade runs over the slot's first seconds")
		local b = {
			air = {
				Density = 0.3,
				Offset = 0.15,
				Haze = 1.2,
				Glare = 0.2,
				Color = { 235, 199, 168 },
				Decay = { 140, 128, 179 },
			},
			clouds = { cover = 0.55, density = 0.6 },
		}
		local clear = WeatherPlan.mix(W, "clear", "clear", 1, b)
		check(clear.air.Density == 0.3 and clear.air.Color[1] == 235, "clear keeps the place's own sky")
		check(
			clear.rain == 0 and not clear.lightning and clear.grade.brightness == 0,
			"clear: no rain, no grade"
		)
		local rain = WeatherPlan.mix(W, "clear", "rain", 1, b)
		check(
			rain.rain == 1 and rain.air.Density > 0.3 and rain.clouds.cover > 0.55,
			"rain: drops, haze, clouds"
		)
		local half = WeatherPlan.mix(W, "clear", "rain", 0.5, b)
		check(half.rain == 0.5, "half way in, half the rain")
		check(WeatherPlan.mix(W, "rain", "storm", 1, b).lightning, "a storm has lightning")
		-- lightning: flashes inside their window with the thunder after them, the same numbers every time
		local flashes = 0
		for w = 1, 200 do
			local at, thunder = WeatherPlan.strike(W, w)
			if at then
				flashes += 1
				check(at >= w * W.lightning.gap and thunder < (w + 1) * W.lightning.gap, "inside its window")
				check(thunder - at >= W.lightning.thunder[1] - 1e-6, "the thunder comes after the flash")
				check(WeatherPlan.flash(W, at + 0.01) > 0.9, "the flash is bright at once")
				check(WeatherPlan.flash(W, at + W.lightning.flash + 0.01) == 0, "and gone after")
				local pts = WeatherPlan.bolt(W, w, 650, 470)
				local top, bottom = pts[1], pts[#pts]
				check(top[2] == 470 and bottom[2] == 0, "the bolt runs from the clouds to the ground")
				check(math.abs(math.sqrt(top[1] ^ 2 + top[3] ^ 2) - 650) < 1, "650 studs away")
			end
			local again = WeatherPlan.strike(W, w)
			check(again == at, "seeded: every device sees the same flash")
		end
		check(flashes > 100 and flashes < 180, "about 7 in 10 windows flash: " .. flashes)
		check(W.rain.texture > 0 and W.rain.splash > 0, "rain and splash textures uploaded")
		check(
			fs.isFile("art/export/fx/rain.png") and fs.isFile("art/export/fx/splash.png"),
			"the drawn textures"
		)
		local init = fs.readFile("src/client/init.client.luau")
		check(string.find(init, "WeatherFx.init()", 1, true) ~= nil, "WeatherFx runs")
		local fx = fs.readFile("src/client/Fx/WeatherFx.luau")
		check(string.find(fx, 'FrameProf.wrap("WeatherFx"', 1, true) ~= nil, "FrameProf on the loop")
		check(
			string.find(fx, "if under then", 1, true) ~= nil,
			"leaves the Atmosphere to DeepClient underwater"
		)
		if T.placePath then
			local roblox = require("@lune/roblox")
			local UiSim = require("./uisim")
			local sim = UiSim.new(UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))), {
				name = "Phone",
				w = 844,
				h = 390,
				top = 0,
				left = 44,
				right = 44,
				bottom = 21,
				touch = true,
			})
			local ws = sim.service("Workspace")
			local lighting = sim.service("Lighting")
			local d0 = lighting:FindFirstChildOfClass("Atmosphere").Density
			sim:run("WeatherFx", sim:require("Client.Fx.WeatherFx").init)
			local function frames(n: number)
				for _ = 1, n do
					sim:run("frame", function()
						sim.service("RunService").Heartbeat:Fire(0.12)
					end)
					sim:advance(0.12)
				end
			end
			ws:SetAttribute("WeatherForce", "storm")
			frames(30)
			local cam = ws.CurrentCamera
			local rainPart = cam:FindFirstChild("WeatherRain")
			local drops = rainPart and rainPart:FindFirstChild("Rain")
			check(drops ~= nil and drops.Rate > 0, "storm: rain falls on the camera's box")
			check(
				string.find(tostring(drops and drops.Texture), "rbxassetid://", 1, true) ~= nil,
				"textured drops"
			)
			local grade = lighting:FindFirstChild("WeatherGrade")
			check(grade ~= nil and grade.Saturation < -0.1, "storm: the picture greys")
			local air = lighting:FindFirstChildOfClass("Atmosphere")
			check(air ~= nil and air.Density > d0 + 0.05, "storm: the sky thickens")
			ws:SetAttribute("WeatherForce", "clear")
			frames(60)
			check(drops.Rate == 0, "clear: the rain stops")
			check(math.abs(air.Density - d0) < 0.02, "clear: the place's own sky comes back")
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, "; "))
		end
	end)

	test("List combat: set pieces move (train, music box, chandelier, Pit fans, the crane cat)", function()
		local M = Config.Fx.setMotion
		local art = Config.SetPieceArt
		local function has(name: string): boolean
			for _, look in art do
				if type(look) == "table" and type(look[name]) == "table" then
					return true
				end
			end
			return false
		end
		for name in M.meshes do
			check(has(name), name .. " is a real set piece mesh")
		end
		local site = fs.readFile("src/server/Services/SiteKit.luau")
		check(
			string.find(site, 'SiteKit.model(if cat then "Cat"', 1, true) ~= nil,
			"the cat model is named Cat"
		)
		for _, size in
			{
				"Vector3.new(1.4, 1, 2.2)",
				"Vector3.new(1.1, 1, 1)",
				"Vector3.new(0.3, 0.5, 0.2)",
				"Vector3.new(0.25, 0.25, 1.6)",
			}
		do
			check(string.find(site, size, 1, true) ~= nil, "the cat's pieces keep their sizes: " .. size)
		end
		local init = fs.readFile("src/client/init.client.luau")
		check(string.find(init, "SetMotion.init()", 1, true) ~= nil, "SetMotion runs")
		local fx = fs.readFile("src/client/Fx/SetMotion.luau")
		check(string.find(fx, 'FrameProf.wrap("SetMotion"', 1, true) ~= nil, "FrameProf on the loop")
		if T.placePath then
			local roblox = require("@lune/roblox")
			local UiSim = require("./uisim")
			local sim = UiSim.new(
				UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
				{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
			)
			local SetMotion = sim:require("Client.Fx.SetMotion")
			sim:run("SetMotion", SetMotion.init)
			local CF, V3 = roblox.CFrame, roblox.Vector3
			local base = CF.new(10, 20, 30)
			-- the train turns in place
			local spun = SetMotion.pose(M.meshes.TrainCars, base, 2, 0, 0)
			check((spun.Position - base.Position).Magnitude < 1e-6, "the train ring turns about its centre")
			check(
				math.abs(spun.LookVector:Dot(base.LookVector) - math.cos(0.9)) < 1e-4,
				"0.45 radians a second"
			)
			-- the chandelier swings about its hook, a little
			local ch = M.meshes.ChandelierFrame
			local hinge = ch.hinge - 3.7
			local hook = base.Position + V3.new(0, hinge, 0)
			local most = 0
			for i = 0, 40 do
				local cf = SetMotion.pose(ch, base, i * 0.1, 0.3, hinge)
				local h = cf:PointToWorldSpace(base:PointToObjectSpace(hook))
				check((h - hook).Magnitude < 1e-4, "the hook stays put")
				most = math.max(most, (cf.Position - base.Position).Magnitude)
			end
			check(most > 0.03 and most < 0.25, "a gentle sway, not a swing: " .. most)
			-- fans hop up from where they stand, never through the bench
			for i = 0, 20 do
				local cf = SetMotion.pose(M.meshes.FanShirt, base, i * 0.07, 0.2, 0)
				check(
					cf.Position.Y >= base.Position.Y - 1e-6 and cf.Position.Y <= base.Position.Y + 0.46,
					"a hop"
				)
			end
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, "; "))
		end
	end)

	test("List combat: power summons, rides and forms in their Blender looks (Art.Powers)", function()
		local roblox = require("@lune/roblox")
		local art = Config.PowerArt
		check(art ~= nil, "Config.PowerArt (generated by art/blender/powers.py)")
		check(
			string.find(fs.readFile("src/shared/MeshFix.luau"), '"Powers", --', 1, true) ~= nil,
			"MeshFix turns the set (measured rotY180 in meshturns.json)"
		)
		local model = roblox.deserializeModel(fs.readFile("art/models/Powers.rbxm"))[1]
		local n = 0
		for look, meshes in art do
			for name, m in meshes do
				n += 1
				local mp = model:FindFirstChild(name, true)
				check(mp ~= nil and mp:IsA("MeshPart"), look .. "." .. name .. " is imported")
				check(mp ~= nil and string.match(mp.MeshId, "%d+$") ~= nil, name .. " has a mesh id")
				check(m.tris < 5000, name .. " stays light")
			end
		end
		check(
			n == 46,
			"46 meshes in 16 looks (Everything Left 382 added the jets, the rail and the slab): " .. n
		)
		for _, look in
			{
				"Turret",
				"Drone",
				"Totem",
				"Mine",
				"Guardian",
				"SpiritBeast",
				"Hoverboard",
				"RockSlab",
				"FlameJets",
				"LightRail",
				"PsiSlab",
			}
		do
			check(art[look] ~= nil, look .. " look")
		end
		local fx = fs.readFile("src/client/Fx/CombatFx.luau")
		for _, needle in
			{
				'PowerMeshes.ready("StonePillar")',
				'PowerMeshes.ready("ThornVine")',
				'PowerMeshes.ready("Wave")',
				"RIDE[set] ~= nil and PowerMeshes.ready(RIDE[set])",
				"look and PowerMeshes.ready(look)",
			}
		do
			check(string.find(fx, needle, 1, true) ~= nil, "CombatFx draws it: " .. needle)
		end
		check(
			string.find(fs.readFile("src/client/Fx/BuildingFx.luau"), 'PowerMeshes.ready("Drone")', 1, true)
				~= nil,
			"repair drones wear the drone"
		)
		if T.placePath then
			local UiSim = require("./uisim")
			local sim = UiSim.new(
				UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
				{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
			)
			local PowerMeshes = sim:require("Client.Fx.PowerMeshes")
			for look in art do
				check(PowerMeshes.ready(look), look .. " is ready in the built place")
			end
			local CombatFx = sim:require("Client.Fx.CombatFx")
			sim:run("CombatFx", CombatFx.init)
			local ws = sim.service("Workspace")
			local at = roblox.Vector3.new(0, 10, 0)
			local color = roblox.Color3.fromRGB(200, 80, 255)
			sim:run("summons", function()
				for _, kind in { "turret", "drone", "totem", "guardian", "mines" } do
					CombatFx.summon(kind, function()
						return at
					end, 3, "Comic", color, 10)
				end
				for _, set in { "Earth", "Gadgeteer", "Spirit", "Fire", "Light", "Mind", "Tide" } do
					CombatFx.ride(set, function()
						return at
					end, 3, "Comic", color)
				end
			end)
			local fxFolder = ws:FindFirstChild("Fx")
			local names = {}
			for _, d in fxFolder:GetDescendants() do
				if d:IsA("MeshPart") then
					names[d.Name] = (names[d.Name] or 0) + 1
				end
			end
			for _, name in
				{
					"TurretHead",
					"DroneBody",
					"TotemPole",
					"GuardianForm",
					"RockBody",
					"BoardDeck",
					"BeastForm",
					"JetNozzles",
					"JetThroats",
					"RailSpine",
					"RailTies",
					"SlabAsphalt",
					"SlabRock",
					"WaveWater",
				}
			do
				check(names[name] ~= nil, name .. " drawn as a mesh")
			end
			check(names.MineShell == 6, "six mines")
			check(names.GuardianForm == 1 and names.TurretLight == 1, "one each")
			-- the tint: the turret's light is the caster's colour, its head keeps steel
			for _, d in fxFolder:GetDescendants() do
				if d.Name == "TurretLight" then
					check(d.Color == color, "tinted to the path")
				elseif d.Name == "TurretHead" then
					check(d.Color ~= color, "the head keeps its own colour")
				end
			end
			-- the Mech Suit's shell on a body
			local FormFx = sim:require("Client.Fx.FormFx")
			local char = UiSim.newInstance("Model")
			for _, pn in { "UpperTorso", "LeftLowerArm", "RightLowerArm", "LeftLowerLeg", "RightLowerLeg" } do
				local bp = UiSim.newInstance("Part")
				bp.Name = pn
				bp.Size = if pn == "UpperTorso"
					then roblox.Vector3.new(2, 1.6, 1)
					else roblox.Vector3.new(1, 1.2, 1)
				bp.Parent = char
			end
			local shell
			sim:run("mech", function()
				shell = FormFx.mech(char, color)
			end)
			check(
				shell ~= nil and #shell == 6,
				"chest, core, two sleeves, two greaves: " .. tostring(shell and #shell)
			)
			-- Bolt Ride's own streak (Everything Left 167): a zigzag bolt with forks and a scorch over the slice's
			-- streak, only for Volt
			local function fxCount()
				local n = 0
				for _, d in fxFolder:GetDescendants() do
					if d:IsA("BasePart") then
						n += 1
					end
				end
				return n
			end
			local n0 = fxCount()
			sim:run("bolt ride", function()
				CombatFx.dash(at, at + roblox.Vector3.new(0, 0, -30), "Comic", color, "Volt")
			end)
			local volt = fxCount() - n0
			n0 = fxCount()
			sim:run("shadow dash", function()
				CombatFx.dash(at, at + roblox.Vector3.new(0, 0, -30), "Comic", color, "Gunslinger")
			end)
			local other = fxCount() - n0
			check(
				volt >= other + 20,
				"Bolt Ride draws its bolt, forks and scorch: " .. volt .. " vs " .. other
			)
			-- Flame Jets and Light Rail: particles, not a new part every other frame
			for _, set in { "Fire", "Light" } do
				local rideAt = at + roblox.Vector3.new(0, 0, 0)
				n0 = fxCount()
				sim:run("ride " .. set, function()
					CombatFx.ride(set, function()
						rideAt += roblox.Vector3.new(0, 0, -0.5)
						return rideAt
					end, 5, "Comic", color)
				end)
				local made = fxCount() - n0
				for _ = 1, 60 do
					sim:run("frame", function()
						sim.service("RunService").RenderStepped:Fire(1 / 60)
					end)
				end
				check(
					fxCount() - n0 <= made,
					set .. " ride adds no parts each frame: " .. (fxCount() - n0) .. " > " .. made
				)
			end
			-- the nemesis armour (Everything Left 218): every trait piece in its Blender mesh, in the part's box
			local NemesisFx = sim:require("Client.Fx.NemesisFx")
			sim:run("NemesisFx", NemesisFx.init)
			local remotes = sim.service("ReplicatedStorage"):WaitForChild("Remotes")
			sim:run("nemesis", function()
				remotes:WaitForChild("NemesisState").OnClientEvent:Fire({
					k = "spawn",
					id = 77,
					name = "Gravemaw",
					rank = 2,
					colors = 1,
					build = "bulky",
					head = "horned",
					cape = true,
					traits = 0xFF,
				})
			end)
			local nem = {}
			for _, d in ws:FindFirstChild("NemesisFx"):GetChildren() do
				if d:IsA("MeshPart") then
					nem[d.Name] = (nem[d.Name] or 0) + 1
				end
			end
			for _, name in
				{ "NemShoulders", "NemCape", "NemPlates", "NemCannon", "NemAntenna", "NemAntennaTip" }
			do
				check(nem[name] == 1, name .. " drawn as a mesh: " .. tostring(nem[name]))
			end
			check(nem.NemHorn == 2, "two horns")
			for _, d in ws:FindFirstChild("NemesisFx"):GetChildren() do
				if d.Name == "NemShoulders" then
					check(math.abs(d.Size.X - 6.5) < 1e-3, "the bulky build widens the shoulders")
				end
			end
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, "; "))
		end
	end)

	test("List combat: rubble heaps in Blender meshes (Art.Rubble)", function()
		local roblox = require("@lune/roblox")
		local art = Config.RubbleArt
		local model = roblox.deserializeModel(fs.readFile("art/models/Rubble.rbxm"))[1]
		for k = 1, 4 do
			local heap = art["Rubble" .. k]
			check(heap ~= nil and heap.box ~= nil, "heap " .. k)
			for _, name in { "Rubble" .. k, "Rubble" .. k .. "Rebar" } do
				local mp = model:FindFirstChild(name, true)
				check(mp ~= nil and mp:IsA("MeshPart"), name .. " imported")
				check(heap[name] ~= nil, name .. " in the fit table")
			end
			-- the heap's main mesh fills the box it is drawn for, so stretched it fills Chunker's box exactly
			local main = heap["Rubble" .. k]
			for i = 1, 3 do
				check(math.abs(main.size[i] - heap.box[i]) < 1e-3, "the heap fills its box")
				check(math.abs(main.offset[i]) < 1e-3, "centred on it")
			end
		end
		local fx = fs.readFile("src/client/Fx/BuildingFx.luau")
		check(string.find(fx, "local heaps = rubbleReady()", 1, true) ~= nil, "BuildingFx draws the heaps")
		check(string.find(fx, "* MeshFix.of(p)", 1, true) ~= nil, "with the import turn")
		check(
			string.find(fs.readFile("src/shared/MeshFix.luau"), '"Rubble", --', 1, true) ~= nil,
			"MeshFix turns it"
		)
		check(
			string.find(fs.readFile("default.project.json"), "art/models/Rubble.rbxm", 1, true) ~= nil,
			"in the place"
		)
	end)

	test("List combat: every weapon's 2nd and 3rd style changes its shape (Everything Left 193)", function()
		local WeaponMesh = require("../src/shared/WeaponMesh")
		local roblox = require("@lune/roblox")
		local model = roblox.deserializeModel(fs.readFile("art/models/Weapons.rbxm"))[1]
		for _, w in Config.Weapons.list do
			local id = w[1]
			local classic = WeaponMesh.pieces(Config, id, 1)
			for st = 2, 3 do
				local diff = 0
				for i, p in WeaponMesh.pieces(Config, id, st) do
					if p.mesh ~= classic[i].mesh then
						diff += 1
						check(model:FindFirstChild(p.mesh, true) ~= nil, p.mesh .. " is imported")
					end
				end
				check(diff > 0, w[3] .. ": style " .. st .. " has its own mesh")
			end
		end
		check(
			#WeaponMesh.check(Config) == 0,
			"the fit table is sound: " .. table.concat(WeaponMesh.check(Config), "; ")
		)
	end)

	test("List combat: robot gear and foe props in Blender meshes (Everything Left 223, 229)", function()
		local roblox = require("@lune/roblox")
		local art = Config.FoeArt
		check(art ~= nil, "Config.FoeArt (generated by art/blender/foes.py)")
		local model = roblox.deserializeModel(fs.readFile("art/models/Foes.rbxm"))[1]
		local n = 0
		for name, m in art do
			n += 1
			local mp = model:FindFirstChild(name, true)
			check(
				mp ~= nil and mp:IsA("MeshPart") and string.match(mp.MeshId, "%d+$") ~= nil,
				name .. " is imported"
			)
			check(m.tris < 1500, name .. " stays light")
		end
		check(n == 28, "28 meshes: " .. n)
		check(
			string.find(fs.readFile("src/shared/MeshFix.luau"), '"Foes", --', 1, true) ~= nil,
			"MeshFix turns the set"
		)
		if not T.placePath then
			return
		end
		-- the real renderer dresses a robot of each geared kind with the meshes, in their parts' boxes
		local UiSim = require("./uisim")
		local sim = UiSim.new(
			UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		)
		local ER = sim:require("Client.Controllers.EnemyRenderer")
		local ws = sim.service("Workspace")
		local want = {
			riot = { "Riot" },
			cap = { "Cap", "CapPeak" },
			rifle = { "Rifle", "Scope" },
			bandolier = { "Strap", "Grenade1", "Satchel" },
			medpack = { "Medpack" },
			wings = { "WingL", "WingR" },
			hookArm = { "Launcher", "Claw", "ClawA" },
		}
		local seen = {}
		for kind, cfg in Config.Enemies do
			if type(cfg) ~= "table" or not cfg.body then
				continue
			end
			for flag, names in want do
				if cfg.body[flag] and not seen[flag] then
					seen[flag] = true
					local m
					sim:run("figure " .. kind, function()
						m = ER.figure(kind, 1, ws)
					end)
					for _, pn in names do
						local p = m and m:FindFirstChild(pn, true)
						check(p ~= nil and p:IsA("MeshPart"), kind .. ": " .. pn .. " is a mesh")
					end
				end
			end
		end
		for flag in want do
			check(seen[flag] == true, "a kind wears " .. flag)
		end
		check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, "; "))
	end)

	test("List combat: collection finds are Blender figures (Everything Left 335)", function()
		local roblox = require("@lune/roblox")
		local art = Config.FindArt
		check(art ~= nil, "Config.FindArt (generated by art/blender/finds.py)")
		local model = roblox.deserializeModel(fs.readFile("art/models/Finds.rbxm"))[1]
		local world = {}
		for _, set in Config.Collect.sets do
			if set.kind == "hidden" or set.kind == "weekly" then
				world[set.id] = set
				check(art[set.id] ~= nil, set.id .. " has its figure")
			end
		end
		for id, rows in art do
			check(world[id] ~= nil, id .. " is a set found in the world")
			for name, row in rows do
				local mp = model:FindFirstChild(name, true)
				check(mp ~= nil and mp:IsA("MeshPart"), name .. " is imported")
				check(row.size[2] <= 2.2 and row.tris < 1500, name .. " is small and light")
			end
		end
		check(
			string.find(fs.readFile("src/shared/MeshFix.luau"), '"Finds", --', 1, true) ~= nil,
			"MeshFix turns the set"
		)
		if not T.placePath then
			return
		end
		-- the real client draws a find near you as its set's figure that bobs and turns
		local UiSim = require("./uisim")
		local sim = UiSim.new(
			UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		)
		local char = UiSim.newInstance("Model")
		local root = UiSim.newInstance("Part")
		root.Name = "HumanoidRootPart"
		root.Parent = char
		char.Parent = sim.workspace
		sim.player.Character = char
		local CC = sim:require("Client.Controllers.CollectClient")
		sim:run("CollectClient", CC.init)
		local remotes = sim.service("ReplicatedStorage"):WaitForChild("Remotes")
		local bell = world.ShipBells.at
		sim:run("state", function()
			remotes
				:WaitForChild("CollectState").OnClientEvent
				:Fire({ spots = { { bell, 4, 3, 2 } }, found = {} })
		end)
		sim:run("look round", CC.step)
		local folder = sim.workspace:FindFirstChild("CollectFinds")
		local glow = folder and folder:FindFirstChild("Find" .. bell)
		local mesh = glow and glow:FindFirstChild("Find_Bell")
		check(mesh ~= nil and mesh:IsA("MeshPart"), "the bell find is the bell mesh")
		local n = 0
		for _, c in (glow and glow:GetChildren() or {}) do
			if c:IsA("MeshPart") then
				n += 1
			end
		end
		local want = 0
		for _ in art.ShipBells do
			want += 1
		end
		check(n == want, "every piece of the bell: " .. n)
		if mesh then
			local before = mesh.CFrame
			local t0, spins = os.clock(), 0
			repeat
				spins += 1
			until os.clock() - t0 > 0.05
			sim:run("frame", function()
				sim.service("RunService").RenderStepped:Fire(1 / 60)
			end)
			check((mesh.CFrame.Position - roblox.Vector3.new(4, 3, 2)).Magnitude < 3, "it stays at its spot")
			check(mesh.CFrame ~= before, "it bobs and turns")
		end
		check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, "; "))
	end)

	test("List combat: the contest stage in Blender meshes (Everything Left 337)", function()
		local roblox = require("@lune/roblox")
		local art = Config.StageArt
		check(art ~= nil, "Config.StageArt (generated by art/blender/contest.py)")
		local model = roblox.deserializeModel(fs.readFile("art/models/Stage.rbxm"))[1]
		local n = 0
		for name, row in art do
			n += 1
			local mp = model:FindFirstChild(name, true)
			check(mp ~= nil and mp:IsA("MeshPart"), name .. " is imported")
			check(row.tris < 2500, name .. " stays light")
		end
		check(n == 11, "11 meshes: " .. n)
		-- the deck mesh fills the collider's box (Config.Contest.stage) and sits under the deck's top
		local st = Config.Contest.stage
		local deck = art.StageDeck
		check(
			math.abs(deck.size[1] - st.size) < 0.3
				and math.abs(deck.size[2] - st.height) < 0.05
				and math.abs(deck.offset[2] + st.height / 2) < 0.05,
			"the deck mesh is the stage's box"
		)
		check(art.StageArch.offset[3] > st.size / 2 - 3, "the arch stands over the podium at the back")
		check(art.SpotCone.alpha > 0.5, "the beam is see-through")
		local src = fs.readFile("src/server/Services/ContestService.luau")
		check(
			string.find(src, "dress(meshes", 1, true) ~= nil,
			"the server dresses the stage when the meshes are in"
		)
		check(
			string.find(src, '"COSTUME CONTEST"', 1, true) ~= nil,
			"the marquee is lettered with fixed text"
		)
		if not T.placePath then
			return
		end
		-- the real client draws the spotlight's beam from a can to the contestant in the show
		local UiSim = require("./uisim")
		local sim = UiSim.new(
			UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		)
		local char = UiSim.newInstance("Model")
		local head = UiSim.newInstance("Part")
		head.Name = "Head"
		head.CFrame = roblox.CFrame.new(100, 9, 52)
		head.Parent = char
		char.Parent = sim.workspace
		sim.player.Character = char
		local Hud = sim:require("Client.Ui.ContestHud")
		sim:run("ContestHud", Hud.init)
		local remotes = sim.service("ReplicatedStorage"):WaitForChild("Remotes")
		sim:run("show", function()
			remotes:WaitForChild("ContestState").OnClientEvent:Fire({
				phase = "show",
				theme = "Heroes",
				entries = { { id = sim.player.UserId, name = "Tester" } },
				spot = sim.player.UserId,
				endsAt = os.time() + 10,
				now = os.time(),
				stage = { 100, 2, 50 },
				top = {},
				max = 8,
			})
		end)
		local beam
		for _, c in sim.workspace:GetChildren() do
			if c.Name == "SpotCone" then
				beam = c
			end
		end
		check(beam ~= nil and beam:IsA("MeshPart"), "the spotlight's beam is drawn")
		if beam then
			check(beam.Size.Y > 10, "it reaches from the arch to the contestant")
			check(beam.Transparency > 0.5, "see-through")
		end
		check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, "; "))
	end)

	test(
		"List combat: the giver's mark, the relay giver and the cat in Blender meshes (Everything Left 399, 401, 402)",
		function()
			local roblox = require("@lune/roblox")
			local art = Config.SitePropArt
			check(art ~= nil, "Config.SitePropArt (generated by art/blender/siteprops.py)")
			local model = roblox.deserializeModel(fs.readFile("art/models/SiteProps.rbxm"))[1]
			-- each mesh fills the box of the part it dresses (the game stretches it to the part: the shape must match)
			local boxes = {
				QuestMark = { 0.8, 1.6, 0.8 },
				RelayPost = { 0.5, 4, 0.5 },
				RelayBox = { 2.2, 1.6, 1.4 },
				RelayAerial = { 0.12, 2.6, 0.12 },
				CatBody = { 1.4, 1, 2.2 },
				CatHead = { 1.1, 1, 1 },
				CatEar = { 0.3, 0.5, 0.2 },
				CatTail = { 0.25, 0.25, 1.6 },
			}
			local n = 0
			for name, row in art do
				n += 1
				local mp = model:FindFirstChild(name, true)
				check(mp ~= nil and mp:IsA("MeshPart"), name .. " is imported")
				local b = boxes[name]
				check(b ~= nil, name .. " dresses a known part")
				if b then
					for k = 1, 3 do
						check(
							math.abs(row.size[k] - b[k]) <= b[k] * 0.16 + 0.02,
							name .. " fills its part's box on axis " .. k
						)
					end
				end
			end
			check(n == 8, "8 meshes: " .. n)
			local kit = fs.readFile("src/server/Services/SiteKit.luau")
			local sq = fs.readFile("src/server/Services/SideQuestService.luau")
			for _, name in { "CatBody", "CatHead", "CatEar", "CatTail" } do
				check(string.find(kit, '"' .. name .. '"', 1, true) ~= nil, "the cat wears " .. name)
			end
			for _, name in { "RelayPost", "RelayBox", "RelayAerial" } do
				check(string.find(sq, '"' .. name .. '"', 1, true) ~= nil, "the relay wears " .. name)
			end
			local _, marks = string.gsub(sq, 'SiteKit.skin%(mark, "QuestMark"%)', "")
			check(marks == 2, "both givers' marks wear the ! mesh: " .. marks)
			check(string.find(kit, "p.Transparency = 1", 1, true) ~= nil, "the dressed part goes invisible")
			check(
				string.find(fs.readFile("src/shared/MeshFix.luau"), '"SiteProps", --', 1, true) ~= nil,
				"MeshFix turns the set"
			)
		end
	)

	test(
		"List combat: client errors and crash-free sessions reach analytics (Everything Left 480)",
		function()
			local AS = require("../src/shared/AnalyticsSchema")
			check(
				AS.EVENTS.client_error ~= nil and AS.EVENTS.session_errors ~= nil,
				"the two events are in the schema"
			)
			check(AS.NOSAVE.client_error and AS.NOSAVE.session_errors, "logged even when a save did not load")
			local h = AS.nameHash("CombatClient")
			check(
				h >= 1 and h <= 999 and h == AS.nameHash("CombatClient"),
				"a script's name as a steady number"
			)
			check(
				Config.Analytics.devicePace[6] ~= nil and Config.Analytics.errorEvery >= 30,
				"paced to once a minute"
			)
			local srv = fs.readFile("src/server/Services/Analytics.luau")
			check(string.find(srv, '"client_error",', 1, true) ~= nil, "the server logs client_error")
			check(string.find(srv, '"session_errors",', 1, true) ~= nil, "and session_errors on leaving")
			if not T.placePath then
				return
			end
			-- the real Telemetry: script errors on the device go up counted, the first script named, once a minute
			local roblox = require("@lune/roblox")
			local UiSim = require("./uisim")
			local sim = UiSim.new(
				UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
				{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
			)
			local sent = {}
			sim:run("hook", function()
				local r = sim.service("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("Telemetry")
				r._props.FireServer = function(_, ...)
					table.insert(sent, { ... })
				end
			end)
			local Tel = sim:require("Client.Controllers.Telemetry")
			sim:run("Telemetry", Tel.init)
			local origin = UiSim.newInstance("ModuleScript")
			origin.Name = "CombatClient"
			sim:run("errors", function()
				local sc = sim.service("ScriptContext")
				sc.Error:Fire("oops", "trace", origin)
				sc.Error:Fire("oops again", "trace", origin)
			end)
			local errs = {}
			for _, row in sent do
				if row[1] == 6 then
					table.insert(errs, row)
				end
			end
			check(#errs == 1, "the first error goes up at once, the second waits a minute: " .. #errs)
			if errs[1] then
				check(errs[1][2] == 1 and errs[1][3] == h, "one error, from CombatClient")
			end
			check(Tel.errors == 1, "the second is held for the next report")
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, "; "))
		end
	)

	test("List combat: player data erasure and save rollback (Everything Left 464, 465)", function()
		local Plan = require("../src/shared/SaveAdminPlan")
		local BoardKeys = require("../src/shared/BoardKeys")
		local D = Config.Data
		local now = BoardKeys.weekStart(D.admin.firstWeek + 3) + 3600
		local targets, prefixes = Plan.erase(Config, 12345, now)
		check(
			targets[1].store == D.storeName and targets[1].key == D.keyPrefix .. "12345",
			"the profile key first"
		)
		local weeks = {}
		local boards = 0
		for _, t in targets do
			if t.ordered then
				boards += 1
				weeks[t.store] = true
				check(t.key == "12345" and t.scope ~= nil, "a board row by the user id in its board's scope")
			end
		end
		local nWeeks = 0
		for _ in weeks do
			nWeeks += 1
		end
		check(
			nWeeks == 5 and boards == 5 * #Config.Boards.boards,
			"every board, first week to next week: " .. boards
		)
		check(
			#prefixes == #D.admin.reviewKinds and prefixes[1].prefix == "kicks_12345_",
			"the review rows by kind"
		)
		-- every review kind GuardService writes is covered
		for kind in
			string.gmatch(
				fs.readFile("src/server/Services/GuardService.luau")
					.. fs.readFile("src/server/Services/DeathService.luau"),
				'GuardService%.review%([^,]+, "(%a+)"'
			)
		do
			check(table.find(D.admin.reviewKinds, kind) ~= nil, kind .. " rows are erased too")
		end
		-- a rollback takes the newest version before the time, never a deleted one
		local v = {
			{ version = "a", time = 100 },
			{ version = "b", time = 200 },
			{ version = "c", time = 300, deleted = true },
			{ version = "d", time = 400 },
		}
		check(
			Plan.pick(v, 350) == "b" and Plan.pick(v, 500) == "d" and Plan.pick(v, 50) == nil,
			"the version picked"
		)
		-- the server tools: kick and stop saving before erasing; refuse a rollback while anyone holds the profile;
		-- and nothing on the wire reaches them
		local sa = fs.readFile("src/server/Services/SaveAdmin.luau")
		check(
			string.find(sa, "DataService.stopSaving(player)", 1, true) ~= nil,
			"an online player's session stops saving"
		)
		check(string.find(sa, "locked = true", 1, true) ~= nil, "a held profile is left alone")
		for _, f in fs.readDir("src/server/Services") do
			if f ~= "SaveAdmin.luau" then
				check(
					not string.find(fs.readFile("src/server/Services/" .. f), "Parent.SaveAdmin", 1, true),
					f .. " does not call SaveAdmin"
				)
			end
		end
		check(
			string.find(fs.readFile("notes/Launch Checklist.md"), "Player data requests", 1, true) ~= nil,
			"the steps are written down for nate"
		)
	end)

	test(
		"List combat: the PvP flag rings and the Downed ring are Blender meshes (Everything Left 385)",
		function()
			local roblox = require("@lune/roblox")
			local art = Config.RingArt
			check(art ~= nil, "Config.RingArt (generated by art/blender/rings.py)")
			local model = roblox.deserializeModel(fs.readFile("art/models/Rings.rbxm"))[1]
			for _, name in { "RingRound", "RingSquare", "RingDowned" } do
				local mp = model:FindFirstChild(name, true)
				check(mp ~= nil and mp:IsA("MeshPart"), name .. " is imported")
				local row = art[name]
				check(
					row ~= nil and math.abs(row.size[1] - 1) < 0.02 and math.abs(row.size[3] - 1) < 0.02,
					name .. " is drawn 1 stud across"
				)
			end
			if not T.placePath then
				return
			end
			local UiSim = require("./uisim")
			local sim = UiSim.new(
				UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
				{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
			)
			local char = UiSim.newInstance("Model")
			local root = UiSim.newInstance("Part")
			root.Name = "HumanoidRootPart"
			root.CFrame = roblox.CFrame.new(10, 3, 10)
			root.Parent = char
			char.Parent = sim.workspace
			sim.player.Character = char
			local PvpFx = sim:require("Client.Fx.PvpFx")
			sim:run("PvpFx", PvpFx.init)
			local function frame()
				sim:run("frame", function()
					sim.service("RunService").RenderStepped:Fire(1 / 60)
				end)
			end
			local function ringNamed(name: string)
				local f = sim.workspace:FindFirstChild("PvpFx")
				return f and f:FindFirstChild(name)
			end
			-- a flagged Vigil hero stands in the round ring, a Syndicate one in the square; Downed adds the grey one
			sim.player:SetAttribute("Pvp", true)
			sim.player:SetAttribute("PvpSide", "hero")
			frame()
			local round = ringNamed("RingRound")
			check(round ~= nil and round:IsA("MeshPart"), "the Vigil's round ring mesh")
			if round then
				check(math.abs(round.Position.Y - 0.1) < 0.2, "it lies under the hero's feet")
			end
			sim.player:SetAttribute("PvpSide", "villain")
			frame()
			check(
				ringNamed("RingSquare") ~= nil and ringNamed("RingRound") == nil,
				"the Syndicate's square ring instead"
			)
			sim.player:SetAttribute("Downed", true)
			frame()
			check(ringNamed("RingDowned") ~= nil, "the Downed ring")
			sim.player:SetAttribute("Pvp", false)
			sim.player:SetAttribute("Downed", false)
			frame()
			check(ringNamed("RingSquare") == nil and ringNamed("RingDowned") == nil, "both go when they end")
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, "; "))
		end
	)

	test(
		"List combat: the block's shield, bubble, shards and flash are Blender meshes (Everything Left 384)",
		function()
			local roblox = require("@lune/roblox")
			local art = Config.GuardArt
			check(art ~= nil, "Config.GuardArt (generated by art/blender/guard.py)")
			local model = roblox.deserializeModel(fs.readFile("art/models/Guard.rbxm"))[1]
			for _, name in { "GuardFace", "GuardRim", "GuardCore", "GuardBubble", "GuardShard", "GuardFlash" } do
				local mp = model:FindFirstChild(name, true)
				check(mp ~= nil and mp:IsA("MeshPart"), name .. " is imported")
				check(art[name] ~= nil and art[name].tris < 3000, name .. " is light")
			end
			check(
				art.GuardFace.size[1] < 0.6 and math.abs(art.GuardFace.size[2] - 1) < 0.02,
				"the face is a domed disc"
			)
			local fx = fs.readFile("src/client/Fx/GuardFx.luau")
			check(not string.find(fx, "PLACEHOLDER ART", 1, true), "GuardFx is no longer placeholder art")
			if not T.placePath then
				return
			end
			local UiSim = require("./uisim")
			local sim = UiSim.new(
				UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
				{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
			)
			local char = UiSim.newInstance("Model")
			local root = UiSim.newInstance("Part")
			root.Name = "HumanoidRootPart"
			root.CFrame = roblox.CFrame.new(10, 3, 10)
			root.Parent = char
			char.Parent = sim.workspace
			sim.player.Character = char
			local GuardFx = sim:require("Client.Fx.GuardFx")
			sim:run("GuardFx", GuardFx.init)
			local function frame()
				sim:run("frame", function()
					sim.service("RunService").RenderStepped:Fire(1 / 60)
				end)
			end
			local folder = sim.workspace:FindFirstChild("GuardFx")
			local function count(name: string): number
				local n = 0
				for _, c in folder:GetChildren() do
					if c.Name == name and c:IsA("MeshPart") then
						n += 1
					end
				end
				return n
			end
			-- held block: the face, its rim and the core, in front of the chest
			sim.player:SetAttribute("Blocking", true)
			frame()
			check(
				count("GuardFace") == 1 and count("GuardRim") == 1 and count("GuardCore") == 1,
				"the held shield"
			)
			local face = folder:FindFirstChild("GuardFace")
			if face then
				check(
					math.abs(face.Size.X - 0.15 * Config.Guard.shield.size) < 0.01
						and face.Size.Y <= Config.Guard.shield.size * Config.Guard.shield.kick + 0.01,
					"sized from Config.Guard.shield (its size and its raise)"
				)
			end
			-- a robot blocks: its bubble; it drops the block: a few shards
			local remotes = sim.service("ReplicatedStorage"):WaitForChild("Remotes")
			sim:run("rup", function()
				remotes:WaitForChild("GuardEvent").OnClientEvent:Fire({
					{ k = "rup", a = 5, x = 40, y = 3, z = 40, f = true, s = 9, t = 2 },
				})
			end)
			frame()
			check(count("GuardBubble") == 1, "a robot's block is the geodesic bubble")
			sim:run("rdown", function()
				remotes
					:WaitForChild("GuardEvent").OnClientEvent
					:Fire({ { k = "rdown", a = 5, x = 40, y = 3, z = 40 } })
			end)
			check(count("GuardBubble") == 0 and count("GuardShard") >= 5, "it breaks into shards")
			-- a shatter: the starburst and eight shards; a perfect block: the starburst
			sim:run("shatter", function()
				remotes
					:WaitForChild("GuardEvent").OnClientEvent
					:Fire({ { k = "shatter", a = 0, x = 0, y = 3, z = 0 } })
				remotes
					:WaitForChild("GuardEvent").OnClientEvent
					:Fire({ { k = "perfect", a = 0, x = 6, y = 3, z = 0 } })
			end)
			check(
				count("GuardFlash") == 2 and count("GuardShard") >= 13,
				"the shatter's shards and the flashes"
			)
			sim.player:SetAttribute("Blocking", false)
			frame()
			check(count("GuardFace") == 0, "the shield goes when the block ends")
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, "; "))
		end
	)

	test(
		"List combat: the juice pieces are Blender meshes and drawn pictures (Everything Left 386)",
		function()
			local roblox = require("@lune/roblox")
			local art = Config.JuiceArt
			check(art ~= nil, "Config.JuiceArt (generated by art/blender/juice.py)")
			local model = roblox.deserializeModel(fs.readFile("art/models/Juice.rbxm"))[1]
			for _, name in { "JuiceCoin", "JuiceStar", "JuiceRing", "JuiceBeam", "JuiceBurst" } do
				local mp = model:FindFirstChild(name, true)
				check(mp ~= nil and mp:IsA("MeshPart"), name .. " is imported")
				check(art[name] ~= nil and art[name].tris < 2500, name .. " is light")
			end
			for key, file in { stamp = "Stamp", badge = "Badge", confetti = "Confetti" } do
				check(type(Config.Ui.juiceArt[key]) == "number", key .. " has its uploaded picture")
				check(
					fs.isFile("art/export/ui/juice/" .. file .. ".png"),
					file .. " is drawn by art/ui/juice_ui.py"
				)
			end
			check(
				not string.find(fs.readFile("src/client/Fx/JuiceFx.luau"), "PLACEHOLDER ART", 1, true),
				"JuiceFx is no longer placeholder art"
			)
			if not T.placePath then
				return
			end
			local UiSim = require("./uisim")
			local sim = UiSim.new(
				UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
				{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
			)
			local char = UiSim.newInstance("Model")
			local root = UiSim.newInstance("Part")
			root.Name = "HumanoidRootPart"
			root.Parent = char
			local head = UiSim.newInstance("Part")
			head.Name = "Head"
			head.Parent = char
			char.Parent = sim.workspace
			sim.player.Character = char
			local JuiceFx = sim:require("Client.Fx.JuiceFx")
			sim:run("JuiceFx", JuiceFx.init)
			local folder = sim.workspace:FindFirstChild("JuiceFx")
			local function count(name: string): number
				local n = 0
				for _, c in folder:GetDescendants() do
					if c.Name == name and c:IsA("MeshPart") then
						n += 1
					end
				end
				return n
			end
			local at = roblox.Vector3.new(5, 3, 5)
			sim:run("juice", function()
				JuiceFx.defeat(at)
				JuiceFx.rescue(at, { renown = 5 })
				JuiceFx.gearDrop(at, { tier = "Legendary" })
				JuiceFx.respawn()
				JuiceFx.dazed(true)
			end)
			check(count("JuiceCoin") == 6, "the coin burst is six struck coins")
			check(count("JuiceRing") >= 2, "the rescue and drop rings are glow rings")
			check(count("JuiceBeam") == 1, "the tier beam is the twisting column")
			check(count("GuardBubble") == 1, "the respawn shield is the geodesic bubble")
			local dazed = folder:FindFirstChild("Dazed")
			check(dazed ~= nil and #dazed:GetChildren() == 3, "three dazed stars")
			sim:run("undazed", function()
				JuiceFx.dazed(false)
			end)
			check(folder:FindFirstChild("Dazed") == nil, "the stars go when the stun ends")
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, "; "))
		end
	)

	test(
		"List combat: every nemesis head and bust piece is shaped; the WANTED bill is printed (Everything Left 397)",
		function()
			local roblox = require("@lune/roblox")
			local WantedRules = require("../src/shared/WantedRules")
			local HqArtKit = require("../src/shared/HqArtKit")
			local N = Config.Nemesis
			local model = roblox.deserializeModel(fs.readFile("art/models/NemParts.rbxm"))[1]
			for name in Config.NemPartArt.HqNemParts do
				local mp = model:FindFirstChild(name, true)
				check(mp ~= nil and mp:IsA("MeshPart"), name .. " is imported")
			end
			-- every head kind, build and trait: each piece the bust and heads put up has its shape
			local allTraits = 0
			for i in N.traits do
				allTraits += 2 ^ (i - 1)
			end
			for _, head in N.heads do
				for _, build in N.builds do
					local look = {
						head = head,
						build = build,
						colors = 1,
						cape = true,
						traits = allTraits,
						rank = 3,
						name = "X",
					}
					for _, p in WantedRules.bust(N, look :: any) do
						local sh = HqArtKit.SHAPES[p.name]
						check(sh ~= nil, head .. "/" .. build .. ": " .. p.name .. " has a shape")
						if sh then
							check(
								#HqArtKit.fill(Config, p.name, { p.sx, p.sy, p.sz }) == #sh.meshes,
								p.name .. " fills its part"
							)
						end
					end
				end
			end
			check(type(Config.Hq.wanted.paper) == "number", "the WANTED bill has its uploaded picture")
			check(fs.isFile("art/export/ui/wanted/Paper.png"), "drawn by art/ui/wanted_paper.py")
			local hq = fs.readFile("src/client/Controllers/HqClient.luau")
			check(string.find(hq, "W.paper", 1, true) ~= nil, "HqClient lays the bill under the words")
			if not T.placePath then
				return
			end
			-- the place has Art.NemParts, and HqMeshes covers a cannon part with its meshes
			local UiSim = require("./uisim")
			local sim = UiSim.new(
				UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
				{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
			)
			local HqMeshes = sim:require("Client.Fx.HqMeshes")
			local holder = UiSim.newInstance("Folder")
			holder.Parent = sim.workspace
			local covered = {}
			sim:run("cover", function()
				for _, shape in
					{ "cannon", "dome", "cyclopsEye", "healDrone", "antenna", "eye", "neck", "plates" }
				do
					local part = UiSim.newInstance("Part")
					part.Size = roblox.Vector3.new(2, 1, 1)
					part.Anchored = true
					part.Parent = holder
					covered[shape] = HqMeshes.cover(part, shape)
				end
			end)
			for shape, ok in covered do
				check(ok == true, shape .. " is covered by its meshes in the built place")
			end
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, "; "))
		end
	)

	test("List combat: the part-built throwables wear Blender meshes (Everything Left 390)", function()
		local roblox = require("@lune/roblox")
		local Th = Config.Throw
		local model = roblox.deserializeModel(fs.readFile("art/models/Throwables.rbxm"))[1]
		local kinds = 0
		for kind, d in Th.dress do
			if not d.art then
				continue
			end
			kinds += 1
			local fit = Config.ThrowArt[kind]
			check(fit ~= nil, kind .. " has its fit table")
			check(d.parts ~= nil, kind .. " keeps its parts as the fallback")
			local box = Th.kinds[kind].size
			local top = 0
			for piece, f in fit or {} do
				local mp = model:FindFirstChild(piece, true)
				check(mp ~= nil and mp:IsA("MeshPart"), kind .. ": " .. piece .. " is imported")
				top = math.max(top, f.offset[2] + f.size[2] / 2)
			end
			-- scaled to the box's height, every piece stays within (or just past) the box
			local k = box[2] / top
			for piece, f in fit or {} do
				for j = 1, 3 do
					local lo = (f.offset[j] - f.size[j] / 2) * k
					local hi = (f.offset[j] + f.size[j] / 2) * k
					local half = if j == 2 then nil else box[j] / 2
					if half then
						check(
							lo >= -half - 0.35 and hi <= half + 0.35,
							string.format("%s %s inside its box on %d", kind, piece, j)
						)
					else
						check(lo >= -0.05, kind .. " " .. piece .. " stands on the foot")
					end
				end
			end
		end
		check(kinds == 5, "the mailbox, sign, dumpster, slab and rubble (" .. kinds .. ")")
		if not T.placePath then
			return
		end
		local UiSim = require("./uisim")
		local sim = UiSim.new(
			UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		)
		local ThrowFx = sim:require("Client.Fx.ThrowFx")
		for kind, d in Th.dress do
			if not d.art then
				continue
			end
			local m = UiSim.newInstance("Model")
			m:SetAttribute("ThrowKind", kind)
			local body = UiSim.newInstance("Part")
			body.Name = "Body"
			local sz = Th.kinds[kind].size
			body.Size = roblox.Vector3.new(sz[1], sz[2], sz[3])
			body.Parent = m
			m.Parent = sim.workspace
			local made = 0
			sim:run("dress " .. kind, function()
				made = ThrowFx.dress(m)
			end)
			local n = 0
			for _ in Config.ThrowArt[kind] do
				n += 1
			end
			check(made == n, kind .. " is dressed in its " .. n .. " meshes (" .. made .. ")")
			local first = m:FindFirstChildWhichIsA("MeshPart")
			check(
				first ~= nil and string.sub(first.Name, 1, 6) == "Dress_",
				kind .. "'s meshes are on the model"
			)
		end
		check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, "; "))
	end)

	test(
		"List combat: the Shield Drone is a Blender drone in the geodesic bubble (Everything Left 383)",
		function()
			local roblox = require("@lune/roblox")
			local model = roblox.deserializeModel(fs.readFile("art/models/Gadget.rbxm"))[1]
			for name in Config.GadgetArt do
				local mp = model:FindFirstChild(name, true)
				check(mp ~= nil and mp:IsA("MeshPart"), name .. " is imported")
			end
			if not T.placePath then
				return
			end
			local UiSim = require("./uisim")
			local sim = UiSim.new(
				UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
				{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
			)
			local char = UiSim.newInstance("Model")
			local root = UiSim.newInstance("Part")
			root.Name = "HumanoidRootPart"
			root.Parent = char
			char.Parent = sim.workspace
			sim.player.Character = char
			local GadgetFx = sim:require("Client.Fx.GadgetFx")
			local ok = false
			sim:run("drone", function()
				ok = GadgetFx.drone(sim.player, 5)
			end)
			check(ok, "the drone flies")
			local drone = sim.workspace:FindFirstChild("ShieldDrone", true)
			check(drone ~= nil, "its model is out")
			if drone then
				local body, bubble = drone:FindFirstChild("Body"), drone:FindFirstChild("Bubble")
				check(body ~= nil and body:IsA("MeshPart"), "its body is the Blender pod")
				check(bubble ~= nil and bubble:IsA("MeshPart"), "its shield is the geodesic bubble")
				local rotor = drone:FindFirstChild("Rotor")
				check(
					rotor == nil or rotor:IsA("MeshPart"),
					"its rotor (when the preset draws it) is the Blender rotor"
				)
			end
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, "; "))
		end
	)

	test("List combat: the line weapons swing a rope or chain mesh (Everything Left 392)", function()
		local roblox = require("@lune/roblox")
		local TetherMath = require("../src/shared/TetherMath")
		local model = roblox.deserializeModel(fs.readFile("art/models/Tether.rbxm"))[1]
		local ropes = 0
		for id, spec in TetherMath.SPECS do
			if spec.mode == "rope" then
				ropes += 1
				check(spec.link ~= nil and Config.TetherArt[spec.link] ~= nil, id .. " names its link mesh")
				local mp = spec.link and model:FindFirstChild(spec.link, true)
				check(mp ~= nil and mp:IsA("MeshPart"), id .. "'s link is imported")
			end
		end
		check(ropes == 3, "the Chain Whip, Yo-yo and Rope Dart")
		check(TetherMath.SPECS[32].link == "TetherChain", "the Chain Whip swings a chain")
		local fx = fs.readFile("src/client/Fx/TetherFx.luau")
		check(string.find(fx, "MeshFix.clone(src)", 1, true) ~= nil, "TetherFx clones the link mesh")
		check(string.find(fx, "cf * LINK_TURN", 1, true) ~= nil, "and turns it as imported")
		check(not string.find(fx, "PLACEHOLDER ART", 1, true), "no placeholder links")
	end)

	test("List combat: the farm truck's wheels roll and steer (Everything Left 395)", function()
		local roblox = require("@lune/roblox")
		local fit = Config.SetPieceArt.FarmTruck
		local model = roblox.deserializeModel(fs.readFile("art/models/SetPieces.rbxm"))[1]
		local wheels, steer = 0, 0
		for name, f in fit do
			check(model:FindFirstChild(name, true) ~= nil, name .. " is imported")
			if f.wheel then
				wheels += 1
				check(f.wheel.r > 1 and f.wheel.r < 1.4, name .. " has its radius")
				check(math.abs(f.offset[2] - f.wheel.r) < 0.05, name .. " sits on the road")
				if f.wheel.steer then
					steer += 1
					check(f.wheel.axle == 0 and f.offset[3] < 0, name .. " steers at the front")
				end
			end
		end
		check(wheels == 4 and steer == 2, "four road wheels, the front pair steers")
		check(fit.FarmTruckWheels == nil, "no baked wheel set left")
		-- SetPieceMeshes hands the wheel to the devices (VehicleRig rolls anything with WheelR)
		local spm = fs.readFile("src/server/Services/SetPieceMeshes.luau")
		check(string.find(spm, 'p:SetAttribute("WheelR", w.r)', 1, true) ~= nil, "the wheel attribute")
	end)

	test("List combat: auras and mentor trails draw the uploaded textures (Everything Left 387)", function()
		local roblox = require("@lune/roblox")
		for _, m in Config.Mentors.list do
			local tex = m.look.tex
			if m.look.kind == "trail" then
				local k = Config.Creator.trailFx.kits[tex]
				check(k ~= nil and k.id > 0, m.id .. "'s trail strip is uploaded")
			else
				local t = Config.Fx.lib.textures[tex]
				check(t ~= nil and t.id > 0, m.id .. "'s motes sheet is uploaded")
			end
		end
		check(Config.Fx.lib.textures[Config.Mentors.accoladeTex] ~= nil, "the accolade motes texture")
		for _, f in { "src/client/Fx/MentorFx.luau", "src/client/Fx/AuraFx.luau" } do
			check(
				not string.find(fs.readFile(f), "PLACEHOLDER ART", 1, true),
				f .. " is no longer placeholder art"
			)
		end
		if not T.placePath then
			return
		end
		local UiSim = require("./uisim")
		local sim = UiSim.new(
			UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		)
		local char = UiSim.newInstance("Model")
		local root = UiSim.newInstance("Part")
		root.Name = "HumanoidRootPart"
		root.CFrame = roblox.CFrame.new(10, 3, 10)
		root.Parent = char
		local torso = UiSim.newInstance("Part")
		torso.Name = "UpperTorso"
		torso.Parent = char
		char.Parent = sim.workspace
		sim.player.Character = char
		local MentorFx = sim:require("Client.Fx.MentorFx")
		sim:run("MentorFx", MentorFx.init)
		local function find(parent: any, cls: string, name: string?): any
			for _, c in parent:GetChildren() do
				if c.ClassName == cls and (name == nil or c.Name == name) then
					return c
				end
			end
			return nil
		end
		for _, m in Config.Mentors.list do
			sim:run("look", function()
				sim.player:SetAttribute("MentorLook", m.look.id)
			end)
			if m.look.kind == "trail" then
				local t = find(torso, "Trail")
				local k = Config.Creator.trailFx.kits[m.look.tex]
				check(
					t ~= nil and t.Texture == "rbxassetid://" .. tostring(k.id),
					m.id .. ": the trail wears its strip"
				)
			else
				local e = find(torso, "ParticleEmitter")
				local tx = Config.Fx.lib.textures[m.look.tex]
				check(
					e ~= nil and e.Texture == "rbxassetid://" .. tostring(tx.id),
					m.id .. ": the motes wear the sheet"
				)
			end
		end
		-- accolade aura
		local aura
		for _, g in Config.Badges.groups do
			if g.accolade and g.accolade.kind == "aura" then
				aura = g.accolade.id
				break
			end
		end
		sim:run("aura", function()
			sim.player:SetAttribute("AccoladeAura", aura)
		end)
		local ae = find(root, "ParticleEmitter", "AccoladeAuraFx")
		check(
			ae ~= nil and string.find(ae.Texture, "rbxassetid://", 1, true) ~= nil,
			"the accolade motes are textured"
		)
		-- AuraFx: shield bubble mesh and Awakened motes
		local AuraFx = sim:require("Client.Fx.AuraFx")
		sim:run("AuraFx", AuraFx.init)
		sim:run("awake", function()
			sim.player:SetAttribute("Aura", 1)
			sim.player:SetAttribute("Awakened", true)
			sim.service("RunService").Heartbeat:Fire(0.2)
		end)
		local bubble = char:FindFirstChild("ShieldBubble")
		check(bubble ~= nil and bubble:IsA("MeshPart"), "the shield bubble is the geodesic mesh")
		check(bubble ~= nil and bubble.Transparency < 1, "the shield shows")
		local motes = find(root, "ParticleEmitter", "AwakenMotes")
		check(motes ~= nil and motes.Enabled == true, "the Awakened motes are on")
		check(
			motes ~= nil and motes.Texture == "rbxassetid://" .. tostring(Config.Fx.lib.textures.spark.id),
			"spark sheet"
		)
		sim:run("calm", function()
			sim.player:SetAttribute("Awakened", false)
			sim.service("RunService").Heartbeat:Fire(0.2)
		end)
		check(motes ~= nil and motes.Enabled == false, "the motes stop with Awakening")
	end)

	test("List combat: a charging hero gathers the path's textured motes (Everything Left 388)", function()
		local roblox = require("@lune/roblox")
		local m = Config.Combat.charge.motes
		check(m ~= nil and m.fast < m.slow and m.first > 0, "Config.Combat.charge.motes")
		check(
			not string.find(fs.readFile("src/client/Fx/ChargeFx.luau"), "PLACEHOLDER ART", 1, true),
			"ChargeFx is no longer placeholder art"
		)
		if not T.placePath then
			return
		end
		local UiSim = require("./uisim")
		local sim = UiSim.new(
			UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		)
		local char = UiSim.newInstance("Model")
		local root = UiSim.newInstance("Part")
		root.Name = "HumanoidRootPart"
		root.CFrame = roblox.CFrame.new(10, 3, 10)
		root.Parent = char
		char.Parent = sim.workspace
		sim.player.Character = char
		local num
		for n, row in Config.Abilities.byNum do
			if row.charge then
				num = n
				break
			end
		end
		check(num ~= nil, "a charge-up power")
		-- another hero charging (your own motes orbit your hand in AimPreview)
		local other = UiSim.newInstance("Player")
		other.Name = "Other"
		other.Parent = sim.service("Players")
		other.Character = char
		sim.player.Character = nil
		local me = sim.player
		sim.service("Players")._props.GetPlayers = function()
			return { me, other }
		end
		local ChargeFx = sim:require("Client.Fx.ChargeFx")
		sim:run("ChargeFx", ChargeFx.init)
		local function frame()
			sim:run("frame", function()
				sim.service("RunService").RenderStepped:Fire(1 / 60)
			end)
		end
		sim:run("charge", function()
			other:SetAttribute("Charging", num)
		end)
		frame()
		check(char:FindFirstChildOfClass("Highlight") ~= nil, "the outline cue")
		local host = sim.workspace:FindFirstChild("FxEmitters")
		check(host ~= nil, "the effects library drew the gather")
		local function textured(): (number, number)
			local n, t = 0, 0
			for _, d in host:GetDescendants() do
				if d:IsA("ParticleEmitter") then
					n += 1
					if string.find(d.Texture, "rbxassetid://", 1, true) then
						t += 1
					end
				end
			end
			return n, t
		end
		local n0, t0 = textured()
		check(n0 > 0 and t0 == n0, "every gather emitter wears an uploaded sheet")
		local t = os.clock()
		local spins = 0
		while os.clock() - t < m.first + 0.05 do
			spins += 1 -- wait past the first mote (os.clock is real time in the sim)
		end
		frame()
		local n1 = textured()
		check(n1 > n0, "the path's charge motes follow")
		sim:run("stop", function()
			other:SetAttribute("Charging", nil)
		end)
		frame()
		check(char:FindFirstChildOfClass("Highlight") == nil, "the glow ends with the charge")
	end)

	test(
		"List combat: the aim preview draws a ground ring and scrolling chevrons (Everything Left 389)",
		function()
			local roblox = require("@lune/roblox")
			local A = Config.Ui.aimArt
			check(A ~= nil and A.ring > 0 and A.chevron > 0, "Config.Ui.aimArt ids (uploaded)")
			for _, f in { "Ring.png", "Chevron.png" } do
				check(fs.isFile("art/export/ui/aim/" .. f), f .. " drawn by art/ui/aim_ui.py")
			end
			check(
				not string.find(fs.readFile("src/client/Fx/AimPreview.luau"), "PLACEHOLDER ART", 1, true),
				"AimPreview is no longer placeholder art"
			)
			if not T.placePath then
				return
			end
			local UiSim = require("./uisim")
			local sim = UiSim.new(
				UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
				{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
			)
			local AimPreview = sim:require("Client.Fx.AimPreview")
			local V = roblox.Vector3
			local col = roblox.Color3.fromRGB(90, 200, 255)
			local function draw(eff: any, level: number)
				sim:run("draw", function()
					AimPreview.draw(
						eff,
						V.new(0, 3, 0),
						V.new(0, 0, 0),
						V.new(0, 0, -20),
						col,
						level,
						"Comic"
					)
				end)
			end
			local folder = sim.workspace:FindFirstChild("AimPreview")
			draw({ shape = "nova", radius = 12, set = "Volt" }, 0)
			folder = sim.workspace:FindFirstChild("AimPreview")
			check(folder ~= nil, "the preview's folder")
			local ring, strip
			for _, p in folder:GetChildren() do
				local art = p:FindFirstChild("AimArt")
				if art and art.ClassName == "Decal" then
					ring = p
				elseif art and art.ClassName == "Texture" and not strip then
					strip = p
				end
			end
			check(ring ~= nil, "the ring wears its Decal")
			local d = ring and ring:FindFirstChild("AimArt")
			check(d ~= nil and d.Texture == "rbxassetid://" .. tostring(A.ring), "the ring picture")
			check(
				ring ~= nil and ring.Transparency == 1 and d.Transparency < 1,
				"the picture shows, the part stays clear"
			)
			check(
				ring ~= nil and math.abs(ring.Size.X - 24) < 0.01 and ring.Size.Y < 0.2,
				"the ring is a flat 2r disc"
			)
			check(
				d ~= nil and d.Color3 == col:Lerp(roblox.Color3.new(1, 1, 1), 0.15),
				"tinted the power's colour"
			)
			-- a bolt: the chevron strip
			draw({ shape = "bolt", range = 40, width = 2, set = "Volt" }, 0.5)
			check(d.Transparency == 1, "the ring hides for a line")
			local tex = strip and strip:FindFirstChild("AimArt")
			local shown = 0
			for _, p in folder:GetChildren() do
				local t = p:FindFirstChild("AimArt")
				if t and t.ClassName == "Texture" and t.Transparency < 1 then
					shown += 1
					check(t.Texture == "rbxassetid://" .. tostring(A.chevron), "the chevron picture")
					check(t.StudsPerTileV == A.tile, "a chevron every tile")
				end
			end
			check(shown == 1, "one strip for a line")
			check(tex ~= nil, "the strips wear the chevron Texture")
			-- a cone: five chevron rays
			draw({ shape = "cone", range = 20, cone = 60, set = "Volt" }, 0)
			shown = 0
			for _, p in folder:GetChildren() do
				local t = p:FindFirstChild("AimArt")
				if t and t.ClassName == "Texture" and t.Transparency < 1 then
					shown += 1
					check(math.abs(p.Size.X - A.rayWidth) < 0.01, "a ray is rayWidth wide")
				end
			end
			check(shown == 5, "five rays for a cone")
			sim:run("hide", AimPreview.hide)
			for _, p in folder:GetChildren() do
				local t = p:FindFirstChild("AimArt")
				check(t == nil or t.Transparency == 1, "hide clears every picture")
			end
		end
	)

	test("List combat: the prologue crowd are Roblox-avatar citizens (Everything Left 406)", function()
		local roblox = require("@lune/roblox")
		check(type(Config.Story.opening.plaza.crowd.seed) == "number", "the crowd's look seed")
		check(
			not string.find(
				fs.readFile("src/client/Fx/PrologueFx.luau"),
				"the crowd and Crane are plain",
				1,
				true
			),
			"the crowd is no longer placeholder art"
		)
		if not T.placePath then
			return
		end
		local UiSim = require("./uisim")
		local sim = UiSim.new(
			UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		)
		local PrologueFx = sim:require("Client.Fx.PrologueFx")
		local faces = {}
		for _, f in Config.CatalogLooks.faces do
			faces["rbxassetid://" .. f[3]] = true
		end
		local shirts = {}
		for _, id in Config.Creator.clothes.shirts do
			shirts["rbxassetid://" .. id] = true
		end
		local seen = {}
		for i = 1, 6 do
			local rig
			sim:run("cast", function()
				rig = PrologueFx.cast("citizen", sim.workspace, i)
			end)
			check(rig ~= nil, "a crowd citizen " .. i)
			local face = rig.parts.Head:FindFirstChild("face")
			check(face ~= nil and faces[face.Texture] == true, "a catalog face")
			local shirt
			for _, d in rig.model:GetDescendants() do
				if d.ClassName == "Texture" and d.Name == "Clothes" and shirts[d.Texture] then
					shirt = d.Texture
					break
				elseif d.ClassName == "Shirt" then
					shirt = d.ShirtTemplate
					break
				end
			end
			check(shirt ~= nil, "wears an uploaded shirt " .. i)
			if shirt then
				seen[shirt] = true
			end
			rig.model:Destroy()
		end
		local n = 0
		for _ in seen do
			n += 1
		end
		check(n >= 2, "the crowd wears different shirts")
	end)

	test("List combat: side styles wear their side's crest over the shape (Everything Left 398)", function()
		local roblox = require("@lune/roblox")
		local SG = Config.SideGearArt
		check(SG ~= nil, "Config.SideGearArt (generated by art/blender/sidegear.py)")
		local model = roblox.deserializeModel(fs.readFile("art/models/SideGear.rbxm"))[1]
		for name in SG.meshes do
			local mp = model:FindFirstChild(name, true)
			check(mp ~= nil and mp:IsA("MeshPart"), name .. " is imported")
		end
		local GearMath = require("../src/shared/GearMath")
		local n = 0
		for slot, list in Config.Gear.styles do
			for _, row in list do
				if row.tier == "Rep" then
					n += 1
					local key = GearMath.lookKey(slot, row)
					local fit = SG.looks[key] and SG.looks[key][row.rep[1]]
					check(fit ~= nil and #fit >= 2, row.name .. " has its side's crest")
					check(Config.GearArt.looks[key] ~= nil, row.name .. " keeps its slot shape")
					for _, p in fit or {} do
						check(SG.meshes[p.mesh] ~= nil, p.mesh .. " is a crest mesh")
						check(p.size[1] < 1.5 and p.size[2] < 1.5, row.name .. " crest is small")
					end
				end
			end
		end
		check(n == 20, "the 20 side styles")
		local src = fs.readFile("src/server/Services/LookService.luau")
		check(
			string.find(src, "sideCrest(char, folder, slot, row, trim)", 1, true) ~= nil,
			"LookService adds it"
		)
		-- (LookService is a server module, which the UI sim does not load: the crest's wearing is Studio list 49)
		for _, p in SG.looks["back:longcape"].syndicate do
			check(p.role == "glow" or p.role == "steel", "the Syndicate crest is steel and glow")
		end
		for _, p in SG.looks["back:longcape"].vigil do
			check(p.role == "glow" or p.role == "gold", "the Vigil crest is gold and glow")
		end
	end)

	test("List combat: travel styles draw the uploaded sheets and strips (Everything Left 143)", function()
		local roblox = require("@lune/roblox")
		local TS = Config.TravelStyles
		for _, list in TS.byMobility do
			for _, st in list do
				local a = TS.art[st.burst]
				check(a ~= nil, st.name .. ": its burst kind has art")
				check(Config.Fx.lib.textures[a.mote].id > 0, st.name .. ": the mote sheet is uploaded")
				check(Config.Creator.trailFx.kits[a.trail].id > 0, st.name .. ": the trail strip is uploaded")
			end
		end
		check(
			not string.find(fs.readFile("src/client/Fx/TravelStyleFx.luau"), "PLACEHOLDER ART", 1, true),
			"TravelStyleFx is no longer placeholder art"
		)
		if not T.placePath then
			return
		end
		local UiSim = require("./uisim")
		local sim = UiSim.new(
			UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		)
		local char = UiSim.newInstance("Model")
		local root = UiSim.newInstance("Part")
		root.Name = "HumanoidRootPart"
		root.Parent = char
		char.Parent = sim.workspace
		sim.player.Character = char
		local TravelStyleFx = sim:require("Client.Fx.TravelStyleFx")
		sim:run("init", TravelStyleFx.init)
		local TravelStyleRules = require("../src/shared/TravelStyleRules")
		local seen = {}
		for id = 1, 30 do
			local st = TravelStyleRules.byId(Config, id)
			if st and not seen[st.burst] then
				seen[st.burst] = true
				sim:run("style", function()
					sim.player:SetAttribute("TravelStyle", id)
				end)
				local tr, mo
				for _, c in root:GetChildren() do
					if c.ClassName == "Trail" then
						tr = c
					elseif c.ClassName == "ParticleEmitter" then
						mo = c
					end
				end
				local a = Config.TravelStyles.art[st.burst]
				check(
					tr ~= nil
						and tr.Texture
							== "rbxassetid://" .. tostring(Config.Creator.trailFx.kits[a.trail].id),
					st.burst .. ": the trail strip"
				)
				check(
					mo ~= nil and mo.Texture == "rbxassetid://" .. tostring(Config.Fx.lib.textures[a.mote].id),
					st.burst .. ": the mote sheet"
				)
			end
		end
	end)

	test("List combat: Photo Mode backdrops are printed overlays (Everything Left 354)", function()
		local ids = Config.Ui.photoBackdrops
		for _, name in { "COMIC", "SPEED", "SUNSET", "NOIR", "NEON" } do
			check(type(ids[name]) == "number" and ids[name] > 0, name .. " has its uploaded picture")
			check(
				fs.isFile(
					"art/export/ui/photo/"
						.. string.sub(name, 1, 1)
						.. string.lower(string.sub(name, 2))
						.. ".png"
				),
				name .. " is drawn by art/ui/photo_backdrops.py"
			)
		end
		local src = fs.readFile("src/client/Ui/PhotoMode.luau")
		check(
			string.find(src, "U.photoBackdrops", 1, true) ~= nil,
			"PhotoMode lays the picture over the screen"
		)
		check(string.find(src, '"BackdropArt"', 1, true) ~= nil, "as BackdropArt")
	end)

	test("List combat: citizens stop to chat (Everything Left 275)", function()
		local CitizenSim = require("../src/shared/CitizenSim")
		local sim = CitizenSim.new(Config, {}, 3)
		CitizenSim.populate(sim)
		local cfg = table.clone(sim.cfg)
		cfg.chat = table.clone(cfg.chat)
		cfg.chat.chance = 1
		sim.cfg = cfg
		local a, b = sim.citizens[1], sim.citizens[2]
		b.state = CitizenSim.PAUSE
		b.untilT = 2
		a.state = CitizenSim.WALK
		a.x, a.z = b.x + 3, b.z
		a.chatAfter = nil
		CitizenSim.step(sim, 0.1, 1)
		check(a.state == CitizenSim.PAUSE, "the walker stops by the stopped one")
		check(a.fx < -0.9, "and faces them")
		check(b.untilT >= a.untilT - 1e-6 and a.untilT >= 1 + cfg.chat.time[1], "both stay to talk")
		-- not twice in a row: after the chat the cooldown holds
		a.state = CitizenSim.WALK
		b.state = CitizenSim.PAUSE
		b.untilT = 100
		CitizenSim.step(sim, 0.1, 1.2)
		check(a.state == CitizenSim.WALK, "the cooldown keeps it walking")
		-- the real tuning over two minutes of a city: some chats happen, most of the crowd keeps walking
		local live = CitizenSim.new(Config, {}, 7)
		CitizenSim.populate(live)
		local chats, walking = 0, 0
		for k = 1, 1200 do
			CitizenSim.step(live, 0.1, k * 0.1)
		end
		for _, c in live.citizens do
			if c.chatAfter then
				chats += 1
			end
			if c.state == CitizenSim.WALK then
				walking += 1
			end
		end
		print(string.format("  citizens: %d tried a chat in 2 minutes, %d walking now", chats, walking))
		check(walking >= #live.citizens * 0.4, "most of the crowd keeps walking")
	end)

	test("List combat: vehicle lettering sits on the bodies' sides (Everything Left 271)", function()
		local VehicleKit = require("../src/shared/VehicleKit")
		local art = Config.VehicleArt
		local n = 0
		for look, L in VehicleKit.LETTERS do
			n += 1
			local row = art[look]
			check(row ~= nil, look .. " is a vehicle look")
			if not row then
				continue
			end
			-- the look's outer box (every mesh but the wheels)
			local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
			local body = 0
			for name, m in row do
				if not string.find(name, "Wheel") then
					for a = 1, 3 do
						lo[a] = math.min(lo[a], m.offset[a] - m.size[a] / 2)
						hi[a] = math.max(hi[a], m.offset[a] + m.size[a] / 2)
					end
				end
				if string.find(name, "Body$") then
					body = m.size[1] / 2
				end
			end
			check(L.x <= hi[1] + 0.05 and L.x >= body - 0.25, look .. ": the panel's faces lie on the sides")
			check(
				L.y - L.h / 2 >= lo[2] and L.y + L.h / 2 <= hi[2],
				look .. ": the band is within the body's height"
			)
			check(
				L.z - L.len / 2 >= lo[3] - 0.05 and L.z + L.len / 2 <= hi[3] + 0.05,
				look .. ": the band is within its length"
			)
			check(string.upper(L.text) == L.text and #L.text <= 24, look .. ": fixed capital words")
		end
		check(n == 8, "8 lettered looks: " .. n)
		local src = fs.readFile("src/server/Services/SetPieceMeshes.luau")
		check(
			string.find(src, "VehicleKit.LETTERS[place.look]", 1, true) ~= nil,
			"SetPieceMeshes letters them"
		)
	end)

	test("List combat: weapons wear baked texture sets (Everything Left 192)", function()
		local roblox = require("@lune/roblox")
		local model = roblox.deserializeModel(fs.readFile("art/models/Weapons.rbxm"))[1]
		check(Config.Weapons.textures == true, "Config.Weapons.textures")
		local flat, textured = 0, 0
		for _, w in Config.WeaponArt do
			for _, p in w.pieces do
				local mp = model:FindFirstChild(p.mesh, true)
				local sa = mp and mp:FindFirstChildOfClass("SurfaceAppearance")
				if p.glow or p.neon then
					check(sa == nil, p.mesh .. ": a glow piece stays flat light")
					flat += 1
				else
					check(sa ~= nil and sa.ColorMap ~= "", p.mesh .. " has its texture set")
					textured += 1
				end
			end
		end
		check(textured > 100, "most pieces are textured: " .. textured .. " (flat " .. flat .. ")")
		if not T.placePath then
			return
		end
		local WeaponSim = require("./weaponsim")
		local sim = WeaponSim.new(roblox.deserializePlace(fs.readFile(T.placePath)))
		local function count(look)
			local folder = sim:weapon(sim:body(), look)
			local sas, glow, n = 0, 0, 0
			for _, m in folder:GetChildren() do
				if m:IsA("MeshPart") then
					n += 1
					local sa = m:FindFirstChildOfClass("SurfaceAppearance")
					if sa then
						sas += 1
						check(sa.AlphaMode == roblox.Enum.AlphaMode.Overlay, "the colour shows through")
					end
					if m.Material == roblox.Enum.Material.Neon then
						glow += 1
						check(sa == nil, "a glowing piece keeps no texture")
					end
				end
			end
			return n - glow, sas
		end
		-- the Sword (5) in Steel: blade and hilt textured; in Wood the blade keeps the wood material, the hilt its maps
		local n, steel = count({ id = 5, style = 1, finish = 1, glowLevel = 0 })
		check(n > 0 and steel == n, "every unlit Steel sword piece is textured: " .. steel .. " of " .. n)
		local _, wood = count({ id = 5, style = 1, finish = 5, glowLevel = 0 })
		check(wood > 0 and wood < steel, "a Wood blade drops its metal maps: " .. wood)
		local _, energy = count({ id = 5, style = 4, finish = 1, glowLevel = 0 })
		check(energy < steel, "the Energy style's light blade is untextured: " .. energy)
	end)
end
