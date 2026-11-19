-- MentorHud: your mentor on screen (spec: Hero MMO features > Original mentors; H6). The MENTOR button
-- (under WANTED) opens the mentor card: who guides you, their quest line (the open part's goals and counts,
-- the parts done), their look reward (WEAR it once earned) and, at a safehouse, CHANGE to the other mentor of
-- your side (free). After the opening the picker card pops once with your side's two mentors. The comic
-- panels (fixed lines with your hero name) slide in at the top and never block play.
-- The portrait is the comic art pass's rendered bust (Config.ComicArt); until its sheet is uploaded, a colour block
-- with the mentor's initial (PLACEHOLDER ART fallback). The rest is Kit frames.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local ComicArt = require(Shared:WaitForChild("ComicArt"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local Juice = require(script.Parent.Parent.Fx.Juice)
local Kit = require(script.Parent.Kit)
local Popups = require(script.Parent.Popups) -- pt-ui: one line for every popup
local PopupGate = require(script.Parent.PopupGate)

local MentorHud = {}
-- WP7: the Journal's MENTOR tab draws this card (drawInto) and redraws when a new card arrives
MentorHud.Changed = Signal.new()

local M = Config.Mentors
local T = Config.Ui.touchTarget
local gui: ScreenGui
local cardFrame: Frame
local cardBody: Frame
local picker: Frame
local pickBody: Frame
local panel: Frame
local panelPortrait: TextLabel
local panelName: TextLabel
local panelLine: TextLabel
local openButton: TextButton
local panelSeq = 0
local last: { [string]: any }? = nil

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function clear(f: Instance)
	for _, c in f:GetChildren() do
		if not c:IsA("UIListLayout") then
			c:Destroy()
		end
	end
end

local function text(parent: Instance, s: string, h: number, size: number, color: Color3?, order: number)
	local l = Kit.label({
		Text = s,
		Size = UDim2.new(1, 0, 0, h),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color or Kit.color.paper,
		Font = Kit.bodyFont,
		TextWrapped = true,
		maxText = size,
	})
	l.LayoutOrder = order
	l.Parent = parent
	return l
end

-- The mentor's rendered comic bust (Config.ComicArt) over the portrait block; with no art uploaded yet the block
-- shows the initial instead (PLACEHOLDER ART fallback). Returns whether the art shows.
local function dressPortrait(p: TextLabel, m: any): boolean
	local art = ComicArt.portrait(Config, m.id)
	local img = p:FindFirstChild("Art") :: ImageLabel?
	if art and not img then
		local new = Instance.new("ImageLabel")
		new.Name = "Art"
		new.Size = UDim2.fromScale(1, 1)
		new.BackgroundTransparency = 1
		new.ZIndex = p.ZIndex
		new.Parent = p
		img = new
	end
	if img then
		img.Visible = art ~= nil
		if art then
			img.Image = art.image
			img.ImageRectOffset = Vector2.new(art.offset[1], art.offset[2])
			img.ImageRectSize = Vector2.new(art.size[1], art.size[2])
		end
	end
	p.Text = if art then "" else m.initial
	return art ~= nil
end

local function portrait(parent: Instance, m: any, size: number): TextLabel
	local p = Kit.label({
		Text = m.initial,
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 0,
		BackgroundColor3 = rgb(m.colors[1]),
		TextColor3 = rgb(m.colors[2]),
		maxText = math.floor(size * 0.6),
	})
	Kit.stroke(p, rgb(m.colors[2]), 3)
	dressPortrait(p, m)
	p.Parent = parent
	return p
end

local function list(parent: Instance): UIListLayout
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = parent
	return l
end

