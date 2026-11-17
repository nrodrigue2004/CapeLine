-- MainMenu: the menu over the city when a returning player joins (spec: Main menu "Create First, Play,
-- Settings | Create First skips the cinematic for returning players"; First 30 seconds).
-- * A brand-new player never sees it: the opening starts at once (the first 30 seconds pillar).
-- * A returning hero (created) sees PLAY, SHOP and SETTINGS over the live city; PLAY is one tap.
-- * A new hero on an account that already did the opening (OpeningState createFirst) sees CREATE FIRST
--   (straight to Suit Up, no cinematic, no disaster) or PLAY THE OPENING (the cinematic, then the run).
-- PLACEHOLDER ART: a Kit panel with the title until the art pass.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local Kit = require(script.Parent.Kit)
local SettingsMenu = require(script.Parent.SettingsMenu)
local ShopHud = require(script.Parent.ShopHud)
local StoryHud = require(script.Parent.StoryHud)
local State = require(script.Parent.Parent.State)
local StoryClient = require(script.Parent.Parent.Controllers.StoryClient)

local MainMenu = {}

local T = Config.Ui.touchTarget

local gui: ScreenGui
local buttons: Frame
local sub: TextLabel
local shown = false -- the menu shows at most once a session
local mode = "" -- "returning" or "createFirst"

local function clear()
	for _, c in buttons:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local function add(text: string, color: Color3, order: number, onClick: () -> ())
	local b = Kit.button({
		Text = text,
		Size = UDim2.new(1, 0, 0, T + 8),
		LayoutOrder = order,
		BackgroundColor3 = color,
		maxText = 30,
	}, onClick)
	b.Parent = buttons
end

function MainMenu.close()
	gui.Enabled = false
end

function MainMenu.isOpen(): boolean
	return gui ~= nil and gui.Enabled
end

local function show(kind: string)
	if shown then
		return
	end
	shown = true
	mode = kind
	clear()
	if kind == "createFirst" then
		sub.Text = "A new hero. Build them now, or play the opening again."
		add("CREATE FIRST", Kit.color.gold, 1, function()
			Net.send("OpeningAct", 3)
			MainMenu.close()
		end)
		add("PLAY THE OPENING", Kit.color.paper, 2, function()
			MainMenu.close()
			StoryHud.playCinematic()
		end)
	else
		sub.Text = "Brightharbor needs you."
		add("PLAY", Kit.color.gold, 1, MainMenu.close)
		add("SHOP", Kit.color.paper, 3, function()
			MainMenu.close()
			ShopHud.open()
		end)
	end
	add("SETTINGS", Kit.color.paper, 4, SettingsMenu.open)
	gui.Enabled = true
end

-- Dev and tests: which menu showed ("" when none has)
function MainMenu.mode(): string
	return mode
end

function MainMenu.init()
	gui = Kit.screen("MainMenu", 20)
	gui.Enabled = false
	local dim = Kit.frame({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Kit.color.ink,
		BackgroundTransparency = 0.45,
		round = false,
	})
	dim.Parent = gui
	local panel = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(380, 150 + 3 * (T + 18)),
		BackgroundColor3 = Kit.color.night,
	})
	Kit.stroke(panel, Kit.color.gold, 3)
	panel.Parent = gui
	Kit.fit(panel, 380, 150 + 3 * (T + 18), 380, 150 + 3 * (T + 18)) -- phone pass: scales down on a short screen
	local title = Kit.label({
		Text = "CAPELINE",
		Size = UDim2.new(1, -20, 0, 70),
		Position = UDim2.fromOffset(10, 10),
		TextColor3 = Kit.color.gold,
		TextStrokeTransparency = 0,
		maxText = 64,
	})
	title.Parent = panel
	sub = Kit.label({
		Text = "",
		Size = UDim2.new(1, -20, 0, 40),
		Position = UDim2.fromOffset(10, 82),
		TextColor3 = Kit.color.paper,
		Font = Kit.bodyFont,
		TextWrapped = true,
		maxText = 16,
	})
	sub.Parent = panel
	buttons = Instance.new("Frame")
	buttons.BackgroundTransparency = 1
	buttons.Position = UDim2.fromOffset(20, 130)
	buttons.Size = UDim2.new(1, -40, 1, -140)
	buttons.Parent = panel
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 10)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = buttons

	-- a returning hero: the first full profile says it was created already
	local function check()
		local p = State.profile
		if shown or type(p.settings) ~= "table" then
			return
		end
		if p.created == true or (type(p.created) == "number" and p.created ~= 0) then
			show("returning")
		end
	end
	State.ProfileChanged:Connect(check)
	check()
	-- a new hero on a returning account
	StoryClient.Changed:Connect(function(what)
		if what ~= "opening" then
			return
		end
		if StoryClient.opening.createFirst and StoryClient.openingStep() == "leap" then
			show("createFirst")
		elseif mode == "createFirst" and StoryClient.openingStep() ~= "leap" then
			MainMenu.close()
		end
	end)
end

return MainMenu
