--!strict
-- PvpRules: every PvP, death and anti-farming rule as plain data (spec: PvP, death and anti-abuse rules;
-- Stat compression; Defeat and death; Anti-farming; PvP rewards; Fame and Infamy). The M8 services hold one
-- Flag per hero and one Ledger per server and ask these functions; nothing here touches Roblox, so Lune runs
-- every rule in tests.
-- * Flag: off by default, on at once (at most every 5 s, level 10+, not in a safe area), off only after 60 s
--   with no PvP damage and never inside the Comet Crater. The Crater forces PvP after a 5 s warning.
-- * Hits: both flags are read at the moment of the hit, safe areas block both ways, spawn protection (5 s,
--   ended by attacking) blocks the target, allies never hit each other.
-- * Support: an unflagged player cannot heal, shield or buff a flagged player who is in PvP combat.
-- * Compression: Power and Health use the level baseline formula; Focus, Precision and Resolve count at a
--   quarter; supers deal 60%.
-- * Rewards: first 2 wins on a target in 30 min pay, nothing 10+ levels down, same side half, boss fights
--   half, 3-and-3 trades in 60 min pay nothing both ways and are logged.

local PvpRules = {}

local NEVER = -1e9

local function P(config: any): any
	return config.Pvp
end

---------------------------------------------------------------------------
-- The flag
---------------------------------------------------------------------------

export type Flag = {
	on: boolean, -- the player's own switch
	setAt: number, -- last accepted switch
	pvpAt: number, -- last PvP damage dealt or taken
	crater: string, -- "out", "warn" or "in"
	warnUntil: number,
	protectUntil: number, -- spawn protection
	protectUsed: boolean, -- this life's protection was already given
}

function PvpRules.newFlag(): Flag
	return {
		on = false,
		setAt = NEVER,
		pvpAt = NEVER,
		crater = "out",
		warnUntil = 0,
		protectUntil = 0,
		protectUsed = false,
	}
end

export type SetContext = { level: number, safe: boolean, now: number }

-- May the player switch the flag to `want`? Returns ok, reason ("level", "rate", "safe", "combat",
-- "crater", "same").
function PvpRules.canSet(config: any, f: Flag, want: boolean, ctx: SetContext): (boolean, string?)
	local p = P(config)
	if want == f.on then
		return false, "same"
	end
	if ctx.level < p.minLevel then
		return false, "level"
	end
	if ctx.now - f.setAt < p.flag.setEvery then
		return false, "rate"
	end
	if want then
		if ctx.safe then
			return false, "safe"
		end
		return true, nil
	end
	if f.crater ~= "out" then
		return false, "crater"
	end
	if ctx.now - f.pvpAt < p.flag.offAfter then
		return false, "combat"
	end
	return true, nil
end

function PvpRules.set(f: Flag, want: boolean, now: number)
	f.on = want
	f.setAt = now
end

-- Seconds until the flag may turn off (0 = now)
function PvpRules.offIn(config: any, f: Flag, now: number): number
	return math.max(0, P(config).flag.offAfter - (now - f.pvpAt))
end

-- Is this hero open to PvP right now? (its own flag, or forced by the Crater at level 10+)
function PvpRules.flagged(config: any, f: Flag, level: number): boolean
	if f.on then
		return true
	end
	return f.crater == "in" and level >= P(config).minLevel
end

function PvpRules.notePvp(f: Flag, now: number)
	f.pvpAt = now
end

function PvpRules.inPvpCombat(config: any, f: Flag, now: number): boolean
	return now - f.pvpAt < P(config).flag.combat
end

-- The Comet Crater: a 400 x 400 square around the landmark's centre
function PvpRules.inCrater(centre: { x: number, z: number }, size: number, x: number, z: number): boolean
	local h = size / 2
	return math.abs(x - centre.x) <= h and math.abs(z - centre.z) <= h
end

-- The Crater as a hero walks in and out: entering starts a 5 s warning (the ring and the Leave button),
-- staying past it forces PvP; leaving resets it. Heroes below level 10 never pass "warn" (never forced).
-- Returns the new state when it changed.
function PvpRules.craterStep(config: any, f: Flag, inside: boolean, level: number, now: number): string?
	local before = f.crater
	if not inside then
		f.crater = "out"
	elseif f.crater == "out" then
		f.crater = "warn"
		f.warnUntil = now + P(config).crater.warn
	elseif f.crater == "warn" and now >= f.warnUntil and level >= P(config).minLevel then
		f.crater = "in"
	end
	return if f.crater ~= before then f.crater else nil
end

