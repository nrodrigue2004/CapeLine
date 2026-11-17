--!strict
-- GuidePlan: the guides' rules (nate's lore, build plan step 6), pure so Lune tests them. Every line in the
-- game plays through one queue (Ui.GuideHud draws it): Lodestar in person, Patch on the radio, Silas Crane's
-- broadcast voice and Act 1's cast, all fixed text from Config.Story (nothing free-typed).
-- * Lines: a line is { who, text } or { who, hero, villain } (read by the side); lineText, speaker, lines
--   (every line in the game with where it lives), validate (speakers, both sides, the phone length cap).
-- * The queue: one line at a time, never two. A camera beat's timed line (cut) takes the box at once; story
--   lines (a stage's radio lines, Lodestar's talk) wait their turn; open-world lines wait while a camera beat
--   runs, are cut when one starts, and go stale. skip ends the line now; cancel drops a tag's lines.
-- * due: which timed line of a beat shows at t, and for how long (until the next, at most `hold`).
-- * The open-world radio: radioOk / radioMark (at most one line a `gap`, once-a-session lines, the idle
--   repeat, the Guide radio setting, never in a mission or the prologue), worldLine, unlockAt, idleMission.
-- * Missions: stageFor (the stage a MissionState packet is on, branches too), stageLines, coverage.
-- * Lodestar: talk (a fixed rotation of lines by story progress; none for the Dread Syndicate, whose HQ he
--   keeps away from).
-- * box: where the line box goes on a w x h screen, clear of the action buttons, the status corner and the
--   top row (TouchLayout), and whether it may take taps (not over the move stick).

local StoryPlan = if script then require(script.Parent.StoryPlan) else (require :: any)("./StoryPlan")
local TouchLayout = if script then require(script.Parent.TouchLayout) else (require :: any)("./TouchLayout")

local GuidePlan = {}

export type Line = { who: string, text: string }
export type Entry = {
	who: string,
	text: string,
	world: boolean?, -- an open-world radio line (waits for camera beats, goes stale)
	cut: boolean?, -- a camera beat's timed line: it takes the box at once
	hold: number?, -- seconds it shows (else from its length)
	tag: string?, -- what queued it (a beat), for cancel
	at: number?, -- when it was queued
}
export type Queue = { current: Entry?, untilT: number, pending: { Entry } }
export type Radio = { last: number, once: { [string]: boolean }, idleAt: number }
export type Box = { x: number, y: number, w: number, h: number, tap: boolean }

GuidePlan.STYLES = { person = true, radio = true, broadcast = true }
GuidePlan.SIDES = { "hero", "villain" }

local function sideKey(side: string): string
	return if side == "villain" then "villain" else "hero"
end

---------------------------------------------------------------------------
-- Lines
---------------------------------------------------------------------------

-- A line's text for a side (text, else the side's own), or nil
function GuidePlan.lineText(line: any, side: string): string?
	local t = line.text or line[sideKey(side)]
	return if type(t) == "string" then t else nil
end

-- A speaker's row (Config.Story.guides.speakers), or nil
function GuidePlan.speaker(Config: any, who: string): any?
	return Config.Story.guides.speakers[who]
end

