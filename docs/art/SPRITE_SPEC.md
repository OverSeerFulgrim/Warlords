# Sprite Specification

**Status:** authored 2026-08-04. The rules any character, creature or map object must follow to be commissioned, generated, or drawn for this project. `ART_BRIEF.md` says *what* to draw; this says *how big, on what canvas, anchored where*.

**Why it exists.** Measured across the sixteen commissioned race tokens, content height on the shared 128px canvas ranges from 90px (Halfling) to 114px (Troll). A Halfling is **79% the height of a Troll**; a Kobold is **91% of a Minotaur**. Every sprite was drawn to fill its own frame, so relative scale carries no information and the map reads as seventeen interchangeable blobs. No engine change can fix that, because the information isn't in the art. This document puts it there.

---

> **Terrain sheets are outside this document's rules.** `assets/official/terrain/*.png` are
> full-resolution 4x4 tilesheets (nominally 1254px square, 5px margin, 8px gutters, 305px tiles),
> sliced and resampled to 64px at load by `WorldMap._build_atlas_texture()`. They have no 256px
> canvas, no y=224 baseline and no body family, and they never should -- ground is not a
> character. The exception already existed in practice; this records it so nobody "fixes" it.
> `TERRAIN_SPEC.md` section 2 is their spec, and `tools/dump_atlas.gd` is how you read one.
> (The *trees* drawn over forest floor are a different matter: `Pine_Tree.png` is an ordinary
> node sprite and **is** governed by this document.)


**Every character is authored on the same canvas, with the same baseline, and occupies a different fraction of it.**

```
        256 px
   ┌──────────────┐  y=0
   │              │
   │      ▲       │        Troll fills 220px of the canvas
   │     ███      │        Halfling fills 105px
   │     ███      │        Both are drawn on the SAME 256x256 canvas
   │    █████     │        Both stand on the SAME baseline
   │              │
   ├──────────────┤  y=224   BASELINE — the ground. Feet touch this line.
   │              │  (32px below for shadow, snow spray, cast light)
   └──────────────┘  y=256
          x=128 — the vertical centre axis. Mass balances here.
```

Everything else in this document is a consequence of that rule.

**What it buys.** The engine applies **one** scale to every character:

```
scale = CANVAS_WORLD_SIZE / 256        # CANVAS_WORLD_SIZE = 96 world px
```

and correct relative size falls out automatically. There is no per-race size table in code, and adding race #18 requires no code change at all — the artist made the size decision on the canvas, which is where it belongs.

Today the engine must scale each sprite individually to a per-race target, and the instant it does that, relative size is destroyed. That is the whole bug.

**Until every race is redrawn to this canvas, the engine measures the alpha bounding box instead — see §9.1.** That is not a competing convention: on a conforming sprite, content height *is* a fixed fraction of the canvas, so the two agree. It is what makes the non-conforming art in the repo today behave, and it goes away for free once §1 is real.

---

## 2. Units

**All sizes are fractions of `SettlementGrid.CELL_SIZE` (64 px), never raw pixels.** The cell is the project's single shared unit — settlement, world map, and walk speed all derive from it (walk speed 1.0 is literally one cell per second). Writing "58 px" in this document would silently rot the moment anything rescales; writing "0.90 cells" does not.

`CANVAS_WORLD_SIZE` is **1.5 cells (96 px)**. That is the size of the *canvas*, not of any character on it.

---

## 3. Body families

Five families. Height is the character's own extent, top of head (or ears/horns — see §5) to baseline.

