-- Block, breaker and interrupt (spec: Hero MMO features > Block, breaker and interrupt; H1). Pure data, tuned
-- in the playtest. Three moves beat each other in a circle, for heroes, villains and robots alike:
--   Block beats normal hits (front half: 70% less damage, no knockback; costs Guard).
--   Breakers beat Block (a heavy hit, a full charge, a grab, or Guard at 0 shatters it: 1 s stagger).
--   Interrupts beat breakers (a light hit, a stun or a knock cancels a heavy wind-up or a charge).
-- Rules live in Shared.GuardMath; the server (BlockService) and the client (BlockClient, GuardFx) read this.
return {
	block = {
		front = 180, -- degrees: hits from the front half are blocked
		cut = 0.7, -- blocked hits take 70% less damage
		moveMult = 0.5, -- you move at half speed while blocking, and cannot cast
		guardMax = 100, -- the Guard bar (the ring round the shield button)
		-- each blocked hit costs its damage as a share of your health x 100 (a hit of 20% health costs 20)
		drainScale = 100,
		refill = 25, -- Guard a second, after `refillDelay` seconds of not blocking
		refillDelay = 1,
		minGuard = 10, -- a block cannot start with less Guard than this (it would shatter at once)
		toggleRate = 10, -- CombatBlock per second (Remotes)
	},
	perfect = {
		window = 0.2, -- a block started this long (or less) before the hit lands is perfect
		stagger = 0.6, -- the attacker is staggered this long
		meter = 10, -- Awakening gained
	},
	breaker = {
		coeff = 2.5, -- the heavy line (the same as Config.Combat.heavyCoeff, the camera shake)
		fullCharge = 1, -- a charge at this level (1 = full) is a breaker (H2)
		stagger = 1, -- a shattered block staggers its owner this long, and the hit lands in full
	},
	interrupt = {
		coeff = 0.8, -- hits under this coefficient are light: they interrupt
		statuses = { stun = true, knockback = true, knockup = true, pull = true }, -- and so do these
		refund = 0.5, -- an interrupted wind-up (or charge) costs half its cooldown
		robotStun = 0.25, -- a robot's interrupted wind-up: the moment it reels
		robotsInterrupt = true, -- robots' light hits interrupt heroes too (the spec's "alike")
	},
	-- Robots (no tutorial: they teach the triangle with their tells). Their heavies already set the windup
	-- flag (red eyes); these kinds' hits are breakers against a hero's block.
	robotBreakers = { brute = true, guard = true },
	-- Robots that block on a timer and shine blue while they do (hit them with a heavy). The Null Sentinel
	-- keeps its own front guard (Config.Enemies guard) and a breaker now shatters it too.
	-- every: seconds between blocks (first one `first` after it starts fighting); time: how long it holds;
	-- cut: damage taken off hits from the `front` arc (degrees); brokenFor: no block for this long after a
	-- shatter. warn (optional): a telegraph this long before the block goes up (the blue shine builds and a
	-- whine rises; not blocking yet). size (optional): the shine's size for a big machine (a boss), drawn at
	-- the spot it was sent rather than on a drawn robot.
	robotBlocks = {
		BruteBot = { every = 7, time = 2.2, first = 2, cut = 0.7, front = 200, brokenFor = 5 },
		-- the Warden (kind NullSentinel; WP6, gap G9): it braces behind its shield. While braced its block
		-- covers the front 240 degrees (wider than its 120-degree guard, so a flank hit is blocked too) and
		-- stands in for the guard (no double cut); only a hit from behind or a breaker gets through. A breaker
		-- shatters the brace and the guard together.
		NullSentinel = { every = 9, time = 2.5, first = 3, cut = 0.85, front = 240, brokenFor = 6 },
		-- Bulwark's battle form, the War-Frame (BossSim id NullWarFrame; WP6, gap G9): a timed block with a
		-- 1.2 s telegraph, then 3.5 s of the shield on its front 200 degrees (the back weak point stays open).
		-- Never during its phase shield. A breaker shatters it and the War-Frame reels: its next attack waits
		-- `breaker.stagger`. NATE TO TUNE.
		NullWarFrame = {
			every = 14,
			time = 3.5,
			first = 6,
			cut = 0.75,
			front = 200,
			brokenFor = 10,
			warn = 1.2,
			size = 52,
		},
	},
	robotTick = 0.25, -- BlockService steps robot blocks this often
	stateRadius = 160, -- robot block starts and ends go to players this close
	wordGap = 0.4, -- the comic words pop at most this often per hero
	-- the comic words (fixed text, no free text)
	words = { block = "BLOCKED", perfect = "PERFECT!", shatter = "SHATTER!", cut = "CUT OFF!" },
	colors = {
		block = { 150, 200, 255 },
		perfect = { 255, 235, 120 },
		shatter = { 255, 140, 60 },
		cut = { 120, 255, 200 },
	},
	-- the held guard (item 149): a force-field face with a glowing core and an eight-sided neon rim that snaps up
	-- (raise seconds, from 0.3 of its size), kicks and flashes on each hit it takes, and runs from rim to low as
	-- your guard drains (flickering under flicker of it). Meshes from art/blender/guard.py (Art.Guard, Fx.GuardFx).
	shield = {
		color = { 110, 180, 255 },
		transparency = 0.55,
		size = 6,
		rim = { 205, 235, 255 },
		low = { 255, 110, 80 },
		sides = 8,
		raise = 0.14,
		kick = 1.14,
		flicker = 0.3,
	},
}
