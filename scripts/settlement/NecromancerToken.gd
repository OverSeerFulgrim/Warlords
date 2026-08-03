extends Node2D
class_name NecromancerToken
## The player's avatar on the map: the Necromancer himself, pacing his domain
## around the Throne of Bones.
##
## **He is not a Laborer and must never become one.** He has no `Worker` or
## `Follower` behind him, so he isn't in `WorkerSystem.workers` and isn't in
## `GameState.followers` -- which means `WorkerSystem.laborers()` (the union of
## exactly those two) can't see him, and he can't be handed a gathering trip or
## counted in the workforce summary. That exclusion is structural rather than a
## flag someone has to remember to check, and it should stay that way: if the
## Necromancer ever *does* need to act on the world, give him his own system,
## don't slot him into the labor pool.
##
## **Where his position lives.** In this node, not in a separate data object --
## a deliberate exception to the codebase convention that simulation state
## belongs on a RefCounted with the token as a pure view (see CLAUDE.md).
## The convention exists because WorkerToken once animated on a clock that
## disagreed with the economy driving it. There is no such risk here: nothing
## reads this position, there is no simulation counterpart to drift from, and
## inventing a `Necromancer` RefCounted whose position only this node writes
## and reads would be ceremony without a beneficiary.
##
## **Migrate the moment that stops being true.** The trigger is any *other*
## system needing to know where he is -- spells cast from his location, a raider
## targeting him, him walking to a building on command. At that point split it
## exactly like Laborer/WorkerToken: data object owns `position`, this node
## becomes a pure view.

## How far he'll drift from the Throne, in grid cells. Small on purpose: he
## should read as pacing his own hall, not wandering off to supervise.
const WANDER_CELLS: float = 2.0

## Slow. He is not going anywhere; he is brooding.
const WALK_SPEED_PX: float = 22.0
const PAUSE_MIN: float = 2.5
const PAUSE_MAX: float = 6.0

## Commissioned art, shared with the HUD badge (Main.NECROMANCER_SPRITE points
## at the same file). It is a 1024px portrait scaled down to token size --
## still a portrait rather than a purpose-drawn map sprite, so he reads as a
## hooded figure rather than a posed character, but it is the real Necromancer
## art rather than a pack stand-in.
const PORTRAIT := "res://Official Sprites/Necromancer_Portrait.png"
const TOKEN_SIZE: float = 44.0

var home: Vector2 = Vector2.ZERO
var sprite: Sprite2D

var _target: Vector2 = Vector2.ZERO
var _pause_left: float = 0.0

func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.centered = true
	if ResourceLoader.exists(PORTRAIT):
		var tex: Texture2D = load(PORTRAIT)
		sprite.texture = tex
		var src: Vector2 = tex.get_size()
		if src.x > 0.0:
			sprite.scale = Vector2.ONE * (TOKEN_SIZE / src.x)
	else:
		push_warning("NecromancerToken: portrait not found at %s" % PORTRAIT)
	add_child(sprite)
	# Drawn above buildings so he's never hidden behind the Throne he's
	# standing next to.
	z_index = 5
	set_process(true)

## `p_home` is the world position he paces around -- the Throne's centre.
func setup(p_home: Vector2) -> void:
	home = p_home
	position = p_home
	_target = p_home
	_pause_left = randf_range(PAUSE_MIN, PAUSE_MAX)

func _process(delta: float) -> void:
	if _pause_left > 0.0:
		_pause_left -= delta
		return
	if position.distance_to(_target) <= 2.0:
		_pick_new_target()
		return
	var step: float = WALK_SPEED_PX * delta
	var to_target: Vector2 = _target - position
	if to_target.length() <= step:
		position = _target
		_pick_new_target()
		return
	position += to_target.normalized() * step
	# Face the way he's drifting.
	if absf(to_target.x) > 1.0:
		sprite.flip_h = to_target.x < 0.0

func _pick_new_target() -> void:
	var r: float = WANDER_CELLS * float(SettlementGrid.CELL_SIZE)
	# Rejection-free polar pick, so he favours no particular direction.
	var angle: float = randf() * TAU
	var dist: float = sqrt(randf()) * r  # sqrt keeps the distribution even over the disc
	_target = home + Vector2(cos(angle), sin(angle)) * dist
	_pause_left = randf_range(PAUSE_MIN, PAUSE_MAX)

## Screen/world-space hit radius for click selection, matching how the
## follower and worker tokens are picked (proximity, not a grid cell -- he
## isn't cell-locked).
func hit_radius() -> float:
	return TOKEN_SIZE * 0.6

# ---------------- Inspection (see InspectionPanel.gd for the contract) -------

## He isn't a Laborer, so none of Laborer's inspection scaffolding applies --
## he has no stats, no trip loop and no upkeep. This is deliberately its own
## small implementation rather than a special case inside the character one.
func get_inspect_data() -> Dictionary:
	return {
		"title": "The Necromancer",
		"subtitle": "Master of the Settlement",
		"sprite": PORTRAIT,
		"description": "He walks the bone-strewn yard at all hours, counting what the living owe him. The dead do not need counting. They simply obey.",
		"details": [
			{"label": "Activity", "value": "Surveying his domain"},
			{"label": "Health", "value": "— no combat system yet", "muted": true},
			{"label": "Spells", "value": "None yet — the art is not yours to work"},
			{"label": "", "value": "He does not gather, and never counts toward your workforce.", "muted": true},
		],
	}
