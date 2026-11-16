# Decisions

One line each, newest at the bottom. Spec = "Capeline build spec".

- 2026-11-13 (nate, in the spec): 22 weeks with no cuts; PvP toggle at level 10 plus the Comet Crater forced zone; accept a Moderate rating; no typed hero names (title and noun wheels); level cap 40.
- 2026-11-16 (nate): start Capeline now; other new games paused. Build milestone after milestone without pausing for Studio checks.
- 2026-11-16 (nate): Capeline is superhero AND anime. Added at launch: (1) a per-hero Comic or Anime effect style plus anime creator pieces (hair, coats, scarves, wraps, glowing eyes), looks only; (2) Awakening, a meter-filled 15 s power-up for every hero (aura, glow, stronger super); (3) a fifth power set, Blade (energy sword dashes, combo strings, a slash-wave super). About +3 weeks: Phase 1 about 25 weeks. All original, nothing copied from real shows.
- 2026-11-16: the spec's "reuse Hive Hold enemy AI and boss framework" can't happen (Hive Hold isn't built); enemies and bosses are written fresh (EnemySim) in Mossbell Stand's plain-data style.
- 2026-11-16: added an Enemy.Delta remote (10 Hz, unreliable, 10 bytes per enemy, only enemies within 450 studs). The spec's remote list had no enemy replication line.
- 2026-11-16: out-of-combat regen 4% of max health per second after 6 s without damage (Config.Stats.regen). The spec has no PvE healing outside abilities, which would leave solo heroes slowly bleeding out between incidents. (tune)
- 2026-11-16: leaps use their own gravity (airGravity 120) so the spec's apex 40 and range 80 give a floaty 1.6 s arc; Roblox's 196 felt like a hop.
- 2026-11-16: speed check uses a travel budget (cap x 1.15 per second, banking 0.5 s) instead of judging each 0.1 s sample alone, so network bursts never trip it. A fail only pulls the hero back; only teleport-sized jumps count as strikes (3 in 10 minutes kicks, no bans).
- 2026-11-16: Zap Bolt and the other basics keep a 0.5 s fire interval (2 per second) though the spec lists cooldown 0; "0" means no skill cooldown.
- 2026-11-16: M1 slice unlocks Flight for everyone (Config.Dev.unlockAllStyles) so the move-and-fight test needs no levels. Turned off in M3 when levels save (spec: Flight at level 3).
- 2026-11-16: M1 default hero is a level 1 Blaster with Volt (basic + Chain Lightning + Dash Strike) until the creator (M9).
- 2026-11-16: world origin is the map centre: map -2,400 to 2,400, hub -800 to 800, Downtown x -750 to -50, z -350 to 350. The Downtown greybox has a fixed seed (the hub is handcrafted in the spec and never changes with the weekly seed).
