# Downed, prisoners, the Cell, Summon Ghoul, burial (LIVING_WORLD L3, 2026-09-27)

`LIVING_WORLD_SPEC.md` §14's L3, built on sections 5.7, 10 and 11 and ruling 6. The designer
said "please proceed" to "start L3 now, before the playtest". The exit this stage is judged by:
**capture-or-slay is a real choice because prisoners do something corpses don't; bodies you leave
come back as graves.**

## Downed (§11.2)

- **At 0 hp a humanoid goes down instead of dying**, with a bleed-out window
  (`data/captives.json`, 45 s). Villagers and outlaws go down. Wolves don't: wildlife kills, and a
  dead sentinel was dead already.
- `CombatSystem._remove_attacker` is the one hook. A `Villager`, or a `SiteGuardian` whose kind has
  `downs`, goes to `Captives.down_villager` / `down_guardian` when `captives` is set. With no
  `captives`, 0 hp is still death.
- **A downed villager** stays the village's man: `Villager.downed`, off `living()`, no work, no
  meals, and his job stays his. His token is hidden and `Captives` draws him lying down, with a
  bleed bar and a `down · Ns` tag. If he was running to tell someone, the report dies with him
  ("run the man down before the gate").
- **A downed outlaw** leaves his cave's guard the way a dead one did, so the cave can clear. What
  is left is a man on the ground.
- **The window runs out:** he dies of it. A villager goes through `Village.on_villager_killed`
  (body, restaffing, and `slew_a_villager` credited to whoever put him down). An outlaw leaves a
  body. That is new: outlaws used to leave nothing.
- **Bind** (only standing over him, 72 px) turns him into a prisoner. **Finish** leaves a corpse,
  exactly what a kill used to be. **Bind all / Finish all** (§11.3) act on every downed man within
  5 cells.
  - **Keys:** **G** and **X**.
  - **Action bar:** Bind and Finish buttons that show only while someone is down near him.
  - **The downed man's panel:** Bind, Finish, and the batch buttons when more than one is down.
- **Rescue (villagers):** a free guard (no alarm, not panicked, no errand) goes for a downed
  villager within 14 cells. He picks him up; the man does not bleed while carried. The guard takes
  him to his house, where he comes round at 35% hp, panicked, with his job. If the guard is downed,
  killed, taken or panicked, the man is dropped and starts bleeding again.
- **Outlaws never flee** (`never_flees` on the kind). They fight to 0 in their own cave, which is
  what puts them on the ground to be bound. The cave fight is a little longer than it was.

## Prisoners (§10)

- **`Prisoner`** (RefCounted): name, race, faction, where he was taken, searched, meals missed.
  On the rope he is in **`Necromancer.prisoners`** (per villain). In a Cell he is in
  **`Settlement.prisoners`** (the settlement owns its own, ruling 13).
- **Binding** records `took_a_prisoner` (Cruelty, 10 XP × band) and is witnessable ("taking Edda
  prisoner"). A villager bound is `captured`: the village reads it like a loss (restaffing, his
  building keeps his name) but leaves no body.
- **The rope:** prisoners walk behind him, 30 px apart. They keep up and do not slow him. A rope
  line is drawn from him down the chain. If he falls, the rope goes slack: villagers walk home
  (`Village.on_villager_freed`) and outlaws are gone.
- **Home** (6 cells of the Throne): prisoners go into a **Cell** while there is room. With no Cell
  they stay on the rope, and he is told once per visit.
- **The Cell** (`buildings.json` `cell`): a blueprint, 6 wood / 6 stone, holds 4.
  - The panel lists who is inside with Search and Summon Ghoul buttons.
  - Its sprite is a placeholder (`building_crypt_kenney.png`).
- **Meals (ruling 6):** every prisoner, in a Cell or on the rope, eats 1 food at dawn and at dusk
  from the treasury. A missed meal is logged. **Two missed in a row and he dies where he is held**,
  leaving a body to raise.
- **Search** (§10.3 use 3), once per prisoner.
  - He finds 0–3 gold and 0–2 food, into his pack and banked at the Throne like any haul.
  - **The first search, while the Cell is unknown, always teaches the Cell blueprint.** That is how
    a player learns it: capture → search → build.
  - After that there is a 25% chance of another unknown blueprint.
  - Records `search_a_prisoner` (5 XP).
