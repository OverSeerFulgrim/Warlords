# Items, gear, and resources that take no space (2026-09-26, evening)

The first playtest, three complaints in one message: the Wolf-Hide Cloak could not be worn;
looting swept everything into his hands with no say; and resources filled the same six slots the
items needed. Ruled by the designer the same evening (asked and answered):

1. **Gear can be worn anywhere** and works the moment it is worn.
2. **Resources have no limit.** The banking rule still applies: none of it is his until the
   Throne, and death costs all of it.
3. **Six item slots, and the escort no longer carries.** Worn gear takes no slot.

## What changed

- **`data/relics.json`**: items with a `slot` are **gear** — cloak (Wolf-Hide Cloak), hands
  (Pallbearer's Gloves), ring (Sexton's Ring), neck (Tarnished Locket), held (Chipped Censer,
  Barrow Lantern — they compete). The rest (the coins, the Seal, the Sermon, the Ledger) are not
  gear and still **work once banked**.
- **`Necromancer`**: `equipped` (slot → id), `equip(id, from_hoard)`, `unequip(slot, to_hoard)`,
  `active_relic_ids()` (worn gear + banked non-gear — every effect reader uses it),
  `owned_relic_ids()`, `lose_unbanked_gear()`, `remove_item()`. `carry_capacity()` is now **item
  slots**; `carried_total()` counts items only; `add_carried()` takes every resource;
  `resources_carried_total()` for the panel. Gear found this sortie and worn is still lost if he dies
  before the Throne; gear taken from the hoard is not. `bank_relics()` counts worn gear as come
  home (XP and the log).
- **`SortieSystem`**: party capacity is his item slots; `take_into_party` puts resources in his
  pack only (skeletons are no longer porters); death also calls `lose_unbanked_gear()`.
- **`WorldSite`**: a pull puts resources in his pack and **items on the ground**
  (`relic_remainder`), emitting `items_on_ground`. New `pick_up_item`, `wear_item` (straight off the
  ground, no free slot needed; whatever it replaces goes to the bag or, if the bag is full, the
  ground) and `leave_item`. Site actions: "Look through the items here (N)" and "Pick up <resources>"
  (always enabled). The old "hands are full" collect refusal is gone.
- **`scripts/ui/ItemsDialog.gd`** (new): the Items window — on the ground (Take / Wear), worn (Take
  off, or Put in the hoard at the Throne), the bag (Wear / Leave here / Drop), and the hoard at the
  Throne (Wear). Each item says what it does in one line (`effect_text`). Opens by itself when a
  pull drops items (real game only — harnesses open it by hand), from the site's row, from his
  panel's **Items** button, or with **I**. Pauses the world while open.
- **Guild pay** always fits now (it is gold); the "owed at the counter" path stays in the code but
  cannot trigger.
- **RunLifecycle**: the run's items include worn gear; carried-in gear is worn from the first step
  if its slot is free.

## Verification

Harnesses rewritten to the new rules where they asserted the old ones: `verify_sortie` **79**
(item slots, no escort carry, items on the ground, worn vs banked effects, one item per slot, death
loses unbanked worn gear only), `verify_loot_tables` **533**, `verify_guild` **65**,
`verify_raise_dead` 26, `smoke_site_actions` 26 (the pick-up row, the window's Wear and Done as
buttons), `verify_villain_combat` 65, `verify_demo_shell` **40** (the new I key). Everything else
unchanged and green; screenshot of the Items window checked.

## Every building is a blueprint (same evening)

The designer, after the same playtest: a new run should not open with every building on the bar;
mechanics arrive one at a time, roguelike-fashion. Ruled (asked and answered): **every building is
unlocked by a blueprint found in the world**, known for good once found; **run one can build
nothing**; and the UI is to be redone, **mockups first**.

- `data/buildings.json`: Bone Pile, Workshop, Blacksmith and Barracks join the Dark Altar as
  `"blueprint": true`. Only the Throne is placed at the start.
- `data/world_sites.json`: a lootable block can name a `blueprint`. First choices, all editable
  there: **Bone Pile** — the band-2 graveyards (derelict or village, whichever the run activates);
  **Workshop** — the abandoned camp; **Blacksmith** — the old crypt; **Barracks** — the outlaw cave.
  The Dark Altar stays with clearing a den.
- `WorldSite` hands the plans over on the first pull or grave choice that resolves there
  (`blueprint_found`), and its panel says "Plans: somewhere in here: how to build a …" until then.
  `RunLifecycle` learns it onto the profile (`blueprint_learned`), and the build bar repopulates.
- The empty build bar says why it is empty.
- `verify_guild` **69** (+4: run one builds nothing, the hint, the camp teaches the Workshop, the
  hint goes).
