--!strict
-- Remotes: every remote in one table (spec: Remote events). Net creates them in ReplicatedStorage/Remotes,
-- checks every client argument against `schema` and rate-limits each player with a token bucket (`rate` per
-- second, `burst` max). Server-to-client remotes have no schema. Handlers still check state, cooldowns,
-- range and line of sight themselves (the spec's "Server validation" column).
-- Each milestone adds its rows here.

export type RemoteDef = {
	dir: string, -- "C2S" or "S2C"
	unreliable: boolean?,
	schema: { any }?,
	rate: number?,
	burst: number?,
}

local INT = "integer"
local function n(lo: number, hi: number, optional: boolean?)
	return { t = INT, min = lo, max = hi, optional = optional }
end
local V3 = { t = "Vector3" }

local Remotes: { [string]: RemoteDef } = {
	-- Combat (spec: Hit resolution). abilityNum, aimDir, targetHint (enemy id or 0), seq, the hero's own
	-- position as the client saw it (used only to pick the rewind time, never trusted for range)
	-- (5th, optional: the charge claimed, 0-100; the server caps it by the hold it timed from CombatCharge)
	CombatUse = {
		dir = "C2S",
		schema = { n(1, 1023), V3, n(0, 65535), n(0, 2 ^ 31), n(0, 100, true) },
		rate = 12,
		burst = 12,
	},
	CombatCharge = { dir = "C2S", schema = { n(1, 1023) }, rate = 12, burst = 12 }, -- a skill key went down
	CombatResult = { dir = "S2C" }, -- batched hits, 10 Hz, to players within 150 studs
	CombatEvents = { dir = "S2C" }, -- enemy shots, deaths and hero hits for the effects, 10 Hz batches

	CombatCancel = { dir = "C2S", schema = { n(0, 2 ^ 31) }, rate = 4, burst = 4 }, -- stop a channel (seq)
	Awaken = { dir = "C2S", schema = {}, rate = 1, burst = 2 }, -- spend a full Awakening meter
	-- Weapons (hero creator plan): hold the power (1) or the weapon (2); buy one at a safehouse Weapon Rack
	-- for Credits, or carry one you own (both at a safehouse); WeaponResult answers the Rack
	WeaponHold = { dir = "C2S", schema = { n(1, 2) }, rate = 6, burst = 6 },
	WeaponBuy = { dir = "C2S", schema = { n(1, 64) }, rate = 1, burst = 3 },
	WeaponCarry = { dir = "C2S", schema = { n(1, 64) }, rate = 2, burst = 4 },
	WeaponResult = { dir = "S2C" }, -- { ok, reason, id, kind = "buy" or "carry" }
	WeaponMastery = { dir = "S2C" }, -- { id, level, opened = { "X", ... } } when a weapon's Mastery level goes up

	-- Abilities (spec: Hero.Loadout, Skills.Rank, Skills.Mod, Skills.Respec). Ability numbers, 0 = empty.
	-- HeroLoadout: loadout index (1-2), the main path (1-17, Abilities.sets), skills 1-4, super
	HeroLoadout = {
		dir = "C2S",
		schema = { n(1, 2), n(1, 17), n(0, 255), n(0, 255), n(0, 255), n(0, 255), n(0, 255) },
		rate = 2,
		burst = 3,
	},
	SkillsRank = { dir = "C2S", schema = { n(1, 255) }, rate = 4, burst = 4 },
	SkillsMod = { dir = "C2S", schema = { n(1, 255), n(1, 2) }, rate = 2, burst = 4 },
	SkillsRespec = { dir = "C2S", schema = {}, rate = 1, burst = 1 },
	HeroStatus = { dir = "S2C" }, -- { meter, awakeLeft, buffs = { kind = { left, value } } }
	AbilityNotice = { dir = "S2C" }, -- { ok, reason } after a rank, mod, loadout or respec request

	-- Movement (spec: Move.Boost, Move.Correct)
	MoveBoost = { dir = "C2S", schema = { { t = "boolean" } }, rate = 4, burst = 4 },
	MoveCorrect = { dir = "S2C" }, -- position: sent when a speed or position check fails
	MovePound = { dir = "C2S", schema = {}, rate = 1, burst = 2 }, -- Leaping: the ground pound landed
	-- your movement mode (Shared.HeroAnim.MODES index) so other devices pose you; the server sets the Move attribute
	MoveMode = { dir = "C2S", schema = { n(1, 13) }, rate = 10, burst = 10 },

	-- Enemies (not in the spec's list; see EnemyBuffer and Decisions.md)
	EnemyDelta = { dir = "S2C", unreliable = true },

	-- Hero state the HUD needs that attributes do not carry well
	HeroState = { dir = "S2C" }, -- { level, classId, power, maxHealth, styles, loadout }

	-- Studio only: test commands and server frame stats (DevService refuses them in live servers)
	DevCommand = {
		dir = "C2S",
		schema = { { t = "string", max = 24 }, n(0, 1000, true) },
		rate = 4,
		burst = 6,
	},
	DevStats = { dir = "S2C" },

	-- Saves, gear and economy (spec: Profile.Sync, Gear.Equip, Gear.Upgrade, Gear.Salvage, Gear.Retune,
	-- Style.Apply, Toast). Piece ids are numbers; the server checks ownership, level and the wallet.
	ProfileSync = { dir = "S2C" }, -- ProfileSchema.clientView
	Toast = { dir = "S2C" }, -- { id = "levelUp" | "reward" | "saveDown" | "secondWind" | "gear", ... }
	LootDrop = { dir = "S2C" }, -- { piece, kind = "stashed" | "salvaged", dust }
	CooldownCut = { dir = "S2C" }, -- ability num, seconds (Cooling Kill)
	GearEquip = { dir = "C2S", schema = { n(0, 2 ^ 31), n(1, 8) }, rate = 4, burst = 6 }, -- piece id (0 = take off), slot
	GearUpgrade = { dir = "C2S", schema = { n(1, 2 ^ 31) }, rate = 4, burst = 6 },
	-- up to 20 piece ids; GearService checks each
	GearSalvage = {
		dir = "C2S",
		schema = { { t = "intList", maxLen = 20, min = 1, max = 2 ^ 31 } },
		rate = 1,
		burst = 2,
	},
	GearRetune = { dir = "C2S", schema = { n(1, 2 ^ 31), n(1, 3) }, rate = 1, burst = 2 },
	StyleApply = { dir = "C2S", schema = { n(1, 8), n(0, 511) }, rate = 4, burst = 6 }, -- slot, style (0 = the gear's own)
	GadgetUse = { dir = "C2S", schema = { V3 }, rate = 2, burst = 2 }, -- aim direction
	GadgetResult = { dir = "S2C" }, -- { kind, target, cd }

	-- World (M4; spec: Move.FastTravel at 1 per 20 s; the skip is the "skippable" part of the 3 s flight)
	MoveFastTravel = { dir = "C2S", schema = { n(1, 12) }, rate = 0.5, burst = 2 },
	MoveTravelSkip = { dir = "C2S", schema = {}, rate = 1, burst = 2 },
	FastTravel = { dir = "S2C" }, -- { ok, id, from, to, time } or { ok = false, reason, wait }
	FastTravelDone = { dir = "S2C" }, -- beacon id: the hero has landed

	-- Destruction (M5; spec: Building.Diff 2 Hz batched, Building.Snapshot on join). The client asks for the
	-- snapshot once its effects are ready, so it never misses the first diffs.
	BuildingSync = { dir = "C2S", schema = {}, rate = 0.2, burst = 2 },
	BuildingSnapshot = { dir = "S2C" }, -- { s = packed 2-bit states, n, dr = drone jobs }
	BuildingDiff = { dir = "S2C" }, -- { d = { id, state, ... }, dr = { { drone, building, seconds } } }
	BuildingImpact = { dir = "S2C" }, -- center, radius, kind (1 crater, 2 cracks)
	VehicleFlip = { dir = "S2C" }, -- vehicle id, push x, push z
	VehicleReset = { dir = "S2C" }, -- vehicle id
	CitizenDelta = { dir = "S2C", unreliable = true }, -- CitizenBuffer packet, 4 Hz

	-- World activity (M6; spec: Incident.Spawn/Update, Contract.Accept/Abandon/Update, Boss.State/
	-- Contribution/Result, Event.State, World.Clock). Rescues and the board open use ProximityPrompts (the
	-- server's own check), so Rescue.Pick and Rescue.Drop have no remotes (Decisions.md).
	IncidentSpawn = { dir = "S2C" }, -- { id, num, x, y, z, side, level, left, own, steps, kind }: one incident
	IncidentUpdate = { dir = "S2C" }, -- array of { id, frac, step, have, need, left, state, medal }, 2 Hz
	ContractBoard = { dir = "S2C" }, -- { offers, active, done, level }: the board screen
	ContractAccept = { dir = "C2S", schema = { n(1, 3) }, rate = 2, burst = 3 }, -- offer index
	ContractAbandon = { dir = "C2S", schema = { n(1, 3) }, rate = 2, burst = 3 }, -- active index
	ContractUpdate = { dir = "S2C" }, -- { list = { num, got, goal, dist, dx, dz } }, 2 Hz
	EventState = { dir = "S2C" }, -- { list = { num, x, z, left, have, need, state } }
	BossState = { dir = "S2C" }, -- { state, num, x, y, z, yaw, hp, max, phase, at, objectives }, 2 Hz
	BossAttack = { dir = "S2C" }, -- { kind, shape, x, z, yaw, r, warn }: telegraphs and strikes
	BossContribution = { dir = "S2C" }, -- { score, tier, rank, heroes }, 1 Hz to each fighter
	BossResult = { dir = "S2C" }, -- { defeated, tier, rank, credits, renown, drops, style, mvp }
	WorldClock = { dir = "S2C" }, -- { start, cycle }: the client works out the time of day
	-- Underwater (Config.Deep): caches open and commuters are picked up by swimming close (the server's own
	-- position check), so there is no C2S remote. { opened = { [cache id] = seconds left }, rescues = { [id]
	-- = true when waiting }, carriers = { [hero id] = rescue id } }
	DeepState = { dir = "S2C" },

	-- Story (M7; spec: Mission.Enter {missionId, partyId} 1/5s, Mission.Leave, Mission.State 2/s, Choice.Pick
	-- 1/s). NPC talk uses ProximityPrompts (the server's own check), so it has no remote.
	StoryState = { dir = "S2C" }, -- the Journal: { side, missions, choices, quests, pinned, perks, rep, states }
	StoryPin = { dir = "C2S", schema = { n(0, 8) }, rate = 2, burst = 3 }, -- 0 the story, 1 to 8 a side quest
	ChoicePrompt = { dir = "S2C" }, -- { id, labels }: the two (or three) big verb buttons
	ChoicePick = { dir = "C2S", schema = { n(0, 4), n(1, 3) }, rate = 1, burst = 2 }, -- choice id, option
	OpeningState = { dir = "S2C" }, -- { step, target = { x, y, z }, side, left }: the playable disaster
	OpeningAct = { dir = "C2S", schema = { n(1, 3) }, rate = 2, burst = 3 }, -- 1 Catch, 2 skip the flight, 3 Create First
	MissionEnter = { dir = "C2S", schema = { n(2, 6), n(0, 1000000, true) }, rate = 0.2, burst = 2 },
	MissionLeave = { dir = "C2S", schema = {}, rate = 0.5, burst = 2 },
	MissionState = { dir = "S2C" }, -- { num, step, steps, kind, have, need, left, points, target }, 2 Hz
	MissionResult = { dir = "S2C" }, -- { num, first, credits, renown, drops, skillPoints, rep, epic }
	QuestTalk = { dir = "S2C" }, -- { num, line, npc }: the NPC's speech bubble (fixed lines, no free text)
	QuestState = { dir = "S2C" }, -- { num, step, have, need, left, target, area }: the pinned quest, 2 Hz

	-- PvP, death and safety (M8; spec: Flag.Set {on} 1/5s, Flag.State, Revive.Start {targetUserId} 2/s,
	-- Down.GiveUp 1/s, Respawn.Choose {safehouseId}, Ping.Place {kind, position} 2/s, Report.Player
	-- {userId, reasonId} 1/10s). Everyone's flag rides on player attributes (Pvp, PvpSide) for the rings.
	FlagSet = { dir = "C2S", schema = { n(0, 1) }, rate = 0.2, burst = 2 }, -- 1 on, 0 off
	FlagState = { dir = "S2C" }, -- { on, flagged, crater, warnLeft, offIn, protectLeft, reason }: to the owner
	CraterLeave = { dir = "C2S", schema = {}, rate = 0.5, burst = 2 }, -- the Leave button during the warning
	ReviveStart = { dir = "C2S", schema = { n(1, 2 ^ 52) }, rate = 2, burst = 3 }, -- the Downed hero's user id
	DownGiveUp = { dir = "C2S", schema = {}, rate = 1, burst = 2 },
	DownState = { dir = "S2C" }, -- { downed, left, revive (0..1), by, respawnIn, pvp }: to the owner
	RespawnChoose = { dir = "C2S", schema = { n(0, 16) }, rate = 1, burst = 3 }, -- a visited safehouse, 0 nearest
	PingPlace = { dir = "C2S", schema = { n(1, 3), V3 }, rate = 2, burst = 3 }, -- 1 Help, 2 Here, 3 Danger
	PingShow = { dir = "S2C" }, -- { kind, x, y, z, from, life, downed }: a marker on allies' screens
	ReportPlayer = { dir = "C2S", schema = { n(1, 2 ^ 52), n(1, 4) }, rate = 0.1, burst = 2 }, -- user id, reason
	PvpResult = { dir = "S2C" }, -- { won, other, credits, fame, cut }: the win or defeat card
	HeroKnock = { dir = "S2C" }, -- { x, y, z, time }: a PvP knockback, pull or knockup on your own hero

	-- Creator, HQ, shops and passes (M9; spec: Hero.Create {side, classId, setId, look, colors, titleId,
	-- nounId} 1/10s, Hero.Select {slot} 1/5s). The look is one 128-byte LookCodec buffer.
	-- HeroCreate: look, side (1 hero, 2 villain), archetype (1-4), path in the archetype (1-5), title, noun,
	-- mobility (1-5, Move.mobilityOrder), weapon (a 12-byte WeaponRules look: id, style, finish, colours, ...)
	HeroCreate = {
		dir = "C2S",
		schema = {
			{ t = "buffer", len = { 128 } },
			n(1, 2),
			n(1, 4),
			n(1, 5),
			n(1, 12),
			n(1, 16),
			n(1, 5),
			{ t = "buffer", len = { 12 }, optional = true },
		},
		rate = 0.1,
		burst = 2,
	},
	HeroSelect = { dir = "C2S", schema = { n(1, 4) }, rate = 0.2, burst = 2 }, -- a character slot (new = create)
	CreatorOpen = { dir = "S2C" }, -- { mode = "create" | "edit" | "first", side, classIdx, hq }: open the creator
	CreatorResult = { dir = "S2C" }, -- { ok, reason }
	LookSave = { dir = "C2S", schema = { n(1, 4) }, rate = 1, burst = 2 }, -- save the look on mannequin n (HQ)
	LookWear = { dir = "C2S", schema = { n(1, 4) }, rate = 1, burst = 2 }, -- wear mannequin n's look (HQ)
	HqLeave = { dir = "C2S", schema = {}, rate = 0.5, burst = 2 },
	HqState = { dir = "S2C" }, -- { on, cell = { x, y, z }, side, level, dummies, bossSim, statues, props }
	HqUpgrade = { dir = "C2S", schema = {}, rate = 1, burst = 2 },
	HqBoard = { dir = "C2S", schema = {}, rate = 1, burst = 2 }, -- the command table's Contract Board
	HqTrophies = {
		dir = "C2S",
		schema = { { t = "intList", maxLen = 12, min = 1, max = 64 } },
		rate = 1,
		burst = 2,
	},
	HqCollect = { dir = "C2S", schema = {}, rate = 1, burst = 2 }, -- M11: bank the offline drones' haul
	IdleReport = { dir = "C2S", schema = { n(0, 600), n(1, 4) }, rate = 0.5, burst = 3 }, -- M11 wait gate
	-- M12: what only the device knows for analytics: kind (1 perf, 2 shop open, 3 item view, 4 photo, 5 hello), value, a, b
	Telemetry = {
		dir = "C2S",
		schema = { n(1, 5), n(0, 1000000), n(0, 1000), n(0, 1000) },
		rate = 1,
		burst = 6,
	},
	DronesReady = { dir = "S2C" }, -- { credits, minutes }: the COLLECT card
	HqBossSim = { dir = "C2S", schema = {}, rate = 0.2, burst = 2 }, -- start the 60 s boss sim (HQ level 3)
	HqDps = { dir = "S2C" }, -- { dps, total, sim = { left, hp, max } }: the training room meter, 2 Hz
	HqRetire = { dir = "C2S", schema = {}, rate = 0.1, burst = 1 }, -- Legacy at level 40 (Hall of Legends)
	GizmoBuy = { dir = "C2S", schema = { n(1, 511) }, rate = 2, burst = 3 }, -- a base style id, Credits only
	ShopBuy = { dir = "C2S", schema = { n(1, 64) }, rate = 1, burst = 3 }, -- an item (ShopRules.keys order)
	ShopResult = { dir = "S2C" }, -- { ok, key, kind, pieces, reason }: after a purchase lands (or not)
	ShopOffer = { dir = "S2C" }, -- { key }: the starter pack offer, once
	ShopDismiss = { dir = "C2S", schema = {}, rate = 1, burst = 2 },
	TintSet = { dir = "C2S", schema = { n(0, 10) }, rate = 1, burst = 3 }, -- an owned effect colour, 0 none
	LandingSet = { dir = "C2S", schema = { n(0, 31) }, rate = 1, burst = 3 }, -- an owned landing pose, 0 none
	EmotePlay = { dir = "C2S", schema = { n(1, 31) }, rate = 1, burst = 2 }, -- an owned emote or landing pose
	-- M10: settings (spec: Settings.Set {key, value} 2/s) and the saved mute list
	SettingsSet = { dir = "C2S", schema = { n(1, 16), n(0, 1000) }, rate = 2, burst = 6 },
	SettingsMute = { dir = "C2S", schema = { n(1, 2 ^ 52), n(0, 1) }, rate = 2, burst = 4 }, -- user id, on
	-- M10: squads (spec: Squad.Invite, Squad.Accept, Squad.Leave {userId or squadId} 1/s, Squad.State)
	SquadInvite = { dir = "C2S", schema = { n(1, 2 ^ 52) }, rate = 1, burst = 3 }, -- user id
	SquadAnswer = { dir = "C2S", schema = { n(0, 1) }, rate = 1, burst = 2 }, -- 1 accept, 0 decline
	SquadLeave = { dir = "C2S", schema = {}, rate = 1, burst = 2 },
	SquadKick = { dir = "C2S", schema = { n(1, 2 ^ 52) }, rate = 1, burst = 2 }, -- leader only
	SquadState = { dir = "S2C" }, -- { members = { { userId, name, level, classId, side, slot } }, leader }
	SquadInvited = { dir = "S2C" }, -- { from, name, size, life }: an invite card

	-- Hero MMO features (spec: Hero MMO features > Data, remotes and services)
	-- H1: hold Block (spec: Combat.Block {on} 10/s); GuardState to your own hero: { guard, on, broken (s
	-- left), cut = ability num (a charge or wind-up of yours was interrupted), cd }; GuardEvent to players
	-- near: { { k, x, y, z, a (actor user id or robot id), t } } words (block, perfect, shatter, cut) and
	-- robot shields (k "rup" / "rdown")
	CombatBlock = { dir = "C2S", schema = { { t = "boolean" } }, rate = 10, burst = 10 },
	GuardState = { dir = "S2C" },
	GuardEvent = { dir = "S2C" },
	-- H3: pick up and throw (spec: World.Grab {id} and World.Throw {aim} 4/s). WorldGrab: the item id
	-- (0 = set down what you hold); WorldThrow: the aim point. ThrowState to your own hero: { id (0 = hands
	-- free), kind, since }; ThrowFly to everyone: item id, from, to, flight time, arc peak, thrower's user id
	-- (each client flies the thing on the same arc); ThrowBack: item id (a thrown prop is home again)
	WorldGrab = { dir = "C2S", schema = { n(0, 65535) }, rate = 4, burst = 4 },
	WorldThrow = { dir = "C2S", schema = { V3 }, rate = 4, burst = 4 },
	ThrowState = { dir = "S2C" },
	ThrowFly = { dir = "S2C" },
	ThrowBack = { dir = "S2C" },
	-- H4: task forces (spec: TaskForce.List / TaskForce.Join / TaskForce.Look 1/s). TaskForceList: ask for
	-- the board; TaskForceJoin: action (1 open a squad for task force `arg`, 2 join squad `arg`, 3 leave your
	-- squad, 4 start, 5 lock to friends, 6 rejoin the run you left) and arg; TaskForceLook: Looking on.
	-- TaskForceBoard to you: { lobbies = { { id, tf, n, leader, locked, can } }, starts, mine, rejoin }
	TaskForceList = { dir = "C2S", schema = {}, rate = 1, burst = 3 },
	TaskForceJoin = { dir = "C2S", schema = { n(1, 6), n(0, 65535) }, rate = 1, burst = 3 },
	TaskForceLook = { dir = "C2S", schema = { { t = "boolean" } }, rate = 1, burst = 3 },
	TaskForceBoard = { dir = "S2C" },
	-- H5: your nemesis (spec: Nemesis.State S2C). NemesisPoster: ask for your WANTED poster; NemesisShowdown:
	-- start the Showdown (3 Intel). NemesisState: { k = poster | taunt | spawn | sig | cloak | escape | gloat |
	-- leave, seed, rank, traits, name, side, ... } (taunt lines are fixed lists filled with your hero name)
	NemesisPoster = { dir = "C2S", schema = {}, rate = 1, burst = 3 },
	NemesisShowdown = { dir = "C2S", schema = {}, rate = 1, burst = 2 },
	NemesisState = { dir = "S2C" },
}

return Remotes
