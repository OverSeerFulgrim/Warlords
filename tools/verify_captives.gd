extends Node
## **Downed, bound, held** (LIVING_WORLD L3, 2026-09-27).
##
##   godot --headless --path . res://tools/verify_captives.tscn
##
## The L3 exit: capture-or-slay is a real choice because prisoners do something
## corpses don't, and bodies you leave come back as graves. Walks it through
## the real systems -- CombatSystem's defeat path, the village's guards on their
## errands, the Cell, the meals, the Altar:
##
## - at 0 hp a villager or an outlaw goes **down**, a wolf does not;
## - a downed man bleeds out into a body, the death his who put him down;
## - bind (only standing over him) -> a prisoner on the rope who follows him;
## - home with no Cell: he stays on the rope; the first search teaches the Cell;
## - with a Cell he goes in; he eats at dawn and dusk; unfed twice, a body;
## - Summon Ghoul: level 2, the Altar, a prisoner -> an undead Ghoul worker;
## - a guard carries a downed villager home and he comes round;
## - a guard finds a body and buries it: a new raisable grave at the graveyard;
##   a hidden body is never found;
## - Bind all / Finish all; the rope goes slack when he falls;
## - the HUD's Bind / Finish buttons and prisoner line appear only when they apply.

var _passed: int = 0
var _failed: int = 0
var _main = null
var _cap: Captives = null
var _vil: Village = null
var _v: Necromancer = null

func _ready() -> void:
	get_tree().root.size = Vector2i(1400, 800)
	await get_tree().process_frame
	_main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(_main)
	for i in range(8):
		await get_tree().process_frame
	seed(20260927)
	_cap = _main.captives
	_vil = _main.village
	_v = _main.villain
	print("\n=== Downed, prisoners, the Cell, the Altar, burial (LIVING_WORLD L3) ===\n")
	if _cap == null or _vil == null:
		_check("the captives system and the village were built", false)
		_finish()
		return
	# Keep the village's own guards out of the tests that are not about them.
	_vil._data["body_notice_cells"] = 0.0
	_the_ghoul_row()
	_down_not_dead()
	_bleeding_out()
	await _binding_and_the_rope()
	_home_without_a_cell()
	_search_teaches_the_cell()
	_into_the_cell()
	_meals_and_starving()
	_summon_ghoul()
	_batch_orders()
	_outlaws_and_wolves()
	await _a_guard_carries_him_home()
	await _burial()
	_the_rope_goes_slack()
	await _the_hud()
	_finish()

func _finish() -> void:
	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

# ---------------- helpers ----------------

func _person(n: String) -> Villager:
	for v in _vil.villagers:
		if v.villager_name == n:
			return v
	return null

## The real defeat path: what CombatSystem does when a villager in a fight hits 0.
func _put_down(v: Villager) -> Downed:
	v.hp = 0
	v.leave_reason = "killed"
	_main.combat_system._remove_attacker(v)
	for d in _cap.downed:
		if d.person == v:
			return d
	return null

func _step(seconds: float, dt: float = 0.1) -> void:
	var t: float = 0.0
	while t < seconds:
		_cap._process(dt)
		t += dt

func _place_building(id: String) -> Building:
	var throne: Building = _main.settlement.get_main_building()
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c: Vector2i = throne.cell + Vector2i(dx, dy)
				if _main.settlement.can_place(c):
					var b := Building.make_from_data(id, BuildingCatalog.get_building(id))
					if _main.settlement.place_building(b, c):
						return b
	return null

func _deed(i: int) -> String:
	var e: Dictionary = _v.deeds[i]
	return String(e.get("id", e.get("deed", "")))

func _body_of(n: String) -> WorldSite:
	for s in _main.world_sites.sites:
		if is_instance_valid(s) and s.display_name == "%s's Body" % n:
			return s
	return null

# ---------------- the checks ----------------

