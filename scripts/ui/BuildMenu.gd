class_name BuildMenu
extends Node

## Town > Build: the buildable row, the Demolish toggle, the two click-to-target
## modes they arm, and the placement/demolition that happens on the next map
## click.
##
## Extracted from Main.gd (CLEANUP_PLAN.md Pass 4). **The split with Main.gd is
## deliberate and load-bearing.** This module owns the two modes' *state* and
## what they do when a cell is finally clicked; Main.gd keeps the *arbitration*
## -- the `_unhandled_input` priority order (placement > demolish > rally >
## inspect) and the Esc handling -- because that is the one place that has to
## see every mode at once. Main.gd asks `is_placing()` / `is_demolishing()` and
## calls `try_place()` / `try_demolish()`; it never reaches into the state.
##
## The third mode, Command Undead's rally point, lives in Main.gd. Arming a
## build or demolish must drop it, which is why that leaves as a signal rather
## than a direct call.

## Arming placement or demolish must cancel rally placement -- the three
## click-to-target modes are mutually exclusive.
signal rally_cancel_requested
## Placement and demolish own the screen; a stale inspector would sit there
## describing something you're no longer looking at.
signal inspector_close_requested
## A building went down. Main.gd writes the history line.
signal placed(display_name: String, cell: Vector2i)
## A building came down. Main.gd writes the history line.
signal demolished(display_name: String, cell: Vector2i)
## The Throne refused demolition. Main.gd logs and alerts.
signal demolish_refused(display_name: String)

# ---------------- Owned Controls ----------------
var build_row: HBoxContainer
var demolish_tab_btn: Button
## The shared click-to-target hint. Owned here because two of the three modes
## are this module's, but Main.gd drives it for rally placement via
## show_hint() / hide_hint().
var hint_label: Label

# ---------------- Mode state ----------------
# Read by Main.gd's arbitration through is_placing()/is_demolishing() only.
var _pending_building_id: String = ""  # "" = not in placement mode
var _demolish_mode: bool = false

# ---------------- References handed in by Main.gd ----------------
var _settlement: SettlementGrid

## Built before the bottom shell so the hint sits under the floating panels in
## child order, exactly where it was in Main.gd's build sequence.
func build_hint(hud_root: Control) -> void:
	hint_label = Label.new()
	hint_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hint_label.position = Vector2(10, 88)
	hint_label.add_theme_font_size_override("font_size", 12)
	hint_label.visible = false
	hud_root.add_child(hint_label)

func build_row_into(cmd_town: VBoxContainer, settlement: SettlementGrid) -> void:
	_settlement = settlement
	# Rebuilt by populate() whenever the settlement changes (a new Workshop
	# can unlock Blacksmith/Barracks appearing here).
	build_row = HBoxContainer.new()
	build_row.add_theme_constant_override("separation", 6)
	cmd_town.add_child(build_row)

	# A recruit moving into a house frees a Barracks slot and can change what
	# is buildable, and nothing else needs to happen when it does.
	EventBus.recruit_housed.connect(func(_f, _cell): populate())

## Shown/hidden by Main.gd's category tab arbitration, which has to see all
## three tabs to pick exactly one.
func set_tab_visible(v: bool) -> void:
	if build_row:
		build_row.visible = v

# ---------------- Mode queries, for Main.gd's arbitration ----------------

func is_placing() -> bool:
	return _pending_building_id != ""

func is_demolishing() -> bool:
	return _demolish_mode

## The shared mode hint. Main.gd drives this for rally placement.
func show_hint(text: String) -> void:
	hint_label.text = text
	hint_label.visible = true

func hide_hint() -> void:
	hint_label.visible = false

## Refreshes the Build tab's inline row of buildable entries. Called once at
## startup and again whenever a building is placed (a new Workshop can unlock
## Blacksmith/Barracks appearing here, per BuildingCatalog's `requires` gate).
func populate() -> void:
	if not build_row:
		return
	for child in build_row.get_children():
		child.queue_free()
	var ids: Array = BuildingCatalog.buildable_ids(_settlement)
	if ids.is_empty():
		var lbl := Label.new()
		lbl.text = "(nothing available)"
		build_row.add_child(lbl)
	else:
		for id in ids:
			var bid: String = id  # explicit re-bind for the closure below, same pattern used elsewhere
			var data: Dictionary = BuildingCatalog.get_building(bid)
			var cost_str := _format_cost(data.get("cost", {}))
			var b := Button.new()
			b.text = data.get("display_name", bid)
			b.tooltip_text = cost_str if cost_str != "" else "free"
			b.pressed.connect(func(): enter_placement_mode(bid))
			build_row.add_child(b)

	# Demolish sits at the end of the row, separated from the buildable list,
	# so it doesn't read as just another thing to build. Toggle button, not a
	# one-shot action -- pressing it enters demolish mode; the actual removal
	# happens on the next map click (see try_demolish()).
	build_row.add_child(VSeparator.new())
	demolish_tab_btn = Button.new()
	demolish_tab_btn.text = "Demolish"
	demolish_tab_btn.tooltip_text = "Click, then select a building on the map to remove it. No resource refund."
	demolish_tab_btn.pressed.connect(toggle_demolish_mode)
	build_row.add_child(demolish_tab_btn)
	_restyle_demolish_button()

