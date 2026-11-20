--!strict
-- BossPose: the world bosses' animation as data (the boss pass, 2026-11-19), like Shared.HeroAnim for heroes.
-- Each boss's body is split into rig segments (art/blender/bosses.py, Config.BossArt rig: the titans' arms,
-- forearms, thighs, shins, head and jaw; the Maw's head, jaw, four legs and tail; the Leviathan's neck, head, jaw,
-- flank gears, turbine and tide wheel). A pose turns each segment about its pivot and can move it; "Root" moves
-- the whole boss from its feet. Fx.BossAnim samples these on the client from the fight's events (BossSim is the
-- truth; nothing here changes a hit, a shape or a time).
-- * idle (a loop: breathing and sway; faster and bigger in phase 3), walk (Rustjaw only: the one boss that moves)
-- * one clip per attack (Config.Boss attacks): a wind-up whose time runs 0 to 1 over the attack's own warning, so
--   its last key (the strike) lands exactly at the hit, with its anticipation peak before it; then a recover clip
--   in seconds from the strike pose back to rest
-- * flinch (a big hit), weak (the weak points exposed: Rustjaw kneels, the Maw arches its back sacs up, the
--   Leviathan drops its head to the water, the War-Frame bows its back core), stagger (plates break at 66% and
--   33%), enrage (the phase change roar), defeat (the collapse; it holds its last pose), land (the entrance)
-- * spin: the Leviathan's machinery turns all the time (gears, turbine, tide wheel), faster while it winds up
-- Angles in degrees about the segment's pivot in the boss's frame (x right, y up, a boss faces -z), then a move in
-- studs: { rx, ry, rz, px, py, pz }. +rx pitches up (a hanging limb swings forward), +ry turns left, left limbs go
-- out with -rz and right limbs with +rz. Every number stays inside LIMITS (tests).
-- PLACEHOLDER ANIMATION: hand-keyed poses until real animations are made (Tasks.md "Placeholder art").
-- Pure: no Roblox types, so Lune tests it.

local BossPose = {}

export type Vec = { number } -- { rx, ry, rz, px, py, pz }
export type Pose = { [string]: Vec }
export type Key = { t: number, pose: Pose, e: string?, peak: boolean?, hit: boolean? }
export type Clip = { dur: number, loop: boolean?, keys: { Key } }
export type Attack = { windup: Clip, recover: Clip }
export type Set = {
	segments: { string },
	clips: { [string]: Clip },
	attacks: { [string]: Attack },
	spin: { [string]: { axis: string, rate: number } }?,
}

BossPose.NONE = {} :: Pose
BossPose.REQUIRED = { "idle", "flinch", "weak", "stagger", "enrage", "defeat", "land", "shot" }
BossPose.flinchShare = 0.04 -- one Boss.State drop of this share of max HP (or more) flinches it
BossPose.flinchGap = 1.4 -- seconds between flinches
BossPose.weakAfter = 0.35 -- a hazard's recover ends in the weak pose this long after the strike
BossPose.walkSpeed = 1 -- studs a second it must move to walk
BossPose.idleRate = { 1, 1.15, 1.35 } -- the idle's speed in each phase
BossPose.idleScale = { 1, 1.15, 1.35 } -- and its size

local function V(rx: number?, ry: number?, rz: number?, px: number?, py: number?, pz: number?): Vec
	return { rx or 0, ry or 0, rz or 0, px or 0, py or 0, pz or 0 }
end

local function K(t: number, pose: Pose, e: string?): Key
	return { t = t, pose = pose, e = e }
end

local function clip(dur: number, keys: { Key }, loop: boolean?): Clip
	return { dur = dur, keys = keys, loop = loop }
end

-- An attack: wind-up keys over 0..1 of the warning (rest first, the anticipation peak, the strike last), then the
-- recover in seconds back to rest
local function attack(peakAt: number, peak: Pose, strike: Pose, recover: number, mid: { Key }?): Attack
	local keys = { K(0, BossPose.NONE) }
	for _, k in mid or {} do
		table.insert(keys, k)
	end
	table.insert(keys, { t = peakAt, pose = peak, peak = true })
	table.insert(keys, { t = 1, pose = strike, e = "in", hit = true })
	return {
		windup = clip(1, keys),
		recover = clip(recover, {
			K(0, strike),
			K(recover * 0.3, strike, "out"),
			K(recover, BossPose.NONE),
		}),
	}
end

-- Mirror a pose left to right (L and R segments swap; y and z turns and x moves flip)
function BossPose.mirror(p: Pose): Pose
	local out: Pose = {}
	for seg, v in p do
		local other = seg
		local last = string.sub(seg, -1)
		if last == "L" then
			other = string.sub(seg, 1, -2) .. "R"
		elseif last == "R" then
			other = string.sub(seg, 1, -2) .. "L"
		end
		out[other] = { v[1], -v[2], -v[3], -v[4], v[5], v[6] }
	end
	return out
end

local function both(p: Pose): Pose
	local out = table.clone(p)
	for seg, v in BossPose.mirror(p) do
		out[seg] = out[seg] or v
	end
	return out
end

---------------------------------------------------------------------------
-- Rustjaw Prime, the Junkyard Titan: heavy stomps, wrecking-fist swings, the crane arm flinging scrap, the
-- headlight laser. Big, slow, every move sold through the knees and the chest.
---------------------------------------------------------------------------

