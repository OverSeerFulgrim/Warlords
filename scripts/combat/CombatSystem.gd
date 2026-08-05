extends Node
class_name CombatSystem
## Everything about the wolf that isn't the wolf: when one turns up, what it
## picks on, and what happens to whoever loses.
##
## The split matters. `Combat` is the formula (reusable, knows nothing).
## `Engagement` is a fight's clock (reusable, knows nothing). `Wolf` is a
## creature that moves and bleeds. **This** is the policy layer -- targeting,
## the emergent-defence rule, and the four consequence rules -- and it is the
## only one of the four that a Stage-4 bounty would need to replace. Building
## wolf-specific damage logic inline was the failure mode worth avoiding here.
##
## It also owns hit-point *maintenance*, because HP is a combat concern and
## there was no better home for it: skeletons repairing at the Throne live here.
## The living side of regen (+2 per meal) is in MoraleSystem, where the meal
## loop already is.

# ---------------- Design rules, stated once ----------------
#
# 1. **Skeleton Workers can be destroyed.** No bones refunded, no body left.
#    Replaceable for the usual 5 Bones. Losses sting; necromancers shrug.
# 2. **Living recruits are never killed by wildlife.** Below FLEE_HP_FRACTION
#    they break off, run home, and are Injured until healed to full. -1 morale.
# 3. **A deer taken by a wolf is a pure economic loss** -- the food is gone, the
#    wolf is fed and stands down for the night. This is the common case.
# 4. **Wolves will not approach the Necromancer** -- while LAIR_AURA_PROTECTS_
#    VILLAIN holds. He is a real Combatant now (he implements the whole contract
#    on `Necromancer`, and Combat.exchange() hits him with no special casing);
#    this rule is a *lair* rule, not an invulnerability, and it lives behind the
#    flag below so R2 can turn it off out in the world.

## **The lair aura.** While true, wolves won't come near the villain and anything
## standing in his shadow is invisible to them -- the settlement-era rule, kept
## because inside his own domain he should read as the apex predator.
##
## It is a named flag rather than hardcoded behaviour because ROGUELITE_REWORK
## section 15 lists "whether a protective aura applies inside his own lair" as an
## open tunable, and section 5 repeals it out in the world: **R2 flips this off**
## (or makes it positional, holding only near the Throne). Deleting the rule now
## would mean rediscovering it then; leaving it hardcoded would mean hunting it.
## Leave the switch.
##
## Flipping it off is necessary but **not sufficient** to make wildlife hunt him:
## he is not in `_prey_candidates()` at all, and the consequence rules below have
## no branch for a villain losing a fight (that branch is "the run ends", which
## is R4). Turning this off today only stops wolves *avoiding* him. `Combat` is
## already complete on him -- `Combat.exchange(wolf, villain)` works right now.
const LAIR_AURA_PROTECTS_VILLAIN: bool = true

## Only one wolf at a time for now.
const MAX_WOLVES: int = 1

## Chance a wolf turns up on any given dusk *after the first*. Not every night:
## a guaranteed nightly wolf becomes a chore to plan around rather than a thing
## that happens to you.
const WOLF_SPAWN_CHANCE_PERCENT: float = 55.0

## **The first dusk of a run always brings a wolf.** Leaving the introduction to
## a 55% roll meant a player could finish a whole session having never met the
## creature -- which is exactly what happened in playtest, twice, because a
## session tends to end on the first night. A mechanic gets to introduce itself
## deterministically; it can be a gamble afterwards.
var _first_dusk_done: bool = false

## Radius, in pixels, for both halves of the emergent-defence rule: fighters
## inside it join, everyone else inside it runs. 3 grid cells.
const ASSIST_RADIUS_PX: float = 3.0 * float(SettlementGrid.CELL_SIZE)

## A recruit counts as "armed with Might" -- and so wades in rather than running
## -- at this Might or above, regardless of category. Warriors always qualify.
const ASSIST_MIGHT_THRESHOLD: int = 6

## Necromantic maintenance: an idle Skeleton Worker standing at the Throne
## knits itself back together at one hit point per this many seconds. Slow on
## purpose -- a mauled skeleton is out of the workforce for a while, which is
## most of what makes losing the fight cost anything when the unit itself is
## replaceable for 5 bones.
const THRONE_REPAIR_SECONDS: float = 6.0
const THRONE_REPAIR_RADIUS_PX: float = 1.5 * float(SettlementGrid.CELL_SIZE)

