-- SquadService: squads of up to 4 (spec: Social table "Up to 4 players, shared incident rewards, squad
-- emblem, squad ping"; Squad.Invite, Squad.Accept, Squad.Leave 1/s; Squad.State on change; Map "party";
-- Mission.Enter "party size 4 or less"). The rules are SquadRules (pure, tested).
-- * Invite anyone in the server from their plate or the SQUAD panel; they get a card for 30 s.
-- * Squadmates are allies: their hits never land on each other, even with PvP flags on (FlagService).
-- * A cleared incident pays squadmates within 250 studs too (IncidentService.share); pings reach the
--   squad at any range (DeathService.squadOf); squadmates near you join your mission (MissionService).
-- * Everyone sees squads through player attributes (Squad id, SquadSlot 1 to 4); members get SquadState
--   with names, levels, the leader's emblem and positions every 2 s for the map.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FrameProf =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("FrameProf"))

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local SquadRules = require(Shared:WaitForChild("SquadRules"))
local CreatorRules = require(Shared:WaitForChild("CreatorRules"))
local LookCodec = require(Shared:WaitForChild("LookCodec"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))

local DataService = require(script.Parent.DataService)
local HeroService = require(script.Parent.HeroService)
local FlagService = require(script.Parent.FlagService)
local IncidentService = require(script.Parent.IncidentService)
local DeathService = require(script.Parent.DeathService)
local MissionService = require(script.Parent.MissionService)
local Analytics = require(script.Parent.Analytics)

local SquadService = {}

local Q = Config.Squad
local st = SquadRules.new()

local function nameOf(player: Player): string
	local hn = player:GetAttribute("HeroName")
	return if typeof(hn) == "string" and hn ~= "" then hn else player.DisplayName
end

local function playersOf(userIds: { number }): { Player }
	local out = {}
	for _, id in userIds do
		local p = Players:GetPlayerByUserId(id)
		if p then
			table.insert(out, p)
		end
	end
	return out
end

-- The leader's emblem (glyph and colour) for the squad tag
local function emblemOf(player: Player): { [string]: any }?
	local profile = DataService.get(player)
	if not profile then
		return nil
	end
	local look = LookCodec.read(ProfileSchema.active(profile).look)
	if not look then
		return nil
	end
	local p = CreatorRules.piece(Config, "emblem", look.pieces.emblem or 0)
	local shape = if p then string.split(p.kit, ":")[1] else "star"
	local c = Config.Creator.palette[look.colors[3] or 1] or { 255, 200, 60 }
	-- gap-icons2: the shape too, so the squad tag can show the drawn emblem mark (Config.Creator.emblemArt)
	return { glyph = Config.Creator.shapes[shape] or "★", color = c, shape = shape }
end

local function send(squadId: number?, withPositions: boolean?)
	local squad = squadId and st.squads[squadId]
	if not squad then
		return
	end
	local list = {}
	for slot, id in squad.members do
		local p = Players:GetPlayerByUserId(id)
		local hero = p and HeroService.get(p)
		local pos = hero and withPositions and HeroService.position(hero)
		table.insert(list, {
			userId = id,
			name = if p then nameOf(p) else "?",
			level = if hero then hero.level else 1,
			classId = if hero then hero.classId else "",
			side = if hero then hero.side else "hero",
			slot = slot,
			x = pos and math.floor(pos.X),
			z = pos and math.floor(pos.Z),
		})
	end
	local leader = Players:GetPlayerByUserId(squad.members[1])
	local packet = {
		id = squad.id,
		leader = squad.members[1],
		members = list,
		emblem = leader and emblemOf(leader),
		positions = withPositions or nil,
	}
	for slot, p in playersOf(squad.members) do
		if not withPositions then
			p:SetAttribute("Squad", squad.id)
			p:SetAttribute("SquadSlot", slot)
		end
		Net.fire("SquadState", p, packet)
	end
end

local function solo(player: Player)
	player:SetAttribute("Squad", nil)
	player:SetAttribute("SquadSlot", nil)
	Net.fire("SquadState", player, { members = {} })
end

local function toast(player: Player, id: string, data: { [string]: any }?)
	local t = data or {}
	t.id = id
	Net.fire("Toast", player, t)
end

local function leave(player: Player)
	local before = SquadRules.members(st, player.UserId)
	local squadId = SquadRules.leave(st, player.UserId)
	if not squadId then
		return
	end
	if player.Parent then
		solo(player)
	end
	if st.squads[squadId] then
		send(squadId)
		for _, p in playersOf(st.squads[squadId].members) do
			toast(p, "squadLeft", { name = nameOf(player) })
		end
	else
		-- the squad is gone: the last one is solo again
		for _, id in before do
			local p = Players:GetPlayerByUserId(id)
			if p and p ~= player then
				solo(p)
				toast(p, "squadGone")
			end
		end
	end
