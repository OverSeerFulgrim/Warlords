extends Node
class_name MoraleSystem
## Meals, morale, misbehaviour and desertion -- FOUNDATION_SPEC section 8.
##
## This is the last unbuilt piece of the foundation day/night loop. The clock
## and its `dawn_started` / `dusk_started` signals already existed (see
## DayNightCycle, which deliberately emitted signals rather than calling
## anything directly, precisely so this could hang off them); what was missing
## was anyone eating.
##
## The loop, per meal tick:
##   1. Living recruits eat their race's `food_per_meal`. **Skeletons eat
##      nothing** -- undead labor is free to run, which is the whole undead
##      perk and why the player can survive Stage 1 with no food economy.
##   2. **Highest Loyalty eats first** when food is short. That ordering is
##      deliberate villain flavor from the spec: the faithful get fed and the
##      malcontents starve, which makes a low-Loyalty recruit a liability
##      exactly when you can least afford one.
##   3. Anyone shorted loses 1 morale. Anyone who cleared a whole cycle
##      without missing a meal gains 1 back (capped at 10).
##   4. Morale <= 3 risks theft/rule-breaking. Morale 1 gets one warning, then
##      leaves on the next missed meal.

## Chance per meal tick that a recruit at or below MISCHIEF_MORALE causes
## trouble. Per-recruit, so a settlement full of miserable people is
## proportionally more chaotic.
const MISCHIEF_MORALE: int = 3
const MISCHIEF_CHANCE_PERCENT: float = 25.0
const MISCHIEF_MIN: int = 1
const MISCHIEF_MAX: int = 3

## Morale at which the departure warning fires.
const DEPARTURE_MORALE: int = 1

## What a disgruntled recruit will help themselves to. Deliberately excludes
## dark_essence -- it's the locked Stage-4 resource and stealing it would be a
## confusing loss of something the player has no way to replace yet.
const STEALABLE := ["food", "wood", "stone", "bones"]

const MISCHIEF_FLAVOR := [
	"%s was caught pilfering the stores (%d %s gone).",
	"%s broke into the stockpile -- %d %s missing.",
	"%s traded away %d %s for something stronger than water.",
	"%s 'lost' %d %s and will not say where.",
]

## Set by Main after construction, same wiring convention as the other systems.
var day_night: DayNightCycle = null

## Food/meal values are fractional (a Kobold eats 0.5, a Troll 3.5) but
## GameState.food is a whole-unit resource that Workers deposit into. Rather
## than making the resource a float and rippling that through the UI and every
## deposit, the meal tick spends whole units and carries the remainder here.
## Without this a Kobold and a Gray Dwarf would cost the same to feed, which
## erases the "cheap-to-feed swarm vs elite specialist" tradeoff the roster is
## built around.
var _food_remainder: float = 0.0

func _ready() -> void:
	EventBus.dawn_started.connect(_on_dawn)
	EventBus.dusk_started.connect(_on_dusk)

## Dawn is also the cycle boundary: score the *previous* cycle for the
## fed-all-day bonus before anyone eats, then reset the counters and serve.
func _on_dawn(_day_number: int) -> void:
	_score_previous_cycle()
	_serve_meal("Dawn")

func _on_dusk(_day_number: int) -> void:
	_serve_meal("Dusk")

## "A full day with food regains 1 morale." Requires missing nothing and having
## eaten at least once -- the "at least once" matters for a recruit who arrived
## at dusk and so only had one meal in the cycle; they shouldn't be denied the
## bonus for a cycle they weren't present for.
func _score_previous_cycle() -> void:
	for f in GameState.followers:
		if f.meals_missed_this_cycle == 0 and f.meals_eaten_this_cycle > 0 and f.morale < Follower.MORALE_MAX:
			f.adjust_morale(1)
			EventBus.morale_changed.emit(f, f.morale)
		f.meals_eaten_this_cycle = 0
		f.meals_missed_this_cycle = 0

func _serve_meal(phase: String) -> void:
	var eaters := _living_recruits_by_loyalty()
	if eaters.is_empty():
		return

	# One shared pool for the whole sitting, so the fractional remainder can't
	# be double-spent between two recruits in the same tick.
	var pool: float = float(GameState.food) + _food_remainder
	var fed: int = 0
	var shorted: Array = []

	for f in eaters:
		var need: float = RaceCatalog.food_per_meal(f.race_id)
		if need <= 0.0:
			continue  # undead; shouldn't reach here, but harmless
		if pool >= need:
			pool -= need
			f.meals_eaten_this_cycle += 1
			fed += 1
			_regenerate(f)
		else:
			f.meals_missed_this_cycle += 1
			f.adjust_morale(-1)
			EventBus.morale_changed.emit(f, f.morale)
			shorted.append(f)

	_write_back_food(pool)
	EventBus.meal_served.emit(phase, fed, shorted.size())

	# Consequences after the whole sitting is resolved, not mid-loop -- a
	# departure removes someone from GameState.followers, and mutating that
	# while iterating it is how you get a skipped element.
	for f in shorted:
		_handle_shorted(f)
	_roll_mischief()

