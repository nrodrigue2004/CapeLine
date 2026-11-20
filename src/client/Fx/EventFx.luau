--!strict
-- EventFx: the city events' looks on this device (the boss pass, 2026-11-19; split from WorldFx, which drew the
-- surge as one glass slab and the Blackout as a colour correction). The server's EventService is the truth; this
-- only draws Event.State.
-- * Tidal surge (the Docks): the flood water still rises over the first half and sits lower the more citizens are
--   saved; on it, waves roll in from the harbour basin across the district one after another: a curved front of
--   sea-blue rollers with a white foam lip, bowed forward in the middle, foam and spray particles thrown off the
--   crest (FxLib). Lower and gentler as citizens are saved; it fades in from the sea and out on the far side.
-- * Blackout (Old Town, for whoever stands in it): a deep blue-black dark, and in it the Lumen Maw's eyes: pairs of
--   glowing slit eyes that open round the hero at a distance, look on, blink and close again elsewhere, with motes of
--   light drifting off toward them as the dark eats the light. Fewer as generators come back on.
-- Reduce flashing: the eyes fade in and out slowly and never blink; colourblind-safe (nothing here is told by
-- colour alone). Cheap: counts per device preset (QualityController), nothing drawn while the camera is far from
-- the event's district; one loop, profiled (FrameProf "EventFx").

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local FrameProf = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FrameProf"))

local WorldClient = require(script.Parent.Parent.Controllers.WorldClient)
local QualityController = require(script.Parent.Parent.Controllers.QualityController)
local CombatFx = require(script.Parent.CombatFx)
local FxLib = require(script.Parent.FxLib)
local PowerMeshes = require(script.Parent.PowerMeshes)
local MeshFix = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MeshFix"))

local EventFx = {}

local folder: Instance
local SEA = Color3.fromRGB(46, 128, 196)
local FOAM = Color3.fromRGB(236, 248, 255)
local WATER = Color3.fromRGB(60, 140, 200)
local EYE = Color3.fromRGB(90, 240, 230) -- the Maw's light (Config.BossArt.LumenMaw theme)
local UP = Vector3.new(0, 1, 0)
local SURGE = {
	period = 9, -- seconds for one wave to cross the district
	waves = 2, -- waves on the water at once
	height = 7, -- a full wave's roller height (studs over the water)
	bow = 60, -- how far the front's middle leads its ends
	segments = { low = 4, medium = 6, high = 8 },
	far = 1400, -- no waves drawn while the camera is further than this from the Docks' middle
}
local DARK = {
	eyes = { low = 3, medium = 4, high = 6 },
	near = 45,
	far = 95,
	life = { 3.5, 6 }, -- seconds a pair stays
	fade = 0.6,
}

local function flashy(): boolean
	return not (CombatFx.reduceFlashing or FxLib.reduceFlashing)
end

