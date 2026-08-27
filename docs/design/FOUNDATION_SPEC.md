# Foundation Spec — Stages 1–3 baseline values

Concrete numbers for the foundation build (Stages 1–3 of `GAME_OUTLINE.md`: collect → build → recruit & settle). Everything here is a **starting hypothesis for playtesting**, not gospel — but code should read these values from data, so retuning is a JSON edit, not a code change.

**Current roadmap focus:** a smooth run of Stages 1–3 only. Bounty board, missions, training centers, market/trade, grudges, and spells are **hard-locked** until this loop is proven. The Barracks gets its **Upgrade button now, but hard-locked** ("Locked" state, no cost shown) as a visible promise of the roadmap.

---

## 1. The stat scale and the Human Peasant reference

All stats and skills run **1–10**. The reference point is a **Human Peasant = 5 in everything**: average strength, average cunning, average work speed, walk speed 1.0. Every race is stated *relative to him*. (Humans aren't recruitable — the peasant exists as the measuring stick, and later as the good nations' commoner NPC.)

Stat groups:

- **Character stats:** Might, Guile, Influence, Loyalty (unchanged from current code)
- **Labor skills (new):** Woodcutting, Mining, Foraging — these drive *work speed*, not permissions. Anyone can chop; skill decides how fast.

## 2. Race baselines

**The full roster (16 races with alignment, rarity, and housing styles) lives in `RACES.md`** — that file supersedes the starter table below, which is kept as a quick reference for the core eight. Baseline = the racial *average*. Individual recruits vary (Section 3).

| Race | Category | Might | Guile | Influence | Loyalty | Woodcut | Mining | Forage | Walk speed | Food/meal |
|---|---|---|---|---|---|---|---|---|---|---|
| *Human Peasant (ref)* | — | 5 | 5 | 5 | 5 | 5 | 5 | 5 | 1.00 | 1.0 |
| **Skeleton Worker** | labor | 4 | 2 | 1 | 10 | 3 | 3 | 2 | 0.90 | **0** |
| **Orc** | Warrior | 7 | 4 | 4 | 5 | 5 | 4 | 4 | 1.00 | 1.5 |
| **Ogre** | Warrior | 9 | 2 | 2 | 4 | 6 | 6 | 3 | 0.80 | 3.0 |
| **Gray Dwarf** | Economy | 6 | 4 | 4 | 6 | 4 | **9** | 2 | 0.85 | 1.0 |
| **Minotaur** | Economy | 8 | 3 | 3 | 5 | 7 | 7 | 3 | 1.10 | 2.5 |
| **Gnome** | Research | 2 | 7 | 5 | 5 | 2 | 3 | 4 | 0.90 | 0.75 |
| **Goblin** | Foraging | 3 | 6 | 2 | 3 | 3 | 3 | **8** | 1.15 | 0.75 |
| **Gnoll** | Foraging | 5 | 5 | 2 | 4 | 3 | 2 | **9** | 1.20 | 1.5 |

Reading it: a Goblin (Might 3) is weaker than the human (5), who is weaker than a Minotaur (8) — per the design rule. Skeleton Workers are mindlessly loyal (10), tireless, unfed, but mediocre labor (3s) — living specialists out-work them in their specialty, which is what makes gathering bounties worth posting later. Skeletons *can* forage berries and hunt deer (Forage 2) — slowly and clumsily, but it means your undead can stock the larder before any living recruit arrives.

## 3. Recruit generation (RNG variety)

Per stat/skill, a generated recruit rolls:

```
value = clamp(baseline + d3 - d3, 1, 10)     # d3 = randi 1..3 → range ±2, bell-shaped
```

- Two dice give a center-weighted spread: most recruits sit at baseline, ±2 is rare. Some ogres are just stronger than others.
- **Exceptional roll:** 5% chance per recruit of +1 to their race's *category-defining* stat after the roll (warrior → Might, economy → best labor skill, research → Guile, foraging → Foraging). These are the recruits worth funding houses for early.
- Loyalty rolls the same way but is the *starting* value — it moves with play. Skeleton Workers don't roll; they're fixed at baseline (interchangeable by design).
- Walk speed and Food/meal are racial constants — no per-recruit variance.

## 4. Movement

- **Walk speed 1.0 = 1 grid cell per second** (the Human Peasant). Racial multipliers in the table. Characters **walk everywhere by default** — running is reserved for battle, escapes, and emergencies (a later system; walking is the only mode in the foundation build).
- Workers/recruits physically travel: settlement → node → gather → settlement → deposit. Distance now matters — a far forest is genuinely slower than a near one.

## 5. Resource nodes (finite)

| Node | Contains | Yield unit | Notes |
|---|---|---|---|
| **Tree** | 10 Wood | 1 Wood per chop | **Finite, no regrowth.** A chopped-out tree is gone (stump). If wood scarcity becomes a problem later, the planned fix is a *manual replant-seeds action*, not automatic regrowth. |
| **Forest** | 15–25 Trees | — | A cluster of Tree nodes; visibly thins as it's cut. |
| **Stone Deposit** | 250 Stone | 1 Stone per mine action | Finite but deep — one deposit covers most of a run. |
| **Berry Grove** | 40 Food cap | 1 Food per forage | **Regrows +8 Food at each dawn** up to cap (tied to the day/night cycle, Section 7) — food is renewable (unlike trees), but a grove supports only a few big eaters per cycle. |
| **Deer** | 8 Food per deer | whole deer on kill | Wild game roaming near the map edges. Hunt uses Forage skill (find/stalk); a kill is hauled home like any load. **2–3 deer on the map at once; a new one wanders in each dawn** up to that cap. Higher yield than berries, but the hunter is away longer. |
| **Animal Bones** | 5 Bones each | 1 Bone per gather | Carcasses scattered inside Forests — workers haul them home like any load. A forest hides 3–5 carcasses among its trees. Finite. |
| **Grave** | 12 Bones each | 1 Bone per dig | **Uncommon** finds: alongside a road, deep in the forest, by an abandoned house, or on a village's outskirts. Richer than carcasses, but few — and the closer to civilization, the more this foreshadows *whose* graves you'll be robbing later. Finite. |

