# Claude Code Prompt — Asset hygiene + visual scale

One prompt, two parts, run in this order. They touch the same sprite-scaling code (`Building._setup_sprite`, `ResourceNode._apply_scale_for`, and the four token classes), so doing them in one visit means one round of visual verification instead of two.

Part 1 is §7 of `MODULAR_CHARACTER_ANIMATION_REVIEW.md`. Part 2 is the visual-scale fix from playtest feedback: characters, buildings and resource nodes all read too small against a 64px terrain tile.

**Explicitly not in this pass:** `CharacterVisual2D`, animation wiring, Aseprite, the modular paper-doll system. That is §8 of the review and it is deferred on purpose — see §1 of that document for why.

---

## The measured problem, for Part 2

Default zoom is 0.72 and `SettlementGrid.CELL_SIZE` is 64, so on a 1400×760 window:

| | world px | on screen | fraction of a tile |
|---|---|---|---|
| terrain tile | 64 | 46 | 1.00 |
| Skeleton Worker | 32 | 23 | 0.50 |
| Follower | 40 | 29 | 0.63 |
| Necromancer | 44 | 32 | 0.69 |
| Wolf | 46 | 33 | 0.72 |
| building (clamped to CELL_SIZE) | 64 | 46 | 1.00 |
| pine tree | 38 | 27 | 0.59 |
| berry grove | 46 | 33 | 0.72 |
| stone deposit | 58 | 42 | 0.91 |
| grave | 34 | 24 | 0.53 |
| carcass | 26 | 19 | 0.41 |
| deer | 30 | 22 | 0.47 |

Every single object on the map is smaller than the tile it stands on. A tree being *narrower than its own ground tile* is why the forest reads as scattered specks rather than woodland, and a building filling exactly one tile gives the player's keep the visual weight of a patch of dirt.

---

## The prompt

