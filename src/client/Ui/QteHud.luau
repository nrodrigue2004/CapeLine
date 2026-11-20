-- QteHud: the prologue's quick-time prompt on screen (fix-flow, nate's playtest 2026-11-19: the rooftop chase "should
-- be a cutscene with QTE's"; the rules are Shared.QtePlan, the runner Fx.PrologueQte). One big round prompt low in
-- the middle: the verb (JUMP! or DODGE!), the key or button for this device (SPACE, Q, A, LB, or TAP on a phone),
-- and a gold bar that runs out with the window. The prompt is itself a button, so a tap or a click counts on
-- every device. A hit pops NICE!; a miss shakes it and reads TRY AGAIN!; the help after the last miss reads GOT IT!
-- prologue-cine (2026-11-20): the kinds of prompt: a press (as above), a mash (TAP FAST / MASH: a fill rises with each
-- press) and a hold (HOLD: the fill rises while the key, the button or the prompt is held). A finger or the mouse
-- held on the prompt is a hold on every device (Held).
-- PLACEHOLDER ART: Kit shapes and text until the UI art pass draws a prompt plate.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local Kit = require(script.Parent.Kit)
local InputController = require(script.Parent.Parent.Controllers.InputController)

local QteHud = {}

QteHud.Pressed = Signal.new() -- () the prompt itself was tapped or clicked
QteHud.Held = Signal.new() -- (down) a finger or the mouse went down on the prompt, or came up (hold prompts)

local gui: ScreenGui
local holder: Frame
local prompt: TextButton
local word: TextLabel
local key: TextLabel
local barBack: Frame
local bar: Frame
local note: TextLabel
local fillBack: Frame
local fill: Frame
local kindNow = "press"
local action = "Leap"
local shownAt = 0
local window = 1
local open = false

-- The key or button that answers `act` on this device (kind: "press", "mash" or "hold")
function QteHud.keyText(act: string, kind: string?): string
	local d = InputController.device
	local k = if d == "touch"
		then "TAP"
		elseif d == "gamepad" then InputController.padHints[act] or act
		else string.upper(InputController.hints[act] or act)
	if kind == "mash" then
		return if d == "touch" then "TAP FAST" else "MASH " .. k
	elseif kind == "hold" then
		return if d == "touch" then "HOLD" else "HOLD " .. k
	end
	return k
end

function QteHud.isOpen(): boolean
	return open
end

-- Show a prompt: its verb, the action that answers it, its window (seconds) and its kind
function QteHud.show(verb: string, act: string, seconds: number, kind: string?)
	action = act
	kindNow = kind or "press"
	fillBack.Visible = kindNow ~= "press"
	fill.Size = UDim2.fromScale(0, 1)
	shownAt = os.clock()
	window = math.max(0.1, seconds)
	open = true
	word.Text = verb
	key.Text = QteHud.keyText(act, kindNow)
	note.Visible = false
	prompt.Visible = true
	barBack.Visible = true
	bar.Size = UDim2.fromScale(1, 1)
	prompt.Size = UDim2.fromScale(0.6, 0.6)
	TweenService:Create(prompt, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Size = UDim2.fromScale(1, 1) })
		:Play()
	gui.Enabled = true
end

-- A mash's or a hold's fill (0 to 1)
function QteHud.progress(f: number)
	fill.Size = UDim2.fromScale(math.clamp(f, 0, 1), 1)
	if kindNow == "mash" and f > 0 then
		Kit.bounce(prompt)
	end
end

-- The prompt's answer: "hit", "miss" or "assist"
function QteHud.result(kind: string)
	open = false
	prompt.Visible = false
	barBack.Visible = false
	fillBack.Visible = false
	note.Visible = true
	if kind == "hit" then
		note.Text = "NICE!"
		note.TextColor3 = Kit.color.gold
	elseif kind == "assist" then
		note.Text = "GOT IT!"
		note.TextColor3 = Kit.color.gold
	else
		note.Text = "TRY AGAIN!"
		note.TextColor3 = Kit.color.paper
	end
	Kit.bounce(note)
	task.delay(0.8, function()
		if not open then
			note.Visible = false
		end
	end)
end

function QteHud.hide()
	open = false
	gui.Enabled = false
	prompt.Visible = false
	barBack.Visible = false
	fillBack.Visible = false
	note.Visible = false
end

-- Each frame while a prompt is up: the bar runs out with the window
function QteHud.frame()
	if open then
		local left = 1 - (os.clock() - shownAt) / window
		bar.Size = UDim2.fromScale(math.clamp(left, 0, 1), 1)
	end
end

-- The uishot sample: a DODGE prompt half way through its window
function QteHud.sample()
	QteHud.show(Config.Story.opening.qte.words.Block, "Block", 2)
	bar.Size = UDim2.fromScale(0.55, 1)
end

function QteHud.init()
	gui = Kit.screen("Qte", 40)
	gui.Enabled = false
	local T = Config.Ui.touchTarget
	holder = Kit.frame({
		Name = "Holder",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.86, 0),
		Size = UDim2.fromOffset(T * 3.2, T * 3.2),
		BackgroundTransparency = 1,
		round = false,
		ink = false,
	})
	holder.Parent = gui
	prompt = Kit.button({
		Name = "Prompt",
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Kit.color.gold,
		Visible = false,
	}, function()
		if open then
			QteHud.Pressed:Fire()
		end
	end)
	local corner = prompt:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0.5, 0) -- round
	end
	Kit.stroke(prompt, Kit.color.ink, 4)
	prompt.Parent = holder
	word = Kit.label({
		Name = "Word",
		Text = "JUMP!",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.16),
		Size = UDim2.fromScale(0.86, 0.36),
		TextColor3 = Kit.color.ink,
		maxText = 44,
	})
	word.Parent = prompt
	key = Kit.label({
		Name = "Key",
		Text = "SPACE",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.56),
		Size = UDim2.fromScale(0.66, 0.24),
		BackgroundTransparency = 0,
		BackgroundColor3 = Kit.color.paper,
		TextColor3 = Kit.color.ink,
		maxText = 28,
	})
	key.Parent = prompt
	barBack = Kit.frame({
		Name = "Clock",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 8),
		Size = UDim2.new(1, 0, 0, 12),
		BackgroundColor3 = Kit.color.ink,
		Visible = false,
	})
	barBack.Parent = holder
	bar = Kit.frame({
		Name = "Left",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Kit.color.gold,
		ink = false,
	})
	bar.Parent = barBack
	-- the mash's and the hold's fill, above the prompt
	fillBack = Kit.frame({
		Name = "Fill",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -8),
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundColor3 = Kit.color.ink,
		Visible = false,
	})
	fillBack.Parent = holder
	fill = Kit.frame({
		Name = "Done",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Kit.color.paper,
		ink = false,
	})
	fill.Parent = fillBack
	note = Kit.label({
		Name = "Note",
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.6, 0.4),
		TextColor3 = Kit.color.gold,
		TextStrokeTransparency = 0,
		Visible = false,
		maxText = 56,
	})
	note.Parent = holder
	-- a finger or the mouse held on the prompt (the hold prompt on a phone; any device may use it)
	prompt.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if open and (t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1) then
			QteHud.Held:Fire(true)
		end
	end)
	prompt.InputEnded:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			QteHud.Held:Fire(false)
		end
	end)
	InputController.DeviceChanged:Connect(function()
		if open then
			key.Text = QteHud.keyText(action, kindNow)
		end
	end)
end

return QteHud
