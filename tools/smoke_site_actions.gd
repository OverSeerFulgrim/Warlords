extends Node
## Presses the site action buttons **as buttons**, in the real panel, built by
## the real inspect path.
##
##   godot --headless --path . res://tools/smoke_site_actions.tscn
##
## A scene, not `-s` (the autoload gotcha).
##
## ## Why this exists separately from verify_loot_tables
##
## That harness calls `WorldSite.begin_action()` directly, which is the right
## thing for asserting rules and the wrong thing for catching the bug that
## produced it. The 2026-08-30 playtest reported "clicking Collect does
## nothing", and the whole chain between the click and `begin_action` --
## `InspectorActions` building a `Button`, its `pressed` signal, the
## `site_action_requested` hop through `Main` -- was untested, along with the
## layering that has eaten HUD clicks twice before
## (`docs/history/2026-08-hud-layering-and-playtest-bugs.md`).
##
## So this drives `Main._inspect_at()` -- the actual click handler -- finds the
## actual `Button` by its text, checks nothing is covering it, and emits its
## `pressed` signal. That is everything a real click does except the OS event,
## and the OS event is the one part nothing headless can supply: godot-mcp's
## simulated input never reaches the game (CLAUDE.md gotcha), so a human mouse
## is still the last word.

var _passed: int = 0
var _failed: int = 0
var _main = null

func _ready() -> void:
	get_tree().root.size = Vector2i(1400, 760)
	await get_tree().process_frame
	_main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(_main)
	for i in range(10):
		await get_tree().process_frame

	print("\n=== Site actions, pressed as buttons ===\n")
	await _collect_button()
	await _raise_through_the_sheet()

	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

# ---------------- Collect -----------------------------------------------------

func _collect_button() -> void:
	print("-- 'Collect what you left' --")
	var site: WorldSite = _site("cemetery")
	var v: Necromancer = _main.villain
	v.carried.clear()
	v.add_carried("bones", v.carry_capacity())
	await _stand_beside(site)
	site._resolve_choice(v, _choice(site, "steal"))
	_ok("the grave left a remainder", site.has_remainder())

	# The real click path: this is what _unhandled_input calls.
	_main._inspect_at(site.position)
	await get_tree().process_frame
	_ok("clicking the site opens the inspector on it", _main.inspector.is_open()
		and _main.inspector.current_source() == site)

	var full_btn: Button = _button("Collect what you left")
	_ok("the collect row is on the panel", full_btn != null)
	if full_btn == null:
		return
	_ok("...greyed, because his hands are full", full_btn.disabled)
	_ok("...with the reason printed under it, not just in a tooltip",
		_panel_says("hands are full"))

	# Empty his hands and re-open: the same row must come back live.
	v.carried.clear()
	_main.inspector.refresh()
	await get_tree().process_frame
	var btn: Button = _button("Collect what you left")
	_ok("with room, the row comes back", btn != null and not btn.disabled)
	if btn == null:
		return
	_ok("...and nothing is covering it", _unobstructed(btn))
	_ok("...and it is big enough to hit", btn.get_global_rect().size.x > 40.0
		and btn.get_global_rect().size.y > 10.0)

	var before: int = v.carried_total()
	var remainder: Dictionary = site.remainder.duplicate()
	# The button's own signal, which is what a mouse release fires.
	btn.pressed.emit()
	await get_tree().process_frame
	_ok("pressing it moves loot into his hands", v.carried_total() > before,
		"%d -> %d" % [before, v.carried_total()])
	_ok("...taking it off the site", site.remainder != remainder)
	_ok("...and the panel redrew in the same frame -- the row is gone",
		_button("Collect what you left") == null or site.has_remainder())

# ---------------- Raise -------------------------------------------------------

