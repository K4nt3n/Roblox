# Giant Veggie Fair

A cozy, kid-friendly Roblox game: plant a seed, let it grow (even while you're offline) into a giant,
water your friends' gardens, and enter your heaviest veggie in the weekly weigh-in fair.

This repo is the **code prototype**. All core loops work end to end with placeholder parts and
placeholder UI. Art, models and audio are intentionally not included; the code has clean seams
where they drop in (see [Art seams](#art-seams)).

- Build order and what's next: [docs/DEV_TIMELINE.md](docs/DEV_TIMELINE.md)
- Manual test plan for Studio: [docs/TEST_PLAN.md](docs/TEST_PLAN.md)

## Run it

1. Install the toolchain with [Rokit](https://github.com/rojo-rbx/rokit): `rokit install`
   (pins Rojo, Selene and StyLua from `rokit.toml`).
2. Install the Rojo plugin in Studio, then from the repo root run `rojo serve`.
3. Open a place in Studio, click **Connect** in the Rojo plugin, and press **Play**.
4. For saving to work in Studio: *Game Settings → Security → Enable Studio Access to API Services*.
   Without it the game still runs on an in-memory store and warns in the output.

To build a place file instead: `rojo build -o GiantVeggieFair.rbxlx`.

### Unit tests

The pure logic (growth, economy, fair, formatting, save schema) has no Roblox dependencies and runs
under the standalone [Luau CLI](https://github.com/luau-lang/luau/releases):

```
luau tests/run.luau
```

## Core loops

| Loop | How it works | Code |
|---|---|---|
| Plant | Walk to an empty plot, press **E**. Uses the seed picked in the bottom bar. Carrots are always free so nobody gets stuck. | `GardenService:Plant` |
| Grow | A plant stores `plantedAt`, a speed and bonus seconds. Its stage and weight are computed from the clock, so growth continues offline with no ticking. | `shared/GrowthMath` |
| Water | **E** on a growing crop (or **R** on a ripe one). Skips a slice of grow time and adds a little permanent weight. Per-plant cooldown. | `GrowthMath.applyWater` |
| Friends water | Anyone in the server (or only Roblox friends, via `Config.Watering.requireFriendship`) can water your crops. They get a coin tip, you get the boost and a notification. Daily cap per garden. | `GardenService:Water` |
| Harvest | Ripe crops can be harvested, or left to swell toward Giant size. Giant-gene seeds (rolled at planting) get extra size. | `GardenService:Harvest` |
| Sell | Basket panel: sell one or sell all. Price = weight x price/kg x Market Stall upgrade x Giant bonus. | `EconomyService` |
| Upgrade | Watering Can, Fertilizer, Green Thumb, Market Stall, plus extra plots. | `Config.Upgrades`, `EconomyService` |
| Fairs | Three fairs run side by side: **Hourly**, **Daily** and the **Weekly Grand Fair**. "Enter Fair" in the Basket asks which one. One entry per fair per period; a heavier one replaces it and the old one returns. Bigger fairs judge more divisions and pay more (`Config.Fair.periods`). | `FairService`, `shared/FairMath` |
| Live shows | When a fair rolls over, every server runs a weigh-in show: countdown banner, camera to the stage, each local entry weighed lightest to heaviest, podium prizes for this server, then the global top 3. Nobody entered? A short fallback card. Missed it? Results arrive as a replay card on your next join. Daily and weekly shows take the camera; the hourly one is an overlay with a "Watch the stage" button. | `FairDayService`, `FairDayController` |
| Ribbons for everyone | Each veggie type has its own board, plus First-Timer, Most Improved, Natural Grown, Team Grown, Helpful Neighbor and the live-show podium. Ribbon ids look like `weekly:Blue:crop_pumpkin`. The Ribbons panel lists them. | `FairMath.divisionsForEntry`, `RibbonPanel` |
| Champion | A big plot in front of your garden for the one veggie you raise all week. It grows bigger and for longer, and care needs (water, bugs, prop it up) pop up on a schedule. Handling them adds weight, so care beats the Giant gene. Name it (text filtered). **F** to care. | `ChampionService`, `shared/CareMath` |
| Grow together | Invite up to two friends to co-grow your champion. They can water and care for it, are listed on its fair card, and get half its prize plus a team ribbon by mail, even if offline. | `ChampionService`, `MailService` |
| XP essence | Harvesting, caring and watering a friend's garden send glowing orbs from the crop into the XP bar. The bar fills a step per orb and rolls over on level-up. | `Feel/EssenceFX`, `UI/LevelBar` |
| Skip wait | Developer product stub. In Studio the Skip button simulates a purchase; set real ids in `Config.Monetization`. Receipts are idempotent. **Honest shop:** a champion can be skipped once per week, a skipped champion leaves Natural Grown, and the shop says so. | `MonetizationService` |
| Welcome back | On join you get a summary of what ripened while you were away. | `GardenService:_sendWelcomeBack` |

## Architecture

```
src/
  shared/            ReplicatedStorage.Shared (pure modules, no Roblox services)
    Config.luau        every tunable
    GrowthMath.luau    plant/grow/water/skip math (timestamp based)
    EconomyMath.luau   prices, upgrades, XP
    FairMath.luau      fair periods, divisions, show phases, ribbon ids, tiers
    CareMath.luau      champion care schedule and credit
    Format.luau        coins / kg / durations
    Net.luau           remote, action and feedback names
    Signal.luau        tiny event class
  server/            ServerScriptService.Server
    init.server.luau   loads services: Init all, then Start all (DataService last)
    Data/Schema.luau   save shape, defaults, reconcile, migrations
    Services/
      NetService         remotes, routing, rate limits, state snapshots, feedback events
      DataService        DataStore load/save, session lock, retries, autosave, memory fallback
      PlotService        garden slots, placeholder plots and stands, prompt routing, plot attributes
      GardenService      plant / water / harvest / skip, stage-change events, welcome back
      EconomyService     coins, XP, seed shop, upgrades, plots, selling
      ChampionService    champion setup, care needs, naming, co-grow invites
      MailService        coins and ribbons for players who are offline or elsewhere
      FairService        hourly/daily/weekly entries, a board per division, rewards
      FairDayService     the live weigh-in show state machine
      MonetizationService  dev products, receipts, champion skip cap, pass checks
  client/            StarterPlayerScripts.Client
    init.client.luau   starts Feel -> Garden -> UI, then listens for state
    ClientState.luau   latest snapshot + signals, server-synced clock
    NetClient.luau     request wrapper
    Feel/              game-feel layer (see below)
    Controllers/       GardenController (crop visuals, prompts, champion care), CropVisuals (art seam),
                       FairDayController (live show: banner, camera, weigh-in, podium)
    UI/                Theme, Scale, ArtSlot, UIKit, Counter, Toasts (building blocks),
                       Hud, UIController (panels + event routing), LevelBar, Modal,
                       ShopPanel, BasketPanel, FairPanel, ChampionPanel, RibbonPanel
tests/               pure-logic specs for the Luau CLI
```

**Server authoritative.** The client only says "I pressed the prompt on plot 3" or "sell item 12".
The server checks ownership, seeds, coins, cooldowns and limits. Weights, prices and times are
never sent by the client.

**State flow.** Services mutate the profile and call `DataService:MarkDirty(player)`. That pushes one
coalesced snapshot per frame to the client, with server-computed extras (prices, upgrade costs).
UI re-renders from the snapshot. Game moments are sent separately as feedback events.

**Smooth growth with no network cost.** The server writes each plant's inputs onto its plot part as
attributes. Every client runs the same `GrowthMath` each frame using `workspace:GetServerTimeNow()`
and spring-smooths the visual size, so crops swell continuously and bounce on each stage change.

### The feel layer

Peter's rule for this project: stiff or robotic games lose players, fluid ones keep them. So feel is a
system, not an afterthought.

- `Feel/Tweens.luau` holds the shared motion presets (pop, slide, fade, bounce, count-up,
  camera punch) and a `reducedMotion` switch. Everything that moves should use these.
- `Feel/FeelController.luau` turns every server feedback event (`Harvested`, `FriendWateredYou`,
  `LevelUp`, ...) and client events (`ButtonPress`, `PanelOpen`) into feel: code presets first,
  then any sound, animation or particle hook, then a `Played` signal the UI listens to.
- `Feel/FeelHooks.luau` is the drop-in table for audio, animation and particle ids. Empty means
  silent; fill an id and it plays, no code change. Show and champion moments have hooks too
  (`FairDrumroll`, `FairWeighIn`, `FairConfetti`, `CareNeeded`, `EssenceTick`, ...).
- `Feel/EssenceFX.luau` flies XP orbs from a world point into a UI target. `UI/LevelBar.luau` holds
  the bar's target while orbs are in the air, so XP never snaps. The same effect flies coins from the
  Sell button into the coin counter (tagged streams, so coins never hold up the XP bar).

### The UI layer

All UI is built in code, in design pixels at a 1280x720 reference.

- `UI/Theme.luau`: colors, panel accents, spacing, text sizes, touch sizes, ScreenGui layers and the
  art slot table. Restyle the game here.
- The look is all code and tuned in `Theme.Style`. It mixes Peter's two references: clean white panels with
  near-black edges and a colored title bar, and "studded" colored buttons with flat saturated faces, a darker
  lip along the bottom (`Theme.gradient`, `Style.Lip`), a subtle square-stud texture (`UI/Studs.luau`,
  `Style.Studs` / `StudSize` / `StudTransparency`), thick dark outlines and white text with a heavy dark
  stroke. A shine sweeps across key buttons (`UIKit.keyButton` / `UIKit.sweep`), HUD pills and seed slots get
  soft drop shadows, and rewards get white/gold flashes with bouncy pops (`Tweens.flash`, `Hud.celebrate`).
  The gloss strip from the first pass is still there, off (`Style.Gloss`).
- Studs: the tile is drawn in code with an EditableImage. If Peter uploads his own tile (one stud, seamless),
  set `Theme.Art.StudTile` and it is used instead. If neither is available the faces just stay flat.
- HUD fair timers: under the level pill, one row per fair with an icon slot (`Timer_<fairId>`) and
  "In 15m 57s". The last minute turns gold; tapping a row opens that fair's tab.
- `UI/Scale.luau`: one responsive scale. `Scale.root(screenGui)` returns a scaled full-screen frame; phones,
  tablets and big monitors all get sensible sizes, and `Scale.device` drives layout changes (smaller menu
  and seed slots on phones, hotbar kept clear of the thumbstick and jump button).
  `Scale.setUserMultiplier` is the hook for a UI size setting.
- `UI/UIKit.luau`: buttons (hover lift, press squash, release spring, gamepad selection ring),
  disabled buttons that shake and say why when tapped, `requestButton` (busy while the server answers,
  pop on success, shake on a denial), sliding tabs, badges, panels, rows.
- `UI/Counter.luau`: numbers roll instead of snapping, bigger jumps roll longer, and gains float a "+250".
- `UI/Toasts.luau`: priority queue (max 3 on screen, 2 on phones), repeats stack as "x3", leaving toasts
  shrink their slot so the rest glide up.
- `UI/Hud.luau`: coin pill, level pill, menu with badges (basket count, champion needs care, a fair waiting
  for an entry, new ribbons), seed hotbar updated in place. `Hud.target(name)` / `UIController.target(name)`
  give fly-to targets for effects (the harvest sequence in G4 can fly crops into `"Market"`).
- `UI/UIController.luau`: one panel at a time over a dimmed, blurred backdrop. Tap outside, X or gamepad B
  closes; opening another panel cross-fades; rows pop in one after another; re-renders keep the scroll
  position. `UIController.registerPanel(name, spec)` adds new panels (settings, store, streak) with the
  same feel.

## Art seams

| What | Where to drop it | Fallback today |
|---|---|---|
| Crop models | `ReplicatedStorage.Assets.Crops.<cropId>` (Model). Optional stage child models `Seed`, `Sprout`, `Growing`, `Ripe`, `Giant`. Set a `BaseDiameter` attribute for scaling. | Colored ball |
| Particles | `ReplicatedStorage.Assets.Particles.<name>` (ParticleEmitter), named in `FeelHooks.Particles` | None |
| Sounds / animations | Asset ids in `FeelHooks.Sounds` / `FeelHooks.Animations` | Silent |
| Garden positions | `Workspace.GardenSlots.<1..8>` parts | Generated grid |
| Shop / market / fair stands | `Workspace.Stands.<SeedShop/Market/FairStand>` parts | Placeholder blocks |
| Map | Any `Workspace.Map` or `Workspace.Baseplate` | Generated ground |
| Fair stage | `Workspace.FairStage` with parts `Floor`, `Scale` and `CameraPoint` (the camera looks along it) | Generated stage |
| Essence orbs | Set `EssenceFX.template` to a GuiObject (e.g. a sparkle ImageLabel) | Glowing round frames |
| UI icons | Asset ids in `Theme.Art`: `CoinIcon`, `LevelIcon`, `Menu<Shop/Market/Fair/Champion/Ribbons>`, `PanelIcon_<panel>` (empty reuses `Menu<panel>`), `ChampionPortrait`, `Timer_<fairId>`, plus `Seed_<cropId>`, `Upgrade_<id>`, `Ribbon_<color>`, `Medal_<1-3>` | Flat colored shapes with a letter |
| Stud texture | `Theme.Art.StudTile` (one seamless stud, tiled) | Stud tile drawn in code |
| UI frames | `Theme.Art.PanelFrame` / `ButtonFace` (9-slice, set `Theme.ArtSlice`) | Flat rounded frames |
| UI look | `UI/Theme.luau` tokens and `UI/UIKit.luau` builders | Rounded placeholder UI |

Every art slot instance is named `Art_<slot>` with an `ArtSlot` attribute, so it is easy to find in
the Explorer. Set `ArtSlot.showLabels = true` to print slot names on the placeholders in Studio.

## Tuning

Everything is in `src/shared/Config.luau`: crop grow times, weights and prices, watering boost and
cooldowns, upgrade curves, plot costs, XP curve, fair tiers, rate limits. Unit tests check that the
tables stay consistent (for example each upgrade has one more value than costs).

## Known gaps (tracked in the timeline)

- Game passes in `Config.Monetization.Passes` have no ids yet (`passId = 0`), so ownership checks return false.
- The hourly show runs in every server every hour; tune or turn it into banner-only after playtests (R9).

- Purchases are granted before the profile is force-saved (timeline M1).
- No tutorial, daily streak, or settings menu yet.
- Fertilizer speed is locked in when a seed is planted, so buying it speeds up the next planting.
- The UI rebuilds an open panel's rows on every snapshot (scroll position is kept). Rows are rebuilt in
  the same frame so nothing jumps, but a button you are hovering loses its hover lift; keyed rows would fix it.
