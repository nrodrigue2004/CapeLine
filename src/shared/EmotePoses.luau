--!strict
-- EmotePoses: every emote, landing pose and photo pose as joint angles (moved here from Fx.EmoteFx, 2026-11-19, so
-- the picture tiles render the very poses the game plays). Pure data: Lune runs it, art/thumbs/pieces.luau
-- exports it for art/blender/clothed.py poses. Keys are Config.Shop.emotes ids, then Photo Mode's own poses
-- (101 and up). Each pose: R15 Motor6D name -> { x, y, z } degrees; EmoteFx tweens each joint's C0 to
-- C0 * CFrame.Angles(x, y, z) (Root turns the whole body). PLACEHOLDER ART until real animations (M11).

local EmotePoses = {}

export type Pose = { [string]: { number } }

local POSES: { [number]: Pose } = {}

POSES = {
	[1] = { RightShoulder = { 0, 0, 150 }, RightElbow = { 0, 0, 110 }, Neck = { -5, 0, 0 } }, -- Salute
	[2] = { Waist = { -45, 0, 0 }, Neck = { -20, 0, 0 }, RightShoulder = { -30, 0, 0 } }, -- Bow
	[3] = { RightShoulder = { 0, 0, 160 }, RightElbow = { 0, 0, 30 } }, -- Wave
	[4] = { RightShoulder = { 70, 0, 0 }, RightElbow = { 80, 0, 0 } }, -- Thumbs Up
	[5] = {
		RightShoulder = { 0, 0, 90 },
		LeftShoulder = { 0, 0, -90 },
		RightElbow = { 0, 0, 100 },
		LeftElbow = { 0, 0, -100 },
	}, -- Flex
	[6] = {
		RightShoulder = { 0, 0, 30 },
		LeftShoulder = { 0, 0, -30 },
		Neck = { 10, 20, 0 },
		RightHip = { 0, 0, 12 },
		LeftHip = { 0, 0, -12 },
	}, -- Hero Pose (fists on hips, chin up)
	[7] = { RightShoulder = { 0, 0, 175 }, Neck = { 25, 0, 0 } }, -- Point Up
	[8] = {
		RightShoulder = { 40, 0, 40 },
		LeftShoulder = { 40, 0, -40 },
		Waist = { -15, 0, 0 },
		RightKnee = { -30, 0, 0 },
		LeftKnee = { -30, 0, 0 },
	}, -- Power Up (a crouch, fists clenched)
	[9] = { Waist = { 20, 0, 0 }, Neck = { 30, 0, 0 }, RightShoulder = { 20, 0, 20 } }, -- Laugh
	[10] = { Waist = { 0, 50, 0 }, RightShoulder = { 0, 0, 100 }, LeftShoulder = { 0, 0, -40 } }, -- Cape Swish
	[11] = {
		RightShoulder = { 0, 0, 165 },
		LeftShoulder = { 0, 0, -165 },
		Neck = { 15, 0, 0 },
	}, -- Rookie Cheer
	[20] = {
		Waist = { -35, 0, 0 },
		RightShoulder = { 0, 0, 60 },
		LeftShoulder = { -40, 0, -20 },
		RightHip = { 70, 0, 0 },
		RightKnee = { -100, 0, 0 },
		LeftHip = { -20, 0, 0 },
		LeftKnee = { -60, 0, 0 },
	}, -- Super Landing (one knee, one fist down)
	[21] = {
		Waist = { -20, 0, 0 },
		RightHip = { 80, 0, 0 },
		RightKnee = { -90, 0, 0 },
		LeftKnee = { -80, 0, 0 },
		Neck = { -10, 0, 0 },
	}, -- Kneel Landing
	[22] = { Root = { 0, 180, 0 }, RightShoulder = { 0, 0, 90 }, LeftShoulder = { 0, 0, -90 } }, -- Spin Landing
	[23] = {
		Waist = { -50, 0, 0 },
		RightShoulder = { -60, 0, 20 },
		LeftShoulder = { -60, 0, -20 },
		RightKnee = { -110, 0, 0 },
		LeftKnee = { -110, 0, 0 },
	}, -- Crater Landing (both fists into the ground)
	[25] = {
		Root = { 0, 180, 0 },
		RightShoulder = { 0, 0, 160 },
		LeftShoulder = { 0, 0, -160 },
		Neck = { -10, 0, 0 },
	}, -- Spotlight Landing: land facing out, both arms up (H8 Hero Pass)
	[24] = {
		RightShoulder = { 0, 0, 45 },
		LeftShoulder = { 0, 0, -45 },
		RightKnee = { -20, 0, 0 },
		Neck = { 10, 0, 0 },
	}, -- Float Down
	-- H6: the mentors' emotes (Config.Mentors)
	[12] = {
		RightShoulder = { 0, 0, 160 },
		RightElbow = { 0, 0, 125 },
		Neck = { -8, 0, 0 },
		LeftShoulder = { 0, 0, -10 },
	}, -- Sharp Salute
	[13] = {
		RightShoulder = { 0, 0, 170 },
		LeftShoulder = { 0, 0, -170 },
		RightElbow = { 0, 0, 20 },
		LeftElbow = { 0, 0, -20 },
	}, -- Big Wave (both arms)
	[14] = {
		Waist = { -60, 0, 0 },
		Neck = { -15, 0, 0 },
		RightShoulder = { 40, 0, 20 },
		LeftShoulder = { -50, 0, -20 },
	}, -- Grand Bow (one arm across, one behind)
	[15] = {
		RightShoulder = { 0, 0, 40 },
		LeftShoulder = { 0, 0, -40 },
		RightElbow = { 0, 0, 90 },
		LeftElbow = { 0, 0, -90 },
		Neck = { 0, 0, 12 },
	}, -- Shrug
	[16] = {
		RightShoulder = { 0, 0, 80 },
		LeftShoulder = { 0, 0, -80 },
		RightElbow = { 0, 0, 100 },
		LeftElbow = { 0, 0, -100 },
		Neck = { -6, 0, 0 },
	}, -- Double Thumbs Up (H7 accolade)
	[17] = {
		Waist = { -30, 0, 0 },
		Neck = { -20, 0, 0 },
		RightShoulder = { 70, 0, 60 },
		LeftShoulder = { 70, 0, -60 },
	}, -- Team Huddle: lean in, arms out round your mates (H7 accolade)
	[18] = {
		RightShoulder = { 0, 0, 150 },
		RightElbow = { 0, 0, 40 },
		LeftShoulder = { 0, 0, -30 },
		LeftElbow = { 0, 0, -80 },
		Waist = { 0, 20, 0 },
	}, -- Comic Pose: one fist up, one on the hip (H8 Hero Pass)
	[19] = {
		Root = { 0, 180, 0 },
		RightShoulder = { 0, 0, 120 },
		LeftShoulder = { 0, 0, -120 },
	}, -- Spotlight Spin: a half turn to face the crowd, arms up (H8 Hero Pass)
	-- Photo Mode's own poses (free, only on your screen while you take a photo; M11)
	[101] = {
		RightShoulder = { 80, 0, 20 },
		LeftShoulder = { 80, 0, -20 },
		RightElbow = { 90, 0, 0 },
		LeftElbow = { 90, 0, 0 },
		RightKnee = { -15, 0, 0 },
	}, -- Ready Stance (fists up)
	[102] = { RightShoulder = { 120, 0, 40 }, RightElbow = { 100, 0, 0 }, Neck = { 10, 15, 0 } }, -- Look Out
	[103] = {
		RightShoulder = { 0, 0, 170 },
		LeftShoulder = { 0, 0, -20 },
		LeftHip = { -25, 0, 0 },
		LeftKnee = { -50, 0, 0 },
	}, -- Take Off (one fist to the sky)
	[104] = { RightShoulder = { 100, 0, 30 }, RightElbow = { 130, 0, 0 }, Neck = { -10, -10, 0 } }, -- Thinking
}

EmotePoses.POSES = POSES
EmotePoses.PHOTO_POSES = { 101, 102, 103, 104 }
EmotePoses.POSE_NAMES = { [101] = "Ready", [102] = "Look Out", [103] = "Take Off", [104] = "Thinking" }

return EmotePoses
