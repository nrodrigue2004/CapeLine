-- The lock-on marker's layout from the game's own rules (Shared.LockRules.marker) for the preview:
-- `lune run art/lock/marker.luau` writes art/lock/marker.json, then `python3 art/lock/marker.py` draws
-- art/preview/lock_marker.png (the soft lock and three moments of the hard lock, on a light and a dark sky).
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Config = require("../../src/config")
local LockRules = require("../../src/shared/LockRules")

local M = Config.Combat.lock.marker
local out = { colors = { soft = M.soft, hard = M.hard, ink = M.ink }, frames = {} }
for _, f in { { false, 0 }, { true, 0 }, { true, 0.35 }, { true, 0.7 } } do
	local m = LockRules.marker(M, 96, f[2], f[1])
	table.insert(out.frames, { hard = f[1], t = f[2], bars = m.bars, diamond = m.diamond or 0, px = 96 })
end
fs.writeFile("art/lock/marker.json", serde.encode("json", out, true))
print("wrote art/lock/marker.json")
