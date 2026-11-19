-- WeaponSim: the carried weapon built headless by the game's own code (fix-weapons, 2026-11-19, nate: "why are there
-- just pieces floating around?"). It loads the real ModuleScripts from a built place (Shared.LookKit, WeaponKit,
-- WeaponMesh, BodyFit, MeshFix and Config, as the server's LookService runs them), stands Roblox's own blocky R15
-- body up from Config.RobloxRig (15 parts at their rest centres, with their attachments) in Workspace, and runs
-- LookKit's weapon step: WeaponKit.build(char, folder, look, colors, LookKit's make, LookKit.bodyPart). What comes
-- back is what a hero carries in game: each piece with its world CFrame, size, flags and weld.
--   local sim = WeaponSim.new(placeGame)
--   local char = sim:body()                          -- a fresh hero body in Workspace
--   local folder = sim:weapon(char, look)            -- look: { id, style, finish, main, trim, glow, glowLevel }
--   sim:rebuild(char, look)                          -- LookKit's own swap: the old Weapon folder goes first
-- Not modelled: physics (welded pieces follow their hand in Roblox; here they keep the CFrame they were built at,
-- which is what the weld holds them to) and the client's Motor6D poses.

local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local WeaponSim = {}
WeaponSim.__index = WeaponSim

local GLOBALS = {
	"Instance",
	"CFrame",
	"Vector3",
	"Vector2",
	"Color3",
	"Enum",
	"UDim",
	"UDim2",
	"BrickColor",
	"NumberSequence",
	"NumberSequenceKeypoint",
	"ColorSequence",
	"ColorSequenceKeypoint",
	"NumberRange",
	"Rect",
	"Ray",
	"Font",
	"PhysicalProperties",
	"Region3",
}

-- opts.noTurn: Shared.MeshFix answers identity, as the game placed the meshes before fix-weapons (for the before
-- sheet and the test that shows the turn matters)
function WeaponSim.new(game: any, opts: any?)
	local self = setmetatable({ game = game, cache = {} }, WeaponSim)
	self.RS = game:GetService("ReplicatedStorage")
	self.Workspace = game:GetService("Workspace")
	if opts and opts.noTurn then
		local mf = self.RS.Shared:FindFirstChild("MeshFix")
		if mf then
			self.cache[mf:GetFullName()] = {
				turn = function()
					return roblox.CFrame.identity
				end,
			}
		end
	end
	return self
end

-- require() of a ModuleScript Instance from the place: its Source run with the place as `game`
function WeaponSim:require(mod: any): any
	local key = mod:GetFullName() -- (Lune hands out a new userdata for the same Instance, so keys are paths)
	if self.cache[key] ~= nil then
		return self.cache[key]
	end
	assert(mod and mod:IsA("ModuleScript"), "not a ModuleScript: " .. tostring(mod))
	local env: { [string]: any } = {} -- (Lune's load adds the standard globals)
	for _, g in GLOBALS do
		env[g] = (roblox :: any)[g]
	end
	env.game = self.game
	env.workspace = self.Workspace
	env.script = mod
	env.task =
		{ spawn = function() end, defer = function() end, delay = function() end, wait = function() end }
	env.tick = os.clock
	env.time = os.clock
	env.warn = function() end
	env.typeof = roblox.typeof or typeof
	env.require = function(m)
		return self:require(m)
	end
	-- (Lune's Instances have no WaitForChild: everything is already in the place, so FindFirstChild answers the same)
	local src = string.gsub(mod.Source, ":WaitForChild%(", ":FindFirstChild(")
	local chunk = luau.load(src, { debugName = mod:GetFullName(), environment = env })
	local out = chunk()
	self.cache[key] = out
	return out
end

function WeaponSim:module(path: string): any
	local node = self.RS
	for part in string.gmatch(path, "[^%.]+") do
		node = node:FindFirstChild(part)
		assert(node, "no " .. path .. " in the place")
	end
	return self:require(node)
end

-- Roblox's blocky R15 body at rest, feet on y = 0, facing -z
function WeaponSim:body(at: any?): any
	local Config = self:module("Config")
	local char = roblox.Instance.new("Model")
	char.Name = "Hero"
	local base = at or roblox.CFrame.new()
	for name, p in Config.RobloxRig.parts do
		local part = roblox.Instance.new("Part")
		part.Name = name
		part.Size = roblox.Vector3.new(p.size[1], p.size[2], p.size[3])
		part.CFrame = base * roblox.CFrame.new(p.centre[1], p.centre[2], p.centre[3])
		for an, pos in p.attachments or {} do
			local a = roblox.Instance.new("Attachment")
			a.Name = an
			a.Position = roblox.Vector3.new(pos[1], pos[2], pos[3])
			a.Parent = part
		end
		part.Parent = char
	end
	local hum = roblox.Instance.new("Humanoid")
	hum.Parent = char
	char.Parent = self.Workspace
	return char
end

local function lookColors(): { [string]: any }
	return { a = roblox.Color3.fromRGB(255, 210, 70) }
end

-- The weapon step of LookKit.build, as the server runs it: a HeroLook folder, a Weapon folder in it, WeaponKit.build
-- with LookKit's maker and body parts
function WeaponSim:weapon(char: any, look: any): any
	local LookKit = self:module("Shared.LookKit")
	local WeaponKit = self:module("Shared.WeaponKit")
	local folder = char:FindFirstChild("HeroLook")
	if not folder then
		folder = roblox.Instance.new("Folder")
		folder.Name = "HeroLook"
		folder.Parent = char
	end
	local wf = roblox.Instance.new("Folder")
	wf.Name = "Weapon"
	wf.Parent = folder
	-- LookKit's own maker for the part fallback (exposed for the sim as LookKit.make when present)
	local make = LookKit.make
		or function()
			error("LookKit.make is not exposed: the part fallback cannot be simulated")
		end
	WeaponKit.build(char, wf, look, lookColors(), make, LookKit.bodyPart)
	return wf
end

-- A weapon swap as LookService does it: LookKit.clear takes the whole old HeroLook away first
function WeaponSim:rebuild(char: any, look: any): any
	local LookKit = self:module("Shared.LookKit")
	LookKit.clear(char)
	return self:weapon(char, look)
end

return WeaponSim
