-- FlagService: the PvP flag and every PvP hit rule (spec: The PvP flag; Stat compression; Anti-exploit
-- "Flag: read at the moment of every hit"). Server-owned: a client can only ask (FlagSet), and the answer
-- comes back as FlagState plus the Pvp and PvpSide player attributes that everyone's rings and name plates
-- read.
-- * Switch: on at once from level 10 (not in a safe area), at most every 5 s; off only after 60 s with no
--   PvP damage dealt or taken, and never inside the Crater.
-- * The Crater: walking in starts a 5 s warning ring (and a Leave button); staying forces PvP for level 10+;
--   +50% Renown inside (the InCrater attribute, read by EconomyService).
-- * Targets: targetsFor(attacker) lists the flagged heroes an attacker may hit (combat ids PVP_BASE + slot),
--   and canHit is checked again when each hit lands. Safe areas (HQ, safehouses, mission pockets and the
--   opening) block both ways; spawn protection (5 s, once per life) blocks the target until it attacks.
-- * Support: canSupport stops unflagged healers keeping a flagged fighter alive.
-- * Compression: damage() turns a PvE roll into the PvP number (PvpRules).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local PvpRules = require(Shared:WaitForChild("PvpRules"))
local RematchRules = require(Shared:WaitForChild("RematchRules"))

local CityBuilder = require(script.Parent.CityBuilder)
local HeroService = require(script.Parent.HeroService)
local SafehouseService = require(script.Parent.SafehouseService)
local DataService = require(script.Parent.DataService)

local FlagService = {}
FlagService.Changed = Signal.new() -- (hero, flagged) the hero's PvP state changed
FlagService.pvpHook = nil :: ((any, any) -> ())? -- AnalyticsHooks: called on every PvP hit (attacker, target)

local P = Config.Pvp
local POCKET_Y = Config.Story.pockets.y - 100
local flags: { [number]: PvpRules.Flag } = {}
local lastBy: { [number]: { id: number, t: number } } = {} -- hero id -> who last dealt PvP damage
local shown: { [number]: string } = {} -- what the owner last saw (FlagState on change only)
local crater: { centre: { x: number, z: number }, size: number }? = nil

-- M10 squads set this: (a, b) -> true when the two heroes are allies (allies never hit each other)
FlagService.allyCheck = nil :: ((any, any) -> boolean)?

function FlagService.flag(hero: any): PvpRules.Flag
	local f = flags[hero.id]
	if not f then
		f = PvpRules.newFlag()
		flags[hero.id] = f
	end
	return f
end

function FlagService.flagged(hero: any): boolean
	return hero.player ~= nil and PvpRules.flagged(Config, FlagService.flag(hero), hero.level)
end

-- HQ, a safehouse's radius, a mission pocket, a story scene or a fast-travel flight
function FlagService.safe(hero: any): boolean
	if hero.scene or hero.traveling then
		return true
	end
	local pos = HeroService.position(hero)
	if not pos then
		return true
	end
	return pos.Y >= POCKET_Y or SafehouseService.near(hero)
end

local function side(hero: any): PvpRules.Side
	return {
		id = hero.id,
		flag = FlagService.flag(hero),
		level = hero.level,
		alive = hero.alive and not hero.downed,
		safe = FlagService.safe(hero),
	}
end

local function allies(a: any, b: any): boolean
	return FlagService.allyCheck ~= nil and FlagService.allyCheck(a, b)
end

-- May `a` hurt `b` right now? (read again at the moment of every hit)
function FlagService.canHit(a: any, b: any): boolean
	if not a.player or not b.player then
		return false -- bots never take part in PvP
	end
	return (PvpRules.canHit(Config, side(a), side(b), allies(a, b), os.clock()))
end

function FlagService.canSupport(giver: any, target: any): boolean
	if giver == target or not giver.player or not target.player then
		return true
	end
	return PvpRules.canSupport(Config, side(giver), side(target), allies(giver, target), os.clock())
end

-- The flagged heroes this attacker may hit, as combat candidates (empty when the attacker cannot fight)
local EMPTY = table.freeze({})
function FlagService.targetsFor(attacker: any): { any }
	if not attacker.player or not FlagService.flagged(attacker) or FlagService.safe(attacker) then
		return EMPTY
	end
	local out = {}
	for _, h in HeroService.all() do
		if h ~= attacker and h.player and h.pvpSlot > 0 and FlagService.canHit(attacker, h) then
			local pos = HeroService.position(h)
			if pos then
				table.insert(out, {
					id = HeroService.PVP_BASE + h.pvpSlot,
					x = pos.X,
					y = pos.Y,
					z = pos.Z,
					r = 2.5,
					flags = 0,
					hero = h,
				})
			end
		end
	end
	return out
end

-- PvP damage dealt by a onto b (both flags go "in PvP combat")
function FlagService.notePvp(a: any, b: any)
	local now = os.clock()
	PvpRules.notePvp(FlagService.flag(a), now)
	PvpRules.notePvp(FlagService.flag(b), now)
	lastBy[b.id] = { id = a.id, t = now }
	if FlagService.pvpHook then
		FlagService.pvpHook(a, b)
	end
