--!strict
-- FunnelDef: Capeline's stage ladder for the studio-wide FunnelKit (the
-- Progress funnel and the "stage" on session_start and session_end). A stage counts only when every stage
-- before it is reached too. Levels and story read the player's best character (alts don't lower it).
-- The first-session steps stay in the Opening onboarding funnel (AnalyticsSchema.FUNNELS.Opening).
-- Once live, only ADD stages at the end: the dashboard keys steps by number.

local Config = if script
	then require(script.Parent.Parent:WaitForChild("Config"))
	else (require :: any)("../config")

local FunnelDef = {}

local function best(profile: any, read: (any) -> number): number
	local top = 0
	for _, character in profile.characters or {} do
		top = math.max(top, read(character))
	end
	return top
end

function FunnelDef.level(profile: any): number
	return best(profile, function(c)
		return c.level or 1
	end)
end

local function level(n: number)
	return function(profile: any): boolean
		return FunnelDef.level(profile) >= n
	end
end

FunnelDef.stages = {
	{
		name = "Joined",
		reached = function()
			return true
		end,
	},
	{
		name = "Opening done",
		reached = function(p)
			return best(p, function(c)
				return c.story and c.story.opening or 0
			end) >= 1
		end,
	},
	{
		name = "Hero created",
		reached = function(p)
			return best(p, function(c)
				return c.created or 0
			end) >= 1
		end,
	},
	{ name = "Level 5", reached = level(5) },
	{
		name = "First world boss",
		reached = function(p)
			return (p.stats and p.stats.bossesJoined or 0) >= 1
		end,
	},
	{ name = "Level 10", reached = level(10) },
	{ name = "Level 15", reached = level(15) },
	{ name = "Level 20", reached = level(20) },
	{
		name = "Act 1 done",
		reached = function(p)
			return best(p, function(c)
				return c.story and c.story.act or 1
			end) >= 2
		end,
	},
	{ name = "Level 30", reached = level(30) },
	{ name = "Level 40", reached = level(40) },
	-- the level cap (50 since 2026-11-17, before any launch, so inserting it here renumbers nothing live)
	{ name = "Level " .. Config.Stats.levelCap, reached = level(Config.Stats.levelCap) },
	{
		name = "First legacy",
		reached = function(p)
			return best(p, function(c)
				return c.legacy or 0
			end) >= 1
		end,
	},
}

FunnelDef.returns = { 1, 2, 3, 5, 10, 20 }

return FunnelDef