-- Spawn protection: once per life, from the respawn
function PvpRules.protect(config: any, f: Flag, now: number)
	if not f.protectUsed then
		f.protectUsed = true
		f.protectUntil = now + P(config).spawnProtect
	end
end

-- A new life (after a defeat): protection can be given again
function PvpRules.newLife(f: Flag)
	f.protectUsed = false
	f.protectUntil = 0
end

function PvpRules.endProtect(f: Flag)
	f.protectUntil = 0
end

function PvpRules.protected(f: Flag, now: number): boolean
	return now < f.protectUntil
end

---------------------------------------------------------------------------
-- Hits and support
---------------------------------------------------------------------------

export type Side = {
	id: number,
	flag: Flag,
	level: number,
	alive: boolean,
	safe: boolean, -- in a safe area (HQ, safehouse radius, mission pocket) or a story scene
}

-- May `a` damage `b` right now? Read at the moment of every hit, for every shape (bolts, areas, chains,
-- fields, channels, echoes). Returns ok, reason.
function PvpRules.canHit(config: any, a: Side, b: Side, allies: boolean, now: number): (boolean, string?)
	if a.id == b.id or not a.alive or not b.alive then
		return false, "self"
	end
	if not PvpRules.flagged(config, a.flag, a.level) or not PvpRules.flagged(config, b.flag, b.level) then
		return false, "flag"
	end
	if a.safe or b.safe then
		return false, "safe"
	end
	if PvpRules.protected(b.flag, now) then
		return false, "protected"
	end
	if allies then
		return false, "ally"
	end
	return true, nil
end

-- May `giver` heal, shield or buff `target`? An unflagged giver cannot help a flagged target in PvP combat,
-- and a flagged giver helps a flagged target in PvP combat only when they are allies.
function PvpRules.canSupport(config: any, giver: Side, target: Side, allies: boolean, now: number): boolean
	if giver.id == target.id then
		return true
	end
	local tFlag = PvpRules.flagged(config, target.flag, target.level)
	if not tFlag or not PvpRules.inPvpCombat(config, target.flag, now) then
		return true
	end
	return PvpRules.flagged(config, giver.flag, giver.level) and allies
end

---------------------------------------------------------------------------
-- Stat compression
---------------------------------------------------------------------------

-- effective = baseline x (1 + bonus x clamp(total / baseline - 1, 0, 1))
function PvpRules.compress(config: any, baseline: number, total: number): number
	if baseline <= 0 then
		return total
	end
	local over = math.clamp(total / baseline - 1, 0, 1)
	return baseline * (1 + P(config).compressBonus * over)
end

function PvpRules.level(config: any, level: number): number
	return math.min(level, P(config).levelCap)
end

-- Power in PvP: the level baseline (30 + 6 x L) against Power with gear Might
function PvpRules.power(config: any, level: number, might: number): number
	local s = config.Stats.power
	local L = PvpRules.level(config, level)
	local base = s.base + s.perLevel * L
	return PvpRules.compress(config, base, base + math.max(0, might))
end

-- Health in PvP: the class baseline at the level against the hero's real max health
function PvpRules.health(config: any, level: number, vitality: number, classId: string): number
	local s = config.Stats.health
	local class = config.Classes[classId]
	local mult = if class then class.healthMult else 1
	local L = PvpRules.level(config, level)
	local base = (s.base + s.perLevel * L) * mult
	local total = (s.base + s.perLevel * L + s.perVitality * math.max(0, vitality)) * mult
	return PvpRules.compress(config, base, total)
end

-- Focus, Precision and Resolve have no level baseline: their gear value counts at minorScale
function PvpRules.minor(config: any, value: number): number
	return value * P(config).minorScale
end

export type DamageContext = {
	power: number, -- the attacker's Power this hit was rolled with
	pvpPower: number, -- PvpRules.power for the attacker
	maxHealth: number, -- the target's real max health
	pvpHealth: number, -- PvpRules.health for the target
	super: boolean?,
}

-- Turn a PvE damage roll into PvP damage: compressed Power, damage scaled so the target dies in as many
-- hits as its compressed health would take, supers at 60%.
function PvpRules.damage(config: any, raw: number, ctx: DamageContext): number
	if raw <= 0 then
		return 0
	end
	local d = raw * (ctx.pvpPower / math.max(1, ctx.power))
	d *= ctx.maxHealth / math.max(1, ctx.pvpHealth)
	if ctx.super then
		d *= P(config).superMult
	end
	return d
end

-- How a Legendary perk works with PvP: 1 full, 0.5 half, 0 off (Config.Gear.perks[perk].pvp)
function PvpRules.perk(config: any, perk: string): number
	local row = config.Gear.perks[perk]
	if not row or row.pvp == "off" then
		return 0
	end
	return if row.pvp == "half" then 0.5 else 1
