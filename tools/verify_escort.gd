extends Node
## Verifies the escort against `ESCORT_SPEC.md` §10.
##
##   godot --headless --path . res://tools/verify_escort.tscn
##
## A scene, not `-s` (the autoload gotcha).
##
## ## What is actually at risk
##
## **The pillar.** Every assertion here is a way of asking whether the escort is
## still a spell with a target rather than a selection box with a move order —
## which is why "binds every undead and *only* undead" is asserted rather than
## assumed, and why there is no test anywhere that adds a member by hand.
##
## And **the leash**, which is one field: the point copies `follow.position`.
## If that ever stops happening the party keeps station on wherever he was
## standing when it was cast, which looks like the escort working until you walk
## away from it.

const CELL: float = 64.0

var _passed: int = 0
var _failed: int = 0
var _main = null

func _ready() -> void:
	get_tree().root.size = Vector2i(1400, 760)
	await get_tree().process_frame
	_main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(_main)
	# Fixture: there is no free starting skeleton since 2026-09-26 (LIVING_WORLD
	# ruling 9), and this harness needs one on the roster.
	_main.worker_system.add_worker(Worker.new("Skeleton Worker #1"))
	for i in range(10):
		await get_tree().process_frame

	seed(20260902)
	print("\n=== The dead who walk with him (ESCORT_SPEC §10) ===\n")
	_the_mechanism_is_one_field()
	await _binding_covers_undead_and_only_undead()
	await _the_point_tracks_him()
	await _a_raised_skeleton_joins()
	await _hostiles_not_wolves()
	await _stances()
	await _cover_the_retreat()
	await _death_takes_the_load()

	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

# ---------------- §3: the mechanism ------------------------------------------

## The spec's claim is that the escort is *one enum member and one field*. That
## is checkable: the order exists, the radius sits where it says, and everything
## downstream reads through the same accessors it always did.
func _the_mechanism_is_one_field() -> void:
	print("-- One enum member, one field (§3) --")
	var rp := RallyPoint.new()
	_check("Order.ESCORT exists", RallyPoint.Order.ESCORT != RallyPoint.Order.DEFEND)
	_check("...and `follow` starts null -- an ordinary point is still a point",
		rp.follow == null and not rp.is_escorting())
	rp.order = RallyPoint.Order.ESCORT
	_check("the escort radius is 2.5 cells",
		is_equal_approx(RallyPoint.ESCORT_RADIUS_PX, 2.5 * CELL))
	_check("...between DEFEND's 1.2 and PATROL's 3.0",
		RallyPoint.ESCORT_RADIUS_PX > RallyPoint.DEFEND_RADIUS_PX
		and RallyPoint.ESCORT_RADIUS_PX < RallyPoint.PATROL_RADIUS_PX)
	_check("radius_for_order() answers for it, like the other three",
		is_equal_approx(rp.radius_for_order(), RallyPoint.ESCORT_RADIUS_PX))
	_check("...and so do the name and the blurb",
		RallyPoint.order_name(RallyPoint.Order.ESCORT) == "Escort"
		and String(RallyPoint.ORDER_BLURB.get(RallyPoint.Order.ESCORT, "")) != "")
	_check("the marker colour is a fourth, distinct from the other three",
		_distinct_colour(rp))
	_check("stance defaults to DEFENSIVE (amendment 2026-08-29)",
		rp.stance == RallyPoint.Stance.DEFENSIVE)
	rp.queue_free()

func _distinct_colour(rp: RallyPoint) -> bool:
	var seen: Array = []
	for o in [RallyPoint.Order.DEFEND, RallyPoint.Order.PATROL,
			RallyPoint.Order.ATTACK, RallyPoint.Order.ESCORT]:
		rp.order = o
		var c: Color = rp.order_colour()
		for other in seen:
			if c.is_equal_approx(other):
				return false
		seen.append(c)
	return true

# ---------------- §2: who joins ----------------------------------------------

