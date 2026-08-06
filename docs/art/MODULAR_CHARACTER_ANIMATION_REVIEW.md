# Review — Modular Character Animation System

**Reviewing:** `Documentation/MODULAR_CHARACTER_ANIMATION_REFERENCE.md` (August 3, 2026)
**Method:** repo audit against the live tree at `C:\Users\sjodz\Warlords` — token scripts, `RaceCatalog`, `races.json`, every PNG in `Official Sprites/` (dimensions, alpha, colour statistics), `project.godot`, `.import` params, `COMBAT_SPEC.md`, `ROGUELITE_REWORK.md`, `ART_BRIEF.md` — plus current upstream state of the three candidate importers.
**Reviewed:** August 3, 2026

> **See §12 (Addendum).** The reference document was revised on August 3, 2026 in response to this review. It accepts the verdict and corrects three claims made below — all three corrections are right and have been verified. **§4, §6 and §7 of this document should be read through the addendum**, which supersedes their overstated parts.

---

## 1. Verdict

**No-go on the two-character, one-weapon Aseprite vertical slice as specified. Go on a much smaller substitute.**

The proposal is technically sound. Godot 4.7.1 can do everything it describes, the layering is well-chosen, and the instinct to keep simulation authority on the RefCounted objects is right. Nothing here is wrong in the way a bad architecture is wrong.

It should still not be built now, for three reasons, in descending order of force:

1. **The system's payload has no schedule.** Modularity buys equipment swapping and appearance variation. `COMBAT_SPEC.md` §9 does not merely limit gear to one weapon slot — it lists gear as **"specified, unscheduled"**, alongside classes and disease, explicitly so that nothing is built in a way that blocks it. Authoring a `weapon_main` visual slot is building the display layer for a system that has no slice number. Meanwhile the actual next slice is **C2, the stat rework**, which `COMBAT_SPEC.md` §12 flags as *"the single most likely thing to stall this work"* — 360 hand-picked numbers across 17 races, plus a rewrite of `RACES.md` and `races.json`. The animation proposal wants to read race appearance identity out of that same data layer, which is about to be re-authored.

2. **A cheaper path to the same visible outcome already exists in the repo, and the proposal does not know about it.** `Official Sprites/` now contains `Orc_Animation_Sheet.png` and `Wolf_Animation_Sheet.png` — complete 4×5 = 20-frame animation sheets (idle / walk / attack / hurt / death), already alpha-keyed, foot-aligned within 4 source pixels, in the project's own art style. Two characters are effectively animated today with zero Aseprite work. See §5.

3. **The art you have is not pixel art, and the proposal's authoring contract assumes it is.** `Human_Outcast.png` contains **63,895 unique RGBA colours**; `Skeleton_Worker.png` contains 41,496. There is no palette, no clean pixel grid, and no colour index. It reads as pixel art only because it is downscaled ~31×. Aseprite-authored 64×64 parts with a real indexed palette would be genuinely crisp — and therefore *visibly a different art style* sitting next to every unconverted race. The doc's own Phase-5 criterion ("static legacy characters and modular characters coexist correctly") is not achievable with this source set. See §6.

**What to do instead:** two hours of asset hygiene that fixes real, currently-shipping visual defects (§7), then wire the two animation sheets you already own (§8). Revisit modularity when gear gets a slice number.

---

## 2. Corrections to the audit section

The doc's factual claims are mostly accurate. These are wrong or stale:

