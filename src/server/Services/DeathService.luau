-- DeathService: Downed, revives, Give Up, respawns and PvP defeats (spec: Defeat and death; Anti-farming;
-- PvP rewards).
-- * PvE health at 0: Downed for 10 s. The hero crawls (4 studs a second) and can ping; a Help marker shows
--   on nearby players' screens. An ally holds Revive next to them for 3 s (1.5 s for Warden Controllers) and
--   they stand with 35% health (the helper gets a Renown pop). Give Up respawns in 2 s. After 10 s the hero
--   is Defeated and respawns in 5 s at the nearest visited safehouse, or the one picked on the screen.
-- * PvP health at 0: Defeated at once, no Downed state (nobody can be finished or camped). The hero
--   overloads into sparks and respawns in 5 s with 5 s of protection. The loser drops 5% of on-hand Credits
--   above 500 (max 300) to the winner, who also earns Credits 40 + 2 x level and 15 Fame, under the
--   anti-farming rules (PvpRules.win). Gear is never lost.
-- * Combat logging: leaving within 15 s of PvP damage counts as that defeat, and the hero's body stays in
--   the world for 10 s.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local PvpRules = require(Shared:WaitForChild("PvpRules"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))

local DataService = require(script.Parent.DataService)
local HeroService = require(script.Parent.HeroService)
local EconomyService = require(script.Parent.EconomyService)
local SafehouseService = require(script.Parent.SafehouseService)
local BossService = require(script.Parent.BossService)
local FlagService = require(script.Parent.FlagService)
local FameService = require(script.Parent.FameService)
local GuardService = require(script.Parent.GuardService)

local DeathService = {}
DeathService.Downed = Signal.new() -- (hero)
DeathService.Revived = Signal.new() -- (hero, helper)
DeathService.PvpDefeat = Signal.new() -- (loser, winner)

local D = Config.Pvp.downed
local PING_KIND = { help = 1, here = 2, danger = 3 }

type Down = {
	untilT: number,
	source: any?,
	giveUpAt: number?,
	reviver: { id: number, startT: number, doneAt: number }?,
	sentAt: number,
}

local downs: { [number]: Down } = {}
local ledger = PvpRules.newLedger()
local overload = 0

local function visitedList(hero: any): { number }
	return SafehouseService.visited(hero)
end

local function sendDown(hero: any, extra: { [string]: any }?)
	local player = hero.player
	if not player then
		return
	end
	local d = downs[hero.id]
	local now = os.clock()
	local msg: { [string]: any } = {
		downed = d ~= nil,
		left = if d then math.max(0, d.untilT - now) else 0,
		giveUp = if d and d.giveUpAt then math.max(0, d.giveUpAt - now) else nil,
		revive = 0,
	}
	if d and d.reviver then
		local r = d.reviver
		msg.revive = math.clamp((now - r.startT) / math.max(0.01, r.doneAt - r.startT), 0, 1)
		local helper = HeroService.byId(r.id)
		msg.by = helper and helper.name
	end
	if extra then
		for k, v in extra do
			msg[k] = v
		end
	end
	Net.fire("DownState", player, msg)
end

-- A marker on the screens of nearby players (Help, Here, Danger)
-- M10 squads set this: (hero) -> the squadmates' players (squad pings reach them at any range)
DeathService.squadOf = nil :: ((any) -> { Player })?

local function ping(hero: any, kind: number, pos: Vector3, downed: boolean?)
	local mates = if DeathService.squadOf then DeathService.squadOf(hero) else {}
	for _, p in Players:GetPlayers() do
		local other = HeroService.get(p)
		local op = other and HeroService.position(other)
		local mate = table.find(mates, p) ~= nil
		if other and other ~= hero and op and (mate or (op - pos).Magnitude <= D.pingRange) then
			Net.fire("PingShow", p, {
				kind = kind,
				x = pos.X,
				y = pos.Y,
				z = pos.Z,
				from = hero.id,
				name = hero.name,
				life = D.pingLife,
				downed = downed or nil,
				squad = mate or nil,
			})
		end
	end
end

---------------------------------------------------------------------------
-- Downed (PvE)
---------------------------------------------------------------------------

