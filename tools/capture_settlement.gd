extends SceneTree
## Boots the real game, lets it settle, and writes a PNG of the actual rendered
## frame. Run **windowed, not headless** -- there is no framebuffer to read in
## headless mode:
##
##   godot --path . --resolution 1400x760 -s res://tools/capture_settlement.gd -- <out.png> [zoom]
##
## Exists because the godot-mcp bridge is only available when the editor happens
## to be running with the plugin connected, and a before/after screenshot pair
## is the only way to check a sizing change. It renders the same `Main.tscn` the
## player launches, at the same default camera zoom, so what it captures is what
## the player sees.

## The game opens on the world map with the camera following the Necromancer,
## which is the wrong frame for judging sprite sizes -- the settlement's resource
## nodes are off-screen to the south-east. So the capture walks the villain into
## the forest, chops out two of the trees so both a pine and a stump are in
## frame next to him, and points the camera there at the default zoom. Nothing
## here changes the game; it is the same thing a player does with WASD and a
## worker, done instantly.
const CHOPPED_TREES: int = 2
## Frames to let elapse before capturing. Main's camera framing deliberately
## re-runs after two frames (Control sizes aren't final on the frame they're
## created), and the resource field seeds on ready, so a capture on frame 1
## shows a half-built settlement centred on the wrong point.
const SETTLE_FRAMES: int = 90

## **The forest is seeded with `randf_range`**, so two runs place their trees in
## different spots and a before/after pair taken without this is comparing two
## different maps. Fixing the global seed makes the two captures the same
## settlement with only the sprite sizes different, which is the entire point of
## taking a pair.
const CAPTURE_SEED: int = 20260805

var _out_path: String = "user://settlement.png"
## Multiplies the game's default camera zoom. 1.0 is what the player sees on
## launch and is the frame the sizing decision has to be judged in; a larger
## value is for detail shots where a 32px stump is otherwise a few pixels.
var _zoom_mult: float = 1.0
var _frames: int = 0
var _framed: bool = false

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_path = args[0]
	if args.size() > 1:
		_zoom_mult = maxf(0.1, args[1].to_float())
	seed(CAPTURE_SEED)
	change_scene_to_file("res://scenes/Main.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	# Main re-frames the camera a couple of frames in (Control sizes aren't
	# final on the frame they're created), so pose the scene after that has
	# settled and let it render for a while longer.
	if _frames == SETTLE_FRAMES / 2 and not _framed:
		_framed = true
		_pose()
	if _frames < SETTLE_FRAMES:
		return false
	var img: Image = root.get_texture().get_image()
	if img == null:
		printerr("capture_settlement: no framebuffer -- did this run with --headless?")
		return true
	# No flip_y(): the GL Compatibility renderer hands back a top-down image
	# already, and flipping it produced a 180-degree-rotated capture.
	var err: int = img.save_png(_out_path)
	print("capture_settlement: -> %s (err %d)" % [_out_path, err])
	return true

## Walks the villain to the forest, leaves a couple of stumps, and frames it.
func _pose() -> void:
	var main: Node = current_scene
	if main == null:
		return
	var field = main.get("resource_field")
	var villain = main.get("villain")
	var camera = main.get("camera")
	if field == null:
		return

	var trees: Array = []
	for n in field.nodes:
		if n.node_type == "tree":
			trees.append(n)
	if trees.is_empty():
		return
	trees.sort_custom(func(a, b): return a.position.x < b.position.x)

	# Chop the westernmost few, so the stumps sit on the settlement side of the
	# treeline where the villain is standing rather than buried in the canopy.
	for i in range(mini(CHOPPED_TREES, trees.size())):
		trees[i].take(trees[i].remaining)

	# Stand the villain right beside the westernmost pine and its fresh stump, so
	# "is the tree taller than him, and is the stump not" is one glance rather
	# than a measurement.
	var focus: Vector2 = trees[0].position
	if villain != null:
		villain.place_at(focus + Vector2(-70.0, 30.0))
		var controller = main.get("villain_controller")
		if controller != null:
			controller.snap_to_villain()
	if camera != null:
		camera.center_on(focus)
		if not is_equal_approx(_zoom_mult, 1.0):
			camera.zoom *= _zoom_mult
			camera.center_on(focus)   # re-solve the HUD inset at the new zoom
	print("capture_settlement: posed at %s, %d trees, %d chopped, zoom x%.2f"
		% [focus, trees.size(), mini(CHOPPED_TREES, trees.size()), _zoom_mult])
