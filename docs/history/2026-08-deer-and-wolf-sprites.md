### The deer sprite

**No vendored art pack contains a quadruped.** Both Kenney roguelike sheets were checked tile by tile before concluding this: `art/roguelikeSheet_transparent.png` is terrain, buildings, furniture, fences, market stalls and UI bars; `art/roguelikeChar_transparent.png` is paper-doll parts (heads, torsos, hair, shields, weapons). There is a roast bird and a fish, but those are food *items* — which was exactly the problem, since the deer had been standing in as the raw-meat icon and read as a floating steak rather than something you hunt.

So `art/creature_deer.png` is generated: a 32×32 side-view silhouette plotted with the `Image` API by **`tools/make_deer_sprite.gd`**, run with `godot --headless --path . -s res://tools/make_deer_sprite.gd`. The generator is kept in the repo rather than run-and-deleted so the placeholder stays tweakable, and it carries the shape/colour reasoning in its comments (including two rejected attempts at a pale belly stripe that read as a saddle blanket). It is **still a placeholder** — it just needs to read as a living animal. Nothing depends on the script at runtime, only on its output PNG.

One gotcha it hit: **`_set` is an `Object` virtual** (`_set(StringName, Variant) -> bool`). Naming a pixel-plotting helper `_set` fails to parse with "function signature doesn't match the parent". It's called `_px` now.

**`art/creature_wolf.png` is generated the same way** (`tools/make_wolf_sprite.gd`), and had one job the deer's didn't: at 34px on a night-tinted map it must never be mistaken for the deer, because one is food and the other eats your workers. Three deliberate contrasts carry that — cold grey-blue against warm brown (and the night tint is itself blue-shifted, so the two *separate* at night rather than converging), a low flat back against the deer's tall short one, and a head carried *below* the shoulder line with no antlers, which is the universal read for a stalking predator. Also still a placeholder.