end

-- Who last dealt PvP damage to this hero within `window` seconds (combat logging), or nil
function FlagService.lastAttacker(hero: any, window: number): number?
	local l = lastBy[hero.id]
	if l and os.clock() - l.t <= window then
		return l.id
	end
	return nil
end

-- That fight is settled (a PvP defeat paid it): leaving or resetting now must not pay it again
function FlagService.clearAttacker(hero: any)
	lastBy[hero.id] = nil
end

function FlagService.inPvpCombat(hero: any): boolean
	return PvpRules.inPvpCombat(Config, FlagService.flag(hero), os.clock())
end

-- Attacking ends this hero's spawn protection early
function FlagService.attacked(hero: any)
	local f = flags[hero.id]
	if f and PvpRules.protected(f, os.clock()) then
		PvpRules.endProtect(f)
		FlagService.send(hero, true)
	end
end

-- A PvE damage roll as a PvP number: compressed Power and Health, supers at 60%
function FlagService.damage(attacker: any, target: any, raw: number, isSuper: boolean): number
	return PvpRules.damage(Config, raw, {
		power = HeroService.power(attacker),
		pvpPower = PvpRules.power(Config, attacker.level, attacker.stats.Might),
		maxHealth = target.maxHealth,
		pvpHealth = PvpRules.health(Config, target.level, target.stats.Vitality, target.classId),
		super = isSuper,
	})
end

---------------------------------------------------------------------------
-- State to the owner and everyone's attributes
---------------------------------------------------------------------------

function FlagService.send(hero: any, force: boolean?, reason: string?)
	local player = hero.player
	if not player then
		return
	end
	local f = FlagService.flag(hero)
	local now = os.clock()
	local flagged = PvpRules.flagged(Config, f, hero.level)
	player:SetAttribute("Pvp", flagged or nil)
	player:SetAttribute("PvpSide", hero.side)
	player:SetAttribute("PvpId", if hero.pvpSlot > 0 then HeroService.PVP_BASE + hero.pvpSlot else nil)
	player:SetAttribute("InCrater", f.crater ~= "out" or nil)
	local protect = math.max(0, f.protectUntil - now)
	player:SetAttribute("Protected", protect > 0 or nil)
	local key = string.format(
		"%s%s%s%d%d",
		tostring(f.on),
		tostring(flagged),
		f.crater,
		if protect > 0 then 1 else 0,
		math.floor(f.pvpAt) -- new PvP damage restarts the 60 s count the button shows
	)
	if not force and not reason and shown[hero.id] == key then
		return
	end
	shown[hero.id] = key
	Net.fire("FlagState", player, {
		on = f.on,
		flagged = flagged,
		crater = f.crater,
		warnLeft = if f.crater == "warn" then math.max(0, f.warnUntil - now) else 0,
		offIn = PvpRules.offIn(Config, f, now),
		protectLeft = protect,
		reason = reason,
		minLevel = P.minLevel,
	})
	FlagService.Changed:Fire(hero, flagged)
end

local function onSet(player: Player, on: number)
	local hero = HeroService.get(player)
	if not hero then
		return
	end
	local f = FlagService.flag(hero)
	local want = on == 1
	local ok, reason = PvpRules.canSet(
		Config,
		f,
		want,
		{ level = hero.level, safe = FlagService.safe(hero), now = os.clock() }
	)
	if not ok then
		FlagService.send(hero, true, reason)
		return
	end
	PvpRules.set(f, want, os.clock())
	FlagService.send(hero, true)
	Net.fire("Toast", player, { id = if want then "pvpOn" else "pvpOff" })
end

-- The Leave button: only during the warning, the hero is set down just outside the nearest edge
local function onLeave(player: Player)
	local hero = HeroService.get(player)
	local c = crater
	if not hero or not c or not hero.alive then
		return
	end
	local f = FlagService.flag(hero)
	local pos = HeroService.position(hero)
	if f.crater ~= "warn" or not pos then
		return
	end
	local dx, dz = pos.X - c.centre.x, pos.Z - c.centre.z
	local h = c.size / 2 + P.crater.leaveOut
	local x, z = pos.X, pos.Z
	if math.abs(dx) > math.abs(dz) then
		x = c.centre.x + (if dx >= 0 then h else -h)
	else
		z = c.centre.z + (if dz >= 0 then h else -h)
	end
	local y = CityBuilder.heightAt(x, z) + 4
	SafehouseService.place(hero, CFrame.new(x, y, z))
	f.crater = "out"
	FlagService.send(hero, true)
end

---------------------------------------------------------------------------
-- WP4 (spec: Social > Rivalry; gap G8): the REMATCH ping (Shared.RematchRules, Config.Pvp.rematch). Fixed
-- buttons and fixed lines only: the loser's REMATCH, the winner's "X wants a rematch" card with ACCEPT and
-- NO. ACCEPT with both flagged tells both and shows each other's spot; nobody is moved or flagged by it.
---------------------------------------------------------------------------

local rematch = RematchRules.new()

