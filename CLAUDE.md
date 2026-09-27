# Warlords (working title: Undead Empire Prototype)

Villain-power-fantasy roguelite settlement builder (Against the Storm / RimWorld lineage, inverted:
you're the villain). Godot 4.7.1, GDScript, GL Compatibility. Local-only, no runtime deps; the
godot_mcp dev bridge's three autoloads are freed at startup in release builds.
Repo: https://github.com/OverSeerFulgrim/Warlords (branch `main`).

**Orientation only, budget ~10KB.** Design lives in `docs/design/`, graphics rules in
`docs/art/SPRITE_SPEC.md`, what the code actually does in `docs/history/` (dated files, indexed in
its `README.md` — read the one for the system you touch). Session write-ups go there, NEVER here.

## Current phase

Roguelite rework (`docs/design/ROGUELITE_REWORK.md` §13, §17) + `docs/design/LIVING_WORLD_SPEC.md`
(§14–15). **R1, R2 and LIVING_WORLD L0–L2 built**: death ends the run, endings keep items (stash,
carry-in, the Lair), the living village, the stance, the Guild, witnesses/standing, blueprints, the
roadside opening. **Next: a human playtest, then L3** (prisoners → Summon Ghoul). Where each
landed: the newest rows of `docs/history/README.md`. The win condition is still the legacy
placeholder. Climate: not implemented. One villain class for now — but **no system may assume
exactly one villain on the map** (per-villain state on the villain, never in an autoload/global).

## Architecture conventions (the load-bearing ones)

- `GameState` (autoload) — a **façade over `player_settlement`** (a `Settlement`; ruling 13): every
  settlement owns its stockpile; the village has its own.
  `GameState.reputation` is legacy — never extend it (R3: five axes on the villain). Threat stays
  global. `EventBus` (autoload) — ALL cross-system communication is signals here.
- **Sim state lives on data objects (RefCounted); tokens are pure views.** `Worker`/`Follower`
  (extend `Laborer`), `Necromancer` own position/hp/state; `*Token` nodes only draw — never put
  timers or state on a token. `ResourceNode` is a Node2D on purpose.
- **Content is data-driven** (`data/*.json`): new content = JSON edit; new *effect types* = extend
  the system.
- `Combat.gd` is THE damage formula (knows nothing); `CombatSystem.gd` is policy. Duck-typed
  contracts: `get_inspect_data()` (inspectables), Combatant methods (fighters).
- Stats: nine attributes, `docs/design/COMBAT_SPEC.md` §2 (Might is gone). `stat_rework_roster.xlsx`
  is the editing surface; `tools/export_roster.gd` derives `data/races.json`. Carry = Endurance
  (his = item slots; resources take none, 2026-09-26), max_hp = 8 + End×2. Walk speed is a
  **per-race constant** in `races.json`, derived from Speed at export only: a recruit's rolled Speed never changes it, and the Necromancer moves at
  `MOVE_SPEED_CELLS` (1.0), not his row. Effective skill = skill + floor((attr−5)/2), clamped
  1–10, **computed at use time, never stored**. Attack profile falls out of highest Str/Dex/Int —
  a unit needing a hand-written profile means the rule is wrong. Creatures and villains use the
  same nine.
- **No unit orders.** Exceptions: the Necromancer (driven directly) and Command Undead (binds the
  dead as a class, via `alignment: "Undead"`). His casting is proximity-engaged — 26px engage,
  5-cell reach, no attack button, never rooted (NECROMANCER_SPEC §3). The escort is that spell
  anchored to him: `RallyPoint.follow`, all the dead, stance as policy (ESCORT_SPEC §3). He is NOT
  a Laborer — keep that structural.
- Timers are delta-accumulators or SceneTreeTimers so `Engine.time_scale` scales everything. Never
  `Time.get_ticks_msec()` for gameplay.

## Graphics rules

`SPRITE_SPEC.md` is the ONE authority for characters and buildings; terrain sheets (4x4 in
`assets/official/terrain/`) are outside it — `TERRAIN_SPEC.md` §2; read one with `dump_atlas.gd`.
Sizes are **content heights** via `Anchoring.scale_for_content_height()` — never texture width,
never `CELL_SIZE`. `Anchoring.foot()` / `cell_base()` anchor; click radii =
`drawn_content_size()` × 0.45. Exceptions: the wolf is width-scaled; `WorldSite`/`Patrol` keep
canvas-width math until `world_sites.json` is re-tuned. `assets/official/` is commissioned
(`_originals/` untouched), `placeholder/` stand-ins (delete in the replacing commit), `vendor/` cold
storage. New art is named per SPRITE_SPEC and wired in the same commit. Never at repo root.

## File map

```
scripts/Main.gd      wiring root + input arbitration (placement > demolish > rally > inspect)
scripts/             Controls (InputMap, physical keys), Anchoring, GameCamera
scripts/autoload/    GameState, EventBus, Building/Race/LootCatalog (LootCatalog owns THE loot roll)
scripts/run/         RunLifecycle (endings, items kept, carry-in, XP, Second Wake), MetaProfile
                     (XP, stash, blueprints)
scripts/ui/          InspectionPanel, Minimap, HudTopBar, BuildMenu, EconomyTab, EventPanelUI,
                     InspectorActions, TokenLayer, CombatFeedback, DebugSiteOverlay (F3),
                     RunSummary, PauseMenu, TitleScreen, KeepItemsDialog, LairScreen, ItemsDialog;
                     the HUD: HudStyle (palette), DeadRoster, ActionBar, HudWindow, LogTicker, MapScreen
scripts/settlement/  Settlement, SettlementGrid, Building, WorkerSystem (trip loop), Laborer/Worker,
                     MoraleSystem, HousePlanner/HouseStyle, ResourceField/ResourceNode, tokens
scripts/villain/     Necromancer (data), VillainController, SortieSystem (capacity/deposit/death)
scripts/combat/      Combat, Engagement, CombatSystem, UndeadCommand, RallyPoint
scripts/world/       WorldMap (one TileMapLayer + one canopy MultiMesh), FogOfWar, DayNightCycle,
                     WorldSite(s), Raven/RavenMarker, SiteGuardian, Patrol, Wolf, Roaming, TravelLog
scripts/world/village/  Village, Villager, VillageBuilding, VillageLabor (data/village.json)
scripts/world/guild/    Guild (board, standing, pay), Witnesses (runners) (data/guild.json)
scripts/bounty|events|missions|threat/  Stage-4 systems, built, mostly unsurfaced
data/                JSON content, incl. loot_tables, relics, site_choices, progression, followers
tools/               generators + harnesses (KEEP). make_world_map.gd GENERATES the layout
                     (TERRAIN_SPEC §8: re-run, commit the JSON); export_roster.gd; dump_atlas.gd
```

## Verification harnesses (`godot --headless --path . res://tools/<name>.tscn`)

`--import` after adding any `class_name`; `--quit-after 200` is the boot check (it sits paused on
the title — expected). Assertion counts as of 2026-09-26:
- `measure_travel` — **the gate on any map change**: every row back in band; walk speed is no knob
- `verify_terrain` 278 — sheets, atlas, masks, the generated layout (roads, Band 4 clearance,
  crossings, reachability, dead ends lead to loot, clearings, canopy budget)
- `verify_loot_tables` 533 — every table ×10k vs LOOT_SITES_SPEC §5, relics, remainders, dusk gate
- `verify_stats` 505 — nine attributes vs the workbook, profiles, hp/carry, no identifier named
  Might (after ANY roster/stat change)
- `check_sprite_scales` 122 — everything draws at its claimed size; looted sprites share a canvas
- `verify_sortie` 79 — item slots (resources take none), gear worn vs banked, deposit, caches, death
- `verify_villain_combat` 65 — aura band edge, engage 26px / cast 5 cells, regen, 1,000-fight bands
- `verify_escort` 58 — undead-only binding, labour pool in/out, a grave-raised skeleton joining,
  both stances, the interpose
- `check_fog_and_minimap` 50 — fog sources (him 7 cells, units 3), minimap dots and clicks
- `verify_run_lifecycle` 49 — XP/level formulas (PROGRESSION.md), profile never written by a
  harness, owner checks, Second Wake, death ending the run, the run-end screen
- `verify_raven` 39 — the five honesty conditions over 1,000 dawns, cap, silence, fog untouched
- `verify_guild` 69 — roadside spawn, run one builds nothing, blueprints from sites, the board from world state, pay into hands, standing
  drops only on a runner's arrival, the keeper, Known shuts doors, the Altar blueprint
- `verify_village` 56 — the GameState façade, integrity, meals, restaffing, alarm, stance, bodies
- `verify_endings` 33 — what each ending keeps, carry slots 1→3, carry-in lost on death, the Lair
- `verify_inspect` 17 — every clickable's `get_inspect_data()` answers (guardians in every state)
- `verify_hud` 42 — the HUD shows nothing until its mechanic does, windows/keys, map names only the seen
- `verify_demo_shell` 44 — physical keys, pause/Esc, Surrender's confirm, title, debug-only tools
- `verify_combat_feedback` 31 — one damage number per landed swing, the pool cap, no leak
- `verify_raise_dead` 26 — no free skeleton, Raise Dead for bones, a grave's corpse as a free Worker
- `smoke_site_actions` 26 — presses the site buttons as buttons (a human mouse is the last word)
- `capture_settlement.gd` — seeded windowed screenshot for before/after

## Gotchas (details in docs/history/)

- F3 overlay (`DebugSiteOverlay`): debug builds only, read-only — it must never reveal, write fog
  or set a `discovered` flag, or it perjures the Raven.
- He wakes at `Main.ROADSIDE_SPAWN_CELL`, not the Throne; a harness that needs him home places
  him at `_throne_world_centre()`.
- The HUD floats: no bottom bar. A new HUD piece must appear the first time its mechanic does
  (`verify_hud`); style it with `HudStyle`.
- The lair aura is a POSITION: `CombatSystem.aura_protects_villain()` reads `is_in_lair_band()`.
- A global signal carrying a villain needs an owner check (`villain_died` fires for every villain).
- Never read a raw keycode: add a row to `Controls.ACTIONS`.
- Harness runs never write `user://meta_profile.json` (only when Main is the running scene).
- godot-mcp simulated input never reaches the game; only `click_button_by_text` works. Real
  mouse/keyboard QA needs a human. The debug window may eat its first click.
- Run harnesses as scenes (`-s` compiles before autoloads); `load()` in `_init()` hangs headless;
  the headless viewport is 64×64 — set `root.size` first.
- A handler missing a signal's args connects fine and fails silently. Lambdas capture locals by
  value. `_set` is an Object virtual. `project.godot` keys are section-relative.
  `get_process_delta_time()` is already time-scaled.
- Some `Icons/Food/` files are `*.png.png`. Keep repo paths short (MAX_PATH). Y-sort opt-outs by
  z_index are deliberate (Necromancer 5, wolf 6, fog 100).

## Maintaining this file

Orientation only. More than ~10 lines about a pass goes in `docs/history/YYYY-MM-topic.md` (plus a
row in its `README.md`); this file gets at most a one-line pointer. Budget ~10KB
(raised from 8KB on 2026-09-26): accuracy first, then size.
