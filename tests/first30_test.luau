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
				check(MT.how[id] ~= nil, id .. " says how to do it")
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
end
