--!strict
-- RobotDamage: which shell pieces a robot has lost at a given health (nate, 2026-11-16: "as they take more
-- damage you see more internal robotic parts"). Every robot is a superhuman-looking android: a synthetic
-- shell (suit, skin, hair) over a metal endoskeleton. As health drops the shell breaks off piece by piece in
-- an order seeded by the robot's id, so every device shows the same robot losing the same pieces at the same
-- health (health rides Enemy.Delta), with no extra network data. Shell pieces break in clean panels with
-- sparks; there is never anything but metal, wires and glowing parts underneath (machines only, no gore).
-- Pure: no Roblox instances, so Lune tests it.

local Rng = if script then require(script.Parent.Rng) else (require :: any)("./Rng")

local RobotDamage = {}

export type Piece = { name: string, tier: number }

-- Break order for one robot: pieces sorted by tier, each nudged by up to `spread` tiers of seeded noise,
-- so low tiers (limbs, chest) tend to go first and the face late, but no two robots break the same way.
function RobotDamage.order(id: number, pieces: { Piece }, spread: number): { string }
	local rng = Rng.new(Rng.hash(id, 7151))
	local keyed = {}
	for i, p in pieces do
		table.insert(keyed, { name = p.name, key = p.tier + rng:next() * spread, i = i })
	end
	table.sort(keyed, function(a, b)
		if a.key == b.key then
			return a.i < b.i
		end
		return a.key < b.key
	end)
	local out = {}
	for _, k in keyed do
		table.insert(out, k.name)
	end
	return out
end

-- How many of `n` shell pieces are gone at this health (0 to 1). The last piece goes when `stripBy` of the
-- health is lost, so a robot near defeat is all endoskeleton. Never goes down as health falls.
function RobotDamage.count(health: number, n: number, stripBy: number): number
	local lost = 1 - math.clamp(health, 0, 1)
	return math.clamp(math.floor(lost / stripBy * n + 1e-6), 0, n)
end

-- The set of broken pieces at this health, from an order made by RobotDamage.order
function RobotDamage.broken(order: { string }, health: number, stripBy: number): { [string]: boolean }
	local out = {}
	for i = 1, RobotDamage.count(health, #order, stripBy) do
		out[order[i]] = true
	end
	return out
end

return RobotDamage