func _the_ghoul_row() -> void:
	print("-- The Ghoul is a workbook row --")
	var a: Dictionary = RaceCatalog.attributes("ghoul")
	_check("races.json has a Ghoul with all nine", a.size() == 9)
	_check("...Undead, so Command Undead binds it", String(RaceCatalog.get_race("ghoul").get("alignment", "")) == "Undead")
	var g := Worker.new("test ghoul", "ghoul")
	_check("a Ghoul Worker is 20 hp and Melee (Str 7)", g.max_hp() == 20 and String(g.combat_profile()["profile"]) == "Melee",
		"%d hp, %s" % [g.max_hp(), g.combat_profile()["profile"]])
	_check("...and stronger than a skeleton", g.strength > Worker.new("s").strength)

func _down_not_dead() -> void:
	print("-- At 0 hp a villager goes down, not dead --")
	var frank: Villager = _person("Frank")
	var d: Downed = _put_down(frank)
	_check("Frank is down", d != null and frank.downed and not frank.dead)
	_check("...off the village's living roll (no work, no meals)", not _vil.living().has(frank))
	_check("...with no body yet", _body_of("Frank") == null)
	_check("...bleeding out for the data's window", d != null and is_equal_approx(d.bleed_left, _cap.bleed_seconds()))
	_check("...and clickable where he lies", d != null and _cap.pick_at(d.position + Vector2(0, -12)) == d)

func _bleeding_out() -> void:
	print("-- Leave him, and he bleeds out --")
	var frank: Villager = _person("Frank")
	var d: Downed = null
	for x in _cap.downed:
		if x.person == frank:
			d = x
	var deeds0: int = _v.deeds.size()
	d.bleed_left = 0.05
	_step(0.2)
	_check("Frank died of it", frank.dead and not _cap.downed.has(d))
	_check("...leaving a body where he fell", _body_of("Frank") != null)
	_check("...and the death is the man who put him down", _v.deeds.size() > deeds0
		and _deed(_v.deeds.size() - 1) == "slew_a_villager")

func _binding_and_the_rope() -> void:
	print("-- Bind him: a prisoner on the rope --")
	var edda: Villager = _person("Edda")
	var d: Downed = _put_down(edda)
	_v.place_at(d.position + Vector2(300, 0))
	_check("too far away: bind refuses", _cap.bind(d, _v) == null and _cap.downed.has(d))
	_v.place_at(d.position + Vector2(20, 0))
	var p: Prisoner = _cap.bind(d, _v)
	_check("standing over him: bound", p != null and _v.prisoners.has(p))
	_check("Edda is taken -- not dead, not the village's", edda.captured and not edda.dead and not _vil.living().has(edda))
	_check("...no body", _body_of("Edda") == null)
	_check("...and the deed is on his ledger", _deed(_v.deeds.size() - 1) == "took_a_prisoner")
	# He walks off; the rope follows.
	var start: Vector2 = _v.position
	for i in range(60):
		_v.place_at(start + Vector2(0, 4.0 * i))
		_cap._process(0.1)
	_check("the prisoner follows him on the rope", p.position.distance_to(_v.position) < 60.0,
		"%.0f px behind" % p.position.distance_to(_v.position))
	await get_tree().process_frame

func _home_without_a_cell() -> void:
	print("-- Home with no Cell: nowhere to put him --")
	var warned: Array = [0]
	var conn := func(_vv, _w, _c): warned[0] += 1
	EventBus.prisoners_no_room.connect(conn)
	_v.place_at(_main._throne_world_centre() + Vector2(0, 40))
	_cap._process(0.1)
	_cap._process(0.1)
	EventBus.prisoners_no_room.disconnect(conn)
	_check("no Cell: he stays on the rope", _v.prisoners.size() == 1 and _cap.held().is_empty())
	_check("...and the player is told, once", warned[0] == 1, "%d" % warned[0])

func _search_teaches_the_cell() -> void:
	print("-- Search him: the first search teaches the Cell --")
	var profile: MetaProfile = _main.run_lifecycle.profile
	profile.blueprints.erase("cell")
	var p: Prisoner = _v.prisoners[0]
	var r: Dictionary = _cap.search(p, _v)
	_check("searched", not r.is_empty() and p.searched)
	_check("...and he knows how a Cell is built", profile.knows_blueprint("cell"), str(profile.blueprints))
	_check("a man is searched once", _cap.search(p, _v).is_empty())
	_check("the Cell is in the build menu now", BuildingCatalog.buildable_ids(_main.settlement).has("cell"))

