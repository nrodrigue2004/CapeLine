-- Settings (spec: Screens and UI; Accessibility "Text size 100% to 160%, colorblind-safe markers, reduce
-- flashing, left-handed layout, controller support. Auto-aim on phones, optional tap-to-fly-to-marker,
-- one-hand flight mode"; save "Graphics preset, text size, left-handed, reduce flashing, mute list";
-- remote Settings.Set {key, value}). Saved per account; the device applies them at once.
-- keys: index order is the Settings.Set key number. kind "choice" lists its options, "toggle" is 0 or 1,
-- "range" is lo to hi in steps.
return {
	keys = {
		{
			id = "preset",
			name = "Graphics",
			kind = "choice",
			options = { "Auto", "Low", "Medium", "High" },
			default = 0,
		},
		{
			id = "textSize",
			name = "Text size",
			kind = "range",
			lo = 100,
			hi = 160,
			step = 10,
			default = 100,
			unit = "%",
		},
		{ id = "leftHanded", name = "Left-handed layout", kind = "toggle", default = 0 },
		{
			id = "reduceFlashing",
			name = "Reduce flashing (no shake or hit-pause)",
			kind = "toggle",
			default = 0,
		},
		{ id = "oneHand", name = "One-hand flight (right thumb, auto-turn)", kind = "toggle", default = 0 },
		{ id = "tapToFly", name = "Tap a map marker to fly there", kind = "toggle", default = 1 },
		{ id = "autoAim", name = "Auto-aim on touch", kind = "toggle", default = 1 },
		{ id = "music", name = "Music", kind = "range", lo = 0, hi = 10, step = 1, default = 2 }, -- nate 2026-11-20 (was 7)
		{ id = "sfx", name = "Sound effects", kind = "range", lo = 0, hi = 10, step = 1, default = 5 }, -- nate 2026-11-20 (was 8)
		{ id = "damageNumbers", name = "Damage numbers", kind = "toggle", default = 1 },
		-- phone pass (2026-11-17): the touch buttons' size on top of the fit to the screen (new keys go last:
		-- the index is the Settings.Set key number)
		{
			id = "buttonSize",
			name = "Button size (touch)",
			kind = "range",
			lo = 80,
			hi = 130,
			step = 10,
			default = 100,
			unit = "%",
		},
		-- lore step 6: Patch's open-world radio lines (story lines in missions and the prologue always play)
		{ id = "guideRadio", name = "Guide radio", kind = "toggle", default = 1 },
		-- lore step 7: the dynamic camera in fights and finishers (Config.Cinema.camera): Full, Reduced
		-- (half), Off; Reduce flashing still removes flashes and shakes on its own
		{
			id = "cameraMotion",
			name = "Camera motion",
			kind = "choice",
			options = { "Full", "Reduced", "Off" },
			default = 0,
		},
		-- nate's playtest 2026-11-19 (lock-on, nate decided both): the soft lock eases casts and the camera toward
		-- the best target in front; the hard lock is the LOCK toggle (middle mouse / Tab, R3, the LOCK button)
		{
			id = "softLock",
			name = "Soft lock-on (aim and camera ease to targets)",
			kind = "toggle",
			default = 1,
		},
		{ id = "hardLock", name = "Lock-on button (MMB or Tab, R3, LOCK)", kind = "toggle", default = 1 },
		-- fix-hud (nate's playtest of gaps7, 2026-11-19: "need a way to get rid of popups"): which popups show
		-- (Config.Ui.popups.modes): All, Important only (rewards and invites as small toasts), Off
		{
			id = "popups",
			name = "Popups",
			kind = "choice",
			options = { "All", "Important only", "Off" },
			default = 0,
		},
	},
	maxMutes = 50, -- muted players kept on the save (user ids)
	sendDelay = 0.6, -- seconds the device waits after the last change before sending (a slider drag sends once)
}
