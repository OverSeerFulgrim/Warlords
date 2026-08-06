### HUD layering, and four playtest bugs worth remembering

A batch of playtest reports that all turned out to be UI plumbing rather than game logic. Recorded because three of them share one root cause that will recur.

**Sibling `Control` order is z-order *and* input order, last on top.** `_build_bottom_shell` used to be the final child of `hud_root`, which put the command bar over both floating panels. The consequences looked like completely unrelated bugs:

- A recruit offer's choice buttons hang below the screen's centre line, landed under the command bar, got tinted by its translucent background (so they read as **disabled**) and had their clicks eaten. A full-Barracks offer was literally unanswerable.
- `PRESET_CENTER` made it worse: it anchors a Control's **top-left corner** to the screen centre, so the panel grows down-right from there rather than being centred on it. The event panel is `PRESET_TOP_LEFT` + `_position_event_panel()` now, which centres it in the *visible band* (between the top strip and the command bar) and clamps it so it can never cover the bar.
- The inspection panel had the same exposure. It also moved from x=360 to x=60 so a centred event offer can't sit on top of the Barracks panel's **Fund house** button — the one control you need to reach to answer a full-Barracks offer.

**A recruit offer is a live decision, not a snapshot.** Its choices used to be frozen at the instant it fired, so funding a house while the offer was open freed a slot that did nothing — you stayed stuck with the two turn-away variants until the offer expired. `EventSystem.refresh_recruit_offer()` re-evaluates against current occupancy and rewrites the description and choices in place; `Main._refresh_open_offer()` drives it off the same 0.4s HUD poll as the inspector. Works both ways — a slot filled by someone else takes the accept option back. Polled rather than signalled because occupancy moves for four unrelated reasons and the refresh is a no-op unless the answer actually changed.

**The inspection panel now scrolls.** A full Barracks roster measured **706px** — five residents each with a wrapped stat block and a Fund house button — which ran off a 760px window and under the command bar. `InspectionPanel` is `PanelContainer > ScrollContainer > VBox` with `max_body_height` set by Main from the real band. Note the cap covers the **whole panel including its own stylebox padding**: capping just the body still overhung by 8px, which was enough to steal clicks from the bottom button.

**The History log was a letterbox.** Fixed at 56px with dead space under it, because neither `command_area` nor `cmd_history` had `SIZE_EXPAND_FILL` vertically, so the tab shrank to its content minimum. All three now expand; the log gets 166px of the 250px band and grows with the window.

Two testing notes from this round, both of which produced false results:

- **Headless Godot runs at a 64×64 viewport.** Every geometry assertion is meaningless until you `get_tree().root.size = Vector2i(1400, 760)` and wait a few frames. The bottom bar otherwise computes to y = −186.
- **GDScript lambdas capture locals by value.** `var seen := false` + `sig.connect(func(): seen = true)` writes to the closure's own copy and the outer `seen` never changes. Capture through an Array (or a member) instead.

