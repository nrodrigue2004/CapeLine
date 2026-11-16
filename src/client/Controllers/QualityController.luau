-- QualityController: picks the device preset (spec: Streaming and device presets): phones start on low,
-- tablets and PCs on medium, then a 5 s frame-time test after spawning moves one step down (under 40 fps)
-- or up to high (over 58 fps on a non-touch device). Settings can fix a preset (QualityController.choose). Client only.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Signal"))

local P = Config.Presets

local QualityController = {}
QualityController.name = "medium"
QualityController.preset = P.medium
QualityController.Changed = Signal.new()
QualityController.fps = 60

function QualityController.set(name: string)
	if not P[name] then
		return
	end
	QualityController.name = name
	QualityController.preset = P[name]
	Lighting.GlobalShadows = P[name].shadows
	QualityController.Changed:Fire(name)
end

-- Settings: 0 Auto (the device pick and frame test), else a fixed preset that the frame test leaves alone
QualityController.fixed = false
local autoName = "medium"
function QualityController.choose(index: number)
	if index <= 0 then
		QualityController.fixed = false
		QualityController.set(autoName)
	elseif P.order[index] then
		QualityController.fixed = true
		QualityController.set(P.order[index])
	end
end

function QualityController.init()
	local phone = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	autoName = if phone then "low" else "medium"
	if not QualityController.fixed then
		QualityController.set(autoName)
	end
	-- running fps for the Dev panel
	local frames, acc = 0, 0
	RunService.RenderStepped:Connect(function(dt)
		frames += 1
		acc += dt
		if acc >= 1 then
			QualityController.fps = frames / acc
			frames, acc = 0, 0
		end
	end)
	task.delay(4, function()
		local t0, n = os.clock(), 0
		local conn = RunService.RenderStepped:Connect(function()
			n += 1
		end)
		task.wait(P.frameTest.seconds)
		conn:Disconnect()
		local fps = n / (os.clock() - t0)
		local idx = table.find(P.order, autoName) :: number
		if fps < P.frameTest.lowBelow and idx > 1 then
			autoName = P.order[idx - 1]
		elseif fps > P.frameTest.highAbove and not phone and idx < #P.order then
			autoName = P.order[idx + 1]
		end
		if not QualityController.fixed then
			QualityController.set(autoName)
		end
	end)
end

return QualityController
