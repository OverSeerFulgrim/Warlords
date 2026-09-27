extends Node
## The Guild, witnesses and standing, blueprints, the roadside opening
## (LIVING_WORLD_SPEC L2, sections 3, 4, 8.1, 9.1; built 2026-09-26).
##
##   godot --headless --path . res://tools/verify_guild.tscn
##
## L2's exit, as far as a harness can walk it: he wakes on the road, the board
## posts the den, the job pays into his hands, clearing the den teaches the
## Altar, and being seen costs standing **only when the runner arrives** -- kill
## the runner first, and nobody hears. Every act here goes through the path the
## game uses (Main's raise, the site's mark_cleared, the guild's own take /
## deliver / turn_in, the village's labour loop carrying the runner).
##
## The profile is in memory (path ""): nothing touches the player's real save.

var _passed: int = 0
var _failed: int = 0
var _main = null
var _guild: Guild = null
var _vil: Village = null

func _ready() -> void:
	get_tree().root.size = Vector2i(1400, 760)
	await get_tree().process_frame
	_main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(_main)
	for i in range(6):
		await get_tree().process_frame
	seed(20260926)
	_guild = _main.guild
	_vil = _main.village
	print("\n=== The Guild, witnesses, blueprints, the road (LIVING_WORLD L2) ===\n")
	_the_road()
	if _guild == null or _vil == null:
		_check("the guild and the village were built", false)
		_finish()
		return
	await _the_hall()
	_the_board_follows_the_world()
	_jobs_pay_into_his_hands()
	_the_den_teaches_the_altar()
	_kill_the_runner_and_nobody_hears()
	_the_runner_arrives()
	_suspected_pays_half()
	_the_keeper_sees_and_the_doors_shut()
	_the_panels()
	_finish()

func _finish() -> void:
	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

# ---------------- Section 3: the opening ---------------------------------------

func _the_road() -> void:
	print("-- He wakes on the road at the lair's edge (section 3) --")
	var v: Necromancer = _main.villain
	var cell: Vector2i = _main.ROADSIDE_SPAWN_CELL
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_map.json"))
	var ch: String = String(map["rows"][cell.y]).substr(cell.x, 1)
	var cat: String = String(map["legend"].get(ch, {}).get("category", ""))
	_check("the spawn cell is road", cat == "road", "'%s' is %s" % [ch, cat])
	var lb: Array = map["lair_band"]
	_check("...inside the lair band", cell.x >= int(lb[0]) and cell.x < int(lb[0]) + int(lb[2])
		and cell.y >= int(lb[1]) and cell.y < int(lb[1]) + int(lb[3]))
	var nudge: Vector2i = cell + Vector2i(1, 0)
	_check("...on its edge: one step east is outside it", nudge.x >= int(lb[0]) + int(lb[2]))
	_check("he stands there when the run begins", v.position.distance_to(_main.roadside_spawn()) < 1.0,
		"%.0f px off" % v.position.distance_to(_main.roadside_spawn()))
	_check("...not at the Throne", v.position.distance_to(_main._throne_world_centre()) > 8.0 * SettlementGrid.CELL_SIZE)
	_check("...and still under the lair's protection", v.is_in_lair_band())
	_check("no skeleton at the start, on any run", _main.worker_system.workers.is_empty())
	var grave: WorldSite = _site("fresh_grave_scree")
	_check("a fresh grave stands beside the road past the guild", grave != null and _guild != null
		and grave.position.y > _guild.position.y
		and grave.position.distance_to(_guild.position) < 20.0 * SettlementGrid.CELL_SIZE)

# ---------------- Section 4: the hall and its board -----------------------------

