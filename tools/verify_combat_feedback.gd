extends Node
## Verifies the floating damage numbers against `COMBAT_FEEDBACK_SPEC.md` §5.
##
##   godot --headless --path . res://tools/verify_combat_feedback.tscn
##
## A **scene** rather than a `-s` script because `-s` compiles before the
## autoloads register, and this whole slice hangs off `EventBus` (CLAUDE.md's
## gotchas). Run headless.
##
## **Kept in the repo.** The two things worth guarding are invisible until they
## break: that the pool is a *cap* rather than a suggestion, and that a thousand
## exchanges leave no nodes behind. Both are the kind of thing a "view of an
## event" gets wrong quietly, months later, when someone adds a second damage
## source.

const EXCHANGES_FOR_LEAK_TEST: int = 1000

var _passed: int = 0
var _failed: int = 0

## Everything `damage_shown` emitted while a probe was armed.
var _seen: Array = []

func _ready() -> void:
	get_tree().root.size = Vector2i(1400, 760)
	await get_tree().process_frame
	var main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	print("\n=== Combat feedback (COMBAT_FEEDBACK_SPEC §5) ===\n")
	EventBus.damage_shown.connect(_record)

	_formula_is_untouched()
	await _emits_per_landed_swing(main)
	# Ends the fight and heals everyone. Runs *before* the repair test as well
	# as after it, because `_tick_throne_repair` skips any worker still flagged
	# `in_combat` -- and the engagement outlives the wolf that started it.
	await _quiet_the_settlement(main)
	await _throne_repair_heals(main)
	await _pool_is_capped(main)
	_bad_units_do_not_error(main)
	await _no_leak(main)

	EventBus.damage_shown.disconnect(_record)
	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

## Arity matters: three parameters, or this connects fine and never fires.
func _record(unit, amount: int, kind: String) -> void:
	_seen.append({"unit": unit, "amount": amount, "kind": kind})

# ---------------- The formula and the clock stay signal-free -----------------

## The spec's hardest constraint, and the one a later change is most likely to
## breach for convenience: `Combat.gd` and `Engagement.gd` must not know this
## signal exists. Asserted against the source rather than trusted.
func _formula_is_untouched() -> void:
	for path in ["res://scripts/combat/Combat.gd", "res://scripts/combat/Engagement.gd"]:
		var src: String = FileAccess.get_file_as_string(path)
		_check("%s never mentions EventBus" % path.get_file(),
			not src.contains("EventBus"), "it does now")
		_check("%s never mentions damage_shown" % path.get_file(),
			not src.contains("damage_shown"), "it does now")

# ---------------- One emit per landed swing, with the right amounts ----------

## Drives a real fight through `CombatSystem` and checks the numbers announced
## match the hp that actually moved -- on **both** sides of the exchange, which
## is the half most easily forgotten (the wolf takes damage too).
func _emits_per_landed_swing(main) -> void:
	var cs: CombatSystem = main.combat_system
	var wolf: Wolf = cs.spawn_wolf(main.villain.position + Vector2(400.0, 0.0))
	_check("a wolf spawned to fight", wolf != null, "spawn_wolf returned null")
	if wolf == null:
		return

	var victim = _a_worker(main)
	_check("a worker exists to be bitten", victim != null, "no workers on the roster")
	if victim == null:
		return

	# Full hp on both sides, so nothing dies mid-test and clips a number.
	victim.hp = victim.max_hp()
	wolf.hp = wolf.max_hp()
	var wolf_before: int = wolf.hp
	var victim_before: int = victim.hp

	_seen.clear()
	cs.engage(wolf, victim)
	# One exchange interval, driven through the real _process path.
	await _advance(cs, Combat.EXCHANGE_INTERVAL + 0.05)

	_check("a landed swing announces itself", _seen.size() >= 2,
		"%d emits for one exchange (expected 2 -- both directions)" % _seen.size())
	if _seen.size() < 2:
		return

	var to_victim: int = _total_for(victim, "damage")
	var to_wolf: int = _total_for(wolf, "damage")
	_check("the victim's number equals the hp it actually lost",
		to_victim == victim_before - victim.hp,
		"announced %d, lost %d" % [to_victim, victim_before - victim.hp])
	_check("the wolf's number equals the hp it actually lost",
		to_wolf == wolf_before - wolf.hp,
		"announced %d, lost %d" % [to_wolf, wolf_before - wolf.hp])
	_check("both directions of the exchange were announced",
		to_victim > 0 and to_wolf > 0,
		"victim %d, wolf %d" % [to_victim, to_wolf])
	for e in _seen:
		_check("every amount is positive (%d)" % e["amount"], e["amount"] > 0, "not positive")
		_check("every kind is damage or heal ('%s')" % e["kind"],
			e["kind"] == "damage" or e["kind"] == "heal", "unknown kind")

	await _break_off(cs, wolf)

