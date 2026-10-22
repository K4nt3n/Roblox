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
| Weekly fair | Enter your heaviest veggie once per week (a heavier one replaces it and the old one returns). Global top 10 is live; rewards are claimed on your next join after the week ends. | `FairService`, `shared/FairMath` |
| Skip wait | Developer product stub. In Studio the Skip button simulates a purchase; set real ids in `Config.Monetization`. Receipts are idempotent. | `MonetizationService` |
| Welcome back | On join you get a summary of what ripened while you were away. | `GardenService:_sendWelcomeBack` |

## Architecture

```
src/
  shared/            ReplicatedStorage.Shared (pure modules, no Roblox services)
    Config.luau        every tunable
    GrowthMath.luau    plant/grow/water/skip math (timestamp based)
    EconomyMath.luau   prices, upgrades, XP
    FairMath.luau      week ids, scores, reward tiers
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
      FairService        weekly weigh-in, OrderedDataStore board, rewards
      MonetizationService  dev products and receipts
  client/            StarterPlayerScripts.Client
    init.client.luau   starts Feel -> Garden -> UI, then listens for state
    ClientState.luau   latest snapshot + signals, server-synced clock
    NetClient.luau     request wrapper
    Feel/              game-feel layer (see below)
    Controllers/       GardenController (crop visuals, prompts), CropVisuals (art seam)
    UI/                Theme tokens, UIKit builders, UIController (HUD + panels)
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
  silent; fill an id and it plays, no code change.

## Art seams

| What | Where to drop it | Fallback today |
|---|---|---|
| Crop models | `ReplicatedStorage.Assets.Crops.<cropId>` (Model). Optional stage child models `Seed`, `Sprout`, `Growing`, `Ripe`, `Giant`. Set a `BaseDiameter` attribute for scaling. | Colored ball |
| Particles | `ReplicatedStorage.Assets.Particles.<name>` (ParticleEmitter), named in `FeelHooks.Particles` | None |
| Sounds / animations | Asset ids in `FeelHooks.Sounds` / `FeelHooks.Animations` | Silent |
| Garden positions | `Workspace.GardenSlots.<1..8>` parts | Generated grid |
| Shop / market / fair stands | `Workspace.Stands.<SeedShop/Market/FairStand>` parts | Placeholder blocks |
| Map | Any `Workspace.Map` or `Workspace.Baseplate` | Generated ground |
| UI look | `UI/Theme.luau` tokens and `UI/UIKit.luau` builders | Rounded placeholder UI |

## Tuning

Everything is in `src/shared/Config.luau`: crop grow times, weights and prices, watering boost and
cooldowns, upgrade curves, plot costs, XP curve, fair tiers, rate limits. Unit tests check that the
tables stay consistent (for example each upgrade has one more value than costs).

## Known gaps (tracked in the timeline)

- Purchases are granted before the profile is force-saved (timeline M1).
- No tutorial, daily streak, or settings menu yet.
- Fertilizer speed is locked in when a seed is planted, so buying it speeds up the next planting.
- The UI re-renders an open panel on every snapshot; fine for a prototype, worth diffing later.
