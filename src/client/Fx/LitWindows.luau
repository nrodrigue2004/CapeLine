--!strict
-- LitWindows: the city's windows light up after dusk (shapes-2, 2026-11-19; nate: "World needs to feel way more
-- alive"). A building part in a kit front (MaterialVariant "Kit" .. front, Config.City.kit) near the camera gets,
-- on each side face, an unlit SurfaceGui (LightInfluence 0) tiled with that front's lit picture
-- (Config.Life.lit.images, art/city/litwindows.py): clear but for the glass of about half the windows, warm or TV
-- blue. Shared.LitPlan starts the tiles at the face's centre like the kit texture, so the light sits on the painted
-- glass. Budgets per preset (Config.Life.lit.budget: radius, faces); the nearest faces win. A wrecked building's
-- guis are switched off with it (BuildingFx.setHidden), and every gui goes at dawn. One pass every `every`
-- seconds under FrameProf ("LitWindows").

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local LitPlan = require(Shared:WaitForChild("LitPlan"))
local QualityController = require(script.Parent.Parent.Controllers.QualityController)

local LIT = Config.Life.lit
local LitWindows = {}
LitWindows.faces = 0 -- lit faces now (the Dev panel can show it)

-- every candidate building part, with its front's picture id
local parts: { [BasePart]: number } = {}
-- the parts lit now -> their guis
local lit: { [BasePart]: { SurfaceGui } } = {}

local function imageOf(p: BasePart): number?
	if p.Name ~= "building" and p.Name ~= "tier" then
		return nil
	end
	local v = p.MaterialVariant
	if string.sub(v, 1, 3) ~= "Kit" then
		return nil
	end
	local id = LIT.images[string.sub(v, 4)]
	return if id and id ~= 0 then id else nil
end

local function consider(d: Instance)
	if d:IsA("BasePart") then
		local id = imageOf(d)
		if id then
			parts[d] = id
		end
	end
end

local function unlight(p: BasePart)
	local guis = lit[p]
	if guis then
		for _, g in guis do
			g:Destroy()
		end
		lit[p] = nil
	end
end

local function light(p: BasePart, id: number)
	local guis = {}
	for _, f in LitPlan.faces(p.Size.X, p.Size.Y, p.Size.Z, LIT.minFace) do
		local lay = LitPlan.layout(f.w, f.h, LIT.block, LIT.pps)
		local g = Instance.new("SurfaceGui")
		g.Name = "LitWindows"
		g.Face = (Enum.NormalId :: any)[f.face]
		g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		g.PixelsPerStud = LIT.pps
		g.LightInfluence = 0
		g.Brightness = LIT.brightness
		g.ClipsDescendants = true
		g.MaxDistance = 0
		g.ResetOnSpawn = false
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.BorderSizePixel = 0
		img.Image = "rbxassetid://" .. tostring(id)
		img.ScaleType = Enum.ScaleType.Tile
		img.TileSize = UDim2.fromOffset(lay.tile, lay.tile)
		img.Position = UDim2.fromOffset(lay.x, lay.y)
		img.Size = UDim2.fromOffset(lay.sw, lay.sh)
		img.Parent = g
		g.Adornee = p
		g.Parent = p
		table.insert(guis, g)
	end
	lit[p] = guis
end

local acc = 0
local function step(dt: number)
	acc += dt
	if acc < LIT.every then
		return
	end
	acc = 0
	local night = LitPlan.night(Lighting.ClockTime, LIT.from, LIT.to)
	local b = LIT.budget[QualityController.name] or LIT.budget.medium
	if not night or b.faces <= 0 then
		for p in lit do
			unlight(p)
		end
		LitWindows.faces = 0
		return
	end
	local cam = Workspace.CurrentCamera
	local at = if cam then cam.Focus.Position else Vector3.zero
	-- the nearest parts within the radius, up to the face budget
	local near: { { p: BasePart, d: number } } = {}
	for p in parts do
		if not p.Parent then
			parts[p] = nil
			unlight(p)
			continue
		end
		local d = (p.Position - at).Magnitude - math.max(p.Size.X, p.Size.Z) / 2
		if d < b.radius and p.LocalTransparencyModifier < 1 then
			table.insert(near, { p = p, d = d })
		end
	end
	table.sort(near, function(a, c)
		return a.d < c.d
	end)
	local want: { [BasePart]: boolean } = {}
	local faces = 0
	for _, e in near do
		local n = #LitPlan.faces(e.p.Size.X, e.p.Size.Y, e.p.Size.Z, LIT.minFace)
		if faces + n > b.faces then
			break
		end
		faces += n
		want[e.p] = true
	end
	for p in lit do
		if not want[p] then
			unlight(p)
		end
	end
	for p in want do
		if not lit[p] then
			light(p, parts[p])
		end
	end
	LitWindows.faces = faces
end

function LitWindows.init()
	local any = false
	for _, id in LIT.images do
		if id ~= 0 then
			any = true
		end
	end
	if not any then
		return -- no pictures uploaded: the windows stay as they are
	end
	task.spawn(function()
		local city = Workspace:WaitForChild("City", 120)
		if not city then
			return
		end
		for _, d in city:GetDescendants() do
			consider(d)
		end
		city.DescendantAdded:Connect(consider)
		RunService.Heartbeat:Connect(FrameProf.wrap("LitWindows", step))
	end)
end

return LitWindows
