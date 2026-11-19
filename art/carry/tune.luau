local Config = require("../../src/config")
local CP = require("../../src/shared/CarryPose")
local body = CP.bodyFromRig(Config.HeroRig)
for _, s in { 160, 165, 170, 175 } do
	for _, e in { 0, 10, 20 } do
		for _, z in { 10, 18 } do
			local P = CP.parts(body, { RightShoulder = { s, 0, z, 0 }, LeftShoulder = { s, 0, -z, 0 }, RightElbow = { e, 0, 0, 0 }, LeftElbow = { e, 0, 0, 0 } })
			local t = CP.tip(body, P, "Right")
			print(s, e, z, string.format("%.2f %.2f %.2f", t[1], t[2], t[3]))
		end
	end
end
