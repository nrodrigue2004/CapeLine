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
	MoveMode = { dir = "C2S", schema = { n(1, 15) }, rate = 10, burst = 10 },

	-- Enemies (not in the spec's list; see EnemyBuffer and Decisions.md)
	EnemyDelta = { dir = "S2C", unreliable = true },
	-- lore step 4: who an evil twin copies ({ id, userId, words, path, name, title }; { id } when it is gone)
	EnemyIdentity = { dir = "S2C" },

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
	BuildingDiff = { dir = "S2C" }, -- { r = repaired ids, d = { id, state, ... }, c = { id, piece, cause, ... }, dr = { { drone, building, seconds } } }
	BuildingImpact = { dir = "S2C" }, -- center, radius, kind (1 crater, 2 cracks)
	-- Momentum and impact (2026-11-19): the device saw its hero ram a wall fast: the contact point, the travel
	-- direction and the speed it claims (ImpactService checks all three against its own history)
	ImpactRam = {
		dir = "C2S",
		schema = { V3, V3, { t = "number", min = 0, max = 400 } },
		rate = 4,
		burst = 6,
	},
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
	StoryState = { dir = "S2C" }, -- the Journal: { side, act, missions, choices, pinned, perks, rep, states, sq }
	StoryPin = { dir = "C2S", schema = { n(0, 127) }, rate = 2, burst = 3 }, -- 0 the story, else a chain in progress
	ChoicePrompt = { dir = "S2C" }, -- { id, labels }: the two (or three) big verb buttons
	ChoicePick = { dir = "C2S", schema = { n(0, 4), n(1, 3) }, rate = 1, burst = 2 }, -- choice id, option
	OpeningState = { dir = "S2C" }, -- { step, t, target, side, left, the scene's points }: the Ceremony prologue
	-- 1 the Spark fires, 2 skip a camera beat (replays only), 3 Create First, 4 play the prologue (main menu)
	OpeningAct = { dir = "C2S", schema = { n(1, 4) }, rate = 2, burst = 3 },
	MissionEnter = { dir = "C2S", schema = { n(2, 6), n(0, 1000000, true) }, rate = 0.2, burst = 2 },
	MissionLeave = { dir = "C2S", schema = {}, rate = 0.5, burst = 2 },
	MissionState = { dir = "S2C" }, -- { num, step, steps, side, kind, text, have, need, t, points, target, focus }, 2 Hz
	MissionResult = { dir = "S2C" }, -- { num, first, credits, renown, drops, skillPoints, rep, ending, sq }
	StoryBroadcast = { dir = "S2C" }, -- { id }: an act's ending broadcast (lore step 5: after Live, back in the city)
	-- lore step 7 (the cinematic layer): a device-started scene was seen (its Config.Cinema bit); skip a
	-- mission's camera beat (only when every hero on that stage has seen it); the news (facts and flashes)
	SceneSeen = { dir = "C2S", schema = { n(0, 255) }, rate = 0.5, burst = 3 },
	SceneSkip = { dir = "C2S", schema = {}, rate = 1, burst = 2 },
	NewsFact = { dir = "S2C" }, -- { list = { { k, t, n, a } } }: NewsPlan facts (fixed templates, safe names)
	-- lore step 10 (side quest chains; givers use ProximityPrompts, the server's own range check):
	-- SideQuestAct { act, chain bit }: 1 accept or resume (the Journal), 2 abandon (on hold at its step)
	SideQuestAct = { dir = "C2S", schema = { n(1, 2), n(1, 127) }, rate = 1, burst = 3 },
	-- the tracked chain's step, 2 Hz: { bit, step, steps, have, need, wait, left, target, area, scene, card }
	SideQuestState = { dir = "S2C" },
	SideQuestTalk = { dir = "S2C" }, -- { bit, kind, step }: fixed giver and step lines through GuideHud

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
	HeroKnock = { dir = "S2C" }, -- { x, y, z, time, wall? = { x, y, z, t } }: a knockback, pull or knockup on your own hero (wall: it broke through one there, t along the throw)
	-- WP4 (spec: Social > Rivalry, gap G8): the REMATCH ping, fixed buttons only. PvpRematch { act, userId }:
	-- 1 the loser pings their last winner (no id), 2 the winner accepts that loser's ping, 3 the winner says no
	PvpRematch = { dir = "C2S", schema = { n(1, 3), n(1, 2 ^ 52, true) }, rate = 0.5, burst = 3 },
	RematchAsk = { dir = "S2C" }, -- { from (user id), name (hero name), life }: "X wants a rematch" to the winner
	-- WP4 (gap G7): the favorite prompt, once per account after a first world boss win (no reward)
	FavoriteAsk = { dir = "S2C" }, -- the server asks this device to show Roblox's favorite prompt
	FavoriteShown = { dir = "C2S", schema = {}, rate = 0.1, burst = 1 }, -- the device showed it: save the flag

	-- Creator, HQ, shops and passes (M9; spec: Hero.Create {side, classId, setId, look, colors, titleId,
	-- nounId} 1/10s, Hero.Select {slot} 1/5s). The look is one 128-byte LookCodec buffer.
	-- HeroCreate: look, side (1 hero, 2 villain), archetype (1-4), path in the archetype (1-5), title, noun,
	-- mobility (1-5, Move.mobilityOrder), weapon (a 12-byte WeaponRules look: id, style, finish, colours, ...),
	-- origin (1-5, Creator.origins; lore step 2)
	HeroCreate = {
		dir = "C2S",
		schema = {
			{ t = "buffer", len = { 128 } },
			n(1, 2),
			n(1, 4),
			n(1, 5),
			n(1, 64), -- title (Config.Creator.titles; the save holds 64)
			n(1, 64), -- noun
			n(1, 5),
			{ t = "buffer", len = { 12 }, optional = true },
			n(1, 16, true), -- origin (10 since 2026-11-18)
		},
		-- one save every 5 s with 3 quick retries (was 1 per 10 s, burst 2: a refused tap plus two retries were
		-- dropped with no answer, nate's "done button dont work sometimes", 2026-11-18)
		rate = 0.2,
		burst = 3,
	},
	HeroSelect = { dir = "C2S", schema = { n(1, 4) }, rate = 0.2, burst = 2 }, -- a character slot (new = create)
	CreatorOpen = { dir = "S2C" }, -- { mode = "create" | "edit" | "first", side, classIdx, hq, origin }: open it
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
	HqRetire = { dir = "C2S", schema = {}, rate = 0.1, burst = 1 }, -- Legacy at the level cap (Hall of Legends)
	-- WP12: visit a friend's HQ (Shared.VisitRules, VisitService). HqVisitAsk: VISIT (the owner's user id);
	-- HqVisitAnswer: the owner's card (the asker's user id, 1 accept or 0 no); HqVisitLeave: LEAVE HQ or the
	-- exit; HqVisitKick: the owner shows a visitor out. HqVisitAsked ({ from, name, life }: the card) and
	-- HqVisitors ({ list = { { userId, name } }, visiting = { owner, name }? }) are S2C; the copy itself comes
	-- as an HqState with `visit` set. Fixed text only: no strings travel either way.
	HqVisitAsk = { dir = "C2S", schema = { n(1, 2 ^ 52) }, rate = 0.5, burst = 2 },
	HqVisitAnswer = { dir = "C2S", schema = { n(1, 2 ^ 52), n(0, 1) }, rate = 1, burst = 3 },
	HqVisitLeave = { dir = "C2S", schema = {}, rate = 0.5, burst = 2 },
	HqVisitKick = { dir = "C2S", schema = { n(1, 2 ^ 52) }, rate = 1, burst = 3 },
	HqVisitAsked = { dir = "S2C" },
	HqVisitors = { dir = "S2C" },
	-- WP12: the device's Roblox block list (StarterGui GetBlockedUserIds) so a block stops visit asks
	-- (GuardService.shuns); { 0 } means none. Only ever narrows what reaches this player.
	GuardBlocks = {
		dir = "C2S",
		schema = { { t = "intList", maxLen = 200, min = 0, max = 2 ^ 52 } },
		rate = 0.2,
		burst = 3,
	},
	GizmoBuy = { dir = "C2S", schema = { n(1, 511) }, rate = 2, burst = 3 }, -- a base style id, Credits only
	ShopBuy = { dir = "C2S", schema = { n(1, 64) }, rate = 1, burst = 3 }, -- an item (ShopRules.keys order)
	ShopResult = { dir = "S2C" }, -- { ok, key, kind, pieces, reason }: after a purchase lands (or not)
	ShopOffer = { dir = "S2C" }, -- { key }: the starter pack offer, once
	ShopDismiss = { dir = "C2S", schema = {}, rate = 1, burst = 2 },
	TintSet = { dir = "C2S", schema = { n(0, 15) }, rate = 1, burst = 3 }, -- an owned effect colour, 0 none
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
	-- H6: mentors. MentorOpen: ask for your mentor card; MentorPick: pick mentor n (the first pick anywhere,
	-- a change at a safehouse); MentorWear: wear mentor n's look (0 = none). MentorState: { k = card | pick |
	-- panel | assist, ... }
	MentorOpen = { dir = "C2S", schema = {}, rate = 1, burst = 3 },
	MentorPick = { dir = "C2S", schema = { n(1, 4) }, rate = 1, burst = 2 },
	MentorWear = { dir = "C2S", schema = { n(0, 4) }, rate = 1, burst = 2 },
	MentorState = { dir = "S2C" },
	-- H7: badges and titles. BadgeOpen: ask for the Badge Book; TitleSet: show title id (0 = your origin's);
	-- AccoladeWear: slot (1 aura, 2 trim), group index (0 = none). BadgeBook / BadgeEarned: S2C.
	BadgeOpen = { dir = "C2S", schema = {}, rate = 1, burst = 3 },
	TitleSet = { dir = "C2S", schema = { n(0, 65535) }, rate = 1, burst = 2 },
	AccoladeWear = { dir = "C2S", schema = { n(1, 2), n(0, 131) }, rate = 1, burst = 3 }, -- 100+n: pass trim n
	BadgeBook = { dir = "S2C" },
	BadgeEarned = { dir = "S2C" },
	-- The Rogues File (the Journal's ROGUES tab): RoguesOpen asks for the pages; RoguesFile = { bits, log };
	-- RoguesNew = { bit, gold } a page just filled (the stamp)
	RoguesOpen = { dir = "C2S", schema = {}, rate = 1, burst = 3 },
	RoguesFile = { dir = "S2C" },
	RoguesNew = { dir = "S2C" },
	-- H7: collections. CollectOpen: ask for the spots and finds; CollectScanner: buy the HQ Scanner (at HQ).
	CollectOpen = { dir = "C2S", schema = {}, rate = 1, burst = 3 },
	CollectScanner = { dir = "C2S", schema = {}, rate = 1, burst = 2 },
	CollectState = { dir = "S2C" },
	CollectFound = { dir = "S2C" },
	-- H7: costume contests. ContestEnter: step on (near the stage, in the call); ContestVote: user id, stars
	ContestOpen = { dir = "C2S", schema = {}, rate = 1, burst = 3 },
	ContestEnter = { dir = "C2S", schema = {}, rate = 1, burst = 2 },
	ContestVote = { dir = "C2S", schema = { n(1, 2 ^ 53), n(1, 5) }, rate = 4, burst = 8 },
	ContestState = { dir = "S2C" },
	-- H8: the Hero Pass and the weekly episode. PassOpen: ask for the pass and episode; PassClaim: tier,
	-- track (0 free, 1 paid); EpisodeSeen: the intro panels were shown; PassState / PassXp: S2C.
	PassOpen = { dir = "C2S", schema = {}, rate = 1, burst = 3 },
	PassClaim = { dir = "C2S", schema = { n(1, 40), n(0, 1) }, rate = 2, burst = 6 },
	EpisodeSeen = { dir = "C2S", schema = {}, rate = 1, burst = 2 },
	PassState = { dir = "S2C" },
	PassXp = { dir = "S2C" },
	-- H8: travel power styles. TravelStyleSet: mobility index (Config.Move.mobilityOrder), slot (0 plain)
	TravelStyleSet = { dir = "C2S", schema = { n(1, 5), n(0, 6) }, rate = 2, burst = 4 },
	-- WP2: the weekly boards. BoardOpen: board (Config.Boards.boards index), filter (0 all, 1 friends); only
	-- numbers go up, names come back from Roblox display names. BoardData: the screen's rows; BoardPlaza: the
	-- plaza board's top 10s (sent when they change); BoardReward: a weekly title earned.
	BoardOpen = { dir = "C2S", schema = { n(1, 8), n(0, 1) }, rate = 1, burst = 4 },
	BoardData = { dir = "S2C" },
	BoardPlaza = { dir = "S2C" },
	BoardReward = { dir = "S2C" },
	-- WP1: the daily streak and quests. DailyOpen: ask for the state; DailyClaim: take today's streak reward
	-- (once a day, the server decides); DailyState (the card, the track, the 3 quests) / DailyProgress (a quest
	-- moved or finished, a reward paid): S2C.
	DailyOpen = { dir = "C2S", schema = {}, rate = 1, burst = 3 },
	DailyClaim = { dir = "C2S", schema = {}, rate = 1, burst = 2 },
	DailyState = { dir = "S2C" },
	DailyProgress = { dir = "S2C" },
	-- WP10: the group piece and creator codes (Settings > REWARDS). PromoOpen: ask for the rows' state;
	-- PromoRedeem: one code from the box (upper-case letters and digits; the server matches it against the
	-- fixed list in Config.Promo only, and never sends it anywhere); PromoGroup: CHECK the group again.
	-- PromoState (the rows) / PromoResult ({ kind, reason, piece }: never the typed text): S2C.
	PromoOpen = { dir = "C2S", schema = {}, rate = 1, burst = 3 },
	PromoRedeem = { dir = "C2S", schema = { { t = "string", max = 20 } }, rate = 0.5, burst = 3 },
	PromoGroup = { dir = "C2S", schema = {}, rate = 0.2, burst = 2 },
	PromoState = { dir = "S2C" },
	PromoResult = { dir = "S2C" },
}

return Remotes
