-- PrologueQte: the Ceremony prologue as a directed cinematic with quick-time prompts, on this device (fix-flow,
-- nate's playtest 2026-11-19: "It should be a cutscene with QTE's. whole thing should be like that until you have to
-- fight them"; prologue-cine, nate 2026-11-20: "dont have the player run to the gold marker. whole prologue needs to
-- be cutscene with qtes until subway"). The server's beats, lines, route and timers are its own (OpeningService,
-- Shared.OpeningPlan); this plays every beat from the run off the plaza to the subway fight the way
-- Shared.PrologueCine authors it:
-- * the hero's controls rest from the ceremony to the fight (InputController.freeze): no free movement, no casts.
-- * the hero moves only on authored paths: runs along the street and the tunnel, vaults, rolls, the hops, the slow-mo
--   leap, the ledge climb and the drop (MoveController.travel, upright, through everything like a fast-travel
--   flight; the server grants the travel and counts the beats by where the body really is), each with its HeroAnim
--   clip (HeroAnimator.cineMode) and a one-shot as it starts and lands.
-- * the camera is directed: each segment's shot (track, front, side, low, wide, top, over, orbit) through the one
--   cutscene player (CinemaClient, a live `follow` camera with the letterbox), cut or eased.
-- * the only input is the prompt (Shared.QtePlan, Ui.QteHud): a press (JUMP, DODGE, GRAB, SHIELD, SMASH), a mash
--   (BREAK FREE) or a hold (SUIT UP), on the key, the pad button or the prompt itself (a tap or a held finger). A
--   prompt shows Config's `lead` s before the move in front of it ends; while it waits the hero holds a pose in
--   slow motion. A miss is a near miss (PrologueFx.moment: the spear lands a stride wide, the sign slips, the beam
--   presses down) and the prompt comes back; the 3rd miss does it by itself. (first-30, nate 2026-11-20: with
--   Config's qte.wait on, the default, a prompt waits for its press: no window, a wrong key is ignored, it pulses
--   to nag, and the server's clocks hold while it waits.) The ceremony, the scan and the
--   Ceremony's choice keep PrologueFx's own camera shots.
-- * at the subway fight the hold ends: FIGHT!, the controls, the normal camera and the HUD come back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local Net = require(Shared:WaitForChild("Net"))
local OpeningPlan = require(Shared:WaitForChild("OpeningPlan"))
local QtePlan = require(Shared:WaitForChild("QtePlan"))
local PrologueCine = require(Shared:WaitForChild("PrologueCine"))

local State = require(script.Parent.Parent.State)
local StoryClient = require(script.Parent.Parent.Controllers.StoryClient)
local MoveController = require(script.Parent.Parent.Controllers.MoveController)
local InputController = require(script.Parent.Parent.Controllers.InputController)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local CinemaClient = require(script.Parent.Parent.Controllers.CinemaClient)
local HeroAnimator = require(script.Parent.Parent.Controllers.HeroAnimator)
local AudioController = require(script.Parent.Parent.Controllers.AudioController)
local CombatFx = require(script.Parent.CombatFx)
local PrologueFx = require(script.Parent.PrologueFx)
local QteHud = require(script.Parent.Parent.Ui.QteHud)

local PrologueQte = {}

local Q = Config.Story.opening.qte
local player = Players.LocalPlayer
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
local GROUP = "TravelFlight" -- BeaconService.GROUP: the body passes through everything on a directed move

type Run = {
	key: string, -- the beat (and the chase's hop) these segments are for
	step: string,
	segs: { PrologueCine.Seg },
	idx: number,
	misses: number,
	shownAt: number?, -- the prompt on screen since (os.clock)
	waitUntil: number,
	go: boolean, -- the prompt is answered: its move starts when the one before it ends
	presses: number, -- a mash's presses so far
	heldAt: number?, -- a hold's key went down at
	cued: boolean,
}
type Move = { seg: PrologueCine.Seg, start: number, time: number, travel: boolean }

local run: Run? = nil
local move: Move? = nil
local froze = false
local camAt: Vector3? = nil
local lookAt: Vector3? = nil
local camSeg: PrologueCine.Seg? = nil
local slowTint: ColorCorrectionEffect? = nil
local groups: { [BasePart]: string } = {}
local keysDown: { [string]: boolean } = {}
local lastStep: string? = nil

local function root(): BasePart?
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function hum(): Humanoid?
	local c = player.Character
	return c and c:FindFirstChildOfClass("Humanoid")
end

-- the root's height over the feet for this body (bodies differ: the creator's height and build)
local function rootUp(): number
	local r, h = root(), hum()
	if not r or not h then
		return 3
	end
	return h.HipHeight + r.Size.Y / 2
end

local function feet(): { number }?
	local r = root()
	if not r then
		return nil
	end
	local p = r.Position
	return { p.X, p.Y - rootUp(), p.Z }
end

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

-- the body passes through everything on a directed move (the old groups come back after)
local function setGroups(on: boolean)
	if on then
		local char = player.Character
		for _, d in if char then char:GetDescendants() else {} do
			if d:IsA("BasePart") and groups[d] == nil then
				groups[d] = d.CollisionGroup
				pcall(function()
					d.CollisionGroup = GROUP
				end)
			end
		end
	else
		for p, g in groups do
			if p.Parent then
				p.CollisionGroup = g
			end
		end
		table.clear(groups)
	end
end

-- slow motion while a prompt waits (the hero's clips slow down, the colours dim a little)
local function setSlow(on: boolean)
	if on and not slowTint then
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "PrologueQteSlow"
		cc.Saturation = -0.25
		cc.Contrast = if CombatFx.reduceFlashing then 0 else 0.06
		cc.Parent = Lighting
		slowTint = cc
		HeroAnimator.timeScale = Q.slowMo
	elseif not on and slowTint then
		slowTint:Destroy()
		slowTint = nil
		HeroAnimator.timeScale = 1
	end
end

-- The segment the camera frames now: the move in flight, else the prompt waiting, else the last one
local function shotSeg(): PrologueCine.Seg?
	local m = move
	if m then
		return m.seg
	end
	local c = run
	-- (between moves: the next segment's shot, its prompt's moment)
	if c and #c.segs > 0 then
		return c.segs[math.min(c.idx, #c.segs)]
	end
	return camSeg
end

-- The directed camera (CinemaClient's follow): the segment's shot, cut in hard or eased over
local function follow(dt: number): (Vector3, Vector3)
	local f = feet()
	local seg = shotSeg()
	if not f or not seg then
		return camAt or Vector3.zero, lookAt or Vector3.new(0, 0, -1)
	end
	local m = move
	local u = if m then math.clamp((os.clock() - m.start) / m.time, 0, 1) else 0
	local c, l = PrologueCine.camera(Config, seg.shot, f, seg, u)
	local lane = StoryClient.opening.lane
	if StoryClient.openingStep() == "tunnel" and type(lane) == "table" then
		-- inside the tunnel's walls and under its roof
		local half = Config.Story.opening.subway.width / 2 - 2
		c[1] = math.clamp(c[1], lane.x - half, lane.x + half)
		c[2] = math.min(c[2], lane.floorY + Config.Story.opening.subway.height - 2)
	end
	local wantCam, wantLook = v3(c), v3(l)
	-- never behind a wall: a building between the hero and the shot pulls the camera in front of it
	local gap = wantCam - wantLook
	if gap.Magnitude > 1 then
		local char = player.Character
		rayParams.FilterDescendantsInstances = if char then { char } else {}
		local hit = Workspace:Raycast(wantLook, gap, rayParams)
		if hit then
			wantCam = hit.Position - gap.Unit * 1.5
		end
	end
	if seg ~= camSeg then
		if seg.cut or not camAt then
			camAt, lookAt = wantCam, wantLook
		end
		camSeg = seg
	end
	local k = 1 - math.exp(-Q.camEase * math.max(dt, 1 / 240))
	camAt = (camAt :: Vector3):Lerp(wantCam, k)
	lookAt = (lookAt :: Vector3):Lerp(wantLook, k)
	return camAt :: Vector3, lookAt :: Vector3
end

local function cameraOn(on: boolean)
	local cur = CinemaClient.current
	local mine = cur ~= nil and cur.owner == "qte"
	if on and not mine then
		if cur and cur.owner == "prologue" then
			return -- PrologueFx's own camera beat (the Ceremony's choice) has the camera
		end
		camAt, lookAt, camSeg = nil, nil, nil
		CinemaClient.play({
			owner = "qte",
			key = "directed",
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
end

local function freeze(on: boolean)
	if on ~= froze then
		froze = on
		InputController.freeze(on)
	end
end

-- Start a segment's move from where the body is now. Not yet (false) while the body is far from the move's start:
-- a beat that begins in a new place (the first roof, the subway) waits for the server's placing to arrive, so no
-- move ever flies the hero across the map (the beat's stuck timer still holds)
local function startMove(seg: PrologueCine.Seg): boolean
	local f = feet()
	if not f then
		return false
	end
	if seg.move ~= "stand" then
		local d = Vector3.new(f[1] - seg.from[1], f[2] - seg.from[2], f[3] - seg.from[3]).Magnitude
		if d > Q.startReach then
			return false
		end
	end
	local up = rootUp()
	local now = os.clock()
	local here = f :: { number }
	HeroAnimator.cineMode = seg.clip
	if seg.start then
		HeroAnimator.play(player, seg.start)
	end
	if seg.slow then
		PrologueFx.slowLeap(seg.time)
	end
	if seg.move == "stand" then
		move = { seg = seg, start = now, time = seg.time, travel = false }
		return true
	end
	local at: (number) -> Vector3
	if seg.move == "run" and seg.path then
		local path = table.clone(seg.path)
		path[1] = here -- from where the body is (a roll or a cut left it a little off the path)
		at = function(u: number): Vector3
			local p = PrologueCine.runAt(path, u)
			return Vector3.new(p[1], p[2] + up, p[3])
		end
	else
		local to, height = seg.to, seg.height or 0
		at = function(u: number): Vector3
			local p = PrologueCine.arcAt(here, to, height, u)
			return Vector3.new(p[1], p[2] + up, p[3])
		end
	end
	setGroups(true)
	MoveController.travel(at, seg.time, true)
	move = { seg = seg, start = now, time = seg.time, travel = true }
	return true
end

local function endMove()
	local m = move
	if not m then
		return
	end
	move = nil
	if m.travel then
		MoveController.endTravel(if m.seg.move == "arc" then 14 else 2)
		setGroups(false)
	end
	HeroAnimator.cineMode = nil
	if m.seg.land then
		HeroAnimator.play(player, m.seg.land)
	end
	if m.seg.land == "landHard" then
		CameraController.shake(0.25, 0.5)
		local r = root()
		if r then
			CombatFx.burst(r.Position - Vector3.new(0, 2.5, 0), State.hero.fxStyle)
		end
	end
end

-- A prompt's answer
local function resolve(result: string)
	local c = run
	if not c or not c.shownAt then
		return
	end
	local seg = c.segs[c.idx]
	local p = seg.prompt :: QtePlan.Prompt
	local after = QtePlan.after(Config, result, c.misses)
	c.shownAt = nil
	c.presses, c.heldAt = 0, nil
	if after.go == "retry" then
		QteHud.result("miss")
		PrologueFx.moment(seg.fx or seg.near, seg, "miss")
		CameraController.shake(0.3, 0.45)
		HeroAnimator.play(player, "flinch", nil, true) -- a near miss: the hero flinches, never hurt
		c.misses = after.misses
		c.waitUntil = os.clock() + after.wait
		return
	end
	QteHud.result(if after.go == "assist" then "assist" else "hit")
	AudioController.play("skillRank", nil)
	PrologueFx.moment(seg.fx, seg, "hit")
	if p.kind == "hold" and seg.fx == "suit" then
		PrologueFx.suitHold(1, true)
	end
	if seg.spark then
		StoryClient.spark() -- the Spark fires (the server judges it: OpeningAct 1)
	end
	c.go = true
end

local function show(c: Run, seg: PrologueCine.Seg, now: number)
	local p = seg.prompt :: QtePlan.Prompt
	c.shownAt = now
	c.presses, c.heldAt = 0, nil
	if keysDown[p.action] and p.kind == "hold" then
		c.heldAt = now -- already held as it showed
	end
	QteHud.show(p.word, p.action, QtePlan.window(Config, c.misses, p.kind), p.kind)
	PrologueFx.moment(seg.fx, seg, "show")
end

local function newRun(step: string, key: string): Run
	local o = StoryClient.opening
	return {
		key = key,
		step = step,
		segs = PrologueCine.beat(Config, o, step, o.hop),
		idx = 1,
		misses = 0,
		shownAt = nil,
		waitUntil = os.clock() + Q.lead,
		go = false,
		presses = 0,
		heldAt = nil,
		cued = false,
	}
end

local function handoff()
	-- the subway fight: FIGHT!, and the hero is the player's again
	CombatFx.banner(Q.fightWord, CombatFx.colorOf(State.hero.setId, player.UserId), State.hero.fxStyle)
	CameraController.punch(0.1)
	AudioController.play("super", nil)
end

local function frameInner(_dt: number)
	local step = StoryClient.openingStep()
	local o = StoryClient.opening
	if step ~= lastStep then
		if step == "fight" and lastStep ~= nil and OpeningPlan.CODE[lastStep] < OpeningPlan.CODE.fight then
			handoff()
		end
		lastStep = step
	end
	freeze(PrologueCine.frozen(step))
	QteHud.frame()
	local now = os.clock()
	-- the move in flight runs to its end, even across a beat change (the server counts the arrival)
	local m = move
	if m and now - m.start >= m.time then
		endMove()
		m = nil
	end
	if m and m.travel and not MoveController.traveling() then
		move = nil -- the flight was cut (a respawn, the server put the body somewhere)
		HeroAnimator.cineMode = nil
		setGroups(false)
		m = nil
	end
	local directed = PrologueCine.directed(Config, step) and not o.hold
	cameraOn(directed and not o.choosing)
	if not directed then
		if run then
			run = nil
			QteHud.hide()
		end
		if not m then
			setSlow(false)
			HeroAnimator.cineMode = nil
		end
		return
	end
	local key = (step :: string) .. ":" .. tostring(if step == "chase" then o.hop or 0 else 0)
	local cur = run
	if not cur or cur.key ~= key then
		if m then
			return -- the next beat (or hop) starts once this move has landed
		end
		if cur and cur.shownAt then
			QteHud.hide()
		end
		cur = newRun(step :: string, key)
		run = cur
	end
	local c = cur :: Run
	-- (idx is the next segment: the one whose prompt shows while the move before it is still in flight)
	if c.idx > #c.segs then
		setSlow(false)
		if not m and not c.cued and c.segs[#c.segs] and c.segs[#c.segs].cue then
			c.cued = true
			Net.send("OpeningAct", 7) -- the suit has snapped on (the server moves on to the drop)
		end
		return
	end
	local seg = c.segs[c.idx]
	local p = seg.prompt
	if seg.spark and o.fired and not c.go then
		-- the server fired the Spark by itself (its own backstop): the prompt is answered
		if c.shownAt then
			QteHud.hide()
			c.shownAt = nil
		end
		c.go = true
	end
	if not p or c.go then
		setSlow(false)
		if not m and startMove(seg) then
			c.idx += 1
			c.misses, c.presses, c.go, c.heldAt = 0, 0, false, nil
			c.waitUntil = now
		end
		return
	end
	if not c.shownAt then
		-- the prompt shows `lead` s before the move in front of it ends (a quick player never stops)
		local ready = if m then m.time - (now - m.start) <= Q.lead else now >= c.waitUntil
		if ready and o.choosing ~= true then
			show(c, seg, now)
		end
		if not m then
			HeroAnimator.cineMode = seg.wait
		end
		return
	end
	-- the prompt is up
	if not m then
		HeroAnimator.cineMode = seg.wait
		setSlow(true)
	end
	if p.kind == "hold" then
		local held = if c.heldAt then now - (c.heldAt :: number) else 0
		local f, done = QtePlan.holdStep(Config, p, held)
		QteHud.progress(f)
		if seg.fx == "suit" then
			PrologueFx.suitHold(f, false)
		end
		if done then
			resolve("hit")
			return
		end
	end
	if QtePlan.expired(Config, now - (c.shownAt :: number), c.misses, p.kind) then
		resolve("miss")
	end
end

-- first-30: the server holds the prologue's clocks while a prompt waits for its press (OpeningAct 8 up, 9 down;
-- Config.Story.opening.qte.wait), so an untimed prompt is never moved on by a stuck timer
local waitingSent = false
local function frame(dt: number)
	frameInner(dt)
	local up = Q.wait == true and run ~= nil and run.shownAt ~= nil
	if up ~= waitingSent then
		waitingSent = up
		Net.send("OpeningAct", if up then 8 else 9)
	end
end

-- One press (or tap) of `act` while a prompt is up
local function pressed(act: string)
	local c = run
	if not c or not c.shownAt then
		return
	end
	local p = c.segs[c.idx].prompt
	if not p then
		return
	end
	local t = os.clock() - (c.shownAt :: number)
	local res = QtePlan.judge(Config, p.action, act, t, c.misses, p.kind)
	if not res then
		return
	end
	if res == "miss" then
		if p.kind ~= "press" and act ~= p.action then
			return -- a stray key never spoils a mash or a hold
		end
		resolve("miss")
		return
	end
	if p.kind == "mash" then
		local n, done = QtePlan.mashStep(Config, p, c.presses)
		c.presses = n
		QteHud.progress(n / (p.count or Q.mash.count))
		if done then
			resolve("hit")
		end
	elseif p.kind == "hold" then
		c.heldAt = c.heldAt or os.clock()
	else
		resolve("hit")
	end
end

local function released(act: string)
	local c = run
	local p = c and c.shownAt and c.segs[c.idx].prompt
	if c and p and p.kind == "hold" and act == p.action then
		c.heldAt = nil -- let go early: it empties again (never a miss by itself)
	end
end

-- The prompt's key: the bound action, the pad's second action (X is GRAB), or a click as SMASH
local function actOf(input: InputObject, want: string?): string?
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		return if want == "Basic" then "Basic" else nil
	end
	local a = InputController.actionOf(input.KeyCode)
	local b = InputController.alsoOf(input.KeyCode)
	if b and b == want then
		return b
	end
	return a
end

local function wanted(): string?
	local c = run
	local p = c and c.shownAt and c.segs[c.idx].prompt
	return p and p.action
end

local function onInput(input: InputObject, processed: boolean)
	local t = input.UserInputType
	if processed and (t == Enum.UserInputType.Keyboard or t == Enum.UserInputType.MouseButton1) then
		return -- typing in a box, or a click on a button (the prompt's own click is QteHud.Pressed)
	end
	local act = actOf(input, wanted())
	if act then
		keysDown[act] = true
		pressed(act)
	end
end

local function onEnded(input: InputObject)
	local act = actOf(input, wanted())
	if act then
		keysDown[act] = nil
		released(act)
	end
end

-- Dev and tests: the prompt run now (nil when none)
function PrologueQte.state(): { [string]: any }?
	return run
end

function PrologueQte.init()
	UserInputService.InputBegan:Connect(onInput)
	UserInputService.InputEnded:Connect(onEnded)
	-- the prompt itself, tapped or clicked (a press, or one mash press), or held (the hold)
	QteHud.Pressed:Connect(function()
		local a = wanted()
		local c = run
		local p = c and c.segs[c.idx].prompt
		if a and p and p.kind ~= "hold" then
			pressed(a)
		end
	end)
	QteHud.Held:Connect(function(down: boolean)
		local a = wanted()
		if not a then
			return
		end
		if down then
			local c = run
			local p = c and c.segs[c.idx].prompt
			if p and p.kind == "hold" then
				pressed(a)
			end
		else
			released(a)
		end
	end)
	player.CharacterAdded:Connect(function()
		move = nil
		table.clear(groups)
		HeroAnimator.cineMode = nil
	end)
	RunService.RenderStepped:Connect(FrameProf.wrap("PrologueQte", frame))
end

return PrologueQte
