class_name HudWindow
extends PanelContainer
## A titled floating window for the HUD (the HUD redo, 2026-09-26): History
## (L), Workforce, the Build tray's roomier cousin. Centred, closable, with a
## scrolling body the caller fills. It does not pause the world -- these are
## places to look, not decisions.

signal closed

var body: VBoxContainer
var title_label: Label
var _scroll: ScrollContainer

func setup(title: String, width: float, height: float, scroll: bool = true) -> HudWindow:
	add_theme_stylebox_override("panel", HudStyle.box(HudStyle.BG, HudStyle.BORDER_ACCENT, 10, 14))
	set_anchors_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(width, height)
	position = Vector2(-width * 0.5, -height * 0.5)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	title_label = HudStyle.label(title, 20)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	var x := Button.new()
	x.text = "Close"
	x.custom_minimum_size = Vector2(88, 40)
	HudStyle.style_button(x, false, 14)
	x.pressed.connect(close)
	head.add_child(x)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if scroll:
		_scroll = ScrollContainer.new()
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_scroll.custom_minimum_size = Vector2(width - 28.0, height - 80.0)
		outer.add_child(_scroll)
		_scroll.add_child(body)
	else:
		outer.add_child(body)
	visible = false
	return self

func is_open() -> bool:
	return visible

func open() -> void:
	visible = true
	# The newest entries are at the bottom of a log; start there.
	if _scroll:
		await get_tree().process_frame
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)

func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()

func toggle() -> void:
	if visible:
		close()
	else:
		open()
