class_name EventPanelUI
extends Node

## The floating event / recruit-offer panel: the decision the player has to
## answer before the world moves on.
##
## Extracted from Main.gd (CLEANUP_PLAN.md Pass 4). It owns the panel, the
## event currently on screen, and the two-frame placement dance. It does not
## know where the screen's usable band is -- that depends on the top strip's
## laid-out height and the command bar, both of which are Main.gd's layout
## knowledge, so Main.gd hands in a provider rather than this module reaching
## into HudTopBar.
##
## The history log stays Main.gd's, so the three things worth writing down go
## out as semantic signals rather than a generic log pipe.

## An event has opened. Main.gd writes the "EVENT: ..." line.
signal event_opened(event: Dictionary)
## A choice was answered. Main.gd writes the "Chose: ..." line.
signal choice_resolved(label: String)
## A Barracks slot opened while an offer was on screen and the offer changed
## because of it. Main.gd logs and raises the alert.
signal offer_room_found(title: String)

var event_panel: PanelContainer
var current_event: Dictionary = {}

# ---------------- References handed in by Main.gd ----------------
var _event_system: EventSystem
## Returns Vector2(band_top, band_bottom) in screen px -- the strip of window
## between the top resource bar and the bottom command bar.
var _visible_band: Callable

## Deliberately TOP_LEFT-anchored and positioned by hand in _show_panel().
func build(hud_root: Control, panel_style: StyleBoxFlat, event_system: EventSystem,
		visible_band: Callable) -> void:
	_event_system = event_system
	_visible_band = visible_band

	event_panel = PanelContainer.new()
	event_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	event_panel.custom_minimum_size = Vector2(280, 0)
	event_panel.add_theme_stylebox_override("panel", panel_style)
	event_panel.visible = false
	hud_root.add_child(event_panel)

	EventBus.event_triggered.connect(_on_event_triggered)

func _on_event_triggered(event: Dictionary) -> void:
	current_event = event
	event_opened.emit(event)
	_render(event)
	_show_panel()

## Split out from _on_event_triggered so an *open* offer can be re-rendered in
## place when the world changes underneath it -- see refresh_open_offer().
func _render(event: Dictionary) -> void:
	for child in event_panel.get_children():
		event_panel.remove_child(child)
		child.queue_free()
	var box := VBoxContainer.new()
	event_panel.add_child(box)

	# Title and description used to be log-only, which was survivable when
	# events were flat flavor text. A recruit offer's stat block is the whole
	# decision, so it has to be on the panel you're deciding from.
	var title := Label.new()
	title.text = event.get("title", "?")
	title.add_theme_font_size_override("font_size", 15)
	box.add_child(title)

	var desc := Label.new()
	desc.text = event.get("description", "")
	desc.add_theme_font_size_override("font_size", 11)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(260, 0)
	box.add_child(desc)
	box.add_child(HSeparator.new())

	var choices: Array = event.get("choices", [])
	for i in range(choices.size()):
		var choice: Dictionary = choices[i]
		var idx := i
		var b := Button.new()
		b.text = choice.get("label", "...")
		b.pressed.connect(func(): _resolve_choice(idx))
		box.add_child(b)

func _show_panel() -> void:
	event_panel.visible = true
	# Above every other HUD element, including the bottom bar. Belt and braces
	# with the build order in _build_ui -- a decision the player has to answer
	# must never be the thing that ends up underneath something else.
	event_panel.move_to_front()
	reposition()

## Centres the panel in the **visible map band** -- between the top resource
## strip and the bottom command bar -- rather than in the raw window, and
## clamps it so a tall offer never spills over the command bar. Same band logic
## the camera framing uses.
##
## Runs over two frames because a Control's size isn't final until layout has
## settled; the first pass uses the minimum size so it is never wildly wrong in
## the meantime.
func reposition() -> void:
	_place_using(event_panel.get_combined_minimum_size())
	await get_tree().process_frame
	if event_panel.visible:
		_place_using(event_panel.size)

func _place_using(panel_size: Vector2) -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	var band: Vector2 = _visible_band.call()
	var band_top: float = band.x
	var band_bottom: float = band.y
	var y: float = band_top + maxf(0.0, (band_bottom - band_top - panel_size.y) * 0.5)
	event_panel.position = Vector2(
		maxf(8.0, (view.x - panel_size.x) * 0.5),
		clampf(y, band_top, maxf(band_top, band_bottom - panel_size.y))
	)

## A recruit offer is a live decision, not a snapshot. It used to freeze its
## choices at the moment it fired, so a player who funded a house to make room
## while the offer was on screen was still stuck with the two turn-away
## variants -- the freed slot did nothing until the offer expired. Polled
## rather than wired to a signal because occupancy moves for several unrelated
## reasons (housing, desertion, another recruit, demolishing the Barracks) and
## EventSystem.refresh_recruit_offer() is a no-op unless the answer actually
## changed.
func refresh_open_offer() -> void:
	if not event_panel.visible or current_event.is_empty():
		return
	if not _event_system.refresh_recruit_offer(current_event):
		return
	_render(current_event)
	reposition()
	if current_event.get("has_room", false):
		offer_room_found.emit(current_event.get("title", "the recruit"))

func _resolve_choice(idx: int) -> void:
	_event_system.resolve_event(current_event, idx)
	choice_resolved.emit(current_event.get("choices", [])[idx].get("label", "?"))
	event_panel.visible = false
	current_event = {}
