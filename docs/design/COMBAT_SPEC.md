# Combat Spec — the stat rework, the damage model, and everything that fights

Companion to `FOUNDATION_SPEC.md` (which owns the settlement loop's numbers) and `GAME_OUTLINE.md` (which owns the arc of a run). This file owns **the stat system, combat resolution, and the systems that read them**. Where this file and `FOUNDATION_SPEC.md` disagree about a stat, this file is newer and wins; where this file and the code disagree, this file is the target.

`RACES.md` and `TRAITS.md` are downstream of this document — both were written against the retired four-stat model and `RACES.md` still needs its table re-authored (see §12).

> **Amendment, 2026-08-06 — C2 adopted into the roguelite build order.** Decided with the designer
> during R2 planning:
>
> 1. **C2 is scheduled**, as prompt **C2** in `docs/prompts/R2_PROMPTS.md`, after the combat-
>    feedback prompt (F1) and **before** the terrain and R2 prompts — everything from R2a on
>    consumes stats, and building those on `combat_might()` would mean migrating every harness
>    twice. The §12 authoring problem is **already solved**: `stat_rework_roster.xlsx` contains
>    all 153 attribute values, the six templates, the overrides, and the export plan.
> 2. **Carry capacity = Endurance is confirmed** (§2.1). The R2 specs (`SORTIE_SPEC.md`,
>    `ESCORT_SPEC.md`, `FOUNDATION_SPEC.md` §6, `LOOT_SITES_SPEC.md`) were reworded 2026-08-06;
>    no shipped number moves (skeleton End 4 and wolf End 5 equal their old Might).
> 3. **The Necromancer's profile is Arcane** — statline and the engage-close/cast-far model live
>    in `NECROMANCER_SPEC.md` §2–§3, which details his side of this spec.
> 4. **Creatures carry all nine attributes** — §7's reduced-set rule is **superseded** (marked
>    inline). Same stat categories everywhere keeps combat fluid: arcane-vs-beast resolves
>    through the beast's own (low) Intelligence instead of a special case. Creature and villain
>    rows are authored in the workbook alongside the races.
> 5. **C3 (morale, judgement, packs) stays post-R2**, targeted alongside R3 — it deletes
>    `FLEE_HP_FRACTION`, which the R2 escort's interpose threshold reads, so it must not land
>    mid-R2. **C4** folds into R5's spell unlocks. **C5** becomes R4's crusade climax.
> 6. **C6 is retracted, not deferred.** Off-map bounty combat assumed the abstracted follower-
>    travel path; commit `3023372` (2026-08-05) deleted that path, and Era-III bounty parties are
>    now visible on-map units (`ROGUELITE_REWORK.md` §16.2). Bounty fights will be ordinary
>    on-map engagements through the same resolver — there is no off-map caller to build.

---

## 1. Scope, and what already exists

The first combat slice is **built and committed** (`a2dcd65`). Working today:

- `scripts/combat/Combat.gd` — the shared damage formula and the duck-typed Combatant contract.
- `scripts/combat/Engagement.gd` — one fight's clock and participant list.
- `scripts/combat/CombatSystem.gd` — policy: wolf spawning, targeting, emergent defence, the consequence rules, Throne repair.
- `scripts/combat/UndeadCommand.gd` + `RallyPoint.gd` — the Command Undead spell.
- `scripts/world/Wolf.gd`, `Roaming.gd` — the first hostile creature.
- HP on every `Laborer`, computed as `8 + Might * 2`.

**This spec does not throw that away.** The layering was correct — `Combat.gd` knows nothing about wolves, and a bounty or a raid can call `Combat.exchange()` without constructing anything. What changes is the *stat vocabulary* those functions read, plus three new rules (profiles, morale routing, judgement) layered on top.

### The slices

| Slice | Content | Status |
|---|---|---|
| **C1** | HP, the shared resolver, the wolf, emergent defence | **done** |
| **C1.5** | Command Undead — rally points, the dead as a commandable class | **done** |
| **C2** | **The stat rework** — §2–§4 of this file | **scheduled** — prompt C2 in `R2_PROMPTS.md`, before R2a |
| **C3** | Morale routing, judgement, guidance, wolf packs — §5–§7 | post-R2, alongside R3 (amendment note 5) |
| **C4** | Necromancer combat spells beyond Command Undead | folds into R5 unlocks (`NECROMANCER_SPEC.md` §7) |
| **C5** | Real raids replacing `ThreatSystem._resolve_crusade()`'s arithmetic | becomes R4's crusade climax |
| **C6** | ~~Off-map bounty combat calling the same resolver~~ | **retracted 2026-08-06** — see amendment note 6 |

