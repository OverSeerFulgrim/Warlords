class_name DeadRoster
extends PanelContainer
## **His dead, at a glance** (the HUD redo, 2026-09-26: "is there anything to
## show your undead?"). One row per risen unit -- name, a health bar, hp -- the
## escort first, the wounded coloured. Click a row to select that unit (Main
## opens its panel and looks at it). Hidden until his first dead rise.
##
## Polled, not signalled: health changes in a dozen places and a quarter-second
## tick costs nothing for a list this size. Shows the first MAX_ROWS and says
## how many more there are.

signal unit_pressed(unit)

const MAX_ROWS := 6
const ROW_WIDTH := 300.0

var worker_system: WorkerSystem = null
var villain: Necromancer = null

var _header: Label
var _rows_box: VBoxContainer
var _more: Label
var _rows: Array = []          # [{button, name, bar, hp, unit}]
var _tick: float = 0.0

func _init() -> void:
	add_theme_stylebox_override("panel", HudStyle.box())
	custom_minimum_size = Vector2(ROW_WIDTH, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	_header = HudStyle.label("His dead", 13, Color("d9ccf2"))
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_header)
	head.add_child(HudStyle.label("click to select", 11, HudStyle.MUTED))
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 4)
	box.add_child(_rows_box)
	_more = HudStyle.label("", 11, HudStyle.MUTED)
	_more.visible = false
	box.add_child(_more)
	visible = false

func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.25
	refresh()

## The dead in the order the player cares about: those walking with him first.
func units() -> Array:
	if worker_system == null:
		return []
	var out: Array = []
	var rest: Array = []
	for w in worker_system.workers:
		if not w.is_alive():
			continue
		if villain and villain.escort.has(w):
			out.append(w)
		else:
			rest.append(w)
	out.append_array(rest)
	return out

func refresh() -> void:
	var list: Array = units()
	visible = not list.is_empty()
	if not visible:
		return
	_header.text = "His dead · %d" % list.size()
	var shown: Array = list.slice(0, MAX_ROWS)
	while _rows.size() < shown.size():
		_rows.append(_make_row())
	for i in range(_rows.size()):
		var r: Dictionary = _rows[i]
		var b: Button = r["button"]
		if i >= shown.size():
			b.visible = false
			continue
		var u = shown[i]
		r["unit"] = u
		b.visible = true
		var frac: float = u.hp_fraction()
		(r["name"] as Label).text = String(u.combat_name())
		(r["hp"] as Label).text = "%d/%d" % [u.hp, u.max_hp()]
		HudStyle.set_bar(r["bar"], frac, HudStyle.hp_color(frac))
		var escorting: bool = villain != null and villain.escort.has(u)
		var border: Color = HudStyle.DANGER if frac < 0.4 else (HudStyle.BORDER_ACCENT if escorting else HudStyle.BORDER)
		var s := HudStyle.box(Color("2a1a20") if frac < 0.4 else HudStyle.BG_RAISED, border, 6, 6)
		for k in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(k, s)
		b.tooltip_text = "%s — %s" % [u.combat_name(), "walking with him" if escorting else "at work"]
	_more.visible = list.size() > MAX_ROWS
	_more.text = "+ %d more" % (list.size() - MAX_ROWS)

func _make_row() -> Dictionary:
	var b := Button.new()
	b.custom_minimum_size = Vector2(ROW_WIDTH - 20.0, 34)
	_rows_box.add_child(b)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_right = -8
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var name_l := HudStyle.label("", 13)
	name_l.custom_minimum_size = Vector2(150, 0)
	name_l.clip_text = true
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_l)
	var bar := HudStyle.bar(64.0, 6.0)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)
	var hp := HudStyle.label("", 12, HudStyle.MUTED)
	hp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hp)
	var r := {"button": b, "name": name_l, "bar": bar, "hp": hp, "unit": null}
	b.pressed.connect(func():
		if r["unit"] != null:
			unit_pressed.emit(r["unit"]))
	return r
