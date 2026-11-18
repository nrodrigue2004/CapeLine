--!strict
-- CitizenSim: up to 60 server-owned citizens walking the hub's sidewalks as plain data (spec: Destruction
-- "Max 60 server-owned citizens; they run to the nearest shelter before any collapse and are never shown
-- hurt"). Clients draw them from CitizenBuffer packets, like the robots.
-- * The sidewalk graph: a node at each corner of every Downtown and Old Town block, joined along the block
--   sides and across the streets (crosswalks).
-- * Walk: node to a random neighbour, sometimes pausing. Flee: when danger is called near them (a building
--   about to collapse, a collapse, a big impact), they run along the graph to the nearest shelter that is
--   not inside the danger, then hide there for 20 to 40 s and come back out somewhere calm. A citizen with no
--   sidewalk route to any shelter ducks into the nearest doorway (hides at once) instead of cutting
--   straight through the blocks.
-- * blocked (CitizenSim.blocker over the world's parts): corners inside a part (the Clock Tower in Clock
--   Square) and sidewalk links that pass through one are left out of the graph, so nobody walks through it.
-- Nothing in the game can damage a citizen.

local Rng = if script then require(script.Parent.Rng) else (require :: any)("./Rng")

local CitizenSim = {}

CitizenSim.WALK, CitizenSim.PAUSE, CitizenSim.FLEE, CitizenSim.HIDDEN = 0, 1, 2, 3

export type Node = { x: number, y: number, z: number, links: { number } }
export type Shelter = { x: number, y: number, z: number, node: number }
export type Citizen = {
	id: number,
	x: number,
	y: number,
	z: number,
	fx: number,
	fz: number,
	state: number,
	color: number,
	node: number, -- the node it last reached
	path: { number }, -- nodes still to walk (flee) or the next one (walk)
	goal: Shelter?, -- the shelter it runs to
	untilT: number,
}

export type Sim = {
	cfg: any,
	nodes: { Node },
	shelters: { Shelter },
	citizens: { Citizen },
	rng: Rng.Rng,
	now: number,
	dangers: { { x: number, z: number, r: number, untilT: number } },
}

-- Corners of a grid of blocks: origin (minX, minZ), block size, street width, count each way, inset
local function gridNodes(
	nodes: { Node },
	minX: number,
	minZ: number,
	block: number,
	street: number,
	nx: number,
	nz: number,
	inset: number,
	y: number
)
	local pitch = block + street
	local index: { [string]: number } = {}
	local function key(bx: number, bz: number, cx: number, cz: number): string
		return string.format("%d,%d,%d,%d", bx, bz, cx, cz)
	end
	for bx = 1, nx do
		for bz = 1, nz do
			local x0 = minX + street / 2 + (bx - 1) * pitch
			local z0 = minZ + street / 2 + (bz - 1) * pitch
			for cx = 0, 1 do
				for cz = 0, 1 do
					table.insert(nodes, {
						x = x0 + (if cx == 0 then inset else block - inset),
						y = y,
						z = z0 + (if cz == 0 then inset else block - inset),
						links = {},
					})
					index[key(bx, bz, cx, cz)] = #nodes
				end
			end
		end
	end
	local function link(a: number?, b: number?)
		if a and b then
			table.insert(nodes[a].links, b)
			table.insert(nodes[b].links, a)
		end
	end
	for bx = 1, nx do
		for bz = 1, nz do
			-- around the block
			link(index[key(bx, bz, 0, 0)], index[key(bx, bz, 1, 0)])
			link(index[key(bx, bz, 1, 0)], index[key(bx, bz, 1, 1)])
			link(index[key(bx, bz, 1, 1)], index[key(bx, bz, 0, 1)])
			link(index[key(bx, bz, 0, 1)], index[key(bx, bz, 0, 0)])
			-- crosswalks to the next block east and south
			link(index[key(bx, bz, 1, 0)], index[key(bx + 1, bz, 0, 0)])
			link(index[key(bx, bz, 1, 1)], index[key(bx + 1, bz, 0, 1)])
			link(index[key(bx, bz, 0, 1)], index[key(bx, bz + 1, 0, 0)])
			link(index[key(bx, bz, 1, 1)], index[key(bx, bz + 1, 1, 0)])
		end
	end
end