func _the_hall() -> void:
	# You cannot click what you cannot see: walk up to it first.
	_at_the_door()
	for i in range(4):
		await get_tree().process_frame
	print("-- The hall on the road (section 4) --")
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_map.json"))
	var c: Vector2i = _main.world_map.cell_at(_guild.position)
	var ch: String = String(map["rows"][c.y]).substr(c.x, 1)
	_check("the guild stands on open ground", String(map["legend"].get(ch, {}).get("category", "")) != "blocking",
		"'%s' at %s" % [ch, c])
	var road_near: bool = false
	for dx in range(-5, 6):
		var ch2: String = String(map["rows"][c.y]).substr(c.x + dx, 1)
		if String(map["legend"].get(ch2, {}).get("category", "")) == "road":
			road_near = true
	_check("...beside the road (caravans pass its door)", road_near)
	_check("the guild does not know what he is", _main.villain.standing_with(Guild.FACTION) == Necromancer.Standing.UNKNOWN)
	_check("he can be inspected", _main._inspect_at(_guild.hit_centre()) and _main.inspector.current_source() == _guild)
	_main._close_inspector()

func _the_board_follows_the_world() -> void:
	print("-- The board is generated from world state (section 4.2) --")
	_guild.refresh_board()
	var dens: Array = _main.world_sites.dens()
	var den_jobs: Array = _guild.visible_bounties().filter(func(b): return String(b["kind"]) == "den")
	_check("every standing den posts a bounty", den_jobs.size() == dens.size() and dens.size() >= 1,
		"%d jobs for %d dens" % [den_jobs.size(), dens.size()])
	var titles: Dictionary = {}
	for b in den_jobs:
		titles[String(b["title"])] = true
	_check("two dens with one name read apart on the board (by direction)", titles.size() == den_jobs.size(), str(titles.keys()))
	_check("a well-stocked village posts nothing",
		_guild.visible_bounties().filter(func(b): return String(b["kind"]) == "deliver").is_empty())
	var s: Settlement = _vil.settlement
	var wood0: int = s.amount("wood")
	s.set_amount("wood", 3)
	_guild.refresh_board()
	var wood_jobs: Array = _guild.visible_bounties().filter(func(b): return String(b.get("res", "")) == "wood")
	_check("a village short of wood posts a delivery", wood_jobs.size() == 1)
	_guild.refresh_board()
	_check("...once, however often the board is read",
		_guild.visible_bounties().filter(func(b): return String(b.get("res", "")) == "wood").size() == 1)
	s.set_amount("wood", 30)
	_guild.refresh_board()
	_check("...and takes it down when the mill is full again",
		_guild.visible_bounties().filter(func(b): return String(b.get("res", "")) == "wood").is_empty())
	s.set_amount("wood", wood0)

func _jobs_pay_into_his_hands() -> void:
	print("-- Take, deliver, collect: the pay goes into his hands --")
	var v: Necromancer = _main.villain
	var s: Settlement = _vil.settlement
	s.set_amount("food", 2)
	_guild.refresh_board()
	var job: Dictionary = _first(func(b): return String(b.get("res", "")) == "food" and String(b["state"]) == "open")
	_check("a food delivery is posted", not job.is_empty())
	if job.is_empty():
		return
	var id: int = int(job["id"])
	v.place_at(_main.world_map.cell_centre_px(Vector2i(70, 64)))
	_check("away from the door he cannot take it", not _guild.take(v, id))
	_at_the_door()
	_check("at the door he can", _guild.take(v, id) and String(job["state"]) == "taken")
	GameState.food = 4
	_check("without the goods it cannot be handed over", not _guild.deliver(v, id) and GameState.food == 4)
	GameState.food = 15
	v.carried.clear()
	var gold0: int = int(v.carried.get("gold", 0))
	var village_food0: int = s.amount("food")
	_check("with them it can", _guild.deliver(v, id))
	_check("...the goods leave his stores", GameState.food == 15 - int(job["amount"]))
	_check("...and arrive in the village's", s.amount("food") == village_food0 + int(job["amount"]))
	var fits: int = mini(int(job["gold"]), v.carry_capacity())
	_check("...and the pay is in his hands, not his treasury, at full rate while Unknown",
		int(v.carried.get("gold", 0)) - gold0 == fits and int(job["owed"]) == int(job["gold"]) - fits,
		"%d gold in hand, %d owed" % [int(v.carried.get("gold", 0)), int(job["owed"])])
	v.carried.clear()
	if int(job["owed"]) > 0:
		_guild.turn_in(v, id)
	_check("...and the job is paid off once he has room for the rest", String(job["state"]) == "paid")
	v.carried.clear()
	s.set_amount("food", 30)
	_guild.refresh_board()
	# Two jobs in hand is the limit.
	var dens: Array = _guild.visible_bounties().filter(func(b): return String(b["kind"]) == "den" and String(b["state"]) == "open")
	if dens.size() >= 2:
		_check("he can hold two jobs", _guild.take(v, int(dens[0]["id"])) and _guild.take(v, int(dens[1]["id"])))
		s.set_amount("wood", 1)
		_guild.refresh_board()
		var w: Dictionary = _first(func(b): return String(b.get("res", "")) == "wood" and String(b["state"]) == "open")
		_check("...but not a third", not w.is_empty() and not _guild.take(v, int(w["id"])))
		s.set_amount("wood", 30)
		_guild.refresh_board()

