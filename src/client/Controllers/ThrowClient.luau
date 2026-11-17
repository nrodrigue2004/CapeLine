-- ThrowClient: pick up and throw on your side (spec: Hero MMO features > Pick up and throw; H3). A GRAB
-- prompt floats over the nearest thing you can lift within 10 studs (tap it on a phone; B on PC; the B
-- button on a controller while on the ground). Carrying: THROW with the attack button along your aim, Grab
-- again sets it down; you move at 80% with no boost (MoveController scale) and cannot cast
-- (CombatClient.blocked). The server owns all of it (ThrowService); this only asks and shows.
-- Heavy things show the prompt only for Powerhouse heroes or while Awakened (Shared.ThrowMath.canLift).

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
local State = require(script.Parent.Parent.State)

local ThrowClient = {}

local T = Config.Throw
local player = Players.LocalPlayer
ThrowClient.Changed = Signal.new() -- (kind?) you picked something up (its kind) or let go (nil)

local held: { id: number, kind: string?, since: number }? = nil
local target: number? = nil -- the item the prompt is on
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
	end
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
	local m = best and found[best] and found[best].m
	if held then
		gui.Adornee = root
		label.Text = if InputController.device == "touch"
			then "THROW: attack  /  tap: set down"
			else "THROW: attack  /  B: set down"
		gui.StudsOffset = Vector3.new(0, 9, 0)
		gui.Enabled = root ~= nil
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
			throw()
		end
	end)
	Net.listen("ThrowState", function(data: any)
		if type(data) ~= "table" then
			return
		end
		if data.id and data.id ~= 0 then
			held = { id = data.id, kind = data.kind, since = os.clock() }
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
