-- Swing trails and the emblem on the weapon (list-combat 2026-11-20; checklist lines 195, 196, 198), built by the
-- place's own WeaponKit and LookKit through tests/weaponsim.luau: every melee weapon carries an unlit SwingTrail
-- along its outer blade (or across the fists), ranged ones none; a picked trail takes its strip; a swap leaves no
-- trail behind; every weapon has a piece for the emblem. ONLY="Weapon trail" runs just these.
return function(T: any)
	local test, check, Config, placePath = T.test, T.check, T.Config, T.place
	if not placePath then
		return
	end
	local fs = require("@lune/fs")
	local roblox = require("@lune/roblox")
	local WeaponSim = require("./weaponsim")
	local HeroAnim = require("../src/shared/HeroAnim")
	local WeaponRules = require("../src/shared/WeaponRules")
	local game = roblox.deserializePlace(fs.readFile(placePath))
	local W = Config.Weapons
	local ST = W.swingTrail

	local function look(id: number, trail: number): any
		return { id = id, style = 1, finish = 1, main = 0, trim = 0, glow = 0, glowLevel = 0, trail = trail }
	end
	local function trailsIn(char: any): { any }
		local out = {}
		for _, d in char:GetDescendants() do
			if d:IsA("Trail") and d.Name == "SwingTrail" then
				table.insert(out, d)
			end
		end
		return out
	end

	test("Weapon trail: every melee weapon has an unlit swing trail along its blade, ranged none", function()
		local sim = WeaponSim.new(game)
		local melee, ranged, blades = 0, 0, 0
		for id, w in W.list do
			local char = sim:body()
			sim:weapon(char, look(id, 0))
			local list = trailsIn(char)
			if ST.families[w[2]] then
				melee += 1
				check(#list >= 1, w[3] .. " has a swing trail")
				for _, tr in list do
					local a0, a1 = tr.Attachment0, tr.Attachment1
					check(
						a0 ~= nil and a1 ~= nil and a0.Parent == tr.Parent,
						w[3] .. ": both ends on its part"
					)
					if a0 and a1 then
						local pc = tr.Parent.CFrame
						local p0, p1 = pc:PointToWorldSpace(a0.Position), pc:PointToWorldSpace(a1.Position)
						check(
							(p1 - p0).Magnitude > 0.3,
							string.format(
								"%s: the trail has width (%.2f on %s %s)",
								w[3],
								(p1 - p0).Magnitude,
								tr.Parent.Name,
								tostring(tr.Parent.Size)
							)
						)
						check(tr.Enabled == false, w[3] .. ": off until a move plays")
						if tr.Parent.Name == "Weapon" then
							blades += 1
						end
					end
				end
			else
				ranged += 1
				check(#list == 0, w[3] .. " (ranged) draws none")
			end
			char:Destroy()
		end
		check(melee >= 25 and ranged >= 5, string.format("%d melee, %d ranged", melee, ranged))
		check(blades >= 15, "blades trail along the weapon itself (" .. blades .. ")")
	end)

	test("Weapon trail: a picked trail takes its strip; a swap leaves nothing on the hands", function()
		local sim = WeaponSim.new(game)
		local char = sim:body()
		sim:weapon(char, look(5, 3)) -- Sword, Frost
		local list = trailsIn(char)
		local kit = Config.Creator.trailFx.kits[ST.looks[3].kit]
		check(#list >= 1 and list[1]:GetAttribute("Trail") == 3, "the sword carries trail 3")
		if kit.id ~= 0 then
			check(string.find(list[1].Texture, tostring(kit.id), 1, true) ~= nil, "with the Frost strip")
		end
		sim:rebuild(char, look(1, 0)) -- Bare Fists: trails on the hands themselves
		local fists = trailsIn(char)
		check(#fists == 2, "fists trail on both hands (" .. #fists .. ")")
		sim:rebuild(char, look(25, 0)) -- a blaster: none, and the fists' trails are gone
		check(#trailsIn(char) == 0, "a swap leaves no trail behind")
		char:Destroy()
	end)

	test("Weapon trail: earned with Mastery, and every move clip lights it", function()
		local pts = W.mastery.perLevel
		check(WeaponRules.trailOpen(Config, 0, 0), "the base slash is free")
		check(not WeaponRules.trailOpen(Config, 0, 1), "Streak needs Mastery")
		check(WeaponRules.trailOpen(Config, ST.looks[1].level * pts, 1), "Streak opens at its level")
		check(not WeaponRules.trailOpen(Config, 300 * pts, 9), "no trail past the list")
		check(#ST.looks == #W.trails - 1, "one look per named trail")
		local src = fs.readFile("src/server/Services/CreatorService.luau")
		check(
			string.find(src, "WeaponRules.trailOpen", 1, true) ~= nil,
			"the server checks the trail is earned"
		)
		-- the clip each weapon move plays (HeroAnim.castClip) is in that weapon's move set (SwingTrailFx.clipsOf)
		local missing = {}
		for id in W.list do
			local m = HeroAnim.WEAPON_MOVES[id]
			local set = {}
			for _, c in (m and m.combo) or {} do
				set[c] = true
			end
			for _, k in { "Z", "X", "C", "V" } do
				if m and m[k] then
					set[m[k]] = true
				end
			end
			for key = 1, 5 do
				local row = Config.Abilities.list["W" .. id .. (if key == 1 then "M1" else W.keys[key - 1])]
				if row then
					for step = 1, 4 do
						local clip = HeroAnim.castClip(row, W.list[id][2], step)
						if not set[clip] then
							table.insert(missing, row.id .. ":" .. clip)
						end
					end
				end
			end
		end
		check(
			#missing == 0,
			"every weapon move's clip lights its trail (" .. table.concat(missing, ", ") .. ")"
		)
	end)

	test("Weapon trail: every weapon has a place for the hero's emblem", function()
		local sim = WeaponSim.new(game)
		local WeaponKit = sim:module("Shared.WeaponKit")
		local none = {}
		for id, w in W.list do
			local char = sim:body()
			local wf = sim:weapon(char, look(id, 0))
			local piece, cf, size = WeaponKit.emblemPiece(wf)
			if not (piece and cf and size) then
				table.insert(none, w[3])
			else
				check(size.X >= 0.25 and size.X <= 1.4, w[3] .. ": the emblem is sized to its face")
				check(
					(cf.Position - piece.CFrame.Position).Magnitude < 1e-3,
					w[3] .. ": centred on its piece"
				)
			end
			char:Destroy()
		end
		check(#none == 0, "every weapon shows the emblem (" .. table.concat(none, ", ") .. ")")
		local lk = fs.readFile("src/shared/LookKit.luau")
		check(
			string.find(lk, "weaponEmblem(wf, e,", 1, true) ~= nil,
			"LookKit draws it when the look says so"
		)
	end)
end
