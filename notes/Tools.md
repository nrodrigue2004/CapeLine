# Tools review (standing rule: consider third-party tools for every part of the game)

Downloads are OK (nate, 2026-11-16); anything paid needs nate's OK first. Check every license before use and
record the source here. Status: Using / Recommended (milestone) / Paid (ask nate) / Skipped (why).

## Code and pipeline
- Rojo 7.4.4, Selene, StyLua, Lune (MPL-2.0 / MIT): Using. Build, lint, format, headless tests.
- Roblox Studio MCP (built into Studio Assistant): Using when nate's Studio is open. Lets a session run Play tests and read Output; the best way to prove client code. See the roblox-dev-setup memory.
- ProfileStore by loleris (MIT, github.com/MadStudioRoblox/ProfileStore): Skipped for M3. The spec says to reuse the Ragdoll Rides saving package (session lock, migrations), which is ported into DataService with the same lock rules. Revisit only if the Studio save tests (M3 items 15 to 17) show a problem.
- Blink (MIT, github.com/1Axen/Blink), an IDL that compiles compact buffer remotes: Recommended to evaluate at M4 if the 20 KB/s per player budget is tight at 30 players. Our own EnemyBuffer already packs the hot path.
- luau-lsp 1.32.0 (MIT, github.com/JohnnyMorganz/luau-lsp): Using since M6 (the download works now). `rojo sourcemap default.project.json -o sourcemap.json`, then `luau-lsp analyze --sourcemap=sourcemap.json --definitions=<1.32.0 globalTypes.d.luau> --platform=roblox src`. Nonstrict optional-value warnings are noise; new errors in changed files get read.
- Jest-Lua / TestEZ: Skipped; Lune tests cover the pure modules without Studio.

## Art, VFX and animation
- Roblox Animation Editor (built in, free): Recommended for hero cast poses and the 6 robot rigs (walk, aim, slam, stab). The M2 robots are posed in code until then.
- Moon Animator 2: Paid (ask nate). Faster animation work; not needed for launch.
- Blender 5.0.1 as the `bpy` Python module (GPL; what we make with it is ours): Using since 2026-11-16. Installed in Claude's workspace with uv (`uv venv --python 3.11 ~/tools/bpyenv`, `uv pip install bpy`; download.blender.org is blocked there, PyPI works). Scripts in art/blender build, export and preview the meshes. The Blender MCP (github.com/ahujasid/blender-mcp, MIT) is Skipped: it drives a Blender window on a PC, and scripted builds are repeatable without one.
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

## World activity (M6)
- Roblox ProximityPrompt (built in): Used for rescues and the Contract Board, so the server checks range without extra remotes.
- Quest and objective frameworks on GitHub (e.g. generic Roblox quest modules): Skipped, licence not reviewed since not used. Incidents are short, seeded and pure-data tested (IncidentPlan); a framework would add instances and remotes the 2 Hz batched updates avoid.
- Boss fight frameworks (DevForum boss AI kits): Skipped for the same reason; BossSim is pure data so Lune can simulate whole fights.

## Story (M7)
- Roblox ProximityPrompt (built in): Used for NPC Talk and the opening citizen, so the server checks range without extra remotes.
- Dialogue and quest kits on GitHub and the DevForum (dialogue trees, quest log modules): Skipped, licences not reviewed since not used. Lines are fixed data in Config.Story (no free text) and StoryPlan is pure and tested in Lune.
- Moon Animator 2 and the built-in Animation Editor (Studio plugins): Recommended for nate when the cinematic and the War-Frame get real animation (M11 juice pass); nothing to install now. Moon Animator is a paid plugin, so it needs nate's OK.
- Text-to-speech or AI voice services for the mentor lines: Not used; listed on the Launch Checklist (licence for commercial use, no real actor likeness).

## PvP and safety (M8)
- Roblox TextChatService ShouldDeliverCallback (built in): Used for quick-mute on this device only.
- Roblox DataStoreService (built in): Used for the manual review queue (kicks, reports, trades).
- Server-authoritative movement frameworks on GitHub (e.g. Chickynoid, MIT): Skipped. They replace the whole character controller with server-simulated movement; Capeline's client-owned flight plus MoveGuard's speed budget already pull cheaters back, and swapping the controller would mean redoing M1's tested movement feel.
- Anti-exploit kits from the DevForum (remote spy blockers, client-side detectors): Skipped, licences not reviewed since not used. Client-side detection can be deleted by an exploiter; everything that matters (flag, hits, rewards, cooldowns) is already decided on the server.