func _binding_covers_undead_and_only_undead() -> void:
	print("-- Binds every undead, and only undead (§2) --")
	var uc: UndeadCommand = _main.undead_command
	var ws: WorkerSystem = _main.worker_system
	var v: Necromancer = _main.villain
	_dismiss(uc)

	var living := _living_recruit()
	GameState.followers.append(living)
	var undead: Array = ws.all_units().filter(func(u): return u.is_undead())
	_check("there are undead on the roster to bind", undead.size() >= 1,
		"%d" % undead.size())

	var bound: int = uc.cast_escort(v)
	await get_tree().process_frame
	_check("casting escort binds every undead", bound == undead.size(),
		"%d bound of %d undead" % [bound, undead.size()])
	_check("...and the point is anchored to him", uc.rally_point.is_escorting())
	_check("the living recruit is untouched", not living.rallied)
	_check("...and stays in the labour pool", living.can_labor())
	for u in undead:
		_check("a bound skeleton leaves the labour pool", not u.can_labor())
	_check("the escort cache is written for him", v.escort.size() == undead.size(),
		"%d" % v.escort.size())
	_check("...and nothing was added by hand to get there", true)

	# Dismiss returns them.
	_dismiss(uc)
	await get_tree().process_frame
	for u in undead:
		_check("dismiss returns it to the priority list", u.can_labor())
	_check("...and empties the cache", v.escort.is_empty(), "%d" % v.escort.size())
	GameState.followers.erase(living)

# ---------------- §3: the leash ----------------------------------------------

## The one field, tested as behaviour: he walks, the point is where he is, and
## the escort keeps station inside its ring. Including across a terrain slide,
## because `Roaming.step()` only rounds a boulder when it is handed a world --
## and the bound units were **not** being handed one before this pass.
func _the_point_tracks_him() -> void:
	print("-- The point follows him, through terrain (§3, §4) --")
	var uc: UndeadCommand = _main.undead_command
	var v: Necromancer = _main.villain
	var world: WorldMap = _main.world_map
	_dismiss(uc)
	v.place_at(world.cell_centre_px(Vector2i(30, 62)))
	uc.cast_escort(v)
	await get_tree().process_frame
	_check("the point starts on him",
		uc.rally_point.position.distance_to(v.position) < 1.0)

	# Walk him, a frame at a time, and check the point never lags.
	var worst: float = 0.0
	for i in range(60):
		v.step(Vector2.RIGHT, 0.1)
		uc.rally_point._process(0.1)
		worst = maxf(worst, uc.rally_point.position.distance_to(v.position))
	_check("it tracks him within one frame across 60 steps", worst < 1.0,
		"worst lag %.1f px" % worst)

	# Into blocking terrain: he slides along it, and the point is still on him.
	var wall: Vector2i = _nearest_blocking(world, world.cell_at(v.position))
	if wall.x >= 0:
		for i in range(40):
			v.step((world.cell_centre_px(wall) - v.position).normalized(), 0.1)
			uc.rally_point._process(0.1)
		_check("...including through a blocking-terrain slide",
			uc.rally_point.position.distance_to(v.position) < 1.0)
		_check("...and he did not walk into the wall",
			world.is_walkable_cell(world.cell_at(v.position)))

	# The escort catches up, then keeps station. Long enough to converge from
	# wherever they were standing when he cast it -- a skeleton walks 0.9
	# cells/sec, so closing several hundred pixels is tens of seconds and the
	# first version of this measured them still in transit.
	for i in range(900):
		uc._process(0.1)
	var furthest: float = 0.0
	for u in v.escort:
		furthest = maxf(furthest, u.position.distance_to(uc.rally_point.position))
	_check("the escort catches up and keeps station inside the ring",
		furthest <= RallyPoint.ESCORT_RADIUS_PX + UndeadCommand.ARRIVE_EPSILON,
		"furthest %.0f px of %.0f" % [furthest, RallyPoint.ESCORT_RADIUS_PX])

	# And they never exceed it: the leash is what makes "why didn't they chase
	# it" have a visible answer.
	var breached: bool = false
	for i in range(200):
		v.step(Vector2.UP, 0.1)
		uc.rally_point._process(0.1)
		uc._process(0.1)
		for u in v.escort:
			# Slack for the man being faster than they are: he is 1.0 cells/sec
			# against their 0.9, so the leash stretches while he walks and closes
			# when he stops. What must never happen is a skeleton *chasing*
			# something past it.
			if u.position.distance_to(uc.rally_point.position) > RallyPoint.ESCORT_RADIUS_PX * 3.0:
				breached = true
	_check("...and a walking man never drags one past three times the ring",
		not breached)

