-- SettingsMenu: the Settings screen (spec: Main menu "Settings"; Accessibility; save "Graphics preset, text
-- size, left-handed, reduce flashing, mute list"). Opens from the gear button on the HUD or the main menu.
-- Every row changes at once on this device and is kept on the account (SettingsClient). Muted players are
-- listed with UNMUTE. PLACEHOLDER look until the art pass: Kit panels.
-- WP10 (gap G12): the REWARDS rows at the bottom: the group piece (only while Config.Promo.group.id is set:
-- CHECK asks the server) and the code box (only while a code is live). The box keeps upper-case letters and
-- digits only, at most Config.Promo.maxLength, as you type; REDEEM (or Enter) sends it to the server, which
-- matches it against the fixed list. The box lives on this screen only: it is never shown to anyone else,
-- and the answer is one fixed line under the box (plus the usual NEW LOOK PIECE toast), never the text.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local PromoRules = require(Shared:WaitForChild("PromoRules"))

local Kit = require(script.Parent.Kit)
local SettingsClient = require(script.Parent.Parent.Controllers.SettingsClient)
local PvpClient = require(script.Parent.Parent.Controllers.PvpClient)
local QualityController = require(script.Parent.Parent.Controllers.QualityController)

local SettingsMenu = {}

local T = Config.Ui.touchTarget
local gui: ScreenGui
local body: ScrollingFrame
local order = 0
-- WP10: the REWARDS rows (PromoState from the server), the last answer's line and what is in the code box
local promo: { [string]: any }? = nil
local promoNote: { text: string, good: boolean }? = nil
local typed = ""

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

-- WP10: every answer is one of these fixed lines (the typed text is never shown back)
local CODE_NOTES: { [string]: string } = {
	ok = "CODE ACCEPTED! NEW LOOK PIECE: %s",
	owned = "Code accepted. You already own the %s.",
	used = "You already used that code.",
	unknown = "That is not one of our codes. Check the spelling.",
	bad = "Codes are 3 to 12 letters and numbers.",
	expired = "That code has ended.",
	notyet = "That code is not live yet.",
	wait = "Too many tries. Wait %s and try again.",
	save = "Saving is down right now. Try again later.",
	off = "Codes are off right now.",
}
local GROUP_NOTES: { [string]: string } = {
	ok = "THANKS FOR JOINING! NEW LOOK PIECE: %s",
	owned = "Thanks for joining! You already own the %s.",
	claimed = "You already have the group reward.",
	notMember = "Join %s from the game page, then tap CHECK.",
	error = "Could not reach Roblox. Try again soon.",
	wait = "Checked a moment ago. Try again in %s.",
	save = "Saving is down right now. Try again later.",
	off = "The group reward is off right now.",
}

local function noteFor(r: { [string]: any }): (string, boolean)
	local notes = if r.kind == "group" then GROUP_NOTES else CODE_NOTES
	local line = notes[r.reason or ""] or "Try again soon."
	local good = r.reason == "ok" or r.reason == "owned"
	if r.reason == "wait" then
		return string.format(line, Kit.time(r.wait or 60)), false
	elseif r.reason == "notMember" then
		return string.format(line, (promo and promo.group and promo.group.name) or "the group"), false
	end
	if string.find(line, "%s", 1, true) then
		line = string.format(line, string.upper(r.piece or "a look piece"))
	end
	return line, good
end

-- Send what is in the box (true when there was a code to send)
local function sendCode(): boolean
	local code = PromoRules.typed(Config, typed)
	if #code == 0 then
		return false
	end
	typed = ""
	Net.send("PromoRedeem", code)
	return true
end

local function promoRows()
	local p = promo
	if not p or not p.on or (not p.group and (p.codes or 0) == 0) then
		return
	end
	order += 1
	local h = Kit.label({
		Name = "PromoHead",
		Text = "REWARDS",
		Size = UDim2.new(1, -8, 0, 30),
		LayoutOrder = order,
		TextColor3 = Kit.color.gold,
		maxText = 24,
	})
	h.Parent = body
	if p.group then
		local f = rowFrame()
		f.Name = "PromoGroup"
		label(f, string.format("JOIN THE GROUP: FREE %s", string.upper(p.group.piece or "")))
		local b = Kit.button({
			Name = "Check",
			Text = if p.group.claimed then "CLAIMED" else "CHECK",
			AnchorPoint = Vector2.new(1, 0.5),
			Size = UDim2.new(0.42, 0, 0, T - 8),
			Position = UDim2.new(1, -6, 0.5, 0),
			BackgroundColor3 = if p.group.claimed then Kit.color.paper else Kit.color.gold,
			pending = not p.group.claimed,
			maxText = 20,
		}, function()
			if not p.group.claimed then
				Net.send("PromoGroup")
			end
		end)
		b.Parent = f
	end
	if (p.codes or 0) > 0 then
		local f = rowFrame()
		f.Name = "PromoCode"
		local box = Instance.new("TextBox")
		box.Name = "CodeBox"
		box.ClearTextOnFocus = false
		box.Text = typed
		box.PlaceholderText = "ENTER CODE"
		box.PlaceholderColor3 = Color3.fromRGB(120, 120, 130)
		box.Font = Kit.font
		box.TextScaled = true
		box.TextColor3 = Kit.color.ink
		box.BackgroundColor3 = Kit.color.paper
		box.BorderSizePixel = 0
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.AnchorPoint = Vector2.new(0, 0.5)
		box.Size = UDim2.new(0.55, -18, 0, T - 8)
		box.Position = UDim2.new(0, 8, 0.5, 0)
		Kit.round(box)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 10)
		pad.PaddingRight = UDim.new(0, 10)
		pad.PaddingTop = UDim.new(0, 6)
		pad.PaddingBottom = UDim.new(0, 6)
		pad.Parent = box
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = math.max(1, math.floor(24 * Kit.textScale))
		limit.Parent = box
		box:GetPropertyChangedSignal("Text"):Connect(function()
			-- only letters and digits, upper case, never longer than a code
			local clean = PromoRules.typed(Config, box.Text)
			if clean ~= box.Text then
				box.Text = clean
			end
			typed = clean
		end)
		box.FocusLost:Connect(function(enter: boolean)
			if enter then
				sendCode()
				box.Text = ""
			end
		end)
		box.Parent = f
		local b: TextButton
		b = Kit.button({
			Name = "Redeem",
			Text = "REDEEM",
			AnchorPoint = Vector2.new(1, 0.5),
			Size = UDim2.new(0.42, 0, 0, T - 8),
			Position = UDim2.new(1, -6, 0.5, 0),
			maxText = 20,
		}, function()
			if b:GetAttribute("Pending") then
				return -- one code at a time
			end
			if sendCode() then
				Kit.pending(b) -- until the answer's line
			end
			box.Text = ""
		end)
		b.Parent = f
	end
	if promoNote then
		order += 1
		local n = Kit.label({
			Name = "PromoNote",
			Text = promoNote.text,
			Size = UDim2.new(1, -8, 0, 30),
			LayoutOrder = order,
			TextColor3 = if promoNote.good then Kit.color.gold else Kit.color.paper,
			Font = Kit.bodyFont,
			TextWrapped = true,
			maxText = 16,
		})
		n.Parent = body
	end
end

-- WP10: the rows' state and answers (the Settings screen and the tests call these)
function SettingsMenu.promoState(state: { [string]: any })
	promo = state
	if gui and gui.Enabled then
		draw()
	end
end

function SettingsMenu.promoResult(r: { [string]: any })
	local text, good = noteFor(r)
	promoNote = { text = text, good = good }
	Kit.settle()
	if gui and gui.Enabled then
		draw()
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
	promoRows()
	body.CanvasPosition = y
end

function SettingsMenu.open()
	Kit.opening("SettingsMenu", gui, SettingsMenu.close)
	gui.Enabled = true
	promoNote = nil
	draw()
	Net.send("PromoOpen") -- WP10: the REWARDS rows (they draw when the answer comes)
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
	Net.listen("PromoState", SettingsMenu.promoState)
	Net.listen("PromoResult", SettingsMenu.promoResult)
end

return SettingsMenu
