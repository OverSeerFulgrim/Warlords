### Art provenance — what's commissioned and what's still placeholder

`Official Sprites/` holds the **commissioned art**. Runtime character tokens, buildings, nodes and icons are 128px square; their full-resolution 1024px/1254px masters live in `_originals/`. The terrain atlas and four frame-sensitive animation/VFX sheets deliberately remain at source resolution. This is the real art. Everything else in the project is a stand-in.

**Wired:**

| Use | Sprite | Where the path lives |
|---|---|---|
| Throne, Barracks, Bone Pile, Dark Altar | `Throne_of_Bones` / `Barracks` / `Bone_Pile` / `Dark_Altar` | `data/buildings.json` → `sprite_path` |
| Trees | `Pine_Tree` → `Pine_Stump` when chopped | `ResourceField` consts |
| Berry grove | `Berry_Grove_Full` → `Berry_Grove_Picked` when stripped | `ResourceField` consts |
| Graves | `Grave_Undisturbed` → `Grave_Dug_Up` when robbed | `ResourceField` consts |
| All 16 race tokens + Skeleton Worker | one per race | **`data/races.json` → `sprite`** |
| Necromancer (HUD badge + inspection) | `Necromancer_Portrait` | `Main.NECROMANCER_SPRITE`, `Necromancer.PORTRAIT` |
| Necromancer (map avatar) | `Necromancer_Full_Body` | `Necromancer.MAP_SPRITE`, read only by `NecromancerToken` |
| Dark Essence in the resource bar | `Icon_Dark_Essence` | `Main.ICON_DARK_ESSENCE` |

**Race token art is data, not code.** `RaceCatalog.sprite(race_id)` reads it from `races.json`, so adding a race never means editing a Dictionary in `Main.gd`. `Main.SPECIES_SPRITES` survives *only* as a fallback for Ghoul and Wraith, which exist in the superseded `followers.json` templates and have no `races.json` row — don't add to it.

**Deliberately not wired:** `Orc_Armed.png`, `Goblin_Armed.png`, `Gray_Dwarf_Miner.png`. These are per-state variants for combat (Stage 4+) and a working/at-node state. There is no state machine to select them, and wiring them now would mean inventing a state concept purely to justify the art.

