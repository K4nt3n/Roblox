# Developer timeline

Prioritized build order for Giant Veggie Fair. Every task's prerequisites appear above it,
so work top to bottom. Art, models and visual assets are intentionally left out; code leaves
drop-in seams for them (see README, "Art seams").

Status: **built** = done in the prototype, **todo** = not started.

## Foundation

_A repo and place that every later task builds on._

| # | ID | Task | Needs | Status |
|---|---|---|---|---|
| 1 | F1 | **Rojo project, toolchain pins and test runner**<br>default.project.json, rokit.toml, tests/run.luau. Everything else lives in this layout. | - | built |
| 2 | F2 | **Studio place setup**<br>Publish the place, enable Studio Access to API Services so DataStores work, set max players to 8 to match garden slots. | F1 | todo |
| 3 | F3 | **Config module for every tunable**<br>All times, prices, upgrade curves and fair tiers in src/shared/Config.luau. | F1 | built |
| 4 | F4 | **Shared pure logic (growth, economy, fair, format)**<br>Timestamp-based growth math used by both server and client. Covered by unit tests. | F3 | built |
| 5 | F5 | **Networking layer with validation and rate limits**<br>One Request remote, per-action rate limiting, friendly Denied reasons. | F1 | built |
| 6 | F6 | **Player data: session lock, retries, migrations, autosave**<br>DataService plus Schema. Falls back to memory when DataStores are off. | F3, F5 | built |
| 7 | F7 | **CI: run unit tests on every push**<br>GitHub Action that runs luau tests/run.luau and selene. Catches broken math before it reaches Studio. | F4 | todo |

## Core loop

_Plant, grow, water, harvest, sell, upgrade, enter the fair._

| # | ID | Task | Needs | Status |
|---|---|---|---|---|
| 8 | C1 | **Garden slots and plots per player**<br>PlotService builds placeholder gardens and prompts. Map can override positions with GardenSlots parts. | F6 | built |
| 9 | C2 | **Plant, grow (offline too), water, harvest**<br>GardenService. Growth continues while players are away because it only depends on timestamps. | C1, F4 | built |
| 10 | C3 | **Friend watering with tips and daily limits**<br>Anyone (or only friends, via config) can water your crops. Both players get feedback. | C2 | built |
| 11 | C4 | **Seed shop, upgrades, plot purchases, selling**<br>EconomyService. Prices come from the server snapshot so the UI never duplicates rules. | C2 | built |
| 12 | C5 | **Weekly weigh-in fair with rewards**<br>FairService. OrderedDataStore per week, live top 10, rewards claimed on next join. | C4 | built |
| 13 | C6 | **Skip-the-wait developer product (stub)**<br>Receipt handling is idempotent. Simulated purchase works in Studio until real ids exist. | C2 | built |
| 14 | C7 | **First Studio playtest and bug pass**<br>Run the full loop in a 2-player local server test. Fix anything that breaks. | F2, C1, C2, C3, C4, C5, C6 | todo |

## Tuning and data

_Know the loop is fun before polishing it._

| # | ID | Task | Needs | Status |
|---|---|---|---|---|
| 15 | T1 | **Analytics funnel events**<br>AnalyticsService custom events: join, first plant, first harvest, first sell, first upgrade, fair entry. Needed to judge every later change. | C7 | todo |
| 16 | T2 | **Economy simulator script**<br>A luau script that simulates a player session by session using Config, to check time-to-first-upgrade and coin inflation. | F4, C7 | todo |
| 17 | T3 | **First-session pacing pass**<br>Targets: first harvest under 30 s, first upgrade under 5 min, first Giant inside the first session. | T1, T2 | todo |
| 18 | T4 | **Long-term pacing pass**<br>Check day 1, day 3 and day 7 progression so offline growth always gives a reason to come back. | T3 | todo |

## Game feel

_Fluid, satisfying, never stiff. This is where CCU is won._

| # | ID | Task | Needs | Status |
|---|---|---|---|---|
| 19 | G1 | **Motion tokens and tween library everywhere**<br>Every moving thing goes through Feel/Tweens with shared easing. Audit for any instant snaps. | - | built |
| 20 | G2 | **Feel event bus with sound, animation and particle hooks**<br>FeelController and FeelHooks. Filling in an id later makes it play, no code changes. | F5 | built |
| 21 | G3 | **Spring-smoothed crop growth and stage bounces**<br>Crops swell every frame on the client and boing on each stage change. | C2 | built |
| 22 | G4 | **Harvest moment sequence**<br>Crop lifts, spins, weight counter rolls up, flies to a basket UI target, camera eases. The single most repeated action, so it must feel great. | G1, G2, G3 | todo |
| 23 | G5 | **Watering interaction**<br>Equip a watering-can tool, auto-face the plot, pour timing, soil darkens, crop wiggles. Uses hooks only, art comes later. | G2, C3 | todo |
| 24 | G6 | **Custom prompt UI**<br>Replace default ProximityPrompts with a themed custom style and hold-to-harvest ring for big crops. | G1 | todo |
| 25 | G7 | **Camera and transitions**<br>Smooth intro flyover of your garden on join, panel open blur, eased camera when the fair opens. | G1 | todo |
| 26 | G8 | **UI polish pass**<br>Notification priority queue, number roll-ups everywhere, consistent button states, no layout jumps on re-render. | G1, T3 | todo |
| 27 | G9 | **Audio plumbing**<br>SoundGroups, volume settings, ducking during big moments, pitch variation per crop size. Code only; audio files come later. | G2 | todo |
| 28 | G10 | **Settings: reduced motion, music, SFX**<br>Settings menu wired to Tweens.reducedMotion and SoundGroups. Saved in player data. | G8, G9 | todo |
| 29 | G11 | **Mobile, tablet and gamepad support**<br>Touch-size targets, UI scale, gamepad selection for every panel. Most young players are on mobile. | G8 | todo |

