### Combat: the minimal primitive, and the wolf (Core Feel Prompt C)

The first thing on the map that can hurt you, and — more importantly — **the one damage formula that Stage-4 bounties and Stage-5 raids are meant to call.** Building wolf-specific combat inline was the explicit failure mode to avoid, so the code is layered by how reusable each piece is:

| File | Knows about | Reusable by |
|---|---|---|
| `scripts/combat/Combat.gd` | nothing — two Combatants and some arithmetic | anything |
| `scripts/combat/Engagement.gd` | a fight's clock and its participant list | anything |
| `scripts/world/Wolf.gd` | how to prowl, look, and bleed | — |
| `scripts/combat/CombatSystem.gd` | **policy**: targeting, defence, consequences | replace per encounter type |

Only the last one would need rewriting for a bounty. A bounty that wants an instant abstract result calls `Combat.exchange()` in a loop and never constructs anything.

#### The formulas

```
max_hp  = 8 + Might * 2          Human Peasant 18, Skeleton Worker 16, Ogre recruit 26
damage  = attacker Might + d3 - floor(defender Might / 2)      minimum 1
exchange interval = 1.5s, both sides swing, both swings land
```

**Might is the only stat combat reads.** No dodging, no crits, no ranged, no initiative, no armour — every one of those would need balancing before the settlement loop it serves has been proven.

Three details that are load-bearing rather than incidental:

- **`max_hp()` is computed, never stored.** Might already decides durability everywhere else (it's carry capacity too), and a stored copy goes stale the moment anything changes Might — which the Blacksmith's `+1 Might` already does. `hp` is stored and initialised by `heal_full()` in each subclass's `_init`, plus once more in `RecruitGenerator` after the exceptional-stat bump.
- **The minimum of 1 is not cosmetic.** Without it a Gnome (Might 2) swinging at an Ogre (Might 9) deals `2 + d3 - 4` = nothing, ever, and a mismatched fight hangs instead of resolving.
- **Both swings land even when one is lethal.** A dying skeleton still gets its last hit in, which is what lets a doomed defender contribute to driving the wolf off — the difference between a loss and a total loss.

#### The Combatant contract

Duck-typed, same shape as `get_inspect_data()`: `combat_name()`, `combat_might()`, `max_hp()`, `hp` (property), `take_damage()`, `is_alive()`, `hp_fraction()`. `Laborer` implements it for every worker and recruit; `Wolf` implements it for the creature. `Combat.is_combatant()` is a cheap guard so a half-implemented new unit fails loudly instead of silently dealing zero forever.

#### The four consequence rules

These are the design decision, implemented exactly:

1. **Skeleton Workers can be destroyed.** No bones refunded, no corpse. Replaceable for the usual 5 Bones — losses sting, necromancers shrug.
   - **The wolf, conversely, leaves a body.** Killed outright (hp 0) it drops an ordinary carcass node worth `WOLF_CARCASS_BONES` (9) where it fell — better than a seeded carcass (5), because map bones are finite and a predator that pays out more than it costs is a welcome pressure valve. Merely *driven off* (below 5 hp) leaves nothing: routing it away is the cheap win, killing it is the paying one. The carcass is a plain `ResourceNode`, so the priority list, crowding rules and inspection panel all pick it up with no special casing.
2. **Living recruits are never killed by wildlife.** Below 30% hp they break off, run home, and are `Injured` (no work) until healed to full, at −1 morale. This is true *by construction*, not by a check at 0 hp: `_injure_and_flee` pulls them out at the threshold, and the 0-hp path warns and injures rather than killing if anything ever reaches it.
3. **A deer taken by a wolf is a pure economic loss.** The food is gone, the wolf is fed and stands down for the night. **This is the common case, and the point** — a wolf that never touches a person has still cost you 8 food and a hunting trip.
4. **Wolves won't approach the Necromancer**, and anything standing in his shadow is invisible to them. The protection is *positional*, so a worker who wanders off to gather is fair game again. **Since the villain split he is no longer "untouchable" in the general sense** — he implements the full Combatant contract and `Combat.exchange()` damages him like anything else. This is a *lair* rule, and it now sits behind `CombatSystem.LAIR_AURA_PROTECTS_VILLAIN` so R2 can switch it off in the world (rework §15 lists it as an open tunable). Flipping it off is necessary but not sufficient to make wildlife hunt him: he isn't in `_prey_candidates()` and there's no consequence branch for a villain losing a fight, because that branch is "the run ends", which is R4.

Note rule 3 and the "nearest prey, no preference" targeting work together: your hunters walk out to the same deer the wolf wants, so the two end up in the same place often enough without a preference rule aiming them at each other.

#### Emergent defence

**Nobody is ordered to fight.** When a fight starts, every recruit within 3 cells either joins or runs: Warrior-category or Might ≥ 6 wades in, everyone else drops their load and flees to their idle anchor. The player's only lever is who they recruited and where those people happen to be — the Majesty indirect-control pillar applied to defence, previewed before guard posts or bounties exist.

Skeleton Workers neither rally nor scatter. They have no self-preservation to override and no orders to act on, so they carry on until something bites them.

#### Regen, split across two systems on purpose

- **Living units: +2 hp per meal actually eaten** (`MoraleSystem._regenerate`). Healing lives in the meal loop because it's a consequence of eating — which ties injury to the food economy rather than to a separate timer. A recruit who goes hungry doesn't heal, so a wolf that mauls your orc during a famine has done compounding damage. Reaching full hp is also the only thing that clears `is_injured`.
- **Skeletons: 1 hp per 6s, only while idle at the Throne** (`CombatSystem._tick_throne_repair`). Necromantic maintenance. The undead perk cuts both ways — free to run, but mendable only at home. Slow on purpose: a mauled skeleton being out of the workforce for a while is most of what makes losing cost anything, when the unit itself is 5 bones.

#### `TripStage.FLEEING` and two new Laborer predicates

The trip loop gained a fifth stage. Fleeing runs at full walk speed rather than the idle shuffle — it's the one time a unit isn't ambling — and becomes `IDLE` on arrival.

Two similar-sounding checks that are deliberately different:

- **`can_labor()`** (existing) — "is this unit in the labor pool at all". False while a follower is away on a bounty.
- **`can_work_now()`** (new) — "will they take a *new* job". False while injured. An injured recruit stays in the pool, so they still walk home, still idle by their house, and still appear in the workforce summary. Removing them from the pool instead would freeze them mid-map wherever the wolf left them.

`in_combat` is a third, cruder flag: `WorkerSystem._advance_laborer` skips anyone carrying it, so a unit trading blows isn't also strolling off to a tree.

#### Tuning knobs

Wolf: Might 5, 18 hp, flees below 5 hp, hunt radius 5 cells, **the first dusk of a run always brings one, then 55% per dusk after that.** Max 1 alive; any wolf still around at dawn slinks off, which keeps that cap honest without a despawn timer.

Two of those numbers were corrected after the first playtest, and the failure is worth recording because it wasn't a crash — the system worked perfectly and the player still never saw it:

- **The introduction was left to a coin flip.** A session tends to end on the first night, so the feature got exactly one 55% roll to exist. Two playtests in a row came up empty. A mechanic gets to introduce itself deterministically; it can be a gamble afterwards.
- **A fed wolf used to depart on the spot, and it spawns beside the deer.** The treeline entry point is inside the deer roam area, so it killed and left within seconds of arriving — off the map before it was ever on screen, twice out of two spawns. Fixed twice over: `HUNT_DELAY_SECONDS` (25s) makes it prowl visibly before it can take anything, and a fed wolf now stays until dawn, which is also what "stops hunting for the rest of the day" actually asked for.
- **And it still wasn't visible after that.** Playtest reported "the wolf spawned but I didn't see it" *with the alert firing and a fight starting*. Two causes: it entered 5.5 cells past the grid edge, which at the default 0.72 zoom is the very rim of the viewport, and a 34px token renders there as ~24 screen pixels of dark grey on dark ground. Entry moved to 2 cells out, `TOKEN_SIZE` raised to 46 (larger than any other unit), `z_index` 6 so nothing occludes it, and the hp label given a black outline. The thing that eats your labourers should be the most legible object on the map.

Measured after the fix: 4 wolves over 6 dusks, first one guaranteed, each visible for a whole night.

**The deer is still the usual victim** — they roam the same ground the wolf enters on, so "nearest prey" nearly always resolves to one. That is rule 3 working, not a targeting bug: the wolf is meant to be an economic threat first. It reaches people when your labourers are out in the forest at night.

Wolf vs a lone Skeleton Worker is close by design — ~5 damage a swing against ~4 back, so the wolf needs 3.2 exchanges and the skeleton 3.5. Measured over 7 scripted fights the skeleton lost 7/7, but the margin is thin enough that it won't always. An Orc (Might 7, 22 hp) beats it comfortably.

#### Verification

A headless harness at both 10× and 60×, all passing: the formula in isolation (range 4–6 for wolf-vs-skeleton, min-damage floor, both sides damaged, contract guard); the hp table (16/18/26); dusk spawn; deer kill → fed → stands down → leaves; 7/7 lone skeletons destroyed with no bones refunded; orc engages and drives the wolf off while never dying; +2/meal recovery clearing `Injured`; a Warrior auto-joining while a Might-2 Gnome flees untouched; the Necromancer's shielding; and Throne repair (9 hp vs 3 hp for a skeleton parked elsewhere).

Two harness traps worth remembering, both of which produced convincing false failures:

- **`get_process_delta_time()` is already scaled by `Engine.time_scale`.** Multiplying by it again advances your accounting 60× too fast, so a "wait 6 seconds" loop returns after 0.1s and everything looks broken until the events arrive later in the log.
- **`NecromancerToken` owns its own position and walks back to `home`.** Assigning `.position` to move him for a test doesn't stick — use `setup()`.

