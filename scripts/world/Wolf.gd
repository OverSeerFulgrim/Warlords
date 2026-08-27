extends Node2D
class_name Wolf
## The first hostile creature, and the first thing on the map that can hurt you.
##
## It exists to make the settlement feel exposed at night without introducing a
## war: it prowls in from the treeline at dusk, takes whatever is *nearest* --
## deer and labourer alike -- and leaves. **Its most common outcome is
## economic, not lethal**: a wolf that eats a deer has cost you 8 food and a
## hunting trip and never touched anyone, which is the threat model this is
## actually trying to establish. Since your hunters walk out to the same deer
## the wolf wants, "nearest" puts the two of them in the same place often
## enough without needing a preference rule.
##
## Movement reuses the deer's wander helpers (`Roaming`), because a prowling
## wolf and a grazing deer want exactly the same "drift to a random point, pick
## another" behaviour -- the difference is entirely in what makes it stop.
##
## **This class knows how to move, look and bleed. It does not know what
## happens when it wins.** Target selection, the fight itself and every
## consequence live in CombatSystem, which is also what a raider or a bounty
## monster would talk to. Keeping policy out of the creature is what stops the
## next hostile thing from being a copy of this file.

## Its row in `data/races.json`, authored in the workbook beside the races
## (COMBAT_SPEC amendment 2026-08-06, note 4: creatures carry all nine
## attributes). Reading them from data rather than restating them here is what
## lets an arcane attacker hit the wolf's own Intelligence 2 instead of
## tripping a "creatures have no Int" branch anywhere in Combat.
const RACE_ID := "wolf"

## Fallbacks if the row is missing, matching the workbook exactly. Strength 5 is
## a human peasant: individually a match for a Skeleton Worker and clearly
## beneath any Warrior-category recruit, which is what makes "keep an orc in
## town" the answer. Endurance 5 is what keeps `max_hp` at the shipped 18, and
## Intelligence 2 is COMBAT_SPEC section 7's arcane-vs-beast knob.
const FALLBACK_ATTRIBUTES := {
	"strength": 5, "dexterity": 3, "speed": 8, "endurance": 5,
	"intelligence": 2, "guile": 3, "perception": 6, "tact": 2, "loyalty": 5,
}

## Breaks off and leaves below this. Absolute rather than a fraction because
## the wolf is a single hand-tuned creature, not a rolled unit -- and because
## "flees when below 5 hp" is the stated design number.
const FLEE_BELOW_HP: int = 5

## How far it will notice prey from, in pixels. ~5 grid cells.
const HUNT_RADIUS_PX: float = 320.0

## Seconds of visible prowling before it will take anything.
##
## Without this the wolf is functionally invisible: it enters at the treeline,
## a roaming deer is usually already inside its hunt radius, and it kills and
## leaves inside a couple of seconds. Playtest saw two spawns in a row that
## never came within sight of the settlement -- the player got two log lines and
## no wolf. A threat the player never sees isn't a threat, it's a tax.
##
## Also gives the emergent-defence rule somewhere to happen: an approaching wolf
## is a thing you can notice and react to, which is the entire point of the
## rule being emergent rather than ordered.
const HUNT_DELAY_SECONDS: float = 25.0

## Close enough to start biting.
const ENGAGE_RADIUS_PX: float = 26.0

## Ambling. Stays a hand-tuned constant on purpose: COMBAT_SPEC section 7 is
## explicit that prowling is a *behaviour state*, not a stat -- a wolf saving
## its legs is not a slower wolf.
const PROWL_SPEED_PX: float = 34.0
const LEAVE_SPEED_PX: float = 96.0   # it does not linger once it's done

## Wolves will not go near the Necromancer. Anything inside this of him is
## effectively invisible to the wolf -- see CombatSystem, which also emits the
## flavor line the first time one gets close.
const NECROMANCER_FEAR_RADIUS_PX: float = 150.0

