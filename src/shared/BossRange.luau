--!strict
-- BossRange: when a device shows the world boss's big banner and shared HP bar (fix-hud, nate after gaps7,
-- 2026-11-19: "Why is the boss bar above my screen if im not even near it?"). Pure, so Lune checks it; Config.Boss.hud.
-- (Its own module: devices never read BossMath, which live balance tunes on the server only.)

local BossRange = {}

-- fix-hud: does this device show the boss's big banner and HP bar? s: the Boss.State packet (state, num, x, z),
-- pos: the hero's {X, Z} (nil: not spawned), listed: on the fight's contribution list (a tier this fight),
-- was: it showed last time (a margin to leave, so the bar never flickers at the edge). Returns "bar" (near or
-- listed), "corner" (a banner or fight far away: the radar's timer and the marker only) or "none".
function BossRange.hudNear(
	Config: any,
	s: any,
	px: number?,
	pz: number?,
	listed: boolean,
	was: boolean
): string
	local B = Config.Boss
	local live = s.state == 1 or s.state == 2 or s.state == 3
	if not live then
		return "none"
	end
	if listed and s.state == 3 then
		return "bar"
	end
	if px == nil or pz == nil or type(s.x) ~= "number" or type(s.z) ~= "number" then
		return "corner"
	end
	local def
	for _, b in B.bosses do
		if b.num == s.num then
			def = b
		end
	end
	local r = math.max(B.hud.near, def and def.arenaRadius or 0) + (if was then B.hud.leave else 0)
	local dx, dz = px - s.x, pz - s.z
	return if dx * dx + dz * dz <= r * r then "bar" else "corner"
end

return BossRange
