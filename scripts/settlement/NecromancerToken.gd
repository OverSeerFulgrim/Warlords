extends Node2D
class_name NecromancerToken
## On-screen presence for the Necromancer -- a **pure view**. It reads
## `villain.position` and draws there. It decides nothing and owns no state.
##
## This file used to own his position, wander target and pause timer outright,
## as a deliberate and documented exception to the codebase convention that
## simulation state belongs on a RefCounted with the token as a pure view. The
## exception came with an equally documented migration trigger: *the moment any
## other system needs to know where he is, split it exactly like
## Laborer/WorkerToken.* Three systems now do -- the camera follows him,
## `Combat.exchange()` can hit him, and the keyboard drives him -- so the split
## has happened and this is what is left of the node.
##
## Everything that was state is now on `Necromancer` (scripts/villain/), which
## `VillainController` advances. The only things here are the sprite, its size,
## and the click radius, all of which are genuinely view-only.
##
## **He is still not a Laborer.** `WorkerSystem.laborers()` is the union of
## `workers` and `GameState.followers`; the villain object is in neither, so he
## cannot be handed a gathering trip or counted in the workforce summary. The
## exclusion is structural rather than a flag, and `Necromancer` extends
## RefCounted directly rather than Laborer to keep it that way.

## Drawn at this size on the map. Larger than a worker (32) or a follower (40):
## he is the one unit the player is always looking for.
const TOKEN_SIZE: float = 44.0

## The villain this token draws. Set by `setup()`; never written back to.
var villain: Necromancer = null

## Optional -- supplies the camera-follow row for the inspection panel. See
## get_inspect_data() for why follow state comes from here rather than from the
## data object.
var controller: VillainController = null

var sprite: Sprite2D

func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.centered = true
	# Map art is separate from the portrait used by inspection and the HUD.
	if ResourceLoader.exists(Necromancer.MAP_SPRITE):
		var tex: Texture2D = load(Necromancer.MAP_SPRITE)
		sprite.texture = tex
		var src: Vector2 = tex.get_size()
		if src.x > 0.0:
			sprite.scale = Vector2.ONE * (TOKEN_SIZE / src.x)
	else:
		push_warning("NecromancerToken: map sprite not found at %s" % Necromancer.MAP_SPRITE)
	add_child(sprite)
	# Drawn above buildings so he's never hidden behind the Throne he's
	# standing next to.
	z_index = 5
	set_process(true)

func setup(p_villain: Necromancer, p_controller: VillainController = null) -> void:
	villain = p_villain
	controller = p_controller
	if villain:
		position = villain.position

func _process(_delta: float) -> void:
	if villain == null:
		return
	position = villain.position
	# Facing is read, not decided: both player input and idle pacing change it,
	# and only one of the two is visible from here.
	sprite.flip_h = villain.facing_x < 0.0

## Screen/world-space hit radius for click selection. Stays on the token because
## it is a function of how big he is *drawn*. Note the hit test itself measures
## `villain.position`, not this node's -- a view is always a frame stale, and
## clicking a ghost is the exact bug `Main._closest_token_hit` was fixed for.
func hit_radius() -> float:
	return TOKEN_SIZE * 0.6

# ---------------- Inspection (see InspectionPanel.gd for the contract) -------

## **Delegates.** Every row about who he is and what shape he is in comes from
## the `Necromancer` object, so there is one description of the villain rather
## than two that can disagree.
##
## The one row added here is camera follow, and it is added here deliberately:
## where the camera is pointing is a property of the *view*, not of the man. Put
## it on the data object and the next thing on it is a scroll offset.
func get_inspect_data() -> Dictionary:
	if villain == null:
		return {}
	var data: Dictionary = villain.get_inspect_data()
	if controller:
		var details: Array = data.get("details", [])
		# Ahead of the closing flavor aside, which reads as a footer.
		details.insert(maxi(0, details.size() - 1), {
			"label": "Camera",
			"value": controller.follow_status_text(),
			"muted": not controller.following,
		})
	return data
