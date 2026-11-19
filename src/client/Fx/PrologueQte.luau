-- PrologueQte: the prologue's rooftop chase as a cinematic with quick-time prompts, on this device (fix-flow, nate's
-- playtest 2026-11-19: "I can literally just kill skylance while im doing rooftop stuff. It should be a cutscene
-- with QTE's. whole thing should be like that until you have to fight them"). The server's beats, lines, route and
-- timers are unchanged (OpeningService, Shared.OpeningPlan); this only changes how the rooftop beats play:
-- * leap, chase, suit and descend (Config.Story.opening.qte.camera): the chase camera through the one cutscene
--   player (CinemaClient, a live `follow` camera with the letterbox; the hero is not held still) and the hero's own
--   controls rest (InputController.freeze), so nobody wanders off a roof or swings at Skylance.
-- * every hop is a prompt (Shared.QtePlan, Ui.QteHud): JUMP sends the hero on the guided arc to the next roof
--   (MoveController.arcTo, the same arc the server granted; the leap's slow motion still plays off Leaped); a DODGE
--   on the dodge roofs side-steps Skylance's spear. A miss is a near miss (the spear lands at the hero's feet, the
--   camera shakes, no damage) and the prompt comes back; after Config's `assist` misses the move happens by itself.
-- * Skylance is untouchable on the server until the subway fight (EnemyService.tune untouchable): the fight that
--   follows is a normal fight.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local OpeningPlan = require(Shared:WaitForChild("OpeningPlan"))
local QtePlan = require(Shared:WaitForChild("QtePlan"))

local StoryClient = require(script.Parent.Parent.Controllers.StoryClient)
local MoveController = require(script.Parent.Parent.Controllers.MoveController)
local InputController = require(script.Parent.Parent.Controllers.InputController)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local CinemaClient = require(script.Parent.Parent.Controllers.CinemaClient)
local EnemyRenderer = require(script.Parent.Parent.Controllers.EnemyRenderer)
local AudioController = require(script.Parent.Parent.Controllers.AudioController)
local CombatFx = require(script.Parent.CombatFx)
local QteHud = require(script.Parent.Parent.Ui.QteHud)

local PrologueQte = {}

local Q = Config.Story.opening.qte
local player = Players.LocalPlayer
local SPEAR = Color3.fromRGB(110, 210, 255)

type Run = {
	key: string, -- the beat and hop these prompts are for
	seq: { QtePlan.Prompt },
	idx: number,
	misses: number,
	shownAt: number?, -- the prompt on screen since (os.clock)
	waitUntil: number,
	doneAt: number?, -- every prompt of this hop answered (the hop is in the air or landed)
}
local run: Run? = nil
local froze = false
local camAt: Vector3? = nil
local lookAt: Vector3? = nil

local function root(): BasePart?
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

-- The chase camera: to the side of the hop, eased so the arcs read as one shot
local function follow(dt: number): (Vector3, Vector3)
	local r = root()
	local p = if r then r.Position else (camAt or Vector3.zero)
	local o = StoryClient.opening
	local to = if type(o.target) == "table" then o.target else { p.X, p.Y, p.Z - 30 }
	local c, l = QtePlan.camera3(Config, { p.X, p.Y, p.Z }, to)
	local wantCam, wantLook = v3(c), v3(l)
	local k = 1 - math.exp(-Q.camEase * math.max(dt, 1 / 240))
	camAt = if camAt then (camAt :: Vector3):Lerp(wantCam, k) else wantCam
	lookAt = if lookAt then (lookAt :: Vector3):Lerp(wantLook, k) else wantLook
	return camAt :: Vector3, lookAt :: Vector3
end

local function cameraOn(on: boolean)
	local cur = CinemaClient.current
	local mine = cur ~= nil and cur.owner == "qte"
	if on and not mine then
		camAt, lookAt = nil, nil
		CinemaClient.play({
			owner = "qte",
			key = "chase",
			shots = {},
			seconds = 1e6,
			beat = true,
			free = true,
			follow = follow,
			canSkip = function()
				return false
			end,
		})
	elseif not on and mine then
		CinemaClient.stop("qte")
	end
	if on ~= froze then
		froze = on
		InputController.freeze(on)
	end
end

-- Skylance's spear from where he is to `at` (a client effect: it never hurts)
local function spear(at: Vector3)
	local o = StoryClient.opening
	local from = o.fake and EnemyRenderer.position(o.fake)
	if from then
		CombatFx.bolt(from + Vector3.new(0, 3, 0), at, "Comic", SPEAR, "Blade")
	end
	CombatFx.burst(at, "Comic")
	AudioController.play("clash", at)
end