**Still placeholder:** the Stone Deposit (Kenney materials icon), animal carcasses (Kenney bones icon), the deer and the wolf (both generated — see below), recruit houses (Kenney House pack, tinted per race by `HouseStyle`), Workshop/Blacksmith (Kenney towers), and the five locked per-species housing buildings. **World terrain is commissioned** (`Terrain_Tileset_Snow.png`, wired via `data/world_map.json`'s legend), with one gap: there is no mountainside tile, so rocky scree stands in for blocking high ground.

`art/tile_ground_frozen.png` is **no longer used** — the world map's terrain layer replaced the settlement's tiled ground background.

**Scaling.** Runtime art remains larger than its on-screen target, and every consumer derives its scale from the loaded texture. Downsampling therefore changes memory use without changing the drawn size. Two mechanisms are already in the codebase:

- **`Sprite2D` users** call `Anchoring.scale_for_content_height(texture, target)` — `Building._setup_sprite`, `ResourceNode._apply_scale_for`, and the unit tokens. They used to divide a target by the *texture* width; see "Sizes" below for why that was meaningless.
- **`Control` users** (the HUD badge and the Dark Essence icon) use a `TextureRect` with `EXPAND_IGNORE_SIZE` + a `custom_minimum_size`. Without `EXPAND_IGNORE_SIZE` a raw 128px texture asks for a 128px-tall container and blows the top bar open.

The 35 eligible top-level PNGs were downsampled offline with premultiplied-alpha Lanczos filtering. Their decoded runtime footprint fell from **213.97 MiB to 32.18 MiB** (6.6×; top-level texture dimensions × 4 RGBA8 bytes, 11.36 MiB on disk); all 40 top-level source files were copied and hash-verified in `_originals/` first. `Terrain_Tileset_Snow.png`, `Orc_Animation_Sheet.png`, `Wolf_Animation_Sheet.png`, `Wolf_Pack_Animation_Sheet.png`, and `VFX_Sheet.png` are byte-identical to their backups — the terrain atlas because `WorldMap` slices it at a *measured* 5px margin / 8px gutters / 305px per tile, the three sheets and the VFX page because the deferred frame normalizer (`MODULAR_CHARACTER_ANIMATION_REVIEW.md` §8) needs source resolution.

**Filtering.** `project.godot` selects **Linear with mipmaps** for canvas textures, and the 35 resampled imports set `mipmaps/generate=true`. Linear because this is not pixel art (`Human_Outcast.png` alone has 63,895 unique RGBA colours); mipmapped because 128px sources draw at 40–70px and that undersampling is what shimmers while a unit walks. The five protected sheets remain unmipped, and `WorldMap` still overrides its generated terrain atlas to Nearest in code — the atlas is packed edge-to-edge and Linear would sample across the tile seams.

> **Two traps in that one setting, both of which cost real time.**
>
> 1. **Keys in `project.godot` are section-relative.** Inside `[rendering]` the key must be `textures/canvas_textures/default_texture_filter`. Written out in full as `rendering/textures/...` it silently defines `rendering/rendering/textures/...` — a setting nothing reads — and the filter quietly stays at its Linear-no-mipmaps default. It was written the long way first, and the fix is *only* visible by querying `ProjectSettings.get_setting()` at runtime; the file looks right.
> 2. **The enum order is not the obvious one.** It is `Nearest, Linear, Linear Mipmap, Nearest Mipmap`, so **2 is Linear Mipmap** and 3 is Nearest Mipmap. Confirm with `ProjectSettings.get_property_list()`'s `hint_string` rather than assuming the CanvasItem node enum's ordering, which is different again.

**Sizes are CONTENT HEIGHTS, not canvas widths.** This is the one rule, and it replaces the previous pass's. Every size constant below is *how tall the thing drawn on the sprite stands*, in world pixels, and width is whatever the art's own aspect ratio makes it. Use these constants, **never `SettlementGrid.CELL_SIZE`**, which is the shared unit across the settlement, the world map, walk speed and the terrain atlas's 64px resample target, and which R1c tuned five travel-time bands against.

> **Why the change.** The earlier pass grew every constant to fix a map that read as miniature, but divided its target by `texture.get_size().x`. Content fills **42%–100%** of a canvas depending on the asset (measured: `tools/measure_sprite_content.gd`), so the same number produced a different real size for every sprite. A pine tree asked for 76px drew **46px** of tree; a grave asked for 50px drew **50px**; a Skeleton Worker asked for 48px drew **38px**, 0.60 of a tile where SPRITE_SPEC §3 asks for 0.90. The numbers in the table were describing the picture, not the thing on it — so the *relative* sizes, which are the entire point, were noise. `Anchoring.scale_for_content_height()` is the fix; the old numbers were retired rather than converted, because most of them had never meant anything.

| Thing | Constant | px | tiles | drawn |
|---|---|---|---|---|
| Skeleton Worker | `WorkerToken.SPRITE_TARGET_SIZE` | 58 | 0.90 | 52×58 |
| Follower | `FollowerToken.SPRITE_TARGET_SIZE` | 58 | 0.90 | varies by race |
| Necromancer | `NecromancerToken.TOKEN_SIZE` | 67 | 1.05 | 47×67 |
| Wolf — **width** | `Wolf.TOKEN_SIZE` | 74 | 1.15 | 74×51 |
| Buildings | `Building.SPRITE_MAX_SIDE` | 104 | 1.63 | 34×104 (tower) – 132×104 (Bone Pile) |
| Pine tree | `ResourceField.NODE_SIZE_TREE` | 96 | 1.50 | 62×96 |
| Pine stump | `NODE_SIZE_STUMP` | 32 | 0.50 | 50×32 |
| Berry grove | `NODE_SIZE_GROVE` | 58 | 0.90 | 63×58 |
| Grave | `NODE_SIZE_GRAVE` | 48 | 0.75 | 59×48 |
| Stone deposit | `NODE_SIZE_STONE` | 45 | 0.70 | 82×45 |
| Deer | `NODE_SIZE_DEER` | 58 | 0.90 | 66×58 |
| Carcass | `NODE_SIZE_CARCASS` | 26 | 0.40 | 45×26 |

**Character sizes are now SPRITE_SPEC.md §3's body families**, not per-token guesses: Medium 0.90 for the worker and recruits, Villain 1.05 for the Necromancer. `FollowerToken` still applies Medium to *every* race, which is the interim state §9 describes — per-family scaling is a `body_class` field in `races.json` plus a lookup, and it is now a pure data change because the machinery exists.

Four things in that table are load-bearing rather than incidental:

- **The Necromancer is the tallest humanoid** — he is the unit the player is always looking for.
- **The wolf is the one sprite measured by width**, per SPRITE_SPEC §3's quadruped rule. It draws 74×51: *shorter* than the Necromancer and *wider* than him, which is the trade §3 spells out ("area is what legibility actually depends on"). This is the single call to `scale_for_content_width` in the project. It is not an inconsistency to tidy up.
- **The stone deposit is 45px tall and ~82px wide.** A height target on a wide flat outcrop is supposed to come out like that.
- **A stump is 0.5 tiles, a pine 1.5.** A stump is not a short tree, it is a different object, which is why `ResourceNode` carries a separate `_depleted_target_height` and `ResourceField._add` takes an optional fifth argument. Only the pine uses it.

**The world map is deliberately NOT converted.** `WorldSite` and `Patrol` still divide by canvas width. Their sizes are seven per-entry numbers in `data/world_sites.json` tuned against R1c's travel bands, and the rule change is not size-neutral there — the Kenney tower art is 310px of tower on a 320px canvas but only 100px across, so `"size": 88` currently draws a **213px** tower and would become an 88px one. Converting means re-tuning all seven and re-verifying the world map. Both files carry a header saying so; convert them together or not at all.

**Anchoring** (`scripts/Anchoring.gd`). Everything used to be centre-anchored, which is invisible at 32px and obvious at 68: a unit's *middle* sat on its position, so its feet were half a tile underground. Two rules now, one file, because it is the same subtle line in six places:

- `Anchoring.foot()` — the **drawn content's** bottom edge lands on the node's origin, and its horizontal centre on the node's x. Units, trees, deer, world sites. A unit's position is **where it stands**.
- `Anchoring.cell_base()` — `foot()`, then the sprite stands on the bottom-centre of its grid cell. Buildings. They used to be `centered = false` with the texture's top-left pinned to the cell, so drawing anything past one tile grew it **down and right over the neighbours**; now they grow *upward* out of their footprint, symmetrically, with nothing below the cell line.

`Sprite2D.offset` is in *texture* pixels and applied *before* `scale`, which is what makes one assignment survive every rescale.

**The float-above-the-ground residual is closed.** `foot()` used to anchor the texture *box*, so each token floated by whatever transparent padding the artist left below the figure. Content-height scaling made that worse rather than better — the padding is multiplied by a different factor per sprite — so `foot()` now anchors the alpha box. It costs one cached scan and no per-frame work. (Trimming the padding is still the better art fix, and is what §8's frame normalizer does for the animation sheets.)

**`Anchoring.content_rect()` is cached by resource path.** A 128×128 alpha scan is 16k pixels — trivial once, wasteful every frame, and every consumer re-derives its scale on depletion swaps and respawns. It uses `Image.get_used_rect()` (C++, not a GDScript pixel loop), decompresses VRAM-compressed imports first, and falls back to the full texture rect for anything unscannable, which reproduces the old behaviour rather than collapsing a sprite to nothing.

**Click targets follow the drawn content, not the constant.** `hit_radius()` is `max(drawn_w, drawn_h) × Anchoring.HIT_RADIUS_FRACTION` on every token, via `Anchoring.drawn_content_size()`; `ResourceNode.hit_radius()` is the same with its own 0.6 and an 18px floor. **Using the size constant would now be wrong**, because the constant is a *height*: the stone deposit's 45 would have claimed a circle covering barely half the 82px outcrop. `Main._closest_token_hit` used to be handed a hardcoded 16.0 for workers and 20.0 for followers — fine at 32/40px, silently wrong the moment the art grew — and now reads the radius off the token. The fraction is **0.45, not 0.6**: at 0.6 the Necromancer claimed an 82px circle on a 64px tile, and standing on the Throne made the Throne unclickable from anywhere in its own cell, taking the Keep menu with it. Note the pick order is unchanged and still deliberate — **characters outrank buildings**, so a villain parked on the Throne does shadow its centre; walk him off, which is what direct control is for.

**Y-sorting is on**, on `settlement` and on each of the four child layers it has to reach through (`WorkersLayer`, `FollowersLayer`, `ResourceField`, `WorldSites`) — Godot only descends into children that are themselves Y-sorted. Bigger sprites overlap far more than 32px ones did, so a worker behind a tree now goes behind it. **Two units deliberately opt out by keeping a higher `z_index`**, and both are recorded playtest fixes rather than oversights: the Necromancer (5) must never be hidden behind the Throne he stands on, and the wolf (6) must never be hidden by anything. Godot sorts by `z_index` first and only then by Y, so they simply never enter the sort. Fog (100) and terrain (−10) are unaffected for the same reason.

**Three tools sit behind all of this, and they are kept rather than thrown away**, because every number above is re-derivable and none of them is guessable:

- `tools/measure_sprite_content.gd` (`-s`, headless) — dumps canvas size, alpha box and fill fraction for every sprite the game scales, as CSV. This is what turned "the map looks wrong" into "content fills 42%–100% of the canvas".
- `tools/check_sprite_scales.tscn` (headless) — 40 assertions that each thing *draws* at the size its constant claims, plus the orderings (pine > Necromancer > stump, deer taller than wolf, carcass smallest). The bug it guards is silent: a scale site that divides by canvas width still runs and just draws the wrong size.
- `tools/capture_settlement.gd` (`-s`, **windowed**, not headless — there is no framebuffer in headless) — boots the real `Main.tscn`, walks the villain into the forest, chops two trees so a pine and a stump are in frame beside him, and saves a PNG. Takes an optional zoom multiplier for detail shots. **It seeds the RNG**, because the forest is placed with `randf_range` and an unseeded before/after pair compares two different maps.

Two traps those tools cost real time to find, both about `-s` script mode: **autoloads do not exist yet while a `-s` SceneTree script is being compiled**, so any class that transitively touches `EventBus`/`GameState` fails to compile and reports it as `Nonexistent function 'make_tree' in base 'GDScript'` — nothing mentions autoloads. Anything testing game classes must be a scene (`godot --headless --path . res://tools/x.tscn`), which is why `measure_travel.tscn` is one. And **`load()` from `_init()` hangs headless Godot**; use `_initialize()`.

Verified by that 40-assertion harness (all passing) plus a seeded before/after 1400×760 render pair at default and 2.2× zoom (written to the untracked `experiments/` scratch area; regenerate with the capture tool rather than looking for them in git): the pine goes from shorter than the Necromancer to half again his height, the stump from a disc as wide as he is tall to something ankle-high, and the treeline from scattered specks to woodland. The earlier pass's verification still stands for everything it covered — anchoring, click selection, the terrain atlas, Y-sorting, the HUD badge — none of which this pass changed the behaviour of.

One latent bug closed on the earlier art-wiring pass: `ResourceNode` used to compute its scale once from the *alive* texture and keep it when swapping to the depleted one. The pairs matched dimensions then, so nothing visibly broke, but a stump of a different resolution to its tree would have rendered at the wrong size. Scale is recomputed per texture in `_apply_scale_for()` — and that now matters in practice rather than latently, because a stump fills far less of its canvas than the pine it replaces *and* targets a different height.

`Official Sprites/_originals/` holds matching full-resolution backups for all 40 top-level PNGs and carries a `.gdignore`, which makes Godot skip the whole directory — confirmed no `.import` files are generated in it and nothing in `.godot/` references it. Leave that file in place.

