# Necromancer Reference — Undead Empire

Reference page for the villain class before we touch code. Pulled from the current `data/buildings.json`, `GameState.gd`, `Main.gd`, `BountyBoard.gd`, `EventSystem.gd`, and `MissionSystem.gd`, plus a scan of the `Characters/Character - 128 x 128/` portrait pack (40 portraits total) for a face to put on the player and the worker.

No code has been changed yet — this is the "what do we actually have" snapshot to plan from.

---

## 1. The Necromancer (player character)

There's currently **no sprite assigned to the player at all.** The player is represented only abstractly, through the Throne of Bones (main building, 40 hp) and the stat readout at the top of the screen. There's no portrait, no on-screen avatar, nothing clickable that says "this is you."

I scanned all 40 portraits in `Characters/Character - 128 x 128/` (the same pack `SPECIES_SPRITES` already draws Skeleton/Ghoul/Wraith/Orc/Goblin from) for something that reads as a necromancer. Three real candidates:

| Candidate | File | Look |
|---|---|---|
| **Top pick** | `character_029.png` | Black hood, pale/gaunt face, dark robe with blood-red trim. Reads as macabre/villainous without needing recoloring. |
| Alt 1 | `character_012.png` | Wide-brimmed black witch/wizard hat, dark robe, pale skin, yellow eyes. Reads more "classic spellcaster." |
| Alt 2 | `character_006.png` | Grey hooded cloak, plain face. Reads more "cultist/rogue" — moodier but less obviously magical. |

My recommendation is **character_029** — it's the most distinct from the follower portraits already in use (no overlap with Skeleton/Ghoul/Wraith/Orc/Goblin) and has the strongest "this is the villain" read of the three at a glance. Open all three side by side in the `Characters/Character - 128 x 128/` folder before deciding — small portraits, worth eyeballing.

**Open question for you:** once we pick a portrait, where does it actually go? A few options worth a real design conversation before I touch code:
- Just a static portrait in the top UI bar (cheapest, matches the debug-UI aesthetic)
- Clickable, opens a "Necromancer" panel (spells/abilities down the road?)
- An actual on-screen token near the Throne of Bones, like Followers/Workers have

---

## 2. The generic Worker ("Zombie Laborer")

Already wired up — no gap here, just documenting what exists. Per `CLAUDE.md` and `Main.gd`:

- Workers reuse the **Skeleton follower portrait** (`character_024.png`) for both the roster-row icon and the on-map `WorkerToken`, scaled down to 32px (vs. Followers' full size).
- This is deliberate: Workers are meant to read as anonymous/interchangeable labor, not individuals, so giving them Skeleton's face rather than a unique "worker" sprite was a conscious call, not an oversight.
- Named `Zombie Laborer #1`, `#2`, etc. — the *name* says zombie, the *sprite* says skeleton. Slightly mismatched if you look closely.

None of the 40 portraits in the pack read distinctly as "shambling zombie" (grey-green skin, stitched, decayed) — the pack just doesn't have that archetype. If you want the name and the face to match, that'd mean either recoloring/editing an existing portrait or sourcing new art later — flagged in `CLAUDE.md`'s "Next milestones" as unique undead art, not urgent.

---

## 3. Buildings — what each one actually does

From `data/buildings.json` + the action-button code in `Main.gd`. Four categories: **resource** (ticks a resource over time), **housing** (hard-gates recruiting a species), **functional** (unlocks an action button), **main** (the Throne, not buildable).

### Resource buildings

| Building | Cost | Produces | Rate | Power |
|---|---|---|---|---|
| **Bone Pile** | 5 Bones | +2 Bones | every 5s | 3 |
| **Dark Altar** | 8 Dark Essence | +1 Dark Essence | every 6s | 6 |

Dark Altar is self-refining — it costs the resource it produces, so building one is a "spend 8 now to slowly earn it back plus more" bet, not a way to bootstrap Dark Essence from zero.

### Housing buildings

Each one hard-gates recruiting its species — `EventSystem._recruit()` refuses that species until the matching building exists. All cost **6 Wood, 4 Stone**, all contribute **4 Power**. They don't produce resources or have a population cap yet — built once, that species is unlocked, full stop.

| Building | Unlocks species |
|---|---|
| Bone Crypt | Skeleton |
| Charnel Pit | Ghoul |
| Haunted Spire | Wraith |
| War Camp | Orc |
| Burrow Warren | Goblin |

(Dark Elf exists as a species in the design space but has no housing entry — intentionally ungated per `CLAUDE.md`, so it can't accidentally soft-lock.)

### Functional buildings

| Building | Cost | Power | Requires | Unlocks |
|---|---|---|---|---|
| **Workshop** | 10 Wood, 10 Stone | 5 | — | Nothing itself — it's the tech-gate for Blacksmith/Barracks |
| **Blacksmith** | 6 Wood, 12 Stone | 7 | Workshop | "Forge Equipment" action button |
| **Barracks** | 12 Wood, 6 Stone | 7 | Workshop | "Train Followers" action button |

**Forge Equipment** (Blacksmith): costs 5 Dark Essence, picks one random idle Follower, gives them +1 to a random stat (Might/Guile/Influence, picked randomly).

**Train Followers** (Barracks): costs 5 Bones, gives **every** idle Follower +1 Might.

### Main building

**Throne of Bones** — seeded at game start, not buildable, not removable, 40/40 hp, contributes 10 Power. This is what the Crusade climax actually attacks; losing it (hp ≤ 0) is the fail state, separate from the Power-threshold win condition.

---

## 4. What Dark Essence is actually used for

Right now, four things touch it:

1. **Dark Altar** — costs 8 to build, produces 1 every 6s once built (see above — self-refining, not a source from nothing).
2. **Forge Equipment** (Blacksmith action) — costs 5, grants a random idle Follower +1 to a random stat.
3. **Bounties** (Bounty Board) — `BountyBoard._resolve_bounty()` pays every successful bounty's reward in Dark Essence, regardless of type. That means **both** bounty types feed the same currency: Harvest (5 reward, risk 2, per `Bounty.harvest_bounty()`) and Reanimation (10 reward, risk 5, per `Bounty.reanimation_bounty()`) — Reanimation is just the higher-risk/higher-reward version, not a different resource. This is currently the main way to earn Dark Essence besides the Altar.
4. **Random events / missions** — a handful of entries in `events.json`/`missions.json` can add or spend it as a choice outcome or mission reward (exact entries are data, not hardcoded — worth a look at those JSON files directly if you want the full list of which specific events touch it).

Starting amount is 20 (`GameState.dark_essence`).

Big picture: Dark Essence currently reads as "the ritual currency that gates upgrading your Followers and building the one arcane structure," separate from Wood/Stone/Bones' "mundane construction and worker-gathered" role. That split is intentional per `CLAUDE.md` and seems to be holding up fine — the two economies don't bleed into each other anywhere in the code I found.

---

## 5. Notes / gaps worth flagging before we plan changes

- No player avatar exists at all yet (section 1) — that's a real gap, not just a placeholder.
- Worker name ("Zombie") and Worker face (Skeleton portrait) don't match (section 2).
- Housing is "unlocked or not," no population caps — already flagged in `CLAUDE.md`'s Next Milestones, repeating here since it's directly part of "does gathering/economy feel right."
- Dark Altar's self-refining cost might feel bad in practice (spend 8 to make a building whose whole job is to slowly make more of the same 8) — worth playtesting specifically before assuming it's fine.
