-- InputController: one set of actions for keyboard and mouse, gamepad and touch (spec: Touch flight,
-- Accessibility: controller support). Touch buttons are drawn by the Hud and feed the same actions.
-- Actions: Leap (hold in the air to glide; climbs while flying), Fly (toggle), Boost (hold), Down (hold),
-- Basic (hold to keep firing), Skill1 to Skill4, Super, Awaken, Loadout (opens the loadout screen), Gear (the
-- gear screen), Gadget (the gadget slot's active), Map (the map and fast travel), HoldPower, HoldWeapon and
-- Swap (what M1 and the skills cast: the power or the carried weapon), Menu (gamepad Select: the top row).
-- H1: Block (hold): Q on PC since nate's playtest 2026-11-19 ("Alt to block doesn't seem to work": Windows
-- turns a lone Alt press into a menu key that eats the next key, Studio's camera takes Alt, and Alt+Shift
-- switches keyboard layouts; Decisions 2026-11-19), LB on a gamepad, the shield button on touch.
-- Lock-on (nate's playtest 2026-11-19; LockClient): Lock toggles the hard lock (middle mouse; a tap of R3 on a
-- gamepad, held R3 is the Gadget; the LOCK button on touch), LockCycle moves it to the next target (Tab; the
-- right stick flicked sideways while locked: InputController.Flick).
-- Phone pass (overhaul step 8): a HUD button's touch is let go wherever the finger lifts, and dragging a
-- held Basic, skill or super button turns the camera to aim (holdTouch).
-- M10 (spec: Accessibility "left-handed layout ... one-hand flight mode (right thumb only with auto-turn)"):
-- on touch, the left-handed layout and one-hand flight swap Roblox's left thumbstick for this module's own
-- stick on the right side (the HUD buttons move left for left-handed). In one-hand mode the stick's sideways
-- push turns the camera (auto-turn) and up and down fly forward and back. autoAim turns touch aim assist off.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Signal"))

local InputController = {}

InputController.Pressed = Signal.new() -- (action)
InputController.Flick = Signal.new() -- (dir) the gamepad's right stick flicked right (1) or left (-1)
InputController.Released = Signal.new() -- (action)
InputController.DeviceChanged = Signal.new() -- (device)
InputController.device = "mouse" -- "mouse", "touch" or "gamepad"

local down: { [string]: boolean } = {}
local r3At, r3Down, r3Gadget = 0, false, false
local flickAt, flickOut = 0, false

InputController.autoAim = true -- Settings: aim assist on touch
InputController.stickMode = "default" :: string -- "default", "left" (left-handed) or "oneHand"
InputController.StickChanged = Signal.new() -- (mode)
local stick = { id = nil :: InputObject?, origin = Vector2.zero, vec = Vector2.zero }
local STICK_RADIUS = 70

