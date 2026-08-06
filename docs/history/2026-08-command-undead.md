### Command Undead — the Necromancer's first spell

Playtest feedback after the combat pass was "I can't direct skeletons anywhere; there's no option to command them." That was true and deliberate (GAME_OUTLINE pillar 2), but it left a threat on the map with no lever to answer it. **The resolution the user chose is better than adding unit orders: a spell.**

**Why this doesn't break the indirect-control pillar.** You still don't order units around. You cast a spell that binds *the dead, as a class*, to a point. The distinction is real rather than a fig leaf: a skeleton has no will to override, which is the entire difference between it and a recruit. Living followers remain uncommandable and always will be.

- **`UndeadCommand`** (system) + **`RallyPoint`** (Node2D marker, inspectable). Cast from the Necromancer's panel — the old "Spells — coming soon" placeholder is now a real button — which arms a third click-to-target mode alongside build placement and demolish. Click the map to plant it.
- **Three orders, differing only in leash length**, which is the only axis that matters at this scale: **Defend** (1.2 cells), **Patrol** (3 cells, walks a beat), **Attack** (7 cells, seeks the nearest hostile). Clicking the rally point opens it in the inspection panel with the order buttons, a Move, and a Dismiss.
- **Hostiles are measured from the rally point, not from the unit.** Measuring from the unit would let a skeleton that chased something to the edge of its leash re-measure from there and keep going forever.
- **The cost is the economy.** Bound undead leave the labor pool — `can_labor()` returns `not rallied`, so the priority list stops seeing them. *The dead can dig or they can fight, not both.* With one starting skeleton that's a total shutdown; with six it becomes a real allocation question, which is when it gets interesting.
- **No resource cost yet.** Dark Essence is the obvious candidate and is locked at 0 for the whole foundation build, so charging now would mean the spell could never be cast. Revisit at Stage 4.
- **It commands *all* undead, not a chosen subset** — on purpose. Picking which skeletons to send is a selection UI, and a selection UI is exactly the per-unit control the pillar rules out.
- **A standing order binds skeletons raised later.** Raise a new one while the point is up and it falls in automatically; the spell is an order on the dead, not on the individuals who happened to be present.

**`Laborer.is_undead()` reads `alignment: "Undead"` from races.json**, not the class. So the ghouls and wraiths on the roadmap are commandable the day they exist, and no living race ever can be — which is what the user meant by "later this will be useful when he unlocks more powerful undead."

Two related fixes fell out:

- **`WorkerSystem.laborers()` now filters Workers by `can_labor()`** instead of appending them wholesale. "Every Worker is always available" stopped being true the moment a spell could take them off the roster. `all_units()` is the new unfiltered view, which combat targeting needs — a skeleton standing guard is out of the workforce but very much still something a wolf can bite.
- **Skeletons no longer flee from fights.** `_rally_and_scatter` was calling `begin_flee()` on them, contradicting this file's own claim that they "neither rally nor scatter". Code now matches the documented intent: they have no self-preservation to override.

Verified headless at 60×: alignment-based targeting, all 3 skeletons bound and the orc untouched, skeletons out of `laborers()` but still in `all_units()`, the march to the point, patrol staying inside its ring (164px of 192px) while defend holds tight, Attack sending them out to engage a wolf beyond the patrol ring, converging skeletons sharing *one* Engagement rather than three duels, dismiss returning everyone to the priority list, a later-raised skeleton joining the standing order, and a regression check that an uncommanded skeleton still gets attacked normally and still doesn't run.

