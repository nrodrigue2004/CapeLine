-- Kit: the one UI kit (spec: Screens and UI; shared with Mossbell Stand). Comic display font, one palette,
-- rounded cards, 56 px touch targets (48 minimum), safe-area aware screens. PLACEHOLDER look until M10.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Kit = {}

local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Signal"))
Kit.Clicked = Signal.new() -- every kit button tap (the UI click sound)

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

Kit.color = {}
for name, value in Config.Ui.colors do
	Kit.color[name] = rgb(value)
end
Kit.font = Enum.Font.Bangers -- comic-book display face
Kit.bodyFont = Enum.Font.GothamBold
Kit.textScale = 1 -- Settings: text size 100 to 160 percent (spec: Accessibility)

-- Every text size limit made by the kit, so a Settings change resizes all text at once
local limits: { [UITextSizeConstraint]: number } = setmetatable({}, { __mode = "k" }) :: any

local function limitFor(parent: Instance, base: number)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = math.max(1, math.floor(base * Kit.textScale))
	limit.Parent = parent
	limits[limit] = base
end

function Kit.setTextScale(scale: number)
	Kit.textScale = math.clamp(scale, Config.Ui.textScale.min, Config.Ui.textScale.max)
	for limit, base in limits do
		limit.MaxTextSize = math.max(1, math.floor(base * Kit.textScale))
	end
end

-- Settings: flash level for bursts and screen flashes. 1 = full, 0.35 = reduced (bursts become a glow),
-- 0 = flash-free (photosensitivity)
function Kit.flash(): number
	return Kit.flashLevel
end
Kit.flashLevel = 1

function Kit.screen(name: string, order: number?): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = order or 0
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

function Kit.round(inst: GuiObject, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or Config.Ui.corner)
	c.Parent = inst
end

function Kit.stroke(inst: GuiObject, color: Color3?, thickness: number?)
	local s = Instance.new("UIStroke")
	s.Color = color or Kit.color.ink
	s.Thickness = thickness or 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
end

function Kit.frame(props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Kit.color.paper
	f.BorderSizePixel = 0
	for k, v in props do
		if k ~= "round" then
			(f :: any)[k] = v
		end
	end
	if props.round ~= false then
		Kit.round(f)
	end
	return f
end

function Kit.label(props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Kit.font
	l.TextColor3 = Kit.color.ink
	l.TextScaled = true
	l.Size = UDim2.fromOffset(100, 24)
	for k, v in props do
		if k ~= "maxText" then
			(l :: any)[k] = v
		end
	end
	limitFor(l, props.maxText or 32)
	return l
end

function Kit.button(props: { [string]: any }, onClick: (() -> ())?): TextButton
	local b = Instance.new("TextButton")
	b.Font = Kit.font
	b.TextColor3 = Kit.color.ink
	b.BackgroundColor3 = Kit.color.gold
	b.TextScaled = true
	b.AutoButtonColor = true
	b.Size = UDim2.fromOffset(Config.Ui.touchTarget * 2, Config.Ui.touchTarget)
	for k, v in props do
		if k ~= "maxText" and k ~= "pending" then
			(b :: any)[k] = v
		end
	end
	Kit.round(b)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = b
	limitFor(b, props.maxText or 28)
	if onClick then
		local waits = props.pending == true
		b.Activated:Connect(function()
			if waits and b:GetAttribute("Pending") then
				return -- one request at a time
			end
			Kit.bounce(b)
			Kit.Clicked:Fire()
			if waits then
				Kit.pending(b)
			end
			onClick()
		end)
	end
	return b
end

-- Pending state (spec: "every remote call has a pending state under 150 ms"): the button shows "..." at
-- once and takes no more taps until the server answers (any profile sync, notice or toast settles it, and
-- most screens redraw). No answer in 5 s shows TRY AGAIN, the error state.
local pendingButtons: { [TextButton]: string } = setmetatable({}, { __mode = "k" }) :: any
function Kit.pending(b: TextButton, timeout: number?)
	if pendingButtons[b] then
		return
	end
	pendingButtons[b] = b.Text
	b:SetAttribute("Pending", true)
	b.Text = "..."
	task.delay(timeout or 5, function()
		local text = pendingButtons[b]
		if text and b.Parent then
			b.Text = "TRY AGAIN"
			task.delay(1.6, function()
				if pendingButtons[b] and b.Parent then
					b.Text = text
					b:SetAttribute("Pending", nil)
					pendingButtons[b] = nil
				end
			end)
		end
	end)
end

-- The server answered: every pending button goes back to normal
function Kit.settle()
	for b, text in pendingButtons do
		if b.Parent then
			b.Text = text
			b:SetAttribute("Pending", nil)
		end
	end
	table.clear(pendingButtons)
end

-- Loading, empty and error states: one centred note in a list or panel, with an optional RETRY
function Kit.stateNote(parent: Instance, kind: string, text: string, retry: (() -> ())?): Frame
	local f = Instance.new("Frame")
	f.Name = "StateNote"
	f.BackgroundTransparency = 1
	f.Size = UDim2.new(1, 0, 0, if retry then 96 else 56)
	f.LayoutOrder = -1
	local l = Kit.label({
		Text = (if kind == "loading" then "⏳ " elseif kind == "error" then "⚠ " else "") .. text,
		Size = UDim2.new(1, -16, 0, 48),
		Position = UDim2.fromOffset(8, 4),
		TextColor3 = if kind == "error" then Color3.fromRGB(255, 150, 120) else Kit.color.paper,
		Font = Kit.bodyFont,
		TextWrapped = true,
		maxText = 16,
	})
	l.Parent = f
	if retry then
		local b = Kit.button({
			Text = "RETRY",
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.fromOffset(140, Config.Ui.touchTarget - 12),
			Position = UDim2.new(0.5, 0, 0, 52),
		}, retry)
		b.Parent = f
	end
	f.Parent = parent
	return f
end

function Kit.bounce(inst: GuiObject)
	local scale = inst:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = inst
	scale.Scale = 0.9
	TweenService
		:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
end

function Kit.pulse(inst: GuiObject, amount: number?)
	local scale = inst:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = inst
	scale.Scale = 1 + (amount or 0.12)
	TweenService
		:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
end

-- 12345 -> "12,345"
function Kit.comma(n: number): string
	local s = tostring(math.floor(n))
	local out = s
	repeat
		local k
		out, k = string.gsub(out, "^(-?%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return out
end

function Kit.time(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

return Kit
