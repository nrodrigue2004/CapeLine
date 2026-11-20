-- GuideClient: when the guides speak outside the camera beats (nate's lore, build plan step 6). Lines go to
-- Ui.GuideHud's queue; the rules are Shared.GuidePlan's; every line is fixed text in Config.Story.guides.
-- * Missions: a stage's radio lines as it starts (Patch on the radio, Lodestar in person in the safehouse),
--   by side, branches too; a late join skips them.
-- * Patch on the open-world radio: the first incident and the first world boss of a session, a level-up that
--   opens a story mission, a hint when the hero stands still with a story mission pinned, and a line after
--   Act 1's ending broadcast, and the rare Your double event on this hero (lore step 9, it skips the gap);
--   side-flavoured, at most one a Config.Story.guides.radio.gap, never in a mission
--   or the prologue, all off with the "Guide radio" setting. Lore step 12: your own new reputation tier, and a
--   high-tier hero the news names on this server (their safe hero name, once a session each).
-- * Lodestar in person: in the Vigil's HQ (the hero's HQ cell) with a Talk prompt (a fixed rotation of lines
--   that change with the story); he keeps away from the Dread Syndicate's Foundry. The Dev panel can spawn him
--   beside you. His figure is PrologueFx.lodestarRig (his fixed look from earnable creator pieces).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GuidePlan = require(Shared:WaitForChild("GuidePlan"))
local NpcRig = require(Shared:WaitForChild("NpcRig"))
local Net = require(Shared:WaitForChild("Net"))
local NewsPlan = require(Shared:WaitForChild("NewsPlan"))
local CreatorRules = require(Shared:WaitForChild("CreatorRules"))
local RepTiers = require(Shared:WaitForChild("RepTiers")) -- lore step 12: Patch names high-tier heroes

local State = require(script.Parent.Parent.State)
local StoryClient = require(script.Parent.StoryClient)
local WorldClient = require(script.Parent.WorldClient)
local SettingsClient = require(script.Parent.SettingsClient)
local HqClient = require(script.Parent.HqClient)
local GuideHud = require(script.Parent.Parent.Ui.GuideHud)
local PrologueFx = require(script.Parent.Parent.Fx.PrologueFx)

local GuideClient = {}

local G = Config.Story.guides
local player = Players.LocalPlayer
local radio = GuidePlan.radio()
GuideClient.radio = radio -- (first-30) the rate state, for tests that step past the gap

local function side(): string
	return if State.hero.side == "villain" then "villain" else "hero"
end

local function level(): number
	return State.hero.level or 1
end

local function story(): { [string]: any }?
	return StoryClient.journal
end

---------------------------------------------------------------------------
-- Patch on the open-world radio
---------------------------------------------------------------------------

local function busy(): boolean
	return StoryClient.inOpening() or StoryClient.inMission() or StoryClient.missionScene() ~= nil
end

-- Say an open-world line when the rate rules allow it. key is the rate key (once-a-session keys are unique);
-- lineKey and n pick the line.
local function say(key: string, lineKey: string, n: number?): boolean
	local now = os.clock()
	if
		not GuidePlan.radioOk(
			Config,
			radio,
			now,
			key,
			{ on = SettingsClient.on("guideRadio"), busy = busy() }
		)
	then
		return false
	end
	local l = GuidePlan.worldLine(Config, lineKey, side(), n)
	if l and GuideHud.say(l.who, l.text, { world = true, tag = "world" }) then
		GuidePlan.radioMark(radio, now, key)
		return true
	end
	return false
end

-- Lore step 12 (the city remembers): Patch names high-tier heroes (their safe hero names, Shared.RepTiers): you on
-- your own tier-up, and a high-tier hero the news names on this server (once a session each); same rate rules.
local aboutSaid: { [string]: boolean } = {}
local function sayText(key: string, text: string?): boolean
	local now = os.clock()
	if
		not text
		or not GuidePlan.radioOk(
			Config,
			radio,
			now,
			key,
			{ on = SettingsClient.on("guideRadio"), busy = busy() }
		)
	then
		return false
	end
	-- a fixed Config.Remembers line with a safe hero name in it (RepTiers), always Patch's
	local l = { who = "patch", text = text :: string }
	if GuideHud.say(l.who, l.text, { world = true, tag = "world" }) then
		GuidePlan.radioMark(radio, now, key)
		return true
	end
	return false
