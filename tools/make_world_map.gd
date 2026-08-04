extends SceneTree
## Generates `data/world_map.json` -- the fixed 144x144 terrain layout.
##
##   godot --headless --path . -s res://tools/make_world_map.gd
##
## **Why a generator and not hand-authored data.** 20,736 cells is too many to
## type and too few to be worth a procgen system, and the layout is *fixed* for
## R1 (shuffling is R4). So the layout is expressed once, here, as the regions
## and roads WORLD_MAP_PLAN §4 describes, and baked into a data file the game
## loads. Same arrangement as tools/make_deer_sprite.gd: the generator is kept
## in the repo so the artefact stays tweakable, and nothing depends on it at
## runtime -- only on its output.
##
## The runtime therefore still has **no layout knowledge in GDScript**: WorldMap
## reads the JSON's legend and rows and knows nothing about where the village is.
## Re-run this after editing, and commit the JSON.
##
## Deliberately free of autoloads and `class_name` types: a `-s` script compiles
## before the autoloads register, so referencing EventBus or SettlementGrid here
## would fail to compile.

const OUT_PATH := "res://data/world_map.json"

const W := 144
const H := 144

## The settlement's 10x8 grid sits with its (0,0) cell here. West of centre and
## a little north of it, in the rough forest WORLD_MAP_PLAN §4 puts the
## Necromancer in -- outside the lord's patrol coverage, a long way from the
## Old Road.
const LAIR_ORIGIN := Vector2i(18, 56)
const SETTLEMENT_W := 10
const SETTLEMENT_H := 8

## Guaranteed-walkable, starts-revealed band around the lair. Sized to contain
## every seeded resource node and every roamer rectangle ResourceField and
## CombatSystem build off the settlement grid -- the forest at +12 cells east,
## the far grave at +15, the grove at -3 west, the deposit at +10 south, and the
## deer's -3..+13 wander box. If any of those move, widen this.
const BAND := Rect2i(12, 50, 26, 26)

## West edge of the central ridge -- the frontier of the villain's valley, and
## the thing "lair -> edge of local territory" is measured to. See
## _paint_mountains() for why it is this far out.
const RIDGE_X := 74

## The northern pass through the ridge. **Deliberately not on the lair's
## latitude (y 60).** It used to sit at y 56-66, which put the door directly in
## front of the Necromancer's front gate and made the ridge free to cross: the
## route east was a straight line and the wall may as well not have been there.
## At y 36 you have to walk *to* the pass, which is what turns a wall into a
## route decision -- and it is most of what buys WORLD_MAP_PLAN §3's 2-4 minute
## lair-to-village target on a map only 144 cells wide.
const GAP_N_Y := 36

## The village core's west edge. Pushed east by the R1c tuning pass for the same
## reason the ridge moved: WORLD_MAP_PLAN §3 wants the lair-to-village trip to
## take 2-4 minutes, and the only geometry that buys that on a 144-cell map is
## putting the two powers at opposite ends of it.
const VILLAGE_X := 120
const VILLAGE_Y := 55

## char -> tile in the 4x4 sheet, category, and how fast you cross it.
const LEGEND := {
	"g": {"tile": [0, 0], "category": "ground", "name": "Frozen grass"},
	"s": {"tile": [0, 1], "category": "ground", "name": "Snow scrub"},
	"S": {"tile": [0, 2], "category": "ground", "name": "Stony snow-grass"},
	"w": {"tile": [0, 3], "category": "ground", "name": "Deep snow"},
	"d": {"tile": [1, 0], "category": "ground", "name": "Bare dirt"},
	"D": {"tile": [1, 1], "category": "ground", "name": "Snow-edged dirt"},   # transition tile -- see _paint_lordship; do not bulk-fill with it
	"t": {"tile": [1, 2], "category": "road", "speed": 1.2, "name": "Worn track"},
	"b": {"tile": [1, 3], "category": "ground", "name": "Log-strewn dirt"},
	"c": {"tile": [2, 0], "category": "road", "speed": 1.35, "name": "Mossy cobblestone"},
	"C": {"tile": [2, 1], "category": "road", "speed": 1.35, "name": "Cobblestone road"},
	"k": {"tile": [2, 2], "category": "road", "speed": 1.2, "name": "Snow-covered cobbles"},
	"m": {"tile": [2, 3], "category": "blocking", "name": "Rocky scree"},
	"e": {"tile": [3, 0], "category": "ground", "name": "Patchy snow"},
	"i": {"tile": [3, 1], "category": "blocking", "name": "Frozen water"},
	"r": {"tile": [3, 2], "category": "ground", "name": "Sealed ritual ground"},
	"B": {"tile": [3, 3], "category": "ground", "name": "Bone-strewn ground"},
}

