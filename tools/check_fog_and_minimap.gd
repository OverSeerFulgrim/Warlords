extends Node
## Asserts the fog's multi-source behaviour and the minimap's friendly dots --
## the two visibility changes from the R1 playtest (requests #3 and #4).
##
##   godot --headless --path . res://tools/check_fog_and_minimap.tscn
##
## **Kept in the repo.** `FogOfWar` grew from "one disc around the villain" to
## "a lit set rebuilt from N sources", and the thing that makes that safe -- a
## unit's disc going back to REMEMBERED when the unit leaves -- is invisible
## until it breaks. It is also exactly the bug a refcounted implementation
## would introduce, so it wants a standing test rather than a one-off eyeball.
##
## A **scene** rather than a `-s` script because `-s` compiles before the
## autoloads register (see CLAUDE.md's gotchas).

const UNIT_CELLS_AWAY := 20

var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	get_tree().root.size = Vector2i(1400, 760)
	await get_tree().process_frame
	var main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var world: WorldMap = main.world_map
	var fog: FogOfWar = main.fog
	var villain: Necromancer = main.villain

	print("\n=== Fog sources and minimap dots ===\n")
	_radii_unchanged()
	_worker_disc(world, fog, villain)
	_early_out(world, fog, villain)
	_frame_cost(fog, villain)
	_minimap_dots(main)
	_input_wiring(main, world)
	await _debug_overlay_changes_nothing(main, fog)

	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

# ---------------- The dev site overlay is read-only ---------------------------

## F3's overlay draws sites through the fog, which is exactly the kind of aid
## that turns into a bug the day it quietly marks something discovered. The
## rule is that it changes **nothing**, and the fog is the sharpest place to
## assert it: a byte-identical image across a full toggle cycle means no cell
## was lit, remembered, or touched.
##
## The second half matters as much as the first. No site carries a `discovered`
## flag today — the overlay has nothing to set — and this asserts that absence
## on purpose, so that whoever adds one (the Raven's pings are the obvious
## caller) finds out here that the debug overlay is a place it must not be set.
func _debug_overlay_changes_nothing(main, fog: FogOfWar) -> void:
	var overlay: DebugSiteOverlay = main.debug_site_overlay
	_check("the overlay exists and starts OFF", overlay != null and not overlay.is_on())
	if overlay == null:
		return

	var before: PackedByteArray = fog.fog_texture().get_image().get_data()
	var sites: Array = main.world_sites.lootable_sites()
	var state_before: Array = _site_state(sites)

	_check("F3 turns it on", overlay.toggle())
	_check("...and it now offers minimap points", overlay.minimap_points().size() == sites.size(),
		"%d of %d" % [overlay.minimap_points().size(), sites.size()])
	# Let the engine actually draw it -- the draw is the thing under test, and
	# calling `_draw()` by hand is refused outside the draw notification.
	overlay.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	_check("F3 again turns it off", not overlay.toggle())
	_check("...and it offers none while hidden", overlay.minimap_points().is_empty())

	var after: PackedByteArray = fog.fog_texture().get_image().get_data()
	_check("the fog is BYTE-IDENTICAL across the toggle", before == after,
		"%d bytes differ" % _byte_diff(before, after))
	_check("no site's state moved", _site_state(sites) == state_before)
	_check("...and no site carries a discovered flag for it to have set",
		not ("discovered" in sites[0]) if not sites.is_empty() else true)

## Everything about a site the overlay could plausibly disturb, as a comparable
## snapshot. Loot state rather than position, because position is the one thing
## a marker legitimately reads.
func _site_state(sites: Array) -> Array:
	var out: Array = []
	for s in sites:
		out.append([s.charges_left, s.is_spent(), s.is_guarded(), s.graves_disturbed,
			s.remainder.duplicate(), s.pulls_taken])
	return out

func _byte_diff(a: PackedByteArray, b: PackedByteArray) -> int:
	if a.size() != b.size():
		return absi(a.size() - b.size())
	var n: int = 0
	for i in range(a.size()):
		if a[i] != b[i]:
			n += 1
	return n

# ---------------- The villain's own numbers are untouched --------------------

func _radii_unchanged() -> void:
	_check("villain reveal radius is still 7",
		FogOfWar.REVEAL_RADIUS_CELLS == 7.0,
		"got %s" % FogOfWar.REVEAL_RADIUS_CELLS)
	_check("friendly unit reveal radius is 3",
		FogOfWar.UNIT_REVEAL_RADIUS_CELLS == 3.0,
		"got %s" % FogOfWar.UNIT_REVEAL_RADIUS_CELLS)

# ---------------- A worker lights its own disc, and gives it back ------------

