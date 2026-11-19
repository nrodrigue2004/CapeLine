--!strict
-- RigJoints: a character's animatable joints by their R15 name, whichever kind Roblox gave it (fix-anims,
-- 2026-11-19; nate: "there just still aren't animations for attacks or powers"). Roblox's Avatar Joint
-- Upgrade (StarterPlayer.AvatarJointUpgrade, "the default for new experiences") spawns R15 player characters
-- with AnimationConstraints instead of Motor6Ds. Code that only looked for Motor6Ds found no joints on the
-- player's hero, so HeroAnimator, EmoteFx and NpcGestures silently did nothing while robots (NpcRig's own
-- Motor6Ds) and Roblox's walk (the Animator) still moved. The place pins AvatarJointUpgrade to Disabled
-- (default.project.json), and every joint reader goes through here so either kind works:
-- * Motor6D: Transform (Animator layered) and C0 (writable) as before;
-- * AnimationConstraint: Transform works the same (the Animator writes it after PreAnimation, we layer in
--   PreSimulation); C0 and C1 are read-only aliases of its attachments, so nothing may write them.
-- A joint is keyed by its own name when it is a standard R15 joint name, else by its child part's.

local RigJoints = {}

-- the R15 joint that moves each part (its child part's name -> the joint's name)
local BY_PART: { [string]: string } = {
	LowerTorso = "Root",
	UpperTorso = "Waist",
	Head = "Neck",
	LeftUpperArm = "LeftShoulder",
	LeftLowerArm = "LeftElbow",
	LeftHand = "LeftWrist",
	RightUpperArm = "RightShoulder",
	RightLowerArm = "RightElbow",
	RightHand = "RightWrist",
	LeftUpperLeg = "LeftHip",
	LeftLowerLeg = "LeftKnee",
	LeftFoot = "LeftAnkle",
	RightUpperLeg = "RightHip",
	RightLowerLeg = "RightKnee",
	RightFoot = "RightAnkle",
}
RigJoints.BY_PART = BY_PART
local NAMES: { [string]: boolean } = {}
for _, j in BY_PART do
	NAMES[j] = true
end
RigJoints.NAMES = NAMES

-- true for an instance whose Transform poses a limb: a Motor6D or an AnimationConstraint
function RigJoints.isJoint(d: Instance): boolean
	return d:IsA("Motor6D") or d:IsA("AnimationConstraint")
end

-- the child part a joint moves (Motor6D.Part1, or an AnimationConstraint's Attachment1's part)
local function childOf(d: any): Instance?
	if d:IsA("Motor6D") then
		return d.Part1
	end
	local a1 = d.Attachment1
	return a1 and a1.Parent
end

-- every joint under a model by its R15 name; a Motor6D wins over a constraint of the same name (a rig mid-swap)
function RigJoints.of(model: Instance): { [string]: any }
	local out: { [string]: any } = {}
	for _, d in model:GetDescendants() do
		if RigJoints.isJoint(d) then
			local name = d.Name
			if not NAMES[name] then
				local part = childOf(d)
				name = part and RigJoints.BY_PART[part.Name] or name
			end
			local had = out[name]
			if not had or (not had:IsA("Motor6D") and d:IsA("Motor6D")) then
				out[name] = d
			end
		end
	end
	return out
end

-- true when this joint's C0 may be written (a Motor6D); an AnimationConstraint's C0 is read-only
function RigJoints.c0Writable(j: Instance): boolean
	return j:IsA("Motor6D")
end

return RigJoints
