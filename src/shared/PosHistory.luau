--!strict
-- PosHistory: each hero's server position at 30 Hz for the last second, so hit checks can rewind the
-- attacker by up to 150 ms of lag (spec: Hit resolution).

local PosHistory = {}

export type History = { times: { number }, xs: { number }, ys: { number }, zs: { number }, keep: number }

function PosHistory.new(keep: number): History
	return { times = {}, xs = {}, ys = {}, zs = {}, keep = keep }
end

function PosHistory.push(h: History, t: number, x: number, y: number, z: number)
	table.insert(h.times, t)
	table.insert(h.xs, x)
	table.insert(h.ys, y)
	table.insert(h.zs, z)
	local cutoff = t - h.keep
	while #h.times > 2 and h.times[1] < cutoff do
		table.remove(h.times, 1)
		table.remove(h.xs, 1)
		table.remove(h.ys, 1)
		table.remove(h.zs, 1)
	end
end

-- Position at time t, interpolated; clamps to the oldest and newest samples
function PosHistory.at(h: History, t: number): (number?, number?, number?)
	local n = #h.times
	if n == 0 then
		return nil, nil, nil
	end
	if t >= h.times[n] then
		return h.xs[n], h.ys[n], h.zs[n]
	end
	if t <= h.times[1] then
		return h.xs[1], h.ys[1], h.zs[1]
	end
	for i = n - 1, 1, -1 do
		local t0 = h.times[i]
		if t0 <= t then
			local t1 = h.times[i + 1]
			local a = if t1 > t0 then (t - t0) / (t1 - t0) else 0
			return h.xs[i] + (h.xs[i + 1] - h.xs[i]) * a,
				h.ys[i] + (h.ys[i + 1] - h.ys[i]) * a,
				h.zs[i] + (h.zs[i + 1] - h.zs[i]) * a
		end
	end
	return h.xs[1], h.ys[1], h.zs[1]
end

-- Rewound position: `latency` seconds ago, never more than rewindMax
function PosHistory.rewind(
	h: History,
	now: number,
	latency: number,
	rewindMax: number
): (number?, number?, number?)
	return PosHistory.at(h, now - math.clamp(latency, 0, rewindMax))
end

return PosHistory
