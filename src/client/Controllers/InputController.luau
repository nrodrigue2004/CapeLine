-- InputController: one set of actions for keyboard and mouse, gamepad and touch (spec: Touch flight,
-- Accessibility: controller support). Touch buttons are drawn by the Hud and feed the same actions.
-- Actions: Leap (hold in the air to glide; climbs while flying), Fly (toggle), Boost (hold), Down (hold),
-- Basic (hold to keep firing), Skill1 to Skill4, Super, Awaken, Loadout (opens the loadout screen), Gear (the
-- gear screen), Gadget (the gadget slot's active), Map (the map and fast travel).
-- M10 (spec: Accessibility "left-handed layout ... one-hand flight mode (right thumb only with auto-turn)"):
-- on touch, the left-handed layout and one-hand flight swap Roblox's left thumbstick for this module's own
-- stick on the right side (the HUD buttons move left for left-handed). In one-hand mode the stick's sideways
-- push turns the camera (auto-turn) and up and down fly forward and back. autoAim turns touch aim assist off.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Signal"))

local InputController = {}

InputController.Pressed = Signal.new() -- (action)
InputController.Released = Signal.new() -- (action)
InputController.DeviceChanged = Signal.new() -- (device)
InputController.device = "mouse" -- "mouse", "touch" or "gamepad"

local down: { [string]: boolean } = {}

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
	[Enum.KeyCode.C] = "Down",
	[Enum.KeyCode.Q] = "Skill1",
	[Enum.KeyCode.One] = "Skill1",
	[Enum.KeyCode.E] = "Skill2",
	[Enum.KeyCode.Two] = "Skill2",
	[Enum.KeyCode.R] = "Skill3",
	[Enum.KeyCode.Three] = "Skill3",
	[Enum.KeyCode.T] = "Skill4",
	[Enum.KeyCode.Four] = "Skill4",
	[Enum.KeyCode.G] = "Super",
	[Enum.KeyCode.Five] = "Super",
	[Enum.KeyCode.V] = "Awaken",
	[Enum.KeyCode.L] = "Loadout",
	[Enum.KeyCode.I] = "Gear",
	[Enum.KeyCode.Z] = "Gadget",
	[Enum.KeyCode.M] = "Map",
	[Enum.KeyCode.J] = "Journal",
	[Enum.KeyCode.C] = "Catch",
	[Enum.KeyCode.P] = "Shop",
	[Enum.KeyCode.H] = "Emote",
	-- gamepad
	[Enum.KeyCode.ButtonA] = "Leap",
	[Enum.KeyCode.ButtonY] = "Fly",
	[Enum.KeyCode.ButtonL2] = "Boost",
	[Enum.KeyCode.ButtonL3] = "Boost",
	[Enum.KeyCode.ButtonB] = "Down",
	[Enum.KeyCode.ButtonR2] = "Basic",
	[Enum.KeyCode.ButtonX] = "Skill1",
	[Enum.KeyCode.ButtonR1] = "Skill2",
	[Enum.KeyCode.ButtonL1] = "Skill3",
	[Enum.KeyCode.DPadLeft] = "Skill4",
	[Enum.KeyCode.DPadUp] = "Super",
	[Enum.KeyCode.DPadRight] = "Awaken",
	[Enum.KeyCode.DPadDown] = "Loadout",
	[Enum.KeyCode.ButtonSelect] = "Gear",
	[Enum.KeyCode.ButtonR3] = "Gadget",
}

-- Key hints shown on the HUD buttons for keyboard players
InputController.hints = {
	Leap = "Space",
	Fly = "F",
	Boost = "Shift",
	Down = "Ctrl",
	Basic = "Click",
	Skill1 = "Q",
	Skill2 = "E",
	Skill3 = "R",
	Skill4 = "T",
	Super = "G",
	Awaken = "V",
	Loadout = "L",
	Gear = "I",
	Gadget = "Z",
	Map = "M",
	Journal = "J",
	Catch = "C",
	Shop = "P",
	Emote = "H",
}

function InputController.isDown(action: string): boolean
	return down[action] == true
end

-- Touch buttons and anything else call this
function InputController.set(action: string, isDown: boolean)
	if (down[action] == true) == isDown then
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

-- Where the stick is (for the HUD's ring): origin and push, or nil when not held
function InputController.stickState(): (Vector2?, Vector2)
	return if stick.id then stick.origin else nil, stick.vec
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
		end
		local action = KEYS[input.KeyCode]
		if action then
			InputController.set(action, true)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if stick.id == input then
			local d = Vector2.new(input.Position.X, input.Position.Y) - stick.origin
			if d.Magnitude > STICK_RADIUS then
				d = d.Unit * STICK_RADIUS
			end
			stick.vec = d / STICK_RADIUS
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if stick.id == input then
			stick.id, stick.vec = nil, Vector2.zero
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			InputController.set("Basic", false)
			return
		end
		local action = KEYS[input.KeyCode]
		if action then
			InputController.set(action, false)
		end
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		for action in down do
			InputController.set(action, false)
		end
	end)
end

return InputController
