-- TravelStyles: how a mobility looks and sounds while moving (spec: Hero MMO features > Travel power styles;
-- H8). Never how fast it is: a style is a trail, a take-off burst and a landing effect (and for swing, the
-- line itself), drawn on every screen by TravelStyleFx from the TravelStyle attribute. Pure data.
-- 6 styles per mobility (Config.Move.mobilityOrder), 30 in all. A style's id is fixed:
-- (mobility index - 1) * 6 + its place in the list; never reorder or delete one (saved in profile.mmo.travel
-- bits and in each hero's mmo.travel, one per mobility, 0 = the plain look).
-- Sources (looks only, nothing random):
--   earned "badge": every badge in a Badge Book group (Config.Badges group id `group`)
--   earned "mentor": any of your heroes finished a mentor's quest line (H6)
--   "shop": a Robux product in Config.Shop.products (travel<id>, 99 to 199 Robux; id 0 until nate makes it)
--   "pass": a Hero Pass reward (Config.Pass), season 1 (one on the free track, one on the paid track)
-- look: c1, c2 = colours; trail = width and life (s); burst = the take-off and landing effect kind:
--   "ring" (a flat ring), "sparks" (bright bits), "puff" (soft clouds), "petals" (flat petals), "ink" (dark
--   splats), "prism" (rainbow shards); glow = the trail glows (LightEmission).
-- PLACEHOLDER ART: engine Trails and ParticleEmitters with default textures until the effects pass.
local function st(
	name: string,
	source: string,
	extra: { [string]: any },
	c1: { number },
	c2: { number },
	burst: string,
	width: number,
	life: number,
	glow: number
): { [string]: any }
	local row = {
		name = name,
		source = source,
		c1 = c1,
		c2 = c2,
		burst = burst,
		width = width,
		life = life,
		glow = glow,
	}
	for k, v in extra do
		row[k] = v
	end
	return row
end

return {
	perMobility = 6,
	-- speeds (studs/s) where the trail shows on other heroes' screens, and where a burst counts as a take-off
	showAt = 30,
	burstAt = 55,
	landFall = 40, -- a fall this fast ends in the landing effect
	byMobility = {
		flight = {
			st(
				"Star Tail",
				"badge",
				{ group = "explore" },
				{ 255, 210, 120 },
				{ 255, 120, 60 },
				"sparks",
				1.6,
				0.7,
				0.9
			),
			st("Static", "mentor", {}, { 150, 220, 255 }, { 255, 255, 255 }, "sparks", 0.8, 0.35, 1),
			st(
				"Ink Splash",
				"shop",
				{ product = "travel3" },
				{ 30, 30, 40 },
				{ 90, 90, 110 },
				"ink",
				1.4,
				0.6,
				0
			),
			st(
				"Petal Storm",
				"shop",
				{ product = "travel4" },
				{ 255, 160, 200 },
				{ 255, 230, 240 },
				"petals",
				1.2,
				0.8,
				0.3
			),
			st(
				"Ghost Fire",
				"pass",
				{ track = "free" },
				{ 120, 255, 200 },
				{ 40, 160, 255 },
				"puff",
				1.5,
				0.6,
				0.8
			),
			st(
				"Prism",
				"pass",
				{ track = "paid" },
				{ 255, 255, 255 },
				{ 200, 160, 255 },
				"prism",
				1.4,
				0.7,
				1
			),
		},
		speed = {
			st(
				"Afterimage",
				"badge",
				{ group = "combat" },
				{ 200, 220, 255 },
				{ 120, 140, 200 },
				"ring",
				2.2,
				0.25,
				0.4
			),
			st("Static Dash", "mentor", {}, { 150, 220, 255 }, { 255, 255, 255 }, "sparks", 1, 0.3, 1),
			st(
				"Ink Sprint",
				"shop",
				{ product = "travel9" },
				{ 30, 30, 40 },
				{ 90, 90, 110 },
				"ink",
				1.8,
				0.4,
				0
			),
			st(
				"Petal Rush",
				"shop",
				{ product = "travel10" },
				{ 255, 160, 200 },
				{ 255, 230, 240 },
				"petals",
				1.6,
				0.5,
				0.3
			),
			st(
				"Ghost Fire Run",
				"pass",
				{ track = "free" },
				{ 120, 255, 200 },
				{ 40, 160, 255 },
				"puff",
				1.8,
				0.4,
				0.8
			),
			st(
				"Prism Streak",
				"pass",
				{ track = "paid" },
				{ 255, 255, 255 },
				{ 200, 160, 255 },
				"prism",
				2,
				0.35,
				1
			),
		},
		leap = {
			st(
				"Shockwave",
				"badge",
				{ group = "defeat" },
				{ 255, 200, 120 },
				{ 200, 140, 90 },
				"ring",
				0.9,
				0.4,
				0.2
			),
			st("Static Bound", "mentor", {}, { 150, 220, 255 }, { 255, 255, 255 }, "sparks", 0.8, 0.35, 1),
			st(
				"Ink Arc",
				"shop",
				{ product = "travel15" },
				{ 30, 30, 40 },
				{ 90, 90, 110 },
				"ink",
				1.2,
				0.6,
				0
			),
			st(
				"Petal Leap",
				"shop",
				{ product = "travel16" },
				{ 255, 160, 200 },
				{ 255, 230, 240 },
				"petals",
				1,
				0.8,
				0.3
			),
			st(
				"Ghost Fire Leap",
				"pass",
				{ track = "free" },
				{ 120, 255, 200 },
				{ 40, 160, 255 },
				"puff",
				1.2,
				0.6,
				0.8
			),
			st(
				"Prism Bound",
				"pass",
				{ track = "paid" },
				{ 255, 255, 255 },
				{ 200, 160, 255 },
				"prism",
				1.2,
				0.7,
				1
			),
		},
		acrobat = {
			st(
				"Ribbon Flip",
				"badge",
				{ group = "story" },
				{ 255, 90, 90 },
				{ 255, 200, 90 },
				"ring",
				0.7,
				0.6,
				0.3
			),
			st("Static Flip", "mentor", {}, { 150, 220, 255 }, { 255, 255, 255 }, "sparks", 0.7, 0.35, 1),
			st(
				"Ink Flourish",
				"shop",
				{ product = "travel21" },
				{ 30, 30, 40 },
				{ 90, 90, 110 },
				"ink",
				0.9,
				0.6,
				0
			),
			st(
				"Petal Twirl",
				"shop",
				{ product = "travel22" },
				{ 255, 160, 200 },
				{ 255, 230, 240 },
				"petals",
				0.9,
				0.8,
				0.3
			),
			st(
				"Ghost Fire Flip",
				"pass",
				{ track = "free" },
				{ 120, 255, 200 },
				{ 40, 160, 255 },
				"puff",
				1,
				0.6,
				0.8
			),
			st(
				"Prism Twist",
				"pass",
				{ track = "paid" },
				{ 255, 255, 255 },
				{ 200, 160, 255 },
				"prism",
				1,
				0.6,
				1
			),
		},
		swing = {
			st(
				"Steel Cable",
				"badge",
				{ group = "groups" },
				{ 190, 200, 215 },
				{ 120, 130, 150 },
				"ring",
				0.5,
				0.4,
				0.1
			),
			st("Static Line", "mentor", {}, { 150, 220, 255 }, { 255, 255, 255 }, "sparks", 0.6, 0.35, 1),
			st(
				"Ink Line",
				"shop",
				{ product = "travel27" },
				{ 30, 30, 40 },
				{ 90, 90, 110 },
				"ink",
				0.8,
				0.5,
				0
			),
			st(
				"Petal Vine",
				"shop",
				{ product = "travel28" },
				{ 120, 200, 110 },
				{ 255, 160, 200 },
				"petals",
				0.8,
				0.7,
				0.3
			),
			st(
				"Ghost Fire Line",
				"pass",
				{ track = "free" },
				{ 120, 255, 200 },
				{ 40, 160, 255 },
				"puff",
				0.9,
				0.5,
				0.8
			),
			st(
				"Prism Line",
				"pass",
				{ track = "paid" },
				{ 255, 255, 255 },
				{ 200, 160, 255 },
				"prism",
				0.9,
				0.6,
				1
			),
		},
	},
}
