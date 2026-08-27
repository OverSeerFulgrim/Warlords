# Warlords — Restructure Plan (Option B)

**Goal:** cut per-prompt AI cost by ~70–80% and make graphics work predictable, without discarding any verified system. Everything here is reversible — the repo is fully committed and pushed to GitHub, so the safety net already exists.

**The three cost centers this plan attacks, measured:**

| Problem | Evidence | Fix |
|---|---|---|
| CLAUDE.md is a 137KB history book | ~30k+ tokens loaded into *every* session | Pass 1: slim to ~8KB orientation; history moves to `docs/history/` |
| `Main.gd` is a 108KB monolith | every UI tweak drags the whole file into context | Pass 4: split into UI modules |
| Asset sprawl across 10 root folders | duplicate full-res art in `art/`, a duplicated vendor pack (`ORCLORD/`), a stray demo project, debug renders committed | Passes 2–3: triage, then reorganize with a grep-driven path migration |

**Ordering rationale:** docs first, because it makes every later prompt cheaper. Deletions before moves, because deletions need no path updates. Code split last, because it benefits from the cheaper prompts the earlier passes buy.

---

## Target folder tree

```
Warlords/
├── project.godot
├── CLAUDE.md                  ← slim orientation, ~8KB, hard budget (see companion draft)
├── README.md
├── addons/godot_mcp/
├── scenes/
├── scripts/                   ← unchanged structure; Main.gd shrinks in Pass 4
├── data/
├── tools/
├── docs/
│   ├── design/                ← GAME_OUTLINE, FOUNDATION_SPEC, ROGUELITE_REWORK,
│   │                            WORLD_MAP_PLAN, RACES, COMBAT_SPEC, TRAITS,
│   │                            TRAITS_IMPLEMENTATION_PLAN, GAME design .docx files
│   ├── art/                   ← SPRITE_SPEC (the one graphics rulebook), ART_BRIEF,
│   │                            MODULAR_CHARACTER_ANIMATION_REVIEW, Necromancer_Reference
│   ├── prompts/               ← CLAUDE_CODE_PROMPTS, ROGUELITE_PROMPTS, STAGE4_PROMPTS,
│   │                            CORE_POLISH_PROMPTS, ART_PASS_PROMPT
│   └── history/               ← the current CLAUDE.md narrative, carved into dated files
└── assets/
    ├── official/              ← the commissioned art (today's "Official Sprites/")
    │   ├── characters/        16 race tokens, Skeleton_Worker, Necromancer(x3),
    │   │                      Orc_Armed, Goblin_Armed, Gray_Dwarf_Miner,
    │   │                      Wolf_Portrait, Wolf_Pack
    │   ├── buildings/         Throne_of_Bones, Barracks, Bone_Pile, Dark_Altar
    │   ├── nodes/             Pine_Tree, Pine_Stump, Berry_Grove_Full/Picked,
    │   │                      Grave_Undisturbed/Dug_Up
    │   ├── icons/             Icon_Dark_Essence
    │   ├── terrain/           Terrain_Tileset_Snow
    │   ├── sheets/            Orc/Wolf/Wolf_Pack animation sheets, VFX_Sheet
    │   │                      (the 5 source-resolution files — never downsample)
    │   └── _originals/        keep as-is, keep the .gdignore
    ├── placeholder/           ← everything still standing in for real art
    │   ├── generated/         creature_deer, creature_wolf (from tools/)
    │   └── kenney/            House/, Tower/, castle_red, the referenced icons
    │                          (bones, crypt, materials_005_stone)
    └── vendor/                ← untouched packs kept for future use, one subfolder each
        ├── modular_characters/  (today's Characters/ — 534 files, kept for the
        │                         animation system, per MODULAR_CHARACTER_ANIMATION_REVIEW)
        ├── icons_pack/           (today's Icons/ — note the *.png.png filenames in Food/)
        ├── gui_pack/             (today's GUI/)
        └── tilemaps_pack/        (today's Tilemaps/)
```

Two rules make this tree stay clean:

1. **`official/` vs `placeholder/` is the load-bearing split.** "What's real art?" becomes a folder question, not an archaeology question. When commissioned art replaces a placeholder, the placeholder file is deleted in the same commit.
2. **`vendor/` is cold storage.** Nothing in it is wired at runtime except what's been promoted into `placeholder/` (`kenney/` or `modular/`). AI sessions never need to explore it.

**As built (Pass 3 deltas from the tree above):** `placeholder/modular/` holds the six
modular-character PNGs that `Main.SPECIES_SPRITES` / `FALLBACK_SPECIES_SPRITE` actually use, so
rule 2 holds; `placeholder/generated/` also took the project-authored placeholder art that Pass 2
kept; `vendor/roguelike_pack/` holds the Kenney roguelike sheets; `vendor/tilemaps_pack/Expansion/`
is the explicit home for the concept tiles (their `.import` files are now generated and committed);
and the pack's `Documentation/` (license, readme, preview) lives with it in
`vendor/modular_characters/`.