func _into_the_cell() -> void:
	print("-- With a Cell, he goes in --")
	var cell: Building = _place_building("cell")
	_check("a Cell was built (holds 4)", cell != null and _cap.cell_capacity() == 4)
	_cap._process(0.1)
	_check("home: the prisoner went into the Cell", _v.prisoners.is_empty() and _cap.held().size() == 1)
	_check("...which the settlement owns (Settlement.prisoners)", GameState.player_settlement.prisoners.size() == 1)

func _meals_and_starving() -> void:
	print("-- Prisoners eat; unfed twice, they die --")
	var p: Prisoner = _cap.held()[0]
	GameState.food = 3
	_cap._on_meal(1)
	_check("a meal: one food each", GameState.food == 2 and p.missed_meals == 0)
	GameState.food = 0
	_cap._on_meal(1)
	_check("no food: one missed meal, still alive", p.missed_meals == 1 and _cap.held().has(p))
	GameState.food = 5
	_cap._on_meal(1)
	_check("fed again, the count resets", p.missed_meals == 0)
	# A second prisoner to starve, so Edda is kept for the Altar.
	var tobin: Villager = _person("Tobin")
	var d: Downed = _put_down(tobin)
	_v.place_at(d.position + Vector2(10, 0))
	var p2: Prisoner = _cap.bind(d, _v)
	GameState.food = 1
	_cap._on_meal(2)
	GameState.food = 0
	_cap._on_meal(2)
	_check("two missed meals in a row: he died where he was held", not _v.prisoners.has(p2) and not _cap.all_prisoners().has(p2))
	_check("...a body to raise", _body_of("Tobin") != null)
	GameState.food = 10
	_v.place_at(_main._throne_world_centre() + Vector2(0, 40))

func _summon_ghoul() -> void:
	print("-- Summon Ghoul: level 2, the Altar, a living sacrifice --")
	var lvl: Array = [1]
	_cap.level_provider = func() -> int: return lvl[0]
	_check("level 1: not yet", _cap.ghoul_blocker(_v).contains("level 2"))
	lvl[0] = 2
	_check("no Altar: cast at an Altar", _cap.ghoul_blocker(_v).contains("Altar"))
	var altar: Building = _place_building("dark_altar")
	_check("the Altar is built", altar != null)
	_check("level 2, an Altar, a prisoner, at home: it can be cast", _cap.ghoul_blocker(_v) == "", _cap.ghoul_blocker(_v))
	var p: Prisoner = _cap.held()[0]
	var n0: int = _main.worker_system.workers.size()
	var g = _cap.summon_ghoul(p, _v)
	_check("a Ghoul got up", g != null and _main.worker_system.workers.size() == n0 + 1)
	_check("...a Ghoul, not a skeleton, and undead", g != null and g.inspect_race_id() == "ghoul" and g.is_undead())
	_check("...named for the man he was", g != null and String(g.worker_name).begins_with("Edda"), g.worker_name if g else "")
	_check("the prisoner is gone", not _cap.all_prisoners().has(p))
	_check("no prisoner left: it says so", _cap.ghoul_blocker(_v).contains("prisoner"))

func _batch_orders() -> void:
	print("-- Bind all / Finish all (section 11.3) --")
	var a: Villager = _person("Randy")
	var b: Villager = _person("Hale")
	var c: Villager = _person("Wyn")
	var da: Downed = _put_down(a)
	var db: Downed = _put_down(b)
	db.position = da.position + Vector2(40, 0)
	_v.place_at(da.position + Vector2(20, 0))
	_check("two down near him", _cap.downed_near(_v).size() == 2)
	_check("Bind all binds both", _cap.bind_all(_v) == 2 and _v.prisoners.size() == 2)
	var dc: Downed = _put_down(c)
	_v.place_at(dc.position)
	_check("Finish all finishes him", _cap.finish_all(_v) == 1 and c.dead and _body_of("Wyn") != null)

