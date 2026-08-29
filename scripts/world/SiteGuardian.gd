extends Node2D
class_name SiteGuardian
## Something standing between the player and a site's loot.
##
## `LOOT_SITES_SPEC.md` section 9 asks for a Combatant-contract fighter parked
## at a site, reusing `Roaming.gd` and the wolf's patterns. That is exactly what
## this is, and the emphasis is on *reusing*: for `kind: "wolf"` it wears
## `Wolf.gd`'s own constants, race row and sprite, so **a den wolf and a dusk
## wolf are visibly and mechanically the same animal**. If they ever diverge it
## will be because someone edited `Wolf.gd` and not this file, which is the
## right way round.
##
## ## Why it is not a `Wolf`
##
## `Wolf` is the *settlement's* night visitor: it owns an exit point, a hunt
## delay, a fed flag, a dawn departure and a prey search over the labour pool.
## A den's defender has none of that -- it stands where it stands, it engages
## what enters, and it is finite. Subclassing would have meant inheriting four
## behaviours to switch off, which is how the next guardian kind ends up being a
## wolf with the wolf parts commented out.
##
## ## Not a Laborer, and the undead exception is deliberate
##
## Guardians are not in any labour pool and are never commandable *while
## living*. Undead guardians **are** commandable through `alignment: "Undead"`
## like any other dead thing -- Command Undead flipping a crypt's sentinel is
## the fantasy, not a hole in the rules (section 9).
##
## ## Finite defenders
##
## A pack wolf that drops below its flee threshold **leaves the run** rather
## than the fight-then-return loop the settlement wolf uses (section 3b). That
## is what makes attrition across two visits a legitimate tactic, and it is why
## `depart()` here despawns rather than heading for an exit.

## The prowl radius, in cells, around the guardian's post. Small on purpose:
## a den's defenders patrol the den, they do not range. `Roaming` does the rest.
const DEFAULT_PROWL_CELLS: float = 3.0

## How close it has to be to start biting. Same number the wolf uses, from the
## wolf, so "in range" means one thing on this map.
const ENGAGE_RADIUS_PX: float = Wolf.ENGAGE_RADIUS_PX

## How far it will notice an intruder from. Deliberately shorter than the
## settlement wolf's 320px hunt radius: a guardian is not hunting, it is
## objecting, and a den that aggroed from five cells away would fight the player
## before the site had a chance to telegraph itself (section 1.3).
const NOTICE_RADIUS_PX: float = 4.0 * float(SettlementGrid.CELL_SIZE)

const PROWL_SPEED_PX: float = 34.0

enum State { PROWL, STALK, FIGHT, GONE }

## Which site it belongs to. A **reference handed in**, never looked up: the
## site owns its guardians and nothing else may reach into them.
var site: WorldSite = null

var kind: String = "wolf"
var display_name: String = "Pack wolf"
var race_id: String = "wolf"
var attributes: Dictionary = {}
var alignment: String = ""
var flee_below_hp: int = 5
var sprite_path: String = ""
var token_size: float = 74.0
var width_scaled: bool = false

var state: int = State.PROWL
var hp: int = 1
var world: WorldMap = null

## Where it stands guard, and the disc it will drift around.
var post: Vector2 = Vector2.ZERO
var prowl_radius_px: float = DEFAULT_PROWL_CELLS * float(SettlementGrid.CELL_SIZE)

## Why it stopped being a problem. Read by the log line.
var leave_reason: String = "driven off"

var _target = null
var _roam_target: Vector2
var _sprite: Sprite2D
var _hp_bar: Label

# ---------------- Construction ------------------------------------------------