## Bones left by a killed wolf. Deliberately better than a seeded animal carcass
## (5): map bones are finite and the whole point of Stage 4's harvest bounties
## is that they run out, so a predator that walks into your settlement and pays
## out more than it costs is a small, welcome pressure valve -- and it makes
## keeping a warrior around something other than pure insurance.
const WOLF_CARCASS_BONES: int = 9

# ---------------- Wiring (set by Main, same convention as the other systems) --
var settlement: SettlementGrid = null
var worker_system: WorkerSystem = null
var resource_field: ResourceField = null
## The villain this settlement belongs to. A **reference passed in**, not a
## lookup and not a singleton -- ROGUELITE_REWORK section 11. It reads his
## `position` off the data object rather than off his token, which is the same
## view-is-a-frame-stale correctness the click hit-test already learned.
var villain: Necromancer = null
## Terrain, handed to each wolf so it prowls around mountains and lakes rather
## than through them.
var world: WorldMap = null
var day_night: DayNightCycle = null

var wolves: Array = []          # Array[Wolf]
var _engagements: Array = []    # Array[Engagement]
var _repair_timer: float = 0.0
## Debounces the Necromancer flavor line so a wolf loitering near the Throne
## doesn't spam the log every frame.
var _necro_fear_cooldown: float = 0.0

func _ready() -> void:
	EventBus.dusk_started.connect(_on_dusk)
	EventBus.dawn_started.connect(_on_dawn)
	set_process(true)

func _process(delta: float) -> void:
	_necro_fear_cooldown = maxf(0.0, _necro_fear_cooldown - delta)
	for wolf in wolves.duplicate():
		_advance_wolf(wolf, delta)
	for e in _engagements.duplicate():
		_advance_engagement(e, delta)
	_tick_throne_repair(delta)

# ---------------- Spawning ----------------

## Wolves come at dusk, from the treeline. The forest is the east edge of the
## map, which is also where your woodcutters and your carcass-gatherers are --
## so the creature arrives where the work is, without any code aiming it there.
func _on_dusk(_day: int) -> void:
	if wolves.size() >= MAX_WOLVES:
		return
	var guaranteed: bool = not _first_dusk_done
	_first_dusk_done = true
	if not guaranteed and randf() * 100.0 > WOLF_SPAWN_CHANCE_PERCENT:
		return
	spawn_wolf()

## Dawn clears the board: any wolf still around slinks off. Keeps "max 1 alive"
## honest without needing a despawn timer, and means a wolf the player never
## dealt with doesn't accumulate into a permanent resident.
func _on_dawn(_day: int) -> void:
	for wolf in wolves:
		if wolf.state != Wolf.State.LEAVING:
			wolf.depart("driven off by the light")

## Public so a smoke test (or a future event) can force one. `at` overrides the
## spawn point; leave it null-ish (Vector2.INF) for the default treeline entry.
func spawn_wolf(at: Vector2 = Vector2.INF) -> Wolf:
	if resource_field == null or settlement == null:
		push_warning("CombatSystem: cannot spawn a wolf before wiring is complete.")
		return null
	var grid_w: float = float(SettlementGrid.GRID_WIDTH * SettlementGrid.CELL_SIZE)
	var grid_h: float = float(SettlementGrid.GRID_HEIGHT * SettlementGrid.CELL_SIZE)
	var cell: float = float(SettlementGrid.CELL_SIZE)

	# East of the grid, level with the forest. Deliberately only ~2 cells out:
	# it used to enter 5.5 cells past the edge, which at the default 0.72 zoom
	# put it right on the rim of the viewport -- playtest reported "the wolf
	# spawned but I didn't see it" even with the alert firing. It has to arrive
	# somewhere the player is actually looking.
	#
	# **This stayed correct when the world grew to 144x144**, and it is worth
	# knowing why rather than re-deriving it: every number here is a multiple of
	# the *settlement grid's* size, and the settlement kept the engine origin
	# when the world map was slid in around it (see WorldMap's header). So the
	# entry point is ~12 cells from the Throne on a 144-cell map exactly as it
	# was on a 10-cell one. Anything added here must stay relative to grid_w /
	# grid_h for the same reason -- a wolf that spawned relative to the *world*
	# would arrive two minutes' walk away and never be seen.
	var entry := Vector2(grid_w + cell * 2.0, grid_h * 0.35)
	var spawn_at: Vector2 = entry if at == Vector2.INF else at

	var wolf := Wolf.new()
	wolf.name = "Wolf"
	settlement.add_child(wolf)
	# The prowl area covers the settlement and its surroundings; the exit is the
	# way it came in.
	wolf.setup(spawn_at, Rect2(Vector2(-cell * 2.0, -cell * 2.0),
		Vector2(grid_w + cell * 6.0, grid_h + cell * 4.0)), entry, world)
	wolves.append(wolf)
	EventBus.wolf_spawned.emit(wolf)
	return wolf

