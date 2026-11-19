--!strict
-- FlowPlan: a character's first minutes as one state machine (fix-flow, nate's playtest 2026-11-19: "prologue runs
-- while im making my character ... The game should open with some sort of exposition that tells the player whats
-- going on. get to the customization, then prologue"). Pure, so Lune checks the order; CreatorService and
-- OpeningService ask it before they open anything.
--   intro     the exposition comic page (Config.Story.opening.intro), skippable; a brand-new character only, and
--             only once an account (the seen set), else straight to the creator
--   creator   the hero creator (mode "create"); the hero waits in the quiet "creator" scene
--   prologue  the Ceremony prologue, only after the creator's PLAY saved the hero (created 1)
--   menu      a returning account's new hero: the main menu's CREATE FIRST or PLAY THE PROLOGUE
--   play      the normal game (a returning hero: the PLAY menu over the city)
-- Events: "introDone" (watched or skipped, or the server's timeout), "created" (PLAY saved the hero), "started"
-- (the prologue's run began), "finished" (the prologue ended, rewards paid), "replay" (the Journal's REPLAY),
-- "createFirst" (the main menu's CREATE FIRST), "playPrologue" (its PLAY THE PROLOGUE).

local FlowPlan = {}

export type Facts = {
	created: number?, -- the character's created flag (1 once the creator saved it)
	opening: number?, -- story.opening (1 once the prologue is through)
	introSeen: boolean?, -- this account has seen the exposition
	returning: boolean?, -- another hero on this account did the prologue
	running: boolean?, -- a prologue run is on
	held: boolean?, -- that run waits for the main menu's pick
}

-- Where a character is in its first minutes, from its saved facts
function FlowPlan.phase(f: Facts): string
	if f.running then
		return if f.held then "menu" else "prologue"
	end
	if f.created ~= 1 then
		if f.opening == 1 then
			return "play" -- a hero made before the creator: it meets the creator once in "first" mode, out of the story
		end
		return if f.introSeen then "creator" else "intro"
	end
	if f.opening ~= 1 then
		return "prologue" -- made, not through the prologue yet: it (re)starts from its first beat
	end
	return "play"
end

-- The phase an event moves to from `phase` (nil: the event does nothing here)
local MOVES: { [string]: { [string]: string } } = {
	intro = { introDone = "creator" },
	creator = { created = "prologue" },
	prologue = { started = "prologue", finished = "play" },
	menu = { createFirst = "play", playPrologue = "prologue", finished = "play" },
	play = { replay = "intro" },
}
function FlowPlan.next(phase: string, event: string): string?
	local m = MOVES[phase]
	return m and m[event]
end

-- May the prologue start now? Never while the creator is open or the hero is unmade (the bug nate hit: a
-- prologue behind the creator), and not twice; a replay (the Journal, Dev) needs a made hero out of any scene.
function FlowPlan.prologueOk(f: Facts, scene: string?, replay: boolean?): boolean
	if f.running or scene == "creator" then
		return false
	end
	if f.created ~= 1 then
		return false
	end
	if replay then
		return scene == nil
	end
	return f.opening ~= 1
end

-- Does this character see the exposition before its creator?
function FlowPlan.introFirst(f: Facts): boolean
	return FlowPlan.phase(f) == "intro"
end

-- May the creator open in "create" mode now? A brand-new character, past its exposition, not in a prologue
function FlowPlan.creatorOk(f: Facts, introDone: boolean): boolean
	local p = FlowPlan.phase(f)
	return (p == "creator" or (p == "intro" and introDone)) and not f.running
end

return FlowPlan
