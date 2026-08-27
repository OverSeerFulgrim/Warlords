extends Node
## Slices every terrain sheet and writes a labelled PNG grid of the result.
##
##   godot --headless --path . res://tools/dump_atlas.tscn
##   -> user://atlas_dump.png  (and a per-sheet geometry report on stdout)
##
## **Run this before wiring a new sheet, and read the output.** R1 recorded the
## practice and TERRAIN_SPEC §2 makes it a rule: which of a sheet's sixteen
## cells holds which connection piece has to be read off the real file, not off
## a description. *"A margin or separation off by a few pixels shows up in the
## dump and nowhere else."*
##
## **Kept committed.** Every future sheet needs it, and the geometry assertions
## below are the thing that stops a silent off-by-one becoming 20,736 wrong
## cells.
##
## ## It measures the geometry rather than trusting it
##
## The sheets are *nominally* 1254x1254, 4x4, 305px tiles, 5px margin, 8px
## separation. They are not all actually that, which is exactly why this
## measures: the gutters between tiles are uniform-colour columns and rows, so
## finding the runs of uniform lines finds the real margin, separation and tile
## size for each file independently. A sheet with a thicker outer border than
## its siblings shifts every tile in it, and an assumption there is invisible
## until the art looks subtly wrong at 64px.
##
## A **scene**, not `-s`: `-s` compiles before the autoloads register, and this
## reads WorldMap's constants.

const OUT_PATH := "user://atlas_dump.png"

## How much to blow the 64px tiles up by in the dump, so a human can see what a
## corner piece actually is.
const DUMP_SCALE: int = 3

## Nominal geometry, for the report's "matches nominal?" column only. Nothing
## slices with these.
const NOMINAL_MARGIN: int = 5
const NOMINAL_SEPARATION: int = 8
const NOMINAL_TILE: int = 305

## A uniform line is one whose pixels are all within this of each other. Not
## zero: the sheets are lossy-compressed art, so a "flat" gutter still has a
## little noise in it.
const UNIFORM_TOLERANCE: float = 0.02

var _passed: int = 0
var _failed: int = 0

## A bare WorldMap, used only for its geometry measurement. Calling into it
## rather than reimplementing the search here is the point: the tool has to
## report exactly what the loader will do, or reading the dump proves nothing.
var _map: WorldMap = WorldMap.new()

func _ready() -> void:
	print("\n=== Terrain atlas dump ===\n")
	var blocks: Array = []
	for sheet_id in WorldMap.TILESET_PATHS.keys():
		var block: Dictionary = _measure_and_slice(sheet_id, WorldMap.TILESET_PATHS[sheet_id])
		if block.is_empty():
			_failed += 1
			continue
		blocks.append(block)
	_write_dump(blocks)
	print("\n%d checks passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

# ---------------- Per-sheet ---------------------------------------------------

func _measure_and_slice(sheet_id: String, path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		print("  MISSING  %s -> %s" % [sheet_id, path])
		return {}
	var tex: Texture2D = load(path)
	var img: Image = tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)

	var geo: Dictionary = _map.measure_sheet_geometry(img)
	var nominal: bool = geo["margin"] == NOMINAL_MARGIN \
		and geo["separation"] == NOMINAL_SEPARATION and geo["tile"] == NOMINAL_TILE
	# The flat-edge widths are reported alongside because they are what a human
	# notices when a sheet "looks like it has a thicker border" -- and they are
	# NOT the margin. path_dirt leads with ten flat columns and is still sliced
	# at margin 5; the other five are its first tile's own flat edge.
	var edges: Vector2i = _map.leading_flat_columns(img)
	print("  %-14s %dx%d  margin %d  separation %d  tile %d   flat edge %d/%d   %s" % [
		sheet_id, img.get_width(), img.get_height(),
		geo["margin"], geo["separation"], geo["tile"], edges.x, edges.y,
		"(nominal, verified)" if nominal else "** DIFFERS FROM NOMINAL **"])

	# The one invariant that must hold whatever the margins are: the measured
	# geometry has to actually fit inside the file. This is the assertion that
	# catches a slice running off the edge and returning black.
	var span: int = geo["margin"] * 2 + WorldMap.SHEET_COLUMNS * geo["tile"] \
		+ (WorldMap.SHEET_COLUMNS - 1) * geo["separation"]
	_check("%s: measured geometry spans the file exactly (%d vs %d)"
		% [sheet_id, span, img.get_width()], span == img.get_width(),
		"a slice would run off the edge")

	var tiles: Array = []
	for row in range(WorldMap.SHEET_ROWS):
		for col in range(WorldMap.SHEET_COLUMNS):
			var region := Rect2i(
				geo["margin"] + col * (geo["tile"] + geo["separation"]),
				geo["margin"] + row * (geo["tile"] + geo["separation"]),
				geo["tile"], geo["tile"])
			var piece: Image = img.get_region(region)
			piece.resize(WorldMap.CELL_SIZE, WorldMap.CELL_SIZE, Image.INTERPOLATE_LANCZOS)
			tiles.append(piece)
			# An all-black tile is the signature of a slice that fell off the
			# sheet -- the failure this whole tool exists to catch.
			_check("%s tile %d,%d is not all black" % [sheet_id, row, col],
				not _is_black(piece), "slicing off-by-one")
	return {"id": sheet_id, "tiles": tiles, "geometry": geo}

func _is_black(img: Image) -> bool:
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c: Color = img.get_pixel(x, y)
			if c.a > 0.05 and (c.r + c.g + c.b) > 0.05:
				return false
	return true

# ---------------- The dump ----------------------------------------------------

## Writes the whole combined atlas, tile by tile, each stamped with the **atlas
## coordinate the legend and the mask tables will name it by**. That is the
## number a human copying pieces out of this dump actually needs; the sheet's
## own row/column is an implementation detail of the slicing.
func _write_dump(blocks: Array) -> void:
	var cols: int = WorldMap.ATLAS_COLUMNS
	var rows: int = WorldMap.ATLAS_ROWS
	var cell: int = WorldMap.CELL_SIZE * DUMP_SCALE
	var out := Image.create_empty(cols * cell, rows * cell, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.08, 0.08, 0.10, 1.0))
	for b in range(blocks.size()):
		var block: Dictionary = blocks[b]
		for i in range(block["tiles"].size()):
			var coord: Vector2i = WorldMap.atlas_coord_for(b, i)
			var piece: Image = (block["tiles"][i] as Image).duplicate()
			piece.resize(cell, cell, Image.INTERPOLATE_NEAREST)
			out.blit_rect(piece, Rect2i(0, 0, cell, cell), Vector2i(coord.x * cell, coord.y * cell))
			_stamp(out, coord.x * cell + 3, coord.y * cell + 3, "%d,%d" % [coord.x, coord.y])
	out.save_png(OUT_PATH)
	print("\n  wrote %s (%dx%d, %d tiles at %dx)" % [
		OUT_PATH, out.get_width(), out.get_height(), blocks.size() * 16, DUMP_SCALE])

