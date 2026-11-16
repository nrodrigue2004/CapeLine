--!strict
-- CitizenSim: up to 60 server-owned citizens walking the hub's sidewalks as plain data (spec: Destruction
-- "Max 60 server-owned citizens; they run to the nearest shelter before any collapse and are never shown
-- hurt"). Clients draw them from CitizenBuffer packets, like the robots.
-- * The sidewalk graph: a node at each corner of every Downtown and Old Town block, joined along the block
--   sides and across the streets (crosswalks).
-- * Walk: node to a random neighbour, sometimes pausing. Flee: when danger is called near them (a building
--   about to collapse, a collapse, a big impact), they run along the graph to the nearest shelter that is
--   not inside the danger, then hide there for 20 to 40 s and come back out somewhere calm.
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

-- shelters: points { x, z } (safehouses and HQ doors in Downtown and Old Town)
function CitizenSim.new(Config: any, shelters: { { x: number, z: number } }, seed: number): Sim
	local nodes = CitizenSim.graph(Config)
	local list: { Shelter } = {}
	for _, s in shelters do
		local node = nearestNode(nodes, s.x, s.z)
		if (nodes[node].x - s.x) ^ 2 + (nodes[node].z - s.z) ^ 2 < 90 * 90 then
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

-- Breadth-first path along the graph
local function route(sim: Sim, from: number, to: number): { number }
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
		return {}
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
			local best, bestD = nil, math.huge
			for _, s in sim.shelters do
				if (s.x - x) ^ 2 + (s.z - z) ^ 2 >= r * r then
					local dd = (s.x - c.x) ^ 2 + (s.z - c.z) ^ 2
					if dd < bestD then
						best, bestD = s, dd
					end
				end
			end
			c.state = CitizenSim.FLEE
			c.goal = best
			if best then
				c.path = route(sim, c.node, best.node)
			else
				c.path = {}
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
