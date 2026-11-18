--!strict
-- MissionRules: small pure rules for the story runs (MissionService's pockets, OpeningService's prologue), so
-- the Lune tests check the decisions the services make (2026-11-18 story fixes).
--   advance: a run moves to its next stage only when it has tracks and every one is done, never while a task
--     force's comic panel is up (between legs the run has no tracks: the old check read that as "all done"
--     and ran every leg, paying each one, in about half a second).
--   afterSpawn: a robot step on a full server waits for a free robot slot and tries again (a boss or a chase
--     never skips); a defeat step fights the robots that came; a switched-off type lets the story move on.
--   canJoin: who a mission may pull in with its leader (loaded, standing, free).
--   partyLevels: the levels the sidekick and mentor pay reads (only members still in the run).
--   markSeen: a camera beat counts as seen when the run moves off it (never as it starts).

local MissionRules = {}

-- Does the run start its next stage now? (tracks: the stage's tracks by side; panel: a task force panel is up)
function MissionRules.advance(tracks: { [string]: any }, panel: boolean?): boolean
	if panel or next(tracks) == nil then
		return false -- the fade in, or the panel between legs: nothing has run yet
	end
	for _, t in tracks do
		if not t.done then
			return false
		end
	end
	return true
end

-- After a robot step's spawn: "go" (got robots: fight them), "skip" (none came and the type is switched
-- off: the story moves on) or "wait" (the server is full: try again on the next tick)
function MissionRules.afterSpawn(got: number, enabled: boolean): string
	if got > 0 then
		return "go"
	end
	return if enabled then "wait" else "skip"
end

-- Can this hero come into a mission with its leader? Downed heroes are not alive; inRun, inCombat and trip
-- are the server's own answers (another run, a fight in the last few seconds, a beacon trip).
function MissionRules.canJoin(hero: any, inRun: boolean, inCombat: boolean, trip: boolean): boolean
	return hero ~= nil
		and hero.loaded == true
		and hero.alive == true
		and hero.downed ~= true
		and hero.scene == nil
		and not hero.traveling
		and not inRun
		and not inCombat
		and not trip
end

-- The levels of the members still in the run (levels keeps a member who left, for a rejoin's pay)
function MissionRules.partyLevels(members: { any }, levels: { [any]: number }): { number }
	local out = {}
	for _, p in members do
		local l = levels[p]
		if l then
			table.insert(out, l)
		end
	end
	return out
end

-- Mark the beat `from` seen as the prologue goes to `to`? Only a camera beat, only when it really ends (a
-- beat re-entered at its own start is not seen yet), and never while a returning account's menu holds it.
function MissionRules.markSeen(from: string, to: string, cut: boolean, hold: boolean): boolean
	return cut and not hold and from ~= to
end

return MissionRules
