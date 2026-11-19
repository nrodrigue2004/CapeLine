--!strict
-- NpcGestures: idle variety for the quest givers and the named helpers (pt-anims, nate's playtest 2026-11-19:
-- "for animations don't forget about ... npcs"). The server tags their rigs "NpcGesture" (attribute Gesture:
-- "giver" or "helper"); on this device the nearest few (Config.Presets gestureNear / gestureMax) play
-- Shared.NpcAnim's people clips on their upper body: a wave when a hero first comes near, the talk while one
-- stands close, a beckon or a point when one is in sight, otherwise arms crossed, a look round, a check of the
-- time or a shrug every few seconds. Written to Motor6D.Transform in PreSimulation (local to this device, like
-- every other pose), under FrameProf. Looks only.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NpcAnim = require(Shared:WaitForChild("NpcAnim"))
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local RigJoints = require(Shared:WaitForChild("RigJoints"))
local QualityController = require(script.Parent.QualityController)

local NpcGestures = {}

type Person = {
	model: Model,
	root: BasePart?,
	motors: { [string]: Motor6D },
	kind: string,
	clip: string?,
	at: number,
	held: boolean,
	nextAt: number,
	greeted: boolean,
	seed: number,
	touched: { [Motor6D]: boolean },
}

local TAG = "NpcGesture"
local G = NpcAnim.people
local people: { [Model]: Person } = {}
local scratch: { [string]: { number } } = {}
local RAD = math.rad

-- Motor6Ds or AnimationConstraints (Shared.RigJoints; fix-anims 2026-11-19), both posed on Transform
local function motorsOf(m: Model): { [string]: Motor6D }
	return RigJoints.of(m) :: any
end

local function add(m: Instance)
	if not m:IsA("Model") or people[m] then
		return
	end
	local motors = motorsOf(m)
	local root = m.PrimaryPart or m:FindFirstChild("HumanoidRootPart")
	local kind = m:GetAttribute("Gesture")
	people[m] = {
		model = m,
		root = if root and root:IsA("BasePart") then root else nil,
		motors = motors,
		kind = if type(kind) == "string" then kind else "giver",
		clip = nil,
		at = 0,
		held = false,
		nextAt = os.clock() + math.random() * 3,
		greeted = false,
		seed = math.random(),
		touched = {},
	}
end

local function rest(p: Person)
	for m in p.touched do
		m.Transform = CFrame.identity
	end
	table.clear(p.touched)
end

-- the nearest hero's distance from a person (studs)
local function heroDistance(pos: Vector3): number
	local best = math.huge
	for _, pl in Players:GetPlayers() do
		local ch = pl.Character
		local r = ch and ch.PrimaryPart
		if r then
			best = math.min(best, (r.Position - pos).Magnitude)
		end
	end
	return best
end

local order: { Person } = {}
local dist: { [Person]: number } = {}
local function nearer(a: Person, b: Person): boolean
	return dist[a] < dist[b]
end

local function update()
	local now = os.clock()
	local Q = QualityController.preset
	local near, most = Q.gestureNear or 70, Q.gestureMax or 8
	local cam = Workspace.CurrentCamera
	local eye = cam and cam.CFrame.Position or Vector3.zero
	table.clear(order)
	table.clear(dist)
	for m, p in people do
		if not m.Parent then
			people[m] = nil
		elseif p.root then
			local d = (p.root.Position - eye).Magnitude
			if d <= near then
				dist[p] = d
				table.insert(order, p)
			elseif next(p.touched) then
				rest(p)
			end
		end
	end
	table.sort(order, nearer)
	for i, p in order do
		if i > most then
			if next(p.touched) then
				rest(p)
			end
			continue
		end
		if not next(p.motors) then
			p.motors = motorsOf(p.model) -- streamed in after the tag
		end
		local root = p.root :: BasePart
		local hero = heroDistance(root.Position)
		if hero > G.farRange then
			p.greeted = false -- they wave again the next time someone comes over
		end
		local clip = p.clip
		local c = clip and NpcAnim.CLIPS[clip]
		local t = now - p.at
		local done = c == nil or (not p.held and t >= c.dur)
		if p.held and clip then
			-- the talk lasts while a hero stands close
			local want = NpcAnim.gesture(p.kind, hero, p.greeted, 0)
			if want ~= clip then
				done = true
			end
		end
		local arrived = hero <= G.nearRange and not p.greeted -- a hero walked up: greet them now
		if done and (now >= p.nextAt or arrived) then
			p.seed = (p.seed * 9301 + 0.49297) % 1
			local pick, held = NpcAnim.gesture(p.kind, hero, p.greeted, p.seed)
			if pick == (NpcAnim.PEOPLE[p.kind] or {}).near then
				p.greeted = true
			end
			p.clip, p.at, p.held = pick, now, held
			p.nextAt = now + G.every[1] + p.seed * (G.every[2] - G.every[1])
			clip, c, t = pick, NpcAnim.CLIPS[pick], 0
		elseif done then
			p.clip = nil
			clip, c = nil, nil
		end
		if not c or not clip then
			if next(p.touched) then
				rest(p)
			end
			continue
		end
		local w = NpcAnim.weight(t, c.dur, G.fade, p.held or c.loop)
		local pose = NpcAnim.sample(clip, t, scratch)
		for joint, a in pose do
			local m = p.motors[joint]
			if m then
				m.Transform = CFrame.identity:Lerp(CFrame.Angles(RAD(a[1]), RAD(a[2]), RAD(a[3])), w)
				p.touched[m] = true
			end
		end
		-- joints the last gesture moved and this one does not go back to rest
		for m in p.touched do
			if not pose[m.Name] then
				m.Transform = CFrame.identity
				p.touched[m] = nil
			end
		end
	end
end

function NpcGestures.init()
	for _, m in CollectionService:GetTagged(TAG) do
		add(m)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(m)
		people[m :: Model] = nil
	end)
	RunService.PreSimulation:Connect(FrameProf.wrap("NpcGestures", update))
end

return NpcGestures
