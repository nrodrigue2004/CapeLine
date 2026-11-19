--!strict
-- VillainCards: the side quest villains' name card portraits (gap-villains, 2026-11-19, nate). Pure, so Lune
-- checks it. A finale's name card (SideQuestPlan.card: the chain's villain, or an encore finale's first foe)
-- shows the villain's rendered portrait (Config.VillainArt, art/panels/villains.py) in the card's picture slot
-- (Ui.CinemaHud, kind "villain"), keyed by the card's name. An id of 0 (not uploaded) answers nil and the card
-- keeps its words only.

local VillainCards = {}

export type Cell = { image: string, offset: { number }, size: { number } }

-- A card name's portrait (its sheet image and cell), or nil
function VillainCards.portrait(Config: any, name: string?): Cell?
	local A = Config.VillainArt
	local at = A and name and A.cards[name]
	if not at then
		return nil
	end
	local id = A.sheets[at[1]]
	if type(id) ~= "number" or id <= 0 then
		return nil
	end
	local c = A.cell
	return {
		image = "rbxassetid://" .. string.format("%d", id),
		offset = { at[2] * c, at[3] * c },
		size = { c, c },
	}
end

-- Every villain name card the side quests can show (the Dev sample chain's aside), each once
function VillainCards.names(Config: any): { string }
	local out, seen = {}, {}
	local function add(n: any)
		if type(n) == "string" and not seen[n] then
			seen[n] = true
			table.insert(out, n)
		end
	end
	for _, chain in Config.SideQuests.chains do
		if type(chain.villain) == "table" and not chain.dev then
			for _, step in chain.steps or {} do
				for _, side in { "hero", "villain" } do
					local g = step[side]
					if type(g) == "table" and g.kind == "finale" and g.encore and type(g.card) == "table" then
						add(g.card.name)
					end
				end
			end
			add(chain.villain.name)
		end
	end
	table.sort(out)
	return out
end

-- Problems (tests): a card with no portrait cell, a cell off its sheet, a sheet with no id
function VillainCards.problems(Config: any): { string }
	local out = {}
	local A = Config.VillainArt
	for _, n in VillainCards.names(Config) do
		local at = A.cards[n]
		if not at then
			table.insert(out, n .. ": no portrait in Config.VillainArt")
		elseif at[1] > #A.sheets or at[2] < 0 or at[2] > 1 or at[3] < 0 or at[3] > 1 then
			table.insert(out, n .. ": cell off its sheet")
		end
	end
	for i, id in A.sheets do
		if type(id) ~= "number" or id <= 0 or id % 1 ~= 0 then
			table.insert(out, "sheet " .. i .. " has no image id")
		end
	end
	return out
end

return VillainCards