| Family | Height | Canvas fill | Width budget | Members |
|---|---|---|---|---|
| **Small** | 0.62 cells | 105 / 256 | ≤ 0.55 cells | Kobold, Goblin, Gnome, Halfling |
| **Stocky** | 0.68 cells | 115 / 256 | ≤ 0.75 cells | Gray Dwarf, Mountain Dwarf |
| **Medium** | 0.90 cells | 154 / 256 | ≤ 0.70 cells | Human Peasant, Human Outcast, Orc, Hobgoblin, Dark Elf, High Elf, Gnoll, Skeleton Worker |
| **Large** | 1.30 cells | 220 / 256 | ≤ 1.10 cells | Ogre, Troll, Minotaur |
| **Villain** | 1.05 cells | 180 / 256 | ≤ 0.70 cells | Necromancer (and future playable classes) |
| **Quadruped** | 0.72 cells tall | 122 / 256 | **1.15 cells wide** | Wolf, Deer |

**Body class is its own field in `races.json`. It is not derived from any stat, and must not be.** Gray Dwarf and Hobgoblin both have Might 6; one is four feet tall and one is six. Deriving height from Might would make dwarves tall, which is the opposite of a dwarf. Deriving it from `food_per_meal` fails on Halflings, who eat 1.5 — more than a Human — entirely on purpose.

**Two families have deliberate exceptions, and both are load-bearing:**

- **Villain sits above Medium but below Large.** The player character should read as the protagonist without being a giant. He is not a Large creature and must never be scaled like one.
- **Quadruped is measured by *width*, not height.** A wolf is low and long. `CLAUDE.md`'s combat section records a playtest where a 34px wolf was literally invisible on dark ground and the fix was making it the largest object on the map — the 1.15-cell width budget is how that decision survives this spec. Do not "correct" the wolf to be shorter than the Necromancer and call it consistent; it is wider, and area is what legibility actually depends on.

---

## 4. Anchors and pivots

