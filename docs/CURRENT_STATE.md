# CURRENT STATE — What's Built, What's Open, What's Next

**Updated 2026-09-27.** **Rule (ruled 2026-09-27): every build or design pass updates this file
before it ends.** Only three things live here: where the project stands, what is still undecided,
and what comes next, including the playtest checklist. Everything else has one home somewhere else:
- **Design intent:** `design/ROGUELITE_REWORK.md` wins, with `design/LIVING_WORLD_SPEC.md` inside
  its frame. Rulings are in ROGUELITE §17 and LIVING_WORLD §15.
- **What the code actually does:** the newest file in `history/` (indexed in `history/README.md`,
  which also serves as the document timeline this file used to carry).
- **Conventions:** `CLAUDE.md`.

If this file disagrees with any of those, they win. Fix this file.

---

## 1. Where the project stands

**Built and verified:**
- The Stage 1–3 settlement loop, R1, and **all of R2**: the generated world with forests, fifteen
  lootable sites and wolf dens, his Arcane kit, deposit at the Throne, the escort, and the Raven.
- **The run** (R4-lite plus the XP and stash halves of R5): death ends the run. The endings are
  slain, abandoned, throne_fell, fled the region and victory (still the legacy placeholder). There
  is a run-end screen, XP from formulas (`design/PROGRESSION.md`), Second Wake at level 5, the stash,
  the Lair and carry-in slots.
- **Raise Dead is his starting spell:** no free skeleton, and 3 starting bones. Timed recruitment
  is off.
- **The demo shell:** InputMap keys, the pause menu, the title screen, and dev tools kept out of
  release builds. Export presets exist for Windows and Linux.
- **The HUD redo:** there is no bottom bar, and each piece appears the first time its mechanic
  does.
- **LIVING_WORLD L0–L3:** settlements with `GameState` as a façade over the player's, Harrowdale,
  the Hidden / Hunting stance, the Guild and standing, witnesses, blueprints and the roadside
  opening. L3 added downed and bleed-out, bind and finish, prisoners, the Cell, Search, Summon
  Ghoul and burial parties.
- **Harnesses, all green** (the counts are in `CLAUDE.md`). `measure_travel` has every row in band,
  and the headless boot is clean.

**Not built:** the manor victory, map shuffle and Lair trophies. LIVING_WORLD L4 onward: goblins,
adventurers, caravans and bandits (so prisoners cannot yet be traded or hired), plus the five
reputation axes, which now come with L4 (LIVING_WORLD ruling 17). Also C3, audio, a
settings/rebinding screen and mid-run saves.

---

## 2. Still undecided

1. **The unused addons** (`limboai`, `ziva_agent`) still load as GDExtensions on the designer's
   machine. A clean clone does not load them. Keep them or remove them?
2. **`_imgtmp_ui_kit/`** is the only copy of the menu art. It needs a home under `assets/`
   (SPRITE_SPEC naming) or an archive.
3. From the 2026-08-29 agenda: a third field action, and the deposit's audio and visual payoff.

**Known, and left alone on purpose:** the HUD placeholders ("Future roadmap goal", "Bounty board --
unlocks in Stage 4", "Upgrades -- coming soon") stay on the designer's instruction. The legacy
crusade and power wins still exist and end the run properly. A raised skeleton walks home in a
straight line through terrain, like every worker. "Might" survives in some comments and in unread
keys in `data/followers.json`. The dead Stage-4 helpers in `Main.gd` are never called.

**Settled 2026-09-27** (recorded where each one lives):
- R3 folds into LIVING_WORLD (LIVING_WORLD ruling 17).
- `court_infiltration` uses **leadership**.
- This file stays, under the update rule above.
- "Discovered" means one of his stood within sight of the site (RAVEN_SPEC §4). The designer
  confirmed this reading.
- The wolf den's gold weight stays at 30 (LOOT_SITES_SPEC). The designer confirmed it.

---

## 3. What comes next, in order

1. **The playtest: a human at the keyboard.** The R2 exit question is whether "one more grave, or
   turn back?" is a real choice. Use `GAME_IMPROVEMENT_REVIEW.md` §14 as the questionnaire. Then
   check:
   - **Combat feel:** is walking into 26px a decision or an accident? Is a lost escort the right
     sting?
   - **Screens at the real window size and font:** the run-end screen, his level line, the title,
     the pause menu, the controls list, the flee picker and the Lair. Does Space as pause clash
     with anything?
   - **The Raven:** does a ping mid-sortie invite or interrupt? Is 70% a day generous or noisy? Does
     the mark read?
   - **Numbers:** the XP amounts, the level curve and Second Wake's level (`data/progression.json`).
   - **The L2 first run:** wake on the road, follow the popup to the guild, take the den, raise the
     roadside grave, clear the den and come home knowing the Altar. Get seen once and watch
     standing drop *when the runner arrives*. Is 8/4 cells of attention fair? Is half pay at
     Suspected a warning or a shrug? Does pay into his hands (6 carry) feel like a wage or a chore?
   - **The village at a glance:** can a player read who does what? Does Hunting feel like a
     choice?
   - **L3:** is 45 s of bleed-out a decision or a scramble? Do guards rescue too eagerly (14 cells)?
     Is 1 food per prisoner per meal the right cost? Is the outlaw cave still fair now that
     outlaws fight to the last? Does the rope read?
2. **LIVING_WORLD L4** (`LIVING_WORLD_SPEC.md` §14): the goblin camp, raiding, adventurers taking
   bounties, MIA and badges. R3 is folded in here: the five axes on the villain, fed by the witness
   runner, with recruit offers when an axis passes a threshold. Also owed from L0: click-to-assign
   on empty buildings.
