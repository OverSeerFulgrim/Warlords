extends Node
class_name WorkerSystem
## Owns the Worker roster, the global priority list, and the per-worker trip
## loop that replaced the old flat gather tick.
##
## **What this used to be:** every `gather_interval` (4s), each worker added +1
## of whatever resource they were individually assigned to, regardless of
## distance, skill, or whether the map had any of it left. Position was
## decorative -- WorkerToken glided around on a separate clock that produced
## nothing (its own header called that out as an honest simplification).
##
## **What it is now** (FOUNDATION_SPEC section 6): each worker runs a real
## round trip --
##
##     pick target -> walk there -> gather until carry-full or node empty ->
##     walk home -> deposit -> repeat
##
## and the resource only enters GameState at the deposit step. Three things
## fall out of that, all of them intended:
##   - **Distance is a cost.** A far forest is genuinely slower than a near
##     one, and the round trip is dead time you're paying for.
##   - **Skill is visible as speed**, not as a permission. Gather time per
##     unit is `4.0s * 5 / skill` (ResourceNode.action_time_for_skill), so a
##     Skeleton's Woodcutting 3 takes ~6.7s per log where a human peasant's 5
##     takes exactly 4s -- deliberately matching the old flat tick, so the
##     overall pacing of the early game survives the rewrite.
##   - **Carry capacity = Might** decides trip length. A Might-4 skeleton
##     hauls 4 units and walks back; a future Ogre would haul 9.
##
## The one carry-capacity exception is a deer: `yield_per_action` 8 in one
## kill, hauled home whole (see ResourceNode.make_deer's comment for why).
##
## Assignment is **global and player-set, not per-worker**: see the priority
## list below. There are no per-worker orders any more -- that was the old
## cycle-button UI, and GAME_OUTLINE Stage 1 explicitly calls for a ranked
## list with thresholds instead.

const RECRUIT_COST := {"bones": 5}

## How close (px) counts as "arrived". Generous enough that a worker never
## jitters past a moving deer, tight enough to look like they're standing on
## the node.
const ARRIVE_EPSILON: float = 6.0

## Idle wandering runs at a fraction of walking pace so "milling about with
## nothing to do" reads differently from "on a job".
const IDLE_SHUFFLE_SCALE: float = 0.6

## Order matters -- this is the *default* ranking, top priority first. The
## player reorders it and edits thresholds through the bottom-bar UI (see
## Main._build_priority_rows). Wood first because the first thing the player
## needs is a Bone Pile and then a Workshop; Bones last because the starting
## 10 already covers two extra workers.
##
## Threshold semantics (GAME_OUTLINE Stage 1's fall-through rule): workers
## serve the highest-priority resource whose **stock is below** its threshold.
## Once stock >= threshold that entry is satisfied and they fall through to the
## next one -- and they come straight back the moment spending dips it under
## again. All four satisfied (or nothing left on the map to gather) = workers
## idle at the keep.
const DEFAULT_PRIORITIES := [
	{"kind": "wood", "threshold": 30},
	{"kind": "stone", "threshold": 20},
	{"kind": "food", "threshold": 20},
	{"kind": "bones", "threshold": 15},
]

var workers: Array = []      # Array[Worker]
var priorities: Array = []   # Array[{kind: String, threshold: int}], ranked

## Set by Main after construction, same wiring convention as
## event_system.settlement / threat_system.settlement.
var resource_field: ResourceField = null
var home_position: Vector2 = Vector2.ZERO

## Idle wander area around the keep -- workers with nothing to do mill about
## here instead of standing in a stack on the throne.
var keep_zone: Rect2 = Rect2()

func _ready() -> void:
	for entry in DEFAULT_PRIORITIES:
		priorities.append(entry.duplicate())
	# Recruits join the labor pool the moment they arrive. They need a starting
	# position before the trip loop touches them, or they'd walk to their first
	# node from the world origin.
	EventBus.follower_recruited.connect(_place_at_home)
	set_process(true)

func _process(delta: float) -> void:
	for l in laborers():
		_advance_laborer(l, delta)

## Everyone who can currently work: the Skeleton Worker roster plus every
## follower who isn't away on a bounty or mission.
##
## **This is the point of recruiting.** A settled Gray Dwarf brings Mining 9
## against a skeleton's 3, so the same trip yields stone roughly three times
## faster (`4.0s * 5 / skill`), and their higher Might means a bigger load per
## round trip on top. Workers and Followers stay separate classes -- see
## Laborer.gd for where that line is drawn -- they just share the job.
func laborers() -> Array:
	var out: Array = workers.duplicate()
	for f in GameState.followers:
		if f.can_labor():
			out.append(f)
		elif f.stage != Laborer.TripStage.IDLE:
			# Pulled onto a bounty mid-trip: drop the job and release the node
			# rather than leaving a phantom claim on it forever.
			f.abandon_trip()
	return out

func _place_at_home(l) -> void:
	l.position = home_position
	l.idle_target = home_position

