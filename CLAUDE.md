# Undead Empire Prototype — Project Notes

Working codename only — no title chosen yet. This file orients any future session (Claude or human) picking this project back up.

## What this is

A villain-power-fantasy roguelite settlement builder, in the lineage of *Against the Storm* / *RimWorld*, inverted: the player is the reason "good" nations are afraid, not the plucky survivors. Full design context lives in `villain_settlement_builder_design_doc.docx` one level up from this folder (in `outputs/`) — that document is the source of truth for anything not covered here. This file is about the *code*, not the design.

## Current phase

**Phase 1 (MVP), narrowed further to Stages 1–3 of `GAME_OUTLINE.md` — see "Foundation reset" below, which supersedes the Core Loop line in this list.** Scope is deliberately narrow:

- One villain class: **Undead Empire**
- Climate: deliberately **not implemented yet** — the placeholder "Frozen Wastes" label/art is still in the code (`tile_ground_frozen.png`, log message in `Main.gd`) but per an explicit user scope call, climate mechanics are a later feature. Narratively the settlement is currently framed as a cold, remote, forested/mountainous hideout (Alps/Alaska-ish — a necromancer needs somewhere to hide) rather than a barren wasteland, which is why Wood exists as a resource; nothing in code enforces this yet, it's just the intended flavor for whenever climate *does* get built.
- Core Loop: settlement grid + building/housing system + a Worker-driven resource economy, Bounty Board (indirect control), Reputation/Threat escalation ladder, a random event pool, and a hand-picked-party mission system
- Win condition: **both** — survive the High-Threat Crusade climax **and** reach a Power threshold (per user's answer in design discussion) — **superseded by the roguelite rework** (below): the win becomes taking the human lord's manor, with Power surviving as an escalation input only. The code still implements the old "both" check; changing it is rework stage R4.

**Important:** the design doc barely specifies the settlement-building/economy layer at all — see its Core Loop section, which only says "establish a settlement" and "carry forward buildings" as meta-progression, nothing more. The building/housing system and the Worker/resource-gathering economy (this section) were designed live in conversation with the user, not transcribed from the doc. If the doc and the code ever disagree on this specific layer, the code (and this file) is the more current source of truth, not the doc.

Multi-settlement, trade, alliances, and climate are explicitly **out of scope** until this loop is proven — see design doc Section 11.

**The roguelite rework (`ROGUELITE_REWORK.md`, 2026-08) is the agreed direction beyond Stages 1–3** and supersedes GAME_OUTLINE Stages 4–5 and the timed-recruit-event model. Headlines: one region = one run (Slay-the-Spire structure — death ends the run, XP/unlocks/stash persist and add *variety, never power*); the Necromancer becomes a directly controlled, killable unit exploring a 144×144 world map (the one sanctioned exception to indirect control — followers stay uncommandable); recruitment gates on a five-axis reputation earned by deeds, not on a timer; victory is taking the human lord's manor; a between-runs Lair hub holds the stash, trophies, and chronicle. The Stage 1–3 settlement foundation is unchanged and is a prerequisite — it becomes the in-run base layer. Design constraint effective immediately: **no system may assume exactly one villain on the map** (villain state on per-villain objects, not global singletons) — this is the whole present-day cost of keeping the second class and multiplayer possible. Build order is `ROGUELITE_REWORK.md` §13 (R1–R6). **R1's first task is done** — the Necromancer is split into a data object + view, is driven with WASD, is followed by the camera, and is killable; see "The villain splits" below. Nothing else from the rework is built. The world-map spec lives in `Warlords_World_Map_Scale_and_Exploration_Plan.docx` (user-authored), adopted with the three amendments in the rework doc's §4.

## Engine & tooling

- **Godot 4.7.1**, GDScript, GL Compatibility renderer (safest for a wide range of hardware during prototyping) -- `project.godot`'s `config/features` is the source of truth if this ever drifts again
- Everything runs **local-only** — no cloud services, no account requirements, no external dependencies beyond the Godot editor itself
- The [GDAI-alternative] **godot-mcp** plugin (`addons/godot_mcp/`, MIT, by mkdevkit) is installed and enabled, connecting this project to a Claude Code session over MCP for live editor introspection/control -- see the three `MCP*Bridge` autoloads in `project.godot`. Requires Godot open with the plugin enabled for the connection to work.
- **The project now lives at `C:\Users\sjodz\Warlords`, under git, pushed to https://github.com/OverSeerFulgrim/Warlords** (branch `main`). It used to sit in an app-managed cache path (`AppData\Local\Packages\...\LocalCache\...`); that copy still exists but is **stale — do not edit it**.
  - The move wasn't optional. The old path was 249 characters, so `.git/config` landed at 261 and blew past Windows' 260-char `MAX_PATH`: `git init` created `.git/` but every subsequent command reported "not a git repository" because it couldn't read the config. `core.longpaths` doesn't rescue this — git reads that config *before* it can apply the setting. If the project ever moves again, keep the path short.
  - **`addons/ziva_agent/` is gitignored**: ~1.4 GB of prebuilt per-platform CEF/`zivacode` binaries, seven of them over GitHub's hard 100 MB file limit, so the repo cannot be pushed with them tracked. It is also not listed in `project.godot`'s `editor_plugins/enabled`, so nothing in the game depends on it — reinstall locally if needed. `addons/godot_mcp/` (255 KB, enabled) *is* committed. The tracked tree is ~28 MB.
  - `.godot/` is ignored (editor cache, regenerates). `*.import` files are **deliberately committed** — they carry each asset's import settings and stable resource UID, and dropping them breaks scene/script references on a fresh clone.

## Known constraint (important)

This project was originally scaffolded by Claude in a sandboxed environment **without the ability to run the Godot engine itself** (the sandbox's network access couldn't reach the Godot binary download), so early passes were hand-written/reviewed but not runtime-tested. That's since been superseded: the project now runs in a local Godot 4.7.1 install, connected live via `godot-mcp` (see below), and has been through multiple rounds of both MCP-driven and real-mouse-input QA. If something doesn't parse, it's most likely a small typo rather than a structural design problem — the architecture itself (autoloads, signal bus, data-driven events/missions via JSON) is standard, well-trodden Godot practice.

**godot-mcp's simulated input tools don't reach the running game.** `simulate_mouse_click`/`simulate_key`/`simulate_mouse_move` never fire `_unhandled_input` in the actual game process — confirmed via a clean diagnostic (an Esc-cancel test that silently didn't fire). Only `click_button_by_text` (which presses a Control button programmatically, bypassing real input entirely) actually works through MCP. Anything that depends on real mouse/keyboard input reaching `_unhandled_input` — click-to-place, Esc-cancel, right-drag pan, clicking the Keep — has to be verified by a human with the actual mouse in the actual running window. This has now been done at least once (click-to-place, Esc-cancel, right-drag pan, and Keep-click all confirmed working with real input) — if a fresh session needs to re-verify after further changes, don't trust an MCP-only pass to have covered it.

**One gotcha hit during that verification, worth remembering:** the floating debug game window sometimes eats its first real click just to take OS focus (normal Windows window-activation behavior, not a bug) — if a click seems to do nothing right after the window appears/reloads, click into the window once first, then try again before assuming something's broken.

## Architecture conventions

- **`GameState` (autoload)**: single source of truth for resources, reputation, threat, power, followers. Nothing else should hold duplicate state.
- **`EventBus` (autoload)**: all cross-system communication goes through signals here rather than nodes holding direct references to each other. If you're about to add a new dependency between two systems, add a signal instead.
- **Followers and Workers are plain `RefCounted` objects, not `Node`s.** They're data (name, species, traits, stats) with behavior, not scene-tree citizens. Keeps "hundreds of followers" cheap. Only give one a visual `Node` representation if/when it needs to be seen on screen.
- **A unit's simulation state lives on the RefCounted, and its token is a pure view.** `Worker.position` is the worker's real map position — `WorkerToken` reads it and draws there, and owns no state of its own. When a token starts running its own timers or animation state machine, the visual and the simulation drift apart; that already happened once here (see "Physical gathering") and unwinding it was most of a pass. `ResourceNode` is a `Node2D` and not a RefCounted precisely because its position and appearance *are* its gameplay content.
- **Events, missions, buildings, and races are data-driven** (`data/events.json`, `data/missions.json`, `data/buildings.json`, `data/races.json`), not hardcoded per-entry in GDScript. Add new content by editing JSON, not by writing new script branches, unless the effect type itself is new (in which case extend `_apply_effects` in `EventSystem.gd` / `MissionSystem.gd`, or the relevant handling in `Building.gd` / `BuildingCatalog.gd`).
- **`Main.gd` builds its debug UI entirely in code** (no hand-laid-out `.tscn` UI tree). This was a deliberate choice to reduce the risk of an unverifiable hand-authored scene file — it is *not* meant to be the final UI. Replace it with a proper scene-based UI once the loop is validated and you're iterating in the actual editor.
- Stats are deliberately minimal: **Might / Guile / Influence / Loyalty**, per the design doc's Section 5 recommendation. Resist adding more without a specific gameplay reason — stat bloat is the fastest way to blow this project's scope.

### Buildings, housing, and the main building (added after Milestone 5)

- **`BuildingCatalog` (autoload)**: loads `data/buildings.json` once, same pattern as `EventSystem`/`MissionSystem` loading their own JSON. `Building` instances are constructed via `Building.make_from_data(id, data)` -- there is no per-building hardcoded factory anymore.
- **Housing is a hard gate.** Each `category: "housing"` entry in `buildings.json` has a `housing_species`. `EventSystem._recruit()` refuses to add a follower of that species until `SettlementGrid.has_housing_for(species)` is true. Species with no housing entry defined (e.g. "Dark Elf") are treated as ungated on purpose, so Phase-2 content doesn't silently break. **Superseded by the foundation reset** (see below): the housing buildings are now `"locked": true`, the 3 starting followers this used to exempt are gone, and this whole gate is slated to be replaced by a Barracks-capacity check.
- **Build menu is player-driven**, not auto-placed. `Main.gd`'s "Build..." button opens a menu of `BuildingCatalog.buildable_ids(settlement)` (excludes `category: "main"` and anything whose `requires` prerequisite isn't built yet — this is how Workshop tech-gates Blacksmith/Barracks). Selecting an entry enters placement mode (`_pending_building_id`); a left-click on an empty grid cell spends the resource cost and places it (`Main._try_place_pending`). Esc cancels. **Camera panning moved from left-drag to right-drag** (`GameCamera.gd`) specifically to free up left-click for this.
- **`throne_of_bones` (category `"main"`)** is the player's home: seeded once in `_seed_starting_state()`, not buildable, not removable (`SettlementGrid.remove_building` refuses if `building.is_main_building`). It has `hp`/`max_hp`. `ThreatSystem._resolve_crusade()` now damages it based on the Power shortfall instead of a flat win/lose check on Power alone — losing the main building (`hp <= 0`) is the actual fail state; surviving still also requires hitting `POWER_WIN_THRESHOLD` per the existing "both" win condition in `GameState`.
- **Blacksmith and Barracks are action buttons, not systems.** `Main._forge_equipment()` / `Main._train_followers()` check `settlement.has_building(id)` and log a rejection if the building isn't there yet, rather than disabling/hiding the buttons reactively — matches the existing log-driven feedback pattern (e.g. `Dispatch Mission`'s idle-follower check). **Both buttons are now unsurfaced** by the foundation reset (see below); the functions themselves are untouched. The Barracks' own redefinition (single, upgradeable, capacity 5) is FOUNDATION_SPEC §9 and not built yet.

