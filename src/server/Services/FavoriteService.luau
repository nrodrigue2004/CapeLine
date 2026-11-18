-- FavoriteService: the server half of the favorite prompt (design doc: keep-playing hooks; gap check G7).
-- After a world boss win, an account that has never been shown the prompt gets FavoriteAsk; its device
-- (Controllers.FavoritePrompt) waits for a quiet moment and answers FavoriteShown, which saves the flag
-- (profile.analytics.fav), so the prompt is shown once per account. A plain ask: nothing is paid, unlocked
-- or remembered about the answer (Roblox's rules: no reward for a favorite).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local DataService = require(script.Parent.DataService)
local BossService = require(script.Parent.BossService)

local FavoriteService = {}

local F = Config.Analytics.favorite
-- os.clock of the last FavoriteAsk this session: FavoriteShown is taken only while that ask is open (the
-- device's wait plus its give-up time), and a device that found no quiet moment is asked again after it
local asked: { [Player]: number } = {}

local function open(player: Player): boolean
	local at = asked[player]
	return at ~= nil and os.clock() - at <= F.wait + F.giveUp + 5
end

-- May this account be asked now? (never shown, and no ask still open)
function FavoriteService.canAsk(player: Player): boolean
	local profile = DataService.get(player)
	return profile ~= nil and profile.analytics.fav == 0 and not open(player)
end

local function won(player: Player, _bossId: any, _tier: string, defeated: boolean)
	if defeated and player.Parent == Players and FavoriteService.canAsk(player) then
		asked[player] = os.clock()
		Net.fire("FavoriteAsk", player)
	end
end

local function shown(player: Player)
	local profile = DataService.get(player)
	if not open(player) or not profile then
		return
	end
	asked[player] = nil
	profile.analytics.fav = 1
	DataService.saveSoon(player)
end

function FavoriteService.init()
	BossService.Rewarded:Connect(won)
	Net.on("FavoriteShown", shown)
	Players.PlayerRemoving:Connect(function(player)
		asked[player] = nil
	end)
end

return FavoriteService
