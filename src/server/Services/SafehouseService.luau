-- SafehouseService: the 16 safehouses (spec: Map layout > Safehouses; Defeat and death; Banking; Screens >
-- Loadout and Skills "swap needs a safehouse unless Quick Swap").
-- * Terminals are ProximityPrompts on the terminal parts: Bank (hold 3 s: every on-hand Credit goes to the
--   bank), Loadout (opens the loadout screen on the client) and Respawn (this safehouse becomes the hero's
--   respawn point).
-- * A 2 Hz pass marks a safehouse visited when a hero walks onto it (respawn choices) and keeps
--   hero.safehouse set while the hero stands inside its safe radius (40 studs, PvP-free in M8).
-- * Respawns: after a defeat the hero lands at the nearest visited safehouse; a returning player joins at
--   their last chosen safehouse; a brand-new hero lands on the plaza (the opening disaster is M7).
-- * near(hero): at a safehouse or HQ, where loadout swaps and respec are allowed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Travel = require(Shared:WaitForChild("Travel"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))

local CityBuilder = require(script.Parent.CityBuilder)
local HeroService = require(script.Parent.HeroService)
local MoveGuard = require(script.Parent.MoveGuard)
local DataService = require(script.Parent.DataService)

local SafehouseService = {}

local W = Config.World
local S = W.safehouse
local deathSpot: { [number]: Vector3 } = {} -- hero id -> where they were defeated
local joined: { [Player]: boolean } = {} -- first spawn handled

local function char(player: Player): any?
	local profile = DataService.get(player)
	return profile and ProfileSchema.active(profile)
end

-- The safehouse a point stands in (within the safe radius), or nil
function SafehouseService.at(pos: Vector3): number?
	local world = CityBuilder.world
	local r2 = S.safeRadius * S.safeRadius
	for id, s in world.safehouses do
		local dx, dz = s.x - pos.X, s.z - pos.Z
		if dx * dx + dz * dz <= r2 and math.abs(pos.Y - s.y) < 30 then
			return id
		end
	end
	return nil
end

-- The two HQs count as safe places too (spec: "free players swap at safehouses and HQ")
local function atHq(pos: Vector3): boolean
	local world = CityBuilder.world
	local bt = world.downtown.beacon
	local door = world.spots.foundryDoor
	for _, p in { { x = bt.x, z = bt.z }, door } do
		if p and (p.x - pos.X) ^ 2 + (p.z - pos.Z) ^ 2 <= 80 * 80 then
			return true
		end
	end
	return false
end

function SafehouseService.near(hero: any): boolean
	local pos = HeroService.position(hero)
	if not pos then
		return false
	end
	return SafehouseService.at(pos) ~= nil or atHq(pos)
end

-- Loadout swaps: at a safehouse or HQ, or anywhere with the Quick Swap pass. Bots always may.
function SafehouseService.canSwap(hero: any): (boolean, string?)
	if not hero.player then
		return true, nil
	end
	local profile = DataService.get(hero.player)
	if profile and profile.purchases.passes.quickSwap then
		return true, nil
	end
	if SafehouseService.near(hero) then
		return true, nil
	end
	return false, "safehouse"
end