-- The prompt's move: JUMP is the guided arc to the beat's target; DODGE a quick side-step as the spear lands
local function perform(p: QtePlan.Prompt)
	local r = root()
	local to = StoryClient.opening.target
	if not r or type(to) ~= "table" then
		return
	end
	local pos = r.Position
	if p.action == "Leap" then
		local time, height = OpeningPlan.hopArc(Config, { pos.X, pos.Y, pos.Z }, to)
		MoveController.arcTo(Vector3.new(to[1], to[2] + 3, to[3]), time, height)
		MoveController.Leaped:Fire(pos) -- the leap beat's slow motion (PrologueFx.slowLeap) plays off it
	else
		local flat = Vector3.new(to[1] - pos.X, 0, to[3] - pos.Z)
		local dir = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, -1)
		local side = Vector3.new(-dir.Z, 0, dir.X)
		MoveController.arcTo(pos + side * Q.side, 0.3, 2)
		task.delay(0.15, spear, pos - Vector3.new(0, 2.5, 0))
	end
end

-- A miss: a near miss that scares and never hurts
local function missFx(p: QtePlan.Prompt)
	local r = root()
	if not r then
		return
	end
	if p.action == "Block" then
		spear(r.Position + Vector3.new(1.8, -2.5, 0))
	end
	CameraController.shake(0.3, 0.45)
end

local function resolve(result: string)
	local cur = run
	if not cur or not cur.shownAt then
		return
	end
	local p = cur.seq[cur.idx]
	local after = QtePlan.after(Config, result, cur.misses)
	cur.shownAt = nil
	if after.go == "retry" then
		QteHud.result("miss")
		missFx(p)
		cur.misses = after.misses
		cur.waitUntil = os.clock() + after.wait
		return
	end
	QteHud.result(if after.go == "assist" then "assist" else "hit")
	perform(p)
	cur.idx += 1
	cur.misses = 0
	cur.waitUntil = os.clock() + Q.lead
	if cur.idx > #cur.seq then
		cur.doneAt = os.clock()
	end
end

local function frame(_dt: number)
	local step = StoryClient.openingStep()
	cameraOn(QtePlan.camera(Config, step))
	QteHud.frame()
	if not QtePlan.on(Config, step) then
		if run then
			run = nil
			QteHud.hide()
		end
		return
	end
	local o = StoryClient.opening
	local r = root()
	local to = o.target
	if not r or type(to) ~= "table" then
		return
	end
	local now = os.clock()
	local key = (step :: string) .. ":" .. tostring(o.hop or 0)
	local cur = run
	if not cur or cur.key ~= key then
		cur = {
			key = key,
			seq = QtePlan.prompts(Config, step :: string, o.hop),
			idx = 1,
			misses = 0,
			shownAt = nil,
			waitUntil = now + Q.lead,
			doneAt = nil,
		}
		run = cur
	end
	local c = cur :: Run
	if MoveController.arcing() then
		return -- mid-hop: the next prompt waits for the landing
	end
	if c.idx > #c.seq then
		-- landed short of the roof the server counts (a hop cut off): JUMP again
		local p = r.Position
		local d = Vector3.new(to[1] - p.X, 0, to[3] - p.Z).Magnitude
		if c.doneAt and now - c.doneAt > 2.5 and d > 30 then
			c.idx = #c.seq
			c.doneAt = nil
			c.waitUntil = now + Q.lead
		end
		return
	end
	if not c.shownAt then
		if now >= c.waitUntil then
			local p = c.seq[c.idx]
			c.shownAt = now
			local win = QtePlan.window(Config, c.misses)
			QteHud.show(p.word, p.action, win)
			if p.action == "Block" then
				CombatFx.warn(r.Position - Vector3.new(0, 2.5, 0), 4, win) -- the spear's mark under the hero
			end
		end
		return
	end
	if QtePlan.expired(Config, now - (c.shownAt :: number), c.misses) then
		resolve("miss")
	end
end

-- A key or pad button while a prompt is up
local function onInput(input: InputObject, processed: boolean)
	local cur = run
	if not cur or not cur.shownAt or (processed and input.UserInputType == Enum.UserInputType.Keyboard) then
		return
	end
	local act = InputController.actionOf(input.KeyCode)
	if not act then
		return
	end
	local p = cur.seq[cur.idx]
	local res = QtePlan.judge(Config, p.action, act, os.clock() - (cur.shownAt :: number), cur.misses)
	if res then
		resolve(res)
	end
end

-- Dev and tests: the prompt run now (nil when none)
function PrologueQte.state(): { [string]: any }?
	return run
end

function PrologueQte.init()
	UserInputService.InputBegan:Connect(onInput)
	QteHud.Pressed:Connect(function()
		resolve("hit") -- the prompt itself, tapped or clicked
	end)
	RunService.RenderStepped:Connect(FrameProf.wrap("PrologueQte", frame))
end

return PrologueQte