## The headline assertion: a unit 20 cells from the villain -- far outside his
## own 7-cell disc, so nothing else could be lighting that ground -- lights a
## 3-cell disc, and that disc returns to REMEMBERED when the unit goes away.
##
## The test cell is deliberately outside the lair band. Inside it every cell is
## permanently VISIBLE (`reveal_permanently`), so a test sited there would pass
## no matter what this code did.
func _worker_disc(world: WorldMap, fog: FogOfWar, villain: Necromancer) -> void:
	var here: Vector2i = world.cell_at(villain.position)
	var there := Vector2i(here.x, here.y - UNIT_CELLS_AWAY)
	if world.lair_band.has_point(there):
		there = Vector2i(here.x, here.y - UNIT_CELLS_AWAY * 2)
	_check("test cell is outside the lair band (or the test proves nothing)",
		not world.lair_band.has_point(there),
		"%s is inside %s" % [there, world.lair_band])

	var centre: Vector2 = world.cell_centre_px(there)
	var villain_only: Array = [[villain.position, FogOfWar.REVEAL_RADIUS_CELLS]]

	fog.update_for(villain_only)
	_check("before: the distant cell is not VISIBLE",
		fog.state_at(centre) != FogOfWar.State.VISIBLE,
		"state %d" % fog.state_at(centre))

	fog.update_for([
		[villain.position, FogOfWar.REVEAL_RADIUS_CELLS],
		[centre, FogOfWar.UNIT_REVEAL_RADIUS_CELLS],
	])
	_check("worker lights the cell it stands in",
		fog.state_at(centre) == FogOfWar.State.VISIBLE,
		"state %d" % fog.state_at(centre))
	_check("worker lights 3 cells out",
		fog.state_at(world.cell_centre_px(there + Vector2i(3, 0))) == FogOfWar.State.VISIBLE,
		"the disc is smaller than its radius")
	_check("worker does NOT light 4 cells out",
		fog.state_at(world.cell_centre_px(there + Vector2i(4, 0))) != FogOfWar.State.VISIBLE,
		"the disc is bigger than its radius")
	# Round, not square: the corner of the bounding box is outside r=3.
	_check("the disc is round, not square",
		fog.state_at(world.cell_centre_px(there + Vector2i(3, 3))) != FogOfWar.State.VISIBLE,
		"the corner of the bounding box is lit")

	var lit_with: int = _visible_count(fog, world, there, 5)
	_check("a 3-cell disc lights ~29 cells", lit_with >= 25 and lit_with <= 33,
		"lit %d" % lit_with)

	fog.update_for(villain_only)
	_check("the cell drops back to REMEMBERED when the worker leaves",
		fog.state_at(centre) == FogOfWar.State.REMEMBERED,
		"state %d (2 = still VISIBLE, 0 = wrongly forgotten)" % fog.state_at(centre))
	_check("the whole disc drops back -- none of it sticks",
		_visible_count(fog, world, there, 5) == 0,
		"%d cells still lit" % _visible_count(fog, world, there, 5))
	_check("and it is REMEMBERED, not UNEXPLORED -- seen ground stays seen",
		fog.state_at(world.cell_centre_px(there + Vector2i(2, 0))) == FogOfWar.State.REMEMBERED,
		"state %d" % fog.state_at(world.cell_centre_px(there + Vector2i(2, 0))))

## Cells within `span` of `centre` that are currently VISIBLE.
func _visible_count(fog: FogOfWar, world: WorldMap, centre: Vector2i, span: int) -> int:
	var n := 0
	for dy in range(-span, span + 1):
		for dx in range(-span, span + 1):
			var c := centre + Vector2i(dx, dy)
			if not world.in_bounds(c):
				continue
			if fog.state_at(world.cell_centre_px(c)) == FogOfWar.State.VISIBLE:
				n += 1
	return n

# ---------------- The early-out still early-outs -----------------------------

