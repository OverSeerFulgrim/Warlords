extends Node
## The living village and the stance (LIVING_WORLD_SPEC L0 + L1, rulings 13-15,
## built 2026-09-26).
##
##   godot --headless --path . res://tools/verify_village.tscn
##
## L0's exit: the player's town runs unchanged on the generalised model, and a
## second settlement owned by "human" exists and ticks. L1's: kill a woodcutter,
## watch the village react -- nothing scripted. Every kill here goes through the
## path the game uses (CombatSystem's engagement, or Village.on_villager_killed
## as CombatSystem calls it), never by editing a roster by hand.

var _passed: int = 0
var _failed: int = 0
var _main = null
var _vil: Village = null

func _ready() -> void:
	get_tree().root.size = Vector2i(1400, 760)
	await get_tree().process_frame
	_main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(_main)
	for i in range(6):
		await get_tree().process_frame
	seed(20260926)
	_vil = _main.village
	print("\n=== The living village and the stance (LIVING_WORLD L0/L1) ===\n")
	_the_facade()
	_the_deposit_rule()
	if _vil == null:
		_check("the village was built", false)
		_finish()
		return
	_a_second_settlement()
	_it_ticks()
	_integrity_scales_the_mill()
	_meals_come_out_of_its_own_stores()
	_the_stance_and_hostiles()
	await _hunting_kills_and_the_village_reacts()
	_the_randy_rule()
	_training()
	_raise_the_body()
	_finish()

func _finish() -> void:
	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

# ---------------- L0: one settlement model -------------------------------------

func _the_facade() -> void:
	print("-- GameState is a facade over the player's settlement (ruling 13) --")
	var s: Settlement = GameState.player_settlement
	_check("the player's settlement is owned by the villain", s != null and s.is_players())
	GameState.wood = 41
	_check("writing GameState.wood writes the settlement", s.amount("wood") == 41)
	s.set_amount("stone", 17)
	_check("...and reading it reads the settlement", GameState.stone == 17)
	var fired: Array = [0]
	var conn := func(): fired[0] += 1
	GameState.resources_changed.connect(conn)
	GameState.add_resource("bones", 2)
	GameState.resources_changed.disconnect(conn)
	_check("add_resource announces exactly once", fired[0] == 1, "%d" % fired[0])
	_check("followers are the settlement's population",
		GameState.followers == s.followers)
	var before: int = GameState.bones
	_check("an unknown kind is refused and changes nothing",
		not GameState.spend_resource("mithril", 1) and GameState.bones == before)

func _the_deposit_rule() -> void:
	print("-- Integrity multiplies each trip's yield (ruling 14) --")
	var s := Settlement.new("test", "human", "Test")
	var banked: int = 0
	for i in range(5):
		banked += s.deposit("wood", 1, 0.8)
	_check("five 1-log loads at 80% bank 4 logs (fractions carry)", banked == 4 and s.amount("wood") == 4,
		"%d" % banked)
	_check("at 100% a load banks whole", s.deposit("food", 5, 1.0) == 5)
	_check("a destroyed building (0%) banks nothing", s.deposit("food", 5, 0.0) == 0)

func _a_second_settlement() -> void:
	print("-- A second settlement, owned by the lordship --")
	_check("owned by \"human\", not the villain", _vil.settlement.owner == "human" and not _vil.settlement.is_players())
	_check("eight villagers", _vil.population() == 8, "%d" % _vil.population())
	_check("its stores are its own", _vil.settlement != GameState.player_settlement)
	var before: int = GameState.food
	_vil.settlement.add("food", 5)
	_check("...so filling the village's larder leaves yours alone", GameState.food == before)
	_check("three farmers, two guards, two woodcutters", _vil.staff_of("farmer").size() == 3
		and _vil.staff_of("guard").size() == 2 and _vil.staff_of("woodcutter").size() == 2)
	_check("...and one with no job", _vil.staff_of("").size() == 1)
	var farm: VillageBuilding = _vil.buildings["farm"]
	_check("buildings are named for their first owner (section 5.6)", farm.display_name == "Frank's Farm",
		farm.display_name)
	_check("the Guardhouse holds its guards", _vil.buildings["guardhouse"].staff.size() == 2)
	_check("the mill has no slots -- it is where wood banks", _vil.buildings["mill"].slots == 0
		and _vil.buildings["woodcutter"].bank_point() == _vil.buildings["mill"])

