extends Node2D
class_name WorldMap
## The 144x144 region the run takes place in (WORLD_MAP_PLAN §2, rework §4).
## Terrain only: what each cell looks like, whether you can walk on it, and how
## fast. Contents -- resources, encounters, the village -- are other systems'.
##
## ## One scale, one cell size
##
## `SettlementGrid.CELL_SIZE` (64px) is the shared unit across the settlement,
## the world and walk speed. There is deliberately **no second scale**: walk
## speed 1.0 is one cell per second everywhere (FOUNDATION_SPEC §4), so the map
## doc's travel-time targets are a division rather than a conversion. 144 cells
## at 1.0 is 9216px and ~2.4 minutes straight-line, inside the 3-5 minute
## crossing target once terrain and detours exist.
##
## ## Where the settlement sits
##
## The settlement's 10x8 grid is a *band inside* this map, at `lair_origin`
## (from the data file). **The engine origin stays the Throne's corner cell**
## and this node is offset west/north instead, so every existing settlement-
## space position -- worker trips, resource nodes, wolf spawns, click hit-tests
## -- keeps the coordinates it has today. Moving the settlement instead would
## have meant auditing every `get_global_mouse_position()` call in the project
## for an off-by-one-band click bug. World cells are the derived coordinate
## system; see cell_at()/cell_origin_px().
##
## ## Performance: no node per cell
##
## 144x144 is 20,736 cells. Terrain is **one `TileMapLayer`** -- a single node
## that batches the lot -- not a Sprite2D each. (The settlement's old ground
## background *was* a Sprite2D per cell; at 80 cells nobody noticed, at 20,736
## it would be a stall and 20k orphan nodes. It's gone, replaced by this.)
## Fog is likewise one node with one small texture -- see FogOfWar.gd.

const CELL_SIZE: int = SettlementGrid.CELL_SIZE

## WORLD_MAP_PLAN §2: 144x144 primary target (bounds 128-160). Read from the
## data file at load; these are the fallback and the sanity check.
const DEFAULT_WIDTH: int = 144
const DEFAULT_HEIGHT: int = 144

const DATA_PATH := "res://data/world_map.json"

## The commissioned 4x4 terrain sheet. 1254px square with a 5px margin and 8px
## gutters, so each tile is 305px -- measured off the file, not assumed.
## Everything else in the project scales commissioned art down at use; this does
## the same, once, into a 4x64 atlas (see _build_tileset).
const TILESET_PATH := "res://assets/official/terrain/Terrain_Tileset_Snow.png"
const SHEET_COLUMNS: int = 4
const SHEET_ROWS: int = 4
const SHEET_MARGIN: int = 5
const SHEET_SEPARATION: int = 8
const SHEET_TILE: int = 305

## Terrain categories. Deliberately three, and deliberately not an enum with
## per-type behaviour: the *layout* and the *category of each tile* are both
## data (data/world_map.json's legend), so adding "marsh: walkable but slow" is
## a JSON edit plus a speed number, not a new branch in here.
const CAT_GROUND := "ground"
const CAT_ROAD := "road"
const CAT_BLOCKING := "blocking"

## Roads are worth taking. **Tunable.** Fast enough to be worth a detour, not so
## fast that wilderness travel feels punished -- the map doc's §9 tradeoff is
## "roads are faster but expose you", and the exposure half arrives in R3 with
## patrols, so this number will want revisiting once there is a cost.
const DEFAULT_ROAD_SPEED: float = 1.35

var width: int = DEFAULT_WIDTH
var height: int = DEFAULT_HEIGHT

## Settlement grid's top-left cell in world coordinates.
var lair_origin: Vector2i = Vector2i.ZERO
## The guaranteed-walkable, starts-revealed band around the lair (x, y, w, h in
## world cells). The seeder below fills it; FogOfWar reveals it.
var lair_band: Rect2i = Rect2i()

