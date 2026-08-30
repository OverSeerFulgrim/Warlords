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

## Draw-call ceiling **for the terrain alone** -- the TileMapLayer, plus the
## canopy when it exists.
##
## Measured by hiding everything that is not terrain and sampling, rather than
## reading the whole viewport. The viewport number is not a terrain budget: it
## drew 52 at R1 and 71 on 2026-08-27, and eighteen of that difference is UI
## added since (the combat-feedback label pool, the minimap's friendly dots, the
## HUD). Gating terrain work on a number the HUD moves would mean trimming UI to
## make a terrain test pass, which is the wrong repair every time.
##
## What this budget is actually protecting is R1's trap: **no node per cell**.
## One TileMapLayer is one draw call per atlas page it touches, and the canopy
## is one more. Anything that starts drawing per cell shows up here immediately.
const MAX_TERRAIN_DRAW_CALLS: int = 6

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
	_generation(world)
	_sites_are_reachable(world)
	_forests(world)
	_canopy(world)
	await _performance(main, world)

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

# ---------------- Generation (TERRAIN_SPEC section 12) ------------------------

## Sites the roads must reach, and sites no path may lead to.
const HUMAN_TARGETS := {
	"village": Vector2i(120, 64), "manor": Vector2i(129, 83),
	"church": Vector2i(124, 102), "cemetery": Vector2i(127, 105),
}
## The regions §6 marks Band 4, checked whether or not a site stands in one.
## **Kept alongside the real sites rather than replaced by them**: the "found,
## not followed" rule is about the *ground*, so a road creeping into the Old
## Crypt's rect is a finding even in a shuffle that left the crypt out.
const BAND_4_REGIONS := [
	Vector2i(64, 17), Vector2i(67, 96), Vector2i(13, 28), Vector2i(101, 123),
]
const MAX_CROSSING_GAP: int = 25

## Where a dirt track may end: at a lootable site, or at the lair (§7 rule 3 --
## the player's own approach is his track, not a signpost to loot).
const TERMINUS_TOLERANCE: int = 2

