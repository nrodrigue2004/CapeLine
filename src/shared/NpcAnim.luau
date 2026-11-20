--!strict
-- NpcAnim: the robots' and the people's clips as data (pt-anims, nate's playtest 2026-11-19: "for animations
-- don't forget about not only the player and everything they can do, but npcs, enemies, bosses"). Same key
-- format and joint frames as Shared.HeroAnim (degrees; on a shoulder +x swings the arm forward and up, right
-- limbs go out with +z; on the waist -x leans forward, +y turns the chest left; on a knee -x bends it), sampled
-- with HeroAnim.sampleKeys, so one sampler serves everyone. A clip moves only the joints it lists.
-- * Robots (EnemyRenderer): per AI kind (Config.Enemies ai) a wind-up held while the server's windup flag is
--   up, a strike per attack event (swing, shot, slam, lob, rally, hook), a hit react and a heavy hit react on
--   EnemyRenderer.impact, and a stagger loop while stunned. Each strike has a readable wind-up, the hit and a
--   recovery; the root's own lean, lunge, coil, recoil and tumble stay EnemyRenderer's code.
-- * People (NpcGestures and CitizenRenderer): idle variety for quest givers, named helpers and standing
--   citizens: talk, wave, point, beckon, shrug, arms crossed, look around, check the time. Upper body only, so
--   the legs keep Roblox's idle (or the giver's stance).
-- PLACEHOLDER ANIMATION: hand-keyed, like HeroAnim, until real animations are made and uploaded.
-- Pure: no Roblox types, so Lune tests it.

local NpcAnim = {}

local HeroAnim = if script then require((script :: any).Parent.HeroAnim) else (require :: any)("./HeroAnim")

type Key = { number }
export type Clip = { dur: number, loop: boolean?, joints: { [string]: { Key } } }

local function K(t: number, rx: number?, ry: number?, rz: number?): Key
	return { t, rx or 0, ry or 0, rz or 0, 0 }
end
local function hold(rx: number?, ry: number?, rz: number?): { Key }
	return { K(0, rx, ry, rz) }
end

-- A strike in five beats: rest, wind-up (a), contact (c), follow-through (f), rest. spec[joint] =
-- { wind, hit, follow? } as { rx, ry, rz }; a joint's rest is its 4th entry (default 0, 0, 0)
local function strike(dur: number, a: number, c: number, spec: { [string]: { { number } } }): Clip
	local f = math.min(c + (1 - c) * 0.45, 0.95)
	local joints: { [string]: { Key } } = {}
	for joint, p in spec do
		local w, h = p[1], p[2]
		local fo = p[3] or { h[1] * 0.9, h[2] * 0.9, h[3] * 0.9 }
		local r = p[4] or { 0, 0, 0 }
		joints[joint] = {
			K(0, r[1], r[2], r[3]),
			K(dur * a, w[1], w[2], w[3]),
			K(dur * c, h[1], h[2], h[3]),
			K(dur * f, fo[1], fo[2], fo[3]),
			K(dur, r[1], r[2], r[3]),
		}
	end
	return { dur = dur, joints = joints }
end

local C: { [string]: Clip } = {}
NpcAnim.CLIPS = C

