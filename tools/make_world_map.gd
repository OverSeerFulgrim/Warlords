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
## `_step_relief()` for why it is this far out.
##
## **Moved 74 -> 77 by this pass, and only after the cheaper knobs.** Routing the
## lair's track with A* instead of drawing it by hand made it straighter, so the
## measured line to the frontier now rides more 1.2-speed track and came in at
## 43s against §3's 45-75s floor. TERRAIN_SPEC §9's knob order puts river
## crossings and forest placement first -- both were already spent moving the
## river out of the valley and the treeline off the measured latitude -- and
## cliff outlines next. Three cells is the smallest change that clears the floor,
## and it buys the village trip headroom it also wanted.
const RIDGE_X := 77

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


# ---------------- Generation parameters (TERRAIN_SPEC §8) --------------------

## The human landmarks the cobble network connects, in the order it chains them.
## **This list is the signposting rule's first half** (§7 rule 1): cobble reaches
## these and nothing else, so a Band 4 site cannot be paved to simply because it
## is not here and cannot be added without someone noticing.
const HUMAN_LANDMARKS := [
	{"name": "crossroads", "cell": Vector2i(87, 64)},
	{"name": "village", "cell": Vector2i(VILLAGE_X, VILLAGE_Y + 9)},
	{"name": "manor", "cell": Vector2i(129, 83)},
	{"name": "church", "cell": Vector2i(124, 102)},
	{"name": "cemetery", "cell": Vector2i(127, 105)},
]

## Where the Old Road enters and leaves the map. The cobble trunk runs between
## them and everything else branches off it, which is what makes the network a
## network rather than spokes.
const OLD_ROAD_NORTH := Vector2i(87, 6)
const OLD_ROAD_SOUTH := Vector2i(87, 137)

## The lair's own approach: it starts at the settlement's east gate and joins
## the cobble network. §7 rule 3 keeps it -- it is the player's own track, not a
## signpost to loot.
const LAIR_GATE := Vector2i(LAIR_ORIGIN.x + SETTLEMENT_W + 1, LAIR_ORIGIN.y + 4)

# --- Hydrology (§6) ---
## The river crosses the contested wilderness **east of the ridge**, between it
## and the lordship -- which is what §6 asks for and what the first attempt got
## wrong. Sourced at (58, 20) it ran down the Necromancer's own valley, and
## since open water is blocking it became the nearest impassable thing east of
## the lair: "edge of local territory" measured the river at 33 cells instead of
## the ridge at ~50, and the row fell from 45-75s to 29s. A river in the valley
## is also just wrong -- the valley is the one region the map doc gives him.
## **East of the Old Road, west of the village.** At (98, 16)-(88, 140) the
## river crossed the Old Road's own longitude, so the trunk's A* found it
## cheaper to detour around the whole thing -- down the west side of the ridge,
## through the Necromancer's valley, and back. The "Old Road" ended up inside
## the one region the map doc gives him, and the eastern network was cut off
## from it by the ridge entirely (4 road components instead of 1).
##
## Here the river sits between the road and the lordship, which is where §4's
## structure wants it: the trunk runs clean north-south, and the run out to the
## village crosses at the bridge. The wall is on the route it is supposed to be
## a decision about.
const RIVER_SOURCE := Vector2i(108, 16)
const RIVER_MOUTH := Vector2i(98, 140)
const RIVER_WIDTH := 2
## No two crossings further apart than this, or the river stops being a route
## decision and becomes a detour tax (§6).
const MAX_CROSSING_GAP := 25

# --- Forests (§6b) ---
## Dense masses, as centre + radii. Three, deliberately: §6b asks for 2-4 and
## aims at 8-14% of the map dense, and three of this size lands at ~11%.
##
## **Placement is constrained, not decorative.** §9's stacking warning is
## explicit -- a mass against the ridge's flank quietly closes a route the
## ridge's gaps were tuned to leave open -- so every one of these is kept clear
## of both pass approaches and of the lair track's line, and the verification
## re-checks that by flood fill rather than by trusting the numbers.
const FOREST_MASSES := [
	# The treeline south-east of the lair valley: the place CombatSystem's
	# wolf-spawn comment has always claimed exists.
	#
	# **Its northern edge is held below y=80 on purpose.** At (50, 88) this mass
	# reached y=72, which put dense forest inside the latitude band
	# `measure_travel` scans for "the edge of local territory" -- so the valley's
	# frontier stopped being the ridge at ~50 cells and became a tree at 8, and
	# the row fell from 45-75s to 15s. That is TERRAIN_SPEC §9's stacking
	# warning exactly: a mass placed against a tuned route quietly redefines it.
	{"centre": Vector2i(52, 100), "rx": 20, "ry": 16, "clearings": 2},
	# The northern belt, between the northern range and the crossroads.
	{"centre": Vector2i(104, 28), "rx": 18, "ry": 14, "clearings": 1},
	# South-east, below the church and east of the river's mouth.
	#
	# **Moved off the Old Road's corridor.** At (96, 100) this mass spanned
	# x80-112, which closed the only gap between the ridge and the river that the
	# trunk could run down -- so the Old Road's A* went west of the ridge instead
	# and ran the human trunk road through the Necromancer's own valley. §9's
	# stacking warning again, and the second time a mass has quietly redefined a
	# route this pass.
	{"centre": Vector2i(118, 122), "rx": 17, "ry": 12, "clearings": 1},
]
const FOREST_FRINGE := 2
const CORRIDOR_WIDTH := 1
const CLEARING_RADIUS := 3

