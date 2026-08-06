### Camera framing and the Necromancer avatar (Core Feel pass, Prompt A)

#### The camera starts on the Throne

It used to centre on the *grid's* midpoint. The Throne sits at cell (0,0) — a corner of the map, not its middle — so the player's own keep started tucked into the top-left with empty ground filling the screen.

`GameCamera.center_on()` now frames a world point in the **visible map band**, not the raw window. A `Camera2D` draws its own `position` at the window centre, so centring on the band between the top resource strip and the bottom command bar means deliberately offsetting away from that:

```
screen_y = window_h/2 + (world_y - camera_y) * zoom
```

Solve for the camera position that puts the target at the band's centre, and divide the screen-space inset by `zoom` to convert it to world units — which is what makes the framing survive zooming. `Main._sync_camera_insets()` feeds it the real panel heights (`top_panel.size.y` and `BOTTOM_BAR_HEIGHT`).

Two timing details worth keeping:

- **Control sizes aren't final on the frame they're created**, so the first framing runs with a top inset of 0 and is a few pixels out. `_settle_initial_camera_framing()` re-runs it after two frames. It's deliberately *not* awaited by `_ready()` — it runs to its first `await`, lets `_ready` finish, then resumes.
- **Resize re-frames only while `camera.player_has_moved_camera` is false.** Any pan or zoom sets that flag. Snapping the view back to the Throne because someone dragged a window corner would be worse than a slightly-off centre.

Verified at 1400×760, 1024×600, 1920×1080 and 900×500: the Throne lands dead centre of the visible band every time (dx and dy both 0.0px).

#### The Necromancer walks his domain (`NecromancerToken.gd`)

The player now has an avatar on the map — a token that paces slowly within ~2 cells of the Throne so the settlement reads as having someone in charge of it, rather than being an unattended machine.

**He is not a `Laborer`, and the exclusion is structural rather than a flag.** `WorkerSystem.laborers()` is the union of `workers` and `GameState.followers`; he is in neither, so there is no path by which he can be handed a gathering trip or counted in the workforce summary. Keep it that way — if he ever needs to act on the world, give him his own system rather than slotting him into the labor pool. (Smoke-tested: labor pool size 1, `is Laborer` false, summary still reads "1 worker".)

**Where his position used to live — the documented exception, now closed.** It was on the node rather than a data object, the opposite of the convention above, on the grounds that nothing else read it. The section carried an explicit migration trigger: split it the moment any *other* system needed to know where he was. **That trigger fired and the split is done** — see "The villain splits" below. Everything from here to the end of this subsection describes the *pre-split* code and survives only as the reasoning trail.

Clicking him (or the HUD badge — two doors, one room) opens his entry in the shared `InspectionPanel` (see below), with a "Spells — coming soon" disabled button, the same visible-promise treatment as the Barracks Upgrade. His own bespoke panel is gone, as this section previously predicted it would be.

His art is the 128px HUD *portrait* scaled down to token size — a stand-in until ART_BRIEF's proper Necromancer sprite exists, same documented spirit as the generated deer.

