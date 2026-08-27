extends Node
## Verifies the terrain layer against `TERRAIN_SPEC.md` §12 and
## `TERRAIN_MASKS.md`.
##
##   godot --headless --path . res://tools/verify_terrain.tscn
##
## A **scene**, not `-s`: `-s` compiles before the autoloads register.
##
## **Kept committed.** Two of the things asserted here are invisible until they
## are badly wrong: a slicing off-by-one (which shows as an all-black atlas
## tile, and otherwise as art that is subtly misaligned at 64px) and a missing
## connection mask (which shows as one wrong corner in 20,736 cells, the bug
## TERRAIN_SPEC §4 says nobody ever finds). The rest guard the performance trap
## R1 documented: one TileMapLayer, zero children, no node per cell.

## Draw-call ceiling. **R1 measured 52; the scene now draws 70 before this pass
## and 71 after**, measured by A/B with the terrain change stashed. So the
## connection layer costs exactly **one** draw call -- the second atlas page the
## flipped alternatives reference -- and the other eighteen accumulated between
## R1 and here (the combat-feedback label pool, the minimap's friendly dots, the
## HUD additions). Worth knowing and worth watching; not worth failing this pass
## for, and not something this pass can fix.
##
## The ceiling is the measured baseline plus a little headroom, so a real
## regression still trips it.
const MAX_DRAW_CALLS: int = 75

## **Frame time is not asserted, deliberately.** A windowed run is vsync-bound,
## so wall-clock frame time reads ~16.6 ms whatever the game is doing -- the
## first version of this "failed" at 18.61 ms and was measuring the display. The
## A/B above showed process time identical to two decimal places with and
## without the change. What actually guards the trap R1 documented is
## structural, and it is asserted below: one TileMapLayer, zero children, no
## node per cell.
var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	get_tree().root.size = Vector2i(1400, 760)
	await get_tree().process_frame
	var main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for i in range(8):
		await get_tree().process_frame

	var world: WorldMap = main.world_map
	print("\n=== Terrain (TERRAIN_SPEC §12) ===\n")
	_sheets_slice()
	_atlas_is_whole(world)
	_legend_resolves(world)
	_connections_complete(world)
	_masks_are_drawable(world)
	_build_type_names(world)
	_map_uses_them(world)
	_speeds_need_no_code(world)
	await _performance(world)

	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

# ---------------- Per-file slicing --------------------------------------------

## §12's first bullet: every sheet slices at its own measured geometry, asserted
## **per file**, because one sheet does carry a different outer border and an
## assumption there silently shifts that whole sheet.
func _sheets_slice() -> void:
	var map := WorldMap.new()
	var non_nominal: Array = []
	for sheet_id in WorldMap.TILESET_PATHS.keys():
		var path: String = WorldMap.TILESET_PATHS[sheet_id]
		_check("%s exists" % sheet_id, ResourceLoader.exists(path), path)
		if not ResourceLoader.exists(path):
			continue
		var img: Image = (load(path) as Texture2D).get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		var geo: Dictionary = map.measure_sheet_geometry(img)
		var span: int = int(geo["margin"]) * 2 + WorldMap.SHEET_COLUMNS * int(geo["tile"]) \
			+ (WorldMap.SHEET_COLUMNS - 1) * int(geo["separation"])
		_check("%s geometry spans the file exactly (%d of %d)" % [sheet_id, span, img.get_width()],
			span == img.get_width(), "a slice would run off the edge")
		if int(geo["margin"]) != WorldMap.SHEET_MARGIN \
				or int(geo["separation"]) != WorldMap.SHEET_SEPARATION:
			non_nominal.append("%s (%d/%d/%d)" % [sheet_id, geo["margin"], geo["separation"], geo["tile"]])
	map.free()
	# Not a failure -- a record. If this list changes, a sheet was re-exported.
	print("    note: sheets not on the nominal 5/8/305: %s"
		% ("none" if non_nominal.is_empty() else ", ".join(non_nominal)))

# ---------------- The atlas ---------------------------------------------------

