local Config = require("../../src/config")
local HeroAnim = require("../../src/shared/HeroAnim")
local CP = require("../../src/shared/CarryPose")
local body = CP.bodyFromRig(Config.HeroRig)
local function f(v) return string.format("(%.2f %.2f %.2f)", v[1], v[2], v[3]) end
for _, c in { "carry", "carryHand", "carryMind" } do
	local P = CP.parts(body, HeroAnim.sample(c, 0))
	print(c, "R tip", f(CP.tip(body, P, "Right")), "L tip", f(CP.tip(body, P, "Left")), "head", f(P.Head.p))
end
local T = Config.Throw
for _, k in { { "car", { 5, 4, 12 }, true }, { "dumpster", { 6, 4, 3.5 } }, { "vending", { 3, 6, 2.4 } }, { "bench", { 5, 2.6, 1.8 } }, { "lampPost", { 0.8, 10, 0.8 } }, { "trashCan", { 2, 3, 2 } } } do
	for _, set in { "Titan", "Mind" } do
		local g = CP.gripOf(T, k[1], set)
		local h = CP.hold(T, body, g, HeroAnim.sample(CP.CLIP[g], 0), k[2], nil, k[3])
		print(k[1], set, g, "box", f(h.box.p), "ext", f(h.size))
	end
end
