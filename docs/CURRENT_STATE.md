# CURRENT STATE — What Is True Right Now

**Refreshed 2026-09-26** (end of day), replacing the 2026-08-09 snapshot, which still read "R2
unbuilt, P0 next". Same rules as before: this file reconciles every design document into one
current picture and records which doc wins on each disputed point. It is a snapshot, not a living
authority — when it disagrees with a doc amended after this date, the newer amendment wins and this
file should be refreshed or deleted (whether to keep it at all is still unruled; see §4).

**Dating note (still true):** the 2026-08-09 pass wrote amendment blocks marked "2026-08-06" into
`TERRAIN_SPEC.md`, `LOOT_SITES_SPEC.md`, `COMBAT_SPEC.md` and `NECROMANCER_SPEC.md`. Treat those as
that pass's changes.

---

## 1. The document timeline (oldest → newest)

| Date | Document | Standing today |
|---|---|---|
| pre-08-03 | `GAME_OUTLINE.md`, `FOUNDATION_SPEC.md`, `RACES.md`, `TRAITS*.md` | Settlement base layer. GAME_OUTLINE Stages 4–5 superseded by the rework. FOUNDATION: **carry = Endurance**; where it still speaks Might, COMBAT_SPEC §2 and `races.json` win. `RACES.md`'s stat table was **re-issued 2026-09-26** from `data/races.json`. |
| pre-08-03 | **`COMBAT_SPEC.md`** | **Live.** C1/C1.5 shipped; **C2 (the stat rework) built 2026-08-26** — nine attributes, Might gone from code. C3 (rout, judgement, wolf packs) is post-R2; C4→R5, C5→R4; C6 retracted. |
| pre-08-03 | `stat_rework_roster.xlsx` | **The authoritative statline source** and editing surface; `tools/export_roster.gd` exports it to `data/races.json`. The export rounded nine races' walk speeds to 0.1 (0.85 → 0.9 etc.). |
| 08-03 | `WORLD_MAP_PLAN.md`, **`ROGUELITE_REWORK.md`** | The plan of record, amended in §16 (2026-08-06) and **§17 (2026-09-26: death ends the run, Second Wake, Raise Dead, timed recruitment off)**. |
| 08-05 | R1 history: `2026-08-world-map-r1.md`, `2026-08-world-population-r1.md`, `2026-08-villain-split.md` | The record of R1's shipped code. |
| 08-05 (filed 08-09) | `GAME_IMPROVEMENT_REVIEW.md` | Product-level review lens, non-authoritative. Its §14 criteria are the **R2 exit playtest questionnaire**. |
| 08-06 → 08-09 | The seven R2 slice specs: `TERRAIN`, `LOOT_SITES`, `SORTIE`, `ESCORT`, `RAVEN`, `NECROMANCER`, `COMBAT_FEEDBACK` | **Reviewed 2026-08-29 and all built.** Amendment blocks bind over spec bodies. |
| 08-09 | **`R2_PROMPTS.md`** | **Every prompt has landed** (P0, U1, F1, C2, P1, P2, R2a–R2e). |
| 08-27 | `2026-08-27-r1-playtest-notes.md` | R1 feel playtest done; the gate opened. |
| 08-29 | `2026-08-29-r2-spec-review-agenda.md` (moved to `history/` 2026-09-26) | The seven-spec review. Its still-open items are carried in §4. |
| late 08 | History files for C2, P1, P2, R2a–R2d (see `history/README.md`) | The record of what was built. |
| 09-26 | `REVIEW_2026-09-26.md` | Fresh-eyes review, a **snapshot**. Its addendum lists what got fixed the same day. |
| 09-26 | **`LIVING_WORLD_SPEC.md`** | Design target after R2: all rulings issued (1–12, then **13–15**, the L0 model). Not yet prompted; its first pieces are built (§2). |
| 09-26 | **`PROGRESSION.md`** + `data/progression.json` | **Live.** XP formulas, the level curve, unlocks. |
| 09-26 | `2026-09-26-run-lifecycle-and-raise-dead.md`, `2026-09-26-raven.md`, `2026-09-26-demo-shell.md` | Today's three passes, in that order. |