---

## Pass 0 — Safety (5 minutes, no AI needed)

- `git checkout -b restructure` — do the whole plan on a branch; merge to `main` when the harness passes at the end.
- `git tag pre-restructure` on main, so "the old layout" is one checkout away forever.

## Pass 1 — The docs diet (1 session; biggest win, zero risk) — ✅ DONE

**Result:** CLAUDE.md cut from 137KB to ~7KB (orientation only); ~20 root docs moved into
`docs/{design,art,prompts}/` and the old narrative carved into dated `docs/history/` files.


No code changes, no paths to break — markdown only.

1. Create `docs/{design,art,prompts,history}/` and `git mv` the ~20 root-level docs per the tree above. `stat_rework_roster.xlsx` → `docs/design/`. Delete the stray `.~lock.stat_rework_roster.xlsx#` lock file.
2. Carve the current CLAUDE.md into `docs/history/` files, split by its own section headings, e.g.:
   - `2026-07-foundation-reset.md`, `2026-07-physical-gathering.md`, `2026-08-art-pass.md`, `2026-08-combat.md`, `2026-08-villain-split.md`, `2026-08-world-map.md` …
   - Content moves verbatim — nothing is lost, it just stops being loaded on every prompt.
3. Replace CLAUDE.md with the slim draft (companion file, `CLAUDE_SLIM_DRAFT.md`). It keeps: what the game is, the current phase pointer, architecture conventions, the graphics rules pointer, the file map, the verification tools, and a one-line-each gotcha table. Everything narrative points into `docs/history/`.
4. Add the maintenance rule to the slim file itself: **CLAUDE.md has a hard ~8KB budget. Session write-ups append to `docs/history/`, never here.**

