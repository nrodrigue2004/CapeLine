--!strict
-- HeroAnimator: plays Shared.HeroAnim's clips on every hero near you (overhaul plan step 2; the animation pass
-- 2026-11-19, nate: "Animation for EVERYTHING. Every attack, power, mobility, every button."). Layers on top of
-- the Animator (Roblox's default Animate keeps the ground walk, run, idle and jump):
-- * mode: the movement pose (fly, boost, dive, hover, glide, leap crouch, dash, arc, swing, wall run,
--   ride by path, water run, swim, sprint, Downed and Give Up), crossfaded on a change. Your own mode comes from
--   MoveController (plus the arc and swim display modes); other heroes' from their "Move" attribute (you send
--   yours with MoveMode, the server sets it) and their speed.
-- * transitions: a mode change plays its one-shot (take-off, landings by fall speed, the leap spring, wall
--   kicks and grabs, swing catch and release, glide open, flight stop) and a mid-air jump flips; every device
--   sees them, since they come from the mode and the hero's velocity.
-- * stance: while the weapon is held (the Held attribute) and the hero stands, runs or jumps, the arms take
--   the weapon's ready stance (HeroAnim.holdClip, by the WeaponId on the look's Weapon folder), faded in and
--   out, over the Animator's arm swing; an action plays over it.
-- * state: held poses from attributes every device has (Blocking: the guard; Carrying: the lift over the
--   head; Charging: the charge-up crouch; Reviving: the kneel over an ally), your own held prompt and emotes.
--   Their edges play one-shots too: lift and heave when a carry starts and ends, the Awakening burst.
-- * action: one-shots (every cast, each weapon's combo and moves, windups, channels, gadgets, interact, catch,
--   block hits and parries, guard breaks, the flinch). Soft ones (transitions, flinches) never cut a cast.
--   A clip moves only the joints it lists, so a cast in the air keeps the flight legs; a hero running on the
--   ground keeps most of the Animator's stride under a cast that moves the legs.
-- Poses are written to Motor6D.Transform in PreSimulation, after the Animator, blended from what the Animator
-- set (or from rest where it set nothing). Transform is local to each device, so every device animates
-- everyone it can see; heroes past HeroAnim.range are left alone, past nearRange they update every other frame.
-- PLACEHOLDER ANIMATION: hand-keyed poses (HeroAnim, HeroMoves) until real animations.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local HeroAnim = require(Shared:WaitForChild("HeroAnim"))
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local MoveController = require(script.Parent.MoveController)
local InputController = require(script.Parent.InputController)

local HeroAnimator = {}

local player = Players.LocalPlayer
local IDENTITY = CFrame.identity
local RAD = math.rad

type Action = {
	clip: string,
	start: number,
	dur: number,
	holdUntil: number?,
	holdT: number?,
	soft: boolean?,
}
type Rig = {
	char: Model,
	root: BasePart,
	hum: Humanoid?,
	motors: { [string]: Motor6D },
	written: { [Motor6D]: CFrame },
	modeFrom: string?,
	modeTo: string?,
	modeAt: number,
	action: Action?,
	frame: number,
	-- the held weapon's ready stance (HeroAnim.holdClip): the clip, how much of it shows, the carried weapon's id
	holdClip: string?,
	holdW: number,
	holdLast: number,
	weaponId: number?,
	weaponAt: number,
	-- the animation pass: the raw mode for transitions, the fall speed for landings, the held state pose
	rawMode: string?,
	fall: number,
	lastVy: number,
	stateClip: string?,
	stateW: number,
	carrying: boolean,
	awake: boolean,
	blocking: boolean,
	basicN: number,
	basicAt: number,
	emoteUntil: number,
	promptUntil: number,
}

local rigs: { [Player]: Rig } = {}

local function motorsOf(char: Model): { [string]: Motor6D }
	local out = {}
	for _, d in char:GetDescendants() do
		if d:IsA("Motor6D") then
			out[d.Name] = d
		end
	end
	return out
end

