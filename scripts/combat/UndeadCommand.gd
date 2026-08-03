extends Node
class_name UndeadCommand
## **Command Undead** — the Necromancer's first spell, and the player's only
## direct lever over a unit's movement.
##
## Casting it plants a `RallyPoint`. Every undead labourer drops what it is
## carrying and marches there, then follows the point's order (Defend / Patrol /
## Attack) until the spell is dismissed. See RallyPoint's header for why this
## does not break the indirect-control pillar: the dead have no will to
## override, which is the whole difference between a skeleton and a recruit.
##
## **The cost is the economy.** Bound undead leave the labor pool entirely --
## they are soldiers now, not workers, and the priority list stops seeing them.
## That is the decision the spell exists to pose: the dead can dig or they can
## fight, not both. With one starting skeleton it is a total shutdown; with six
## it is a real allocation question, which is where it starts being interesting.
##
## No resource cost yet. Dark Essence is the obvious candidate and it is locked
## at 0 for the whole foundation build, so charging for this now would mean the
## spell could never be cast. Revisit when Stage 4 unlocks the essence loop.
##
## Scope note: this deliberately commands **all** undead rather than a chosen
## subset. Picking which skeletons to send is a selection UI, and a selection UI
## is the per-unit control the pillar rules out. One spell, all the dead, one
## point.

## How close counts as "arrived at the rally point".
const ARRIVE_EPSILON: float = 8.0

## How close an undead has to be to a hostile before it starts swinging. Matches
## the wolf's own engage range so neither side gets a free approach.
const ENGAGE_RADIUS_PX: float = 26.0

## Patrol pacing: how long they hold at each point on the beat.
const PATROL_PAUSE_MIN: float = 1.5
const PATROL_PAUSE_MAX: float = 4.0

# ---------------- Wiring (set by Main, same convention as the other systems) --
var settlement: SettlementGrid = null
var worker_system: WorkerSystem = null
var combat_system: CombatSystem = null

var rally_point: RallyPoint = null

## Per-unit patrol bookkeeping, keyed by Laborer. Kept here rather than as
## fields on Laborer because it is meaningless to a unit that isn't bound, and
## Laborer is already carrying more state than it wants to.
var _patrol_targets: Dictionary = {}
var _patrol_waits: Dictionary = {}

func _ready() -> void:
	set_process(true)

# ---------------- Casting ----------------

func is_active() -> bool:
	return rally_point != null and is_instance_valid(rally_point)

## Casts (or moves) the rally point. Returns the number of undead bound to it.
func cast(at: Vector2, order: int = RallyPoint.Order.DEFEND) -> int:
	if not is_active():
		rally_point = RallyPoint.new()
		rally_point.name = "RallyPoint"
		settlement.add_child(rally_point)
	rally_point.position = at
	rally_point.order = order
	var bound: int = _bind_all()
	EventBus.undead_commanded.emit(at, RallyPoint.order_name(order), bound)
	return bound

func set_order(order: int) -> void:
	if not is_active():
		return
	rally_point.order = order
	# Drop every patrol target: a beat walked under the old order is the wrong
	# beat under the new one.
	_patrol_targets.clear()
	_patrol_waits.clear()
	EventBus.undead_commanded.emit(rally_point.position, RallyPoint.order_name(order), rally_point.bound_count)

## Releases the dead back to the priority list.
func dismiss() -> void:
	if not is_active():
		return
	for u in _undead():
		u.rallied = false
	_patrol_targets.clear()
	_patrol_waits.clear()
	rally_point.queue_free()
	rally_point = null
	EventBus.undead_dismissed.emit()

func _bind_all() -> int:
	var n: int = 0
	for u in _undead():
		if not u.rallied:
			u.rallied = true
			# They are soldiers now. Anything half-carried is dropped where they
			# stand -- abandon_trip also releases the claim on the node so a
			# living recruit can pick the job up.
			u.abandon_trip()
			u.carrying_amount = 0
			u.carrying_kind = ""
		n += 1
	return n

## Every undead unit on the roster, bound or not. Reads `is_undead()`, which
## reads races.json's `alignment` -- so a future ghoul or wraith recruit is
## commandable the day it exists, with no change here.
func _undead() -> Array:
	if worker_system == null:
		return []
	var out: Array = []
	for u in worker_system.all_units():
		if u.is_undead():
			out.append(u)
	return out

# ---------------- Driving the bound ----------------

func _process(delta: float) -> void:
	if not is_active():
		return
	# Newly raised skeletons fall in automatically -- the spell is a standing
	# order on the dead, not on the individuals who happened to be present.
	var bound: Array = []
	for u in _undead():
		if not u.rallied:
			u.rallied = true
			u.abandon_trip()
		bound.append(u)
	rally_point.bound_count = bound.size()

	for u in bound:
		if u.in_combat or not u.is_alive():
			continue
		_advance_bound(u, delta)

func _advance_bound(u, delta: float) -> void:
	var hostile = _hostile_for(u)
	if hostile != null:
		if u.position.distance_to(hostile.position) <= ENGAGE_RADIUS_PX:
			if combat_system:
				combat_system.engage(hostile, u)
			return
		u.position = Roaming.step(u.position, hostile.position, u.walk_speed_px(), delta)
		return

	match rally_point.order:
		RallyPoint.Order.PATROL:
			_walk_beat(u, delta)
		_:
			# Defend and Attack both idle *at* the point when there's nothing to
			# fight; the difference between them is only how far they'll go for
			# a hostile, which _hostile_for() above already applied.
			if u.position.distance_to(rally_point.position) > ARRIVE_EPSILON:
				u.position = Roaming.step(u.position, rally_point.position, u.walk_speed_px(), delta)

## The nearest hostile this unit is allowed to go after, given the order's
## radius. Measured from the **rally point**, not from the unit -- otherwise a
## skeleton that chased something to the edge of its leash could then measure
## from its new position and keep going forever.
func _hostile_for(u):
	if combat_system == null:
		return null
	var limit: float = rally_point.radius_for_order()
	var best = null
	var best_dist: float = INF
	for wolf in combat_system.wolves:
		if not is_instance_valid(wolf) or not wolf.is_alive():
			continue
		if wolf.state == Wolf.State.LEAVING:
			continue  # let a beaten or fed wolf go; chasing it off the map is pointless
		if rally_point.position.distance_to(wolf.position) > limit:
			continue
		var d: float = u.position.distance_to(wolf.position)
		if d < best_dist:
			best_dist = d
			best = wolf
	return best

func _walk_beat(u, delta: float) -> void:
	var wait: float = _patrol_waits.get(u, 0.0)
	if wait > 0.0:
		_patrol_waits[u] = wait - delta
		return
	var target: Vector2 = _patrol_targets.get(u, Vector2.INF)
	if target == Vector2.INF or Roaming.arrived(u.position, target, ARRIVE_EPSILON):
		var r: float = RallyPoint.PATROL_RADIUS_PX
		# Even over the disc rather than uniform in radius, so the beat doesn't
		# bunch up around the marker -- same sqrt trick NecromancerToken uses.
		var angle: float = randf() * TAU
		var dist: float = sqrt(randf()) * r
		_patrol_targets[u] = rally_point.position + Vector2(cos(angle), sin(angle)) * dist
		_patrol_waits[u] = randf_range(PATROL_PAUSE_MIN, PATROL_PAUSE_MAX)
		return
	u.position = Roaming.step(u.position, target, u.walk_speed_px(), delta)
