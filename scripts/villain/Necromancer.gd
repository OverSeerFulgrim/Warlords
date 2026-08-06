class_name Necromancer
extends RefCounted
## **The villain, as data.** Position, hit points, Might, what he is carrying,
## who walks with him. `NecromancerToken` is a pure view over this object and
## owns nothing -- the same contract `Laborer`/`WorkerToken` already follow.
##
## ## Why this file exists now
##
## The token used to own his position, with a documented exception in CLAUDE.md
## and an equally documented migration trigger: *the moment any other system
## needs to know where he is, split it.* Three systems now do -- the camera
## follows him, `Combat.exchange()` hits him, and the keyboard drives him -- so
## the split has happened. There is exactly one authoritative position again.
##
## ## Per-villain state, not global state
##
## ROGUELITE_REWORK section 11: **no system may assume there is exactly one
## villain on the map.** None of this lives in `GameState` or any other
## autoload, and nothing here is a singleton. `Main` holds a reference to one
## instance; every system that needs "the villain" takes it as a field or a
## parameter (see `CombatSystem.villain`, `VillainController.villain`). That
## discipline is the entire present-day cost of keeping the Demonologist and
## multiplayer possible, and retrofitting it later is the expensive version.
##
## Practical consequence for anything added here: if you catch yourself writing
## `GameState.necromancer_hp` or a static `Necromancer.current`, that's the
## mistake this class exists to prevent.
##
## ## What he is NOT
##
## He is **not a `Laborer`** and must never become one. `WorkerSystem.laborers()`
## is the union of `workers` and `GameState.followers`; he is in neither, so
## there is no path by which he can be handed a gathering trip or counted in
## the workforce summary. That exclusion is structural rather than a flag
## someone has to remember to check. He extends RefCounted directly rather than
## Laborer for exactly this reason -- sharing the trip-loop base class would put
## him one `laborers()` change away from being labour.

## Which villain class this is. A string rather than an enum because the class
## roster is content (ROGUELITE_REWORK section 11 -- the Demonologist is class
## two) and content is data in this project.
const CLASS_ID := "necromancer"

## Commissioned portrait used by the inspection payload and HUD badge.
const PORTRAIT := "res://assets/official/characters/Necromancer_Portrait.png"

## Full-body art used only by the settlement map token.
const MAP_SPRITE := "res://assets/official/characters/Necromancer_Full_Body.png"

# ---------------- Tunables (ROGUELITE_REWORK section 15 lists these as open) --

## His combat stat, and therefore his durability (`max_hp` below) and his carry
## capacity. **Tunable, and currently a first guess:** at Might 6 he has 20 hp
## and beats a lone wolf (Might 5, 18 hp) without walking away clean. Section 15
## flags "Necromancer combat stats" as an open question; this is the number to
## move when it gets answered.
const BASE_MIGHT: int = 6

## Cells per second while the player is holding a movement key. **Tunable.**
## Deliberately faster than a Skeleton Worker's 0.9 (he is the player, and
## trudging is not a fantasy) but not so fast that the settlement reads as small
## -- 1.4 crosses the 12-cell grid in about 8.5 seconds. Speed is in *cells* for
## the same reason walk_speed is (FOUNDATION_SPEC section 4): 1.0 = one grid
## cell per second, literally.
const MOVE_SPEED_CELLS: float = 1.0

## How long without a movement key before the idle pacing resumes. **Tunable.**
const IDLE_RESUME_SECONDS: float = 8.0

## The old pacing behaviour, demoted from "what he does" to "what he does when
## you leave him alone". Radius is around wherever he stopped, not around the
## Throne -- he is a unit you park now, not a fixture of the keep.
const IDLE_WANDER_CELLS: float = 2.0
const IDLE_WALK_SPEED_PX: float = 22.0
const IDLE_PAUSE_MIN: float = 2.5
const IDLE_PAUSE_MAX: float = 6.0

# ---------------- State ------------------------------------------------------

var class_id: String = CLASS_ID