## WORLD_MAP_PLAN §6's four danger bands, as **data only**. Nothing consumes
## these yet -- they are the hook R2's encounter and loot tables plug into, and
## for now they drive one HUD readout so the player always knows how deep they
## are.
##
## **Later entries win.** The list reads as "the whole map is contested
## wilderness, except..." which is both the shortest way to write it and the
## right default: anywhere the design has not claimed is Band 2.
const BANDS := [
	{"band": 2, "name": "Contested Wilderness", "rect": [0, 0, W, H]},
	{"band": 1, "name": "Lair Surroundings", "rect": [BAND.position.x, BAND.position.y, BAND.size.x, BAND.size.y]},
	{"band": 3, "name": "The Lord's Lands", "rect": [100, 45, 41, 46]},
	{"band": 3, "name": "Church and Cemetery", "rect": [VILLAGE_X - 2, 98, 15, 14]},
	{"band": 3, "name": "The Sealed Ground", "rect": [12, 100, 23, 23]},
	{"band": 4, "name": "The Cursed Battlefield", "rect": [58, 12, 12, 10]},
	{"band": 4, "name": "The Drowned Ruin", "rect": [60, 90, 14, 13]},
	{"band": 4, "name": "The Outlaw Cave", "rect": [9, 24, 9, 9]},
	{"band": 4, "name": "The Old Crypt", "rect": [96, 118, 11, 10]},
]

var grid: Array = []   # Array[PackedStringArray-ish] -- Array of Array[String]
var rng := RandomNumberGenerator.new()

func _initialize() -> void:
	rng.seed = 20260803   # fixed: the layout must be identical every run and every build
	_fill_base()
	_paint_north()
	_paint_lordship()
	_paint_demonologist()
	_paint_mountains()
	_paint_water()
	_paint_roads()          # last, so a road can cut through a ridge
	_clear_lair_band()      # last of all, so nothing blocks the starting area
	_write()
	quit()

# ---------------- Painting ---------------------------------------------------

func _put(x: int, y: int, ch: String) -> void:
	if x < 0 or y < 0 or x >= W or y >= H:
		return
	grid[y][x] = ch

func _pick(options: Array) -> String:
	return options[rng.randi_range(0, options.size() - 1)]

## Ground cover in **patches**, not per-cell static.
##
## Picking a variant independently per cell looked like television snow once it
## was rendered: four quite different tiles alternating every 64px, with the
## eye reading the noise instead of the terrain. Hashing a coarse patch
## coordinate makes neighbours agree, so snow gathers in drifts and stony
## ground in outcrops. The 25% break-out is what keeps the patch edges ragged
## rather than a visible 4x4 quilt.
const PATCH_CELLS := 4
const PATCH_BREAK_CHANCE := 0.25

func _patch_pick(x: int, y: int, options: Array) -> String:
	if rng.randf() < PATCH_BREAK_CHANCE:
		return _pick(options)
	var px: int = floori(float(x) / PATCH_CELLS)
	var py: int = floori(float(y) / PATCH_CELLS)
	# An explicit integer mix rather than `hash(Vector2i)`: the built-in came out
	# correlated along one axis on this data, and the map rendered as vertical
	# corduroy -- one-cell-wide bars of bare dirt running down the farmland. The
	# two large primes are the standard spatial-hash pair.
	var h: int = absi((px * 73856093) ^ (py * 19349663))
	return options[h % options.size()]

## Snow thickens northward. Purely cosmetic variation -- it is FLAVOR for a cold
## hideout, not a climate system (CLAUDE.md's climate scope call still stands;
## nothing reads these tiles for temperature, and nothing should).
func _fill_base() -> void:
	grid.clear()
	for y in range(H):
		var row: Array = []
		for x in range(W):
			var northness: float = 1.0 - float(y) / float(H)
			var options: Array = ["g", "s", "S", "e"]
			if rng.randf() < northness * 0.55:
				options = ["w", "s", "S", "w"]
			row.append(_patch_pick(x, y, options))
		grid.append(row)

