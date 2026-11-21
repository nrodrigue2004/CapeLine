-- MoveGuard: samples every hero's position (spec: Anti-exploit > Speed and teleport, Flight).
-- * 30 Hz position history for the lag rewind in hit checks (PosHistory).
-- * 10 Hz speed check (MoveCheck) against the hero's style cap (x speed buffs) x 1.15. A fail pulls the hero
--   back to the last good spot (MoveCorrect), after one sample's wait for a grant still on its way. Only teleport-sized jumps count as strikes; 3 in 10 minutes kick with a
--   generic message. Nothing is banned automatically (Config.Safety).
-- * Boost drains stamina on the server too, so a client that never runs out still gets the cruise cap.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Status = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Status"))
local MoveMath = require(Shared:WaitForChild("MoveMath"))
local MoveCheck = require(Shared:WaitForChild("MoveCheck"))
local PosHistory = require(Shared:WaitForChild("PosHistory"))
local Travel = require(Shared:WaitForChild("Travel"))
local ClimbMath = require(Shared:WaitForChild("ClimbMath"))
local LabRules = require(Shared:WaitForChild("LabRules"))

local HeroService = require(script.Parent.HeroService)
local PerfMonitor = require(script.Parent.PerfMonitor)

local MoveGuard = {}

type Track = {
	check: MoveCheck.State,
	history: PosHistory.History,
	boosting: boolean,
	stamina: number,
	graceUntil: number,
	corrections: number,
	freeUntil: number?,
	drainAt: number, -- when the boost last drained (regen waits Config.Move.stamina.regenDelay after it)
}

local tracks: { [number]: Track } = {}

local function newTrack(pos: Vector3, now: number): Track
	return {
		check = MoveCheck.new(pos.X, pos.Y, pos.Z, now),
		history = PosHistory.new(Config.Combat.historyKeep),
		boosting = false,
		stamina = Config.Move.stamina.max,
		graceUntil = now + 1,
		corrections = 0,
		drainAt = -math.huge,
	}
end

local function trackFor(hero: any, pos: Vector3, now: number): Track
	local t = tracks[hero.id]
	if not t then
		t = newTrack(pos, now)
		tracks[hero.id] = t
	end
	return t
end

-- A legal jump (respawn, fast travel, mission pocket): accept the new spot
-- GuardService sets this: (player, kind) counts a strike (M8)
MoveGuard.strikeHook = nil :: ((Player, string) -> ())?

-- The check also expects the hero at the new spot for Safety.teleportKeep seconds, so a device whose lag
-- outlasts the 1 s grace is not pulled back to where it came from when the move finally lands there.
function MoveGuard.reset(hero: any)
	if HeroService.byId(hero.id) ~= hero then
		return -- left (or respawned as a new hero) while being moved: no track for a gone hero
	end
	local pos = HeroService.position(hero)
	if pos then
		local now = os.clock()
		local t = trackFor(hero, pos, now)
		MoveCheck.reset(t.check, pos.X, pos.Y, pos.Z, now)
		MoveCheck.expect(t.check, pos.X, pos.Y, pos.Z, now + Config.Safety.teleportKeep)
		t.graceUntil = now + 1
	end
end

-- A server-approved burst such as Dash Strike
function MoveGuard.grant(hero: any, distance: number)
	local t = tracks[hero.id]
	if t then
		MoveCheck.grant(t.check, distance, os.clock())
	end
end

-- Rewound position for hit checks (attacker lag, at most 150 ms)
function MoveGuard.rewound(hero: any, latency: number): Vector3?
	local t = tracks[hero.id]
	if t then
		local x, y, z = PosHistory.rewind(t.history, os.clock(), latency, Config.Combat.rewindMax)
		if x then
			return Vector3.new(x, y :: number, z :: number)
		end
	end
	return HeroService.position(hero)
end

-- Studs per second over the last 0.2 s (Speedster Momentum)
function MoveGuard.speed(hero: any): number
	local t = tracks[hero.id]
	if not t then
		return 0
	end
	local now = os.clock()
	local x1, y1, z1 = PosHistory.at(t.history, now)
	local x0, y0, z0 = PosHistory.at(t.history, now - 0.2)
	if not x1 or not x0 then
		return 0
	end
	local dx, dy, dz = x1 - x0, (y1 :: number) - (y0 :: number), (z1 :: number) - (z0 :: number)
	return math.sqrt(dx * dx + dy * dy + dz * dz) / 0.2
end

