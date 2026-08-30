# Getting it home — the deposit, the drop, and what death costs (R2c)

Prompt **R2c**, against the whole of `SORTIE_SPEC.md` (body plus the binding 2026-08-29 amendment)
and `ROGUELITE_REWORK.md` §1's banking rule. R2b was done: he can fight his way back.

This is the pass that makes the haul mean something. Until now loot went into
`Necromancer.carried` and stayed there for ever — R2a filled his hands and R2b could empty them by
killing him, but nothing ever turned a haul into a number the settlement could spend.

---

## 1. The banking rule, at sortie scale

> Nothing is yours until it is home.

The trip loop already proves the shape — a worker's resources enter `GameState` only on deposit —
and this is the same rule at four minutes' range with a much bigger number on the line. Everything
in this pass falls out of it: why death costs the haul, why a relic in his hands does nothing, and
why putting something down is a real decision.

**`scripts/villain/SortieSystem.gd`** is the new policy layer, the third beside `WorkerSystem` (the
trip loop) and `CombatSystem` (fights). It takes `villain`, `settlement` and `world` as fields and
never looks a villain up — one instance per villain, and a second one would get his own Throne, his
own escort and his own haul, sharing only `GameState`, which is world state by design.

It needed a fourth field the spec's §9 list does not have: `world_sites`. The 2026-08-29 amendment
makes an open-country drop **spawn a site**, and sites are that container's business.

---

## 2. The deposit

**Automatic, at the Throne, no button.** The check runs every frame and fires when he is within
`DEPOSIT_RADIUS_PX` with something to bank. That constant is
`CombatSystem.THRONE_REPAIR_RADIUS_PX` — 1.5 cells, taken from the existing precedent rather than
invented, so "close enough to the Throne" means one thing in this project.

No prompt, deliberately: the worker trip loop deposits without one, and a confirmation dialog
between the player and the thing they walked four minutes for is friction rather than tension.
Partial deposits are free — no minimum, no penalty. The tax is the walk.

### The band is not the Throne

The single most likely thing in this pass to be "simplified" later, so it is worth writing down
plainly. `TravelLog` treats `world.lair_band.has_point(...)` as **home**, and that is correct — for
*measuring a journey*. Banking is a different question and happens at the Throne.

The band is 26×26 cells. Crossing its edge is not an arrival, and making the player walk the last
few cells keeps the final seconds of the return leg real. The harness asserts it from both sides:
standing one cell inside the band with five bones banks **nothing**, and walking on to the Throne
banks all five. It also asserts the two radii have not quietly become one.

---

## 3. Party capacity, and where loot goes

The arithmetic is §2's and lives in `SortieSystem`, not on the villain — §9 is explicit that he
must not hold his own escort's capacity logic, because that is the seam where "the villain knows
about the party" becomes "the villain owns the party".

```
party_capacity() = villain.carry_capacity() + Σ escort_member.endurance
```

Villain alone: **6**. With two End-4 skeletons: **14**. Both asserted against the stated numbers
rather than against whatever the code computes, because those are the numbers every loot table was
tuned against.

**Filling order is villain first, escort second, remainder third.** Not the reverse: the villain is
who survives, and if the party is going to lose someone on the way home it should not be the one
holding the haul. Each escort member hauls **one kind**, through the `carrying_kind` /
`carrying_amount` pair `Laborer` already owns — a skeleton is a pair of arms, not a pack, and
reusing those fields means the worker deposit path works on them unchanged.

Sites reach this through a `party_filler` Callable, the same pattern as `day_provider` and
`guardian_spawner`. The escort itself is R2d's, but the seam is in place so that pass does not have
to reopen `WorldSite`.

**Two things about that Callable went wrong and are worth recording**, because both were caught by
existing tests rather than by thinking:

- It was set per-site in a loop over `world_sites.sites`, so a site created *later* — a dropped
  cache — never got one. Moved onto `WorldSites` itself, which hands it to everything it builds.
- Its first signature was `(kind, amount)`, so it filled whoever `SortieSystem` held rather than
  the villain the site was handed. In the game those are the same man. In `verify_loot_tables`,
  which rolls tables into throwaway villains, it silently filled the *live* one and eleven
  assertions went red. It now takes the villain as a parameter and reads the escort off him, which
  is `LOOT_SITES_SPEC.md` §3's rule — *passed as a parameter, never looked up* — restored.

