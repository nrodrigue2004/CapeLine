-- Audio and the juice table (spec: Audio, VFX, juice and accessibility; Music). Pure data.
-- Every one of the 31 juice actions has a sound here and a visual somewhere in the client (tests check
-- both). `asset` is the licence-checked Creator Store id nate picks (Launch Checklist); until then a
-- `fallback` plays one of Roblox's own built-in client sounds (rbxasset://sounds, shipped with every
-- Roblox client, free to use), pitched per action so they differ. PLACEHOLDER SOUND until the ids land.
-- Groups: Music, Effects, Voice (volumes from Settings). Music ducks 40% for the boss siren and voices.

local B = "rbxasset://sounds/"

local function s(fallback: string?, volume: number, pitch: number?, extra: { [string]: any }?)
	local t =
		{ asset = 0, fallback = if fallback then B .. fallback else nil, volume = volume, pitch = pitch or 1 }
	for k, v in extra or {} do
		t[k] = v
	end
	return t
end

return {
	-- the juice table, in spec order: action id, sound, and where its visual is drawn (tests read `visual`)
	juice = {
		{ id = "leap", visual = "MoveFx" }, -- charge hum then whoosh; dust ring; FOV widens 6%
		{ id = "land", visual = "MoveFx" }, -- heavy thud; dust ring and crack; 0.1 s shake, vibration
		{ id = "glide", visual = "MoveFx" }, -- soft air; faint trail
		{ id = "flyCruise", visual = "MoveFx" }, -- wind that rises with speed; speed lines at boost
		{ id = "boost", visual = "MoveFx" }, -- burst; trail in your colour
		{ id = "basic", visual = "CombatFx" }, -- zap, punch or crackle by set; hit flash; number pop
		{ id = "cast", visual = "CombatFx" }, -- charge and release by set; coloured shape
		{ id = "super", visual = "CombatFx" }, -- big charge-up and boom; shockwave ring; screen punch
		{ id = "crit", visual = "CombatFx" }, -- higher ping; gold number 1.5x
		{ id = "defeat", visual = "JuiceFx" }, -- pop and clatter; sparks; Credit coin burst
		{ id = "rescue", visual = "JuiceFx" }, -- cheer and chime; safe zone glow; Renown pop
		{ id = "incidentClear", visual = "JuiceFx" }, -- short fanfare; medal stamp
		{ id = "collapse", visual = "BuildingFx" }, -- rumble; dust plume; camera rumble under 80 studs
		{ id = "crater", visual = "BuildingFx" }, -- crunch; decal for 30 s
		{ id = "clash", visual = "CombatFx" }, -- impact boom; both freeze 0.3 s; shockwave ring
		{ id = "vehicleFlip", visual = "VehicleFx" }, -- metal whoomp; dust
		{ id = "downed", visual = "PvpHud" }, -- muffled heartbeat; grey edge, pulse ring
		{ id = "revive", visual = "JuiceFx" }, -- rising chime; gold ring
		{ id = "pvpFlag", visual = "PvpFx" }, -- short horn; ring grows
		{ id = "levelUp", visual = "JuiceFx" }, -- rising bell; level badge spins; next unlock lights
		{ id = "skillRank", visual = "LoadoutScreen" }, -- click and chime; node fills; UI bounce
		{ id = "gearDrop", visual = "JuiceFx" }, -- chime by tier; tier colour beam; Legendary chimes twice
		{ id = "bossWarning", visual = "WorldFx" }, -- siren and deep horn; red edge tint; banner
		{ id = "bossPhase", visual = "WorldFx" }, -- roar; phase pips flip; shake 0.4 s
		{ id = "bossDefeated", visual = "JuiceFx" }, -- fireworks; MVP card
		{ id = "combo", visual = "CombatFx" }, -- chord; combo ring; bonus Renown pop
		{ id = "purchase", visual = "JuiceFx" }, -- soft bell; NEW badge
		{ id = "photo", visual = "PhotoMode" }, -- shutter; flash only if reduce flashing is off
		{ id = "fastTravel", visual = "TravelClient" }, -- whoosh; streaks; skip button
		{ id = "respawn", visual = "JuiceFx" }, -- rising hum; protect shield ring for 5 s
		{ id = "contractDone", visual = "JuiceFx" }, -- chime; stamp; reward banner
	},

	-- one sound per juice action (3D ones play at the action's spot, heard within `range` studs)
	sounds = {
		leap = s("swoosh.wav", 0.6, 0.85, { range = 120 }),
		land = s("action_jump_land.mp3", 0.8, 0.7, { range = 140 }),
		glide = s("swoosh.wav", 0.25, 0.6),
		flyCruise = s("action_falling.mp3", 0.0, 1, { loop = true }), -- volume follows speed (0 to 0.5)
		boost = s("swoosh.wav", 0.7, 1.25, { range = 120 }),
		basic = s("electronicpingshort.wav", 0.35, 1.6, { range = 90, vary = 0.12 }),
		cast = s("swoosh.wav", 0.55, 1.1, { range = 120, vary = 0.08 }),
		super = s("action_jump_land.mp3", 1, 0.45, { range = 260 }),
		crit = s("electronicpingshort.wav", 0.5, 2.1, { range = 90 }),
		defeat = s("action_jump_land.mp3", 0.6, 1.5, { range = 120, vary = 0.1 }),
		rescue = s("electronicpingshort.wav", 0.6, 1.2),
		incidentClear = s("electronicpingshort.wav", 0.8, 0.8),
		collapse = s("action_jump_land.mp3", 1, 0.3, { range = 400 }),
		crater = s("action_jump_land.mp3", 0.8, 0.55, { range = 200 }),
		clash = s("action_jump_land.mp3", 1, 0.6, { range = 220 }),
		vehicleFlip = s("action_jump_land.mp3", 0.7, 0.9, { range = 160 }),
		downed = s("action_falling.mp3", 0.5, 0.4, { loop = true }), -- the muffled heartbeat while Downed
		revive = s("action_get_up.mp3", 0.8, 1.2, { range = 120 }),
		pvpFlag = s("electronicpingshort.wav", 0.7, 0.5),
		levelUp = s("electronicpingshort.wav", 0.9, 1.4),
		skillRank = s("button.wav", 0.6, 1.2),
		gearDrop = s("electronicpingshort.wav", 0.6, 1.8),
		bossWarning = s("action_falling.mp3", 1, 0.3, { duck = true }),
		bossPhase = s("action_jump_land.mp3", 1, 0.35, { range = 500 }),
		bossDefeated = s("electronicpingshort.wav", 1, 1),
		combo = s("electronicpingshort.wav", 0.8, 1.05, { range = 200 }),
		purchase = s("electronicpingshort.wav", 0.7, 1.3),
		photo = s("clickfast.wav", 0.8, 1),
		fastTravel = s("swoosh.wav", 0.8, 0.7),
		respawn = s("action_get_up.mp3", 0.7, 0.8),
		contractDone = s("electronicpingshort.wav", 0.7, 0.95),
		ui = s("button.wav", 0.35, 1), -- every button tap
		-- the newer robots (not juice actions; CombatClient plays them with their CombatFx visuals)
		aimLock = s("electronicpingshort.wav", 0.6, 2.6), -- a Sniper's laser locks on you
		grenadeBoom = s("action_jump_land.mp3", 0.9, 0.5, { range = 200, vary = 0.08 }), -- a Bomber's grenade
		rally = s("electronicpingshort.wav", 0.6, 0.6, { range = 160 }), -- a Captain's rally
		reveal = s("clickfast.wav", 0.7, 0.7, { range = 120 }), -- a Mimic shows itself
		-- lore step 4: a famous fake's face cracks to show metal (with a white flash and a short hit-stop)
		unmask = s("clickfast.wav", 1, 0.45, { range = 200 }),
	},

	-- every path's own sound layer (overhaul plan step 6), played with the slot's cast sound above (Juice.path):
	-- cast (skills), super, hit (your hits, once per use) and charge (a skill starts charging). PLACEHOLDER
	-- SOUND: built-in clips pitched per path until nate picks licence-checked ids (Launch Checklist).
	paths = {
		Volt = {
			cast = s("electronicpingshort.wav", 0.3, 2.4, { range = 100, vary = 0.08 }),
			super = s("electronicpingshort.wav", 0.6, 0.7, { range = 220 }),
			hit = s("electronicpingshort.wav", 0.25, 2.8, { range = 80, vary = 0.1 }),
			charge = s("electronicpingshort.wav", 0.3, 3, { range = 60 }),
		},
		Frost = {
			cast = s("clickfast.wav", 0.45, 1.6, { range = 100, vary = 0.08 }),
			super = s("swoosh.wav", 0.8, 0.5, { range = 220 }),
			hit = s("clickfast.wav", 0.4, 2.2, { range = 80, vary = 0.1 }),
			charge = s("clickfast.wav", 0.3, 2.6, { range = 60 }),
		},
		Fire = {
			cast = s("swoosh.wav", 0.5, 0.75, { range = 100, vary = 0.08 }),
			super = s("action_jump_land.mp3", 0.9, 0.4, { range = 240 }),
			hit = s("swoosh.wav", 0.4, 0.6, { range = 80, vary = 0.1 }),
			charge = s("action_falling.mp3", 0.3, 1.4, { range = 60 }),
		},
		Earth = {
			cast = s("action_jump_land.mp3", 0.5, 0.65, { range = 100, vary = 0.08 }),
			super = s("action_jump_land.mp3", 0.9, 0.35, { range = 240 }),
			hit = s("action_jump_land.mp3", 0.4, 0.9, { range = 80, vary = 0.1 }),
			charge = s("action_get_up.mp3", 0.3, 0.6, { range = 60 }),
		},
		Tide = {
			cast = s("action_swim.mp3", 0.5, 1.1, { range = 100, vary = 0.08 }),
			super = s("impact_water.mp3", 1, 0.55, { range = 240 }),
			hit = s("impact_water.mp3", 0.45, 1.4, { range = 80, vary = 0.1 }),
			charge = s("action_swim.mp3", 0.3, 1.5, { range = 60 }),
		},
		Blade = {
			cast = s("swoosh.wav", 0.5, 1.9, { range = 100, vary = 0.08 }),
			super = s("swoosh.wav", 0.9, 0.9, { range = 220 }),
			hit = s("clickfast.wav", 0.4, 1.7, { range = 80, vary = 0.1 }),
			charge = s("clickfast.wav", 0.3, 1.2, { range = 60 }),
		},
		Gunslinger = {
			cast = s("clickfast.wav", 0.55, 0.8, { range = 120, vary = 0.08 }),
			super = s("action_jump_land.mp3", 0.9, 0.8, { range = 240 }),
			hit = s("electronicpingshort.wav", 0.3, 1.9, { range = 80, vary = 0.12 }),
			charge = s("button.wav", 0.4, 0.8, { range = 60 }),
		},
		Gadgeteer = {
			cast = s("button.wav", 0.45, 1.5, { range = 100, vary = 0.08 }),
			super = s("electronicpingshort.wav", 0.7, 0.5, { range = 220 }),
			hit = s("button.wav", 0.35, 2, { range = 80, vary = 0.1 }),
			charge = s("electronicpingshort.wav", 0.25, 1.3, { range = 60 }),
		},
		Shadow = {
			cast = s("swoosh.wav", 0.45, 1.45, { range = 90, vary = 0.08 }),
			super = s("action_falling.mp3", 0.8, 0.35, { range = 220 }),
			hit = s("swoosh.wav", 0.35, 2.2, { range = 70, vary = 0.1 }),
			charge = s("action_falling.mp3", 0.25, 0.8, { range = 60 }),
		},
		Titan = {
			cast = s("action_jump_land.mp3", 0.55, 0.8, { range = 120, vary = 0.08 }),
			super = s("action_jump_land.mp3", 1, 0.3, { range = 260 }),
			hit = s("action_jump_land.mp3", 0.5, 1.1, { range = 90, vary = 0.1 }),
			charge = s("action_get_up.mp3", 0.3, 0.8, { range = 60 }),
		},
		Martial = {
			cast = s("swoosh.wav", 0.5, 1.3, { range = 100, vary = 0.08 }),
			super = s("action_falling.mp3", 0.9, 0.6, { range = 240 }),
			hit = s("action_jump_land.mp3", 0.4, 1.6, { range = 80, vary = 0.1 }),
			charge = s("action_falling.mp3", 0.3, 1.8, { range = 60 }),
		},
		Juggernaut = {
			cast = s("action_jump_land.mp3", 0.55, 0.55, { range = 120, vary = 0.08 }),
			super = s("action_jump_land.mp3", 1, 0.25, { range = 260 }),
			hit = s("clickfast.wav", 0.45, 0.7, { range = 90, vary = 0.1 }),
			charge = s("action_falling.mp3", 0.3, 0.5, { range = 60 }),
		},
		Colossus = {
			cast = s("action_jump_land.mp3", 0.6, 0.45, { range = 140, vary = 0.08 }),
			super = s("action_jump_land.mp3", 1, 0.2, { range = 300 }),
			hit = s("action_jump_land.mp3", 0.5, 0.75, { range = 100, vary = 0.1 }),
			charge = s("action_get_up.mp3", 0.35, 0.45, { range = 60 }),
		},
		Pulse = {
			cast = s("action_falling.mp3", 0.45, 0.6, { range = 100, vary = 0.08 }),
			super = s("action_falling.mp3", 0.9, 0.25, { range = 240 }),
			hit = s("electronicpingshort.wav", 0.3, 0.6, { range = 80, vary = 0.1 }),
			charge = s("action_falling.mp3", 0.3, 1.1, { range = 60 }),
		},
		Mind = {
			cast = s("electronicpingshort.wav", 0.35, 0.9, { range = 100, vary = 0.08 }),
			super = s("action_falling.mp3", 0.8, 0.45, { range = 220 }),
			hit = s("electronicpingshort.wav", 0.3, 1.15, { range = 80, vary = 0.1 }),
			charge = s("electronicpingshort.wav", 0.25, 0.75, { range = 60 }),
		},
		Spirit = {
			cast = s("action_get_up.mp3", 0.45, 1.3, { range = 100, vary = 0.08 }),
			super = s("action_get_up.mp3", 0.9, 0.6, { range = 240 }),
			hit = s("swoosh.wav", 0.35, 1.6, { range = 80, vary = 0.1 }),
			charge = s("action_get_up.mp3", 0.3, 1.6, { range = 60 }),
		},
		Light = {
			cast = s("electronicpingshort.wav", 0.35, 1.7, { range = 100, vary = 0.08 }),
			super = s("electronicpingshort.wav", 0.8, 1.2, { range = 260 }),
			hit = s("electronicpingshort.wav", 0.3, 2.4, { range = 80, vary = 0.1 }),
			charge = s("electronicpingshort.wav", 0.25, 2, { range = 60 }),
		},
	},

	-- per-tier gear chimes (pitch rises with the tier; Legendary plays a second chime 0.25 s later)
	tierPitch = { 1.2, 1.4, 1.6, 1.85, 2.1 },

	-- the three loops (spec: city patrol day and night, boss theme, victory sting). PLACEHOLDER: silent
	-- until nate picks licence-checked tracks (Launch Checklist).
	music = {
		patrolDay = { asset = 0, volume = 0.35 },
		patrolNight = { asset = 0, volume = 0.3 },
		boss = { asset = 0, volume = 0.45 },
		victory = { asset = 0, volume = 0.5, sting = true },
		fade = 1.5, -- seconds to crossfade
		duck = 0.6, -- music volume while the boss siren or a voice line plays (ducks 40%)
		bossRange = 600, -- the boss theme plays within this many studs of a live boss
	},

	-- voice packs: 6 lines each (Config.Shop.voiceSounds holds the ids); which event plays which line
	voice = {
		lines = { "super", "rescue", "incidentClear", "levelUp", "downed", "emote" },
		gap = 2.5, -- at most one line every 2.5 s per hero
		range = 90, -- other heroes' lines are heard this close
	},

	haptics = { land = 0.35, super = 0.6, clash = 0.8, downed = 0.5, bossPhase = 0.5, collapse = 0.4 },

	pool = 24, -- 3D sounds alive at once (the oldest is reused)
}
