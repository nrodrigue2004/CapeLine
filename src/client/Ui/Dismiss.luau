-- Dismiss: every popup can be sent away (fix-hud, nate's playtest of gaps7 2026-11-19: "need a way to get rid of
-- popups shit is just on my screen"). Config.Ui.popups.dismiss.
-- * Dismiss.attach(obj, close, opts): an X in the popup's top-right corner (unless it already has its own close
--   button) and a tap or click anywhere on it (a clear button under its own content, so its buttons still take
--   their taps first) both call close(). opts: small (a toast's smaller X), tap = false (no tap-anywhere: panels
--   that scroll or hold a list), x = false (no X), left (the X on the left corner: a button sits right), keep (a tracker: Backspace hides it, no auto-hide here).
--   Calling it again on the same object only swaps its close function (cards reused show after show).
-- * Dismiss.clearAll(): Backspace (keyboard). Every attached popup on screen closes and Dismiss.Cleared fires (Ui.Popups
--   then drops what still waits in its line, the answers to a tap excepted). Keyboard B is GRAB and the prompts'
--   key, and the pad's B is Down (InputController), so neither clears: on a pad the short lives do it.
-- Pure UI: no game rules here. Ui.Popups attaches every card and toast of its line as it shows.

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Signal"))

local Kit = require(script.Parent.Kit)

local Dismiss = {}

local D = Config.Ui.popups.dismiss
Dismiss.Cleared = Signal.new()

type Entry = { close: () -> (), opts: { [string]: any } }
-- (a strong table: Roblox may drop an Instance key from a weak one while it is still on screen; Destroying and
-- clearAll tidy it)
local entries: { [GuiObject]: Entry } = {}
local bound = false

-- Is this object drawn now (itself, every GuiObject above it, and its ScreenGui on)?
function Dismiss.shown(obj: GuiObject): boolean
	local p: Instance? = obj
	while p do
		if p:IsA("GuiObject") and not p.Visible then
			return false
		end
		if p:IsA("LayerCollector") then
			return (p :: any).Enabled ~= false
		end
		p = p.Parent
	end
	return false
end

-- Has the popup its own close button already (DailyHud's X, the contest's X, the broadcast's CLOSE)?
local function ownClose(obj: GuiObject): boolean
	for _, d in obj:GetDescendants() do
		if d:IsA("TextButton") and d.Name ~= "DismissX" then
			local t = string.upper(d.Text)
			if d.Name == "Close" or t == "X" or t == "✕" or t == "CLOSE" then
				return true
			end
		end
	end
	return false
end

local function fire(obj: GuiObject)
	local e = entries[obj]
	if not e then
		return
	end
	local ok, err = pcall(e.close)
	if not ok then
		warn("[Dismiss] " .. obj.Name .. ": " .. tostring(err))
		obj.Visible = false
	end
end

local function bind()
	if bound then
		return
	end
	bound = true
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return -- typing in a box (the creator's name, the promo code)
		end
		for _, k in D.keys do
			if input.KeyCode == (Enum.KeyCode :: any)[k] then
				Dismiss.clearAll()
				return
			end
		end
	end)
end

function Dismiss.attach(obj: GuiObject, close: () -> (), opts: { [string]: any }?): GuiObject
	bind()
	local o = opts or {}
	local had = entries[obj]
	entries[obj] = { close = close, opts = o }
	if had then
		return obj
	end
	obj:SetAttribute("Dismiss", true)
	-- (in a Folder: a Folder is outside the popup's UIListLayout, as Kit's ink shadows are, so they are never laid
	-- out as rows; they still draw in the popup's box)
	local holder = Instance.new("Folder")
	holder.Name = "Dismiss"
	holder.Parent = obj
	if o.tap ~= false then
		-- a clear button under the popup's own content: its labels let a tap through, its buttons take theirs first
		local tap = Instance.new("TextButton")
		tap.Name = "DismissTap"
		tap.BackgroundTransparency = 1
		tap.Text = ""
		tap.AutoButtonColor = false
		tap.Selectable = false
		tap.Size = UDim2.fromScale(1, 1)
		tap.ZIndex = 0
		tap.Activated:Connect(function()
			fire(obj)
		end)
		tap.Parent = holder
	end
	if o.x ~= false and not ownClose(obj) then
		local size = if o.small then D.toastX else D.cardX
		local x = Kit.button({
			Name = "DismissX",
			Text = "X",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = if o.left
				then UDim2.new(0, size * 0.25, 0, size * 0.25)
				else UDim2.new(1, -size * 0.25, 0, size * 0.25),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = Kit.color.paper,
			ZIndex = 100, -- over the popup's own content (a name card's parts sit at 20+)
			maxText = math.floor(size * 0.6),
		}, function()
			fire(obj)
		end)
		local pad = x:FindFirstChildOfClass("UIPadding")
		if pad then
			pad:Destroy() -- a small round X: the letter fills it
		end
		x.Parent = holder
	end
	obj.Destroying:Connect(function()
		entries[obj] = nil
	end)
	return obj
end

-- Take this one away now (as its X would)
function Dismiss.close(obj: GuiObject)
	fire(obj)
end

function Dismiss.attached(obj: GuiObject): boolean
	return entries[obj] ~= nil
end

-- Backspace: every attached popup on screen goes; returns how many
function Dismiss.clearAll(): number
	local n = 0
	local list = {}
	for obj in entries do
		if not obj.Parent then
			entries[obj] = nil
		elseif Dismiss.shown(obj) then
			table.insert(list, obj)
		end
	end
	for _, obj in list do
		fire(obj)
		n += 1
	end
	Dismiss.Cleared:Fire(n)
	return n
end

return Dismiss
