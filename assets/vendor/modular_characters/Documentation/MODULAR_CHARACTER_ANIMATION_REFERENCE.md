# Character Animation Pipeline — Reviewed Decision and Long-Term Reference

**Project:** Warlords / Undead Empire Prototype  
**Engine:** Godot 4.7.1  
**Art tool:** Aseprite 1.3.18.1  
**Status:** Reviewed decision; animation-sheet proof approved, full modular system deferred  
**Prepared:** August 3, 2026

## Purpose of this document

This document consolidates the proposed modular character-animation system, the independent review in [`MODULAR_CHARACTER_ANIMATION_REVIEW.md`](../MODULAR_CHARACTER_ANIMATION_REVIEW.md), a follow-up audit of the current repository, and the resulting implementation decision.

It distinguishes between:

- The **approved immediate work**: asset hygiene and a small animation-sheet proof using existing Orc and Wolf artwork.
- The **deferred long-term option**: a modular Aseprite-authored paper-doll system, to be reconsidered when visible equipment is scheduled.

The deferred long-term concept is a scalable paper-doll system in which:

- Animation data belongs to a reusable rig.
- A character supplies compatible body and appearance artwork.
- Equipment replaces or adds visual slots.
- Multiple races can reuse a small number of rig families.
- Pixel art remains crisp and hand-authored.
- Hundreds of simulation characters remain inexpensive to render.

## Executive conclusion

### Immediate decision

**Do not begin the two-character, one-weapon modular Aseprite vertical slice yet.** Visible gear is specified but unscheduled, while the repository already contains complete Orc and Wolf animation sheets that can validate the real runtime questions with no new character art.

Proceed instead with a smaller proof:

1. Preserve the high-resolution sources and generate normalized runtime-size assets.
2. Set texture filtering deliberately rather than inheriting an implicit default.
3. Introduce `CharacterVisual2D` with only `legacy_static` and `animated` renderer modes.
4. Normalize and wire `Orc_Animation_Sheet.png` and `Wolf_Animation_Sheet.png`.
5. Drive idle, walk, attack, and hurt from state already present in the simulation.
6. Judge animation readability, direction conventions, and coexistence with static tokens in the real game and under the night tint.

### Long-term decision

The modular paper-doll architecture remains technically feasible and potentially valuable once equipment and appearance variation have a scheduled gameplay payload. The existing commissioned figures are finished images rather than modular assets, so adopting that architecture will require a deliberate art-style conversion and substantial redraw work.

Godot capability is not the blocker. The unresolved risk is whether newly authored modular art can coexist with or replace the current pseudo-pixel commissioned artwork consistently enough to justify the production cost.

## Current project findings

### Existing runtime architecture

The production game currently renders characters as lightweight visual tokens over plain simulation objects:

- [`FollowerToken.gd`](../scripts/settlement/FollowerToken.gd) creates one `Sprite2D`, a carrying label, and an exceptional-recruit star label; the sprite displays followers at approximately 40 pixels wide.
- [`WorkerToken.gd`](../scripts/settlement/WorkerToken.gd) creates one `Sprite2D` and a carrying label; the sprite displays workers at approximately 32 pixels wide.
- [`NecromancerToken.gd`](../scripts/settlement/NecromancerToken.gd) creates one `Sprite2D` and displays the player at approximately 44 pixels wide.
- [`RaceCatalog.gd`](../scripts/autoload/RaceCatalog.gd) obtains the static map-sprite path from [`races.json`](../data/races.json).

This separation is worth preserving. Followers and workers should remain inexpensive simulation/data objects. `CharacterVisual2D` replaces only the sprite child; the existing labels remain sibling UI children and continue reading their current simulation fields.

### Official Sprites audit

The imported root of `Official Sprites/` currently contains 40 PNG files representing approximately **213.97 MiB of decoded RGBA8 pixels** if every texture is loaded simultaneously. The map-character set is approximately 98 MiB: 15 recruitable 1254×1254 race figures, the 1024×1024 Skeleton Worker, and the 1024×1024 Necromancer portrait.

