# What each ending keeps, the stash, and the Lair (2026-09-26)

ROGUELITE_REWORK rulings 17.6–17.7, built. Before this, every ending kept nothing but XP.

## The rules, as built

| Ending | Keeps |
|---|---|
| **victory** | every piece of gear and every relic found this run |
| **fled** (new) | the **3** items the player picks |
| slain / throne_fell / abandoned | nothing but XP |

- **Items are gear and relics only** — never resources.
- **Carry-in:** one item may be taken into a run from the stash (**1 slot → 2 at level 7 → 3 at
  level 10**, never more). It works from the first step. **If he dies it is lost for good**; if he
  comes home alive it goes back on the shelf marked as risked, and pays `risked_relic_survived`
  XP (20).
- **Fleeing** is only possible from the lair band, and only alive: `RunLifecycle.can_flee()`.

## What was built

- **`MetaProfile`**: `stash` (entries `{uid, id, run, day, shelf, carry, risked}`), `LAIR_SHELVES`
  8, `add_to_stash`, `remove_from_stash`, `carry_slots(class)`, `set_carry`, `set_shelf` (a shelf
  holds one item; putting another there takes the first down), `on_shelf`; blueprints (for L2).
  All of it saved with the XP.
- **`RunLifecycle`**: `_carry_in()` at the start of a run (and `reapply_carry_in()` when the Lair
  is closed before the first step), `run_items()` (this run's finds, never the carried-in one),
  `flee(keep)` → `end_run("fled")`, `_settle_items` applying the table above, and the summary's
  `kept` / `lost` lists. "Fled" has its own title and epitaph ("…fled the region alive").
- **`scripts/ui/KeepItemsDialog.gd`**: the flee picker. Pre-ticks three, locks the rest at the
  limit.
- **`scripts/ui/LairScreen.gd`**: the hall — eight shelves, the stash with a pick button and a
  Carry box per item, carry boxes locked at the slot limit.
- **Buttons:** "The Lair" on the title and on the run-end screen; "Flee the region…" in the pause
  menu (greyed away from the lair) and in his panel when he is home. The abandon confirm now says a
  carried item is lost.
- **`data/progression.json`**: unlocks `relic_slot_2` (level 7) and `relic_slot_3` (level 10);
  event XP `risked_relic_survived` 20.

## Verification

`tools/verify_endings.tscn` — **33**: carry slots 1 → 2 → 3 and no further; stash ids; the carry
limit; shelves; fleeing only from the lair and keeping exactly the three chosen; victory keeping
all five; death losing a carried-in relic for good; coming home alive with one (still stashed,
marked risked, XP paid); the picker's pre-tick and lock; the Lair's carry boxes; the title's Lair
button; the pause menu's greyed Flee. Profiles are in memory — nothing touches the real save.

Screenshots were checked for the title, the Lair and the flee picker. Decorating the Lair
(ruling 17.7) is shelves only for now: which item sits where, nothing else.
