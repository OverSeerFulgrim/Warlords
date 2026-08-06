# Implementation Plan — Recruit Traits

A self-contained work order for implementing the trait system. Written for an implementing agent with no prior context on this project.

**Read before touching anything:** `CLAUDE.md` (architecture conventions + what every system does), `TRAITS.md` (the design being implemented — trait list, rules, conflicts), `RACES.md` (how recruits are generated), `FOUNDATION_SPEC.md` §3 (stat roll rules). Follow CLAUDE.md's conventions: data-driven JSON, autoload singletons for catalogs, EventBus signals for cross-system communication, log-and-alert over modal popups. **Commit when done** with a descriptive message. If the game launches as a blank window at any point, check `scenes/Main.tscn` still has its `script = ExtResource(...)` line before debugging anything else (known recurring corruption — see CLAUDE.md).

## 0. Ordering — read this first

A **stat system rework is in design and not yet built.** It replaces Might/Guile/Influence/Loyalty with nine attributes (Strength, Dexterity, Speed, Endurance, Intelligence, Guile, Perception, Tact, Loyalty), twelve skills derived as `skill + floor((governing_attribute − 5) / 2)`, and a condition layer (hp, morale, hunger, disease). It also replaces the combat system's flat hp-percentage flee check with morale-driven routing.

**Traits are still worth building now**, because the bulk of this plan is MoraleSystem and economy work that the rework doesn't touch. But three things follow from the ordering, and they are not optional:

1. **Every combat effect in this plan is deferred.** Stored in JSON, parsed, ignored. Do not touch `scripts/combat/` this pass. The traits still roll, still display, still read correctly to the player — only their combat consequences wait.
2. **`stat_bonus` may only target stats that survive the rework.** Loyalty, Guile, Perception, Leadership and Foraging all survive. Influence does not.
3. **Perception and Leadership do not exist in the codebase yet.** Two traits (Keen-eyed, Charming) target them. See §2 for how to handle that without inventing half the rework.

The stat rework will be its own pass with its own document. Nothing here should try to get a head start on it.

## 1. Data: `data/traits.json`

New file. One entry per trait from TRAITS.md's table. Schema per entry:

```json
"industrious": {
  "display_name": "Industrious",
  "description": "Never happier than mid-task. Works fast, sulks when idle.",
  "hint_line": "There's always somethin' needs doin'. Point me at it.",
  "conflicts": ["lazy"],
  "effects": {
    "work_speed_mult": 1.2,
    "idle_day_morale": -1,
    "train_speed_mult": 2.0
  }
}
```

`hint_line` is new and is **required on every entry.** TRAITS.md's rules section makes traits hidden at the gate and revealed in the Barracks; the hint line is the raw material the recruit-offer dialogue is assembled from. Write one per trait now even though §2 only stores it — authoring sixteen lines of voice is a writing job, and doing it inside the JSON pass is much cheaper than retrofitting it later. Keep them in character: a Glutton asks about food, a Lazy negotiates their hours, neither says the word "trait".

### Live keys — implement now

| Key | Type | Consumed by | Meaning |
|---|---|---|---|
| `stat_bonus` | dict, e.g. `{"loyalty": 1}` | RecruitGenerator | Added after the d3−d3 roll, clamped 1–10. **Only Loyal (+1 Loyalty) and Sticky-fingered (+1 Guile) are live** — see §2 for Charming and Keen-eyed |
| `work_speed_mult` | float | trip-loop gather timing | Multiplies gather speed (divides per-unit action time). Industrious 1.2, Lazy 0.8 |
| `food_mult` | float | MoraleSystem meals | Multiplies race food_per_meal. Glutton 1.5, Ascetic 0.5 |
| `shorted_morale_mult` | int | MoraleSystem | Morale loss multiplier when a meal is missed (Glutton 2) |
| `fed_morale_bonus` | int | MoraleSystem | Extra morale on a fully-fed day (Glutton +1, cap 10 still applies) |
| `missed_meal_floor` | int | MoraleSystem | Morale from missed meals can't drop below this (Fanatic 2) |
| `first_miss_free_per_cycle` | bool | MoraleSystem | First missed meal each dawn→dawn cycle costs 0 morale (Ascetic) |
| `baseline_morale_bonus` | int | MoraleSystem | Applied once at generation to starting morale (Lazy +1) |
| `idle_day_morale` | int | MoraleSystem, scored at dawn | Morale delta if the recruit did no work all cycle (Industrious −1) |
| `theft_chance_mult` | float | MoraleSystem low-morale theft roll | Greedy 2.0 |
| `petty_theft` | bool | MoraleSystem | Rare (~5%/cycle) 1-resource theft even at good morale, flavor log (Sticky-fingered) |
| `never_deserts` | bool | MoraleSystem departure path | Fanatic |
| `extra_desertion_warning` | bool | MoraleSystem | Second warning before leaving (Loyal) |
| `gain_day_morale` | int | MoraleSystem | +morale on any day GameState gained coin/dark_essence (Greedy +1; if neither resource is flowing yet this is dormant, implement anyway) |
| `neighbor_morale_immune` | bool | MoraleSystem | Morale events originating from other recruits don't land (Grumpy) |
| `housing_social` | string: `"pack"` or `"loner"` | MoraleSystem, checked at dawn | pack: +1 morale if own house adjacent (Chebyshev 1) to another house, −1 if no house within 2 cells. loner: inverse. Barracks residents: no effect |

