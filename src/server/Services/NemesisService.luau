-- NemesisService: your nemesis (spec: Hero MMO features > Nemesis; H5). From level 8 every hero has one
-- robot villain made for them (a hunter robot for a villain), the same on every server (Shared.
-- NemesisMath from the user id and rank). At most once per 30 minutes of play, and only 15 minutes into a
-- session, it ambushes you out in the city (never in a pocket, a safehouse, the Crater or a world boss
-- fight): a comic panel taunt, 6 robots of its kind, then the nemesis. Squadmates near you help and all get
-- paid (3x an incident at their own level). In encounters 1 to 3 it escapes at 30% health in a teleport
-- flash, dropping Intel and gaining a trait; Downing you gives it a trait too, and it gloats. 3 Intel show
-- its weak point (its back takes double damage) and open the Showdown: a pocket mission (sidekicking
-- applies) with its traits and robots. Winning pays a mission reward at your level, a Rare or better roll,
-- its Nemesis Core, its head for your HQ wall and the title Bane of (its name); a new one, one rank
-- tougher, shows up a day later. Saved per character as mmo.nemesis.
-- Its body is a Brute Bot (it hits like one); its look, signature tells and traits are drawn by NemesisFx.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Formulas = require(Shared:WaitForChild("Formulas"))
local GuardMath = require(Shared:WaitForChild("GuardMath"))
local NemesisMath = require(Shared:WaitForChild("NemesisMath"))
local Net = require(Shared:WaitForChild("Net"))
local Rng = require(Shared:WaitForChild("Rng"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local Analytics = require(script.Parent.Analytics)
local BlockService = require(script.Parent.BlockService)
local BossService = require(script.Parent.BossService)
local DataService = require(script.Parent.DataService)
local DeathService = require(script.Parent.DeathService)
local EconomyService = require(script.Parent.EconomyService)
local EnemyService = require(script.Parent.EnemyService)
local GearService = require(script.Parent.GearService)
local HeroService = require(script.Parent.HeroService)
local MissionService = require(script.Parent.MissionService)
local SafehouseService = require(script.Parent.SafehouseService)
local SquadService = require(script.Parent.SquadService)
local StoryService = require(script.Parent.StoryService)

local NemesisService = {}

local N = Config.Nemesis
local TAG = -9100 -- the nemesis's robots
local rng = Rng.new(Rng.hash(os.time(), 77))
NemesisService.Met = Signal.new() -- (player) first sight of a nemesis this encounter (analytics, badges)
NemesisService.Won = Signal.new() -- (player, rank) a Showdown win (badges, H7)

type Enc = {
	owner: Player,
	who: NemesisMath.Who,
	st: NemesisMath.Saved,
	side: string,
	level: number,
	at: Vector3,
	id: number?, -- the nemesis robot
	robots: { [number]: boolean },
	startedAt: number,
	sigAt: { [string]: number },
	traitAt: { [string]: number },
	cloakUntil: number,
	showdown: boolean,
	done: boolean,
}

local session: { [Player]: number } = {} -- os.clock when the session started
local lastEnc: { [Player]: number } = {} -- os.clock of the last encounter (play time)
local encs: { [Player]: Enc } = {}

local function char(player: Player): any?
	return StoryService.char(player)
end

-- The saved nemesis (made on first use, from the user id)
local function saved(player: Player): NemesisMath.Saved?
	local c = char(player)
	if not c or not c.mmo then
		return nil
	end
	local n = c.mmo.nemesis
	if n.seed == 0 then
		local f = NemesisMath.fresh(N, player.UserId, StoryService.side(player))
		for k, v in f do
			n[k] = v
		end
	end
	return n
end

local function whoOf(player: Player, st: NemesisMath.Saved): NemesisMath.Who
	return NemesisMath.make(N, player.UserId, st.rank, StoryService.side(player))
end

local function heroName(player: Player): string
	local n = player:GetAttribute("HeroName")
	return if type(n) == "string" and n ~= "" then n else player.DisplayName
end

-- Everyone who sees and helps: the owner plus squadmates near them
local function helpers(e: Enc): { Player }
	local out = { e.owner }
	for _, p in SquadService.mates(e.owner) do
		local h = HeroService.get(p)
		local pos = h and HeroService.position(h)
		if pos and (pos - e.at).Magnitude <= N.near * 2 then
			table.insert(out, p)
		end
	end
	return out
end

local function tell(e: Enc, data: { [string]: any })
	data.seed, data.rank, data.traits, data.name = e.who.seed, e.st.rank, e.st.traits, e.who.name
	data.side = e.side
	for _, p in Players:GetPlayers() do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if p == e.owner or (root and (root.Position - e.at).Magnitude < 250) then
			Net.fire("NemesisState", p, data)
		end
	end
end

-- The WANTED poster for its owner
local function sendPoster(player: Player)
	local st = saved(player)
	local hero = HeroService.get(player)
	if not st or not hero then
		return
	end
	local who = whoOf(player, st)
	local c = char(player)
	Net.fire("NemesisState", player, {
		k = "poster",
		seed = who.seed,
		name = who.name,
		rank = st.rank,
		traits = st.traits,
		intel = st.intel,
		met = st.met,
		side = StoryService.side(player),
		readyIn = math.max(0, st.readyAt - os.time()),
		locked = hero.level < N.minLevel,
		showdown = NemesisMath.showdownOpen(N, st),
		banes = c and #c.mmo.banes or 0,
	})
end

local function pay(e: Enc)
	for _, p in helpers(e) do
		local h = HeroService.get(p)
		if h then
			for _ = 1, N.payMult do
				EconomyService.reward(p, "incident", h.level)
			end
		end
	end
end

local function clearRobots(e: Enc)
	for id in e.robots do
		if EnemyService.alive(id) then
			EnemyService.remove(id)
		end
		BlockService.robotMults[id] = nil
	end
	table.clear(e.robots)
end

local function finish(e: Enc, how: string)
	if e.done then
		return
	end
	e.done = true
	local name = heroName(e.owner)
	if e.id then
		local nem = EnemyService.get(e.id)
		if nem and nem.alive then
			e.at = Vector3.new(nem.x, nem.y, nem.z)
		end
	end
	if how == "escape" then
		local t = NemesisMath.escaped(N, e.who, e.st)
		pay(e)
		tell(e, {
			k = "escape",
			id = e.id,
			trait = t,
			line = NemesisMath.line(N, "escape", e.who.seed, e.st.met, name),
			intel = e.st.intel,
		})
	elseif how == "gloat" then
		local t = NemesisMath.grow(N, e.who, e.st)
		tell(e, {
			k = "gloat",
			id = e.id,
			trait = t,
			line = NemesisMath.line(N, "gloat", e.who.seed, e.st.met, name),
		})
	else
		tell(e, { k = "leave", id = e.id })
	end
	clearRobots(e)
	encs[e.owner] = nil
	lastEnc[e.owner] = os.clock()
	DataService.saveSoon(e.owner)
	sendPoster(e.owner)
end

-- Its damage-taken hook: plates, the cloak, and once its Intel is complete its back (the weak point)
local function takenHook(e: Enc)
	return function(_hero: any, from: Vector3?): number
		local m = 1
		for i, t in N.traits do
			if NemesisMath.hasTrait(e.st.traits, i) then
				if t.id == "plates" or (t.id == "cloak" and os.clock() < e.cloakUntil) then
					m *= t.taken
				end
			end
		end
		local nem = e.id and EnemyService.get(e.id)
		if nem and from and NemesisMath.showdownOpen(N, e.st) then
			local fx, fz = -math.sin(nem.yaw or 0), -math.cos(nem.yaw or 0)
			if not GuardMath.front(180, fx, fz, nem.x, nem.z, from.X, from.Z) then
				m *= N.weakMult -- the glowing core on its back
			end
		end
		return m
	end
end

local function spawnNemesis(e: Enc, at: Vector3, squad: boolean): number?
	local id = EnemyService.spawnAt(N.body, at, e.level, TAG)
	if not id then
		return nil
	end
	EnemyService.tune(id, { hpMult = NemesisMath.hpMult(N, squad, e.st.rank) })
	e.id = id
	e.robots[id] = true
	BlockService.robotMults[id] = takenHook(e)
	tell(e, {
		k = "spawn",
		id = id,
		build = e.who.build,
		colors = e.who.colors,
		head = e.who.head,
		cape = e.who.cape,
		pitch = e.who.pitch,
		weak = NemesisMath.showdownOpen(N, e.st),
	})
	return id
end

local function startAmbush(player: Player, st: NemesisMath.Saved, at: Vector3)
	local hero = HeroService.get(player)
	if not hero then
		return
	end
	st.met += 1
	local e: Enc = {
		owner = player,
		who = whoOf(player, st),
		st = st,
		side = StoryService.side(player),
		level = hero.level,
		at = at,
		id = nil,
		robots = {},
		startedAt = os.clock(),
		sigAt = {},
		traitAt = {},
		cloakUntil = 0,
		showdown = false,
		done = false,
	}
	encs[player] = e
	lastEnc[player] = os.clock()
	tell(e, { k = "taunt", line = NemesisMath.line(N, "taunt", e.who.seed, st.met, heroName(player)) })
	for _, p in helpers(e) do
		NemesisService.Met:Fire(p)
		Analytics.event(p, "nemesis_met", st.met, { st.rank, NemesisMath.traitCount(st.traits) })
	end
	task.delay(N.panelTime, function()
		if e.done then
			return
		end
		local A = N.ambush
		for i = 1, A.robots do
			local a = i / A.robots * math.pi * 2
			local kind = A.kinds[(i - 1) % #A.kinds + 1]
			local id = EnemyService.spawnAt(
				kind,
				at + Vector3.new(math.cos(a) * A.ring, 2, math.sin(a) * A.ring),
				e.level,
				TAG
			)
			if id then
				e.robots[id] = true
			end
		end
		task.delay(A.nemesisAfter, function()
			if not e.done then
				spawnNemesis(e, at + Vector3.new(0, 2, 0), #helpers(e) > 1)
			end
		end)
	end)
	DataService.saveSoon(player)
end

-- A signature attack: tell the clients where (the warning), then hit every hero standing in it
local function signature(e: Enc, sig: string, nem: any)
	local target, best = nil, math.huge
	for _, p in helpers(e) do
		local h = HeroService.get(p)
		local pos = h and h.alive and HeroService.position(h)
		if pos then
			local d = (Vector3.new(nem.x, nem.y, nem.z) - pos).Magnitude
			if d < best then
				target, best = h, d
			end
		end
	end
	if not target or best > 120 then
		return
	end
	local tp = HeroService.position(target) :: Vector3
	local S = N.signatures[sig]
	local areas = NemesisMath.areas(N, sig, nem.x, nem.z, tp.X, tp.Z, rng:nextInt32())
	tell(e, { k = "sig", id = e.id, sig = sig, areas = areas, delay = S.delay, y = tp.Y - 2.5 })
	if S.drones then
		local alive = 0
		for id in e.robots do
			if EnemyService.alive(id) then
				alive += 1
			end
		end
		for k = 1, S.drones do
			if alive + k <= S.maxDrones + 1 then
				local id =
					EnemyService.spawnAt("SparkDrone", Vector3.new(nem.x, nem.y + 10, nem.z), e.level, TAG)
				if id then
					e.robots[id] = true
				end
			end
		end
	end
	local id = e.id :: number
	local dmg = Formulas.enemyDamage(Config, N.body, e.level) * S.dmg
	task.delay(S.delay, function()
		if e.done or not EnemyService.alive(id) then
			return
		end
		for _, h in HeroService.all() do
			local pos = h.alive and HeroService.position(h)
			if pos and math.abs(pos.Y - tp.Y) < 12 then
				for _, a in areas do
					if NemesisMath.inArea(a, pos.X, pos.Z) then
						HeroService.damage(h, dmg, { enemy = id })
						if S.pull then
							HeroService.cc(h, "slow", 1.5, 0.5)
						end
						break
					end
				end
			end
		end
	end)
end

local function stepTraits(e: Enc, nem: any, now: number)
	for i, t in N.traits do
		if NemesisMath.hasTrait(e.st.traits, i) then
			if t.id == "healDrone" and nem.health < nem.maxHealth then
				nem.health = math.min(nem.maxHealth, nem.health + nem.maxHealth * t.heal * 0.25)
			elseif t.id == "cloak" and now >= (e.traitAt.cloak or now + t.every) - 0.01 then
				e.traitAt.cloak = now + t.every
				e.cloakUntil = now + t.time
				tell(e, { k = "cloak", id = e.id, time = t.time })
			elseif t.id == "summon" and now >= (e.traitAt.summon or now + t.every) - 0.01 then
				e.traitAt.summon = now + t.every
				for k = 1, t.n do
					local kind = N.ambush.kinds[(k - 1) % #N.ambush.kinds + 1]
					local id =
						EnemyService.spawnAt(kind, Vector3.new(nem.x + k * 4, nem.y + 2, nem.z), e.level, TAG)
					if id then
						e.robots[id] = true
					end
				end
			end
			if e.traitAt[t.id] == nil then
				e.traitAt[t.id] = now + (t.every or 0)
			end
		end
	end
end

local function step()
	local now = os.clock()
	for player, e in encs do
		if e.done then
			continue
		end
		if not player.Parent then
			finish(e, "leave")
			continue
		end
		local nem = e.id and EnemyService.get(e.id)
		if e.id and (not nem or not nem.alive) then
			-- knocked out before it could run (a big burst past 30%): it still gets away, as an escape
			if e.showdown then
				BlockService.robotMults[e.id :: number] = nil
				encs[player] = nil
			else
				finish(e, "escape")
			end
			continue
		end
		if nem then
			e.at = Vector3.new(nem.x, nem.y, nem.z)
			if
				not e.showdown
				and NemesisMath.escapes(N, e.st.met)
				and nem.health <= nem.maxHealth * N.escapeAt
			then
				EnemyService.remove(e.id :: number)
				finish(e, "escape")
				continue
			end
			for _, sig in NemesisMath.signatures(N, e.who, e.st.traits) do
				local due = e.sigAt[sig]
				if not due then
					e.sigAt[sig] = now + N.signatures[sig].every * 0.5
				elseif now >= due then
					e.sigAt[sig] = now + N.signatures[sig].every
					signature(e, sig, nem)
				end
			end
			stepTraits(e, nem, now)
		end
		if not e.showdown and now - e.startedAt > N.leaveAfter then
			finish(e, "leave")
		end
	end
end

local function check()
	local now = os.time()
	local clock = os.clock()
	for _, player in Players:GetPlayers() do
		local hero = HeroService.get(player)
		local st = hero and hero.loaded and saved(player)
		if st and hero and not encs[player] and hero.alive then
			local pos = HeroService.position(hero)
			local ok = pos ~= nil
				and NemesisMath.canAppear(N, {
					level = hero.level,
					session = clock - (session[player] or clock),
					since = if lastEnc[player] then clock - lastEnc[player] else math.huge,
					now = now,
					readyAt = st.readyAt,
					intel = st.intel,
					inPocket = hero.scene ~= nil,
					inSafehouse = SafehouseService.at(pos :: Vector3) ~= nil,
					inCrater = player:GetAttribute("InCrater") == true,
					bossFight = BossService.inFight(hero),
				})
			if ok and rng:next() < N.appearChance then
				local a = rng:next() * math.pi * 2
				startAmbush(player, st, (pos :: Vector3) + Vector3.new(math.cos(a) * 30, 0, math.sin(a) * 30))
			end
		end
	end
end

-- The Showdown's pay (MissionService custom pay hook): the Rare or better roll for everyone; the owner also
-- gets the Core, the head trophy and the Bane title, and a new nemesis one rank tougher a day later
local function payShowdown(run: any, player: Player, out: { [string]: any }, own: number): { [string]: any }
	local tier = if rng:next() < N.showdown.epicChance then "Epic" else N.showdown.gearTier
	GearService.grantPiece(player, tier, own)
	out.gear = tier
	if player.UserId == run.m.owner then
		local c = char(player)
		local st = saved(player)
		if c and st then
			local banes = c.mmo.banes
			if #banes >= 8 then
				table.remove(banes, 1)
			end
			table.insert(banes, st.seed)
			c.mmo.cores += 1
			c.mmo.heads += 1
			local fresh = NemesisMath.afterWin(N, st, player.UserId, StoryService.side(player), os.time())
			for k, v in fresh do
				(st :: any)[k] = v
			end
			out.bane = true
			NemesisService.Won:Fire(player, st.rank - 1)
			Analytics.event(player, "nemesis_showdown", 1, { st.rank - 1 })
			DataService.saveSoon(player)
			task.defer(sendPoster, player)
		end
	end
	return out
end

local function startShowdown(player: Player)
	local st = saved(player)
	local hero = HeroService.get(player)
	if not st or not hero or not NemesisMath.showdownOpen(N, st) or hero.scene or encs[player] then
		return
	end
	local players = { player }
	for _, p in SquadService.mates(player) do
		local h = HeroService.get(p)
		local a = h and HeroService.position(h)
		local b = HeroService.position(hero)
		if a and b and (a - b).Magnitude <= N.near then
			table.insert(players, p)
		end
	end
	local who = whoOf(player, st)
	local SD = N.showdown
	local m = {
		custom = true,
		showdown = true,
		id = "Showdown", -- analytics: mission_start and mission_done
		owner = player.UserId,
		num = SD.num,
		name = who.name,
		layout = SD.layout,
		minLevel = hero.level,
		minutes = SD.minutes,
		pay = payShowdown,
		steps = {
			{
				kind = "defeat",
				squads = { { N.ambush.kinds[1], SD.adds }, { N.ambush.kinds[2], SD.adds } },
				text = "Beat its robots",
			},
			{
				kind = "boss",
				enemy = N.body,
				hpMult = NemesisMath.hpMult(N, false, st.rank),
				text = "Showdown: " .. who.name,
			},
		},
	}
	local ok, why = MissionService.enterCustom(players, m)
	if not ok then
		Net.fire("Toast", player, { id = "missionRefused", reason = why })
		return
	end
	-- the boss step registers once its robot spawns (MissionService.bossOf)
	local e: Enc = {
		owner = player,
		who = who,
		st = st,
		side = StoryService.side(player),
		level = hero.level,
		at = Vector3.zero,
		id = nil,
		robots = {},
		startedAt = os.clock(),
		sigAt = {},
		traitAt = {},
		cloakUntil = 0,
		showdown = true,
		done = false,
	}
	task.spawn(function()
		for _ = 1, 1200 do
			task.wait(0.5)
			local run = MissionService.runOf(player)
			if not run or run.done or run.m ~= m then
				return
			end
			local bossId = MissionService.bossOf(run)
			if bossId and EnemyService.alive(bossId) then
				e.id = bossId
				e.level = run.level
				e.robots[bossId] = true
				BlockService.robotMults[bossId] = takenHook(e)
				encs[player] = e
				tell(e, {
					k = "spawn",
					id = bossId,
					build = who.build,
					colors = who.colors,
					head = who.head,
					cape = who.cape,
					weak = true,
				})
				tell(e, {
					k = "taunt",
					line = NemesisMath.line(N, "taunt", who.seed, st.met + 7, heroName(player)),
				})
				return
			end
		end
	end)
	Analytics.event(player, "nemesis_showdown_start", 1, { st.rank, #players })
end

function NemesisService.state(player: Player): NemesisMath.Saved?
	return saved(player)
end

-- Studio only (DevService "nemesis"): 0 ambushes you now (skipping the time rules), 1 fills your Intel
function NemesisService.dev(player: Player, what: number)
	local st = saved(player)
	local hero = HeroService.get(player)
	local pos = hero and HeroService.position(hero)
	if not st or not hero or not pos then
		return
	end
	if what == 1 then
		st.intel = N.intelForShowdown
		sendPoster(player)
	elseif not encs[player] and not hero.scene then
		st.readyAt = 0
		startAmbush(player, st, pos + Vector3.new(30, 0, 0))
	end
end

function NemesisService.init()
	Players.PlayerAdded:Connect(function(p)
		session[p] = os.clock()
	end)
	for _, p in Players:GetPlayers() do
		session[p] = os.clock()
	end
	Players.PlayerRemoving:Connect(function(p)
		local e = encs[p]
		if e then
			finish(e, "leave")
		end
		session[p], lastEnc[p] = nil, nil
	end)
	DeathService.Downed:Connect(function(hero: any)
		for _, e in encs do
			if not e.done and not e.showdown and e.id then
				for _, p in helpers(e) do
					if p == hero.player then
						if EnemyService.alive(e.id) then
							EnemyService.remove(e.id)
						end
						finish(e, "gloat") -- it Downs you: a trait and a gloat, and it leaves
						break
					end
				end
			end
		end
	end)
	Net.on("NemesisPoster", sendPoster)
	Net.on("NemesisShowdown", startShowdown)
	task.spawn(function()
		local acc = 0
		while true do
			task.wait(0.25)
			step()
			acc += 0.25
			if acc >= N.checkEvery then
				acc = 0
				check()
			end
		end
	end)
end

return NemesisService
