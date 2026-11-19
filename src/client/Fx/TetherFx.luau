--!strict
-- TetherFx: swing physics for the weapons on a line (the weapons polish pass, 2026-11-19: the Chain Whip, the
-- Yo-yo and the Rope Dart lash out on a rope and the Nunchucks swing round the grip; Shared.TetherMath). For every
-- hero near the camera holding one, the welded line and tip meshes are hidden on this device only
-- (LocalTransparencyModifier) and drawn instead: the line as links along the rope, the tip as local copies of
-- its own meshes riding the end. The rope hangs and lags behind the hand; during an attack (HeroAnimator.actionOf)
-- it pays out along the arm to the move's reach and reels back in, so the swing clips crack it like a whip.
-- Within HeroAnim.nearRange and at most MAX heroes; every frame is timed by FrameProf. Only meshed weapons swing
-- (the part-built fallback stays as it is).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local HeroAnim = require(Shared:WaitForChild("HeroAnim"))
local TetherMath = require(Shared:WaitForChild("TetherMath"))
local FrameProf = require(Shared:WaitForChild("FrameProf"))

local HeroAnimator = require(script.Parent.Parent.Controllers.HeroAnimator)

local TetherFx = {}

local MAX = 6 -- heroes swinging lines at once on this device

type Piece = { part: BasePart, copy: BasePart?, rel: CFrame }
type Rig = {
	char: Model,
	folder: Instance,
	weaponId: number,
	spec: TetherMath.Spec,
	hand: BasePart,
	arm: BasePart?,
	grip: Vector3, -- in the hand's frame
	restTip: Vector3, -- the tip's rest point in the hand's frame
	restLen: number,
	restDir: Vector3, -- grip to tip in the hand's frame
	tips: { Piece },
	lines: { BasePart }, -- the hidden welded line meshes
	links: { BasePart }, -- the drawn rope
	state: TetherMath.State,
}

local rigs: { [Player]: Rig } = {}
local folder: Folder

local function vec(v: Vector3): { number }
	return { v.X, v.Y, v.Z }
end
local function V3(a: { number }): Vector3
	return Vector3.new(a[1], a[2], a[3])
end

local function hide(part: BasePart, on: boolean)
	part.LocalTransparencyModifier = if on then 1 else 0
end

local function release(r: Rig)
	for _, t in r.tips do
		if t.part.Parent then
			hide(t.part, false)
		end
		if t.copy then
			t.copy:Destroy()
		end
	end
	for _, l in r.lines do
		if l.Parent then
			hide(l, false)
		end
	end
	for _, l in r.links do
		l:Destroy()
	end
end

local function weaponOf(char: Model): (Instance?, number?)
	local look = char:FindFirstChild("HeroLook")
	local wf = look and look:FindFirstChild("Weapon")
	local id = wf and wf:GetAttribute("WeaponId")
	if not wf or type(id) ~= "number" or wf:GetAttribute("Meshed") ~= true then
		return nil, nil
	end
	return wf, id
end

local function setup(p: Player, char: Model, wf: Instance, id: number): Rig?
	local spec = TetherMath.SPECS[id]
	local hand = char:FindFirstChild("RightHand")
	if not spec or not (hand and hand:IsA("BasePart")) then
		return nil
	end
	local art = Config.WeaponArt[id]
	local g = art and art.grip and art.grip.pos or { 0, -0.15, 0 }
	local grip = Vector3.new(g[1], g[2], g[3])
	local tips: { Piece } = {}
	local lines: { BasePart } = {}
	local sum, n = Vector3.zero, 0
	for _, part in wf:GetChildren() do
		local mesh = part:GetAttribute("Piece")
		if part:IsA("BasePart") and type(mesh) == "string" then
			local role = TetherMath.role(spec, mesh)
			if role == "tip" then
				local local3 = (hand :: BasePart).CFrame:ToObjectSpace(part.CFrame)
				table.insert(tips, { part = part, copy = nil, rel = local3 })
				sum += local3.Position
				n += 1
			elseif role == "line" then
				table.insert(lines, part)
			end
		end
	end
	if n == 0 then
		return nil
	end
	local restTip = sum / n
	local off = restTip - grip
	local restLen = math.max(0.5, off.Magnitude)
	local restDir = if off.Magnitude > 1e-3 then off.Unit else Vector3.new(0, -1, 0)
	-- the tip's copies (the welded originals stay, hidden here), placed relative to the rest tip point
	for _, t in tips do
		local copy = t.part:Clone()
		for _, c in copy:GetChildren() do
			if c:IsA("WeldConstraint") or c:IsA("Weld") then
				c:Destroy()
			end
		end
		copy.Anchored = true
		copy.CanCollide = false
		copy.CanQuery = false
		copy.CanTouch = false
		copy.Parent = folder
		t.copy = copy
		t.rel = CFrame.new(-restTip) * t.rel
		hide(t.part, true)
	end
	local links: { BasePart } = {}
	if spec.mode == "rope" then
		local color = if lines[1] then lines[1].Color else Color3.fromRGB(200, 200, 210)
		local mat = if lines[1] then lines[1].Material else Enum.Material.Metal
		for _ = 1, spec.segs do
			local l = Instance.new("Part")
			l.Name = "TetherLink" -- PLACEHOLDER ART: plain links until a rope mesh
			l.Anchored = true
			l.CanCollide = false
			l.CanQuery = false
			l.CanTouch = false
			l.CastShadow = false
			l.Color = color
			l.Material = mat
			l.Size = Vector3.new(spec.width, spec.width, 0.5)
			l.Parent = folder
			table.insert(links, l)
		end
		for _, l in lines do
			hide(l, true)
		end
	end
	local anchor = (hand :: BasePart).CFrame:PointToWorldSpace(grip)
	local r: Rig = {
		char = char,
		folder = wf,
		weaponId = id,
		spec = spec,
		hand = hand :: BasePart,
		arm = char:FindFirstChild("RightUpperArm") :: BasePart?,
		grip = grip,
		restTip = restTip,
		restLen = restLen,
		restDir = restDir,
		tips = tips,
		lines = lines,
		links = links,
		state = TetherMath.new(spec, vec(anchor), restLen),
	}
	rigs[p] = r
	return r
