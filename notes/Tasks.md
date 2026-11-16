# Tasks

Milestones in order (spec "Milestones and cut list", plus nate's 2026-11-16 anime additions). Each one is
code-complete when lint is clean, tests pass and the place builds; the "done when" checks that need people,
phones or Studio go on the Studio test list below.

| # | Milestone | Scope | Done when (spec) | State |
|---|---|---|---|---|
| M1 | Move and fight slice | Leap, Glide, Flight with touch, PC and gamepad controls; Volt basic + 2 skills; clash hit feel; Spark Drone; greybox Downtown; 30-bot load test; Comic and Anime effect styles | 5 first-timers stop the first machine in 30 s with no help; 4 of 5 say flight and hits feel good on a phone; 30+ fps on a mid-range phone | Code-complete 2026-11-16 |
| M2 | Classes, abilities, enemies | 4 classes with passives, 5 sets (Volt, Frost, Titan, Pulse, Blade) with 40 abilities in both styles, the super slot, Awakening, ranks, mods, power budget, 6 enemies, data tables | Every class solos a contract and has a clear role in a 4-player test; no loadout exceeds the budget | Next |
| M3 | Gear, loot, saves | 5 tiers, 8 slots, stats, drops and pity, salvage, upgrade, style collection, profile and migrations, levels and Renown | Drops match the table; a tester wears any look over any gear; rejoin restores everything | |
| M4 | World generator, 30-player gate | Hub districts, seeded outskirts (2 zone types), weekly seed, streaming, presets, landmarks, safehouses, beacons, age questionnaire | Same seed gives the same hash on two servers; 30+ fps flying across the map on a phone; 30 bots hold the server frame | |
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
- Spark Drone body: sphere, ring, eye, fins (EnemyRenderer). PLACEHOLDER ART.
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
