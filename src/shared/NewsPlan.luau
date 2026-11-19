--!strict
-- NewsPlan: the in-city news broadcasts (nate's lore, build plan step 7; Config.Cinema.news). Pure, so Lune
-- tests it. The server (NewsService) turns what players did into facts; every device keeps a short feed and
-- shows it on the big screens and the HUD's corner TV.
-- * A fact: { k = kind code, t = title id, n = noun id, a = a number (boss num, mission num, robot type id,
--   a count), at = os.clock() on the device }. The hero's name is CreatorRules.heroName(t, n): the safe name
--   system, never free text. text(Config, fact, name) fills one fixed template.
-- * push(Config, feed, fact, now): keeps the newest Config.Cinema.news.feed facts; the same kind for the same
--   hero is news once in repeatGap seconds.
-- * reel(Config, feed, now): what a screen shows now: BREAKING (a fresh flash), Crane's segment (a fixed line)
--   or the ticker, in turn.
-- * streak(Config, streaks, heroId, now): incident clears in a row; returns the count when it is news.
-- * screens(Config, world): where the big screens hang (Downtown towers by the plaza, the plaza's own frame,
--   the Crane billboard on Uptown's landmark).

local NewsPlan = {}

-- Fact kinds on the wire (NewsFact k)
-- (only add at the end: the codes go on the wire; "double" and "doubleDown" are lore step 9's Your double event)
NewsPlan.KINDS = {
	"boss",
	"bossDown",
	"bossAway",
	"unmask",
	"streak",
	"heist",
	"heistVillain",
	"act1",
	"double",
	"doubleDown",
	-- lore step 12 (the city remembers): a = the rank (1 to 5) for the rep kinds, the event's num for the side kinds
	"repVigil",
	"repSyndicate",
	"sideStart",
	"sideVigil",
	"sideSyndicate",
	"sideDraw",
	-- WP5: a Suspicious Hero unmasked in the street (the Vigil exposes it; the Syndicate spreads the panic)
	"fakeVigil",
	"fakeSyndicate",
}
NewsPlan.CODE = {} :: { [string]: number }
for i, k in NewsPlan.KINDS do
	NewsPlan.CODE[k] = i
end

export type Fact = { k: number, t: number?, n: number?, a: number?, at: number? }

-- The thing a fact is about, from config only (a boss, a fake, a mission's name, a count). A world boss's
-- arrival names it with its title (the name card's: "RUSTJAW PRIME, THE JUNKYARD TITAN")
local function thing(Config: any, kind: string, a: number?): string?
	local n = a or 0
	if kind == "boss" or kind == "bossDown" or kind == "bossAway" then
		for id, b in Config.Boss.bosses do
			if b.num == n then
				local title = Config.Cinema.nameCard.titles[id]
				if kind == "boss" and not b.mission and title then
					return string.upper(b.name) .. ", " .. title
				end
				return string.upper(b.name)
			end
		end
		return nil
	elseif kind == "unmask" then
		for _, e in Config.Enemies do
			if type(e) == "table" and e.typeId == n and e.name then
				return string.upper(e.name)
			end
		end
		return nil
	elseif kind == "streak" then
		return if n >= 2 and n <= 999 and n == math.floor(n) then tostring(n) else nil
	elseif kind == "act1" then
		local m = Config.Story.missions[n]
		return if m and m.name then string.upper(m.name) else nil
	elseif kind == "repVigil" or kind == "repSyndicate" then
		-- lore step 12: the rank and its title (Config.Remembers.titles), e.g. RANK 5, "HEART OF THE CITY"
		local list = Config.Remembers.titles[if kind == "repVigil" then "vigil" else "syndicate"]
		local title = list and list[n]
		return if title then string.format('RANK %d, "%s"', n, string.upper(title)) else nil
	elseif kind == "sideStart" or kind == "sideVigil" or kind == "sideSyndicate" or kind == "sideDraw" then
		-- lore step 12: a side-vs-side event's card name
		for _, id in Config.Events.side or {} do
			local e = Config.Events.events[id]
			local card = Config.Cinema.nameCard.events[id]
			if e and e.num == n then
				return if card then card.name else string.upper(e.name)
			end
		end
		return nil
	end
	return ""
end

-- Does this kind name a hero?
function NewsPlan.named(kind: string): boolean
	return kind ~= "boss" and kind ~= "bossAway" and kind ~= "sideStart" and kind ~= "sideDraw"
end

-- A fact's line (nil for a bad fact): the template with the hero's name and the thing put in
function NewsPlan.text(Config: any, fact: Fact, name: string?): string?
	local kind = NewsPlan.KINDS[fact.k]
	if not kind then
		return nil
	end
	local tpl = Config.Cinema.news.templates[kind]
	local th = thing(Config, kind, fact.a)
	if not tpl or th == nil then
		return nil
	end
	local who = string.upper(name or "")
	if NewsPlan.named(kind) and who == "" then
		who = "A HERO"
	end
	local out = string.gsub(tpl, "%%s", function()
		return who
	end)
	local thingText: string = th or ""
	out = string.gsub(out, "%%t", function()
		return thingText
	end)
	return out
end

-- Does it also flash on every HUD (toast + corner TV)?
function NewsPlan.flash(Config: any, fact: Fact): boolean
	local kind = NewsPlan.KINDS[fact.k]
	return kind ~= nil and Config.Cinema.news.flash[kind] == true
end

function NewsPlan.feed(): { Fact }
	return {}
end

-- Add a fact (newest first). False when it is a repeat (same kind, same hero, within repeatGap).
function NewsPlan.push(Config: any, feed: { Fact }, fact: Fact, now: number): boolean
	local N = Config.Cinema.news
	if not NewsPlan.KINDS[fact.k] then
		return false
	end
	for _, f in feed do
		if
			f.k == fact.k
			and f.t == fact.t
			and f.n == fact.n
			and f.a == fact.a
			and now - (f.at or 0) < N.repeatGap
		then
			return false
		end
	end
	fact.at = now
	table.insert(feed, 1, fact)
	while #feed > N.feed do
		table.remove(feed)
	end
	return true
end

-- What the screens show now: "breaking" (with the fact), "crane" (with the line's index) or "ticker"
function NewsPlan.reel(Config: any, feed: { Fact }, now: number): (string, any)
	local N = Config.Cinema.news
	local top = feed[1]
	if top and NewsPlan.flash(Config, top) and now - (top.at or 0) < N.breaking then
		return "breaking", top
	end
	local cycle = N.reel.crane + N.reel.ticker
	local t = now % cycle
	if t < N.reel.crane or #feed == 0 then
		local n = #N.crane
		return "crane", (math.floor(now / cycle) % n) + 1
	end
	return "ticker", nil
end

-- One ticker line from the feed (each fact once, joined), the safe names from nameOf(t, n)
function NewsPlan.ticker(Config: any, feed: { Fact }, nameOf: (number?, number?) -> string?): string
	local parts = {}
	for _, f in feed do
		local line = NewsPlan.text(Config, f, nameOf(f.t, f.n))
		if line then
			table.insert(parts, line)
		end
	end
	if #parts == 0 then
		return Config.Cinema.news.channel
	end
	return table.concat(parts, "   *   ")
end

-- Incident clears in a row: { [heroId] = { n, at } }. Returns the count when it reaches a news mark.
function NewsPlan.streak(Config: any, streaks: { [number]: any }, heroId: number, now: number): number?
	local S = Config.Cinema.news.streak
	local s = streaks[heroId]
	if not s or now - s.at > S.gap then
		s = { n = 0, at = now }
		streaks[heroId] = s
	end
	s.n += 1
	s.at = now
	return if table.find(S.at, s.n) then s.n else nil
end

export type Screen = {
	kind: string, -- "downtown", "plaza", "uptown"
	x: number,
	y: number,
	z: number,
	nx: number, -- the way it faces (flat)
	nz: number,
	w: number,
	h: number,
	building: number?, -- the building it hangs on (hidden while that building is down)
}

-- The wall pieces of a building's Structure grid a screen hangs on (fix-destroy, 2026-11-19, nate: the billboard's
-- words "keep showing after the building is destroyed"): the panels and pillars of the face it is on, under its
-- span and height. Once any of them is knocked out the screen falls with it (NewsService sets Down).
function NewsPlan.behind(grid: any, s: Screen): { number }
	local face = if s.nx > 0 then 4 elseif s.nx < 0 then 3 elseif s.nz > 0 then 2 else 1
	local out = {}
	for i, p in grid.pieces do
		if p.kind == "wall" or p.kind == "pillar" then
			local onFace = p.kind == "wall" and p.face == face
			if p.kind == "pillar" then
				-- a corner pillar belongs to the two faces it joins
				local c = p.face
				onFace = (face == 1 and (c == 1 or c == 2))
					or (face == 2 and (c == 3 or c == 4))
					or (face == 3 and (c == 1 or c == 3))
					or (face == 4 and (c == 2 or c == 4))
			end
			if onFace then
				local along = if face <= 2
					then math.abs(p.cx - s.x) - p.sx / 2
					else math.abs(p.cz - s.z) - p.sz / 2
				local up = math.abs(p.cy - s.y) - p.sy / 2
				if along < s.w / 2 and up < s.h / 2 then
					table.insert(out, i)
				end
			end
		end
	end
	return out
end

-- Is a screen down: its building collapsed, or a piece it hangs on gone (gone: piece -> true)
function NewsPlan.screenDown(state: number, behind: { number }, gone: { [number]: boolean }?): boolean
	if state == 2 then
		return true
	end
	if state == 1 and gone then
		for _, i in behind do
			if gone[i] then
				return true
			end
		end
	end
	return false
end

-- Where the big screens hang for a world (WorldMap.build's): the Downtown towers nearest the plaza with a
-- face toward it, a screen on a frame at the plaza's edge, and the Crane billboard on Uptown's landmark
function NewsPlan.screens(Config: any, world: any): { Screen }
	local S = Config.Cinema.news.screens
	local gy = Config.City.ground.y
	local bt = world.downtown and world.downtown.beacon
	local px, pz = if bt then bt.x else -400, if bt then bt.z else 0
	local out: { Screen } = {}
	local function face(b: any, tx: number, tz: number): (number, number)
		if math.abs(tx - b.x) / b.sx > math.abs(tz - b.z) / b.sz then
			return if tx > b.x then 1 else -1, 0
		end
		return 0, if tz > b.z then 1 else -1
	end
	-- the plaza's own screen: on a frame, back from the plaza's centre, facing it
	local P = S.plaza
	table.insert(out, {
		kind = "plaza",
		x = px,
		y = gy + P.height,
		z = pz - P.back,
		nx = 0,
		nz = 1,
		w = P.size[1],
		h = P.size[2],
	})
	-- Downtown: the towers nearest the plaza (stable order by distance, then id)
	local list = {}
	for _, b in world.buildings or {} do
		if b.district == "Downtown" and b.top - gy >= S.minTop and b.sx >= S.size[1] * 0.8 then
			local d = (b.x - px) ^ 2 + (b.z - pz) ^ 2
			if d > 60 ^ 2 then
				table.insert(list, { b = b, d = d })
			end
		end
	end
	table.sort(list, function(a, b)
		return if a.d == b.d then a.b.id < b.b.id else a.d < b.d
	end)
	for i = 1, math.min(S.downtown, #list) do
		local b = list[i].b
		local nx, nz = face(b, px, pz)
		local half = if nx ~= 0 then b.sx / 2 else b.sz / 2
		table.insert(out, {
			kind = "downtown",
			x = b.x + nx * (half + 1),
			y = math.min(b.top - S.size[2] / 2 - 4, gy + 30 + S.size[2] / 2),
			z = b.z + nz * (half + 1),
			nx = nx,
			nz = nz,
			w = S.size[1],
			h = S.size[2],
			building = b.id,
		})
	end
	-- Uptown: the Crane billboard on the landmark's face toward Downtown
	local up = world.uptown
	local L = up and up.landmark
	if L and L.size > 0 then
		local U = S.uptown
		local on: number? = nil
		for _, b in world.buildings or {} do
			if math.abs(b.x - L.x) < 1 and math.abs(b.z - L.z) < 1 then
				on = b.id
			end
		end
		local nx, nz = 0, 0
		if math.abs(px - L.x) > math.abs(pz - L.z) then
			nx = if px > L.x then 1 else -1
		else
			nz = if pz > L.z then 1 else -1
		end
		table.insert(out, {
			kind = "uptown",
			x = L.x + nx * (L.size / 2 + 1),
			y = gy + 60 + U.size[2] / 2,
			z = L.z + nz * (L.size / 2 + 1),
			nx = nx,
			nz = nz,
			w = U.size[1],
			h = U.size[2],
			building = on,
		})
	end
	return out
end

return NewsPlan
