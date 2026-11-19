-- ThrowClient: pick up and throw on your side (spec: Hero MMO features > Pick up and throw; H3). A GRAB
-- prompt floats over the nearest thing you can lift within 10 studs (tap it on a phone; B on PC; the B
-- button on a controller while on the ground). Carrying: THROW with the attack button along your aim, Grab
-- again sets it down; you move at 80% with no boost (MoveController scale) and cannot cast
-- (CombatClient.blocked). The server owns all of it (ThrowService); this only asks and shows.
-- Heavy things show the prompt only for Powerhouse heroes or while Awakened (Shared.ThrowMath.canLift).
-- Grab a robot and swing it (nate, 2026-11-19 13:18Z; Config.Throw.swing): the prompt also shows over a stunned
-- (or tumbling) robot you could hold; holding a robot's wreck or a robot, a tap of attack SWINGS it (a wide arc
-- that hits robots and breaks walls), a held attack (or the last swing used) THROWS it. SwingFx draws everyone's
-- swings.
-- Holding (fix-carry, nate after gaps7: "i should actually hold them"): ThrowService welds a carried prop into
-- the carrier's hands (Shared.CarryPose); this moves it on every device during the moments the hands leave the
-- hold pose (the lift, the swings and the slam: it follows the right hand), bobs a telekinesis float and whirls
-- it on a swing, and draws everyone's held live robots in their hands (EnemyRenderer.heldAt), from the same
-- CarryPose sums the server uses for the hits. All local: the Weld's C0 is set on this device only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local ThrowMath = require(Shared:WaitForChild("ThrowMath"))

local InputController = require(script.Parent.InputController)
local MoveController = require(script.Parent.MoveController)
local CombatClient = require(script.Parent.CombatClient)
local StoryClient = require(script.Parent.StoryClient)
local EnemyRenderer = require(script.Parent.EnemyRenderer)
local CombatFx = require(script.Parent.Parent.Fx.CombatFx)
local HeroAnimator = require(script.Parent.HeroAnimator)
local CarryPose = require(Shared:WaitForChild("CarryPose"))
local HeroAnim = require(Shared:WaitForChild("HeroAnim"))
local RigJoints = require(Shared:WaitForChild("RigJoints"))
local State = require(script.Parent.Parent.State)

local ThrowClient = {}

local T = Config.Throw
local player = Players.LocalPlayer
ThrowClient.Changed = Signal.new() -- (kind?) you picked something up (its kind) or let go (nil)

local held: { id: number, kind: string?, since: number, swings: number }? = nil
local target: number? = nil -- the item the prompt is on
local robotTarget: number? = nil -- a stunned robot the prompt is on (no item near)
local anchor: Part -- the prompt's spot over a robot (robots are drawn without parts the prompt could hang on)
local basicAt = 0
local BITS = require(Shared:WaitForChild("Status")).BITS
local targetModel: Model? = nil
local gui: BillboardGui
local label: TextButton
local lastScan = 0
local found: { [number]: { id: number, kind: string, x: number, y: number, z: number, busy: boolean?, m: Model } } =
	{}

function ThrowClient.carrying(): string?
	return held and held.kind
end

-- Every liftable thing: the props in Workspace.Throwables and the tagged vehicles
local function scan()
	table.clear(found)
	local function add(m: Instance)
		local id, kind = m:GetAttribute("ThrowId"), m:GetAttribute("ThrowKind")
		if m:IsA("Model") and type(id) == "number" and type(kind) == "string" then
			local pos = m:GetPivot().Position
			found[id] = {
				id = id,
				kind = kind,
				x = pos.X,
				y = pos.Y,
				z = pos.Z,
				busy = m:GetAttribute("ThrowBusy") == true,
				m = m,
			}
		end
	end
	local props = Workspace:FindFirstChild("Throwables")
	for _, m in (if props then props:GetChildren() else {}) do
		add(m)
	end
	local city = Workspace:FindFirstChild("City")
	local vehicles = city and city:FindFirstChild("Vehicles")
	for _, m in (if vehicles then vehicles:GetChildren() else {}) do
		add(m)
	end
end

local function free(): boolean
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0 and not (CombatClient.blocked and CombatClient.blocked())
end

local function grab()
	if held then
		Net.send("WorldGrab", 0) -- set it down
	elseif target then
		Net.send("WorldGrab", target)
	elseif robotTarget then
		Net.send("WorldGrabRobot", robotTarget)
	end
end