-- The hero's top speed over the last `window` seconds, in 0.1 s steps (ImpactService: a ram claimed at a wall
-- must be no faster than the hero really moved just before it, while the wall has already stopped it)
function MoveGuard.peakSpeed(hero: any, window: number): number
	local t = tracks[hero.id]
	if not t then
		return 0
	end
	local now = os.clock()
	local top = 0
	local steps = math.max(1, math.floor(window / 0.1 + 0.5))
	for k = 0, steps - 1 do
		local x1, y1, z1 = PosHistory.at(t.history, now - k * 0.1)
		local x0, y0, z0 = PosHistory.at(t.history, now - (k + 1) * 0.1)
		if x1 and x0 then
			local dx, dy, dz = x1 - x0, (y1 :: number) - (y0 :: number), (z1 :: number) - (z0 :: number)
			top = math.max(top, math.sqrt(dx * dx + dy * dy + dz * dz) / 0.1)
		end
	end
	return top
end

-- How far the hero has dropped from the highest point of the last `window` seconds (the ground pound needs
-- a real fall, so a client cannot pound on flat ground)
function MoveGuard.dropped(hero: any, window: number): number
	local t = tracks[hero.id]
	if not t then
		return 0
	end
	local now = os.clock()
	local _, y1 = PosHistory.at(t.history, now)
	if not y1 then
		return 0
	end
	local top = y1 :: number
	for k = 1, 10 do
		local _, y = PosHistory.at(t.history, now - window * k / 10)
		if y and (y :: number) > top then
			top = y :: number
		end
	end
	return top - (y1 :: number)
end

-- Zero G (Weightless capstone): boosting costs no stamina for a while
function MoveGuard.freeStamina(hero: any, untilT: number)
	local t = tracks[hero.id]
	if t then
		t.freeUntil = untilT
	end
end

function MoveGuard.stamina(hero: any): number
	local t = tracks[hero.id]
	return if t then t.stamina else Config.Move.stamina.max
end