| Doc claim | Actual |
|---|---|
| "Several unnamed `call_*.png` files are generation boards, including **Ogre** and wolf animation boards. They have **opaque chroma backgrounds** and require extraction." | The files are named — `Orc_Animation_Sheet.png` (1536×1024), `Wolf_Animation_Sheet.png` (1254×1254), `Wolf_Pack_Animation_Sheet.png` (1402×1122), `VFX_Sheet.png`, `Terrain_Tileset_Snow.png`. It is an **Orc** sheet, not an Ogre. **All are already alpha-keyed** (alpha extrema 0–255, 65–87% fully transparent). No extraction is required. |
| "`FollowerToken.gd` creates one `Sprite2D`" | Creates a `Sprite2D` **plus two `Label`s** (carry tag, exceptional ★) under a `Node2D` — 4 canvas items, and its own per-token `_process`. `WorkerToken` creates a `Sprite2D` + one `Label` = 3. The per-character baseline is 3–4 canvas items, not 1. This matters to the crowd argument in §4. |
| "roughly 100 MiB of raw RGBA pixels" for 17 race tokens | Confirmed: **98 MiB** (15 recruitable races × 6.0 MiB at 1254², + `Skeleton_Worker` 4.0 MiB at 1024², + `Necromancer_Portrait` 4.0 MiB). The whole `Official Sprites/` folder is **214 MiB** decoded. |
| Doc is silent on residency: "Actual residency depends on what Godot loads." | Determinable: every `.import` carries `compress/mode=0` (lossless) and `metadata={"vram_texture": false}`, so each texture uploads as full **RGBA8**. `RaceCatalog.sprite()` → `load()` in token setup means every race that has ever appeared this session stays resident at 6 MiB. This is not a hypothetical. |
| The `Characters/Character - parts/` pack "contains bodies, faces, and hair" | Confirmed — `Character_128x128_body`, `_face`, `_hair_back`, `_hair_front` and 256× equivalents. The doc's conclusion (not articulated limbs; style mismatch) is correct. |

The token sizes (40 / 32 / 44 px), `RaceCatalog`'s role, `Skeleton_Worker.png` at 1024², and the COMBAT_SPEC gear reference all check out.

**One asset inventory gap:** the doc predates `Necromancer_Full_Body.png`, `Wolf_Portrait.png`, `Wolf_Pack.png` and `Terrain_Tileset_Snow.png`. A full-body Necromancer now exists, which is relevant — the token currently draws the *portrait* scaled to 44px, and swapping in the full body is a one-line fix independent of everything else here.

---

## 3. What the proposal gets right

Worth stating plainly, because the no-go is about timing, not quality:

- **Keeping `CharacterVisual2D` below the token classes, with simulation authority untouched.** This is the correct boundary and it matches the convention the codebase has already paid for twice (`WorkerToken`, then `NecromancerToken`).
- **Three renderer modes with a legacy fallback.** Incremental migration is right; a big-bang conversion of 16 races would be the actual project-killer.
- **Refusing one universal humanoid skeleton.** Correct, and the four proposed families are a sensible cut.
- **Rig families with body-profile offsets rather than per-race rigs.** Right shape.
- **Treating generated sheets and JSON as build products, not source.** Right.
- **Deferring `death` past the first technical test.** Right.
- **Naming the risk as art-production consistency rather than engine capability.** Correct, and under-stated — see §6.

---

## 4. Technical review, Godot 4.7.1

### `Node2D` + `AnimationPlayer` + sprite swaps vs. `Skeleton2D`

**The proposal's choice is correct, and the reasoning should be stronger than "pixel art scale."** `Skeleton2D` / `Bone2D` drives `Polygon2D` deformation with weighted vertices. At a 32–44px on-screen figure, a limb is 6–10 pixels wide; skinned deformation at that size produces sub-pixel vertex motion, which is exactly the shimmer the doc's own acceptance criteria forbid. Discrete frame swaps also let the artist hand-place every pixel, which is the stated goal. `Skeleton2D` is the wrong tool here and should be ruled out explicitly, not left as an open question.

### Crowd cost — the doc's fear is overstated, the target is phantom

Phase 4 proposes profiling 100–200 visible characters. **No design document in this repo states that target.** `GAME_OUTLINE.md` puts the Barracks at base capacity 5, upgradeable ("Only one, ever — but upgradeable ... base 5 → upgrade tiers"). `ROGUELITE_REWORK.md` describes an escort, not an army. The "hundreds of followers" phrase originates in `Follower.gd`'s header as a justification for RefCounted — it is an architecture note, not a population spec.

At realistic counts (20–40 characters), 15 layers each is 300–600 canvas items. Godot 4's Compatibility renderer batches 2D draws that share texture and material; with a single atlas that is well inside comfortable. The measurement that would actually matter is the one nobody has taken: **the existing per-token `_process` + `Label` cost**, which is already 3–4 canvas items and a per-frame `String` format per hauling character.

**Recommendation:** drop Phase 4's composite-cache requirement from the design. Keep the composite path *possible* (the doc is right that the architecture should not preclude it) but do not build it, and do not gate the go/no-go on a profiling result for a population the game does not have.

For the record, the composite path is cheap if it is ever needed: 64×64×4 = 16 KiB/frame, ×20 frames = **320 KiB per unique appearance**. A hundred distinct loadouts is 32 MiB — one seventh of what `Official Sprites/` costs today.