func _generation(world: WorldMap) -> void:
	# **Every road network is connected**, checked by walking road cells only --
	# a road that does not reach the village is a road that leads nowhere, which
	# is the one thing TERRAIN_SPEC section 1 goal 1 forbids.
	var lair := Vector2i(world.lair_origin.x + 5, world.lair_origin.y + 4)
	var start: Vector2i = _nearest(world, lair, func(c: Vector2i): return _is_road(world, c))
	_check("there is a road within reach of the lair", start.x >= 0, "none found")
	if start.x >= 0:
		var reachable: Dictionary = _flood(world, start, func(c: Vector2i): return _is_road(world, c))
		var sizes: Array = []
		var seen: Dictionary = {}
		for y in range(world.height):
			for x in range(world.width):
				if not _is_road(world, Vector2i(x, y)) or seen.has(y * world.width + x):
					continue
				var comp: Dictionary = _flood(world, Vector2i(x, y),
					func(c: Vector2i): return _is_road(world, c))
				for k in comp.keys():
					seen[k] = true
				sizes.append([comp.size(), Vector2i(x, y)])
		sizes.sort_custom(func(a, b): return a[0] > b[0])
		print("    note: %d road components, largest %s" % [sizes.size(), str(sizes.slice(0, 4))])
		for name in HUMAN_TARGETS.keys():
			var target: Vector2i = _nearest(world, HUMAN_TARGETS[name],
				func(c: Vector2i): return _is_road(world, c))
			_check("the road network reaches the %s" % name,
				target.x >= 0 and reachable.has(target.y * world.width + target.x),
				"no continuous road from the lair")

	# **Found, not followed** (section 7): no path of any kind may terminate
	# within 3 cells of a Band 4 site. The crypt, the outlaw cave and the cursed
	# battlefield are the whole reason distance buys quality.
	#
	# Checked against **the sites that are actually placed** as well as the
	# regions, which is new in R2a: until the loot layer landed there was
	# nothing in a Band-4 rect for a road to lead to, and the assertion could
	# only guard the ground. Now it guards the crypt, the cave and the
	# battlefield by name -- and would catch a site moved onto a road, which the
	# region check never could.
	var band_4: Array = BAND_4_REGIONS.duplicate()
	var named := {}
	for entry in _lootable_sites():
		if int(entry["band"]) >= 4:
			band_4.append(entry["cell"])
			named[entry["cell"]] = entry["id"]
	for site_variant in band_4:
		var site: Vector2i = site_variant
		var near: Array = []
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				var c: Vector2i = site + Vector2i(dx, dy)
				if _is_road(world, c):
					near.append(c)
		_check("no path runs within 3 cells of the Band 4 site at %s%s" % [site,
			"" if not named.has(site) else " (%s)" % named[site]],
			near.is_empty(), "%d road cells: %s" % [near.size(), str(near.slice(0, 4))])

	_road_promise(world)

	# **The river has its doors, and they are not far apart** (section 6).
	var crossings: Array = []
	for y in range(world.height):
		for x in range(world.width):
			var name: String = _type_name(world, Vector2i(x, y))
			if name == "Bridge" or name == "Shallows / ford":
				# One crossing may be two cells wide; count each latitude once.
				if crossings.is_empty() or int(crossings[crossings.size() - 1]) != y:
					crossings.append(y)
	_check("the river has at least 2 crossings", crossings.size() >= 2,
		"%d" % crossings.size())
	var worst: int = 0
	for i in range(1, crossings.size()):
		worst = maxi(worst, int(crossings[i]) - int(crossings[i - 1]))
	_check("no two adjacent crossings more than %d cells apart" % MAX_CROSSING_GAP,
		crossings.size() < 2 or worst <= MAX_CROSSING_GAP, "worst gap %d" % worst)
	var has_bridge: bool = _first_cell(world, "Bridge").x >= 0
	var has_ford: bool = _first_cell(world, "Shallows / ford").x >= 0
	_check("there is a bridge (fast, exposed) and a ford (slow, unwatched)",
		has_bridge and has_ford, "bridge=%s ford=%s" % [has_bridge, has_ford])

	# **Flood fill from the lair reaches every walkable cell.** No forest mass,
	# cliff line or river bend may seal off a region the generator did not mean
	# to seal -- this is the assertion that would have caught the first river,
	# which cut the valley in half.
	var walkable_start: Vector2i = _nearest(world, lair, func(c: Vector2i): return world.is_walkable_cell(c))
	var reached: Dictionary = _flood(world, walkable_start,
		func(c: Vector2i): return world.is_walkable_cell(c))
	var total: int = 0
	var stranded: Array = []
	for y in range(world.height):
		for x in range(world.width):
			if not world.is_walkable_cell(Vector2i(x, y)):
				continue
			total += 1
			if not reached.has(y * world.width + x):
				stranded.append(Vector2i(x, y))
	# **Where** the stranded cells are matters more than how many. Pockets inside
	# the northern range are cells the range has closed around -- §12's "the only
	# unreachable cells are inside blocking masses" -- and a 75%-fill band of
	# scree makes a scatter of them. A stranded cell out in open country would
	# be a route the generator sealed by accident, which is the real failure.
	var outside_masses: Array = []
	for c in stranded:
		var in_northern_range: bool = c.y >= 6 and c.y <= 23
		var in_rim: bool = c.x < 12 or c.y < 6 or c.x >= world.width - 12 or c.y >= world.height - 12
		if not (in_northern_range or in_rim):
			outside_masses.append(c)
	print("    note: %d walkable cells, %d unreachable (%d of them outside a blocking mass)"
		% [total, stranded.size(), outside_masses.size()])
	# **Size of the largest stranded pocket, not the total.** A handful of cells
	# walled in by a forest edge meeting a scree spur is a blocking mass doing
	# its job; a *region* is a route the generator sealed by accident, and that
	# is what §12 means by "no forest mass, cliff line or river bend may seal off
	# a region the generator didn't mean to seal".
	var worst_pocket: int = 0
	var counted: Dictionary = {}
	for c in outside_masses:
		if counted.has(c.y * world.width + c.x):
			continue
		var pocket: Dictionary = _flood(world, c, func(n: Vector2i): return world.is_walkable_cell(n))
		for k in pocket.keys():
			counted[k] = true
		worst_pocket = maxi(worst_pocket, pocket.size())
	print("    note: largest stranded pocket outside a blocking mass: %d cells" % worst_pocket)
	_check("flood fill from the lair seals off no region (largest pocket <= 8 cells)",
		worst_pocket <= 8, "a %d-cell region is unreachable" % worst_pocket)

