extends PanelContainer
class_name InspectionPanel
## The one panel that shows you what you just clicked. Replaces the three
## bespoke panels that grew one at a time (Keep menu, Barracks roster,
## Necromancer info) -- each of which had its own toggle function, its own
## populate function, and its own idea of what a header looks like.
##
## ## The Inspectable contract
##
## Anything clickable implements **`get_inspect_data() -> Dictionary`**. That's
## the whole interface. GDScript has no `interface` keyword, so this is
## duck-typed: `inspect()` checks `has_method()` and refuses politely rather
## than crashing on something that isn't inspectable.
##
## A registry was the other option and was rejected: it would need every
## clickable to register and deregister (resource nodes are created and freed
## at runtime -- deer especially), and the registry itself would end up holding
## the per-type knowledge that the whole point is to keep distributed. Asking
## the object is cheaper and can't go stale.
##
## The returned Dictionary:
##
## ```
## {
##   "title":       String,   # "Pine Tree", "Thokk", "The Necromancer"
##   "subtitle":    String,   # optional: "Gray Dwarf — Economy", "Recruit intake"
##   "sprite":      String,   # optional res:// path; omitted if "" or missing
##   "description": String,   # the one description line: flavor, or what it does
##   "details":     Array,    # rows, see below
## }
## ```
##
## Each `details` row is `{"label": String, "value": String}` plus optional
## `"muted": bool` (dims the row -- for placeholders and asides) and
## `"color": Color` (overrides the value colour -- morale warnings use this).
## A row with an empty `label` renders as a full-width line, which is what
## flavor asides and "nothing left here" notes want.
##
## **Per-object data stays in the per-object script.** There is deliberately no
## `match` on type in here or in Main.gd -- ResourceNode knows about regrowth,
## Building knows about tick rates, Follower knows about morale. Adding a new
## inspectable type means writing one method on it and nothing else.
##
## ## Actions are the exception
##
## Buildings that already had menus (the Keep's Recruit Worker / Surrender, the
## Barracks roster's Fund House buttons) keep them, but those buttons call
## *Main's* handlers -- so they can't live on Building without handing every
## building a reference to Main. Instead `inspect()` takes an optional
## `extra` Callable that Main supplies, and which is handed the content VBox to
## fill. Data comes from the object; actions come from whoever owns the
## handlers. That split is the reason this class has no idea what a Barracks is.

## Width of the panel body. Wide enough for a Barracks roster row (the longest
## content it has to hold) without pushing into the middle of the map.
const PANEL_WIDTH: float = 330.0
const PORTRAIT_SIZE: float = 44.0
const LABEL_COLUMN_WIDTH: float = 84.0

const TITLE_FONT_SIZE: int = 15
const BODY_FONT_SIZE: int = 11

## The object currently being shown. Kept (rather than the Dictionary it
## produced) so refresh() can re-ask it -- a Barracks' resident count and a
## worker's current activity both change while the panel is open.
var _source: Object = null
var _extra: Callable = Callable()

var _root: VBoxContainer

func _init() -> void:
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	visible = false
	add_theme_stylebox_override("panel", _panel_style())
	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 4)
	add_child(_root)

func _panel_style() -> StyleBoxFlat:
	# Matches Main._panel_style() so the inspector reads as part of the same HUD
	# as the top bar and the command bar rather than a floating stranger.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.88)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

# ---------------- Public API ----------------

## Shows `source`. Returns the Dictionary it rendered, so the caller can reuse
## the same title/subtitle for the bottom-bar info strip without asking the
## source twice. Returns {} if `source` isn't inspectable.
##
## `extra` is optional and is called with the content VBox after the details
## rows, to append action buttons -- see the class header for why those don't
## come from the source.
func inspect(source: Object, extra: Callable = Callable()) -> Dictionary:
	if source == null or not source.has_method("get_inspect_data"):
		push_warning("InspectionPanel: %s has no get_inspect_data()" % source)
		return {}
	_source = source
	_extra = extra
	var data: Dictionary = source.get_inspect_data()
	_render(data)
	visible = true
	return data

