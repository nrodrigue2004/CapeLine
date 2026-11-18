-- PromoService: the group-join cosmetic and creator codes (spec: Update 1; gap check G12, WP10). Rules in
-- Shared.PromoRules, numbers and the FIXED code list in Config.Promo, the save in profile.promo (the
-- account's, so a slot switch changes nothing).
-- * The group piece: when Config.Promo.group.id is set, a member gets its piece once per account. Checked
--   with Player:IsInGroup in a pcall when the save loads, and again when CHECK is tapped (CHECK also asks
--   GroupService:GetGroupsAsync, since IsInGroup can keep an answer from earlier in the session). A failed
--   call pays nothing and says so; it is never a "not a member".
-- * Codes: PromoRedeem carries one string (Remotes: 20 characters at most, rate-limited). The server
--   normalizes it and matches it against the fixed list only (PromoRules.find); every answer is a fixed
--   reason. The typed text is never stored unless it matched a row, never logged, never sent to another
--   player and never sent back. Wrong codes count towards a short wait (Config.Promo.tries).
-- * Pay and save: the claim is marked on the same profile as the piece before anything is sent, and only
--   while the session can save (DataService.isSaving), so a rejoin or a server hop never pays twice and a
--   save that is down claims nothing.
-- * Analytics: promo_claim (kind, tag), one per claim (rare, well inside the per-minute budget).
-- * Studio (DevService "promo"): 1 forget this account's claims; 2 pay the group piece as if a member.
--   Config.Promo.studio codes work in Studio only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GroupService = game:GetService("GroupService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CreatorRules = require(Shared:WaitForChild("CreatorRules"))
local Net = require(Shared:WaitForChild("Net"))
local PromoRules = require(Shared:WaitForChild("PromoRules"))

local Analytics = require(script.Parent.Analytics)
local DataService = require(script.Parent.DataService)

local PromoService = {}

local P = Config.Promo
local wrongTries: { [Player]: { number } } = {}
local lastCheck: { [Player]: number } = {}
local member: { [Player]: boolean } = {} -- the last group answer this session (for the row)

local function studio(): boolean
	return RunService:IsStudio()
end

local function today(): number
	return os.time() // 86400
end

local function send(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local v = PromoRules.view(Config, profile.promo, today(), studio())
	if v.group then
		v.group.member = member[player] == true
	end
	v.offline = not DataService.isSaving(player) or nil
	Net.fire("PromoState", player, v)
end

-- Unlock a reward piece; true when it was new (false: already owned, the claim still counts)
local function payPiece(player: Player, profile: any, name: string): boolean
	local piece = CreatorRules.index(Config).byName[name]
	if piece and CreatorRules.grant(profile, piece) then
		Net.fire("Toast", player, { id = "piece", name = piece.name })
		return true
	end
	return false
end

local function result(player: Player, kind: string, reason: string, piece: string?, extra: number?)
	Net.fire("PromoResult", player, { kind = kind, reason = reason, piece = piece, wait = extra })
end

-- Ask Roblox whether a player is in the group: true, false, or nil when the call failed
local function inGroup(player: Player, fresh: boolean): boolean?
	local id = P.group.id
	if id == 0 then
		return false
	end
	local ok, yes = pcall(player.IsInGroup, player, id)
	if ok and yes then
		return true
	end
	if fresh then
		-- IsInGroup may keep an answer from earlier in the session: the group list is asked anew
		local ok2, groups = pcall(GroupService.GetGroupsAsync, GroupService, player.UserId)
		if ok2 and type(groups) == "table" then
			for _, g in groups do
				if type(g) == "table" and g.Id == id then
					return true
				end
			end
			return false
		end
		return if ok then false else nil
	end
	return if ok then false else nil
end

-- Pay the group piece if this player is a member and has not had it (answers on the row when `tapped`)
local function checkGroup(player: Player, tapped: boolean)
	if not P.on or P.group.id == 0 then
		if tapped then
			result(player, "group", "off")
		end
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end
	if profile.promo.group == 1 then
		if tapped then
			result(player, "group", "claimed", P.group.piece)
		end
		return
	end
	local yes = inGroup(player, tapped)
	if player.Parent ~= Players then
		return
	end
	if yes == nil then
		if tapped then
			result(player, "group", "error")
		end
		return
	end
	member[player] = yes
	profile = DataService.get(player) -- the call yields: read the profile again
	if not profile then
		return
	end
	if yes and not DataService.isSaving(player) then
		if tapped then
			result(player, "group", "save")
		end
		return
	end
	if PromoRules.group(Config, profile.promo, yes) then
		local new = payPiece(player, profile, P.group.piece)
		DataService.changed(player)
		DataService.saveSoon(player)
		Analytics.event(player, "promo_claim", PromoRules.event("group", nil))
		result(player, "group", if new then "ok" else "owned", P.group.piece)
		send(player)
	elseif tapped then
		result(player, "group", if yes then "claimed" else "notMember", P.group.piece)
		send(player)
	end
end

local function redeem(player: Player, raw: string)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	if not DataService.isSaving(player) then
		result(player, "code", "save")
		return
	end
	local t = wrongTries[player] or {}
	wrongTries[player] = t
	local now = os.clock()
	local can, left = PromoRules.canTry(Config, t, now)
	if not can then
		result(player, "code", "wait", nil, math.ceil(left))
		return
	end
	local r = PromoRules.redeem(Config, profile.promo, raw, today(), studio())
	if PromoRules.wrong(r.reason) then
		PromoRules.fail(t, now)
	end
	if not r.ok or not r.row then
		result(player, "code", r.reason)
		return
	end
	local row = r.row :: PromoRules.Row
	local new = payPiece(player, profile, row.piece)
	DataService.changed(player)
	DataService.saveSoon(player)
	Analytics.event(player, "promo_claim", PromoRules.event("code", row))
	result(player, "code", if new then "ok" else "owned", row.piece)
	send(player)
end

-- Studio (DevService): 1 forget this account's claims (codes and the group piece's mark), 2 pay the group
-- piece as if a member (needs a group id)
function PromoService.dev(player: Player, what: number)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	if what == 1 then
		profile.promo = PromoRules.clean(nil)
		wrongTries[player] = nil
		lastCheck[player] = nil
	elseif what == 2 then
		if PromoRules.group(Config, profile.promo, true) then
			local new = payPiece(player, profile, P.group.piece)
			result(player, "group", if new then "ok" else "owned", P.group.piece)
		end
	end
	DataService.changed(player)
	send(player)
end

function PromoService.init()
	Net.on("PromoOpen", send)
	Net.on("PromoRedeem", redeem)
	Net.on("PromoGroup", function(player: Player)
		local now = os.clock()
		local last = lastCheck[player]
		if last and now - last < P.group.recheck then
			result(player, "group", "wait", nil, math.ceil(P.group.recheck - (now - last)))
			return
		end
		lastCheck[player] = now
		checkGroup(player, true)
	end)
	DataService.Loaded:Connect(function(player: Player)
		task.spawn(checkGroup, player, false)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		wrongTries[player] = nil
		lastCheck[player] = nil
		member[player] = nil
	end)
end

return PromoService