const SPRITE_PATH := "res://assets/placeholder/generated/creature_wolf.png"
## **Content WIDTH in world px: 74 = 1.15 of a 64px tile.**
##
## The one sizing exception in the project, and it is SPRITE_SPEC.md §3's, not
## an oversight here: *"Quadruped is measured by width, not height. A wolf is
## low and long."* Everything else -- every token, node and building -- targets
## content **height** via `Anchoring.scale_for_content_height`; this is the
## single call to the width variant, and §3 marks it load-bearing.
##
## Why width. At the default 0.72 zoom a 34px token rendered as ~24 screen
## pixels of dark grey on dark ground, and playtest simply could not find it.
## The thing that eats your labourers has to be the most legible unit on the
## map, and legibility comes from the area it covers, not from standing tall.
## At 74px wide it draws ~51px tall (0.80 tiles) -- shorter than the Necromancer
## (67) and wider than him (47), which is exactly the trade §3 describes. **Do
## not "correct" this to a height target to make the rule uniform.**
##
## Was `70.0` interpreted as a canvas width. The generated art fills its 32px
## canvas edge to edge horizontally, so that happened to be close; the number
## meant nothing the moment the placeholder is replaced with real art.
const TOKEN_SIZE: float = 74.0

enum State {
	PROWL,    ## drifting around the roam rect looking for something
	STALK,    ## has a target, closing on it
	FIGHT,    ## engaged; CombatSystem is running the exchanges
	LEAVING,  ## fed, beaten, or dawn came -- heading off the map to despawn
}

## The nine, read from the race row at construction. Instance vars rather than
## consts because they come from data now, and `_init` runs long after the
## autoloads are up (CombatSystem builds wolves at dusk).
var attributes: Dictionary = FALLBACK_ATTRIBUTES.duplicate()

var state: int = State.PROWL
var hp: int = 1

func _init() -> void:
	var authored: Dictionary = RaceCatalog.attributes(RACE_ID)
	if not authored.is_empty():
		attributes = authored.duplicate()
	hp = max_hp()

## Set once it has eaten. A fed wolf will not start another fight for the rest
## of the night -- FOUNDATION_SPEC-style economic pressure rather than an
## escalating threat.
var is_fed: bool = false

## Why it's leaving, for the log line. Has a default rather than "" so a wolf
## removed by some path that didn't call depart() still logs a sentence.
var leave_reason: String = "slipping back into the dark"

var roam_rect: Rect2
var exit_point: Vector2

## The terrain it has to get around. Set by CombatSystem at spawn; null-safe, so
## a wolf spawned in a test with no map still prowls in a straight line.
var world: WorldMap = null

var _target = null          ## a Laborer or a deer ResourceNode
var _roam_target: Vector2
## Counts down HUNT_DELAY_SECONDS from spawn. See the constant.
var _hunt_delay_left: float = HUNT_DELAY_SECONDS
var _sprite: Sprite2D
var _hp_bar: Label

func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.centered = true
	if ResourceLoader.exists(SPRITE_PATH):
		var tex: Texture2D = load(SPRITE_PATH)
		_sprite.texture = tex
		# Width, not height -- see TOKEN_SIZE. The only such call in the project.
		_sprite.scale = Vector2.ONE * Anchoring.scale_for_content_width(tex, TOKEN_SIZE)
		Anchoring.foot(_sprite)   # it stands on the ground it is hunting over
	else:
		push_warning("Wolf: sprite not found at %s" % SPRITE_PATH)
	add_child(_sprite)

	# A wolf you can't find is a wolf you can't respond to, and the whole point
	# of emergent defence is that the player gets to react. The hp readout
	# doubles as "is my orc winning".
	_hp_bar = Label.new()
	_hp_bar.add_theme_font_size_override("font_size", 11)
	_hp_bar.add_theme_color_override("font_color", Color(1.0, 0.45, 0.40))
	_hp_bar.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_hp_bar.add_theme_constant_override("outline_size", 4)
	_hp_bar.position = Vector2(-18, -TOKEN_SIZE - 16.0)   # clear of its own head
	add_child(_hp_bar)

	z_index = 6  # above every other unit -- it is the thing you must not miss
	set_process(true)

