# His own two hands — engage close, cast far, and the aura becomes geography (R2b)

Prompt **R2b**, against the whole of `NECROMANCER_SPEC.md` (body plus the binding 2026-08-29
amendment), `COMBAT_SPEC.md` §3's profile table, and `SORTIE_SPEC.md` §6 for his zero. R2a was
done — the den packs and site guardians this makes fightable had to exist first — and C2 was done,
which the prompt asked to be checked before anything else: `combat_might()` survives only in
comments and in a `verify_stats` assertion that `is_combatant` *rejects* a unit still implementing
it. Nothing to stop for.

The old comment block at the top of `CombatSystem.gd` predicted this pass by name. It said the
lair aura was "a named flag rather than hardcoded behaviour because ROGUELITE_REWORK §15 lists
[it] as an open tunable", that flipping it off was "necessary but **not sufficient**" because "he
is not in `_prey_candidates()` at all", and that "the consequence rules below have no branch for a
villain losing a fight". All three are now false, which is the shape of this commit.

---

## 1. What he does now

**Walking in is attacking.** A fight opens when he closes to `VILLAIN_ENGAGE_PX` of something
hostile — which is `Wolf.ENGAGE_RADIUS_PX`, taken from the wolf rather than restated, because a
second "close enough" number that drifted from the first would be invisible until a playtest
could not explain why a fight started early.

**Once engaged he casts at five cells.** Not a constant in `CombatSystem`: it is
`combat_profile()["reach_px"]`, off C2's profile table, because his reach is a property of being
Arcane. If a relic ever changed his profile, a local copy would be the first thing to drift.

**Walking out is disengaging**, and he is never rooted. There is no `in_combat` on him — the
harness asserts its absence — and his engagement membership is the `Engagement` that
`_advance_villain()` adds him to and removes him from. That ordering matters: the villain step runs
*before* the engagements are advanced, so a villain who has walked out is off the defender list by
the time the frame's exchanges are rolled, which is what "stops his swings the next interval" means
in code.

**No auto-engage at five cells**, and §3 says why in a sentence worth keeping: he would snipe every
wolf that wandered past, "he never auto-seeks" would become a lie, and stealth-by-default would
stop being the fiction's resting state. Starting a fight costs the walk into biting distance;
only *running* one rewards positioning.

**Retaliation needs no input.** Anything that hits him is answered from the next exchange, from
range — which required one correction, below.

`Combat.gd` and `Engagement.gd` are **untouched**. C2 already widened the contract to profiles and
this pass only reads it; the villain is Arcane because Intelligence 7 is his highest of
Str/Dex/Int, with no special case anywhere. (One stale line survives in `Combat.gd`: the reach
constants still carry "Nothing consumes reach in this slice". That was true of C2's slice, and this
is the slice it was written in anticipation of — left alone rather than edited, since the spec is
explicit that touching either file means the design has drifted.)

---

## 2. The aura, made geography

`LAIR_AURA_PROTECTS_VILLAIN` is **deleted**, not set to false — §8's instruction, and its reason is
good: a dead flag beside a live rule is how the next reader flips the wrong one. In its place:

```
CombatSystem.aura_protects_villain()  ->  Necromancer.is_in_lair_band()
```

The position test lives on the villain because it is a fact about *his position*, which he owns;
the policy built on it is the combat layer's. And it has **three consumers reading one line**:

1. the aura itself — wolves fear him inside the band and nowhere else;
2. his membership in `_prey_candidates()` — outside it, a dusk wolf, a den pack and a site
   guardian all hunt him like anyone else;
3. his regeneration rate.

That the amendment's regen ruling reuses this exact test is the whole of its implementation, which
is what "one test, two consequences" was asking for.

Two knock-ons worth recording. `_is_valid_target()` reads `is_injured`, which the villain does not
have and deliberately never will (§6: he does not flee, the player decides) — so he gets an
explicit branch there rather than an accidental crash the first time a wolf re-validated its
target. And `Wolf.get_inspect_data()`'s promise line now reads the position rather than a flag: it
says *"It will not go near the Necromancer while he is in his own valley"* at home and *"Out here,
nothing keeps it off the Necromancer"* in the field. A panel still promising protection in the
wilderness would be the single most expensive lie this game could tell, so the wolf takes a villain
reference at spawn — handed in beside `world`, never looked up — purely to answer that question.

