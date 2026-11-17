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
		{ id = "music", name = "Music", kind = "range", lo = 0, hi = 10, step = 1, default = 7 },
		{ id = "sfx", name = "Sound effects", kind = "range", lo = 0, hi = 10, step = 1, default = 8 },
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
	},
	maxMutes = 50, -- muted players kept on the save (user ids)
	sendDelay = 0.6, -- seconds the device waits after the last change before sending (a slider drag sends once)
}
