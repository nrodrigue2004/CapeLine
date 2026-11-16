-- Toasts: short pop-ups in the top middle of the screen (spec: Remote events > Toast; Juice table: level up,
-- loot). Level up is a big gold banner with what just unlocked; a drop is a card in its tier colour (gold
-- and purple drops get a burst); rewards show +Credits and +Renown; Second Wind and a save outage get a
-- line each; beacons, safehouses and the bank get one too; so do incidents, contracts, photos and events. At most 4 show at once; older ones slide out. PLACEHOLDER look until M10 and M11.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progress = require(Shared:WaitForChild("Progress"))
local GearMath = require(Shared:WaitForChild("GearMath"))

local Kit = require(script.Parent.Kit)
local State = require(script.Parent.Parent.State)
local GearScreen = require(script.Parent.GearScreen)
local ContractBoard = require(script.Parent.ContractBoard)

local Toasts = {}

local G = Config.Gear
local gui: ScreenGui
local stack: Frame
local MAX = 4

local function push(text: string, color: Color3, big: boolean?, life: number?)
	local kids = {}
	for _, c in stack:GetChildren() do
		if c:IsA("TextLabel") then
			table.insert(kids, c)
		end
	end
	if #kids >= MAX then
		table.sort(kids, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		kids[1]:Destroy()
	end
	local l = Kit.label({
		Text = text,
		Size = UDim2.new(1, 0, 0, if big then 54 else 34),
		BackgroundColor3 = Kit.color.night,
		BackgroundTransparency = 0.2,
		TextColor3 = color,
		TextStrokeTransparency = 0.4,
		LayoutOrder = math.floor(os.clock() * 100),
		maxText = if big then 40 else 22,
	})
	Kit.round(l, 8)
	Kit.stroke(l, color, if big then 3 else 2)
	l.Parent = stack
	Kit.pulse(l, if big then 0.35 else 0.15)
	task.delay(life or 3.5, function()
		if l.Parent then
			TweenService:Create(l, TweenInfo.new(0.3), { TextTransparency = 1, BackgroundTransparency = 1 })
				:Play()
			task.wait(0.3)
			l:Destroy()
		end
	end)
end

function Toasts.show(data: { [string]: any })
	local id = data.id
	if id == "levelUp" then
		local unlock = Progress.UNLOCKS[data.level]
		push(string.format("LEVEL %d!", data.level), Kit.color.gold, true, 4.5)
		if unlock then
			push("Unlocked: " .. unlock, Kit.color.paper, false, 5)
		end
		push("+1 Skill Point (POWERS)", Kit.color.paper, false, 4)
	elseif id == "reward" then
		push(
			string.format(
				"+%s CREDITS   +%s RENOWN",
				Kit.comma(data.credits or 0),
				Kit.comma(data.renown or 0)
			),
			Kit.color.gold
		)
	elseif id == "loot" and data.piece then
		local piece = data.piece
		local tier = GearMath.tierName(Config, piece)
		local c = G.tiers[tier].color
		local color = Color3.fromRGB(c[1], c[2], c[3])
		if data.kind == "salvaged" then
			push(
				string.format("Stash full: %s became %d Dust", GearScreen.pieceName(piece), data.dust or 0),
				color
			)
		else
			push(
				string.format("%s  (ilvl %d)", GearScreen.pieceName(piece), piece.ilvl),
				color,
				piece.tier >= 4,
				4.5
			)
		end
	elseif id == "secondWind" then
		push("SECOND WIND!", Color3.fromRGB(255, 200, 60), true)
	elseif id == "beacon" then
		push(string.format("BEACON FOUND: %s", string.upper(data.name or "")), Kit.color.gold, true, 4)
		push(
			string.format(
				"Fast travel unlocked (%d / %d). Open the MAP to fly there.",
				data.found or 0,
				data.total or 12
			),
			Kit.color.paper,
			false,
			4.5
		)
	elseif id == "safehouse" then
		push(string.format("Safehouse found: %s", data.name or ""), Color3.fromRGB(120, 230, 150))
	elseif id == "respawnSet" then
		push(
			string.format("You will respawn at %s", data.name or "this safehouse"),
			Color3.fromRGB(120, 230, 150)
		)
	elseif id == "banked" then
		if (data.credits or 0) > 0 then
			push(string.format("Banked %s Credits: safe from PvP", Kit.comma(data.credits)), Kit.color.gold)
		else
			push("Nothing on hand to bank", Kit.color.paper)
		end
	elseif id == "incident" then
		local medal = string.upper(data.medal or "")
		push(
			string.format("%s CLEARED!  %s", string.upper(data.name or "Incident"), medal),
			Kit.color.gold,
			true,
			3.5
		)
	elseif id == "contract" then
		push(
			string.format(
				"CONTRACT DONE: %s  +%s CREDITS  +%s RENOWN%s",
				string.upper(data.name or ""),
				Kit.comma(data.credits or 0),
				Kit.comma(data.renown or 0),
				if data.double then "  (x2)" else ""
			),
			Color3.fromRGB(255, 150, 70),
			true,
			4.5
		)
	elseif id == "contractRefused" then
		push(ContractBoard.REASONS[data.reason or ""] or "You cannot take that contract", Kit.color.paper)
	elseif id == "photo" then
		push("SNAP! Sneak Bot photographed", Kit.color.volt)
	elseif id == "event" then
		push(string.format("EVENT: %s!", string.upper(data.name or "")), Kit.color.gold, true, 5)
		if data.text then
			push(data.text, Kit.color.paper, false, 5)
		end
	elseif id == "eventDone" then
		push(
			string.format(
				"%s DONE!  +%s CREDITS  +%s RENOWN",
				string.upper(data.name or "Event"),
				Kit.comma(data.credits or 0),
				Kit.comma(data.renown or 0)
			),
			Kit.color.gold,
			true,
			4.5
		)
	elseif id == "saveDown" then
		push(
			"Saving is down right now: this session's progress will not be kept",
			Color3.fromRGB(255, 150, 120),
			false,
			10
		)
	end
end

function Toasts.init()
	gui = Kit.screen("Toasts", 8)
	stack = Instance.new("Frame")
	stack.Name = "Stack"
	stack.BackgroundTransparency = 1
	stack.AnchorPoint = Vector2.new(0.5, 0)
	stack.Position = UDim2.new(0.5, 0, 0, 70)
	stack.Size = UDim2.new(0.9, 0, 0, 260)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = stack
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(420, 260)
	limit.Parent = stack
	stack.Parent = gui
	State.Toast:Connect(Toasts.show)
end

return Toasts