The consequence the spec wanted stated: **the lair band is now mechanically home.** Fleeing a
botched sortie back across the edge is reaching sanctuary.

---

## 3. Regen (amendment ruling 1)

A trickle afield, six times faster at home, **stopped entirely** while anything is fighting him —
not slowed, stopped, because healing through an exchange would blunt every threshold §6 exists to
announce.

The rate was not chosen by asking "how fast should healing be" but by the constraint the amendment
gives: *a den fight must not be resettable by circling the clearing.* At one hit point per 24
seconds, clawing back the ~12 hp a pack costs is four minutes of a thirty-minute day standing
still. The harness asserts that number against `DayNightCycle.DAY_SECONDS` rather than against a
literal, so a shorter day would trip it.

The amendment's hot-slot row is R5 material and is **not built**, as instructed.

---

## 4. His zero

`Necromancer.take_damage()` still emits `villain_died` — the emission stays on the data object so
that *anything* able to hurt him announces it, not just this file. The consequence half is new:
the unbanked haul is cleared, he respawns at the Throne at full hp, the log is loud. R4 still owns
the run ending, and R2c's `SortieSystem` takes this handler over rather than reinventing it.

It is connected in `CombatSystem._ready()`, which runs during `_build_systems()` — well before
`Main._connect_signals()` — so the clearing happens before the log line can describe a haul he no
longer has. `SORTIE_SPEC` §6 words that as "before anything else reads them", which is an *ordering*
claim, so the harness tests it by connecting a handler afterwards and reading the villain from
inside it rather than by inspecting the aftermath.

---

## 5. The den breadcrumb (designer ruling, 2026-08-30)

At dawn, when the raid resolves and the wolves have gone, the log reads the ground: *"Tracks in the
snow lead toward the woods south-east of here."* — the bearing from the settlement to the nearest
den still standing, in eight plain-word sectors. A hint in a sentence: no marker, no path, and **no
change to the spawn**, which stays settlement-relative exactly as before. Silent once the last den
falls, because at that point there is nothing to point at and the quiet is the reward.

> **Placement settled 2026-08-30.** The first build put this in the dusk handler, which is where
> the ruling asked for it — but that puts an arrival's verb on a departure's sentence, because at
> dusk nothing has gone anywhere yet. Dawn is when the raid actually resolves, and tracks are what
> a player can read off snow. Moved, and phrased as tracks; `R2_PROMPTS.md`'s 4c item was reworded
> to match what shipped so the prompt file stays honest.
>
> One consequence worth stating: a quiet night leaves no tracks. The line fires only when the night
> actually brought a wolf, which the harness asserts alongside the placement itself — dusk must say
> nothing, dawn-after-a-raid must speak, dawn-after-nothing must not.

---

## 6. Two bugs this pass produced, and the harness caught

Both are worth recording because neither would have shown up in play for a long time.

**The engage signal missed every fight he did not start.** The first version emitted
`villain_engaged` only on the walk-in path. But the wolf's own policy runs earlier in `_process`,
so a wolf that closes on him opens the fight first and the walk-in branch is never reached — which
is exactly §4's retaliation case, the one place he is engaged without touching a key. The signal
now fires off **the membership changing, whoever changed it**: one place, both directions, no way
for the HUD to be told about half of his fights.

**The death handler resurrected other people's villains.** `villain_died` is a global signal and
every villain emits it; `_on_villain_died` acted on whoever the signal carried. With one villain
that is invisible. With the harness simulating a thousand fights on throwaway `Necromancer`
objects, the live handler healed each simulated villain back to full the moment it died — so he
"survived" pack fights indefinitely and the reported win rate was **31.6% instead of 0%**. The
numbers were fiction and looked plausible, which is the worst kind.

The fix is one line — ignore a villain that is not this system's — and it is the exact discipline
ROGUELITE_REWORK §11 exists to enforce: *no system may assume there is exactly one villain on the
map*. A second villain would have been respawned at somebody else's Throne. It is now a CLAUDE.md
gotcha, because the shape generalises to every global signal that carries a villain.

---

## 7. Verification

`tools/verify_villain_combat.tscn` — **65 assertions**, run as a scene, per §10:

| Claim | How it is tested |
|---|---|
| the aura is a place | from **both sides** of the band edge, same villain, same frame: home ⇒ protected and off the menu; one cell out ⇒ neither |
| engage close | at four cells he starts nothing; at 25px he does, announces it, and both swings land |
| cast far | he keeps exchanging from four cells and the damage lands there |
| disengage | past five cells the engagement ends, says why, and no further exchange lands |
| retaliation | engaged from four cells with no input, and he answers from range |
| never rooted | `in_combat` is asserted **absent** from him |
| regen | half an interval heals nothing, a full one heals exactly 1, the band multiplies it, and it is **stopped** — not slowed — while engaged |
| his zero | a handler connected *after* the system's reads an already-empty haul; full hp; at the Throne; out of the fight |
| the breadcrumb | the compass from four known bearings; **the placement** through the real handlers -- dusk silent, dawn-after-a-raid speaks, dawn-after-a-quiet-night silent; and silence once every den is cleared |
| the flag is gone | `LAIR_AURA_PROTECTS_VILLAIN` is asserted not to exist |

The 1,000-fight bands, printed on every run:

```
Int 7 vs one wolf          won 100.0% of 1000, averaging 12.0 of 20 hp left
alone vs a 3-wolf pack     won   0.0% of 1000
```

That is §1.2's "costly win" shape exactly: he takes a lone wolf every time and it costs him 40% of
his health, and the den is not soloable at baseline. Both are asserted as **bands**, not points — a
point estimate would fail on noise and teach everyone to ignore the harness.

Full suite green: `verify_villain_combat` 65, `verify_loot_tables` 500, `smoke_site_actions` 26,
`verify_terrain` 261, `check_sprite_scales` 122, `verify_stats` 505, `verify_combat_feedback` 31,
`check_fog_and_minimap` 41. Headless boot clean.

### The one number that did not match the spec — corrected

§10 asked the harness to assert that kiting yields "at most 2–3 exchanges before the wolf closes".
**It yields ten, and the spec's own figures did not produce three either.**

```
reach 320px − bite 26px            = 294px to close
wolf 83.2px/s − villain 64px/s     =  19.2px/s closing
294 / 19.2                         =  15.3s  =  10 exchange intervals
```

Using §3's own quoted "78px/s against his 64" gives fourteen, not three. Both speeds are correct
and deliberate — his 1.0 cells/sec is R1's tuned travel value (`TERRAIN_SPEC.md` §9 says outright
it is not a knob) and the wolf's 1.3 is what `COMBAT_SPEC.md` §7 asks for by name — so the
constants are right and the prose is wrong.

The harness therefore asserts what is true and load-bearing: **the wolf is faster, so retreating
can never open the gap** — kiting delays and never escapes, bounded by his hit points rather than
his legs — plus a pinned band around the shipped figure so drift in Speed, chase, reach or the
exchange interval trips it. The derivation is printed on every run rather than buried.

**Ruled 2026-08-30: the pin is accepted and the spec was corrected**, with the arithmetic written
into §10 in place so nobody re-derives it. Nothing was tuned to fit the sentence. §10's tunables
gained the matching line: if a playtest shows a lone wolf dying damage-free to kiting, the lever is
**wolf hit points or a chase-lunge** (`COMBAT_SPEC.md` §7 territory) — never the two speeds, which
are load-bearing elsewhere.

---

## 8. Needs a human

§10's own question, unchanged and unanswerable headless: **does walking into engage range feel
like a decision or an accident?** Twenty-six pixels is under half a cell; the fear is that a player
threading past a wolf starts a fight he did not choose. If it reads as an accident the tunable is
`VILLAIN_ENGAGE_PX`, not the split.

And the payoff the Arcane profile was chosen for — **does casting over the escort read on screen?**
— cannot be answered until R2d puts skeletons between him and the thing biting. F1's red numbers
exist and should make the smoke-test fight legible in the meantime.

Two smaller things to watch:

- The HUD now carries his hit points beside the badge, red below `Combat.FLEE_HP_FRACTION` (read
  from the constant, not restated). He does **not** auto-flee at it — deliberate, §6 — so the
  readout is the game making sure nobody dies uninformed while leaving the panicking to the player.
- Whether the field regen at 24s/hp feels like a real choice or just like waiting. The lever if it
  reads as tedium is the rate, not the rule.
