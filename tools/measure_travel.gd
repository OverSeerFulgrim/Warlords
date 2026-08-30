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
##
## ## Worker nodes and sortie-scale resources are two different rows
##
## §3's "lair to nearby resource" row used to be measured to the nearest seeded
## resource node, which reported FAST forever and read as a regression. It was a
## category error in the harness, not a fault in the map: the lair's own nodes
## are **worker nodes**, deliberately close because workers walk them every trip
## and a long haul would wreck the settlement economy's pacing. §3's row is
## about **sortie-scale** resources -- the ones the Necromancer leaves home for --
## which R2 places outside the lair band.
##
## So the two are measured separately: the worker-node span is reported with its
## reason and no target, and the sortie-scale row is measured to the ring §3
## implies at the tuned walk speed. Until R2 seeds a site into that ring the row
## is PENDING, and `_ring_report()` asserts the ring is there to seed into --
## walkable, reachable, and inside the 10-20s band once you get there.

const DT := 1.0 / 60.0
const ARRIVE_PX := 20.0
const GIVE_UP_SECONDS := 1800.0

## How many bearings the sortie-scale ring is sampled along. 16 is every 22.5°,
## enough to catch a whole quadrant walled off by the ridge.
const RING_BEARINGS := 16

## **The forest is scattered with `randf_range`**, so two runs place their trees
## in different spots and the nearest-worker-node row lands on a different tree
## each time -- it wobbled 4-5s across runs with everything else identical. A
## travel harness that reports a different number every run cannot be regressed
## against, so the global seed is fixed here exactly as `capture_settlement.gd`
## fixes it, and for the same reason: measure one map, not a family of them.
const MEASURE_SEED: int = 20260805

## How far a ring cell's routed walk may exceed its straight-line time before
## the ring is called a problem.
##
## Judging ring cells against the raw 10-20s band directly does not work: the
## ring's edges *are* the band's edges by construction, so a cell sampled at
## radius 20 lands at 20.5s and reads as a failure over grid quantisation. The
## detour factor is the scale-free version of the same question -- "does routing
## make this cell further than it looks?" -- and it is what would actually catch
## a quadrant walled off by the ridge. Measured worst case on the R1 map is
## 1.06x (pure diagonal-step quantisation); a genuinely blocked bearing routes
## at 1.5x or worse, so 1.15 sits clearly between the two.
const MAX_RING_DETOUR := 1.15

## The one node in `ResourceField.nodes` that a travel measurement must not use:
## the **deer roams**, every frame, from a `randf_range` start. It is not a
## place a worker walks to on a repeatable trip.
##
## This is why the row was nondeterministic -- it reported 3s, 4s or 5s run to
## run depending on where the deer had wandered, which is also how the backlog
## came to record 3s while the R1 travel table recorded 5s. Both numbers were
## real; neither was measuring a resource.
##
## Note the forest's four **carcasses stay in** -- they are seeded fixed nodes
## seeded among the trees so a Bones trip and a Wood trip share a corner of the
## map, and a worker walks them exactly like a tree. Only the wolf drop shares
## that `node_type`, and it does not exist at seeding time.
const ROAMING_NODES := ["deer"]

