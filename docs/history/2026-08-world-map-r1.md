### The world the Necromancer walks (rework R1: the 144×144 map, fog, terrain)

The region from `WORLD_MAP_PLAN.md` §2, built as a **fixed layout** — no shuffle, no procgen; shuffling is R4. The settlement stops being the map and becomes a band inside one.

#### One scale, and where the settlement sits

`SettlementGrid.CELL_SIZE` (64px) stays the single unit across settlement, world and walk speed. **There is deliberately no second scale**, so walk speed 1.0 is one cell/second everywhere and the map doc's travel-time targets are a division rather than a conversion. 144 cells = 9216px ≈ 2.4 minutes straight-line, inside the 3–5 minute crossing target once terrain and detours exist.

**The engine origin stays the Throne's corner cell, and the world map is offset around it** (`WorldMap.origin_px` = `-lair_origin × 64`, currently cell (18, 56)). The alternative — moving the settlement to its world position — would have meant auditing every `get_global_mouse_position()` call in the project, because that returns *global* space and every settlement child position is settlement-local; today they coincide, and one missed conversion is a silent click-offset bug. So world cells are the derived coordinate system, and `WorldMap.cell_at()` / `cell_origin_px()` do the arithmetic so callers never do. Consequence: every existing position — worker trips, the forest, the graves, the wolf's entry point, click hit-tests — is untouched, which is what makes "keep the settlement layer working" true by construction rather than by testing.

`ResourceField` is the lair-band seeder now (rework §12) rather than "the map". Its code didn't change: everything in it was already placed relative to `grid_w`/`grid_h`, which is exactly why nothing moved.

#### The performance trap, and how it's avoided

20,736 cells. **No node per cell, anywhere.**

- **Terrain is one `TileMapLayer`.** 20,736 `set_cell` calls at load — those are dictionary writes into the layer's own storage, not scene-tree operations — and one child node. Measured: 52 draw calls with the whole map loaded, 226 nodes in the tree, 1.3 ms average frame.
- **Fog is one node and one 144×144 `Image`** — literally one pixel per cell — uploaded to an `ImageTexture` and stretched over the map in a single `draw_texture_rect`. A move costs a few hundred pixel writes and one 82KB upload, and only when the villain crosses a cell boundary.
- `Main._build_ground_background()` is **gone**: it was a `Sprite2D` per cell, which nobody noticed at 80 cells and would have been 20,736 orphan nodes here. That nested `add_child` loop was the exact shape of the trap.

#### Terrain is data, and it's the real art

`Official Sprites/Terrain_Tileset_Snow.png` — 1254px square, 4×4 tiles, **5px margin and 8px gutters, so 305px per tile** (measured off the file, not assumed). `WorldMap._build_atlas_texture()` slices it once at load and resamples each tile to 64px with Lanczos into a gutter-free 256×256 atlas. The alternative — pointing the TileSet at the full-size sheet and scaling the layer by 64/305 — keeps more detail but minifies on the GPU with no mipmaps, which shimmers while panning.