Gear (§9), classes (§10) and disease (§11) are specified here but deliberately unscheduled — they're named so nothing gets built in a way that blocks them.

---

## 2. The stat model

Three layers, and the distinction between them is load-bearing:

| Layer | Rolled? | Changes during play? |
|---|---|---|
| **Attributes** | at generation | rarely — training, gear, a trait |
| **Skills** | at generation | yes, slowly, via training |
| **Condition** | no | constantly |

### 2.1 Attributes

Scale 1–10, Human Peasant = 5 in everything. Nine of them:

| Attribute | Group | Direct consumers |
|---|---|---|
| **Strength** | Physical | melee damage; governs Woodcutting, Mining |
| **Dexterity** | Physical | ranged damage; governs Hunting, Fishing, Crafting |
| **Speed** | Physical | walk speed (`1.0` = one grid cell/sec); ranged defence |
| **Endurance** | Physical | `max_hp`; **carry capacity**; melee defence |
| **Intelligence** | Social | arcane damage; arcane defence; governs Research, Surgeon |
| **Guile** | Social | governs Trapper, Mercantile; Stage-4 stealth rolls |
| **Perception** | Social | governs Scouting, Foraging; feeds judgement |
| **Tact** | Social | judgement; governs Leadership |
| **Loyalty** | Social | meal priority; desertion; departure disposition |

Three notes on why the list looks like this:

- **Carry capacity moved from Strength to Endurance.** Otherwise Strength is damage plus carry plus two labor skills, and we have rebuilt Might under a new name. Endurance carrying HP *and* load also opens a high-Endurance/low-Strength porter, which is a real build rather than a strictly-worse one.
- **Leadership is governed by Tact, not Intelligence.** A sergeant who keeps a troll pointed at the enemy is battle-smart, not well-read, and Leadership's only live consumer is the guidance rule in §6. It also rebalances the load — Intelligence was carrying five jobs, Tact one.
- **Influence is retired.** It was vague and barely read (two call sites). Leadership and Mercantile cover what it gestured at, and both are trainable where an attribute isn't.

### 2.2 Skills

Scale 1–10. Twelve, each with exactly **one** governing attribute:

| Governing attribute | Skills |
|---|---|
| Strength | Woodcutting, Mining |
| Dexterity | Hunting, Fishing, Crafting |
| Intelligence | Research, Surgeon |
| Guile | Trapper, Mercantile |
| Perception | Scouting, Foraging |
| Tact | Leadership |

**One governing attribute per skill is a rule, not a default.** Two would double-count and make the numbers unreadable.

Two assignments that were argued and should not be quietly re-litigated:

- **Foraging → Perception, not Intelligence or Dexterity.** Intelligence would hand a foraging bonus to Gnomes (Int 7, Foraging 4) while Gnolls and Goblins — the races whose whole identity is foraging — get nothing. Perception preserves the roster's intent and reads correctly as noticing what's edible.
- **Trapper → Guile, not Intelligence.** A trap is an ambush, not an engineering project. Pairing it with Mercantile gives Guile a coherent "deceive" identity against Perception's "detect", and the two make a natural opposed roll at Stage 4.

### 2.3 The derivation formula

```
effective_skill = skill + floor((governing_attribute − 5) / 2)
```

Range −2 to +2. **Compute at use time, in one helper.** Never store an effective value — a stored copy goes stale the moment gear, training or a trait moves the attribute, which is the same reasoning that keeps `max_hp()` computed rather than stored today.

Known asymmetry: an attribute bonus is lumpier than a skill bonus, because +1 only crosses a boundary on odd steps (Perception 6→7 helps, 5→6 does nothing). Accept it — it means a bonus matters more on a race already strong in that attribute, which reads as playing to type.

**The `/2` divisor is the main balance knob.** At `/2` an Ogre (Str 9, Mining 6) reaches effective 8 against a Gray Dwarf's specialist 9 — close enough that the Ogre's bigger load makes him the better miner, offset by eating 3.0 food to the dwarf's 1.0. That tradeoff is intended. If specialists need more protection, `/3` narrows the swing to ±1 and is a one-constant change.

### 2.4 Condition

Not rolled, not authored per race. Simulated state:

| Value | Range | Owner |
|---|---|---|
| **hp** | 0…`max_hp` | `Laborer` (already implemented) |
| **morale** | 1–10 | `Follower` (already implemented) |
| **hunger** | — | `MoraleSystem`'s meal tick |
| **disease** | — | unbuilt, see §11 |