## **SITE REACHABILITY** (added 2026-08-30, after a playtester reported a den
## he could not get into).
##
## The suite had a hole between two assertions that each looked complete. The
## flood fill proves every *walkable cell* is reachable; the clearing rule
## proves every *clearing* has a mouth. **Neither proves a site is standing
## somewhere the villain can actually reach**, and a site placed on a mountain,
## in an unclassified pocket, or one cell outside its own clearing would pass
## both and ship.
##
## So: every active site must have at least one walkable cell **within its own
## interaction reach** that flood-fill-connects to the lair. Reach rather than
## "the site's cell", because that is the rule the game actually enforces --
## `WorldSite.in_reach()` is what decides whether the panel offers anything, and
## a site you can stand next to but not interact with is just as broken.
func _sites_are_reachable(world: WorldMap) -> void:
	var lair := Vector2i(world.lair_origin.x + 5, world.lair_origin.y + 4)
	var start: Vector2i = _nearest(world, lair, func(c: Vector2i): return world.is_walkable_cell(c))
	var reached: Dictionary = _flood(world, start, func(c: Vector2i): return world.is_walkable_cell(c))
	for site in _lootable_sites():
		var cell: Vector2i = site["cell"]
		# The same reach the runtime uses: `pick_radius`, which is
		# max(18, size * 0.6). Derived from the site's own authored size rather
		# than assumed, so a resized site is re-checked at its new reach.
		var reach: float = maxf(18.0, float(site["size"]) * 0.6)
		var span: int = int(ceil(reach / float(WorldMap.CELL_SIZE))) + 1
		var centre: Vector2 = world.cell_centre_px(cell)
		var walkable: int = 0
		var connected: int = 0
		for dy in range(-span, span + 1):
			for dx in range(-span, span + 1):
				var c: Vector2i = cell + Vector2i(dx, dy)
				if c.x < 0 or c.y < 0 or c.x >= world.width or c.y >= world.height:
					continue
				if centre.distance_to(world.cell_centre_px(c)) > reach:
					continue
				if not world.is_walkable_cell(c):
					continue
				walkable += 1
				if reached.has(c.y * world.width + c.x):
					connected += 1
		_check("site '%s' can be stood at and reached from the lair" % site["id"],
			connected > 0,
			"%d walkable cells in reach, %d connected -- %s" % [walkable, connected,
				"SEALED" if walkable > 0 else "nothing walkable in reach"])