-- ------------------------------------------------------------------ robots: wind-ups (held loops)
C.windupOverhead = { -- both fists raised for a slam, trembling with the charge
	dur = 0.4,
	loop = true,
	joints = {
		RightShoulder = { K(0, 165, 0, 12), K(0.2, 170, 0, 14), K(0.4, 165, 0, 12) },
		LeftShoulder = { K(0, 165, 0, -12), K(0.2, 170, 0, -14), K(0.4, 165, 0, -12) },
		RightElbow = hold(30),
		LeftElbow = hold(30),
		Waist = { K(0, 16), K(0.2, 18), K(0.4, 16) },
		Neck = hold(-10),
	},
}
C.windupAim = { -- the gun arm levelled, the other hand bracing it, the body set
	dur = 0.5,
	loop = true,
	joints = {
		RightShoulder = { K(0, 90, 0, -6), K(0.25, 91, 0, -6), K(0.5, 90, 0, -6) },
		RightElbow = hold(4),
		LeftShoulder = hold(80, 0, 30),
		LeftElbow = hold(70),
		Waist = hold(4, 16),
		Neck = hold(0, -14),
	},
}
C.windupSwing = { -- one arm cocked back across the chest for a swing
	dur = 0.5,
	loop = true,
	joints = {
		RightShoulder = { K(0, 70, 0, 70), K(0.25, 74, 0, 74), K(0.5, 70, 0, 70) },
		RightElbow = hold(60),
		LeftShoulder = hold(40, 0, -30),
		LeftElbow = hold(60),
		Waist = hold(6, 34),
		Neck = hold(0, -26),
	},
}
C.windupThrow = { -- the throwing arm drawn back behind the head
	dur = 0.5,
	loop = true,
	joints = {
		RightShoulder = { K(0, 150, 0, 30), K(0.25, 154, 0, 32), K(0.5, 150, 0, 30) },
		RightElbow = hold(100),
		LeftShoulder = hold(70, 0, -10),
		LeftElbow = hold(20),
		Waist = hold(12, 26),
		Neck = hold(0, -20),
	},
}
C.windupShield = { -- the shield arm braced, shoulder into it
	dur = 0.6,
	loop = true,
	joints = {
		LeftShoulder = { K(0, 80, 0, 10), K(0.3, 82, 0, 10), K(0.6, 80, 0, 10) },
		LeftElbow = hold(70),
		RightShoulder = hold(30, 0, 20),
		RightElbow = hold(80),
		Waist = hold(-10, -20),
		Neck = hold(6, 16),
	},
}
C.windupClaw = { -- both claws up and spread, ready to rake
	dur = 0.3,
	loop = true,
	joints = {
		RightShoulder = { K(0, 130, 0, 40), K(0.15, 134, 0, 44), K(0.3, 130, 0, 40) },
		LeftShoulder = { K(0, 130, 0, -40), K(0.15, 134, 0, -44), K(0.3, 130, 0, -40) },
		RightElbow = hold(50),
		LeftElbow = hold(50),
		Waist = hold(-14),
		Neck = hold(16),
	},
}
C.windupHook = { -- the hook launcher wound back at the hip
	dur = 0.5,
	loop = true,
	joints = {
		RightShoulder = { K(0, -40, 0, 20), K(0.25, -44, 0, 22), K(0.5, -40, 0, 20) },
		RightElbow = hold(40),
		LeftShoulder = hold(60, 0, -20),
		LeftElbow = hold(30),
		Waist = hold(8, 30),
		Neck = hold(0, -24),
	},
}

