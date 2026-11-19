-- Costume contests (spec: Hero MMO features > Costume contests; H7). Pure data, tuned in the playtest.
-- Every 30 minutes (on the clock, the same on every server) a contest opens on a stage at a corner of the
-- hub plaza (the Beacon Tower's square). Call: a banner and a map ping 60 s before; up to 8 players step onto
-- the pads (or press ENTER near the stage). Show: 10 s in the spotlight each, posing with any emote they own.
-- Vote: everyone else gets a vote card (1 to 5 stars per contestant); players far away vote from the banner.
-- Results: the top 3 take the podium with confetti. Rules: Shared.ContestRules; ContestService; ContestHud.
-- Looks come from the creator and the shop, so contests show off looks; nothing here touches stats.
-- PLACEHOLDER ART: the stage, pads, podium and spotlight are simple parts until the Blender pass.
return {
	every = 1800, -- seconds between contests (on os.time, so servers agree)
	offset = 900, -- the first call of each half hour comes this many seconds in (clear of the boss timer)
	call = 60, -- the banner and map ping this long before the show; entries open
	show = 10, -- seconds in the spotlight per contestant
	vote = 20, -- seconds of voting after the last contestant (votes open with the first spotlight)
	results = 12, -- seconds on the podium
	bannerLife = 12, -- fix-hud: seconds the call, show and vote banner stays up after each new step (then folds; X too)
	maxEntries = 8,
	minEntries = 3,
	minVoters = 5,
	voteAfter = 120, -- seconds on the server before your votes count
	squadWeight = 0.5, -- a squadmate's vote for you counts half
	winEvery = 3600, -- a player wins at most once an hour (the next best takes first)
	enterRange = 60, -- studs from the stage to step on (ENTER on the banner)
	pay = {
		first = 1500, -- Credits
		second = 900,
		third = 600,
		entry = 150, -- every contestant
		showedUp = 100, -- a skipped contest (too few contestants or voters) pays this to those who stepped on
	},
	-- the stage: at the plaza corner, this far from the tower's centre on both axes (studs)
	stage = { corner = 50, size = 26, height = 2, padGap = 6, podium = { 4, 3, 2 } },
	-- fixed themes (no free text); one per contest, picked from the half hour's number
	themes = {
		"Fire and Ice",
		"Retro Hero",
		"Villain Chic",
		"Ocean",
		"Neon",
		"Robot Fan",
		"Night Patrol",
		"Sunny Day",
		"Storm Front",
		"Galaxy",
		"All Gold",
		"Shadow Play",
		"Jungle",
		"Desert Wind",
		"Winter Cape",
		"Street Style",
		"Royal",
		"Spooky",
		"Sports Hero",
		"Mad Scientist",
		"Sky Pirate",
		"Speedster",
		"Heavy Armor",
		"Mystic",
		"Big Hat Energy",
		"Monochrome",
		"Rainbow",
		"Masked",
		"Team Colours",
		"Your Origin",
	},
}
