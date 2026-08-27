extends Node2D
class_name CombatFeedback
## Floating damage numbers over every combatant, per `COMBAT_FEEDBACK_SPEC.md`
## §3. A red `-N` where the hit landed, a muted green `+N` where the Throne
## knits a skeleton back together.
##
## ## It is a view of an event, not state
##
## Nothing here is simulation. No sim object gains a field, no token gains a
## timer, and deleting this node entirely leaves combat bit-identical -- which
## is the test the spec sets for the whole slice. It subscribes to one signal
## (`EventBus.damage_shown`) and knows nothing about who emitted it, so the
## traps and crusade damage that do not exist yet will draw through it for free.
##
## ## A pool of 32, and one clock
##
## The labels are created **once** in `_ready` and reused forever. Past the cap
## the oldest float is recycled, so a mass battle becomes a churn of numbers --
## which reads fine and bounds the node count at exactly `MAX_FLOATS`, no matter
## what happens in front of it.
##
## Animation is **one `_process` loop over the pool**, not a `Tween` or a
## `SceneTreeTimer` per float. Two reasons, and the second is the load-bearing
## one:
##
## 1. 32 pooled labels and one loop is less machinery than 32 live tweens.
## 2. `_process(delta)` is already time-scaled, so the floats inherit
##    `Engine.time_scale` by construction -- at the debug 60x they blur, and
##    **that is correct**: a 60x session is not a cinematic. A `SceneTreeTimer`
##    would have been the CLAUDE.md timer trap in a new costume.
##
## ## Where it sits
##
## A child of the settlement layer, sibling of the token layers, in their
## coordinate space. `z_index` above the units (the wolf's 6 is the highest) and
## far below the fog's 100 -- a number over a unit standing in fog is hidden
## with the unit, which is right.

## Spec §5's tunables, all of them.
const MAX_FLOATS: int = 32
const FLOAT_SECONDS: float = 0.8
const RISE_CELLS: float = 0.5
const FONT_SIZE: int = 13

## Above the units, below the fog. See the class header.
const Z_INDEX: int = 10

## The project's damage red -- the same `Color(1.0, 0.35, 0.35)` the inspection
## panel's hp rows use. The wolf's label is a hair warmer (0.45/0.40); this
## follows the panel, because the panel is where a player learns what red means.
const COLOR_DAMAGE := Color(1.0, 0.35, 0.35)
## The muted repair green `Building.gd` uses for a healthy hp row. Deliberately
## quieter than the damage red: watching the Throne mend skeletons is meant to
## be noticed, not announced.
const COLOR_HEAL := Color(0.75, 0.9, 0.75)

## The wolf's label settings, unchanged. Legibility of small text on snow was
## solved there once -- a 4px black outline -- and there is no reason to solve
## it a second time differently.
const OUTLINE_COLOR := Color(0, 0, 0, 0.9)
const OUTLINE_SIZE: int = 4

## Horizontal spread, so the two halves of one exchange never print on the same
## pixel. The wolf's number and its victim's are emitted in the same frame.
const JITTER_PX: float = 6.0

## Clearance above the unit's own head. Sized to clear the **wolf's hp label**,
## which sits at `-TOKEN_SIZE - 16` and is about 14px tall -- so a float has to
## start another label-height above that to sit on top of nothing.
const CLEARANCE_PX: float = 34.0

## Each label is laid out in a fixed-width box and centre-aligned, then offset
## by half of it. Centring a number over a head cannot wait for the label to
## work out its own width.
const BOX_WIDTH: float = 60.0

## Fraction of the lifetime spent at full opacity before the fade begins.
const FADE_STARTS_AT: float = 0.5

# ---------------- The pool ---------------------------------------------------
#
# Parallel arrays rather than a dictionary or an inner class per float: the
# whole state of a float is three numbers and a label, and `_process` walks all
# 32 slots every frame it runs.

var _labels: Array[Label] = []
var _elapsed: PackedFloat32Array = PackedFloat32Array()
var _origin: PackedVector2Array = PackedVector2Array()
var _live: PackedByteArray = PackedByteArray()
var _live_count: int = 0

func _ready() -> void:
	z_index = Z_INDEX
	_elapsed.resize(MAX_FLOATS)
	_origin.resize(MAX_FLOATS)
	_live.resize(MAX_FLOATS)
	for i in range(MAX_FLOATS):
		var label := Label.new()
		label.add_theme_font_size_override("font_size", FONT_SIZE)
		label.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
		label.add_theme_constant_override("outline_size", OUTLINE_SIZE)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.custom_minimum_size = Vector2(BOX_WIDTH, 0.0)
		label.size = Vector2(BOX_WIDTH, float(FONT_SIZE) + 5.0)
		# A float is a mark on the map, not a thing you can click. Without this
		# the labels would sit on top of the world and eat the clicks that
		# Main's inspect path is waiting for.
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.visible = false
		add_child(label)
		_labels.append(label)

	# **Arity.** `damage_shown` carries three arguments; a handler declaring
	# fewer connects without complaint and then fails silently at emit
	# (CLAUDE.md's gotcha). All three are named here on purpose.
	EventBus.damage_shown.connect(_on_damage_shown)
	set_process(false)   # nothing to animate until something gets hit

