# Playtest Kit (M12)

The M12 gate: **20 testers play with no crash reports in one session week, and the analytics show in the Creator Dashboard.** This is how to run that week. Everything here needs nate's PC and a published (private) place, so nothing runs until nate says go.

## Before the week
1. Publish the place as a **private** experience (Launch Checklist: publish, Studio API access on, product ids filled or left at 0 for test receipts). Do not make it public.
2. Turn on Creator Dashboard > Analytics. Custom events and funnels appear about a day after the first players.
3. Invite testers through a private server link or the experience's Collaborators/Test group. Aim for 20 different people over the week, with at least: 4 on a low-end phone, 6 on a mid-range phone, 2 on a tablet, 6 on PC, 2 on a controller (spec device matrix).
4. Mix of testers: at least 5 who have never seen the game (they run the first-30-seconds checks), and the rest any age 9+ (the game is rated Moderate; do not test with under 9s).
5. Studio first: run `lune run tests/run.luau build/Capeline.rbxl` (all green), then a 30-bot load test (Dev panel BOTS 30) for 10 minutes and note the server frame.

## Each session (30 to 45 minutes)
- 3 to 8 testers in one server when possible (squads, boss, PvP need people).
- Script for new testers: say nothing, hand them the device, watch the first 3 minutes (opening and Suit Up). Note any moment they ask for help.
- Then free play with three asks: finish one incident, one contract, and join the world boss when the siren sounds.
- PC/Studio watcher keeps the Dev panel open: server frame, idle waits, analytics events, server script errors.
- After: 3 questions, out loud or a quick form (no names kept): Did flying feel good? Did hitting feel good? What was boring or confusing?

