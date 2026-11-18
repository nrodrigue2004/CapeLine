-- RoguesPage: the Rogues File, drawn as the Journal's ROGUES tab (spec: Collections and records > Rogues
-- File; Config.Rogues, Shared.RoguesFile). Every robot kind, famous fake, side quest finale villain and world
-- boss in one book:
-- * the count beaten, the gold pages and the next collection reward at the top;
-- * a beaten one's page: its portrait in its own colours, name, title, the fixed blurb, how many times you
--   beat it and when (the day and your level the first time); a boss beaten at the gold level gets a gold
--   page (gold frame, GOLD PAGE);
-- * one not beaten yet: a black silhouette, "???" and a hint where to meet it (never hidden, so there is
--   always a next one to find).
-- The server fills the pages (RoguesService); a new page stamps on screen (Juice "roguePage").
-- PLACEHOLDER ART: the portraits are Kit shapes until the UI art pass.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local RoguesFile = require(Shared:WaitForChild("RoguesFile"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local Juice = require(script.Parent.Parent.Fx.Juice)
local Kit = require(script.Parent.Kit)

local RoguesPage = {}
RoguesPage.Changed = Signal.new() -- the pages arrived or changed (the Journal redraws)

local R = Config.Rogues
local SHADOW = Color3.fromRGB(28, 28, 34)
local OUTLINE = Color3.fromRGB(110, 110, 120)
local DIM = Color3.fromRGB(46, 46, 54)
local GOLD_EDGE = Color3.fromRGB(255, 200, 60)

local data: { bits: { [number]: boolean }, log: { [string]: { number } } }? = nil
local inited = false

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

-- The pages as the server sent them: { bits = list of page bits, log = { [bit] = { day, count, level } } }
function RoguesPage.apply(d: any)
	if type(d) ~= "table" then
		return
	end
	local set = {}
	for _, b in (if type(d.bits) == "table" then d.bits else {}) do
		if type(b) == "number" then
			set[b] = true
		end
	end
	data = { bits = set, log = if type(d.log) == "table" then d.log else {} }
	RoguesPage.Changed:Fire()
end

-- Ask the server for the pages (the Journal's tab opening)
function RoguesPage.request()
	Net.send("RoguesOpen")
end

function RoguesPage.hasData(): boolean
	return data ~= nil
end

local function has(bit: number?): boolean
	return bit ~= nil and data ~= nil and data.bits[bit] == true
end

-- The portrait: a head, eyes and shoulders in the robot's own colours, or a black silhouette with "?"
local function portrait(parent: Instance, e: RoguesFile.Entry, beaten: boolean)
	local box = Kit.frame({
		Size = UDim2.fromOffset(56, 56),
		Position = UDim2.fromOffset(8, 10),
		BackgroundColor3 = if beaten then Kit.color.night else DIM,
	})
	Kit.stroke(box, if beaten then rgb(e.colors[2]) else OUTLINE, 2)
	box.Parent = parent
	local body = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -2),
		Size = UDim2.fromOffset(40, 18),
		BackgroundColor3 = if beaten then rgb(e.colors[1]) else SHADOW,
	})
	body.Parent = box
	local head = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = if beaten then rgb(e.colors[2]) else SHADOW,
	})
	head.Parent = box
	if beaten then
		for i, x in { 6, 14 } do
			local eye = Kit.frame({
				Name = "Eye" .. i,
				Position = UDim2.fromOffset(x, 10),
				Size = UDim2.fromOffset(6, 5),
				BackgroundColor3 = rgb(e.colors[3]),
			})
			eye.Parent = head
		end
	else
		local q = Kit.label({
			Text = "?",
			Size = UDim2.fromScale(1, 1),
			TextColor3 = OUTLINE,
			maxText = 22,
		})
		q.Parent = head
	end
end

local function label(
	parent: Instance,
	text: string,
	x: number,
	y: number,
	w: number,
	h: number,
	size: number,
	color: Color3,
	font: Enum.Font?,
	wrapped: boolean?
): TextLabel
	local l = Kit.label({
		Text = text,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.new(1, w, 0, h),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = if wrapped then Enum.TextYAlignment.Top else Enum.TextYAlignment.Center,
		TextColor3 = color,
		Font = font or Kit.bodyFont,
		TextWrapped = wrapped == true,
		maxText = size,
	})
	l.Parent = parent
	return l
end