func _raise_through_the_sheet() -> void:
	print("\n-- 'Raise the corpse', through the choice sheet --")
	var site: WorldSite = _site("derelict_graveyard")
	var v: Necromancer = _main.villain
	v.carried.clear()
	await _stand_beside(site)

	_main._inspect_at(site.position)
	await get_tree().process_frame
	var open_btn: Button = _button("Open a grave", true)
	_ok("the site offers its sheet", open_btn != null)
	if open_btn == null:
		return
	_ok("...and nothing is covering it", _unobstructed(open_btn))
	open_btn.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame

	_ok("the choice sheet opened", _main.event_panel_ui.is_open())
	var raise_btn: Button = _button_in(_main.event_panel_ui.event_panel, "Raise the corpse")
	_ok("...offering 'Raise the corpse'", raise_btn != null)
	_ok("...and 'Leave it', because walking away is a real answer",
		_button_in(_main.event_panel_ui.event_panel, "Leave it") != null)
	if raise_btn == null:
		return
	_ok("...unobstructed", _unobstructed(raise_btn))

	var bodies: int = _main.world_sites.raised.size()
	var ledger: int = v.raised_dead.size()
	raise_btn.pressed.emit()
	await get_tree().process_frame
	_ok("the sheet closes on the answer", not _main.event_panel_ui.is_open())
	_ok("...and he starts channelling", site.is_channelling())

	# Run the channel out. A delta accumulator, so this is just time passing.
	for i in range(60):
		site._process(0.5)
		if not site.is_channelling():
			break
		await get_tree().process_frame
	_ok("the channel completes", not site.is_channelling())
	_ok("A BODY IS STANDING THERE", _main.world_sites.raised.size() == bodies + 1,
		"%d -> %d" % [bodies, _main.world_sites.raised.size()])
	_ok("...and the ledger entry is written", v.raised_dead.size() == ledger + 1)
	if _main.world_sites.raised.size() > bodies:
		var body = _main.world_sites.raised[_main.world_sites.raised.size() - 1]
		# Step him off it first: he outranks scenery in the pick order and he is
		# standing right next to what he just raised.
		v.place_at(body.position + Vector2(0.0, -160.0))
		for i in range(6):
			await get_tree().process_frame
		_ok("...it is clickable in the world", _main._inspect_at(body.position)
			and _main.inspector.current_source() == body,
			str(_main.inspector.current_source()))
		_ok("...and inspects as what it is",
			String(body.get_inspect_data()["title"]) == "A Raised Corpse")

# ---------------- Helpers -----------------------------------------------------

## Puts him **beside** the site rather than on it, and waits for the fog.
##
## Two things this had to learn the hard way. Standing exactly on a site means
## clicking it inspects HIM -- characters outrank scenery in the pick order, by
## design -- so the test has to stand where a player would. And `_inspect_at`
## refuses anything under fog, also by design, so the reveal has to catch up
## with him first.
##
## The offset is derived from the two radii rather than hardcoded, which makes
## this an assertion as well as a setup step: if a site's reach were ever
## smaller than the villain's own click radius, there would be NO point from
## which the site is both in reach and clickable, and it would be unusable.
func _stand_beside(site: WorldSite) -> void:
	var mine: float = _main.necromancer_token.hit_radius()
	var reach: float = site.interact_radius()
	_ok("%s can be clicked from somewhere inside its own reach" % site.site_id,
		reach > mine, "reach %.1f vs his own click radius %.1f" % [reach, mine])
	_main.villain.place_at(site.position + Vector2((mine + reach) * 0.5, 0.0))
	for i in range(6):
		await get_tree().process_frame

func _site(id: String) -> WorldSite:
	for s in _main.world_sites.sites:
		if s.site_id == id:
			return s
	return null

func _choice(site: WorldSite, id: String) -> Dictionary:
	for c in LootCatalog.choice_sheet(site.choices_id).get("choices", []):
		if String(c.get("id", "")) == id:
			return c
	return {}

func _button(text: String, prefix: bool = false) -> Button:
	return _button_in(_main.inspector, text, prefix)

func _button_in(root: Node, text: String, prefix: bool = false) -> Button:
	if root == null:
		return null
	for child in root.get_children():
		if child is Button:
			var b: Button = child
			if b.text == text or (prefix and b.text.begins_with(text)):
				return b
		var found: Button = _button_in(child, text, prefix)
		if found:
			return found
	return null

## Does any *later* sibling Control overlap this button?
##
## Sibling order is z-order **and** input order, last on top, and that has eaten
## HUD clicks twice: a recruit offer's buttons once landed under the command bar
## and became genuinely unanswerable. Cheap to check, and this is the assertion
## that would have caught it.
func _unobstructed(btn: Button) -> bool:
	if not btn.is_visible_in_tree():
		return false
	var rect: Rect2 = btn.get_global_rect()
	var panel: Control = btn
	while panel.get_parent() is Control:
		panel = panel.get_parent()
	var siblings: Array = panel.get_parent().get_children() if panel.get_parent() else []
	var after: bool = false
	for node in siblings:
		if node == panel:
			after = true
			continue
		if not after or not (node is Control):
			continue
		var other: Control = node
		if other.mouse_filter == Control.MOUSE_FILTER_IGNORE or not other.is_visible_in_tree():
			continue
		if other.get_global_rect().intersects(rect):
			printerr("    covered by later sibling %s %s" % [other.name, other.get_global_rect()])
			return false
	return true

## Is `text` anywhere in the inspection panel's labels? The reason for a greyed
## action has to be *readable*, which a tooltip is not.
func _panel_says(text: String) -> bool:
	return _label_contains(_main.inspector, text)

func _label_contains(root: Node, text: String) -> bool:
	if root == null:
		return false
	for child in root.get_children():
		if child is Label and String(child.text).findn(text) >= 0:
			return true
		if _label_contains(child, text):
			return true
	return false

func _ok(what: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("  PASS  %s" % what)
	else:
		_failed += 1
		printerr("  FAIL  %s   (%s)" % [what, detail])
