-- SquadClient: this device's copy of your squad (spec: Squads; Squad.State on change). Members with their
-- names, levels, slots and (every 2 s) map positions; the leader's emblem; a pending invite card.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local SquadClient = {}

SquadClient.Changed = Signal.new() -- () members, leader or emblem changed
SquadClient.Moved = Signal.new() -- () new map positions
SquadClient.Invited = Signal.new() -- (invite) { from, name, size, life }
SquadClient.state = { members = {} } :: { [string]: any }
SquadClient.positions = {} :: { [number]: Vector2 } -- user id -> map x, z

local me = Players.LocalPlayer

function SquadClient.inSquad(): boolean
	return #(SquadClient.state.members or {}) > 1
end

function SquadClient.isLeader(): boolean
	return SquadClient.state.leader == me.UserId
end

-- Is this player in your squad? (attributes, so it works for plates before Squad.State arrives)
function SquadClient.isMate(p: Player): boolean
	local mine = me:GetAttribute("Squad")
	return p ~= me and mine ~= nil and p:GetAttribute("Squad") == mine
end

function SquadClient.slotOf(p: Player): number?
	local s = p:GetAttribute("SquadSlot")
	return if typeof(s) == "number" then s else nil
end

function SquadClient.invite(userId: number)
	Net.send("SquadInvite", userId)
end

function SquadClient.answer(yes: boolean)
	Net.send("SquadAnswer", if yes then 1 else 0)
end

function SquadClient.leave()
	Net.send("SquadLeave")
end

function SquadClient.kick(userId: number)
	Net.send("SquadKick", userId)
end

function SquadClient.init()
	Net.listen("SquadState", function(data)
		if data.positions then
			for _, m in data.members or {} do
				if m.x and m.z then
					SquadClient.positions[m.userId] = Vector2.new(m.x, m.z)
				end
			end
			SquadClient.Moved:Fire()
			return
		end
		SquadClient.state = data
		SquadClient.positions = {}
		SquadClient.Changed:Fire()
	end)
	Net.listen("SquadInvited", function(data)
		SquadClient.Invited:Fire(data)
	end)
end

return SquadClient
