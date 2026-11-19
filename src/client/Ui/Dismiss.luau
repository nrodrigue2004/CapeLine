-- Dismiss: every popup can be sent away (fix-hud, nate's playtest of gaps7 2026-11-19: "need a way to get rid of
-- popups shit is just on my screen"). Config.Ui.popups.dismiss.
-- * Dismiss.attach(obj, close, opts): an X in the popup's top-right corner (unless it already has its own close
--   button; a toast has none: the whole bubble is its tap) and a tap or click anywhere on it (a clear button under its own content, so its buttons still take
--   their taps first) both call close(). opts: small (a toast: no X, the bubble is the button), thin (a tracker's smaller X face), tap = false (no tap-anywhere: panels
--   that scroll or hold a list), x = false (no X), left (the X on the left corner), inset (px in from the right: a button sits in the corner), keep (a tracker: Backspace hides it, no auto-hide here).
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

-- a button with one of these words already sends the popup away (an ask's NO is its X)
local CLOSERS = {
	X = true,
	["✕"] = true,
	CLOSE = true,
	NO = true,
	["NO THANKS"] = true,
	LATER = true,
	["NICE!"] = true,
	OK = true,
}

-- Has the popup its own close button already (DailyHud's X, the contest's X, the broadcast's CLOSE, an ask's NO)?
local function ownClose(obj: GuiObject): boolean
	for _, d in obj:GetDescendants() do
		if d:IsA("TextButton") and d.Name ~= "DismissX" then
			local t = string.upper(d.Text)
			if d.Name == "Close" or CLOSERS[t] then
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
	if o.x ~= false and not o.small and not ownClose(obj) then
		-- the X: a clear tap-sized button (Config.Ui.phone.minTap) just inside the popup's corner, so a thumb can
		-- hit it on a phone, wearing a smaller round X (cardX, or toastX on a tracker) in that corner
		local size = if o.thin then D.toastX else D.cardX
		local hit = math.max(Config.Ui.phone.minTap, size)
		local x = Instance.new("TextButton")
		x.Name = "DismissX"
		x.Text = ""
		x.BackgroundTransparency = 1
		x.AutoButtonColor = false
		local inset = tonumber(o.inset) or 0 -- px in from the right edge (a button already sits in the corner)
		x.AnchorPoint = if o.left then Vector2.zero else Vector2.new(1, 0)
		x.Position = if o.left then UDim2.fromOffset(0, 0) else UDim2.new(1, -inset, 0, 0)
		x.Size = UDim2.fromOffset(hit, hit)
		x.ZIndex = 100 -- over the popup's own content (a name card's parts sit at 20+)
		x.Activated:Connect(function()
			Kit.Clicked:Fire()
			fire(obj)
		end)
		local face = Kit.label({
			Name = "Face",
			Text = "X",
			AnchorPoint = if o.left then Vector2.zero else Vector2.new(1, 0),
			Position = if o.left then UDim2.fromOffset(2, 2) else UDim2.new(1, -2, 0, 2),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = Kit.color.paper,
			BackgroundTransparency = 0,
			TextColor3 = Kit.color.ink,
			ZIndex = 101,
			maxText = math.floor(size * 0.6),
		})
		Kit.round(face, math.floor(size / 2))
		Kit.stroke(face, Kit.color.ink, 2)
		face.Parent = x
		-- in a clear full-size frame of its own (out of the popup's UIListLayout, over its content)
		local top = Instance.new("Frame")
		top.Name = "DismissTop"
		top.BackgroundTransparency = 1
		top.Size = UDim2.fromScale(1, 1)
		top.ZIndex = 100
		top.Active = false
		top.Parent = holder
		x.Parent = top
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
