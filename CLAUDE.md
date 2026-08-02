# Undead Empire Prototype — Project Notes

Working codename only — no title chosen yet. This file orients any future session (Claude or human) picking this project back up.

## What this is

A villain-power-fantasy roguelite settlement builder, in the lineage of *Against the Storm* / *RimWorld*, inverted: the player is the reason "good" nations are afraid, not the plucky survivors. Full design context lives in `villain_settlement_builder_design_doc.docx` one level up from this folder (in `outputs/`) — that document is the source of truth for anything not covered here. This file is about the *code*, not the design.

## Current phase

**Phase 1 (MVP), narrowed further to Stages 1–3 of `GAME_OUTLINE.md` — see "Foundation reset" below, which supersedes the Core Loop line in this list.** Scope is deliberately narrow:

- One villain class: **Undead Empire**
- Climate: deliberately **not implemented yet** — the placeholder "Frozen Wastes" label/art is still in the code (`tile_ground_frozen.png`, log message in `Main.gd`) but per an explicit user scope call, climate mechanics are a later feature. Narratively the settlement is currently framed as a cold, remote, forested/mountainous hideout (Alps/Alaska-ish — a necromancer needs somewhere to hide) rather than a barren wasteland, which is why Wood exists as a resource; nothing in code enforces this yet, it's just the intended flavor for whenever climate *does* get built.
- Core Loop: settlement grid + building/housing system + a Worker-driven resource economy, Bounty Board (indirect control), Reputation/Threat escalation ladder, a random event pool, and a hand-picked-party mission system
- Win condition: **both** — survive the High-Threat Crusade climax **and** reach a Power threshold (per user's answer in design discussion)

**Important:** the design doc barely specifies the settlement-building/economy layer at all — see its Core Loop section, which only says "establish a settlement" and "carry forward buildings" as meta-progression, nothing more. The building/housing system and the Worker/resource-gathering economy (this section) were designed live in conversation with the user, not transcribed from the doc. If the doc and the code ever disagree on this specific layer, the code (and this file) is the more current source of truth, not the doc.

Multi-settlement, trade, alliances, and climate are explicitly **out of scope** until this loop is proven — see design doc Section 11.

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
- **There is no animal sprite in any vendored art pack** — see "The deer sprite" below for what was done about it. Stumps reuse the branch icon; spent graves reuse the second tombstone variant.

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

### The deer sprite

**No vendored art pack contains a quadruped.** Both Kenney roguelike sheets were checked tile by tile before concluding this: `art/roguelikeSheet_transparent.png` is terrain, buildings, furniture, fences, market stalls and UI bars; `art/roguelikeChar_transparent.png` is paper-doll parts (heads, torsos, hair, shields, weapons). There is a roast bird and a fish, but those are food *items* — which was exactly the problem, since the deer had been standing in as the raw-meat icon and read as a floating steak rather than something you hunt.

So `art/creature_deer.png` is generated: a 32×32 side-view silhouette plotted with the `Image` API by **`tools/make_deer_sprite.gd`**, run with `godot --headless --path . -s res://tools/make_deer_sprite.gd`. The generator is kept in the repo rather than run-and-deleted so the placeholder stays tweakable, and it carries the shape/colour reasoning in its comments (including two rejected attempts at a pale belly stripe that read as a saddle blanket). It is **still a placeholder** — it just needs to read as a living animal. Nothing depends on the script at runtime, only on its output PNG.

One gotcha it hit: **`_set` is an `Object` virtual** (`_set(StringName, Variant) -> bool`). Naming a pixel-plotting helper `_set` fails to parse with "function signature doesn't match the parent". It's called `_px` now.

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

## File map

```
project.godot              Godot project config, autoloads registered here
scenes/Main.tscn            Root scene (minimal — logic lives in Main.gd)
scripts/Main.gd              Wires all systems together + debug UI + build menu
scripts/autoload/           GameState.gd, EventBus.gd, BuildingCatalog.gd, RaceCatalog.gd (singletons)
scripts/settlement/         SettlementGrid.gd, Building.gd, FollowerToken.gd, WorkerSystem.gd, WorkerToken.gd,
                            Laborer.gd -- base class: the trip loop + labor stats
                            Worker.gd  -- extends Laborer (so does Follower, in scripts/bounty/)
							  ResourceNode.gd, ResourceField.gd
scripts/world/              DayNightCycle.gd (phase clock, CanvasModulate tint, debug time scale)
tools/                      make_deer_sprite.gd -- one-off art generator, not runtime code
scripts/bounty/              BountyBoard.gd, Bounty.gd, Follower.gd
scripts/threat/               ThreatSystem.gd
scripts/events/                EventSystem.gd, RecruitGenerator.gd
scripts/missions/            MissionSystem.gd
scripts/GameCamera.gd     Pan (right-drag)/zoom Camera2D controller
addons/godot_mcp/           Third-party MCP bridge plugin (mkdevkit, MIT) — Godot-editor side
data/events.json               15 MVP random events
data/missions.json            4 MVP party missions
data/followers.json           SUPERSEDED recruit templates -- only the off-timer events.json entries still use these
data/races.json               Race roster from RACES.md: stats, labor skills, alignment, rarity, housing style, rivalries (loaded by RaceCatalog)
data/buildings.json           Building catalog: costs, prerequisites, "locked" and "unique" flags, Barracks capacity
data/recruitment.json         Recruit tuning: rarity-by-power table, stat-roll dice, exceptional chance, first-run categories
art/, Buildings/, Characters/    Placeholder sprites (see README for provenance/upgrade path)
art/creature_deer.png       Generated, not from a pack -- see tools/make_deer_sprite.gd
```

## Next milestones (not yet built)

- Real UI (replace the code-built debug UI with a proper `.tscn`-based interface once validated in-editor)
- Multi-cell building footprints (everything is 1x1 on the grid for now)
- Housing capacity limits (currently a pure hard gate — species is unlocked or not, no cap on how many of that species you can have once housing exists)
- Physical gathering *buildings* / per-node worker capacity (workers now walk to real map nodes, but there's still no Lumber Camp/Quarry building layer and no hard cap on how many workers can share one node — `claims` is only a soft spreading hint)
- Manual per-worker override on top of the priority list (GAME_OUTLINE Stage 1 flags it as a possible later add)
- Replanting trees (FOUNDATION_SPEC §5: if wood scarcity bites, the planned fix is a manual replant-seeds action, explicitly *not* automatic regrowth)
- Dawn/dusk **meal ticks** — the last unbuilt piece of FOUNDATION_SPEC §7. The clock, the phases and both signals are in place (see "Day/night, finished"); what's missing is the food/morale system they'd drive, which needs living recruits to exist first (outline gap #3)
- Real deer art (and a real animal set generally) — `art/creature_deer.png` is a generated placeholder
- Climate system (deliberately deferred — see "Current phase" above)
- Save/load
- Remaining villain classes and climates (Phase 2, per design doc)
- Unique undead-themed building art per housing type (currently reusing the Kenney fantasy House/Tower/Castle packs with color-variant reuse as a placeholder — see `data/buildings.json` `sprite_path` fields)
