-- WeaponRack: the Weapon Rack screen at a safehouse (nate's hero creator plan, 2026-11-16). Opens from the
-- Rack terminal's prompt. Every weapon by family with its Complexity, what it does and its Mastery; owned
-- ones can be carried (WeaponCarry), Rack ones bought for Credits (WeaponBuy), Exotic ones point to the
-- Robux shop, and the rest say "Coming soon". CUSTOMIZE opens the creator on the weapon step.
-- The server checks everything again (WeaponService).

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local WeaponRules = require(Shared:WaitForChild("WeaponRules"))

local Kit = require(script.Parent.Kit)
local CreatorScreen = require(script.Parent.CreatorScreen)
local State = require(script.Parent.Parent.State)

local WeaponRack = {}

local W = Config.Weapons
local T = Config.Ui.touchTarget
local gui: ScreenGui
local panel: Frame
local body: ScrollingFrame
local footer: TextLabel

local REASONS = {
	rack = "Stand at a Weapon Rack to do that",
	soon = "That weapon is coming soon",
	owned = "You already own that one",
	robux = "That one is in the Robux shop",
	credits = "Not enough Credits",
	weapon = "That weapon does not exist",
}
WeaponRack.REASONS = REASONS

-- the client's copy of what you own (the server checks again)
local function view(): any
	local owned = table.create(4, 0)
	for _, id in State.profile.weaponsOwned or {} do
		local k = id // 32 + 1
		if owned[k] then
			owned[k] = bit32.bor(owned[k], bit32.lshift(1, id % 32))
		end
	end
	return { weaponsOwned = owned, weapons = State.profile.weapons or {} }
end

local function wallet(): number
	local c = State.profile.currency or {}
	return (c.credits or 0) + (c.banked or 0)
end

local function clear()
	for _, c in body:GetChildren() do
		if not c:IsA("UIListLayout") then
			c:Destroy()
		end
	end
end

local order = 0
local function heading(text: string)
	order += 1
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

local function card(title: string, lines: { string }, button: string?, color: Color3?, onClick: (() -> ())?)
	order += 1
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
	if button then
		local b = Kit.button({
			pending = onClick ~= nil,
			Text = button,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(T * 2 + 10, T - 6),
			BackgroundColor3 = color or Kit.color.gold,
			AutoButtonColor = onClick ~= nil,
		}, onClick)
		b.Parent = f
	end
	f.Parent = body
end

local function render()
	clear()
	order = 0
	local pv = view()
	local carried = State.hero.weapon or W.defaultWeapon
	local credits = wallet()
	for _, fam in W.families do
		heading(string.upper(fam.name))
		for _, w in WeaponRules.list(Config) do
			if w.family == fam.id then
				local st = WeaponRules.state(pv, w.id)
				local lvl = WeaponRules.masteryLevel(Config, st.mastery)
				local lines = {
					w.text,
					string.format("Complexity: %s   Mastery %d", W.complexity[w.complexity] or "", lvl),
				}
				local id = w.id
				if not WeaponRules.playable(Config, id) then
					card(string.upper(w.name), lines, "SOON", Kit.color.muted, nil)
				elseif id == carried then
					card(string.upper(w.name), lines, "CARRIED", Kit.color.muted, nil)
				elseif WeaponRules.owned(Config, pv, id) then
					card(string.upper(w.name), lines, "CARRY", nil, function()
						Net.send("WeaponCarry", id)
					end)
				elseif w.robux then
					local row = Config.Shop.products[w.robux]
					card(
						string.upper(w.name),
						lines,
						(if row then row.robux else "?") .. " R$",
						Kit.color.muted,
						nil
					)
				else
					local price = w.price or 0
					card(
						string.upper(w.name),
						lines,
						Kit.comma(price) .. " CR",
						if credits >= price then Kit.color.gold else Kit.color.muted,
						function()
							Net.send("WeaponBuy", id)
						end
					)
				end
			end
		end
	end
	footer.Text = string.format("Credits: %s   Exotic weapons are in the shop (P)", Kit.comma(credits))
end

function WeaponRack.open()
	panel.Visible = true
	render()
end

function WeaponRack.close()
	panel.Visible = false
end

function WeaponRack.isOpen(): boolean
	return panel.Visible
end

function WeaponRack.init()
	gui = Kit.screen("WeaponRack", 6)
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
	limit.MaxSize = Vector2.new(640, 680)
	limit.Parent = panel
	panel.Parent = gui
	local title = Kit.label({
		Text = "WEAPON RACK",
		Size = UDim2.new(1, -(T * 4 + 40), 0, 30),
		Position = UDim2.fromOffset(14, 8),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.gold,
		maxText = 28,
	})
	title.Parent = panel
	local custom = Kit.button({
		Text = "CUSTOMIZE",
		Size = UDim2.fromOffset(T * 3, T - 10),
		Position = UDim2.new(1, -T * 4 - 20, 0, 6),
		BackgroundColor3 = Kit.color.gold,
	}, function()
		WeaponRack.close()
		CreatorScreen.open({ mode = "edit", step = "weapon" })
	end)
	custom.Parent = panel
	local close = Kit.button({
		Text = "X",
		Size = UDim2.fromOffset(T, T - 10),
		Position = UDim2.new(1, -T - 8, 0, 6),
		BackgroundColor3 = Kit.color.paper,
	}, WeaponRack.close)
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
	body = scroll
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
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if player == Players.LocalPlayer and prompt:GetAttribute("Terminal") == "weapons" then
			WeaponRack.open()
		end
	end)
	Net.listen("WeaponResult", function(data)
		if data.ok then
			local w = WeaponRules.get(Config, data.id)
			local name = if w then w.name else "Weapon"
			State.Toast:Fire({
				id = "note",
				text = if data.kind == "buy" then name .. " is yours" else "Carrying " .. name,
			})
		else
			State.Toast:Fire({ id = "note", text = REASONS[data.reason or ""] or "Try again" })
		end
		if panel.Visible then
			render()
		end
	end)
	local function redraw()
		if panel.Visible then
			render()
		end
	end
	State.ProfileChanged:Connect(redraw)
	State.Changed:Connect(redraw)
end

return WeaponRack
