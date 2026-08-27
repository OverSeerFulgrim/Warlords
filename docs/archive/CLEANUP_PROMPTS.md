# Cleanup Prompts — one per session, in order

Companion to `CLEANUP_PLAN.md` (repo root). Paste one prompt per **fresh** Claude Code session,
run from `C:\Users\sjodz\Warlords`. Don't chain passes in one session — a fresh session after
Pass 1 loads the slim CLAUDE.md and runs much cheaper.

**Before Prompt 1, run these yourself (no AI needed):**

```
git tag pre-restructure
git checkout -b restructure
```

**Godot editor: keep it CLOSED during Passes 1–3** (it fights file moves), open it again after
each pass's `--import` step.

---

## Prompt 1 — Docs diet (do this one first; it makes every later session cheaper)

```
Read CLEANUP_PLAN.md at the repo root, section "Pass 1 — The docs diet". Execute it exactly:

1. Create docs/design/, docs/art/, docs/prompts/, docs/history/.
2. git mv the root-level docs into them per the plan's target tree:
   - docs/design/: GAME_OUTLINE.md, FOUNDATION_SPEC.md, ROGUELITE_REWORK.md, WORLD_MAP_PLAN.md,
     RACES.md, COMBAT_SPEC.md, TRAITS.md, TRAITS_IMPLEMENTATION_PLAN.md,
     Warlords_World_Map_Scale_and_Exploration_Plan.docx, stat_rework_roster.xlsx
   - docs/art/: SPRITE_SPEC.md, ART_BRIEF.md, MODULAR_CHARACTER_ANIMATION_REVIEW.md,
     Necromancer_Reference.md
   - docs/prompts/: CLAUDE_CODE_PROMPTS.md, ROGUELITE_PROMPTS.md, STAGE4_PROMPTS.md,
     CORE_POLISH_PROMPTS.md, ART_PASS_PROMPT.md
   Delete the stray lock file ".~lock.stat_rework_roster.xlsx#".
3. Carve the CURRENT CLAUDE.md into docs/history/ as dated files split at its own section
   headings (e.g. 2026-07-foundation-reset.md, 2026-07-physical-gathering.md,
   2026-08-art-provenance.md, 2026-08-combat-and-wolf.md, 2026-08-command-undead.md,
   2026-08-villain-split.md, 2026-08-world-map-r1.md, 2026-08-world-population-r1.md,
   plus a 2026-07-early-passes.md for everything older). Content moves VERBATIM — do not
   summarize, do not drop anything.
4. Replace CLAUDE.md with the contents of CLAUDE_SLIM_DRAFT.md (repo root), then delete
   CLAUDE_SLIM_DRAFT.md. Fix any doc paths in the slim file that don't match where you
   actually moved things.
5. Verify: CLAUDE.md is under 9KB; grep confirms no root-level .md remains except CLAUDE.md
   and README.md; run "godot --headless --path . --quit-after 200" and confirm a clean boot
   (nothing should have changed — this is a canary).
6. Commit with message "docs: slim CLAUDE.md to orientation-only; move history and specs to docs/".

Do NOT touch scripts/, data/, scenes/, assets, or project.godot in this session.
```

## Prompt 2 — Asset triage (deletions only)

```
Read CLEANUP_PLAN.md at the repo root, section "Pass 2 — Asset triage". Execute it exactly.

For EACH deletion group in the plan's table, first run
  grep -rn "res://<path-or-folder>" scripts/ data/ scenes/ project.godot
and only delete when the grep is empty. Groups: the full-res duplicates and timestamped twins
in art/, the grid_band_*/grid_overview/detail_* debug renders, tile_ground_frozen.png, the
unreferenced art/follower_*.png files (check Main.gd's SPECIES_SPRITES first — Ghoul and
Wraith fallbacks may still be referenced; keep any that are), the ORCLORD/ folder (first
verify it duplicates the root-level Buildings/Characters/GUI/Icons/Tilemaps packs — spot-check
a few file hashes), the demo/ folder (verify no res://demo references), _debug_char/,
_debug_char2/, Buildings/Bridge/, Buildings/building_all.png, and Buildings/Castle/ EXCEPT
castle_red.png which is referenced by data/world_sites.json.

Delete each PNG together with its .png.import. Add _debug_char*/, experiments/, and
_to_delete/ to .gitignore.

Verify: re-run every grep and confirm empty; "godot --headless --path . --quit-after 200"
boots clean with no missing-resource errors; git status shows only deletions and .gitignore.
Commit as "chore: delete duplicate, debug, and unreferenced assets (see CLEANUP_PLAN.md Pass 2)".

Do NOT move or rename anything in this session — deletions only.
```