## Retention

_Reasons to come back tomorrow and next week._

| # | ID | Task | Needs | Status |
|---|---|---|---|---|
| 30 | R1 | **Tutorial (first-time flow)**<br>Guided plant, water, harvest, sell, enter fair. Skippable. Tracked with T1 events. | G4, T3 | todo |
| 31 | R2 | **Welcome-back sequence**<br>Short tour of what grew while away, then a harvest-all shortcut. Builds on the existing WelcomeBack event. | G4, G7 | todo |
| 32 | R3 | **Offline friend-water log**<br>Store waters received while offline and show who helped on join. Strong social pull. | C3, R2 | todo |
| 33 | R4 | **Daily streak reward**<br>Seeds and fertilizer for consecutive days. Data field plus a claim panel. | R1 | todo |
| 34 | R5 | **Live fair day event**<br>Saturday server-wide judging show with countdown, top-3 reveal and confetti hooks. | C5, G7 | todo |
| 35 | R6 | **Ribbon and trophy shelf**<br>Show earned ribbons in the garden and on the HUD so wins feel permanent. | C5 | todo |
| 36 | R7 | **Crop mutations and seed index**<br>Rare variants (golden, rainbow) rolled at planting, plus a collection book to fill. | T4 | todo |
| 37 | R8 | **Visit friends across servers**<br>Join-a-friend button and teleport to their server to water their garden. | C3, R3 | todo |

## Monetization

_Fair, kid-appropriate spending that never blocks fun._

| # | ID | Task | Needs | Status |
|---|---|---|---|---|
| 38 | M1 | **Save-before-grant receipts**<br>Force a profile save before returning PurchaseGranted so a crash can never lose a paid item. | F6, C6 | todo |
| 39 | M2 | **Real developer products**<br>Create products in the Creator Dashboard, put ids in Config, remove the Studio stub path from live. | M1 | todo |
| 40 | M3 | **Game passes**<br>Bigger watering can, extra plot row, auto-water sprinkler. Pass checks through one ownership service. | M2 | todo |
| 41 | M4 | **Robux shop panel and starter pack**<br>One clean store panel. Starter pack offer shown after the first fair entry, never during the tutorial. | M3, G8, R1 | todo |

## Hardening

_Safe, stable and fast enough to launch._

| # | ID | Task | Needs | Status |
|---|---|---|---|---|
| 42 | H1 | **Exploit audit**<br>Fuzz every Request action with bad payloads, check rate limits, confirm no client value is trusted. | C7 | todo |
| 43 | H2 | **DataStore budget and failure monitoring**<br>Log save failures and budget usage. Alert on lock conflicts. | F6, T1 | todo |
| 44 | H3 | **Performance pass**<br>Profile 8 gardens x 12 plots on low-end mobile. Throttle label updates and spring math for far gardens. Enable streaming. | G3, G11 | todo |
| 45 | H4 | **Soft shutdown for updates**<br>Teleport players to a reserved server and back on update so nobody loses a session. | F6 | todo |
| 46 | H5 | **Safety and policy checks**<br>PolicyService checks for paid items, text filtering on any player text, no paid random items. | M3 | todo |
| 47 | H6 | **Localization setup**<br>Move all player-facing strings to a localization table. Kid audience is global. | G8 | todo |

## Launch

_Ship, measure, iterate._

| # | ID | Task | Needs | Status |
|---|---|---|---|---|
| 48 | L1 | **Closed beta**<br>Small group of testers for a week. Review D1 retention and the T1 funnel. | H1, H2, H3, R1, M2 | todo |
| 49 | L2 | **Final tuning from beta data**<br>Adjust Config only where possible so changes ship without code risk. | L1 | todo |
| 50 | L3 | **Public launch**<br>Go live with the first official fair week. | L2, H4, H5 | todo |
| 51 | L4 | **Live ops cadence**<br>Weekly fair themes, new crop every two weeks, monthly event. All driven from Config. | L3 | todo |
