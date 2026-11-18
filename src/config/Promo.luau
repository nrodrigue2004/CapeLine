-- Promo: the group-join cosmetic and creator codes (spec: Update 1 > "group rewards and creator codes"; gap
-- check G12, work package WP10). Pure data; Shared.PromoRules has the rules, PromoService pays, SettingsMenu
-- has the REWARDS rows.
-- * Both are OFF until nate sets them (Launch Checklist): `group.id` 0 hides the group row, an empty `codes`
--   list hides the code box. Nothing here needs a new build of anything else.
-- * Rewards are existing creator pieces from the "drop" pool (Config.Creator: earnable from Epic and
--   Legendary drops, never sold, looks only). A test refuses any other piece, so a code can never hand out
--   a sold piece, a stat or a piece meant for a level, rank, mission or boss.
-- * Codes are a FIXED list: a typed code only ever matches one of these rows (Shared.PromoRules.find). It is
--   never filtered text, never sent to anyone else and never shown on any screen but the typer's own box.
-- * Each code pays once per account, forever (a claimed code stays on the save even after its row is gone,
--   so putting the same code back never pays twice). The group piece pays once per account too, and stays
--   yours if you leave the group (CLAUDE.md rule 6).
return {
	on = true,

	-- Typed codes: A to Z and 0 to 9 only (the box drops anything else as you type and upper-cases letters),
	-- minLength to maxLength characters. The remote takes at most `rawMax` characters.
	minLength = 3,
	maxLength = 12,
	rawMax = 20,

	-- Wrong codes (not on the list, or not a code at all): after `n` inside `window` seconds the box answers
	-- "wait" until the oldest one is `window` seconds old (on top of the remote's own rate limit).
	tries = { n = 5, window = 60 },

	-- The Roblox group (nate's community group). id 0 = off. A member gets `piece` once per account; the
	-- server checks with Player:IsInGroup (in a pcall) when the save loads and when CHECK is tapped (CHECK
	-- also asks GroupService:GetGroupsAsync, because IsInGroup can keep an answer from earlier in the session).
	group = {
		id = 0, -- NATE: the group id from the group's page (roblox.com/communities/<id>/...)
		piece = "Spark Badge", -- a suit emblem in the game's spark mark
		name = "the Capeline group", -- shown on the row (PLACEHOLDER NAME until the group is made)
		recheck = 20, -- seconds between CHECK taps (the server's own wait, any rate the remote allows)
	},

	-- Creator codes, each { code, piece, starts?, ends?, tag? }:
	-- * code: 3 to 12 of A to Z and 0 to 9 (upper case), unique in this list and `studio`;
	-- * piece: a "drop" creator piece by its name (Config.Creator);
	-- * starts / ends: optional "YYYY-MM-DD" UTC dates; the code works from 00:00 UTC on `starts` to the end of
	--   23:59:59 UTC on `ends`;
	-- * tag: optional short id for the analytics field (letters, digits, "_"), else the code itself.
	-- Only ever append; a removed code's claims stay on every save it paid.
	codes = {
		-- Example (not live): a creator's launch code, January only
		-- { code = "SKYLINE", piece = "Fox Mask", starts = "2027-01-01", ends = "2027-01-31", tag = "launch" },
	},

	-- Codes that work only in Studio (RunService:IsStudio), for the Studio test list; never on a live server
	studio = {
		{ code = "STUDIOTEST", piece = "Clover Badge", tag = "studio" },
		{ code = "STUDIOOLD", piece = "Moon Badge", ends = "2026-01-01", tag = "studio_old" },
	},
}