local function rigOf(p: Player): Rig?
	local char = p.Character
	if not char then
		rigs[p] = nil
		return nil
	end
	local r = rigs[p]
	if r and r.char == char and r.root.Parent then
		return r
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return nil
	end
	local motors = motorsOf(char :: Model)
	if not motors.Waist then
		return nil -- not an R15 rig (yet)
	end
	r = {
		char = char :: Model,
		root = root :: BasePart,
		hum = (char :: Model):FindFirstChildOfClass("Humanoid"),
		motors = motors,
		written = {},
		modeFrom = nil,
		modeTo = nil,
		modeAt = 0,
		action = nil,
		frame = 0,
		holdClip = nil,
		holdW = 0,
		holdLast = 0,
		weaponId = nil,
		weaponAt = -1,
		rawMode = nil,
		fall = 0,
		lastVy = 0,
		stateClip = nil,
		stateW = 0,
		-- what the hero is doing when first seen counts as already started (no lift or burst replayed)
		carrying = p:GetAttribute("Carrying") ~= nil,
		awake = p:GetAttribute("Awakened") == true,
		blocking = p:GetAttribute("Blocking") == true,
		basicN = 0,
		basicAt = 0,
		emoteUntil = 0,
		promptUntil = 0,
	}
	rigs[p] = r
	return r
end

local function toCFrame(a: { number }): CFrame
	local cf = CFrame.Angles(RAD(a[1]), RAD(a[2]), RAD(a[3]))
	if a[4] ~= 0 then
		cf = CFrame.new(0, a[4], 0) * cf
	end
	return cf
end

-- your display mode: MoveController's, with a zip or launch arc and swimming told apart (the MoveMode you send)
local function displayMode(): string
	local mode = MoveController.mode
	if mode == "dash" and MoveController.arcing() then
		return "arc"
	end
	if mode == "ground" then
		local r = rigs[player]
		local hum = r and r.hum
		if hum and hum:GetState() == Enum.HumanoidStateType.Swimming then
			return "swim"
		end
	end
	return mode
end

local function modeOf(p: Player): string?
	if p == player then
		return displayMode()
	end
	local n = p:GetAttribute("Move")
	return if type(n) == "number" then HeroAnim.MODES[n] else nil
end

local function busy(r: Rig, now: number): boolean
	local a = r.action
	return a ~= nil and not a.soft and now - a.start < a.dur
end

