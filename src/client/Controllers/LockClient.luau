-- LockClient: lock-on (nate's playtest 2026-11-19: "a player/enemy lock-on... camera should have dynamic
-- movement"; nate decided BOTH, each a setting). Rules in Shared.LockRules, numbers in Config.Combat.lock.
-- * Soft lock (Settings softLock, on by default): your casts take the best target in front within soft.range
--   (CombatClient.lockAim), and while you leave the camera alone it eases its yaw toward that target.
-- * Hard lock (Settings hardLock): Lock (middle mouse, a tap of R3, the LOCK button) locks the best target in
--   front or lets go; held (padHold) or Tab, or the right stick flicked sideways, moves it to the next target.
--   While locked the camera keeps the target framed: a smooth orbit round the hero toward it, the look point
--   between the two so the hero stays on screen, pulled back for big targets (bosses), a shoulder offset, and a
--   lean and sway with your sideways motion scaled by Settings "Camera motion" (Off removes them). The body faces
--   the target (MoveController.lockAt), so the stick strafes and backpedals round it. A lock drops when the
--   target dies, goes past hard.keep or is hidden behind buildings for hard.lost.
-- * Targets: drawn robots (not cloaked or disguised), the world boss, and flagged players only while PvP allows
--   the hit (PvpClient.targets).
-- * The marker: comic corner brackets round the target, thin white for the soft lock, red, turning and
--   breathing with a diamond over it for the hard lock (LockRules.marker; preview art/preview/lock_marker.png).
-- The candidate list is rebuilt at 10 Hz; the per-frame work is a few small tables (FrameProf'd).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local LockRules = require(Shared:WaitForChild("LockRules"))
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local InputController = require(script.Parent.InputController)
local MoveController = require(script.Parent.MoveController)
local CameraController = require(script.Parent.CameraController)
local CombatClient = require(script.Parent.CombatClient)
local EnemyRenderer = require(script.Parent.EnemyRenderer)
local PvpClient = require(script.Parent.PvpClient)
local WorldFx = require(script.Parent.Parent.Fx.WorldFx)

local LockClient = {}

local K = Config.Combat.lock
local M = K.marker
local BOSS = -1 -- the world boss's candidate id (its hit parts carry their own target ids)
local player = Players.LocalPlayer

LockClient.softOn = true -- Settings softLock
LockClient.hardOn = true -- Settings hardLock
LockClient.Changed = Signal.new() -- (locked) the hard lock took a target or let go

type Cand = LockRules.Cand & { pvp: boolean? }
local cands: { Cand } = {}
local lastScan = 0
local hardId: number? = nil
local hardPos: Vector3? = nil
local hardSize = 6
local hiddenFor = 0
local lastSight = 0
local softId: number? = nil
local softPos: Vector3? = nil
local lockPressAt = 0
local ourYaw: number? = nil -- the camera's yaw after our own turn last frame (to tell the player's turns apart)
local idle = 0
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

local function rootPart(): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

-- Every target the lock may take, rebuilt at 10 Hz
local function scan()
	table.clear(cands)
	for id, pos in EnemyRenderer.each() do
		table.insert(cands, { id = id, x = pos.X, y = pos.Y, z = pos.Z, size = 6 })
	end
	local bp, bh = WorldFx.bossFocus()
	if bp then
		table.insert(cands, { id = BOSS, x = bp.X, y = bp.Y, z = bp.Z, size = bh })
	end
	for _, t in PvpClient.targets() do
		table.insert(cands, { id = t.id, x = t.pos.X, y = t.pos.Y, z = t.pos.Z, size = 6, pvp = true })
	end
end

-- The live position of a candidate (between scans: the drawn robot's, the boss's or the player's own)
local function livePos(id: number): (Vector3?, number)
	if id == BOSS then
		return WorldFx.bossFocus()
	end
	local pos = EnemyRenderer.lockable(id)
	if pos then
		return pos, 6
	end
	for _, t in PvpClient.targets() do
		if t.id == id then
			return t.pos, 6
		end
	end
	return nil, 0
end

local function camState(): LockRules.Cam
	local cf = Workspace.CurrentCamera.CFrame
	local l = cf.LookVector
	return { x = cf.Position.X, y = cf.Position.Y, z = cf.Position.Z, lx = l.X, ly = l.Y, lz = l.Z }
end

local function heroState(root: BasePart): LockRules.P3
	local p = root.Position
	return { x = p.X, y = p.Y, z = p.Z }
end

local function setHard(id: number?)
	if hardId == id then
		return
	end
	hardId = id
	hiddenFor = 0
	if not id then
		hardPos = nil
		MoveController.lockAt = nil
	end
	LockClient.Changed:Fire(id ~= nil)
end

function LockClient.locked(): boolean
	return hardId ~= nil
end

-- The hard lock's target now: position, candidate id (0 for the boss: its parts carry their own ids), size
function LockClient.hard(): (Vector3?, number, number)
	if not hardId or not hardPos then
		return nil, 0, 0
	end
	return hardPos, if hardId == BOSS then 0 else hardId, hardSize
end

local function toggle()
	if not LockClient.hardOn then
		return
	end
	if hardId then
		setHard(nil)
		return
	end
	local root = rootPart()
	if not root then
		return
	end
	scan()
	local H = K.hard
	local i = LockRules.pick(cands, camState(), heroState(root), H.range, H.angle)
	if i then
		setHard(cands[i].id)
	end
end

local function cycle(dir: number)
	if not LockClient.hardOn then
		return
	end
	local root = rootPart()
	if not root then
		return
	end
	if not hardId then
		toggle()
		return
	end
	scan()
	local H = K.hard
	local i = LockRules.cycle(cands, hardId, camState(), dir, heroState(root), H.range, H.cycleAngle)
	if i then
		setHard(cands[i].id)
	end
end
LockClient.cycle = cycle

-- CombatClient asks this first: the hard target, else the soft one when it is in the cast's reach
local function lockAim(range: number, origin: Vector3): (Vector3?, number)
	if hardPos and hardId and (hardPos - origin).Magnitude <= range + hardSize * 0.5 + 6 then
		return hardPos, if hardId == BOSS then 0 else hardId
	end
	if LockClient.softOn and softPos and softId and (softPos - origin).Magnitude <= range + 3 then
		return softPos, if softId == BOSS then 0 else softId
	end
	return nil, 0
end

---------------------------------------------------------------------------
-- The marker
---------------------------------------------------------------------------

local gui: ScreenGui
local bars: { Frame } = {}
local inks: { Frame } = {}
local diamond: Frame
local diamondInk: Frame

local function bar(color: Color3, z: number): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundColor3 = color
	f.ZIndex = z
	f.Visible = false
	f.Parent = gui
	return f
end

local function buildMarker()
	gui = Instance.new("ScreenGui")
	gui.Name = "LockMarker"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 4
	gui.Parent = player:WaitForChild("PlayerGui")
	for i = 1, 8 do
		inks[i] = bar(rgb(M.ink), 1)
		bars[i] = bar(rgb(M.soft), 2)
	end
	diamondInk = bar(rgb(M.ink), 1)
	diamondInk.Rotation = 45
	diamond = bar(rgb(M.hard), 2)
	diamond.Rotation = 45
end

local function hideMarker()
	for i = 1, 8 do
		bars[i].Visible = false
		inks[i].Visible = false
	end
	diamond.Visible = false
	diamondInk.Visible = false
end

local function drawMarker(at: Vector3, size: number, hard: boolean, now: number)
	local cam = Workspace.CurrentCamera
	local sp, onScreen = cam:WorldToViewportPoint(at)
	if not onScreen or sp.Z <= 0 then
		hideMarker()
		return
	end
	local px = math.clamp(M.size * 30 / math.max(sp.Z, 1) * math.max(1, size / 6), M.min, M.max)
	local layout = LockRules.marker(M, px, now, hard)
	local color = rgb(if hard then M.hard else M.soft)
	for i, b in layout.bars do
		local f, ink = bars[i], inks[i]
		if f then
			f.BackgroundColor3 = color
			f.Position = UDim2.fromOffset(sp.X + b.x, sp.Y + b.y)
			f.Size = UDim2.fromOffset(b.w, b.h)
			f.Rotation = b.rot
			f.Visible = true
			ink.Position = f.Position
			ink.Size = UDim2.fromOffset(b.w + 4, b.h + 4)
			ink.Rotation = b.rot
			ink.Visible = true
		end
	end
	if layout.diamond then
		local d = layout.diamond
		local top = UDim2.fromOffset(sp.X, sp.Y - px * 0.5 - d * 1.1)
		diamond.Position = top
		diamond.Size = UDim2.fromOffset(d, d)
		diamondInk.Position = top
		diamondInk.Size = UDim2.fromOffset(d + 5, d + 5)
		diamond.Visible = true
		diamondInk.Visible = true
	else
		diamond.Visible = false
		diamondInk.Visible = false
	end
end

---------------------------------------------------------------------------
-- The frame
---------------------------------------------------------------------------

local function sight(from: Vector3, to: Vector3): boolean
	local city = Workspace:FindFirstChild("City")
	if not city then
		return true
	end
	rayParams.FilterDescendantsInstances = { city }
	local d = to - from
	return Workspace:Raycast(from, d * 0.95, rayParams) == nil
end

local function update()
	local now = os.clock()
	local root = rootPart()
	if not root then
		setHard(nil)
		hideMarker()
		return
	end
	if now - lastScan > 0.1 then
		lastScan = now
		scan()
	end
	-- the hard lock: follow it, drop it when lost
	if hardId then
		local pos, size = livePos(hardId)
		if not pos or not LockClient.hardOn then
			setHard(nil)
		else
			hardPos, hardSize = pos, math.max(size, 2)
			if now - lastSight > 0.2 then
				local seen = sight(root.Position, pos)
				hiddenFor = if seen then 0 else hiddenFor + (now - lastSight)
				lastSight = now
			end
			if not LockRules.keep(K, (pos - root.Position).Magnitude, hiddenFor) then
				setHard(nil)
			end
		end
	end
	MoveController.lockAt = if hardId then hardPos else nil
	-- the soft lock: the best target in front, for casts and the camera's ease
	softId, softPos = nil, nil
	if LockClient.softOn and not hardId then
		local S = K.soft
		local i = LockRules.pick(cands, camState(), heroState(root), S.range, S.angle)
		if i then
			local c = cands[i]
			softId = c.id
			softPos = livePos(c.id) or Vector3.new(c.x, c.y, c.z)
		end
	end
	if hardId and hardPos then
		drawMarker(hardPos, hardSize, true, now)
	elseif softPos then
		drawMarker(softPos, 6, false, now)
	else
		hideMarker()
	end
end

-- Before Roblox's camera: turn it round the hero toward the lock (hard), or ease toward the soft target
local function camPre(dt: number)
	local cam = Workspace.CurrentCamera
	local root = rootPart()
	if not cam or not root or cam.CameraType == Enum.CameraType.Scriptable then
		ourYaw = nil
		return
	end
	local look = cam.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	if ourYaw and math.abs(((yaw - ourYaw + math.pi) % (2 * math.pi)) - math.pi) > math.rad(0.3) then
		idle = 0 -- the player turned the camera
	else
		idle += dt
	end
	local focus = cam.Focus.Position
	local dist = (cam.CFrame.Position - focus).Magnitude
	if hardId and hardPos then
		local f =
			LockRules.frame(K, heroState(root), { x = hardPos.X, y = hardPos.Y, z = hardPos.Z }, hardSize)
		local pitch = math.asin(math.clamp(look.Y, -1, 1))
		local k = LockRules.ease(K.hard.turn, dt)
		local ny = yaw + ((f.yaw - yaw + math.pi) % (2 * math.pi) - math.pi) * k
		local np = pitch + (f.pitch - pitch) * k
		local dir = CFrame.fromOrientation(np, ny, 0).LookVector
		cam.CFrame = CFrame.lookAt(focus - dir * dist, focus)
		ourYaw = ny
		return
	end
	if softPos and LockClient.softOn then
		local to = softPos - root.Position
		local want = math.atan2(-to.X, -to.Z)
		local off = (want - yaw + math.pi) % (2 * math.pi) - math.pi
		local turn = LockRules.softTurn(K, off, idle, CameraController.motion.lean, dt)
		if turn ~= 0 then
			local pivot = focus
			cam.CFrame = CFrame.new(pivot) * CFrame.Angles(0, turn, 0) * CFrame.new(-pivot) * cam.CFrame
			ourYaw = yaw + turn
			return
		end
	end
	ourYaw = yaw
end

-- After the camera: pull back for big targets, sit off the shoulder, lean and sway with the hero's sideways
-- motion (Camera motion scales the lean and sway; Off removes them)
local lean, sway = 0, 0
local backParams = RaycastParams.new()
backParams.FilterType = Enum.RaycastFilterType.Include
local function camPost(dt: number)
	local cam = Workspace.CurrentCamera
	local root = rootPart()
	if not cam or not root or not hardId or not hardPos or cam.CameraType == Enum.CameraType.Scriptable then
		lean += (0 - lean) * LockRules.ease(6, dt)
		sway += (0 - sway) * LockRules.ease(6, dt)
		return
	end
	local H = K.hard
	local f = LockRules.frame(K, heroState(root), { x = hardPos.X, y = hardPos.Y, z = hardPos.Z }, hardSize)
	local m = CameraController.motion.lean
	local side = MoveController.velocity:Dot(cam.CFrame.RightVector) / math.max(Config.Move.flight.cruise, 1)
	side = math.clamp(side, -1, 1)
	local k = LockRules.ease(4, dt)
	lean += (-side * math.rad(H.lean) * m - lean) * k
	sway += (side * H.sway * m - sway) * k
	local back = f.pull
	if back > 0 then
		-- never through a wall behind the camera
		local city = Workspace:FindFirstChild("City")
		if city then
			backParams.FilterDescendantsInstances = { city }
			local hit = Workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * -back, backParams)
			if hit then
				back = math.max(0, (hit.Position - cam.CFrame.Position).Magnitude - 1)
			end
		end
	end
	cam.CFrame *= CFrame.new(f.shoulder + sway, 0, back) * CFrame.Angles(0, 0, lean)
end

function LockClient.init()
	buildMarker()
	CombatClient.lockAim = lockAim
	InputController.Pressed:Connect(function(action: string)
		if action == "Lock" then
			lockPressAt = os.clock()
		elseif action == "LockCycle" then
			cycle(1)
		end
	end)
	InputController.Released:Connect(function(action: string)
		if action == "Lock" then
			-- held: the next target; a tap locks or lets go
			if hardId and os.clock() - lockPressAt >= K.padHold then
				cycle(1)
			else
				toggle()
			end
		end
	end)
	InputController.Flick:Connect(function(dir: number)
		if hardId then
			cycle(dir)
		end
	end)
	player.CharacterAdded:Connect(function()
		setHard(nil)
	end)
	RunService:BindToRenderStep(
		"CapelineLockPre",
		Enum.RenderPriority.Camera.Value - 3,
		FrameProf.wrap("LockClient", function(dt)
			update()
			camPre(dt)
		end)
	)
	RunService:BindToRenderStep(
		"CapelineLockPost",
		Enum.RenderPriority.Camera.Value + 2,
		FrameProf.wrap("LockClient", camPost)
	)
end

return LockClient