# --- The A* cost grid (§8) ---
const COST_ROAD := 0.5          # roads merge into a network instead of fanning out
const COST_OPEN := 1.0
const COST_WOODLAND := 1.5      # a road may clip a treeline, reluctantly
const COST_BAD_GROUND := 4.0    # marsh, boulder field: real roads bend around bad ground
const COST_IMPASSABLE := -1.0   # cliff, dense forest, unbridged river

var grid: Array = []   # Array[Array[String]]
var rng := RandomNumberGenerator.new()

## Cells reserved as river crossings before any road is laid (§8 step 3). A road
## may cross the river only here, which is what forces every road over a bridge
## hydrology already placed.
var crossings: Array = []       # Array[{cell, kind}] -- kind "bridge" | "ford"

## Set when a step refuses to continue. `quit()` in a SceneTree is deferred,
## so a hard error alone does not stop the pipeline -- the first run of the
## signposting check errored correctly and then wrote the map anyway, which is
## worse than not checking.
var aborted: bool = false

func _initialize() -> void:
	rng.seed = 20260803   # fixed: the layout must be identical every run and every build
	# **The order is load-bearing** (TERRAIN_SPEC §8). Crossings are reserved
	# before roads are laid; forests go down before anything human exists, so
	# roads route around the woods rather than the woods around the roads; and
	# dirt branches off cobble rather than radiating from the lair, so the world
	# reads as a human landscape the Necromancer is hiding inside.
	_step_base_terrain()
	_step_relief()
	_step_hydrology()
	_step_forests()
	_step_landmarks()
	_step_cobble_network()
	_step_dirt_network()
	_step_dressing()
	_step_bake()
	quit()

# ---------------- Grid helpers ------------------------------------------------