## `spec` is one entry of `world_sites.json`'s top-level `guardians` table.
## Everything statistical comes from `races.json` through `RaceCatalog`, so a
## guardian is authored in the workbook beside every other creature rather than
## in a second private statline.
func setup(p_kind: String, spec: Dictionary, p_site: WorldSite, at: Vector2,
		p_world: WorldMap = null) -> void:
	kind = p_kind
	site = p_site
	world = p_world
	post = at
	position = at
	display_name = String(spec.get("name", p_kind.capitalize()))
	race_id = String(spec.get("race_id", p_kind))
	sprite_path = String(spec.get("sprite", ""))
	token_size = float(spec.get("size", 56.0))
	width_scaled = bool(spec.get("width_scaled", false))
	flee_below_hp = int(spec.get("flee_below_hp", 0))
	alignment = String(spec.get("alignment", ""))
	prowl_radius_px = float(spec.get("prowl_cells", DEFAULT_PROWL_CELLS)) \
		* float(SettlementGrid.CELL_SIZE)

	var authored: Dictionary = RaceCatalog.attributes(race_id)
	attributes = authored.duplicate() if not authored.is_empty() \
		else Wolf.FALLBACK_ATTRIBUTES.duplicate()
	hp = max_hp()
	_roam_target = post

func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.centered = true
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		var tex: Texture2D = load(sprite_path)
		_sprite.texture = tex
		# The wolf is the project's one width-scaled sprite (SPRITE_SPEC section
		# 3's quadruped rule) and a den wolf has to be the same animal as the
		# dusk wolf, so the flag travels with the guardian kind rather than
		# being decided here.
		_sprite.scale = Vector2.ONE * (Anchoring.scale_for_content_width(tex, token_size)
			if width_scaled else Anchoring.scale_for_content_height(tex, token_size))
		Anchoring.foot(_sprite)
	else:
		push_warning("SiteGuardian '%s': sprite not found at %s" % [kind, sprite_path])
	add_child(_sprite)

	_hp_bar = Label.new()
	_hp_bar.add_theme_font_size_override("font_size", 11)
	_hp_bar.add_theme_color_override("font_color", Color(1.0, 0.45, 0.40))
	_hp_bar.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_hp_bar.add_theme_constant_override("outline_size", 4)
	_hp_bar.position = Vector2(-18, -token_size - 16.0)
	add_child(_hp_bar)

	z_index = 6   # the wolf's layer: the thing you must not miss
	set_process(true)

# ---------------- Behaviour ---------------------------------------------------

func _process(delta: float) -> void:
	if _hp_bar:
		_hp_bar.text = "%d hp" % hp
	match state:
		State.PROWL:
			_tick_prowl(delta)
		State.STALK:
			_tick_stalk(delta)
		_:
			pass   # FIGHT is the Engagement's; GONE is about to be freed

func _tick_prowl(delta: float) -> void:
	if Roaming.arrived(position, _roam_target):
		_roam_target = Roaming.random_point_in(_prowl_rect(), world)
	var before: Vector2 = position
	position = Roaming.step(position, _roam_target, PROWL_SPEED_PX, delta, world)
	if position.is_equal_approx(before):
		_roam_target = Roaming.random_point_in(_prowl_rect(), world)
	_face_toward(_roam_target)

## Closes on whatever the policy layer handed it, and **goes home if the
## intruder leaves**. A guardian that chased across the map would stop being a
## guardian; the fight is at the site or it is nowhere.
func _tick_stalk(delta: float) -> void:
	if _target == null or not _is_live(_target):
		clear_target()
		return
	if post.distance_to(_target.position) > NOTICE_RADIUS_PX + prowl_radius_px:
		clear_target()
		return
	position = Roaming.step(position, _target.position, chase_speed_px(), delta, world)
	_face_toward(_target.position)

func _prowl_rect() -> Rect2:
	return Rect2(post - Vector2.ONE * prowl_radius_px, Vector2.ONE * prowl_radius_px * 2.0)

func _face_toward(p: Vector2) -> void:
	if _sprite and absf(p.x - position.x) > 1.0:
		_sprite.flip_h = p.x < position.x

func _is_live(t) -> bool:
	return t != null and is_instance_valid(t) and t.has_method("is_alive") and t.is_alive()

# ---------------- Target handling (set by CombatSystem) -----------------------

## Anything hostile inside the disc it is guarding. The *villain* counts, and
## the lair aura does not apply out here: `CombatSystem.LAIR_AURA_PROTECTS_
## VILLAIN` is a rule about his own domain (its own header says so), and a den
## whose wolves refused to face him would be a den nobody could ever clear.
func notices(pos: Vector2) -> bool:
	return post.distance_to(pos) <= NOTICE_RADIUS_PX

func set_target(t) -> void:
	_target = t
	if state != State.FIGHT and state != State.GONE:
		state = State.STALK if t != null else State.PROWL

