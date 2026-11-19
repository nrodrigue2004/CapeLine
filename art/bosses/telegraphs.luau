-- telegraphs.luau: the boss pass's render check for the telegraphs (2026-11-19). Runs the game's own
-- src/client/Fx/BossTelegraph.luau headless (Lune's Instances; the effects library, combat effects and the quality
-- preset stubbed), warns each shape the bosses use at 25%, 60% and 95% of its warning, and writes every part it
-- built as JSON; art/bosses/telegraphs.py draws them from above: art/preview/boss_telegraphs.png.
-- Run from the repo root: lune run art/bosses/telegraphs.luau && python3 art/bosses/telegraphs.py
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Instance, CFrame, Vector3, Color3, Enum = roblox.Instance, roblox.CFrame, roblox.Vector3, roblox.Color3, roblox.Enum

-- Lune's CFrame.lookAt points the wrong way for some directions (its -z is flipped); Roblox's is the usual one
local RealCFrame = CFrame
CFrame = setmetatable({
	lookAt = function(at: any, target: any, up: any?)
		local look = (target - at).Unit
		local right = look:Cross(up or Vector3.new(0, 1, 0)).Unit
		return RealCFrame.fromMatrix(at, right, right:Cross(look))
	end,
}, { __index = RealCFrame }) :: any

local clock = 0
local fakeOs = table.clone(os)
fakeOs.clock = function()
	return clock
end
local Random = {}
function Random.new(seed: number)
	local s = math.floor(seed) % 2147483647
	if s <= 0 then
		s = s + 2147483646
	end
	return {
		NextNumber = function(_, a: number, b: number)
			s = (s * 16807) % 2147483647
			return a + (b - a) * (s / 2147483647)
		end,
	}
end
local stub = setmetatable({}, { __index = function()
	return function() end
end })
local mods = {
	CombatFx = { reduceFlashing = false },
	FxLib = setmetatable({ reduceFlashing = false }, { __index = function()
		return function() end
	end }),
	QualityController = { name = "high" },
}
local function fakeScript(): any
	local node
	node = setmetatable({}, {
		__index = function(_, k)
			if mods[k] then
				return mods[k]
			end
			return node
		end,
	})
	return node
end
local game = {
	GetService = function(_, name: string)
		return stub
	end,
}
local env = {
	script = fakeScript(),
	require = function(m: any)
		return m
	end,
	game = game,
	Instance = Instance,
	CFrame = CFrame,
	Vector3 = Vector3,
	Color3 = Color3,
	Enum = Enum,
	Random = Random,
	os = fakeOs,
	TweenInfo = { new = function() end },
}
local BT = luau.load(fs.readFile("src/client/Fx/BossTelegraph.luau"), { debugName = "BossTelegraph", environment = env })()

local Config = require("../../src/config")
local B = Config.Boss.bosses
local function row(id: string, a: string): any
	for _, x in B[id].attacks do
		if x.id == a then
			return x
		end
	end
	error(a)
end

local cases = {
	{ "Stomp (ring)", "RustjawPrime", "Stomp", {} },
	{ "Swipe (cone)", "RustjawPrime", "Swipe", { yaw = 0.4 } },
	{ "Tail Sweep (cone 200)", "LeviathanEngine", "TailSweep", { yaw = 0 } },
	{ "Shard Spikes (circles)", "LumenMaw", "ShardSpikes", { points = { { -40, -30 }, { 10, -60 }, { 45, -20 }, { -10, 30 }, { 50, 40 }, { -55, 25 } } } },
	{ "Eye Laser (lines)", "RustjawPrime", "EyeLaser", { points = { { 0, -1 }, { 0.7, -0.7 }, { -0.8, -0.6 } } } },
	{ "Gravity Pull (pull)", "LumenMaw", "GravityPull", {} },
}
local out = {}
for _, c in cases do
	local atk = row(c[2], c[3])
	local frames = {}
	for _, f in { 0.25, 0.6, 0.95 } do
		local folder = Instance.new("Folder")
		BT.init(folder)
		clock = 100
		local ev = {
			k = "warn",
			shape = atk.shape,
			x = 0,
			y = 0,
			z = 0,
			yaw = c[4].yaw or 0,
			r = atk.r,
			arc = atk.arc,
			width = atk.width,
			length = if atk.length then math.min(atk.length, 140) else nil,
			nova = atk.nova,
			points = c[4].points,
			t = atk.warn,
		}
		BT.warn(ev, 0, Color3.fromRGB(90, 240, 230))
		clock = 100 + atk.warn * f
		BT.step()
		local parts = {}
		for _, p in folder:GetChildren() do
			local cf = p.CFrame
			if p:IsA("WedgePart") then
				local h, l = p.Size.Y / 2, p.Size.Z / 2
				local tri = {}
				for _, v in { Vector3.new(0, -h, -l), Vector3.new(0, -h, l), Vector3.new(0, h, l) } do
					local w = cf * v
					table.insert(tri, { w.X, w.Z })
				end
				table.insert(parts, {
					shape = "tri",
					pos = { cf.Position.X, cf.Position.Y, cf.Position.Z },
					tri = tri,
					color = { p.Color.R, p.Color.G, p.Color.B },
					alpha = 1 - p.Transparency,
				})
				continue
			end
			table.insert(parts, {
				shape = if p.Shape == Enum.PartType.Cylinder then "disc" else "box",
				pos = { cf.Position.X, cf.Position.Y, cf.Position.Z },
				look = { cf.LookVector.X, cf.LookVector.Z },
				size = { p.Size.X, p.Size.Y, p.Size.Z },
				color = { p.Color.R, p.Color.G, p.Color.B },
				alpha = 1 - p.Transparency,
			})
		end
		table.insert(frames, { f = f, parts = parts })
		-- clear what step left (a finished one clears itself; these are mid-warning)
		clock = 1e6
		BT.step()
	end
	local radius = if atk.shape == "circles" then 70 else atk.r or (atk.length and math.min(atk.length, 140)) or 60
	table.insert(out, { name = c[1], radius = radius, frames = frames })
end
fs.writeDir("build")
fs.writeFile("build/boss_telegraphs.json", serde.encode("json", out))
print("wrote build/boss_telegraphs.json")
