-- LoreCard: a lore page's comic caption card (side-content, 2026-11-19; Config.Lore): a cream caption box with an
-- ink stroke, the district tag, the page's title in Bangers, its lines and who says them. It waits its turn in
-- the popup line (Ui.Popups "lorePage": its life, an X, a tap and Backspace close it). Controllers.LoreClient shows
-- it on a pickup; the Journal's LORE tab shows it again for a page read.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local LorePlan = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LorePlan"))

local Kit = require(script.Parent.Kit)
local Popups = require(script.Parent.Popups)

local LoreCard = {}

local L = Config.Lore
local card: Frame? = nil
local cardTitle: TextLabel? = nil
local cardBody: TextLabel? = nil
local cardBy: TextLabel? = nil
local cardTag: TextLabel? = nil

local function buildCard()
	local gui = Kit.screen("LoreCard", 7)
	local f = Kit.frame({
		Name = "LoreCard",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.12, 0),
		Size = UDim2.new(0.9, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Kit.color.paper,
		Visible = false,
	})
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(460, 400)
	limit.Parent = f
	Kit.stroke(f, Kit.color.ink, 3)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = f
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 4)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = f
	local function line(
		name: string,
		h: number,
		size: number,
		font: Enum.Font,
		color: Color3,
		order: number
	): TextLabel
		local l = Kit.label({
			Name = name,
			Text = "",
			Size = UDim2.new(1, 0, 0, h),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = color,
			Font = font,
			TextWrapped = true,
			TextScaled = false, -- a fixed size so the caption grows down with its lines (AutomaticSize)
			TextSize = size,
			maxText = size,
			ink = false,
		})
		l.LayoutOrder = order
		l.Parent = f
		return l
	end
	cardTag = line("Tag", 16, 14, Kit.bodyFont, Kit.color.red, 1)
	cardTitle = line("Title", 30, 28, Kit.font, Kit.color.ink, 2)
	cardBody = line("Body", 20, 18, Kit.bodyFont, Kit.color.ink, 3)
	cardBy = line("By", 18, 16, Kit.font, Color3.fromRGB(110, 80, 40), 4)
	if cardBy then
		cardBy.TextXAlignment = Enum.TextXAlignment.Right
	end
	f.Parent = gui
	card = f
	Popups.panel("lorePage", function() -- fix-hud's Ui.Dismiss: its X, a tap and Backspace
		return card
	end)
end

local function districtName(id: string): string
	local i = LorePlan.districtIndex(L, id)
	return if i then L.districts[i].name else id
end

-- Show page `bit`'s caption card (it waits its turn in the popup line, Ui.Popups "lorePage")
function LoreCard.show(bit: number)
	local page = LorePlan.page(L, bit)
	if not page then
		return
	end
	if not card then
		buildCard()
	end
	Popups.show("lorePage", function()
		if not (card and cardTitle and cardBody and cardBy and cardTag) then
			return
		end
		cardTag.Text = string.upper(districtName(page.district)) .. "  ·  LORE"
		cardTitle.Text = string.upper(page.title)
		cardBody.Text = table.concat(page.lines, "\n")
		cardBy.Text = "— " .. page.by
		card.Visible = true
	end, function()
		return card ~= nil and card.Visible
	end, function()
		if card then
			card.Visible = false
		end
	end, page.title)
end

return LoreCard
