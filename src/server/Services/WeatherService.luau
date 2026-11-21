-- WeatherService (2026-11-21, Everything Left 735): the one weather that needs the server. The weather itself is
-- worked out on every device from server time (Shared.WeatherPlan); in a lightning storm (`strikes`) the server
-- here, every Config.Weather.strikes.gap seconds with its chance, picks a hero out in the city (not in a pocket,
-- the HQ, underwater or the prologue), strikes the roof of a breakable building near them (never one with a hero
-- standing close: WeatherPlan.pickRoof) and knocks pieces out (BuildingService.smash). Every device draws the bolt
-- from WeatherStrike. A hero is never hurt by it: a look and the city's destruction, nothing more.
-- Studio: DevCommand "weather n" holds kind n of Config.Weather.order (0 lets go), "strike" strikes now.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local WeatherPlan = require(Shared:WaitForChild("WeatherPlan"))
local PocketLayout = require(Shared:WaitForChild("PocketLayout"))
local DeepLayout = require(Shared:WaitForChild("DeepLayout"))

local BuildingService = require(script.Parent.BuildingService)
local HeroService = require(script.Parent.HeroService)
local OpeningService = require(script.Parent.OpeningService)

local WeatherService = {}

local W = Config.Weather
local K = W.strikes
local rng = Random.new()

-- the weather now (the Studio hold first), as WeatherFx works it out
function WeatherService.kind(): string
	local force = Workspace:GetAttribute("WeatherForce")
	if type(force) == "string" and W.kinds[force] then
		return force
	end
	local from, to, k = WeatherPlan.at(W, Workspace:GetServerTimeNow())
	return if k < 0.5 then from else to
end

-- heroes out in the city: { player, position }
local function outside(): { { any } }
	local out = {}
	for _, player in Players:GetPlayers() do
		local hero = HeroService.get(player)
		local pos = hero and HeroService.position(hero)
		if
			pos
			and pos.Y < Config.Audio.bed.maxY
			and not PocketLayout.at(Config, pos.X, pos.Y, pos.Z)
			and not DeepLayout.underwater(Config, pos.X, pos.Y, pos.Z)
			and not OpeningService.running(player)
		then
			table.insert(out, { player, pos })
		end
	end
	return out
end

-- One strike near a random hero out in the city. Returns the struck point, or nil.
function WeatherService.strike(): Vector3?
	local heroes = outside()
	if #heroes == 0 then
		return nil
	end
	local pick = heroes[rng:NextInteger(1, #heroes)][2]
	local others = {}
	for _, h in heroes do
		table.insert(others, { h[2].X, h[2].Y, h[2].Z })
	end
	local roofs = BuildingService.roofsNear(pick.X, pick.Z, K.range)
	local roof, at =
		WeatherPlan.pickRoof(W, roofs, pick.X, pick.Z, others, rng:NextNumber(), rng:NextNumber())
	if not (roof and at) then
		return nil
	end
	local p = Vector3.new(at[1], at[2], at[3])
	Net.fireAll("WeatherStrike", p.X, p.Y, p.Z, rng:NextInteger(1, 1000000))
	BuildingService.smash(roof.id, p + Vector3.new(0, -2, 0), K.dmg, K.radius)
	return p
end

function WeatherService.hold(n: number)
	Workspace:SetAttribute("WeatherForce", if n > 0 then W.order[n] else nil)
end

function WeatherService.init()
	task.spawn(function()
		while true do
			task.wait(K.gap)
			if W.on and W.kinds[WeatherService.kind()].strikes and rng:NextNumber() < K.chance then
				local ok, err = pcall(WeatherService.strike)
				if not ok then
					warn("[WeatherService] strike failed:", err)
				end
			end
		end
	end)
end

return WeatherService
