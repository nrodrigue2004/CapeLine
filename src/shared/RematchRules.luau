--!strict
-- RematchRules: the REMATCH ping after a PvP defeat (spec: Social > Rivalry, "Defeated players see the
-- attacker's name plate and a Rematch ping; no trash-talk text"; gap check G8). Pure, so Lune tests it;
-- FlagService runs it (the PvpRematch remote).
-- * defeat: a PvP defeat gives the loser one ping at that winner for Config.Pvp.rematch.offer seconds.
-- * ask: the loser taps REMATCH. It needs the loser's PvP flag on, the winner still here, and the pair's gap
--   since its last ping; it spends the offer, and the winner has `answer` seconds to accept.
-- * accept: the winner taps ACCEPT on "X wants a rematch". Both must be flagged right then: that is the whole
--   feature (both are told and see each other's spot); nobody is moved, nothing is forced.
-- Every message is a fixed line with a hero name from the safe name system: no free text ever.

local RematchRules = {}

export type State = {
	offers: { [number]: { winner: number, untilT: number } }, -- loser id -> the ping it may send
	asks: { [number]: { [number]: number } }, -- winner id -> loser id -> answer by (os.clock)
	pairs: { [string]: number }, -- "low:high" ids -> when that pair last pinged
}

function RematchRules.new(): State
	return { offers = {}, asks = {}, pairs = {} }
end

local function pairKey(a: number, b: number): string
	return if a < b then a .. ":" .. b else b .. ":" .. a
end

-- A PvP defeat: the loser may ping this winner until `offer` seconds from now (a newer defeat replaces it)
function RematchRules.defeat(R: any, st: State, loserId: number, winnerId: number, now: number)
	if loserId == winnerId then
		return
	end
	st.offers[loserId] = { winner = winnerId, untilT = now + R.offer }
end

-- The loser's REMATCH tap. facts: flagged (the loser's PvP flag is on), here (the winner is on this server).
-- Returns the winner's id, or nil and why: "none" (no offer, or it ran out), "flag", "gone", "wait".
function RematchRules.ask(
	R: any,
	st: State,
	loserId: number,
	now: number,
	facts: { flagged: boolean, here: boolean }
): (number?, string?)
	local o = st.offers[loserId]
	if not o or now > o.untilT then
		st.offers[loserId] = nil
		return nil, "none"
	end
	if not facts.here then
		st.offers[loserId] = nil
		return nil, "gone"
	end
	if not facts.flagged then
		return nil, "flag" -- the offer stays: switch PvP on and tap again
	end
	local key = pairKey(loserId, o.winner)
	local last = st.pairs[key]
	if last and now - last < R.pairGap then
		return nil, "wait"
	end
	st.offers[loserId] = nil
	st.pairs[key] = now
	local mine = st.asks[o.winner]
	if not mine then
		mine = {}
		st.asks[o.winner] = mine
	end
	mine[loserId] = now + R.answer
	return o.winner, nil
end

-- The winner's ACCEPT on a loser's ping. bothFlagged: both PvP flags are on right now.
-- Returns true, or false and why: "late" (no ping from them, or it ran out), "flag".
function RematchRules.accept(
	_R: any,
	st: State,
	winnerId: number,
	loserId: number,
	now: number,
	bothFlagged: boolean
): (boolean, string?)
	local mine = st.asks[winnerId]
	local by = mine and mine[loserId]
	if not by or now > by then
		if mine then
			mine[loserId] = nil
		end
		return false, "late"
	end
	if not bothFlagged then
		return false, "flag" -- the ping stays until it runs out: flag up and tap again
	end
	(mine :: any)[loserId] = nil
	return true, nil
end

-- The winner's NO (or the card ran out): the ping is gone
function RematchRules.decline(st: State, winnerId: number, loserId: number)
	local mine = st.asks[winnerId]
	if mine then
		mine[loserId] = nil
	end
end

-- A hero left: its offers and pings go both ways; old pair gaps are dropped
function RematchRules.forget(R: any, st: State, id: number, now: number)
	st.offers[id] = nil
	st.asks[id] = nil
	for loser, o in st.offers do
		if o.winner == id then
			st.offers[loser] = nil
		end
	end
	for _, mine in st.asks do
		mine[id] = nil
	end
	for key, at in st.pairs do
		if now - at >= R.pairGap then
			st.pairs[key] = nil
		end
	end
end

return RematchRules
