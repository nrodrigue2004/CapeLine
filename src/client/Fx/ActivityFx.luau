-- ActivityFx: the looks of the 2026-11-17 events that need one on the device. The Harbour fog ambush
-- (Config.Events.HarbourFog.fog) rolls fog banks over the Docks around a hero standing in them and greys the
-- colours a little; it fades out when the event ends or the hero leaves. Lighting fog and the Atmosphere
-- are left alone (DeepClient owns them underwater). The banks are art/blender/activity.py's ActFog puffs once
-- ReplicatedStorage.Art.Activity holds them (Shared.ActivityKit.FOG), else plain translucent balls (the fallback).
-- It also drives ActivityProps (the incident, event and contract props' Blender looks) twice a second.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local EventPlan = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EventPlan"))
local ActivityKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ActivityKit"))

local ActivityProps = require(script.Parent.ActivityProps)

local WorldClient = require(script.Parent.Parent.Controllers.WorldClient)

local ActivityFx = {}

local BANKS = 10
local folder: Folder? = nil
local banks: { BasePart } = {}
local grade: ColorCorrectionEffect? = nil
local amount = 0 -- 0 clear to 1 full fog

local function fogEvent(): any
	for _, ev in WorldClient.events do
		local def = ev.id and Config.Events.events[ev.id]
		if def and def.fog and ev.state == 0 then
			return def
		end
	end
	return nil
end

-- Is the hero inside one of the event's areas?
local function inside(def: any, p: Vector3): boolean
	for _, a in EventPlan.areas(Config, def.where) do
		if math.abs(p.X - a.x) <= a.hx and math.abs(p.Z - a.z) <= a.hz then
			return true
		end
	end
	return false
end

local function build()
	local f = Instance.new("Folder")
	f.Name = "ActivityFog"
	f.Parent = workspace
	folder = f
	-- the ActFog puffs once imported (one mesh, the ball's 90 x 16 x 90), else a plain ball
	local puff = if ActivityProps.ready(ActivityKit.FOG)
		then ActivityKit.meshes(Config, { look = ActivityKit.FOG, boxes = {} })[1]
		else nil
	for i = 1, BANKS do
		local p: BasePart
		local mesh = puff and ActivityProps.clone(puff)
		if mesh then
			p = mesh
		else
			local ball = Instance.new("Part")
			ball.Shape = Enum.PartType.Ball
			ball.Size = Vector3.new(90, 16, 90)
			ball.Material = Enum.Material.SmoothPlastic
			ball.Color = Color3.fromRGB(215, 222, 230)
			p = ball
		end
		p.Name = "FogBank" .. i
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Transparency = 1
		p.Parent = f
		table.insert(banks, p)
	end
	local c = Instance.new("ColorCorrectionEffect")
	c.Name = "HarbourFog"
	c.Parent = Lighting
	grade = c
end

local function step(dt: number)
	local char = Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local def = fogEvent()
	local want = if def and root and inside(def, root.Position) then 1 else 0
	amount += (want - amount) * math.min(1, dt * 0.8)
	if amount < 0.01 and want == 0 then
		if folder then
			folder:Destroy()
			folder = nil
			table.clear(banks)
		end
		if grade then
			grade:Destroy()
			grade = nil
		end
		amount = 0
		return
	end
	if not folder then
		build()
	end
	local at = if root then root.Position else Vector3.zero
	local t = os.clock()
	for i, p in banks do
		-- banks drift in a slow ring round the hero
		local a = i / BANKS * math.pi * 2 + t * 0.03
		local r = 45 + (i % 3) * 25
		p.CFrame =
			CFrame.new(at.X + math.cos(a) * r, Config.City.ground.y + 4 + (i % 2) * 5, at.Z + math.sin(a) * r)
		p.Transparency = 1 - 0.45 * amount
	end
	if grade then
		grade.Saturation = -0.35 * amount
		grade.Contrast = -0.15 * amount
		grade.Brightness = 0.04 * amount
	end
end

function ActivityFx.init()
	local acc = 0
	local props = 0
	RunService.Heartbeat:Connect(FrameProf.wrap("ActivityFx", function(dt)
		acc += dt
		if acc >= 0.1 then
			step(acc)
			acc = 0
			props += 1
			if props >= 5 then
				props = 0
				ActivityProps.step()
			end
		end
	end))
end

return ActivityFx