# ---------------- The trip loop ----------------

func _advance_laborer(w: Laborer, delta: float) -> void:
	match w.stage:
		Laborer.TripStage.IDLE:
			_tick_idle(w, delta)
		Laborer.TripStage.WALK_TO_NODE:
			_tick_walk_to_node(w, delta)
		Laborer.TripStage.GATHERING:
			_tick_gathering(w, delta)
		Laborer.TripStage.WALK_HOME:
			_tick_walk_home(w, delta)

## Idle workers re-check the priority list every frame -- cheap (four
## comparisons against GameState) and it means a threshold edit or a bit of
## spending puts them back to work immediately rather than on some poll timer.
## While there's genuinely nothing to do they wander the keep zone.
func _tick_idle(w: Laborer, delta: float) -> void:
	var node := _pick_target_for(w)
	if node:
		w.target_node = node
		node.claims += 1
		w.stage = Laborer.TripStage.WALK_TO_NODE
		return
	# Nothing worth doing: amble.
	w.idle_wait -= delta
	if w.idle_wait <= 0.0 and keep_zone.size != Vector2.ZERO:
		w.idle_target = Vector2(
			randf_range(keep_zone.position.x, keep_zone.position.x + keep_zone.size.x),
			randf_range(keep_zone.position.y, keep_zone.position.y + keep_zone.size.y)
		)
		w.idle_wait = randf_range(2.0, 5.0)
	if w.position.distance_to(w.idle_target) > ARRIVE_EPSILON:
		_step_toward(w, w.idle_target, delta, IDLE_SHUFFLE_SCALE)  # a shuffle, not a march

func _tick_walk_to_node(w: Laborer, delta: float) -> void:
	if w.target_node == null or w.target_node.is_depleted():
		# Someone else finished it off, or it was a deer that got hunted first.
		w.abandon_trip()
		return
	# Re-reads the node's position every frame rather than caching a
	# destination, which is what makes chasing a roaming deer work with no
	# special-case pursuit code.
	if _step_toward(w, w.target_node.position, delta):
		w.target_node.freeze(true)  # a hunted deer holds still; no-op otherwise
		w.stage = Laborer.TripStage.GATHERING
		w.gather_timer = 0.0
		w.gather_action_target = w.target_node.action_time_for_skill(w.skill_for(w.target_node.skill_key))

func _tick_gathering(w: Laborer, delta: float) -> void:
	var node = w.target_node
	if node == null or node.is_depleted():
		_head_home_or_idle(w)
		return
	w.gather_timer += delta
	if w.gather_timer < w.gather_action_target:
		return
	# One action completed. Take what's left of a full yield, but never more
	# than the worker can still carry -- except a deer, which is all-or-nothing
	# by design (see ResourceNode.make_deer).
	w.gather_timer -= w.gather_action_target
	var room: int = w.carry_capacity() - w.carrying_amount
	var want: int = node.yield_per_action
	if node.node_type != "deer":
		want = min(want, room)
	var taken: int = node.take(want)
	if taken > 0:
		w.carrying_kind = node.kind
		w.carrying_amount += taken
	# Recompute for the next action -- the node may have changed state, and a
	# depleted node ends the visit regardless.
	if node.is_depleted() or w.is_carrying_full():
		_head_home_or_idle(w)
	else:
		w.gather_action_target = node.action_time_for_skill(w.skill_for(node.skill_key))

## Ends the visit: release the claim, then walk home if there's anything worth
## depositing, or go straight back to idle if the trip came up empty (node
## died before the first action completed).
func _head_home_or_idle(w: Laborer) -> void:
	if w.target_node:
		w.target_node.claims = max(0, w.target_node.claims - 1)
		w.target_node.freeze(false)
		w.target_node = null
	if w.carrying_amount > 0:
		w.stage = Laborer.TripStage.WALK_HOME
	else:
		w.stage = Laborer.TripStage.IDLE
		w.gather_timer = 0.0

func _tick_walk_home(w: Laborer, delta: float) -> void:
	if not _step_toward(w, home_position, delta):
		return
	# Deposit -- the only place gathered resources enter GameState.
	if w.carrying_amount > 0:
		GameState.add_resource(w.carrying_kind, w.carrying_amount)
		EventBus.worker_deposited.emit(w, w.carrying_kind, w.carrying_amount)
	w.carrying_amount = 0
	w.carrying_kind = ""
	w.stage = Laborer.TripStage.IDLE
	w.idle_wait = 0.0

## Moves a worker toward `target` at their racial walk speed. Returns true on
## arrival. `speed_scale` lets the idle shuffle reuse the same movement code at
## a slower pace.
func _step_toward(w: Laborer, target: Vector2, delta: float, speed_scale: float = 1.0) -> bool:
	var to_target: Vector2 = target - w.position
	var step: float = w.walk_speed_px() * speed_scale * delta
	if to_target.length() <= max(step, ARRIVE_EPSILON):
		w.position = target
		return true
	w.position += to_target.normalized() * step
	return false