end

-- the rotation that turns unit vector a onto unit vector b
local function between(a: Vector3, b: Vector3): CFrame
	local axis = a:Cross(b)
	local dot = math.clamp(a:Dot(b), -1, 1)
	if axis.Magnitude < 1e-5 then
		if dot > 0 then
			return CFrame.identity
		end
		local side = if math.abs(a.X) < 0.9 then Vector3.xAxis else Vector3.yAxis
		return CFrame.fromAxisAngle(a:Cross(side).Unit, math.pi)
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
end

local function draw(p: Player, r: Rig, dt: number)
	local hand = r.hand.CFrame
	local anchor = hand:PointToWorldSpace(r.grip)
	-- an attack pays the line out along the arm (from the shoulder through the hand)
	local clip, t, dur = HeroAnimator.actionOf(p)
	local u = if clip and dur > 0 and t < dur then t / dur else nil
	local length = TetherMath.lengthAt(r.spec, r.restLen, u)
	local aim = nil
	if u then
		local from = if r.arm then r.arm.Position else hand.Position + Vector3.new(0, 1, 0)
		local d = anchor - from
		aim = if d.Magnitude > 1e-3 then vec(d.Unit) else nil
	end
	TetherMath.step(r.state, r.spec, vec(anchor), aim, length, dt)
	local pts = r.state.p
	for i, l in r.links do
		local a, b = V3(pts[i]), V3(pts[i + 1])
		local mid = (a + b) / 2
		local len = (b - a).Magnitude
		l.Size = Vector3.new(r.spec.width, r.spec.width, math.max(0.05, len + r.spec.width))
		l.CFrame = if len > 1e-4 then CFrame.lookAt(mid, b) else CFrame.new(mid)
	end
	local tipPos, tipDir = TetherMath.tip(r.state)
	local rot = hand.Rotation
	local turn = between(rot:VectorToWorldSpace(r.restDir), V3(tipDir))
	local at = CFrame.new(V3(tipPos)) * turn * rot
	for _, tp in r.tips do
		if tp.copy then
			tp.copy.CFrame = at * tp.rel
			tp.copy.LocalTransparencyModifier = tp.part.Transparency >= 1 and 1 or 0
		end
	end
end

local function step(dt: number)
	local cam = Workspace.CurrentCamera
	local eye = cam and cam.CFrame.Position or Vector3.zero
	local live = 0
	for _, p in Players:GetPlayers() do
		local char = p.Character
		local r = rigs[p]
		local wf, id = nil, nil
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local near = root ~= nil
			and root:IsA("BasePart")
			and (root.Position - eye).Magnitude <= HeroAnim.nearRange
		if char and near and live < MAX and p:GetAttribute("Held") == "weapon" then
			wf, id = weaponOf(char)
		end
		if r and (r.char ~= char or r.folder ~= wf or r.weaponId ~= id or not r.hand.Parent) then
			release(r)
			rigs[p] = nil
			r = nil
		end
		if not r and wf and id and TetherMath.SPECS[id] then
			r = setup(p, char :: Model, wf, id)
		end
		if r then
			live += 1
			draw(p, r, dt)
		end
	end
end

function TetherFx.init()
	folder = Instance.new("Folder")
	folder.Name = "TetherFx"
	folder.Parent = Workspace
	-- after the animation is written (PreSimulation) the hands are where they are drawn
	RunService.RenderStepped:Connect(FrameProf.wrap("TetherFx", step))
	Players.PlayerRemoving:Connect(function(p)
		local r = rigs[p]
		if r then
			release(r)
			rigs[p] = nil
		end
	end)
end

return TetherFx