func _format_cost(cost: Dictionary) -> String:
	var parts: Array = []
	for kind in cost.keys():
		parts.append("%d %s" % [cost[kind], kind])
	return ", ".join(parts)

func enter_placement_mode(building_id: String) -> void:
	if _demolish_mode:
		toggle_demolish_mode()  # the three click-to-target modes are mutually exclusive
	rally_cancel_requested.emit()
	# The inspector would sit there describing something you're no longer
	# looking at, and its Close button would be a click that doesn't place a
	# building. Placement mode owns the screen.
	inspector_close_requested.emit()
	_pending_building_id = building_id
	var data: Dictionary = BuildingCatalog.get_building(building_id)
	show_hint("Placing %s -- click an empty tile (Esc to cancel)" % data.get("display_name", building_id))

func cancel_placement() -> void:
	_pending_building_id = ""
	hide_hint()

## Toggles demolish mode on/off. Cancels any pending placement first (the two
## click-to-target modes can't both be active), and restyles the Demolish
## button so it's visually obvious the mode is armed.
func toggle_demolish_mode() -> void:
	if _pending_building_id != "":
		cancel_placement()
	rally_cancel_requested.emit()
	_demolish_mode = not _demolish_mode
	_restyle_demolish_button()
	if _demolish_mode:
		inspector_close_requested.emit()  # same reasoning as enter_placement_mode
		show_hint("Demolishing -- click a building to remove it (Esc to cancel)")
	else:
		hide_hint()

func _restyle_demolish_button() -> void:
	if not demolish_tab_btn:
		return
	demolish_tab_btn.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45) if _demolish_mode else Color(0.85, 0.6, 0.6))

func try_place(cell: Vector2i) -> void:
	var id := _pending_building_id
	var data: Dictionary = BuildingCatalog.get_building(id)
	if data.is_empty():
		cancel_placement()
		return
	if not _settlement.can_place(cell):
		EventBus.build_failed.emit("That tile is occupied.")
		return
	var cost: Dictionary = data.get("cost", {})
	if not GameState.can_afford_cost(cost):
		EventBus.build_failed.emit("Not enough resources for %s (%s)." % [data.get("display_name", id), _format_cost(cost)])
		return
	# can_afford_cost() already guards this, so spend_resource() "should"
	# always succeed here -- but checking its return value anyway means a
	# future change that lets the two drift out of sync (e.g. a resource
	# type that can go negative, or a cost check that doesn't match spend
	# semantics 1:1) fails loud instead of silently handing out a free building.
	for kind in cost.keys():
		if not GameState.spend_resource(kind, cost[kind]):
			push_warning("BuildMenu: spend_resource('%s', %d) failed after can_afford_cost passed -- aborting placement." % [kind, cost[kind]])
			return
	var building := Building.make_from_data(id, data)
	_settlement.place_building(building, cell)
	placed.emit(building.display_name, cell)
	cancel_placement()

## Removes whatever's on `cell`, if anything. Mirrors try_place()'s shape:
## empty tile clicked -> silently stay in demolish mode (no message needed,
## same as clicking an occupied tile during placement); building found ->
## remove it via SettlementGrid.remove_building(), which already refuses the
## main building (Throne of Bones) -- surfaced as a log + alert rather than a
## silent no-op. No resource refund, per explicit user confirmation. Exits
## demolish mode after a successful removal, same as placement mode exiting
## after a successful build.
func try_demolish(cell: Vector2i) -> void:
	if not _settlement.cells.has(cell):
		return
	var building: Building = _settlement.cells[cell]
	if building.is_main_building:
		demolish_refused.emit(building.display_name)
		return
	var demolished_name := building.display_name
	if _settlement.remove_building(cell):
		demolished.emit(demolished_name, cell)
	toggle_demolish_mode()
