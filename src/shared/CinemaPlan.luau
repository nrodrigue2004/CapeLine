--!strict
-- CinemaPlan: the cinematic layer's rules (nate's lore, build plan step 7; Config.Cinema). Pure, so Lune tests
-- it; the device's cutscene player (CinemaClient) and the server (CinemaService, OpeningService,
-- MissionService) use the same rules.
-- * Shots: cut (a still camera), dolly (from -> to, looking at -> at2), orbit (round a centre), look (a pan
--   from one spot: a dolly that stays put). sample(shot, k, out) writes the camera's position and look point
--   into `out` (6 numbers) with no new tables, so the player reads it every frame. Points are { x, y, z }.
-- * at(shots, t): the shot running at t and how far into it (eased 0 to 1).
-- * check(Config, scene): a scene's shots are back to back from 0, of known kinds, 5 to 20 s long, and its
--   subtitles fall inside it.
-- * The seen set: a scene's bit (named scenes) or a mission stage's bit (missionBit); canSkip once seen.
-- * safe(Config, ctx): a device-started scene plays only when no fight would leave the hero defenceless.
-- * motion(Config, option, reduceFlashing): the dynamic camera's scales (lean, push, orbit, shake, flash).
-- * finisher(Config, style, role, option, reduceFlashing): the slow-mo finisher's plan by fx style.
-- * nameCardDue(Config, ...): a boss's name card for a hero arriving at the fight.

local CinemaPlan = {}

export type Shot = {
	kind: string, -- "cut", "dolly", "orbit", "look"
	t0: number,
	t1: number,
	from: { number }?,
	to: { number }?,
	at: { number }?,
	at2: { number }?,
	center: { number }?,
	radius: number?,
	height: number?,
	yaw0: number?,
	yaw1: number?,
	lift: number?,
	ease: string?, -- "smooth" (default) or "linear"
}

CinemaPlan.KINDS = { cut = true, dolly = true, orbit = true, look = true }

local function ease(x: number, how: string?): number
	if how == "linear" then
		return x
	end
	return x * x * (3 - 2 * x)
end
CinemaPlan.ease = ease

local function lerp(a: number, b: number, k: number): number
	return a + (b - a) * k
end

local ORIGIN = { 0, 0, 0 }
local AHEAD = { 0, 0, -1 }

-- The camera for a shot at k (0 to 1, already eased): out[1..3] the camera, out[4..6] where it looks
function CinemaPlan.sample(shot: Shot, k: number, out: { number }): { number }
	local kind = shot.kind
	if kind == "orbit" then
		local c: { number } = shot.center or ORIGIN
		local yaw = lerp(shot.yaw0 or 0, shot.yaw1 or 0, k)
		local r = shot.radius or 20
		out[1] = c[1] + math.sin(yaw) * r
		out[2] = c[2] + (shot.height or 0)
		out[3] = c[3] + math.cos(yaw) * r
		out[4] = c[1]
		out[5] = c[2] + (shot.lift or 0)
		out[6] = c[3]
		return out
	end
	local a: { number } = shot.from or ORIGIN
	local b: { number } = if kind == "dolly" then (shot.to or a) else a
	local la: { number } = shot.at or AHEAD
	local lb: { number } = if kind == "cut" then la else (shot.at2 or la)
	for i = 1, 3 do
		out[i] = lerp(a[i], b[i], k)
		out[i + 3] = lerp(la[i], lb[i], k)
	end
	return out
end

-- The shot running at t (the last one after the end) and how far into it, eased
function CinemaPlan.at(shots: { Shot }, t: number): (Shot?, number)
	local n = #shots
	if n == 0 then
		return nil, 0
	end
	local s = shots[n]
	for i = 1, n do
		local x = shots[i]
		if t >= x.t0 and t < x.t1 then
			s = x
			break
		end
	end
	if t < shots[1].t0 then
		s = shots[1]
	end
	local k = math.clamp((t - s.t0) / math.max(0.01, s.t1 - s.t0), 0, 1)
	return s, ease(k, s.ease)
end

-- How long a scene runs: its own seconds, else its last shot's end
function CinemaPlan.length(scene: { [string]: any }): number
	if type(scene.seconds) == "number" then
		return scene.seconds
	end
	local shots = scene.shots or {}
	return if #shots > 0 then shots[#shots].t1 else 0
end

