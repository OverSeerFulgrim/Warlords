class_name VillageLabor
extends WorkerSystem
## **The village's trip loop is the player's trip loop** (LIVING_WORLD_SPEC
## section 2, ruling 14). This extends WorkerSystem and changes only the four
## things that genuinely differ for a village:
##
## - **Who works** -- the village's living villagers, not a skeleton roster.
## - **What they go for** -- their job (farmer: a field; woodcutter: a tree;
##   no job: sometimes berries), not the player's ranked priority list.
## - **Where they bank** -- their job building's bank point (the woodcutters'
##   logs go to the mill), through its **integrity**.
## - **How they walk** -- around terrain with the shared slide (`Roaming.step`),
##   because a village's fields and treeline are far enough apart to meet a
##   boulder.
##
## Walk out, gather, walk back, deposit: the loop itself is inherited unchanged,
## which is the whole of ruling 14's "keep the worker trip loop".
##
## Guards do not gather. They walk the village's beat, train at the Guardhouse
## until trained, and answer an alarm -- see `_advance_laborer`.

var village = null            # Village (untyped: no load-order dependency)
var world: WorldMap = null

## Chance, each time a jobless villager's idle wait runs out, that he walks out
## for berries instead of pottering by his door (section 5.8).
const FORAGE_CHANCE: float = 0.35
## How close a guard needs to be to the Guardhouse to be trained there.
const TRAIN_RADIUS_PX: float = 40.0

var _beat_index: Dictionary = {}   # Villager -> next beat waypoint

func _ready() -> void:
	# Deliberately NOT super._ready(): the player's priority list and the
	# recruit hooks are the lair's, not the village's.
	set_process(true)

func laborers() -> Array:
	if village == null:
		return []
	return village.living()

func all_units() -> Array:
	return laborers()

func _advance_laborer(w: Laborer, delta: float) -> void:
	var v: Villager = w
	# **A witness runs to tell** (section 8.1) -- nothing else matters to him,
	# and being cast at does not stop him. He tells on arrival.
	if v.is_running_to_tell():
		v.stage = Laborer.TripStage.FLEEING
		if _step_toward(v, v.runner_to, delta):
			if village:
				village.on_runner_arrived(v)
		return
	# A panicked villager keeps running even while something is casting at
	# him -- running is the only thing he is doing. The fight ends when he
	# gets out of reach (CombatSystem's disengage-by-distance rule).
	if v.panicked:
		var refuge: Vector2 = v.idle_anchor if v.idle_anchor != Vector2.ZERO else home_position
		if v.position.distance_to(refuge) > ARRIVE_EPSILON:
			v.stage = Laborer.TripStage.FLEEING
			_step_toward(v, refuge, delta)
			return
		# Home, and cowering. The calm only counts down while nothing is
		# casting at him.
		v.stage = Laborer.TripStage.IDLE
		if not v.in_combat:
			v.calm_left -= delta
			if v.calm_left <= 0.0:
				v.panicked = false
		return
	if v.in_combat:
		return
	if v.is_guard():
		_tick_guard(v, delta)
		return
	super._advance_laborer(v, delta)


# ---------------- Jobs ----------------

func _pick_target_for(w: Laborer) -> ResourceNode:
	var v: Villager = w
	if resource_field == null or not v.can_work_now():
		return null
	match v.job:
		"farmer":
			return _nearest(["crop_field"], v.workplace.position if v.workplace else v.position)
		"woodcutter":
			return _nearest(["tree"], v.position)
		"":
			# **Jobless villagers forage** -- at random, not on a schedule, so a
			# forager on the road is a surprise to both of you.
			if randf() < FORAGE_CHANCE:
				return _nearest(["berry_grove"], v.position)
	return null

## Idle ticks call _pick_target_for every frame; a jobless villager must only
## roll the forage chance when his idle wait runs out, or FORAGE_CHANCE would
## really be "certainly, within a second".
func _tick_idle(w: Laborer, delta: float) -> void:
	var v: Villager = w
	if v.job == "" and v.carrying_amount == 0:
		v.idle_wait -= delta
		if v.idle_wait > 0.0:
			if v.position.distance_to(v.idle_target) > ARRIVE_EPSILON:
				_step_toward(v, v.idle_target, delta, IDLE_SHUFFLE_SCALE)
			return
		var node := _pick_target_for(v)
		if node:
			v.target_node = node
			node.claims += 1
			v.stage = Laborer.TripStage.WALK_TO_NODE
			return
		var r: float = Laborer.IDLE_WANDER_RADIUS
		v.idle_target = v.idle_anchor + Vector2(randf_range(-r, r), randf_range(-r, r))
		v.idle_wait = randf_range(4.0, 9.0)
		return
	super._tick_idle(v, delta)

func _nearest(types: Array, from: Vector2) -> ResourceNode:
	var best: ResourceNode = null
	var best_score: float = INF
	for n in resource_field.nodes:
		if not types.has(n.node_type) or n.is_depleted():
			continue
		var score: float = from.distance_to(n.position) + n.claims * ResourceField.CROWDING_PENALTY_PX
		if score < best_score:
			best_score = score
			best = n
	return best

