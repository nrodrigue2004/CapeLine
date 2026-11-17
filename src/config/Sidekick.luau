-- Sidekicking, missions only (spec: Hero MMO features > Sidekicking; H4). Pure data, tuned in the playtest.
-- nate's rule: only inside mission pockets (Act 1 missions, Nemesis Showdowns and task forces). The open
-- world, contracts, incidents, events, the world boss and PvP never raise anyone.
-- Rules live in Shared.SidekickRules; MissionService applies them.
return {
	gap = 1, -- a member more than this many levels below the mission level is a sidekick
	raiseTo = -1, -- a sidekick counts as the mission level plus this (mission level minus 1)
	renownBonus = 0.2, -- a sidekick's Renown in the pocket
	mentorBonus = 0.1, -- the top member's Renown when a sidekick is `mentorGap` or more levels lower
	mentorGap = 5,
	-- robots and bosses in a pocket get this much more health per party size (1 to 4 players)
	partyHp = { 1, 1.6, 2.2, 2.8 },
	badge = "SIDEKICK", -- the star badge over a sidekick's name plate
}