## Ends a fight the way the **game** ends one, and waits for CombatSystem to
## notice.
##
## **This is what the harness was getting wrong.** It used to call
## `Wolf.depart()` -- a raw state setter -- and then wait up to 600 frames for
## `is_fighting()` to go false. But `depart()` does not end the engagement:
## `CombatSystem._advance_engagement` keeps running an exchange every 1.5s until
## the wolf despawns or its defender dies. So the wait was ten seconds of the
## wolf still biting, which killed the skeleton it was fighting, then the next
## one, and about one run in three the roster was empty by the time the
## Throne-repair test asked for a worker -- failing as "a throne and a worker
## exist" with no hint that a wolf had eaten the workforce.
##
## Dropping the wolf below `FLEE_BELOW_HP` instead uses the game's own path:
## `_advance_engagement` sees `should_flee()`, clears every defender's
## `in_combat`, departs the wolf and calls `_finish(e)` in the same tick. The
## fight is over because the game ended it, which is also the only way it ends
## in play.
##
## The game is not wrong here and was not changed. A wolf told to leave while
## its teeth are in something does keep biting for a moment, and in play that
## state is only ever reached *through* `should_flee()` or dawn, both of which
## finish the engagement on the spot.
func _break_off(cs: CombatSystem, wolf: Wolf) -> void:
	if wolf == null or not is_instance_valid(wolf):
		return
	wolf.hp = 1   # below Wolf.FLEE_BELOW_HP, so should_flee() is true
	var frames: int = 0
	while cs.is_fighting() and frames < 120:
		await get_tree().process_frame
		frames += 1

## Sums the announced amounts for one unit and kind.
func _total_for(unit, kind: String) -> int:
	var n: int = 0
	for e in _seen:
		if e["unit"] == unit and e["kind"] == kind:
			n += e["amount"]
	return n

# ---------------- The Throne's +1 is announced too ----------------------------