### Blocked keys — store, parse, ignore

These are real designed effects whose consuming system is being rewritten. **Storing them is the deliverable; wiring them is not.** They must not produce warnings.

| Key | Type | Waiting on | Meaning |
|---|---|---|---|
| `rout_morale_offset` | int | morale-driven routing | Shifts the rout threshold. Cowardly −2 (routs earlier), Brave +2, Pack-minded −1 when isolated |
| `never_routs` | bool | morale-driven routing | Fanatic |
| `ally_death_morale_immune` | bool | morale-driven routing | Loner |
| `requires_ally_to_engage` | int (cells) | combat targeting | Won't start a fight without an ally within N cells. Cowardly 3 |
| `combat_damage_bonus` | int | combat exchange | Bloodthirsty +1 |
| `kill_morale_bonus` | int | combat morale | Bloodthirsty +1 |
| `assist_radius_cells` | int | auto-assist check | Brave 5 (default 3) |
| `escalates_friction` | bool | relationship system | Bloodthirsty |

Note what is **not** in either table: the old `flee_hp_pct`. Routing is no longer a flat hp percentage, so that key describes nothing and should not appear in the JSON at all. If you find it referenced anywhere, it's stale.

### Deferred keys — Stage-4+ systems

Store and ignore, same as blocked, but these wait on features rather than on a rewrite: `stealth_bonus`, `bounty_min_difficulty_refused`, `bounty_prefers`, `bounty_reward_demand_mult`, `trade_price_bonus`, `relationship_start_bias`, `co_bounty_bonus`, `solo_bonus`, `ambush_penalty_mult`, `never_ambushes`, `grudge_on_fail_bonus`, `train_speed_mult`.

**The loader must tolerate unknown keys silently — that is a hard requirement, not a nicety.** With two whole categories of stored-and-inert keys, this requirement is doing real work rather than guarding a hypothetical.

## 2. Code changes

**`TraitCatalog` (new autoload)** — `scripts/autoload/TraitCatalog.gd`, registered in `project.godot` after `RaceCatalog`. Same load-once pattern as RaceCatalog/BuildingCatalog. API: `get_trait(id) -> Dictionary`, `all_ids() -> Array`, `hint_line(id) -> String`, `effect(follower, key, default)` — a helper that scans a follower's traits and returns the combined effect value (sum for numeric bonuses, product for `*_mult` keys, OR for bools, first-found for strings). Put the stacking rule in ONE place (this helper), because two traits can both carry the same key.

