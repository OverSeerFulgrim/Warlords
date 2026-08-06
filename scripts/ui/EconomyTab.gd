class_name EconomyTab
extends Node

## Town > Economy: the gathering-priority list, its per-row status text, and the
## workforce/map-stock summary line, plus the tab's two action buttons.
##
## Extracted from Main.gd (CLEANUP_PLAN.md Pass 4). The priority list is the
## "indirect control" pillar applied to labor -- the player sets policy and the
## workforce sorts itself out -- so everything here reads WorkerSystem and
## writes back through its `move_priority` / `set_threshold` API. No sim state
## lives in this module; it is a view over WorkerSystem plus the controls that
## poke it.
##
## Raising a worker costs Bones and writes a history line, so that stays Main's
## and goes out as a signal. Lay Low is a pure GameState call with no Main
## involvement, so it is wired directly.

## Recruit Worker was pressed. Main.gd owns the cost check and the log line.
signal recruit_worker_pressed

const PRIORITY_ROW_HEIGHT := 24.0
const PRIORITY_FONT_SIZE := 10
const PRIORITY_ARROW_WIDTH := 22.0

# ---------------- Owned Controls ----------------
var economy_row: VBoxContainer
var workers_row: VBoxContainer     # holds the priority list + workforce summary
var workforce_label: Label
var priority_status_labels: Dictionary = {}  # kind String -> Label

# ---------------- References handed in by Main.gd ----------------
var _worker_system: WorkerSystem
var _resource_field: ResourceField

## Builds the tab into `cmd_town`. Both systems already exist by the time the
## UI is built, so unlike the other modules there is nothing to hand over later.
func build(cmd_town: VBoxContainer, worker_system: WorkerSystem, resource_field: ResourceField) -> void:
	_worker_system = worker_system
	_resource_field = resource_field

	economy_row = VBoxContainer.new()
	cmd_town.add_child(economy_row)
	var economy_actions := HBoxContainer.new()
	economy_actions.add_theme_constant_override("separation", 6)
	economy_row.add_child(economy_actions)

	var recruit := Button.new()
	recruit.text = "Recruit Worker (5 Bones)"
	recruit.pressed.connect(func(): recruit_worker_pressed.emit())
	economy_actions.add_child(recruit)
	# Forge Equipment, Train Followers and Dispatch Mission are hard-locked
	# alongside the bounty board -- all three are Stage 4. Their handlers
	# (_forge_equipment/_train_followers) and MissionSystem are deliberately
	# left intact and unreferenced, so re-surfacing them at Stage 4 is one
	# button each.
	var lay_low := Button.new()
	lay_low.text = "Lay Low"
	lay_low.pressed.connect(func(): GameState.lay_low())
	economy_actions.add_child(lay_low)

	# The global resource priority list -- replaces the per-worker "click to
	# cycle Idle/Wood/Stone/Bones" buttons that used to sit here. See
	# build_priority_rows() for the layout and WorkerSystem's `priorities`
	# for what the numbers mean.
	workers_row = VBoxContainer.new()
	workers_row.add_theme_constant_override("separation", 2)
	economy_row.add_child(workers_row)

	EventBus.priorities_changed.connect(build_priority_rows)

## Shown/hidden by Main.gd's category tab arbitration, which has to see all
## three tabs to pick exactly one.
func set_tab_visible(v: bool) -> void:
	if economy_row:
		economy_row.visible = v

