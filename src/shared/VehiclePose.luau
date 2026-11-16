-- VehiclePose: a vehicle's root CFrame at home and partway through a flip (spec: Clash moments > Vehicle
-- flip). Shared so the server's landed pose and every client's 1 s arc come from the same maths
-- (Vehicles.flipPose). Uses CFrame, so Lune tests Vehicles.flipPose instead.

local Vehicles = require(script.Parent.Vehicles)

local VehiclePose = {}

function VehiclePose.home(v: any): CFrame
	return CFrame.new(v.x, v.y, v.z) * CFrame.Angles(0, math.rad(v.ry), 0)
end

-- The root pose at flip fraction t (0 at home, 1 landed on its roof), pushed along (dx, dz)
function VehiclePose.flip(cfg: any, v: any, t: number, dx: number, dz: number): CFrame
	local ox, oy, oz, roll = Vehicles.flipPose(cfg, v, t, dx, dz)
	local axis = Vector3.new(dz, 0, -dx)
	if axis.Magnitude < 1e-3 then
		axis = Vector3.new(1, 0, 0)
	end
	-- roll about the vehicle's middle, so it lands on its roof where it rolled to
	local mid = Vector3.new(0, v.sy / 2 + 1, 0)
	local base = VehiclePose.home(v)
	local turned = CFrame.new(base.Position + mid) * CFrame.fromAxisAngle(axis.Unit, roll) * CFrame.new(-mid)
	return CFrame.new(ox, oy, oz) * turned * base.Rotation
end

-- Place every part of a vehicle model at a root pose (each part keeps its Offset attribute)
function VehiclePose.apply(m: Model, root: CFrame)
	for _, p in m:GetChildren() do
		if p:IsA("BasePart") then
			local offset = p:GetAttribute("Offset")
			if typeof(offset) == "CFrame" then
				p.CFrame = root * offset
			end
		end
	end
end

return VehiclePose