The runtime scales those sources down to approximately 32–44 pixels. Current `.import` files use lossless compression, generate no mipmaps, and enable `process/fix_alpha_border`. `project.godot` does not explicitly select a canvas texture filter, so Godot's Linear default is inherited.

Godot Resources are reference-counted: an active token retains its texture, while a texture can leave the cache after all references are released. The decoded totals therefore describe the maximum source cost, not guaranteed permanent residency of every file that has ever appeared.

The source figures look pixel-inspired but are not conventional indexed pixel art. `Human_Outcast.png` contains 51,362 unique visible RGBA colors and `Skeleton_Worker.png` contains 41,202. A true low-resolution indexed redraw may therefore produce a noticeable style seam unless all runtime assets receive a consistent normalization treatment.

Other consequences:

- The characters have strongly different proportions. An elf, dwarf, goblin, troll, ogre, and minotaur should not share one exact set of pivots and limb lengths.
- Clothing and equipment are baked into most figures.
- Pixels hidden behind torsos, sleeves, hands, hair, and armor do not exist and must be drawn when parts are separated.
- `Orc_Animation_Sheet.png`, `Wolf_Animation_Sheet.png`, `Wolf_Pack_Animation_Sheet.png`, `VFX_Sheet.png`, and `Terrain_Tileset_Snow.png` are now named and alpha-keyed.
- The Orc and Wolf animation sheets appear to contain 4 columns × 5 rows, but their dimensions are not evenly divisible into that grid. They still require crop detection, uniform-cell output, baseline alignment, animation naming, and validation before Godot can consume them reliably.

The separate `Characters/Character - parts/` asset pack contains bodies, faces, and hair, but not articulated limb sets. It may help prototype a portrait creator, but it does not match the commissioned art style closely enough to mix into map characters without an intentional restyle.

### Equipment scope already specified by the game

[`COMBAT_SPEC.md`](../COMBAT_SPEC.md) deliberately limits equipment version 1 to one weapon slot. It explicitly defers armor slots, durability, inventory grids, and two-handed rules.

The visual architecture may reserve future slots, but the first implementation should author only `weapon_main`. Building the complete armor/equipment presentation system before the related gameplay exists would add unnecessary scope.

For the approved immediate proof, even `weapon_main` remains unimplemented. It returns to scope only when the gameplay equipment slice is scheduled.

## Approved immediate proof

### Asset hygiene

Keep the original high-resolution files under the existing `_originals/.gdignore` boundary and generate smaller runtime assets. The exact output size and resampling filter must be evaluated visually; the target is a low-single-digit-MiB runtime set, not an unsupported promise that the entire folder will fit below 1 MiB.

The normalization pass must:

- Preserve alpha correctly and avoid chroma-colored edge bleed.
- Crop transparent waste without losing a stable origin.
- Place each character on a standard transparent canvas.
- Align feet to an integer baseline.
- Use a consistent resampling policy for static and animated assets.
- Produce deterministic, reviewable outputs.
- Preserve high-resolution portraits independently where the UI needs them.

### Animation-sheet proof

Use the existing Orc and Wolf sheets to build the first animation path. A small project-owned normalization tool should inspect row bands and frame bounds, emit uniform cells, and write a metadata sidecar describing animation names, frame counts, timing, origin, and facing convention.

The proof should test:

- `legacy_static` and `animated` characters coexisting on the same map.
- Idle/walk state from `Laborer.TripStage`.
- Attack from `in_combat`.
- Hurt/recovery from `is_injured`.
- Horizontal facing and mirroring.
- Readability at 32–44 pixels and under the existing night tint.
- Whether front-facing Orc animation and side-facing Wolf animation establish an acceptable convention or reveal a direction mismatch that must be resolved before more sheets are produced.

### Map art and inspection art

Map rendering and inspection portraits are separate concerns for every inspectable unit, even when they currently share one file.

