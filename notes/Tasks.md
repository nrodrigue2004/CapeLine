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
| M5 | Destruction v1 | Chunker, 220 hub buildings with 3 states, debris, craters, vehicle flips, repair drones, citizens | 10 players wreck a block for 10 minutes with no server spike and 30+ fps on a phone; everything repairs | |
| M6 | Incidents, contracts, events, boss | Incident spawner with 10 templates, 6 contract types, 6 random events, world boss with 2 bosses, contribution rewards | First boss within 8 minutes; boss rewards by tier; no idle wait over 5 s | |
| M7 | Opening, Act 1, missions | Cinematic, playable disaster, choice, 6 missions in sky pockets, 3 choices, 8 side quests, journal | 5 new testers finish the opening and suit up with no help; both routes reach the finale | |
| M8 | PvP, death, anti-exploit | Flag, Crater, Downed and Defeated, Fame and Infamy, rules table, strikes | The 30-minute exploit test finds nothing; PvP rules checklist passes | |
| M9 | Creator, HQ, shop, passes | Creator with the 116 spec pieces plus the anime pieces and the Comic/Anime pick, 2 HQs, Gizmo's shop, Robux shop, passes, slots, Legacy | A tester makes a hero in under 3 minutes; test purchases grant once; looks show to others | |
| M10 | UI and phone pass | All screens, settings, accessibility, presets, map, squad | Every screen has loading, empty and error states; device matrix passes | |
| M11 | Juice, audio, wait fillers | Juice table, sounds, music, offline drones, downed polish, friend boost, Photo Mode | No idle wait over 5 s in a 30-minute session with 8 testers; every action has a sound and visual | |
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
- Load bot bodies (LoadBots, Studio only).
- Landing crack: dark disc instead of a crack decal (MoveFx).
- Flight, leap and glide poses: the default avatar tilted along the travel direction; no custom animations yet (MoveController).
- Loading screen: title on a gradient (LoadingScreen). The cinematic comes in M7.
- HUD: Kit placeholder look (M10 restyles).

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