### Worker economy: the original flat-tick version (historical — see "Physical gathering" below)

> **Superseded.** The flat `gather_interval` tick, the per-worker `gather_target` enum, and the two decorative map markers described here were all replaced by the real trip loop. Kept because the *design calls* in it still hold and get cited later; the mechanics don't. Skip to "Physical gathering" for what the code does now.

- **`Worker` is deliberately a separate class from `Follower`**, not a second purpose for the same one. Workers (`scripts/settlement/Worker.gd`, RefCounted like Follower) can't go on bounties or missions. This was an explicit design call: Followers stay the roster/story unit, Workers are pure economy labor. Don't merge them without re-confirming that call. **(Still true.)**
- ~~**`WorkerSystem`** owns `workers: Array` and ticks every `gather_interval` (4s), adding 1 of whatever resource each assigned Worker is gathering.~~ Replaced by the trip loop. `recruit_worker()` still costs 5 Bones (`WorkerSystem.RECRUIT_COST`), and the free starting Worker still bypasses it via `add_worker()`. **(Still true.)**
- **Resource split:** Wood/Stone/Bones/Food are the four "mundane" resources; Workers gather all four and buildings mostly cost them to construct. **Dark Essence stays separate** — a ritual/magic resource, never something a Worker gathers. Bone Pile still passively ticks Bones on its own timer — building tick and Worker gather stack rather than replace each other. **(Still true.)**
- ~~**UI is one button per Worker**: click cycles Idle → Wood → Stone → Bones.~~ Replaced by the global priority list.
- **Starting economy numbers** (tune here if rebalancing): `GameState` starts with `wood=8, stone=5, bones=10, food=5, dark_essence=0` — FOUNDATION_SPEC §10's table. A Worker costs 5 Bones, so the starting Bones affords exactly 2 extra recruits beyond the 1 free one (3 total) before any gathering happens; Wood/Stone deliberately don't cover a building outright, which is the Stage-1→2 gate doing its job.

### The "small test space": the Keep-click menu (added after the Worker economy)

Per an explicit user sequencing call — prove material gathering first, then named-character recruitment, then the bounty board — this pass added visible presence to the abstract Wood/Stone economy above. Its resource-marker and WorkerToken-glide parts are **superseded by "Physical gathering" below**; the Keep menu is not.