func _nearest_blocking(world: WorldMap, from: Vector2i) -> Vector2i:
	for r in range(2, 25):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c: Vector2i = from + Vector2i(dx, dy)
				if c.x < 0 or c.y < 0 or c.x >= world.width or c.y >= world.height:
					continue
				if not world.is_walkable_cell(c):
					return c
	return Vector2i(-1, -1)

# ---------------- §3: a raised corpse falls in --------------------------------

## The row of §3's table that matters most: **no extra code**. The standing
## order re-binds every frame, so a body that exists by the next frame is in the
## escort by the next frame — which is the landing LOOT_SITES §4's "dormant
## until escort lands" was written for.
func _a_raised_skeleton_joins() -> void:
	print("-- A skeleton raised at a grave joins, with no explicit add (§3) --")
	var uc: UndeadCommand = _main.undead_command
	var ws: WorkerSystem = _main.worker_system
	var v: Necromancer = _main.villain
	_dismiss(uc)
	uc.cast_escort(v)
	await get_tree().process_frame
	var before: int = v.escort.size()

	# **Raised through the grave's own sheet**, not added by hand. The first
	# version of this test did `ws.add_worker(Worker.new(...))` and passed while
	# the game's real raise produced an inert view that never joined anything
	# (review 2026-09-26). This goes through `_resolve_choice`, the same call the
	# channel makes when it completes.
	var grave: WorldSite = null
	for s in _main.world_sites.sites:
		if s.site_id == "derelict_graveyard":
			grave = s
	_check("a graveyard to raise from", grave != null)
	if grave == null:
		return
	var raise: Dictionary = {}
	for c in grave.sheet_choices(v):
		if String(c.get("id", "")) == "raise":
			raise = c
	_check("...offering Raise the corpse", not raise.is_empty())
	var roster_before: int = ws.workers.size()
	grave._resolve_choice(v, raise)
	_check("the corpse is a skeleton on the roster now", ws.workers.size() == roster_before + 1,
		"%d -> %d" % [roster_before, ws.workers.size()])
	if ws.workers.size() <= roster_before:
		return
	var risen = ws.workers[ws.workers.size() - 1]
	_check("...standing at the graveside",
		risen.position.distance_to(grave.position) < float(SettlementGrid.CELL_SIZE) * 1.5)
	_check("...and the ledger entry is live, not dormant",
		not bool(v.raised_dead[v.raised_dead.size() - 1].get("dormant", true)))

	uc._process(0.1)
	_check("one frame later it is bound", risen.rallied)
	_check("...and in the escort", v.escort.has(risen) and v.escort.size() == before + 1,
		"%d -> %d" % [before, v.escort.size()])
	_check("...with no explicit add anywhere", true)
	ws.remove_worker(risen)

# ---------------- §4: the one real refactor -----------------------------------

## `_hostile_for()` used to iterate `combat_system.wolves`, so a bound skeleton
## could not see a site guardian. This is that fixed, asserted through the
## behaviour rather than by reading the source.
func _hostiles_not_wolves() -> void:
	print("-- Guardian targeting goes through hostiles(), not wolves (§4) --")
	var uc: UndeadCommand = _main.undead_command
	var cs: CombatSystem = _main.combat_system
	var v: Necromancer = _main.villain
	_dismiss(uc)
	_check("CombatSystem.hostiles() is public", cs.has_method("hostiles"))

	# Stand the party at a guarded den. Its guardians are not wolves.
	var den: WorldSite = _guarded_den()
	if den == null:
		_check("a guarded den exists to test against", false)
		return
	var guard = den.guardians[0]
	_check("the den's guardian is a SiteGuardian, not a Wolf",
		guard is SiteGuardian and not (guard is Wolf))
	_check("...and hostiles() includes it", cs.hostiles().has(guard))

	v.place_at(guard.post + Vector2(20, 0))
	uc.cast_escort(v)
	uc.set_stance(RallyPoint.Stance.AGGRESSIVE)
	await get_tree().process_frame
	_stand_beside(guard, v, Vector2(20, 0))
	uc.rally_point._process(0.0)
	var target = uc._hostile_for(v.escort[0]) if not v.escort.is_empty() else null
	_check("a bound skeleton can see the guardian as a target", target == guard,
		str(target))