local function down(hero: any, source: any?)
	local now = os.clock()
	hero.alive = false
	hero.downed = true
	hero.health = 0
	hero.channel = nil
	local hum = HeroService.humanoid(hero)
	if hum then
		hum.Health = math.max(1, hum.MaxHealth * 0.01) -- the body stays up (kneeling, crawling)
	end
	HeroService.applyWalkSpeed(hero)
	downs[hero.id] = { untilT = now + D.time, source = source, sentAt = now }
	if hero.player then
		hero.player:SetAttribute("Downed", true)
	end
	DeathService.Downed:Fire(hero)
	sendDown(hero, { safehouses = visitedList(hero) })
	local pos = HeroService.position(hero)
	if pos then
		ping(hero, PING_KIND.help, pos, true)
	end
end

-- Defeated: quick = Give Up (respawn now), else the normal 5 s respawn. dead: the humanoid already died
-- (a Reset while Downed): Roblox brings the character back on its own respawn timer
local function defeat(hero: any, quick: boolean, dead: boolean?)
	local d = downs[hero.id]
	downs[hero.id] = nil
	hero.downed = nil
	hero.alive = false
	hero.health = 0
	local player = hero.player
	if player then
		player:SetAttribute("Downed", nil)
	end
	HeroService.Defeated:Fire(hero, d and d.source)
	sendDown(hero, {
		defeated = true,
		respawnIn = if dead then Players.RespawnTime elseif quick then 0 else Config.Pvp.respawn.pve,
		safehouses = if quick then nil else visitedList(hero),
	})
	if dead then
		return
	elseif quick and player and player.Parent == Players then
		player:LoadCharacter()
	else
		local hum = HeroService.humanoid(hero)
		if hum then
			hum.Health = 0
		end
	end
end

local function revive(hero: any, helper: any)
	downs[hero.id] = nil
	hero.downed = nil
	hero.alive = true
	hero.health = math.max(1, math.floor(hero.maxHealth * D.reviveHealth + 0.5))
	hero.lastDamaged = os.clock()
	local hum = HeroService.humanoid(hero)
	if hum then
		hum.Health = hero.health
	end
	HeroService.applyWalkSpeed(hero)
	if hero.player then
		hero.player:SetAttribute("Downed", nil)
		Net.fire("Toast", hero.player, { id = "revivedBy", name = helper.name })
	end
	sendDown(hero, { revived = true })
	if helper.player then
		EconomyService.addRenown(helper.player, D.reviveRenown)
		Net.fire("Toast", helper.player, { id = "revived", name = hero.name, renown = D.reviveRenown })
	end
	HeroService.Supported:Fire(helper, hero.health)
	DeathService.Revived:Fire(hero, helper)
end

local function onRevive(player: Player, userId: number)
	local helper = HeroService.get(player)
	local target = Players:GetPlayerByUserId(userId)
	local hero = target and HeroService.get(target)
	local d = hero and downs[hero.id]
	if not helper or not hero or not d or helper == hero or not helper.alive or helper.downed then
		return
	end
	local hp, tp = HeroService.position(helper), HeroService.position(hero)
	if not hp or not tp or (hp - tp).Magnitude > D.reviveRange + 2 then
		return
	end
	if not FlagService.canSupport(helper, hero) then
		Net.fire("Toast", player, { id = "reviveBlocked" })
		return
	end
	if d.reviver and d.reviver.id ~= helper.id and HeroService.byId(d.reviver.id) then
		return -- someone is already reviving
	end
	local now = os.clock()
	d.reviver = { id = helper.id, startT = now, doneAt = now + PvpRules.reviveTime(Config, helper.classId) }
	sendDown(hero)
end

local function onGiveUp(player: Player)
	local hero = HeroService.get(player)
	local d = hero and downs[hero.id]
	if hero and d and not d.giveUpAt then
		d.giveUpAt = os.clock() + D.giveUp
		sendDown(hero)
	end
end