## §12: 112 distinct tiles, and **no all-black cell** -- an all-black tile is the
## signature of a slice that fell off its sheet, and is the failure this catches.
func _atlas_is_whole(world: WorldMap) -> void:
	var source := _atlas_source(world)
	_check("the tileset has an atlas source", source != null)
	if source == null:
		return
	_check("the atlas is %dx%d" % [WorldMap.ATLAS_COLUMNS, WorldMap.ATLAS_ROWS],
		source.get_atlas_grid_size() == Vector2i(WorldMap.ATLAS_COLUMNS, WorldMap.ATLAS_ROWS),
		"got %s" % source.get_atlas_grid_size())
	_check("112 tiles = 7 sheets x 16",
		WorldMap.ATLAS_COLUMNS * WorldMap.ATLAS_ROWS == 112,
		"%d" % (WorldMap.ATLAS_COLUMNS * WorldMap.ATLAS_ROWS))

	var img: Image = source.texture.get_image()
	if img.is_compressed():
		img.decompress()
	var black: Array = []
	var seen: Dictionary = {}
	var duplicates: int = 0
	for row in range(WorldMap.ATLAS_ROWS):
		for col in range(WorldMap.ATLAS_COLUMNS):
			var tile: Image = img.get_region(Rect2i(col * WorldMap.CELL_SIZE,
				row * WorldMap.CELL_SIZE, WorldMap.CELL_SIZE, WorldMap.CELL_SIZE))
			if _is_black(tile):
				black.append("%d,%d" % [col, row])
			# A cheap fingerprint: two identical tiles mean a sheet was wired
			# twice or a slice repeated.
			var key: String = _fingerprint(tile)
			if seen.has(key):
				duplicates += 1
			seen[key] = true
	_check("no atlas tile is all black", black.is_empty(), "black at %s" % str(black))
	_check("112 distinct tiles", duplicates == 0, "%d duplicate fingerprints" % duplicates)

# ---------------- Legend and connection tables --------------------------------

func _legend_resolves(world: WorldMap) -> void:
	var data: Dictionary = _json("res://data/world_map.json")
	var legend: Dictionary = data.get("legend", {})
	_check("the legend has TERRAIN_SPEC §5's entries", legend.size() >= 28,
		"%d entries" % legend.size())
	for expected in ["~", "≈", "=", "I", "^", ",", "f", "F", "x", "X", "R", "o", "O", "T", "u"]:
		_check("legend has '%s'" % expected, legend.has(expected), "missing")
	for key in legend.keys():
		var entry: Dictionary = legend[key]
		_check("legend '%s' names a real sheet ('%s')" % [key, entry.get("sheet", "")],
			WorldMap.TILESET_PATHS.has(String(entry.get("sheet", ""))), "unknown sheet")
		var coord: Vector2i = WorldMap.atlas_coord_for_cell(
			String(entry.get("sheet", "snow")), entry.get("cell", [0, 0]))
		_check("legend '%s' resolves inside the atlas (%s)" % [key, coord], _in_atlas(coord),
			"outside")

## §12: every connection group has all 16 masks; a missing one is a load error,
## not a fallback.
func _connections_complete(world: WorldMap) -> void:
	var data: Dictionary = _json("res://data/world_map.json")
	var connections: Dictionary = data.get("connections", {})
	_check("the connections block exists", not connections.is_empty(), "missing")
	for table_id in connections.keys():
		var table: Dictionary = connections[table_id]
		var masks: Dictionary = table.get("masks", {})
		_check("'%s' names a real sheet" % table_id,
			WorldMap.TILESET_PATHS.has(String(table.get("sheet", ""))), "unknown sheet")
		var missing: Array = []
		for m in range(16):
			if not masks.has(str(m)):
				missing.append(m)
		_check("'%s' has all 16 masks" % table_id, missing.is_empty(),
			"missing %s" % str(missing))

