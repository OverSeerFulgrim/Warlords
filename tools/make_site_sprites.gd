extends SceneTree
## One-off art generator: writes the nine lootable-site placeholder pairs into
## `assets/placeholder/generated/`.
##
## Run with:  godot --headless --path . -s res://tools/make_site_sprites.gd
##
## `LOOT_SITES_SPEC.md` section 9's "New art" row asks for a looted-state sprite
## per type, as placeholders, named per SPRITE_SPEC and deleted in the commit
## that replaces each with real art. Twelve site types needed art and the vendor
## packs have none of it -- a Kenney tower is not a wolf den and a red house is
## not an abandoned camp -- so these are drawn here for the same reason the deer
## and the wolf were.
##
## ## The two rules that make these usable
##
## 1. **128x128 canvas, every one of them**, matching the commissioned
##    `Grave_Undisturbed.png` / `Grave_Dug_Up.png` pair the single graves reuse.
##    `WorldSite` still sizes by *canvas width* (its documented exception), so a
##    looted sprite on a different canvas would silently resize the site the
##    moment it was looted. `check_sprite_scales.tscn` asserts the pairing.
## 2. **The looted state is a different silhouette, not a darker one.** At world
##    zoom a tint is invisible; a toppled pillar or an open black doorway reads
##    from across the valley, which is what the spent-site swap is for.
##
## Kept in the repo rather than run-and-deleted, same as the deer's and the
## wolf's, so the placeholders stay tweakable. Nothing depends on this file at
## runtime, only on its output PNGs.

const OUT_DIR := "res://assets/placeholder/generated/"
const SIZE := 128
const GROUND := 112   # where everything stands, in canvas pixels

const COL_OUTLINE := Color8(28, 30, 38)
const COL_STONE := Color8(132, 136, 146)
const COL_STONE_DARK := Color8(92, 96, 106)
const COL_STONE_LIGHT := Color8(176, 180, 190)
const COL_WOOD := Color8(104, 82, 60)
const COL_WOOD_DARK := Color8(72, 56, 40)
const COL_BONE := Color8(224, 218, 198)
const COL_DARK := Color8(16, 16, 22)       # the black of an opening
const COL_EARTH := Color8(74, 62, 52)
const COL_SNOW := Color8(226, 232, 240)
const COL_EMBER := Color8(196, 96, 48)
const COL_IRON := Color8(150, 158, 168)
const COL_BLOOD := Color8(112, 44, 44)

var img: Image

func _init() -> void:
	var made: int = 0
	for name in ["graveyard", "cache", "shrine", "camp", "ruin", "den", "crypt", "cave", "battlefield"]:
		for looted in [false, true]:
			_begin()
			call("_draw_%s" % name, looted)
			made += 1 if _save(name, looted) == OK else 0
	print("make_site_sprites: wrote %d sprites to %s" % [made, OUT_DIR])
	quit()

func _begin() -> void:
	img = Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

func _save(name: String, looted: bool) -> int:
	var path: String = "%ssite_%s%s.png" % [OUT_DIR, name, "_looted" if looted else ""]
	var err: int = img.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		printerr("  FAILED %s (err=%d)" % [path, err])
	return err

# ---------------- Drawing primitives -----------------------------------------
#
# Every solid shape is stamped twice -- oversized in the outline colour, then at
# true size in its fill -- for a free 1px keyline around the whole silhouette.
# Same two-pass trick the deer and the wolf use, and the reason these read at
# 50px on dark ground.

