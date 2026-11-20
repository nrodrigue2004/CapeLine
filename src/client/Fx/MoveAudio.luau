-- MoveAudio: the movement sounds no one else plays (the sounds pass, 2026-11-19; nate: "need better sounds badly",
-- pillars: impact and weight). Listens to MoveController's signals and speed, plays Config.Audio rows through the
-- AudioController, and changes nothing about movement:
-- * pound: a Leaping ground pound landing (MoveController.Pounded), with its duck under the boom
-- * bounce: an awning springing the hero up (Bounced); splash: going into the water (mode "water")
-- * dash: the Acrobat's dash (mode "dash")
-- * sonicBoom: the moment your speed first passes Config.Audio.move.boomSpeed (a boost, a Super Speed sprint, a
--   long dive), with a short camera shake; again only after dropping below boomReset and boomGap seconds
-- * speedRun: the held rush of a Super Speed run, its volume and pitch from the run's speed

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local MoveController = require(script.Parent.Parent.Controllers.MoveController)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local AudioController = require(script.Parent.Parent.Controllers.AudioController)
local State = require(script.Parent.Parent.State)

local MoveAudio = {}

local M = Config.Audio.move
local player = Players.LocalPlayer

local function rootPos(): Vector3?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root and root.Position
end

-- Whether a sonic boom fires now (pure rule, so tests can read it): above boomSpeed, armed, and boomGap after the last
function MoveAudio.boomNow(speed: number, armed: boolean, sinceLast: number): boolean
	return armed and speed >= M.boomSpeed and sinceLast >= M.boomGap
end

function MoveAudio.init()
	MoveController.Pounded:Connect(function(pos: Vector3)
		AudioController.play("pound", pos)
	end)
	MoveController.Bounced:Connect(function(pos: Vector3)
		AudioController.play("bounce", pos)
	end)
	local MODE_SOUND: { [string]: string } = { water = "splash", dash = "dash" }
	MoveController.ModeChanged:Connect(function(mode: string, old: string)
		local id = MODE_SOUND[mode]
		if id and old ~= mode then
			AudioController.play(id, rootPos())
		end
	end)
	local armed, lastBoom = true, -99
	RunService.Heartbeat:Connect(FrameProf.wrap("MoveAudio", function()
		local v = MoveController.velocity
		local speed = v.Magnitude
		local now = os.clock()
		if MoveAudio.boomNow(speed, armed, now - lastBoom) then
			armed, lastBoom = false, now
			AudioController.play("sonicBoom", rootPos())
			CameraController.shake(M.boomShake[1], M.boomShake[2])
		elseif speed < M.boomReset then
			armed = true
		end
		local mode = MoveController.mode
		local flat = Vector3.new(v.X, 0, v.Z).Magnitude
		local running = State.hero.mobility == "speed" and mode == "ground" and flat > M.runFrom
		local k = math.clamp((flat - M.runFrom) / (M.runFull - M.runFrom), 0, 1)
		AudioController.loop("speedRun", running, if running then 0.05 + (M.runVolume - 0.05) * k else nil)
	end))
end

return MoveAudio
