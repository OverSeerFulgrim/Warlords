### The villain splits: data object, direct control, and a camera that follows (rework R1, first task)

**The documented migration trigger fired.** `NecromancerToken` used to own his position outright, as an explicit exception to the token-is-a-pure-view convention, with the exception's own expiry condition written into the file: *split it the moment any other system needs to know where he is.* Three now do — the camera follows him, `Combat.exchange()` hits him, and the keyboard drives him. This pass is that split, and nothing more: no world map, no sorties, no escort behaviour. **The game is still the settlement build; it just has a Necromancer the player drives.**

#### The split itself

`scripts/villain/Necromancer.gd` (RefCounted) owns position, hp, Might, carry capacity and current carried load, an escort roster, and a class identity string. `NecromancerToken` is now a **pure view** — it reads `villain.position`, draws there, flips a sprite, and decides nothing. Exactly the `Laborer`/`WorkerToken` contract, for exactly the reason that one exists.

Two details that carry weight:

- **He extends `RefCounted` directly, not `Laborer`** — deliberately. Sharing the trip-loop base class would put him one `laborers()` change away from being labour. The exclusion stays structural: `WorkerSystem.laborers()` is the union of `workers` and `GameState.followers`, and he is in neither. (Re-verified after the split: labor pool size 1, `is_instance_of(villain, Laborer)` false, summary still reads "1 worker".)
- **`carry_capacity()` is Might**, the same rule as every other unit (FOUNDATION_SPEC §6). One rule, not two. `carried` is a `kind -> amount` Dictionary rather than a Laborer's single kind/amount pair, because a sortie brings back a mixed load and a worker trip is one resource by construction. Nothing banks it yet — that's R2's deposit-at-the-lair step.

#### Per-villain state is the whole point (rework §11)

**None of this is in `GameState` or any other autoload, and nothing looks him up.** `Main` holds a reference to one instance; every consumer takes him as a field — `CombatSystem.villain`, `VillainController.villain`, `NecromancerToken.villain`. `CombatSystem`'s old `necromancer: Node2D` (which read the *token's* position) is now `villain: Necromancer` reading the data object, which also closes the same view-is-a-frame-stale hole `_closest_token_hit` was fixed for.

If a future pass catches itself writing `GameState.necromancer_hp` or a static `Necromancer.current`, that is the mistake this discipline exists to prevent. It is the entire present-day cost of keeping the Demonologist and multiplayer possible, and retrofitting it later is the expensive version.

#### Direct control is the keyboard, deliberately not click-to-move

Left-click already means three things arbitrated by mode (inspection, build/demolish placement, rally-point targeting) and right-drag means camera pan. Adding "walk here" as a fourth meaning for a mouse button would make every click first ask *which mode am I in* before it could ask *what did they click* — which is how an input layer rots. Hold-to-move on the keyboard is a separate channel: it can't collide with any click, it needs no mode, and it reads as direct control rather than as issuing an order (which matters, since ordering people about is the one thing the pillars rule out).

**There was a real conflict to resolve, and it's resolved as WASD = the man, arrows = the camera.** `GameCamera._process` used to pan on both WASD *and* the arrow keys; the WASD half is gone. With follow mode on the two read almost identically anyway — moving him moves the view — so the arrow keys are really "look away from him for a moment", and like a right-drag they drop follow.

- **`MOVE_SPEED_CELLS = 1.4`, flagged as a tunable.** Same cells-per-second convention as `walk_speed` (1.0 = one grid cell/sec, literally). Faster than a Skeleton Worker's 0.9 because he's the player and trudging is not a fantasy; slow enough that the settlement doesn't read as small.
- **Movement is polled (`Input.is_key_pressed`), not event-driven.** Hold-to-move is a *state*, and rebuilding it from key-down/key-up desyncs the first time the window loses focus mid-hold. The F key (snap back to follow) is the opposite — a discrete press, so it's in `_unhandled_input`.
- **Movement is suppressed while a `LineEdit` has focus.** The Economy tab's threshold `SpinBox`es are real text entry; without the guard, typing "30" into one walks the Necromancer across the map. (This bug already existed in the WASD *camera* pan — it was just less visible.)

#### Idle pacing survives, demoted

No movement input for 8 seconds and he resumes the old slow wander — within ~2 cells of **wherever he's standing**, not of the Throne, because he's a unit you park now rather than a fixture of the keep. Any input cancels it in the same frame, with no easing out and no finishing the current step. Both halves live in `Necromancer.step()` rather than being split between the object and its controller, because both write `position` and position has exactly one owner: the controller decides *what the player asked for*, the object decides *where he ends up*.

#### Camera follow, and the escape hatch

