--!strict
-- IncidentPlan: the rules of incidents as plain data (spec: Incident spawner; Incidents table). The server's
-- IncidentService places the robots, citizens and props; this decides which template, rolls its steps,
-- tracks progress, the medal and the hold speed, so Lune tests every rule.
-- * pick: a template the hero's side can play at a spot kind that exists near them; villain-side templates
--   are 30% likelier at night; never the same template twice in a row for a hero when there is a choice;
--   Raid prep only while a boss counts down (and then it is preferred). Given Config and the zone level, a
--   template whose `requires` robot types are switched off or not unlocked yet is skipped.
-- * new: an incident with its steps rolled (robot counts) and a deadline. A row's robot type that is off
--   or not unlocked at the level uses the row's fallback (or is dropped). Heroic (Shared.HeroicRules) adds a
--   robot to each squad step and some time.
-- * advance: progress on the current step; returns "step" when a step finishes, "done" after the last.
-- * shell / endBarrage: the barrage step's blocks and misses.

local HeroicRules = if script then require(script.Parent.HeroicRules) else (require :: any)("./HeroicRules")
local EnemyVariety = if script
	then require(script.Parent.EnemyVariety)
	else (require :: any)("./EnemyVariety")

local IncidentPlan = {}

-- Every step kind the server knows how to build (tests check each template uses only these)
IncidentPlan.KINDS = {
	"defeat",
	"rescue",
	"hold",
	"object",
	"runner",
	"nest",
	"leader",
	"find",
	"convoy",
	"barrage",
	"tug",
	"unmask", -- WP5: the Suspicious Hero's costumed fake (crack its mask)
}

-- A template's step rows for one side (WP5): a row with `side` runs only for that side's incidents, so a
-- both-sides template can end on a side-flavoured goal
function IncidentPlan.rows(t: any, side: string?): { any }
	local out = {}
	for _, row in t.steps do
		if row.side == nil or side == nil or row.side == side then
			table.insert(out, row)
		end
	end
	return out
end

-- WP5: the costumes an unmask row may wear at this level: its `dress` ids (Config.Incidents.dress) whose
-- suit is switched on and unlocked
function IncidentPlan.dresses(Config: any, row: any, level: number): { string }
	local out = {}
	for _, id in row.dress or {} do
		local d = Config.Incidents.dress and Config.Incidents.dress[id]
		if d and IncidentPlan.kindReady(Config, d.suit, level) then
			table.insert(out, id)
		end
	end
	return out
end

export type Step = {
	kind: string,
	need: number, -- robots to beat, citizens to carry, seconds to hold, 1 object, 1 runner, shells to block
	have: number,
	spawn: { { kind: string, n: number } }?, -- squad steps: what to spawn
	leader: string?, -- leader: the robot type that must fall
	missed: number?, -- barrage: shells that landed
	def: any, -- the template's step row
}

export type Incident = {
	tid: string,
	num: number,
	level: number,
	heroic: boolean,
	step: number,
	steps: { Step },
	started: number,
	deadline: number,
	done: boolean,
	failed: boolean,
}

-- The level a robot type unlocks at in open-world fights (Config.Enemies.variety.swaps); 1 for the first
-- robots, which every level has
function IncidentPlan.unlockLevel(Config: any, kind: string): number
	local v = Config.Enemies.variety
	for _, sw in (v and v.swaps) or {} do
		if sw.kind == kind then
			return sw.level
		end
	end
	return 1
end

-- May a fight at this level have this robot type? (switched on, and unlocked)
function IncidentPlan.kindReady(Config: any, kind: string, level: number): boolean
	return EnemyVariety.enabled(Config, kind) and level >= IncidentPlan.unlockLevel(Config, kind)
end

-- Can this template run at this level? Its `requires` types are on and unlocked, and its minLevel is met.
function IncidentPlan.available(cfg: any, Config: any, tid: string, level: number): boolean
	local t = cfg.templates[tid]
	if not t then
		return false
	end
	if t.minLevel and level < t.minLevel then
		return false
	end
	for _, kind in t.requires or {} do
		if not IncidentPlan.kindReady(Config, kind, level) then
			return false
		end
	end
	-- WP5: an unmask step needs a costume whose suit is on
	for _, row in t.steps do
		if row.dress and #IncidentPlan.dresses(Config, row, level) == 0 then
			return false
		end
	end
	return true
end