## The spec's other emit site. Easy to leave out, because nothing about a
## healing skeleton looks like combat -- but it is the same signal, and the one
## place the `heal` kind is produced by the game rather than by this harness.
##
## Runs at `Engine.time_scale = 10` rather than waiting six real seconds. That
## is also a free check of the thing the spec cares about: the repair timer and
## the float clock are both delta accumulators, so both scale together.
##
## **`_wait` counts game seconds, not wall-clock ones** -- `get_process_delta_time()`
## is already scaled. So the wait is the full THRONE_REPAIR_SECONDS and the time
## scale only decides how fast that arrives. Dividing the wait by the scale as
## well, which the first version did, asked for 0.9s of game time against a 6s
## timer and passed only when an earlier test had left the accumulator nearly
## full -- an intermittent green that had nothing to do with the code under test.
func _throne_repair_heals(main) -> void:
	var throne: Building = main.settlement.get_main_building()
	var victim = _a_worker(main)
	if throne == null or victim == null:
		_check("a throne and a worker exist for the repair test", false,
			"throne=%s, %d workers on the roster" % [throne, main.worker_system.workers.size()])
		return

	# **WorkerSystem is paused for the duration.** Repair only reaches a worker
	# that is IDLE and standing by the Throne, and the trip loop hands an idle
	# worker a job within a frame and walks it off -- the first run of this test
	# watched the victim leave at stage 1 and 50px out. Pausing the one system
	# that moves it is less fragile than re-pinning it every frame and racing
	# node order.
	var worker_system = main.worker_system
	worker_system.set_process(false)

	var half: float = float(SettlementGrid.CELL_SIZE) * 0.5
	victim.position = Vector2(
		throne.cell.x * SettlementGrid.CELL_SIZE + half,
		throne.cell.y * SettlementGrid.CELL_SIZE + half)
	victim.in_combat = false
	victim.stage = Laborer.TripStage.IDLE
	victim.hp = maxi(1, victim.max_hp() - 3)
	var before: int = victim.hp

	_seen.clear()
	Engine.time_scale = 10.0
	await _wait(CombatSystem.THRONE_REPAIR_SECONDS + 0.5)
	Engine.time_scale = 1.0
	worker_system.set_process(true)

	_check("the Throne's repair announces a heal", _total_for(victim, "heal") > 0,
		"no heal emitted in %ss of game time" % CombatSystem.THRONE_REPAIR_SECONDS)
	_check("the heal amount equals the hp actually restored",
		_total_for(victim, "heal") == victim.hp - before,
		"announced %d, restored %d" % [_total_for(victim, "heal"), victim.hp - before])
	for e in _seen:
		if e["unit"] == victim:
			_check("a repair float is a heal, not damage ('%s')" % e["kind"],
				e["kind"] == "heal", "wrong kind")
			break
	victim.hp = victim.max_hp()   # nothing left for repair to announce

## Leaves the settlement emitting nothing of its own, so the pool and leak
## counts below measure this harness rather than the game running underneath it.
##
## Two sources had to be shut off, both found by instrumenting a failing run:
##
## 1. **A live engagement.** `Wolf.depart()` sets the wolf leaving; it does not
##    end the fight. `CombatSystem` finishes the engagement on its own tick, and
##    until it does the exchanges keep landing -- the first run of the pool test
##    was counting a real wolf still biting a real skeleton. So this waits for
##    `is_fighting()` to go false rather than assuming departing did it.
## 2. **Throne repair.** Every damaged worker within 1.5 cells of the Throne
##    floats a `+1` every six seconds. Correct behaviour, wrong test; healing
##    everyone to full removes the reason rather than the symptom.
func _quiet_the_settlement(main) -> void:
	var cs: CombatSystem = main.combat_system
	for wolf in cs.wolves.duplicate():
		await _break_off(cs, wolf)
	# Bounded: a stuck engagement should fail the tests below, not hang here.
	var frames: int = 0
	while cs.is_fighting() and frames < 600:
		await get_tree().process_frame
		frames += 1
	_check("the test fight ended before the quiet tests", not cs.is_fighting(),
		"still fighting after %d frames" % frames)
	for w in main.worker_system.all_units():
		w.in_combat = false
		w.hp = w.max_hp()

# ---------------- The cap is a cap -------------------------------------------

## 200 emits into a 32-slot pool. The point is not that it copes -- it is that
## the node count does not move at all, because the pool is allocated once and
## the oldest float is recycled.
func _pool_is_capped(main) -> void:
	var cf: CombatFeedback = main.combat_feedback
	var victim = _a_worker(main)
	var baseline: int = cf.pool_size()
	_check("the pool is exactly MAX_FLOATS labels",
		baseline == CombatFeedback.MAX_FLOATS,
		"%d children, expected %d" % [baseline, CombatFeedback.MAX_FLOATS])

	for i in range(200):
		EventBus.damage_shown.emit(victim, 1 + (i % 9), "damage")
	_check("200 emits do not grow the pool", cf.pool_size() == baseline,
		"%d children now" % cf.pool_size())
	_check("live floats never exceed the cap",
		cf.live_count() <= CombatFeedback.MAX_FLOATS,
		"%d live" % cf.live_count())
	_check("and the cap is actually reached, or this proved nothing",
		cf.live_count() == CombatFeedback.MAX_FLOATS,
		"%d live" % cf.live_count())

	# They expire on the shared clock, not on a timer each.
	await _wait(CombatFeedback.FLOAT_SECONDS + 0.2)
	_check("floats expire and the pool empties", cf.live_count() == 0,
		"%d still live" % cf.live_count())
	_check("expiring frees no nodes either", cf.pool_size() == baseline,
		"%d children" % cf.pool_size())