## **THE ROAD PROMISE** (designer ruling, 2026-08-27 P2 human check): *a road
## always has something at its end, even minor loot.*
##
## The generator enforces the rule it can see -- a signposted site must carry a
## `lootable` block -- but that only covers tracks it laid on purpose. This is
## the half that reads the finished map: every dead end in the dirt network must
## be a lootable site with at least one loot action at generation time, or the
## lair's own gate (section 7 rule 3: the player's approach is his track, not a
## signpost to loot).
##
## A dead end is a track cell with at most one road neighbour. Cobble is
## deliberately excluded -- the Old Road runs off the map edge at both ends, and
## the map edge is not a broken promise.
func _road_promise(world: WorldMap) -> void:
	var sites: Array = _lootable_sites()
	var termini: Array = []
	for y in range(world.height):
		for x in range(world.width):
			var here := Vector2i(x, y)
			if _type_name(world, here) != "Worn track":
				continue
			var neighbours: int = 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					if _is_road(world, here + Vector2i(dx, dy)):
						neighbours += 1
			if neighbours <= 1:
				termini.append(here)
	print("    note: %d dirt-track dead ends" % termini.size())
	for t_variant in termini:
		var t: Vector2i = t_variant
		if world.lair_band.has_point(t):
			continue   # his own gate, and the one sanctioned exception
		var found: String = ""
		for entry in sites:
			var cell: Vector2i = entry["cell"]
			if maxi(absi(cell.x - t.x), absi(cell.y - t.y)) <= TERMINUS_TOLERANCE \
					and bool(entry["has_loot_action"]):
				found = String(entry["id"])
				break
		_check("the dirt track ending at %s leads to something worth the walk" % t,
			found != "", "nothing lootable within %d cells" % TERMINUS_TOLERANCE)

## Every entry of `world_sites.json` carrying a `lootable` block. Read here
## rather than off the live `WorldSites` so the assertions are about the data
## the generator saw, which is the thing they are really guarding.
func _lootable_sites() -> Array:
	var out: Array = []
	var data: Dictionary = _json("res://data/world_sites.json")
	for entry in data.get("sites", []):
		if not entry.has("lootable"):
			continue
		var block: Dictionary = entry["lootable"]
		var c: Array = entry.get("cell", [0, 0])
		out.append({
			"id": String(entry.get("id", "?")),
			"type": String(block.get("type", "")),
			"band": int(block.get("band", 2)),
			"cell": Vector2i(int(c[0]), int(c[1])),
			"size": float(entry.get("size", 56.0)),
			"signposted": bool(entry.get("signposted", false)),
			# "At least one loot action at generation time": a charge to spend,
			# and either a table to roll or a sheet to answer.
			"has_loot_action": int(block.get("charges", 0)) > 0
				and (String(block.get("loot_table", "")) != ""
					or String(block.get("choices", "")) != ""),
		})
	return out