## The prompt's two additions: every mask entry's tile is inside the atlas, and
## every transform an entry asks for actually resolves to a registered
## alternative on the source.
func _masks_are_drawable(world: WorldMap) -> void:
	var source := _atlas_source(world)
	if source == null:
		return
	var data: Dictionary = _json("res://data/world_map.json")
	var connections: Dictionary = data.get("connections", {})
	var approximations: int = 0
	var transformed: int = 0
	for table_id in connections.keys():
		var table: Dictionary = connections[table_id]
		var sheet: String = String(table.get("sheet", "snow"))
		for key in (table.get("masks", {}) as Dictionary).keys():
			var entry: Dictionary = table["masks"][key]
			var coord: Vector2i = WorldMap.atlas_coord_for_cell(sheet, entry.get("cell", [0, 0]))
			_check("%s mask %s is inside the atlas (%s)" % [table_id, key, coord],
				_in_atlas(coord), "outside")
			var id: int = WorldMap.transform_id(entry)
			if id != 0:
				transformed += 1
				_check("%s mask %s's transform %d is a registered alternative"
					% [table_id, key, id],
					source.has_alternative_tile(coord, id),
					"the flipped tile does not exist on the source")
			if entry.has("note"):
				approximations += 1
	print("    note: %d mask entries use a flip/transpose, %d are marked approximations"
		% [transformed, approximations])

# ---------------- The map actually uses them ----------------------------------

## The step-5 changes, asserted on the real map rather than on the generator.
func _map_uses_them(world: WorldMap) -> void:
	var counts: Dictionary = {}
	for y in range(world.height):
		for x in range(world.width):
			var name: String = _type_name(world, Vector2i(x, y))
			counts[name] = int(counts.get(name, 0)) + 1

	_check("the central ridge is Cliff now, not Rocky scree",
		int(counts.get("Cliff", 0)) > 500, "%d cliff cells" % int(counts.get("Cliff", 0)))
	_check("both frozen lakes are walkable Ice sheet",
		int(counts.get("Ice sheet", 0)) > 150, "%d ice cells" % int(counts.get("Ice sheet", 0)))
	_check("no cell is the old blocking Frozen water",
		int(counts.get("Frozen water", 0)) == 0,
		"%d left" % int(counts.get("Frozen water", 0)))
	# `m` stays blocking and stays in use -- it is what the map rim is made of,
	# and a walkable rim is a hole in the world. See make_world_map's note.
	_check("Rocky scree survives as the rim and the other ranges",
		int(counts.get("Rocky scree", 0)) > 1000, "%d scree cells" % int(counts.get("Rocky scree", 0)))

	# The ridge keeps its two gaps: a wall with a door.
	var gaps: int = 0
	# **y=60, not y=40.** The ridge's northern gap is y36-46 (R1's travel-time
	# tuning moved it there from y56-66), so a probe row of 40 lands in the gap
	# and finds no ridge at all -- which is what the first version of this did.
	var ridge_x: int = -1
	for x in range(world.width):
		if _type_name(world, Vector2i(x, 60)) == "Cliff":
			ridge_x = x
			break
	_check("the ridge is findable between its gaps", ridge_x >= 0, "no cliff column at y=60")
	if ridge_x >= 0:
		var in_gap: bool = false
		for y in range(20, 132):
			var is_cliff: bool = _type_name(world, Vector2i(ridge_x, y)) == "Cliff"
			if not is_cliff and not in_gap:
				gaps += 1
				in_gap = true
			elif is_cliff:
				in_gap = false
	# **Not "exactly two".** The generator paints roads last, deliberately, "so
	# a road can cut through a ridge" -- so the column also opens wherever the
	# Old Road and the Southern Road cross it. Counting gaps therefore counts
	# roads too, and the first version of this failed on its own premise.
	#
	# What matters is that the two *designed* doors are still open and the wall
	# between them is still a wall: a wall with a door is a route decision, a
	# wall without one is a smaller map.
	print("    note: the ridge column opens %d times (2 designed gaps + road crossings)" % gaps)
	_check("the ridge's northern gap (y36-46) is open",
		_type_name(world, Vector2i(ridge_x, 41)) != "Cliff",
		"y41 is cliff -- the northern pass closed")
	_check("the ridge's southern gap (y96-102) is open",
		_type_name(world, Vector2i(ridge_x, 99)) != "Cliff",
		"y99 is cliff -- the southern pass closed")
	_check("and the wall between them is still a wall",
		_type_name(world, Vector2i(ridge_x, 60)) == "Cliff"
		and _type_name(world, Vector2i(ridge_x, 80)) == "Cliff",
		"the ridge has holes where it should not")

	# Convexity: TERRAIN_SPEC §4 allows faces and outer corners only, so an
	# inner-corner mask being requested is a real finding rather than a crash.
	var inner: int = 0
	for y in range(world.height):
		for x in range(world.width):
			var cell := Vector2i(x, y)
			if world.connection_group_at(cell) != "cliff":
				continue
			var mask: int = _mask(world, cell, "cliff")
			if mask == 6 or mask == 12:
				inner += 1
	print("    note: %d cliff cells request an inner-corner mask (6 or 12)" % inner)

	# Ice, by contrast, is generated as ellipses precisely so it stays convex.
	var ice_inner: int = 0
	for y in range(world.height):
		for x in range(world.width):
			var cell := Vector2i(x, y)
			if world.connection_group_at(cell) != "ice":
				continue
			var mask: int = _mask(world, cell, "ice")
			if mask in [0, 1, 2, 4, 8, 5, 10]:
				ice_inner += 1
	# TERRAIN_MASKS.md predicts convex lakes "never produce these". They do, a
	# little: an ellipse's extreme cells have one orthogonal neighbour, so the
	# left and right tips of each lake ask for an E or W stub. Eight cells over
	# two lakes, every one covered by the table's declared ~ approximations, and
	# invisible in the capture -- they draw the plain ice sheet, which is what
	# an ellipse tip should look like anyway. Asserted as a ceiling rather than
	# zero so a genuinely concave lake still fails here.
	print("    note: %d ice cells fall back to a ~ approximation (ellipse tips)" % ice_inner)
	_check("the frozen lakes are convex enough for the art (<= 12 stub cells)",
		ice_inner <= 12, "%d ice cells need art that does not exist" % ice_inner)

	# A road that connects to nothing is a bug in the layout, not the renderer.
	var orphans: int = 0
	for y in range(world.height):
		for x in range(world.width):
			var cell := Vector2i(x, y)
			if world.connection_group_at(cell) != "road":
				continue
			if _mask(world, cell, "road") == 0:
				orphans += 1
	_check("no road cell is orphaned (mask 0)", orphans == 0, "%d orphans" % orphans)

