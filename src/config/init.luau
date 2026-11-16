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
	"Boss",
	"Story",
	"Pvp",
	"Creator",
	"Shop",
	"Hq",
	"Settings",
	"Squad",
}

local Config: { [string]: any } = {}
for _, name in NAMES do
	if script then
		Config[name] = require((script :: any):WaitForChild(name))
	else
		Config[name] = (require :: any)("./" .. name)
	end
end

return Config
