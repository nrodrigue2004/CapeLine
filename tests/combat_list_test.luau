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
end
