--!strict
-- ClimbAnim: the climbing, crawling, flipping and sprinting clips (move-2, nate's playtest 2026-11-19 20:42Z),
-- merged into Shared.HeroAnim's clip table (HeroAnim asserts no name is taken twice). Same conventions as HeroAnim:
-- degrees in each joint's frame, the 5th number a height offset (Root only); on a shoulder or hip +x swings the
-- limb forward and up, on an elbow +x bends the forearm forward, on a knee -x bends the shin back; on the waist
-- +x leans back; on the neck +x looks up; left limbs go outward with -z, right ones with +z.
-- Modes (MoveController's, the Move attribute others read): climb (the Hulk hang on a wall: both hands dug in
-- overhead, knees up against the face), bound (the vertical spring up the face to the next grab), vault (over the
-- top onto the roof: climbVault), crawl (the Acrobat flat on a wall or ceiling, limbs splayed, crawling), flip (the dodge: a
-- tucked flip, the Root turned once), runFast (everyone's sprint on Boost, between the run and Super-speed's).
-- One-shots (HeroAnim.transition): leapGrab (the hands slam into the face), leapRegrab (the next grab at a
-- bound's top), crawlLand (sticking to a face).
-- PLACEHOLDER ANIMATION: hand-keyed poses like the rest of HeroAnim until real animations are uploaded.
-- Pure: no Roblox types, so Lune tests and the pose previews (art/anim/climb_poses.luau) read it.

local ClimbAnim = {}

type Key = { number }
type Clip = { dur: number, loop: boolean?, joints: { [string]: { Key } } }

local function K(t: number, rx: number?, ry: number?, rz: number?, py: number?): Key
	return { t, rx or 0, ry or 0, rz or 0, py or 0 }
end
local function hold(rx: number?, ry: number?, rz: number?, py: number?): { Key }
	return { K(0, rx, ry, rz, py) }
end

local C: { [string]: Clip } = {}

-- The Hulk hang: both hands dug in overhead and wide, the elbows bent so the chest is close to the face, the knees
-- pulled up with the feet braced against the wall; a slow breath so it never freezes
C.climb = {
	dur = 1.6,
	loop = true,
	joints = {
		RightShoulder = { K(0, 158, 0, 22), K(0.8, 162, 0, 20), K(1.6, 158, 0, 22) },
		LeftShoulder = { K(0, 150, 0, -24), K(0.8, 154, 0, -22), K(1.6, 150, 0, -24) },
		RightElbow = { K(0, 46), K(0.8, 40), K(1.6, 46) },
		LeftElbow = { K(0, 52), K(0.8, 46), K(1.6, 52) },
		RightWrist = hold(-20),
		LeftWrist = hold(-20),
		Waist = { K(0, 8), K(0.8, 12), K(1.6, 8) },
		Neck = hold(26, -10),
		RightHip = hold(52, 0, 14),
		LeftHip = hold(34, 0, -18),
		RightKnee = hold(-84),
		LeftKnee = hold(-62),
		RightAnkle = hold(-20),
		LeftAnkle = hold(-14),
	},
}

-- The bound: the legs have just driven off the wall, the whole body stretched up, both arms reaching for the
-- next hold, the head up to see it
C.bound = {
	dur = 0.6,
	loop = true,
	joints = {
		RightShoulder = { K(0, 172, 0, 10), K(0.3, 176, 0, 6), K(0.6, 172, 0, 10) },
		LeftShoulder = { K(0, 164, 0, -14), K(0.3, 170, 0, -10), K(0.6, 164, 0, -14) },
		RightElbow = hold(10),
		LeftElbow = hold(18),
		Waist = hold(14),
		Neck = hold(36),
		RightHip = { K(0, -14, 0, 4), K(0.3, -6, 0, 4), K(0.6, -14, 0, 4) },
		LeftHip = { K(0, 8, 0, -4), K(0.3, 16, 0, -4), K(0.6, 8, 0, -4) },
		RightKnee = { K(0, -8), K(0.3, -18), K(0.6, -8) },
		LeftKnee = { K(0, -36), K(0.3, -48), K(0.6, -36) },
		RightAnkle = hold(-40),
		LeftAnkle = hold(-30),
	},
}

-- The vault: one hand planted on the edge, the body swung up and over, knees tucked (the air mode for
-- Config.Move.mobility.leap.climb.vault.time after the top)
C.climbVault = {
	dur = 0.42,
	joints = {
		RightShoulder = { K(0, 160, 0, 10), K(0.14, 70, 0, 10), K(0.42, 20, 0, 14) },
		LeftShoulder = { K(0, 150, 0, -12), K(0.14, 90, 0, -20), K(0.42, 40, 0, -40) },
		RightElbow = { K(0, 30), K(0.14, 6), K(0.42, 20) },
		LeftElbow = { K(0, 30), K(0.14, 10), K(0.42, 30) },
		Waist = { K(0, 10), K(0.14, -24), K(0.42, -6) },
		Neck = { K(0, 30), K(0.14, 10), K(0.42, 0) },
		RightHip = { K(0, 20), K(0.14, 96, 0, 10), K(0.42, 30) },
		LeftHip = { K(0, 10), K(0.14, 88, 0, -10), K(0.42, 50) },
		RightKnee = { K(0, -30), K(0.14, -118), K(0.42, -30) },
		LeftKnee = { K(0, -40), K(0.14, -110), K(0.42, -60) },
		Root = { K(0, 0), K(0.14, -30, 0, 0, 0.3), K(0.42, 0) },
	},
}

-- The wall crawl: flat on the face (the body's front into it, its head along the crawl), limbs splayed like a
-- spider, the diagonal pairs reaching on in turn; the head lifted to look where it goes
C.crawl = {
	dur = 0.7,
	loop = true,
	joints = {
		RightShoulder = { K(0, 150, 0, 50), K(0.35, 96, 0, 70), K(0.7, 150, 0, 50) },
		LeftShoulder = { K(0, 96, 0, -70), K(0.35, 150, 0, -50), K(0.7, 96, 0, -70) },
		RightElbow = { K(0, 40), K(0.35, 86), K(0.7, 40) },
		LeftElbow = { K(0, 86), K(0.35, 40), K(0.7, 86) },
		RightWrist = hold(-30),
		LeftWrist = hold(-30),
		Waist = { K(0, 6, 8), K(0.35, 6, -8), K(0.7, 6, 8) },
		Neck = hold(44),
		RightHip = { K(0, 20, 0, 48), K(0.35, 62, 0, 40), K(0.7, 20, 0, 48) },
		LeftHip = { K(0, 62, 0, -40), K(0.35, 20, 0, -48), K(0.7, 62, 0, -40) },
		RightKnee = { K(0, -96), K(0.35, -60), K(0.7, -96) },
		LeftKnee = { K(0, -60), K(0.35, -96), K(0.7, -60) },
		RightAnkle = hold(-30),
		LeftAnkle = hold(-30),
	},
}

-- The dodge: a tucked front flip, one whole turn of the Root (Config.Move.mobility.acrobat.flip.time)
C.flip = {
	dur = 0.32,
	joints = {
		Root = { K(0, 0, 0, 0, 0), K(0.16, -180, 0, 0, 0.6), K(0.32, -360, 0, 0, 0) },
		RightShoulder = { K(0, 60, 0, 30), K(0.1, 100, 0, 20), K(0.26, 100, 0, 20), K(0.32, 40, 0, 40) },
		LeftShoulder = { K(0, 60, 0, -30), K(0.1, 100, 0, -20), K(0.26, 100, 0, -20), K(0.32, 40, 0, -40) },
		RightElbow = { K(0, 40), K(0.1, 110), K(0.26, 110), K(0.32, 30) },
		LeftElbow = { K(0, 40), K(0.1, 110), K(0.26, 110), K(0.32, 30) },
		Waist = { K(0, -10), K(0.1, -40), K(0.26, -40), K(0.32, -10) },
		Neck = { K(0, 0), K(0.1, -30), K(0.26, -30), K(0.32, 0) },
		RightHip = { K(0, 30), K(0.1, 110), K(0.26, 110), K(0.32, 20) },
		LeftHip = { K(0, 30), K(0.1, 110), K(0.26, 110), K(0.32, 20) },
		RightKnee = { K(0, -50), K(0.1, -130), K(0.26, -130), K(0.32, -30) },
		LeftKnee = { K(0, -50), K(0.1, -130), K(0.26, -130), K(0.32, -30) },
	},
}

-- Everyone's sprint (Config.Move.sprint): a longer, harder stride than the walk, leaning in, fists pumping
C.runFast = {
	dur = 0.5,
	loop = true,
	joints = {
		Waist = hold(-12),
		Neck = hold(10),
		RightShoulder = { K(0, -48, 0, 6), K(0.25, 62, 0, 6), K(0.5, -48, 0, 6) },
		LeftShoulder = { K(0, 62, 0, -6), K(0.25, -48, 0, -6), K(0.5, 62, 0, -6) },
		RightElbow = hold(84),
		LeftElbow = hold(84),
		RightHip = { K(0, 56), K(0.25, -34), K(0.5, 56) },
		LeftHip = { K(0, -34), K(0.25, 56), K(0.5, -34) },
		RightKnee = { K(0, -16), K(0.125, -50), K(0.25, -96), K(0.375, -50), K(0.5, -16) },
		LeftKnee = { K(0, -96), K(0.125, -50), K(0.25, -16), K(0.375, -50), K(0.5, -96) },
		Root = {
			K(0, 0, 0, 0, -0.08),
			K(0.125, 0, 0, 0, 0.08),
			K(0.25, 0, 0, 0, -0.08),
			K(0.375, 0, 0, 0, 0.08),
			K(0.5, 0, 0, 0, -0.08),
		},
	},
}

-- The grab: the hands slam into the face from below the head and dig in, the knees come up hard
C.leapGrab = {
	dur = 0.32,
	joints = {
		RightShoulder = { K(0, 120, 0, 30), K(0.08, 170, 0, 30), K(0.32, 158, 0, 22) },
		LeftShoulder = { K(0, 110, 0, -30), K(0.08, 164, 0, -32), K(0.32, 150, 0, -24) },
		RightElbow = { K(0, 30), K(0.08, 10), K(0.32, 46) },
		LeftElbow = { K(0, 30), K(0.08, 14), K(0.32, 52) },
		Waist = { K(0, 0), K(0.08, 18), K(0.32, 8) },
		RightHip = { K(0, 10), K(0.08, 70, 0, 14), K(0.32, 52, 0, 14) },
		LeftHip = { K(0, 10), K(0.08, 60, 0, -18), K(0.32, 34, 0, -18) },
		RightKnee = { K(0, -30), K(0.08, -110), K(0.32, -84) },
		LeftKnee = { K(0, -30), K(0.08, -100), K(0.32, -62) },
		Root = { K(0, 0), K(0.08, 0, 0, 0, -0.25), K(0.32, 0) },
	},
}

-- The next grab at a bound's top: a quicker re-dig of the hands
C.leapRegrab = {
	dur = 0.2,
	joints = {
		RightShoulder = { K(0, 172, 0, 10), K(0.06, 166, 0, 26), K(0.2, 158, 0, 22) },
		LeftShoulder = { K(0, 164, 0, -14), K(0.06, 158, 0, -28), K(0.2, 150, 0, -24) },
		RightElbow = { K(0, 10), K(0.06, 30), K(0.2, 46) },
		LeftElbow = { K(0, 18), K(0.06, 34), K(0.2, 52) },
		RightKnee = { K(0, -8), K(0.06, -90), K(0.2, -84) },
		LeftKnee = { K(0, -36), K(0.06, -80), K(0.2, -62) },
	},
}

-- Sticking to a face (the crawl begins): splayed, a little squash into it
C.crawlLand = {
	dur = 0.28,
	joints = {
		RightShoulder = { K(0, 130, 0, 30), K(0.08, 120, 0, 70), K(0.28, 150, 0, 50) },
		LeftShoulder = { K(0, 130, 0, -30), K(0.08, 120, 0, -70), K(0.28, 96, 0, -70) },
		RightElbow = { K(0, 20), K(0.08, 90), K(0.28, 40) },
		LeftElbow = { K(0, 20), K(0.08, 90), K(0.28, 86) },
		RightHip = { K(0, 30), K(0.08, 40, 0, 56), K(0.28, 20, 0, 48) },
		LeftHip = { K(0, 30), K(0.08, 40, 0, -56), K(0.28, 62, 0, -40) },
		RightKnee = { K(0, -40), K(0.08, -110), K(0.28, -96) },
		LeftKnee = { K(0, -40), K(0.08, -110), K(0.28, -60) },
		Root = { K(0, 0), K(0.08, 0, 0, 0, -0.2), K(0.28, 0) },
	},
}

ClimbAnim.CLIPS = C

-- the new movement modes (appended to HeroAnim.MODES, never reordered)
ClimbAnim.MODES = { "climb", "bound", "crawl", "flip", "climbVault" }

ClimbAnim.runFastSpeed = 25 -- running faster than this (everyone's sprint on Boost) takes the sprint stride

return ClimbAnim