---

## 4. Relics wake at the Throne

`LOOT_SITES_SPEC.md` §7's rule, now with a place to happen: the six live effects read from
`relics_banked`, and `bank_relics()` is called by the deposit. A relic in his hands grants nothing,
which is exactly what keeps "drop it and run" a live choice on the return leg rather than a pure
loss.

All six readers already existed from R2a — this pass connected the switch. The two dormant ones
(`noble_seal`'s Wealth-axis bonus, `ledger_of_names`' escort cap) stay dormant and the panel still
says so.

---

## 5. Dropping, and the cache

The amendment struck destruction. Dropping in open country now leaves a **`dropped_cache`**, and
the reason it is short to implement is the reason it is the right design:

> A cache is a site with `charges: 0` and a remainder.

`actions_for()` already offers *"Collect what you left"* for a remainder and nothing else for zero
charges. `is_spent()` already flips to the looted sprite when the last of it is taken. Full reuse of
the site machinery, exactly as the ruling asks — there is no cache *type* in code beyond the label.

One real bug fell out of that: `_setup_lootable` clamped `charges` to a minimum of 1, so the cache
got a phantom "Search it" action that would have rolled a table named `""`. Zero is now a legal
answer, and the guard moved to `verify_loot_tables`, which asserts every **authored** site has at
least one charge — which is where "this is a content mistake" actually means something.

Other properties, all asserted: the cache holds the exact dropped contents; re-looting empties it;
it is **never Raven-eligible** (`WorldSite.is_raven_eligible()`, stated now so R2e cannot miss it —
a bird announcing "I found something" about a pile you left twenty seconds ago is how players learn
to stop trusting it); and it sits outside the 10–15 active density budget, which counts authored
sites from the JSON and so cannot be inflated by anything the player creates.

Dropping beside your own cache adds to it rather than littering a second one — that falls out of
the in-reach path finding it, not from a rule of its own.

**The two paths still differ**, which the amendment insists on: in-reach emits
`sortie_load_dropped` with the site he was standing at; open country emits that *plus*
`sortie_cache_created`. The second is a genuinely different event — a new site now exists in the
world — and it is the hook R3's scavengers want.

---

## 6. Death

Moved out of `CombatSystem` and into `SortieSystem`, which is what that handler's own comment said
would happen. `carried`, `relics_carried` and every escort member's load are cleared, he respawns
at the Throne at full hp, and the log is loud. What stayed behind in `CombatSystem` is the part
that is genuinely combat's: taking him out of any fight he was in when he fell.

Ordering is the whole claim — §6 says "before anything else reads them" — so `SortieSystem` is
built before every other listener, and the harness proves it by connecting a handler *afterwards*
and reading the villain from inside it rather than by inspecting the aftermath.

---

## 7. `arms` had to go somewhere

`LOOT_SITES_SPEC.md` §9 says `GameState` gains gold and "nothing else". That line **predates the
same document's 2026-08-29 amendment**, which introduced `arms` as a carryable loot kind — so as
written, a kind he can carry could never be banked, and every deposit containing weapons would have
printed `unknown kind` and silently dropped them.

So `arms` banks, and does nothing: no building spends it, no recipe reads it, its sink arrives with
`COMBAT_SPEC.md` §9's gear v1 exactly as ruling 2 says. The HUD shows it only once he has some, so
a permanently-zero counter is not sitting on the strip for a milestone.

**Flagged as a deliberate deviation** rather than buried — it is a spec line contradicted by a
later ruling in the same spec, and the alternative was shipping a visible bug.

> **Approved 2026-08-30** (designer). §9's row now carries a dated one-line correction pointing at
> ruling 2, rather than the section being rewritten around it.

---

## 8. Legibility (§7)

- **Carry state beside the Away timer**: `Carrying 4 / 6`, or `6 / 6 — full`. The panel has it too,
  but the panel is closed exactly when it matters — closing it is how you get back to driving him —
  and "he was full" must never be something a player learns from a site refusing to pay out.
