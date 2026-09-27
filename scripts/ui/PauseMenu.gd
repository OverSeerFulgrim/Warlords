extends CanvasLayer
class_name PauseMenu
## Space / P / Esc (with nothing else to close): the game stops, and this is the
## only thing that answers. Resume, the controls list, abandon the run (behind a
## confirm -- review 2026-09-26: Surrender had none), and quit.
##
## PROCESS_MODE_ALWAYS so it takes input while the tree is paused underneath.
## It owns the pause it sets and never clears one it did not set, so it cannot
## unpause the run-end screen by accident.

signal abandon_confirmed
## Flee the region (alive, from the lair) -- Main opens the keep-3 picker.
signal flee_requested

const WIDTH := 380.0

var _panel: PanelContainer
var _body: VBoxContainer
var _paused_by_me: bool = false
## Asked when the menu opens: can he flee from where he stands?
var flee_available: Callable = Callable()

func _ready() -> void:
	layer = 58
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(WIDTH, 0)
	_panel.add_theme_stylebox_override("panel", PauseMenu.panel_style())
	center.add_child(_panel)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	_panel.add_child(_body)
	visible = false

static func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.04, 0.08, 0.96)
	style.border_color = Color(0.55, 0.42, 0.75, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	return style

func is_open() -> bool:
	return visible

func open() -> void:
	if visible:
		return
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_me = true
	visible = true
	_show_main()

func close() -> void:
	if not visible:
		return
	visible = false
	if _paused_by_me:
		get_tree().paused = false
		_paused_by_me = false

## Surrender's door: straight to the confirm, never a one-click end of the run.
func open_confirm_abandon() -> void:
	open()
	_show_confirm()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("cancel") or event.is_action_pressed("pause", false, false):
		close()
		get_viewport().set_input_as_handled()

func _clear() -> void:
	for c in _body.get_children():
		c.queue_free()

func _show_main() -> void:
	_clear()
	_body.add_child(PauseMenu.heading("Paused", 22))
	_button("Resume", close)
	_button("Controls", _show_controls)
	_body.add_child(HSeparator.new())
	var flee := _button("Flee the region…", func():
		close()
		flee_requested.emit())
	var can: bool = flee_available.is_valid() and bool(flee_available.call())
	flee.disabled = not can
	flee.tooltip_text = "End the run alive and keep 3 things he found." if can \
		else "Only from the lair: get him home first."
	_button("Abandon this run…", _show_confirm)
	_button("Quit the game", func(): get_tree().quit())
	_focus_first.call_deferred()

func _show_controls() -> void:
	_clear()
	_body.add_child(PauseMenu.heading("Controls", 18))
	PauseMenu.build_controls_grid(_body)
	_button("Back", _show_main)
	_focus_first.call_deferred()

func _show_confirm() -> void:
	_clear()
	_body.add_child(PauseMenu.heading("Abandon the run?", 18))
	var l := Label.new()
	l.text = "The run ends here. XP already earned is kept and the chronicle gets its line; everything else is lost -- including anything carried in from the Lair. (Fleeing the region from the lair keeps 3 things.)"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(WIDTH - 44.0, 0)
	l.add_theme_font_size_override("font_size", 12)
	_body.add_child(l)
	var yes := _button("Abandon the run", func():
		close()
		abandon_confirmed.emit())
	yes.add_theme_color_override("font_color", Color(0.95, 0.4, 0.4))
	_button("Keep playing", _show_main)
	_focus_first.call_deferred()

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 32)
	b.pressed.connect(cb)
	_body.add_child(b)
	return b

func _focus_first() -> void:
	for c in _body.get_children():
		if c is Button and not c.is_queued_for_deletion():
			c.grab_focus()
			return

static func heading(text: String, size: int) -> Label:
	var t := Label.new()
	t.text = text
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", size)
	t.add_theme_color_override("font_color", Color(0.85, 0.74, 1.0))
	return t

## The key reference, as the keyboard in front of the player names its keys
## (`Controls.label_for`). Shared with the title screen.
static func build_controls_grid(parent: Control) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 3)
	parent.add_child(grid)
	for row in Controls.reference_rows():
		var k := Label.new()
		k.text = String(row[0])
		k.add_theme_font_size_override("font_size", 12)
		k.add_theme_color_override("font_color", Color(1.0, 0.86, 0.5))
		grid.add_child(k)
		var d := Label.new()
		d.text = String(row[1])
		d.add_theme_font_size_override("font_size", 12)
		grid.add_child(d)
