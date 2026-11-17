--!strict
-- HeroAnimator: plays Shared.HeroAnim's clips on every hero near you (overhaul plan step 2). Two layers on top
-- of the Animator (Roblox's default Animate keeps the ground walk, run, idle and jump):
-- * mode: the movement pose (fly, hover, glide, leap, dash, slide, swing, wall run, ride, swim, Downed),
--   crossfaded on a change. Your own mode comes from MoveController; other heroes' from their "Move"
--   attribute (you send yours with MoveMode, the server sets it) and their speed.
-- * action: one-shots (every cast, each weapon's combo and moves, the windup, the channel, the flinch).
--   A clip moves only the joints it lists, so a cast in the air keeps the flight legs.
-- Poses are written to Motor6D.Transform in PreSimulation, after the Animator, blended from what the Animator
-- set (or from rest where it set nothing). Transform is local to each device, so every device animates
-- everyone it can see; heroes past HeroAnim.range are left alone, past nearRange they update every other frame.
-- PLACEHOLDER ANIMATION: hand-keyed poses (HeroAnim) until real animations.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local HeroAnim = require(Shared:WaitForChild("HeroAnim"))
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local MoveController = require(script.Parent.MoveController)

local HeroAnimator = {}

local player = Players.LocalPlayer
local IDENTITY = CFrame.identity
local RAD = math.rad

type Action = { clip: string, start: number, dur: number }
type Rig = {
	char: Model,
	root: BasePart,
	motors: { [string]: Motor6D },
	written: { [Motor6D]: CFrame },
	modeFrom: string?,
	modeTo: string?,
	modeAt: number,
	action: Action?,
	frame: number,
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
	local motors = motorsOf(char)
	if not motors.Waist then
		return nil -- not an R15 rig (yet)
	end
	r = {
		char = char,
		root = root,
		motors = motors,
		written = {},
		modeFrom = nil,
		modeTo = nil,
		modeAt = 0,
		action = nil,
		frame = 0,
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

local function modeOf(p: Player): string?
	if p == player then
		return MoveController.mode
	end
	local n = p:GetAttribute("Move")
	return if type(n) == "number" then HeroAnim.MODES[n] else nil
end

-- start an action clip on a hero (dur overrides the clip's length: channels, windups)
function HeroAnimator.play(p: Player?, clip: string, dur: number?)
	if not p or not HeroAnim.CLIPS[clip] then
		return
	end
	local r = rigOf(p)
	if not r then
		return
	end
	r.action = { clip = clip, start = os.clock(), dur = dur or HeroAnim.CLIPS[clip].dur }
end

local function familyOf(row: any): string?
	local w = row.weapon and Config.Weapons.list[row.weapon]
	return if w then w[2] else nil
end

-- an ability cast: its clip from the row and the combo step
function HeroAnimator.cast(p: Player?, row: any, step: number?)
	if not row then
		return
	end
	local clip = HeroAnim.castClip(row, familyOf(row), step)
	local dur = nil
	if clip == "channel" then
		dur = (row.channel or 1) * (row.tick or 0.25)
	end
	HeroAnimator.play(p, clip, dur)
end

function HeroAnimator.windup(p: Player?, seconds: number)
	HeroAnimator.play(p, "windup", math.max(0.2, seconds))
end

-- a flinch when hit, unless the hero is mid-cast (the cast wins)
function HeroAnimator.hit(p: Player?)
	if not p then
		return
	end
	local r = rigOf(p)
	local a = r and r.action
	if a and os.clock() - a.start < a.dur and a.clip ~= "flinch" then
		return
	end
	HeroAnimator.play(p, "flinch")
end

function HeroAnimator.byUserId(id: number?): Player?
	return if id then Players:GetPlayerByUserId(id) else nil
end

local function step(r: Rig, p: Player, now: number)
	local speed = r.root.AssemblyLinearVelocity.Magnitude
	local want = HeroAnim.modeClip(modeOf(p), speed, p:GetAttribute("Downed") == true, r.modeTo)
	if want ~= r.modeTo then
		r.modeFrom, r.modeTo, r.modeAt = r.modeTo, want, now
	end
	local wTo = math.clamp((now - r.modeAt) / HeroAnim.modeBlend, 0, 1)
	if wTo >= 1 then
		r.modeFrom = nil
	end
	local from = if r.modeFrom then HeroAnim.sample(r.modeFrom, now) else nil
	local to = if r.modeTo then HeroAnim.sample(r.modeTo, now) else nil
	local act, wAct = nil, 0
	local a = r.action
	if a then
		local t = now - a.start
		wAct = HeroAnim.actionWeight(t, a.dur)
		if wAct <= 0 and t >= a.dur then
			r.action = nil
		else
			act = HeroAnim.sample(a.clip, t)
		end
	end
	for name, motor in r.motors do
		local f = from and from[name]
		local tt = to and to[name]
		local ac = act and act[name]
		local last = r.written[motor]
		if f or tt or ac then
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
			if ac then
				out = out:Lerp(toCFrame(ac), wAct)
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

local function update()
	local now = os.clock()
	local cam = Workspace.CurrentCamera
	local eye = cam and cam.CFrame.Position or Vector3.zero
	for _, p in Players:GetPlayers() do
		local r = rigOf(p)
		if r then
			local d = (r.root.Position - eye).Magnitude
			if d <= HeroAnim.range then
				r.frame += 1
				if p == player or d <= HeroAnim.nearRange or r.frame % 2 == 0 then
					step(r, p, now)
				end
			end
		end
	end
end

-- your mode to the server (at most every 0.15 s; the latest one wins), so other devices pose you
local sentMode = 0
local pendingAt = 0
local function sendMode()
	local n = HeroAnim.modeIndex[MoveController.mode] or 1
	if n ~= sentMode then
		sentMode = n
		Net.send("MoveMode", n)
	end
end

function HeroAnimator.init()
	RunService.PreSimulation:Connect(FrameProf.wrap("HeroAnimator", update))
	MoveController.ModeChanged:Connect(function()
		local now = os.clock()
		if now - pendingAt >= 0.15 then
			pendingAt = now
			sendMode()
		else
			local wait = 0.15 - (now - pendingAt)
			pendingAt = now + wait
			task.delay(wait, sendMode)
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		rigs[p] = nil
	end)
	player.CharacterAdded:Connect(function()
		sentMode = 0
		task.defer(sendMode)
	end)
end

return HeroAnimator