function CitizenSim.graph(Config: any): { Node }
	local city = Config.City
	local nodes: { Node } = {}
	local gy = city.ground.y
	local d = city.districts.Downtown
	local t = city.downtown
	local pitch = t.block + t.street
	gridNodes(
		nodes,
		d.minX,
		d.minZ,
		t.block,
		t.street,
		math.floor((d.maxX - d.minX) / pitch),
		math.floor((d.maxZ - d.minZ) / pitch),
		2.5,
		gy + 0.9
	)
	local o = city.districts.OldTown
	local ot = city.oldTown
	local op = ot.block + ot.street
	gridNodes(
		nodes,
		o.minX,
		o.minZ,
		ot.block,
		ot.street,
		math.floor((o.maxX - o.minX) / op),
		math.floor((o.maxZ - o.minZ) / op),
		2,
		gy + 0.8
	)
	return nodes
end

local function nearestNode(nodes: { Node }, x: number, z: number): number
	local best, bestD = 1, math.huge
	for i, n in nodes do
		local d = (n.x - x) ^ 2 + (n.z - z) ^ 2
		if d < bestD then
			best, bestD = i, d
		end
	end
	return best
end
CitizenSim.nearestNode = nearestNode

-- A test for the world's solid parts at a citizen's height (y0 to y1), for CitizenSim.new: (x, z, r) says
-- whether a body of radius r there would be inside one. Pure: a 32-stud grid over the boxes.
local CELL = 32
function CitizenSim.blocker(world: any, Config: any): (number, number, number) -> boolean
	local gy = Config.City.ground.y
	local y0, y1 = gy + 2.4, gy + 6 -- above a sidewalk, a kerb or a low plaza; below a citizen's head
	local cells: { [number]: { any } } = {}
	for _, b in world.hubBoxes do
		local solid = not b.ghost and b.kind ~= "band" and b.kind ~= "glow" and b.kind ~= "crop"
		if solid and b.cy - b.sy / 2 < y1 and b.cy + b.sy / 2 > y0 then
			local r = math.sqrt(b.sx * b.sx + b.sz * b.sz) / 2 + 2
			for cx = math.floor((b.cx - r) / CELL), math.floor((b.cx + r) / CELL) do
				for cz = math.floor((b.cz - r) / CELL), math.floor((b.cz + r) / CELL) do
					local k = cx * 100000 + cz
					cells[k] = cells[k] or {}
					table.insert(cells[k], b)
				end
			end
		end
	end
	return function(x: number, z: number, r: number): boolean
		local list = cells[math.floor(x / CELL) * 100000 + math.floor(z / CELL)]
		if not list then
			return false
		end
		for _, b in list do
			local a = math.rad(b.ry or 0)
			local dx, dz = x - b.cx, z - b.cz
			local lx = dx * math.cos(a) - dz * math.sin(a)
			local lz = dx * math.sin(a) + dz * math.cos(a)
			if math.abs(lx) < b.sx / 2 + r and math.abs(lz) < b.sz / 2 + r then
				return true
			end
		end
		return false
	end
end

local BODY = 1 -- a citizen's half width (with a little room) for the graph's checks

local function clearLine(blocked: (number, number, number) -> boolean, a: any, b: any): boolean
	local len = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
	local steps = math.max(1, math.ceil(len / 1))
	for s = 0, steps do
		local f = s / steps
		if blocked(a.x + (b.x - a.x) * f, a.z + (b.z - a.z) * f, BODY) then
			return false
		end
	end
	return true
end

-- The graph without the corners inside parts, the links through them and the corners left with no link
local function prune(nodes: { Node }, blocked: (number, number, number) -> boolean): { Node }
	local keep: { [number]: number } = {}
	local out: { Node } = {}
	for i, n in nodes do
		if not blocked(n.x, n.z, BODY) then
			table.insert(out, { x = n.x, y = n.y, z = n.z, links = {} })
			keep[i] = #out
		end
	end
	for i, n in nodes do
		local a = keep[i]
		if a then
			for _, m in n.links do
				local b = keep[m]
				if b and m > i and clearLine(blocked, n, nodes[m]) then
					table.insert(out[a].links, b)
					table.insert(out[b].links, a)
				end
			end
		end
	end
	local final: { Node } = {}
	local again: { [number]: number } = {}
	for i, n in out do
		if #n.links > 0 then
			table.insert(final, n)
			again[i] = #final
		end
	end
	for _, n in final do
		for k, m in n.links do
			n.links[k] = again[m]
		end
	end
	return final
end

