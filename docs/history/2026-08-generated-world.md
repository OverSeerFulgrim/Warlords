# The world stops being drawn and starts being generated (P1, final)

`tools/make_world_map.gd` was 356 lines of hand-drawn line segments: `for x in range(86, 120): _put(x, 64, "C")`. It is now TERRAIN_SPEC §8's nine-step pipeline, and the layout is **produced by rule** rather than typed. Same fixed seed, same layout every run — this changes how the map is made, not how often. Shuffle is still R4, and after this it is a change to steps 4–5 only.

## The order is the argument

```
1 base terrain   2 relief   3 hydrology   4 FORESTS   5 landmarks
6 cobble A*      7 dirt A*  8 dressing    9 bake
```

Three orderings are load-bearing and each one paid off during the build:

- **Crossings are reserved before roads exist**, so step 6's A* is *forced* over the bridges hydrology already placed rather than inventing a ford wherever it wants one.
- **Forests go down before anything human**, so roads route around the woods. Painting trees after the roads would mean drawing a road and then pretending it went around something.
- **Dirt branches off the cobble network**, not out of the lair. That is the fiction in one line: a human landscape the Necromancer is hiding inside, rather than a wheel with him at the hub.

## The forests

Three dense masses (`T`, blocking) at **8.6% of the map** — §6b's 8–14% band — each with a 1–3 cell open-woodland fringe, a corridor carved through it, and one or two interior clearings. Blocking, not slow: *a forest you can shuffle through at 0.5 speed is not a wall and creates no paths; it's a big marsh.* The wall is what makes the gap mean something.

**Two clearings survive as sealed interiors**, each with exactly one corridor mouth — asserted structurally, not trusted: the harness finds patches of ordinary ground whose every outside neighbour is forest, then counts the connected groups of woodland touching them. Zero mouths is a softlock, two is a crossroads, and a crossroads inside a wood is just a road. These are where R2a's wolf dens land.

The canopy is **one `MultiMeshInstance2D` with 3,782 instances and zero children**. 1,791 dense cells at two trees each as `Sprite2D` nodes would be the exact trap R1 documented and removed. Position and scale are hashed from the cell — never `randf()`, or the forest reshuffles every boot — in the 1.9–2.6 tile band, and `ResourceField`'s gatherable pines go 96 → 128 in the same commit so the lair's trees and the world's read as one species.

Three bugs on the way in, all mine, all instructive:

1. **z_index is relative.** `-9` on a child of a node at `-10` is `-19` — under its own ground. It drew forest floor and no trees.
2. **The canopy is a child of WorldMap, which sits at `origin_px`.** Using `cell_origin_px()` double-counted the offset and put every tree thousands of pixels off the map.
3. **Forests ate the frozen lakes.** The skip list had rock and water but not ice.

## Hydrology, and the third wall

A river across the contested wilderness with three crossings: a **bridge at y=64**, where the human road actually crosses (fast, exposed, what patrols will walk in R3), and two **fords** (0.7, unwatched). No two adjacent crossings more than 25 cells apart — a rule, not a preference, and my first placement at 30/55/80% of the course was 31 apart and over the line.

**The river moved twice, and both moves were the map telling me something.**

Sourced at (58, 20) it ran down the Necromancer's own valley. Open water is blocking, so it became the nearest impassable thing east of the lair — *"edge of local territory"* measured the river at 33 cells instead of the ridge at 50, and the row fell out of band. A river in the valley is also simply wrong: that is the one region the map doc gives him.

Moved to (98, 16)→(88, 140) it crossed the Old Road's own longitude, so the trunk's A* found it cheaper to detour around the whole thing — down the west side of the ridge, through the valley, and back. **The Old Road ended up inside the Necromancer's territory** and the eastern network was cut off from it by the ridge entirely: four road components instead of one.

It now runs (108, 16)→(98, 140), between the road and the lordship, which is where §4's structure wants it. The trunk runs clean north–south at x≈86 and the run out to the village crosses at the bridge — the wall is on the route it is supposed to be a decision about.

Its course is also a **meander around a line, not a random walk**. `x += step + noise` accumulates; over 124 rows it wandered more than ten cells off course.

## Roads by A*, and the signposting rule by construction