## Healing is a consequence of eating, so it lives in the meal loop rather than
## in CombatSystem: **living units regenerate +2 hp per meal actually eaten.**
## A recruit who goes hungry doesn't heal, which is what ties the injury system
## to the food economy instead of leaving it on a separate timer -- a wolf that
## mauls your orc during a famine has done real, compounding damage.
##
## Clearing the Injured flag is also here, because reaching full health is the
## only thing that clears it and this is where health goes up. (Skeletons have
## no path through here at all: they eat nothing, and repair at the Throne
## instead -- see CombatSystem._tick_throne_repair.)
const HEAL_PER_MEAL: int = 2

func _regenerate(f) -> void:
	if f.hp >= f.max_hp():
		return
	f.heal(HEAL_PER_MEAL)
	if f.is_injured and f.hp >= f.max_hp():
		f.is_injured = false
		EventBus.recruit_recovered.emit(f)

## Spends the whole units consumed and keeps the sub-unit remainder for next
## time. `pool` is what's left after the sitting.
func _write_back_food(pool: float) -> void:
	var new_food: int = maxi(0, floori(pool))
	var spent: int = GameState.food - new_food
	if spent > 0:
		GameState.spend_resource("food", spent)
	_food_remainder = pool - float(new_food)

## Living recruits only, highest Loyalty first (FOUNDATION_SPEC section 8).
## Skeleton Workers aren't here at all -- they're `Worker`s, not on the
## follower roster. Any *follower* whose race eats nothing is filtered by the
## food_per_meal check.
func _living_recruits_by_loyalty() -> Array:
	var out: Array = []
	for f in GameState.followers:
		if RaceCatalog.food_per_meal(f.race_id) > 0.0:
			out.append(f)
	out.sort_custom(func(a, b): return a.loyalty > b.loyalty)
	return out

func _handle_shorted(f) -> void:
	if not GameState.followers.has(f):
		return  # already gone this tick
	if f.morale > DEPARTURE_MORALE:
		return
	if not f.departure_warned:
		f.departure_warned = true
		EventBus.recruit_departure_warning.emit(f)
		return
	# Warned already, and shorted again: they're done.
	_depart(f, "starved out")

func _depart(f, reason: String) -> void:
	var day: int = day_night.day_number if day_night else 0
	GameState.record_departure(f, reason, day)
	f.abandon_trip()  # release any claim they held on a resource node
	GameState.remove_follower(f)
	EventBus.recruit_departed.emit(f, reason)

## Theft / rule-breaking. Logged rather than raised as a blocking popup: the
## event panel is the recruit-offer channel, and a modal dialog every time a
## hungry goblin skims the stores would be exhausting. The player still can't
## miss it -- these fire an alert pin and a coloured History entry.
func _roll_mischief() -> void:
	for f in GameState.followers:
		if f.morale > MISCHIEF_MORALE:
			continue
		if randf() * 100.0 > MISCHIEF_CHANCE_PERCENT:
			continue
		var kind: String = STEALABLE[randi() % STEALABLE.size()]
		var amount: int = randi_range(MISCHIEF_MIN, MISCHIEF_MAX)
		# Never steal more than exists -- a negative stockpile would be a much
		# worse bug than a theft that comes up short.
		amount = mini(amount, _stock_of(kind))
		if amount <= 0:
			continue
		GameState.spend_resource(kind, amount)
		var flavor: String = MISCHIEF_FLAVOR[randi() % MISCHIEF_FLAVOR.size()]
		EventBus.recruit_misbehaved.emit(f, flavor % [f.follower_name, amount, kind], kind, amount)

func _stock_of(kind: String) -> int:
	match kind:
		"food":
			return GameState.food
		"wood":
			return GameState.wood
		"stone":
			return GameState.stone
		"bones":
			return GameState.bones
		_:
			return 0

## Settlement-average morale, for a HUD summary. Per-recruit values are the
## real data (see Follower.morale); this is only ever a display convenience.
func average_morale() -> float:
	if GameState.followers.is_empty():
		return 0.0
	var total: int = 0
	for f in GameState.followers:
		total += f.morale
	return float(total) / float(GameState.followers.size())
