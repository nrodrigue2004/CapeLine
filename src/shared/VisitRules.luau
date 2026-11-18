--!strict
-- VisitRules: visiting a friend's HQ on the same server (gap check G15, spec Update 2 "visit a friend's HQ").
-- Pure, so VisitService, HqClient, SquadHud and the Lune tests agree. Players are user ids.
-- * pocket(Config, i) / pocketAt(Config, x, y, z): the visit pockets. Each host (an owner with visitors) gets
--   one, a sealed copy of the HQ cell on the HQ cells' own grid but Config.Hq.visit.pocket.y high (700 studs
--   over the cells, 2,200 over the mission pockets), so a copy never meets a real cell, a mission pocket or
--   the city. freeIndex picks the lowest pocket no host holds.
-- * ask(Config, st, from, to, now, ctx): a visitor asks an owner (the VISIT button). Fixed reasons only. An ask
--   the owner would never want (they muted or blocked the asker, or reported them) is "sent" but hidden: the
--   owner never sees it, and the asker is not told (muting stays private, as with PvP rematches).
-- * answer(Config, st, owner, from, yes, now, ctx): the owner's ACCEPT or NO on the card. NO and a kick start a
--   wait before the same visitor may ask that owner again.
-- * leave, kick, drop (left the server), visitors, hostOf.
-- * readOnly(view, visit): the owner's HqState packet made into a visitor's: no upgrade, retire, picks,
--   training ids or boss sim; the stations draw but only the exit works (allowed()).
-- * event(...): the hq_visit analytics fields, at most once a minute per visitor (logs()).

local VisitRules = {}

export type Ask = { to: number, at: number, hidden: boolean }
export type Host = { index: number, visitors: { number } }
export type State = {
	asks: { [number]: Ask }, -- asker -> their one open ask
	hosts: { [number]: Host }, -- owner -> their pocket and visitors
	at: { [number]: number }, -- visitor -> the owner whose HQ they are in
	wait: { [string]: number }, -- "visitor:owner" -> no new ask before this time
	logged: { [number]: number }, -- visitor -> when their last hq_visit event went
}

-- What the server knows about the two players when one asks the other (or when the owner answers)
export type Context = {
	fromFree: boolean?, -- the asker can leave what they are doing (no mission, cutscene, Downed or PvP fight)
	toReady: boolean?, -- the owner's hero is loaded and made (has an HQ)
	fromMuted: boolean?, -- the asker muted the owner
	fromBlocked: boolean?, -- the asker blocked or reported the owner
	toMuted: boolean?, -- the owner muted the asker
	toBlocked: boolean?, -- the owner blocked or reported the asker
}

function VisitRules.new(): State
	return { asks = {}, hosts = {}, at = {}, wait = {}, logged = {} }
end

---------------------------------------------------------------------------
-- The pockets
---------------------------------------------------------------------------

