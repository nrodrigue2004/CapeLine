-- Fx.IntroFilm: plays Shared.IntroFilm, a new account's first 45 seconds as one in-engine film, in the real city
-- round the spot the hero waits in (list-combat 2026-11-20, nate: a cold open "before anything else", then short
-- in-engine cutscenes that explain the world instead of the 4-panel intro comic; "make sure it looks very nice and
-- isn't boring": real meshes and lighting in every shot, a cut every 2 to 4 s, effects, destruction and sound).
-- * The server sends the stage with OpeningIntro (OpeningService.introStage: the real tower, the far roof, the
--   street); StoryClient.playIntro hands it here (StoryClient.filmScene) and plays the scene through CinemaClient
--   as a live camera (`follow`), so the letterbox, SKIP (from Config.Story.opening.intro.skipAfter) and the end
--   (the creator opens, or a replay's prologue) work as the comic page did. No stage: the comic page plays.
-- * The cast are the game's own figures on this device only: Lodestar (PrologueFx.lodestarRig) as the hero who
--   smashes through the tower, Crane Troopers (EnemyRenderer.figure), Silas Crane and the three famous fakes
--   (PrologueFx.cast), a Dread Syndicate crook in Syndicate pieces (Config.Story.opening.film.syndicate), the
--   crowd and "you". Poses from Shared.HeroAnim (fly, pound, hover) on Motor6D.Transform, a stride for walkers.
-- * The tower really breaks on this device: BuildingFx.predict knocks the wall's pieces out where the hero goes in
--   and out (held for the film, then healed: the server's city never changes); the landing cracks the street
--   (BuildingFx.landing). Drone bolts, the drone's blast, the scanner's red cone, Radiant's face crack, the spark.
-- * On screen: comic captions (the lore doc's words and the game's lines), comic sound words in the world, the
--   CAPELINE title slam, the white flash. Music: the boss track for the cold open, then the night patrol
--   (AudioController.musicOverride). One RenderStepped step under FrameProf; actors are built a few a frame
--   ahead of their first shot and destroyed once their part is over.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local IntroFilm = require(Shared:WaitForChild("IntroFilm"))
local HeroAnim = require(Shared:WaitForChild("HeroAnim"))
local NpcRig = require(Shared:WaitForChild("NpcRig"))

local StoryClient = require(script.Parent.Parent.Controllers.StoryClient)
local CinemaClient = require(script.Parent.Parent.Controllers.CinemaClient)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local EnemyRenderer = require(script.Parent.Parent.Controllers.EnemyRenderer)
local AudioController = require(script.Parent.Parent.Controllers.AudioController)
local BuildingFx = require(script.Parent.BuildingFx)
local FxLib = require(script.Parent.FxLib)
local PrologueFx = require(script.Parent.PrologueFx)
local Kit = require(script.Parent.Parent.Ui.Kit)

local IntroFilmFx = {}

local F = Config.Story.opening.film
local GLOW = Color3.fromRGB(F.glow[1], F.glow[2], F.glow[3])
local RED = Color3.fromRGB(255, 50, 50)
local CONCRETE = Color3.fromRGB(165, 160, 152)
local GLASS = Color3.fromRGB(190, 230, 255)
local INK = Color3.fromRGB(18, 18, 22)
local PAPER = Color3.fromRGB(255, 226, 90)

type Actor = {
	track: IntroFilm.Track,
	rig: any?,
	model: Model?,
	first: number, -- the first time it shows
	last: number, -- after this it is gone for good
	shown: boolean,
	dead: boolean,
	phase: number,
}

local film: IntroFilm.Film? = nil
local stage: IntroFilm.Stage? = nil
local folder: Folder? = nil
local actors: { [string]: Actor } = {}
local order: { Actor } = {}
local nextEvent, nextWord, building = 1, 1, false
local gui: ScreenGui? = nil
local caption: Frame? = nil
local captionText: TextLabel? = nil
local captionShown = 0
local title: TextLabel? = nil
local flash: Frame? = nil
local sparkLight: PointLight? = nil

local function V(p: { number }): Vector3
	return Vector3.new(p[1], p[2], p[3])
end

local function toCFrame(a: { number }): CFrame
	local cf = CFrame.Angles(math.rad(a[1]), math.rad(a[2]), math.rad(a[3]))
	if (a[4] or 0) ~= 0 then
		cf = CFrame.new(0, a[4], 0) * cf
	end
	return cf
end

---------------------------------------------------------------------------
-- The screen: captions, the title, the flash
---------------------------------------------------------------------------

local function buildGui()
	if gui then
		return
	end
	local g = Kit.screen("IntroFilm", 7) -- over the letterbox (CinemaHud 6), under the comic page and SKIP
	g.IgnoreGuiInset = true
	g.Enabled = false
	local bar = Config.Cinema.letterbox.size
	-- the comic caption box: ink border, yellow paper, the comic face, top left of the frame
	local box = Instance.new("Frame")
	box.Name = "Caption"
	box.AnchorPoint = Vector2.new(0, 0)
	box.Position = UDim2.new(0.035, 0, bar + 0.03, 0)
	box.Size = UDim2.fromScale(0.42, 0.1)
	box.BackgroundColor3 = PAPER
	box.BorderSizePixel = 0
	box.Visible = false
	box.Rotation = -1.5
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = INK
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = box
	local cons = Instance.new("UISizeConstraint")
	cons.MinSize = Vector2.new(220, 44)
	cons.MaxSize = Vector2.new(560, 110)
	cons.Parent = box
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.Size = UDim2.new(1, -20, 1, -10)
	text.Position = UDim2.fromOffset(10, 5)
	text.Font = Kit.font
	text.TextScaled = true
	text.TextWrapped = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextColor3 = INK
	text.Text = ""
	text.Parent = box
	box.Parent = g
	-- the title: CAPELINE slams in over the landing
	local t = Instance.new("TextLabel")
	t.Name = "Title"
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = UDim2.fromScale(0.5, 0.42)
	t.Size = UDim2.fromScale(0.7, 0.22)
	t.BackgroundTransparency = 1
	t.Font = Kit.font
	t.Text = "CAPELINE"
	t.TextScaled = true
	t.TextColor3 = PAPER
	t.Visible = false
	local ts = Instance.new("UIStroke")
	ts.Thickness = 6
	ts.Color = INK
	ts.Parent = t
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(255, 245, 170), Color3.fromRGB(255, 150, 40))
	grad.Rotation = 90
	grad.Parent = t
	t.Parent = g
	-- the white frame (the spark's flash and the cut to the creator)
	local f = Instance.new("Frame")
	f.Name = "Flash"
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.ZIndex = 5
	f.Parent = g
	gui, caption, captionText, title, flash = g, box, text, t, f
end

local function showCaption(c: IntroFilm.Caption?)
	local box, text = caption, captionText
	if not box or not text then
		return
	end
	if not c then
		box.Visible = false
		return
	end
	text.Text = string.upper(c.text)
	box.Visible = true
	box.Position = UDim2.new(-0.5, 0, box.Position.Y.Scale, 0)
	TweenService:Create(
		box,
		TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.035, 0, box.Position.Y.Scale, 0) }
	):Play()
end

local function slamTitle()
	local t = title
	if not t then
		return
	end
	t.Visible = true
	t.Size = UDim2.fromScale(2.2, 0.66)
	t.TextTransparency = 0.4
	t.Rotation = -8
	TweenService:Create(t, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(0.7, 0.22),
		TextTransparency = 0,
		Rotation = -3,
	}):Play()
	task.delay(0.28, function()
		CameraController.shake(0.35, 1.4)
		AudioController.play("crater", nil, { volume = 0.9, pitch = 0.8 })
	end)
	-- it holds, then drifts up and out as the world's beats start
	task.delay(1.6, function()
		if title == t then
			TweenService:Create(t, TweenInfo.new(0.4), {
				Position = UDim2.fromScale(0.5, 0.3),
				TextTransparency = 1,
			}):Play()
		end
	end)
