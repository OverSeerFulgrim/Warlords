class_name Village
extends Node2D
## **The human village, alive** (LIVING_WORLD_SPEC L0 + L1, built 2026-09-26).
##
## A settlement owned by the lordship: its own stockpile (`Settlement`, ruling
## 13), job buildings with slots and integrity (ruling 14), named villagers who
## walk out to the fields and the treeline and back (`VillageLabor` -- the
## player's trip loop, inherited), guards who walk the rounds, and the one rule
## that makes a village read as *reacting* (section 5.3):
##
## > **food > safety > wood** -- when people are short, the village fills its
## > jobs in that order, and re-staffing changes the job, not the stats.
##
## Kill the guards and a woodcutter takes up a spear (Randy the rule), the mill
## goes quiet on its own, and the Guardhouse starts training him. Nothing is
## scripted: it all falls out of `restaff()`.
##
## **Per-village state lives here, not in an autoload** -- a second village is
## a second instance of this node with its own data file.
##
## Content is `data/village.json`: buildings, people, fields, treeline, beat.

const DATA_PATH := "res://data/village.json"

## Set by Main before build().
var world: WorldMap = null
var world_sites: WorldSites = null
var combat_system: CombatSystem = null
## Who hears a runner's report (L2). Set by Main; may be null.
var witnesses = null
var villain: Necromancer = null
var day_provider: Callable = Callable()

var settlement: Settlement
var display_name: String = "The village"
var buildings: Dictionary = {}     # id -> VillageBuilding
var villagers: Array = []          # every villager ever, dead ones flagged
var field: ResourceField
var labor: VillageLabor
var guard_beat: Array = []         # engine-space waypoints

var _data: Dictionary = {}
var _priority: Array = []          # jobs, highest priority first
var _token_layer: Node2D
var _tokens: Dictionary = {}       # Villager -> WorkerToken
var _sprite_tex: Texture2D = null
var _guard_tex: Texture2D = null

## The alarm (section 8.2's guard row, before witnesses exist): when a villager
## is attacked, guards within reach come for the attacker, and anyone else
## nearby runs home.
var _alarm_left: float = 0.0
var _alarm_at: Vector2 = Vector2.ZERO
var _alarm_target = null

func build(p_world: WorldMap) -> bool:
	world = p_world
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_warning("Village: no %s -- the village stays scenery." % DATA_PATH)
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Village: %s did not parse." % DATA_PATH)
		return false
	_data = parsed
	display_name = String(_data.get("name", "The village"))
	settlement = Settlement.new(String(_data.get("id", "village")), String(_data.get("owner", "human")), display_name)
	for k in _data.get("stock", {}).keys():
		settlement.set_amount(String(k), int(_data["stock"][k]))
	_priority = _data.get("restaff_priority", ["farmer", "guard", "woodcutter"])
	var sp: String = String(_data.get("villager_sprite", ""))
	if sp != "" and ResourceLoader.exists(sp):
		_sprite_tex = load(sp)
	var gp: String = String(_data.get("guard_sprite", sp))
	if gp != "" and ResourceLoader.exists(gp):
		_guard_tex = load(gp)

	_build_buildings()
	_build_field()
	for c in _data.get("guard_beat", []):
		guard_beat.append(_cell_px(c))

	_token_layer = Node2D.new()
	_token_layer.name = "Villagers"
	_token_layer.y_sort_enabled = true
	add_child(_token_layer)

	labor = VillageLabor.new()
	labor.name = "VillageLabor"
	labor.village = self
	labor.world = world
	labor.resource_field = field
	var farm: VillageBuilding = buildings.get("farm")
	labor.home_position = farm.position if farm else Vector2.ZERO
	add_child(labor)

	_spawn_people()
	restaff(true)
	EventBus.dawn_started.connect(_on_meal.bind("dawn"))
	EventBus.dusk_started.connect(_on_meal.bind("dusk"))
	EventBus.villager_attacked.connect(_on_villager_attacked)
	return true

func _cell_px(c) -> Vector2:
	return world.cell_centre_px(Vector2i(int(c[0]), int(c[1]))) if world else Vector2(c[0], c[1]) * 64.0

