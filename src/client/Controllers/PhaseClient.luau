--!strict
-- PhaseClient: a private mission run's pieces are only its own party's to see and touch (missions lane, 2026-11-20;
-- nate: "other players shouldn't be able to interrupt ur story. Just you or you and friends in missions"). The server
-- tags a run's Sites models (SiteKit.inPhase: rings, break objects, the runaway train, citizens, pads, shards, props)
-- with the Phase attribute and puts the local player's own phase on its Player (PhaseService). On a device whose
-- player is not in that phase (Shared.PhaseRules.sees: strict both ways, so a run's party does not see the open
-- world's site pieces either) every part of the model goes invisible (LocalTransparencyModifier), stops colliding,
-- taking queries and touches, its decals fade out and its prompts, lights, particles and signs switch off, all
-- locally: the server's model is untouched and shows again the moment this player joins the phase (or leaves one).
-- Its robots are never sent to this device at all (EnemyService: Enemy.Delta and CombatEvents per phase).
-- Event-driven (Sites' children, their Phase attribute, the player's Phase attribute, parts streaming in): no
-- per-frame work. StoryProps and ActivityProps never dress a hidden model (PhaseClient.hidden).
-- Players too (nate, 2026-11-20, "Hide you fully"): a hero in another phase than this device's (a run's party seen
-- from outside, or the open world seen from inside a run; squad members in one run see each other) is hidden the
-- same way, its whole character (parts and accessories, decals, its name, trails, aura and look pieces, sounds
-- muted, no collision here). PhaseClient.seesPlayer(p) gates what draws outside the character (Plates, Radar,
-- SquadHud, the ping wheel and the Fx that put effects in the world for a hero).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local PhaseRules = require(Shared:WaitForChild("PhaseRules"))

local PhaseClient = {}

type Saved = {
	cc: boolean?,
	cq: boolean?,
	ct: boolean?,
	alpha: number?,
	on: boolean?,
	reach: number?,
	vol: number?,
	name: Enum.HumanoidDisplayDistanceType?,
}

local hiddenModels: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local saved: { [Instance]: Saved } = setmetatable({}, { __mode = "k" }) :: any
local mine: number? = nil

-- Is this Sites model hidden on this device (another phase's, or the open world's while this player is in one)?
function PhaseClient.hidden(m: Instance): boolean
	return hiddenModels[m] == true
end

-- This device's phase (nil: the open world)
function PhaseClient.phase(): number?
	return mine
end

local function hideOne(d: Instance)
	if saved[d] then
		return
	end
	if d:IsA("BasePart") then
		saved[d] = { cc = d.CanCollide, cq = d.CanQuery, ct = d.CanTouch }
		d.LocalTransparencyModifier = 1
		d.CanCollide = false
		d.CanQuery = false
		d.CanTouch = false
	elseif d:IsA("Decal") then -- (a Texture is a Decal)
		saved[d] = { alpha = d.Transparency }
		d.Transparency = 1
	elseif d:IsA("Sound") then
		saved[d] = { vol = d.Volume }
		d.Volume = 0
	elseif d:IsA("Humanoid") then
		saved[d] = { name = d.DisplayDistanceType }
		d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	elseif d:IsA("ProximityPrompt") then
		-- (the server may switch the prompt on again, a set-down citizen; at reach 0 it never shows here)
		saved[d] = { on = d.Enabled, reach = d.MaxActivationDistance }
		d.Enabled = false
		d.MaxActivationDistance = 0
	elseif
		d:IsA("BillboardGui")
		or d:IsA("SurfaceGui")
		or d:IsA("ParticleEmitter")
		or d:IsA("Light")
		or d:IsA("Beam")
		or d:IsA("Trail")
		or d:IsA("Highlight")
	then
		saved[d] = { on = (d :: any).Enabled };
		(d :: any).Enabled = false
	end
end

