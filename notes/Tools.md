# Tools review (standing rule: consider third-party tools for every part of the game)

Downloads are OK (nate, 2026-11-16); anything paid needs nate's OK first. Check every license before use and
record the source here. Status: Using / Recommended (milestone) / Paid (ask nate) / Skipped (why).

## Code and pipeline
- Rojo 7.4.4, Selene, StyLua, Lune (MPL-2.0 / MIT): Using. Build, lint, format, headless tests.
- Roblox Studio MCP (built into Studio Assistant): Using when nate's Studio is open. Lets a session run Play tests and read Output; the best way to prove client code. See the roblox-dev-setup memory.
- ProfileStore by loleris (MIT, github.com/MadStudioRoblox/ProfileStore): Skipped for M3. The spec says to reuse the Ragdoll Rides saving package (session lock, migrations), which is ported into DataService with the same lock rules. Revisit only if the Studio save tests (M3 items 15 to 17) show a problem.
- Blink (MIT, github.com/1Axen/Blink), an IDL that compiles compact buffer remotes: Recommended to evaluate at M4 if the 20 KB/s per player budget is tight at 30 players. Our own EnemyBuffer already packs the hot path.
- luau-lsp (MIT): Recommended for type checking; its download was blocked by the cloud safety check on 11-15, retry from nate's PC.
- Jest-Lua / TestEZ: Skipped; Lune tests cover the pure modules without Studio.

## Art, VFX and animation
- Roblox Animation Editor (built in, free): Recommended for hero cast poses and the 6 robot rigs (walk, aim, slam, stab). The M2 robots are posed in code until then.
- Moon Animator 2: Paid (ask nate). Faster animation work; not needed for launch.
- Blender (GPL, free) plus the Blender MCP (github.com/ahujasid/blender-mcp, MIT): Recommended for M5 and M9: capes, hair, coats and building chunks as low-poly meshes Claude can help model.
- Kenney assets (CC0, kenney.nl): Recommended for UI shapes and placeholder textures (M10).
- game-icons.net (CC BY 3.0, attribution in the game description): Recommended for the 120 ability, slot and tier icons (M2 to M9), recoloured to one style.
- Creator Store free models and VFX: Recommended only after a license and script check (free models can hide scripts); restyle to the palette.
- AI 3D generators (Meshy, Tripo): Paid tiers (ask nate). Possible for props and hair at M9.

## World (M4)
- Roblox streaming built-ins (StreamingMesh level of detail, Atomic models, RequestStreamAroundAsync): Used. No third-party city generator fits a seeded, hashable tile array, so WorldGen is our own code.
- Roblox SHA libraries on GitHub (e.g. pure-Luau hashing modules, MIT): Skipped; the M4 hash only has to match between servers, so a 20-line FNV-1a does the job without a dependency.

## Destruction (M5)
- Voxel and fracture destruction modules from the DevForum and GitHub (e.g. VoxBreaker-style part splitting): Skipped, licence not reviewed since not used. They split parts at run time on the server and replicate every piece, which a 30-player server cannot afford; the spec wants state-only replication, so the Chunker is our own seeded code.
- Roblox built-in particle texture rbxasset://textures/particles/smoke_main.dds: Used for collapse dust (ships with the engine, no download). Replace with a generated texture at the art pass.

## Audio
- Creator Store audio (Roblox-licensed for use on Roblox): Recommended for the 110 effects and 3 music loops (M11).
- Freesound (check each clip: CC0 preferred, CC BY needs credit): Recommended as a backup source.

## Analytics and monetization
- Roblox AnalyticsService custom events and funnels (built in): Recommended for M12, as in Ragdoll Rides and Mossbell Stand.
- Roblox Creator Dashboard price testing for passes: Recommended after launch.