func _build_buildings() -> void:
	for entry in _data.get("buildings", []):
		var b := VillageBuilding.new()
		b.setup(entry, _cell_px(entry.get("cell", [0, 0])))
		b.village = self
		add_child(b)
		buildings[b.building_id] = b
	for entry in _data.get("buildings", []):
		if entry.has("banks_at") and buildings.has(String(entry["banks_at"])):
			buildings[String(entry["id"])].banks_at = buildings[String(entry["banks_at"])]

func _build_field() -> void:
	field = ResourceField.new()
	field.name = "VillageField"
	field.y_sort_enabled = true
	field.world = world
	field.spawns_deer = false
	add_child(field)
	var art: Dictionary = _data.get("node_art", {})
	for c in _data.get("fields", []):
		field.add_node(ResourceNode.make_crop_field(_cell_px(c)),
			String(art.get("crop", "")), String(art.get("crop_cut", "")), 40.0, 30.0)
	for c in _data.get("treeline", []):
		field.add_node(ResourceNode.make_tree(_cell_px(c)),
			ResourceField.SPRITE_TREE, ResourceField.SPRITE_STUMP,
			ResourceField.NODE_SIZE_TREE, ResourceField.NODE_SIZE_STUMP)
	for c in _data.get("forage", []):
		field.add_node(ResourceNode.make_berry_grove(_cell_px(c)),
			ResourceField.SPRITE_BERRY, ResourceField.SPRITE_BERRY_PICKED,
			ResourceField.NODE_SIZE_GROVE)

func _spawn_people() -> void:
	var houses: Array = []
	if world_sites:
		for id in _data.get("houses", []):
			for s in world_sites.sites:
				if s.site_id == String(id):
					houses.append(s)
	var i: int = 0
	for entry in _data.get("people", []):
		var v := Villager.new(String(entry.get("name", "Villager")), String(entry.get("job", "")))
		if bool(entry.get("trained", false)):
			v.finish_training()
		if not houses.is_empty():
			v.house = houses[i % houses.size()]
			v.idle_anchor = world.nearest_walkable(v.house.position + Vector2(0, 26)) if world else v.house.position
		else:
			v.idle_anchor = labor.home_position
		v.position = v.idle_anchor
		v.idle_target = v.idle_anchor
		villagers.append(v)
		settlement.followers.append(v)
		_spawn_token(v)
		i += 1

func _spawn_token(v: Villager) -> void:
	var token := WorkerToken.new()
	_token_layer.add_child(token)
	token.setup(v, _guard_tex if v.is_guard() and _guard_tex else _sprite_tex)
	_tokens[v] = token

func _refresh_token(v: Villager) -> void:
	var token: WorkerToken = _tokens.get(v)
	if token == null:
		return
	_set_bang(v, v.is_running_to_tell())
	var tex: Texture2D = _guard_tex if v.is_guard() and _guard_tex else _sprite_tex
	if tex and token.sprite.texture != tex:
		token.setup(v, tex)

# ---------------- Queries ----------------

func living() -> Array:
	return villagers.filter(func(v): return not v.dead and v.is_alive())

func population() -> int:
	return living().size()

func train_seconds() -> float:
	return float(_data.get("train_seconds", 90.0))

func staff_of(job: String) -> Array:
	return living().filter(func(v): return v.job == job)

## The section 5.2 formula, as a **readout** of what the trip loop is doing
## (ruling 14) -- never used to compute income.
func production_readout(b: VillageBuilding) -> String:
	if b.slots <= 0:
		return "banks at %d%%" % int(round(b.integrity * 100.0))
	var staffed: float = float(b.staff.size()) / float(maxi(1, b.slots))
	var bank: VillageBuilding = b.bank_point()
	return "%d%% staffed × %d%% integrity = %d%%" % [
		int(round(staffed * 100.0)), int(round(bank.integrity * 100.0)),
		int(round(staffed * bank.integrity * 100.0))]

## For CombatSystem.hostiles(): who would fight him or his right now. Guards
## answering an alarm always; everyone, when he is Hunting (ruling 15).
func hostile_villagers(hunting: bool) -> Array:
	var out: Array = []
	for v in living():
		if hunting or (v.is_guard() and alarm_active() and guard_answers_alarm(v)):
			out.append(v)
	return out