**Precedence rule, unchanged:** `ROGUELITE_REWORK.md` wins on design intent; the newest history
file wins on what the code actually does; `CLAUDE.md` wins on conventions.

---

## 2. Where the project stands

- **Built and verified:** the Stage 1–3 settlement loop, R1, and **all of R2** — the generated
  world with forests, fifteen lootable sites and wolf dens, his Arcane kit, deposit at the Throne,
  the escort, and **the Raven** (honest dawn pings, camp occupancy, discovery as its own flag).
- **Also built 2026-09-26, ahead of the roadmap:**
  - **Death ends the run** (R4-lite + the XP half of R5, `scripts/run/`). Endings: slain,
    abandoned (behind a confirm), throne_fell, victory (still the legacy placeholder). A run-end
    screen with epitaph, stats, XP, level and next unlock. XP is banked per deed in
    `user://meta_profile.json`; harness runs never write it. **Second Wake** (level 5, once per
    run) is the only way he wakes at the Throne.
  - **Raise Dead is his starting spell:** a grave's corpse is free and becomes a real Skeleton
    Worker; otherwise 5 bones, anywhere. **No free starting skeleton; 3 starting bones**, so the
    first dead come from a grave. Timed recruitment is off.
  - **The demo shell:** every key an InputMap action by physical key, pause menu, title screen,
    Surrender confirm, dev tools out of release builds, Windows/Linux export presets built and run.
- **Harnesses, all green:** verify_stats 505, verify_loot_tables 536, verify_terrain 278,
  check_sprite_scales 122, verify_sortie 67, verify_villain_combat 65, verify_guild 62,
  verify_escort 58, verify_village 56, check_fog_and_minimap 50, verify_run_lifecycle 49,
  verify_raven 39, verify_demo_shell 39, verify_endings 33, verify_combat_feedback 31,
  verify_raise_dead 26, smoke_site_actions 26; measure_travel all rows in band; headless boot clean.
  - **What each ending keeps** (ROGUELITE §17.7): victory keeps all gear and relics, **fleeing the
    region** from the lair keeps 3 of the player's choice, death keeps nothing. The stash, **the
    Lair** (title and run-end buttons; shelves; carry-in 1 → 3 slots at levels 7/10, lost on death).
  - **LIVING_WORLD L0–L2:** `Settlement` with `GameState` as its façade; **Harrowdale**, a working
    village of eight named people (jobs, meals, guard training, alarm, restaffing, bodies); the
    **Hidden / Hunting stance** (H); **the Adventurers' Guild** with a board generated from world
    state and pay into his hands; **witnesses** whose runners lower standing only on arrival; the
    **Altar blueprint** learned by clearing a den; **he wakes on the road** with a first-run popup,
    and a roadside grave past the guild.
- **Not built:** the manor victory, map shuffle, Lair trophies; R3's reputation axes;
  LIVING_WORLD L3 onward (prisoners, so Summon Ghoul is shown but not castable); C3; audio; a
  settings/rebinding screen; mid-run save.
- **The prompt order** (`R2_PROMPTS.md`), all landed:

  ```
  playtest R1 → P0 → U1 → F1 → C2 → P1 → P2 → R2a → R2b → R2c → R2d → R2e
  ```

---

## 3. Decisions made (2026-09-26 rulings)

1. **Death ends the run.** Waking at the Throne is the **Second Wake** unlock (level 5 = 1,000 XP,
   once per run), not the default (ROGUELITE_REWORK §17).
2. **Raise Dead is the starting spell.** Raised corpses are ordinary Skeleton Workers; Raise Dead
   for 5 bones replaced the "Recruit Worker" buttons. **No starting skeletons on any run**
   (LIVING_WORLD ruling 9); starting bones = 3.
3. **R4-lite before R2e** (review ruling 7.9) — done in that order.
4. **XP comes from formulas** (`PROGRESSION.md`): deed = base × band; flat XP for wolves, buildings
   and banked loot; 25 per full day survived; level *L* needs 100 × L × (L−1) / 2; cap 20.