## One row per gatherable resource:
##
##     [^][v]  Wood    stop at [ 40 ]   Working
##     [^][v]  Stone   stop at [ 20 ]   Satisfied
##
## Workers serve the highest row whose stock is under its threshold; at or
## above it, that row is satisfied and they fall through to the next. This
## deliberately replaces per-worker assignment -- you set policy, the workforce
## sorts itself out, which is the "indirect control" design pillar applied to
## labor. Rebuilt wholesale on EventBus.priorities_changed rather than
## patched in place; four rows is far too little to bother diffing.
func build_priority_rows() -> void:
	if not workers_row:
		return
	for child in workers_row.get_children():
		child.queue_free()
	priority_status_labels.clear()

	var header := Label.new()
	header.text = "Gathering priorities — workers serve the top resource still under its threshold"
	_compact(header)
	header.modulate = Color(1, 1, 1, 0.6)
	workers_row.add_child(header)

	for i in range(_worker_system.priorities.size()):
		var entry: Dictionary = _worker_system.priorities[i]
		var kind: String = entry["kind"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		var up := Button.new()
		up.text = "^"
		up.tooltip_text = "Raise %s priority" % kind
		up.disabled = i == 0
		_compact(up)
		up.custom_minimum_size = Vector2(PRIORITY_ARROW_WIDTH, PRIORITY_ROW_HEIGHT)
		up.pressed.connect(func(): _worker_system.move_priority(kind, -1))
		row.add_child(up)

		var down := Button.new()
		down.text = "v"
		down.tooltip_text = "Lower %s priority" % kind
		down.disabled = i == _worker_system.priorities.size() - 1
		_compact(down)
		down.custom_minimum_size = Vector2(PRIORITY_ARROW_WIDTH, PRIORITY_ROW_HEIGHT)
		down.pressed.connect(func(): _worker_system.move_priority(kind, 1))
		row.add_child(down)

		var name_label := Label.new()
		name_label.text = "%d. %s" % [i + 1, kind.capitalize()]
		name_label.custom_minimum_size = Vector2(70, 0)
		_compact(name_label)
		row.add_child(name_label)

		var stop_label := Label.new()
		stop_label.text = "stop at"
		_compact(stop_label)
		stop_label.modulate = Color(1, 1, 1, 0.6)
		row.add_child(stop_label)

		# A real SpinBox rather than the codebase's usual +/- button pair:
		# thresholds are an arbitrary number the player types, not a small
		# fixed choice set, which is exactly the case the button-pair
		# convention doesn't cover.
		# The SpinBox is what actually set the old 31px row height -- its
		# default minimum is the tallest thing in the row. Capping it here is
		# most of the compaction; its internal LineEdit needs the font
		# override too or it forces the height back up.
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = 999
		spin.step = 5
		spin.value = entry["threshold"]
		spin.custom_minimum_size = Vector2(66, PRIORITY_ROW_HEIGHT)
		spin.add_theme_font_size_override("font_size", PRIORITY_FONT_SIZE)
		spin.get_line_edit().add_theme_font_size_override("font_size", PRIORITY_FONT_SIZE)
		spin.value_changed.connect(func(v: float): _worker_system.set_threshold(kind, int(v)))
		row.add_child(spin)

		var status := Label.new()
		_compact(status)
		priority_status_labels[kind] = status
		row.add_child(status)

		workers_row.add_child(row)

	# Workforce census and map stock share one line. They used to be two
	# labels, which cost ~16px of a band that had none to spare, and they read
	# fine together -- "who is working" next to "what is left to work on".
	workforce_label = Label.new()
	_compact(workforce_label)
	workforce_label.modulate = Color(1, 1, 1, 0.75)
	workers_row.add_child(workforce_label)

	refresh_status()

## Per-row Working/Satisfied/None-left text plus the workforce and map-stock
## summaries. Cheap enough to run every frame from Main.gd's _process -- the
## trip loop changes worker states continuously, so there's no useful signal to
## hang this on that wouldn't just fire constantly anyway.
func refresh_status() -> void:
	for kind in priority_status_labels.keys():
		var lbl: Label = priority_status_labels[kind]
		var status: String = _worker_system.priority_status(kind)
		lbl.text = status
		match status:
			"Working":
				lbl.modulate = Color(0.6, 0.9, 0.6)
			"Satisfied":
				lbl.modulate = Color(0.7, 0.7, 0.7)
			"None left":
				lbl.modulate = Color(0.95, 0.6, 0.5)
			_:
				lbl.modulate = Color(1, 1, 1)
	if workforce_label:
		var stock: String = _resource_field.stock_summary() if _resource_field else ""
		workforce_label.text = "%s   —   %s" % [_worker_system.workforce_summary(), stock]

## Shrinks a Control to the priority list's compact metrics. Godot's default
## theme gives Buttons and SpinBoxes a ~31px minimum height, which is fine for
## the main action buttons but far too tall for a four-row list crammed into
## the bottom band.
func _compact(c: Control) -> void:
	c.add_theme_font_size_override("font_size", PRIORITY_FONT_SIZE)
	if c is Button:
		# Trim the vertical padding too -- the font override alone doesn't
		# shrink a Button, its StyleBox content margins set the floor.
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var sb := StyleBoxEmpty.new()
			sb.content_margin_top = 2
			sb.content_margin_bottom = 2
			sb.content_margin_left = 4
			sb.content_margin_right = 4
			c.add_theme_stylebox_override(state, sb)
