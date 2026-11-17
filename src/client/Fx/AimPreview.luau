--!strict
-- AimPreview: the aim shown while a skill or super key is held (hold to aim and charge, overhaul plan step 3).
-- One shape per ability shape, in the power's colour, on your screen only:
--   area   a flat ring around you (novas) or at the aim point (fields, placed things, launches)
--   line   a strip from you along the aim (bolts, lines, chains, dashes, leaps, rides)
--   cone   a fan of rays (cones and arcs)
-- A charge grows it (ChargeRules.apply's size) and brightens it; at full charge it pulses white.
-- PLACEHOLDER ART: neon parts until the effects textures are uploaded.

local Workspace = game:GetService("Workspace")

local AimPreview = {}

local folder: Folder? = nil
local ring: Part? = nil
local strip: Part? = nil
local rays: { Part } = {}
local RAYS = 5
local WHITE = Color3.new(1, 1, 1)

local function make(shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Transparency = 1
	if shape then
		p.Shape = shape
	end
	if not folder or not folder.Parent then
		local f = Instance.new("Folder")
		f.Name = "AimPreview"
		f.Parent = Workspace
		folder = f
	end
	p.Parent = folder
	return p
end

local function parts()
	if not ring or not ring.Parent then
		ring = make(Enum.PartType.Cylinder)
		strip = make()
		rays = {}
		for i = 1, RAYS do
			rays[i] = make()
		end
	end
end

-- which preview an ability shape uses
function AimPreview.kind(shape: string?): string
	if shape == "nova" then
		return "self"
	elseif
		shape == "field"
		or shape == "place"
		or shape == "launch"
		or shape == "wall"
		or shape == "ramp"
	then
		return "area"
	elseif shape == "cone" or shape == "arc" then
		return "cone"
	elseif shape == "buff" then
		return "none"
	end
	return "line"
end

local function hideAll()
	if ring then
		ring.Transparency = 1
	end
	if strip then
		strip.Transparency = 1
	end
	for _, r in rays do
		r.Transparency = 1
	end
end

-- draw it for this frame. origin: your chest; point: the aim point; feet: the ground under you
function AimPreview.draw(
	eff: any,
	origin: Vector3,
	feet: Vector3,
	point: Vector3,
	color: Color3,
	level: number
)
	parts()
	hideAll()
	local kind = AimPreview.kind(eff.shape)
	local pulse = if level >= 1 then 0.5 + 0.5 * math.sin(os.clock() * 14) else 0
	local c = color:Lerp(WHITE, 0.15 + 0.5 * pulse)
	local alpha = 0.72 - 0.25 * level
	local range = eff.range or 40
	local dir = point - origin
	if dir.Magnitude < 0.1 then
		dir = Vector3.new(0, 0, -1)
	end
	if kind == "self" or kind == "area" then
		local r = eff.radius or 10
		local at = feet
		if kind == "area" then
			local flat = Vector3.new(point.X - feet.X, 0, point.Z - feet.Z)
			local d = math.min(flat.Magnitude, range)
			at = feet + (if flat.Magnitude > 0.1 then flat.Unit * d else Vector3.zero)
			at = Vector3.new(at.X, point.Y + 0.2, at.Z)
		end
		local rg = ring :: Part
		rg.Size = Vector3.new(0.15, r * 2, r * 2)
		rg.CFrame = CFrame.new(at + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
		rg.Color = c
		rg.Transparency = alpha + 0.1
	elseif kind == "line" then
		local len = math.min(range, dir.Magnitude)
		local w = math.max(0.6, (eff.width or 1.5) * 0.5)
		local st = strip :: Part
		st.Size = Vector3.new(w, 0.15, len)
		st.CFrame = CFrame.lookAt(origin + dir.Unit * len / 2, origin + dir.Unit * len)
		st.Color = c
		st.Transparency = alpha
	elseif kind == "cone" then
		local f = dir.Unit
		local up = Vector3.new(0, 1, 0)
		local right = f:Cross(up)
		right = if right.Magnitude > 1e-3 then right.Unit else Vector3.new(1, 0, 0)
		local half = math.rad(math.min(eff.cone or 60, 170) / 2)
		for i, r in rays do
			local a = -half + (i - 1) / (RAYS - 1) * half * 2
			local d = (f * math.cos(a) + right * math.sin(a)).Unit
			local len = range
			r.Size = Vector3.new(0.25, 0.1, len)
			r.CFrame = CFrame.lookAt(origin + d * len / 2, origin + d * len)
			r.Color = c
			r.Transparency = alpha
		end
	end
end

function AimPreview.hide()
	hideAll()
end

return AimPreview
