extends Node2D
class_name Patrol
## A human patrol walking a fixed loop. **Scenery, per ROGUELITE_REWORK §4
## amendment 2:** it walks, it does not react. No detection, no aggression, no
## schedule -- the village is static in v1 and this is the one moving thing in
## it, there so the place reads as inhabited rather than as a diorama.
##
## Built on `Roaming`, the same two static helpers the deer and the wolf use, so
## it rounds terrain exactly the way they do and inherits the debug time scale
## for free. The only thing it adds is a waypoint list instead of a random point
## in a rectangle.
##
## When R3 makes patrols escalate with notoriety, the thing to add is *reaction*
## -- a detection radius and a response. The walking is done.

## Cells per second, converted like every other speed in the project.
var speed_cells: float = 0.7
var waypoints: PackedVector2Array = PackedVector2Array()
var patrol_name: String = "Patrol"
var subtitle: String = "Human lordship"
var description: String = ""
var sprite_path: String = ""
var world: WorldMap = null

## **56px, matching FollowerToken.** Not on the prompt's list, but a patrolman
## left at 34 would have stood shorter than the Skeleton Workers he is supposed
## to be a threat to eventually -- and he is the same kind of thing as a recruit
## (a person), so he gets a person's size.
const TOKEN_SIZE: float = 56.0

var _index: int = 0
var _sprite: Sprite2D

func setup(data: Dictionary, points: PackedVector2Array, p_world: WorldMap) -> void:
	patrol_name = String(data.get("name", "Patrol"))
	subtitle = String(data.get("subtitle", "Human lordship"))
	description = String(data.get("description", ""))
	sprite_path = String(data.get("sprite", ""))
	speed_cells = float(data.get("speed", 0.7))
	waypoints = points
	world = p_world
	if waypoints.size() > 0:
		position = waypoints[0]
		_index = 1 % waypoints.size()

	_sprite = Sprite2D.new()
	_sprite.centered = true
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		var tex: Texture2D = load(sprite_path)
		_sprite.texture = tex
		if tex.get_size().x > 0.0:
			_sprite.scale = Vector2.ONE * (TOKEN_SIZE / tex.get_size().x)
	else:
		push_warning("Patrol '%s': sprite not found at %s" % [patrol_name, sprite_path])
	add_child(_sprite)
	Anchoring.foot(_sprite)
	z_index = 1
	set_process(true)

func _process(delta: float) -> void:
	if waypoints.is_empty():
		return
	var target: Vector2 = waypoints[_index]
	if Roaming.arrived(position, target, 6.0):
		_index = (_index + 1) % waypoints.size()
		return
	var before: Vector2 = position
	position = Roaming.step(position, target, speed_px(), delta, world)
	# Waypoints are authored on roads and open ground, so this should never
	# fire -- but a loop that silently stalls against a rock for the rest of the
	# run is exactly the sort of scenery bug nobody notices, so it skips on.
	if position.is_equal_approx(before):
		_index = (_index + 1) % waypoints.size()
	if absf(target.x - before.x) > 1.0:
		_sprite.flip_h = target.x < before.x

func speed_px() -> float:
	return speed_cells * float(SettlementGrid.CELL_SIZE)

func hit_radius() -> float:
	return TOKEN_SIZE * Anchoring.HIT_RADIUS_FRACTION

func get_inspect_data() -> Dictionary:
	return {
		"title": patrol_name,
		"subtitle": subtitle,
		"sprite": sprite_path,
		"description": description,
		"details": [
			{"label": "Activity", "value": "Walking its round"},
			{"label": "Speed", "value": "%s cells/sec" % String.num(speed_cells, 2)},
			{"label": "Notices you", "value": "Not yet", "muted": true},
			{"label": "", "value": "It walks the same beat whatever you do. The lord's men have not learned to look for you.", "muted": true},
		],
	}
