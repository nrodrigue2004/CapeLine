--!strict
-- BalanceMerge: lays a live tuning key (the Balance_v<N> DataStore's value, gap check G11, WP8) over the
-- bundled Config, number by number, and only where Config.Balance allows it. Pure: no Roblox types, so Lune
-- tests every rule. BalanceService runs it once at boot.
-- * A key's value is a table shaped like Config ({ Economy = { scale = { credits = 1.2 } } }), dotted paths
--   ({ ["Economy.scale.credits"] = 1.2 }) or both. Arrays count from 1 ("Boss.schedule.every.1").
--   "_rev" (a whole number, the edit's own count) is kept as the revision; any other key starting "_" is a
--   note and skipped.
-- * Every number lands only on a path in rules.keys that already holds a finite number in the bundled
--   Config, and only inside that path's range. Anything else is refused with a reason and changes nothing:
--   unknown (not listed, or not in Config), locked (a locked section or word), type (not a number, or the
--   bundled value is not one), nan, inf, range, int (not a whole number), duplicate (the same path twice),
--   order (a rules.pairs pair would read first > second), too_many / too_deep (the whole key is refused).
-- * merge(config, patch, rules) never changes config: it returns a view (config with the applied numbers,
--   copying only the tables on their paths), the applied list ({ path, old, new }, sorted by path) and the
--   rejected list ({ path, why }). write(config, applied) then sets them in place (the server's live
--   Config, before the other services read it).

local BalanceMerge = {}

export type Rule = { path: string, min: number?, max: number?, rel: { number }?, int: boolean? }
export type Applied = { path: string, old: number, new: number }
export type Rejected = { path: string, why: string }
export type Result = {
	view: { [any]: any },
	applied: { Applied },
	rejected: { Rejected },
	rev: number?,
}

local function split(path: string): { string }
	local out = {}
	for seg in string.gmatch(path, "[^%.]+") do
		table.insert(out, seg)
	end
	return out
end
BalanceMerge.split = split

-- The child of t under a path segment: a string key, else the number it spells (array slots). Returns the
-- child and the real key, or nil.
local function child(t: any, seg: string): (any, any)
	if type(t) ~= "table" then
		return nil, nil
	end
	local v = t[seg]
	if v ~= nil then
		return v, seg
	end
	local n = tonumber(seg)
	if n ~= nil then
		v = t[n]
		if v ~= nil then
			return v, n
		end
	end
	return nil, nil
end

-- The value at a dotted path in t (nil if any step is missing)
function BalanceMerge.get(t: any, path: string): any
	local node = t
	for _, seg in split(path) do
		node = child(node, seg)
		if node == nil then
			return nil
		end
	end
	return node
end

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- True when a path is never tunable live: its section or any of its segments is in rules.locked
function BalanceMerge.locked(rules: any, path: string): boolean
	local L = rules.locked or {}
	local segs = split(path)
	if segs[1] and table.find(L.sections or {}, segs[1]) then
		return true
	end
	for _, seg in segs do
		for _, word in L.words or {} do
			if string.lower(seg) == string.lower(word) then
				return true
			end
		end
	end
	return false
end

-- The first rule whose pattern matches a path ("*" matches any one segment), or nil
function BalanceMerge.match(rules: any, path: string): Rule?
	local segs = split(path)
	for _, rule in rules.keys or {} do
		local pat = split(rule.path)
		if #pat == #segs then
			local ok = true
			for i, p in pat do
				if p ~= "*" and p ~= segs[i] then
					ok = false
					break
				end
			end
			if ok then
				return rule
			end
		end
	end
	return nil
end

-- The allowed range of a rule at a bundled value: lo, hi
function BalanceMerge.range(rule: Rule, bundled: number): (number, number)
	if rule.rel then
		local a, b = bundled * rule.rel[1], bundled * rule.rel[2]
		return math.min(a, b), math.max(a, b)
	end
	return rule.min or -math.huge, rule.max or math.huge
end

-- The patch as sorted { path, value } leaves (nested tables and dotted keys alike). Returns the leaves, the
-- revision (or nil) and an error code when the whole patch is refused.
function BalanceMerge.flatten(patch: any, rules: any): ({ { path: string, value: any } }, number?, string?)
	local leaves: { { path: string, value: any } } = {}
	local rev: number? = nil
	local maxDepth = rules.maxDepth or 8
	local maxEntries = rules.maxEntries or 200
	local deep = false
	local function walk(node: any, prefix: string, depth: number)
		if depth > maxDepth then
			deep = true
			return
		end
		for k, v in node do
			if #leaves > maxEntries then
				return
			end
			local key = tostring(k)
			if prefix == "" and string.sub(key, 1, 1) == "_" then
				if key == "_rev" and finite(v) and v >= 0 and math.floor(v) == v then
					rev = v
				end
				continue
			end
			local path = if prefix == "" then key else prefix .. "." .. key
			if type(v) == "table" then
				walk(v, path, depth + 1)
			else
				table.insert(leaves, { path = path, value = v })
			end
		end
	end
	if type(patch) ~= "table" then
		return {}, nil, if patch == nil then nil else "type"
	end
	walk(patch, "", 1)
	if deep then
		return {}, rev, "too_deep"
	end
	if #leaves > maxEntries then
		return {}, rev, "too_many"
	end
	table.sort(leaves, function(a, b)
		return a.path < b.path
	end)
	return leaves, rev, nil
end

-- One leaf's verdict: nil (fine) or the reason it is refused
local function verdict(config: any, rules: any, path: string, value: any): string?
	if BalanceMerge.locked(rules, path) then
		return "locked"
	end
	local found = BalanceMerge.match(rules, path)
	if not found then
		return "unknown"
	end
	local rule = found :: Rule
	local bundled = BalanceMerge.get(config, path)
	if bundled == nil then
		return "unknown"
	end
	if type(value) ~= "number" or not finite(bundled) then
		return "type"
	end
	if value ~= value then
		return "nan"
	end
	if value == math.huge or value == -math.huge then
		return "inf"
	end
	if rule.int and math.floor(value) ~= value then
		return "int"
	end
	local lo, hi = BalanceMerge.range(rule, bundled)
	if value < lo or value > hi then
		return "range"
	end
	return nil
end

-- The canonical path (the way the leaf resolves in Config) so "every.1" from an array and "every.1" from a
-- dotted key are the same path
local function canon(path: string): string
	return table.concat(split(path), ".")
end

-- Merge a patch over config under rules (Config.Balance). config is never changed.
function BalanceMerge.merge(config: any, patch: any, rules: any): Result
	local leaves, rev, whole = BalanceMerge.flatten(patch, rules)
	local rejected: { Rejected } = {}
	if whole then
		table.insert(rejected, { path = "*", why = whole })
		return { view = config, applied = {}, rejected = rejected, rev = rev }
	end
	local want: { [string]: number } = {}
	local order: { string } = {}
	for _, leaf in leaves do
		local path = canon(leaf.path)
		local why = verdict(config, rules, path, leaf.value)
		if why == nil and want[path] ~= nil then
			why = "duplicate"
		end
		if why then
			table.insert(rejected, { path = path, why = why })
		else
			want[path] = leaf.value
			table.insert(order, path)
		end
	end
	-- pairs that must stay in order (shortest <= longest)
	for _, pair in rules.pairs or {} do
		local a, b = pair[1], pair[2]
		if want[a] ~= nil or want[b] ~= nil then
			local va = if want[a] ~= nil then want[a] else BalanceMerge.get(config, a)
			local vb = if want[b] ~= nil then want[b] else BalanceMerge.get(config, b)
			if type(va) == "number" and type(vb) == "number" and va > vb then
				for _, p in { a, b } do
					if want[p] ~= nil then
						want[p] = nil
						table.insert(rejected, { path = p, why = "order" })
					end
				end
			end
		end
	end
	local applied: { Applied } = {}
	for _, path in order do
		local v = want[path]
		if v ~= nil then
			table.insert(applied, { path = path, old = BalanceMerge.get(config, path), new = v })
		end
	end
	table.sort(rejected, function(x, y)
		return x.path < y.path
	end)
	if #applied == 0 then
		return { view = config, applied = applied, rejected = rejected, rev = rev }
	end
	-- the view: copy only the tables along each applied path
	local copied: { [any]: boolean } = {}
	local view = table.clone(config)
	copied[view] = true
	for _, a in applied do
		local segs = split(a.path)
		local node = view
		for i = 1, #segs - 1 do
			local nxt, key = child(node, segs[i])
			if not copied[nxt] then
				nxt = table.clone(nxt)
				copied[nxt] = true
				node[key] = nxt
			end
			node = nxt
		end
		local _, key = child(node, segs[#segs])
		node[key] = a.new
	end
	return { view = view, applied = applied, rejected = rejected, rev = rev }
end

-- Set the applied numbers in place (the server's live Config). Returns how many were set.
function BalanceMerge.write(config: any, applied: { Applied }): number
	local n = 0
	for _, a in applied do
		local segs = split(a.path)
		local node = config
		for i = 1, #segs - 1 do
			node = child(node, segs[i])
			if type(node) ~= "table" then
				break
			end
		end
		if type(node) == "table" then
			local cur, key = child(node, segs[#segs])
			if type(cur) == "number" then
				node[key] = a.new
				n += 1
			end
		end
	end
	return n
end

-- The report lines (the boot log and the Dev panel's print): one per applied and refused number
function BalanceMerge.lines(result: Result): { string }
	local out = {}
	for _, a in result.applied do
		table.insert(out, string.format("  set %s: %s -> %s", a.path, tostring(a.old), tostring(a.new)))
	end
	for _, r in result.rejected do
		table.insert(out, string.format("  refused %s (%s)", r.path, r.why))
	end
	return out
end

return BalanceMerge
