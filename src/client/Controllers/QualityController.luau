-- QualityController: picks the device preset (spec: Streaming and device presets): phones start on low,
-- tablets, PCs and consoles on medium (Shared.QualityRules.device; Config.Presets.auto), then a 5 s
-- frame-time test after spawning moves one step down (under 40 fps) or up to high (over 58 fps on a PC or
-- console). After that a watch steps down once more when the game stays slow (phone pass: a phone that
-- heats up mid-fight drops to low by itself). Settings can fix a preset (QualityController.choose); the
-- test and the watch leave a fixed one alone. A preset sets shadows, Bloom and SunRays here; the renderers
-- read the rest (QualityController.preset). Client only.

local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FrameProf = require(Shared:WaitForChild("FrameProf"))
local QualityRules = require(Shared:WaitForChild("QualityRules"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local P = Config.Presets

local QualityController = {}
QualityController.name = "medium"
QualityController.preset = P.medium
QualityController.Changed = Signal.new()
QualityController.fps = 60
QualityController.device = "pc" :: QualityRules.Device

local function effect(className: string, on: boolean)
	for _, e in Lighting:GetChildren() do
		if e:IsA(className) then
			(e :: any).Enabled = on
		end
	end
end

function QualityController.set(name: string)
	if not P[name] then
		return
	end
	local p = P[name]
	QualityController.name = name
	QualityController.preset = p
	Lighting.GlobalShadows = p.shadows
	effect("BloomEffect", p.bloom ~= false)
	effect("SunRaysEffect", p.sunRays ~= false)
	QualityController.Changed:Fire(name)
end

-- Settings: 0 Auto (the device pick, frame test and watch), else a fixed preset they leave alone
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

local function setAuto(name: string)
	autoName = name
	if not QualityController.fixed and QualityController.name ~= name then
		QualityController.set(name)
	end
end

function QualityController.init()
	local cam = Workspace.CurrentCamera
	local size = if cam then cam.ViewportSize else Vector2.new(800, 400)
	local device = QualityRules.device(
		UserInputService.TouchEnabled,
		UserInputService.KeyboardEnabled,
		GuiService:IsTenFootInterface(),
		size.X,
		size.Y
	)
	QualityController.device = device
	autoName = QualityRules.auto(P, device)
	if not QualityController.fixed then
		QualityController.set(autoName)
	end
	-- running fps for the Dev panel, and the slow watch once the frame test is done
	local watch = QualityRules.newWatch()
	local watching = false
	local frames, acc = 0, 0
	RunService.RenderStepped:Connect(FrameProf.wrap("QualityController", function(dt)
		frames += 1
		acc += dt
		if acc >= 1 then
			QualityController.fps = frames / acc
			if watching and not QualityController.fixed then
				setAuto(QualityRules.watchStep(P, watch, autoName, QualityController.fps, acc))
			end
			frames, acc = 0, 0
		end
	end))
	task.delay(4, function()
		local t0, n = os.clock(), 0
		local conn = RunService.RenderStepped:Connect(FrameProf.wrap("QualityController", function()
			n += 1
		end))
		task.wait(P.frameTest.seconds)
		conn:Disconnect()
		local fps = n / (os.clock() - t0)
		setAuto(QualityRules.frameStep(P, autoName, fps, device))
		watching = true
	end)
end

return QualityController
