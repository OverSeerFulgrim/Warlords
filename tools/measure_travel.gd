extends Node
## Measures real travel times against WORLD_MAP_PLAN §3's target table.
##
##   godot --headless --path . res://tools/measure_travel.tscn
##
## **Kept in the repo, not thrown away.** §3's table is the exit criterion for
## the world's scale, and every knob that moves it -- the Necromancer's walk
## speed, the road bonus, where the village sits, where the ridge sits -- is a
## constant somebody will change later. This is how you find out what that did,
## without playing a four-minute walk five times.
##
## A **scene** rather than a `-s` script because `-s` compiles before the
## autoloads register, and every class that touches EventBus then fails to load.
##
## ## How it measures
##
## It walks the villain for real: an A* route over walkable cells, then repeated
## `Necromancer.step()` calls at a fixed delta until he arrives. So the number
## includes terrain sliding, diagonal normalisation and the road multiplier,
## because it comes out of the same movement code the player drives.
##
## Two routes are reported for each journey:
##
## - **wilderness** -- shortest walkable path, roads not preferred. This is the
##   number judged against §3, because §3 says "uninterrupted movement before
##   ... detours", and taking the road is a detour with a tradeoff (§9: faster
##   but exposed). It is also the honest worst case for a villain avoiding
##   witnesses, which is the whole Era I fantasy.
## - **road** -- A* weighted toward roads. Reported as the bonus it is.

const DT := 1.0 / 60.0
const ARRIVE_PX := 20.0
const GIVE_UP_SECONDS := 1800.0

## label -> [min, max] seconds, straight from WORLD_MAP_PLAN §3.
const TARGETS := {
	"lair -> nearby resource": [10.0, 20.0],
	"lair -> first landmark": [20.0, 40.0],
	"lair -> edge of local territory": [45.0, 75.0],
	"lair -> the village": [120.0, 240.0],
	"crossing the entire map": [180.0, 300.0],
}

var world: WorldMap
var villain: Necromancer
var _wild := AStarGrid2D.new()
var _road := AStarGrid2D.new()

func _ready() -> void:
	get_tree().root.size = Vector2i(1400, 760)
	await get_tree().process_frame
	var main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	world = main.world_map
	villain = main.villain
	_build_graphs()

	var lair: Vector2i = world.lair_origin + Vector2i(
		SettlementGrid.GRID_WIDTH / 2, SettlementGrid.GRID_HEIGHT / 2)

	print("\n=== Travel times vs WORLD_MAP_PLAN §3 ===")
	print("Necromancer walk speed: %.2f cells/sec   (road bonus up to x%.2f)"
		% [Necromancer.MOVE_SPEED_CELLS, WorldMap.DEFAULT_ROAD_SPEED])
	print("Lair at cell %s.  Distances are routed, not straight-line.\n" % lair)
	print("%-34s %-11s %-11s %-9s %s" % ["journey", "wilderness", "on roads", "cells", "verdict"])
	print("-".repeat(86))

	var span: Array = _resource_span(main, lair)
	_journey("lair -> nearby resource", lair, span[0])
	_journey("lair -> furthest lair resource", lair, span[1])
	_journey("lair -> first landmark", lair, _nearest_landmark_cell(main, lair))
	_journey("lair -> edge of local territory", lair, _valley_mouth_cell(lair))
	_journey("lair -> the village", lair, _site_cell(main, "manor"))
	var a: Vector2i = _nearest_open(Vector2i(6, 6))
	var b: Vector2i = _nearest_open(Vector2i(world.width - 7, world.height - 7))
	_journey("crossing the entire map", a, b)

	print("\nA day is 30 minutes of daylight + 20 of night (DayNightCycle).")
	get_tree().quit()

# ---------------- Journeys ---------------------------------------------------

func _journey(label: String, from: Vector2i, to: Vector2i) -> void:
	if to.x < 0:
		print("%-34s (no destination found)" % label)
		return
	var wild_path: Array = _wild.get_id_path(from, to)
	var road_path: Array = _road.get_id_path(from, to)
	if wild_path.is_empty():
		print("%-34s (unreachable)" % label)
		return
	var wild: float = _walk(wild_path)
	var road: float = _walk(road_path)
	var band: Array = TARGETS.get(label, [])
	var verdict := ""
	if not band.is_empty():
		if wild < band[0]:
			verdict = "FAST — target %s-%s" % [_fmt(band[0]), _fmt(band[1])]
		elif wild > band[1]:
			verdict = "SLOW — target %s-%s" % [_fmt(band[0]), _fmt(band[1])]
		else:
			verdict = "in band (%s-%s)" % [_fmt(band[0]), _fmt(band[1])]
	print("%-34s %-11s %-11s %-9d %s" % [
		label, _fmt(wild), _fmt(road), wild_path.size(), verdict])

