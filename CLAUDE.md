# Warlords (working title: Undead Empire Prototype)

Villain-power-fantasy roguelite settlement builder (Against the Storm / RimWorld lineage, inverted:
you're the villain). Godot 4.7.1, GDScript, GL Compatibility. Local-only, no external deps.
Repo: https://github.com/OverSeerFulgrim/Warlords (branch `main`).

**This file is orientation only, hard budget ~8KB.** Detailed design lives in `docs/design/`,
graphics rules in `docs/art/SPRITE_SPEC.md`, and the full development narrative in `docs/history/`
(dated files, indexed in `docs/history/README.md` — read the relevant one only when a task touches
that system). Session write-ups append to `docs/history/`, NEVER here.

## Current phase

Roguelite rework, **R2 in progress — R2a done, R2b next** (`docs/design/ROGUELITE_REWORK.md` §13
is the roadmap; it supersedes GAME_OUTLINE stages 4–5). R2a shipped the lootable-site layer — 15
placed sites, channelled looting, the grave choice sheet, loot/relics/gold, dens gating the dusk
raid, the deeds ledger R3 reads (`docs/history/2026-08-loot-sites.md`).
R1 is done: directly-controlled killable Necromancer (WASD,
camera follow), 144×144 fixed world with terrain/blocking/roads/fog, static village, sealed rival
ground, travel times tuned to WORLD_MAP_PLAN §3. The Stage 1–3 settlement loop (priority-list
economy, Barracks intake, generated recruits, meals/morale/desertion, fund-a-house, wolf combat,
Command Undead) is built and verified. Win/lose is still the old placeholder; run lifecycle is R4.
Climate: deliberately not implemented. One villain class (Undead Empire) for now — but **no system
may assume exactly one villain on the map** (per-villain state on the villain object, never in an
autoload/global).

## Architecture conventions (the load-bearing ones)

- `GameState` (autoload) — single source of truth for resources/threat/power/followers. Reputation
  is per-villain (ROGUELITE_REWORK §7/§11, decided 2026-08-06): today's `GameState.reputation` int
  is legacy, replaced in R3 by five axes on the villain object — never extend it. Threat stays
  global (world state). `EventBus` (autoload) — ALL cross-system communication is signals here,
  not direct references.
- **Sim state lives on data objects (RefCounted); tokens are pure views.** `Worker`/`Follower`
  (extend `Laborer`), `Necromancer` own position/hp/state; `*Token` nodes only draw. Never put
  timers or state on a token — that drift has been unwound twice already.
- `ResourceNode` is a Node2D on purpose (its position/appearance IS its gameplay content).
- **Content is data-driven:** `data/*.json` (races, buildings, events, missions, recruitment,
  world_map, world_sites). New content = JSON edit; new *effect types* = extend the relevant system.
- Combat: `Combat.gd` is THE damage formula (knows nothing); `CombatSystem.gd` is policy.
  Duck-typed contracts: `get_inspect_data()` (inspectables), Combatant methods (fighters).
- Stats: the nine-attribute model of `docs/design/COMBAT_SPEC.md` §2. **Live since C2** —
  Might is gone. `stat_rework_roster.xlsx` is the editing surface; `tools/export_roster.gd` derives
  `data/races.json` from it, templates and overrides included. Carry = Endurance, max_hp =
  8 + End×2, walk speed derives from Speed. One governing attribute per skill; effective =
  skill + floor((attr−5)/2), clamped 1–10 and **computed at use time, never stored**. Attack
  profile (Melee/Ranged/Arcane) falls out of highest Str/Dex/Int — a unit needing a hand-written
  profile means the rule is wrong, not the unit special. Creatures and villains use the same nine.
- Indirect control is a pillar: no unit orders. The exceptions are the Necromancer (driven
  directly) and Command Undead (binds the dead as a class, via `alignment: "Undead"`).
- The Necromancer is NOT a Laborer and not in any labor pool — keep the exclusion structural.
- Timers must be delta-accumulators or SceneTreeTimers so `Engine.time_scale` (debug 1x/10x/60x)
  scales everything together. Never `Time.get_ticks_msec()` for gameplay.

## Graphics rules

`docs/art/SPRITE_SPEC.md` is the ONE authority for **characters and buildings** (256px canvas,
y=224 baseline, body families). **Terrain sheets are explicitly outside it** — full-res 4x4
tilesheets in `assets/official/terrain/`, sliced to 64px at load; `TERRAIN_SPEC.md` §2 governs
them and `tools/dump_atlas.gd` is how you read one.
In code: sizes are **content heights** via `Anchoring.scale_for_content_height()` (never divide
by texture width; never use `CELL_SIZE` as a sprite size). `Anchoring.foot()` / `cell_base()`
anchor the drawn alpha box. Click radii come from `Anchoring.drawn_content_size()` × 0.45.
Exception: the wolf is width-scaled (quadruped rule); `WorldSite`/`Patrol` still use the old
canvas-width math — convert them only together with re-tuning `data/world_sites.json`.
`assets/official/` is commissioned art (masters in `_originals/`, .gdignore'd — leave alone);
`assets/placeholder/` is stand-ins (delete each in the commit that replaces it);
`assets/vendor/` is cold storage — nothing there is wired. New art lands in the right subfolder,
named per SPRITE_SPEC, in the same commit that wires it. Never at repo root.

## File map

```
scripts/Main.gd            wiring root + input-mode arbitration (placement > demolish > rally > inspect)
scripts/ui/                InspectionPanel (the one inspect panel), Minimap, HudTopBar, BuildMenu,
                           EconomyTab, EventPanelUI, InspectorActions, TokenLayer,
                           CombatFeedback (pooled floating damage numbers)
scripts/autoload/          GameState, EventBus, BuildingCatalog, RaceCatalog, LootCatalog (load-once
                           JSON catalogs; LootCatalog also owns THE loot roll)
scripts/settlement/        SettlementGrid, Building, WorkerSystem (trip loop), Laborer/Worker,
                           MoraleSystem, HousePlanner/HouseStyle, ResourceField/ResourceNode, tokens
scripts/villain/           Necromancer (data), VillainController (WASD+camera follow)
scripts/combat/            Combat (formula), Engagement, CombatSystem (policy), UndeadCommand, RallyPoint
scripts/world/             WorldMap (ONE TileMapLayer, 7-sheet atlas + connection tiles + ONE
                           MultiMeshInstance2D canopy),
                           FogOfWar (one 144×144 image), DayNightCycle,
                           WorldSite(s) (loot state on the node), SiteGuardian, Patrol, Wolf,
                           Roaming, TravelLog
scripts/bounty|events|missions|threat/   Stage-4 systems, built but mostly unsurfaced in UI
data/                      the JSON content (races/buildings/events/missions/recruitment/world_*,
                           loot_tables/relics/site_choices)
tools/                     generators + verification harnesses (KEEP: they re-derive every number),
                           make_world_map.gd (GENERATES the layout by rule -- 9-step pipeline,
                           TERRAIN_SPEC §8; re-run and commit the JSON after editing),
                           export_roster.gd (stat_rework_roster.xlsx → data/races.json),
                           dump_atlas.gd (READ ITS OUTPUT before wiring a terrain sheet)
docs/design|art|prompts|history/         specs, art rules, prompt libraries, dated dev narrative
assets/official|placeholder|vendor/      see Graphics rules
```

## Verification harnesses (run after touching the related system)

- `godot --headless --path . --import` — required after adding any `class_name`
- headless boot: `godot --headless --path . --quit-after 200` — clean start check
- `tools/check_sprite_scales.tscn` — 122 assertions: everything draws at its claimed size, and
  every looted-state sprite shares its unlooted partner's canvas
- `tools/measure_travel.tscn` — travel bands vs WORLD_MAP_PLAN §3. **The gate on any map change**
  (TERRAIN_SPEC §9): every row must be back in band, and walk speed is not a knob
- `tools/verify_terrain.tscn` — 261 assertions: per-file sheet slicing, 112 distinct atlas tiles
  with none all-black, every legend char and all 80 mask entries resolving, the flipped
  alternatives, **and the generated layout** — road network connected to every landmark, no path
  within 3 cells of a Band 4 site, river crossings ≤25 cells apart, flood fill sealing off no
  region, clearings with exactly one mouth, canopy within budget. Terrain-only draw calls (run
  windowed for that gate)
- `tools/verify_loot_tables.tscn` — 500 assertions: every table rolled 10k times against
  LOOT_SITES_SPEC §5's bands (four per-column authored exceptions), relics unique, the grave
  sheet's gating, remainder charges, the notice-vs-deeds split, relic effects waking only on
  deposit, Dark Essence unprintable at home, and the dusk gate (1,000 dusks each way)
- `tools/smoke_site_actions.tscn` — 26 assertions: presses the site action buttons **as buttons**,
  through `Main._inspect_at` and the real panel, checking no later sibling Control covers them.
  The only cover on the click→`begin_action` chain; a human mouse is still the last word
- `tools/verify_stats.tscn` — 505 assertions: nine attributes, the derivation formula against the
  workbook's Effective skills sheet, profiles, hp/carry, no identifier named Might (after ANY
  roster or stat change)
- `tools/verify_combat_feedback.tscn` — 31 assertions: one emit per landed swing both ways,
  the 32-float cap, no leak over 1000 exchanges, and Combat/Engagement still signal-free
- `tools/check_fog_and_minimap.tscn` — 41 assertions: multi-source fog (villain 7 cells, friendly
  units 3, lit-while-present), the cell-boundary early-out, minimap dots and the two click paths
- `tools/capture_settlement.gd` — seeded windowed screenshot for before/after eyeballs

## Gotchas (one line each; details in docs/history/)

- godot-mcp simulated input NEVER reaches the game (`_unhandled_input`/`Input.is_key_pressed`);
  only `click_button_by_text` works. Real mouse/keyboard QA needs a human.
- The debug game window may eat its first real click (OS focus) — click once, then test.
- `-s` scripts compile before autoloads exist → run harnesses as scenes
  (`godot --headless --path . res://tools/x.tscn`); `load()` in `_init()` hangs headless.
- Headless viewport is 64×64 — set `root.size` before any geometry assertion.
- Signal arity: a handler missing the signal's args connects fine and fails silently at emit.
- GDScript lambdas capture locals by value — mutate through an Array or member.
- `_set` is an Object virtual — don't name helpers that.
- `project.godot` keys are section-relative; verify with `ProjectSettings.get_setting()` at runtime.
- `get_process_delta_time()` is already time-scaled — don't multiply again in harnesses.
- Some `Icons/Food/` files are really named `*.png.png` — check disk before "fixing" paths.
- Keep repo paths short — a 260-char path once broke git entirely (MAX_PATH).
- Y-sort: opt-outs by higher z_index are deliberate (Necromancer 5, wolf 6, fog 100).

## Maintaining this file

Orientation only. If you're writing more than ~10 lines about a pass you just finished, it goes in
`docs/history/YYYY-MM-topic.md` (and a row in that folder's `README.md`) and this file gets at most
a one-line pointer. Budget ~8KB.