`max_hp = 8 + Endurance * 2` — the existing formula with Endurance substituted for Might. Human Peasant 18, Ogre ~24.

**Traits may modify attributes and skills, never condition.** A trait that set morale directly would fight the system that owns it; traits change the *rules* around condition instead (`missed_meal_floor`, `rout_morale_offset`).

---

## 3. Attack profiles

An attack has two independent properties: **how far it reaches** and **which attribute drives it**. Casters are not a special case — they're the third row of the same table.

| Profile | Reach | Attacks with | Defended by |
|---|---|---|---|
| **Melee** | 1 cell | Strength | Endurance |
| **Ranged** | 5 cells | Dexterity | Speed |
| **Arcane** | 5 cells | Intelligence | Intelligence |

### 3.1 How a unit gets its profile

In priority order:

1. **Class**, if it has one — a shaman is Arcane regardless of being a Strength-8 orc (§10, unbuilt).
2. **Equipped weapon**, if it has one — a bow makes an archer (§9, unbuilt).
3. **Highest of Strength / Dexterity / Intelligence**, ties to Strength.

Rule 3 is the whole of v1, and it costs no new data: a Goblin (Dex 7) picks up a sling, a Gnome (Int 7) throws scrolls, an Ogre swings. The roster diversifies itself the day the attributes are authored.

### 3.2 Consequences already accounted for

- **Glass cannons self-balance.** Dexterity and Intelligence races have low Endurance, so low HP. An archer gets a couple of free shots while something closes, then dies if it arrives. That makes "does my melee line hold?" the emergent question, which is the indirect-control pillar working as intended.
- **Intelligence both attacks and defends.** A mild version of the overload we just removed from Might, accepted deliberately: it makes a low-Int troll both prone to straying *and* soft to magic, which is one coherent unit identity rather than two unrelated weaknesses.
- **Melee-only creatures become trivial against archers.** This is why wolves hunt in packs and gain Speed (§7).

---

## 4. The damage model

Unchanged in shape from what shipped. One opposed exchange every `EXCHANGE_INTERVAL` (1.5s), both sides swing, both swings land:

```
damage = attack_attribute + d3 − floor(defence_attribute / 2)      minimum 1
```

Only the **attribute pair** changes, and it comes from the attacker's profile (§3) — melee reads Strength vs Endurance, ranged Dexterity vs Speed, arcane Intelligence vs Intelligence.

Everything the current implementation says about this formula still holds and should be preserved verbatim in spirit:

- **The minimum of 1 is not cosmetic.** Without it a Gnome swinging at an Ogre deals nothing forever and a mismatched fight hangs instead of resolving.
- **Both swings land even when one is lethal.** A dying skeleton gets its last hit in, which is what lets a doomed defender contribute to driving something off — the difference between a loss and a total loss.

### 4.1 Migration from the shipped code

`Combat.gd`'s Combatant contract currently requires `combat_might()`, checked by `Combat.is_combatant()`. That widens:

```
combat_name()            -> String
combat_profile()         -> Dictionary   # {attack_attr, defence_key, reach_px}
combat_defence(key)      -> int          # the attribute named by an attacker's profile
max_hp()                 -> int
hp                       : int
take_damage(n)           -> int
is_alive()               -> bool
hp_fraction()            -> float
```

`Combat.is_combatant()` must be updated in step — it exists precisely so a half-migrated unit fails loudly instead of silently dealing zero damage forever, and it can only do that job if its method list is current.

`Combat.FLEE_HP_FRACTION` (0.3) is **deleted, not re-tuned.** Routing is morale-driven (§5). Living recruits are still never killed by wildlife, but `CombatSystem._injure_and_flee` is reached via the rout check rather than an hp threshold.

---

## 5. Morale, and routing

Fights are lost by breaking, not only by dying. This is the highest-value rule in the spec and it reuses a stat that already exists.

### 5.1 Morale events in combat

| Event | Morale |
|---|---|
| An ally falls within sight (5 cells) | −2 |
| An ally routs within sight | −1 |
| Kill an enemy | +1 (Bloodthirsty only, per `TRAITS.md`) |
| Dropped below 50% hp | −1, once per fight |

Sight is a plain radius. No line-of-sight, no occlusion — there's nothing on the map to hide behind.

### 5.2 The rout check

