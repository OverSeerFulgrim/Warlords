extends CanvasLayer
class_name LairScreen
## **The Lair** (ROGUELITE_REWORK section 10; ruled 2026-09-26, 17.6): reached
## from a Lair button on the main menu. Where the loot kept from runs lives,
## where the player puts it on display, and where he chooses what to risk in the
## next run.
##
## - **The hall**: `MetaProfile.LAIR_SHELVES` display spots. Pick an item, then a
##   spot; pick a filled spot to take its item down. Decoration is the chronicle
##   made into a room -- it changes no number.
## - **The stash**: every kept item, where it came from, and a tick box to carry
##   it into the next run -- 1 slot, unlockable to a maximum of 3. A carried
##   item works from the first step and is **lost for good** if he dies.
##
## Reads and writes only the `MetaProfile` it is handed. PROCESS_MODE_ALWAYS:
## it opens over the paused title.

signal closed

const WIDTH := 720.0

var _profile: MetaProfile = null
var _class_id: String = "necromancer"
var _body: VBoxContainer
var _picked_uid: int = -1

func _ready() -> void:
	layer = 63
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.04, 0.94)
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
	center.add_child(panel)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	panel.add_child(_body)
	visible = false

func is_showing() -> bool:
	return visible

func show_lair(profile: MetaProfile, class_id: String) -> void:
	_profile = profile
	_class_id = class_id
	_picked_uid = -1
	visible = true
	_rebuild()

func _rebuild() -> void:
	for c in _body.get_children():
		c.queue_free()
	_body.add_child(PauseMenu.heading("The Lair", 24))
	var sub := Label.new()
	sub.text = "What he brought out of the world, and what he will risk going back in."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 12)
	sub.modulate = Color(1, 1, 1, 0.65)
	_body.add_child(sub)

	# ---- The hall ----
	_body.add_child(_section("The hall"))
	var hall := GridContainer.new()
	hall.columns = 4
	hall.add_theme_constant_override("h_separation", 8)
	hall.add_theme_constant_override("v_separation", 8)
	_body.add_child(hall)
	for i in range(MetaProfile.LAIR_SHELVES):
		hall.add_child(_shelf_button(i))
	var hint := Label.new()
	hint.text = ("Now pick a place in the hall for it." if _picked_uid >= 0
		else "Pick something below to put it on display; pick a place in the hall to take it down.")
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(0.85, 0.78, 1.0)
	_body.add_child(hint)

	# ---- The stash ----
	var slots: int = _profile.carry_slots(_class_id)
	var carrying: int = _profile.carried_entries().size()
	_body.add_child(_section("The stash  ·  carrying %d of %d into the next run" % [carrying, slots]))
	if _profile.stash.is_empty():
		var none := Label.new()
		none.text = "Nothing yet. Flee the region alive with something in hand, or take the Manor."
		none.add_theme_font_size_override("font_size", 12)
		none.modulate = Color(1, 1, 1, 0.55)
		_body.add_child(none)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(WIDTH - 44.0, mini(260, 36 * maxi(1, _profile.stash.size())))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for e in _profile.stash:
		list.add_child(_stash_row(e, carrying < slots))
	var warn := Label.new()
	warn.text = "A carried item works from his first step -- and if he dies, it is gone for good. Come home alive and it earns XP for the risk."
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn.custom_minimum_size = Vector2(WIDTH - 44.0, 0)
	warn.add_theme_font_size_override("font_size", 11)
	warn.modulate = Color(1.0, 0.8, 0.6)
	_body.add_child(warn)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 34)
	back.pressed.connect(func():
		visible = false
		closed.emit())
	_body.add_child(back)
	back.grab_focus.call_deferred()

func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.86, 0.72, 1.0))
	return l

func _name(e: Dictionary) -> String:
	return String(LootCatalog.relic(String(e.get("id", ""))).get("name", e.get("id", "?")))

func _shelf_button(i: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2((WIDTH - 44.0 - 24.0) / 4.0, 58)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_size_override("font_size", 11)
	var e: Dictionary = _profile.on_shelf(i)
	b.text = _name(e) if not e.is_empty() else "— empty —"
	if not e.is_empty():
		b.tooltip_text = "%s\nFrom run %d. Pick to take it down." % [
			String(LootCatalog.relic(String(e.get("id", ""))).get("description", "")), int(e.get("run", 0))]
		b.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	b.pressed.connect(func(): _on_shelf(i))
	return b

func _on_shelf(i: int) -> void:
	if _picked_uid >= 0:
		_profile.set_shelf(_picked_uid, i)
		_picked_uid = -1
	else:
		var e: Dictionary = _profile.on_shelf(i)
		if not e.is_empty():
			_profile.set_shelf(int(e["uid"]), -1)
	_rebuild()

func _stash_row(e: Dictionary, room: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var r: Dictionary = LootCatalog.relic(String(e.get("id", "")))
	var name := Button.new()
	name.text = "%s  (%s)" % [_name(e), String(r.get("tier", ""))]
	name.tooltip_text = String(r.get("description", ""))
	name.flat = int(e["uid"]) != _picked_uid
	name.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.add_theme_font_size_override("font_size", 12)
	name.pressed.connect(func():
		_picked_uid = -1 if _picked_uid == int(e["uid"]) else int(e["uid"])
		_rebuild())
	row.add_child(name)
	var where := Label.new()
	var shelf: int = int(e.get("shelf", -1))
	where.text = "run %d%s%s" % [int(e.get("run", 0)),
		"  · on display" if shelf >= 0 else "",
		"  · survived %d" % int(e.get("risked", 0)) if int(e.get("risked", 0)) > 0 else ""]
	where.add_theme_font_size_override("font_size", 11)
	where.modulate = Color(1, 1, 1, 0.6)
	row.add_child(where)
	var carry := CheckBox.new()
	carry.text = "Carry"
	carry.add_theme_font_size_override("font_size", 11)
	carry.button_pressed = bool(e.get("carry", false))
	carry.disabled = not carry.button_pressed and not room
	carry.tooltip_text = "Take it into the next run." if not carry.disabled else "Every carry slot is full."
	carry.toggled.connect(func(on: bool):
		_profile.set_carry(_class_id, int(e["uid"]), on)
		_rebuild())
	row.add_child(carry)
	return row

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("cancel"):
		visible = false
		closed.emit()
		get_viewport().set_input_as_handled()
