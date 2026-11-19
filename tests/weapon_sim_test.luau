-- The carried weapon as the game builds it (fix-weapons, 2026-11-19, nate: "why are there just pieces floating
-- around?"): tests/weaponsim.luau runs the place's own LookKit and WeaponKit on Roblox's blocky body, for every
-- weapon in every style. Every piece is a mesh welded to its body part, never anchored, massless and out of
-- collisions, queries and touches; it sits where Shared.BodyFit puts its box; it is turned by Shared.MeshFix (Open
-- Cloud's import turned every weapon mesh 180 degrees about y inside its box, so unturned pieces came apart); a
-- swap leaves no old pieces; nothing lands at the origin or outside the hero; the part fallback is welded the same
-- way and never built beside the meshes. (Roblox's own geometry check: art/weapons/simcheck.py, needs the network.)
-- Called from tests/run.luau with the built place; ONLY="Weapon sim" runs just these.
return function(T: any)
	local test, check, Config, placePath = T.test, T.check, T.Config, T.place
	if not placePath then
		return
	end
	local fs = require("@lune/fs")
	local roblox = require("@lune/roblox")
	local WeaponSim = require("./weaponsim")
	local BodyFit = require("../src/shared/BodyFit")
	local WeaponMesh = require("../src/shared/WeaponMesh")
	local game = roblox.deserializePlace(fs.readFile(placePath))
	local TURN = roblox.CFrame.Angles(0, math.pi, 0)

	local function same(a: any, b: any, tol: number): boolean
		local ca, cb = { a:GetComponents() }, { b:GetComponents() }
		for i = 1, 12 do
			if math.abs(ca[i] - cb[i]) > tol then
				return false
			end
		end
		return true
	end

	local function look(id: number, style: number): any
		return { id = id, style = style, finish = 1, main = 0, trim = 0, glow = 0, glowLevel = 3 }
	end

	test("Weapon sim: every weapon is whole, welded and turned in game", function()
		local sim = WeaponSim.new(game)
		local looks, pieces, stray = 0, 0, 0
		for _, w in Config.Weapons.list do
			local id = w[1]
			for style = 1, 4 do
				local char = sim:body(roblox.CFrame.new(40, 10, -25) * roblox.CFrame.Angles(0, 0.7, 0))
				local wf = sim:weapon(char, look(id, style))
				local name = string.format("%d %s style %d", id, w[3], style)
				looks += 1
				check(wf:GetAttribute("Meshed") == true, name .. ": drawn from its meshes")
				local want = #WeaponMesh.pieces(Config, id, style)
				local got = 0
				for _, d in wf:GetDescendants() do
					if d:IsA("BasePart") then
						got += 1
						pieces += 1
						local mesh = d:GetAttribute("Piece")
						local tag = name .. " " .. tostring(mesh)
						check(
							d:IsA("MeshPart") and type(mesh) == "string",
							tag .. ": a mesh, not a fallback part"
						)
						check(
							not d.Anchored
								and d.Massless
								and not d.CanCollide
								and not d.CanQuery
								and not d.CanTouch,
							tag .. ": unanchored, massless, no collide, query or touch"
						)
						local weld = d:FindFirstChildOfClass("WeldConstraint")
						local body = weld and weld.Part0
						check(
							weld ~= nil and weld.Part1 == d and body ~= nil and body.Parent == char,
							tag .. ": welded to a body part of its hero"
						)
						if body then
							local rel = body.CFrame:ToObjectSpace(d.CFrame)
							-- where BodyFit puts the box, and the import's turn
							local row
							for _, p in WeaponMesh.pieces(Config, id, style) do
								if p.mesh == mesh then
									row = p
								end
							end
							if row then
								local s = body.Size
								local at =
									BodyFit.place(Config, body.Name, { s.X, s.Y, s.Z }, row.offset, row.size)
								local wantCf = roblox.CFrame.new(at[1], at[2], at[3]) * TURN
								check(same(rel, wantCf, 1e-3), tag .. ": at its fit and turned 180 about y")
							end
							check(
								(d.CFrame.Position - body.CFrame.Position).Magnitude < 8,
								tag .. ": near its body part"
							)
						end
						if d.CFrame.Position.Magnitude < 1 then
							stray += 1
						end
					end
				end
				check(got == want, name .. ": every mesh built")
				char:Destroy()
			end
		end
		check(stray == 0, "no weapon piece at the origin")
		check(
			looks == 144 and pieces > 600,
			string.format("all looks built (%d looks, %d pieces)", looks, pieces)
		)
	end)

	test(
		"Weapon sim: without Shared.MeshFix the pieces are turned wrong (the turn is what fixes them)",
		function()
			local sim = WeaponSim.new(game, { noTurn = true })
			local char = sim:body()
			local wf = sim:weapon(char, look(5, 1))
			local hand = char:FindFirstChild("RightHand")
			for _, d in wf:GetChildren() do
				if d:IsA("BasePart") then
					local rel = hand.CFrame:ToObjectSpace(d.CFrame)
					check(
						not same(rel.Rotation, TURN, 1e-3),
						"the unturned build differs from the turned one"
					)
					break
				end
			end
			char:Destroy()
		end
	)

	test("Weapon sim: a swap leaves nothing behind", function()
		local sim = WeaponSim.new(game)
		local char = sim:body()
		sim:weapon(char, look(11, 1))
		sim:rebuild(char, look(5, 2))
		sim:rebuild(char, look(26, 3))
		local folders, parts = 0, 0
		for _, d in char:GetChildren() do
			if d.Name == "HeroLook" then
				folders += 1
				for _, x in d:GetDescendants() do
					if x:IsA("BasePart") then
						parts += 1
						check(
							x:GetAttribute("Piece") and string.sub(x:GetAttribute("Piece"), 1, 3) == "W26",
							"only the new weapon's pieces"
						)
					end
				end
			end
		end
		check(folders == 1, "one HeroLook after swaps")
		check(parts == #WeaponMesh.pieces(Config, 26, 3), "exactly the new weapon's pieces")
		local loose = 0
		for _, d in sim.Workspace:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "Weapon" and not d:FindFirstAncestor("HeroLook") then
				loose += 1
			end
		end
		check(loose == 0, "no weapon piece loose in Workspace")
		char:Destroy()
	end)

	test("Weapon sim: the part fallback is welded the same way and never built beside the meshes", function()
		local sim = WeaponSim.new(game)
		local art = sim.RS:FindFirstChild("Art")
		local lib = art and art:FindFirstChild("Weapons")
		check(lib ~= nil, "Art.Weapons is in the place")
		if not lib then
			return
		end
		lib.Name = "WeaponsHidden"
		for _, id in { 5, 13, 22, 28 } do
			local char = sim:body()
			local wf = sim:weapon(char, look(id, 1))
			check(wf:GetAttribute("Meshed") == false, id .. ": parts when the meshes are missing")
			for _, d in wf:GetDescendants() do
				if d:IsA("BasePart") then
					check(not d:IsA("MeshPart"), id .. ": no mesh beside the parts")
					local weld = d:FindFirstChildOfClass("WeldConstraint")
					check(
						weld ~= nil and weld.Part0 and weld.Part0.Parent == char,
						id .. ": a part welded to its hero"
					)
					check(
						not d.Anchored and d.Massless and not d.CanCollide,
						id .. ": unanchored, massless, no collide"
					)
				end
			end
			char:Destroy()
		end
		lib.Name = "Weapons"
	end)
end
