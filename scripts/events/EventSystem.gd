extends Node
class_name EventSystem
## Loads data/events.json and periodically fires a random eligible event,
## applying whichever choice effect the player (or, for now, an autoplay
## stub) picks. UI layer listens to EventBus.event_triggered to show a popup;
## this script never touches UI directly.

const EVENTS_PATH := "res://data/events.json"
const FOLLOWERS_PATH := "res://data/followers.json"

@export var min_interval: float = 20.0
@export var max_interval: float = 45.0

## Set by Main.gd right after construction (same wiring pattern as camera/
## other systems). The Barracks gate below needs it.
var settlement: SettlementGrid

## Owns the first-run category guarantee's counter, so it has to be one
## long-lived instance rather than a static utility.
var recruit_generator := RecruitGenerator.new()

var _events: Array = []
var _follower_templates: Dictionary = {}
var _timer: float = 0.0
var _next_fire: float = 0.0

func _ready() -> void:
	_load_events()
	_load_follower_templates()
	_queue_next()
	set_process(true)

## **The Barracks is the event gate.** This replaced a hardcoded
## `EVENTS_ENABLED = false` const, which existed only because events used to
## fire from turn zero and drown out whatever else was being tested. Now
## there's a real in-fiction reason for the timer to be off at the start:
## GAME_OUTLINE Stage 2 ends with "Barracks built -> recruitment-event timer
## turns on", so until the player builds one, nobody comes.
##
## Note this gates on the Barracks *existing*, not on it having a free slot.
## A full Barracks still gets offers -- they just arrive with only turn-away
## choices (see _fire_recruit_offer). Fizzling the event entirely would make a
## full Barracks look identical to a broken event timer.
func events_enabled() -> bool:
	return settlement != null and settlement.has_barracks()

func _process(delta: float) -> void:
	if not events_enabled():
		return
	_timer += delta
	if _timer >= _next_fire:
		_timer = 0.0
		_queue_next()
		_fire_recruit_offer()

