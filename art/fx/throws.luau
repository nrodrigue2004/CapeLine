-- Writes the throw and smash particle plans (gap-fx3, 2026-11-19; Config.Fx.lib.throw through Shared.FxPlan, per
-- preset) to art/export/fx/throws.json, for art/fx/throws.py to draw art/preview/fx_throws.png.
-- Run from the repo root:  lune run art/fx/throws.luau && python3 art/fx/throws.py
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Config = require("../../src/config")
local FxPlan = require("../../src/shared/FxPlan")
local L = Config.Fx.lib

local out = { kinds = {}, plans = {}, radius = {} }
for name, k in L.kinds do
	out.kinds[name] = {
		file = L.textures[k.tex].file,
		flip = L.textures[k.tex].flip,
		light = k.light,
		size = k.size,
		life = k.life,
		speed = k.speed,
		spread = k.spread,
		rise = k.rise,
		drag = k.drag,
		face = k.face,
	}
end
local moments = {
	{ "grab", "grab", nil },
	{ "land_light", "land", "light" },
	{ "land_medium", "land", "medium" },
	{ "land_heavy", "land", "heavy" },
	{ "smash", "smash", nil },
	{ "back", "back", nil },
}
for _, preset in { "low", "medium", "high" } do
	out.plans[preset] = {}
	for _, m in moments do
		local counts = {}
		for _, e in FxPlan.throwPlan(L, m[2], L.scale[preset], m[3]) do
			counts[e.kind] = e.count
		end
		out.plans[preset][m[1]] = counts
	end
end
for w, row in Config.Throw.weights do
	out.radius[w] = row.radius
end
fs.writeFile("art/export/fx/throws.json", serde.encode("json", out, true))
print("wrote art/export/fx/throws.json")
