-- StoryFx: the story's props and companions, drawn on this device only.
-- (The Ceremony prologue's scene is PrologueFx's, lore step 3.)
-- * Null Echo: a small drone buddy that follows every hero who spared the Sentinel core (Player attribute
--   NullEcho), bobbing at the shoulder. Cosmetic only.
-- * The Overload arena effect: the War-Frame arena's pillars crackle for heroes who overloaded the core.
-- PLACEHOLDER ART: parts until the art pass.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local Workspace = game:GetService("Workspace")

local State = require(script.Parent.Parent.State)
local StoryClient = require(script.Parent.Parent.Controllers.StoryClient)
local CombatFx = require(script.Parent.CombatFx)

local StoryFx = {}

local folder: Folder
local buddies: { [Player]: Part } = {}
local sparkAt = 0

local function part(
	parent: Instance,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	mat: Enum.Material?,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

local function buddyStep(now: number)
	for _, p in Players:GetPlayers() do
		local want = p:GetAttribute("NullEcho") == true
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local b = buddies[p]
		if want and root then
			if not b then
				local d = part(
					folder,
					Vector3.new(1.4, 1.4, 1.4),
					root.CFrame,
					Color3.fromRGB(150, 60, 200),
					Enum.Material.Metal,
					Enum.PartType.Ball
				)
				d.Name = "NullEcho"
				local eye = part(
					d,
					Vector3.new(0.5, 0.5, 0.3),
					root.CFrame,
					Color3.fromRGB(120, 230, 255),
					Enum.Material.Neon
				)
				local weld = Instance.new("WeldConstraint")
				eye.Anchored = false
				weld.Part0 = d
				weld.Part1 = eye
				weld.Parent = d
				b = d
				buddies[p] = d
			end
			local bob = math.sin(now * 2 + p.UserId % 7) * 0.6
			local goal = root.CFrame * CFrame.new(2.6, 2.4 + bob, 1.2)
			local bp = b :: Part
			bp.CFrame = bp.CFrame:Lerp(goal, 0.15)
		elseif b then
			b:Destroy()
			buddies[p] = nil
		end
	end
end

-- Overload: the arena's pillars crackle (a spark on a random pillar now and then)
local function arenaStep(now: number)
	local m = StoryClient.mission
	if not m.arena or (m.num or 0) ~= 6 or now < sparkAt then
		return
	end
	sparkAt = now + 0.7
	local pockets = Workspace:FindFirstChild("Pockets")
	local list = {}
	for _, p in (if pockets then pockets:GetDescendants() else {}) do
		if p:IsA("BasePart") and p.Shape == Enum.PartType.Cylinder then
			table.insert(list, p)
		end
	end
	if #list > 0 then
		local p = list[math.random(1, #list)]
		CombatFx.burst(
			p.Position + Vector3.new(0, math.random(-15, 15), 0),
			State.hero.fxStyle,
			Color3.fromRGB(190, 120, 255)
		)
	end
end

function StoryFx.init()
	folder = Instance.new("Folder")
	folder.Name = "StoryFx"
	folder.Parent = Workspace
	Players.PlayerRemoving:Connect(function(p)
		local b = buddies[p]
		if b then
			b:Destroy()
			buddies[p] = nil
		end
	end)
	RunService.RenderStepped:Connect(FrameProf.wrap("StoryFx", function()
		local now = os.clock()
		buddyStep(now)
		arenaStep(now)
	end))
end

return StoryFx
