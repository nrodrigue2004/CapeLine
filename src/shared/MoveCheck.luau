--!strict
-- MoveCheck: the server's speed and teleport check as pure rules (spec: Anti-exploit > Speed and teleport).
-- Position deltas must not exceed the style cap x 1.15. Instead of judging each 0.1 s sample alone (network
-- jitter delivers positions in bursts), each hero has a travel budget that refills at cap x 1.15 per second
-- and can bank `burstSeconds` of travel. Falling is free up to terminal speed. Dashes and other granted moves
-- add budget; fast travel, respawn and mission entry reset the check.

local MoveCheck = {}

export type State = {
	x: number,
	y: number,
	z: number,
	t: number,
	budget: number,
	strikes: { number },
}

function MoveCheck.new(x: number, y: number, z: number, t: number): State
	return { x = x, y = y, z = z, t = t, budget = 0, strikes = {} }
end

-- A legal teleport (fast travel, respawn, mission pocket): accept the new spot
function MoveCheck.reset(state: State, x: number, y: number, z: number, t: number)
	state.x, state.y, state.z, state.t = x, y, z, t
	state.budget = 0
end

-- A server-approved burst (Dash Strike's 30 studs): extra distance allowed right away
function MoveCheck.grant(state: State, distance: number)
	state.budget += distance
end

-- Returns ok, strike. On a fail the accepted position stays where it was; the caller pulls the hero back.
function MoveCheck.sample(
	state: State,
	x: number,
	y: number,
	z: number,
	t: number,
	cap: number,
	moveCfg: any,
	safetyCfg: any
): (boolean, boolean)
	local dt = t - state.t
	if dt <= 0 then
		return true, false
	end
	state.t = t
	local rate = cap * moveCfg.tolerance
	local bank = rate * safetyCfg.burstSeconds + safetyCfg.slack
	state.budget = math.min(math.max(state.budget, 0) + rate * dt, math.max(bank, state.budget))

	local dx, dy, dz = x - state.x, y - state.y, z - state.z
	local up = math.max(0, dy)
	local freeFall = moveCfg.fall.terminal * moveCfg.tolerance * dt
	local extraDown = math.max(0, -dy - freeFall)
	local used = math.sqrt(dx * dx + dz * dz + up * up) + extraDown

	if used <= state.budget then
		state.budget -= used
		state.x, state.y, state.z = x, y, z
		return true, false
	end
	local strike = used > state.budget * safetyCfg.strikeFactor + safetyCfg.slack * 4
	return false, strike
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
