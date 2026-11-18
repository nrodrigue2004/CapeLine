-- BadgeService: badges and titles (spec: Hero MMO features > Badges and titles; H7). About 120 badges for
-- doing things (Config.Badges, Shared.BadgeRules), saved on the account (profile.mmo.badges and counts):
-- * counters from the game's signals (robots by kind, elites, world bosses, rescues of cats and Sunken Line
--   riders, revives, blocks, perfect blocks, interrupts, breaks, throws, Awakenings, mission, task force and
--   Showdown clears, contests) and position checks once a second (areas, the deep, heights, the Trench
--   floor, time underwater);
-- * facts read from the save (story clears and choices across your heroes, side quest chains, safehouses and
--   beacons found, styles and emotes owned, full collections, Fame rank, PvP wins);
-- * a new badge: a stamp, a chime and confetti for you (BadgeEarned), and a toast for squadmates near you;
-- * accolades: a group finished gives its aura, plate trim or emote (worn from the Badge Book); never stats;
-- * titles: one shown under your name (TitleSet), from your origin, the story and Fame titles, your badges
--   and your banes; all fixed text. The shown title rides on the player attribute Title.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BadgeRules = require(Shared:WaitForChild("BadgeRules"))
local CollectPlan = require(Shared:WaitForChild("CollectPlan"))
local DeepLayout = require(Shared:WaitForChild("DeepLayout"))
local Net = require(Shared:WaitForChild("Net"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))
local StoryPlan = require(Shared:WaitForChild("StoryPlan"))
local SideQuestPlan = require(Shared:WaitForChild("SideQuestPlan"))
local ZoneLevel = require(Shared:WaitForChild("ZoneLevel"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local Analytics = require(script.Parent.Analytics)
local BlockService = require(script.Parent.BlockService)
local BossService = require(script.Parent.BossService)
local CityBuilder = require(script.Parent.CityBuilder)
local DataService = require(script.Parent.DataService)
local DeathService = require(script.Parent.DeathService)
local EconomyService = require(script.Parent.EconomyService)
local EnemyService = require(script.Parent.EnemyService)
local HeroService = require(script.Parent.HeroService)
local IncidentService = require(script.Parent.IncidentService)
local MentorService = require(script.Parent.MentorService)
local MissionService = require(script.Parent.MissionService)
local NemesisService = require(script.Parent.NemesisService)
local SquadService = require(script.Parent.SquadService)
local TaskForceService = require(script.Parent.TaskForceService)
local ThrowService = require(script.Parent.ThrowService)

local BadgeService = {}
BadgeService.Earned = Signal.new() -- (player, entry) a badge was earned (the Hero Pass pays XP, H8)

local B = Config.Badges
local Bits = ProfileSchema.Bits

local dirty: { [Player]: boolean } = {}

local function mmoOf(player: Player): (any?, any?)
	local profile = DataService.get(player)
	return profile and profile.mmo, profile
end

local function popcount(n: number): number
	local c = 0
	while n > 0 do
		c += n % 2
		n = n // 2
	end
	return c
end

-- What the save itself says (facts win over counters of the same key)
local function facts(player: Player, profile: any): { [string]: number }
	local f: { [string]: number } = {}
	local c = ProfileSchema.active(profile)
	f.safehouses = popcount(c.safehouses or 0)
	f.safehousesAll = if f.safehouses >= #Config.World.safehouses then 1 else 0
	f.beacons = popcount(c.beacons or 0)
	f.beaconsAll = if f.beacons >= #Config.World.beacons then 1 else 0
	-- the story across every hero on the account
	local picked: { [number]: { [number]: boolean } } = {}
	local quests = false
	for _, ch in profile.characters do
		local st = ch.story
		if st then
			for n = 1, #Config.Story.missions do
				if StoryPlan.cleared(st, n) then
					f["mission:" .. n] = 1
				end
			end
			if StoryPlan.cleared(st, #Config.Story.missions) then
				f["act1:" .. (ch.side or "hero")] = 1
			end
			for i, o in st.choices or {} do
				if o ~= 0 then
					picked[i] = picked[i] or {}
					picked[i][o] = true
				end
			end
			quests = quests or SideQuestPlan.allDone(Config, ch) -- lore step 10: every chain or retired arc
		end
	end
	for i, set in picked do
		f["bothChoices:" .. i] = if set[1] and set[2] then 1 else 0
	end
	f.quests = if quests then 1 else 0
	f.styles = #Bits.list(profile.styles)
	f.emotes = #Bits.list(profile.emotes)
	f.fullSets = CollectPlan.fullSets(Config.Collect, profile.mmo.collect)
	f.rescues = profile.stats.rescues or 0
	f.pvpWins = profile.stats.wins or 0
	local rank = player:GetAttribute("FameRank")
	f.fameRank = if typeof(rank) == "number" then rank else 0
	return f
end

local function have(player: Player, profile: any): { [string]: number }
	return BadgeRules.have(profile.mmo.counts, facts(player, profile))
end

-- Squadmates near you see a toast too
local function tellMates(player: Player, e: BadgeRules.Entry)
	local hero = HeroService.get(player)
	local at = hero and HeroService.position(hero)
	for _, mate in SquadService.mates(player) do
		local h = HeroService.get(mate)
		local p = h and HeroService.position(h)
		if at and p and (p - at).Magnitude <= B.squadToast then
			Net.fire("Toast", mate, { id = "badgeMate", who = player.DisplayName, name = e.name })
		end
	end
end

-- Give every badge the numbers now earn
function BadgeService.check(player: Player)
	local mmo, profile = mmoOf(player)
	if not mmo or not profile then
		return
	end
	local before = BadgeRules.accolades(B, mmo.badges)
	local new = BadgeRules.earn(B, mmo.badges, have(player, profile))
	if #new == 0 then
		return
	end
	for _, e in new do
		Net.fire("BadgeEarned", player, { bit = e.bit, name = e.name, group = e.groupName })
		tellMates(player, e)
		Analytics.event(player, "badge_earned", 1, { e.id })
		BadgeService.Earned:Fire(player, e)
	end
	-- a group finished: its accolade (an emote goes in the emote bits; auras and trims are worn from the book)
	local after = BadgeRules.accolades(B, mmo.badges)
	if #after > #before then
		for _, a in after do
			if a.kind == "emote" then
				Bits.set(profile.emotes, a.emote)
			end
		end
		Net.fire("Toast", player, { id = "accolade", name = after[#after].name })
		DataService.changed(player)
	end
	DataService.saveSoon(player)
end

-- Count something for a player (counters live on the account); the check runs on the next second
function BadgeService.bump(player: Player, key: string, n: number?)
	local mmo = mmoOf(player)
	if mmo then
		BadgeRules.bump(B, mmo.counts, key, n)
		dirty[player] = true
	end
end

local function bumpHero(hero: any, key: string, n: number?)
	if hero and hero.player then
		BadgeService.bump(hero.player, key, n)
	end
end

---------------------------------------------------------------------------
-- Titles and accolade looks
---------------------------------------------------------------------------

local function charOf(player: Player): (any?, any?)
	local profile = DataService.get(player)
	return profile, profile and ProfileSchema.active(profile)
end

local function showTitle(player: Player)
	local profile, c = charOf(player)
	if not profile or not c then
		return
	end
	local id = c.mmo.title
	-- 0 shows the origin's title the creator already puts on the plate (OriginTitle)
	local text = if id ~= 0 then BadgeRules.titleText(Config, profile, c, id) else nil
	player:SetAttribute("Title", text)
	-- accolade looks: the worn aura and trim (indices into Config.Badges.groups; 0 = none)
	local aura = B.groups[c.mmo.aura or 0]
	local trim = B.groups[c.mmo.trim or 0]
	local done = BadgeRules.accolades(B, profile.mmo.badges)
	local function owned(g: any): boolean
		return g ~= nil and table.find(done, g.accolade) ~= nil
	end
	player:SetAttribute("AccoladeAura", if owned(aura) then aura.accolade.id else nil)
	local passTrim = BadgeService.passTrim(profile, c.mmo.trim or 0)
	player:SetAttribute(
		"PlateTrim",
		if passTrim then passTrim.id elseif owned(trim) then trim.accolade.id else nil
	)
end

-- H8: a Hero Pass plate trim (mmo.trim = Config.Pass.trimBase + n) the account owns, or nil
function BadgeService.passTrim(profile: any, value: number): any?
	local P = Config.Pass
	local n = value - P.trimBase
	if n < 1 or not P.trims[n] or not Bits.get(profile.pass.trims, n) then
		return nil
	end
	return P.trims[n]
end

-- The Badge Book's packet: earned bits, progress numbers, titles, accolades
local function book(player: Player)
	local profile, c = charOf(player)
	if not profile or not c then
		return
	end
	local h = have(player, profile)
	local progress = {}
	for _, e in BadgeRules.list(B) do
		local got, need = BadgeRules.progress(B, profile.mmo.badges, h, e)
		progress[tostring(e.bit)] = { got, need }
	end
	local accolades = {}
	for i, g in B.groups do
		if g.accolade and table.find(BadgeRules.accolades(B, profile.mmo.badges), g.accolade) then
			table.insert(accolades, i)
		end
	end
	Net.fire("BadgeBook", player, {
		bits = Bits.list(profile.mmo.badges),
		progress = progress,
		titles = BadgeRules.titles(Config, profile, c),
		title = c.mmo.title,
		accolades = accolades,
		aura = c.mmo.aura or 0,
		trim = c.mmo.trim or 0,
		collect = Bits.list(profile.mmo.collect),
		scanner = profile.mmo.scanner,
	})
end
BadgeService.book = book

local function setTitle(player: Player, id: number)
	local profile, c = charOf(player)
	if not profile or not c then
		return
	end
	if id == 0 or BadgeRules.titleText(Config, profile, c, id) then
		c.mmo.title = id
		showTitle(player)
		DataService.saveSoon(player)
	end
	book(player)
end

-- Wear an accolade's aura or trim (group index; 0 = none)
local function wear(player: Player, slot: number, group: number)
	local profile, c = charOf(player)
	if not profile or not c then
		return
	end
	local g = B.groups[group]
	local kind = if slot == 1 then "aura" else "trim"
	-- H8: a Hero Pass trim (Config.Pass.trimBase + n)
	if slot == 2 and group > Config.Pass.trimBase then
		if BadgeService.passTrim(profile, group) then
			c.mmo.trim = group
			showTitle(player)
			DataService.saveSoon(player)
		end
		book(player)
		return
	end
	if group == 0 or (g and g.accolade and g.accolade.kind == kind) then
		if group ~= 0 and not table.find(BadgeRules.accolades(B, profile.mmo.badges), g.accolade) then
			return
		end
		c.mmo[kind] = group
		showTitle(player)
		DataService.saveSoon(player)
	end
	book(player)
end

---------------------------------------------------------------------------
-- Where heroes are (once a second): areas, the deep, heights
---------------------------------------------------------------------------

local underwaterFor: { [Player]: number } = {}

local function explore(player: Player, hero: any, dt: number)
	local p = HeroService.position(hero)
	if not p or hero.scene then
		return -- a mission pocket or the HQ is no place in the city
	end
	local mmo = mmoOf(player)
	if not mmo then
		return
	end
	local x, y, z = p.X, p.Y, p.Z
	local function seen(key: string)
		if (mmo.counts[key] or 0) == 0 then
			mmo.counts[key] = 1
			dirty[player] = true
		end
	end
	for name, d in Config.City.districts do
		if x >= d.minX and x < d.maxX and z >= d.minZ and z < d.maxZ then
			seen("area:" .. name)
		end
	end
	local world = CityBuilder.world
	seen("area:" .. ZoneLevel.area(Config, x, z, world and world.tiles))
	if DeepLayout.underwater(Config, x, y, z) then
		local deep = DeepLayout.area(Config, x, z, y)
		if deep then
			seen("deep:" .. deep)
		end
		local floor = DeepLayout.floorAt(Config, x, z, y)
		if deep == "trench" and floor and y <= floor + 6 then
			seen("trenchFloor")
		end
		underwaterFor[player] = (underwaterFor[player] or 0) + dt
		if underwaterFor[player] >= 5 then
			BadgeService.bump(player, "underwater", math.floor(underwaterFor[player]))
			underwaterFor[player] = 0
		end
	end
	local up = math.floor(y - Config.City.ground.y)
	if up > (mmo.counts.height or 0) then
		BadgeService.bump(player, "height", up)
	end
end

function BadgeService.init()
	Net.on("BadgeOpen", book)
	Net.on("TitleSet", setTitle)
	Net.on("AccoladeWear", wear)
	HeroService.Spawned:Connect(function(hero: any)
		local player = hero.player
		if player then
			task.delay(2, function()
				if player.Parent then
					showTitle(player)
					dirty[player] = true
				end
			end)
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		dirty[p] = nil
		underwaterFor[p] = nil
	end)
	-- Defeat
	EnemyService.Killed:Connect(function(kind: string, heroId: number?)
		local hero = heroId and HeroService.byId(heroId)
		if hero and hero.player then
			BadgeService.bump(hero.player, "kill:" .. kind)
			BadgeService.bump(hero.player, "kills")
			local def = Config.Enemies[kind]
			if def and def.elite then
				BadgeService.bump(hero.player, "elites")
			end
		end
	end)
	BossService.Rewarded:Connect(function(player: Player, bossId: any, _tier: string, defeated: boolean)
		if defeated then
			BadgeService.bump(player, "boss:" .. tostring(bossId))
		end
	end)
	-- Rescue
	IncidentService.Cleared:Connect(function(inc: any)
		local n = 0
		for _ in inc.helpers or {} do
			n += 1
		end
		for heroId in inc.helpers or {} do
			local h = HeroService.byId(heroId)
			if inc.plan and inc.plan.tid == "CatOnCrane" then
				bumpHero(h, "cats")
			end
			if n >= 2 then
				bumpHero(h, "squadIncidents")
			end
		end
	end)
	IncidentService.Rescued:Connect(function(hero: any)
		bumpHero(hero, "rescuesSeen") -- the fact reads profile.stats.rescues; this wakes the check
	end)
	-- WP5: a Suspicious Hero's mask cracked: everyone who hit it unmasked a fake
	IncidentService.FakeUnmasked:Connect(function(inc: any)
		for heroId in inc.helpers or {} do
			bumpHero(HeroService.byId(heroId), "fakes")
		end
	end)
	EconomyService.Earned:Connect(function(player: Player, action: string)
		if action == "deepRescue" then
			BadgeService.bump(player, "riders")
		end
	end)
	DeathService.Revived:Connect(function(_hero: any, helper: any)
		bumpHero(helper, "revives")
	end)
	-- Combat
	BlockService.Outcome:Connect(function(hero: any, outcome: string)
		if outcome == "blocked" or outcome == "perfect" then
			bumpHero(hero, "blocks")
			if outcome == "perfect" then
				bumpHero(hero, "perfects")
			end
		elseif outcome == "cut" then
			bumpHero(hero, "interrupts")
		elseif outcome == "break" then
			bumpHero(hero, "breaks")
		end
	end)
	ThrowService.Thrown:Connect(function(hero: any, kind: string, weight: string, hits: number)
		bumpHero(hero, "throws")
		if weight == "heavy" then
			bumpHero(hero, "heavyThrows")
		end
		if kind == "car" and (hits or 0) > 0 and BossService.inFight(hero) then
			bumpHero(hero, "carAtBoss")
		end
	end)
	HeroService.Awakened:Connect(function(hero: any)
		bumpHero(hero, "awakens")
	end)
	-- Groups
	MissionService.Cleared:Connect(function(player: Player, _num: number, info: any)
		info = info or {}
		if info.sidekick then
			BadgeService.bump(player, "sidekickClears")
		end
		if info.mentor then
			BadgeService.bump(player, "mentorClears")
		end
		if (info.party or 1) >= 2 and not info.taskForce then
			BadgeService.bump(player, "squadMissions")
		end
	end)
	TaskForceService.Done:Connect(function(player: Player, tf: number, seconds: number?, party: number?)
		BadgeService.bump(player, "tf:" .. tf)
		BadgeService.bump(player, "tfClears")
		if seconds and seconds < Config.TaskForce.speedClear then
			BadgeService.bump(player, "tfSpeed")
		end
		if (party or 1) >= Config.TaskForce.maxPlayers then
			BadgeService.bump(player, "tfFull")
		end
	end)
	MentorService.LineDone:Connect(function(player: Player)
		BadgeService.bump(player, "mentorLines")
	end)
	-- Nemesis
	NemesisService.Met:Connect(function(player: Player)
		BadgeService.bump(player, "nemesisMet")
	end)
	NemesisService.Won:Connect(function(player: Player, rank: number)
		BadgeService.bump(player, "bane:" .. rank)
	end)
	-- PvP: a win inside the Crater
	DeathService.PvpDefeat:Connect(function(_loser: any, winner: any)
		local p = winner and HeroService.position(winner)
		if p and ZoneLevel.area(Config, p.X, p.Z) == "CometCrater" then
			bumpHero(winner, "craterWins")
		end
		if winner and winner.player then
			dirty[winner.player] = true -- pvpWins is a fact
		end
	end)
	HeroService.Leveled:Connect(function(hero: any)
		if hero.player then
			dirty[hero.player] = true
		end
	end)
	task.spawn(function()
		local acc = 0
		while true do
			local dt = task.wait(B.checkEvery)
			acc += dt
			for _, player in Players:GetPlayers() do
				local hero = HeroService.get(player)
				if hero and hero.loaded and hero.alive then
					explore(player, hero, dt)
				end
			end
			for player in dirty do
				dirty[player] = nil
				if player.Parent then
					BadgeService.check(player)
				end
			end
			-- facts (Fame, styles, story) move without a signal here: a slow sweep catches them
			if acc >= 15 then
				acc = 0
				for _, player in Players:GetPlayers() do
					dirty[player] = true
				end
			end
		end
	end)
end

return BadgeService
