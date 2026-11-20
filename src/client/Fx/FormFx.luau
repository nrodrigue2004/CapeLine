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

local function step()
	for _, p in Players:GetPlayers() do
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
	RunService.Heartbeat:Connect(FrameProf.wrap("FormFx", step))
end

return FormFx
