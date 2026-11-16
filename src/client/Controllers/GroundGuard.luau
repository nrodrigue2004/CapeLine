-- GroundGuard: never let the hero fall through a world that has not streamed in yet. The city is built at
-- run time and streams to each device (StreamingEnabled), so after a spawn or a server move (the opening's
-- rooftop, a respawn, fast travel, a mission pocket, the HQ) the ground under the hero can arrive a few
-- seconds after the hero does. Character physics run on this device, so without ground the hero just falls.
-- When the hero appears somewhere new (a new character, or a jump of more than 80 studs in one frame) and a
-- ray finds nothing below, the root is held still on this device and a small LOADING AREA label shows,
-- until the ground streams in (or 12 s pass, so a real hole never traps anyone).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GroundGuard = {}

GroundGuard.holding = false
GroundGuard.holds = 0 -- how many times this session the guard held the hero (Dev panel)

local player = Players.LocalPlayer
local JUMP = 80 -- studs in one frame: no movement does this, only a server move
local DOWN = 6000 -- the ray reaches the ground from the HQ cells (y 4,500) and the pockets (y 3,000)
local TIMEOUT = 12
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

local label: TextLabel? = nil

local function showLabel(on: boolean)
	if on and not label then
		local gui = Instance.new("ScreenGui")
		gui.Name = "GroundGuard"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 50
		gui.IgnoreGuiInset = true
		local t = Instance.new("TextLabel")
		t.AnchorPoint = Vector2.new(0.5, 0)
		t.Position = UDim2.new(0.5, 0, 0.18, 0)
		t.Size = UDim2.fromOffset(260, 40)
		t.BackgroundColor3 = Color3.fromRGB(20, 24, 40)
		t.BackgroundTransparency = 0.25
		t.TextColor3 = Color3.new(1, 1, 1)
		t.Font = Enum.Font.GothamBlack
		t.TextSize = 18
		t.Text = "LOADING AREA..."
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = t
		t.Parent = gui
		gui.Parent = player:WaitForChild("PlayerGui")
		label = t
	end
	if label and label.Parent then
		(label.Parent :: ScreenGui).Enabled = on
	end
end

local function groundBelow(root: BasePart, character: Model): boolean
	params.FilterDescendantsInstances = { character }
	return Workspace:Raycast(root.Position, Vector3.new(0, -DOWN, 0), params) ~= nil
end

local holdToken = 0
local function hold(root: BasePart, character: Model)
	if groundBelow(root, character) then
		return
	end
	holdToken += 1
	local token = holdToken
	GroundGuard.holding = true
	GroundGuard.holds += 1
	root.Anchored = true
	showLabel(true)
	task.spawn(function()
		local t0 = os.clock()
		while token == holdToken and root.Parent and os.clock() - t0 < TIMEOUT do
			if groundBelow(root, character) then
				break
			end
			task.wait(0.1)
		end
		if token ~= holdToken then
			return
		end
		task.wait(0.15) -- one more beat for the parts around the ground
		if root.Parent then
			root.Anchored = false
			root.AssemblyLinearVelocity = Vector3.zero
		end
		GroundGuard.holding = false
		showLabel(false)
	end)
end

function GroundGuard.init()
	local last: Vector3? = nil
	local function bind(character: Model)
		last = nil
		local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
		if root then
			hold(root, character)
			last = root.Position
		end
	end
	if player.Character then
		task.spawn(bind, player.Character)
	end
	player.CharacterAdded:Connect(bind)
	RunService.PostSimulation:Connect(function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or not character then
			return
		end
		local pos = root.Position
		if last and not GroundGuard.holding and (pos - last).Magnitude > JUMP then
			hold(root, character)
		end
		last = pos
	end)
end

return GroundGuard
