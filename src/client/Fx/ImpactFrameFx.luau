-- ImpactFrameFx: the big blows' impact frames on this screen (first-30, nate 2026-11-20: "Do we have hit
-- stop/freeze frames/flash frames ... the game being cinematic is also one of the most important things";
-- Shared.ImpactFrames, Config.Cinema.impactFrames). For 2 to 4 frames the whole picture goes stark black and white
-- (a ColorCorrection on Lighting: white frames blown out, black frames crushed under a black wash) with ink lines
-- bursting from the hit's point on screen (black on a white frame, white on a black one); Comic adds the black
-- hit star at the point. Your own clip holds still under the cut. Reduce flashing never cuts: a gentle hit stop.
-- Called by CombatClient (your crits and supers) and FinisherFx (finishers).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local ImpactFrames = require(Shared:WaitForChild("ImpactFrames"))

local State = require(script.Parent.Parent.State)
local HeroAnimator = require(script.Parent.Parent.Controllers.HeroAnimator)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)

local ImpactFrameFx = {}

local I = Config.Cinema.impactFrames
local STAR = Config.Fx.lib.textures.hitstar
local last = { kind = nil :: string?, at = -math.huge }
local cur: ImpactFrames.Plan? = nil
local curAt = 0
local curPoint = Vector2.zero
local curSeed = 0
local shownLook: string? = nil

local gui: ScreenGui? = nil
local wash: Frame
local star: ImageLabel
local lines: { Frame } = {}
local cc: ColorCorrectionEffect? = nil

local function build()
	if gui then
		return
	end
	local g = Instance.new("ScreenGui")
	g.Name = "ImpactFrame"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 90 -- over the HUD: the whole picture cuts
	g.Enabled = false
	g.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	wash = Instance.new("Frame")
	wash.Name = "Wash"
	wash.BorderSizePixel = 0
	wash.Size = UDim2.fromScale(1, 1)
	wash.BackgroundColor3 = Color3.new(0, 0, 0)
	wash.Parent = g
	star = Instance.new("ImageLabel")
	star.Name = "Star"
	star.BackgroundTransparency = 1
	star.AnchorPoint = Vector2.new(0.5, 0.5)
	star.Image = if STAR.id and STAR.id > 0
		then "rbxassetid://" .. string.format("%d", STAR.id)
		else STAR.builtin
	star.ImageColor3 = Color3.new(0, 0, 0)
	star.ZIndex = 3
	star.Parent = g
	local most = math.max(I.lines.Comic, I.lines.Anime)
	for i = 1, most do
		local l = Instance.new("Frame")
		l.Name = "Line" .. i
		l.BorderSizePixel = 0
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.ZIndex = 2
		l.Parent = g
		lines[i] = l
	end
	gui = g
end

local function setLook(look: string?)
	if look == shownLook then
		return
	end
	shownLook = look
	local g = gui :: ScreenGui
	if not look then
		g.Enabled = false
		if cc then
			cc.Enabled = false
		end
		return
	end
	if not cc then
		local made = Instance.new("ColorCorrectionEffect")
		made.Name = "ImpactFrame"
		made.Parent = Lighting
		cc = made
	end
	local c = cc :: ColorCorrectionEffect
	local L = if look == "white" then I.white else I.black
	c.Saturation, c.Contrast, c.Brightness = L.saturation, L.contrast, L.brightness
	c.TintColor = Color3.new(1, 1, 1)
	c.Enabled = true
	local plan = cur :: ImpactFrames.Plan
	local cam = Workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	local ink = if look == "white" then Color3.new(0, 0, 0) else Color3.new(1, 1, 1)
	wash.BackgroundTransparency = if look == "white" then 1 else 1 - I.black.cover
	local reach = (vp.Magnitude + curPoint.Magnitude) -- long enough to run off every edge
	local inner = vp.Y * I.inner
	for i, l in lines do
		if i <= plan.lines then
			local a, w = ImpactFrames.line(plan, i, curSeed)
			local len = reach
			local mid = curPoint + Vector2.new(math.cos(a), math.sin(a)) * (inner + len / 2)
			l.Position = UDim2.fromOffset(mid.X, mid.Y)
			l.Size = UDim2.fromOffset(len, w)
			l.Rotation = math.deg(a)
			l.BackgroundColor3 = ink
			l.Visible = true
		else
			l.Visible = false
		end
	end
	star.Visible = State.hero.fxStyle ~= "Anime" and look == "white"
	local s = vp.Y * 0.32
	star.Size = UDim2.fromOffset(s, s)
	star.Position = UDim2.fromOffset(curPoint.X, curPoint.Y)
	g.Enabled = true
end

-- A big blow landed at `at`: cut to its impact frames (kind: "crit", "super" or "finisher")
function ImpactFrameFx.cut(kind: string, at: Vector3?)
	local now = os.clock()
	local plan = ImpactFrames.plan(Config, kind, State.hero.fxStyle, CameraController.reduceMotion, now, last)
	if not plan then
		return
	end
	if plan.gentle then
		HeroAnimator.freeze(plan.gentle) -- Reduce flashing: a gentle hit stop, never a flash
		return
	end
	build()
	local cam = Workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	local point = vp / 2
	if cam and at then
		local v, onScreen = cam:WorldToViewportPoint(at)
		if onScreen and v.Z > 0 then
			point = Vector2.new(v.X, v.Y)
		end
	end
	cur, curAt, curPoint, curSeed = plan, now, point, math.floor(now * 1000) % 997
	shownLook = nil
	HeroAnimator.freeze(plan.seconds) -- the game holds still under the cut
end

-- Is a cut on screen now?
function ImpactFrameFx.cutting(): boolean
	return cur ~= nil
end

local function frame()
	local plan = cur
	if not plan then
		return
	end
	local f = ImpactFrames.at(plan, os.clock() - curAt)
	if not f then
		cur = nil
		setLook(nil)
		return
	end
	setLook(f.look)
end

function ImpactFrameFx.init()
	RunService.RenderStepped:Connect(FrameProf.wrap("ImpactFrameFx", frame))
end

return ImpactFrameFx
