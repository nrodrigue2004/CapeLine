--!strict
-- IncidentPlan: the rules of incidents as plain data (spec: Incident spawner; Incidents table). The server's
-- IncidentService places the robots, citizens and props; this decides which template, rolls its steps,
-- tracks progress, the medal and the hold speed, so Lune tests every rule.
-- * pick: a template the hero's side can play at a spot kind that exists near them; villain-side templates
--   are 30% likelier at night; never the same template twice in a row for a hero when there is a choice;
--   Raid prep only while a boss counts down (and then it is preferred).
-- * new: an incident with its steps rolled (robot counts) and a deadline.
-- * advance: progress on the current step; returns "step" when a step finishes, "done" after the last.

local IncidentPlan = {}

export type Step = {
	kind: string,
	need: number, -- robots to beat, citizens to carry, seconds to hold, 1 object, 1 runner
	have: number,
	spawn: { { kind: string, n: number } }?, -- defeat: what to spawn
	def: any, -- the template's step row
}

export type Incident = {
	tid: string,
	num: number,
	level: number,
	step: number,
	steps: { Step },
	started: number,
	deadline: number,
	done: boolean,
	failed: boolean,
}

-- Templates this hero could get. valid: where-kinds that exist near the hero ({ street = true, ... }).
function IncidentPlan.choices(cfg: any, side: string, valid: { [string]: boolean }, prep: boolean): { string }
	local out = {}
	for _, tid in cfg.order do
		local t = cfg.templates[tid]
		local sideOk = t.side == "both" or t.side == side
		local whereOk = t.where == "any" or valid[t.where] == true
		local prepOk = (t.prep == true) == false or prep
		if sideOk and whereOk and prepOk then
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
	nightBoost: number?
): string?
	local list = IncidentPlan.choices(cfg, side, valid, prep)
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

function IncidentPlan.new(cfg: any, rng: any, tid: string, level: number, now: number): Incident
	local t = cfg.templates[tid]
	assert(t, "unknown incident " .. tid)
	local steps: { Step } = {}
	for _, row in t.steps do
		local step: Step = { kind = row.kind, need = 1, have = 0, spawn = nil, def = row }
		if row.kind == "defeat" then
			local spawn = {}
			local total = 0
			for _, e in row.enemies do
				local n = rng:int(e[2], e[3])
				table.insert(spawn, { kind = e[1], n = n })
				total += n
			end
			step.spawn = spawn
			step.need = total
		elseif row.kind == "rescue" then
			step.need = row.count
		elseif row.kind == "hold" then
			step.need = row.seconds
		end
		table.insert(steps, step)
	end
	return {
		tid = tid,
		num = t.num,
		level = level,
		step = 1,
		steps = steps,
		started = now,
		deadline = now + t.time,
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

return IncidentPlan
