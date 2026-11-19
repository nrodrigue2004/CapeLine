-- simdump.luau: every weapon in every style built by the game's own code on Roblox's blocky body (tests/weaponsim.luau),
-- written as build/weaponsim/<before|after>.json: each piece's mesh name, world CFrame (position + 3x3 rows), size,
-- flags and weld, plus the hand's CFrame. art/weapons/simcheck.py lays Roblox's own downloaded geometry
-- (art/upload/meshcheck.py's cache) on these CFrames, compares it with the Blender layout and renders the sheets.
--   lune run art/weapons/simdump.luau build/Capeline.rbxl [before]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local WeaponSim = require("../../tests/weaponsim")

local place = process.args[1] or "build/Capeline.rbxl"
local mode = process.args[2] or "after"
local game = roblox.deserializePlace(fs.readFile(place))
local sim = WeaponSim.new(game, { noTurn = mode == "before" })
local Config = sim:module("Config")

local function cf(c: any)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = c:GetComponents()
	return { pos = { x, y, z }, rot = { { r00, r01, r02 }, { r10, r11, r12 }, { r20, r21, r22 } } }
end

local out = { mode = mode, weapons = {} }
for _, w in Config.Weapons.list do
	local id = w[1]
	for style = 1, 4 do
		local char = sim:body()
		local wf = sim:weapon(char, { id = id, style = style, finish = 1, main = 0, trim = 0, glow = 0, glowLevel = 3 })
		local pieces = {}
		for _, d in wf:GetDescendants() do
			if d:IsA("BasePart") then
				local weld = d:FindFirstChildOfClass("WeldConstraint")
				table.insert(pieces, {
					mesh = d:GetAttribute("Piece"),
					class = d.ClassName,
					part = weld and weld.Part0 and weld.Part0.Name or nil,
					welded = weld ~= nil and weld.Part1 == d,
					cf = cf(d.CFrame),
					size = { d.Size.X, d.Size.Y, d.Size.Z },
					anchored = d.Anchored,
					massless = d.Massless,
					collide = d.CanCollide,
				})
			end
		end
		local parts = {}
		for _, p in char:GetChildren() do
			if p:IsA("BasePart") then
				local c = cf(p.CFrame)
				c.size = { p.Size.X, p.Size.Y, p.Size.Z }
				parts[p.Name] = c
			end
		end
		table.insert(out.weapons, {
			id = id,
			name = w[3],
			style = style,
			meshed = wf:GetAttribute("Meshed"),
			pieces = pieces,
			parts = parts,
		})
		char:Destroy()
	end
end
fs.writeDir("build/weaponsim")
fs.writeFile("build/weaponsim/" .. mode .. ".json", serde.encode("json", out))
print(mode, #out.weapons, "weapon looks")
