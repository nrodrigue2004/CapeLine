-- MainMenu: the menu over the city when a returning player joins (spec: Main menu "Create First, Play,
-- Settings | Create First skips the cinematic for returning players"; First 30 seconds).
-- * A brand-new player never sees it: the hero creator opens at once, then the opening (creator first, lore
--   step 2).
-- * A returning hero (created when the session's first profile came) sees PLAY, SHOP and SETTINGS over the
--   live city; PLAY is one tap. A hero made this session never gets it (it is in the opening).
-- * A new hero on an account that already did the opening (OpeningState createFirst), once made in the
--   creator, sees CREATE FIRST (the Create First path: straight to the city with the rewards) or PLAY THE
--   PROLOGUE (the Ceremony waits on its first beat until then; lore step 3).
-- PLACEHOLDER ART: a Kit panel with the title until the art pass.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Kit = require(script.Parent.Kit)
local SettingsMenu = require(script.Parent.SettingsMenu)
local ShopHud = require(script.Parent.ShopHud)
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
	-- at most once a session; a new hero's Create First may still replace the returning menu (a rejoin
	-- mid-prologue on a returning account: its held ceremony waits for this pick)
	if shown and not (kind == "createFirst" and mode == "returning") then
		return
	end
	shown = true
	mode = kind
	clear()
	if kind == "createFirst" then
		sub.Text = "Your new hero is ready. Go to the city, or play the prologue again."
		add("CREATE FIRST", Kit.color.gold, 1, function()
			StoryClient.createFirst()
			MainMenu.close()
		end)
		add("PLAY THE PROLOGUE", Kit.color.paper, 2, function()
			StoryClient.playPrologue()
			MainMenu.close()
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
	Kit.padFocus(gui) -- a controller starts on the first button
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
	if (Config.Ui.logo or 0) ~= 0 then
		-- the drawn logo over the typed title once it has loaded (Everything Left 85)
		local drawn = Instance.new("ImageLabel")
		drawn.Name = "Logo"
		drawn.BackgroundTransparency = 1
		drawn.Size = UDim2.new(1, -10, 0, 96)
		drawn.Position = UDim2.fromOffset(5, -8)
		drawn.ScaleType = Enum.ScaleType.Fit
		drawn.Image = "rbxassetid://" .. Config.Ui.logo
		drawn.ImageTransparency = 1
		drawn.ZIndex = title.ZIndex + 1
		drawn.Parent = panel
		task.spawn(function()
			pcall(function()
				game:GetService("ContentProvider"):PreloadAsync({ drawn })
			end)
			if drawn.IsLoaded and drawn.Parent then
				drawn.ImageTransparency = 0
				title.TextTransparency = 1
				title.TextStrokeTransparency = 1
			end
		end)
	end
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

	-- a returning hero: the first full profile says it was created already and past its prologue (a hero made
	-- later this session, in the creator, goes on to the opening instead; a rejoin mid-prologue goes back into
	-- it, with no PLAY menu over its ceremony)
	local decided = false
	local function check()
		local p = State.profile
		if shown or decided or type(p.settings) ~= "table" then
			return
		end
		decided = true
		local made = p.created == true or (type(p.created) == "number" and p.created ~= 0)
		if made and p.opening ~= 0 then
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
		-- (a held ceremony has no openingStep: it is not playing until PLAY THE PROLOGUE, fix-flow 2026-11-19)
		if StoryClient.opening.createFirst and StoryClient.held() and StoryClient.opening.step == 1 then
			show("createFirst")
		elseif mode == "createFirst" and not StoryClient.opening.createFirst then
			MainMenu.close()
		end
	end)
end

return MainMenu
