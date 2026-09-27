extends Node2D
class_name RavenMarker
## The Raven's mark on the world: a small violet sigil hovering over a site it
## pinged, drawn **above the fog** (z 110 against the fog's 100) and revealing
## nothing -- it is a pointer, not a window (`RAVEN_SPEC.md` sections 3 and 5).
##
## Inspectable through the ordinary `get_inspect_data()` contract: "The Raven's
## Word", the site's name and band, the day found, and the distance from the
## Necromancer's current position (not the Throne) as the raven flies. The route is the player's problem; the bird vouches for the
## destination, never the road (section 4).

const HIT_RADIUS: float = 22.0
const COLOR := Color(0.72, 0.52, 1.0)

var raven = null
var site = null
var day_found: int = 1
var _t: float = 0.0

func setup(p_raven, p_site, p_day: int) -> void:
	raven = p_raven
	site = p_site
	day_found = p_day
	position = site.position + Vector2(0, -46)
	z_index = 110

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var bob: float = sin(_t * 2.4) * 3.0
	var c: Vector2 = Vector2(0, bob)
	# A diamond with a notch: reads as "marked" at any zoom, and is nothing like
	# the lair ring, the villain dot or a site sprite.
	var pts := PackedVector2Array([c + Vector2(0, -13), c + Vector2(10, 0), c + Vector2(0, 13), c + Vector2(-10, 0)])
	draw_colored_polygon(pts, Color(0.12, 0.06, 0.2, 0.85))
	pts.append(pts[0])
	draw_polyline(pts, COLOR, 2.0, true)
	draw_circle(c, 3.0, COLOR)
	draw_line(c + Vector2(0, 13), c + Vector2(0, 30), Color(COLOR, 0.55), 1.5, true)

func hit_radius() -> float:
	return HIT_RADIUS

func get_inspect_data() -> Dictionary:
	var rows: Array = []
	if site:
		rows.append({"label": "Site", "value": site.display_name})
		rows.append({"label": "Danger", "value": "Band %d" % site.band})
		rows.append({"label": "Found", "value": "Day %d" % day_found})
		if raven and raven.villain:
			var cells: int = int(round(raven.villain.position.distance_to(site.position) / float(WorldMap.CELL_SIZE)))
			rows.append({"label": "Distance", "value": "%d cells from him as the raven flies — about %s on foot, more by the long way"
				% [cells, TravelLog._fmt(float(cells))]})
	rows.append({"label": "", "value": "She has been there. It is real, it is empty of anything that bites, and nobody of yours has found it yet. She says nothing about the road.",
		"muted": true})
	return {
		"title": "The Raven's Word",
		"subtitle": "A mark only you can see",
		"description": "The bird came back at dawn with a place in her eye.",
		"details": rows,
	}