local rust: Set = {
	segments = {
		"Root",
		"Body",
		"ThighL",
		"ShinL",
		"ThighR",
		"ShinR",
		"Head",
		"Jaw",
		"ArmL",
		"ForeL",
		"ArmR",
		"ForeR",
	},
	clips = {
		idle = clip(4, {
			K(0, BossPose.NONE),
			K(1, {
				Body = V(-1.5, 2),
				Root = V(0, 0, 0, 0, -0.6),
				ArmL = V(-2, 0, -2),
				ArmR = V(-2, 0, 2),
				Head = V(-2, 6),
				Jaw = V(3),
			}),
			K(2, { Body = V(0, 0), Head = V(0, 0), Jaw = V(1) }),
			K(3, {
				Body = V(-1.5, -2),
				Root = V(0, 0, 0, 0, -0.6),
				ArmL = V(-2, 0, -2),
				ArmR = V(-2, 0, 2),
				Head = V(-2, -6),
				Jaw = V(3),
			}),
			K(4, BossPose.NONE),
		}, true),
		walk = clip(2.4, {
			K(0, {
				ThighL = V(14),
				ShinL = V(-4),
				ThighR = V(-12),
				ShinR = V(-16),
				Body = V(0, 3, 2),
				ArmL = V(-8),
				ArmR = V(8),
			}),
			K(
				0.6,
				{ ThighL = V(2), ShinL = V(-2), ThighR = V(0), ShinR = V(-24), Root = V(0, 0, 0, 0, 1.2) }
			),
			K(1.2, {
				ThighL = V(-12),
				ShinL = V(-16),
				ThighR = V(14),
				ShinR = V(-4),
				Body = V(0, -3, -2),
				ArmL = V(8),
				ArmR = V(-8),
			}),
			K(
				1.8,
				{ ThighL = V(0), ShinL = V(-24), ThighR = V(2), ShinR = V(-2), Root = V(0, 0, 0, 0, 1.2) }
			),
			K(2.4, {
				ThighL = V(14),
				ShinL = V(-4),
				ThighR = V(-12),
				ShinR = V(-16),
				Body = V(0, 3, 2),
				ArmL = V(-8),
				ArmR = V(8),
			}),
		}, true),
		flinch = clip(0.6, {
			K(0, BossPose.NONE),
			K(0.12, {
				Body = V(8, 0, 3),
				Head = V(12, -6),
				Jaw = V(14),
				ArmL = V(10, 0, -14),
				ArmR = V(6, 0, 18),
				Root = V(0, 0, 0, 0, 0, 1.5),
			}, "out"),
			K(0.6, BossPose.NONE),
		}),
		weak = clip(2.4, {
			K(0, BossPose.NONE),
			K(
				0.4,
				both({
					ThighL = V(22),
					ShinL = V(-34),
					ArmL = V(-6, 0, -6),
					Body = V(-12),
					Head = V(-16),
					Root = V(0, 0, 0, 0, -6),
				}),
				"out"
			),
			K(
				1.9,
				both({
					ThighL = V(20),
					ShinL = V(-30),
					ArmL = V(-4, 0, -8),
					Body = V(-10),
					Head = V(-12),
					Jaw = V(10),
					Root = V(0, 0, 0, 0, -5),
				})
			),
			K(2.4, BossPose.NONE),
		}),
		stagger = clip(1.6, {
			K(0, BossPose.NONE),
			K(0.22, {
				Body = V(10, 0, 10),
				Root = V(0, 0, 0, 3, -2),
				ThighL = V(20),
				ShinL = V(-26),
				Head = V(-8, 10),
				ArmL = V(12, 0, -24),
				ArmR = V(-6, 0, 10),
			}, "out"),
			K(0.75, {
				Body = V(2, 0, -6),
				Root = V(0, 0, 0, 1, -1),
				ThighL = V(8),
				ShinL = V(-10),
				Head = V(4, -6),
			}),
			K(1.6, BossPose.NONE),
		}),
		enrage = clip(2.2, {
			K(0, BossPose.NONE),
			K(
				0.4,
				both({
					Body = V(10),
					ArmL = V(30, 0, -50),
					ForeL = V(40),
					Head = V(18),
					Jaw = V(30),
					Root = V(0, 0, 0, 0, 1),
				}),
				"out"
			),
			K(
				1.6,
				both({
					Body = V(12),
					ArmL = V(34, 0, -55),
					ForeL = V(48),
					Head = V(20),
					Jaw = V(34),
					Root = V(0, 0, 0, 0, 1),
				})
			),
			K(2.2, BossPose.NONE),
		}),
		defeat = clip(3, {
			K(0, BossPose.NONE),
			K(
				0.4,
				{ Body = V(10, 0, 4), Head = V(14), Jaw = V(20), ArmL = V(10, 0, -20), ArmR = V(10, 0, 20) },
				"out"
			),
			K(1.3, {
				ThighL = V(40),
				ShinL = V(-60),
				ThighR = V(34),
				ShinR = V(-52),
				Body = V(-24, 0, 6),
				Head = V(-26),
				Jaw = V(24),
				ArmL = V(-10, 0, -6),
				ArmR = V(-12, 0, 8),
				Root = V(0, 0, 0, 0, -14),
			}, "in"),
			K(3, {
				ThighL = V(44),
				ShinL = V(-70),
				ThighR = V(40),
				ShinR = V(-66),
				Body = V(-40, 0, 10),
				Head = V(-30, 10),
				Jaw = V(28),
				ArmL = V(-18, 0, -4),
				ArmR = V(-20, 0, 6),
				Root = V(-10, 0, 0, 0, -22),
			}, "in"),
		}),
		land = clip(2.2, {
			K(
				0,
				both({
					ThighL = V(30),
					ShinL = V(-46),
					Body = V(-18),
					ArmL = V(-10, 0, -30),
					Head = V(-20),
					Root = V(0, 0, 0, 0, -8),
				})
			),
			K(
				0.9,
				both({
					ThighL = V(26),
					ShinL = V(-40),
					Body = V(-14),
					ArmL = V(-8, 0, -28),
					Head = V(-10),
					Root = V(0, 0, 0, 0, -7),
				})
			),
			K(
				1.6,
				both({
					Body = V(6),
					ArmL = V(16, 0, -36),
					ForeL = V(30),
					Head = V(14),
					Jaw = V(24),
					Root = V(0, 0, 0, 0, 0.5),
				}),
				"out"
			),
			K(2.2, BossPose.NONE),
		}),
		shot = clip(0.45, {
			K(0, BossPose.NONE),
			K(0.08, { Body = V(3, 0, 0, 0, 0, 0.8) }, "out"),
			K(0.45, BossPose.NONE),
		}),
	},
	attacks = {
		-- the titan stomp: the right leg high, arms up for balance, then the slam down into a crouch
		Stomp = attack(
			0.82,
			{
				ThighR = V(44),
				ShinR = V(-30),
				Body = V(6, 0, -6),
				ArmL = V(16, 0, -28),
				ArmR = V(10, 0, 34),
				Head = V(10),
				Jaw = V(18),
				Root = V(0, 0, 0, 0, 2),
			},
			{
				ThighR = V(-4),
				ShinR = V(0),
				ThighL = V(10),
				ShinL = V(-14),
				Body = V(-8, 0, 2),
				ArmL = V(-6, 0, -18),
				ArmR = V(-6, 0, 18),
				Head = V(-8),
				Jaw = V(4),
				Root = V(0, 0, 0, 0, -3),
			},
			1,
			{
				K(0.45, {
					ThighR = V(30),
					ShinR = V(-22),
					Body = V(4, 0, -5),
					ArmL = V(8, 0, -18),
					ArmR = V(6, 0, 22),
					Root = V(0, 0, 0, 0, 1.4),
				}, "out"),
			}
		),
		-- the wrecking-fist swing: the body winds back to the left, the left arm cocked, then sweeps across the front
		Swipe = attack(0.78, {
			Body = V(2, 26, 0),
			ArmL = V(-30, 0, -40),
			ForeL = V(30),
			ArmR = V(10, 0, 14),
			Head = V(0, 10),
			Jaw = V(10),
			Root = V(0, 0, 0, 0, -1),
		}, {
			Body = V(-4, -28, 0),
			ArmL = V(72, -10, 14),
			ForeL = V(14),
			ArmR = V(-10, 0, 20),
			Head = V(-4, -14),
			Jaw = V(16),
			ThighL = V(8),
			Root = V(0, 0, 0, 0, -1.5),
		}, 0.9),
		-- the crane arm flings scrap: both arms reach high, the chest leans back, then hurls everything forward
		ScrapRain = attack(0.8, {
			ArmL = V(120, 0, -16),
			ForeL = V(20),
			ArmR = V(130, 0, 14),
			ForeR = V(30),
			Body = V(10),
			Head = V(16),
			Jaw = V(22),
			Root = V(0, 0, 0, 0, 1.5),
		}, {
			ArmL = V(56, 0, -10),
			ForeL = V(6),
			ArmR = V(66, 0, 8),
			ForeR = V(4),
			Body = V(-12),
			Head = V(-6),
			Jaw = V(28),
			Root = V(0, 0, 0, 0, -1),
		}, 1.1),
		-- the headlight laser: the head drops and the jaw opens as it charges, then the head snaps up on the beam
		EyeLaser = attack(0.85, {
			Head = V(-12),
			Jaw = V(26),
			Body = V(-6),
			ArmL = V(6, 0, -22),
			ArmR = V(6, 0, 22),
			ThighL = V(8),
			ThighR = V(8),
			ShinL = V(-12),
			ShinR = V(-12),
			Root = V(0, 0, 0, 0, -1.5),
		}, {
			Head = V(6),
			Jaw = V(32),
			Body = V(4),
			ArmL = V(-4, 0, -26),
			ArmR = V(-4, 0, 26),
			Root = V(0, 0, 0, 0, 0, 1),
		}, 1),
	},
}

---------------------------------------------------------------------------
-- Lumen Maw, the Light Eater: a big cat of the night. Coils, lunges, rears and slams, gapes wide to pull the light
-- in; the light-stream lunges throw the whole body forward.
---------------------------------------------------------------------------