## One byte per cell -- an index into `_types`. A PackedByteArray rather than a
## Dictionary or a 2D Array: 20,736 entries queried every frame by movement, so
## it wants to be flat and cheap. 20KB total.
var _cells: PackedByteArray = PackedByteArray()
## Per-type data, parallel arrays indexed by the byte above.
var _types: Array = []            # Array[Dictionary] -- name, category, atlas, speed
var _walkable: PackedByteArray = PackedByteArray()
var _speeds: PackedFloat32Array = PackedFloat32Array()
## Average colour of each terrain type, sampled from the atlas at load. The
## minimap draws these, so it can never drift from the art the way a
## hand-written colour table would.
var _map_colors: PackedColorArray = PackedColorArray()

## WORLD_MAP_PLAN §6's danger bands, straight from the data file:
## `{band: int, name: String, rect: Rect2i}`. **Data only** -- nothing consumes
## the number yet; it is the hook R2's encounter and loot tables plug into, and
## today it drives one HUD readout. Later entries win (see band_at).
var bands: Array = []

var terrain_layer: TileMapLayer

## Engine-space pixel offset of world cell (0,0). Negative, because the engine
## origin is the Throne's corner and the Throne is deep inside the map.
var origin_px: Vector2 = Vector2.ZERO

func _ready() -> void:
	z_index = -10  # terrain is under everything else in the settlement layer

## Loads the layout and builds the single tile layer. Call once, from Main,
## before anything asks about walkability.
func build() -> bool:
	var data: Dictionary = _load_data()
	if data.is_empty():
		return false
	_apply_data(data)
	origin_px = -Vector2(lair_origin) * float(CELL_SIZE)
	position = origin_px
	_build_layer()
	return true

func _load_data() -> Dictionary:
	if not FileAccess.file_exists(DATA_PATH):
		push_error("WorldMap: %s missing. Regenerate it with tools/make_world_map.gd." % DATA_PATH)
		return {}
	var text: String = FileAccess.get_file_as_string(DATA_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("WorldMap: %s is not a JSON object." % DATA_PATH)
		return {}
	return parsed

func _apply_data(data: Dictionary) -> void:
	width = int(data.get("width", DEFAULT_WIDTH))
	height = int(data.get("height", DEFAULT_HEIGHT))
	var lo: Array = data.get("lair_origin", [0, 0])
	lair_origin = Vector2i(int(lo[0]), int(lo[1]))
	var lb: Array = data.get("lair_band", [0, 0, width, height])
	lair_band = Rect2i(int(lb[0]), int(lb[1]), int(lb[2]), int(lb[3]))

	bands.clear()
	for entry in data.get("bands", []):
		var r: Array = entry.get("rect", [0, 0, width, height])
		bands.append({
			"band": int(entry.get("band", 2)),
			"name": String(entry.get("name", "Wilderness")),
			"rect": Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])),
		})

	# The legend maps one character to one terrain type. Order matters only in
	# that the byte grid indexes into it, so it's resolved to a char -> index
	# map here and never looked up by character again.
	var legend: Dictionary = data.get("legend", {})
	var index_of: Dictionary = {}
	_types.clear()
	_walkable.resize(0)
	_speeds.resize(0)
	for key in legend.keys():
		var entry: Dictionary = legend[key]
		var category: String = entry.get("category", CAT_GROUND)
		var atlas: Array = entry.get("tile", [0, 0])
		index_of[key] = _types.size()
		_types.append({
			"char": key,
			"name": entry.get("name", key),
			"category": category,
			"atlas": Vector2i(int(atlas[0]), int(atlas[1])),
		})
		_walkable.append(0 if category == CAT_BLOCKING else 1)
		var speed: float = float(entry.get("speed", DEFAULT_ROAD_SPEED if category == CAT_ROAD else 1.0))
		_speeds.append(speed)

	var rows: Array = data.get("rows", [])
	_cells.resize(width * height)
	# Anything the data doesn't cover falls back to type 0 rather than crashing
	# -- a short data file should render as a small map, not as no map.
	for y in range(height):
		var row: String = String(rows[y]) if y < rows.size() else ""
		for x in range(width):
			var ch: String = row.substr(x, 1) if x < row.length() else ""
			_cells[y * width + x] = int(index_of.get(ch, 0))

