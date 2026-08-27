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

## char -> which sheet cell draws it, category, and how fast you cross it.
##
## **`cell` is `[row, col]` inside that sheet's own 4x4**, not an atlas
## coordinate. Atlas coordinates are derived from the sheet order at load
## (`WorldMap.atlas_coord_for`), so a sheet added or reordered re-derives every
## one of these instead of silently repainting the map -- which is exactly what
## happened when the atlas grew from one sheet to seven and this table still
## held 4x4 coordinates.
##
## `group` is **connectivity**: which cells count as neighbours for the bitmask.
## `draws` is **art**: which connection table supplies the tile. They are
## deliberately different keys, because cobble and dirt share the group `road`
## (a track meeting a road forms a junction on both sides) while each draws from
## its own sheet -- TERRAIN_SPEC section 4.
const LEGEND := {
	# --- the R1 snow sheet, unchanged ground ---------------------------------
	"g": {"sheet": "snow", "cell": [0, 0], "category": "ground", "name": "Frozen grass"},
	"s": {"sheet": "snow", "cell": [1, 0], "category": "ground", "name": "Snow scrub"},
	"S": {"sheet": "snow", "cell": [2, 0], "category": "ground", "name": "Stony snow-grass"},
	"w": {"sheet": "snow", "cell": [3, 0], "category": "ground", "name": "Deep snow"},
	"d": {"sheet": "snow", "cell": [0, 1], "category": "ground", "name": "Bare dirt"},
	"D": {"sheet": "snow", "cell": [1, 1], "category": "ground", "name": "Snow-edged dirt"},   # transition tile -- see _paint_lordship; do not bulk-fill with it
	"b": {"sheet": "snow", "cell": [3, 1], "category": "ground", "name": "Log-strewn dirt"},
	"e": {"sheet": "snow", "cell": [0, 3], "category": "ground", "name": "Patchy snow"},
	"r": {"sheet": "snow", "cell": [2, 3], "category": "ground", "name": "Sealed ritual ground"},
	"B": {"sheet": "snow", "cell": [3, 3], "category": "ground", "name": "Bone-strewn ground"},
	"m": {"sheet": "snow", "cell": [3, 2], "category": "blocking", "name": "Rocky scree"},
	"i": {"sheet": "snow", "cell": [1, 3], "category": "blocking", "name": "Frozen water"},

	# --- roads: one group, two sheets ----------------------------------------
	"c": {"sheet": "snow", "cell": [0, 2], "category": "road", "speed": 1.35,
		"name": "Mossy cobblestone", "group": "road", "draws": "road_cobble"},
	"C": {"sheet": "snow", "cell": [1, 2], "category": "road", "speed": 1.35,
		"name": "Cobblestone road", "group": "road", "draws": "road_cobble"},
	"k": {"sheet": "snow", "cell": [2, 2], "category": "road", "speed": 1.2,
		"name": "Snow-covered cobbles", "group": "road", "draws": "road_cobble"},
	"t": {"sheet": "snow", "cell": [2, 1], "category": "road", "speed": 1.2,
		"name": "Worn track", "group": "road", "draws": "path_dirt"},

	# --- TERRAIN_SPEC section 5's extended legend ----------------------------
	"~": {"sheet": "water_ice", "cell": [0, 0], "category": "blocking",
		"name": "Open water", "group": "water", "draws": "water"},
	"≈": {"sheet": "water_ice", "cell": [0, 1], "category": "ground", "speed": 0.7,
		"name": "Shallows / ford"},
	"=": {"sheet": "water_ice", "cell": [2, 2], "category": "road", "speed": 1.2,
		"name": "Bridge"},
	"I": {"sheet": "water_ice", "cell": [0, 2], "category": "ground", "speed": 0.85,
		"name": "Ice sheet", "group": "ice", "draws": "ice"},
	"^": {"sheet": "rock_ruins", "cell": [1, 0], "category": "blocking",
		"name": "Cliff", "group": "cliff", "draws": "cliff"},
	",": {"sheet": "marsh_corrupt", "cell": [0, 2], "category": "ground", "speed": 0.6,
		"name": "Marsh"},
	"f": {"sheet": "marsh_corrupt", "cell": [2, 2], "category": "ground",
		"name": "Plowed farmland"},
	"F": {"sheet": "marsh_corrupt", "cell": [2, 3], "category": "ground",
		"name": "Stubble field"},
	"x": {"sheet": "marsh_corrupt", "cell": [3, 1], "category": "ground", "speed": 0.9,
		"name": "Corrupted ground"},
	"X": {"sheet": "marsh_corrupt", "cell": [3, 0], "category": "ground",
		"name": "Charred ground"},
	"R": {"sheet": "rock_ruins", "cell": [3, 1], "category": "ground", "speed": 0.9,
		"name": "Stone ruins"},
	"o": {"sheet": "rock_ruins", "cell": [0, 0], "category": "ground", "speed": 0.8,
		"name": "Boulder field"},
	"O": {"sheet": "rock_ruins", "cell": [0, 2], "category": "blocking", "name": "Boulder"},
	# Forest floor for both, per TERRAIN_SPEC section 6b: T and u share a ground
	# tile and differ by the canopy drawn over them, which is P2's. **No cell on
	# the map uses either yet** -- they are legend entries so the generation pass
	# that plants forests is a data change rather than a schema change.
	"T": {"sheet": "marsh_corrupt", "cell": [1, 0], "category": "blocking",
		"name": "Dense forest"},
	"u": {"sheet": "marsh_corrupt", "cell": [1, 0], "category": "ground", "speed": 0.85,
		"name": "Open woodland"},
}