local function showOne(d: Instance)
	local s = saved[d]
	if not s then
		return
	end
	saved[d] = nil
	if d:IsA("BasePart") then
		d.LocalTransparencyModifier = 0
		d.CanCollide = s.cc == true
		d.CanQuery = s.cq == true
		d.CanTouch = s.ct == true
	elseif d:IsA("Decal") then
		d.Transparency = s.alpha or 0
	elseif d:IsA("Sound") then
		d.Volume = s.vol or d.Volume
	elseif d:IsA("Humanoid") then
		d.DisplayDistanceType = s.name or d.DisplayDistanceType
	elseif d:IsA("ProximityPrompt") then
		d.Enabled = s.on == true
		d.MaxActivationDistance = s.reach or d.MaxActivationDistance
	else
		(d :: any).Enabled = s.on == true
	end
end

local function apply(m: Instance, phase: any?)
	local hide =
		not PhaseRules.sees(PhaseRules.read(if phase == nil then m:GetAttribute("Phase") else phase), mine)
	if hide == (hiddenModels[m] == true) then
		return
	end
	if hide then
		hiddenModels[m] = true
		hideOne(m)
		for _, d in m:GetDescendants() do
			hideOne(d)
		end
	else
		hiddenModels[m] = nil
		showOne(m)
		for _, d in m:GetDescendants() do
			showOne(d)
		end
	end
end

local applyTimed = FrameProf.wrap("PhaseClient", apply)

local function watch(m: Instance)
	m:GetAttributeChangedSignal("Phase"):Connect(function()
		applyTimed(m)
	end)
	-- parts built later or streaming in take the model's state (only while it is hidden)
	m.DescendantAdded:Connect(function(d)
		if hiddenModels[m] then
			hideOne(d)
		end
	end)
	applyTimed(m)
end

---------------------------------------------------------------------------
-- Players ("Hide you fully", nate 2026-11-20)
---------------------------------------------------------------------------

local me = Players.LocalPlayer
local chars: { [Player]: Model } = {}

-- Does this device see that player (the same phase, or both in the open world)? Always itself.
function PhaseClient.seesPlayer(p: Player?): boolean
	if not p or p == me then
		return true
	end
	return PhaseRules.sees(PhaseRules.read(p:GetAttribute("Phase")), mine)
end

-- A character takes its player's phase: hidden while it is another phase's than this device's
local function applyChar(p: Player)
	local char = chars[p]
	if char then
		-- (false stands for "no phase": a character carries no Phase attribute of its own)
		apply(char, p:GetAttribute("Phase") or false)
	end
end
local applyCharTimed = FrameProf.wrap("PhaseClient", applyChar)

local function watchChar(p: Player, char: Model)
	local old = chars[p]
	if old then
		hiddenModels[old] = nil
	end
	chars[p] = char
	char.DescendantAdded:Connect(function(d)
		if hiddenModels[char] then
			hideOne(d)
		end
	end)
	applyCharTimed(p)
end

local function watchPlayer(p: Player)
	if p == me then
		return
	end
	p.CharacterAdded:Connect(function(char)
		watchChar(p, char)
	end)
	p:GetAttributeChangedSignal("Phase"):Connect(function()
		applyCharTimed(p)
	end)
	if p.Character then
		watchChar(p, p.Character)
	end
end

local function watchSites(sites: Instance)
	sites.ChildAdded:Connect(watch)
	for _, m in sites:GetChildren() do
		watch(m)
	end
end

function PhaseClient.init()
	local player = Players.LocalPlayer
	mine = PhaseRules.read(player:GetAttribute("Phase"))
	player:GetAttributeChangedSignal("Phase"):Connect(FrameProf.wrap("PhaseClient", function()
		mine = PhaseRules.read(player:GetAttribute("Phase"))
		local sites = Workspace:FindFirstChild("Sites")
		for _, m in if sites then sites:GetChildren() else {} do
			apply(m)
		end
		for p in chars do
			applyChar(p)
		end
	end))
	for _, p in Players:GetPlayers() do
		watchPlayer(p)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(p)
		chars[p] = nil
	end)
	local sites = Workspace:FindFirstChild("Sites")
	if sites then
		watchSites(sites)
	else
		local conn: RBXScriptConnection? = nil
		conn = Workspace.ChildAdded:Connect(function(c)
			if c.Name == "Sites" and c:IsA("Folder") then
				if conn then
					conn:Disconnect()
				end
				watchSites(c)
			end
		end)
	end
end

return PhaseClient