local KEYS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.Space] = "Leap",
	[Enum.KeyCode.F] = "Fly",
	[Enum.KeyCode.LeftShift] = "Boost",
	[Enum.KeyCode.LeftControl] = "Down",
	-- hero creator plan (nate, 2026-11-16): 1 holds the power, 2 the weapon; Z X C V (and Q E R T) cast the
	-- held one's four skills
	[Enum.KeyCode.One] = "HoldPower",
	[Enum.KeyCode.Two] = "HoldWeapon",
	[Enum.KeyCode.Z] = "Skill1",
	[Enum.KeyCode.X] = "Skill2",
	[Enum.KeyCode.C] = "Skill3",
	[Enum.KeyCode.V] = "Skill4",
	[Enum.KeyCode.E] = "Skill2",
	[Enum.KeyCode.R] = "Skill3",
	[Enum.KeyCode.T] = "Skill4",
	[Enum.KeyCode.G] = "Super",
	[Enum.KeyCode.Five] = "Super",
	[Enum.KeyCode.Y] = "Awaken",
	[Enum.KeyCode.L] = "Loadout",
	[Enum.KeyCode.I] = "Gear",
	[Enum.KeyCode.Three] = "Gadget",
	[Enum.KeyCode.M] = "Map",
	[Enum.KeyCode.J] = "Journal",
	[Enum.KeyCode.K] = "TaskForce", -- H4: the Task Force board (Photo Mode moved to N: PhotoMode.KEY)
	[Enum.KeyCode.B] = "Catch", -- the interact key (only the opening's catch step listens)
	[Enum.KeyCode.P] = "Shop",
	[Enum.KeyCode.H] = "Emote",
	-- H1 (Hero MMO features): hold to block. The spec's F stays Fly (Decisions 2026-11-17). Block was Alt until
	-- nate's playtest 2026-11-19 found it unreliable (Windows' menu key, Studio's camera, Alt+Shift), so it is Q
	-- (Z stays Skill 1; Q was only Skill 1's second key)
	[Enum.KeyCode.Q] = "Block",
	-- lock-on (nate's playtest 2026-11-19): Tab moves the lock to the next target (middle mouse toggles it)
	[Enum.KeyCode.Tab] = "LockCycle",
	-- gamepad
	[Enum.KeyCode.ButtonA] = "Leap",
	[Enum.KeyCode.ButtonY] = "Fly",
	[Enum.KeyCode.ButtonL2] = "Boost",
	[Enum.KeyCode.ButtonL3] = "Swap", -- power or weapon
	[Enum.KeyCode.ButtonB] = "Down",
	[Enum.KeyCode.ButtonR2] = "Basic",
	[Enum.KeyCode.ButtonX] = "Skill1",
	[Enum.KeyCode.ButtonR1] = "Skill2",
	-- H1: LB holds Block (spec); Skill 3 and 4 move to the d-pad, and the POWERS screen opens from its HUD
	-- button (gamepad UI selection) instead of d-pad down
	[Enum.KeyCode.ButtonL1] = "Block",
	[Enum.KeyCode.DPadLeft] = "Skill3",
	[Enum.KeyCode.DPadDown] = "Skill4",
	[Enum.KeyCode.DPadUp] = "Super",
	[Enum.KeyCode.DPadRight] = "Awaken",
	-- phone pass: Select opens the top row and its MORE drawer for the D-pad (GEAR, MAP, JOURNAL, SHOP,
	-- POWERS; H1 moved d-pad down to Skill 4)
	[Enum.KeyCode.ButtonSelect] = "Menu",
	-- R3: a tap toggles the lock, a hold (Config.Combat.lock.padHold) is the Gadget (see init)
}

-- Gamepad keys that also fire a second action: X catches in the opening's catch step (StoryHud only
-- listens then), so a controller can finish the opening
local ALSO: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.ButtonX] = "Catch",
}

-- Button labels shown on the HUD for controller players (they follow KEYS: H1 moved Skill 3 and 4 to the
-- d-pad and gave LB to Block; POWERS has no pad button, it opens from the top row with Select)
InputController.padHints = {
	Leap = "A",
	Fly = "Y",
	Boost = "LT",
	Down = "B",
	Basic = "RT",
	Skill1 = "X",
	Skill2 = "RB",
	Skill3 = "◀",
	Skill4 = "▼",
	Super = "▲",
	Awaken = "▶",
	Swap = "LS",
	Gadget = "RS hold",
	Block = "LB",
	Lock = "RS",
	Catch = "X",
}

-- Key hints shown on the HUD buttons for keyboard players
InputController.hints = {
	Leap = "Space",
	Fly = "F",
	Boost = "Shift",
	Down = "Ctrl",
	Basic = "Click",
	Skill1 = "Z",
	Skill2 = "X",
	Skill3 = "C",
	Skill4 = "V",
	Super = "G",
	Awaken = "Y",
	HoldPower = "1",
	HoldWeapon = "2",
	Swap = "1 / 2",
	Loadout = "L",
	Gear = "I",
	Gadget = "3",
	Map = "M",
	Journal = "J",
	Catch = "B",
	Shop = "P",
	Emote = "H",
	Block = "Q",
	Lock = "MMB",
	LockCycle = "Tab",
}