-- The centre (the floor's top) of visit pocket i (1 to Config.Hq.visit.pocket.count)
function VisitRules.pocket(Config: any, i: number): (number, number, number)
	local p = Config.Hq.visit.pocket
	local k = math.clamp(i, 1, p.count) - 1
	return p.x0 + (k % p.perRow) * p.gap, p.y, p.z0 + (k // p.perRow) * p.gap
end

-- Which visit pocket a point is in, or nil
function VisitRules.pocketAt(Config: any, x: number, y: number, z: number): number?
	local p = Config.Hq.visit.pocket
	if y < p.y - 60 or y > p.y + 200 then
		return nil
	end
	local col = math.floor((x - p.x0) / p.gap + 0.5)
	local row = math.floor((z - p.z0) / p.gap + 0.5)
	if col < 0 or col >= p.perRow or row < 0 then
		return nil
	end
	local i = row * p.perRow + col + 1
	if i > p.count then
		return nil
	end
	local cx, cz = p.x0 + col * p.gap, p.z0 + row * p.gap
	local half = Config.Hq.cell.size / 2 + 10
	if math.abs(x - cx) > half or math.abs(z - cz) > half then
		return nil
	end
	return i
end

-- The lowest pocket no host holds (nil when every one is taken)
function VisitRules.freeIndex(Config: any, st: State): number?
	local used: { [number]: boolean } = {}
	for _, h in st.hosts do
		used[h.index] = true
	end
	for i = 1, Config.Hq.visit.pocket.count do
		if not used[i] then
			return i
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Asks and answers
---------------------------------------------------------------------------

local function pair(from: number, to: number): string
	return from .. ":" .. to
end

function VisitRules.visitors(st: State, owner: number): { number }
	local h = st.hosts[owner]
	return if h then table.clone(h.visitors) else {}
end

function VisitRules.hostOf(st: State, visitor: number): number?
	return st.at[visitor]
end

-- The open ask from this asker (nil when none or it ran out)
function VisitRules.pending(Config: any, st: State, from: number, now: number): Ask?
	local a = st.asks[from]
	if a and now - a.at < Config.Hq.visit.askLife then
		return a
	end
	return nil
end

-- The owner's visible open ask from someone else, if any (one card at a time)
local function shownTo(Config: any, st: State, to: number, now: number): number?
	for from, a in st.asks do
		if a.to == to and not a.hidden and now - a.at < Config.Hq.visit.askLife then
			return from
		end
	end
	return nil
end

-- Ask to visit. Returns ok, reason (a key of Config.Hq.visit.reasons when refused), and deliver: whether the
-- owner gets a card (false for a hidden ask; the asker is told "sent" either way).
function VisitRules.ask(
	Config: any,
	st: State,
	from: number,
	to: number,
	now: number,
	ctx: Context
): (boolean, string?, boolean)
	local V = Config.Hq.visit
	if from == to then
		return false, "self", false
	end
	if st.at[from] then
		return false, "visiting", false
	end
	if not ctx.fromFree then
		return false, "busy", false
	end
	if not ctx.toReady then
		return false, "new", false
	end
	if ctx.fromMuted or ctx.fromBlocked then
		return false, "muted", false -- your own mute or block: undo it first
	end
	local cur = VisitRules.pending(Config, st, from, now)
	if cur then
		return false, if cur.to == to then "pending" else "asking", false
	end
	local w = st.wait[pair(from, to)]
	if w and now < w then
		return false, "wait", false
	end
	if #VisitRules.visitors(st, to) >= V.max then
		return false, "full", false
	end
	local hidden = ctx.toMuted == true or ctx.toBlocked == true
	if not hidden and shownTo(Config, st, to, now) then
		return false, "theirBusy", false
	end
	st.asks[from] = { to = to, at = now, hidden = hidden }
	return true, nil, not hidden
end

-- The owner's answer to `from`'s ask. Returns ok, reason. A yes puts the visitor in the owner's HQ (the caller
-- moves them there); a pocket for a new host comes from freeIndex.
function VisitRules.answer(
	Config: any,
	st: State,
	owner: number,
	from: number,
	yes: boolean,
	now: number,
	ctx: Context
): (boolean, string?)
	local V = Config.Hq.visit
	local a = VisitRules.pending(Config, st, from, now)
	if not a or a.to ~= owner or a.hidden then
		if st.asks[from] and st.asks[from].to == owner then
			st.asks[from] = nil
		end
		return false, "expired"
	end
	st.asks[from] = nil
	if not yes then
		st.wait[pair(from, owner)] = now + V.again
		return false, "declined"
	end
	if ctx.toMuted or ctx.toBlocked or ctx.fromMuted or ctx.fromBlocked then
		return false, "expired" -- muted or blocked since the ask: as if it ran out
	end
	if st.at[from] then
		return false, "visiting"
	end
	if not ctx.fromFree then
		return false, "busy"
	end
	if not ctx.toReady then
		return false, "new"
	end
	local host: Host? = st.hosts[owner]
	if host and #host.visitors >= V.max then
		return false, "full"
	end
	if not host then
		local index = VisitRules.freeIndex(Config, st)
		if not index then
			return false, "full"
		end
		local made: Host = { index = index :: number, visitors = {} }
		st.hosts[owner] = made
		host = made
	end
	table.insert((host :: Host).visitors, from)
	st.at[from] = owner
	return true, nil
end

-- A visitor leaves (LEAVE, the exit, or sent home). Returns the owner, and true when the host's pocket is
-- now empty (the caller takes the pocket down).
function VisitRules.leave(st: State, visitor: number): (number?, boolean)
	local owner = st.at[visitor]
	if not owner then
		return nil, false
	end
	st.at[visitor] = nil
	local h = st.hosts[owner]
	if not h then
		return owner, true
	end
	local i = table.find(h.visitors, visitor)
	if i then
		table.remove(h.visitors, i)
	end
	if #h.visitors == 0 then
		st.hosts[owner] = nil
		return owner, true
	end
	return owner, false
end

-- The owner shows a visitor out. True when they were visiting this owner. The visitor waits Config.Hq.visit.
-- kicked seconds before asking this owner again.
function VisitRules.kick(Config: any, st: State, owner: number, visitor: number, now: number): boolean
	if st.at[visitor] ~= owner then
		return false
	end
	VisitRules.leave(st, visitor)
	st.wait[pair(visitor, owner)] = now + Config.Hq.visit.kicked
	return true
end

-- A player left the server: their asks go, they leave any HQ they were in, and as a host every visitor goes
-- home. Returns the visitors to send home (their host left) and the owner they were visiting.
function VisitRules.drop(st: State, userId: number): ({ number }, number?)
	st.asks[userId] = nil
	for from, a in st.asks do
		if a.to == userId then
			st.asks[from] = nil
		end
	end
	local was = VisitRules.leave(st, userId)
	local home = {}
	local h = st.hosts[userId]
	if h then
		for _, v in h.visitors do
			st.at[v] = nil
			table.insert(home, v)
		end
		st.hosts[userId] = nil
	end
	st.logged[userId] = nil
	return home, was
end

---------------------------------------------------------------------------
-- What a visitor sees and may do
---------------------------------------------------------------------------

-- A visitor may only leave: every station (the command table, Gizmo, mannequins, the training room, the
-- trophy picks, the Hall of Legends, the scanner, the WANTED poster's panel) is the owner's.
function VisitRules.allowed(station: string): boolean
	return station == "exit"
end

-- The owner's HqState packet as a visitor's read-only copy. visit: { owner, name } (the owner's user id and
-- the name the plate shows). Keeps the look (side, level, trophies on the wall, statues, props, dressing, the
-- WANTED poster and heads, the dummies as decor) and drops everything that acts.
function VisitRules.readOnly(
	view: { [string]: any },
	visit: { owner: number, name: string }
): { [string]: any }
	local out: { [string]: any } = {
		on = true,
		cell = view.cell,
		side = view.side,
		name = view.name,
		level = view.level,
		trophySlots = view.trophySlots,
		trophies = table.clone(view.trophies or {}),
		statues = view.statues or {},
		props = view.props or {},
		repTier = view.repTier or 0,
		wanted = view.wanted,
		heads = view.heads or {},
		visit = { owner = visit.owner, name = visit.name },
	}
	local decor = {}
	for _, d in view.dummies or {} do
		table.insert(decor, { id = 0, x = d.x, y = d.y, z = d.z }) -- no id: never an aim target
	end
	out.dummies = decor
	return out
end

-- Analytics: the hq_visit event's value and fields (Shared.AnalyticsSchema), or nil when this visitor logged
-- one less than Config.Hq.visit.logEvery seconds ago (so a leave-and-ask loop never floods the budget)
function VisitRules.event(
	Config: any,
	st: State,
	visitor: number,
	now: number,
	ownerSide: string,
	visitorSide: string,
	visitors: number,
	ownerLevel: number
): (number?, { any }?)
	local last = st.logged[visitor]
	if last and now - last < Config.Hq.visit.logEvery then
		return nil, nil
	end
	st.logged[visitor] = now
	local cross = if ownerSide == visitorSide then "same" else "cross"
	local fields: { any } = { ownerSide, cross, visitors }
	return ownerLevel, fields
end

-- The fixed line for a key, with a name put in (names are hero names or Roblox display names: never typed
-- text). Unknown keys read as the generic refusal.
function VisitRules.line(Config: any, key: string, name: string?): string
	local V = Config.Hq.visit
	local t = V.text[key] or V.reasons[key] or V.reasons.busy
	if string.find(t, "%s", 1, true) then
		return string.format(t, name or "Someone")
	end
	return t
end

return VisitRules