## The performance guarantee, asserted rather than assumed: standing still costs
## nothing. `changed` firing is the observable proxy for "it rebuilt", and 34
## sources is the playtest's own case (villain + 33 bound undead).
func _early_out(world: WorldMap, fog: FogOfWar, villain: Necromancer) -> void:
	var sources: Array = [[villain.position, FogOfWar.REVEAL_RADIUS_CELLS]]
	for i in range(33):
		sources.append([
			villain.position + Vector2(i * 3, 0), FogOfWar.UNIT_REVEAL_RADIUS_CELLS])
	fog.update_for(sources)

	var fired := [0]
	var counter := func(): fired[0] += 1
	fog.changed.connect(counter)

	for f in range(10):
		fog.update_for(sources)
	_check("34 sources standing still: 10 frames, 0 rebuilds", fired[0] == 0,
		"rebuilt %d times" % fired[0])

	# A sub-cell nudge is still the same cell, so still no rebuild.
	sources[5][0] += Vector2(1.0, 0.0)
	fog.update_for(sources)
	_check("a sub-cell nudge does not rebuild", fired[0] == 0,
		"rebuilt %d times" % fired[0])

	# A whole cell across the boundary must rebuild, exactly once.
	sources[5][0] += Vector2(float(WorldMap.CELL_SIZE), 0.0)
	fog.update_for(sources)
	_check("crossing a cell boundary rebuilds exactly once", fired[0] == 1,
		"rebuilt %d times" % fired[0])

	# Losing a unit changes the list length, which must also rebuild.
	sources.remove_at(5)
	fog.update_for(sources)
	_check("a unit disappearing rebuilds", fired[0] == 2,
		"rebuilt %d times" % fired[0])
	fog.changed.disconnect(counter)

# ---------------- What it actually costs -------------------------------------

## The playtest's own worst case -- the villain plus 33 bound undead -- timed
## on both paths, because the early-out is the whole reason this design is
## affordable and "it early-outs" is worth a number rather than a claim.
##
## Wall-clock microseconds via `Time.get_ticks_usec()`. That is the measuring
## instrument, not a gameplay timer, so CLAUDE.md's rule against it does not
## apply here (the same exemption `GameCamera._now()` takes for gesture timing).
func _frame_cost(fog: FogOfWar, villain: Necromancer) -> void:
	var sources: Array = [[villain.position, FogOfWar.REVEAL_RADIUS_CELLS]]
	for i in range(33):
		sources.append([
			villain.position + Vector2(i * 40, 0), FogOfWar.UNIT_REVEAL_RADIUS_CELLS])
	fog.update_for(sources)

	# Standing still: the path that runs on almost every frame.
	var t0: int = Time.get_ticks_usec()
	for i in range(1000):
		fog.update_for(sources)
	var idle_us: float = float(Time.get_ticks_usec() - t0) / 1000.0

	# Rebuilding: one source shifted a whole cell each iteration, so every call
	# takes the expensive branch -- dim the old set, relight 34 discs, upload.
	var t1: int = Time.get_ticks_usec()
	for i in range(1000):
		sources[1][0] = villain.position + Vector2(float(WorldMap.CELL_SIZE) * (i % 8), 0)
		fog.update_for(sources)
	var rebuild_us: float = float(Time.get_ticks_usec() - t1) / 1000.0

	print("  --    34 sources, standing still: %.1f us/call" % idle_us)
	print("  --    34 sources, full rebuild:   %.1f us/call" % rebuild_us)
	print("  --    a 60fps frame is 16667 us" )
	_check("standing still costs under 5% of a frame", idle_us < 833.0,
		"%.1f us" % idle_us)
	_check("even a rebuild every frame stays under a third of a frame",
		rebuild_us < 5555.0, "%.1f us" % rebuild_us)

# ---------------- The minimap draws its own units, and only those ------------

func _minimap_dots(main) -> void:
	var mm: Minimap = main.minimap
	_check("minimap takes its own clicks",
		mm.mouse_filter == Control.MOUSE_FILTER_STOP,
		"mouse_filter %d" % mm.mouse_filter)
	_check("minimap has a units source", mm.units_source.is_valid(), "none set")
	_check("friendly colour is distinct from the lair marker",
		_far_apart(Minimap.FRIENDLY_COLOR, Minimap.LAIR_COLOR),
		"too close to LAIR_COLOR")
	_check("friendly colour is distinct from the villain marker",
		_far_apart(Minimap.FRIENDLY_COLOR, Minimap.VILLAIN_COLOR),
		"too close to VILLAIN_COLOR")

	# _from_map is the inverse of _to_map -- the property both click paths rest
	# on. Round-tripped through a real position rather than asserted by reading
	# the arithmetic.
	var p := Vector2(1234.5, -678.25)
	var back: Vector2 = mm._from_map(mm._to_map(p))
	_check("minimap _from_map inverts _to_map", back.distance_to(p) < 0.01,
		"%s -> %s" % [p, back])

	# The rule the header states: your units are drawn, the wolf and the deer
	# are not. Asserted against the source, the way the R1 minimap test did.
	var src: String = FileAccess.get_file_as_string("res://scripts/ui/Minimap.gd")
	var code: String = _strip_comments(src)
	for banned in ["Wolf", "Patrol", "deer", "ResourceNode"]:
		_check("minimap code never mentions %s outside comments" % banned,
			not code.contains(banned), "found it in live code")