func _the_den_teaches_the_altar() -> void:
	print("-- Clearing the den: the bounty, and the Altar blueprint (section 3, 9.1) --")
	var v: Necromancer = _main.villain
	var profile: MetaProfile = _main.run_lifecycle.profile
	_check("the Altar is not buildable before", not BuildingCatalog.buildable_ids(_main.settlement).has("dark_altar"))
	var job: Dictionary = _first(func(b): return String(b["kind"]) == "den" and String(b["state"]) == "taken")
	if job.is_empty():
		_check("a den job in hand", false)
		return
	var den: WorldSite = job["site"]
	var learned: Array = []
	var conn := func(id: String, _src: String): learned.append(id)
	EventBus.blueprint_learned.connect(conn)
	den.mark_cleared(v)
	EventBus.blueprint_learned.disconnect(conn)
	_check("clearing the den teaches the Dark Altar", profile.knows_blueprint("dark_altar") and learned == ["dark_altar"])
	_check("...and the build menu offers it now", BuildingCatalog.buildable_ids(_main.settlement).has("dark_altar"))
	_guild.refresh_board()
	_check("the bounty is ready to collect", String(job["state"]) == "done")
	# Hands full: nothing is paid, and nothing is lost.
	v.carried.clear()
	v.add_carried("wood", v.carry_capacity())
	_check("with full hands the clerk holds the pay", not _guild.turn_in(v, int(job["id"]))
		and int(job["owed"]) == int(job["gold"]) and String(job["state"]) == "done")
	v.carried.clear()
	v.add_carried("wood", v.carry_capacity() - 3)
	_guild.turn_in(v, int(job["id"]))
	_check("...room for three: three paid, the rest still owed", int(v.carried.get("gold", 0)) == 3
		and int(job["owed"]) == int(job["gold"]) - 3, "owed %d" % int(job["owed"]))
	v.carried.clear()
	var rest: int = int(job["gold"]) - 3
	_check("...and collected on the next visit (as much as he can carry)", _guild.turn_in(v, int(job["id"]))
		and int(v.carried.get("gold", 0)) == mini(rest, v.carry_capacity()))
	while String(job["state"]) != "paid":
		v.carried.clear()
		if not _guild.turn_in(v, int(job["id"])):
			break
	_check("...until it is paid off", String(job["state"]) == "paid")
	v.carried.clear()
	var second: MetaProfile = MetaProfile.open("")
	second.learn_blueprint("dark_altar")
	_check("a blueprint is kept for good (it is on the profile)", second.knows_blueprint("dark_altar"))

# ---------------- Section 8.1: seen, and told -----------------------------------

## Leaves `who` as the only non-guard villager within sight of `at`.
func _isolate(who: Villager, at: Vector2) -> void:
	var reach: float = _guild.attention_px(true) + 64.0
	for o in _vil.living():
		if o == who or o.is_guard():
			continue
		if o.position.distance_to(at) <= reach:
			o.position = at + Vector2(0, reach + 200.0)
			o.idle_anchor = o.position

func _tick(n: int) -> void:
	for i in range(n):
		_vil.labor._process(0.05)
		_vil._process(0.05)

