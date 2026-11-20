--!strict
-- LongGoals: the long goals a hero works toward, as progress rows (list-combat 2026-11-20, nate: a recurring
-- player base: "long goals on screen"). Pure, so Lune checks it; the Journal's GOALS tab draws the bars.
-- * rows(Config, view, lore): view is the client's profile view (ProfileSchema.clientView), lore the lore pages
--   by district (LorePlan.progress) or nil. Each row: { id, name, have, need, note }, have <= need.
-- Rows: the level cap then Legacy, HQ upgrades, mobility training (all five picks), the carried weapon's
-- Mastery, the lore pages, the world bosses (each beaten as an MVP) and the Rogues File when its data is in.

local WeaponRules = if script then require(script.Parent.WeaponRules) else (require :: any)("./WeaponRules")

local LongGoals = {}

export type Row = { id: string, name: string, have: number, need: number, note: string }

function LongGoals.rows(
	Config: any,
	view: any,
	lore: { any }?,
	rogues: { have: number, total: number }?
): { Row }
	local out: { Row } = {}
	local function add(id: string, name: string, have: number, need: number, note: string)
		table.insert(
			out,
			{ id = id, name = name, have = math.clamp(have, 0, need), need = need, note = note }
		)
	end
	local cap = Config.Stats.levelCap
	local level = tonumber(view.level) or 1
	if level < cap then
		add("level", "Level " .. cap, level, cap, "Legacy opens at the level cap")
	else
		add(
			"legacy",
			"Legacy",
			tonumber(view.legacy) or 0,
			10,
			"Each Legacy keeps your hero growing past the cap"
		)
	end
	local hqMax = #Config.Economy.hqLevels + 1
	local hq = (view.hq and tonumber(view.hq.level)) or 1
	add(
		"hq",
		"Safehouse HQ",
		hq,
		hqMax,
		if hq < hqMax then "Upgrade at your HQ for dummies, trophies, drones" else "HQ complete"
	)
	local ranks = 0
	for _, r in view.mobRanks or {} do
		ranks += tonumber(r) or 0
	end
	add(
		"mobility",
		"Mobility training",
		ranks,
		5 * #Config.Move.ranks.costs,
		"Train each pick on POWERS > MOBILITY"
	)
	local M = Config.Weapons.mastery
	local wid = tonumber(view.weapon) or 0
	local pts = WeaponRules.state(view, wid).mastery or 0
	local w = WeaponRules.get(Config, if wid == 0 then 1 else wid)
	add(
		"mastery",
		string.format("%s Mastery", if w and w.name then w.name else "Weapon"),
		math.floor(pts / M.perLevel),
		M.max,
		"Land hits and defeats with it: trails and skills open as it grows"
	)
	if lore then
		local have, total = 0, 0
		for _, d in lore do
			have += d.have
			total += d.total
		end
		if total > 0 then
			add("lore", "Lore pages", have, total, "Glowing books at the city's landmarks")
		end
	end
	local mvps = 0
	for _, t in view.bosses or {} do
		if (tonumber(t) or 0) >= 3 then
			mvps += 1
		end
	end
	add("bosses", "World boss MVPs", mvps, #Config.Boss.order, "Top the damage on each world boss once")
	if rogues and rogues.total > 0 then
		add("rogues", "Rogues File", rogues.have, rogues.total, "Beat every robot, fake and villain once")
	end
	return out
end

return LongGoals
