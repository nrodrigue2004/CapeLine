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

-- Every goal EventService knows how to build (tests check each event uses one)
EventPlan.GOALS =
	{ "shards", "robots", "rescue", "hold", "train", "generators", "object", "objects", "float" }

export type Area = { name: string, x: number, z: number, hx: number, hz: number } -- centre and half sizes

-- Is this district a downtown? Its name says so, or it is marked downtown = true (a second downtown joins
-- the downtown events by name, wherever the city places it)
function EventPlan.isDowntown(name: string, d: any): boolean
	return string.find(string.lower(name), "downtown", 1, true) ~= nil
		or (type(d) == "table" and d.downtown == true)
end

local function districtArea(name: string, d: any): Area
	return {
		name = name,
		x = (d.minX + d.maxX) / 2,
		z = (d.minZ + d.maxZ) / 2,
		hx = (d.maxX - d.minX) / 2,
		hz = (d.maxZ - d.minZ) / 2,
	}
end

-- The areas an event may happen in, from its `where` (by name: districts in Config.City.districts and
-- landmark ids in Config.World.landmarks; "downtown" every downtown district). "hub" and "anchor" are
-- decided by the server (the plaza, a hero), so they give an empty list. Sorted by name, so a seed picks
-- the same area every time.
function EventPlan.areas(Config: any, where: any): { Area }
	local out: { Area } = {}
	local districts = Config.City.districts
	if where == "downtown" then
		local listed = (Config.Events and Config.Events.downtowns) or {}
		for name, d in districts do
			if EventPlan.isDowntown(name, d) or table.find(listed, name) then
				table.insert(out, districtArea(name, d))
			end
		end
	elseif type(where) == "table" then
		local tile = Config.City.tile
		local origin = -Config.City.mapSize / 2
		for _, name in where do
			local d = districts[name]
			if d then
				table.insert(out, districtArea(name, d))
			else
				for _, lm in Config.World.landmarks or {} do
					if lm.id == name then
						local half = lm.size * tile / 2
						table.insert(out, {
							name = name,
							x = origin + lm.tx * tile + half,
							z = origin + lm.tz * tile + half,
							hx = half,
							hz = half,
						})
					end
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a.name < b.name
	end)
	return out
end

-- Where an event starts: a point in one of its areas (a random one; near the middle so a street spot
-- search from it stays inside), or nil when `where` is "hub" / "anchor" or names nothing that exists
function EventPlan.place(Config: any, def: any, rng: any): (number?, number?, string?)
	local list = EventPlan.areas(Config, def.where)
	if #list == 0 then
		return nil, nil, nil
	end
	local a = list[rng:int(1, #list)]
	local x = a.x + rng:range(-0.25, 0.25) * a.hx
	local z = a.z + rng:range(-0.25, 0.25) * a.hz
	return x, z, a.name
end

-- One wave or guard row { kind, n, fallback? } at a level: its robots, the fallback's, or nil. Heroic adds
-- the extra unit (Shared.HeroicRules). ready(kind, level): may this level have this type?
function EventPlan.row(
	Config: any,
	row: { any },
	level: number,
	heroic: boolean?,
	ready: (string, number) -> boolean
): { kind: string, n: number }?
	local kind = row[1]
	if not ready(kind, level) then
		kind = row[3]
		if not kind or not ready(kind, level) then
			return nil
		end
	end
	local n = row[2] + (if heroic then Config.Heroic.extraUnits else 0)
	return { kind = kind, n = n }
end

-- An event's guard rows as a list (old events give one row { kind, n })
function EventPlan.guardRows(def: any): { { any } }
	local g = def.guards
	if not g then
		return {}
	end
	if type(g[1]) == "string" then
		return { g }
	end
	return g
end

return EventPlan