```
Read CLAUDE.md first, then MODULAR_CHARACTER_ANIMATION_REVIEW.md section 7.
Two-part art pass. No gameplay logic changes in either part. Do NOT build
CharacterVisual2D or wire any animation — that is section 8 and it is
deliberately deferred.

=================================================================
PART 1 — ASSET HYGIENE
=================================================================

STEP 0 — BACK UP FIRST. THIS IS DESTRUCTIVE AND PARTLY UNRECOVERABLE.
"Official Sprites/_originals/" holds full-resolution backups, but only 39
of the 40 top-level PNGs are covered. These SIXTEEN have NO backup and are
gone forever if you resample in place before copying:

  Dark_Elf, Gnoll, Gnome, Goblin_Armed, Gray_Dwarf, Gray_Dwarf_Miner,
  Halfling, High_Elf, Hobgoblin, Human_Outcast, Kobold, Minotaur,
  Mountain_Dwarf, Necromancer, Orc_Armed, Troll

Copy every top-level PNG into _originals/ and verify the count matches
before writing a single resampled file. _originals/ carries a .gdignore
that keeps Godot out of it — leave that file alone.

STEP 1 — Downsample the source art.
"Official Sprites/" is ~214 MiB decoded and renders at 32-64px. Resample
character tokens to 128x128 and buildings/resource nodes to 128px on the
long side, offline, with a proper filter (Lanczos), preserving alpha.

This needs NO code changes and here is why: every consumer computes its
scale from the texture at runtime — Building._setup_sprite,
ResourceNode._apply_scale_for (_target_size / tex.get_size().x),
WorkerToken, FollowerToken, NecromancerToken. Smaller source, same
on-screen size, automatically. If you find yourself editing a scale
constant to compensate, stop: you have broken something. (Part 2 changes
those constants deliberately, which is a different thing.)

FIVE FILES ARE EXCLUDED — resampling them breaks working code:
  - Terrain_Tileset_Snow.png — WorldMap._build_atlas_texture slices it at
    a measured 5px margin / 8px gutters / 305px per tile. Change the
    dimensions and every one of those numbers is wrong.
  - Orc_Animation_Sheet.png, Wolf_Animation_Sheet.png,
    Wolf_Pack_Animation_Sheet.png, VFX_Sheet.png — per-frame bounding
    boxes and foot alignment; section 8's normalizer needs source
    resolution.

Do NOT delete the .import files. Replacing a PNG in place preserves the
.import and its uid:// — deleting it assigns a new UID and breaks every
reference to that asset. Godot re-imports on next open by itself.

STEP 2 — Set the texture filter deliberately.
project.godot does not set
rendering/textures/canvas_textures/default_texture_filter, so it is
Linear by accident. The art is NOT pixel art (Human_Outcast.png has
63,895 unique RGBA colours), so Linear is right — set it explicitly so it
is a decision rather than a default. Also flip mipmaps/generate to true on
the resampled textures: even at 128px they draw at 32-70px, and that
undersampling is what produces the shimmer during movement.

Terrain is the exception and already handles itself — WorldMap sets its
atlas to Nearest in code because the atlas is packed edge-to-edge and
Linear would sample across tile seams. Do not change that.

STEP 3 — Point the Necromancer's MAP TOKEN at his full body.
Necromancer_Full_Body.png exists; the token draws Necromancer_Portrait.png.
Careful: Necromancer.PORTRAIT is used in TWO places — the map token
(NecromancerToken._ready) and the inspection panel payload
(get_inspect_data) — and Main.NECROMANCER_SPRITE is the HUD badge. The
badge and the panel should stay a PORTRAIT. Only the map token becomes the
full body. Add a separate const rather than repointing PORTRAIT, and say
which you changed.

=================================================================
PART 2 — VISUAL SCALE
=================================================================

Playtest feedback: characters, buildings and resource nodes all read too
small. Measured at the default 0.72 zoom against a 64px tile, EVERY object
on the map is smaller than the tile it stands on — a pine tree is 0.59 of
a tile wide, a Skeleton Worker 0.50, a deer 0.47.

DO NOT FIX THIS BY CHANGING SettlementGrid.CELL_SIZE. It is the shared unit
across the settlement, the world map, walk speed and the terrain atlas's
64px resample target, and R1c just tuned five travel-time bands against it.
The sprite target sizes are the only numbers that express "how big is this
thing relative to its tile", so they are the ones to move.

New targets (world px; CELL_SIZE is 64, so 64 == one tile):

  WorkerToken.SPRITE_TARGET_SIZE      32 -> 48   (0.75 tiles)
  FollowerToken   (its target const)  40 -> 56   (0.88)
  NecromancerToken.TOKEN_SIZE         44 -> 68   (1.06 — he is the player
                                                  and should read as the
                                                  largest humanoid)
  Wolf.TOKEN_SIZE                     46 -> 70   (stays the single largest
                                                  unit on the map — that is
                                                  a DELIBERATE existing
                                                  decision, see CLAUDE.md's
                                                  combat section on the
                                                  invisible-wolf playtest.
                                                  Do not "correct" it below
                                                  the Necromancer.)

  Building._setup_sprite clamp        64 -> 104  (1.6 tiles)
  ResourceField._build_* size args:
    pine tree                         38 -> 76   (1.2 — a tree should be
                                                  taller than its tile)
    berry grove                       46 -> 66
    stone deposit                     58 -> 88
    grave                             34 -> 50
    carcass                           26 -> 40
    deer                              30 -> 54

Treat these as a starting point, not gospel. If something looks wrong in
the running game, change it and say what and why.

THREE THINGS THAT WILL BREAK IF THIS IS DONE NAIVELY:

1. ANCHORING. Building sets `sprite.centered = false` and pins the top-left
   to the cell, so scaling past 64 grows the sprite DOWN AND RIGHT, over
   the neighbouring cells. Buildings must be anchored bottom-centre to the
   cell so they grow UPWARD, like buildings. Character tokens use
   `centered = true`, which drifts their feet as they scale — they want a
   foot anchor too, so a unit's position is where it STANDS. Resource nodes
   the same: a tree's trunk base is its position, not its middle. Get this
   wrong and everything sits at the wrong depth against the ground.

2. CLICK TARGETS. hit_radius() on the tokens and ResourceField.node_at()
   do not derive from sprite size. Grow the art without growing the hit
   areas and clicks start landing beside the thing the player aimed at.
   Derive them from the same target-size constants so they can never drift
   apart again.

3. Building._setup_sprite currently only ever scales DOWN
   (`if largest_side > CELL_SIZE`). With a 104px cap and 128px source art
   that still works, but make the intent explicit: scale to FIT the cap,
   in both directions.

Also worth doing while you are in here, if it is cheap: enable y-sorting on
the settlement layer so a taller tree or building correctly occludes a
character standing behind it, and is occluded by one standing in front.
Bigger sprites overlap far more than 32px ones did. If it turns out to
fight the existing z_index assignments (fog is 100, the wolf is 6), skip it
and say so rather than half-doing it.

=================================================================
VERIFY
=================================================================

Launch the real game at 1400x760, default zoom, and check:
  - Report the before/after decoded size of Official Sprites/.
  - Nothing shimmers while the Necromancer walks (that is the mipmap fix).
  - Buildings grow upward from their cell and do not cover the cell to
    their right or below.
  - Characters' feet sit on the ground, not floating or sunk.
  - Clicking each kind of thing selects that thing, at the new sizes:
    a worker, the Throne, a tree, a grave, the deer, the Necromancer.
  - The world map still renders correctly (terrain was excluded, so any
    change there is a bug).
  - The HUD badge still shows the portrait; the map token shows full body.
  - The top bar is still ~47px tall and the panels have not moved.

Update CLAUDE.md — the "Art provenance" section's scaling notes and the
measured token/node/building sizes, which this pass makes stale. Commit.
```

---

## After this

The remaining art placeholders are the stone deposit (Kenney materials icon), the animal carcasses (Kenney bones icon), the generated deer and wolf, the recruit houses (tinted Kenney House pack), Workshop/Blacksmith (Kenney towers), and the mountainside terrain tile that does not exist yet. None of those block anything.

The animation question stays where `MODULAR_CHARACTER_ANIMATION_REVIEW.md` §8 left it: wire the Orc and Wolf sheets you already own, no Aseprite, whenever R2 is not occupying the same files.
