# The living village (LIVING_WORLD L0 + L1, 2026-09-26)

`LIVING_WORLD_SPEC.md` §14's first two steps, built on rulings 13–15: one settlement model for
everyone, and a human village that works, eats, trains its guards and reacts to being killed —
nothing scripted. Plus the **Hidden / Hunting stance** (§8.7), because L1's exit ("kill a woodcutter
and watch the village react") needed a way to start that fight without an attack button.

## L0 — one settlement model

- **`scripts/settlement/Settlement.gd`** (`class_name Settlement`): owner, id, display name, a
  stockpile over `KINDS` (wood, stone, food, bones, dark_essence, gold, arms), followers, power,
  home position, `stockpile_changed`. `deposit(kind, n, integrity)` multiplies a trip's yield by
  the building's integrity and **carries the fraction** (five 1-log loads at 80% bank exactly 4).
- **`GameState` is a façade** (ruling 13): `player_settlement` holds the numbers; `wood`, `stone`,
  `food`, `bones`, `dark_essence`, `gold`, `arms`, `power` and `followers` are get/set properties
  on it, and `add_resource` / `spend_resource` / `can_afford` delegate. Every existing call site is
  unchanged. `reset()` resets the settlement in place so connections survive. Starting stock is
  unchanged (8 wood, 5 stone, 5 food, 3 bones).
- **`WorkerSystem`** gained two hooks, `_home_for(w)` and `_deposit(w)`, so a second labour system
  can reuse the trip loop with a different drop-off and a different treasury.
- **`ResourceNode`** has a `crop_field` type (cap 24, regrows 12 at dawn); `ResourceField` has
  `spawns_deer` so the village's field does not breed deer.

## L1 — Harrowdale

- **`data/village.json`**: Harrowdale, owner `human`, 24 food / 12 wood / 4 stone. Buildings:
  farm (3 slots), guardhouse (2, trains), woodcutter (2, banks at the mill), mill; six houses.
  Eight people with names — Frank, Edda and Tobin farm; Osric and Brom are trained guards; Randy
  and Hale cut wood; Wyn has no work. Restaff priority farmer > guard > woodcutter.
- **`scripts/world/village/`**:
  - `Villager.gd` (extends `Laborer`, race `human_peasant`): job, workplace, house, training,
    panic with a 20-second calm, `depart()`, and the runner fields L2 uses. Panicked or running,
    his combat profile has no attack.
  - `VillageBuilding.gd`: a named building ("Frank's Farm" — the owner's name stays after he
    dies), slots, integrity (damage tints it; repair costs 2 wood per 0.25), an Output readout.
  - `VillageLabor.gd` (extends `WorkerSystem`): farmers to crop fields, woodcutters to trees, the
    jobless forage (35%), guards walk a beat, train at the guardhouse (90 s, Str +2 End +1 and
    warrior skills) and answer the alarm; the panicked run to a refuge and cower.
  - `Village.gd`: builds all of it, feeds everyone at dawn and dusk from its own stores,
    **restaffs** on a death (jobless first, then the lowest job below the gap — "Randy takes up a
    spear; the mill is a hand short"), raises an alarm (30 s, 14 cells), leaves a **body** where a
    villager fell, and records `slew_a_villager` (Cruelty) against the Necromancer who killed him.
- **Bodies** (`WorldSites.spawn_body`): a lootable site, "Frank's Body", on the grave sheet's
  grammar — raise, search, or hide (`site_choices.json` `body_choices`, `loot_tables.json`
  `villager_body`, band 1).
- **The village is a child of `settlement`** and draws under the fog like any site. The old
  scripted "Village Watch" patrol is gone from `world_sites.json`: the guards are real now.

## The stance (§8.7, ruling 15)

- `Necromancer.Stance` HIDDEN / HUNTING, `set_stance`, `toggle_stance`; **H**
  (`Controls` action `stance`), a button in his panel, a HUD line under the portrait.
- **Hidden** (the default): he starts no fight with the living. **Hunting**: anything living he
  walks up to is a target, through the same 26 px engage as a wolf — still no attack button.
  `CombatSystem.hostiles()` asks the village for its people only while he hunts.
- Hunting sets the escort **Aggressive** and remembers what it was; Hidden restores it.
- `Necromancer.standing` (per faction: Unknown / Suspected / Known, one way only) landed here too,
  for L2 to use.

## Verification

`tools/verify_village.tscn` — **56**: the façade (writes and reads go through the settlement,
one `resources_changed` per change), the fractional deposit, a second settlement that ticks,
integrity scaling the mill, meals from the village's own stores, the stance and `hostiles()`, a
Hunting kill through the real engagement with the alarm and restaffing that follow, the "Randy
rule", guard training, and raising a villager's body. Every other harness stayed green.

## Found on the way

- A panicked villager in a fight had his flight cancelled every frame (`_enter_combat` →
  `abandon_trip` reset FLEEING to IDLE), and one already home "arrived" at once and calmed. Fixed:
  a panicked villager is never made to abandon his trip, and he cowers with a countdown that only
  runs out of combat.
- `wayside_shrine`'s gold floor (1.98 expected vs a band floor of 2.0) was a latent flake the
  village's extra RNG draws exposed; its gold max went 3 → 4.