## Prompt 3 — Asset reorganization (the careful one)

```
Read CLEANUP_PLAN.md at the repo root, sections "Target folder tree" and "Pass 3". Execute:

1. FIRST build the checklist: grep -rn "res://" scripts/ data/ scenes/ project.godot | grep -i png
   Save the output to /tmp or a scratch buffer. This is the definitive list of paths to update —
   work from it, not from memory.
2. git mv the art into the new assets/ tree per the plan (official/ split into
   characters/buildings/nodes/icons/terrain/sheets, _originals/ moved as-is with its .gdignore;
   placeholder/generated/ for creature_deer + creature_wolf; placeholder/kenney/ for the
   referenced House/, Tower/, castle_red, and the referenced kenney icons; vendor/ for the
   Characters, Icons, GUI, Tilemaps packs). Move every .png WITH its .png.import file.
3. Update every path from the step-1 checklist (data/buildings.json, data/races.json,
   data/world_sites.json, data/world_map.json legend, ResourceField.gd, HouseStyle.gd,
   Main.gd consts, Necromancer.gd, Wolf.gd, and anything else the grep found).
   Also update path references inside tools/ scripts (the harnesses and generators).
4. Delete the now-empty old folders ("Official Sprites", art, Buildings, Characters, Icons,
   GUI, Tilemaps).
5. Verify, in this order:
   a. grep -rn "res://Official Sprites\|res://art/\|res://Buildings/\|res://Icons/\|res://Characters/\|res://GUI/\|res://Tilemaps/" scripts/ data/ scenes/ tools/ project.godot  → must be EMPTY
   b. godot --headless --path . --import
   c. godot --headless --path . --quit-after 200  → clean boot, zero missing-resource warnings
   d. godot --headless --path . res://tools/check_sprite_scales.tscn  → all 40 assertions pass
   e. run tools/capture_settlement.gd (windowed) and confirm the screenshot looks normal
6. Commit as "refactor: reorganize art into assets/official|placeholder|vendor (CLEANUP_PLAN.md Pass 3)".

If any single verification fails, fix forward within the session; if the pass goes sideways,
git checkout -- . and report what went wrong instead of pushing through.
```

## Prompt 4 — Main.gd split (repeat this prompt once per module, 6 sessions)

Use this template, substituting one row per session from the table in CLEANUP_PLAN.md Pass 4.
Do them in this order: HudTopBar, EconomyTab, EventPanelUI, BuildMenu, InspectorActions, TokenLayer.

```
Read CLEANUP_PLAN.md at the repo root, section "Pass 4 — Split Main.gd". This session extracts
exactly ONE module: {MODULE} (scripts/ui/{MODULE}.gd), which takes {RESPONSIBILITIES} from
Main.gd.

Rules: the module communicates through EventBus signals and explicit references passed in from
Main.gd at _ready — no lookups, no new autoloads. Input-mode arbitration in _unhandled_input
stays in Main.gd. Move code, don't rewrite it — behavior must be identical. Main.gd keeps a
reference to the module and delegates; delete the moved code from Main.gd in the same commit.

Verify: godot --headless --path . --import (new class_name), then a headless boot, then tell me
what to click in a real window to smoke-test this module (I'll do it by hand — remember MCP
simulated input doesn't reach the game). Report Main.gd's new size in KB.

Commit as "refactor(ui): extract {MODULE} from Main.gd".
```

First instantiation, ready to paste:

```
... This session extracts exactly ONE module: HudTopBar (scripts/ui/HudTopBar.gd), which takes
the resource bar, the day/clock readout, the time-scale button, and the necromancer badge +
position readout from Main.gd. ...
```

## Prompt 5 — Wrap up and merge

```
Read CLEANUP_PLAN.md Pass 5. Confirm the guardrails are present in CLAUDE.md (size budget,
asset intake rule, history-file rule, SPRITE_SPEC as single graphics authority) — add any
missing ones concisely. Verify CLAUDE.md is still under 9KB. Run the full check battery from
Pass 3 step 5 one more time. Then: git checkout main && git merge restructure && git push,
and delete the restructure branch. Finally, delete CLEANUP_PROMPTS.md and move CLEANUP_PLAN.md
to docs/history/2026-08-restructure-plan.md with a one-line note at the top saying it was
executed.
```

---

## Session hygiene (why these are written this way)

- **One pass, one session.** Never continue into the next pass — fresh sessions get the slim
  CLAUDE.md and stay cheap.
- Each prompt names its files and forbids touching anything else, so the session never has to
  explore.
- Verification is in-prompt so sessions self-check instead of you discovering breakage later.
- Human-keyboard smoke tests are called out explicitly (MCP input can't reach the game — a
  documented project constraint).