- **A dusk warning**, only while he is outside the lair band with the light going: *"The light is
  going — 1m 40s of it left, and you are 38 cells from home."* Inside the band he is home and the
  warning would be noise. It reads the day cycle's own clock, so it inherits the debug time scale.
  Both the threshold (two minutes) and the wording are §10 tunables.
- **The round-trip line names the haul**: *"Home. Round trip 4m04s — carrying 4 Bones, 2 Gold."*
  Read off his hands at the band edge, which is what that line measures. The deposit writes its own
  line a few cells later when the haul actually banks — the two are deliberately separate, for the
  same reason the two tests are.
- **Drop rows** on the villain's panel, one per carried kind and one per relic, with the panel
  saying *where it will land* before the click.

---

## 9. Verification

`tools/verify_sortie.tscn` — **66 assertions**, run as a scene, covering §10's list:

| Claim | How |
|---|---|
| capacity arithmetic | 6 alone, 14 with two skeletons, a relic eats a slot — against the stated numbers |
| filling order | eight bones fill the villain to his brim *first*, then spill to the escort; a skeleton already hauling bones will not also take gold |
| overflow | the exact remainder stays at the site, which still offers actions and is not spent |
| the deposit | banks without a prompt and empties villain **and** escort in the same frame |
| the band edge | one cell inside the band banks **nothing**; the last few cells bank everything |
| the two drop paths | in-reach returns to that site and creates no cache; open country creates one and emits its own signal |
| the cache | holds the exact contents, re-looting empties it, offers only the collect, is never Raven-eligible |
| relics | nothing in hand, everything on deposit, dormant ones still dormant |
| death | a handler connected *afterwards* reads an already-empty haul, escort included |

`measure_travel` gained the loaded-return row, and the claim it tests is a negative one: **carry
must not silently gate travel time.** It fills his hands and walks the village trip home again.

```
lair -> the village            2m06s   1m53s   108   in band (2m00s-4m00s)
village -> lair, hands full    2m06s   2m06s   108   in band (2m00s-4m00s)
```

Identical, as it must be. There is no encumbrance curve and there is not meant to be — §10 names
load-slowing-the-carrier as a *designated fallback lever*, adopted only by striking that assertion
openly. If the number ever moves, this row is where that conversation starts.

Full suite green: `verify_sortie` 66, `verify_loot_tables` 515, `verify_villain_combat` 65,
`verify_terrain` 278, `check_sprite_scales` 122, `check_fog_and_minimap` 50, `smoke_site_actions`
26, `verify_stats` 505, `verify_combat_feedback` 31. Headless boot clean.

### A testing note worth keeping

The harness hung on its first run with **zero output** — no banner, nothing. The cause was
`Worker.new()` called without its required name argument: the error aborted `_ready` before
`get_tree().quit()`, so the scene ran for ever, and Godot's block-buffered stdout meant nothing was
ever flushed. **A harness that hangs silently is usually an error thrown before its own `quit()`.**

---

## 10. Not built, on purpose

Everything the amendment blocks park elsewhere: the **Storage Shed** and the **Shop** (§9's future
gear/economy spec, where gold and `arms` finally get their sinks — moving the banking anchor from
Throne to Shed is a one-line position-test change when it lands), **scavengers** finding caches
(R3), and the **day/night risk axis** (R3, shipped as one coherent pass so the R2 exit playtest
measures a single pressure).

The escort itself is R2d's. Every path here handles it — capacity, filling, deposit, death — and
`villain.escort` is simply empty until that pass fills it.

---

## 11. Needs a human

§10's exit criterion is a feel question: **a sortie that fills the party's hands at two sites,
walks home at dusk with a wolf on the map, and banks the haul at the Throne — with at least one
moment where the player had to choose between one more pull and the light.**

Three things to watch:

1. **Does the last stretch to the Throne feel like arriving, or like admin?** The band-is-not-the-
   Throne rule is the one that buys the final seconds of tension, and it is also the one most
   likely to read as busywork if the walk from the band edge is boring rather than tense.
2. **Is the dusk warning early enough to act on?** Two minutes of a thirty-minute day is a guess.
   Too early and it is wallpaper; too late and it is an obituary.
3. **Does dropping ever feel right?** With destruction struck, dropping in open country costs only
   a walk — which may make it too easy until R3's scavengers restore the price. If it reads as
   free, that is worth knowing before scavengers are built, not after.
