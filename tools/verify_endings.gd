extends Node
## What each ending keeps, the stash, and the Lair (ROGUELITE_REWORK section 10,
## rulings 17.6-17.7, built 2026-09-26).
##
##   godot --headless --path . res://tools/verify_endings.tscn
##
## | Ending | Keeps |
## | victory | all the run's gear and relics |
## | fled   | 3 items the player picks |
## | slain / throne_fell / abandoned | nothing but XP -- and a carried-in item is lost |
##
## Every profile here is in memory (path ""). Nothing touches the player's
## real meta_profile.json.

var _passed: int = 0
var _failed: int = 0

const A := "tarnished_locket"
const B := "grave_coins"
const C := "sextons_ring"

func _ready() -> void:
	get_tree().root.size = Vector2i(1400, 760)
	await get_tree().process_frame
	print("\n=== Endings, the stash and the Lair (ROGUELITE_REWORK 17.6-17.7) ===\n")
	_the_stash_rules()
	await _flee_keeps_three()
	await _victory_keeps_everything()
	await _death_loses_what_was_risked()
	await _alive_brings_the_risk_home()
	await _the_screens()
	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

func _relic_ids(n: int) -> Array:
	var out: Array = []
	for id in LootCatalog.relic_ids():
		if String(LootCatalog.relic(id).get("tier", "")) != "legendary" and id != C:
			out.append(String(id))
		if out.size() >= n:
			break
	return out

# ---------------- The stash ----------------------------------------------------

func _the_stash_rules() -> void:
	print("-- The stash: shelves, and 1 -> 3 carry slots --")
	var p := MetaProfile.open("")
	_check("one carry slot to begin with", p.carry_slots("necromancer") == 1)
	p.add_xp("necromancer", MetaProfile.threshold(7))
	_check("a second at level 7", p.carry_slots("necromancer") == 2)
	p.add_xp("necromancer", MetaProfile.threshold(20))
	_check("...and never more than three (section 10)", p.carry_slots("necromancer") == 3)
	var p2 := MetaProfile.open("")
	var a: Dictionary = p2.add_to_stash(A, 1, 2)
	var b: Dictionary = p2.add_to_stash(B, 1, 2)
	_check("kept items get their own ids", int(a["uid"]) != int(b["uid"]))
	_check("carry one", p2.set_carry("necromancer", int(a["uid"]), true))
	_check("...but not a second at level 1", not p2.set_carry("necromancer", int(b["uid"]), true))
	_check("a shelf holds one item", p2.set_shelf(int(a["uid"]), 3) and int(p2.on_shelf(3).get("uid", 0)) == int(a["uid"]))
	p2.set_shelf(int(b["uid"]), 3)
	_check("...putting another there takes the first down", int(a.get("shelf", 0)) == -1
		and int(p2.on_shelf(3).get("uid", 0)) == int(b["uid"]))

# ---------------- Endings ------------------------------------------------------

func _spawn() -> Node:
	var m = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(m)
	for i in range(4):
		await get_tree().process_frame
	m.run_lifecycle.pause_on_end = false
	return m

func _despawn(m) -> void:
	get_tree().paused = false
	m.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _flee_keeps_three() -> void:
	print("-- Fleeing the region keeps 3 items, and only from the lair --")
	var m = await _spawn()
	var rl: RunLifecycle = m.run_lifecycle
	var v: Necromancer = m.villain
	var ids: Array = _relic_ids(5)
	v.relics_banked.append_array(ids.slice(0, 3))
	v.relics_carried.append_array(ids.slice(3, 5))
	v.place_at(m.world_map.cell_centre_px(Vector2i(70, 64)))
	_check("away from the lair, he cannot flee", not rl.can_flee() and not rl.flee(ids))
	v.place_at(m._throne_world_centre())
	_check("at the lair, he can", rl.can_flee())
	_check("the run's items are the five he found", rl.run_items().size() == 5)
	rl.flee(ids)
	_check("the run ended as 'fled'", rl.ended and String(rl.summary.get("ending", "")) == "fled")
	var kept: Array = rl.summary.get("kept", [])
	_check("...keeping exactly three", kept.size() == 3 and rl.profile.stash.size() == 3,
		"%d kept, %d stashed" % [kept.size(), rl.profile.stash.size()])
	_check("...the three he chose", kept == ids.slice(0, 3))
	_check("the epitaph says he lived", String(rl.summary.get("epitaph", "")).contains("fled the region alive"))
	await _despawn(m)

