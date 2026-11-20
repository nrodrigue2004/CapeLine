-- CapeSway (item 219, spec M11 "a sway tween"): capes move with the hero on every device. LookKit marks the drape
-- pieces Sway (meshes and the box capes alike); here each one's server WeldConstraint is turned off on this device
-- and a local Weld hangs it from a hinge at the collar, swung each frame from the body's own movement: it lifts
-- behind with forward speed and when falling, swings out from sideways movement, ripples at speed and breathes
-- when still. Only heroes within reach of the camera, nearest first, up to Config.Fx.cape.count. FrameProf
-- "CapeSway". Looks only: nothing on the server changes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local FrameProf = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FrameProf"))

local CapeSway = {}

local K = Config.Fx.cape
type Piece = { part: BasePart, weld: Weld, hinge: CFrame }
type Rig = {
	char: Model,
	torso: BasePart,
	pieces: { Piece },
	last: Vector3?,
	lift: number,
	side: number,
	phase: number,
}
local rigs: { [Player]: Rig } = {}
local scanAt = 0

-- the cape's lift and side swing (degrees) toward which it moves, from the torso's velocity in its own frame
-- (fwd: studs/s forward, lat: to the right, up: up) and the time
function CapeSway.target(fwd: number, lat: number, up: number, t: number, phase: number): (number, number)
	local speed = math.sqrt(fwd * fwd + lat * lat + up * up)
	local lift = math.clamp(fwd / K.fast, 0, 1) * K.lift + math.clamp(-up / K.fall, 0, 1) * K.fallLift
	local ripple = math.min(speed / 30, 1) * K.flutter * math.sin(t * (6 + speed / 10) + phase)
	local breath = K.idle * (0.5 + 0.5 * math.sin(t * 1.3 + phase))
	local side = -math.clamp(lat / K.fast, -1, 1) * K.side
	return math.clamp(lift + ripple + breath, 0, K.max), side
end

local function hook(char: Model, torso: BasePart): { Piece }
	local pieces = {}
	-- the collar: the torso's back, near its top
	local hinge = CFrame.new(0, torso.Size.Y * 0.42, torso.Size.Z * 0.5 + 0.05)
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Sway") == true then
			local wc = d:FindFirstChildOfClass("WeldConstraint")
			if wc and wc.Part0 == torso then
				wc.Enabled = false -- this device only; the local weld below holds it instead
				local w = Instance.new("Weld")
				w.Name = "CapeSway"
				w.Part0 = torso
				w.Part1 = d
				local hingeWorld = torso.CFrame * hinge
				w.C0 = hinge
				w.C1 = d.CFrame:ToObjectSpace(hingeWorld)
				w.Parent = d
				table.insert(pieces, { part = d, weld = w, hinge = hinge })
			end
		end
	end
	return pieces
end

local function drop(p: Player)
	local r = rigs[p]
	rigs[p] = nil
	if r then
		for _, pc in r.pieces do
			if pc.weld.Parent then
				pc.weld.C0 = pc.hinge
			end
		end
	end
end

-- which heroes get a swinging cape: those with Sway pieces in reach, nearest first
local function scan(eye: Vector3)
	local near = {}
	for _, p in Players:GetPlayers() do
		local char = p.Character
		local torso = char and char:FindFirstChild("UpperTorso")
		if torso and torso:IsA("BasePart") then
			local d = (torso.Position - eye).Magnitude
			if d <= K.reach then
				table.insert(near, { p = p, d = d, char = char :: Model, torso = torso })
			end
		end
	end
	table.sort(near, function(a, b)
		return a.d < b.d
	end)
	local keep = {}
	for i = 1, math.min(#near, K.count) do
		local n = near[i]
		keep[n.p] = true
		local r = rigs[n.p]
		local stale = r and (r.char ~= n.char or r.torso ~= n.torso)
		if r and not stale then
			for _, pc in r.pieces do
				if not pc.part.Parent then
					stale = true -- the look was rebuilt
					break
				end
			end
		end
		if stale then
			drop(n.p)
			r = nil
		end
		if not r or #r.pieces == 0 then
			-- a new body, or a look rebuilt (its Sway pieces are new): hook what is there now
			local pieces = hook(n.char, n.torso)
			rigs[n.p] = {
				char = n.char,
				torso = n.torso,
				pieces = pieces,
				lift = 0,
				side = 0,
				phase = math.random() * 6,
			}
		end
	end
	for p in rigs do
		if not keep[p] then
			drop(p)
		end
	end
end

local function step(dt: number)
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local now = os.clock()
	if now >= scanAt then
		scanAt = now + 0.5
		scan(cam.CFrame.Position)
	end
	for _, r in rigs do
		if #r.pieces == 0 or not r.torso.Parent then
			continue
		end
		local pos = r.torso.Position
		local v = if r.last and dt > 0 then (pos - r.last) / dt else Vector3.zero
		r.last = pos
		if v.Magnitude > 400 then
			v = Vector3.zero -- a teleport, not a speed
		end
		local cf = r.torso.CFrame
		local lift, side =
			CapeSway.target(v:Dot(cf.LookVector), v:Dot(cf.RightVector), v:Dot(cf.UpVector), now, r.phase)
		local k = math.min(1, dt * K.follow)
		r.lift += (lift - r.lift) * k
		r.side += (side - r.side) * k
		-- lift: the hanging drape (down, behind) swings back and up about the torso's right axis
		local turn = CFrame.Angles(-math.rad(r.lift), 0, math.rad(r.side))
		for _, pc in r.pieces do
			if pc.part.Parent then
				pc.weld.C0 = pc.hinge * turn
			end
		end
	end
end

function CapeSway.init()
	Players.PlayerRemoving:Connect(drop)
	RunService.RenderStepped:Connect(FrameProf.wrap("CapeSway", step))
end

return CapeSway