local function step()
	local now = os.clock()
	for id, d in downs do
		local hero = HeroService.byId(id)
		if not hero or not hero.downed then
			downs[id] = nil
			continue
		end
		local r = d.reviver
		if r then
			local helper = HeroService.byId(r.id)
			local hp, tp = helper and HeroService.position(helper), HeroService.position(hero)
			local ok = helper ~= nil
				and helper.alive
				and not helper.downed
				and hp ~= nil
				and tp ~= nil
				and (hp - tp).Magnitude <= D.reviveRange + 3
				and helper.lastCast < r.startT -- casting breaks the hold
			if not ok then
				d.reviver = nil
				sendDown(hero)
			elseif now >= r.doneAt and helper then
				revive(hero, helper)
				continue
			end
		end
		if d.giveUpAt and now >= d.giveUpAt then
			defeat(hero, true)
		elseif now >= d.untilT then
			defeat(hero, false)
		elseif now - d.sentAt >= 0.25 then
			d.sentAt = now
			sendDown(hero)
		end
	end
end

---------------------------------------------------------------------------
-- PvP defeat and rewards
---------------------------------------------------------------------------

-- Pay a PvP win. The loser may already have left (combat logging): its profile, level and side are passed.
local function settle(
	winner: any,
	loserId: number,
	loserName: string,
	loserLevel: number,
	loserSide: string,
	loserProfile: any?,
	loserPlayer: Player?,
	inBoss: boolean
)
	local now = os.clock()
	local reviews = #ledger.review
	local factor, why = PvpRules.win(Config, ledger, winner.id, loserId, now, {
		winnerLevel = winner.level,
		loserLevel = loserLevel,
		sameSide = winner.side == loserSide,
		inBoss = inBoss,
	})
	if #ledger.review > reviews then
		local row = ledger.review[#ledger.review]
		GuardService.review(row.a, "trade", { with = row.b })
		GuardService.review(row.b, "trade", { with = row.a })
	end
	local moved = 0
	if loserProfile and factor > 0 then
		local loss = math.floor(PvpRules.loss(Config, loserProfile.currency.credits) * factor)
		moved = EconomyService.takeOnHand(loserProfile, loserPlayer, loss)
	end
	local credits, fame = PvpRules.reward(Config, loserLevel, factor)
	if winner.player then
		EconomyService.addCredits(winner.player, credits + moved)
		if fame > 0 then
			FameService.add(winner.player, "pvp", factor)
			local wp = DataService.get(winner.player)
			if wp then
				wp.stats.wins += 1 -- a PvP win that paid (the trophy wall, M9)
			end
		end
		Net.fire("PvpResult", winner.player, {
			won = true,
			other = loserName,
			credits = credits + moved,
			fame = fame,
			cut = why,
		})
		DataService.saveSoon(winner.player)
	end
	if loserPlayer and loserPlayer.Parent == Players then
		Net.fire("PvpResult", loserPlayer, { won = false, other = winner.name, credits = moved })
	end
end

local function pvpDefeat(loser: any, winner: any)
	-- this fight is paid now: leaving within the combat-log window must not pay it again (2026-11-18 fix)
	FlagService.clearAttacker(loser)
	loser.alive = false
	loser.health = 0
	loser.channel = nil
	overload += 1
	local player = loser.player
	if player then
		player:SetAttribute("Overload", overload) -- everyone draws the sparks burst
	end
	local profile = player and DataService.get(player)
	settle(
		winner,
		loser.id,
		loser.name,
		loser.level,
		loser.side,
		profile,
		player,
		BossService.inFight(winner) or BossService.inFight(loser)
	)
	HeroService.gainMeter(winner, "kill", 1)
	HeroService.Defeated:Fire(loser, { pvp = winner })
	DeathService.PvpDefeat:Fire(loser, winner)
	if player then
		sendDown(loser, {
			defeated = true,
			pvp = true,
			respawnIn = Config.Pvp.respawn.pvp,
			safehouses = visitedList(loser),
		})
	end
	local hum = HeroService.humanoid(loser)
	if hum then
		hum.Health = 0
	end
end

-- HeroService calls this when a player's health hits 0. Bots keep the old path.
local function onZero(hero: any, source: any?): boolean
	if not hero.player then
		return false
	end
	if hero.downed then
		return true
	end
	if source and source.pvp then
		pvpDefeat(hero, source.pvp)
	else
		down(hero, source)
	end
	return true
end

-- A Reset (the humanoid died outside these rules): Downed is Give Up, a standing hero inside the combat-log
-- window loses that PvP fight (as leaving would), else HeroService's plain defeat (PvpRules.resetOutcome)
local function onReset(hero: any): boolean
	if not hero.player then
		return false
	end
	local attackerId = FlagService.lastAttacker(hero, Config.Pvp.combatLog.window)
	local winner = attackerId and HeroService.byId(attackerId)
	if winner == hero or (winner and not winner.player) then
		winner = nil
	end
	local outcome = PvpRules.resetOutcome(downs[hero.id] ~= nil, hero.alive == true, winner and winner.id)
	if outcome == "giveUp" then
		defeat(hero, true, true)
		return true
	elseif outcome == "pvp" and winner then
		pvpDefeat(hero, winner)
		return true
	end
	return false
end

-- Combat logging: a player who leaves within 15 s of PvP damage loses that fight, and the body stays 10 s
local function onLeaving(player: Player, profile: any)
	local W = Config.Pvp.combatLog
	local attackerId = FlagService.lastAttacker({ id = player.UserId }, W.window)
	local winner = attackerId and HeroService.byId(attackerId)
	if not winner or not winner.player then
		return
	end
	local c = ProfileSchema.active(profile)
	settle(
		winner,
		player.UserId,
		player.DisplayName,
		c.level,
		c.side,
		profile,
		nil,
		BossService.inFight(winner)
	)
	local char = player.Character
	if char then
		char.Archivable = true
		local ok, ghost = pcall(char.Clone, char)
		if ok and ghost then
			for _, p in ghost:GetDescendants() do
				if p:IsA("BasePart") then
					p.Anchored = true
				elseif p:IsA("Script") or p:IsA("LocalScript") then
					p:Destroy()
				end
			end
			ghost.Name = "LeftBehind"
			ghost.Parent = Workspace
			Debris:AddItem(ghost, W.linger)
		end
	end
end

function DeathService.isDowned(hero: any): boolean
	return downs[hero.id] ~= nil
end

-- Studio: down a hero now (DevPanel)
function DeathService.downNow(hero: any)
	if hero.alive and hero.player then
		down(hero, nil)
	end
end

function DeathService.init()
	HeroService.downHandler = onZero
	HeroService.resetHandler = onReset
	-- Dawnburst (Light): every Downed ally within the radius stands up (allowed allies only)
	local CombatService = require(script.Parent.CombatService) :: any
	CombatService.reviveHook = function(helper: any, pos: Vector3, radius: number)
		for id in table.clone(downs) do
			local hero = HeroService.byId(id)
			local p = hero and HeroService.position(hero)
			if
				hero
				and p
				and hero ~= helper
				and (p - pos).Magnitude <= radius
				and FlagService.canSupport(helper, hero)
			then
				revive(hero, helper)
			end
		end
	end
	Net.on("ReviveStart", onRevive)
	Net.on("DownGiveUp", onGiveUp)
	Net.on("RespawnChoose", function(player, id: number)
		local hero = HeroService.get(player)
		if hero and not hero.alive and SafehouseService.chooseRespawn(hero, id) then
			Net.fire("Toast", player, { id = "respawnPick", safehouse = id })
		end
	end)
	Net.on("PingPlace", function(player, kind: number, pos: Vector3)
		local hero = HeroService.get(player)
		local at = hero and HeroService.position(hero)
		if not hero or not at or (pos - at).Magnitude > 300 then
			return
		end
		ping(hero, kind, pos, hero.downed)
	end)
	DataService.Leaving:Connect(onLeaving)
	HeroService.Spawned:Connect(function(hero)
		downs[hero.id] = nil
		-- a new character is never Downed: the attribute drives the crawl and the flight lock on the client
		-- (a Reset while Downed left it set, 2026-11-18 fix)
		if hero.player then
			hero.player:SetAttribute("Downed", nil)
		end
		sendDown(hero, { respawned = true })
	end)
	HeroService.Removed:Connect(function(hero)
		downs[hero.id] = nil
	end)
	local acc = 0
	RunService.Heartbeat:Connect(FrameProf.wrap("DeathService", function(dt)
		acc += dt
		if acc >= 0.1 then
			acc = 0
			step()
		end
	end))
end

return DeathService
