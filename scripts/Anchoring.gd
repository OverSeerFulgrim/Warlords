class_name Anchoring
extends RefCounted
## Where a sprite sits relative to the thing it represents.
##
## **Why this exists.** Every token in the project used `centered = true`, which
## puts a unit's *middle* on its position. That was invisible at 32px and
## obvious the moment the art grew: at 68px the Necromancer's midriff was on
## the ground and his feet were half a tile below it. A unit's position is where
## it **stands**, so the sprite hangs above it.
##
## The rule is one line, but it is the same subtle line in five places (four
## unit tokens plus resource nodes), and getting it wrong looks like a depth bug
## rather than an anchoring bug. So it lives here once.
##
## **`Sprite2D.offset` is in texture pixels and is applied before `scale`**,
## which is exactly what makes this work at any target size: set it once from
## the texture and the anchor survives every rescale.

## Click radius as a fraction of a unit's drawn width. Every token derives its
## `hit_radius()` from this times its own target size, so the hit area and the
## art can never drift apart -- `Main._closest_token_hit` used to be handed a
## hardcoded 16.0 for workers and 20.0 for followers, which silently became
## wrong the moment the art grew.
##
## **0.45, not 0.6.** At 0.6 the Necromancer's 68px sprite claimed a 41px radius
## -- an 82px circle on a 64px tile — and standing on the Throne made the Throne
## unclickable from anywhere in its own cell, taking the Keep menu with it. 0.45
## still leaves every unit a larger target than it had before this pass, while
## leaving the corners of the tile underneath reachable. The pick order
## (characters above buildings) is unchanged and deliberate; this is about how
## much of the tile a character is allowed to claim.
const HIT_RADIUS_FRACTION: float = 0.45

## The sprite hangs above its node position: its bottom edge lands on the node's
## origin. Use for anything that stands on the ground -- units, trees, deer.
##
## **Known residual:** the commissioned 128px tokens carry 6-14px of transparent
## padding below the figure, so this lands the *texture box* on the ground and
## the figure floats ~4-5px above it at these sizes. Trimming that padding is an
## art fix (and exactly what the deferred sheet normalizer in
## MODULAR_CHARACTER_ANIMATION_REVIEW.md §8 does for the animation sheets); it
## is deliberately not worked around here with a per-texture alpha scan.
static func foot(sprite: Sprite2D) -> void:
	if sprite == null or sprite.texture == null:
		return
	sprite.centered = true
	sprite.offset = Vector2(0.0, -sprite.texture.get_size().y * 0.5)

## The sprite stands on the bottom-centre of a `cell_size` square whose top-left
## is the node's origin -- the grid convention `SettlementGrid.place_building`
## uses. Buildings grow **upward and outward from their footprint** rather than
## down-and-right over their neighbours, which is what `centered = false` used
## to do the moment a sprite was allowed past one tile.
static func cell_base(sprite: Sprite2D, cell_size: float) -> void:
	if sprite == null or sprite.texture == null:
		return
	sprite.centered = true
	sprite.offset = Vector2(0.0, -sprite.texture.get_size().y * 0.5)
	sprite.position = Vector2(cell_size * 0.5, cell_size)
