-- ContractBoard: the Contract Board screen at a safehouse (spec: Radiant contracts; Contract.Accept,
-- Contract.Abandon). Opens when the server sends the board (the safehouse terminal is the check). Three
-- offers for the hero's side with their pay at the zone level (x2 for the first 5 each day), and the
-- accepted contracts (up to 3) with their progress and an Abandon button.
-- PLACEHOLDER look until the UI pass (M10).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local Kit = require(script.Parent.Kit)
local State = require(script.Parent.Parent.State)
local WorldClient = require(script.Parent.Parent.Controllers.WorldClient)

local ContractBoard = {}

local CC = Config.Contracts
local T = Config.Ui.touchTarget
local gui: ScreenGui
local panel: Frame
local body: Frame
local footer: TextLabel

local REASONS = {
	level = "Contracts open at level " .. CC.board.minLevel,
	gone = "That offer changed: here are the new ones",
	side = "That contract is for the other side",
	full = "You already have 3 contracts: finish or abandon one",
	same = "You already have one of those",
	board = "Stand at the Contract Board to take a contract",
}
ContractBoard.REASONS = REASONS

local function clear()
	for _, c in body:GetChildren() do
		if not c:IsA("UIListLayout") then
			c:Destroy()
		end
	end
end

local function heading(text: string, order: number)
	local l = Kit.label({
		Text = text,
		Size = UDim2.new(1, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.gold,
		LayoutOrder = order,
		maxText = 20,
	})
	l.Parent = body
end

local function card(
	order: number,
	title: string,
	lines: { string },
	button: string?,
	color: Color3?,
	onClick: (() -> ())?
)
	local f = Kit.frame({
		Size = UDim2.new(1, 0, 0, 30 + #lines * 18 + 6),
		BackgroundColor3 = Kit.color.paper,
		LayoutOrder = order,
	})
	local t = Kit.label({
		Text = title,
		Size = UDim2.new(1, -(T * 2 + 30), 0, 24),
		Position = UDim2.fromOffset(10, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		maxText = 20,
	})
	t.Parent = f
	for i, line in lines do
		local l = Kit.label({
			Text = line,
			Size = UDim2.new(1, -(T * 2 + 30), 0, 16),
			Position = UDim2.fromOffset(10, 28 + (i - 1) * 18),
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Kit.bodyFont,
			TextColor3 = Kit.color.ink,
			maxText = 13,
		})
		l.Parent = f
	end
	if button and onClick then
		local b = Kit.button({
			Text = button,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(T * 2, T - 6),
			BackgroundColor3 = color or Kit.color.gold,
		}, onClick)
		b.Parent = f
	end
	f.Parent = body
end

local function render(board: { [string]: any })
	clear()
	local first = Config.Economy.bonus.firstContracts
	local done = board.done or 0
	heading("OFFERS", 1)
	for i, o in board.offers or {} do
		local id = WorldClient.contractByNum[o[1]]
		local def = id and CC.types[id]
		if def then
			local pay = string.format(
				"+%s Credits   +%s Renown   (zone level %d)",
				Kit.comma(o[3]),
				Kit.comma(o[4]),
				o[2]
			)
			local taken = o[5] == 1
			card(
				1 + i,
				string.upper(def.name),
				{ def.text, pay },
				if taken then nil else "ACCEPT",
				nil,
				if taken
					then nil
					else function()
						Net.send("ContractAccept", i)
					end
			)
		end
	end
	heading("YOUR CONTRACTS", 10)
	if #(board.active or {}) == 0 then
		local l = Kit.label({
			Text = "None yet: accept one above",
			Size = UDim2.new(1, 0, 0, 18),
			TextColor3 = Kit.color.muted,
			Font = Kit.bodyFont,
			LayoutOrder = 11,
			maxText = 13,
		})
		l.Parent = body
	end
	for i, a in board.active or {} do
		local id = WorldClient.contractByNum[a[1]]
		local def = id and CC.types[id]
		if def then
			card(
				10 + i,
				string.upper(def.name),
				{ def.text, string.format("Progress %d / %d", a[2], a[3]) },
				"ABANDON",
				Kit.color.muted,
				function()
					Net.send("ContractAbandon", i) -- the server sends the board back
				end
			)
		end
	end
	footer.Text = if done < first
		then string.format("Double pay: %d of your first %d contracts today left", first - done, first)
		else string.format("%d contracts done today", done)
end

function ContractBoard.open(board: { [string]: any })
	panel.Visible = true
	render(board)
end

function ContractBoard.close()
	panel.Visible = false
end

function ContractBoard.isOpen(): boolean
	return panel.Visible
end

function ContractBoard.init()
	gui = Kit.screen("ContractBoard", 6)
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
	limit.MaxSize = Vector2.new(620, 640)
	limit.Parent = panel
	panel.Parent = gui
	local title = Kit.label({
		Text = "CONTRACT BOARD",
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
	}, ContractBoard.close)
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
		maxText = 14,
	})
	footer.Parent = panel
	WorldClient.Board:Connect(ContractBoard.open)
	State.Toast:Connect(function(data)
		if data.id == "contract" and panel.Visible then
			ContractBoard.close()
		end
	end)
end

return ContractBoard
