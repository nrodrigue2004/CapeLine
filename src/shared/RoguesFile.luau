--!strict
-- RoguesFile: the Journal's Rogues File as pure rules (spec: Collections and records > Rogues File), so
-- RoguesService, Ui.RoguesPage and the Lune tests agree:
-- * the pages, built from Config.Rogues over the game's own data (Config.Enemies, Config.SideQuests' finales,
--   Config.Boss and the bosses' name cards), each with its fixed bit in profile.rogues;
-- * which page a beaten robot kind, a won side quest finale or a beaten world boss fills, and when a boss
--   win is a gold page;
-- * marking a page beaten: its bit, and its log row { first day (UTC day number), times beaten, the level
--   it was first beaten at } in profile.roguesLog[tostring(bit)];
-- * the counts, the milestone rewards due, the outline's hint and the first-beaten date;
-- * validate(): unique bits inside their ranges and the save's words, every robot kind, finale and boss
--   covered (tests/rogues_test.luau).

local Bits = if script
	then require(script.Parent.ProfileSchema).Bits
	else (require :: any)("./ProfileSchema").Bits

local RoguesFile = {}

RoguesFile.WORDS = 4 -- profile.rogues: ProfileSchema.SMALL_WORDS 32-bit words
RoguesFile.BITS = RoguesFile.WORDS * 32

export type Entry = {
	bit: number,
	group: string, -- robots, fakes, villains, bosses
	id: string,
	name: string,
	title: string,
	blurb: string,
	where: string,
	kind: string?, -- the Config.Enemies kind it fills from (robots and fakes), or a villain's finale foe
	dress: string?, -- a villain's finale dress (Config.SideQuests.dress)
	chain: string?, -- a villain's side quest chain id
	phase: number?, -- a villain's finale phase (2 = the encore)
	boss: string?, -- a boss's Config.Boss id
	gold: number?, -- a boss's gold page bit
	colors: { { number } }, -- the portrait: suit, trim, eye (PLACEHOLDER ART)
}

export type LogRow = { number } -- { first UTC day, times beaten, level first beaten at }

local cache: { [any]: { Entry } } = {}

local GREY = { { 90, 90, 100 }, { 160, 160, 170 }, { 255, 200, 80 } }

local function bodyColors(body: any): { { number } }
	if type(body) ~= "table" then
		return GREY
	end
	return { body.suit or GREY[1], body.trim or GREY[2], body.eye or GREY[3] }
end

