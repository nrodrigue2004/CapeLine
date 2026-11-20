-- Phase (missions lane, 2026-11-20; nate: "other players shouldn't be able to interrupt ur story. Just you or you
-- and friends in missions"): private ("phased") mission runs on the real map. Checked here, headless:
--   * Shared.PhaseRules: keys never meet the prologue's, strict both ways, attribute reads
--   * EnemySim: a phased robot ignores an outsider and attacks a member; its shots pass through an outsider; an
--     unphased robot's whole event trace is the same with a phased hero standing beside its hero
--   * EnemyBuffer: the Enemy.Delta packet builder leaves another key's robots out
--   * the real EnemyService (src file, the world around it stubbed): per-player Enemy.Delta and CombatEvents, hero
--     hits, robot and target damage from outside refused, candidatesFor
--   * the real PhaseService: open, join, leave, close, the Player's Phase attribute
-- Lune proves the maths and the server's bookkeeping; what devices show (PhaseClient hiding the pieces) is on the
-- Studio list (Tasks.md 420-439). Called from tests/run.luau. ONLY="Phase" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local luau = require("@lune/luau")
	local roblox = require("@lune/roblox")
	local PhaseRules = require("../src/shared/PhaseRules")
	local EnemySim = require("../src/shared/EnemySim")
	local EnemyBuffer = require("../src/shared/EnemyBuffer")
	local Signal = require("../src/shared/Util/Signal")
	local V3 = roblox.Vector3

	local function flat()
		return 0
	end

	test("Phase: rules keep a phase's key apart from the prologue's and the open world's", function()
		check(PhaseRules.key(nil) == nil and PhaseRules.key(3) == -3, "a phase's key is its id made negative")
		check(
			PhaseRules.phaseOf(-3) == 3 and PhaseRules.phaseOf(5) == nil,
			"a key's phase (a hero id is none)"
		)
		check(PhaseRules.heroKey({ id = 9, scene = "opening" }) == 9, "the prologue keeps the hero's own id")
		check(
			PhaseRules.heroKey({ id = 9, scene = "mission", phase = 4 }) == -4,
			"a run's hero: its phase's key"
		)
		check(PhaseRules.heroKey({ id = 9 }) == nil and PhaseRules.heroKey(nil) == nil, "the open world: nil")
		check(PhaseRules.sees(nil, nil) and PhaseRules.sees(2, 2), "same phase (or none) sees")
		check(not PhaseRules.sees(2, nil) and not PhaseRules.sees(nil, 2), "strict both ways")
		check(not PhaseRules.sees(2, 3), "another run's is hidden")
		check(PhaseRules.read(4) == 4 and PhaseRules.read(nil) == nil, "attribute read")
		check(
			PhaseRules.read(-1) == nil and PhaseRules.read(1.5) == nil and PhaseRules.read("4") == nil,
			"junk is nil"
		)
		-- keys of a phase can never equal a hero id key (hero ids are positive)
		local clash = false
		for p = 1, 200 do
			for id = 1, 200 do
				if PhaseRules.key(p) == id then
					clash = true
				end
			end
		end
		check(not clash, "no phase key equals a prologue key")
	end)

	-- one drone and some heroes; returns the hits and targets per hero id over `secs`
	local function run(
		sim: any,
		heroes: { any },
		secs: number
	): ({ [number]: number }, { [number]: boolean }, { any })
		local hits: { [number]: number } = {}
		local targeted: { [number]: boolean } = {}
		local trace = {}
		for i = 1, secs * 20 do
			EnemySim.step(sim, i / 20, heroes)
			for _, e in sim.enemies do
				if e.target then
					targeted[e.target] = true
				end
			end
			for _, ev in EnemySim.drainEvents(sim) do
				table.insert(trace, ev)
				if ev.k == "hit" then
					hits[ev.hero] = (hits[ev.hero] or 0) + 1
				end
			end
		end
		return hits, targeted, trace
	end

	test("Phase: a phased robot ignores a hero outside its phase and attacks one inside", function()
		local key = PhaseRules.key(7)
		-- only an outsider near: it never targets, chases or hurts them
		local sim = EnemySim.new(Config, { heightAt = flat })
		local e = EnemySim.spawn(sim, "SparkDrone", 1530, 40, 1500, 1) :: any
		e.solo = key
		local outsider = { id = 1, x = 1500, y = 5, z = 1500, alive = true }
		local hits, targeted = run(sim, { outsider }, 15)
		check(not targeted[1], "never targets the outsider")
		check((hits[1] or 0) == 0, "never hurts the outsider")
		check(math.abs(e.x - 1530) < 80, "never chases the outsider far")
		-- a member a little farther than the outsider: it goes for the member and hits them, never the outsider
		local sim2 = EnemySim.new(Config, { heightAt = flat })
		local e2 = EnemySim.spawn(sim2, "SparkDrone", 1530, 40, 1500, 1) :: any
		e2.solo = key
		local near = { id = 1, x = 1515, y = 5, z = 1500, alive = true }
		local member = { id = 2, x = 1490, y = 5, z = 1500, alive = true, solo = key }
		local hits2, targeted2 = run(sim2, { near, member }, 15)
		check(targeted2[2] and not targeted2[1], "targets the member, never the outsider")
		check((hits2[2] or 0) > 0, string.format("hits the member (%d)", hits2[2] or 0))
		check((hits2[1] or 0) == 0, "the outsider standing nearer is never hit (its shots pass through)")
	end)

	test(
		"Phase: an outsider never soaks a phased robot's shots, and an open-world shot passes through a member",
		function()
			local key = PhaseRules.key(3)
			local member = { id = 2, x = 1500, y = 5, z = 1500, alive = true, solo = key }
			local outsider = { id = 1, x = 1500, y = 5, z = 1520, alive = true } -- on the line between
			local got: { [number]: boolean } = {}
			-- a straight shot from the robot to the member, through the outsider
			local sim2 = EnemySim.new(Config, { heightAt = flat })
			local e2 = EnemySim.spawn(sim2, "SparkDrone", 1500, 200, 1540, 1) :: any
			e2.solo = key
			e2.scripted = true -- it stands still; only the shot flies
			sim2.shots = {
				{
					x = 1500,
					y = 6.5,
					z = 1538,
					vx = 0,
					vy = 0,
					vz = -120,
					life = 1,
					damage = 5,
					enemyId = e2.id,
					radius = 1.5,
					solo = key,
				},
			}
			for i = 1, 30 do
				EnemySim.step(sim2, i / 60, { member, outsider })
				for _, ev in EnemySim.drainEvents(sim2) do
					if ev.k == "hit" then
						got[ev.hero] = true
					end
				end
			end
			check(got[2] == true, "the member behind the outsider is hit")
			check(not got[1], "the outsider in the way is not")
			-- an open-world shot through a member reaches the outsider behind
			local sim3 = EnemySim.new(Config, { heightAt = flat })
			local e3 = EnemySim.spawn(sim3, "SparkDrone", 1500, 200, 1540, 1) :: any
			e3.scripted = true
			sim3.shots = {
				{
					x = 1500,
					y = 6.5,
					z = 1538,
					vx = 0,
					vy = 0,
					vz = -120,
					life = 1,
					damage = 5,
					enemyId = e3.id,
					radius = 1.5,
				},
			}
			local m2 = { id = 2, x = 1500, y = 5, z = 1520, alive = true, solo = key }
			local o2 = { id = 1, x = 1500, y = 5, z = 1500, alive = true }
			local got3: { [number]: boolean } = {}
			for i = 1, 30 do
				EnemySim.step(sim3, i / 60, { m2, o2 })
				for _, ev in EnemySim.drainEvents(sim3) do
					if ev.k == "hit" then
						got3[ev.hero] = true
					end
				end
			end
			check(
				got3[1] == true and not got3[2],
				"an open-world shot passes the member and hits the outsider"
			)
			-- an ice wall of another key does not stop the shot
			local sim4 = EnemySim.new(Config, { heightAt = flat })
			local e4 = EnemySim.spawn(sim4, "SparkDrone", 1500, 200, 1540, 1) :: any
			e4.solo = key
			e4.scripted = true
			EnemySim.addBlocker(sim4, 1500, 6.5, 1520, 4, 100, nil) -- an outsider's wall
			sim4.shots = {
				{
					x = 1500,
					y = 6.5,
					z = 1538,
					vx = 0,
					vy = 0,
					vz = -120,
					life = 1,
					damage = 5,
					enemyId = e4.id,
					radius = 1.5,
					solo = key,
				},
			}
			local hit4 = false
			for i = 1, 30 do
				EnemySim.step(
					sim4,
					i / 60,
					{ { id = 2, x = 1500, y = 5, z = 1500, alive = true, solo = key } }
				)
				for _, ev in EnemySim.drainEvents(sim4) do
					if ev.k == "hit" then
						hit4 = true
					end
				end
			end
			check(hit4, "an outsider's wall does not block a run's shot")
		end
	)

	test(
		"Phase: an unphased robot behaves exactly as before (same trace with a phased hero beside its hero)",
		function()
			local function trace(extra: boolean): { any }
				local seed = 11
				local sim = EnemySim.new(Config, {
					heightAt = flat,
					random = function()
						seed = (seed * 1103515245 + 12345) % 2147483648
						return seed / 2147483648
					end,
				})
				EnemySim.spawn(sim, "SparkDrone", 1530, 40, 1500, 1)
				EnemySim.spawn(sim, "BruteBot", 1480, 3, 1510, 1)
				local heroes = { { id = 1, x = 1500, y = 5, z = 1500, alive = true } }
				if extra then
					-- a run's hero standing right beside, in the line of fire
					table.insert(
						heroes,
						{ id = 2, x = 1502, y = 5, z = 1500, alive = true, solo = PhaseRules.key(5) }
					)
				end
				local _, _, tr = run(sim, heroes, 20)
				local out = {}
				for _, ev in tr do
					table.insert(
						out,
						string.format(
							"%s %s %s %.3f %.3f",
							ev.k,
							tostring(ev.e),
							tostring(ev.hero),
							ev.x or 0,
							ev.z or 0
						)
					)
				end
				return out
			end
			local a, b = trace(false), trace(true)
			local same = #a == #b and #a > 0
			for i = 1, math.min(#a, #b) do
				if a[i] ~= b[i] then
					same = false
					break
				end
			end
			check(same, string.format("identical traces (%d and %d events)", #a, #b))
		end
	)

	test("Phase: the Enemy.Delta packet builder leaves another key's robots out", function()
		local key = PhaseRules.key(2)
		local list = {
			{
				id = 1,
				alive = true,
				x = 0,
				y = 5,
				z = 0,
				health = 1,
				maxHealth = 1,
				state = 0,
				typeId = 1,
				yaw = 0,
			},
			{
				id = 2,
				alive = true,
				x = 5,
				y = 5,
				z = 0,
				health = 1,
				maxHealth = 1,
				state = 0,
				typeId = 1,
				yaw = 0,
				solo = key,
			},
			{
				id = 3,
				alive = true,
				x = 9,
				y = 5,
				z = 0,
				health = 1,
				maxHealth = 1,
				state = 0,
				typeId = 1,
				yaw = 0,
				solo = 7,
			},
		}
		local function ids(k: number?): { [number]: boolean }
			local _, _, rows = EnemyBuffer.decode(EnemyBuffer.encodeFor(1, 0, list, 0, 0, 0, 500, 60, k))
			local out = {}
			for _, r in rows do
				out[r.id] = true
			end
			return out
		end
		local open, member, prologue = ids(nil), ids(key), ids(7)
		check(open[1] and not open[2] and not open[3], "the open world gets only open-world robots")
		check(member[2] and not member[1] and not member[3], "a run's player gets only its run's robots")
		check(prologue[3] and not prologue[1] and not prologue[2], "the prologue's hero only its own")
	end)

	---------------------------------------------------------------------------
	-- The real EnemyService and PhaseService from src, the world around them stubbed
	---------------------------------------------------------------------------

	local function loadServer(name: string, stubs: { [string]: any }, W: any): any
		local function node(path: string): any
			local n = {}
			n.__path = path
			n.Name = string.match(path, "[^/]+$")
			function n.WaitForChild(_, child: string)
				return node(path .. "/" .. child)
			end
			n.FindFirstChild = n.WaitForChild
			return n
		end
		local RS = node("rs")
		local services = {
			ReplicatedStorage = RS,
			Players = stubs.Players,
			RunService = stubs.RunService,
			Workspace = stubs.Workspace,
		}
		local gameStub = {
			GetService = function(_, s: string)
				return services[s]
			end,
		}
		local function req(m: any): any
			if type(m) == "table" and m.__stub ~= nil then
				return m.__stub
			end
			local path = m.__path :: string
			if path == "rs/Config" then
				return Config
			end
			local sub = string.match(path, "^rs/Shared/(.+)$")
			if sub == "Net" or sub == "FrameProf" then
				return stubs[sub]
			end
			if sub then
				return (require :: any)("../src/shared/" .. sub)
			end
			error("unknown require " .. path)
		end
		local parent = setmetatable({}, {
			__index = function(_, k)
				return { __stub = stubs[k] or error("no stub for " .. k) }
			end,
		})
		local env: { [string]: any } = {
			game = gameStub,
			script = { Parent = parent, Name = name },
			require = req,
			Vector3 = roblox.Vector3,
			CFrame = roblox.CFrame,
			os = {
				clock = function()
					return W.clock
				end,
				time = os.time,
				date = os.date,
			},
			warn = function() end,
			print = function() end,
			Random = {
				new = function()
					local seed = 5
					return {
						NextNumber = function()
							seed = (seed * 1103515245 + 12345) % 2147483648
							return seed / 2147483648
						end,
					}
				end,
			},
		}
		local src = fs.readFile("src/server/Services/" .. name .. ".luau")
		return luau.load(src, { debugName = name, environment = env })()
	end

	local function world(): any
		local W: any = { clock = 1000, fired = {}, damaged = {}, heroes = {}, players = {} }
		local stubs: any = {}
		stubs.FrameProf = {
			wrap = function(_, f)
				return f
			end,
		}
		stubs.Net = {
			fire = function(name, player, data)
				table.insert(W.fired, { name = name, player = player, data = data })
			end,
			fireAll = function() end,
		}
		stubs.Players = {
			PlayerAdded = Signal.new(),
			PlayerRemoving = Signal.new(),
			GetPlayers = function()
				return W.players
			end,
		}
		stubs.RunService = {
			Heartbeat = {
				Connect = function(_, f)
					W.beat = f
				end,
			},
		}
		stubs.Workspace = {
			GetServerTimeNow = function()
				return W.clock
			end,
		}
		local list = {}
		stubs.HeroService = {
			Removed = Signal.new(),
			get = function(p)
				return W.heroes[p]
			end,
			byId = function(id)
				for _, h in W.heroes do
					if h.id == id then
						return h
					end
				end
				return nil
			end,
			position = function(h)
				return h.pos
			end,
			simHeroes = function()
				table.clear(list)
				for _, h in W.heroes do
					table.insert(list, {
						id = h.id,
						x = h.pos.X,
						y = h.pos.Y,
						z = h.pos.Z,
						alive = true,
						solo = PhaseRules.heroKey(h),
					})
				end
				return list
			end,
			damage = function(h, amount, source)
				table.insert(W.damaged, { hero = h.id, by = source and source.enemy, amount = amount })
				return amount
			end,
			cc = function() end,
		}
		stubs.DataService = {
			get = function()
				return nil
			end,
		}
		stubs.MoveGuard = { grant = function() end }
		stubs.PerfMonitor = { watch = function() end, add = function() end }
		stubs.Analytics = {
			device = function()
				return nil
			end,
		}
		W.stubs = stubs
		W.Enemy = loadServer("EnemyService", stubs, W)
		W.Phase = loadServer("PhaseService", stubs, W)
		return W
	end

	local function newPlayer(W: any, id: number, pos: any): (any, any)
		local root = { Position = pos }
		local p: any = { UserId = id, Name = "P" .. id, attrs = {} }
		p.Character = {
			FindFirstChild = function(_, n)
				return if n == "HumanoidRootPart" then root else nil
			end,
		}
		function p.SetAttribute(self, k, v)
			self.attrs[k] = v
		end
		function p.GetAttribute(self, k)
			return self.attrs[k]
		end
		local hero = { id = id, player = p, pos = pos, alive = true }
		W.heroes[p] = hero
		table.insert(W.players, p)
		return p, hero
	end

	test("Phase: PhaseService opens, joins, leaves and closes, with the Player's Phase attribute", function()
		local W = world()
		local P = W.Phase
		local p1, h1 = newPlayer(W, 101, V3.new(0, 5, 0))
		local _, h2 = newPlayer(W, 102, V3.new(0, 5, 0))
		local a, b = P.open(), P.open()
		check(a ~= b and P.isOpen(a) and P.isOpen(b), "two open phases")
		P.join(a, h1)
		P.join(a, h2)
		check(h1.phase == a and p1:GetAttribute("Phase") == a, "a member carries the phase (hero and Player)")
		check(#P.heroes(a) == 2 and P.has(a, h2), "both are in it")
		P.join(b, h2)
		check(h2.phase == b and #P.heroes(a) == 1, "joining another leaves the first")
		P.leave(h1)
		check(h1.phase == nil and p1:GetAttribute("Phase") == nil, "leaving clears both")
		P.close(b)
		check(h2.phase == nil and not P.isOpen(b), "closing sends everyone back")
		P.join(b, h1)
		check(h1.phase == nil, "a closed phase takes nobody")
	end)

	test(
		"Phase: EnemyService sends, hits and refuses by phase (Enemy.Delta, CombatEvents, damage, targets)",
		function()
			local W = world()
			local E, P = W.Enemy, W.Phase
			E.init(flat)
			local outP, outsider = newPlayer(W, 101, V3.new(1500, 5, 1500))
			local memP, member = newPlayer(W, 102, V3.new(1495, 5, 1500))
			local ph = P.open()
			P.join(ph, member)
			check(E.soloKey(member) == PhaseRules.key(ph) and E.soloKey(outsider) == nil, "hero keys")
			local runBot = E.spawnAt("SparkDrone", V3.new(1525, 40, 1500), 1, -8001) :: number
			E.setPhase(runBot, ph)
			local cityBot = E.spawnAt("SparkDrone", V3.new(1470, 40, 1500), 1, 5) :: number
			check(E.phaseOf(runBot) == ph and E.phaseOf(cityBot) == nil, "phaseOf")
			check(E.reaches(runBot, member) and not E.reaches(runBot, outsider), "reaches: the run's robot")
			check(
				E.reaches(cityBot, outsider) and not E.reaches(cityBot, member),
				"reaches: the city's robot"
			)
			-- 15 s of heartbeats
			for _ = 1, 15 * 30 do
				W.clock += 1 / 30
				W.beat(1 / 30)
			end
			local deltaOut, deltaMem = {}, {}
			local evOut, evMem = {}, {}
			for _, f in W.fired do
				if f.name == "EnemyDelta" then
					local _, _, rows = EnemyBuffer.decode(f.data)
					for _, r in rows do
						(if f.player == outP then deltaOut else deltaMem)[r.id] = true
					end
				elseif f.name == "CombatEvents" then
					for _, row in f.data do
						table.insert(if f.player == outP then evOut else evMem, row)
					end
				end
			end
			check(
				deltaOut[cityBot] and not deltaOut[runBot],
				"the outsider's Enemy.Delta: the city's robot only"
			)
			check(
				deltaMem[runBot] and not deltaMem[cityBot],
				"the member's Enemy.Delta: the run's robot only"
			)
			local leakOut, leakMem, sawRun, sawCity = false, false, false, false
			for _, row in evOut do
				if row[1] ~= E.HERO_HIT and row[1] ~= E.BLOCKED then
					leakOut = leakOut or row[2] == runBot
					sawCity = sawCity or row[2] == cityBot
				elseif row[1] == E.HERO_HIT then
					leakOut = leakOut or row[2] == member.id
				end
			end
			for _, row in evMem do
				if row[1] ~= E.HERO_HIT and row[1] ~= E.BLOCKED then
					leakMem = leakMem or row[2] == cityBot
					sawRun = sawRun or row[2] == runBot
				elseif row[1] == E.HERO_HIT then
					leakMem = leakMem or row[2] == outsider.id
				end
			end
			check(sawCity and not leakOut, "the outsider's CombatEvents: none of the run's")
			check(sawRun and not leakMem, "the member's CombatEvents: none of the city's")
			local hitMember, hitOutsider, cross = 0, 0, false
			for _, d in W.damaged do
				if d.hero == member.id then
					hitMember += 1
					cross = cross or d.by == cityBot
				elseif d.hero == outsider.id then
					hitOutsider += 1
					cross = cross or d.by == runBot
				end
			end
			check(
				hitMember > 0 and hitOutsider > 0,
				string.format("each robot hurt its own hero (%d, %d)", hitMember, hitOutsider)
			)
			check(not cross, "no robot hurt the other side's hero")
			-- damage from outside does nothing
			local _, _, dealt = E.damage(runBot, 5, outsider.id)
			check(dealt == 0, "an outsider's hit on the run's robot deals nothing")
			local _, _, dealt2 = E.damage(runBot, 5, member.id)
			check(dealt2 > 0, "a member's hit lands")
			local _, _, dealt3 = E.damage(cityBot, 5, member.id)
			check(dealt3 == 0, "a member's hit on the city's robot deals nothing")
			-- a phased target refuses outside hits (SiteKit.inPhase sets target.phase on its objects)
			local took = 0
			local tid = E.addTarget({
				x = 1500,
				y = 5,
				z = 1500,
				r = 3,
				phase = ph,
				hit = function(amount)
					took += amount
					return amount, false
				end,
			})
			local _, _, d1 = E.damage(tid, 7, outsider.id)
			check(d1 == 0 and took == 0, "an outsider's hit never reaches the run's target")
			local _, _, d2 = E.damage(tid, 7, member.id)
			check(d2 == 7 and took == 7, "a member's hit does")
			local openTook = 0
			local oid = E.addTarget({
				x = 1500,
				y = 5,
				z = 1500,
				r = 3,
				hit = function(amount)
					openTook += amount
					return amount, false
				end,
			})
			local _, _, d3 = E.damage(oid, 4, member.id)
			local _, _, d4 = E.damage(oid, 4, outsider.id)
			check(
				d3 == 0 and d4 == 4 and openTook == 4,
				"an open-world target: the outsider's hit only, as before"
			)
			-- candidates
			local function has(list: { any }, id: number): boolean
				for _, c in list do
					if c.id == id then
						return true
					end
				end
				return false
			end
			local co, cm = E.candidatesFor(outsider), E.candidatesFor(member)
			check(
				has(co, cityBot) and has(co, oid) and not has(co, runBot) and not has(co, tid),
				"outsider's candidates"
			)
			check(
				has(cm, runBot) and has(cm, tid) and not has(cm, cityBot) and not has(cm, oid),
				"member's candidates"
			)
			-- the run ends: the member is back in the open world and the city's robot sees them again
			P.close(ph)
			check(
				E.soloKey(member) == nil and E.reaches(cityBot, member),
				"after the run: back in the open world"
			)
			local _ = memP
		end
	)
end
