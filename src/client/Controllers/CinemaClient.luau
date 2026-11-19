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
	if on then
		cam.CameraType = Enum.CameraType.Scriptable
		local r = root()
		if r and not free then
			r.Anchored = true -- the hero holds still for the scene (on this device only)
			anchored = r
		end
	else
		cam.CameraType = Enum.CameraType.Custom
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			cam.CameraSubject = hum
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

local function step(dt: number)
	local w = waiting
	if w and os.clock() > w.untilT then
		waiting = nil
	end
	local s = CinemaClient.current
	if not s then
		return
	end
	local t = CinemaClient.time()
	if s.owner == "client" and t >= s.seconds then
		finish(true)
		return
	end
	if not camOn then
		return
	end
	local cam = Workspace.CurrentCamera
	if s.follow and cam then
		local at, look = s.follow(dt)
		cam.CFrame = CFrame.lookAt(at, look)
		return
	end
	local shot, k = CinemaPlan.at(s.shots, t)
	if shot and cam then
		CinemaPlan.sample(shot, k, buf)
		cam.CFrame = CFrame.lookAt(Vector3.new(buf[1], buf[2], buf[3]), Vector3.new(buf[4], buf[5], buf[6]))
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