func setup(spawn_pos: Vector2, p_roam_rect: Rect2, p_exit_point: Vector2,
		p_world: WorldMap = null) -> void:
	position = spawn_pos
	roam_rect = p_roam_rect
	exit_point = p_exit_point
	world = p_world
	_roam_target = Roaming.random_point_in(roam_rect, world)

func _process(delta: float) -> void:
	_hp_bar.text = "%d hp" % hp
	_hunt_delay_left = maxf(0.0, _hunt_delay_left - delta)
	match state:
		State.PROWL:
			_tick_prowl(delta)
		State.STALK:
			_tick_stalk(delta)
		State.FIGHT:
			pass  # CombatSystem drives the exchanges; the wolf holds still
		State.LEAVING:
			_tick_leaving(delta)

func _tick_prowl(delta: float) -> void:
	if Roaming.arrived(position, _roam_target):
		_roam_target = Roaming.random_point_in(roam_rect, world)
	var before: Vector2 = position
	position = Roaming.step(position, _roam_target, PROWL_SPEED_PX, delta, world)
	# Wedged against terrain: pick somewhere else rather than grinding at a
	# cliff face for the rest of the night.
	if position.is_equal_approx(before):
		_roam_target = Roaming.random_point_in(roam_rect, world)
	_face_toward(_roam_target)

## Chases whatever CombatSystem handed it. Re-reads the target's position every
## frame rather than caching a destination -- the same trick that lets a worker
## chase a roaming deer with no pursuit code (see WorkerSystem._step_toward).
func _tick_stalk(delta: float) -> void:
	if _target == null:
		state = State.PROWL
		return
	var target_pos: Vector2 = _target.position
	position = Roaming.step(position, target_pos, chase_speed_px(), delta, world)
	_face_toward(target_pos)

func _tick_leaving(delta: float) -> void:
	position = Roaming.step(position, exit_point, LEAVE_SPEED_PX, delta, world)
	_face_toward(exit_point)

func _face_toward(p: Vector2) -> void:
	if absf(p.x - position.x) > 1.0:
		_sprite.flip_h = p.x < position.x

# ---------------- Target handling (set by CombatSystem) ----------------

## False while it's still working up to it. CombatSystem checks this before
## looking for prey at all, so an approaching wolf spends its first
## HUNT_DELAY_SECONDS visibly crossing the map instead of eating the first deer
## it spawns beside.
func may_hunt() -> bool:
	return _hunt_delay_left <= 0.0 and not is_fed

func set_target(t) -> void:
	_target = t
	state = State.STALK if t != null else State.PROWL

func current_target():
	return _target

func clear_target() -> void:
	_target = null
	if state != State.LEAVING:
		state = State.PROWL

func is_within_engage_range() -> bool:
	return _target != null and position.distance_to(_target.position) <= ENGAGE_RADIUS_PX

## Fed, beaten off, or seen off by the dawn. Reaching the exit point despawns
## it (CombatSystem checks has_left()).
func depart(reason: String) -> void:
	leave_reason = reason
	_target = null
	state = State.LEAVING

func has_left() -> bool:
	return state == State.LEAVING and position.distance_to(exit_point) < 8.0

# ---------------- The Combatant contract (see Combat.gd) ----------------

func combat_name() -> String:
	return "wolf"

## Melee, and **not because anything here says so**: Strength 5 is simply its
## highest of Strength / Dexterity / Intelligence. The creature needed no
## rebalancing for the stat rework, only re-expressing.
func combat_profile() -> Dictionary:
	return Combat.profile_for(attribute("strength"), attribute("dexterity"),
		attribute("intelligence"))

func combat_defence(key: String) -> int:
	return attribute(key)

func attribute(key: String) -> int:
	return int(attributes.get(key, RaceCatalog.REFERENCE_VALUE))