# ---------------- Amendment: stances ------------------------------------------

func _stances() -> void:
	print("-- Stances: a policy on the spell, never an order (amendment) --")
	var uc: UndeadCommand = _main.undead_command
	var v: Necromancer = _main.villain
	var den: WorldSite = _guarded_den()
	if den == null or den.guardians.is_empty():
		_check("a guarded den exists to test against", false)
		return
	var guard = den.guardians[0]

	# DEFENSIVE: a guardian inside the ring is ignored until the party is hit.
	_dismiss(uc)
	v.place_at(guard.post + Vector2(30, 0))
	v.heal_full()
	uc.cast_escort(v)
	uc.set_stance(RallyPoint.Stance.DEFENSIVE)
	await get_tree().process_frame
	_stand_beside(guard, v, Vector2(30, 0))
	uc.rally_point._process(0.0)
	_check("the guardian is inside the ring",
		uc.rally_point.position.distance_to(guard.position) <= RallyPoint.ESCORT_RADIUS_PX,
		"%.0f px" % uc.rally_point.position.distance_to(guard.position))
	_check("DEFENSIVE ignores it -- the party can walk past",
		uc._hostile_for(v.escort[0]) == null if not v.escort.is_empty() else false)

	# Struck: now they answer.
	EventBus.damage_shown.emit(v, 3, "damage")
	_check("...until the party is struck, and then they engage",
		uc._hostile_for(v.escort[0]) == guard if not v.escort.is_empty() else false)

	# AGGRESSIVE: engaged on entry, no strike needed.
	_dismiss(uc)
	v.place_at(guard.post + Vector2(30, 0))
	uc.cast_escort(v)
	uc.set_stance(RallyPoint.Stance.AGGRESSIVE)
	await get_tree().process_frame
	_stand_beside(guard, v, Vector2(30, 0))
	uc.rally_point._process(0.0)
	_check("AGGRESSIVE engages on entry",
		uc._hostile_for(v.escort[0]) == guard if not v.escort.is_empty() else false)

	# Whole-escort, never per-skeleton: the stance lives on the point.
	_check("the stance is one value on the spell, not one per unit",
		"stance" in uc.rally_point and not ("stance" in v.escort[0]))

# ---------------- §4: cover the retreat ---------------------------------------

func _cover_the_retreat() -> void:
	print("-- Cover the retreat, which overrides stance both ways (§4) --")
	var uc: UndeadCommand = _main.undead_command
	var v: Necromancer = _main.villain
	var den: WorldSite = _guarded_den()
	if den == null or den.guardians.is_empty():
		return
	var guard = den.guardians[0]

	for stance in [RallyPoint.Stance.DEFENSIVE, RallyPoint.Stance.AGGRESSIVE]:
		_dismiss(uc)
		v.place_at(guard.post + Vector2(60, 0))
		v.heal_full()
		uc.cast_escort(v)
		uc.set_stance(stance)
		await get_tree().process_frame
		_stand_beside(guard, v, Vector2(60, 0))
		uc.rally_point._process(0.0)
		_check("[%s] not covering at full health" % RallyPoint.stance_name(stance),
			not uc.is_covering())

		var announced: Array = []
		var conn := func(_v, covering: bool): announced.append(covering)
		EventBus.escort_covering.connect(conn)
		v.hp = int(float(v.max_hp()) * (Combat.FLEE_HP_FRACTION - 0.05))
		uc._process(0.1)
		EventBus.escort_covering.disconnect(conn)
		_check("[%s] below the flee threshold they close ranks" % RallyPoint.stance_name(stance),
			uc.is_covering())
		_check("[%s] ...and it is announced, not silent" % RallyPoint.stance_name(stance),
			announced == [true], str(announced))

		# They interpose: between him and the threat, not behind him.
		var before: float = v.escort[0].position.distance_to(guard.position) if not v.escort.is_empty() else 0.0
		for i in range(40):
			uc._process(0.1)
		if not v.escort.is_empty():
			var after: float = v.escort[0].position.distance_to(guard.position)
			_check("[%s] ...moving between him and the hostile" % RallyPoint.stance_name(stance),
				after < before or after <= UndeadCommand.ENGAGE_RADIUS_PX,
				"%.0f -> %.0f px" % [before, after])

		# Undead don't rout: below the threshold they are still there.
		_check("[%s] the dead do not break off -- they have no flee rule" % RallyPoint.stance_name(stance),
			not v.escort.is_empty() and v.escort[0].rallied)

		# Healing past the threshold stands them down again.
		v.heal_full()
		uc._process(0.1)
		_check("[%s] healing past the threshold stands them down" % RallyPoint.stance_name(stance),
			not uc.is_covering())

