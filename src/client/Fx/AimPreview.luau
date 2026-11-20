--!strict
-- AimPreview: the aim shown while a skill or super key is held (hold to aim and charge, overhaul plan step 3).
-- One shape per ability shape, in the power's colour, on your screen only:
--   area   a flat ring around you (novas) or at the aim point (fields, placed things, launches)
--   line   a strip from you along the aim (bolts, lines, chains, dashes, leaps, rides)
--   cone   a fan of rays (cones and arcs)
-- A charge grows it (ChargeRules.apply's size) and brightens it; at full charge it pulses white.
-- While a skill charges (or a super is aimed) the path's own charge motes orbit the hand, closing in and
-- growing as the charge fills, with the element's charge particles (overhaul plan step 6; Config.Fx.paths).
-- Art (Everything Left 389, 2026-11-20): the ring is a drawn ground marker (a double rim, ticks and four inward
-- arrows) and the line and cone strips tile a glowing chevron that scrolls outward (art/ui/aim_ui.py,
-- Config.Ui.aimArt), each a Decal or Texture tinted the power's colour on a see-through flat part; the neon parts
-- come back only while an id is 0.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local CombatFx = require(script.Parent.CombatFx)
local FxLib = require(script.Parent.FxLib)

local AimPreview = {}

local folder: Folder? = nil
local ring: Part? = nil
local strip: Part? = nil
local rays: { Part } = {}
local RAYS = 5
local WHITE = Color3.new(1, 1, 1)
local moteList: { CombatFx.Mote } = {}
local moteSet: string? = nil
local nextCharge = 0
local ART = Config.Ui.aimArt
local ringArt = ART and ART.ring and ART.ring > 0
local chevArt = ART and ART.chevron and ART.chevron > 0
-- the chevrons' picture top toward the aim (Config.Ui.aimArt.turn flips the strips if Studio shows them inward)
local TURN = if ART and ART.turn then CFrame.Angles(0, math.pi, 0) else CFrame.identity
AimPreview.art = { ring = ringArt, chevron = chevArt }

local function dropMotes()
	if #moteList > 0 then
		CombatFx.dropMotes(moteList)
	end
	moteList = {}
	moteSet = nil
end

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

-- the drawn picture on a flat part's top: a Decal (the ring) or a tiled Texture (the chevron strips)
local function dress(p: Part, kind: string)
	if kind == "ring" then
		local d = Instance.new("Decal")
		d.Name = "AimArt"
		d.Face = Enum.NormalId.Top
		d.Texture = "rbxassetid://" .. tostring(ART.ring)
		d.Parent = p
	else
		local t = Instance.new("Texture")
		t.Name = "AimArt"
		t.Face = Enum.NormalId.Top
		t.Texture = "rbxassetid://" .. tostring(ART.chevron)
		t.StudsPerTileV = ART.tile
		t.Parent = p
	end
end

local function parts()
	if not ring or not ring.Parent then
		ring = make(if ringArt then nil else Enum.PartType.Cylinder)
		if ringArt then
			dress(ring :: Part, "ring")
		end
		strip = make()
		if chevArt then
			dress(strip :: Part, "chevron")
		end
		rays = {}
		for i = 1, RAYS do
			rays[i] = make()
			if chevArt then
				dress(rays[i], "chevron")
			end
		end
	end
end

-- show a part: its picture tinted (the part itself stays clear), or the neon part
local function show(p: Part, c: Color3, alpha: number, width: number?)
	local art = p:FindFirstChild("AimArt")
	if art and (art:IsA("Decal") or art:IsA("Texture")) then
		p.Transparency = 1
		art.Color3 = c
		art.Transparency = math.max(0, alpha - ART.clearer)
		if art:IsA("Texture") then
			art.StudsPerTileU = width or 1
			-- scroll outward along the aim
			art.OffsetStudsV = (os.clock() * ART.scroll) % ART.tile
		end
	else
		p.Color = c
		p.Transparency = alpha
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
	local function off(p: Part?)
		if not p then
			return
		end
		p.Transparency = 1
		local art = p:FindFirstChild("AimArt")
		if art and (art:IsA("Decal") or art:IsA("Texture")) then
			art.Transparency = 1
		end
	end
	off(ring)
	off(strip)
	for _, r in rays do
		off(r)
	end
end

-- draw it for this frame. origin: your chest; point: the aim point; feet: the ground under you
function AimPreview.draw(
	eff: any,
	origin: Vector3,
	feet: Vector3,
	point: Vector3,
	color: Color3,
	level: number,
	style: string?
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
		if ringArt then
			rg.Size = Vector3.new(r * 2, 0.1, r * 2)
			rg.CFrame = CFrame.new(at + Vector3.new(0, 0.12, 0))
		else
			rg.Size = Vector3.new(0.15, r * 2, r * 2)
			rg.CFrame = CFrame.new(at + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
		end
		show(rg, c, alpha + 0.1)
	elseif kind == "line" then
		local len = math.min(range, dir.Magnitude)
		local w = math.max(0.6, (eff.width or 1.5) * 0.5)
		local st = strip :: Part
		st.Size = Vector3.new(w, 0.15, len)
		st.CFrame = CFrame.lookAt(origin + dir.Unit * len / 2, origin + dir.Unit * len) * TURN
		show(st, c, alpha, w)
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
			local rw = if chevArt then ART.rayWidth else 0.25
			r.Size = Vector3.new(rw, 0.1, len)
			r.CFrame = CFrame.lookAt(origin + d * len / 2, origin + d * len) * TURN
			show(r, c, alpha, rw)
		end
	end
	-- the path's charge motes around the hand while it charges (a super's aim holds them half-gathered)
	local gather = if level > 0 then level elseif eff.slot == "super" then 0.6 else 0
	if gather > 0 then
		if moteSet ~= eff.set then
			dropMotes()
			moteList = CombatFx.motes(eff.set, style or "Comic", color)
			moteSet = eff.set
		end
		local hand = origin + dir.Unit * 1.5
		CombatFx.placeMotes(moteList, eff.set, hand, gather, os.clock())
		local now = os.clock()
		if now >= nextCharge then
			nextCharge = now + 0.25
			FxLib.charge(hand, eff.set, color)
		end
	elseif #moteList > 0 then
		dropMotes()
	end
end

function AimPreview.hide()
	hideAll()
	dropMotes()
end

return AimPreview