func _kill_the_runner_and_nobody_hears() -> void:
	print("-- Run him down before the gate, and nobody hears (section 8.1) --")
	var v: Necromancer = _main.villain
	var wyn: Villager = _named("Wyn")
	if wyn == null:
		_check("Wyn is in the village", false)
		return
	_isolate(wyn, wyn.position)
	var threat0: int = GameState.threat
	v.place_at(wyn.position + Vector2(3.0 * SettlementGrid.CELL_SIZE, 0))
	GameState.bones = 10
	var seen: Array = []
	var conn := func(_v, who, act: String): seen.append([who, act])
	EventBus.witnessed.connect(conn)
	_main._recruit_worker()
	EventBus.witnessed.disconnect(conn)
	_check("he raised one in plain sight, and Wyn saw it", seen.size() == 1 and seen[0][0] == wyn, str(seen))
	_check("...and is running to tell", wyn.is_running_to_tell())
	var gh: Vector2 = _vil.buildings["guardhouse"].position
	_check("...to the nearest place that will listen (the Guardhouse, not the guild)",
		wyn.runner_to.distance_to(gh) < 1.0)
	_vil._process_bangs()
	var tok = _vil._tokens.get(wyn)
	_check("...with a ! over his head", tok != null and tok.get_node_or_null("Bang") != null)
	_check("nothing has changed yet: standing drops on arrival",
		v.standing_with(Guild.FACTION) == Necromancer.Standing.UNKNOWN and GameState.threat == threat0)
	_vil.on_villager_killed(wyn, v)
	_tick(200)
	_check("he is dead before the gate -- and nobody hears",
		v.standing_with(Guild.FACTION) == Necromancer.Standing.UNKNOWN and GameState.threat == threat0,
		"%s, threat %d" % [Necromancer.standing_name(v.standing_with(Guild.FACTION)), GameState.threat])

func _the_runner_arrives() -> void:
	print("-- A runner who gets there drops his standing, once --")
	var v: Necromancer = _main.villain
	var runner: Villager = null
	for o in _vil.living():
		if not o.is_guard() and not o.is_running_to_tell():
			runner = o
			break
	if runner == null:
		_check("a villager left to see it", false)
		return
	_isolate(runner, runner.position)
	var threat0: int = GameState.threat
	v.place_at(runner.position + Vector2(2.0 * SettlementGrid.CELL_SIZE, 0))
	GameState.bones = 10
	_main._recruit_worker()
	_check("%s saw it and runs" % runner.villager_name, runner.is_running_to_tell())
	var arrived: Array = []
	var conn := func(_v, who, _act: String, where: String): arrived.append([who, where])
	EventBus.report_arrived.connect(conn)
	for i in range(3000):
		_tick(1)
		if not arrived.is_empty():
			break
	EventBus.report_arrived.disconnect(conn)
	_check("he got there", arrived.size() == 1 and arrived[0][0] == runner, str(arrived))
	_check("...and the guild now Suspects him", v.standing_with(Guild.FACTION) == Necromancer.Standing.SUSPECTED)
	_check("...and the region's threat rose", GameState.threat == threat0 + _guild.report_threat(),
		"%d -> %d" % [threat0, GameState.threat])
	_check("...and the runner goes back to his life", not runner.is_running_to_tell())
	_main.witnesses.arrive({"villain": v, "act": "raising the dead", "id": _main.witnesses._next_act - 1}, "the Guardhouse")
	_check("a second man telling the same story changes nothing",
		v.standing_with(Guild.FACTION) == Necromancer.Standing.SUSPECTED and GameState.threat == threat0 + _guild.report_threat())
	var other = Necromancer.new()
	_main.witnesses.arrive({"villain": other, "act": "x", "id": 999}, "the Guardhouse")
	_check("a report about another villain is not his", v.standing_with(Guild.FACTION) == Necromancer.Standing.SUSPECTED)
	_check("attention is longer by day than by night (ruling 15)", _guild.attention_px(true) > _guild.attention_px(false))

