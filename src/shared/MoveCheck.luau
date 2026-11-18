--!strict
-- MoveCheck: the server's speed and teleport check as pure rules (spec: Anti-exploit > Speed and teleport).
-- Position deltas must not exceed the style cap x 1.15. Instead of judging each 0.1 s sample alone (network
-- jitter delivers positions in bursts), each hero has a travel budget that refills at cap x 1.15 per second
-- and can bank `burstSeconds` of travel. Falling is free up to terminal speed. Dashes and other granted moves
-- add budget; fast travel, respawn and mission entry reset the check.
-- A strike needs fresh evidence: after one, the samples for `strikeGrace` seconds still fail and pull back,
-- but count no strike. Until MoveCorrect reaches the device (one lag spike can hold it up), every 10 Hz
-- sample still sees the same stale far position, which once stacked 3 strikes in 0.2 s and kicked.
-- Grants sit in their own pool (`extra`), spent first and gone `grantKeep` seconds after the last grant, so
-- old dashes never bank a later jump. A fail that is not a strike waits one sample before it pulls back
-- (`wait`): a dash's positions can reach the server before its CombatUse grant does.

local MoveCheck = {}

export type State = {
	x: number,
	y: number,
	z: number,
	t: number,
	budget: number,
	strikes: { number },
	quietUntil: number, -- no strike before this (the grace after the last one)
	extra: number, -- granted travel not spent yet (dashes, leaps, knocks)
	extraAt: number, -- when the last grant came
	missAt: number?, -- the first of the fails in a row (nil after a pass)
	expect: { x: number, y: number, z: number, from: number, untilT: number }?, -- a server move still landing
}

function MoveCheck.new(x: number, y: number, z: number, t: number): State
	return {
		x = x,
		y = y,
		z = z,
		t = t,
		budget = 0,
		strikes = {},
		quietUntil = -math.huge,
		extra = 0,
		extraAt = -math.huge,
		missAt = nil,
	}
end

-- A legal teleport (fast travel, respawn, mission pocket): accept the new spot
function MoveCheck.reset(state: State, x: number, y: number, z: number, t: number)
	state.x, state.y, state.z, state.t = x, y, z, t
	state.budget = 0
	state.extra = 0
	state.missAt = nil
end

-- The server just moved the hero to (x, y, z) (fast travel, respawn, a pocket). Until untilT a sample that
-- arrives there (or as far from there as the hero could legally have gone since) is that move landing late:
-- accepted, measured from, and the expectation is spent. reset leaves it alone (MoveGuard's grace resets
-- every sample, sometimes to the stale spot the device still reports).
function MoveCheck.expect(state: State, x: number, y: number, z: number, untilT: number)
	state.expect = { x = x, y = y, z = z, from = state.t, untilT = untilT }
end

-- A server-approved burst (Dash Strike's 30 studs): extra distance allowed right away, for `grantKeep` s.
-- now: when it was granted (defaults to the last sample's time)
function MoveCheck.grant(state: State, distance: number, now: number?)
	state.extra = math.max(0, state.extra) + math.max(0, distance)
	state.extraAt = now or state.t
end

-- Returns ok, strike, wait. On a fail the accepted position stays where it was; the caller pulls the hero
-- back unless `wait` (the first fail in a row that is no strike: the next sample measures again from the
-- last good spot, with any grant that has arrived since).
function MoveCheck.sample(
	state: State,
	x: number,
	y: number,
	z: number,
	t: number,
	cap: number,
	moveCfg: any,
	safetyCfg: any
): (boolean, boolean, boolean)
	local dt = t - state.t
	if dt <= 0 then
		return true, false, false
	end
	state.t = t
	local rate = cap * moveCfg.tolerance
	local bank = rate * safetyCfg.burstSeconds + safetyCfg.slack
	state.budget = math.min(math.max(state.budget, 0) + rate * dt, math.max(bank, state.budget))
	if t - state.extraAt > (safetyCfg.grantKeep or math.huge) then
		state.extra = 0 -- an unspent grant does not last
	end
	local avail = state.budget + state.extra

	local ex = state.expect
	if ex then
		if t > ex.untilT then
			state.expect = nil
		else
			local reach = safetyCfg.slack * 2 + rate * math.max(0, t - ex.from)
			local fx, fy, fz = x - ex.x, y - ex.y, z - ex.z
			if fx * fx + fy * fy + fz * fz <= reach * reach then
				local far = (x - state.x) ^ 2 + (z - state.z) ^ 2 > (safetyCfg.slack * 2) ^ 2
				if far then
					-- the move has landed on the device: measure from here on, and expect it no more
					state.expect = nil
					state.x, state.y, state.z = x, y, z
					state.budget = 0
					state.missAt = nil
					return true, false, false
				end
				state.expect = nil -- it landed on time: an ordinary sample from here on
			end
		end
	end

	local dx, dy, dz = x - state.x, y - state.y, z - state.z
	local up = math.max(0, dy)
	local freeFall = moveCfg.fall.terminal * moveCfg.tolerance * dt
	local extraDown = math.max(0, -dy - freeFall)
	local used = math.sqrt(dx * dx + dz * dz + up * up) + extraDown

	if used <= avail then
		local fromExtra = math.min(state.extra, used)
		state.extra -= fromExtra
		state.budget -= used - fromExtra
		state.x, state.y, state.z = x, y, z
		state.missAt = nil
		return true, false, false
	end
	local strike = used > avail * safetyCfg.strikeFactor + safetyCfg.slack * 4
	if strike then
		state.missAt = state.missAt or t
		if t < state.quietUntil then
			return false, false, false -- the same jump again before the pull-back landed: pulled back, no strike
		end
		state.quietUntil = t + (safetyCfg.strikeGrace or 0)
		return false, true, false
	end
	if state.missAt == nil then
		state.missAt = t
		return false, false, true -- the first miss: wait one sample (a grant may still be on its way)
	end
	return false, false, false
end

-- Count a strike; returns true when the strike rule says kick (3 in 10 minutes)
function MoveCheck.addStrike(state: State, now: number, safetyCfg: any): boolean
	table.insert(state.strikes, now)
	local cutoff = now - safetyCfg.strikes.window
	while #state.strikes > 0 and state.strikes[1] < cutoff do
		table.remove(state.strikes, 1)
	end
	return #state.strikes >= safetyCfg.strikes.kickAt
end

return MoveCheck
