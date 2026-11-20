--!strict
-- PhaseRules: private ("phased") story content on the real map (missions lane, 2026-11-20; nate's playtest: "other
-- players shouldn't be able to interrupt ur story. Just you or you and friends in missions"). A mission run gets a
-- phase id (PhaseService on the server); its robots, combat targets and Sites pieces carry it, and only the heroes in
-- that phase see, hit or are hit by them. Everything here is plain data so Lune tests it.
--
-- EnemySim already had the prologue's solo rule (a robot and a hero meet only when their `solo` keys are equal, nil
-- matching nil). A phase rides on the same key: a phase's key is its id made negative, so it can never equal the
-- prologue's keys (a hero's own id, always positive). Unphased robots and heroes keep the nil key: nothing changes
-- for them.

local PhaseRules = {}

-- The sim key (EnemySim's `solo` field) of a phase id; nil for no phase
function PhaseRules.key(phase: number?): number?
	return if phase then -phase else nil
end

-- The phase id of a sim key (nil for the open world and for the prologue's hero-id keys)
function PhaseRules.phaseOf(key: number?): number?
	return if key and key < 0 then -key else nil
end

-- A hero's sim key: the prologue's (its own id), else its phase's, else nil (the open world)
function PhaseRules.heroKey(hero: { id: number, scene: string?, phase: number? }?): number?
	if not hero then
		return nil
	end
	if hero.scene == "opening" then
		return hero.id
	end
	return PhaseRules.key(hero.phase)
end

-- May something tagged with phase `tag` (nil: the open world) be seen, touched or used by a hero or device in
-- phase `mine` (nil: the open world)? Strict both ways: a phase's pieces are only its own members', and a member
-- is out of the open world's pieces until the run ends (nobody's story is interrupted, and nobody else's is).
function PhaseRules.sees(tag: number?, mine: number?): boolean
	return tag == mine
end

-- The Phase attribute value on a Player or a Sites model (attributes are any): a positive whole number, else nil
function PhaseRules.read(v: any): number?
	if type(v) == "number" and v > 0 and v % 1 == 0 then
		return v
	end
	return nil
end

return PhaseRules