### GL Compatibility renderer

`project.godot` sets `renderer/rendering_method="gl_compatibility"`. Nothing in the proposal is blocked by this — `SubViewport`-to-texture baking, `AtlasTexture`, `SpriteFrames` and `AnimationPlayer` all work. Worth noting only because the composite-bake path is the one part that touches renderer specifics, and it is the part §4 recommends dropping anyway.

### Two current-state defects the proposal did not find

Both are live today, both are cheap, and both sit directly on the doc's acceptance criteria.

1. **No mipmaps on a 31× downscale.** Every `.import` in `Official Sprites/` has `mipmaps/generate=false`. `project.godot` does not set `rendering/textures/canvas_textures/default_texture_filter`, so it defaults to **Linear** — which samples a 2×2 texel neighbourhood. Reducing 1254px to 40px with a 2×2 filter and no mip chain is textbook undersampling: aliasing at rest and crawling shimmer on any movement. The doc lists "no subpixel shimmer at gameplay scale" as an acceptance criterion for the *new* system; **the current system fails it**, and nobody has attributed it.

2. **Chroma residue under transparent pixels.** Fully-transparent pixels retain their generation-background RGB — magenta `(238,10,218)` on the Orc sheet, green `(29,236,36)` on `Human_Outcast`, cyan `(5,248,252)` on `Necromancer_Full_Body`. On any filtered downscale those values get averaged into edge pixels. This one is *already mitigated*: every `.import` carries `process/fix_alpha_border=true`, which bleeds edge colour outward at import time. Flagging it because it is a live landmine for any hand-rolled export pipeline (§9) that bypasses Godot's importer.

---

## 5. The alternative the proposal does not consider

`Official Sprites/Orc_Animation_Sheet.png` and `Wolf_Animation_Sheet.png` are complete character animation sheets in the project's own style. Measured:

| | Orc sheet | Wolf sheet |
|---|---|---|
| Dimensions | 1536×1024 | 1254×1254 |
| Layout | 4 cols × 5 rows = 20 frames | 4 × 5 = 20 frames |
| Rows read as | idle / walk / attack / hurt / death | idle / walk / run / attack / hurt-death |
| Foot-Y drift within a row | ≤ 4 px of ~200 px | ≤ 8 px of ~300 px |
| Alpha | already keyed, 77% transparent | already keyed, 65% transparent |
| Facing | front-facing | side-facing |

At the token scale factor (44/1254 ≈ 0.035), a 4-pixel source drift is **0.14 screen pixels**. These are usable essentially as-is.

This changes the cost comparison materially:

| | Modular Aseprite (proposal) | Baked per-race sheets (already demonstrated) |
|---|---|---|
| Per rig family | ~10 animating parts × 14 frames = ~140 hand-drawn cels, **plus** hidden-pixel reconstruction for every part occluded in the source figure | — |
| Per race | body/head/hair variants on the family rig | 20 frames, generated + normalized |
| Per weapon | 4 grip/pose variants × 4 rig families × directions | 0 (baked, or a separate overlay later) |
| Races done today | 0 | 2 |
| Enables gear swapping | yes | no |
| Style-consistent with existing 16 races | **no** (see §6) | yes |

The honest framing: **modularity's entire advantage is combinatorial reuse, and this project's combinatorics are currently 1 weapon slot × unscheduled.** Baked sheets lose badly at 5 armour slots and win decisively at zero.

**Two inconsistencies to fix before leaning on sheets**, and they are the whole normalization job:

- The Orc sheet is **front-facing**, the Wolf sheet is **side-facing**. Pick one convention and hold it. The current tokens use `sprite.flip_h` for facing, which only works with side views; a front-facing walk cycle that mirrors is a different visual language. This is decision (1) in §10 and it needs answering before any more sheets are commissioned.
- Neither sheet sits on an integer grid (1024/5 = 204.8; 1254/5 = 250.8). Row bands are clean and separable, but a naive uniform `SpriteFrames` region slice will drift. Normalization — crop to bounding boxes, snap to a uniform cell, align feet — is a ~60-line Python or GDScript pass, run once per sheet, output checked in.

---

## 6. The hidden art cost the proposal understates

The doc identifies "hidden pixels behind torsos, sleeves, hands, hair, and armor must be drawn." Correct, and looking at `Human_Outcast.png` confirms it is severe — the hood, hair and head are a single merged mass; both arms overlap the torso; the tunic and legs interpenetrate. A faithful part-separation is closer to a redraw than a cut.