## label -> [min, max] seconds, straight from WORLD_MAP_PLAN §3.
##
## §3's first row reads "lair to nearby resource", and **that row is about
## sortie-scale resources, not the lair's own worker nodes** -- two different
## journeys with two different expectations, see `_worker_node_span()`. The
## worker-node rows are deliberately reported without a target; judging them
## against §3 is what produced the standing FAST false alarm this table carried.
const TARGETS := {
	"lair -> sortie-scale resource": [10.0, 20.0],
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
	seed(MEASURE_SEED)
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

	# The lair's own nodes, reported as what they are and judged against nothing.
	var span: Array = _worker_node_span(main, lair)
	var why := "short by design — workers walk these every trip"
	_journey("lair -> worker node (nearest)", lair, span[0], why)
	_journey("lair -> worker node (furthest)", lair, span[1], why)

	# §3's actual first row. PENDING until R2 seeds the ring.
	var ring: Array = _sortie_ring_cells()
	var sortie: Vector2i = _sortie_site_cell(main, lair, ring)
	if sortie.x < 0:
		_pending("lair -> sortie-scale resource",
			"PENDING R2a — no site in the %d-%d cell ring yet" % [ring[0], ring[1]])
	else:
		_journey("lair -> sortie-scale resource", lair, sortie)

	_journey("lair -> first landmark", lair, _nearest_landmark_cell(main, lair))
	_journey("lair -> edge of local territory", lair, _valley_mouth_cell(lair))
	_journey("lair -> the village", lair, _site_cell(main, "manor"))
	var a: Vector2i = _nearest_open(Vector2i(6, 6))
	var b: Vector2i = _nearest_open(Vector2i(world.width - 7, world.height - 7))
	_journey("crossing the entire map", a, b)
	_loaded_return(main, lair)

	if sortie.x < 0:
		_ring_report(lair, ring)

	print("\nA day is 30 minutes of daylight + 20 of night (DayNightCycle).")
	get_tree().quit()

# ---------------- Journeys ---------------------------------------------------

## `note`, when given, replaces the verdict column. It is how a row says "this
## journey is not one of §3's and here is why", which is different from a row
## that simply has no target -- silence there reads as an oversight.
## **The return leg, measured rather than assumed** (SORTIE_SPEC §10).
##
## The claim under test is a negative one: **carry must not silently gate travel
## time.** There is no encumbrance curve in this project and there is not meant
## to be -- SORTIE_SPEC §10 names load-slowing-the-carrier as a *designated
## fallback lever*, to be adopted only by striking that spec's loaded-return
## assertion openly. So this fills his hands to the brim, walks the village trip
## home again, and asserts the number did not move.
##
## If it ever does move, either somebody added encumbrance without saying so, or
## the lever was pulled on purpose -- and this row is where that conversation
## starts instead of a playtest wondering why the walk got long.
func _loaded_return(main, lair: Vector2i) -> void:
	var village: Vector2i = _site_cell(main, "manor")
	if village.x < 0:
		return
	var empty_path: Array = _wild.get_id_path(village, lair)
	if empty_path.is_empty():
		return
	var empty_seconds: float = _walk(empty_path)

	# Fill him. `carry_capacity()` rather than a literal, so a relic that widens
	# his hands is measured at its real width.
	var before: Dictionary = villain.carried.duplicate()
	villain.carried.clear()
	villain.add_carried("bones", villain.carry_capacity())
	var loaded_seconds: float = _walk(_wild.get_id_path(village, lair))
	var full: bool = villain.carry_space() == 0
	villain.carried = before

	var band: Array = TARGETS["lair -> the village"]
	var verdict: String = "in band (%s-%s)" % [_fmt(band[0]), _fmt(band[1])]
	if loaded_seconds < band[0]:
		verdict = "FAST (under %s)" % _fmt(band[0])
	elif loaded_seconds > band[1]:
		verdict = "SLOW (over %s)" % _fmt(band[1])
	if not is_equal_approx(loaded_seconds, empty_seconds):
		verdict += "  !! CARRY IS GATING TRAVEL -- see SORTIE_SPEC §10"
	print("%-34s %-11s %-11s %-9s %s" % ["village -> lair, hands full",
		_fmt(loaded_seconds), _fmt(loaded_seconds), str(empty_path.size()), verdict])
	if not full:
		print("    note: could not fill his hands -- the row measured an empty walk")

func _journey(label: String, from: Vector2i, to: Vector2i, note := "") -> void:
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
	var verdict := note
	if not band.is_empty():
		if wild < band[0]:
			verdict = "FAST — target %s-%s" % [_fmt(band[0]), _fmt(band[1])]
		elif wild > band[1]:
			verdict = "SLOW — target %s-%s" % [_fmt(band[0]), _fmt(band[1])]
		else:
			verdict = "in band (%s-%s)" % [_fmt(band[0]), _fmt(band[1])]
	print("%-34s %-11s %-11s %-9d %s" % [
		label, _fmt(wild), _fmt(road), wild_path.size(), verdict])

## A row that has a §3 target but nothing in the world to measure it to yet.
## Printed rather than skipped, so the table keeps a slot for it and the reason
## it is empty travels with the number that is missing.
func _pending(label: String, why: String) -> void:
	print("%-34s %-11s %-11s %-9s %s" % [label, "—", "—", "—", why])

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

## The nearest and furthest **worker node**, so the report shows the *spread*
## rather than a single number.
##
## These are the lair's own seeded resources -- `ResourceField`'s lair-band
## seeding -- and they sit close **on purpose**: workers walk them every trip,
## and a long haul would wreck the settlement economy's pacing. They are not
## §3's "nearby resource" and are not judged against it. Do not "fix" a short
## number here by moving the nodes; that trades a working economy for a row in
## a table that was never about these nodes.
##
## The lair band is the structural line between the two kinds, which is also
## how `ROGUELITE_REWORK.md` §12 frames it ("`ResourceField`'s fixed seeding
## becomes the lair-band seeder"). Anything R2 seeds outside the band is a
## sortie-scale resource and gets measured by `_sortie_site_cell()` instead.
func _worker_node_span(main, lair: Vector2i) -> Array:
	var near := Vector2i(-1, -1)
	var far := Vector2i(-1, -1)
	var near_d := INF
	var far_d := -1.0
	for n in main.resource_field.nodes:
		if n.node_type in ROAMING_NODES:
			continue
		var cell: Vector2i = world.cell_at(n.position)
		if not world.lair_band.has_point(cell):
			continue   # not a worker node -- see _sortie_site_cell()
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

## The ring §3's "lair -> nearby resource" row implies, in **cells**, derived
## from the target seconds and the tuned walk speed rather than hardcoded -- so
## if anyone retunes `MOVE_SPEED_CELLS`, the ring this harness checks moves with
## it instead of quietly going stale.
func _sortie_ring_cells() -> Array:
	var band: Array = TARGETS["lair -> sortie-scale resource"]
	return [
		roundi(band[0] * Necromancer.MOVE_SPEED_CELLS),
		roundi(band[1] * Necromancer.MOVE_SPEED_CELLS),
	]

## The nearest sortie-scale resource: a resource node or world site **outside
## the lair band**, inside the ring. R2 has not placed any yet, so this returns
## (-1, -1) and the row reports PENDING -- but it is wired now so the row starts
## reporting a real number the moment `LOOT_SITES_SPEC.md` §2's sites land.
func _sortie_site_cell(main, lair: Vector2i, ring: Array) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	var candidates: Array = []
	candidates.append_array(main.resource_field.nodes)
	candidates.append_array(main.world_sites.sites)
	for c in candidates:
		var cell: Vector2i = world.cell_at(c.position)
		if world.lair_band.has_point(cell):
			continue
		var d: float = Vector2(cell - lair).length()
		if d < float(ring[0]) or d > float(ring[1]):
			continue
		if d < best_d:
			best_d = d
			best = cell
	if best.x < 0:
		return best
	return _nearest_open(best)

## With no sortie-scale site to measure to, assert the **ring** instead: that
## there is somewhere in it to put one, and that standing there is 10-20s from
## home once you do.
##
## Worth doing rather than just printing PENDING, because "10-20 cells out" is a
## straight-line claim and the villain walks a route. The ridge, the marsh and
## the blocking terrain are all entitled to make a cell 12 cells away a 30-second
## walk, and that would be a real finding about where R2 may seed.
##
## Cells are sampled unsnapped: a blocked ring cell is genuinely unavailable for
## seeding, and snapping it to its nearest open neighbour would hide exactly the
## thing this is looking for.
func _ring_report(lair: Vector2i, ring: Array) -> void:
	var band: Array = TARGETS["lair -> sortie-scale resource"]
	var radii: Array = [float(ring[0]), (ring[0] + ring[1]) * 0.5, float(ring[1])]
	var bounds := Rect2i(0, 0, world.width, world.height)
	var sampled := 0
	var blocked := 0
	var unreachable := 0
	var outside_band := 0
	var over := 0
	var worst := 0.0
	var worst_cell := Vector2i.ZERO
	var times: Array = []
	for i in range(RING_BEARINGS):
		var dir := Vector2.RIGHT.rotated(TAU * float(i) / float(RING_BEARINGS))
		for r in radii:
			var cell: Vector2i = lair + Vector2i(roundi(dir.x * r), roundi(dir.y * r))
			if not bounds.has_point(cell):
				continue
			sampled += 1
			if not world.is_walkable_cell(cell):
				blocked += 1
				continue
			var path: Array = _wild.get_id_path(lair, cell)
			if path.is_empty():
				unreachable += 1
				continue
			var t: float = _walk(path)
			times.append(t)
			var detour: float = t / (r / Necromancer.MOVE_SPEED_CELLS)
			if detour > worst:
				worst = detour
				worst_cell = cell
			if detour > MAX_RING_DETOUR:
				over += 1
			if not world.lair_band.has_point(cell):
				outside_band += 1
	times.sort()
	print("\n--- sortie-scale ring: %d-%d cells from the lair ---" % [ring[0], ring[1]])
	print("§3's %s-%s row is a sortie-scale row. At %.2f cells/sec that is this ring."
		% [_fmt(band[0]), _fmt(band[1]), Necromancer.MOVE_SPEED_CELLS])
	print("R2 seeds against it; until then this asserts the ring is there to seed into.")
	print("  sampled            %d cells (%d bearings x radii %d/%d/%d)"
		% [sampled, RING_BEARINGS, int(radii[0]), int(radii[1]), int(radii[2])])
	print("  blocked terrain    %d" % blocked)
	print("  unreachable        %d" % unreachable)
	if times.is_empty():
		print("  RING PROBLEM — nothing in the ring is walkable and reachable.")
		return
	print("  walkable+reachable %d   (of those, %d outside the lair band = seedable)"
		% [times.size(), outside_band])
	print("  walk times         min %s / median %s / max %s"
		% [_fmt(times[0]), _fmt(times[times.size() / 2]), _fmt(times[-1])])
	print("  worst detour       %.2fx straight-line, at cell %s (limit %.2fx)"
		% [worst, worst_cell, MAX_RING_DETOUR])
	if over == 0 and outside_band > 0:
		print("  RING OK — routing never inflates a ring distance past the limit, so the")
		print("            %d-%d cell ring really is a %s-%s ring. %d cells are seedable."
			% [ring[0], ring[1], _fmt(band[0]), _fmt(band[1]), outside_band])
	elif outside_band == 0:
		print("  RING PROBLEM — no reachable ring cell sits outside the lair band.")
	else:
		print("  RING PARTIAL — %d cell(s) route past %.2fx; seed away from those bearings."
			% [over, MAX_RING_DETOUR])

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
