--!strict
-- ContractPlan: Radiant contract rules as plain data (spec: Radiant contracts; Contract.Accept rules "Board
-- at safehouse, max 3"; Profile daily {day, contractsDone}). ContractService places the sites; this makes
-- the offers, checks accepting, counts progress and works out the pay.
-- * offers: board.offers contracts a hero's side can take (Vault job is villain only, Stakeout and Defusal
--   hero only), seeded by the hero and the 5-minute window, so a board shows the same offers until they
--   change. From level 40 an offer may be Heroic (Shared.HeroicRules), seeded the same way.
-- * A saved contract is { type, seed, level, got, heroic?, pick? }: the seed rebuilds its sites after a
--   rejoin; pick chooses a bounty's name and robot type from fixed lists (no free text).
-- * pay: Credits base + perLevel x L; Renown the type's own or the Economy contract row; the first 5
--   contracts each day pay x2 (a bonus, not a penalty after); Heroic x1.5 on top.

local Rng = if script then require(script.Parent.Rng) else (require :: any)("./Rng")
local HeroicRules = if script then require(script.Parent.HeroicRules) else (require :: any)("./HeroicRules")
local EnemyVariety = if script
	then require(script.Parent.EnemyVariety)
	else (require :: any)("./EnemyVariety")

local ContractPlan = {}

export type Saved = {
	type: string,
	seed: number,
	level: number,
	got: number,
	ox: number?, -- ox, oz: the board it came from
	oz: number?,
	heroic: boolean?,
	pick: number?, -- 1 to 12: a bounty's name (and its robot type)
}

function ContractPlan.allowed(cfg: any, side: string): { string }
	local out = {}
	for _, id in cfg.order do
		local t = cfg.types[id]
		if t.side == "both" or t.side == side then
			table.insert(out, id)
		end
	end
	return out
end

