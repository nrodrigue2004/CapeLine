-- Missions walk (missions lane, 2026-11-20; nate: "Missions are glitched ... I got stuck after I told Lodestar a
-- fake name"). Every Act 1 mission in a pocket (2 to 6) played end to end headless on the real MissionService and
-- StoryService from the built place, for both sides and every option of its own choice (and both sets of earlier
-- picks, so every branch runs). Only the world around them is stubbed: heroes stand where the walker puts them,
-- robots die when it says so, break targets break, the battle form takes hits through BossSim. A choice is
-- answered the way a client does: its ChoicePick goes through the real Remotes schema first (the bug: ids 5 and 6
-- failed it and the mission waited forever). Each run must finish with its result card and send the hero home.
-- Called from tests/run.luau. ONLY="Missions walk" runs just these.

return function(T: any)
	local test, check = T.test, T.check
	local fs = require("@lune/fs")
	local roblox = require("@lune/roblox")
	local luau = require("@lune/luau")
	local placePath = T.place

	-- one fresh copy of the services for each run (their state is module-local)
	-- the place is read once (a fresh copy per walk ran out of memory); each walk gets fresh modules
	local placeGame: any = nil
	local function boot(): any
		if not placeGame then
			placeGame = roblox.deserializePlace(fs.readFile(placePath))
		end
		local game = placeGame
		local RS = game:GetService("ReplicatedStorage")
		local services =
			game:GetService("ServerScriptService"):FindFirstChild("Server"):FindFirstChild("Services")
		local W: any =
			{ clock = 1000, queue = {}, log = {}, handlers = {}, heroes = {}, enemies = {}, nextId = 0 }
		W.errors = {}

		-- time and tasks on the walker's clock
		local function later(at: number, f: any, ...)
			table.insert(W.queue, { at = at, f = f, args = table.pack(...) })
		end
		W.task = {
			spawn = function(f, ...)
				f(...)
			end,
			defer = function(f, ...)
				later(W.clock, f, ...)
			end,
			delay = function(t, f, ...)
				later(W.clock + (t or 0), f, ...)
			end,
			wait = function()
				return 0
			end,
		}
		function W.run(dt: number)
			W.clock += dt
			local due = {}
			for i = #W.queue, 1, -1 do
				if W.queue[i].at <= W.clock then
					table.insert(due, 1, table.remove(W.queue, i))
				end
			end
			for _, q in due do
				local ok, err = pcall(q.f, table.unpack(q.args, 1, q.args.n))
				if not ok then
					table.insert(W.errors, tostring(err))
				end
			end
			if W.beat then
				local ok, err = pcall(W.beat, dt)
				if not ok then
					table.insert(W.errors, tostring(err))
				end
			end
		end

		local function signal()
			local s = { list = {} }
			function s:Connect(f)
				table.insert(self.list, f)
				return { Disconnect = function() end }
			end
			function s:Fire(...)
				for _, f in self.list do
					f(...)
				end
			end
			return s
		end

		-- the world the missions stand in
		local V3, CF = roblox.Vector3, roblox.CFrame
		local stubs: { [string]: any } = {}
		stubs.Net = {
			fire = function(name, player, data)
				table.insert(W.log, { name = name, player = player, data = data })
			end,
			fireAll = function(name, data)
				table.insert(W.log, { name = name, data = data })
			end,
			on = function(name, f)
				W.handlers[name] = f
			end,
			listen = function() end,
		}
		stubs.FrameProf = {
			wrap = function(_, f)
				return f
			end,
		}
		local Hero: any = {
			Leveled = signal(),
			all = function()
				local out = {}
				for _, h in W.heroes do
					table.insert(out, h)
				end
				return out
			end,
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
			rootPart = function(h)
				return { CFrame = CF.new(h.pos), Position = h.pos }
			end,
			damage = function() end,
			inCombat = function()
				return false
			end,
			refresh = function() end,
			sendState = function() end,
			statLevel = function(h)
				return h.level
			end,
		}
		stubs.HeroService = Hero
		local Enemy: any = { Killed = signal() }
		function Enemy.spawnAt(kind, pos, level)
			W.nextId += 1
			local id = W.nextId
			W.enemies[id] = {
				id = id,
				kind = kind,
				alive = true,
				health = 100,
				maxHealth = 100,
				x = pos.X,
				y = pos.Y,
				z = pos.Z,
			}
			return id
		end
		function Enemy.spawnTwin(_, pos, level)
			return Enemy.spawnAt("Twin", pos, level)
		end
		function Enemy.alive(id)
			local e = W.enemies[id]
			return e ~= nil and e.alive
		end
		function Enemy.get(id)
			return W.enemies[id]
		end
		function Enemy.place(id, pos)
			local e = W.enemies[id]
			if e then
				e.x, e.y, e.z = pos.X, pos.Y, pos.Z
			end
		end
		function Enemy.remove(id)
			local e = W.enemies[id]
			if e then
				e.alive = false
			end
		end
		function Enemy.kill(id)
			local e = W.enemies[id]
			if e and e.alive then
				e.alive, e.health = false, 0
				Enemy.Killed:Fire(nil, nil, nil, id)
			end
		end
		Enemy.tune = function() end
		Enemy.usePocket = function() end
		Enemy.setPocketHeight = function() end
		Enemy.target = function() end
		-- (the phasing layer: a run's robots carry its phase, PhaseService)
		function Enemy.setPhase(id, phase)
			local e = W.enemies[id]
			if e then
				e.phase = phase
			end
		end
		function Enemy.phaseOf(id)
			local e = W.enemies[id]
			return e and e.phase
		end
		stubs.EnemyService = Enemy
		stubs.SiteKit = {
			part = function(parent, size)
				local p = roblox.Instance.new("Part")
				p.Size = size
				p.Parent = parent
				return p
			end,
			ring = function()
				return { ring = true }
			end,
			object = function(name, pos, _lift, _radius, hp, build, _onHit, onBroken)
				local m = roblox.Instance.new("Model")
				m.Name = name
				pcall(build, m)
				return { model = m, pos = pos, hp = hp, maxHp = hp, onBroken = onBroken, target = 0 }
			end,
			moveObject = function(h, pos)
				h.pos = pos
			end,
			inPhase = function(thing, phase)
				if type(thing) == "table" then
					thing.phase = phase
				end
				return thing
			end,
			clear = function(things)
				for _, t in things do
					if type(t) == "table" then
						t.cleared = true
					end
				end
				table.clear(things)
			end,
			heroesIn = function(pos, r)
				local out = {}
				for _, h in W.heroes do
					if h.alive and (h.pos - pos).Magnitude <= r then
						table.insert(out, h)
					end
				end
				return out
			end,
		}
		stubs.SiteKit.citizen = function(pos, opts)
			return { state = "stuck", home = pos, onSafe = opts.onSafe, who = opts.who, prompt = true }
		end
		stubs.SiteKit.pad = function(pos)
			return { pos = pos, model = true }
		end
		stubs.SiteKit.carrying = function()
			return false
		end
		stubs.SiteKit.bystander = function()
			return roblox.Instance.new("Model")
		end
		stubs.CityBuilder = {
			part = function(b)
				local p = roblox.Instance.new("Part")
				return p
			end,
		}
		stubs.PocketArt = {
			dress = function()
				return {}
			end,
			tier1 = function() end,
		}
		stubs.SetPieceMeshes = {
			drawn = function()
				return {}
			end,
			hide = function() end,
			add = function() end,
			yaw = function()
				return CF.new()
			end,
		}
		stubs.DataService = {
			Loaded = signal(),
			get = function(p)
				return W.profiles[p]
			end,
			changed = function() end,
			saveSoon = function() end,
		}
		stubs.EconomyService = {
			reward = function()
				return 100, 10
			end,
			addRenown = function() end,
			addCredits = function() end,
		}
		stubs.GearService = {
			grant = function()
				return {}
			end,
			grantPiece = function() end,
			refresh = function() end,
		}
		stubs.SafehouseService = {
			place = function(hero, cf)
				hero.pos = cf.Position
				hero.placed = (hero.placed or 0) + 1
			end,
		}
		stubs.BeaconService = {
			traveling = function()
				return false
			end,
		}
		stubs.BossService = {
			STATE = setmetatable({ idle = 0 }, {
				__index = function()
					return 3
				end,
			}),
			linkTargets = function() end,
			unlinkTargets = function() end,
			strikeHero = function() end,
		}
		stubs.BlockService = { watchBoss = function() end }
		stubs.CinemaService = {
			mark = function() end,
			seen = function()
				return false
			end,
		}
		stubs.Analytics = { event = function() end, step = function() end }
		stubs.IncidentService = { Rescued = signal() }

		local PlayersStub = {
			PlayerRemoving = signal(),
			GetPlayers = function()
				return {}
			end,
		}
		local RunStub = {
			Heartbeat = {
				Connect = function(_, f)
					W.beat = f
					return { Disconnect = function() end }
				end,
			},
			IsStudio = function()
				return false
			end,
		}
		local gameProxy = setmetatable({}, {
			__index = function(_, k)
				if k == "GetService" then
					return function(_, name)
						if name == "Players" then
							return PlayersStub
						elseif name == "RunService" then
							return RunStub
						end
						return game:GetService(name)
					end
				end
				return (game :: any)[k]
			end,
		})

		local cache: { [any]: any } = {}
		local GLOBALS = { "Instance", "CFrame", "Vector3", "Color3", "Enum", "UDim2", "UDim", "Vector2" }
		local fakeOs = {
			clock = function()
				return W.clock
			end,
			time = os.time,
			date = os.date,
		}
		-- keyed by full name: Lune hands out a new userdata for the same Instance on every lookup
		local function load(mod: any): any
			local key = mod:GetFullName()
			if cache[key] ~= nil then
				return cache[key]
			end
			local stub = stubs[mod.Name]
			if stub and (mod.Parent == services or mod.Name == "Net" or mod.Name == "FrameProf") then
				cache[key] = stub
				return stub
			end
			local env: { [string]: any } = {}
			for _, g in GLOBALS do
				env[g] = (roblox :: any)[g]
			end
			-- Lune's Instances have no events: a prompt is a stand-in whose Triggered the walker never needs (it
			-- calls the step's prompt handlers itself, as Triggered would)
			env.Instance = {
				new = function(cls: string)
					if cls == "ProximityPrompt" then
						return {
							Triggered = { Connect = function() end },
							Enabled = true,
						}
					end
					return roblox.Instance.new(cls)
				end,
			}
			env.game = gameProxy
			env.workspace = game:GetService("Workspace")
			env.script = mod
			env.task = W.task
			env.os = fakeOs
			env.warn = function() end
			env.print = function() end
			env.typeof = roblox.typeof or typeof
			env.require = load
			local src = string.gsub(mod.Source, ":WaitForChild%(", ":FindFirstChild(")
			local out = luau.load(src, { debugName = mod:GetFullName(), environment = env })()
			cache[key] = out
			return out
		end
		W.Config = load(RS:FindFirstChild("Config"))
		local shared = RS:FindFirstChild("Shared")
		W.Remotes = load(shared:FindFirstChild("Remotes"))
		W.NetSchema = load(shared:FindFirstChild("NetSchema"))
		W.StoryPlan = load(shared:FindFirstChild("StoryPlan"))
		W.ProfileSchema = load(shared:FindFirstChild("ProfileSchema"))
		W.BossSim = load(shared:FindFirstChild("BossSim"))
		W.Story = load(services:FindFirstChild("StoryService"))
		W.Mission = load(services:FindFirstChild("MissionService"))
		W.Enemy = Enemy
		W.profiles = {}
		W.Story.init()
		W.Mission.init()
		return W
	end

	-- a player as the services see one
	local function newPlayer(W: any, side: string, level: number): any
		local p: any = { Name = "Walker", UserId = 1, Parent = true, attrs = {} }
		function p:SetAttribute(k, v)
			self.attrs[k] = v
		end
		function p:GetAttribute(k)
			return self.attrs[k]
		end
		local profile = W.ProfileSchema.default()
		local c = W.ProfileSchema.active(profile)
		if not c then
			profile.characters = profile.characters or {}
			table.insert(profile.characters, W.ProfileSchema.newCharacter(side))
			profile.active = #profile.characters
			c = W.ProfileSchema.active(profile)
		end
		c.side = side
		W.profiles[p] = profile
		W.heroes[p] = {
			id = 1,
			player = p,
			level = level,
			side = side,
			alive = true,
			loaded = true,
			pos = roblox.Vector3.new(0, 30, 0),
			bonusPoints = 0,
		}
		return p, c.story
	end

	-- answer the open prompt the way a client does: through the real schema, then the server's handler
	local function answer(W: any, player: any, option: number): (boolean, string?)
		local prompt = nil
		for i = #W.log, 1, -1 do
			local e = W.log[i]
			if e.name == "ChoicePrompt" and e.player == player then
				prompt = e.data
				break
			end
		end
		if not prompt or prompt.id < 0 then
			return false, "no prompt"
		end
		local def = W.Remotes.ChoicePick
		local args = { prompt.id, math.min(option, #prompt.labels) }
		local ok, why = W.NetSchema.validate(def.schema, args, #args)
		if not ok then
			return false,
				"ChoicePick refused by its schema (" .. tostring(why) .. ") for choice " .. prompt.id
		end
		W.handlers.ChoicePick(player, args[1], args[2])
		return true, nil
	end

	-- one mission start to finish; returns what happened
	local function walk(num: number, side: string, own: number, earlier: number, leaveAtChoice: boolean?): any
		local W = boot()
		local Config, StoryPlan = W.Config, W.StoryPlan
		local S = Config.Story
		local m = S.missions[num]
		local player, story = newPlayer(W, side, math.max(m.minLevel, 10))
		-- the story so far: every earlier mission cleared, every earlier choice on `earlier`
		story.opening = true
		for k = 1, num - 1 do
			StoryPlan.clear(story, k)
		end
		for _, ch in S.choices do
			if ch.mission < num or (ch.mission == 1 and num > 1) then
				story.choices[ch.num] =
					math.min(earlier, #ch[if side == "villain" then "villain" else "hero"])
			end
		end
		local out = { stuck = nil, steps = {}, texts = {}, errors = W.errors, finished = false }
		local ok, why = W.Mission.enter(player, num)
		if not ok then
			out.stuck = "could not enter: " .. tostring(why)
			return out
		end
		local run = W.Mission.runOf(player)
		local limit = W.clock + m.minutes * 60
		local lastStage, stageAt = 0, W.clock
		local hero = W.heroes[player]
		while W.clock < limit do
			W.run(0.1)
			run = W.Mission.runOf(player)
			if not run then
				break
			end
			if run.done then
				-- the result card shows, then the trip home
				for _ = 1, 120 do
					W.run(0.1)
				end
				break
			end
			if run.stage ~= lastStage then
				lastStage, stageAt = run.stage, W.clock
			end
			for key, t in run.tracks do
				local st = t.st
				if st and not t.done then
					local k = st.kind
					local tag = string.format("%d:%s:%s", run.stage, key, k)
					if not out.steps[tag] then
						out.steps[tag] = true
						table.insert(out.steps, tag)
						local text = StoryPlan.text(st, side)
						table.insert(out.texts, { stage = run.stage, kind = k, text = text })
					end
					local l = run.layout
					local function v3(p, up)
						return roblox.Vector3.new(p[1], p[2] + (up or 0), p[3])
					end
					if k == "hold" then
						-- stand in the first ring not yet held
						for i, p in t.points do
							if t.held[i] < st.seconds then
								hero.pos = v3(p, 2)
								break
							end
						end
					elseif k == "break" then
						for _, h in t.things do
							if type(h) == "table" and h.onBroken and not h.broke then
								h.broke, h.hp = true, 0
								h.onBroken(1)
								break
							end
						end
					elseif k == "defeat" or k == "boss" or k == "twin" or k == "chase" then
						for id in t.enemies do
							W.Enemy.kill(id)
							break
						end
					elseif k == "reach" then
						hero.pos = v3(l.points[st.at], 2)
					elseif k == "fake" then
						local e = t.fakeId and W.Enemy.get(t.fakeId)
						if e then
							e.health = math.max(1, e.health - 10)
						end
					elseif k == "talk" or k == "find" then
						-- walk up and press the prompt (one a tick, like a player going spot to spot)
						for i, e in t.prompts or {} do
							if k == "talk" and t.talkAt then
								break
							end
							if k == "talk" or (t.found and not t.found[i]) then
								hero.pos = v3(e.at, 2)
								e.fn(player)
								break
							end
						end
					elseif k == "carry" then
						for _, c in t.people or {} do
							if c.state == "stuck" then
								if c.who(hero) then
									c.state = "safe"
									c.onSafe(hero, nil)
								end
								break
							end
						end
					elseif k == "choice" then
						if t.asked and leaveAtChoice then
							-- LEAVE with the choice card up (nate was stuck in the Safehouse): the trip home
							W.handlers.MissionLeave(player)
							for _ = 1, 120 do
								W.run(0.1)
							end
							out.left = true
						elseif t.asked then
							local good, err = answer(W, player, own)
							if not good and err ~= "no prompt" then
								out.stuck = err
							end
						end
					elseif k == "warframe" then
						local wf = t.wf
						if wf and not wf.over then
							local sim = wf.sim
							local key = if sim.shield > 0 then sim.cfg.shield.key else "body"
							local d = W.BossSim.damage(sim, key, sim.maxHp * 0.01)
							if d == 0 then
								for i, ob in sim.objectives do
									if ob.alive then
										W.BossSim.damage(sim, "obj" .. i, ob.maxHp)
										break
									end
								end
							end
						end
					end
				end
			end
			if out.stuck or out.left then
				break
			end
			if W.clock - stageAt > 240 then
				out.stuck = "stage " .. run.stage .. " never finished: " .. table.concat(out.steps, ", ")
				break
			end
		end
		for _, e in W.log do
			if e.name == "MissionResult" and e.player == player then
				out.finished = true
				out.result = e.data
			end
		end
		out.home = W.Mission.runOf(player) == nil and player.attrs.Mission == nil and hero.scene == nil
		out.choice = nil
		for _, ch in S.choices do
			if ch.mission == num then
				out.choice = story.choices[ch.num]
			end
		end
		out.time = W.clock
		return out
	end

	test("Missions walk: every mission ends for both sides and every choice", function()
		if not placePath then
			return
		end
		local Config = T.Config
		local S = Config.Story
		local n = 0
		for num, m in S.missions do
			if not m.opening then -- every act's missions (Act 2 since 2026-11-20)
				local own = nil
				for _, ch in S.choices do
					if ch.mission == num then
						own = ch
					end
				end
				for _, side in { "hero", "villain" } do
					local options = if own then #own[side] else 1
					for o = 1, options do
						for earlier = 1, 2 do
							local r = walk(num, side, o, earlier)
							n += 1
							local name =
								string.format("%s %s option %d (earlier picks %d)", m.id, side, o, earlier)
							check(r.stuck == nil, name .. ": " .. tostring(r.stuck))
							check(r.finished, name .. ": the result card comes")
							check(r.home, name .. ": the hero goes home")
							if own then
								check(
									r.choice == o,
									name .. ": the pick is saved (" .. tostring(r.choice) .. ")"
								)
							end
							for _, tx in r.texts do
								-- a scene is a camera beat with its own subtitle lines, not a goal
								check(
									tx.kind == "scene" or tx.text ~= "",
									string.format(
										"%s: stage %d (%s) has a goal line",
										name,
										tx.stage,
										tx.kind
									)
								)
							end
							check(#r.errors == 0, name .. ": no script errors: " .. (r.errors[1] or ""))
						end
					end
				end
			end
		end
		check(n >= 20, "every mission walked (" .. n .. ")")
	end)

	test("Missions walk: LEAVE with the choice card up sends the hero home", function()
		if not placePath then
			return
		end
		for _, side in { "hero", "villain" } do
			local r = walk(2, side, 1, 1, true)
			check(r.left == true, side .. ": the Safehouse reached its choice")
			check(r.home, side .. ": LEAVE sends the hero home from the choice")
			check(#r.errors == 0, side .. ": no script errors: " .. (r.errors[1] or ""))
		end
	end)
end
