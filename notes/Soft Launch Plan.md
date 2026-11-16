# Soft Launch Plan (M12)

How Capeline goes from the playtest week to public, what we watch, and when we scale it, fix it or pause it. Spec: Analytics and KPIs. Every step that publishes, spends Robux or changes the store page needs nate's OK first.

## Steps
1. **Playtest week** (Playtest Kit): 20 testers, private place, no crash report in one week. Gate to go on.
2. **Quiet public launch**: make the experience public with no ads and no sponsored placement. Friends, the Roblox group and nate's other games' players only. Run for 2 weeks to get the first real D1 and D7 numbers and fix the worst funnel step.
3. **First push**: one content update (the spec's Update 1) plus a small sponsored ad test only if nate approves a budget. Watch the KPIs below weekly.
4. **Decision at 8 weeks live**: the kill-or-scale rule at the bottom.

## Where each KPI comes from
| KPI | Target (starting guess, revise with real data) | Where to read it |
|---|---|---|
| Opening completion (first_blast within 30 s) | 85% | Onboarding funnel: session_start to first_blast; first_blast's value is seconds since join |
| Creator completion | 90% of those who open it | Onboarding funnel: creator_open to creator_done |
| Day-1 retention | 25% or more | Dashboard Retention; Onboarding funnel's d1_return step |
| Day-7 retention | 8% or more | Dashboard Retention |
| Average session | 25 min or more, with at least 1 boss | Dashboard Engagement; leave event value; first_boss_join step |
| Boss participation | 60% of sessions over 15 min | boss_join events vs sessions over 15 min (leave value) |
| Payer conversion | 1.5 to 3% of players a month | Dashboard Monetization; purchase events; Purchase funnel |
| PvP flag-on rate | 10 to 25% of sessions; alert above 40% | flag_on events / session_start |
| PvP reports per 1,000 sessions | under 5 | report_player events |
| Phone fps median | 30 or more | perf_sample (device = phone), value = median fps |
| Crash-free sessions | 99% or more | Dashboard Error report and the server script error count |
| Server fill | average over 12 of 30 players | Dashboard Servers / concurrent users |
| Capeline share of the income goal | $200 to $700 a month by month 3 | Dashboard Monetization (DevEx value) |

## Weekly routine (15 minutes)
1. Onboarding funnel: the biggest drop between two steps. That step is next week's fix.
2. D1 and D7 against the targets.
3. perf_sample by device: any device class under 30 fps median gets a lower default preset.
4. idle_wait count and reasons: a rising "no_incident" means more incidents near spawn.
5. report_player and anti_exploit_flag: read the review queue by hand (no automatic bans, ever).
6. Purchase funnel: shop_open to shop_view_item to shop_buy_prompt to shop_buy_ok. A big drop at prompt means the price or the item; at view means the shop layout.
7. Bump Config.Version.balance whenever a tuning number changes, so the numbers split by balance version.

## Kill or scale (after 8 weeks of live play, from the spec)
- **Scale** when retention is met and revenue rises toward the lower end of the goal: more content updates (every 2 to 3 weeks), a season every 4 to 6 weeks, and Phase 2.
- **One 4-week fix sprint** on a single weak number if retention is near target but revenue is under half.
- **Pause** and keep light maintenance if day-1 retention stays under 15%, or monthly revenue is under about $50 after two fix cycles.

## Event budget note
Custom events are capped per server per minute (Config.Analytics.budget: 120 + 20 per player, Roblox's throttle as we understand it; verify the live limit before launch). Skill casts log at 20% (the spec's "reduced to 20% for combat events"), and busy events (casts, perf samples, gear drops, PvP hits) stop at half the budget so funnels and rare events always get through. The Dev panel shows events sent and skipped.
