--!strict
-- NpcLoco: Roblox's own R15 idle, walk and run animations on a rig the game draws itself (NpcRig: robots;
-- quality pass 2026-11-18, nate: "the enemies dont move properly"). The heroes walk with Roblox's default
-- Animate, so the robots now walk the same way instead of a code-posed swing whose feet skated. The three
-- clips are Roblox's own (made by Roblox, free in every experience; ids in Config.Enemies.look.loco) and play
-- on the rig's AnimationController, blended by speed like Animate (Shared.LocoMath). Poses the game adds on
-- top (aimed rifles, a shield arm, a crouch) are written after the Animator in PreSimulation (NpcRig.over).
-- Device only: nothing here reaches the server.

local ContentProvider = game:GetService("ContentProvider")
local Workspace = game:GetService("Workspace")

local LocoMath = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("LocoMath"))

local NpcLoco = {}

export type Loco = {
	idle: AnimationTrack,
	walk: AnimationTrack,
	run: AnimationTrack,
	on: boolean,
	scale: number, -- the rig's heightScale (LocoMath)
	w: { number }, -- the weights and speeds last set (idle, walk, run, walk speed, run speed)
}

local SMALL = 0.0001 -- a clip kept playing at no weight (Animate's smallButNotZero), so it never restarts
local EPS = 0.02 -- changes smaller than this are not sent to the tracks

local animations: { [string]: Animation } = {}
local function animation(id: string): Animation
	local a = animations[id]
	if not a then
		a = Instance.new("Animation")
		a.AnimationId = id
		animations[id] = a
	end
	return a
end

-- Load the three clips once at start (in the background), so a rig's tracks are ready when it first walks
function NpcLoco.preload(cfg: any)
	local list = { animation(cfg.idle), animation(cfg.walk), animation(cfg.run) }
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
	end)
end

-- The clips have loaded (a track's Length stays 0 until then, or for good if a clip cannot load): until then
-- the caller keeps its code-posed walk, so a robot never slides along in the rest pose
function NpcLoco.ready(l: Loco): boolean
	return l.idle.Length > 0 and l.walk.Length > 0 and l.run.Length > 0
end

-- The rig's tracks, loaded once (the rig must be in the Workspace). Nil when it has no AnimationController or
-- a clip will not load (the caller keeps its own code-posed walk then).
function NpcLoco.new(model: Model, ground: number, hip: number, cfg: any): Loco?
	if not model:IsDescendantOf(Workspace) then
		return nil
	end
	local ac = model:FindFirstChildOfClass("AnimationController")
	if not ac then
		return nil
	end
	local animator = ac:FindFirstChildOfClass("Animator")
	if not animator then
		local made = Instance.new("Animator")
		made.Parent = ac
		animator = made
	end
	local ok, tracks = pcall(function()
		local a = animator :: Animator
		return {
			a:LoadAnimation(animation(cfg.idle)),
			a:LoadAnimation(animation(cfg.walk)),
			a:LoadAnimation(animation(cfg.run)),
		}
	end)
	if not ok or type(tracks) ~= "table" then
		return nil
	end
	for _, t in tracks do
		t.Looped = true
		t.Priority = Enum.AnimationPriority.Movement -- one priority, so the three blend by weight
	end
	return {
		idle = tracks[1],
		walk = tracks[2],
		run = tracks[3],
		on = false,
		scale = LocoMath.heightScale(ground, hip, cfg),
		w = { -1, -1, -1, -1, -1 },
	}
end

local function weight(t: AnimationTrack, w: number, last: number, fade: number): number
	if math.abs(w - last) < EPS and not (w == 0 and last ~= 0) then
		return last
	end
	t:AdjustWeight(math.max(w, SMALL), fade)
	return w
end

local function speed(t: AnimationTrack, s: number, last: number): number
	if math.abs(s - last) < EPS and not (s == 0 and last ~= 0) then
		return last
	end
	t:AdjustSpeed(s)
	return s
end

-- Play the walk for a body moving at `studs` per second; `frozen` holds the pose (a hit-stop)
function NpcLoco.drive(l: Loco, studs: number, frozen: boolean, cfg: any)
	local b = LocoMath.blend(studs, l.scale, cfg)
	local w = l.w
	if not l.on then
		l.on = true
		l.idle:Play(cfg.fade, math.max(b.idle, SMALL), 1)
		l.walk:Play(cfg.fade, math.max(b.walk, SMALL), b.walkSpeed)
		l.run:Play(cfg.fade, math.max(b.run, SMALL), b.runSpeed)
		w[1], w[2], w[3], w[4], w[5] = b.idle, b.walk, b.run, b.walkSpeed, b.runSpeed
		return
	end
	w[1] = weight(l.idle, b.idle, w[1], cfg.fade)
	w[2] = weight(l.walk, b.walk, w[2], cfg.fade)
	w[3] = weight(l.run, b.run, w[3], cfg.fade)
	w[4] = speed(l.walk, if frozen then 0 else b.walkSpeed, w[4])
	w[5] = speed(l.run, if frozen then 0 else b.runSpeed, w[5])
	local idleSpeed = if frozen then 0 else 1
	if l.idle.Speed ~= idleSpeed then
		l.idle:AdjustSpeed(idleSpeed)
	end
end

-- Stop the clips at once (the code-posed moves take over this frame)
function NpcLoco.stop(l: Loco)
	if not l.on then
		return
	end
	l.on = false
	l.idle:Stop(0)
	l.walk:Stop(0)
	l.run:Stop(0)
	l.w[1], l.w[2], l.w[3], l.w[4], l.w[5] = -1, -1, -1, -1, -1
end

return NpcLoco