-- The nearest robot you could hold: stunned or tumbling from a hit, a row ThrowMath allows, within reach
local function nearestRobot(p: Vector3): number?
	local best, bestD = nil, T.swing.robot.reach
	for id, pos in EnemyRenderer.each() do
		local d = (pos - p).Magnitude
		if d <= bestD then
			local f = EnemyRenderer.flags(id)
			local dazed = bit32.band(f, BITS.stun) ~= 0 or bit32.band(f, BITS.lifted) ~= 0
			local cfg = EnemyRenderer.cfgOf(id)
			if dazed and cfg and ThrowMath.canHoldRobot(T, cfg, T.swing.robot.stunAtLeast) then
				best, bestD = id, d
			end
		end
	end
	return best
end

local function swingable(): boolean
	return held ~= nil and ThrowMath.swingable(T, held.kind) and held.swings > 0
end

local function swingAim()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not held or not root then
		return
	end
	Net.send("WorldSwing", CombatClient.aimAt(T.swing.radius, root.Position))
end

local function throw()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not held or not root then
		return
	end
	local w = ThrowMath.weight(T, held.kind or "") or "light"
	local point = CombatClient.aimAt(T.weights[w].range, root.Position)
	Net.send("WorldThrow", point)
end

local function step()
	local now = os.clock()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if now - lastScan > 0.5 then
		lastScan = now
		scan()
	end
	local best: number? = nil
	if root and not held and free() then
		local p = root.Position
		-- the prompt follows the latest model position (things move once thrown)
		for _, it in found do
			local pos = it.m:GetPivot().Position
			it.x, it.y, it.z = pos.X, pos.Y, pos.Z
			it.busy = it.m:GetAttribute("ThrowBusy") == true
		end
		best = ThrowMath.nearest(found, p.X, p.Y, p.Z, T.reach, function(kind: string)
			return ThrowMath.canLift(T, kind, State.hero.classId, State.awakened())
		end)
	end
	target = best
	robotTarget = nil
	if root and not held and not best and free() then
		robotTarget = nearestRobot(root.Position)
	end
	local m = best and found[best] and found[best].m
	if held then
		gui.Adornee = root
		local touch = InputController.device == "touch"
		label.Text = if swingable()
			then (if touch
				then "SWING: attack  /  hold: THROW"
				else "SWING: click  /  hold: THROW  /  B: drop")
			elseif touch then "THROW: attack  /  tap: set down"
			else "THROW: attack  /  B: set down"
		gui.StudsOffset = Vector3.new(0, 9, 0)
		gui.Enabled = root ~= nil
	elseif robotTarget then
		local pos = EnemyRenderer.position(robotTarget)
		if pos then
			anchor.CFrame = CFrame.new(pos)
		end
		targetModel = nil
		gui.Adornee = anchor
		label.Text = if InputController.device == "touch" then "GRAB" else "GRAB [B]"
		gui.StudsOffset = Vector3.new(0, 4, 0)
		gui.Enabled = pos ~= nil
	elseif m then
		if m ~= targetModel then
			targetModel = m
			gui.Adornee = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
		end
		label.Text = if InputController.device == "touch" then "GRAB" else "GRAB [B]"
		gui.StudsOffset = Vector3.new(0, 3, 0)
		gui.Enabled = true
	else
		targetModel = nil
		gui.Enabled = false
	end
end

---------------------------------------------------------------------------
-- Holding: the carried thing in the hands on this device (fix-carry)
---------------------------------------------------------------------------

local HOLD_RANGE = 220 -- carriers farther from the camera than this keep the plain weld
local M = T.mind
type Carrier = {
	char: Model?,
	weld: Weld?,
	robot: number?,
	grip: string?,
	hold: CarryPose.Hold?, -- a held robot's hold, worked out here from the carrier's own joints
	holdH: number?,
	whirl: { start: number, yaw: number }?, -- a swing's whirl round a telekinesis carrier (world yaw)
	glow: Highlight?,
}
local carriers: { [Player]: Carrier } = {}
local robotHeld: { [number]: Player } = {} -- robot id -> who holds it

local function toCF(c: CarryPose.CF): CFrame
	return CFrame.new(table.unpack(CarryPose.components(c)))
end

-- a carrier's R15 arm from its own joints (Motor6Ds or AnimationConstraints), the way ThrowService reads it
local function bodyOf(char: Model): CarryPose.Body?
	local joints = RigJoints.of(char)
	local body: CarryPose.Body = { joints = {}, sizes = {} }
	for _, j in CarryPose.JOINTS do
		local m = joints[j[1]]
		if not m then
			return nil
		end
		local c0, c1 = (m :: any).C0, (m :: any).C1
		table.insert(body.joints, {
			name = j[1],
			part0 = j[2],
			part1 = j[3],
			c0 = CarryPose.fromComponents({ c0:GetComponents() }),
			c1 = CarryPose.fromComponents({ c1:GetComponents() }),
		})
	end
	for _, n in { "Head", "RightHand", "LeftHand" } do
		local p = char:FindFirstChild(n)
		if p and p:IsA("BasePart") then
			body.sizes[n] = { p.Size.X, p.Size.Y, p.Size.Z }
		end
	end
	return body
