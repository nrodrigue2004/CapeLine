--!strict
-- BodyShape: how a look's body (gender, build, height) scales the blocky R15 rig (nate's hero creator plan,
-- 2026-11-16: Small, Medium, Large, Titan for "hulk or thing fantasies", 5 heights). Looks only: the
-- HumanoidRootPart (the one collider and the combat hit capsule) never changes, so no body is harder to hit
-- or blocked by doors. Pure, so Lune tests it; LookKit.shapeBody applies it to a character.
-- Each part gets x, y, z factors on its own size; its attachments move by the same factors, so the joints
-- (shoulders on a wide Titan torso, hips on a narrow waist) follow on their own.

local BodyShape = {}

export type Factors = { [string]: { number } }

local TORSO = { UpperTorso = true, LowerTorso = true }
local ARMS = { LeftUpperArm = true, RightUpperArm = true, LeftLowerArm = true, RightLowerArm = true }
local HANDS = { LeftHand = true, RightHand = true }
local LEGS = {
	LeftUpperLeg = true,
	RightUpperLeg = true,
	LeftLowerLeg = true,
	RightLowerLeg = true,
	LeftFoot = true,
	RightFoot = true,
}
BodyShape.PARTS = {
	"Head",
	"UpperTorso",
	"LowerTorso",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
}

local function pick(list: { any }, i: any, default: number): any
	return list[if type(i) == "number" then i else default] or list[default]
end

-- The per-part factors and the hip height factor for a look's body
function BodyShape.factors(Config: any, look: any): (Factors, number)
	local B = Config.Creator.body
	local build = pick(B.builds, look.build, 2)
	local tall = build.tall * pick(B.heights, look.height, 3)
	local female = look.gender == 2
	local out: Factors = {}
	for _, name in BodyShape.PARTS do
		if name == "Head" then
			out[name] = { build.head, build.head, build.head }
		elseif TORSO[name] then
			local w = build.width
			if female and name == "LowerTorso" then
				w *= B.femaleWaist
			end
			out[name] = { w, tall, build.depth }
		elseif ARMS[name] then
			out[name] = { build.limbs, tall, build.limbs }
		elseif HANDS[name] then
			out[name] = { build.hands, build.hands, build.hands }
		elseif LEGS[name] then
			-- two legs always fit under the waist
			local waist = build.width * (if female then B.femaleWaist else 1)
			local t = math.min(build.limbs, waist)
			out[name] = { t, tall, math.min(build.limbs, build.depth) }
		end
	end
	return out, tall
end

-- The body set a look wears (art/blender/bodies.py): "<Gender><Build>", e.g. "FemaleTitan". Each set is the
-- blocky hero reshaped (tapers, a V on the big builds, a soft chest and hips on the female sets); its meshes are
-- ReplicatedStorage.Art.Bodies["<Set>_<Part>"], and a part a set does not change is the hero's own
-- (Art.Hero). "MaleMedium" is the hero body itself.
function BodyShape.setKey(Config: any, look: any): string
	local B = Config.Creator.body
	local build = pick(B.builds, look.build, 2)
	return (if look.gender == 2 then "Female" else "Male") .. build.name
end

-- Is this the standard body (nothing to scale)?
function BodyShape.standard(look: any): boolean
	return (look.build or 2) == 2 and (look.height or 3) == 3 and (look.gender or 1) == 1
end

return BodyShape
