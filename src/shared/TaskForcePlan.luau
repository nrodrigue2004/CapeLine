--!strict
-- TaskForcePlan: task forces (spec: Hero MMO features > Task forces; H4). Pure, so TaskForceService,
-- MissionService, the board screen and the Lune tests agree:
--   who may start one (level 12+, Act 1 done, their side) or be put in a squad by Looking (within 2 levels
--   of the floor: sidekicking raises them), the fullest open squad for Looking, the 3 minute rejoin, the
--   leader hand-off, the legs as mission-shaped tables MissionService runs, and the week number for the
--   weekly first-clear bonus.

local TaskForcePlan = {}

export type Lobby = {
	id: number,
	tf: number, -- index in Config.TaskForce.list
	side: string,
	members: { number }, -- user ids, the leader first
	locked: boolean, -- friends only
	running: boolean,
}

function TaskForcePlan.get(TF: any, index: number): any?
	return TF.list[index]
end

function TaskForcePlan.indexOf(TF: any, id: string): number?
	for i, t in TF.list do
		if t.id == id then
			return i
		end
	end
	return nil
end

-- Start one yourself: level 12+, Act 1 done, and your side's task force
function TaskForcePlan.canStart(
	TF: any,
	index: number,
	level: number,
	side: string,
	act1Done: boolean
): (boolean, string?)
	local t = TF.list[index]
	if not t then
		return false, "none"
	end
	if t.side ~= side then
		return false, "side"
	end
	if not act1Done then
		return false, "act1"
	end
	if level < TF.floor then
		return false, "level"
	end
	return true, nil
end

-- Join someone's squad (the board or Looking): your side, Act 1 done, within `lookSlack` of the floor
function TaskForcePlan.canJoin(TF: any, lobby: Lobby, level: number, side: string, act1Done: boolean): boolean
	return lobby.side == side
		and act1Done
		and level >= TF.floor - TF.lookSlack
		and #lobby.members < TF.maxPlayers
end

-- Looking: the fullest open squad you may join (friends-only squads only when a friend leads it); ties go to
-- the oldest squad (lowest id). isFriend(leaderUserId) answers the lock.
function TaskForcePlan.match(
	TF: any,
	lobbies: { Lobby },
	level: number,
	side: string,
	act1Done: boolean,
	isFriend: (number) -> boolean
): Lobby?
	local best: Lobby? = nil
	for _, l in lobbies do
		if
			not l.running
			and TaskForcePlan.canJoin(TF, l, level, side, act1Done)
			and (not l.locked or isFriend(l.members[1]))
		then
			if not best or #l.members > #best.members or (#l.members == #best.members and l.id < best.id) then
				best = l
			end
		end
	end
	return best
end

-- A member who left or dropped keeps their place this long
function TaskForcePlan.canRejoin(TF: any, leftAt: number?, now: number): boolean
	return leftAt ~= nil and now - leftAt <= TF.rejoin
end

-- The leader leaves: the next member leads (nil when nobody is left: the run ends)
function TaskForcePlan.nextLeader(members: { any }, leaving: any): any?
	for _, m in members do
		if m ~= leaving then
			return m
		end
	end
	return nil
end

-- One leg as a mission-shaped table for MissionService (layout, waves, steps), numbered after the Act 1
-- missions so the client knows it is a task force
function TaskForcePlan.leg(TF: any, index: number, legIndex: number): any?
	local t = TF.list[index]
	local l = t and t.legs[legIndex]
	if not l then
		return nil
	end
	return {
		num = TF.numBase + index,
		id = t.id .. legIndex,
		name = t.name,
		layout = l.layout,
		waves = l.waves,
		waveGap = l.waveGap or 14,
		minLevel = TF.floor,
		minutes = l.minutes or TF.legMinutes, -- an abandoned leg frees its pocket after twice this plus 5 min
		panel = l.panel,
		steps = l.steps,
		taskForce = index,
		leg = legIndex,
		legs = #t.legs,
	}
end

-- The week number for "first clear each week" (weeks start Monday 00:00 UTC)
function TaskForcePlan.week(unix: number): number
	-- 1970-01-01 was a Thursday: shift 3 days so weeks turn over on Mondays
	return math.floor((unix + 3 * 86400) / (7 * 86400))
end

-- Renown multiplier for the final clear: double on the first clear of this task force this week
function TaskForcePlan.weeklyMult(TF: any, lastWeek: number, thisWeek: number): number
	return if lastWeek ~= thisWeek then TF.weeklyRenownMult else 1
end

return TaskForcePlan
