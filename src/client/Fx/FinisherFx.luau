-- FinisherFx: slow-mo finishers on bosses and elites (nate's lore, build plan step 7, K1; Shared.CinemaPlan,
-- Config.Cinema.finisher). The blow that brings down a world boss, the mission's battle form or an elite robot,
-- or ends a boss's phase or cracks a fake's face, slows time on this device for a moment: every hero's
-- animation (HeroAnimator.timeScale) and every effect's particles (FxLib.setTimeScale) run slow, the camera
-- pushes in (CameraController, scaled by Camera motion). The server is never slowed.
-- * By the hero's fx style: Comic shows a big impact word and a hit stop; Anime a freeze frame (a pale,
--   inked moment) and speed lines (CinemaHud draws them).
-- * The finishing player gets the full version; players within Config.Cinema.finisher.near see a shorter one.
-- * Reduce flashing drops the hit stop, the freeze and the white frame; Camera motion Off drops the push.
-- * At most one finisher every `gap` seconds on a screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local CinemaPlan = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CinemaPlan"))

local State = require(script.Parent.Parent.State)
local HeroAnimator = require(script.Parent.Parent.Controllers.HeroAnimator)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local WorldClient = require(script.Parent.Parent.Controllers.WorldClient)
local AudioController = require(script.Parent.Parent.Controllers.AudioController)
local CombatClient = require(script.Parent.Parent.Controllers.CombatClient)
local FxLib = require(script.Parent.FxLib)
local CinemaHud = require(script.Parent.Parent.Ui.CinemaHud)

local FinisherFx = {}

local F = Config.Cinema.finisher
local player = Players.LocalPlayer
local nextAt = 0
local restoreAt = 0
local eliteByType: { [number]: boolean } = {}
for _, e in Config.Enemies do
	if type(e) == "table" and e.typeId and e.elite then
		eliteByType[e.typeId] = true
	end
end

local function restore()
	HeroAnimator.timeScale = 1
	FxLib.setTimeScale(1)
end

-- Play a finisher: what (CinemaPlan.FINISHERS), where it landed, the finishing hero's id (a player's
-- UserId), a seed for the word. Returns the plan, or nil when this screen shows none.
function FinisherFx.play(what: string, at: Vector3, by: number?, seed: number?): CinemaPlan.Finisher?
	if not CinemaPlan.FINISHERS[what] then
		return nil
	end
	local now = os.clock()
	if now < nextAt then
		return nil
	end
	local cam = Workspace.CurrentCamera
	local eye = cam and cam.CFrame.Position or at
	local role = CinemaPlan.role(Config, by == player.UserId, (eye - at).Magnitude)
	if not role then
		return nil
	end
	nextAt = now + F.gap
	local plan = CinemaPlan.finisher(
		Config,
		State.hero.fxStyle or "Comic",
		role,
		CameraController.motionOption,
		CameraController.reduceMotion
	)
	-- the time-slow feel (this device only)
	HeroAnimator.timeScale = plan.slow
	FxLib.setTimeScale(plan.slow)
	local stop = math.max(plan.hitStop, plan.freeze)
	if stop > 0 then
		HeroAnimator.freeze(stop) -- the hit stop or the freeze frame holds your own clip still
	end
	if plan.push > 0 then
		CameraController.push(plan.push, true)
	end
	CinemaHud.finisher(plan, CinemaPlan.word(Config, what, seed or math.floor(at.X + at.Z)))
	AudioController.play("bossPhase", at)
	restoreAt = now + plan.seconds
	local mine = restoreAt
	task.delay(plan.seconds, function()
		if restoreAt == mine then
			restore()
		end
	end)
	return plan
end

-- An enemy went down (CombatClient's DIE): a finisher when it was an elite robot
function FinisherFx.enemyDown(typeId: number, at: Vector3, by: number?, id: number?)
	if eliteByType[typeId] then
		FinisherFx.play("eliteDead", at, by, id)
	end
end

function FinisherFx.init()
	CombatClient.Finish:Connect(function(what: string, typeId: number, at: Vector3, by: number?, id: number?)
		if what == "die" then
			FinisherFx.enemyDown(typeId, at, by, id)
		elseif what == "unmask" then
			FinisherFx.play("unmask", at, by, id)
		end
	end)
	WorldClient.BossAttack:Connect(function(ev: { [string]: any })
		if ev.k == "phase" or ev.k == "dead" then
			local at = Vector3.new(ev.x or 0, ev.y or 0, ev.z or 0)
			local b = WorldClient.boss
			if (ev.x == nil or ev.x == 0) and b and b.x then
				at = Vector3.new(b.x, b.y or 0, b.z)
			end
			FinisherFx.play(if ev.k == "dead" then "bossDead" else "bossPhase", at, ev.by, ev.phase)
		end
	end)
end

return FinisherFx