func _victory_keeps_everything() -> void:
	print("-- Victory keeps every piece of gear and every relic --")
	var m = await _spawn()
	var rl: RunLifecycle = m.run_lifecycle
	var v: Necromancer = m.villain
	var ids: Array = _relic_ids(5)
	v.relics_banked.append_array(ids.slice(0, 3))
	v.relics_carried.append_array(ids.slice(3, 5))
	rl.end_run("victory", "")
	_check("all five went to the stash", rl.profile.stash.size() == 5 and rl.summary.get("kept", []).size() == 5)
	await _despawn(m)

func _death_loses_what_was_risked() -> void:
	print("-- Death: nothing kept, and what he carried in is gone for good --")
	var m = await _spawn()
	var rl: RunLifecycle = m.run_lifecycle
	var v: Necromancer = m.villain
	var e: Dictionary = rl.profile.add_to_stash(C, 0, 1)
	rl.profile.set_carry(v.class_id, int(e["uid"]), true)
	rl.run_seconds = 0.0
	rl.reapply_carry_in()
	_check("the carried relic is working from the first step (gear: worn from the start)", v.owned_relic_ids().has(C) and v.active_relic_ids().has(C))
	_check("...and is not one of the run's own finds", not rl.run_items().has(C))
	v.relics_banked.append(A)
	v.take_damage(999)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("he died and the run ended", rl.ended and String(rl.summary.get("ending", "")) == "slain")
	_check("nothing was kept", rl.summary.get("kept", []).is_empty())
	_check("the carried relic is lost", rl.summary.get("lost", []).has(C)
		and rl.profile.stash_entry(int(e["uid"])).is_empty())
	await _despawn(m)

func _alive_brings_the_risk_home() -> void:
	print("-- Home alive: a risked item comes back, and pays for the risk --")
	var m = await _spawn()
	var rl: RunLifecycle = m.run_lifecycle
	var v: Necromancer = m.villain
	var e: Dictionary = rl.profile.add_to_stash(C, 0, 1)
	rl.profile.set_carry(v.class_id, int(e["uid"]), true)
	rl.run_seconds = 0.0
	rl.reapply_carry_in()
	v.place_at(m._throne_world_centre())
	var xp0: int = rl.profile.xp(v.class_id)
	rl.flee([])
	_check("it is still in the stash", not rl.profile.stash_entry(int(e["uid"])).is_empty())
	_check("...marked as having survived a risked run", int(rl.profile.stash_entry(int(e["uid"])).get("risked", 0)) == 1)
	_check("...and paid XP for it", rl.profile.xp(v.class_id) - xp0 >= MetaProfile.event_xp("risked_relic_survived"))
	_check("fleeing with nothing picked keeps nothing new", rl.profile.stash.size() == 1)
	await _despawn(m)

# ---------------- The screens --------------------------------------------------

func _the_screens() -> void:
	print("-- The flee picker, the Lair, and the buttons that reach them --")
	var m = await _spawn()
	var d: KeepItemsDialog = m.keep_dialog
	d.open(_relic_ids(5))
	_check("the picker pre-ticks three", d.selected().size() == 3)
	var locked: int = 0
	for pair in d._boxes:
		if pair[0].disabled:
			locked += 1
	_check("...and locks the rest at the limit", locked == 2)
	d._close()
	var p: MetaProfile = m.run_lifecycle.profile
	p.add_to_stash(A, 1, 1)
	p.add_to_stash(B, 1, 1)
	m._open_lair()
	_check("the Lair opens", m.lair_screen.is_showing())
	var carry_boxes: Array = _find_all(m.lair_screen, "CheckBox")
	_check("...with a carry box for each kept item", carry_boxes.size() == 2)
	if carry_boxes.size() == 2:
		carry_boxes[0].button_pressed = true
		await get_tree().process_frame
		var after: Array = _find_all(m.lair_screen, "CheckBox")
		_check("carrying one at level 1 locks the other", after.size() == 2 and after[1].disabled)
	m.lair_screen.visible = false
	var title_buttons: Array = []
	m.title_screen.show_title({"level": 1, "xp": 0, "runs": 0})
	for b in _find_all(m.title_screen, "Button"):
		title_buttons.append(b.text)
	_check("the main menu has a Lair button", title_buttons.has("The Lair"))
	m.title_screen.visible = false
	m.villain.place_at(m.world_map.cell_centre_px(Vector2i(70, 64)))
	m.pause_menu.open()
	var flee_btn = null
	for b in _find_all(m.pause_menu, "Button"):
		if b.text.begins_with("Flee"):
			flee_btn = b
	_check("the pause menu offers Flee the region", flee_btn != null)
	_check("...greyed out away from the lair", flee_btn != null and flee_btn.disabled)
	m.pause_menu.close()
	await _despawn(m)

func _find_all(n: Node, cls: String) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c.is_class(cls) and not c.is_queued_for_deletion():
			out.append(c)
		out.append_array(_find_all(c, cls))
	return out

func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s   (%s)" % [what, detail])
