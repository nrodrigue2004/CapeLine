-- PerkService: the Legendary perks that watch movement (spec: Legendary perks). Quakeheel sends a shockwave
-- when a hero lands from 30 studs or higher; Echo Trail makes a fast airborne hero's trail hurt nearby
-- machines (0.1 coeff a second). The other perks live where their trigger is: Cooling Kill and Lucky Strike
-- in CombatService, Second Wind in HeroService.damage, Shared Spark in HeroService.power, Magnet Palm in
-- rescues (M6) and Steady Beam in channel interrupts (PvP, M8).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local HeroService = require(script.Parent.HeroService)
local MoveGuard = require(script.Parent.MoveGuard)
local CombatService = require(script.Parent.CombatService)

local PerkService = {}

local P = Config.Gear.perks
local STEP = 0.1
local TRAIL_EVERY = 0.5
local TRAIL_SPEED = 30 -- studs/s: flying or boosting, not hovering

type Track = { airborne: boolean, peak: number, trailAt: number }
local tracks: { [any]: Track } = {}

local function step(now: number)
	for _, hero in HeroService.all() do
		if not hero.player or not hero.alive or not (hero.perks.Quakeheel or hero.perks.EchoTrail) then
			tracks[hero] = nil
			continue
		end
		local char = hero.player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local pos = HeroService.position(hero)
		if not hum or not pos then
			continue
		end
		local t = tracks[hero]
		if not t then
			t = { airborne = false, peak = pos.Y, trailAt = 0 }
			tracks[hero] = t
		end
		local inAir = hum.FloorMaterial == Enum.Material.Air
		if inAir then
			if not t.airborne then
				t.airborne = true
				t.peak = pos.Y
			end
			t.peak = math.max(t.peak, pos.Y)
			if hero.perks.EchoTrail and now >= t.trailAt and MoveGuard.speed(hero) >= TRAIL_SPEED then
				t.trailAt = now + TRAIL_EVERY
				CombatService.burst(
					hero,
					pos,
					P.EchoTrail.radius,
					P.EchoTrail.coeffPerSecond * TRAIL_EVERY,
					true
				)
			end
		elseif t.airborne then
			t.airborne = false
			if hero.perks.Quakeheel and t.peak - pos.Y >= P.Quakeheel.fall then
				CombatService.burst(hero, pos, P.Quakeheel.radius, P.Quakeheel.coeff, false)
			end
		end
	end
end

function PerkService.init()
	task.spawn(function()
		while true do
			task.wait(STEP)
			step(os.clock())
		end
	end)
	HeroService.Removed:Connect(function(hero)
		tracks[hero] = nil
	end)
end

return PerkService