func _far_apart(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.4

## The R1 version of this check failed on the header's own comments, which name
## the units it ignores. Strip them before scanning.
func _strip_comments(src: String) -> String:
	var out := ""
	for line in src.split("\n"):
		var i: int = line.find("#")
		out += (line if i < 0 else line.substr(0, i)) + "\n"
	return out

# ---------------- The two new input paths, at the wiring level ---------------

## Simulated input never reaches the running game in this project (CLAUDE.md's
## first gotcha: neither `_unhandled_input` nor `Input.is_key_pressed` sees it),
## so the *gesture* still needs a human. What can be tested without one is
## everything downstream of the gesture -- and that is where the wiring bugs
## live, so it is worth testing.
##
## Each case drives the signal or handler the real input would reach, then
## asserts on the state it should have changed.
func _input_wiring(main, world: WorldMap) -> void:
	var villain: Necromancer = main.villain
	var camera: GameCamera = main.camera
	var vc: VillainController = main.villain_controller
	var mm: Minimap = main.minimap

	# --- right tap on the world walks him ---------------------------------
	var dest: Vector2 = villain.position + Vector2(500.0, 0.0)
	villain.clear_move_target()
	camera.right_tapped.emit(dest)
	_check("a right tap sets a move target", villain.has_move_target,
		"no target set")
	_check("and it is the tapped point", villain.move_target.is_equal_approx(dest),
		"%s" % villain.move_target)

	# --- it walks through step(), not around it ---------------------------
	var before: Vector2 = villain.position
	for i in range(30):
		villain.step(villain.target_direction(1.0 / 60.0), 1.0 / 60.0)
	_check("the target actually moves him", villain.position.distance_to(before) > 1.0,
		"moved %.2fpx" % villain.position.distance_to(before))
	_check("toward the target, not away",
		villain.position.distance_to(dest) < before.distance_to(dest),
		"got further away")
	_check("and step() saw it as movement, so facing/idle still work",
		villain.is_moving, "is_moving false after a driven step")

	# --- arrival clears it ------------------------------------------------
	villain.set_move_target(villain.position + Vector2(0.5, 0.0))
	var dir: Vector2 = villain.target_direction(1.0 / 60.0)
	_check("arriving inside the epsilon clears the target",
		not villain.has_move_target and dir == Vector2.ZERO, "still outstanding")

	# --- an armed click-to-target mode eats the tap instead ---------------
	villain.clear_move_target()
	main._rally_placement_mode = true
	camera.right_tapped.emit(dest)
	_check("a right tap cancels an armed rally placement",
		not main._rally_placement_mode, "mode still armed")
	_check("and does NOT also walk him", not villain.has_move_target,
		"it did both")

	# --- minimap left click jumps the camera ------------------------------
	var target_cell := Vector2i(100, 100)
	var target_px: Vector2 = world.cell_centre_px(target_cell)
	camera.position = world.cell_centre_px(Vector2i(20, 20))
	vc.following = true
	mm.camera_requested.emit(target_px)
	_check("a minimap left-click moves the camera",
		world.cell_at(camera.position).distance_to(Vector2(target_cell)) < 12.0,
		"camera at cell %s" % world.cell_at(camera.position))
	_check("and breaks follow, exactly as a manual pan does", not vc.following,
		"still following")

	# --- ...but only when it was already following ------------------------
	vc.following = false
	var ticks: int = camera.manual_pan_ticks
	mm.camera_requested.emit(target_px)
	_check("with follow already off it stays off and disturbs nothing",
		not vc.following and camera.manual_pan_ticks == ticks,
		"follow or pan ticks changed")

	# --- minimap right click walks him ------------------------------------
	villain.clear_move_target()
	mm.move_requested.emit(target_px)
	_check("a minimap right-click sets a move target", villain.has_move_target,
		"no target set")
	_check("to the minimap point", villain.move_target.is_equal_approx(target_px),
		"%s" % villain.move_target)
	villain.clear_move_target()

	# --- the tap/drag split lives in exactly one place ---------------------
	var offenders: Array = []
	for path in ["res://scripts/Main.gd", "res://scripts/ui/Minimap.gd",
			"res://scripts/villain/VillainController.gd"]:
		if _strip_comments(FileAccess.get_file_as_string(path)).contains("MOUSE_BUTTON_RIGHT"):
			offenders.append(path)
	# Minimap is allowed: a drag across it is a click on another cell, not a
	# pan, so it has no second meaning to separate out. Main and the controller
	# must never test the button.
	offenders.erase("res://scripts/ui/Minimap.gd")
	_check("only GameCamera and Minimap test MOUSE_BUTTON_RIGHT",
		offenders.is_empty(), "also: %s" % str(offenders))

# ---------------- Reporting --------------------------------------------------

func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s   (%s)" % [what, detail])