A unit routs when `morale + rout_morale_offset <= ROUT_THRESHOLD` (baseline 3). Routing reuses the existing `TripStage.FLEEING` machinery: full walk speed to the idle anchor, drop the carried load, become `IDLE` on arrival.

`rout_morale_offset` comes from traits — Cowardly −2, Brave +2, Pack-minded −1 while isolated. Fanatic carries `never_routs`. Loner carries `ally_death_morale_immune`, so the first row of the table above never fires for them.

### 5.3 The undead never rout

Skeletons — anything with `alignment: "Undead"`, the same check `Laborer.is_undead()` already uses for Command Undead — have no morale and skip the rout check entirely.

**This is the class fantasy paying out.** Undead labour already doesn't eat and doesn't sleep; adding "doesn't break" makes it a genuine battle line. Living recruits hit harder individually and crack when their friends die; your skeletons hold. It costs one branch and it's the single strongest argument for the whole morale system.

It also means `CombatSystem._rally_and_scatter` keeps its current behaviour for skeletons — they neither rally nor scatter — and that behaviour is now *derived* from a rule rather than special-cased.

Note `Combat.FLEE_HP_FRACTION` is referenced in four files (`Combat.gd`, `CombatSystem.gd`, `Laborer.gd`, `Wolf.gd`). Removing it is a four-file edit, not a one-line deletion.

### 5.4 One coupling to be aware of

Settlement morale (hunger) and combat resolve are **the same number**. A starving settlement routs early. This is intended — it makes the food economy matter during a raid, which is exactly the cross-system consequence this game wants — but it does make famine doubly punishing. If playtest says it's too harsh, the split is a second field, not a redesign.

---

## 6. Judgement, Tact, and guidance

```
judgement = Tact + floor((Perception − 5) / 2)
```