But the larger cost is one the doc does not raise at all:

**The commissioned art is not pixel art.** `Human_Outcast.png` has 63,895 unique RGBA values across 1254². At a colour tolerance of ±6, the 75th-percentile horizontal run length is 8 pixels — implying a nominal ~157px logical figure rendered with continuous-tone noise inside each notional block. There is no palette, no index, and no clean grid.

Three consequences:

1. **Style seam.** True 64×64 Aseprite art with an indexed palette will be crisp and flat. Placed beside a legacy race token — soft, noisy, 31× downscaled — the difference is immediately visible. The doc's Phase-5 "coexist correctly" criterion is unachievable against this source set, and Phase 5 is where 14 of 16 races live for most of the project's life.
2. **Palette features are impractical.** The appearance definition proposes "skin or palette selection." Palette swapping requires a palette. Against 64k colours it becomes a hue-shift shader, which is a different and worse feature.
3. **`Human_Outcast.png` is a poor Phase-1 reference.** The doc picks it as the locked reference for the first rig. It is one of the softest, most-occluded figures in the set. If a redraw does happen, the Orc — which already has a 20-frame sheet establishing its own poses and silhouette — is a far better anchor.

**Net:** the doc's "main risk is art-production consistency" is right, but the inconsistency is not between future Aseprite assets. It is between future Aseprite assets and the 16 finished race tokens the game already ships.

---

## 7. What to do this week instead — highest value per hour

None of this depends on the animation decision, and all of it fixes something real.

**A. Downsample the source art. ~2 hours, no design risk.**
`Official Sprites/` is 214 MiB decoded, rendering at 32–64 px. The art's effective logical resolution is ~157 px, so resampling every character token to 128×128 and every building/node to 64–128 px loses nothing visible. Result: the folder drops to **well under 1 MiB decoded**, VRAM pressure disappears, and — because you resample once, offline, with a proper filter instead of every frame with a 2×2 GPU filter — **the aliasing and shimmer go away**. Keep the current files in `Official Sprites/_originals/` (which already carries a `.gdignore`).

This single change satisfies two of the proposal's eight acceptance criteria before any animation work starts.

**B. Set the texture filter deliberately.** Add `rendering/textures/canvas_textures/default_texture_filter` to `project.godot` — Nearest if you commit to the pixel-art contract, Linear if not. Right now it is Linear by accident. Decide it.

**C. Swap `NecromancerToken` to `Necromancer_Full_Body.png`.** It currently draws `Necromancer_Portrait.png` at 44 px. A full body now exists. One constant.

**D. Normalize and wire the two sheets you own.** See §8.

---

## 8. The smaller proof of concept

The doc asks: *"Any smaller proof of concept that would invalidate bad assumptions sooner?"* Yes, and it is much smaller.

**Animate the Orc and the Wolf from the sheets already in the repo. No Aseprite, no new art, no paper-doll.**

1. Write `tools/normalize_sheet.py` (or `.gd`): read a sheet, find row bands and per-frame bounding boxes, emit a uniform-cell PNG with feet snapped to a fixed baseline plus a small JSON sidecar of rows→tag names and frame counts. Run it on both sheets; check outputs in as build products.
2. Add `CharacterVisual2D` with exactly **two** modes: `legacy` (current `Sprite2D`) and `animated` (`AnimatedSprite2D` from `SpriteFrames`). Give it the animation-state API and facing/mirroring the doc specifies. Leave the layered and composite modes unwritten.
3. Point `FollowerToken` at it. Orc followers animate; every other race falls back to legacy, unchanged.
4. Drive state from what already exists: `Laborer.TripStage` gives you idle / walk directly, `in_combat` gives attack, `is_injured` gives hurt.
5. Point `Wolf` at it too.

**What this proves or kills, in a fraction of the effort:**

- Whether animated and legacy characters can share a map without a visible style seam — *the actual project-level risk*, and it is testable today.
- Whether `CharacterVisual2D`'s state API and facing model survive contact with the real trip loop.
- Whether frame-swap animation at 32–44 px reads at all under the night tint.
- Whether normalized sheets are a repeatable pipeline.

**What it deliberately does not prove:** equipment swapping. That is correct — nothing schedules equipment.

If step 3 looks good and the seam is tolerable, the cheap road is "commission 14 more sheets," and the modular system may never be needed. If the seam is intolerable, you have learned that for one day's work rather than after redrawing a rig.