Filtering is split on purpose and the two reasons are opposite: **terrain is nearest** (the atlas is packed edge-to-edge, so linear would sample across a tile seam), **fog is linear** (it's an alpha mask, so interpolation gives a soft one-cell falloff instead of a staircase).

Layout lives in **`data/world_map.json`**: `width`/`height`, `lair_origin`, `lair_band`, a `legend` mapping one character to `{tile, category, speed, name}`, and 144 row strings. The runtime has **no layout knowledge in GDScript** — `WorldMap` reads the legend and rows and doesn't know where the village is. Three categories: `ground`, `road` (a speed multiplier), `blocking`. Adding "marsh: walkable but slow" is a JSON edit, not a new branch.

`tools/make_world_map.gd` generates that file (`godot --headless --path . -s res://tools/make_world_map.gd`), same arrangement as the deer-sprite generator: 20,736 cells is too many to type and too few to deserve a procgen system, so the layout is expressed once as WORLD_MAP_PLAN §4's regions and baked. Fixed seed, so the layout is identical every run. Re-run it after editing and commit the JSON.

- **Ground cover is picked in patches, not per cell.** Independent per-cell picks rendered as television snow — four quite different tiles alternating every 64px, the eye reading noise instead of terrain. A hashed 4×4 patch coordinate makes neighbours agree (drifts, outcrops), with a 25% break-out so patch edges stay ragged rather than a visible quilt.
- **The snow is flavor, not climate.** CLAUDE.md's climate scope call still stands: nothing reads these tiles for temperature and nothing should.
- **Rocky scree stands in for mountains** — the sheet has no mountainside tile. It is the one terrain placeholder; a real cliff/mountain tile belongs in the art brief.
- The map carries the structure the docs asked for: Old Road north–south, crossroads into the village, Southern Road past the church, a worn track from the lair out to the network, the human lordship east, the Northern Wilderness, a western range and a central ridge **with two gaps** (a wall with a door is a route decision; a wall without one is a smaller map), two frozen lakes, and the Demonologist's **sealed** ritual ground in the south-west (rework §4 amendment 1 — terrain only, no rival).

#### Blocking, and one slide for everything that moves

`WorldMap.slide(from, motion)` refuses blocking cells but slides along them — full motion, then x-only, then y-only. The axis retries are what make a wall feel like a wall instead of flypaper. **Everything that moves uses it**: the Necromancer directly, and the wolf and the deer through `Roaming.step(..., world)`, so predator and prey round a boulder the same way. `Roaming.random_point_in(rect, world)` retries for a walkable target, and both roamers re-target if a step leaves them where they started rather than grinding at a cliff all night.

Out-of-bounds is *not walkable*, which is what stops anything leaving the world without a second fence. The lair band is guaranteed blocking-free by the generator, so **workers need no pathfinding** — the trip loop is untouched.

Roads: `speed 1.35` on cobblestone, `1.2` on the worn track. Tunable. The map doc's §9 tradeoff is "roads are faster but expose you", and the exposure half arrives with R3's patrols — so this number wants revisiting once there's a cost.

#### Fog of war

Three states: unexplored (opaque), remembered (dim — terrain you've seen, no live contents), visible. Reveal radius travels with the Necromancer at 7 cells. *[Corrected 2026-08-06: this line originally cited the map doc's 8–12 cells as "the Raven's scouting number, and that's R2" — a misreading. Rework §4 amendment 3 deleted the directed-scouting model entirely; the R2 Raven is passive pings only and clears no fog, and directed scouting is deferred post-v1 (rework §6). Fog clears only through the Necromancer's own travel.]*

- **The lair band never dims.** Fiction: it's his own domain. Mechanics: the settlement layer is a management screen, and having the workforce vanish into haze the moment he leaves the valley would break the half of the game that already worked.
- **Layering:** a child of the settlement layer with `z_index` 100, so it covers terrain, buildings and units — and, being an ordinary Node2D, it stays under the HUD's `CanvasLayer`. Same lesson as `DayNightCycle`'s `CanvasModulate`, which darkens the settlement and leaves the HUD legible. **Not in `hud_root`.**
- "No live contents" is done by painting over rather than each unit testing the fog, plus **one guard in `Main._inspect_at`**: you cannot inspect anything standing in a cell that isn't currently visible. Clicking into fog closes the panel, exactly like clicking bare ground.

#### Camera

`zoom_min` 0.35 → **0.12** (a 1400px window now covers ~180 cells, so the whole region fits with margin). Panning and zooming clamp to `world_bounds`, done in code rather than with `Camera2D`'s built-in `limit_*`: those clamp what is *drawn* while leaving `position` free to wander, which turns a drag into a dead zone that lurches when you come back. An axis where the world is smaller than the view is centred instead of clamped. `center_on` clamps too, so following him into a corner shows the corner rather than the void — he drifts off exact centre there, which is correct. Initial framing on the Throne is unchanged and still lands dead centre (the Throne is 18 cells from the west edge, well clear of the clamp at default zoom).

#### The wolf still comes to the lair — and why nothing had to change

`CombatSystem.spawn_wolf()`'s entry point is `grid_w + 2 cells` east of the settlement, and its prowl rect is likewise built from `grid_w`/`grid_h`. Because the settlement kept the engine origin, **that is still ~12 cells from the Throne on a 144-cell map exactly as it was on a 10-cell one** — verified, not assumed. Anything added there must stay relative to `grid_w`/`grid_h` for the same reason: a wolf spawned relative to the *world* would arrive two minutes' walk away and never be seen. The wolf now also carries a `world` reference so it prowls around terrain.

#### Verification

A headless-and-windowed scene harness, **41 assertions, all passing**: 144×144 bounds and a 9216px square; one `TileMapLayer` with zero children and 20,736 painted cells; 191 nodes in the whole tree; the Throne still at (32, 32) and sitting on `lair_origin`; all 30 seeded resource nodes walkable and inside the band, with the stone deposit still at its exact old offset; blocking stops him and the diagonal slides 127px along the ridge; **1.35× measured on the road** (89.6px vs 121.0px in one second); fog starting at 678 revealed cells, growing to 1090 after a walk, ground behind him REMEMBERED and unvisited country UNEXPLORED while the lair band stays VISIBLE; camera clamped at both corners; the wolf spawning 11.7 cells from the Throne inside the band; **a worker completing a full trip and banking 4 wood**; day/night still ticking; and 52 draw calls / 1.3 ms average frame with the whole map loaded.

Notes worth keeping:

- **The `_set` trap bites again.** Naming a grid-writing helper `_set` in the generator fails to parse — `_set(StringName, Variant) -> bool` is an `Object` virtual. This file already recorded that from the deer sprite; it's `_put` now.
- **A harness that spawns a wolf and then runs 25 minutes of game time at 60× is flaky**, because the wolf can eat the only Skeleton Worker and take the worker-trip assertion with it. Despawn it between sections; the failure has nothing to do with what's under test.
- **`Performance.TIME_PROCESS` did not move between frames** in this harness (120 identical samples). Wall-clock deltas around `await get_tree().process_frame` with `Engine.max_fps = 0` and vsync disabled are the honest measurement, and `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` is the number that actually proves terrain is batched.
- **Dump the sliced atlas to a PNG when tiles look wrong.** A margin or separation off by a few pixels shows up there and nowhere else — it's how the 5px/8px/305px numbers above were confirmed rather than guessed.

**Needs a human:** walking out of the lair band with WASD and watching fog clear behind you, being stopped by the ridge, and feeling the road. Simulated input reaches neither `_unhandled_input` nor `Input.is_key_pressed` (see "Known constraint").

