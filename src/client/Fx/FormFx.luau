-- FormFx (item 179): what a hero's transformation looks like on every device. Grow and Titan Form only scaled
-- the body (HeroService.setForm: ScaleTo plus the Form attribute); now a giant wears a lit outline in its path
-- colour, bursts out with a dust ring and a thud as the form starts, and its footfalls land with dust, a low
-- thud and a camera shake nearby; a titan's steps knock the street's small things loose underfoot. Numbers:
-- Config.Fx.giant. Per-frame work is a short loop over players under FrameProf "FormFx".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local FrameProf = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FrameProf"))

local AudioController = require(script.Parent.Parent.Controllers.AudioController)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local BuildingFx = require(script.Parent.BuildingFx)
local CombatFx = require(script.Parent.CombatFx)
local FxLib = require(script.Parent.FxLib)
local Juice = require(script.Parent.Juice)
local MeshFix = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MeshFix"))
local PowerMeshes = require(script.Parent.PowerMeshes)

local FormFx = {}

local G = Config.Fx.giant
local player = Players.LocalPlayer
type Giant = { form: string, hl: Highlight?, last: Vector3?, walked: number, left: boolean }
local giants: { [Player]: Giant } = {}

-- the stride a giant of this form takes (studs between footfalls)
function FormFx.stride(form: string): number
	return G.stride * (G.forms[form] or 1)
end

local function rootOf(p: Player): BasePart?
	local char = p.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function shakeNear(at: Vector3, k: number)
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local d = (cam.CFrame.Position - at).Magnitude
	if d < G.shake.range then
		CameraController.shake(G.shake.time, G.shake.amount * k * (1 - d / G.shake.range))
	end
end

local function footfall(p: Player, g: Giant, root: BasePart)
	local scale = G.forms[g.form] or 1
	local side = if g.left then -1 else 1
	g.left = not g.left
	local foot = root.CFrame * CFrame.new(side * 0.5 * scale, -3 * scale, 0)
	local at = foot.Position
	FxLib.dust(at, G.dust * scale * 0.5)
	AudioController.playSpec(Config.Audio.impact.heavy, at, { pitch = G.pitch / math.sqrt(scale) })
	shakeNear(at, scale / 2)
	if scale >= G.crushAt then
		BuildingFx.smashAt(at, 3 * scale) -- benches, bins and lamps underfoot go flying
	end
	if p == player then
		CameraController.punch(0.15 * scale)
	end
end

local function start(p: Player, form: string, root: BasePart?)
	local g: Giant = { form = form, walked = 0, left = false }
	giants[p] = g
	local char = p.Character
	if char then
		local hl = Instance.new("Highlight")
		hl.Name = "GiantForm"
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.OutlineColor = CombatFx.colorOf("Colossus", p.UserId)
		hl.OutlineTransparency = G.outline
		hl.FillColor = hl.OutlineColor
		hl.FillTransparency = G.fill
		hl.Adornee = char
		hl.Parent = char
		g.hl = hl
	end
	if root then
		local scale = G.forms[form] or 1
		local feet = root.Position - Vector3.new(0, 3 * scale, 0)
		FxLib.dust(feet, G.dust * scale)
		Juice.fire("land", feet, { mine = p == player })
		shakeNear(feet, scale)
	end
end

local function stop(p: Player)
	local g = giants[p]
	giants[p] = nil
	if g and g.hl then
		g.hl:Destroy()
	end
end

