-- GadgetFx: the gadgets' looks on every screen (gap polish 2026-11-19; they were a plain disc or a pop and the
-- decoy had no body). GadgetClient calls one per use, for your own and everyone else's.
-- * Smoke Bomb: a real smoke cloud of effects-library puffs (FxLib "cloud") over the blinded radius, topped up
--   every Config.Fx.polish.smoke.puffEvery while the blind lasts (PolishPlan.smokePuffs/smokeSpots), a darker
--   rim, and a shockwave ring where it bursts (medium and high).
-- * Decoy: a hologram copy of the owner's real body and look (Preview.clone, the same copy the creator and HQ
--   use: their LookKit look with its catalog face and hair as the hero wears them, nothing of ours), frozen in
--   the pose they had, flickering (PolishPlan.flicker) with a blue glow on medium and high, then a pop of
--   sparks when it ends. No copy can be made (the owner is gone or streamed out): the old field disc.
-- * Shield Drone: a small drone (a body, a spinning rotor ring and a lamp; low draws the body only) circling
--   the owner (PolishPlan.droneAt) with a shield bubble round them while the shield lasts, then a pop.
-- One Heartbeat loop moves the decoys and drones while any is out (FrameProf "GadgetFx"); nothing else runs.
-- Budgets per device preset: Config.Fx.polish.presets. Looks only: the server's gadget rules are untouched.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local PolishPlan = require(Shared:WaitForChild("PolishPlan"))

local CombatFx = require(script.Parent.CombatFx)
local FxLib = require(script.Parent.FxLib)
local Preview = require(script.Parent.Parent.Ui.Preview)
local QualityController = require(script.Parent.Parent.Controllers.QualityController)

local GadgetFx = {}

local P = Config.Fx.polish
local G = Config.Gear.gadgets

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function budget(): any
	return P.presets[QualityController.name] or P.presets.medium
end

local folder: Folder? = nil
local function holder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "GadgetFx"
	f.Parent = Workspace
	folder = f
	return f
end

