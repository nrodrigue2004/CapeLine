--!strict
-- EventPlan: the random event scheduler (spec: "One event every 4 to 6 minutes, max 2 at once, never the
-- same type twice in a row, never inside a mission pocket"). Pure: EventService asks it when the next one
-- is due and which one; the events themselves live in EventService.

local EventPlan = {}

export type State = { nextAt: number, last: string?, active: { [string]: number } } -- active: id -> end time

function EventPlan.new(cfg: any, now: number): State
	return { nextAt = now + cfg.scheduler.firstAfter, last = nil, active = {} }
end

function EventPlan.activeCount(state: State): number
	local n = 0
	for _ in state.active do
		n += 1
	end
	return n
end

-- Which event starts now, or nil (not due, two running, or nothing allowed). rng: :range and :int.
function EventPlan.due(cfg: any, state: State, now: number, rng: any): string?
	for id, ends in state.active do
		if now >= ends then
			state.active[id] = nil
		end
	end
	if now < state.nextAt or EventPlan.activeCount(state) >= cfg.scheduler.maxActive then
		return nil
	end
	local pool = {}
	for _, id in cfg.order do
		if id ~= state.last and state.active[id] == nil then
			table.insert(pool, id)
		end
	end
	if #pool == 0 then
		return nil
	end
	local id = pool[rng:int(1, #pool)]
	state.last = id
	state.active[id] = now + cfg.events[id].length
	state.nextAt = now + rng:range(cfg.scheduler.every[1], cfg.scheduler.every[2])
	return id
end

-- An event ended early (cleared): free its slot
function EventPlan.finish(state: State, id: string)
	state.active[id] = nil
end

-- Mission pockets sit high above the city; nothing from the world scheduler goes there
function EventPlan.inPocket(cfg: any, y: number): boolean
	return y >= cfg.scheduler.pocketY
end

return EventPlan