## Which sheet cell draws each of the sixteen neighbour combinations, per
## connection group. **Transcribed from `docs/design/TERRAIN_MASKS.md`**, which
## was read off the sheets by hand -- do not re-derive it from pixels, which is
## what failed on the first attempt at P1.
##
## `cell` is `[row, col]` in the named sheet, exactly as the doc states it, so
## this table can be diffed against the doc line by line.
##
## **The sheets are not complete 16-piece sets.** Missing pieces are supplied as
## `flip_h` / `flip_v` / `transpose` of ones that exist. Entries carrying `note`
## are the approximations TERRAIN_SPEC section 4's 16-tile caveat already
## allows; the note travels into the JSON so nobody later mistakes an
## approximation for art that was drawn for that case.
const CONNECTIONS := {
	"road_cobble": {
		"sheet": "road_cobble",
		"masks": {
			"0": {"cell": [0, 1], "note": "~ stub; isolated road cells should not be generated"},
			"1": {"cell": [0, 1], "flip_v": true},
			"2": {"cell": [2, 0]},
			"3": {"cell": [2, 1], "flip_h": true},
			"4": {"cell": [0, 1]},
			"5": {"cell": [1, 1]},
			"6": {"cell": [1, 2], "flip_h": true},
			"7": {"cell": [3, 1], "flip_h": true},
			"8": {"cell": [0, 2]},
			"9": {"cell": [2, 1]},
			"10": {"cell": [2, 2]},
			"11": {"cell": [2, 3]},
			"12": {"cell": [1, 2]},
			"13": {"cell": [3, 1]},
			"14": {"cell": [2, 3], "flip_v": true},
			"15": {"cell": [1, 3]},
		},
	},
	"path_dirt": {
		"sheet": "path_dirt",
		"masks": {
			"0": {"cell": [2, 1]},
			"1": {"cell": [1, 0]},
			"2": {"cell": [0, 2], "flip_h": true},
			"3": {"cell": [1, 2], "flip_v": true},
			"4": {"cell": [0, 1]},
			"5": {"cell": [1, 1]},
			"6": {"cell": [1, 2]},
			"7": {"cell": [1, 3]},
			"8": {"cell": [0, 2]},
			"9": {"cell": [0, 3], "flip_v": true},
			"10": {"cell": [2, 2]},
			"11": {"cell": [2, 3]},
			"12": {"cell": [0, 3]},
			"13": {"cell": [3, 1]},
			"14": {"cell": [2, 3], "flip_v": true},
			"15": {"cell": [3, 2]},
		},
	},
	"water": {
		"sheet": "water_ice",
		"masks": {
			"15": {"cell": [0, 0]},
			"14": {"cell": [1, 0]},
			"11": {"cell": [1, 0], "flip_v": true},
			"7": {"cell": [1, 1]},
			"13": {"cell": [1, 1], "flip_h": true},
			"6": {"cell": [1, 2]},
			"12": {"cell": [1, 3]},
			"3": {"cell": [1, 2], "flip_v": true},
			"9": {"cell": [1, 3], "flip_v": true},
			"5": {"cell": [2, 0]},
			"10": {"cell": [2, 0], "transpose": true},
			"1": {"cell": [2, 0], "note": "~ river runs off the map edge; the straight is right"},
			"4": {"cell": [2, 0], "note": "~ river runs off the map edge; the straight is right"},
			"2": {"cell": [2, 0], "transpose": true, "note": "~ as above, E-W"},
			"8": {"cell": [2, 0], "transpose": true, "note": "~ as above, E-W"},
			"0": {"cell": [3, 3], "note": "~ no all-round shore exists; do not generate single water cells"},
		},
	},
	"ice": {
		"sheet": "water_ice",
		"masks": {
			"15": {"cell": [0, 2]},
			"14": {"cell": [3, 0]},
			"11": {"cell": [3, 0], "flip_v": true},
			"7": {"cell": [3, 1]},
			"13": {"cell": [3, 1], "flip_h": true},
			"6": {"cell": [3, 2]},
			"12": {"cell": [3, 2], "flip_h": true},
			"3": {"cell": [3, 2], "flip_v": true},
			"9": {"cell": [3, 2], "flip_h": true, "flip_v": true},
			"5": {"cell": [0, 2], "note": "~ no ice-channel art; frozen lakes are convex and never make one"},
			"10": {"cell": [0, 2], "note": "~ no ice-channel art; frozen lakes are convex and never make one"},
			"0": {"cell": [0, 2], "note": "~ single ice cell; not generated"},
			"1": {"cell": [0, 2], "note": "~ ice stub; not generated"},
			"2": {"cell": [0, 2], "note": "~ ice stub; not generated"},
			"4": {"cell": [0, 2], "note": "~ ice stub; not generated"},
			"8": {"cell": [0, 2], "note": "~ ice stub; not generated"},
		},
	},
	"cliff": {
		"sheet": "rock_ruins",
		"masks": {
			"0": {"cell": [1, 0]},
			"10": {"cell": [1, 1]},
			"5": {"cell": [1, 2]},
			"9": {"cell": [2, 0]},
			"3": {"cell": [2, 1]},
			"12": {"cell": [2, 0], "flip_v": true, "note": "~ inner corner approximated"},
			"6": {"cell": [2, 1], "flip_v": true, "note": "~ inner corner approximated"},
			"2": {"cell": [1, 1], "note": "~ ridge end; the face continues"},
			"8": {"cell": [1, 1], "note": "~ ridge end; the face continues"},
			"1": {"cell": [1, 2], "note": "~ ridge end; the face continues"},
			"4": {"cell": [1, 2], "note": "~ ridge end; the face continues"},
			"11": {"cell": [1, 1], "note": "~ tee approximated by the E-W face"},
			"14": {"cell": [1, 1], "note": "~ tee approximated by the E-W face"},
			"7": {"cell": [1, 2], "note": "~ tee approximated by the N-S face"},
			"13": {"cell": [1, 2], "note": "~ tee approximated by the N-S face"},
			# **Plateau top, not a cliff face.** A ridge thicker than one cell has an
			# interior, and its interior is snow you walk on top of -- the lone crag
			# drew a south face on every one of them, so a 7-wide ridge rendered as a
			# grid of crags. Changed 2026-08-27 after P1 showed exactly that.
			"15": {"sheet": "snow", "cell": [3, 0]},
		},
	},
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
	# **Cliff, not scree.** R1 flagged rocky scree as the one terrain
	# placeholder -- "a real cliff/mountain tile belongs in the art brief" --
	# and the rock sheet closes it. The two gaps are untouched: a wall with a
	# door is a route decision, a wall without one is a smaller map.
	#
	# Only THIS range converts. The map rim, the western range, the northern
	# range and the spur stay `m`, and `m` stays **blocking** -- TERRAIN_SPEC
	# section 5 retires scree to walkable decoration once cliffs are the real
	# wall, but the rim is made of scree, and a walkable rim is a hole in the
	# world. Converting the rest is a generation pass, which this is not.
	for y in range(20, 132):
		if (y >= GAP_N_Y and y <= GAP_N_Y + 10) or (y >= 96 and y <= 102):
			continue
		for x in range(RIDGE_X, RIDGE_X + 7):
			grid[y][x] = "^"
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

## Frozen lakes. **Walkable ice at 0.85, not blocking** (TERRAIN_SPEC section 6):
## a frozen lake you can cross is a shortcut with a flavour of risk; one you
## cannot is a hole in the map. If ice-breaking is ever wanted it is an R3+
## hazard, not terrain.
##
## Ellipses, which matters more than it looks: the ice connection set has shore
## pieces for the four sides and the four outer corners and nothing else, so a
## convex blob is exactly what the art can draw. A concave lake would ask for an
## inner corner that does not exist -- the same constraint the cliff outlines
## are held to.
func _paint_water() -> void:
	_ellipse(66, 96, 9, 6, "I")
	_ellipse(112, 28, 6, 4, "I")

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
		"connections": CONNECTIONS,
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