## Builds the tile layer. **One node, 20,736 `set_cell` calls** -- set_cell is a
## dictionary write into the layer's own storage, not a scene-tree operation,
## so this costs milliseconds and adds exactly one child to the tree.
func _build_layer() -> void:
	terrain_layer = TileMapLayer.new()
	terrain_layer.name = "Terrain"
	terrain_layer.tile_set = _build_tileset()
	# Nearest, because the atlas is packed edge-to-edge at exactly the cell
	# size: linear filtering would sample across the seam into the neighbouring
	# tile. The cost is some shimmer at extreme zoom-out, which is the cheaper
	# of the two artefacts.
	terrain_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(terrain_layer)
	for y in range(height):
		for x in range(width):
			var t: Dictionary = _types[_cells[y * width + x]]
			terrain_layer.set_cell(Vector2i(x, y), 0, t["atlas"])

## Slices the 4x4 sheet into a single 256x256 atlas at exactly CELL_SIZE per
## tile, resampling each 305px tile down once at load.
##
## The alternative -- pointing the TileSet at the 1254px sheet and scaling the
## layer by 64/305 -- keeps more source detail but minifies on the GPU every
## frame with no mipmaps, which shimmers badly while panning. Resampling once
## with Lanczos is sharper, and it also lets the atlas be gutter-free so the
## tile regions are a plain 64px grid.
func _build_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(CELL_SIZE, CELL_SIZE)
	var source := TileSetAtlasSource.new()
	source.texture = _build_atlas_texture()
	source.texture_region_size = Vector2i(CELL_SIZE, CELL_SIZE)
	for row in range(SHEET_ROWS):
		for col in range(SHEET_COLUMNS):
			source.create_tile(Vector2i(col, row))
	ts.add_source(source, 0)
	return ts

## Average colour per terrain type, for the minimap. **Sampled from the atlas**
## rather than written down: a hand-kept colour table is one more thing to
## update when the art changes, and a minimap that disagrees with the ground is
## worse than no minimap. Resizing a tile to 1x1 is the cheapest possible
## average.
func _sample_map_colors(atlas: Image) -> void:
	_map_colors.resize(_types.size())
	for i in range(_types.size()):
		var a: Vector2i = _types[i]["atlas"]
		var pixel: Image = atlas.get_region(
			Rect2i(a.x * CELL_SIZE, a.y * CELL_SIZE, CELL_SIZE, CELL_SIZE))
		pixel.resize(1, 1, Image.INTERPOLATE_BILINEAR)
		_map_colors[i] = pixel.get_pixel(0, 0)

func minimap_color_at(cell: Vector2i) -> Color:
	var i: int = type_index_at(cell)
	if i < 0 or i >= _map_colors.size():
		return Color.BLACK
	return _map_colors[i]

func _build_atlas_texture() -> Texture2D:
	var sheet: Texture2D = load(TILESET_PATH)
	if sheet == null:
		push_error("WorldMap: terrain sheet missing at %s" % TILESET_PATH)
		return null
	var src: Image = sheet.get_image()
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	var out := Image.create_empty(
		SHEET_COLUMNS * CELL_SIZE, SHEET_ROWS * CELL_SIZE, false, Image.FORMAT_RGBA8)
	for row in range(SHEET_ROWS):
		for col in range(SHEET_COLUMNS):
			var region := Rect2i(
				SHEET_MARGIN + col * (SHEET_TILE + SHEET_SEPARATION),
				SHEET_MARGIN + row * (SHEET_TILE + SHEET_SEPARATION),
				SHEET_TILE, SHEET_TILE)
			var piece: Image = src.get_region(region)
			piece.resize(CELL_SIZE, CELL_SIZE, Image.INTERPOLATE_LANCZOS)
			out.blit_rect(piece, Rect2i(0, 0, CELL_SIZE, CELL_SIZE),
				Vector2i(col * CELL_SIZE, row * CELL_SIZE))
	_sample_map_colors(out)
	return ImageTexture.create_from_image(out)

# ---------------- Queries ----------------------------------------------------
#
# Everything takes an *engine-space* point (the space workers, tokens and the
# villain already live in) and converts internally. Callers never do the offset
# arithmetic themselves -- that's the one thing about this coordinate system
# that would be easy to get subtly, invisibly wrong.