func _it_ticks() -> void:
	print("-- It ticks: the trip loop, walked by villagers --")
	var food0: int = _vil.settlement.amount("food")
	var wood0: int = _vil.settlement.amount("wood")
	var deposits: Array = []
	var conn := func(v, _who, kind: String, carried: int, banked: int): deposits.append([kind, carried, banked])
	EventBus.village_deposited.connect(conn)
	_run_village(240.0)
	EventBus.village_deposited.disconnect(conn)
	var food_trips: int = deposits.filter(func(d): return d[0] == "food").size()
	var wood_trips: int = deposits.filter(func(d): return d[0] == "wood").size()
	_check("farmers walked out, cut, and banked food at the farm", food_trips >= 3 and _vil.settlement.amount("food") > food0,
		"%d trips, %d -> %d" % [food_trips, food0, _vil.settlement.amount("food")])
	_check("woodcutters walked to the treeline and banked at the mill", wood_trips >= 1 and _vil.settlement.amount("wood") > wood0,
		"%d trips, %d -> %d" % [wood_trips, wood0, _vil.settlement.amount("wood")])
	_check("none of it reached the player's stockpile", true)
	var frank: Villager = _named("Frank")
	_check("a farmer's load goes home to the farm", _main.village.labor._home_for(frank) != Vector2.ZERO)

func _integrity_scales_the_mill() -> void:
	print("-- Damage the mill, and every load is worth less --")
	var mill: VillageBuilding = _vil.buildings["mill"]
	mill.damage(0.5)
	var carried: Array = [0]
	var banked: Array = [0]
	var conn := func(_v, _who, kind: String, c: int, b: int):
		if kind == "wood":
			carried[0] += c
			banked[0] += b
	EventBus.village_deposited.connect(conn)
	_run_village(300.0)
	EventBus.village_deposited.disconnect(conn)
	_check("wood still arrives", carried[0] > 0, "%d carried" % carried[0])
	_check("...at half value (±1 for the carried fraction)", absi(banked[0] - carried[0] / 2) <= 1,
		"%d carried, %d banked" % [carried[0], banked[0]])
	_check("the readout says so", _vil.production_readout(_vil.buildings["woodcutter"]).contains("50% integrity"),
		_vil.production_readout(_vil.buildings["woodcutter"]))
	mill.repair(1.0)

func _meals_come_out_of_its_own_stores() -> void:
	print("-- Two meals a day, from the village's own larder --")
	_vil.settlement.set_amount("food", 20)
	var mine: int = GameState.food
	_vil._on_meal(2, "dusk")
	_check("eight villagers ate eight food", _vil.settlement.amount("food") == 12,
		"%d" % _vil.settlement.amount("food"))
	_check("...and none of yours", GameState.food == mine)

# ---------------- Ruling 15: the stance ----------------------------------------

func _the_stance_and_hostiles() -> void:
	print("-- Hidden / Hunting (ruling 15) --")
	var v: Necromancer = _main.villain
	var cs: CombatSystem = _main.combat_system
	_check("he starts Hidden", not v.is_hunting())
	_check("Hidden: no villager is hostile", cs.hostiles().filter(func(h): return h is Villager).is_empty())
	# The escort follows the stance: cast it, hunt, and it goes Aggressive.
	var ws: WorkerSystem = _main.worker_system
	for i in range(2):
		ws.add_worker(Worker.new("Fixture Skeleton #%d" % i))
	_main.undead_command.cast_escort(v)
	var before: int = _main.undead_command.rally_point.stance
	v.set_stance(Necromancer.Stance.HUNTING)
	_check("Hunting: every living villager is fair game", cs.hostiles().filter(func(h): return h is Villager).size() == _vil.population())
	_check("...and the escort went Aggressive", _main.undead_command.rally_point.stance == RallyPoint.Stance.AGGRESSIVE)
	v.set_stance(Necromancer.Stance.HIDDEN)
	_check("Hidden again gives the escort its old stance back", _main.undead_command.rally_point.stance == before)
	_main.undead_command.dismiss()
	_check("the stance is a key, not a button to click in a fight", InputMap.has_action("stance"))