## Drives the villain along a cell path with the real movement code and returns
## the game-seconds it took.
func _walk(path: Array) -> float:
	if path.is_empty():
		return 0.0
	villain.place_at(world.cell_centre_px(path[0]))
	var seconds := 0.0
	var i := 1
	var stuck := 0
	while i < path.size() and seconds < GIVE_UP_SECONDS:
		var target: Vector2 = world.cell_centre_px(path[i])
		var offset: Vector2 = target - villain.position
		if offset.length() <= ARRIVE_PX:
			i += 1
			stuck = 0
			continue
		var before: Vector2 = villain.position
		villain.step(offset, DT)
		seconds += DT
		# A* only routes over walkable cells, so this should never trip -- but a
		# silent infinite loop in a measurement tool would produce confident
		# wrong numbers, which is worse than a crash.
		if villain.position.is_equal_approx(before):
			stuck += 1
			if stuck > 60:
				push_warning("measure_travel: stuck at %s, skipping waypoint" % villain.position)
				i += 1
				stuck = 0
	return seconds

# ---------------- Destinations -----------------------------------------------

## The nearest and furthest seeded resource, so the report shows the *spread*
## rather than a single number. The lair's own nodes deliberately sit close --
## workers walk them every trip and a long haul would wreck the settlement
## economy's pacing -- so the near end is expected to undershoot §3's floor.
func _resource_span(main, lair: Vector2i) -> Array:
	var near := Vector2i(-1, -1)
	var far := Vector2i(-1, -1)
	var near_d := INF
	var far_d := -1.0
	for n in main.resource_field.nodes:
		var cell: Vector2i = world.cell_at(n.position)
		var d: float = Vector2(cell - lair).length()
		if d < 3.0:
			continue   # standing in the settlement's own footprint
		if d < near_d:
			near_d = d
			near = cell
		if d > far_d:
			far_d = d
			far = cell
	return [_nearest_open(near), _nearest_open(far)]

func _nearest_landmark_cell(main, lair: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for label in main.world_sites.landmarks.keys():
		var cell: Vector2i = world.cell_at(main.world_sites.landmarks[label])
		if world.lair_band.has_point(cell):
			continue
		var d: float = Vector2(cell - lair).length()
		if d < best_d:
			best_d = d
			best = cell
	return _nearest_open(best)

func _site_cell(main, id: String) -> Vector2i:
	for s in main.world_sites.sites:
		if s.site_id == id:
			return _nearest_open(world.cell_at(s.position))
	return Vector2i(-1, -1)

## The mouth of the Necromancer's valley: scanning east from the lair, the first
## column that the central ridge occupies. Derived rather than hardcoded, so
## moving the ridge in the generator moves this measurement with it.
##
## **Only rows near the lair's own latitude count.** Scanning the full column
## height found the northern range instead and reported the frontier 20 cells
## too close -- a measurement bug that would have been read as a map problem.
func _valley_mouth_cell(lair: Vector2i) -> Vector2i:
	for x in range(lair.x + 5, world.width):
		for y in range(lair.y - 14, lair.y + 15):
			if not world.is_walkable_cell(Vector2i(x, y)):
				return _nearest_open(Vector2i(x - 1, lair.y))
	return Vector2i(-1, -1)

func _nearest_open(cell: Vector2i) -> Vector2i:
	if cell.x < 0:
		return cell
	if world.is_walkable_cell(cell):
		return cell
	return world.cell_at(world.nearest_walkable(world.cell_centre_px(cell), 12))

# ---------------- Graphs -----------------------------------------------------

func _build_graphs() -> void:
	for grid in [_wild, _road]:
		grid.region = Rect2i(0, 0, world.width, world.height)
		grid.cell_size = Vector2(WorldMap.CELL_SIZE, WorldMap.CELL_SIZE)
		grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		grid.update()
	for y in range(world.height):
		for x in range(world.width):
			var cell := Vector2i(x, y)
			var solid: bool = not world.is_walkable_cell(cell)
			_wild.set_point_solid(cell, solid)
			_road.set_point_solid(cell, solid)
			if not solid:
				# Cost is time, so a road cell costs less to cross. The
				# wilderness graph deliberately keeps every cell at 1.0.
				_road.set_point_weight_scale(cell,
					1.0 / maxf(0.1, world.speed_multiplier(world.cell_centre_px(cell))))

static func _fmt(seconds: float) -> String:
	if seconds < 60.0:
		return "%.0fs" % seconds
	return "%dm%02ds" % [int(seconds) / 60, int(seconds) % 60]