end

local function white(hold: number, out: number)
	local f = flash
	if not f then
		return
	end
	f.BackgroundTransparency = 0
	TweenService
		:Create(f, TweenInfo.new(out, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, hold), {
			BackgroundTransparency = 1,
		})
		:Play()
end

---------------------------------------------------------------------------
-- Sound words in the world (comic lettering on a billboard that pops in)
---------------------------------------------------------------------------

local function word(text: string, at: Vector3, big: boolean)
	local att = Instance.new("Attachment")
	att.Position = at -- on Terrain (at the origin), so this is the world position
	att.Parent = Workspace.Terrain
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(if big then 26 else 16, if big then 9 else 5.5)
	bb.LightInfluence = 0
	bb.AlwaysOnTop = true
	bb.MaxDistance = 600
	bb.Parent = att
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.fromScale(0.5, 0.5)
	l.Size = UDim2.fromScale(0.3, 0.3)
	l.BackgroundTransparency = 1
	l.Font = Kit.font
	l.Text = text
	l.TextScaled = true
	l.Rotation = math.random(-12, 12)
	l.TextColor3 = if text == "SPARK DETECTED" then RED else PAPER
	local s = Instance.new("UIStroke")
	s.Thickness = 4
	s.Color = INK
	s.Parent = l
	l.Parent = bb
	TweenService:Create(l, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(1, 1),
	}):Play()
	task.delay(0.9, function()
		TweenService:Create(l, TweenInfo.new(0.3), { TextTransparency = 1, Size = UDim2.fromScale(1.3, 1.3) })
			:Play()
		TweenService:Create(s, TweenInfo.new(0.3), { Transparency = 1 }):Play()
	end)
	task.delay(1.3, function()
		att:Destroy()
	end)
