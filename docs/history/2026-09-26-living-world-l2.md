# The Guild, witnesses and the roadside opening (LIVING_WORLD L2, 2026-09-26)

`LIVING_WORLD_SPEC.md` §14's L2, built except for what needs L3 (prisoners, so Summon Ghoul's
sacrifice) and the parts the spec leaves to later (the guild's own adventurers, Known's bounty on
his head). The first run now reads the way §3 describes: wake on the road, walk to the guild, take
the den, raise your first dead from a roadside grave on the way, clear the den, come home knowing
the Altar.

## The opening (§3)

- **He wakes on the road**, not at the Throne: `Main.ROADSIDE_SPAWN_CELL` (37, 60), the worn track
  at the east edge of the lair band, still under the lair's protection. The camera frames him.
  Second Wake still wakes him at the Throne.
- **First-run popup:** *"Follow this road to the Adventurers' Guild."* with a Go button, shown when
  the title's Begin is pressed and this class has never finished a run. Never again.
- **The roadside grave:** `fresh_grave_scree` moved from (33, 70) to (84, 78), beside the trade
  road past the guild *(moved again after the first playtest — see below)*. Not signposted, so the generated map is
  unchanged (the loot-site count stays 15). `fresh_grave_hollow` stays north-west of the Throne.
- The opening log line now says where he is and where the dead are.

## The Guild (§4)

- **`data/guild.json`** and **`scripts/world/guild/Guild.gd`**: a neutral hall, first at (89, 61) on
  the cobble road *(moved after the first playtest — see below)*, `guild_hall.png` (generated placeholder). Reach 2.5 cells.
- **The board is generated from world state** (§4.2), refreshed every second: every standing den
  posts "Clear the den" (6 gold × band) with its direction from the door, because both dens are
  called "A Wolf Den"; a village short of wood (< 10) or food (< 12) posts a delivery of 10 for 8
  gold, and takes it down when the stores recover. At most two jobs in hand.
- **Take / Hand over / Collect** in the inspector (`InspectorActions.guild_actions`). A delivery
  moves the goods from his stores to the village's. **Pay goes into his hands** through
  `SortieSystem.take_into_party` and is his when banked at the Throne; what will not fit stays
  **owed** at the counter. First payment records the deed `guild_bounty` (Wealth, 10 XP × band).
- **Standing** (§4.1) is on the villain: Unknown pays in full; **Suspected** still pays, at half,
  with "strange sightings" on the board; **Known** shuts the doors.

## Seen, and told (§8.1, ruling 15)

- **`scripts/world/guild/Witnesses.gd`**, per villain. Raising the dead (`skeleton_raised`) and
  striking the living (`villager_attacked`, by him or his escort) are witnessed by every
  non-guard villager within the **attention range** — 8 cells by day, 4 by night
  (`guild.json`). Each gets a red **!** and becomes a **runner** to the nearer of the Guardhouse
  and the guild.
- **Standing drops only when a runner arrives** (`Village.on_runner_arrived` → `Witnesses.arrive`),
  with +5 threat. Kill him on the way and nobody hears. Three witnesses to one deed are one report.
- **The keeper** sees anything within range of the guild's door and is already where the report
  goes: raise the dead on the doorstep and the drop is instant.
- Logs and alerts: seen, arrived, standing changed, doors shut.

## Blueprints (§9.1)

- `BuildingCatalog.blueprint_provider` (set by Main from the profile) gates any building with
  `"blueprint": true`. **The Dark Altar** is now blueprint-gated rather than locked, has lost its
  legacy passive essence tick, and is learned for good by **clearing a den**
  (`RunLifecycle._on_deed`). The build menu repopulates with a log line and an alert.
- The Altar's panel shows **Summon Ghoul**, greyed with its reason: level 2 first, then "needs a
  living prisoner" (L3).

## Verification

`tools/verify_guild.tscn` — **62** at first (68 after the playtest fixes below): the spawn cell is road, inside the lair band on its east edge,
and he stands there; the roadside grave is past the guild; the hall is on open ground beside the
road and inspectable once seen; one bounty per standing den, readable apart; deliveries posted
once and taken down; out-of-reach refusals; delivery moves goods between treasuries; pay into
hands, owed when full, collected later; the two-job limit; clearing the den teaches the Altar and
the build menu offers it; a runner killed before the gate changes nothing; a runner who arrives
drops standing once, adds threat and goes home; a second telling and another villain's report
change nothing; day attention beats night; Suspected pays half; the keeper's instant report to
Known, the shut doors and the refused job; the board, Altar and popup panels. The whole suite
stayed green; `measure_travel` in band; headless boot clean.

## After the first playtest (same evening)

The designer's first run went the wrong way: the lair's track forks four ways within a dozen
cells of where he wakes, and "follow this road" did not say which. Ruled: **the guild must be in
sight when he wakes, and marked on the minimap.**

- **The guild moved** from (89, 61) on the cobble road to **(43, 58)**, at the first fork east of
  the lair's edge, beside the track north — 6.3 cells from the spawn, inside his fog sight and on
  screen. Its 7×7 cells of ground are revealed from the first frame (`reveal_cells`: a public
  hall, known to everyone).
- **The keeper's sight is his own**, shorter than a villager's (`keeper_attention_cells` 5 by day,
  3 by night), so the derelict graveyard ~6.7 cells down the south track is out of his view.
- **The minimap marks it**: an orange house drawn above the fog; the legend reads
  "○ lair ⌂ guild ● you".
- **The popup says which way** ("…The hall is just ahead, to the east.", from `Guild.compass`) and
  sits above the command bar, where it does not cover the hall.
- **The roadside grave followed**: `fresh_grave_scree` moved again, to **(51, 66)** beside the
  track south past the guild (toward the standing stones and the valley den). Still not
  signposted; the map is unchanged.
- `verify_guild` **68** (+6: in sight, on screen, ground known, on the minimap, the keeper clear of
  the graveyard, the popup's direction). The whole suite stayed green.

## Not built yet

The guild's own adventurers and caravans; Known's bounty on him; "strange sightings" as board
entries; prisoners (L3) and so Summon Ghoul; hamlets. The guardhouse hears reports but the village
does nothing more with them yet.