## Authoritative map position. The token reads it; nothing else writes it.
var position: Vector2 = Vector2.ZERO

var might: int = BASE_MIGHT

## Current hit points. Initialised by heal_full() below -- see max_hp() for why
## the maximum is never stored.
var hp: int = 1

## What he is hauling, `resource kind -> amount`. A Dictionary rather than the
## single kind/amount pair a Laborer carries, because a sortie brings back a
## mixed load (ROGUELITE_REWORK section 8) while a worker trip is one resource
## by construction. Nothing banks it yet -- that is R2's deposit-at-the-lair
## step -- but the capacity is real and the inspection panel reads it.
var carried: Dictionary = {}

## Who is walking with him. Empty for the whole of R1: the escort arrives in R2
## with the sortie loop, built on the Command Undead order model rather than
## per-unit orders (ROGUELITE_REWORK section 5). It exists now so that every
## system reading "the villain" already sees the field it will eventually need.
var escort: Array = []

## Optional soft fence, set by whoever owns the map. Zero-size means unbounded.
## Belt to `world`'s braces: the world map's blocking rim already stops him at
## the edge, and this catches the case where there is no map at all (tests).
var bounds: Rect2 = Rect2()

## The terrain he walks. A **reference handed in** like everything else about
## him -- he does not look it up, and a second villain on a second map would
## simply hold a different one. Null-safe: with no world he walks on water.
var world: WorldMap = null

## -1 / +1, last horizontal direction of travel. The token flips its sprite on
## it -- facing is simulation state for the same reason position is, since idle
## pacing and player input both change it and only one of them is on screen.
var facing_x: float = 1.0

## True on any frame the player actually drove him. Read by the inspection
## panel's Activity row.
var is_moving: bool = false

## Seconds since the last movement input. Once past IDLE_RESUME_SECONDS the
## pacing below takes over.
var idle_seconds: float = 0.0

var _idle_anchor: Vector2 = Vector2.ZERO
var _idle_target: Vector2 = Vector2.ZERO
var _idle_pause: float = 0.0
var _pacing: bool = false

## Death is announced once. `take_damage` is the only route to zero hp and
## Combat.exchange() will happily land another swing on a corpse in the same
## frame, so without this the signal fires twice.
var _death_announced: bool = false

func _init(start_position: Vector2 = Vector2.ZERO) -> void:
	position = start_position
	_idle_anchor = start_position
	_idle_target = start_position
	heal_full()

## Places him without any of the movement bookkeeping thinking he walked there.
func place_at(p: Vector2) -> void:
	position = p
	_reset_idle(p)

# ---------------- Movement ---------------------------------------------------

## Pixels per second under player control. Same cells-per-second convention as
## `Laborer.walk_speed_px()`.
func move_speed_px() -> float:
	return MOVE_SPEED_CELLS * float(SettlementGrid.CELL_SIZE)

## One frame of movement. `move_dir` is the raw (unnormalised) key vector from
## whoever is reading input -- `Vector2.ZERO` when nothing is held.
##
## Both halves of "hold to move" and "idle pacing resumes" live here rather than
## in the controller, because both write `position` and position has exactly one
## owner. The controller decides *what the player asked for*; this decides where
## he ends up.
func step(move_dir: Vector2, delta: float) -> void:
	is_moving = false
	if move_dir != Vector2.ZERO:
		# Any input cancels pacing instantly -- no easing out of it, no walking
		# the last step of a wander first. The player pressed a key; he moves.
		_reset_idle(position)
		var motion: Vector2 = move_dir.normalized() * move_speed_px() * terrain_speed() * delta
		_move_by(motion)
		is_moving = true
		return

	idle_seconds += delta
	if idle_seconds < IDLE_RESUME_SECONDS:
		return
	if not _pacing:
		# Around wherever he was left standing, not around the Throne.
		_pacing = true
		_idle_anchor = position
		_pick_idle_target()
	_advance_pacing(delta)

## True while he has fallen back to the slow wander. Purely informational --
## the panel says so, and the smoke test asserts on it.
func is_pacing() -> bool:
	return _pacing