local maw: Set = {
	segments = { "Root", "Body", "Head", "Jaw", "Tail", "LegFL", "LegFR", "LegBL", "LegBR" },
	clips = {
		idle = clip(3.2, {
			K(0, { Tail = V(0, 10, 4) }),
			K(
				0.8,
				{ Body = V(1.5), Root = V(0, 0, 0, 0, 0.8), Head = V(-2, 6), Jaw = V(8), Tail = V(4, 0, 0) }
			),
			K(1.6, { Body = V(0), Head = V(0, 0), Jaw = V(3), Tail = V(0, -10, -4) }),
			K(
				2.4,
				{ Body = V(1.5), Root = V(0, 0, 0, 0, 0.8), Head = V(-2, -6), Jaw = V(8), Tail = V(4, 0, 0) }
			),
			K(3.2, { Tail = V(0, 10, 4) }),
		}, true),
		flinch = clip(0.55, {
			K(0, BossPose.NONE),
			K(0.12, {
				Body = V(6, 0, -4),
				Head = V(18, 8),
				Jaw = V(26),
				Tail = V(16, 14),
				Root = V(0, 0, 0, 0, 0, 2),
			}, "out"),
			K(0.55, BossPose.NONE),
		}),
		weak = clip(2.4, {
			K(0, BossPose.NONE),
			K(0.4, {
				Body = V(-10),
				Head = V(-22),
				Jaw = V(6),
				LegFL = V(-10),
				LegFR = V(-10),
				Tail = V(-10),
				Root = V(0, 0, 0, 0, -5),
			}, "out"),
			K(1.9, {
				Body = V(-8),
				Head = V(-20),
				Jaw = V(10),
				LegFL = V(-8),
				LegFR = V(-8),
				Tail = V(-8),
				Root = V(0, 0, 0, 0, -4),
			}),
			K(2.4, BossPose.NONE),
		}),
		stagger = clip(1.6, {
			K(0, BossPose.NONE),
			K(0.2, {
				Body = V(4, 0, 14),
				Root = V(0, 0, 0, 4, -3),
				Head = V(10, 16),
				Jaw = V(30),
				LegFL = V(0, 0, -16),
				LegBL = V(0, 0, -12),
				Tail = V(10, -20),
			}, "out"),
			K(0.8, { Body = V(0, 0, -6), Root = V(0, 0, 0, 1, -1), Head = V(-4, -8), Jaw = V(10) }),
			K(1.6, BossPose.NONE),
		}),
		enrage = clip(2.2, {
			K(0, BossPose.NONE),
			K(0.45, {
				Body = V(14),
				Head = V(26),
				Jaw = V(55),
				Tail = V(30, 0),
				LegFL = V(14),
				LegFR = V(14),
				Root = V(0, 0, 0, 0, 3),
			}, "out"),
			K(1.6, {
				Body = V(16),
				Head = V(28, 6),
				Jaw = V(58),
				Tail = V(34, 8),
				LegFL = V(16),
				LegFR = V(16),
				Root = V(0, 0, 0, 0, 3.5),
			}),
			K(2.2, BossPose.NONE),
		}),
		defeat = clip(3, {
			K(0, BossPose.NONE),
			K(0.5, { Body = V(14), Head = V(24), Jaw = V(50), Tail = V(20), Root = V(0, 0, 0, 0, 2) }, "out"),
			K(1.4, {
				Body = V(-4, 0, 18),
				Head = V(-20, 14),
				Jaw = V(30),
				LegFL = V(0, 0, -36),
				LegBL = V(0, 0, -30),
				LegFR = V(0, 0, 20),
				LegBR = V(0, 0, 18),
				Tail = V(-6, 30),
				Root = V(0, 0, 0, 0, -12),
			}, "in"),
			K(3, {
				Body = V(-6, 0, 24),
				Head = V(-26, 18),
				Jaw = V(34),
				LegFL = V(0, 0, -40),
				LegBL = V(0, 0, -36),
				LegFR = V(0, 0, 28),
				LegBR = V(0, 0, 24),
				Tail = V(-10, 34),
				Root = V(0, 0, 0, 0, -18),
			}, "in"),
		}),
		-- it climbs out of its pit and roars
		land = clip(2.4, {
			K(0, { Body = V(18), Head = V(10), LegFL = V(40), LegFR = V(40), Root = V(0, 0, 0, 0, -6) }),
			K(1, {
				Body = V(10),
				Head = V(20),
				Jaw = V(48),
				LegFL = V(20),
				LegFR = V(20),
				Tail = V(26),
				Root = V(0, 0, 0, 0, -2),
			}, "out"),
			K(1.8, { Body = V(8), Head = V(22), Jaw = V(52), Tail = V(28), Root = V(0, 0, 0, 0, 1) }),
			K(2.4, BossPose.NONE),
		}),
		shot = clip(
			0.45,
			{ K(0, BossPose.NONE), K(0.1, { Head = V(6), Jaw = V(12) }, "out"), K(0.45, BossPose.NONE) }
		),
	},
	attacks = {
		-- the bite: coils back low with the jaw open, then lunges and snaps shut
		Bite = attack(0.8, {
			Body = V(6),
			Head = V(14),
			Jaw = V(36),
			LegFL = V(-16),
			LegFR = V(-16),
			LegBL = V(10),
			LegBR = V(10),
			Tail = V(20),
			Root = V(0, 0, 0, 0, -3, 5),
		}, {
			Body = V(-6),
			Head = V(-10),
			Jaw = V(0),
			LegFL = V(30),
			LegFR = V(30),
			LegBL = V(-22),
			LegBR = V(-22),
			Tail = V(-6),
			Root = V(0, 0, 0, 0, 1, -10),
		}, 0.9),
		-- the shard spikes: rears up on the back legs, then slams the forepaws down
		ShardSpikes = attack(0.78, {
			Body = V(22),
			Head = V(16),
			Jaw = V(26),
			LegFL = V(36),
			LegFR = V(36),
			LegBL = V(-8),
			LegBR = V(-8),
			Tail = V(16),
			Root = V(0, 0, 0, 0, 4),
		}, {
			Body = V(-8),
			Head = V(-12),
			Jaw = V(12),
			LegFL = V(-10),
			LegFR = V(-10),
			Tail = V(-4),
			Root = V(0, 0, 0, 0, -2),
		}, 1),
		-- the light-stream lunge: head low and jaw wide while the light gathers in its maw, then the whole body
		-- throws forward along the beam
		LumenBeam = attack(0.82, {
			Head = V(-14),
			Jaw = V(42),
			Body = V(-6),
			LegFL = V(-12),
			LegFR = V(-12),
			Tail = V(26),
			Root = V(0, 0, 0, 0, -3, 4),
		}, {
			Head = V(6),
			Jaw = V(48),
			Body = V(2),
			LegFL = V(24),
			LegFR = V(24),
			LegBL = V(-18),
			LegBR = V(-18),
			Tail = V(8),
			Root = V(0, 0, 0, 0, 0, -8),
		}, 1.1),
		-- the gravity pull: rears its head and gapes wide to swallow the light round it, then snaps down
		GravityPull = attack(
			0.9,
			{
				Head = V(20),
				Jaw = V(56),
				Body = V(10),
				LegFL = V(10, 0, -8),
				LegFR = V(10, 0, 8),
				Tail = V(24),
				Root = V(0, 0, 0, 0, 2),
			},
			{
				Head = V(-14),
				Jaw = V(0),
				Body = V(-8),
				LegFL = V(-6),
				LegFR = V(-6),
				Tail = V(-4),
				Root = V(0, 0, 0, 0, -2),
			},
			1,
			{
				K(
					0.4,
					{ Head = V(16), Jaw = V(46), Body = V(8), Tail = V(18), Root = V(0, 0, 0, 0, 1.5) },
					"out"
				),
			}
		),
	},
}

---------------------------------------------------------------------------
-- Leviathan Engine, the Deep Machine: rides the swell, its gears, turbine and tide wheel always turning (the
-- pistons of the old machine run faster as it winds up), the neck coils and sweeps, it dives and surfaces.
---------------------------------------------------------------------------

