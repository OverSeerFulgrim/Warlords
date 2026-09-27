extends Node
## GameState (Autoload singleton)
## Resources, reputation, threat, and followers -- read and written through here
## rather than by poking at other systems directly.
##
## **A facade over the player's settlement since L0** (LIVING_WORLD_SPEC ruling
## 13, 2026-09-26). Each settlement owns its own stockpile, population and Power
## (`Settlement.gd`); the player's is `player_settlement`, and `wood`,
## `followers`, `power` and the rest below are properties that read and write it.
## Every existing caller -- the HUD, the build menu, the harnesses -- keeps
## saying `GameState.wood` and is really talking to the player's settlement. The
## village has its own Settlement and never touches GameState.

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

# --- The player's settlement (the facade's backing store) ---

## Starting values are FOUNDATION_SPEC section 10's Stage-0 table: 8 wood, 5
## stone, 5 food and **3 bones** -- below Raise Dead's 5 (ruling 2026-09-26), so
## the first dead must come from a grave, never from the stockpile on minute one.
## Dark essence, gold and arms start at 0: lootable sites are their only source.
const STARTING_STOCK := {"wood": 8, "stone": 5, "food": 5, "bones": 3,
	"dark_essence": 0, "gold": 0, "arms": 0}

var player_settlement: Settlement = _new_player_settlement()

func _new_player_settlement() -> Settlement:
	var s := Settlement.new("lair", "villain", "The Lair")
	for k in STARTING_STOCK.keys():
		s.stockpile[k] = int(STARTING_STOCK[k])
	s.stockpile_changed.connect(func(): resources_changed.emit())
	return s

# --- Resources (properties over player_settlement) ---
# dark_essence is the "magic" resource, field loot only (LOOT_SITES_SPEC
# section 5). Gold is the sixth resource and the first field-only spendable one;
# its sinks arrive with R3 (Wealth) and R5 (stash value). Arms is the seventh
# (designer-approved 2026-08-30): it banks and does nothing until COMBAT_SPEC
# section 9's gear v1 -- the HUD shows it only once you have some.
var dark_essence: int:
	get: return player_settlement.amount("dark_essence")
	set(v): player_settlement.set_amount("dark_essence", v)
var bones: int:
	get: return player_settlement.amount("bones")
	set(v): player_settlement.set_amount("bones", v)
var wood: int:
	get: return player_settlement.amount("wood")
	set(v): player_settlement.set_amount("wood", v)
var stone: int:
	get: return player_settlement.amount("stone")
	set(v): player_settlement.set_amount("stone", v)
var food: int:
	get: return player_settlement.amount("food")
	set(v): player_settlement.set_amount("food", v)
var gold: int:
	get: return player_settlement.amount("gold")
	set(v): player_settlement.set_amount("gold", v)
var arms: int:
	get: return player_settlement.amount("arms")
	set(v): player_settlement.set_amount("arms", v)

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
var power: int:
	get: return player_settlement.power
	set(v): player_settlement.power = v
const POWER_WIN_THRESHOLD: int = 50
var survived_high_threat_crusade: bool = false
var _last_building_power: int = 0  # cached so follower-only changes can also trigger a recompute

# --- Followers ---
## The player's recruits (`Follower`s) -- the settlement's population.
var followers: Array:
	get: return player_settlement.followers
	set(v): player_settlement.followers = v

## Everyone who has left, with how they felt about it. **Data only** -- nothing
## reads this yet. It exists so the departure-memory system (GAME_OUTLINE gap
## #6: sent-away recruits "return later with a gift" or "hate you and ambush
## your villagers") has a history to work from when it's built, rather than
## starting from nothing. Each entry:
##   {name, species, race_id, disposition, reason, day}
## `disposition` is Follower.departure_disposition() -- negative = resentful.
var departed: Array = []  # Array[Dictionary]

func record_departure(follower, reason: String, day: int) -> void:
	departed.append({
		"name": follower.follower_name,
		"species": follower.species,
		"race_id": follower.race_id,
		"disposition": follower.departure_disposition(),
		"reason": reason,
		"day": day,
	})

func _ready() -> void:
	print("[GameState] ready. dark_essence=%d bones=%d wood=%d stone=%d food=%d gold=%d" % [dark_essence, bones, wood, stone, food, gold])

# ---------------- Resources ----------------

func add_resource(kind: String, amount: int) -> void:
	if not Settlement.KINDS.has(kind):
		push_warning("GameState.add_resource: unknown kind '%s'" % kind)
		return
	player_settlement.add(kind, amount)

## Checks affordability without spending -- used by the build menu to grey
## out / reject placements before committing the spend.
func can_afford(kind: String, amount: int) -> bool:
	return player_settlement.can_afford(kind, amount)

## Checks a full cost Dictionary (e.g. {"bones": 6, "dark_essence": 4}) at once.
func can_afford_cost(cost: Dictionary) -> bool:
	return player_settlement.can_afford_cost(cost)

func spend_resource(kind: String, amount: int) -> bool:
	if not Settlement.KINDS.has(kind):
		push_warning("GameState.spend_resource: unknown kind '%s'" % kind)
		return false
	return player_settlement.spend(kind, amount)

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

# ---------------- Reset ----------------

## Returns every var back to its Stage-0 starting value so
## reload_current_scene() produces a fresh run rather than
## picking up where the old one left off. Called by
## Main._begin_new_run, the start of every new run.
func reset() -> void:
	# In place rather than a fresh Settlement: the relay to resources_changed
	# is connected once, in _new_player_settlement().
	for k in STARTING_STOCK.keys():
		player_settlement.stockpile[k] = int(STARTING_STOCK[k])
	player_settlement._deposit_carry.clear()
	player_settlement.prisoners.clear()
	player_settlement.stockpile_changed.emit()
	reputation = 0
	threat = 0
	threat_tier = ThreatTier.LOW
	power = 0
	survived_high_threat_crusade = false
	_last_building_power = 0
	_has_won = false
	followers.clear()
	departed.clear()

# ---------------- Followers ----------------

func add_follower(follower) -> void:
	followers.append(follower)
	EventBus.follower_count_changed.emit(followers.size())
	recompute_power(_last_building_power)

func remove_follower(follower) -> void:
	followers.erase(follower)
	EventBus.follower_count_changed.emit(followers.size())
	recompute_power(_last_building_power)