local function render(d: { [string]: any })
	last = d
	clear(cardBody)
	local m = M.list[d.mentor or 0]
	openButton.Text = if m then "MENTOR" else "PICK MENTOR"
	if not m then
		text(cardBody, "No mentor yet.", 26, 20, Kit.color.gold, 1)
		if d.canPick then
			for i, idx in
				(function()
					local out = {}
					for j, row in M.list do
						if row.side == d.side then
							table.insert(out, j)
						end
					end
					return out
				end)()
			do
				local row = M.list[idx]
				local b = Kit.button({
					pending = true,
					Text = "PICK " .. string.upper(row.name),
					Size = UDim2.new(1, 0, 0, T),
					BackgroundColor3 = rgb(row.colors[1]),
					TextColor3 = Color3.new(1, 1, 1),
				}, function()
					Net.send("MentorPick", idx)
				end)
				b.LayoutOrder = 1 + i
				b.Parent = cardBody
			end
		else
			text(cardBody, "Finish the opening to pick a mentor.", 22, 15, nil, 2)
		end
		return
	end
	local head = Kit.frame({ Size = UDim2.new(1, 0, 0, 64), BackgroundTransparency = 1 })
	head.LayoutOrder = 1
	head.Parent = cardBody
	portrait(head, m, 60)
	local nm = Kit.label({
		Text = string.upper(m.name),
		Size = UDim2.new(1, -72, 0, 32),
		Position = UDim2.fromOffset(72, 2),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = rgb(m.colors[2]),
		maxText = 26,
	})
	nm.Parent = head
	local grp = Kit.label({
		Text = m.group .. " mentor",
		Size = UDim2.new(1, -72, 0, 22),
		Position = UDim2.fromOffset(72, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.muted,
		Font = Kit.bodyFont,
		maxText = 15,
	})
	grp.Parent = head
	-- the quest line
	local done = (d.parts or {})[d.mentor] or 0
	text(
		cardBody,
		string.format("Quest line: %d of %d parts done", done, #M.quest),
		22,
		17,
		Kit.color.gold,
		2
	)
	for i, part in M.quest do
		local state
		if i <= done then
			state = "done"
		elseif d.open == i then
			local bits = {}
			for g, goal in part.goals do
				table.insert(
					bits,
					string.format(
						"%s %d / %d",
						M.goalNames[goal.kind],
						math.min(goal.n, (d.count or {})[g] or 0),
						goal.n
					)
				)
			end
			state = table.concat(bits, ", ")
		else
			state = "opens at level " .. part.level
		end
		text(cardBody, string.format("%s: %s", M.partNames[i], state), 20, 14, nil, 2 + i)
	end
	-- the look reward
	text(
		cardBody,
		string.format("Reward: %s and the %s emote", m.look.name, Config.Shop.emotes[m.emote].name),
		20,
		14,
		Kit.color.muted,
		10
	)
	local earned = {}
	for i in M.list do
		if ((d.parts or {})[i] or 0) >= #M.quest then
			table.insert(earned, i)
		end
	end
	for k, i in earned do
		local row = M.list[i]
		local wearing = d.look == i
		local b = Kit.button({
			pending = true,
			Text = if wearing
				then "TAKE OFF " .. string.upper(row.look.name)
				else "WEAR " .. string.upper(row.look.name),
			Size = UDim2.new(1, 0, 0, T - 8),
			BackgroundColor3 = if wearing then Kit.color.paper else Kit.color.gold,
		}, function()
			Net.send("MentorWear", if wearing then 0 else i)
		end)
		b.LayoutOrder = 10 + k
		b.Parent = cardBody
	end
	-- change (free, at a safehouse)
	for j, row in M.list do
		if row.side == d.side and j ~= d.mentor then
			if d.atSafe then
				local b = Kit.button({
					pending = true,
					Text = "CHANGE TO " .. string.upper(row.name),
					Size = UDim2.new(1, 0, 0, T - 8),
					BackgroundColor3 = Kit.color.paper,
				}, function()
					Net.send("MentorPick", j)
				end)
				b.LayoutOrder = 20 + j
				b.Parent = cardBody
			else
				text(
					cardBody,
					"Change to " .. row.name .. " at any safehouse (free).",
					20,
					13,
					Kit.color.muted,
					20 + j
				)
			end
		end
	end
end

local function showPicker(d: { [string]: any })
	clear(pickBody)
	text(pickBody, "PICK YOUR MENTOR", 30, 26, Kit.color.gold, 0)
	text(pickBody, "A guide and a look, never stats. Change at any safehouse for free.", 20, 14, nil, 1)
	for k, idx in d.options or {} do
		local m = M.list[idx]
		if m then
			local row = Kit.frame({
				Size = UDim2.new(1, 0, 0, 84),
				BackgroundColor3 = Kit.color.night,
				BackgroundTransparency = 0.2,
			})
			row.LayoutOrder = 1 + k
			row.Parent = pickBody
			local p = portrait(row, m, 64)
			p.Position = UDim2.fromOffset(8, 10)
			local nm = Kit.label({
				Text = string.upper(m.name),
				Size = UDim2.new(1, -200, 0, 30),
				Position = UDim2.fromOffset(82, 8),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = rgb(m.colors[2]),
				maxText = 22,
			})
			nm.Parent = row
			local sub = Kit.label({
				Text = m.blurb .. " Reward: " .. m.look.name,
				Size = UDim2.new(1, -200, 0, 36),
				Position = UDim2.fromOffset(82, 40),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Kit.color.paper,
				Font = Kit.bodyFont,
				TextWrapped = true,
				maxText = 13,
			})
			sub.Parent = row
			local b = Kit.button({
				pending = true,
				Text = "PICK",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(T * 2, T),
				BackgroundColor3 = Kit.color.gold,
			}, function()
				Net.send("MentorPick", idx)
				picker.Visible = false
			end)
			b.Parent = row
		end
	end
	local later = Kit.button({
		Text = "LATER",
		Size = UDim2.new(1, 0, 0, T - 10),
		BackgroundColor3 = Kit.color.paper,
	}, function()
		picker.Visible = false
	end)
	later.LayoutOrder = 10
	later.Parent = pickBody
	picker.Visible = true
end

local function comicNow(mentor: number, line: string)
	local m = M.list[mentor]
	if not m then
		return
	end
	panelSeq += 1
	local seq = panelSeq
	panelPortrait.BackgroundColor3 = rgb(m.colors[1])
	panelPortrait.TextColor3 = rgb(m.colors[2])
	dressPortrait(panelPortrait, m)
	panelName.Text = string.upper(m.name)
	panelName.TextColor3 = rgb(m.colors[2])
	panelLine.Text = line
	panel.Visible = true
	Juice.fire("mentorPanel")
	task.delay(M.panelTime, function()
		if panelSeq == seq then
			panel.Visible = false
		end
	end)
end

-- pt-ui: the mentor's panel waits its turn in Ui.Popups ("mentorPanel")
local function comic(mentor: number, line: string)
	Popups.show("mentorPanel", function()
		comicNow(mentor, line)
	end, function()
		return panel.Visible
	end, function()
		panel.Visible = false
	end)
end

-- WP7: the mentor card in another screen's list (the Journal's MENTOR tab); the caller cleared it. The
-- card's own panel is left as it is.
function MentorHud.drawInto(container: Instance)
	local d = last
	if not d then
		Kit.stateNote(container, "loading", "Finding your mentor...")
		return
	end
	local keep = cardBody
	cardBody = container :: any
	render(d)
	cardBody = keep
end

-- Ask the server for the mentor card (MentorState answers)
function MentorHud.request()
	Net.send("MentorOpen")
end

function MentorHud.open()
	Kit.opening("MentorHud", cardFrame, MentorHud.close, true)
	cardFrame.Visible = true
	Net.send("MentorOpen")
	if last then
		render(last)
	end
end

function MentorHud.close()
	cardFrame.Visible = false
end

function MentorHud.init()
	gui = Kit.screen("MentorHud", 6)
	-- the mentor card
	cardFrame = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.9, 0, 0.8, 0),
		BackgroundColor3 = Kit.color.night,
		BackgroundTransparency = 0.05,
		Visible = false,
	})
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(460, 560)
	limit.Parent = cardFrame
	cardFrame.Parent = gui
	local close = Kit.button({
		Text = "X",
		Size = UDim2.fromOffset(T, T - 10),
		Position = UDim2.new(1, -T - 8, 0, 6),
		BackgroundColor3 = Kit.color.paper,
	}, MentorHud.close)
	close.Parent = cardFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(14, T)
	scroll.Size = UDim2.new(1, -28, 1, -T - 12)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollBarThickness = 6
	scroll.Parent = cardFrame
	cardBody = scroll :: any
	list(cardBody)
	-- the picker
	picker = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.9, 0, 0, 340),
		BackgroundColor3 = Kit.color.night,
		BackgroundTransparency = 0.05,
		Visible = false,
	})
	-- phone pass: the picker (title, two mentor rows, LATER: about 310 px) fits the screen, drawing smaller
	-- on a phone (a fixed 340 px ran past a 375 px phone's safe area)
	Kit.fit(picker, 400, 310, 480, 340)
	picker.Parent = gui
	PopupGate.card("mentorPick", function()
		return picker.Visible and gui.Enabled
	end)
	pickBody = Kit.frame({
		Size = UDim2.new(1, -28, 1, -20),
		Position = UDim2.fromOffset(14, 10),
		BackgroundTransparency = 1,
	})
	pickBody.Parent = picker
	list(pickBody)
	-- the menu button (under WANTED)
	openButton = Kit.button({
		Name = "MentorButton",
		Text = "MENTOR",
		Size = UDim2.fromOffset(T * 2 + 20, T - 10),
		Position = UDim2.fromOffset(Config.Ui.safe + 258, Config.Ui.safe + T * 3 - 8),
		BackgroundColor3 = Kit.color.paper,
	}, function()
		if cardFrame.Visible then
			MentorHud.close()
		else
			MentorHud.open()
		end
	end)
	Kit.dock(openButton, "Mentor", 14) -- the top row (or its MORE drawer), after SETTINGS
	-- the comic panel (top of the screen, under the nemesis's)
	panel = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 210),
		Size = UDim2.fromOffset(460, 96),
		BackgroundColor3 = Color3.fromRGB(255, 250, 235),
		Visible = false,
	})
	Kit.stroke(panel, Kit.color.ink, 4)
	panel.Parent = gui
	local function placePanel()
		-- under the nemesis's panel, but never past the bottom of a short phone screen
		local a = Kit.area()
		panel.Position = UDim2.new(0.5, 0, 0, math.min(210, a.Y - 96 - Config.Ui.phone.panelMargin))
	end
	placePanel()
	Kit.LayoutChanged:Connect(placePanel)
	panelPortrait = Kit.label({
		Text = "",
		Size = UDim2.fromOffset(72, 72),
		Position = UDim2.fromOffset(12, 12),
		BackgroundTransparency = 0,
		maxText = 44,
	})
	panelPortrait.Parent = panel
	panelName = Kit.label({
		Text = "",
		Size = UDim2.new(1, -110, 0, 28),
		Position = UDim2.fromOffset(96, 8),
		TextXAlignment = Enum.TextXAlignment.Left,
		maxText = 24,
	})
	panelName.Parent = panel
	panelLine = Kit.label({
		Text = "",
		Size = UDim2.new(1, -110, 0, 52),
		Position = UDim2.fromOffset(96, 38),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.ink,
		Font = Kit.bodyFont,
		TextWrapped = true,
		maxText = 17,
	})
	panelLine.Parent = panel

	Net.listen("MentorState", function(d: any)
		if type(d) ~= "table" then
			return
		end
		if d.k == "card" then
			render(d)
			MentorHud.Changed:Fire()
		elseif d.k == "pick" then
			-- after the prologue: one card at a time (the daily card first), never over a menu or a cutscene
			PopupGate.later("mentorPick", function()
				showPicker(d)
				Kit.padFocus(picker, false)
			end)
		elseif d.k == "panel" and d.line then
			comic(d.mentor or 0, d.line)
		end
	end)
	task.defer(function()
		Net.send("MentorOpen") -- the button's label (MENTOR or PICK MENTOR)
	end)
end

return MentorHud