func _hunting_kills_and_the_village_reacts() -> void:
	print("-- Hunting: walk up to a woodcutter, and the village reacts --")
	var v: Necromancer = _main.villain
	var cs: CombatSystem = _main.combat_system
	var hale: Villager = _named("Hale")
	_check("Hale is a woodcutter", hale != null and hale.job == "woodcutter")
	if hale == null:
		return
	# Out on his own, so this measures one man: the others keep their places.
	var alone: Vector2 = _main.world_map.nearest_walkable(_main.world_map.cell_centre_px(Vector2i(112, 47)))
	var anchor_was: Vector2 = hale.idle_anchor
	hale.position = alone
	hale.idle_anchor = alone
	hale.abandon_trip()
	# Hidden, standing on top of him: nothing starts.
	v.place_at(hale.position + Vector2(10, 0))
	cs._process(0.05)
	_check("Hidden: standing next to him starts nothing", not cs.villain_is_engaged())
	# Hunting: walking up to him is the attack.
	var alarms: Array = [0]
	var aconn := func(_vil2, _at: Vector2): alarms[0] += 1
	EventBus.village_alarm.connect(aconn)
	var killed: Array = []
	var kconn := func(_vil2, who, killer): killed.append([who, killer])
	EventBus.villager_killed.connect(kconn)
	v.set_stance(Necromancer.Stance.HUNTING)
	# The guards stay out of *this* fight so it measures one thing; whether they
	# answer an alarm is checked on its own below.
	var reach: float = float(_vil._data.get("alarm_cells", 14.0))
	_vil._data["alarm_cells"] = 0.0
	var hp0: int = v.hp
	for i in range(1200):
		v.place_at(hale.position + Vector2(10, 0))   # he keeps pace with the running man
		cs._process(0.05)
		_vil.labor._process(0.05)
		_vil._process(0.05)
		if hale.dead or hale.downed:
			break
	# **Down, not dead** (LIVING_WORLD L3, 2026-09-27): at 0 hp he lies there
	# bleeding out. Standing over him, the Necromancer finishes him -- which is
	# the kill this block has always measured.
	_check("at 0 hp he went down, not dead (L3)", hale.downed and not hale.dead)
	var downs: Array = _main.captives.downed.filter(func(dd): return dd.person == hale)
	if not downs.is_empty():
		v.place_at(downs[0].position + Vector2(8, 0))
		_main.captives.finish(downs[0], v)
	EventBus.village_alarm.disconnect(aconn)
	EventBus.villager_killed.disconnect(kconn)
	_check("the fight opened and the village raised its alarm", alarms[0] >= 1, "%d" % alarms[0])
	_check("Hale is dead", hale.dead and killed.size() >= 1)
	_check("...and the kill is the Necromancer's", not killed.is_empty() and killed[0][1] == v)
	# Each man lands one real blow before he breaks; after that he only flails.
	_check("a running man does not fight back -- it cost him under half his health", hp0 - v.hp < hp0 / 2,
		"%d -> %d hp" % [hp0, v.hp])
	_check("the deed is on his ledger", v.deeds.any(func(d): return String(d.get("id", d.get("deed", ""))) == "slew_a_villager"))
	var body: WorldSite = _body_of("Hale")
	_check("his body lies where he fell", body != null and body.position.distance_to(hale.position) < 2.0)
	_check("...and the village filled the gap from its spare hand, not from a job above",
		_vil.staff_of("").is_empty() and _vil.buildings["woodcutter"].staff.size() == 2
		and _vil.staff_of("farmer").size() == 3 and _vil.staff_of("guard").size() == 2,
		"%d woodcutters, %d jobless" % [_vil.buildings["woodcutter"].staff.size(), _vil.staff_of("").size()])
	hale.idle_anchor = anchor_was
	# A guard in reach answers the alarm, and is hostile even to a Hidden man.
	_vil._data["alarm_cells"] = reach
	var brom: Villager = _named("Brom")
	var brom_at: Vector2 = brom.position
	_vil.raise_alarm(v.position, v)
	brom.position = v.position + Vector2(3.0 * SettlementGrid.CELL_SIZE, 0)
	v.set_stance(Necromancer.Stance.HIDDEN)
	_check("a guard in reach answers the alarm", _vil.guard_answers_alarm(brom) and _vil.alarm_active())
	_check("...and is hostile even while he is Hidden", cs.hostiles().has(brom))
	_vil._alarm_left = 0.0
	brom.position = brom_at
	v.place_at(_main._throne_world_centre())

