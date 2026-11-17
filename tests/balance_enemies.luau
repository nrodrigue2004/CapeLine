-- Robot balance table (not in the default suite):  lune run tests/balance_enemies.luau
-- One robot of each kind against one hero who stands still (no dodging, no blocking, no gear Vitality) for
-- 40 simulated seconds in EnemySim: the damage it lands a second, and the seconds it takes to bring down a
-- default-class hero of the same level (Formulas.health) at levels 5, 20, 40 and 50. The hero stands where
-- each kind fights: on the ground at 30 studs, at 80 for the Sniper, 25 up in the air for the Interceptor.
-- A Swarmer row is one robot and its pack of 6. Robot damage and hero health both grow with level, so the
-- order of the kinds is the same at every level; the seconds are what changes.
-- Lore step 4: the famous fakes, an evil twin of each fighting style (by a path that takes it) and the world
-- bosses (a hero 30 studs in front of one, 60 s from its first attack) are rows too, so a fake can be seen to
-- sit between the elite robots and the hardest-hitting boss (tests/run.luau "Lore 4" checks it).

local Config = require("../src/config")
local EnemySim = require("../src/shared/EnemySim")
local Formulas = require("../src/shared/Formulas")
local BossSim = require("../src/shared/BossSim")
local Rng = require("../src/shared/Rng")

local LEVELS = { 5, 20, 40, 50 }
local SECONDS = 40

local function dps(kind: string, level: number, pack: boolean?, path: string?): number
	local cfg = Config.Enemies[kind]
	local sim = EnemySim.new(Config, {
		heightAt = function(x: number, _z: number): number
			return if cfg.sea and x > -1000 then -40 else 0
		end,
		water = function(_x: number, y: number, _z: number): boolean
			return cfg.sea == true and y < Config.World.coast.waterY
		end,
	})
	local y0 = if cfg.sea then -30 else (if cfg.ai == "flyer" then 30 else 0)
	local e = if path
		then EnemySim.spawnTwin(sim, path, 0, 30, 0, level) :: any
		else EnemySim.spawn(sim, kind, 0, y0, 0, level) :: any
	if path and e.ai ~= "flyer" then
		e.y = EnemySim.halfHeight(e.cfg)
	end
	if pack then
		EnemySim.company(sim, e, false)
	end
	local dist = if kind == "Sniper" then 80 else 30
	local hy = if cfg.hunter then 28 elseif cfg.sea then -36 else 3
	local hero = { id = 1, x = 0, y = hy, z = -dist, alive = true, lx = 0, lz = 1 }
	local total, t = 0, 0
	while t < SECONDS do
		t += 1 / 30
		EnemySim.step(sim, t, { hero })
		for _, ev in EnemySim.drainEvents(sim) do
			if ev.k == "hit" and ev.hero == 1 then
				total += ev.damage
			end
		end
	end
	return total / SECONDS
end

print(string.format("Robot time-to-kill (s) on a standing default-class hero, %d s each", SECONDS))
local head = string.format("%-22s %7s", "kind", "dps@20")
for _, lv in LEVELS do
	head ..= string.format("  L%-5d", lv)
end
print(head)
local rows = {}
for _, kind in Config.Enemies.order do
	table.insert(rows, { kind = kind, label = Config.Enemies[kind].name })
	if Config.Enemies[kind].pack then
		table.insert(rows, { kind = kind, label = Config.Enemies[kind].name .. " pack", pack = true })
	end
end
local styles = {}
for path, style in Config.Enemies.EvilTwin.twin.paths do
	if not styles[style] or path < styles[style] then
		styles[style] = path
	end
end
for style, path in styles do
	table.insert(rows, { kind = "EvilTwin", label = "Twin " .. style .. " (" .. path .. ")", path = path })
end
for _, r in rows do
	local line = ""
	local d20 = 0
	for _, lv in LEVELS do
		local d = dps(r.kind, lv, r.pack, r.path)
		if lv == 20 then
			d20 = d
		end
		local hp = Formulas.health(Config, lv, 0, Config.Classes.default)
		line ..= if d > 0 then string.format("  %6.1f", hp / d) else "       -"
	end
	print(string.format("%-22s %7.1f%s", r.label, d20, line))
end
local function bossDps(id: string, level: number): number
	local sim = BossSim.new(Config, id, 0, 0, 0, 1e9, level, 0, Rng.new(5))
	BossSim.step(sim, 6, {})
	local hero = { id = 1, x = 0, y = 3, z = -30, alive = true }
	local total, t = 0, 6
	while t < 66 do
		t += 0.1
		BossSim.step(sim, t, { hero })
		for _, ev in BossSim.drain(sim) do
			if ev.k == "strike" then
				for _, h in ev.hits do
					total += h[2]
				end
			end
		end
	end
	return total / 60
end
for id in Config.Boss.bosses do
	local line = ""
	local d20 = 0
	for _, lv in LEVELS do
		local d = bossDps(id, lv)
		if lv == 20 then
			d20 = d
		end
		line ..= string.format("  %6.1f", Formulas.health(Config, lv, 0, Config.Classes.default) / d)
	end
	print(string.format("%-22s %7.1f%s", "Boss " .. id, d20, line))
end
local hpLine = "hero HP"

for _, lv in LEVELS do
	hpLine ..= string.format("  L%d %d", lv, Formulas.health(Config, lv, 0, Config.Classes.default))
end
print(hpLine)
