# Claude Code Prompts — Roguelite Rework, Stage R2 ("The world is worth exploring")

Run **one at a time, in order**, from `C:\Users\sjodz\Warlords`. Same standing rules as the
foundation, Core Feel and R1 sets: read `CLAUDE.md` first, leave the game runnable, smoke test,
update `CLAUDE.md`, **commit with a descriptive message**. Playtest between prompts and feed
failures back as targeted bug prompts with exact log output. Session write-ups go to
`docs/history/`, never into `CLAUDE.md`.

Design sources: `ROGUELITE_REWORK.md` (§1 banking, §5 sortie loop, §6 the Raven, §8 loot, §11 the
per-villain constraint, §12 impact table, §13 the stage plan), `COMBAT_SPEC.md` (its 2026-08-06
amendment block adopts slice C2 into this order; §2–§4 and §7-as-amended are prompt C2's design
source), and the seven R2 specs — `TERRAIN_SPEC.md` (forest amendment included),
`LOOT_SITES_SPEC.md` (wolf-den amendment included), `SORTIE_SPEC.md`, `ESCORT_SPEC.md`,
`RAVEN_SPEC.md`, `NECROMANCER_SPEC.md`, `COMBAT_FEEDBACK_SPEC.md`. `FOUNDATION_SPEC.md` /
`RACES.md` remain authoritative for the settlement layer, which R2 does not touch (`RACES.md`'s
stat table is re-authored by prompt C2's export, per COMBAT_SPEC §12).

Standing warning: if the game ever launches as a blank window, check `scenes/Main.tscn` for its
`script = ExtResource(...)` line before debugging GDScript.

---

## ⚠ Gate — the order these run in matters

**The R1 feel playtest comes first, and P1 is why.** `ROGUELITE_PROMPTS.md` closes with *"R2 prompts
should be written after that playtest, not now,"* and the question it answers is the one everything
here builds on: **does leaving the lair feel like a decision?**

P1 and P2 **change the map** — new terrain, real cliffs, a river, a generated road network. Playing
after them means judging a different world than the one R1 tuned. So:

```
playtest R1  →  P0 (safe anytime, changes no gameplay)  →  F1 (damage numbers — safe anytime)
             →  C2 (the stat rework — combat only, map untouched)
             →  P1  →  P2  →  R2a (sites + dens) → R2b (his own hands) → R2c (getting it home)
             →  R2d (escort) → R2e (raven)
```

F1 sits early on purpose: it changes no gameplay, and every fight after it — the dusk wolf, den
packs, guardians, the villain's own casting — is legible during its own playtest instead of only
in the log. (It was briefly labelled C1; renamed because `COMBAT_SPEC.md`'s slice C1 is a
different, already-shipped thing.)

C2 sits before the terrain and R2 prompts because everything from R2a on **consumes stats** —
guardians, dens, the villain's kit, party capacity, escort hauling. Build those on
`combat_might()` and every harness gets written twice. It sits *after* the R1 playtest gate
trivially: it changes combat, not the walk.

If the walk is *boring*, that is R2's job and these prompts are the fix. If the walk is **tedious**,
that is a travel-speed or density problem — fix it before P1, because P2 re-tunes travel and needs a
known-good baseline to tune against.

---

## Decisions already made, so no prompt has to re-litigate them

- **Reputation is per-villain; threat stays global.** The five axes (`ROGUELITE_REWORK.md` §7) live
  on the villain object per §11. World-level threat and escalation stay in `GameState`, because the
  world reacting is not villain state. This makes `LOOT_SITES_SPEC.md` §2's `GameState.add_threat()`
  call legal and `CLAUDE.md`'s "single source of truth for … reputation" line **wrong** — P0 fixes
  the line.
- **The Raven does not clear fog.** `docs/history/2026-08-world-map-r1.md` says the 8–12 cell number
  is the Raven's and lands in R2. It isn't and it doesn't — see `RAVEN_SPEC.md`'s correction block.
  P0 fixes that too.
- **Density budget is ~10–15 active meaningful locations per run**, per `ROGUELITE_REWORK.md` §4
  adopting map doc §12 — *not* §7's 12–20 possible encounter sites, which is the pool the run draws
  from.
- **Band 4 sites get no paths — found, not followed** (`TERRAIN_SPEC.md` §7). Cobble leads to human
  places, dirt tracks lead to Band 1–2 minor sites, the crypt and outlaw cave get nothing. Enforced
  by the generator, not by convention.
- **Shuffle is still R4.** P2 rewrites *how* the layout is generated, keeping the fixed seed.
  `WORLD_MAP_PLAN.md` §11 asks for shuffled contents on a fixed scale, not procedural generation.
- **Dense forest is blocking, and clearings have exactly one way in** (`TERRAIN_SPEC.md` §6b).
  Forest corridors are carved `u` lanes, not roads; no path of any kind enters a dense mass or a
  clearing. World-canopy pines are paint — one MultiMesh, no nodes, not choppable.
- **The stat rework (C2) is adopted; carry = Endurance; creatures get all nine attributes.**
  `COMBAT_SPEC.md`'s 2026-08-06 amendment block is the record. The roster numbers are DONE —
  `stat_rework_roster.xlsx` — including the villain and wolf rows. C3 stays post-R2; C6 is
  retracted. No prompt re-litigates the attribute list or the derivation formula.
- **The villain has no attack button, and he is Arcane** (`NECROMANCER_SPEC.md` §2–§3).
  Starting a fight takes closing to the wolf's own 26px engage radius (or being hit); once
  engaged he casts at his 5-cell arcane reach — engage close, cast far. Walking out is
  disengaging. The lair aura becomes a position test against `lair_band` in R2b and the flag is
  deleted.
- **Clearing the last wolf den ends dusk raids for the run** (`LOOT_SITES_SPEC.md` §3b). The
  spawn entry point stays settlement-relative; dens explain the wolf, they do not path it.

---

## Prompt P0 — The travel retune, and three doc corrections

```
Read CLAUDE.md, docs/history/2026-08-world-population-r1.md (the measured
travel table and the "one row still out of band" note), and
docs/design/WORLD_MAP_PLAN.md §3 first.

This is a small correction pass before R2 proper. No new systems.

1. THE REGRESSION. tools/measure_travel.tscn reports lair -> nearby resource
   at 3s against WORLD_MAP_PLAN §3's 10-20s target, and the backlog flags it
   "retune resource placement or speeds before R2".

   Do NOT touch walk speed. It was tuned to 1.0 cells/sec against the map
   crossing and the village trip, both of which are in band, and moving it
   would break two rows to fix one.

   The population write-up already worked out the answer: §3's row is really
   about SORTIE-SCALE resources, and at 1.0 cells/sec the right ring is
   10-20 CELLS from the lair. The lair's own worker nodes are deliberately
   close (workers walk them every trip; a long haul would wreck the
   settlement economy's pacing) and must NOT move.

   So: distinguish the two in the harness rather than moving anything.
   Report "lair -> worker node" (expected: short, by design, with the
   reason) separately from "lair -> sortie-scale resource" measured to the
   10-20 cell ring. If no site exists in that ring yet, assert the ring is
   walkable and reachable in 10-20s and leave the row pending for R2a.
   Say clearly in your summary which rows are now in band and why.

2. CLAUDE.md, architecture conventions: the GameState line currently reads
   "single source of truth for resources/reputation/threat/power/followers".
   Reputation is moving to the villain object (ROGUELITE_REWORK §7, §11) and
   threat is staying global. Reword to say exactly that, with a pointer to
   §11. Do not change any code in this prompt -- GameState.reputation stays
   as it is until R3 replaces it with the five axes; this is a docs fix so
   the convention line stops contradicting the design doc.

3. docs/history/2026-08-world-map-r1.md, fog-of-war section: it says the map
   doc's 8-12 cells is "the Raven's scouting number, rework §6, and that's
   R2". That is wrong -- ROGUELITE_REWORK §4 amendment 3 replaced the
   directed-scouting model entirely, and §6's Raven has no reveal radius.
   Correct the parenthetical and point it at docs/design/RAVEN_SPEC.md.
   The 7-cell villain reveal radius is unaffected and stays.

Smoke test: headless boot clean, measure_travel runs and reports the new
row split. Commit.
```

---

## Prompt U1 — Pointing at the map

*Added 2026-08-27 from the R1 playtest notes (`docs/history/2026-08-27-r1-playtest-notes.md`).
Map-untouched; runs after P0 and before F1 because every later playtest is nicer with it.*

```
Read CLAUDE.md, the header comments of scripts/ui/Minimap.gd,
scripts/world/FogOfWar.gd, scripts/GameCamera.gd, and the click-to-target
section of scripts/Main.gd (build / demolish / Command Undead modes) first.
Also docs/history/2026-08-27-r1-playtest-notes.md for why. P0 must be done.

Four small input/visibility fixes from the R1 playtest. No new systems, no
map changes, no economy changes.

1. MINIMAP CLICK. Left-clicking the minimap calls GameCamera.center_on()
   with the world position under the cursor (invert Minimap._to_map). Do
   not disturb "F to follow" unless it is already following, in which case
   a minimap click breaks follow exactly as a manual pan does
   (_note_manual_pan). The minimap must consume the click so it never
   reaches _unhandled_input as a world click.

2. RIGHT-CLICK TO MOVE THE NECROMANCER. Necromancer.gd is driven by a
   movement vector from held keys. Add a click destination: a right-click
   TAP on the world (press and release with < ~6px of drag and < ~250ms)
   sets `move_target` and he walks a straight line toward it at his
   normal speed, cancelled by any key input or arrival (reuse the arrive
   epsilon the idle pacing already uses). A right-click DRAG remains camera
   pan -- GameCamera._unhandled_input already handles MOUSE_BUTTON_RIGHT;
   put the tap/drag decision in ONE place so the two never both fire.
   Right-clicking the minimap does the same with the minimap-to-world
   inverse from step 1. No pathfinding in this prompt: straight-line, and
   terrain speed_multiplier applies as it does for keyed movement. If a
   right-click lands while a click-to-target mode (build/demolish/Command
   Undead) is armed, it cancels that mode and does nothing else -- same as
   those modes already treat a stray click. Read the movement-vector
   contract comment in Necromancer.gd (~line 156) and keep that function
   the single source of "where is he going": the click target should feed
   the same vector, not bypass it, so facing, idle-resume and pacing all
   keep working.

3. FRIENDLY UNITS LIGHT THE FOG. FogOfWar._relight() lights one disc of
   REVEAL_RADIUS_CELLS (7) around the villain and drops the previous disc
   back to REMEMBERED. Generalise it: update_for() takes a list of
   (position, radius) pairs, rebuilds the full lit set from all of them,
   and still early-outs when no source has crossed a cell boundary. The
   villain keeps 7. Add const UNIT_REVEAL_RADIUS_CELLS := 3 for every
   friendly unit -- WorkerToken, FollowerToken, and bound undead -- and
   have Main feed those positions each frame. Nothing becomes permanent:
   when a unit leaves, the cell goes back to REMEMBERED exactly as it does
   for the villain today. Keep the per-source cell-boundary early-out or
   this will not stay off the frame budget with 30+ undead; measure it
   with the bound-33 case from the playtest and say the frame cost in your
   summary. Do NOT change the villain's radius and do NOT touch
   reveal_permanently(). Update the RAVEN_SPEC "revealing the map remains
   the Necromancer's job" line to say "the Necromancer's and his people's
   job -- the Raven still reveals nothing".

4. FRIENDLY DOTS ON THE MINIMAP. Minimap.gd's rule is "no live contents".
   Amend it, in the header comment, to: no live HOSTILE or NEUTRAL
   contents -- wolves, deer, patrols stay hidden because seeing them
   through fog would undo it; YOUR OWN units are not intelligence about
   the world. Draw workers, followers and bound undead as 2px dots in a
   dim friendly colour (new const, keep it distinct from LAIR_COLOR and
   VILLAIN_COLOR at 3-4px on dark terrain). Draw them under the villain
   marker. Only draw a dot if its cell is currently VISIBLE or REMEMBERED
   -- it always will be after step 3, but assert it rather than assume it.

Smoke test: headless boot clean; the existing fog and minimap tests still
pass; add one test that a worker 20 cells from the villain lights a 3-cell
disc and that the disc returns to REMEMBERED when the worker is removed.
Play 2 minutes: minimap click jumps, right-tap walks, right-drag pans,
workers carry a small lit disc, dots appear. Commit.
```

---

## Prompt F1 — Red numbers

```
Read CLAUDE.md and the whole of docs/design/COMBAT_FEEDBACK_SPEC.md first.
P0 must be done. Safe to run before or after the R1 playtest -- it changes
no gameplay, only makes damage visible.

Floating damage numbers over every combatant, in real time.

1. EventBus.damage_shown(unit, amount, kind) -- kind "damage" or "heal".
   Emitted from CombatSystem only: per landed swing while walking each
   Engagement.tick() result (both directions of the exchange -- the numbers
   are already in the result Dictionary), and "heal" from Throne repair.
   Combat.gd and Engagement.gd are NOT touched; if you find yourself
   editing either, stop -- the formula and the clock stay signal-free.

2. New scripts/ui/CombatFeedback.gd per the spec's §3: one Node2D layer, a
   pool of at most 32 Labels, red -N (the project's 1.0/0.35/0.35 with the
   wolf label's 4px black outline), +N muted green for heals, spawned above
   the unit's drawn content height with ±6px jitter, rising ~0.5 cells over
   0.8s and fading. Driven by ONE delta accumulator in _process -- no Tween
   or SceneTreeTimer per float, so Engine.time_scale scales it like every
   other clock in the project.

3. unit is the DATA OBJECT, never a token -- read unit.position at emit
   time (the view-is-a-frame-stale rule). Floats do not follow the unit
   after spawning.

4. Mind the signal-arity gotcha when connecting.

Verification: tools/verify_combat_feedback.tscn per the spec's §5,
headless AS A SCENE not -s -- one emit per landed swing with the right
amounts, pool never exceeds 32, 1000 exchanges leak zero nodes. Smoke
test: spawn a wolf via CombatSystem.spawn_wolf(), watch a fight, confirm
the numbers read at 1x and blur harmlessly at 60x.
Update CLAUDE.md (file map, one line). Write up
docs/history/2026-08-combat-feedback.md and add its row to the history
README. Commit.
```

---

## Prompt C2 — The stat rework

```
Read CLAUDE.md, docs/design/COMBAT_SPEC.md IN FULL -- especially its
2026-08-06 amendment block, §2-§4, §7 as amended, and §12 -- and open
docs/design/stat_rework_roster.xlsx's Legend sheet first. F1 must be
done. This is COMBAT_SPEC's slice C2, adopted into this order by the
amendment block; do not re-litigate the attribute list, the governing-
attribute map, or the derivation formula -- they are decided and
authored.

Replace the four-stat model with the nine-attribute model, everywhere,
in one pass. The map is untouched; this is combat, labor and data.

1. EXPORT THE WORKBOOK. stat_rework_roster.xlsx is the source of truth:
   9 attributes x 17 races (plus the Necromancer and Wolf rows), six
   skill templates, per-race overrides, and the derivation formula
   effective_skill = skill + floor((attr - 5) / 2). Export to
   data/races.json per the workbook's own order-of-work sheet: templates
   and overrides land IN THE JSON, not in code. Write the exporter as
   tools/export_roster.gd (headless, committed) so the workbook stays
   the editing surface and the JSON stays derived.

2. THE COMBATANT CONTRACT widens per COMBAT_SPEC §4.1:
   combat_profile() -> {attack_attr, defence_key, reach_px} and
   combat_defence(key) replace combat_might(). Update
   Combat.is_combatant()'s method list IN THE SAME COMMIT -- it exists
   to make a half-migrated unit fail loudly. Combat.damage_roll() reads
   the attribute pair from the attacker's profile: melee Str vs End,
   ranged Dex vs Speed, arcane Int vs Int. EXCHANGE_INTERVAL, the d3,
   MIN_DAMAGE and both-swings-land are UNCHANGED.

3. Profiles per COMBAT_SPEC §3.1 rule 3 only (no classes, no gear):
   highest of Str/Dex/Int, ties to Strength. The wolf is Melee, the
   villain is Arcane (Int 7) -- both fall out of the rule; if either
   needs a special case, something is wrong.

4. max_hp = 8 + Endurance * 2. Carry = Endurance (Laborer AND
   Necromancer.carry_capacity()). Walk speed reads the Speed attribute
   through the workbook's divisor -- assert the tuned values survive:
   villain 1.0 (Speed 5), skeleton 0.9 (Speed 4), wolf chase from
   Speed 8. measure_travel MUST report every row unchanged; walk speeds
   moving is a failed export, not a retune.

5. What does NOT change in this prompt: FLEE_HP_FRACTION and all rout
   behaviour (that is C3, post-R2 -- the amendment block says why),
   judgement/guidance (C3), gear/classes/disease (unscheduled), the
   emergent-defence rule's SHAPE (but _will_fight's might >= 6 test
   rewords to Strength >= 6, per COMBAT_SPEC §6.2's note), wolf
   behaviour states, and every creature's effective numbers (End 4/5
   equal old Might by authored design -- assert skeleton hp 16, wolf
   hp 18, villain hp 20 before/after).

6. RecruitGenerator: rolls move to the nine attributes + template
   skills; the exceptional-roll rule targets the category-defining
   attribute (warrior -> Strength, economy -> best labor skill's
   governing attribute, research -> Intelligence, foraging ->
   Perception). Rarity weights, Barracks gate, offer machinery
   unchanged.

7. UI: InspectionPanel stat rows show the nine attributes compactly
   (group Physical / Social, skip untrained skills); the "Stats" line
   format is yours to lay out, but Might must appear nowhere after this
   commit -- grep for it.

Verification: tools/verify_stats.tscn, headless AS A SCENE -- every race
in races.json has 9 attributes and 12 resolvable skills; effective-skill
spot checks match the workbook's Effective skills sheet (Gray Dwarf
mining 9+0=9 -- Str 6 gives floor(1/2)=0; Ogre 6+2=8); profile assignment matches the
workbook's profile column for all 17 races + villain + wolf; damage_roll
reads the right pair for all three profiles; hp/carry assertions from
step 5; is_combatant rejects an object still implementing only
combat_might(). Re-run verify_sortie/verify_escort equivalents if they
exist yet (order says they don't -- fine), check_sprite_scales, headless
boot, and measure_travel (step 4's gate).
Update CLAUDE.md (the stats convention line already points here; update
the file map for export_roster.gd). Write up
docs/history/2026-08-stat-rework.md and add its row to the history
README. Commit.
```

---

## Prompt P1 — Seven sheets, and tiles that know their neighbours

```
Read CLAUDE.md, docs/design/TERRAIN_SPEC.md (all of it) and
docs/history/2026-08-world-map-r1.md (the terrain and performance sections)
first. P0 must be done, and the R1 playtest must have happened.

Six new tilesheets are already in assets/official/terrain/. Wire them, and
add the connection-tile layer. NO generation changes in this prompt -- the
layout stays exactly as authored; this pass changes how it is RENDERED.

1. DUMP THE ATLAS FIRST. Write tools/dump_atlas.gd, run it, and look at the
   output before writing anything else. It slices every sheet and writes a
   labelled PNG grid. TERRAIN_SPEC deliberately does NOT tabulate which cell
   holds which connection piece, because that has to be read off the real
   file -- R1's own write-up records that a margin or separation off by a
   few pixels shows up in the dump and nowhere else. Keep the tool
   committed; every future sheet needs it.

   All seven sheets are 1254x1254, 4x4, 305px tiles, 5px margin, 8px
   separation -- but ASSERT THAT PER FILE. One sheet measures a thicker
   outer border than the others and an assumption there silently shifts the
   whole atlas.

2. Grow the atlas: TILESET_PATH becomes a Dictionary of sheet id -> path,
   and _build_atlas_texture() loops sheets into one larger atlas (112 tiles,
   e.g. 8x14 at 64px). The per-sheet slicing maths does not change; only the
   destination offset moves. Keep the Lanczos resample and keep terrain
   filtering NEAREST (the atlas is packed edge-to-edge; linear samples
   across seams -- see the R1 write-up for why fog is the opposite).

3. Extend the legend per TERRAIN_SPEC §5, including marsh at speed 0.6.
   That is the first sub-1.0 speed in the project and it needs NO code
   change -- speed_multiplier() already returns a float and everything
   multiplies by it. Verify that rather than assuming it. The legend also
   gains T (dense forest, blocking) and u (open woodland, 0.85) from the
   forest amendment (§6b) -- in THIS prompt they are legend entries with a
   forest-floor tile and zero cells using them; the masses, corridors and
   canopy layer are P2's, where generation lives.

4. The connection layer, per TERRAIN_SPEC §3-§4. Semantic characters in the
   rows; a 4-bit orthogonal-neighbour mask picks the actual tile at load;
   the mask -> atlas-coord table lives in data/world_map.json, filled from
   step 1's dump. Roads and dirt paths share the connection group "road" so
   a track meeting a road forms a junction rather than a dead end. A MISSING
   MASK IS A HARD ERROR AT LOAD, not a fallback -- one silently-wrong corner
   in 20,736 cells is the bug nobody ever finds.

5. Apply it to what already exists, so this pass is visibly true:
   - the existing cobble roads and worn track get real junctions and corners
   - the central ridge converts from 'm' (rocky scree, blocking) to '^'
     (cliff, blocking), which closes the placeholder R1 flagged: "a real
     cliff/mountain tile belongs in the art brief". KEEP ITS TWO GAPS.
   - the two frozen lakes become 'I' (walkable ice, 0.85) rather than
     blocking -- a frozen lake you can cross is a shortcut, one you can't is
     a hole in the map
   Generate cliff outlines CONVEX; 16 tiles gives faces and outer corners
   only, and a concave notch would request an inner corner that doesn't
   exist.

6. PERFORMANCE, the R1 trap, restated: still ONE TileMapLayer with ZERO
   children, still no node per cell. The connection pass is one pass over
   20,736 cells with four neighbour lookups each, at load. If draw calls
   move much past 52 or frame time past 1.3ms, stop and say so.

7. SPRITE_SPEC.md: add one line recording that terrain sheets are outside
   its rules (they are full-res 4x4 sheets, not 256px canvas sprites with a
   y=224 baseline). The exception already exists in practice; write it down.

Verification: tools/verify_terrain.tscn per TERRAIN_SPEC §12, headless AS A
SCENE not -s -- per-file slicing assertions, 112 distinct atlas tiles with
no all-black cell (an all-black tile means an off-by-one), every legend
char resolving, every connection group having all 16 masks, and the node/
draw-call/frame-time invariants. Re-run measure_travel: the ice and cliff
changes can move routes, and any row out of band must be reported.
Update CLAUDE.md (graphics rules + file map). Write up
docs/history/2026-08-terrain-tiles.md and add its row to the history README.
Commit.
```

---

## Prompt P2 — Roads that lead somewhere

```
Read CLAUDE.md, docs/design/TERRAIN_SPEC.md (§6-§9 especially) and
docs/design/WORLD_MAP_PLAN.md (§3 travel targets, §4 structure, §5 regions,
§9 roads vs wilderness) first. P1 must be done.

Rewrite tools/make_world_map.gd so the layout is GENERATED BY RULE instead
of hand-authored. Fixed seed, same layout every run -- this changes HOW the
map is produced, not how often. Shuffle is still R4.

1. The nine-step pipeline in TERRAIN_SPEC §8, in that order: base terrain,
   relief, hydrology, FORESTS, landmarks, cobble network, dirt network,
   dressing, bake. Step order is load-bearing -- crossings are reserved
   before roads are laid, forests are laid before anything human exists so
   roads route around the woods, and dirt tracks branch OFF the cobble
   network rather than radiating from the lair, so the world reads as a
   human landscape the Necromancer is hiding inside.

1b. THE FORESTS, per TERRAIN_SPEC §6b -- this is the new step and the bulk
   of this prompt's new work:
   - 2-4 dense masses (T, blocking) with 1-3 cells of open-woodland fringe
     (u, 0.85), aiming 8-14% of the map dense. One mass east of the lair
     valley -- the "treeline" CombatSystem's wolf-spawn comment has always
     claimed. Keep masses OFF the two ridge-pass approaches and the lair
     track's line (§9's stacking warning).
   - corridors: 1-2 cell u lanes carved through each mass by A*, mouths on
     a side no more than ~25 cells apart. Corridors are NOT roads.
   - clearings: 1-2 per large mass, radius 2-4, ordinary ground, EXACTLY
     one corridor mouth each -- zero is a softlock, two is a crossroads.
     These are where R2a's wolf dens and better sites land.
   - the canopy layer in WorldMap: ONE MultiMeshInstance2D drawing
     Pine_Tree.png over T (~2/cell) and u (~0.3/cell) cells, deterministic
     per-cell hash jitter for position and for scale in the 1.9-2.6-tile
     band (via Anchoring.scale_for_content_height). Zero per-tree nodes.
     Not choppable, not inspectable -- paint.
   - the lair's own gatherable pines join the family: ResourceField's
     NODE_SIZE_TREE 96 -> 128 and NODE_SIZE_STUMP 32 -> 42, with
     check_sprite_scales' tree assertions updated in the same commit.
   - _clear_lair_band() learns T and u alongside m and i.

2. Hydrology (§6): a river across the contested wilderness, 1-2 cells wide,
   with 2-3 crossings -- a BRIDGE on the human road network (fast, exposed)
   and a FORD in the wilderness (0.7, unwatched). No two crossings more than
   ~25 cells apart. This is the ridge lesson again: a wall with a door is a
   route decision, a wall without one is a smaller map.

3. Roads by A* over the cost grid in §8: existing road 0.5 (so roads MERGE
   into a network instead of fanning out as spokes), open ground 1.0, open
   woodland 1.5, marsh and boulder field 4.0, cliff and DENSE FOREST
   infinite, river infinite except at a reserved crossing. AStarGrid2D is
   already used in measure_travel, so the pattern exists in-repo. A dirt
   track may end at a corridor mouth; nothing paved ever continues inside
   a wood.

4. THE SIGNPOSTING RULE (§7), enforced by construction and not by
   convention:
   - cobble connects ONLY entries in the human_landmarks list
   - dirt connects ONLY sites tagged signposted:true in world_sites.json
   - the generator HARD-ERRORS if any Band 3 or 4 site sets signposted
   The crypt, the outlaw cave and the cursed battlefield are found, not
   followed. Ruins terrain under a site is how it telegraphs instead -- that
   satisfies LOOT_SITES_SPEC §3 without a line leading to it.

5. Dressing: farmland around the village (map doc §4's sketch asks for
   Human Farms and R1 shipped without them), corrupted ground and the real
   ritual circle in the sealed region (§5's "ruined ritual ground, corrupted
   terrain"), ruins patches under ruin sites, marsh in the Necromancer's
   lowlands.

6. THE GATE, and do not skip it. R1's travel numbers were won by four
   deliberate changes (walk speed 1.4->1.0, ridge x40->x74, its pass
   y56->y36, village x108->x120) and the village trip has only two minutes
   of headroom in §3's 2-4 minute band. Marsh, a river that must be crossed,
   and cliffs that are genuinely impassable ALL push those numbers up.

   This prompt is not done until measure_travel is re-run and every row is
   back in band. If rows fall out, the knobs IN THIS ORDER: river crossing
   placement, then marsh extent, then cliff outlines, then landmark
   positions. WALK SPEED IS NOT A KNOB -- if the map has genuinely become
   too big, the honest fix is a smaller map, exactly as R1 concluded.
   Report what you changed and why; do not silently retune.

Verification: tools/verify_terrain.tscn gains §12's generation assertions --
every road network connected (A* from lair to village, manor, church and
cemetery entirely on road cells), NO path of any kind terminating within 3
cells of a Band 4 site, every river having >=2 crossings none more than 25
cells apart, cliff ranges convex, FLOOD FILL from the lair reaching every
walkable cell, every dense mass crossable with corridor mouths <=25 cells
apart, every clearing having exactly one mouth and no paved cell inside,
and the canopy being one MultiMeshInstance2D within its instance budget.
Re-run the generator and COMMIT THE JSON.
NEEDS A HUMAN afterwards: do the roads actually read as leading somewhere at
world zoom, can you get from the Throne to the village with the minimap
off, following the ground alone, and does walking a dense mass's treeline
turn up a corridor mouth before it turns up frustration.
Update CLAUDE.md. Write up docs/history/2026-08-generated-world.md. Commit.
```

---

## Prompt R2a — Sites worth stopping at

```
Read CLAUDE.md, ROGUELITE_REWORK.md (§8 loot, §13 R2) and the whole of
docs/design/LOOT_SITES_SPEC.md first. P2 must be done.

Build the lootable-site layer. This is the biggest R2 prompt; everything
after it is the loop closing around it.

0. FIRST, THE MINIMAP TOGGLE the P2 human check found missing (docs/
   history/2026-08-27-r1-playtest-notes.md, "P2 human check"): the M key
   toggles minimap visibility, default on, one TravelLog line when it
   changes. No other minimap change. The R2 exit walk ("Throne to village
   by ground alone") cannot be run without it.

1. Everything in LOOT_SITES_SPEC.md §2-§5 and §7-§8: the site type catalog,
   the interaction model (reach, InspectorActions surface, channelled
   looting, charges, guardians), the four-way grave choice sheet, loot
   tables in data/loot_tables.json, gold as the sixth GameState resource,
   relics in data/relics.json, and the site_choices.json grammar. The
   2026-08-29 amendment block at the top of the spec is BINDING and
   supersedes the body where they differ: three graveyard tiers replace
   the single cemetery (twelve types), the `arms` loot kind exists
   (human sites only), and the cache tables are gold-first with mundane
   demoted to garnish. Witnesses and haulage in that block are R3+/gear
   material -- do NOT build them here.

1b. THE WOLF DENS, per LOOT_SITES_SPEC.md §3b: 1-2 wolf_den sites in P2's
   forest clearings (one in the mass east of the lair valley), each with
   guardian {"kind": "wolf", "count": 2-3} -- SiteGuardians wearing
   Wolf.gd's stats and sprite, parked on a small prowl radius. Pack wolves
   that flee below 5 hp leave the run. Clearing the pack unlocks the den's
   one loot action (best wolfhide_cloak odds in the game), leaves the
   standard carcass per kill AT THE SITE, and emits a Power deed. THE DUSK
   GATE: CombatSystem._on_dusk asks WorldSites.any_den_uncleared() before
   rolling; the last den cleared means no more dusk raids this run. The
   spawn ENTRY POINT stays settlement-relative -- do not path wolves from
   dens. Den assertions per LOOT_SITES §10's harness paragraph.

2. DENSITY CAP: author to 10-15 ACTIVE meaningful locations (ROGUELITE_
   REWORK §4 adopting map doc §12). §7's 12-20 is the POOL a run draws from,
   and LOOT_SITES §2 cites the wrong one -- its amendment block records the
   correction. Let the pool/active_count schema carry the rest for R4's
   shuffle. Say in your summary what the final active count is.

3. TERRAIN, now that P2 exists. Sites sit on terrain that suits them: ruin
   pockets and the crypt on ruins tiles, the cursed battlefield on charred
   ground, the cemetery inside the church grounds. That is how a site
   telegraphs (LOOT_SITES §3) -- NOT by a path leading to it. Set
   signposted:true only on Band 1-2 sites; the generator hard-errors
   otherwise. THE ROAD PROMISE (designer ruling, 2026-08-27 human
   check): a road always has something at its end, even minor loot --
   every dirt-track terminus must be a site with at least one loot
   action at generation time. Assert it in verify_terrain beside the
   no-path-near-Band-4 check.

4. REMAINDER CHARGES come from SORTIE_SPEC.md §4, not from LOOT_SITES:
   loot that doesn't fit stays at the site as a remainder charge, the site
   keeps its actions and its unlooted sprite, and its inspection payload
   says what is still there. NO ground piles, ever -- read SORTIE_SPEC §4
   for why. Implement this here because the state lives on the site.

5. Deeds: emit EventBus.deed_committed(villain, deed_id, axes) and append
   to a per-villain deeds Array on Necromancer, per LOOT_SITES §6. R2
   consumes none of it beyond a TravelLog line. This is the ledger R3 will
   read, and it is per-villain by decision -- do not put it in GameState.
   Site NOTICE, by contrast, goes to GameState.add_threat(): threat is
   world state and stays global. Both halves of that split are deliberate.

6. Sortie-scale placement: seed at least one Band-2 site in the 10-20 cell
   ring P0 left pending, so measure_travel's "lair -> sortie-scale
   resource" row goes green.

7. Dark Essence completes its move to field-loot-only (§5). Its current
   sources -- BountyBoard.gd's reward grant, MissionSystem and EventSystem
   effect handlers -- get re-pointed or retired in this pass. Note that
   ROGUELITE_REWORK §8 wrongly calls this "already a code convention"; it
   isn't, which is why it's a task.

Verification per LOOT_SITES §10: tools/verify_loot_tables.tscn with the
10k-roll tier assertions, run headless AS A SCENE not -s. Extend
check_sprite_scales for looted-state sprites. Re-run verify_terrain -- the
no-path-near-Band-4 assertion now has real Band 4 sites to check against.
Headless boot after every schema change.
Update CLAUDE.md (one line in Current phase). Write the session up in
docs/history/2026-08-loot-sites.md and add its row to the history README.
Commit.
```

---

## Prompt R2b — His own two hands

```
Read CLAUDE.md, the comment block at the top of CombatSystem.gd (rules 1-4
and the LAIR_AURA flag's own comment -- it predicted this prompt), and the
whole of docs/design/NECROMANCER_SPEC.md first. R2a must be done -- the
den packs and guardians this makes fightable have to exist. C2 must be
done -- he fights through his C2 statline (Arcane, Int 7) and profile
reach; if combat_might() still exists, stop.

Give the villain a fight he can win with his own craft, without giving
him an attack button.

1. Engage close, cast far, per NECROMANCER_SPEC §3: a fight OPENS only
   when he closes to VILLAIN_ENGAGE_PX (= Wolf.ENGAGE_RADIUS_PX, 26 --
   one "close enough to start" number, do not invent a second) of a
   hostile, or when a hostile hits him first. Once engaged he exchanges
   at his ARCANE 5-CELL PROFILE REACH (Int vs Int, from C2's profile
   table -- not a new constant). Walking beyond his reach stops his
   swings the next interval. He is NEVER rooted -- no in_combat state on
   him; his membership lives in CombatSystem. Do NOT auto-engage at 5
   cells -- the split is the design; read §3's "why the split matters".

2. Retaliation (§4): anything that hits him is engaged back from the
   next exchange, no input, from range.

3. THE AURA GOES POSITIONAL (§5): the settlement-era protection holds
   exactly while world.lair_band contains him, and nowhere else. It is a
   position test, not a second flag -- DELETE LAIR_AURA_PROTECTS_VILLAIN
   in the same commit, and update Wolf.get_inspect_data()'s promise line
   to read the position test. Outside the band he joins
   _prey_candidates() (per-villain reference, never a lookup).

4. His consequence branch: never injured-and-flee (he is not a Follower);
   his zero is villain_died, which Necromancer.take_damage() already
   emits. R2's death handling stays SORTIE_SPEC §6's (haul cleared,
   respawn at Throne, loud log) -- if R2c hasn't run yet there is no haul
   to clear, and the handler still lands here so R2c only wires into it.

5. EventBus: villain_engaged(villain, foe_name), villain_disengaged(
   villain, foe_name, reason). HUD hp readout red below 30%; the panel's
   Activity row says who he is fighting.

6. Combat.gd and Engagement.gd are UNCHANGED (C2 already widened the
   contract; this prompt only uses it). If either needs an edit, stop
   and say so.

Verification: tools/verify_villain_combat.tscn per NECROMANCER_SPEC §10,
headless AS A SCENE -- the band-edge test from both sides, engage at
26px and cast out to 5 cells, disengage-on-walk-away, retaliation, the
bounded-kiting assertion (a chasing wolf grants at most 2-3 free casts),
the 1000-fight win-rate bands (Int 7 vs one wolf: costly win; a 3-wolf
pack alone: lose or flee -- wolf Int 2 is the knob if arcane runs hot),
death clearing state before other handlers. F1's red numbers should make
the smoke-test fight readable -- if they don't exist yet you ran these
out of order.
NEEDS A HUMAN: does walking into engage range feel like a decision or an
accident, and does casting-over-the-escort read on screen once R2d
exists.
Update CLAUDE.md (the indirect-control line gains "his casting is
proximity-engaged, not ordered"; the gotcha list if the aura deletion
trips anything). Write up docs/history/2026-08-villain-combat.md and add
its row to the history README. Commit.
```

---

## Prompt R2c — Getting it home

```
Read CLAUDE.md, ROGUELITE_REWORK.md §1 (the banking rule) and the whole of
docs/design/SORTIE_SPEC.md first. R2b must be done.

Close the loop: the haul becomes real only when it reaches the Throne.

1. Everything in SORTIE_SPEC.md §2-§6: party capacity arithmetic, the
   deposit at 1.5 cells from the Throne (automatic, no button -- the worker
   trip loop deposits without a prompt and this is the same rule at longer
   range), the drop action with its in-reach/open-country asymmetry, and
   death clearing the unbanked haul.

2. THE BAND IS NOT THE THRONE. TravelLog treats lair_band membership as
   "home" for MEASURING a journey, and that stays. Banking is a different
   question and happens at the Throne. Do not merge the two tests --
   SORTIE_SPEC §3 explains why the last few cells matter.

3. New scripts/villain/SortieSystem.gd, per §9. It takes villain,
   settlement and world as FIELDS. It must never look the villain up and
   must never assume there is one of him (ROGUELITE_REWORK §11).

4. Relic effects activate ON DEPOSIT, not on pickup (LOOT_SITES §7). That
   is the §1 banking rule applied to power, and it is what keeps "drop it
   and run" a live choice. Implement the six live effects from LOOT_SITES
   §7's table; the dormant ones stay dormant and the panel says so.

5. HUD: carry state beside the existing Away timer, and a dusk warning when
   he is outside the lair band late in the day (§7). The player should
   never discover they were overloaded at nightfall by dying of it.

Verification: tools/verify_sortie.tscn per §10 -- capacity arithmetic,
overflow leaving an exact remainder, deposit emptying villain and escort in
one frame, crossing the band edge banking NOTHING, the two drop paths
emitting different signals, and villain_died clearing everything before any
other handler runs. Extend measure_travel with one loaded-return row.
Update CLAUDE.md. Write up docs/history/2026-08-sortie-deposit.md. Commit.
```

---

## Prompt R2d — The dead who walk with him

```
Read CLAUDE.md, ROGUELITE_REWORK.md §5, the header comments in
RallyPoint.gd and UndeadCommand.gd, and the whole of
docs/design/ESCORT_SPEC.md first. R2c must be done.

Give him an escort WITHOUT giving the player unit orders.

1. The mechanism is one enum member and one field: RallyPoint gains
   Order.ESCORT and `follow: Object`, and when follow is set the point
   copies follow.position each frame. Everything downstream --
   _advance_bound, the arrive epsilon, _hostile_for's measure-from-the-
   point rule, the drawn radius ring -- then works unchanged, because none
   of it ever assumed the point was still. Read ESCORT_SPEC §3's table
   before writing anything; if you find yourself building a second
   follow-the-villain system beside UndeadCommand, stop.

2. NO SELECTION UI. All bound undead, never a chosen subset -- that scope
   call is already in UndeadCommand.gd's header and escort mode inherits
   it. Living recruits never escort in R2 (§2).

3. The one real refactor: _hostile_for() currently iterates
   combat_system.wolves. Add CombatSystem.hostiles() unioning wolves and
   live site guardians, and route through it, so nothing downstream
   hard-codes a creature type again.

4. Cover-the-retreat (§4) is the only genuinely new behaviour: below
   Combat.FLEE_HP_FRACTION escorts interpose between him and the nearest
   hostile and do not break off. Undead don't rout -- the living-recruit
   flee rule does not apply. Announce it in the log; it's the one thing
   they do that the player didn't ask for.

5. Escort hauling uses Laborer.carrying_kind/carrying_amount, one kind per
   member. Relics ride the villain only (SORTIE_SPEC §2).

6. The lair aura is ALREADY positional -- R2b did it and deleted the flag.
   Nothing to do here except not reintroducing one: escort behaviour must
   read the same position test if it ever needs to know, and ESCORT_SPEC
   §9's line about flipping the flag is satisfied by R2b, not by new code.

Verification: tools/verify_escort.tscn per §10 -- binding covers undead and
only undead, bound escorts leave the labor pool and return on dismiss, the
point tracks him through a terrain slide, a skeleton raised at a grave
joins within one frame with no explicit add, interpose engages and
disengages at the hp threshold, and guardian targeting works through
hostiles() rather than wolves.
NEEDS A HUMAN afterwards: does the party read as a party at world zoom, and
does the leash feel like protection or like a tether.
Update CLAUDE.md. Write up docs/history/2026-08-escort.md. Commit.
```

---

## Prompt R2e — The bird that never lies

```
Read CLAUDE.md, ROGUELITE_REWORK.md §6, and the whole of
docs/design/RAVEN_SPEC.md -- INCLUDING its correction block at the top --
first. R2d must be done.

The Raven is a passive ping system. No token, no directives, no scouting
UI, and NO FOG INTERACTION AT ALL.

1. Everything in RAVEN_SPEC.md §2-§5: pings as pointers to already-placed
   undiscovered sites, the eligibility pool, dawn cadence at 70% with a cap
   of 3 outstanding, pings that never expire, the HUD portrait chip, markers
   above fog on world and minimap, and the inspection payload.

2. THE HONESTY INVARIANT (§4) is the load-bearing rule and it is stated so a
   harness can assert it: a pinged site must, at ping time, be reachable on
   walkable terrain, in Band 1 or 2, free of guardians and occupants,
   undiscovered, and hold at least one unclaimed charge. If nothing
   qualifies, THE RAVEN SAYS NOTHING THAT DAY. Never relax a condition to
   produce content -- a silent day is a correct day.

3. The abandoned_camp exception is the interesting one: occupancy rolls at
   activation, so the Raven can honestly know a camp is empty when the
   player cannot. That asymmetry is the Raven's whole value, and it is
   worth more than any reveal radius. Implement it deliberately.

4. New scripts/world/Raven.gd, per §8. Fields not lookups: villain, world,
   world_sites, fog. A second villain gets a second familiar.

5. The minimap deliberately carries NO live contents (see the world-
   population write-up). Ping markers are the one sanctioned exception,
   because they are intelligence you were given rather than the world
   leaking through fog. Put that reason in the minimap's header comment so
   the next reader doesn't "fix" it.

6. Centring on a ping is a manual camera move and drops villain-follow,
   exactly like an arrow-key pan (see the villain-split write-up).

Verification: tools/verify_raven.tscn per §9 -- the five invariant
conditions as separate assertions over 1000 simulated dawns, the cap, the
silent-day path, cadence near 70%, and FOG STATE BYTE-IDENTICAL before and
after 1000 pings. That last one is the assertion that keeps this spec
honest.
Update CLAUDE.md. Write up docs/history/2026-08-raven.md. Commit.
```

---

## After R2

Check `ROGUELITE_REWORK.md` §13's R2 exit explicitly: **a full sortie loop — out, choices made,
loot home — is tense and repeatable, and dying on a sortie is always traceable to a decision.**

Then playtest for the feel question this stage exists to answer: **is "one more grave, or turn
back?" a real question?** If the answer is always obviously "one more", the pressure is too low —
look at carry capacity vs yield (`SORTIE_SPEC.md` §10) and the dusk warning before adding anything
new. If it's always "turn back", the loot is not worth the risk and the tier ratios in
`LOOT_SITES_SPEC.md` §5 are the knob.

And the terrain question P1/P2 exist to answer: **can you navigate by the ground alone?** Turn the
minimap off and walk from the Throne to the village. If you can't, the road network isn't doing its
job; if you can walk straight to the crypt, it's doing too much.

Two new feel questions this revision adds: **does the den fight teach the arithmetic?** — a
solo villain should start one, read the numbers, and leave; with an escort it should be a real
but winnable brawl (`NECROMANCER_SPEC.md` §10's win-rate bands are the tuning target). And
**do the forests hide things or just slow things?** — if a clearing's contents were obvious from
outside, the corridor isn't doing its job.

Four things R2 leaves deliberately open, all flagged in their specs: the deeds ledger has no
reader, site notice feeds threat but nothing yet reads threat as notoriety, the villain's spell
list is two entries and stays that way until R5's unlocks, and the generator can lay out one map
but not shuffle between runs (`TERRAIN_SPEC.md` §11 — R4 changes steps 4–5 only).

R3 prompts should be written after that playtest, not now.