-- A PvP defeat between two players gives the loser one ping at that winner (DeathService.PvpDefeat)
function FlagService.rematchOffer(loser: any, winner: any)
	if loser.player and winner.player then
		RematchRules.defeat(P.rematch, rematch, loser.id, winner.id, os.clock())
	end
end

local function rematchNo(player: Player, reason: string)
	Net.fire("Toast", player, { id = "rematchRefused", reason = reason })
end

-- Each other's spot for a few seconds: a Here ping from the other hero (the PingShow marker)
local function showSpot(to: Player, other: any)
	local pos = HeroService.position(other)
	if pos then
		Net.fire("PingShow", to, {
			kind = 2,
			x = pos.X,
			y = pos.Y,
			z = pos.Z,
			from = other.id,
			name = other.name,
			life = P.rematch.spotLife,
		})
	end
end

local function onRematch(player: Player, act: number, userId: number?)
	local me = HeroService.get(player)
	if not me then
		return
	end
	local now = os.clock()
	if act == 1 then
		-- the loser pings their last winner
		local o = rematch.offers[me.id]
		local winnerPlayer = o and Players:GetPlayerByUserId(o.winner)
		local winner = winnerPlayer and HeroService.get(winnerPlayer)
		local winnerId, why = RematchRules.ask(P.rematch, rematch, me.id, now, {
			flagged = FlagService.flagged(me),
			here = winner ~= nil,
		})
		if not winnerId or not winner or not winnerPlayer then
			rematchNo(player, why or "none")
			return
		end
		Net.fire("Toast", player, { id = "rematchSent", name = winner.name })
		-- a winner who muted this player never hears it (the loser is not told: muting stays private)
		local profile = DataService.get(winnerPlayer)
		if profile and table.find(profile.mutes, player.UserId) then
			RematchRules.decline(rematch, winner.id, me.id)
			return
		end
		Net.fire(
			"RematchAsk",
			winnerPlayer,
			{ from = player.UserId, name = me.name, life = P.rematch.answer }
		)
	elseif userId then
		local loserPlayer = Players:GetPlayerByUserId(userId)
		local loser = loserPlayer and HeroService.get(loserPlayer)
		if act == 3 or not loser or not loserPlayer then
			RematchRules.decline(rematch, me.id, userId)
			if act == 2 then
				rematchNo(player, "gone")
			end
			return
		end
		local ok, why = RematchRules.accept(
			P.rematch,
			rematch,
			me.id,
			loser.id,
			now,
			FlagService.flagged(me) and FlagService.flagged(loser)
		)
		if not ok then
			rematchNo(player, why or "late")
			return
		end
		Net.fire("Toast", player, { id = "rematchOn", name = loser.name })
		Net.fire("Toast", loserPlayer, { id = "rematchOn", name = me.name })
		showSpot(player, loser)
		showSpot(loserPlayer, me)
	end
end

local function initRematch()
	Net.on("PvpRematch", onRematch)
	-- (required here, not at the top: DeathService requires this module)
	local DeathService = require(script.Parent.DeathService) :: any
	DeathService.PvpDefeat:Connect(FlagService.rematchOffer)
	HeroService.Removed:Connect(function(hero)
		RematchRules.forget(P.rematch, rematch, hero.id, os.clock())
	end)
end

local function tick()
	local now = os.clock()
	local c = crater
	for _, hero in HeroService.all() do
		if not hero.player then
			continue
		end
		local f = FlagService.flag(hero)
		local pos = HeroService.position(hero)
		if c and pos then
			local inside = hero.alive
				and not hero.scene
				and pos.Y < POCKET_Y
				and PvpRules.inCrater(c.centre, c.size, pos.X, pos.Z)
			local changed = PvpRules.craterStep(Config, f, inside, hero.level, now)
			if changed == "in" then
				Net.fire("Toast", hero.player, { id = "craterIn" })
			end
		end
		FlagService.send(hero)
	end
end

function FlagService.init()
	for _, lm in CityBuilder.world.landmarks do
		if lm.id == P.crater.id then
			crater = { centre = lm.centre, size = lm.size }
		end
	end
	Net.on("FlagSet", onSet)
	Net.on("CraterLeave", onLeave)
	initRematch()
	HeroService.Spawned:Connect(function(hero)
		local f = FlagService.flag(hero)
		PvpRules.protect(Config, f, os.clock())
		FlagService.send(hero, true)
	end)
	HeroService.Defeated:Connect(function(hero)
		PvpRules.newLife(FlagService.flag(hero))
	end)
	HeroService.Leveled:Connect(function(hero)
		FlagService.send(hero, true) -- level 10 shows the flag button
	end)
	HeroService.Removed:Connect(function(hero)
		task.delay(Config.Pvp.combatLog.window + 1, function()
			if not HeroService.byId(hero.id) then
				flags[hero.id] = nil
				lastBy[hero.id] = nil
				shown[hero.id] = nil
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		player:SetAttribute("Pvp", nil)
	end)
	local acc = 0
	RunService.Heartbeat:Connect(FrameProf.wrap("FlagService", function(dt)
		acc += dt
		if acc >= 0.25 then
			acc = 0
			tick()
		end
	end))
end

return FlagService
