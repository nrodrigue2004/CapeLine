-- CombatClient: fires abilities with client prediction (spec: Hit resolution). Effects play at once; the
-- server confirms hits in CombatResult and only then do damage numbers and hit flashes show. The client
-- sends only what it wants (ability, aim, a target hint and a sequence number), never damage.
-- Aim: the mouse on PC; on phones and gamepads the screen centre with auto-aim that snaps to the nearest
-- enemy within 25 degrees and 60 studs (spec: Touch flight).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Cooldowns = require(Shared:WaitForChild("Cooldowns"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local InputController = require(script.Parent.InputController)
local MoveController = require(script.Parent.MoveController)
local CameraController = require(script.Parent.CameraController)
local EnemyRenderer = require(script.Parent.EnemyRenderer)
local State = require(script.Parent.Parent.State)
local CombatFx = require(script.Parent.Parent.Fx.CombatFx)

local A = Config.Abilities
local C = Config.Combat
local player = Players.LocalPlayer

local CombatClient = {}
CombatClient.HitConfirm = Signal.new() -- (crit)
CombatClient.Cast = Signal.new() -- (abilityId)

local book = Cooldowns.new()
local seq = 0
local CHEST = Vector3.new(0, 1.5, 0)
local SHOTS = 1
local HERO_HIT = 2
local DIE = 3

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

function CombatClient.cooldownFraction(id: string): number
	local a = A.list[id]
	if not a then
		return 0
	end
	return Cooldowns.fraction(book, id, os.clock(), Formulas.cooldown(Config, a.cd, 0, State.hero.classId))
end

local function rangeOf(a: any): number
	if a.shape == "bolt" and State.hero.classId == "Blaster" then
		return math.max(a.range, Config.Classes.Blaster.basicRange)
	end
	return a.range
end

-- Pick the aim point and the target hint for an ability
local function aim(a: any, origin: Vector3): (Vector3, number, Vector3?)
	local ray = InputController.aimRay()
	local range = rangeOf(a)
	local touchAim = InputController.device ~= "mouse"
	local slack = if touchAim then Config.Move.touch.autoAimAngle else 6
	local maxDist = if touchAim then math.min(range, Config.Move.touch.autoAimRange) else range
	local bestId, bestAng, bestPos = 0, slack, nil
	for id, pos in EnemyRenderer.each() do
		local toEnemy = pos - ray.Origin
		local fromHero = (pos - origin).Magnitude
		if fromHero <= maxDist + 3 and toEnemy.Magnitude > 1 then
			local ang = math.deg(math.acos(math.clamp(toEnemy.Unit:Dot(ray.Direction.Unit), -1, 1)))
			if ang < bestAng then
				bestId, bestAng, bestPos = id, ang, pos
			end
		end
	end
	if bestPos then
		return bestPos, bestId, bestPos
	end
	local char = player.Character
	local skip = {}
	for _, name in { "Fx", "Enemies", "MoveFx", "LoadBots" } do
		local inst = Workspace:FindFirstChild(name)
		if inst then
			table.insert(skip, inst)
		end
	end
	if char then
		table.insert(skip, char)
	end
	rayParams.FilterDescendantsInstances = skip
	local hit = Workspace:Raycast(ray.Origin, ray.Direction.Unit * 400, rayParams)
	local point = if hit then hit.Position else ray.Origin + ray.Direction.Unit * 400
	return point, 0, nil
end

local function hitPause(time: number)
	if CameraController.reduceMotion then
		return
	end
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

function CombatClient.fire(id: string): boolean
	local a = A.list[id]
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not a or not a.built or not root or not hum or hum.Health <= 0 then
		return false
	end
	local now = os.clock()
	if not Cooldowns.ready(book, id, now, 0) then
		return false
	end
	local origin = root.Position + CHEST
	local point, hint, targetPos = aim(a, origin)
	local dir = point - origin
	if dir.Magnitude < 0.5 then
		dir = Workspace.CurrentCamera.CFrame.LookVector
	end
	dir = dir.Unit
	Cooldowns.start(book, id, now, Formulas.cooldown(Config, a.cd, 0, State.hero.classId))
	seq += 1
	local style = State.hero.fxStyle
	local range = rangeOf(a)
	if a.shape == "bolt" then
		CombatFx.bolt(
			origin,
			targetPos or (origin + dir * math.min(range, (point - origin).Magnitude)),
			style
		)
	elseif a.shape == "chain" then
		CombatFx.chain(
			{ origin, targetPos or (origin + dir * math.min(range, (point - origin).Magnitude)) },
			style
		)
	elseif a.shape == "dash" then
		CombatFx.dash(origin, origin + dir * a.range, style)
		MoveController.dash(dir, a.range, a.time)
		CameraController.punch(0.05)
	end
	Net.send("CombatUse", a.num, dir, hint, seq)
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

local function onResult(list: { any })
	for _, r in list do
		local mine = r.a == player.UserId
		local a = A.byNum[r.n]
		local style = styleOf(r.a)
		local hits = r.h or {}
		local points = { r.o }
		for _, h in hits do
			table.insert(points, EnemyRenderer.position(h[1]) or Vector3.new(h[5], h[6], h[7]))
		end
		if a then
			if not mine then
				if a.shape == "bolt" then
					CombatFx.bolt(r.o, points[2] or (r.o + r.d * a.range), style)
				elseif a.shape == "chain" and #points > 1 then
					CombatFx.chain(points, style)
				elseif a.shape == "dash" and r.e then
					CombatFx.dash(r.o, r.e, style)
				end
			elseif a.shape == "chain" and #points > 2 then
				CombatFx.chain({ table.unpack(points, 2) }, style) -- the jumps the client could not predict
			end
		end
		local anyCrit = false
		for i, h in hits do
			local pos = points[i + 1]
			local crit = h[3] == 1
			anyCrit = anyCrit or crit
			EnemyRenderer.flash(h[1])
			CombatFx.impact(pos, crit, style, mine)
			CombatFx.number(pos + Vector3.new(0, 2, 0), h[2], crit, style, mine)
		end
		if mine and #hits > 0 then
			hitPause(if anyCrit then C.critPause else C.hitPause)
			CombatClient.HitConfirm:Fire(anyCrit)
		end
	end
end

local function onEvents(list: { any })
	for _, ev in list do
		local kind = ev[1]
		if kind == SHOTS then
			CombatFx.enemyShot(Vector3.new(ev[3], ev[4], ev[5]), Vector3.new(ev[6], ev[7], ev[8]))
		elseif kind == HERO_HIT then
			if ev[2] == player.UserId then
				CombatFx.hurt()
				CameraController.shake(0.12, 0.25)
			end
		elseif kind == DIE then
			local pos = EnemyRenderer.kill(ev[2]) or Vector3.new(ev[3], ev[4], ev[5])
			CombatFx.burst(pos, styleOf(ev[7]))
			if ev[7] == player.UserId then
				CameraController.shake(0.08, 0.15)
			end
		end
	end
end

function CombatClient.init()
	Net.listen("CombatResult", onResult)
	Net.listen("CombatEvents", onEvents)
	InputController.Pressed:Connect(function(action)
		local skills = State.hero.loadout.skills
		if action == "Skill1" and skills[1] then
			CombatClient.fire(skills[1])
		elseif action == "Skill2" and skills[2] then
			CombatClient.fire(skills[2])
		elseif action == "Basic" then
			CombatClient.fire(State.hero.loadout.basic)
		end
	end)
	RunService.Heartbeat:Connect(function()
		if InputController.isDown("Basic") then
			CombatClient.fire(State.hero.loadout.basic) -- hold to keep firing at the basic's rate
		end
	end)
	player.CharacterAdded:Connect(function()
		Cooldowns.clear(book)
	end)
end

return CombatClient