func _outlaws_and_wolves() -> void:
	print("-- Outlaws go down; wolves do not --")
	var ws: WorldSites = _main.world_sites
	var cave: WorldSite = null
	var den: WorldSite = null
	for s in ws.sites:
		if s.site_id == "outlaw_cave":
			cave = s
		if s.is_den() and den == null and not s.guardians.is_empty():
			den = s
	if cave == null or cave.guardians.is_empty():
		_check("the outlaw cave has its outlaws", false)
		return
	var o: SiteGuardian = cave.guardians[0]
	o.hp = 1
	_check("an outlaw never runs from his own cave", o.never_flees and not o.should_flee())
	o.hp = 0
	o.leave_reason = "killed"
	var n0: int = _cap.downed.size()
	_main.combat_system._remove_attacker(o)
	var od: Downed = _cap.downed[_cap.downed.size() - 1] if _cap.downed.size() > n0 else null
	_check("an outlaw at 0 hp goes down", od != null and od.faction == "outlaw")
	_check("...and has left the cave's guard", not cave.guardians.has(o))
	_v.place_at(od.position + Vector2(10, 0))
	var p: Prisoner = _cap.bind(od, _v)
	_check("...and can be bound", p != null and p.origin == cave.display_name)
	if den:
		var w: SiteGuardian = den.guardians[0]
		w.hp = 0
		w.leave_reason = "killed"
		var n1: int = _cap.downed.size()
		_main.combat_system._remove_attacker(w)
		_check("a pack wolf at 0 hp is dead, not down", _cap.downed.size() == n1 and not den.guardians.has(w))

func _a_guard_carries_him_home() -> void:
	print("-- His own come for him: a guard carries him home --")
	var edda_s: Villager = _person("Osric")   # a guard to put down
	var guard: Villager = _person("Brom")
	var d: Downed = _put_down(edda_s)
	# Farmers taken, the village pulled its guards into the fields (food >
	# safety). Give it one guard back for this test.
	guard.assign("guard", _vil.buildings.get("guardhouse"), 0.0)
	guard.trained = true
	_v.place_at(d.position + Vector2(600, 0))
	_vil._alarm_left = 0.0
	guard.duty = {}
	guard.in_combat = false
	guard.panicked = false
	guard.runner_to = Vector2.ZERO   # he saw a binding earlier and ran to tell
	guard.report = {}
	guard.position = d.position + Vector2(200, 0)
	_vil._assign_duties()
	_check("a free guard goes for him", String(guard.duty.get("kind", "")) == "rescue" and guard.duty.get("target") == d,
		str(guard.duty))
	var bleed0: float = d.bleed_left
	guard.position = d.position
	_vil.labor._advance_laborer(guard, 0.1)
	_check("he picks him up", d.is_carried() and d.carrier == guard)
	_step(1.0)
	_check("carried, he does not bleed", is_equal_approx(d.bleed_left, bleed0))
	guard.position = edda_s.idle_anchor
	_vil.labor._advance_laborer(guard, 0.1)
	_check("home: he comes round, hurt and shaken", not edda_s.downed and _vil.living().has(edda_s)
		and edda_s.hp > 0 and edda_s.hp < edda_s.max_hp() and edda_s.panicked)
	_check("...and the guard is free again", guard.duty.is_empty())
	await get_tree().process_frame

