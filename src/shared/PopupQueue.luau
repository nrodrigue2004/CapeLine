--!strict
-- PopupQueue: one priority queue for every transient popup (pt-ui, nate's playtest 2026-11-19: "too many popups
-- on the screen at once"). Pure rules, no Roblox instances, so Lune checks them; Ui.Popups runs it on the device.
-- * Two kinds: a "card" (the big middle-of-screen things: result cards, name cards, stamps, the level badge,
--   offers, invites, the join cards) and a "toast" (the small speech bubbles of Ui.Toasts). At most P.maxCards
--   cards and P.maxToasts toasts show at once (P.phoneToasts on a phone).
-- * Higher pri first, then oldest first. A waiting toast of the same group merges into the one already
--   waiting (count + 1, and its merge rule adds the two up), so a burst of drops reads "+3 more".
-- * urgent: the answer to a tap (a refusal, "Not during a fight") or a story card: never waits for a fight or a
--   menu; an urgent toast pushes out the oldest non-urgent toast on screen.
-- * Combat quieting: while fighting (a hit given or taken in the last P.calm s), non-urgent cards wait, at
--   most P.combatHold s (then they show anyway, so nothing important is lost); offers never show while
--   fighting and wait P.offerCalm s of calm.
-- * blocked (loading screen, menu, creator, prologue, cutscene): no new non-urgent card; once free, cards wait
--   P.settle s of calm (the join cards' old rule).
-- * stale: an item that may not wait long (a juice stamp, a short note) is folded into the "+N more" count
--   once it has waited `stale` s; expires: an ask that runs out (a squad invite) is dropped when it has.
-- * life: the longest a card or toast stays up; step() returns it to close then, whatever its own timer
--   does (every card closes: tests "pt-ui"). While toasts wait, the ones up are cut to P.hurry s.

local PopupQueue = {}

export type Item = {
	id: number,
	name: string,
	kind: string, -- "card" | "toast"
	pri: number,
	urgent: boolean,
	offer: boolean,
	fightOk: boolean, -- a card that may show while fighting (a timed ask: squad invite, visit ask)
	group: string?,
	life: number?, -- seconds on screen at most (nil: until it closes itself; a card must then say isOpen)
	stale: number?,
	expires: number?,
	born: number,
	shown: number?,
	count: number,
	data: any,
	merge: ((any, any) -> any)?,
}

export type Ctx = {
	fighting: boolean, -- a hit given or taken in the last P.calm s
	calmFor: number, -- seconds since the last hit given or taken
	blocked: boolean, -- loading, menu, creator, prologue or cutscene
	freeFor: number, -- seconds since the screen was last blocked
	phone: boolean,
}

export type Queue = {
	P: any,
	nextId: number,
	waiting: { Item },
	showing: { Item },
	more: number, -- folded items since the last read (the "+N more" chip)
}

export type Step = { show: { Item }, close: { Item } }

function PopupQueue.new(P: any): Queue
	return { P = P, nextId = 0, waiting = {}, showing = {}, more = 0 }
end

-- Queue a popup. spec: name, kind, pri, and optional urgent, offer, fightOk, group, life, stale, expires,
-- data, merge. Returns the item and whether it merged into one already waiting.
function PopupQueue.push(q: Queue, spec: { [string]: any }, now: number): (Item, boolean)
	local kind = spec.kind or "toast"
	if spec.group then
		for _, w in q.waiting do
			if w.kind == kind and w.group == spec.group then
				w.count += 1
				w.data = if w.merge then w.merge(w.data, spec.data) else w.data
				w.pri = math.max(w.pri, spec.pri or 0)
				return w, true
			end
		end
	end
	-- a card of the same name is up or waiting already: the newer one takes its place in the line
	if kind == "card" then
		for i, w in q.waiting do
			if w.kind == "card" and w.name == spec.name then
				table.remove(q.waiting, i)
				break
			end
		end
	end
	q.nextId += 1
	local item: Item = {
		id = q.nextId,
		name = spec.name or kind,
		kind = kind,
		pri = spec.pri or 0,
		urgent = spec.urgent == true,
		offer = spec.offer == true,
		fightOk = spec.fightOk == true,
		group = spec.group,
		life = spec.life,
		stale = spec.stale,
		expires = spec.expires,
		born = now,
		shown = nil,
		count = 1,
		data = spec.data,
		merge = spec.merge,
	}
	table.insert(q.waiting, item)
	return item, false
end

-- The popup went away by itself (a tap, its own timer): its slot is free
function PopupQueue.closed(q: Queue, id: number)
	for i, s in q.showing do
		if s.id == id then
			table.remove(q.showing, i)
			return
		end
	end
	for i, w in q.waiting do
		if w.id == id then
			table.remove(q.waiting, i)
			return
		end
	end
end

local function count(q: Queue, kind: string): number
	local n = 0
	for _, s in q.showing do
		if s.kind == kind then
			n += 1
		end
	end
	return n
end

-- May a waiting card show now (slots aside)?
function PopupQueue.cardMay(P: any, w: Item, ctx: Ctx, now: number): boolean
	if w.urgent then
		return true
	end
	if ctx.blocked or ctx.freeFor < P.settle then
		return false
	end
	if w.offer then
		return ctx.calmFor >= P.offerCalm
	end
	if ctx.fighting and not w.fightOk then
		return now - w.born >= P.combatHold -- a long fight: it shows anyway, nothing is lost
	end
	return true
end

-- One tick: which popups to put up and which to take down (their life is over)
function PopupQueue.step(q: Queue, now: number, ctx: Ctx): Step
	local P = q.P
	local out: Step = { show = {}, close = {} }
	-- 1. take down what has had its time (a cut life while others wait)
	local toastsWaiting = 0
	for _, w in q.waiting do
		if w.kind == "toast" then
			toastsWaiting += 1
		end
	end
	for i = #q.showing, 1, -1 do
		local s = q.showing[i]
		local life = s.life
		if life and s.kind == "toast" and toastsWaiting > 0 and not s.urgent then
			life = math.min(life, P.hurry)
		end
		if life and now - (s.shown :: number) >= life then
			table.remove(q.showing, i)
			table.insert(out.close, s)
		end
	end
	-- 2. drop what ran out or went stale while waiting (stale ones count toward "+N more")
	for i = #q.waiting, 1, -1 do
		local w = q.waiting[i]
		if w.expires and now >= w.expires then
			table.remove(q.waiting, i)
		elseif w.stale and now - w.born >= w.stale then
			table.remove(q.waiting, i)
			q.more += w.count
		end
	end
	-- 3. what shows: by pri, then oldest
	table.sort(q.waiting, function(a, b)
		if a.pri ~= b.pri then
			return a.pri > b.pri
		end
		return a.id < b.id
	end)
	local cards = count(q, "card")
	local toasts = count(q, "toast")
	local full = if ctx.phone then P.phoneToasts else P.maxToasts
	-- cards first (a phone shows no toast at all over a big card: it would cover the card's title; the card is
	-- short and a tap closes it), then toasts
	for _, pass in { "card", "toast" } do
		local toastCap = if ctx.phone and cards > 0 then 0 else full
		local i = 1
		while i <= #q.waiting do
			local w = q.waiting[i]
			local go = false
			if w.kind ~= pass then
				go = false
			elseif w.kind == "card" then
				if PopupQueue.cardMay(P, w, ctx, now) and (cards < P.maxCards or w.urgent) then
					go = true
					cards += 1
				end
			elseif toasts < toastCap then
				go = true
				toasts += 1
			elseif w.urgent and toastCap > 0 then
				-- an answer to a tap pushes the oldest small note off (never a big moment: then it waits first in line)
				local oldest, at = nil, nil
				for k, s in q.showing do
					if
						s.kind == "toast"
						and not s.urgent
						and s.pri < P.pri.result
						and (oldest == nil or s.id < oldest.id)
					then
						oldest, at = s, k
					end
				end
				if oldest and at then
					table.remove(q.showing, at)
					table.insert(out.close, oldest)
					go = true
				end
			end
			if go then
				table.remove(q.waiting, i)
				w.shown = now
				table.insert(q.showing, w)
				table.insert(out.show, w)
			else
				i += 1
			end
		end
	end
	return out
end

-- How many folded since the last call (and reset)
function PopupQueue.takeMore(q: Queue): number
	local n = q.more
	q.more = 0
	return n
end

-- Is a card of this name up?
function PopupQueue.up(q: Queue, name: string?): boolean
	for _, s in q.showing do
		if s.kind == "card" and (name == nil or s.name == name) then
			return true
		end
	end
	return false
end

return PopupQueue
