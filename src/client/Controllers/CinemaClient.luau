-- CinemaClient: the one cutscene player (nate's lore, build plan step 7; Shared.CinemaPlan, Config.Cinema).
-- Every camera beat in the game plays through it: the prologue's (PrologueFx), the missions' (StoryFx) and the
-- device-started scenes (the Dev panel's samples: an in-engine scene and a comic-panel flashback page).
-- * A scene: shots (cut, dolly, orbit, look), its length, optional subtitles (CinemaHud feeds the guide line
--   box, Ui.GuideHud), and for a server beat its clock (the server times the beat), whether SKIP may show and
--   what SKIP does. The camera goes Scriptable for the scene and the hero holds still on this device (the
--   server still moves it); both come back when it ends.
-- * Skippable only once the save has seen that scene (profile.seen; CinemaPlan.canSkip), and never in its
--   first moment. A device-started scene that ends (or is skipped) sends SceneSeen.
-- * Never while a fight would leave you defenceless: server beats are safe by design (the prologue's camera
--   beats, a mission pocket's scene step); a device-started scene waits for a quiet moment (CinemaPlan.safe)
--   and stops at once if the hero is hit.
-- * The camera step makes no new tables (one shared buffer); only the CFrame it writes is new.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local CinemaPlan = require(Shared:WaitForChild("CinemaPlan"))

local State = require(script.Parent.Parent.State)
local CameraController = require(script.Parent.CameraController)
local QualityController = require(script.Parent.QualityController)
local CamClear = require(script.Parent.CamClear)
local Lighting = game:GetService("Lighting")

local CinemaClient = {}

export type Scene = {
	owner: string, -- "prologue", "mission" or "client"
	key: any, -- which beat (a new key restarts the scene)
	id: string?, -- Config.Cinema.scenes id (client scenes)
	bit: number?,
	shots: { CinemaPlan.Shot },
	seconds: number,
	lines: { any }?,
	comic: string?, -- a comic-panel page (CinemaHud draws it; the camera stays as it is)
	beat: boolean?, -- a server beat (safe by design, timed by the server)
	clock: (() -> number)?, -- seconds in (server beats)
	bars: (() -> boolean)?, -- letterbox shows (default: always)
	canSkip: (() -> boolean)?,
	skip: (() -> ())?,
	startedAt: number?,
	-- fix-flow (2026-11-19, the prologue's rooftop chase): a live camera instead of shots (it writes the camera's
	-- position and look point each frame), and `free`: the hero is not held still (it moves in the scene)
	follow: ((dt: number) -> (Vector3, Vector3))?,
	free: boolean?,
}

CinemaClient.Changed = Signal.new() -- (scene?) a scene started or ended
CinemaClient.current = nil :: Scene?
CinemaClient.lastHit = 0 -- os.clock() of the last hit taken (CombatClient)
-- (set at boot) the safe-moment facts for a device-started scene: { hitAgo, enemy, downed, pvp, boss }
CinemaClient.context = nil :: (() -> { [string]: any })?

local player = Players.LocalPlayer
local camOn = false
local anchored: BasePart? = nil
local buf = table.create(6, 0)
-- (first-30 polish round 2) the shot last drawn and its camera, for easing across jump cuts
local lastShot: any = nil
local lastCf: CFrame? = nil
local easeFrom: CFrame? = nil
local pull = CamClear.newPull() -- (nate's playtest 2026-11-21) the shot's camera kept in front of walls
local lensOn = false
-- Told where a scene's camera is each frame it runs, and nil once it stops (init.client: CityLife and
-- CitizenRenderer keep cars and people out of the lens, CamClear fades anything else moving right at it)
CinemaClient.onLens = nil :: ((at: Vector3?) -> ())?

local function lens(at: Vector3?)
	if at == nil and not lensOn then
		return
	end
	lensOn = at ~= nil
	local f = CinemaClient.onLens
	if f then
		f(at)
	end
end
local easeAt = 0
local localSeen: { [number]: boolean } = {}
local waiting: { scene: Scene, untilT: number }? = nil

local function root(): BasePart?
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Has this save seen the scene with this bit?
function CinemaClient.seen(bit: number?): boolean
	if bit == nil then
		return false
	end
	local b: number = bit
	return localSeen[b] == true or CinemaPlan.seen(State.profile.seen, b)
end

local function setCamera(on: boolean, free: boolean?)
	local cam = Workspace.CurrentCamera
	if not cam or on == camOn then
		return
	end
	camOn = on
	local CCam = Config.Cinema.camera
	if on then
		CameraController.fovOverride = CCam.fov
		cam.CameraType = Enum.CameraType.Scriptable
		local r = root()
		if r and not free then
			r.Anchored = true -- the hero holds still for the scene (on this device only)
			anchored = r
		end
	else
		CameraController.fovOverride = nil
		local last = cam.CFrame
		cam.CameraType = Enum.CameraType.Custom
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			cam.CameraSubject = hum
			-- first-30 polish: ease from the last shot to the follow camera, no snap behind the hero
			CameraController.blendFrom(last, CCam.blendOut)
		end
		if anchored then
			anchored.Anchored = false
			anchored = nil
		end
	end
end

-- Seconds into the scene playing
function CinemaClient.time(): number
	local s = CinemaClient.current
	if not s then
		return 0
	end
	if s.clock then
		return s.clock()
	end
	return os.clock() - (s.startedAt or os.clock())
end

function CinemaClient.playing(): boolean
	return CinemaClient.current ~= nil
end

-- Is the letterbox up?
function CinemaClient.letterboxed(): boolean
	local s = CinemaClient.current
	if not s or s.comic then
		return false
	end
	return if s.bars then s.bars() else true
end

-- Does the scene playing carry its own subtitles (a device-started scene)?
function CinemaClient.ownLines(): boolean
	local s = CinemaClient.current
	return s ~= nil and s.lines ~= nil
end

-- May SKIP show now?
function CinemaClient.skippable(): boolean
	local s = CinemaClient.current
	if not s then
		return false
	end
	if s.canSkip then
		return s.canSkip()
	end
	return CinemaClient.seen(s.bit) and CinemaClient.time() >= Config.Cinema.skipDelay
end

local function finish(markSeen: boolean, keepCamera: boolean?)
	local s = CinemaClient.current
	if not s then
		return
	end
	CinemaClient.current = nil
	if not keepCamera then
		setCamera(false)
	end
	if markSeen and s.owner == "client" and s.bit then
		localSeen[s.bit] = true
		Net.send("SceneSeen", s.bit)
	end
	CinemaClient.Changed:Fire(nil)
end

-- Play a scene. A server beat starts at once; a device-started one waits for a safe moment (up to
-- Config.Cinema.safe.waitSeconds). Returns whether it started now, and why not.
function CinemaClient.play(scene: Scene): (boolean, string?)
	local cur = CinemaClient.current
	if cur and cur.owner == scene.owner and cur.key == scene.key then
		return true, nil -- already playing
	end
	if not scene.beat then
		if cur and cur.beat then
			return false, "beat" -- a story beat is on
		end
		local ctx = if CinemaClient.context then CinemaClient.context() else {}
		local ok, why = CinemaPlan.safe(Config, ctx)
		if not ok then
			if not waiting or waiting.scene ~= scene then
				waiting = { scene = scene, untilT = os.clock() + Config.Cinema.safe.waitSeconds }
			end
			return false, why
		end
	end
	local wantsCam = #scene.shots > 0 or scene.follow ~= nil
	if cur then
		-- one beat cuts straight to the next (a held hero let go for a free scene)
		finish(false, wantsCam and (cur.free == true) == (scene.free == true))
	end
	waiting = nil
	lastShot, lastCf, easeFrom = nil, nil, nil
	scene.startedAt = os.clock()
	CinemaClient.current = scene
	setCamera(wantsCam, scene.free)
	CinemaClient.Changed:Fire(scene)
	return true, nil
end

-- Stop the scene an owner is playing (nil: any)
function CinemaClient.stop(owner: string?)
	local s = CinemaClient.current
	if s and (owner == nil or s.owner == owner) then
		finish(false)
	end
	if waiting and (owner == nil or waiting.scene.owner == owner) then
		waiting = nil
	end
end

-- SKIP: a server beat asks the server; a device-started scene ends here (and counts as seen)
function CinemaClient.skip()
	local s = CinemaClient.current
	if not s or not CinemaClient.skippable() then
		return
	end
	if s.skip then
		s.skip()
	else
		finish(true)
	end
end

-- The hero took a hit: a device-started scene ends at once (never defenceless)
function CinemaClient.hurt()
	CinemaClient.lastHit = os.clock()
	local s = CinemaClient.current
	if s and not s.beat then
		finish(false)
	end
end

-- A device-started scene from Config.Cinema.scenes, its shots placed round the hero
function CinemaClient.playScene(id: string): (boolean, string?)
	local def = Config.Cinema.scenes[id]
	local r = root()
	if not def or not def.client or not r then
		return false, "none"
	end
	local p = r.Position
	return CinemaClient.play({
		owner = "client",
		key = id,
		id = id,
		bit = def.bit,
		shots = if def.shots then CinemaPlan.around(def.shots, p.X, p.Y, p.Z) else {},
		seconds = CinemaPlan.length(def),
		lines = def.lines,
		comic = def.comic,
	})
end

-- (first-30 polish round 2) a filmic depth of field while a scene's shots play: the subject sharp, the far city
-- softly blurred (Config.Cinema.camera.dof); never on the low preset; eased in and out
local dof: DepthOfFieldEffect? = nil
local dofK = 0
local dofWant = false
local function focusOn(distance: number, dt: number)
	local D = Config.Cinema.camera.dof
	dofWant = D.on and QualityController.name ~= "low"
	if not dofWant then
		return
	end
	if not dof then
		local e = Instance.new("DepthOfFieldEffect")
		e.Name = "CinemaFocus"
		e.NearIntensity = 0
		e.FarIntensity = 0
		e.Enabled = false
		e.Parent = Lighting
		dof = e
	end
	local e = dof :: DepthOfFieldEffect
	e.FocusDistance = math.clamp(distance, 4, 200)
	e.InFocusRadius = math.clamp(distance * D.radius, 8, 60)
	dofK = math.min(1, dofK + dt / D.ease)
	e.FarIntensity = D.far * dofK
	e.Enabled = true
end

local function focusOff(dt: number)
	local e = dof
	if not e or not e.Enabled then
		return
	end
	dofK = math.max(0, dofK - dt / Config.Cinema.camera.dof.ease)
	e.FarIntensity = Config.Cinema.camera.dof.far * dofK
	if dofK <= 0 then
		e.Enabled = false
	end
end

local function step(dt: number)
	if not (CinemaClient.current and camOn and #(CinemaClient.current :: Scene).shots > 0) then
		focusOff(dt)
	end
	local w = waiting
	if w and os.clock() > w.untilT then
		waiting = nil
	end
	local s = CinemaClient.current
	if not s then
		lens(nil)
		return
	end
	local t = CinemaClient.time()
	if s.owner == "client" and t >= s.seconds then
		finish(true)
		return
	end
	if not camOn then
		lens(nil)
		return
	end
	local cam = Workspace.CurrentCamera
	if s.follow and cam then
		local at, look = s.follow(dt)
		at = CamClear.ease(pull, look, at, dt)
		cam.CFrame = CFrame.lookAt(at, look)
		lens(at)
		return
	end
	local shot, k = CinemaPlan.at(s.shots, t)
	if shot and cam then
		CinemaPlan.sample(shot, k, buf)
		local at = Vector3.new(buf[1], buf[2], buf[3])
		local look = Vector3.new(buf[4], buf[5], buf[6])
		-- (first-30 polish round 2) no shot is dead still: a slow push toward the subject over the shot and a
		-- faint breathing sway, like a real camera operator (Config.Cinema.camera.drift)
		local D = Config.Cinema.camera.drift
		local toLook = look - at
		if toLook.Magnitude > 1 then
			at += toLook * (D.push * k)
			local tt = os.clock() * D.rate * math.pi * 2
			local right = toLook.Unit:Cross(Vector3.yAxis)
			if right.Magnitude > 1e-3 then
				at += right.Unit * (math.sin(tt) * D.sway) + Vector3.yAxis * (math.sin(tt * 0.7 + 1.3) * D.sway * 0.6)
			end
		end
		-- (nate's playtest 2026-11-21) never through a wall: a camera a building stands in front of is pulled
		-- in front of it (cars, people and small props never count; CamClear)
		if shot ~= lastShot then
			pull.dist = nil
		end
		at = CamClear.ease(pull, look, at, dt)
		toLook = look - at
		if toLook.Magnitude > 1e-3 and math.abs(toLook.Unit.Y) > 0.985 then
			-- straight up or down: lookAt would spin; lean the look a hair off the vertical
			look += Vector3.new(0.05 * toLook.Magnitude, 0, 0)
		end
		local cf = CFrame.lookAt(at, look)
		-- a jump cut (the next shot starts close to where the last one ended, looking nearly the same way) reads
		-- as a glitch: ease across it instead of cutting
		if shot ~= lastShot then
			local prev = lastCf
			lastShot = shot
			if
				prev
				and (prev.Position - cf.Position).Magnitude < D.jumpCut.dist
				and prev.LookVector:Dot(cf.LookVector) > math.cos(math.rad(D.jumpCut.angle))
			then
				easeFrom, easeAt = prev, os.clock()
			else
				easeFrom = nil
			end
		end
		if easeFrom then
			local e = (os.clock() - easeAt) / D.jumpCut.ease
			if e >= 1 then
				easeFrom = nil
			else
				cf = (easeFrom :: CFrame):Lerp(cf, CinemaPlan.ease(e))
			end
		end
		lastCf = cf
		cam.CFrame = cf
		lens(cf.Position)
		focusOn((look - at).Magnitude, dt)
	end
end

function CinemaClient.init()
	RunService:BindToRenderStep(
		"CapelineCinema",
		Enum.RenderPriority.Camera.Value, -- before CameraController's step, so its shakes land on the shot
		FrameProf.wrap("CinemaClient", step)
	)
	-- a waiting device-started scene tries again once a second
	task.spawn(function()
		while true do
			task.wait(1)
			local w = waiting
			if w and not CinemaClient.current then
				CinemaClient.play(w.scene)
			end
		end
	end)
	player.CharacterAdded:Connect(function()
		anchored = nil
	end)
end

return CinemaClient
