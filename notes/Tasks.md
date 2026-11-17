# Tasks

Milestones in order (spec "Milestones and cut list", plus nate's 2026-11-16 anime additions). Each one is
code-complete when lint is clean, tests pass and the place builds; the "done when" checks that need people,
phones or Studio go on the Studio test list below.

| # | Milestone | Scope | Done when (spec) | State |
|---|---|---|---|---|
| M1 | Move and fight slice | Leap, Glide, Flight with touch, PC and gamepad controls; Volt basic + 2 skills; clash hit feel; Spark Drone; greybox Downtown; 30-bot load test; Comic and Anime effect styles | 5 first-timers stop the first machine in 30 s with no help; 4 of 5 say flight and hits feel good on a phone; 30+ fps on a mid-range phone | Code-complete 2026-11-16 |
| M2 | Classes, abilities, enemies | 4 classes with passives, 5 sets (Volt, Frost, Titan, Pulse, Blade) with 40 abilities in both styles, the super slot, Awakening, ranks, mods, power budget, 6 enemies, data tables | Every class solos a contract and has a clear role in a 4-player test; no loadout exceeds the budget | Code-complete 2026-11-16 |
| M3 | Gear, loot, saves | 5 tiers, 8 slots, stats, drops and pity, salvage, upgrade, style collection, profile and migrations, levels and Renown | Drops match the table; a tester wears any look over any gear; rejoin restores everything | Code-complete 2026-11-16 |
| M4 | World generator, 30-player gate | Hub districts, seeded outskirts (2 zone types), weekly seed, streaming, presets, landmarks, safehouses, beacons, age questionnaire | Same seed gives the same hash on two servers; 30+ fps flying across the map on a phone; 30 bots hold the server frame | Code-complete 2026-11-16 (age questionnaire is nate's, on the Launch Checklist) |
| M5 | Destruction v1 | Chunker, 220 hub buildings with 3 states, debris, craters, vehicle flips, repair drones, citizens | 10 players wreck a block for 10 minutes with no server spike and 30+ fps on a phone; everything repairs | Code-complete 2026-11-16 |
| M6 | Incidents, contracts, events, boss | Incident spawner with 10 templates, 6 contract types, 6 random events, world boss with 2 bosses, contribution rewards | First boss within 8 minutes; boss rewards by tier; no idle wait over 5 s | Code-complete 2026-11-16 |
| M7 | Opening, Act 1, missions | Cinematic, playable disaster, choice, 6 missions in sky pockets, 3 choices, 8 side quests, journal | 5 new testers finish the opening and suit up with no help; both routes reach the finale | Code-complete 2026-11-16 |
| M8 | PvP, death, anti-exploit | Flag, Crater, Downed and Defeated, Fame and Infamy, rules table, strikes | The 30-minute exploit test finds nothing; PvP rules checklist passes | Code-complete 2026-11-16 |
| M9 | Creator, HQ, shop, passes | Creator with the 116 spec pieces plus the anime pieces and the Comic/Anime pick, 2 HQs, Gizmo's shop, Robux shop, passes, slots, Legacy | A tester makes a hero in under 3 minutes; test purchases grant once; looks show to others | Code-complete 2026-11-16 (economy sim gate met for the median level; see Decisions) |
| M10 | UI and phone pass | All screens, settings, accessibility, presets, map, squad | Every screen has loading, empty and error states; device matrix passes | Code-complete 2026-11-16 (device matrix on the Studio list) |
| M11 | Juice, audio, wait fillers | Juice table, sounds, music, offline drones, downed polish, friend boost, Photo Mode | No idle wait over 5 s in a 30-minute session with 8 testers; every action has a sound and visual | Code-complete 2026-11-16 (the 8-tester gate and real sound ids are on the Studio list and Launch Checklist) |
| M12 | Test and launch prep | Playtests, balance, thumbnails, icon, analytics, soft launch plan | 20 testers play with no crash reports in one session week; analytics visible | Code-complete 2026-11-16 (analytics wired; the playtest week, art and launch need nate: Playtest Kit, Store Page, Soft Launch Plan) |

## Placeholder art and animation (replace before launch)
- City: Downtown greybox boxes, window bands and rooftop props (CityBuilder). PLACEHOLDER ART.
- World (M4): the Docks, Old Town, hub filler blocks, all 32 outskirts tile variants (houses, shops, parks, farms, coast), the 3 landmarks, safehouses, beacons, the sand and the ocean are simple parts (Districts, WorldGen, WorldMap). Balls stand in for leaves, domes and dunes. PLACEHOLDER ART until the M5 kit.
- Map screen: flat coloured squares for zones, districts and landmarks; no tile detail (MapScreen). Fast-travel flight is a camera sweep with the hero left standing (TravelClient). PLACEHOLDER ART until M10.
- Robot bodies: Blender meshes since 2026-11-16 (art/models/Robots.rbxm); the walk, aim and windup poses are still code-driven. PLACEHOLDER animation until real animations.
- Ability visuals for all powers: neon parts, beams and rings (CombatFx, AuraFx) with the effects library's particles under them (FxLib, 2026-11-17) on Roblox's built-in particle images until the generated sheets in art/export/fx are uploaded (Launch Checklist). PLACEHOLDER ART until then and the icon set.
- Snow Wall pieces, the Ice Slide ramp and the thrown crate in Lift and Throw: plain parts (CombatService). PLACEHOLDER ART.
- Ability buttons show short names, not icons (Hud, LoadoutScreen). PLACEHOLDER ART.
- Hero animations (2026-11-17): flight, hover, glide, leaps, dashes, slides, swings, wall runs, rides, swimming, the Downed kneel, every cast, each weapon family's combo, the windup and the flinch are hand-keyed code poses (Shared.HeroAnim, HeroAnimator); the ground walk, run, idle and jump are Roblox's default Animate. PLACEHOLDER ANIMATION until real animations are made and uploaded.
- Gear looks: all 31 gear styles (plus 5 set looks and the gilded Legendary look per slot) are blocks, balls, wedges and cylinders welded to the body (LookService). PLACEHOLDER ART until the M9 accessory meshes.
- Gear, loot and toast screens: Kit placeholder look, text-only piece cards, no item icons (GearScreen, Toasts). PLACEHOLDER ART.
- Gadget effects: smoke, decoy and shield drone are a plain disc or pop (GadgetClient); the decoy has no body. PLACEHOLDER ART.
- Destruction (M5): building chunks and rubble are plain boxes in the body's colour; craters are a dark disc with a rock rim; facade cracks are thin dark bars; dust uses the engine's built-in smoke texture; repair drones are a box with four rotor discs and a neon beam (BuildingFx). PLACEHOLDER ART until the destruction kit and decals.
- Vehicles (M5): the 40 cars, trucks and trams are boxes with cylinder wheels (VehicleService); the flip has a dust ball and sparks (VehicleFx). PLACEHOLDER ART.
- Citizens (M5): blocky cartoon people in 6 colour sets with a code walk, idle and flee pose (CitizenRenderer). PLACEHOLDER ART.
- World activity (M6): incident and contract props (tram, relay dish, vaults, shard crate, billboard, balconies, the escort truck, the event train and generators, rescue pads and rings) are plain parts (SiteKit, IncidentService, ContractService, EventService); stranded citizens and the cat reuse the blocky citizen look; Tower fire uses the engine's Fire and Smoke. PLACEHOLDER ART.
- World bosses (M6): Rustjaw Prime and the Lumen Maw are part-built models with no animation beyond moving, turning, landing and sinking (WorldFx); telegraphs are flat red markers; the Tidal surge water is one glass slab and the Blackout a colour correction. PLACEHOLDER ART until the M11 boss pass.
- World markers, the tracker, the boss bar, the result card and the Contract Board: Kit placeholder look with a "!" icon (WorldHud, ContractBoard). PLACEHOLDER ART until M10.
- Load bot bodies (LoadBots, Studio only).
- Landing crack: dark disc instead of a crack decal (MoveFx).
- Flight, leap and glide: the body tilts along the travel direction (MoveController) and HeroAnimator poses the limbs (see Hero animations above).
- Loading screen: title on a gradient (LoadingScreen).
- Story (M7): the cinematic is 4 flat comic panels (StoryHud); the opening's tram car, shard, trapped citizen and beams are plain parts (StoryFx); mission pockets are greybox boxes (PocketLayout); the War-Frame is a part-built mech (WorldFx); quest NPCs are blocky figures with a name tag and a marker (QuestService); the Null Echo buddy is a ball with an eye; the Journal, Suit Up, choice card, trackers and result card use the Kit placeholder look. PLACEHOLDER ART.
- PvP and death (M8): flag rings and the Downed ring are flat neon discs, the PvP defeat is a CombatFx spark burst, Help/Here/Danger pings are text markers (PvpFx); name plates, the plate menu, the PVP button, the Crater bar, the Downed and Defeated screens and the PvP card use the Kit placeholder look (Plates, PvpHud). The Downed hero kneels when still and slumps while crawling (HeroAnimator). PLACEHOLDER ART.
- Creator pieces (M9): all 146 suits, capes, coats, scarves, masks, gloves, wraps, boots, hair, eyes, auras and trails are blocks, wedges, balls and neon parts welded to the body; emblems are a glyph on a SurfaceGui; auras are the engine's default particle (LookKit). PLACEHOLDER ART until accessory meshes.
- Voice packs (M9): the 4 voice choices have sound ids 0 (Config.Shop.voiceSounds). PLACEHOLDER until free-licensed clips (M11).
- Emotes and landing poses (M9): joint angles tweened on the rig (EmoteFx). PLACEHOLDER ART until real animations (M11).
- HQ rooms (M9): Beacon Tower and The Foundry are box rooms with neon pads and signs, part-built dummies and boss sim robot, marble copies of the hero for statues, box trophies and props (HqClient). PLACEHOLDER ART.
- Creator, Robux shop, HQ panels (M9): Kit placeholder look, text tiles, no piece icons; the preview is a ViewportFrame copy of the hero (CreatorScreen, ShopHud, HqHud, Preview). PLACEHOLDER ART until M10.
- HUD: Kit placeholder look (M10 restyles).
- M11 sounds: every juice sound is one of Roblox's built-in client sounds (rbxasset://sounds: swoosh, jump land, falling, get up, ping, button, click) pitched per action; music loops and voice clips are silent (asset 0) (Config.Audio, Config.Shop.voiceSounds). PLACEHOLDER SOUND until nate picks licence-checked Creator Store ids.
- M11 juice visuals: coin burst, medal and NEW stamps, the level badge, tier beams, fireworks, confetti, the shield ring and dazed stars are neon parts and Kit frames (JuiceFx); Photo Mode backdrops are Kit frames and colour grades (PhotoMode); the photo poses are joint angles (EmoteFx). PLACEHOLDER ART until the art pass.
- M10 screens: Settings, the squad list, panel and invite card, the radar (Kit shapes and glyphs: circle, diamond, triangle, square, star), the ping wheel, the settings gear and the main menu are Kit placeholder looks (SettingsMenu, SquadHud, Radar, Shapes, Hud, MainMenu). PLACEHOLDER ART until the art pass. The squad emblem is a text glyph.
- 17 paths (2026-11-16): the 96 new abilities use the existing neon parts, beams and rings; summons (turret, drone, clones, totem, guardian, mines, holo decoy) and rides (jets, rock, board, platform, rail) are a few parts each; size forms just scale the hero (CombatFx, CombatClient). Swing lines are a thin part (MoveController). PLACEHOLDER ART.
- Underwater (2026-11-16): the basin walls, the Sunken Line tunnel, station and train cars, reef, kelp, wrecks, caches and the sunken factory are plain parts; the seabed and rock walls are Terrain sand and rock (DeepLayout, CityBuilder); commuters are blocky figures in a glass bubble, cache markers are labels (DeepClient); Diver helmets and tanks are parts (EnemyRenderer); torpedoes are a box with ball bubbles (CombatFx); the Leviathan Engine is a part-built serpent sub (WorldFx). PLACEHOLDER ART.
- New robot types (2026-11-17): the riot shield, officer's cap, rifle, visor, bandolier, medic backpack, jet wings and hook launcher are plain parts (EnemyRenderer); the aim laser, tracer, net, hook and cable, grenade, burning patch, repair beam, rally ring and the Mimic's glitch burst are neon parts and the effects library's particles (CombatFx); their sounds are pitched built-in sounds (Config.Audio aimLock, grenadeBoom, rally, reveal). PLACEHOLDER ART until meshes and effect sheets.
- Store page (M12): no icon, thumbnails or concept art yet; briefs in notes/Store Page.md (generated and hand-cleaned, nate approves each).
- Hero creator first slice (2026-11-16): the 121 new pieces (beards, faces, makeup, hats, ears, shoulders, neck, arms, wrists, belts, legs, back bling, 10 hair styles) are blocks, wedges, balls and cylinders welded to the body (PieceKits); all 36 weapons are part-built (WeaponKit); body builds and heights scale the blocky rig and the 8 Blender body sets (art/blender/bodies.py, 2026-11-17) reshape it once Bodies.fbx is imported; weapon moves reuse the power visuals in a steel colour with no swing animation. PLACEHOLDER ART.

## Studio test list (needs nate's PC)
Start: `rojo serve`, connect the Rojo plugin, press Play (or Test > Clients and Servers with 2 players). The DEV button (top right, Studio only) has the test tools.

### New robot types: looks and effects (2026-11-17)
Needs the server AI for the nine new robots (each one spawns in the ambient mix and in open-world squads). Best with a second player to see the effects from outside.
1. Shield Bearer: a big dark riot shield with a window and a gold stripe held out in front on the left arm; a hit from the side or back knocks it away in a burst of chips and the arm drops; it comes back when the guard does.
2. Captain: a peaked officer's cap with a gold badge over its cape; on a rally its arm goes up, then a gold ring of the rally's size spreads with a "RALLY!" pop, and the robots in it get gold eyes and core and a gold chevron over the head until the rally ends.
3. Sniper: a long rifle held low in both hands and a glowing visor; while it aims the rifle is shouldered and a thin red laser runs from the rifle tip to the hero's chest and follows them; for the last part it stops following, thickens and blinks, then a bright long tracer fires. The aimed-at player sees a red edge pulse round the screen that blinks hard at the lock (steady with Reduce flashing) and hears a ping. The laser goes when the Sniper dies.
4. Bomber: a strap of three grenades across the chest and a satchel on the hip; it throws (arm back) and a small spinning grenade arcs to the spot, its red light blinking faster, with a red ring where it lands; the blast is a fireball with flames, smoke, a ring and rubble bits (camera shake within 40 studs), then an orange burning patch with flames and embers for the zone's time.
5. Medic Unit: a white backpack with a green plus (never red) and a green light on top; while it repairs, its right arm points out, a green beam with running green packets joins it to the robot it mends (both ends follow), and the backpack light pulses.
6. Swarmer: a small (3 studs) robot that scuttles crouched and leaning forward with quick steps and arms swept back; a lunge throws it flat out with arms reaching.
7. Mimic: until it shows itself it looks like a plain citizen (street shirt and trousers in its own colours per robot, or the citizens' uploaded clothes once those are on, a citizen's face, no health bar, no robot gear) and auto-aim skips it. When it shows itself: a cyan and magenta glitch burst, its eyes turn, and it is a normal robot from then on.
8. Interceptor: swept jet wings on the back with glowing tips; its net shot is a spinning square net, bigger than a pellet.
9. Grappler: the right forearm is a big hook launcher with a claw; the hook flies out on a cable from the launcher, grabs a hero and stays on them while the robot reels (a flying hero is pulled down toward it), and the claw is gone from the arm while it is out; a miss sticks in a wall for a moment or reels back.
10. Low preset with several Bombers and Medics fighting: the frame stays smooth (FrameProf) and nothing errors in the Output.
### Level cap 50 (2026-11-17)
nate's call: the cap goes from 40 to 50 (Config.Stats.levelCap is the one number; Decisions.md). Code and tests are done (1,000-hero sim: median 46.5 h to 40, 91.5 h to 50).
1. DEV > Level +5 from 40: the badge and toast say LEVEL 41 to 45, the Renown bar shows RENOWN x / about 7,600 to 8,900 and "NEXT LV 50: Level cap, Legacy"; at level 40 the toast says "Unlocked: Level 40 trophy".
2. DEV > Level 50: the bar says MAX LEVEL; more Renown adds nothing.
3. At 45 in the hub and the outskirts, incidents, contracts and robots run at level 45 (the tracker and the plates); gear drops show ilvl 43 to 47 (up to 52 at the cap) and can be worn.
4. Swim to the Trench floor at level 1 to 30: robots and caches there run at level 35 (the depths below y -160); higher up in the Trench, 25.
5. HQ > Hall of Legends at level 40 to 49: "Retiring opens at level 50"; at 50 RETIRE works and the statue plate says Level 50.
6. PvP at 50 against 45: hits land as before (compression uses the cap).
7. Rejoin with a level 40 hero saved before the change: still level 40 with 0 Renown, and now earns on to 41.

### M1 Move and fight slice
1. Spawn: you land on the plaza by the Beacon Tower; the HUD shows LV 1 BLASTER VOLT, health, stamina, and buttons ZAP, CHAIN, DASH, LEAP, FLY. No errors in Output.
2. Leap (Space or LEAP): short crouch, a big floaty arc (about 40 studs up, 80 forward), dust ring on take-off, a thud, shake and dark crack on landing. Cooldown sweep on the LEAP button.
3. Glide: hold Space after the top of a leap; you sink slowly (12 studs/s) and drift forward; the stick steers. Release to drop.
4. Walk off a tall roof: the fall turns into a leap-style fall you can glide out of.
5. Fly (F or FLY): take-off hop, then hover. Stick moves where the camera points (look up to climb). Space climbs, Ctrl dives. Let go: you slow to a hover and level out.
6. Boost (hold Shift or BOOST while flying): about 110 studs/s, trail, speed lines, wider FOV; the stamina ring drains in about 7 s, then you drop to cruise. Stamina refills in the air and faster on the ground.
7. Bank and tilt: the body leans into turns and lies flat when flying fast. Check it reads as flying, not falling (PLACEHOLDER pose).
8. Ceiling: fly straight up; you're pushed back down above the clouds (about 560) and can't pass 600.
9. Landing from flight: dive into the ground or hold Ctrl near it; you land and run.
10. Drones: within a few seconds 3 Spark Drones appear nearby, fly to you and strafe while firing orange 3-shot bursts you can see coming. Getting hit shows a red edge and a small shake; flying fast dodges most shots.
11. Zap (hold click or ZAP): bolts at 2 per second; hits flash the drone, show numbers, a tiny hit-pause; every 5th hit is a gold crit (Blaster Overcharge). A drone dies in 5 hits with a burst of parts.
12. Chain (Q or CHAIN): lightning jumps to up to 3 drones close together; 6 s cooldown sweep.
13. Dash (E or DASH): you dash 30 studs along your aim, hitting what you pass; drones get knocked aside; 8 s cooldown. You are never pulled back after a dash.
14. Phone (Studio device emulator, then a real phone): thumbstick moves, camera drag steers, auto-aim snaps to the nearest drone in front within 60 studs. Buttons are reachable, nothing in the bottom-right 80 px.
15. Gamepad: A leap or climb, Y fly, L2 boost, B dive, R2 zap, X chain, R1 dash.
16. Style: DEV > Style: Anime. Bolts turn thin and white with afterimages, hits show a white flash and radial lines, crits flash the screen briefly, speed lines show when flying fast. Switch back to Comic: thick bolts, rings and stars.
17. Death: DEV > God OFF and let drones win; you respawn on the plaza after 5 s with full health and cooldowns.
18. Regen: after 6 s without damage, health refills at about 4% a second.
19. Speed check: nothing honest (leap, glide, boost, dash, falling from 600) ever snaps you back. If you see a snap-back, note what you were doing.
20. 30-player load: DEV > 30 bots. Bots fly around Downtown and fire at drones. The DEV stats line should show server frame about 16.7 ms (60 fps), scripts well under 8 ms total (enemies under 2.5, combat under 1.5, replication under 1.5), enemies near 90 at most, send kbps reasonable. Play for 5 minutes. Then Clear bots.
21. Client fps: the DEV line shows fps and the preset (low on phones). Target 30+ fps on a mid-range phone at low.
22. The M1 "done when" checks: 5 first-timers stop the first machine in 30 s with no help; 4 of 5 say flight and hits feel good on a phone; 30+ fps on a mid-range phone.

### M2 Classes, abilities, enemies
DEV panel now has: 3x robot (cycles all 6), Level 50 (the cap, Config.Stats.levelCap), +10 Skill Pts, Fill Awakening. Skill ranks are free of Credits in Studio (Config.Dev.freeRankCredits) until M3.
1. HUD: four skill buttons (Q, E, R, T), a SUPER button (G) from level 20, a POWERS button (L), and the Awakening meter under health. No errors in Output.
2. POWERS screen: tabs for Volt, Frost, Titan, Pulse, Blade (locked until 1, 6, 10, 14, 18). LEARN, RANK UP and EQUIP work; the budget reads x / 52 and refuses an over-budget loadout with a clear notice. At rank 3 (rank 2 for supers) two mod buttons appear. SET PRIMARY changes the basic attack and the colours. Loadout 2 opens at level 15. RESPEC refunds everything (10 minute wait, not in combat).
3. Mixing: equip a Frost skill on a Volt primary; it works and keeps its own Frost look.
4. Every ability in both styles (DEV > Level 50, +10 Skill Pts a few times, then try each set). For each: it fires where you aim, the number and look match its kind (bolt, chain, dash, cone, arc, nova, line, leap, throw, field, buff, wall, ramp), the cooldown sweep matches, and robots react (stun ring, ice tint, float, pull, knock-up, knock-back into walls).
5. Channels: Freeze Beam and Thousand Cuts keep going while you hold still; pressing again cancels. Gravity Well, Static Field, Blizzard Dome, Blade Storm and Singularity show their area and tick.
6. Recast: with Dash Strike at rank 5 (Double Back) you can dash again within 3 s.
7. Punch Combo and Blade Slash: three-hit strings, the third hit bigger; a pause resets the string.
8. Awakening: DEV > Fill Awakening, then V (or the AWAKEN button). Gold aura and sparks for 15 s, bigger hits, faster cooldowns, and a bigger super.
9. Team-up combo (2 players): two different sets' supers within 3 s and 30 studs show a combo banner (e.g. Frost + Volt = Storm) and extra damage.
10. Classes: DEV > Class cycles Blaster, Bruiser, Speedster, Controller. Bruiser takes less damage and taunts what it hits; Speedster runs faster with shorter cooldowns; Controller's Anchor shrugs off damage near allies; Blaster crits every 5th hit.
11. Robots are humanoid machines (sparks and bolts on defeat, no blood). DEV > 3x robot for each:
    - Spark Trooper: jet-boot flyer, strafes and fires 3-shot bursts.
    - Burglar Bot: runs from you with a loot bag, turns and fires when cornered.
    - Sneak Bot: fades out, circles behind you, and backstabs hard (front stabs are weak). Turn to face it.
    - Brute Bot: a red ring warns 0.8 s before its slam; step out to dodge; a stun cancels it.
    - Sentry: planted gun that turns slowly; circle it fast; a blue bubble blocks hits for 1.5 s every 6 s.
    - Null Sentinel: blocks hits from the front (BLOCK numbers); hit it from the side to break the guard (BREAK!).
12. Snow Wall blocks robot shots.
13. Parry (Brace at rank 3 or the parry mod): a hit during the window ripostes.
14. 30-bot load test again with mixed sets (bots now use all 5 sets): server frame and send rate stay inside the M1 numbers.
15. The M2 "done when" checks: every class solos a contract and has a clear role in a 4-player test (contracts come in M6; until then, clear a street of mixed robots per class); no loadout exceeds the budget (also covered by tests).

### M3 Gear, loot, saves
Saves need a published place with Game Settings > Security > "Enable Studio Access to API Services" on. Without it (or in an unpublished place) profiles live in memory for the session and Output says so. Flight now opens at level 3 (DEV > Level +5 skips ahead). Ranks now cost Credits (DEV > +1000 Credits).
1. Join: the HUD shows GS 0, a purple Renown bar ("RENOWN 0 / 100  NEXT LV 3: Flight"), CREDITS 0 and DUST 0 under POWERS, and a GEAR button. No errors in Output.
2. DEV > +500 Renown: the bar fills, a LEVEL banner pops with what unlocked and "+1 Skill Point". At level 3 the FLY button appears.
3. DEV > Loot: cycles the 8 drop sources (incident, contract, event, story, storyFinale, bossParticipant, bossContributor, bossMvp). Each press rolls that source at your level: a toast in the tier colour (Epic and Legendary pop bigger). An incident only drops 12% of the time. Below level 20 boss Epics come out Rare; MVP Legendaries need level 30.
4. GEAR (I, or Select): STASH lists pieces best first, filtered by slot. Pick one: the card shows item level, budget, stats, set or perk text. EQUIP it: GS and the hero card change, health rises with Vitality, and the gear look appears on your hero (blocks and colours, PLACEHOLDER). Other players see it too (2-player test).
5. A piece above your level + 5 refuses with "Your level is too low". A hands piece only goes in Hands.
6. UPGRADE (DEV > +500 Dust first): +1 costs 12 on a Common; the name shows +1 and stats rise 4% a step; +10 stops.
7. RETUNE a bonus stat (DEV > +1000 Credits): the stat changes, the value stays, locked after 3.
8. SALVAGE: refused while worn ("Take it off before salvaging"); otherwise Dust goes up. SALVAGE UNWORN COMMONS clears up to 20 at once. The style stays unlocked in STYLES.
9. STYLES: pick a slot tab; unlocked styles light up, locked ones say "Loot a piece with this style". Show any unlocked style over any gear in that slot; SHOW MY GEAR'S OWN LOOK goes back. (Done-when check: a tester wears any look over any gear.)
10. LOOT INFO lists every source's odds, the pity rules and your own pity counters.
11. Sets: wear 2 Epic pieces of one set (Stormcaller etc.): that power set hits 8% harder. 4 pieces: the ability change (Chain Lightning hits 5, Frost Nova shields allies, Ground Slam leaves a shockwave, Float heals allies near the target, Parry ripostes heal).
12. Perks (DEV > Level 50, then Loot: bossMvp until a Legendary): Quakeheel shockwave on a 30+ stud landing; Cooling Kill takes 20% off the super's cooldown sweep on a kill; Second Wind saves you once per 5 minutes (God OFF); Echo Trail hurts robots you fly fast past; Lucky Strike crits every 8th hit; Shared Spark raises a nearby ally's Power (2 players).
13. Gadgets: loot until a gadget drops (about 1 in 16), equip it in Gadget; a GADGET button (Z, R3) appears with its cooldown sweep. Grappling Hook pulls you to what the camera points at within 90 studs (never snaps back); Smoke Bomb makes nearby robots lose you; Shield Drone gives a shield bar; Decoy pulls robots off you for 5 s.
14. POWERS: RANK UP shows points and Credits; with no Credits it says "Not enough Credits". RESPEC refunds the Credits (they show as banked in GEAR).
15. Rejoin (published place with API access): level, Renown, Credits, Dust, stash, worn gear, styles shown, ranks, mods, loadouts, Comic/Anime choice and the respec timer all come back. (Done-when check.)
16. Two servers: join a second server with the same account while the first is still open; the second waits and then asks you to rejoin, never loading a stale copy. (Spec: a second server cannot open the same profile.)
17. Crash test: play 3 minutes, note the Renown, then stop the server from Studio without leaving (or kill the test server). Rejoin: at most 120 s of progress is lost. (Spec check.)
18. DEV > Wipe profile starts over at level 1 with nothing; DEV > Save now prints true.
19. The M3 "done when" checks: drops match the table (tests check 10,000 rolls per source); a tester wears any look over any gear (item 9); rejoin restores everything (item 15).

### M4 World generator, 30-player gate
The weekly seed is ISO year x 100 + ISO week (UTC). Config.Dev.worldSeed (Studio only) forces a seed; 0 uses the week's.
1. Play: Output shows "[CityBuilder] seed 2026xx tile hash xxxxxxxx", then "hub ready in N s", then "outskirts built in N s" under 20 s. No errors.
2. Gate: two servers with the same seed log the same hash. Start a server, note the hash, stop, start again (or set Dev.worldSeed = 202647 on both runs): same hash. Then set 202648: a different hash, the same hub.
3. Fly from the plaza across the whole map: Downtown, the Docks (warehouses, container stacks, 3 cranes over the basin, the dark Foundry with red glow and chimneys), Old Town (small houses, pitched roofs, Clock Square and the Clock Tower), filler blocks and parks, suburbs, farms, the coast (beaches, piers, lighthouses, dunes), the ocean. Pitched roofs must slope up to a ridge, not down into a V (check the WedgePart direction).
4. Landmarks: Comet Crater northeast (dark floor, rim, glowing comet), Radio Hill west (stepped hill, mast, glide hoops), Old Quarry south (walls, a gate on the north side, terraces).
5. Gate: on a mid-range phone at the low preset, flying at boost across the map holds 30+ fps (Shift+F5 or the Dev panel). Note memory (F9 > Memory): under 1.5 GB.
6. Gate: DEV > 30 bots: they now fly across the whole map. The Dev panel's server frame stays under 16 ms (scripts under 8 ms) for 5 minutes, including while the outskirts are still building.
7. Streaming: far towers show as a low-detail skyline; flying fast never drops you into empty space; landing on a far roof works.
8. Safehouses (16, the map shows them): walking onto one toasts "Safehouse found". Bank (hold B 3 s): on-hand Credits move to banked (GEAR shows it). Respawn here: toast. Loadout: opens POWERS. Away from safehouses and HQ, changing a loadout or respec says "Change loadouts and respec at a safehouse or HQ"; rank-ups still work. Check the B key and gamepad X do not also fire a skill.
9. Respawns (DEV God off, let robots win): you come back at the nearest safehouse you have visited, else Plaza West. Rejoin (published place): you join at the safehouse you chose. A wiped profile lands on the plaza.
10. Beacons: fly to one (tall light beam); touching it toasts "BEACON FOUND". MAP (M, or the MAP button) shows zones, districts, landmarks, both HQs, safehouses (green once visited) and beacons (gold once found) and your dot. Tap a gold beacon: a 3 s camera flight with SKIP, then you stand on that roof. In combat it says "Not while fighting"; within 20 s "Fast travel ready in N s". DEV > Find all beacons unlocks all 12.
11. Robots still walk on roofs and the ground across the whole map (the heightmap covers the outskirts), and drones keep to sensible heights over the hills and the quarry.
12. Age questionnaire (nate): run it on this build and record the answer in Decisions.md (Launch Checklist).

### M5 Destruction v1
Hub buildings: 220 (all of Downtown, 6 Docks warehouses, 122 Old Town houses). Dev panel: Wreck here (3,000 structure damage in 30 studs), Repair city (every building and vehicle back), Flip cars.
1. Play: no errors. Fly into Downtown; DEV > Wreck here next to a building a few times: at 40% it turns Damaged (4 to 8 upper chunks tumble off, a dust puff, a small shake), at 100% it collapses over 6 s (a shudder, floors drop, a dust cloud), leaving a low rubble heap you can stand on.
2. A collapsed building no longer blocks you or shots; robots walk over its rubble, not its old roof.
3. Supers (3,000 structure damage each) and the abilities with structDmg (Thunder Drop, Lift and Throw, Ground Slam, Haymaker) damage buildings where they land; a nova leaves a crater on the ground and cracks on nearby walls; a blast leaves wall cracks. Craters and cracks fade after 30 s and never pile past the preset count.
4. Collapse cap: wreck 4 buildings within 6 s: the 4th stops at Damaged and falls on the next hit after the others finish.
5. Knockback: a heavy hit (Titan heavy or any 2.5x hit) on a robot next to a wall throws it at the wall and the wall turns Damaged (at most 3 per player per 10 s). Check the robot does not end up stuck inside the building (it should land on the roof or beside it).
6. Vehicles: 40 in the hub (20 Downtown cars, 8 trams on two east-west lines, 10 Old Town cars, 2 Docks trucks). A heavy hit near one flips it in a 1 s arc onto its roof with dust and sparks; at most 6 flipped per district; each goes back after 30 s. Other players see the same flip. Vehicles never sit inside a building or across a sidewalk.
7. Citizens: up to 60 walk the Downtown and Old Town sidewalks (pause at corners). Wreck a building near them: everyone close runs (arms up) before it falls, to a safehouse or Beacon Tower, and disappears inside; 20 to 40 s later they walk again. Nothing hurts them.
8. Repair: 3 minutes after the last hit a Damaged building gets a yellow drone that flies in and beams it for 20 s, then the building pops back whole (4 minutes for a collapsed one). A building hit during the job stays broken.
9. Join late: a second player who joins after buildings fell sees the same Damaged and Collapsed buildings and rubble at once (no collapse replays) and any drone already working.
10. Streaming: fly away from wrecked buildings and come back: they still look wrecked, with no leftover floating chunks.
11. Gate: 10 players (or you plus 9 bots and a friend) wreck one block for 10 minutes: the Dev panel's server frame stays under 16 ms and the "buildings", "citizens" and "wrecked" counters behave; a mid-range phone on the low preset holds 30+ fps during collapses. After the drones finish, everything is back.

### Red Faction destruction (2026-11-16)
DEV panel: stand next to a hub building and press Wreck here (a super-sized hit at your feet), or use supers. Repair city puts everything back. Pieces are plain boxes in the building's colour (PLACEHOLDER ART).
1. First hit on a building: it turns into pillars, wall panels and floors; a hole opens where you hit and 2 to 6 pieces fly out, tumble and fade in about 5 s. You can see the floors inside and fly in through the hole.
2. Hit high on a tall building around one storey (all sides): that storey shakes and drops with everything above it in a dust cloud; the floors below stay standing. Robots walk on the new lower roof.
3. Hit around the ground floor: the whole building comes down storey by storey and leaves the rubble heap.
4. A heavy hit that throws a robot into a wall breaks 1 or 2 panels where it goes through.
5. A second player joining after the damage sees the same holes; a phone (Low preset) shows fewer flying pieces but the same holes.
6. Repair drones put the whole building back after 3 minutes of quiet.
7. Performance: 10 players wrecking a block for 10 minutes: server frame steady, phones 30+ fps (Dev panel).
8. A level 1 hero with only basic attacks and starter skills: every third basic hit on a wall knocks a piece out, every skill hit breaks at least one piece.

### Superhuman android robots (2026-11-16)
DEV panel: spawn robots with the "3x" button (it cycles through the 6 kinds) and hit them a little at a time. The shell and endoskeleton are plain parts (PLACEHOLDER ART until the art pass).
1. Each kind looks like a superhuman soldier at full health: uniform in its colours, gloves and boots, a chest mark and belt, cartoon skin and hair (different robots get different skin and hair), softly glowing eyes. The Null Sentinel wears a violet cape that sways as it moves. No metal shows through anywhere (no flicker on the shoulders, face or chest).
2. A few hits: a limb piece breaks off with 2 or 3 chips and a spark, and the metal bone and joint show underneath.
3. About half health: the belly or chest is open; you see the ribs and the glowing core.
4. Low health: the face breaks off half at a time, showing the metal skull and the glowing eyes behind it; the core sparks under 35% health. At 15% health it is all endoskeleton.
5. Two players see the same robot lose the same pieces at the same time. A robot that walks into view already hurt shows its damage without a burst of chips.
6. Cloaked Sneak Bots still fade fully (broken pieces stay hidden), the cold tint, stun ring and shields still show, and the hit flash only lights the pieces still there.
7. Performance: 60 robots on screen on PC (High), 20 on a phone (Low): frame rate steady (Dev panel).

### Blender robot meshes (2026-11-16)
The robots can use real meshes made in Blender (art/blender/robots.py builds them; art/export/Robots.fbx is the file). Until they are imported the robots stay plain parts, so nothing breaks.
DONE 2026-11-16: Claude imported them on nate's PC (uploaded to his account) and pulled the model into the repo (art/models/Robots.rbxm, mapped to ReplicatedStorage.Art by Rojo), so every build has the meshes. Redo steps 1 to 3 only when Robots.fbx changes, then Claude pulls the new model in.
Import (when Robots.fbx changes):
1. Studio: Home > Import 3D, pick `art/export/Robots.fbx` (from project files: capeline/Robots.fbx). In the importer turn OFF "Import as a single mesh" and leave rig settings off. Import.
2. A model with 38 MeshParts appears (Spine, Ribs, ChestL, FaceL, Hair, ShLowerL and so on). Rename the model `Robots`.
3. In ReplicatedStorage add a Folder named `Art` and drag `Robots` into it. Optional: select all the MeshParts and set CollisionFidelity to Box (smaller and faster; the robots never collide).
4. Publish the meshes with the place (they upload with it). Rojo leaves ReplicatedStorage.Art alone.
Checks:
5. DEV panel "3x": robots now have rounded muscular suits, gloves with fists, boots, a face with a nose and ears, spiky hair, a belt that hugs the waist. The pieces line up (no gaps at the chest centre or face centre, the hair sits on the head).
6. They face the way they walk. If every robot walks backwards or sideways, tell Claude: the export gets turned (`--flip`) in one step.
7. The shell still breaks off piece by piece showing the metal skeleton (steps 2 to 4 of the android list above), and colours still differ per robot.
8. Performance: a full robot is about 27,000 triangles; Roblox lowers detail with distance by itself. 60 robots on PC (High) and 20 on a phone (Low) hold the frame rate (Dev panel). If not, Claude thins the meshes further.

### Hero body on the R15 rig (2026-11-16)
nate: every humanoid follows the standard R15 body. art/blender/hero.py builds the hero base body in the classic blocky Roblox look (15 parts named exactly as R15, bevelled blocks and the classic head, about 6,000 triangles), exports art/export/Hero.fbx and writes Config.HeroRig (sizes, centres, every rig and accessory attachment). HeroBody (server) builds StarterPlayer.StarterCharacter from it at boot. Until the meshes are imported heroes keep the player's own avatar, so nothing breaks. Claude asks nate before doing the import on his PC.
Import (once, and again only when Hero.fbx changes):
1. Studio: Home > Import 3D, pick `Hero.fbx` (project files: capeline/Hero.fbx). Turn OFF "Import as a single mesh", rig settings off. Import.
2. A model with 15 MeshParts appears (Head, UpperTorso, LeftUpperArm and so on). Rename it `Hero` and drag it into ReplicatedStorage > Art (next to Robots).
3. Claude pulls it into the repo (art/models/Hero.rbxm, mapped by Rojo) like the robots.
Checks (Play):
4. The Output says "[HeroBody] every hero uses the R15 hero body". Your hero is the blocky R15 body with the classic head and face (not your avatar), feet on the ground, facing the way it walks.
5. Walk, run, jump, fall, climb and swim play Roblox's R15 animations; emotes (EmoteFx) bend the right joints.
6. Creator looks (suits, capes, masks, hair, gloves, boots, emblems, auras, trails) sit on the right parts; skin tone colours the head and hands.
7. Abilities, hits, PvP and the Downed state work as before (the root part is the standard 2 x 2 x 1).
8. If the body is missing or the Output shows a HeroBody error: tell Claude (the fallback is the avatar body).

### Hero creator and weapons, first slice (2026-11-16)
nate's plan: https://claude.ai/artifact/VeuJPWz6kKE6gGsUBmqQC9. Use a fresh hero (DEV: delete hero) for 1 to 6, then an old one for 7.
1. Creator (Suit Up or MainMenu Create First): tabs BODY, SIDE, MOBILITY, POWERS, WEAPON, APPEARANCE, PLAY along the top; BACK, RANDOMIZE and NEXT along the bottom; the hero turns in the middle. Hover any row: the hero and the card on the right show it; leave: it goes back.
2. BODY: Male and Female (narrower waist), Small, Medium, Large and Titan (a Titan is huge and bulky, head a bit smaller), 5 heights. Feet stay on the floor at every size; arms and legs join the body with no gaps.
3. WEAPON: 7 families; pick a family, then a weapon (Coming soon ones say so and block DONE); the camera moves to the weapon; STYLE, FINISH and GLOW cyclers, MAIN/TRIM/GLOW colours with AUTO, EMBLEM on and off all change the weapon on the hero. Pick the Sword.
4. APPEARANCE: every area (Body, Head, Torso, Arms, Waist and legs, Back, Extras) lists its slots; each slot's pieces show on the hero (head slots move the camera to the face, cape and back bling to the back); a slot's MAIN/TRIM/GLOW colour and MATERIAL override just that piece; the 30 skins include Stone, Metal, Ice, Energy, Shadow and Crystal. A helmet hides the hair, the knight helm the face too.
5. PLAY: pick a Title and Noun; the card sums up the hero; DONE saves and you spawn with that body and look. Phone layout (Device emulator, a phone): the list is a drawer along the bottom and everything fits.
6. In the city: press 2: the sword appears in the hand and the skill buttons turn into the sword's (M1 a 4-hit combo, Z Dash Cut; X, C, V say LOCKED); press 1: the sword goes away and your power is back. Z X C V and Q E R T both cast. Super (G) is always the power's. Gadget is now 3, Awaken Y. Gamepad: left stick click swaps; phone: the WEAPON/POWER button.
7. Mastery: hit robots with the sword; at Mastery 25 a toast says X UNLOCKED and X casts (DEV: give Credits and fight a while, or set mastery). Other players see your weapon only while you hold it.
8. Weapon Rack: the grey fifth terminal at a safehouse (hold B): every weapon by family; BUY one for Credits (Credits go down, it says it's yours), CARRY it (the hand shows it on 2), CUSTOMIZE opens the creator on the weapon step. Exotic ones show their Robux price; the Boomerang bought in the shop (test purchase) can be carried.
9. Body sizes and doors: as a Titan and as a Small hero, walk through a safehouse shelter, a doorway and under a low ledge: both fit the same places a Medium hero does (one standard collider), and nobody falls through the floor or sinks into it.
10. Old heroes: a hero made before this update keeps its look (no missing pieces), has Bare Fists on 2 and Male Medium Average.

### Downtown kit block (2026-11-17)
One Downtown block (east of the plaza) to the new look (overhaul plan step 3): textured building fronts with the windows in them, paved sidewalk, kerbs, lane dashes, textured roads, street lamps, planted trees, benches, bins, hydrants and traffic lights. Previews: art/preview/block_street.png and block_air.png (rendered from the game's own layout). Until the textures and props are in, the block keeps today's look (plain colours, window bands, no props), so nothing breaks.
Textures (art/export/city, project files capeline/art/city; Claude can do this on your PC when you say so):
1. Studio: View > Material Manager. For each of the six (Brick, Office, Curtain, Stone, Paving, Asphalt), create a variant named `Kit` + the name (KitBrick, KitOffice, ...) on its base material: Brick on Brick, Office on Concrete, Curtain on Glass, Stone on Sandstone, Paving on Pavement, Asphalt on Asphalt.
2. In each variant, import its `_Color`, `_Normal` and `_Roughness` PNGs (Curtain also `_Metalness`). Studs Per Tile: 12 for the four fronts, 8 for Paving, 16 for Asphalt. Pattern: Regular.
3. The variants live in MaterialService and publish with the place. Claude then pulls them into the repo so every build has them.
Props:
4. Home > Import 3D, pick `art/export/Street.fbx` (project files capeline/art/city/Street.fbx), "Import as a single mesh" OFF. Rename the model `Street`, put it in ReplicatedStorage.Art. Claude pulls it into the repo (art/models/Street.rbxm).
Checks (walk out of the plaza to the east):
5. The block's four buildings show stone, office or glass-tower fronts with windows, a storey a tile; the window bands are gone there (only there); each roof has a pale cornice. The other blocks look as before.
6. Windows line up with the storeys and are not stretched (if they sit half a storey off, tell Claude: the tiling start moves in one step).
7. The sidewalk is paved slabs with a kerb; the roads everywhere in Downtown have asphalt grit; white dashes run down the four streets around the block.
8. Lamps (lit bulbs) along the kerb with trees in planters between, a bench and a bin on each side, a hydrant near a corner, traffic lights on two corners with their lights over the street. You can stand on benches and planters, walk through leaves.
9. Smash a building on the block: the falling wall panels keep the front texture; rubble is plain.
10. Performance: about 120 more parts on the block; the Dev panel frame time is unchanged.

### Heroes: a Roblox character in our own clothes (2026-11-17)
nate's call: every hero is the classic blocky Roblox character and keeps nothing from the player's avatar ("They wear our clothes, our gear, our accessories"). Our classic Shirt and Pants (art/clothes/heroes.py: 18 shirts, 12 pants, previews art/preview/hero_clothes.png and hero_clothes_2.png), tinted by the hero's colours, our 6 faces and our hair, with suits and gear on top. No gender, build or height. The Output says build city-clothes (2026-11-17).
Uploads (with the robot uploads below; Claude puts the ids in Config.Creator.clothes):
1. Asset Manager > Bulk Import the 30 PNGs in project files capeline/art/clothes/heroes (Shirt_*.png, Pants_*.png; not the preview folder). Copy each id into the chat with its name. Until then the body is painted in the shirt's and pants' colours.
Checks:
2. New hero: a hoodie and jeans (tinted in the hero colours), the Hero face, swept hair, a domino mask, a classic cape and a star. Nothing from your Roblox avatar shows (no hats, hair, clothes or face of yours).
3. Creator: no Body step. HEAD has Face (our 6 faces) first; TORSO has Shirt first; WAIST AND LEGS has Pants first. Shirt, Pants and Face have no NONE. Each shirt and pants changes in the preview and in the world; a slot colour square tints it.
4. Pick a Top (suit): it covers the shirt and pants; NONE on Top brings the shirt and pants back. A Legs piece covers only the pants.
5. Short sleeves, the tank and shorts show the skin; hands are skin under every shirt.
6. HQ mannequins show the outfit as plain colours (they have no Humanoid, so Roblox clothing cannot draw on them).
7. Citizens: once the clothes are uploaded, every citizen wears one of the shirts and pants in its own colours, with one of our faces (if uploaded); walking around, no two near each other look the same. Clothes sit right on every face of the body (if all are shifted, Config.NpcLooks.offsetSign flips them, as for robots).

### Robots: try both looks in game (2026-11-17)
nate wants to compare the two robot looks in game: "Roblox" (a plain Roblox character: blocky R15 body, classic clothes image, a Roblox face that turns, real Roblox hair from the catalog; every robot kind, all 18, has 3 uniform versions, Grunt, Veteran and Elite, preview art/preview/uniforms.png for the first 9 and art/preview/uniforms_new.png for the 9 newer ones) and "Shell" (the Blender superhero meshes below). Dev panel button "Robots: Auto / Roblox / Shell / Plain" switches every robot live. The Output says build robot-uniforms (2026-11-17).
Uploads (once; then Claude builds one place with everything in it):
(Faster: an Open Cloud API key lets Claude upload all of these itself through Remote Control; see Decisions 2026-11-17.)
1. Download the 54 uniform PNGs (18 kinds x 3 versions) (project files capeline/art/clothes/uniforms: only the <Kind>_<Version>.png files, not the _Shirt or _Pants ones), the 12 face PNGs (capeline/art/clothes/faces: Face_<Name>.png and Face_<Name>_Turned.png) and Trooper.fbx (capeline/art/trooper).
2. Studio, any place: View > Asset Manager > Bulk Import, pick the 66 PNGs, Open. Wait until they show under Images. (To try it sooner, the 12 faces plus SparkDrone_Grunt.png are enough for the Spark Trooper.)
3. In Asset Manager > Images, right-click each > Copy ID to Clipboard, and paste each into the chat with its name.
4. Home > Import 3D, pick Trooper.fbx, keep "Import only as a single mesh" OFF, Import.
5. In the Explorer, right-click the new Trooper model > Save to File..., save Trooper.rbxm, and attach it in the chat.
6. Claude puts the ids in Config.NpcLooks and Trooper.rbxm in the repo and sends a new Capeline.rbxl; open it.
Checks:
7. Play, DEV > "3x Spark Trooper", then press "Robots:" to cycle. Roblox: blue suit with the diamond bolt emblem, orange gloves and boots, belt, one of six comic-style faces, Roblox hair (one of three styles); face, hair and skin differ robot to robot, and about 3 in 10 wear the Veteran suit (white shoulders, chevrons) and 1 in 10 the Elite (navy and gold). Then a few other kinds (DEV spawns): each wears its own uniform (burglar stripes, sneak sash, brute's champion belt, guard uniform, commander's coat, wetsuit, overalls, naval jacket; and the 9 newer kinds once they spawn: riot plates and the shield-wall mark, the officer's tunic and cape, camouflage with a chest rig, crossed bandoliers and hazard stripes, the medic's white tunic with the green plus, the hive-patterned runner kit, plain street clothes on the Mimic (no mark, so it passes for a citizen), the flight suit with wings on the back, the armoured hook arm). Shell: the Blender superhero. Plain: the old look.
8. Roblox look: the clothes sit right on every face (emblem centred on the chest, gloves on the hands, boots at the feet). If every face is shifted, Claude flips Config.NpcLooks.offsetSign. If the hair is missing, copy the Output's [NpcLooks] lines into the chat.
9. Roblox look: the face turns (dark eyes that glow) the first time it attacks or breaks; it reddens during a windup; the white hit flash still shows; broken parts take their clothes with them.
10. Performance: 30 Roblox-look robots near you hold the frame rate on PC (High) and on a phone (Low).

### Remade Spark Trooper (2026-11-17)
The first robot to the new look (overhaul plan step 3), redone as a superhero on nate's note (2026-11-17, "not humanoid enough"): a face with skin, glowing eyes and swept hair, a fitted blue suit with a white and orange diamond emblem, orange gloves and boots, a belt and side stripes, all on the blocky R15 body with one baked texture set (art/blender/trooper.py; preview art/preview/trooper.png). Until it is imported the Spark Trooper keeps today's look, so nothing breaks. The build line in the Output says hero-trooper (2026-11-17).
Import (steps 4 to 6 of "Robots: try both looks in game" above do this):
1. Studio: Home > Import 3D, pick `art/export/Trooper.fbx` (project files: capeline/art/trooper/Trooper.fbx). Turn OFF "Import as a single mesh". The textures are inside the file; the importer should give each part a SurfaceAppearance.
2. A model with 16 MeshParts appears (Head, UpperTorso ... RightFoot, Hair). Rename it `Trooper` and drag it into ReplicatedStorage.Art.
3. If the parts come in white with no textures: import the four PNGs next to it (Trooper_Color, _Normal, _Roughness, _Metalness), set them on one SurfaceAppearance and copy it into every part.
4. Claude then pulls the model into the repo (art/models/Trooper.rbxm, mapped by Rojo) so every build has it.
Checks (DEV panel "3x" until a Spark Trooper comes up):
5. It reads as a person in a hero suit: a face (skin, brows, nose, mouth) with human eyes under the brows (white with a brown, blue, green or dark iris), swept hair in one of the hair colours, the diamond emblem on the chest, the belt with its round buckle, orange gloves and boots. Skin and hair differ from robot to robot. Nothing floats or sits inside the body; it faces the way it flies.
6. Hits: the white flash still shows on the suit, skin and gloves; the ice tint shows when slowed.
7. Damage: skin and suit still break off part by part (the hair with the head), showing the metal skeleton only where broken.
7b. Turning: the eyes stay human while it patrols. The first time it winds up an attack or a piece breaks, the whites go dark and the irises glow (red during each windup) and stay that way.
8. Performance: about 5,000 triangles a robot; 60 on PC (High) and 20 on a phone (Low) hold the frame rate.

### Phone pass (2026-11-17)
The Output at boot says build phone-pass (2026-11-17). Use Test > Device (the Device Emulator) and pick each of: iPhone SE (667 x 375), iPhone 14 Pro (notch), a 20:9 Android (Galaxy S-series or Pixel), iPad, then back to the PC view. Landscape for the phones. Press Play on each. `lune run tests/run.luau build/Capeline.rbxl` already checks every screen headless at these sizes (tests/uisim.luau); this list is what only a real screen and a real thumb can show.
1. HUD on each phone: the action buttons sit bottom right in rings (Basic biggest, Z X C V around it, the super outside, Leap, Fly, Boost with its stamina dots, Down, Gadget, Swap and Awaken at the edges), nothing under Roblox's top bar or the notch, nothing in the lower-left move stick area. The radar is small top left, the status card beside it, the tracker under it. The top row (POWERS, GEAR, MAP, SHOP ...) fits on one line and the rest is in MORE; MORE opens a scrolling drawer and a pick closes it.
2. Thumbs: walk with the left thumb while pressing every button with the right; nothing is hard to hit or hit by mistake. Hold a skill button and drag: the camera turns to aim, lift to cast. Hold a damaging skill: its ring thickens as it charges and turns white at full. A cooldown shows its seconds on the button.
3. Settings > Button size: 80% to 130% grows and shrinks the cluster and it never leaves the screen (on a phone 100% is already the biggest that fits). Left-handed: the cluster moves bottom left, the corner group top right, our own stick on the right, all still clear of each other.
4. Open every screen on the iPhone SE: POWERS, GEAR, MAP, SHOP, JOURNAL, SETTINGS, SQUAD, the Weapon Rack, PHOTO, the contract board, the HQ stations, the creator (Create or Edit Hero) and the main menu. Each fits the screen (scaled down a little at most), long lists scroll, the close button is reachable, no text under about 10 px.
5. iPad: the radar sits beside the status card (the move stick owns the lower left) and the cluster is full size. PC: the same layout a little smaller, the key letter on top of each button.
6. Controller (Xbox in the emulator or a pad on the PC): Select opens the top row and selects its first button (MORE too); X also catches in the opening; every action still has its button.
7. Quality: on a phone the Dev panel shows the low preset (no shadows, bloom or sun rays, 30 citizens drawn, fewer particles); a PC starts on medium. On Auto, a game that stays under 26 fps for 20 s (for example the 30-bot load test, LoadBots) steps down one preset and never back up; a fixed preset in Settings stays put.

### Hold to aim and charge (2026-11-17)
The Output at boot says build aim-charge (2026-11-17).
1. Tap Z, X, C or V: the skill goes off on release, as quick as before. The basic (click) still fires on press and on hold.
2. Hold a skill: its aim shows in the power's colour (a strip for bolts, lines, chains and dashes, a fan for cones and arcs, a ring around you for novas, a ring at the aim point for fields and placed things) and follows the camera; release casts where it shows.
3. Hold a damaging skill (a bolt, line, chain, cone, arc or nova) past a quarter second: the charging pose starts and the aim grows and brightens; at 1.2 s it is full (a gather flash and a chime) and the aim pulses. The hit is clearly bigger (up to +20% damage, +15% size). Supers, buffs, fields, summons, dashes and channels aim but never charge.
4. Holding past 4 s casts by itself. Pressing a running channel's key still stops it at once. Holding one key then pressing another fires the first.
5. Phone: hold a skill button, drag the camera to aim, lift to cast. Controller: the same with the skill buttons.
6. Server check: in the Dev panel's damage numbers, a full charge hits about 20% harder than a tap; nothing errors when spamming taps.

### Effects library (2026-11-17)
The Output at boot says build fx-lib (2026-11-17). Uses Roblox's built-in particle images (art/export/fx holds the generated sheets to upload later).
1. Volt (the slice to judge): the basic bolt crackles along its path with blue-white sparks and a hand flash; hits throw sparks and a short lightning crackle; Chain Lightning sparks at each hop; a nova leaves a flat electric shockwave ring on the floor with a spark burst; the beam channel crackles along the beam the whole time. Say yes or no on the look.
2. Other elements, one power each: Fire leaves flames and embers, Frost and Tide throw shards, Earth and Colossus kick up dust, Shadow trails smoke and wisps, Mind and Pulse swirl a vortex, Spirit and Light leave wisps and sparkles, weapons spark like steel. Comic draws a little less than Anime.
3. Feel: each of your hits holds the pose for a blink (hit-stop) with a small camera kick; crits and heavy hits kick harder. Other heroes' hits draw smaller.
4. Settings: Reduce flashing removes the bright flashes (glow, core, crackle) but keeps sparks and smoke. The Low preset draws clearly fewer particles; with 4 heroes spamming novas the frame stays smooth (FrameProf in the Dev panel) and nothing errors.
5. Robot deaths: a flash, sparks and a puff of smoke on top of the flying plates. Enemy slams kick up a ring of dust.

### Hero animations (2026-11-17)
The Output at boot says build hero-anim (2026-11-17). Best with a second player (Studio Test > 2 players) to see the poses on another device too.
1. Fly fast: one fist leads overhead, the other arm trails, legs together with a soft kick. Slow down: it changes to a hover (arms out, legs dangling, a gentle bob) without flickering at the edge. Glide: arms spread like wings. Leap and fall: a tuck. Super-speed dash, slide, swing (one arm up on the line), wall climb and wall run, a ride (surf stance), swimming (front crawl), and a Leaping ground pound (fists overhead) each have their pose. Landing goes straight back to the normal walk and idle.
2. Casts: Volt's basic alternates left and right palm blasts; a beam channel holds the arm out until it ends; a nova flings the arms out; an area slam brings both fists down; buffs and summons flex; dashes lunge; a super pushes both hands forward. A cast with a cast time shows the drawn-back windup first. Casting while flying keeps the flight legs.
3. Weapons, M1 three times each: Fists punch left, right, then kick; a Sword goes slash, backhand, overhead; a Greatsword sweeps wide and slow, then overhead; Twin Blades alternate hands, then spin; a shield bashes; a Spear thrusts; a Bow draws and looses; Throwing Stars and the Boomerang throw; a Chain Whip lashes. The weapon stays in the hand.
4. Getting hit makes a short flinch (not during a cast). Downed: kneel on one knee when still, slumped while crawling.
5. On the second player's screen, the first player's poses match (flight, hover, casts, flinch, Downed). Nothing jitters or snaps when two things overlap, and emotes and Photo Mode poses still work.
6. Dev panel FrameProf: HeroAnimator stays well under 1 ms a frame with 30 heroes nearby (load bots are not players, so this needs a real server or a quick read of the per-frame cost with 2 to 4 players).

### Creator pieces to 503 (2026-11-17)
The Output at boot says build creator-503 (2026-11-17). Open the creator (Create First or the HQ mirror). DEV: the Dev panel's "pieces" command unlocks every piece.
1. Every tab shows its new pieces, scrolls smoothly, and each piece shows on the preview the moment you pick it: 20 more hair styles, beards, 15 faces, makeup, ears, eye shapes (sharp, round, slit, visor and so on), 20 more emblems, 10 headwear, 14 masks, 30 tops, shoulders, neck pieces, arms, 8 gloves, wrist pieces, belts, 18 legs, 14 boots, back bling and 3 capes.
2. Spot check that pieces sit on the body, not floating or buried: the Ninja Wrap, Do-rag, Bucket Hat and Aviator Cap hide the hair; the Space Suit, Puffer Jacket, Mystic Robe and Kimono look right on a Small and a Titan body; Roller Skates and Flippers sit at the feet; the Hooded Cape and Star Cape hang like the old capes.
3. The old gloves and boots (Gloves, Long Cuffs, Spiked, Gauntlets, Claws, Wraps, Boots, Tall Boots, Sneakers, Winged, Jet, Armored) were sized for slimmer hands and sat hidden inside the body; they are now widened to wrap the hands, forearms, feet and shins. Check each one shows and none look oversized.
4. Locked pieces say how to earn them (level, quest, mission, rep, Fame, Legacy or drop), and Randomize uses the new pieces.
5. Save, rejoin: the look comes back the same (pieces past id 860 included).

### All 36 weapons playable (2026-11-17)
The Output at boot says build all-weapons (2026-11-17). DEV: give Credits, buy weapons at the Weapon Rack (or set mastery to 150 to open X, C and V).
1. Weapon Rack and creator: no weapon says "Coming soon"; every Rack weapon can be bought and carried, and the creator's free pick offers all 31 Rack weapons.
2. Try one per family on robots, all 5 moves each: Martial Arts (Counter Stance parries), Power Gauntlets (Ground Pound breaks walls), Katana (Thousand Cuts channels), Spear (long M1 reach), Scythe (Reaping Pull pulls robots in), Tower Shield (Cover Allies shields squadmates nearby), Bow (Arrow Rain), Crossbow (Net Bolt roots), Throwing Stars (Ricochet bounces to 4), Chain Whip (Pull Lash), War Fan (Glide Step speeds you up), Yo-yo, Rope Dart. Every move hits, shows its visual and its comic word, and nothing errors.
3. Feel: no weapon kills robots clearly faster than a power of the same role; the M1 combos all take about the same time to kill a Spark Trooper (fists and daggers fast and light, hammers and great axes slow and heavy).
4. Exotic weapons (Chain Whip, War Fan, Yo-yo, Rope Dart, Boomerang) show their Robux price and need product ids before they can be bought (Launch Checklist).
5. Known placeholder: weapon moves reuse the power visuals in a steel colour and there are no swing animations yet (PLACEHOLDER ART).

### Body sets (2026-11-17)
The Output at boot says build body-sets (2026-11-17). Needs art/export/Bodies.fbx imported first (Studio 3D Importer, into ReplicatedStorage.Art, named "Bodies"; preview art/preview/bodies.png). Before the import everything looks as it does now.
(2026-11-17: heroes no longer choose a body (Config.Creator.bodyStep = false), so steps 1 and 2 only apply if that is turned back on; citizens and robots in step 3 still use the sets.)
1. Creator: pick each of the 8 bodies (Male and Female, Small, Medium, Large, Titan). The torso, arms and legs change shape, not just size: tapers, a broad V on Large and Titan, a soft chest and wider hips on the female bodies. Nothing stretches oddly or leaves gaps at the joints.
2. Switch body back and forth in the creator, then press Play: the hero in the city has the same body as the creator preview, and hats, coats and armour still sit right.
3. Citizens: men and women, slim to big, walk around (no Titans). Robots: Brutes and Sentinels have the Large body, drones and Sneak Bots the Small one. The big HQ dummy is Large.
4. The Output has no "[LookKit] body set" warnings (MeshPart:ApplyMesh is the one new Roblox call here).

### Everyone on R15 (2026-11-16)
The Output at boot says build r15-everyone (2026-11-16). Works before and after the Hero.fbx import.
1. Robots: every robot is the blocky R15 body (same shape as a hero, wider for Brutes and Sentinels, slimmer for drones and Sneak Bots). In the Explorer, Workspace.Enemies has models with HumanoidRootPart, the 15 R15 parts and Motor6Ds named Root, Waist, Neck, LeftShoulder and so on.
2. They walk with arms swinging, elbows bending forward and knees back; Sneak Bots crouch; drones fly with knees back; a windup raises both arms; a knock-up tumbles; a stun wobbles with the yellow ring spinning over the head.
3. Hit one: arms, legs, hands and feet break off first (chips and sparks) showing metal bones, then the torso (ribs, spine, the glowing core), the head last (skull, jaw, eyes). The hair, eyes and mask go with the head. Nothing floats in the air or pokes through.
4. Capes hang from the shoulders and sway; sea robots' helmets and tanks, the Sentinel's cannon and base, the guard plate and the bubble sit where they should.
5. Citizens: every citizen is the blocky R15 body with the classic face, a shirt, pants, shoes and hair; they walk, idle and run with arms up when fleeing. Quest givers, witnesses, stranded citizens (arms up) and the HQ training dummies are R15 too.
   Checked by Claude in Studio on 2026-11-16 (Capeline-r15c.rbxl): your hero is the R15 hero body (no skeleton avatar), robots, citizens and quest givers are R15 rigs with the hero meshes, a beaten robot shows its metal skeleton, 0 errors. Still to check by eye: steps 2 to 4 and 6.
6. Performance: in a busy street (30+ robots and the citizens), the Dev panel's frame times for EnemyRenderer and CitizenRenderer stay under about 2 ms on the desktop.

### 17 paths, mobility and underwater (2026-11-16)
Pick a path at the creator, then use the DEV panel to level up (15+ to borrow). Everything new is plain parts (PLACEHOLDER ART).
1. Creator: 4 archetypes with their paths (17 in all); each path's starters show and a path change works once before level 10. At 15+ a hero can learn up to 5 skills from other paths in the same archetype; the basic and super stay the main path's.
2. Each path's TRAVEL power (marked in Loadout) moves you: Flame Jets, Rock Ride, Psi Platform, Spirit Ride (ride in the air), Wave Surf and Hoverboard (surf the ground and water), Light Rail, Recoil Jump, Sky Step and Giant Stride (launches), Shadow Step and Unstoppable (dashes). No speed-check pull-backs while riding.
3. Mobility (swap free at a safehouse): Super-speed sprint, wall run, water run and slide; Leaping super leap, wall bounce and ground pound (a real fall only); Acrobat double jump, climb, wall run and glide; Swing lines from buildings and zips; Flight as before. The HUD buttons change with the pick. Phone and gamepad too.
4. Summons and decoys: Turret Drop, Fix-It Drone, Shadow Clones, Ward Totem, Ascended Guardian, Holo Decoy and Tide Mirror draw and act; Mech Suit, Grow, Titan Form and Shrink Dodge change the hero's size.
5. Water: jump into the sea off any beach or into the harbour basin at the Docks: you swim (Terrain water), the screen tints blue and darkens deeper down, bubbles trail. No air meter.
6. The Sunken Line: from the basin floor swim west through the tunnel mouth to the flooded station and 3 train cars; each has a commuter in an air bubble. Swim close to pick one up (they follow you), swim up to the green pad on the quay: Credits and Renown. They come back after 4 minutes.
7. Coral Shelf (south of the south beach): reef, kelp, 3 shipwrecks, 7 sunken caches. Swim into one: Credits, Renown, sometimes gear; the marker shows a refill timer (15 minutes per hero).
8. The Trench (past the shelf, very deep): the sunken Null factory with chimneys and a glowing gate, 3 more caches.
9. Underwater robots: Divers (jet packs, helmets), Anchors (heavy seabed slammers) and Torpedo Sentries (slow torpedoes that turn after you) appear only while you swim; land robots stay out of the water and Spark Troopers skim the surface.
10. Element reactions in water: Storm chains jump farther, Fire blinds and pushes, Frost skills leave an ice raft at the surface you can stand on, Earth skills hide you for 2 s, Tide is stronger with shorter cooldowns.
11. Leviathan Engine: DEV boss controls start the third world boss; it rises over the Trench, sweeps its tail, fires torpedo volleys, pulls with a whirlpool and sends a surge ring. Break the 2 torpedo bays; eyes and reactor take double damage. MVP gets Leviathan Coils.
12. Performance: the world builds (the Output says how many underwater fills and parts and the seconds); phones hold 30+ fps swimming the shelf.

### M12 Test and launch prep
The playtest week itself is in notes/Playtest Kit.md (42 checks). These prove the M12 code in Studio first. In Studio every analytics event prints as `[Analytics] name value fields` in the Output.
1. Join: the Output shows `[Analytics] session_start 1 pc new hero` (or returning) within 20 s; a brand-new save also logs the Opening step (no print for steps; check the Dev panel's analytics count goes up).
2. Opening: play it through: first_leap, first_catch, first_blast, choice_made (shardfall save or grab) print in order; creator_done prints with class, side and set when you press DONE.
3. Combat: cast skills for a minute: about 1 in 5 casts prints skill_cast. Rank a skill (skill_rank), save a loadout at a safehouse, equip and upgrade a gear piece (gear_upgrade with tier, level, dust); every robot drop prints gear_drop.
4. World: clear an incident (incident_done with the template, medal and helpers), finish a contract (contract_done), fast travel and skip the flight (fast_travel ... 1), join the boss (boss_join) and finish it (boss_done with tier and win or fail).
5. PvP (2 players, level 10+): flag on and off (flag_on, flag_off with city or crater), hit each other (pvp_hit once per session), win (pvp_win); go Downed and get revived (downed N revived) or give up (downed N gave_up, then defeat pve).
6. Story and squads: enter a mission (mission_start), finish it (mission_done with seconds); answer a choice (choice_pick); join a squad (squad_join); change a setting (setting_change preset 2); take a photo (photo comic).
7. Shop: open the shop, tap a few cards, press BUY on a Studio test item: purchase prints with the item and Robux.
8. Leave: stop the test: `leave N idle` (or boss, pvp, downed, mission).
9. Dev panel: "analytics events N sent, 0 over budget", "perf sample on (median/p5 fps)" after a minute in Studio, "server script errors 0".
10. Rejoin the next day on the same save with Studio API access: no second session_start "new"; after 24 to 48 hours the d1_return step logs once.
11. Creator Dashboard (published private place, a day after testers): Analytics shows the custom events and the Onboarding, Combat, PvP, Story and Purchase funnels (the M12 "analytics visible" gate).
12. The playtest week: 20 testers, no crash report (Playtest Kit), results in notes/Build Log.md.

### M11 Juice, audio and wait fillers
Sounds are built-in placeholders (listen for each one, not for quality). Dev panel stats now show "idle waits >5 s". Use Test > Clients and Servers with 2 players for the clash and voice checks.
1. Movement: Leap (whoosh, dust ring), a big landing (thud, crack, a buzz on phone or gamepad), Glide (soft air), flight (a wind that grows with speed and stops when you land), Boost (a burst).
2. Combat: basic attacks ping, skills whoosh, supers boom; a crit adds a high ping; a defeated robot pops, sparks and throws 6 gold coins. Other players' casts are heard near them only.
3. Collision freeze: two players hit the same robot with heavy attacks (Titan Seismic Slam, Blade Moonsplit, supers) at the same moment: both freeze for a moment, a white shockwave rings out, the camera pushes in. It does not happen again for that pair for 5 s.
4. World: a building collapse rumbles (a buzz when within 80 studs), a crater crunches, a car flip whoomps; the boss countdown sounds a siren (music ducks), each boss phase roars, a boss defeat sets off fireworks over it and confetti on screen (no confetti with Reduce flashing on).
5. Rewards: a rescue shows a green ring and "+N RENOWN"; an incident clear slams a GOLD, SILVER or BRONZE stamp; a contract slams DONE!; a level up spins the level badge and lights NEXT AT n: the unlock; a gear drop shows a beam in the tier colour (Legendary and Mythic chime twice); a purchase slams NEW!; a skill rank or loadout save clicks.
6. Death: Downed plays a slow heartbeat loop that stops when revived or respawned; a revive shows gold rings; a respawn shows a blue shield bubble for 5 s; on the Defeated screen CHOOSE LOADOUT opens POWERS right after you are back.
7. Dazed: a PvP stun on you shows spinning stars over your head until it ends.
8. Photo Mode: PHOTO (top left) or K: every other screen hides, the hero holds still, drag or the right stick orbits, scroll, pinch or the triggers zoom. POSE steps through Ready, Look Out, Take Off, Thinking and your owned emotes (a second player sees only the emotes). LOOK steps through NONE, COMIC (frame and name caption), SPEED (lines), SUNSET, NOIR, NEON. HIDE UI hides the bar until you tap. SNAP clicks and flashes (no flash with Reduce flashing). EXIT, K or B puts everything back. Nothing is saved.
9. Friend boost: join with a Roblox friend: both see "<name> is here! FRIEND BOOST +10% Renown" and FRIEND BOOST +10% under the radar; kill rewards show the bigger Renown. It goes away when the friend leaves.
10. Offline drones: DEV > HQ level 5, Away 8 h, rejoin: a YOUR DRONES ARE BACK card with the Credits and COLLECT; tapping banks them ("Your drones brought back ..."). Leave without tapping and rejoin: the Credits were banked anyway.
11. Reward cards: a boss result and a mission result count the Credits and Renown up in 1.5 s; the first tap finishes the count, the next tap closes the boss card.
12. Settings: Music and Effects volumes change the sounds at once; Effects 0 silences every effect and voice line.
13. The M11 gate: 8 testers play 30 minutes; the Output shows no "[Capeline] idle wait" line longer than 5 s (each line says why: no incident near, dead or respawning), and every action above had a sound and a visual.

### M10 UI and phone pass
DEV panel (M10 rows): Reset settings, Text 160% / 100%. Use Test > Clients and Servers with 2 to 4 players for squads, and Studio's device emulator for phones.
1. Settings: the gear button (top left, next to the wallet) opens SETTINGS. Each row changes at once: Graphics (Auto shows the picked preset), Text size 100 to 160% in 10s (every screen's text grows, nothing overflows its box at 160%), Left-handed, Reduce flashing, One-hand flight, Tap to fly, Aim assist, Music, Effects, Damage numbers. Rejoin: every value is kept.
2. Left-handed (phone emulator): the action buttons move to the bottom left and the move stick works on the right half of the screen; turning it off puts both back.
3. One-hand flight: the stick only flies forward and its left-right turns the camera; the action buttons stay on the right.
4. Reduce flashing: hits, crits, supers and the Awakening burst flash much less and the camera barely shakes. Damage numbers off: no numbers on hits.
5. Mutes: mute a player from their plate, open SETTINGS: they are under MUTED PLAYERS with UNMUTE; rejoin: still muted. With nobody muted the list says so.
6. Radar (top left under the status card): turns with the camera; incidents are circles, events stars, the boss a diamond, danger pings triangles, squadmates squares in their colour; far ones sit on the rim; tap it for the map. Under it: DAY or NIGHT and the hour, and the boss countdown. It is hidden during the opening.
7. Ping wheel: PING > HELP, HERE (where you aim) or DANGER: others see the ping; DANGER is a red triangle on everyone's radar for a few seconds.
8. Map: incidents, events and the boss have their shapes; with Tap to fly on, tap one (or a beacon outside fast travel): your hero flies there on its own and stops when you touch the stick or land.
9. Squads: tap a plate > INVITE TO SQUAD (or SQUAD > INVITE). The other player gets a card with JOIN and NO and a 30 s bar. JOIN: both see the squad list under the radar in slot colours, the emblem glyph and SQUAD tag on plates. A 5th player can't join ("full"). The leader can KICK; LEAVE works; a squad of one is gone ("Your squad broke up").
10. Squad play: squadmates can't hurt each other even with PvP on; clear an incident with a mate within 250 studs: both are paid; a squad ping shows for mates anywhere on the map with SQUAD on it; mates show as squares on the map and radar even when far.
11. Party missions: the leader enters a mission with 1 to 3 mates within 120 studs: everyone comes in, robots and the War-Frame are scaled to the party's median level, each member is paid at the end, and only the leader's story moves. A member's LEAVE takes only them out; the leader's ends the run for all.
12. Pending buttons: tap a button that asks the server (ACCEPT on a contract, EQUIP, UPGRADE, a station row, INVITE): it shows "..." until the answer, a double tap does nothing, and with no answer in 5 s it says TRY AGAIN.
13. Loading, empty and error states: Journal before the save loads says "Loading your journal..."; the Contract Board with no offers says so; the map opened before the world is built says it is still loading; the creator's DONE with no answer in 8 s says "Could not save. Try again".
14. Main menu: a returning hero joins to CAPELINE with PLAY, SHOP and SETTINGS over the city; PLAY closes it at once. A brand-new player never sees it (the opening starts). Make a second hero (slot 2): the menu offers CREATE FIRST (straight to Suit Up, no cinematic) or PLAY THE OPENING (the cinematic and the run).
15. Controller: every screen above works with a gamepad (Settings rows, squad card, radar buttons, main menu).
16. Device matrix (the M10 gate): a low-end phone, a mid-range phone, a tablet, a PC and a controller each finish the opening, a contract and a boss with no blocked button, unreadable text or overlapping HUD.

### M9 Creator, HQ, shop, passes
DEV panel (M9 rows): Creator (opens it in "first" mode), Enter HQ, HQ level (cycles 1 to 6), Away 8 h (pays the offline drones), All pieces, Buy (grants the shown shop item with a fixed test receipt, then steps to the next), Level 50 (the cap; Legacy needs it).
1. Fresh profile (DEV > Wipe, rejoin): at Suit Up the creator opens (WHO ARE YOU?) with a turning hero. Every tab (Suits to Eyes) changes the preview at once; locked pieces are grey with how to get them (Level 15, a boss tier, a pack). Hair and Eyes tabs exist; COMIC or ANIME and VOLT or BLADE sit under HERO.
2. DONE stays grey until a Title, a Noun and a class are picked; a blocked pair (e.g. Captain + Falcon) shows "taken". RANDOMIZE fills everything from owned pieces. Time it: a new tester makes a hero in under 3 minutes.
3. After DONE: "<NAME> IS READY", the opening carries on, and a second player sees the same look and the hero name on the plate with the Roblox name small under it.
4. Pick BLADE as the start: the POWERS screen shows Blade abilities at level 1. Pick ANIME: effects use the Anime style.
5. A hero made before M9 (created 0): a few seconds after joining the creator opens once in "first" mode (no Hero/Villain switch, class can change).
6. Gear styles: wear gear with a Show Style picked: that style shows over the creator piece; with no Show Style the creator piece shows.
7. HQ: walk to the beacon (hero) or the foundry door (villain): B "Enter". You stand in Beacon Tower (blue) or The Foundry (red) with 6 station pads and an exit. Villains cannot use the hero door ("That is the other side's base").
8. Stations: Command Table opens the Contract Board, the Journal and HEROES; Gizmo lists 40 styles with prices (buying takes Credits, says NEW STYLE, shows OWNED after); UPGRADE HQ takes Credits and says HQ LEVEL n; Mannequins save and wear looks (2 to 4 locked until level 2); Training shows DPS and TOTAL when you hit a dummy, with aim assist on touch; the Exit puts you back where you came in.
9. Boss sim (DEV > HQ level 3): BOSS SIM starts a big robot, a top bar with HP and seconds, red rings every 6 s that hurt for 10% if you stay in and never down you; at the end a toast with the time or the damage dealt.
10. Trophy Wall: earned trophies list (DEV > Boss now and finish one for First World Boss); pick up to 3 (12 at level 4), SAVE THE WALL, plaques appear.
11. Offline drones: DEV > HQ level 5, Away 8 h: "Your drones brought back N Credits" (about 960 at level 5).
12. Legacy: DEV > Level 50 (the cap), Hall of Legends > RETIRE > YES: LEGACY RANK 1, a marble statue of the old hero in the hall, the hero is level 1 with the same look, name and side and a star on the plate.
13. Robux shop (P or SHOP, at HQ or out of a fight): 5 tabs; a pack card previews its pieces on your hero; tapping R$ in Studio grants the item at once ("THANKS! ... IS YOURS") and the card says OWNED; DEV > Buy the same item twice: the second says "nothing (replay)". Slot 4 says LOCKED until slot 3.
14. Effects tint: buy one, EQUIP: your power effects change colour for every player; Prism cycles colours. Landing pose: EQUIP, then fall from a roof: the pose plays and others see it.
15. Emotes: H opens the picker with owned emotes (Salute after Fame rank 2); the pose shows on other screens. Spam does nothing beyond one per 1.5 s.
16. Starter pack: the first world boss reward is followed 6 s later by FIRST BOSS DOWN! with GET IT and NO THANKS; it never shows again.
17. Hero slots: buy slot 3, Command Table > HEROES > + NEW HERO: the creator opens for the new hero; switching back to slot 1 restores that hero's level, gear and story.
18. Shop refused: casting at a robot then pressing SHOP from the city within 10 s says "The shop opens 10 s after a fight".

### M8 PvP, death, anti-exploit
Use Test > Clients and Servers with 2 (or 3) players. DEV panel (M8 rows): Force PvP on (level 10 and the flag, skipping the 5 s and 60 s rules), Down me, Go to the Crater, +200 Fame.
1. Below level 10 there is no PVP button. At 10 (DEV > Level +5 twice) it shows under the wallet. Press it at a safehouse: "Step out of the safe area". Outside: PVP ON in your side colour, a blue (League) or red (Syndicate) ring grows under you and others see it and a PVP tag on your plate.
2. Toggle spam: tap PVP fast: it only changes once per 5 s and nothing kicks you. Hit a flagged player, then try to turn off: "Can switch off in Ns" counts from 60 and restarts on each PvP hit.
3. Unflagged safety: a flagged player's bolts, chains, novas, fields, beams, echoes and supers never hurt an unflagged player standing in them (no numbers, no health loss), and an unflagged player cannot hurt a flagged one. A flag switched off while a field is on the ground stops its hits.
4. Two flagged players fight: numbers show, supers hit for less, stuns and roots stop the other's movement and buttons (a second stun within 8 s is half as long, then 3 s of immunity), slows slow, knockbacks and pulls throw the other player a short way, and nobody gets pulled back by the speed check for it.
5. Safe areas: inside a safehouse's radius, at HQ or in a mission pocket no PvP damage lands either way.
6. PvP defeat: the loser bursts into sparks with no Downed screen, OVERLOADED and a 5 s count, then respawns with SHIELDED for 5 s (hits do nothing until they attack). The card: winner "+N Credits +15 Fame"; loser "-N unbanked Credits. Gear is never lost." (or "Nothing lost" with 500 or fewer on hand).
7. Farming: beat the same player 3 times inside 30 minutes: the third card says no pay. Two players trading 3 wins each inside an hour: both see no pay, and the Output shows two "[GuardService] review: ... trade" lines. Same side pays half.
8. Combat logging: hit a flagged player, then have them leave within 15 s: their body stays standing for 10 s and the attacker gets the win card.
9. Support: an unflagged player's heal or shield (e.g. Controller buffs) skips a flagged ally who is in a PvP fight; it works again 15 s after their last PvP hit.
10. Downed (PvE): DEV > Down me (or let robots win): grey pulsing edge, DOWNED 10 count, GIVE UP, HELP; you crawl slowly and cannot cast or fly; robots stop shooting you. A second player gets a REVIVE button within 8 studs; staying close 3 s (1.5 s as Controller) brings you back with about a third of your health and gives them +40 Renown. Casting or walking away stops it. GIVE UP respawns 2 s later. Waiting 10 s: DEFEATED, the safehouse picker (NEAREST plus visited ones) and a respawn 5 s later at the pick. HELP shows a "HELP!" marker on the other player's screen.
11. The Comet Crater (DEV > Go to the Crater, then walk in): red bar "PVP ZONE IN 5" with LEAVE (puts you just outside); stay: PVP ZONE, your flag is forced on, the PVP button cannot turn it off, Renown from incidents and boss tiers inside pays +50%. A level 9 sees the bar but never gets flagged.
12. Plates: every other player has a plate with name, FAME n (INFAMY for villains), PVP and DOWNED tags; tap it: REPORT (4 reasons; a second report on the same player within 10 minutes says "already"), MUTE hides their chat for you. Three accounts reporting one player within 10 minutes prints a review line.
13. Fame: DEV > +200 Fame: rank up toasts (FAME RANK 2, 3), the Spotlight Visor style shows in GEAR at rank 3.
14. Strikes: speed hack test (DEV teleport tools or a CFrame jump far away): pulled back each time; 3 big jumps inside 10 minutes would kick on a live server (Studio prints "would kick"). Remote fuzzing (wrong types, NaN, floods) only drops calls and, if flooding, counts strikes. No ban anywhere.
15. Gate: a 30-minute exploit test with 2 to 3 players (toggle spam, combat logging, alt farming, speed hacks, remote fuzzing, duplication via fast equip and salvage) finds nothing that pays, hurts an unflagged player or duplicates gear.

### M7 Opening, Act 1, missions
DEV panel (M7 rows): Opening (replays it), Open step (jumps the running opening to a step), Mission (cycles 2 to 6 and enters it), Finish step (the current mission or quest step), Leave mission, Quest (cycles the 8 arcs and talks to that NPC), Act 1 done, Reset story. DEV > Wipe profile then rejoin gives a fresh character.
1. Fresh profile: the cinematic plays (comet, rooftops, the shadow over the moon, the street); SKIP shows after 2 s. Underneath you stand on a roof at dusk with only a pulsing LEAP button and a gold diamond over the next roof. No other text or numbers on screen.
2. Leap across; in the air the button reads GLIDE; the diamond moves to the tram car hanging off its rail below. Glide down to it: a big CATCH button pulses (C on PC). Catch: the car settles, 3 citizens run off, +50 RENOWN pops.
3. ZAP pulses and 2 Spark Drones come: the first falls to 2 hits and never shoots; the second takes 4 and hits lightly. The no-tutorial test: 5 first-timers stop the first drone within 30 s with no help (fail if 1 of 5 needs help).
4. A shard and a trapped citizen glow nearby; go to them: SAVE HER and GRAB IT appear. Save: carry her (hold B) to the green beam pad on a roof. Grab: drones chase you to the purple beam toward the Docks. Both reach Suit Up within about 3 minutes.
5. Suit Up: pick a class and Hero or Villain (preset by your choice), SUIT UP: level 3, +1 Skill Point, FLY appears, the full HUD returns and a marker leads to the nearest beacon (SKIP works). The side shows on the HUD and incidents start.
6. Rejoin mid-opening: it starts again from the roof. Get defeated during it: you come back on the roof or at the tram.
7. Journal (J or JOURNAL): STORY lists 6 missions (Shardfall cleared, Hold the Line READY at level 3, the rest LOCKED or LEVEL n), START enters; QUESTS shows the 8 NPCs and where they are; REP shows 3 bars; PERKS is empty until Spare the Core.
8. Mission 2 hero (Hold the Line): fade into a sealed glass pocket; stand in each of 3 rings 10 s while waves come; the train-or-thief choice; Save the Train (hit the yellow train 30 times) or Chase the Thief (beat the Sneak Bot hopping the roofs). The result card shows Credits, Renown, gear and +2 Skill Points; you fade back to where you started. Villain (DEV > Side): break 3 shard crates (14 hits each) guarded by 2 sentries.
9. Mission 3 Signal Tower: fly to the top, beat the Null Sentinel (much tougher) and its drones, hold the mast ring 6 s. +600 Renown on the first clear.
10. Mission 4 The Informant: reach the contact roof, Trust Her or Test Her (Test adds a 4-bot ambush), chase the Sneak Bot round the roofs. Mission 5 Under the Docks: clear room 1, run the sentry gauntlet (2 sentries if you trusted her, else 4), beat the vault guard, then Spare the Core (Null Echo buddy follows you; others see it) or Overload It (+800 Credits, +600 Renown).
11. Mission 6 The War-Frame (level 8): it drops in; break the 2 shoulder cannons; at 66% 6 drones arrive and a purple bubble shields it until 3 hits on the glowing back core; at 33% fire lines and a charged laser: hide behind a pillar and it misses. Get wiped: you respawn in the pocket and it keeps its HP. Defeat: it falls apart; Rare plus Epic gear, +1 Skill Point. With Overload, the pillars crackle.
12. Replay a cleared mission: the choice step says your first choice stands; only the mission's base Credits and Renown pay.
13. Side quests: talk to each NPC (hold B): a speech bubble, the tracker on the left of the top and a marker; finish all 3 steps of the Mayor (records, the speech ring, the motorcade that only rolls while you are near), Pip (helmet, clear 3 real incidents, carry Pip to the pad), Maribel (rebuild ring, defend, pick a menu), Old Beacon (4 rings in 45 s, 5 drones, land on a high roof; villains talk to the Velvet Paw next to him), Tamsin, Quill, Iron Dee and Skye. Rewards: Mayor's Sash and Dock Coat styles in GEAR, the Salute emote, the cafe sign and photo frame unlock toasts, a Skill Point, a Rare piece, the Decoy gadget.
14. Gate: 7 players in 7 missions at once; an 8th gets "every mission pocket is in use". The server frame holds and nobody in a pocket gets incidents or boss banners.

### M6 Incidents, contracts, events, boss
DEV panel (M6 row): Inc (cycles the 10 templates, spawns that one next to you), Clear incidents, Ev (cycles the 6 events), Boss now (lands in 3 s), Boss to 1 HP, Finish contract, Clock (day, dusk, night, dawn), Side (hero or villain for this session).
1. Play: no errors. Within a few seconds 2 incidents appear within 300 studs: a "!" marker (blue League, red Syndicate) with name and distance, and rows in the tracker on the right (time left, progress bar). Clear one: a CLEARED toast with a medal, Credits and Renown, sometimes a drop; a new one appears within 10 s. Walk 600 studs away: it quietly goes and another spawns near you.
2. Each template once via DEV > Inc: Robot heist (squad on a street); Tower fire (citizens on 3 balconies of a tall building with flames, carry each to the Rescue pad: hold B on a citizen, fly to the pad); Runaway tram (yellow tram rolling east or west along a Downtown tram line, hit it to brake; it fails if it reaches the end of the line); Falling sign (stand in the ring 5 s; on a fail the billboard drops); Rooftop chase (a Sneak Bot hopping roofs, or the street out of town; it slows when nobody chases); Cat on a crane (Docks crane top); Raid prep (only during the 5 minutes before a boss); villain side (DEV > Side): Vault breach, Shard crate, Comm sabotage (relay dish).
3. Citizens: the prompt shows only within 12 studs; carried ones ride on your back; get defeated while carrying and the citizen goes back to where they were, unhurt. Two players cannot grab the same one.
4. Contracts: at level 4+ (DEV > Level +5) use the Contract Board terminal at a safehouse (hold B): 3 offers with pay (x2 for the first 5 a day), ACCEPT up to 3. Try each type: Drone sweep (3 squads), Rescue run (carry 5 citizens to any safehouse), Shard recovery (the tracker shows the nearest shard's distance and compass direction; only you can pick yours up), Escort (the truck moves only while you stay within 40 studs, 2 ambushes), Vault job (villain), Stakeout (hero: keep a Sneak Bot in view within 40 studs for 2 s for a SNAP). Rejoin: accepted contracts come back with their progress. ABANDON removes the sites.
5. Events: DEV > Ev for each: an EVENT banner toast for everyone, a gold marker and tracker row; Meteor shower (warning rings across the plaza, shards after 4 s), Robot rampage (4 waves), Tidal surge (water rises over the Docks while you carry 12 citizens to 2 boats), Vault breach (hold the ring 30 s while robbers come), Train hijack (stop the train before the end of the line), Blackout (Old Town goes dark; clear the 2 drones at each of 4 generators, hold each 5 s). Everyone who helped gets the EVENT DONE toast. Left alone, a new event arrives every 4 to 6 minutes, at most 2 at once.
6. World boss: DEV > Boss now (or wait 10 minutes on a fresh server; a wiped profile pulls it to 6 minutes). At T minus 60 s a red banner counts down (Raid prep incidents start 5 minutes out; each clear takes 3% off its HP). Rustjaw Prime drops from the sky south of the plaza; the bar shows HP, phase marks, time left and your tier and rank. Its core and knees take double damage; the 2 shoulder cannons shell heroes until broken. Telegraphs: red rings and cones fill before each Stomp and Swipe; Scrap Rain circles in phase 2; Eye Laser lines in phase 3; a stomp next to a building damages it.
7. Lumen Maw (next boss): rises in the Old Quarry; 3 generators around the pit heal it until broken; Gravity Pull drags you toward it in phase 3 while its ring warns.
8. Contribution: a healer or shielder who never hits it still reaches Contributor in a 4-player fight; a player who arrives with 1 minute left still gets at least the floor. Heroes and villains (DEV > Side) hit the same bar.
9. Result: DEV > Boss to 1 HP, then hit it: it falls apart in sparks and plates; the result card (5 s, tap to close) shows tier, rank, Credits, Renown, drops, a style unlock (GEAR > Styles) and the MVP names. Let it run 8 minutes instead: it flies off and the card says it got away (Credits only).
10. Clock: DEV > Clock steps day, dusk, night, dawn; the sky glides there and night is darker blue but readable. At night more red Syndicate incidents show up (with Side: villain).
11. MAP shows incident dots, event diamonds and the boss.
12. Gate: with 30 bots plus you, the Dev panel's "schedulers" and "boss" times stay low and the server frame holds; nothing idles more than 5 s (an incident is always within reach).