Bones on the map are **finite** — which naturally caps the early skeleton workforce and is exactly why, come Stage 4, *it's just easier to set up harvest bounties*. The map teaches the escalation.

Map seeds for the foundation build: 1 Forest (east, ~20 trees + 4 animal carcasses), 1 Stone Deposit (south), 1 Berry Grove (west), 2 Graves (one by the road, one at the forest's far edge). Fixed positions for now, procedural later.

## 6. Work model (replaces the flat 4s tick)

The old `WorkerSystem` flat timer (+1 resource / 4s regardless of anything) is replaced by a **trip loop**:

```
walk to node → gather until carry-full or node empty → walk home → deposit → repeat
```

- **Gather time per unit:** `base_time × 5 / skill`, with `base_time = 4s`.
  - Human peasant (skill 5): 4s per unit — matches the old tick rate, so overall pacing survives.
  - Gray Dwarf mining (9): ~2.2s per stone. Skeleton (3): ~6.7s. Skill is *visible* as speed.
- **Carry capacity = Endurance.** (Reworded 2026-08-06 per `COMBAT_SPEC.md` §2.1's adopted stat rework — was Might; the code says Might until prompt C2 migrates it.) An Ogre (End 8) hauls 8 units per trip; a Gnome (End 3) makes many small trips. Endurance carrying HP *and* load is deliberate — it opens the tough-porter build without rebuilding Might under a new name.
- Priority list (Stage 1 system) decides *which* node type a worker heads to on each new trip, using the threshold fall-through rule.

## 7. Day/night cycle

- **Day: 30 minutes. Night: a little shorter — 20 minutes.** Full cycle 50 min. Tune after feel-testing.
- Foundation build keeps it minimal: a clock, a lighting tint shift, and the meal ticks below. Sleep schedules, night work penalties, and night-only events are later systems.
- Natural undead perk already implied: Skeleton Workers don't sleep — whatever night behavior living recruits get later, undead labor runs 24/7.

## 8. Food consumption (foundation-simple)

- **Meals are tied to the day/night cycle: one at dawn, one at dusk** (2 meals per full cycle). Each living recruit eats `Food/meal` (racial constant) per meal. Skeletons eat nothing.
- Not enough food → the shorted recruit loses **1 morale** (morale 1–10, starts 7). At morale ≤ 3: theft/rule-breaking events possible; at 1: departure warning, then leaves.
- Morale is **per-recruit** in data even if the foundation UI only shows a settlement average — cheap now, enables "the hungry ogre riots first" later.
- Feeding order when short: highest Loyalty eats first (the faithful get fed; malcontents starve — very villain).

## 9. Barracks (foundation state)

- Cost: 8 Wood, 6 Stone. **Capacity 5. Only one can ever exist.**
- **Upgrade button: present, hard-locked** — greyed "Locked" state, no tooltip cost. Unlock is a roadmap milestone, not a hidden requirement.
- Recruitment events require: Barracks built AND free slot. Full Barracks = offer fizzles with a clear message.
- Fund-a-house (frees a slot): flat **6 Wood, 4 Stone** for the foundation build (per-race costs later). **The recruit picks the spot by their race's housing style** (Clustered/Communal/Spaced/Near-feature/Edge — see `RACES.md`): goblins pile in next to each other, a minotaur wants empty cells around him.

## 10. Starting state (Stage 0)

| Item | Value |
|---|---|
| Buildings | Throne of Bones only |
| Workers | 1 Skeleton Worker |
| Wood / Stone / Bones | 8 / 5 / 10 |
| Food | 5 (a small larder for the first living recruit) |
| Dark Essence | 0 — not part of the foundation loop (harvest bounties are locked) |
| Followers | 0 |

10 starting Bones = 2 extra Skeleton Workers (5 Bones each) before any gathering.

## 11. What "running smoothly" means (foundation exit criteria)

A run of Stages 1–3 counts as proven when, in one unbroken session:

1. Priority list drives 3 workers across Wood/Stone/Bones with thresholds, and trees visibly deplete.
2. Barracks gets built from gathered (not starting) resources.
3. At least 3 recruits arrive via events spanning ≥2 categories, get fed every meal tick, and none desert from a bug rather than a real shortage.
4. One recruit gets a funded house; Barracks slot frees; town visibly grows.
5. One food shortage is survivable and legible (morale drops, player recovers by reassigning priorities).
6. No soft-locks: node exhaustion, full Barracks, and zero-food states all have clear UI messaging and a way out.

## Open questions (foundation-scoped)

- House placement rule: pure random-adjacent, or race-clustered (goblins burrow together)?
- Deer hunting in the foundation build: does the Food priority send workers to berries vs deer automatically (nearest/most efficient), or are they separate priority entries?
- With meals at dawn/dusk on a 50-min cycle, do the Food/meal values need scaling up so food still feels like a real economy? Playtest — a 30-min day is long; food may only bite once recruits number 4+.
- Night behavior for living recruits (sleep? slower work?) — deferred, but the skeleton 24/7 advantage should be preserved whatever is chosen.
