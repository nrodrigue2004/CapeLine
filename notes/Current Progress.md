# Current Progress

- Done: M1 to M12 code-complete (2026-11-16): movement, classes and abilities, robots, gear and loot, the seeded world, destruction, incidents, contracts, events, world bosses, the opening and Act 1, PvP, Creator, HQ, shop and passes, UI and phone pass, juice and audio, analytics and launch notes (Playtest Kit, Store Page, Soft Launch Plan, Build Log).
- Done 2026-11-16 after M12 (nate's asks): Red Faction-style destruction (Shared.Structure), robots whose shell breaks off (Shared.RobotDamage), 4 archetypes and 17 paths (136 abilities), 5 mobility picks, underwater at launch. Save v7.
- Done 2026-11-16 (overhaul, nate OKed the plan): Blender pipeline (art/blender) and robot meshes, FrameProf, the blocky R15 hero body; everyone (robots, citizens) on the same R15 rig, play-tested in Studio with 0 errors.
- Done 2026-11-16/17 (hero creator and weapons plan): save v9 look, 503 creator pieces, all 36 weapons playable (180 moves), the 8 Blender body sets (wait on the Bodies.fbx import).
- Done 2026-11-17: hero animations (Shared.HeroAnim), the effects library (FxLib, nate liked it), hold to aim and charge, the remade Spark Trooper (Art.Trooper), robots' Roblox look (27 uniforms, 6 faces), heroes and citizens in our own classic shirts and pants (nate's call). Each waits on nate's uploads or imports; Studio lists in Tasks.md.
- Done 2026-11-17 (overhaul step 3): Downtown kit block (art/city/materials.py, art/blender/street.py + block.py, Config.City.kit). Studio list "Downtown kit block".
- Done 2026-11-17 (overhaul step 5): the kit look on the whole city: every Downtown block, the Docks, Old Town and the outskirts tiles, each with its own fronts, ground and props (19 textures, 21 street props, Shared.CityKit; props built on each device near the camera by preset, CityProps). Previews art/preview/{block,Docks,OldTown,Suburbs}_{street,air}.png. Studio list "City kit: the whole city".
- Planned 2026-11-16 (nate approved): Hero MMO features (spec milestones H1 to H8), ON HOLD until nate asks to build.
- Next: nate judges the slice (robot + city), uploads the 19 textures and imports Street.fbx; then overhaul step 4 (robots and bosses). Lore and missions are with the lore thread.
- Waiting on nate: the Studio test lists (everything client-side is unrun in Studio), the M12 balance call, store art, the age questionnaire, then the playtest week and the quiet launch.
- Repo: local only (/home/user/capeline, branch main). Backup after every milestone: /mnt/project-files/capeline/ (capeline.bundle, Capeline.rbxl, notes). Restore: `git clone capeline.bundle capeline`.
- Tools: rojo, lune, selene, stylua, luau-lsp in ~/tools. Auto-resume: a check fires every 90 minutes (send_later) and reschedules itself.
