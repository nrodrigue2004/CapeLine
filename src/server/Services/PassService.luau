-- PassService: the Hero Pass and the weekly episode (spec: Hero MMO features > The Hero Pass, Weekly episodes;
-- H8). Rules in Shared.PassRules, numbers in Config.Pass and Config.Episodes.
-- * Seasons and weeks follow os.time (Monday 00:00 UTC, the world seed's weeks): a profile rolls to the live
--   season and week when it loads, on each spawn and once a minute.
-- * Pass XP from everything: incidents, contracts, missions, task forces, world bosses, the episode, costume
--   contests, badges and collection finds; the first win of the UTC day adds the daily bonus. The 2x pass
--   never touches it. PassXp tells the device (the tier-up card and the mission results card).
-- * PassClaim: a reached tier's reward once per track (the paid track needs the season's receipt, which
--   ShopRules.grant sets from the heroPass product). Looks go into their stores, Credits and Dust are paid
--   here. No tier skips, nothing random, nothing with a stat.
-- * The episode: free for everyone and standalone (never the main story). Its steps count the same signals;
--   each step pays Renown and Pass XP, all four add more and the week's badge. Its theme tilts the random
--   events' mix (EventService reads PassRules.eventWeights).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local BossMath = require(Shared:WaitForChild("BossMath"))
local PassRules = require(Shared:WaitForChild("PassRules"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))

