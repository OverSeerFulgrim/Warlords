extends CanvasLayer
class_name ItemsDialog
## **His items: what is on the ground, in the bag, and worn** (designer rulings
## 2026-09-26, first playtest):
##
## - items land on the ground when a site pays out, and he **chooses** what to
##   pick up and what to leave;
## - **resources take no space** -- the bag's slots are for items;
## - **gear can be worn anywhere** and works the moment it is worn, taking no
##   bag slot. At the Throne he can also wear gear from the hoard, or put worn
##   gear back in it.
##
## Opened by a site (`items_on_ground`), by his panel's "Items" button, or the
## **I** key. Reads and changes nothing itself beyond calling the villain's and
## the site's own methods -- the rules live there. PROCESS_MODE_ALWAYS over a
## paused world; it owns the pause it sets.

signal closed

const WIDTH := 520.0

var villain: Necromancer = null
var sortie_system: SortieSystem = null
var site: WorldSite = null            # null: no ground section
var _body: VBoxContainer
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
	dim.color = Color(0, 0, 0, 0.5)
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
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(WIDTH - 20.0, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	visible = false

func is_open() -> bool:
	return visible

## `at`: the site whose ground to show, or null for just the bag and the worn.
func open(at: WorldSite = null) -> void:
	site = at
	_render()
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_me = true
	visible = true

func _at_throne() -> bool:
	return sortie_system != null and sortie_system.at_throne()

func _render() -> void:
	for c in _body.get_children():
		c.queue_free()
	if villain == null:
		return
	# The scroll box sizes to its content, capped to the window.
	UiKit.fit_scroll(_body.get_parent() as ScrollContainer, _body, 560.0)
	_body.add_child(PauseMenu.heading("Items", 20))
	var line := _note("Bag: %d / %d slots. Resources take no room: %s." % [villain.carried_total(),
		villain.carry_capacity(), LootCatalog.describe(villain.carried) if not villain.carried.is_empty() else "none"])
	line.modulate = Color(1, 1, 1, 0.8)

	# ---- On the ground ----
	if site != null and site.in_reach(villain) and not site.relic_remainder.is_empty():
		_body.add_child(PauseMenu.heading("On the ground — %s" % site.display_name, 15))
		for id in site.relic_remainder.duplicate():
			var row := _item_row(String(id))
			var take := _button(row, "Take", func():
				site.pick_up_item(villain, String(id))
				_render())
			take.disabled = villain.carry_space() <= 0
			if take.disabled:
				take.tooltip_text = "The bag is full. Leave something here, or wear it."
			if Necromancer.is_gear(String(id)):
				_button(row, "Wear", func():
					site.wear_item(villain, String(id))
					_render())

	# ---- Worn ----
	_body.add_child(PauseMenu.heading("Worn", 15))
	var any_worn: bool = false
	for slot in Necromancer.GEAR_SLOTS:
		if not villain.equipped.has(slot):
			continue
		any_worn = true
		var id: String = String(villain.equipped[slot])
		var row := _item_row(id, Necromancer.GEAR_SLOT_NAMES[slot])
		if _at_throne():
			_button(row, "Put in the hoard", func():
				villain.unequip(slot, true)
				_render())
		else:
			var off := _button(row, "Take off", func():
				villain.unequip(slot)
				_render())
			off.disabled = villain.carry_space() <= 0
	if not any_worn:
		_note("Nothing. Gear works the moment he puts it on, anywhere.")

	# ---- The bag ----
	_body.add_child(PauseMenu.heading("In the bag (%d / %d)" % [villain.carried_total(), villain.carry_capacity()], 15))
	if villain.relics_carried.is_empty():
		_note("Empty.")
	for id in villain.relics_carried.duplicate():
		var row := _item_row(String(id))
		if Necromancer.is_gear(String(id)):
			_button(row, "Wear", func():
				villain.equip(String(id))
				_render())
		if site != null and site.in_reach(villain):
			_button(row, "Leave here", func():
				site.leave_item(villain, String(id))
				_render())
		elif sortie_system != null:
			_button(row, "Drop", func():
				sortie_system.drop_relic(String(id))
				_render())

	# ---- The hoard (only at the Throne) ----
	if _at_throne() and not villain.relics_banked.is_empty():
		_body.add_child(PauseMenu.heading("At the Throne", 15))
		for id in villain.relics_banked.duplicate():
			var row := _item_row(String(id))
			if Necromancer.is_gear(String(id)):
				_button(row, "Wear", func():
					villain.equip(String(id), true)
					_render())

	var done := Button.new()
	done.text = "Done"
	done.custom_minimum_size = Vector2(0, 32)
	done.pressed.connect(close)
	_body.add_child(done)
	done.grab_focus.call_deferred()

## One item: its name, what it does, and a row for its buttons.
func _item_row(id: String, prefix: String = "") -> HBoxContainer:
	var r: Dictionary = LootCatalog.relic(id)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	_body.add_child(box)
	var name_l := Label.new()
	name_l.text = ("%s: " % prefix if prefix != "" else "") + String(r.get("name", id))
	name_l.add_theme_font_size_override("font_size", 13)
	name_l.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	name_l.tooltip_text = String(r.get("description", ""))
	name_l.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(name_l)
	var what := Label.new()
	what.text = effect_text(id)
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	what.custom_minimum_size = Vector2(WIDTH - 60.0, 0)
	what.add_theme_font_size_override("font_size", 11)
	what.modulate = Color(1, 1, 1, 0.7)
	box.add_child(what)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	return row

func _button(row: HBoxContainer, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(96, 26)
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(cb)
	row.add_child(b)
	return b

func _note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(WIDTH - 44.0, 0)
	l.add_theme_font_size_override("font_size", 11)
	_body.add_child(l)
	return l

## "Gear (cloak) — +10% speed off the road. Works while worn." -- one line a
## player can decide on, from the data alone.
static func effect_text(id: String) -> String:
	var r: Dictionary = LootCatalog.relic(id)
	var parts: Array = []
	for e in r.get("effects", []):
		var kind: String = String(e.get("kind", ""))
		var t: String = ""
		match kind:
			"move_speed_mult":
				t = "+%d%% walking speed%s" % [int(round((float(e.get("value", 1.0)) - 1.0) * 100.0)),
					" off the road" if bool(e.get("off_road", false)) else ""]
			"carry_delta":
				t = "+%d bag slots" % int(e.get("value", 0))
			"heal_at_dawn":
				t = "heals %d hp at dawn" % int(e.get("value", 0))
			"fog_reveal_delta":
				t = "sees %d cells further" % int(e.get("value", 0))
			"channel_mult":
				t = "%s work %d%% faster" % [", ".join(e.get("tags", ["all"])),
					int(round((1.0 - float(e.get("value", 1.0))) * 100.0))]
			"attribute":
				t = "+%d %s" % [int(e.get("delta", 0)), String(e.get("attribute", "")).capitalize()]
			_:
				t = kind.replace("_", " ")
		if bool(e.get("dormant", false)):
			t += " (not in the game yet)"
		parts.append(t)
	var does: String = ", ".join(parts) if not parts.is_empty() else "Worth something, and nothing more"
	if Necromancer.is_gear(id):
		return "Gear (%s) — %s. Works while worn." % [Necromancer.GEAR_SLOT_NAMES.get(Necromancer.gear_slot(id), "?").to_lower(), does]
	if parts.is_empty():
		return does + "."
	return "%s. Works once it is home at the Throne." % does

func close() -> void:
	visible = false
	site = null
	if _paused_by_me:
		get_tree().paused = false
		_paused_by_me = false
	closed.emit()

func _input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("cancel") or event.is_action_pressed("items")):
		close()
		get_viewport().set_input_as_handled()