- `Necromancer_Full_Body.png` now exists, but the current map token and inspection UI both ultimately depend on `Necromancer.PORTRAIT`. Do not replace that constant globally. Add a separate map-sprite path for `NecromancerToken` while preserving the portrait for inspection and HUD use.
- [`Wolf.gd`](../scripts/world/Wolf.gd) currently uses `Wolf.SPRITE_PATH` for both the map sprite and `get_inspect_data()["sprite"]`. Do not redirect that shared constant to a normalized animation cell. Let `CharacterVisual2D` resolve the map animation while the inspection payload continues to resolve a dedicated Wolf portrait.

Use one stable `appearance_id` for identity, resolved independently by map and portrait systems. Shared identity does not imply a shared texture.

## Immediate system architecture

```text
Follower / Worker / Necromancer simulation state
                    |
                    v
             CharacterVisual2D
                /          \
       legacy static     animated
          Sprite2D     AnimatedSprite2D
                             ^
                             |
                 normalized sheet + metadata
```

### `CharacterVisual2D`

Add a reusable visual component below the existing token classes. For the immediate proof it should receive:

- Race or visual identifier.
- Current animation state.
- Facing direction.
- Legacy sprite path or animated visual definition.

It should initially support two renderer modes:

1. **Legacy:** displays the current single PNG.
2. **Animated:** displays normalized `SpriteFrames` through `AnimatedSprite2D`.

This permits gradual migration without a large one-time conversion. A future layered modular renderer may implement the same state-facing API without forcing the token classes to change again.

## Deferred modular architecture

The following resource model is retained as a long-term design reference only. It is **not approved for implementation during the Orc/Wolf animation-sheet proof**. Revisit it when visible equipment or large-scale appearance variation is placed on the gameplay schedule.

### Proposed data resources

#### Rig definition

Defines:

- Rig ID and compatible body profiles.
- Required visual slots.
- Standard animation names and timing.
- Socket names and default pivots.
- Direction rules and mirroring.
- Draw-order rules by direction or pose.
- Animation-event markers such as footsteps and attack impact.

#### Appearance definition

Defines:

- Rig ID.
- Body/profile ID.
- Skin or palette selection.
- Body-part asset IDs.
- Hair, face, and accessory choices.
- Legacy sprite fallback.

#### Equipment visual definition

Defines:

- Equipment ID and slot.
- Compatible rig families.
- Artwork keyed by direction, pose, and frame where required.
- Socket/grip information.
- Optional layer-hiding or hand-replacement rules.

### Deferred runtime options

A future layered paper-doll renderer would create more canvas items than the current single-sprite tokens. That cost may be acceptable at the project's actual visible-character count, so no composite-cache system is approved yet.

If profiling later shows a material cost, preserve these optimization options:

- Pack compatible parts into atlases to reduce texture changes.
- Cache an assembled animation by an appearance signature such as `rig + body + hair + weapon + armor`.
- Rebuild the cached result only when appearance or equipment changes.
- Render cached characters through one `AnimatedSprite2D` where practical.

Build any cache only after measuring a representative gameplay scene. Do not use an assumed target of hundreds of simultaneously visible characters as an immediate requirement.

## Deferred Aseprite modular-authoring contract

If the modular system is scheduled later, Aseprite should be the editable source of truth. Generated PNG sheets and JSON metadata should be treated as build products rather than hand-edited source files. These conventions are provisional until the smaller animation-sheet proof establishes the correct map scale, direction policy, and filtering treatment.

### Map-character format

Provisional starting standard for a future modular rig:

- Canvas: 64×64 transparent pixels, subject to the proof's visual results.
- Visible figure: approximately 32–44 pixels tall/wide, depending on body family.
- Foot/origin anchor: fixed integer coordinate across every frame.
- Integer-only pivots and part placement.
- No baked drop shadow; shadow is its own layer.
- Nearest-neighbor rendering in Godot.
- Portraits remain a separate 128×128 system.