func _burial() -> void:
	print("-- The dead are buried: a new grave (section 5.7) --")
	var threat0: int = GameState.threat
	var body: WorldSite = _body_of("Frank")
	_check("Frank's body is still out there", body != null)
	var guard: Villager = _person("Brom")
	guard.duty = {}
	guard.panicked = false
	guard.runner_to = Vector2.ZERO
	guard.position = body.position + Vector2(30, 0)
	_vil._data["body_notice_cells"] = 6.0
	_vil._alarm_left = 0.0
	_vil._scan_bodies()
	_check("a villager near it finds it; threat rises", _vil._known_bodies.has(body) and GameState.threat > threat0)
	# A hidden body is never found.
	var hidden: WorldSite = _main.world_sites.spawn_body(guard.position + Vector2(-40, 0), "Nobody")
	hidden._conceals = 1
	_vil._scan_bodies()
	_check("a hidden body is never found", not _vil._known_bodies.has(hidden))
	_vil._known_bodies = {body: true}
	for other in _vil.living():
		if other.is_guard() and other != guard:
			other.duty = {"kind": "busy"}
	_vil._assign_duties()
	_check("a guard is sent to bury him", String(guard.duty.get("kind", "")) == "bury" and guard.duty.get("target") == body, str(guard.duty))
	guard.position = body.position
	_vil.labor._advance_laborer(guard, 0.1)
	await get_tree().process_frame
	_check("he lifts the body (nothing left to raise there)", bool(guard.duty.get("carrying", false)) and _body_of("Frank") == null)
	var graves0: int = _main.world_sites.sites.filter(func(s): return is_instance_valid(s) and s.display_name == "Frank's Grave").size()
	guard.duty["to"] = _vil.next_grave_spot()
	guard.position = guard.duty["to"]
	_vil.labor._advance_laborer(guard, 0.1)
	var graves: Array = _main.world_sites.sites.filter(func(s): return is_instance_valid(s) and s.display_name == "Frank's Grave")
	_check("a new grave at the graveyard, with his name on it", graves.size() == graves0 + 1)
	if not graves.is_empty():
		var g: WorldSite = graves[0]
		_check("...a fresh grave: a corpse to raise", g.loot_type == "fresh_grave" and g.corpse_present())
		_check("...near the village graveyard", g.position.distance_to(_vil.graveyard_position()) < 6.0 * 64.0)
	for other in _vil.living():
		if String(other.duty.get("kind", "")) == "busy":
			other.duty = {}

func _the_rope_goes_slack() -> void:
	print("-- He falls with prisoners on the rope --")
	var tow: Array = _v.prisoners.duplicate()
	var villagers_on_rope: Array = tow.filter(func(p): return p.person != null)
	_check("he has villagers on the rope", not villagers_on_rope.is_empty())
	_cap._on_villain_died(_v, "test")
	_check("the rope went slack", _v.prisoners.is_empty())
	var back: bool = true
	for p in villagers_on_rope:
		back = back and not p.person.captured and _vil.living().has(p.person)
	_check("...and the villagers walked home", back)

func _the_hud() -> void:
	print("-- The HUD: Bind / Finish and the prisoner line appear when they apply --")
	var ab: ActionBar = _main.action_bar
	var t: HudTopBar = _main.hud_top_bar
	for d in _cap.downed.duplicate():
		_cap._die(d, null, "test")
	ab.refresh()
	t.refresh_prisoners()
	_check("nobody down near him: no Bind / Finish buttons", not ab.bind_btn.visible and not ab.finish_btn.visible)
	_check("the prisoner line shows exactly when he holds anyone", t.prisoner_panel.visible == not _cap.all_prisoners().is_empty())
	var guard: Villager = _person("Brom")
	var d: Downed = _put_down(guard)
	_v.place_at(d.position + Vector2(30, 0))
	ab.refresh()
	_check("a man down near him: Bind and Finish appear", ab.bind_btn.visible and ab.finish_btn.visible)
	_main._captive_action("bind_all", null)
	ab.refresh()
	t.refresh_prisoners()
	_check("G/Bind binds him (the same order the key sends)", _v.prisoners.size() == 1 and not ab.bind_btn.visible)
	_check("the prisoner line shows who is on the rope", t.prisoner_panel.visible and t.prisoner_label.text.contains("Brom"),
		t.prisoner_label.text)
	_check("key actions 'bind' and 'finish' exist", InputMap.has_action("bind") and InputMap.has_action("finish"))
	await get_tree().process_frame

func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s   (%s)" % [what, detail])
