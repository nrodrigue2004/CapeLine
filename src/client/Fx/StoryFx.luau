-- StoryFx: the story's props and companions, drawn on this device only.
-- (The Ceremony prologue's scene is PrologueFx's, lore step 3.)
-- * The Echo Drone: a small drone that follows every villain who reprogrammed their evil twin's core (Player
--   attribute NullEcho; older saves that spared the old core keep it), bobbing at the shoulder. Cosmetic only.
-- * The crackling arena: Live's pillars crackle for heroes who destroyed their twin's core. Cosmetic only.
-- * A mission's camera beats (lore step 5): the camera leaves the hero for the beat's focus (a fake, the mast,
--   the safehouse door) and pushes in slowly; the hero holds still on this device; Lodestar stands where the
--   beat says; each radio line starts with a blip (the subtitles are StoryHud's). No flashes or shakes, so
--   Reduce flashing has nothing to remove. The shot plays through the one cutscene player (CinemaClient,
--   lore step 7: letterbox, SKIP once every hero on the stage has seen it).
-- PLACEHOLDER ART: parts until the art pass.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local Workspace = game:GetService("Workspace")

local NpcRig = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("NpcRig"))
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Config"))
local Net = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Net"))
local CinemaPlan =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("CinemaPlan"))

local State = require(script.Parent.Parent.State)
local StoryClient = require(script.Parent.Parent.Controllers.StoryClient)
local CinemaClient = require(script.Parent.Parent.Controllers.CinemaClient)
local CombatFx = require(script.Parent.CombatFx)
local PrologueFx = require(script.Parent.PrologueFx)

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

---------------------------------------------------------------------------
-- A mission's camera beats (lore step 5)
---------------------------------------------------------------------------

local player = Players.LocalPlayer
local sceneKey: any = nil
local lodestar: any = nil

local function heroRoot(): BasePart?
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function lodestarStep(at: { number }?, face: Vector3?)
	if not at then
		if lodestar then
			lodestar.model:Destroy()
			lodestar = nil
		end
		return
	end
	if not lodestar then
		lodestar = PrologueFx.lodestarRig(folder)
	end
	local pos = Vector3.new(at[1], at[2], at[3])
	local d = if face then face - pos else Vector3.new(0, 0, 1)
	NpcRig.place(lodestar, CFrame.new(pos) * CFrame.Angles(0, math.atan2(-d.X, -d.Z), 0))
end

-- The beat's shot (lore step 7: played by the one cutscene player, CinemaClient): from beside and above the
-- hero, looking at the focus (or the hero, with no focus), with a slow push in over the beat
local function playScene(st: any, r: BasePart)
	local m = StoryClient.mission
	local f = m.focus
	local at = if f then Vector3.new(f[1], f[2] + 5, f[3]) else r.Position + Vector3.new(0, 3, 0)
	local flat = Vector3.new(r.Position.X - at.X, 0, r.Position.Z - at.Z)
	local back = if flat.Magnitude > 1 then flat.Unit else Vector3.new(0, 0, 1)
	local dist = math.clamp(flat.Magnitude * 0.6 + 26, 30, 70)
	local side = back:Cross(Vector3.new(0, 1, 0)) * 10
	local from = at + back * dist + side + Vector3.new(0, 14, 0)
	local to = from:Lerp(at, 0.22)
	local seconds = math.max(1, st.seconds)
	CinemaClient.play({
		owner = "mission",
		key = st,
		bit = CinemaPlan.missionBit(Config, m.num or 0, m.step or 0),
		shots = {
			{
				kind = "dolly",
				t0 = 0,
				t1 = seconds,
				from = { from.X, from.Y, from.Z },
				to = { to.X, to.Y, to.Z },
				at = { at.X, at.Y, at.Z },
				at2 = { at.X, at.Y, at.Z },
			},
		},
		seconds = seconds,
		beat = true,
		clock = function(): number
			local _, t = StoryClient.missionScene()
			return t
		end,
		canSkip = function(): boolean
			local _, t = StoryClient.missionScene()
			return StoryClient.mission.seen == true and t >= Config.Cinema.skipDelay
		end,
		skip = function()
			Net.send("SceneSkip")
		end,
	})
end

local function sceneStep()
	local st = StoryClient.missionScene()
	local m = StoryClient.mission
	local r = heroRoot()
	if not st or not r then
		if sceneKey ~= nil then
			CinemaClient.stop("mission")
			sceneKey = nil
		end
		lodestarStep(if StoryClient.inMission() and st then m.lodestar else nil, nil)
		return
	end
	lodestarStep(m.lodestar, r.Position)
	if sceneKey ~= st then
		sceneKey = st
		playScene(st, r)
	end
	-- (lore step 6: each line's blip is the guide line queue's, Ui.GuideHud)
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
		sceneStep()
	end))
end

return StoryFx