func _suspected_pays_half() -> void:
	print("-- Suspected: the board still pays, at half --")
	var v: Necromancer = _main.villain
	_at_the_door()
	var job: Dictionary = _first(func(b): return String(b["kind"]) == "den" and String(b["state"]) == "taken")
	if job.is_empty():
		job = _first(func(b): return String(b["kind"]) == "den" and String(b["state"]) == "open")
		_check("Suspected, he can still take a job", not job.is_empty() and _guild.take(v, int(job["id"])))
	if job.is_empty():
		return
	v.carried.clear()
	(job["site"] as WorldSite).mark_cleared(v)
	_guild.refresh_board()
	var half: int = int(round(float(job["gold"]) * 0.5))
	_check("the second den's pay is halved", _guild.turn_in(v, int(job["id"]))
		and int(v.carried.get("gold", 0)) + int(job["owed"]) == half,
		"%d in hand + %d owed, of %d" % [int(v.carried.get("gold", 0)), int(job["owed"]), int(job["gold"])])
	v.carried.clear()

func _the_keeper_sees_and_the_doors_shut() -> void:
	print("-- The keeper sees from the door: no runner needed; Known shuts it --")
	var v: Necromancer = _main.villain
	_at_the_door()
	GameState.bones = 10
	_main._recruit_worker()
	_check("raised on the guild's doorstep: Known at once", v.standing_with(Guild.FACTION) == Necromancer.Standing.KNOWN)
	_check("the doors are shut to him", not _guild.open_to(v))
	GameState.food = 0
	_vil.settlement.set_amount("food", 1)
	_guild.refresh_board()
	var job: Dictionary = _first(func(b): return String(b["state"]) == "open")
	_check("...he cannot take a job", not job.is_empty() and not _guild.take(v, int(job["id"])))
	_check("standing only moves one way (and stops at Known)",
		v.lower_standing(Guild.FACTION, "again") == Necromancer.Standing.KNOWN)
	_vil.settlement.set_amount("food", 30)

# ---------------- The panels ---------------------------------------------------

func _the_panels() -> void:
	print("-- The board, the Altar and the opening hint, on screen --")
	var box := VBoxContainer.new()
	add_child(box)
	_main.inspector_actions.guild_actions(box, _guild)
	var text: String = _texts(box)
	_check("the board shows his standing", text.contains("Standing: Known"))
	_check("...and says the doors are shut", text.contains("doors are shut"))
	box.queue_free()
	var box2 := VBoxContainer.new()
	add_child(box2)
	_main.inspector_actions.altar_actions(box2)
	var btn = _find(box2, "Button")
	_check("the Altar offers Summon Ghoul", btn != null and btn.text == "Summon Ghoul")
	var lvl: int = _main.run_lifecycle.profile.level(_main.villain.class_id)
	var why: String = "level 2" if lvl < 2 else "prisoner"
	_check("...greyed, with the reason (%s)" % why, btn != null and btn.disabled and _texts(box2).contains(why))
	box2.queue_free()
	_main._show_opening_popup()
	_check("the first-run hint says where to go", _main.opening_popup.visible
		and _texts(_main.opening_popup).contains(_main.OPENING_POPUP_TEXT))

# ---------------- Helpers ------------------------------------------------------

func _at_the_door() -> void:
	_main.villain.place_at(_guild.position + Vector2(0, float(SettlementGrid.CELL_SIZE)))

func _first(pred: Callable) -> Dictionary:
	for b in _guild.bounties:
		if pred.call(b):
			return b
	return {}

func _named(n: String) -> Villager:
	for o in _vil.living():
		if o.villager_name == n:
			return o
	return null

func _site(id: String) -> WorldSite:
	for s in _main.world_sites.sites:
		if s.site_id == id:
			return s
	return null

func _texts(n: Node) -> String:
	var out: String = ""
	if n is Label or n is Button:
		out += n.text + "\n"
	elif n is RichTextLabel:
		out += n.text + "\n"
	for c in n.get_children():
		out += _texts(c)
	return out

func _find(n: Node, cls: String):
	for c in n.get_children():
		if c.is_class(cls):
			return c
		var f = _find(c, cls)
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
