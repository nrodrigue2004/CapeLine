-- CombatService: server-authoritative hit resolution (spec: Hit resolution, Damage and stats formulas).
-- The client plays effects at once (prediction); the server checks the ability is equipped, off cooldown
-- (100 ms leeway), the hero is up, and finds targets from the attacker's position rewound by its lag (at most
-- 150 ms) with line of sight through the city. Damage is computed here only. Results go out in 10 Hz
-- batches to players within 150 studs. Clients never send damage, targets' positions or results.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Cooldowns = require(Shared:WaitForChild("Cooldowns"))
local HitQuery = require(Shared:WaitForChild("HitQuery"))

local HeroService = require(script.Parent.HeroService)
local MoveGuard = require(script.Parent.MoveGuard)
local EnemyService = require(script.Parent.EnemyService)
local PerfMonitor = require(script.Parent.PerfMonitor)

local CombatService = {}

local A = Config.Abilities
local C = Config.Combat
local CHEST = Vector3.new(0, 1.5, 0)

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Include

local function los(ox: number, oy: number, oz: number, tx: number, ty: number, tz: number): boolean
	local from = Vector3.new(ox, oy, oz)
	local dir = Vector3.new(tx, ty, tz) - from
	local hit = Workspace:Raycast(from, dir, losParams)
	return hit == nil or (hit.Position - from).Magnitude >= dir.Magnitude - 3
end

local function equipped(hero: any, id: string): boolean
	if hero.loadout.basic == id then
		return true
	end
	return table.find(hero.loadout.skills, id) ~= nil
end

local pending: { any } = {}

local function rollDamage(hero: any, ability: any): (number, boolean)
	local crit = false -- Precision comes from gear (M3); 0 Precision is 0% crit
	local chance = Formulas.critChance(Config, 0)
	if chance > 0 and math.random() < chance then
		crit = true
	end
	local dmg = Formulas.damage(Config, HeroService.power(hero), ability.coeff, hero.classId, crit, 0)
	-- Blaster passive Overcharge: every 5th hit deals +30%
	local class = Config.Classes[hero.classId]
	if class.passive.id == "Overcharge" then
		hero.hitCount += 1
		if hero.hitCount % class.passive.everyNth == 0 then
			dmg *= 1 + class.passive.bonus
			crit = true -- drawn as a crit so the pop reads
		end
	end
	return dmg, crit
end

-- Shared by players (CombatUse) and load bots. Returns true when the use was accepted.
function CombatService.use(
	hero: any,
	num: number,
	aim: Vector3,
	hint: number,
	seq: number,
	latency: number
): boolean
	local ability = A.byNum[num]
	if not ability or not ability.built or not hero.alive then
		return false
	end
	if not equipped(hero, ability.id) then
		return false
	end
	local now = os.clock()
	if not Cooldowns.ready(hero.cooldowns, ability.id, now, C.cooldownLeeway) then
		return false
	end
	if aim.Magnitude < 0.5 then
		return false
	end
	local dir = aim.Unit
	local root = MoveGuard.rewound(hero, latency)
	if not root then
		return false
	end
	local origin = root + CHEST
	local cands = EnemyService.candidates()
	local targets = {}
	local endPos = nil

	if ability.shape == "bolt" then
		local range = ability.range + C.reachSlack
		if hero.classId == "Blaster" and Config.Classes.Blaster.basicRange then
			range = math.max(range, Config.Classes.Blaster.basicRange + C.reachSlack)
		end
		local t = HitQuery.bolt(
			origin.X,
			origin.Y,
			origin.Z,
			dir.X,
			dir.Y,
			dir.Z,
			range,
			ability.radius,
			hint,
			C.aimSlack,
			cands,
			los
		)
		if t then
			table.insert(targets, t)
		end
	elseif ability.shape == "chain" then
		local range = ability.range + C.reachSlack
		local first = HitQuery.bolt(
			origin.X,
			origin.Y,
			origin.Z,
			dir.X,
			dir.Y,
			dir.Z,
			range,
			4,
			hint,
			C.aimSlack,
			cands,
			los
		) or HitQuery.cone(
			origin.X,
			origin.Y,
			origin.Z,
			dir.X,
			dir.Y,
			dir.Z,
			range,
			ability.cone,
			cands,
			los
		)
		if first then
			targets = HitQuery.chain(first, cands, ability.targets, ability.jump, los)
		end
	elseif ability.shape == "dash" then
		local wanted = dir * ability.range
		local hit = Workspace:Raycast(origin, wanted, losParams)
		local dist = if hit then math.max(0, (hit.Position - origin).Magnitude - 3) else ability.range
		endPos = origin + dir * dist
		MoveGuard.grant(hero, ability.range + 10)
		targets =
			HitQuery.capsule(origin.X, origin.Y, origin.Z, endPos.X, endPos.Y, endPos.Z, ability.width, cands)
		if hero.bot then
			hero.bot.position = endPos - CHEST
		end
	else
		return false
	end

	Cooldowns.start(hero.cooldowns, ability.id, now, Formulas.cooldown(Config, ability.cd, 0, hero.classId))
	local hits = {}
	for _, t in targets do
		local dmg, crit = rollDamage(hero, ability)
		local killed = EnemyService.damage(t.id, dmg, hero.id)
		if ability.shape == "dash" and not killed then
			EnemyService.push(t.id, dir * 6) -- knocked aside by the dash
		end
		table.insert(
			hits,
			{ t.id, math.floor(dmg + 0.5), if crit then 1 else 0, if killed then 1 else 0, t.x, t.y, t.z }
		)
	end
	table.insert(pending, {
		a = hero.id,
		n = num,
		s = seq,
		o = origin,
		d = dir,
		e = endPos,
		h = hits,
	})
	return true
end

local function flush()
	if #pending == 0 then
		return
	end
	local batch = pending
	pending = {}
	local r2 = C.resultRadius * C.resultRadius
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local mine = {}
			for _, r in batch do
				local d = r.o - root.Position
				if r.a == player.UserId or d:Dot(d) <= r2 then
					table.insert(mine, r)
				end
			end
			if #mine > 0 then
				Net.fire("CombatResult", player, mine)
			end
		end
	end
end

function CombatService.init()
	local city = Workspace:WaitForChild("City")
	losParams.FilterDescendantsInstances = { city }
	Net.on("CombatUse", function(player, num: number, aim: Vector3, hint: number, seq: number)
		local hero = HeroService.get(player)
		if not hero then
			return
		end
		local t0 = os.clock()
		CombatService.use(hero, num, aim, hint, seq, player:GetNetworkPing())
		PerfMonitor.add("combat", (os.clock() - t0) * 1000)
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 1 / C.resultRate then
			acc = 0
			local t0 = os.clock()
			flush()
			PerfMonitor.add("replication", (os.clock() - t0) * 1000)
		end
	end)
end

return CombatService