func _despawn(wolf: Wolf) -> void:
	_end_engagements_with(wolf)
	wolves.erase(wolf)
	EventBus.wolf_departed.emit(wolf, wolf.leave_reason)
	wolf.queue_free()

# ---------------- Wolf behaviour ----------------

func _advance_wolf(wolf: Wolf, _delta: float) -> void:
	if wolf.state == Wolf.State.LEAVING:
		if wolf.has_left():
			_despawn(wolf)
		return
	if wolf.state == Wolf.State.FIGHT:
		return  # the Engagement owns it until the fight resolves

	_check_necromancer_fear(wolf)

	# A fed wolf still wanders -- visibly still out there, which is the point of
	# it *standing down* rather than vanishing -- and takes nothing else until
	# dawn moves it on. Same gate covers the post-spawn prowl period.
	if not wolf.may_hunt():
		wolf.clear_target()
		return

	var target = wolf.current_target()
	if target == null or not _is_valid_target(target):
		target = _find_prey(wolf)
		wolf.set_target(target)
		if target == null:
			return

	if not wolf.is_within_engage_range():
		return

	# Reached it. A deer is eaten outright -- no fight, no exchange -- because a
	# wolf killing a deer is a foraging event, not a battle, and modelling it as
	# combat would mean giving deer a Might value that means nothing.
	if _is_deer(target):
		_take_deer(wolf, target)
		return
	_begin_fight(wolf, target)

## Nearest living recruit, worker or deer inside the hunt radius. No preference
## between them -- see Wolf's header for why "nearest" is sufficient.
func _find_prey(wolf: Wolf):
	var best = null
	var best_dist: float = Wolf.HUNT_RADIUS_PX
	for candidate in _prey_candidates():
		var d: float = wolf.position.distance_to(candidate.position)
		if d < best_dist:
			best_dist = d
			best = candidate
	return best

## all_units() rather than laborers(): a skeleton standing guard at a rally
## point is out of the workforce but very much still on the map, and a wolf that
## couldn't see it would walk straight past the thing sent to stop it.
func _prey_candidates() -> Array:
	var out: Array = []
	if worker_system:
		for l in worker_system.all_units():
			if _is_valid_target(l):
				out.append(l)
	if resource_field:
		for n in resource_field.nodes:
			if n.node_type == "deer" and not n.is_depleted():
				out.append(n)
	return out

## Excludes anyone standing in the Necromancer's shadow (rule 4) and any recruit
## already injured -- they're holed up at home, and re-targeting them would put
## a below-threshold unit straight back into a fight it must immediately flee,
## which loops.
func _is_valid_target(t) -> bool:
	if t == null:
		return false
	if _is_deer(t):
		return not t.is_depleted()
	if not t.is_alive():
		return false
	if t.is_injured:
		return false
	if _near_necromancer(t.position):
		return false
	return true

func _is_deer(t) -> bool:
	return t is ResourceNode and t.node_type == "deer"

func _near_necromancer(pos: Vector2) -> bool:
	if not LAIR_AURA_PROTECTS_VILLAIN or villain == null:
		return false
	return pos.distance_to(villain.position) <= Wolf.NECROMANCER_FEAR_RADIUS_PX

## Rule 4, as behaviour rather than a hard wall: a wolf that drifts too close to
## the Necromancer turns around. Flavor-logged the first time, then debounced.
## No-ops entirely once the lair aura is switched off -- see the flag.
func _check_necromancer_fear(wolf: Wolf) -> void:
	if not _near_necromancer(wolf.position):
		return
	wolf.clear_target()
	# Push it back out the way it came.
	wolf.position += (wolf.position - villain.position).normalized() * 12.0
	if _necro_fear_cooldown <= 0.0:
		_necro_fear_cooldown = 20.0
		EventBus.necromancer_feared.emit("wolf")

## Rule 3. The deer is emptied outright rather than damaged -- the wolf takes the
## whole animal exactly as a hunter would (ResourceNode.make_deer's
## yield_per_action is the same 8), the food never reaches the player, and the
## wolf stands down for the night.
##
## It does **not** leave. An earlier version had it depart on the spot, which
## read cleanly in the log and terribly on screen: the wolf was off the map
## seconds after arriving and the player never saw it. "Stops hunting for the
## rest of the day" is also what the design actually asked for. It slinks off at
## dawn like any other wolf (see _on_dawn).
func _take_deer(wolf: Wolf, deer) -> void:
	deer.take(deer.remaining)
	wolf.is_fed = true
	wolf.clear_target()
	EventBus.deer_taken_by_predator.emit(deer, "wolf")