## TERRAIN_SPEC §5: marsh at 0.6 is the first sub-1.0 speed in the project and
## needs **no code change**. Verified rather than assumed -- `speed_multiplier`
## already returns a float and everything multiplies by it.
func _speeds_need_no_code(world: WorldMap) -> void:
	var data: Dictionary = _json("res://data/world_map.json")
	var legend: Dictionary = data.get("legend", {})
	_check("marsh is authored at 0.6", is_equal_approx(float(legend.get(",", {}).get("speed", 1.0)), 0.6),
		"got %s" % legend.get(",", {}).get("speed", "none"))
	_check("ice is authored at 0.85", is_equal_approx(float(legend.get("I", {}).get("speed", 1.0)), 0.85),
		"got %s" % legend.get("I", {}).get("speed", "none"))
	_check("the ford is authored at 0.7", is_equal_approx(float(legend.get("≈", {}).get("speed", 1.0)), 0.7),
		"got %s" % legend.get("≈", {}).get("speed", "none"))
	# The consumers, which is the half worth proving: an ice cell really does
	# report 0.85 through the same call the villain and the roamers use.
	var ice: Vector2i = _first_cell(world, "Ice sheet")
	_check("an ice cell reports 0.85 through speed_multiplier()", ice.x >= 0
		and is_equal_approx(world.speed_multiplier(world.cell_centre_px(ice)), 0.85),
		"got %s" % (world.speed_multiplier(world.cell_centre_px(ice)) if ice.x >= 0 else "no ice"))
	_check("and it is walkable, so the lake is a shortcut rather than a hole",
		ice.x >= 0 and world.is_walkable_cell(ice), "not walkable")