## Section 6b: every dense mass crossable, corridor mouths close enough together,
## every clearing with exactly one mouth and nothing paved inside a wood.
func _forests(world: WorldMap) -> void:
	var dense: int = 0
	var woodland: int = 0
	for y in range(world.height):
		for x in range(world.width):
			var name: String = _type_name(world, Vector2i(x, y))
			if name == "Dense forest":
				dense += 1
			elif name == "Open woodland":
				woodland += 1
	var coverage: float = 100.0 * float(dense) / float(world.width * world.height)
	print("    note: %d dense forest cells (%.1f%% of the map), %d open woodland"
		% [dense, coverage, woodland])
	_check("dense forest covers 8-14%% of the map (section 6b)",
		coverage >= 8.0 and coverage <= 14.0, "%.1f%%" % coverage)

	# **Nothing paved inside a wood** (section 6b's hard error, asserted). A
	# corridor is not a road, and a road that entered a forest would make every
	# clearing a crossroads.
	var paved_in_wood: int = 0
	for y in range(world.height):
		for x in range(world.width):
			if not _is_paved(world, Vector2i(x, y)):
				continue
			for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
				if _type_name(world, Vector2i(x, y) + d) == "Dense forest":
					paved_in_wood += 1
					break
	print("    note: %d paved cells touch dense forest (a track may END at a mouth)"
		% paved_in_wood)
	_check("no paved cell is surrounded by dense forest", _paved_inside_wood(world) == 0,
		"%d paved cells are inside a wood" % _paved_inside_wood(world))

	var masses: Array = _mass_components(world)
	var big: int = 0
	for m in masses:
		if int(m["size"]) >= 40:
			big += 1
	# **Components, not masses.** §6b authors 2-4 masses; this counts connected
	# regions of dense forest, and a corridor cut clean through a mass splits its
	# dense region in two by construction -- that is the corridor working. Three
	# authored masses therefore present as six or more components, and asserting
	# 2-4 here would have been asserting that the corridors had failed.
	print("    note: %d dense-forest components, %d of mass size (corridors split masses)"
		% [masses.size(), big])
	_check("there are at least two dense masses of real size", big >= 2, "%d" % big)

	# **Every clearing has exactly one corridor mouth.** Zero is a softlock, two
	# is a crossroads -- and a crossroads inside a wood is just a road, which is
	# the one thing a clearing must not be. A clearing is found structurally: a
	# patch of ordinary ground whose every outside neighbour is forest.
	var clearings: Array = _clearings(world)
	print("    note: %d interior clearings" % clearings.size())
	_check("the masses hold at least one clearing between them",
		not clearings.is_empty(), "none found -- R2a's dens have nowhere to go")
	# Which clearings actually hold something worth walking to. A clearing with
	# no site in it can have whatever mouth it likes; one with a den in it has to
	# be enterable by a person who cannot see the tile grid.
	var site_cells: Dictionary = {}
	for site in _lootable_sites():
		var sc: Vector2i = site["cell"]
		site_cells[sc.y * world.width + sc.x] = site["id"]

	for c in clearings:
		_check("the clearing at %s has exactly one corridor mouth" % str(c["at"]),
			int(c["mouths"]) == 1, "%d mouths" % int(c["mouths"]))
		_check("and nothing paved inside it", not bool(c["paved"]), "a road reaches in")
		# **A mouth a player can find** (2026-08-30). One cell is topologically a
		# mouth and practically a wall: with the canopy drawn over both sides,
		# a playtester walked the perimeter of the valley den and reported it
		# "literally impossible to reach". It was reachable -- flood fill and an
		# A* from the lair both said so -- through a single 64px gap in six cells
		# of unbroken pine, which is why every existing assertion passed.
		#
		# Asserted only for clearings that hold a site, because that is where the
		# cost of an unfindable door is paid, and TERRAIN_SPEC §6b allows 1-2
		# cell lanes generally.
		var holds: String = ""
		for key in c["cells"].keys():
			if site_cells.has(key):
				holds = String(site_cells[key])
		if holds != "":
			_check("the clearing holding '%s' has a mouth wide enough to find" % holds,
				int(c["mouth_cells"]) >= 2,
				"%d cell mouth -- one cell of gap under canopy reads as solid forest"
					% int(c["mouth_cells"]))

## Section 6b: the canopy is ONE MultiMeshInstance2D, within its instance budget,
## with zero per-tree nodes.
func _canopy(world: WorldMap) -> void:
	_check("the canopy exists", world.canopy != null, "null")
	if world.canopy == null:
		return
	_check("the canopy is a MultiMeshInstance2D", world.canopy is MultiMeshInstance2D)
	_check("with zero children -- no node per tree", world.canopy.get_child_count() == 0,
		"%d children" % world.canopy.get_child_count())
	var dense: int = 0
	var woodland: int = 0
	for y in range(world.height):
		for x in range(world.width):
			var name: String = _type_name(world, Vector2i(x, y))
			if name == "Dense forest":
				dense += 1
			elif name == "Open woodland":
				woodland += 1
	var instances: int = world.canopy.multimesh.instance_count
	var budget: int = int(1.5 * float(dense * 2 + woodland))
	print("    note: %d canopy instances over %d dense + %d woodland cells"
		% [instances, dense, woodland])
	_check("the canopy is within its instance budget (<= %d)" % budget,
		instances > 0 and instances <= budget, "%d" % instances)
	_check("the canopy draws above the terrain and below the units",
		world.canopy.z_index > 0 and world.canopy.z_index < 5,
		"z_index %d" % world.canopy.z_index)

# ---------------- Generation helpers ------------------------------------------

