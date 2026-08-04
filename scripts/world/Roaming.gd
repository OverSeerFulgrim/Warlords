class_name Roaming
extends RefCounted
## Wander-around-a-rectangle movement, shared by the deer (`ResourceNode`) and
## the wolf (`Wolf`).
##
## This was the deer's private ten lines until the wolf needed exactly the same
## behaviour. Extracted rather than copied, and extracted as two static
## functions rather than a base class: the deer is a `ResourceNode` and the wolf
## is a plain `Node2D`, so there is no shared ancestor to hang it on and
## inventing one ("Roamer extends Node2D") would force the deer to stop being a
## resource node purely to satisfy a hierarchy.

## A uniformly random point inside `rect`. Used to pick the next drift target.
##
## Pass `world` and it will only return somewhere walkable -- retrying a few
## times, then falling back to the nearest walkable cell. Both callers roam
## rectangles that can overlap a mountain or a frozen lake once those exist, and
## a target inside one would leave the animal shuffling against a cliff forever.
static func random_point_in(rect: Rect2, world: WorldMap = null, attempts: int = 8) -> Vector2:
	var point := Vector2(
		randf_range(rect.position.x, rect.position.x + rect.size.x),
		randf_range(rect.position.y, rect.position.y + rect.size.y)
	)
	if world == null:
		return point
	for i in range(attempts):
		if world.is_walkable(point):
			return point
		point = Vector2(
			randf_range(rect.position.x, rect.position.x + rect.size.x),
			randf_range(rect.position.y, rect.position.y + rect.size.y)
		)
	return world.nearest_walkable(point)

## Moves `from` toward `to` at `speed` px/sec and returns the new position.
## Never overshoots. `delta` is the ordinary frame delta, so this inherits the
## debug time scale like everything else.
##
## With a `world`, blocking terrain is respected by the **same slide** the
## villain uses (`WorldMap.slide`), so a wolf and the man it is hunting round a
## boulder the same way rather than each having their own idea of what a wall
## does.
static func step(from: Vector2, to: Vector2, speed: float, delta: float,
		world: WorldMap = null) -> Vector2:
	var offset: Vector2 = to - from
	var travel: float = speed * delta
	var motion: Vector2 = offset if offset.length() <= travel else offset.normalized() * travel
	if world == null:
		return from + motion
	return world.slide(from, motion)

## True once `from` is close enough to `to` to want a new target.
static func arrived(from: Vector2, to: Vector2, epsilon: float = 4.0) -> bool:
	return from.distance_to(to) < epsilon