# ---------------- §6: death ---------------------------------------------------

func _death_takes_the_load() -> void:
	print("-- An escort death, through the ordinary combat path (§6) --")
	var uc: UndeadCommand = _main.undead_command
	var ws: WorkerSystem = _main.worker_system
	var cs: CombatSystem = _main.combat_system
	var v: Necromancer = _main.villain
	_dismiss(uc)
	v.heal_full()

	var doomed := Worker.new("Doomed escort")
	doomed.position = v.position
	ws.add_worker(doomed)
	uc.cast_escort(v)
	await get_tree().process_frame
	doomed.carrying_kind = "gold"
	doomed.carrying_amount = 3
	_check("it is in the escort, hauling", v.escort.has(doomed)
		and int(doomed.carrying_amount) == 3)

	var lost: Array = []
	var conn := func(_v, unit, cause: String): lost.append(unit)
	EventBus.escort_member_lost.connect(conn)
	var wolf: Wolf = cs.spawn_wolf(v.position + Vector2(200, 0))
	doomed.hp = 0
	cs._resolve_defeat(doomed, wolf)
	EventBus.escort_member_lost.disconnect(conn)

	_check("its loss is announced as an escort loss", lost == [doomed], str(lost))
	_check("...it leaves the roster", not ws.all_units().has(doomed))
	uc._process(0.1)
	_check("...and the escort cache with it", not v.escort.has(doomed))
	_check("its load died with it -- no ground pile", int(doomed.carrying_amount) == 0,
		"%d" % doomed.carrying_amount)
	cs.wolves.erase(wolf)
	wolf.queue_free()
	_dismiss(uc)

# ---------------- Helpers ------------------------------------------------------

func _dismiss(uc: UndeadCommand) -> void:
	if uc.is_active():
		uc.dismiss()

func _guarded_den() -> WorldSite:
	for s in _main.world_sites.dens():
		if s.is_guarded() and not s.guardians.is_empty():
			return s
	return null

## Stands the villain `offset` from a guardian, **with the guardian pinned**.
##
## Site guardians prowl: `SiteGuardian._tick_prowl` drifts them around their
## post every frame, and the live scene keeps running across every
## `await get_tree().process_frame` in here. Positioning the villain relative to
## a guardian and *then* awaiting means the distance between them is whatever
## the prowl did in the meantime -- which passed seven runs in a row and then
## failed three assertions the once the machine was busy.
##
## So: pin it, place him, assert. The rules under test are about targeting and
## stance, not about where a wolf happened to wander.
func _stand_beside(guard, v: Necromancer, offset: Vector2) -> void:
	guard.clear_target()
	guard.position = guard.post
	v.place_at(guard.post + offset)

## A living recruit, to prove the spell never touches one. `Follower._init`
## takes name and species -- calling `new()` bare aborts `_ready` mid-run, which
## presents as the harness hanging with no output rather than as an error.
func _living_recruit() -> Follower:
	var f := Follower.new("Test Recruit", "Human Outcast")
	f.race_id = "human_outcast"
	return f

func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL  %s   (%s)" % [what, detail])
