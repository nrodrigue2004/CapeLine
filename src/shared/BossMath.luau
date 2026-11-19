--!strict
-- BossMath: world boss numbers as pure functions (spec: World boss rules table; Drops > world boss rows).
-- HP at the start, the phase from the HP share, the schedule, contribution scores, reward tiers and the
-- reward list. BossSim runs the fight itself; BossService wires both to the game.

local BossMath = {}

-- (1 + 0.1 x (L - 1)): the same level scale robots use
local function levelScale(Config: any, level: number): number
	return 1 + Config.Enemies.scale.hpPerLevel * (level - 1)
end

-- Max HP: (60,000 + 4,000 per hero near at the start) at level 20, scaled to the median level, minus the
-- Raid prep weakening (3% a clear, at most 15%)
function BossMath.maxHp(Config: any, heroesNear: number, medianLevel: number, prepCleared: number): number
	local b = Config.Boss
	local base = b.hp.base + b.hp.perHero * math.max(1, heroesNear)
	local scaled = base * levelScale(Config, medianLevel) / levelScale(Config, b.hp.atLevel)
	local weaken = math.min(b.prep.weakenMax, b.prep.weakenEach * math.max(0, prepCleared))
	return math.floor(scaled * (1 - weaken) + 0.5)
end

-- The War-Frame (mission 6): 36,000 HP at level 20, scaled by the party's median level like any robot
function BossMath.warframeHp(Config: any, partyLevel: number): number
	local w = Config.Story.warframe
	return math.floor(w.hp * levelScale(Config, partyLevel) / levelScale(Config, w.atLevel) + 0.5)
end

-- Phase 1 above 66%, 2 above 33%, then 3
function BossMath.phase(Config: any, hpShare: number): number
	local p = Config.Boss.phases
	if hpShare > p[1] then
		return 1
	elseif hpShare > p[2] then
		return 2
	end
	return 3
end

-- Seconds from a boss ending to the next one starting (rng: :range)
function BossMath.nextDelay(Config: any, rng: any): number
	local e = Config.Boss.schedule.every
	return rng:range(e[1], e[2])
end

-- A player who has never seen a boss joined at `now`: the next boss is no later than 6 minutes away
function BossMath.clampForNewPlayer(Config: any, startAt: number, now: number): number
	return math.min(startAt, now + Config.Boss.schedule.firstClamp)
end

export type Ledger = { [number]: { damage: number, support: number, objectives: number } }

-- The ledger without heroes who left the server (here(id) false): they no longer take an MVP or Contributor
-- slot, nor move the median, at the fight's end or in the live standings (2026-11-18 fix)
function BossMath.present(ledger: Ledger, here: (number) -> boolean): Ledger
	local out = {}
	for id, l in ledger do
		if here(id) then
			out[id] = l
		end
	end
	return out
end

-- Contribution scores: 50% damage share + 30% support share + 20% objective share
function BossMath.scores(Config: any, ledger: Ledger): { [number]: number }
	local w = Config.Boss.contribution
	local td, ts, to = 0, 0, 0
	for _, l in ledger do
		td += l.damage
		ts += l.support
		to += l.objectives
	end
	local out = {}
	for id, l in ledger do
		local s = 0
		if td > 0 then
			s += w.damage * l.damage / td
		end
		if ts > 0 then
			s += w.support * l.support / ts
		end
		if to > 0 then
			s += w.objectives * l.objectives / to
		end
		out[id] = s
	end
	return out
end

