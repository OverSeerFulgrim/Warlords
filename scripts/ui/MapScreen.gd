class_name MapScreen
extends Control
## **The big map (M)** (the HUD redo, 2026-09-26: "it would be easier to see and
## it could have points of interest labeled when discovered").
##
## A full-size `Minimap` -- the same terrain, fog and clicks (left: look there;
## right: walk there) -- with a layer of names drawn over it, and a list of the
## places he knows beside it. **Only what he has seen is drawn**, and a place is
## named the moment he first sees it (`WorldSite.discovered`, the same flag the
## Raven reads). The guild and his lair are known from the start.
##
## Does not pause the world: it is a place to look, and right-clicking a place
## to walk there is the point.

signal place_chosen(world_pos: Vector2)
signal walk_requested(world_pos: Vector2)
signal closed

var world: WorldMap = null
var fog: FogOfWar = null
var villain: Necromancer = null
var camera: GameCamera = null
var world_sites: WorldSites = null
var guild = null
var village = null
var raven = null
var worker_system: WorkerSystem = null

var map: Minimap
var _names: Control
var _list: VBoxContainer
var _show_names: CheckBox
var _show_raven: CheckBox
var _show_dead: CheckBox
var _built: bool = false

func build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.05, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(k, 20)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	margin.add_child(row)

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", HudStyle.box(Color("0b0a0e"), Color("6c5a86"), 10, 4))
	row.add_child(frame)
	map = Minimap.new()
	frame.add_child(map)
	map.setup(world, fog, villain, camera)
	map.units_source = func():
		return worker_system.all_units() if worker_system and _show_dead and _show_dead.button_pressed else []
	map.raven_markers_source = func():
		return raven.minimap_points() if raven and _show_raven and _show_raven.button_pressed else []
	map.landmarks_source = func():
		return [guild.position] if guild else []
	map.camera_requested.connect(func(p: Vector2):
		place_chosen.emit(p)
		close())
	map.move_requested.connect(func(p: Vector2): walk_requested.emit(p))
	_names = Control.new()
	_names.set_anchors_preset(Control.PRESET_FULL_RECT)
	_names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_names.draw.connect(_draw_names)
	map.add_child(_names)

	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 12)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(side)
	var head := HBoxContainer.new()
	side.add_child(head)
	var title := HudStyle.label("The Region", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "Close  %s" % Controls.label_for("map")
	close_btn.custom_minimum_size = Vector2(96, 40)
	HudStyle.style_button(close_btn, false, 14)
	close_btn.pressed.connect(close)
	head.add_child(close_btn)
	var note := HudStyle.label("Only what he has seen is drawn. Places are named the moment he first sees them. Left-click to look there; right-click to walk him there.", 13, HudStyle.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(300, 0)
	side.add_child(note)
	side.add_child(HudStyle.label("Known places", 15, Color("d9ccf2")))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	side.add_child(HudStyle.label("Show", 15, Color("d9ccf2")))
	_show_names = _check(side, "Place names", true)
	_show_raven = _check(side, "The Raven's marks", true)
	_show_dead = _check(side, "His dead", false)
	visible = false
	_built = true

func _check(parent: Control, text: String, on: bool) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.add_theme_font_size_override("font_size", 14)
	c.toggled.connect(func(_v):
		map.queue_redraw()
		_names.queue_redraw())
	parent.add_child(c)
	return c

func is_open() -> bool:
	return visible

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	if not _built:
		return
	# Sized by hand: a Control under a CanvasLayer has no parent rect to
	# anchor to until the first layout, and the map must cover the world.
	position = Vector2.ZERO
	size = get_viewport_rect().size
	visible = true
	# Square, as large as the window allows beside the list.
	var vp: Vector2 = get_viewport_rect().size
	var side: float = floorf(minf(vp.y - 56.0, vp.x - 420.0))
	map.custom_minimum_size = Vector2(side, side)
	map.queue_redraw()
	_names.queue_redraw()
	_fill_list()

func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()

func _process(_delta: float) -> void:
	if visible:
		_names.queue_redraw()

# ---------------- What he knows ----------------

## Every place he knows: `{pos, name, tag, color}`. The lair and the guild are
## always there; a site once he has seen it; the village once any of it is.
func places() -> Array:
	var out: Array = []
	if world:
		out.append({"pos": world.cell_centre_px(world.lair_origin + Vector2i(SettlementGrid.GRID_WIDTH / 2, SettlementGrid.GRID_HEIGHT / 2)),
			"name": "Your lair", "tag": "", "color": HudStyle.GOOD, "above": true})
	if guild:
		var tag: String = Necromancer.standing_name(villain.standing_with(Guild.FACTION)) if villain else ""
		out.append({"pos": guild.position, "name": guild.display_name, "tag": "standing: %s" % tag if tag != "" else "",
			"color": Color("f6d9bd")})
	if village and fog and village.buildings.size() > 0:
		var any_seen: bool = false
		var centre := Vector2.ZERO
		for b in village.buildings.values():
			centre += b.position
			if fog.state_at(b.position) != FogOfWar.State.UNEXPLORED:
				any_seen = true
		if any_seen:
			out.append({"pos": centre / float(village.buildings.size()), "name": village.display_name,
				"tag": "a village", "color": Color("f3e7d3")})
	if world_sites:
		for s in world_sites.sites:
			if not s.discovered or String(s.site_id).begins_with("house_"):
				continue
			out.append({"pos": s.position, "name": s.display_name, "tag": _site_tag(s), "color": _site_color(s)})
	return out

func _site_tag(s: WorldSite) -> String:
	var bits: Array = []
	if not s.lootable:
		return ""
	if s.is_guarded():
		bits.append("guarded")
	if s.has_unknown_blueprint():
		bits.append("plans")
	if not s.relic_remainder.is_empty():
		bits.append("%d item%s left" % [s.relic_remainder.size(), "" if s.relic_remainder.size() == 1 else "s"])
	if s.is_spent():
		bits.append("emptied")
	return " · ".join(bits)

func _site_color(s: WorldSite) -> Color:
	if not s.lootable:
		return Color("d7cce8")
	if s.is_spent():
		return Color("8d8399")
	if s.is_guarded():
		return Color("ffcfc4")
	return HudStyle.AMBER

func _fill_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	for p in places():
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 40)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = String(p["name"]) + ("   —  " + String(p["tag"]) if String(p["tag"]) != "" else "")
		HudStyle.style_button(b, false, 13)
		var at: Vector2 = p["pos"]
		b.pressed.connect(func():
			place_chosen.emit(at)
			close())
		_list.add_child(b)

func _draw_names() -> void:
	if not visible or map == null or world == null:
		return
	var font: Font = ThemeDB.fallback_font
	var names: bool = _show_names.button_pressed
	for p in places():
		var at: Vector2 = map._to_map(p["pos"])
		var col: Color = p["color"]
		_names.draw_rect(Rect2(at - Vector2(4, 4), Vector2(8, 8)), col, false, 2.0)
		if not names:
			continue
		var text: String = String(p["name"])
		if String(p["tag"]) != "":
			text += " · " + String(p["tag"])
		var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var dy: float = -28.0 if bool(p.get("above", false)) else 8.0
		var box := Rect2(at + Vector2(-w * 0.5 - 5.0, dy), Vector2(w + 10.0, 18.0))
		_names.draw_rect(box, Color(0.09, 0.07, 0.11, 0.85))
		_names.draw_string(font, box.position + Vector2(5, 14), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
	if villain:
		var me: Vector2 = map._to_map(villain.position)
		_names.draw_circle(me, 6.0, Color("e7c55a"))
		_names.draw_string(font, me + Vector2(9, 5), "You", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("f5e3a1"))