local function respawnCFrame(id: number): CFrame?
	local s = CityBuilder.world.safehouses[id]
	if not s then
		return nil
	end
	local p = s.respawn[math.random(1, #s.respawn)]
	-- face away from the shelter, toward the open side of the pad
	return CFrame.lookAt(Vector3.new(p.x, p.y, p.z), Vector3.new(p.x, p.y, p.z + 20))
end

local function placeCharacter(hero: any, cf: CFrame)
	local player = hero.player
	local model = player and player.Character
	if not model then
		return
	end
	pcall(player.RequestStreamAroundAsync, player, cf.Position, 2)
	local root = model:WaitForChild("HumanoidRootPart", 5)
	if root and model.Parent then
		model:PivotTo(cf)
		MoveGuard.reset(hero)
	end
end

local function onSpawned(hero: any)
	local player = hero.player
	if not player then
		return
	end
	local c = char(player)
	if not c then
		return -- not loaded yet; the plaza spawn stands
	end
	local died = deathSpot[hero.id]
	deathSpot[hero.id] = nil
	local id = 0
	if died then
		id = Travel.respawnAt(
			CityBuilder.world.safehouses,
			c.safehouses,
			c.lastSafehouse,
			S.homeSafehouse,
			died.X,
			died.Z
		)
	elseif not joined[player] and c.lastSafehouse ~= 0 then
		id = c.lastSafehouse
	end
	joined[player] = true
	local cf = id ~= 0 and respawnCFrame(id)
	if cf then
		task.spawn(placeCharacter, hero, cf)
	end
end

local function bank(player: Player)
	local profile = DataService.get(player)
	local hero = HeroService.get(player)
	if not profile or not hero then
		return
	end
	local moved = Travel.deposit(profile.currency)
	DataService.changed(player, true)
	if moved > 0 then
		DataService.saveSoon(player)
	end
	Net.fire("Toast", player, { id = "banked", credits = moved })
end

local function setRespawn(player: Player, id: number)
	local c = char(player)
	if not c then
		return
	end
	c.lastSafehouse = id
	c.safehouses = Travel.add(c.safehouses, id)
	DataService.changed(player)
	DataService.saveSoon(player)
	Net.fire("Toast", player, { id = "respawnSet", name = CityBuilder.world.safehouses[id].name })
end

local function addPrompt(part: BasePart, kind: string, id: number)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Terminal"
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = S.terminalRange
	prompt.KeyboardKeyCode = Enum.KeyCode.B -- E is Skill 2
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	if kind == "bank" then
		prompt.ActionText = "Bank Credits"
		prompt.ObjectText = "Safehouse bank"
		prompt.HoldDuration = S.bankHold
	elseif kind == "loadout" then
		prompt.ActionText = "Loadout"
		prompt.ObjectText = "Safehouse"
		prompt.HoldDuration = 0
	else
		prompt.ActionText = "Respawn here"
		prompt.ObjectText = "Safehouse"
		prompt.HoldDuration = 0.5
	end
	prompt:SetAttribute("Terminal", kind)
	prompt:SetAttribute("Safehouse", id)
	prompt.Triggered:Connect(function(player)
		local hero = HeroService.get(player)
		if not hero or not hero.alive then
			return
		end
		if kind == "bank" then
			bank(player)
		elseif kind == "respawn" then
			setRespawn(player, id)
		end
		-- "loadout" is opened by the client (it hears the same prompt)
	end)
	prompt.Parent = part
end

local function visitPass()
	for _, hero in HeroService.all() do
		local player = hero.player
		local pos = player and hero.alive and HeroService.position(hero)
		if pos then
			local id = SafehouseService.at(pos)
			hero.safehouse = id
			local c = id and char(player)
			if c and not Travel.has(c.safehouses, id) then
				c.safehouses = Travel.add(c.safehouses, id)
				if c.lastSafehouse == 0 then
					c.lastSafehouse = id
				end
				DataService.changed(player)
				Net.fire("Toast", player, { id = "safehouse", name = CityBuilder.world.safehouses[id].name })
			end
		end
	end
end

function SafehouseService.init()
	local city = CityBuilder.folder
	for _, part in (city :: Folder):GetDescendants() do
		if part:IsA("BasePart") then
			local tag = part:GetAttribute("Tag")
			if tag == "bank" or tag == "loadout" or tag == "respawn" then
				addPrompt(part, tag, part:GetAttribute("Ref") :: number)
			end
		end
	end
	HeroService.Defeated:Connect(function(hero)
		local pos = HeroService.position(hero)
		if pos then
			deathSpot[hero.id] = pos
		end
	end)
	HeroService.Spawned:Connect(onSpawned)
	DataService.Loaded:Connect(function(player)
		-- the character spawned before the profile arrived: place it now
		local hero = HeroService.get(player)
		if hero and player.Character and not joined[player] then
			onSpawned(hero)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		joined[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			visitPass()
		end
	end)
	Workspace:SetAttribute("Safehouses", #W.safehouses)
end

return SafehouseService