func _load_events() -> void:
	if not FileAccess.file_exists(EVENTS_PATH):
		push_warning("EventSystem: events.json not found at %s" % EVENTS_PATH)
		return
	var f := FileAccess.open(EVENTS_PATH, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null:
		push_warning("EventSystem: failed to parse events.json")
		return
	_events = parsed

func _load_follower_templates() -> void:
	if not FileAccess.file_exists(FOLLOWERS_PATH):
		push_warning("EventSystem: followers.json not found at %s" % FOLLOWERS_PATH)
		return
	var f := FileAccess.open(FOLLOWERS_PATH, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null:
		push_warning("EventSystem: failed to parse followers.json")
		return
	_follower_templates = parsed
	# followers.json has the same "_comment" documentation-key convention as
	# buildings.json. It's currently harmless here because _recruit() only
	# ever does a direct has()/[] lookup by a known template_id and never
	# iterates all keys -- but strip it anyway so this stays true even if
	# something here grows an all-keys iteration later (that's exactly the
	# bug BuildingCatalog.all_ids()/buildable_ids() hit).
	_follower_templates.erase("_comment")

func _queue_next() -> void:
	_next_fire = randf_range(min_interval, max_interval)

## The flavor/moral events in events.json are still loaded and still resolvable
## through resolve_event(), but they are **not on the timer** for the
## foundation build -- the timer fires recruit offers only, because Stage 3 is
## what's being proven. Several of those entries also still point their
## "recruit" effect at followers.json templates, which is the superseded
## generation path (see _recruit below). Reintroducing the flavor pool means
## mixing it back in here and porting those effects.
func _fire_random_event() -> void:
	if _events.is_empty():
		return
	var event: Dictionary = _events[randi() % _events.size()]
	EventBus.event_triggered.emit(event)

## Builds and fires one recruitment offer. The recruit is generated *before*
## the capacity check so the offer is always about a specific named person --
## you see who you're turning away, which is what makes a full Barracks feel
## like a cost rather than a silent no-op.
func _fire_recruit_offer() -> void:
	var recruit: Follower = recruit_generator.generate()
	if recruit == null:
		return
	var has_room: bool = settlement.barracks_free_slots() > 0
	var event := {
		"id": "recruit_offer",
		"category": "recruit",
		"title": "%s the %s" % [recruit.follower_name, recruit.species],
		"description": _describe(recruit, has_room),
		"recruit": recruit,
		# Recorded so refresh_recruit_offer() can tell whether the answer has
		# changed since the offer went up, rather than rebuilding every poll.
		"has_room": has_room,
		"choices": _offer_choices(has_room),
	}
	EventBus.event_triggered.emit(event)

## Re-evaluates an already-open recruit offer against the Barracks' **current**
## occupancy, rewriting its description and choices in place. Returns true if
## anything actually changed.
##
## The offer used to be a snapshot: whatever the capacity was at the instant it
## fired, that was the decision you were stuck with. So a player who saw
## "Barracks full", funded a house to make room, and came back to the still-open
## offer found the freed slot did nothing -- the two turn-away variants were the
## only choices until the offer expired and a *new* recruit turned up. An offer
## is a standing decision, and the world is allowed to move while you think.
##
## Works in both directions: a slot filled by a departing recruit or a second
## offer takes the accept option back away again.
func refresh_recruit_offer(event: Dictionary) -> bool:
	if event.get("id", "") != "recruit_offer":
		return false
	var recruit = event.get("recruit")
	if recruit == null or settlement == null:
		return false
	var has_room: bool = settlement.barracks_free_slots() > 0
	if has_room == bool(event.get("has_room", false)):
		return false
	event["has_room"] = has_room
	event["description"] = _describe(recruit, has_room)
	event["choices"] = _offer_choices(has_room)
	return true

func _describe(f: Follower, has_room: bool) -> String:
	var stars := " ★ exceptional" if f.is_exceptional else ""
	var line := "%s %s (%s)%s\nMight %d  Guile %d  Influence %d  Loyalty %d\nWood %d  Mine %d  Forage %d" % [
		f.rarity, f.category, f.species, stars,
		f.might, f.guile, f.influence, f.loyalty,
		f.woodcutting, f.mining, f.foraging,
	]
	if not has_room:
		# Says what to do about it, because you can: funding a house from the
		# Barracks panel frees a slot and this offer updates itself on the spot.
		line += "\n\n[Barracks full — %d/%d. Fund a house to free a slot and this offer will update.]" % [
			settlement.barracks_residents(), settlement.barracks_capacity()]
	return line

## A full Barracks still gets the offer, but every choice is a turn-away
## variant -- FOUNDATION_SPEC section 9's "Full Barracks = offer fizzles with a
## clear message", made legible rather than silent. The variants differ in how
## you turn them away, which is the hook departure-memory (GAME_OUTLINE gap #6)
## will hang off later.
func _offer_choices(has_room: bool) -> Array:
	if has_room:
		return [
			{"label": "Welcome them into the Barracks", "effects": {"accept_recruit": true, "reputation": 1}},
			{"label": "Turn them away", "effects": {"turn_away": true}},
		]
	return [
		{"label": "Send them on their way (no room)", "effects": {"turn_away": true}},
		{"label": "Drive them off (no room)", "effects": {"turn_away": true, "reputation": -1, "threat": 1}},
	]

## Called by the UI once the player picks a choice (or by an autoplay stub
## during headless testing). Applies the chosen effects to GameState.
func resolve_event(event: Dictionary, choice_index: int) -> void:
	var choices: Array = event.get("choices", [])
	if choice_index < 0 or choice_index >= choices.size():
		return
	var choice: Dictionary = choices[choice_index]
	var effects: Dictionary = choice.get("effects", {})
	# Recruit accept/decline is handled here rather than in _apply_effects
	# because it needs the *event* (which carries the generated Follower), not
	# just the effects Dictionary.
	if effects.get("accept_recruit", false):
		_accept_recruit(event.get("recruit"))
	elif effects.get("turn_away", false):
		_turn_away(event.get("recruit"))
	_apply_effects(effects)
	EventBus.event_resolved.emit(event, choice_index)

func _accept_recruit(f) -> void:
	if f == null:
		return
	# Re-checked at resolve time, not just at offer time: the player can leave
	# an offer open while a previous recruit fills the last slot.
	if settlement.barracks_free_slots() <= 0:
		print("[EventSystem] Barracks full -- %s turned away." % f.follower_name)
		EventBus.recruit_turned_away.emit(f, "the Barracks is full")
		return
	GameState.add_follower(f)
	EventBus.follower_recruited.emit(f)

func _turn_away(f) -> void:
	if f == null:
		return
	EventBus.recruit_turned_away.emit(f, "turned away")

func _apply_effects(effects: Dictionary) -> void:
	for key in effects.keys():
		var value = effects[key]
		match key:
			"dark_essence":
				if value >= 0:
					GameState.add_resource("dark_essence", value)
				else:
					GameState.spend_resource("dark_essence", -value)
			"bones":
				if value >= 0:
					GameState.add_resource("bones", value)
				else:
					GameState.spend_resource("bones", -value)
			"reputation":
				GameState.add_reputation(value)
			"threat":
				GameState.add_threat(value)
			"recruit":
				_recruit(value)
			"recruit_chance":
				_recruit_chance(value)
			_:
				pass

## **Superseded generation path.** Builds a Follower from a
## data/followers.json template. Recruit offers now roll off the race roster
## instead (see RecruitGenerator) -- richer, and per-individual varied. This
## remains only for the events.json entries that still reference template ids,
## which are off the timer; when those get ported, this and followers.json can
## both go.
##
## The old per-species housing hard gate that used to live here is **gone**.
## It checked `settlement.has_housing_for(species)` against the per-species
## housing buildings, and those became unbuildable when the foundation reset
## locked them -- which silently made every gated species impossible to
## recruit. Barracks capacity is the gate now, for both paths.
func _recruit(template_id: String) -> Follower:
	if not _follower_templates.has(template_id):
		push_warning("EventSystem: no follower template for '%s'" % template_id)
		return null
	if settlement and settlement.barracks_free_slots() <= 0:
		print("[EventSystem] Recruit blocked: no free Barracks slot.")
		return null
	var t: Dictionary = _follower_templates[template_id]

	var names: Array = t.get("names", ["Unnamed"])
	var follower_name: String = names[randi() % names.size()]

	var traits_pool: Array = t.get("traits_pool", [])
	var trait_count: int = t.get("trait_count", 1)
	var chosen_traits: Array[String] = []
	var pool_copy := traits_pool.duplicate()
	pool_copy.shuffle()
	for i in range(min(trait_count, pool_copy.size())):
		chosen_traits.append(pool_copy[i])

	var might := _roll_range(t.get("might", [1, 3]))
	var guile := _roll_range(t.get("guile", [1, 3]))
	var influence := _roll_range(t.get("influence", [1, 3]))
	var loyalty := _roll_range(t.get("loyalty", [3, 7]))

	var follower := Follower.new(follower_name, t.get("species", "Unknown"), chosen_traits,
		might, guile, influence, loyalty)
	GameState.add_follower(follower)
	EventBus.follower_recruited.emit(follower)
	return follower

## Same as _recruit, but gated behind the template's "chance" (0-100), used
## for events where the outcome should sometimes fail (e.g. a corruption
## attempt on a captured paladin).
func _recruit_chance(template_id: String) -> void:
	if not _follower_templates.has(template_id):
		push_warning("EventSystem: no follower template for '%s'" % template_id)
		return
	var t: Dictionary = _follower_templates[template_id]
	var chance: float = t.get("chance", 40.0)
	if randf() * 100.0 <= chance:
		_recruit(template_id)
	else:
		print("[EventSystem] Recruit-chance failed for '%s' (needed <= %s)." % [template_id, chance])

func _roll_range(range_arr: Array) -> int:
	if range_arr.size() < 2:
		return 1
	return randi_range(int(range_arr[0]), int(range_arr[1]))
