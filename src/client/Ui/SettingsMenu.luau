-- SettingsMenu: the Settings screen (spec: Main menu "Settings"; Accessibility; save "Graphics preset, text
-- size, left-handed, reduce flashing, mute list"). Opens from the gear button on the HUD or the main menu.
-- Every row changes at once on this device and is kept on the account (SettingsClient). Muted players are
-- listed with UNMUTE. PLACEHOLDER look until the art pass: Kit panels.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Kit = require(script.Parent.Kit)
local SettingsClient = require(script.Parent.Parent.Controllers.SettingsClient)
local PvpClient = require(script.Parent.Parent.Controllers.PvpClient)
local QualityController = require(script.Parent.Parent.Controllers.QualityController)

local SettingsMenu = {}

local T = Config.Ui.touchTarget
local gui: ScreenGui
local body: ScrollingFrame
local order = 0

local function clear()
	for _, c in body:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	order = 0
end

local function rowFrame(): Frame
	order += 1
	local f = Kit.frame({
		Size = UDim2.new(1, -8, 0, T + 8),
		LayoutOrder = order,
		BackgroundColor3 = Kit.color.ink,
		BackgroundTransparency = 0.2,
	})
	f.Parent = body
	return f
end

local function label(f: Frame, text: string)
	local l = Kit.label({
		Text = text,
		Size = UDim2.new(0.55, -12, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.paper,
		Font = Kit.bodyFont,
		TextWrapped = true,
		maxText = 16,
	})
	l.Parent = f
end

local function valueText(k: any, v: number): string
	if k.kind == "toggle" then
		return if v == 1 then "ON" else "OFF"
	elseif k.kind == "choice" then
		local name = k.options[v + 1] or "?"
		if k.id == "preset" and v == 0 then
			name ..= " (" .. string.upper(QualityController.name) .. ")"
		end
		return string.upper(name)
	end
	return tostring(v) .. (k.unit or "")
end

local draw: () -> ()

local function settingRow(k: any)
	local f = rowFrame()
	label(f, k.name)
	local v = SettingsClient.get(k.id)
	if k.kind == "range" then
		local minus = Kit.button({
			Text = "-",
			AnchorPoint = Vector2.new(1, 0.5),
			Size = UDim2.fromOffset(T, T - 8),
			Position = UDim2.new(1, -T - 108, 0.5, 0),
			BackgroundColor3 = Kit.color.paper,
		}, function()
			SettingsClient.set(k.id, v - k.step)
			draw()
		end)
		minus.Parent = f
		local val = Kit.label({
			Text = valueText(k, v),
			AnchorPoint = Vector2.new(1, 0.5),
			Size = UDim2.fromOffset(96, T - 8),
			Position = UDim2.new(1, -T - 8, 0.5, 0),
			TextColor3 = Kit.color.gold,
			maxText = 22,
		})
		val.Parent = f
		local plus = Kit.button({
			Text = "+",
			AnchorPoint = Vector2.new(1, 0.5),
			Size = UDim2.fromOffset(T, T - 8),
			Position = UDim2.new(1, -6, 0.5, 0),
			BackgroundColor3 = Kit.color.paper,
		}, function()
			SettingsClient.set(k.id, v + k.step)
			draw()
		end)
		plus.Parent = f
	else
		local b = Kit.button({
			Text = valueText(k, v),
			AnchorPoint = Vector2.new(1, 0.5),
			Size = UDim2.new(0.42, 0, 0, T - 8),
			Position = UDim2.new(1, -6, 0.5, 0),
			BackgroundColor3 = if k.kind == "toggle" and v == 1 then Kit.color.gold else Kit.color.paper,
			maxText = 20,
		}, function()
			if k.kind == "toggle" then
				SettingsClient.set(k.id, 1 - v)
			else
				SettingsClient.set(k.id, (v + 1) % #k.options)
			end
			draw()
		end)
		b.Parent = f
	end
end

local function muteRows()
	order += 1
	local h = Kit.label({
		Text = "MUTED PLAYERS",
		Size = UDim2.new(1, -8, 0, 30),
		LayoutOrder = order,
		TextColor3 = Kit.color.gold,
		maxText = 24,
	})
	h.Parent = body
	local any = false
	for userId in PvpClient.muted do
		any = true
		local f = rowFrame()
		local p = Players:GetPlayerByUserId(userId)
		label(f, if p then p.DisplayName else ("A player not in this server (" .. userId .. ")"))
		local b = Kit.button({
			Text = "UNMUTE",
			AnchorPoint = Vector2.new(1, 0.5),
			Size = UDim2.new(0.3, 0, 0, T - 8),
			Position = UDim2.new(1, -6, 0.5, 0),
			BackgroundColor3 = Kit.color.paper,
		}, function()
			PvpClient.mute(userId, false)
			draw()
		end)
		b.Parent = f
	end
	if not any then
		order += 1
		local e = Kit.label({
			Text = "Nobody muted. Tap a name plate to mute someone.",
			Size = UDim2.new(1, -8, 0, 26),
			LayoutOrder = order,
			TextColor3 = Kit.color.paper,
			Font = Kit.bodyFont,
			maxText = 14,
		})
		e.Parent = body
	end
end

draw = function()
	if not gui.Enabled then
		return
	end
	local y = body.CanvasPosition
	clear()
	for _, k in Config.Settings.keys do
		settingRow(k)
	end
	muteRows()
	body.CanvasPosition = y
end

function SettingsMenu.open()
	Kit.opening("SettingsMenu", gui, SettingsMenu.close)
	gui.Enabled = true
	draw()
end

function SettingsMenu.close()
	gui.Enabled = false
end

function SettingsMenu.isOpen(): boolean
	return gui ~= nil and gui.Enabled
end

function SettingsMenu.init()
	gui = Kit.screen("Settings", 22)
	gui.Enabled = false
	local panel = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.9, 0, 0.88, 0),
		BackgroundColor3 = Kit.color.night,
	})
	Kit.stroke(panel, Kit.color.gold, 3)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(640, 900)
	limit.Parent = panel
	panel.Parent = gui
	local title = Kit.label({
		Text = "SETTINGS",
		Size = UDim2.new(1, -150, 0, 40),
		Position = UDim2.fromOffset(12, 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.color.gold,
		maxText = 34,
	})
	title.Parent = panel
	local close = Kit.button({
		Text = "CLOSE",
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(120, T - 8),
		Position = UDim2.new(1, -10, 0, 8),
		BackgroundColor3 = Kit.color.paper,
	}, SettingsMenu.close)
	close.Parent = panel
	body = Instance.new("ScrollingFrame")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(10, 58)
	body.Size = UDim2.new(1, -20, 1, -68)
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.CanvasSize = UDim2.new()
	body.ScrollBarThickness = 6
	body.Parent = panel
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = body
	QualityController.Changed:Connect(draw)
	PvpClient.MutesChanged:Connect(draw)
end

return SettingsMenu
