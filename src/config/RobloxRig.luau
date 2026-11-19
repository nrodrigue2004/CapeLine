--!strict
-- RobloxRig: Roblox's own blocky R15 body, the one every hero, robot and citizen now stands on
-- (Config.Creator.robloxBody, HeroBody.robloxBody, ReplicatedStorage.RobloxBody; Decisions 2026-11-18/19). The
-- default body a blank HumanoidDescription gives at the classic scales (AvatarRules.SCALES), the same 15 meshes as
-- Studio's Rig Builder "Block" rig. Measured from that rig (pt-fit, 2026-11-19): each part's mesh asset, its box
-- size, its rest centre (studs, Roblox axes x right, y up, z back, feet on y = 0) and its attachments from that
-- centre. Roblox's limb boxes are taller than what they show and overlap at the joints (the upper arm is 1.169
-- tall, the arm shows as the classic 1 x 2 x 1 block from y 2 to 4), so creator pieces and weapons drawn on the
-- classic blocks (Config.HeroRig) are placed by Shared.BodyFit, never by these boxes alone. Pure data.
return {
	parts = {
		Head = {
			mesh = 7430070993,
			size = { 1.198, 1.202, 1.198 },
			centre = { 0, 4.5, 0 },
			attachments = {
				NeckRigAttachment = { 0, -0.5, 0 },
				FaceFrontAttachment = { 0, 0, -0.6 },
				HatAttachment = { 0, 0.6, 0 },
				HairAttachment = { 0, 0.6, 0 },
				FaceCenterAttachment = { 0, 0, 0 },
			},
		},
		UpperTorso = {
			mesh = 7430071038,
			size = { 2, 1.6, 1 },
			centre = { 0, 3.2, 0 },
			attachments = {
				WaistRigAttachment = { 0, -0.8, 0 },
				NeckRigAttachment = { 0, 0.8, 0 },
				LeftShoulderRigAttachment = { -1, 0.563, 0 },
				RightShoulderRigAttachment = { 1, 0.563, 0 },
				BodyFrontAttachment = { 0, -0.2, -0.5 },
				BodyBackAttachment = { 0, -0.2, 0.5 },
				LeftCollarAttachment = { -1, 0.8, 0 },
				RightCollarAttachment = { 1, 0.8, 0 },
				NeckAttachment = { 0, 0.8, 0 },
			},
		},
		LowerTorso = {
			mesh = 7430071109,
			size = { 2, 0.4, 1 },
			centre = { 0, 2.2, 0 },
			attachments = {
				RootRigAttachment = { 0, -0.2, 0 },
				WaistRigAttachment = { 0, 0.2, 0 },
				LeftHipRigAttachment = { -0.5, -0.2, 0 },
				RightHipRigAttachment = { 0.5, -0.2, 0 },
				WaistBackAttachment = { 0, -0.2, 0.5 },
				WaistCenterAttachment = { 0, -0.2, 0 },
				WaistFrontAttachment = { 0, -0.2, -0.5 },
			},
		},
		LeftUpperArm = {
			mesh = 7430071044,
			size = { 1, 1.169, 1 },
			centre = { -1.5, 3.369, 0 },
			attachments = {
				LeftShoulderRigAttachment = { 0.5, 0.394, 0 },
				LeftElbowRigAttachment = { 0, -0.334, 0 },
				LeftShoulderAttachment = { 0, 0.584, 0 },
			},
		},
		LeftLowerArm = {
			mesh = 7430071005,
			size = { 1, 1.052, 1 },
			centre = { -1.5, 2.776, 0 },
			attachments = {
				LeftElbowRigAttachment = { 0, 0.259, 0 },
				LeftWristRigAttachment = { 0, -0.501, 0 },
			},
		},
		LeftHand = {
			mesh = 7430070991,
			size = { 1, 0.3, 1 },
			centre = { -1.5, 2.15, 0 },
			attachments = {
				LeftWristRigAttachment = { 0, 0.125, 0 },
				LeftGripAttachment = { 0, -0.15, 0 },
			},
		},
		RightUpperArm = {
			mesh = 7430071041,
			size = { 1, 1.169, 1 },
			centre = { 1.5, 3.369, 0 },
			attachments = {
				RightShoulderRigAttachment = { -0.5, 0.394, 0 },
				RightElbowRigAttachment = { 0, -0.334, 0 },
				RightShoulderAttachment = { 0, 0.584, 0 },
			},
		},
		RightLowerArm = {
			mesh = 7430071013,
			size = { 1, 1.052, 1 },
			centre = { 1.5, 2.776, 0 },
			attachments = {
				RightElbowRigAttachment = { 0, 0.259, 0 },
				RightWristRigAttachment = { 0, -0.501, 0 },
			},
		},
		RightHand = {
			mesh = 7430070997,
			size = { 1, 0.3, 1 },
			centre = { 1.5, 2.15, 0 },
			attachments = {
				RightWristRigAttachment = { 0, 0.125, 0 },
				RightGripAttachment = { 0, -0.15, 0 },
			},
		},
		LeftUpperLeg = {
			mesh = 7430071065,
			size = { 1, 1.217, 1 },
			centre = { -0.5, 1.579, 0 },
			attachments = {
				LeftHipRigAttachment = { 0, 0.421, 0 },
				LeftKneeRigAttachment = { 0, -0.401, 0 },
			},
		},
		LeftLowerLeg = {
			mesh = 7430071049,
			size = { 1, 1.193, 1 },
			centre = { -0.5, 0.799, 0 },
			attachments = {
				LeftKneeRigAttachment = { 0, 0.379, 0 },
				LeftAnkleRigAttachment = { 0, -0.547, 0 },
			},
		},
		LeftFoot = {
			mesh = 7430071039,
			size = { 1, 0.3, 1 },
			centre = { -0.5, 0.15, 0 },
			attachments = {
				LeftAnkleRigAttachment = { 0, 0.102, 0 },
				LeftFootAttachment = { 0.018, -0.153, -0.05 },
			},
		},
		RightUpperLeg = {
			mesh = 7430071119,
			size = { 1, 1.217, 1 },
			centre = { 0.5, 1.579, 0 },
			attachments = {
				RightHipRigAttachment = { 0, 0.421, 0 },
				RightKneeRigAttachment = { 0, -0.401, 0 },
			},
		},
		RightLowerLeg = {
			mesh = 7430071105,
			size = { 1, 1.193, 1 },
			centre = { 0.5, 0.799, 0 },
			attachments = {
				RightKneeRigAttachment = { 0, 0.379, 0 },
				RightAnkleRigAttachment = { 0, -0.547, 0 },
			},
		},
		RightFoot = {
			mesh = 7430071082,
			size = { 1, 0.3, 1 },
			centre = { 0.5, 0.15, 0 },
			attachments = {
				RightAnkleRigAttachment = { 0, 0.102, 0 },
				RightFootAttachment = { -0.018, -0.153, -0.05 },
			},
		},
	},
}