### Initial layer groups

The map rig should begin with approximately 8–12 meaningful layers rather than the full 25-layer wish list:

```text
GUIDES                 hidden and never exported
shadow
cape_back
arm_back
shield
legs
boots
body
waist
chest_armor
head
hair
helmet
arm_front
weapon_main
effects_front
```

Some of these can be combined after testing. Fine facial elements such as individual eyes, beards, jewelry, and expression details are better suited to the separate portrait system at the current map scale.

### Initial animation tags

Suggested proof-of-concept timeline:

```text
idle        4 frames
walk        4 frames
attack      6 frames
hurt        2 frames, optional for the first technical test
death       deferred until the basic pipeline is proven
```

### Named slices and pivots

Suggested Aseprite slices:

```text
origin_feet
hand_main
hand_off
headgear
effect_origin
```

Aseprite can export slices and their pivots in JSON. For a future modular system, project-owned Godot rig resources should remain authoritative unless an importer proves deterministic and preserves the full contract. The design must not depend on a third-party importer retaining pivot metadata.

### Important equipment constraint

Equipment reuse does not mean one PNG per item in every case.

Approximate visual authoring cost is:

```text
compatible rig families × authored directions × required pose variants
```

A helmet may need direction and head-pose variants. A sword may need idle-grip, wind-up, swing, and recovery variants. Boots and gloves must match relevant limb poses. This is still substantially cheaper than redrawing complete characters, but it is not free.

## Proposed rig families

Do not begin with one universal humanoid skeleton. A practical initial classification is:

1. **Standard humanoid:** Human Outcast, High Elf, Dark Elf, Necromancer, possibly Hobgoblin.
2. **Small humanoid:** Halfling, Gnome, Goblin, Kobold.
3. **Stocky humanoid:** Mountain Dwarf, Gray Dwarf, Orc.
4. **Large/unusual humanoid:** Ogre, Troll, Minotaur.
5. **Digitigrade or unique humanoid:** Gnoll and any other creature whose feet, gait, or limb proportions fail the standard contracts.

Characters within a family may use body-profile offsets. A creature whose locomotion or limb topology differs significantly should receive a separate rig.

Non-humanoids should expose the same gameplay animation names—`idle`, `walk`, `attack`, `hurt`, `death`—but may use different internal renderers. Wolves and slimes, for example, may be more efficient and attractive as traditional cel animation.

## Available automation and integration options

### Direct Aseprite automation — recommended first

Aseprite is installed at:

```text
C:\Program Files\Aseprite\Aseprite.exe
```

Verified version: `1.3.18.1-x64`.

Its command-line and Lua scripting interfaces can create and modify saved `.aseprite` files, manage layers/frames/tags/slices, import references, export sheets and metadata, and perform validation. This is enough to build a deterministic in-repository asset pipeline without adding an MCP dependency.

Official reference: <https://www.aseprite.org/docs/cli/>

Operational limitation: automation works against files on disk, not unsaved state in an open Aseprite window. Human and automated edits should not save the same file simultaneously. Automation should modify a closed file or produce a versioned copy for review.

### Optional Aseprite MCP — not recommended for this work

