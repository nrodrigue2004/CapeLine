# CLAUDE.md: rules for this repo

Read this first. Keep it short. Quality comes first; efficiency never means lower quality.

## Project
- What it is: **Capeline**, a Roblox open-city superhero and anime action RPG: build a hero or villain, fly and fight across a destructible comic-book city with up to 30 players, 4 classes, 5 power sets (Volt, Frost, Titan, Pulse, Blade), Awakening, tiered gear, a world boss every 20 to 30 minutes, opt-in PvP. Slot 13 of nate's lineup, built now (nate, 2026-11-16).
- Source of truth for design: "Capeline build spec" (https://claude.ai/artifact/CeeEePQMFiY4hBKzbieNLG), plus nate's 2026-11-16 anime additions in `notes/Decisions.md`. Never edit nate's docs; record any change to a spec number in `notes/Decisions.md`.
- Stack: Luau, Rojo 7.4.4 (`default.project.json`), tools pinned in `rokit.toml`. Owner: nate.
- Commands:
  - `rojo build default.project.json -o build/Capeline.rbxl` (the city place, Brightharbor)
  - `rojo serve` (live sync into Studio with the Rojo plugin)
  - `lune run tests/run.luau build/Capeline.rbxl` (unit and sim tests + place layout check; `ONLY=M1` in front runs only tests whose name has M1)
  - `selene src tests` and `stylua src tests` (lint and format; run stylua twice)
  - `python3 tests/callcheck.py .` (every required-module call names a real function)

## Memory: read these, keep them current
- `notes/Current Progress.md`: done / in progress / next. Under 20 lines. Read it at the start of every session.
- `notes/Tasks.md`: milestones in order with their "done when" checks, plus the Studio test list (what needs nate's PC).
- `notes/Decisions.md`: every design or technical decision, one line each with the date. Check it before changing direction.
- `notes/Working Agreement.md`: how nate wants the work done.
- `notes/Launch Checklist.md`: what nate does before going public (ids, sounds, art, rules).
- `notes/Tools.md`: third-party libraries, plugins and MCPs reviewed for this game, with licenses.

## Code map
- `src/config` (ReplicatedStorage.Config): every tuning number as pure data, one module per spec table (Move, Stats, Classes, Abilities, Enemies, Combat, City, Presets, Net, Safety, Fx, Ui, Dev, Places, Version, Gear, Loot, Economy, Data, World). `init` indexes them.
- `src/shared` (ReplicatedStorage.Shared): `Net` + `NetSchema` + `Remotes` (all remotes, schema checks, rate limits), `Rng`, `Formulas` (every spec formula), `MoveMath` (leap, glide, flight, stamina, speed caps), `MoveCheck` (server speed budget and strikes), `PosHistory` (30 Hz lag rewind), `HitQuery` (bolt, cone, chain, capsule targeting), `Cooldowns`, `Status` (crowd control and buffs), `AbilityRules` (ranks, mods, budget, loadouts, recasts), `CastPlan` (every ability shape as pure geometry), `Awakening` (meter and team-up combos), `GearMath` (piece budget, stats, upgrades, salvage, sets, perks, styles), `LootTable` (drop rolls, pity, level gates), `Progress` (levels, Renown, earn formulas, spending), `ProfileSchema` (the save: defaults, migrations, repair, client view), `Inventory` (equip, salvage, upgrade, retune, styles on a profile), `EnemySim` (6 humanoid robot AIs as plain data), `EnemyBuffer` (Enemy.Delta packets), `CityLayout` (seeded Downtown greybox), `BoxKit` (shared box helpers: houses, trees, roofs), `Districts` (the Docks, Old Town), `WorldGen` (weekly seed, tile array and hash, outskirts tiles, roads, landmarks), `HeightMap` (whole-map roof heights), `WorldMap` (the whole world for one seed: hub, tiles, safehouses, beacons, heights), `Travel` (fast travel, bank and respawn rules), `Util/` (Maid, Signal). Pure modules have no Roblox instances so Lune runs them.
- `src/server` (ServerScriptService.Server): `Services/` PerfMonitor, CityBuilder (builds the world, hub first, outskirts 40 tiles a frame), HeroService (heroes for players and bots, health, regen, buffs, Awakening), MoveGuard (history, speed checks, boost stamina), EnemyService (runs EnemySim, Enemy.Delta, CombatEvents), CombatService (casts, channels, fields, walls, combos), AbilityService (learn, rank, mods, loadouts, respec), DataService (session-locked saves, ported from Ragdoll Rides), EconomyService (Credits, Renown, Dust, level ups, friend boost), GearService (drops, stash, equipment, styles, gadgets), LookService (gear looks on bodies), PerkService (Quakeheel, Echo Trail), SafehouseService (terminals, visits, respawns, where loadouts may change), BeaconService (beacon discovery, fast travel), LoadBots (30-bot load test), DevService (Studio commands).
- `src/client` (StarterPlayerScripts.Client): `State`, `Controllers/` (InputController, MoveController, CameraController, CombatClient, GadgetClient, TravelClient, EnemyRenderer, QualityController), `Fx/` (CombatFx in Comic and Anime styles, MoveFx, AuraFx), `Ui/` (Kit, Hud, LoadoutScreen, GearScreen, MapScreen, Toasts, DevPanel).
- `src/first` (ReplicatedFirst): `LoadingScreen`. `src/character`: the empty Health override.

## Quality
1. Extend what exists. Do not re-implement or restyle working systems, and do not revert nate's work.
2. Shipped-game quality. Placeholder art is labelled PLACEHOLDER ART in code and listed in Tasks.
3. Verify before saying done: lint clean, tests pass, place builds. Anything only Studio can prove goes on the Studio test list.
4. Design pillars and north star (reach and revenue) apply to every decision. Cartoon combat, no blood, machines-only enemies, no free text, nothing sold changes stats.
5. Downloads are allowed (nate, 2026-11-16) with licenses checked and noted in Tools.md; never spend money or publish without nate's OK. Original characters, powers and symbols only: anime-inspired, never copied from a real show.
6. Moderation leans hard toward not punishing players: no automatic bans; speed fails only pull the hero back.