## Re-asks the current source and redraws. Cheap enough to poll -- Main runs it
## on a timer while the panel is open so a worker's Activity row and a Barracks'
## resident count stay live without a signal per field.
##
## Closes itself if the source has been freed underneath it: an inspected deer
## can be hunted, and a ResourceNode is a Node2D that really does get
## queue_free()d.
func refresh() -> void:
	if not visible:
		return
	if _source == null or not is_instance_valid(_source):
		close()
		return
	_render(_source.get_inspect_data())

func close() -> void:
	visible = false
	_source = null
	_extra = Callable()

func is_open() -> bool:
	return visible

## What's currently being shown, or null. Used by Main to answer "is this the
## thing that just deserted / just got demolished?".
func current_source() -> Object:
	return _source

# ---------------- Rendering ----------------

func _render(data: Dictionary) -> void:
	for child in _root.get_children():
		_root.remove_child(child)
		child.queue_free()

	_build_header(data)

	var description: String = data.get("description", "")
	if description != "":
		var desc := Label.new()
		desc.text = description
		desc.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(PANEL_WIDTH - 24.0, 0)
		desc.modulate = Color(1, 1, 1, 0.72)
		_root.add_child(desc)

	var details: Array = data.get("details", [])
	if not details.is_empty():
		_root.add_child(HSeparator.new())
		for row in details:
			_add_detail_row(row)

	# Action buttons, if the caller supplied any. They go below the details in
	# their own box so the extra builder can't accidentally reorder the header.
	if _extra.is_valid():
		_root.add_child(HSeparator.new())
		var actions := VBoxContainer.new()
		actions.add_theme_constant_override("separation", 4)
		_root.add_child(actions)
		_extra.call(actions)

	# One Close button for every inspectable, rather than each menu growing its
	# own. Esc and clicking empty ground also close -- see Main._unhandled_input.
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(close)
	_root.add_child(close_btn)

func _build_header(data: Dictionary) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	_root.add_child(header)

	var sprite_path: String = data.get("sprite", "")
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		# EXPAND_IGNORE_SIZE matters: the commissioned art is 1024-1254px square,
		# and without it a TextureRect asks for a container that size and blows
		# the panel apart. Same pattern as Main's top-bar icons.
		var portrait := TextureRect.new()
		portrait.texture = load(sprite_path)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
		portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		header.add_child(portrait)

	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(titles)

	var title := Label.new()
	title.text = data.get("title", "?")
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	titles.add_child(title)

	var subtitle_text: String = data.get("subtitle", "")
	if subtitle_text != "":
		var subtitle := Label.new()
		subtitle.text = subtitle_text
		subtitle.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
		subtitle.modulate = Color(0.85, 0.80, 0.95)
		titles.add_child(subtitle)

## A `label: value` line, or -- when `label` is empty -- one full-width line.
func _add_detail_row(row: Dictionary) -> void:
	var label_text: String = row.get("label", "")
	var value_text: String = row.get("value", "")
	var muted: bool = row.get("muted", false)

	if label_text == "":
		var solo := Label.new()
		solo.text = value_text
		solo.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
		solo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		solo.custom_minimum_size = Vector2(PANEL_WIDTH - 24.0, 0)
		solo.modulate = Color(1, 1, 1, 0.55 if muted else 0.85)
		if row.has("color"):
			solo.add_theme_color_override("font_color", row["color"])
		_root.add_child(solo)
		return

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)

	var key := Label.new()
	key.text = label_text
	key.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	key.custom_minimum_size = Vector2(LABEL_COLUMN_WIDTH, 0)
	key.modulate = Color(1, 1, 1, 0.5)
	line.add_child(key)

	var value := Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if row.has("color"):
		value.add_theme_color_override("font_color", row["color"])
	elif muted:
		value.modulate = Color(1, 1, 1, 0.5)
	line.add_child(value)

	_root.add_child(line)