-- Shots placed round a point (a client scene's shots are offsets from the hero): new tables, made once per play
function CinemaPlan.around(shots: { Shot }, x: number, y: number, z: number): { Shot }
	local out = {}
	local function move(p: { number }?): { number }?
		return if p then { p[1] + x, p[2] + y, p[3] + z } else nil
	end
	for _, s in shots do
		local c = table.clone(s)
		if s.kind == "orbit" then
			c.center = move(s.center or { 0, 0, 0 })
		else
			c.from, c.to, c.at, c.at2 = move(s.from), move(s.to), move(s.at), move(s.at2)
		end
		table.insert(out, c)
	end
	return out
end

-- A scene is well formed: shots back to back from 0 with known kinds and points, 5 to 20 s long (the
-- Ceremony's `long` beat may run to its own length), its lines inside it. Returns ok and the first problem.
function CinemaPlan.check(Config: any, scene: { [string]: any }, seconds: number?): (boolean, string?)
	local L = Config.Cinema.length
	local len = seconds or CinemaPlan.length(scene)
	if not scene.long and (len < L.min or len > L.max) then
		return false, string.format("runs %.1f s (want %d to %d)", len, L.min, L.max)
	end
	local shots = scene.shots
	if shots then
		local t = 0
		for i, s in shots do
			if not CinemaPlan.KINDS[s.kind] then
				return false, "shot " .. i .. " kind " .. tostring(s.kind)
			end
			if math.abs(s.t0 - t) > 1e-6 or s.t1 <= s.t0 then
				return false, "shot " .. i .. " is not back to back"
			end
			if s.t1 - s.t0 > L.max then
				return false, "shot " .. i .. " is longer than a scene"
			end
			if s.kind == "orbit" then
				if not s.radius or s.radius <= 0 then
					return false, "shot " .. i .. " orbit needs a radius"
				end
			elseif not s.from or not s.at then
				return false, "shot " .. i .. " needs from and at"
			end
			t = s.t1
		end
		if math.abs(t - len) > 0.05 then
			return false, string.format("shots end at %.1f, scene at %.1f", t, len)
		end
	end
	for _, l in scene.lines or {} do
		if l.at < 0 or l.at >= len then
			return false, "a line falls outside the scene"
		end
	end
	return true, nil
end

---------------------------------------------------------------------------
-- The seen set (profile.seen)
---------------------------------------------------------------------------

-- A named scene's bit, or nil
function CinemaPlan.bit(Config: any, id: string): number?
	local s = Config.Cinema.scenes[id]
	return s and s.bit
end

-- Is this bit in a named scene's range? 0 up to the missions' base, then Cinema.extraBits (the seen
-- set's last bits, above the missions')
function CinemaPlan.namedBit(Config: any, bit: number): boolean
	local C = Config.Cinema
	if type(bit) ~= "number" or bit % 1 ~= 0 then
		return false
	end
	if bit >= 0 and bit < C.missionBits.base then
		return true
	end
	local x = C.extraBits
	return x ~= nil and bit >= x.from and bit <= x.to
end

-- The bit of a mission stage's camera beat, or nil outside the range
function CinemaPlan.missionBit(Config: any, num: number, stage: number): number?
	local M = Config.Cinema.missionBits
	if num < 1 or num > M.missions or stage < 1 or stage > M.perMission then
		return nil
	end
	return M.base + (num - 1) * M.perMission + (stage - 1)
end

-- May a device send SceneSeen for this bit? Only a device-started scene's
function CinemaPlan.clientBit(Config: any, bit: number): boolean
	for _, s in Config.Cinema.scenes do
		if s.bit == bit and s.client then
			return true
		end
	end
	return false
end

-- seen: a list of set bits (the client view) or a lookup { [bit] = true }
function CinemaPlan.seen(seen: any, bit: number?): boolean
	if bit == nil or type(seen) ~= "table" then
		return false
	end
	if seen[bit] == true then
		return true
	end
	return table.find(seen, bit) ~= nil
end

-- Skip shows only for a scene seen before (on this save), and never in its first moment
function CinemaPlan.canSkip(Config: any, seen: any, bit: number?, t: number): boolean
	return CinemaPlan.seen(seen, bit) and t >= Config.Cinema.skipDelay
end

---------------------------------------------------------------------------
-- Safe moments
---------------------------------------------------------------------------

-- ctx: beat (a prologue or mission camera beat: the server already made it safe), hitAgo (seconds since the
-- hero was last hit), enemy (studs to the nearest drawn robot), downed, pvp (the PvP flag), boss (in a world
-- boss fight's arena)
function CinemaPlan.safe(Config: any, ctx: { [string]: any }): (boolean, string?)
	if ctx.beat then
		return true, nil
	end
	local S = Config.Cinema.safe
	if ctx.downed then
		return false, "downed"
	elseif ctx.pvp then
		return false, "pvp"
	elseif ctx.boss then
		return false, "boss"
	elseif (ctx.hitAgo or math.huge) < S.quietSeconds then
		return false, "hit"
	elseif (ctx.enemy or math.huge) < S.enemyRange then
		return false, "enemy"
	end
	return true, nil
end

---------------------------------------------------------------------------
-- The dynamic camera and Reduce flashing
---------------------------------------------------------------------------

export type Motion = { lean: number, push: number, orbit: number, shake: number, flash: number, slow: number }

-- option: the Camera motion setting (0 Full, 1 Reduced, 2 Off). Reduced halves the camera's moves, Off
-- removes them (and its shakes); Reduce flashing removes flashes and shakes whatever the camera setting.
-- The slow-mo's time feel is not camera motion and stays.
function CinemaPlan.motion(Config: any, option: number, reduceFlashing: boolean, out: Motion?): Motion
	local scale = Config.Cinema.camera.scale[math.clamp(math.floor(option or 0), 0, 2) + 1]
	local m = out or ({} :: any)
	m.lean = scale
	m.push = scale
	m.orbit = scale
	m.shake = if reduceFlashing then 0 else scale
	m.flash = if reduceFlashing then 0 else 1
	m.slow = 1
	return m
end

export type Finisher = {
	slow: number, -- time scale while it holds (1 = none)
	seconds: number,
	push: number, -- FOV share narrowed
	word: boolean, -- Comic: the big impact word
	hitStop: number, -- Comic: seconds everything holds
	freeze: number, -- Anime: seconds of the freeze frame
	lines: number, -- Anime: speed lines drawn
	flash: number, -- 0 to 1: the white frame
}

-- The finisher for a style ("Comic" or "Anime") and role ("killer": the finishing player; "near": anyone
-- close by sees a shorter version). Reduce flashing drops the hit stop, the freeze and the white frame (the
-- setting is "no shake or hit-pause"); the word and the lines stay (nothing flashes).
function CinemaPlan.finisher(
	Config: any,
	style: string,
	role: string,
	option: number,
	reduceFlashing: boolean
): Finisher
	local F = Config.Cinema.finisher
	local who = if role == "killer" then F.killer else F.nearby
	local m = CinemaPlan.motion(Config, option, reduceFlashing)
	local short = if role == "killer" then 1 else 0.5
	local anime = style == "Anime"
	return {
		slow = who.slow,
		seconds = who.seconds,
		push = Config.Cinema.camera.push.finisher * m.push * short,
		word = not anime,
		hitStop = if anime or reduceFlashing then 0 else F.comic.hitStop * short,
		freeze = if anime and not reduceFlashing then F.anime.freeze * short else 0,
		lines = if anime then math.floor(F.anime.lines * (if role == "killer" then 1 else 0.6)) else 0,
		flash = if reduceFlashing then 0 else (if anime then 0.6 else 0.35) * short,
	}
end

-- Which blows are finishers: the one that brings down a boss or an elite robot, or ends a boss's phase or
-- cracks a fake's face (ends its first phase). what: "bossDead", "bossPhase", "eliteDead", "unmask".
CinemaPlan.FINISHERS = { bossDead = true, bossPhase = true, eliteDead = true, unmask = true }

-- The role this device plays: the finishing player's own, a shorter one nearby, else none
function CinemaPlan.role(Config: any, byMe: boolean, distance: number): string?
	if byMe then
		return "killer"
	elseif distance <= Config.Cinema.finisher.near then
		return "near"
	end
	return nil
end

-- The impact word for an event (seeded, the same on every screen)
function CinemaPlan.word(Config: any, what: string, seed: number): string
	local F = Config.Cinema.finisher
	local list = if what == "bossPhase" or what == "unmask" then F.phaseWords else F.words
	return list[(math.floor(math.abs(seed)) % #list) + 1]
end

---------------------------------------------------------------------------
-- Boss name cards
---------------------------------------------------------------------------

-- A boss's name card is due for a hero who has not had it this fight, while it lands or fights, once within
-- reach of the arena (distance from its centre)
function CinemaPlan.nameCardDue(
	Config: any,
	state: number,
	distance: number,
	arenaRadius: number,
	shown: boolean
): boolean
	-- Boss.State codes: 2 landing, 3 fight
	return not shown and (state == 2 or state == 3) and distance <= arenaRadius + Config.Cinema.nameCard.reach
end

-- The card's two lines: the boss's name and its title
function CinemaPlan.nameCard(Config: any, bossId: string): (string, string)
	local b = Config.Boss.bosses[bossId]
	local name = if b then string.upper(b.name) else "UNKNOWN"
	return name, Config.Cinema.nameCard.titles[bossId] or ""
end

-- A place's or an event's card (lore step 9; group "places" or "events"): its two lines and slash colour, or nil
function CinemaPlan.card(Config: any, group: string, id: string): (string?, string?, { number }?)
	local list = Config.Cinema.nameCard[group]
	local c = list and list[id]
	if not c then
		return nil, nil, nil
	end
	return c.name, c.title, c.color
end

return CinemaPlan
