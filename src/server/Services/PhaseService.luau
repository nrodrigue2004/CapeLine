-- PhaseService: who is in which private ("phased") story run (missions lane, 2026-11-20; nate's playtest: missions on
-- the real map, "just you or you and friends"). A run opens a phase, its members join it and leave it, and the run
-- closes it. A member's hero carries `hero.phase`; its player carries the Phase attribute, so its own device knows
-- which Sites pieces to show (Controllers.PhaseClient). The rules (keys, who sees what) are Shared.PhaseRules:
--   * EnemyService.setPhase puts a robot in a phase: it sees, chases, shoots and hurts only that phase's heroes, only
--     they can hurt it, and only their devices get it in Enemy.Delta and CombatEvents.
--   * EnemyService.addTarget({ phase = id }) and SiteKit.inPhase do the same for combat targets and Sites pieces.
--   * A hero in a phase is out of the open world's robots, targets, Sites pieces, the world boss and PvP.
-- MissionService opens one per run (pocket runs too, so the layer is used today; a later step puts runs on the map).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PhaseRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PhaseRules"))

local HeroService = require(script.Parent.HeroService)

local PhaseService = {}

local nextId = 0
local members: { [number]: { [any]: boolean } } = {} -- phase id -> its heroes

-- A new phase id (1 to 30,000, never one that is open)
function PhaseService.open(): number
	repeat
		nextId = nextId % 30000 + 1
	until not members[nextId]
	members[nextId] = {}
	return nextId
end

-- Put a hero in a phase (out of any other first). A closed or unknown phase does nothing.
function PhaseService.join(phase: number?, hero: any)
	if not phase or not hero or not members[phase] then
		return
	end
	if hero.phase and hero.phase ~= phase then
		PhaseService.leave(hero)
	end
	members[phase][hero] = true
	hero.phase = phase
	if hero.player then
		hero.player:SetAttribute("Phase", phase)
	end
end

-- Back to the open world
function PhaseService.leave(hero: any)
	if not hero or not hero.phase then
		return
	end
	local set = members[hero.phase]
	if set then
		set[hero] = nil
	end
	hero.phase = nil
	if hero.player then
		hero.player:SetAttribute("Phase", nil)
	end
end

-- The run is over: everyone left in it goes back to the open world
function PhaseService.close(phase: number?)
	local set = phase and members[phase]
	if not set then
		return
	end
	for hero in table.clone(set) do
		PhaseService.leave(hero)
	end
	members[phase :: number] = nil
end

function PhaseService.of(hero: any): number?
	return hero and hero.phase or nil
end

function PhaseService.has(phase: number?, hero: any): boolean
	return phase ~= nil and hero ~= nil and hero.phase == phase
end

-- The heroes in a phase now
function PhaseService.heroes(phase: number?): { any }
	local out = {}
	local set: { [any]: boolean } = if phase then members[phase] or {} else {}
	for hero in set do
		table.insert(out, hero)
	end
	return out
end

function PhaseService.isOpen(phase: number?): boolean
	return phase ~= nil and members[phase] ~= nil
end

-- A player's phase (nil outside one): a prompt or remote from a player checks it
function PhaseService.ofPlayer(player: Player): number?
	return PhaseRules.read(player:GetAttribute("Phase"))
end

function PhaseService.init()
	HeroService.Removed:Connect(function(hero)
		PhaseService.leave(hero)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local hero = HeroService.get(player)
		if hero then
			PhaseService.leave(hero)
		end
	end)
end

return PhaseService
