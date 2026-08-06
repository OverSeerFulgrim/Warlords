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