---

## 9. Third-party dependency risk

**Aseprite Wizard** (`viniciusgerevini/godot-aseprite-wizard`, MIT, ~1.3k stars) is the only one of the three worth considering. Its store listing claims Godot 4.7 and 4.7.1 support; the `godot_4` branch is actively maintained (v9.8.0, March 2026, with a listing update in July 2026). It covers tags, per-tag animations, Aseprite frame-duration → Godot FPS conversion, regex layer filtering, per-layer separate resources, and `AtlasTexture`-backed `SpriteFrames`.

**Important correction to the proposal's assumption:** its README describes slice support as *"Supports slices. **Import only a region from your file.**"* That is slice-as-crop-region, **not** slice-as-exported-pivot. It does not give you sockets. This directly settles decision (5) — no importer in the candidate list delivers pivot metadata, so sockets must live in Godot rig resources or come from your own parse of Aseprite's JSON.

**Importality** (`nklbdev/godot-4-importality`) has a documented failure mode against recent Godot dev builds — empty frames on `SpriteFrames` import, with a `fix_empty_frames` branch as the workaround. Given 4.7.1, treat as higher risk.

**`diivi/aseprite-mcp`** exposes **unrestricted Lua execution**. The doc flags this and then still lists it as "promising." It is a convenience wrapper over the CLI you already have, at the cost of arbitrary code execution driven by model output. There is no capability behind it you cannot reach with `Aseprite.exe --batch --script`. Recommend: do not install.

**Also worth noting** — the proposal's own escape hatch (Phase 3: "create a small project-owned exporter/importer around Aseprite's PNG and JSON output") is almost certainly the right answer regardless. Aseprite's `--sheet` + `--data` JSON output is stable, documented, and gives you exactly the tags/durations/slices you need, with no plugin in the dependency graph and no editor-side behaviour to debug. The §8 normalization script is the same tool.

---

## 10. The seven open decisions

**(1) Left/right mirroring only, or author front/back/right immediately?**
**Mirroring only, and side-view as the convention.** The camera is top-down-ish, tokens are 32–44 px, and the codebase already implements facing as `sprite.flip_h` in three places. Four-direction authoring quadruples every art cost to buy readability the player cannot resolve at this size. **But settle the front-vs-side inconsistency first** — the Orc sheet is front-facing and the Wolf sheet is side-facing, and `flip_h` only makes sense for side views. Every subsequent asset depends on this answer. *This is the single decision that should be made before anything else on the list.*

**(2) Is 64×64 canvas / 32–44 px figure the permanent standard?**
**Not as stated — it conflicts with `ART_BRIEF.md`, which specifies 32×32 map tokens and 128×128 portraits.** You have two written standards and delivered art (1254×1254) that follows neither. Recommendation: adopt **64×64 canvas with a ~44 px figure** as the map standard, and *amend `ART_BRIEF.md` to match* rather than leaving both documents live. The larger canvas is right — 32×32 leaves no room for an attack frame's reach, and the Orc sheet's attack frames are 60% wider than its idle frames.

**(3) Layered parts continuously, or composite frames by default?**
**Neither, yet — see §4.** The crowd target that motivates the question (100–200 visible characters) is not in any design document. Build the layered path if you build anything; keep the composite path architecturally possible; do not implement it until a profile on a real population says otherwise.

**(4) Which importer, if any, on 4.7.1?**
**Aseprite Wizard, if you use one at all** — it is the only candidate that claims 4.7.1 explicitly and is actively maintained. But prefer **no importer**: a project-owned script around `Aseprite.exe --batch --sheet --data` gives deterministic, reviewable, checked-in build products with nothing in the dependency graph. That is also the doc's own Phase-3 fallback, and it is the same script §8 needs anyway. Do not install `aseprite-mcp` (§9).

**(5) Are Aseprite slices authoritative, or do sockets live in Godot?**
**Sockets live in Godot rig resources.** Forced by capability, not preference: Aseprite Wizard's slice support is region-cropping, not pivot export (§9). If you write your own exporter you *could* carry slice pivots through `--data` JSON — but the rig resource still has to hold direction rules, draw order and mirroring, so putting pivots anywhere else splits one concept across two files with two edit workflows. Keep Aseprite slices as an authoring aid; make the Godot resource authoritative.

