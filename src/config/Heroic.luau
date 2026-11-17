-- Heroic tier (2026-11-17, nate: "way more content to keep players playing" with the level cap at 50). From
-- level 40 an incident, an event or a contract offer can roll Heroic: its robots spawn `levelBonus` levels
-- higher through the usual robot scaling (HP x (1 + 0.1 x (L - 1)), damage 20 + 4 x L), every squad gets
-- `extraUnits` more robot, and the clear pays `rewardMult` x the usual Credits and Renown (the same earn
-- maths, then this multiplier) plus a gear roll `gearLevels` item levels higher. The tracker, the markers and
-- the board show HEROIC. Rules: Shared.HeroicRules. Economy check (Decisions, 2026-11-17): at level 45 the
-- expected Renown bump over the play model is about +8% before the longer fights, so 40 to 50 stays near
-- 41 to 43 hours instead of 45. (tune)
return {
	on = true,
	minLevel = 40, -- the hero's level (events: the event's zone level, the median of the server)
	chance = { incident = 0.25, event = 0.3, contract = 0.34 }, -- per roll once the level is met
	levelBonus = 5, -- robots spawn this many levels higher
	extraUnits = 1, -- one more robot in every squad (the first row of a squad step)
	rewardMult = 1.5, -- Credits and Renown
	gearLevels = 2, -- the gear roll's zone level, capped at the level cap
	timeMult = 1.15, -- a Heroic incident gets 15% more time for the tougher squad
	color = { 200, 120, 255 }, -- the HEROIC tag on the tracker, markers and board
	tag = "HEROIC", -- fixed text, never free text
	-- what one Heroic roll adds to income in the economy check (HeroicRules.incomeBump): the share of
	-- contracts a hero takes Heroic when offered (most do: it is clearly marked and pays more)
	takeShare = { contract = 0.8 },
}
