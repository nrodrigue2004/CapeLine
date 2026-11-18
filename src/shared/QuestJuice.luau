--!strict
-- QuestJuice: what each moment of a side quest chain shows and plays (the juice pass, 2026-11-18; data in
-- Config.Audio.sideQuest, the chains in Config.SideQuests). Pure, so Lune checks every step of every chain maps
-- to a juice row; StoryHud fires the rows and fills the result card from result().
-- * moment(Config, name): the juice row for accept, step, wait, villain, encore, finale, done or retry.
-- * kindOf(chain, idx, side): the step's kind for a side (the other side's when a line is for one side only).
-- * step(Config, kind): { juice, word } for a step done of that kind (the finale's is its win).
-- * result(Config, chain, credits, renown): the chain's result card: its title line, the pay and one line per
--   cosmetic it gives (NEW TITLE, NEW STYLE...). Every word is fixed: the chain's and reward's own names only.

local GearMath = if script then require(script.Parent.GearMath) else (require :: any)("./GearMath")
local SideQuestPlan = if script
	then require(script.Parent.SideQuestPlan)
	else (require :: any)("./SideQuestPlan")

local QuestJuice = {}

QuestJuice.MOMENTS = { "accept", "step", "wait", "villain", "encore", "finale", "done", "retry" }

-- The cosmetic fields a chain may give, in the card's order, with the card's word for each
QuestJuice.REWARDS = {
	{ "title", "NEW TITLE" },
	{ "style", "NEW STYLE" },
	{ "emote", "NEW EMOTE" },
	{ "frame", "NEW FRAME" },
	{ "prop", "NEW HQ PROP" },
}

local function Q(Config: any): any
	return Config.Audio.sideQuest
end

function QuestJuice.moment(Config: any, name: string): string?
	return Q(Config).moments[name]
end

function QuestJuice.kindOf(chain: any, idx: number, side: string): string?
	local st = chain and chain.steps and chain.steps[idx]
	if not st then
		return nil
	end
	local g = SideQuestPlan.goal(st, side)
		or SideQuestPlan.goal(st, if side == "villain" then "hero" else "villain")
	return g and g.kind
end

function QuestJuice.step(Config: any, kind: string?): { juice: string, word: string }?
	return kind and Q(Config).kinds[kind] or nil
end

-- "CrackedHalo" -> "CRACKED HALO" (an id's own words, for rewards with no display name)
local function words(id: string): string
	return string.upper((string.gsub(id, "(%l)(%u)", "%1 %2")))
end

-- The name the card shows for a reward field's value
function QuestJuice.rewardName(Config: any, field: string, value: string): string
	if field == "style" then
		local id = GearMath.questStyle(Config, value)
		local row = id and GearMath.styleRow(Config, id)
		if row and type(row.name) == "string" then
			return string.upper(row.name)
		end
	elseif field == "title" then
		return string.upper(value)
	end
	return words(value)
end

export type Result = {
	title: string,
	villain: string?,
	credits: number,
	renown: number,
	rewards: { string },
}

function QuestJuice.result(Config: any, chain: any, credits: number?, renown: number?): Result
	local out: Result = {
		title = string.upper(chain.name or "SIDE QUEST") .. " COMPLETE!",
		villain = if type(chain.villain) == "table" and type(chain.villain.name) == "string"
			then string.upper(chain.villain.name)
			else nil,
		credits = math.max(0, math.floor(credits or 0)),
		renown = math.max(0, math.floor(renown or 0)),
		rewards = {},
	}
	local cos = SideQuestPlan.cosmetic(chain)
	for _, r in QuestJuice.REWARDS do
		local v = cos[r[1]]
		if v then
			table.insert(out.rewards, r[2] .. ": " .. QuestJuice.rewardName(Config, r[1], v))
		end
	end
	return out
end

return QuestJuice