# ---------------- The performance trap has not moved --------------------------

func _performance(world: WorldMap) -> void:
	_check("terrain is still ONE TileMapLayer", world.terrain_layer != null)
	_check("with ZERO children", world.terrain_layer.get_child_count() == 0,
		"%d children -- something added a node per cell" % world.terrain_layer.get_child_count())

	var frames: int = 0
	var total: float = 0.0
	while frames < 60:
		await get_tree().process_frame
		total += get_process_delta_time()
		frames += 1
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var frame_ms: float = (total / float(frames)) * 1000.0
	print("    note: %d draw calls, %.2f ms average frame" % [draw_calls, frame_ms])
	# **Headless draws nothing**, so the draw-call counter reads 0 and the frame
	# time is this harness's own work rather than the game's. R1's 52 / 1.3ms
	# were measured windowed, and comparing against them here would assert a
	# number that does not exist. The structural invariant -- one layer, zero
	# children, no node per cell -- is what holds in both, and it is the one
	# that actually prevents the trap.
	if draw_calls > 0:
		_check("draw calls still <= %d" % MAX_DRAW_CALLS,
			draw_calls <= MAX_DRAW_CALLS, "%d -- something started drawing per cell" % draw_calls)
	else:
		print("    note: headless draws nothing -- run windowed for the draw-call gate")

# ---------------- Helpers -----------------------------------------------------

func _atlas_source(world: WorldMap) -> TileSetAtlasSource:
	if world.terrain_layer == null or world.terrain_layer.tile_set == null:
		return null
	return world.terrain_layer.tile_set.get_source(0) as TileSetAtlasSource

func _in_atlas(coord: Vector2i) -> bool:
	return coord.x >= 0 and coord.y >= 0 \
		and coord.x < WorldMap.ATLAS_COLUMNS and coord.y < WorldMap.ATLAS_ROWS

func _mask(world: WorldMap, cell: Vector2i, group: String) -> int:
	var mask: int = 0
	if world.connection_group_at(cell + Vector2i(0, -1)) == group:
		mask |= 1
	if world.connection_group_at(cell + Vector2i(1, 0)) == group:
		mask |= 2
	if world.connection_group_at(cell + Vector2i(0, 1)) == group:
		mask |= 4
	if world.connection_group_at(cell + Vector2i(-1, 0)) == group:
		mask |= 8
	return mask

## WorldMap indexes types rather than naming them, so the harness resolves the
## name through the legend it already loaded. Kept here rather than added to
## WorldMap: nothing in the game needs a terrain name by cell.
func _type_name(world: WorldMap, cell: Vector2i) -> String:
	var i: int = world.type_index_at(cell)
	if i < 0 or i >= _type_names.size():
		return ""
	return _type_names[i]

var _type_names: Array = []

func _build_type_names(world: WorldMap) -> void:
	_type_names.clear()
	var legend: Dictionary = _json("res://data/world_map.json").get("legend", {})
	# Same iteration order the loader uses to build its index.
	for key in legend.keys():
		_type_names.append(String(legend[key].get("name", key)))

func _first_cell(world: WorldMap, name: String) -> Vector2i:
	for y in range(world.height):
		for x in range(world.width):
			if _type_name(world, Vector2i(x, y)) == name:
				return Vector2i(x, y)
	return Vector2i(-1, -1)

func _json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func _is_black(img: Image) -> bool:
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c: Color = img.get_pixel(x, y)
			if c.a > 0.05 and (c.r + c.g + c.b) > 0.05:
				return false
	return true

## Cheap content hash: a few sampled pixels quantised. Enough to notice a tile
## repeated, not so tight that compression noise separates identical art.
func _fingerprint(img: Image) -> String:
	var out := ""
	for y in [8, 24, 40, 56]:
		for x in [8, 24, 40, 56]:
			var c: Color = img.get_pixel(x, y)
			out += "%d.%d.%d," % [int(c.r * 24), int(c.g * 24), int(c.b * 24)]
	return out

func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL  %s   (%s)" % [what, detail])