-- Is the hero boosting now (the server's own mirror of it)?
function MoveGuard.boosting(hero: any): boolean
	local t = tracks[hero.id]
	return t ~= nil and t.boosting
end

-- The mobility moves (MoveActService): a cost taken off the stamina mirror (Phase, Blazing Ram) or a refill
-- (Slipstream); the device does the same sum on its own copy
function MoveGuard.spend(hero: any, amount: number)
	local t = tracks[hero.id]
	if t then
		local cap = HeroService.moveConfig(hero).stamina.max
		t.stamina = math.clamp(t.stamina - amount, 0, cap)
		if amount > 0 then
			t.drainAt = os.clock()
		end
		if t.stamina <= 0 then
			t.boosting = false
		end
	end
end

local function correct(hero: any, t: Track)
	local player = hero.player
	local root = HeroService.rootPart(hero)
	if not player or not root then
		return
	end
	local c = t.check
	local pos = Vector3.new(c.x, c.y, c.z)
	t.corrections += 1
	root.AssemblyLinearVelocity = Vector3.zero
	root.CFrame = CFrame.new(pos) * root.CFrame.Rotation
	Net.fire("MoveCorrect", player, pos)
end

function MoveGuard.init()
	-- looks only (HeroAnimator poses the hero on other devices); the speed checks never trust it
	Net.on("MoveMode", function(player, mode: number)
		player:SetAttribute("Move", mode)
	end)
	-- the Swing's line, for other devices to draw (looks only): a Swing hero's anchor within the line's reach
	Net.on("MoveLine", function(player, at: Vector3)
		local hero = HeroService.get(player)
		local root = hero and HeroService.rootPart(hero)
		local ok = hero ~= nil
			and root ~= nil
			and hero.mobility == "swing"
			and at.Magnitude > 1e-3
			and at == at -- not NaN
			and (at - root.Position).Magnitude
				<= HeroService.moveConfig(hero).mobility.swing.up.range * 1.5
		player:SetAttribute("SwingAt", if ok then at else nil)
	end)
	-- move-2: an Acrobat's flip dodges for its i-frames, timed on the server's own clock (the cooldown with 15% slack
	-- for lag); a stunned, Downed or other-pick hero gets nothing. The flip's burst sits inside the Acrobat's cap,
	-- and the grant covers a late packet so it never pulls back
	Net.on("MoveFlip", function(player)
		local hero = HeroService.get(player)
		if
			not hero
			or not hero.alive
			or hero.downed
			or hero.mobility ~= "acrobat"
			or HeroService.disabled(hero)
		then
			return
		end
		local cfg = HeroService.moveConfig(hero)
		local now = os.clock()
		local ok, untilT = ClimbMath.flipOk(cfg, hero.flipAt or -math.huge, now, 0.85)
		if not ok then
			return
		end
		hero.flipAt = now
		hero.dodgeUntil = untilT
		local f = cfg.mobility.acrobat.flip
		MoveGuard.grant(hero, f.speed * f.time + 4)
	end)
	HeroService.Dodged:Connect(function(hero)
		if hero.player then
			Net.fire("MoveDodged", hero.player)
		end
	end)
	Net.on("MoveBoost", function(player, on: boolean)
		local hero = HeroService.get(player)
		if hero then
			local t = tracks[hero.id]
			if t then
				t.boosting = on
					and hero.styles.flight == true
					and t.stamina >= HeroService.moveConfig(hero).stamina.boostMin
			end
		end
	end)
	HeroService.Spawned:Connect(function(hero)
		tracks[hero.id] = nil
		if hero.player then
			hero.player:SetAttribute("SwingAt", nil) -- a new body has no line out
		end
		task.defer(MoveGuard.reset, hero)
	end)
	HeroService.Removed:Connect(function(hero)
		tracks[hero.id] = nil
	end)

	local histAcc, checkAcc = 0, 0
	local histStep = 1 / Config.Combat.historyRate
	local checkStep = 1 / Config.Safety.sampleRate
	RunService.Heartbeat:Connect(FrameProf.wrap("MoveGuard", function(dt)
		local t0 = os.clock()
		histAcc += dt
		checkAcc += dt
		local now = os.clock()
		if histAcc >= histStep then
			histAcc = 0
			for _, hero in HeroService.all() do
				local pos = HeroService.position(hero)
				if pos then
					local t = trackFor(hero, pos, now)
					PosHistory.push(t.history, now, pos.X, pos.Y, pos.Z)
				end
			end
		end
		if checkAcc >= checkStep then
			local step = checkAcc
			checkAcc = 0
			for _, hero in HeroService.all() do
				local pos = HeroService.position(hero)
				if pos and hero.player and (hero.alive or hero.downed) then -- a Downed crawl is checked too
					local t = trackFor(hero, pos, now)
					-- side-content: the hero's own Config.Move (its trained mobility ranks), as on its device
					local moveCfg = HeroService.moveConfig(hero)
					-- server stamina mirror
					local free = (t.freeUntil ~= nil and now < (t.freeUntil :: number))
						or LabRules.freeStamina(hero.lab) -- Studio's Test Lab: infinite stamina
					local drain = t.boosting and not free
					t.stamina = MoveMath.staminaStep(moveCfg, t.stamina, true, drain, step, now - t.drainAt)
					if drain then
						t.drainAt = now
					end
					if t.stamina <= 0 then
						t.boosting = false
					end
					-- a fast-travel flight (gap polish 2026-11-19): free while the body stays on the trip's arc;
					-- off it the normal check runs and pulls the hero back (BeaconService sets travelRoute)
					local route = hero.travelRoute
					local onRoute = route ~= nil
						and Travel.routeGap(
								route.from.X,
								route.from.Y,
								route.from.Z,
								route.to.X,
								route.to.Y,
								route.to.Z,
								pos.X,
								pos.Y,
								pos.Z
							)
							<= Config.World.beacon.routeSlack
					if now < t.graceUntil or onRoute then
						MoveCheck.reset(t.check, pos.X, pos.Y, pos.Z, now)
					else
						-- travel powers: a ride's own speed; Weightless lets anyone fly for its time; speed buffs
						-- (and a class's run bonus) scale the cap as they scale the client's run
						local class = Config.Classes[hero.classId]
						local cap = MoveMath.guardCap(moveCfg, hero.styles, t.boosting, {
							ride = Status.value(hero.status, "ride", now, 0),
							zeroG = Status.has(hero.status, "zeroG", now),
							speedBuff = Status.value(hero.status, "speed", now, 0),
							classSpeed = class and class.moveSpeed or 0,
							slip = Status.value(hero.status, "slip", now, 0), -- Slipstream (MoveActService)
						})
						local ok, strike, wait =
							MoveCheck.sample(t.check, pos.X, pos.Y, pos.Z, now, cap, moveCfg, Config.Safety)
						if not ok and not wait then
							correct(hero, t)
							if strike then
								warn(string.format("[MoveGuard] strike for %s (%d)", hero.name, hero.id))
								if MoveGuard.strikeHook then
									-- GuardService (M8) counts every kind of strike together
									MoveGuard.strikeHook(hero.player :: Player, "speed")
								else
									local kick = MoveCheck.addStrike(t.check, now, Config.Safety)
									if kick and not RunService:IsStudio() then
										(hero.player :: Player):Kick("Connection problem. Please rejoin.")
									end
								end
							end
						end
					end
				end
			end
		end
		PerfMonitor.add("move", (os.clock() - t0) * 1000)
	end))
	Players.PlayerRemoving:Connect(function(player)
		tracks[player.UserId] = nil
	end)
end

return MoveGuard
