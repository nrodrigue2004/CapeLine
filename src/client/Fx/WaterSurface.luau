--!strict
-- WaterSurface: the city's pools, ponds and fountains ripple (shapes-2, 2026-11-19; nate: "pools need to look better
-- as well"). CityBuilder tiles the uploaded ripple picture twice on each water part's top (tag LifeWater,
-- Config.Life.shapes.water); this drifts the two layers in different directions on the water near the camera, so
-- the light on the surface moves. Cheap: a texture offset a frame for the few pools in range, under FrameProf
-- ("WaterSurface").

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local FrameProf = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FrameProf"))

local W = Config.Life.shapes.water
local WaterSurface = {}

local near: { BasePart } = {}
local scan = 0
local t = 0

local function step(dt: number)
	t += dt
	scan -= dt
	if scan <= 0 then
		scan = 1
		table.clear(near)
		local cam = Workspace.CurrentCamera
		local at = if cam then cam.Focus.Position else Vector3.zero
		for _, p in CollectionService:GetTagged("LifeWater") do
			if p:IsA("BasePart") and (p.Position - at).Magnitude < W.radius then
				table.insert(near, p)
			end
		end
	end
	local a = t * W.drift
	for _, p in near do
		local k = 0
		for _, tex in p:GetChildren() do
			if tex:IsA("Texture") then
				k += 1
				if k == 1 then
					tex.OffsetStudsU = a
					tex.OffsetStudsV = a * 0.4
				else
					tex.OffsetStudsU = -a * 0.7
					tex.OffsetStudsV = a * 0.9
				end
			end
		end
	end
end

function WaterSurface.init()
	if W.image == 0 then
		return -- no ripple picture uploaded: the water stays as it is
	end
	RunService.Heartbeat:Connect(FrameProf.wrap("WaterSurface", step))
end

return WaterSurface