## Northern Wilderness (WORLD_MAP_PLAN §4): ruins, graves, beasts. Deep snow
## with bone-strewn patches where the old graves are.
func _paint_north() -> void:
	for y in range(2, 38):
		for x in range(2, W - 2):
			if rng.randf() < 0.72:
				grid[y][x] = _patch_pick(x, y, ["w", "w", "s", "S"])
	for i in range(9):
		var cx: int = rng.randi_range(20, W - 20)
		var cy: int = rng.randi_range(8, 34)
		_blob(cx, cy, rng.randi_range(2, 4), ["B", "b", "d"])

## The human lordship, east: farms around a village core, per §5's 35x45.
func _paint_lordship() -> void:
	for y in range(45, 91):
		for x in range(100, 141):
			grid[y][x] = _patch_pick(x, y, ["d", "d", "e", "b"])
	# Village core, ~18x22 (§5). Dirt with a couple of cobbled streets rather
	# than a cobbled field -- the streets are the fast bit, not the whole town.
	for y in range(VILLAGE_Y, VILLAGE_Y + 23):
		for x in range(VILLAGE_X, VILLAGE_X + 19):
			grid[y][x] = _patch_pick(x, y, ["d", "b", "d", "e"])
	for x in range(VILLAGE_X, VILLAGE_X + 19):
		_put(x, VILLAGE_Y + 11, "c")
	for y in range(VILLAGE_Y, VILLAGE_Y + 23):
		_put(VILLAGE_X + 9, y, "c")
	# The manor's forecourt, south of the village.
	for y in range(80, 87):
		for x in range(VILLAGE_X + 4, VILLAGE_X + 15):
			grid[y][x] = "c"
	# Church and cemetery, further south again (§4's sketch).
	_blob(VILLAGE_X + 4, 104, 4, ["B", "B", "b"])
	for y in range(100, 108):
		for x in range(VILLAGE_X, VILLAGE_X + 9):
			if rng.randf() < 0.4:
				grid[y][x] = "d"

## The Demonologist's 20x20, south-west. **Sealed for v1** (rework §4 amendment
## 1): the ritual ground is here as terrain so the layout never needs rework,
## but there is no rival and nothing reads this region yet.
func _paint_demonologist() -> void:
	for y in range(100, 123):
		for x in range(12, 35):
			grid[y][x] = _patch_pick(x, y, ["d", "d", "b", "B"])
	for y in range(109, 112):
		for x in range(21, 24):
			grid[y][x] = "r"

## Rocky scree stands in for mountains -- the sheet has no mountainside tile, and
## a dark broken-rock ground reads as impassable at a glance. Flagged in
## CLAUDE.md as the one terrain placeholder.
func _paint_mountains() -> void:
	# A rim, so the edge of the world is a wall rather than an invisible fence.
	for y in range(H):
		for x in range(W):
			if x < 2 or y < 2 or x >= W - 2 or y >= H - 2:
				grid[y][x] = "m"
	# Western range: the back wall of the Necromancer's valley.
	for y in range(18, 132):
		for x in range(2, 9 + (1 if rng.randf() < 0.5 else 0)):
			grid[y][x] = "m"
	# The central ridge, dividing villain country from the lord's roads. Two
	# gaps: the eastern track at y 56-66, and a southern pass at y 96-102. The
	# gaps are the whole point -- a wall with a door is a route decision, a wall
	# without one is a smaller map.
	#
	# **Moved east from x40 to x68 by the R1c travel-time tuning pass.** This
	# ridge is the frontier of the Necromancer's valley, and WORLD_MAP_PLAN §3
	# wants "lair -> edge of local territory" to take 45-75 seconds. At x40 the
	# frontier sat 22 cells from the Throne, which is ~22s at any walk speed
	# this project can use -- a third of the target. At x68 it is ~50 cells,
	# which lands in band. The 20x20 *starting region* (§5) is unchanged; what
	# grew is the contested wilderness between it and the ridge.
	for y in range(20, 132):
		if (y >= GAP_N_Y and y <= GAP_N_Y + 10) or (y >= 96 and y <= 102):
			continue
		for x in range(RIDGE_X, RIDGE_X + 7):
			grid[y][x] = "m"
	# Northern range.
	for y in range(8, 21):
		for x in range(50, 131):
			if rng.randf() < 0.75:
				grid[y][x] = "m"
	# A spur guarding the lordship's northern approach.
	for y in range(30, 45):
		for x in range(95, 101):
			if rng.randf() < 0.8:
				grid[y][x] = "m"

