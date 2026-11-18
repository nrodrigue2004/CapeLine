-- CombatClient: fires abilities with client prediction (spec: Hit resolution). Effects play at once; the
-- server confirms hits in CombatResult and only then do damage numbers and hit flashes show. The client
-- sends only what it wants (ability, aim, a target hint and a sequence number), never damage.
-- Aim: the mouse on PC; on phones and gamepads the screen centre with auto-aim that snaps to the nearest
-- enemy within 25 degrees and 60 studs (spec: Touch flight). Cloaked Sneak Bots are not auto-aimed.
-- Predicted on the spot: bolts, chains, dashes, cones, slashes and punches, novas (and the Thunder Drop
-- dive), lines, buffs, the Meteor Leap arc and windup glows. Fields, beams, throws, walls, ramps, landings,
-- echoes and combos are drawn when the server's result arrives (one 10 Hz batch later).
-- M8: when you are flagged, other flagged players can be auto-aimed (their PvpId is the hint); you cannot
-- cast while stunned, lifted or Downed; Focus counts at its PvP quarter while flagged (as on the server).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Cooldowns = require(Shared:WaitForChild("Cooldowns"))
local AbilityRules = require(Shared:WaitForChild("AbilityRules"))
local ChargeRules = require(Shared:WaitForChild("ChargeRules"))
local WeaponRules = require(Shared:WaitForChild("WeaponRules"))
local EnemySim = require(Shared:WaitForChild("EnemySim"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local InputController = require(script.Parent.InputController)
local MoveController = require(script.Parent.MoveController)
local CameraController = require(script.Parent.CameraController)
local CinemaClient = require(script.Parent.CinemaClient) -- lore step 7: a hit ends a device-started scene
local AudioController = require(script.Parent.AudioController)
local EnemyRenderer = require(script.Parent.EnemyRenderer)
local PvpClient = require(script.Parent.PvpClient)
local HeroAnimator = require(script.Parent.HeroAnimator)
local State = require(script.Parent.Parent.State)
local CombatFx = require(script.Parent.Parent.Fx.CombatFx)
local Juice = require(script.Parent.Parent.Fx.Juice)
local AimPreview = require(script.Parent.Parent.Fx.AimPreview)
local FxLib = require(script.Parent.Parent.Fx.FxLib)

-- The juice sound for a cast by its slot (basic, super, or any skill)
local function castSound(slot: string?): string
	return if slot == "basic" then "basic" elseif slot == "super" then "super" else "cast"
end

local A = Config.Abilities
local C = Config.Combat
local player = Players.LocalPlayer

local CombatClient = {}
CombatClient.HitConfirm = Signal.new() -- (crit)
CombatClient.Cast = Signal.new() -- (abilityId)
-- lore step 7: a blow that may be a finisher: ("die", typeId, pos, byUserId, enemyId) or ("unmask", 0, pos,
-- byUserId, enemyId); FinisherFx decides (elites and fakes only)
CombatClient.Finish = Signal.new()
-- H1: BlockClient sets this (no casting while Block is held)
CombatClient.blocked = nil :: (() -> boolean)?

local book = Cooldowns.new()
local recast: AbilityRules.RecastState = {}
local combo = { at = 0, step = 0 }
local startHold: (string, string) -> ()
local releaseHold: () -> ()
local updateHold: () -> ()
local seq = 0
local channel: { seq: number, id: string, untilT: number }? = nil
local CHEST = Vector3.new(0, 1.5, 0)

-- Result kinds (CombatService.KIND)
local K = { CAST = 1, WINDUP = 2, TICK = 3, LAND = 4, ECHO = 5, END = 6, COMBO = 7, RIPOSTE = 8, CLASH = 9 }
-- CombatEvents kinds (EnemyService)
local SHOT, HERO_HIT, DIE, WARN, SLAM, SWING, BLOCKED = 1, 2, 3, 4, 5, 6, 7
-- the nine newer robot types (EnemyService.AIM ... BOOM; the robots' own flags are EnemySim.EXTRA)
local AIM, RALLY, LOB, ZONE, MEND, REVEAL, BOOM = 8, 9, 10, 11, 12, 13, 14
-- the famous fakes and the evil twin (lore step 4): a dive, charge or dash; a face cracking
local DASH, UNMASK = 15, 16
local LUNGE = 17 -- WP6: a Sneak Bot winds up its lunge
local PATH_SHOT = 4 -- shot style 4: a power path's shot (CombatFx.pathShot)
local HOOKED = EnemySim.EXTRA.hooked

-- While robot e's EXTRA bit holds (after a short grace for the next Enemy.Delta): a stun breaks a Sniper's
-- aim and a Medic's beam on the server, and these let the client's laser and beam end with them
local function holds(e: number, bit: number): () -> boolean
	local t0 = os.clock()
	return function()
		return os.clock() - t0 < 0.3 or bit32.band(EnemyRenderer.extra(e), bit) ~= 0
	end
end

-- The same for a robot's windup flag (WP6: an interrupt cuts a Sneak Bot's lunge wind-up, and its lane goes)
local WINDUP = EnemySim.WINDUP_BIT
local function windingUp(e: number): () -> boolean
	local t0 = os.clock()
	return function()
		return os.clock() - t0 < 0.3 or bit32.band(EnemyRenderer.flags(e), WINDUP) ~= 0
	end
end

local PREDICTED =
	{ bolt = true, chain = true, dash = true, cone = true, arc = true, nova = true, line = true, buff = true }

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function skipList(): { Instance }
	local skip = {}
	for _, name in { "Fx", "Enemies", "MoveFx", "LoadBots", "AbilityParts", "HqDecor" } do
		local inst = Workspace:FindFirstChild(name)
		if inst then
			table.insert(skip, inst)
		end
	end
	if player.Character then
		table.insert(skip, player.Character)
	end
	return skip
end

-- 0 when ready, 1 right after use (HUD sweeps)
function CombatClient.cooldownFraction(id: string): number
	return Cooldowns.fraction(book, id, os.clock())
end

function CombatClient.cooldownLeft(id: string): number
	return Cooldowns.left(book, id, os.clock())
end

local function rangeOf(eff: any): number
	if
		eff.slot == "basic"
		and eff.shape == "bolt"
		and State.hero.classId == "Elemental"
		and not eff.weapon
	then
		return math.max(eff.range, Config.Classes.Elemental.basicRange)
	end
	return eff.range or 10
end

-- Extra aim targets that are not robots or players (the HQ's training dummies): fn returns { {id, pos} }
local targetSources: { () -> { { id: number, pos: Vector3 } } } = {}
function CombatClient.addTargetSource(fn: () -> { { id: number, pos: Vector3 } })
	table.insert(targetSources, fn)
end

local function sourcePosition(id: number): Vector3?
	for _, source in targetSources do
		for _, t in source() do
			if t.id == id then
				return t.pos
			end
		end
	end
	return nil
end

-- Pick the aim point and the target hint for an ability
local function aim(range: number, origin: Vector3): (Vector3, number, Vector3?)
	local ray = InputController.aimRay()
	local touchAim = InputController.device == "gamepad"
		or (InputController.device == "touch" and InputController.autoAim)
	local slack = if touchAim then Config.Move.touch.autoAimAngle else 6
	local maxDist = if touchAim then math.min(math.max(range, 12), Config.Move.touch.autoAimRange) else range
	local bestId, bestAng, bestPos = 0, slack, nil
	local function consider(id: number, pos: Vector3)
		local toEnemy = pos - ray.Origin
		local fromHero = (pos - origin).Magnitude
		if fromHero <= maxDist + 3 and toEnemy.Magnitude > 1 then
			local ang = math.deg(math.acos(math.clamp(toEnemy.Unit:Dot(ray.Direction.Unit), -1, 1)))
			if ang < bestAng then
				bestId, bestAng, bestPos = id, ang, pos
			end
		end
	end
	for id, pos in EnemyRenderer.each() do
		consider(id, pos)
	end
	for _, t in PvpClient.targets() do
		consider(t.id, t.pos)
	end
	for _, source in targetSources do
		for _, t in source() do
			consider(t.id, t.pos)
		end
	end
	if bestPos then
		return bestPos, bestId, bestPos
	end
	rayParams.FilterDescendantsInstances = skipList()
	local hit = Workspace:Raycast(ray.Origin, ray.Direction.Unit * 400, rayParams)
	local point = if hit then hit.Position else ray.Origin + ray.Direction.Unit * 400
	return point, 0, nil
end

-- H3: ThrowClient aims a throw the same way (auto-aim on pads and phones, the crosshair on PC)
CombatClient.aimAt = aim

local function rayDist(from: Vector3, dir: Vector3, max: number): number
	rayParams.FilterDescendantsInstances = skipList()
	local hit = Workspace:Raycast(from, dir * max, rayParams)
	return if hit then (hit.Position - from).Magnitude else max
end

local function hitPause(time: number)
	if CameraController.reduceMotion then
		return
	end
	HeroAnimator.freeze(time)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local tracks = animator:GetPlayingAnimationTracks()
	local speeds = {}
	for i, t in tracks do
		speeds[i] = t.Speed
		t:AdjustSpeed(0)
	end
	task.delay(time, function()
		for i, t in tracks do
			if t.IsPlaying then
				t:AdjustSpeed(speeds[i] or 1)
			end
		end
	end)
end

-- The slot in what is held now (the power's loadout, or the weapon's moves while key 2 holds it)
local function slotOf(id: string): string?
	return WeaponRules.slotIn(State.kit(), id)
end

-- Hold the power (1) or the weapon (2). The swap shows at once here; the server flips its own copy too.
function CombatClient.hold(which: number)
	local held = if which == 2 then "weapon" else "power"
	if State.hero.held == held then
		return
	end
	State.hero.held = held
	combo.at, combo.step = 0, 0
	channel = nil
	Net.send("WeaponHold", which)
	Juice.fire("ui", nil, { mine = true })
	State.Changed:Fire()
end

local function myChest(): Vector3?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root and root.Position + CHEST
end

-- charge: how far a held skill charged (0 to 1, ChargeRules.level); the server caps it by its own timing
function CombatClient.fire(id: string, charge: number?): boolean
	local row = A.list[id]
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not row or not root or not hum or hum.Health <= 0 then
		return false
	end
	local cc = State.status.cc
	local now0 = os.clock()
	for _, kind in { "stun", "knockup", "float" } do
		if cc[kind] and now0 < cc[kind].untilT then
			return false
		end
	end
	if PvpClient.downed() or (CombatClient.blocked and CombatClient.blocked()) then
		return false -- H1: no casting while blocking
	end
	local slot = slotOf(id)
	if not slot then
		return false
	end
	local now = os.clock()
	if channel and channel.id == id and now < channel.untilT then
		-- pressing a channel again stops it
		Net.send("CombatCancel", channel.seq)
		channel = nil
		return false
	end
	if not Cooldowns.ready(book, id, now, 0) or AbilityRules.blocked(recast, id, now) then
		return false
	end
	local eff = State.effective(id)
	local chargeLevel = if charge and ChargeRules.chargeable(row) then charge else 0
	ChargeRules.apply(C, eff, chargeLevel)
	local awake = State.awakened()
	local origin = root.Position + CHEST
	local range = rangeOf(eff)
	local point, hint, targetPos = aim(range, origin)
	local dir = point - origin
	if dir.Magnitude < 0.5 then
		dir = Workspace.CurrentCamera.CFrame.LookVector
	end
	dir = dir.Unit
	local full = AbilityRules.cooldown(Config, Formulas, eff, {
		classId = State.hero.classId,
		focus = (State.hero.stats and State.hero.stats.Focus or 0)
			* (if PvpClient.flagged() then Config.Pvp.minorScale else 1),
		attackSpeed = State.buff("attackSpeed"),
		awakened = awake,
	})
	Cooldowns.start(book, id, now, AbilityRules.afterUse(recast, id, eff, now, full))
	seq += 1
	channel = nil
	local style = State.hero.fxStyle
	local color = CombatFx.colorOf(eff.set, player.UserId)
	if slot == "super" and awake then
		color = color:Lerp(Color3.fromRGB(255, 235, 120), 0.35)
	end
	if slot == "super" then
		CameraController.orbit(if seq % 2 == 0 then 1 else -1) -- lore step 7: a small orbit on supers
	end
	local shape = eff.shape
	local step = 1
	if eff.hits then
		step = AbilityRules.comboStep(combo.at, combo.step, now, #eff.hits)
		combo.at, combo.step = now, step
	end

	-- the hero's own pose at once (others see it when the server's result reaches them)
	if eff.cast and eff.cast > 0 then
		HeroAnimator.windup(player, eff.cast)
	else
		HeroAnimator.cast(player, row, step)
	end
	if eff.cast and eff.cast > 0 then
		CombatFx.windup(myChest, eff.cast, style, color, eff.set)
	elseif shape == "bolt" and not eff.channel then
		local to = targetPos or (origin + dir * math.min(range, (point - origin).Magnitude))
		CombatFx.bolt(origin, to, style, color, eff.set)
	elseif shape == "bolt" and eff.channel then
		local tid = hint
		channel = { seq = seq, id = id, untilT = now + eff.channel * (eff.tick or 0.25) }
		if tid > 0 then
			CombatFx.beamHold(myChest, function()
				local c = channel
				if not c or c.id ~= id then
					return nil
				end
				return EnemyRenderer.position(tid) or PvpClient.position(tid) or sourcePosition(tid)
			end, eff.channel * (eff.tick or 0.25), style, color, eff.set)
		end
	elseif shape == "chain" then
		CombatFx.chain(
			{ origin, targetPos or (origin + dir * math.min(range, (point - origin).Magnitude)) },
			style,
			color,
			eff.set
		)
	elseif shape == "dash" then
		local d = math.max(0, rayDist(origin, dir, eff.range) - 3)
		CombatFx.dash(origin, origin + dir * d, style, color, eff.set)
		MoveController.dash(dir, d, eff.time or 0.18)
		CameraController.punch(0.05)
		CameraController.lean(dir) -- lore step 7: the camera leans into the dash
	elseif shape == "cone" then
		CombatFx.cone(origin, dir, eff.range, eff.cone or 40, style, color, eff.set)
	elseif shape == "arc" then
		CombatFx.arc(
			origin,
			dir,
			eff.range,
			eff.cone or 90,
			style,
			color,
			step,
			(eff.set == "Blade" or eff.sword == true),
			id == "RisingBlade",
			eff.set
		)
		if eff.channel then
			channel = { seq = seq, id = id, untilT = now + eff.channel * (eff.tick or 0.15) }
			CombatFx.cast(eff, style, { o = origin, d = dir, step = step, a = player.UserId })
		end
		if step == 3 and style ~= "Anime" then
			CombatFx.word(origin + dir * eff.range, eff.set, color, false)
		end
	elseif shape == "nova" then
		if eff.slam then
			local down = rayDist(root.Position, Vector3.new(0, -1, 0), 300)
			local ground = root.Position - Vector3.new(0, math.max(0, down - 3), 0)
			if down > 6 then
				MoveController.dash(Vector3.new(0, -1, 0), down - 3, 0.2)
			end
			task.delay(if down > 6 then 0.2 else 0, function()
				CombatFx.nova(ground, eff.radius, style, color, true, eff.set)
				CameraController.shake(0.25, 0.6)
			end)
		else
			CombatFx.nova(origin, eff.radius, style, color, slot == "super", eff.set)
			CameraController.shake(0.1, 0.3)
		end
	elseif shape == "line" then
		local ld = dir
		if eff.ground then
			local f = Vector3.new(dir.X, 0, dir.Z)
			ld = if f.Magnitude > 1e-3 then f.Unit else Vector3.new(0, 0, -1)
		end
		local d = rayDist(origin, ld, eff.range)
		CombatFx.line(
			origin,
			origin + ld * d,
			eff.width or 5,
			style,
			color,
			eff.ground,
			(eff.set == "Blade" or eff.sword == true),
			eff.set
		)
		if slot == "super" then
			CameraController.shake(0.2, 0.5)
		end
	elseif shape == "leap" then
		local d = math.max(
			0,
			rayDist(
				origin + Vector3.new(0, 4, 0),
				Vector3.new(dir.X, math.max(dir.Y, -0.2), dir.Z).Unit,
				eff.range
			) - 3
		)
		local target = origin + Vector3.new(dir.X, 0, dir.Z).Unit * d
		local down = rayDist(target + Vector3.new(0, 20, 0), Vector3.new(0, -1, 0), 400)
		local land = target + Vector3.new(0, 20 - down + 3, 0)
		MoveController.arcTo(land, eff.time or 1.1, math.max(20, d * 0.35))
	elseif shape == "buff" then
		CombatFx.buffPop(origin, style, color)
		if eff.zeroG then
			MoveController.wantTakeOff = now + 1.5 -- Weightless: lift off once the server's zeroG buff lands
		end
	elseif shape == "ride" then
		MoveController.ride(eff.ride or "surf", eff.speed or 80, eff.duration or 4)
	elseif shape == "launch" then
		-- the same spot CastPlan gives the server: up, and forward along the flat aim until a wall
		local f = Vector3.new(dir.X, 0, dir.Z)
		f = if f.Magnitude > 1e-3 then f.Unit else Vector3.new(0, 0, -1)
		local fwd = math.min(eff.forward or 0, rayDist(origin, f, eff.forward or 0))
		local up = eff.up or 30
		local target = root.Position + f * math.max(0, fwd - 2) + Vector3.new(0, up, 0)
		MoveController.launchTo(target, eff.time or 0.5, math.max(4, up * 0.25))
	end
	-- every path's own look and sound (overhaul plan step 6): the flourish, the super's moment, the sound layer
	if slot ~= "basic" then
		CombatFx.castFlourish(eff, style, origin, dir, player.UserId)
		Juice.path(eff.set, if slot == "super" then "super" else "cast", origin)
	end
	if slot == "super" and PREDICTED[shape] and not (eff.cast and eff.cast > 0) and not eff.channel then
		CombatFx.superMoment(
			eff,
			style,
			{ o = origin, d = dir, c = origin, r = eff.radius, a = player.UserId, aw = awake }
		)
	end
	Juice.fire(castSound(slot), origin, { mine = true })
	Net.send("CombatUse", eff.num, dir, hint, seq, math.floor(chargeLevel * 100 + 0.5))
	CombatClient.Cast:Fire(id)
	return true
end

local function styleOf(userId: number): string
	if userId == player.UserId then
		return State.hero.fxStyle
	end
	local p = Players:GetPlayerByUserId(userId)
	return p and p:GetAttribute("FxStyle") or "Comic"
end

local function casterPos(userId: number, fallback: Vector3): () -> Vector3?
	return function()
		local p = Players:GetPlayerByUserId(userId)
		local char = p and p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		return if root then root.Position + CHEST else fallback
	end
end

local IMPACT = Config.Audio.impact
local lastThud = 0

local function drawHits(r: any, row: any, style: string, mine: boolean)
	local hits = r.h or {}
	local color = CombatFx.colorOf(row and row.set, r.a)
	local anyCrit = false
	local wordDone = false
	local tick = r.k == K.TICK
	local heavyRow = row ~= nil and (row.coeff or 0) >= C.heavyCoeff
	for _, h in hits do
		local pos = EnemyRenderer.position(h[1]) or Vector3.new(h[5], h[6], h[7])
		local crit = h[3] == 1
		anyCrit = anyCrit or crit
		EnemyRenderer.flash(h[1])
		if not tick or crit then
			CombatFx.impact(pos, crit, style, mine, color, row and row.set)
		end
		-- weighty hits (Config.Combat.weight): the robot freezes with you, then recoils; sparks spray out
		if not tick and h[4] ~= 1 then
			local big = crit or heavyRow
			local from = r.o or (Workspace.CurrentCamera and Workspace.CurrentCamera.CFrame.Position) or pos
			local dir = pos - from
			local freeze = if mine and not CameraController.reduceMotion
				then (if big then C.critPause else C.hitPause)
				else 0
			EnemyRenderer.impact(h[1], dir, big, freeze)
			CombatFx.hitSparks(pos, if dir.Magnitude > 1e-3 then dir.Unit else Vector3.yAxis, color, big)
		end
		CombatFx.number(pos + Vector3.new(0, 2, 0), h[2], crit, style, mine, h[8])
		if
			not wordDone
			and style ~= "Anime"
			and row
			and row.slot ~= "basic"
			and (r.k == K.CAST or r.k == K.LAND)
		then
			wordDone = true
			CombatFx.word(pos, row.set, color, row.slot == "super")
		end
	end
	if mine and anyCrit and #hits > 0 then
		Juice.fire(
			"crit",
			EnemyRenderer.position(hits[1][1]) or Vector3.new(hits[1][5], hits[1][6], hits[1][7])
		)
	end
	if mine and #hits > 0 then
		local heavy = heavyRow
		hitPause(if anyCrit or heavy then C.critPause else C.hitPause)
		if not tick then
			-- weighty hits: every hit you land shakes the camera and thuds; heavy and crit hits harder
			local W = C.weight
			local sh = if anyCrit or heavy then W.shakeHeavy else W.shake
			CameraController.shake(sh[1], sh[2])
			local now = os.clock()
			if now - lastThud >= W.thudGap then
				lastThud = now
				local at = EnemyRenderer.position(hits[1][1])
					or Vector3.new(hits[1][5], hits[1][6], hits[1][7])
				AudioController.playSpec(if anyCrit or heavy then IMPACT.heavy else IMPACT.hit, at)
				AudioController.playSpec(IMPACT.clank, at)
			end
		end
		-- the camera punch: a small FOV kick on crits and heavy hits, smaller on the rest (never on ticks)
		if r.k ~= K.TICK then
			CameraController.punch(if anyCrit or heavy then C.punchHeavy else C.punchHit)
			if anyCrit or heavy then
				CameraController.push() -- lore step 7: a gentle push in on heavy hits
			end
			Juice.path(
				row and row.set,
				"hit",
				EnemyRenderer.position(hits[1][1]) or Vector3.new(hits[1][5], hits[1][6], hits[1][7])
			)
		end
		CombatClient.HitConfirm:Fire(anyCrit)
	end
end

-- The prologue's quiet world (kid-proof, nate's playtest 2026-11-18; PrologueFx sets these): other heroes'
-- casts and the live world's robots' shots, blasts and hits are not drawn while the hero is in its own story
CombatClient.hideCaster = nil :: ((userId: number) -> boolean)?
CombatClient.hideEnemy = nil :: ((enemyId: number) -> boolean)?

local function onResult(list: { any })
	local hideCaster = CombatClient.hideCaster
	for _, r in list do
		if hideCaster and r.a ~= player.UserId and hideCaster(r.a) then
			continue
		end
		local mine = r.a == player.UserId
		local row = A.byNum[r.n]
		local style = styleOf(r.a)
		if row then
			local color = CombatFx.colorOf(row.set, r.a)
			local kind = r.k
			if kind == K.CAST and not mine then
				Juice.fire(castSound(row.slot), r.o, { mine = false, userId = r.a })
				if row.slot ~= "basic" then
					Juice.path(row.set, if row.slot == "super" then "super" else "cast", r.o)
				end
			end
			if kind == K.CAST and (not mine or (row.cast and row.cast > 0)) then
				HeroAnimator.cast(HeroAnimator.byUserId(r.a), row, r.m) -- yours after a windup, others' always
			end
			if kind == K.CAST then
				local predicted = mine
					and PREDICTED[row.shape]
					and not (row.cast and row.cast > 0)
					and not row.channel
				if mine and row.shape == "chain" then
					-- the jumps the client could not predict
					local points = {}
					for _, h in r.h or {} do
						table.insert(points, EnemyRenderer.position(h[1]) or Vector3.new(h[5], h[6], h[7]))
					end
					if #points > 1 then
						CombatFx.chain(points, style, color, row.set)
					end
				elseif not predicted and not (mine and row.shape == "leap") then
					local data: CombatFx.CastData = {
						o = r.o,
						d = r.d,
						e = r.e,
						c = r.c,
						r = r.r,
						t = r.t,
						step = r.m,
						aw = r.aw == 1,
						dur = r.dur,
						caster = casterPos(r.a, r.o),
						thrown = r.x ~= nil and r.x ~= 0,
					}
					if row.shape == "bolt" and row.channel and r.x then
						if mine then
							data = nil :: any -- already drawn from the prediction
						else
							local tid = r.x
							data.target = function()
								return EnemyRenderer.position(tid)
							end
						end
					end
					if row.shape == "field" and r.f == 1 then
						data.follow = casterPos(r.a, r.c or r.o)
					end
					if row.shape == "ride" then
						data.caster = casterPos(r.a, r.o)
					end
					if data then
						data.a = r.a
						CombatFx.cast(row, style, data)
					end
					-- Override: the area that follows the robot fighting for you
					if row.hfDur and r.x and r.c then
						local tid = r.x
						local c0 = r.c
						CombatFx.field(
							c0,
							r.r or row.hfRadius or 10,
							r.dur or row.hfDur,
							style,
							color,
							false,
							function()
								return EnemyRenderer.position(tid)
							end,
							false,
							row.set
						)
					end
					-- decoys (Tide Mirror, Holo Decoy, Spirit Swap): a copy the robots chase
					if row.decoy and r.c and row.shape ~= "place" then
						local c1 = r.c
						CombatFx.summon("holo", function()
							return c1
						end, r.dur or row.decoy, style, color)
					end
					if row.shape == "leap" and r.e then
						CombatFx.dash(r.o, r.e, style, color, row.set) -- others see the leap's streak
					end
				end
			elseif kind == K.WINDUP and not mine then
				CombatFx.windup(casterPos(r.a, r.o), r.dur or 1, style, color, row.set)
				HeroAnimator.windup(HeroAnimator.byUserId(r.a), r.dur or 1)
			elseif kind == K.LAND or kind == K.END then
				if r.c then
					CombatFx.area(row, style, r.c, r.r or 10, mine, r.a)
					if mine and row.slot == "super" then
						CameraController.shake(0.3, 0.8)
					end
				end
				if kind == K.LAND and r.dur then
					CombatFx.field(r.c, row.radius * 0.6, r.dur, style, color, false, nil, false, row.set)
				end
			elseif kind == K.ECHO then
				if r.c then
					CombatFx.nova(r.c, r.r or 10, style, color, false, row.set)
				elseif r.e then
					CombatFx.line(
						r.o,
						r.e,
						row.width or 6,
						style,
						color,
						row.ground,
						(row.set == "Blade" or row.sword == true),
						row.set
					)
				end
			elseif kind == K.CLASH then
				-- the collision freeze: both attackers stop for 0.3 s, a shockwave, a camera push
				if r.c then
					local inIt = mine or r.p == player.UserId
					CombatFx.nova(r.c, r.r or C.clash.radius, style, Color3.new(1, 1, 1), true)
					Juice.fire("clash", r.c, { mine = inIt })
					if inIt then
						hitPause(C.clash.freeze)
						CameraController.punch(C.clash.push)
					end
				end
			elseif kind == K.COMBO then
				local pair = A.combos.pairs[r.x or 0]
				if pair and r.c then
					Juice.fire("combo", r.c, { mine = mine or r.p == player.UserId })
					CombatFx.combo(
						r.c,
						r.r or pair.radius,
						pair.name,
						style,
						color,
						mine or r.p == player.UserId
					)
				end
			elseif kind == K.RIPOSTE then
				if r.e then
					CombatFx.dash(r.o, r.e, style, color)
					CombatFx.arc(r.e, r.d, 8, 140, style, color, 3, true)
				end
			end
		end
		drawHits(r, row, style, mine)
	end
end

-- A robot's piece now (its rifle tip, its hand), else its body plus `up`; nil once it is gone
local function robotAt(e: number, piece: string, up: Vector3): () -> Vector3?
	return function()
		local p = EnemyRenderer.point(e, piece)
		if p then
			return p
		end
		local pos = EnemyRenderer.position(e)
		return pos and pos + up
	end
end

-- A hero's chest by user id (players only: load-test bots have no Player, so they get nil)
local function heroChest(userId: number): () -> Vector3?
	return function()
		local p = Players:GetPlayerByUserId(userId)
		local char = p and p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		return root and root.Position + CHEST
	end
end

local function near(pos: Vector3, range: number): boolean
	local p = myChest()
	return p ~= nil and (p - pos).Magnitude < range
end

-- A famous fake's or an evil twin's attacks take its power path's look (lore step 4): the path, the effect
-- style to draw in (yours) and the colour (a twin's: the effect tint of the player it copies)
local function fakeLook(e: number): (string?, string, Color3)
	local set, userId = EnemyRenderer.pathOf(e)
	return set, styleOf(player.UserId), CombatFx.colorOf(set, userId)
end

local function onEvents(list: { any })
	local hideEnemy = CombatClient.hideEnemy
	for _, ev in list do
		local kind = ev[1]
		if hideEnemy then
			-- a hit on another hero, or anything a hidden robot does (BLOCKED carries no robot: the hero's own)
			if kind == HERO_HIT then
				if ev[2] ~= player.UserId then
					continue
				end
			elseif kind ~= BLOCKED and hideEnemy(ev[2]) then
				continue
			end
		end
		if kind == SHOT then
			local pos, vel = Vector3.new(ev[3], ev[4], ev[5]), Vector3.new(ev[6], ev[7], ev[8])
			if ev[11] == PATH_SHOT then
				local set, style, color = fakeLook(ev[2])
				CombatFx.pathShot(pos, vel, set, style, color)
				Juice.path(set, "cast", pos)
			elseif ev[9] and ev[9] ~= 0 then
				CombatFx.torpedo(pos, vel, ev[9], ev[10])
			elseif ev[11] == 3 then
				local e = ev[2]
				CombatFx.hook(robotAt(e, "Claw", Vector3.new(0, 1, 0)), pos, vel, function()
					return bit32.band(EnemyRenderer.extra(e), HOOKED) ~= 0
				end)
			else
				CombatFx.enemyShot(pos, vel, ev[11])
			end
		elseif kind == HERO_HIT then
			if ev[6] and ev[6] > 0 then
				HeroAnimator.hit(HeroAnimator.byUserId(ev[2]))
			end
			if ev[2] == player.UserId then
				if ev[6] and ev[6] > 0 then
					CinemaClient.hurt()
					CombatFx.hurt()
					CameraController.shake(0.12, 0.25)
				else
					local p = myChest()
					if p then
						CombatFx.blocked(p) -- shield or parry took it
					end
				end
			end
		elseif kind == DIE then
			local pos, metal, creature = EnemyRenderer.kill(ev[2])
			CombatClient.Finish:Fire("die", ev[6], pos or Vector3.new(ev[3], ev[4], ev[5]), ev[7], ev[2])
			if creature then
				-- a cartoon creature (lore step 11, chain 4) bursts into light, never into metal parts
				EnemyRenderer.lightBurst(pos or Vector3.new(ev[3], ev[4], ev[5]), metal)
			else
				CombatFx.burst(pos or Vector3.new(ev[3], ev[4], ev[5]), styleOf(ev[7]), metal)
			end
			Juice.fire("defeat", pos or Vector3.new(ev[3], ev[4], ev[5]), { mine = false })
			if ev[7] == player.UserId then
				CameraController.shake(0.08, 0.15)
			end
		elseif kind == WARN then
			CombatFx.warn(Vector3.new(ev[3], ev[4], ev[5]), ev[6], ev[7], ev[8], ev[9])
		elseif kind == SLAM then
			CombatFx.slam(Vector3.new(ev[3], ev[4], ev[5]), ev[6])
			local set, style, color = fakeLook(ev[2])
			if set then
				-- a fake's slam, shockwave or dive lands in its path's look (Colossus' quake, Light's prism...)
				CombatFx.nova(Vector3.new(ev[3], ev[4] + 1.2, ev[5]), ev[6], style, color, ev[6] >= 18, set)
				Juice.path(set, "hit", Vector3.new(ev[3], ev[4], ev[5]))
			end
			local p = myChest()
			if p and (p - Vector3.new(ev[3], ev[4], ev[5])).Magnitude < 40 then
				CameraController.shake(0.2, 0.4)
			end
		elseif kind == SWING then
			EnemyRenderer.swing(ev[2])
			local set, style, color = fakeLook(ev[2])
			local f = EnemyRenderer.facing(ev[2])
			if set and f then
				-- an evil twin's strike: its path's cut or blow in front of it
				CombatFx.arc(Vector3.new(ev[3], ev[4], ev[5]), f, 7, 110, style, color, 1, true, false, set)
			end
		elseif kind == BLOCKED then
			CombatFx.blocked(Vector3.new(ev[3], ev[4], ev[5]))
		elseif kind == AIM then
			-- {8, e, x,y,z, heroUserId, time, lock}: a Sniper's laser on a hero (bots have no body to aim at)
			local to = heroChest(ev[6])
			local aiming = holds(ev[2], EnemySim.EXTRA.aim)
			if to() then
				CombatFx.aimLaser(
					robotAt(ev[2], "RifleTip", Vector3.new(0, 1.5, 0)),
					to,
					ev[7],
					ev[8],
					aiming
				)
			end
			if ev[6] == player.UserId then
				CombatFx.targeted(ev[7], ev[8], aiming)
				task.delay(math.max(0, ev[7] - ev[8]), function()
					if aiming() then -- no lock sound for an aim a stun already broke
						Juice.fire("aimLock", nil, { mine = true })
					end
				end)
			end
		elseif kind == RALLY then
			local at = EnemyRenderer.position(ev[2]) or Vector3.new(ev[3], ev[4], ev[5])
			CombatFx.rally(at, ev[6])
			Juice.fire("rally", at, { mine = false })
		elseif kind == LOB then
			EnemyRenderer.swing(ev[2]) -- the throw
			CombatFx.lob(Vector3.new(ev[3], ev[4], ev[5]), Vector3.new(ev[6], ev[7], ev[8]), ev[9])
		elseif kind == ZONE then
			CombatFx.zone(Vector3.new(ev[3], ev[4], ev[5]), ev[6], ev[7])
		elseif kind == MEND then
			-- {12, e, x,y,z, patientId, time}: both ends follow their robots
			local patient = ev[6]
			CombatFx.mend(robotAt(ev[2], "RightHand", Vector3.new(0, 1, 0)), function()
				return EnemyRenderer.position(patient)
			end, ev[7], holds(ev[2], EnemySim.EXTRA.mend))
		elseif kind == REVEAL then
			local at = EnemyRenderer.position(ev[2]) or Vector3.new(ev[3], ev[4], ev[5])
			CombatFx.reveal(at)
			Juice.fire("reveal", at, { mine = false })
		elseif kind == BOOM then
			local at = Vector3.new(ev[3], ev[4], ev[5])
			local set, style, color = fakeLook(ev[2])
			if set then
				CombatFx.nova(at + Vector3.new(0, 1.2, 0), ev[6], style, color, false, set) -- a twin's blast
			else
				CombatFx.boom(at, ev[6])
			end
			Juice.fire("grenadeBoom", at, { mine = false })
			if near(at, Config.Fx.robots.boom.shake) then
				CameraController.shake(0.2, 0.45)
			end
		elseif kind == DASH then
			-- {15, e, x,y,z, tx,ty,tz}: a fake's dive, charge or dash, a streak in its path's look
			local set, style, color = fakeLook(ev[2])
			CombatFx.dash(
				Vector3.new(ev[3], ev[4], ev[5]),
				Vector3.new(ev[6], ev[7], ev[8]),
				style,
				color,
				set
			)
		elseif kind == LUNGE then
			-- {17, e, x,y,z, tx,ty,tz, time, width}: a Sneak Bot coils for its lunge; the red lane fills along the
			-- ground to the spot it will dash to (the robot telegraph: step out of it, or hit it with anything fast)
			local from = Vector3.new(ev[3], ev[4], ev[5])
			CombatFx.lane(from, Vector3.new(ev[6], ev[7], ev[8]), ev[10] or 3, ev[9] or 0.6, windingUp(ev[2]))
			Juice.fire("lungeWind", from, { mine = false })
		elseif kind == UNMASK then
			-- {16, e, x,y,z}: a famous fake's face cracks to show metal: sound, flash, and a short hit-stop
			-- and camera punch when it is near you
			local at = EnemyRenderer.position(ev[2]) or Vector3.new(ev[3], ev[4], ev[5])
			CombatClient.Finish:Fire("unmask", 0, at, ev[6], ev[2])
			local close = near(at, Config.Fx.fakes.unmaskNear)
			Juice.fire("unmask", at + Vector3.new(0, 2, 0), { mine = close, near = close })
			if close then
				hitPause(Config.Fx.fakes.unmaskPause)
				CameraController.punch(C.punchHeavy)
				CameraController.shake(0.15, 0.3)
			end
		end
	end
end

-- Hold to aim and charge (overhaul plan step 3; Config.Combat.charge, Shared.ChargeRules): a skill or super key
-- shows its aim while held (AimPreview) and casts on release; damaging skills also charge (the server times
-- the hold from CombatCharge). Pressing a running channel's key still stops it at once.
type Hold = { action: string, id: string, t0: number, charge: boolean, posed: boolean, full: boolean }
local holding: Hold? = nil

releaseHold = function()
	local h = holding
	holding = nil
	AimPreview.hide()
	MoveController.setScale("charge", nil)
	if not h then
		return
	end
	local level = if h.charge then ChargeRules.level(C, os.clock() - h.t0, A.list[h.id]) else 0
	CombatClient.fire(h.id, level)
end

startHold = function(action: string, id: string)
	local row = A.list[id]
	if not row or (CombatClient.blocked and CombatClient.blocked()) then
		return
	end
	if channel and channel.id == id and os.clock() < channel.untilT then
		CombatClient.fire(id) -- stops the channel
		return
	end
	if not ChargeRules.aimable(row) then
		CombatClient.fire(id)
		return
	end
	if holding then
		releaseHold() -- a second key: the first one goes off
	end
	local charge = ChargeRules.chargeable(row)
	holding = { action = action, id = id, t0 = os.clock(), charge = charge, posed = false, full = false }
	if charge then
		Net.send("CombatCharge", row.num)
	end
	if ChargeRules.power(row) then
		MoveController.setScale("charge", C.charge.powerSlow) -- H2: charging a charge-up power slows you
	end
end

updateHold = function()
	local h = holding
	if not h then
		return
	end
	local held = os.clock() - h.t0
	if held >= C.charge.maxHold then
		releaseHold()
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or held < 0.12 then
		return
	end
	local level = if h.charge then ChargeRules.level(C, held, A.list[h.id]) else 0
	local eff = ChargeRules.apply(C, State.effective(h.id), level)
	local origin = root.Position + CHEST
	local point = aim(rangeOf(eff), origin)
	local color = CombatFx.colorOf(eff.set, player.UserId)
	AimPreview.draw(
		eff,
		origin,
		root.Position - Vector3.new(0, 3, 0),
		point,
		color,
		level,
		State.hero.fxStyle
	)
	if h.charge and level > 0 and not h.posed then
		h.posed = true
		Juice.path(eff.set, "charge", origin)
		HeroAnimator.windup(player, C.charge.maxHold) -- the charging pose until release
	end
	if level >= 1 and not h.full then
		h.full = true
		FxLib.gather(origin, eff.set, color) -- fully charged
		if ChargeRules.power(A.list[h.id]) then
			Juice.fire("chargeFull", origin, { mine = true }) -- H2: the ping and flash; it breaks blocks now
		else
			Juice.fire("skillRank", origin, { mine = true })
		end
	end
end

-- H1: the server interrupted your charge or heavy wind-up: drop the hold, and the skill costs `cd`
function CombatClient.cancelHold(num: number, cd: number)
	local row = A.byNum[num]
	if not row then
		return
	end
	local h = holding
	if h and h.id == row.id then
		holding = nil
		AimPreview.hide()
		MoveController.setScale("charge", nil)
	end
	Cooldowns.start(book, row.id, os.clock(), cd)
end

-- What is held now (Hud's charge ring, H2): the ability id and its charge level (0 to 1), or nil
function CombatClient.holdState(): (string?, number, boolean)
	local h = holding
	if not h then
		return nil, 0, false
	end
	return h.id, if h.charge then ChargeRules.level(C, os.clock() - h.t0, A.list[h.id]) else 0, h.charge
end

function CombatClient.init()
	Net.listen("CombatResult", onResult)
	Net.listen("CombatEvents", onEvents)
	InputController.Pressed:Connect(function(action)
		local kit = State.kit()
		if action == "Basic" then
			if kit.basic then
				CombatClient.fire(kit.basic)
			end
		elseif action == "Super" then
			if kit.super then
				startHold(action, kit.super)
			end
		elseif action == "Awaken" then
			Net.send("Awaken")
		elseif action == "HoldPower" then
			CombatClient.hold(1)
		elseif action == "HoldWeapon" then
			CombatClient.hold(2)
		elseif action == "Swap" then
			CombatClient.hold(if State.hero.held == "weapon" then 1 else 2)
		else
			local n = string.match(action, "^Skill(%d)$")
			local i = n and tonumber(n) :: number
			local id = i and kit.skills[i]
			if i and id then
				if kit.locked[i] then
					local key = Config.Weapons.keys[i]
					State.Toast:Fire({
						id = "note",
						text = string.format("Mastery %d opens %s", Config.Weapons.mastery.skills[key], key),
					})
				else
					startHold(action, id)
				end
			end
		end
	end)
	InputController.Released:Connect(function(action)
		local h = holding
		if h and h.action == action then
			releaseHold()
		end
	end)
	RunService.Heartbeat:Connect(FrameProf.wrap("CombatClient", function()
		updateHold()
		if InputController.isDown("Basic") then
			local basic = State.kit().basic
			if basic then
				CombatClient.fire(basic) -- hold to keep firing at the basic's rate
			end
		end
	end))
	player.CharacterAdded:Connect(function()
		holding = nil
		AimPreview.hide()
		MoveController.setScale("charge", nil)
		Cooldowns.clear(book)
		table.clear(recast)
		channel = nil
	end)
	Net.listen("WeaponMastery", function(data)
		local w = WeaponRules.get(Config, data.id)
		local name = string.upper(if w then w.name else "Weapon")
		State.Toast:Fire({ id = "note", text = string.format("%s MASTERY %d", name, data.level) })
		for _, key in data.opened or {} do
			State.Toast:Fire({ id = "note", text = name .. ": " .. key .. " UNLOCKED" })
			Juice.fire("skillRank", nil, { mine = true })
		end
	end)
	Net.listen("CooldownCut", function(n: number, seconds: number)
		local row = Config.Abilities.byNum[n]
		if row then
			Cooldowns.reduce(book, row.id, seconds) -- Cooling Kill
		end
	end)
	State.Changed:Connect(function()
		-- a respec or a new loadout resets local cooldowns the server also cleared
		if State.hero.respecIn and State.hero.respecIn > Config.Abilities.respecCooldown - 2 then
			Cooldowns.clear(book)
		end
	end)
end

return CombatClient
