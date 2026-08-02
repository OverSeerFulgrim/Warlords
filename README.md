# Undead Empire Prototype — README

## What's here

A Godot 4.3 project implementing the Phase 1 slice of the villain-settlement-builder design doc: Undead Empire class, Frozen Wastes climate, Bounty Board, Reputation/Threat escalation, 15 random events, and a 4-mission party system. See `CLAUDE.md` in this folder for architecture notes, and the design doc (`villain_settlement_builder_design_doc.docx`, one folder up) for the full game concept.

## How to run it

1. Install [Godot 4.3 or later](https://godotengine.org/download) (free) — the standard build, not Godot 3.
2. Open Godot, choose **Import**, and select the `project.godot` file in this folder.
3. Once it opens in the editor, press **F5** (or the Play button) to run.
4. `Main.tscn` is already set as the main scene, so it should just run.

## First-run smoke test

Because I (Claude) built this in a sandboxed environment that couldn't download and run the actual Godot engine — the sandbox's network access doesn't reach Godot's binary releases — **none of this has been executed yet.** It's carefully hand-written, standard-pattern GDScript, but you're the first real test. Here's what to check, in order:

1. **Does it open without errors?** Check the Output panel at the bottom of the editor immediately after opening the project. Any red text there is a parse error — most likely a small typo, not a structural problem.
2. **Does it run (F5) without errors?** You should see a window with a stats line at the top (Dark Essence / Bones / Reputation / Threat / Power), a row of buttons, and a log panel.
3. **Click "Place Bone Pile."** A log line should appear confirming placement, and after ~5 seconds Bones should start ticking up.
4. **Click "Post Harvest Bounty."** Within a few seconds one of the three starting followers (Grix, Morra, or Vash) should accept it and, after ~8 seconds, resolve it — Dark Essence should go up (or Threat should tick up slightly on failure).
5. **Click "Dispatch Mission (auto-party)."** Should immediately resolve and log SUCCESS/COMPLICATED/FAILURE.
6. **Let it run for a while** (or repeatedly post bounties / trigger events) and watch Threat climb through its tiers — you should see log messages when it escalates, and eventually a "CRUSADE INCOMING" message with a 60-second timer, followed by either victory or defeat depending on your Power at that point.

If any step breaks, the error in the Output panel will point at a specific script and line — that's the fastest way back to me (or into your own fix) for a follow-up pass.

## What's actually implemented

- Settlement grid with 3 building types (Bone Pile, Dark Altar, Crypt) — placement, passive resource ticking, Power contribution
- Majesty-style Bounty Board — post a bounty, followers with matching traits decide whether to answer it, resolves with a risk-weighted success chance
- Reputation/Threat system with the three-tier escalation ladder from the design doc, culminating in a timed Crusade climax
- 15 random events across all four categories (hazard, visitor, moral-choice, opportunity) from the design doc's Section 8, wired to fire on a randomized timer with a simple choice UI
- 4 hand-picked-party missions (Smuggling Run, Robbery, Mass Grave Recovery, Court Infiltration) resolved via the Might/Guile/Influence/Loyalty stat-check system from Section 5's recommendation
- "Both" win condition wired end-to-end: survive the High-Threat Crusade **and** hit the Power threshold
- 13 placeholder sprites (buildings, followers, resource/UI icons, a frozen-ground tile) — see below

## What's deliberately stubbed for this pass

- **The UI is a debug UI, not a real one.** Built entirely in GDScript rather than laid out in the Godot editor, on purpose — see `CLAUDE.md` for why. Swap it for a proper `.tscn`-based UI once the loop is confirmed working.
- **Balancing is placeholder.** Numbers (resource yields, threat thresholds, mission difficulty, the Power-vs-30 crusade check) are rough guesses to prove the systems connect, not tuned for fun. Expect to need a real balancing pass once you're playing it.
- **No save/load.** Every run starts fresh from `_seed_starting_state()`.
- **Only Undead Empire / Frozen Wastes is implemented.** The other three villain classes and climates from the design doc are still just design-doc content, not code.

## Recently completed

- **Buildings and followers now render with real art.** Buildings use Kenney's Roguelike/RPG pack (`art/`). Followers get a portrait in the debug UI's roster row, sourced from the "Characters" asset pack in `Characters/Character - 128 x 128/` (added via the Godot Asset Library) — hand-picked per species by look (see the comment above `SPECIES_SPRITES` in `Main.gd` for which numbered portrait maps to which species). The earlier Kenney-recolor versions are still in `art/` as `follower_*_kenney.png` but are no longer used.
- **A "Buildings" asset pack also landed in the project** (`Buildings/` — castles, houses, towers, bridges in 4 team colors) from the same Asset Library import. Not currently wired up; its high-fantasy medieval look doesn't match the Bone Pile / Dark Altar / Crypt villain aesthetic as well as the Kenney set does, but it's there if you want a rival-kingdom or human-settlement visual later.
- **Recruitment is fully wired.** Events like "Orcs Seeking a Home" now instantiate a real `Follower` via `data/followers.json` (species, name pool, trait pool, stat ranges) instead of printing a stub. `EventSystem._recruit()` / `_recruit_chance()` handle it; `EventBus.follower_recruited` fires so the UI can log it and the roster row updates automatically.

## Placeholder art

I don't have an image-generation tool in this environment, so the 13 sprites in `art/` are procedurally generated flat-color icons (Python/PIL) — simple, readable shapes rather than real illustration, in line with the "bright, stylized, not grimdark" art direction from the design doc. They're meant to make the prototype legible while you're testing systems, not to represent final art quality.

When you're ready for something more visually interesting without commissioning custom art yet, [Kenney.nl](https://kenney.nl/assets) is the standard go-to for free, CC0-licensed game art — they have several fantasy/RPG-flavored 2D asset packs that would drop in cleanly here and read a lot better than these flat placeholders.

## Suggested next session

1. Run the smoke test above and fix whatever the Output panel flags.
2. Wire the placeholder sprites onto buildings/followers so it's visually legible.
3. Build the real `followers.json` + recruitment flow.
4. Start a balancing pass once it's playable end-to-end.
