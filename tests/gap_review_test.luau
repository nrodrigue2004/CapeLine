-- The gap review (2026-11-19, own file): runtime bugs found reading today's six merged packages (6078fcb..gaps1)
-- before nate's Studio playtest. Device code cannot run in Lune, so each fix is checked by its source, as
-- tests/review_test.luau does. Called from tests/run.luau:
--   require("./gap_review_test")({ test = test, check = check, Config = Config })
-- ONLY="GapReview" runs just these.

return function(T: any)
	local test, check = T.test, T.check
	local fs = require("@lune/fs")

	local function has(text: string, needle: string): boolean
		return string.find(text, needle, 1, true) ~= nil
	end

	test(
		"GapReview: a pocket's lights sit where PocketDress put them (no WorldPosition on a loose attachment)",
		function()
			-- Attachment.WorldPosition set before the attachment has a parent is taken as its Position, so once
			-- parented to the anchor (at the pocket's centre) every light landed a whole pocket centre away
			local src = fs.readFile("src/client/Controllers/PocketDecor.luau")
			check(
				not has(src, "a.WorldPosition ="),
				"PocketDecor sets no WorldPosition on an unparented attachment"
			)
			check(
				has(src, "a.Position = anchor.CFrame:PointToObjectSpace(Vector3.new(li.x, li.y, li.z))"),
				"the light's attachment is placed relative to its anchor"
			)
			-- the anchor's place is set before the attachments are placed against it
			local anchorAt = string.find(src, "anchor.CFrame = CFrame.new(l.cx, l.cy, l.cz)", 1, true)
			local lightAt = string.find(src, "a.Position = anchor.CFrame", 1, true)
			check(anchorAt ~= nil and lightAt ~= nil and anchorAt < lightAt, "the anchor is placed first")
		end
	)
end
