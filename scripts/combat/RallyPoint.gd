extends Node2D
class_name RallyPoint
## Where the Necromancer's will is anchored: a marker on the map that his undead
## march to, and the order they follow once there.
##
## **Why this exists rather than per-unit orders.** GAME_OUTLINE pillar 2 says
## "you post bounties, set priorities, and assemble parties; you don't order
## units around", and that pillar is load-bearing -- it's what makes the
## settlement feel like it has people in it rather than pieces. Commanding a
## skeleton to walk somewhere would break it. Commanding *the dead*, as a class,
## through a spell, does not: the skeletons have no will to override, which is
## the entire difference between them and a recruit. So the player's lever is a
## spell with a target, not a selection box with a move order.
##
## The living are unaffected, and always will be. `UndeadCommand` filters on
## `Laborer.is_undead()`, which reads `alignment: "Undead"` out of races.json --
## so the ghouls and wraiths on the roadmap fall under the same spell for free,
## and no living race ever can.
##
## Exactly one exists at a time. Re-casting moves it.

## What the dead do once they've arrived.
##
## The three differ in how far they will go from this point, which is the only
## axis that matters at this scale -- there is no formation, no facing, and no
## target priority beyond "nearest".
enum Order {
	DEFEND,   ## hold the spot; engage what comes within a tight radius
	PATROL,   ## walk a beat around it; engage what they meet
	ATTACK,   ## seek the nearest hostile in a wide radius and go to it
}

## How far the dead will stray from the point, per order. Defend is deliberately
## tighter than a wolf's own hunt radius (320px) so a defended spot is genuinely
## a *spot* -- otherwise every order collapses into "attack".
const DEFEND_RADIUS_PX: float = 1.2 * float(SettlementGrid.CELL_SIZE)
const PATROL_RADIUS_PX: float = 3.0 * float(SettlementGrid.CELL_SIZE)
const ATTACK_RADIUS_PX: float = 7.0 * float(SettlementGrid.CELL_SIZE)

const MARKER_RADIUS: float = 13.0

var order: int = Order.DEFEND

## Set by UndeadCommand each frame so the panel and the marker can show it
## without either of them recounting the roster.
var bound_count: int = 0

func _ready() -> void:
	z_index = 3  # above the ground and buildings, below units
	set_process(true)

func _process(_delta: float) -> void:
	queue_redraw()  # the pulse, and the colour changes with the order

## Drawn rather than sprited: it is a magical marker, not an object, and a
## pulsing ring reads as "an effect is in force here" in a way a static icon
## doesn't. Also means the order change is instantly visible as a colour change
## with no extra art.
func _draw() -> void:
	var col: Color = order_colour()
	# Slow pulse. Uses the engine clock rather than a delta accumulator on
	# purpose -- this is pure decoration and should keep breathing at the same
	# rate whatever the debug time scale is doing.
	var pulse: float = 0.75 + 0.25 * sin(Time.get_ticks_msec() / 400.0)
	draw_circle(Vector2.ZERO, MARKER_RADIUS * pulse, Color(col.r, col.g, col.b, 0.22))
	draw_arc(Vector2.ZERO, MARKER_RADIUS, 0.0, TAU, 24, col, 2.0)
	# A short spine and crossbar -- a standard, without needing a standard.
	draw_line(Vector2(0, -MARKER_RADIUS), Vector2(0, -MARKER_RADIUS - 12.0), col, 2.0)
	draw_line(Vector2(-5, -MARKER_RADIUS - 9.0), Vector2(5, -MARKER_RADIUS - 9.0), col, 2.0)
	# The radius the order actually covers, so "why didn't they chase it" has a
	# visible answer.
	draw_arc(Vector2.ZERO, radius_for_order(), 0.0, TAU, 48, Color(col.r, col.g, col.b, 0.18), 1.0)

func order_colour() -> Color:
	match order:
		Order.ATTACK:
			return Color(0.95, 0.40, 0.35)
		Order.PATROL:
			return Color(0.85, 0.75, 0.35)
		_:
			return Color(0.55, 0.75, 0.95)

func radius_for_order() -> float:
	match order:
		Order.ATTACK:
			return ATTACK_RADIUS_PX
		Order.PATROL:
			return PATROL_RADIUS_PX
		_:
			return DEFEND_RADIUS_PX

static func order_name(o: int) -> String:
	match o:
		Order.ATTACK:
			return "Attack"
		Order.PATROL:
			return "Patrol"
		_:
			return "Defend"

const ORDER_BLURB := {
	Order.DEFEND: "Hold this ground. They will not chase anything past the ring.",
	Order.PATROL: "Walk a circuit. They will take whatever they run into on the way.",
	Order.ATTACK: "Hunt. They will cross the whole ring to reach the nearest living thing that isn't yours.",
}

# ---------------- Inspection (see InspectionPanel.gd) ----------------

func get_inspect_data() -> Dictionary:
	return {
		"title": "Rally Point",
		"subtitle": "Command Undead — %s" % order_name(order),
		"description": "The Necromancer's will, driven into the ground like a stake. What is dead and his answers it.",
		"details": [
			{"label": "Order", "value": order_name(order), "color": order_colour()},
			{"label": "", "value": ORDER_BLURB.get(order, ""), "muted": true},
			{"label": "Bound", "value": "%d undead" % bound_count},
			{"label": "Range", "value": "%.1f cells" % (radius_for_order() / float(SettlementGrid.CELL_SIZE))},
			{"label": "", "value": "Bound undead do not gather. The dead can dig or they can fight, not both.", "muted": true},
		],
	}

func hit_radius() -> float:
	return MARKER_RADIUS + 6.0
