--!strict
-- SwingTrailFx: lights the weapons' swing trails (list-combat 2026-11-20; checklist lines 196 and 198: "swing trails
-- per weapon" and "weapon moves ... with no slash effects of their own"). WeaponKit builds each melee weapon's
-- SwingTrail (off) on every hero; here, for the heroes near the camera holding their weapon, a trail is lit while one
-- of that weapon's moves plays (HeroAnimator.actionOf: inside Config.Weapons.swingTrail.window of its clip) and off
-- otherwise, so the blade's path through the swing draws as a slash on every device. At most `max` heroes within
-- `near` studs; the loop is timed by FrameProf.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local HeroAnim = require(Shared:WaitForChild("HeroAnim"))
local FrameProf = require(Shared:WaitForChild("FrameProf"))

local HeroAnimator = require(script.Parent.Parent.Controllers.HeroAnimator)

local SwingTrailFx = {}

local ST = Config.Weapons.swingTrail
type Rig = { folder: Instance, trails: { Trail }, on: boolean }
local rigs: { [Player]: Rig } = {}

-- every clip a weapon's moves play (its combo and Z X C V, two-handed copies included)
local moveClips: { [number]: { [string]: boolean } } = {}
local function clipsOf(id: number): { [string]: boolean }
	local set = moveClips[id]
	if set then
		return set
	end
	set = {}
	local m = HeroAnim.WEAPON_MOVES[id]
	if m then
		for _, c in m.combo or {} do
			set[c] = true
		end
		for _, k in { "Z", "X", "C", "V" } do
			if m[k] then
				set[m[k]] = true
			end
		end
	end
	moveClips[id] = set
	return set
end
SwingTrailFx.clipsOf = clipsOf

-- the SwingTrails of a weapon folder (on its pieces, or on the hands through its TrailRef values)
local function trailsOf(folder: Instance): { Trail }
	local out: { Trail } = {}
	for _, d in folder:GetDescendants() do
		if d:IsA("Trail") and d.Name == "SwingTrail" then
			table.insert(out, d)
		elseif d:IsA("ObjectValue") and d.Name == "TrailRef" and d.Value and d.Value:IsA("Trail") then
			table.insert(out, d.Value :: Trail)
		end
	end
	return out
end

local function set(r: Rig, on: boolean)
	if r.on == on then
		return
	end
	r.on = on
	for _, t in r.trails do
		if t.Parent then
			t.Enabled = on
		end
	end
end

-- lit now? the hero's action is one of its weapon's moves, inside the window
function SwingTrailFx.lit(id: number, clip: string?, t: number, dur: number): boolean
	if not clip or dur <= 0 or not clipsOf(id)[clip] then
		return false
	end
	local u = t / dur
	return u >= ST.window[1] and u <= ST.window[2]
end

local function step()
	local cam = Workspace.CurrentCamera
	local eye = cam and cam.CFrame.Position or Vector3.zero
	local live = 0
	for _, p in Players:GetPlayers() do
		local char = p.Character
		local look = char and char:FindFirstChild("HeroLook")
		local wf = look and look:FindFirstChild("Weapon")
		local id = wf and wf:GetAttribute("WeaponId")
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local near = root ~= nil and root:IsA("BasePart") and (root.Position - eye).Magnitude <= ST.near
		local r = rigs[p]
		if r and r.folder ~= wf then
			set(r, false)
			rigs[p] = nil
			r = nil
		end
		if
			not (
				wf
				and type(id) == "number"
				and near
				and live < ST.max
				and p:GetAttribute("Held") == "weapon"
			)
		then
			if r then
				set(r, false)
			end
			continue
		end
		if not r then
			r = { folder = wf :: Instance, trails = trailsOf(wf :: Instance), on = false }
			rigs[p] = r
		end
		live += 1
		local clip, t, dur = HeroAnimator.actionOf(p)
		set(r :: Rig, SwingTrailFx.lit(id :: number, clip, t, dur))
	end
end

function SwingTrailFx.init()
	RunService.RenderStepped:Connect(FrameProf.wrap("SwingTrailFx", step))
	Players.PlayerRemoving:Connect(function(p)
		rigs[p] = nil
	end)
end

return SwingTrailFx