# ---------------- Priority list ----------------

## The fall-through rule. Walks the ranked list top-down and returns a node for
## the first entry that is both **under threshold** and **actually available on
## the map**; null if nothing qualifies.
##
## The availability check matters as much as the threshold one: without it, a
## forest chopped down to stumps would park every worker on "wood" forever
## while stone and food sat unharvested. Running out of a resource has to fall
## through exactly like satisfying it does.
func _pick_target_for(w: Laborer) -> ResourceNode:
	if resource_field == null:
		return null
	for entry in priorities:
		var kind: String = entry["kind"]
		if _stock_of(kind) >= int(entry["threshold"]):
			continue
		var node := resource_field.find_best_node(kind, w.position)
		if node:
			return node
	return null

func _stock_of(kind: String) -> int:
	match kind:
		"wood":
			return GameState.wood
		"stone":
			return GameState.stone
		"food":
			return GameState.food
		"bones":
			return GameState.bones
		_:
			return 0

## True if this entry is currently being served (under threshold and the map
## still has some) -- drives the "Working" / "Satisfied" / "Depleted" label on
## each priority row.
func priority_status(kind: String) -> String:
	var entry := _entry_for(kind)
	if entry.is_empty():
		return ""
	if _stock_of(kind) >= int(entry["threshold"]):
		return "Satisfied"
	if resource_field and not resource_field.has_available(kind):
		return "None left"
	return "Working"

func _entry_for(kind: String) -> Dictionary:
	for entry in priorities:
		if entry["kind"] == kind:
			return entry
	return {}

func set_threshold(kind: String, value: int) -> void:
	var entry := _entry_for(kind)
	if entry.is_empty():
		return
	entry["threshold"] = max(0, value)
	_rethink_all()
	EventBus.priorities_changed.emit()

## Moves an entry up (-1) or down (+1) the ranking.
func move_priority(kind: String, direction: int) -> void:
	for i in range(priorities.size()):
		if priorities[i]["kind"] != kind:
			continue
		var target: int = clampi(i + direction, 0, priorities.size() - 1)
		if target == i:
			return
		var entry = priorities[i]
		priorities.remove_at(i)
		priorities.insert(target, entry)
		_rethink_all()
		EventBus.priorities_changed.emit()
		return

## After a priority change, any worker still *walking to* a node may now be
## heading to the wrong job -- drop those trips so they re-pick immediately.
## Workers already gathering or hauling are left alone on purpose: abandoning a
## half-dug grave or dumping a carried load to chase a reshuffled list would
## waste work the player already paid for, and it looks like a bug.
func _rethink_all() -> void:
	for w in workers:
		if w.stage == Laborer.TripStage.WALK_TO_NODE:
			w.abandon_trip()

# ---------------- Roster ----------------

## Adds a Worker directly, no cost -- used for the free starting laborer.
## Player-recruited workers go through recruit_worker() instead.
func add_worker(worker: Worker) -> void:
	worker.position = home_position
	worker.idle_target = home_position
	workers.append(worker)
	EventBus.worker_count_changed.emit(workers.size())

## Player-facing recruitment: costs RECRUIT_COST, returns null (and spends
## nothing) if unaffordable.
func recruit_worker(worker_name: String) -> Worker:
	if not GameState.can_afford_cost(RECRUIT_COST):
		return null
	for kind in RECRUIT_COST.keys():
		if not GameState.spend_resource(kind, RECRUIT_COST[kind]):
			push_warning("WorkerSystem: spend_resource('%s') failed after can_afford_cost passed." % kind)
			return null
	var w := Worker.new(worker_name)
	add_worker(w)
	return w

func idle_workers() -> Array:
	return workers.filter(func(w): return w.stage == Laborer.TripStage.IDLE)

## One-line census for the HUD, e.g. "3 hands: 2 gathering, 1 hauling".
## Counts the whole labor pool -- skeletons and working recruits alike -- since
## that's what the priority list is actually commanding.
func workforce_summary() -> String:
	var pool := laborers()
	if pool.is_empty():
		return "No one working"
	var counts := {"idle": 0, "walking": 0, "gathering": 0, "hauling": 0}
	for w in pool:
		match w.stage:
			Laborer.TripStage.WALK_TO_NODE:
				counts["walking"] += 1
			Laborer.TripStage.GATHERING:
				counts["gathering"] += 1
			Laborer.TripStage.WALK_HOME:
				counts["hauling"] += 1
			_:
				counts["idle"] += 1
	var parts: Array = []
	for key in ["gathering", "hauling", "walking", "idle"]:
		if counts[key] > 0:
			parts.append("%d %s" % [counts[key], key])
	var recruits: int = pool.size() - workers.size()
	var who := "%d worker%s" % [workers.size(), "" if workers.size() == 1 else "s"]
	if recruits > 0:
		who += " + %d recruit%s" % [recruits, "" if recruits == 1 else "s"]
	return "%s: %s" % [who, ", ".join(parts)]