func _px(x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= SIZE or y >= SIZE:
		return
	img.set_pixel(x, y, c)

func _rect(x: int, y: int, w: int, h: int, c: Color, grow: int = 0) -> void:
	for yy in range(y - grow, y + h + grow):
		for xx in range(x - grow, x + w + grow):
			_px(xx, yy, c)

## A solid shape plus its keyline, in one call.
func _blk(x: int, y: int, w: int, h: int, c: Color) -> void:
	_rect(x, y, w, h, COL_OUTLINE, 2)
	_rect(x, y, w, h, c)

## An upright rounded slab -- the headstone/pillar primitive.
func _slab(x: int, y: int, w: int, h: int, c: Color) -> void:
	_blk(x, y, w, h, c)
	# Round the two top corners by clearing a pixel wedge.
	for d in range(2):
		for i in range(2 - d):
			_px(x + i, y + d, Color(0, 0, 0, 0))
			_px(x + w - 1 - i, y + d, Color(0, 0, 0, 0))

## A filled ellipse, for mounds, pits and cave mouths.
func _ellipse(cx: int, cy: int, rx: int, ry: int, c: Color, grow: int = 0) -> void:
	for yy in range(cy - ry - grow, cy + ry + grow + 1):
		for xx in range(cx - rx - grow, cx + rx + grow + 1):
			var dx: float = float(xx - cx) / maxf(1.0, float(rx + grow))
			var dy: float = float(yy - cy) / maxf(1.0, float(ry + grow))
			if dx * dx + dy * dy <= 1.0:
				_px(xx, yy, c)

func _dome(cx: int, cy: int, rx: int, ry: int, c: Color) -> void:
	_ellipse(cx, cy, rx, ry, COL_OUTLINE, 2)
	_ellipse(cx, cy, rx, ry, c)
	# Flatten it onto the ground: nothing below the ground line.
	_rect(0, GROUND + 3, SIZE, SIZE - GROUND - 3, Color(0, 0, 0, 0))

## A thick line, for spears, beams and toppled things.
func _bar(x0: int, y0: int, x1: int, y1: int, thick: int, c: Color) -> void:
	var steps: int = maxi(absi(x1 - x0), absi(y1 - y0))
	for i in range(steps + 1):
		var t: float = float(i) / float(maxi(1, steps))
		var x: int = int(round(lerpf(float(x0), float(x1), t)))
		var y: int = int(round(lerpf(float(y0), float(y1), t)))
		_rect(x - thick / 2, y - thick / 2, thick, thick, c)

func _bar_out(x0: int, y0: int, x1: int, y1: int, thick: int, c: Color) -> void:
	_bar(x0, y0, x1, y1, thick + 3, COL_OUTLINE)
	_bar(x0, y0, x1, y1, thick, c)

## Rubble and scatter, deterministic so re-running the generator produces the
## same PNG and git sees no diff.
func _scatter(cx: int, cy: int, spread: int, count: int, c: Color, salt: int) -> void:
	for i in range(count):
		var h: float = _hash01(i, salt)
		var h2: float = _hash01(i + 97, salt)
		var x: int = cx + int((h - 0.5) * float(spread) * 2.0)
		var y: int = cy + int((h2 - 0.5) * float(spread) * 0.6)
		_rect(x - 1, y - 1, 4, 3, COL_OUTLINE)
		_rect(x, y, 2, 2, c)

func _hash01(a: int, b: int) -> float:
	var n: int = (a * 374761393 + b * 668265263) & 0x7fffffff
	n = (n ^ (n >> 13)) * 1274126177
	return float((n & 0x7fffffff) % 10000) / 10000.0

# ---------------- The nine types ---------------------------------------------

## Three headstones. The graveyards (derelict, village, church) share one
## drawing: they differ in danger and watcher, not in what a grave looks like.
func _draw_graveyard(looted: bool) -> void:
	_dome(64, GROUND - 2, 46, 10, COL_SNOW)
	if not looted:
		_slab(30, 60, 18, 52, COL_STONE)
		_slab(56, 48, 20, 64, COL_STONE_LIGHT)
		_slab(84, 66, 16, 46, COL_STONE_DARK)
		_bar(62, 60, 70, 60, 4, COL_STONE_DARK)   # a cross-arm on the tall one
	else:
		# Two toppled, one still standing crooked, and open earth in front.
		_ellipse(44, 104, 16, 7, COL_OUTLINE, 2)
		_ellipse(44, 104, 16, 7, COL_EARTH)
		_ellipse(86, 106, 13, 6, COL_OUTLINE, 2)
		_ellipse(86, 106, 13, 6, COL_EARTH)
		_bar_out(28, 100, 52, 92, 12, COL_STONE_DARK)
		_slab(60, 62, 18, 50, COL_STONE)
		_scatter(66, 108, 26, 7, COL_BONE, 11)

## A hidden cache: stones pulled over a pit, with a sack showing.
func _draw_cache(looted: bool) -> void:
	_dome(64, GROUND - 1, 34, 9, COL_SNOW)
	if not looted:
		_ellipse(64, 96, 26, 12, COL_OUTLINE, 2)
		_ellipse(64, 96, 26, 12, COL_STONE_DARK)
		_blk(50, 68, 28, 30, COL_WOOD)          # the sack/bundle
		_bar(52, 74, 76, 74, 3, COL_WOOD_DARK)
		_rect(46, 90, 12, 8, COL_STONE)
		_rect(72, 88, 14, 10, COL_STONE_LIGHT)
	else:
		_ellipse(64, 94, 28, 14, COL_OUTLINE, 2)
		_ellipse(64, 94, 28, 14, COL_DARK)      # an open hole
		_ellipse(64, 92, 22, 9, COL_EARTH)
		_scatter(64, 104, 30, 6, COL_STONE, 23)

## A wayside shrine: a pillar with an offering bowl.
func _draw_shrine(looted: bool) -> void:
	_dome(64, GROUND - 1, 32, 9, COL_SNOW)
	if not looted:
		_blk(50, 40, 28, 72, COL_STONE)
		_rect(54, 46, 20, 4, COL_STONE_LIGHT)
		_blk(44, 30, 40, 12, COL_STONE_LIGHT)   # the cap
		_ellipse(64, 62, 11, 6, COL_OUTLINE, 2)
		_ellipse(64, 62, 11, 6, COL_EMBER)      # the offering
	else:
		_bar_out(38, 104, 92, 78, 26, COL_STONE_DARK)   # the pillar, on its side
		_blk(30, 92, 22, 20, COL_STONE)                  # its broken base
		_scatter(70, 106, 24, 6, COL_STONE_LIGHT, 5)

## An abandoned camp: a lean-to and a firepit.
func _draw_camp(looted: bool) -> void:
	_dome(64, GROUND - 1, 44, 9, COL_SNOW)
	if not looted:
		_bar_out(34, 110, 66, 44, 7, COL_WOOD)
		_bar_out(96, 110, 66, 44, 7, COL_WOOD)
		for i in range(9):
			_bar(38 + i * 3, 108 - i * 6, 92 - i * 3, 108 - i * 6, 3, COL_WOOD_DARK)
		_ellipse(96, 102, 10, 5, COL_OUTLINE, 2)
		_ellipse(96, 102, 10, 5, COL_EMBER)
	else:
		_bar_out(30, 110, 74, 96, 7, COL_WOOD_DARK)
		_bar_out(58, 108, 100, 104, 6, COL_WOOD_DARK)
		_ellipse(88, 104, 11, 5, COL_OUTLINE, 2)
		_ellipse(88, 104, 11, 5, COL_STONE_DARK)   # cold ashes
		_scatter(60, 106, 30, 5, COL_WOOD, 17)

## A collapsed ruin: one arch still standing.
func _draw_ruin(looted: bool) -> void:
	_dome(64, GROUND - 1, 46, 10, COL_SNOW)
	if not looted:
		_blk(26, 46, 20, 66, COL_STONE)
		_blk(82, 46, 20, 66, COL_STONE)
		_blk(26, 34, 76, 14, COL_STONE_LIGHT)    # the lintel
		_rect(50, 50, 28, 62, COL_DARK)          # the dark under the arch
	else:
		_blk(26, 60, 20, 52, COL_STONE_DARK)
		_bar_out(84, 110, 108, 86, 18, COL_STONE_DARK)
		_scatter(70, 104, 34, 9, COL_STONE, 31)

## A wolf den: a hole under a root ball, with gnawed bones in front.
func _draw_den(looted: bool) -> void:
	_dome(64, GROUND - 1, 46, 12, COL_EARTH)
	_ellipse(64, 66, 40, 26, COL_OUTLINE, 2)
	_ellipse(64, 66, 40, 26, COL_WOOD_DARK)      # the root mass
	for i in range(5):
		_bar(30 + i * 16, 48, 24 + i * 16, 30, 4, COL_WOOD)
	_ellipse(64, 92, 22, 16, COL_OUTLINE, 2)
	_ellipse(64, 92, 22, 16, COL_DARK)           # the mouth
	if not looted:
		_scatter(64, 108, 32, 8, COL_BONE, 3)
		_bar_out(40, 108, 54, 104, 4, COL_BONE)
	else:
		_scatter(64, 108, 30, 3, COL_BONE, 41)

## An ancient crypt: a stone door set into a mound.
func _draw_crypt(looted: bool) -> void:
	_dome(64, GROUND - 1, 54, 34, COL_SNOW)
	_blk(38, 52, 52, 60, COL_STONE_DARK)         # the facing
	_blk(32, 42, 64, 12, COL_STONE)              # the lintel
	if not looted:
		_blk(50, 62, 28, 50, COL_STONE_LIGHT)    # the sealed door
		_bar(56, 84, 72, 84, 4, COL_STONE_DARK)
		_bar(64, 70, 64, 100, 4, COL_STONE_DARK)
	else:
		_rect(50, 62, 28, 50, COL_DARK)          # open, and darker than the snow
		_bar_out(88, 110, 110, 92, 16, COL_STONE_LIGHT)   # the door, thrown down

## An outlaw cave: a mouth in a rock face.
func _draw_cave(looted: bool) -> void:
	_ellipse(64, 96, 58, 44, COL_OUTLINE, 2)
	_ellipse(64, 96, 58, 44, COL_STONE_DARK)
	_ellipse(52, 70, 22, 14, COL_STONE)          # a lit face on the rock
	_rect(0, GROUND + 3, SIZE, SIZE - GROUND - 3, Color(0, 0, 0, 0))
	_ellipse(64, 100, 26, 22, COL_OUTLINE, 2)
	_ellipse(64, 100, 26, 22, COL_DARK)
	if not looted:
		_bar_out(28, 108, 34, 78, 5, COL_WOOD)   # a stake with something on it
		_ellipse(34, 74, 7, 8, COL_OUTLINE, 2)
		_ellipse(34, 74, 7, 8, COL_BONE)
		_bar(96, 96, 104, 74, 4, COL_IRON)       # a spear leaning by the mouth
	else:
		_scatter(64, 108, 34, 5, COL_STONE, 61)

## A cursed battlefield: a shield and a spear left where they fell.
func _draw_battlefield(looted: bool) -> void:
	_dome(64, GROUND - 2, 50, 10, COL_EARTH)
	if not looted:
		_bar_out(88, 112, 78, 34, 5, COL_WOOD)         # the spear, upright
		_bar(74, 40, 82, 26, 4, COL_IRON)
		_ellipse(44, 84, 24, 26, COL_OUTLINE, 2)
		_ellipse(44, 84, 24, 26, COL_WOOD)             # the shield
		_ellipse(44, 84, 8, 9, COL_IRON)
		_bar(30, 84, 58, 84, 3, COL_IRON)
		_scatter(64, 106, 40, 10, COL_BONE, 7)
	else:
		_bar_out(26, 106, 64, 98, 5, COL_WOOD)         # the spear, down and snapped
		_ellipse(46, 96, 24, 14, COL_OUTLINE, 2)
		_ellipse(46, 96, 24, 14, COL_WOOD_DARK)        # the shield, face down
		_bar(34, 96, 58, 96, 3, COL_BLOOD)
		_scatter(66, 106, 40, 12, COL_BONE, 13)
