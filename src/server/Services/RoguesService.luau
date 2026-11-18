-- RoguesService: fills the Rogues File (spec: Collections and records > Rogues File; Config.Rogues,
-- Shared.RoguesFile), account-wide on profile.rogues and profile.roguesLog. Only signals, no edits in the
-- services it listens to:
-- * EnemyService.Killed: the robot or famous fake page of the kind the hero beat (a dressed finale villain is
--   its villain's page, filled by the finale instead);
-- * SideQuestService.StepPaid (a chain finished, so its finale was won): the finale's villain pages, for every
--   member of the group;
-- * BossService.Rewarded (beaten): the boss's page (BossService sets its bit, as since M6) and, in a fight at
--   the gold level as a Contributor or the MVP, its gold page.
-- A new page: RoguesNew (the stamp on the owner's screen) and a quick save; every beat counts on its log row.
-- Milestones (10, 25, every page): one existing earnable creator piece each, once per account.
-- RoguesOpen answers with the pages (RoguesFile) for the Journal's ROGUES tab.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CreatorRules = require(Shared:WaitForChild("CreatorRules"))
local Net = require(Shared:WaitForChild("Net"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))
local RoguesFile = require(Shared:WaitForChild("RoguesFile"))

local BossService = require(script.Parent.BossService)
local DataService = require(script.Parent.DataService)
local EnemyService = require(script.Parent.EnemyService)
local HeroService = require(script.Parent.HeroService)
local SideQuestService = require(script.Parent.SideQuestService)

local RoguesService = {}

local Bits = ProfileSchema.Bits

local function send(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	Net.fire("RoguesFile", player, { bits = Bits.list(profile.rogues), log = profile.roguesLog })
end

-- Pay every milestone reached and not paid yet (its bit marks it paid even when the piece was owned already)
local function payMilestones(player: Player, profile: any): boolean
	local paid = false
	for _, m in RoguesFile.due(Config, profile.rogues) do
		Bits.set(profile.rogues, m.bit)
		paid = true
		local piece = CreatorRules.index(Config).byName[m.piece]
		if piece and CreatorRules.grant(profile, piece) then
			Net.fire("Toast", player, { id = "piece", name = piece.name })
		end
		Net.fire("RoguesNew", player, { milestone = RoguesFile.need(Config, m), piece = m.piece })
	end
	return paid
end

-- Mark these page bits beaten for a player (gold: the bits are gold pages). Returns nothing; a new page
-- stamps on the owner's screen and saves soon.
local function beat(player: Player, bits: { number }, gold: boolean?)
	local profile = DataService.get(player)
	if not profile or #bits == 0 then
		return
	end
	local hero = HeroService.get(player)
	local level = if hero then hero.level else 1
	local day = os.time() // 86400
	local fresh = false
	for _, bit in bits do
		if RoguesFile.beat(Config, profile.rogues, profile.roguesLog, bit, day, level) then
			fresh = true
			Net.fire("RoguesNew", player, { bit = bit, gold = gold == true })
		end
	end
	if fresh then
		payMilestones(player, profile)
		DataService.changed(player)
		DataService.saveSoon(player)
		send(player)
	end
end

function RoguesService.init()
	Net.on("RoguesOpen", send)
	EnemyService.Killed:Connect(function(kind: string, heroId: number?, _pos: Vector3?, enemyId: number?)
		local hero = heroId and HeroService.byId(heroId)
		local player = hero and hero.player
		if not player then
			return
		end
		-- a finale villain in a dress is its own page (filled when the finale is won), not its suit's robot
		local ident = enemyId and EnemyService.identity(enemyId)
		if ident and ident.dress then
			return
		end
		local e = RoguesFile.forKind(Config, kind)
		if e then
			beat(player, { e.bit })
		end
	end)
	SideQuestService.StepPaid:Connect(function(player: Player, done: boolean, chainId: string?)
		if not done or type(chainId) ~= "string" then
			return
		end
		local bits = {}
		for _, e in RoguesFile.forChain(Config, chainId :: string) do
			table.insert(bits, e.bit)
		end
		beat(player, bits)
	end)
	BossService.Rewarded:Connect(
		function(
			player: Player,
			bossId: any,
			tier: string,
			defeated: boolean,
			_score: number?,
			level: number?
		)
			local e = defeated and RoguesFile.forBoss(Config, tostring(bossId))
			if not e then
				return
			end
			beat(player, { e.bit })
			if e.gold and RoguesFile.isGold(Config, tier, defeated, level) then
				beat(player, { e.gold }, true)
			end
		end
	)
	-- a milestone moved or added since this account's last session is paid when it loads
	DataService.Loaded:Connect(function(player: Player, profile: any)
		if payMilestones(player, profile) then
			DataService.changed(player)
			DataService.saveSoon(player)
		end
	end)
end

return RoguesService
