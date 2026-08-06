# Warlords (working title: Undead Empire Prototype)

Villain-power-fantasy roguelite settlement builder (Against the Storm / RimWorld lineage, inverted:
you're the villain). Godot 4.7.1, GDScript, GL Compatibility. Local-only, no external deps.
Repo: https://github.com/OverSeerFulgrim/Warlords (branch `main`).

**This file is orientation only, hard budget ~8KB.** Detailed design lives in `docs/design/`,
graphics rules in `docs/art/SPRITE_SPEC.md`, and the full development narrative in `docs/history/`
(dated files — read the relevant one only when a task touches that system). Session write-ups
append to `docs/history/`, NEVER here.

## Current phase

Roguelite rework, stage **R2 next** (`docs/design/ROGUELITE_REWORK.md` §13 is the roadmap; it
supersedes GAME_OUTLINE stages 4–5). R1 is done: directly-controlled killable Necromancer (WASD,
camera follow), 144×144 fixed world with terrain/blocking/roads/fog, static village, sealed rival
ground, travel times tuned to WORLD_MAP_PLAN §3. The Stage 1–3 settlement loop (priority-list
economy, Barracks intake, generated recruits, meals/morale/desertion, fund-a-house, wolf combat,
Command Undead) is built and verified. Win/lose is still the old placeholder; run lifecycle is R4.
Climate: deliberately not implemented. One villain class (Undead Empire) for now — but **no system
may assume exactly one villain on the map** (per-villain state on the villain object, never in an
autoload/global).

## Architecture conventions (the load-bearing ones)

- `GameState` (autoload) — single source of truth for resources/reputation/threat/power/followers.
  `EventBus` (autoload) — ALL cross-system communication is signals here, not direct references.
- **Sim state lives on data objects (RefCounted); tokens are pure views.** `Worker`/`Follower`
  (extend `Laborer`), `Necromancer` own position/hp/state; `*Token` nodes only draw. Never put
  timers or state on a token — that drift has been unwound twice already.
- `ResourceNode` is a Node2D on purpose (its position/appearance IS its gameplay content).
- **Content is data-driven:** `data/*.json` (races, buildings, events, missions, recruitment,
  world_map, world_sites). New content = JSON edit; new *effect types* = extend the relevant system.
- Combat: `Combat.gd` is THE damage formula (knows nothing); `CombatSystem.gd` is policy.
  Duck-typed contracts: `get_inspect_data()` (inspectables), Combatant methods (fighters).
- Stats stay minimal: Might/Guile/Influence/Loyalty + 3 labor skills. Resist stat bloat.
- Indirect control is a pillar: no unit orders. The exceptions are the Necromancer (driven
  directly) and Command Undead (binds the dead as a class, via `alignment: "Undead"`).
- The Necromancer is NOT a Laborer and not in any labor pool — keep the exclusion structural.
- Timers must be delta-accumulators or SceneTreeTimers so `Engine.time_scale` (debug 1x/10x/60x)
  scales everything together. Never `Time.get_ticks_msec()` for gameplay.

## Graphics rules

`docs/art/SPRITE_SPEC.md` is the ONE authority (256px canvas, y=224 baseline, body families).
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
                           EconomyTab, EventPanelUI, InspectorActions, TokenLayer
scripts/autoload/          GameState, EventBus, BuildingCatalog, RaceCatalog (load-once JSON catalogs)
scripts/settlement/        SettlementGrid, Building, WorkerSystem (trip loop), Laborer/Worker,
                           MoraleSystem, HousePlanner/HouseStyle, ResourceField/ResourceNode, tokens
scripts/villain/           Necromancer (data), VillainController (WASD+camera follow)
scripts/combat/            Combat (formula), Engagement, CombatSystem (policy), UndeadCommand, RallyPoint
scripts/world/             WorldMap (one TileMapLayer), FogOfWar (one 144×144 image), DayNightCycle,
                           WorldSite(s), Patrol, Wolf, Roaming, TravelLog
scripts/bounty|events|missions|threat/   Stage-4 systems, built but mostly unsurfaced in UI
data/                      the JSON content (races/buildings/events/missions/recruitment/world_*)
tools/                     generators + verification harnesses (KEEP: they re-derive every number)
docs/design|art|prompts|history/         specs, art rules, prompt libraries, dated dev narrative
assets/official|placeholder|vendor/      see Graphics rules
```

## Verification harnesses (run after touching the related system)

- `godot --headless --path . --import` — required after adding any `class_name`
- headless boot: `godot --headless --path . --quit-after 200` — clean start check
- `tools/check_sprite_scales.tscn` — 40 assertions: everything draws at its claimed size
- `tools/measure_travel.tscn` — travel bands vs WORLD_MAP_PLAN §3 (after speed/layout changes)
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
`docs/history/YYYY-MM-DD-topic.md` and this file gets at most a one-line pointer. Budget ~8KB.