func _reset_idle(anchor: Vector2) -> void:
	idle_seconds = 0.0
	_pacing = false
	_idle_anchor = anchor
	_idle_target = anchor
	_idle_pause = 0.0

func _advance_pacing(delta: float) -> void:
	if _idle_pause > 0.0:
		_idle_pause -= delta
		return
	var to_target: Vector2 = _idle_target - position
	var stride: float = IDLE_WALK_SPEED_PX * delta
	if to_target.length() <= maxf(stride, 2.0):
		position = _idle_target
		_pick_idle_target()
		return
	_move_by(to_target.normalized() * stride)

func _pick_idle_target() -> void:
	var r: float = IDLE_WANDER_CELLS * float(SettlementGrid.CELL_SIZE)
	# Rejection-free polar pick, so he favours no particular direction. The sqrt
	# keeps the distribution even over the disc instead of clumping at the
	# centre.
	var angle: float = randf() * TAU
	var dist: float = sqrt(randf()) * r
	_idle_target = _idle_anchor + Vector2(cos(angle), sin(angle)) * dist
	_idle_pause = randf_range(IDLE_PAUSE_MIN, IDLE_PAUSE_MAX)

## What the ground under him does to his pace: 1.0 on open ground, more on a
## road. Roads being faster is the map doc's §9 tradeoff -- worth a detour, and
## worth the exposure that arrives with patrols in R3.
func terrain_speed() -> float:
	return world.speed_multiplier(position) if world else 1.0

## Blocking terrain is refused, but **slid along rather than stuck against**
## (see WorldMap.slide) -- walking a diagonal into a cliff should scrape past
## it, not stop you dead. Idle pacing goes through here too, so he can't drift
## into a lake while brooding.
func _move_by(motion: Vector2) -> void:
	if world:
		position = world.slide(position, motion)
	else:
		position += motion
	if bounds.size.x > 0.0 and bounds.size.y > 0.0:
		position = position.clamp(bounds.position, bounds.position + bounds.size)
	if absf(motion.x) > 0.01:
		facing_x = signf(motion.x)

# ---------------- Carrying ---------------------------------------------------

## Carry capacity = Might, the same rule every other unit follows
## (FOUNDATION_SPEC section 6). One rule, not two: Might is already what decides
## how much a body can haul, and giving the villain a bespoke carry stat would
## mean two places to look when a sortie comes home light.
func carry_capacity() -> int:
	return maxi(1, might)

func carried_total() -> int:
	var total: int = 0
	for amount in carried.values():
		total += int(amount)
	return total

func carry_space() -> int:
	return maxi(0, carry_capacity() - carried_total())

## Takes as much of `amount` as will fit and returns how much was actually
## taken, so the caller can log the real number and leave the rest on the
## ground. Nothing calls this until R2's loot; the capacity exists now so the
## field and the panel agree from the start.
func add_carried(kind: String, amount: int) -> int:
	var taken: int = mini(maxi(0, amount), carry_space())
	if taken > 0:
		carried[kind] = int(carried.get(kind, 0)) + taken
	return taken

## Hands the whole load over and empties him -- the deposit half of the banking
## rule (ROGUELITE_REWORK section 1). Returns what he was holding.
func take_carried() -> Dictionary:
	var load_out: Dictionary = carried.duplicate()
	carried.clear()
	return load_out

## Human-readable load, for logs and the panel. "nothing" when empty.
func carried_label() -> String:
	if carried.is_empty():
		return "nothing"
	var parts: Array = []
	for kind in carried.keys():
		parts.append("%d %s" % [int(carried[kind]), String(kind).capitalize()])
	return ", ".join(parts)

# ---------------- Escort -----------------------------------------------------

func escort_count() -> int:
	return escort.size()

# ---------------- Combat (the Combatant contract -- see Combat.gd) -----------
#
# All six methods, so `Combat.exchange()` and `Combat.is_combatant()` work on him
# with no special casing anywhere. He is a combatant like any other now; the
# only thing that treats him differently is CombatSystem's lair-aura rule, and
# that is a named flag rather than a hole in this contract.