end

---------------------------------------------------------------------------
-- Defeat, loss and rewards
---------------------------------------------------------------------------

-- Credits a PvP defeat moves: 5% of on-hand Credits above 500, at most 300
function PvpRules.loss(config: any, onHand: number): number
	local l = P(config).loss
	return math.min(l.max, math.floor(math.max(0, onHand - l.buffer) * l.share))
end

export type Win = { w: number, l: number, t: number }
export type Ledger = { wins: { Win }, review: { { a: number, b: number, t: number } } }

function PvpRules.newLedger(): Ledger
	return { wins = {}, review = {} }
end

local function prune(config: any, ledger: Ledger, now: number)
	local keep = P(config).farm.altWindow
	local i = 1
	while i <= #ledger.wins do
		if now - ledger.wins[i].t > keep then
			table.remove(ledger.wins, i)
		else
			i += 1
		end
	end
end

local function count(ledger: Ledger, w: number, l: number, since: number): number
	local n = 0
	for _, row in ledger.wins do
		if row.w == w and row.l == l and row.t >= since then
			n += 1
		end
	end
	return n
end

export type WinContext = {
	winnerLevel: number,
	loserLevel: number,
	sameSide: boolean,
	inBoss: boolean,
}

-- Record a win and return the pay factor (0, 0.25, 0.5 or 1) and why it was cut. A 3-and-3 trade inside
-- 60 minutes pays zero both ways and lands in ledger.review once per pair.
function PvpRules.win(
	config: any,
	ledger: Ledger,
	winner: number,
	loser: number,
	now: number,
	ctx: WinContext
): (number, string?)
	local f = P(config).farm
	prune(config, ledger, now)
	local before = count(ledger, winner, loser, now - f.sameWindow)
	table.insert(ledger.wins, { w = winner, l = loser, t = now })
	local since = now - f.altWindow
	local ab = count(ledger, winner, loser, since)
	local ba = count(ledger, loser, winner, since)
	if ab >= f.altWins and ba >= f.altWins then
		local logged = false
		for _, r in ledger.review do
			if (r.a == winner and r.b == loser) or (r.a == loser and r.b == winner) then
				logged = true
			end
		end
		if not logged then
			table.insert(ledger.review, { a = winner, b = loser, t = now })
		end
		return 0, "trade"
	end
	-- a pair already logged keeps paying nothing for the hour
	for _, r in ledger.review do
		if
			((r.a == winner and r.b == loser) or (r.a == loser and r.b == winner))
			and now - r.t <= f.altWindow
		then
			return 0, "trade"
		end
	end
	if before >= f.sameTarget then
		return 0, "repeat"
	end
	if ctx.loserLevel <= ctx.winnerLevel - f.levelGap then
		return 0, "gap"
	end
	local m = 1
	local why = nil
	if ctx.sameSide then
		m *= f.sameSide
		why = "side"
	end
	if ctx.inBoss then
		m *= f.boss
		why = "boss"
	end
	return m, why
end

-- What a win pays at a factor: Credits 40 + 2 x target level and Fame 15, scaled (rounded down)
function PvpRules.reward(config: any, loserLevel: number, factor: number): (number, number)
	local r = P(config).reward
	local credits = (r.credits[1] + r.credits[2] * loserLevel) * factor
	return math.floor(credits), math.floor(r.fame * factor)
end

---------------------------------------------------------------------------
-- Downed and revive
---------------------------------------------------------------------------

function PvpRules.reviveTime(config: any, classId: string): number
	local d = P(config).downed
	return if classId == "Controller" then d.reviveWarden else d.reviveTime
end

---------------------------------------------------------------------------
-- Fame and Infamy
---------------------------------------------------------------------------

-- The rank (1 to 10) for a Fame total
function PvpRules.fameRank(config: any, points: number): number
	local rank = 1
	for i, row in P(config).fame.ranks do
		if points >= row.at then
			rank = i
		end
	end
	return rank
end

-- Fame for an earn action (incident, rescue, contract, mission, boss tiers, pvp); villains get 3 a rescue
function PvpRules.fameFor(config: any, action: string, side: string): number
	local f = P(config).fame
	if action == "rescue" and side == "villain" then
		return f.rescueVillain
	end
	local v = f[action]
	return if type(v) == "number" then v else 0
end

-- Points to the next rank, or nil at the top
function PvpRules.nextRank(config: any, points: number): number?
	local ranks = P(config).fame.ranks
	local r = PvpRules.fameRank(config, points)
	local nxt = ranks[r + 1]
	return if nxt then nxt.at else nil
end

return PvpRules
