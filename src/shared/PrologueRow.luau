--!strict
-- PrologueRow: the Ceremony prologue's rooftop row held whole while a prologue hops it (2026-11-18, the
-- onboarding check). Pure, so Lune checks it. The row's buildings are ordinary wreckable Downtown buildings,
-- and other players' fights could knock out the roof a new hero is about to land on; so while at least one
-- prologue is on the row's beats (Config.Story.opening.holdRow: the leap, the chase and the suit on the last
-- roof) its buildings are pinned through the same holder-counted rule the side quest roof goals use
-- (BuildingState.pin via BuildingService.pin), and each run lets go the moment it leaves them.
-- * ids(world, roofs): the buildings under a route's roof points (OpeningPlan's roofPoint: centre, top + 1.5)
-- * holds(Config, step): does this beat hold the row?
-- * sync(held, want, ids, pin): one run's hold: pin the ids when it starts holding, unpin them when it stops;
--   returns the run's new held list (nil when not holding)

local PrologueRow = {}

function PrologueRow.ids(world: any, roofs: { { number } }): { number }
	local out = {}
	for _, p in roofs do
		for _, b in world.buildings do
			if
				math.abs(b.x - p[1]) < 0.01
				and math.abs(b.z - p[3]) < 0.01
				and math.abs(b.top + 1.5 - p[2]) < 0.01
			then
				if not table.find(out, b.id) then
					table.insert(out, b.id)
				end
				break
			end
		end
	end
	return out
end

function PrologueRow.holds(Config: any, step: string?): boolean
	return step ~= nil and Config.Story.opening.holdRow[step] == true
end

function PrologueRow.sync(
	held: { number }?,
	want: boolean,
	ids: () -> { number },
	pin: (id: number, on: boolean) -> ()
): { number }?
	if want and not held then
		local list = ids()
		for _, id in list do
			pin(id, true)
		end
		return list
	elseif not want and held then
		for _, id in held do
			pin(id, false)
		end
		return nil
	end
	return held
end

return PrologueRow