# ---------------- Spawning ---------------------------------------------------

## `unit` is the **data object** -- Laborer, Necromancer, Wolf -- so its
## `position` is this frame's truth. A token's is a frame stale, which is the
## same rule the click hit-test had to learn.
##
## Reads that position **now** and never again: the float marks where the hit
## landed and does not follow anyone. A recruit fleeing out from under its own
## pain number is correct, and reads well.
func _on_damage_shown(unit, amount: int, kind: String) -> void:
	if unit == null or amount <= 0:
		return
	# A unit that was freed between the emit and here, or something that was
	# never drawable in the first place. The spec asks that this not error; it
	# is a view, and a view has nothing useful to say about a unit that is gone.
	if unit is Object and not is_instance_valid(unit):
		return
	if not (unit is Object) or not ("position" in unit):
		return

	var at: Vector2 = unit.position
	at.y -= _head_height(unit) + CLEARANCE_PX
	at.x += randf_range(-JITTER_PX, JITTER_PX)

	var slot: int = _claim_slot()
	var label: Label = _labels[slot]
	label.text = ("+%d" % amount) if kind == "heal" else ("-%d" % amount)
	label.add_theme_color_override("font_color",
		COLOR_HEAL if kind == "heal" else COLOR_DAMAGE)
	label.modulate.a = 1.0
	label.visible = true

	# The box is centred on the unit, so its left edge sits half a box out.
	_origin[slot] = at - Vector2(BOX_WIDTH * 0.5, 0.0)
	label.position = _origin[slot]
	_elapsed[slot] = 0.0
	if _live[slot] == 0:
		_live[slot] = 1
		_live_count += 1
	set_process(true)

## A free slot, or the oldest live one.
##
## "Oldest" is simply the largest `_elapsed`: every float has the same lifetime,
## so age and elapsed time are the same ordering and no spawn counter is needed.
func _claim_slot() -> int:
	var oldest: int = 0
	var oldest_elapsed: float = -1.0
	for i in range(MAX_FLOATS):
		if _live[i] == 0:
			return i
		if _elapsed[i] > oldest_elapsed:
			oldest_elapsed = _elapsed[i]
			oldest = i
	return oldest

## How far above `unit.position` its own art reaches.
##
## Read from the **token classes' public size constants** rather than by finding
## the live token and measuring it. Those constants are the content heights fed
## to `Anchoring.scale_for_content_height()`, so they are the drawn height by
## definition -- and this way the layer never reaches into another view's
## children, and no token needed changing to support it. Anything unrecognised
## falls back to one cell, exactly as the spec allows.
##
## The wolf's is a content *width* (it is the project's one width-scaled
## quadruped), which is fine and in fact wanted here: its hp label is placed off
## the same constant, so measuring from it is what keeps the float above that
## label rather than through it.
func _head_height(unit) -> float:
	if unit is Wolf:
		return Wolf.TOKEN_SIZE
	if unit is Necromancer:
		return NecromancerToken.TOKEN_SIZE
	if unit is Laborer:
		# Worker and Follower tokens are both 58.0 -- one Medium body family.
		return WorkerToken.SPRITE_TARGET_SIZE
	return float(SettlementGrid.CELL_SIZE)

# ---------------- The one clock ----------------------------------------------

## `delta` is already time-scaled (CLAUDE.md: never multiply by it again), so
## the floats speed up and blur at 60x along with everything else.
func _process(delta: float) -> void:
	var rise: float = RISE_CELLS * float(SettlementGrid.CELL_SIZE)
	for i in range(MAX_FLOATS):
		if _live[i] == 0:
			continue
		_elapsed[i] += delta
		var t: float = _elapsed[i] / FLOAT_SECONDS
		if t >= 1.0:
			_labels[i].visible = false
			_live[i] = 0
			_live_count -= 1
			continue
		_labels[i].position = _origin[i] - Vector2(0.0, rise * t)
		# Full opacity for the first half, then out. A number that starts fading
		# immediately is a number you have to catch rather than read.
		_labels[i].modulate.a = 1.0 - clampf(
			(t - FADE_STARTS_AT) / (1.0 - FADE_STARTS_AT), 0.0, 1.0)
	if _live_count <= 0:
		set_process(false)

# ---------------- Queries (the harness) --------------------------------------

## How many floats are animating right now. The pool itself never grows, so this
## is what a leak test watches rather than the child count.
func live_count() -> int:
	return _live_count

## The pool size, which must equal MAX_FLOATS from `_ready` until shutdown.
func pool_size() -> int:
	return get_child_count()