local function median(list: { number }): number
	if #list == 0 then
		return 0
	end
	local s = table.clone(list)
	table.sort(s)
	local mid = (#s + 1) / 2
	return (s[math.floor(mid)] + s[math.ceil(mid)]) / 2
end

-- Tiers: "mvp" (top 3), "contributor" (top 50%), "participant" (10% of the median or more), "floor"
-- (took part, below that: the 25% floor). Only heroes with a score above 0 get a tier. Returns the tiers
-- and the ids in rank order.
function BossMath.tiers(Config: any, scores: { [number]: number }): ({ [number]: string }, { number })
	local c = Config.Boss.contribution
	local ranked = {}
	local values = {}
	for id, s in scores do
		if s > 0 then
			table.insert(ranked, id)
			table.insert(values, s)
		end
	end
	table.sort(ranked, function(a, b)
		if scores[a] == scores[b] then
			return a < b
		end
		return scores[a] > scores[b]
	end)
	local med = median(values)
	local top = math.ceil(#ranked * c.contributorTop)
	local out = {}
	for i, id in ranked do
		if i <= c.mvp then
			out[id] = "mvp"
		elseif i <= top then
			out[id] = "contributor"
		elseif scores[id] >= med * c.participantShare then
			out[id] = "participant"
		else
			out[id] = "floor"
		end
	end
	return out, ranked
end

local EARN = {
	mvp = "bossMvp",
	contributor = "bossContributor",
	participant = "bossParticipant",
	floor = "bossParticipant",
}
local DROP = { mvp = "bossMvp", contributor = "bossContributor", participant = "bossParticipant" }
BossMath.EARN = EARN

-- Did a hero with this tier take part? Tiers are strings ("mvp" .. "floor"); anything else (nil, "", a
-- number) is no (2026-11-18 fix: PassService compared the string with 1 and threw out of the reward loop)
function BossMath.tookPart(tier: any): boolean
	return type(tier) == "string" and EARN[tier] ~= nil
end

export type Reward = {
	earn: string, -- the Economy.earn row
	share: number, -- how much of that row is paid
	drops: { string }, -- Loot sources rolled (the MVP also rolls the Contributor pieces)
	style: boolean, -- rolls for the boss's cosmetic
	page: boolean, -- the Rogues File page
	fame: boolean, -- the tier's Fame or Infamy (EconomyService.Earned); a retreat pays none
}

-- What a tier earns. defeated = false: the boss retreated (Credits consolation only, no Fame)
function BossMath.reward(Config: any, tier: string, defeated: boolean): Reward
	local r = Config.Boss.rewards
	if not defeated then
		return {
			earn = EARN[tier],
			share = if tier == "floor" then 0 else r.consolation,
			drops = {},
			style = false,
			page = false,
			fame = false,
		}
	end
	if tier == "floor" then
		return {
			earn = EARN.floor,
			share = Config.Boss.contribution.floor,
			drops = {},
			style = false,
			page = true,
			fame = true,
		}
	end
	local drops = { DROP[tier] }
	if tier == "mvp" then
		table.insert(drops, 1, DROP.contributor)
	end
	return { earn = EARN[tier], share = 1, drops = drops, style = true, page = true, fame = true }
end

-- Does this tier get the boss's cosmetic, and is it the shiny one? (rng: :chance)
function BossMath.styleRoll(Config: any, tier: string, rng: any): (boolean, boolean)
	local r = Config.Boss.rewards
	local chance = r.styleChance[tier] or 0
	if chance <= 0 or not rng:chance(chance) then
		return false, false
	end
	return true, rng:chance(r.shiny)
end

-- A local offset (x right, y up, -z forward) turned by the boss's yaw (Roblox: CFrame.Angles(0, yaw, 0))
function BossMath.worldOffset(yaw: number, ox: number, oy: number, oz: number): (number, number, number)
	local c, s = math.cos(yaw), math.sin(yaw)
	return ox * c + oz * s, oy, -ox * s + oz * c
end

-- fix-hud: does this device show the boss's big banner and HP bar? s: the Boss.State packet (state, num, x, z),
-- pos: the hero's {X, Z} (nil: not spawned), listed: on the fight's contribution list (a tier this fight),
-- was: it showed last time (a margin to leave, so the bar never flickers at the edge). Returns "bar" (near or
-- listed), "corner" (a banner or fight far away: the radar's timer and the marker only) or "none".
function BossMath.hudNear(
	Config: any,
	s: any,
	px: number?,
	pz: number?,
	listed: boolean,
	was: boolean
): string
	local B = Config.Boss
	local live = s.state == 1 or s.state == 2 or s.state == 3
	if not live then
		return "none"
	end
	if listed and s.state == 3 then
		return "bar"
	end
	if px == nil or pz == nil or type(s.x) ~= "number" or type(s.z) ~= "number" then
		return "corner"
	end
	local def
	for _, b in B.bosses do
		if b.num == s.num then
			def = b
		end
	end
	local r = math.max(B.hud.near, def and def.arenaRadius or 0) + (if was then B.hud.leave else 0)
	local dx, dz = px - s.x, pz - s.z
	return if dx * dx + dz * dz <= r * r then "bar" else "corner"
end

return BossMath