- **Not yet:**
  - Trading to bandits (needs the bandits, L6).
  - Hiring as mercenaries (L7).
  - Blood for vampires (L8).

## Summon Ghoul (ROGUELITE_REWORK 17.5)

- **It needs:** level 2, a built Dark Altar, a prisoner (in the Cell or on the rope), and him at
  home. The Altar panel offers one button per prisoner, or a disabled button with the reason.
  `Captives.ghoul_blocker()` is the one list of reasons.
- **A Ghoul is a `Worker` with the Ghoul race row.** `Worker` takes a race id;
  `WorkerSystem.raise_unit_at`. It is named for the man he was ("Edda the Ghoul"), is Undead so
  Command Undead and the escort take him, and works the trip loop. Records `summon_a_ghoul`
  (30 XP).
- **The Ghoul row is in the workbook** (`stat_rework_roster.xlsx`): Str 7 Dex 3 Spd 6 End 6 Int 2,
  Undead, player-made, labor template. That makes 20 hp, walk 1.1 and Melee.
  - It fills the blank rows under Human Outcast on Attributes, Race skills and Effective skills.
    LibreOffice recalculated the cached values.
  - `export_roster.gd` maps "Ghoul". Its output matched the hand-merged `races.json` exactly.
  - The token art is the placeholder `character_036.png`.

## The dead are buried (§5.7)

- **A body is found** when any living villager is within 6 cells of it (`body_notice_cells` in
  `village.json`, default 6). That raises threat by 1. **A hidden body** (the body sheet's "Drag
  him out of sight") **is never found.**
- **A free guard is sent** (after rescues, never during an alarm). He lifts the body (the body
  site is removed, so there is nothing left to raise there) and carries it to the village
  graveyard at 75% speed, with a "carrying Frank" tag.
- **Each burial is a new grave**, named for him ("Frank's Grave", `WorldSites.spawn_grave`). It
  uses the fresh-grave grammar: raise him free, rob him, return his things. The graves sit in
  rows beside the Village Graveyard, and he has to find them like any site.
  - This is simpler than the spec's "fixed set that fills, then grows": every burial grows it.
- **If the guard drops the body** (downed, killed, taken, or panicked), it lands where he stands
  as a body again.
- **`WorldSite`** gained `corpse_present()` and `is_concealed()`; bodies carry `body_of` meta.

## HUD

- **Action bar:** **Bind** (G) and **Finish** (X), only while a downed man lies within reach.
- **Under the portrait:** a prisoner line, only while he holds anyone, e.g. "On the rope: Frank,
  Edda — walk them home · The Cell: 1 / 4 · 1 hungry".
- **Clicking:** a downed man or a prisoner can be clicked (`Captives.pick_at`, asked before the
  village's people).
- **Panels:** his own panel lists his rope with Search buttons. The Cell and the Altar have
  action blocks.
- **Log lines** for every step; names read mid-sentence through `Main._who()` ("an outlaw").

## Harnesses

- **`verify_captives` 71 (new).** It covers:
  - the Ghoul row;
  - down not dead, and bleeding out into a body credited to him;
  - bind only in reach, and the rope following him;
  - home with no Cell (told once), and the first search teaching the Cell;
  - into the Cell, meals, and a two-meal starvation into a body;
  - every Summon Ghoul blocker, and the Ghoul itself;
  - Bind all / Finish all;
  - outlaws that down and never flee, and wolves that don't down;
  - a guard carrying a man home (no bleeding while carried);
  - a burial making a named raisable grave, and a hidden body never found;
  - the rope going slack;
  - the HUD buttons and prisoner line appearing only when they apply.
- **`verify_village` 56 → 57.** The Hunting kill now goes down first; the Necromancer finishes
  him, which is the kill the block always measured.
- **`verify_guild`** turns off body-finding. Its threat numbers are the witnesses' alone.
- **`verify_stats` 505 → 532.** 20 race rows, the Ghoul's profile, walk speed and two effective
  skills.
- **`verify_demo_shell` 44 → 46.** The two new key actions.
- Everything else is unchanged and green, and `measure_travel` is in band.

## Open questions for the playtest

- Is 45 s of bleed-out enough to walk over and decide, and short enough to be a fight?
- Do guards rescue so eagerly that binding a villager near the village is hard? (14-cell reach.)
- Prisoners eat from the treasury, which starts at 5 food. Is that the right cost?
- Outlaws now fight to the last. Is the cave still a fair band-4 fight?