-- A chain's finale goal (the hero's goal, or the villain's on a one-side line)
local function finaleGoal(chain: any): any?
	local steps = chain and chain.steps
	local last = steps and steps[#steps]
	if type(last) ~= "table" then
		return nil
	end
	local g = if type(last.hero) == "table" then last.hero else last.villain
	return if type(g) == "table" and g.kind == "finale" then g else nil
end

local function chainById(Config: any, id: string): any?
	for _, c in Config.SideQuests.chains do
		if c.id == id then
			return c
		end
	end
	return nil
end

-- The finale foe of a villain page: (the foe's goal table, the chain), or nil
local function villainFoe(Config: any, row: any): (any?, any?)
	local chain = chainById(Config, row.chain)
	local goal = finaleGoal(chain)
	if not goal then
		return nil, chain
	end
	if (row.phase or 1) >= 2 then
		return goal.encore, chain
	end
	return goal, chain
end

-- Every page in book order (robots, fakes, villains, bosses)
function RoguesFile.list(Config: any): { Entry }
	local hit = cache[Config]
	if hit then
		return hit
	end
	local R = Config.Rogues
	local E = Config.Enemies
	local out: { Entry } = {}
	for _, row in R.robots do
		local def = E[row.kind]
		table.insert(out, {
			bit = row.bit,
			group = "robots",
			id = row.kind,
			name = if def then def.name else row.kind,
			title = "",
			blurb = row.blurb,
			where = row.where,
			kind = row.kind,
			colors = bodyColors(def and def.body),
		})
	end
	for _, row in R.fakes do
		local def = E[row.kind]
		local title = row.title or (def and def.fake and def.fake.title) or ""
		table.insert(out, {
			bit = row.bit,
			group = "fakes",
			id = row.kind,
			name = if def then def.name else row.kind,
			title = title,
			blurb = row.blurb,
			where = row.where,
			kind = row.kind,
			colors = bodyColors(def and def.body),
		})
	end
	for _, row in R.villains do
		local foe, chain = villainFoe(Config, row)
		local goal = finaleGoal(chain)
		local dress = foe and foe.dress and Config.SideQuests.dress[foe.dress]
		local name, title = row.id, ""
		if dress then
			name, title = dress.name, dress.title or ""
		elseif (row.phase or 1) == 1 and goal and goal.encore and goal.card then
			name, title = goal.card.name, goal.card.title or ""
		elseif chain and chain.villain then
			name, title = chain.villain.name, chain.villain.title or ""
		end
		local def = foe and E[foe.enemy]
		table.insert(out, {
			bit = row.bit,
			group = "villains",
			id = row.id,
			name = name,
			title = title,
			blurb = row.blurb,
			where = if chain then "Side quest: " .. chain.name else "A side quest",
			kind = foe and foe.enemy,
			dress = foe and foe.dress,
			chain = row.chain,
			phase = row.phase or 1,
			colors = bodyColors(if dress then dress.body else def and def.body),
		})
	end
	for _, row in R.bosses do
		local b = Config.Boss.bosses[row.boss]
		table.insert(out, {
			bit = row.bit,
			group = "bosses",
			id = row.boss,
			name = if b then b.name else row.boss,
			title = Config.Cinema.nameCard.titles[row.boss] or "",
			blurb = row.blurb,
			where = row.where,
			boss = row.boss,
			gold = row.gold,
			colors = row.colors or GREY,
		})
	end
	cache[Config] = out
	return out
end

function RoguesFile.byBit(Config: any, bit: number): Entry?
	for _, e in RoguesFile.list(Config) do
		if e.bit == bit then
			return e
		end
	end
	return nil
end

-- The robot or fake page a beaten Config.Enemies kind fills (nil: a finale suit, filled by its finale)
function RoguesFile.forKind(Config: any, kind: string): Entry?
	for _, e in RoguesFile.list(Config) do
		if (e.group == "robots" or e.group == "fakes") and e.kind == kind then
			return e
		end
	end
	return nil
end

-- The villain pages a won side quest finale fills (its villain, and its encore's)
function RoguesFile.forChain(Config: any, chainId: string): { Entry }
	local out = {}
	for _, e in RoguesFile.list(Config) do
		if e.group == "villains" and e.chain == chainId then
			table.insert(out, e)
		end
	end
	return out
end

function RoguesFile.forBoss(Config: any, bossId: string): Entry?
	for _, e in RoguesFile.list(Config) do
		if e.group == "bosses" and e.boss == bossId then
			return e
		end
	end
	return nil
end

-- A boss win that earns the gold page: beaten, in a fight at the gold level or higher, at a gold tier
function RoguesFile.isGold(Config: any, tier: any, defeated: boolean, fightLevel: number?): boolean
	local g = Config.Rogues.gold
	return defeated == true
		and type(tier) == "string"
		and g.tiers[tier] == true
		and type(fightLevel) == "number"
		and fightLevel >= g.level
end

-- Mark a page beaten (its bit and its log row). True when it is new: its bit was off, or it has no log row
-- yet (BossService sets a boss's bit itself just before its Rewarded signal)
function RoguesFile.beat(
	Config: any,
	words: { number },
	log: { [string]: LogRow },
	bit: number,
	day: number,
	level: number
): boolean
	if bit < 0 or bit >= RoguesFile.BITS then
		return false
	end
	local key = tostring(bit)
	local row = log[key]
	local fresh = not Bits.get(words, bit) or type(row) ~= "table"
	Bits.set(words, bit)
	if type(row) ~= "table" then
		row = { math.max(0, math.floor(day)), 0, math.max(0, math.floor(level)) }
		log[key] = row
	end
	row[2] = math.min(Config.Rogues.countMax, (row[2] or 0) + 1)
	return fresh
end

-- (pages beaten, pages in the book); gold pages are extra and not counted here
function RoguesFile.count(Config: any, words: { number }): (number, number)
	local n, total = 0, 0
	for _, e in RoguesFile.list(Config) do
		total += 1
		if Bits.get(words, e.bit) then
			n += 1
		end
	end
	return n, total
end

-- (gold pages earned, gold pages there are)
function RoguesFile.goldCount(Config: any, words: { number }): (number, number)
	local n, total = 0, 0
	for _, e in RoguesFile.list(Config) do
		if e.gold then
			total += 1
			if Bits.get(words, e.gold) then
				n += 1
			end
		end
	end
	return n, total
end

-- How many pages a milestone asks for
function RoguesFile.need(Config: any, m: any): number
	if m.all then
		return #RoguesFile.list(Config)
	end
	return m.n
end

-- The milestones reached but not yet paid, in order
function RoguesFile.due(Config: any, words: { number }): { any }
	local n = RoguesFile.count(Config, words)
	local out = {}
	for _, m in Config.Rogues.milestones do
		if n >= RoguesFile.need(Config, m) and not Bits.get(words, m.bit) then
			table.insert(out, m)
		end
	end
	return out
end

-- The first milestone not reached yet (nil when all are)
function RoguesFile.nextMilestone(Config: any, words: { number }): any?
	local n = RoguesFile.count(Config, words)
	for _, m in Config.Rogues.milestones do
		if n < RoguesFile.need(Config, m) then
			return m
		end
	end
	return nil
end

-- The lowest level a robot joins open-world fights at (Config.Enemies.variety swaps), or nil
local function swapLevel(Config: any, kind: string?): number?
	local v = Config.Enemies.variety
	if not kind or not v or not v.on then
		return nil
	end
	local lo: number? = nil
	for _, sw in v.swaps do
		if sw.kind == kind and (lo == nil or sw.level < lo) then
			lo = sw.level
		end
	end
	return lo
end

-- The outline's hint: where to meet it (a robot that swaps into street fights says from which level)
function RoguesFile.where(Config: any, e: Entry): string
	local lvl = if e.group == "robots" then swapLevel(Config, e.kind) else nil
	if lvl and lvl > 1 then
		return string.format("%s from level %d", e.where, lvl)
	end
	return e.where
end

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

-- A UTC day number (os.time() // 86400) as "18 Nov 2026" (the civil calendar, no os.date)
function RoguesFile.dateText(day: number): string
	local z = math.floor(day) + 719468
	local era = z // 146097
	local doe = z - era * 146097
	local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
	local mp = (5 * doy + 2) // 153
	local d = doy - (153 * mp + 2) // 5 + 1
	local m = if mp < 10 then mp + 3 else mp - 9
	if m <= 2 then
		y += 1
	end
	return string.format("%d %s %d", d, MONTHS[m], y)
end

-- A page's beaten count as shown ("999+" past 999)
function RoguesFile.countText(n: number): string
	if n > 999 then
		return "999+"
	end
	return tostring(math.max(0, math.floor(n)))
end

-- What is wrong with the book (empty when nothing): bits unique, inside their group's range and the
-- save's words, clear of the milestone bits; every robot kind, chain finale foe and world boss has a page;
-- the boss bits match Config.Boss; every page has its text
function RoguesFile.validate(Config: any): { string }
	local R = Config.Rogues
	local errs = {}
	local used: { [number]: string } = {}
	local function take(bit: any, what: string, group: string)
		if type(bit) ~= "number" or bit % 1 ~= 0 then
			table.insert(errs, what .. ": no whole bit")
			return
		end
		if bit < 0 or bit >= RoguesFile.BITS then
			table.insert(errs, what .. ": bit " .. bit .. " outside the save's " .. RoguesFile.BITS)
		end
		if bit < R.firstBit[group] or bit > R.lastBit[group] then
			table.insert(errs, what .. ": bit " .. bit .. " outside the " .. group .. " range")
		end
		if used[bit] then
			table.insert(errs, what .. ": bit " .. bit .. " already used by " .. used[bit])
		end
		used[bit] = what
	end
	for _, e in RoguesFile.list(Config) do
		take(e.bit, e.id, e.group)
		if e.gold then
			take(e.gold, e.id .. " gold", "gold")
		end
		if type(e.blurb) ~= "string" or #e.blurb == 0 or #e.blurb > 80 then
			table.insert(errs, e.id .. ": a blurb of 1 to 80 characters")
		end
		if type(e.where) ~= "string" or #e.where == 0 then
			table.insert(errs, e.id .. ": an outline hint")
		end
		if e.name == "" then
			table.insert(errs, e.id .. ": a name from its name card")
		end
		if (e.group == "robots" or e.group == "fakes") and not Config.Enemies[e.kind or ""] then
			table.insert(errs, e.id .. ": not a Config.Enemies kind")
		end
		if e.group == "villains" and not e.kind then
			table.insert(errs, e.id .. ": no finale foe in chain " .. tostring(e.chain))
		end
	end
	for _, m in R.milestones do
		take(m.bit, "milestone " .. tostring(m.n or "all"), "milestones")
	end
	-- every robot kind: its own page, or the finale foe of a villain page
	local covered: { [string]: boolean } = {}
	for _, e in RoguesFile.list(Config) do
		if e.kind then
			covered[e.kind] = true
		end
	end
	for _, kind in Config.Enemies.order do
		if not covered[kind] then
			table.insert(errs, "the robot kind " .. kind .. " has no page")
		end
	end
	-- every live chain's finale foes
	for _, chain in Config.SideQuests.chains do
		local goal = finaleGoal(chain)
		if not chain.dev and goal then
			local pages = RoguesFile.forChain(Config, chain.id)
			local want = if goal.encore then 2 else 1
			if #pages ~= want then
				table.insert(
					errs,
					string.format("chain %s: %d villain pages, want %d", chain.id, #pages, want)
				)
			end
		end
	end
	-- every world boss, on its Config.Boss bit
	for _, id in Config.Boss.order do
		local e = RoguesFile.forBoss(Config, id)
		local b = Config.Boss.bosses[id]
		if not e then
			table.insert(errs, "the boss " .. id .. " has no page")
		elseif b and e.bit ~= b.rogues then
			table.insert(errs, "the boss " .. id .. "'s page is not on its Config.Boss rogues bit")
		end
	end
	return errs
end

return RoguesFile