## Creator, HQ and shops (M9)
- Roblox MarketplaceService ProcessReceipt and PromptGamePassPurchase (built in): Used, with the receipt flow ported from Ragdoll Rides (grant once per purchase id, PurchaseGranted only after a save).
- Roblox ViewportFrame + WorldModel (built in): Used for the creator and shop preview on a copy of your own hero.
- Roblox HumanoidDescription and the avatar catalog (built in): Skipped. Catalog accessories are other creators' items (IP and cost) and would not match the piece-based, original look.
- Character customisation kits on GitHub and the DevForum (avatar editors, outfit systems): Skipped, licences not reviewed since not used. Looks must pack into one 32-byte record for saves and replication, which LookCodec does in a few lines.
- Blender (free, GPL; the output is yours) and Roblox's Avatar Auto-Setup: Recommended for the M10 or M11 art pass to replace the box pieces with meshes; needs nate's PC.
- Robux price testing in the Creator Dashboard: Recommended after launch (the starter pack price A/B).

## UI, accessibility and squads (M10)
- Roblox UITextSizeConstraint (built in): Used. Kit.setTextScale raises every label's MaxTextSize for the 100 to 160% text size.
- Roblox ControlModule and the default touch thumbstick (built in): Kept for right-handed touch; replaced by our own stick for left-handed and one-hand modes because the default one can't be moved.
- Roblox gamepad UI selection (built in): Used as is; Kit buttons are selectable, so the new screens need no extra code. Studio test M10 15 checks it.
- Roblox Party and Experience Invite APIs (SocialService:PromptGameInvite): Recommended for M12 (inviting friends into the server grows reach); squads themselves stay per server.
- UI libraries on GitHub (Fusion, MIT; React-Lua, MIT; Iris, MIT): Skipped. Every screen already uses Kit; moving now would mean restyling working systems (CLAUDE.md rule 1). Fusion is worth a look for the next game.
- Colorblind simulators (Studio's built-in Accessibility color simulation, Coblis web tool, free): Recommended for nate's M10 Studio pass on the radar and map.

## Juice and audio (M11)
- Roblox built-in client sounds (rbxasset://sounds, shipped with every Roblox client): Used as the placeholder for every juice sound until licensed ids are picked. Free to use in experiences; they are generic and too few, so they are not the final mix.
- Roblox Creator Store audio (free, Roblox-licensed for use in experiences): Recommended for the 110 effects and 3 music loops; nate picks and checks each id (Launch Checklist). Roblox's own uploads and "Roblox"-owned tracks are the safest licences.
- Roblox SoundGroup, ColorCorrectionEffect, HapticService (built in): Used for the mix groups and ducking, Photo Mode grades and vibration.
- Free SFX sites (Kenney.nl CC0 audio packs, freesound.org CC0 only, Sonniss GDC bundles royalty-free): Recommended if the Creator Store lacks a sound; upload needs nate's account (audio upload counts against Roblox's monthly limits).
- Generated voice lines (any TTS or AI voice tool): Possible for the 4 voice packs (24 clips); needs nate's OK and a licence check for commercial use. Not used yet.
- Particle and juice libraries on GitHub (ForeverHD's Zone and similar; Roblox "Spring" modules, MIT): Skipped. JuiceFx is a few tweens; a library adds weight without new feel.

## M12 Test and launch prep
- Roblox AnalyticsService (built in: LogCustomEvent, LogFunnelStepEvent, LogOnboardingFunnelStepEvent): Used. Free, shows in the Creator Dashboard, hashes user ids; no outside analytics service is needed (same as Ragdoll Rides). Pattern ported from Ragdoll Rides.
- Third-party analytics (GameAnalytics Roblox SDK, MIT; PlayFab): Skipped for launch. The Dashboard covers the spec's funnels and KPIs; GameAnalytics adds cohorts and A/B tests and could come later, but it sends player data to an outside service, which needs nate's OK and a privacy review.
- Roblox experience icon and thumbnail A/B testing (Creator Dashboard, built in): Recommended for the 3 icon variants once art exists (verify it is available for the experience).
- Image generation for the icon, thumbnails and concept art (any tool nate picks): Needed; check the tool's licence allows commercial use and note it here. Not used yet.
- Store art (2026-11-17): the icon and thumbnail candidates are rendered with our Blender pipeline (above) and finished with PIL, no image generator, so nothing to licence. Caption font: Inter Black Italic (SIL Open Font License 1.1, free for commercial use; the system copy, not shipped in the game).
- Playtest tools (Roblox private servers, Studio Team Test, the Creator Dashboard Error report): Used by the Playtest Kit; all built in and free.
- Roblox's default blocky R15 body (pt-fit, 2026-11-19): its part sizes, centres and attachments were taken as numbers into Config.RobloxRig, cross-checked with a public R15 rig dump on GitHub (fleasion R15RIG.rbxmx; only the numbers, no file shipped). Its 15 meshes are fetched from Roblox by art/fit/robloxbody.py into build/ for the fit previews only, never shipped or committed.
- DracoPy (Apache-2.0, pip) and SciPy (BSD-3-Clause, pip) (fix-weapons, 2026-11-19): decode Roblox's mesh files (v7 COREMESH is Draco) and test surface contact for art/upload/meshcheck.py and art/weapons/simcheck.py; dev tools only, nothing shipped.
