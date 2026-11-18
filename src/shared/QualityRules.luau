--!strict
-- QualityRules: the device preset's rules (spec: Streaming and device presets; overhaul plan step 8, the
-- phone pass), pure so Lune tests them. QualityController applies them on the device.
-- * device: phone, tablet, pc or console from the input kinds and the screen (Telemetry's rule: a touch
--   screen with no keyboard is a tablet when its short side is 700 px or more, else a phone).
-- * auto: the preset a device starts on (Config.Presets.auto: phones low, the rest medium).
-- * frameStep: the first 5 s frame test moves one step down under lowBelow fps, or up over highAbove on a
--   device that may go up (a PC or console; touch devices never pick high on their own).
-- * watch: after the test, fps under watch.below for watch.seconds in a row steps down once more (never up),
--   so a phone that heats up and slows mid-fight drops to low without the player opening Settings.

local QualityRules = {}

export type Device = "phone" | "tablet" | "pc" | "console"
export type Watch = { slow: number }

function QualityRules.device(
	touch: boolean,
	keyboard: boolean,
	tenFoot: boolean,
	w: number,
	h: number
): Device
	if tenFoot then
		return "console"
	end
	if touch and not keyboard then
		return if math.min(w, h) >= 700 then "tablet" else "phone"
	end
	return "pc"
end

function QualityRules.auto(Presets: any, device: string): string
	return Presets.auto[device] or "medium"
end

local function step(Presets: any, name: string, by: number): string
	local idx = table.find(Presets.order, name) or 2
	return Presets.order[math.clamp(idx + by, 1, #Presets.order)]
end

-- How many robots the server sends one player in Enemy.Delta (perf pass 2026-11-18: everyone got the high
-- preset's 60 while a phone draws 20): the most that player's device can draw, plus `spare` so the robots
-- nearest the camera (not the hero) are still in the packet. `chosen` is the saved Graphics setting (0 Auto,
-- else Presets.order's index): a fixed preset draws its own count. On Auto it is the highest preset the
-- device can reach by itself (its start, one step up only where frameTest.upFor allows it); a device that
-- has not said what it is yet (nil) gets the highest preset's.
function QualityRules.enemiesFor(Presets: any, device: string?, chosen: number?, spare: number?): number
	local name = Presets.order[#Presets.order]
	if chosen and chosen >= 1 and Presets.order[chosen] then
		name = Presets.order[chosen]
	elseif device then
		name = QualityRules.auto(Presets, device)
		if Presets.frameTest.upFor[device] then
			name = step(Presets, name, 1)
		end
	end
	return Presets[name].enemiesDrawn + (spare or 0)
end

-- The preset after the first frame test (average fps over frameTest.seconds)
function QualityRules.frameStep(Presets: any, name: string, fps: number, device: string): string
	local F = Presets.frameTest
	if fps < F.lowBelow then
		return step(Presets, name, -1)
	elseif fps > F.highAbove and F.upFor[device] then
		return step(Presets, name, 1)
	end
	return name
end

function QualityRules.newWatch(): Watch
	return { slow = 0 }
end

-- One second of the running watch: the preset to use now (one step down after watch.seconds slow seconds)
function QualityRules.watchStep(Presets: any, w: Watch, name: string, fps: number, dt: number): string
	local W = Presets.watch
	if fps < W.below then
		w.slow += dt
	else
		w.slow = 0
	end
	if w.slow >= W.seconds then
		w.slow = 0
		return step(Presets, name, -1)
	end
	return name
end

-- The rows to draw when a preset draws fewer than are sent: the `limit` nearest to (cx, cz) by flat distance.
-- Rows already drawn (in `kept`) count as 15% nearer so a citizen at the cut does not blink on and off.
-- Returns `rows` itself when they all fit.
function QualityRules.nearest<T>(
	rows: { [number]: T & { x: number, z: number } },
	cx: number,
	cz: number,
	limit: number,
	kept: { [number]: any }?
): { [number]: T & { x: number, z: number } }
	local ids = {}
	for id in rows do
		table.insert(ids, id)
	end
	if #ids <= limit then
		return rows
	end
	local d: { [number]: number } = {}
	for _, id in ids do
		local r = rows[id]
		local dx, dz = r.x - cx, r.z - cz
		d[id] = (dx * dx + dz * dz) * (if kept and kept[id] then 0.85 * 0.85 else 1)
	end
	table.sort(ids, function(a, b)
		if d[a] ~= d[b] then
			return d[a] < d[b]
		end
		return a < b
	end)
	local out = {}
	for i = 1, math.max(0, limit) do
		out[ids[i]] = rows[ids[i]]
	end
	return out
end

return QualityRules
