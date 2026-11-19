-- Writes art/export/wrecks/layout.json for art/blender/wrecks.py: every robot kind that leaves a wreck
-- (Shared.ThrowMath.canWreck) with its heap box (ThrowMath.wreckSize: x wide, y tall, z deep), its colours (suit,
-- trim, the endoskeleton's metal as EnemyRenderer mixes it, eyes, cape) and its gear flags, from the game's own data.
--   lune run art/wrecks/layout.luau
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Config = require("../../src/config")
local ThrowMath = require("../../src/shared/ThrowMath")

local LOOK = Config.Enemies.look
local function mix(a, b, t)
	return {
		math.floor(a[1] + (b[1] - a[1]) * t + 0.5),
		math.floor(a[2] + (b[2] - a[2]) * t + 0.5),
		math.floor(a[3] + (b[3] - a[3]) * t + 0.5),
	}
end
local out = {}
for kind, cfg in Config.Enemies do
	if type(cfg) == "table" and cfg.body and ThrowMath.canWreck(cfg) then
		local b = cfg.body
		local sx, sy, sz = ThrowMath.wreckSize(Config.Throw, cfg)
		local flags = {}
		for k, v in b do
			if v == true then
				table.insert(flags, k)
			end
		end
		table.sort(flags)
		out[kind] = {
			frame = { sx, sy, sz },
			height = b.height,
			build = b.build or "normal",
			suit = b.suit or b.metal,
			trim = b.trim or b.eye,
			metal = mix(LOOK.endo, b.metal, 0.35),
			dark = mix(b.metal, { 0, 0, 0 }, 0.45),
			eye = b.eye,
			cape = b.cape,
			jet = b.jetColor,
			flags = flags,
		}
	end
end
fs.writeDir("art/export/wrecks")
fs.writeFile("art/export/wrecks/layout.json", serde.encode("json", out))
local n = 0
for _ in out do
	n += 1
end
print("wreck layout:", n, "kinds")
