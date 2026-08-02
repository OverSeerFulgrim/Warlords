extends Node2D
class_name FollowerToken
## Lightweight on-screen presence for a Follower. Followers themselves stay
## RefCounted (see Follower.gd header -- keeps the "hundreds of followers"
## case cheap); this is a purely visual token that Main.gd spawns, moves, and
## despawns in response to EventBus signals, so the simulation layer never
## has to carry Node overhead per follower.
##
## **Now a pure view**, same as WorkerToken. It used to run its own Tween idle
## wander inside a "home zone" rect, which was fine while followers did nothing
## but stand around looking recruited. Since recruits gather -- they run the
## same trip loop as Skeleton Workers, via `Laborer` -- their position is real
## simulation state that `WorkerSystem` owns, and this reads it. Same lesson as
## the WorkerToken rewrite: when a token holds its own movement state, the
## visual and the simulation drift apart.
##
## The exception is bounties/missions: those genuinely take a follower *off*
## the map, so send_away()/return_home() still glide to a gate point and hide.
## Both are currently unreachable from the UI (Stage 4 is hard-locked) but are
## kept wired for when it isn't.

var follower  # Follower (untyped to avoid a hard script dependency loop)
var gate_point: Vector2

var sprite: Sprite2D
var carry_label: Label
var star_label: Label
var _tween: Tween
var _away: bool = false

func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.centered = true
	add_child(sprite)

	# Same "+4 wood" load tag WorkerToken carries -- a recruit hauling stone
	# home should read identically to a skeleton doing it.
	carry_label = Label.new()
	carry_label.add_theme_font_size_override("font_size", 10)
	carry_label.position = Vector2(-18, -40)
	carry_label.visible = false
	add_child(carry_label)

	# Exceptional recruits (the 5% roll) are marked on the map, not just in
	# menus -- FOUNDATION_SPEC section 3 calls them "the recruits worth funding
	# houses for early", which only works if you can pick them out.
	star_label = Label.new()
	star_label.text = "★"
	star_label.add_theme_font_size_override("font_size", 12)
	star_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	star_label.position = Vector2(6, -34)
	star_label.visible = false
	add_child(star_label)

	set_process(true)

func setup(p_follower, texture: Texture2D, p_gate_point: Vector2) -> void:
	follower = p_follower
	gate_point = p_gate_point
	if texture:
		sprite.texture = texture
		# Portraits come in at ~128px source; scale down to a small token
		# footprint so a handful of them read as a crowd, not a wall of faces.
		var target_size := 40.0
		var src := texture.get_size()
		if src.x > 0.0:
			sprite.scale = Vector2.ONE * (target_size / src.x)
	star_label.visible = follower.is_exceptional
	position = follower.position

func _process(_delta: float) -> void:
	if follower == null or _away:
		return
	position = follower.position
	if follower.stage == Laborer.TripStage.WALK_HOME:
		sprite.flip_h = true
	elif follower.stage == Laborer.TripStage.WALK_TO_NODE:
		sprite.flip_h = false
	if follower.carrying_amount > 0:
		carry_label.visible = true
		carry_label.text = "+%d %s" % [follower.carrying_amount, follower.carrying_kind]
	else:
		carry_label.visible = false

## Called when this follower's bounty/mission dispatch signal fires -- glides
## to the gate and fades from view once it arrives.
func send_away() -> void:
	_away = true
	_glide_to(gate_point, 1.0)
	_tween.finished.connect(func(): visible = false)

## Called when this follower's bounty/mission resolve signal fires -- pops back
## in at the gate. Position control returns to the trip loop immediately; the
## follower walks home from the gate on their own.
func return_home() -> void:
	visible = true
	_away = false
	if follower:
		follower.position = gate_point

func _glide_to(target: Vector2, duration: float) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "position", target, duration)
