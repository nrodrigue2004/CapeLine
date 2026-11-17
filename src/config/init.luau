--!strict
-- Config: every tuning number in the game (spec: "Every number is a starting value to tune, kept in
-- server-side tables"). Each child module is pure data named after a spec table, so numbers change without
-- touching code. This index requires them all so callers write Config.Move.flight, in Studio and in Lune.

local NAMES = {
	"Version",
	"Move",
	"Stats",
	"Classes",
	"Abilities",
	"Enemies",
	"Combat",
	"City",
	"Presets",
	"Net",
	"Safety",
	"Fx",
	"Ui",
	"Dev",
	"Places",
	"Gear",
	"Loot",
	"Economy",
	"Data",
	"World",
	"Destruction",
	"Incidents",
	"Contracts",
	"Events",
	"Heroic",
	"Boss",
	"Story",
	"Pvp",
	"Creator",
	"Shop",
	"Hq",
	"Settings",
	"Squad",
	"Audio",
	"Analytics",
	"Deep",
	"ArtFit",
	"HeroRig",
	"TrooperArt",
	"StreetArt",
	"NpcLooks",
	"Weapons",
}

local Config: { [string]: any } = {}
for _, name in NAMES do
	if script then
		Config[name] = require((script :: any):WaitForChild(name))
	else
		Config[name] = (require :: any)("./" .. name)
	end
end

-- The weapons' moves join the ability table (list and byNum, never order, so loadouts and the 136 powers
-- stay as they are) and CombatService casts them like any power (Config.Weapons.skills)
do
	local A, W = Config.Abilities, Config.Weapons
	for weaponId, rows in W.skills do
		for key, src in rows do
			local row = table.clone(src)
			row.num = W.numBase + weaponId * 5 + (key - 1)
			row.id = "W" .. weaponId .. (if key == 1 then "M1" else W.keys[key - 1])
			row.set = "Weapon"
			row.slot = if key == 1 then "basic" else "skill"
			row.weapon = weaponId
			row.weaponKey = if key == 1 then "M1" else W.keys[key - 1]
			row.pts = 0
			A.list[row.id] = row
			A.byNum[row.num] = row
		end
	end
end

return Config
