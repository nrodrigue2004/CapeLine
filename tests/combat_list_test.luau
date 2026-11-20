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
			-- (the last two pieces since the PsiSlab look, Everything Left 382)
			string.find(cf, 'for i, name in { [n - 1] = "Crate", [n] = "Barrel" } do', 1, true) ~= nil,
			"psi junk"
		)
		check(
			string.find(cf, "CityProps.dress(name, holder, holder.Size.Y, dressed)", 1, true) ~= nil,
			"dressed"
		)
		check(Config.City.kit.props.Barrel ~= nil and Config.StreetArt.Barrel ~= nil, "Barrel is a kit prop")
		check(Config.Abilities.list.GirderSwing ~= nil, "Girder Swing exists")
		-- the held girder in its Blender look (Art.Powers Girder) once imported, the parts before
		local G = Config.PowerArt.Girder
		check(
			G ~= nil and G.GirderBeam ~= nil and G.GirderRivets ~= nil,
			"the girder's meshes are in the fit table"
		)
		check(
			G.GirderBeam.size[2] > 9 and G.GirderBeam.offset[2] < -4,
			"the beam hangs down from the hand, about 11 long"
		)
		check(
			string.find(cf, 'PowerMeshes.pieces("Girder", hand.CFrame)', 1, true) ~= nil,
			"heldGirder draws the Blender girder at the hand"
		)
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
			n == 96,
			"96 meshes in 41 looks (the supers' sigil, sunrise, helix and crater; Siege Mode's anchors; the Bomber's grenade; the petal; a robot's scrap; the psi gem; the snowflake; the hex plate; the robots' net and claw; the wings flourish; 178 the held girder; 382 added the jets, the rail and the slab; 173 the bullet; 169, 177, 180 and 183 the sun, ki ring, black hole and field rims; 172 the slash; 381 the shock ring and cone fan, then the flying heads; 167 Static Field's arcs): "
				.. n
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
				"Bullet",
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
				'PowerMeshes.ready("Bullet")',
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
					if d:IsA("BasePart") or (d:IsA("Beam") and d.Name == "Lightning") then
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
				volt >= other + 5,
				"Bolt Ride draws its drawn bolt, forks and scorch: " .. volt .. " vs " .. other
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

	test("List combat: knocked-out pieces fly as broken blocks and bits (Art.Rubble chunks)", function()
		local roblox = require("@lune/roblox")
		local art = Config.RubbleArt
		local model = roblox.deserializeModel(fs.readFile("art/models/Rubble.rbxm"))[1]
		for k = 1, 3 do
			local name = "Chunk" .. k
			local row = art[name]
			check(row ~= nil and row[name] ~= nil, name .. " in the fit table")
			local mp = model:FindFirstChild(name, true)
			check(
				mp ~= nil and mp:IsA("MeshPart") and string.match(mp.MeshId, "%d+$") ~= nil,
				name .. " imported"
			)
			-- one mesh filling its own box, so stretched to a piece's box it fills the piece exactly
			for i = 1, 3 do
				check(math.abs(row[name].size[i] - row.box[i]) < 1e-3, name .. " fills its box")
			end
			check(row[name].tris < 400, name .. " stays light")
		end
		local B = Config.Destruction.structure.bits
		check(B ~= nil and B.count >= 1 and B.most > 0, "wall bits are tuned")
		local fx = fs.readFile("src/client/Fx/BuildingFx.luau")
		for _, needle in
			{
				"for i, piece in breakUp(rec, part) do",
				'if pieceKind[part] ~= "wall" then',
				"DebrisBudget.lease(B.count, D.structure.debrisLife)",
				"p.CFrame = cf * MeshFix.of(p)",
				"pieceKind[p] = c.kind",
			}
		do
			check(string.find(fx, needle, 1, true) ~= nil, "BuildingFx: " .. needle)
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

	test(
		"List combat: the prologue's kid and shover are dressed like the crowd, in their beat's colours",
		function()
			local roblox = require("@lune/roblox")
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
			local heights = {}
			for kind, want in
				{ kid = roblox.Color3.fromRGB(255, 200, 60), shover = roblox.Color3.fromRGB(190, 50, 50) }
			do
				local rig
				sim:run("cast", function()
					rig = PrologueFx.cast(kind, sim.workspace)
				end)
				check(rig ~= nil, "the " .. kind)
				if not rig then
					continue
				end
				local face = rig.parts.Head:FindFirstChild("face")
				check(face ~= nil and faces[face.Texture] == true, "the " .. kind .. " has a catalog face")
				local shirt
				for _, d in rig.model:GetDescendants() do
					if d.ClassName == "Texture" and shirts[d.Texture] then
						shirt = d
						break
					end
				end
				check(shirt ~= nil, "the " .. kind .. " wears an uploaded shirt")
				if shirt then
					local c = shirt.Color3
					check(
						math.abs(c.R - want.R) + math.abs(c.G - want.G) + math.abs(c.B - want.B) < 0.02,
						"in the beat's colour"
					)
				end
				heights[kind] = rig.parts.UpperTorso.Size.Y + rig.parts.LeftUpperLeg.Size.Y
				rig.model:Destroy()
			end
			check((heights.kid or 0) < (heights.shover or 0) * 0.8, "the kid is small")
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
		end
	)

	test("List combat: the prologue's title card shows the drawn CAPELINE logo", function()
		local roblox = require("@lune/roblox")
		check((Config.Ui.logo or 0) ~= 0, "the logo is uploaded")
		check(
			not string.find(
				fs.readFile("src/client/Ui/StoryHud.luau"),
				"the title card is the plain Kit title",
				1,
				true
			),
			"no longer the plain title"
		)
		if not T.placePath then
			return
		end
		local UiSim = require("./uisim")
		local sim = UiSim.new(
			UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		)
		sim:run("InputController", sim:require("Client.Controllers.InputController").init)
		sim:run("StoryHud", sim:require("Client.Ui.StoryHud").init)
		local card = sim.playerGui and sim.playerGui:FindFirstChild("TitleCard", true)
			or sim.service("Players").LocalPlayer:FindFirstChild("TitleCard", true)
		check(card ~= nil, "the title card")
		local logo = card and card:FindFirstChild("Logo")
		check(logo ~= nil and logo.ClassName == "ImageLabel", "with the drawn logo")
		if logo then
			check(logo.Image == "rbxassetid://" .. Config.Ui.logo, "the uploaded logo")
			check(logo:FindFirstChildOfClass("UIScale") ~= nil, "it can slam in")
		end
		check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
	end)

	test("List combat: story break targets jolt on each hit and burst apart on the last", function()
		local roblox = require("@lune/roblox")
		check(
			string.find(
				fs.readFile("src/server/Services/SiteKit.luau"),
				'm:SetAttribute("Hp", math.max(0, h.hp / h.maxHp))',
				1,
				true
			) ~= nil,
			"the server sends what is left on every hit"
		)
		if not T.placePath then
			return
		end
		local UiSim = require("./uisim")
		local sim = UiSim.new(
			UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		)
		local StoryProps = sim:require("Client.Fx.StoryProps")
		check(StoryProps.ready("StoryCrate"), "the crate look is imported")
		local ws = sim.service("Workspace")
		local cam = ws.CurrentCamera
		if cam then
			cam.CFrame = roblox.CFrame.new(0, 10, 30)
		end
		local sites = UiSim.newInstance("Folder")
		sites.Name = "Sites"
		sites.Parent = ws
		local function crate(x: number, look: string)
			local m = UiSim.newInstance("Model")
			m.Name = "StoryCrate"
			m:SetAttribute("StoryLook", look)
			m:SetAttribute("Hp", 1)
			local root = UiSim.newInstance("Part")
			root.Name = "Root"
			root.Anchored = true
			root.Size = roblox.Vector3.new(1, 1, 1)
			root.CFrame = roblox.CFrame.new(x, 0, 0)
			root.Parent = m
			local box = UiSim.newInstance("Part")
			box.Name = "Box"
			box.Size = roblox.Vector3.new(5, 4, 5)
			box.CFrame = roblox.CFrame.new(x, 2, 0)
			box.Parent = m
			m.Parent = sites
			return m, box
		end
		local m, box = crate(0, "StoryCrate")
		sim:run("step", StoryProps.step)
		local art = ws:FindFirstChild("StoryArt")
		local meshes = if art then art:GetChildren() else {}
		check(#meshes > 0, "the crate is dressed")
		check(box.LocalTransparencyModifier == 1, "its plain box hidden")
		local function moved(): number
			local most = 0
			for _, p in meshes do
				local w = p:FindFirstChildOfClass("Weld")
				if w then
					most = math.max(most, w.C0.Position.Magnitude)
				end
			end
			return most
		end
		-- the sim jumps every tween to its end: count the springs back to rest instead
		local ts = sim.service("TweenService")
		local create = ts._props.Create
		local springs = 0
		ts._props.Create = function(self, inst, info, goals)
			if inst.ClassName == "Weld" and goals.C0 then
				springs += 1
			end
			return create(self, inst, info, goals)
		end
		local before = moved()
		sim:run("hit", function()
			m:SetAttribute("Hp", 0.5)
		end)
		check(springs == #meshes, string.format("a hit jolts every mesh and springs it back (%d)", springs))
		check(math.abs(moved() - before) < 1e-3, "back at rest")
		sim:run("break", function()
			m:SetAttribute("Hp", 0)
		end)
		local loose, welded = 0, 0
		for _, p in meshes do
			if p:FindFirstChildOfClass("Weld") then
				welded += 1
			elseif p.Anchored == false and p.AssemblyLinearVelocity.Magnitude > 5 then
				loose += 1
			end
		end
		check(
			welded == 0 and loose == #meshes,
			string.format("the last hit bursts it apart (%d loose)", loose)
		)
		sim:run("step", StoryProps.step)
		check(box.LocalTransparencyModifier == 1, "the broken crate's box stays hidden")
		-- a never-dressed broken target (plain parts) just goes too; the train stays whole
		local train, tbox = crate(4, "StoryTrain")
		sim:run("break", function()
			train:SetAttribute("Hp", 0)
		end)
		sim:run("step", StoryProps.step)
		local _, gone = crate(-4, "StoryCrate")
		gone.Parent:SetAttribute("Hp", 0)
		sim:run("step", StoryProps.step)
		check(gone.LocalTransparencyModifier == 1, "a broken plain crate goes")
		check(
			tbox.LocalTransparencyModifier == 1 and train.Parent ~= nil,
			"the beaten train is still drawn in its look"
		)
		check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
	end)

	test(
		"List combat: the prologue crowd and the intro film's people run on the heroes' sprint stride",
		function()
			local roblox = require("@lune/roblox")
			local HeroAnim = require("../src/shared/HeroAnim")
			check(HeroAnim.loops("runFast"), "the sprint stride loops")
			local pro = fs.readFile("src/client/Fx/PrologueFx.luau")
			local film = fs.readFile("src/client/Fx/IntroFilm.luau")
			check(
				string.find(pro, 'local RUN_CLIP = "runFast"', 1, true) ~= nil,
				"the prologue's runners use it"
			)
			check(
				string.find(film, 'HeroAnim.sample("runFast"', 1, true) ~= nil,
				"the intro film's runners use it"
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
			local rig
			sim:run("cast", function()
				rig = PrologueFx.cast("citizen", sim.workspace, 2)
			end)
			check(rig ~= nil, "a crowd citizen")
			-- every joint the stride moves is a joint of the crowd's rig, so none of the run is lost
			local a = HeroAnim.sample("runFast", 0.1)
			local n = 0
			for joint in a do
				n += 1
				check(rig and rig.motors[joint] ~= nil, "the rig has " .. joint)
			end
			check(n >= 10, "the stride moves arms, legs, waist and root (" .. n .. ")")
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
		end
	)

	test("List combat: incident and event objects jolt on each hit (ActivityProps)", function()
		local fx = fs.readFile("src/client/Fx/ActivityProps.luau")
		check(string.find(fx, 'm:GetAttributeChangedSignal("Hp")', 1, true) ~= nil, "listens to what is left")
		check(string.find(fx, "StoryProps.punch(rest, anchor.Position)", 1, true) ~= nil, "the shared punch")
		check(
			string.find(fs.readFile("src/client/Fx/StoryProps.luau"), "function StoryProps.punch(", 1, true)
				~= nil,
			"StoryProps shares it"
		)
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

	test(
		"List combat: the rooftop row's tanks, hatch, skylights and washing are meshes (Everything Left 268)",
		function()
			local roblox = require("@lune/roblox")
			local RA = Config.RoofArt
			check(RA ~= nil, "Config.RoofArt (generated by art/blender/rooftop.py)")
			local model = roblox.deserializeModel(fs.readFile("art/models/Roof.rbxm"))[1]
			local K = Config.City.kit
			for prop, pieces in RA do
				local def = K.props[prop]
				check(def ~= nil and def.server == true, prop .. " is a server kit prop")
				for piece in pieces do
					local mp = model:FindFirstChild(piece, true)
					check(mp ~= nil and mp:IsA("MeshPart"), piece .. " is imported")
					check(def ~= nil and def.pieces[piece] ~= nil, prop .. "." .. piece .. " has its colour")
				end
			end
			-- each mesh fits the box it stands for (ROW_DRESS sizes)
			local fit = {
				RoofTankStand = { 8, 2, 8 },
				RoofTank = { 7, 10, 7 },
				RoofHatch = { 4, 2.5, 4 },
				RoofSkylight = { 6, 1.2, 8 },
				LaundryPole = { 0.6, 7, 0.6 },
				LaundryShirt = { 2.4, 3, 0.2 },
				LaundrySheet = { 2.4, 3, 0.2 },
				LaundryTowel = { 2.4, 3, 0.2 },
			}
			for prop, box in fit do
				for piece, f in RA[prop] do
					for k = 1, 3 do
						check(
							f.size[k] <= box[k] + 0.35,
							prop .. "." .. piece .. " stays inside its box on axis " .. k
						)
					end
				end
			end
			local src = fs.readFile("src/shared/CityLayout.luau")
			for prop in fit do
				check(string.find(src, '"' .. prop .. '"', 1, true) ~= nil, "ROW_DRESS names " .. prop)
			end
			check(
				string.find(
					fs.readFile("src/server/Services/CityBuilder.luau"),
					'FindFirstChild("Roof")',
					1,
					true
				) ~= nil,
				"CityBuilder finds Art.Roof"
			)
		end
	)

	test("List combat: Gunslinger's shots fly a Blender bullet (Everything Left 173)", function()
		local roblox = require("@lune/roblox")
		local B = Config.PowerArt.Bullet
		check(B ~= nil and B.BulletSlug ~= nil and B.BulletStreak ~= nil, "the Bullet look")
		check(B.BulletStreak.tint == true, "the tracer takes the path colour")
		if not T.placePath then
			return
		end
		local UiSim = require("./uisim")
		local sim = UiSim.new(
			UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		)
		local CombatFx = sim:require("Client.Fx.CombatFx")
		sim:run("CombatFx", CombatFx.init)
		local color = roblox.Color3.fromRGB(255, 200, 80)
		sim:run("shot", function()
			CombatFx.bolt(
				roblox.Vector3.new(0, 5, 0),
				roblox.Vector3.new(0, 5, -60),
				"Comic",
				color,
				"Gunslinger"
			)
		end)
		local fx = sim.service("Workspace"):FindFirstChild("Fx")
		local slug, streak = 0, 0
		for _, d in fx:GetDescendants() do
			if d:IsA("MeshPart") and d.Name == "BulletSlug" then
				slug += 1
				check(d.Material == roblox.Enum.Material.Metal, "a copper slug")
			elseif d:IsA("MeshPart") and d.Name == "BulletStreak" then
				streak += 1
				check(d.Material == roblox.Enum.Material.Neon, "a glowing streak")
			end
		end
		check(
			slug >= 1 and streak >= 1,
			string.format("the bullet flies (%d slugs, %d streaks)", slug, streak)
		)
	end)

	test(
		"List combat: Sunfall, Singularity, Heavenfall, Ki Blast and the Fire and Light fields in Blender looks (Everything Left 169, 177, 180, 183)",
		function()
			local roblox = require("@lune/roblox")
			local P = Config.PowerArt
			for look, names in
				{
					Sun = { "SunCore", "SunCorona" },
					BlackHole = { "HoleDisc", "HoleRing" },
					KiRing = { "KiRingBand" },
					EmberRim = { "EmberFlames" },
					HaloRim = { "HaloBlades" },
				}
			do
				for _, name in names do
					check(P[look] ~= nil and P[look][name] ~= nil, look .. "." .. name .. " is in PowerArt")
				end
			end
			check(
				P.Sun.SunCorona.tint and P.BlackHole.HoleDisc.tint and P.KiRing.KiRingBand.tint,
				"they take the path colour"
			)
			if not T.placePath then
				return
			end
			local UiSim = require("./uisim")
			local sim = UiSim.new(
				UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
				{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
			)
			local CombatFx = sim:require("Client.Fx.CombatFx")
			sim:run("CombatFx", CombatFx.init)
			local A = Config.Abilities.list
			local V = roblox.Vector3.new
			local function data(): any
				return { o = V(0, 5, 0), d = V(0, 0, -1), e = V(0, 5, -40), c = V(0, 3, -20), r = 14, dur = 2 }
			end
			sim:run("Sunfall", function()
				CombatFx.superMoment(A.Sunfall, "Comic", data())
			end)
			sim:run("Singularity", function()
				CombatFx.superMoment(A.Singularity, "Anime", data())
			end)
			sim:run("Heavenfall", function()
				CombatFx.superMoment(A.HeavenfallBeam, "Comic", data())
			end)
			sim:run("Ki Blast", function()
				CombatFx.bolt(
					V(0, 5, 0),
					V(0, 5, -50),
					"Comic",
					roblox.Color3.fromRGB(255, 200, 80),
					"Martial"
				)
			end)
			sim:run("Ember Ring", function()
				CombatFx.cast(A.EmberRing, "Comic", data())
			end)
			sim:run("Halo Blades", function()
				CombatFx.cast(A.HaloBlades, "Comic", data())
			end)
			local rs = sim.service("RunService")
			for _ = 1, 10 do
				sim:run("frame", function()
					rs.RenderStepped:Fire(1 / 60)
				end)
				sim:advance(1 / 60)
			end
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
			local seen = {}
			for _, d in sim.service("Workspace"):GetDescendants() do
				if d:IsA("MeshPart") then
					seen[d.Name] = (seen[d.Name] or 0) + 1
				end
			end
			for _, name in
				{ "SunCore", "SunCorona", "HoleDisc", "HoleRing", "KiRingBand", "EmberFlames", "HaloBlades" }
			do
				check((seen[name] or 0) >= 1, name .. " is drawn (" .. tostring(seen[name]) .. ")")
			end
			check((seen.KiRingBand or 0) >= 3, "Heavenfall's rings and the Ki Blast's halo are ki rings")
			local src = fs.readFile("src/client/Fx/CombatFx.luau")
			for _, look in { "Sun", "BlackHole", "KiRing" } do
				check(
					string.find(src, 'PowerMeshes.ready("' .. look .. '")', 1, true) ~= nil,
					look .. " keeps its part build until imported"
				)
			end
			check(string.find(src, "PowerMeshes.ready(rimLook)", 1, true) ~= nil, "the rims too")
		end
	)

	test(
		"List combat: Static Field crackles with a ring of Blender lightning arcs (Everything Left 167)",
		function()
			local roblox = require("@lune/roblox")
			local m = Config.PowerArt.VoltRim and Config.PowerArt.VoltRim.StaticArcs
			check(m ~= nil and m.tint == true, "VoltRim.StaticArcs is in PowerArt and takes the path colour")
			if not T.placePath then
				return
			end
			local UiSim = require("./uisim")
			local sim = UiSim.new(
				UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
				{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
			)
			local CombatFx = sim:require("Client.Fx.CombatFx")
			sim:run("CombatFx", CombatFx.init)
			local V = roblox.Vector3.new
			sim:run("Static Field", function()
				CombatFx.cast(
					Config.Abilities.list.StaticField,
					"Comic",
					{ o = V(0, 5, 0), d = V(0, 0, -1), e = V(0, 5, -40), c = V(0, 3, -20), r = 14, dur = 2 }
				)
			end)
			local rs = sim.service("RunService")
			local yaws = {}
			local task = require("@lune/task")
			for _ = 1, 8 do
				task.wait(0.06) -- the crackle jumps on the device's clock
				sim:run("frame", function()
					rs.RenderStepped:Fire(1 / 60)
				end)
				sim:advance(1 / 60)
				for _, d in sim.service("Workspace"):GetDescendants() do
					if d:IsA("MeshPart") and d.Name == "StaticArcs" then
						local _, y = d.CFrame:ToEulerAnglesYXZ()
						yaws[string.format("%.3f", y)] = true
					end
				end
			end
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
			local arcs, n = nil, 0
			for _, d in sim.service("Workspace"):GetDescendants() do
				if d:IsA("MeshPart") and d.Name == "StaticArcs" then
					arcs = d
				end
			end
			for _ in yaws do
				n += 1
			end
			check(arcs ~= nil, "the arcs ring the field")
			check(arcs ~= nil and arcs.Material == roblox.Enum.Material.Neon, "glowing")
			check(
				arcs ~= nil and arcs.Size.X > 20,
				"out to the field's edge (" .. tostring(arcs and arcs.Size.X) .. ")"
			)
			check(n >= 2, "jumping as it crackles (" .. n .. " spots)")
		end
	)

	test("List combat: Storm's bolts are drawn lightning (Everything Left 167)", function()
		local roblox = require("@lune/roblox")
		local L = Config.Fx.lightning
		check(L ~= nil and #L.frames >= 2 and L.tile > 0 and L.flick > 0, "lightning frames are set")
		if not T.placePath then
			return
		end
		local UiSim = require("./uisim")
		local sim = UiSim.new(
			UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		)
		local CombatFx = sim:require("Client.Fx.CombatFx")
		sim:run("CombatFx", CombatFx.init)
		local V = roblox.Vector3.new
		local blue = roblox.Color3.fromRGB(120, 210, 255)
		sim:run("bolts", function()
			CombatFx.bolt(V(0, 5, 0), V(0, 5, -40), "Comic", blue, "Volt")
			CombatFx.chain({ V(0, 5, 0), V(10, 5, -10), V(20, 5, -5) }, "Comic", blue, "Volt")
			CombatFx.dash(V(0, 5, 0), V(0, 5, -30), "Comic", blue, "Volt")
		end)
		local ws = sim.service("Workspace")
		local function beams(): { any }
			local out = {}
			for _, d in ws:GetDescendants() do
				if d:IsA("Beam") and d.Name == "Lightning" then
					table.insert(out, d)
				end
			end
			return out
		end
		local list = beams()
		check(#list == 4, "a bolt, two chain links and the ride (" .. #list .. ")")
		local ok = true
		for _, b in list do
			local id = tonumber(string.match(b.Texture, "%d+$"))
			local known = false
			for _, f in L.frames do
				known = known or f == id
			end
			ok = ok and known and b.FaceCamera and b.Attachment0 ~= nil and b.Attachment1 ~= nil
		end
		check(ok, "each a camera-facing beam on a drawn frame between two points")
		local task = require("@lune/task")
		local rs = sim.service("RunService")
		local seen = {}
		for _ = 1, 4 do
			task.wait(L.flick + 0.01)
			sim:run("frame", function()
				rs.RenderStepped:Fire(1 / 60)
			end)
			for _, b in beams() do
				seen[b.Texture] = true
			end
		end
		local n = 0
		for _ in seen do
			n += 1
		end
		check(n >= 2, "the frames flick (" .. n .. ")")
		task.wait(0.5)
		sim:run("frame", function()
			rs.RenderStepped:Fire(1 / 60)
		end)
		check(#beams() == 0, "and they are gone once faded")
		local left = 0
		for _, d in ws:GetDescendants() do
			if d:IsA("Attachment") and (d.Name == "Lightning0" or d.Name == "Lightning1") then
				left += 1
			end
		end
		check(left == 0, "no attachments left behind (" .. left .. ")")
		check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
	end)

	test("List combat: bolts and held beams are drawn energy strips (Everything Left 381)", function()
		local roblox = require("@lune/roblox")
		local E = Config.Fx.energyBeam
		check(E ~= nil and E.texture > 0 and E.width > 0 and E.speed > 0, "the energy strip is set")
		if not T.placePath then
			return
		end
		local UiSim = require("./uisim")
		local sim = UiSim.new(
			UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		)
		local CombatFx = sim:require("Client.Fx.CombatFx")
		sim:run("CombatFx", CombatFx.init)
		local V = roblox.Vector3.new
		local orange = roblox.Color3.fromRGB(255, 140, 60)
		local target = V(0, 5, -30)
		sim:run("cast", function()
			CombatFx.bolt(V(0, 5, 0), V(0, 5, -40), "Comic", orange, "Fire")
			CombatFx.beamHold(function()
				return V(0, 5, 0)
			end, function()
				return target
			end, 0.4, "Comic", orange, "Fire")
		end)
		local ws = sim.service("Workspace")
		local function named(n: string): any
			for _, d in ws:GetDescendants() do
				if d:IsA("Beam") and d.Name == n then
					return d
				end
			end
			return nil
		end
		local bolt, held = named("EnergyBolt"), named("EnergyBeam")
		check(
			bolt ~= nil and string.find(bolt.Texture, tostring(E.texture), 1, true) ~= nil,
			"a bolt streaks"
		)
		check(
			held ~= nil and held.TextureSpeed > 0 and held.FaceCamera,
			"the held beam scrolls, facing the camera"
		)
		local rs = sim.service("RunService")
		target = V(10, 5, -30)
		sim:run("frame", function()
			rs.RenderStepped:Fire(1 / 60)
		end)
		local a1 = held and held.Attachment1
		check(a1 ~= nil and (a1.Position - target).Magnitude < 1e-3, "the beam follows its target")
		local task = require("@lune/task")
		task.wait(0.5)
		sim:run("frame", function()
			rs.RenderStepped:Fire(1 / 60)
		end)
		check(named("EnergyBolt") == nil and named("EnergyBeam") == nil, "both gone after")
		local left = 0
		for _, d in ws:GetDescendants() do
			if d:IsA("Attachment") and string.find(d.Name, "^Energy") then
				left += 1
			end
		end
		check(left == 0, "no attachments left (" .. left .. ")")
		check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
	end)

	test(
		"List combat: bolts throw Blender heads: ice crystals, fireballs, stones, kunai, globs (Everything Left 381)",
		function()
			local roblox = require("@lune/roblox")
			local H = Config.PowerArt.Heads
			for _, name in
				{ "HeadSpike", "HeadFlame", "HeadRock", "HeadKunai", "HeadDrop", "HeadLance", "HeadPsiRing" }
			do
				check(
					H ~= nil and H[name] ~= nil and H[name].tint == true,
					name .. " in PowerArt, in the path colour"
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
			local CombatFx = sim:require("Client.Fx.CombatFx")
			sim:run("CombatFx", CombatFx.init)
			local V = roblox.Vector3.new
			local want = {
				Frost = "HeadSpike",
				Fire = "HeadFlame",
				Earth = "HeadRock",
				Shadow = "HeadKunai",
				Tide = "HeadDrop",
				Light = "HeadLance",
				Mind = "HeadPsiRing",
			}
			for set, name in want do
				sim:run(set, function()
					CombatFx.bolt(
						V(0, 5, 0),
						V(0, 5, -40),
						"Comic",
						roblox.Color3.fromRGB(200, 120, 255),
						set
					)
				end)
				local found = nil
				for _, d in sim.service("Workspace"):GetDescendants() do
					if d:IsA("MeshPart") and d.Name == name then
						found = d
					end
				end
				check(found ~= nil, set .. " throws its " .. name)
				if found then
					-- nose first along the flight (-z): the mesh's long side lies along the bolt
					local look = found.CFrame.LookVector
					check(
						name == "HeadRock"
							or name == "HeadPsiRing"
							or found.Size.Z >= math.max(found.Size.X, found.Size.Y) - 1e-3,
						name .. " is longest along its flight"
					)
					check(
						math.abs(look.Y) < 0.2,
						name .. " flies level (" .. string.format("%.2f", look.Y) .. ")"
					)
					check(
						name == "HeadKunai"
							or name == "HeadLance"
							or found.Color == roblox.Color3.fromRGB(200, 120, 255),
						name .. " in the path colour (the kunai in its dark accent)"
					)
				end
			end
			-- the round glows stay balls (a puff grows, a ki orb's shell, the spirit fires)
			local src = fs.readFile("src/client/Fx/CombatFx.luau")
			check(
				string.find(src, "local outer = PIECE.glow(2.4 * s, color)", 1, true) ~= nil,
				"the ki orb stays round"
			)
			check(
				string.find(src, "* (headTwist[p] or CFrame.identity)", 1, true) ~= nil,
				"fly() keeps the import turn"
			)
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
		end
	)

	test("List combat: travelling lines ride Blender crescents and crystal spikes", function()
		local roblox = require("@lune/roblox")
		if not T.placePath then
			return
		end
		local UiSim = require("./uisim")
		local sim = UiSim.new(
			UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		)
		local CombatFx = sim:require("Client.Fx.CombatFx")
		sim:run("CombatFx", CombatFx.init)
		local V = roblox.Vector3.new
		local col = roblox.Color3.fromRGB(120, 200, 255)
		sim:run("lines", function()
			CombatFx.line(V(0, 3, 0), V(0, 3, -36), 4, "Comic", col, false, true, "Martial") -- Crescent Wave
			CombatFx.line(V(20, 3, 0), V(20, 3, -36), 4, "Comic", col, true, false, "Volt") -- Ground Spark
		end)
		local crescents, spikes, upright = 0, 0, true
		for _, d in sim.service("Workspace"):GetDescendants() do
			if d:IsA("MeshPart") and d.Name == "SlashCrescent" and d.CFrame.Position.X < 10 then
				crescents += 1
			elseif d:IsA("MeshPart") and d.Name == "HeadSpike" and d.CFrame.Position.X > 10 then
				spikes += 1
				-- nose up: the crystal's long (z) side stands vertical
				upright = upright and math.abs(d.CFrame.LookVector.Y) > 0.95
			end
		end
		check(crescents >= 3, "the blade line rides crescents (" .. crescents .. ")")
		check(spikes >= 3, "the ground line juts crystal spikes (" .. spikes .. ")")
		check(upright, "standing up")
		check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
	end)

	test("List combat: a Comic hit pops an inked hit star", function()
		local roblox = require("@lune/roblox")
		local L = Config.Fx.lib
		check(L.textures.hitstar ~= nil and L.textures.hitstar.id > 0, "the hit star is uploaded")
		check(fs.isFile("art/export/fx/hitstar.png"), "drawn by art/fx/hitstar.py")
		check(L.kinds.hitstar ~= nil and L.kinds.hitstar.light == 0, "unlit, so its ink rim stays black")
		if not T.placePath then
			return
		end
		local UiSim = require("./uisim")
		local sim = UiSim.new(
			UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		)
		local CombatFx = sim:require("Client.Fx.CombatFx")
		sim:run("CombatFx", CombatFx.init)
		sim:run("hit", function()
			CombatFx.impact(
				roblox.Vector3.new(0, 5, 0),
				false,
				"Comic",
				true,
				roblox.Color3.fromRGB(255, 200, 60),
				"Fire"
			)
		end)
		local star = nil
		for _, d in sim.service("Workspace"):GetDescendants() do
			if
				d:IsA("ParticleEmitter") and string.find(d.Texture, tostring(L.textures.hitstar.id), 1, true)
			then
				star = d
			end
		end
		check(star ~= nil, "the hit star's emitter is made")
		-- a weighty hit's spray: textured spark streaks from the particle budget (two part streaks on heavy hits)
		sim:run("sparks", function()
			CombatFx.hitSparks(roblox.Vector3.new(0, 5, 0), roblox.Vector3.new(0, 0, -1), nil, true)
		end)
		local sparks = nil
		for _, d in sim.service("Workspace"):GetDescendants() do
			if d:IsA("ParticleEmitter") and string.find(d.Parent.Name, "^hitspark:") then
				sparks = d
			end
		end
		check(sparks ~= nil, "the spark spray is particles")
		local src = fs.readFile("src/client/Fx/CombatFx.luau")
		check(
			string.find(src, 'FxLib.emit("hitstar", color:Lerp(WHITE, 0.35), center, 1', 1, true) ~= nil,
			"a Comic nova pops a big hit star too"
		)
		check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
	end)

	test("List combat: Girder Swing swings the Blender girder (Everything Left 178)", function()
		local roblox = require("@lune/roblox")
		if not T.placePath then
			return
		end
		local UiSim = require("./uisim")
		local sim = UiSim.new(
			UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		)
		local CombatFx = sim:require("Client.Fx.CombatFx")
		sim:run("CombatFx", CombatFx.init)
		local char = UiSim.newInstance("Model")
		local rh = UiSim.newInstance("Part")
		rh.Name = "RightHand"
		rh.Size = roblox.Vector3.new(1, 0.3, 1)
		rh.CFrame = roblox.CFrame.new(3, 4, 0)
		rh.Parent = char
		char.Parent = sim.service("Workspace")
		local me = sim.service("Players").LocalPlayer
		me.Character = char
		local hand = char:FindFirstChild("RightHand")
		check(hand ~= nil, "the test body has a right hand")
		sim:run("girder", function()
			CombatFx.heldGirder(me.UserId)
		end)
		local held = nil
		for _, d in sim.service("Workspace"):GetDescendants() do
			if d.Name == "HeldGirder" then
				held = d
			end
		end
		check(held ~= nil, "the girder is drawn")
		if held and hand then
			local beam = held:FindFirstChild("GirderBeam")
			check(beam ~= nil and beam:IsA("MeshPart"), "as the Blender beam")
			check(held:FindFirstChild("GirderRivets") ~= nil, "with its rivets and grip plate")
			for _, b in held:GetChildren() do
				local w = b:FindFirstChildWhichIsA("WeldConstraint")
				check(
					w ~= nil and w.Part0 == hand and b.Anchored == false,
					b.Name .. " is welded to the hand"
				)
			end
			if beam then
				-- it hangs below the hand, about 5 studs down to its middle
				local rel = hand.CFrame:PointToObjectSpace(beam.CFrame.Position)
				check(rel.Y < -4 and rel.Y > -6, string.format("the beam hangs from the hand (%.2f)", rel.Y))
			end
		end
		check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
	end)

	test("List combat: crater rims are broken Blender blocks (Art.Rubble chunks)", function()
		local roblox = require("@lune/roblox")
		if not T.placePath then
			return
		end
		check(Config.Destruction.ground.on == true, "ground craters are on")
		local UiSim = require("./uisim")
		local sim = UiSim.new(
			UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		)
		local GroundFx = sim:require("Client.Fx.GroundFx")
		sim:run("GroundFx", GroundFx.init)
		local remotes = sim.service("ReplicatedStorage"):WaitForChild("Remotes")
		sim:run("crater", function()
			remotes:WaitForChild("CraterAdd").OnClientEvent:Fire({ 5, 4, 0, -6, 7, 0, 0 })
		end)
		require("@lune/task").wait(0.3)
		sim:run("frame", function()
			sim.service("RunService").Heartbeat:Fire(1 / 60)
		end)
		local crater = sim.service("Workspace"):FindFirstChild("GroundCrater_5", true)
		check(crater ~= nil, "the crater is drawn")
		local meshes, plain = 0, 0
		for _, d in (if crater then crater:GetChildren() else {}) do
			if d:IsA("MeshPart") and string.match(d.Name, "^Chunk%d$") then
				meshes += 1
				check(d.CanCollide == false and d.CanQuery == false and d.Anchored, d.Name .. " is look only")
			elseif d:IsA("Part") and d.Shape == roblox.Enum.PartType.Block and d.Transparency == 0 then
				plain += 1
			end
		end
		check(meshes >= 4, "the rim is broken blocks (" .. meshes .. ")")
		check(plain == 0, "no plain block chunks left (" .. plain .. ")")
		check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
	end)

	test("List combat: Shadow Clones and decoys are see-through copies of your own hero", function()
		local roblox = require("@lune/roblox")
		if not T.placePath then
			return
		end
		local UiSim = require("./uisim")
		local sim = UiSim.new(
			UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		)
		local CombatFx = sim:require("Client.Fx.CombatFx")
		sim:run("CombatFx", CombatFx.init)
		local V = roblox.Vector3.new
		-- a hero facing +x (turned 90 degrees), with a hat mesh on top
		local face = roblox.CFrame.new(10, 3, 0) * roblox.CFrame.Angles(0, -math.pi / 2, 0)
		local char = UiSim.newInstance("Model")
		local function add(class, name, size, cf, color)
			local p = UiSim.newInstance(class)
			p.Name = name
			p.Size = size
			p.CFrame = cf
			p.Color = color
			p.Parent = char
			return p
		end
		add("Part", "HumanoidRootPart", V(2, 2, 1), face, roblox.Color3.new(1, 1, 1)).Transparency = 1
		add(
			"Part",
			"UpperTorso",
			V(2, 1.6, 1),
			face * roblox.CFrame.new(0, 0.6, 0),
			roblox.Color3.fromRGB(200, 40, 40)
		)
		add(
			"MeshPart",
			"GhostHat",
			V(1.4, 0.8, 1.4),
			face * roblox.CFrame.new(0, 2.6, 0),
			roblox.Color3.new(0, 0, 0)
		)
		char.Parent = sim.service("Workspace")
		local me = sim.service("Players").LocalPlayer
		me.Character = char
		local col = roblox.Color3.fromRGB(90, 60, 200)
		sim:run("clones", function()
			CombatFx.summon("clones", function()
				return V(10, 3, 0)
			end, 3, "Comic", col, nil, me.UserId)
		end)
		sim:run("frame", function()
			sim.service("RunService").RenderStepped:Fire(1 / 60)
		end)
		local hats, torsos, roots = {}, 0, 0
		for _, d in sim.service("Workspace"):GetDescendants() do
			if d:IsDescendantOf(char) then
				continue
			end
			if d.Name == "GhostHat" then
				table.insert(hats, d)
			elseif d.Name == "UpperTorso" then
				torsos += 1
			elseif d.Name == "HumanoidRootPart" then
				roots += 1
			end
		end
		check(
			#hats == 2 and torsos == 2,
			"two copies of the hero, gear and all (" .. #hats .. ", " .. torsos .. ")"
		)
		check(roots == 0, "the invisible root is not copied")
		for _, h in hats do
			check(h.Material == roblox.Enum.Material.Neon and h.Transparency > 0.3, "glowing and see-through")
			check(h.Anchored and not h.CanCollide and not h.CanQuery, "look only")
			-- left and right of the hero in the hero's own facing (+x forward: the sides are along z)
			local rel = face:PointToObjectSpace(h.CFrame.Position)
			check(math.abs(math.abs(rel.X) - 4) < 0.05, string.format("beside the hero (%.2f)", rel.X))
			check(math.abs(rel.Y - 2.6) < 0.05, "the hat on the copy's head")
		end
		-- no character here (a bot): the old stand-in figure
		sim:run("bot clones", function()
			CombatFx.summon("clones", function()
				return V(40, 3, 0)
			end, 3, "Comic", col, nil, 999)
		end)
		check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
		local src = fs.readFile("src/client/Fx/CombatFx.luau")
		check(
			string.find(src, "data.dur or row.duration, style, color, data.r or row.radius, data.a)", 1, true)
				~= nil,
			"the cast passes the caster"
		)
		check(
			string.find(
				fs.readFile("src/client/Controllers/CombatClient.luau"),
				"r.dur or row.decoy, style, color, nil, r.a)",
				1,
				true
			) ~= nil,
			"decoys pass the caster"
		)
	end)

	test(
		"List combat: the prologue tunnel's roof chunks and pinning beam and the run's barrier wear Blender meshes",
		function()
			local roblox = require("@lune/roblox")
			if not T.placePath then
				return
			end
			local UiSim = require("./uisim")
			local sim = UiSim.new(
				UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
				{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
			)
			local PrologueFx = sim:require("Client.Fx.PrologueFx")
			local char = UiSim.newInstance("Model")
			local hrp = UiSim.newInstance("Part")
			hrp.Name = "HumanoidRootPart"
			hrp.Size = roblox.Vector3.new(2, 2, 1)
			hrp.CFrame = roblox.CFrame.new(0, 3, 0)
			hrp.Parent = char
			char.Parent = sim.service("Workspace")
			sim.service("Players").LocalPlayer.Character = char
			sim:run("beam", function()
				PrologueFx.moment("beam", { at = { 0, 0, 0 } }, "show")
			end)
			sim:run("slab", function()
				PrologueFx.moment("slab", { at = { 6, 0, 2 } }, "hit")
			end)
			sim:run("barrier", function()
				PrologueFx.moment(
					"barrier",
					{ at = { 30, 0, 0 }, from = { 30, 0, 10 }, to = { 30, 0, -10 } },
					"show"
				)
			end)
			local folder = sim.service("Workspace"):FindFirstChild("Prologue")
			check(folder ~= nil, "the prologue's folder")
			local beam, rivets, chunk = nil, nil, nil
			for _, d in (if folder then folder:GetDescendants() else {}) do
				if d.Name == "GirderBeam" then
					beam = d
				elseif d.Name == "GirderRivets" then
					rivets = d
				elseif d:IsA("MeshPart") and string.match(d.Name, "^Chunk%d$") then
					chunk = d
				end
			end
			check(beam ~= nil and rivets ~= nil, "the beam is the Blender girder")
			if beam then
				local host = beam.Parent
				check(host:IsA("BasePart") and host.Transparency == 1, "over its hidden part")
				-- lying across the shoulders: the girder's length (its y) runs along the part's x, about 14 long
				check(math.abs(beam.Size.Y - 14) < 1.5, string.format("14 studs long (%.2f)", beam.Size.Y))
				check(
					math.abs(beam.CFrame.UpVector:Dot(host.CFrame.RightVector)) > 0.95,
					"its length runs along the beam part"
				)
				local w = beam:FindFirstChildWhichIsA("WeldConstraint")
				check(w ~= nil and w.Part0 == host and not beam.Anchored, "welded so it falls with the part")
			end
			-- the run's barrier: the sawhorse barricade standing on its feet, over its hidden part
			local bar = {}
			for _, d in (if folder then folder:GetDescendants() else {}) do
				if d:IsA("MeshPart") and string.sub(d.Name, 1, 7) == "Barrier" then
					bar[d.Name] = d
				end
			end
			for _, name in { "Barrier", "BarrierStripes", "BarrierLegs", "BarrierLamp" } do
				check(bar[name] ~= nil, "the barrier's " .. name)
			end
			if bar.Barrier and bar.BarrierLegs then
				check(bar.Barrier.Parent.Transparency == 1, "over its hidden part")
				local legs = bar.BarrierLegs
				local low = legs.CFrame.Position.Y - legs.Size.Y / 2
				check(math.abs(low) < 0.4, string.format("standing on its feet (%.2f)", low))
				check(math.abs(bar.Barrier.CFrame.Position.X - 30) < 1, "where the beat puts it")
			end
			check(chunk ~= nil, "the falling roof chunk is a broken block")
			if chunk then
				check(
					chunk.Parent.Transparency == 1 and math.abs(chunk.Size.X - 5) < 1e-3,
					"stretched over its part"
				)
			end
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
		end
	)

	test(
		"List combat: a robot shot that meets a wall stops there in sparks and a scorch, the muzzle flashes",
		function()
			local roblox = require("@lune/roblox")
			local sp = Config.Fx.shot.splash
			check(
				sp and sp.sparks > 0 and sp.tracerSparks >= sp.sparks and sp.scorch > 0,
				"the splash is tuned"
			)
			if not T.placePath then
				return
			end
			local UiSim = require("./uisim")
			local sim = UiSim.new(
				UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
				{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
			)
			local FxLib = sim:require("Client.Fx.FxLib")
			local CombatFx = sim:require("Client.Fx.CombatFx")
			sim:run("CombatFx", CombatFx.init)
			local V = roblox.Vector3.new
			local emits: { [string]: number } = {}
			local real = FxLib.emit
			FxLib.emit = function(kind: string, ...)
				emits[kind] = (emits[kind] or 0) + 1
				return real(kind, ...)
			end
			-- a wall 30 studs ahead of the pellet
			local ws = sim.service("Workspace")
			local wall = UiSim.newInstance("Part")
			ws._props.Raycast = function(_, origin, dir)
				if dir.Z < 0 and origin.Z - 30 >= origin.Z + dir.Z then
					return {
						Position = V(origin.X, origin.Y, origin.Z - 30),
						Normal = V(0, 0, 1),
						Instance = wall,
						Distance = 30,
					}
				end
				return nil
			end
			sim:run("pellet", function()
				CombatFx.enemyShot(V(0, 5, 0), V(0, 0, -60), nil)
			end)
			check((emits.glow or 0) >= 1 and (emits.spark or 0) >= 1, "the muzzle flashes")
			check((emits.hitspark or 0) == 0, "nothing on the wall before the shot gets there")
			sim:advance(0.6)
			check(
				(emits.hitspark or 0) == 1 and (emits.scorch or 0) == 1,
				"sparks and a scorch where it hit, at 0.5 s"
			)
			-- the Sniper's round too
			sim:run("sniper", function()
				CombatFx.enemyShot(V(10, 5, 0), V(0, 0, -200), 1)
			end)
			sim:advance(0.3)
			check(
				(emits.hitspark or 0) == 2 and (emits.scorch or 0) == 2,
				"a Sniper round sparks on the wall too"
			)
			-- a famous fake's path shot splashes in its own colour
			sim:run("fake", function()
				CombatFx.pathShot(
					V(20, 5, 0),
					V(0, 0, -60),
					"Light",
					"Comic",
					roblox.Color3.fromRGB(255, 230, 120)
				)
			end)
			sim:advance(0.6)
			check(
				(emits.hitspark or 0) == 3 and (emits.scorch or 0) == 3,
				"a path shot stops on the wall too"
			)
			-- an Interceptor's net pins on the wall, holds, then goes
			check((Config.Fx.shot.splash.netHold or 0) > 0, "the net's hold is tuned")
			sim:run("net", function()
				CombatFx.enemyShot(V(30, 5, 0), V(0, 0, -60), 2)
			end)
			sim:advance(0.6)
			check(
				(emits.hitspark or 0) == 4 and (emits.scorch or 0) == 4,
				"a net sparks where it hits the wall"
			)
			check(
				string.find(fs.readFile("src/client/Fx/CombatFx.luau"), "life + pinned", 1, true) ~= nil,
				"the net holds on the wall before it goes"
			)
			-- in the open: no splash
			ws._props.Raycast = function()
				return nil
			end
			sim:run("open", function()
				CombatFx.enemyShot(V(0, 5, 0), V(0, 0, -60), nil)
			end)
			sim:advance(2)
			check((emits.scorch or 0) == 4, "a shot into the open fades as before")
			FxLib.emit = real
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
		end
	)
	test(
		"List combat: Shadow's Eclipse is the Blender sun gone dark, Siege Mode drives Blender anchors",
		function()
			local roblox = require("@lune/roblox")
			local E = Config.Fx.eclipse
			check(E and E.corona > E.core and E.core > 0, "the eclipse is tuned")
			if not T.placePath then
				return
			end
			local UiSim = require("./uisim")
			local sim = UiSim.new(
				UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
				{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
			)
			local CombatFx = sim:require("Client.Fx.CombatFx")
			sim:run("CombatFx", CombatFx.init)
			local V = roblox.Vector3.new
			sim:run("Eclipse", function()
				CombatFx.superMoment(
					Config.Abilities.list.Eclipse,
					"Comic",
					{ o = V(0, 5, 0), d = V(0, 0, -1), c = V(0, 3, -20), r = 14 } :: any
				)
			end)
			local core, corona, discs = nil, nil, 0
			for _, d in sim.service("Workspace"):GetDescendants() do
				if d:IsA("MeshPart") and d.Name == "SunCore" then
					core = d
				elseif d:IsA("MeshPart") and d.Name == "SunCorona" then
					corona = d
				elseif d:IsA("Part") and d.Shape == roblox.Enum.PartType.Cylinder and d.Position.Y > 20 then
					discs += 1
				end
			end
			check(core ~= nil and corona ~= nil, "the core and corona are drawn")
			if core and corona then
				check(
					core.Material == roblox.Enum.Material.SmoothPlastic,
					"the core is a flat black, not a glow"
				)
				local accent = Config.Fx.paths.Shadow.accent
				check(
					math.abs(core.Color.R * 255 - accent[1]) < 1
						and math.abs(core.Color.B * 255 - accent[3]) < 1,
					"in Shadow's dark accent"
				)
				check(corona.CFrame.Position.Y > 20, "high over the zone")
			end
			check(discs == 0, "no flat neon disc rim")
			-- Juggernaut's Siege Mode: four Blender anchors driven point first round the hero, each a stake, a housing
			-- and a glowing band, slamming down
			sim:run("Siege", function()
				CombatFx.superMoment(
					Config.Abilities.list.SiegeMode,
					"Comic",
					{ o = V(100, 5, 0), d = V(0, 0, -1), r = 14 } :: any
				)
			end)
			local stakes, housings, bands, highest = 0, 0, 0, -math.huge
			for _, d in sim.service("Workspace"):GetDescendants() do
				if d:IsA("MeshPart") and d.Name == "SiegeStake" then
					stakes += 1
					highest = math.max(highest, d.CFrame.Position.Y)
				elseif d:IsA("MeshPart") and d.Name == "SiegeHousing" then
					housings += 1
				elseif d:IsA("MeshPart") and d.Name == "SiegeBand" then
					bands += 1
				end
			end
			check(
				stakes == 4 and housings == 4 and bands == 4,
				"four anchors (" .. stakes .. ", " .. housings .. ", " .. bands .. ")"
			)
			check(
				highest > 0 and highest < 6,
				"they slam down into the ground round the hero (" .. highest .. ")"
			)
			local boxes = 0
			for _, d in sim.service("Workspace"):GetDescendants() do
				if
					d:IsA("Part")
					and d.Material == roblox.Enum.Material.Metal
					and math.abs(d.Size.Y - 6) < 0.01
				then
					boxes += 1
				end
			end
			check(boxes == 0, "no plain anchor boxes")
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
		end
	)
	test(
		"List combat: the supers' own Blender looks: Psychic Storm's sigil, Dawnburst's sunrise, the light helix, Meteor Leap's crater",
		function()
			local roblox = require("@lune/roblox")
			local S = Config.Fx.supers
			check(
				S and S.helix > 1 and S.dawn > 0 and S.crater > 0 and S.craterHold > 0,
				"the supers' looks are tuned"
			)
			if not T.placePath then
				return
			end
			local UiSim = require("./uisim")
			local sim = UiSim.new(
				UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
				{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
			)
			local CombatFx = sim:require("Client.Fx.CombatFx")
			sim:run("CombatFx", CombatFx.init)
			local V = roblox.Vector3.new
			local A = Config.Abilities.list
			local function data(): any
				return { o = V(0, 5, 0), d = V(0, 0, -1), e = V(0, 5, -40), c = V(0, 3, -20), r = 14 }
			end
			local function count(): { [string]: number }
				local seen = {}
				for _, d in sim.service("Workspace"):GetDescendants() do
					if d:IsA("MeshPart") then
						seen[d.Name] = (seen[d.Name] or 0) + 1
					end
				end
				return seen
			end
			sim:run("Psychic Storm", function()
				CombatFx.superMoment(A.PsychicStorm, "Comic", data())
			end)
			sim:run("Dawnburst", function()
				CombatFx.superMoment(A.Dawnburst, "Anime", data())
			end)
			sim:run("Meteor Leap", function()
				CombatFx.superMoment(A.MeteorLeap, "Comic", data(), true)
			end)
			local seen = count()
			for _, name in
				{
					"SigilOuter",
					"SigilInner",
					"DawnBurst",
					"DawnCrown",
					"PillarHelix",
					"CraterBowl",
					"CraterRim",
				}
			do
				check((seen[name] or 0) >= 1, name .. " is drawn (" .. tostring(seen[name]) .. ")")
			end
			for _ = 1, 10 do
				sim:run("frame", function()
					sim.service("RunService").RenderStepped:Fire(1 / 30)
				end)
			end
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
		end
	)
	test(
		"List combat: taking a hit sparks off the hero, a red arrow points at the robot, a thud and a shake",
		function()
			local roblox = require("@lune/roblox")
			local H = Config.Fx.hurt
			check(H and H.heavy > 0 and H.arrow.pool >= 1 and H.arrow.life > 0, "the hurt feedback is tuned")
			local enemy = fs.readFile("src/server/Services/EnemyService.luau")
			check(
				string.find(enemy, "table.insert(row, if ev.melee then 1 else 0)", 1, true) ~= nil,
				"the server sends the robot's spot and the melee bit with each hero hit"
			)
			if not T.placePath then
				return
			end
			local UiSim = require("./uisim")
			local sim = UiSim.new(
				UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
				{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
			)
			local cam = sim.service("Workspace").CurrentCamera
			cam.CFrame = roblox.CFrame.new(0, 5, 10) -- looking down -Z
			local char = UiSim.newInstance("Model")
			local root = UiSim.newInstance("Part")
			root.Name = "HumanoidRootPart"
			root.CFrame = roblox.CFrame.new(0, 3, 0)
			root.Position = roblox.Vector3.new(0, 3, 0)
			root.Parent = char
			char.Parent = sim.workspace
			sim.player.Character = char
			local FxLib = sim:require("Client.Fx.FxLib")
			local CombatFx = sim:require("Client.Fx.CombatFx")
			sim:run("CombatFx", CombatFx.init)
			local Combat = sim:require("Client.Controllers.CombatClient")
			sim:run("CombatClient", Combat.init)
			local SimConfig = sim:require("Config")
			local Audio = sim:require("Client.Controllers.AudioController")
			local Camera = sim:require("Client.Controllers.CameraController")
			local sparks, sounds, shakes = 0, {}, {}
			local realEmit, realPlay, realShake = FxLib.emit, Audio.playSpec, Camera.shake
			FxLib.emit = function(kind: string, ...)
				if kind == "hitspark" then
					sparks += 1
				end
				return realEmit(kind, ...)
			end
			Audio.playSpec = function(spec, ...)
				table.insert(sounds, spec)
				return realPlay(spec, ...)
			end
			Camera.shake = function(t, a)
				table.insert(shakes, a)
				return realShake(t, a)
			end
			local gui = sim.player:WaitForChild("PlayerGui")
			local function arrow(i: number): any
				return gui:FindFirstChild("HurtArrow" .. i, true)
			end
			check(arrow(1) ~= nil, "the hurt arrows are made")
			local remotes = sim.service("ReplicatedStorage"):WaitForChild("Remotes")
			local function hit(dmg: number, rx: number, rz: number, melee: number)
				sim:run("hero hit", function()
					remotes:WaitForChild("CombatEvents").OnClientEvent:Fire({
						{ 2, sim.player.UserId, 0, 3, 0, dmg, rx, 3, rz, melee },
					})
				end)
			end
			-- a pellet from a robot on the right
			hit(5, 40, 10, 0)
			check(sparks == 1, "sparks off the hero's chest (" .. sparks .. ")")
			local a1 = arrow(1)
			check(
				a1 and math.abs(a1.Rotation - 90) < 1,
				"the arrow points right (" .. tostring(a1 and a1.Rotation) .. ")"
			)
			check(#sounds == 1 and sounds[1] == SimConfig.Audio.impact.hit, "a thud")
			check(#shakes >= 1 and shakes[#shakes] == H.shake[2], "a light shake")
			-- a punch from behind a moment later: heavy
			require("@lune/task").wait(0.1) -- the thud's gap runs on the real clock
			hit(4, 0, 40, 1)
			local a2 = arrow(2)
			check(a2 and math.abs(math.abs(a2.Rotation) - 180) < 1, "the second arrow points behind")
			check(a1 and a2 and a2.Bar.Size.X.Scale > a1.Bar.Size.X.Scale, "a heavy hit's arrow is wider")
			check(sounds[#sounds] == SimConfig.Audio.impact.heavy, "a heavy thud on a melee blow")
			check(shakes[#shakes] == H.shakeHeavy[2], "a harder shake")
			-- a big hit on another hero nearby: sparks only
			local n = #sounds
			sim:run("other", function()
				remotes
					:WaitForChild("CombatEvents").OnClientEvent
					:Fire({ { 2, 999, 20, 3, 0, 60, 30, 3, 0, 0 } })
			end)
			check(sparks == 3 and #sounds == n, "another hero's hit sparks, with no thud for you")
			-- an old event with no robot spot still works
			require("@lune/task").wait(0.1) -- the thud's gap runs on the real clock
			hit(5, nil :: any, nil :: any, nil :: any)
			check(#sounds == n + 1, "a hit with no robot spot still thuds")
			-- a hit your shield or parry took (0 damage): sparks glance off and it clanks, no hurt shake
			local sp0, sh0 = sparks, #shakes
			hit(0, 40, 10, 0)
			check(sparks == sp0 + 1, "a blocked hit sparks")
			check(sounds[#sounds] == SimConfig.Audio.impact.clank, "and clanks")
			check(#shakes == sh0, "with no hurt shake")
			-- a robot's punch (SWING) near you: a hot streak, a fist flash and a whoosh; far off, nothing
			local Enemy = sim:require("Client.Controllers.EnemyRenderer")
			local realFacing = Enemy.facing
			Enemy.facing = function()
				return roblox.Vector3.new(0, 0, -1)
			end
			local function parts(): number
				local c = 0
				for _, d in sim.service("Workspace"):GetDescendants() do
					if d:IsA("BasePart") then
						c += 1
					end
				end
				return c
			end
			local p0, s0 = parts(), #sounds
			sim:run("swing", function()
				remotes:WaitForChild("CombatEvents").OnClientEvent:Fire({ { 6, 41, 4, 3, 0 } })
			end)
			check(parts() > p0 + 3, "a robot's punch draws its streak and flash (" .. (parts() - p0) .. ")")
			check(#sounds == s0 + 1 and sounds[#sounds] == SimConfig.Audio.impact.whoosh, "and whooshes")
			p0, s0 = parts(), #sounds
			sim:run("far swing", function()
				remotes:WaitForChild("CombatEvents").OnClientEvent:Fire({ { 6, 42, 4000, 3, 0 } })
			end)
			check(parts() == p0 and #sounds == s0, "a punch far away draws nothing")
			Enemy.facing = realFacing
			-- a Sniper locks onto a hero near you: the lock pings from them, quieter and lower; far off, silent
			local Aim = SimConfig.Fx.robots.aim.ally
			local allyChar = UiSim.newInstance("Model")
			local allyRoot = UiSim.newInstance("Part")
			allyRoot.Name = "HumanoidRootPart"
			allyRoot.CFrame = roblox.CFrame.new(20, 3, 0)
			allyRoot.Position = roblox.Vector3.new(20, 3, 0)
			allyRoot.Parent = allyChar
			allyChar.Parent = sim.workspace
			local ally = { Character = allyChar, UserId = 555 }
			local players = sim.service("Players")
			local realGet = players._props.GetPlayerByUserId
			players._props.GetPlayerByUserId = function(_, id)
				return if id == 555 then ally else realGet(_, id)
			end
			local opts: any = nil
			local realAudioPlay = Audio.play
			Audio.play = function(id, at, o)
				if id == "aimLock" then
					opts = { at = at, o = o }
				end
				return realAudioPlay(id, at, o)
			end
			sim:run("aim", function()
				remotes
					:WaitForChild("CombatEvents").OnClientEvent
					:Fire({ { 8, 43, 60, 3, 0, 555, 0.25, 0.1 } })
			end)
			check(opts == nil, "no ping before the lock")
			sim:advance(0.2)
			check(opts ~= nil and opts.o and opts.o.volume == Aim.volume, "a quieter lock ping for the ally")
			check(opts and (opts.at - roblox.Vector3.new(20, 4.5, 0)).Magnitude < 0.01, "from the ally")
			opts = nil
			allyRoot.Position = roblox.Vector3.new(2000, 3, 0)
			sim:run("far aim", function()
				remotes
					:WaitForChild("CombatEvents").OnClientEvent
					:Fire({ { 8, 44, 1960, 3, 0, 555, 0.25, 0.1 } })
			end)
			sim:advance(0.2)
			check(opts == nil, "a lock on a far hero stays silent")
			Audio.play = realAudioPlay
			players._props.GetPlayerByUserId = realGet
			FxLib.emit, Audio.playSpec, Camera.shake = realEmit, realPlay, realShake
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
		end
	)
	test(
		"List combat: a Grappler's claw bites a hero with sparks, a clank and a taut cable, and sparks on a wall",
		function()
			local roblox = require("@lune/roblox")
			local hk = Config.Fx.robots.hook
			check(hk.biteSparks > 0 and hk.wallSparks > 0 and hk.taut > 1, "the bite is tuned")
			if not T.placePath then
				return
			end
			local UiSim = require("./uisim")
			local sim = UiSim.new(
				UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
				{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
			)
			local V = roblox.Vector3.new
			local char = UiSim.newInstance("Model")
			local root = UiSim.newInstance("Part")
			root.Name = "HumanoidRootPart"
			root.CFrame = roblox.CFrame.new(0, 5, 60)
			root.Position = V(0, 5, 60)
			root.Parent = char
			char.Parent = sim.workspace
			sim.player.Character = char
			local FxLib = sim:require("Client.Fx.FxLib")
			local CombatFx = sim:require("Client.Fx.CombatFx")
			sim:run("CombatFx", CombatFx.init)
			local emits: { [string]: number } = {}
			local real = FxLib.emit
			FxLib.emit = function(kind: string, ...)
				emits[kind] = (emits[kind] or 0) + 1
				return real(kind, ...)
			end
			local bites = {}
			local function frames(n: number)
				for _ = 1, n do
					sim:run("frame", function()
						sim.service("RunService").RenderStepped:Fire(1 / 30)
					end)
				end
			end
			local function cable(): any
				local best = nil
				for _, d in sim.service("Workspace"):GetDescendants() do
					if d:IsA("BasePart") and d.Material == roblox.Enum.Material.Metal and d.Size.Z > 3 then
						best = d
					end
				end
				return best
			end
			-- a claw shot at you from 20 studs
			sim:run("hook", function()
				CombatFx.hook(
					function()
						return V(0, 5, 80)
					end,
					V(0, 5, 80),
					V(0, 0, -60),
					function()
						return true
					end,
					function(what, at, who)
						table.insert(bites, { what, at, who })
					end
				)
			end)
			frames(12)
			check(#bites == 1 and bites[1][1] == "hero" and bites[1][3] == sim.player, "it bites you, once")
			check((emits.hitspark or 0) == 1, "sparks where it bites")
			local c = cable()
			check(c ~= nil and math.abs(c.Size.X - hk.cable * hk.taut) < 1e-3, "the cable goes taut")
			-- a claw into a wall 15 studs off
			root.Position = V(500, 5, 0)
			root.CFrame = roblox.CFrame.new(500, 5, 0)
			sim.service("Workspace")._props.Raycast = function(_, origin, dir)
				if origin.X < -5 and dir.Z < 0 and origin.Z + dir.Z <= 65 then
					return {
						Position = V(origin.X, origin.Y, 65),
						Normal = V(0, 0, 1),
						Instance = root,
						Distance = 1,
					}
				end
				return nil
			end
			sim:run("hook 2", function()
				CombatFx.hook(
					function()
						return V(-10, 5, 80)
					end,
					V(-10, 5, 80),
					V(0, 0, -60),
					function()
						return true
					end,
					function(what, at, who)
						table.insert(bites, { what, at, who })
					end
				)
			end)
			frames(12)
			check(#bites == 2 and bites[2][1] == "wall" and bites[2][3] == nil, "it bites the wall")
			check((emits.hitspark or 0) == 2 and (emits.scorch or 0) == 1, "sparks and a scorch on the wall")
			local client = fs.readFile("src/client/Controllers/CombatClient.luau")
			check(
				string.find(client, 'if what == "hero" then IMPACT.heavy else IMPACT.clank', 1, true) ~= nil,
				"the client clanks each bite"
			)
			FxLib.emit = real
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
		end
	)
	test(
		"List combat: robot shots leave a glowing streak you can see coming, Medics a flowing beam, burning patches a flame ring, nets and claws Blender meshes",
		function()
			local roblox = require("@lune/roblox")
			check(Config.Fx.shot.trail > 0 and Config.Fx.shot.life > 0, "the streak is tuned")
			if not T.placePath then
				return
			end
			local UiSim = require("./uisim")
			local sim = UiSim.new(
				UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
				{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
			)
			local CombatFx = sim:require("Client.Fx.CombatFx")
			sim:run("CombatFx", CombatFx.init)
			local V = roblox.Vector3.new
			local function trails()
				local n, textured = 0, true
				for _, d in sim.service("Workspace"):GetDescendants() do
					if d:IsA("Trail") and d.Name == "ShotTrail" then
						n += 1
						textured = textured
							and d.Texture == "rbxassetid://" .. Config.Fx.energyBeam.texture
							and d.FaceCamera
							and d.Attachment0 ~= nil
							and d.Attachment1 ~= nil
							and d.Attachment0.Parent == d.Parent
					end
				end
				return n, textured
			end
			sim:run("pellet", function()
				CombatFx.enemyShot(V(0, 5, 0), V(0, 0, -60), nil)
			end)
			local n, ok = trails()
			check(n == 1 and ok, "a pellet trails an energy streak (" .. n .. ")")
			sim:run("sniper", function()
				CombatFx.enemyShot(V(10, 5, 0), V(0, 0, -200), 1)
			end)
			n, ok = trails()
			check(n == 2 and ok, "a Sniper round too (" .. n .. ")")
			sim:run("fake", function()
				CombatFx.pathShot(
					V(20, 5, 0),
					V(0, 0, -60),
					"Light",
					"Comic",
					roblox.Color3.fromRGB(255, 230, 120)
				)
			end)
			n, ok = trails()
			check(n == 3 and ok, "and a famous fake's shot (" .. n .. ")")
			-- a Medic Unit's repair beam: the flowing energy strip between the Medic and its patient, gone after
			local ma, mb = V(0, 5, 0), V(12, 5, 0)
			sim:run("mend", function()
				CombatFx.mend(function()
					return ma
				end, function()
					return mb
				end, 0.5)
			end)
			sim:run("frame", function()
				sim.service("RunService").RenderStepped:Fire(1 / 60)
			end)
			local mend = sim.service("Workspace"):FindFirstChild("MendBeam", true)
			check(mend ~= nil and mend:IsA("Beam"), "the repair beam is an energy strip")
			if mend then
				check(mend.Attachment1.Position == mb, "reaching the patient")
			end
			require("@lune/task").wait(0.55)
			sim:run("frame", function()
				sim.service("RunService").RenderStepped:Fire(0.6)
			end)
			check(
				sim.service("Workspace"):FindFirstChild("MendBeam", true) == nil,
				"and it goes when the mend ends"
			)
			-- an Interceptor's net and a Grappler's claw in their Blender looks
			sim:run("net", function()
				CombatFx.enemyShot(V(0, 5, 40), V(0, 0, -50), 2)
				CombatFx.hook(
					function()
						return V(0, 5, 80)
					end,
					V(0, 5, 80),
					V(0, 0, -50),
					function()
						return true
					end
				)
			end)
			sim:run("frame", function()
				sim.service("RunService").RenderStepped:Fire(0.2)
			end)
			local cords, hubs, prongs = nil, 0, 0
			for _, d in sim.service("Workspace"):GetDescendants() do
				if d:IsA("MeshPart") and d.Name == "NetCords" then
					cords = d
				elseif d:IsA("MeshPart") and d.Name == "ClawHub" then
					hubs += 1
				elseif d:IsA("MeshPart") and d.Name == "ClawProng" then
					prongs += 1
				end
			end
			check(cords ~= nil, "the net is the woven Blender net")
			if cords then
				local want = Config.PowerArt.Net.NetCords.size[1] * Config.Fx.robots.net.size / 2
				check(
					math.abs(cords.Size.X - want) < 0.05,
					string.format("opened to its size (%.2f)", cords.Size.X)
				)
			end
			check(
				hubs == 1 and prongs == 3,
				"the claw: a hub and three prongs (" .. hubs .. ", " .. prongs .. ")"
			)
			-- a Bomber's grenade: the banded Blender body, cap and blinking light, spinning on its arc, gone on landing
			sim:run("lob", function()
				CombatFx.lob(V(60, 5, 0), V(60, 0, -20), 0.6)
			end)
			sim:run("frame", function()
				sim.service("RunService").RenderStepped:Fire(0.2)
			end)
			local gp = {}
			for _, d in sim.service("Workspace"):GetDescendants() do
				if d:IsA("MeshPart") and string.sub(d.Name, 1, 7) == "Grenade" then
					gp[d.Name] = d
				end
			end
			check(gp.GrenadeBody and gp.GrenadeCap and gp.GrenadeLight, "the grenade is the Blender grenade")
			if gp.GrenadeBody then
				local want = Config.PowerArt.Grenade.GrenadeBody.size[1]
					* Config.Fx.robots.lob.size
					* Config.Fx.robots.lob.mesh
				check(math.abs(gp.GrenadeBody.Size.X - want) < 0.02, "at its size")
				local at = gp.GrenadeBody.CFrame.Position
				check(at.X > 55 and at.Y > 4, "on its arc")
				check((gp.GrenadeLight.CFrame.Position - at).Magnitude < 1.2, "the light rides the cap")
			end
			sim:run("frame", function()
				sim.service("RunService").RenderStepped:Fire(0.5)
			end)
			check(gp.GrenadeBody == nil or gp.GrenadeBody.Parent == nil, "gone when it lands")
			-- a Bomber's burning patch: Ember Ring's flame tongues round it
			sim:run("zone", function()
				CombatFx.zone(V(-30, 0, 0), 6, 1)
			end)
			sim:run("tick", function()
				sim.service("RunService").Heartbeat:Fire(1 / 60)
			end)
			local flames = nil
			for _, d in sim.service("Workspace"):GetDescendants() do
				if d:IsA("MeshPart") and d.Name == "EmberFlames" and d.CFrame.Position.X < -20 then
					flames = d
				end
			end
			check(flames ~= nil, "the burning patch has a ring of flame tongues")
			if flames then
				check(
					math.abs(flames.Size.X - Config.PowerArt.EmberRim.EmberFlames.size[1] * 6 * 0.95) < 0.05,
					"round the patch"
				)
			end
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
		end
	)

	test("List combat: standing and ground rings are the Blender shockwave ring", function()
		local roblox = require("@lune/roblox")
		if not T.placePath then
			return
		end
		local UiSim = require("./uisim")
		local sim = UiSim.new(
			UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		)
		local CombatFx = sim:require("Client.Fx.CombatFx")
		sim:run("CombatFx", CombatFx.init)
		local cam = sim.service("Workspace").CurrentCamera
		cam.CFrame = roblox.CFrame.new(0, 5, 30)
		local function rings()
			local out = {}
			for _, d in sim.service("Workspace"):GetDescendants() do
				if d:IsA("MeshPart") and d.Name == "ShockRing" then
					table.insert(out, d)
				end
			end
			return out
		end
		local before = #rings()
		-- Martial's ki ring bursts flat toward the camera: two rings standing across the view
		sim:run("ki", function()
			CombatFx.impact(
				roblox.Vector3.new(0, 5, 0),
				false,
				"Comic",
				true,
				roblox.Color3.fromRGB(255, 160, 60),
				"Martial"
			)
		end)
		local all = rings()
		check(#all - before >= 2, "the ki ring is the shockwave mesh (" .. (#all - before) .. ")")
		local facing = 0
		for i = before + 1, #all do
			-- its axis (up) points at the camera (+z here)
			if all[i].CFrame.UpVector.Z > 0.95 then
				facing += 1
			end
		end
		check(facing >= 2, "stood up facing the camera (" .. facing .. ")")
		local src = fs.readFile("src/client/Fx/CombatFx.luau")
		check(
			string.find(src, "CFrame.lookAt(pos, pos + normal) * STAND", 1, true) ~= nil,
			"disc stands the ring across its normal"
		)
		check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
	end)

	test("List combat: a crater hit lays the scorch sheet, not a slate disc", function()
		local roblox = require("@lune/roblox")
		if not T.placePath then
			return
		end
		local row = Config.Abilities.list.StonePillar
		check(
			row ~= nil and Config.FxMoves.moves.StonePillar.hit == "crater",
			"Stone Pillar's hit is a crater"
		)
		local UiSim = require("./uisim")
		local sim = UiSim.new(
			UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		)
		local CombatFx = sim:require("Client.Fx.CombatFx")
		sim:run("CombatFx", CombatFx.init)
		sim:run("hit", function()
			CombatFx.impact(
				roblox.Vector3.new(0, 5, 0),
				false,
				"Comic",
				true,
				roblox.Color3.fromRGB(160, 120, 80),
				row.set,
				"StonePillar"
			)
		end)
		local scorch, slate = false, 0
		for _, d in sim.service("Workspace"):GetDescendants() do
			if d:IsA("ParticleEmitter") and string.find(d.Parent.Name, "^scorch:") then
				scorch = true
			elseif
				d:IsA("Part")
				and d.Shape == roblox.Enum.PartType.Cylinder
				and d.Material == roblox.Enum.Material.Slate
			then
				slate += 1
			end
		end
		check(scorch, "the scorch sheet is laid")
		check(slate == 0, "no slate disc (" .. slate .. ")")
		check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
	end)

	test(
		"List combat: halo and spin flourishes are hollow Blender hoops, shatters glass stones, wings Blender wings, cages lances, plates hex plates, flakes snowflakes, tris psi gems, rings hoops, robots throw scrap",
		function()
			local roblox = require("@lune/roblox")
			if not T.placePath then
				return
			end
			local UiSim = require("./uisim")
			local sim = UiSim.new(
				UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
				{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
			)
			local CombatFx = sim:require("Client.Fx.CombatFx")
			local AbilityFx = sim:require("Client.Fx.AbilityFx")
			sim:run("CombatFx", CombatFx.init)
			local V = roblox.Vector3.new
			local function count()
				local hoops, discs = 0, 0
				for _, d in sim.service("Workspace"):GetDescendants() do
					if d:IsA("MeshPart") and d.Name == "ShockRing" then
						hoops += 1
					elseif d:IsA("Part") and d.Shape == roblox.Enum.PartType.Cylinder then
						discs += 1
					end
				end
				return hoops, discs
			end
			-- Phoenix Dive's wings: the Blender wings of light, one either side (only spacing is checked here: Lune's
			-- CFrame.lookAt mirrors its frame, so which side is the hero's right is a Studio check, Tasks Studio 82)
			sim:run("wings", function()
				AbilityFx.flair(
					Config.Abilities.list.PhoenixDive,
					"Comic",
					V(60, 5, 0),
					V(0.3, 0, -1),
					roblox.Color3.fromRGB(255, 140, 60),
					roblox.Color3.fromRGB(255, 230, 150),
					nil
				)
			end)
			local wings, edges = {}, 0
			for _, d in sim.service("Workspace"):GetDescendants() do
				if d:IsA("MeshPart") and d.Name == "WingFeathers" then
					table.insert(wings, d.CFrame.Position)
				elseif d:IsA("MeshPart") and d.Name == "WingEdge" then
					edges += 1
				end
			end
			check(
				#wings == 2 and edges == 2,
				"two Blender wings with their bright edges (" .. #wings .. ", " .. edges .. ")"
			)
			if #wings == 2 then
				check((wings[1] - wings[2]).Magnitude > 2.5, "spread apart either side")
				check(wings[1].Y > 5.5 and wings[2].Y > 5.5, "raised up over the shoulders")
			end
			local src = fs.readFile("src/client/Fx/AbilityFx.luau")
			check(
				string.find(src, "-0.35 * open * sgn", 1, true) ~= nil,
				"both wings sweep back (mirrored yaw)"
			)
			-- Ember Ring's petals (the plate piece): bolted Blender hex plates, not boxes
			sim:run("petals", function()
				AbilityFx.hit(
					Config.Abilities.list.EmberRing,
					"Comic",
					V(-90, 5, 0),
					roblox.Color3.fromRGB(255, 120, 40),
					roblox.Color3.new(1, 1, 1),
					true,
					nil,
					1
				)
			end)
			local plates = 0
			for _, d in sim.service("Workspace"):GetDescendants() do
				if d:IsA("MeshPart") and d.Name == "PetalLeaf" and d.CFrame.Position.X < -80 then
					plates += 1
				end
			end
			check(plates >= 4, "the petals are Blender petals (" .. plates .. ")")
			-- Frost's flake piece: the Blender six-armed snowflake
			sim:run("frost field", function()
				CombatFx.field(
					V(-120, 0, 0),
					8,
					1,
					"Comic",
					roblox.Color3.fromRGB(150, 220, 255),
					false,
					nil,
					false,
					"Frost"
				)
			end)
			for _ = 1, 3 do
				sim:run("frame", function()
					sim.service("RunService").RenderStepped:Fire(1 / 60)
				end)
			end
			-- Mind's charge circles psi gems (the tri piece)
			sim:run("mind field", function()
				CombatFx.field(
					V(-150, 0, 0),
					8,
					1,
					"Comic",
					roblox.Color3.fromRGB(200, 140, 255),
					false,
					nil,
					false,
					"Mind"
				)
			end)
			for _ = 1, 3 do
				sim:run("frame", function()
					sim.service("RunService").RenderStepped:Fire(1 / 60)
				end)
			end
			-- Gunslinger's field pops rings (the ring piece): hollow shockwave rings, not filled discs; counted
			-- against the same field with no path (its own rim draws rings too)
			local function ringsAfter(set, x)
				local before = 0
				for _, d in sim.service("Workspace"):GetDescendants() do
					if d:IsA("MeshPart") and d.Name == "ShockRing" then
						before += 1
					end
				end
				sim:run("field " .. tostring(set), function()
					CombatFx.field(
						V(x, 0, 0),
						8,
						1,
						"Comic",
						roblox.Color3.fromRGB(120, 240, 255),
						false,
						nil,
						false,
						set
					)
				end)
				for _ = 1, 3 do
					sim:run("frame", function()
						sim.service("RunService").RenderStepped:Fire(1 / 60)
					end)
				end
				local after = 0
				for _, d in sim.service("Workspace"):GetDescendants() do
					if d:IsA("MeshPart") and d.Name == "ShockRing" then
						after += 1
					end
				end
				return after - before
			end
			local plain = ringsAfter(nil, -180)
			local gun = ringsAfter("Gunslinger", -210)
			check(gun > plain, "Gunslinger's field pieces are rings (" .. gun .. " vs " .. plain .. ")")
			-- a downed robot throws gears, brackets and bolts
			sim:run("robot down", function()
				CombatFx.burst(V(-240, 5, 0), "Comic", roblox.Color3.fromRGB(90, 96, 110))
			end)
			local scrapKinds = {}
			for _, d in sim.service("Workspace"):GetDescendants() do
				if d:IsA("MeshPart") and string.sub(d.Name, 1, 5) == "Scrap" then
					scrapKinds[d.Name] = true
					check(not d.Anchored, d.Name .. " flies loose")
				end
			end
			check(scrapKinds.ScrapGear and scrapKinds.ScrapBolt, "the scrap is gears and bolts")
			local gems = 0
			for _, d in sim.service("Workspace"):GetDescendants() do
				if d:IsA("MeshPart") and d.Name == "PsiGem" then
					gems += 1
				end
			end
			check(gems >= 1, "Mind's pieces are psi gems (" .. gems .. ")")
			local flakes = 0
			for _, d in sim.service("Workspace"):GetDescendants() do
				if d:IsA("MeshPart") and d.Name == "FlakeChip" then
					flakes += 1
				end
			end
			check(flakes >= 1, "Frost's falling chips are snowflakes (" .. flakes .. ")")
			-- Static Field's cage: bars of light are Blender lances stood on end round the target
			sim:run("cage", function()
				AbilityFx.hit(
					Config.Abilities.list.StaticField,
					"Comic",
					V(-60, 5, 0),
					roblox.Color3.fromRGB(120, 200, 255),
					roblox.Color3.new(1, 1, 1),
					true,
					nil,
					1
				)
			end)
			local bars = 0
			for _, d in sim.service("Workspace"):GetDescendants() do
				if d:IsA("MeshPart") and d.Name == "HeadLance" and d.CFrame.Position.X < -50 then
					bars += 1
					check(math.abs(d.CFrame.LookVector.Y) > 0.95, "standing upright")
				end
			end
			check(bars >= 4, "the cage's bars are lances (" .. bars .. ")")
			-- Glacier Armor's hit shatters chipped glass stones (the Blender rock), not cubes
			local rocks0 = 0
			for _, d in sim.service("Workspace"):GetDescendants() do
				if d:IsA("MeshPart") and d.Name == "HeadRock" then
					rocks0 += 1
				end
			end
			sim:run("shatter", function()
				AbilityFx.hit(
					Config.Abilities.list.GlacierArmor,
					"Comic",
					V(30, 5, 0),
					roblox.Color3.fromRGB(150, 220, 255),
					roblox.Color3.new(1, 1, 1),
					true,
					nil,
					1
				)
			end)
			local rocks, cubes = 0, 0
			for _, d in sim.service("Workspace"):GetDescendants() do
				if d:IsA("MeshPart") and d.Name == "HeadRock" then
					rocks += 1
					check(d.Material == roblox.Enum.Material.Glass, "in glass")
				elseif
					d:IsA("Part")
					and d.Material == roblox.Enum.Material.Glass
					and d.Shape == roblox.Enum.PartType.Block
				then
					cubes += 1
				end
			end
			check(rocks - rocks0 >= 3, "the shatter throws glass stones (" .. (rocks - rocks0) .. ")")
			check(cubes == 0, "no glass cubes (" .. cubes .. ")")
			for _, id in { "ThunderDrop", "Overcharge" } do
				local row = Config.Abilities.list[id]
				check(row ~= nil, id .. " exists")
				local h0, d0 = count()
				sim:run(id, function()
					AbilityFx.flair(
						row,
						"Comic",
						V(0, 5, 0),
						V(0, 0, -1),
						roblox.Color3.fromRGB(255, 220, 90),
						roblox.Color3.fromRGB(255, 255, 255),
						nil
					)
				end)
				local h1, d1 = count()
				local want = if id == "Overcharge" then 2 else 1
				check(h1 - h0 == want, id .. "'s rings are hoops (" .. (h1 - h0) .. ")")
				check(d1 == d0, id .. " makes no filled discs")
			end
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
		end
	)

	test("List combat: repair drones shine a textured energy beam and weld sparks", function()
		local roblox = require("@lune/roblox")
		if not T.placePath then
			return
		end
		local BuildingState = require("../src/shared/BuildingState")
		local UiSim = require("./uisim")
		local sim = UiSim.new(
			UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		)
		-- the hero stands by the building (drones only draw near you)
		local char = UiSim.newInstance("Model")
		local hrp = UiSim.newInstance("Part")
		hrp.Name = "HumanoidRootPart"
		hrp.CFrame = roblox.CFrame.new(0, 3, 0)
		hrp.Parent = char
		char.Parent = sim.service("Workspace")
		sim.service("Players").LocalPlayer.Character = char
		local BuildingFx = sim:require("Client.Fx.BuildingFx")
		sim:run("BuildingFx", BuildingFx.init)
		local remotes = sim.service("ReplicatedStorage"):WaitForChild("Remotes")
		local id = 4000
		sim:run("snapshot", function()
			remotes:WaitForChild("BuildingSnapshot").OnClientEvent:Fire({
				s = buffer.create(0),
				n = 0,
				o = BuildingState.packBoxes({ { x = 10, z = 0, sx = 20, sz = 20, base = 0, top = 30 } }),
				o1 = id,
				dr = { { 1, id, 10 } },
			})
		end)
		require("@lune/task").wait(2.2) -- the drone flies in for 2 s, then works
		for _ = 1, 2 do
			sim:run("frame", function()
				sim.service("RunService").RenderStepped:Fire(1 / 60)
			end)
		end
		local drone = sim.service("Workspace"):FindFirstChild("RepairDrone", true)
		check(drone ~= nil, "the repair drone flies in")
		local ray = drone and drone:FindFirstChild("RepairRay", true)
		check(ray ~= nil and ray:IsA("Beam"), "its beam is a textured Beam")
		if ray then
			check(
				ray.Texture == "rbxassetid://" .. Config.Fx.energyBeam.texture,
				"in the energy strip texture"
			)
			check(ray.Enabled, "shining while it works")
			local len = math.abs(ray.Attachment0.Position.Y - ray.Attachment1.Position.Y)
			check(len > 5, string.format("reaching down to the roof (%.1f)", len))
			check(ray.Parent.Transparency == 1, "the old neon bar stays clear")
		end
		local sparks = false
		for _, d in sim.service("Workspace"):GetDescendants() do
			if d:IsA("ParticleEmitter") and string.find(d.Parent.Name, "^spark:") then
				sparks = true
			end
		end
		check(sparks, "weld sparks where it lands")
		check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
	end)

	test(
		"List combat: holes in a standing building have torn concrete edges with rebar (destruction kit)",
		function()
			local roblox = require("@lune/roblox")
			local Structure = require("../src/shared/Structure")
			-- the seams: a 20 x 30 x 20 block's first front panel meets its two corner pillars and the slab above it
			local rec = { id = 1, x = 10, z = 0, sx = 20, sz = 20, base = 0, top = 30 }
			local grid = Structure.build(D, rec)
			local seams = Structure.seams(grid)
			local front = grid.at["w:1:1:1"]
			check(front ~= nil, "the front panel")
			local kinds = {}
			for _, seam in seams[front] or {} do
				check(seam.to == front and seam.on ~= front, "seams on the pieces round it")
				kinds[grid.pieces[seam.on].kind] = (kinds[grid.pieces[seam.on].kind] or 0) + 1
				check(seam.len >= seam.thick and seam.thick > 0.5, "a seam runs along its longer side")
				-- the seam's face lies on the panel's box
				local p = grid.pieces[front]
				local c = { p.cx, p.cy, p.cz }
				local sz = { p.sx, p.sy, p.sz }
				check(
					math.abs(math.abs(seam.at[seam.n] - c[seam.n]) - sz[seam.n] / 2) < 0.31,
					"on the panel's face"
				)
			end
			check(kinds.pillar == 2 and kinds.slab == 1, "two pillars and the slab above")
			check(Structure.seams(grid) == seams, "built once a grid")
			local T2 = D.structure.torn
			check(T2 ~= nil and T2.seg > 0 and T2.reach > 0, "tuned")
			for _, name in Config.Presets.order do
				check((Config.Presets[name].torn or 0) > 0, name .. " draws torn edges")
			end
			for k = 1, 2 do
				local row = Config.RubbleArt["Torn" .. k]
				check(
					row ~= nil and row["Torn" .. k] ~= nil and row["Torn" .. k .. "Rebar"] ~= nil,
					"Torn" .. k
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
			local id = 4100
			local info = UiSim.newInstance("StringValue")
			info.Name = "WorldInfo"
			info.Value =
				require("@lune/serde").encode("json", { buildings = { { id, 10, 0, 20, 20, 0, 30, 0 } } })
			info.Parent = sim.service("ReplicatedStorage")
			local city = sim.service("Workspace"):FindFirstChild("City")
			if not city then
				city = UiSim.newInstance("Folder")
				city.Name = "City"
				city.Parent = sim.service("Workspace")
			end
			local body = UiSim.newInstance("Model")
			body:SetAttribute("BuildingId", id)
			local shell = UiSim.newInstance("Part")
			shell.Size = roblox.Vector3.new(20, 30, 20)
			shell.CFrame = roblox.CFrame.new(10, 15, 0)
			shell.Color = roblox.Color3.fromRGB(180, 120, 90)
			shell.Parent = body
			body.Parent = city
			local BuildingFx = sim:require("Client.Fx.BuildingFx")
			sim:run("BuildingFx", BuildingFx.init)
			require("@lune/task").wait(0.3)
			local n = 0
			sim:run("hit", function()
				-- one piece knocked out of the front wall's first storey
				n = BuildingFx.predict(id, roblox.Vector3.new(10, 5, -11), D.structure.chunkCost, 2, 30)
			end)
			check(n >= 1, "the hit knocks a piece out (" .. n .. ")")
			local wreck = sim.service("Workspace"):FindFirstChild("Wreck_" .. id, true)
			check(wreck ~= nil, "the building is drawn in pieces")
			local lips, bars = 0, 0
			for _, d in (if wreck then wreck:GetChildren() else {}) do
				if d:IsA("MeshPart") and string.match(d.Name, "^Torn%d$") then
					lips += 1
					check(d.CanCollide == false and d.CanQuery == false and d.Anchored, "a lip is look only")
				elseif d:IsA("MeshPart") and string.match(d.Name, "^Torn%dRebar$") then
					bars += 1
					check(d.Material == roblox.Enum.Material.Metal, "rebar is steel")
				end
			end
			check(
				lips >= 3 and bars == lips,
				string.format("torn edges round the hole (%d lips, %d rebar)", lips, bars)
			)
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
		end
	)

	test("List combat: the petals hit throws Blender petals, not hex plates", function()
		local roblox = require("@lune/roblox")
		local P = Config.PowerArt.Petal
		check(
			P ~= nil and P.PetalLeaf ~= nil and P.PetalLeaf.tint == true,
			"the Petal look takes the path colour"
		)
		if not T.placePath then
			return
		end
		local UiSim = require("./uisim")
		local sim = UiSim.new(
			UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		)
		local CombatFx = sim:require("Client.Fx.CombatFx")
		sim:run("CombatFx", CombatFx.init)
		local pink = roblox.Color3.fromRGB(255, 150, 200)
		local made
		sim:run("petal", function()
			made = CombatFx.piece("petal", 2, pink)
		end)
		check(
			made ~= nil and made:IsA("MeshPart") and made.Name == "PetalLeaf",
			"a petal piece is the Blender petal"
		)
		if made then
			check(made.Size.Z > made.Size.X * 1.8 and made.Size.Y < made.Size.X, "long, narrow and thin")
			check(made.Color == pink, "in the path colour")
		end
		local fx = fs.readFile("src/client/Fx/AbilityFx.luau")
		check(string.find(fx, "K.PIECE.petal(", 1, true) ~= nil, "HIT.petals throws petals")
		check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
	end)

	test("List combat: the Swordsman's cuts are Blender crescents (Everything Left 172)", function()
		local roblox = require("@lune/roblox")
		local S = Config.PowerArt.Slash
		check(S ~= nil and S.SlashCrescent ~= nil and S.SlashEdge ~= nil, "the Slash look")
		check(S.SlashCrescent.tint == true, "the crescent takes the path colour")
		if not T.placePath then
			return
		end
		local UiSim = require("./uisim")
		local sim = UiSim.new(
			UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		)
		local CombatFx = sim:require("Client.Fx.CombatFx")
		sim:run("CombatFx", CombatFx.init)
		local V = roblox.Vector3.new
		local red = roblox.Color3.fromRGB(255, 70, 90)
		local function count(name: string): number
			local n = 0
			for _, d in sim.service("Workspace"):GetDescendants() do
				if d:IsA("MeshPart") and d.Name == name then
					n += 1
				end
			end
			return n
		end
		local beamsBefore = #sim.service("Workspace"):GetDescendants()
		sim:run("slash", function()
			CombatFx.arc(V(0, 5, 0), V(0, 0, -1), 8, 120, "Comic", red, 1, true, false, "Blade")
		end)
		check(
			count("SlashCrescent") == 1 and count("SlashEdge") == 1,
			"a sword cut is one crescent and its edge"
		)
		check(
			#sim.service("Workspace"):GetDescendants() - beamsBefore < 12,
			"no row of beam segments under it ("
				.. (#sim.service("Workspace"):GetDescendants() - beamsBefore)
				.. ")"
		)
		local punchBefore = count("SlashCrescent")
		sim:run("punch", function()
			CombatFx.arc(V(0, 5, 0), V(0, 0, -1), 6, 90, "Comic", red, 1, false, false, "Martial")
		end)
		check(count("SlashCrescent") == punchBefore, "a punch keeps its own look")
		sim:run("splitter", function()
			CombatFx.superMoment(
				Config.Abilities.list.HeavenSplitter,
				"Anime",
				{ o = V(0, 5, 0), d = V(0, 0, -1), e = V(0, 5, -60) }
			)
		end)
		check(count("SlashCrescent") >= 2, "Heaven Splitter flies the giant crescent")
		local big = 0
		for _, d in sim.service("Workspace"):GetDescendants() do
			if d:IsA("MeshPart") and d.Name == "SlashCrescent" then
				big = math.max(big, d.Size.X)
			end
		end
		check(big > 15, "the splitter's crescent is giant (" .. big .. ")")
		sim:advance(1)
		check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
	end)

	test("List combat: shock rings and cone blasts are Blender meshes (Everything Left 381)", function()
		local roblox = require("@lune/roblox")
		local S = Config.PowerArt.Shock
		check(S and S.ShockRing and S.ConeFan and S.ConeStreaks, "the Shock look")
		if not T.placePath then
			return
		end
		local UiSim = require("./uisim")
		local sim = UiSim.new(
			UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		)
		local CombatFx = sim:require("Client.Fx.CombatFx")
		sim:run("CombatFx", CombatFx.init)
		local V = roblox.Vector3.new
		local c = roblox.Color3.fromRGB(80, 200, 255)
		local function count(name: string): (number, any)
			local n, last = 0, nil
			for _, d in sim.service("Workspace"):GetDescendants() do
				if d:IsA("MeshPart") and d.Name == name then
					n += 1
					last = d
				end
			end
			return n, last
		end
		local before = count("ShockRing")
		sim:run("ring", function()
			CombatFx.ring(V(0, 0, 0), 12, c, 0.4)
		end)
		local n, r = count("ShockRing")
		check(n == before + 1, "a burst's ring is the shock ring")
		check(r and r.CFrame.Position.Y > 0 and r.CFrame.Position.Y < 1, "standing on the ground point")
		sim:run("nova", function()
			CombatFx.nova(V(0, 3, 0), 15, "Comic", c, true, "Volt")
		end)
		check(count("ShockRing") >= before + 3, "novas ring out in it")
		sim:run("cone", function()
			CombatFx.cone(V(0, 5, 0), V(0, 0, -1), 20, 60, "Comic", c, "Frost")
		end)
		check(count("ConeFan") == 1 and count("ConeStreaks") == 1, "a cone power blasts a fan with streaks")
		sim:run("anime cone", function()
			CombatFx.cone(V(0, 5, 0), V(0, 0, -1), 20, 60, "Anime", c, "Frost")
		end)
		check(count("ConeFan") == 1, "Anime keeps its white rays and speed lines")
		sim:advance(1)
		check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
	end)

	test("List combat: the Tidal surge rolls in Blender breaking waves (Everything Left 248)", function()
		local roblox = require("@lune/roblox")
		if not T.placePath then
			return
		end
		local UiSim = require("./uisim")
		local sim = UiSim.new(
			UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		)
		local WorldClient = sim:require("Client.Controllers.WorldClient")
		local EventFx = sim:require("Client.Fx.EventFx")
		local ws = sim.service("Workspace")
		local holder = UiSim.newInstance("Folder")
		holder.Parent = ws
		sim:run("EventFx", function()
			EventFx.init(holder)
		end)
		local d = Config.City.districts.Docks
		local cx, cz = (d.minX + d.maxX) / 2, (d.minZ + d.maxZ) / 2
		local cam = ws.CurrentCamera
		if cam then
			cam.CFrame = roblox.CFrame.new(cx, 60, cz + 80)
		end
		table.insert(
			WorldClient.events,
			{ id = "TidalSurge", state = 0, ends = os.clock() + 60, need = 4, have = 1 }
		)
		local rs = sim.service("RunService")
		for _ = 1, 3 do
			sim:run("frame", function()
				rs.RenderStepped:Fire(1 / 30)
			end)
		end
		local water, foam, cyl = 0, 0, 0
		for _, x in holder:GetDescendants() do
			if x:IsA("MeshPart") and x.Name == "WaveWater" then
				water += 1
			elseif x:IsA("MeshPart") and x.Name == "WaveFoam" then
				foam += 1
			elseif x:IsA("Part") and x.Shape == roblox.Enum.PartType.Cylinder then
				cyl += 1
			end
		end
		check(
			water >= 4 and water == foam,
			string.format("breaking waves with foam crests (%d, %d)", water, foam)
		)
		check(cyl == 0, "no cylinder rollers left (" .. cyl .. ")")
		check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
	end)

	test("List combat: the STYLES tab shows a picture per style (Everything Left 362)", function()
		local GearMath = require("../src/shared/GearMath")
		local tiles = Config.StyleTiles
		check(Config.Ui.styleTiles and Config.Ui.styleTiles > 0, "the style tiles sheet has an uploaded id")
		check(fs.isFile("art/export/ui/styles/StyleTiles.png"), "the packed sheet is committed")
		check(fs.isFile("art/ui/style_tiles.py"), "the script that packs it is committed")
		-- every style that can exist names a cell, and the cells fit the sheet without overlap
		local used, missing = {}, {}
		for _, id in GearMath.allStyles(Config) do
			local slotIdx = GearMath.styleParts(id)
			local slot = Config.Gear.slotOrder[slotIdx]
			local row = GearMath.styleRow(Config, id)
			local key = GearMath.lookKey(slot, row)
			local i = tiles.keys[key]
			if i == nil then
				table.insert(missing, key)
			else
				check(i >= 0 and i < tiles.per * tiles.per, key .. " sits on the sheet")
			end
		end
		check(#missing == 0, "every style has a tile; missing: " .. table.concat(missing, ", "))
		for key, i in tiles.keys do
			check(used[i] == nil, key .. " has its own cell")
			used[i] = key
		end
		-- the real screen: GearScreen's STYLES tab puts a Thumb with the style's cell on each style button
		local roblox = require("@lune/roblox")
		local UiSim = require("./uisim")
		local trees = UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath)))
		local sim = UiSim.new(trees, {
			name = "iPhone 14",
			w = 844,
			h = 390,
			top = 58,
			left = 47,
			right = 47,
			bottom = 0,
			touch = true,
		})
		sim:run("InputController", sim:require("Client.Controllers.InputController").init)
		local GS = sim:require("Client.Ui.GearScreen")
		local State = sim:require("Client.State")
		local first = GearMath.allStyles(Config)[1]
		State.profile.styles = { first }
		sim:run("GearScreen", GS.init)
		sim:run("open", GS.open)
		local g = sim.playerGui:FindFirstChild("Gear") or sim.playerGui:FindFirstChild("GearScreen")
		local root = g or sim.playerGui
		for _, d in root:GetDescendants() do
			if d:IsA("TextButton") and d.Text == "STYLES" then
				sim:run("styles", function()
					d.Activated:Fire()
				end)
				break
			end
		end
		local pics, dim = 0, 0
		for _, d in root:GetDescendants() do
			if
				d:IsA("ImageLabel")
				and d.Name == "Thumb"
				and d.Image == "rbxassetid://" .. Config.Ui.styleTiles
			then
				pics += 1
				check(d.ImageRectSize.X == tiles.cell, "a style picture shows one cell")
				if d.ImageTransparency > 0.3 then
					dim += 1
				end
			end
		end
		local slot1 = 0
		for _, id in GearMath.allStyles(Config) do
			if GearMath.styleParts(id) == 1 then
				slot1 += 1
			end
		end
		check(
			pics == slot1,
			"the first slot's " .. slot1 .. " styles each show a picture (saw " .. pics .. ")"
		)
		check(dim == slot1 - 1, "locked styles' pictures are dimmed, the owned one is not (" .. dim .. ")")
	end)

	test("List combat: every Legs piece has its own drawn Pants overlay (Everything Left 101)", function()
		local LA = Config.Creator.legsArt
		check(LA ~= nil and LA.on == true, "legsArt is on")
		local ROLES = { p = true, s = true, a = true, white = true, dark = true, gold = true, skin = true }
		local kits = {}
		for _, tab in Config.Creator.tabs do
			if tab.id == "legs" then
				for _, piece in tab.pieces do
					kits[piece[2]] = true
					local row = LA.kits[piece[2]]
					check(row ~= nil and row.pants > 0, piece[2] .. ": an uploaded Pants overlay")
					if row then
						check(ROLES[row.tint] == true, piece[2] .. ": a tint role LookKit.colors holds")
						check(type(row.parts) == "boolean", piece[2] .. ": says whether its parts stay")
						check(
							fs.isFile("art/export/clothes/legs/LegsPants_" .. piece[2] .. ".png"),
							piece[2] .. ": the drawn template is committed"
						)
					end
				end
			end
		end
		local n = 0
		for kit in LA.kits do
			n += 1
			check(kits[kit] == true, "legsArt row " .. kit .. " is a Legs piece")
		end
		check(n == 30, "all 30 Legs pieces drawn (" .. n .. ")")
		-- the 3D pieces keep their parts; the flat ones (stripes, pockets, patches, cuffs) are drawn instead
		for _, k in { "skirt", "hakama", "greaves", "armored", "pleated", "sarong" } do
			check(LA.kits[k].parts == true, k .. " keeps its 3D parts")
		end
		for _, k in { "track", "cargo", "ripped", "jeans", "camo", "checkered", "bandaged", "shorts" } do
			check(LA.kits[k].parts == false, k .. "'s flat parts are drawn on the overlay")
		end
		-- the real path: LookKit puts one tinted HeroPants on a Humanoid body, none without one
		local roblox = require("@lune/roblox")
		local UiSim = require("./uisim")
		local trees = UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath)))
		local sim =
			UiSim.new(trees, { name = "PC", w = 1920, h = 1080, top = 36, left = 0, right = 0, bottom = 0 })
		local LookKit = sim:require("Shared.LookKit")
		local colors = {
			p = roblox.Color3.new(1, 0, 0),
			s = roblox.Color3.new(0, 1, 0),
			a = roblox.Color3.new(0, 0, 1),
			gold = roblox.Color3.new(1, 0.8, 0.3),
			white = roblox.Color3.new(1, 1, 1),
		}
		local char = UiSim.newInstance("Model")
		UiSim.newInstance("Humanoid").Parent = char
		local old = UiSim.newInstance("Pants")
		old.Name = "HeroPants"
		old.Parent = char
		local drawn = LookKit.legsClothes(char, "jeans", colors)
		local pants = {}
		for _, c in char:GetChildren() do
			if c:IsA("Pants") then
				table.insert(pants, c)
			end
		end
		check(#pants == 1, "one Pants on the body (" .. #pants .. ")")
		check(pants[1].PantsTemplate == "rbxassetid://" .. LA.kits.jeans.pants, "the jeans' own template")
		check(pants[1].Color3 == colors.gold, "tinted by its role (gold stitching)")
		check(drawn == true, "the jeans' gold stitch parts stay off")
		check(LookKit.legsClothes(char, "skirt", colors) == false, "the skirt keeps its 3D skirt")
		local bare = UiSim.newInstance("Model")
		check(
			LookKit.legsClothes(bare, "jeans", colors) == false,
			"no Humanoid (an HQ mannequin): parts as before"
		)
		check(bare:FindFirstChildOfClass("Pants") == nil, "and no Pants")
		local src = fs.readFile("src/shared/LookKit.luau")
		check(
			string.find(src, "not avatar and legsClothes(char, legsKit", 1, true) ~= nil,
			"LookKit.build wears it, never over the player's own avatar clothes"
		)
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

	test("List combat: citizens window shop and come out with bags (Everything Left 275)", function()
		local CitizenSim = require("../src/shared/CitizenSim")
		local CitizenBuffer = require("../src/shared/CitizenBuffer")
		local shop = Config.Destruction.citizens.shop
		check(shop ~= nil and shop.chance > 0 and shop.buy > 0, "window shopping is tuned")
		-- every sidewalk corner knows its block's centre
		local sim = CitizenSim.new(Config, {}, 5)
		for _, n in sim.nodes do
			check(n.cx ~= nil and n.cz ~= nil, "a corner knows its block")
		end
		CitizenSim.populate(sim)
		-- force one: a walker heading along a block's side stops, faces the block, goes in, comes out with a bag
		local cfg = table.clone(sim.cfg)
		cfg.shop = table.clone(cfg.shop)
		cfg.shop.chance, cfg.shop.buy = 1000, 1
		cfg.chat = nil
		sim.cfg = cfg
		local c = sim.citizens[1]
		local here = sim.nodes[c.node]
		local side
		for _, l in here.links do
			if sim.nodes[l].cx == here.cx and sim.nodes[l].cz == here.cz then
				side = l
			end
		end
		check(side ~= nil, "the corner has a block side")
		c.state, c.path, c.shopAfter = CitizenSim.WALK, { side }, nil
		local n = sim.nodes[side]
		local dx, dz = n.x - c.x, n.z - c.z
		local d = math.sqrt(dx * dx + dz * dz)
		c.fx, c.fz = dx / d, dz / d
		CitizenSim.step(sim, 0.1, 1)
		check(c.state == CitizenSim.PAUSE, "it stops to look in the windows")
		local tx, tz = (here.cx :: number) - c.x, (here.cz :: number) - c.z
		check(c.fx * tx + c.fz * tz > 0, "facing the shops, not the street")
		check(math.abs(c.fx * dx / d + c.fz * dz / d) < 0.01, "side on to the sidewalk")
		local x0, z0 = c.x, c.z
		CitizenSim.step(sim, 0.1, 1 + shop.time[2] + 0.1)
		check(c.state == CitizenSim.HIDDEN and c.inside == true, "then it goes in to buy")
		CitizenSim.step(sim, 0.1, 1 + shop.time[2] + shop.inside[2] + 0.3)
		check(c.state == CitizenSim.WALK and c.bag == true, "and comes back out with a bag")
		check(c.x == x0 and c.z == z0, "where it went in")
		local b = CitizenBuffer.encodeFor(1, { c }, c.x, c.z, 50)
		local _, rows = CitizenBuffer.decode(b)
		check(
			rows[1] and rows[1].bag == true and rows[1].color == c.color,
			"the bag rides the packet beside the colour"
		)
		CitizenSim.step(sim, 0.1, 1 + shop.time[2] + shop.inside[2] + shop.bag + 1)
		check(c.bag == false, "the bag goes after a while")
		local _, rows2 = CitizenBuffer.decode(CitizenBuffer.encodeFor(2, { c }, c.x, c.z, 50))
		check(rows2[1] and rows2[1].bag == false, "no bag in the packet then")
		-- a scare while looking: no shopping trip, it runs
		local o = sim.citizens[2]
		o.state, o.buy = CitizenSim.PAUSE, true
		CitizenSim.danger(sim, o.x, o.z, 30, 10)
		check(o.buy == nil and o.state ~= CitizenSim.PAUSE, "danger cancels the trip")
		-- the real tuning over five minutes: some shop, some carry bags, most of the crowd still walks
		local live = CitizenSim.new(Config, {}, 11)
		CitizenSim.populate(live)
		local looked, bags = 0, 0
		for k = 1, 3000 do
			CitizenSim.step(live, 0.1, k * 0.1)
			if k % 50 == 0 then
				for _, x in live.citizens do
					if x.bag then
						bags += 1
					end
				end
			end
		end
		for _, x in live.citizens do
			if x.shopAfter then
				looked += 1
			end
		end
		print(string.format("  citizens: %d window shopped in 5 minutes, %d bag sightings", looked, bags))
		check(looked >= 5, "window shopping happens (" .. looked .. ")")
		check(bags >= 3, "bags are carried (" .. bags .. ")")
		local walking = 0
		for _, x in live.citizens do
			if x.state == CitizenSim.WALK then
				walking += 1
			end
		end
		check(walking >= #live.citizens * 0.4, "most of the crowd keeps walking (" .. walking .. ")")
		local src = fs.readFile("src/client/Controllers/CitizenRenderer.luau")
		check(
			string.find(src, "setBag(body, if rb.bag then id else nil)", 1, true) ~= nil,
			"the devices draw the bag"
		)
		check(string.find(src, "setBag(body, nil)", 1, true) ~= nil, "and take it off a pooled body")
	end)

	test("List combat: citizens sit on the street benches (Everything Left 275)", function()
		local CitizenSim = require("../src/shared/CitizenSim")
		local CitizenBuffer = require("../src/shared/CitizenBuffer")
		local WorldMap = require("../src/shared/WorldMap")
		local sit = Config.Destruction.citizens.sit
		check(sit ~= nil and sit.chance > 0 and sit.reach > 0, "bench sitting is tuned")
		local world = WorldMap.build(Config, 7, { props = true })
		local benches = {}
		for _, p in world.props do
			if p.name == "Bench" and (p.d == "Downtown" or p.d == "OldTown") then
				table.insert(benches, p)
			end
		end
		check(#benches >= 20, "Downtown and Old Town have benches (" .. #benches .. ")")
		local sim = CitizenSim.new(Config, {}, 5, nil, benches)
		check(#sim.seats == #benches * 2, "two seats a bench")
		-- every seat is a step off a sidewalk the citizens walk (within reach of a link between two corners)
		local near = 0
		for _, st in sim.seats do
			local best = math.huge
			for _, n in sim.nodes do
				for _, l in n.links do
					local m = sim.nodes[l]
					local ax, az, bx, bz = n.x, n.z, m.x, m.z
					local vx, vz = bx - ax, bz - az
					local t = math.clamp(((st.x - ax) * vx + (st.z - az) * vz) / (vx * vx + vz * vz), 0, 1)
					best = math.min(best, math.sqrt((ax + vx * t - st.x) ^ 2 + (az + vz * t - st.z) ^ 2))
				end
			end
			if best <= sit.reach then
				near += 1
			end
		end
		check(
			near >= #sim.seats * 0.8,
			string.format("seats beside the sidewalks (%d of %d)", near, #sim.seats)
		)
		-- the seat sits on the bench: behind its foot point, facing out of its front (-z at ry 0)
		local b = benches[1]
		local st = sim.seats[1]
		local a = math.rad(b.ry)
		check(
			math.abs(st.fx + math.sin(a)) < 1e-6 and math.abs(st.fz + math.cos(a)) < 1e-6,
			"facing out of the bench"
		)
		local back = (st.x - b.x) * -st.fx + (st.z - b.z) * -st.fz
		check(math.abs(back - sit.back) < 1e-6, "on the seat, behind the foot point")
		-- force one: a walker beside a free seat walks over, sits facing out, stands up and walks on
		CitizenSim.populate(sim)
		local cfg = table.clone(sim.cfg)
		cfg.sit = table.clone(cfg.sit)
		cfg.sit.chance = 1000
		cfg.chat, cfg.shop = nil, nil
		sim.cfg = cfg
		local c = sim.citizens[1]
		for _, o in sim.citizens do
			o.sitAfter = math.huge
		end
		c.sitAfter = nil
		c.state, c.path = CitizenSim.WALK, {}
		c.x, c.z = st.x - st.fx * 3, st.z - st.fz * 3
		CitizenSim.step(sim, 0.1, 1)
		check(c.seat ~= nil and sim.seats[c.seat :: number].taken, "it picks the seat")
		local s = sim.seats[c.seat :: number]
		local t = 1
		while not c.sit and t < 5 do
			t += 0.1
			CitizenSim.step(sim, 0.1, t)
		end
		check(c.sit == true and c.state == CitizenSim.PAUSE, "and sits down")
		check(c.x == s.x and c.z == s.z and c.fx == s.fx and c.fz == s.fz, "on the seat, facing out")
		local _, rows = CitizenBuffer.decode(CitizenBuffer.encodeFor(1, { c }, c.x, c.z, 50))
		check(rows[1] and rows[1].sit == true and rows[1].color == c.color, "sitting rides the packet")
		CitizenSim.step(sim, 0.1, t + sit.time[2] + 0.1)
		check(
			not c.sit and c.seat == nil and not s.taken and c.state == CitizenSim.WALK,
			"then stands and walks on"
		)
		local _, rows2 = CitizenBuffer.decode(CitizenBuffer.encodeFor(2, { c }, c.x, c.z, 50))
		check(rows2[1] and rows2[1].sit == false, "standing in the packet")
		-- a scare on the bench: up and running, the seat freed
		c.sitAfter = nil
		c.state, c.path = CitizenSim.WALK, {}
		c.x, c.z = s.x - s.fx * 2, s.z - s.fz * 2
		t += sit.time[2] + 1
		for _ = 1, 30 do
			t += 0.1
			CitizenSim.step(sim, 0.1, t)
		end
		check(c.sit == true, "sat again")
		CitizenSim.danger(sim, c.x, c.z, 30, 10)
		check(
			not c.sit and c.seat == nil and not s.taken and c.state ~= CitizenSim.PAUSE,
			"danger stands it up"
		)
		-- the real tuning over five minutes: some sit, never two on one seat, most still walk
		local live = CitizenSim.new(Config, {}, 11, nil, benches)
		CitizenSim.populate(live)
		local sat, sightings, clash = 0, 0, 0
		for k = 1, 3000 do
			CitizenSim.step(live, 0.1, k * 0.1)
			if k % 50 == 0 then
				local on = {}
				for _, x in live.citizens do
					if x.sit then
						sightings += 1
						if on[x.seat] then
							clash += 1
						end
						on[x.seat :: number] = true
					end
				end
			end
		end
		for _, x in live.citizens do
			if x.sitAfter then
				sat += 1
			end
		end
		print(string.format("  citizens: %d sat on a bench in 5 minutes, %d sightings", sat, sightings))
		check(sat >= 5, "bench sitting happens (" .. sat .. ")")
		check(clash == 0, "one sitter a seat")
		local walking = 0
		for _, x in live.citizens do
			if x.state == CitizenSim.WALK then
				walking += 1
			end
		end
		check(walking >= #live.citizens * 0.4, "most of the crowd keeps walking (" .. walking .. ")")
		local src = fs.readFile("src/client/Controllers/CitizenRenderer.luau")
		check(
			string.find(src, "if anim[id] and not body.sit then", 1, true) ~= nil,
			"sitters keep the code pose"
		)
		check(string.find(src, "LC.seat + L.ground * LC.sitDrop", 1, true) ~= nil, "lifted onto the seat")
		local svc = fs.readFile("src/server/Services/CitizenService.luau")
		check(
			string.find(svc, "CitizenSim.blocker(world, Config), benches)", 1, true) ~= nil,
			"the server seats them"
		)
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