local lev: Set = {
	segments = { "Root", "Body", "Neck", "Head", "Jaw", "GearL", "GearR", "CogL", "CogR", "Turbine", "Wheel" },
	spin = {
		GearL = { axis = "x", rate = 40 },
		GearR = { axis = "x", rate = -40 },
		CogL = { axis = "x", rate = -70 },
		CogR = { axis = "x", rate = 70 },
		Turbine = { axis = "y", rate = 90 },
		Wheel = { axis = "z", rate = 120 },
	},
	clips = {
		idle = clip(4.5, {
			K(0, BossPose.NONE),
			K(1.1, { Root = V(0, 0, 1.5, 0, 1.4), Neck = V(3), Head = V(-2, 8), Jaw = V(4) }),
			K(2.25, { Root = V(0, 0, 0, 0, 0), Neck = V(0), Head = V(0, 0), Jaw = V(1) }),
			K(3.4, { Root = V(0, 0, -1.5, 0, 1.4), Neck = V(3), Head = V(-2, -8), Jaw = V(4) }),
			K(4.5, BossPose.NONE),
		}, true),
		flinch = clip(0.6, {
			K(0, BossPose.NONE),
			K(0.14, { Neck = V(10, 0, 6), Head = V(16, -8), Jaw = V(22), Root = V(0, 0, 3, 0, -1) }, "out"),
			K(0.6, BossPose.NONE),
		}),
		weak = clip(2.4, {
			K(0, BossPose.NONE),
			K(0.45, { Neck = V(-30), Head = V(-10), Jaw = V(14), Root = V(0, 0, 0, 0, -2) }, "out"),
			K(1.9, { Neck = V(-26), Head = V(-8), Jaw = V(18), Root = V(0, 0, 0, 0, -1.5) }),
			K(2.4, BossPose.NONE),
		}),
		stagger = clip(1.6, {
			K(0, BossPose.NONE),
			K(0.22, { Root = V(0, 0, 10, 0, -2), Neck = V(4, 10, -12), Head = V(6, 14), Jaw = V(26) }, "out"),
			K(0.8, { Root = V(0, 0, -4, 0, -1), Neck = V(0, -6, 6), Head = V(-4, -8), Jaw = V(8) }),
			K(1.6, BossPose.NONE),
		}),
		enrage = clip(2.2, {
			K(0, BossPose.NONE),
			K(0.5, { Root = V(0, 0, 0, 0, 6), Neck = V(20), Head = V(26), Jaw = V(46) }, "out"),
			K(1.6, { Root = V(0, 0, 0, 0, 6.5), Neck = V(22, 4), Head = V(28), Jaw = V(50) }),
			K(2.2, BossPose.NONE),
		}),
		defeat = clip(3, {
			K(0, BossPose.NONE),
			K(0.5, { Root = V(0, 0, 0, 0, 4), Neck = V(18), Head = V(24), Jaw = V(44) }, "out"),
			K(1.5, { Root = V(0, 0, 12, 0, -4), Neck = V(-36, 0, 10), Head = V(-20), Jaw = V(30) }, "in"),
			K(3, { Root = V(0, 0, 20, 0, -10), Neck = V(-50, 0, 16), Head = V(-30), Jaw = V(34) }, "in"),
		}),
		-- it surfaces, the head up out of the spray, and roars
		land = clip(2.4, {
			K(0, { Neck = V(-20), Head = V(-10), Root = V(0, 0, 0, 0, -8) }),
			K(1, { Neck = V(24), Head = V(20), Jaw = V(40), Root = V(0, 0, 0, 0, 3) }, "out"),
			K(1.8, { Neck = V(20), Head = V(22), Jaw = V(44), Root = V(0, 0, 0, 0, 2) }),
			K(2.4, BossPose.NONE),
		}),
		shot = clip(0.45, {
			K(0, BossPose.NONE),
			K(0.1, { Root = V(0, 0, 0, 0, -0.8), Neck = V(-3) }, "out"),
			K(0.45, BossPose.NONE),
		}),
	},
	attacks = {
		-- the sweep: the neck and body coil round to one side, then whip across the front
		TailSweep = attack(
			0.8,
			{ Neck = V(4, 34), Head = V(0, 16), Body = V(0, 12), Jaw = V(12), Root = V(0, 0, 4) },
			{ Neck = V(-2, -34), Head = V(0, -16), Body = V(0, -12), Jaw = V(20), Root = V(0, 0, -4) },
			1
		),
		-- the torpedo volley: it dips low into the water, then surges up and the bays fire
		TorpedoVolley = attack(
			0.8,
			{ Root = V(0, 0, 0, 0, -8), Neck = V(-20), Head = V(-10), Jaw = V(10) },
			{ Root = V(0, 0, 0, 0, 2), Neck = V(10), Head = V(12), Jaw = V(26) },
			1
		),
		-- the whirlpool: it sinks and leans, the machinery racing, then rears up with a roar
		Whirlpool = attack(
			0.85,
			{ Root = V(0, 0, -6, 0, -4), Neck = V(-24, 10), Head = V(-14), Jaw = V(30) },
			{ Root = V(0, 0, 2, 0, 3), Neck = V(16), Head = V(20), Jaw = V(40) },
			1.1
		),
		-- the surge: it rises high out of the sea, then crashes back down
		Surge = attack(
			0.82,
			{ Root = V(0, 0, 0, 0, 12), Neck = V(16), Head = V(20), Jaw = V(34) },
			{ Root = V(0, 0, 0, 0, -6), Neck = V(-26), Head = V(-20), Jaw = V(4) },
			1.1
		),
	},
}

---------------------------------------------------------------------------
-- Bulwark's battle form (the War-Frame, mission 6): a mech. Braces for rockets, sweeps its blade arm, stomps,
-- sprays the floor and hunches over the chest laser's charge.
---------------------------------------------------------------------------

local war: Set = {
	segments = {
		"Root",
		"Body",
		"ThighL",
		"ShinL",
		"ThighR",
		"ShinR",
		"Head",
		"ArmL",
		"ForeL",
		"ArmR",
		"ForeR",
	},
	clips = {
		idle = clip(3, {
			K(0, BossPose.NONE),
			K(
				0.75,
				{ Root = V(0, 0, 0, 0, -0.4), Body = V(0, 3), Head = V(0, 10), ArmL = V(3), ArmR = V(-3) }
			),
			K(1.5, { Body = V(0, 0), Head = V(0, 0) }),
			K(
				2.25,
				{ Root = V(0, 0, 0, 0, -0.4), Body = V(0, -3), Head = V(0, -10), ArmL = V(-3), ArmR = V(3) }
			),
			K(3, BossPose.NONE),
		}, true),
		flinch = clip(0.5, {
			K(0, BossPose.NONE),
			K(0.1, {
				Body = V(10, 0, 4),
				Head = V(12),
				ArmL = V(8, 0, -14),
				ArmR = V(8, 0, 14),
				Root = V(0, 0, 0, 0, 0, 1),
			}, "out"),
			K(0.5, BossPose.NONE),
		}),
		weak = clip(2.4, {
			K(0, BossPose.NONE),
			K(0.4, {
				ThighL = V(40),
				ShinL = V(-62),
				ThighR = V(-6),
				ShinR = V(-20),
				Body = V(-16),
				Head = V(-14),
				ArmL = V(-6, 0, -10),
				ArmR = V(14, 0, 8),
				Root = V(0, 0, 0, 0, -4),
			}, "out"),
			K(1.9, {
				ThighL = V(38),
				ShinL = V(-60),
				ThighR = V(-6),
				ShinR = V(-18),
				Body = V(-14),
				Head = V(-12),
				ArmL = V(-6, 0, -10),
				ArmR = V(12, 0, 8),
				Root = V(0, 0, 0, 0, -4),
			}),
			K(2.4, BossPose.NONE),
		}),
		stagger = clip(1.5, {
			K(0, BossPose.NONE),
			K(0.2, {
				Body = V(12, 0, -10),
				Root = V(0, 0, 0, -2, -1),
				ThighR = V(20),
				ShinR = V(-28),
				Head = V(-8, -12),
				ArmR = V(14, 0, 26),
			}, "out"),
			K(0.7, { Body = V(2, 0, 4), Head = V(2, 6) }),
			K(1.5, BossPose.NONE),
		}),
		enrage = clip(2, {
			K(0, BossPose.NONE),
			K(
				0.4,
				both({
					Body = V(10),
					ArmL = V(24, 0, -44),
					ForeL = V(36),
					Head = V(14),
					Root = V(0, 0, 0, 0, 0.5),
				}),
				"out"
			),
			K(
				1.5,
				both({
					Body = V(12),
					ArmL = V(28, 0, -48),
					ForeL = V(40),
					Head = V(16),
					Root = V(0, 0, 0, 0, 0.5),
				})
			),
			K(2, BossPose.NONE),
		}),
		defeat = clip(3, {
			K(0, BossPose.NONE),
			K(0.4, { Body = V(12, 0, 6), Head = V(16), ArmL = V(14, 0, -24), ArmR = V(10, 0, 20) }, "out"),
			K(1.3, {
				ThighL = V(44),
				ShinL = V(-66),
				ThighR = V(38),
				ShinR = V(-58),
				Body = V(-26, 0, -6),
				Head = V(-24),
				ArmL = V(-12, 0, -6),
				ArmR = V(-14, 0, 6),
				Root = V(0, 0, 0, 0, -8),
			}, "in"),
			K(3, {
				ThighL = V(48),
				ShinL = V(-72),
				ThighR = V(44),
				ShinR = V(-68),
				Body = V(-40, 0, -8),
				Head = V(-30, -10),
				ArmL = V(-20, 0, -4),
				ArmR = V(-22, 0, 4),
				Root = V(-8, 0, 0, 0, -12),
			}, "in"),
		}),
		land = clip(2, {
			K(
				0,
				both({
					ThighL = V(34),
					ShinL = V(-52),
					Body = V(-18),
					ArmL = V(-8, 0, -26),
					Head = V(-16),
					Root = V(0, 0, 0, 0, -5),
				})
			),
			K(
				0.8,
				both({
					ThighL = V(30),
					ShinL = V(-46),
					Body = V(-14),
					ArmL = V(-6, 0, -24),
					Head = V(-8),
					Root = V(0, 0, 0, 0, -4),
				})
			),
			K(
				1.4,
				both({ Body = V(4), ArmL = V(10, 0, -24), Head = V(10), Root = V(0, 0, 0, 0, 0.3) }),
				"out"
			),
			K(2, BossPose.NONE),
		}),
		shot = clip(
			0.4,
			{ K(0, BossPose.NONE), K(0.08, { Body = V(3, 0, 0, 0, 0, 0.5) }, "out"), K(0.4, BossPose.NONE) }
		),
	},
	attacks = {
		Rockets = attack(0.8, {
			Body = V(8),
			Head = V(10),
			ArmL = V(20, 0, -10),
			ArmR = V(20, 0, 10),
			ThighL = V(6),
			ThighR = V(6),
			ShinL = V(-10),
			ShinR = V(-10),
			Root = V(0, 0, 0, 0, -0.8),
		}, {
			Body = V(-3),
			Head = V(-2),
			ArmL = V(8, 0, -14),
			ArmR = V(8, 0, 14),
			Root = V(0, 0, 0, 0, 0, 1.5),
		}, 0.8),
		GroundSweep = attack(0.78, {
			Body = V(2, 30),
			ArmR = V(30, 0, 40),
			ForeR = V(20),
			ArmL = V(-10, 0, -12),
			Head = V(0, 12),
			Root = V(0, 0, 0, 0, -0.8),
		}, {
			Body = V(-4, -34),
			ArmR = V(70, 0, 10),
			ForeR = V(16),
			ArmL = V(10, 0, -20),
			Head = V(-4, -14),
			Root = V(0, 0, 0, 0, -1),
		}, 0.9),
		Stomp = attack(0.82, {
			ThighR = V(46),
			ShinR = V(-34),
			Body = V(6, 0, -6),
			ArmL = V(16, 0, -26),
			ArmR = V(10, 0, 30),
			Head = V(8),
			Root = V(0, 0, 0, 0, 1),
		}, {
			ThighR = V(-4),
			ShinR = V(0),
			ThighL = V(10),
			ShinL = V(-14),
			Body = V(-8),
			ArmL = V(-6, 0, -16),
			ArmR = V(-6, 0, 16),
			Head = V(-8),
			Root = V(0, 0, 0, 0, -1.5),
		}, 0.9),
		FloorFire = attack(0.8, {
			ArmL = V(50, -10, -6),
			ForeL = V(30),
			ArmR = V(50, 10, 6),
			ForeR = V(30),
			Body = V(-10, 26),
			Head = V(-10, 10),
		}, {
			ArmL = V(46, -10, -6),
			ForeL = V(24),
			ArmR = V(46, 10, 6),
			ForeR = V(24),
			Body = V(-8, -26),
			Head = V(-8, -12),
		}, 1),
		ChargeLaser = attack(
			0.88,
			{
				Body = V(-12),
				Head = V(-6),
				ArmL = V(24, 0, -40),
				ArmR = V(24, 0, 40),
				ForeL = V(30),
				ForeR = V(30),
				ThighL = V(10),
				ThighR = V(10),
				ShinL = V(-16),
				ShinR = V(-16),
				Root = V(0, 0, 0, 0, -2),
			},
			{
				Body = V(10),
				Head = V(6),
				ArmL = V(-6, 0, -46),
				ArmR = V(-6, 0, 46),
				ForeL = V(10),
				ForeR = V(10),
				Root = V(0, 0, 0, 0, 0, 2),
			},
			1.1,
			{
				K(0.4, {
					Body = V(-8),
					ArmL = V(16, 0, -30),
					ArmR = V(16, 0, 30),
					ForeL = V(20),
					ForeR = V(20),
					Root = V(0, 0, 0, 0, -1),
				}, "out"),
			}
		),
	},
}