-- The action a key or pad button is bound to, or nil (fix-flow, 2026-11-19: the prologue's quick-time prompts
-- read keys while the hero's controls rest)
function InputController.actionOf(key: Enum.KeyCode): string?
	return KEYS[key]
end

function InputController.isDown(action: string): boolean
	return down[action] == true
end

-- Photo Mode holds the hero still: no moving and no actions until it closes
InputController.frozen = false

-- Touch buttons and anything else call this
function InputController.set(action: string, isDown: boolean)
	if (down[action] == true) == isDown then
		return
	end
	if isDown and InputController.frozen then
		return
	end
	down[action] = isDown or nil
	if isDown then
		InputController.Pressed:Fire(action)
	else
		InputController.Released:Fire(action)
	end
end

local function setDevice(d: string)
	if InputController.device ~= d then
		InputController.device = d
		InputController.DeviceChanged:Fire(d)
	end
end

-- Camera-relative move vector from the default control scripts (keyboard, thumbstick, gamepad)
local controls: any = nil
function InputController.moveVector(): Vector3
	if InputController.frozen then
		return Vector3.zero
	end
	if not controls then
		local ok, module = pcall(function()
			return require(
				Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: any
			)
		end)
		if ok and module then
			controls = module:GetControls()
		end
	end
	if InputController.stickMode ~= "default" and InputController.device == "touch" then
		local v = stick.vec
		if InputController.stickMode == "oneHand" then
			return Vector3.new(0, 0, v.Y) -- sideways turns the camera instead (InputController.turnRate)
		end
		return Vector3.new(v.X, 0, v.Y)
	end
	if controls then
		local ok, v = pcall(function()
			return controls:GetMoveVector()
		end)
		if ok and v then
			return v
		end
	end
	return Vector3.zero
end

-- One-hand flight: how hard the stick pushes sideways (-1 to 1); CameraController turns by it
function InputController.turnRate(): number
	if InputController.stickMode == "oneHand" and InputController.device == "touch" then
		return stick.vec.X
	end
	return 0
end

-- The stick's touch area: the right 45% of the screen, lower 60%
local function inStickZone(pos: Vector2): boolean
	local v = Workspace.CurrentCamera.ViewportSize
	return pos.X >= v.X * 0.55 and pos.Y >= v.Y * 0.4
end

-- Use the right-side stick ("left" or "oneHand") or Roblox's own ("default")
function InputController.setStick(mode: string)
	if InputController.stickMode == mode then
		return
	end
	InputController.stickMode = mode
	stick.id, stick.vec = nil, Vector2.zero
	InputController.moveVector() -- loads the control module
	if controls then
		pcall(function()
			if mode == "default" then
				controls:Enable()
			elseif InputController.device == "touch" then
				controls:Disable()
			end
		end)
	end
	InputController.StickChanged:Fire(mode)
end

-- Hold the hero still (Photo Mode) or let go; the default controls follow the stick mode again after
function InputController.freeze(on: boolean)
	InputController.frozen = on
	InputController.moveVector() -- loads the control module
	if on then
		for action in down do
			InputController.set(action, false)
		end
	end
	if controls then
		pcall(function()
			if on then
				controls:Disable()
			elseif InputController.stickMode == "default" or InputController.device ~= "touch" then
				controls:Enable()
			end
		end)
	end
end

-- Where the stick is (for the HUD's ring): origin and push, or nil when not held
function InputController.stickState(): (Vector2?, Vector2)
	return if stick.id then stick.origin else nil, stick.vec
end

-- Phone pass: a touch that pressed a HUD button. Its action is let go when that finger lifts anywhere (a
-- thumb that slides off the button still releases it), and with aim on, dragging it turns the camera, so a
-- held skill aims by dragging its own button (the aim preview follows the screen centre).
local touchHolds: { [InputObject]: { action: string, last: Vector2, aim: boolean } } = {}
local aimYaw, aimPitch = 0, 0
function InputController.holdTouch(input: InputObject, action: string, aim: boolean)
	touchHolds[input] = { action = action, last = Vector2.new(input.Position.X, input.Position.Y), aim = aim }
end

-- A mouse click that pressed a HUD button: let go when the mouse button comes up anywhere (nate's playtest
-- 2026-11-19, "so many buttons are extremely unreliable"). The button's own InputEnded only comes when the
-- release is over it; POWERS, GEAR, MAP and the rest open their screen on the press, so the release landed on
-- that screen, the action stayed down, and the next click was no press at all (it only let go): every
-- other click did nothing.
local mouseHolds: { [string]: boolean } = {}
function InputController.holdMouse(action: string)
	mouseHolds[action] = true
end

-- Apply the drag to the camera before Roblox's camera runs (as CameraController's one-hand auto-turn does)
local function applyAimDrag()
	if aimYaw == 0 and aimPitch == 0 then
		return
	end
	local yaw, pitch = aimYaw, aimPitch
	aimYaw, aimPitch = 0, 0
	local cam = Workspace.CurrentCamera
	local char = Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (cam and root) then
		return
	end
	local A = Config.Ui.phone.aimDrag
	local pivot = root.Position
	local cf = CFrame.new(pivot) * CFrame.Angles(0, -yaw, 0) * CFrame.new(-pivot) * cam.CFrame
	-- pitch about the camera's right axis, kept inside maxPitch
	local look = cf.LookVector
	local now = math.asin(math.clamp(look.Y, -1, 1))
	local limit = math.rad(A.maxPitch)
	local want = math.clamp(now - pitch, -limit, limit)
	local d = want - now
	if math.abs(d) > 1e-4 then
		cf = CFrame.new(pivot) * CFrame.fromAxisAngle(cf.RightVector, d) * CFrame.new(-pivot) * cf
	end
	cam.CFrame = cf
end

-- Where the player is aiming: the mouse on PC, the screen centre on touch and gamepad
function InputController.aimRay(): Ray
	local cam = Workspace.CurrentCamera
	if InputController.device == "mouse" then
		local m = UserInputService:GetMouseLocation()
		return cam:ViewportPointToRay(m.X, m.Y)
	end
	local v = cam.ViewportSize
	return cam:ViewportPointToRay(v.X / 2, v.Y * 0.45)
end

function InputController.init()
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		InputController.device = "touch"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		InputController.device = "gamepad"
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch then
			setDevice("touch")
			local p = Vector2.new(input.Position.X, input.Position.Y)
			if
				not processed
				and InputController.stickMode ~= "default"
				and not stick.id
				and inStickZone(p)
			then
				stick.id, stick.origin, stick.vec = input, p, Vector2.zero
			end
			return -- touch actions come from the Hud buttons
		elseif t == Enum.UserInputType.Gamepad1 then
			setDevice("gamepad")
		elseif t == Enum.UserInputType.Keyboard or t == Enum.UserInputType.MouseButton1 then
			setDevice("mouse")
		end
		if processed then
			return
		end
		if t == Enum.UserInputType.MouseButton1 then
			InputController.set("Basic", true)
			return
		elseif t == Enum.UserInputType.MouseButton3 then
			InputController.set("Lock", true)
			return
		end
		if input.KeyCode == Enum.KeyCode.ButtonR3 then
			-- a tap toggles the lock; held past padHold it is the Gadget (held until R3 lets go)
			r3At = os.clock()
			local at = r3At
			task.delay(Config.Combat.lock.padHold, function()
				if r3At == at and r3Down then
					r3Gadget = true
					InputController.set("Gadget", true)
				end
			end)
			r3Down = true
			return
		end
		local action = KEYS[input.KeyCode]
		if action then
			InputController.set(action, true)
		end
		local also = ALSO[input.KeyCode]
		if also then
			InputController.set(also, true)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Thumbstick2 then
			-- a sideways flick of the right stick (LockClient cycles the lock with it)
			local x = input.Position.X
			local L = Config.Combat.lock.hard
			if math.abs(x) >= L.flick and math.abs(input.Position.Y) < L.flick then
				local now = os.clock()
				if not flickOut and now - flickAt >= L.flickGap then
					flickOut, flickAt = true, now
					InputController.Flick:Fire(if x > 0 then 1 else -1)
				end
			elseif math.abs(x) < 0.3 then
				flickOut = false
			end
			return
		end
		local hold = touchHolds[input]
		if hold then
			local p = Vector2.new(input.Position.X, input.Position.Y)
			if hold.aim then
				local d = p - hold.last
				local A = Config.Ui.phone.aimDrag
				aimYaw += d.X * A.yaw
				aimPitch += d.Y * A.pitch
			end
			hold.last = p
		end
		if stick.id == input then
			local d = Vector2.new(input.Position.X, input.Position.Y) - stick.origin
			if d.Magnitude > STICK_RADIUS then
				d = d.Unit * STICK_RADIUS
			end
			stick.vec = d / STICK_RADIUS
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local hold = touchHolds[input]
		if hold then
			touchHolds[input] = nil
			InputController.set(hold.action, false)
		end
		if stick.id == input then
			stick.id, stick.vec = nil, Vector2.zero
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton3 then
			InputController.set("Lock", false)
			return
		end
		if input.KeyCode == Enum.KeyCode.ButtonR3 then
			r3Down = false
			if r3Gadget then
				r3Gadget = false
				InputController.set("Gadget", false)
			else
				InputController.set("Lock", true)
				InputController.set("Lock", false)
			end
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			InputController.set("Basic", false)
			for action in mouseHolds do
				InputController.set(action, false)
			end
			table.clear(mouseHolds)
			return
		end
		local action = KEYS[input.KeyCode]
		if action then
			InputController.set(action, false)
		end
		local also = ALSO[input.KeyCode]
		if also then
			InputController.set(also, false)
		end
	end)
	RunService:BindToRenderStep("CapelineAimDrag", Enum.RenderPriority.Camera.Value - 2, applyAimDrag)
	UserInputService.WindowFocusReleased:Connect(function()
		table.clear(touchHolds)
		table.clear(mouseHolds)
		for action in down do
			InputController.set(action, false)
		end
	end)
end

return InputController
