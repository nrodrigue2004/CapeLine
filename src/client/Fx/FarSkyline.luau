--!strict
-- FarSkyline: the city's buildings from far away on this device (2026-11-21, nate's playtest: "i can see the boss and
-- i can see the park from really far but not the buildings or skyscrapers. Thats way more importnat"). The hub's
-- chunks stream (StreamingEnabled, Atomic models), so a building past the streaming radius was not there at all. For
-- every hub building (Shared.SkylinePlan, from ReplicatedStorage.SkylineInfo) this device keeps a stand-in: its body
-- and crown boxes in their own kit texture and colour plus a few window bands (glass by day, lit Neon after dusk), all
-- anchored with no collisions, queries, touches or shadows. A stand-in shows only while its real model is NOT streamed
-- in (BuildingFx.present) and the building has not collapsed; a Damaged building's stand-in is cut to what still
-- stands and loses its crown with the top storey (BuildingFx.standing). Budget per preset (Config.Presets far: the part
-- cap and the bands a building); built a few parts a frame, rebuilt on a preset change. Event driven
-- (BuildingFx.onChange) with a pass every Config.City.far.every seconds for day and night.

local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local SkylinePlan = require(Shared:WaitForChild("SkylinePlan"))
local LitPlan = require(Shared:WaitForChild("LitPlan"))
local QualityController = require(script.Parent.Parent.Controllers.QualityController)
local BuildingFx = require(script.Parent.BuildingFx)

local F = Config.City.far
local KIT = Config.City.kit
local LIT = Config.Life.lit
local WHITE = Color3.new(1, 1, 1)

local FarSkyline = {}
FarSkyline.parts = 0 -- stand-in parts built now (the Dev panel can show it)
FarSkyline.shown = 0 -- buildings whose stand-in shows now

type Stand = {
	rec: SkylinePlan.Rec,
	model: Model?,
	look: string?, -- the standing top and crown the model was built for
	bands: { BasePart },
}

local stands: { [number]: Stand } = {}
local folder: Folder? = nil
local share: { [number]: number } = {}
local dirty: { [number]: boolean } = {}
local allDirty = true
local night = false
local generation = 0

local colorCache: { [string]: Color3 } = {}
local function color(key: string?): Color3
	if not key then
		return WHITE
	end
	local c = colorCache[key]
	if not c then
		local rgb = Config.City.palette[key] or { 158, 156, 150 }
		c = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
		colorCache[key] = c
	end
	return c
end

local kitFound: { [string]: boolean } = {}
local function kitHas(name: string): boolean
	local found = kitFound[name]
	if found == nil then
		local v = MaterialService:FindFirstChild("Kit" .. name)
		found = v ~= nil and v:IsA("MaterialVariant")
		kitFound[name] = found
	end
	return found
end

local DAY = Color3.fromRGB(F.dayColor[1], F.dayColor[2], F.dayColor[3])
local NIGHT = Color3.fromRGB(F.nightColor[1], F.nightColor[2], F.nightColor[3])

local function bandLook(p: BasePart)
	if night then
		p.Material = Enum.Material.Neon
		p.Color = NIGHT
		p.Transparency = F.nightTransparency
	else
		p.Material = Enum.Material.SmoothPlastic
		p.Color = DAY
		p.Transparency = 0
	end
end

-- One stand-in box, the way CityBuilder's makePart dresses the real one (kit texture and tint, else its colour)
local function makeBox(o: SkylinePlan.Out): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Name = "far_" .. o.kind
	local turn = CFrame.Angles(0, math.rad(o.ry), 0)
	if o.round then
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(o.sy, o.sx, o.sz)
		p.CFrame = CFrame.new(o.cx, o.cy, o.cz) * turn * CFrame.Angles(0, 0, math.rad(90))
	else
		p.Size = Vector3.new(o.sx, o.sy, o.sz)
		p.CFrame = CFrame.new(o.cx, o.cy, o.cz) * turn
	end
	if o.kind == "band" then
		bandLook(p)
	elseif o.kind == "glow" then
		p.Material = Enum.Material.Neon
		p.Color = color(o.color)
	elseif o.kit and kitHas(o.kit) then
		p.Material = (Enum.Material :: any)[KIT.baseMaterial[o.kit]] or Enum.Material.SmoothPlastic
		p.MaterialVariant = "Kit" .. o.kit
		p.Color = if KIT.landmark[o.kit] or KIT.tinted[o.kit] == nil then WHITE else color(o.tint or o.color)
	else
		p.Material = Enum.Material.SmoothPlastic
		p.Color = color(o.color)
	end
	return p