Dijkstra over §8's cost grid — existing road **0.5**, so roads merge into a network instead of fanning out as spokes; open woodland 1.5 (a road may clip a treeline, reluctantly); marsh and boulder 4.0 (which is why real roads bend); cliff, dense forest and unbridged river impassable.

§7 is enforced by construction rather than by convention:

- cobble connects **only** `HUMAN_LANDMARKS` — a Band 4 site cannot be paved to because it is not on the list and cannot be added without someone noticing;
- dirt connects **only** sites tagged `signposted: true` in `world_sites.json` (three Band 1–2 sites now are);
- the generator **hard-errors** on a Band 3–4 site that sets it. Verified by temporarily flagging the sealed ritual ground: it errors, and — after a fix — it now aborts the bake rather than erroring and writing the map anyway. `quit()` in a SceneTree is deferred, so the error alone did not stop the pipeline, which is worse than not checking.

One more bug worth recording: `_nearest_road()` counted the bridge as a road, so the village spur *started on the far bank* and never joined the trunk. A bridge is part of the network but it is a **door**, not somewhere a new branch may begin.

## The gate, and what I moved to pass it

R1's numbers were won by four deliberate changes and the village trip had two minutes of headroom. Marsh, a river that must be crossed and genuinely impassable cliffs all push those numbers up, so §9's knob order was used in order and **walk speed was never touched**.

| Journey | §3 target | Now | Was (R1) |
|---|---|---|---|
| lair → first landmark | 20–40s | 25s | 25s |
| lair → edge of local territory | 45–75s | **46s** | 45s |
| lair → the village | 2–4 min | **2m06s** | 2m02s |
| crossing the entire map | 3–5 min | **3m31s** | 3m20s |

Three things moved, in §9's order, each because a measurement said so:

1. **River crossing placement** (knob 1) — the two relocations above, and the spacing fix.
2. **Forest mass placement** (knob 2), twice. The south-east mass at (50, 88) reached y=72, putting dense forest inside the latitude band `measure_travel` scans, so the valley's frontier stopped being the ridge and became a tree at 8 cells — 15s against a 45s floor. And the mass at (96, 100) spanned x80–112, closing the only gap between the ridge and the river the trunk could run down. **§9's stacking warning was right twice**: a mass placed against a tuned route quietly redefines it.
3. **Cliff outlines** (knob 4) — `RIDGE_X` 74 → 77. Routing the lair's track with A* instead of drawing it by hand made it straighter, so the measured line rides more 1.2-speed track and came in at 43s. Three cells is the smallest change that clears the floor, and it bought the village trip headroom it also wanted.

Landmark positions were never touched, and neither was walk speed.

## Verification

`tools/verify_terrain.tscn`, **254 assertions, all passing**, gains §12's generation half: every road network connected (flood fill from the lair reaching village, manor, church and cemetery on road cells); **no path of any kind within 3 cells of a Band 4 site**; ≥2 river crossings none more than 25 apart, with both a bridge and a ford; flood fill from the lair sealing off no region; dense forest at 8–14%; nothing paved inside a wood; every clearing with exactly one mouth; the canopy one MultiMesh within its instance budget.

Two assertions I had to correct, because they were asserting the *opposite* of what the design wants:

- **"exactly two ridge gaps"** counts road crossings too — the generator paints roads last, deliberately, "so a road can cut through a ridge". It now asserts the two *designed* doors are open and the wall between them is intact.
- **"2–4 dense masses"** counted connected components, and **a corridor cut clean through a mass splits its dense region in two by construction**. Asserting 2–4 would have been asserting that the corridors had failed.

Also green: `measure_travel` (above), `verify_stats` 505/505, `check_sprite_scales` 41/41 (tree assertions updated with the new sizes), `check_fog_and_minimap` 41/41, `verify_combat_feedback` 31/31, boot clean.

## Needs a human

The three questions a harness cannot answer:

- Do the roads actually **read as leading somewhere** at world zoom?
- Can you get from the Throne to the village **with the minimap off**, following the ground alone?
- Does walking a dense mass's treeline turn up a **corridor mouth before it turns up frustration**?

And one thing to look at with a designer's eye: the map now has 26.4% blocking, up from 16.9%. Every row is in band and nothing is sealed, but a quarter of the world being wall is a bigger change to how it *feels* than any single number here shows.