`VillainController` calls `GameCamera.center_on(villain.position)` each frame while following — that band arithmetic (between the top strip and the command bar) already exists and already survives zooming, so following him is one call per frame rather than a second camera implementation.

**The drop-out needed a new flag, and the reason is worth keeping.** `player_has_moved_camera` is set by pan *and* zoom, and zooming in on the man you're following must not stop following him. So `GameCamera.manual_pan_ticks` counts manual pans only (right-drag or arrow key); the controller drops follow when the count changes. Comparing a counter rather than reading a boolean also means re-engaging follow doesn't have to reach in and clear someone else's flag. **F snaps back and re-engages**, and there's a button in his panel doing the same thing — the key is the fast path, the button is how you learn the key exists. State is shown under the HUD badge (bright "Following [F]" / dim "Free camera").

One consequence: `Main._on_viewport_resized` now re-syncs the camera insets **unconditionally** rather than only while the player hasn't panned. The follow camera calls `center_on` every frame regardless, so stale insets would mis-frame him for the rest of the session.

#### He is killable

`Necromancer` implements the whole Combatant contract (`combat_name`/`combat_might`/`max_hp`/`hp`/`take_damage`/`is_alive`/`hp_fraction`), so `Combat.exchange()` works on him with **no special casing anywhere**. `max_hp` is computed from Might, never stored, and it reuses `Laborer.HP_BASE`/`HP_PER_MIGHT` rather than restating the formula — there is exactly one hp formula in the project. Might 6 → 20 hp, a first guess flagged as the number to move when rework §15's "Necromancer combat stats" gets answered.

**Death is emitted from `take_damage()`, not from a policy layer.** `Combat.exchange()` doesn't know who it's hitting, so a run-ending event that only fired when `CombatSystem` happened to be the caller would be a trap for every later damage source (traps, the crusade, a rival villain). `EventBus.villain_died(villain, cause)` carries the villain object rather than assuming there's one of him, and fires once — `_death_announced` guards it, because `exchange()` will happily land another swing on a corpse in the same frame. **Nothing ends the run:** Main logs "THE NECROMANCER HAS FALLEN — the run would end here" and play continues. The run lifecycle is R4 and building half of it now would mean unpicking it then.

The lair aura is now `CombatSystem.LAIR_AURA_PROTECTS_VILLAIN` — see combat consequence rule 4 above for what flipping it off does and doesn't do. `Wolf.get_inspect_data()` reads the flag too, so the panel stops promising protection the moment it's switched off.

#### Inspection

His entry shows hp (current/max, colour-coded), Might, carry (current/capacity), escort count, and follow state. `NecromancerToken.get_inspect_data()` **delegates** to the data object rather than duplicating it — the one row it adds itself is camera follow, deliberately, because where the camera is pointing is a property of the view and not of the man. Put it on the data object and the next thing on it is a scroll offset. Actions (Command Undead, the follow toggle) stay in `Main`, unchanged split.

#### Verification

A headless scene harness, 49 assertions, all passing: the split (token mirrors the object, owns nothing, same instance), absence from `laborers()`/`all_units()` and the workforce summary, 1s of held input covering exactly 1.4 cells with diagonals no faster, the token catching up within one frame, follow tracking / dropping on a simulated manual pan / staying put once dropped / re-engaging on snap / surviving a zoom, pacing staying quiet at 7s and resuming by 8s within 2 cells then cancelling instantly on input, the Combatant contract, `max_hp` tracking a changed Might, `Combat.exchange(wolf, villain)` damaging both sides, death at 0 hp firing exactly once and not re-firing on a corpse, the lair aura still hiding a worker standing in his shadow, and every inspection row present via delegation.

Two harness notes for next time:

- **A `-s` SceneTree script compiles before the autoloads are registered**, so every class touching `EventBus` or `RaceCatalog` fails with "Identifier not found". Run a harness as a **scene** (`godot --headless --path . res://tools/whatever.tscn`) instead. If you do need `-s`, autoloads are reachable as `root.get_node("EventBus")`.
- **`root` is busy setting up children during your `_ready`** — await one frame before `add_child`ing an instantiated `Main.tscn`, or the call fails outright.
- The compiler statically rejects `villain is Laborer` ("Expression is of type Necromancer so it can't be of type Laborer"), which is itself the proof the assertion wanted. Route through an `Object` local and `is_instance_of()` if you want it as a runtime check.

**Not verified here, and it needs a human:** `Input.is_key_pressed` polling and `_unhandled_input` are both unreachable from godot-mcp's simulated input (see "Known constraint"). Actually holding W/A/S/D, panning with the arrows, and pressing F have to be checked with a real keyboard in the real window.

