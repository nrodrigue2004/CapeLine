# Launch Checklist (nate, before going public)

- [ ] Create the GitHub repo nrodrigue2004/Capeline and add it to the project (then the build pushes there).
- [ ] Publish the place from Studio; fill Config.Places ids (Phase 3 planets later).
- [ ] Run the Roblox content maturity questionnaire on the first playable build (spec: end of M4) and answer honestly; expect Moderate.
- [x] Config.Dev.unlockAllStyles and freeRankCredits are off (M3). Double-check before publishing.
- [ ] Turn on Game Settings > Security > Enable Studio Access to API Services for testing saves; DataStores need a published place.
- [ ] Review the loot odds shown in GEAR > LOOT INFO against the live config before launch (players see them).
- [ ] Review every emblem, costume and anime piece against a list of famous hero and anime symbols and looks (spec: IP).
- [ ] Replace all PLACEHOLDER ART listed in Tasks.md.
- [ ] Effects textures (2026-11-17): upload the 19 PNGs in art/export/fx (10 from the library, 9 path shapes added for the 17 paths' looks) (Studio Asset Manager, bulk import; preview art/preview/fx.png) and put each id in Config.Fx.lib.textures `id` (the *_4x4 sheets are flipbooks, already set up). Until then the effects use Roblox's built-in particle images.
- [x] Path sounds (2026-11-17; done 2026-11-19, sounds pass: CC0 + our synth, uploaded): 68 licence-checked sounds for Config.Audio.paths, 4 per power path (cast, super, hit, charge) for all 17 paths; until then each plays a built-in Roblox clip pitched per path (PLACEHOLDER SOUND).
- [x] Sound ids and music (M11), checked for licenses (done 2026-11-19, sounds pass: Config.AudioClips; voice lines still open below) (now including destruction: crumble, collapse rumble, glass, car flip, drone hum, citizen gasps; and M6: boss siren, boss landing, stomps, lasers, incident clear jingle, event fanfare, camera snap; and M7: the cinematic music sting, the mentor voice lines for Old Beacon and the Velvet Paw, tram creak and cheers, the choice whoosh, mission fade, War-Frame shield break and laser charge, NPC talk blips).
- [ ] Robux products and passes created on the dashboard, ids in config (M9): 6 packs, the starter pack, hero slots 4 to 10 (slot4 ... slot10, 99 Robux each, 2026-11-21; no weapon products any more), 10 tints, 8 emotes, 4 landing poses (Config.Shop.products) and the Quick Swap and 2x passes (Config.Shop.passes). Prices are nate's call; the starter pack is set up for an A/B test at 49, 79 or 99.
- [ ] H8: create the Hero Pass season 1 developer product (499 Robux) and the 10 travel style products (99 to 199 Robux) and put their ids in Config.Shop.products (heroPass, travel3 ... travel28; all 0 now); set Config.Pass.startWeek to the launch Monday.
- [ ] M9 review every creator piece, emblem glyph, name pair and the 13 Gizmo styles against famous hero and anime looks; extend Config.Creator.blockedNames if a Title + Noun pair matches a known character.
- [ ] M9 voice pack sounds (4 packs x 6 clips) with a licence for commercial use.
- [ ] M9 re-check Roblox's paid random item and DevEx rules: packs are fixed (no random items), nothing sold changes stats.
- [ ] M10 device matrix: low-end phone, mid-range phone, tablet, PC and a controller each finish the opening, a contract and a boss (Studio list M10 16), and the text at 160% fits every screen.
- [ ] M10 check the radar, map and PvP rings with Studio's colorblind simulation (shapes must read without colour).
- [ ] M10 Roblox's current accessibility and photosensitivity guidance: Reduce flashing is in Settings; confirm nothing flashes faster than 3 times a second with it on.
- [x] M11 sound ids (done 2026-11-19 for the sounds and the 4 music tracks; the 24 voice clips are still open): put a licence-checked Creator Store id in `asset` for each of the 32 rows in Config.Audio.sounds (the built-in fallbacks are placeholders), the 4 music tracks in Config.Audio.music (patrol day, patrol night, boss, victory sting) and the 24 voice clips in Config.Shop.voiceSounds; then run the M11 Studio list again.
- [ ] M11 the 8-tester, 30-minute session: no "[Capeline] idle wait" line over 5 s in the Output.
- [ ] M12 icon (3 variants), 3 thumbnails, concept art and the description from notes/Store Page.md; pick the image tool and check its licence allows commercial use.
- [ ] M12 store art picks (nate, 2026-11-17; rendered with our own Blender pipeline, no generator): icons icon_clash and icon_smash, thumbnails thumb_build, thumb_boss and thumb_twist (art/export/store, sheet art/preview/store_picks.png; Tasks.md "Store art picks"); re-render thumb_boss and thumb_twist with the final boss and fake art, run check #42 on each, then upload them yourself.
- [ ] M12 the playtest week (notes/Playtest Kit.md): 20 testers, private place, no crash report in one week; write each session in notes/Build Log.md.
- [ ] M12 Creator Dashboard: confirm the custom events and the 5 funnels show (Onboarding, Combat, PvP, Story, Purchase) a day after the first testers.
- [ ] M12 verify Roblox's current AnalyticsService limits (custom event names, events per server per minute, custom field values) against Config.Analytics.budget and the 34 event names in Shared.AnalyticsSchema.
- [x] M12 balance call: nate kept the current pacing (Credits x1.4, Renown x0.35) until soft launch data (Decisions 2026-11-16).
- [ ] M12 soft launch (notes/Soft Launch Plan.md): quiet public launch first, no ad spend without a budget nate approves; the kill-or-scale decision at 8 weeks live.
- [ ] Private server price.
- [ ] Re-check Roblox rules (PvP, free-form creation, rewarded video ads) before launch.
- [ ] M8 sounds (2026-11-19 sounds pass recorded the Downed heartbeat, revive chime and PvP flag horn; the rest still use shared rows): Downed heartbeat, revive chime, PvP flag horn, overload spark crackle, Crater warning alarm, ping blips (licences checked).
- [ ] M8 moderation: read the review queue (DataStore CapelineReview_v1: kicks, reports, PvP trades) by hand now and then; there is no automatic ban. Confirm the in-game Report (preset reasons) plus Roblox's own Report Abuse meet the current Roblox community rules, and that quick-mute through TextChatService is still allowed.
- [ ] M8 re-check the PvP rules against Roblox's current policy (opt-in PvP, no forced PvP below level 10, the Moderate rating) before launch.
- [ ] Voice lines for the two mentors (M7 opening) are recorded or generated with a licence that allows commercial use; no real actor likeness.

## Marketing: paid ads (nate's rule, 2026-11-17)
Every paid push follows the shared playbook in project files `marketing/Paid Ads Playbook.md`. No Robux spent without nate's OK on that campaign.
- [ ] Only after the quiet launch: organic Day-1 return at least 15% and no known crash in the opening.
- [ ] Make 2 to 3 ad thumbnails (16:9) as well as the icon; submit them 3 days before the start (moderation takes up to 48 hours).
- [ ] Split the budget over 5 to 7 days as a daily budget (example: 10,000 Robux = about 1,400 to 2,000 a day). Objective Plays, audience All Players, no extra targeting at first.
- [ ] Day 1: CTR per thumbnail in Ads Manager (aim for 2.5% or more). Day 2: turn off the weakest thumbnail, and read day 1's FunnelKit data.
- [ ] Pause the campaign if more than 35% of first sessions end in under 1 minute (`first_session_end`, length "under 1m"), or under half of new players reach Opening done (Progress funnel; also the Opening funnel). Fix that step, then run ads again.
- [ ] Log each campaign in the playbook's campaign log.

## Group and creator codes (WP10, 2026-11-18)
Both ship off. Set them in `src/config/Promo.luau`, then run Tasks.md "WP10: group-join piece and creator codes".
- [ ] Make the Capeline community group (original name and emblem, no famous hero or anime look), put its id in Config.Promo.group.id (0 = off) and its name in Config.Promo.group.name (PLACEHOLDER NAME "the Capeline group" now). Link the group on the game page so players can find it.
- [ ] OK the group reward: the Spark Badge (an earnable drop emblem, never sold, looks only), or pick another "drop" piece in Config.Promo.group.piece.
- [ ] Creator codes: for each creator, append a row to Config.Promo.codes (code 3 to 12 of A-Z and 0-9, a "drop" piece, optional starts and ends as YYYY-MM-DD UTC, a short tag for analytics). Never reuse an old code for a new reward: a claimed code stays used on every save.
- [ ] Re-check Roblox's current rules for group-join rewards and promo codes (free cosmetics only, no Robux or paid items, nothing that needs leaving Roblox) before turning them on.
- [ ] Add promo_claim to the custom events checked against Roblox's AnalyticsService limits (Shared.AnalyticsSchema).
## Live tuning (Balance_v, WP8, 2026-11-18)
- [ ] To change a tuned number without a new build: open the DataStore named Balance_v<N> (N is Config.Version.balance, 1 now) with a DataStore editor plugin or the Creator Dashboard's Data Stores page, and write the key "live" as JSON shaped like Config, for example `{"_rev": 1, "_note": "softer first weeks", "Economy": {"scale": {"credits": 1.5}}, "Boss": {"hp": {"base": 50000}}, "Enemies.BruteBot.hp": 500}`. Raise "_rev" each edit. Only the numbers in Config.Balance.keys change, each inside its range; anything else is refused and logged. New servers pick it up at boot (running servers keep their numbers until they restart). Check the "[Balance]" line in a test server's Output, or the balance_live event in the Creator Dashboard. Delete the key to go back to the bundled numbers. When a build changes bundled numbers, bump Config.Version.balance: the store moves to Balance_v<N+1> and the old key stops applying.

## Player data requests (list-combat, 2026-11-20; Everything Left 464, 465)
Roblox sends right-to-erasure requests to the account's email/messages. For each one:
1. Open the published place in Studio (Game Settings > Security > Enable Studio Access to API Services) and play a server (or use a live server's console as the owner).
2. In the server's command bar: `require(game.ServerScriptService.Server.Services.SaveAdmin).erase(<userId>)`. It kicks that player if they are in this server, then removes their profile (CapelineProfile_v1 P_<id>), their rows on every weekly board and their review queue rows. The Output line says how many keys went, were not there or failed; run it again if any failed.
3. Reply to Roblox that the data is erased, and keep a one-line note (date, user id, result) somewhere private. Never keep the request's personal details in the repo.
If a bad build breaks saves (rollback):
1. Pull the build first (republish the last good version), so no new saves go wrong.
2. Pick the time just before the bad build went live (Unix seconds).
3. For each affected player, once they are out of the game: `require(game.ServerScriptService.Server.Services.SaveAdmin).rollback(<userId>, <unixTime>)`. It puts back their newest save from before that time (Roblox keeps 30 days of versions) and refuses while a server holds their profile.
4. Repair on load (ProfileSchema migrations) still runs on their next join.
