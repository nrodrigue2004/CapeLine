-- KoFx: the blow that takes a robot down reads as the big one (first-30, 2026-11-20, round 3: "every hit should
-- read on screen: flinch, sparks, a number or stamp, and a heavy final blow"). Each hit already flashes, flinches,
-- sparks and shows its number (CombatClient.drawHits); the last one only added a scrap burst and a tiny shake.
-- When a robot this hero hit goes down (CombatClient.Finish "die" with this player as the finisher), on top:
-- a short hit stop on your own hero, a heavier camera shake and punch, the heavy thud a little lower, and a big gold
-- word (Config.Fx.robots.ko.words) over it, at most one word every `gap` s. Elite robots get FinisherFx's slow-mo instead.
-- Reduce flashing drops the stop, shake and punch (the word and the sound stay).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local CombatClient = require(script.Parent.Parent.Controllers.CombatClient)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local HeroAnimator = require(script.Parent.Parent.Controllers.HeroAnimator)
local AudioController = require(script.Parent.Parent.Controllers.AudioController)
local CombatFx = require(script.Parent.CombatFx)

local KoFx = {}

local K = Config.Fx.robots.ko
local COLOR = Color3.fromRGB(K.color[1], K.color[2], K.color[3])
-- the heavy thud as its own row, so the killing hit's own thud a moment before does not hold it back
local THUD = table.clone(Config.Audio.impact.heavy)
local player = Players.LocalPlayer

local elite: { [number]: boolean } = {}
for _, e in Config.Enemies do
	if type(e) == "table" and e.typeId and e.elite then
		elite[e.typeId] = true
	end
end

local lastWord = -math.huge
local count = 0

-- A robot went down at `at`; by: the finisher's UserId
function KoFx.down(typeId: number, at: Vector3, by: number?)
	if by ~= player.UserId or elite[typeId] then
		return
	end
	if not CameraController.reduceMotion then
		HeroAnimator.freeze(K.stop)
		CameraController.shake(K.shake[1], K.shake[2])
		CameraController.punch(Config.Combat.punchHeavy)
	end
	AudioController.playSpec(THUD, at, { pitch = (THUD.pitch or 1) * K.pitch })
	local now = os.clock()
	if now - lastWord >= K.gap then
		lastWord = now
		count += 1
		CombatFx.say(at, K.words[(count - 1) % #K.words + 1], COLOR, true)
	end
end

function KoFx.init()
	CombatClient.Finish:Connect(function(what: string, typeId: number, at: Vector3, by: number?)
		if what == "die" then
			KoFx.down(typeId, at, by)
		end
	end)
end

return KoFx