local function part(size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	if shape then
		p.Shape = shape
	end
	p.Parent = folder
	return p
end

local function heroPos(): Vector3?
	local char = Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root and root.Position
end

local function inDistrict(name: string): boolean
	local p = heroPos()
	local d = Config.City.districts[name]
	return p ~= nil and p.X >= d.minX and p.X <= d.maxX and p.Z >= d.minZ and p.Z <= d.maxZ
end

local function eventOf(id: string): { [string]: any }?
	for _, ev in WorldClient.events do
		if ev.id == id and ev.state == 0 then
			return ev
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- The Tidal surge
---------------------------------------------------------------------------

type Wave = { rollers: { BasePart }, foam: { BasePart }, offset: number, meshed: boolean }
local water: Part? = nil
local waves: { Wave } = {}
local nextSpray = 0
local bulkParts: { BasePart } = {}
local bulkCFs: { CFrame } = {}

local function clearSurge()
	if water then
		water:Destroy()
		water = nil
	end
	for _, w in waves do
		for _, p in w.rollers do
			p:Destroy()
		end
		for _, p in w.foam do
			p:Destroy()
		end
	end
	table.clear(waves)
end

local function buildWaves()
	local n = SURGE.segments[QualityController.name] or SURGE.segments.medium
	-- each roller a breaking wave with its foam crest in the Blender look (Art.Powers Wave, the Tsunami's;
	-- Everything Left 248) once it is imported; cylinders before that
	local meshed = PowerMeshes.ready("Wave")
	for k = 1, SURGE.waves do
		local w: Wave = { rollers = {}, foam = {}, offset = (k - 1) / SURGE.waves, meshed = meshed }
		for _ = 1, n do
			if meshed then
				local r = PowerMeshes.part("WaveWater")
				local f = PowerMeshes.part("WaveFoam")
				if r and f then
					r.Color, r.Material, r.Transparency = SEA, Enum.Material.Glass, 0.3
					f.Color, f.Material, f.Transparency = FOAM, Enum.Material.SmoothPlastic, 0.1
					r.Parent, f.Parent = folder, folder
					table.insert(w.rollers, r)
					table.insert(w.foam, f)
					continue
				end
			end
			local r =
				part(Vector3.one, CFrame.identity, SEA, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
			r.Transparency = 0.3
			table.insert(w.rollers, r)
			local f =
				part(Vector3.one, CFrame.identity, FOAM, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
			f.Transparency = 0.1
			table.insert(w.foam, f)
		end
		table.insert(waves, w)
	end
end

local function surgeStep(ev: { [string]: any }, now: number)
	local def = Config.Events.events.TidalSurge
	local d = Config.City.districts.Docks
	local gy = Config.City.ground.y
	local cx, cz = (d.minX + d.maxX) / 2, (d.minZ + d.maxZ) / 2
	local f = math.clamp(1 - (ev.ends - os.clock()) / def.length, 0, 1)
	-- the flood rises over the first half and holds; the more citizens saved, the lower it sits
	local saved = if ev.need > 0 then ev.have / ev.need else 0
	local h = def.rise * math.min(1, f * 2) * (1 - saved * 0.5)
	if not water then
		local wp = part(
			Vector3.new(d.maxX - d.minX, 1, d.maxZ - d.minZ),
			CFrame.new(cx, gy - 1, cz),
			WATER,
			Enum.Material.Glass
		)
		wp.Name = "SurgeWater"
		wp.Transparency = 0.45
		water = wp
	end
	local wp = water :: Part
	wp.Size = Vector3.new(wp.Size.X, math.max(0.2, h), wp.Size.Z)
	wp.CFrame = CFrame.new(cx, gy - 0.5 + h / 2, cz)
	local cam = Workspace.CurrentCamera
	if cam and (cam.CFrame.Position - Vector3.new(cx, gy, cz)).Magnitude > SURGE.far then
		for _, w in waves do
			for _, p in w.rollers do
				p.Transparency = 1
			end
			for _, p in w.foam do
				p.Transparency = 1
			end
		end
		return
	end
	if #waves == 0 then
		buildWaves()
	end
	-- the waves roll from the harbour (the district's sea edge, +z) toward the warehouses (-z)
	local top = gy - 0.5 + h
	local waveH = SURGE.height * (0.45 + 0.55 * math.min(1, f * 3)) * (1 - saved * 0.6)
	local width = d.maxX - d.minX
	local depth = d.maxZ - d.minZ
	table.clear(bulkParts)
	table.clear(bulkCFs)
	for _, w in waves do
		local k = ((now / SURGE.period) + w.offset) % 1
		local zf = d.maxZ - depth * k
		-- fade in off the sea and out at the far side
		local fade = math.clamp(math.min(k / 0.12, (1 - k) / 0.15), 0, 1)
		local n = #w.rollers
		local seg = width / n
		for i, r in w.rollers do
			local x0 = d.minX + seg * (i - 1)
			local x1 = x0 + seg
			local function zAt(x: number): number
				local u = (x - cx) / (width / 2)
				return zf - SURGE.bow * (1 - u * u)
			end
			local a = Vector3.new(x0, top, zAt(x0))
			local b = Vector3.new(x1, top, zAt(x1))
			local mid = (a + b) / 2
			local along = (b - a).Unit
			local len = (b - a).Magnitude * 1.08
			local fwd = along:Cross(UP).Unit -- toward -z (the way it rolls)
			if fwd.Z > 0 then
				fwd = -fwd
			end
			-- a cylinder's axis is its X: lay it along the front
			local frame = CFrame.fromMatrix(mid, along, UP)
			if w.meshed then
				-- the breaking wave: its curl (-z) toward the way it rolls, its foam riding the crest
				local A = Config.PowerArt.Wave
				local WW, WF = A.WaveWater, A.WaveFoam
				local kx, ky, kz = len / WW.size[1], waveH * 2 / WW.size[2], waveH * 1.4 / WW.size[3]
				local face = if along:Cross(UP):Dot(fwd) > 0
					then CFrame.Angles(0, math.pi, 0)
					else CFrame.identity
				local base = frame * face
				local turn = MeshFix.turn("Powers")
				r.Size = Vector3.new(WW.size[1] * kx, WW.size[2] * ky, WW.size[3] * kz)
				table.insert(bulkParts, r)
				table.insert(bulkCFs, base * CFrame.new(0, waveH * 0.75, WW.offset[3] * kz) * turn)
				r.Transparency = 1 - (0.7 * fade)
				local fo = w.foam[i]
				fo.Size = Vector3.new(WF.size[1] * kx, WF.size[2] * ky, WF.size[3] * kz)
				table.insert(bulkParts, fo)
				table.insert(
					bulkCFs,
					base
						* CFrame.new(WF.offset[1] * kx, waveH * 0.75 + WF.offset[2] * ky, WF.offset[3] * kz)
						* turn
				)
				fo.Transparency = 1 - (0.9 * fade)
				continue
			end
			r.Size = Vector3.new(len, waveH * 2, waveH * 2)
			table.insert(bulkParts, r)
			table.insert(bulkCFs, frame + UP * (waveH * 0.15))
			r.Transparency = 1 - (0.7 * fade)
			local fo = w.foam[i]
			fo.Size = Vector3.new(len, waveH * 0.7, waveH * 0.7)
			table.insert(bulkParts, fo)
			table.insert(bulkCFs, frame + UP * (waveH * 0.95) + fwd * (waveH * 0.55))
			fo.Transparency = 1 - (0.9 * fade)
		end
		-- spray off the crest
		if fade > 0.5 and now >= nextSpray then
			nextSpray = now + 0.2
			local x = d.minX + math.random() * width
			local u = (x - cx) / (width / 2)
			local at = Vector3.new(x, top + waveH * 1.1, zf - SURGE.bow * (1 - u * u))
			FxLib.emit("smoke", FOAM, at, 1, Vector3.new(0, 0.6, -1))
			FxLib.emit("bubble", FOAM, at, 2, Vector3.new(0, 1, -0.5))
		end
	end
	Workspace:BulkMoveTo(bulkParts, bulkCFs, Enum.BulkMoveMode.FireCFrameChanged)
end

---------------------------------------------------------------------------
-- The Blackout
---------------------------------------------------------------------------

type Eyes = { parts: { Part }, born: number, life: number, at: Vector3, blinkAt: number }
local dim: ColorCorrectionEffect? = nil
local eyes: { Eyes } = {}
local nextMote = 0

local function closeEyes()
	for _, e in eyes do
		for _, p in e.parts do
			p:Destroy()
		end
	end
	table.clear(eyes)
end

-- one pair of slit eyes somewhere round the hero, looking at it
local function openEyes(hp: Vector3, now: number): Eyes
	local a = math.random() * math.pi * 2
	local r = DARK.near + math.random() * (DARK.far - DARK.near)
	local at = hp + Vector3.new(math.cos(a) * r, 6 + math.random() * 22, math.sin(a) * r)
	local size = 1 + math.random() * 0.8
	local e: Eyes = {
		parts = {},
		born = now,
		life = DARK.life[1] + math.random() * (DARK.life[2] - DARK.life[1]),
		at = at,
		blinkAt = now + 1 + math.random() * 2,
	}
	for _ = 1, 2 do
		local p = part(Vector3.new(2.6 * size, 0.7 * size, 0.3), CFrame.new(at), EYE, Enum.Material.Neon)
		p.Transparency = 1
		table.insert(e.parts, p)
	end
	return e
end

local function eyesStep(e: Eyes, hp: Vector3, now: number): boolean
	local t = now - e.born
	if t > e.life then
		for _, p in e.parts do
			p:Destroy()
		end
		return false
	end
	local vis = math.clamp(math.min(t / DARK.fade, (e.life - t) / DARK.fade), 0, 1)
	local squint = 1
	if flashy() and now >= e.blinkAt then
		-- a slow blink (never with Reduce flashing)
		local b = now - e.blinkAt
		if b > 0.3 then
			e.blinkAt = now + 1.5 + math.random() * 2.5
		else
			squint = math.abs(b - 0.15) / 0.15
		end
	end
	local look = CFrame.lookAt(e.at, Vector3.new(hp.X, e.at.Y, hp.Z))
	for i, p in e.parts do
		local s = if i == 1 then -1 else 1
		-- angry slits tilted in toward the middle, the Maw's look
		p.CFrame = look * CFrame.new(s * 1.9 * p.Size.X / 2.6, 0, 0) * CFrame.Angles(0, 0, math.rad(-s * 14))
		p.Size = Vector3.new(p.Size.X, math.max(0.08, 0.7 * (p.Size.X / 2.6) * squint), 0.3)
		p.Transparency = 1 - vis
	end
	return true
end

local function blackoutStep(ev: { [string]: any }?, now: number)
	local dark = ev ~= nil and inDistrict("OldTown")
	local lit = if ev then math.clamp((ev.have or 0) / math.max(1, ev.need or 4), 0, 1) else 1
	if dark and not dim then
		local c = Instance.new("ColorCorrectionEffect")
		c.Name = "Blackout"
		c.Brightness = 0
		c.Parent = Lighting
		dim = c
	end
	local c = dim
	if c then
		-- deep and blue-black; each generator back on lifts it a little
		local want = if dark then -0.3 + 0.14 * lit else 0
		c.Brightness += (want - c.Brightness) * 0.08
		c.Saturation = c.Brightness * 1.6
		c.Contrast = -c.Brightness * 0.4
		c.TintColor = Color3.new(1, 1, 1)
			:Lerp(Color3.fromRGB(150, 165, 255), math.clamp(-c.Brightness * 3, 0, 1))
		if not dark and math.abs(c.Brightness) < 0.01 then
			c:Destroy()
			dim = nil
		end
	end
	local hp = heroPos()
	if not (dark and hp) then
		closeEyes()
		return
	end
	local hero = hp :: Vector3
	local want = math.floor((DARK.eyes[QualityController.name] or DARK.eyes.medium) * (1 - lit * 0.6) + 0.5)
	for i = #eyes, 1, -1 do
		if not eyesStep(eyes[i], hero, now) then
			table.remove(eyes, i)
		end
	end
	if #eyes < want then
		table.insert(eyes, openEyes(hero, now))
	end
	-- light motes drift off the hero toward the eyes in the dark
	if #eyes > 0 and now >= nextMote then
		nextMote = now + 0.35
		local e = eyes[math.random(1, #eyes)]
		local from = hero + Vector3.new(math.random(-8, 8), math.random(1, 6), math.random(-8, 8))
		FxLib.emit("wisp", EYE, from, 1, (e.at - from).Unit)
		FxLib.emit("star", EYE, from, 1, (e.at - from).Unit)
	end
end

function EventFx.init(parent: Instance)
	folder = parent
	local acc = 0
	RunService.RenderStepped:Connect(FrameProf.wrap("EventFx", function(dt)
		local now = os.clock()
		local surge = eventOf("TidalSurge")
		if surge then
			surgeStep(surge, now)
		elseif water or #waves > 0 then
			clearSurge()
		end
		acc += dt
		if acc >= 1 / 30 then
			acc = 0
			blackoutStep(eventOf("Blackout"), now)
		end
	end))
end

return EventFx