# ---------------- Junk in, no crash out --------------------------------------

## The spec asks that emits with a dead or never-shown unit do not error. A view
## has nothing useful to say about a unit that is gone, and must not take the
## frame down trying.
func _bad_units_do_not_error(main) -> void:
	var cf: CombatFeedback = main.combat_feedback
	var before: int = cf.pool_size()

	EventBus.damage_shown.emit(null, 5, "damage")
	# A RefCounted with no `position` at all -- something never drawable.
	EventBus.damage_shown.emit(RefCounted.new(), 5, "damage")
	# A freed Node.
	var doomed := Node2D.new()
	doomed.free()
	EventBus.damage_shown.emit(doomed, 5, "damage")
	# Amounts that must never draw.
	EventBus.damage_shown.emit(_a_worker(main), 0, "damage")
	EventBus.damage_shown.emit(_a_worker(main), -3, "heal")

	_check("null / undrawable / freed units and 0-amounts do not error", true)
	_check("and none of them spawned a float", cf.live_count() == 0,
		"%d live" % cf.live_count())
	_check("and none of them changed the pool", cf.pool_size() == before,
		"%d children" % cf.pool_size())

# ---------------- 1,000 exchanges leak nothing -------------------------------

## The spec's leak test, run against the **whole scene** rather than just the
## feedback layer: a float that parented itself somewhere else, or a label that
## was `new()`d instead of reused, shows up here and nowhere else.
func _no_leak(main) -> void:
	var cf: CombatFeedback = main.combat_feedback
	var victim = _a_worker(main)
	var pool_before: int = cf.pool_size()
	var tree_before: int = _count_nodes(get_tree().root)
	var orphans_before: int = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)

	for i in range(EXCHANGES_FOR_LEAK_TEST):
		# Both halves, the way a real exchange announces itself.
		EventBus.damage_shown.emit(victim, 1 + (i % 7), "damage")
		EventBus.damage_shown.emit(victim, 1 + (i % 5), "damage")
		if i % 50 == 0:
			EventBus.damage_shown.emit(victim, 1, "heal")
	await _wait(CombatFeedback.FLOAT_SECONDS + 0.2)

	_check("%d exchanges leak zero pool nodes" % EXCHANGES_FOR_LEAK_TEST,
		cf.pool_size() == pool_before,
		"%d -> %d" % [pool_before, cf.pool_size()])
	_check("...and zero nodes anywhere in the tree",
		_count_nodes(get_tree().root) == tree_before,
		"%d -> %d" % [tree_before, _count_nodes(get_tree().root)])
	_check("...and zero orphans",
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) == orphans_before,
		"%d -> %d" % [orphans_before,
			Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)])
	_check("and the pool is idle again", cf.live_count() == 0,
		"%d live" % cf.live_count())

# ---------------- Helpers ----------------------------------------------------

func _a_worker(main):
	for w in main.worker_system.workers:
		if w.is_alive():
			return w
	return null

## Drives CombatSystem's own `_process` for `seconds` of game time, in real
## frames, so the exchanges resolve through the path the game uses.
func _advance(cs: CombatSystem, seconds: float) -> void:
	var left: float = seconds
	while left > 0.0:
		await get_tree().process_frame
		left -= get_process_delta_time()

func _wait(seconds: float) -> void:
	var left: float = seconds
	while left > 0.0:
		await get_tree().process_frame
		left -= get_process_delta_time()

func _count_nodes(n: Node) -> int:
	var total: int = 1
	for c in n.get_children():
		total += _count_nodes(c)
	return total

func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s   (%s)" % [what, detail])
