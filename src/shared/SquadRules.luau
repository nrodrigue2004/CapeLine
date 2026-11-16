--!strict
-- SquadRules: squads of up to 4 (spec: Social table; Squad.Invite, Squad.Accept, Squad.Leave). Pure, so
-- Lune tests it. Members are user ids; the first member leads.
-- * invite(from, to, now): any member (or a solo player) invites someone not in a squad; one pending invite
--   per target, Config.Squad.inviteLife seconds.
-- * accept(to, now): joins the inviter's squad (made when the first invite is accepted). Full squads refuse.
-- * leave(userId): out of the squad; the next member leads; a squad of one is gone.
-- * kick(leader, target), allies(a, b), members(userId).

local SquadRules = {}

export type Squad = { id: number, members: { number } }
export type Invite = { from: number, at: number }
export type State = {
	squads: { [number]: Squad },
	of: { [number]: number }, -- user id -> squad id
	invites: { [number]: Invite }, -- target user id -> invite
	nextId: number,
}

function SquadRules.new(): State
	return { squads = {}, of = {}, invites = {}, nextId = 1 }
end

function SquadRules.squadOf(st: State, userId: number): Squad?
	local id = st.of[userId]
	return if id then st.squads[id] else nil
end

function SquadRules.members(st: State, userId: number): { number }
	local s = SquadRules.squadOf(st, userId)
	return if s then table.clone(s.members) else { userId }
end

function SquadRules.allies(st: State, a: number, b: number): boolean
	return a ~= b and st.of[a] ~= nil and st.of[a] == st.of[b]
end

function SquadRules.leader(st: State, userId: number): number?
	local s = SquadRules.squadOf(st, userId)
	return s and s.members[1]
end

function SquadRules.invite(Config: any, st: State, from: number, to: number, now: number): (boolean, string?)
	if from == to then
		return false, "self"
	end
	if st.of[to] then
		return false, "taken"
	end
	local s = SquadRules.squadOf(st, from)
	if s and #s.members >= Config.Squad.max then
		return false, "full"
	end
	local cur = st.invites[to]
	if cur and now - cur.at < Config.Squad.inviteLife then
		return false, if cur.from == from then "pending" else "busy"
	end
	st.invites[to] = { from = from, at = now }
	return true, nil
end

-- The pending invite for a user (nil when none or expired)
function SquadRules.pending(Config: any, st: State, to: number, now: number): Invite?
	local inv = st.invites[to]
	if inv and now - inv.at < Config.Squad.inviteLife then
		return inv
	end
	return nil
end

function SquadRules.decline(st: State, to: number)
	st.invites[to] = nil
end

-- Returns ok, reason, squad id
function SquadRules.accept(Config: any, st: State, to: number, now: number): (boolean, string?, number?)
	local inv = SquadRules.pending(Config, st, to, now)
	st.invites[to] = nil
	if not inv then
		return false, "expired", nil
	end
	if st.of[to] then
		return false, "taken", nil
	end
	local s = SquadRules.squadOf(st, inv.from)
	if not s then
		local id = st.nextId
		st.nextId += 1
		local made: Squad = { id = id, members = { inv.from } }
		st.squads[id] = made
		st.of[inv.from] = id
		s = made
	end
	local squad = s :: Squad
	if #squad.members >= Config.Squad.max then
		return false, "full", nil
	end
	table.insert(squad.members, to)
	st.of[to] = squad.id
	return true, nil, squad.id
end

-- Leave (or drop on disconnect). Returns the squad id that changed (nil if not in one).
function SquadRules.leave(st: State, userId: number): number?
	local s = SquadRules.squadOf(st, userId)
	st.invites[userId] = nil
	for to, inv in st.invites do
		if inv.from == userId then
			st.invites[to] = nil
		end
	end
	if not s then
		return nil
	end
	local at = table.find(s.members, userId)
	if at then
		table.remove(s.members, at)
	end
	st.of[userId] = nil
	if #s.members <= 1 then
		for _, m in s.members do
			st.of[m] = nil
		end
		st.squads[s.id] = nil
	end
	return s.id
end

function SquadRules.kick(st: State, leader: number, target: number): boolean
	local s = SquadRules.squadOf(st, leader)
	if not s or s.members[1] ~= leader or leader == target or st.of[target] ~= s.id then
		return false
	end
	SquadRules.leave(st, target)
	return true
end

-- The median of a list of levels (mission and boss scaling by the party)
function SquadRules.median(levels: { number }): number
	if #levels == 0 then
		return 1
	end
	local l = table.clone(levels)
	table.sort(l)
	local n = #l
	if n % 2 == 1 then
		return l[(n + 1) // 2]
	end
	return math.floor((l[n // 2] + l[n // 2 + 1]) / 2 + 0.5)
end

return SquadRules