-- start an action clip on a hero (dur overrides the clip's length: channels, windups). soft: a transition or a
-- reaction that never cuts a cast in progress (and any cast cuts it)
function HeroAnimator.play(p: Player?, clip: string, dur: number?, soft: boolean?)
	if not p or not HeroAnim.CLIPS[clip] then
		return
	end
	local r = rigOf(p :: Player)
	if not r then
		return
	end
	local now = os.clock()
	if soft and busy(r, now) then
		return
	end
	r.action = { clip = clip, start = now, dur = dur or HeroAnim.CLIPS[clip].dur, soft = soft }
end

-- the action a hero plays now (TetherFx swings the whip, yo-yo and rope dart lines along it): clip, time, length
function HeroAnimator.actionOf(p: Player): (string?, number, number)
	local r = rigs[p]
	local a = r and r.action
	if not a then
		return nil, 0, 0
	end
	return a.clip, os.clock() - a.start, a.dur
end

-- the carried weapon's id on a hero's look (LookKit puts it on the look's Weapon folder; re-read twice a second)
local function weaponOf(r: Rig, now: number): number?
	if now - r.weaponAt > 0.5 then
		r.weaponAt = now
		local look = r.char:FindFirstChild("HeroLook")
		local wf = look and look:FindFirstChild("Weapon")
		local id = wf and wf:GetAttribute("WeaponId")
		r.weaponId = if type(id) == "number" then id else nil
	end
	return r.weaponId
end

local function familyOfId(id: number?): string?
	local w = id and Config.Weapons.list[id]
	return if w then w[2] else nil
end

-- the weapon stance to show now (nil: none): the weapon held, standing, running or jumping
local function stanceOf(r: Rig, p: Player, now: number): string?
	if p:GetAttribute("Held") ~= "weapon" or not HeroAnim.holdsIn(r.modeTo) then
		return nil
	end
	local id = weaponOf(r, now)
	local fam = familyOfId(id)
	return if fam then HeroAnim.holdClip(id, fam) else nil
end

-- the held state pose (nil: none), by priority
local function stateOf(r: Rig, p: Player, now: number): string?
	if p:GetAttribute("Downed") == true then
		return nil
	end
	if p:GetAttribute("Reviving") ~= nil then
		return "revive"
	elseif p:GetAttribute("Carrying") ~= nil then
		-- a grabbed robot held as a club (pt-combat sets CarryGrip "club"): both hands on it by the shoulder
		return if p:GetAttribute("CarryGrip") == "club" then "robotHold" else "carry"
	elseif p:GetAttribute("Blocking") == true then
		local shield = p:GetAttribute("Held") == "weapon" and familyOfId(weaponOf(r, now)) == "shield"
		return if shield then "guardShield" else "guard"
	elseif p:GetAttribute("Charging") ~= nil and p ~= player then
		return "powerCharge" -- yours shows the cast's own wind-up (CombatClient)
	elseif now < r.promptUntil then
		return "interactHold"
	elseif now < r.emoteUntil then
		return "emoteBob"
	end
	return nil
end

local function familyOf(row: any): string?
	return familyOfId(row.weapon)
end

-- an ability cast: its clip from the row and the combo step (a basic with no combo alternates on its own count)
function HeroAnimator.cast(p: Player?, row: any, step: number?)
	if not row or not p then
		return
	end
	local s = step
	if row.slot == "basic" and not row.hits then
		local r = rigOf(p :: Player)
		if r then
			local now = os.clock()
			r.basicN = if now - r.basicAt < 1.2 then r.basicN + 1 else 1
			r.basicAt = now
			s = r.basicN
		end
	end
	local clip = HeroAnim.castClip(row, familyOf(row), s)
	local dur = nil
	if row.channel and HeroAnim.loops(clip) then
		dur = (row.channel or 1) * (row.tick or 0.25)
	end
	HeroAnimator.play(p, clip, dur)
end

-- a grabbed robot swung as a weapon (pt-combat): step 1, 2, 3... alternates the swing and the backhand;
-- slam brings it down overhead. Every device calls it from the swing's event.
function HeroAnimator.robotSwing(p: Player?, step: number?, slam: boolean?)
	local clip = if slam then "robotSlam" elseif (step or 1) % 2 == 0 then "robotSwingBack" else "robotSwing"
	HeroAnimator.play(p, clip)
end

-- a cast time or a charge-up: the pose for the row (both hands, heavy, or aimed), held for `seconds`
function HeroAnimator.windup(p: Player?, seconds: number, row: any?)
	local clip = HeroAnim.windupClip(row, if row then familyOf(row) else nil)
	HeroAnimator.play(p, clip, math.max(0.2, seconds))
end

-- a flinch when hit, unless the hero is mid-cast (the cast wins); a heavy hit staggers, others twist away
local flinchN = 0
function HeroAnimator.hit(p: Player?, heavy: boolean?)
	if not p then
		return
	end
	local r = rigOf(p :: Player)
	if r and p:GetAttribute("Blocking") == true then
		return -- the guard takes it (GuardFx plays the block hit)
	end
	flinchN += 1
	local pick = if heavy then "flinchHeavy" else ({ "flinch", "flinchL", "flinchR" })[flinchN % 3 + 1]
	HeroAnimator.play(p, pick, nil, true)
end

-- the hit-stop: your own action clip holds still for a moment (CombatClient pauses the Animator too)
function HeroAnimator.freeze(seconds: number)
	local r = rigs[player]
	local a = r and r.action
	if a then
		local now = os.clock()
		a.holdT = a.holdT or (now - a.start)
		a.holdUntil = now + seconds
	end
end

function HeroAnimator.byUserId(id: number?): Player?
	return if id then Players:GetPlayerByUserId(id) else nil
end

-- every button's own move (gadgets, catch, interact, block reactions): a one-shot on that hero
function HeroAnimator.gadget(p: Player?, kind: string)
	local clip = HeroAnim.GADGET_CLIPS[kind]
	if clip then
		HeroAnimator.play(p, clip)
	end
end

-- GuardEvent (GuardFx): a hit on the guard, a perfect block, a broken guard
function HeroAnimator.guardEvent(p: Player?, kind: string)
	if not p then
		return
	end
	local r = rigOf(p :: Player)
	if kind == "block" then
		HeroAnimator.play(p, "blockHit", nil, true)
	elseif kind == "perfect" then
		HeroAnimator.play(p, "parry")
	elseif kind == "shatter" and r and (r.blocking or p:GetAttribute("Blocking") == true) then
		HeroAnimator.play(p, "guardBreak")
	end
end

-- the emote's bounce under EmoteFx's held pose (every device: EmoteFx plays it from the Emote attribute)
function HeroAnimator.emote(p: Player?, seconds: number)
	local r = p and rigOf(p :: Player)
	if r then
		r.emoteUntil = os.clock() + seconds
	end
end

-- The slow-mo finisher (lore step 7, FinisherFx): every hero's clips run at this speed on this device only
-- (the server is never slowed). The mode clips' clock lags behind by `modeLag`; action clips start later.
HeroAnimator.timeScale = 1
local modeLag = 0
local lastUpdate = 0

local LEG = HeroAnim.LEGS
local AIR = { air = true, glide = true }

local function step(r: Rig, p: Player, now: number, dt: number)
	local vel = r.root.AssemblyLinearVelocity
	local speed = vel.Magnitude
	local flat = Vector3.new(vel.X, 0, vel.Z).Magnitude
	-- the fall speed just before a landing (it decays, so a landing reads the last moments of the fall)
	r.fall = math.max(-vel.Y, r.fall - dt * 160, 0)
	local mode = modeOf(p)
	local downed = p:GetAttribute("Downed") == true
	-- a mode change plays its transition (a take-off, a landing...); an air jump flips
	if mode ~= r.rawMode then
		local tr = if downed then nil else HeroAnim.transition(r.rawMode, mode, r.fall, flat)
		if tr == "landHard" and p:GetAttribute("Landing") ~= nil then
			tr = "land" -- an equipped landing pose (EmoteFx) is the big landing
		end
		r.rawMode = mode
		if tr then
			HeroAnimator.play(p, tr, nil, true)
		end
	elseif mode and AIR[mode] and vel.Y - r.lastVy > HeroAnim.jumpKick and vel.Y > 12 then
		HeroAnimator.play(p, "airFlip", nil, true)
	end
	r.lastVy = vel.Y
	-- attribute edges: a lift and a heave around a carry, the Awakening burst
	local carrying = p:GetAttribute("Carrying") ~= nil
	if carrying ~= r.carrying then
		r.carrying = carrying
		HeroAnimator.play(p, if carrying then "lift" else "heave")
	end
	local awake = p:GetAttribute("Awakened") == true
	if awake ~= r.awake then
		r.awake = awake
		if awake then
			HeroAnimator.play(p, "awaken")
		end
	end
	r.blocking = p:GetAttribute("Blocking") == true

	local ctx = {
		vy = vel.Y,
		giveUp = p:GetAttribute("GiveUp") == true,
		ride = p:GetAttribute("PowerSet") :: any,
	}
	local want = HeroAnim.modeClip(mode, speed, downed, r.modeTo, ctx)
	if want ~= r.modeTo then
		r.modeFrom, r.modeTo, r.modeAt = r.modeTo, want, now
	end
	local wTo = math.clamp((now - r.modeAt) / HeroAnim.modeBlend, 0, 1)
	if wTo >= 1 then
		r.modeFrom = nil
	end
	local clipNow = now - modeLag
	local from = if r.modeFrom then HeroAnim.sample(r.modeFrom, clipNow) else nil
	local to = if r.modeTo then HeroAnim.sample(r.modeTo, clipNow) else nil
	-- the held state (guard, carry, charge-up, revive...) fades in and out like the stance, and hides it
	local dtHold = math.clamp(now - r.holdLast, 0, 0.1)
	r.holdLast = now
	local fade = dtHold / HeroAnim.holdBlend
	local stateWant = stateOf(r, p, now)
	if stateWant then
		r.stateClip = stateWant
	end
	r.stateW = if stateWant then math.min(1, r.stateW + fade) else math.max(0, r.stateW - fade)
	local state = if r.stateW > 0 and r.stateClip
		then HeroAnim.sample(r.stateClip :: string, clipNow)
		else nil
	-- the weapon stance fades in and out (holdBlend), over the mode pose and under any action
	local stance = if stateWant then nil else stanceOf(r, p, now)
	if stance then
		r.holdClip = stance
	end
	r.holdW = if stance then math.min(1, r.holdW + fade) else math.max(0, r.holdW - fade)
	local hold = if r.holdW > 0 and r.holdClip then HeroAnim.sample(r.holdClip :: string, clipNow) else nil
	local wHold = r.holdW * HeroAnim.holdWeight
	local act, wAct = nil, 0
	local a = r.action
	if a then
		if a.holdUntil then
			if now < a.holdUntil then
				a.start = now - (a.holdT or 0) -- held: the clip's clock stops
			else
				a.holdUntil, a.holdT = nil, nil
			end
		end
		local t = now - a.start
		wAct = HeroAnim.actionWeight(t, a.dur)
		if wAct <= 0 and t >= a.dur then
			r.action = nil
		else
			act = HeroAnim.sample(a.clip, t)
		end
	end
	-- a cast that leaves the legs alone, cast standing still: the feet set and the knees bend under it, so the
	-- whole body moves (a running hero keeps the Animator's stride)
	local brace = if act
			and not r.modeTo
			and speed < 4
			and not HeroAnim.movesLegs((a :: Action).clip)
		then HeroAnim.sample("brace", 0)
		else nil
	-- the upper-body layer (HeroAnim.layer): running on the ground a cast shows only a little of its legs, so
	-- the stride carries on; flying, falling, gliding, swimming or riding it shows none of them and only the
	-- Root's turn, so the travel pose keeps its legs and pitch
	local legW, upper = HeroAnim.layer(r.modeTo, flat)
	for name, motor in r.motors do
		local f = from and from[name]
		local tt = to and to[name]
		local ac = act and act[name]
		local hd = hold and hold[name]
		local st = state and state[name]
		local br = brace and brace[name]
		local last = r.written[motor]
		if f or tt or ac or hd or st or br then
			-- what the Animator set this frame, or rest if it left our last pose in place
			local base = motor.Transform
			if last and base == last then
				base = IDENTITY
			end
			local out = base
			if f then
				out = out:Lerp(toCFrame(f), if tt then 1 else 1 - wTo)
			end
			if tt then
				out = out:Lerp(toCFrame(tt), wTo)
			end
			if hd then
				out = out:Lerp(toCFrame(hd), wHold)
			end
			local lw = if LEG[name] then legW else 1
			if upper and name == "Root" then
				st = st and HeroAnim.upperRoot(st)
				ac = ac and HeroAnim.upperRoot(ac)
			end
			if st and lw > 0 then
				out = out:Lerp(toCFrame(st), r.stateW * lw)
			end
			if br then
				out = out:Lerp(toCFrame(br), wAct)
			end
			if ac and lw > 0 then
				out = out:Lerp(toCFrame(ac), wAct * lw)
			end
			motor.Transform = out
			r.written[motor] = out
		elseif last then
			if motor.Transform == last then
				motor.Transform = IDENTITY -- nothing animates this joint now: back to rest
			end
			r.written[motor] = nil
		end
	end
end

-- your mode to the server (at most every 0.15 s; the latest one wins), so other devices pose you
local sentMode = 0
local sentAt = 0
local function sendMode(now: number)
	local n = HeroAnim.modeIndex[displayMode()] or 1
	if n ~= sentMode and now - sentAt >= 0.15 then
		sentMode, sentAt = n, now
		Net.send("MoveMode", n)
	end
end

local function update()
	local now = os.clock()
	local dt = math.min(0.1, now - lastUpdate)
	lastUpdate = now
	local slow = HeroAnimator.timeScale
	if slow < 1 then
		local held = dt * (1 - slow)
		modeLag += held
		for _, r in rigs do
			local a = r.action
			if a and not a.holdUntil then
				a.start += held -- the action clip's clock runs at the slow speed
			end
		end
	end
	sendMode(now)
	local cam = Workspace.CurrentCamera
	local eye = cam and cam.CFrame.Position or Vector3.zero
	for _, p in Players:GetPlayers() do
		local r = rigOf(p)
		if r then
			local d = (r.root.Position - eye).Magnitude
			if d <= HeroAnim.range then
				r.frame += 1
				if p == player or d <= HeroAnim.nearRange or r.frame % 2 == 0 then
					step(r, p, now, if p == player or d <= HeroAnim.nearRange then dt else dt * 2)
				end
			end
		end
	end
end

function HeroAnimator.init()
	RunService.PreSimulation:Connect(FrameProf.wrap("HeroAnimator", update))
	Players.PlayerRemoving:Connect(function(p)
		rigs[p] = nil
	end)
	player.CharacterAdded:Connect(function()
		sentMode = 0
	end)
	-- interact: a terminal, a door, a quest giver (ProximityPrompts fire only for you; others see their result)
	ProximityPromptService.PromptTriggered:Connect(function(_prompt, who)
		if who == player then
			local r = rigs[player]
			if r then
				r.promptUntil = 0
			end
			HeroAnimator.play(player, "interact", nil, true)
		end
	end)
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(_prompt, who)
		local r = who == player and rigOf(player)
		if r then
			r.promptUntil = os.clock() + 30
		end
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(_prompt, who)
		local r = who == player and rigs[player]
		if r then
			r.promptUntil = 0
		end
	end)
	-- the interact key (Catch): reach out and pull in (a grab then shows the lift, from Carrying)
	InputController.Pressed:Connect(function(action)
		if action == "Catch" then
			HeroAnimator.play(player, "catch", nil, true)
		end
	end)
end

return HeroAnimator
