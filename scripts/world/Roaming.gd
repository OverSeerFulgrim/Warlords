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
static func random_point_in(rect: Rect2) -> Vector2:
	return Vector2(
		randf_range(rect.position.x, rect.position.x + rect.size.x),
		randf_range(rect.position.y, rect.position.y + rect.size.y)
	)

## Moves `from` toward `to` at `speed` px/sec and returns the new position.
## Never overshoots. `delta` is the ordinary frame delta, so this inherits the
## debug time scale like everything else.
static func step(from: Vector2, to: Vector2, speed: float, delta: float) -> Vector2:
	var offset: Vector2 = to - from
	var travel: float = speed * delta
	if offset.length() <= travel:
		return to
	return from + offset.normalized() * travel

## True once `from` is close enough to `to` to want a new target.
static func arrived(from: Vector2, to: Vector2, epsilon: float = 4.0) -> bool:
	return from.distance_to(to) < epsilon