# ---------------- Guards ----------------

## Training first (at the Guardhouse, for as long as it takes), then the beat.
## An alarm outranks both -- see Village.raise_alarm.
func _tick_guard(v: Villager, delta: float) -> void:
	# A man with a body over his shoulder finishes the carry. One on his way to
	# fetch one drops the errand if the alarm needs him.
	if not v.duty.is_empty():
		if bool(v.duty.get("carrying", false)) or not (village and village.alarm_active() and village.guard_answers_alarm(v)):
			_tick_duty(v, delta)
			return
		village.drop_duty(v)
	if village and village.alarm_active() and village.guard_answers_alarm(v):
		if _step_toward(v, village.alarm_target_position(), delta):
			pass
		village.guard_try_engage(v)
		return
	if not v.trained and v.workplace != null:
		var post: Vector2 = v.workplace.position
		if v.position.distance_to(post) > TRAIN_RADIUS_PX:
			_step_toward(v, post, delta)
			return
		v.training_left -= delta
		if v.training_left <= 0.0:
			v.finish_training()
			if village:
				village.on_guard_trained(v)
		return
	var beat: Array = village.guard_beat if village else []
	if beat.is_empty():
		super._tick_idle(v, delta)
		return
	var i: int = int(_beat_index.get(v, _nearest_beat_index(v, beat)))
	if _step_toward(v, beat[i], delta, 0.8):
		_beat_index[v] = (i + 1) % beat.size()
	else:
		_beat_index[v] = i

## **A guard's errands** (L3): fetch a downed villager home (he comes round
## there), or carry a body to the graveyard (a new grave). Slower with a load.
const CARRY_SPEED_SCALE: float = 0.75

func _tick_duty(v: Villager, delta: float) -> void:
	var kind: String = String(v.duty.get("kind", ""))
	var carrying: bool = bool(v.duty.get("carrying", false))
	v.stage = Laborer.TripStage.WALK_TO_NODE if not carrying else Laborer.TripStage.WALK_HOME
	if kind == "rescue":
		var d = v.duty.get("target")
		var cap = village.captives if village else null
		if cap == null or d == null or not cap.downed.has(d):
			village.drop_duty(v)
			return
		if not carrying:
			if _step_toward(v, d.position, delta):
				cap.pick_up(d, v)
				v.duty["carrying"] = true
				village._set_carry_tag(v, "carrying %s" % String(d.person.villager_name if d.person else d.display_name))
			return
		var home: Vector2 = d.person.idle_anchor if d.person and d.person.idle_anchor != Vector2.ZERO else home_position
		if _step_toward(v, home, delta, CARRY_SPEED_SCALE):
			v.duty = {}
			village._set_carry_tag(v, "")
			cap.revive(d)
		return
	if kind == "bury":
		if not carrying:
			var s = v.duty.get("target")
			if not village._buryable(s):
				village.drop_duty(v)
				return
			if _step_toward(v, s.position, delta):
				village.lift_body(v)
			return
		if not v.duty.has("to"):
			v.duty["to"] = village.next_grave_spot()
		if _step_toward(v, v.duty["to"], delta, CARRY_SPEED_SCALE):
			village.bury(v)
		return
	village.drop_duty(v)

func _nearest_beat_index(v: Villager, beat: Array) -> int:
	var best: int = 0
	var best_d: float = INF
	for i in range(beat.size()):
		var d: float = v.position.distance_to(beat[i])
		if d < best_d:
			best_d = d
			best = i
	return best

# ---------------- Where loads go ----------------

func _home_for(w: Laborer) -> Vector2:
	var v: Villager = w
	if v.carrying_amount > 0 and v.workplace != null:
		return v.workplace.bank_point().position
	if v.idle_anchor != Vector2.ZERO:
		return v.idle_anchor
	return home_position

## Into the village's own stockpile, through the bank point's integrity. A
## jobless forager's berries go into the stores at full value -- he walked them
## to his own kitchen.
func _deposit(w: Laborer) -> void:
	var v: Villager = w
	var integrity: float = 1.0
	var at = null
	if v.workplace != null:
		at = v.workplace.bank_point()
		integrity = at.integrity
	var banked: int = village.settlement.deposit(v.carrying_kind, v.carrying_amount, integrity) if village else 0
	if village:
		village.on_deposit(v, v.carrying_kind, v.carrying_amount, banked, at)

## Around terrain, not through it.
func _step_toward(w: Laborer, target: Vector2, delta: float, speed_scale: float = 1.0) -> bool:
	if w.position.distance_to(target) <= ARRIVE_EPSILON:
		w.position = target
		return true
	w.position = Roaming.step(w.position, target, w.walk_speed_px() * speed_scale, delta, world)
	return w.position.distance_to(target) <= ARRIVE_EPSILON
