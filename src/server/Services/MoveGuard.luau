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

function MoveGuard.reset(hero: any)
	local pos = HeroService.position(hero)
	if pos then
		local now = os.clock()
		local t = trackFor(hero, pos, now)
		MoveCheck.reset(t.check, pos.X, pos.Y, pos.Z, now)
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
	Net.on("MoveBoost", function(player, on: boolean)
		local hero = HeroService.get(player)
		if hero then
			local t = tracks[hero.id]
			if t then
				t.boosting = on and hero.styles.flight == true and t.stamina >= Config.Move.stamina.boostMin
			end
		end
	end)
	HeroService.Spawned:Connect(function(hero)
		tracks[hero.id] = nil
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
					-- server stamina mirror
					local free = t.freeUntil ~= nil and now < (t.freeUntil :: number)
					t.stamina =
						MoveMath.staminaStep(Config.Move, t.stamina, true, t.boosting and not free, step)
					if t.stamina <= 0 then
						t.boosting = false
					end
					if now < t.graceUntil then
						MoveCheck.reset(t.check, pos.X, pos.Y, pos.Z, now)
					else
						-- travel powers: a ride's own speed; Weightless lets anyone fly for its time; speed buffs
						-- (and a class's run bonus) scale the cap as they scale the client's run
						local class = Config.Classes[hero.classId]
						local cap = MoveMath.guardCap(Config.Move, hero.styles, t.boosting, {
							ride = Status.value(hero.status, "ride", now, 0),
							zeroG = Status.has(hero.status, "zeroG", now),
							speedBuff = Status.value(hero.status, "speed", now, 0),
							classSpeed = class and class.moveSpeed or 0,
						})
						local ok, strike, wait = MoveCheck.sample(
							t.check,
							pos.X,
							pos.Y,
							pos.Z,
							now,
							cap,
							Config.Move,
							Config.Safety
						)
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
