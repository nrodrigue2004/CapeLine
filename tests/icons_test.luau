-- The comic icon set (gap-icons, 2026-11-19): art/icons/icons.py's sheets and Config.Icons. Every power,
-- weapon (and weapon move), mobility pick, gadget, HUD action, gear slot and tier maps to a cell that exists,
-- inside its 1024 px sheet, and no two keys share a cell; the sheet files are 1024 x 1024 PNGs. Called from
-- tests/run.luau:
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
		for _, group in { "ability", "weapon", "move", "mobility", "gadget", "action", "slot", "tier" } do
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
		check(count == 136 + 36 + 5 + 5 + 4 + 3 + 8 + 6, "203 cells (got " .. count .. ")")
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
end
