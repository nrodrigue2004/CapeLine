-- Archetypes (nate, 2026-11-16: "a couple large classes that have subclasses"). A hero picks an archetype,
-- one of its paths (the power set, Abilities.sets) and a mobility (Move.mobility). The archetype sets the base
-- numbers and the passive; the path sets the 8 abilities. Old saves move over in ProfileSchema (Bruiser ->
-- Powerhouse, Blaster -> Elemental, Speedster -> Rogue, Controller -> Mystic). Path ids: the 5 launch sets keep
-- their ids so saves, combos and gear stay put (Volt is shown as Storm, Titan as Brawler, Pulse as Gravity,
-- Blade as Swordsman; Abilities.setName).
return {
	order = { "Elemental", "Rogue", "Powerhouse", "Mystic" },
	Elemental = {
		name = "Elemental",
		role = "Ranged and area damage",
		healthMult = 0.95,
		damageMult = 1.1,
		basicRange = 60,
		paths = { "Volt", "Frost", "Fire", "Earth", "Tide" },
		-- Attunement: every 5th hit is 30% stronger (drawn as a crit)
		passive = { id = "Attunement", everyNth = 5, bonus = 0.30 },
	},
	Rogue = {
		name = "Rogue",
		role = "Burst damage and tricks",
		healthMult = 0.95,
		damageMult = 1.15,
		cooldowns = -0.05,
		paths = { "Blade", "Gunslinger", "Gadgeteer", "Shadow" },
		-- Opening: a hit on a robot that is not fighting you (or from stealth) is a critical hit
		passive = { id = "Opening" },
	},
	Powerhouse = {
		name = "Powerhouse",
		role = "Tank and melee",
		healthMult = 1.35,
		damageMult = 0.9,
		taunt = 25,
		paths = { "Titan", "Martial", "Juggernaut", "Colossus" },
		passive = { id = "StandFirm", mitigation = 0.15 },
	},
	Mystic = {
		name = "Mystic",
		role = "Control and support",
		healthMult = 1.0,
		damageMult = 0.9,
		supportBonus = 0.25,
		ccBonus = 0.20,
		paths = { "Pulse", "Mind", "Spirit", "Light" },
		passive = { id = "Anchor", radius = 25, mitigation = 0.08 },
	},
	default = "Elemental",
	-- saves from before the archetypes
	renamed = { Bruiser = "Powerhouse", Blaster = "Elemental", Speedster = "Rogue", Controller = "Mystic" },
}