## `max_hp = 8 + Might * 2`. **Computed, never stored**, same as every other
## combatant -- a stored copy goes stale the moment anything changes Might, and
## the run frame will change it (levels grant options rather than numbers, but
## relics and the Blacksmith already touch Might). The constants come from
## `Laborer` rather than being restated, so there is exactly one hp formula in
## the project.
func max_hp() -> int:
	return Laborer.HP_BASE + maxi(1, might) * Laborer.HP_PER_MIGHT

func heal_full() -> void:
	hp = max_hp()
	_death_announced = false

func combat_name() -> String:
	return "The Necromancer"

func combat_might() -> int:
	return might

func is_alive() -> bool:
	return hp > 0

func hp_fraction() -> float:
	return float(hp) / float(maxi(1, max_hp()))

## Returns the damage actually applied, like every other Combatant.
##
## **Death is emitted from here, not from a policy layer**, precisely so that
## anything that can reduce his hp announces it: `Combat.exchange()` does not
## know who it is hitting, and a run-ending event that only fired when
## CombatSystem happened to be the caller would be a trap for every later
## damage source (traps, the crusade, a rival villain).
func take_damage(amount: int) -> int:
	var before: int = hp
	hp = maxi(0, hp - maxi(0, amount))
	var dealt: int = before - hp
	if hp <= 0 and not _death_announced:
		_death_announced = true
		EventBus.villain_died.emit(self, "slain")
	return dealt

func heal(amount: int) -> int:
	var before: int = hp
	hp = mini(max_hp(), hp + maxi(0, amount))
	return hp - before

# ---------------- Inspection (see InspectionPanel.gd for the contract) -------
#
# The data half only. Actions (Command Undead, camera follow) stay in Main, and
# the *camera follow state* row is appended by NecromancerToken, because where
# the camera is pointing is a view concern and has no business being state on
# the villain. See NecromancerToken.get_inspect_data().

func _hp_row() -> Dictionary:
	var row := {"label": "Health", "value": "%d / %d hp" % [hp, max_hp()]}
	if not is_alive():
		row["value"] = "Fallen"
		row["color"] = Color(1.0, 0.35, 0.35)
	elif hp_fraction() < Combat.FLEE_HP_FRACTION:
		row["color"] = Color(1.0, 0.45, 0.45)
	elif hp < max_hp():
		row["color"] = Color(0.95, 0.70, 0.40)
	return row

## What he is standing on, and what it is doing to his pace. Reads as flavour
## and works as a debug readout: "am I actually faster on this road" is
## answerable by clicking him.
func _ground_row() -> Dictionary:
	if world == null:
		return {"label": "Ground", "value": "—", "muted": true}
	var speed: float = terrain_speed()
	var value: String = world.terrain_name(position)
	if speed > 1.0:
		value += "  —  %d%% pace" % roundi(speed * 100.0)
	return {"label": "Ground", "value": value}

func activity_label() -> String:
	if not is_alive():
		return "Fallen"
	if is_moving:
		return "Walking his domain"
	if _pacing:
		return "Surveying his domain"
	return "Standing still"

func get_inspect_data() -> Dictionary:
	return {
		"title": "The Necromancer",
		"subtitle": "Master of the Settlement",
		"sprite": PORTRAIT,
		"description": "He walks the bone-strewn yard at all hours, counting what the living owe him. The dead do not need counting. They simply obey.",
		"details": [
			{"label": "Activity", "value": activity_label()},
			_hp_row(),
			{"label": "Stats", "value": "Might %d" % might},
			_ground_row(),
			{"label": "Carrying", "value": "%d / %d — %s" % [carried_total(), carry_capacity(), carried_label()]},
			{"label": "Escort", "value": "None — he walks alone" if escort.is_empty()
				else "%d following" % escort_count()},
			{"label": "", "value": "He does not gather, and never counts toward your workforce.", "muted": true},
		],
	}
