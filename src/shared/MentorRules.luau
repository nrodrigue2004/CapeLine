--!strict
-- MentorRules: mentors (spec: Hero MMO features > Original mentors; H6). Pure, so MentorService, MentorHud
-- and the Lune tests agree: which mentors a side may pick, when one may be changed (any safehouse, free),
-- which moments open a panel (once each, and every 5 levels), the quest line (the part open at your level,
-- its goals, progress) and the fixed panel lines with your hero name.
-- Save (per character, mmo): mentor = index in Config.Mentors.list (0 = none yet), mentorSeen = moment bits,
-- mentorParts = finished parts per mentor, mentorCount = the open part's goal counts, mentorLook = index of
-- the mentor whose look you wear (0 = none).

local MentorRules = {}

export type Save = {
	mentor: number,
	mentorSeen: number,
	mentorParts: { number },
	mentorCount: { number },
	mentorLook: number,
}

function MentorRules.get(M: any, index: number): any?
	return M.list[index]
end

function MentorRules.indexOf(M: any, id: string): number?
	for i, m in M.list do
		if m.id == id then
			return i
		end
	end
	return nil
end

-- The mentors a side may pick (indices)
function MentorRules.forSide(M: any, side: string): { number }
	local out = {}
	for i, m in M.list do
		if m.side == side then
			table.insert(out, i)
		end
	end
	return out
end

-- May this hero pick mentor i now? The first pick anywhere (after the opening); a change at a safehouse.
function MentorRules.canPick(
	M: any,
	s: Save,
	i: number,
	side: string,
	openingDone: boolean,
	atSafehouse: boolean
): (boolean, string?)
	local m = M.list[i]
	if not m then
		return false, "none"
	elseif m.side ~= side then
		return false, "side"
	elseif not openingDone then
		return false, "opening"
	elseif s.mentor == i then
		return false, "same"
	elseif s.mentor ~= 0 and not atSafehouse then
		return false, "safehouse"
	end
	return true, nil
end

-- A side change (in the creator) leaves a mentor of the other side: the hero picks again
function MentorRules.fits(M: any, s: Save, side: string): boolean
	local m = M.list[s.mentor]
	return m ~= nil and m.side == side
end

-- Pick: a change keeps each mentor's finished parts; the open part's counts start over
function MentorRules.pick(_M: any, s: Save, i: number)
	if s.mentor ~= i then
		s.mentor = i
		for k in s.mentorCount do
			s.mentorCount[k] = 0
		end
	end
end

local function momentBit(M: any, moment: string): number?
	local i = table.find(M.moments, moment)
	return if i then bit32.lshift(1, i - 1) else nil
end

-- First time for this moment? Marks it seen and says yes once.
function MentorRules.firstTime(M: any, s: Save, moment: string): boolean
	local b = momentBit(M, moment)
	if not b or bit32.btest(s.mentorSeen, b) then
		return false
	end
	s.mentorSeen = bit32.bor(s.mentorSeen, b)
	return true
end

-- The level panels crossed going from a level to another (every 5 levels)
function MentorRules.levelPanels(M: any, from: number, to: number): { number }
	local out = {}
	for l = from + 1, to do
		if l % M.levelEvery == 0 then
			table.insert(out, l)
		end
	end
	return out
end

-- The part of the current mentor's quest line that is open now (nil: none open yet, or all done)
function MentorRules.openPart(M: any, s: Save, level: number): number?
	if s.mentor == 0 then
		return nil
	end
	local done = s.mentorParts[s.mentor] or 0
	local nextPart = done + 1
	local part = M.quest[nextPart]
	if part and level >= part.level then
		return nextPart
	end
	return nil
end

-- Count something that happened (kind: incident, robot, contract, mission, boss). Returns the part
-- finished by it, if any (the caller pays it); the counts start over for the next part.
function MentorRules.count(M: any, s: Save, level: number, kind: string, n: number?): number?
	local p = MentorRules.openPart(M, s, level)
	if not p then
		return nil
	end
	local part = M.quest[p]
	local any = false
	for g, goal in part.goals do
		if goal.kind == kind then
			s.mentorCount[g] = math.min(goal.n, (s.mentorCount[g] or 0) + (n or 1))
			any = true
		end
	end
	if not any then
		return nil
	end
	for g, goal in part.goals do
		if (s.mentorCount[g] or 0) < goal.n then
			return nil
		end
	end
	s.mentorParts[s.mentor] = p
	for k in s.mentorCount do
		s.mentorCount[k] = 0
	end
	return p
end

-- The whole line done for mentor i: their look, emote and Mentor's Pride
function MentorRules.lineDone(M: any, s: Save, i: number): boolean
	return (s.mentorParts[i] or 0) >= #M.quest
end

-- Looks you may wear: the mentors whose line you finished
function MentorRules.canWear(M: any, s: Save, i: number): boolean
	return i == 0 or (M.list[i] ~= nil and MentorRules.lineDone(M, s, i))
end

-- A fixed panel line with the hero name and level filled in
function MentorRules.line(M: any, i: number, moment: string, hero: string, level: number?): string?
	local m = M.list[i]
	local set = m and M.lines[m.id]
	local text = set and set[moment]
	if not text then
		return nil
	end
	text = string.gsub(text, "{hero}", hero)
	text = string.gsub(text, "{level}", tostring(level or 0))
	return text
end

-- Any character's finished line (the account's Mentor's Pride trophy)
function MentorRules.pride(M: any, profile: any): boolean
	for _, c in profile.characters or {} do
		local mmo = c.mmo
		if mmo and mmo.mentorParts then
			for i in M.list do
				if (mmo.mentorParts[i] or 0) >= #M.quest then
					return true
				end
			end
		end
	end
	return false
end

return MentorRules
