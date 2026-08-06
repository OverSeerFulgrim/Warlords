## File map

```
project.godot              Godot project config, autoloads registered here
scenes/Main.tscn            Root scene (minimal — logic lives in Main.gd)
scripts/Main.gd              Wires all systems together + debug UI + build menu
scripts/autoload/           GameState.gd, EventBus.gd, BuildingCatalog.gd, RaceCatalog.gd (singletons)
scripts/settlement/         SettlementGrid.gd, Building.gd, FollowerToken.gd, WorkerSystem.gd, WorkerToken.gd,
                            MoraleSystem.gd -- meals, morale, theft, desertion
                            NecromancerToken.gd -- PURE VIEW over scripts/villain/Necromancer.gd; NOT a Laborer
                            HousePlanner.gd -- WHERE a recruit builds (race housing_style)
                            HouseStyle.gd   -- WHAT it looks like (sprite + tint per race)
                            Laborer.gd -- base class: the trip loop + labor stats
                            Worker.gd  -- extends Laborer (so does Follower, in scripts/bounty/)
							  ResourceNode.gd, ResourceField.gd
scripts/ui/                 InspectionPanel.gd -- the one click-to-inspect panel; defines the
                            get_inspect_data() contract every clickable implements
                            Minimap.gd -- the region at 1px/cell; terrain image + the world's own fog
                            texture. Shows no live contents, on purpose
scripts/combat/             Combat.gd -- THE damage formula; reusable, knows nothing (bounties/raids call this)
                            Engagement.gd -- one fight's clock and participants
                            CombatSystem.gd -- policy: wolf spawning, targeting, emergent defence,
                            the four consequence rules, skeleton repair at the Throne
                            UndeadCommand.gd -- the Command Undead spell; binds the dead to a rally point
                            RallyPoint.gd -- the marker and its Defend/Patrol/Attack order
scripts/villain/            Necromancer.gd -- THE villain as data: position, hp, Might, carry, escort.
                            Per-villain state lives here and NOWHERE else (rework section 11 -- no
                            autoload may hold it, no code may assume exactly one villain)
                            VillainController.gd -- WASD hold-to-move + camera follow; takes the
                            villain and the camera as fields, looks nothing up
scripts/world/              DayNightCycle.gd (phase clock, CanvasModulate tint, debug time scale)
                            WorldMap.gd -- the 144x144 region: ONE TileMapLayer, walkability,
                            road speeds, and the settlement-space <-> world-cell conversions
                            FogOfWar.gd -- unexplored/remembered/visible, ONE node + a 144x144 image
                            WorldSite.gd  -- a static thing standing in the world; NOT a Building
                            WorldSites.gd -- loads data/world_sites.json, owns sites + patrols, answers clicks
                            Patrol.gd -- a human loop walker built on Roaming; scenery, it does not react
                            TravelLog.gd -- times journeys against WORLD_MAP_PLAN section 3
                            Wolf.gd -- the first hostile creature
                            Roaming.gd -- wander helpers shared by the deer and the wolf
tools/                      make_deer_sprite.gd, make_wolf_sprite.gd -- one-off art generators, not runtime code
                            make_world_map.gd -- generates data/world_map.json; edit it, re-run, commit the JSON
                            measure_travel.gd/.tscn -- REPEATABLE: routed travel times vs WORLD_MAP_PLAN section 3.
                            Re-run after touching walk speed, the road bonus, or the layout
scripts/bounty/              BountyBoard.gd, Bounty.gd, Follower.gd
scripts/threat/               ThreatSystem.gd
scripts/events/                EventSystem.gd, RecruitGenerator.gd
scripts/missions/            MissionSystem.gd
scripts/Anchoring.gd      Where a sprite sits relative to its position (feet on the ground; buildings
                          on their cell's base) + the shared click-radius fraction. Six callers
scripts/GameCamera.gd     Pan (right-drag or ARROW keys -- not WASD, that's the villain)/zoom Camera2D
addons/godot_mcp/           Third-party MCP bridge plugin (mkdevkit, MIT) — Godot-editor side
data/events.json               15 MVP random events
data/missions.json            4 MVP party missions
data/followers.json           SUPERSEDED recruit templates -- only the off-timer events.json entries still use these
data/races.json               Race roster from RACES.md: stats, labor skills, alignment, rarity, housing style, rivalries (loaded by RaceCatalog)
data/buildings.json           Building catalog: costs, prerequisites, "locked" and "unique" flags, Barracks capacity
data/recruitment.json         Recruit tuning: rarity-by-power table, stat-roll dice, exceptional chance, first-run categories
data/world_map.json           GENERATED 144x144 terrain: legend (char -> tile/category/speed), danger bands, 144 row strings
data/world_sites.json         Static world content in WORLD cells: village, sealed ritual ground, landmarks, patrol routes
Official Sprites/            COMMISSIONED art -- buildings, nodes, all 16 race tokens, necromancer, icons
Official Sprites/_originals/ Full-res backups; .gdignore keeps Godot out. Leave alone.
art/, Buildings/, Characters/    Remaining placeholder sprites (see "Art provenance")
art/creature_deer.png       Generated, not from a pack -- see tools/make_deer_sprite.gd
```