-- The offers on a board for a hero: window = floor(time / refresh); villain-side types a little likelier
-- at night (nightBoost). Config (optional): lets offers roll Heroic from level 40.
function ContractPlan.offers(
	cfg: any,
	heroId: number,
	side: string,
	window: number,
	level: number,
	night: boolean?,
	nightBoost: number?,
	Config: any?
): { Saved }
	local rng = Rng.new(Rng.hash(heroId, window, 7))
	local pool = ContractPlan.allowed(cfg, side)
	local out: { Saved } = {}
	for _ = 1, math.min(cfg.board.offers, #pool) do
		local weights, total = {}, 0
		for i, id in pool do
			local w = if night and cfg.types[id].side == "villain" then (nightBoost or 1.3) else 1
			weights[i] = w
			total += w
		end
		local r = rng:range(0, total)
		local pickIdx = #pool
		for i in pool do
			r -= weights[i]
			if r <= 0 then
				pickIdx = i
				break
			end
		end
		local id = table.remove(pool, pickIdx) :: string
		local offer: Saved = { type = id, seed = rng:nextInt32() % 2147483647, level = level, got = 0 }
		local t = cfg.types[id]
		if t.names then
			offer.pick = rng:int(1, #t.names)
		end
		if Config and HeroicRules.roll(Config, "contract", level, rng) then
			offer.heroic = true
		end
		table.insert(out, offer)
	end
	return out
end

-- Can this contract be accepted? Returns ok and a reason
function ContractPlan.canAccept(
	cfg: any,
	level: number,
	side: string,
	active: { Saved },
	offer: Saved?
): (boolean, string?)
	if level < cfg.board.minLevel then
		return false, "level"
	end
	if not offer then
		return false, "gone"
	end
	local t = cfg.types[offer.type]
	if not t or (t.side ~= "both" and t.side ~= side) then
		return false, "side"
	end
	if #active >= cfg.board.maxAccepted then
		return false, "full"
	end
	for _, c in active do
		if c.type == offer.type then
			return false, "same"
		end
	end
	return true, nil
end

function ContractPlan.goal(cfg: any, kind: string): number
	return cfg.types[kind].goal
end

-- Add progress; returns true when the contract is complete
function ContractPlan.progress(cfg: any, c: Saved, amount: number): boolean
	local goal = cfg.types[c.type].goal
	c.got = math.clamp(c.got + amount, 0, goal)
	return c.got >= goal
end

-- Credits and Renown before friend and Legacy bonuses, and the daily multiplier applied; Heroic on top
function ContractPlan.pay(
	Config: any,
	kind: string,
	level: number,
	doneToday: number,
	heroic: boolean?
): (number, number, number)
	local t = Config.Contracts.types[kind]
	local e = Config.Economy.earn.contract
	local b = Config.Economy.bonus
	local mult = if doneToday < b.firstContracts then b.firstContractMult else 1
	local scale = Config.Economy.scale
	local credits = (t.credits[1] + t.credits[2] * level) * mult * scale.credits
	local rr = t.renown or e.renown
	local renown = (rr[1] + rr[2] * level) * mult * scale.renown
	local c, r = math.floor(credits + 0.5), math.floor(renown + 0.5)
	c, r = HeroicRules.pay(Config, c, r, heroic)
	return c, r, mult
end

-- A bounty's target: its name and robot type (the pick-th name; the type counted round from the pick
-- among the targets switched on and unlocked at the level; BruteBot when none are). ready(kind, level).
function ContractPlan.bounty(
	cfg: any,
	pick: number?,
	level: number,
	ready: (string, number) -> boolean
): (string, string)
	local t = cfg.types.Bounty
	local p = math.clamp(math.floor(pick or 1), 1, #t.names)
	local list = {}
	for _, kind in t.targets do
		if ready(kind, level) then
			table.insert(list, kind)
		end
	end
	local kind = if #list > 0 then list[(p - 1) % #list + 1] else "BruteBot"
	return t.names[p], kind
end

-- The board's title and line for a contract (fixed strings with fixed names put in). enemyName(kind) gives
-- a robot type's display name; ready as for bounty.
function ContractPlan.title(
	cfg: any,
	c: Saved,
	side: string,
	enemyName: (string) -> string,
	ready: (string, number) -> boolean
): (string, string)
	local t = cfg.types[c.type]
	local name = if side == "villain" and t.villainName then t.villainName else t.name
	local text = if side == "villain" and t.villainText then t.villainText else t.text
	if c.type == "Bounty" then
		local who, kind = ContractPlan.bounty(cfg, c.pick, c.level, ready)
		return name .. ": " .. who, string.format(text, who, enemyName(kind))
	elseif c.type == "RooftopCourier" then
		return name, string.format(text, t.timeLimit)
	elseif c.type == "GeneratorHold" then
		return name, string.format(text, t.goal)
	end
	return name, text
end

-- The usual ready check for a robot type at a level (on, and unlocked by Enemies.variety.swaps)
function ContractPlan.readyFor(Config: any): (string, number) -> boolean
	return function(kind: string, level: number): boolean
		if not EnemyVariety.enabled(Config, kind) then
			return false
		end
		for _, sw in Config.Enemies.variety.swaps do
			if sw.kind == kind then
				return level >= sw.level
			end
		end
		return true
	end
end

-- Protect the generator: seconds held after dt with or without a hero in the ring (it drains while empty,
-- never below 0 or past the goal)
function ContractPlan.holdTick(cfg: any, value: number, holding: boolean, dt: number): number
	local t = cfg.types.GeneratorHold
	local v = if holding then value + dt else value - t.drain * dt
	return math.clamp(v, 0, t.goal)
end

-- Rooftop courier: seconds left on the parcel's clock (nil before the parcel is grabbed); 0 is late
function ContractPlan.courierLeft(cfg: any, grabbedAt: number?, now: number): number?
	if not grabbedAt then
		return nil
	end
	return math.max(0, cfg.types.RooftopCourier.timeLimit - (now - grabbedAt))
end

-- Sabotage defusal: seconds left on a charge's fuse (it starts when the hero first comes near)
function ContractPlan.fuseLeft(cfg: any, wokeAt: number?, now: number): number?
	if not wokeAt then
		return nil
	end
	return math.max(0, cfg.types.Defusal.fuse - (now - wokeAt))
end

-- Keep a saved list sane (repair after load); maxLevel is the level cap (Config.Stats.levelCap)
function ContractPlan.repair(cfg: any, list: any, maxLevel: number): { Saved }
	local out: { Saved } = {}
	if type(list) ~= "table" then
		return out
	end
	local seen: { [string]: boolean } = {}
	for _, c in list do
		if type(c) == "table" and type(c.type) == "string" and cfg.types[c.type] and not seen[c.type] then
			seen[c.type] = true
			local t = cfg.types[c.type]
			local goal = t.goal
			table.insert(out, {
				type = c.type,
				seed = if type(c.seed) == "number" then math.floor(c.seed) % 2147483647 else 1,
				level = if type(c.level) == "number" then math.clamp(math.floor(c.level), 1, maxLevel) else 1,
				got = if type(c.got) == "number" then math.clamp(math.floor(c.got), 0, goal) else 0,
				ox = if type(c.ox) == "number" and math.abs(c.ox) < 5000 then c.ox else nil,
				oz = if type(c.oz) == "number" and math.abs(c.oz) < 5000 then c.oz else nil,
				heroic = if c.heroic == true then true else nil,
				pick = if t.names and type(c.pick) == "number"
					then math.clamp(math.floor(c.pick), 1, #t.names)
					else nil,
			})
			if #out >= cfg.board.maxAccepted then
				break
			end
		end
	end
	return out
end

return ContractPlan