## Frozen lakes. Blocking, because a necromancer who drowns in a bog is not the
## fantasy -- and because the map needs blocking that isn't all mountain.
func _paint_water() -> void:
	_ellipse(66, 96, 9, 6, "i")
	_ellipse(112, 28, 6, 4, "i")

## Roads paint last so they cut through ridges. §4's structure: the Old Road runs
## north-south, the village hangs off it at a crossroads, the Southern Road runs
## past the church, and a worn track connects the lair to the network.
func _paint_roads() -> void:
	for y in range(4, H - 4):        # Old Road
		_put(86, y, "C")
		_put(87, y, "C")
	for x in range(44, W - 4):       # Southern Road
		_put(x, 118, "c")
		_put(x, 119, "c")
	for x in range(87, VILLAGE_X + 19):   # Crossroads -> village
		_put(x, 64, "k")
		_put(x, 65, "k")
	# The lair's own track: east across the valley, north along the ridge, then
	# through the pass to the Old Road. It bends because the ridge makes it
	# bend -- a track that ignored the terrain would be a track through a
	# mountain.
	for x in range(38, 63):
		_put(x, 60, "t")
		_put(x, 61, "t")
	for y in range(GAP_N_Y + 4, 62):
		_put(62, y, "t")
		_put(63, y, "t")
	for x in range(62, 88):
		_put(x, GAP_N_Y + 4, "t")
		_put(x, GAP_N_Y + 5, "t")
	for y in range(76, 119):         # south from the lair toward the ritual ground
		_put(24, y, "t")
		_put(25, y, "t")
	for y in range(86, 119):         # manor spur down to the Southern Road
		_put(VILLAGE_X + 9, y, "C")

## The lair band is guaranteed walkable and guaranteed connected: no scree, no
## ice, nothing that could strand the settlement inside its own valley. The
## settlement's own footprint is bone-strewn ground, which is what a necromancer
## does to a yard he has held for a season.
func _clear_lair_band() -> void:
	for y in range(BAND.position.y, BAND.position.y + BAND.size.y):
		for x in range(BAND.position.x, BAND.position.x + BAND.size.x):
			if grid[y][x] == "m" or grid[y][x] == "i":
				grid[y][x] = _patch_pick(x, y, ["g", "s", "S"])
	for y in range(LAIR_ORIGIN.y, LAIR_ORIGIN.y + SETTLEMENT_H):
		for x in range(LAIR_ORIGIN.x, LAIR_ORIGIN.x + SETTLEMENT_W):
			grid[y][x] = _patch_pick(x, y, ["B", "B", "b"])

# ---------------- Shapes -----------------------------------------------------

func _blob(cx: int, cy: int, r: int, options: Array) -> void:
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if Vector2(x - cx, y - cy).length() <= float(r) + rng.randf() * 0.8:
				_put(x, y, _pick(options))

func _ellipse(cx: int, cy: int, rx: int, ry: int, ch: String) -> void:
	for y in range(cy - ry, cy + ry + 1):
		for x in range(cx - rx, cx + rx + 1):
			var dx: float = float(x - cx) / float(rx)
			var dy: float = float(y - cy) / float(ry)
			if dx * dx + dy * dy <= 1.0:
				_put(x, y, ch)

# ---------------- Output -----------------------------------------------------

func _write() -> void:
	var rows: Array = []
	for y in range(H):
		rows.append("".join(grid[y]))
	var data := {
		"_comment": "Generated by tools/make_world_map.gd -- edit that, re-run, commit this.",
		"width": W,
		"height": H,
		"lair_origin": [LAIR_ORIGIN.x, LAIR_ORIGIN.y],
		"lair_band": [BAND.position.x, BAND.position.y, BAND.size.x, BAND.size.y],
		"bands": BANDS,
		"legend": LEGEND,
		"rows": rows,
	}
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		push_error("make_world_map: cannot write %s" % OUT_PATH)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	var blocked := 0
	var road := 0
	for y in range(H):
		for x in range(W):
			var cat: String = LEGEND[grid[y][x]].get("category", "ground")
			if cat == "blocking":
				blocked += 1
			elif cat == "road":
				road += 1
	print("Wrote %s: %dx%d, %d blocking cells (%.1f%%), %d road cells." % [
		OUT_PATH, W, H, blocked, 100.0 * blocked / float(W * H), road])

