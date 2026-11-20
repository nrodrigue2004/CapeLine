-- HelpHud (Everything Left 86): HOW TO PLAY, a page for each deeper system (moving, fighting, block and break,
-- powers and borrowing, gear, the Hero Pass), opened from the MENU drawer. Fixed lines from Config.Ui.help (no
-- free text); the tabs down the left, the page on the right; fits a phone (Kit.fit) and closes with X.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Kit = require(script.Parent.Kit)

local HelpHud = {}

local T = Config.Ui.touchTarget
local PAGES = Config.Ui.help
local W, H = 520, 340
local panel: Frame
local tabs: { TextButton } = {}
local body: Frame
local current = 1

local function show(i: number)
	current = i
	for k, b in tabs do
		b.BackgroundColor3 = if k == i then Kit.color.gold else Kit.color.paper
	end
	for _, c in body:GetChildren() do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	local page = PAGES[i]
	local head = Kit.label({
		Text = page.title,
		Size = UDim2.new(1, -8, 0, 34),
		Position = UDim2.fromOffset(4, 0),
		TextColor3 = Kit.color.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		maxText = 30,
	})
	head.Parent = body
	for n, line in page.lines do
		local l = Kit.label({
			Text = line,
			Size = UDim2.new(1, -8, 0, 56),
			Position = UDim2.fromOffset(4, 40 + (n - 1) * 60),
			TextColor3 = Kit.color.paper,
			Font = Kit.bodyFont,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			maxText = 18,
		})
		l.Parent = body
	end
end

function HelpHud.open(page: number?)
	Kit.opening("HelpHud", panel, HelpHud.close, true)
	show(page or current)
	panel.Visible = true
end

function HelpHud.close()
	panel.Visible = false
end

function HelpHud.init()
	local gui = Kit.screen("HelpHud", 6)
	panel = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(W, H + 50),
		BackgroundColor3 = Kit.color.night,
		Visible = false,
	})
	Kit.stroke(panel, Kit.color.gold, 3)
	Kit.fit(panel, W, H + 50, W, H + 50) -- phone pass: draws smaller on a short screen
	panel.Parent = gui
	local title = Kit.label({
		Text = "HOW TO PLAY",
		Size = UDim2.new(1, -2 * (T + 14), 0, 40),
		Position = UDim2.fromOffset(12, 6),
		TextColor3 = Kit.color.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		maxText = 32,
	})
	title.Parent = panel
	local close = Kit.button({
		Text = "X",
		Size = UDim2.fromOffset(T, T - 6),
		Position = UDim2.new(1, -T - 8, 0, 6),
		BackgroundColor3 = Kit.color.paper,
	}, HelpHud.close)
	close.Parent = panel
	local tabH = math.floor((H - 10) / #PAGES)
	for i, page in PAGES do
		local b = Kit.button({
			Text = page.title,
			Size = UDim2.fromOffset(130, tabH - 6),
			Position = UDim2.fromOffset(10, 50 + (i - 1) * tabH),
			BackgroundColor3 = Kit.color.paper,
		}, function()
			show(i)
		end)
		b.Parent = panel
		tabs[i] = b
	end
	body = Instance.new("Frame")
	body.Name = "Page"
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(152, 50)
	body.Size = UDim2.new(1, -164, 1, -60)
	body.Parent = panel
	local open = Kit.button({
		Name = "HelpButton",
		Text = "HOW TO PLAY",
		Size = UDim2.fromOffset(T * 3, T - 10),
		BackgroundColor3 = Kit.color.paper,
	}, function()
		if panel.Visible then
			HelpHud.close()
		else
			HelpHud.open()
		end
	end)
	Kit.dock(open, "Help", 19) -- the MENU drawer, after BOARDS
end

return HelpHud
