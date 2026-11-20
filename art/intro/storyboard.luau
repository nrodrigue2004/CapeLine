-- storyboard.luau: the intro film's frames as data for art/blender/intro_storyboard.py (list-combat 2026-11-20).
-- Straight from the game's own rules: the world for the test seed (WorldMap), the stage near the first spawn
-- (Shared.IntroFilm.stage, as the server's OpeningService.introStage picks it), the film (IntroFilm.film) and the
-- camera (IntroFilm.camera). Frames: each shot's middle plus the cold open's big moments, with every actor that
-- shows (kind, feet, facing, pose), the caption and the sound word on screen then.
-- Run: lune run art/intro/storyboard.luau [spawn]   (writes art/export/intro/storyboard.json)
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Config = require("../../src/config")
local WorldMap = require("../../src/shared/WorldMap")
local IntroFilm = require("../../src/shared/IntroFilm")

local world = WorldMap.build(Config, 202647)
local which = tonumber(process.args[1] or "1") or 1
local sp = world.spawns[which]
local st = IntroFilm.stage(Config, world, sp.x, sp.z)
assert(st, "no stage near spawn " .. which)
local film = IntroFilm.film(Config, st)

local near = {}
for _, b in world.buildings do
	local d = math.sqrt((b.x - st.tower.x) ^ 2 + (b.z - st.tower.z) ^ 2)
	if d < 700 then
		table.insert(near, { b.x, b.z, b.sx, b.sz, b.top, b.base, b.id == st.tower.id and 1 or 0 })
	end
end

local times = {}
for i, s in film.shots do
	table.insert(times, { t = (s.t0 + s.t1) / 2, shot = i })
end
for _, t in { 0.6, 5.75, 8.1, 10.35, 11.4, 26.5, 42.4 } do
	table.insert(times, { t = t, shot = 0 })
end
table.sort(times, function(a, b)
	return a.t < b.t
end)

local frames = {}
for _, tt in times do
	local t = tt.t
	local shot, k = IntroFilm.shotAt(film, t)
	local idx = 0
	for i, s in film.shots do
		if s == shot then
			idx = i
		end
	end
	local cam, look = IntroFilm.camera(film, t)
	local actors = {}
	for _, tr in film.tracks do
		local p, yaw, clip, show = IntroFilm.at(tr, t)
		if show then
			table.insert(actors, { id = tr.id, kind = tr.kind, p = p, yaw = yaw, clip = clip or "" })
		end
	end
	local cap = ""
	for _, c in film.captions do
		if t >= c.t0 and t < c.t1 then
			cap = c.text .. (if c.draft then "  [DRAFT]" else "")
		end
	end
	local word = ""
	for _, w in film.words do
		if t >= w.t and t < w.t + 1.2 then
			word = w.text or ""
		end
	end
	local title = t >= 11 and t < 12.8
	local fx = {}
	for _, e in film.events do
		if t >= e.t and t < e.t + 1.2 and e.p then
			table.insert(fx, { kind = e.kind, p = e.p })
		end
	end
	table.insert(frames, {
		t = t,
		shot = idx,
		k = k,
		cam = cam,
		look = look,
		actors = actors,
		caption = cap,
		word = word,
		title = title,
		fx = fx,
		-- holes knocked in the tower so far
		holes = {
			entry = t >= 5.6,
			exit = t >= 8.0,
		},
	})
end

local out = {
	ground = Config.City.ground.y,
	tower = { st.tower.x, st.tower.z, st.tower.sx, st.tower.sz, st.tower.top, st.tower.base },
	r = st.r,
	f = st.f,
	buildings = near,
	frames = frames,
	events = film.events,
}
fs.writeDir("art/export/intro")
fs.writeFile("art/export/intro/storyboard.json", serde.encode("json", out))
print(string.format("storyboard: %d frames, tower %d (%d tall), %d buildings", #frames, st.tower.id, st.tower.top - st.tower.base, #near))