## Road cells, **plus the river's own doors**.
##
## A bridge is a road cell outright (category `road`). A ford is not -- it is
## shallows you wade -- but it is how a track continues across water, and
## `_paint_route` deliberately does not pave over one. Excluding fords made the
## connectivity check report the network severed at every wilderness crossing,
## which is the crossing doing its job rather than a broken road.
func _is_road(world: WorldMap, cell: Vector2i) -> bool:
	if world.connection_group_at(cell) == "road":
		return true
	var name: String = _type_name(world, cell)
	return name == "Bridge" or name == "Shallows / ford"

func _is_paved(world: WorldMap, cell: Vector2i) -> bool:
	return world.connection_group_at(cell) == "road"

func _paved_inside_wood(world: WorldMap) -> int:
	var n: int = 0
	for y in range(world.height):
		for x in range(world.width):
			if not _is_paved(world, Vector2i(x, y)):
				continue
			var trees: int = 0
			for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
				if _type_name(world, Vector2i(x, y) + d) == "Dense forest":
					trees += 1
			if trees >= 3:
				n += 1
	return n

## Interior clearings: components of ordinary ground (not forest, not blocking)
## that are entirely ringed by forest. Their "mouths" are the connected groups
## of open woodland touching them -- the corridor's ends.
func _clearings(world: WorldMap) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	for y in range(world.height):
		for x in range(world.width):
			var here := Vector2i(x, y)
			if seen.has(y * world.width + x) or not _is_plain_ground(world, here):
				continue
			var comp: Dictionary = _flood(world, here,
				func(c: Vector2i): return _is_plain_ground(world, c))
			for k in comp.keys():
				seen[k] = true
			if comp.size() > 60 or comp.size() < 4:
				continue   # the open world, or a stray cell
			var ringed: bool = true
			var touching: Array = []
			var paved: bool = false
			for k in comp.keys():
				var c := Vector2i(int(k) % world.width, int(k) / world.width)
				if _is_paved(world, c):
					paved = true
				for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
					var n: Vector2i = c + d
					if comp.has(n.y * world.width + n.x):
						continue
					var name: String = _type_name(world, n)
					if name == "Open woodland":
						touching.append(n)
					elif name != "Dense forest":
						ringed = false
			if not ringed or touching.is_empty():
				continue
			out.append({"at": here, "mouths": _components_of(world, touching), "paved": paved,
				"mouth_cells": touching.size(), "cells": comp})
	return out

func _is_plain_ground(world: WorldMap, cell: Vector2i) -> bool:
	var name: String = _type_name(world, cell)
	return name != "" and name != "Dense forest" and name != "Open woodland" \
		and world.is_walkable_cell(cell)

## How many connected groups a set of woodland cells forms -- one corridor
## arriving is one mouth, however wide it is.
func _components_of(world: WorldMap, cells: Array) -> int:
	var pool: Dictionary = {}
	for c in cells:
		pool[c.y * world.width + c.x] = true
	var groups: int = 0
	while not pool.is_empty():
		groups += 1
		var seed_key: int = pool.keys()[0]
		var queue: Array = [Vector2i(seed_key % world.width, seed_key / world.width)]
		pool.erase(seed_key)
		while not queue.is_empty():
			var here: Vector2i = queue.pop_back()
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var k: int = (here.y + dy) * world.width + (here.x + dx)
					if pool.has(k):
						pool.erase(k)
						queue.append(Vector2i(here.x + dx, here.y + dy))
	return groups

func _mass_components(world: WorldMap) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	for y in range(world.height):
		for x in range(world.width):
			if _type_name(world, Vector2i(x, y)) != "Dense forest":
				continue
			if seen.has(y * world.width + x):
				continue
			var comp: Dictionary = _flood(world, Vector2i(x, y),
				func(c: Vector2i): return _type_name(world, c) == "Dense forest")
			for k in comp.keys():
				seen[k] = true
			out.append({"size": comp.size(), "centre": Vector2i(x, y)})
	return out

