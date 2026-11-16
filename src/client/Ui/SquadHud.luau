-- SquadHud: squads on screen (spec: Squads "Up to 4 players, shared incident rewards, squad emblem, squad
-- ping"; Squad.Invite, Squad.Accept, Squad.Leave). PLACEHOLDER look until the art pass: Kit panels.
-- * The squad list under the radar: each member's name, level and class in their slot colour, with the
--   leader's emblem on top.
-- * SQUAD opens a panel: members (KICK for the leader), LEAVE, and INVITE next to everyone else in the
--   server who is not in a squad. Empty state when you are alone in the server.
-- * An invite card with JOIN and NO for 30 s (a countdown bar).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Kit = require(script.Parent.Kit)
local SquadClient = require(script.Parent.Parent.Controllers.SquadClient)

local SquadHud = {}

local Q = Config.Squad
local T = Config.Ui.touchTarget
local me = Players.LocalPlayer

local gui: ScreenGui
local list: Frame
local panel: Frame
local body: ScrollingFrame
local card: Frame
local cardText: TextLabel
local cardBar: Frame
local cardUntil = 0
local cardLife = 30

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

function SquadHud.slotColor(slot: number?): Color3
	return rgb(Q.colors[slot or 1] or Q.colors[1])
end

local function drawList()
	for _, c in list:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local st = SquadClient.state
	list.Visible = SquadClient.inSquad()
	if not list.Visible then
		return
	end
	local e = st.emblem
	local head = Kit.label({
		Text = (if e then e.glyph .. "  " else "") .. "SQUAD",
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = 0,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = if e then rgb(e.color) else Kit.color.gold,
		TextStrokeTransparency = 0.3,
		maxText = 16,
	})
	head.Parent = list
	for _, m in st.members do
		if m.userId ~= me.UserId then
			local l = Kit.label({
				Text = string.format(
					"%s%s  Lv %d",
					if m.userId == st.leader then "★ " else "",
					m.name,
					m.level
				),
				Size = UDim2.new(1, 0, 0, 18),
				LayoutOrder = m.slot,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = SquadHud.slotColor(m.slot),
				TextStrokeTransparency = 0.3,
				Font = Kit.bodyFont,
				maxText = 13,
			})
			l.Parent = list
		end
	end
end

local order = 0
local function row(text: string, button: string?, onClick: (() -> ())?, color: Color3?)
	order += 1
	local f = Kit.frame({
		Size = UDim2.new(1, -8, 0, T),
		LayoutOrder = order,
		BackgroundColor3 = Kit.color.ink,
		BackgroundTransparency = 0.2,
	})
	local l = Kit.label({
		Text = text,
		Size = UDim2.new(0.62, -10, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color or Kit.color.paper,
		Font = Kit.bodyFont,
		maxText = 15,
	})
	l.Parent = f
	if button and onClick then
		local b = Kit.button({
			Text = button,
			pending = true,
			AnchorPoint = Vector2.new(1, 0.5),
			Size = UDim2.new(0.36, 0, 0, T - 10),
			Position = UDim2.new(1, -6, 0.5, 0),
		}, onClick)
		b.Parent = f
	end
	f.Parent = body
end

local function note(text: string)
	order += 1
	local l = Kit.label({
		Text = text,
		Size = UDim2.new(1, -8, 0, 28),
		LayoutOrder = order,
		TextColor3 = Kit.color.paper,
		Font = Kit.bodyFont,
		TextWrapped = true,
		maxText = 14,
	})
	l.Parent = body
end

local function drawPanel()
	if not panel.Visible then
		return
	end
	for _, c in body:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	order = 0
	local st = SquadClient.state
	if SquadClient.inSquad() then
		for _, m in st.members do
			local leaderMark = if m.userId == st.leader then "★ " else ""
			local text = string.format("%s%s  Lv %d %s", leaderMark, m.name, m.level, m.classId)
			if SquadClient.isLeader() and m.userId ~= me.UserId then
				row(text, "KICK", function()
					SquadClient.kick(m.userId)
				end, SquadHud.slotColor(m.slot))
			else
				row(text, nil, nil, SquadHud.slotColor(m.slot))
			end
		end
		row("Leave this squad", "LEAVE", function()
			SquadClient.leave()
		end)
		note(
			"Squadmates share incident rewards, can't hurt each other, see your pings anywhere and join your missions."
		)
	else
		note("You are not in a squad. Invite up to 3 players.")
	end
	order += 1
	local h = Kit.label({
		Text = "IN THIS SERVER",
		Size = UDim2.new(1, -8, 0, 26),
		LayoutOrder = order,
		TextColor3 = Kit.color.gold,
		maxText = 20,
	})
	h.Parent = body
	local any = false
	local full = #(st.members or {}) >= Q.max
	for _, p in Players:GetPlayers() do
		if p ~= me and p:GetAttribute("Squad") == nil then
			any = true
			local name = p:GetAttribute("HeroName")
			local text = (if typeof(name) == "string" and name ~= "" then name .. "  @" else "@")
				.. p.DisplayName
			if full then
				row(text, nil, nil)
			else
				row(text, "INVITE", function()
					SquadClient.invite(p.UserId)
				end)
			end
		end
	end
	if not any then
		note("Nobody else is free to invite right now.")
	end
end

function SquadHud.open()
	panel.Visible = true
	drawPanel()
end

function SquadHud.close()
	panel.Visible = false
end

function SquadHud.toggle()
	if panel.Visible then
		SquadHud.close()
	else
		SquadHud.open()
	end
end

local function showInvite(inv: { [string]: any })
	cardText.Text = string.format(
		"%s asks you to join their squad (%d/%d)",
		inv.name or "Someone",
		(inv.size or 1) + 1,
		Q.max
	)
	cardLife = inv.life or Q.inviteLife
	cardUntil = os.clock() + cardLife
	card.Visible = true
end

function SquadHud.init()
	gui = Kit.screen("Squad", 9)
	list = Instance.new("Frame")
	list.Name = "SquadList"
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(Config.Ui.safe, Config.Ui.safe + 310)
	list.Size = UDim2.fromOffset(200, 100)
	list.Visible = false
	local ll = Instance.new("UIListLayout")
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Parent = list
	list.Parent = gui

	panel = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.8, 0, 0.8, 0),
		BackgroundColor3 = Kit.color.night,
		Visible = false,
	})
	Kit.stroke(panel, Kit.color.gold, 3)
	local lim = Instance.new("UISizeConstraint")
	lim.MaxSize = Vector2.new(520, 640)
	lim.Parent = panel
	panel.Parent = gui
	local title = Kit.label({
		Text = "SQUAD",
		Size = UDim2.new(1, -150, 0, 38),
		Position = UDim2.fromOffset(12, 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.gold,
		maxText = 32,
	})
	title.Parent = panel
	local close = Kit.button({
		Text = "CLOSE",
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(120, T - 8),
		Position = UDim2.new(1, -10, 0, 8),
		BackgroundColor3 = Kit.color.paper,
	}, SquadHud.close)
	close.Parent = panel
	body = Instance.new("ScrollingFrame")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(10, 56)
	body.Size = UDim2.new(1, -20, 1, -64)
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.CanvasSize = UDim2.new()
	body.ScrollBarThickness = 6
	body.Parent = panel
	local bl = Instance.new("UIListLayout")
	bl.Padding = UDim.new(0, 6)
	bl.SortOrder = Enum.SortOrder.LayoutOrder
	bl.Parent = body

	-- the invite card
	card = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 150),
		Size = UDim2.fromOffset(380, 130),
		BackgroundColor3 = Kit.color.night,
		Visible = false,
	})
	Kit.stroke(card, Kit.color.gold, 3)
	card.Parent = gui
	cardText = Kit.label({
		Text = "",
		Size = UDim2.new(1, -20, 0, 50),
		Position = UDim2.fromOffset(10, 6),
		TextColor3 = Kit.color.paper,
		Font = Kit.bodyFont,
		TextWrapped = true,
		maxText = 17,
	})
	cardText.Parent = card
	local join = Kit.button({
		Text = "JOIN",
		Size = UDim2.new(0.5, -15, 0, T - 6),
		Position = UDim2.new(0, 10, 1, -T - 4),
	}, function()
		card.Visible = false
		SquadClient.answer(true)
	end)
	join.Parent = card
	local no = Kit.button({
		Text = "NO",
		Size = UDim2.new(0.5, -15, 0, T - 6),
		Position = UDim2.new(0.5, 5, 1, -T - 4),
		BackgroundColor3 = Kit.color.paper,
	}, function()
		card.Visible = false
		SquadClient.answer(false)
	end)
	no.Parent = card
	cardBar = Kit.frame({
		Size = UDim2.new(1, -20, 0, 4),
		Position = UDim2.fromOffset(10, 60),
		BackgroundColor3 = Kit.color.gold,
		round = false,
	})
	cardBar.Parent = card

	SquadClient.Changed:Connect(function()
		drawList()
		drawPanel()
	end)
	SquadClient.Invited:Connect(showInvite)
	Players.PlayerAdded:Connect(drawPanel)
	Players.PlayerRemoving:Connect(function()
		task.defer(drawPanel)
	end)
	RunService.Heartbeat:Connect(function()
		if card.Visible then
			local left = cardUntil - os.clock()
			if left <= 0 then
				card.Visible = false
			else
				cardBar.Size = UDim2.new((1 * left / cardLife), -20, 0, 4)
			end
		end
	end)
	drawList()
end

return SquadHud
