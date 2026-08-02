extends SceneTree
## One-off art generator: writes art/creature_deer.png.
##
## Run with:  godot --headless --path . -s res://tools/make_deer_sprite.gd
##
## Why this exists: none of the art packs vendored into this project contain a
## quadruped. The Kenney roguelike sheets were checked tile by tile -- the
## environment sheet (`art/roguelikeSheet_transparent.png`) is terrain,
## buildings, furniture, fences and UI, and the character sheet
## (`art/roguelikeChar_transparent.png`) is paper-doll parts (heads, torsos,
## hair, shields, weapons). There is a roast bird and a fish, but those are
## food *items*, which is the exact problem we're trying to fix.
##
## So the deer is composed here instead: a hand-plotted 32x32 side-view
## silhouette. It is still a **placeholder** -- it just needs to read as a
## living animal rather than a floating steak, so that a worker walking out to
## hunt one is legible. Replace with real art whenever the art pass happens;
## nothing depends on this file at runtime, only on its output PNG.
##
## Kept in the repo rather than run-and-deleted so the placeholder can be
## tweaked (colour, antler shape, size) without re-deriving the whole thing.

const OUT_PATH := "res://art/creature_deer.png"
const SIZE := 32

# Deer faces left. Colours picked to sit alongside the Kenney palette already
# in use -- warm mid-brown body, darker outline, cream underside/tail.
const COL_OUTLINE := Color8(74, 47, 24)
const COL_BODY := Color8(146, 96, 48)
const COL_LIGHT := Color8(226, 208, 180)
const COL_ANTLER := Color8(198, 176, 138)
const COL_EYE := Color8(20, 14, 10)

var img: Image

func _init() -> void:
	img = Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Two passes: every solid shape is stamped once oversized in the outline
	# colour, then again at true size in its fill colour. Cheap way to get a
	# consistent 1px dark keyline around the whole silhouette without tracing
	# edges by hand.
	_draw_body(true)
	_draw_body(false)

	_draw_antlers()
	_draw_details()

	var abs_path := ProjectSettings.globalize_path(OUT_PATH)
	var err := img.save_png(abs_path)
	print("save_png -> %s (err=%d)" % [abs_path, err])
	quit()

func _draw_body(outline: bool) -> void:
	var grow := 1 if outline else 0
	var body_col := COL_OUTLINE if outline else COL_BODY

	# Legs first so the body overlaps their tops. Front pair then rear pair;
	# the slight x-offset between the two legs of each pair reads as a walking
	# stance rather than a cardboard cut-out.
	for leg in [[11, 17, 2, 10], [15, 18, 2, 9], [21, 18, 2, 9], [25, 17, 2, 10]]:
		_rect(leg[0] - grow, leg[1] - grow, leg[2] + grow * 2, leg[3] + grow * 2, body_col)

	# Barrel of the body.
	_ellipse(18, 14, 8 + grow, 5 + grow, body_col)
	# Rump, sitting a touch higher than the shoulder.
	_ellipse(24, 13, 5 + grow, 4 + grow, body_col)
	# Neck: a wedge from the shoulder up to the head.
	_thick_line(13, 13, 8, 7, 3 + grow, body_col)
	# Head.
	_ellipse(7, 6, 4 + grow, 3 + grow, body_col)
	# Muzzle.
	_ellipse(3, 7, 2 + grow, 2 + grow, body_col)
	# Ear, tucked behind the antler bases.
	_ellipse(11, 4, 2 + grow, 1 + grow, body_col)

func _draw_antlers() -> void:
	# Two beams with a single tine each -- more than that turns to mush at
	# 32px. Both start *inside* the head silhouette (y=4, below its y=3 crown)
	# so they read as growing out of the skull rather than hovering above it.
	_line(6, 4, 5, 0, COL_ANTLER)
	_line(5, 1, 2, 1, COL_ANTLER)
	_line(9, 4, 10, 0, COL_ANTLER)
	_line(10, 1, 13, 1, COL_ANTLER)

func _draw_details() -> void:
	# Pale chest patch at the base of the neck. Two earlier attempts at a full
	# belly stripe both failed: at mid-height it read as a saddle blanket, and
	# at the belly line it read as a horizontal bar floating across the gap
	# between the fore and hind legs. A chest patch lands on solid body pixels
	# and still gives the two-tone break that stops the sprite being one brown
	# blob.
	_ellipse(12, 11, 3, 2, COL_LIGHT)
	# Tail.
	_ellipse(29, 11, 2, 2, COL_LIGHT)
	# Eye.
	_px(6, 5, COL_EYE)

# ---------------- Tiny raster helpers ----------------

func _px(x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < SIZE and y < SIZE:
		img.set_pixel(x, y, c)

func _rect(x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_px(xx, yy, c)

func _ellipse(cx: int, cy: int, rx: int, ry: int, c: Color) -> void:
	for yy in range(cy - ry, cy + ry + 1):
		for xx in range(cx - rx, cx + rx + 1):
			var dx := float(xx - cx) / float(max(1, rx))
			var dy := float(yy - cy) / float(max(1, ry))
			if dx * dx + dy * dy <= 1.0:
				_px(xx, yy, c)

func _line(x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	var steps: int = max(abs(x1 - x0), abs(y1 - y0))
	if steps == 0:
		_px(x0, y0, c)
		return
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		_px(roundi(lerpf(x0, x1, t)), roundi(lerpf(y0, y1, t)), c)

## A line with body -- used for the neck, where a 1px stroke would vanish.
func _thick_line(x0: int, y0: int, x1: int, y1: int, thickness: int, c: Color) -> void:
	var steps: int = max(abs(x1 - x0), abs(y1 - y0))
	var half: int = thickness / 2
	for i in range(steps + 1):
		var t := float(i) / float(max(1, steps))
		var cx := roundi(lerpf(x0, x1, t))
		var cy := roundi(lerpf(y0, y1, t))
		for yy in range(cy - half, cy + half + 1):
			for xx in range(cx - half, cx + half + 1):
				_px(xx, yy, c)