func current_target():
	return _target

func clear_target() -> void:
	_target = null
	if state != State.GONE:
		state = State.PROWL

func is_within_engage_range() -> bool:
	return _target != null and is_instance_valid(_target) \
		and position.distance_to(_target.position) <= ENGAGE_RADIUS_PX

## Section 3b: a pack wolf that flees **leaves the run**. There is no exit walk
## and no return -- `CombatSystem` despawns it on the next frame, and the den
## counts it as dealt with (the spec's current answer to the "does a fled wolf
## count toward cleared" tunable is yes).
func depart(reason: String) -> void:
	leave_reason = reason
	_target = null
	state = State.GONE

func has_left() -> bool:
	return state == State.GONE

# ---------------- The Combatant contract (see Combat.gd) ----------------------

func combat_name() -> String:
	return display_name

func combat_profile() -> Dictionary:
	return Combat.profile_for(attribute("strength"), attribute("dexterity"),
		attribute("intelligence"))

func combat_defence(key: String) -> int:
	return attribute(key)

func attribute(key: String) -> int:
	return int(attributes.get(key, RaceCatalog.REFERENCE_VALUE))

func max_hp() -> int:
	return Laborer.HP_BASE + maxi(1, attribute("endurance")) * Laborer.HP_PER_ENDURANCE

func chase_speed_px() -> float:
	return RaceCatalog.walk_speed(race_id) * float(SettlementGrid.CELL_SIZE)

func take_damage(amount: int) -> int:
	var before: int = hp
	hp = maxi(0, hp - maxi(0, amount))
	return before - hp

func is_alive() -> bool:
	return hp > 0

func hp_fraction() -> float:
	return float(hp) / float(maxi(1, max_hp()))

## Absolute when the guardian kind names one (the wolf's hand-tuned 5 hp),
## proportional otherwise -- a sentinel rolled from a race row has no authored
## flee number and falls back to the project's one fraction.
func should_flee() -> bool:
	if flee_below_hp > 0:
		return hp < flee_below_hp
	return hp_fraction() < Combat.FLEE_HP_FRACTION

## Undead guardians answer to Command Undead like every other dead thing.
func is_undead() -> bool:
	return alignment == "Undead"

# ---------------- Inspection (see InspectionPanel.gd) -------------------------

func hit_radius() -> float:
	if _sprite == null:
		return token_size * Anchoring.HIT_RADIUS_FRACTION
	var drawn: Vector2 = Anchoring.drawn_content_size(_sprite)
	return maxf(drawn.x, drawn.y) * Anchoring.HIT_RADIUS_FRACTION

func get_inspect_data() -> Dictionary:
	var activity := "Guarding"
	match state:
		State.STALK:
			activity = "Coming for you"
		State.FIGHT:
			activity = "Fighting"
		State.GONE:
			activity = "Gone — %s" % leave_reason
	var hp_row := {"label": "Health", "value": "%d / %d hp" % [hp, max_hp()]}
	if should_flee():
		hp_row["color"] = Color(1.0, 0.45, 0.45)
	elif hp < max_hp():
		hp_row["color"] = Color(0.95, 0.70, 0.40)
	var rows: Array = [
		{"label": "Activity", "value": activity},
		hp_row,
		{"label": "Guarding", "value": site.display_name if site else "—"},
		{"label": "Profile", "value": "%s — %s %d" % [
			combat_profile()["profile"],
			String(combat_profile()["attack_attr"]).capitalize(),
			attribute(String(combat_profile()["attack_attr"]))]},
		{"label": "Physical", "value": "Str %d   Dex %d   Spd %d   End %d" % [
			attribute("strength"), attribute("dexterity"),
			attribute("speed"), attribute("endurance")]},
	]
	if flee_below_hp > 0:
		rows.append({"label": "Breaks off", "value": "Below %d hp — and does not come back" % flee_below_hp})
	rows.append({"label": "", "value": "Its defenders are finite. Whatever leaves this fight is gone for the run.", "muted": true})
	return {
		"title": display_name,
		"subtitle": "Site guardian — hostile",
		"sprite": sprite_path,
		"description": "It was here before you were, and it has nowhere else to be.",
		"details": rows,
	}