end

local function invite(player: Player, userId: number)
	local target = Players:GetPlayerByUserId(userId)
	if not target then
		toast(player, "squadRefused", { reason = "gone" })
		return
	end
	local hero = HeroService.get(player)
	if hero and hero.scene == "mission" then
		toast(player, "squadRefused", { reason = "mission" })
		return
	end
	local ok, why = SquadRules.invite(Config, st, player.UserId, userId, os.clock())
	if not ok then
		toast(player, "squadRefused", { reason = why })
		return
	end
	toast(player, "squadInvited", { name = nameOf(target) })
	Net.fire("SquadInvited", target, {
		from = player.UserId,
		name = nameOf(player),
		size = #SquadRules.members(st, player.UserId),
		life = Q.inviteLife,
	})
end

local function answer(player: Player, yes: number)
	if yes ~= 1 then
		SquadRules.decline(st, player.UserId)
		return
	end
	local hero = HeroService.get(player)
	if hero and hero.scene == "mission" then
		toast(player, "squadRefused", { reason = "mission" })
		return
	end
	local ok, why, squadId = SquadRules.accept(Config, st, player.UserId, os.clock())
	if not ok then
		toast(player, "squadRefused", { reason = why })
		return
	end
	send(squadId)
	for _, p in playersOf(SquadRules.members(st, player.UserId)) do
		if p ~= player then
			toast(p, "squadJoined", { name = nameOf(player) })
		end
	end
	toast(player, "squadJoin")
	Analytics.event(player, "squad_join", 1, { #SquadRules.members(st, player.UserId) })
end

function SquadService.allies(a: Player, b: Player): boolean
	return SquadRules.allies(st, a.UserId, b.UserId)
end

function SquadService.mates(player: Player): { Player }
	local out = {}
	for _, p in playersOf(SquadRules.members(st, player.UserId)) do
		if p ~= player then
			table.insert(out, p)
		end
	end
	return out
end

function SquadService.init()
	Net.on("SquadInvite", invite)
	Net.on("SquadAnswer", answer)
	Net.on("SquadLeave", leave)
	Net.on("SquadKick", function(player, userId: number)
		local target = Players:GetPlayerByUserId(userId)
		if SquadRules.kick(st, player.UserId, userId) then
			if target then
				solo(target)
				toast(target, "squadKicked")
			end
			local squadId = st.of[player.UserId]
			if squadId then
				send(squadId)
			else
				solo(player)
			end
		end
	end)
	Players.PlayerRemoving:Connect(leave)
	-- allies never hit each other
	FlagService.allyCheck = function(a, b)
		return a.player ~= nil and b.player ~= nil and SquadRules.allies(st, a.player.UserId, b.player.UserId)
	end
	-- shared incident rewards: squadmates near the site count as helpers
	IncidentService.share = function(helpers, pos)
		local add = {}
		for heroId in helpers do
			local hero = HeroService.byId(heroId)
			if hero and hero.player then
				for _, mate in SquadService.mates(hero.player) do
					local mh = HeroService.get(mate)
					local mp = mh and HeroService.position(mh)
					if mh and mp and (mp - pos).Magnitude <= Q.shareRange then
						add[mh.id] = true
					end
				end
			end
		end
		for id in add do
			helpers[id] = true
		end
	end
	-- squad pings reach the whole squad
	DeathService.squadOf = function(hero)
		return if hero.player and Q.pingSquad then SquadService.mates(hero.player) else {}
	end
	-- squadmates near the leader come into the mission
	MissionService.partyOf = function(leader)
		local lh = HeroService.get(leader)
		local lp = lh and HeroService.position(lh)
		local out = {}
		if not lp then
			return out
		end
		for _, mate in SquadService.mates(leader) do
			local mh = HeroService.get(mate)
			local mp = mh and HeroService.position(mh)
			if mh and mp and (mp - lp).Magnitude <= Q.missionRange and not HeroService.inCombat(mh) then
				table.insert(out, mate)
			end
		end
		return out
	end
	HeroService.Leveled:Connect(function(hero)
		if hero.player then
			send(st.of[hero.player.UserId])
		end
	end)
	-- positions for the map every 2 s
	local acc = 0
	RunService.Heartbeat:Connect(FrameProf.wrap("SquadService", function(dt)
		acc += dt
		if acc < 2 then
			return
		end
		acc = 0
		for id in st.squads do
			send(id, true)
		end
	end))
end

-- Dev and tests: the rules state
function SquadService.state(): SquadRules.State
	return st
end

return SquadService