local Analytics = require(script.Parent.Analytics)
local BadgeService = require(script.Parent.BadgeService)
local BossService = require(script.Parent.BossService)
local CollectService = require(script.Parent.CollectService)
local ContestService = require(script.Parent.ContestService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local EnemyService = require(script.Parent.EnemyService)
local HeroService = require(script.Parent.HeroService)
local IncidentService = require(script.Parent.IncidentService)
local MissionService = require(script.Parent.MissionService)
local TaskForceService = require(script.Parent.TaskForceService)

local PassService = {}

local P = Config.Pass
local E = Config.Episodes
local Bits = ProfileSchema.Bits

-- Roll a profile to the live season and week. Returns this week's episode and its number.
local function roll(profile: any): (any?, number)
	local now = os.time()
	local season = PassRules.season(P, now)
	PassRules.roll(profile.pass, season)
	local ep, e, week = PassRules.episode(Config, now)
	PassRules.episodeRoll(profile.episode, week)
	return ep, e
end

local function seasonEnds(season: number): number
	local w = P.startWeek + season * P.weeks
	return (w * 7 - 3) * 86400
end

-- The pass and episode card's packet
local function sendState(player: Player, claimed: { number }?)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local ep, e = roll(profile)
	local pass = profile.pass
	local d = PassRules.data(P, pass.season)
	local steps = {}
	if ep then
		for i, st in ep.steps do
			table.insert(steps, {
				text = st.text,
				n = st.n,
				have = profile.episode.counts[i] or 0,
				done = PassRules.stepDone(profile.episode, i),
			})
		end
	end
	local _, week = PassRules.season(P, os.time())
	Net.fire("PassState", player, {
		open = d ~= nil,
		season = pass.season,
		seasonName = d and d.name or "",
		week = week,
		endsAt = seasonEnds(pass.season),
		now = os.time(),
		xp = pass.xp,
		tier = PassRules.tier(P, pass.xp),
		paid = pass.paid,
		claimedFree = Bits.list(pass.claimed.free),
		claimedPaid = Bits.list(pass.claimed.paid),
		trims = Bits.list(pass.trims),
		dailyReady = pass.day ~= PassRules.day(os.time()),
		claimed = claimed,
		episode = ep and {
			num = e,
			name = ep.name,
			theme = ep.theme,
			panels = ep.panels,
			steps = steps,
			done = PassRules.episodeDone(ep, profile.episode),
			intro = profile.episode.intro ~= profile.episode.week,
			endsAt = PassRules.weekEnds(os.time()),
		} or nil,
	})
end
PassService.sendState = sendState

-- Pass XP for an action. kind: a Config.Pass.dailyKinds key earns the first-win bonus once a day.
function PassService.xp(player: Player, n: number, kind: string?, reason: string?)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	roll(profile)
	if not PassRules.data(P, profile.pass.season) then
		return -- no season running (no rewards written for it)
	end
	local add, before, after = PassRules.addXp(P, profile.pass, n, kind, PassRules.day(os.time()))
	if add <= 0 then
		return
	end
	Net.fire("PassXp", player, {
		add = add,
		xp = profile.pass.xp,
		tier = after,
		before = before,
		reason = reason or kind,
		daily = add > n,
	})
	if after > before then
		Analytics.event(player, "pass_tier", after, { tostring(profile.pass.season) })
	end
	DataService.saveSoon(player)
end

-- Count towards this week's episode steps
function PassService.count(player: Player, key: string, n: number?)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local ep, e = roll(profile)
	if not ep then
		return
	end
	local steps, finished = PassRules.bump(ep, profile.episode, key, n)
	for _, i in steps do
		EconomyService.addRenown(player, E.stepRenown)
		PassService.xp(player, E.stepXp, nil, "episode")
		Net.fire("Toast", player, { id = "episodeStep", text = ep.steps[i].text, renown = E.stepRenown })
		Analytics.event(player, "episode_step", i, { ep.name })
	end
	if finished then
		EconomyService.addRenown(player, E.doneRenown)
		PassService.xp(player, E.doneXp, nil, "episode")
		BadgeService.bump(player, "episode:" .. e)
		Net.fire("Toast", player, { id = "episodeDone", name = ep.name, renown = E.doneRenown })
		Analytics.event(player, "episode_done", 1, { ep.name })
	end
	if #steps > 0 then
		sendState(player)
		DataService.saveSoon(player)
	end
end

local function claim(player: Player, tier: number, track: number)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	roll(profile)
	local paid = track == 1
	local ok, row = PassRules.claim(Config, profile, tier, paid)
	if not ok or not row then
		sendState(player)
		return
	end
	if row.kind == "credits" then
		EconomyService.addCredits(player, row.v)
	elseif row.kind == "dust" then
		EconomyService.addDust(player, row.v)
	end
	Analytics.event(player, "pass_claim", tier, { if paid then "paid" else "free", row.kind })
	if row.kind == "title" or row.kind == "trim" then
		BadgeService.book(player)
	end
	DataService.changed(player)
	DataService.saveSoon(player)
	sendState(player, { tier, track })
end

local function seen(player: Player)
	local profile = DataService.get(player)
	if profile then
		roll(profile)
		profile.episode.intro = profile.episode.week
		DataService.saveSoon(player)
	end
end

local function playerOf(heroId: number?): Player?
	local hero = heroId and HeroService.byId(heroId)
	return hero and hero.player or nil
end

function PassService.init()
	Net.on("PassOpen", function(player: Player)
		sendState(player)
	end)
	Net.on("PassClaim", claim)
	Net.on("EpisodeSeen", seen)
	DataService.Loaded:Connect(function(player: Player, profile: any)
		roll(profile)
		task.delay(6, function()
			if player.Parent then
				sendState(player) -- the device shows this week's intro panels once
			end
		end)
	end)
	-- Pass XP and the episode's steps
	IncidentService.Cleared:Connect(function(inc: any)
		for heroId in inc.helpers or {} do
			local player = playerOf(heroId)
			if player then
				PassService.xp(player, P.xp.incident, "incident", "incident")
				PassService.count(player, "incident")
				if inc.plan and inc.plan.tid then
					PassService.count(player, "incident:" .. inc.plan.tid)
				end
			end
		end
	end)
	EconomyService.Earned:Connect(function(player: Player, action: any)
		if action == "contract" then
			PassService.xp(player, P.xp.contract, "contract", "contract")
			PassService.count(player, "contract")
		elseif action == "rescue" or action == "deepRescue" then
			PassService.count(player, "rescue")
		end
	end)
	MissionService.Cleared:Connect(function(player: Player, _num: any, info: any)
		if not (info and info.taskForce) then
			PassService.xp(player, P.xp.mission, "mission", "mission")
			PassService.count(player, "mission")
		end
	end)
	TaskForceService.Done:Connect(function(player: Player)
		PassService.xp(player, P.xp.taskForce, "taskForce", "mission")
		PassService.count(player, "taskForce")
	end)
	BossService.Rewarded:Connect(function(player: Player, _bossId: any, tier: string, defeated: boolean)
		-- the tier is a string ("mvp" .. "floor"); comparing it with a number threw out of the boss's reward loop
		if BossMath.tookPart(tier) then
			PassService.xp(player, P.xp.boss, if defeated then "boss" else nil, "boss")
			PassService.count(player, "boss")
		end
	end)
	EnemyService.Killed:Connect(function(kind: string, heroId: number?)
		local player = playerOf(heroId)
		if player then
			PassService.count(player, "kill")
			PassService.count(player, "kill:" .. kind)
		end
	end)
	BadgeService.Earned:Connect(function(player: Player)
		PassService.xp(player, P.xp.badge, nil, "badge")
	end)
	CollectService.Found:Connect(function(player: Player)
		PassService.xp(player, P.xp.find, nil, "find")
		PassService.count(player, "find")
	end)
	ContestService.Entered:Connect(function(player: Player)
		PassService.xp(player, P.xp.contestEnter, nil, "contest")
		PassService.count(player, "contest")
	end)
	ContestService.Placed:Connect(function(player: Player, place: number)
		if place <= 3 then
			PassService.xp(player, P.xp.contestPodium, nil, "contest")
		end
	end)
	-- a new season or week mid-session
	task.spawn(function()
		local lastWeek = PassRules.week(os.time())
		while true do
			task.wait(60)
			local w = PassRules.week(os.time())
			if w ~= lastWeek then
				lastWeek = w
				for _, player in Players:GetPlayers() do
					sendState(player)
				end
			end
		end
	end)
end

return PassService