## Breadth-first fill over cells the predicate accepts. Returns the set of flat
## indices reached, so callers can ask "is this one connected to that one".
func _flood(world: WorldMap, from: Vector2i, accept: Callable) -> Dictionary:
	var seen: Dictionary = {}
	if from.x < 0 or not accept.call(from):
		return seen
	var queue: Array = [from]
	seen[from.y * world.width + from.x] = true
	while not queue.is_empty():
		var here: Vector2i = queue.pop_back()
		for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var n: Vector2i = here + d
			if n.x < 0 or n.y < 0 or n.x >= world.width or n.y >= world.height:
				continue
			var key: int = n.y * world.width + n.x
			if seen.has(key) or not accept.call(n):
				continue
			seen[key] = true
			queue.append(n)
	return seen

## The nearest cell to `from` the predicate accepts, searched in rings.
func _nearest(world: WorldMap, from: Vector2i, accept: Callable) -> Vector2i:
	for r in range(0, 40):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := from + Vector2i(dx, dy)
				if c.x < 0 or c.y < 0 or c.x >= world.width or c.y >= world.height:
					continue
				if accept.call(c):
					return c
	return Vector2i(-1, -1)

# ---------------- The performance trap has not moved --------------------------

func _performance(main, world: WorldMap) -> void:
	_check("terrain is still ONE TileMapLayer", world.terrain_layer != null)
	_check("with ZERO children", world.terrain_layer.get_child_count() == 0,
		"%d children -- something added a node per cell" % world.terrain_layer.get_child_count())

	var everything: int = await _sample_draw_calls()
	var hidden: Array = _hide_all_but_terrain(main)
	var terrain_only: int = await _sample_draw_calls()
	for node in hidden:
		node.visible = true
	print("    note: %d draw calls for the terrain alone, %d for the whole viewport"
		% [terrain_only, everything])
	var draw_calls: int = terrain_only
	# **Headless draws nothing**, so the draw-call counter reads 0 and the frame
	# time is this harness's own work rather than the game's. R1's 52 / 1.3ms
	# were measured windowed, and comparing against them here would assert a
	# number that does not exist. The structural invariant -- one layer, zero
	# children, no node per cell -- is what holds in both, and it is the one
	# that actually prevents the trap.
	if everything > 0:
		_check("the terrain draws in <= %d calls" % MAX_TERRAIN_DRAW_CALLS,
			draw_calls <= MAX_TERRAIN_DRAW_CALLS,
			"%d -- something started drawing per cell" % draw_calls)
	else:
		print("    note: headless draws nothing -- run windowed for the draw-call gate")

## Hides every visible CanvasItem that is not the terrain layer or the canopy,
## and returns what it hid so the caller can put it back.
##
## Blunt on purpose: the alternative is a list of node paths that goes stale the
## first time someone adds a UI element, and a stale exclusion list would quietly
## start counting that element as terrain.
func _hide_all_but_terrain(main) -> Array:
	var keep: Array = [main.world_map.terrain_layer]
	if main.world_map.canopy != null:
		keep.append(main.world_map.canopy)
	var hidden: Array = []
	_hide_recursive(get_tree().root, keep, hidden)
	return hidden

func _hide_recursive(node: Node, keep: Array, hidden: Array) -> void:
	if node in keep:
		return
	if (node is CanvasItem or node is CanvasLayer) and node.visible:
		# Hiding a parent hides its children, so stop descending -- and do not
		# hide an ancestor of something we are keeping.
		if not _contains_any(node, keep):
			node.visible = false
			hidden.append(node)
			return
	for child in node.get_children():
		_hide_recursive(child, keep, hidden)

func _contains_any(node: Node, keep: Array) -> bool:
	for k in keep:
		if k != null and is_instance_valid(k) and node.is_ancestor_of(k):
			return true
	return false

func _sample_draw_calls() -> int:
	var peak: int = 0
	for i in range(12):
		await get_tree().process_frame
		peak = maxi(peak, int(Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	return peak

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
