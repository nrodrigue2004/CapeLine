-- Enemies, machines only (spec: Enemies). Health and damage scale with the zone level:
-- HP x (1 + 0.1 x (zone level - 1)); enemy damage = (20 + 4 x level) x coeff. (tune)
-- typeId goes on the wire (3 bits). Only the Spark Drone is built in M1; the rest arrive in M2.
return {
	order = { "SparkDrone", "BurglarBot", "SneakBot", "BruteBot", "Turret", "NullSentinel" },
	scale = { hpPerLevel = 0.1, dmgBase = 20, dmgPerLevel = 4 },
	SparkDrone = {
		typeId = 1,
		name = "Spark Drone",
		hp = 100,
		flies = true,
		speed = 30,
		hover = { min = 14, max = 40 }, -- height above the ground it holds while patrolling
		aggro = 80,
		attackRange = 50,
		orbit = { min = 22, max = 38 }, -- the distance it strafes at while firing
		burst = { shots = 3, gap = 0.18, every = 2.6 },
		coeff = 0.5,
		shotSpeed = 90, -- studs/s, so a flying hero can dodge
		shotRadius = 3.5,
		fleeBelow = 0.2, -- health fraction: backs off for a moment
		fleeTime = 1.5,
		radius = 2.5, -- body size for hits
		built = true,
	},
	BurglarBot = { typeId = 2, name = "Burglar Bot", hp = 150, coeff = 0.8 },
	SneakBot = { typeId = 3, name = "Sneak Bot", hp = 120, coeff = 1.0 },
	BruteBot = { typeId = 4, name = "Brute Bot", hp = 600, coeff = 2.0 },
	Turret = { typeId = 5, name = "Turret", hp = 400, coeff = 0.6 },
	NullSentinel = { typeId = 6, name = "Null Sentinel", hp = 900, coeff = 1.5 },
	caps = {
		perServer = 90,
		attackingOneHero = 6,
		aiTicksPerFrame = 40,
	},
	tickRate = 10, -- World.Tick (spec: Server lifecycle)
	-- M1 stand-in for the incident spawner (M6): keep a few drones near every hero
	nearHero = { count = 3, radius = 150, minDistance = 60, respawn = 8 },
}
