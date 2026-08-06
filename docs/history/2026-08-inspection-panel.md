### One panel for everything clickable (`InspectionPanel`, Core Feel Prompt B)

Click behaviour used to be three separate panels grown one at a time — the Keep menu, the Barracks roster, the Necromancer card — each with its own toggle function, its own populate function, and its own idea of what a header looks like. Meanwhile most of the map wasn't clickable at all: a tree, a grave, a funded house and a Bone Pile were all scenery. Now **everything on the map is inspectable through one panel**.

#### The Inspectable contract

Anything clickable implements **`get_inspect_data() -> Dictionary`**. That is the entire interface. GDScript has no `interface` keyword, so it's duck-typed — `InspectionPanel.inspect()` checks `has_method()` and refuses with a warning rather than crashing.

```
{ "title", "subtitle", "sprite", "description", "details": [ {label, value, muted?, color?}, ... ] }
```

A `details` row with an empty `label` renders full-width — that's what the flavor asides and "nothing left here" notes use.

**A registry was the other option and was rejected.** It would need every clickable to register and deregister (resource nodes are created and freed at runtime — deer especially), and the registry would end up holding exactly the per-type knowledge this pattern exists to distribute. Asking the object is cheaper and can't go stale.

**There is no `match` on type in `InspectionPanel` or in `Main.gd`.** `ResourceNode` knows about regrowth and depletion, `Building` knows about tick rates and residents, `Follower` knows about morale and housing, `NecromancerToken` knows he isn't a laborer. Adding a new inspectable type means writing one method on it and nothing else.

Characters are the one place with shared scaffolding: `Laborer.get_inspect_data()` assembles the whole character block (activity, four stats, three labor skills, carry, walk speed) and subclasses fill four small hooks — `inspect_race_id/category/social_stats/extra_rows` plus subtitle and description. A skeleton and a gray dwarf want the same *shape*; only the contents differ. Note `Worker.inspect_social_stats()` reads Guile/Influence/Loyalty straight off the race row rather than storing fields — a Worker has no use for them, and a skeleton's are constants anyway.

#### Actions are the deliberate exception

The Keep's Recruit Worker / Surrender and the Barracks' Fund House buttons call *Main's* handlers, so they can't live on `Building` without handing every building a reference to Main. `inspect()` takes an optional `extra: Callable` that Main supplies and which is handed the panel's action VBox to fill (`_build_keep_actions` / `_build_barracks_actions` / `_build_necromancer_actions`). **Data comes from the object; actions come from whoever owns the handlers.** That split is why `InspectionPanel` has no idea what a Barracks is.

#### Click pick order

**characters > resource nodes > buildings > ground**, in `Main._inspect_at()`. A worker standing on a tree inspects as the worker; the Necromancer pacing on the Throne inspects as the Necromancer; a deer wandering over the Bone Pile inspects as the deer. Clicking bare ground closes the panel — that counts as a deliberate action, so the click is still consumed.

Nodes sit above buildings because they're mostly off-grid (forest, deposit, graves) and a deer roams anywhere, so an overlap means the node is the thing on top.

**Placement and demolish modes keep first refusal on every click**, unchanged: `_unhandled_input` still returns early for both before inspection is ever reached, and entering either mode closes the panel. Esc cancels the *mode* while one is armed, and only closes the inspector when neither is.

Depleted nodes stay clickable on purpose. A stump and a dug-up grave are exactly what a player clicks to ask "is this finished?", and answering that is half the point.

#### Live refresh by polling, not by signal

`InspectionPanel` keeps the *source object*, not the Dictionary it produced, so `refresh()` re-asks it. `Main._process` polls every `INSPECTOR_REFRESH_INTERVAL` (0.4s) while the panel is open. A worker's Activity row and a Barracks' resident count both change while you're looking at them, and most of the signals that would drive them (activity especially) fire every frame anyway — same reasoning as the priority rows being polled rather than signalled. The handful of genuinely discrete moments (funding a house, a recruit joining, a meal served) call `refresh()` directly so the panel agrees with the button the player just pressed.

`refresh()` closes itself if the source has been freed — an inspected deer really can be hunted, and `ResourceNode` is a Node2D that gets `queue_free()`d. `Follower` is RefCounted so `is_instance_valid()` stays true after they desert; Main closes the panel explicitly in the `recruit_departed` handler for that case, and in `building_removed` for demolition (where `queue_free()` is deferred and the guard wouldn't notice until next frame).

#### One real bug this pass caught

**`_closest_token_hit()` measured the *token's* position, not the Laborer's.** The token is a pure view that copies `laborer.position` in `_process`, so it's always one frame stale — and a follower sent away on a bounty has a token that stopped mirroring entirely and glided off to the gate, meaning a click at the gate would select someone who isn't there while the real unit was unclickable. It now measures the Dictionary key (which *is* the simulation object) and skips hidden tokens. This is the same view-vs-simulation drift the architecture conventions warn about, surviving in the input layer after the rendering layer had been fixed twice.

#### Data added

`data/buildings.json` gained a `description` per entry (the one-line "what is this for"), for the same reason costs and prerequisites live there: adding a building should never mean a new branch in a description function. `Building.house_owner_name` is set by `fund_house()` alongside `display_name`, so a house can name its resident without searching the roster for whoever lives at that cell. `ResourceNode` now keeps its sprite *paths* alongside the loaded textures — a `Texture2D` has no route back to its `res://` source, and the panel shows whichever art is currently on screen (stump, not tree).

Tree nodes are `Pine Tree` / `Pine Stump` now rather than `Tree` / `Stump`, matching the commissioned art.

