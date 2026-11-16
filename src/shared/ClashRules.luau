--!strict
-- ClashRules: the collision freeze (spec: Clash moments "Two heavy attacks overlap within 0.15 s | Both
-- attackers freeze 0.3 s, shockwave radius 14 studs, camera push 8% | Server counts one per pair per 5 s").
-- Pure, so Lune tests it. note(cfg, book, hit) records a heavy hit and returns the other hero's hit when
-- the two overlap (different heroes, within `window` seconds and `reach` studs) and the pair is off its
-- cooldown.

local ClashRules = {}

export type Hit = { hero: number, x: number, y: number, z: number, t: number }
export type Book = { recent: { Hit }, pairs: { [string]: number } }

function ClashRules.book(): Book
	return { recent = {}, pairs = {} }
end

local function pairKey(a: number, b: number): string
	return if a < b then a .. ":" .. b else b .. ":" .. a
end

function ClashRules.note(cfg: any, book: Book, hit: Hit): Hit?
	local i = 1
	while i <= #book.recent do
		if hit.t - book.recent[i].t > cfg.window then
			table.remove(book.recent, i)
		else
			i += 1
		end
	end
	for k, other in book.recent do
		if other.hero ~= hit.hero then
			local dx, dy, dz = other.x - hit.x, other.y - hit.y, other.z - hit.z
			if dx * dx + dy * dy + dz * dz <= cfg.reach * cfg.reach then
				local key = pairKey(hit.hero, other.hero)
				if hit.t - (book.pairs[key] or -math.huge) >= cfg.pairCooldown then
					book.pairs[key] = hit.t
					table.remove(book.recent, k)
					return other
				end
			end
		end
	end
	-- one entry per hero is enough (its latest heavy hit)
	for k, other in book.recent do
		if other.hero == hit.hero then
			table.remove(book.recent, k)
			break
		end
	end
	table.insert(book.recent, hit)
	return nil
end

return ClashRules
