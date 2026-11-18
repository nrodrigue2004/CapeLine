-- FavoritePrompt: Roblox's own "favorite this experience" prompt, once per account, after the hero's first
-- world boss win (design doc: keep-playing hooks; gap check G7). A plain ask: no reward, no reminder and
-- nothing locked behind it (Roblox's rules forbid rewarding a favorite).
-- * The server sends FavoriteAsk after a first boss win on an account that has never seen it (FavoriteService
--   keeps the flag in the save). This device waits for a quiet moment (the result card gone, no scene, not
--   Downed, no hit taken for a few seconds), says FavoriteShown so the flag is saved, then opens the prompt.
-- * The call is AvatarEditorService:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true): a place
--   is an asset, so its place id favorites the experience. Wrapped in pcall (Studio and some devices refuse).
-- * No quiet moment within Config.Analytics.favorite.giveUp seconds: nothing is shown and the flag stays
--   unset, so the next boss win asks again.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local CinemaClient = require(script.Parent.CinemaClient)

local FavoritePrompt = {}

local F = Config.Analytics.favorite
local player = Players.LocalPlayer
local askedAt: number? = nil -- os.clock of the server's ask, while waiting for a quiet moment
FavoritePrompt.shown = false -- this session opened the prompt (the Dev panel and tests read it)

-- Is now a calm moment for a system prompt?
function FavoritePrompt.quiet(now: number): boolean
	local at = askedAt
	if not at or now - at < F.wait then
		return false -- the boss result card is still up
	end
	if CinemaClient.playing() or player:GetAttribute("Downed") == true then
		return false
	end
	return now - (CinemaClient.lastHit or 0) >= F.calm
end

local function show()
	askedAt = nil
	FavoritePrompt.shown = true
	Net.send("FavoriteShown") -- saved before the prompt opens, so it is never asked twice
	local ok, err = pcall(function()
		local service = game:GetService("AvatarEditorService")
		service:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
	end)
	if not ok then
		warn("[FavoritePrompt] " .. tostring(err))
	end
end

function FavoritePrompt.init()
	Net.listen("FavoriteAsk", function()
		if not FavoritePrompt.shown and not askedAt then
			askedAt = os.clock()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local at = askedAt
			if at then
				local now = os.clock()
				if FavoritePrompt.quiet(now) then
					show()
				elseif now - at > F.giveUp then
					askedAt = nil -- the next boss win asks again
				end
			end
		end
	end)
end

return FavoritePrompt
