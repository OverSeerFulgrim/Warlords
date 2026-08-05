extends Node2D
class_name WorkerToken
## On-screen presence for a Worker -- now a **pure view**. It reads
## `worker.position` and draws there. It decides nothing.
##
## This used to run its own 4-stage Tween glide loop (AT_KEEP -> TO_NODE ->
## AT_NODE -> TO_KEEP) whose timing was hand-tuned to *look* like it matched
## WorkerSystem's flat 4s gather tick, with a header comment admitting the two
## were not actually the same clock and that unifying them was a later pass.
## This is that pass. The glide loop is gone: the trip is real, it happens in
## WorkerSystem against real map positions and real walk speeds, and this node
## just renders the result. There is no longer any way for the animation and
## the economy to disagree, because there is only one of them.
##
## The RefCounted/Node2D split is unchanged and still the point -- Worker stays
## a cheap data object, and this is the only part that costs a scene-tree slot.
## What moved is *authority*: position is now data on the Worker, not state
## owned by the token.

var worker  # Worker (untyped to avoid a hard script dependency loop)

var sprite: Sprite2D
var carry_label: Label

## Workers read as smaller/plainer than Follower portraits on purpose -- the
## trait-less, interchangeable labor unit, not the roster.
##
## **48px = 0.75 of a 64px tile.** Was 32, which measured at half a tile: every
## object on the map was smaller than the ground it stood on, and playtest read
## the whole scene as miniature. Sizes across the project are now expressed as
## fractions of `CELL_SIZE` -- see CLAUDE.md's art provenance section for the
## table.
const SPRITE_TARGET_SIZE: float = 48.0

func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.centered = true
	add_child(sprite)

	# A tiny "+4 wood" tag above a hauling worker. The load is the whole point
	# of the trip loop being visible -- without it, a worker walking home looks
	# identical to one walking out.
	carry_label = Label.new()
	carry_label.add_theme_font_size_override("font_size", 10)
	# Above the sprite's head. Derived from the target size rather than a magic
	# number, so growing the art can't put the tag behind the worker's face.
	carry_label.position = Vector2(-18, -SPRITE_TARGET_SIZE - 14.0)
	carry_label.visible = false
	add_child(carry_label)

	set_process(true)

func setup(p_worker, texture: Texture2D) -> void:
	worker = p_worker
	if texture:
		sprite.texture = texture
		var src := texture.get_size()
		if src.x > 0.0:
			sprite.scale = Vector2.ONE * (SPRITE_TARGET_SIZE / src.x)
		# The worker's position is where he stands, not where his waist is.
		Anchoring.foot(sprite)
	position = worker.position

## Click-selection radius. Derived from the drawn size so the hit area and the
## art can never drift apart -- Main used to pass a hardcoded 16.0 here, which
## would have left clicks landing beside a 48px worker.
func hit_radius() -> float:
	return SPRITE_TARGET_SIZE * Anchoring.HIT_RADIUS_FRACTION

func _process(_delta: float) -> void:
	if worker == null:
		return
	position = worker.position
	# Face the way they're walking -- cheap, and it makes a busy map legible at
	# a glance without any animation frames.
	if worker.stage == Worker.TripStage.WALK_HOME:
		sprite.flip_h = true
	elif worker.stage == Worker.TripStage.WALK_TO_NODE:
		sprite.flip_h = false
	if worker.carrying_amount > 0:
		carry_label.visible = true
		carry_label.text = "+%d %s" % [worker.carrying_amount, worker.carrying_kind]
	else:
		carry_label.visible = false