# ---------------- Fights ----------------

## Public entry point for "this unit and that wolf are now fighting", whoever
## started it. Adds to the existing fight if one is already running against that
## wolf, so three rallied skeletons converging on the same wolf produce one
## three-defender Engagement rather than three separate duels.
##
## Called by UndeadCommand when a bound skeleton closes on a wolf -- the roles
## are nominally reversed there (the skeleton is the aggressor) but combat is
## symmetric, both sides swing, so the Engagement doesn't care who is filed as
## the attacker.
func engage(wolf: Wolf, unit) -> void:
	if wolf == null or unit == null or not is_instance_valid(wolf):
		return
	var existing := _engagement_for(wolf)
	if existing:
		if existing.add_defender(unit):
			unit.in_combat = true
			unit.abandon_trip()
		return
	_begin_fight(wolf, unit)

func _engagement_for(wolf: Wolf) -> Engagement:
	for e in _engagements:
		if e.attacker == wolf:
			return e
	return null

func _begin_fight(wolf: Wolf, defender) -> void:
	if not Combat.is_combatant(wolf) or not Combat.is_combatant(defender):
		push_warning("CombatSystem: refusing to start a fight with a non-Combatant.")
		return
	var e := Engagement.new(wolf)
	e.add_defender(defender)
	defender.in_combat = true
	defender.abandon_trip()
	wolf.state = Wolf.State.FIGHT
	_engagements.append(e)
	EventBus.combat_started.emit(wolf.combat_name(), defender.combat_name())
	_rally_and_scatter(wolf, e)

## The emergent-defence rule, and the reason this is worth building before
## guard posts exist: **nobody is ordered to fight.** Any Warrior-category or
## Might >= 6 recruit close enough to see it wades in on their own; everyone
## else drops what they're carrying and runs. The player's only lever is who
## they recruited and where those people happen to be -- which is the Majesty
## indirect-control pillar applied to defence.
func _rally_and_scatter(wolf: Wolf, e: Engagement) -> void:
	if worker_system == null:
		return
	for l in worker_system.all_units():
		if l.in_combat or not l.is_alive():
			continue
		if l.position.distance_to(wolf.position) > ASSIST_RADIUS_PX:
			continue
		# Skeletons neither rally nor scatter (see _will_fight) -- and a rallied
		# one is under standing orders that outrank a panic, so it is skipped
		# entirely rather than being told to run.
		if not (l is Follower):
			continue
		if _will_fight(l):
			e.add_defender(l)
			l.in_combat = true
			l.abandon_trip()
			EventBus.combat_joined.emit(l, wolf.combat_name())
		else:
			l.begin_flee()

## Skeleton Workers are never volunteers -- they have no self-preservation to
## override and, unless the Necromancer has bound them to a rally point, no
## orders to act on either. They neither rally nor scatter; they carry on until
## something bites them. Only living recruits react on their own.
##
## (Caller already excludes non-Followers, so this is the same rule stated
## twice on purpose -- it is the sort of thing a later edit gets wrong.)
func _will_fight(l) -> bool:
	if not (l is Follower):
		return false
	return l.category == "Warrior" or l.might >= ASSIST_MIGHT_THRESHOLD

func _advance_engagement(e: Engagement, delta: float) -> void:
	var wolf: Wolf = e.attacker
	if wolf == null or not is_instance_valid(wolf):
		_finish(e)
		return

	for result in e.tick(delta):
		var defender = result["defender"]
		# Consequences are checked per exchange, not per frame, so a unit can
		# never take two lethal hits before anyone notices.
		if not defender.is_alive():
			_resolve_defeat(defender, wolf)
			e.remove_defender(defender)
		elif defender is Follower and defender.hp_fraction() < Combat.FLEE_HP_FRACTION:
			_injure_and_flee(defender, wolf)
			e.remove_defender(defender)

	if not wolf.is_alive():
		# **Killed outright**, which is the good outcome and now pays for itself:
		# the body is left on the map as a carcass any labourer can gather. It
		# reuses the ordinary carcass node, so hauling a dead wolf home is the
		# same trip as hauling any other bones -- no new mechanic, and the
		# reward for defending the settlement is a real one.
		for d in e.defenders:
			d.in_combat = false
		_leave_carcass(wolf)
		wolf.leave_reason = "killed"
		_despawn(wolf)
		_finish(e)
		return

	if wolf.should_flee():
		# Hurt but alive: it breaks off and leaves. No body, no bones -- driving
		# it away is the cheap win and killing it is the paying one.
		for d in e.defenders:
			d.in_combat = false
		wolf.depart("beaten off")
		_finish(e)
		return

	if not e.has_defenders():
		# Everyone it was fighting is gone -- back to prowling, unless the fight
		# was the last thing it needed.
		wolf.state = Wolf.State.PROWL
		wolf.clear_target()
		_finish(e)

