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
end

return ThrowClient
