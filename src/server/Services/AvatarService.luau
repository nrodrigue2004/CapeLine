-- AvatarService: every hero is the player's own Roblox avatar plus hero gear (nate, 2026-11-17: "Own avatar plus
-- hero gear"). On each spawn the player's avatar (their HumanoidDescription) is put on the hero body with its
-- body parts, animations and scales reset (Shared.AvatarRules), so the avatar's clothes, face, skin colour, hair
-- and accessories show on the classic blocky R15 body every hero shares. Then the character is marked Avatar
-- and its colours are kept (AvatarStash.AvatarColors) so LookKit can hide and bring back the avatar's own items
-- as the creator's pieces cover them. Ready fires so the look is rebuilt over the avatar.
-- A player whose avatar cannot be read (Studio test players, a web error) keeps the old look: the hero body
-- painted by its suit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local AvatarRules = require(Shared:WaitForChild("AvatarRules"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local AvatarService = {}

AvatarService.Ready = Signal.new() -- (player) the avatar is on the character: rebuild the look over it

local cache: { [number]: HumanoidDescription } = {}

-- The player's avatar for the hero body (the body parts, animations and scales reset), or nil
function AvatarService.description(player: Player): HumanoidDescription?
	local base = cache[player.UserId]
	if not base then
		if player.UserId <= 0 then
			return nil -- Studio's local test players have no avatar
		end
		local ok, desc = pcall(Players.GetHumanoidDescriptionFromUserId, Players, player.UserId)
		if not ok or not desc then
			warn("[AvatarService] could not read the avatar of", player.UserId, desc)
			return nil
		end
		for _, field in AvatarRules.CLEAR do
			(desc :: any)[field] = 0
		end
		for field, value in AvatarRules.SCALES do
			(desc :: any)[field] = value
		end
		cache[player.UserId] = desc
		base = desc
	end
	return base:Clone()
end

-- Keep the avatar's own colours, so a look without a suit can bring them back after a suit painted the body
local function keepColors(char: Model)
	local stash = char:FindFirstChild("AvatarStash")
	if not stash then
		stash = Instance.new("Folder")
		stash.Name = "AvatarStash"
		stash.Parent = char
	end
	local old = (stash :: Folder):FindFirstChild("AvatarColors")
	if old then
		old:Destroy()
	end
	local bc = char:FindFirstChildOfClass("BodyColors")
	if bc then
		local copy = bc:Clone()
		copy.Name = "AvatarColors"
		copy.Parent = stash
	end
end

local function wear(player: Player, char: Model)
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum then
		return
	end
	local desc = AvatarService.description(player)
	if not desc then
		return
	end
	while char.Parent and not char:IsDescendantOf(Workspace) do
		char.AncestryChanged:Wait()
	end
	if player.Character ~= char or not char.Parent then
		return
	end
	local ok, err = pcall(hum.ApplyDescription, hum, desc)
	if not ok then
		warn("[AvatarService] the avatar did not go on:", err)
		return
	end
	if player.Character ~= char then
		return
	end
	keepColors(char)
	char:SetAttribute("Avatar", true)
	AvatarService.Ready:Fire(player)
end

function AvatarService.init()
	if not Config.Creator.avatar.on then
		print("[AvatarService] off (Config.Creator.avatar.on): heroes wear the hero body only")
		return
	end
	local function added(player: Player)
		player.CharacterAdded:Connect(function(char)
			wear(player, char)
		end)
		if player.Character then
			task.spawn(wear, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(added)
	for _, p in Players:GetPlayers() do
		added(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		cache[player.UserId] = nil
	end)
end

return AvatarService
