extends Node
## GameState (Autoload singleton)
## Central source of truth for resources, reputation, threat, and followers.
## Everything else in the prototype reads/writes through this rather than
## poking at other systems directly, so behavior stays easy to reason about.

## Zero-args on purpose: its only listener (Main.gd) already just calls
## _update_stats_label(), which reads GameState's vars directly rather than
## via signal params -- so every resource type added (Wood/Stone here) would
## otherwise mean growing this signature again for no real benefit.
signal resources_changed
signal reputation_changed(new_value: int)
signal threat_changed(new_value: int, tier: int)
signal power_changed(new_value: int)
signal game_won
signal game_lost(reason: String)

enum ThreatTier { LOW, MEDIUM, HIGH }

# --- Resources ---
# dark_essence stays a separate "magic" resource tied to ritual/harvest
# bounties, not something workers gather -- wood/stone/bones/food are the
# four mundane resources. Food is the newest of them (FOUNDATION_SPEC
# section 8): only living recruits eat, undead labor eats nothing, so it
# sits idle at the starting 5 until Stage 3 brings the first living recruit.
# Starting values are FOUNDATION_SPEC section 10's Stage-0 table -- dark
# essence starts at 0 because harvest bounties (its only source) are locked.
var dark_essence: int = 0
var bones: int = 10
var wood: int = 8
var stone: int = 5
var food: int = 5

# --- Reputation / Threat ---
var reputation: int = 0
var threat: int = 0
var threat_tier: int = ThreatTier.LOW

const THREAT_MEDIUM_AT: int = 30
const THREAT_HIGH_AT: int = 70
const THREAT_MAX: int = 100

# --- Power / win condition ---
# "Both" win condition per design doc: player must (a) survive the High
# Threat tier crusade event, AND (b) reach a power threshold. Power is a
# simple derived stat for the prototype: buildings + followers, weighted.
var power: int = 0
const POWER_WIN_THRESHOLD: int = 50
var survived_high_threat_crusade: bool = false
var _last_building_power: int = 0  # cached so follower-only changes can also trigger a recompute

# --- Followers ---
var followers: Array = []  # Array[Follower]

func _ready() -> void:
	print("[GameState] ready. dark_essence=%d bones=%d wood=%d stone=%d food=%d" % [dark_essence, bones, wood, stone, food])

# ---------------- Resources ----------------

func add_resource(kind: String, amount: int) -> void:
	match kind:
		"dark_essence":
			dark_essence += amount
		"bones":
			bones += amount
		"wood":
			wood += amount
		"stone":
			stone += amount
		"food":
			food += amount
		_:
			push_warning("GameState.add_resource: unknown kind '%s'" % kind)
			return
	resources_changed.emit()

## Checks affordability without spending -- used by the build menu to grey
## out / reject placements before committing the spend.
func can_afford(kind: String, amount: int) -> bool:
	match kind:
		"dark_essence":
			return dark_essence >= amount
		"bones":
			return bones >= amount
		"wood":
			return wood >= amount
		"stone":
			return stone >= amount
		"food":
			return food >= amount
		_:
			return false

## Checks a full cost Dictionary (e.g. {"bones": 6, "dark_essence": 4}) at once.
func can_afford_cost(cost: Dictionary) -> bool:
	for kind in cost.keys():
		if not can_afford(kind, cost[kind]):
			return false
	return true

func spend_resource(kind: String, amount: int) -> bool:
	match kind:
		"dark_essence":
			if dark_essence < amount:
				return false
			dark_essence -= amount
		"bones":
			if bones < amount:
				return false
			bones -= amount
		"wood":
			if wood < amount:
				return false
			wood -= amount
		"stone":
			if stone < amount:
				return false
			stone -= amount
		"food":
			if food < amount:
				return false
			food -= amount
		_:
			push_warning("GameState.spend_resource: unknown kind '%s'" % kind)
			return false
	resources_changed.emit()
	return true

# ---------------- Reputation / Threat ----------------

func add_reputation(amount: int) -> void:
	reputation = max(0, reputation + amount)
	reputation_changed.emit(reputation)

func add_threat(amount: int) -> void:
	var old_tier := threat_tier
	threat = clamp(threat + amount, 0, THREAT_MAX)
	threat_tier = _compute_tier(threat)
	threat_changed.emit(threat, threat_tier)
	if threat_tier != old_tier:
		EventBus.threat_tier_escalated.emit(threat_tier)
	if threat_tier == ThreatTier.HIGH and old_tier != ThreatTier.HIGH:
		EventBus.crusade_incoming.emit()

func lay_low(amount: int = 10) -> void:
	# Deliberately cooling off: reduces Threat but does not undo Reputation.
	add_threat(-amount)

func _compute_tier(value: int) -> int:
	if value >= THREAT_HIGH_AT:
		return ThreatTier.HIGH
	elif value >= THREAT_MEDIUM_AT:
		return ThreatTier.MEDIUM
	else:
		return ThreatTier.LOW

# ---------------- Power / Win-Loss ----------------

## building_power is the sum of every placed building's power_value (see
## SettlementGrid._total_building_power()) -- NOT a building count. Used to
## be a flat "count * 5" placeholder that made buildings.json's per-building
## power_value fields dead data; now each building's individual value
## actually counts. Followers are still a flat 3 each -- no per-follower
## power stat exists yet, tune once real balancing starts.
func recompute_power(building_power: int) -> void:
	_last_building_power = building_power
	power = building_power + followers.size() * 3
	power_changed.emit(power)
	_check_win_condition()

func mark_crusade_survived() -> void:
	survived_high_threat_crusade = true
	_check_win_condition()

var _has_won: bool = false  # latch -- without this, every recompute_power() after
                             # the win conditions are already met re-fires game_won

func _check_win_condition() -> void:
	if _has_won:
		return
	if survived_high_threat_crusade and power >= POWER_WIN_THRESHOLD:
		_has_won = true
		game_won.emit()

func lose_game(reason: String) -> void:
	game_lost.emit(reason)

# ---------------- Followers ----------------

func add_follower(follower) -> void:
	followers.append(follower)
	EventBus.follower_count_changed.emit(followers.size())
	recompute_power(_last_building_power)

func remove_follower(follower) -> void:
	followers.erase(follower)
	EventBus.follower_count_changed.emit(followers.size())
	recompute_power(_last_building_power)
