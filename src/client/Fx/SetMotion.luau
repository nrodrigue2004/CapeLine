-- SetMotion (list-combat 2026-11-20, Everything Left 215 and 216): the set pieces that stood still now move on
-- every device. The toy shop's train runs round its ring and the music box's dancer turns, the gala's chandelier
-- sways under the canopy, the Pit's fans hop and cheer, and the cat stuck on the crane swishes its tail and looks
-- round while it waits. The server's meshes are anchored; each device moves its own copy locally (nothing is sent),
-- from the pose the server gave, and lets go of a piece the moment the server moves it itself (the chandelier
-- dropping when it breaks, the cat picked up and carried). Numbers: Config.Fx.setMotion. Only pieces within reach
-- of the camera move; the loop runs under FrameProf "SetMotion".

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local FrameProf = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FrameProf"))

local SetMotion = {}

local M = Config.Fx.setMotion
type Mover = {
	part: BasePart,
	base: CFrame,
	row: { [string]: any },
	hinge: number,
	phase: number,
	last: CFrame?,
}
local movers: { [BasePart]: Mover } = {}
type Cat = {
	model: Model,
	parts: { [string]: BasePart }?,
	base: { [BasePart]: CFrame },
	last: { [BasePart]: CFrame },
}
local cats: { [Model]: Cat } = {}

-- the mesh's height above its look's foot (Config.SetPieceArt), so a sway hinges at the look's own hook
local heightOf: { [string]: number } = {}
for _, look in Config.SetPieceArt do
	if type(look) == "table" then
		for name, m in look do
			if type(m) == "table" and type(m.offset) == "table" and heightOf[name] == nil then
				heightOf[name] = m.offset[2]
			end
		end
	end
end

-- The pose of one mover at time t (pure CFrame maths on its base)
function SetMotion.pose(row: { [string]: any }, base: CFrame, t: number, phase: number, hinge: number): CFrame
	local pos = base.Position
	local turn = base - pos
	local cf = base
	if row.spin then
		cf = CFrame.new(pos) * CFrame.Angles(0, row.spin * t, 0) * turn
	end
	if row.bob then
		cf += Vector3.new(0, row.bob * math.sin((t * row.rate + phase) * math.pi * 2), 0)
	end
	if row.cheer then
		cf += Vector3.new(0, row.cheer * math.abs(math.sin((t * row.rate + phase) * math.pi)), 0)
	end
	if row.sway then
		local w = (t / row.period + phase) * math.pi * 2
		local a = math.rad(row.sway)
		local pivot = CFrame.new(pos + Vector3.new(0, hinge, 0))
		cf = pivot * CFrame.Angles(a * math.sin(w), 0, a * 0.6 * math.cos(w * 0.83)) * pivot:Inverse() * cf
	end
	return cf
end

local function phaseOf(p: Vector3): number
	return ((math.floor(p.X) * 73 + math.floor(p.Z) * 151) % 97) / 97
end

local function track(inst: Instance)
	if inst:IsA("BasePart") then
		local row = M.meshes[inst.Name]
		if row and inst.Anchored and not movers[inst] then
			local base = inst.CFrame
			local h = if row.hinge then row.hinge - (heightOf[inst.Name] or 0) else 0
			movers[inst] = { part = inst, base = base, row = row, hinge = h, phase = phaseOf(base.Position) }
		end
	elseif inst:IsA("Model") and inst.Name == "Cat" and not cats[inst] then
		cats[inst] = { model = inst, base = {}, last = {} }
	end
end

-- The cat's pieces by their sizes (SiteKit's box cat: body, head, two ears, tail), once all are there
local function catParts(model: Model): { [string]: BasePart }?
	local out: { [string]: BasePart } = {}
	local ears = 0
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") then
			local s = p.Size
			if math.abs(s.Z - 1.6) < 0.05 and s.X < 0.3 then
				out.tail = p
			elseif math.abs(s.X - 1.1) < 0.05 then
				out.head = p
			elseif math.abs(s.Y - 0.5) < 0.05 and s.X < 0.35 then
				ears += 1
				out["ear" .. ears] = p
			elseif math.abs(s.Z - 2.2) < 0.05 then
				out.body = p
			end
		end
	end
	return if out.tail and out.head and out.body and ears == 2 then out else nil
end

local function moved(p: BasePart, last: CFrame?): boolean
	return not p.Anchored or (last ~= nil and (p.CFrame.Position - last.Position).Magnitude > 0.01)
end

local parts: { BasePart } = {}
local frames: { CFrame } = {}

local function catStep(c: Cat, t: number, out: (BasePart, CFrame) -> ())
	local cp = c.parts
	if not cp then
		cp = catParts(c.model)
		if not cp then
			return
		end
		c.parts = cp
		for _, p in cp do
			c.base[p] = p.CFrame
		end
	end
	for _, p in cp do
		if moved(p, c.last[p]) then
			cats[c.model] = nil -- picked up: the server has it now
			return
		end
	end
	local C = M.cat
	local phase = phaseOf(c.base[cp.body].Position)
	-- the tail swishes about its root, the head looks round now and then, the body breathes
	local tail = c.base[cp.tail]
	local root = (tail * CFrame.new(0, 0, -0.8)).Position
	local swish = math.rad(C.tail) * math.sin((t * C.tailRate + phase) * math.pi * 2)
	local pivot = CFrame.new(root)
	out(cp.tail, pivot * CFrame.Angles(0, swish, 0) * pivot:Inverse() * tail)
	local look = math.sin((t / C.headEvery + phase) * math.pi * 2)
	look = math.sign(look) * math.min(1, math.abs(look) * 2.5) -- holds a look, then turns
	local head = c.base[cp.head]
	local hp = CFrame.new(head.Position)
	local turn = hp * CFrame.Angles(0, math.rad(C.head) * look, 0) * hp:Inverse()
	for _, key in { "head", "ear1", "ear2" } do
		local p = cp[key]
		out(p, turn * c.base[p])
	end
	local body = c.base[cp.body]
	local b = 1 + C.breathe * math.sin(t * math.pi * 2 * 0.4)
	out(cp.body, body + Vector3.new(0, (b - 1) * 0.5, 0))
end

local function step()
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local at = cam.CFrame.Position
	local t = Workspace:GetServerTimeNow()
	table.clear(parts)
	table.clear(frames)
	local n = 0
	local function out(p: BasePart, cf: CFrame)
		n += 1
		parts[n] = p
		frames[n] = cf
	end
	for p, m in movers do
		if not p.Parent or moved(p, m.last) then
			movers[p] = nil -- gone, or the server moved it (a chandelier falling): let go
		elseif n < M.max and (p.Position - at).Magnitude < M.reach then
			local cf = SetMotion.pose(m.row, m.base, t, m.phase, m.hinge)
			m.last = cf
			out(p, cf)
		end
	end
	for model, c in cats do
		if not model.Parent then
			cats[model] = nil
		elseif model.PrimaryPart and (model.PrimaryPart.Position - at).Magnitude < M.reach then
			local before = n
			catStep(c, t, out)
			for i = before + 1, n do
				c.last[parts[i]] = frames[i]
			end
		end
	end
	if n > 0 then
		Workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function SetMotion.init()
	for _, d in Workspace:GetDescendants() do
		track(d)
	end
	Workspace.DescendantAdded:Connect(track)
	RunService.Heartbeat:Connect(FrameProf.wrap("SetMotion", step))
end

return SetMotion
