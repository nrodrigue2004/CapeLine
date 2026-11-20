--!strict
-- MusicPlan: which music loop plays now (first-30, nate's playtest 2026-11-20: "Music should change according to
-- context"; Config.Audio.musicContext). Pure, so Lune checks every case. AudioController asks it twice a second
-- with what is going on and crossfades to the answer (Config.Audio.music.fade).
-- In order: the intro film's own pick; the creator or main menu (a calm loop); the prologue's beat (the Ceremony's
-- fanfare, the chase, the subway fight); a live boss nearby; a cutscene; an HQ; the deep; a mission (its tense loop,
-- or the fight loop while you fight in it); a fight in the city (a hit dealt or taken in the last `combatHold` s,
-- or a robot within `enemyRange` studs since a recent hit); else the patrol loop by day or night.

local MusicPlan = {}

export type Context = {
	override: string?, -- the intro film's own track
	menu: boolean?, -- the creator or the main menu is open
	opening: string?, -- the prologue's beat (OpeningPlan.STEPS), nil outside it
	boss: boolean?, -- a live boss within Config.Audio.music.bossRange
	scene: boolean?, -- a cutscene is playing (CinemaClient)
	hq: boolean?, -- inside an HQ
	underwater: boolean?,
	mission: boolean?, -- in a story mission
	hitAgo: number?, -- seconds since this hero last dealt or took a hit
	enemyNear: number?, -- studs to the nearest robot drawn (nil: none)
	night: boolean?,
}

-- Fighting now: a hit in the last `combatHold` s, or a robot close since a hit in the last `combatNear` s
function MusicPlan.fighting(Config: any, ctx: Context): boolean
	local C = Config.Audio.musicContext
	local ago = ctx.hitAgo
	if ago == nil then
		return false
	end
	if ago <= C.combatHold then
		return true
	end
	return ctx.enemyNear ~= nil and ctx.enemyNear <= C.enemyRange and ago <= C.combatNear
end

-- The loop for this moment (a name in Config.Audio.music)
function MusicPlan.pick(Config: any, ctx: Context): string
	local C = Config.Audio.musicContext
	if ctx.override then
		return ctx.override
	end
	if ctx.menu then
		return C.menu
	end
	if ctx.opening then
		local o = C.opening[ctx.opening]
		if o then
			return o
		end
	end
	if ctx.boss then
		return "boss"
	end
	if ctx.scene then
		return C.scene
	end
	if ctx.hq then
		return C.hq
	end
	if ctx.underwater then
		return if MusicPlan.fighting(Config, ctx) then C.combat else C.deep
	end
	if ctx.mission then
		return if MusicPlan.fighting(Config, ctx) then C.combat else C.mission
	end
	if MusicPlan.fighting(Config, ctx) then
		return C.combat
	end
	return if ctx.night then "patrolNight" else "patrolDay"
end

return MusicPlan
