-- MoveActClient: the 20 mobility moves on this device (nate's mobility upgrade rework, 2026-11-20; Config.Move.moves,
-- Shared.MoveActs). MoveController runs the moves that change how the hero moves; this controller
-- * sets off the ones that read the hero's movement: Sonic Boom Dive and Impact Landing (a landing after a big drop),
--   Tornado Run (a tight circle at speed), Afterimage (a hard stop from top speed), Wall Crusher (a climb's kick-off),
--   Shadow Flip (a flip), Wrecking Kick's bowl (a fast release), Blazing Ram and Slipstream's stamina on a ram;
-- * hands MoveController the robots near a point (Ceiling Drop) and Yank's target along the aim;
-- * draws every move: its own (MoveController.Acted, Kicked, Phased) and other heroes' (MoveActFx), all with the
--   effects library (FxLib), the gadget decoy (GadgetFx.decoy) and the juice table's uploaded sounds (Juice).
-- Its frame loop is profiled (FrameProf "MoveActClient") and does nothing for a hero without a move that needs it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local MoveActs = require(Shared:WaitForChild("MoveActs"))
local ThrowMath = require(Shared:WaitForChild("ThrowMath"))
local FrameProf = require(Shared:WaitForChild("FrameProf"))

local State = require(script.Parent.Parent.State)
local MoveController = require(script.Parent.MoveController)
local CameraController = require(script.Parent.CameraController)
local EnemyRenderer = require(script.Parent.EnemyRenderer)
local FxLib = require(script.Parent.Parent.Fx.FxLib)
local GadgetFx = require(script.Parent.Parent.Fx.GadgetFx)
local Juice = require(script.Parent.Parent.Fx.Juice)

local MoveActClient = {}

local MOVES = Config.Move.moves
local player = Players.LocalPlayer

-- each move's colour and its effects set (FxLib elements by set: Config.Fx.lib.setElement)
local LOOK: { [string]: { set: string, color: Color3 } } = {
	sonicDive = { set = "Pulse", color = Color3.fromRGB(190, 225, 255) },
	slipstream = { set = "Pulse", color = Color3.fromRGB(170, 240, 255) },
	phase = { set = "Spirit", color = Color3.fromRGB(170, 140, 255) },
	blazeRam = { set = "Fire", color = Color3.fromRGB(255, 140, 40) },
	tornadoRun = { set = "Earth", color = Color3.fromRGB(215, 205, 185) },
	afterimage = { set = "Volt", color = Color3.fromRGB(120, 220, 255) },
	sonicWake = { set = "Pulse", color = Color3.fromRGB(230, 240, 255) },
	blink = { set = "Volt", color = Color3.fromRGB(120, 220, 255) },
	impactLanding = { set = "Earth", color = Color3.fromRGB(190, 170, 140) },
	wallCrusher = { set = "Earth", color = Color3.fromRGB(165, 158, 150) },
	meteorStrike = { set = "Fire", color = Color3.fromRGB(255, 120, 40) },
	moonJump = { set = "Light", color = Color3.fromRGB(255, 245, 205) },
	kickChain = { set = "Martial", color = Color3.fromRGB(255, 220, 120) },
	ceilingDrop = { set = "Shadow", color = Color3.fromRGB(150, 110, 220) },
	shadowFlip = { set = "Shadow", color = Color3.fromRGB(150, 110, 220) },
	slingshot = { set = "Martial", color = Color3.fromRGB(255, 220, 120) },
	doubleZip = { set = "Volt", color = Color3.fromRGB(255, 255, 255) },
	yank = { set = "Pulse", color = Color3.fromRGB(255, 255, 255) },
	wreckingKick = { set = "Titan", color = Color3.fromRGB(255, 200, 120) },
	skyHook = { set = "Light", color = Color3.fromRGB(255, 255, 255) },
}
-- the moves whose act is (target, start) on this device; MoveActFx sends (start, target - start)
local FROM_START = { ceilingDrop = true, slingshot = true, doubleZip = true, yank = true }

local function rootOf(p: Player?): BasePart?
	local char = p and p.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

-- a body flickering (Phase): who, until when
local flickers: { [Model]: number } = {}

local function flicker(char: Model?, dur: number)
	if char then
		flickers[char] = os.clock() + dur
	end
end

-- Draw one move going off. at, dir: as MoveActFx carries them (for FROM_START moves: the start and the offset to
-- the target); owner: whose it is; mine: this device's own hero (camera kick too)
function MoveActClient.draw(id: string, at: Vector3, dir: Vector3, extra: any, owner: Player?, mine: boolean)
	local look = LOOK[id]
	if not look then
		return
	end
	local c, set = look.color, look.set
	if id == "sonicDive" then
		local m = MOVES.sonicDive
		FxLib.burst(at, m.radius, set, c, true)
		FxLib.dust(at, m.radius)
		Juice.fire("land", at, { mine = mine })
		if mine then
			CameraController.shake(0.25, 0.8)
		end
	elseif id == "phase" then
		local r = rootOf(owner)
		flicker(if r then r.Parent :: Model else nil, MOVES.phase.time * 1.5)
		FxLib.emit("glow", c, at, 1)
		FxLib.emit("wisp", c, at, 6, dir)
	elseif id == "blazeRam" then
		FxLib.burst(at, 8, set, c)
		if dir.Magnitude > 0.1 then
			FxLib.trail(at, at + dir.Unit * 20, set, c)
		end
	elseif id == "tornadoRun" then
		local m = MOVES.tornadoRun
		Juice.fire("boost", at, { mine = mine })
		local t0 = os.clock()
		task.spawn(function()
			while os.clock() - t0 < m.life do
				local t = os.clock() - t0
				for i = 0, 2 do
					local a = t * 9 + i * 2.1
					local h = (t * 14 + i * 5) % 18
					local r = m.lift.radius * (0.35 + h / 36)
					local p = at + Vector3.new(math.cos(a) * r, h, math.sin(a) * r)
					FxLib.emit("dust", c, p, 1, Vector3.new(-math.sin(a), 0.4, math.cos(a)))
				end
				FxLib.emit("cloud", c, at + Vector3.new(0, 2, 0), 1)
				task.wait(0.12)
			end
		end)
	elseif id == "afterimage" or id == "shadowFlip" then
		local life = if type(extra) == "number" and extra > 0 then extra else MOVES[id].life
		GadgetFx.decoy(owner, at, life)
		FxLib.emit("glow", c, at, 1)
	elseif id == "blink" then
		FxLib.trail(at, at + dir, set, c)
		FxLib.emit("glow", c, at, 1)
		FxLib.emit("glow", c, at + dir, 1)
		Juice.fire("boost", at, { mine = mine })
	elseif id == "impactLanding" then
		local m = MOVES.impactLanding
		local radius = if type(extra) == "number" and extra > 0 then extra else m.radius[1]
		FxLib.burst(at, radius, set, c, radius >= m.radius[2] * 0.8)
		FxLib.dust(at, radius)
		Juice.fire("land", at, { mine = mine })
		if mine then
			CameraController.shake(0.2, 0.4 + radius / 40)
		end
	elseif id == "wallCrusher" then
		FxLib.throwMoment("smash", at, c, if dir.Magnitude > 0.1 then dir.Unit else Vector3.yAxis, 3)
		Juice.fire("wallSmash", at, { mine = mine })
	elseif id == "meteorStrike" then
		if extra == 1 then
			FxLib.trail(at, at + dir, set, c) -- the aim, start to target
			FxLib.emit("glow", c, at + dir, 1)
		else
			local m = MOVES.meteorStrike
			FxLib.burst(at, m.radius, set, c, true)
			FxLib.super(at, set, c)
			FxLib.dust(at, m.radius)
			Juice.fire("crater", at, { mine = mine })
			if mine then
				CameraController.shake(0.35, 1.1)
				CameraController.punch(0.08)
			end
		end
	elseif id == "moonJump" then
		FxLib.shock(at - Vector3.new(0, 2.5, 0), 6, c)
		FxLib.emit("star", c, at, 6)
		Juice.fire("leap", at, { mine = mine })
	elseif id == "kickChain" then
		local n = if type(extra) == "number" then extra else 1
		FxLib.emit("spark", c, at, 3 + n * 3, dir)
		if n >= MOVES.kickChain.most then
			FxLib.emit("star", c, at, 4)
		end
	elseif id == "ceilingDrop" then
		FxLib.trail(at, at + dir, set, c)
		local m = MOVES.ceilingDrop
		task.delay(dir.Magnitude / Config.Move.mobility.acrobat.cap, function()
			FxLib.burst(at + dir, m.radius, set, c)
			Juice.fire("land", at + dir, { mine = mine })
		end)
	elseif id == "slingshotCharge" then
		FxLib.gather(at, "Martial", LOOK.slingshot.color)
	elseif id == "slingshot" then
		FxLib.dust(at, 4)
		FxLib.emit("shock", c, at, 1, dir, 4)
		Juice.fire("leap", at, { mine = mine })
	elseif id == "doubleZip" then
		local lines = type(extra) == "table" and extra or nil
		if lines and typeof(lines.first) == "Vector3" and typeof(lines.second) == "Vector3" then
			FxLib.trail(at, lines.first, set, c)
			FxLib.trail(at, lines.second, set, c)
		end
		FxLib.trail(at, at + dir, set, c)
		Juice.fire("boost", at, { mine = mine })
	elseif id == "yank" then
		FxLib.trail(at, at + dir, set, c)
		FxLib.emit("glow", c, at + dir, 1)
		Juice.fire("grab", at + dir, { mine = mine })
	elseif id == "wreckingKick" then
		local m = MOVES.wreckingKick
		local way = if dir.Magnitude > 0.1 then dir.Unit else Vector3.zAxis
		for i = 0, 2 do
			FxLib.shock(at + way * (i * m.radius * 1.5), m.radius, c)
		end
		Juice.fire("clash", at, { mine = mine })
	elseif id == "skyHook" then
		FxLib.emit("glow", c, at, 1)
		FxLib.shock(at, 4, c)
	end
end

---------------------------------------------------------------------------
-- What this device sees its hero do
---------------------------------------------------------------------------

local samples: { MoveActs.Sample } = {}
local peak, peakAt = 0, 0
local wakeFx = 0
local blazeUntil = 0
local lastBlazeAt: Vector3? = nil
local acc = 0

local function onLanded(pos: Vector3, fallSpeed: number)
	local drop = MoveController.dropHeight()
	if MoveController.canUse("sonicDive") and MoveActs.dive(MOVES.sonicDive, drop, fallSpeed) then
		MoveController.act("sonicDive", pos, Vector3.new(0, -1, 0), MOVES.sonicDive.cooldown)
	end
	if MoveController.canUse("impactLanding") then
		local m = MOVES.impactLanding
		local radius = MoveActs.impact(m, drop)
		if radius then
			MoveController.act("impactLanding", pos, Vector3.new(0, drop, 0), m.cooldown, nil, nil, radius)
		end
	end
end

local function onRammed(at: Vector3)
	if MoveController.has("blazeRam") then
		MoveController.stamina = math.max(0, MoveController.stamina - MOVES.blazeRam.stamina)
		blazeUntil = os.clock() + 1
		MoveActClient.draw("blazeRam", at, MoveController.velocity, nil, player, true)
	end
	if MoveController.has("slipstream") and MoveController.boosting then
		-- (the server's mirror does the same refill: MoveActService's ram hook)
		MoveController.stamina =
			math.min(MoveController.config().stamina.max, MoveController.stamina + MOVES.slipstream.refill)
		FxLib.emit("glow", LOOK.slipstream.color, at, 1)
	end
end

local function step(dt: number)
	local root = rootOf(player)
	local now = os.clock()
	-- flickers (Phase) on every body that has one
	for char, untilT in flickers do
		local done = now >= untilT or not char.Parent
		local a = if done then 0 else 0.45 + 0.35 * math.sin(now * 32)
		for _, d in char:GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
				d.LocalTransparencyModifier = a
			end
		end
		if done then
			flickers[char] = nil
		end
	end
	if not root or (State.hero.mobility ~= "speed" and now > blazeUntil) then
		return
	end
	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local p = root.Position
	-- Blazing Ram: the second after a ram leaves fire along the way
	if now < blazeUntil then
		if lastBlazeAt and (p - lastBlazeAt).Magnitude > 4 then
			FxLib.trail(lastBlazeAt, p, LOOK.blazeRam.set, LOOK.blazeRam.color)
		end
		lastBlazeAt = p
	else
		lastBlazeAt = nil
	end
	if State.hero.mobility ~= "speed" or MoveController.mode ~= "ground" then
		table.clear(samples)
		peak = 0
		return
	end
	-- Tornado Run: the run's path, checked five times a second
	if MoveController.has("tornadoRun") then
		table.insert(samples, { x = p.X, z = p.Z, t = now, s = speed })
		while #samples > 0 and now - samples[1].t > MOVES.tornadoRun.window do
			table.remove(samples, 1)
		end
		acc += dt
		if acc >= 0.2 then
			acc = 0
			local ok, cx, cz = MoveActs.circled(MOVES.tornadoRun, samples, now)
			if ok and MoveController.canUse("tornadoRun") then
				table.clear(samples)
				MoveController.act(
					"tornadoRun",
					Vector3.new(cx, p.Y, cz),
					Vector3.zero,
					MOVES.tornadoRun.cooldown
				)
			end
		end
	end
	-- Afterimage: a hard stop from top speed
	if MoveController.has("afterimage") then
		local m = MOVES.afterimage
		if MoveActs.stopped(m, peak, now - peakAt, speed) and MoveController.canUse("afterimage") then
			peak = 0
			MoveController.act("afterimage", p, Vector3.zero, m.cooldown, nil, nil, m.life)
		elseif speed >= peak or now - peakAt > m.within then
			peak, peakAt = speed, now
		end
	end
	-- Sonic Wake: the wind beside a hero at top speed (the server flips the cars and cracks the walls)
	if MoveController.has("sonicWake") and MoveActs.wakeSpeed(MOVES.sonicWake, speed) and now >= wakeFx then
		wakeFx = now + 0.1
		local side = Vector3.new(-v.Z, 0, v.X).Unit * 3
		FxLib.emit("wisp", LOOK.sonicWake.color, p + side, 1, -v)
		FxLib.emit("wisp", LOOK.sonicWake.color, p - side, 1, -v)
	end
end

---------------------------------------------------------------------------
-- Targets for MoveController
---------------------------------------------------------------------------

local function robotsNear(at: Vector3, reach: number): { MoveActs.Cand }
	local out = {}
	for id, pos in EnemyRenderer.each() do
		if (pos - at).Magnitude <= reach then
			table.insert(out, { id = id, x = pos.X, y = pos.Y, z = pos.Z })
		end
	end
	return out
end

-- Yank: a robot that can be held (kind 1), else a liftable thing (kind 2), nearest the aim
local function yankPick(from: Vector3, look: Vector3): (Vector3?, number, number)
	local m = MOVES.yank
	local robots = {}
	for id, pos in EnemyRenderer.each() do
		local cfg = EnemyRenderer.cfgOf(id)
		if
			cfg
			and ThrowMath.canHoldRobot(Config.Throw, cfg, m.stun)
			and (pos - from).Magnitude <= m.range
		then
			table.insert(robots, { id = id, x = pos.X, y = pos.Y, z = pos.Z })
		end
	end
	local c = MoveActs.aimPick(m, from.X, from.Y, from.Z, look.X, look.Y, look.Z, robots)
	if c then
		return Vector3.new(c.x, c.y, c.z), c.id, 1
	end
	local things = {}
	local function add(folder: Instance?)
		for _, mdl in (if folder then folder:GetChildren() else {}) do
			local id = mdl:GetAttribute("ThrowId")
			if mdl:IsA("Model") and type(id) == "number" and mdl:GetAttribute("ThrowBusy") ~= true then
				local pos = mdl:GetPivot().Position
				if (pos - from).Magnitude <= m.range then
					table.insert(things, { id = id, x = pos.X, y = pos.Y, z = pos.Z })
				end
			end
		end
	end
	add(Workspace:FindFirstChild("Throwables"))
	local city = Workspace:FindFirstChild("City")
	add(city and city:FindFirstChild("Vehicles"))
	c = MoveActs.aimPick(m, from.X, from.Y, from.Z, look.X, look.Y, look.Z, things)
	if c then
		return Vector3.new(c.x, c.y, c.z), c.id, 2
	end
	return nil, 0, 0
end

function MoveActClient.init()
	MoveController.robotsNear = robotsNear
	MoveController.yankPick = yankPick
	MoveController.Landed:Connect(onLanded)
	MoveController.Rammed:Connect(onRammed)
	MoveController.Kicked:Connect(function(at: Vector3, normal: Vector3, kind: string, chain: number)
		if kind == "climb" and MoveController.canUse("wallCrusher") then
			MoveController.act("wallCrusher", at, normal, MOVES.wallCrusher.cooldown)
		elseif kind == "acrobat" and MoveController.has("kickChain") and chain >= 2 then
			MoveActClient.draw("kickChain", at, normal, chain, player, true)
		end
	end)
	MoveController.Flipped:Connect(function(at: Vector3)
		if MoveController.canUse("shadowFlip") then
			MoveController.act(
				"shadowFlip",
				at,
				Vector3.zero,
				MOVES.shadowFlip.cooldown,
				nil,
				nil,
				MOVES.shadowFlip.life
			)
		end
	end)
	MoveController.SwingReleased:Connect(function(v: Vector3)
		local root = rootOf(player)
		if
			root
			and MoveController.canUse("wreckingKick")
			and MoveActs.bowl(MOVES.wreckingKick, v.Magnitude)
		then
			MoveController.act("wreckingKick", root.Position, v, MOVES.wreckingKick.cooldown)
		end
	end)
	MoveController.Phased:Connect(function(on: boolean)
		local char = player.Character
		if char then
			if on then
				flicker(char, MOVES.phase.time * 2)
			else
				flickers[char] = os.clock() -- back to solid next frame
			end
		end
	end)
	-- this device's own moves
	MoveController.Acted:Connect(function(id: string, at: Vector3, dir: Vector3, extra: any)
		if id == "phase" then
			FxLib.emit("glow", LOOK.phase.color, at, 1)
			return -- the flicker comes from Phased
		end
		if FROM_START[id] or (id == "meteorStrike" and extra == 1) then
			at, dir = dir, at - dir
		end
		MoveActClient.draw(id, at, dir, extra, player, true)
	end)
	-- other heroes' moves (MoveActService)
	Net.listen("MoveActFx", function(num: number, at: Vector3, dir: Vector3, by: number, extra: number)
		local id = MoveActs.idOf(Config.Move, num)
		if id and typeof(at) == "Vector3" and typeof(dir) == "Vector3" then
			MoveActClient.draw(id, at, dir, extra, Players:GetPlayerByUserId(by), false)
		end
	end)
	RunService.Heartbeat:Connect(FrameProf.wrap("MoveActClient", step))
end

return MoveActClient
