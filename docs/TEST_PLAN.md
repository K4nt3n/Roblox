# Studio test plan

Run with **Test → Local Server, 2 players** unless noted. Automated tests for the pure math live in
`tests/` (`luau tests/run.luau`); this list covers what needs a running game.

## New player
- [ ] Spawns at their own garden. Sign shows their display name. 3 plots open, the rest faded.
- [ ] HUD shows 50 coins, level 1, Carrot ∞ in the seed bar.
- [ ] Output shows no errors. Without API access, one warning about the in-memory store.

## UI and feel
- [ ] HUD: coin pill top left, level pill with the level number in the badge, menu on the right, seed hotbar at the bottom.
- [ ] Buttons lift on hover, squash on press and spring back. Greyed-out buttons shake and toast why (e.g. "Not enough Coins yet!").
- [ ] Opening a panel dims and blurs the world, the hotbar slides away, rows pop in. X, tapping outside, or gamepad B closes.
- [ ] Opening Basket while Shop is open cross-fades. Shop and Fairs tabs slide their highlight.
- [ ] Selling: coins fly from the Sell button into the coin pill, the number rolls up and a "+N" floats off.
- [ ] Basket menu badge shows the produce count; Champion shows "!" when a care need is up; Ribbons counts new ribbons until the shed is opened.
- [ ] Spam a button: toasts stack as "x2", never more than 3 on screen.
- [ ] Device emulator (iPhone landscape, iPad, 1080p): everything readable, nothing off screen, hotbar clear of the thumbstick and jump button.
- [ ] Gamepad: opening a panel selects its first button; the gold ring moves with the D-pad; B closes.

## Plant, grow, water, harvest
- [ ] E on an empty plot plants a carrot. A small ball appears and swells smoothly (no jumps).
- [ ] Label above the crop counts down. Stage changes give a visible bounce.
- [ ] E on a growing crop waters it: soil darkens then fades back, timer drops, prompt shows "Watered" during cooldown.
- [ ] After about 2 minutes the label says "Ripe!" and E harvests. Toast shows the weight; XP bar fills.
- [ ] Leaving a ripe crop: it keeps growing, becomes GIANT (toast), then MAX.
- [ ] R on a ripe crop waters it toward Giant size.

## Friends
- [ ] Player 2 walks to Player 1's garden: only the Water prompt shows, labelled with the owner's name.
- [ ] Watering gives Player 2 +5 coins and a toast; Player 1 gets "X watered your garden!".
- [ ] After 10 waters on the same garden in a day, Player 2 sees the daily limit message.

## Economy
- [ ] Shop: buying tomato seeds deducts coins (count-down animation) and adds them to the seed bar.
- [ ] Locked crops say "Unlocks at level N" and can't be bought.
- [ ] Upgrades: level and cost update after buying; MAX at the end.
- [ ] Buying a plot un-fades the next plot. E on the next locked plot also offers to buy it.
- [ ] Basket: sell one and Sell All both pay the shown price.

## XP essence
- [ ] Harvest a crop: glowing orbs pop out of it, tumble, then curve into the XP bar. The bar fills in steps as they land, never snaps.
- [ ] Harvest enough for a level-up: the bar fills to the end, flashes gold, rolls over to the new level.
- [ ] Watering a friend's garden and caring for a champion also send essence.

## Champion
- [ ] A big plot sits in front of each garden. E on it says "Plant Champion" and plants the selected seed.
- [ ] In Studio a care need appears every 45 s: label hops and shows "Thirsty!", "Bugs!" or "Leaning!", and a toast says so.
- [ ] Thirsty: Water prompt says "Water (thirsty!)". Bugs / Leaning: F prompt appears. Handling it shows a toast, essence and adds care points (Champion panel).
- [ ] Champion panel: name it. Name shows on the plot label and in the fair. A rude name is filtered.
- [ ] Shop → Skip the wait: champion skip works once, then the button greys out and the server says "once a week". Panel now says "Natural Grown: not eligible".

## Grow together
- [ ] Champion panel → Invite Player 2. Player 2 gets a card; "Let's grow!" adds them. Both see a toast.
- [ ] Player 2 sees the F care prompt on Player 1's champion and can water it.
- [ ] After a fair with a prize, Player 2 gets coins and a team ribbon by mail (toast), also if they rejoin later.

## Fairs
- [ ] Basket → Enter Fair opens a picker with Hourly, Daily and Weekly. Entering removes the item and the toast names the fair and divisions.
- [ ] Entering a lighter crop in the same fair is refused; a heavier one replaces the entry and returns the old one.
- [ ] Fairs panel: tabs switch fairs; each shows its countdown, your entry, divisions and top 10.
- [ ] Fairs panel → "Preview show (Studio)": banner, letterbox, camera glides to the stage, each entry is weighed with a count-up, podium cards pop in winner last, global top 3, then the camera returns. "Back to garden" works at any time.
- [ ] Preview with nobody entered shows the "No entries from this server" card.
- [ ] Rollover: set an hourly `anchorUnix` so the hour ends in two minutes. The announce banner counts down, the show runs by itself, and results arrive as a card after it. A player who joins after the show gets "You missed the ... Here's the replay".
- [ ] Ribbons panel lists every ribbon won with a readable name.

## Skip wait (stub)
- [ ] Shop → Garden → Skip on a growing crop makes it ripe at once (Studio only).

## Persistence (needs API access)
- [ ] Plant a pumpkin, leave, wait a few minutes, rejoin: crop has grown, welcome-back toast lists ready crops.
- [ ] Coins, seeds, upgrades, basket and fair entry survive a rejoin.

## Abuse
- [ ] Spam a shop button: after 8 calls in 2 s requests are refused with "Whoa, slow down!".
- [ ] From the client command bar, invoke the Request remote with junk (`nil`, numbers, other players' plot ids). Nothing changes and the server logs no errors.
