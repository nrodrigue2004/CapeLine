-- MentorService: mentors (spec: Hero MMO features > Original mentors; H6). After the opening a hero picks one
-- of their side's two mentors (the picker card pops once; the MENTOR button keeps it), and can change at any
-- safehouse for free. Mentors are guides and a look, never stats:
-- * comic panels (fixed lines with your hero name) the first time you block, meet your nemesis and clear a
--   task force, and at every 5 levels;
-- * a 4-part quest line (parts open at levels 10, 20, 30 and 40) counting incident clears, robots defeated,
--   contracts, mission clears and world boss rewards; each part pays a mission reward at your level, the last
--   gives the mentor's look (a trail or an aura, worn from the mentor card), their emote and the HQ trophy
--   Mentor's Pride;
-- * the task force's own mentor fights beside the squad in its final fight (an ally on the blocky R15 body
--   that hits the nearest robot every few seconds).
-- Saved per character in mmo (Shared.MentorRules). The worn look is the player attribute MentorLook.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MentorRules = require(Shared:WaitForChild("MentorRules"))
local Net = require(Shared:WaitForChild("Net"))
local NpcRig = require(Shared:WaitForChild("NpcRig"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))
local RigMath = require(Shared:WaitForChild("RigMath"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local Analytics = require(script.Parent.Analytics)
local BlockService = require(script.Parent.BlockService)
local BossService = require(script.Parent.BossService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local EnemyService = require(script.Parent.EnemyService)
local HeroService = require(script.Parent.HeroService)
local IncidentService = require(script.Parent.IncidentService)
local MissionService = require(script.Parent.MissionService)
local NemesisService = require(script.Parent.NemesisService)
local OpeningService = require(script.Parent.OpeningService)
local SafehouseService = require(script.Parent.SafehouseService)
local StoryService = require(script.Parent.StoryService)
local TaskForceService = require(script.Parent.TaskForceService)

local MentorService = {}
MentorService.Picked = Signal.new() -- (player, mentor index)
MentorService.LineDone = Signal.new() -- (player, mentor index) a quest line finished (badges, H7)

local M = Config.Mentors

local asked: { [Player]: boolean } = {} -- the picker card popped this session
type Ally = { model: Model, root: BasePart, run: any, mentor: number, nextAt: number }
local allies: { [any]: Ally } = {} -- per task force run

local function mmo(player: Player): any?
	local c = StoryService.char(player)
	return c and c.mmo
end

local function heroName(player: Player): string
	local c = StoryService.char(player)
	return (c and c.name ~= "" and c.name) or player.DisplayName
end

local function openingDone(player: Player): boolean
	local st = StoryService.story(player)
	return st ~= nil and st.opening == 1
end

local function setLook(player: Player)
	local s = mmo(player)
	local m = s and M.list[s.mentorLook]
	player:SetAttribute("MentorLook", if m then m.look.id else nil)
end

local function card(player: Player)
	local s = mmo(player)
	local hero = HeroService.get(player)
	if not s or not hero then
		return
	end
	local pos = HeroService.position(hero)
	local part = MentorRules.openPart(M, s, hero.level)
	Net.fire("MentorState", player, {
		k = "card",
		mentor = s.mentor,
		side = StoryService.side(player),
		parts = table.clone(s.mentorParts),
		count = table.clone(s.mentorCount),
		open = part or 0,
		level = hero.level,
		look = s.mentorLook,
		atSafe = pos ~= nil and SafehouseService.at(pos) ~= nil,
		canPick = openingDone(player),
	})
end

local function panel(player: Player, moment: string, level: number?)
	local s = mmo(player)
	if not s or s.mentor == 0 then
		return
	end
	local line = MentorRules.line(M, s.mentor, moment, heroName(player), level)
	if line then
		Net.fire("MentorState", player, { k = "panel", mentor = s.mentor, line = line })
	end
end

local function firstTime(player: Player, moment: string)
	local s = mmo(player)
	if s and s.mentor ~= 0 and MentorRules.firstTime(M, s, moment) then
		panel(player, moment)
		DataService.saveSoon(player)
	end
end

-- Something the quest line counts happened for this player
local function count(player: Player, kind: string, n: number?)
	local s = mmo(player)
	local hero = HeroService.get(player)
	if not s or not hero or s.mentor == 0 then
		return
	end
	local before = table.clone(s.mentorCount)
	local done = MentorRules.count(M, s, hero.level, kind, n)
	if done then
		EconomyService.reward(player, "mission", hero.level)
		Net.fire("Toast", player, { id = "mentorPart", part = done, of = #M.quest })
		if MentorRules.lineDone(M, s, s.mentor) then
			local mentor = M.list[s.mentor]
			local profile = DataService.get(player)
			if profile then
				ProfileSchema.Bits.set(profile.emotes, mentor.emote)
			end
			s.mentorLook = s.mentor
			setLook(player)
			panel(player, "questDone")
			Net.fire("MentorState", player, { k = "reward", mentor = s.mentor })
			MentorService.LineDone:Fire(player, s.mentor)
			Analytics.event(player, "mentor_line_done", 1, { mentor.id })
			DataService.changed(player)
		end
		DataService.saveSoon(player)
		card(player)
	elseif s.mentorCount[1] ~= before[1] or s.mentorCount[2] ~= before[2] then
		DataService.saveSoon(player)
	end
end

local function pick(player: Player, i: number)
	local s = mmo(player)
	local hero = HeroService.get(player)
	if not s or not hero then
		return
	end
	local pos = HeroService.position(hero)
	local ok = MentorRules.canPick(
		M,
		s,
		i,
		StoryService.side(player),
		openingDone(player),
		pos ~= nil and SafehouseService.at(pos) ~= nil
	)
	if not ok then
		card(player)
		return
	end
	local first = s.mentor == 0
	MentorRules.pick(M, s, i)
	if first then
		MentorRules.firstTime(M, s, "pick")
	end
	panel(player, "pick")
	MentorService.Picked:Fire(player, i)
	Analytics.event(player, "mentor_pick", 1, { M.list[i].id, if first then "first" else "change" })
	DataService.saveSoon(player)
	card(player)
end

local function wear(player: Player, i: number)
	local s = mmo(player)
	if not s or not MentorRules.canWear(M, s, i) then
		return
	end
	s.mentorLook = i
	setLook(player)
	DataService.saveSoon(player)
	card(player)
end

-- After the opening, with no mentor (or one of the other side after a side change): the picker card, once
local function maybeAsk(player: Player)
	local s = mmo(player)
	if not s or asked[player] or not openingDone(player) then
		return
	end
	local side = StoryService.side(player)
	if s.mentor ~= 0 and not MentorRules.fits(M, s, side) then
		s.mentor = 0 -- a side change: pick again (earned looks stay wearable on either side)
	end
	if s.mentor == 0 then
		asked[player] = true
		Net.fire("MentorState", player, { k = "pick", side = side, options = MentorRules.forSide(M, side) })
	end
end

---------------------------------------------------------------------------
-- The ally in a task force's final fight
---------------------------------------------------------------------------

local allyLayout = RigMath.layout(Config.HeroRig, nil, 1)

local function color(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function spawnAlly(run: any, mentor: number)
	local m = M.list[mentor]
	local pts = run.layout and run.layout.points
	local p = pts and (pts.boss or pts.spawn)
	if not m or not p then
		return
	end
	local rig = NpcRig.person(
		allyLayout,
		"Mentor" .. m.id,
		color(m.colors[1]),
		color(m.colors[2]),
		Color3.fromRGB(235, 200, 160),
		color(m.colors[2])
	)
	local off = M.ally.offset
	local at = Vector3.new(p[1] + off[1], p[2] + off[2], p[3] + off[3])
	rig.model.Parent = run.model
	NpcRig.place(rig, CFrame.new(at))
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(180, 28)
	tag.StudsOffset = Vector3.new(0, 4.4, 0)
	tag.MaxDistance = 120
	tag.AlwaysOnTop = true
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Bangers
	label.TextScaled = true
	label.TextColor3 = color(m.colors[2])
	label.TextStrokeTransparency = 0.3
	label.Text = m.name -- a fixed name from Config.Mentors
	label.Parent = tag
	tag.Parent = rig.parts.Head
	allies[run] = { model = rig.model, root = rig.root, run = run, mentor = mentor, nextAt = os.clock() + 1 }
	for _, pl in run.members do
		if pl.Parent then
			panel(pl, "ally")
		end
	end
end

local function nearestRobot(at: Vector3, reach: number): (number?, any)
	local best, bestD, bestE = nil, reach, nil
	for _, c in EnemyService.candidates() do
		if c.id and c.alive ~= false and c.x then
			local d = (Vector3.new(c.x, c.y or at.Y, c.z) - at).Magnitude
			if d < bestD then
				best, bestD, bestE = c.id, d, c
			end
		end
	end
	return best, bestE
end

local function stepAllies()
	local now = os.clock()
	-- a final fight starting: the task force's mentor joins
	local seen: { [any]: boolean } = {}
	for _, player in Players:GetPlayers() do
		local run = MissionService.runOf(player)
		if run and not seen[run] then
			seen[run] = true
			local final = run.tf and run.leg and run.m and run.m.legs and run.leg >= run.m.legs
			local tf = run.tf and Config.TaskForce.list[run.tf]
			local lastStep = run.stage ~= nil and run.stages ~= nil and run.stage >= run.stages
			if final and lastStep and tf and tf.mentor and not allies[run] then
				local i = MentorRules.indexOf(M, tf.mentor)
				if i then
					spawnAlly(run, i)
				end
			end
		end
	end
	for run, a in allies do
		if run.done or not seen[run] or not a.model.Parent then
			if a.model.Parent then
				a.model:Destroy()
			end
			allies[run] = nil
		elseif now >= a.nextAt then
			a.nextAt = now + M.ally.every
			local at = a.root.Position
			local id, c = nearestRobot(at, M.ally.reach)
			local e = id and EnemyService.get(id)
			local amount, to = 0, nil
			local track = run.tracks and run.tracks.both
			local wf = track and track.wf
			if id and e and e.alive then
				local share = if id == MissionService.bossOf(run) then M.ally.bossShare else M.ally.share
				amount, to = (e.maxHealth or 0) * share, Vector3.new(e.x, e.y, e.z)
			elseif id and c and EnemyService.target(id) and wf and wf.sim then
				-- the battle form's parts are targets: a boss share of its health
				amount, to = wf.sim.maxHp * M.ally.bossShare, Vector3.new(c.x, c.y, c.z)
			end
			if id and to and amount > 0 then
				EnemyService.damage(id, math.max(1, math.floor(amount)), nil, at)
				for _, pl in run.members do
					if pl.Parent then
						Net.fire("MentorState", pl, { k = "assist", from = at, to = to, mentor = a.mentor })
					end
				end
			end
		end
	end
end

function MentorService.state(player: Player): any?
	return mmo(player)
end

function MentorService.init()
	Net.on("MentorOpen", card)
	Net.on("MentorPick", pick)
	Net.on("MentorWear", wear)
	HeroService.Spawned:Connect(function(hero: any)
		local player = hero.player
		if player then
			task.delay(3, function()
				if player.Parent then
					setLook(player)
					maybeAsk(player)
				end
			end)
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		asked[p] = nil
	end)
	-- the picker pops as the prologue ends (the hero is back in the plaza, after the Suit Up beat)
	OpeningService.Finished:Connect(function(player: Player)
		task.delay(Config.Mentors.afterOpening, function()
			if player.Parent then
				maybeAsk(player)
			end
		end)
	end)
	-- the panels
	BlockService.Outcome:Connect(function(hero: any, outcome: string)
		if hero and hero.player and (outcome == "blocked" or outcome == "perfect") then
			firstTime(hero.player, "firstBlock")
		end
	end)
	NemesisService.Met:Connect(function(player: Player)
		firstTime(player, "firstNemesis")
	end)
	TaskForceService.Done:Connect(function(player: Player)
		firstTime(player, "firstTaskForce")
	end)
	HeroService.Leveled:Connect(function(hero: any, gained: number)
		if hero.player then
			local levels = MentorRules.levelPanels(M, hero.level - gained, hero.level)
			if #levels > 0 then
				panel(hero.player, "level", levels[#levels])
			end
			maybeAsk(hero.player)
		end
	end)
	-- the quest line's counts
	IncidentService.Cleared:Connect(function(inc: any)
		for heroId in inc.helpers or {} do
			local h = HeroService.byId(heroId)
			if h and h.player then
				count(h.player, "incident")
			end
		end
	end)
	EnemyService.Killed:Connect(function(_kind: string, heroId: number?)
		local h = heroId and HeroService.byId(heroId)
		if h and h.player then
			count(h.player, "robot")
		end
	end)
	EconomyService.Earned:Connect(function(player: Player, action: string)
		if action == "contract" then
			count(player, "contract")
		end
	end)
	MissionService.Cleared:Connect(function(player: Player)
		count(player, "mission")
	end)
	BossService.Rewarded:Connect(function(player: Player)
		count(player, "boss")
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			stepAllies()
		end
	end)
end

return MentorService
