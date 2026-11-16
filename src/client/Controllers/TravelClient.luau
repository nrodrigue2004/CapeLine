-- TravelClient: the fast-travel flight and the safehouse terminals on this device (spec: Movement kit > Fast
-- travel "3 s skippable flight"; Wait table "Long flights").
-- * FastTravel ok: the camera sweeps up, across and down along Travel.flightPath for 3 s while a SKIP
--   button waits; skipping asks the server to land now. FastTravelDone hands the camera back.
-- * A refused trip shows why on the map (undiscovered, in combat, cooldown).
-- * The Loadout terminal's prompt opens the loadout screen here (the server checks the location again).

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Travel = require(Shared:WaitForChild("Travel"))

local Kit = require(script.Parent.Parent.Ui.Kit)
local Juice = require(script.Parent.Parent.Fx.Juice)
local MapScreen = require(script.Parent.Parent.Ui.MapScreen)
local LoadoutScreen = require(script.Parent.Parent.Ui.LoadoutScreen)

local TravelClient = {}
TravelClient.flying = false

local REASONS = {
	undiscovered = "Find that beacon first",
	combat = "Not while fighting (wait a few seconds)",
	cooldown = "Fast travel is cooling down",
	traveling = "Already flying",
}

local gui: ScreenGui
local skip: TextButton
local trip: { from: Vector3, to: Vector3, time: number, start: number }? = nil

local function stop()
	trip = nil
	TravelClient.flying = false
	skip.Visible = false
	RunService:UnbindFromRenderStep("CapelineTravel")
	local cam = Workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	local char = Players.LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		cam.CameraSubject = hum
	end
end

local function start(data: any)
	MapScreen.close()
	trip = { from = data.from, to = data.to, time = data.time, start = os.clock() }
	TravelClient.flying = true
	Juice.fire("fastTravel")
	skip.Visible = true
	local cam = Workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep(
		"CapelineTravel",
		Enum.RenderPriority.Camera.Value + 2,
		FrameProf.wrap("TravelClient", function()
			local t0 = trip
			if not t0 then
				return
			end
			local f = math.clamp((os.clock() - t0.start) / t0.time, 0, 1)
			-- ease in and out so the flight reads as a swoop
			local e = f * f * (3 - 2 * f)
			local a, b = t0.from, t0.to
			local x, y, z = Travel.flightPath(a.X, a.Y, a.Z, b.X, b.Y, b.Z, e)
			local nx, ny, nz = Travel.flightPath(a.X, a.Y, a.Z, b.X, b.Y, b.Z, math.min(1, e + 0.05))
			local here = Vector3.new(x, y + 12, z)
			local ahead = Vector3.new(nx, ny, nz)
			if (ahead - here).Magnitude < 1 then
				ahead = b
			end
			cam.CFrame = CFrame.lookAt(here, ahead)
			if f >= 1 then
				-- wait at the end until the server says we have landed (FastTravelDone)
				cam.CFrame = CFrame.lookAt(b + Vector3.new(0, 18, 26), b)
			end
		end)
	)
end

function TravelClient.init()
	gui = Kit.screen("Travel", 9)
	skip = Kit.button({
		Text = "SKIP",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -Config.Ui.safe - 90),
		Visible = false,
	}, function()
		Net.send("MoveTravelSkip")
	end)
	skip.Parent = gui
	Net.listen("FastTravel", function(data)
		if data.ok then
			start(data)
		else
			local text = REASONS[data.reason or ""] or "Can't fast travel right now"
			if data.reason == "cooldown" and data.wait then
				text = string.format("Fast travel ready in %d s", math.ceil(data.wait))
			end
			MapScreen.say(text)
		end
	end)
	Net.listen("FastTravelDone", function()
		stop()
	end)
	Players.LocalPlayer.CharacterAdded:Connect(function()
		if trip then
			stop()
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if player == Players.LocalPlayer and prompt:GetAttribute("Terminal") == "loadout" then
			LoadoutScreen.open()
		end
	end)
end

return TravelClient
