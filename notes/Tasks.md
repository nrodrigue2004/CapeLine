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
| M12 | Test and launch prep | Playtests, balance, thumbnails, icon, analytics, soft launch plan | 20 testers play with no crash reports in one session week; analytics visible | |

## Placeholder art and animation (replace before launch)
- City: Downtown greybox boxes, window bands and rooftop props (CityBuilder). PLACEHOLDER ART.
- World (M4): the Docks, Old Town, hub filler blocks, all 32 outskirts tile variants (houses, shops, parks, farms, coast), the 3 landmarks, safehouses, beacons, the sand and the ocean are simple parts (Districts, WorldGen, WorldMap). Balls stand in for leaves, domes and dunes. PLACEHOLDER ART until the M5 kit.
- Map screen: flat coloured squares for zones, districts and landmarks; no tile detail (MapScreen). Fast-travel flight is a camera sweep with the hero left standing (TravelClient). PLACEHOLDER ART until M10.
- Robot bodies: all 6 humanoid robots are built from blocks and cylinders with a code-driven walk, aim and windup pose (EnemyRenderer). PLACEHOLDER ART until meshes and animations.
- Ability visuals for all 40 powers: neon parts, beams and rings (CombatFx, AuraFx). PLACEHOLDER ART until particle textures and the icon set.
- Snow Wall pieces, the Ice Slide ramp and the thrown crate in Lift and Throw: plain parts (CombatService). PLACEHOLDER ART.
- Ability buttons show short names, not icons (Hud, LoadoutScreen). PLACEHOLDER ART.
- Cast poses: no arm or body animation on the hero when casting yet.
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
- Flight, leap and glide poses: the default avatar tilted along the travel direction; no custom animations yet (MoveController).
- Loading screen: title on a gradient (LoadingScreen).
- Story (M7): the cinematic is 4 flat comic panels (StoryHud); the opening's tram car, shard, trapped citizen and beams are plain parts (StoryFx); mission pockets are greybox boxes (PocketLayout); the War-Frame is a part-built mech (WorldFx); quest NPCs are blocky figures with a name tag and a marker (QuestService); the Null Echo buddy is a ball with an eye; the Journal, Suit Up, choice card, trackers and result card use the Kit placeholder look. PLACEHOLDER ART.
- PvP and death (M8): flag rings and the Downed ring are flat neon discs, the PvP defeat is a CombatFx spark burst, Help/Here/Danger pings are text markers (PvpFx); name plates, the plate menu, the PVP button, the Crater bar, the Downed and Defeated screens and the PvP card use the Kit placeholder look (Plates, PvpHud). The Downed hero has no kneel or crawl animation yet (the humanoid just walks slowly). PLACEHOLDER ART.
- Creator pieces (M9): all 146 suits, capes, coats, scarves, masks, gloves, wraps, boots, hair, eyes, auras and trails are blocks, wedges, balls and neon parts welded to the body; emblems are a glyph on a SurfaceGui; auras are the engine's default particle (LookKit). PLACEHOLDER ART until accessory meshes.
- Voice packs (M9): the 4 voice choices have sound ids 0 (Config.Shop.voiceSounds). PLACEHOLDER until free-licensed clips (M11).
- Emotes and landing poses (M9): joint angles tweened on the rig (EmoteFx). PLACEHOLDER ART until real animations (M11).
- HQ rooms (M9): Beacon Tower and The Foundry are box rooms with neon pads and signs, part-built dummies and boss sim robot, marble copies of the hero for statues, box trophies and props (HqClient). PLACEHOLDER ART.
- Creator, Robux shop, HQ panels (M9): Kit placeholder look, text tiles, no piece icons; the preview is a ViewportFrame copy of the hero (CreatorScreen, ShopHud, HqHud, Preview). PLACEHOLDER ART until M10.
- HUD: Kit placeholder look (M10 restyles).
- M11 sounds: every juice sound is one of Roblox's built-in client sounds (rbxasset://sounds: swoosh, jump land, falling, get up, ping, button, click) pitched per action; music loops and voice clips are silent (asset 0) (Config.Audio, Config.Shop.voiceSounds). PLACEHOLDER SOUND until nate picks licence-checked Creator Store ids.
- M11 juice visuals: coin burst, medal and NEW stamps, the level badge, tier beams, fireworks, confetti, the shield ring and dazed stars are neon parts and Kit frames (JuiceFx); Photo Mode backdrops are Kit frames and colour grades (PhotoMode); the photo poses are joint angles (EmoteFx). PLACEHOLDER ART until the art pass.
- M10 screens: Settings, the squad list, panel and invite card, the radar (Kit shapes and glyphs: circle, diamond, triangle, square, star), the ping wheel, the settings gear and the main menu are Kit placeholder looks (SettingsMenu, SquadHud, Radar, Shapes, Hud, MainMenu). PLACEHOLDER ART until the art pass. The squad emblem is a text glyph.

## Studio test list (needs nate's PC)
Start: `rojo serve`, connect the Rojo plugin, press Play (or Test > Clients and Servers with 2 players). The DEV button (top right, Studio only) has the test tools.

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
DEV panel now has: 3x robot (cycles all 6), Level 40, +10 Skill Pts, Fill Awakening. Skill ranks are free of Credits in Studio (Config.Dev.freeRankCredits) until M3.
1. HUD: four skill buttons (Q, E, R, T), a SUPER button (G) from level 20, a POWERS button (L), and the Awakening meter under health. No errors in Output.
2. POWERS screen: tabs for Volt, Frost, Titan, Pulse, Blade (locked until 1, 6, 10, 14, 18). LEARN, RANK UP and EQUIP work; the budget reads x / 52 and refuses an over-budget loadout with a clear notice. At rank 3 (rank 2 for supers) two mod buttons appear. SET PRIMARY changes the basic attack and the colours. Loadout 2 opens at level 15. RESPEC refunds everything (10 minute wait, not in combat).
3. Mixing: equip a Frost skill on a Volt primary; it works and keeps its own Frost look.
4. Every ability in both styles (DEV > Level 40, +10 Skill Pts a few times, then try each set). For each: it fires where you aim, the number and look match its kind (bolt, chain, dash, cone, arc, nova, line, leap, throw, field, buff, wall, ramp), the cooldown sweep matches, and robots react (stun ring, ice tint, float, pull, knock-up, knock-back into walls).
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
12. Perks (DEV > Level 40, then Loot: bossMvp until a Legendary): Quakeheel shockwave on a 30+ stud landing; Cooling Kill takes 20% off the super's cooldown sweep on a kill; Second Wind saves you once per 5 minutes (God OFF); Echo Trail hurts robots you fly fast past; Lucky Strike crits every 8th hit; Shared Spark raises a nearby ally's Power (2 players).
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
DEV panel (M9 rows): Creator (opens it in "first" mode), Enter HQ, HQ level (cycles 1 to 6), Away 8 h (pays the offline drones), All pieces, Buy (grants the shown shop item with a fixed test receipt, then steps to the next), Level 40.
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
12. Legacy: DEV > Level 40, Hall of Legends > RETIRE > YES: LEGACY RANK 1, a marble statue of the old hero in the hall, the hero is level 1 with the same look, name and side and a star on the plate.
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
