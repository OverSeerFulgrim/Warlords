### Meals, morale, desertion, and fund-a-house

Closes the last three gaps in the Stage 1–3 loop. Food finally has a consumer, morale finally has consequences, and the Barracks finally has an exit.

#### Meals (`MoraleSystem.gd`)

Hangs off `EventBus.dawn_started` / `dusk_started` — exactly what those signals were emitted for two passes ago, when `DayNightCycle` deliberately signalled rather than calling `ResourceField` directly. Two meals per 50-minute cycle.

- **Skeletons eat nothing.** They aren't even on the roster (`Worker`, not `Follower`), and any follower whose race has `food_per_meal: 0` is skipped. This is the undead perk that makes Stage 1 survivable with no food economy at all.
- **Highest Loyalty eats first** when food is short (FOUNDATION_SPEC §8). Deliberate villain flavor: the faithful get fed, malcontents starve — which makes a low-Loyalty recruit a liability precisely when you can least afford one.
- **Fractional appetites vs an integer resource.** Races eat 0.5–3.5 food/meal but `GameState.food` is a whole-unit resource that Workers deposit into. Rather than making the resource a float and rippling that through every deposit and the HUD, `MoraleSystem` feeds from a pooled float and carries the sub-unit remainder in `_food_remainder`. Without that carry a Kobold (0.5) and a Gray Dwarf (1.0) would cost the same, erasing the cheap-swarm-vs-elite-specialist tradeoff the whole roster is built on.

#### Morale

Per-recruit `Follower.morale`, 1–10, starts 7 — per-recruit rather than a settlement meter because §8 asks for it explicitly and it's what makes the feeding order meaningful. Shown per-resident in the Barracks panel and colour-coded (amber ≤3, red at 1).

- Miss a meal → −1. Clear a whole dawn→dawn cycle without missing one → +1, capped at 10. The cycle is scored at dawn *before* that meal is served. Note the one-cycle lag when recovering: the cycle during which food arrives still contains the earlier missed meal, so the bonus lands a cycle later. That's correct, not a bug — verified 7→4 starving, then 4→5→6 once fed.
- **Morale ≤ 3** → 25% chance per meal tick of theft/rule-breaking: 1–3 units of a random resource vanish with flavor text. Clamped to what actually exists, because a negative stockpile is a far worse bug than a theft that comes up short. Dark Essence is deliberately not stealable — it's the locked Stage-4 resource and losing it would be unreplaceable.
- **Morale 1** → one departure warning, then they leave on the *next* missed meal. The warning is a chance to recover, not a formality.
- **These are logged and alerted, not raised as modal popups.** The event panel is the recruit-offer channel; a blocking dialog every time a hungry goblin skims the stores would be exhausting. They still can't be missed — alert pin plus a coloured History entry.

Departures write to `GameState.departed` with a `disposition` int: **data only, nothing reads it yet.** It exists so departure-memory (GAME_OUTLINE gap #6 — leavers who return with a gift or ambush your villagers) has a history to work from. Disposition anchors on Loyalty (`loyalty - 8 + (morale - 1)`), so a Loyalty-10 fanatic who starved out still half understands while a Loyalty-3 goblin leaves bitter.

#### Fund-a-house (`HousePlanner.gd`, `HouseStyle.gd`)

Flat 6 wood / 4 stone per FOUNDATION_SPEC §9, charged by `SettlementGrid.fund_house()` rather than by the catalog entry, because `recruit_house` is never placed from the build menu.

**The recruit picks the cell, not the player** — GAME_OUTLINE pillar 4. `HousePlanner` implements RACES.md's five styles:

| Style | Rule | Races |
|---|---|---|
| clustered | adjacent to a same-race house, else communal | Goblin, Kobold, Gnoll, Halfling |
| communal | within 2 cells of any house, else the Throne | Orc, Hobgoblin, Human Outcast |
| spaced | Chebyshev ≥ 3 from every house, most isolated first | Ogre, Troll, Minotaur, High Elf |
| near_feature | nearest cell to the Stone Deposit (dwarves) or Workshop (Gnome) | Gray/Mountain Dwarf, Gnome |
| edge | grid rim, furthest from the Throne | Dark Elf |

**Nothing here may ever block.** Every style degrades preferred → communal → any free cell. RACES.md says that of Gnolls specifically ("preference-not-guarantee"), but it has to hold for all of them: the player has already paid, so an awkward grid must never eat the cost. Distances are Chebyshev (king-move) since diagonals are neighbours on this grid. "Town centre" means the Throne at (0,0) — a corner, not a literal middle, but it *is* where the settlement grew from, which is the sense the styles want.

`HouseStyle` picks sprite + tint per race from the 8-variant Kenney House pack — a placeholder in the same spirit as the generated deer, wanting only that a goblin warren doesn't read as a minotaur's lodge.

**Housing frees the Barracks slot.** `barracks_residents()` now counts only unhoused followers (it used to return the whole roster, correct only while this feature didn't exist). Housed recruits idle at their own doorstep via `Laborer.idle_anchor`, but still deposit loads at the keep.

