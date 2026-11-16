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
- 2026-11-16 (nate): enemies are humanoid robots ("robots that look like humans"): metal android bodies with glowing eyes, walking and punching. Spark Drone becomes a jet-boot flyer, Turret a planted heavy sentry android. Still machines only: defeats are sparks, bolts and parts, never blood.
- 2026-11-16: a hero's skills may come from any unlocked set (spec: "Any class can use any set"; the 52-point cap only bites when mixing sets). The primary set (hero.setId) gives the basic attack and the look.
- 2026-11-16: Blade set (abilities 33-40) numbers: Blade Slash 0.65/0.65/1.0 combo, Flash Step 1.4 dash 35, Crescent Wave 1.3 line 50, Rising Blade 1.5 knockup, Thousand Cuts 8 x 0.35 flurry, Parry Stance 1 s counter 2.0, Blade Storm 0.35 per tick r10 4 s, Heaven Splitter super 4.2 line 80 x 14. Unlocks at level 18. (tune)
- 2026-11-16: Awakening numbers: meter 100; +1.5 per basic hit, +4 per skill hit, +8 per super hit, +6 per kill, +0.5 per 1% health lost; 15 s of +20% damage, skill cooldowns 35% faster, supers +30% coeff and half cooldown. Same for every hero; nothing sold touches it. (tune)
- 2026-11-16: supers have 3 ranks: 2 = +10% coeff and the mod pick, 3 = capstone and -8% cooldown. Rank Credits cost is waived (Config.Dev.freeRankCredits) until Credits exist in M3.
- 2026-11-16: Rally Roar gives +10% Power, not "+10% Might" (Might is 0 without gear). Bruiser hits taunt the target 2 s. Loadouts change anywhere out of combat (5 s since damage) until safehouses exist in M4.
- 2026-11-16: 4 more team-up combos for the Blade set (Storm Edge, Ice Bloom, Sky Breaker, Void Cut), 10 in all.
- 2026-11-16: melee basics (Punch Combo, Blade Slash) swing every 0.5 s like the ranged basics; their combo strings average about 1.4x a ranged basic's damage for the risk of being close. A level 10 Burglar Bot falls in about 2.1 to 2.3 s to any basic (spec test: 2 to 3 s).
- 2026-11-16: Enemy.Delta grew to 12 bytes per enemy (status flags and facing for the robot bodies); 60 enemies still fit in under 900 bytes.
- 2026-11-16: M3 gear. A Common piece (no bonus stats) puts its whole budget in the main stat; the spec's 70% main share applies when there are bonus stats to take the rest.
- 2026-11-16: upgrade step cost follows the spec formula round(12 x n^1.5 x tier mult): +10 on a Common is 379 (the spec text says 380).
- 2026-11-16: supers rank for 300, 900 and 2,400 Credits (spec Sinks table), not the skill prices.
- 2026-11-16: pity counts the boss in hand: the 5th boss in a row with no Epic is an Epic, the 15th MVP roll in a row with no Legendary is a Legendary (spec test wording). Fixed story rewards (the Act 1 finale Epic) skip the level 20 Epic gate; every other Epic or Legendary above the hero's gate drops one tier lower.
- 2026-11-16: the 5th power set (Blade) gets a 5th Epic set, Edgewalker: 2 pieces Blade damage +8%, 4 pieces Parry Stance ripostes heal 5%. Ironclad's shockwave is 0.3 coeff per 0.5 s for 3 s; Orbitwear's Float heal reaches allies within 12 studs of the lifted target (Float lifts machines).
- 2026-11-16: a respec refunds the Credits its ranks cost into the bank, so trying builds stays free (spec: respec is free).
- 2026-11-16: gadget actives (Grappling Hook 30 s, Smoke Bomb 40 s, Shield Drone 45 s, Decoy 60 s) ship in M3 with the gadget slot; about 6% of drops are gadgets.
- 2026-11-16: server close waits up to 25 s for saves (Roblox allows 30); the spec's 4 s deadline would only drop slow saves. Saves also go 8 s after a level up, drop, gear change, rank or loadout change (one write per burst).
- 2026-11-16: a full stash (150) turns a new drop into Lumen Dust; its style still unlocks.
- 2026-11-16: Profile.Sync sends the full view after gear changes and a small wallet-only view after rewards and spending.
- 2026-11-16: until incidents and bosses exist (M6), nothing in play drops gear or pays Renown; the Dev panel rolls any source and adds Renown, Credits and Dust.
