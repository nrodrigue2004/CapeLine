--!strict
-- GuardMath: block, breaker and interrupt (spec: Hero MMO features > Block, breaker and interrupt; H1), pure
-- so Lune tests it. G is Config.Guard.
-- * A hero's guard state: holding Block, when it started, the Guard bar (lazy refill), the stagger after a
--   shatter. setBlock starts and ends a block; guard reads the bar now.
-- * resolve: what one hit does to a hero: "hit" (not blocking, or from behind), "blocked" (70% less, no
--   knockback, Guard drains by the hit's share of health), "perfect" (started within 0.2 s: no damage, the
--   attacker reels, +Awakening), "shatter" (a breaker or Guard at 0: the full hit and a 1 s stagger).
--   PvP hits arrive already compressed (FlagService.damage), so they drain Guard at their compressed size.
-- * isBreaker / isInterrupt: which hits are which; interrupts cancel heavy wind-ups and charges for half
--   their cooldown.
-- * Robots: the kinds in G.robotBlocks block on a timer while they fight (robotStep) and shatter on breakers
--   (robotHit), like heroes. An entry with `warn` telegraphs first (the War-Frame); robotBreak ends a block
--   that a breaker shattered another way (the Warden's front guard).

local GuardMath = {}

export type State = {
	on: boolean,
	since: number, -- when the current block started
	guard: number, -- the bar at `at`
	at: number,
	offAt: number, -- when the last block ended (refill waits refillDelay after it)
	brokenUntil: number, -- staggered after a shatter: no blocking
}

export type Hit = {
	damage: number?, -- the incoming damage (after PvP compression)
	maxHealth: number?,
	coeff: number?,
	charged: number?, -- the charge level (0 to 1)
	grab: boolean?,
	breaker: boolean?, -- set by the caller for anything else that breaks (robot heavies, heavy throws)
	status: string?,
	status2: string?,
	front: boolean?, -- the hit came from the target's front half
}

export type Result = {
	outcome: string, -- "hit", "blocked", "perfect", "shatter"
	mult: number, -- damage multiplier
	noKnock: boolean, -- blocked and perfect hits push nobody
	stagger: number, -- seconds the target reels (shatter)
	attackerStagger: number, -- seconds the attacker reels (perfect)
	meter: number, -- Awakening the target gains (perfect)
	guardOut: boolean?, -- the shatter came from Guard running out
}

function GuardMath.new(G: any, now: number?): State
	local t = now or 0
	return {
		on = false,
		since = -math.huge,
		guard = G.block.guardMax,
		at = t,
		offAt = -math.huge,
		brokenUntil = 0,
	}
end

-- The Guard bar now: it refills `refill` a second once `refillDelay` has passed since the last block ended
function GuardMath.guard(G: any, st: State, now: number): number
	local B = G.block
	if st.on then
		return st.guard
	end
	local start = math.max(st.at, st.offAt + B.refillDelay)
	if now <= start then
		return st.guard
	end
	return math.min(B.guardMax, st.guard + (now - start) * B.refill)
end

local function settle(G: any, st: State, now: number)
	st.guard = GuardMath.guard(G, st, now)
	st.at = now
end

function GuardMath.staggered(st: State, now: number): boolean
	return now < st.brokenUntil
end

-- Start (on) or end a block. Returns whether it changed and why not ("broken", "low", "safe").
-- opts.safe: the hero stands in a safehouse (no block there)
function GuardMath.setBlock(
	G: any,
	st: State,
	on: boolean,
	now: number,
	opts: { safe: boolean? }?
): (boolean, string?)
	if on == st.on then
		return false, nil
	end
	settle(G, st, now)
	if on then
		if opts and opts.safe then
			return false, "safe"
		end
		if GuardMath.staggered(st, now) then
			return false, "broken"
		end
		if st.guard < G.block.minGuard then
			return false, "low"
		end
		st.on = true
		st.since = now
	else
		st.on = false
		st.offAt = now
	end
	return true, nil
end

-- Is a hit from (fromX, fromZ) in front of a target at (px, pz) facing (faceX, faceZ)? `arc` in degrees.
function GuardMath.front(
	arc: number,
	faceX: number,
	faceZ: number,
	px: number,
	pz: number,
	fromX: number,
	fromZ: number
): boolean
	local tx, tz = fromX - px, fromZ - pz
	local l = math.sqrt(tx * tx + tz * tz)
	local fl = math.sqrt(faceX * faceX + faceZ * faceZ)
	if l < 0.5 or fl < 1e-3 then
		return true -- on top of you, or no facing: it counts as the front
	end
	local dot = (faceX * tx + faceZ * tz) / (l * fl)
	return dot >= math.cos(math.rad(math.clamp(arc, 0, 360) / 2)) - 1e-9
end

function GuardMath.isBreaker(G: any, hit: Hit): boolean
	return hit.breaker == true
		or hit.grab == true
		or (hit.coeff or 0) >= G.breaker.coeff
		or (hit.charged or 0) >= G.breaker.fullCharge
end

function GuardMath.isInterrupt(G: any, hit: Hit): boolean
	local I = G.interrupt
	local c = hit.coeff or 0
	if c > 0 and c < I.coeff then
		return true
	end
	return (hit.status ~= nil and I.statuses[hit.status] == true)
		or (hit.status2 ~= nil and I.statuses[hit.status2] == true)
end

-- A heavy wind-up that an interrupt cancels: a cast with a wind-up at the heavy line
function GuardMath.heavyWindup(G: any, eff: any): boolean
	return eff ~= nil and (eff.cast or 0) > 0 and (eff.coeff or 0) >= G.breaker.coeff
end

-- An interrupt landing on someone winding up a heavy or charging cancels it
function GuardMath.interrupts(G: any, hit: Hit, winding: boolean): boolean
	return winding and GuardMath.isInterrupt(G, hit)
end

-- The cooldown an interrupted wind-up or charge costs (of its full cooldown)
function GuardMath.refund(G: any, full: number): number
	return full * G.interrupt.refund
end

local function result(outcome: string, mult: number): Result
	return {
		outcome = outcome,
		mult = mult,
		noKnock = outcome == "blocked" or outcome == "perfect",
		stagger = 0,
		attackerStagger = 0,
		meter = 0,
	}
end

-- What one hit does to a hero with guard state `st` (changes st: Guard drain, a shatter ends the block)
function GuardMath.resolve(G: any, st: State, hit: Hit, now: number): Result
	if not st.on or hit.front == false then
		return result("hit", 1)
	end
	settle(G, st, now)
	if now - st.since <= G.perfect.window and not hit.grab then
		local r = result("perfect", 0)
		r.attackerStagger = G.perfect.stagger
		r.meter = G.perfect.meter
		return r
	end
	local function shatter(guardOut: boolean): Result
		st.on = false
		st.offAt = now
		st.brokenUntil = now + G.breaker.stagger
		local r = result("shatter", 1)
		r.stagger = G.breaker.stagger
		r.guardOut = guardOut
		return r
	end
	if GuardMath.isBreaker(G, hit) then
		return shatter(false)
	end
	local drain = (hit.damage or 0) / math.max(1, hit.maxHealth or 1) * G.block.drainScale
	st.guard = math.max(0, st.guard - drain)
	if st.guard <= 0 then
		return shatter(true)
	end
	return result("blocked", 1 - G.block.cut)
end

---------------------------------------------------------------------------
-- Robots that block on a timer
---------------------------------------------------------------------------

export type RobotState = {
	nextAt: number,
	untilT: number,
	warnUntil: number, -- a telegraph (rb.warn) is on until then; 0 when none
}

function GuardMath.robotNew(rb: any, now: number): RobotState
	return { nextAt = now + rb.first, untilT = 0, warnUntil = 0 }
end

function GuardMath.robotBlocking(rs: RobotState, now: number): boolean
	return now < rs.untilT
end

-- Is the block's telegraph showing (rb.warn: the shine builds, the block is not up yet)?
function GuardMath.robotWarning(rs: RobotState, now: number): boolean
	return (rs.warnUntil or 0) > 0 and now < rs.warnUntil
end

-- One step: a fighting robot that is not winding up or reeling raises its block every `every` seconds for
-- `time`. busy: winding up, stunned or lifted (ends a block). Returns "warn", "start", "stop" or nil.
-- With rb.warn the block first telegraphs for `warn` seconds ("warn", not blocking yet), then goes up
-- ("start"); being busy or leaving the fight during the telegraph calls it off ("stop"). `every` counts from
-- the block going up either way.
function GuardMath.robotStep(rb: any, rs: RobotState, now: number, fighting: boolean, busy: boolean): string?
	if GuardMath.robotBlocking(rs, now) then
		if busy or not fighting then
			rs.untilT = 0
			rs.nextAt = math.max(rs.nextAt, now + rb.first)
			return "stop"
		end
		return nil
	end
	if rs.untilT > 0 and now >= rs.untilT then
		rs.untilT = 0
		return "stop"
	end
	if (rs.warnUntil or 0) > 0 then
		if busy or not fighting then
			rs.warnUntil = 0
			rs.nextAt = math.max(rs.nextAt, now + rb.first)
			return "stop"
		end
		if now < rs.warnUntil then
			return nil
		end
		rs.warnUntil = 0
		rs.untilT = now + rb.time
		rs.nextAt = now + rb.every
		return "start"
	end
	if not fighting then
		rs.nextAt = math.max(rs.nextAt, now + rb.first)
		return nil
	end
	if busy or now < rs.nextAt then
		return nil
	end
	if (rb.warn or 0) > 0 then
		rs.warnUntil = now + rb.warn
		rs.nextAt = now + rb.warn + rb.every
		return "warn"
	end
	rs.untilT = now + rb.time
	rs.nextAt = now + rb.every
	return "start"
end

-- A breaker shattered this robot's guard some other way (the Warden's front guard): any block or telegraph
-- ends and none comes back for rb.brokenFor. Returns true when a block or telegraph was showing.
function GuardMath.robotBreak(rb: any, rs: RobotState, now: number): boolean
	local was = GuardMath.robotBlocking(rs, now) or GuardMath.robotWarning(rs, now)
	rs.untilT = 0
	rs.warnUntil = 0
	rs.nextAt = now + rb.brokenFor
	return was
end

-- A hero's hit on a blocking robot: "hit", "blocked" (rb.cut less) or "shatter" (a breaker: the block ends,
-- the robot reels for G.breaker.stagger and cannot block again for rb.brokenFor)
function GuardMath.robotHit(G: any, rb: any, rs: RobotState, hit: Hit, now: number): (string, number)
	if not GuardMath.robotBlocking(rs, now) or hit.front == false then
		return "hit", 1
	end
	if GuardMath.isBreaker(G, hit) then
		rs.untilT = 0
		rs.nextAt = now + rb.brokenFor
		return "shatter", 1
	end
	return "blocked", 1 - rb.cut
end

return GuardMath