## Next milestones (not yet built)

> **The roadmap is now `ROGUELITE_REWORK.md` §13 (stages R1–R6)** — see "Current phase". The list below predates it and survives as a backlog of settlement-layer items; where the two disagree, the rework doc wins. Specifically superseded by it: "Combat beyond the primitive"'s Stage-4/5 bounty-raid framing (bounties return in the run frame, R2+ escort/encounters first), "Save/load" (now required, scoped in R5 as meta-persistence first), and "Remaining villain classes" (the Demonologist is the second *playable* class, rework §11).

- Real UI (replace the code-built debug UI with a proper `.tscn`-based interface once validated in-editor)
- Multi-cell building footprints (everything is 1x1 on the grid for now)
- Housing capacity limits (currently a pure hard gate — species is unlocked or not, no cap on how many of that species you can have once housing exists)
- Physical gathering *buildings* / per-node worker capacity (workers now walk to real map nodes, but there's still no Lumber Camp/Quarry building layer and no hard cap on how many workers can share one node — `claims` is only a soft spreading hint)
- ~~Manual per-worker override on top of the priority list~~ — **answered differently**: see "Command Undead". The player's lever over unit movement is a spell that binds the dead as a class, not per-unit orders, which keeps the indirect-control pillar intact. Per-worker overrides for *living* recruits remain out.
- Replanting trees (FOUNDATION_SPEC §5: if wood scarcity bites, the planned fix is a manual replant-seeds action, explicitly *not* automatic regrowth)
- Dawn/dusk **meal ticks** — the last unbuilt piece of FOUNDATION_SPEC §7. The clock, the phases and both signals are in place (see "Day/night, finished"); what's missing is the food/morale system they'd drive, which needs living recruits to exist first (outline gap #3)
- Real deer / wolf / carcass / stone-deposit art — the last unreplaced map placeholders after the commissioned art pass
- Combat beyond the primitive: guard posts, ordered defence, more creature types, and the Stage-4 bounty/Stage-5 raid resolution that `Combat.exchange()` was built to serve
- Per-race house art (recruit houses still reuse the tinted Kenney House pack)
- Wiring the Orc_Armed / Goblin_Armed / Gray_Dwarf_Miner variants, once combat and work states exist to select them
- Climate system (deliberately deferred — see "Current phase" above)
- Save/load
- Remaining villain classes and climates (Phase 2, per design doc)
- Unique undead-themed building art per housing type (currently reusing the Kenney fantasy House/Tower/Castle packs with color-variant reuse as a placeholder — see `data/buildings.json` `sprite_path` fields)
- measure_travel (fixed 2026-08-05): lair -> nearby resource is 3s vs the 10-20s design target — retune resource placement or speeds before R2.