**Done when:** CLAUDE.md ≤ 8KB; every old section findable in `docs/history/`; game still boots (nothing should have changed, but run the headless boot anyway — it's free).

## Pass 2 — Asset triage: delete the dead weight (1 session) — ✅ DONE

**Result:** duplicate full-res art, committed debug renders, `ORCLORD/`, `demo/`, `_debug_char*/`
and the unreferenced Kenney building variants deleted; grep confirmed empty and boot stayed clean.


Deletions only — no moves, so no path updates. Verify with grep before each deletion group: `grep -rn "res://<folder>" scripts/ data/ scenes/` must come back empty.

| Target | What it is | Action |
|---|---|---|
| `art/` full-res duplicates | `Barracks.png`, `Throne_of_Bones.png`, `Necromancer_Portrait.png`, `Pine_Tree.png`, `Pine_Stump.png`, `Berry_Grove_*.png`, `Grave_*.png`, `Bone_Pile.png`, `Dark_Altar.png`, `Skeleton_Worker.png`, `icon_dark_essence.png` — 300–670KB *each*, superseded by the downsampled copies in Official Sprites | delete, plus their `*_sprite_<timestamp>.png` twins (each file exists twice) |
| `art/grid_band_*.png`, `grid_overview.png`, `detail_*.png` | committed debug renders | delete |
| `art/tile_ground_frozen.png` | documented as no longer used | delete |
| `art/follower_*.png` (10 files) | old Kenney stand-ins; only Ghoul/Wraith fallbacks may still be referenced via `Main.SPECIES_SPRITES` | grep first; delete the unreferenced ones |
| `ORCLORD/` | appears to be a second copy of the vendor pack (same Buildings/Characters/GUI/Icons/Tilemaps structure) | diff against the root-level copies to confirm, then delete the whole folder |
| `demo/` | stray demo project (agents/ai/assets/props/scenes — likely from an addon) | confirm no `res://demo` references, then delete |
| `_debug_char/`, `_debug_char2/` | debug output committed to the repo | delete; add to `.gitignore` |
| `experiments/` | scratch area (already documented as regenerable) | ensure gitignored |
| `Buildings/Bridge/`, `Buildings/building_all.png`, `Buildings/Castle/` (except `castle_red`) | unreferenced Kenney variants (grep confirms only House/, Tower/, castle_red are wired) | delete |

**Done when:** grep for each deleted path returns nothing; headless boot is clean; `git status` shows only deletions.

## Pass 3 — Asset reorganization: the moves (1–2 sessions) — ✅ DONE

**Result:** all art moved into `assets/official|placeholder|vendor/` (1244 renames, 57 reference
paths rewritten); old-prefix grep empty, import clean, headless boot clean, 40/40 sprite-scale
assertions pass, settlement screenshot unchanged. `vendor/` is genuinely cold storage — the six
runtime-wired modular-character PNGs were promoted to `assets/placeholder/modular/`.

This is the only risky pass, so it's driven by a checklist, not by memory:

1. **Build the definitive reference list first:** `grep -rn "res://" scripts/ data/ scenes/ project.godot | grep -i "\.png"` → save as the migration checklist. (Known reference sites from today's survey: `data/buildings.json` `sprite_path`, `data/races.json` `sprite`, `data/world_sites.json`, `ResourceField.gd` consts, `HouseStyle.gd`, `Main.gd` consts (`NECROMANCER_SPRITE`, `ICON_DARK_ESSENCE`, `SPECIES_SPRITES`), `Necromancer.gd` (`PORTRAIT`, `MAP_SPRITE`), `Wolf.gd`, `data/world_map.json` legend → `Terrain_Tileset_Snow`.)
2. `git mv` the files into the target tree. **Move each `.png` together with its `.png.import`** — the import file carries the resource UID; losing it breaks references on fresh clones.
3. Update every path on the checklist (mostly JSON strings + a handful of script consts).
4. Delete the now-empty old folders. Keep `_originals/` exactly as it is, `.gdignore` included.
5. **Verify with the tools that already exist for this:** one editor open so Godot reimports, then
   `godot --headless --path . --import`, then the 40-assertion `tools/check_sprite_scales.tscn`, then a headless boot, then `tools/capture_settlement.gd` for an eyeball screenshot.

**Done when:** all 40 sprite-scale assertions pass, boot log is clean, screenshot looks right, and `grep -rn "res://Official Sprites\|res://art/\|res://Buildings/\|res://Icons/" scripts/ data/ scenes/` returns nothing.

## Pass 4 — Split Main.gd (4–6 short sessions, one module each)

`Main.gd` (108KB) is the wiring root plus five unrelated UIs. Target: Main.gd ≤ ~15KB of wiring; each module owns one concern. Suggested cut lines, one session apiece, running the game between each:

| New file (`scripts/ui/`) | Takes from Main.gd |
|---|---|
| `HudTopBar.gd` | resource bar, day/clock readout, time-scale button, necromancer badge + position readout |
| `BuildMenu.gd` | build/demolish menus, placement mode state, `_try_place_pending` |
| `EconomyTab.gd` | priority rows, workforce summary |
| `EventPanelUI.gd` | event/recruit-offer panel, `_position_event_panel`, offer refresh |
| `InspectorActions.gd` | `_build_keep_actions` / `_build_barracks_actions` / `_build_necromancer_actions`, inspect pick-order glue |
| `TokenLayer.gd` | `_sync_worker_tokens` / `_sync_follower_tokens`, token hit-testing |

Rules for the split: modules talk through `EventBus` (the convention already exists); input arbitration (`_unhandled_input` mode priority: placement > demolish > rally > inspect) **stays in Main.gd** — it's the one thing that must see all modes. This is also the natural moment to note that the code-built debug UI is scheduled for replacement by a real `.tscn` UI later; the split makes that swap module-by-module instead of all-at-once.

**Done when:** each extraction ends with a clean boot + a quick manual click-through (build, inspect, event answer), and Main.gd is under ~15KB.

## Pass 5 — Guardrails so it stays fixed (30 minutes, mostly writing rules down)

These go in the slim CLAUDE.md (already included in the draft):

- **CLAUDE.md budget:** ≤ 8KB, orientation only. Session write-ups are dated files in `docs/history/`.
- **Asset intake rule:** new art lands in the correct `assets/` subfolder in the same commit that wires it, named per SPRITE_SPEC. Nothing lands at repo root. Placeholders die in the commit that replaces them.
- **One concern per AI session,** pointed at named files ("edit `EconomyTab.gd`"), not at the project ("fix the economy UI"). The folder structure now makes that possible.
- **SPRITE_SPEC.md is the single graphics authority** (canvas, baseline, content-height scaling, anchoring, body families). ART_BRIEF and the animation review are commissioning/reference docs, not rulebooks.

---

## What this costs vs. a restart

Passes 0–3 are roughly 3–4 focused sessions of mostly-mechanical work; Pass 4 is another 4–6 short ones you can spread out. Compare: rebuilding the trip loop, combat, morale, world map, fog, travel tuning, and re-doing all the human-keyboard QA from scratch — plus the same cleanup discipline being needed in the new project anyway. After Pass 1 alone, every session you run gets ~30k tokens cheaper, which pays for the rest of the plan as you go.

## Verification safety net (already in the repo)

- `godot --headless --path . --import` then headless boot — parse/load regressions
- `tools/check_sprite_scales.tscn` — 40 assertions that art draws at the size its constant claims
- `tools/measure_travel.tscn` — travel-time bands (rerun only if anything touches speed/layout; this plan doesn't)
- `tools/capture_settlement.gd` — seeded screenshot for eyeball diffs
- `git tag pre-restructure` — total rollback in one command
