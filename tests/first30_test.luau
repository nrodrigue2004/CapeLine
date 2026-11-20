-- first-30 (2026-11-20, nate: "the first 30 seconds and the first 30 minutes are the most important part of the
-- game"): the first session's polish, proven on the real client code where it can be (UiSim on the built place).
-- Called from tests/run.luau; ONLY="First 30" runs just these.

return function(T: any)
	local test, check, Config, world = T.test, T.check, T.Config, T.world
	local fs = require("@lune/fs")
	local roblox = require("@lune/roblox")
	local NpcAnim = require("../src/shared/NpcAnim")
	local OpeningPlan = require("../src/shared/OpeningPlan")
	local Rng = require("../src/shared/Rng")

	local function newSim()
		local UiSim = require("./uisim")
		return UiSim.new(
			UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		),
			UiSim
	end

	test(
		"First 30: the Ceremony crowd's cheers, the stage's wave and the gasp are whole-body clips",
		function()
			local C = NpcAnim.CLIPS
			for _, e in NpcAnim.crowd.cheer do
				check(C[e[1]] ~= nil and C[e[1]].loop == true, e[1] .. " is a looping clip")
			end
			for _, name in { NpcAnim.crowd.stage, NpcAnim.crowd.crane, NpcAnim.crowd.scan } do
				check(C[name] ~= nil and C[name].loop == true, name .. " is a looping clip")
			end
			-- loops close on themselves (no pop at the wrap) and the cheers move the legs and the hop, not just arms
			for name, clip in C do
				if clip.loop then
					for joint, keys in clip.joints do
						local a, b = keys[1], keys[#keys]
						if #keys > 1 then
							check(
								b[1] == clip.dur
									and a[2] == b[2]
									and a[3] == b[3]
									and a[4] == b[4]
									and a[5] == b[5],
								name .. "'s " .. joint .. " loops cleanly"
							)
						end
					end
				end
			end
			check(
				C.cheer.joints.Root ~= nil and C.cheer.joints.LeftKnee ~= nil,
				"the cheer hops on bent knees"
			)
			local seen = {}
			for i = 0, 29 do
				seen[NpcAnim.pick(NpcAnim.crowd.cheer, (i * 0.37) % 1)] = true
			end
			local kinds = 0
			for _ in seen do
				kinds += 1
			end
			check(kinds == #NpcAnim.crowd.cheer, "a crowd of 30 mixes every cheer (" .. kinds .. ")")
			local fx = fs.readFile("src/client/Fx/PrologueFx.luau")
			check(not string.find(fx, "local function poseCheer", 1, true), "the shoulder-sine cheer is gone")
			check(not string.find(fx, "local function poseWave", 1, true), "the shoulder-sine wave is gone")
		end
	)

	test(
		"First 30: the real PrologueFx poses the crowd from the clips on the ceremony and the scan",
		function()
			if not T.placePath then
				return
			end
			local sim = newSim()
			local route
			for k = 1, 20 do
				route = OpeningPlan.route(Config, world, Rng.new(k * 17))
				if route then
					break
				end
			end
			check(route ~= nil, "a prologue route")
			if not route then
				return
			end
			local StoryClient = sim:require("Client.Controllers.StoryClient")
			local PrologueFx = sim:require("Client.Fx.PrologueFx")
			sim:run("StoryClient", StoryClient.init)
			sim:run("PrologueFx", PrologueFx.init)
			local remotes = sim.service("ReplicatedStorage"):WaitForChild("Remotes")
			local function state(step: string, t: number)
				sim:run("state " .. step, function()
					remotes:WaitForChild("OpeningState").OnClientEvent:Fire({
						step = OpeningPlan.CODE[step],
						t = t,
						side = "hero",
						hall = route.hall,
						face = route.face,
						stage = route.stage,
						crane = route.crane,
						fakes = route.fakes,
						scanner = route.scanner,
						crowd = route.crowd,
						start = route.start,
						spark = route.spark,
						kid = route.kid,
						roofs = route.roofs,
						entrance = route.entrance,
						billboard = route.billboard,
					})
				end)
				-- real time passes (the crowd's crossfade runs on os.clock)
				local stop = os.clock() + NpcAnim.crowd.blend + 0.05
				repeat
					sim:run("frame", function()
						sim.service("RunService").RenderStepped:Fire(1 / 60)
					end)
				until os.clock() >= stop
			end
			local function elbows(): ({ number }, number)
				local out, lifted = {}, 0
				for _, d in sim.workspace:GetDescendants() do
					if d:IsA("Motor6D") and d.Name == "RightElbow" and d.Transform then
						local x = d.Transform:ToEulerAnglesXYZ()
						table.insert(out, math.deg(x))
					elseif
						d:IsA("Motor6D")
						and d.Name == "Root"
						and d.Transform
						and math.abs(d.Transform.Position.Y) > 0.01
					then
						lifted += 1
					end
				end
				return out, lifted
			end
			state("ceremony", 1)
			local e, lifted = elbows()
			check(#e >= 10, "the crowd stands in the plaza (" .. #e .. " elbows)")
			local bent = 0
			for _, a in e do
				if math.abs(a) > 3 then
					bent += 1
				end
			end
			check(bent >= #e * 0.6, "the cheering crowd bends its elbows (" .. bent .. " of " .. #e .. ")")
			check(lifted >= 5, "and hops (" .. lifted .. " roots lifted)")
			state("scan", Config.Story.opening.beats.scan * 0.8)
			e = elbows()
			local gasp = 0
			for _, a in e do
				if math.abs(a) > 60 then
					gasp += 1
				end
			end
			check(
				gasp >= #e * 0.6,
				"on the scan the crowd gasps, hands to the chest (" .. gasp .. " of " .. #e .. ")"
			)
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
		end
	)

	test(
		"First 30: after the prologue the next mission is on the HUD with START (no Journal hunt)",
		function()
			if not T.placePath then
				return
			end
			local UiSim = require("./uisim")
			local ProfileSchema = require("../src/shared/ProfileSchema")
			local StoryPlan = require("../src/shared/StoryPlan")
			local trees = UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath)))
			local P = Config.Ui.phone
			for _, d in
				{
					{
						name = "Android 20:9",
						w = 800,
						h = 360,
						top = 58,
						left = 32,
						right = 32,
						bottom = 0,
						touch = true,
					},
					{
						name = "iPad",
						w = 1024,
						h = 768,
						top = 58,
						left = 0,
						right = 0,
						bottom = 0,
						touch = true,
					},
					{
						name = "iPhone SE",
						w = 667,
						h = 375,
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
			do
				local sim = UiSim.new(trees, d)
				sim:run("InputController", sim:require("Client.Controllers.InputController").init)
				local Hud = sim:require("Client.Ui.Hud")
				sim:run("Hud", Hud.init)
				local StoryClient = sim:require("Client.Controllers.StoryClient")
				local StoryHud = sim:require("Client.Ui.StoryHud")
				sim:run("StoryClient", StoryClient.init)
				sim:run("StoryHud", StoryHud.init)
				local State = sim:require("Client.State")
				local entered = nil
				StoryClient.enter = function(num: number)
					entered = num
				end
				local story = ProfileSchema.newCharacter().story
				StoryPlan.clear(story, 1) -- the prologue is done
				local remotes = sim.service("ReplicatedStorage"):WaitForChild("Remotes")
				local function journal(level: number)
					State.hero.level = level
					sim:run("StoryState", function()
						remotes:WaitForChild("StoryState").OnClientEvent:Fire({
							side = "hero",
							act = 1,
							opening = 1,
							missions = story.missions,
							choices = story.choices,
							pinned = 0,
							perks = 0,
							rep = { 0, 0, 0 },
							states = {},
							sq = {},
						})
					end)
					sim:run("frame", function()
						sim.service("RunService").RenderStepped:Fire(1 / 60)
					end)
				end
				journal(Config.Story.opening.reward.level)
				local panel = sim.playerGui:FindFirstChild("NextMission", true)
				check(
					panel ~= nil and panel.Visible,
					d.name .. ": the next mission's card shows after the prologue"
				)
				if not panel then
					continue
				end
				local start = panel:FindFirstChild("Start", true)
				local texts = {}
				for _, c in panel:GetDescendants() do
					if c:IsA("TextLabel") then
						table.insert(texts, c.Text)
					end
				end
				local all = table.concat(texts, " | ")
				check(
					string.find(all, "MISSION 2: SAFEHOUSE", 1, true) ~= nil,
					d.name .. ": it names Safehouse: " .. all
				)
				check(start ~= nil and start.Visible, d.name .. ": with START")
				for _, issue in
					sim:issues({
						minTap = P.minTap,
						minText = P.minText,
						safe = true,
						only = { StoryHud = true },
					})
				do
					check(false, d.name .. ": " .. issue)
				end
				-- clear of every HUD button
				local mine
				local others = {}
				for _, b in sim:boxes() do
					if b.inst == panel then
						mine = b
					elseif
						(b.inst:IsA("GuiButton") or b.inst.Name == "Status")
						and not b.inst:IsDescendantOf(panel)
					then
						table.insert(others, b)
					end
				end
				check(mine ~= nil, d.name .. ": the card has a box")
				if mine then
					for _, o in others do
						local hit = mine.x < o.x + o.w
							and o.x < mine.x + mine.w
							and mine.y < o.y + o.h
							and o.y < mine.y + mine.h
						check(
							not hit,
							string.format(
								"%s: the card (%d,%d %dx%d) covers %s (%d,%d %dx%d)",
								d.name,
								mine.x,
								mine.y,
								mine.w,
								mine.h,
								o.inst:GetFullName(),
								o.x,
								o.y,
								o.w,
								o.h
							)
						)
					end
				end
				if start then
					sim:tap(start)
				end
				check(entered == 2, d.name .. ": START enters mission 2 (" .. tostring(entered) .. ")")
				-- Safehouse cleared at level 3: Framed needs level 4, so the card says how to get there, no START
				StoryPlan.clear(story, 2)
				journal(3)
				check(
					panel.Visible and start ~= nil and not start.Visible,
					d.name .. ": a mission above the level shows no START"
				)
				local need = if d.touch and d.h < 500
					then string.format(Config.Ui.nextMission.pillLevel, 3, Config.Story.missions[3].minLevel)
					else string.format(Config.Ui.nextMission.level, Config.Story.missions[3].minLevel)
				local seen = false
				for _, c in panel:GetDescendants() do
					if c:IsA("TextLabel") and c.Text == need then
						seen = true
					end
				end
				check(seen, d.name .. ": and the level it needs")
				check(#sim.errors == 0, d.name .. ": no errors: " .. table.concat(sim.errors, " | "))
			end
		end
	)

	test("First 30: level 5's new power slot and move training get Patch's POWERS line", function()
		local GuidePlan = require("../src/shared/GuidePlan")
		check(GuidePlan.powerAt(Config, 5) == "powerBoth", "level 5 opens the third slot and rank 1")
		check(GuidePlan.powerAt(Config, 10) == "powerSlot", "level 10 the fourth slot")
		check(GuidePlan.powerAt(Config, Config.Move.ranks.levels[2]) == "powerRank", "rank 2's level")
		check(GuidePlan.powerAt(Config, 4) == nil, "level 4 opens neither")
		for _, k in { "powerBoth", "powerSlot", "powerRank" } do
			for _, side in { "hero", "villain" } do
				local l = GuidePlan.worldLine(Config, k, side)
				check(
					l ~= nil and string.find(l.text, "POWERS", 1, true) ~= nil,
					k .. " names POWERS for " .. side
				)
			end
		end
		if not T.placePath then
			return
		end
		local sim = newSim()
		local StoryClient = sim:require("Client.Controllers.StoryClient")
		local GuideHud = sim:require("Client.Ui.GuideHud")
		local GuideClient = sim:require("Client.Controllers.GuideClient")
		sim:run("StoryClient", StoryClient.init)
		sim:run("GuideHud", GuideHud.init)
		sim:run("GuideClient", GuideClient.init)
		local State = sim:require("Client.State")
		local story = require("../src/shared/ProfileSchema").newCharacter().story
		require("../src/shared/StoryPlan").clear(story, 1)
		require("../src/shared/StoryPlan").clear(story, 2)
		require("../src/shared/StoryPlan").clear(story, 3)
		StoryClient.journal = { missions = story.missions, choices = story.choices, pinned = 0 }
		State.hero.level = 5
		local function texts(): string
			local out = {}
			for _, c in sim.playerGui:GetDescendants() do
				if (c:IsA("TextLabel") or c:IsA("TextButton")) and c.Text ~= "" then
					table.insert(out, c.Text)
				end
			end
			return table.concat(out, " | ")
		end
		sim:run("level up", function()
			State.Toast:Fire({ id = "levelUp", level = 5 })
		end)
		local function frames(n: number)
			for _ = 1, n do
				sim:run("frame", function()
					sim.service("RunService").RenderStepped:Fire(1 / 30)
					sim.service("RunService").Heartbeat:Fire(1 / 30)
				end)
			end
		end
		frames(3)
		local copy = GuidePlan.worldLine(Config, "unlock", "hero", 4)
		check(
			copy ~= nil and string.find(texts(), copy.text, 1, true) ~= nil,
			"Patch says The Copy is open first"
		)
		local want = GuidePlan.worldLine(Config, "powerBoth", "hero")
		-- inside the radio's gap the POWERS line waits (a second's tick on the Heartbeat)
		sim:run("tick", function()
			sim.service("RunService").Heartbeat:Fire(1.1)
		end)
		check(want ~= nil and GuideClient.radio.once["power5"] == nil, "it waits out the gap")
		-- the gap passes (the rate state's last line moves back past it)
		GuideClient.radio.last -= Config.Story.guides.radio.gap + 1
		sim:run("tick", function()
			sim.service("RunService").Heartbeat:Fire(1.1)
		end)
		check(GuideClient.radio.once["power5"] == true, "then the POWERS line goes out")
		-- the Copy line is still up (it plays its reading time): skip it, and the POWERS line is next
		sim:run("skip", GuideHud.skip)
		local heard = false
		for _ = 1, 30 do
			frames(1)
			heard = want ~= nil and string.find(texts(), want.text, 1, true) ~= nil
			if heard then
				break
			end
			sim:advance(1 / 30)
		end
		check(heard, "then Patch says the POWERS line: " .. texts())
		check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
	end)

	test(
		"First 30: the level-up banner and NEXT LV name what really unlocks (no stale Flight or Frost)",
		function()
			local Progress = require("../src/shared/Progress")
			local u3 = Progress.unlockAt(Config, 3) or ""
			check(string.find(u3, "Safehouse", 1, true) ~= nil, "level 3 opens Safehouse: " .. u3)
			local u5 = Progress.unlockAt(Config, 5) or ""
			check(
				string.find(u5, "Skill slot 3", 1, true) ~= nil
					and string.find(u5, "Move training", 1, true) ~= nil,
				"level 5: the third slot and move training: " .. u5
			)
			check(
				string.find(
					Progress.unlockAt(Config, Config.Contracts.board.minLevel) or "",
					"Contract Board",
					1,
					true
				) ~= nil,
				"the Contract Board's level"
			)
			-- no mobility pick or power path is named: every hero has its pick and its main path from level 1
			local stale = {}
			for _, m in Config.Move.mobility do
				table.insert(stale, m.name)
			end
			for _, set in { "Frost", "Titan", "Pulse", "Blade" } do
				table.insert(stale, set .. " powers")
			end
			for L = 2, Config.Stats.levelCap do
				local u = Progress.unlockAt(Config, L) or ""
				for _, word in stale do
					check(
						string.find(u, word, 1, true) == nil,
						"level " .. L .. " does not claim " .. word .. ": " .. u
					)
				end
			end
		end
	)

	test(
		"First 30: a new mobility move gets a NEW MOVE card with how to do it, and its name on first use",
		function()
			local MoveRanks = require("../src/shared/MoveRanks")
			local MT = Config.Ui.moveTutor
			for id in Config.Move.moves do
				check(Config.Move.moves[id].how ~= nil, id .. " says how to do it")
			end
			check(Config.Ui.popups.cards.moveNew ~= nil, "the card waits in the popup line")
			if not T.placePath then
				return
			end
			local sim = newSim()
			sim:run("InputController", sim:require("Client.Controllers.InputController").init)
			local State = sim:require("Client.State")
			local MoveController = sim:require("Client.Controllers.MoveController")
			local MoveTutor = sim:require("Client.Ui.MoveTutor")
			local pick = "acrobat"
			local pi = table.find(Config.Move.mobilityOrder, pick) :: number
			local ranks = { 0, 0, 0, 0, 0 }
			ranks[pi] = 3
			State.hero.mobility = pick
			State.hero.mobRanks = ranks
			State.hero.mobMoves = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
			sim:run("JuiceFx", sim:require("Client.Fx.JuiceFx").init)
			sim:run("MoveTutor", MoveTutor.init)
			local function frames(n: number)
				for _ = 1, n do
					sim:run("frame", function()
						sim.service("RunService").RenderStepped:Fire(1 / 30)
						sim.service("RunService").Heartbeat:Fire(1 / 30)
					end)
					sim:advance(1 / 30)
					sim:run("popups", function()
						sim:require("Client.Ui.Popups").advance(1 / 30)
					end)
				end
			end
			local function texts(): string
				local out = {}
				for _, c in sim.playerGui:GetDescendants() do
					if (c:IsA("TextLabel") or c:IsA("TextButton")) and c.Text ~= "" and c.Visible then
						local ok = true
						local a = c.Parent
						while a and a:IsA("GuiObject") do
							ok = ok and a.Visible
							a = a.Parent
						end
						if ok then
							table.insert(out, c.Text)
						end
					end
				end
				return table.concat(out, " | ")
			end
			frames(3)
			check(
				sim.playerGui:FindFirstChild("MoveCard", true) == nil,
				"no card for the moves a hero already had"
			)
			-- rank 3's first option picked (Kick Chain)
			local moves = table.clone(State.hero.mobMoves)
			moves[MoveRanks.slotOf(Config.Move, pick, 3) :: number] = 1
			State.hero.mobMoves = moves
			sim:run("sync", function()
				State.Changed:Fire()
			end)
			frames(10)
			local id = MoveRanks.moveOf(Config.Move, ranks, moves, pick, 3) :: string
			local name = string.upper(Config.Move.moves[id].name)
			local all = texts()
			check(string.find(all, MT.tagNew, 1, true) ~= nil, "the NEW MOVE card: " .. all)
			check(string.find(all, name, 1, true) ~= nil, "names " .. name)
			check(string.find(all, MoveTutor.how(id) :: string, 1, true) ~= nil, "and says how: " .. all)
			check(not string.find(all, "{", 1, true), "no {Action} left unturned")
			local P = Config.Ui.phone
			for _, issue in
				sim:issues({
					minTap = P.minTap,
					minText = P.minText,
					safe = true,
					only = { MoveTutor = true },
				})
			do
				check(false, issue)
			end
			-- the card goes (its X); the first use stamps the name, the third does not
			local Popups = sim:require("Client.Ui.Popups")
			sim:run("clear", function()
				Popups.clearAll()
			end)
			frames(3)
			for k = 1, MT.named + 1 do
				sim:run("act", function()
					MoveController.Acted:Fire(id, roblox.Vector3.zero, roblox.Vector3.zero, nil)
				end)
				frames(3)
				if k == 1 then
					check(
						string.find(texts(), name .. "!", 1, true) ~= nil,
						"the first use stamps " .. name .. "!: " .. texts()
					)
				end
			end
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
		end
	)

	test(
		"First 30: a new player can make a hero with NEXT alone and PLAY saves it (no step blocks)",
		function()
			if not T.placePath then
				return
			end
			for _, d in
				{
					{
						name = "iPhone SE",
						w = 667,
						h = 375,
						top = 58,
						left = 0,
						right = 0,
						bottom = 0,
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
			do
				local UiSim = require("./uisim")
				local sim = UiSim.new(UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))), d)
				local sent = nil
				sim:run("hook", function()
					local r =
						sim.service("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("HeroCreate")
					r._props.FireServer = function(_, ...)
						sent = table.pack(...)
					end
				end)
				sim:run("InputController", sim:require("Client.Controllers.InputController").init)
				local Creator = sim:require("Client.Ui.CreatorScreen")
				sim:run("Creator", Creator.init)
				sim:run("open", function()
					Creator.open({ mode = "create" })
				end)
				sim:advance(0.2)
				local gui = sim.playerGui:FindFirstChild("Creator")
				local function button(text: string): any
					for _, c in gui:GetDescendants() do
						if c:IsA("TextButton") and c.Text == text and c.Visible and c.Name ~= "play" then -- not the PLAY tab
							return c
						end
					end
					return nil
				end
				local Kit = sim:require("Client.Ui.Kit")
				local IDS =
					{ body = true, side = true, origin = true, mobility = true, powers = true, weapon = true }
				IDS.appearance, IDS.play = true, true
				local function lit(): string?
					for _, c in gui:GetDescendants() do
						if c:IsA("TextButton") and IDS[c.Name] and c.BackgroundColor3 == Kit.color.gold then
							return c.Name
						end
					end
					return nil
				end
				-- the first choice row in the list that is not picked (a row: a blank button with its name label)
				local function firstRow(): any
					for _, c in gui:GetDescendants() do
						if
							c:IsA("TextButton")
							and c.Text == ""
							and c.Visible
							and c.BackgroundColor3 == Kit.color.paper
							and c:FindFirstChildWhichIsA("TextLabel")
						then
							return c
						end
					end
					return nil
				end
				local taps, asked = 0, {}
				while button("NEXT") and taps < 30 do
					local at = lit()
					sim:tap(button("NEXT"))
					taps += 1
					sim:advance(0.1)
					if lit() == at then
						-- NEXT stayed: this step needs a pick, and says so
						local said = false
						for _, c in gui:GetDescendants() do
							if
								c:IsA("TextLabel")
								and c.Visible
								and string.find(c.Text, "to go on", 1, true)
							then
								said = true
							end
						end
						check(said, d.name .. ": NEXT on " .. tostring(at) .. " stays and says what to pick")
						asked[tostring(at)] = true
						local r = firstRow()
						if r then
							sim:tap(r)
							taps += 1
							sim:advance(0.1)
						end
					end
				end
				check(asked.origin == true, d.name .. ": the ORIGIN step asked for its pick")
				local play = button("PLAY")
				check(play ~= nil, d.name .. ": NEXT leads to PLAY (" .. taps .. " taps)")
				-- NEXT x7, an origin, an archetype and a path, then PLAY: about a dozen taps, well inside 2 minutes
				check(taps <= 14, d.name .. ": in at most 14 taps (" .. taps .. ")")
				if play then
					sim:tap(play)
					sim:advance(0.1)
				end
				local said = {}
				for _, c in gui:GetDescendants() do
					if
						(c:IsA("TextLabel") or c:IsA("TextButton"))
						and c.Visible
						and #c.Text > 3
						and #said < 60
					then
						table.insert(said, c.Text)
					end
				end
				check(
					sent ~= nil,
					d.name
						.. ": PLAY sends the hero with the defaults (no step refused): "
						.. table.concat(said, " | ")
				)
				check(#sim.errors == 0, d.name .. ": no errors: " .. table.concat(sim.errors, " | "))
			end
		end
	)

	test("First 30: Patch says when a side quest chain opens and points at the MAP", function()
		local GuidePlan = require("../src/shared/GuidePlan")
		local SideQuestPlan = require("../src/shared/SideQuestPlan")
		-- the first non-dev chain after Safehouse
		local chain
		for _, c in Config.SideQuests.chains do
			if not c.dev and c.unlock and c.unlock.story == 2 and (not chain or c.bit < chain.bit) then
				chain = c
			end
		end
		check(chain ~= nil, "a chain opens after Safehouse")
		if not chain then
			return
		end
		local b = chain.bit
		-- pure: first read with nothing started names the first open chain; one opening later is named once
		local pick, seen = GuidePlan.newSideQuest({ { bit = b, state = "open" } }, nil)
		check(pick == b, "a new player who never started one hears about it")
		pick = GuidePlan.newSideQuest({ { bit = b, state = "open" }, { bit = 99, state = "done" } }, nil)
		check(pick == nil, "a hero who has done side quests is not told on join")
		pick, seen = GuidePlan.newSideQuest({ { bit = b, state = "locked" } }, nil)
		check(pick == nil, "nothing open, nothing said")
		pick, seen = GuidePlan.newSideQuest({ { bit = b, state = "open" } }, seen)
		check(pick == b, "the chain opening is named")
		pick = GuidePlan.newSideQuest({ { bit = b, state = "open" } }, seen)
		check(pick == nil, "once")
		check(SideQuestPlan.byBit(Config, b) == chain, "found by its bit")
		if not T.placePath then
			return
		end
		-- the real client: GuideClient on two StoryState packets (locked, then open)
		local sim = newSim()
		local StoryClient = sim:require("Client.Controllers.StoryClient")
		local GuideHud = sim:require("Client.Ui.GuideHud")
		local GuideClient = sim:require("Client.Controllers.GuideClient")
		sim:run("StoryClient", StoryClient.init)
		sim:run("GuideHud", GuideHud.init)
		sim:run("GuideClient", GuideClient.init)
		local remotes = sim.service("ReplicatedStorage"):WaitForChild("Remotes")
		local function journal(state: string)
			sim:run("StoryState", function()
				remotes:WaitForChild("StoryState").OnClientEvent:Fire({
					side = "hero",
					missions = 3,
					choices = {},
					pinned = 0,
					sq = { { bit = b, state = state } },
				})
			end)
			sim:run("tick", function()
				sim.service("RunService").Heartbeat:Fire(1.1)
			end)
		end
		journal("locked")
		journal("open")
		check(GuideClient.radio.once["sq" .. b] == true, "Patch said it")
		local heard = false
		for _ = 1, 10 do
			sim:run("frame", function()
				sim.service("RunService").RenderStepped:Fire(1 / 30)
			end)
			for _, c in sim.playerGui:GetDescendants() do
				if
					c:IsA("TextLabel")
					and string.find(c.Text, "side quest", 1, true)
					and string.find(c.Text, "MAP", 1, true)
				then
					heard = true
				end
			end
		end
		check(heard, "the line says a side quest opened (" .. chain.name .. ") and points at the MAP")
		check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
	end)

	test(
		"First 30: a person freed at Framed's ring is a rescue (cheer and chime, SAVED!) and cheers on the clip",
		function()
			if not T.placePath then
				return
			end
			local sim = newSim()
			local AudioController = sim:require("Client.Controllers.AudioController")
			local played = {}
			AudioController.play = function(id: string)
				table.insert(played, id)
			end
			local StoryClient = sim:require("Client.Controllers.StoryClient")
			local StoryFx = sim:require("Client.Fx.StoryFx")
			sim:run("StoryFx", StoryFx.init)
			local function frame()
				sim:run("frame", function()
					sim.service("RunService").RenderStepped:Fire(1 / 30)
				end)
			end
			StoryClient.mission = {
				num = 3,
				step = 2,
				kind = "hold",
				people = true,
				points = { { 0, 20, 0 } },
				held = { 2 },
				seconds = 10,
			}
			frame()
			check(not table.find(played, "rescue"), "no rescue while the ring is held")
			StoryClient.mission.held = { 10 }
			frame()
			check(
				table.find(played, "rescue") ~= nil,
				"the ring done plays the rescue: " .. table.concat(played, ",")
			)
			local stop = os.clock() + 0.3
			repeat
				frame()
			until os.clock() >= stop
			local elbow = nil
			for _, d in sim.workspace:GetDescendants() do
				if d:IsA("Motor6D") and d.Name == "RightKnee" and d.Transform then
					elbow = math.deg((d.Transform:ToEulerAnglesXYZ()))
				end
			end
			check(
				elbow ~= nil and math.abs(elbow) > 2,
				"the freed person cheers with bent knees (" .. tostring(elbow) .. ")"
			)
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
		end
	)

	test(
		"First 30: the intro film's middle never goes quiet: Crane, his heroes, the Vigil and the Syndicate each arrive",
		function()
			local IntroFilm = require("../src/shared/IntroFilm")
			local sp = world.spawns[1]
			local st = IntroFilm.stage(Config, world, sp.x, sp.z) :: any
			local fl = IntroFilm.film(Config, st)
			-- no stretch of the film longer than 6 s without something landing (an event or a sound word)
			local times = {}
			for _, e in fl.events do
				table.insert(times, e.t)
			end
			for _, w in fl.words do
				table.insert(times, w.t)
			end
			table.sort(times)
			local worst, at = 0, 0
			for i = 2, #times do
				if math.min(times[i], 37.5) - times[i - 1] > worst then -- (the quiet before the Spark is the beat)
					worst, at = math.min(times[i], 37.5) - times[i - 1], times[i - 1]
				end
			end
			check(worst <= 6, string.format("the longest quiet stretch is %.1f s from %.1f", worst, at))
			if not T.placePath then
				return
			end
			local sim, UiSim = newSim()
			local AudioController = sim:require("Client.Controllers.AudioController")
			local played = {}
			AudioController.play = function(id: string)
				table.insert(played, id)
			end
			local CinemaClient = sim:require("Client.Controllers.CinemaClient")
			local IntroFilmFx = sim:require("Client.Fx.IntroFilm")
			local now = 0
			CinemaClient.time = function()
				return now
			end
			local terrain
			sim:run("film", function()
				-- (the sim's place has no Terrain; the sound words hang off it)
				terrain = sim.workspace:FindFirstChild("Terrain")
				if not terrain then
					terrain = UiSim.newInstance("Folder")
					terrain.Name = "Terrain"
					terrain.Parent = sim.workspace
				end
				sim.workspace._props.Terrain = terrain
				IntroFilmFx.init()
				local scene = IntroFilmFx.scene(st, { key = "intro" })
				CinemaClient.current = scene
			end)
			check(
				CinemaClient.current ~= nil and CinemaClient.current.follow ~= nil,
				"the film is a follow scene"
			)
			local words = {}
			for t = 19, 33, 0.25 do
				now = t
				sim:run("frame", function()
					sim.service("RunService").RenderStepped:Fire(1 / 4)
				end)
				for _, d in terrain:GetDescendants() do
					if d:IsA("TextLabel") then
						words[d.Text] = true
					end
				end
			end
			local dashes = 0
			for _, id in played do
				if id == "dash" then
					dashes += 1
				end
			end
			check(dashes == 3, "Crane and both sides whoosh (" .. table.concat(played, ",") .. ")")
			check(
				words["THUD!"] and words["FWOOSH!"] and words["SHHRAK!"],
				"the sound words pop in the world ("
					.. table.concat(
						(function()
							local seen = {}
							for w in words do
								table.insert(seen, w)
							end
							return seen
						end)(),
						","
					)
					.. ")"
			)
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
		end
	)

	test(
		"First 30: a robot you take down is the big blow (hit stop, heavy shake, low thud, a gold KO word)",
		function()
			if not T.placePath then
				return
			end
			local sim, UiSim = newSim()
			local cam = sim.service("Workspace").CurrentCamera
			cam.CFrame = roblox.CFrame.new(0, 5, 10)
			local char = UiSim.newInstance("Model")
			local root = UiSim.newInstance("Part")
			root.Name = "HumanoidRootPart"
			root.CFrame = roblox.CFrame.new(0, 3, 0)
			root.Position = roblox.Vector3.new(0, 3, 0)
			root.Parent = char
			char.Parent = sim.workspace
			sim.player.Character = char
			local CombatFx = sim:require("Client.Fx.CombatFx")
			sim:run("CombatFx", CombatFx.init)
			local Combat = sim:require("Client.Controllers.CombatClient")
			sim:run("CombatClient", Combat.init)
			local KoFx = sim:require("Client.Fx.KoFx")
			sim:run("KoFx", KoFx.init)
			local Audio = sim:require("Client.Controllers.AudioController")
			local Camera = sim:require("Client.Controllers.CameraController")
			local Anim = sim:require("Client.Controllers.HeroAnimator")
			local shakes, thuds, stops = {}, 0, 0
			local realShake, realPlay, realFreeze = Camera.shake, Audio.playSpec, Anim.freeze
			Camera.shake = function(t, a)
				table.insert(shakes, a)
				return realShake(t, a)
			end
			Audio.playSpec = function(spec, at, opts, ...)
				if opts and opts.pitch and spec.fallback == Config.Audio.impact.heavy.fallback then
					thuds += 1
				end
				return realPlay(spec, at, opts, ...)
			end
			Anim.freeze = function(sec)
				stops += 1
				return realFreeze(sec)
			end
			local remotes = sim.service("ReplicatedStorage"):WaitForChild("Remotes")
			local function die(id: number, typeId: number, by: number)
				sim:run("die", function()
					remotes
						:WaitForChild("CombatEvents").OnClientEvent
						:Fire({ { 3, id, 0, 3, -12, typeId, by } })
				end)
			end
			local function words(): { string }
				local out = {}
				for _, d in sim.workspace:GetDescendants() do
					if d:IsA("TextLabel") then
						for _, w in Config.Fx.robots.ko.words do
							if d.Text == w then
								table.insert(out, w)
							end
						end
					end
				end
				return out
			end
			local grunt = Config.Enemies.BurglarBot.typeId
			die(901, grunt, sim.player.UserId + 1)
			check(#words() == 0 and thuds == 0 and stops == 0, "another hero's kill adds nothing of yours")
			die(902, grunt, sim.player.UserId)
			check(#words() == 1, "a gold KO word over it (" .. table.concat(words(), ",") .. ")")
			check(thuds == 1, "the low heavy thud (" .. thuds .. ")")
			check(stops == 1, "a hit stop on your own hero")
			local big = 0
			for _, a in shakes do
				big = math.max(big, a)
			end
			check(big >= Config.Fx.robots.ko.shake[2], "a heavy shake (" .. big .. ")")
			-- a sweep: three down at once show one word, every one still thuds once the sound's gap allows
			die(903, grunt, sim.player.UserId)
			die(904, grunt, sim.player.UserId)
			check(#words() == 1, "one word for a sweep")
			-- an elite gets FinisherFx's slow-mo, not this
			local eliteType
			for _, e in Config.Enemies do
				if type(e) == "table" and e.elite and e.typeId then
					eliteType = e.typeId
				end
			end
			if eliteType then
				sim:advance(1)
				local before = #words()
				die(905, eliteType, sim.player.UserId)
				check(#words() == before, "an elite's knockout is FinisherFx's")
			end
			-- Reduce flashing: no stop or shake, the word and the sound stay
			Camera.reduceMotion = true
			sim:advance(1)
			local s0, n0 = stops, #shakes
			die(906, grunt, sim.player.UserId)
			check(stops == s0, "no hit stop with Reduce flashing")
			local extra = 0
			for i = n0 + 1, #shakes do
				if shakes[i] >= Config.Fx.robots.ko.shake[2] then
					extra += 1
				end
			end
			check(extra == 0, "no heavy shake with Reduce flashing")
			Camera.reduceMotion = false
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
		end
	)

	test("First 30: Patch says where the Contract Board is on the level it opens", function()
		local GuidePlan = require("../src/shared/GuidePlan")
		local L = Config.Contracts.board.minLevel
		check(GuidePlan.boardAt(Config, L) == "boardOpen", "the board's level has the line")
		check(
			GuidePlan.boardAt(Config, L - 1) == nil and GuidePlan.boardAt(Config, L + 1) == nil,
			"only that level"
		)
		for _, side in { "hero", "villain" } do
			local l = GuidePlan.worldLine(Config, "boardOpen", side)
			check(
				l ~= nil and string.find(l.text, "safehouse", 1, true) ~= nil,
				side .. ": names the safehouse"
			)
			check(l ~= nil and string.find(l.text, "MAP", 1, true) ~= nil, side .. ": points at the MAP")
		end
		local R = { last = -1000, idleAt = -1000, once = {} }
		local ctx = { on = true, busy = false }
		check(GuidePlan.radioOk(Config, R, 0, "boardOpen", ctx), "said when the radio is free")
		GuidePlan.radioMark(R, 0, "boardOpen")
		check(not GuidePlan.radioOk(Config, R, 1000, "boardOpen", ctx), "once a session")
	end)
	test(
		"First 30: an untimed prologue prompt holds the server's clocks (the Spark never fires by itself)",
		function()
			local QtePlan = require("../src/shared/QtePlan")
			local O = Config.Story.opening
			local Q = O.qte
			check(Q.wait == true, "prompts wait by default")
			-- the spark beat with its prompt up for 60 s: the backstop (O.spark.auto) never comes due
			local r = { qteUp = true, stepAt = 0, startedAt = 0 }
			local dt = 1 / 30
			local now = 0
			for _ = 1, 60 * 30 do
				now += dt
				QtePlan.holdClocks(Config, r, dt)
			end
			check(now - r.stepAt < 1e-6, "the beat's clock held for a minute")
			check(now - r.stepAt < O.spark.auto, "so the Spark's backstop never fires while the prompt waits")
			check(now - r.startedAt < O.timeout, "and the whole prologue's timeout holds too")
			-- answered (OpeningAct 9): the clocks run again
			r.qteUp = false
			check(not QtePlan.holdClocks(Config, r, dt), "an answered prompt holds nothing")
			-- an away player: the hold ends after waitMax s in all
			local away = { qteUp = true, stepAt = 0, startedAt = 0 }
			local held = 0
			for _ = 1, math.ceil((Q.waitMax + 5) / 0.5) do
				if QtePlan.holdClocks(Config, away, 0.5) then
					held += 0.5
				end
			end
			check(
				held >= Q.waitMax and held <= Q.waitMax + 0.5,
				"the hold stops at waitMax (an away player still finishes)"
			)
			-- timed prompts (wait off) hold nothing
			local Timed = { Story = { opening = { qte = setmetatable({ wait = false }, { __index = Q }) } } }
			check(
				not QtePlan.holdClocks(Timed, { qteUp = true, stepAt = 0, startedAt = 0 }, dt),
				"wait off: no hold"
			)
			-- the runtime path: the server holds before any clock is read, takes 8 and 9, and the device sends them
			local svc = fs.readFile("src/server/Services/OpeningService.luau")
			local stepFn = string.match(svc, "local function step%(r: Run.-\nend\n") or ""
			local h = string.find(stepFn, "QtePlan.holdClocks(Config, r, dt)", 1, true)
			local t = string.find(stepFn, "now - r.startedAt > O.timeout", 1, true)
			local sp = string.find(stepFn, "now - r.stepAt >= O.spark.auto", 1, true)
			check(
				h ~= nil and t ~= nil and sp ~= nil and h < t and h < sp,
				"step() holds before the timeout and the Spark"
			)
			check(
				string.find(svc, "act == 8 or act == 9", 1, true) ~= nil,
				"the server takes OpeningAct 8 and 9"
			)
			local run = fs.readFile("src/client/Fx/PrologueQte.luau")
			check(
				string.find(run, 'Net.send("OpeningAct", if up then 8 else 9)', 1, true) ~= nil,
				"the device sends them"
			)
		end
	)

	test(
		"First 30: an untimed prologue prompt stays up, pulses after 3 s and answers only to its key",
		function()
			local sim = newSim()
			sim.fakeClock = true
			sim:run("InputController", sim:require("Client.Controllers.InputController").init)
			local QteHud = sim:require("Client.Ui.QteHud")
			sim:run("QteHud", QteHud.init)
			local QtePlan = require("../src/shared/QtePlan")
			local Q = Config.Story.opening.qte
			sim:run("show", function()
				QteHud.show(Q.words.Leap, "Leap", QtePlan.window(Config, 0), "press")
			end)
			local gui = sim.game.Players.Tester.PlayerGui:FindFirstChild("Qte", true)
			local prompt = gui and gui:FindFirstChild("Prompt", true)
			local key = prompt and prompt:FindFirstChild("Key", true)
			local clock = gui and gui:FindFirstChild("Clock", true)
			check(prompt ~= nil and key ~= nil and clock ~= nil, "the prompt is built")
			if not (prompt and key and clock) then
				return
			end
			check(clock.Visible == false, "no running-out bar on an untimed prompt")
			local paper = key.BackgroundColor3
			local pulsedAt = nil
			local t = 0
			while t < 30 do
				sim:advance(0.1)
				t += 0.1
				sim:run("frame", QteHud.frame)
				if pulsedAt == nil and key.BackgroundColor3 ~= paper then
					pulsedAt = t
				end
			end
			check(QteHud.isOpen() and prompt.Visible, "still up after 30 s")
			check(
				pulsedAt ~= nil and pulsedAt >= Q.nag.after - 0.05 and pulsedAt <= Q.nag.after + 0.25,
				"it pulses at " .. Q.nag.after .. " s (" .. tostring(pulsedAt) .. ")"
			)
			check(QtePlan.judge(Config, "Leap", "Block", 30, 0) == nil, "a wrong key 30 s in is ignored")
			check(QtePlan.judge(Config, "Leap", "Leap", 30, 0) == "hit", "the right key 30 s in hits")
			sim:run("hit", function()
				QteHud.result("hit")
			end)
			check(not QteHud.isOpen() and not prompt.Visible, "answered: the prompt goes")
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
		end
	)
	test(
		"First 30 polish: a letterboxed cutscene owns the FOV, clears the side HUD and eases back after",
		function()
			local sim = newSim()
			sim.fakeClock = true
			sim:run("InputController", sim:require("Client.Controllers.InputController").init)
			local Kit = sim:require("Client.Ui.Kit")
			local CameraController = sim:require("Client.Controllers.CameraController")
			local CinemaClient = sim:require("Client.Controllers.CinemaClient")
			local CinemaHud = sim:require("Client.Ui.CinemaHud")
			local CinemaPlan = require("../src/shared/CinemaPlan")
			sim:run("CinemaClient", CinemaClient.init)
			sim:run("CinemaHud", CinemaHud.init)
			local toasts, plates, stay
			sim:run("screens", function()
				toasts = Kit.screen("Toasts", 1)
				plates = Kit.screen("Plates", 1)
				stay = Kit.screen("GuideHud", 1)
			end)
			local function frames(n: number)
				for _ = 1, n do
					sim:renderFrame(1 / 60)
				end
			end
			plates.Enabled = false -- hidden before the scene: stays hidden after it
			local def = Config.Cinema.scenes.cityWatch
			local shots = CinemaPlan.around(def.shots, 0, 10, 0)
			local ok
			sim:run("play", function()
				ok =
					CinemaClient.play({ owner = "mission", key = 1, beat = true, shots = shots, seconds = 6 })
			end)
			check(ok == true, "the scene plays")
			frames(5)
			check(CinemaClient.letterboxed(), "letterboxed")
			check(CameraController.fovOverride == Config.Cinema.camera.fov, "the scene holds its own FOV")
			check(toasts.Enabled == false, "the toasts step aside")
			check(stay.Enabled == true, "the subtitles' screen stays")
			local focus = sim.game:GetService("Lighting"):FindFirstChild("CinemaFocus")
			check(
				focus ~= nil and focus.Enabled and focus.FarIntensity > 0,
				"a soft depth of field on the shots"
			)
			sim:run("stop", function()
				CinemaClient.stop("mission")
			end)
			frames(5)
			check(CameraController.fovOverride == nil, "the FOV is the game's again")
			frames(40)
			check(focus ~= nil and not focus.Enabled, "the depth of field eases off after the scene")
			local NpcAnim = require("../src/shared/NpcAnim")
			check(
				NpcAnim.CLIPS[NpcAnim.crowd.waiting].loop == true,
				"the stage's waiting clip loops (no statues)"
			)
			check(NpcAnim.CLIPS.talk.loop == true, "Lodestar's talk clip loops")
			local fx = fs.readFile("src/client/Fx/PrologueFx.luau")
			check(
				string.find(fx, "NpcAnim.crowd.waiting", 1, true) ~= nil,
				"the stage keeps posing after the Ceremony"
			)
			local sfx = fs.readFile("src/client/Fx/StoryFx.luau")
			check(
				string.find(sfx, 'then "talk" else NpcAnim.crowd.waiting', 1, true) ~= nil,
				"Lodestar talks in a beat"
			)
			check(toasts.Enabled == true, "the toasts come back")
			check(plates.Enabled == false, "a screen hidden before the scene stays hidden")
			check(Config.Cinema.camera.blendOut > 0, "the end eases back to the follow camera")
			check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
		end
	)
	test("First 30: the music follows what is going on (MusicPlan)", function()
		local MusicPlan = require("../src/shared/MusicPlan")
		local M = Config.Audio.music
		local C = Config.Audio.musicContext
		local function pick(ctx)
			return MusicPlan.pick(Config, ctx)
		end
		check(
			pick({}) == "patrolDay" and pick({ night = true }) == "patrolNight",
			"the patrol loops by day and night"
		)
		check(pick({ override = "victory", menu = true }) == "victory", "the intro film's own pick first")
		check(pick({ menu = true, boss = true }) == C.menu, "the creator and menu are calm")
		check(pick({ opening = "ceremony" }) == "ceremony", "the Ceremony's fanfare")
		check(pick({ opening = "chase" }) == "chase" and pick({ opening = "tunnel" }) == "chase", "the chase")
		check(pick({ opening = "fight" }) == "combat", "the subway fight")
		check(pick({ boss = true, mission = true }) == "boss", "a live boss near")
		check(pick({ scene = true, hitAgo = 1 }) == C.scene, "a cutscene")
		check(pick({ hq = true, hitAgo = 1 }) == "hq", "an HQ")
		check(pick({ underwater = true }) == "deep", "the deep")
		check(pick({ mission = true }) == "mission", "a mission between fights")
		check(pick({ mission = true, hitAgo = 2 }) == "combat", "a fight in a mission")
		check(pick({ hitAgo = C.combatHold - 0.5 }) == "combat", "a fight in the city")
		check(pick({ hitAgo = C.combatHold + 1 }) == "patrolDay", "the fight loop lets go after the last hit")
		check(
			pick({ hitAgo = C.combatHold + 1, enemyNear = C.enemyRange - 1 }) == "combat",
			"a robot close holds it"
		)
		check(pick({ hitAgo = C.combatNear + 1, enemyNear = 5 }) == "patrolDay", "but not for ever")
		-- every loop the plan can pick has its spec and a clip in the Music atlas
		local names =
			{ "patrolDay", "patrolNight", "boss", C.menu, C.scene, C.hq, C.deep, C.mission, C.combat }
		for _, v in C.opening do
			table.insert(names, v)
		end
		for _, n in names do
			check(M[n] ~= nil and Config.AudioClips.clips[M[n].clip] ~= nil, n .. ": a track with a clip")
		end
		for step in Config.Audio.musicContext.opening do
			check(require("../src/shared/OpeningPlan").CODE[step] ~= nil, step .. " is a prologue beat")
		end
		for _, step in require("../src/shared/OpeningPlan").STEPS do
			check(C.opening[step] ~= nil, step .. " has its music")
		end
		check(Config.AudioClips.atlases.Music > 0, "the Music atlas is uploaded")
		-- the runtime path: the device fills the context and AudioController asks the plan
		local boot = fs.readFile("src/client/init.client.luau")
		check(
			string.find(boot, "AudioController.musicContext = function()", 1, true) ~= nil,
			"the boot fills it"
		)
		local ac = fs.readFile("src/client/Controllers/AudioController.luau")
		check(string.find(ac, "MusicPlan.pick(Config, ctx)", 1, true) ~= nil, "AudioController asks the plan")
	end)
	test("First 30: impact frames: big blows cut to black and white ink frames (ImpactFrames)", function()
		local ImpactFrames = require("../src/shared/ImpactFrames")
		local I = Config.Cinema.impactFrames
		local last = { kind = nil, at = -math.huge }
		local p = ImpactFrames.plan(Config, "crit", "Comic", false, 10, last)
		check(p ~= nil and #p.frames == I.frames.crit, "a crit cuts for its frames")
		check(p ~= nil and #p.frames >= 2 and #p.frames <= 4, "2 to 4 frames")
		check(
			p ~= nil and p.frames[1].look == "white" and p.frames[2].look == "black",
			"Comic: white, then inked black"
		)
		check(
			ImpactFrames.plan(Config, "crit", "Comic", false, 10.3, last) == nil,
			"a hail of crits cuts once"
		)
		local s = ImpactFrames.plan(Config, "super", "Anime", false, 10.4, last)
		check(s ~= nil and s.frames[1].look == "black" and #s.frames == I.frames.super, "Anime: black first")
		check(s ~= nil and s.lines > (p :: any).lines, "Anime draws more, thinner lines")
		check(
			ImpactFrames.plan(Config, "crit", "Anime", false, 10.5, last) == nil,
			"no small cut over a big one"
		)
		local f = ImpactFrames.plan(Config, "finisher", "Comic", false, 10.45, last)
		check(f ~= nil and #f.frames == 4, "a finisher always cuts, 4 frames")
		check(
			ImpactFrames.plan(Config, "crit", "Comic", false, 10.45 + I.gap.crit + 0.1, last) ~= nil,
			"later crits cut again"
		)
		-- the frames run back to back and end
		local fp = f :: any
		check(
			ImpactFrames.at(fp, 0) == fp.frames[1] and ImpactFrames.at(fp, fp.seconds + 0.01) == nil,
			"it ends"
		)
		check(fp.seconds <= 0.2, "short: a cut, not a pause (" .. fp.seconds .. " s)")
		local a1 = ImpactFrames.line(fp, 3, 42)
		local a2 = ImpactFrames.line(fp, 3, 42)
		check(a1 == a2, "a line holds still between frames (no flicker)")
		-- Reduce flashing: never a frame, a gentle hit stop instead
		local g = ImpactFrames.plan(Config, "finisher", "Comic", true, 50, { kind = nil, at = -math.huge })
		check(g ~= nil and #g.frames == 0 and g.gentle == I.gentle, "Reduce flashing: a gentle hit stop")
		-- the runtime path: crits and supers (CombatClient) and finishers (FinisherFx) call the cut
		local cc = fs.readFile("src/client/Controllers/CombatClient.luau")
		check(string.find(cc, "ImpactFrameFx.cut(", 1, true) ~= nil, "CombatClient cuts on crits and supers")
		local fin = fs.readFile("src/client/Fx/FinisherFx.luau")
		check(string.find(fin, 'ImpactFrameFx.cut("finisher", at)', 1, true) ~= nil, "finishers cut")
		local boot = fs.readFile("src/client/init.client.luau")
		check(string.find(boot, "ImpactFrameFx.init()", 1, true) ~= nil, "it runs")
	end)

	test("First 30: impact frames draw on screen and clear (UiSim)", function()
		local sim = newSim()
		sim.fakeClock = true
		sim:run("InputController", sim:require("Client.Controllers.InputController").init)
		local ImpactFrameFx = sim:require("Client.Fx.ImpactFrameFx")
		local CameraController = sim:require("Client.Controllers.CameraController")
		sim:run("init", ImpactFrameFx.init)
		local RS = sim.game:GetService("RunService")
		local function frames(n: number)
			for _ = 1, n do
				sim:advance(1 / 60)
				for _, h in table.clone(RS.RenderStepped.handlers) do
					sim:run("RenderStepped", function()
						h(1 / 60)
					end)
				end
			end
		end
		sim:run("cut", function()
			ImpactFrameFx.cut("finisher", nil)
		end)
		frames(1)
		local gui = sim.game.Players.Tester.PlayerGui:FindFirstChild("ImpactFrame")
		local cc = sim.game:GetService("Lighting"):FindFirstChild("ImpactFrame")
		check(gui ~= nil and gui.Enabled, "the cut shows over the HUD")
		check(cc ~= nil and cc.Enabled and cc.Saturation == -1, "the picture goes black and white")
		local shown = 0
		if gui then
			for _, c in gui:GetChildren() do
				if string.sub(c.Name, 1, 4) == "Line" and c.Visible then
					shown += 1
				end
			end
		end
		check(shown == Config.Cinema.impactFrames.lines.Comic, "its ink lines burst out (" .. shown .. ")")
		frames(20)
		check(gui ~= nil and not gui.Enabled and cc ~= nil and not cc.Enabled, "and it clears")
		-- Reduce flashing: nothing on screen
		CameraController.reduceMotion = true
		sim:advance(5)
		sim:run("cut2", function()
			ImpactFrameFx.cut("finisher", nil)
		end)
		frames(1)
		check(gui ~= nil and not gui.Enabled, "Reduce flashing: no frame")
		CameraController.reduceMotion = false
		check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
	end)
	test(
		"First 30 polish: a cutscene's subtitles, bars and SKIP never overlap, on a phone and a PC",
		function()
			local UiSim = require("./uisim")
			local trees = UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath)))
			for _, d in
				{
					{
						name = "PC",
						w = 1280,
						h = 720,
						top = 36,
						left = 0,
						right = 0,
						bottom = 0,
						touch = false,
					},
					{
						name = "Phone",
						w = 844,
						h = 390,
						top = 0,
						left = 47,
						right = 47,
						bottom = 21,
						touch = true,
					},
				}
			do
				local sim = UiSim.new(trees, d)
				sim.fakeClock = true
				sim:run("InputController", sim:require("Client.Controllers.InputController").init)
				local CinemaClient = sim:require("Client.Controllers.CinemaClient")
				local CinemaHud = sim:require("Client.Ui.CinemaHud")
				local GuideHud = sim:require("Client.Ui.GuideHud")
				sim:run("CinemaClient", CinemaClient.init)
				sim:run("GuideHud", GuideHud.init)
				sim:run("CinemaHud", CinemaHud.init)
				local CinemaPlan = require("../src/shared/CinemaPlan")
				local def = Config.Cinema.scenes.cityWatch
				sim:run("play", function()
					CinemaClient.play({
						owner = "client",
						key = "t",
						bit = def.bit,
						shots = CinemaPlan.around(def.shots, 0, 10, 0),
						seconds = 12,
						lines = def.lines,
					})
				end)
				-- a seen scene: SKIP shows after its delay
				for _ = 1, 150 do
					sim:renderFrame(1 / 30)
				end
				local shown = {}
				for _, b in sim:boxes() do
					if b.screen.Name == "GuideHud" or b.screen.Name == "CinemaHud" then
						shown[b.screen.Name] = true
					end
				end
				check(shown.GuideHud and shown.CinemaHud, d.name .. ": the bars and a subtitle are up")
				local issues = sim:issues({ only = { CinemaHud = true, GuideHud = true } })
				local bad = {}
				for _, i in issues do
					if string.find(i, "overlap", 1, true) or string.find(i, "off", 1, true) then
						table.insert(bad, i)
					end
				end
				check(#bad == 0, d.name .. ": " .. table.concat(bad, " | "))
				check(#sim.errors == 0, d.name .. " no errors: " .. table.concat(sim.errors, " | "))
			end
		end
	)
end