end

local function drop(s: Stand)
	if s.model then
		FarSkyline.parts -= #s.model:GetChildren()
		s.model:Destroy()
		s.model = nil
	end
	s.look = nil
	s.bands = {}
end

-- Bring one building's stand-in up to date: shown or not, and built for what still stands
local function update(s: Stand): number
	local id = s.rec.id
	local st, top, crown = BuildingFx.standing(id)
	if not SkylinePlan.shows(BuildingFx.present(id), st) then
		if s.model and s.model.Parent then
			s.model.Parent = nil
			FarSkyline.shown -= 1
		end
		return 0
	end
	local look = string.format("%.1f/%s", if st == 0 then s.rec.top else top, tostring(crown))
	local made = 0
	if s.look ~= look then
		local wasShown = s.model ~= nil and s.model.Parent ~= nil
		drop(s)
		if wasShown then
			FarSkyline.shown -= 1
		end
		local m = Instance.new("Model")
		m.Name = "Far_" .. id
		local boxes = SkylinePlan.boxes(s.rec, share[id] or 0, if st == 0 then s.rec.top else top, crown, F)
		for _, o in boxes do
			local p = makeBox(o)
			if o.kind == "band" then
				table.insert(s.bands, p)
			end
			p.Parent = m
		end
		made = #boxes
		FarSkyline.parts += made
		s.model = m
		s.look = look
	end
	local m = s.model :: Model
	if not m.Parent then
		m.Parent = folder
		FarSkyline.shown += 1
	end
	return made
end

local function pass()
	local gen = generation
	local budget = F.build
	local list: { Stand } = {}
	if allDirty then
		allDirty = false
		table.clear(dirty)
		for _, s in stands do
			table.insert(list, s)
		end
	else
		for id in dirty do
			local s = stands[id]
			if s then
				table.insert(list, s)
			end
		end
		table.clear(dirty)
	end
	for _, s in list do
		if gen ~= generation then
			return
		end
		budget -= update(s)
		if budget <= 0 then
			RunService.Heartbeat:Wait() -- a few parts a frame, so a whole skyline never hitches
			budget = F.build
		end
	end
end

local function rebudget()
	generation += 1
	local far = (QualityController.preset :: any).far or Config.Presets.medium.far
	local recs = {}
	for _, s in stands do
		table.insert(recs, s.rec)
	end
	share = SkylinePlan.budget(recs, far)
	for _, s in stands do
		local shown = s.model ~= nil and s.model.Parent ~= nil
		drop(s)
		if shown then
			FarSkyline.shown -= 1
		end
	end
	allDirty = true
end

local function setNight(on: boolean)
	if on == night then
		return
	end
	night = on
	for _, s in stands do
		for _, p in s.bands do
			bandLook(p)
		end
	end
end

function FarSkyline.init()
	if not (F and F.on) then
		return
	end
	task.spawn(function()
		local value = ReplicatedStorage:WaitForChild("SkylineInfo", 120)
		if not (value and value:IsA("StringValue")) then
			return
		end
		while value.Value == "" do
			value.Changed:Wait()
		end
		local ok, data = pcall(HttpService.JSONDecode, HttpService, value.Value)
		if not ok then
			return
		end
		for _, r in SkylinePlan.unpack(data) do
			stands[r.id] = { rec = r, bands = {} }
		end
		local f = Instance.new("Folder")
		f.Name = "FarSkyline"
		f.Parent = Workspace
		folder = f
		night = LitPlan.night(Lighting.ClockTime, LIT.from, LIT.to)
		rebudget()
		BuildingFx.onChange = function(id: number)
			if id == 0 then
				allDirty = true
			else
				dirty[id] = true
			end
		end
		QualityController.Changed:Connect(rebudget)
		while true do
			setNight(LitPlan.night(Lighting.ClockTime, LIT.from, LIT.to))
			if allDirty or next(dirty) ~= nil then
				pass()
			end
			task.wait(F.every)
		end
	end)
end

return FarSkyline
