extends SceneTree
## One-off art generator: writes art/creature_wolf.png.
##
## Run with:  godot --headless --path . -s res://tools/make_wolf_sprite.gd
##
## Same situation and same solution as the deer (see make_deer_sprite.gd for
## the full survey of why no vendored pack has a usable quadruped). This is a
## **placeholder** with one job the deer's didn't have: at 34px on a dark night
## map it must not be mistaken for the deer, because one of them is food and the
## other one eats your workers.
##
## Three deliberate differences carry that read:
##   - **Cold grey-blue** against the deer's warm brown. The single strongest
##     cue at this size, and it survives the night tint (which is itself
##     blue-shifted, so the wolf goes *flatter* at night while the brown deer
##     goes muddier -- they separate rather than converge).
##   - **Low and long.** The wolf's back line is flat and its chest sits low;
##     the deer is tall, short-backed and high-legged. Silhouette alone should
##     be enough.
##   - **No antlers, plus a low head and a raised hackle.** The deer's antlers
##     are its most recognisable feature, so the wolf leads with the opposite
##     shape: head *below* the shoulder line, which is the universal shorthand
##     for a stalking predator.
##
## Kept in the repo rather than run-and-deleted, same as the deer's, so the
## placeholder stays tweakable. Nothing depends on this file at runtime, only on
## its output PNG.

const OUT_PATH := "res://assets/placeholder/generated/creature_wolf.png"
const SIZE := 32

# Wolf faces left, matching the deer so the two read consistently when both are
# on screen. Cold grey palette -- see the header.
const COL_OUTLINE := Color8(38, 42, 52)
const COL_BODY := Color8(104, 112, 126)
const COL_DARK := Color8(72, 79, 92)
const COL_LIGHT := Color8(186, 192, 200)
const COL_EYE := Color8(228, 196, 84)   # amber; the one warm pixel, and it reads as "awake and looking at you"

var img: Image

func _init() -> void:
	img = Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Same two-pass trick as the deer: stamp every solid shape oversized in the
	# outline colour, then again at true size in its fill, for a free 1px
	# keyline around the whole silhouette.
	_draw_body(true)
	_draw_body(false)

	_draw_details()

	var abs_path := ProjectSettings.globalize_path(OUT_PATH)
	var err := img.save_png(abs_path)
	print("save_png -> %s (err=%d)" % [abs_path, err])
	quit()

func _draw_body(outline: bool) -> void:
	var grow := 1 if outline else 0
	var c := COL_OUTLINE if outline else COL_BODY

	# Legs. Shorter and thicker than the deer's, and set wider apart -- a wolf
	# stands over its feet, a deer stands on stilts.
	for leg in [[10, 19, 3, 8], [14, 20, 3, 7], [21, 20, 3, 7], [25, 19, 3, 8]]:
		_rect(leg[0] - grow, leg[1] - grow, leg[2] + grow * 2, leg[3] + grow * 2, c)

	# Long, level barrel. Wider on x and flatter on y than the deer's, which is
	# most of the "low and long" silhouette.
	_ellipse(18, 16, 10 + grow, 5 + grow, c)
	# Deep chest, forward and low.
	_ellipse(12, 17, 5 + grow, 4 + grow, c)
	# Haunch, slightly higher than the shoulder -- the coiled back end.
	_ellipse(25, 15, 5 + grow, 5 + grow, c)
	# Neck, angling DOWN toward the head. The deer's neck rises; this is the
	# stalking posture and the fastest way to tell them apart in silhouette.
	_thick_line(12, 13, 7, 15, 4 + grow, c)
	# Head: a blunt wedge, lower than the shoulders.
	_ellipse(6, 16, 4 + grow, 3 + grow, c)
	# Long muzzle.
	_ellipse(2, 17, 3 + grow, 2 + grow, c)
	# Ears: two sharp triangles, upright and pricked.
	_triangle(6, 10, 4, 4, c, grow)
	_triangle(10, 10, 4, 4, c, grow)
	# Tail, low and straight out behind -- not the deer's little pale scut.
	_thick_line(29, 14, 31, 11, 2 + grow, c)

func _draw_details() -> void:
	# Raised hackle along the spine. Reads as bristling, and breaks the flat
	# back line so the body isn't one grey lozenge.
	for x in range(13, 25, 2):
		_px(x, 11, COL_DARK)
		_px(x, 12, COL_DARK)

	# Darker saddle over the shoulders. On the deer this same shape failed --
	# it read as a blanket -- but on a low flat back it reads as markings,
	# because there's no tall body for it to sit "on top of".
	_ellipse(17, 13, 6, 2, COL_DARK)

	# Pale throat and underbelly. The deer got a chest patch only; the wolf can
	# carry a full belly line because its legs are short enough that the gap
	# between them doesn't turn the stripe into a floating bar.
	_ellipse(9, 19, 3, 2, COL_LIGHT)
	_rect(13, 20, 9, 1, COL_LIGHT)

	# Muzzle tip, darker than the body so the snout has a point.
	_ellipse(1, 17, 1, 1, COL_OUTLINE)

	# Eye. One amber pixel with a dark surround so it doesn't blow out.
	_px(6, 15, COL_OUTLINE)
	_px(5, 15, COL_EYE)

# ---------------- Tiny raster helpers (shared shape with the deer's) --------

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

## An upward-pointing triangle with its base at (cx, base_y), used for the ears.
func _triangle(cx: int, base_y: int, w: int, h: int, c: Color, grow: int) -> void:
	var half: int = w / 2 + grow
	for i in range(h + grow):
		var y: int = base_y - i
		var span: int = int(round(float(half) * (1.0 - float(i) / float(max(1, h + grow)))))
		for x in range(cx - span, cx + span + 1):
			_px(x, y, c)

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