-- The Mech Suit (item 174): the hero's own body in a mech shell (art/blender/powers.py's Mech look): a chest plate
-- and thruster pack on the torso, armoured sleeves on the lower arms and greaves on the lower legs, each drawn round a
-- unit body part and sized to the real one, welded on, in the hero's path colour at the core. Only once imported
-- (else the form shows as before: the scaled hero).
local MECH = {
	{ part = "UpperTorso", unit = Vector3.new(2, 2, 1), meshes = { "MechChest", "MechCore" } },
	{ part = "LeftLowerArm", unit = Vector3.new(1, 1, 1), meshes = { "MechArm" } },
	{ part = "RightLowerArm", unit = Vector3.new(1, 1, 1), meshes = { "MechArm" }, flip = true },
	{ part = "LeftLowerLeg", unit = Vector3.new(1, 1, 1), meshes = { "MechLeg" } },
	{ part = "RightLowerLeg", unit = Vector3.new(1, 1, 1), meshes = { "MechLeg" } },
}
local mechs: { [Player]: { parts: { BasePart }, char: Model, size: Vector3? } } = {}

local function unmech(p: Player)
	local m = mechs[p]
	mechs[p] = nil
	if m then
		for _, part in m.parts do
			part:Destroy()
		end
	end
end

function FormFx.mech(char: Model, color: Color3): { BasePart }
	local out = {}
	local art = Config.PowerArt.Mech
	for _, slot in MECH do
		local body = char:FindFirstChild(slot.part)
		if body and body:IsA("BasePart") then
			local k = body.Size / slot.unit
			for _, name in slot.meshes do
				local m = art[name]
				local mp = PowerMeshes.part(name, Vector3.new(m.size[1], m.size[2], m.size[3]) * k)
				if mp then
					mp.Anchored = false
					mp.Color = if m.tint then color else Color3.fromRGB(m.color[1], m.color[2], m.color[3])
					mp.Material = (Enum.Material :: any)[m.mat] or Enum.Material.Metal
					local x = if slot.flip then -m.offset[1] else m.offset[1]
					mp.CFrame = body.CFrame
						* CFrame.new(Vector3.new(x, m.offset[2], m.offset[3]) * k)
						* MeshFix.turn("Powers")
					local w = Instance.new("WeldConstraint")
					w.Part0 = body
					w.Part1 = mp
					w.Parent = mp
					mp.Name = "Mech_" .. name
					mp.Parent = char
					table.insert(out, mp)
				end
			end
		end
	end
	return out
end

local function mechStep(p: Player, form: any)
	local char = p.Character
	local want = form == "mech" and char ~= nil and PowerMeshes.ready("Mech")
	local m = mechs[p]
	local torso = char and char:FindFirstChild("UpperTorso")
	local size = if torso and torso:IsA("BasePart") then torso.Size else nil
	-- a new body, or the form's scale arriving after the shell was built (the server scales the body): build again
	if m and (not want or m.char ~= char or m.size ~= size) then
		unmech(p)
		m = nil
	end
	if want and not m and char then
		mechs[p] =
			{ parts = FormFx.mech(char, CombatFx.colorOf("Gadgeteer", p.UserId)), char = char, size = size }
	end
end

local function step()
	for _, p in Players:GetPlayers() do
		mechStep(p, p:GetAttribute("Form"))
		local form = p:GetAttribute("Form")
		local isGiant = type(form) == "string" and G.forms[form] ~= nil
		local g = giants[p]
		local root = rootOf(p)
		if isGiant and (not g or g.form ~= form) then
			stop(p)
			start(p, form :: string, root)
			g = giants[p]
		elseif not isGiant and g then
			stop(p)
			g = nil
		end
		if g and root then
			-- footfalls: every stride walked on the ground (not flying or in the air)
			local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
			local grounded = hum ~= nil and hum.FloorMaterial ~= Enum.Material.Air
			local pos = root.Position
			if g.last and grounded then
				local flat = Vector3.new(pos.X - g.last.X, 0, pos.Z - g.last.Z).Magnitude
				if flat < 20 then -- a teleport is not a walk
					g.walked += flat
				end
				if g.walked >= FormFx.stride(g.form) then
					g.walked = 0
					footfall(p, g, root)
				end
			end
			g.last = pos
		end
	end
end

function FormFx.init()
	Players.PlayerRemoving:Connect(stop)
	Players.PlayerRemoving:Connect(unmech)
	RunService.Heartbeat:Connect(FrameProf.wrap("FormFx", step))
end

return FormFx