**`RecruitGenerator`** — after stats are rolled: roll 1 trait uniformly; 30% chance of a second; if the second conflicts with the first (check both directions via `conflicts`), reroll the second up to a few attempts, then settle for one. Apply `stat_bonus` and `baseline_morale_bonus`. Skeleton Workers get no traits (they're `Worker`, not `Follower` — this should already fall out naturally; verify).

**Charming and Keen-eyed** target Leadership and Perception, which don't exist yet. Do **not** add those stats to `races.json` or `Follower` to make the bonus work — that's the stat rework leaking into this pass. Instead: give both traits their full JSON entry with the correct `stat_bonus` (`{"leadership": 1}` and `{"perception": 1}`), and have `RecruitGenerator` skip any `stat_bonus` key it doesn't recognise as a field on the recruit, logging nothing. Both traits still roll, still display, still read correctly to the player; their bonus activates for free the day the stat exists. Same principle as the blocked keys.

**`Follower`** — `traits` array already exists; keep storing **trait ids** (strings). `evaluate_bounty()` already string-matches old trait names (Bloodthirsty, Greedy, Cowardly, Loyal, Fanatic) — those ids collide with the new set *by design*; verify the casing matches what evaluate_bounty expects or normalize. The retired old-pool traits that don't exist in traits.json need no migration (no live followers persist across sessions).

**Trip loop** (WorkerSystem/Laborer — see CLAUDE.md "Physical gathering") — apply `work_speed_mult` to the per-unit gather time for Followers. Workers are unaffected (no traits).

**`MoraleSystem`** — the bulk of the work. Wire every key from the live table. Note the existing meal logic feeds highest-Loyalty first and tracks a fractional food pool; `food_mult` multiplies the individual's draw from that pool. The dawn cycle-scoring pass gains: `idle_day_morale` (needs a worked-this-cycle flag set by the trip loop when a Follower deposits), `housing_social`, `gain_day_morale`, `fed_morale_bonus`.

**`scripts/combat/` — do not modify this pass.** Every combat effect is in the blocked table.

**UI** — trait names shown: Barracks panel rows, roster/follower list, and the inspection panel (`get_inspect_data()`). Tooltip or secondary line with each trait's description where space allows; at minimum names everywhere, descriptions in the inspection panel.

**The recruit-offer popup is the exception, and it is the important one.** Per TRAITS.md, traits are hidden at the gate. The offer shows race, class, best skills — and must **not** name traits. Wiring the `hint_line` dialogue into the offer is a separate pass (it needs a line-assembly rule for two-trait recruits, and a decision about how visible food cost stays); for this pass, simply ensure the offer does not leak trait names, and leave the dialogue slot unfilled. Getting this wrong in the other direction — shipping trait badges on the offer — would ship a design that's already been superseded.

## 3. Edge cases

- Two traits stacking the same key: handled centrally by `TraitCatalog.effect()` (sum/product/OR rules above).
- `stat_bonus` after exceptional (+1) roll: both apply, clamp 1–10 last.
- `stat_bonus` naming a field the recruit doesn't have: skip silently (see §2 — this is the Charming/Keen-eyed path, and it is expected, not an error).
- A trait id in a follower that's missing from traits.json (future data edits): log one warning, treat as no effects — don't crash.
- Morale caps: all bonuses respect the 1–10 clamp; `missed_meal_floor` only floors losses *from missed meals*, not theft-event or friction penalties.

## 4. Verification

Headless harness (delete after, including any project.godot autoload edits — check none linger):

1. Generate 200 recruits: every recruit has 1–2 traits, no conflict pair ever co-occurs, distribution roughly uniform, ~30% have a second trait.
2. Loyal recruit's Loyalty averages 1 higher than baseline; clamp respected. Sticky-fingered likewise on Guile.
3. Charming and Keen-eyed recruits generate cleanly with **no warnings and no crash**, despite targeting stats that don't exist — and their traits still appear in the recruit's trait list.
4. Industrious vs Lazy follower on identical gathering trips: ~1.5× delivery ratio over a fixed window.
5. Glutton eats 1.5×; Ascetic 0.5×; starve both — Glutton loses 2 morale/miss, Ascetic's first miss of the cycle is free.
6. Fanatic starved repeatedly: morale floors at 2, never deserts. Loyal gets two warnings.
7. Grumpy is unaffected by a neighbor-sourced morale event that moves a control recruit.
8. Every trait in traits.json has a non-empty `hint_line`.
9. Unknown-key tolerance: add a fake `"xyzzy": 3` effect to one trait, confirm silent ignore. Confirm the same for every key in the blocked and deferred tables — nothing in `scripts/combat/` changed, and nothing warned.

Manual checks to list for the user: trait names visible on the Barracks panel and inspection panel; **trait names absent from the recruit-offer popup**; a Lazy recruit's description readable somewhere.

## 5. Documentation

Update CLAUDE.md: the new TraitCatalog autoload, the effect-key vocabulary (or a pointer here), the stacking rule location, the `hint_line` field and why the offer popup deliberately doesn't use it yet, and the note that blocked keys are stored-but-inert pending the stat rework. Update `TRAITS.md` only if implementation forced a design deviation — and say so explicitly in the commit message.

## Out of scope — do not build

The stat rework itself (attributes, skills, condition, the derivation formula). Anything in `scripts/combat/`. The recruit-offer dialogue assembly. Stealth rolls, bounty preference logic beyond what `evaluate_bounty` already does, relationships, missions, race-weighted trait odds, race passives, classes. The deferred and blocked keys exist so those systems can consume them later; implementing any of them now is scope creep.
