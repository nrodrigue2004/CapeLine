--!strict
-- MoveRanks: mobility training (side-content, 2026-11-19; Config.Move.ranks and each pick's `ranks` rows). Pure, so
-- the device's MoveController, the server's MoveGuard and HeroService, and the Lune tests share one answer:
-- * config(base, pick, rank): this hero's own copy of Config.Move with the pick's ranks 1..rank applied in order
--   (each row's `set` writes numbers at dotted paths), cached per pick and rank. The device moves with it and the
--   server's speed caps (MoveMath.speedCap / guardCap) read the same copy, so a faster rank never trips a pull-back.
-- * rankOf / train: the saved ranks (one number per pick, Config.Move.mobilityOrder) and the training rule: the
--   next rank in order, opened at its level, paid in Credits (earned only; nothing here is sold).
-- * check(base): every rank of every pick keeps its own speeds inside its own caps (tests and the boot check).

local MoveMath = if script then require(script.Parent.MoveMath) else (require :: any)("./MoveMath")

local MoveRanks = {}

local function deepCopy(t: any): any
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in t do
		out[k] = deepCopy(v)
	end
	return out
end

local function setPath(cfg: any, path: string, value: any)
	local keys = string.split(path, ".")
	local t = cfg
	for i = 1, #keys - 1 do
		local nxt = t[keys[i]]
		if type(nxt) ~= "table" then
			error("MoveRanks: no table at " .. path)
		end
		t = nxt
	end
	t[keys[#keys]] = value
end

-- How many ranks a pick has (the rows), at most #base.ranks.costs
function MoveRanks.max(base: any, pick: string): number
	local m = base.mobility[pick]
	local rows = m and m.ranks
	return if rows then math.min(#rows, #base.ranks.costs) else 0
end

local cache: { [any]: { [string]: any } } = setmetatable({}, { __mode = "k" }) :: any

-- This hero's Config.Move: the base with `pick`'s ranks 1..rank applied (rank 0 is the base itself)
function MoveRanks.config(base: any, pick: string?, rank: number?): any
	local r = math.clamp(math.floor(rank or 0), 0, MoveRanks.max(base, pick or ""))
	if not pick or r <= 0 then
		return base
	end
	local byBase = cache[base]
	if not byBase then
		byBase = {}
		cache[base] = byBase
	end
	local key = pick .. "#" .. r
	local hit = byBase[key]
	if hit then
		return hit
	end
	local cfg = deepCopy(base)
	for i = 1, r do
		for _, row in base.mobility[pick].ranks[i].set do
			setPath(cfg, row[1], row[2])
		end
	end
	cfg.trained = { pick = pick, rank = r }
	byBase[key] = cfg
	return cfg
end

-- The saved rank of `pick` in a ranks list (one number per Config.Move.mobilityOrder entry)
function MoveRanks.rankOf(base: any, ranks: any, pick: string?): number
	local i = pick and table.find(base.mobilityOrder, pick)
	local v = if i and type(ranks) == "table" then ranks[i] else nil
	if type(v) ~= "number" then
		return 0
	end
	return math.clamp(math.floor(v), 0, MoveRanks.max(base, pick :: string))
end

-- The level and Credits rank n needs
function MoveRanks.needs(base: any, n: number): (number, number)
	return base.ranks.levels[n] or math.huge, base.ranks.costs[n] or math.huge
end

-- May this hero train `pick` one rank up? Returns ok, the reason ("pick", "max", "level", "credits"), the new
-- rank and its cost
function MoveRanks.canTrain(
	base: any,
	ranks: any,
	pick: string,
	level: number,
	credits: number
): (boolean, string?, number, number)
	if not base.mobility[pick] or not table.find(base.mobilityOrder, pick) then
		return false, "pick", 0, 0
	end
	local now = MoveRanks.rankOf(base, ranks, pick)
	local nextRank = now + 1
	if nextRank > MoveRanks.max(base, pick) then
		return false, "max", now, 0
	end
	local lv, cost = MoveRanks.needs(base, nextRank)
	if level < lv then
		return false, "level", nextRank, cost
	end
	if credits < cost then
		return false, "credits", nextRank, cost
	end
	return true, nil, nextRank, cost
end

-- Write a trained rank into the ranks list (a copy)
function MoveRanks.withRank(base: any, ranks: any, pick: string, rank: number): { number }
	local out = table.create(#base.mobilityOrder, 0)
	for i = 1, #base.mobilityOrder do
		local v = if type(ranks) == "table" then ranks[i] else nil
		out[i] = if type(v) == "number" then v else 0
	end
	local i = table.find(base.mobilityOrder, pick)
	if i then
		out[i] = rank
	end
	return out
end

-- The fastest a pick moves on its own at this rank (the number its server cap must cover), by feature
function MoveRanks.speeds(cfg: any, pick: string): { [string]: number }
	local m = cfg.mobility[pick]
	local out: { [string]: number } = {}
	out.runSprint = if cfg.sprint then cfg.sprint.speed else 0 -- everyone's sprint (move-2)
	if pick == "flight" then
		out.cruise = cfg.flight.cruise
		out.boost = math.max(cfg.flight.boost, m.up.boost)
	elseif pick == "speed" then
		out.sprint = m.sprint
		out.wallRun = m.wallRun
		out.hop = math.sqrt(m.sprint * m.sprint + m.hop.up * m.hop.up)
	elseif pick == "leap" then
		out.leap = MoveMath.superLeapSpeed(cfg)
		out.bounce = math.sqrt(m.bounce.up * m.bounce.up + m.bounce.out * m.bounce.out)
		if m.climb then -- move-2: the Hulk climb's bound, vault and kick
			local c = m.climb
			out.bound = math.sqrt(2 * c.gravity * c.bound) + c.press + c.side
			out.vault = math.sqrt(c.vault.up * c.vault.up + c.vault.forward * c.vault.forward)
			out.kick = math.sqrt(c.kick.up * c.kick.up + c.kick.out * c.kick.out)
		end
	elseif pick == "acrobat" then
		out.jump = math.sqrt(m.jump * m.jump + m.jumpForward * m.jumpForward)
		out.glide = m.glideForward
		out.wallRun = m.wallRun
		out.climb = m.climb
		if m.flip then -- move-2: the scurry and the flip
			out.crawlBurst = m.crawlBurst + 12 -- plus the hold onto the face
			out.flip = math.sqrt(m.flip.speed * m.flip.speed + m.flip.up * m.flip.up)
			out.sprint = m.run + cfg.sprint.speed - cfg.run.speed
		end
	elseif pick == "swing" then
		out.swing = m.maxSpeed
		out.release = m.release.cap
		out.zip = m.zip
	end
	return out
end

-- Every rank of every pick: rows complete, numbers only grow the pick, and every speed sits inside the server's
-- cap for that hero (speedCap with the pick, boosting). Returns problems (empty when fine).
function MoveRanks.check(base: any): { string }
	local bad = {}
	if #base.ranks.levels ~= #base.ranks.costs then
		table.insert(bad, "levels and costs differ in length")
	end
	for i = 2, #base.ranks.levels do
		if
			base.ranks.levels[i] <= base.ranks.levels[i - 1]
			or base.ranks.costs[i] <= base.ranks.costs[i - 1]
		then
			table.insert(bad, "levels and costs must rise")
		end
	end
	for _, pick in base.mobilityOrder do
		if MoveRanks.max(base, pick) ~= #base.ranks.costs then
			table.insert(bad, pick .. ": needs " .. #base.ranks.costs .. " ranks")
		end
		for r = 0, MoveRanks.max(base, pick) do
			local row = r > 0 and base.mobility[pick].ranks[r]
			if row and (type(row.name) ~= "string" or type(row.text) ~= "string" or #row.text > 44) then
				table.insert(bad, string.format("%s rank %d: name and text", pick, r))
			end
			local ok, err = pcall(MoveRanks.config, base, pick, r)
			if not ok then
				table.insert(bad, string.format("%s rank %d: %s", pick, r, tostring(err)))
				continue
			end
			local cfg = err
			local cap = MoveMath.speedCap(cfg, { [pick] = true }, true)
			for what, v in MoveRanks.speeds(cfg, pick) do
				if v > cap * cfg.tolerance then
					table.insert(
						bad,
						string.format("%s rank %d: %s %.1f over the cap %.1f", pick, r, what, v, cap)
					)
				end
			end
			if pick == "flight" then
				if
					cfg.flight.cruise > cfg.caps.cruise
					or math.max(cfg.flight.boost, cfg.mobility.flight.up.boost) > cfg.caps.flight
				then
					table.insert(bad, string.format("flight rank %d: over its own caps", r))
				end
			end
		end
	end
	return bad
end

return MoveRanks