-- ------------------------------------------------------------------ robots: strikes (one-shots)
C.hammer = strike(0.55, 0.3, 0.5, { -- both fists from overhead into the ground
	RightShoulder = { { 170, 0, 12 }, { 40, 0, 10 }, { 30, 0, 10 } },
	LeftShoulder = { { 170, 0, -12 }, { 40, 0, -10 }, { 30, 0, -10 } },
	RightElbow = { { 30 }, { 10 }, { 20 } },
	LeftElbow = { { 30 }, { 10 }, { 20 } },
	Waist = { { 18 }, { -40 }, { -34 } },
	Neck = { { -10 }, { 24 }, { 20 } },
	RightHip = { { 0 }, { 40, 0, 10 }, { 36, 0, 10 } },
	LeftHip = { { 0 }, { 40, 0, -10 }, { 36, 0, -10 } },
	RightKnee = { { 0 }, { -60 }, { -54 } },
	LeftKnee = { { 0 }, { -60 }, { -54 } },
})
C.haymaker = strike(0.5, 0.3, 0.5, { -- a big round right
	RightShoulder = { { 60, 0, 80 }, { 90, 0, -20 }, { 80, 0, -40 } },
	RightElbow = { { 90 }, { 10 }, { 20 } },
	LeftShoulder = { { 50, 0, -20 }, { 10, 0, -30 }, { 10, 0, -30 } },
	LeftElbow = { { 80 }, { 90 }, { 90 } },
	Waist = { { 6, 40 }, { -10, -40 }, { -8, -46 } },
	Neck = { { 0, -20 }, { 0, 20 }, { 0, 22 } },
})
C.stab = strike(0.35, 0.35, 0.55, { -- a low thrust from the hip (the Sneak Bot's blade)
	RightShoulder = { { -30, 0, 20 }, { 80, 0, 0 }, { 76, 0, 0 } },
	RightElbow = { { 100 }, { 0 }, { 6 } },
	LeftShoulder = { { 40, 0, -20 }, { -30, 0, -20 }, { -26, 0, -20 } },
	LeftElbow = { { 60 }, { 40 }, { 40 } },
	Waist = { { 8, 30 }, { -22, -20 }, { -18, -16 } },
	Neck = { { 0, -16 }, { 12, 10 }, { 10, 8 } },
})
C.sweep = strike(0.5, 0.35, 0.55, { -- a flat arm sweep across the front (the Warden's bar)
	RightShoulder = { { 90, 0, 90 }, { 90, 0, -50 }, { 86, 0, -70 } },
	RightElbow = { { 20 }, { 4 }, { 6 } },
	LeftShoulder = { { 30, 0, -30 }, { 20, 0, -10 }, { 20, 0, -10 } },
	LeftElbow = { { 60 }, { 60 }, { 60 } },
	Waist = { { 4, 50 }, { -6, -50 }, { -4, -56 } },
	Neck = { { 0, -30 }, { 0, 30 }, { 0, 30 } },
})
C.shieldBash = strike(0.45, 0.3, 0.5, { -- the shield driven forward with the shoulder behind it
	LeftShoulder = { { 60, 0, 20 }, { 92, 0, 6 }, { 88, 0, 6 } },
	LeftElbow = { { 90 }, { 20 }, { 26 } },
	RightShoulder = { { 20, 0, 20 }, { -20, 0, 20 }, { -16, 0, 20 } },
	RightElbow = { { 80 }, { 60 }, { 60 } },
	Waist = { { 8, -30 }, { -20, 20 }, { -16, 16 } },
	Neck = { { 0, 20 }, { 6, -10 }, { 6, -8 } },
})
C.snatch = strike(0.45, 0.3, 0.5, { -- both hands shoot out and grab, then pull it in (the Burglar Bot)
	RightShoulder = { { 40, 0, 30 }, { 95, 0, -6 }, { 60, 0, 10 } },
	LeftShoulder = { { 40, 0, -30 }, { 95, 0, 6 }, { 60, 0, -10 } },
	RightElbow = { { 90 }, { 6 }, { 90 } },
	LeftElbow = { { 90 }, { 6 }, { 90 } },
	Waist = { { 10 }, { -20 }, { 6 } },
	Neck = { { -6 }, { 10 }, { 0 } },
})
C.claw = strike(0.35, 0.3, 0.5, { -- both claws rake down (the Swarmer)
	RightShoulder = { { 140, 0, 40 }, { 40, 0, 10 }, { 20, 0, 10 } },
	LeftShoulder = { { 140, 0, -40 }, { 40, 0, -10 }, { 20, 0, -10 } },
	RightElbow = { { 50 }, { 20 }, { 30 } },
	LeftElbow = { { 50 }, { 20 }, { 30 } },
	Waist = { { 6 }, { -30 }, { -26 } },
	Neck = { { -10 }, { 20 }, { 16 } },
})
C.zap = strike(0.3, 0.2, 0.35, { -- a shot: the gun arm kicks up with the recoil, the chest rocks back
	RightShoulder = { { 86, 0, -4 }, { 106, 0, -4 }, { 96, 0, -4 }, { 90, 0, -4 } },
	RightElbow = { { 4 }, { 14 }, { 8 } },
	Waist = { { 0, 10 }, { 10, 12 }, { 6, 10 } },
	Neck = { { 0, -8 }, { -4, -8 }, { -2, -8 } },
})
C.rifleKick = strike(0.4, 0.2, 0.3, { -- a long shot in both hands: the rifle jumps, the body takes it
	RightShoulder = { { 90, 0, -10 }, { 102, 0, -10 }, { 94, 0, -10 }, { 90, 0, -10 } },
	LeftShoulder = { { 85, 0, 30 }, { 96, 0, 30 }, { 88, 0, 30 }, { 85, 0, 30 } },
	RightElbow = { { 0 }, { 12 }, { 4 } },
	LeftElbow = { { 15 }, { 26 }, { 18 } },
	Waist = { { 0, 8 }, { 14, 8 }, { 8, 8 } },
	Neck = { { 0, -6 }, { -6, -6 }, { -2, -6 } },
})
C.braceShot = strike(0.35, 0.2, 0.3, { -- a turret's or a sentry's shot: both arms forward, the body jolts
	RightShoulder = { { 88, 0, -10 }, { 100, 0, -10 }, { 92, 0, -10 } },
	LeftShoulder = { { 88, 0, 10 }, { 100, 0, 10 }, { 92, 0, 10 } },
	RightElbow = { { 6 }, { 20 }, { 10 } },
	LeftElbow = { { 6 }, { 20 }, { 10 } },
	Waist = { { -4 }, { 12 }, { 6 } },
})
C.lobThrow = strike(0.55, 0.4, 0.58, { -- an overhand throw (the Bomber's charge)
	RightShoulder = { { 155, 0, 30 }, { 60, 0, 10 }, { 20, 0, 0 } },
	RightElbow = { { 110 }, { 10 }, { 20 } },
	LeftShoulder = { { 80, 0, -10 }, { -10, 0, -20 }, { -10, 0, -20 } },
	LeftElbow = { { 20 }, { 50 }, { 50 } },
	Waist = { { 14, 30 }, { -20, -24 }, { -16, -20 } },
	Neck = { { 0, -24 }, { 6, 20 }, { 4, 16 } },
	RightHip = { { -10 }, { 20 }, { 16 } },
	LeftHip = { { 20 }, { -20 }, { -16 } },
})
C.command = strike(0.9, 0.25, 0.4, { -- the Captain points its squad on: arm high and forward, chest out
	RightShoulder = { { 120, 0, 20 }, { 110, 0, 0 }, { 108, 0, 0 } },
	RightElbow = { { 60 }, { 0 }, { 0 } },
	LeftShoulder = { { 10, 0, -30 }, { 0, 0, -40 }, { 0, 0, -40 } },
	LeftElbow = { { 60 }, { 90 }, { 90 } },
	Waist = { { 10, 10 }, { 6, -10 }, { 6, -10 } },
	Neck = { { 10 }, { 6 }, { 6 } },
})
C.hookThrow = strike(0.5, 0.35, 0.5, { -- the Grappler fires its hook arm: swung up from the hip and out
	RightShoulder = { { -40, 0, 20 }, { 95, 0, 0 }, { 90, 0, 0 } },
	RightElbow = { { 40 }, { 0 }, { 0 } },
	LeftShoulder = { { 60, 0, -20 }, { 0, 0, -30 }, { 0, 0, -30 } },
	LeftElbow = { { 30 }, { 70 }, { 70 } },
	Waist = { { 8, 30 }, { -12, -20 }, { -10, -16 } },
	Neck = { { 0, -24 }, { 0, 14 }, { 0, 12 } },
})
C.yank = strike(0.5, 0.25, 0.55, { -- and hauls the line in with both hands, leaning back
	RightShoulder = { { 90, 0, -6 }, { 20, 0, 10 }, { 14, 0, 10 } },
	LeftShoulder = { { 90, 0, 20 }, { 26, 0, -6 }, { 20, 0, -6 } },
	RightElbow = { { 0 }, { 100 }, { 100 } },
	LeftElbow = { { 10 }, { 100 }, { 100 } },
	Waist = { { -10 }, { 24 }, { 20 } },
	Neck = { { 6 }, { -10 }, { -8 } },
})
C.mendHand = strike(0.6, 0.3, 0.5, { -- a medic's repair beam: the hand out, palm forward, steadied
	RightShoulder = { { 70, 0, 10 }, { 90, 0, 0 }, { 88, 0, 0 } },
	RightElbow = { { 40 }, { 6 }, { 6 } },
	LeftShoulder = { { 40, 0, -10 }, { 60, 0, 20 }, { 58, 0, 20 } },
	LeftElbow = { { 60 }, { 70 }, { 70 } },
	Neck = { { 0 }, { -4 }, { -4 } },
})

-- ------------------------------------------------------------------ robots: hit reacts and stagger
C.hit = strike(0.35, 0.18, 0.4, { -- a hit from the front: the chest snaps back, the arms fling
	Waist = { { 18, 8 }, { 8, 2 }, { 4, 0 } },
	Neck = { { -18 }, { -6 }, { -2 } },
	RightShoulder = { { 50, 0, 40 }, { 30, 0, 20 }, { 20, 0, 14 } },
	LeftShoulder = { { 50, 0, -40 }, { 30, 0, -20 }, { 20, 0, -14 } },
	RightElbow = { { 40 }, { 20 }, { 14 } },
	LeftElbow = { { 40 }, { 20 }, { 14 } },
})
C.hitHeavy = strike(0.6, 0.15, 0.45, { -- a heavy hit: thrown back from the waist, a knee buckles, arms wide
	Waist = { { 32, 12 }, { 20, 6 }, { 10, 0 } },
	Neck = { { -26, 0, 10 }, { -12 }, { -6 } },
	RightShoulder = { { 90, 0, 70 }, { 50, 0, 40 }, { 30, 0, 20 } },
	LeftShoulder = { { 90, 0, -70 }, { 50, 0, -40 }, { 30, 0, -20 } },
	RightElbow = { { 20 }, { 30 }, { 20 } },
	LeftElbow = { { 20 }, { 30 }, { 20 } },
	RightHip = { { -16 }, { -10 }, { -4 } },
	LeftHip = { { 24 }, { 14 }, { 6 } },
	LeftKnee = { { -40 }, { -24 }, { -10 } },
})
C.stagger = { -- stunned: arms dangling and swaying, head lolling, the chest circling
	dur = 1.2,
	loop = true,
	joints = {
		Waist = {
			K(0, -14, 10, 6),
			K(0.3, -10, 0, -6),
			K(0.6, -14, -10, 6),
			K(0.9, -10, 0, -6),
			K(1.2, -14, 10, 6),
		},
		Neck = { K(0, -20, -14, 10), K(0.6, -24, 14, -10), K(1.2, -20, -14, 10) },
		RightShoulder = { K(0, 10, 0, 10), K(0.6, -10, 0, 16), K(1.2, 10, 0, 10) },
		LeftShoulder = { K(0, -10, 0, -16), K(0.6, 10, 0, -10), K(1.2, -10, 0, -16) },
		RightElbow = hold(26),
		LeftElbow = hold(26),
		RightKnee = { K(0, -14), K(0.6, -24), K(1.2, -14) },
		LeftKnee = { K(0, -24), K(0.6, -14), K(1.2, -24) },
	},
}

-- Each AI kind's clips (Config.Enemies ai): what it holds on a wind-up and what each attack event plays.
-- Events: swing (CombatEvents SWING), shot (SHOT), hook (a Grappler's shot), slam (SLAM), lob (LOB), rally.
-- A missing event falls back to NpcAnim.DEFAULT; "hit", "hitHeavy" and "stagger" are everyone's.
NpcAnim.DEFAULT = {
	windup = "windupOverhead",
	swing = "haymaker",
	shot = "zap",
	hook = "hookThrow",
	slam = "hammer",
	lob = "lobThrow",
	rally = "command",
	pull = "yank",
	mend = "mendHand",
} :: { [string]: string }
NpcAnim.AI = {
	flyer = { windup = "windupAim", swing = "claw", shot = "zap", slam = "hammer" },
	thief = { windup = "windupSwing", swing = "snatch", shot = "zap" },
	sneak = { windup = "windupSwing", swing = "stab" },
	brute = { windup = "windupOverhead", swing = "haymaker", slam = "hammer", shot = "zap" },
	sentry = { windup = "windupAim", shot = "braceShot", swing = "sweep" },
	guard = { windup = "windupShield", swing = "shieldBash", slam = "hammer" },
	captain = { windup = "windupAim", rally = "command", shot = "zap", swing = "haymaker" },
	sniper = { windup = "windupAim", shot = "rifleKick", swing = "haymaker" },
	bomber = { windup = "windupThrow", lob = "lobThrow", shot = "zap", swing = "haymaker" },
	medic = { windup = "windupAim", shot = "zap", mend = "mendHand", swing = "haymaker" },
	swarm = { windup = "windupClaw", swing = "claw", slam = "claw" },
	mimic = { windup = "windupSwing", swing = "haymaker", shot = "zap" },
	grappler = {
		windup = "windupHook",
		shot = "hookThrow",
		hook = "hookThrow",
		pull = "yank",
		swing = "haymaker",
	},
} :: { [string]: { [string]: string } }
NpcAnim.EVENTS = { "windup", "swing", "shot", "hook", "slam", "lob", "rally", "pull", "mend" }

-- the clip a robot of AI kind `ai` plays for `event` (nil: none)
function NpcAnim.robotClip(ai: string?, event: string): string?
	if event == "hit" or event == "hitHeavy" or event == "stagger" then
		return event
	end
	local own = ai and NpcAnim.AI[ai]
	return (own and own[event]) or NpcAnim.DEFAULT[event]
end

-- ------------------------------------------------------------------ people: idle variety (upper body)
C.talk = { -- talking with the hands: one hand opens out, the other follows, the head nods
	dur = 2.4,
	loop = true,
	joints = {
		RightShoulder = {
			K(0, 20, 0, 10),
			K(0.6, 46, 0, 20),
			K(1.2, 30, 0, 14),
			K(1.8, 50, 0, 24),
			K(2.4, 20, 0, 10),
		},
		RightElbow = { K(0, 60), K(0.6, 80), K(1.2, 70), K(1.8, 86), K(2.4, 60) },
		LeftShoulder = { K(0, 10, 0, -8), K(0.9, 30, 0, -18), K(1.6, 14, 0, -10), K(2.4, 10, 0, -8) },
		LeftElbow = { K(0, 40), K(0.9, 70), K(1.6, 50), K(2.4, 40) },
		RightWrist = { K(0, 0, 0, 0), K(0.6, 0, -30, 0), K(1.8, 0, -40, 0), K(2.4, 0, 0, 0) },
		Neck = { K(0, 0), K(0.4, -8), K(0.8, 2), K(1.4, -6), K(2.0, 2, 6), K(2.4, 0) },
		Waist = { K(0, 0, 0), K(1.2, 0, 6), K(2.4, 0, 0) },
	},
}
C.wave = { -- a big friendly wave, the hand rocking side to side
	dur = 1.8,
	joints = {
		RightShoulder = {
			K(0, 0, 0, 0),
			K(0.3, 20, 0, 150),
			K(0.6, 20, 0, 160),
			K(0.9, 20, 0, 140),
			K(1.2, 20, 0, 160),
			K(1.5, 20, 0, 145),
			K(1.8, 0, 0, 0),
		},
		RightElbow = {
			K(0, 0),
			K(0.3, 40),
			K(0.6, 20),
			K(0.9, 50),
			K(1.2, 20),
			K(1.5, 40),
			K(1.8, 0),
		},
		Neck = { K(0, 0), K(0.3, 4, 0, -6), K(1.5, 4, 0, -6), K(1.8, 0) },
		Waist = { K(0, 0), K(0.3, 0, 0, -4), K(1.5, 0, 0, -4), K(1.8, 0) },
	},
}
C.point = { -- pointing off to one side ("that way"), the head turning with it
	dur = 2.0,
	joints = {
		RightShoulder = { K(0, 0), K(0.35, 92, 0, 40), K(1.6, 92, 0, 40), K(2.0, 0) },
		RightElbow = { K(0, 0), K(0.35, 0), K(1.6, 0), K(2.0, 0) },
		LeftShoulder = { K(0, 0), K(0.35, 0, 0, -6), K(1.6, 0, 0, -6), K(2.0, 0) },
		Neck = { K(0, 0), K(0.35, 0, -30), K(1.6, 0, -30), K(2.0, 0) },
		Waist = { K(0, 0), K(0.35, 0, -14), K(1.6, 0, -14), K(2.0, 0) },
	},
}
C.beckon = { -- "come here": the arm forward, the hand curling in twice
	dur = 1.8,
	joints = {
		RightShoulder = { K(0, 0), K(0.3, 70, 0, 10), K(1.5, 70, 0, 10), K(1.8, 0) },
		RightElbow = { K(0, 0), K(0.3, 20), K(0.6, 90), K(0.9, 20), K(1.2, 90), K(1.5, 30), K(1.8, 0) },
		Neck = { K(0, 0), K(0.3, -6), K(1.5, -6), K(1.8, 0) },
	},
}
C.shrug = { -- a shrug: shoulders up, palms open out
	dur = 1.2,
	joints = {
		RightShoulder = { K(0, 0), K(0.3, 20, 0, 34), K(0.8, 20, 0, 34), K(1.2, 0) },
		LeftShoulder = { K(0, 0), K(0.3, 20, 0, -34), K(0.8, 20, 0, -34), K(1.2, 0) },
		RightElbow = { K(0, 0), K(0.3, 90), K(0.8, 90), K(1.2, 0) },
		LeftElbow = { K(0, 0), K(0.3, 90), K(0.8, 90), K(1.2, 0) },
		RightWrist = { K(0, 0), K(0.3, 0, 0, 30), K(0.8, 0, 0, 30), K(1.2, 0) },
		LeftWrist = { K(0, 0), K(0.3, 0, 0, -30), K(0.8, 0, 0, -30), K(1.2, 0) },
		Neck = { K(0, 0), K(0.3, 0, 0, 10), K(0.8, 0, 0, 10), K(1.2, 0) },
	},
}
C.armsCrossed = { -- arms folded, waiting, the weight shifting
	dur = 3.0,
	loop = true,
	joints = {
		RightShoulder = hold(40, 0, -30),
		LeftShoulder = hold(36, 0, 30),
		RightElbow = hold(110),
		LeftElbow = hold(116),
		Waist = { K(0, 0, 0, 2), K(1.5, 0, 0, -2), K(3.0, 0, 0, 2) },
		Neck = { K(0, 0, 0), K(1.0, 0, 10), K(2.0, 0, -6), K(3.0, 0, 0) },
	},
}
C.lookAround = { -- glancing left, then right, a hand shading the eyes
	dur = 3.0,
	joints = {
		Neck = { K(0, 0), K(0.6, 4, 40), K(1.3, 4, 40), K(1.9, 4, -40), K(2.6, 4, -40), K(3.0, 0) },
		Waist = { K(0, 0), K(0.6, 0, 12), K(1.3, 0, 12), K(1.9, 0, -12), K(2.6, 0, -12), K(3.0, 0) },
		RightShoulder = { K(0, 0), K(0.5, 118, 0, -28), K(2.5, 118, 0, -28), K(3.0, 0) },
		RightElbow = { K(0, 0), K(0.5, 118), K(2.5, 118), K(3.0, 0) },
	},
}
C.checkTime = { -- a look at the wrist
	dur = 1.6,
	joints = {
		LeftShoulder = { K(0, 0), K(0.35, 60, 0, 20), K(1.2, 60, 0, 20), K(1.6, 0) },
		LeftElbow = { K(0, 0), K(0.35, 100), K(1.2, 100), K(1.6, 0) },
		Neck = { K(0, 0), K(0.35, -24, 10), K(1.2, -24, 10), K(1.6, 0) },
	},
}

-- ------------------------------------------------------------------ the Ceremony's crowd and stage (first-30)
-- (first-30, 2026-11-20: the prologue crowd's cheer and the stage's wave were two shoulder sines; these are whole
-- body loops: a hop on the Root, bent knees on the dip, elbows pumping. PLACEHOLDER ANIMATION like the rest.)
local function lift(t: number, py: number): Key
	return { t, 0, 0, 0, py }
end
C.cheer = { -- both fists up, pumping, a little hop on every pump
	dur = 0.8,
	loop = true,
	joints = {
		RightShoulder = { K(0, 150, 0, 18), K(0.4, 172, 0, 10), K(0.8, 150, 0, 18) },
		LeftShoulder = { K(0, 172, 0, -10), K(0.4, 150, 0, -18), K(0.8, 172, 0, -10) },
		RightElbow = { K(0, 40), K(0.4, 8), K(0.8, 40) },
		LeftElbow = { K(0, 8), K(0.4, 40), K(0.8, 8) },
		Neck = hold(14),
		Waist = { K(0, 4, 0, 3), K(0.4, 4, 0, -3), K(0.8, 4, 0, 3) },
		RightKnee = { K(0, -6), K(0.2, -22), K(0.4, -6), K(0.6, -22), K(0.8, -6) },
		LeftKnee = { K(0, -6), K(0.2, -22), K(0.4, -6), K(0.6, -22), K(0.8, -6) },
		RightHip = { K(0, 0), K(0.2, 12), K(0.4, 0), K(0.6, 12), K(0.8, 0) },
		LeftHip = { K(0, 0), K(0.2, 12), K(0.4, 0), K(0.6, 12), K(0.8, 0) },
		Root = { lift(0, 0.3), lift(0.2, -0.15), lift(0.4, 0.3), lift(0.6, -0.15), lift(0.8, 0.3) },
	},
}
C.cheerPump = { -- one fist punching the air, the other hand on the hip
	dur = 0.6,
	loop = true,
	joints = {
		RightShoulder = { K(0, 130, 0, 12), K(0.25, 176, 0, 6), K(0.6, 130, 0, 12) },
		RightElbow = { K(0, 80), K(0.25, 6), K(0.6, 80) },
		LeftShoulder = hold(-10, 0, -38),
		LeftElbow = hold(96),
		Neck = { K(0, 10), K(0.25, 18), K(0.6, 10) },
		Waist = { K(0, 0, 6), K(0.25, 4, 10), K(0.6, 0, 6) },
		RightKnee = { K(0, -14), K(0.3, -4), K(0.6, -14) },
		LeftKnee = { K(0, -14), K(0.3, -4), K(0.6, -14) },
		Root = { lift(0, -0.1), lift(0.25, 0.2), lift(0.6, -0.1) },
	},
}
C.clap = { -- clapping up high, rocking on the feet
	dur = 0.5,
	loop = true,
	joints = {
		RightShoulder = { K(0, 105, 0, 24), K(0.25, 112, 0, -4), K(0.5, 105, 0, 24) },
		LeftShoulder = { K(0, 105, 0, -24), K(0.25, 112, 0, 4), K(0.5, 105, 0, -24) },
		RightElbow = hold(55),
		LeftElbow = hold(55),
		Neck = hold(8),
		Waist = { K(0, 2, -4), K(0.25, 2, 4), K(0.5, 2, -4) },
		Root = { lift(0, 0), lift(0.25, 0.12), lift(0.5, 0) },
	},
}
C.stageWave = { -- the fakes on the stage: a big overhead wave, the weight rolling side to side
	dur = 1.2,
	loop = true,
	joints = {
		RightShoulder = {
			K(0, 20, 0, 135),
			K(0.3, 20, 0, 165),
			K(0.6, 20, 0, 135),
			K(0.9, 20, 0, 165),
			K(1.2, 20, 0, 135),
		},
		RightElbow = { K(0, 40), K(0.3, 15), K(0.6, 40), K(0.9, 15), K(1.2, 40) },
		LeftShoulder = hold(8, 0, -14),
		LeftElbow = hold(20),
		Neck = { K(0, 6, -8), K(0.6, 6, 8), K(1.2, 6, -8) },
		Waist = { K(0, 0, 0, -5), K(0.6, 0, 0, 5), K(1.2, 0, 0, -5) },
	},
}
C.present = { -- Silas Crane presenting his heroes: an open hand swept toward the fakes and back
	dur = 3.0,
	loop = true,
	joints = {
		RightShoulder = { K(0, 55, 0, 30), K(1.2, 80, 0, 60), K(2.0, 80, 0, 60), K(3.0, 55, 0, 30) },
		RightElbow = { K(0, 30), K(1.2, 8), K(2.0, 8), K(3.0, 30) },
		LeftShoulder = { K(0, 30, 0, -10), K(1.5, 40, 0, -14), K(3.0, 30, 0, -10) },
		LeftElbow = hold(70),
		Neck = { K(0, 4, -10), K(1.2, 6, 18), K(2.0, 6, 18), K(3.0, 4, -10) },
		Waist = { K(0, 0, -4), K(1.2, 0, 8), K(2.0, 0, 8), K(3.0, 0, -4) },
	},
}
C.gasp = { -- the scan stops on the hero: hands up to the chest, leaning back, a nervous tremble
	dur = 0.4,
	loop = true,
	joints = {
		RightShoulder = { K(0, 72, 0, -18), K(0.2, 76, 0, -20), K(0.4, 72, 0, -18) },
		LeftShoulder = { K(0, 72, 0, 18), K(0.2, 76, 0, 20), K(0.4, 72, 0, 18) },
		RightElbow = hold(118),
		LeftElbow = hold(118),
		Waist = hold(9),
		Neck = hold(-6),
	},
}
-- who plays what in the Ceremony (PrologueFx): the crowd picks a cheer by weight (seeded per person), the fakes
-- wave, Crane presents; on the scan everyone gasps toward the hero; the run is HeroAnim runFast
NpcAnim.crowd = {
	cheer = { { "cheer", 3 }, { "cheerPump", 2 }, { "clap", 2 } },
	stage = "stageWave",
	crane = "present",
	scan = "gasp",
	blend = 0.25, -- seconds a crowd member crossfades from one clip to the next
}

-- what each kind of person does when idle (picked by weight) and when a hero comes close
local PEOPLE: any = {
	giver = {
		idle = { { "armsCrossed", 3 }, { "lookAround", 2 }, { "checkTime", 1 }, { "shrug", 1 } },
		near = "wave", -- a hero comes within nearRange: a wave once
		talk = "talk", -- and keeps talking while one stands within talkRange
		far = "beckon", -- a hero in sight but not yet near: a beckon now and then
	},
	helper = {
		idle = { { "lookAround", 3 }, { "point", 2 }, { "shrug", 1 }, { "armsCrossed", 1 } },
		near = "wave",
		talk = "talk",
		far = "point",
	},
	citizen = {
		idle = { { "lookAround", 3 }, { "checkTime", 2 }, { "talk", 2 }, { "shrug", 1 }, { "point", 1 } },
	},
}
NpcAnim.PEOPLE = PEOPLE :: { [string]: any }
NpcAnim.people = {
	nearRange = 18, -- a hero this close gets the wave
	talkRange = 10, -- and this close the talk
	farRange = 45, -- a hero this close (but not near) gets a beckon now and then
	every = { 4, 9 }, -- seconds between idle gestures
	fade = 0.3, -- seconds a gesture fades in and out
}

-- a seeded pick from a weighted list ({ { name, weight } }), r in [0, 1)
function NpcAnim.pick(list: { { any } }, r: number): string
	local total = 0
	for _, e in list do
		total += e[2]
	end
	local at = r * total
	for _, e in list do
		at -= e[2]
		if at < 0 then
			return e[1]
		end
	end
	return list[#list][1]
end

-- the gesture a person of `kind` wants now. d: the nearest hero's distance; greeted: they already waved at
-- that hero; r: a seeded number for the idle pick. Returns the clip and whether it is held (a loop while the
-- hero stays)
function NpcAnim.gesture(kind: string, d: number, greeted: boolean, r: number): (string, boolean)
	local P = NpcAnim.PEOPLE[kind] or NpcAnim.PEOPLE.citizen
	local G = NpcAnim.people
	if P.talk and d <= G.talkRange and greeted then
		return P.talk, true
	end
	if P.near and d <= G.nearRange and not greeted then
		return P.near, false
	end
	if P.far and d <= G.farRange and d > G.nearRange and r < 0.5 then
		return P.far, false
	end
	return NpcAnim.pick(P.idle, r), false
end

-- how much of a one-shot shows at time t (fades in and out over `fade`)
function NpcAnim.weight(t: number, dur: number, fade: number, loop: boolean?): number
	if t < 0 then
		return 0
	end
	local fin = math.min(1, t / fade)
	if loop then
		return fin
	end
	if t >= dur then
		return 0
	end
	return math.clamp(math.min(fin, (dur - t) / fade), 0, 1)
end

-- a clip's joint angles at t: { joint = { rx, ry, rz, py } } (written into `out`, reused per robot)
function NpcAnim.sample(name: string, t: number, out: { [string]: { number } }?): { [string]: { number } }
	local clip = C[name]
	local o = out or {}
	if out then
		table.clear(out)
	end
	if not clip then
		return o
	end
	for joint, keys in clip.joints do
		o[joint] = HeroAnim.sampleKeys(keys, t, clip.dur, clip.loop)
	end
	return o
end

return NpcAnim