## Click picking: a villager first, then a building, then a field node.
func pick_at(pos: Vector2):
	var best = null
	var best_d: float = INF
	for v in living():
		var token: WorkerToken = _tokens.get(v)
		if token == null:
			continue
		var d: float = v.position.distance_to(pos)
		if d <= token.hit_radius() and d < best_d:
			best_d = d
			best = v
	if best:
		return best
	for b in buildings.values():
		if b.hit_centre().distance_to(pos) <= b.hit_radius():
			return b
	return field.node_at(pos) if field else null

# ---------------- Re-staffing (section 5.3) ----------------

## Fills the job slots in priority order from whoever is alive.
##
## 1. Everyone already in a job keeps it, up to the slot count.
## 2. Empty slots are filled **first from the jobless, then from the lowest-
##    priority job** -- never from a higher one. That single rule is the whole
##    of "kill the guards and the village pulls a woodcutter in to hold a
##    spear".
## 3. A villager moved into the guard keeps his own stats (the Randy rule) and
##    owes the Guardhouse his training.
func restaff(initial: bool = false) -> void:
	var alive: Array = living()
	var by_job: Dictionary = {}
	for job in _priority:
		by_job[job] = []
	var spare: Array = []
	for v in alive:
		if by_job.has(v.job):
			by_job[v.job].append(v)
		else:
			spare.append(v)
	# Trim any job over its slots (a building lost capacity) back to the spare pool.
	for job in _priority:
		var b: VillageBuilding = _building_for_job(job)
		var cap: int = b.slots if b else 0
		while by_job[job].size() > cap:
			spare.append(by_job[job].pop_back())
	var changes: Array = []
	for job in _priority:
		var b: VillageBuilding = _building_for_job(job)
		if b == null:
			continue
		while by_job[job].size() < b.slots:
			var pick = null
			if not spare.is_empty():
				pick = spare.pop_front()
			else:
				# Lowest priority first, and only from jobs *below* this one.
				var my_rank: int = _priority.find(job)
				for k in range(_priority.size() - 1, my_rank, -1):
					var lower: String = _priority[k]
					if not by_job[lower].is_empty():
						pick = by_job[lower].pop_back()
						break
			if pick == null:
				break
			var was: String = pick.job
			pick.assign(job, b, train_seconds())
			by_job[job].append(pick)
			if not initial and was != job:
				changes.append([pick, was, job])
	for v in spare:
		if v.job != "":
			var was: String = v.job
			v.assign("", null, 0.0)
			if not initial:
				changes.append([v, was, ""])
	# Staff lists, owner names, sprites.
	for b in buildings.values():
		b.staff.clear()
	for job in _priority:
		var b: VillageBuilding = _building_for_job(job)
		if b == null:
			continue
		for v in by_job[job]:
			v.workplace = b
			b.staff.append(v)
			b.claim_name(v.villager_name)
	for v in alive:
		_refresh_token(v)
	for c in changes:
		EventBus.village_restaffed.emit(self, c[0], c[1], c[2])

func _building_for_job(job: String) -> VillageBuilding:
	for b in buildings.values():
		if b.job == job:
			return b
	return null

func on_guard_trained(v: Villager) -> void:
	EventBus.village_guard_trained.emit(self, v)

func on_deposit(v: Villager, kind: String, carried: int, banked: int, at) -> void:
	EventBus.village_deposited.emit(self, v, kind, carried, banked)

# ---------------- Meals and repairs ----------------

## Two meals a day, one food each, from the village's own stores -- the same
## clock the player's recruits eat on. At dawn a damaged building is patched
## with the village's own wood (section 5.2: "repaired, costs their wood").
func _on_meal(_day: int, phase: String) -> void:
	var need: int = population()
	var have: int = settlement.amount("food")
	var eaten: int = mini(need, have)
	settlement.spend("food", eaten)
	if eaten < need:
		EventBus.village_hungry.emit(self, need - eaten)
	if phase == "dawn":
		for b in buildings.values():
			if b.integrity < 1.0 and settlement.spend("wood", int(_data.get("repair_wood", 2))):
				b.repair(float(_data.get("repair_step", 0.25)))

# ---------------- Witnesses (section 8.1) ----------------

