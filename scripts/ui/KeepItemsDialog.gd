extends CanvasLayer
class_name KeepItemsDialog
## **Fleeing the region: choose what you carry out** (ROGUELITE_REWORK 17.7,
## ruled 2026-09-26: fleeing alive keeps 3 items). Lists the run's gear and
## relics with a tick box each, allows at most `limit`, and hands the chosen ids
## back. Items carried *in* from the Lair are not on the list -- they go home
## with him on any alive ending, so they never cost a pick.
##
## PROCESS_MODE_ALWAYS over a paused world, like the pause menu, and it owns the
## pause it sets.

signal chosen(ids: Array)
signal cancelled

const WIDTH := 460.0

var limit: int = 3
var _body: VBoxContainer
var _boxes: Array = []     # [CheckBox, id]
var _confirm: Button
var _count: Label
var _paused_by_me: bool = false

func _ready() -> void:
	layer = 59
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.menu_theme()
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(WIDTH, 0)
	panel.add_theme_stylebox_override("panel", PauseMenu.panel_style())
	UiKit.add_crest(panel)
	center.add_child(panel)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	panel.add_child(_body)
	visible = false

func is_open() -> bool:
	return visible

## `items`: relic ids found this run. `carried`: ids he brought in (shown, not
## choosable -- they come home anyway).
func open(items: Array, carried: Array = []) -> void:
	for c in _body.get_children():
		c.queue_free()
	_boxes.clear()
	_body.add_child(PauseMenu.heading("Flee the region", 20))
	var intro := Label.new()
	intro.text = "The run ends here, and he lives. He can carry %d things out of the region; the rest stays behind for good." % limit
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(WIDTH - 44.0, 0)
	intro.add_theme_font_size_override("font_size", 12)
	_body.add_child(intro)
	if items.is_empty():
		var none := Label.new()
		none.text = "He found nothing worth keeping this run."
		none.modulate = Color(1, 1, 1, 0.6)
		none.add_theme_font_size_override("font_size", 12)
		_body.add_child(none)
	for id in items:
		var r: Dictionary = LootCatalog.relic(String(id))
		var cb := CheckBox.new()
		cb.text = "%s  (%s)" % [String(r.get("name", id)), String(r.get("tier", ""))]
		cb.tooltip_text = String(r.get("description", ""))
		cb.add_theme_font_size_override("font_size", 12)
		cb.toggled.connect(func(_on): _refresh())
		_body.add_child(cb)
		_boxes.append([cb, String(id)])
	# Pre-tick the first `limit` so the common case is one click.
	for i in range(mini(limit, _boxes.size())):
		_boxes[i][0].button_pressed = true
	if not carried.is_empty():
		var names: Array = carried.map(func(id): return String(LootCatalog.relic(String(id)).get("name", id)))
		var cl := Label.new()
		cl.text = "Coming home with him anyway (carried in from the Lair): %s" % ", ".join(names)
		cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cl.custom_minimum_size = Vector2(WIDTH - 44.0, 0)
		cl.add_theme_font_size_override("font_size", 11)
		cl.modulate = Color(0.8, 0.9, 1.0)
		_body.add_child(cl)
	_count = Label.new()
	_count.add_theme_font_size_override("font_size", 11)
	_body.add_child(_count)
	_confirm = Button.new()
	_confirm.custom_minimum_size = Vector2(0, 32)
	_confirm.pressed.connect(_on_confirm)
	_body.add_child(_confirm)
	var stay := Button.new()
	stay.text = "Stay in the region"
	stay.custom_minimum_size = Vector2(0, 32)
	stay.pressed.connect(func():
		_close()
		cancelled.emit())
	_body.add_child(stay)
	_refresh()
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_me = true
	visible = true
	_confirm.grab_focus.call_deferred()

func selected() -> Array:
	var out: Array = []
	for pair in _boxes:
		if pair[0].button_pressed:
			out.append(pair[1])
	return out

func _refresh() -> void:
	var n: int = selected().size()
	# At the limit, the unticked boxes lock -- the rule is visible, not an error.
	for pair in _boxes:
		pair[0].disabled = n >= limit and not pair[0].button_pressed
	if _count:
		_count.text = "Taking %d of %d." % [n, limit]
	if _confirm:
		_confirm.text = "Flee with these" if n > 0 else "Flee with nothing"

func _on_confirm() -> void:
	var ids: Array = selected()
	_close()
	chosen.emit(ids)

func _close() -> void:
	visible = false
	if _paused_by_me:
		get_tree().paused = false
		_paused_by_me = false

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("cancel"):
		_close()
		cancelled.emit()
		get_viewport().set_input_as_handled()
