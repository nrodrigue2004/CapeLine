-- TaskForceHud: the Task Force board (spec: Hero MMO features > Task forces; H4). Opens from the TASK FORCE
-- button (or K), and from the Task Force prompt on every safehouse's Contract Board terminal. Shows your
-- side's task forces (OPEN A SQUAD when you may start one), your squad (START, LOCK to friends, LEAVE),
-- LOOKING (the server puts you in the fullest open squad), every open squad with JOIN, and REJOIN when you
-- left a run less than 3 minutes ago. Between legs of a run it shows the comic panel.
-- PLACEHOLDER look until the UI pass; PLACEHOLDER CONTENT: the panels between legs are a title card until
-- the lore thread fills them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local Kit = require(script.Parent.Kit)
local InputController = require(script.Parent.Parent.Controllers.InputController)

local TaskForceHud = {}

local TF = Config.TaskForce
local T = Config.Ui.touchTarget
local ACT = { open = 1, join = 2, leave = 3, start = 4, lock = 5, rejoin = 6 }
local REASONS = {
	level = "Task forces open at level " .. TF.floor .. " once Act 1 is done",
	none = "No open squad for you right now: open one",
	full = "Too many missions running: try again in a minute",
	busy = "Finish what you are doing first",
}

local gui: ScreenGui
local panel: Frame
local body: Frame
local footer: TextLabel
local card: Frame
local cardTitle: TextLabel
local cardSub: TextLabel
local board: { [string]: any } = {}
local asked = 0 -- each TaskForceList ask; the board's answer clears it (0: none waiting)

local function clear()
	for _, c in body:GetChildren() do
		if not c:IsA("UIListLayout") then
			c:Destroy()
		end
	end
end

local function line(text: string, order: number, color: Color3?)
	local l = Kit.label({
		Text = text,
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color or Kit.color.gold,
		LayoutOrder = order,
		maxText = 18,
	})
	l.Parent = body
end