-- How long a line shows by its length
function GuidePlan.duration(Config: any, text: string): number
	local q = Config.Story.guides.queue
	return math.clamp(q.base + #text * q.perChar, q.min, q.max)
end

-- A stage's radio lines for a side (lore step 6), in order
function GuidePlan.stageLines(step: any, side: string): { Line }
	local out = {}
	for _, l in (step and step.radio) or {} do
		local t = GuidePlan.lineText(l, side)
		if t then
			table.insert(out, { who = l.who, text = t })
		end
	end
	return out
end

-- Every line in the game: { where, line } (the prologue's beats, each mission's camera beats and stage
-- lines with their branches, the ending broadcast, the open-world radio, Lodestar's talk as lines)
function GuidePlan.lines(Config: any): { { where: string, line: any, mission: number? } }
	local S = Config.Story
	local out = {}
	local function add(where: string, line: any, mission: number?)
		table.insert(out, { where = where, line = line, mission = mission })
	end
	for beat, list in S.opening.lines do
		for i, l in list do
			add(string.format("opening.%s[%d]", beat, i), l, 1)
		end
	end
	for num, m in S.missions do
		local function stage(where: string, st: any)
			for i, l in st.lines or {} do
				add(string.format("%s.lines[%d]", where, i), l, num)
			end
			for i, l in st.radio or {} do
				add(string.format("%s.radio[%d]", where, i), l, num)
			end
		end
		for _, key in GuidePlan.SIDES do
			for i, st in m[key] or {} do
				stage(string.format("%s.%s[%d]", m.id, key, i), st)
			end
			for i, st in (m.branches and m.branches[key]) or {} do
				stage(string.format("%s.branches.%s[%d]", m.id, key, i), st)
			end
		end
	end
	for id, e in S.ending do
		for i, l in e.lines do
			add(string.format("ending.%s[%d]", id, i), l)
		end
	end
	local R = S.guides.radio.lines
	for key, v in R do
		if v.who then
			add("radio." .. key, v)
		else
			for n, l in v do
				add(string.format("radio.%s[%s]", key, tostring(n)), l)
			end
		end
	end
	for t, tier in S.guides.lodestar.talk do
		for i, text in tier.lines do
			add(string.format("lodestar.talk[%d][%d]", t, i), { who = "lodestar", text = text })
		end
	end
	return out
end

-- Problems with the lines (empty when all is well): every speaker known, every line readable by both sides,
-- no longer than the phone cap, fixed text (no format holes)
function GuidePlan.validate(Config: any): { string }
	local G = Config.Story.guides
	local bad = {}
	for _, e in GuidePlan.lines(Config) do
		local l = e.line
		if not G.speakers[l.who] then
			table.insert(bad, e.where .. ": unknown speaker " .. tostring(l.who))
		end
		for _, side in GuidePlan.SIDES do
			local t = GuidePlan.lineText(l, side)
			if not t or #t == 0 then
				table.insert(bad, e.where .. ": no text for " .. side)
			elseif #t > G.maxChars then
				table.insert(bad, string.format("%s: %d characters (cap %d)", e.where, #t, G.maxChars))
			elseif string.find(t, "%", 1, true) or string.find(t, "{", 1, true) then
				table.insert(bad, e.where .. ": a format hole")
			end
		end
	end
	for who, sp in G.speakers do
		if not GuidePlan.STYLES[sp.style] then
			table.insert(bad, who .. ": style " .. tostring(sp.style))
		end
		if type(sp.name) ~= "string" or type(sp.color) ~= "table" or type(sp.portrait) ~= "table" then
			table.insert(bad, who .. ": name, colour and portrait")
		end
	end
	return bad
end

---------------------------------------------------------------------------
-- The queue
---------------------------------------------------------------------------

function GuidePlan.queue(): Queue
	return { current = nil, untilT = 0, pending = {} }
end

-- Queue a line. A cut line goes first and ends the one showing; an open-world line is dropped when another
-- open-world line already waits. Returns whether it was queued.
function GuidePlan.push(Q: Queue, e: Entry, now: number): boolean
	e.at = now
	if e.cut then
		Q.current = nil
		table.insert(Q.pending, 1, e)
		return true
	end
	if e.world then
		for _, p in Q.pending do
			if p.world then
				return false
			end
		end
		table.insert(Q.pending, e)
		return true
	end
	-- a story line: after the story lines already waiting, before the open-world ones
	local at = #Q.pending + 1
	for i, p in Q.pending do
		if p.world then
			at = i
			break
		end
	end
	table.insert(Q.pending, at, e)
	return true
end

-- Each frame: ends the line whose time is up, then starts the next. paused: a camera beat (or the prologue,
-- or a broadcast) is on, so open-world lines wait and one showing is cut. Returns the line that started.
function GuidePlan.tick(Config: any, Q: Queue, now: number, paused: boolean): Entry?
	local cur = Q.current
	if cur and (now >= Q.untilT or (paused and cur.world)) then
		Q.current = nil
	end
	if Q.current then
		return nil
	end
	local ttl = Config.Story.guides.queue.ttl
	local i = 1
	while i <= #Q.pending do
		local p = Q.pending[i]
		if p.world and now - (p.at or now) > ttl then
			table.remove(Q.pending, i)
		else
			i += 1
		end
	end
	for k, p in Q.pending do
		if not (p.world and paused) then
			table.remove(Q.pending, k)
			Q.current = p
			Q.untilT = now + (p.hold or GuidePlan.duration(Config, p.text))
			return p
		end
	end
	return nil
end

-- End the line showing now (the next starts on the next tick)
function GuidePlan.skip(Q: Queue)
	Q.current = nil
	Q.untilT = 0
end

-- Drop a tag's lines (a beat that ended): the one showing and any waiting
function GuidePlan.cancel(Q: Queue, tag: string)
	if Q.current and Q.current.tag == tag then
		Q.current = nil
	end
	local i = 1
	while i <= #Q.pending do
		if Q.pending[i].tag == tag then
			table.remove(Q.pending, i)
		else
			i += 1
		end
	end
end

-- A beat's timed lines ({ at, who, text } by time): the newest due at t when it is past `said`, and the
-- seconds it should still show (until the next line, at most `hold`; nil when its time already passed, so a
-- late join skips it). Returns nil when nothing new is due.
function GuidePlan.due(Config: any, list: { any }, t: number, said: number): (number?, number?)
	local idx = nil
	for i, l in list do
		if l.at <= t then
			idx = i
		end
	end
	if not idx or idx <= said then
		return nil, nil
	end
	local l = list[idx]
	local hold = Config.Story.guides.queue.hold
	local nxt = list[idx + 1]
	local span = if nxt then math.min(nxt.at - l.at, hold) else hold
	local left = span - (t - l.at)
	if left <= 0.25 then
		return idx, nil
	end
	return idx, left
end

---------------------------------------------------------------------------
-- The open-world radio (Patch)
---------------------------------------------------------------------------

function GuidePlan.radio(): Radio
	return { last = -math.huge, once = {}, idleAt = -math.huge }
end

local ONCE = { firstIncident = true, firstBoss = true, afterAct1 = true }

-- May Patch say an open-world line for `key` now? ctx.on: the Guide radio setting; ctx.busy: in a mission,
-- the prologue or a camera beat. Unlock keys ("unlock3") and afterAct1 are once a session too.
function GuidePlan.radioOk(
	Config: any,
	R: Radio,
	now: number,
	key: string,
	ctx: { on: boolean, busy: boolean }
): boolean
	local cfg = Config.Story.guides.radio
	if not ctx.on or ctx.busy then
		return false
	end
	if now - R.last < cfg.gap then
		return false
	end
	if (ONCE[key] or string.sub(key, 1, 6) == "unlock") and R.once[key] then
		return false
	end
	if string.sub(key, 1, 4) == "idle" and now - R.idleAt < cfg.idleRepeat then
		return false
	end
	return true
end

-- Patch said `key` at now
function GuidePlan.radioMark(R: Radio, now: number, key: string)
	R.last = now
	R.once[key] = true
	if string.sub(key, 1, 4) == "idle" then
		R.idleAt = now
	end
end

-- An open-world line for a side: key "firstIncident", "firstBoss" or "afterAct1", or "unlock" / "idle"
-- with the mission number
function GuidePlan.worldLine(Config: any, key: string, side: string, n: number?): Line?
	local row = Config.Story.guides.radio.lines[key]
	if row and n then
		row = row[n]
	end
	if not row or not row.who then
		return nil
	end
	local t = GuidePlan.lineText(row, side)
	return if t then { who = row.who, text = t } else nil
end

-- The mission a level-up to `level` opens (its minLevel, and open now), or nil
function GuidePlan.unlockAt(Config: any, story: any, level: number): number?
	for num, m in Config.Story.missions do
		if not m.opening and m.minLevel == level and StoryPlan.state(Config, story, level, num) == "open" then
			return num
		end
	end
	return nil
end

-- The story mission the Journal pins (no side quest pinned) when it is open to play, or nil
function GuidePlan.idleMission(Config: any, story: any, level: number): number?
	if (story.pinned or 0) ~= 0 then
		return nil
	end
	local num = StoryPlan.nextMission(Config, story)
	local m = num and Config.Story.missions[num]
	if not num or not m or m.opening or StoryPlan.state(Config, story, level, num) ~= "open" then
		return nil
	end
	return num
end

---------------------------------------------------------------------------
-- Missions
---------------------------------------------------------------------------

-- The stage a MissionState packet ({ num, step, side, kind, text }) is on, its branch in place, or nil
function GuidePlan.stageFor(Config: any, m: { [string]: any }): any?
	local def = Config.Story.missions[m.num or 0]
	if not def or not def.hero then
		return nil
	end
	local key = sideKey(m.side or "hero")
	local st = def[key][m.step or 0]
	if not st then
		return nil
	end
	if st.kind ~= "branch" then
		return if st.kind == m.kind then st else nil
	end
	for _, b in (def.branches and def.branches[key]) or {} do
		if b.kind == m.kind and StoryPlan.text(b, key) == m.text then
			return b
		end
	end
	return nil
end

-- Who speaks in mission num for a side, and how often: { [who] = lines } (the prologue's beats for mission
-- 1; every stage, camera beat and branch for the rest)
function GuidePlan.coverage(Config: any, num: number, side: string): { [string]: number }
	local out: { [string]: number } = {}
	local function count(who: string)
		out[who] = (out[who] or 0) + 1
	end
	local m = Config.Story.missions[num]
	if not m then
		return out
	end
	if m.opening then
		for _, list in Config.Story.opening.lines do
			for _, l in list do
				if GuidePlan.lineText(l, side) then
					count(l.who)
				end
			end
		end
		return out
	end
	local key = sideKey(side)
	local steps = table.clone(m[key] or {})
	for _, b in (m.branches and m.branches[key]) or {} do
		table.insert(steps, b)
	end
	for _, st in steps do
		for _, l in st.lines or {} do
			if GuidePlan.lineText(l, side) then
				count(l.who)
			end
		end
		for _, l in GuidePlan.stageLines(st, side) do
			count(l.who)
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Lodestar
---------------------------------------------------------------------------

-- Lodestar's n-th talk line for the story so far (a fixed rotation), or nil for the Dread Syndicate
function GuidePlan.talk(Config: any, story: any, side: string, n: number): Line?
	if side == "villain" then
		return nil
	end
	local L = Config.Story.guides.lodestar
	local nxt = StoryPlan.nextMission(Config, story) or (#Config.Story.missions + 1)
	local tier = L.talk[1]
	for _, t in L.talk do
		if t.from <= nxt then
			tier = t
		end
	end
	local lines = tier.lines
	return { who = "lodestar", text = lines[(math.max(1, n) - 1) % #lines + 1] }
end

---------------------------------------------------------------------------
-- The box
---------------------------------------------------------------------------

local function overlaps(a: any, b: any): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end
GuidePlan.overlaps = overlaps

-- What the box must stay clear of on a w x h safe area: every action button (its circle's box, the Boost
-- ring counted), the status corner (status card, wallet, buffs, radar and its text) and the top row
function GuidePlan.obstacles(Config: any, w: number, h: number, opts: any): { any }
	local o = opts or {}
	local out = {}
	local placed, s = TouchLayout.cluster(Config, w, h, o)
	for id, p in placed do
		local slot = TouchLayout.SLOTS[id]
		if id ~= "Catch" and (not slot.optional or (o.present and o.present[id])) then
			local r = p.size / 2 + (if id == "Boost" then TouchLayout.RING * s else 0)
			table.insert(out, { x = p.x - r, y = p.y - r, w = r * 2, h = r * 2 })
		end
	end
	local hud = TouchLayout.hud(Config, w, h, o)
	for _, key in { "status", "wallet", "buffs", "radar", "radarText" } do
		table.insert(out, (hud :: any)[key])
	end
	table.insert(out, { x = 0, y = 0, w = w, h = TouchLayout.topReserve(Config, w, h) })
	return out
end

-- The widest free span of x in [lo, hi] for a band [y0, y1] with these obstacles (each kept `gap` away)
local function freeSpan(
	list: { any },
	y0: number,
	y1: number,
	lo: number,
	hi: number,
	gap: number
): (number, number)
	local cuts = {}
	for _, b in list do
		if b.y < y1 + gap and y0 - gap < b.y + b.h then
			table.insert(cuts, { b.x - gap, b.x + b.w + gap })
		end
	end
	table.sort(cuts, function(a, b)
		return a[1] < b[1]
	end)
	local bestA, bestB = lo, lo
	local x = lo
	for _, c in cuts do
		if c[1] > x then
			local a, b = x, math.min(c[1], hi)
			if b - a > bestB - bestA then
				bestA, bestB = a, b
			end
		end
		x = math.max(x, c[2])
	end
	if hi - x > bestB - bestA then
		bestA, bestB = x, hi
	end
	return bestA, bestB
end

-- Where the line box goes. cinematic: a camera beat (the HUD's buttons are away), centred under the
-- letterbox. In play: the first band from the top (under the top row, then under each obstacle) with a free
-- span of at least minW, the box up to maxW in it, near the centre; else the widest band found. extra: more
-- boxes to keep clear of (the story trackers). tap: the box may take taps (it is not over the move stick).
function GuidePlan.box(Config: any, w: number, h: number, opts: any, cinematic: boolean, extra: { any }?): Box
	local B = Config.Story.guides.box
	local o = opts or {}
	local m = Config.Ui.safe
	local gap = Config.Ui.phone.gap
	local bh = if TouchLayout.compact(Config, w, h) then B.hCompact else B.h
	if cinematic then
		local bw = math.min(B.maxW, w - 2 * m)
		return { x = (w - bw) / 2, y = h * B.letterbox + 6, w = bw, h = bh, tap = true }
	end
	local list = GuidePlan.obstacles(Config, w, h, o)
	local more: { any } = extra or {}
	for _, b in more do
		table.insert(list, b)
	end
	local ys = { TouchLayout.topReserve(Config, w, h) }
	for _, b in list do
		table.insert(ys, b.y + b.h + gap)
	end
	table.sort(ys)
	local best: { y: number, a: number, b: number }? = nil
	for _, y in ys do
		if y + bh <= h - m then
			local a, b = freeSpan(list, y, y + bh, m, w - m, gap)
			if b - a >= B.minW then
				best = { y = y, a = a, b = b }
				break
			end
			if not best or b - a > best.b - best.a then
				best = { y = y, a = a, b = b }
			end
		end
	end
	local pick = best or { y = TouchLayout.topReserve(Config, w, h), a = m, b = w - m }
	local bw = math.min(B.maxW, pick.b - pick.a)
	local x = math.clamp(w / 2 - bw / 2, pick.a, pick.b - bw)
	local out: Box = { x = x, y = pick.y, w = bw, h = bh, tap = true }
	if o.touch ~= false then
		local mode = if o.leftHanded then "left" else (o.stick or "default")
		out.tap = not overlaps(out, TouchLayout.stickZone(w, h, mode))
	end
	return out
end

return GuidePlan
