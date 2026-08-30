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
	ESCORT,   ## the point follows the villain; keep station on him
}

## **The escort stance** (ESCORT_SPEC amendment 2026-08-29). A policy on the
## spell, never an order to a unit: whole-escort always, no per-skeleton
## setting, no selection UI -- section 1.1 and 1.2 survive intact.
##
## Without it a party can never walk PAST a den or a guardian without starting
## the fight, which becomes fatal once R3 puts patrols and adventurers on the
## map. **Default DEFENSIVE**, which makes the party consistent with the
## villain's own engage model: nothing the player owns starts a fight unless
## they chose it.
##
## Cover-the-retreat overrides stance in both directions -- instinct is not
## policy.
enum Stance {
	DEFENSIVE,  ## engage only once the party has been struck
	AGGRESSIVE, ## engage anything hostile inside the radius
}

## How far the dead will stray from the point, per order. Defend is deliberately
## tighter than a wolf's own hunt radius (320px) so a defended spot is genuinely
## a *spot* -- otherwise every order collapses into "attack".
const DEFEND_RADIUS_PX: float = 1.2 * float(SettlementGrid.CELL_SIZE)
const PATROL_RADIUS_PX: float = 3.0 * float(SettlementGrid.CELL_SIZE)
const ATTACK_RADIUS_PX: float = 7.0 * float(SettlementGrid.CELL_SIZE)
## Between DEFEND's 1.2 and PATROL's 3.0: tight enough that the party reads as
## a group at world zoom, loose enough that they do not conga-line through a
## mountain pass. The single number that decides whether a party looks like one.
const ESCORT_RADIUS_PX: float = 2.5 * float(SettlementGrid.CELL_SIZE)

const MARKER_RADIUS: float = 13.0

var order: int = Order.DEFEND
var stance: int = Stance.DEFENSIVE

## **The entire escort mechanism.** When set, `_process` copies this object's
## position into the point's own, every frame.
##
## Everything downstream -- `UndeadCommand._advance_bound()`, the arrive
## epsilon, `_hostile_for()`'s measure-from-the-point rule, the radius ring this
## node draws -- then works unchanged, because none of it ever assumed the point
## was still. That is why the escort is one field and one enum member rather
## than a second follow-the-villain system living beside the first.
##
## Typed `Object` rather than `Necromancer` so the anchor is not villain-shaped
## by construction: anything with a `position` can be followed, and a spec that
## wanted the dead to follow a cart would need no change here.
var follow: Object = null

## Set by UndeadCommand each frame so the panel and the marker can show it
## without either of them recounting the roster.
var bound_count: int = 0

func _ready() -> void:
	z_index = 3  # above the ground and buildings, below units
	set_process(true)

## **Where the escort happens.** One copy, every frame, and the rest of the
## system follows because nothing in it assumed the point was still.
func _process(_delta: float) -> void:
	if follow != null and is_instance_valid(follow):
		position = follow.position
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
		Order.ESCORT:
			# A fourth, distinct from the other three: cold green, which reads as
			# "his" rather than as a place.
			return Color(0.55, 0.90, 0.70)
		_:
			return Color(0.55, 0.75, 0.95)

func radius_for_order() -> float:
	match order:
		Order.ATTACK:
			return ATTACK_RADIUS_PX
		Order.PATROL:
			return PATROL_RADIUS_PX
		Order.ESCORT:
			return ESCORT_RADIUS_PX
		_:
			return DEFEND_RADIUS_PX

static func order_name(o: int) -> String:
	match o:
		Order.ATTACK:
			return "Attack"
		Order.PATROL:
			return "Patrol"
		Order.ESCORT:
			return "Escort"
		_:
			return "Defend"

const ORDER_BLURB := {
	Order.DEFEND: "Hold this ground. They will not chase anything past the ring.",
	Order.PATROL: "Walk a circuit. They will take whatever they run into on the way.",
	Order.ATTACK: "Hunt. They will cross the whole ring to reach the nearest living thing that isn't yours.",
	Order.ESCORT: "Walk with him. The ring goes where he goes, and they will not chase anything past it.",
}

static func stance_name(s: int) -> String:
	return "Aggressive" if s == Stance.AGGRESSIVE else "Defensive"

const STANCE_BLURB := {
	Stance.DEFENSIVE: "They strike back, and only back. Nothing starts a fight you did not.",
	Stance.AGGRESSIVE: "They take anything hostile inside the ring, whether it noticed you or not.",
}

func is_escorting() -> bool:
	return order == Order.ESCORT and follow != null and is_instance_valid(follow)

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
		] + _escort_rows() + [
			{"label": "", "value": "Bound undead do not gather. The dead can dig or they can fight, not both.", "muted": true},
		],
	}

## The two rows that only mean anything while the point is anchored to a man.
## Legibility is section 7's whole job here: the player must be able to answer
## *why did they do that* without reading source, and "the ring is on him" plus
## "they only strike back" is the entire answer.
func _escort_rows() -> Array:
	if not is_escorting():
		return []
	return [
		{"label": "Anchored to", "value": "The Necromancer — the ring goes where he goes"},
		{"label": "Stance", "value": stance_name(stance), "color": order_colour()},
		{"label": "", "value": STANCE_BLURB.get(stance, ""), "muted": true},
	]

func hit_radius() -> float:
	return MARKER_RADIUS + 6.0