**(6) Which races genuinely share a rig family?**
**Unanswerable until §8 runs, and the doc's grouping is optimistic in one place.** The four proposed families are a reasonable first cut, but "Large/unusual humanoid: Ogre, Troll, Minotaur, **Gnoll**" is wrong — a Gnoll is digitigrade with a canine head; it shares limb topology with the *Wolf*, not the Ogre. Provisionally: standard / small / stocky / large as proposed, minus Gnoll, which gets its own treatment or a baked sheet. Confirm nothing until two characters have actually been drawn on one rig.

**(7) Should portraits share appearance IDs with a separate 128×128 system?**
**Yes to shared IDs, and this is the one recommendation to act on immediately and cheaply.** Make the appearance ID a plain string key in `races.json` — nothing more — resolved independently by the map renderer and the portrait renderer. It costs one field today, it survives every other decision on this list, and it is the correct move whether you end up with paper-dolls, baked sheets, or neither. It also survives the C2 `races.json` re-authoring, which is coming regardless.

---

## 11. Summary

| Question asked | Answer |
|---|---|
| Technically correct for Godot 4.7.1? | Yes. Nothing proposed is blocked by the engine or the Compatibility renderer. |
| Is the Aseprite layer/tag/slice contract robust enough for automation? | Layers and tags yes. **Slices no** — no candidate importer exports pivots as sockets; that must live in Godot. |
| `Node2D` + `AnimationPlayer` + sprite swaps, or `Skeleton2D`-first? | **Sprite swaps, decisively.** Skinned deformation at a 6–10 px limb width produces exactly the shimmer the acceptance criteria forbid. Rule `Skeleton2D` out explicitly. |
| Is layered-authoring + cached-composite the right optimization boundary? | The boundary is fine; the **problem is phantom**. No design doc targets hundreds of visible characters. Do not gate on it. |
| Hidden art-production costs? | Two. Hidden-pixel reconstruction is worse than described (`Human_Outcast` is a merged mass). And **the source art is not pixel art** — 63,895 colours, no palette, no grid — so converted races will not stylistically match unconverted ones. |
| Risks in the listed MCP/importer projects? | Importality has a known empty-frames failure on recent Godot builds. `aseprite-mcp` offers unrestricted Lua execution for zero capability gain — decline. Aseprite Wizard is sound but probably unnecessary. |
| A smaller PoC that invalidates bad assumptions sooner? | **Yes — §8.** Animate the Orc and the Wolf from the sheets already in `Official Sprites/`, with a two-mode `CharacterVisual2D`. Tests the real risk (style seam between animated and legacy characters) in roughly a day, with no new art. |
| **Go/no-go on the two-character, one-weapon vertical slice?** | **No-go as specified.** Gear is unscheduled, C2 is about to re-author the data layer the system reads from, and the seam risk is untested. **Go on §7 (asset hygiene) and §8 (sheet PoC)**, and revisit modularity when gear gets a slice number. |

---

## Appendix — measurements

All figures below were measured directly from the repo on 2026-08-03, not estimated.

```
Official Sprites/ decoded RGBA8 total ............... 214.0 MiB
  17 race/villain tokens ............................. 98.0 MiB
  per 1254² token ..................................... 6.0 MiB
  per 1024² asset ..................................... 4.0 MiB
Import settings (all files) ......... compress/mode=0 (lossless)
                                      mipmaps/generate=false
                                      process/fix_alpha_border=true
                                      metadata vram_texture=false
project.godot default_texture_filter ..... unset → Linear (default)
Renderer .................................... gl_compatibility

Human_Outcast.png unique RGBA colours ................... 63,895
Skeleton_Worker.png unique RGBA colours ................. 41,496
Human_Outcast p75 run length at ±6 tolerance ............. 8 px
  → effective logical figure width ................... ~157 px

Orc_Animation_Sheet.png ....... 1536×1024, 4×5 = 20 frames
  row bands (y) ..... 16-228, 242-432, 440-623, 631-814, 827-984
  foot-Y drift within row 0 ............................. 1 px
  foot-Y drift within rows 2-3 .......................... 4 px
  attack-frame width vs idle ....................... 258 vs 161 px
  transparent-pixel RGB residue .............. (238, 10, 218)

Wolf_Animation_Sheet.png ...... 1254×1254, 4×5 = 20 frames
  foot-Y drift within row ............................. ≤ 8 px
  transparent-pixel RGB residue .............. (234, 10, 233)

Token canvas items today
  FollowerToken .... Node2D + Sprite2D + 2 Labels = 4, own _process
  WorkerToken ...... Node2D + Sprite2D + 1 Label  = 3, own _process
  NecromancerToken . Node2D + Sprite2D            = 2, own _process
Y-sorting in project ........................... none configured

races.json rows ......... 17 real + 2 comment keys; 16 have sprites
  (human_peasant is the reference row and has none)
```

