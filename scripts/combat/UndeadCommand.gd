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
## fight, not both. With one skeleton it is a total shutdown; with six
## it is a real allocation question, which is where it starts being interesting.
##
## No resource cost yet. Dark Essence is the obvious candidate; when this was
## written it was locked at 0 for the whole foundation build, so charging for it
## would have meant the spell could never be cast. It is field loot now
## (LOOT_SITES_SPEC section 5), but the cost has not been revisited.
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
## The terrain the bound walk over. Handed in like everywhere else, and passed
## straight through to `Roaming.step()` -- which the bound units were **not**
## doing before R2d, so a skeleton marching to the point walked through cliffs
## while the wolf chasing it went around. Predator, prey, worker and escort now
## all round a boulder the same way (ESCORT_SPEC section 4).
var world: WorldMap = null
## The man the escort walks with, when there is one. A reference handed in, not
## a lookup -- ROGUELITE_REWORK section 11, as everywhere.
var villain: Necromancer = null

var rally_point: RallyPoint = null

## True while the party is covering his retreat. Held so the announcement fires
## once on each transition rather than every frame.
var _covering: bool = false

## **Defensive stance's latch.** Set when the villain or any bound escort takes
## a hit; cleared when nothing hostile is left inside the ring. Without it,
## "engage only after the party is struck" would mean re-checking a past event
## for ever, and the escort would stay aggressive for the rest of the run after
## one scratch.
var _party_struck: bool = false

## Per-unit patrol bookkeeping, keyed by Laborer. Kept here rather than as
## fields on Laborer because it is meaningless to a unit that isn't bound, and
## Laborer is already carrying more state than it wants to.
var _patrol_targets: Dictionary = {}
var _patrol_waits: Dictionary = {}

func _ready() -> void:
	# Defensive stance needs to know when the party was hit, and the policy layer
	# already announces every landed blow for the floating numbers. Riding that
	# signal beats a second announcement or a per-frame hp comparison.
	EventBus.damage_shown.connect(_on_damage_shown)
	set_process(true)

func _on_damage_shown(unit, _amount: int, kind: String) -> void:
	if kind != "damage" or not is_active():
		return
	if unit == villain or (unit is Laborer and unit.rallied):
		_party_struck = true

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

## **Escort: the same spell, anchored to a man instead of to the ground.**
##
## No targeting mode, because the target is him -- which is also why the input
## arbitration in Main needs no new branch. Binds exactly as any other cast: all
## the dead, never a chosen subset, because picking which three skeletons to
## take is a selection UI and a selection UI is the per-unit control the pillar
## rules out.
func cast_escort(who) -> int:
	var bound: int = cast(who.position, RallyPoint.Order.ESCORT)
	rally_point.follow = who
	villain = who
	_party_struck = false
	EventBus.escort_bound.emit(who, bound)
	return bound

## Re-anchors the point to the ground, ending the escort without releasing the
## dead. Re-cast is the way back to it -- section 3's "re-cast re-anchors".
func anchor_to_ground(at: Vector2) -> void:
	if not is_active():
		return
	rally_point.follow = null
	rally_point.position = at
	_set_covering(false)

func set_stance(stance: int) -> void:
	if not is_active() or rally_point.stance == stance:
		return
	rally_point.stance = stance
	# Switching to Defensive forgets the last scuffle: the player just said
	# "stop starting things", and holding a struck latch would ignore them for
	# as long as the fight lasted.
	if stance == RallyPoint.Stance.DEFENSIVE:
		_party_struck = false
	EventBus.escort_stance_changed.emit(villain, RallyPoint.stance_name(stance))

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
	if villain:
		villain.escort.clear()
	_set_covering(false)
	_party_struck = false
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
	_refresh_escort_cache(bound)
	_refresh_cover_state()
	# The Defensive latch lets go once there is nothing left in the ring: the
	# fight is over, or the party walked away from it.
	if _party_struck and _hostiles_in_ring().is_empty():
		_party_struck = false

	for u in bound:
		if u.in_combat or not u.is_alive():
			continue
		_advance_bound(u, delta)

## `Necromancer.escort` is a **cache, not the source of truth** (ESCORT_SPEC
## section 8). Membership is derived every frame from "undead and rallied and
## the point follows him"; this writes the answer down where the panel and
## `SortieSystem` can read it without recounting the roster.
##
## It is also what makes a skeleton raised at a grave join with no explicit add:
## the standing order re-binds every frame, so a body that exists by the next
## frame is in this Array by the next frame.
func _refresh_escort_cache(bound: Array) -> void:
	if villain == null:
		return
	if not rally_point.is_escorting():
		villain.escort.clear()
		return
	villain.escort.assign(bound.filter(func(u): return u.is_alive()))

