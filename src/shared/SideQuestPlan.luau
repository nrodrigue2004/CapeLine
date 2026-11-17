--!strict
-- SideQuestPlan: the side quest framework's rules (nate's lore, build plan step 10). Pure, so Lune checks the
-- chains, the unlocks, the save, the pay and co-op; SideQuestService builds the steps in the world.
-- * Chains (Config.SideQuests.chains) run 5 to 10 steps; each step has a goal per side (one shared table is
--   one goal for both), the last is the mini villain finale. validate() checks every chain the way the
--   missions are checked: kinds, both sides' goals and texts, unlocks reachable, rewards in range, finale,
--   lines and scenes, no free text.
-- * The save (a character's `sq`): at[chain id] = the current step (absent: not started or finished), done =
--   a bitset by chain bit, retired / owed / settled for the arcs before step 10; story.pinned is the chain
--   bit tracked (0 the story). accept starts and pins, abandon unpins (the chain waits on hold at its step:
--   steps finished are kept and the half-done one restarts), resume pins it again, advance moves on.
-- * Co-op: a group is one step of one chain shared by squadmates. Each side present has its own goal (or one
--   "both" goal for a shared step) and the group moves on when every side present has finished.
-- * Pay: a step pays a share of a contract at the hero's level (Config.SideQuests.pay); the chain's end its
--   reward share and one cosmetic or title.

local ProfileSchema = if script
	then require(script.Parent.ProfileSchema)
	else (require :: any)("./ProfileSchema")
local GearMath = if script then require(script.Parent.GearMath) else (require :: any)("./GearMath")
local ContractPlan = if script
	then require(script.Parent.ContractPlan)
	else (require :: any)("./ContractPlan")
local StoryPlan = if script then require(script.Parent.StoryPlan) else (require :: any)("./StoryPlan")

local Bits = ProfileSchema.Bits

local SideQuestPlan = {}

local function Q(Config: any): any
	return Config.SideQuests
end

---------------------------------------------------------------------------
-- Steps and goals
---------------------------------------------------------------------------

-- The step kinds: the fields each needs and how much progress it takes
local function sum(rows: any): number
	local n = 0
	for _, r in rows or {} do
		n += r[2] or 0
	end
	return n
end

SideQuestPlan.KINDS = {
	talk = {
		fields = {},
		need = function(_g)
			return 1
		end,
	},
	fight = {
		fields = { "squads" },
		need = function(g)
			return sum(g.squads)
		end,
	},
	incident = {
		fields = { "count" },
		need = function(g)
			return g.count
		end,
	},
	chase = {
		fields = { "enemy", "hops", "speed" },
		need = function(_g)
			return 1
		end,
	},
	deliver = {
		fields = { "range" },
		need = function(_g)
			return 1
		end,
	},
	fetch = {
		fields = { "range" },
		need = function(g)
			return g.count or 1
		end,
	},
	hold = {
		fields = { "seconds", "radius" },
		need = function(g)
			return g.seconds
		end,
	},
	escort = {
		fields = { "goal", "speed", "near" },
		need = function(g)
			return g.goal
		end,
	},
	carry = {
		fields = { "range" },
		need = function(_g)
			return 1
		end,
	},
	race = {
		fields = { "checkpoints", "gap", "time" },
		need = function(g)
			return g.checkpoints
		end,
	},
	reach = {
		fields = { "high", "range" },
		need = function(_g)
			return 1
		end,
	},
	find = {
		fields = { "range" },
		need = function(_g)
			return 1
		end,
	},
	photo = {
		fields = { "count", "range" },
		need = function(g)
			return g.count
		end,
	},
	beacon = {
		fields = { "seconds" },
		need = function(g)
			return g.seconds
		end,
	},
	pocket = {
		fields = { "layout", "minutes", "steps" },
		need = function(_g)
			return 1
		end,
	},
	finale = {
		fields = { "enemy", "hpMult" },
		need = function(_g)
			return 1
		end,
	},
} :: { [string]: { fields: { string }, need: (any) -> number } }

-- The step kinds a pocket run may use (MissionService's own; no camera beats or fakes)
SideQuestPlan.POCKET_KINDS = { defeat = true, boss = true, hold = true, reach = true, ["break"] = true }

-- A side's goal on a step ("same" on the villain's side is the hero's goal, shared)
function SideQuestPlan.goal(step: any, side: string): any?
	local key = if side == "villain" then "villain" else "hero"
	local g = step[key]
	if g == "same" then
		g = step.hero
	end
	return if type(g) == "table" then g else nil
end

-- Is the step one goal for both sides?
function SideQuestPlan.shared(step: any): boolean
	return step.villain == "same" or (step.hero ~= nil and step.hero == step.villain)
end

-- The co-op key a side works under on a step: "both" for a shared goal, else the side
function SideQuestPlan.keyFor(step: any, side: string): string
	if SideQuestPlan.shared(step) then
		return "both"
	end
	return if side == "villain" then "villain" else "hero"
end

-- A goal's text for a side
function SideQuestPlan.text(goal: any, side: string): string
	if side == "villain" and type(goal.villainText) == "string" then
		return goal.villainText
	end
	return goal.text or ""
end

function SideQuestPlan.need(goal: any): number
	local k = SideQuestPlan.KINDS[goal.kind]
	return if k then math.max(1, k.need(goal) or 1) else 1
end

---------------------------------------------------------------------------
-- Chains
---------------------------------------------------------------------------

function SideQuestPlan.chain(Config: any, id: string): any?
	for _, c in Q(Config).chains do
		if c.id == id then
			return c
		end
	end
	return nil
end

function SideQuestPlan.byBit(Config: any, bit: number): any?
	for _, c in Q(Config).chains do
		if c.bit == bit then
			return c
		end
	end
	return nil
end

-- Dev chains show only with the Dev flag on (devOn: Studio and Config.Dev.sideQuestSample)
function SideQuestPlan.visible(chain: any, devOn: boolean): boolean
	return not chain.dev or devOn
end

-- The chains a giver offers
function SideQuestPlan.byGiver(Config: any, giver: string): { any }
	local out = {}
	for _, c in Q(Config).chains do
		if c.giver == giver then
			table.insert(out, c)
		end
	end
	return out
end

-- A character's side quest save, made if missing (Lune tests and old shapes)
function SideQuestPlan.save(c: any): any
	local sq = c.sq
	if type(sq) ~= "table" then
		sq =
			{ at = {}, done = table.create(ProfileSchema.SMALL_WORDS, 0), retired = 0, owed = 0, settled = 0 }
		c.sq = sq
	end
	return sq
end

function SideQuestPlan.isDone(c: any, chain: any): boolean
	return Bits.get(SideQuestPlan.save(c).done, chain.bit)
end

-- The current step of a chain in progress, or nil
function SideQuestPlan.stepOf(c: any, chain: any): number?
	local s = SideQuestPlan.save(c).at[chain.id]
	return if type(s) == "number" and s >= 1 and s <= #chain.steps then s else nil
end

-- The tracked chain and its step, or nil
function SideQuestPlan.pinned(Config: any, c: any): (any?, number?)
	local p = (c.story and c.story.pinned) or 0
	if p <= 0 then
		return nil, nil
	end
	local chain = SideQuestPlan.byBit(Config, p)
	local s = chain and SideQuestPlan.stepOf(c, chain)
	if not chain or not s then
		return nil, nil
	end
	return chain, s
end

-- Unlock state of a chain for a hero: "done", "active" (in progress), "open" (may be accepted) or "locked",
-- with the reason a locked one is locked ("level", "story", "after", "origin", "side") and its number
function SideQuestPlan.state(
	Config: any,
	c: any,
	chain: any,
	level: number,
	side: string
): (string, string?, any)
	if SideQuestPlan.isDone(c, chain) then
		return "done", nil, nil
	end
	if SideQuestPlan.stepOf(c, chain) then
		return "active", nil, nil
	end
	local u = chain.unlock or {}
	if u.side and u.side ~= side then
		return "locked", "side", u.side
	end
	if u.origin and (c.origin or 0) ~= u.origin then
		return "locked", "origin", u.origin
	end
	if u.after then
		local prev = SideQuestPlan.chain(Config, u.after)
		if not prev or not SideQuestPlan.isDone(c, prev) then
			return "locked", "after", u.after
		end
	end
	if (u.story or 0) > 0 and not StoryPlan.cleared(c.story, u.story) then
		return "locked", "story", u.story
	end
	if level < (u.level or 1) then
		return "locked", "level", u.level
	end
	return "open", nil, nil
end

-- Accept a chain (from its giver, or from the Journal unless it is an NPC-only line): it starts at step 1 and
-- is tracked. Returns ok and why not.
function SideQuestPlan.accept(
	Config: any,
	c: any,
	chain: any,
	level: number,
	side: string,
	fromJournal: boolean?
): (boolean, string?)
	local st, why = SideQuestPlan.state(Config, c, chain, level, side)
	if st ~= "open" then
		return false, why or st
	end
	if fromJournal and chain.unlock and chain.unlock.npc then
		return false, "npc"
	end
	SideQuestPlan.save(c).at[chain.id] = 1
	c.story.pinned = chain.bit
	return true, nil
end

-- Track a chain in progress again (from its giver or the Journal)
function SideQuestPlan.resume(c: any, chain: any): boolean
	if not SideQuestPlan.stepOf(c, chain) then
		return false
	end
	c.story.pinned = chain.bit
	return true
end

-- Put a chain on hold: no longer tracked, its step kept (the half-done step restarts on resume)
function SideQuestPlan.abandon(c: any, chain: any): boolean
	if not SideQuestPlan.stepOf(c, chain) then
		return false
	end
	if c.story.pinned == chain.bit then
		c.story.pinned = 0
	end
	return true
end

-- Finish the current step: "next" (another step), "done" (the chain is finished: pay it) or nil
function SideQuestPlan.advance(c: any, chain: any): string?
	local s = SideQuestPlan.stepOf(c, chain)
	if not s then
		return nil
	end
	local sq = SideQuestPlan.save(c)
	if s < #chain.steps then
		sq.at[chain.id] = s + 1
		return "next"
	end
	sq.at[chain.id] = nil
	Bits.set(sq.done, chain.bit)
	if c.story.pinned == chain.bit then
		c.story.pinned = 0
	end
	return "done"
end

-- Dev: set a chain in progress to a step (1 to #steps), started if needed
function SideQuestPlan.jump(c: any, chain: any, step: number)
	local sq = SideQuestPlan.save(c)
	Bits.set(sq.done, chain.bit, false)
	sq.at[chain.id] = math.clamp(math.floor(step), 1, #chain.steps)
	c.story.pinned = chain.bit
end

-- Dev: forget a chain (not started)
function SideQuestPlan.reset(c: any, chain: any)
	local sq = SideQuestPlan.save(c)
	sq.at[chain.id] = nil
	Bits.set(sq.done, chain.bit, false)
	if c.story.pinned == chain.bit then
		c.story.pinned = 0
	end
end

-- The Journal's rows: every visible chain with its state, step, steps and lock reason
function SideQuestPlan.journal(Config: any, c: any, level: number, side: string, devOn: boolean): { any }
	local rows = {}
	for _, chain in Q(Config).chains do
		if SideQuestPlan.visible(chain, devOn) then
			local st, why, n = SideQuestPlan.state(Config, c, chain, level, side)
			if why ~= "side" and why ~= "origin" then -- a line for another side or origin stays hidden
				table.insert(rows, {
					bit = chain.bit,
					state = st,
					step = SideQuestPlan.stepOf(c, chain) or 0,
					steps = #chain.steps,
					why = why,
					n = if type(n) == "number" then n else nil,
					after = if why == "after" then n else nil,
				})
			end
		end
	end
	return rows
end

-- What the giver does on Talk: the chain to resume, else the first to start, else nil. kind: "resume",
-- "offer" or "none" (the giver has nothing for this hero now)
function SideQuestPlan.talkPick(
	Config: any,
	c: any,
	giver: string,
	level: number,
	side: string,
	devOn: boolean
): (any?, string)
	local open = nil
	for _, chain in SideQuestPlan.byGiver(Config, giver) do
		if SideQuestPlan.visible(chain, devOn) then
			local st = SideQuestPlan.state(Config, c, chain, level, side)
			if st == "active" then
				return chain, "resume"
			elseif st == "open" and not open then
				open = chain
			end
		end
	end
	if open then
		return open, "offer"
	end
	return nil, "none"
end

---------------------------------------------------------------------------
-- Pay
---------------------------------------------------------------------------

local function contractPay(Config: any, level: number, share: number): (number, number)
	local credits, renown = ContractPlan.pay(Config, Q(Config).pay.contract, level, math.huge, false)
	return math.floor(credits * share + 0.5), math.floor(renown * share + 0.5)
end

-- A step's pay at the hero's level (the finale more)
function SideQuestPlan.stepPay(Config: any, level: number, finale: boolean): (number, number)
	local P = Q(Config).pay
	return contractPay(Config, level, if finale then P.finale else P.step)
end

-- The chain's end: its reward share of contract pay at the hero's level (the cosmetic is paid on its own)
function SideQuestPlan.chainPay(Config: any, chain: any, level: number): (number, number)
	local share = math.clamp((chain.reward and chain.reward.share) or 0, 0, Q(Config).pay.maxShare)
	return contractPay(Config, level, share)
end

-- The reward table StoryService.pay takes for the chain's cosmetic (style, emote, frame, prop, title)
function SideQuestPlan.cosmetic(chain: any): { [string]: string }
	local out = {}
	for _, k in { "style", "emote", "frame", "prop", "title" } do
		local v = chain.reward and chain.reward[k]
		if type(v) == "string" then
			out[k] = v
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Co-op groups
---------------------------------------------------------------------------

export type Side = { have: number, need: number, done: boolean }
export type Group = { chain: string, step: number, sides: { [string]: Side }, members: { [any]: string } }

function SideQuestPlan.newGroup(chain: string, step: number): Group
	return { chain = chain, step = step, sides = {}, members = {} }
end

-- May a hero on this chain and step share the group?
function SideQuestPlan.canJoin(g: Group, chain: string, step: number): boolean
	return g.chain == chain and g.step == step
end

-- A member joins under its side's key; returns the key and whether that key's goal is new (build it)
function SideQuestPlan.join(g: Group, step: any, id: any, side: string): (string, boolean)
	local key = SideQuestPlan.keyFor(step, side)
	g.members[id] = key
	if g.sides[key] then
		return key, false
	end
	local goal = SideQuestPlan.goal(step, side)
	g.sides[key] = { have = 0, need = if goal then SideQuestPlan.need(goal) else 1, done = false }
	return key, true
end

-- A member leaves; a side left with nobody drops its goal (nobody waits on it). Returns the dropped key (tear
-- its goal down) and whether the group is empty.
function SideQuestPlan.leave(g: Group, id: any): (string?, boolean)
	local key = g.members[id]
	g.members[id] = nil
	local dropped = nil
	if key then
		local still = false
		for _, k in g.members do
			if k == key then
				still = true
				break
			end
		end
		if not still then
			g.sides[key] = nil
			dropped = key
		end
	end
	return dropped, next(g.members) == nil
end

-- A side's progress (absolute); returns true the moment that side's goal is met
function SideQuestPlan.set(g: Group, key: string, have: number): boolean
	local s = g.sides[key]
	if not s or s.done then
		return false
	end
	s.have = math.clamp(have, 0, s.need)
	if s.have >= s.need then
		s.done = true
		return true
	end
	return false
end

function SideQuestPlan.add(g: Group, key: string, amount: number): boolean
	local s = g.sides[key]
	return s ~= nil and SideQuestPlan.set(g, key, s.have + amount)
end

-- Every side present has finished (and someone is there)
function SideQuestPlan.groupDone(g: Group): boolean
	local any = false
	for _, s in g.sides do
		if not s.done then
			return false
		end
		any = true
	end
	return any
end

-- A side that finished waits on another still working
function SideQuestPlan.waiting(g: Group, key: string): boolean
	local s = g.sides[key]
	return s ~= nil and s.done and not SideQuestPlan.groupDone(g)
end

---------------------------------------------------------------------------
-- The arcs before step 10 (retired): settle once
---------------------------------------------------------------------------

local function popcount(n: number): number
	local c = 0
	n = math.floor(n)
	while n > 0 do
		c += n % 2
		n = n // 2
	end
	return c
end
SideQuestPlan.popcount = popcount

-- Pay what the retired arcs left on a profile, once per character: Credits owed for finished steps of arcs in
-- progress, and every finished arc's unlocks set (already owned ones stay as they are: nothing twice).
-- Returns { credits, unlocks = { { kind, name } } } of what was added.
function SideQuestPlan.settle(Config: any, profile: any): { credits: number, unlocks: { any } }
	local R = Q(Config).retired
	local out = { credits = 0, unlocks = {} }
	for _, c in profile.characters or {} do
		local sq = SideQuestPlan.save(c)
		if sq.settled ~= 1 then
			sq.settled = 1
			if sq.owed > 0 then
				profile.currency.credits += sq.owed
				out.credits += sq.owed
				sq.owed = 0
			end
			for arc = 1, R.arcs do
				local rw = R.rewards[arc]
				if rw and (sq.retired // 2 ^ (arc - 1)) % 2 == 1 then
					local words, bit = nil, nil
					if rw.style then
						words, bit = "styles", GearMath.questStyle(Config, rw.style)
					elseif rw.emote then
						words, bit = "emotes", Config.Story.unlocks.emotes[rw.emote]
					elseif rw.frame then
						words, bit = "frames", Config.Story.unlocks.frames[rw.frame]
					elseif rw.prop then
						words, bit = "props", Config.Story.unlocks.props[rw.prop]
					end
					if words and bit and profile[words] and not Bits.get(profile[words], bit) then
						Bits.set(profile[words], bit)
						table.insert(out.unlocks, { words, rw.style or rw.emote or rw.frame or rw.prop })
					end
				end
			end
		end
	end
	return out
end

-- Side quest chains finished on the account (the creator's chain pieces): the most on any one hero, live
-- chains (not Dev ones) plus the retired arcs that hero finished
function SideQuestPlan.chainsDone(Config: any, profile: any): number
	local best = 0
	for _, c in profile.characters or {} do
		local sq = c.sq
		if type(sq) == "table" then
			local n = popcount(sq.retired or 0)
			for _, chain in Q(Config).chains do
				if not chain.dev and type(sq.done) == "table" and Bits.get(sq.done, chain.bit) then
					n += 1
				end
			end
			best = math.max(best, n)
		end
	end
	return best
end

-- Every side quest done on this hero (the HQ trophy, the Odd Jobs badge): every retired arc, or every live
-- chain this hero's side and origin can take (at least one)
function SideQuestPlan.allDone(Config: any, c: any): boolean
	local sq = c.sq
	if type(sq) ~= "table" then
		return false
	end
	local R = Q(Config).retired
	if (sq.retired or 0) >= 2 ^ R.arcs - 1 then
		return true
	end
	local any = false
	for _, chain in Q(Config).chains do
		local u = chain.unlock or {}
		if not chain.dev and (not u.side or u.side == c.side) and (not u.origin or u.origin == c.origin) then
			if type(sq.done) ~= "table" or not Bits.get(sq.done, chain.bit) then
				return false
			end
			any = true
		end
	end
	return any
end

---------------------------------------------------------------------------
-- Validation
---------------------------------------------------------------------------

local FORBIDDEN_REWARD = { "credits", "renown", "skillPoints", "loot", "gadget", "dust", "xp" }

-- Fixed text: a non-empty string with no format holes, at most cap characters
local function fixedText(t: any, cap: number): string?
	if type(t) ~= "string" or #t == 0 then
		return "no text"
	elseif #t > cap then
		return string.format("%d characters (cap %d)", #t, cap)
	elseif string.find(t, "%", 1, true) or string.find(t, "{", 1, true) then
		return "a format hole"
	end
	return nil
end
SideQuestPlan.fixedText = fixedText

-- A line's speaker: a guide (Config.Story.guides.speakers) or a giver
local function speakerKnown(Config: any, who: any): boolean
	return type(who) == "string"
		and (Config.Story.guides.speakers[who] ~= nil or Q(Config).givers[who] ~= nil)
end

local function enemyKnown(Config: any, kind: any): boolean
	return type(kind) == "string" and Config.Enemies[kind] ~= nil and type(Config.Enemies[kind]) == "table"
end

local function checkGoal(
	Config: any,
	goal: any,
	side: string,
	where: string,
	bad: { string },
	finaleOk: boolean
)
	local function no(msg: string)
		table.insert(bad, where .. ": " .. msg)
	end
	local SQ = Q(Config)
	local kind = SideQuestPlan.KINDS[goal.kind]
	if not kind then
		no("unknown kind " .. tostring(goal.kind))
		return
	end
	for _, f in kind.fields do
		if goal[f] == nil then
			no(goal.kind .. " needs " .. f)
		end
	end
	local bad1 = fixedText(SideQuestPlan.text(goal, side), SQ.maxText)
	if bad1 then
		no(side .. " text: " .. bad1)
	end
	if SideQuestPlan.need(goal) < 1 then
		no("needs nothing")
	end
	for _, row in goal.squads or {} do
		if not enemyKnown(Config, row[1]) or (row[2] or 0) < 1 then
			no("squad " .. tostring(row[1]))
		end
	end
	for _, row in goal.adds or {} do
		if not enemyKnown(Config, row[1]) or (row[2] or 0) < 1 then
			no("adds " .. tostring(row[1]))
		end
	end
	if goal.guards and not enemyKnown(Config, goal.guards[1]) then
		no("guards " .. tostring(goal.guards[1]))
	end
	if goal.kind == "chase" and not enemyKnown(Config, goal.enemy) then
		no("chase robot " .. tostring(goal.enemy))
	end
	if goal.kind == "talk" and goal.giver and not SQ.givers[goal.giver] then
		no("talk to an unknown giver " .. tostring(goal.giver))
	end
	if goal.kind == "incident" then
		if (goal.count or 0) < 1 then
			no("incident count")
		end
		local t = goal.template and Config.Incidents.templates[goal.template]
		if goal.template and not t then
			no("unknown incident " .. tostring(goal.template))
		elseif t and t.side ~= "both" and t.side ~= side then
			no("incident " .. goal.template .. " is not for " .. side)
		end
	end
	if goal.kind == "pocket" then
		local PocketLayout = if script
			then require((script :: any).Parent.PocketLayout)
			else (require :: any)("./PocketLayout")
		if not PocketLayout.known(goal.layout) then
			no("unknown pocket layout " .. tostring(goal.layout))
		end
		local m = SQ.pocketMinutes
		if type(goal.minutes) ~= "number" or goal.minutes < m[1] or goal.minutes > m[2] then
			no("pocket minutes")
		end
		if type(goal.steps) ~= "table" or #goal.steps == 0 then
			no("a pocket needs steps")
		end
		for i, st in goal.steps or {} do
			local w = string.format("pocket step %d", i)
			if not SideQuestPlan.POCKET_KINDS[st.kind] then
				no(w .. " kind " .. tostring(st.kind))
			end
			local t = fixedText(st.text, SQ.maxText)
			if t then
				no(w .. " text: " .. t)
			end
			if st.villainText and fixedText(st.villainText, SQ.maxText) then
				no(w .. " villain text")
			end
			if st.kind == "boss" and not enemyKnown(Config, st.enemy) then
				no(w .. " boss " .. tostring(st.enemy))
			end
			for _, row in st.squads or {} do
				if not enemyKnown(Config, row[1]) then
					no(w .. " squad " .. tostring(row[1]))
				end
			end
		end
	end
	if goal.kind == "finale" then
		if not finaleOk then
			no("a finale only as the last step")
		end
		if not table.find(SQ.finale.enemies, goal.enemy) or not enemyKnown(Config, goal.enemy) then
			no("finale robot " .. tostring(goal.enemy) .. " (an elite or a famous fake)")
		end
		local h = SQ.finale.hpMult
		if type(goal.hpMult) ~= "number" or goal.hpMult < h[1] or goal.hpMult > h[2] then
			no("finale health")
		end
	end
	if goal.range and (type(goal.range) ~= "table" or goal.range[1] > goal.range[2]) then
		no("range")
	end
end

local function checkLine(Config: any, line: any, where: string, bad: { string })
	if not speakerKnown(Config, line.who) then
		table.insert(bad, where .. ": unknown speaker " .. tostring(line.who))
	end
	for _, side in Q(Config).sides do
		local t = line.text or line[side]
		local b = fixedText(t, Config.Story.guides.maxChars)
		if b then
			table.insert(bad, where .. " " .. side .. ": " .. b)
		end
	end
end

local function checkReward(Config: any, r: any, where: string, bad: { string })
	local function no(msg: string)
		table.insert(bad, where .. ": " .. msg)
	end
	if type(r) ~= "table" then
		no("no reward")
		return
	end
	if type(r.share) ~= "number" or r.share <= 0 or r.share > Q(Config).pay.maxShare then
		no("reward share out of range")
	end
	for _, k in FORBIDDEN_REWARD do
		if r[k] ~= nil then
			no("reward " .. k .. " (only the pay share and a cosmetic or title)")
		end
	end
	local U = Config.Story.unlocks
	local n = 0
	for k, v in SideQuestPlan.cosmetic({ reward = r }) do
		n += 1
		if k == "style" and not GearMath.questStyle(Config, v) then
			no("style " .. v)
		elseif k == "emote" then
			local bit = U.emotes[v]
			local row = bit and Config.Shop.emotes[bit]
			if not row or not row.earned then
				no("emote " .. v .. " (must exist and never be sold)")
			end
		elseif (k == "frame" or k == "prop" or k == "title") and not U[k .. "s"][v] then
			no(k .. " " .. v)
		end
	end
	if n ~= 1 then
		no("one cosmetic or title at the end (has " .. n .. ")")
	end
end

-- Problems with one chain (empty when it is fine); ids: chain id -> chain, for `after`
function SideQuestPlan.checkChain(Config: any, chain: any, ids: { [string]: any }): { string }
	local SQ = Q(Config)
	local bad = {}
	local where = "chain " .. tostring(chain.id)
	local function no(msg: string)
		table.insert(bad, where .. ": " .. msg)
	end
	if type(chain.id) ~= "string" or chain.id == "" then
		no("id")
	end
	if type(chain.bit) ~= "number" or chain.bit < 1 or chain.bit >= ProfileSchema.SMALL_WORDS * 32 then
		no("bit 1 to 127")
	end
	local nb = fixedText(chain.name, 40)
	if nb then
		no("name: " .. nb)
	end
	if not table.find(SQ.layers, chain.layer) then
		no("layer " .. tostring(chain.layer))
	end
	local giver = SQ.givers[chain.giver]
	if not giver then
		no("giver " .. tostring(chain.giver))
	elseif giver.dev and not chain.dev then
		no("a Dev giver on a real chain")
	end
	local u = chain.unlock or {}
	if chain.layer == "district" and not table.find(SQ.districts, chain.district) then
		no("district " .. tostring(chain.district))
	end
	if chain.layer == "origin" and not Config.Creator.origins[u.origin or 0] then
		no("an origin line needs its origin")
	end
	if u.origin and not Config.Creator.origins[u.origin] then
		no("origin " .. tostring(u.origin))
	end
	if u.level and (u.level < 1 or u.level > Config.Stats.levelCap) then
		no("level " .. u.level .. " is out of reach")
	end
	if u.story and (u.story < 0 or u.story > #Config.Story.missions) then
		no("story mission " .. u.story)
	end
	if u.side and u.side ~= "hero" and u.side ~= "villain" then
		no("side " .. tostring(u.side))
	end
	if u.after then
		local prev = ids[u.after]
		if not prev or prev == chain then
			no("after " .. tostring(u.after))
		else
			local pu = prev.unlock or {}
			if prev.dev and not chain.dev then
				no("after a Dev chain")
			end
			if pu.side and u.side ~= pu.side then
				no("after a chain another side cannot finish")
			end
			if pu.origin and u.origin ~= pu.origin then
				no("after a chain another origin cannot finish")
			end
			-- no loops: follow the after links
			local seen = { [chain] = true }
			local at = prev
			while at do
				if seen[at] then
					no("an after loop")
					break
				end
				seen[at] = true
				at = at.unlock and at.unlock.after and ids[at.unlock.after]
			end
		end
	end
	local v = chain.villain
	if type(v) ~= "table" or fixedText(v.name, 32) or fixedText(v.title, 32) then
		no("villain name card (name and title)")
	end
	checkReward(Config, chain.reward, where, bad)
	for _, key in { "offer", "resume", "done" } do
		local l = chain.lines and chain.lines[key]
		if not l then
			no("giver line " .. key)
		else
			checkLine(
				Config,
				{ who = chain.giver, text = l.text, hero = l.hero, villain = l.villain },
				where .. " " .. key,
				bad
			)
		end
	end
	local steps = chain.steps or {}
	if #steps < SQ.minSteps or #steps > SQ.maxSteps then
		no(string.format("%d steps (%d to %d)", #steps, SQ.minSteps, SQ.maxSteps))
	end
	for i, step in steps do
		local w = string.format("%s step %d", where, i)
		local last = i == #steps
		for _, side in SQ.sides do
			local g = SideQuestPlan.goal(step, side)
			if not g then
				table.insert(bad, w .. ": no " .. side .. " goal")
			else
				checkGoal(Config, g, side, w .. " " .. side, bad, last)
			end
		end
		if last then
			local gh, gv = SideQuestPlan.goal(step, "hero"), SideQuestPlan.goal(step, "villain")
			if not gh or gh.kind ~= "finale" or not gv or gv.kind ~= "finale" then
				table.insert(bad, w .. ": the last step is the finale")
			end
		end
		for j, line in step.lines or {} do
			checkLine(Config, line, string.format("%s line %d", w, j), bad)
		end
		if step.scene then
			local sc = Config.Cinema.scenes[step.scene]
			if not sc or not sc.client then
				table.insert(bad, w .. ": scene " .. tostring(step.scene) .. " (a device scene)")
			end
		end
	end
	return bad
end

-- Problems with all the side quest data (empty when all is well)
function SideQuestPlan.validate(Config: any): { string }
	local SQ = Q(Config)
	local bad = {}
	local ids, bits = {}, {}
	for _, chain in SQ.chains do
		if ids[chain.id] then
			table.insert(bad, "chain id twice: " .. tostring(chain.id))
		end
		if bits[chain.bit] then
			table.insert(bad, "chain bit twice: " .. tostring(chain.bit))
		end
		ids[chain.id], bits[chain.bit] = chain, true
	end
	for _, chain in SQ.chains do
		for _, b in SideQuestPlan.checkChain(Config, chain, ids) do
			table.insert(bad, b)
		end
	end
	for id, g in SQ.givers do
		if fixedText(g.name, 24) or type(g.color) ~= "table" or type(g.portrait) ~= "table" then
			table.insert(bad, "giver " .. id .. ": name, colour and portrait")
		end
		if g.style ~= "person" and g.style ~= "radio" then
			table.insert(bad, "giver " .. id .. ": style")
		end
		if g.anchor ~= "plaza" and g.anchor ~= "hq" and not Config.City.districts[g.anchor] then
			table.insert(bad, "giver " .. id .. ": anchor " .. tostring(g.anchor))
		end
		if Config.Story.guides.speakers[id] then
			table.insert(bad, "giver " .. id .. ": a guide already has that id")
		end
	end
	for i, g in SQ.devKinds do
		checkGoal(Config, g, "hero", "devKinds " .. i, bad, true)
	end
	return bad
end

return SideQuestPlan
