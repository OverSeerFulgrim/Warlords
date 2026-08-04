# Claude Code Prompts — Core Feel Pass (run BEFORE the Stage-4 set)

Three prompts that flesh out the core before Stage 4 builds on it: camera/avatar presence, a universal inspection system, and the first combat primitive (the wild wolf). Same rules as always: read CLAUDE.md first, keep the game runnable, smoke test, update CLAUDE.md, **commit when done**. If the game launches blank, check `scenes/Main.tscn` for its `script =` line before debugging.

---

## Prompt A — The Throne is the center, and the Necromancer walks his domain

```
Read CLAUDE.md first.

1. Camera start: on game start the camera must be centered on the Throne
   of Bones — the throne in the middle of the screen, not off in a
   corner. Account for the bottom UI panel: center it in the *visible*
   map area above the panel, not the raw window.

2. The Necromancer becomes an on-map character. He is the player avatar:
   a token near the Throne (reuse the existing necromancer portrait art
   scaled to token size for now — flag it as a placeholder for the
   ART_BRIEF's Necromancer sprite). Give him a slow idle wander within
   ~2 cells of the Throne so he reads as alive, pacing his domain. He is
   NOT a Laborer — he never gathers, never shows up in worker counts.
   Structure: own small script (e.g. scripts/settlement/NecromancerToken.gd)
   with position owned by a plain object if any system will ever need it,
   or by the token if purely cosmetic for now — document the choice.

3. Clicking him opens his info panel (uses the inspection system from
   Prompt B if that's built; otherwise a simple panel): name, title
   ("The Necromancer — Master of the Settlement"), and a flavor line.
   Later he gets spells and stats; leave a "Spells — coming soon" locked
   line as the visible promise.

Smoke test: launch, verify throne centered at multiple window sizes,
necromancer token wanders near throne and never enters the labor pool.
Update CLAUDE.md. Commit.
```

## Prompt B — Click anything, learn everything (universal inspection)

```
Read CLAUDE.md first. The game has scattered click behaviors (Keep menu,
Barracks panel). This pass makes EVERYTHING inspectable through one
consistent system, without breaking those existing panels.

1. One InspectionPanel (single reusable UI panel, one instance): shows
   name, portrait/sprite, a description line, and a details section that
   each inspectable thing fills in its own way. Opens on left-click of
   any inspectable object, closes on Esc / clicking elsewhere / clicking
   another object (which switches to it). Must not conflict with build-
   placement mode (placement clicks keep priority, same pattern as the
   existing Keep-menu guard).

2. Make inspectable, with these details:
   - Resource nodes: type, remaining/capacity ("Pine Tree — 7/10 wood
     left"), regrowth note if any ("Berry Grove — regrows at dawn"),
     which skill gathers it. Depleted nodes say so ("a stump").
   - Trees/graves/carcasses/deposit/grove/deer all included. Deer also
     shows "8 food when hunted".
   - Houses: owner name and race ("Durin's Stone Hut — Gray Dwarf"),
     housing style flavor line.
   - Buildings: existing panels (Keep, Barracks) keep their menus but
     gain the same header treatment; other buildings (Bone Pile,
     Workshop, Blacksmith, houses) get name + what they do + per-tick
     output if any.
   - Characters (workers, recruits, the Necromancer): name, race,
     category, stats (the 4 + 3 labor skills), morale for living
     recruits, current activity ("Hauling 4 wood home"), housed-at.
     Add HP display here ONLY if Prompt C has landed; otherwise leave a
     placeholder row.
   - The Throne: hp, power contribution, flavor.

3. Implementation guidance: an "Inspectable" pattern — either a shared
   component/interface each clickable implements (get_inspect_data() ->
   Dictionary) or a registry the panel queries. Pick whichever fits the
   codebase; keep per-object data IN the object's script, not in one
   giant match statement in Main.gd.

4. Click pick order when overlapping: characters > nodes > buildings >
   ground. A worker standing on a tree should inspect as the worker.

Smoke test: headless can't click — verify get_inspect_data() returns
sane dictionaries for every type via harness, then LIST the manual
checks for me to do with real mouse (tree shows remaining wood, house
shows owner, recruit shows stats+activity, esc closes, placement mode
unaffected). Update CLAUDE.md. Commit.
```

## Prompt C — The wolf, and the first combat primitive

```
Read CLAUDE.md, FOUNDATION_SPEC.md (stats), and RACES.md before starting.
This builds the MINIMAL combat system that bounties and raids will later
reuse. Keep it small and data-visible; resist scope creep.

1. HP on all units (Laborer base + the wolf): max_hp = 8 + Might * 2
   (Human Peasant 18, Skeleton Worker 16, Ogre recruit ~26). Regen for
   living units: +2 per meal eaten. Skeletons repair only at the Throne:
   idle skeletons below max slowly restore there (necromantic
   maintenance). Show HP in the inspection panel.

2. The Wolf (new creature, reuse/extend the deer's roaming machinery):
   spawns from the map edge near the forest at dusk (max 1 alive for
   now), prowls, and attacks the nearest living recruit, worker, or
   deer within its hunt radius. Wolf stats: Might 5, max_hp 18,
   flees when below 5 hp.

3. Combat resolution — one shared function, because bounties and raids
   will reuse it: opposed exchange every 1.5s while engaged:
   damage = attacker Might + d3 - defender Might/2 (min 1). No dodging,
   no crits, no ranged. Both sides swing each exchange. Disengage rules:
   wolf flees at low hp; living recruits flee home at <30% hp.

4. Consequences (the design decision — implement exactly this):
   - Skeleton Workers CAN be destroyed: token removed, log + alert
     ("A wolf tore apart Skeleton Worker #2"). Bones refund: none.
     Replaceable at the usual 5 bones — losses sting, necromancers
     shrug.
   - Living recruits are NEVER killed by wildlife: at <30% hp they
     flee to their house/Barracks, are "Injured" (no work, no training)
     until back to full via meals/regen, and take -1 morale.
   - Deer killed by wolf: deer dies, wolf stops hunting for the rest of
     the day (fed). This makes the wolf an ECONOMY threat even when it
     never touches your people.
   - The Necromancer is untouchable for now (wolves fear him — flavor
     log if one wanders close).
5. Defense is emergent, not ordered: any armed-with-Might recruit
   (Warrior-category, or Might >= 6) within 3 cells of an attack
   auto-joins the fight. This previews the Majesty-style indirect
   defense before guard posts/bounties exist. Everyone else runs.

6. Alerts: wolf spawn ("Wolves prowl the treeline"), each fight start,
   each consequence — History log + alert pin, no modal popups.

Smoke test at 10x/60x: wolf spawns at dusk, kills a deer and stands
down; force-spawn near a lone skeleton -> skeleton destroyed, log
correct; near an orc recruit -> orc fights, wolf flees or orc flees
injured and recovers after meals; warrior nearby auto-assists. Verify
combat function is a standalone reusable unit (bounties will call it).
Update CLAUDE.md with the combat formulas. Commit.
```

---

## Order and notes

- Run A → B → C, then continue with STAGE4_PROMPTS.md (Prompt 6 onward).
- B before C so HP has a place to be displayed; A is independent but tiny.
- The combat formula lives in ONE function on purpose — Stage-4 bounty
  resolution and Stage-5 raids are planned consumers. If Claude Code
  builds wolf-specific combat logic inline, that's the thing to push
  back on.