func _in(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < W and y < H

func _put(x: int, y: int, ch: String) -> void:
	if _in(x, y):
		grid[y][x] = ch

func _at(x: int, y: int) -> String:
	return grid[y][x] if _in(x, y) else ""

func _pick(options: Array) -> String:
	return options[rng.randi() % options.size()]

## Ground cover is picked in **patches, not per cell**. Independent per-cell
## picks render as television snow -- four quite different tiles alternating
## every 64px, the eye reading noise instead of terrain. A hashed patch
## coordinate makes neighbours agree, with a break-out chance so patch edges
## stay ragged rather than a visible quilt.
const PATCH_CELLS := 4
const PATCH_BREAK_CHANCE := 0.25

func _patch_pick(x: int, y: int, options: Array) -> String:
	var px: int = x / PATCH_CELLS
	var py: int = y / PATCH_CELLS
	var h: int = abs(int(px * 73856093) ^ int(py * 19349663))
	if float((h >> 8) % 1000) / 1000.0 < PATCH_BREAK_CHANCE:
		h = abs(int(x * 83492791) ^ int(y * 29840611))
	return options[h % options.size()]

## Deterministic 0..1 from a cell. Used wherever a per-cell decision must be the
## same on every boot -- **never `randf()` at load**, or the world reshuffles.
func _hash01(x: int, y: int, salt: int) -> float:
	var h: int = abs(int(x * 73856093) ^ int(y * 19349663) ^ int(salt * 83492791))
	return float(h % 100000) / 100000.0

func _ellipse_cells(centre: Vector2i, rx: int, ry: int, wobble: float = 0.0,
		salt: int = 0) -> Array:
	var out: Array = []
	for y in range(centre.y - ry - 2, centre.y + ry + 3):
		for x in range(centre.x - rx - 2, centre.x + rx + 3):
			if not _in(x, y):
				continue
			var dx: float = float(x - centre.x) / float(rx)
			var dy: float = float(y - centre.y) / float(ry)
			var limit: float = 1.0
			if wobble > 0.0:
				limit += (_hash01(x / 3, y / 3, salt) - 0.5) * wobble
			if dx * dx + dy * dy <= limit:
				out.append(Vector2i(x, y))
	return out

# ---------------- 1. Base terrain --------------------------------------------

## Regions per WORLD_MAP_PLAN §4-§5, patch-hashed ground cover. Unchanged from
## R1 in intent: this is the part that was always right.
func _step_base_terrain() -> void:
	grid.clear()
	for y in range(H):
		var row: Array = []
		for x in range(W):
			row.append(_patch_pick(x, y, ["g", "s", "S", "g"]))
		grid.append(row)

	# The Northern Wilderness: deeper snow, more stone.
	for y in range(6, 26):
		for x in range(4, W - 4):
			_put(x, y, _patch_pick(x, y, ["w", "S", "s", "w"]))
	# The Necromancer's own valley: bare, bone-strewn, cold.
	for y in range(BAND.position.y - 8, BAND.position.y + BAND.size.y + 10):
		for x in range(6, RIDGE_X - 4):
			_put(x, y, _patch_pick(x, y, ["s", "S", "e", "s"]))
	# The lord's lands: worked ground, kinder cover.
	for y in range(42, 96):
		for x in range(96, W - 4):
			_put(x, y, _patch_pick(x, y, ["g", "g", "e", "d"]))

# ---------------- 2. Relief ---------------------------------------------------

## Cliff ranges with **convex outlines** (§4's 16-tile caveat: faces and outer
## corners only, so a concave notch would request art that does not exist), and
## the central ridge keeps its two gaps.
func _step_relief() -> void:
	# A rim, so the edge of the world is a wall rather than an invisible fence.
	# Scree rather than cliff: it is the frame, not a feature, and `m` stays
	# blocking precisely because this is what it is holding up.
	for y in range(H):
		for x in range(W):
			if x < 2 or y < 2 or x >= W - 2 or y >= H - 2:
				_put(x, y, "m")
	# Western range: the back wall of the Necromancer's valley.
	for y in range(18, 132):
		for x in range(2, 9 + (1 if rng.randf() < 0.5 else 0)):
			_put(x, y, "m")
	# **The central ridge**, dividing villain country from the lord's roads, at
	# x74 with two gaps. Both numbers were won by R1's travel-time tuning and
	# neither is free to move: the ridge is what "edge of local territory" is
	# measured to, and the gaps are what make the village trip 2-4 minutes
	# rather than a straight line.
	for y in range(20, 132):
		if (y >= GAP_N_Y and y <= GAP_N_Y + 10) or (y >= 96 and y <= 102):
			continue
		for x in range(RIDGE_X, RIDGE_X + 7):
			_put(x, y, "^")
	# Northern range and the spur guarding the lordship's northern approach.
	#
	# **With a door at the Old Road's longitude.** At 75% fill a 13-row band is
	# well past the percolation threshold, so it is a solid wall in practice --
	# R1 could ignore that because it painted the road straight over the rock,
	# but an A*-routed road cannot, and the first run of this failed with "no
	# route from (87, 6) to (87, 137)". The gap is the same rule the ridge
	# taught: a wall with a door is a route decision.
	for y in range(8, 21):
		for x in range(50, 131):
			if x >= OLD_ROAD_NORTH.x - 3 and x <= OLD_ROAD_NORTH.x + 3:
				continue
			if rng.randf() < 0.75:
				_put(x, y, "m")
	for y in range(30, 45):
		for x in range(95, 101):
			if rng.randf() < 0.8:
				_put(x, y, "m")

# ---------------- 3. Hydrology ------------------------------------------------

## A river across the contested wilderness, **and its doors**.
##
## This is the ridge's lesson applied to water: a wall with a door is a route
## decision, a wall without one is a smaller map. Every crossing is reserved
## *here*, before any road exists, so step 6's A* is forced over them rather
## than inventing its own ford wherever it happens to want one.
##
## A **bridge** sits on the human road network -- fast, exposed, and what
## patrols will walk in R3. A **ford** sits in the wilderness -- slow (0.7),
## unwatched. That is WORLD_MAP_PLAN §9's roads-vs-wilderness tradeoff expressed
## as terrain instead of as a speed number.
func _step_hydrology() -> void:
	_paint_frozen_lakes()
	var path: Array = _river_path()
	for cell in path:
		for w in range(RIVER_WIDTH):
			# Blocking water. The crossings below cut back through it.
			_put(cell.x + w, cell.y, "~")

	# Crossings, at explicit latitudes rather than fractions of the course.
	#
	# **Spacing is a rule, not a preference** (§6): no two adjacent crossings
	# more than ~25 cells apart, or the river stops being a route decision and
	# starts being a detour tax. The first version placed them at 30/55/80% of
	# the course, which on a 124-row river is 31 cells apart -- over the line.
	#
	# The **bridge sits at y=64 because that is where the human road crosses**:
	# the crossroads-to-village run. Fast and exposed, and what patrols will
	# walk in R3. The two fords are wilderness crossings -- slow at 0.7,
	# unwatched. That is WORLD_MAP_PLAN §9's tradeoff as terrain rather than as
	# a speed number.
	crossings.clear()
	var wanted: Array = [
		{"y": 42, "kind": "ford"},
		{"y": 64, "kind": "bridge"},
		{"y": 88, "kind": "ford"},
	]
	for entry in wanted:
		var cell: Vector2i = path[clampi(int(entry["y"]) - RIVER_SOURCE.y, 0, path.size() - 1)]
		crossings.append({"cell": cell, "kind": entry["kind"]})
		for w in range(RIVER_WIDTH):
			# A ford is shallows you wade; a bridge is a road over water. Both
			# are walkable, which is the entire point of reserving them.
			_put(cell.x + w, cell.y, "≈" if entry["kind"] == "ford" else "=")

## Two frozen lakes, **walkable ice at 0.85** (§6): a frozen lake you can cross
## is a shortcut with a flavour of risk; one you cannot is a hole in the map.
##
## Ellipses, and that matters more than it looks: the ice connection set has
## shore pieces for the four sides and the four outer corners and nothing else,
## so a convex blob is exactly what the art can draw. A concave lake would ask
## for an inner corner that does not exist -- the same constraint the cliff
## outlines are held to.
func _paint_frozen_lakes() -> void:
	for spec in [{"c": Vector2i(66, 96), "rx": 9, "ry": 6},
			{"c": Vector2i(112, 28), "rx": 6, "ry": 4}]:
		for cell in _ellipse_cells(spec["c"], spec["rx"], spec["ry"]):
			if _at(cell.x, cell.y) in ["^", "m"]:
				continue   # a lake does not climb the ridge
			_put(cell.x, cell.y, "I")

## The river's course: a wandering north-south line, deterministic per cell so
## the same river appears on every boot.
## **A meander around its line, not a random walk.** The first version did
## `x += step + noise`, which accumulates: over 124 rows the course wandered
## more than ten cells off its intended line, crossed the Old Road's longitude
## and sealed the trunk route entirely ("no route from (87, 6) to (87, 137)").
## Two sine terms plus a small per-row jitter give a river that bends without
## ever leaving the corridor it was placed in.
func _river_path() -> Array:
	var out: Array = []
	var span: float = float(RIVER_MOUTH.y - RIVER_SOURCE.y)
	for y in range(RIVER_SOURCE.y, RIVER_MOUTH.y + 1):
		var t: float = float(y - RIVER_SOURCE.y) / span
		var line: float = lerpf(float(RIVER_SOURCE.x), float(RIVER_MOUTH.x), t)
		var meander: float = sin(float(y) * 0.11) * 3.0 + sin(float(y) * 0.047) * 2.0
		var x: float = line + meander + (_hash01(0, y, 7) - 0.5) * 1.2
		var cell := Vector2i(clampi(int(round(x)), 3, W - 5), y)
		# The river never runs through the ridge -- rivers go around rock, and
		# a river inside a cliff would be a hole in the wall the ridge exists
		# to be.
		if cell.x >= RIDGE_X - 2 and cell.x <= RIDGE_X + 8:
			cell.x = RIDGE_X - 3
			x = float(cell.x)
		out.append(cell)
	return out

# ---------------- 4. Forests --------------------------------------------------

## Dense masses, their soft fringes, the corridors carved through them and the
## clearings sealed inside (§6b).
##
## **Before landmarks and roads, deliberately.** Forests are terrain the human
## world routes *around*; laying them after the roads would mean painting trees
## over a road and then pretending the road went around them.
func _step_forests() -> void:
	for i in range(FOREST_MASSES.size()):
		_build_mass(FOREST_MASSES[i], i)

func _build_mass(spec: Dictionary, salt: int) -> void:
	var centre: Vector2i = spec["centre"]
	var dense: Array = []
	for cell in _ellipse_cells(centre, spec["rx"], spec["ry"], 0.35, salt * 13 + 3):
		# Trees do not grow on rock, in water, or on anything human. Checking
		# rather than overwriting is what keeps a mass from quietly swallowing
		# the ridge's gap or a reserved crossing.
		if _at(cell.x, cell.y) in ["^", "m", "~", "≈", "=", "I"]:
			continue
		_put(cell.x, cell.y, "T")
		dense.append(cell)

	# The ragged edge every mass wears: 1-3 cells of open woodland, so a forest
	# has a silhouette instead of a hedge-maze border, and walking a treeline
	# reads differently from walking open snow.
	for cell in dense:
		for dy in range(-FOREST_FRINGE, FOREST_FRINGE + 1):
			for dx in range(-FOREST_FRINGE, FOREST_FRINGE + 1):
				var n := Vector2i(cell.x + dx, cell.y + dy)
				if _at(n.x, n.y) == "" or _at(n.x, n.y) in ["T", "^", "m", "~", "≈", "=", "I"]:
					continue
				if _hash01(n.x, n.y, salt * 7 + 5) < 0.55:
					_put(n.x, n.y, "u")

	_carve_corridor(spec, dense, salt)
	for c in range(int(spec.get("clearings", 1))):
		_carve_clearing(spec, salt * 31 + c)

## A 1-2 cell lane of open woodland cut through the mass, west to east.
##
## **A corridor is not a road**: no speed bonus beyond `u` being better than
## impassable, no signposting, no patrol exposure. It is simply the way
## through, and finding it is navigation the open snow cannot offer. The
## wall-with-a-door rule applies verbatim -- every dense mass must be crossable.
func _carve_corridor(spec: Dictionary, dense: Array, salt: int) -> void:
	if dense.is_empty():
		return
	var centre: Vector2i = spec["centre"]
	var rx: int = spec["rx"]
	# A gentle S rather than a straight line, so the way through has to be
	# found rather than seen from outside.
	for i in range(-rx - FOREST_FRINGE - 1, rx + FOREST_FRINGE + 2):
		var x: int = centre.x + i
		var drift: int = int(round(sin(float(i) * 0.22) * 3.0))
		var y: int = centre.y + drift
		for w in range(CORRIDOR_WIDTH + 1):
			if _at(x, y + w) in ["T", "u"]:
				_put(x, y + w, "u")

## An interior clearing: ordinary ground inside the trees, reachable **only**
## through one corridor.
##
## This is the map's first genuinely isolated location type and what the loot
## layer has been waiting for -- R2a's wolf den lives in one. It satisfies
## "found, not followed" *structurally*: there is no line on the ground because
## there is no ground until you are through the trees.
func _carve_clearing(spec: Dictionary, salt: int) -> void:
	var centre: Vector2i = spec["centre"]
	var angle: float = _hash01(centre.x, centre.y, salt) * TAU
	var reach: float = float(mini(spec["rx"], spec["ry"])) * 0.55
	var at := Vector2i(
		centre.x + int(round(cos(angle) * reach)),
		centre.y + int(round(sin(angle) * reach)))
	var cells: Array = []
	for cell in _ellipse_cells(at, CLEARING_RADIUS, CLEARING_RADIUS - 1, 0.2, salt):
		if _at(cell.x, cell.y) != "T":
			continue   # only carve out of dense forest, never out of the world
		_put(cell.x, cell.y, _patch_pick(cell.x, cell.y, ["g", "s", "S"]))
		cells.append(cell)
	if cells.is_empty():
		return
	# **Exactly one mouth, and it has to be findable.** Zero is a softlock, two
	# is a crossroads -- and a crossroads inside a wood is just a road, which is
	# the one thing a clearing must not be.
	#
	# **Two cells wide, not one** (2026-08-30). The first version carved a
	# single-cell lane, which is topologically a mouth and practically a wall:
	# with the canopy drawn over both sides of it, a playtester walked the
	# perimeter of the valley den and reported it "literally impossible to
	# reach". It was reachable -- flood fill proved it, and so did an A* from
	# the lair -- through one 64px gap in six cells of unbroken pine. A door
	# nobody can find is not a door.
	#
	# Two is still one mouth (the pair is a single connected group of woodland,
	# so the clearing rule holds) and still inside TERRAIN_SPEC §6b's "1-2 cell
	# lanes". `verify_terrain` now asserts the width for any clearing holding a
	# site, so this cannot narrow again unnoticed.
	var target := Vector2i(centre.x, centre.y)
	var step := Vector2i(signi(target.x - at.x), signi(target.y - at.y))
	var walk := at
	var guard: int = 0
	while walk != target and guard < 64:
		guard += 1
		# Widened perpendicular to the direction of travel, so the lane is two
		# across however it bends.
		var widen := Vector2i.ZERO
		if walk.x != target.x:
			walk.x += step.x
			widen = Vector2i(0, 1)
		elif walk.y != target.y:
			walk.y += step.y
			widen = Vector2i(1, 0)
		if _at(walk.x, walk.y) == "u":
			break   # reached the corridor; stop, or the clearing gains a second mouth
		if _at(walk.x, walk.y) == "T":
			_put(walk.x, walk.y, "u")
			# Only ever beside a cell this walk carved itself. Widening blindly
			# could punch a second way in, which is the one thing forbidden here.
			var side: Vector2i = walk + widen
			if _at(side.x, side.y) == "T":
				_put(side.x, side.y, "u")
	_widen_the_mouth(cells)

## Guarantees the lane is **two cells wide where it meets the clearing**, which
## is the bit a player standing in the trees actually has to spot.
##
## Widening perpendicular to the walk gets this right most of the time and
## missed one of the two dens outright: the partner cell landed one step along
## the lane rather than against the clearing itself, so the opening was still a
## single tile. Rather than trust the geometry, this finds the mouth after the
## fact and opens it.
##
## Still exactly one mouth: the cell it opens must touch both the clearing *and*
## the existing mouth cell, so the two stay a single connected group of
## woodland. A cell touching the clearing somewhere else would be a second door.
func _widen_the_mouth(cells: Array) -> void:
	var dirs := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	var in_clearing: Dictionary = {}
	for cell in cells:
		in_clearing[cell] = true

	# The mouth: woodland cells orthogonally touching the clearing.
	var mouth: Array = []
	for cell in cells:
		for d in dirs:
			var n: Vector2i = cell + d
			if not in_clearing.has(n) and _at(n.x, n.y) == "u" and not mouth.has(n):
				mouth.append(n)
	if mouth.size() != 1:
		return   # already wide enough, or sealed -- the harness owns both cases

	# The throat is the pair (lane cell, clearing cell it opens onto). Widening
	# means sliding that pair one cell sideways and opening both -- padding the
	# lane alone does not help, because the clearing's own edge is what pinches
	# it. The southwood den needed exactly this: its lane had no widenable
	# neighbour at all, because the clearing only reached the lane on one row.
	var m: Vector2i = mouth[0]
	var c := Vector2i(-1, -1)
	for d in dirs:
		if in_clearing.has(m + d):
			c = m + d
			break
	if c.x < 0:
		return
	var along: Vector2i = c - m
	for d in dirs:
		if d == along or d == -along:
			continue   # along the lane, not across it
		var m2: Vector2i = m + d
		var c2: Vector2i = c + d
		# The new lane cell has to be forest or already open, and the new
		# clearing cell has to be forest or already clearing. Anything else --
		# rock, water, a road -- and this is not a throat to widen.
		if not (_at(m2.x, m2.y) in ["T", "u"]):
			continue
		if _at(c2.x, c2.y) != "T" and not in_clearing.has(c2):
			continue
		if _at(m2.x, m2.y) == "T":
			_put(m2.x, m2.y, "u")
		if _at(c2.x, c2.y) == "T":
			_put(c2.x, c2.y, _patch_pick(c2.x, c2.y, ["g", "s", "S"]))
		return

# ---------------- 5. Landmarks ------------------------------------------------

## Positions only -- the human buildings themselves are `world_sites.json`'s
## business. What this step does is make sure the ground each landmark stands on
## is something a road can reach.
func _step_landmarks() -> void:
	for entry in HUMAN_LANDMARKS:
		var cell: Vector2i = entry["cell"]
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if _at(cell.x + dx, cell.y + dy) in ["T", "^", "~"]:
					_put(cell.x + dx, cell.y + dy, "e")

# ---------------- 6-7. The road networks --------------------------------------

## Cobble first, dirt second, and the order is the fiction: **dirt tracks branch
## off the cobble network rather than radiating from the lair**, so the world
## reads as a human landscape the Necromancer is hiding inside rather than as a
## wheel with him at the hub.
func _step_cobble_network() -> void:
	# The Old Road trunk, north to south. Everything else joins it, and the
	# existing-road cost of 0.5 is what makes them join rather than run parallel.
	var trunk: Array = _route(OLD_ROAD_NORTH, OLD_ROAD_SOUTH)
	_paint_route(trunk, "C", 2)
	for entry in HUMAN_LANDMARKS:
		_paint_route(_route(_nearest_road(entry["cell"]), entry["cell"]), "C", 2)

## §7 rule 2: dirt connects **only** sites tagged `signposted: true`, and the
## generator refuses to signpost anything in Band 3 or 4 -- a hard error at
## generation time, not a convention someone has to remember.
func _step_dirt_network() -> void:
	# The lair's own approach stays (§7 rule 3): it is the player's track, not a
	# signpost to loot.
	_paint_route(_route(LAIR_GATE, _nearest_road(LAIR_GATE)), "t", 2)

	var lootable: Dictionary = {}
	for entry in _lootable_sites():
		lootable[entry["id"]] = entry

	for site in _signposted_sites():
		var cell: Vector2i = site["cell"]
		var band: int = _band_of(cell)
		if band >= 3:
			push_error(("make_world_map: site '%s' at %s is Band %d and sets "
				+ "signposted:true. TERRAIN_SPEC §7 forbids it -- the crypt, the "
				+ "outlaw cave and the cursed battlefield are found, not followed.")
				% [site.get("id", "?"), cell, band])
			aborted = true
			return
		# **THE ROAD PROMISE** (designer ruling, 2026-08-27 P2 human check): a
		# road always has something at its end, even minor loot. Every dirt
		# track this step paints terminates at a signposted site, so the promise
		# reduces to one rule -- a signposted site must be lootable -- and it is
		# a hard error here rather than a convention, for the same reason the
		# Band-3 check above is. `verify_terrain` re-checks it against the
		# painted map, which is the half that catches a track laid by anything
		# other than this loop.
		if not lootable.has(site.get("id", "?")):
			push_error(("make_world_map: site '%s' at %s sets signposted:true but has no "
				+ "`lootable` block. A dirt track must end at something worth walking to "
				+ "(the road promise, 2026-08-27) -- give it loot or unsignpost it.")
				% [site.get("id", "?"), cell])
			aborted = true
			return
		_paint_route(_route(_nearest_road(cell), cell), "t", 1)

func _signposted_sites() -> Array:
	var out: Array = []
	if not FileAccess.file_exists("res://data/world_sites.json"):
		return out
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_sites.json"))
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	for entry in parsed.get("sites", []):
		if not bool(entry.get("signposted", false)):
			continue
		var c: Array = entry.get("cell", [0, 0])
		out.append({"id": entry.get("id", "?"), "cell": Vector2i(int(c[0]), int(c[1]))})
	return out

## Which of WORLD_MAP_PLAN §6's bands a cell falls in. Later entries win, same
## rule the runtime uses.
func _band_of(cell: Vector2i) -> int:
	var band: int = 2
	for entry in BANDS:
		var r: Array = entry["rect"]
		if cell.x >= int(r[0]) and cell.y >= int(r[1]) \
				and cell.x < int(r[0]) + int(r[2]) and cell.y < int(r[1]) + int(r[3]):
			band = int(entry["band"])
	return band

func _paint_route(path: Array, ch: String, width: int) -> void:
	for cell in path:
		for w in range(width):
			# A route never paves over water, a crossing, or a clearing: the
			# crossing is already the door, and §6b forbids anything paved
			# inside a wood.
			var here: String = _at(cell.x + w, cell.y)
			if here in ["~", "≈", "=", "T"]:
				continue
			_put(cell.x + w, cell.y, ch)

## The nearest **paved** cell -- deliberately not counting crossings.
##
## A bridge is part of the road network but it is a *door*, not somewhere a new
## branch may start. Including "=" here made `_nearest_road(village)` return the
## bridge itself, so the village spur began on the far bank and never joined the
## trunk: four disconnected road components, and a village you could not drive
## to from the lair.
func _nearest_road(from: Vector2i) -> Vector2i:
	var best := OLD_ROAD_NORTH
	var best_d: float = INF
	for y in range(H):
		for x in range(W):
			if not (_at(x, y) in ["C", "c", "k", "t"]):
				continue
			var d: float = Vector2(x - from.x, y - from.y).length()
			if d < best_d:
				best_d = d
				best = Vector2i(x, y)
	return best

## Dijkstra over §8's cost grid. `AStarGrid2D` cannot carry per-cell weights the
## way this needs (a reserved crossing is passable while the river around it is
## not), so the queue is written out -- 20,736 cells is small enough that the
## simplicity is worth more than the heuristic.
func _route(from: Vector2i, to: Vector2i) -> Array:
	var cost: PackedFloat32Array = PackedFloat32Array()
	cost.resize(W * H)
	for i in range(W * H):
		cost[i] = INF
	var prev: PackedInt32Array = PackedInt32Array()
	prev.resize(W * H)
	for i in range(W * H):
		prev[i] = -1
	var start: int = from.y * W + from.x
	cost[start] = 0.0
	var frontier: Array = [[0.0, start]]
	var goal: int = to.y * W + to.x

	while not frontier.is_empty():
		frontier.sort_custom(func(a, b): return a[0] < b[0])
		var top: Array = frontier.pop_front()
		var here: int = top[1]
		if here == goal:
			break
		if top[0] > cost[here]:
			continue
		var hx: int = here % W
		var hy: int = here / W
		for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var nx: int = hx + d.x
			var ny: int = hy + d.y
			if not _in(nx, ny):
				continue
			var step: float = _cell_cost(nx, ny)
			if step < 0.0:
				continue
			var next: int = ny * W + nx
			var total: float = cost[here] + step
			if total < cost[next]:
				cost[next] = total
				prev[next] = here
				frontier.append([total, next])

	if cost[goal] == INF:
		push_error("make_world_map: no route from %s to %s -- the cost grid has sealed something off"
			% [from, to])
		return []
	var path: Array = []
	var walk: int = goal
	while walk != -1:
		path.append(Vector2i(walk % W, walk / W))
		walk = prev[walk]
	path.reverse()
	return path

## TERRAIN_SPEC §8's cost table. Negative means impassable.
func _cell_cost(x: int, y: int) -> float:
	match _at(x, y):
		"C", "c", "k", "t":
			return COST_ROAD        # roads merge and share trunk sections
		"=", "≈":
			return COST_ROAD        # a reserved crossing is the door through the river
		"u":
			return COST_WOODLAND    # a road may clip a treeline, reluctantly
		",", "o":
			return COST_BAD_GROUND  # real roads bend around bad ground
		"^", "m", "T", "~", "O":
			return COST_IMPASSABLE  # never climbs, never enters the woods, never fords
		_:
			return COST_OPEN

# ---------------- 8. Dressing -------------------------------------------------

## The four things WORLD_MAP_PLAN asked for and R1 shipped without.
func _step_dressing() -> void:
	# Human farms around the village (§4's sketch). Plowed and stubble in
	# patches, so the fields read as worked rather than as a texture.
	for cell in _ellipse_cells(Vector2i(VILLAGE_X, VILLAGE_Y + 8), 16, 13, 0.3, 91):
		if _at(cell.x, cell.y) in ["g", "s", "S", "e", "d", "w"]:
			_put(cell.x, cell.y, _patch_pick(cell.x, cell.y, ["f", "f", "F"]))
	# Corrupted ground and the real ritual circle in the sealed region (§5).
	for cell in _ellipse_cells(Vector2i(23, 111), 11, 11, 0.4, 17):
		if _at(cell.x, cell.y) in ["g", "s", "S", "e", "w", "d"]:
			_put(cell.x, cell.y, _patch_pick(cell.x, cell.y, ["x", "x", "X"]))
	for y in range(109, 112):
		for x in range(21, 24):
			_put(x, y, "r")
	# Marsh in the Necromancer's lowlands -- the doc's own example, finally
	# real, and the project's first sub-1.0 speed. Kept off the lair track.
	for cell in _ellipse_cells(Vector2i(34, 96), 9, 7, 0.4, 55):
		if _at(cell.x, cell.y) in ["g", "s", "S", "e"]:
			_put(cell.x, cell.y, ",")
	_dress_lootable_sites()

## **Terrain telegraphs, paths do not** (§7 rule 4, `LOOT_SITES_SPEC.md` §3).
## A ruin pocket and a crypt sit on ruins, the cursed battlefield on charred
## ground, a wolf den on gnawed bone -- so each reads as *something is here* from
## a distance, which is what satisfies the telegraphing requirement without a
## line leading to it.
##
## **Driven off `world_sites.json`, not off a list of cells.** The pair of
## hardcoded centres this replaces had already drifted: one of them sat in the
## middle of the frozen lake and painted nothing, and the other missed the crypt
## by three cells. Reading the site file means the dressing cannot be somewhere
## the site is not, and a site moved in the JSON brings its ground with it.
##
## Only ORDINARY GROUND is overpainted -- never blocking terrain, never water,
## never a road or a wood. That is what keeps this a dressing step rather than a
## second terrain generator: the battlefield at the foot of the northern range
## chars the walkable cells between the scree and leaves the range itself alone,
## and a den's bone patch stays inside its clearing because open woodland is not
## on the list.
const SITE_DRESSING := {
	"ruin_pocket": {"chars": ["R", "R", "o"], "rx": 4, "ry": 3},
	"crypt": {"chars": ["R", "R", "o"], "rx": 5, "ry": 4},
	"outlaw_cave": {"chars": ["o", "o", "R"], "rx": 4, "ry": 3},
	"cursed_battlefield": {"chars": ["X", "X", "B"], "rx": 5, "ry": 4},
	"wolf_den": {"chars": ["B", "B", "b"], "rx": 3, "ry": 2},
}
## What a dressing patch may be laid over. Ordinary ground only.
const DRESSABLE := ["g", "s", "S", "e", "w", "d", "D", "b", "f", "F"]

func _dress_lootable_sites() -> void:
	var salt: int = 23
	for site in _lootable_sites():
		var spec: Dictionary = SITE_DRESSING.get(String(site["type"]), {})
		if spec.is_empty():
			continue
		salt += 7
		var painted: int = 0
		for cell in _ellipse_cells(site["cell"], int(spec["rx"]), int(spec["ry"]), 0.5, salt):
			if _at(cell.x, cell.y) in DRESSABLE:
				_put(cell.x, cell.y, _patch_pick(cell.x, cell.y, spec["chars"]))
				painted += 1
		# A site whose ground refused every cell is a site that no longer
		# telegraphs, and that is worth saying out loud rather than discovering
		# at a playtest.
		if painted == 0:
			push_warning("make_world_map: site '%s' (%s) at %s got no dressing -- nothing under it is ordinary ground."
				% [site["id"], site["type"], str(site["cell"])])

## Every entry carrying a `lootable` block, as `{id, type, band, cell,
## signposted}`. Read once here and once by `_signposted_sites()`; kept separate
## because the signposting check runs before the roads and this runs after.
func _lootable_sites() -> Array:
	var out: Array = []
	if not FileAccess.file_exists("res://data/world_sites.json"):
		return out
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_sites.json"))
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	for entry in parsed.get("sites", []):
		if not entry.has("lootable"):
			continue
		var c: Array = entry.get("cell", [0, 0])
		out.append({
			"id": String(entry.get("id", "?")),
			"type": String(entry["lootable"].get("type", "")),
			"band": int(entry["lootable"].get("band", 2)),
			"cell": Vector2i(int(c[0]), int(c[1])),
			"signposted": bool(entry.get("signposted", false)),
		})
	return out

# ---------------- 9. Bake -----------------------------------------------------

func _step_bake() -> void:
	if aborted:
		push_error("make_world_map: aborted -- data/world_map.json left untouched.")
		quit(1)
		return
	_clear_lair_band()
	_write()

## The lair band is guaranteed walkable and guaranteed connected: no scree, no
## cliff, **no forest**, nothing that could strand the settlement inside its own
## valley. The settlement's own footprint is bone-strewn ground, which is what a
## necromancer does to a yard he has held for a season.
func _clear_lair_band() -> void:
	for y in range(BAND.position.y, BAND.position.y + BAND.size.y):
		for x in range(BAND.position.x, BAND.position.x + BAND.size.x):
			if _at(x, y) in ["m", "i", "^", "T", "u", "~"]:
				_put(x, y, _patch_pick(x, y, ["g", "s", "S"]))
	for y in range(LAIR_ORIGIN.y, LAIR_ORIGIN.y + SETTLEMENT_H):
		for x in range(LAIR_ORIGIN.x, LAIR_ORIGIN.x + SETTLEMENT_W):
			_put(x, y, _patch_pick(x, y, ["B", "B", "b"]))

# ---------------- Output ------------------------------------------------------

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

	var counts: Dictionary = {}
	for y in range(H):
		for x in range(W):
			counts[grid[y][x]] = int(counts.get(grid[y][x], 0)) + 1
	var blocked: int = 0
	var road: int = 0
	for ch in counts.keys():
		var cat: String = LEGEND[ch].get("category", "ground")
		if cat == "blocking":
			blocked += int(counts[ch])
		elif cat == "road":
			road += int(counts[ch])
	var dense: int = int(counts.get("T", 0))
	print("Wrote %s: %dx%d, %d blocking (%.1f%%), %d road, %d dense forest (%.1f%%), %d woodland, %d marsh, %d water, %d crossings"
		% [OUT_PATH, W, H, blocked, 100.0 * blocked / float(W * H), road,
			dense, 100.0 * dense / float(W * H), int(counts.get("u", 0)),
			int(counts.get(",", 0)), int(counts.get("~", 0)), crossings.size()])