Same helper shape as skill derivation. **Perception is what you notice; Tact is what you do about it.** A high-Perception low-Tact unit spots the wolf circling and charges anyway; a high-Tact low-Perception unit fights well within what it knows and gets blindsided. Collapsing both into one number is deliberate for now — separating them properly needs an information layer (units tracking what they've detected), which is far more machinery than these fights justify. Noted as the v2 if fights ever get complex enough to want it.

### 6.1 What judgement decides

Checked when a unit picks a combat action:

| Judgement | Behaviour |
|---|---|
| ≤ 3 | Charges the nearest enemy. Won't kite, won't withdraw, may pick a target it can't beat |
| 4–6 | Engages sensibly; withdraws when badly hurt |
| ≥ 7 | Ranged units maintain distance; melee units prefer already-engaged targets |

The Ogre (Tact 2) charges. The Gnome mage (Int 8, Tact 2) casts beautifully and has no idea when to fall back — which is precisely why he needs a sergeant.

### 6.2 The guidance rule

A unit with `judgement <= 3` within `LEADERSHIP_RADIUS` (4 cells) of an ally whose **effective Leadership ≥ 6** uses that ally's judgement band instead of its own.

This is the mechanic that makes a low-Tact heavy hitter an asset rather than a liability, and it's a pure expression of the indirect-control pillar: you never order the troll, you recruit someone who can handle him and house them near each other. It's the same *shape* as the auto-assist check already in `CombatSystem._will_fight` (`category == "Warrior" or might >= ASSIST_MIGHT_THRESHOLD`, within `ASSIST_RADIUS_PX`), so it slots into existing machinery. Note `_will_fight`'s Might test needs rewording to Strength as part of C2 regardless.

Charming (+1 Leadership) is the trait that plugs into this.

### 6.3 Cowardly

`requires_ally_to_engage: 3` — a Cowardly recruit won't *start* a fight without an ally within 3 cells. They'll still defend themselves. This is the trait's whole combat identity now that flat hp thresholds are gone, and it makes them awkward to place rather than merely statistically worse.

---

## 7. Creatures

**(Superseded 2026-08-06, amendment note 4: creatures carry all nine attributes.)** The original
reduced-set rule is kept below, struck through in spirit, because its *behavioural* half survives:
creatures still get **no judgement and no rout-check subtlety** — a hardcoded behaviour profile per
creature remains more honest than pretending a wolf weighs options. What changed is the *data*
shape: every creature authors the same nine attributes as every race, in `stat_rework_roster.xlsx`,
so combat needs no special case anywhere — an arcane attacker hits a wolf's own (low) Intelligence
instead of triggering a "creatures have no Int" branch. Low mental stats *are* the reduced set,
expressed as numbers instead of absences.

| Attribute | Wolf |
|---|---|
| Strength | 5 |
| Dexterity | 3 |
| Speed | **8** (→ 1.3 cells/sec via the workbook's walk divisor) |
| Endurance | 5 |
| Intelligence | **2** — the arcane-vs-beast knob; tune it if casters trivialize wildlife |
| Guile | 3 |
| Perception | 6 |
| Tact | 2 |
| Loyalty | 5 (pack morale baseline) |

Melee profile, always (Str 5 is its highest of Str/Dex/Int). Endurance 5 gives `max_hp` 18, which is exactly the shipped `Wolf.MAX_HP` — the creature needs no rebalancing, only re-expressing. Speed is now on the same 1–10 scale as everyone (the old draft wrote "1.3" in cells/sec — that unit mismatch is exactly why one scale everywhere matters).

**Speed matters more than it looks** — it's what lets a melee-only predator close on an archer, and without it two ranged recruits trivialize the entire creature layer. The wolf already has this: `CHASE_SPEED_PX` is 78, which against `CELL_SIZE` 64 is ~1.22 cells/sec. Express it as a Speed attribute so it reads like every other unit, and raise it to 1.3 (83 px/s) rather than treating it as a new capability. `PROWL_SPEED_PX` (34) stays a separate constant — ambling is a behaviour state, not a stat.

### 7.1 Packs

`MAX_WOLVES` rises from 1 to a pack of **2–4**, spawning together from the same treeline point. Packs are what make the morale rules visible: kill one wolf and the rest waver, which turns a fight the player watches into a fight the player can read.

Pack morale uses the same §5 table. A wolf that routs runs for the map edge and **looks for weaker prey** — re-targeting to deer rather than despawning, so a driven-off pack still costs you food. That is the wolf's design brief restated: an economic threat first, a threat to people second.

### 7.2 Unchanged from C1

The Necromancer's protection, the fed-wolf-stands-down rule, the carcass drop on a kill (`WOLF_CARCASS_BONES` 9, better than a seeded carcass's 5), the guaranteed first-dusk spawn, and the visibility tuning (entry 2 cells out, `TOKEN_SIZE` 46, `z_index` 6) all survive as-is. That tuning came out of playtests where the feature worked perfectly and the player never saw it — don't quietly revert it.

---

## 8. Consequence rules

Carried forward from C1, with one addition:

1. **Skeleton Workers can be destroyed.** No bones refunded, no corpse. Replaceable for 5 Bones.
2. **Living recruits are never killed by wildlife.** They rout, run home, and are `Injured` (no work) until healed, at −1 morale. True by construction — the rout check pulls them out before 0 hp.
3. **A deer taken by a wolf is a pure economic loss.** The common case, and the point.
4. **The Necromancer is untouchable**, and anything in his shadow is invisible to wildlife. Positional, so a worker who wanders off is fair game again.
5. **New: raiders can kill.** Rule 2 is a wildlife rule. An endgame raid where nobody can die is toothless, and the asymmetry is legible — a wolf is a hazard, an army is an army.

### 8.1 Healing

- **Living units: +2 hp per meal eaten** (`MoraleSystem._regenerate`). Ties injury to the food economy — a recruit who goes hungry doesn't heal.
- **Skeletons: 1 hp per 6s, only while idle at the Throne.** Necromantic maintenance; the undead perk cuts both ways.
- **New: Surgeon.** A recruit with effective Surgeon ≥ 5 heals an injured ally at the Barracks for `1 + floor((Surgeon − 5) / 2)` hp per meal tick, on top of the base +2. This gives Intelligence races defensive value without ever throwing a punch, and it's the hook disease plugs into (§11).

---

## 9. Gear — specified, unscheduled

Recruits arrive with little or nothing: a knife, a sling, whatever they walked in with. The Workshop sells better, and **the player can discount an individual's purchase to buy loyalty**.

That last part is the reason gear belongs in this game rather than being generic RPG furniture: it's bribery, not commanding, which is the pillar. It also gives Dark Essence and the Blacksmith a real sink.

**v1, when it happens, is one weapon slot** that sets the attack profile (§3.1 rule 2) plus a flat damage modifier. No armour slots, no durability, no inventory grid, no two-handed rules. The full system — item data, per-unit slots, Workshop-as-shop, the discount-for-loyalty mechanic — is larger than the combat work itself and needs its own spec.

*Amendment, 2026-08-29 (spec review):* the gear family also owns **backpacks** — a carry-raising slot item, v1+ material, deliberately scarce so the escort economy (`SORTIE_SPEC.md` §1.4) survives contact with it. See `LOOT_SITES_SPEC.md`'s 2026-08-29 amendment, ruling 5.

*Amendment, 2026-08-29 (second):* the gear/economy spec also owns the **Storage Shed** (the built home of banked loot; the banking anchor moves there from the Throne when it exists) and the **Shop** — the player sells chosen items at prices they set, recruits buy, which is this section's discount-for-loyalty mechanic generalized. Gold and `arms` get their sinks there. See `SORTIE_SPEC.md`'s 2026-08-29 amendment, ruling 1.

## 10. Classes — specified, unscheduled

Mages are a **role layer on top of race**, not a race. Every race has its own flavour: orcs have shamans, elves have wizards. Rare, but they appear.

A class sets the default attack profile (§3.1 rule 1) and probably shifts attribute rolls toward its key stat. Open: whether class is rolled during recruit generation as a second independent roll, or is a rarity tier of its own.

**A trait never grants a class.** Race is biology, traits are personality, class is role — three separate layers, and merging any two of them will be regretted.

## 11. Disease — specified, unscheduled

The only genuinely new condition value. It plugs into Surgeon (§8.1) and the meal tick, and it's what gives Surgeon a second job beyond patching combat wounds. Deferred until the Stage 1–3 loop and the combat rework are both stable — it's a debuff system, and debuff systems are miserable to balance against an economy that's still moving.

---

## 12. The authoring problem (read before scheduling C2)

**(Resolved 2026-08-06: `stat_rework_roster.xlsx`, beside this file, contains the whole thing —
attributes, templates, overrides, derived effective skills, and the export order of work. C2 is
now an engineering task. The workbook also carries the creature and villain rows per amendment
note 4. The section below stands as the record of the approach.)**

The rework takes each race from 14 authored values to **21** — nine attributes plus twelve skills — across 17 races, plus class variants later. That's roughly 360 hand-picked numbers, and it is a *design-hours* problem, not an engineering one. It is the single most likely thing to stall this work.

Recommended approach:

1. **Hand-author the nine attributes per race** (153 values). This is the part that carries the design intent and it's genuinely doable in one sitting.
2. **Derive skill baselines from per-category templates** — `warrior`, `miner`, `forager`, `scholar`, `versatile` — with a handful of per-race overrides. A Gray Dwarf is the `miner` template plus a Crafting override. This replaces 204 hand-picked numbers with five templates and maybe twenty overrides.
3. Keep the templates **in `races.json`**, not in code, so rebalancing stays a data edit.

`RACES.md`'s table is the input to step 1 and needs rewriting as part of C2 — the current Might/Guile/Influence/Loyalty columns don't survive.

---

## 13. Exit criteria

C2–C3 count as proven when all of these hold in one unbroken session:

- [ ] **1.** A Dexterity-heavy recruit fights at range and a Strength-heavy one closes to melee, with no code path naming either race.
- [ ] **2.** A Gray Dwarf out-mines a Skeleton Worker on the same deposit by a visible margin, and the margin traces to the derivation formula.
- [ ] **3.** A wolf pack attacks; one wolf falls; the rest visibly waver and at least one routs.
- [ ] **4.** Skeletons hold a fight that living recruits break from, in the same engagement.
- [ ] **5.** A low-Tact heavy hitter behaves differently with and without a high-Leadership ally nearby — and the player can tell which is happening from the log.
- [ ] **6.** A starving settlement routs measurably earlier than a fed one.
- [ ] **7.** An injured recruit is healed faster at a Barracks with a Surgeon present.
- [ ] **8.** No soft-locks: a settlement of pure casters, a settlement with zero Tact, and a full rout all resolve without hanging.

---

## 14. Open questions

- **Rout recovery.** Does a routed unit return to the fight if morale recovers mid-engagement, or is it out until the fight ends? Out-until-over is simpler and probably reads better.
- **Ranged in the trip loop.** A Hunting-skilled archer should plausibly take deer faster than a forager finds berries. Does hunting become a combat action against the deer, or stay a gather action? Combat is more consistent; gathering is far less work.
- **Does the Necromancer have attributes?** He's untouchable and doesn't fight, so he needs none today. C4 spells may change that.
- **Judgement bands vs a continuous roll.** Three bands are legible and cheap; a roll would be smoother but harder for the player to reason about. Bands until proven insufficient.
- **Class as a rarity tier or an independent roll** (§10).
- **Whether `/2` or `/3` is the right derivation divisor** (§2.3) — needs the re-authored roster before it can be judged.
