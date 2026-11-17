-- RepService: "The city remembers" (nate's lore, build plan step 12; Config.Remembers, Shared.RepTiers).
-- * Own-side reputation (Vigil Trust for heroes, Syndicate Fear for villains) from the repeatable activities:
--   incidents cleared, contracts finished, world events (side-vs-side events pay more, the winners more again)
--   and side quest chain steps (StoryService.addRep "side"; Act 1 already pays it for missions and choices).
-- * Watches each hero's own tier (every 2 s and on every gain): the player's RepTier attribute (citizens, the
--   radio and the HUD read it), a toast of what a new tier opened (Gizmo's side styles, the title, the hideout
--   upgrade), and the news naming a hero at Config.Remembers.mention.tier and up (when they reach it, and once a
--   session when they join). The news fact carries only safe name ids; every device builds the line.
-- * Dev: set your own tier (the points at that rank's threshold).
-- Nothing here changes a stat: the tiers open looks, a title and props only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local RepTiers = require(Shared:WaitForChild("RepTiers"))
local StoryPlan = require(Shared:WaitForChild("StoryPlan"))

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local IncidentService = require(script.Parent.IncidentService)
local EventService = require(script.Parent.EventService)
local SideQuestService = require(script.Parent.SideQuestService)
local StoryService = require(script.Parent.StoryService)
local NewsService = require(script.Parent.NewsService)
local HeroService = require(script.Parent.HeroService)
local HqService = require(script.Parent.HqService)

local RepService = {}

local R = Config.Remembers
local seen: { [Player]: { tier: number, slot: number } } = {}
local joinedNews: { [Player]: boolean } = {}

local function newsKind(track: string): string
	return if track == "syndicate" then "repSyndicate" else "repVigil"
end

-- Read the hero's own tier; announce a new one
local function refresh(player: Player)
	local c = StoryService.char(player)
	local profile = DataService.get(player)
	if not c or not profile then
		return
	end
	local track = RepTiers.track(Config, c.side)
	local tier = RepTiers.tier(Config, c, track)
	player:SetAttribute("RepTier", tier)
	local slot = profile.active or 1
	local prev = seen[player]
	seen[player] = { tier = tier, slot = slot }
	if prev and prev.slot == slot and tier > prev.tier then
		for t = prev.tier + 1, tier do
			local u = RepTiers.unlocks(Config, track, t)
			Net.fire("Toast", player, {
				id = "repUnlocks",
				track = track,
				tier = t,
				hideout = u.hideout,
				title = u.title,
				styles = #u.styles,
			})
		end
		if RepTiers.mention(Config, tier) then
			NewsService.post(newsKind(track), player, tier)
		end
		HqService.redraw(player)
	elseif not prev and not joinedNews[player] and RepTiers.mention(Config, tier) then
		-- once a session: the city notices a high-tier hero is out tonight
		joinedNews[player] = true
		task.delay(R.mention.joinDelay, function()
			if player.Parent then
				NewsService.post(newsKind(track), player, tier)
			end
		end)
	end
end

-- Own-side reputation from an activity (nothing in a mission pocket's story run: those pay their own)
function RepService.add(player: Player, amount: number)
	if amount <= 0 then
		return
	end
	StoryService.addRep(player, "side", amount)
	refresh(player)
end

-- Studio: set your own side's tier (0 to 5) to its rank's points
function RepService.devTier(player: Player, tier: number)
	local c = StoryService.char(player)
	if not c then
		return
	end
	local track = RepTiers.track(Config, c.side)
	c.rep[StoryPlan.repIndex(Config, track)] =
		RepTiers.need(Config, math.clamp(math.floor(tier), 0, RepTiers.MAX))
	DataService.changed(player)
	StoryService.changed(player)
	refresh(player)
	HqService.redraw(player)
end

function RepService.init()
	local E = R.earn
	IncidentService.Cleared:Connect(function(inc: any)
		for heroId in inc.helpers or {} do
			local h = HeroService.byId(heroId)
			if h and h.player then
				RepService.add(h.player, E.incident)
			end
		end
	end)
	EconomyService.Earned:Connect(function(player: Player, action: string)
		if action == "contract" then
			RepService.add(player, E.contract)
		end
	end)
	EventService.Paid:Connect(function(player: Player, _id: string, _result: string?, rep: number)
		RepService.add(player, rep)
	end)
	SideQuestService.StepPaid:Connect(function(player: Player, finale: boolean)
		RepService.add(player, if finale then E.sideFinale else E.sideStep)
	end)
	DataService.Loaded:Connect(function(player)
		task.delay(3, function()
			if player.Parent then
				refresh(player)
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		seen[player] = nil
		joinedNews[player] = nil
	end)
	-- missions, choices and slot switches change the tier too: a light poll keeps the attribute right
	task.spawn(function()
		while true do
			task.wait(2)
			for _, player in Players:GetPlayers() do
				if seen[player] then
					refresh(player)
				end
			end
		end
	end)
end

return RepService
