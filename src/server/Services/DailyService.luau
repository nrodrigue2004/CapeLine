-- DailyService: the daily login streak and daily quests (spec: Update 1 > "daily quests and login streak";
-- gap G1, WP1). Rules in Shared.DailyRules, numbers in Config.Daily, the save in profile.daily (the account's,
-- so a slot switch changes nothing).
-- * The streak: a UTC day's login counts when the profile loads (and at 00:00 UTC for anyone still on). Its
--   reward waits for DailyClaim; one claim a day per account, decided here from the save: the visit stamps
--   the day and the claim clears `owed` before anything is paid, both in the same profile as the wallet, so a
--   rejoin or a server hop (DataService's session lock hands the saved profile on) never pays twice, and a
--   server whose clock is behind never counts a day again. A reward still owed at the next day's login is
--   paid then (rule 6: nothing earned is lost). A session that cannot save (DataStore down) counts nothing:
--   the device shows the error state and the streak waits for a working save.
-- * The card: shown once the hero is free (made, the prologue done, no story scene), a few seconds later.
-- * Daily quests: 3 a day from the day's seed, counted from the signals players already make: incidents
--   cleared, citizens rescued (street, events, the Sunken Line), contracts, robots defeated, a world boss hit,
--   side quest steps, city events, throws, and PvP wins that paid (DeathService.PvpWon) only while
--   Config.Daily.pvp is on (those quests also count a non-PvP way). Each quest pays once when it finishes, the all-done bonus once.
-- * Analytics: daily_login, daily_claim, daily_quest, daily_all_done (fields from DailyRules).
-- * Studio (DevService "daily"): a day passes, skip a day (the grace), finish today's quests, start over.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local DailyRules = require(Shared:WaitForChild("DailyRules"))
local Net = require(Shared:WaitForChild("Net"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))

local Analytics = require(script.Parent.Analytics)
local BossService = require(script.Parent.BossService)
local DataService = require(script.Parent.DataService)
local DeathService = require(script.Parent.DeathService)
local EconomyService = require(script.Parent.EconomyService)
local EnemyService = require(script.Parent.EnemyService)
local EventService = require(script.Parent.EventService)
local HeroService = require(script.Parent.HeroService)
local IncidentService = require(script.Parent.IncidentService)
local SideQuestService = require(script.Parent.SideQuestService)
local ThrowService = require(script.Parent.ThrowService)
local BadgeService = require(script.Parent.BadgeService)

local DailyService = {}

local D = Config.Daily
local shown: { [Player]: boolean } = {} -- the card was shown for the reward owed now (once per owed day)

local function level(player: Player, profile: any): number
	local hero = HeroService.get(player)
	if hero and hero.loaded then
		return hero.level
	end
	return ProfileSchema.active(profile).level
end

-- A live profile this session can save, with its hero loaded (Renown needs the hero); nil otherwise:
-- nothing is counted or paid on it
local function saveable(player: Player): any?
	local profile = DataService.get(player)
	local hero = HeroService.get(player)
	if profile and hero and hero.loaded and DataService.isSaving(player) and D.on then
		return profile
	end
	return nil
end

local function pay(player: Player, credits: number, renown: number, dust: number)
	EconomyService.addCredits(player, credits)
	EconomyService.addRenown(player, renown)
	EconomyService.addDust(player, dust)
end

-- The state packet (show: open the claim card)
local function send(player: Player, show: boolean?)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	if not D.on then
		Net.fire("DailyState", player, { on = false })
		return
	end
	if not DataService.isSaving(player) then
		Net.fire("DailyState", player, { on = true, offline = true })
		return
	end
	local now = os.time()
	local v = DailyRules.view(Config, profile.daily, DailyRules.day(Config, now), level(player, profile), now)
	v.show = show == true
	Net.fire("DailyState", player, v)
end
DailyService.send = send

-- Pay a reward DailyRules settled (Credits, Renown, Dust; the title is in the save already)
local function payReward(player: Player, r: DailyRules.Reward, late: boolean)
	pay(player, r.credits, r.renown, r.dust)
	if r.title > 0 then
		BadgeService.book(player) -- the new title shows in the title list
	end
	Analytics.event(player, "daily_claim", DailyRules.claimEvent(r, late))
	Net.fire("DailyProgress", player, {
		kind = "claim",
		day = r.day,
		streak = r.streak,
		credits = r.credits,
		renown = r.renown,
		dust = r.dust,
		title = r.titleName,
		late = late or nil,
	})
end

-- Count today (a later UTC day only) and roll today's quests. Returns true when a new day was counted.
local function roll(player: Player): boolean
	local profile = saveable(player)
	if not profile then
		return false
	end
	local d = profile.daily
	local today = DailyRules.day(Config, os.time())
	local lvl = level(player, profile)
	local counted = false
	local v = DailyRules.visit(Config, d, today)
	if v then
		counted = true
		shown[player] = nil
		if v.late > 0 then
			-- yesterday's reward was never claimed: paid now, never lost
			local r = DailyRules.settle(Config, d, v.late, lvl)
			if r then
				payReward(player, r, true)
			end
		end
		Analytics.event(player, "daily_login", DailyRules.loginEvent(Config, v))
	end
	if DailyRules.roll(Config, d, today, lvl) then
		counted = true
	end
	if counted then
		DataService.changed(player)
		DataService.saveSoon(player)
	end
	return counted
end

-- Free for the card: made, the prologue done, standing in the city (no story scene)
local function free(player: Player): boolean
	local profile = DataService.get(player)
	local hero = HeroService.get(player)
	if not profile or not hero or not hero.loaded or hero.scene then
		return false
	end
	local c = ProfileSchema.active(profile)
	return c.created == 1 and c.story.opening == 1
end

-- Show the claim card once the hero is free (once per owed day)
local function offerCard(player: Player)
	task.spawn(function()
		local waited = 0
		while player.Parent == Players and not free(player) and waited < D.ui.freeWait do
			task.wait(2)
			-- the creator and the prologue are a new hero's first minutes, not a busy hero: they never use up
			-- the wait, so a slow creator plus the prologue still ends with the day's card (onboarding check)
			local hero = HeroService.get(player)
			if not (hero and (hero.scene == "creator" or hero.scene == "opening")) then
				waited += 2
			end
		end
		if player.Parent ~= Players or not free(player) then
			return
		end
		task.wait(D.ui.showAfter)
		local profile = DataService.get(player)
		if player.Parent == Players and profile and not shown[player] then
			shown[player] = true
			send(player, profile.daily.owed > 0)
		end
	end)
end

local function claim(player: Player)
	local profile = saveable(player)
	if not profile then
		send(player) -- not loaded yet, or a save that cannot save: the card's state says why
		return
	end
	roll(player) -- a claim just after 00:00 UTC is for the new day
	local r = DailyRules.claim(Config, profile.daily, level(player, profile))
	if r then
		payReward(player, r, false)
		DataService.changed(player)
		DataService.saveSoon(player)
	end
	send(player)
end

-- Count `n` of a key towards a player's daily quests (paid as each finishes)
function DailyService.count(who: Player?, key: string, n: number?)
	if not who then
		return
	end
	local player = who :: Player
	local profile = saveable(player)
	if not profile then
		return
	end
	roll(player)
	local d = profile.daily
	local finished, moved, all = DailyRules.bump(Config, d, key, n)
	if #moved == 0 then
		return
	end
	local lvl = level(player, profile)
	for _, slot in finished do
		local q = DailyRules.quest(Config, d.quests[slot])
		if q then
			local c, r = DailyRules.questPay(Config, q, lvl)
			pay(player, c, r, 0)
			Analytics.event(player, "daily_quest", DailyRules.questEvent(Config, d, slot))
			Net.fire(
				"DailyProgress",
				player,
				{ kind = "quest", slot = slot, text = q.text, credits = c, renown = r }
			)
		end
	end
	if all then
		local c, r, dust = DailyRules.allPay(Config, lvl)
		pay(player, c, r, dust)
		Analytics.event(player, "daily_all_done", DailyRules.allEvent(Config, d))
		Net.fire("DailyProgress", player, { kind = "all", credits = c, renown = r, dust = dust })
	end
	if #finished == 0 then
		-- a count that moved (a robot, a rescue): the tracker's numbers only, no full state
		for _, slot in moved do
			local q = DailyRules.quest(Config, d.quests[slot])
			Net.fire("DailyProgress", player, {
				kind = "move",
				slot = slot,
				have = d.have[slot],
				n = if q then q.n else 0,
			})
		end
	else
		DataService.changed(player)
		DataService.saveSoon(player)
		send(player)
	end
end

local function playerOf(heroId: number?): Player?
	local hero = heroId and HeroService.byId(heroId)
	return hero and hero.player or nil
end

-- Studio (DevService): 1 a day passes, 2 two days pass (one missed: the grace), 3 finish today's quests,
-- 4 start over (no streak, no titles, no quests)
function DailyService.dev(player: Player, what: number)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local d = profile.daily
	if what == 1 or what == 2 then
		DailyRules.shift(d, what)
	elseif what == 3 then
		for i, id in d.quests do
			local q = DailyRules.quest(Config, id)
			if q and not DailyRules.slotPaid(d, i) then
				DailyService.count(player, q.key, q.n)
			end
		end
	elseif what == 4 then
		local fresh = ProfileSchema.default().daily
		fresh.day, fresh.contractsDone = d.day, d.contractsDone
		profile.daily = fresh
	end
	shown[player] = nil
	roll(player)
	send(player, profile.daily.owed > 0)
end

function DailyService.init()
	Net.on("DailyOpen", function(player: Player)
		roll(player)
		send(player)
	end)
	Net.on("DailyClaim", claim)
	DataService.Loaded:Connect(function(player: Player)
		task.spawn(function()
			-- the day counts once the hero is loaded (a late reward's Renown goes on the hero)
			local waited = 0
			local function ready(): boolean
				local hero = HeroService.get(player)
				return hero ~= nil and hero.loaded
			end
			while player.Parent == Players and not ready() and waited < D.ui.freeWait do
				task.wait(1)
				waited += 1
			end
			if player.Parent ~= Players then
				return
			end
			roll(player)
			send(player) -- the tracker (the card waits until the hero is free)
			offerCard(player)
		end)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		shown[player] = nil
	end)
	-- the signals players already make
	IncidentService.Cleared:Connect(function(inc: any)
		for heroId in inc.helpers or {} do
			DailyService.count(playerOf(heroId), "incident")
		end
	end)
	EconomyService.Earned:Connect(function(player: Player, action: any)
		if action == "contract" then
			DailyService.count(player, "contract")
		elseif action == "rescue" or action == "deepRescue" then
			DailyService.count(player, "rescue")
		end
	end)
	EnemyService.Killed:Connect(function(_kind: string, heroId: number?)
		DailyService.count(playerOf(heroId), "kill")
	end)
	BossService.Joined:Connect(function(hero: any)
		DailyService.count(hero and hero.player, "boss")
	end)
	SideQuestService.StepPaid:Connect(function(player: Player)
		DailyService.count(player, "sideQuest")
	end)
	EventService.Paid:Connect(function(player: Player)
		DailyService.count(player, "event")
	end)
	ThrowService.Thrown:Connect(function(hero: any)
		DailyService.count(hero and hero.player, "throw")
	end)
	-- only a PvP win that paid (past the anti-farming ledger, like the weekly PvP board): two friends trading
	-- defeats never finish a PvP quest (review 2026-11-18; was every PvP defeat)
	DeathService.PvpWon:Connect(function(winner: any)
		DailyService.count(winner and winner.player, "pvpWin")
	end)
	-- 00:00 UTC for everyone still on: count the new day and offer its card
	task.spawn(function()
		local last = DailyRules.day(Config, os.time())
		while true do
			task.wait(15)
			local today = DailyRules.day(Config, os.time())
			if today ~= last then
				last = today
				for _, player in Players:GetPlayers() do
					if roll(player) then
						send(player)
						offerCard(player)
					end
				end
			end
		end
	end)
end

return DailyService