**Sources consulted:**

- [Aseprite Wizard (GitHub, `godot_4` branch)](https://github.com/viniciusgerevini/godot-aseprite-wizard) — feature list, slice semantics, v9.8.0 release
- [Aseprite Wizard (Godot Asset Store)](https://store.godotengine.org/asset/this-is-vini/aseprite-wizard/) — 4.7 / 4.7.1 compatibility claim
- [Importality (GitHub)](https://github.com/nklbdev/godot-4-importality) — capability list and the `fix_empty_frames` known issue
- [Aseprite CLI documentation](https://www.aseprite.org/docs/cli/) — `--batch`, `--sheet`, `--data`

---

## 12. Addendum — response to the revised reference document

*Added August 3, 2026, after the reference document was revised to "Character Animation Pipeline — Reviewed Decision and Long-Term Reference."*

The revision accepts the no-go and restructures around the §8 proof. Its "Review disposition" section corrects three claims made above. **All three corrections are right.** Each was re-verified against the repo; the numbers below are measured, not conceded on principle.

### 12.1 Corrections accepted

**(a) Texture residency — my claim was wrong.**

§2 and §4 above assert that "every race that has ever appeared this session stays resident at 6 MiB." That is not how Godot resources behave, and it is not what this code does. Verified in `Main.gd`: `_spawn_token()` and `_spawn_worker_token()` call `load()` per token with **no cache dictionary**, and `_despawn_token()` calls `queue_free()`. The texture reference dies with the token; `ResourceLoader`'s cache is weak, so the resource is released once nothing holds it. The revision's phrasing — decoded totals are "the maximum source cost, not guaranteed permanent residency" — is correct.

The hygiene argument survives, but it should be made on **steady-state**, not maximum:

```
Permanently resident (map furniture, never despawns):
  Throne, Barracks, Bone Pile, Pine_Tree/Stump, Berry_Grove ×2,
  Grave ×2, deposit, Icon_Dark_Essence, Necromancer_Portrait
  ≈ 10-12 textures × 4-6 MiB ................... ~40-50 MiB

Population-dependent (one per distinct race present):
  8 distinct races at steady state × 6 MiB .......... ~48 MiB

Realistic steady state ............................. ~90 MiB
```

~90 MiB resident for figures drawn at 32–44 px is still the point. "214 MiB always resident" was not.

**(b) Colour counts — the revision's figures are better than mine.**

Reproduced exactly:

| | all RGBA values | alpha > 0 |
|---|---|---|
| `Human_Outcast.png` | 63,895 | **51,362** |
| `Skeleton_Worker.png` | 41,496 | **41,202** |
| `Orc.png` | 55,934 | 46,386 |

My figures included fully-transparent pixels carrying generation-background chroma noise, which inflates the count and measures nothing useful. The revision's visible-pixel counts are the right metric. (In these files every visible pixel is fully opaque — alpha is binary, with no semi-transparent edge pixels at all. Worth knowing for the normalization pass: there is no soft alpha to preserve, so nearest-neighbour resampling is viable if the pixel-art contract is adopted.) The conclusion is unchanged: 51k colours is not indexed pixel art.

**(c) "Well under 1 MiB" was wrong — low single-digit MiB is the honest target.**

§7 above claims the folder drops "well under 1 MiB." That figure is only reachable at a 64² canvas for everything, and it quietly excluded the animation sheets and the terrain tileset. Recomputed against this review's own recommendations:

```
16 race tokens @ 64²  ....................... 256 KiB
Necromancer portrait @ 128² (UI needs it) .... 64 KiB
~13 buildings/nodes @ 64² (= CELL_SIZE) ..... 208 KiB
Orc + Wolf sheets, 20 frames @ 64² cells .... 640 KiB
Terrain_Tileset_Snow ......... must stay large, TBD
                                            ---------
                                      ~1.2 MiB + tileset
```

The revision is right to refuse the promise. **Low single-digit MiB** is the number to write into the acceptance criteria, and "measurements recorded" — which the revision already added — is the correct way to hold it.

### 12.2 One correction that is right and understated

The revision's Necromancer note is correct: do not swap `Necromancer.PORTRAIT` globally. §7C above was wrong to call it "one constant."

There are in fact **three consumers across two constants**:

| Consumer | Reads | Wants |
|---|---|---|
| `NecromancerToken` map sprite | `Necromancer.PORTRAIT` | full body |
| `Necromancer.get_inspect_data()` → `"sprite"` | `Necromancer.PORTRAIT` | portrait |
| `Main` HUD badge | `Main.NECROMANCER_SPRITE` (separate const, same file) | portrait |

So the fix is: add a new map-sprite path, point only the token at it, leave `PORTRAIT` serving the inspect payload and `Main.NECROMANCER_SPRITE` serving the badge.

**The same pattern applies to the Wolf, and the revision does not mention it.** `Wolf.SPRITE_PATH` feeds both `_sprite.texture` **and** `get_inspect_data()["sprite"]`. Swapping the token to a normalized sheet without splitting the constant will put an animation-sheet cell in the inspection panel. This is a general rule worth stating once in the pipeline doc: **map art and inspect-panel art are separate concerns wherever a unit is inspectable**, which is every unit.

### 12.3 Gaps remaining in the revision

Five, in descending order of consequence.

1. **No statement of where this sits in the build order.** The revision has five phases and no roadmap position. `COMBAT_SPEC.md` lists **C2 (the stat rework) as "next"** and §12 warns it is *"the single most likely thing to stall this work."* `ROGUELITE_REWORK.md` §13 has **R1 in progress**. This proof is a third parallel thread against a single-developer project. It needs one explicit sentence saying whether it runs *around* C2/R1 or *before* them — otherwise the honest risk is that all three sit half-finished.

2. **`races.json` collision with C2.** `CharacterVisual2D` needs a per-race pointer choosing `legacy_static` vs `animated`, which naturally belongs in `races.json` — the file C2 is about to re-author from 14 to 21 values per race, with `RACES.md` rewritten alongside it. Add the field, and flag it in `COMBAT_SPEC.md` §12's checklist so the re-author does not drop it.

3. **The shared appearance-ID recommendation was dropped.** §10 decision (7) above recommended a plain string appearance key in `races.json`, resolved independently by the map and portrait renderers. The revision resolves "keep map sprites separate from portraits" (about *assets*) but not the shared *ID*. These are different things, and the ID is the one that survives every other decision on the list. Since C2 is opening `races.json` anyway, that is the cheap moment — one field, no behaviour.

4. **The Wolf swap can regress a legibility fix with playtest history.** `CLAUDE.md` records that `TOKEN_SIZE = 46`, `z_index = 6` and the HP label's 4px black outline were all *reactive* fixes after two playtests in which the player never saw the wolf at all. A normalized sheet frame changes its silhouette and effective drawn size. "Readable under the night tint" is already in the acceptance criteria; the wolf specifically should be called out by name, because it has failed this test before.

5. **`FollowerToken` still described as "creates one `Sprite2D`."** It creates a `Sprite2D` **plus two `Label`s** (carry tag, exceptional ★); `WorkerToken` creates a `Sprite2D` plus one. This matters to Phase 2's integration shape: `CharacterVisual2D` replaces the *sprite child*, not the token, and must sit as a sibling of labels that keep reading `follower.carrying_amount`. Minor, but it is the difference between a clean insertion and a rewrite of two token classes.

**One testing note for Phase 3.** Exercising the Wolf means either waiting for dusk or using the 60× debug time scale. `CLAUDE.md` records the trap: `get_process_delta_time()` is **already** scaled by `Engine.time_scale`, so a harness that multiplies by it again advances its accounting 60× too fast and produces convincing false failures. Wolf spawn is guaranteed on the first dusk, then 55% per dusk after.

### 12.4 Disposition

**The revision is sound and the plan is approvable as written**, subject to the five items in §12.3 — of which only (1) and (2) need resolving before Phase 0 starts; (3) and (5) are one-line additions, and (4) is a line in the test plan.

Two things the revision improved on this review rather than merely accepting it: the fifth **digitigrade rig family** (a better answer than my "Gnoll gets its own treatment"), and **deferring the direction convention to the proof's outcome** rather than pre-deciding it — the Orc/Wolf comparison is precisely the experiment that should settle front-vs-side, so deciding first would have wasted the evidence.
