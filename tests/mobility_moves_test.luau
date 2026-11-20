-- The mobility upgrade rework (nate, 2026-11-20): ranks 3 and 5 of each pick are a choice of two moves (Config.Move
-- moves and each rank row's `choice`; Shared.MoveRanks; save v16 mobMoves). Called from tests/run.luau;
-- ONLY="Mobility moves" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local MoveRanks = require("../src/shared/MoveRanks")
	local ProfileSchema = require("../src/shared/ProfileSchema")
	local M = Config.Move

	test(
		"Mobility moves: ranks 3 and 5 offer two moves each, 20 in all, every number inside the caps",
		function()
			check(#MoveRanks.check(M) == 0, "MoveRanks.check: " .. table.concat(MoveRanks.check(M), "; "))
			local seen = {}
			for _, pick in M.mobilityOrder do
				for _, r in M.choices do
					local opts = MoveRanks.options(M, pick, r)
					check(opts ~= nil and #opts == 2, pick .. " rank " .. r .. " offers two")
					for _, id in opts or {} do
						check(not seen[id], id .. " belongs to one rank")
						seen[id] = true
					end
				end
				for _, r in { 1, 2, 4 } do
					check(
						MoveRanks.options(M, pick, r) == nil,
						pick .. " rank " .. r .. " stays a number bump"
					)
				end
			end
			local n = 0
			for id in M.moves do
				n += 1
				check(seen[id], id .. " is offered somewhere")
			end
			check(n == 20, "20 moves (" .. n .. ")")
			check(MoveRanks.slots(M) == 10, "10 saved picks")
		end
	)

	test("Mobility moves: picking, the first pick anywhere, swaps at a safehouse, kept per pick", function()
		local ranks = MoveRanks.withRank(M, nil, "flight", 3)
		local moves = MoveRanks.withChoice(M, nil, "flight", 3, 0)
		check(MoveRanks.moveOf(M, ranks, moves, "flight", 3) == nil, "nothing until picked")
		local ok, why = MoveRanks.canChoose(M, ranks, moves, "flight", 5, 1, true)
		check(not ok and why == "rank", "rank 5 is not trained")
		ok = MoveRanks.canChoose(M, ranks, moves, "flight", 3, 2, false)
		check(ok, "the first pick needs no safehouse")
		moves = MoveRanks.withChoice(M, moves, "flight", 3, 2)
		check(MoveRanks.moveOf(M, ranks, moves, "flight", 3) == "slipstream", "Slipstream picked")
		ok, why = MoveRanks.canChoose(M, ranks, moves, "flight", 3, 1, false)
		check(not ok and why == "safehouse", "a swap away from a safehouse is refused")
		ok = MoveRanks.canChoose(M, ranks, moves, "flight", 3, 1, true)
		check(ok, "a swap at a safehouse is fine")
		ok, why = MoveRanks.canChoose(M, ranks, moves, "flight", 3, 2, true)
		check(not ok and why == "same", "the same pick again")
		ok, why = MoveRanks.canChoose(M, ranks, moves, "flight", 3, 3, true)
		check(not ok and why == "option", "only options 1 and 2")
		check(MoveRanks.active(M, ranks, moves, "flight").slipstream == true, "active on its pick")
		check(next(MoveRanks.active(M, ranks, moves, "speed")) == nil, "not on another pick")
		-- the speed pick's slots are its own
		local both = MoveRanks.withChoice(M, moves, "speed", 5, 1)
		check(
			MoveRanks.picked(M, both, "flight", 3) == 2 and MoveRanks.picked(M, both, "speed", 5) == 1,
			"kept per pick"
		)
		-- untrained back down (a stale save): the pick does nothing
		check(
			MoveRanks.moveOf(M, { 2, 0, 0, 0, 0 }, moves, "flight", 3) == nil,
			"a pick past the trained rank is off"
		)
	end)

	test("Mobility moves: save v16 keeps a pick per hero and cleans bad ones", function()
		check(ProfileSchema.VERSION >= 16, "save v16")
		local fresh = ProfileSchema.load(nil)
		local c = fresh.characters[1]
		check(type(c.mobMoves) == "table" and #c.mobMoves == 10, "ten zeros on a new hero")
		local old = ProfileSchema.load({ version = 15, characters = { { mobRanks = { 3, 0, 0, 0, 0 } } } })
		check(
			#old.characters[1].mobMoves == 10 and old.characters[1].mobMoves[1] == 0,
			"a v15 save starts unpicked"
		)
		local bad = ProfileSchema.load({
			version = 16,
			characters = { { mobMoves = { 1, 9, -1, "x", 2, 0, 0, 0, 0, 0, 7 } } },
		})
		local mm = bad.characters[1].mobMoves
		check(
			#mm == 10 and mm[1] == 1 and mm[2] == 0 and mm[3] == 0 and mm[4] == 0 and mm[5] == 2,
			"repaired"
		)
	end)

	test("Mobility moves: the server path and the LOADOUT cards", function()
		local remotes = fs.readFile("src/shared/Remotes.luau")
		check(string.find(remotes, "MoveChoose = {", 1, true) ~= nil, "MoveChoose remote")
		local ab = fs.readFile("src/server/Services/AbilityService.luau")
		check(string.find(ab, 'Net.on("MoveChoose"', 1, true) ~= nil, "handled")
		check(string.find(ab, "SafehouseService.canSwap(hero)", 1, true) ~= nil, "swaps at a safehouse")
		local hs = fs.readFile("src/server/Services/HeroService.luau")
		check(string.find(hs, "function HeroService.hasMove(", 1, true) ~= nil, "HeroService.hasMove")
		check(string.find(hs, "char.mobMoves = table.clone(hero.mobMoves)", 1, true) ~= nil, "saved")
		local ui = fs.readFile("src/client/Ui/LoadoutScreen.luau")
		check(string.find(ui, 'Net.send("MoveChoose", rank, k)', 1, true) ~= nil, "the PICK button")
		check(string.find(ui, 'Kit.icon("mobmove", id', 1, true) ~= nil, "with the move's icon")
	end)
	test("Mobility moves: the MOBILITY tab shows each choice rank's two moves as cards with icons", function()
		if not T.placePath then
			return
		end
		local roblox = require("@lune/roblox")
		local UiSim = require("./uisim")
		local sim = UiSim.new(
			UiSim.load(roblox.deserializePlace(fs.readFile(T.placePath))),
			{ name = "PC", w = 1280, h = 720, top = 36, left = 0, right = 0, bottom = 0, touch = false }
		)
		sim:run("InputController", sim:require("Client.Controllers.InputController").init)
		local State = sim:require("Client.State")
		local Loadout = sim:require("Client.Ui.LoadoutScreen")
		sim:run("LoadoutScreen", Loadout.init)
		State.hero.mobility = "flight"
		State.hero.mobRanks = { 3, 0, 0, 0, 0 }
		State.hero.mobMoves = { 2, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
		State.hero.level = 25
		local sent = {}
		local remote = sim.service("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("MoveChoose")
		remote._props.FireServer = function(_, ...)
			table.insert(sent, { ... })
		end
		sim:run("open", Loadout.open)
		local panel = sim.playerGui:FindFirstChild("Loadout")
		local tab = panel and panel:FindFirstChild("MobilityTab", true)
		check(tab ~= nil, "the MOBILITY tab")
		if not tab then
			return
		end
		sim:run("tab", function()
			sim:tap(tab)
		end)
		local function card(name: string)
			return panel:FindFirstChild(name, true)
		end
		local a, b = card("Move3_1"), card("Move3_2")
		check(a ~= nil and b ~= nil, "rank 3's two move cards")
		check(card("Move5_1") ~= nil and card("Move5_2") ~= nil, "rank 5's two move cards")
		if a and b then
			check(a:FindFirstChild("MoveIcon") ~= nil, "with the move's icon")
			check(string.find(a:FindFirstChild("MoveName").Text, "SONIC BOOM DIVE", 1, true) ~= nil, "named")
			check(a:FindFirstChild("MoveText").Text == M.moves.sonicDive.text, "and what it does")
			-- Slipstream is picked; tapping Sonic Boom Dive asks the server for option 1
			local buttons = {}
			for _, d in a:GetChildren() do
				if d.ClassName == "TextButton" then
					table.insert(buttons, d)
				end
			end
			check(#buttons == 1 and buttons[1].Text == "SWAP", "the other move offers a swap")
			sim:run("pick", function()
				sim:tap(buttons[1])
			end)
			check(#sent == 1 and sent[1][1] == 3 and sent[1][2] == 1, "MoveChoose 3, 1 sent")
		end
		local five = card("Move5_1")
		if five then
			for _, d in five:GetChildren() do
				if d.ClassName == "TextButton" then
					check(d.Text == "RANK 5 FIRST", "rank 5 waits for its training")
				end
			end
		end
		check(#sim.errors == 0, "no errors: " .. table.concat(sim.errors, " | "))
	end)
end
