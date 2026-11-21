--!strict
-- CamClear (nate's playtest 2026-11-21: "cameras get stuck in things... cutscenes get glitchy going through walls
-- and objects constantly"): keeps every scripted camera (cutscene shots, the prologue's follow camera) clear.
-- * Only the big, still world blocks a camera: anchored parts at least Config.Cinema.camera.clear.minSize studs
--   across. Cars, people, robots, debris and small props never pull a camera in (they are skipped and the ray
--   goes on), so a passing car can no longer snap a shot into a hero's back.
-- * A shot whose camera sits behind a wall is pulled in front of it at once (never a frame inside a building)
--   and eased back out slowly once the wall is passed, so a camera sliding past a corner glides out again.
-- * Moving things right at the lens (citizens, hub vehicles, other heroes) are faded out on this device only
--   while a scene runs, so the camera is never seen from inside a car or a person.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local CamClear = {}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local MOVING = { "Citizens", "Enemies", "CityLife", "ParkLife", "Debris", "Rubble" }

local function C(): any
	return Config.Cinema.camera.clear
end

-- Is this hit part a still, big piece of the world a camera may not pass through?
function CamClear.blocks(p: BasePart): boolean
	if not p.Anchored or p.Transparency > 0.9 or not p.CanCollide then
		return false
	end
	local s = p.Size
	return math.max(s.X, s.Y, s.Z) >= C().minSize
end

local function baseExclude(extra: { Instance }?): { Instance }
	local list: { Instance } = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	for _, name in MOVING do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	local city = Workspace:FindFirstChild("City")
	local cars = city and city:FindFirstChild("Vehicles")
	if cars then
		table.insert(list, cars)
	end
	if extra then
		for _, e in extra do
			table.insert(list, e)
		end
	end
	return list
end

-- The first big still surface between from and to, skipping anything that moves or is small; nil when clear
function CamClear.cast(from: Vector3, to: Vector3, extra: { Instance }?): RaycastResult?
	local list = baseExclude(extra)
	local origin = from
	local left = to - from
	for _ = 1, C().tries do
		if left.Magnitude < 0.05 then
			return nil
		end
		rayParams.FilterDescendantsInstances = list
		local hit = Workspace:Raycast(origin, left, rayParams)
		if not hit then
			return nil
		end
		if CamClear.blocks(hit.Instance) then
			return hit
		end
		table.insert(list, hit.Instance)
		local went = (hit.Position - origin).Magnitude
		local unit = left.Unit
		origin = hit.Position
		left = unit * math.max(0, left.Magnitude - went)
	end
	return nil
end

-- Where the camera may stand on the line from look toward at: at itself when clear, else just in front of the
-- first wall (never closer than clear.near studs to the subject)
function CamClear.spot(look: Vector3, at: Vector3, extra: { Instance }?): Vector3
	local gap = at - look
	if gap.Magnitude < 0.5 then
		return at
	end
	local hit = CamClear.cast(look, at, extra)
	if not hit then
		return at
	end
	local d = math.max(C().near, (hit.Position - look).Magnitude - C().pad)
	return look + gap.Unit * math.min(d, gap.Magnitude)
end

-- Eased pull-in: a state table per camera keeps the distance so a wall glides the camera in and out
export type Pull = { dist: number? }
function CamClear.newPull(): Pull
	return { dist = nil }
end

function CamClear.ease(state: Pull, look: Vector3, at: Vector3, dt: number, extra: { Instance }?): Vector3
	local gap = at - look
	local want = gap.Magnitude
	if want < 0.5 then
		state.dist = nil
		return at
	end
	local free = (CamClear.spot(look, at, extra) - look).Magnitude
	local d = state.dist or free
	if free < d then
		d = free -- in at once: never stand behind the wall
	else
		d += (free - d) * math.min(1, dt * C().outRate)
	end
	d = math.min(d, want)
	state.dist = d
	return look + gap.Unit * d
end

-- Fade moving things right at the lens on this device (a scene's camera never sits inside a car or a person)
local faded: { [BasePart]: number } = {}
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include

function CamClear.fadeNear(at: Vector3?)
	local keep: { [BasePart]: boolean } = {}
	if at then
		local include: { Instance } = {}
		for _, name in { "Citizens", "Enemies" } do
			local f = Workspace:FindFirstChild(name)
			if f then
				table.insert(include, f)
			end
		end
		local city = Workspace:FindFirstChild("City")
		local cars = city and city:FindFirstChild("Vehicles")
		if cars then
			table.insert(include, cars)
		end
		for _, p in Players:GetPlayers() do
			if p ~= Players.LocalPlayer and p.Character then
				table.insert(include, p.Character)
			end
		end
		overlap.FilterDescendantsInstances = include
		for _, p in Workspace:GetPartBoundsInRadius(at, C().fade, overlap) do
			keep[p] = true
			if faded[p] == nil then
				faded[p] = p.LocalTransparencyModifier
				p.LocalTransparencyModifier = 1
			end
		end
	end
	for p, was in faded do
		if not keep[p] then
			if p.Parent then
				p.LocalTransparencyModifier = was
			end
			faded[p] = nil
		end
	end
end

return CamClear
