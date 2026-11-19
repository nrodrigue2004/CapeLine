-- ImpactFx: momentum and impact on this device (nate's playtest 2026-11-19: "More weight, more impact with
-- everything ... it sends me back into a building and it destroys the building. Or even just flying at super
-- speed. Momentum and impact should destroy things").
-- * A ram (MoveController.Rammed: your hero hit a building's wall fast): tells the server (ImpactRam; ImpactService
--   checks it and knocks the pieces out, BuildingFx draws them), and plays the wall smash: a crunch, a camera shake
--   and punch, a burst of chips off the wall from the device's debris budget. MoveController holds the hit-stop.
-- * A throw that broke a wall (HeroKnock with `wall`): the same smash where you go through, timed to when you get
--   there.
-- PLACEHOLDER ART: the chips are plain blocks in the wall's colour.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local MoveController = require(script.Parent.Parent.Controllers.MoveController)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local Juice = require(script.Parent.Juice)
local DebrisBudget = require(script.Parent.DebrisBudget)

local ImpactFx = {}

local I = Config.Combat.impact
local CHIPS = 8
local CHIP_LIFE = 2.5
local CHIP_COLOR = Color3.fromRGB(150, 144, 136)

local folder: Folder? = nil

-- Chips flying off the wall at `at` (out along its normal)
local function chips(at: Vector3, normal: Vector3, color: Color3?)
	local n = DebrisBudget.lease(CHIPS, CHIP_LIFE)
	for _ = 1, n do
		local s = 0.6 + math.random() * 1.2
		local p = Instance.new("Part")
		p.Size = Vector3.new(s, s * 0.7, s)
		p.CFrame = CFrame.new(
			at + normal * 1.5 + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 3
		)
		p.Color = color or CHIP_COLOR
		p.Material = Enum.Material.Concrete
		p.CanCollide = true
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		local out = normal + Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5)
		p.AssemblyLinearVelocity = out.Unit * (24 + math.random() * 20)
		p.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
			* 10
		p.Parent = folder
		task.delay(CHIP_LIFE - 0.6, function()
			if p.Parent then
				TweenService:Create(p, TweenInfo.new(0.6), { Transparency = 1 }):Play()
			end
		end)
		task.delay(CHIP_LIFE, function()
			p:Destroy()
		end)
	end
end

-- The wall smash: sound, shake, punch, chips
function ImpactFx.smash(at: Vector3, normal: Vector3, strength: number, color: Color3?)
	local k = math.clamp(strength, 0.3, 1)
	Juice.fire("wallSmash", at, { mine = true })
	CameraController.shake(I.ram.shake[1], I.ram.shake[2] * k)
	CameraController.punch(0.05 * k)
	chips(at, normal, color)
end

function ImpactFx.init()
	folder = Instance.new("Folder")
	folder.Name = "ImpactFx"
	folder.Parent = Workspace
	MoveController.Rammed:Connect(function(at: Vector3, normal: Vector3, speed: number, _id: number)
		local dir = MoveController.velocity
		if dir.Magnitude < 1e-3 then
			dir = -normal
		end
		Net.send("ImpactRam", at, dir.Unit, math.clamp(speed, 0, 400))
		local R = I.ram
		local hit = Workspace:Raycast(at + normal, -normal * 3)
		local color = if hit and hit.Instance:IsA("BasePart") then hit.Instance.Color else nil
		ImpactFx.smash(at, normal, (speed - R.minSpeed) / (R.fullSpeed - R.minSpeed) + 0.4, color)
	end)
	Net.listen("HeroKnock", function(k: any)
		local w = type(k) == "table" and k.wall
		if type(w) ~= "table" or type(w.x) ~= "number" or type(w.y) ~= "number" or type(w.z) ~= "number" then
			return
		end
		local at = Vector3.new(w.x, w.y, w.z)
		local flat = Vector3.new(tonumber(k.x) or 0, 0, tonumber(k.z) or 0)
		local normal = if flat.Magnitude > 0.1 then -flat.Unit else Vector3.yAxis
		local delay = math.clamp((tonumber(w.t) or 0) * (tonumber(k.time) or 0.4), 0, 1)
		task.delay(delay, ImpactFx.smash, at, normal, 1)
	end)
end

return ImpactFx