func cell_at(point: Vector2) -> Vector2i:
	var local: Vector2 = point - origin_px
	return Vector2i(floori(local.x / CELL_SIZE), floori(local.y / CELL_SIZE))

func cell_origin_px(cell: Vector2i) -> Vector2:
	return origin_px + Vector2(cell) * float(CELL_SIZE)

func cell_centre_px(cell: Vector2i) -> Vector2:
	return cell_origin_px(cell) + Vector2.ONE * (CELL_SIZE * 0.5)

func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height

## The whole map as an engine-space rectangle -- what the camera clamps to.
func bounds_px() -> Rect2:
	return Rect2(origin_px, Vector2(width, height) * float(CELL_SIZE))

func type_index_at(cell: Vector2i) -> int:
	if not in_bounds(cell):
		return -1
	return _cells[cell.y * width + cell.x]

## **Out of bounds is not walkable**, which is what stops anything walking off
## the edge of the world without a second clamp somewhere else.
func is_walkable_cell(cell: Vector2i) -> bool:
	if not in_bounds(cell):
		return false
	return _walkable[_cells[cell.y * width + cell.x]] == 1

func is_walkable(point: Vector2) -> bool:
	return is_walkable_cell(cell_at(point))

## Movement multiplier at a point: 1.0 on open ground, more on a road. Blocking
## cells report 1.0 rather than 0 -- refusing to enter them is is_walkable's
## job, and a zero here would silently freeze anything that got in somehow.
func speed_multiplier(point: Vector2) -> float:
	var cell := cell_at(point)
	if not in_bounds(cell):
		return 1.0
	return _speeds[_cells[cell.y * width + cell.x]]

## Which of WORLD_MAP_PLAN §6's four danger bands a point falls in.
## `{band, name}`. **Last match wins**, so the data file can read as "the whole
## map is contested wilderness, except..." -- see the BANDS table in
## tools/make_world_map.gd.
func band_at(point: Vector2) -> Dictionary:
	var cell: Vector2i = cell_at(point)
	var found: Dictionary = {"band": 2, "name": "Contested Wilderness"}
	for entry in bands:
		if (entry["rect"] as Rect2i).has_point(cell):
			found = entry
	return found

func terrain_name(point: Vector2) -> String:
	var i: int = type_index_at(cell_at(point))
	return String(_types[i]["name"]) if i >= 0 else "The void"

func category_at(point: Vector2) -> String:
	var i: int = type_index_at(cell_at(point))
	return String(_types[i]["category"]) if i >= 0 else CAT_BLOCKING

## Slides `from` toward `from + motion`, refusing blocking cells but sliding
## along them rather than sticking. Shared by everything that moves on the world
## map, so "how blocking feels" is one implementation: the villain, the wolf and
## the deer all route around a mountain the same way.
##
## The axis retries are what make a wall feel like a wall instead of flypaper --
## walking a diagonal into a north-south cliff should slide you along it, not
## stop you dead.
func slide(from: Vector2, motion: Vector2) -> Vector2:
	if motion == Vector2.ZERO:
		return from
	var target: Vector2 = from + motion
	if is_walkable(target):
		return target
	var x_only: Vector2 = from + Vector2(motion.x, 0.0)
	if motion.x != 0.0 and is_walkable(x_only):
		return x_only
	var y_only: Vector2 = from + Vector2(0.0, motion.y)
	if motion.y != 0.0 and is_walkable(y_only):
		return y_only
	return from

## Nearest walkable cell centre to `point`, searched outward in rings. Used to
## rescue anything that asks for a destination inside a mountain -- roamers
## picking a random point, mostly. Gives up and returns `point` after
## `max_rings`, because a caller that gets a blocked answer will just pick again
## next frame, and an unbounded search over 20,736 cells would not.
func nearest_walkable(point: Vector2, max_rings: int = 6) -> Vector2:
	if is_walkable(point):
		return point
	var origin: Vector2i = cell_at(point)
	for ring in range(1, max_rings + 1):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if absi(dx) != ring and absi(dy) != ring:
					continue  # only the ring's rim; the inside was searched already
				var c := origin + Vector2i(dx, dy)
				if is_walkable_cell(c):
					return cell_centre_px(c)
	return point