## A "!" over the token while he runs to tell. A Label, so it needs no art.
func _set_bang(v: Villager, on: bool) -> void:
	var token: WorkerToken = _tokens.get(v)
	if token == null:
		return
	var bang: Label = token.get_node_or_null("Bang")
	if on and bang == null:
		bang = Label.new()
		bang.name = "Bang"
		bang.text = "!"
		bang.add_theme_font_size_override("font_size", 22)
		bang.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25))
		bang.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		bang.add_theme_constant_override("outline_size", 5)
		bang.position = Vector2(-5, -WorkerToken.SPRITE_TARGET_SIZE - 34.0)
		token.add_child(bang)
	elif not on and bang != null:
		bang.queue_free()

func _process_bangs() -> void:
	for v in living():
		var token: WorkerToken = _tokens.get(v)
		if token == null:
			continue
		var has: bool = token.get_node_or_null("Bang") != null
		if has != v.is_running_to_tell():
			_set_bang(v, v.is_running_to_tell())

## He got there. The report lands now -- standing drops, threat rises -- and he
## goes home, spent.
func on_runner_arrived(v: Villager) -> void:
	var report: Dictionary = v.report
	var where: String = "the Guardhouse"
	if witnesses and witnesses.guild and v.runner_to.distance_to(witnesses.guild.position) < 4.0:
		where = witnesses.guild.display_name
	v.runner_to = Vector2.ZERO
	v.report = {}
	v.panicked = true
	v.calm_left = Villager.CALM_SECONDS
	_set_bang(v, false)
	if witnesses:
		witnesses.arrive(report, where)
	EventBus.report_arrived.emit(report.get("villain"), v, String(report.get("act", "")), where)

# ---------------- Death ----------------

## A villager died. The village reads its loss (his building keeps his name,
## empty), fills the gap by priority, and leaves a body where he fell -- a
## body the Necromancer can raise, search or hide (the grave sheet's grammar).
func on_villager_killed(v: Villager, killer) -> void:
	if v.dead:
		return
	v.dead = true
	v.abandon_trip()
	settlement.followers.erase(v)
	var token: WorkerToken = _tokens.get(v)
	if token:
		token.queue_free()
	_tokens.erase(v)
	var at: Vector2 = v.position
	if world_sites:
		world_sites.spawn_body(at, v.villager_name)
	if killer != null and killer is Necromancer:
		var band: int = int(world.band_at(at).get("band", 2)) if world else 2
		killer.record_deed("slew_a_villager", {"cruelty": 1}, _day(), band)
	EventBus.villager_killed.emit(self, v, killer)
	restaff()

func _day() -> int:
	return int(day_provider.call()) if day_provider.is_valid() else 1

# ---------------- The alarm ----------------

func _on_villager_attacked(v, by) -> void:
	if not villagers.has(v):
		return
	raise_alarm(v.position, by)

func raise_alarm(at: Vector2, attacker) -> void:
	var fresh: bool = _alarm_left <= 0.0
	_alarm_at = at
	_alarm_target = attacker
	_alarm_left = float(_data.get("alarm_seconds", 30.0))
	var panic_px: float = float(_data.get("panic_cells", 6.0)) * float(SettlementGrid.CELL_SIZE)
	for v in living():
		if v.is_guard() or v.in_combat or v.panicked or v.is_running_to_tell():
			continue
		if v.position.distance_to(at) <= panic_px:
			v.depart("fled the fighting")
	if fresh:
		EventBus.village_alarm.emit(self, at)

func alarm_active() -> bool:
	return _alarm_left > 0.0 and _alarm_target != null and is_instance_valid(_alarm_target) \
		and _alarm_target.is_alive()

func alarm_target_position() -> Vector2:
	return _alarm_target.position if alarm_active() else _alarm_at

func guard_answers_alarm(v: Villager) -> bool:
	var reach: float = float(_data.get("alarm_cells", 14.0)) * float(SettlementGrid.CELL_SIZE)
	return v.position.distance_to(_alarm_at) <= reach or v.in_combat

## A guard who has reached the man the alarm is about opens a fight with him --
## guard in the attacker slot, like every other thing that fights him.
func guard_try_engage(v: Villager) -> void:
	if combat_system == null or not alarm_active() or v.in_combat:
		return
	if v.position.distance_to(_alarm_target.position) <= CombatSystem.VILLAIN_ENGAGE_PX:
		combat_system.engage(v, _alarm_target)

func _process(delta: float) -> void:
	if _alarm_left > 0.0:
		_alarm_left -= delta
	_process_bangs()