func _print_coord_table(blocks: Array) -> void:
	print("\n  sheet -> atlas coords (sheet row,col = atlas x,y)")
	for b in range(blocks.size()):
		var line := "    %-14s " % blocks[b]["id"]
		for i in range(16):
			var c: Vector2i = WorldMap.atlas_coord_for(b, i)
			line += "%d,%d=%d,%d  " % [i / 4, i % 4, c.x, c.y]
			if i % 4 == 3:
				print(line)
				line = "    %-14s " % ""

# ---------------- A 3x5 digit font, because Image cannot draw text ------------

const GLYPHS := {
	"0": ["111", "101", "101", "101", "111"],
	"1": ["010", "110", "010", "010", "111"],
	"2": ["111", "001", "111", "100", "111"],
	"3": ["111", "001", "111", "001", "111"],
	"4": ["101", "101", "111", "001", "001"],
	"5": ["111", "100", "111", "001", "111"],
	"6": ["111", "100", "111", "101", "111"],
	"7": ["111", "001", "010", "010", "010"],
	"8": ["111", "101", "111", "101", "111"],
	"9": ["111", "101", "111", "001", "111"],
	",": ["000", "000", "000", "010", "010"],
}

## Two passes: a dark halo then the glyph, so a label stays readable over pale
## snow and dark rock alike -- the same problem the wolf's hp label solved with
## an outline.
func _stamp(img: Image, ox: int, oy: int, text: String) -> void:
	for pass_index in range(2):
		var colour: Color = Color(0, 0, 0, 0.9) if pass_index == 0 else Color(1, 1, 0.3, 1)
		var spread: int = 1 if pass_index == 0 else 0
		var x: int = ox
		for ch in text:
			if not GLYPHS.has(ch):
				x += 4 * DUMP_SCALE
				continue
			var rows: Array = GLYPHS[ch]
			for gy in range(rows.size()):
				var row: String = rows[gy]
				for gx in range(row.length()):
					if row[gx] != "1":
						continue
					for sy in range(-spread, spread + 1):
						for sx in range(-spread, spread + 1):
							_fill(img, x + gx * DUMP_SCALE + sx, oy + gy * DUMP_SCALE + sy,
								DUMP_SCALE, colour)
			x += 4 * DUMP_SCALE
	return

func _fill(img: Image, x: int, y: int, size: int, colour: Color) -> void:
	for dy in range(size):
		for dx in range(size):
			var px: int = x + dx
			var py: int = y + dy
			if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
				img.set_pixel(px, py, colour)

func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL  %s   (%s)" % [what, detail])