local function row(order: number, title: string, sub: string, buttons: { { any } }) -- { label, colour, onClick }
	local f = Kit.frame({
		Size = UDim2.new(1, 0, 0, 54),
		BackgroundColor3 = Kit.color.paper,
		LayoutOrder = order,
	})
	local t = Kit.label({
		Text = title,
		Size = UDim2.new(1, -(#buttons * (T * 2 + 8) + 20), 0, 24),
		Position = UDim2.fromOffset(10, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		maxText = 18,
	})
	t.Parent = f
	local s = Kit.label({
		Text = sub,
		Size = UDim2.new(1, -(#buttons * (T * 2 + 8) + 20), 0, 18),
		Position = UDim2.fromOffset(10, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Kit.bodyFont,
		TextColor3 = Kit.color.ink,
		maxText = 12,
	})
	s.Parent = f
	for i, b in buttons do
		local btn = Kit.button({
			pending = true,
			Text = b[1],
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10 - (i - 1) * (T * 2 + 8), 0.5, 0),
			Size = UDim2.fromOffset(T * 2, T - 6),
			BackgroundColor3 = b[2],
		}, b[3])
		btn.Parent = f
	end
	f.Parent = body
end

local function render()
	clear()
	local mine = board.mine
	if board.rejoin then
		row(1, "YOUR RUN", "You left a task force less than 3 minutes ago", {
			{
				"REJOIN",
				Kit.color.gold,
				function()
					Net.send("TaskForceJoin", ACT.rejoin, 0)
				end,
			},
		})
	end
	line("TASK FORCES", 2)
	for i, t in TF.list do
		local can = board.starts and board.starts[i]
		row(
			2 + i,
			string.upper(t.name),
			string.format(
				"%d missions in a row   level %d+   1 to %d players",
				#t.legs,
				TF.floor,
				TF.maxPlayers
			),
			if can and not mine
				then {
					{
						"OPEN SQUAD",
						Kit.color.gold,
						function()
							Net.send("TaskForceJoin", ACT.open, i)
						end,
					},
				}
				else {}
		)
	end
	if mine then
		local t = TF.list[mine.tf]
		line("YOUR SQUAD", 10)
		local buttons = {
			{
				"LEAVE",
				Kit.color.muted,
				function()
					Net.send("TaskForceJoin", ACT.leave, 0)
				end,
			},
		}
		if mine.leader then
			table.insert(buttons, 1, {
				if mine.locked then "UNLOCK" else "FRIENDS",
				Kit.color.paper,
				function()
					Net.send("TaskForceJoin", ACT.lock, 0)
				end,
			})
			table.insert(buttons, 1, {
				"START",
				Kit.color.gold,
				function()
					Net.send("TaskForceJoin", ACT.start, 0)
				end,
			})
		end
		row(
			11,
			string.upper(t and t.name or ""),
			string.format(
				"%d of %d heroes%s",
				mine.n,
				TF.maxPlayers,
				if mine.locked then "   friends only" else ""
			),
			buttons
		)
	else
		row(10, "LOOKING", "Join the fullest open squad on your side", {
			{
				"LOOKING",
				Kit.color.gold,
				function()
					Net.send("TaskForceLook", true)
				end,
			},
		})
	end
	line("OPEN SQUADS", 20)
	local any = false
	for i, l in board.lobbies or {} do
		local t = TF.list[l.tf]
		if t and not (mine and mine.id == l.id) then
			any = true
			row(
				20 + i,
				string.upper(t.name),
				string.format(
					"Led by %s   %d of %d%s",
					l.leader,
					l.n,
					TF.maxPlayers,
					if l.locked then "   friends only" else ""
				),
				if l.can and not mine
					then {
						{
							"JOIN",
							Kit.color.gold,
							function()
								Net.send("TaskForceJoin", ACT.join, l.id)
							end,
						},
					}
					else {}
			)
		end
	end
	if not any then
		line("None right now", 21, Kit.color.muted)
	end
	footer.Text = "Sidekicking: lower levels are raised to the top level minus 1 inside the run"
end

-- Ask for the board: the last board shows meanwhile, or the loading note; no answer in 5 s shows the error
-- note with RETRY (spec: every screen has its loading and error states)
local function ask()
	asked += 1
	local mine = asked
	if next(board) == nil then
		clear()
		Kit.stateNote(body, "loading", "Finding task forces...")
		footer.Text = ""
	end
	Net.send("TaskForceList")
	task.delay(5, function()
		if asked == mine and panel.Visible and next(board) == nil then
			clear()
			Kit.stateNote(body, "error", "The board did not answer. Try again in a moment.", ask)
		end
	end)
end

function TaskForceHud.open()
	Kit.opening("TaskForceHud", panel, TaskForceHud.close, true)
	panel.Visible = true
	if next(board) ~= nil then
		render()
	end
	ask()
end

function TaskForceHud.close()
	panel.Visible = false
end

function TaskForceHud.isOpen(): boolean
	return panel.Visible
end

-- PLACEHOLDER CONTENT: lore thread to fill. The comic panel between legs is a title card for now.
local function showPanel(m: { [string]: any })
	local t = TF.list[m.tf or 0]
	cardTitle.Text = string.upper(t and t.name or "TASK FORCE")
	cardSub.Text = string.format("MISSION %d OF %d", m.leg or 1, m.legs or 1)
	card.Visible = true
	task.delay(TF.panelTime, function()
		card.Visible = false
	end)
end

function TaskForceHud.init()
	gui = Kit.screen("TaskForceHud", 6)
	panel = Kit.frame({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.9, 0, 0.86, 0),
		BackgroundColor3 = Kit.color.night,
		BackgroundTransparency = 0.05,
		Visible = false,
	})
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(640, 660)
	limit.Parent = panel
	panel.Parent = gui
	local title = Kit.label({
		Text = "TASK FORCE BOARD",
		Size = UDim2.new(1, -80, 0, 30),
		Position = UDim2.fromOffset(14, 8),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.gold,
		maxText = 28,
	})
	title.Parent = panel
	local close = Kit.button({
		Text = "X",
		Size = UDim2.fromOffset(T, T - 10),
		Position = UDim2.new(1, -T - 8, 0, 6),
		BackgroundColor3 = Kit.color.paper,
	}, TaskForceHud.close)
	close.Parent = panel
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(14, 48)
	scroll.Size = UDim2.new(1, -28, 1, -88)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollBarThickness = 6
	scroll.Parent = panel
	body = scroll :: any
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = body
	footer = Kit.label({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -28, 0, 20),
		TextColor3 = Kit.color.paper,
		Font = Kit.bodyFont,
		maxText = 13,
	})
	footer.Parent = panel
	-- the menu button (top left, beside Settings)
	local open = Kit.button({
		Name = "TaskForceButton",
		Text = "TASK FORCE",
		Size = UDim2.fromOffset(T * 2 + 20, T - 10),
		Position = UDim2.fromOffset(Config.Ui.safe + 258, Config.Ui.safe + T),
		BackgroundColor3 = Kit.color.paper,
	}, function()
		if panel.Visible then
			TaskForceHud.close()
		else
			TaskForceHud.open()
		end
	end)
	Kit.dock(open, "TaskForce", 12) -- the top row (or its MORE drawer), after SETTINGS
	-- the comic panel between legs
	card = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(420, 150),
		BackgroundColor3 = Kit.color.paper,
		Visible = false,
	})
	Kit.stroke(card, Kit.color.ink, 4)
	card.Parent = gui
	cardTitle = Kit.label({
		Text = "",
		Size = UDim2.new(1, -20, 0, 56),
		Position = UDim2.fromOffset(10, 22),
		TextColor3 = Kit.color.ink,
		maxText = 40,
	})
	cardTitle.Parent = card
	cardSub = Kit.label({
		Text = "",
		Size = UDim2.new(1, -20, 0, 34),
		Position = UDim2.fromOffset(10, 88),
		TextColor3 = Kit.color.ink,
		maxText = 26,
	})
	cardSub.Parent = card

	Net.listen("TaskForceBoard", function(data: any)
		if type(data) ~= "table" then
			return
		end
		board = data
		asked = 0
		if data.open and not panel.Visible then
			Kit.opening("TaskForceHud", panel, TaskForceHud.close, true)
			panel.Visible = true
		end
		if panel.Visible then
			render()
		end
	end)
	Net.listen("MissionState", function(m: any)
		if type(m) == "table" and m.panel then
			panel.Visible = false
			showPanel(m)
		elseif type(m) == "table" and m.num and m.num > 0 then
			panel.Visible = false -- in a run: the board closes
		end
	end)
	Net.listen("Toast", function(data: any)
		if type(data) == "table" and data.id == "taskForce" then
			footer.Text = REASONS[data.reason or ""] or REASONS.busy
		end
	end)
	InputController.Pressed:Connect(function(action: string)
		if action == "TaskForce" then
			if panel.Visible then
				TaskForceHud.close()
			else
				TaskForceHud.open()
			end
		end
	end)
end

return TaskForceHud