## Drops a gatherable carcass where the wolf fell. Added to ResourceField the
## same way the seeded ones are, so the priority list, the crowding rules and
## the inspection panel all pick it up with no special casing -- a dead wolf is
## simply another pile of bones that happens to have arrived late.
func _leave_carcass(wolf: Wolf) -> void:
	if resource_field == null:
		return
	var carcass := ResourceNode.make_carcass(wolf.position)
	carcass.capacity = WOLF_CARCASS_BONES
	carcass.remaining = WOLF_CARCASS_BONES
	# Drawn at the same size as the seeded carcasses, from their constant rather
	# than a literal: sizes are content heights now, and a bare 28.0 here was a
	# leftover canvas-width number that would have quietly meant something else.
	resource_field.add_node(carcass, ResourceField.SPRITE_CARCASS, "", ResourceField.NODE_SIZE_CARCASS)
	EventBus.wolf_killed.emit(wolf.position, WOLF_CARCASS_BONES)

func _finish(e: Engagement) -> void:
	e.finished = true
	for d in e.defenders:
		d.in_combat = false
	_engagements.erase(e)

func _end_engagements_with(wolf: Wolf) -> void:
	for e in _engagements.duplicate():
		if e.attacker == wolf:
			_finish(e)

## Rule 1. Only ever reached by a Worker -- a Follower is pulled out at 30% by
## _injure_and_flee well before hp hits zero, which is what makes "living
## recruits are never killed by wildlife" true by construction rather than by a
## check at the moment of death.
func _resolve_defeat(unit, wolf: Wolf) -> void:
	unit.in_combat = false
	if unit is Worker:
		unit.abandon_trip()
		worker_system.remove_worker(unit)
		EventBus.worker_destroyed.emit(unit, wolf.combat_name())
		return
	# Defensive: a Follower should never get here. If one does, treat it as an
	# injury rather than a death, so the design rule holds even if a future
	# caller skips the flee check.
	push_warning("CombatSystem: a Follower reached 0 hp -- injuring instead of killing.")
	unit.hp = 1
	_injure_and_flee(unit, wolf)

## Rule 2.
func _injure_and_flee(f, wolf: Wolf) -> void:
	f.in_combat = false
	f.is_injured = true
	f.adjust_morale(-1)
	f.begin_flee()
	EventBus.morale_changed.emit(f, f.morale)
	EventBus.recruit_injured.emit(f, wolf.combat_name())

# ---------------- Hit-point maintenance ----------------

## Necromantic repair. Idle skeletons standing near the Throne slowly knit back
## together; living recruits heal from meals instead (MoraleSystem), which is
## the mechanical shape of "the undead don't eat" cutting both ways -- free to
## run, but they can only be mended at home.
func _tick_throne_repair(delta: float) -> void:
	if worker_system == null or settlement == null:
		return
	_repair_timer += delta
	if _repair_timer < THRONE_REPAIR_SECONDS:
		return
	_repair_timer -= THRONE_REPAIR_SECONDS
	var throne: Building = settlement.get_main_building()
	if throne == null:
		return
	var half: float = float(SettlementGrid.CELL_SIZE) * 0.5
	var throne_pos := Vector2(throne.cell.x * SettlementGrid.CELL_SIZE + half,
		throne.cell.y * SettlementGrid.CELL_SIZE + half)
	for w in worker_system.workers:
		if w.in_combat or w.hp >= w.max_hp():
			continue
		if w.stage != Laborer.TripStage.IDLE:
			continue
		if w.position.distance_to(throne_pos) <= THRONE_REPAIR_RADIUS_PX:
			w.heal(1)

# ---------------- Queries (HUD / smoke tests) ----------------

func active_wolf() -> Wolf:
	return wolves[0] if not wolves.is_empty() else null

func is_fighting() -> bool:
	return not _engagements.is_empty()