end

local function onRepFacts(data: any)
	if type(data) ~= "table" or data.join or type(data.list) ~= "table" then
		return
	end
	for _, f in data.list do
		local kind = type(f) == "table" and NewsPlan.KINDS[f.k]
		if (kind == "repVigil" or kind == "repSyndicate") and (tonumber(f.g) or 0) < 5 then
			local name = CreatorRules.heroName(Config, tonumber(f.t) or 0, tonumber(f.n) or 0)
			if name and name ~= player:GetAttribute("HeroName") and not aboutSaid[name] then
				local track = if kind == "repSyndicate" then "syndicate" else "vigil"
				if sayText("repAbout", RepTiers.radioAbout(Config, side(), track, name)) then
					aboutSaid[name] = true
				end
			end
		end
	end
end

-- first-30: a level-up's POWERS line waiting for the radio (GuidePlan.powerAt), tried every frame until `till`
local powerLine: { key: string, line: string, till: number }? = nil
local function powerStep(now: number)
	local p = powerLine
	if not p then
		return
	end
	if now > p.till or say(p.key, p.line) then
		powerLine = nil
	end
end

-- Idle: standing still (under idleMove studs) for `idle` seconds with a story mission pinned
local still = { pos = Vector3.zero, since = os.clock() }
local function idleStep(now: number)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local s = story()
	if not root or not s or busy() or HqClient.inside() then
		still.since = now
		return
	end
	if (root.Position - still.pos).Magnitude > G.radio.idleMove then
		still.pos, still.since = root.Position, now
		return
	end
	if now - still.since >= G.radio.idle then
		still.since = now
		local n = GuidePlan.idleMission(Config, s, level())
		if n then
			say("idle", "idle", n)
		end
	end
end

---------------------------------------------------------------------------
-- Mission stage lines
---------------------------------------------------------------------------

local stageKey: string? = nil
local function onMission()
	local m = StoryClient.mission
	if (m.num or 0) == 0 or m.done or m.kind == "wait" then
		if (m.num or 0) == 0 and stageKey then
			GuideHud.cancel("stage")
		end
		stageKey = nil
		return
	end
	local key =
		string.format("%d:%d:%s:%s:%s", m.num, m.step or 0, m.side or "hero", m.kind or "", m.text or "")
	if key == stageKey then
		return
	end
	stageKey = key
	if os.clock() - StoryClient.missionAt > G.radio.stageLate then
		return -- joined late: the stage's lines already played
	end
	local st = GuidePlan.stageFor(Config, m)
	for _, l in GuidePlan.stageLines(st, m.side or "hero") do
		GuideHud.say(l.who, l.text, { tag = "stage" })
	end
end

---------------------------------------------------------------------------
-- Lodestar in person
---------------------------------------------------------------------------

local talks = 0
local function talk(sideOverride: string?)
	local s = story() or { missions = 0, pinned = 0 }
	talks += 1
	local l = GuidePlan.talk(Config, s, sideOverride or side(), talks)
	if l then
		GuideHud.say(l.who, l.text, { cut = true, tag = "talk" })
	end
end