-- No corner walks straight in to shelter s (its hut, or another lot, is in the way): the point on a sidewalk
-- link nearest the shelter that does becomes a new node splitting that link (the safehouse's front door)
local function doorNode(nodes: { Node }, blocked: (number, number, number) -> boolean, s: any): number?
	local best: { i: number, j: number, x: number, z: number }? = nil
	local bestD = 90 * 90
	for i, n in nodes do
		for _, j in n.links do
			if j > i then
				local o = nodes[j]
				local ax, az = o.x - n.x, o.z - n.z
				local l2 = ax * ax + az * az
				for k = 0, 20 do
					-- a few points along the link, nearest first matters less than a clear one
					local f = if l2 > 0 then k / 20 else 0
					local px, pz = n.x + ax * f, n.z + az * f
					local d = (px - s.x) ^ 2 + (pz - s.z) ^ 2
					if d < bestD and clearLine(blocked, { x = px, z = pz }, s) then
						best, bestD = { i = i, j = j, x = px, z = pz }, d
					end
				end
			end
		end
	end
	if not best then
		return nil
	end
	local door = best :: { i: number, j: number, x: number, z: number }
	local a, b = nodes[door.i], nodes[door.j]
	table.insert(nodes, { x = door.x, y = a.y, z = door.z, links = { door.i, door.j } })
	local id = #nodes
	a.links[table.find(a.links, door.j) :: number] = id
	b.links[table.find(b.links, door.i) :: number] = id
	return id
end

-- shelters: points { x, z } (safehouses and HQ doors in Downtown and Old Town). blocked (optional): the
-- world's parts (CitizenSim.blocker); without it the whole grid is used (tests of the walking rules).
function CitizenSim.new(
	Config: any,
	shelters: { { x: number, z: number } },
	seed: number,
	blocked: ((number, number, number) -> boolean)?
): Sim
	local nodes = CitizenSim.graph(Config)
	if blocked then
		nodes = prune(nodes, blocked)
	end
	local list: { Shelter } = {}
	for _, s in shelters do
		-- the nearest corner with a clear walk in (a safehouse's own hut stands between some corners and its pad)
		local node, bestD = nil, 90 * 90
		for i, n in nodes do
			local d = (n.x - s.x) ^ 2 + (n.z - s.z) ^ 2
			if d < bestD and (not blocked or clearLine(blocked, n, s)) then
				node, bestD = i, d
			end
		end
		if not node and blocked then
			node = doorNode(nodes, blocked, s)
		end
		if node then
			table.insert(list, { x = s.x, y = nodes[node].y, z = s.z, node = node })
		end
	end
	return {
		cfg = Config.Destruction.citizens,
		nodes = nodes,
		shelters = list,
		citizens = {},
		rng = Rng.new(seed),
		now = 0,
		dangers = {},
	}
end

local function inDanger(sim: Sim, x: number, z: number): boolean
	for _, d in sim.dangers do
		if (d.x - x) ^ 2 + (d.z - z) ^ 2 < d.r * d.r then
			return true
		end
	end
	return false
end

local function spawnAt(sim: Sim, c: Citizen)
	local n: number
	local tries = 0
	repeat
		n = sim.rng:int(1, #sim.nodes)
		tries += 1
	until not inDanger(sim, sim.nodes[n].x, sim.nodes[n].z) or tries > 20
	local node = sim.nodes[n]
	c.x, c.y, c.z = node.x, node.y, node.z
	c.node = n
	c.path = {}
	c.goal = nil
	c.state = CitizenSim.WALK
end

-- Fill up to the cap
function CitizenSim.populate(sim: Sim, count: number?)
	local want = math.min(count or sim.cfg.max, sim.cfg.max)
	while #sim.citizens < want do
		local c: Citizen = {
			id = #sim.citizens + 1,
			x = 0,
			y = 0,
			z = 0,
			fx = 0,
			fz = 1,
			state = 0,
			color = sim.rng:int(1, sim.cfg.colorSets),
			node = 1,
			path = {},
			goal = nil,
			untilT = 0,
		}
		spawnAt(sim, c)
		table.insert(sim.citizens, c)
	end
end

-- Breadth-first path along the graph, or nil when `to` cannot be reached from `from`
local function route(sim: Sim, from: number, to: number): { number }?
	if from == to then
		return {}
	end
	local prev: { [number]: number } = { [from] = 0 }
	local queue = { from }
	local head = 1
	while head <= #queue do
		local n = queue[head]
		head += 1
		if n == to then
			break
		end
		for _, m in sim.nodes[n].links do
			if prev[m] == nil then
				prev[m] = n
				table.insert(queue, m)
			end
		end
	end
	if prev[to] == nil then
		return nil
	end
	local path = {}
	local n = to
	while n ~= from do
		table.insert(path, 1, n)
		n = prev[n]
	end
	return path
end

-- Something dangerous at (x, z): everyone within r runs to the nearest shelter outside the danger
function CitizenSim.danger(sim: Sim, x: number, z: number, r: number, duration: number)
	table.insert(sim.dangers, { x = x, z = z, r = r, untilT = sim.now + duration })
	for _, c in sim.citizens do
		if c.state ~= CitizenSim.HIDDEN and (c.x - x) ^ 2 + (c.z - z) ^ 2 < r * r then
			-- the nearest shelter outside the danger that the sidewalks reach
			local options = {}
			for _, s in sim.shelters do
				if (s.x - x) ^ 2 + (s.z - z) ^ 2 >= r * r then
					table.insert(options, { s = s, d = (s.x - c.x) ^ 2 + (s.z - c.z) ^ 2 })
				end
			end
			table.sort(options, function(a, b)
				return a.d < b.d
			end)
			local best, path = nil, nil
			for _, o in options do
				path = route(sim, c.node, o.s.node)
				if path then
					best = o.s
					break
				end
			end
			if best and path then
				c.state = CitizenSim.FLEE
				c.goal = best
				c.path = path
			else
				-- nowhere to run along the sidewalks: duck into the nearest doorway
				c.state = CitizenSim.HIDDEN
				c.goal = nil
				c.path = {}
				c.untilT = sim.now + sim.rng:range(sim.cfg.hideFor[1], sim.cfg.hideFor[2])
			end
		end
	end
end

local function moveToward(c: Citizen, tx: number, tz: number, speed: number, dt: number): boolean
	local dx, dz = tx - c.x, tz - c.z
	local d = math.sqrt(dx * dx + dz * dz)
	if d < 0.5 then
		return true
	end
	local stepLen = math.min(d, speed * dt)
	c.x += dx / d * stepLen
	c.z += dz / d * stepLen
	c.fx, c.fz = dx / d, dz / d
	return stepLen >= d - 0.01
end

function CitizenSim.step(sim: Sim, dt: number, now: number)
	sim.now = now
	for i = #sim.dangers, 1, -1 do
		if now >= sim.dangers[i].untilT then
			table.remove(sim.dangers, i)
		end
	end
	local cfg = sim.cfg
	local rng = sim.rng
	for _, c in sim.citizens do
		if c.state == CitizenSim.HIDDEN then
			if now >= c.untilT then
				spawnAt(sim, c)
			end
		elseif c.state == CitizenSim.PAUSE then
			if now >= c.untilT then
				c.state = CitizenSim.WALK
			end
		elseif c.state == CitizenSim.FLEE then
			local nextNode = c.path[1]
			if nextNode then
				local n = sim.nodes[nextNode]
				if moveToward(c, n.x, n.z, cfg.run, dt) then
					c.node = nextNode
					table.remove(c.path, 1)
				end
			else
				local g = c.goal
				local tx, tz = if g then g.x else c.x, if g then g.z else c.z
				if not g or moveToward(c, tx, tz, cfg.run, dt) then
					c.state = CitizenSim.HIDDEN
					c.untilT = now + rng:range(cfg.hideFor[1], cfg.hideFor[2])
				end
			end
		else
			-- walk to the next node, sometimes pausing at a corner
			if #c.path == 0 then
				local links = sim.nodes[c.node].links
				if #links > 0 then
					c.path = { links[rng:int(1, #links)] }
				end
			end
			local nextNode = c.path[1]
			if nextNode then
				local n = sim.nodes[nextNode]
				if moveToward(c, n.x, n.z, cfg.walk, dt) then
					c.node = nextNode
					c.y = n.y
					c.path = {}
					if rng:chance(cfg.pauseChance) then
						c.state = CitizenSim.PAUSE
						c.untilT = now + rng:range(cfg.pause[1], cfg.pause[2])
					end
				end
			end
		end
	end
end

function CitizenSim.visible(sim: Sim): number
	local n = 0
	for _, c in sim.citizens do
		if c.state ~= CitizenSim.HIDDEN then
			n += 1
		end
	end
	return n
end

return CitizenSim
