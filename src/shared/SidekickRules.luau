--!strict
-- SidekickRules: sidekicking, missions only (spec: Hero MMO features > Sidekicking; H4). Pure, so the
-- server (MissionService, HeroService, GearService) and the Lune tests share one set of rules.
--   Mission level: the party's highest level (it replaces the median, for pockets only).
--   Raised up: a member more than 1 level below counts as mission level minus 1 (stats, health and gear item
--   levels); they keep only the abilities and ranks they own. Never lowered.
--   Pay at your own level; a sidekick gets +20% Renown, the top member +10% when a sidekick is 5 or more
--   levels lower (the mentor bonus).
--   Only in a pocket: `level` answers the real level anywhere else, so a raise never leaves a pocket.

local SidekickRules = {}

-- The mission level of a party (never below the mission's own floor)
function SidekickRules.missionLevel(levels: { number }, floor: number?): number
	local top = floor or 1
	for _, l in levels do
		top = math.max(top, l)
	end
	return top
end

-- The level a member counts as in the pocket: raised to mission level - 1 when more than `gap` below
function SidekickRules.raised(S: any, level: number, missionLevel: number): number
	if level < missionLevel - S.gap then
		return missionLevel + S.raiseTo
	end
	return level -- never lowered
end

function SidekickRules.isSidekick(S: any, level: number, missionLevel: number): boolean
	return SidekickRules.raised(S, level, missionLevel) > level
end

-- The level that stats use: the raise only counts inside a mission pocket
function SidekickRules.level(level: number, raise: number?, inPocket: boolean): number
	if raise and inPocket and raise > level then
		return raise
	end
	return level
end

-- Gear item levels in the pocket: each worn piece below the raised level counts at it, its rolled stats
-- scaled by the item level ratio (budget is linear in item level, GearMath.baseBudget). Copies: the saved
-- pieces never change.
function SidekickRules.raiseGear(worn: { any }, raise: number?): { any }
	if not raise then
		return worn
	end
	local out = {}
	for _, piece in worn do
		local ilvl = piece.ilvl or 0
		if ilvl > 0 and ilvl < raise then
			local k = raise / ilvl
			local copy = table.clone(piece)
			copy.ilvl = raise
			copy.main = math.floor((piece.main or 0) * k + 0.5)
			local bonus = {}
			for _, b in piece.bonus or {} do
				table.insert(bonus, { b[1], math.floor(b[2] * k + 0.5) })
			end
			copy.bonus = bonus
			table.insert(out, copy)
		else
			table.insert(out, piece)
		end
	end
	return out
end

-- The Renown multiplier for one member at the end of a mission: a sidekick +20%; the top member +10% when
-- any sidekick is `mentorGap` or more levels lower (the mentor bonus). Also says whether this clear counts
-- as a mentor clear (for the Mentor badges) and as a sidekick clear.
function SidekickRules.renown(S: any, level: number, levels: { number }): (number, boolean, boolean)
	local top = SidekickRules.missionLevel(levels)
	if SidekickRules.isSidekick(S, level, top) then
		return 1 + S.renownBonus, false, true
	end
	if level == top then
		for _, l in levels do
			if top - l >= S.mentorGap then
				return 1 + S.mentorBonus, true, false
			end
		end
	end
	return 1, false, false
end

-- Robots' and bosses' health in a pocket for this many players
function SidekickRules.partyHp(S: any, n: number): number
	return S.partyHp[math.clamp(n, 1, #S.partyHp)]
end

return SidekickRules
