-- CinemaService: the save's seen set for the cinematic layer (nate's lore, build plan step 7). A scene may be
-- skipped only once its bit is set (Shared.CinemaPlan): the prologue's camera beats and the missions' camera
-- beats are marked here by OpeningService and MissionService when they end; a device-started scene (the Dev
-- panel's samples) sends SceneSeen with its bit, and only those bits are taken from a device.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local CinemaPlan = require(Shared:WaitForChild("CinemaPlan"))
local ProfileSchema = require(Shared:WaitForChild("ProfileSchema"))

local DataService = require(script.Parent.DataService)

local Bits = ProfileSchema.Bits

local CinemaService = {}

-- Has this player's save seen the scene with this bit?
function CinemaService.seen(player: Player, bit: number?): boolean
	local profile = DataService.get(player)
	if not profile or bit == nil or type(profile.seen) ~= "table" then
		return false
	end
	return Bits.get(profile.seen, bit)
end

-- Set a scene's bit on the save (the client view carries it, so the device's SKIP follows)
function CinemaService.mark(player: Player, bit: number?)
	local profile = DataService.get(player)
	if not profile or bit == nil or bit < 0 or bit >= ProfileSchema.SEEN_WORDS * 32 then
		return
	end
	if not Bits.get(profile.seen, bit) then
		Bits.set(profile.seen, bit, true)
		DataService.changed(player)
	end
end

-- A named scene by id (Config.Cinema.scenes)
function CinemaService.seenScene(player: Player, id: string): boolean
	return CinemaService.seen(player, CinemaPlan.bit(Config, id))
end

function CinemaService.markScene(player: Player, id: string)
	CinemaService.mark(player, CinemaPlan.bit(Config, id))
end

function CinemaService.init()
	Net.on("SceneSeen", function(player: Player, bit: number)
		if CinemaPlan.clientBit(Config, bit) then
			CinemaService.mark(player, bit)
		end
	end)
end

return CinemaService