end

---------------------------------------------------------------------------
-- The cast
---------------------------------------------------------------------------

local function firstShow(tr: IntroFilm.Track): (number, number)
	local first, last = math.huge, 0
	for i, k in tr.keys do
		if not k.hide then
			first = math.min(first, k.t)
			-- shown until the next key (a hidden key ends it)
			local nk = tr.keys[i + 1]
			last = math.max(last, if nk then nk.t else k.t)
		end
	end
	return first, last
end

local function make(a: Actor, f: Folder)
	local tr = a.track
	local id = tr.id
	local rig: any
	if tr.kind == "drone" then
		local _, r = EnemyRenderer.figure("SparkDrone", 9000 + #id * 37 + string.byte(id, -1), f)
		rig = r
	elseif tr.kind == "lodestar" then
		rig = PrologueFx.lodestarRig(f)
		if id == "hero" then
			-- no name plate on the streak through the tower; a gold trail off the shoulders
			for _, d in rig.model:GetDescendants() do
				if d:IsA("BillboardGui") then
					d.Enabled = false
				end
			end
			local torso = rig.parts.UpperTorso
			if torso then
				local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
				a0.Position = Vector3.new(-torso.Size.X / 2, 0.4, 0)
				a1.Position = Vector3.new(torso.Size.X / 2, 0.4, 0)
				a0.Parent, a1.Parent = torso, torso
				local trail = Instance.new("Trail")
				trail.Attachment0, trail.Attachment1 = a0, a1
				trail.Lifetime = 0.35
				trail.Color = ColorSequence.new(GLOW, Color3.fromRGB(255, 140, 40))
				trail.Transparency = NumberSequence.new(0.2, 1)
				trail.LightEmission = 0.8
				trail.FaceCamera = true
				trail.WidthScale = NumberSequence.new(1, 0.2)
				trail.Parent = torso
			end
		end
	elseif tr.kind == "crane" then
		rig = PrologueFx.cast("crane", f)
	elseif tr.kind == "fake" then
		rig = PrologueFx.cast(id, f)
	elseif tr.kind == "villain" then
		rig = PrologueFx.cast("Dread Syndicate", f, nil, F.syndicate)
	elseif tr.kind == "you" then
		rig = PrologueFx.cast("citizen", f, F.you)
	else
		rig = PrologueFx.cast("citizen", f, #id + string.byte(id, -1))
	end
	a.rig = rig
	a.model = rig and rig.model
	if a.model then
		a.model.Parent = nil -- shown by the step when its time comes
	end
end

local function pose(a: Actor, clip: string?, t: number)
	local rig = a.rig
	if not rig then
		return
	end
	if clip == "walk" or clip == "sprint" then
		local speed = if clip == "sprint" then 18 else 6
		local swing = math.sin(t * (6 + speed * 0.3) + a.phase) * math.clamp(speed / 14, 0, 1) * 0.8
		for _, s in { { "Left", 1 }, { "Right", -1 } } do
			NpcRig.turn(rig, s[1] .. "Hip", CFrame.Angles(swing * s[2], 0, 0))
			NpcRig.turn(rig, s[1] .. "Knee", CFrame.Angles(-math.max(0, swing * s[2]) * 0.9, 0, 0))
			NpcRig.turn(
				rig,
				s[1] .. "Shoulder",
				CFrame.Angles(-swing * s[2] * 0.9 + (if speed > 8 then 0.5 else 0), 0, 0)
			)
		end
		return
	end
	local angles = if clip then HeroAnim.sample(clip, t + a.phase) else nil
	if not angles then
		return
	end
	for joint in rig.motors do
		local k = angles[joint]
		NpcRig.turn(rig, joint, if k then toCFrame(k) else CFrame.identity)
	end
end

---------------------------------------------------------------------------
-- The events
---------------------------------------------------------------------------

local function actorAt(id: string?, t: number): Vector3?
	local a = id and actors[id]
	if not a then
		return nil
	end
	local p = IntroFilm.at(a.track, t)
	return V(p)
end

local function bolt(from: Vector3, to: Vector3)
	local f = folder
	if not f then
		return
	end
	local d = to - from
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	p.Color = RED
	p.Size = Vector3.new(0.35, 0.35, d.Magnitude)
	p.CFrame = CFrame.lookAt(from + d / 2, to)
	p.Parent = f
	TweenService
		:Create(p, TweenInfo.new(0.18), { Transparency = 1, Size = Vector3.new(0.1, 0.1, d.Magnitude) })
		:Play()
	task.delay(0.2, function()
		p:Destroy()
	end)
	FxLib.impact(to, "tech", RED, 0.8, -d.Unit)
	AudioController.play("basic", from, { volume = 0.5, pitch = 1.3 })
end

local function smash(at: Vector3, along: Vector3, glass: boolean)
	local st = stage
	local fl = film
	if not st or not fl then
		return
	end
	-- the real wall's pieces knocked out on this device, held to the end of the film
	BuildingFx.predict(st.tower.id, at, 6000, 8, fl.seconds + 2)
	FxLib.burst(at, 9, "earth", CONCRETE, true)
	FxLib.emit("rock", CONCRETE, at, 14, along)
	FxLib.emit("chip", CONCRETE, at, 16, along)
	FxLib.emit("cloud", CONCRETE, at, 4, along)
	if glass then
		FxLib.emit("shard", GLASS, at, 22, along)
	end
	CameraController.shake(0.45, if glass then 1.1 else 1.5)
	AudioController.play("collapse", at, { volume = 0.9 })
	AudioController.play("wallSmash", at, { volume = 1 })
end

local function crackFace(a: Actor?)
	local rig = a and a.rig
	local head = rig and rig.parts and rig.parts.Head
	if not head then
		return
	end
	-- half the face gone to metal, a red eye glowing through (the famous hero is a robot)
	local plateP = Instance.new("Part")
	plateP.Anchored, plateP.CanCollide, plateP.CanQuery, plateP.CanTouch = false, false, false, false
	plateP.Massless = true
	plateP.Material = Enum.Material.Metal
	plateP.Color = Color3.fromRGB(150, 156, 168)
	plateP.Size = Vector3.new(head.Size.X * 0.5, head.Size.Y * 0.8, 0.08)
	NpcRig.fix(rig, "Head", plateP, CFrame.new(head.Size.X * 0.24, 0, -head.Size.Z / 2 - 0.04))
	local eye = Instance.new("Part")
	eye.Anchored, eye.CanCollide, eye.CanQuery, eye.CanTouch = false, false, false, false
	eye.Massless = true
	eye.Material = Enum.Material.Neon
	eye.Color = RED
	eye.Shape = Enum.PartType.Ball
	eye.Size = Vector3.new(0.28, 0.28, 0.28)
	NpcRig.fix(rig, "Head", eye, CFrame.new(head.Size.X * 0.22, head.Size.Y * 0.08, -head.Size.Z / 2 - 0.1))
	local l = Instance.new("PointLight")
	l.Color = RED
	l.Range = 6
	l.Brightness = 3
	l.Parent = eye
	FxLib.emit("crackle", Color3.fromRGB(140, 200, 255), head.Position, 6)
	FxLib.emit("spark", Color3.fromRGB(255, 210, 120), head.Position, 10)
	AudioController.play("shatter", head.Position, { volume = 0.7, pitch = 1.2 })
end

local function scanCone(from: Vector3, to: Vector3)
	local f = folder
	if not f then
		return
	end
	local d = to - from
	local cone = Instance.new("Part")
	cone.Anchored, cone.CanCollide, cone.CanQuery, cone.CanTouch, cone.CastShadow =
		true, false, false, false, false
	cone.Material = Enum.Material.Neon
	cone.Color = RED
	cone.Transparency = 0.7
	cone.Shape = Enum.PartType.Cylinder
	cone.Size = Vector3.new(d.Magnitude, 0.6, 0.6)
	cone.CFrame = CFrame.lookAt(from + d / 2, to) * CFrame.Angles(0, math.rad(90), 0)
	cone.Parent = f
	local ring = Instance.new("Part")
	ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch, ring.CastShadow =
		true, false, false, false, false
	ring.Material = Enum.Material.Neon
	ring.Color = RED
	ring.Transparency = 0.5
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, 9, 9)
	ring.CFrame = CFrame.new(to - Vector3.new(0, 1.9, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = f
	TweenService
		:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			Size = Vector3.new(0.2, 5, 5),
		})
		:Play()
	AudioController.play("bossWarning", to, { volume = 0.45, pitch = 1.4 })
	task.delay(3.6, function()
		cone:Destroy()
		ring:Destroy()
	end)
end

local function spark(a: Actor?)
	local rig = a and a.rig
	local torso = rig and rig.parts and rig.parts.UpperTorso
	if not torso then
		return
	end
	local l = Instance.new("PointLight")
	l.Color = GLOW
	l.Range = 0
	l.Brightness = 6
	l.Shadows = false
	l.Parent = torso
	sparkLight = l
	TweenService:Create(l, TweenInfo.new(1.6, Enum.EasingStyle.Quad), { Range = 22 }):Play()
	FxLib.gather(torso.Position, "electric", GLOW)
	FxLib.charge(torso.Position, "electric", GLOW)
	FxLib.emit("crackle", GLOW, torso.Position, 10)
	FxLib.emit("star", GLOW, torso.Position, 8)
	AudioController.play("chargeFull", torso.Position, { volume = 0.9 })
	task.delay(0.8, function()
		if sparkLight == l then
			FxLib.emit("crackle", GLOW, torso.Position, 12)
			FxLib.emit("glow", GLOW, torso.Position, 3)
		end
	end)
end

local function fire(e: IntroFilm.Event, t: number)
	local kind = e.kind
	if kind == "music" then
		AudioController.musicOverride = e.text
	elseif kind == "whoosh" then
		local p = actorAt(e.actor, t)
		AudioController.play("sonicBoom", p, { volume = 0.8 })
	elseif kind == "shot" then
		local from = actorAt(e.actor, t)
		if from and e.q then
			bolt(from + Vector3.new(0, 3, 0), V(e.q))
		end
	elseif kind == "smash" and e.p and e.q then
		smash(V(e.p), V(e.q), e.text == "glass")
	elseif kind == "boom" then
		local a = e.actor and actors[e.actor]
		local p = actorAt(e.actor, t)
		if a and p then
			a.dead = true
			if a.model then
				a.model.Parent = nil
			end
			FxLib.burst(p, 8, "fire", Color3.fromRGB(255, 150, 50), true)
			FxLib.wreck(p)
			FxLib.emit("smoke", Color3.fromRGB(60, 60, 66), p, 6)
			AudioController.play("crit", p, { volume = 0.9, pitch = 0.8 })
		end
	elseif kind == "land" and e.p then
		local p = V(e.p)
		BuildingFx.landing(p, 9)
		FxLib.dust(p, 14)
		FxLib.shock(p + Vector3.new(0, 0.3, 0), 16, GLOW)
		FxLib.emit("rock", CONCRETE, p, 12, Vector3.new(0, 1, 0))
		CameraController.shake(0.5, 1.8)
		AudioController.play("pound", p, { volume = 1 })
		AudioController.play("land", p, { volume = 1, pitch = 0.8 })
	elseif kind == "title" then
		slamTitle()
	elseif kind == "scan" then
		local from = actorAt(e.actor, t)
		if from and e.q then
			scanCone(from + Vector3.new(0, 3, 0), V(e.q) + Vector3.new(0, 2, 0))
		end
	elseif kind == "crack" then
		crackFace(e.actor and actors[e.actor])
	elseif kind == "rise" then
		AudioController.play("bossPhase", nil, { volume = 0.5 })
	elseif kind == "spark" then
		spark(e.actor and actors[e.actor])
	elseif kind == "flash" then
		white(0.15, 0.5)
		AudioController.play("super", nil, { volume = 0.8 })
	end
end

---------------------------------------------------------------------------
-- The step
---------------------------------------------------------------------------

local function stop()
	local f = folder
	folder = nil
	film, stage = nil, nil
	if f then
		f:Destroy()
	end
	table.clear(actors)
	table.clear(order)
	sparkLight = nil
	AudioController.musicOverride = nil
	if gui then
		gui.Enabled = false
	end
	if caption then
		caption.Visible = false
	end
	if title then
		title.Visible = false
	end
end

-- build the cast a few a frame, each a little before its first shot
local function buildAhead(t: number)
	local f = folder
	if not f or building then
		return
	end
	local made = 0
	for _, a in order do
		if not a.rig and not a.dead and a.first - t < 2.5 then
			building = true
			local ok, err = pcall(make, a, f)
			building = false
			if not ok then
				warn("[IntroFilm] actor", a.track.id, err)
				a.dead = true
			end
			made += 1
			if made >= 2 then
				return
			end
		end
	end
end

local function step()
	local fl = film
	if not fl then
		return
	end
	local s = CinemaClient.current
	if not s or s.key ~= "intro" or not s.follow then
		stop()
		return
	end
	local t = CinemaClient.time()
	buildAhead(t)
	for _, a in order do
		local model = a.model
		if model and not a.dead then
			local p, yaw, clip, show = IntroFilm.at(a.track, t)
			show = show and t <= a.last
			if show then
				if model.Parent ~= folder then
					model.Parent = folder
				end
				local cf = CFrame.new(V(p)) * CFrame.Angles(0, yaw, 0)
				if clip == "fly" then
					cf = cf * CFrame.new(0, 3, 0) * CFrame.Angles(math.rad(-78), 0, 0) * CFrame.new(0, -3, 0)
				end
				NpcRig.place(a.rig, cf)
				pose(a, clip, t)
			elseif model.Parent ~= nil then
				model.Parent = nil
			end
			if t > a.last + 0.5 then
				a.dead = true
				model:Destroy()
				a.model = nil
			end
		end
	end
	while nextEvent <= #fl.events and fl.events[nextEvent].t <= t do
		fire(fl.events[nextEvent], t)
		nextEvent += 1
	end
	while nextWord <= #fl.words and fl.words[nextWord].t <= t do
		local w = fl.words[nextWord]
		local at = if w.p then V(w.p) else actorAt(w.actor, t)
		if at and w.text then
			word(w.text, at + Vector3.new(0, if w.actor then 6 else 2, 0), w.actor == nil)
		end
		nextWord += 1
	end
	-- the caption on screen now
	local cur = 0
	for i, c in fl.captions do
		if t >= c.t0 and t < c.t1 then
			cur = i
		end
	end
	if cur ~= captionShown then
		captionShown = cur
		showCaption(if cur > 0 then fl.captions[cur] else nil)
	end
end

-- The scene for the stage the server sent (nil: no film; the comic page plays). StoryClient.playIntro plays it.
function IntroFilmFx.scene(st: any, base: { [string]: any }): any?
	if not F.on or type(st) ~= "table" or type(st.tower) ~= "table" then
		return nil
	end
	local ok, fl = pcall(IntroFilm.film, Config, st)
	if not ok then
		warn("[IntroFilm]", fl)
		return nil
	end
	stop()
	buildGui()
	film, stage = fl, st
	local f = Instance.new("Folder")
	f.Name = "IntroFilm"
	f.Parent = Workspace
	folder = f
	nextEvent, nextWord, captionShown = 1, 1, 0
	for _, tr in fl.tracks do
		local first, last = firstShow(tr)
		local a: Actor = {
			track = tr,
			first = first,
			last = last,
			shown = false,
			dead = false,
			phase = math.random() * 2,
		}
		actors[tr.id] = a
		table.insert(order, a)
	end
	table.sort(order, function(x, y)
		return x.first < y.first
	end)
	buildAhead(0)
	if gui then
		gui.Enabled = true
	end
	-- the city round the stage streamed in for the camera (it may sit past the hero's own streaming radius)
	local T = st.tower
	task.spawn(function()
		local lp = Players.LocalPlayer
		for _, at in { Vector3.new(T.x, T.base + 20, T.z), Vector3.new(st.far.x, st.far.top, st.far.z) } do
			pcall(function()
				lp:RequestStreamAroundAsync(at, 4)
			end)
		end
	end)
	local scene = table.clone(base)
	scene.seconds = fl.seconds
	scene.shots = {}
	scene.comic = nil
	scene.follow = function(_dt: number): (Vector3, Vector3)
		local pos, look = IntroFilm.camera(fl, CinemaClient.time())
		return V(pos), V(look)
	end
	return scene
end

function IntroFilmFx.init()
	StoryClient.filmScene = IntroFilmFx.scene
	RunService.RenderStepped:Connect(FrameProf.wrap("IntroFilm", step))
end

return IntroFilmFx