local function pageRow(body: Instance, order: number, e: RoguesFile.Entry)
	local beaten = has(e.bit)
	local gold = beaten and has(e.gold)
	local row = Kit.frame({
		Name = "Page" .. e.bit,
		Size = UDim2.new(1, -8, 0, 96),
		LayoutOrder = order,
		BackgroundColor3 = if beaten then Kit.color.paper else DIM,
	})
	if gold then
		Kit.stroke(row, GOLD_EDGE, 4)
		row.BackgroundColor3 = Color3.fromRGB(255, 240, 200)
	elseif not beaten then
		Kit.stroke(row, OUTLINE, 2)
	end
	row.Parent = body
	portrait(row, e, beaten)
	local ink = if beaten then Kit.color.ink else Color3.fromRGB(170, 170, 180)
	if not beaten then
		label(row, "???", 74, 6, -84, 26, 22, ink, Kit.font)
		label(row, RoguesFile.where(Config, e), 74, 36, -84, 32, 14, ink, nil, true)
		return
	end
	label(row, string.upper(e.name), 74, 4, -84, 24, 22, ink, Kit.font)
	if e.title ~= "" then
		label(row, string.upper(e.title), 74, 27, -84, 16, 13, Kit.color.muted, Kit.font)
	end
	label(row, e.blurb, 74, 44, -84, 32, 14, ink, nil, true)
	local log = data and data.log[tostring(e.bit)]
	local count = if type(log) == "table" then log[2] or 0 else 0
	local day = if type(log) == "table" then log[1] or 0 else 0
	local lvl = if type(log) == "table" then log[3] or 0 else 0
	local stats = string.format("Beaten x%s", RoguesFile.countText(math.max(1, count)))
	if day > 0 then
		stats ..= "  |  First: " .. RoguesFile.dateText(day)
		if lvl > 0 then
			stats ..= string.format(", level %d", lvl)
		end
	end
	if gold then
		stats = "GOLD PAGE  |  " .. stats
	end
	label(row, stats, 74, 77, -84, 16, 12, if gold then Color3.fromRGB(150, 100, 0) else Kit.color.muted)
	if e.gold and not gold then
		-- a beaten boss: how to get its gold page (on the title line's right, small)
		row.Size = UDim2.new(1, -8, 0, 112)
		label(row, R.gold.hint, 74, 93, -84, 16, 12, Color3.fromRGB(150, 100, 0))
	end
end

local function header(body: Instance, order: number, text: string)
	local h = Kit.frame({
		Size = UDim2.new(1, -8, 0, 30),
		LayoutOrder = order,
		BackgroundTransparency = 1,
	})
	h.Parent = body
	label(h, text, 4, 2, -8, 26, 18, Kit.color.gold, Kit.font)
end

-- Draw the whole book into a Journal tab's scrolling list (the caller cleared it)
function RoguesPage.drawInto(body: Instance)
	local d = data
	if not d then
		Kit.stateNote(body, "loading", "Opening the Rogues File...")
		return
	end
	local list = RoguesFile.list(Config)
	local words = table.create(RoguesFile.WORDS, 0)
	for b in d.bits do
		local k = b // 32 + 1
		if words[k] then
			words[k] = bit32.bor(words[k], bit32.lshift(1, b % 32))
		end
	end
	local n, total = RoguesFile.count(Config, words)
	local g, gTotal = RoguesFile.goldCount(Config, words)
	-- the top: pages, gold pages and the next reward
	local top =
		Kit.frame({ Size = UDim2.new(1, -8, 0, 84), LayoutOrder = 1, BackgroundColor3 = Kit.color.paper })
	top.Parent = body
	label(top, string.format("ROGUES FILE   %d / %d", n, total), 10, 4, -20, 28, 24, Kit.color.ink, Kit.font)
	local bar = Kit.frame({
		Position = UDim2.fromOffset(10, 36),
		Size = UDim2.new(1, -20, 0, 10),
		BackgroundColor3 = Kit.color.muted,
	})
	bar.Parent = top
	local fill = Kit.frame({
		Size = UDim2.fromScale(math.clamp(n / math.max(1, total), 0, 1), 1),
		BackgroundColor3 = Kit.color.gold,
	})
	fill.Parent = bar
	local m = RoguesFile.nextMilestone(Config, words)
	local nextText = if m
		then string.format("Next: %d pages for the %s", RoguesFile.need(Config, m), m.piece)
		else "Every page found!"
	label(
		top,
		string.format("Gold pages %d / %d  |  %s", g, gTotal, nextText),
		10,
		52,
		-20,
		26,
		13,
		Kit.color.ink,
		nil,
		true
	)
	-- the groups, in book order
	for gi, grp in R.groups do
		local got, all = 0, 0
		for _, e in list do
			if e.group == grp.id then
				all += 1
				if has(e.bit) then
					got += 1
				end
			end
		end
		header(body, gi * 1000, string.format("%s   %d / %d", grp.name, got, all))
		local i = 0
		for _, e in list do
			if e.group == grp.id then
				i += 1
				pageRow(body, gi * 1000 + i, e)
			end
		end
	end
end

function RoguesPage.init()
	if inited then
		return
	end
	inited = true
	Net.listen("RoguesFile", RoguesPage.apply)
	Net.listen("RoguesNew", function(d: any)
		if type(d) ~= "table" then
			return
		end
		if d.milestone then
			Juice.fire("roguePage", nil, { milestone = d.milestone, piece = d.piece })
			return
		end
		local e = type(d.bit) == "number" and RoguesFile.byBit(Config, d.bit)
		if d.gold then
			-- a gold page's bit is its boss's gold bit
			for _, row in RoguesFile.list(Config) do
				if row.gold == d.bit then
					e = row
				end
			end
		end
		Juice.fire("roguePage", nil, { name = e and e.name, gold = d.gold == true })
	end)
end

return RoguesPage