func _advance_bound(u, delta: float) -> void:
	# **Cover the retreat** (section 4), and it overrides stance in both
	# directions -- instinct is not policy.
	if _covering:
		_interpose(u, delta)
		return

	var hostile = _hostile_for(u)
	if hostile != null:
		if u.position.distance_to(hostile.position) <= ENGAGE_RADIUS_PX:
			if combat_system:
				combat_system.engage(hostile, u)
			return
		u.position = Roaming.step(u.position, hostile.position, u.walk_speed_px(), delta, world)
		return

	match rally_point.order:
		RallyPoint.Order.PATROL:
			_walk_beat(u, delta)
		_:
			# Defend, Attack and Escort all idle *at* the point when there's
			# nothing to fight; the difference between them is only how far
			# they'll go for a hostile, which _hostile_for() above already
			# applied -- and, for Escort, that the point is walking.
			if u.position.distance_to(rally_point.position) > ARRIVE_EPSILON:
				u.position = Roaming.step(u.position, rally_point.position,
					u.walk_speed_px(), delta, world)

## **The only genuinely new behaviour in this spec.** Below the flee threshold
## the dead put themselves between him and the nearest hostile -- they target
## the midpoint rather than the hostile, and they do not break off.
##
## Undead don't rout: the living-recruit flee rule explicitly does not apply to
## them, so "cover" is positioning, not morale. It ends when he heals past the
## threshold or the hostiles are gone.
func _interpose(u, delta: float) -> void:
	var hostile = _nearest_hostile_to_villain()
	if hostile == null:
		if u.position.distance_to(rally_point.position) > ARRIVE_EPSILON:
			u.position = Roaming.step(u.position, rally_point.position,
				u.walk_speed_px(), delta, world)
		return
	# Between the two, a little toward the threat: standing exactly on the
	# midpoint leaves a gap either side at any real spacing.
	var spot: Vector2 = villain.position.lerp(hostile.position, 0.6)
	if u.position.distance_to(hostile.position) <= ENGAGE_RADIUS_PX:
		if combat_system:
			combat_system.engage(hostile, u)
		return
	u.position = Roaming.step(u.position, spot, u.walk_speed_px(), delta, world)

func _refresh_cover_state() -> void:
	var should: bool = (villain != null and villain.is_alive()
		and rally_point.is_escorting()
		and villain.hp_fraction() < Combat.FLEE_HP_FRACTION
		and _nearest_hostile_to_villain() != null)
	_set_covering(should)

func _set_covering(on: bool) -> void:
	if on == _covering:
		return
	_covering = on
	if villain:
		EventBus.escort_covering.emit(villain, on)

func is_covering() -> bool:
	return _covering

func _nearest_hostile_to_villain():
	if combat_system == null or villain == null:
		return null
	var best = null
	var best_dist: float = INF
	for h in combat_system.hostiles():
		var d: float = villain.position.distance_to(h.position)
		if d < best_dist:
			best_dist = d
			best = h
	return best

## Hostiles inside the order's ring, measured from the point as everything else
## here is.
func _hostiles_in_ring() -> Array:
	if combat_system == null or not is_active():
		return []
	var limit: float = rally_point.radius_for_order()
	return combat_system.hostiles().filter(
		func(h): return rally_point.position.distance_to(h.position) <= limit)

## The nearest hostile this unit is allowed to go after, given the order's
## radius. Measured from the **rally point**, not from the unit -- otherwise a
## skeleton that chased something to the edge of its leash could then measure
## from its new position and keep going forever.
##
## **Iterates `combat_system.hostiles()`, not `wolves`** -- ESCORT_SPEC section
## 4's one real refactor. Before R2d this loop knew what a `Wolf` was, so a
## bound skeleton standing in front of a site guardian could not see it, and the
## den fight the escort exists for was unwinnable by the escort. The list also
## already drops a departing wolf, so letting a beaten or fed one go is now the
## hostile list's rule rather than a check restated here.
##
## **Stance gates it** (amendment 2026-08-29). Defensive returns nothing until
## the party has been struck; Aggressive is the body's original behaviour. The
## gate is here rather than in `_advance_bound` so that every consumer of "what
## may this unit attack" gets it -- including anything added later.
func _hostile_for(u):
	if combat_system == null:
		return null
	if not _stance_permits_engaging():
		return null
	var limit: float = rally_point.radius_for_order()
	var best = null
	var best_dist: float = INF
	for h in combat_system.hostiles():
		if rally_point.position.distance_to(h.position) > limit:
			continue
		var d: float = u.position.distance_to(h.position)
		if d < best_dist:
			best_dist = d
			best = h
	return best

## Aggressive always; Defensive only once the party has been hit. Stance is an
## escort concept, so the other three orders are unaffected -- a Defend point
## planted on a doorstep behaves exactly as it did before this pass.
func _stance_permits_engaging() -> bool:
	if not rally_point.is_escorting():
		return true
	if rally_point.stance == RallyPoint.Stance.AGGRESSIVE:
		return true
	return _party_struck

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
	u.position = Roaming.step(u.position, target, u.walk_speed_px(), delta, world)