-- The level a template needs (its requires' unlock levels and minLevel)
function IncidentPlan.levelFor(cfg: any, Config: any, tid: string): number
	local t = cfg.templates[tid]
	local lvl = t.minLevel or 1
	for _, kind in t.requires or {} do
		lvl = math.max(lvl, IncidentPlan.unlockLevel(Config, kind))
	end
	return lvl
end

-- One { kind, min, max, fallback... } row at a level: itself, its fallback, or nil (dropped). Without
-- Config, as written.
function IncidentPlan.resolveRow(Config: any?, row: any, level: number): { any }?
	if not Config or IncidentPlan.kindReady(Config, row[1], level) then
		return row
	end
	-- the fallback: { kind, min, max, fallbackKind, fallbackMin, fallbackMax }
	local fb = row[4]
	if fb and IncidentPlan.kindReady(Config, fb, level) then
		return { fb, row[5] or row[2], row[6] or row[3] }
	end
	return nil
end

-- A robot type for a one-robot slot (the convoy, the leader): itself, the fallback, or nil
function IncidentPlan.resolveKind(Config: any?, kind: string, fallback: string?, level: number): string?
	if not Config or IncidentPlan.kindReady(Config, kind, level) then
		return kind
	end
	if fallback and IncidentPlan.kindReady(Config, fallback, level) then
		return fallback
	end
	return nil
end

-- Templates this hero could get. valid: where-kinds that exist near the hero ({ street = true, ... }).
-- With Config and level, templates whose robots are off or not unlocked yet are left out.
function IncidentPlan.choices(
	cfg: any,
	side: string,
	valid: { [string]: boolean },
	prep: boolean,
	Config: any?,
	level: number?
): { string }
	local out = {}
	for _, tid in cfg.order do
		local t = cfg.templates[tid]
		local sideOk = t.side == "both" or t.side == side
		local whereOk = t.where == "any" or valid[t.where] == true
		local prepOk = (t.prep == true) == false or prep
		local readyOk = not Config or IncidentPlan.available(cfg, Config, tid, level or 1)
		if sideOk and whereOk and prepOk and readyOk then
			table.insert(out, tid)
		end
	end
	return out
end

-- rng: anything with :range(lo, hi) (Rng)
function IncidentPlan.pick(
	cfg: any,
	rng: any,
	side: string,
	valid: { [string]: boolean },
	last: string?,
	night: boolean,
	prep: boolean,
	nightBoost: number?,
	Config: any?,
	level: number?
): string?
	local list = IncidentPlan.choices(cfg, side, valid, prep, Config, level)
	if prep then
		for _, tid in list do
			if cfg.templates[tid].prep and tid ~= last then
				return tid
			end
		end
	end
	if #list > 1 and last then
		local i = table.find(list, last)
		if i then
			table.remove(list, i)
		end
	end
	if #list == 0 then
		return nil
	end
	local weights, total = {}, 0
	for i, tid in list do
		local t = cfg.templates[tid]
		local w = if t.prep then 0.5 else 1
		if night and t.side == "villain" then
			w *= nightBoost or 1.3
		end
		weights[i] = w
		total += w
	end
	local r = rng:range(0, total)
	for i, tid in list do
		r -= weights[i]
		if r <= 0 then
			return tid
		end
	end
	return list[#list]
end

-- Is this a step whose goal is robots (Config.Incidents.kinds[kind].squad)?
function IncidentPlan.isSquad(cfg: any, kind: string): boolean
	local k = cfg.kinds and cfg.kinds[kind]
	return k ~= nil and k.squad == true
end

-- Can this template roll Heroic? Only when something in it gets tougher: a squad or an object
function IncidentPlan.canHeroic(cfg: any, tid: string): boolean
	for _, row in cfg.templates[tid].steps do
		if IncidentPlan.isSquad(cfg, row.kind) or row.kind == "object" then
			return true
		end
	end
	return false
end

local function rollRows(Config: any?, rng: any, rows: { any }, level: number): { { kind: string, n: number } }
	local out = {}
	for _, e in rows do
		local r = IncidentPlan.resolveRow(Config, e, level)
		if r then
			local n = rng:int(r[2], r[3])
			if n > 0 then
				table.insert(out, { kind = r[1], n = n })
			end
		end
	end
	return out
end

local function total(rows: { { kind: string, n: number } }): number
	local n = 0
	for _, r in rows do
		n += r.n
	end
	return n
end

-- opts: Config (robot switches, unlock levels and Heroic need it), heroic, and side (the incident's side:
-- rows for the other side are left out; nil keeps every row)
function IncidentPlan.new(
	cfg: any,
	rng: any,
	tid: string,
	level: number,
	now: number,
	opts: { config: any?, heroic: boolean?, side: string? }?
): Incident
	local t = cfg.templates[tid]
	assert(t, "unknown incident " .. tid)
	local Config = opts and opts.config
	local heroic = (opts and opts.heroic) == true and Config ~= nil
	local steps: { Step } = {}
	for _, row in IncidentPlan.rows(t, opts and opts.side) do
		local step: Step = { kind = row.kind, need = 1, have = 0, spawn = nil, def = row }
		local k = row.kind
		if k == "defeat" or k == "nest" or k == "find" or k == "tug" then
			local spawn = rollRows(Config, rng, row.enemies, level)
			if heroic then
				spawn = HeroicRules.squad(Config, spawn, true)
			end
			step.spawn = spawn
			step.need = math.max(1, total(spawn))
		elseif k == "leader" then
			step.leader = IncidentPlan.resolveKind(Config, row.leader, row.fallback, level) or "BruteBot"
			local escort = rollRows(Config, rng, row.enemies, level)
			if heroic then
				escort = HeroicRules.squad(Config, escort, true)
			end
			step.spawn = escort
			step.need = 1
		elseif k == "convoy" then
			local kind = IncidentPlan.resolveKind(Config, row.enemy, row.fallback or "SparkDrone", level)
				or "SparkDrone"
			local n = row.n + (if heroic then Config.Heroic.extraUnits else 0)
			step.spawn = { { kind = kind, n = n } }
			step.need = n
		elseif k == "barrage" then
			local spawn = rollRows(Config, rng, row.enemies, level)
			if heroic then
				spawn = HeroicRules.squad(Config, spawn, true)
			end
			step.spawn = spawn
			step.need = row.blocks
			step.missed = 0
		elseif k == "rescue" then
			step.need = row.count
		elseif k == "hold" then
			step.need = row.seconds
		end
		table.insert(steps, step)
	end
	local limit = if heroic then HeroicRules.time(Config, t.time, true) else t.time
	return {
		tid = tid,
		num = t.num,
		level = level,
		heroic = heroic,
		step = 1,
		steps = steps,
		started = now,
		deadline = now + limit,
		done = false,
		failed = false,
	}
end

function IncidentPlan.current(inc: Incident): Step?
	return inc.steps[inc.step]
end

-- Progress on the current step (of `kind`). Returns "step", "done" or nil.
function IncidentPlan.advance(inc: Incident, kind: string, amount: number): string?
	local s = inc.steps[inc.step]
	if inc.done or inc.failed or not s or s.kind ~= kind then
		return nil
	end
	s.have = math.min(s.need, s.have + amount)
	if s.have < s.need - 1e-9 then
		return nil
	end
	inc.step += 1
	if inc.step > #inc.steps then
		inc.done = true
		return "done"
	end
	return "step"
end

-- A barrage shell landed: blocked (a hero stood in its ring) counts toward the goal; a miss counts toward
-- the misses, and one more than the step allows fails the incident. Returns "step", "done", "failed" or nil.
function IncidentPlan.shell(inc: Incident, blocked: boolean): string?
	local s = inc.steps[inc.step]
	if inc.done or inc.failed or not s or s.kind ~= "barrage" then
		return nil
	end
	if blocked then
		return IncidentPlan.advance(inc, "barrage", 1)
	end
	s.missed = (s.missed or 0) + 1
	if (s.missed :: number) > (s.def.misses or 0) then
		inc.failed = true
		return "failed"
	end
	return nil
end

-- Every Bomber is down: the barrage is over (the rest of the goal counts as blocked)
function IncidentPlan.endBarrage(inc: Incident): string?
	local s = inc.steps[inc.step]
	if not s or s.kind ~= "barrage" then
		return nil
	end
	return IncidentPlan.advance(inc, "barrage", s.need - s.have)
end

-- Out of time?
function IncidentPlan.expired(inc: Incident, now: number): boolean
	return not inc.done and now >= inc.deadline
end

-- The share done, over all steps (0 to 1), for the tracker bar
function IncidentPlan.fraction(inc: Incident): number
	if inc.done then
		return 1
	end
	local n = #inc.steps
	local s = inc.steps[inc.step]
	local within = if s and s.need > 0 then s.have / s.need else 0
	return math.clamp(((inc.step - 1) + within) / n, 0, 1)
end

-- "gold" within half the time limit, "silver" within 80%, else "bronze"
function IncidentPlan.medal(cfg: any, inc: Incident, now: number): string
	local limit = inc.deadline - inc.started
	local used = (now - inc.started) / math.max(limit, 1e-6)
	if used <= cfg.medal.gold then
		return "gold"
	elseif used <= cfg.medal.silver then
		return "silver"
	end
	return "bronze"
end

-- Seconds of hold progress per second for n heroes in the circle
function IncidentPlan.holdRate(cfg: any, n: number): number
	if n <= 0 then
		return 0
	end
	local h = cfg.holdRate
	return math.min(h.max, h.first + h.each * (n - 1))
end

-- An object's HP: `hits` hits of the Power a hero of that level has with no gear (30 + 6 x L)
function IncidentPlan.objectHp(Config: any, hits: number, level: number): number
	return math.floor(hits * (Config.Stats.power.base + Config.Stats.power.perLevel * level) + 0.5)
end

-- The banner for a side
function IncidentPlan.title(cfg: any, tid: string, side: string): (string, string)
	local t = cfg.templates[tid]
	if side == "villain" then
		return t.villainName or t.name, t.villainText or t.text
	end
	return t.name, t.text
end

-- The tracker's line for step `i` of a template (fixed text: the step's own, else its kind's); `i` counts
-- the side's own rows (IncidentPlan.rows)
function IncidentPlan.stepText(cfg: any, tid: string, i: number, side: string): string
	local t = cfg.templates[tid]
	local row = t and IncidentPlan.rows(t, side)[i]
	if not row then
		return ""
	end
	if side == "villain" and row.villainText then
		return row.villainText
	end
	return row.text or (cfg.kinds and cfg.kinds[row.kind] and cfg.kinds[row.kind].text) or ""
end

return IncidentPlan