No Aseprite MCP is connected to the current Codex session, and none is needed. A community bridge such as [`diivi/aseprite-mcp`](https://github.com/diivi/aseprite-mcp) can expose structured operations, but it also exposes unrestricted Lua execution. Direct Aseprite CLI/Lua automation already provides the required file operations with a smaller dependency and trust surface.

Decision: do not install an Aseprite MCP for the approved proof. Reconsider only if a later workflow requires interactive editor operations that cannot be handled safely through versioned files and project-owned scripts.

### Existing Godot MCP

The repository already contains and enables [`addons/godot_mcp`](../addons/godot_mcp). Its command modules cover scenes, nodes, scripts, resources, animations, runtime inspection, screenshots, profiling, testing, and other editor operations.

The add-on is not currently exposed as a callable tool in this Codex session, but the Godot side can still be implemented through project files and verified using the installed Godot 4.7.1 executable. Connecting the MCP later would improve editor convenience, not unlock a required capability.

### Candidate Godot Aseprite importers — deferred evaluation

The immediate proof should use no third-party Aseprite importer. Normalize the existing PNG sheets with project-owned tooling, emit explicit metadata, and generate or construct `SpriteFrames` deterministically. This keeps the first test focused on visual and runtime assumptions rather than plugin compatibility.

#### Importality

Repository: <https://github.com/nklbdev/godot-4-importality>

Relevant capabilities:

- Imports `.aseprite` sources.
- Produces sprite sheets, `SpriteFrames`, `AnimatedSprite2D`, or `AnimationPlayer` resources/scenes.
- Supports animation tags and frame timing.
- Supports splitting visible layers into independent animation resources.

#### Aseprite Spritesheet Importer

Repository: <https://github.com/ColinHeathman/godot-aseprite-spritesheet-importer>

Relevant capabilities:

- Automatically updates Godot resources when Aseprite sources are saved.
- Supports layer groups, frames, slices, split layers, `SpriteFrames`, and `AtlasTexture`.
- Is resource-oriented rather than generating an opinionated character scene.
- Was tested by its author on Godot 4.4.1 and claims compatibility with later versions; compatibility with this project's Godot 4.7.1 must be verified.

#### Aseprite Wizard

Repository: <https://github.com/viniciusgerevini/godot-aseprite-wizard>

Relevant capabilities:

- Godot 4 branch.
- Imports Aseprite tags and timing into `SpriteFrames`, `AnimatedSprite2D`, and `AnimationPlayer` workflows.
- Supports filtering layers and creating separate resources per layer.

No importer implements the entire paper-doll system. An importer handles the Aseprite-to-Godot bridge; project-specific appearance resolution, equipment compatibility, animation-state mapping, draw order, caching, and legacy fallback still require custom code. If an importer is reconsidered later, test Aseprite Wizard first in an isolated Godot 4.7.1 branch, then compare deterministic output and maintenance cost against the project-owned path.

## Recommended implementation sequence

### Roadmap gate — do not create a third parallel workstream

This proof is approved as a technical direction, not promoted ahead of the current roadmap. [`ROGUELITE_REWORK.md`](../ROGUELITE_REWORK.md) keeps R1 as the active staged build, and [`COMBAT_SPEC.md`](../COMBAT_SPEC.md) identifies C2 as the next combat slice and its race-stat authoring as the work most likely to stall progress.

Default order: finish the current R1 checkpoint and C2 before starting Phase 0. If this proof is intentionally moved earlier, explicitly pause or reschedule that work; do not run all three as partially active threads.

### Phase 0 — Freeze the source/runtime boundary

- Preserve commissioned high-resolution sources under `_originals/.gdignore` or an equivalent non-imported source folder.
- Record screenshots of representative characters at actual map zoom, in daylight and under the night tint.
- Choose an explicit canvas texture filter for the proof instead of relying on Godot's default.
- Define source, generated-output, and metadata folders; generated runtime assets must be reproducible rather than edited by hand.
- Treat canvas size, resampling filter, and facing direction as test parameters rather than permanent standards.
- Coordinate the visual data contract with C2's rewrite of `races.json`. Add a stable `appearance_id` and retain a per-race way to resolve `legacy_static` versus `animated` map visuals. Record both fields in C2's authoring checklist so the rewrite cannot silently drop them.

### Phase 1 — Normalize the Orc and Wolf sheets

Create a project-owned normalization tool that:

- Detects occupied frame bounds without assuming the source dimensions form a perfect grid.
- Crops frames safely, aligns them to an integer foot baseline, and writes uniform transparent cells.
- Assigns animation names and timing through an explicit metadata file.
- Records facing and mirroring rules.
- Detects empty or malformed frames and fails with useful validation messages.
- Produces byte-stable outputs when the source and configuration have not changed.

Run the tool first on `Orc_Animation_Sheet.png` and `Wolf_Animation_Sheet.png`. Leave the pack, VFX, and terrain sheets out of this proof unless one is needed to validate the same code path.

### Phase 2 — Add the Godot visual boundary

Implement `CharacterVisual2D` with:

- `legacy_static` rendering through `Sprite2D`.
- `animated` rendering through `AnimatedSprite2D`.
- A small state API for `idle`, `walk`, `attack`, and `hurt`.
- Facing/mirroring support.
- A visual definition that references normalized output and metadata.
- A safe fallback when animation data is absent or invalid.

Integrate it below the existing token classes without moving simulation authority or changing unrelated gameplay behavior.

For `FollowerToken` and `WorkerToken`, replace only the current `Sprite2D` child. Keep carrying and exceptional-recruit labels as siblings with their existing data flow, positions, and visibility rules.

### Phase 3 — Integrate and test real states

- Use the Orc animation for an Orc follower while other races remain legacy static sprites.
- Use the Wolf animation in the smallest existing or test-only creature path that exercises real movement and combat state.
- Map `Laborer.TripStage`, `in_combat`, and `is_injured` to visual states without allowing animation playback to own gameplay timing.
- Test direction changes, interrupted states, despawn/respawn, pause behavior, and missing assets.
- Compare at actual gameplay zoom and under the night tint rather than judging enlarged source art alone.
- Retest the Wolf by name: preserve or deliberately replace its proven `TOKEN_SIZE = 46`, `z_index = 6`, and outlined HP-label treatment. The normalized frame's changed silhouette must not undo the legibility fixes established through playtesting.
- Exercise dusk spawning at normal speed and the 60× debug speed. Test accounting must use Godot's already-scaled `delta`; never multiply `get_process_delta_time()` by `Engine.time_scale` again.

### Phase 4 — Separate portrait and map assets

- Add a dedicated Necromancer map-sprite reference and keep `Necromancer.PORTRAIT` for UI use.
- Split Wolf map-animation resolution from its inspection portrait before changing `Wolf.SPRITE_PATH` behavior.
- Apply the validated normalization policy to oversized static map figures where it produces an acceptable visual result.
- Measure source and runtime texture sizes before and after normalization.

### Phase 5 — Make the production decision

After the proof, decide among three paths:

1. Continue commissioning or producing conventional baked animation sheets for important units.
2. Keep most units static and animate only high-value characters and creatures.
3. Schedule the modular paper-doll system when visible equipment and appearance variation justify its additional art and engineering cost.

If the third path is selected, run a new approval gate for the two-character, one-weapon Aseprite vertical slice described in the deferred sections above. Do not infer that approval from success of the Orc/Wolf proof.

## Proof-of-concept acceptance criteria

The immediate proof is successful only if all of the following are true:

- The Orc and Wolf sheets normalize deterministically without manual edits to generated PNGs.
- Animated and legacy-static visuals coexist on the same map.
- Idle, walk, attack, hurt, and facing transitions reflect simulation state correctly.
- No texture bleeding, unstable edges, baseline jumps, or subpixel shimmer is visible at actual gameplay zoom.
- The characters remain readable under the existing night tint.
- The Wolf remains unmistakable at actual camera zoom, including at dusk/night, without regressing its established size, draw-order, or HP-label legibility.
- Missing frames, invalid metadata, and unsupported states produce validation errors or a safe legacy fallback.
- The visual component does not become simulation authority or alter combat/movement timing.
- Follower and worker carrying/exceptional labels retain their existing behavior after their sprite child is replaced.
- Map sprites and inspection portraits resolve independently for the Necromancer, Wolf, and any other inspectable animated unit.
- Unconverted races continue to work without asset or behavior regressions.
- Generated runtime assets materially reduce decoded texture cost compared with their oversized sources, with measurements recorded.
- The results provide enough evidence to choose a direction convention and one of the three production paths in Phase 5.

## Decision register

### Resolved for the immediate proof

- Use discrete sprite-frame animation; do not introduce `Skeleton2D` or a layered paper-doll renderer.
- Use Aseprite as an optional inspection/editing tool, not as a required live integration.
- Use direct CLI/Lua only when Aseprite automation is necessary; do not install an Aseprite MCP.
- Use no third-party Aseprite importer for the first proof.
- Do not build a composite-character cache before a modular renderer exists and real profiling warrants it.
- Keep map sprites separate from portraits.
- Use a shared stable `appearance_id` to identify a character across those separate map and portrait resolvers.
- Preserve the existing simulation classes and introduce a visual-only boundary.
- Start by testing the game's existing horizontal-facing/mirroring behavior; do not treat it as the permanent convention until the Orc/Wolf comparison is complete.

### Decide after the proof

1. Final direction convention: side-facing with mirroring, front/back/right with mirrored left, or a documented mixture by creature type.
2. Final runtime canvas and visible-character dimensions.
3. Resampling and Godot texture-filter policy for pseudo-pixel sources.
4. Whether baked animation sheets provide enough value or modular equipment visuals should be scheduled.
5. If modular work is scheduled, which races share each rig and whether any importer is worth adopting.

## Review disposition

The independent review's main recommendation is accepted: the original modular vertical slice is a **no-go for the current milestone**, while asset hygiene plus the Orc/Wolf animation-sheet proof is a **go**.

Accepted findings include:

- The current commissioned figures are monolithic and would require substantial redraw work to become articulated parts.
- Existing animation sheets can invalidate runtime assumptions sooner and with less art production.
- Explicit filtering, consistent map scale, source/runtime separation, and coexistence with legacy tokens should be solved before a broader character system.
- Gear and classes are specified but unscheduled; they do not currently justify a full paper-doll implementation.

Clarifications from the follow-up audit:

- Godot's resource cache does not imply that every texture ever loaded remains resident forever. Resources are reference-counted and can leave the cache after all references are released.
- The oversized source set has a meaningful decoded-memory cost, but the total is a maximum if all files are simultaneously referenced, not guaranteed permanent residency.
- Downsampling should reduce runtime cost dramatically, but the realistic target is likely low single-digit MiB rather than a promise below 1 MiB.
- A style mismatch between normalized or redrawn assets and the commissioned figures is a risk to test in game, not a proven impossibility.

The review addendum subsequently approved the revision subject to five documentation safeguards, all now incorporated: explicit placement after R1/C2 by default, protection of visual fields during the C2 `races.json` rewrite, a stable shared appearance ID, Wolf-specific legibility regression testing, and sprite-only insertion beneath existing token labels.

## Primary external references

- Aseprite CLI and automation: <https://www.aseprite.org/docs/cli/>
- Aseprite slices and pivot metadata: <https://www.aseprite.org/docs/slices/>
- Godot resources and reference-counted caching: <https://docs.godotengine.org/en/4.7/tutorials/scripting/resources.html>
- Godot texture filtering: <https://docs.godotengine.org/en/4.7/tutorials/2d/2d_antialiasing.html>
- Godot cutout animation: <https://docs.godotengine.org/en/stable/tutorials/animation/cutout_animation.html>
- Godot 2D skeletons: <https://docs.godotengine.org/en/latest/tutorials/animation/2d_skeletons.html>
- Godot `AtlasTexture`: <https://docs.godotengine.org/en/stable/classes/class_atlastexture.html>
- Community Aseprite MCP considered but not selected: <https://github.com/diivi/aseprite-mcp>
- Importality: <https://github.com/nklbdev/godot-4-importality>
- Aseprite Spritesheet Importer: <https://github.com/ColinHeathman/godot-aseprite-spritesheet-importer>
- Aseprite Wizard: <https://github.com/viniciusgerevini/godot-aseprite-wizard>
