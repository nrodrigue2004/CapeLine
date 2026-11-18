# Store Page: icon, thumbnails, description (M12)

Briefs for the experience icon, the 3 thumbnails and the store text. The spec's asset list says marketing is "concept art, 3 icon variants, 3 thumbnails: generated, hand-edited". Nothing here is made or uploaded without nate's OK. Everything must be original: no real hero, no anime character, no famous emblem, colour-and-symbol combo or pose that copies one.

## Rules for every image
- Our characters only: a player-made hero and villain in creator pieces, the Spark Drone, Brute and Turret robots, Rustjaw Prime, the Lumen Maw, the Null War-Frame, Old Beacon, the Velvet Paw, Gizmo.
- Robots only as enemies, sparks not blood. Cartoon, bright, readable at 150 px on a phone.
- Show both looks the game sells: one Comic hero (bold outline, primary colours, a cape) and one Anime hero (sharp hair, glowing aura, speed lines). nate asked for both audiences.
- Text on images: at most 3 words, big, and never a claim Roblox would reject ("best", "free Robux", fake update badges).
- Generate, then hand-clean in one style; check the generator's licence allows commercial use (note it in Tools.md).

## Icon (512 x 512), 3 variants to A/B test
1. **Hero in flight**: a Comic hero flying at the camera, fist forward, cape snapping, a burst of blue Volt lightning behind, Brightharbor towers small below. Strong silhouette, no text.
2. **Hero vs villain clash**: an Anime hero (white hair, gold aura) and a Syndicate villain (purple, horned mask) meeting fists in the centre, a white shockwave ring between them. No text.
3. **Boss hook**: a hero tiny against the huge Rustjaw Prime robot head filling the frame, red eye glow, sparks. Word "CAPELINE" at the bottom only if it stays readable at small size.
Test with Roblox's experience icon A/B tool if it is available (verify), 1 week each, keep the best click-through.

## Thumbnails (1920 x 1080), 3
1. **Fly the city**: a hero banking between towers at sunset, speed lines, a building collapsing in the background with dust and chunks. Caption: "FLY. FIGHT. SAVE."
2. **Build your hero**: the creator line-up: 4 heroes side by side (Bruiser, Blaster, Speedster, Controller), two Comic and two Anime, Volt, Frost, Titan, Pulse and Blade effects. Caption: "HERO OR VILLAIN?"
3. **World boss**: 10+ players flying around the Lumen Maw over the Docks, the boss bar at the top, fireworks. Caption: "20-MINUTE WORLD BOSS" (check the number matches Config.Boss before upload).
Optional 4th once a video is made: a 30 s trailer clip (Roblox allows video thumbnails; verify the rules).

## Concept art (3, for the group page and update posts)
Old Beacon on the Beacon Tower roof at dusk; the Velvet Paw on a crane at the Docks; Sovereign Null's War-Frame in its arena.

## Title and description
- Title: **Capeline** (add a short tag only for an update: "Capeline [WORLD BOSS]"; no all-caps spam).
- Description (draft, under 1,000 characters):
  > Make your own hero or villain and take to the skies over Brightharbor. Leap, glide and fly across a city you can smash, then save it (or rule it).
  > - Build your look: comic-book capes or anime auras, mix both.
  > - 4 classes and 5 power sets: Volt, Frost, Titan, Pulse and Blade, with an Awakening super mode.
  > - Rescue citizens, stop robot attacks and take contracts.
  > - Every 20 to 30 minutes a giant robot boss lands and the whole server fights it together.
  > - PvP is opt-in from level 10.
  > Looks are cosmetic: nothing sold changes your stats.
- Genre: Action (verify the current genre list), Fighting/RPG tags if offered.
- Age: the content questionnaire answers decide it (expected Moderate, 9+). Do not market to under 9s.

## Before upload
- [ ] nate picks the art tool and approves each image.
- [ ] The leaked-name and look check (Playtest Kit #42) passes for every image.
- [ ] The numbers in captions match the live config.

## Store art refresh (2026-11-18, overnight queue item 13)
New icon variants and ad thumbnails with the newer villains and bosses, made the same way as the 2026-11-17 picks (the game's own Blender meshes posed for a poster, ink outlines on the figures, the effects library's cards, then the same grade, speed lines and caption style). Files: `art/export/store2/` (upload sizes), renders before the finish in `art/export/store2/raw/`, previews `art/export/store2/preview_sheet.png` (each icon at 400, 150 and 50 px) and `preview_small.png` (each thumbnail at 480 and 240 px wide). Rebuild with `bash art/store/make2.sh` (one image: `bash art/store/make2.sh icon_maw`; `--draft` for a quick half-size pass). Nothing was uploaded.

Icons (512 x 512, no text): three hooks for the icon A/B test (target CTR 2.5% or better, Paid Ads Playbook).
- `icon_maw.png` (recommended first): the Anime hero (white spikes, gold aura, red jacket) punching a gold blast into the Lumen Maw's glowing jaws at night. A hero in action (nate's icon rule), one focal point, gold against cyan and navy, reads at 50 px.
- `icon_fake.png`: the twist up close: the Comic hero's red fist landing on Radiant's face, cracked half open to the metal plate and a red eye. The strongest small-size read (one face, one red dot); test it against icon_maw.
- `icon_titan.png`: the boss hook (icon brief 3): the Comic hero rising at the camera, Volt crackling round his fist, in front of Rustjaw Prime nearly in silhouette against a red sunset, its eyes burning red. Busier at 50 px; the third arm of the test.

Thumbnails (1920 x 1080, 3 words each):
- `thumb_maw.png`, "GIANT WORLD BOSSES": the Comic hero's Volt lightning into the Lumen Maw's jaws over the Old Quarry (its arena) at night, a squad diving in, the boss bar. For the boss arm of the ad test (with or instead of thumb_boss).
- `thumb_deep.png`, "FROM THE DEEP": the Leviathan Engine rearing out of the sea at the Trench (its arena, at the water's surface), spray and foam, the hero's lightning on its head, the boss bar. Sells the sea and the underwater side.
- `thumb_fakes.png`, "SPOT THE FAKE": the famous fakes posing as heroes on a Downtown roof at sunset, Radiant in front with its face cracked to the plate and a red eye, Bulwark and Skylance behind. The fake-hero twist arm (with or instead of thumb_twist).
- `thumb_giant.png`, "TOPPLE THE GIANT": Wind-Up Lane's finale in the Suburbs: the Wind-Up Giant stomping down the street (its 10-stud body), the hero punching in, the Bramblebeast and the Voidhound (the other finale creatures) behind. Sells the side quests.

Before upload (adds to the list above):
- [ ] The finale creatures (art/export/finales/*.fbx) and the world bosses (art/export/Bosses.fbx) are imported and showing in the game, so the images only show what players will see; re-render after any change to those looks (`bash art/store/make2.sh`).
- [ ] Bulwark's and Skylance's store looks are close stand-ins for their creator pieces (Plated Suit, Great Pauldrons, Wind Scarf, High Ponytail) drawn on the blocky body; compare them with the game once and say if anything should change.
- [ ] Pick 2 or 3 per test; the old picks (art/export/store) stay valid.
