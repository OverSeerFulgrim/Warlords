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

## The sprite hangs above its node position: the bottom edge of the **drawn
## content** lands on the node's origin, and the content's horizontal centre
## lands on its x. Use for anything that stands on the ground -- units, trees,
## deer.
##
## This used to anchor the *texture box*. The commissioned 128px tokens carry
## transparent padding below the figure, so a unit floated above the ground by
## whatever the artist happened to leave there -- and once sizes are derived
## from content height (see `content_rect`), that padding is scaled by a
## different factor per sprite, so the float is inconsistent as well as wrong.
## Anchoring the alpha box costs one cached scan and closes both.
static func foot(sprite: Sprite2D) -> void:
	if sprite == null or sprite.texture == null:
		return
	var tex_size: Vector2 = sprite.texture.get_size()
	var box: Rect2 = content_rect(sprite.texture)
	sprite.centered = true
	# `offset` is in texture pixels and applied before `scale`, so this survives
	# every rescale. Solve for the offset that maps the content's bottom-centre
	# to the sprite's local origin.
	sprite.offset = Vector2(
		tex_size.x * 0.5 - box.position.x - box.size.x * 0.5,
		tex_size.y * 0.5 - box.end.y,
	)

## The sprite stands on the bottom-centre of a `cell_size` square whose top-left
## is the node's origin -- the grid convention `SettlementGrid.place_building`
## uses. Buildings grow **upward and outward from their footprint** rather than
## down-and-right over their neighbours, which is what `centered = false` used
## to do the moment a sprite was allowed past one tile.
static func cell_base(sprite: Sprite2D, cell_size: float) -> void:
	if sprite == null or sprite.texture == null:
		return
	foot(sprite)
	sprite.position = Vector2(cell_size * 0.5, cell_size)

# ---------------- Content bounds: the canvas is not the thing ----------------
#
# **The bug this closes.** Every scale site in the project used to divide a
# target size by the *texture* width. But each sprite was drawn to fill its own
# frame to a different degree -- content spans 56%-100% of the canvas depending
# on the asset -- so the same target number produced wildly different real
# sizes. A pine tree asked for 76px drew 43px of actual tree; a grave asked for
# 50px drew 48px. The numbers in the size tables were not describing anything.
#
# The fix is to measure the **alpha bounding box** and scale that instead, which
# is what `scale_for_content_height` does. One rule everywhere: a size target is
# the height of the thing drawn, in world pixels.

## Alpha bounding boxes, keyed by `Texture2D.resource_path`. A 128x128 scan is
## 16k pixels -- trivial once per texture, wasteful every frame, and every
## consumer here re-derives its scale on depletion swaps and respawns.
##
## Keyed by path rather than by object so the two `load()` calls a tree and a
## stump make from different `ResourceNode`s share one entry. Textures with no
## resource path (generated at runtime) are measured but not cached, since
## there is no stable key for them.
static var _content_cache: Dictionary = {}

## The alpha bounding box of `tex`, in texture pixels. Falls back to the full
## texture rect for anything that can't be scanned (a fully transparent image, a
## format that won't decompress), which reproduces the old canvas-based
## behaviour rather than collapsing the sprite to nothing.
static func content_rect(tex: Texture2D) -> Rect2:
	if tex == null:
		return Rect2()
	var tex_size: Vector2 = tex.get_size()
	var full := Rect2(Vector2.ZERO, tex_size)
	var key: String = tex.resource_path
	if key != "" and _content_cache.has(key):
		return _content_cache[key]

	var rect: Rect2 = full
	var img: Image = tex.get_image()
	if img != null:
		# VRAM-compressed imports can't be read pixel-wise until decompressed.
		if not img.is_compressed() or img.decompress() == OK:
			var used: Rect2i = img.get_used_rect()
			if used.size.x > 0 and used.size.y > 0:
				rect = Rect2(used)
				# A mipmapped/compressed texture can report a different base size
				# than the Image it hands back; express the box in texture pixels
				# so callers can mix it with `get_size()` safely.
				var iw: float = float(img.get_width())
				var ih: float = float(img.get_height())
				if iw > 0.0 and ih > 0.0 and (iw != tex_size.x or ih != tex_size.y):
					var k := Vector2(tex_size.x / iw, tex_size.y / ih)
					rect = Rect2(rect.position * k, rect.size * k)

	if key != "":
		_content_cache[key] = rect
	return rect

## Uniform scale that draws `tex`'s content `target_height` world pixels tall.
## **This is the project's one sizing rule** -- every token, node and building
## derives its scale from here, so a size constant means the same thing
## everywhere it appears.
static func scale_for_content_height(tex: Texture2D, target_height: float) -> float:
	var h: float = content_rect(tex).size.y
	if h <= 0.0:
		return 1.0
	return target_height / h

## The width-budgeted variant, for the one family SPRITE_SPEC.md §3 measures by
## width instead: quadrupeds. A wolf is low and long, and its legibility comes
## from how much ground it covers, not how tall it stands.
static func scale_for_content_width(tex: Texture2D, target_width: float) -> float:
	var w: float = content_rect(tex).size.x
	if w <= 0.0:
		return 1.0
	return target_width / w

## The content's on-screen size in world pixels for an already-scaled sprite.
## Click targets read this rather than a size constant, for the same reason the
## scale sites do: a stone deposit asked for 45px of height covers 82px of
## ground, and a hit circle built from the height alone would miss most of it.
static func drawn_content_size(sprite: Sprite2D) -> Vector2:
	if sprite == null or sprite.texture == null:
		return Vector2.ZERO
	return content_rect(sprite.texture).size * sprite.scale.abs()
