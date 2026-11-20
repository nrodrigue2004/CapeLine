-- ImpactFx: momentum and impact on this device (nate's playtest 2026-11-19: "More weight, more impact with
-- everything ... it sends me back into a building and it destroys the building. Or even just flying at super
-- speed. Momentum and impact should destroy things").
-- * A ram (MoveController.Rammed: your hero hit a building's wall fast): tells the server (ImpactRam; ImpactService
--   checks it and knocks the pieces out, BuildingFx draws them), and plays the wall smash: a crunch, a camera shake
--   and punch, a burst of chips and a puff of dust off the wall in its own colour: textured particles through the
--   effects library since gap-fx3, 2026-11-19 (FxLib.throwMoment "smash", Config.Fx.lib.throw, the uploaded
--   chip.png; inside the preset's particle budget). MoveController holds the hit-stop.
-- * A ram through a vehicle or a dressed look (BuildingFx.onPropSmash, destroy-all 2026-11-20): the same smash.
-- * A throw that broke a wall (HeroKnock with `wall`): the same smash where you go through, timed to when you get
--   there.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local MoveController = require(script.Parent.Parent.Controllers.MoveController)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local Juice = require(script.Parent.Juice)
local FxLib = require(script.Parent.FxLib)
local BuildingFx = require(script.Parent.BuildingFx)
local ImpactRules = require(Shared:WaitForChild("ImpactRules"))

local ImpactFx = {}

local I = Config.Combat.impact
local CHIP_COLOR = Color3.fromRGB(150, 144, 136)

-- Chips and dust flying off the wall at `at` (out along its normal), in the wall's colour
local function chips(at: Vector3, normal: Vector3, color: Color3?)
	FxLib.throwMoment("smash", at + normal * 1.5, color or CHIP_COLOR, normal, 3)
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
	-- destroy-all (2026-11-20): a ram through a car or a park structure smashes like a wall, a little lighter
	BuildingFx.onPropSmash = function(at: Vector3, color: Color3, strength: number)
		local v = MoveController.velocity
		local normal = if v.Magnitude > 1e-3 then -v.Unit else Vector3.yAxis
		ImpactFx.smash(at, normal, strength, color)
	end
	MoveController.Rammed:Connect(function(at: Vector3, normal: Vector3, speed: number, id: number)
		local dir = MoveController.velocity
		if dir.Magnitude < 1e-3 then
			dir = -normal
		end
		Net.send("ImpactRam", at, dir.Unit, math.clamp(speed, 0, 400))
		local R = I.ram
		-- the hole opens here now (fix-destroy): the same blast the server will run, so the hero flies on through
		-- Blazing Ram (Flight rank 5): more damage, the pieces blown outward (MoveActService does the same sum)
		local blaze = MoveController.has("blazeRam")
		local B = Config.Move.moves.blazeRam
		BuildingFx.predict(
			id,
			at + dir.Unit * 1.5,
			ImpactRules.ramDamage(R, speed) * (if blaze then B.ram else 1),
			R.radius,
			nil,
			if blaze then B.throw else nil
		)
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
