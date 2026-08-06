### Stage 3: the Barracks, and recruits who are actually individuals

Turns the Barracks into real recruit intake and replaces template-based recruitment with generation off the race roster. This is the pass that made GAME_OUTLINE Stage 3 playable.

#### The Barracks (`buildings.json`, `SettlementGrid`)

`category: "housing_intake"` — a category of exactly one, deliberately **not** `"housing"` (that category means the old per-species hard gate, which is locked). Cost 8 wood / 6 stone, `capacity: 5`, `power_value: 4`, `"unique": true`.

- **`"unique"` is a new catalog flag**, filtered in `BuildingCatalog.buildable_ids()`: once one is placed it leaves the build menu forever. FOUNDATION_SPEC §9's "Only one can ever exist."
- **No `requires`.** It used to be gated behind the Workshop. GAME_OUTLINE Stage 2 puts the Barracks *first* and the Workshop tech line after, so the prerequisite was inverting the intended build order — with 8 wood / 6 stone against a `wood=8 stone=5` start it's now reachable after roughly one gathering trip, which is the Stage-1→2 gate doing its job.
- **Clicking it opens the Barracks panel** (`Main._toggle_barracks_panel`), same click-the-building-on-the-map pattern as the Keep menu. It lists each resident's race, category, four stats and three labor skills side by side, because that's the information the fund-a-house decision will need.
- **The Upgrade button is a real, visible, `disabled` `Button` labelled "Upgrade — Locked"**, with no handler and no cost shown. Deliberately a Button rather than a greyed Label like the other roadmap placeholders: FOUNDATION_SPEC §9 asks specifically for a *button* that is present and locked, because the promise being made is "there will be a button here".

`SettlementGrid` gained `get_barracks()` / `barracks_capacity()` / `barracks_residents()` / `barracks_free_slots()`. **`barracks_residents()` currently returns the whole roster size** — exact only because fund-a-house doesn't exist yet, so nobody has ever moved out. When that lands (GAME_OUTLINE gap #4) it has to count only followers still resident.

#### The Barracks is the event gate

`EventSystem.EVENTS_ENABLED`, a hardcoded `false` that existed only to stop events drowning out other testing, is **gone**. `events_enabled()` now returns "is there a Barracks?" — GAME_OUTLINE Stage 2 ends with "Barracks built → recruitment-event timer turns on", so there's a real in-fiction reason for silence at the start.

Note it gates on the Barracks *existing*, not on a free slot. **A full Barracks still gets offers** — they just arrive with only turn-away choices (and the description says why). Fizzling the event entirely would make a full Barracks indistinguishable from a broken timer. The two turn-away variants differ in *how* you refuse, which is the hook departure-memory (gap #6) will hang off.

#### `RecruitGenerator` — recruits rolled from `races.json`

Replaces the `data/followers.json` template lookup (seven hand-written archetypes with flat min/max ranges). Owned as one long-lived instance by `EventSystem`, not a static utility, because the first-run guarantee has to remember how many offers it has made.

- **Which race** — roulette-wheel weighted by the race's rarity band. A rarity string missing from the weight table gets weight 0 rather than a silent default, so a typo in `races.json` shows up as "this race never appears" instead of quietly skewing the distribution.
- **Power attracts power** — the weights come from a **table in `data/recruitment.json`**, not branches: `[{min_power: 0, 60/30/10}, {min_power: 25, 50/35/15}, {min_power: 40, 40/40/20}]`. `rarity_weights_for_power()` walks it and takes the last tier whose `min_power` has been reached, so tiers must stay sorted ascending and adding a fourth is a JSON edit.
- **Stat rolls** — `clamp(baseline + d3 − d3, 1, 10)` per stat and per labor skill (FOUNDATION_SPEC §3). Centre-weighted, so most recruits sit near baseline and ±2 is rare. Walk speed and food/meal stay racial constants with no variance.
- **Exceptional recruits** — 5% chance of +1 to the category-defining stat, `Follower.is_exceptional` set. `"best_labor"` (the Economy entry) resolves *per individual* to whichever labor skill they actually rolled highest, because an Economy race's defining trait is being good at its own speciality and that differs by race. `"none"` (Versatile, Labor) never rolls exceptional — Human Outcast is the flat-5 jack-of-all-trades by definition and Skeleton Workers are interchangeable by design. Marked with a ★ in the roster, the Barracks panel, the info panel, and on the map token.
- **First-run guarantee** — the first three offers are dealt from `first_run_categories` (Warrior, Economy, Research) in order, still rarity-weighted *within* the category. It counts **offers, not acceptances**: turning the first orc away still burns the warrior slot, because you were shown the category, which is what the guarantee promises. Versatile is deliberately absent from the list, per RACES.md.

`data/followers.json` and `EventSystem._recruit()` still exist for the events.json entries that reference template ids, but those are off the timer — the timer fires recruit offers only for the foundation build. **The old per-species housing hard gate is deleted**; it checked buildings that the foundation reset made unbuildable, which silently made every gated species impossible to recruit (this file flagged it as a blocker two passes ago). Barracks capacity is the gate now, for both paths.

#### `Laborer` — the new base class, and why Worker and Follower both extend it

This is the structural change worth understanding before touching any of it.

Recruits gather. A settled Gray Dwarf brings Mining 9 against a skeleton's 3, so the same trip yields stone roughly three times faster, and their higher Might means a bigger load on top — that's most of the reason to recruit one at all. But Worker and Follower are still deliberately different types, and the "don't merge them" call has been reaffirmed twice. So the **labor half** — Might/walk speed/the three labor skills, plus the whole `TripStage` state machine, `position`, carry state and `abandon_trip()` — is factored into `scripts/settlement/Laborer.gd`, and both extend it.

The boundary to hold: **`Laborer` is the job, not the person.** Traits, Loyalty, race identity, bounty appetite, `is_busy` all stay on Follower; serial-number naming stays on Worker; neither belongs in the base. Two hooks make the difference work:

- `can_labor()` — Worker always true (labor is all it is, there is nothing to pull it away). Follower returns `not is_busy`, so a follower on a bounty leaves the pool, and `WorkerSystem.laborers()` calls `abandon_trip()` on anyone pulled away mid-trip rather than leaving a phantom claim on a resource node.
- `display_name()` — Worker returns `worker_name`, Follower returns `follower_name`. They stayed separate fields on purpose: "Skeleton Worker #3" is a serial number and "Thokk" is a person.

`WorkerSystem._process` now iterates `laborers()` (workers + non-busy followers) rather than `workers`, and every trip-loop function is typed `Laborer` instead of `Worker`. `FollowerToken` became a pure position-mirroring view exactly like `WorkerToken` — it used to run its own Tween idle wander, which was fine while followers only stood around, but their position is real simulation state now. Bounty/mission `send_away()`/`return_home()` survive as visibility toggles, since those genuinely take a follower off the map.