- **`Main._sync_worker_tokens()`** reconciles `worker_tokens` against `worker_system.workers` on `worker_count_changed`, same spawn/despawn pattern as `_sync_follower_tokens()`. Worker tokens reuse the Skeleton Follower portrait (`SPECIES_SPRITES["Skeleton"]`) scaled smaller (32px vs Follower tokens' size) as a generic "undead laborer" look — deliberate, since Workers are meant to read as interchangeable, not individual.
- **Clicking the main building opens a "Keep" menu** (`Main._toggle_keep_menu()` / `_populate_keep_menu()`), handled inside the existing `_unhandled_input()` alongside build-placement clicks (checked only when *not* in placement mode, so it can't fire while you're placing a building). Currently offers the same "Recruit Worker (5 Bones)" action as the top-bar button (two paths to the same call, `Main._recruit_worker()`), plus a greyed "Upgrades — coming soon" placeholder label per the "possibly get upgrades down the road" design note. No new functionality yet, just the entry point.

### Foundation reset: back to Stages 1–3 (added after the "small test space" pass)

The design docs got ahead of the code: `GAME_OUTLINE.md` (v4) restructured the run into five stages and declared **Stages 1–3 only** (collect → build → recruit & settle) the current roadmap focus, with `FOUNDATION_SPEC.md` supplying the numbers and `RACES.md` the roster. But the code was still starting the player mid-Stage-4 — three free followers, a Dark Altar, and a full row of bounty/mission/training buttons — so nothing about the actual first ten minutes matched the design's "earn it in stages" pillar. This pass pulled the code back to the documented Stage-0 baseline. **It is a scope reduction, not a feature removal: nothing was deleted, only unsurfaced or reset.**

- **`data/races.json` (new)** — the `RACES.md` roster as data: 16 recruitable/player-made races plus the Human Peasant reference entry (`recruitable: false` — it's the 1–10 measuring stick, per FOUNDATION_SPEC §1). Each entry carries category, alignment, rarity, the 4 character stats, the 3 labor skills (woodcutting/mining/foraging — new, they drive *work speed*, not permissions), `walk_speed`, `food_per_meal`, `housing_style`, and a `rivalries` list of race ids. The Good↔Evil blanket rivalry is deliberately *not* listed per-race — it's derivable from `alignment`. **Nothing loads this file yet.** It's data ahead of its consumers, on purpose: the recruit generator (FOUNDATION_SPEC §3's `baseline + d3 − d3` roll), the food/morale tick, and the fund-a-house placement rules all read from it when they get built. Whoever writes the first consumer should add a `RaceCatalog` autoload next to `BuildingCatalog`, same load-once pattern. Note it does *not* replace `data/followers.json` yet — that's still what `EventSystem._recruit()` reads (outline gap #5).
- **Food is a fourth mundane resource** in `GameState` (`add_resource`/`can_afford`/`spend_resource`), shown in the top bar. Wood/Stone/Bones/Food are the mundane four; **Dark Essence stays separate** and is now the *last* item in the bar. Food currently has no producer and no consumer — it sits at the starting 5 until the day/night meal tick (FOUNDATION_SPEC §8) and a food-gathering source exist. Only living recruits eat; undead labor never does.
- **Starting state reset to FOUNDATION_SPEC §10:** Throne of Bones only, 1 Skeleton Worker, `wood=8 stone=5 bones=10 food=5 dark_essence=0`, **zero followers**. The seeded Bone Pile and Dark Altar are gone from `_seed_starting_state()` — the Bone Pile is now the player's first build rather than a gift, which is what makes the Stage-1→2 gate ("afford your first building") mean anything. Dark Essence starts at 0 because harvest bounties, its only legitimate source, are locked. Grix/Morra/Vash are deleted (outline gap #13). The starting worker was also renamed *Zombie Laborer* → *Skeleton Worker* to match the race name in `races.json`.
- **Stage-4 systems are hard-locked in the UI, not in code.** Post Harvest/Reanimation Bounty, Dispatch Mission, Forge Equipment, and Train Followers are no longer built as buttons. `BountyBoard`, `MissionSystem`, `Bounty`, and `Main._forge_equipment()`/`_train_followers()`/`_dispatch_random_mission()` are **all still present, wired, and unchanged** — just unreferenced by the UI, so re-surfacing each is one `_add_button()` line. The Bounty category tab stays visible with a greyed locked placeholder (`_add_locked_placeholder()`) rather than disappearing, matching the "visible promise of the roadmap" treatment FOUNDATION_SPEC §9 asks for on the Barracks Upgrade button.
- **Build menu is down to Bone Pile + the Workshop line** (Workshop → Blacksmith/Barracks). The Dark Altar and the five old per-species housing buildings (`bone_crypt`, `charnel_pit`, `haunted_spire`, `war_camp`, `burrow_warren`) are marked **`"locked": true`** in `buildings.json` and filtered by `BuildingCatalog.buildable_ids()`. **Their entries are intentionally not deleted** — per-species housing is superseded by the Barracks-intake + fund-a-house model (FOUNDATION_SPEC §9, `RACES.md` housing styles), but the entries are the reference for what replaces them, and `EventSystem`'s housing gate still reads the same `housing_species` field. `locked` only hides from the player: `get_building()`/`all_ids()` still return locked entries, so seeding and already-placed instances are unaffected.
- **Consequence worth knowing:** because the housing entries still exist in the catalog, `EventSystem._species_requires_housing()` still reports Skeleton/Ghoul/Wraith/Orc/Goblin as housing-gated, and their housing can no longer be built — so those recruits would now always fizzle. This is currently inert (`EventSystem.EVENTS_ENABLED == false`), but **whoever re-enables events must replace that gate with the Barracks-capacity check first** (outline gap #2), or recruitment will silently do nothing.

Verified by a headless run (`godot --headless --path . --quit-after 200`): clean start, no warnings, zero followers, one worker, `Wood: 8 Stone: 5 Bones: 10 Food: 5 Dark Essence: 0` in the bar, build row = Bone Pile + Workshop (+ Demolish), and Blacksmith/Barracks still appearing once a Workshop is placed.

### Physical gathering: the trip loop, resource nodes, and the priority list (added after the foundation reset)

**The biggest architecture change since the building system.** The worker economy used to be a flat timer: every 4 seconds, each worker added +1 of whatever resource they were individually assigned, regardless of distance, skill, or whether the map had any of it left. Worker position was decorative — `WorkerToken` ran a Tween glide loop tuned to *look* like it matched the tick, and its own header admitted the two were not the same clock. This pass makes gathering physical, and collapses those two clocks into one.

#### The trip loop (`WorkerSystem.gd`)

Each worker runs a real round trip, per FOUNDATION_SPEC §6:

```
pick target (priority list) → walk there → gather until carry-full or node empty
    → walk home → deposit → repeat
```

`Worker.TripStage` is `IDLE / WALK_TO_NODE / GATHERING / WALK_HOME`. **Resources only enter `GameState` at the deposit step** — a worker mid-trip is holding value that isn't banked yet. Three consequences, all intended:

- **Distance is a cost.** Walk speed is `walk_speed × CELL_SIZE` px/sec, so FOUNDATION_SPEC §4's "walk speed 1.0 = 1 grid cell per second" is literal. A Skeleton at 0.9 covers 57.6 px/s. A far forest is genuinely slower than a near one.
- **Skill is visible as speed, not permission.** Per-unit gather time is `4.0s × 5 / skill` (`ResourceNode.action_time_for_skill`). Skill 5 (the human peasant) lands on exactly 4s — deliberately the old flat tick's rate, so early-game pacing survived the rewrite. A Skeleton's Woodcutting 3 takes ~6.7s per log.
- **Carry capacity = Might** sets trip length. A Might-4 skeleton hauls 4 units per trip. The **one exception is a deer**: `yield_per_action` 8, taken in a single action and hauled home whole, because FOUNDATION_SPEC §5 says "whole deer on kill" and a Might-4 worker could otherwise never bring one home at all.

`_step_toward()` re-reads the target node's `position` every frame rather than caching a destination — that's the entire implementation of chasing a roaming deer. There is no separate pursuit code.

#### Position moved from the token to the worker

`Worker.position` is now the single source of truth for both the economy and what's on screen. `WorkerToken` is a **pure view**: it reads `worker.position` and draws there, plus a `+N wood` carry tag and a sprite flip. It decides nothing, owns no state machine, and runs no Tweens. The old honesty note about the animation and the economy being different clocks is gone from the codebase because the situation it described no longer exists — there is only one clock now. The RefCounted/Node2D split is unchanged and still the point; what moved is *authority*, not cost.

#### Resource nodes (`ResourceNode.gd`, `ResourceField.gd`)

`ResourceNode` is a Node2D — unlike Worker/Follower — because a node's whole purpose is to occupy a spot you walk to and to visibly change as it's worked. Each has `kind` (the GameState resource string), `node_type` (flavor/subtype), `remaining`/`capacity`, `yield_per_action`, `regrows_per_dawn`, and `skill_key` (which labor skill drives its speed). Static factories implement FOUNDATION_SPEC §5's table: `make_tree` (10 wood), `make_stone_deposit` (250), `make_berry_grove` (40 cap, +8/dawn), `make_carcass` (5 bones), `make_grave` (12 bones), `make_deer` (8 food).

Note `skill_key` is **not** derivable from `kind`: bones come from both carcasses (Foraging — finding them in the underbrush) and graves (Mining — digging). That's why the skill lives on the node.

**Depletion is visible, not just numeric** — FOUNDATION_SPEC §11.1 makes "trees visibly deplete" a foundation exit criterion. A chopped-out tree swaps to a stump sprite; an emptied grave dims to a spent marker; nodes without distinct empty-state art fade toward transparent in proportion to `remaining/capacity` (floored at 0.45 alpha so a nearly-empty node stays findable).

`ResourceField` owns every node, seeds the map (Forest of 20 trees + 4 carcasses east, Stone Deposit south, Berry Grove west, 2 Graves — one road-side, one past the forest — and 2 starting deer), handles dawn upkeep, and answers `find_best_node(kind, from_pos)`. Fixed positions; procgen is still out of scope. **Nothing reaches into `ResourceField.nodes` directly** — go through the query methods so the crowding and depletion rules stay in one place.

`find_best_node` scores by `distance + claims × CROWDING_PENALTY_PX` (200px, ~3 cells). `claims` is a **soft crowding hint, not a lock**: it spreads three workers across three trees instead of stacking them on the nearest one, but it will still hand out an already-claimed node when that's all there is — which is exactly what has to happen for one Stone Deposit shared by the whole workforce. Food routing needs no special case: berry groves and deer are both `kind: "food"`, so "berries or deer, whichever is nearest-available" is just this function running over a mixed set.

#### The priority list (replaces per-worker assignment)

Global and player-set, per GAME_OUTLINE Stage 1 — there are no per-worker orders any more. `WorkerSystem.priorities` is a ranked `Array` of `{kind, threshold}`, defaulting to Wood 30 / Stone 20 / Food 20 / Bones 15. **The fall-through rule:** workers serve the highest-ranked resource whose stock is *below* its threshold; at or above it that entry is satisfied and they fall through to the next, returning the moment spending dips it back under.

`_pick_target_for()` checks **two** conditions per entry, and the second matters as much as the first: under-threshold **and** still available on the map. Without the availability check, a forest chopped to stumps would park every worker on "wood" forever while stone and food sat unharvested. Running out has to fall through exactly like being satisfied does.

Reordering or editing a threshold calls `_rethink_all()`, which drops trips only for workers still in `WALK_TO_NODE`. Workers already gathering or hauling are **deliberately left alone** — abandoning a half-dug grave or dumping a carried load to chase a reshuffled list wastes work the player already paid for and reads as a bug.

UI is one row per resource in the Economy tab (`Main._build_priority_rows`): `[^][v] Wood  stop at [30]  Working`. The threshold uses a real `SpinBox` rather than the codebase's usual +/- button pair — that convention is for small fixed choice sets, and a threshold is an arbitrary number. Rows are rebuilt wholesale on `EventBus.priorities_changed`; the Working/Satisfied/None-left labels and the workforce summary are polled from `Main._process()` instead, because worker state changes continuously and any signal for it would fire every frame anyway.

#### Worker stats now come from `races.json`

`RaceCatalog` (new autoload, same load-once pattern as `BuildingCatalog`) is the first consumer of the `races.json` the previous pass added. `Worker` reads the `skeleton_worker` row: Might 4 (carry capacity), walk 0.9, Woodcutting 3 / Mining 3 / Foraging 2. **No RNG variance** — FOUNDATION_SPEC §3 explicitly exempts Skeleton Workers from the `baseline + d3 − d3` roll ("interchangeable by design"). Two skeletons are the same skeleton. Missing-row fallbacks degrade to the hardcoded baseline, and `RaceCatalog`'s stat getters default to 5 rather than 0 specifically because a 0 skill would divide by zero in the gather-time formula.

#### `DayNightCycle` — the minimum clock, added because dawn had to exist

Berry regrowth and deer respawn are both "at each dawn" in FOUNDATION_SPEC §5, which is dead code with nothing emitting a dawn. So `scripts/world/DayNightCycle.gd` started as the smallest thing that makes them real: a timer that flips day (30 min) / night (20 min) and emits `EventBus.dawn_started` / `dusk_started`. **Extended since — see "Day/night, finished" below.** Note the game starts *at* dawn of day 1, so the first `dawn_started` is a full 50-minute cycle in.

#### Gotchas worth knowing

- **New `class_name` scripts need an import pass.** Running `godot --headless --path . --quit-after N` right after adding one fails with `Could not find type "X" in the current scope` — the global class cache isn't rebuilt. Run `godot --headless --path . --import` once first.
- **Some `Icons/Food/` files really are named `*.png.png`** (roughly the first ten). If a path from that folder looks like it has a typo'd extension, check the filename on disk before "fixing" it.
- **There is no animal sprite in any vendored art pack** — see "The deer sprite" below. (Trees, groves and graves have since gained real commissioned depleted-state art; see "Art provenance".)

**Verification.** A headless 10× run with 3 workers and wood threshold 30: wood climbed 8 → 32 and fell through to stone exactly as specified, stone then climbed to 29 and fell through to food; two deer were tracked down and hauled home 8-food-in-one-load each; bones drained from carcasses and both graves until the map read `bones=None left` and the workforce went idle; two trees became stumps. A separate 60× run (fast enough to clear a whole 50-minute cycle) confirmed dusk at t≈1792, dawn at t≈2992, the berry grove regrowing +8, and a replacement deer wandering in. And a plain 1× run with no harness at all logged `Skeleton Worker #1 delivered 4 wood` — one full walk-chop-haul-deposit trip, carrying exactly its Might.

Worth repeating a bug that run caught, since the failure mode is silent: **`ResourceField._on_dawn` originally took no arguments while `EventBus.dawn_started` carries a day number.** Godot 4 accepts that connection and only fails at emit time, so the clock looked perfect while regrowth quietly never ran. If something wired to a signal appears to do nothing, check the handler's arity before anything else.

### Day/night, finished — tint, clock readout, and the debug time scale

Completes FOUNDATION_SPEC §7's foundation cycle. All of it is **inside the existing `DayNightCycle.gd`** rather than a second system — the phase clock, the lighting, and the speed control are one concern, and splitting them would mean three things reading the same `elapsed_in_phase`.

**Sub-phases.** `Phase` is `DAWN / DAYLIGHT / DUSK / NIGHT`. Dawn and Dusk are the first `TRANSITION_SECONDS` (90s) of the day and night phases respectively; the rest of each phase is the settled state. The HUD reads `"Day 2 — Dusk"` — the day *number* only advances at dawn, so night 2 is still part of day 2.

**Tint.** A `CanvasModulate` created by `DayNightCycle` cross-fades `DAY_TINT` (white) → `NIGHT_TINT` (`0.52, 0.58, 0.82`) over the transition window, driven off `elapsed_in_phase` so it inherits the time scale for free. Two deliberate choices:

- **Night is a blue-shifted dimming, not a blackout.** Skeleton labour works through the night by design (§7's "undead don't sleep" perk) — making night unreadable would punish the player for a mechanic that's meant to be an *advantage*.
- **The HUD is not tinted.** `CanvasModulate` only affects its own canvas; the HUD lives in a separate `CanvasLayer`, so the settlement darkens and the UI stays legible. That's a consequence of where the node is parented, so don't "tidy" it into the HUD layer.

The fade's `from` colour is captured as the *actual current tint* at the moment the phase flips, not the previous phase's constant — so flipping phases mid-fade (only reachable by cranking the time scale, but still) eases from wherever it got to instead of snapping.

**Debug time scale.** A `1x / 10x / 60x` button at the right of the top bar, cycling via `DayNightCycle.cycle_time_scale()`.

> **How the scaling is applied:** it sets **`Engine.time_scale`**, which multiplies the `delta` Godot hands to every `_process`/`_physics_process` in the game. Every timer in this project is a delta accumulator — the day/night clock, `WorkerSystem`'s trip loop, `Building`'s resource tick, `EventSystem`'s event timer — so they all inherit the scaling with **no per-system plumbing**, and stay in sync with each other by construction. Godot also scales `SceneTreeTimer` and `Tween` by it, so nothing is left running at wall-clock speed. It does *not* scale input or rendering, which is what keeps it usable as a debug control.
>
> The practical consequence for future work: **if you add a timer, use `delta` accumulation or a `SceneTreeTimer` and it just works.** A timer built on `Time.get_ticks_msec()` or `OS.get_unix_time()` would silently ignore the speed control and desync from everything else — don't.

It's labelled debug because it is one: a way to watch a 50-minute cycle or a gathering trip without waiting, not a player-facing game-speed feature.

### Art provenance — what's commissioned and what's still placeholder

`Official Sprites/` holds the **commissioned art**: transparent PNGs, 1024px square for buildings/nodes/icons and 1254px square for race tokens. This is the real art. Everything else in the project is a stand-in.

**Wired:**

| Use | Sprite | Where the path lives |
|---|---|---|
| Throne, Barracks, Bone Pile, Dark Altar | `Throne_of_Bones` / `Barracks` / `Bone_Pile` / `Dark_Altar` | `data/buildings.json` → `sprite_path` |
| Trees | `Pine_Tree` → `Pine_Stump` when chopped | `ResourceField` consts |
| Berry grove | `Berry_Grove_Full` → `Berry_Grove_Picked` when stripped | `ResourceField` consts |
| Graves | `Grave_Undisturbed` → `Grave_Dug_Up` when robbed | `ResourceField` consts |
| All 16 race tokens + Skeleton Worker | one per race | **`data/races.json` → `sprite`** |
| Necromancer (HUD badge + map avatar) | `Necromancer_Portrait` | `Main.NECROMANCER_SPRITE`, `Necromancer.PORTRAIT` (the data object names its own portrait, so the inspection payload never asks a view for it) |
| Dark Essence in the resource bar | `Icon_Dark_Essence` | `Main.ICON_DARK_ESSENCE` |

**Race token art is data, not code.** `RaceCatalog.sprite(race_id)` reads it from `races.json`, so adding a race never means editing a Dictionary in `Main.gd`. `Main.SPECIES_SPRITES` survives *only* as a fallback for Ghoul and Wraith, which exist in the superseded `followers.json` templates and have no `races.json` row — don't add to it.

**Deliberately not wired:** `Orc_Armed.png`, `Goblin_Armed.png`, `Gray_Dwarf_Miner.png`. These are per-state variants for combat (Stage 4+) and a working/at-node state. There is no state machine to select them, and wiring them now would mean inventing a state concept purely to justify the art.

**Still placeholder:** the Stone Deposit (Kenney materials icon), animal carcasses (Kenney bones icon), the deer and the wolf (both generated — see below), recruit houses (Kenney House pack, tinted per race by `HouseStyle`), Workshop/Blacksmith (Kenney towers), and the five locked per-species housing buildings.

**Scaling.** Source art is 30–40× its on-screen size, so every use scales down. Two different mechanisms, both already in the codebase:

- **`Sprite2D` users** divide a target pixel width by the texture width — `Building._setup_sprite` (largest side → 64px = `CELL_SIZE`), `ResourceNode.setup_sprites` (per-node target: tree 38, grove 46, grave 34, deposit 58), and the tokens (worker 32, follower 40, necromancer 44).
- **`Control` users** (the HUD badge and the Dark Essence icon) use a `TextureRect` with `EXPAND_IGNORE_SIZE` + a `custom_minimum_size`. Without `EXPAND_IGNORE_SIZE` a raw 1024px texture asks for a 1024px-tall container and blows the top bar open.

Verified after the swap: every building renders 64×64, every node at its target, every token 32/40/44, and the top bar stayed 47px.

One latent bug closed on the way through: `ResourceNode` used to compute its scale once from the *alive* texture and keep it when swapping to the depleted one. Every pair happens to be 1024px so nothing visibly broke, but a stump of a different resolution to its tree would have rendered at the wrong size. Scale is now recomputed per texture in `_apply_scale_for()`.

`Official Sprites/_originals/` holds full-resolution backups and carries a `.gdignore`, which makes Godot skip the whole directory — confirmed no `.import` files are generated in it and nothing in `.godot/` references it. Leave that file in place.

### The deer sprite

**No vendored art pack contains a quadruped.** Both Kenney roguelike sheets were checked tile by tile before concluding this: `art/roguelikeSheet_transparent.png` is terrain, buildings, furniture, fences, market stalls and UI bars; `art/roguelikeChar_transparent.png` is paper-doll parts (heads, torsos, hair, shields, weapons). There is a roast bird and a fish, but those are food *items* — which was exactly the problem, since the deer had been standing in as the raw-meat icon and read as a floating steak rather than something you hunt.

So `art/creature_deer.png` is generated: a 32×32 side-view silhouette plotted with the `Image` API by **`tools/make_deer_sprite.gd`**, run with `godot --headless --path . -s res://tools/make_deer_sprite.gd`. The generator is kept in the repo rather than run-and-deleted so the placeholder stays tweakable, and it carries the shape/colour reasoning in its comments (including two rejected attempts at a pale belly stripe that read as a saddle blanket). It is **still a placeholder** — it just needs to read as a living animal. Nothing depends on the script at runtime, only on its output PNG.

One gotcha it hit: **`_set` is an `Object` virtual** (`_set(StringName, Variant) -> bool`). Naming a pixel-plotting helper `_set` fails to parse with "function signature doesn't match the parent". It's called `_px` now.

**`art/creature_wolf.png` is generated the same way** (`tools/make_wolf_sprite.gd`), and had one job the deer's didn't: at 34px on a night-tinted map it must never be mistaken for the deer, because one is food and the other eats your workers. Three deliberate contrasts carry that — cold grey-blue against warm brown (and the night tint is itself blue-shifted, so the two *separate* at night rather than converging), a low flat back against the deer's tall short one, and a head carried *below* the shoulder line with no antlers, which is the universal read for a stalking predator. Also still a placeholder.

### Stage 3: the Barracks, and recruits who are actually individuals

Turns the Barracks into real recruit intake and replaces template-based recruitment with generation off the race roster. This is the pass that made GAME_OUTLINE Stage 3 playable.

#### The Barracks (`buildings.json`, `SettlementGrid`)

`category: "housing_intake"` — a category of exactly one, deliberately **not** `"housing"` (that category means the old per-species hard gate, which is locked). Cost 8 wood / 6 stone, `capacity: 5`, `power_value: 4`, `"unique": true`.

- **`"unique"` is a new catalog flag**, filtered in `BuildingCatalog.buildable_ids()`: once one is placed it leaves the build menu forever. FOUNDATION_SPEC §9's "Only one can ever exist."
- **No `requires`.** It used to be gated behind the Workshop. GAME_OUTLINE Stage 2 puts the Barracks *first* and the Workshop tech line after, so the prerequisite was inverting the intended build order — with 8 wood / 6 stone against a `wood=8 stone=5` start it's now reachable after roughly one gathering trip, which is the Stage-1→2 gate doing its job.
- **Clicking it opens the Barracks panel** (`Main._toggle_barracks_panel`), same click-the-building-on-the-map pattern as the Keep menu. It lists each resident's race, category, four stats and three labor skills side by side, because that's the information the fund-a-house decision will need.
- **The Upgrade button is a real, visible, `disabled` `Button` labelled "Upgrade — Locked"**, with no handler and no cost shown. Deliberately a Button rather than a greyed Label like the other roadmap placeholders: FOUNDATION_SPEC §9 asks specifically for a *button* that is present and locked, because the promise being made is "there will be a button here".

`SettlementGrid` gained `get_barracks()` / `barracks_capacity()` / `barracks_residents()` / `barracks_free_slots()`. **`barracks_residents()` currently returns the whole roster size** — exact only because fund-a-house doesn't exist yet, so nobody has ever moved out. When that lands (GAME_OUTLINE gap #4) it has to count only followers still resident.

#### The Barracks is the event gate

`EventSystem.EVENTS_ENABLED`, a hardcoded `false` that existed only to stop events drowning out other testing, is **gone**. `events_enabled()` now returns "is there a Barracks?" — GAME_OUTLINE Stage 2 ends with "Barracks built → recruitment-event timer turns on", so there's a real in-fiction reason for silence at the start.

Note it gates on the Barracks *existing*, not on a free slot. **A full Barracks still gets offers** — they just arrive with only turn-away choices (and the description says why). Fizzling the event entirely would make a full Barracks indistinguishable from a broken timer. The two turn-away variants differ in *how* you refuse, which is the hook departure-memory (gap #6) will hang off.

#### `RecruitGenerator` — recruits rolled from `races.json`

Replaces the `data/followers.json` template lookup (seven hand-written archetypes with flat min/max ranges). Owned as one long-lived instance by `EventSystem`, not a static utility, because the first-run guarantee has to remember how many offers it has made.

- **Which race** — roulette-wheel weighted by the race's rarity band. A rarity string missing from the weight table gets weight 0 rather than a silent default, so a typo in `races.json` shows up as "this race never appears" instead of quietly skewing the distribution.
- **Power attracts power** — the weights come from a **table in `data/recruitment.json`**, not branches: `[{min_power: 0, 60/30/10}, {min_power: 25, 50/35/15}, {min_power: 40, 40/40/20}]`. `rarity_weights_for_power()` walks it and takes the last tier whose `min_power` has been reached, so tiers must stay sorted ascending and adding a fourth is a JSON edit.
- **Stat rolls** — `clamp(baseline + d3 − d3, 1, 10)` per stat and per labor skill (FOUNDATION_SPEC §3). Centre-weighted, so most recruits sit near baseline and ±2 is rare. Walk speed and food/meal stay racial constants with no variance.
- **Exceptional recruits** — 5% chance of +1 to the category-defining stat, `Follower.is_exceptional` set. `"best_labor"` (the Economy entry) resolves *per individual* to whichever labor skill they actually rolled highest, because an Economy race's defining trait is being good at its own speciality and that differs by race. `"none"` (Versatile, Labor) never rolls exceptional — Human Outcast is the flat-5 jack-of-all-trades by definition and Skeleton Workers are interchangeable by design. Marked with a ★ in the roster, the Barracks panel, the info panel, and on the map token.
- **First-run guarantee** — the first three offers are dealt from `first_run_categories` (Warrior, Economy, Research) in order, still rarity-weighted *within* the category. It counts **offers, not acceptances**: turning the first orc away still burns the warrior slot, because you were shown the category, which is what the guarantee promises. Versatile is deliberately absent from the list, per RACES.md.

`data/followers.json` and `EventSystem._recruit()` still exist for the events.json entries that reference template ids, but those are off the timer — the timer fires recruit offers only for the foundation build. **The old per-species housing hard gate is deleted**; it checked buildings that the foundation reset made unbuildable, which silently made every gated species impossible to recruit (this file flagged it as a blocker two passes ago). Barracks capacity is the gate now, for both paths.

#### `Laborer` — the new base class, and why Worker and Follower both extend it

This is the structural change worth understanding before touching any of it.

Recruits gather. A settled Gray Dwarf brings Mining 9 against a skeleton's 3, so the same trip yields stone roughly three times faster, and their higher Might means a bigger load on top — that's most of the reason to recruit one at all. But Worker and Follower are still deliberately different types, and the "don't merge them" call has been reaffirmed twice. So the **labor half** — Might/walk speed/the three labor skills, plus the whole `TripStage` state machine, `position`, carry state and `abandon_trip()` — is factored into `scripts/settlement/Laborer.gd`, and both extend it.

The boundary to hold: **`Laborer` is the job, not the person.** Traits, Loyalty, race identity, bounty appetite, `is_busy` all stay on Follower; serial-number naming stays on Worker; neither belongs in the base. Two hooks make the difference work:

- `can_labor()` — Worker always true (labor is all it is, there is nothing to pull it away). Follower returns `not is_busy`, so a follower on a bounty leaves the pool, and `WorkerSystem.laborers()` calls `abandon_trip()` on anyone pulled away mid-trip rather than leaving a phantom claim on a resource node.
- `display_name()` — Worker returns `worker_name`, Follower returns `follower_name`. They stayed separate fields on purpose: "Skeleton Worker #3" is a serial number and "Thokk" is a person.

`WorkerSystem._process` now iterates `laborers()` (workers + non-busy followers) rather than `workers`, and every trip-loop function is typed `Laborer` instead of `Worker`. `FollowerToken` became a pure position-mirroring view exactly like `WorkerToken` — it used to run its own Tween idle wander, which was fine while followers only stood around, but their position is real simulation state now. Bounty/mission `send_away()`/`return_home()` survive as visibility toggles, since those genuinely take a follower off the map.

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

### Camera framing and the Necromancer avatar (Core Feel pass, Prompt A)

#### The camera starts on the Throne

It used to centre on the *grid's* midpoint. The Throne sits at cell (0,0) — a corner of the map, not its middle — so the player's own keep started tucked into the top-left with empty ground filling the screen.

`GameCamera.center_on()` now frames a world point in the **visible map band**, not the raw window. A `Camera2D` draws its own `position` at the window centre, so centring on the band between the top resource strip and the bottom command bar means deliberately offsetting away from that:

```
screen_y = window_h/2 + (world_y - camera_y) * zoom
```

Solve for the camera position that puts the target at the band's centre, and divide the screen-space inset by `zoom` to convert it to world units — which is what makes the framing survive zooming. `Main._sync_camera_insets()` feeds it the real panel heights (`top_panel.size.y` and `BOTTOM_BAR_HEIGHT`).

Two timing details worth keeping:

- **Control sizes aren't final on the frame they're created**, so the first framing runs with a top inset of 0 and is a few pixels out. `_settle_initial_camera_framing()` re-runs it after two frames. It's deliberately *not* awaited by `_ready()` — it runs to its first `await`, lets `_ready` finish, then resumes.
- **Resize re-frames only while `camera.player_has_moved_camera` is false.** Any pan or zoom sets that flag. Snapping the view back to the Throne because someone dragged a window corner would be worse than a slightly-off centre.

Verified at 1400×760, 1024×600, 1920×1080 and 900×500: the Throne lands dead centre of the visible band every time (dx and dy both 0.0px).

#### The Necromancer walks his domain (`NecromancerToken.gd`)

The player now has an avatar on the map — a token that paces slowly within ~2 cells of the Throne so the settlement reads as having someone in charge of it, rather than being an unattended machine.

**He is not a `Laborer`, and the exclusion is structural rather than a flag.** `WorkerSystem.laborers()` is the union of `workers` and `GameState.followers`; he is in neither, so there is no path by which he can be handed a gathering trip or counted in the workforce summary. Keep it that way — if he ever needs to act on the world, give him his own system rather than slotting him into the labor pool. (Smoke-tested: labor pool size 1, `is Laborer` false, summary still reads "1 worker".)

**Where his position used to live — the documented exception, now closed.** It was on the node rather than a data object, the opposite of the convention above, on the grounds that nothing else read it. The section carried an explicit migration trigger: split it the moment any *other* system needed to know where he was. **That trigger fired and the split is done** — see "The villain splits" below. Everything from here to the end of this subsection describes the *pre-split* code and survives only as the reasoning trail.

Clicking him (or the HUD badge — two doors, one room) opens his entry in the shared `InspectionPanel` (see below), with a "Spells — coming soon" disabled button, the same visible-promise treatment as the Barracks Upgrade. His own bespoke panel is gone, as this section previously predicted it would be.

His art is the 128px HUD *portrait* scaled down to token size — a stand-in until ART_BRIEF's proper Necromancer sprite exists, same documented spirit as the generated deer.

### One panel for everything clickable (`InspectionPanel`, Core Feel Prompt B)

Click behaviour used to be three separate panels grown one at a time — the Keep menu, the Barracks roster, the Necromancer card — each with its own toggle function, its own populate function, and its own idea of what a header looks like. Meanwhile most of the map wasn't clickable at all: a tree, a grave, a funded house and a Bone Pile were all scenery. Now **everything on the map is inspectable through one panel**.

#### The Inspectable contract

Anything clickable implements **`get_inspect_data() -> Dictionary`**. That is the entire interface. GDScript has no `interface` keyword, so it's duck-typed — `InspectionPanel.inspect()` checks `has_method()` and refuses with a warning rather than crashing.

```
{ "title", "subtitle", "sprite", "description", "details": [ {label, value, muted?, color?}, ... ] }
```

A `details` row with an empty `label` renders full-width — that's what the flavor asides and "nothing left here" notes use.

**A registry was the other option and was rejected.** It would need every clickable to register and deregister (resource nodes are created and freed at runtime — deer especially), and the registry would end up holding exactly the per-type knowledge this pattern exists to distribute. Asking the object is cheaper and can't go stale.

**There is no `match` on type in `InspectionPanel` or in `Main.gd`.** `ResourceNode` knows about regrowth and depletion, `Building` knows about tick rates and residents, `Follower` knows about morale and housing, `NecromancerToken` knows he isn't a laborer. Adding a new inspectable type means writing one method on it and nothing else.

Characters are the one place with shared scaffolding: `Laborer.get_inspect_data()` assembles the whole character block (activity, four stats, three labor skills, carry, walk speed) and subclasses fill four small hooks — `inspect_race_id/category/social_stats/extra_rows` plus subtitle and description. A skeleton and a gray dwarf want the same *shape*; only the contents differ. Note `Worker.inspect_social_stats()` reads Guile/Influence/Loyalty straight off the race row rather than storing fields — a Worker has no use for them, and a skeleton's are constants anyway.

#### Actions are the deliberate exception

The Keep's Recruit Worker / Surrender and the Barracks' Fund House buttons call *Main's* handlers, so they can't live on `Building` without handing every building a reference to Main. `inspect()` takes an optional `extra: Callable` that Main supplies and which is handed the panel's action VBox to fill (`_build_keep_actions` / `_build_barracks_actions` / `_build_necromancer_actions`). **Data comes from the object; actions come from whoever owns the handlers.** That split is why `InspectionPanel` has no idea what a Barracks is.

#### Click pick order

**characters > resource nodes > buildings > ground**, in `Main._inspect_at()`. A worker standing on a tree inspects as the worker; the Necromancer pacing on the Throne inspects as the Necromancer; a deer wandering over the Bone Pile inspects as the deer. Clicking bare ground closes the panel — that counts as a deliberate action, so the click is still consumed.

Nodes sit above buildings because they're mostly off-grid (forest, deposit, graves) and a deer roams anywhere, so an overlap means the node is the thing on top.

**Placement and demolish modes keep first refusal on every click**, unchanged: `_unhandled_input` still returns early for both before inspection is ever reached, and entering either mode closes the panel. Esc cancels the *mode* while one is armed, and only closes the inspector when neither is.

Depleted nodes stay clickable on purpose. A stump and a dug-up grave are exactly what a player clicks to ask "is this finished?", and answering that is half the point.

#### Live refresh by polling, not by signal

`InspectionPanel` keeps the *source object*, not the Dictionary it produced, so `refresh()` re-asks it. `Main._process` polls every `INSPECTOR_REFRESH_INTERVAL` (0.4s) while the panel is open. A worker's Activity row and a Barracks' resident count both change while you're looking at them, and most of the signals that would drive them (activity especially) fire every frame anyway — same reasoning as the priority rows being polled rather than signalled. The handful of genuinely discrete moments (funding a house, a recruit joining, a meal served) call `refresh()` directly so the panel agrees with the button the player just pressed.

`refresh()` closes itself if the source has been freed — an inspected deer really can be hunted, and `ResourceNode` is a Node2D that gets `queue_free()`d. `Follower` is RefCounted so `is_instance_valid()` stays true after they desert; Main closes the panel explicitly in the `recruit_departed` handler for that case, and in `building_removed` for demolition (where `queue_free()` is deferred and the guard wouldn't notice until next frame).

#### One real bug this pass caught

**`_closest_token_hit()` measured the *token's* position, not the Laborer's.** The token is a pure view that copies `laborer.position` in `_process`, so it's always one frame stale — and a follower sent away on a bounty has a token that stopped mirroring entirely and glided off to the gate, meaning a click at the gate would select someone who isn't there while the real unit was unclickable. It now measures the Dictionary key (which *is* the simulation object) and skips hidden tokens. This is the same view-vs-simulation drift the architecture conventions warn about, surviving in the input layer after the rendering layer had been fixed twice.

#### Data added

`data/buildings.json` gained a `description` per entry (the one-line "what is this for"), for the same reason costs and prerequisites live there: adding a building should never mean a new branch in a description function. `Building.house_owner_name` is set by `fund_house()` alongside `display_name`, so a house can name its resident without searching the roster for whoever lives at that cell. `ResourceNode` now keeps its sprite *paths* alongside the loaded textures — a `Texture2D` has no route back to its `res://` source, and the panel shows whichever art is currently on screen (stump, not tree).

Tree nodes are `Pine Tree` / `Pine Stump` now rather than `Tree` / `Stump`, matching the commissioned art.

### Combat: the minimal primitive, and the wolf (Core Feel Prompt C)

The first thing on the map that can hurt you, and — more importantly — **the one damage formula that Stage-4 bounties and Stage-5 raids are meant to call.** Building wolf-specific combat inline was the explicit failure mode to avoid, so the code is layered by how reusable each piece is:

| File | Knows about | Reusable by |
|---|---|---|
| `scripts/combat/Combat.gd` | nothing — two Combatants and some arithmetic | anything |
| `scripts/combat/Engagement.gd` | a fight's clock and its participant list | anything |
| `scripts/world/Wolf.gd` | how to prowl, look, and bleed | — |
| `scripts/combat/CombatSystem.gd` | **policy**: targeting, defence, consequences | replace per encounter type |

Only the last one would need rewriting for a bounty. A bounty that wants an instant abstract result calls `Combat.exchange()` in a loop and never constructs anything.

#### The formulas

```
max_hp  = 8 + Might * 2          Human Peasant 18, Skeleton Worker 16, Ogre recruit 26
damage  = attacker Might + d3 - floor(defender Might / 2)      minimum 1
exchange interval = 1.5s, both sides swing, both swings land
```

**Might is the only stat combat reads.** No dodging, no crits, no ranged, no initiative, no armour — every one of those would need balancing before the settlement loop it serves has been proven.

Three details that are load-bearing rather than incidental:

- **`max_hp()` is computed, never stored.** Might already decides durability everywhere else (it's carry capacity too), and a stored copy goes stale the moment anything changes Might — which the Blacksmith's `+1 Might` already does. `hp` is stored and initialised by `heal_full()` in each subclass's `_init`, plus once more in `RecruitGenerator` after the exceptional-stat bump.
- **The minimum of 1 is not cosmetic.** Without it a Gnome (Might 2) swinging at an Ogre (Might 9) deals `2 + d3 - 4` = nothing, ever, and a mismatched fight hangs instead of resolving.
- **Both swings land even when one is lethal.** A dying skeleton still gets its last hit in, which is what lets a doomed defender contribute to driving the wolf off — the difference between a loss and a total loss.

#### The Combatant contract

Duck-typed, same shape as `get_inspect_data()`: `combat_name()`, `combat_might()`, `max_hp()`, `hp` (property), `take_damage()`, `is_alive()`, `hp_fraction()`. `Laborer` implements it for every worker and recruit; `Wolf` implements it for the creature. `Combat.is_combatant()` is a cheap guard so a half-implemented new unit fails loudly instead of silently dealing zero forever.

#### The four consequence rules

These are the design decision, implemented exactly:

1. **Skeleton Workers can be destroyed.** No bones refunded, no corpse. Replaceable for the usual 5 Bones — losses sting, necromancers shrug.
   - **The wolf, conversely, leaves a body.** Killed outright (hp 0) it drops an ordinary carcass node worth `WOLF_CARCASS_BONES` (9) where it fell — better than a seeded carcass (5), because map bones are finite and a predator that pays out more than it costs is a welcome pressure valve. Merely *driven off* (below 5 hp) leaves nothing: routing it away is the cheap win, killing it is the paying one. The carcass is a plain `ResourceNode`, so the priority list, crowding rules and inspection panel all pick it up with no special casing.
2. **Living recruits are never killed by wildlife.** Below 30% hp they break off, run home, and are `Injured` (no work) until healed to full, at −1 morale. This is true *by construction*, not by a check at 0 hp: `_injure_and_flee` pulls them out at the threshold, and the 0-hp path warns and injures rather than killing if anything ever reaches it.
3. **A deer taken by a wolf is a pure economic loss.** The food is gone, the wolf is fed and stands down for the night. **This is the common case, and the point** — a wolf that never touches a person has still cost you 8 food and a hunting trip.
4. **Wolves won't approach the Necromancer**, and anything standing in his shadow is invisible to them. The protection is *positional*, so a worker who wanders off to gather is fair game again. **Since the villain split he is no longer "untouchable" in the general sense** — he implements the full Combatant contract and `Combat.exchange()` damages him like anything else. This is a *lair* rule, and it now sits behind `CombatSystem.LAIR_AURA_PROTECTS_VILLAIN` so R2 can switch it off in the world (rework §15 lists it as an open tunable). Flipping it off is necessary but not sufficient to make wildlife hunt him: he isn't in `_prey_candidates()` and there's no consequence branch for a villain losing a fight, because that branch is "the run ends", which is R4.

Note rule 3 and the "nearest prey, no preference" targeting work together: your hunters walk out to the same deer the wolf wants, so the two end up in the same place often enough without a preference rule aiming them at each other.

#### Emergent defence

**Nobody is ordered to fight.** When a fight starts, every recruit within 3 cells either joins or runs: Warrior-category or Might ≥ 6 wades in, everyone else drops their load and flees to their idle anchor. The player's only lever is who they recruited and where those people happen to be — the Majesty indirect-control pillar applied to defence, previewed before guard posts or bounties exist.

Skeleton Workers neither rally nor scatter. They have no self-preservation to override and no orders to act on, so they carry on until something bites them.

#### Regen, split across two systems on purpose

- **Living units: +2 hp per meal actually eaten** (`MoraleSystem._regenerate`). Healing lives in the meal loop because it's a consequence of eating — which ties injury to the food economy rather than to a separate timer. A recruit who goes hungry doesn't heal, so a wolf that mauls your orc during a famine has done compounding damage. Reaching full hp is also the only thing that clears `is_injured`.
- **Skeletons: 1 hp per 6s, only while idle at the Throne** (`CombatSystem._tick_throne_repair`). Necromantic maintenance. The undead perk cuts both ways — free to run, but mendable only at home. Slow on purpose: a mauled skeleton being out of the workforce for a while is most of what makes losing cost anything, when the unit itself is 5 bones.

#### `TripStage.FLEEING` and two new Laborer predicates

The trip loop gained a fifth stage. Fleeing runs at full walk speed rather than the idle shuffle — it's the one time a unit isn't ambling — and becomes `IDLE` on arrival.

Two similar-sounding checks that are deliberately different:

- **`can_labor()`** (existing) — "is this unit in the labor pool at all". False while a follower is away on a bounty.
- **`can_work_now()`** (new) — "will they take a *new* job". False while injured. An injured recruit stays in the pool, so they still walk home, still idle by their house, and still appear in the workforce summary. Removing them from the pool instead would freeze them mid-map wherever the wolf left them.

`in_combat` is a third, cruder flag: `WorkerSystem._advance_laborer` skips anyone carrying it, so a unit trading blows isn't also strolling off to a tree.

#### Tuning knobs

Wolf: Might 5, 18 hp, flees below 5 hp, hunt radius 5 cells, **the first dusk of a run always brings one, then 55% per dusk after that.** Max 1 alive; any wolf still around at dawn slinks off, which keeps that cap honest without a despawn timer.

Two of those numbers were corrected after the first playtest, and the failure is worth recording because it wasn't a crash — the system worked perfectly and the player still never saw it:

- **The introduction was left to a coin flip.** A session tends to end on the first night, so the feature got exactly one 55% roll to exist. Two playtests in a row came up empty. A mechanic gets to introduce itself deterministically; it can be a gamble afterwards.
- **A fed wolf used to depart on the spot, and it spawns beside the deer.** The treeline entry point is inside the deer roam area, so it killed and left within seconds of arriving — off the map before it was ever on screen, twice out of two spawns. Fixed twice over: `HUNT_DELAY_SECONDS` (25s) makes it prowl visibly before it can take anything, and a fed wolf now stays until dawn, which is also what "stops hunting for the rest of the day" actually asked for.
- **And it still wasn't visible after that.** Playtest reported "the wolf spawned but I didn't see it" *with the alert firing and a fight starting*. Two causes: it entered 5.5 cells past the grid edge, which at the default 0.72 zoom is the very rim of the viewport, and a 34px token renders there as ~24 screen pixels of dark grey on dark ground. Entry moved to 2 cells out, `TOKEN_SIZE` raised to 46 (larger than any other unit), `z_index` 6 so nothing occludes it, and the hp label given a black outline. The thing that eats your labourers should be the most legible object on the map.

Measured after the fix: 4 wolves over 6 dusks, first one guaranteed, each visible for a whole night.

**The deer is still the usual victim** — they roam the same ground the wolf enters on, so "nearest prey" nearly always resolves to one. That is rule 3 working, not a targeting bug: the wolf is meant to be an economic threat first. It reaches people when your labourers are out in the forest at night.

Wolf vs a lone Skeleton Worker is close by design — ~5 damage a swing against ~4 back, so the wolf needs 3.2 exchanges and the skeleton 3.5. Measured over 7 scripted fights the skeleton lost 7/7, but the margin is thin enough that it won't always. An Orc (Might 7, 22 hp) beats it comfortably.

#### Verification

A headless harness at both 10× and 60×, all passing: the formula in isolation (range 4–6 for wolf-vs-skeleton, min-damage floor, both sides damaged, contract guard); the hp table (16/18/26); dusk spawn; deer kill → fed → stands down → leaves; 7/7 lone skeletons destroyed with no bones refunded; orc engages and drives the wolf off while never dying; +2/meal recovery clearing `Injured`; a Warrior auto-joining while a Might-2 Gnome flees untouched; the Necromancer's shielding; and Throne repair (9 hp vs 3 hp for a skeleton parked elsewhere).

Two harness traps worth remembering, both of which produced convincing false failures:

- **`get_process_delta_time()` is already scaled by `Engine.time_scale`.** Multiplying by it again advances your accounting 60× too fast, so a "wait 6 seconds" loop returns after 0.1s and everything looks broken until the events arrive later in the log.
- **`NecromancerToken` owns its own position and walks back to `home`.** Assigning `.position` to move him for a test doesn't stick — use `setup()`.

### Command Undead — the Necromancer's first spell

Playtest feedback after the combat pass was "I can't direct skeletons anywhere; there's no option to command them." That was true and deliberate (GAME_OUTLINE pillar 2), but it left a threat on the map with no lever to answer it. **The resolution the user chose is better than adding unit orders: a spell.**

**Why this doesn't break the indirect-control pillar.** You still don't order units around. You cast a spell that binds *the dead, as a class*, to a point. The distinction is real rather than a fig leaf: a skeleton has no will to override, which is the entire difference between it and a recruit. Living followers remain uncommandable and always will be.

- **`UndeadCommand`** (system) + **`RallyPoint`** (Node2D marker, inspectable). Cast from the Necromancer's panel — the old "Spells — coming soon" placeholder is now a real button — which arms a third click-to-target mode alongside build placement and demolish. Click the map to plant it.
- **Three orders, differing only in leash length**, which is the only axis that matters at this scale: **Defend** (1.2 cells), **Patrol** (3 cells, walks a beat), **Attack** (7 cells, seeks the nearest hostile). Clicking the rally point opens it in the inspection panel with the order buttons, a Move, and a Dismiss.
- **Hostiles are measured from the rally point, not from the unit.** Measuring from the unit would let a skeleton that chased something to the edge of its leash re-measure from there and keep going forever.
- **The cost is the economy.** Bound undead leave the labor pool — `can_labor()` returns `not rallied`, so the priority list stops seeing them. *The dead can dig or they can fight, not both.* With one starting skeleton that's a total shutdown; with six it becomes a real allocation question, which is when it gets interesting.
- **No resource cost yet.** Dark Essence is the obvious candidate and is locked at 0 for the whole foundation build, so charging now would mean the spell could never be cast. Revisit at Stage 4.
- **It commands *all* undead, not a chosen subset** — on purpose. Picking which skeletons to send is a selection UI, and a selection UI is exactly the per-unit control the pillar rules out.
- **A standing order binds skeletons raised later.** Raise a new one while the point is up and it falls in automatically; the spell is an order on the dead, not on the individuals who happened to be present.

**`Laborer.is_undead()` reads `alignment: "Undead"` from races.json**, not the class. So the ghouls and wraiths on the roadmap are commandable the day they exist, and no living race ever can be — which is what the user meant by "later this will be useful when he unlocks more powerful undead."

Two related fixes fell out:

- **`WorkerSystem.laborers()` now filters Workers by `can_labor()`** instead of appending them wholesale. "Every Worker is always available" stopped being true the moment a spell could take them off the roster. `all_units()` is the new unfiltered view, which combat targeting needs — a skeleton standing guard is out of the workforce but very much still something a wolf can bite.
- **Skeletons no longer flee from fights.** `_rally_and_scatter` was calling `begin_flee()` on them, contradicting this file's own claim that they "neither rally nor scatter". Code now matches the documented intent: they have no self-preservation to override.

Verified headless at 60×: alignment-based targeting, all 3 skeletons bound and the orc untouched, skeletons out of `laborers()` but still in `all_units()`, the march to the point, patrol staying inside its ring (164px of 192px) while defend holds tight, Attack sending them out to engage a wolf beyond the patrol ring, converging skeletons sharing *one* Engagement rather than three duels, dismiss returning everyone to the priority list, a later-raised skeleton joining the standing order, and a regression check that an uncommanded skeleton still gets attacked normally and still doesn't run.

### HUD layering, and four playtest bugs worth remembering

A batch of playtest reports that all turned out to be UI plumbing rather than game logic. Recorded because three of them share one root cause that will recur.

**Sibling `Control` order is z-order *and* input order, last on top.** `_build_bottom_shell` used to be the final child of `hud_root`, which put the command bar over both floating panels. The consequences looked like completely unrelated bugs:

- A recruit offer's choice buttons hang below the screen's centre line, landed under the command bar, got tinted by its translucent background (so they read as **disabled**) and had their clicks eaten. A full-Barracks offer was literally unanswerable.
- `PRESET_CENTER` made it worse: it anchors a Control's **top-left corner** to the screen centre, so the panel grows down-right from there rather than being centred on it. The event panel is `PRESET_TOP_LEFT` + `_position_event_panel()` now, which centres it in the *visible band* (between the top strip and the command bar) and clamps it so it can never cover the bar.
- The inspection panel had the same exposure. It also moved from x=360 to x=60 so a centred event offer can't sit on top of the Barracks panel's **Fund house** button — the one control you need to reach to answer a full-Barracks offer.

**A recruit offer is a live decision, not a snapshot.** Its choices used to be frozen at the instant it fired, so funding a house while the offer was open freed a slot that did nothing — you stayed stuck with the two turn-away variants until the offer expired. `EventSystem.refresh_recruit_offer()` re-evaluates against current occupancy and rewrites the description and choices in place; `Main._refresh_open_offer()` drives it off the same 0.4s HUD poll as the inspector. Works both ways — a slot filled by someone else takes the accept option back. Polled rather than signalled because occupancy moves for four unrelated reasons and the refresh is a no-op unless the answer actually changed.

**The inspection panel now scrolls.** A full Barracks roster measured **706px** — five residents each with a wrapped stat block and a Fund house button — which ran off a 760px window and under the command bar. `InspectionPanel` is `PanelContainer > ScrollContainer > VBox` with `max_body_height` set by Main from the real band. Note the cap covers the **whole panel including its own stylebox padding**: capping just the body still overhung by 8px, which was enough to steal clicks from the bottom button.

**The History log was a letterbox.** Fixed at 56px with dead space under it, because neither `command_area` nor `cmd_history` had `SIZE_EXPAND_FILL` vertically, so the tab shrank to its content minimum. All three now expand; the log gets 166px of the 250px band and grows with the window.

Two testing notes from this round, both of which produced false results:

- **Headless Godot runs at a 64×64 viewport.** Every geometry assertion is meaningless until you `get_tree().root.size = Vector2i(1400, 760)` and wait a few frames. The bottom bar otherwise computes to y = −186.
- **GDScript lambdas capture locals by value.** `var seen := false` + `sig.connect(func(): seen = true)` writes to the closure's own copy and the outer `seen` never changes. Capture through an Array (or a member) instead.

### The villain splits: data object, direct control, and a camera that follows (rework R1, first task)

**The documented migration trigger fired.** `NecromancerToken` used to own his position outright, as an explicit exception to the token-is-a-pure-view convention, with the exception's own expiry condition written into the file: *split it the moment any other system needs to know where he is.* Three now do — the camera follows him, `Combat.exchange()` hits him, and the keyboard drives him. This pass is that split, and nothing more: no world map, no sorties, no escort behaviour. **The game is still the settlement build; it just has a Necromancer the player drives.**

#### The split itself

`scripts/villain/Necromancer.gd` (RefCounted) owns position, hp, Might, carry capacity and current carried load, an escort roster, and a class identity string. `NecromancerToken` is now a **pure view** — it reads `villain.position`, draws there, flips a sprite, and decides nothing. Exactly the `Laborer`/`WorkerToken` contract, for exactly the reason that one exists.

Two details that carry weight:

- **He extends `RefCounted` directly, not `Laborer`** — deliberately. Sharing the trip-loop base class would put him one `laborers()` change away from being labour. The exclusion stays structural: `WorkerSystem.laborers()` is the union of `workers` and `GameState.followers`, and he is in neither. (Re-verified after the split: labor pool size 1, `is_instance_of(villain, Laborer)` false, summary still reads "1 worker".)
- **`carry_capacity()` is Might**, the same rule as every other unit (FOUNDATION_SPEC §6). One rule, not two. `carried` is a `kind -> amount` Dictionary rather than a Laborer's single kind/amount pair, because a sortie brings back a mixed load and a worker trip is one resource by construction. Nothing banks it yet — that's R2's deposit-at-the-lair step.

#### Per-villain state is the whole point (rework §11)

**None of this is in `GameState` or any other autoload, and nothing looks him up.** `Main` holds a reference to one instance; every consumer takes him as a field — `CombatSystem.villain`, `VillainController.villain`, `NecromancerToken.villain`. `CombatSystem`'s old `necromancer: Node2D` (which read the *token's* position) is now `villain: Necromancer` reading the data object, which also closes the same view-is-a-frame-stale hole `_closest_token_hit` was fixed for.

If a future pass catches itself writing `GameState.necromancer_hp` or a static `Necromancer.current`, that is the mistake this discipline exists to prevent. It is the entire present-day cost of keeping the Demonologist and multiplayer possible, and retrofitting it later is the expensive version.

#### Direct control is the keyboard, deliberately not click-to-move

Left-click already means three things arbitrated by mode (inspection, build/demolish placement, rally-point targeting) and right-drag means camera pan. Adding "walk here" as a fourth meaning for a mouse button would make every click first ask *which mode am I in* before it could ask *what did they click* — which is how an input layer rots. Hold-to-move on the keyboard is a separate channel: it can't collide with any click, it needs no mode, and it reads as direct control rather than as issuing an order (which matters, since ordering people about is the one thing the pillars rule out).

**There was a real conflict to resolve, and it's resolved as WASD = the man, arrows = the camera.** `GameCamera._process` used to pan on both WASD *and* the arrow keys; the WASD half is gone. With follow mode on the two read almost identically anyway — moving him moves the view — so the arrow keys are really "look away from him for a moment", and like a right-drag they drop follow.

- **`MOVE_SPEED_CELLS = 1.4`, flagged as a tunable.** Same cells-per-second convention as `walk_speed` (1.0 = one grid cell/sec, literally). Faster than a Skeleton Worker's 0.9 because he's the player and trudging is not a fantasy; slow enough that the settlement doesn't read as small.
- **Movement is polled (`Input.is_key_pressed`), not event-driven.** Hold-to-move is a *state*, and rebuilding it from key-down/key-up desyncs the first time the window loses focus mid-hold. The F key (snap back to follow) is the opposite — a discrete press, so it's in `_unhandled_input`.
- **Movement is suppressed while a `LineEdit` has focus.** The Economy tab's threshold `SpinBox`es are real text entry; without the guard, typing "30" into one walks the Necromancer across the map. (This bug already existed in the WASD *camera* pan — it was just less visible.)

#### Idle pacing survives, demoted

No movement input for 8 seconds and he resumes the old slow wander — within ~2 cells of **wherever he's standing**, not of the Throne, because he's a unit you park now rather than a fixture of the keep. Any input cancels it in the same frame, with no easing out and no finishing the current step. Both halves live in `Necromancer.step()` rather than being split between the object and its controller, because both write `position` and position has exactly one owner: the controller decides *what the player asked for*, the object decides *where he ends up*.

#### Camera follow, and the escape hatch

`VillainController` calls `GameCamera.center_on(villain.position)` each frame while following — that band arithmetic (between the top strip and the command bar) already exists and already survives zooming, so following him is one call per frame rather than a second camera implementation.

**The drop-out needed a new flag, and the reason is worth keeping.** `player_has_moved_camera` is set by pan *and* zoom, and zooming in on the man you're following must not stop following him. So `GameCamera.manual_pan_ticks` counts manual pans only (right-drag or arrow key); the controller drops follow when the count changes. Comparing a counter rather than reading a boolean also means re-engaging follow doesn't have to reach in and clear someone else's flag. **F snaps back and re-engages**, and there's a button in his panel doing the same thing — the key is the fast path, the button is how you learn the key exists. State is shown under the HUD badge (bright "Following [F]" / dim "Free camera").

One consequence: `Main._on_viewport_resized` now re-syncs the camera insets **unconditionally** rather than only while the player hasn't panned. The follow camera calls `center_on` every frame regardless, so stale insets would mis-frame him for the rest of the session.

#### He is killable

`Necromancer` implements the whole Combatant contract (`combat_name`/`combat_might`/`max_hp`/`hp`/`take_damage`/`is_alive`/`hp_fraction`), so `Combat.exchange()` works on him with **no special casing anywhere**. `max_hp` is computed from Might, never stored, and it reuses `Laborer.HP_BASE`/`HP_PER_MIGHT` rather than restating the formula — there is exactly one hp formula in the project. Might 6 → 20 hp, a first guess flagged as the number to move when rework §15's "Necromancer combat stats" gets answered.

**Death is emitted from `take_damage()`, not from a policy layer.** `Combat.exchange()` doesn't know who it's hitting, so a run-ending event that only fired when `CombatSystem` happened to be the caller would be a trap for every later damage source (traps, the crusade, a rival villain). `EventBus.villain_died(villain, cause)` carries the villain object rather than assuming there's one of him, and fires once — `_death_announced` guards it, because `exchange()` will happily land another swing on a corpse in the same frame. **Nothing ends the run:** Main logs "THE NECROMANCER HAS FALLEN — the run would end here" and play continues. The run lifecycle is R4 and building half of it now would mean unpicking it then.

The lair aura is now `CombatSystem.LAIR_AURA_PROTECTS_VILLAIN` — see combat consequence rule 4 above for what flipping it off does and doesn't do. `Wolf.get_inspect_data()` reads the flag too, so the panel stops promising protection the moment it's switched off.

#### Inspection

His entry shows hp (current/max, colour-coded), Might, carry (current/capacity), escort count, and follow state. `NecromancerToken.get_inspect_data()` **delegates** to the data object rather than duplicating it — the one row it adds itself is camera follow, deliberately, because where the camera is pointing is a property of the view and not of the man. Put it on the data object and the next thing on it is a scroll offset. Actions (Command Undead, the follow toggle) stay in `Main`, unchanged split.

#### Verification

A headless scene harness, 49 assertions, all passing: the split (token mirrors the object, owns nothing, same instance), absence from `laborers()`/`all_units()` and the workforce summary, 1s of held input covering exactly 1.4 cells with diagonals no faster, the token catching up within one frame, follow tracking / dropping on a simulated manual pan / staying put once dropped / re-engaging on snap / surviving a zoom, pacing staying quiet at 7s and resuming by 8s within 2 cells then cancelling instantly on input, the Combatant contract, `max_hp` tracking a changed Might, `Combat.exchange(wolf, villain)` damaging both sides, death at 0 hp firing exactly once and not re-firing on a corpse, the lair aura still hiding a worker standing in his shadow, and every inspection row present via delegation.

Two harness notes for next time:

- **A `-s` SceneTree script compiles before the autoloads are registered**, so every class touching `EventBus` or `RaceCatalog` fails with "Identifier not found". Run a harness as a **scene** (`godot --headless --path . res://tools/whatever.tscn`) instead. If you do need `-s`, autoloads are reachable as `root.get_node("EventBus")`.
- **`root` is busy setting up children during your `_ready`** — await one frame before `add_child`ing an instantiated `Main.tscn`, or the call fails outright.
- The compiler statically rejects `villain is Laborer` ("Expression is of type Necromancer so it can't be of type Laborer"), which is itself the proof the assertion wanted. Route through an `Object` local and `is_instance_of()` if you want it as a runtime check.

**Not verified here, and it needs a human:** `Input.is_key_pressed` polling and `_unhandled_input` are both unreachable from godot-mcp's simulated input (see "Known constraint"). Actually holding W/A/S/D, panning with the arrows, and pressing F have to be checked with a real keyboard in the real window.

### Foundation exit criteria (manual playtest checklist)

Copied from FOUNDATION_SPEC §11 — Stages 1–3 count as proven when all of these hold **in one unbroken session**. Headless smoke tests have covered the mechanics in isolation; these are the integration checks that need a human at the keyboard.

- [ ] **1. Priority list drives 3 workers** across Wood/Stone/Bones with thresholds, and trees visibly deplete.
- [ ] **2. Barracks gets built from gathered** (not starting) resources.
- [ ] **3. At least 3 recruits arrive via events** spanning ≥2 categories, get fed every meal tick, and none desert from a bug rather than a real shortage.
- [ ] **4. One recruit gets a funded house**; Barracks slot frees; town visibly grows.
- [ ] **5. One food shortage is survivable and legible** — morale drops, player recovers by reassigning priorities.
- [ ] **6. No soft-locks** — node exhaustion, full Barracks, and zero-food states all have clear UI messaging and a way out.

Known gaps against this list, as of now:

- **#5's "recovers by reassigning priorities"** is untested end-to-end. Food is gatherable (berry grove + deer) and the priority list has a Food row, but no session has yet gone shortage → reprioritise → recovery in one unbroken run.
- **#6's zero-food state** has messaging (hungry-meal log line, alert pin, morale colour) but no explicit "you have no food source left" warning if the grove is picked clean and the deer are gone.
- **#3's "spanning ≥2 categories"** is guaranteed by construction for the first three offers, but the *arrive via events, get fed every tick* half is only verified in isolation.

## File map

```
project.godot              Godot project config, autoloads registered here
scenes/Main.tscn            Root scene (minimal — logic lives in Main.gd)
scripts/Main.gd              Wires all systems together + debug UI + build menu
scripts/autoload/           GameState.gd, EventBus.gd, BuildingCatalog.gd, RaceCatalog.gd (singletons)
scripts/settlement/         SettlementGrid.gd, Building.gd, FollowerToken.gd, WorkerSystem.gd, WorkerToken.gd,
                            MoraleSystem.gd -- meals, morale, theft, desertion
                            NecromancerToken.gd -- PURE VIEW over scripts/villain/Necromancer.gd; NOT a Laborer
                            HousePlanner.gd -- WHERE a recruit builds (race housing_style)
                            HouseStyle.gd   -- WHAT it looks like (sprite + tint per race)
                            Laborer.gd -- base class: the trip loop + labor stats
                            Worker.gd  -- extends Laborer (so does Follower, in scripts/bounty/)
							  ResourceNode.gd, ResourceField.gd
scripts/ui/                 InspectionPanel.gd -- the one click-to-inspect panel; defines the
                            get_inspect_data() contract every clickable implements
scripts/combat/             Combat.gd -- THE damage formula; reusable, knows nothing (bounties/raids call this)
                            Engagement.gd -- one fight's clock and participants
                            CombatSystem.gd -- policy: wolf spawning, targeting, emergent defence,
                            the four consequence rules, skeleton repair at the Throne
                            UndeadCommand.gd -- the Command Undead spell; binds the dead to a rally point
                            RallyPoint.gd -- the marker and its Defend/Patrol/Attack order
scripts/villain/            Necromancer.gd -- THE villain as data: position, hp, Might, carry, escort.
                            Per-villain state lives here and NOWHERE else (rework section 11 -- no
                            autoload may hold it, no code may assume exactly one villain)
                            VillainController.gd -- WASD hold-to-move + camera follow; takes the
                            villain and the camera as fields, looks nothing up
scripts/world/              DayNightCycle.gd (phase clock, CanvasModulate tint, debug time scale)
                            Wolf.gd -- the first hostile creature
                            Roaming.gd -- wander helpers shared by the deer and the wolf
tools/                      make_deer_sprite.gd, make_wolf_sprite.gd -- one-off art generators, not runtime code
scripts/bounty/              BountyBoard.gd, Bounty.gd, Follower.gd
scripts/threat/               ThreatSystem.gd
scripts/events/                EventSystem.gd, RecruitGenerator.gd
scripts/missions/            MissionSystem.gd
scripts/GameCamera.gd     Pan (right-drag or ARROW keys -- not WASD, that's the villain)/zoom Camera2D
addons/godot_mcp/           Third-party MCP bridge plugin (mkdevkit, MIT) — Godot-editor side
data/events.json               15 MVP random events
data/missions.json            4 MVP party missions
data/followers.json           SUPERSEDED recruit templates -- only the off-timer events.json entries still use these
data/races.json               Race roster from RACES.md: stats, labor skills, alignment, rarity, housing style, rivalries (loaded by RaceCatalog)
data/buildings.json           Building catalog: costs, prerequisites, "locked" and "unique" flags, Barracks capacity
data/recruitment.json         Recruit tuning: rarity-by-power table, stat-roll dice, exceptional chance, first-run categories
Official Sprites/            COMMISSIONED art -- buildings, nodes, all 16 race tokens, necromancer, icons
Official Sprites/_originals/ Full-res backups; .gdignore keeps Godot out. Leave alone.
art/, Buildings/, Characters/    Remaining placeholder sprites (see "Art provenance")
art/creature_deer.png       Generated, not from a pack -- see tools/make_deer_sprite.gd
```

## Next milestones (not yet built)

> **The roadmap is now `ROGUELITE_REWORK.md` §13 (stages R1–R6)** — see "Current phase". The list below predates it and survives as a backlog of settlement-layer items; where the two disagree, the rework doc wins. Specifically superseded by it: "Combat beyond the primitive"'s Stage-4/5 bounty-raid framing (bounties return in the run frame, R2+ escort/encounters first), "Save/load" (now required, scoped in R5 as meta-persistence first), and "Remaining villain classes" (the Demonologist is the second *playable* class, rework §11).

- Real UI (replace the code-built debug UI with a proper `.tscn`-based interface once validated in-editor)
- Multi-cell building footprints (everything is 1x1 on the grid for now)
- Housing capacity limits (currently a pure hard gate — species is unlocked or not, no cap on how many of that species you can have once housing exists)
- Physical gathering *buildings* / per-node worker capacity (workers now walk to real map nodes, but there's still no Lumber Camp/Quarry building layer and no hard cap on how many workers can share one node — `claims` is only a soft spreading hint)
- ~~Manual per-worker override on top of the priority list~~ — **answered differently**: see "Command Undead". The player's lever over unit movement is a spell that binds the dead as a class, not per-unit orders, which keeps the indirect-control pillar intact. Per-worker overrides for *living* recruits remain out.
- Replanting trees (FOUNDATION_SPEC §5: if wood scarcity bites, the planned fix is a manual replant-seeds action, explicitly *not* automatic regrowth)
- Dawn/dusk **meal ticks** — the last unbuilt piece of FOUNDATION_SPEC §7. The clock, the phases and both signals are in place (see "Day/night, finished"); what's missing is the food/morale system they'd drive, which needs living recruits to exist first (outline gap #3)
- Real deer / wolf / carcass / stone-deposit art — the last unreplaced map placeholders after the commissioned art pass
- Combat beyond the primitive: guard posts, ordered defence, more creature types, and the Stage-4 bounty/Stage-5 raid resolution that `Combat.exchange()` was built to serve
- Per-race house art (recruit houses still reuse the tinted Kenney House pack)
- Wiring the Orc_Armed / Goblin_Armed / Gray_Dwarf_Miner variants, once combat and work states exist to select them
- Climate system (deliberately deferred — see "Current phase" above)
- Save/load
- Remaining villain classes and climates (Phase 2, per design doc)
- Unique undead-themed building art per housing type (currently reusing the Kenney fantasy House/Tower/Castle packs with color-variant reuse as a placeholder — see `data/buildings.json` `sprite_path` fields)
