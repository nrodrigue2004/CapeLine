-- StoryFx: the story's props and companions, drawn on this device only.
-- * The opening (for the local hero alone): the tram car hanging off its broken rail with sparks, the
--   citizens climbing out after the Catch, the glowing shard that lands by the trapped citizen, and the
--   escape marker beam for Grab It. The server only keeps the logic and the real robots.
-- * Null Echo: a small drone buddy that follows every hero who spared the Sentinel core (Player attribute
--   NullEcho), bobbing at the shoulder. Cosmetic only.
-- * The Overload arena effect: the War-Frame arena's pillars crackle for heroes who overloaded the core.
-- PLACEHOLDER ART: parts until the art pass.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local State = require(script.Parent.Parent.State)
local StoryClient = require(script.Parent.Parent.Controllers.StoryClient)
local CombatFx = require(script.Parent.CombatFx)

local StoryFx = {}

local folder: Folder
local tram: Model? = nil
local shard: Model? = nil
local beam: Part? = nil
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

local function v3(t: { number }?): Vector3?
	return if t then Vector3.new(t[1], t[2], t[3]) else nil
end

local function clearOpening()
	if tram then
		tram:Destroy()
		tram = nil
	end
	if shard then
		shard:Destroy()
		shard = nil
	end
	if beam then
		beam:Destroy()
		beam = nil
	end
end

-- The tram car tipped off the broken rail: one end on the street, the other up on the rail stub
local function buildTram(at: Vector3)
	local m = Instance.new("Model")
	m.Name = "OpeningTram"
	local rail = Color3.fromRGB(90, 90, 100)
	part(m, Vector3.new(3, 22, 3), CFrame.new(at + Vector3.new(-16, 11, 0)), rail, Enum.Material.Metal)
	part(m, Vector3.new(20, 2, 4), CFrame.new(at + Vector3.new(-24, 22, 0)), rail, Enum.Material.Metal)
	local car = part(
		m,
		Vector3.new(28, 9, 9),
		CFrame.new(at + Vector3.new(-2, 9, 0)) * CFrame.Angles(0, 0, math.rad(-32)),
		Color3.fromRGB(230, 120, 50),
		Enum.Material.SmoothPlastic
	)
	car.Name = "Car"
	for i = -1, 1 do
		part(
			m,
			Vector3.new(5, 3, 0.4),
			car.CFrame * CFrame.new(i * 8, 1.5, -4.7),
			Color3.fromRGB(180, 230, 255),
			Enum.Material.Glass
		)
	end
	m.Parent = folder
	tram = m
end

-- After the Catch: the car settles flat and three citizens climb out and run off (cheers are a sound)
local function settleTram()
	local m = tram
	if not m then
		return
	end
	local car = m:FindFirstChild("Car") :: BasePart?
	if car then
		local flat = CFrame.new(car.Position.X, car.Position.Y - 3.5, car.Position.Z)
		TweenService:Create(car, TweenInfo.new(0.6, Enum.EasingStyle.Back), { CFrame = flat }):Play()
		for i = 1, 3 do
			local c = part(
				m,
				Vector3.new(1.6, 4, 1),
				flat * CFrame.new(-6 + i * 4, 1, -6),
				Color3.fromRGB(80 + i * 40, 120, 200 - i * 30)
			)
			TweenService
				:Create(
					c,
					TweenInfo.new(2.5),
					{ CFrame = c.CFrame * CFrame.new(math.random(-30, 30), 0, -40) }
				)
				:Play()
		end
		CombatFx.burst(car.Position, State.hero.fxStyle)
	end
end

local function buildShard(at: Vector3)
	local m = Instance.new("Model")
	m.Name = "OpeningShard"
	local crystal = part(
		m,
		Vector3.new(3, 7, 3),
		CFrame.new(at + Vector3.new(0, 3.5, 0)) * CFrame.Angles(0, math.rad(30), math.rad(15)),
		Color3.fromRGB(150, 230, 255),
		Enum.Material.Neon
	)
	local light = Instance.new("PointLight")
	light.Color = crystal.Color
	light.Range = 24
	light.Brightness = 3
	light.Parent = crystal
	-- the trapped citizen, pinned under rubble beside it
	part(m, Vector3.new(1.6, 3.6, 1), CFrame.new(at + Vector3.new(5, 1.8, 0)), Color3.fromRGB(220, 110, 140))
	part(
		m,
		Vector3.new(6, 2, 4),
		CFrame.new(at + Vector3.new(5, 1, 2)),
		Color3.fromRGB(120, 110, 100),
		Enum.Material.Slate
	)
	m.Parent = folder
	shard = m
	CombatFx.burst(at + Vector3.new(0, 4, 0), State.hero.fxStyle)
end

local function buildBeam(at: Vector3, color: Color3)
	local b = part(
		folder,
		Vector3.new(4, 300, 4),
		CFrame.new(at + Vector3.new(0, 150, 0)),
		color,
		Enum.Material.Neon
	)
	b.Transparency = 0.5
	beam = b
end

local lastStep: string? = nil
local function onOpening()
	local o = StoryClient.opening
	local step = StoryClient.openingStep()
	if not step or step == "suitup" or step == "flight" then
		clearOpening()
		lastStep = step
		return
	end
	local at = v3(o.tram)
	if not tram and at then
		buildTram(at)
	end
	if step == "blast" and lastStep == "catch" then
		settleTram()
	end
	local sh = v3(o.shard)
	if step == "choice" and not shard and sh then
		buildShard(sh)
	elseif (step == "save" or step == "grab") and shard then
		-- Save: the server's citizen takes over; Grab: the shard is in hand
		shard:Destroy()
		shard = nil
	end
	if step == "grab" then
		local esc = v3(o.escape)
		if not beam and esc then
			buildBeam(esc, Color3.fromRGB(190, 80, 220))
		end
	elseif step == "save" then
		local pad = v3(o.pad)
		if not beam and pad then
			buildBeam(pad, Color3.fromRGB(80, 220, 140))
		end
	end
	lastStep = step
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
	StoryClient.Changed:Connect(function(what)
		if what == "opening" then
			onOpening()
		end
	end)
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
