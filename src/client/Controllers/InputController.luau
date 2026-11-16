-- InputController: one set of actions for keyboard and mouse, gamepad and touch (spec: Touch flight,
-- Accessibility: controller support). Touch buttons are drawn by the Hud and feed the same actions.
-- Actions: Leap (hold in the air to glide; climbs while flying), Fly (toggle), Boost (hold), Down (hold),
-- Basic (hold to keep firing), Skill1 to Skill4, Super, Awaken, Loadout (opens the loadout screen), Gear (the
-- gear screen), Gadget (the gadget slot's active), Map (the map and fast travel).

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
	UserInputService.InputEnded:Connect(function(input)
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