local function bit(size: Vector3, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = material
	if shape then
		p.Shape = shape
	end
	return p
end

---------------------------------------------------------------------------
-- the live decoys and drones (one loop while any is out)
---------------------------------------------------------------------------

type Live = {
	kind: string,
	start: number,
	dur: number,
	model: Model?,
	parts: { BasePart }?,
	owner: Player?,
	body: BasePart?,
	rotor: BasePart?,
	bubble: BasePart?,
	at: Vector3,
	done: boolean,
}
local live: { Live } = {}
local conn: RBXScriptConnection? = nil

local function pop(at: Vector3, color: Color3)
	FxLib.emit("spark", color, at, 14)
	FxLib.emit("glow", color, at, 1)
	CombatFx.buffPop(at, "Comic", color)
end

local function finish(l: Live)
	l.done = true
	if l.kind == "decoy" then
		pop(l.at, rgb(P.decoy.popColor))
	elseif l.kind == "drone" then
		local b = l.body
		if b then
			FxLib.emit("spark", rgb(P.drone.color), b.Position, 8)
		end
	end
	if l.model then
		l.model:Destroy()
	end
end

local function rootOf(p: Player?): BasePart?
	local char = p and p.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function update()
	local now = os.clock()
	for i = #live, 1, -1 do
		local l = live[i]
		local t = now - l.start
		if t >= l.dur or not (l.model and l.model.Parent) then
			table.remove(live, i)
			if not l.done then
				finish(l)
			end
		elseif l.kind == "decoy" then
			local a = PolishPlan.flicker(t, l.dur, P.decoy.flickerFrom)
			for _, part in l.parts :: { BasePart } do
				part.LocalTransparencyModifier = a
			end
		elseif l.kind == "drone" then
			local root = rootOf(l.owner)
			if not root then
				table.remove(live, i)
				finish(l)
			else
				local D = P.drone
				local x, y, z = PolishPlan.droneAt(t, D.radius, D.height, D.spin)
				local here = root.Position
				l.at = here
				local spot = here + Vector3.new(x, y, z)
				local body = l.body :: BasePart
				body.CFrame = CFrame.lookAt(spot, here + Vector3.new(0, D.height, 0))
				local rotor = l.rotor
				if rotor then
					rotor.CFrame = CFrame.new(spot + Vector3.new(0, 0.55, 0))
						* CFrame.Angles(0, t * 20, math.rad(90))
				end
				local bubble = l.bubble
				if bubble then
					local pulse = 1 + 0.03 * math.sin(t * 6)
					local fade = math.clamp((l.dur - t) / 0.5, 0, 1)
					bubble.CFrame = CFrame.new(here)
					bubble.Size = Vector3.one * D.bubble * 2 * pulse * math.min(1, t * 5)
					bubble.Transparency = 1 - 0.45 * fade
				end
			end
		end
	end
	if #live == 0 and conn then
		conn:Disconnect()
		conn = nil
	end
end

local function add(l: Live)
	table.insert(live, l)
	if not conn then
		conn = RunService.Heartbeat:Connect(FrameProf.wrap("GadgetFx", update))
	end
end

---------------------------------------------------------------------------
-- the three gadgets
---------------------------------------------------------------------------

-- Smoke Bomb at `at` (the thrower's root): the cloud over the blinded radius while the blind lasts
function GadgetFx.smoke(at: Vector3, seed: number?)
	local row = G.SmokeBomb
	local S = P.smoke
	local b = budget()
	local base = at - Vector3.new(0, 1.5, 0)
	local color, edge = rgb(S.color), rgb(S.edge)
	if b.smokeRing > 0 then
		FxLib.shock(base - Vector3.new(0, 1, 0), row.radius, color)
	end
	FxLib.dust(base, row.radius * 0.6, color)
	local s = seed or math.floor(at.X * 7 + at.Z * 13)
	for k, t in PolishPlan.smokePuffs(row.blind, S.puffEvery) do
		task.delay(t, function()
			for i, spot in PolishPlan.smokeSpots(b.smoke, row.radius * 0.85, s + k * 101) do
				local rim = i % 3 == 0
				FxLib.emit(
					"cloud",
					if rim then edge else color,
					base + Vector3.new(spot[1], 1 + spot[3] * 2, spot[2]),
					1
				)
			end
		end)
	end
end

-- Decoy at `at`, a hologram of owner's body for dur seconds (false when no copy could be made)
function GadgetFx.decoy(owner: Player?, at: Vector3, dur: number): boolean
	local char = owner and owner.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not char or not root then
		return false
	end
	local ok, copy = pcall(Preview.clone, char, true)
	if not ok or not copy then
		return false
	end
	local model = copy :: Model
	model.Name = "Decoy"
	local parts: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			if d.Name ~= "HumanoidRootPart" then
				table.insert(parts, d)
			end
		elseif d:IsA("Trail") or d:IsA("Highlight") then
			d:Destroy()
		end
	end
	local mroot = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if mroot then
		model.PrimaryPart = mroot
	end
	model:PivotTo(CFrame.new(at) * root.CFrame.Rotation)
	if budget().decoyGlow then
		local h = Instance.new("Highlight")
		h.FillColor = rgb(P.decoy.color)
		h.FillTransparency = 0.72
		h.OutlineColor = rgb(P.decoy.color)
		h.OutlineTransparency = 0.15
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = model
	end
	model.Parent = holder()
	FxLib.emit("glow", rgb(P.decoy.color), at, 1)
	add({
		kind = "decoy",
		start = os.clock(),
		dur = dur,
		model = model,
		parts = parts,
		at = at,
		done = false,
	})
	return true
end

-- Shield Drone: a little drone circling owner and a bubble round them for the shield's time
function GadgetFx.drone(owner: Player?, dur: number): boolean
	local root = rootOf(owner)
	if not root then
		return false
	end
	local D = P.drone
	local color = rgb(D.color)
	local model = Instance.new("Model")
	model.Name = "ShieldDrone"
	local body = bit(Vector3.new(1.1, 0.8, 1.1), Color3.fromRGB(235, 240, 248), Enum.Material.SmoothPlastic)
	body.Name = "Body"
	body.Parent = model
	local lamp = bit(Vector3.new(0.5, 0.3, 0.2), color, Enum.Material.Neon)
	lamp.Name = "Lamp"
	-- the lamp rides on the body (welded to it, so moving the body moves it)
	local rotor: BasePart? = nil
	if budget().droneBits then
		local r = bit(
			Vector3.new(0.12, 2.2, 2.2),
			Color3.fromRGB(60, 70, 90),
			Enum.Material.Metal,
			Enum.PartType.Cylinder
		)
		r.Name = "Rotor"
		r.Transparency = 0.35
		r.Parent = model
		rotor = r
		lamp.Anchored = false
		local w = Instance.new("WeldConstraint")
		lamp.CFrame = body.CFrame * CFrame.new(0, 0, -0.55)
		w.Part0 = body
		w.Part1 = lamp
		w.Parent = lamp
		lamp.Parent = model
	end
	local bubble = bit(Vector3.one, color, Enum.Material.ForceField, Enum.PartType.Ball)
	bubble.Name = "Bubble"
	bubble.Transparency = 1
	bubble.Parent = model
	model.Parent = holder()
	FxLib.emit("glow", color, root.Position, 1)
	add({
		kind = "drone",
		start = os.clock(),
		dur = dur,
		model = model,
		owner = owner,
		body = body,
		rotor = rotor,
		bubble = bubble,
		at = root.Position,
		done = false,
	})
	return true
end

-- End a hero's drone early (its shield broke: your own, from State)
function GadgetFx.endDrone(owner: Player?)
	for i = #live, 1, -1 do
		local l = live[i]
		if l.kind == "drone" and l.owner == owner then
			table.remove(live, i)
			finish(l)
		end
	end
end

-- the decoy fallback (no body to copy): the old soft field disc
function GadgetFx.field(at: Vector3, dur: number, style: string)
	CombatFx.field(at, 4, dur, style, rgb(P.decoy.color), false)
end

return GadgetFx