5. **Timed recruitment is switched off** (`EventSystem.TIMED_RECRUIT_OFFERS = false`); the offer
   machinery stays for R3.
6. **LIVING_WORLD L0 model (rulings 13–15, built 2026-09-26):** each settlement has its own stockpile, and
   `GameState` is a façade over the player's; production keeps the worker trip loop, with job slots and integrity
   multiplying each trip's yield (the player's Throne: unlimited slots, 100% integrity); NPCs get
   attention ranges, and the Necromancer gets a **Hidden / Hunting stance**, never an attack button.
7. **Built as a deliberate reading, awaiting confirmation:** a site is "undiscovered" until he or
   one of his units stands within fog-sight of it (not the fog state); the wolf den's gold weight
   went 26 → 30.

The 2026-08-09 decisions (stat rework, the Arcane Necromancer, creatures on the nine, forests as the
third wall, wolf dens, red damage numbers, relic attribute deltas) are all built; the history files
are the record.

---

## 4. Known rough edges and open questions

**Still open — not decided:**
1. **How R3 relates to the built guild standing** — R3's five reputation axes alongside the per-faction standing L2 built, or folded into it: recommended (fold), not ruled.
2. **CURRENT_STATE.md** delete vs refresh — not ruled (this refresh follows the ask that every doc
   match today).
3. **The unused addons** (`limboai`, `ziva_agent`) still load as GDExtensions on the designer's
   machine, which a clean clone does not.
4. **`court_infiltration`'s stat** (mercantile vs leadership), and **`_imgtmp_ui_kit/`** (move or
   delete; it is the only copy of the menu art).
5. **LIVING_WORLD:** every ruling is issued (1–16); nothing open.
6. From the 2026-08-29 agenda: a third field action, and the deposit's audiovisual payoff.

**Known, left alone on purpose:**
- The HUD placeholders ("Future roadmap goal", "Bounty board -- unlocks in Stage 4", "Upgrades --
  coming soon") stay, on the designer's own instruction.
- The legacy crusade and power win still exist; they now end the run properly.
- A raised skeleton walks home in a straight line through terrain, like every worker.
- "Might" survives in some code comments and as unread keys in `data/followers.json`; the dead Stage-4
  helpers in `Main.gd` (`_forge_equipment`, `_train_followers`, `_dispatch_random_mission`) are
  never called.

---

## 5. What happens next, in order

1. **The R2 exit playtest — a human at the keyboard.** Is "one more grave, or turn back?" a real
   question? Use `GAME_IMPROVEMENT_REVIEW.md` §14 as the questionnaire, plus the deferred feel
   questions: is walking into 26px a decision or an accident, and is a lost escort the right sting?
2. In the same session, the things only a human can check:
   - the run-end screen, the level line in his panel, the title, the pause menu and the controls
     list at the real window size and font; whether Space as pause fights anything;
   - whether a Raven ping mid-sortie invites or interrupts, whether 70% a day is generous or
     noisy, whether the "stood within sight of it" reading of *discovered* is right, and the
     mark's look;
   - the XP numbers, the curve and Second Wake's level (`data/progression.json`);
   - whether the wolf den should stay leaner than its new gold weight;
   - **the L2 first run** (LIVING_WORLD §14's exit): wake on the road, follow the popup to the
     guild, take the den, raise the roadside grave on the way, clear the den, come home knowing
     the Altar. Get seen once and watch standing drop *when the runner arrives*. Are 8/4 cells of
     attention fair? Is half pay at Suspected a warning or a shrug? Does pay into his hands (6
     carry) feel like a wage or a chore?
   - the village at a glance: can a player read who does what, and does Hunting feel like a choice;
   - the flee picker and the Lair at real size.
3. **Then LIVING_WORLD L3** (`LIVING_WORLD_SPEC.md` §14): downed / bleed-out, prisoners, the Cell —
   which also makes Summon Ghoul castable. Also owed from L0: click-to-assign on empty buildings.
   How R3's reputation axes fit (alongside, or folded into the standing model) is the open ruling
   above.

Housekeeping: CRLF normalization was committed long ago (`19fc078`); nothing is owed there.