- **Anchor is bottom-centre**, at canvas `(128, 224)`. A unit's `position` is **where it stands**, not its middle.
- This applies to characters, resource nodes (a tree's trunk base, not its crown) and buildings (the front doorstep).
- **Buildings grow upward from their cell.** The current code pins a building sprite's top-left to the cell, so scaling it past one cell grows it down and to the right, over its neighbours. Bottom-centre anchoring is what makes a building taller than its footprint read correctly.
- The 32px below the baseline is reserved for **contact shadow, snow spray and cast light**. Nothing structural goes there — it will be overlapped by whatever the character is standing on.

---

## 5. Silhouette and contrast

The gameplay render is **39–83 px tall** depending on family. Everything here is about surviving that.

- **Read the silhouette first.** Filled black at final size, a race must still be identifiable. If two races share a black shape, one of them needs a horn, a hunch, a tail or a hat.
- **No detail below 3 px** at final render. Buckles, teeth, eye whites and finger separation are wasted and become noise once mipmapped.
- **Headroom counts toward height.** Horns, ears, hats and hoods are part of the character's extent — a Minotaur's horns live inside the 1.30-cell budget, not on top of it. Otherwise "Large" quietly means "Large plus whatever the artist added."
- **Contrast against four grounds, not one.** The terrain is snow, dirt, cobblestone and ice, and the whole map is blue-shifted at night by `DayNightCycle`. A mid-grey character is invisible on cobble, and a pale one vanishes on snow. Every character needs either a value anchor (a dark mass) or a hue the terrain palette does not contain. Grey-on-grey at dusk is a failure mode this project has already shipped once.
- **Face the camera in three-quarter view, facing right.** Left-facing is produced by mirroring at runtime, so nothing asymmetric may carry meaning (a shoulder pauldron will flip sides; a scar will move cheeks).

---

## 6. Delivery formats

Two, and a race may ship either. Both use the §1 canvas.

**Static token** — one 256×256 PNG. The minimum for a race to exist in game.

**Animation sheet** — a grid of 256×256 frames, **4 columns × 5 rows**, rows in this fixed order:

| Row | Tag | Frames | Notes |
|---|---|---|---|
| 1 | `idle` | 4 | loops; breathing/sway only |
| 2 | `walk` | 4 | loops; contact-down-pass-up |
| 3 | `attack` | 4 | one-shot, returns to idle |
| 4 | `hurt` | 4 | one-shot, short |
| 5 | `death` | 4 | one-shot, holds on final frame |

This is the layout `Orc_Animation_Sheet.png` and `Wolf_Animation_Sheet.png` already use, which is why it is the spec rather than something invented.

**Every frame keeps the same canvas and the same baseline.** The character may move within the frame; the frame never moves. This is what makes a sheet drop-in — no per-frame bounding-box normalization, no foot-alignment pass, no hand-tuned offsets.

**Transparency is real alpha.** No chroma key, no magenta, no cyan. If a generator emits chroma, key it before delivery and check no opaque pixel remains within tolerance of the key colour.

---

## 7. Adding a new race, end to end

The whole point of this document is that this list is short.

1. Choose a body family. Write `"body_class": "medium"` into the race's `races.json` entry.
2. Commission or generate a 256×256 static token on the §1 canvas at that family's height.
3. Drop the PNG in `Official Sprites/`, point the race's `sprite` field at it.
4. Done. No code change, no scale constant, no size table.
5. *Later, optionally:* commission a 4×5 sheet to §6 and swap the reference. Same canvas, so it drops in.

---

## 8. Reserved — layers and rigs (NOT BUILT)

This chapter exists so the decision is written down, not because anything here is scheduled. See `MODULAR_CHARACTER_ANIMATION_REVIEW.md` for the full argument.

**Modular paper-doll construction is deferred, not rejected.** Its unique payoff is combinatorial content — equipment variants, appearance customization — and `COMBAT_SPEC.md` §9 lists gear as *specified, unscheduled*. Building the display layer for an unscheduled system is how a project acquires a rig it must maintain and cannot use.

**Skinned deformation (`Skeleton2D` / `Bone2D` / `Polygon2D`) is rejected outright, permanently, at this render size.** At 39–83 px a limb is six to ten pixels wide; weighted vertices land on non-integer positions and the rasterizer resamples every frame, producing exactly the crawling shimmer this document's contrast rules exist to prevent. Rigid cut-out layering — `Sprite2D` pieces in a `Node2D` hierarchy rotated by an `AnimationPlayer` — is the version that stays on the table.

**When it arrives, it inherits this document unchanged.** The canvas, the baseline, the anchor and the five families are the same whether a character is one flat drawing or fourteen stacked pieces. That is the reason to adopt §1 now: it is the part that never needs redoing.

Reserved layer order, for when it happens: `cape_back → legs → torso → arms_back → head → hair → arms_front → weapon_main → weapon_off → effects`.

---

## 9. Migration — what conforms today, and what to do about it

**Nothing conforms at the canvas level.** All sixteen race tokens are 128×128 with no shared baseline and near-identical content heights.

**Do not redraw all sixteen now.** The thing that makes race #18 cheap is §7 — the spec and the pipeline — not the redraw. Redrawing sixteen races today buys correct relative sizing and nothing else, and every one of them will need redrawing *again* when it gets an animation sheet. **Each race should be redrawn exactly once, at the moment it earns a sheet, and conform to this document then.**

### 9.1 Done — the engine measures content, not canvas

**The premise this document opened with was worse than it said.** §Why-it-exists blamed the art: sprites drawn to fill their own frames, so relative scale carried no information. Measurement (`tools/measure_sprite_content.gd`) found the engine was making it worse. Every scale site divided a target by `texture.get_size().x`, and content fills **42%–100%** of a canvas depending on the asset — 42% for High Elf, 100% for the graves. So the same target number produced a different real size for every sprite:

| Asked for | Actually drew | |
|---|---|---|
| Pine tree, 76 px | 46 px of tree | 0.72 tiles, not 1.19 |
| Skeleton Worker, 48 px | 38 px of skeleton | **0.60 tiles, where §3 asks 0.90** |
| Grave, 50 px | 50 px of grave | correct, by coincidence |

The size tables were describing the *picture*, not the thing drawn on it. Relative size — the only thing they exist to control — was noise.

**`Anchoring.scale_for_content_height(texture, target)` is the fix, and it is now the project's one sizing rule.** It measures the alpha bounding box (cached by resource path) and scales *that* to the target. Every token, resource node and building on the settlement layer goes through it. Width follows the art's own proportions, which is correct: the stone deposit asks for 45 px of height and covers 82 px of ground, because it is a wide flat outcrop.

Consequences worth knowing:

- **`§3`'s family heights are now literally what gets drawn.** The Skeleton Worker draws 58 px (Medium, 0.90) instead of 38, and the Necromancer 67 px (Villain, 1.05).
- **`§3`'s quadruped-by-width rule survives as the one exception**, via `scale_for_content_width`. The wolf targets 1.15 cells wide and draws 74×51 — shorter than the Necromancer, wider than him. That is the trade §3 describes, and it is a single documented call, not a leak in the rule.
- **§1's `CANVAS_WORLD_SIZE / 256` is unaffected and still the destination.** Once a race is redrawn to the shared canvas and baseline, content height *is* a fixed fraction of the canvas, and the two formulas agree. Content measurement is what makes the pre-conformance art behave in the meantime; it does not replace §1, and adopting §1 does not mean ripping it out.
- **`Anchoring.foot()` anchors the content box too.** Anchoring the texture box floated every figure by whatever padding sat under it, and content-height scaling multiplies that padding by a different factor per sprite. Same cached scan, so it was free.

### 9.2 Next — `body_class` in `races.json`

**Still the interim step, and now a pure data change.** `FollowerToken` applies Medium (0.90 cells) to every recruit, so a Troll and a Halfling are the same height on screen. Add `body_class` to every entry in `races.json` and have the token look its height up by family. The scaling machinery it needed — content measurement — exists; what is missing is only the field and a five-entry table.

Because each existing sprite fills its own frame, scaling per family produces roughly correct relative size from the art already in the repo — a Troll near 83 px against a Halfling near 40 px, versus today's uniform 58. It is approximate, because the source art has no shared baseline and the ratio comes out a little wide. It is right in every way that matters at a glance.

**The `body_class` field survives the migration.** It is what §7 step 1 writes, and what the interim scaling reads. Adding it now is not throwaway work — coordinate it with the C2 stat rework, which is re-authoring `races.json` anyway.

### 9.3 Not done — the world map

`WorldSite` and `Patrol` still divide by canvas width. Their sizes are seven per-entry numbers in `data/world_sites.json`, hand-tuned against R1c's travel-time bands, and the rule change is not size-neutral there: the Kenney tower art is 310 px of tower on a 320 px canvas but only 100 px across, so `"size": 88` currently draws a **213 px** tower and would become an 88 px one. Converting means re-tuning all seven values and re-verifying the world map against R1c. **Convert the two files together or not at all** — they share a screen, and half-converting is worse than neither.

### 9.4 The regression guard

`tools/check_sprite_scales.tscn` (`godot --headless --path . res://tools/check_sprite_scales.tscn`) asserts that each thing *draws* at the size its constant claims, plus the orderings this document cares about: a pine towers over the Necromancer, a stump does not, the Necromancer is the tallest humanoid, the deer stands taller than the wolf. **Run it after any change to a size constant or a scale site.** The failure mode it exists for is silent — a site that divides by canvas width still runs, looks plausible, and simply draws the wrong size, which is how the last pass shipped.

**Ordering note:** `Terrain_Tileset_Snow.png` and the four animation/VFX sheets are excluded from every rule here that mentions the character canvas. Terrain is sliced at a measured 5px margin / 8px gutters / 305px per tile by `WorldMap._build_atlas_texture`, and changing its dimensions breaks that arithmetic.