## Section 5.3: food > safety > wood. Kill both guards and the spare takes the
## first spear -- and with no spare left, the woodmill gives up the second.
func _the_randy_rule() -> void:
	print("-- The Randy rule: re-staffing changes the job, not the stats --")
	var restaffs: Array = []
	var conn := func(_v, who, from_job: String, to_job: String): restaffs.append([who.villager_name, from_job, to_job])
	EventBus.village_restaffed.connect(conn)
	var brom: Villager = _named("Brom")
	_vil.on_villager_killed(brom, null)
	_check("a guard dies: the woodmill gives up a hand to the spear (safety > wood)",
		restaffs.any(func(r): return r[1] == "woodcutter" and r[2] == "guard"), str(restaffs))
	var randy: Villager = _named("Randy")
	var str_before: int = randy.strength
	var osric: Villager = _named("Osric")
	_vil.on_villager_killed(osric, null)
	EventBus.village_restaffed.disconnect(conn)
	_check("the second guard dies: Randy the Woodcutter becomes Randy (Guard)",
		randy.job == "guard", randy.label())
	_check("...with a woodcutter's arms (same stats)", randy.strength == str_before)
	_check("...untrained, owing the Guardhouse his training", not randy.trained and randy.training_left > 0.0)
	_check("safety outranks wood: the woodmill has nobody now",
		_vil.buildings["woodcutter"].staff.is_empty())
	_check("...and says so: it keeps Randy's name, empty",
		_vil.buildings["woodcutter"].display_name.ends_with("Woodcutter's Hut"))
	var farmers_before: int = _vil.staff_of("farmer").size()
	_check("food is still fully staffed", farmers_before == 3)

func _training() -> void:
	print("-- The Guardhouse trains a replacement --")
	var randy: Villager = _named("Randy")
	var str_before: int = randy.strength
	var trained: Array = [false]
	var conn := func(_v, who): trained[0] = trained[0] or who == randy
	EventBus.village_guard_trained.connect(conn)
	_run_village(_vil.train_seconds() + 120.0)
	EventBus.village_guard_trained.disconnect(conn)
	_check("he walked to the Guardhouse and trained", randy.trained and trained[0])
	_check("...and training is what changed the numbers", randy.strength == str_before + 2)

func _raise_the_body() -> void:
	print("-- A body is a free corpse (ruling C) --")
	var v: Necromancer = _main.villain
	var ws: WorkerSystem = _main.worker_system
	var body: WorldSite = _body_of("Hale")
	if body == null:
		_check("a body to raise", false)
		return
	v.place_at(body.position + Vector2(20, 0))
	var bones: int = GameState.bones
	var before: int = ws.workers.size()
	body._resolve_choice(v, _choice(body, "raise"))
	_check("a skeleton rose from him", ws.workers.size() == before + 1)
	_check("...for free", GameState.bones == bones)
	_check("the body is never Raven-eligible", not body.is_raven_eligible())

# ---------------- Helpers ------------------------------------------------------

func _run_village(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		_vil.labor._process(0.1)
		_vil._process(0.1)
		t += 0.1

func _named(n: String) -> Villager:
	for v in _vil.villagers:
		if v.villager_name == n:
			return v
	return null

func _body_of(n: String) -> WorldSite:
	for s in _main.world_sites.sites:
		if s.display_name == "%s's Body" % n:
			return s
	return null

func _choice(site: WorldSite, id: String) -> Dictionary:
	for c in LootCatalog.choice_sheet(site.choices_id).get("choices", []):
		if String(c.get("id", "")) == id:
			return c
	return {}

func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s   (%s)" % [what, detail])