-- Lodestar's figure at feet with a Talk prompt; returns its model
local function figure(parent: Instance, feet: CFrame, sideOverride: string?): Model
	local rig = PrologueFx.lodestarRig(parent)
	NpcRig.place(rig, feet)
	local post = Instance.new("Part")
	post.Name = "TalkPost"
	post.Anchored = true
	post.CanCollide = false
	post.CanQuery = false
	post.CanTouch = false
	post.Transparency = 1
	post.Size = Vector3.one
	post.CFrame = feet + Vector3.new(0, 3, 0)
	post.Parent = rig.model
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = G.lodestar.prompt
	prompt.ObjectText = "Lodestar"
	prompt.KeyboardKeyCode = Enum.KeyCode.B -- E is Skill 2 (the HQ stations' key)
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = G.lodestar.range
	prompt.RequiresLineOfSight = false
	prompt.Parent = post
	prompt.Triggered:Connect(function()
		talk(sideOverride)
	end)
	return rig.model
end

local hqModel: Model? = nil
local hqCell: string? = nil
local function onHq(state: { [string]: any })
	-- WP12: a visit copy of a friend's HQ has no Lodestar (she is the owner's guide, not a decoration)
	local inside = state.on == true
		and state.side ~= "villain"
		and type(state.cell) == "table"
		and not state.visit
	local cellKey = if inside then table.concat(state.cell, ",") else nil
	if hqModel and cellKey == hqCell then
		return
	end
	if hqModel then
		hqModel:Destroy()
		hqModel = nil
	end
	hqCell = cellKey
	if not inside then
		return
	end
	local c = Vector3.new(state.cell[1], state.cell[2], state.cell[3])
	local at = c + Vector3.new(G.lodestar.at[1], 0, G.lodestar.at[2])
	local face = Vector3.new(c.X, at.Y, c.Z)
	hqModel = figure(Workspace, CFrame.lookAt(at, face))
end

local devModel: Model? = nil
-- Dev panel: Lodestar beside you for a minute (his talk as the Vigil hears it)
function GuideClient.spawnLodestar()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	if devModel then
		devModel:Destroy()
	end
	local fwd = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	fwd = if fwd.Magnitude > 0.1 then fwd.Unit else Vector3.new(0, 0, -1)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local feetY = root.Position.Y - (if hum then hum.HipHeight + root.Size.Y / 2 else 3)
	local at = Vector3.new(root.Position.X, feetY, root.Position.Z) + fwd * 8
	local model = figure(Workspace, CFrame.lookAt(at, at - fwd), "hero")
	devModel = model
	task.delay(G.lodestar.spawnFor, function()
		if devModel == model then
			model:Destroy()
			devModel = nil
		end
	end)
end

function GuideClient.init()
	StoryClient.Changed:Connect(function(what)
		if what == "mission" then
			onMission()
		end
	end)
	WorldClient.Changed:Connect(function(what)
		if what == "incidents" and next(WorldClient.incidents) ~= nil then
			say("firstIncident", "firstIncident")
		elseif what == "boss" and WorldClient.boss.state == 2 then -- a world boss arriving
			say("firstBoss", "firstBoss")
		end
	end)
	State.Toast:Connect(function(data)
		local s = story()
		-- lore step 9: Your double starts on this hero (its start toast carries mine)
		if data.id == "event" and data.mine and data.num == Config.Events.events.YourDouble.num then
			say("double", "double")
		end
		-- lore step 12: your own new reputation tier
		if data.id == "repUnlocks" and type(data.tier) == "number" then
			local name = player:GetAttribute("HeroName")
			sayText(
				"repTier" .. data.tier,
				RepTiers.radioSelf(Config, side(), data.tier, if type(name) == "string" then name else nil)
			)
		end
		if data.id == "levelUp" and s and type(data.level) == "number" then
			local n = GuidePlan.unlockAt(Config, s, data.level)
			if n then
				say("unlock" .. n, "unlock", n)
			end
			-- first-30: the new power slot or move training, once the radio is free (after the unlock line)
			local power = GuidePlan.powerAt(Config, data.level)
			if power then
				powerLine =
					{ key = "power" .. data.level, line = power, till = os.clock() + G.radio.powerWait }
			end
		end
	end)
	StoryClient.Broadcast:Connect(function(id)
		local e = Config.Story.ending[id]
		if id == "act1" and e then
			task.delay(e.seconds + G.radio.afterAct, function()
				say("afterAct1", "afterAct1")
			end)
		end
	end)
	HqClient.Changed:Connect(onHq)
	Net.listen("NewsFact", onRepFacts) -- lore step 12
	local acc = 0
	RunService.Heartbeat:Connect(FrameProf.wrap("GuideClient", function(dt)
		acc += dt
		if acc >= 1 then
			acc = 0
			idleStep(os.clock())
			powerStep(os.clock())
		end
	end))
end

return GuideClient
