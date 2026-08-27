# Warlords

*Working title: Undead Empire Prototype.*

A villain-power-fantasy roguelite settlement builder. Think Against the Storm or RimWorld with the
morality inverted: you are the Necromancer, hiding in a lair because you are weak, and the game is
about the arc from **Hide → Explore → Influence → Rule**. One region is one run. Permadeath. What
persists between runs is variety, never power.

Built in **Godot 4.7.1**, GDScript, GL Compatibility renderer. No external dependencies.

## Where the project stands

The **roguelite rework** (`docs/design/ROGUELITE_REWORK.md`) is the plan of record. It is built in
stages, each playable before the next begins:

| Stage | Status |
|---|---|
| Stage 1–3 settlement loop — grid, priority-list economy, Barracks intake, generated recruits, meals/morale/desertion, fund-a-house, wolf combat, Command Undead | **Built and verified** |
| **R1 — The world exists.** 144×144 fixed world, terrain/blocking/roads, fog of war, directly-controlled killable Necromancer with camera follow, static village, sealed rival ground, travel times in band | **Built and verified** |
| **R2 — The world is worth exploring.** Loot sites and wolf dens, carry capacity and deposit-at-lair, the escort, Raven pings, the Necromancer's Arcane combat kit, generated world with forests | **Fully specced, nothing implemented** |
| R3 — reputation axes and reputation-gated recruitment | Designed at outline level |
| R4 — run lifecycle: death, flee, take-the-manor victory, map shuffle | Designed at outline level |
| R5 — meta-progression: XP, unlocks, the Lair hub, chronicle | Designed at outline level |

Win/lose is still the old placeholder until R4. Climate and additional villain classes are
deliberately deferred. `docs/CURRENT_STATE.md` is the dated snapshot that reconciles every design
document into one picture; read it before anything else in `docs/`.

### The build order for R2

`docs/prompts/R2_PROMPTS.md` is the only live prompt set. Nothing in it runs before a human has
playtested R1 for feel:

```
playtest R1 → P0 (travel harness + doc fixes) → F1 (damage numbers) → C2 (stat rework)
            → P1 (tilesheets) → P2 (generated world + forests)
            → R2a (sites + dens) → R2b (villain combat) → R2c (deposit)
            → R2d (escort) → R2e (raven)
```

## Running it

1. Install [Godot 4.7](https://godotengine.org/download) (the standard build, not Godot 3 and not
   .NET).
2. **Import** `project.godot` from this folder.
3. Press **F5**. `Main.tscn` is the main scene.

Controls: **WASD** moves the Necromancer, **arrow keys** pan the camera, **F** toggles camera
follow. Building placement, demolish, rally and inspect are mouse-driven from the HUD. A debug
time-scale control (1×/10×/60×) is available for watching the economy run.

Headless checks worth knowing about (see `CLAUDE.md` for the full list):

```
godot --headless --path . --import                   # required after adding any class_name
godot --headless --path . --quit-after 200            # clean-boot check
godot --headless --path . res://tools/check_sprite_scales.tscn
godot --headless --path . res://tools/measure_travel.tscn
```

## Layout

```
scripts/        Main.gd (wiring root), ui/, autoload/, settlement/, villain/, combat/, world/,
                plus bounty/events/missions/threat (Stage-4 systems, built but mostly unsurfaced)
data/           all game content as JSON — races, buildings, events, missions, recruitment,
                world_map, world_sites. New content is a JSON edit.
assets/         official/ (commissioned art), placeholder/ (stand-ins), vendor/ (cold storage)
tools/          generators and verification harnesses; they re-derive every tuned number
docs/           design/ (specs), art/ (sprite rules), prompts/ (build order), history/ (dated
                dev narrative), archive/ (completed or superseded — nothing there is live)
```

## Which document wins

Stated once, in `docs/README.md`, and repeated here because it matters:
**`ROGUELITE_REWORK.md` wins on design intent; the newest `docs/history/` file wins on what the
code actually does; `CLAUDE.md` wins on code conventions.** The nine-attribute stat model in
`COMBAT_SPEC.md` §2 is adopted, with `stat_rework_roster.xlsx` as the authoritative statline
source until prompt C2 exports it to `data/races.json` — the code still reads the old Might until
then.

## Design pillars (short form)

- **Indirect control.** No unit orders. The two exceptions are the Necromancer himself and
  Command Undead, which binds the dead as a class.
- **Nothing is yours until it is home.** Worker loads bank on deposit, sortie loot banks at the
  lair, a run's haul banks only if you leave the region alive.
- **Power attracts power.** Followers come because of deeds the world has heard about, never on
  a timer.
- **No meta-progression grants in-run numbers.** A level-20 Necromancer's skeleton hits exactly
  as hard as a level-1's; the veteran has more options, not bigger stats.
- **Bright and stylized, not grimdark.** See `docs/art/SPRITE_SPEC.md`.

## Working on it with Claude

`CLAUDE.md` is the orientation file (hard budget ~8 KB) and lists the load-bearing conventions:
sim state on RefCounted data objects with tokens as pure views, all cross-system communication
through `EventBus` signals, delta-accumulator timers so `Engine.time_scale` scales everything, and
the sprite sizing rules. Session write-ups go in `docs/history/`, never in `CLAUDE.md`.

Repo: https://github.com/OverSeerFulgrim/Warlords
