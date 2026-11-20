-- Every ability's own look (nate's playtest 2026-11-19: "Need more unique effects"). Each of the 136 powers has
-- a recipe in Config.FxMoves (flair, hit, trail, a screen moment for supers, optional head, mark and cast swaps)
-- drawn by the client's Fx/AbilityFx on top of its path's look. Checked here:
--   * every power has a recipe whose names AbilityFx draws, and weapon moves have none
--   * inside a path no two moves share a flair, a hit, or (among moves that fly) a trail, and no swap repeats
--     what the path already draws
--   * the particle and piece budgets per device preset (phones fewer) hold for every move, with a super's path
--     moment on top, and basics stay light
--   * CombatFx and CombatClient wire it in, nothing runs per frame, and the two new sheets fall back to built-in
--     images until they are uploaded
-- Called from tests/run.luau: require("./fx_unique_test")({ test = test, check = check, Config = Config })
-- ONLY="FX unique" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local FxPlan = require("../src/shared/FxPlan")

	local A = Config.Abilities
	local M = Config.FxMoves
	local F = Config.Fx
	local L = F.lib

	local function has(list: { string }, name: string?): boolean
		return name ~= nil and table.find(list, name) ~= nil
	end
	local function read(path: string): string
		return fs.readFile(path)
	end

	-- every power (the 136, not the weapons' moves that join A.list), by path
	local powers: { any } = {}
	local byPath: { [string]: { any } } = {}
	for _, row in A.list do
		if row.set ~= "Weapon" then
			table.insert(powers, row)
			byPath[row.set] = byPath[row.set] or {}
			table.insert(byPath[row.set], row)
		end
	end

	test("FX unique: every power has its own recipe, every name is drawn, weapon moves have none", function()
		check(#powers == 136, "136 powers (got " .. #powers .. ")")
		local n = 0
		for id in M.moves do
			n += 1
			check(A.list[id] ~= nil and A.list[id].set ~= "Weapon", id .. " is a power")
		end
		check(n == #powers, "one recipe a power (" .. n .. ")")
		for _, row in powers do
			local r = FxPlan.recipeOf(M, row.id)
			check(r ~= nil, row.id .. " has a recipe")
			if r then
				check(
					has(FxPlan.FLAIRS, r.flair) and r.flair ~= "none",
					row.id .. " flair " .. tostring(r.flair)
				)
				check(has(FxPlan.HITS, r.hit) and r.hit ~= "none", row.id .. " hit " .. tostring(r.hit))
				if FxPlan.TRAVEL[row.shape] then
					check(
						has(FxPlan.TRAILS, r.trail) and r.trail ~= "none",
						row.id .. " flies: trail " .. tostring(r.trail)
					)
				else
					check(r.trail == nil, row.id .. " does not fly: no trail")
				end
				if row.slot == "super" then
					check(
						has(FxPlan.SCREENS, r.screen) and r.screen ~= "none",
						row.id .. " super has a screen moment"
					)
				elseif FxPlan.SKILL_SCREENS[row.id] then
					check(r.screen == FxPlan.SKILL_SCREENS[row.id], row.id .. " has its own screen")
				else
					check(r.screen == nil, row.id .. " only supers have screen moments")
				end
				check(r.head == nil or has(FxPlan.HEADS, r.head), row.id .. " head swap is drawn")
				check(r.mark == nil or has(FxPlan.MARKS, r.mark), row.id .. " mark swap is drawn")
				check(r.cast == nil or has(FxPlan.CASTS, r.cast), row.id .. " cast swap is drawn")
				check(
					r.head == nil or FxPlan.TRAVEL[row.shape] or row.shape == "cone",
					row.id .. " head swap flies"
				)
				local size = r.size or 1
				check(size >= 0.6 and size <= 1.6, row.id .. " size stays near the path's")
			end
		end
		-- the weapons' moves keep their own visuals
		local weapons = 0
		for _, row in A.list do
			if row.set == "Weapon" then
				weapons += 1
				check(FxPlan.recipeOf(M, row.id) == nil, row.id .. " (weapon) has no recipe")
			end
		end
		check(weapons > 0, "weapon moves are in the list")
		check(FxPlan.recipeOf(M, nil) == nil and FxPlan.recipeOf(M, "Nope") == nil, "unknown ids have none")
		-- the kit names match FxPlan's lists both ways, and every particle kind exists
		for kind, list in { trail = FxPlan.TRAILS, hit = FxPlan.HITS, flair = FxPlan.FLAIRS } do
			for _, name in list do
				check(M.kit[kind][name] ~= nil, kind .. " " .. name .. " has a cost row")
			end
			for name, row in M.kit[kind] do
				check(has(list, name), kind .. " " .. name .. " is listed")
				check(row.parts >= 0 and row.parts <= 8, kind .. " " .. name .. " piece count is small")
				for fx, c in row.fx do
					check(fx == "shock" or L.kinds[fx] ~= nil, kind .. " " .. name .. " uses kind " .. fx)
					check(c >= 1 and c <= 10, kind .. " " .. name .. " count " .. fx)
				end
			end
		end
		-- AbilityFx draws every name
		local src = read("src/client/Fx/AbilityFx.luau")
		for prefix, list in
			{ TRAIL = FxPlan.TRAILS, HIT = FxPlan.HITS, FLAIR = FxPlan.FLAIRS, SCREEN = FxPlan.SCREENS }
		do
			for _, name in list do
				check(
					string.find(src, prefix .. "." .. name .. " = function", 1, true) ~= nil,
					"AbilityFx draws " .. prefix .. "." .. name
				)
			end
		end
	end)

	test("FX unique: inside a path every move reads as its own", function()
		check(#(function()
			local t = {}
			for set in byPath do
				table.insert(t, set)
			end
			return t
		end)() == 17, "17 paths")
		for set, rows in byPath do
			local p = F.paths[set]
			local flairs, hits, trails, keys = {}, {}, {}, {}
			for _, row in rows do
				local r = M.moves[row.id]
				if r then
					check(
						not flairs[r.flair],
						set .. ": " .. row.id .. " has its own flair (" .. r.flair .. ")"
					)
					check(not hits[r.hit], set .. ": " .. row.id .. " has its own hit (" .. r.hit .. ")")
					flairs[r.flair] = true
					hits[r.hit] = true
					if r.trail then
						check(
							not trails[r.trail],
							set .. ": " .. row.id .. " has its own trail (" .. r.trail .. ")"
						)
						trails[r.trail] = true
					end
					local key = FxPlan.recipeKey(r)
					check(not keys[key], set .. ": " .. row.id .. " recipe is its own")
					keys[key] = true
					-- a swap never repeats what the path already draws, and a flair never doubles the path's cast
					check(r.head == nil or r.head ~= p.head, row.id .. " head swap differs from the path's")
					check(r.mark == nil or r.mark ~= p.mark, row.id .. " mark swap differs from the path's")
					check(r.cast == nil or r.cast ~= p.cast, row.id .. " cast swap differs from the path's")
					check(r.flair ~= p.cast, row.id .. " flair does not double the path's flourish")
				end
			end
		end
		-- the recipe key really tells two recipes apart
		check(
			FxPlan.recipeKey({ flair = "sigil", hit = "ring" })
				~= FxPlan.recipeKey({ flair = "sigil", hit = "crater" }),
			"keys differ by hit"
		)
		check(
			FxPlan.recipeKey({ flair = "sigil", hit = "ring" })
				~= FxPlan.recipeKey({ flair = "sigil", hit = "ring", mark = "pow" }),
			"keys differ by a mark swap"
		)
		-- different shapes in a path keep their look: supers stand out by size
		for _, row in powers do
			local r = M.moves[row.id]
			if row.slot == "super" then
				check(FxPlan.recipeSize(M, r, "super") >= 1.3, row.id .. " super draws big")
			elseif row.slot == "basic" then
				check(
					FxPlan.recipeSize(M, r, "basic") < FxPlan.recipeSize(M, r, "skill"),
					row.id .. " basic draws smaller"
				)
			end
		end
	end)

	test("FX unique: the budgets hold on every preset, phones draw fewer, basics stay light", function()
		local K = M.kit
		check(K.share > 0 and K.share <= 0.25, "a move takes a small share of a second's particles")
		check(K.partShare > 0 and K.partShare <= 0.6, "and of the pieces")
		check(K.basicScale < 1 and K.othersScale < 1, "basics and others' moves draw smaller")
		local totals: { [string]: number } = {}
		for _, row in powers do
			local r = M.moves[row.id]
			local el = FxPlan.elementOf(L, row.set)
			local prevP, prevQ = -1, -1
			for _, preset in Config.Presets.order do
				local scale = if row.slot == "basic" then K.basicScale else 1
				local particles, parts = FxPlan.moveCost(L, M, r, preset, L.superTargets, scale)
				totals[preset] = (totals[preset] or 0) + particles + parts
				check(
					particles <= L.budget[preset] * K.share,
					string.format("%s on %s: %d particles of %d", row.id, preset, particles, L.budget[preset])
				)
				check(
					parts <= L.partBudget[preset] * K.partShare,
					string.format("%s on %s: %d pieces of %d", row.id, preset, parts, L.partBudget[preset])
				)
				check(
					particles >= prevP and parts >= prevQ,
					row.id .. " never draws more on a smaller preset"
				)
				prevP, prevQ = particles, parts
				if row.slot == "super" then
					local whole = FxPlan.superCost(L, el, L.scale[preset]) + particles
					check(
						whole <= L.budget[preset] * K.withSuper,
						string.format(
							"%s super on %s with its path moment: %d of %d",
							row.id,
							preset,
							whole,
							L.budget[preset]
						)
					)
				end
				if row.slot == "basic" then
					-- two basics a second on one robot each stay a sliver of the budget
					local one = FxPlan.moveCost(L, M, r, preset, 1, K.basicScale)
					check(one * 2 <= L.budget[preset] * 0.08, row.id .. " basic stays light on " .. preset)
				end
			end
		end
		check(totals.low < totals.medium and totals.medium < totals.high, "phones draw the least")
		-- the counting rule: one-offs always show, the rest scale and never vanish
		check(
			FxPlan.count(1, 0.4) == 1 and FxPlan.count(8, 0.4) == 3 and FxPlan.count(2, 0.1) == 1,
			"count rule"
		)
		local p0, q0 = FxPlan.momentCost(L, M, "hit", "none", "high")
		check(p0 == 0 and q0 == 0, "a none moment costs nothing")
		local p1 = FxPlan.momentCost(L, M, "trail", "sparkle", "high", 1, K.trailPoints)
		check(p1 == 2 * K.trailPoints, "a trail emits at each of its points")
	end)

	test("FX unique: CombatFx and CombatClient wire it in, nothing per frame, sheets optional", function()
		local afx = read("src/client/Fx/AbilityFx.luau")
		local cfx = read("src/client/Fx/CombatFx.luau")
		local cc = read("src/client/Controllers/CombatClient.luau")
		local function hasText(src: string, needle: string): boolean
			return string.find(src, needle, 1, true) ~= nil
		end
		-- nothing per frame (tweens and Debris only), and every count comes from the budgets
		check(
			not hasText(afx, "RenderStepped") and not hasText(afx, "Heartbeat"),
			"AbilityFx has no per-frame loop"
		)
		check(
			hasText(afx, "FxLib.pieces(") and hasText(afx, "FxPlan.count("),
			"AbilityFx counts through the budgets"
		)
		check(hasText(afx, 'row.set == "Weapon"'), "AbilityFx never draws weapon moves")
		check(
			not hasText(afx, 'Instance.new("Part")'),
			"AbilityFx builds parts with CombatFx's kit (the Fx folder)"
		)
		check(hasText(afx, "PLACEHOLDER ART"), "AbilityFx is marked placeholder art")
		-- CombatFx hands over its kit and calls each moment
		for _, needle in
			{
				"AbilityFx.init(",
				"AbilityFx.flair(",
				"AbilityFx.travel(",
				"AbilityFx.hit(",
				"AbilityFx.screen(",
				"AbilityFx.headOf(",
				"AbilityFx.markOf(",
				"AbilityFx.castOf(",
				"function CombatFx.begin(",
				"function CombatFx.finish(",
			}
		do
			check(hasText(cfx, needle), "CombatFx: " .. needle)
		end
		-- CombatClient: hits carry the ability, your predicted shapes draw in scope, basics get their flair
		check(hasText(cc, "fxSet, row and row.id)"), "CombatClient passes the ability to impacts")
		check(
			hasText(cc, "CombatFx.begin(id, true)") and hasText(cc, "CombatFx.finish(fxPrev)"),
			"your casts are in scope"
		)
		-- the two new sheets: drawn, listed and uploaded (2026-11-19), with a built-in image kept as the fallback
		for _, name in { "rune", "scorch" } do
			local t = L.textures[name]
			check(
				t ~= nil and t.id > 0 and t.builtin ~= nil,
				name .. " sheet is uploaded, with a built-in fallback"
			)
			check(fs.isFile("art/export/fx/" .. t.file), name .. " sheet is drawn")
			check(
				FxPlan.textureOf(L, name) == "rbxassetid://" .. tostring(t.id),
				name .. " uses its uploaded image"
			)
			check(L.kinds[name] ~= nil and L.kinds[name].face == "flat", name .. " lies flat")
		end
		check(hasText(read("art/fx/textures.py"), "--moves"), "textures.py draws the ability sheets alone")
		-- the per-frame profiler rule still holds for CombatFx (every loop wrapped)
		local loops = 0
		for _ in string.gmatch(cfx, "RenderStepped:Connect%(") do
			loops += 1
		end
		local wrapped = 0
		for _ in string.gmatch(cfx, "RenderStepped:Connect%(FrameProf%.wrap%(") do
			wrapped += 1
		end
		check(loops == wrapped, "CombatFx's per-frame loops are all under FrameProf")
	end)
end
