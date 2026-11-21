-- The Test Lab (nate, 2026-11-21: "Need a way for me to test out all the weapons/powers/abolities/mobilies in an
-- easier way. If I go through the creator in dev console it brings me to prologue."): Shared.LabRules, the real
-- DevService's lab commands with the world around them stubbed (each does what it says, and nothing runs outside
-- Studio), the real HeroService's save of the lab (the build from before the lab), and a UiSim walk of the
-- Dev panel's LAB page at phone, tablet and PC sizes. Called from tests/run.luau:
--   require("./testlab_test")({ test = test, check = check, Config = Config, placePath = process.args[1] })
-- ONLY="Test Lab" runs just these.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local LabRules = require("../src/shared/LabRules")
	local AbilityRules = require("../src/shared/AbilityRules")
	local WeaponRules = require("../src/shared/WeaponRules")
	local MoveRanks = require("../src/shared/MoveRanks")
	local Cooldowns = require("../src/shared/Cooldowns")
	local Awakening = require("../src/shared/Awakening")
	local Signal = require("../src/shared/Util/Signal")
	local A = Config.Abilities
	local M = Config.Move
	local cap = Config.Stats.levelCap

	local function src(path: string): string
		return fs.readFile(path)
	end
	local function has(s: string, needle: string): boolean
		return string.find(s, needle, 1, true) ~= nil
	end

	local function newHero(): any
		local ranks, loadout = AbilityRules.starter(Config, "Volt")
		return {
			id = 1,
			level = 3,
			xp = 40,
			side = "hero",
			classId = "Elemental",
			setId = "Volt",
			startSet = "Volt",
			fxStyle = "Comic",
			mobility = "flight",
			mobRanks = { 1, 0, 0, 0, 0 },
			mobMoves = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
			styles = { flight = true },
			loadout = loadout,
			loadouts = { loadout, table.clone(loadout) },
			loadoutIndex = 1,
			ranks = ranks,
			mods = {},
			bonusPoints = 2,
			respecAt = 0,
			cooldowns = Cooldowns.new(),
			recast = {},
			meter = Awakening.new(),
			combo = { at = 0, step = 0 },
			held = "power",
			weapon = 1,
			weaponMastery = 0,
			god = false,
			loaded = true,
			alive = true,
		}
	end

	---------------------------------------------------------------------------
	-- Shared.LabRules
	---------------------------------------------------------------------------
	test(
		"Test Lab: every path loads at the cap with every ability at max rank and a valid loadout",
		function()
			for _, set in A.sets do
				if AbilityRules.pathReady(Config, set) then
					local ranks, loadout = LabRules.pathKit(Config, set, cap)
					local ok, why =
						AbilityRules.validate(Config, { level = cap, startSet = set, ranks = ranks }, loadout)
					check(
						ok,
						set .. ": the lab loadout passes the game's own check (" .. tostring(why) .. ")"
					)
					check(
						#loadout.skills == AbilityRules.skillSlots(Config, cap),
						set .. ": every skill slot filled"
					)
					check(loadout.super == AbilityRules.superOf(Config, set), set .. ": its super slotted")
					for _, id in A.order do
						local row = A.list[id]
						if row.set == set then
							check(ranks[id] == AbilityRules.maxRank(row), set .. ": " .. id .. " at max rank")
						end
					end
				end
			end
		end
	)

	test("Test Lab: TRY puts every ability of every path on key 1 (or the super) inside the rules", function()
		local tried = 0
		for _, set in A.sets do
			if AbilityRules.pathReady(Config, set) then
				local ranks, loadout = LabRules.pathKit(Config, set, cap)
				local hero = { level = cap, startSet = set, ranks = ranks, loadout = loadout }
				local p = LabRules.pathAbilities(Config, set)
				for _, id in p.skills do
					local ok, why, r2, l2 = LabRules.try(Config, hero, id)
					check(
						ok and l2 ~= nil and l2.skills[1] == id,
						set .. ": " .. id .. " on key 1 (" .. tostring(why) .. ")"
					)
					if ok and l2 and r2 then
						hero = { level = cap, startSet = set, ranks = r2, loadout = l2 }
						tried += 1
						check(
							AbilityRules.loadoutPoints(Config, l2.skills) <= A.loadoutCap,
							set .. ": inside the budget"
						)
					end
				end
				local ok, _, _, l3 = LabRules.try(Config, hero, p.super :: string)
				check(ok and l3 ~= nil and l3.super == p.super, set .. ": the super tries")
				check(not (LabRules.try(Config, hero, p.basic :: string)), set .. ": the basic stays on M1")
				-- borrowed: every skill of the archetype's other paths, the borrow limit kept
				for _, other in LabRules.borrowPaths(Config, set) do
					for _, id in LabRules.pathAbilities(Config, other).skills do
						local okB, whyB, rB, lB = LabRules.try(Config, hero, id)
						check(
							okB and lB ~= nil and lB.skills[1] == id,
							set .. ": borrow " .. id .. " (" .. tostring(whyB) .. ")"
						)
						if okB and rB and lB then
							check(
								AbilityRules.borrowed(Config, rB, set) <= A.borrowMax,
								set .. ": borrow limit held"
							)
							hero = { level = cap, startSet = set, ranks = rB, loadout = lB }
							tried += 1
						end
					end
					local otherSuper = AbilityRules.superOf(Config, other)
					check(
						not (LabRules.try(Config, hero, otherSuper :: string)),
						set .. ": no borrowed super"
					)
				end
				-- another archetype's skill is refused (the game's rule)
				for _, s2 in A.sets do
					if AbilityRules.archetypeOf(Config, s2) ~= AbilityRules.archetypeOf(Config, set) then
						local id = LabRules.pathAbilities(Config, s2).skills[1]
						check(
							not (LabRules.try(Config, hero, id)),
							set .. ": " .. id .. " from another archetype refused"
						)
						break
					end
				end
			end
		end
		check(tried >= 17 * 6, "every path's skills tried (" .. tried .. ")")
	end)

	test(
		"Test Lab: a lab weapon is any of the 36 with Z X C V open; cooldowns and stamina switches",
		function()
			local lab = LabRules.new(newHero())
			check(#Config.Weapons.list == 36, "36 weapons")
			for _, row in Config.Weapons.list do
				local id = row[1]
				check(LabRules.weaponOk(Config, id), "weapon " .. id .. " may be carried")
				lab.weapon = id
				check(LabRules.weaponOf(lab, 1) == id, "weapon " .. id .. " in play")
				local kit = WeaponRules.kit(Config, nil, "weapon", id, LabRules.weaponMastery(Config, lab, 0))
				check(kit.weapon and #kit.skills == 4, row[3] .. ": a weapon kit")
				for i = 1, 4 do
					check(not kit.locked[i], row[3] .. ": key " .. Config.Weapons.keys[i] .. " open")
				end
			end
			check(not LabRules.weaponOk(Config, 99), "no weapon 99")
			check(
				LabRules.weaponOf(nil, 7) == 7 and LabRules.weaponMastery(Config, nil, 12) == 12,
				"no lab: as saved"
			)
			check(LabRules.cooldown(Config, nil, "skill", 9) == 9, "no lab: full cooldown")
			lab.noCd = true
			check(LabRules.cooldown(Config, lab, "skill", 9) == Config.Dev.lab.cooldown, "cooldowns off: cut")
			check(LabRules.cooldown(Config, lab, "super", 60) == Config.Dev.lab.cooldown, "supers too")
			check(LabRules.cooldown(Config, lab, "basic", 0.5) == 0.5, "the basic keeps its rate")
			check(not LabRules.freeStamina(lab), "stamina normal by default")
			lab.stamina = true
			check(LabRules.freeStamina(lab) and not LabRules.freeStamina(nil), "endless stamina")
		end
	)

	test("Test Lab: every mobility at every rank, both choice moves switchable", function()
		for _, pick in M.mobilityOrder do
			local max = MoveRanks.max(M, pick)
			check(max == 5, pick .. ": 5 ranks")
			local ranks, moves = LabRules.mobility(M, { 0, 0, 0, 0, 0 }, {}, pick)
			check(MoveRanks.rankOf(M, ranks, pick) == max, pick .. ": at its last rank")
			for _, c in M.choices do
				check(MoveRanks.picked(M, moves, pick, c) == 1, pick .. ": rank " .. c .. " move picked")
				for option = 1, 2 do
					local now = MoveRanks.picked(M, moves, pick, c)
					local ok = MoveRanks.canChoose(M, ranks, moves, pick, c, option, true)
					check(
						ok == (now ~= option),
						pick .. ": rank " .. c .. " option " .. option .. " switchable"
					)
					moves = MoveRanks.withChoice(M, moves, pick, c, option)
					check(
						MoveRanks.active(M, ranks, moves, pick)[MoveRanks.options(M, pick, c)[option]],
						pick .. ": move on"
					)
				end
			end
			for r = 0, max do
				local r2 = LabRules.mobility(M, ranks, moves, pick, r)
				check(MoveRanks.rankOf(M, r2, pick) == r, pick .. ": rank " .. r)
			end
		end
		local rank, option = LabRules.choiceOf(LabRules.choiceValue(5, 2))
		check(rank == 5 and option == 2, "a choice on the wire")
	end)

	test("Test Lab: the build kept aside comes back whole; robots and spots", function()
		local hero = newHero()
		local lab = LabRules.new(hero)
		local ranks, loadout = LabRules.pathKit(Config, "Fire", cap)
		hero.level, hero.ranks, hero.startSet, hero.loadouts = cap, ranks, "Fire", { loadout, loadout }
		hero.mobRanks[1] = 5
		check(
			lab.home.level == 3 and lab.home.startSet == "Volt" and lab.home.mobRanks[1] == 1,
			"home unchanged"
		)
		LabRules.restore(hero, lab.home)
		check(hero.level == 3 and hero.xp == 40 and hero.startSet == "Volt", "level and path back")
		check(hero.ranks.Bolt == nil or hero.ranks.Bolt == lab.home.ranks.Bolt, "ranks back")
		check(hero.loadout == hero.loadouts[1] and hero.loadout.set == "Volt", "the loadout in use back")
		check(hero.mobRanks[1] == 1, "mobility ranks back")
		local robots = LabRules.robots(Config)
		check(#robots >= 20, "most robot kinds listed (" .. #robots .. ")")
		for _, r in robots do
			check(Config.Enemies.order[r.index] == r.kind and r.kind ~= "EvilTwin", r.kind .. ": its index")
		end
		local x, z = LabRules.spot(0, 0, 0, -1, 10, 1, 1, 8)
		check(math.abs(x) < 1e-6 and math.abs(z + 10) < 1e-6, "straight ahead")
		local v = LabRules.view(nil, true)
		check(v.on == false and v.god == true, "no lab: a table that clears the device's copy")
	end)

	---------------------------------------------------------------------------
	-- The real server modules with their world stubbed
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
		local services = {
			ReplicatedStorage = node("rs"),
			Players = {
				PlayerAdded = Signal.new(),
				PlayerRemoving = Signal.new(),
				GetPlayers = function()
					return {}
				end,
			},
			RunService = {
				IsStudio = function()
					return W.studio
				end,
				Heartbeat = Signal.new(),
			},
			Workspace = W.workspace,
		}
		local gameStub = {
			GetService = function(_, s: string)
				return services[s] or error("no service " .. s)
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
			if path == "rs/Shared/Util/Signal" then
				return Signal
			end
			local sub = string.match(path, "^rs/Shared/(.+)$")
			if sub == "Net" then
				return stubs.Net
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
			workspace = W.workspace,
			script = { Parent = parent, Name = name },
			require = req,
			Vector3 = roblox.Vector3,
			CFrame = roblox.CFrame,
			Instance = roblox.Instance,
			warn = function() end,
			print = function() end,
			task = {
				delay = function() end,
				defer = function() end,
				spawn = function(f, ...)
					f(...)
				end,
			},
		}
		return luau.load(
			src("src/server/Services/" .. name .. ".luau"),
			{ debugName = name, environment = env }
		)()
	end

	-- A stub service: the functions given, and any other call recorded in W.calls as "Service.fn"
	local function stub(W: any, sname: string, fns: { [string]: any }?): any
		return setmetatable(fns or {}, {
			__index = function(t, k)
				local f = function(...)
					table.insert(W.calls, { sname .. "." .. k, ... })
					return nil
				end
				rawset(t, k, f)
				return f
			end,
		})
	end
	local function called(W: any, what: string): boolean
		for _, c in W.calls do
			if c[1] == what then
				return true
			end
		end
		return false
	end

	local function world(): any
		local dm = roblox.Instance.new("DataModel")
		local W: any = { studio = true, calls = {}, fired = {}, workspace = dm:GetService("Workspace") }
		W.hero = newHero()
		W.player = { Name = "Tester", UserId = 1 }
		local stubs: any = {}
		stubs.Net = {
			on = function(remote, fn)
				if remote == "DevCommand" then
					W.handler = fn
				end
			end,
			fire = function(remote, _, data)
				table.insert(W.fired, { remote = remote, data = data })
			end,
		}
		local real = loadServer("HeroService", {
			Net = stubs.Net,
			Analytics = stub(W, "Analytics"),
			DataService = stub(W, "DataService"),
		}, W)
		W.HeroService = real
		local root = { Position = roblox.Vector3.new(10, 5, 20), CFrame = roblox.CFrame.new(10, 5, 20) }
		stubs.HeroService = stub(W, "HeroService", {
			get = function()
				return W.hero
			end,
			rootPart = function()
				return root
			end,
			position = function()
				return root.Position
			end,
			setClass = function(h, c)
				h.classId = c
				table.insert(W.calls, { "HeroService.setClass", c })
			end,
			setMobility = function(h, m)
				h.mobility = m
				table.insert(W.calls, { "HeroService.setMobility", m })
			end,
			chooseMove = function(h, rank, option, canSwap)
				h.player = nil -- the real one (its sendState needs no player here)
				return real.chooseMove(h, rank, option, canSwap)
			end,
		})
		local nextTarget = 50000
		W.targets = {}
		stubs.EnemyService = stub(W, "EnemyService", {
			addTarget = function(t)
				nextTarget += 1
				W.targets[nextTarget] = t
				return nextTarget
			end,
			removeTarget = function(id)
				W.targets[id] = nil
			end,
			spawnAt = function(kind, pos, level)
				table.insert(W.calls, { "EnemyService.spawnAt", kind, pos, level })
				return 7
			end,
		})
		stubs.BossService = stub(W, "BossService", {
			startPick = function(i)
				table.insert(W.calls, { "BossService.startPick", i })
				return true
			end,
		})
		stubs.CityBuilder = stub(W, "CityBuilder", {
			heightAt = function()
				return 2
			end,
			world = { landmarks = {} },
		})
		for _, n in
			{
				"LoadBots",
				"DataService",
				"EconomyService",
				"GearService",
				"BuildingService",
				"VehicleService",
				"IncidentService",
				"ContractService",
				"EventService",
				"ClockService",
				"WeatherService",
				"StoryService",
				"OpeningService",
				"MissionService",
				"NemesisService",
				"SideQuestService",
				"FlagService",
				"DeathService",
				"FameService",
				"SafehouseService",
				"CreatorService",
				"HqService",
				"PurchaseService",
				"NewsService",
				"RepService",
				"BoardService",
				"DailyService",
				"PromoService",
				"BalanceService",
				"WeaponService",
			}
		do
			stubs[n] = stub(W, n)
		end
		W.Dev = loadServer("DevService", stubs, W)
		W.Dev.init()
		W.run = function(name: string, value: number?)
			W.handler(W.player, name, value)
		end
		return W
	end

	test("Test Lab: every lab command is refused outside Studio", function()
		local W = world()
		W.studio = false
		local before = W.hero.startSet
		for name in W.Dev.labCommands do
			W.run(name, 1)
		end
		W.run("god", 1)
		check(W.hero.lab == nil and W.hero.startSet == before and not W.hero.god, "nothing changed")
		check(#W.calls == 0 and #W.fired == 0, "no service was called")
		local ds = src("src/server/Services/DevService.luau")
		check(
			has(ds, "if not RunService:IsStudio() then\n\t\t\treturn"),
			"the one gate: DevCommand in Studio only"
		)
		check(
			has(src("src/server/Services/OpeningService.luau"), "if not RunService:IsStudio() or not hero"),
			"skip: Studio only"
		)
		check(
			has(
				src("src/server/Services/CreatorService.luau"),
				"skipFor[player] == true and RunService:IsStudio()"
			),
			"the creator's skip: Studio only"
		)
		check(
			has(src("src/client/Ui/TestLab.luau"), "if not RunService:IsStudio() then"),
			"the page is never built live"
		)
	end)

	test("Test Lab: each lab command does what it says (real DevService, the world stubbed)", function()
		local W = world()
		local hero = W.hero
		-- a weapon: carried, held, every key open (GearService.refresh reads LabRules.weaponOf)
		W.run("labweapon", 21)
		check(
			hero.lab ~= nil and hero.lab.weapon == 21 and hero.held == "weapon",
			"Nunchucks carried and held"
		)
		check(hero.lab.home.level == 3 and hero.lab.home.startSet == "Volt", "the build kept aside")
		check(called(W, "GearService.refresh") and called(W, "WeaponService.showHeld"), "the look rebuilt")
		W.run("labweapon", 99)
		check(
			hero.lab.weapon == 21 and W.fired[#W.fired].data.id == "note",
			"a weapon that is not there: a note"
		)
		-- a path: archetype with it, level cap, every ability at max rank, a valid loadout
		local frost = table.find(Config.Abilities.sets, "Juggernaut") :: number
		W.run("labpath", frost)
		check(hero.startSet == "Juggernaut" and hero.classId == "Powerhouse", "Juggernaut and its archetype")
		check(hero.level == cap and hero.held == "power", "at the cap, the power held")
		check((AbilityRules.validate(Config, hero, hero.loadout)), "the loadout passes the game's check")
		check(hero.loadout == hero.loadouts[1] and #hero.loadout.skills == 4, "four skills slotted")
		-- try: a skill on key 1, a borrowed one, a super
		local p = LabRules.pathAbilities(Config, "Juggernaut")
		local last = p.skills[#p.skills]
		W.run("labtry", A.list[last].num)
		check(hero.loadout.skills[1] == last and hero.loadouts[1] == hero.loadout, "tried skill on key 1")
		local other = LabRules.borrowPaths(Config, "Juggernaut")[1]
		local b = LabRules.pathAbilities(Config, other).skills[3]
		W.run("labtry", A.list[b].num)
		check(hero.loadout.skills[1] == b and hero.ranks[b] == 5, "a borrowed skill tried at max rank")
		W.run("labtry", A.list[LabRules.pathAbilities(Config, "Volt").skills[1]].num)
		check(hero.loadout.skills[1] == b, "another archetype's skill refused")
		W.run("labtry", A.list[p.super].num)
		check(hero.loadout.super == p.super, "the super")
		-- mobility: a pick at its last rank, a rank, both moves
		W.run("labmove", 5)
		check(
			hero.mobility == "swing" and MoveRanks.rankOf(M, hero.mobRanks, "swing") == 5,
			"Swing at rank 5"
		)
		W.run("labrank", 2)
		check(MoveRanks.rankOf(M, hero.mobRanks, "swing") == 2, "Swing at rank 2")
		W.run("labrank", 5)
		W.run("labchoice", LabRules.choiceValue(3, 2))
		check(MoveRanks.picked(M, hero.mobMoves, "swing", 3) == 2, "rank 3's second move")
		W.run("labchoice", LabRules.choiceValue(5, 2))
		check(MoveRanks.picked(M, hero.mobMoves, "swing", 5) == 2, "rank 5's second move (a swap anywhere)")
		-- switches and now buttons
		W.run("labnocd", 1)
		W.run("labstamina", 1)
		check(hero.lab.noCd and hero.lab.stamina, "cooldowns off, endless stamina")
		Cooldowns.start(hero.cooldowns, "X", 0, 60)
		local reset = hero.lab.reset
		W.run("labready")
		check(Cooldowns.ready(hero.cooldowns, "X", 0, 0), "supers ready: cooldowns done")
		check(
			hero.meter.value == Config.Abilities.awakening.max and hero.lab.reset == reset + 1,
			"Awakening full"
		)
		W.run("god", 1)
		check(hero.god, "god mode")
		-- targets: dummies, a robot, a boss
		W.run("labdummy", 0)
		W.run("labdummy", 1)
		local folder = W.workspace:FindFirstChild("TestLab")
		check(folder ~= nil and #folder:GetChildren() == 2, "two dummies in Workspace.TestLab")
		local n = 0
		for id, t in W.targets do
			n += 1
			local dealt = t.hit(120)
			check(dealt == 120, "a dummy takes the hit")
			local anchor = nil
			for _, c in folder:GetChildren() do
				if c:GetAttribute("TargetId") == id then
					anchor = c
				end
			end
			check(
				anchor ~= nil and anchor:GetAttribute("Dealt") == 120 and anchor:GetAttribute("Hits") == 1,
				"its readout"
			)
		end
		check(n == 2, "two targets")
		for _ = 1, Config.Dev.lab.dummies do
			W.run("labdummy", 0)
		end
		check(#folder:GetChildren() == Config.Dev.lab.dummies, "at most the cap")
		W.run("labdummy", 2)
		check(#folder:GetChildren() == 0 and next(W.targets) == nil, "cleared")
		local brute = table.find(Config.Enemies.order, "BruteBot") :: number
		W.run("labrobot", brute)
		local spawned = W.calls[#W.calls]
		check(
			spawned[1] == "EnemyService.spawnAt" and spawned[2] == "BruteBot" and spawned[4] == cap,
			"a Brute Bot at your level"
		)
		W.run("labboss", 2)
		check(called(W, "BossService.startPick"), "a chosen boss lands")
		W.run("labskip", 1)
		local skip = false
		for _, c in W.calls do
			if c[1] == "CreatorService.setSkipPrologue" and c[3] == true then
				skip = true
			end
		end
		check(skip, "skip prologue on")
		-- the save keeps the build from before the lab
		local char = {}
		W.HeroService.writeBack(hero, char)
		check(
			char.level == 3 and char.startSet == "Volt" and char.mobility == "flight",
			"the save: the old build"
		)
		check(
			char.loadouts[1].set == "Volt" and char.mobRanks[1] == 1 and char.xp == 40,
			"its loadout and ranks"
		)
		-- leave: the build back
		W.run("lableave")
		check(
			hero.lab == nil and hero.level == 3 and hero.startSet == "Volt" and hero.mobility == "flight",
			"own build back"
		)
		check(hero.loadout == hero.loadouts[1] and hero.loadout.set == "Volt", "own loadout back")
		local char2 = {}
		W.HeroService.writeBack(hero, char2)
		check(char2.level == 3 and char2.startSet == "Volt", "the save as before")
	end)

	test("Test Lab: the game reads the lab's weapon, cooldowns, stamina and skip", function()
		check(
			has(src("src/server/Services/GearService.luau"), "LabRules.weaponOf(hero.lab,"),
			"GearService: the lab weapon"
		)
		check(
			has(src("src/server/Services/GearService.luau"), "LabRules.weaponMastery(Config, hero.lab"),
			"every key open"
		)
		check(
			has(
				src("src/server/Services/CombatService.luau"),
				"LabRules.cooldown(Config, hero.lab, slot, full)"
			),
			"server cooldowns"
		)
		check(
			has(
				src("src/client/Controllers/CombatClient.luau"),
				"LabRules.cooldown(Config, State.hero.lab, slot, full)"
			),
			"device cooldowns"
		)
		check(
			has(src("src/server/Services/MoveGuard.luau"), "LabRules.freeStamina(hero.lab)"),
			"server stamina"
		)
		check(
			has(src("src/client/Controllers/MoveController.luau"), "LabRules.freeStamina(State.hero.lab)"),
			"device stamina"
		)
		check(has(src("src/server/Services/WeaponService.luau"), "or hero.lab then"), "no Mastery in the lab")
		local cs = src("src/server/Services/CreatorService.luau")
		check(has(cs, "task.defer(OpeningService.skip, player, side)"), "the creator skips the prologue")
		check(
			has(cs, "FlowPlan.introFirst(facts) and not CreatorService.skipsPrologue(player)"),
			"and the exposition"
		)
		check(
			has(src("src/server/Services/HeroService.luau"), "hero.lab = nil -- a wipe"),
			"a wipe ends the lab"
		)
	end)

	---------------------------------------------------------------------------
	-- The LAB page at phone, tablet and PC sizes
	---------------------------------------------------------------------------
	local placePath = T.placePath
	if not placePath then
		return
	end
	test("Test Lab: the LAB page walks at phone, tablet and PC sizes", function()
		local UiSim = require("./uisim")
		local trees = UiSim.load(roblox.deserializePlace(fs.readFile(placePath)))
		local P = Config.Ui.phone
		local DEVICES = {
			{ name = "iPhone SE", w = 667, h = 375, top = 58, left = 0, right = 0, bottom = 0, touch = true },
			{
				name = "Android 640",
				w = 640,
				h = 360,
				top = 58,
				left = 0,
				right = 0,
				bottom = 0,
				touch = true,
			},
			{
				name = "iPhone 14",
				w = 844,
				h = 390,
				top = 58,
				left = 47,
				right = 47,
				bottom = 0,
				touch = true,
			},
			{
				name = "Phone portrait",
				w = 390,
				h = 844,
				top = 58,
				left = 0,
				right = 0,
				bottom = 34,
				touch = true,
			},
			{
				name = "PC 1080p",
				w = 1920,
				h = 1080,
				top = 58,
				left = 0,
				right = 0,
				bottom = 0,
				touch = false,
			},
		}
		for _, d in DEVICES do
			local sim = UiSim.new(trees, d)
			local sent: { { any } } = {}
			sim:run("hook", function()
				local rs = sim.service("RunService")
				rs._props.IsStudio = function()
					return true
				end
				local remotes = sim.service("ReplicatedStorage"):WaitForChild("Remotes")
				for _, r in { "DevCommand", "SkillsMod", "WeaponHold" } do
					remotes:WaitForChild(r)._props.FireServer = function(_, ...)
						table.insert(sent, { r, ... })
					end
				end
			end)
			sim:run("InputController", sim:require("Client.Controllers.InputController").init)
			local State = sim:require("Client.State")
			local ranks, loadout = LabRules.pathKit(Config, "Blade", cap)
			for k, v in
				{
					level = cap,
					classId = "Rogue",
					startSet = "Blade",
					setId = "Blade",
					ranks = ranks,
					mods = {},
					loadout = loadout,
					loadouts = { loadout, loadout },
					mobility = "flight",
					mobRanks = { 5, 0, 0, 0, 0 },
					mobMoves = { 1, 1, 0, 0, 0, 0, 0, 0, 0, 0 },
					held = "power",
					weapon = 1,
					lab = { on = true, weapon = 0, noCd = false, stamina = false, reset = 0, god = false },
				}
			do
				State.hero[k] = v
			end
			local Lab = sim:require("Client.Ui.TestLab")
			check(sim:run("init", Lab.init), d.name .. ": the Test Lab builds")
			local gui = sim.playerGui:FindFirstChild("TestLab")
			check(gui ~= nil, d.name .. ": its screen")
			if not gui then
				continue
			end
			local function find(name: string): any
				for _, c in gui:GetDescendants() do
					if c.Name == name then
						return c
					end
				end
				return nil
			end
			local function last(): { any }
				return sent[#sent] or {}
			end
			local function report(tag: string)
				for _, issue in
					sim:issues({
						minTap = P.minTap,
						minText = P.minText,
						safe = true,
						only = { TestLab = true },
					})
				do
					check(false, d.name .. " " .. tag .. ": " .. issue)
				end
			end
			sim:tap(find("LabToggle"))
			check(find("Panel").Visible, d.name .. ": LAB opens the page")
			for _, t in Lab.TABS do
				sim:tap(find("Tab_" .. t.id))
				check(Lab.tab() == t.id, d.name .. ": the " .. t.text .. " tab")
				report(t.id)
			end
			-- WEAPONS: all 36, a tap carries one
			sim:tap(find("Tab_weapons"))
			for _, row in Config.Weapons.list do
				check(find("Weapon_" .. row[1]) ~= nil, d.name .. ": " .. row[3] .. " listed")
			end
			sim:tap(find("Weapon_33"))
			check(
				last()[1] == "DevCommand" and last()[2] == "labweapon" and last()[3] == 33,
				d.name .. ": War Fan carried"
			)
			sim:tap(find("HoldWeapon"))
			check(last()[1] == "WeaponHold" and last()[2] == 2, d.name .. ": hold the weapon")
			-- POWERS: archetypes, paths, TRY and MOD, borrow
			sim:tap(find("Tab_powers"))
			sim:tap(find("Path_Shadow"))
			check(last()[2] == "labpath" and A.sets[last()[3]] == "Shadow", d.name .. ": load Shadow")
			local p = LabRules.pathAbilities(Config, "Blade")
			for _, id in p.skills do
				check(find("Try_" .. id) ~= nil, d.name .. ": TRY " .. id)
			end
			check(
				find("Try_" .. p.super) ~= nil and find("Try_" .. p.basic) == nil,
				d.name .. ": the super's TRY, no basic's"
			)
			sim:tap(find("Try_" .. p.skills[6]))
			check(last()[2] == "labtry" and last()[3] == A.list[p.skills[6]].num, d.name .. ": TRY sends it")
			local modded = nil
			for _, id in p.skills do
				if A.list[id].mods then
					modded = id
					break
				end
			end
			if modded then
				sim:tap(find("Mod_" .. modded))
				check(
					last()[1] == "SkillsMod" and last()[2] == A.list[modded].num and last()[3] == 1,
					d.name .. ": MOD"
				)
			end
			local other = LabRules.borrowPaths(Config, "Blade")[2]
			sim:tap(find("Borrow_" .. other))
			report("borrow")
			local bs = LabRules.pathAbilities(Config, other).skills[1]
			sim:tap(find("Try_" .. bs))
			check(last()[2] == "labtry" and last()[3] == A.list[bs].num, d.name .. ": a borrowed TRY")
			sim:tap(find("Class_Mystic"))
			check(find("Path_Light") ~= nil and find("Path_Blade") == nil, d.name .. ": the Mystic paths")
			report("mystic")
			-- MOVES
			sim:tap(find("Tab_moves"))
			sim:tap(find("Move_acrobat"))
			check(last()[2] == "labmove" and last()[3] == 4, d.name .. ": Acrobat")
			sim:tap(find("Rank_2"))
			check(last()[2] == "labrank" and last()[3] == 2, d.name .. ": rank 2")
			sim:tap(find("Choice_5_2"))
			check(last()[2] == "labchoice" and last()[3] == 52, d.name .. ": rank 5's second move")
			-- CHEATS
			sim:tap(find("Tab_cheats"))
			for name, cmd in
				{ God = "god", NoCooldowns = "labnocd", Stamina = "labstamina", Ready = "labready" }
			do
				sim:tap(find(name))
				check(last()[2] == cmd, d.name .. ": " .. name)
			end
			-- TARGETS
			sim:tap(find("Tab_targets"))
			sim:tap(find("BigDummy"))
			check(last()[2] == "labdummy" and last()[3] == 1, d.name .. ": a big dummy")
			for _, r in LabRules.robots(Config) do
				check(find("Robot_" .. r.kind) ~= nil, d.name .. ": " .. r.kind)
			end
			sim:tap(find("Robot_Captain"))
			check(
				last()[2] == "labrobot" and Config.Enemies.order[last()[3]] == "Captain",
				d.name .. ": a Captain"
			)
			sim:tap(find("Boss_" .. Config.Boss.order[3]))
			check(last()[2] == "labboss" and last()[3] == 3, d.name .. ": the third boss")
			sim:tap(find("BossSim"))
			check(last()[2] == "hq", d.name .. ": the HQ boss sim")
			-- START: skip prologue, leave
			sim:tap(find("Tab_start"))
			sim:tap(find("Skip"))
			check(last()[2] == "labskip" and last()[3] == 1, d.name .. ": skip prologue on")
			check(find("Skip").Text == "SKIP PROLOGUE: ON", d.name .. ": and it says so")
			sim:tap(find("Leave"))
			check(last()[2] == "lableave", d.name .. ": leave the lab")
			sim:tap(find("Close"))
			check(
				not find("Panel").Visible and find("LabToggle").Visible,
				d.name .. ": X closes it, LAB is back"
			)
			check(#sim.errors == 0, d.name .. ": no errors " .. table.concat(sim.errors, "; "))
		end
	end)
end
