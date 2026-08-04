# Claude Code Prompts — Roguelite Rework, Stage R1 ("The world exists")

Run **one at a time, in order**, from `C:\Users\sjodz\Warlords`. Same standing rules as the foundation and Core Feel sets: read `CLAUDE.md` first, leave the game runnable, smoke test, update `CLAUDE.md`, **commit with a descriptive message**. Playtest between prompts and feed failures back as targeted bug prompts with exact log output.

Design sources: `ROGUELITE_REWORK.md` (§5 the sortie loop, §11 the per-villain constraint, §12 the impact table, §13 the stage plan) and `WORLD_MAP_PLAN.md` (the map spec, adopted with the rework's three amendments). `FOUNDATION_SPEC.md` / `RACES.md` remain authoritative for the settlement layer, which R1 does not touch.

Standing warning: if the game ever launches as a blank window, check `scenes/Main.tscn` for its `script = ExtResource(...)` line before debugging GDScript.

> **Note on the map spec.** `ROGUELITE_REWORK.md` cites `Warlords_World_Map_Scale_and_Exploration_Plan.docx`, which Claude Code cannot read (its Read tool is text-only). The prompts below point at **`WORLD_MAP_PLAN.md`** instead — a faithful markdown conversion sitting beside the original .docx, with the rework's three amendments flagged in its header. Keep both; edit the .md, since that's the one the tooling reads.

---

## Why R1a is first

R1 is the only rework stage blocked on nothing, and inside R1 the Necromancer data/view split is the piece everything else waits on. `ROGUELITE_REWORK.md` §5 says it outright: *"He needs a data object (position, hp, carry, escort roster) with the token as a pure view, before any world-map work begins."* `CLAUDE.md` predicted this exact migration trigger and it has now fired.

It's also the only R1 piece that is **fully testable in the game as it exists today** — a 10×8 settlement is enough to prove direct control, camera follow, and a killable villain. Building the 144×144 map first would mean doing the split later, inside a much larger blast radius.

**Not in R1, at all:** encounters, loot, relics, reputation axes, the Raven, recruit rework, run start/end lifecycle, map shuffle, escort behavior. Those are R2–R5. R1 proves you can walk out of the lair and back.

---

## Prompt R1a — The Necromancer becomes a unit

```
Read CLAUDE.md and ROGUELITE_REWORK.md (§5, §11, §12) first.

This is the documented NecromancerToken migration trigger firing. Scope is
the split plus direct control — no world map, no sorties, no escort. The
game must still be the current settlement build when you're done, just with
a Necromancer the player drives.

1. Split him, exactly like Laborer/WorkerToken. New data object
   scripts/villain/Necromancer.gd (RefCounted) owns: position, hp, Might,
   carry capacity and current carried load, an escort roster (empty array
   for now), and a class identity field ("necromancer"). NecromancerToken
   becomes a PURE VIEW — it reads necromancer.position and draws there,
   owns no state, decides nothing. Same contract the file map already
   describes for WorkerToken.

2. Per-villain state, per §11: this object is the ONLY home for villain
   state. Do not add necromancer fields to GameState or any other autoload,
   and do not write code that assumes exactly one villain exists — Main
   holds a reference to an instance, and anything that needs "the villain"
   takes it as a parameter. This constraint is the whole present-day cost
   of keeping the Demonologist and multiplayer possible; honour it now
   because retrofitting it later is the expensive version.

3. He is NOT a Laborer and must stay out of the labor pool. That's already
   structural (WorkerSystem.laborers() unions workers + followers and he's
   in neither) — keep it that way. Re-verify after the split.

4. Direct control — keyboard, hold to move. Deliberately NOT click-to-move:
   left-click is already inspection and build/demolish/rally placement,
   right-drag is camera pan, and adding a fourth meaning to a mouse button
   is how the input layer rots. Document that reasoning.

   THERE IS AN EXISTING CONFLICT TO RESOLVE: GameCamera._process already
   pans on WASD *and* arrow keys (scripts/GameCamera.gd, ~line 51). Split
   them — **WASD drives the Necromancer, arrow keys stay camera pan**, and
   remove WASD from GameCamera. While follow mode is on the two read
   almost identically anyway (moving him moves the view), and arrow-key pan
   drops follow exactly like a right-drag does. If you disagree with that
   split, say so before implementing rather than picking a third scheme.

   Movement speed as a const on Necromancer, tuned so he reads as faster
   than a Skeleton Worker (0.9 cells/sec) but not silly — start at
   1.4 cells/sec and flag it as a tunable.

5. Idle pacing survives, demoted. If there has been no movement input for
   ~8 seconds he resumes the existing slow wander within ~2 cells of wherever
   he's standing, so he still reads as alive. Any input cancels it instantly.

6. Camera follow, with an escape hatch. While following, the camera keeps
   him centred in the VISIBLE map band (reuse GameCamera.center_on and
   Main._sync_camera_insets — that band maths already exists and already
   survives zooming). Any manual right-drag pan drops out of follow
   (GameCamera.player_has_moved_camera is the existing flag); a key —
   suggest Space or F — snaps back and re-engages. Show the follow state
   somewhere small in the HUD.

7. He becomes killable — implement the Combatant contract from
   scripts/combat/Combat.gd (combat_name, combat_might, max_hp, hp,
   take_damage, is_alive, hp_fraction) on Necromancer so Combat.exchange()
   works on him with no special casing. max_hp stays COMPUTED from Might,
   never stored, same as every other combatant.
   - Death for now: emit an EventBus signal and log "THE NECROMANCER HAS
     FALLEN — the run would end here." Do NOT build the run lifecycle;
     that's R4.
   - The "wolves won't approach him" rule in CombatSystem stays, but move
     it behind a named const/flag (e.g. LAIR_AURA_PROTECTS_VILLAIN) rather
     than deleting or hardcoding it. §15 lists the lair aura as an open
     tunable and R2 needs to flip it off in the world; leave the switch.

8. Inspection panel: his entry now shows hp (current/max), Might, carry
   (current/capacity), escort count, and follow-mode state. Data comes from
   the Necromancer object via get_inspect_data(), actions stay in Main —
   the existing split. The token's get_inspect_data() should delegate to
   the data object, not duplicate it.

Smoke test (headless where possible, then real input — remember MCP
simulated input does NOT reach _unhandled_input, per CLAUDE.md):
WASD moves him and the token tracks with no lag or drift; camera follows,
drops out on right-drag, re-engages on the key; he still isn't in
laborers() or the workforce summary; Combat.exchange() against a wolf
damages him and the death signal fires at 0 hp; idle pacing resumes after
8s and cancels on input.
Update CLAUDE.md — including the migration note, which should now describe
the split as done rather than as a pending trigger. Commit.
```

---

## Prompt R1b — The world is 144×144

```
Read CLAUDE.md, ROGUELITE_REWORK.md (§4, §12, §13) and WORLD_MAP_PLAN.md
first. R1a must be done.

Build the world the Necromancer walks. FIXED LAYOUT — no shuffle, no
procgen. Shuffle is R4.

1. scripts/world/WorldMap.gd: 144x144 cells at the existing
   SettlementGrid.CELL_SIZE (64px) — a 9216px square. CELL_SIZE stays the
   one shared unit across settlement, world, and walk speed; do not
   introduce a second scale.

2. PERFORMANCE — the biggest trap in this stage. 144x144 is 20,736 cells.
   Do NOT instance a Node2D or a Sprite2D per cell for terrain or for fog.
   Use TileMapLayer for terrain and a single overlay (custom _draw, a
   generated texture, or a shader sampling a small fog image) for fog.
   If you find yourself writing a nested for-loop that calls add_child(),
   stop and reconsider.

3. Terrain, minimal: walkable ground, blocking terrain (mountain/water),
   and road cells that move faster than open ground. Layout comes from data
   (a JSON or a hand-authored tilemap resource), not from branches in
   GDScript. Movement must respect blocking — the Necromancer, the wolf and
   the deer all route around it.

   USE THE REAL ART, not coloured rectangles: "Official Sprites/
   Terrain_Tileset_Snow.png" is a 4x4 grid of seamless tiles — grass, three
   snow-over-grass variants, dirt, dirt-with-snow, a worn track, bone-strewn
   ground, three cobblestones, gravel, ice, and a ritual circle. Slice it
   into a TileSet and map those to the ground/road/blocking categories.
   Note the snow tiles are cold-hideout FLAVOR, not the climate system —
   CLAUDE.md's scope call that climate is deferred still stands, and this
   prompt must not start implementing one.

4. The settlement becomes a band inside the world, not the world.
   SettlementGrid's 10x8 sits at a defined world origin; ResourceField.build()
   becomes the lair-band seeder within the larger map (§12) rather than
   "the map". Everything already placed — Throne, forest, deposit, graves,
   grove — must land exactly where it does today relative to the Throne.

5. Fog of war, three states: unexplored (opaque), explored-but-not-visible
   (dimmed memory — terrain remembered, no live contents), and visible.
   Reveal radius travels with the Necromancer; the lair band starts
   revealed. Fog is an overlay above the map and BELOW the HUD CanvasLayer
   — same layering lesson as the day/night CanvasModulate, which
   deliberately doesn't tint the HUD. Do not put fog in hud_root.

6. Camera: extend zoom-out range so the player can see a useful chunk of
   the world, and clamp panning to the world rect so you can't pan into
   the void. Initial framing on the Throne is unchanged.

7. Keep the settlement layer working untouched. Workers still walk to lair-
   band nodes, day/night still runs, and — check this specifically — the
   wolf must still enter near the lair, not at a random point in a 144x144
   map. CombatSystem's spawn logic assumes a small map; fix it to spawn
   relative to the settlement band.

Smoke test: headless run confirms 144x144 bounds, no per-cell nodes (log
the child count of the terrain node), workers complete trips normally, and
the wolf spawns within the documented distance of the lair. Then a real
run: walk out of the lair band, watch fog clear behind you and stay
remembered, walk into a mountain and be blocked, walk a road and be
measurably faster. Log frame time with the whole map loaded.
Update CLAUDE.md. Commit.
```

---

## Prompt R1c — Places worth walking to, and the clock that makes it cost

```
Read CLAUDE.md, ROGUELITE_REWORK.md (§4 amendments, §13 R1 exit) and
WORLD_MAP_PLAN.md (§3 travel-time targets, §5 region allocation, §6 bands)
first. R1b must be done.

Populate the world enough to prove the travel loop, and tune it against the
doc's travel-time targets. Still NO encounters, loot, or reputation — R2.

1. The village, static per amendment 2. A cluster of static human buildings
   at its designated spot: no homes, no market, no inn, no daily routines.
   One or two patrol loops built on the existing Roaming.gd. Patrols are
   scenery in R1 — they walk, they don't react. Reuse the inspection
   contract so village buildings and patrols are clickable and say what
   they are.

2. The rival region ships sealed, per amendment 1. Reserve the 20x20
   territory in the layout and place a dormant/sealed ritual ground marker
   there. It is inspectable ("something else sleeps here") and does nothing
   else. No AI, no spawns.

3. Danger bands as data only. Tag world regions with the map doc's four
   bands and surface the band in a small HUD readout so the player always
   knows how deep they are. Nothing consumes the band yet — it's the hook
   R2's encounter and loot tables plug into.

4. Orientation. The player must not get lost in 9216px: add a minimap or a
   world-position readout, and make the lair findable from anywhere (a
   compass arrow or a minimap marker). Fog-remembered terrain should show
   on the minimap; live contents should not.

5. TUNE AND MEASURE — this is the actual exit criterion. Instrument travel
   so a run logs real elapsed times, then report each of these against
   WORLD_MAP_PLAN.md §3's table (all uninterrupted, against a 30-minute day):
     lair -> nearby resource            10-20 sec
     lair -> first worthwhile encounter 20-40 sec
     lair -> edge of local territory    45-75 sec
     lair -> human village              2-4 min
     full map crossing                  3-5 min
   If numbers land outside a band, adjust the Necromancer's walk speed const
   and/or the village's placement, and say what you changed and why — do not
   silently retune and call it done. Note the 20x20 lair region and 35x45
   human territory from §5 are what make those first three targets
   achievable; if you have to move the village a long way to hit 2-4 min,
   the walk speed is the wrong knob and the region sizes are the right one.

6. Verify the day/night interaction, because it's supposed to come free:
   a round trip to the village should be able to run into dusk, and the
   wolf spawn, and a meal tick. Confirm in a real playtest that leaving at
   the wrong hour is a real decision.

R1 exit criteria to check off explicitly in your summary:
walk from the lair to the village and back inside the travel-time targets,
fog clearing as you go, day/night pressuring the trip.
Update CLAUDE.md. Commit.
```

---

## After R1

Playtest for the feel question the stage exists to answer: **does leaving the lair feel like a decision?** If the walk is boring rather than tense, that's R2's job (danger bands, encounters, unbanked loot) — but if the walk is *tedious*, that's a travel-speed or map-density problem and it must be fixed before R2 builds on top of it.

R2 prompts should be written after that playtest, not now.