end

local function refresh(p: Player)
	local kind = p:GetAttribute("Carrying")
	local old = carriers[p]
	if old and old.robot then
		robotHeld[old.robot] = nil
	end
	if old and old.glow then
		old.glow:Destroy()
	end
	if not kind then
		carriers[p] = nil
		return
	end
	local robot = p:GetAttribute("CarryRobot")
	local c: Carrier = {
		char = p.Character,
		robot = if type(robot) == "number" then robot else nil,
		grip = p:GetAttribute("CarryGrip") :: any,
	}
	carriers[p] = c
	if c.robot then
		robotHeld[c.robot] = p
	end
end

local function track(p: Player)
	for _, name in { "Carrying", "CarryGrip", "CarryRobot" } do
		p:GetAttributeChangedSignal(name):Connect(function()
			refresh(p)
		end)
	end
	refresh(p)
end

-- the box's middle in its weld part's frame now: the hold, following the right hand through the lift and the
-- swings (blended by the clip's weight), bobbing or whirling for telekinesis
local function boxNow(
	p: Player,
	c: Carrier,
	char: Model,
	part0: BasePart,
	base: CFrame,
	hand: CFrame,
	now: number
): CFrame
	if c.grip == "mind" then
		local w = c.whirl
		if w then
			local u = (now - w.start) / T.swing.time
			if u < 1 then
				local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					local v = CarryPose.whirl(T, w.yaw, u)
					local world = CFrame.new(root.Position + Vector3.new(v[1], v[2], v[3]))
						* root.CFrame.Rotation
					return part0.CFrame:Inverse() * world * base.Rotation
				end
			else
				c.whirl = nil
			end
		end
		return CFrame.new(0, math.sin(now * M.bobRate + p.UserId % 7) * M.bob, 0) * base
	end
	local clip, t, dur = HeroAnimator.actionOf(p)
	if clip and CarryPose.FOLLOW[clip] then
		local rh = char:FindFirstChild("RightHand") :: BasePart?
		local w = HeroAnim.actionWeight(t, dur)
		if rh and w > 0 then
			return base:Lerp(part0.CFrame:Inverse() * rh.CFrame * hand, w)
		end
	end
	return base
end

-- Props: the carry Weld's C0 on this device (PreSimulation, so the physics step solves it this frame)
local function holdStep()
	local now = os.clock()
	local cam = Workspace.CurrentCamera
	local eye = if cam then cam.CFrame.Position else Vector3.zero
	for p, c in carriers do
		local char = p.Character
		if c.robot or not char then
			continue
		end
		if not (c.weld and c.weld.Parent and c.char == char) then
			c.char = char
			local w = char:FindFirstChild("CarryWeld", true)
			c.weld = if w and w:IsA("Weld") then w else nil
		end
		local weld = c.weld
		local part0 = weld and weld.Part0
		if not (weld and part0) then
			continue
		end
		if (part0.Position - eye).Magnitude > HOLD_RANGE then
			continue
		end
		local base, hand, offset =
			weld:GetAttribute("CarryBase"), weld:GetAttribute("CarryHand"), weld:GetAttribute("CarryOffset")
		if typeof(base) ~= "CFrame" or typeof(hand) ~= "CFrame" or typeof(offset) ~= "CFrame" then
			continue
		end
		local c0 = boxNow(p, c, char, part0, base, hand, now) * offset
		if c0 ~= weld.C0 then
			weld.C0 = c0
		end
	end
end

-- Robots: where EnemyRenderer draws a held one (its middle in the world), from the carrier's hands now
local function robotAt(id: number, height: number): CFrame?
	local p = robotHeld[id]
	local c = p and carriers[p]
	local char = p and p.Character
	if not (c and char) then
		return nil
	end
	if not c.hold or c.holdH ~= height or c.char ~= char then
		local body = bodyOf(char)
		if not body then
			return nil
		end
		local grip = c.grip or "overhead"
		c.char = char
		c.holdH = height
		c.hold = CarryPose.hold(
			T,
			body,
			grip,
			HeroAnim.sample(CarryPose.CLIP[grip] or "carry", 0),
			CarryPose.robotSize(height),
			true
		)
	end
	local hold = c.hold :: CarryPose.Hold
	local part0 = char:FindFirstChild(hold.part) :: BasePart?
	if not part0 then
		return nil
	end
	if c.grip == "mind" and not c.glow then
		local m = EnemyRenderer.modelOf(id)
		local rgb = M.glow[p:GetAttribute("PowerSet") :: any] or M.glow.Mind
		if m then
			local h = Instance.new("Highlight")
			h.FillColor = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
			h.OutlineColor = h.FillColor
			h.FillTransparency = 0.75
			h.DepthMode = Enum.HighlightDepthMode.Occluded
			h.Adornee = m
			h.Parent = m
			c.glow = h
		end
	end
	return part0.CFrame * boxNow(p, c, char, part0, toCF(hold.c0), toCF(hold.hand), os.clock())
end

function ThrowClient.init()
	gui = Instance.new("BillboardGui")
	gui.Name = "GrabPrompt"
	gui.Size = UDim2.fromOffset(190, 40)
	gui.AlwaysOnTop = true
	gui.Active = true
	gui.Enabled = false
	gui.ResetOnSpawn = false
	label = Instance.new("TextButton")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(24, 26, 34)
	label.BackgroundTransparency = 0.2
	label.TextColor3 = Color3.fromRGB(255, 220, 90)
	label.Font = Enum.Font.Bangers
	label.TextScaled = true
	label.AutoButtonColor = true
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label
	gui.Parent = player:WaitForChild("PlayerGui")
	anchor = Instance.new("Part")
	anchor.Name = "GrabAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.Parent = Workspace.CurrentCamera
	label.Activated:Connect(grab) -- a tap on a phone (or a click)

	-- no casting with your hands full; the attack button throws instead
	local before = CombatClient.blocked
	CombatClient.blocked = function(): boolean
		return held ~= nil or (before ~= nil and before())
	end
	InputController.Pressed:Connect(function(action: string)
		if action == "Catch" and StoryClient.openingStep() ~= "catch" then
			grab() -- B: the interact key
		elseif
			action == "Down"
			and InputController.device == "gamepad"
			and MoveController.mode == "ground"
		then
			if held or target then
				grab()
			end
		elseif action == "Basic" and held then
			if swingable() then
				basicAt = os.clock() -- a tap swings, a hold throws (on the release)
			else
				throw()
			end
		end
	end)
	InputController.Released:Connect(function(action: string)
		if action == "Basic" and held and basicAt > 0 then
			local long = os.clock() - basicAt >= Config.Combat.lock.padHold
			basicAt = 0
			if long or not swingable() then
				throw()
			else
				swingAim()
			end
		end
	end)
	-- everyone's swings near you: a wide comic arc round the swinger (its hits draw as hits)
	Net.listen("SwingFx", function(d: any)
		if type(d) ~= "table" or type(d.x) ~= "number" then
			return
		end
		local origin = Vector3.new(d.x, d.y + 1.5, d.z)
		local dir = Vector3.new(d.dx or 0, 0, d.dz or -1)
		local style = State.hero.fxStyle or "Comic"
		CombatFx.arc(
			origin,
			dir,
			d.r or T.swing.radius,
			d.arc or T.swing.arc,
			style,
			CombatFx.colorOf(nil, d.u),
			3
		)
		local who = if type(d.u) == "number" then Players:GetPlayerByUserId(d.u) else nil
		local held = who and carriers[who]
		if held and held.grip == "mind" then
			held.whirl = { start = os.clock(), yaw = math.atan2(-dir.X, -dir.Z) }
		end
		if who then
			HeroAnimator.robotSwing(who, if type(d.n) == "number" then d.n else nil, d.slam == true)
		end
	end)
	Net.listen("ThrowState", function(data: any)
		if type(data) ~= "table" then
			return
		end
		if data.id and data.id ~= 0 then
			held = {
				id = data.id,
				kind = data.kind,
				since = if held and held.id == data.id then held.since else os.clock(),
				swings = data.swings or 0,
			}
		else
			held = nil
		end
		MoveController.setScale("carry", if held then T.carrySpeed else nil)
		ThrowClient.Changed:Fire(held and held.kind)
	end)
	player.CharacterAdded:Connect(function()
		held = nil
		MoveController.setScale("carry", nil)
	end)
	RunService.Heartbeat:Connect(FrameProf.wrap("ThrowClient", step))
	for _, p in Players:GetPlayers() do
		track(p)
	end
	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(function(p)
		local c = carriers[p]
		if c and c.robot then
			robotHeld[c.robot] = nil
		end
		carriers[p] = nil
	end)
	EnemyRenderer.heldAt = robotAt
	RunService.PreSimulation:Connect(FrameProf.wrap("ThrowHold", holdStep))
end

return ThrowClient