## Endurance 5 gives exactly the 18 the wolf shipped with -- the same formula
## every unit uses, with the constants taken from Laborer so the project has one
## hp rule rather than a creature exception.
func max_hp() -> int:
	return Laborer.HP_BASE + maxi(1, attribute("endurance")) * Laborer.HP_PER_ENDURANCE

## Chase speed derived from the Speed attribute through the workbook's own walk
## divisor, rather than the hand-set 78 px/s it used to carry. Speed 8 lands at
## 1.3 cells/sec (83 px/s) -- COMBAT_SPEC section 7 asks for exactly that, and
## calls out why it matters: without it a melee-only predator can never close on
## an archer, and two ranged recruits trivialize the whole creature layer.
func chase_speed_px() -> float:
	return RaceCatalog.walk_speed(RACE_ID) * float(SettlementGrid.CELL_SIZE)

func take_damage(amount: int) -> int:
	var before: int = hp
	hp = maxi(0, hp - maxi(0, amount))
	return before - hp

func is_alive() -> bool:
	return hp > 0

func hp_fraction() -> float:
	return float(hp) / float(maxi(1, max_hp()))

## Absolute threshold rather than Combat.FLEE_HP_FRACTION -- the wolf's flee
## point is a hand-tuned design number (5 hp), not a proportion.
func should_flee() -> bool:
	return hp < FLEE_BELOW_HP

# ---------------- Inspection (see InspectionPanel.gd) ----------------

func get_inspect_data() -> Dictionary:
	var activity := "Prowling"
	match state:
		State.STALK:
			activity = "Stalking %s" % (_target.combat_name() if _target and _target.has_method("combat_name") else "prey")
		State.FIGHT:
			activity = "Fighting"
		State.LEAVING:
			activity = "Leaving — %s" % leave_reason
	var hp_row := {"label": "Health", "value": "%d / %d hp" % [hp, max_hp()]}
	if should_flee():
		hp_row["color"] = Color(1.0, 0.45, 0.45)
	elif hp < max_hp():
		hp_row["color"] = Color(0.95, 0.70, 0.40)
	var rows: Array = [
		{"label": "Activity", "value": activity},
		hp_row,
		{"label": "Profile", "value": "%s — Strength %d vs Endurance" % [
			combat_profile()["profile"], attribute("strength")]},
		{"label": "Physical", "value": "Str %d   Dex %d   Spd %d   End %d" % [
			attribute("strength"), attribute("dexterity"),
			attribute("speed"), attribute("endurance")]},
		{"label": "Social", "value": "Int %d   Gui %d   Per %d   Tac %d   Loy %d" % [
			attribute("intelligence"), attribute("guile"), attribute("perception"),
			attribute("tact"), attribute("loyalty")]},
		{"label": "Breaks off", "value": "Below %d hp" % FLEE_BELOW_HP},
	]
	if is_fed:
		rows.append({"label": "", "value": "It has eaten. It will not hunt again tonight.", "muted": true})
	# Reads the flag rather than restating the rule: the lair aura is an open
	# tunable (CombatSystem.LAIR_AURA_PROTECTS_VILLAIN) and the panel must not go
	# on promising protection after it's switched off.
	if CombatSystem.LAIR_AURA_PROTECTS_VILLAIN:
		rows.append({"label": "", "value": "It will not go near the Necromancer.", "muted": true})
	return {
		"title": "Wolf",
		"subtitle": "Wildlife — hostile",
		"sprite": SPRITE_PATH,
		"description": "Lean, patient, and entirely uninterested in your ambitions. It came for the deer. It will settle for a labourer.",
		"details": rows,
	}

## Click-selection radius, matching the token conventions elsewhere.
func hit_radius() -> float:
	var drawn: Vector2 = Anchoring.drawn_content_size(_sprite)
	return maxf(drawn.x, drawn.y) * Anchoring.HIT_RADIUS_FRACTION
