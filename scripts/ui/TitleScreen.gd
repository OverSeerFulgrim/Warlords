extends CanvasLayer
class_name TitleScreen
## The first thing on screen when the game launches (review 2026-09-26: there
## was no title, no menu). Shown once per session over a paused world -- a new
## run from the run-end screen goes straight in. The world is already built
## behind it, so "Begin" costs nothing.
##
## Reads a summary Dictionary Main hands it (level, XP, runs, last epitaph) and
## nothing else, same as the run-end screen.

signal begin_requested
signal lair_requested

const WIDTH := 440.0

var _body: VBoxContainer
var begin_button: Button

func _ready() -> void:
	layer = 62
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.menu_theme()
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.04, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	# The kit's main-menu frame, as large as the window allows at its own
	# shape; the menu sits in its inside and scrolls if the window is short.
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	root.add_child(margin)
	var fit := AspectRatioContainer.new()
	fit.ratio = float(UiKit.TITLE_FRAME.get_width()) / float(UiKit.TITLE_FRAME.get_height())
	fit.stretch_mode = AspectRatioContainer.STRETCH_FIT
	fit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(fit)
	var frame := TextureRect.new()
	frame.texture = UiKit.TITLE_FRAME
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fit.add_child(frame)
	var inside := ScrollContainer.new()
	inside.anchor_left = UiKit.TITLE_INSIDE.position.x
	inside.anchor_top = UiKit.TITLE_INSIDE.position.y
	inside.anchor_right = UiKit.TITLE_INSIDE.end.x
	inside.anchor_bottom = UiKit.TITLE_INSIDE.end.y
	inside.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(inside)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inside.add_child(center)
	_body = VBoxContainer.new()
	_body.custom_minimum_size = Vector2(WIDTH, 0)
	_body.add_theme_constant_override("separation", 8)
	center.add_child(_body)
	visible = false

func is_showing() -> bool:
	return visible

## `info`: {level, xp, next_level_xp, runs, last_epitaph}.
func show_title(info: Dictionary) -> void:
	_last_info = info
	for c in _body.get_children():
		c.queue_free()
	var title := Label.new()
	title.text = "WARLORDS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.86, 0.72, 1.0))
	_body.add_child(title)
	var sub := Label.new()
	sub.text = "Undead Empire"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 15)
	sub.modulate = Color(1, 1, 1, 0.7)
	_body.add_child(sub)
	_body.add_child(UiKit.divider())

	var runs: int = int(info.get("runs", 0))
	var line := Label.new()
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_theme_font_size_override("font_size", 13)
	if runs == 0:
		line.text = "He is weak, and he is hidden. Nobody knows his name yet."
	else:
		line.text = "Level %d  ·  %d XP  ·  %d %s" % [int(info.get("level", 1)), int(info.get("xp", 0)),
			runs, "run" if runs == 1 else "runs"]
	_body.add_child(line)
	var last: String = String(info.get("last_epitaph", ""))
	if last != "":
		var ep := Label.new()
		ep.text = last
		ep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ep.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ep.custom_minimum_size = Vector2(WIDTH, 0)
		ep.add_theme_font_size_override("font_size", 11)
		ep.modulate = Color(1, 1, 1, 0.6)
		_body.add_child(ep)

	begin_button = _button("Begin the run", func():
		visible = false
		begin_requested.emit())
	_button("The Lair", func(): lair_requested.emit())
	_button("Controls", _show_controls)
	_button("Quit", func(): get_tree().quit())
	visible = true
	begin_button.grab_focus.call_deferred()

func _show_controls() -> void:
	for c in _body.get_children():
		c.queue_free()
	_body.add_child(PauseMenu.heading("Controls", 18))
	PauseMenu.build_controls_grid(_body)
	var hint := Label.new()
	hint.text = "He has no dead yet. Open a grave and raise what is inside; bones raise more. Bring what you find home to the Throne. If he dies, the run is over."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(WIDTH, 0)
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(1, 1, 1, 0.7)
	_body.add_child(hint)
	_button("Back", func(): show_title(_last_info))

var _last_info: Dictionary = {}

func set_info(info: Dictionary) -> void:
	_last_info = info

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 40)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(cb)
	_body.add_child(b)
	return b