---------------------------------------------------------------------------
-- bosses-3 (2026-11-20; DRAFT looks until nate OKs them). PLACEHOLDER ANIMATION like the rest: hand-keyed poses.
-- The Storm Colossus hovers (its idle bobs and its lift fan spins), the Swarm Queen's shells swing open when its core
-- is exposed (weak) and its orbit rings spin, the Quarry Titan moves like the titans (Rustjaw's clips without a jaw).
---------------------------------------------------------------------------

-- A clip set copied from another boss with the segments this one does not have left out
local function without(clips: { [string]: Clip }, drop: { [string]: boolean }): { [string]: Clip }
	local out = {}
	for name, c in clips do
		local keys = {}
		for _, k in c.keys do
			local pose: Pose = {}
			for seg, v in k.pose do
				if not drop[seg] then
					pose[seg] = v
				end
			end
			if next(k.pose) == nil then
				pose = BossPose.NONE
			end
			table.insert(keys, { t = k.t, pose = pose, e = k.e, peak = k.peak, hit = k.hit })
		end
		out[name] = { dur = c.dur, loop = c.loop, keys = keys }
	end
	return out
end

local storm: Set = {
	segments = { "Root", "Body", "Fan", "Head", "ArmL", "ForeL", "ArmR", "ForeR" },
	spin = { Fan = { axis = "y", rate = 540 } },
	clips = {
		idle = clip(3, {
			K(0, BossPose.NONE),
			K(1.5, {
				Root = V(2, 0, 3, 0, 1.6),
				Body = V(0, 6),
				Head = V(-3, -8),
				ArmL = V(6, 0, -6),
				ForeL = V(8),
				ArmR = V(-4, 0, 6),
				ForeR = V(6),
			}),
			K(3, BossPose.NONE),
		}, true),
		flinch = clip(0.55, {
			K(0, BossPose.NONE),
			K(
				0.12,
				{ Root = V(8, 0, 4, 0, 0, 2), Head = V(10, 8), ArmL = V(-10, 0, -16), ArmR = V(-6, 0, 18) },
				"out"
			),
			K(0.55, BossPose.NONE),
		}),
		-- it sags, sparking: the fan sputters and it lists to one side (its core and dynamo in reach)
		weak = clip(2.4, {
			K(0, BossPose.NONE),
			K(
				0.4,
				{ Root = V(10, 0, 8, 0, -4), Head = V(18, 10), ArmL = V(30, 0, -20), ArmR = V(20, 0, 30) },
				"out"
			),
			K(1.8, { Root = V(8, 0, 6, 0, -3), Head = V(14, 6), ArmL = V(26, 0, -18), ArmR = V(18, 0, 26) }),
			K(2.4, BossPose.NONE),
		}),
		stagger = clip(1.6, {
			K(0, BossPose.NONE),
			K(0.25, {
				Root = V(-10, 0, -8, 0, -2),
				Head = V(-14, -10),
				ArmL = V(-20, 0, -40),
				ArmR = V(-20, 0, 40),
			}, "out"),
			K(0.8, { Root = V(6, 0, 4), Head = V(8, 6), ArmL = V(10, 0, -10), ArmR = V(10, 0, 10) }),
			K(1.6, BossPose.NONE),
		}),
		-- it throws its arms wide and crackles: the storm builds
		enrage = clip(2.2, {
			K(0, BossPose.NONE),
			K(0.5, {
				Root = V(-6, 0, 0, 0, 2),
				Head = V(-20),
				ArmL = V(-40, 0, -60),
				ArmR = V(-40, 0, 60),
				ForeL = V(30),
				ForeR = V(30),
			}, "out"),
			K(1.6, {
				Root = V(-6, 0, 0, 0, 2),
				Head = V(-22),
				ArmL = V(-44, 0, -64),
				ArmR = V(-44, 0, 64),
				ForeL = V(34),
				ForeR = V(34),
			}),
			K(2.2, BossPose.NONE),
		}),
		-- the fan dies: it tips over and drops (it holds the last pose; WorldFx sinks it)
		defeat = clip(3, {
			K(0, BossPose.NONE),
			K(
				0.5,
				{ Root = V(10, 0, 10), Head = V(20, 14), ArmL = V(20, 0, -30), ArmR = V(10, 0, 40) },
				"out"
			),
			K(3, {
				Root = V(12, 0, 14, 0, -26),
				Body = V(10, 20),
				Head = V(26, 20),
				ArmL = V(40, 0, -40),
				ArmR = V(30, 0, 50),
				ForeL = V(40),
				ForeR = V(40),
			}, "in"),
		}),
		land = clip(2, {
			K(0, { Root = V(0, 0, 0, 0, 12), ArmL = V(-30, 0, -50), ArmR = V(-30, 0, 50) }),
			K(
				1.2,
				{ Root = V(-4, 0, 0, 0, -2), ArmL = V(10, 0, -30), ArmR = V(10, 0, 30), Head = V(-10) },
				"out"
			),
			K(2, BossPose.NONE),
		}),
		shot = clip(
			0.4,
			{ K(0, BossPose.NONE), K(0.08, { Body = V(0, 0, 0, 0, 0, 0.6) }, "out"), K(0.4, BossPose.NONE) }
		),
	},
	attacks = {
		-- both coil hands rise: the clouds answer with bolts
		Lightning = attack(
			0.75,
			{ ArmL = V(-60, 0, -30), ArmR = V(-60, 0, 30), ForeL = V(30), ForeR = V(30), Head = V(-16) },
			{
				ArmL = V(-100, 0, -24),
				ArmR = V(-100, 0, 24),
				ForeL = V(10),
				ForeR = V(10),
				Head = V(-24),
				Root = V(0, 0, 0, 0, 1),
			},
			0.9
		),
		-- it winds back and swings both arms forward: the fan roars and the wind blasts out
		Gust = attack(
			0.7,
			{ Root = V(-8, 0, 0, 0, 0, 2), ArmL = V(-30, 0, -50), ArmR = V(-30, 0, 50), Body = V(-6) },
			{
				Root = V(10, 0, 0, 0, 0, -2),
				ArmL = V(70, 0, -20),
				ArmR = V(70, 0, 20),
				Body = V(8),
			},
			0.9
		),
		-- it rises and spreads its arms: the clouds gather
		StormCloud = attack(0.7, { Root = V(0, 0, 0, 0, -2), ArmL = V(10, 0, -10), ArmR = V(10, 0, 10) }, {
			Root = V(0, 0, 0, 0, 3),
			ArmL = V(-50, 0, -70),
			ArmR = V(-50, 0, 70),
			Head = V(-20),
		}, 1),
		-- a whip of both arms across the ground
		StormLash = attack(
			0.75,
			{ Body = V(0, 30), ArmR = V(-20, 0, 50), ArmL = V(10, 0, -30), Head = V(0, 16) },
			{
				Body = V(0, -30),
				ArmR = V(60, 0, 10),
				ArmL = V(40, 0, -40),
				Head = V(0, -16),
			},
			1
		),
		BallLightning = attack(0.75, { ArmL = V(20, 0, -20), ArmR = V(20, 0, 20), Head = V(10) }, {
			ArmL = V(-120, 0, -20),
			ArmR = V(-120, 0, 20),
			Head = V(-26),
			Root = V(0, 0, 0, 0, 1),
		}, 0.9),
		-- a ring of thunder round its body: it curls up, then flings everything out
		Thunderhead = attack(
			0.7,
			{ Root = V(10), ArmL = V(40, 0, 20), ArmR = V(40, 0, -20), Head = V(16) },
			{
				Root = V(-6),
				ArmL = V(-20, 0, -80),
				ArmR = V(-20, 0, 80),
				Head = V(-20),
			},
			0.9
		),
		-- one arm reaches for the kiter and twists: the vortex pulls
		Vortex = attack(0.75, { ArmR = V(-20, 0, 40), ForeR = V(30), Body = V(0, -20) }, {
			ArmR = V(80, 0, 10),
			ForeR = V(0),
			Body = V(0, 24),
			Head = V(0, 14),
		}, 0.9),
	},
}

local swarm: Set = {
	segments = { "Root", "Body", "ShellL", "ShellR", "Crown", "RingA", "RingB" },
	spin = { RingA = { axis = "y", rate = 70 }, RingB = { axis = "y", rate = -45 } },
	clips = {
		idle = clip(3.2, {
			K(0, BossPose.NONE),
			K(1.6, {
				Root = V(0, 0, 0, 0, 2),
				Body = V(3, 8),
				Crown = V(-4, -10),
				ShellL = V(0, 0, -4),
				ShellR = V(0, 0, 4),
			}),
			K(3.2, BossPose.NONE),
		}, true),
		flinch = clip(0.5, {
			K(0, BossPose.NONE),
			K(
				0.1,
				{ Root = V(6, 0, 0, 0, 0, 2), ShellL = V(0, 0, -10), ShellR = V(0, 0, 10), Crown = V(10) },
				"out"
			),
			K(0.5, BossPose.NONE),
		}),
		-- its formations are broken: the shells swing wide open and the core hangs bare
		weak = clip(2.4, {
			K(0, BossPose.NONE),
			K(
				0.35,
				{ ShellL = V(0, 0, -50), ShellR = V(0, 0, 50), Crown = V(-10), Root = V(6, 0, 0, 0, -2) },
				"out"
			),
			K(1.9, { ShellL = V(0, 0, -46), ShellR = V(0, 0, 46), Crown = V(-8), Root = V(4, 0, 0, 0, -2) }),
			K(2.4, BossPose.NONE),
		}),
		stagger = clip(1.5, {
			K(0, BossPose.NONE),
			K(
				0.25,
				{ Root = V(-8, 0, 6), ShellL = V(0, 0, -20), ShellR = V(0, 0, 20), Crown = V(-14) },
				"out"
			),
			K(1.5, BossPose.NONE),
		}),
		enrage = clip(2, {
			K(0, BossPose.NONE),
			K(
				0.4,
				{ Root = V(0, 0, 0, 0, 3), ShellL = V(0, 0, -24), ShellR = V(0, 0, 24), Crown = V(-16) },
				"out"
			),
			K(1.5, { Root = V(0, 0, 0, 0, 3), ShellL = V(0, 0, -26), ShellR = V(0, 0, 26), Crown = V(-18) }),
			K(2, BossPose.NONE),
		}),
		defeat = clip(3, {
			K(0, BossPose.NONE),
			K(0.6, { ShellL = V(0, 0, -40), ShellR = V(0, 0, 40), Root = V(8, 0, 6) }, "out"),
			K(
				3,
				{ ShellL = V(0, 0, -58), ShellR = V(0, 0, 58), Crown = V(18, 20), Root = V(9, 0, 9, 0, -24) },
				"in"
			),
		}),
		land = clip(2, {
			K(0, { Root = V(0, 0, 0, 0, 10), ShellL = V(0, 0, -30), ShellR = V(0, 0, 30) }),
			K(1.2, { Root = V(0, 0, 0, 0, -2) }, "out"),
			K(2, BossPose.NONE),
		}),
		shot = clip(
			0.4,
			{ K(0, BossPose.NONE), K(0.08, { Body = V(0, 0, 0, 0, 0, 0.5) }, "out"), K(0.4, BossPose.NONE) }
		),
	},
	attacks = {
		DroneFist = attack(0.75, { Body = V(-10), Crown = V(-10), Root = V(0, 0, 0, 0, 2) }, {
			Body = V(14),
			Crown = V(12),
			Root = V(0, 0, 0, 0, -2),
		}, 0.9),
		FistSweep = attack(
			0.75,
			{ Body = V(0, 30), Crown = V(0, 16) },
			{ Body = V(0, -30), Crown = V(0, -16) },
			0.9
		),
		DroneRain = attack(0.7, { ShellL = V(0, 0, -16), ShellR = V(0, 0, 16), Crown = V(-12) }, {
			ShellL = V(0, 0, -30),
			ShellR = V(0, 0, 30),
			Crown = V(-20),
			Root = V(0, 0, 0, 0, 2),
		}, 0.9),
		DroneWall = attack(0.75, { Body = V(0, -24), Root = V(0, 0, 0, 0, 0, 2) }, {
			Body = V(0, 24),
			Root = V(0, 0, 0, 0, 0, -2),
		}, 1),
		GiantStomp = attack(0.8, { Root = V(-6, 0, 0, 0, 5), Crown = V(-10) }, {
			Root = V(8, 0, 0, 0, -4),
			Crown = V(10),
			ShellL = V(0, 0, -12),
			ShellR = V(0, 0, 12),
		}, 1),
		Stingers = attack(
			0.75,
			{ Crown = V(10), Body = V(6) },
			{ Crown = V(-24), Body = V(-10), Root = V(0, 0, 0, 0, 1) },
			0.9
		),
		HiveCrush = attack(0.7, { ShellL = V(0, 0, -30), ShellR = V(0, 0, 30) }, {
			ShellL = V(0, 0, 4),
			ShellR = V(0, 0, -4),
			Crown = V(14),
		}, 0.9),
		DroneChain = attack(0.75, { Body = V(0, 24), Crown = V(0, 14) }, {
			Body = V(10, -14),
			Crown = V(6, -10),
			Root = V(0, 0, 0, 0, 0, -2),
		}, 0.9),
	},
}

local titan: Set = {
	segments = {
		"Root",
		"Body",
		"ThighL",
		"ShinL",
		"ThighR",
		"ShinR",
		"Head",
		"ArmL",
		"ForeL",
		"ArmR",
		"ForeR",
	},
	clips = without(rust.clips, { Jaw = true }),
	attacks = {
		-- both boulder fists come up over its head, then down into the ground
		GroundSlam = attack(0.8, {
			ArmL = V(-120, 0, -16),
			ArmR = V(-120, 0, 16),
			ForeL = V(20),
			ForeR = V(20),
			Body = V(-14),
			Head = V(-10),
			Root = V(0, 0, 0, 0, 1),
		}, {
			ArmL = V(40, 0, -10),
			ArmR = V(40, 0, 10),
			ForeL = V(10),
			ForeR = V(10),
			Body = V(26),
			Head = V(14),
			ThighL = V(16),
			ThighR = V(16),
			ShinL = V(-24),
			ShinR = V(-24),
			Root = V(0, 0, 0, 0, -3),
		}, 1),
		-- it tears a boulder up and hurls it overarm
		RockThrow = attack(0.78, {
			ArmR = V(-110, 0, 30),
			ForeR = V(40),
			Body = V(-6, 30),
			ArmL = V(20, 0, -20),
			Head = V(-6, 14),
		}, {
			ArmR = V(60, 0, 10),
			ForeR = V(10),
			Body = V(10, -24),
			ArmL = V(-10, 0, -24),
			Head = V(6, -12),
		}, 0.9),
		MagmaSweep = attack(0.78, { Body = V(2, 30), ArmR = V(30, 0, 40), ForeR = V(20), Head = V(0, 12) }, {
			Body = V(-4, -34),
			ArmR = V(70, 0, 10),
			ForeR = V(16),
			Head = V(-4, -14),
		}, 0.9),
		-- it beats its chest and the floor cracks open into lava
		LavaFloor = attack(
			0.75,
			{ ArmL = V(-40, 0, -40), ArmR = V(-40, 0, 40), Body = V(-10), Head = V(-14) },
			{
				ArmL = V(30, 0, -10),
				ArmR = V(30, 0, 10),
				Body = V(12),
				Head = V(10),
			},
			1
		),
		-- a full-body roar: lava bursts up all round it
		Eruption = attack(0.85, {
			Body = V(16),
			Head = V(20),
			ArmL = V(20, 0, -10),
			ArmR = V(20, 0, 10),
			ThighL = V(20),
			ThighR = V(20),
			ShinL = V(-30),
			ShinR = V(-30),
			Root = V(0, 0, 0, 0, -3),
		}, {
			Body = V(-20),
			Head = V(-24),
			ArmL = V(-60, 0, -60),
			ArmR = V(-60, 0, 60),
			Root = V(0, 0, 0, 0, 1),
		}, 1.1),
		LavaBombs = attack(
			0.75,
			{ ArmL = V(-20, 0, -30), ArmR = V(-20, 0, 30), Body = V(8), Head = V(14) },
			{
				ArmL = V(110, 0, -20),
				ArmR = V(110, 0, 20),
				Body = V(-6),
				Head = V(24),
			},
			0.9
		),
		MagmaGeyser = attack(0.75, { ArmR = V(-30, 0, 50), ForeR = V(30), Body = V(0, -20) }, {
			ArmR = V(125, 0, 10),
			ForeR = V(10),
			Body = V(-6, 22),
			Head = V(20, 10),
		}, 0.9),
		BoulderLeap = attack(0.6, {
			ThighL = V(40),
			ThighR = V(40),
			ShinL = V(-60),
			ShinR = V(-60),
			Body = V(20),
			Root = V(0, 0, 0, 0, -6),
		}, {
			ThighL = V(30),
			ThighR = V(30),
			ShinL = V(-50),
			ShinR = V(-50),
			Body = V(16),
			ArmL = V(-10, 0, -40),
			ArmR = V(-10, 0, 40),
			Root = V(0, 0, 0, 0, -5),
		}, 1),
	},
}

BossPose.SETS = {
	RustjawPrime = rust,
	LumenMaw = maw,
	LeviathanEngine = lev,
	NullWarFrame = war,
	StormColossus = storm,
	SwarmQueen = swarm,
	QuarryTitan = titan,
} :: { [string]: Set }

-- Joint limits (degrees; studs for a move), per boss and segment: every key of every clip, with the idle at its
-- biggest on top, stays inside them (tests). Spin-only machinery is not limited.
local function L(rx: number, ry: number, rz: number, move: number): { number }
	return { rx, ry, rz, move }
end
local TITAN = {
	Root = L(12, 4, 4, 24),
	Body = L(45, 40, 12, 2),
	ThighL = L(50, 0, 0, 0),
	ThighR = L(50, 0, 0, 0),
	ShinL = L(75, 0, 0, 0),
	ShinR = L(75, 0, 0, 0),
	Head = L(36, 30, 0, 0),
	Jaw = L(40, 0, 0, 0),
	ArmL = L(135, 12, 60, 0),
	ArmR = L(135, 12, 60, 0),
	ForeL = L(50, 0, 0, 0),
	ForeR = L(50, 0, 0, 0),
}
BossPose.LIMITS = {
	RustjawPrime = TITAN,
	NullWarFrame = TITAN,
	-- bosses-3: the golem's eruption throws its arms a little wider than Rustjaw ever does
	QuarryTitan = (function()
		local t = table.clone(TITAN)
		t.ArmL = L(135, 12, 66, 0)
		t.ArmR = L(135, 12, 66, 0)
		return t
	end)(),
	StormColossus = {
		Root = L(16, 4, 20, 30),
		Body = L(14, 40, 4, 1),
		Head = L(32, 32, 0, 0),
		ArmL = L(135, 4, 92, 0),
		ArmR = L(135, 4, 92, 0),
		ForeL = L(54, 0, 0, 0),
		ForeR = L(54, 0, 0, 0),
	},
	SwarmQueen = {
		Root = L(12, 4, 12, 28),
		Body = L(20, 44, 4, 1),
		Crown = L(32, 34, 4, 0),
		ShellL = L(4, 4, 66, 0),
		ShellR = L(4, 4, 66, 0),
	},
	LumenMaw = {
		Root = L(4, 4, 4, 20),
		Body = L(26, 4, 26, 0),
		Head = L(32, 30, 0, 0),
		Jaw = L(70, 0, 0, 0),
		Tail = L(40, 50, 10, 0),
		LegFL = L(42, 0, 42, 0),
		LegFR = L(42, 0, 42, 0),
		LegBL = L(30, 0, 40, 0),
		LegBR = L(30, 0, 40, 0),
	},
	LeviathanEngine = {
		Root = L(4, 4, 24, 14),
		Body = L(0, 14, 0, 0),
		Neck = L(56, 36, 18, 0),
		Head = L(34, 30, 0, 0),
		Jaw = L(56, 0, 0, 0),
	},
} :: { [string]: { [string]: { number } } }

---------------------------------------------------------------------------
-- Sampling
---------------------------------------------------------------------------

local function ease(f: number, e: string?): number
	if e == "in" then
		return f * f * f -- accelerating into the key: a strike lands hard
	elseif e == "out" then
		local g = 1 - f
		return 1 - g * g * g -- decelerating into the key: a settle
	elseif e == "linear" then
		return f
	end
	return f * f * (3 - 2 * f)
end

local ZERO: Vec = { 0, 0, 0, 0, 0, 0 }

local function vecOf(p: Pose, seg: string): Vec
	return p[seg] or ZERO
end

-- A clip's pose at time t (seconds; a loop wraps; past the end it holds the last key)
function BossPose.sample(c: Clip, t: number, out: Pose?): Pose
	local res: Pose = out or {}
	local keys = c.keys
	if c.loop and c.dur > 0 then
		t = t % c.dur
	end
	t = math.clamp(t, 0, c.dur)
	local a, b = keys[1], keys[#keys]
	for i = 1, #keys - 1 do
		if t >= keys[i].t and t <= keys[i + 1].t then
			a, b = keys[i], keys[i + 1]
			break
		end
	end
	if t >= keys[#keys].t then
		a, b = keys[#keys], keys[#keys]
	end
	local span = b.t - a.t
	local f = if span > 0 then ease((t - a.t) / span, b.e) else 1
	local segs: { [string]: boolean } = {}
	for seg in a.pose do
		segs[seg] = true
	end
	for seg in b.pose do
		segs[seg] = true
	end
	for seg in segs do
		local va, vb = vecOf(a.pose, seg), vecOf(b.pose, seg)
		local v = res[seg]
		if not v then
			v = { 0, 0, 0, 0, 0, 0 }
			res[seg] = v
		end
		for k = 1, 6 do
			v[k] = va[k] + (vb[k] - va[k]) * f
		end
	end
	return res
end

-- Add w x pose b into a (a changes)
function BossPose.add(a: Pose, b: Pose, w: number): Pose
	if w == 0 then
		return a
	end
	for seg, v in b do
		local o = a[seg]
		if not o then
			o = { 0, 0, 0, 0, 0, 0 }
			a[seg] = o
		end
		for k = 1, 6 do
			o[k] += v[k] * w
		end
	end
	return a
end

-- An attack's pose `elapsed` seconds after its warning began (warn: the attack's warning, as BossSim sent it):
-- the wind-up until the hit, then the recover. Returns the pose and the stage ("windup", "recover"), or nil once
-- it is over.
function BossPose.attack(
	bossId: string,
	attackId: string,
	elapsed: number,
	warn: number,
	out: Pose?
): (Pose?, string?)
	local set = BossPose.SETS[bossId]
	local a = set and set.attacks[attackId]
	if not a then
		return nil, nil
	end
	if elapsed < warn then
		return BossPose.sample(a.windup, math.clamp(elapsed / math.max(warn, 1e-3), 0, 1), out), "windup"
	end
	local r = elapsed - warn
	if r > a.recover.dur then
		return nil, nil
	end
	return BossPose.sample(a.recover, r, out), "recover"
end

-- When an attack's moments fall (seconds from its warning): the anticipation peak, the hit (= warn, BossSim's
-- resolve time) and the end of the recover
function BossPose.timing(
	bossId: string,
	attackId: string,
	warn: number
): { peak: number, hit: number, done: number }?
	local set = BossPose.SETS[bossId]
	local a = set and set.attacks[attackId]
	if not a then
		return nil
	end
	local peak, hit = 0, 0
	for _, k in a.windup.keys do
		if k.peak then
			peak = k.t * warn
		end
		if k.hit then
			hit = k.t * warn
		end
	end
	return { peak = peak, hit = hit, done = warn + a.recover.dur }
end

-- A clip by name (nil when the boss has none)
function BossPose.clip(bossId: string, name: string): Clip?
	local set = BossPose.SETS[bossId]
	return set and set.clips[name]
end

-- A spinning segment's angle (degrees) after t seconds at a rate scale
function BossPose.spinAngle(rate: number, t: number, scale: number): number
	return (rate * t * scale) % 360
end

-- The machinery's speed: faster while an attack winds up, fastest in phase 3
function BossPose.spinScale(phase: number, windingUp: boolean): number
	return (1 + 0.4 * (math.clamp(phase, 1, 3) - 1)) * (if windingUp then 2.5 else 1)
end

-- Does a Boss.State hp drop flinch it? (drop: hp lost since the last state; max: its max hp)
function BossPose.bigHit(drop: number, max: number): boolean
	return max > 0 and drop / max >= BossPose.flinchShare
end

---------------------------------------------------------------------------
-- The counters' attacks (pt-bosses, nate's playtest 2026-11-19: homing shots at fliers, a swat or snap at heroes
-- hovering by the body, the gap closers). PLACEHOLDER ANIMATION: simple hand-keyed poses so every attack id has a
-- clip; the animation pass (pt-anims) replaces them by adding real clips under the same ids in the sets above
-- (a clip already there wins: these only fill the gaps).
---------------------------------------------------------------------------

local COUNTERS: { [string]: { [string]: Attack } } = {
	RustjawPrime = {
		-- the shoulders hunch and the arms cock back, then both fling scrap up at the sky
		JunkFlak = attack(0.75, {
			ArmL = V(-20, 0, -30),
			ArmR = V(-20, 0, 30),
			Body = V(8),
			Head = V(14),
			Root = V(0, 0, 0, 0, -1),
		}, { ArmL = V(110, 0, -20), ArmR = V(110, 0, 20), Body = V(-6), Head = V(24), Jaw = V(16) }, 0.9),
		-- the right arm swings up and over, swatting the air above its shoulders
		Swat = attack(
			0.75,
			{ ArmR = V(-30, 0, 50), ForeR = V(30), Body = V(0, -20), Head = V(10, -10) },
			{ ArmR = V(125, 0, 10), ForeR = V(10), Body = V(-6, 22), Head = V(20, 10) },
			0.9
		),
		-- a deep crouch, then up and over: the Root lifts (the arc itself is WorldFx's) and lands in a crouch
		Leap = attack(0.6, {
			ThighL = V(40),
			ThighR = V(40),
			ShinL = V(-60),
			ShinR = V(-60),
			Body = V(20),
			Root = V(0, 0, 0, 0, -6),
		}, {
			ThighL = V(30),
			ThighR = V(30),
			ShinL = V(-50),
			ShinR = V(-50),
			Body = V(16),
			ArmL = V(-10, 0, -40),
			ArmR = V(-10, 0, 40),
			Root = V(0, 0, 0, 0, -5),
		}, 1),
	},
	LumenMaw = {
		-- the light sacs flare: the head tips up and the jaw opens to spit seekers at the sky
		LightSeekers = attack(
			0.75,
			{ Head = V(-10), Jaw = V(20), Body = V(-8), Root = V(0, 0, 0, 0, -1) },
			{ Head = V(24), Jaw = V(50), Body = V(10), Tail = V(10) },
			0.9
		),
		-- it rears on its back legs and snaps straight up
		SnapUp = attack(
			0.75,
			{ Body = V(-12), Head = V(-14), LegFL = V(-20), LegFR = V(-20), Root = V(0, 0, 0, 0, -2) },
			{ Body = V(16), Head = V(22), Jaw = V(52), LegFL = V(30), LegFR = V(30), Root = V(0, 0, 0, 0, 6) },
			1
		),
		-- the head aims low at its prey, then the lure beam lashes out
		LureBeam = attack(
			0.75,
			{ Head = V(-16, 20), Jaw = V(30), Body = V(-6) },
			{ Head = V(6, -10), Jaw = V(50), Body = V(6), Tail = V(0, 30) },
			0.9
		),
	},
	LeviathanEngine = {
		-- the neck coils back and the head tips skyward to fire torpedoes up
		SkyTorpedoes = attack(
			0.75,
			{ Neck = V(-20), Head = V(-10), Jaw = V(10) },
			{ Neck = V(40), Head = V(28), Jaw = V(40) },
			0.9
		),
		-- it surges up out of the water and snaps at what hovers above it
		Breach = attack(
			0.75,
			{ Neck = V(-30), Head = V(-20), Root = V(0, 0, 0, 0, -4) },
			{ Neck = V(40), Head = V(24), Jaw = V(42), Root = V(0, 0, 0, 0, 10) },
			1
		),
		-- the head turns to sight the kiter, then fires its harpoon
		Harpoon = attack(
			0.75,
			{ Neck = V(-10, 20), Head = V(-8, 16), Jaw = V(16) },
			{ Neck = V(20, -10), Head = V(6, -8), Jaw = V(30) },
			0.9
		),
	},
	NullWarFrame = {
		-- the shoulder pods tip up and the arms brace for the missile salvo
		SeekerMissiles = attack(
			0.75,
			{ Body = V(10), ArmL = V(-20, 0, -30), ArmR = V(-20, 0, 30), Root = V(0, 0, 0, 0, -1) },
			{ Body = V(-14), ArmL = V(40, 0, -40), ArmR = V(40, 0, 40), Head = V(20) },
			0.9
		),
		-- both arms sweep up overhead for the flak burst
		FlakBurst = attack(
			0.75,
			{ ArmL = V(-30, 0, -20), ArmR = V(-30, 0, 20), Body = V(12) },
			{ ArmL = V(130, 0, -30), ArmR = V(130, 0, 30), Body = V(-10), Head = V(24) },
			0.9
		),
		-- the right arm aims the grapple claw, then fires it out
		GrappleClaw = attack(
			0.75,
			{ ArmR = V(-20, 0, 30), ForeR = V(40), Body = V(0, -20) },
			{ ArmR = V(80, 0, 10), ForeR = V(0), Body = V(0, 16), Head = V(0, 10) },
			0.9
		),
	},
}
for bossId, list in COUNTERS do
	local set = BossPose.SETS[bossId]
	for id, a in list do
		if set and set.attacks[id] == nil then
			set.attacks[id] = a
		end
	end
end

return BossPose
