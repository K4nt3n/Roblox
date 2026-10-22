# Studio test plan

Run with **Test → Local Server, 2 players** unless noted. Automated tests for the pure math live in
`tests/` (`luau tests/run.luau`); this list covers what needs a running game.

## New player
- [ ] Spawns at their own garden. Sign shows their display name. 3 plots open, the rest faded.
- [ ] HUD shows 50 coins, level 1, Carrot ∞ in the seed bar.
- [ ] Output shows no errors. Without API access, one warning about the in-memory store.

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

## Fair
- [ ] Enter Fair from the Basket removes the item and shows it in the Fair panel and top 10.
- [ ] Entering a lighter crop is refused; a heavier one replaces the entry and returns the old one.
- [ ] Countdown ticks every second while the panel is open.
- [ ] Week rollover: set `Config.Fair.weekAnchorUnix` so the week ends in a minute, rejoin after it ends, and confirm the reward toast and coins.

## Skip wait (stub)
- [ ] Shop → Garden → Skip on a growing crop makes it ripe at once (Studio only).

## Persistence (needs API access)
- [ ] Plant a pumpkin, leave, wait a few minutes, rejoin: crop has grown, welcome-back toast lists ready crops.
- [ ] Coins, seeds, upgrades, basket and fair entry survive a rejoin.

## Abuse
- [ ] Spam a shop button: after 8 calls in 2 s requests are refused with "Whoa, slow down!".
- [ ] From the client command bar, invoke the Request remote with junk (`nil`, numbers, other players' plot ids). Nothing changes and the server logs no errors.
