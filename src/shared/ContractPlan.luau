--!strict
-- ContractPlan: Radiant contract rules as plain data (spec: Radiant contracts; Contract.Accept rules "Board
-- at safehouse, max 3"; Profile daily {day, contractsDone}). ContractService places the sites; this makes
-- the offers, checks accepting, counts progress and works out the pay.
-- * offers: 3 contracts a hero's side can take (Vault job is villain only, Stakeout hero only), seeded by
--   the hero and the 5-minute window, so a board shows the same offers until they change.
-- * A saved contract is { type, seed, level, got }: the seed rebuilds its sites after a rejoin.
-- * pay: Credits base + perLevel x L; Renown the type's own or the Economy contract row; the first 5
--   contracts each day pay x2 (a bonus, not a penalty after).

local Rng = if script then require(script.Parent.Rng) else (require :: any)("./Rng")

local ContractPlan = {}

export type Saved = { type: string, seed: number, level: number, got: number, ox: number?, oz: number? } -- ox, oz: the board it came from

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
-- at night (nightBoost)
function ContractPlan.offers(
	cfg: any,
	heroId: number,
	side: string,
	window: number,
	level: number,
	night: boolean?,
	nightBoost: number?
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
		table.insert(out, { type = id, seed = rng:nextInt32() % 2147483647, level = level, got = 0 })
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

-- Credits and Renown before friend and Legacy bonuses, and the daily multiplier applied
function ContractPlan.pay(
	Config: any,
	kind: string,
	level: number,
	doneToday: number
): (number, number, number)
	local t = Config.Contracts.types[kind]
	local e = Config.Economy.earn.contract
	local b = Config.Economy.bonus
	local mult = if doneToday < b.firstContracts then b.firstContractMult else 1
	local credits = (t.credits[1] + t.credits[2] * level) * mult
	local rr = t.renown or e.renown
	local renown = (rr[1] + rr[2] * level) * mult
	return math.floor(credits + 0.5), math.floor(renown + 0.5), mult
end

-- Keep a saved list sane (repair after load)
function ContractPlan.repair(cfg: any, list: any): { Saved }
	local out: { Saved } = {}
	if type(list) ~= "table" then
		return out
	end
	local seen: { [string]: boolean } = {}
	for _, c in list do
		if type(c) == "table" and type(c.type) == "string" and cfg.types[c.type] and not seen[c.type] then
			seen[c.type] = true
			local goal = cfg.types[c.type].goal
			table.insert(out, {
				type = c.type,
				seed = if type(c.seed) == "number" then math.floor(c.seed) % 2147483647 else 1,
				level = if type(c.level) == "number" then math.clamp(math.floor(c.level), 1, 40) else 1,
				got = if type(c.got) == "number" then math.clamp(math.floor(c.got), 0, goal) else 0,
				ox = if type(c.ox) == "number" and math.abs(c.ox) < 5000 then c.ox else nil,
				oz = if type(c.oz) == "number" and math.abs(c.oz) < 5000 then c.oz else nil,
			})
			if #out >= cfg.board.maxAccepted then
				break
			end
		end
	end
	return out
end

return ContractPlan
