-- The comic icon set (gap-icons, 2026-11-19): art/icons/icons.py's sheets and Config.Icons. Every power,
-- weapon (and weapon move), mobility pick, gadget, HUD action, gear slot and tier maps to a cell that exists,
-- inside its 1024 px sheet, and no two keys share a cell; the sheet files are 1024 x 1024 PNGs. Called from
-- tests/run.luau. gap-icons2 (2026-11-19): the second set (sheets 5 and 6): every incident, event, contract
-- type, boss, world marker, badge group, collection, accolade, Journal tab, Rogues File group, daily reward,
-- weekly board and movement button, plus the six tintable shape backings and where a symbol sits on each.
-- Called from tests/run.luau:
--   require("./icons_test")({ test = test, check = check, Config = Config })
-- ONLY="Icons" runs just these.

return function(T: any)
	local test, check, Config = T.test, T.check, T.Config
	local fs = require("@lune/fs")
	local IC = Config.Icons

	local function cellOk(at: any, what: string)
		check(type(at) == "table" and #at == 2, what .. " has a { sheet, cell } entry")
		if type(at) ~= "table" then
			return
		end
		local sheet = IC.sheets[at[1]]
		check(sheet ~= nil, what .. " names a real sheet")
		local per = IC.perRow * IC.perRow
		check(at[2] >= 0 and at[2] < per and at[2] % 1 == 0, what .. " cell is inside the sheet")
		local x = (at[2] % IC.perRow) * IC.cell
		local y = (at[2] // IC.perRow) * IC.cell
		check(x + IC.cell <= IC.sheetSize and y + IC.cell <= IC.sheetSize, what .. " rect is in bounds")
	end

	test("Icons: every power, weapon and move maps to a cell", function()
		local n = 0
		for _, id in Config.Abilities.order do
			cellOk(IC.ability[id], "ability " .. id)
			n += 1
		end
		check(n == 136, "136 powers (got " .. n .. ")")
		for _, row in Config.Weapons.list do
			cellOk(IC.weapon[row[1]], "weapon " .. row[3])
		end
		-- every weapon move id (W<n><key>, Shared.WeaponRules.skillId) resolves to its weapon and a badge
		local moves = 0
		for id in Config.Abilities.list do
			local w, key = string.match(id, "^W(%d+)(%w+)$")
			if w then
				moves += 1
				check(IC.weapon[tonumber(w)] ~= nil, id .. ": its weapon has an icon")
				check(IC.move[key] ~= nil, id .. ": its move has a badge")
			end
		end
		check(moves > 0, "weapon moves found")
		for _, key in { "M1", "Z", "X", "C", "V" } do
			cellOk(IC.move[key], "move " .. key)
		end
	end)

	test("Icons: mobility, gadgets, actions, slots and tiers map to cells", function()
		for _, key in Config.Move.mobilityOrder do
			cellOk(IC.mobility[key], "mobility " .. key)
		end
		for _, key in Config.Gear.gadgetOrder do
			cellOk(IC.gadget[key], "gadget " .. key)
		end
		for _, key in { "Awaken", "Block", "Power" } do
			cellOk(IC.action[key], "action " .. key)
		end
		for _, key in Config.Gear.slotOrder do
			cellOk(IC.slot[key], "slot " .. key)
		end
		for _, key in Config.Gear.tierOrder do
			cellOk(IC.tier[key], "tier " .. key)
		end
	end)

	test("Icons: no two keys share a cell; sheets are 1024 px PNGs", function()
		local used = {}
		local count = 0
		for _, group in
			{
				"ability",
				"weapon",
				"move",
				"mobility",
				"gadget",
				"action",
				"slot",
				"tier",
				"shape",
				"incident",
				"event",
				"contract",
				"marker",
				"badgeGroup",
				"collect",
				"accolade",
				"journal",
				"rogues",
				"daily",
				"board",
				"moveKey",
			}
		do
			for key, at in IC[group] do
				local k = at[1] .. ":" .. at[2]
				check(
					used[k] == nil,
					string.format("%s %s shares cell %s with %s", group, tostring(key), k, used[k] or "")
				)
				used[k] = group .. " " .. tostring(key)
				count += 1
			end
		end
		check(count == 203 + 129, "332 cells (got " .. count .. ")") -- bosses-3: 3 boss markers at the end
		for i, sheet in IC.sheets do
			check(type(sheet.id) == "number" and sheet.id >= 0, "sheet " .. i .. " id is a number")
			local ok, png = pcall(fs.readFile, "art/export/icons/" .. sheet.file)
			check(ok, sheet.file .. " exists")
			if ok then
				check(string.sub(png, 2, 4) == "PNG", sheet.file .. " is a PNG")
				local w = string.unpack(">I4", png, 17)
				local h = string.unpack(">I4", png, 21)
				check(w == IC.sheetSize and h == IC.sheetSize, sheet.file .. " is 1024 x 1024")
			end
		end
	end)

	test("Icons: the open world's symbols and markers map to cells (gap-icons2)", function()
		for _, key in { "circle", "diamond", "triangle", "star", "square", "hex" } do
			cellOk(IC.shape[key], "shape " .. key)
			local inner = IC.shapeInner[key]
			check(type(inner) == "table" and #inner == 3, "shape " .. key .. " has its inner box")
			if inner then
				check(inner[3] > 0.3 and inner[3] <= 0.8, "shape " .. key .. " symbol size is sane")
				check(
					inner[1] - inner[3] / 2 >= 0 and inner[2] + inner[3] / 2 <= 1,
					"shape " .. key .. " symbol stays in the cell"
				)
			end
		end
		local n = 0
		for _, id in Config.Incidents.order do
			cellOk(IC.incident[id], "incident " .. id)
			n += 1
		end
		check(n >= 24, "every incident (got " .. n .. ")")
		local E = Config.Events
		for _, list in { E.order, E.rare, E.side } do
			for _, id in list do
				cellOk(IC.event[id], "event " .. id)
			end
		end
		for _, id in Config.Contracts.order do
			cellOk(IC.contract[id], "contract " .. id)
		end
		for id in Config.Boss.bosses do
			cellOk(IC.marker[id], "boss " .. id)
		end
		for _, key in
			{
				"boss",
				"giver",
				"site",
				"quest",
				"safehouse",
				"beacon",
				"hqHero",
				"hqVillain",
				"squad",
				"help",
				"here",
				"danger",
			}
		do
			cellOk(IC.marker[key], "marker " .. key)
		end
		-- every sheet of the second set comes after the four first ones (those never change once uploaded)
		for _, group in { "shape", "incident", "event", "contract", "marker" } do
			for key, at in IC[group] do
				check(at[1] >= 5, group .. " " .. tostring(key) .. " is on a new sheet")
			end
		end
	end)

	test("Icons: books, boards, rewards and movement buttons map to cells (gap-icons2)", function()
		for _, g in Config.Badges.groups do
			cellOk(IC.badgeGroup[g.id], "badge group " .. g.id)
			if g.accolade then
				cellOk(IC.accolade[g.accolade.id], "accolade " .. g.accolade.id)
			end
		end
		for _, set in Config.Collect.sets do
			cellOk(IC.collect[set.id], "collection " .. set.id)
		end
		for _, key in { "story", "quests", "rep", "perks", "rogues", "badges", "mentor", "showdown" } do
			cellOk(IC.journal[key], "journal tab " .. key)
		end
		for _, g in Config.Rogues.groups do
			cellOk(IC.rogues[g.id], "rogues group " .. g.id)
		end
		-- the daily tiles' reward kinds (DailyHud tileText, lower case) and the got tick
		for _, key in { "credits", "renown", "dust", "title", "got" } do
			cellOk(IC.daily[key], "daily " .. key)
		end
		for _, b in Config.Boards.boards do
			cellOk(IC.board[b.id], "board " .. b.id)
		end
		for _, key in { "Leap", "Boost", "Down" } do
			cellOk(IC.moveKey[key], "movement button " .. key)
		end
		for _, key in Config.Move.mobilityOrder do
			cellOk(IC.mobility[key], "the FLY button's mobility icon " .. key)
		end
	end)
end