## What counts as a crash report
- A tester's client freezes, closes, or shows "Disconnected" not caused by their network.
- Any server script error line in the Output (the Dev panel's "server script errors" count) or in Creator Dashboard > Error report.
- A lost save: anything a tester earned is missing after rejoining.
One crash report in the week fails the gate: fix it, then the week restarts from that day.

## Build log
Write one line per session in `notes/Build Log.md` (date, testers, devices, crashes, idle waits, what broke). The spec says a box is ticked only when a person ran the check and wrote the result.

## The spec's test checklists, re-run at M12
Where: **Auto** = the Lune tests already check it every build; **Studio** = the Studio test list in Tasks.md; **Week** = needs real testers in the playtest week.

| # | Check | Where | Result |
|---|---|---|---|
| 1 | 5 first-time testers stop the first drone within 30 s with no help (fail if 1 of 5 needs help) | Week | |
| 2 | The only text on screen in the first 3 minutes is the verb buttons | Week | |
| 3 | Both choices (Save Her, Grab It) reach Suit Up within 3:00 and set the creator side | Studio (M7) + Week | |
| 4 | A tester makes a hero in under 3 minutes and the look shows on other players' screens | Week | |
| 5 | Skipping the cinematic does not skip control hand-off or the first incident | Studio (M7) | |
| 6 | 4 of 5 testers say flying and hitting feel good on a phone | Week | |
| 7 | 30+ fps on a mid-range phone flying the whole map at boost and fighting 20 enemies | Week (perf_sample) | |
| 8 | Every class solos a contract and has a clear role in a 4-player test; Bruiser never out-damages Blaster, Blaster never out-tanks Bruiser | Auto (M2) + Week | |
| 9 | No loadout exceeds 52 skill points, even from forged Hero.Loadout remotes | Auto (M2) | |
| 10 | PvP time to defeat at equal gear 8 to 14 s; PvE Burglar Bot at level 10 takes 2 to 3 s | Auto (M2, M8) | |
| 11 | The server rejects a cooldown ignored by 200 ms and accepts one ignored by 50 ms | Auto (M2) | |
| 12 | Every drop source matches its odds over 10,000 rolls (within 1%) | Auto (M3) | |
| 13 | Pity on the 5th boss without an Epic and the 15th Legendary roll | Auto (M3) | |
| 14 | Any look over any gear; salvaging an equipped piece is rejected | Auto (M3) + Studio | |
| 15 | Rejoin restores gear, ranks, styles, level, choices and points; a second server can't open the same profile | Studio (M3) + Week | |
| 16 | A forced server crash loses at most 120 s of progress | Studio (M3) | |
| 17 | Two servers with the same seed log the same tile hash | Auto (M4) + Studio | |
| 18 | A full region streams at 30+ fps on a phone; boot to open under 20 s | Studio (M4) + Week | |
| 19 | 30 bots hold the 16 ms server frame for 10 minutes | Studio (M4) | |
| 20 | 10 players wreck a block for 10 minutes, no server spike over 50 ms, 30+ fps on phones | Week | |
| 21 | A 4th collapse at once is cut to Damaged; every building repairs within 6 minutes | Auto (M5) + Studio | |
| 22 | A late joiner sees the same building states within 2 s | Studio (M5) | |
| 23 | A new account's first boss starts within 8 minutes | Auto (M6) + Week (first_boss_join) | |
| 24 | A late joiner gets at least the 25% floor | Auto (M6) | |
| 25 | A healer-only player reaches Contributor | Auto (M6) + Week | |
| 26 | Heroes and villains share the boss bar; flagged players fighting each other still earn halved PvP rewards | Auto (M8) + Studio | |
| 27 | 6 random events fire in order without more than 2 at once | Auto (M6) | |
| 28 | The 30-minute exploit test (toggle spam, combat logging, alt farming, speed hacks, remote fuzzing, duplication) finds nothing | Studio (M8) | |
| 29 | The flag can't turn off for 60 s after PvP damage, or inside the Crater | Auto (M8) | |
| 30 | An unflagged player can't be hurt by any ability, area or chain from a flagged player | Auto (M8) | |
| 31 | Rewards hit zero after 2 wins on the same player in 30 min; 3-and-3 trades pay zero both ways | Auto (M8) | |
| 32 | Below level 10: no flag button, can't be forced into the Crater | Auto (M8) + Studio | |
| 33 | Spawn protection (5 s) ends early on attack and can't be reused | Auto (M8) | |
| 34 | 1,000 simulated heroes over 10 hours reach level 20 to 28 and spend within 15% of the Sinks table | Auto (M9) | passes (median 24) |
| 35 | Test purchases grant once; a replayed receipt grants nothing | Auto (M9) + Studio | |
| 36 | No Robux item changes a stat, roll or Credits balance (except the 2x pass on earnings) | Auto (M9) | |
| 37 | The Robux shop opens only in HQ, safehouses and the menu | Auto (M9) | |
| 38 | Device matrix: low-end phone, mid phone, tablet, PC, controller each finish the opening, a contract and a boss | Week | |
| 39 | Reduce flashing removes shake, hit-pause and flashes; colorblind rings read as round and squared | Studio (M10) | |
| 40 | No idle wait over 5 s in a 30-minute session with 8 testers | Week (idle_wait, Dev panel) | |
| 41 | 20 testers play with no crash report in one session week; analytics show in Creator Dashboard | Week | |
| 42 | No copied superhero or anime names, emblems or colour-and-symbol combos in the shop or the 40 emblems | nate review | |

## Reading the analytics after the week
Creator Dashboard > Analytics:
- **Funnels > Onboarding (Opening)**: 12 steps from session_start to d1_return. The pillar: 85% reach first_blast. A big drop at one step names the step to fix.
- **Funnels > Combat, PvP, Story, Purchase**: drop-offs between steps.
- **Custom events**: perf_sample (median fps by device; phone median 30+), idle_wait (should be near zero), leave (state shows where people quit), anti_exploit_flag and report_player (safety).
- In Studio, every event also prints as `[Analytics] name value fields` in the Output, so a Studio session proves the wiring before the week.
