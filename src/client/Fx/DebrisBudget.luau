-- DebrisBudget: one count of loose effect parts (robot bolts, falling building chunks, flying rubble) so
-- every effect shares the device preset's debris limit (spec: Streaming and device presets "debris").
-- take(n) returns how many may be made now; each one made is handed back with give after it is gone.

local QualityController = require(script.Parent.Parent.Controllers.QualityController)

local DebrisBudget = {}

local live = 0

function DebrisBudget.take(n: number): number
	local granted = math.max(0, math.min(n, QualityController.preset.debris - live))
	live += granted
	return granted
end

function DebrisBudget.give(n: number)
	live = math.max(0, live - n)
end

-- Take one part's worth and hand it back after `life` seconds
function DebrisBudget.lease(n: number, life: number): number
	local granted = DebrisBudget.take(n)
	if granted > 0 then
		task.delay(life, DebrisBudget.give, granted)
	end
	return granted
end

function DebrisBudget.live(): number
	return live
end

return DebrisBudget
