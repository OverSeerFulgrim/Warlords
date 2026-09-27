extends Node
## **The HUD redo: nothing on screen until he needs it** (2026-09-26; mockups
## in the "Warlords HUD redo" canvas).
##
##   godot --headless --path . res://tools/verify_hud.tscn
##
## Walks the "What appears when" chart: run one opens with the portrait, the
## clock, Map and History, the minimap, Raise Dead and Items -- and every other
## piece shows up the first time its mechanic does. Also: the old bottom bar is
## gone, the keys open what they say, and the map names only what he has seen.

var _passed: int = 0
var _failed: int = 0
var _main = null

func _ready() -> void:
	get_tree().root.size = Vector2i(1400, 800)
	await get_tree().process_frame
	_main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(_main)
	for i in range(8):
		await get_tree().process_frame
	print("\n=== The HUD: nothing until he needs it ===\n")
	await _run_one()
	await _things_appear()
	await _the_windows()
	await _the_map()
	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

func _tick() -> void:
	_main.action_bar.refresh()
	_main.dead_roster.refresh()
	_main.hud_top_bar.refresh_orientation()
	_main._refresh_hud_state()
	await get_tree().process_frame

func _run_one() -> void:
	print("-- Run one, minute one --")
	await _tick()
	var t: HudTopBar = _main.hud_top_bar
	var ab: ActionBar = _main.action_bar
	_check("the old bottom command bar is gone", _find_text(_main, "Research") == null and _find_text(_main, "Bounty") == null)
	_check("the portrait card is up", t.necro_badge.is_visible_in_tree() and t.villain_hp_label.text.contains("hp"))
	_check("the clock, Map and History are up", t.day_label.is_visible_in_tree() and t.map_btn.is_visible_in_tree()
		and t.history_btn.is_visible_in_tree())
	_check("Raise Dead and Items are on the bar", ab.raise_btn.visible and ab.items_btn.visible)
	_check("...and nothing else is", not ab.escort_btn.visible and not ab.rally_btn.visible and not ab.build_btn.visible)
	_check("no roster of the dead yet", not _main.dead_roster.visible)
	_check("no worn-gear strip, no pouch", not t.gear_strip.visible and not t.pouch_panel.visible)
	_check("no Treasury at the roadside", not t.treasury_panel.visible)
	_check("no guild chip, no Raven chip", not t.guild_chip.visible and not t.raven_chip.visible)
	_check("no threat readout while there is no threat", not t.threat_label.visible)
	_check("no Flee or Workforce at the roadside", not _main.home_buttons.visible)
	_check("the minimap sits in its corner", _main.minimap.is_visible_in_tree())

func _things_appear() -> void:
	print("-- Each piece appears when its mechanic does --")
	var v: Necromancer = _main.villain
	var t: HudTopBar = _main.hud_top_bar
	var ab: ActionBar = _main.action_bar
	GameState.bones = 20
	_main._recruit_worker()
	await _tick()
	_check("his first dead: the roster and the Escort button", _main.dead_roster.visible and ab.escort_btn.visible)
	_check("...but not the rally point yet", not ab.rally_btn.visible)
	_main._recruit_worker()
	_main._recruit_worker()
	await _tick()
	_check("three dead: the rally point", ab.rally_btn.visible)
	var w = _main.worker_system.workers[0]
	w.hp = 3
	await _tick()
	_check("the roster lists each of them with health", _main.dead_roster.units().size() == 3)
	v.add_carried("gold", 5)
	await _tick()
	_check("carrying resources: the 'not home yet' line", t.pouch_panel.visible and t.pouch_label.text.contains("gold"))
	v.relics_carried.append("wolfhide_cloak")
	await _tick()
	_check("owning gear: the worn-gear strip", t.gear_strip.visible)
	_check("his level shows on the card", t.level_label.text.begins_with("Lv"))
	_main.run_lifecycle.profile.learn_blueprint("workshop")
	await _tick()
	_check("a blueprint known: the Build button", ab.build_btn.visible)
	GameState.add_threat(2)
	t.refresh_stats()
	_check("threat above zero: the threat readout", t.threat_label.visible)
	v.place_at(_main._throne_world_centre() + Vector2(0, 40))
	await _tick()
	_check("by the Throne: the Treasury", t.treasury_panel.visible and t.treasury_label.text.contains("Wood"))
	_check("...and Flee the region", _main.home_buttons.visible and _main._flee_btn.visible)
	v.place_at(_main.guild.position + Vector2(0, 40))
	await _tick()
	_check("at the guild's door: the standing chip", t.guild_chip.visible and t.guild_chip.text.contains("Unknown"))

func _the_windows() -> void:
	print("-- History (L), Build (B), Items --")
	_main._log("a line for the record", "events")
	_check("a log line reaches the ticker", _main.log_ticker.get_child_count() > 0)
	_main.history_window.open()
	_check("History opens", _main.history_window.is_open())
	_check("...and holds the log", _main.history_log_list.get_child_count() > 0)
	_main.history_window.close()
	_main._toggle_build_tray()
	_check("B opens the Build tray", _main.build_tray.visible)
	_check("...listing what he knows", _find_text(_main.build_tray, "Workshop", true) != null)
	_main._toggle_build_tray()
	_check("...and closes it", not _main.build_tray.visible)
	for a in ["map", "history", "build", "escort", "rally", "items"]:
		_check("key action '%s' exists" % a, InputMap.has_action(a))

func _the_map() -> void:
	print("-- The big map (M) --")
	_main._toggle_map()
	await get_tree().process_frame
	var ms: MapScreen = _main.map_screen
	_check("M opens the map", ms.is_open())
	_check("...over the whole window", ms.size.x >= 1300.0)
	var names: Array = ms.places().map(func(p): return String(p["name"]))
	_check("his lair and the guild are known from the start", names.has("Your lair") and names.has(_main.guild.display_name))
	var hidden_site: WorldSite = null
	for s in _main.world_sites.sites:
		if s.lootable and not s.discovered:
			hidden_site = s
			break
	_check("a place he has not seen is not named", hidden_site != null and not names.has(hidden_site.display_name))
	if hidden_site:
		hidden_site.discovered = true
		_check("...and is, once he has", ms.places().map(func(p): return String(p["name"])).has(hidden_site.display_name))
		hidden_site.discovered = false
	_main._toggle_map()
	_check("M closes it", not ms.is_open())

func _find_text(n: Node, text: String, prefix: bool = false):
	for c in n.get_children():
		if (c is Button or c is Label) and c.is_visible_in_tree():
			var t: String = String(c.text)
			if t == text or (prefix and t.begins_with(text)):
				return c
		var f = _find_text(c, text, prefix)
		if f != null:
			return f
	return null

func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s   (%s)" % [what, detail])
