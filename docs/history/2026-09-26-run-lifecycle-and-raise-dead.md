# The run ends, and the dead come from the ground (2026-09-26)

The pass that followed `docs/REVIEW_2026-09-26.md`. Four designer rulings from that conversation,
the R2 close-out bugs the review found, and one new directory (`scripts/run/`).

## Rulings this pass implements

1. **Raise Dead is his starting spell (ruling C).** A corpse in a grave is raised **free**, from the
   grave's own sheet. Without a corpse, Raise Dead costs **5 bones** from the stockpile and works
   wherever he stands (his panel, the Economy tab, or **R**). There is no free starting skeleton
   (LIVING_WORLD ruling 9); the 10 starting bones buy two raises on minute one if the player wants
   them instead of walking to a grave.
2. **Death ends the run.** A run-end screen shows how it ended, the run's stats, XP earned, level and
   progress to the next level, the next unlock, and the last five chronicle lines. One button: begin
   a new run.
3. **Waking at the Throne is an unlock** ("Second Wake", level 5, once per run), not the default.
4. **Timed recruitment is stopped** (`EventSystem.TIMED_RECRUIT_OFFERS = false`). The offer machinery
   stays for R3 to re-trigger from reputation.

## What was built

- `scripts/run/MetaProfile.gd` — XP per villain class and the chronicle, in
  `user://meta_profile.json`. **Levels and unlocks are computed from XP at read time**, never
  stored, so re-tuning `data/progression.json` re-levels every profile without a migration.
  A plain RefCounted handed to whoever needs it, not an autoload.
- `scripts/run/RunLifecycle.gd` — one per villain, holding him as a field. Banks XP the instant it
  is earned (ROGUELITE_REWORK §9): deeds by id, wolves killed, buildings placed (not the seeded
  Throne), loot and relics banked at the Throne, and days survived at run end. Owns the ending:
  `slain`, `abandoned` (Surrender), `throne_fell` (the legacy crusade's `game_lost`) and `victory`
  (the legacy `game_won`, until the manor exists). Every villain-carrying signal is owner-checked.
- `scripts/ui/RunSummary.gd` — the run-end screen. A pure view over the summary Dictionary that
  arrives on `EventBus.run_ended`; `PROCESS_MODE_ALWAYS` because the tree is paused underneath it.
- `data/progression.json` — every XP number, the level curve, the unlock list. All hypotheses.
- `EventBus`: `skeleton_raised`, `xp_gained`, `villain_levelled`, `villain_woke`, `run_ended`.
- His panel now opens with "Level N — x / y XP · next: …", and **Raise Dead** replaces the
  "Further spells — coming soon" placeholder.

## Order on death, and why the end is deferred

`SortieSystem` (clears the haul) → `CombatSystem` (takes him out of every fight) → `RunLifecycle`
(wake or end). SortieSystem used to heal and teleport him itself, which is also why CombatSystem's
Necromancer branch of `_resolve_defeat` could never see him dead; it now only clears the haul.

The end itself is `call_deferred`. `villain_died` is emitted from inside a combat exchange, and
ending the run there paused the tree mid-exchange and put the epitaph in the log above the line that
announced the death (seen in the first scripted playthrough). A `_dying` latch stops a second death or
a Surrender landing in the same frame.

## Harness profiles never touch the player's

Main passes a real path to `MetaProfile.open()` **only when it is the running scene**
(`get_tree().current_scene == self`). Every harness instantiates Main as a child of its own scene and
kills the villain on purpose; those runs keep their profile in memory. `verify_run_lifecycle` writes
its own `user://_verify_run_lifecycle_profile.json` and deletes it.

## R2 close-out fixes (review §2)

| Review item | Fix |
|---|---|
| 2.1 raised corpse never became a unit | `WorldSites._raise_dead` calls `raise_handler` → `WorkerSystem.raise_skeleton_at` — a real Worker at the graveside, live on arrival. `RaisedDead.gd` is deleted. It joins an active escort the next frame (UndeadCommand re-binds every undead each frame); otherwise it walks home to work. |
| 2.3 escort loads orphaned / relabelled | `WorkerSystem._tick_idle` walks a unit home to bank before it may gather, so a dismissed escort's gold banks as gold. |
| 2.4 relic uniqueness through caches | `Necromancer.relics_rolled` records every relic a table handed him; `drawn_relic_ids()` includes it. `add_relic` refuses only what he holds or has banked, so the cached copy can be picked back up. |
| 2.6 timed recruitment | Off (above). |
| 2.7 time scale survives restart | `Main._begin_new_run` resets `Engine.time_scale` and unpauses before the reload. |
| 2.8 Main's `villain_died` had no owner check | Added. |
| 2.9 Collect ignored escort space | `SortieSystem.party_space_of(who)` (static); resources count the escort's arms, a relic-only remainder still needs his hands. |

## Harnesses

New: `tools/verify_raise_dead.tscn` (26) and `tools/verify_run_lifecycle.tscn` (43). Changed:
`verify_escort` now raises through the grave's `_resolve_choice` instead of `add_worker` (58);
`verify_sortie` / `verify_villain_combat` grant a Second Wake before their death test so the haul and
the wake are still tested and the run survives for the tests after (67 / 65); `verify_stats`,
`verify_combat_feedback` and `verify_escort` add a fixture skeleton, since there is no free one;
`verify_loot_tables` and `smoke_site_actions` assert a real Worker instead of a `RaisedDead`.

Scripted playthrough (headless, game-mode, persistent profile): R-key raise → walk to
`fresh_grave_hollow`, raise free → escort 2 → clear `wolf_den_valley` (villain down to 2–9 hp across
two runs) → loot → deposit → dismiss → walk alone into `wolf_den_southwood` → slain → run-end screen
up, tree paused → "Begin a new run" → 1x, unpaused, 0 workers, 10 bones, XP kept, level 2, chronicle
1. One sortie is ~90–100 XP; Second Wake (700 XP) lands around the sixth run. Screenshot of the
screen taken under Xvfb and checked by eye.

## Needs a human

- The run-end screen and the level line in his panel at your real window size and font.
- Whether 10 starting bones (two raises on minute one) undercuts "the first dead come from graves".
  Lower `GameState` starting bones below 5 if the grave should be mandatory.
- A raised skeleton walks home **in a straight line through terrain**, like every worker. Near the
  lair that never showed; from a far grave it will.
- XP numbers, the curve, and Second Wake's level — all in `data/progression.json`.

## Not done

Flee-the-region, map shuffle, the stash/Lair hub (R4/R5 proper). The legacy crusade and power win
still exist; they now end the run properly instead of doing nothing. Camp occupancy and R2e are
untouched.
