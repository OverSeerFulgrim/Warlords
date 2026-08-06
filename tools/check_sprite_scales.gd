extends Node
## Asserts that every sized thing on the settlement layer draws its **content**
## at the size its constant claims. Run:
##
##   godot --headless --path . res://tools/check_sprite_scales.tscn
##
## **A scene, not a `-s` SceneTree script**, for the same reason
## `measure_travel.tscn` is: under `-s` the script is compiled before the
## autoloads exist, so every class that transitively touches `EventBus` or
## `GameState` -- which is `ResourceNode`, `Building` and most of the rest --
## fails to compile, and the failure surfaces as "Nonexistent function
## 'make_tree' in base 'GDScript'" rather than as anything mentioning autoloads.
##
## The bug this guards against is silent: a scale site that divides by
## `texture.get_size().x` still runs, still looks plausible, and just draws the
## wrong size. Nothing about it shows up as an error, which is why it survived
## a whole art pass. These checks compare the drawn alpha box against the
## constant, so the only way to pass is to have actually used the content.

const CELL: float = 64.0
const TOLERANCE_PX: float = 1.5

var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	_check_helper()
	_check_resource_nodes()
	_check_tokens()
	_check_buildings()
	_check_orderings()
	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

# ---------------- The helper itself ----------------

func _check_helper() -> void:
	print("\n-- Anchoring.content_rect --")
	var tex: Texture2D = load("res://assets/official/nodes/Pine_Tree.png")
	var box: Rect2 = Anchoring.content_rect(tex)
	_eq("pine content box is the alpha bbox, not the canvas", box.size, Vector2(78, 120))
	_ok("pine canvas is 128x128, so the box is genuinely smaller",
		box.size.x < tex.get_size().x and box.size.y < tex.get_size().y)
	# Second call must come from the cache, and must agree with the first.
	_eq("cached lookup returns the same box", Anchoring.content_rect(tex).size, box.size)
	_ok("cache is keyed by resource path", Anchoring._content_cache.has(tex.resource_path))

	var s: float = Anchoring.scale_for_content_height(tex, 96.0)
	_close("scale_for_content_height(96) puts 96px of tree on screen", box.size.y * s, 96.0)
	_close("...and lets width follow the art", box.size.x * s, 78.0 * 96.0 / 120.0)

	var stone: Texture2D = load("res://assets/placeholder/kenney/materials_005_stone.png")
	var stone_box: Rect2 = Anchoring.content_rect(stone)
	var ss: float = Anchoring.scale_for_content_height(stone, 45.0)
	_close("the wide flat stone outcrop comes out ~82px across from a 45px height",
		stone_box.size.x * ss, 82.0, 1.0)

# ---------------- Resource nodes ----------------

## Every row of the table in ResourceField, in world px of content height.
const EXPECTED_NODES := [
	["tree", 96.0, 1.50],
	["stump", 32.0, 0.50],
	["berry_grove", 58.0, 0.90],
	["grave", 48.0, 0.75],
	["stone_deposit", 45.0, 0.70],
	["carcass", 26.0, 0.40],
	["deer", 58.0, 0.90],
]

func _check_resource_nodes() -> void:
	print("\n-- Resource nodes (content height) --")
	for row in EXPECTED_NODES:
		var kind: String = row[0]
		var want: float = row[1]
		var tiles: float = row[2]
		var node: ResourceNode = _make_node(kind)
		add_child(node)
		var sprite: Sprite2D = node.get_child(0)
		var drawn: Vector2 = Anchoring.drawn_content_size(sprite)
		_close("%s draws %.0fpx tall (%.2f tiles)" % [kind, want, tiles], drawn.y, want)
		_close("...which is %.2f of a tile" % tiles, want / CELL, tiles, 0.01)
		node.queue_free()

## Builds a seeded node of each type with the sprites and sizes ResourceField
## hands it, then depletes it where the check is about the spent art.
func _make_node(kind: String) -> ResourceNode:
	var n: ResourceNode
	match kind:
		"tree", "stump":
			n = ResourceNode.make_tree(Vector2.ZERO)
			n.setup_sprites(ResourceField.SPRITE_TREE, ResourceField.SPRITE_STUMP,
				ResourceField.NODE_SIZE_TREE, ResourceField.NODE_SIZE_STUMP)
			if kind == "stump":
				n.take(n.remaining)
		"berry_grove":
			n = ResourceNode.make_berry_grove(Vector2.ZERO)
			n.setup_sprites(ResourceField.SPRITE_BERRY, ResourceField.SPRITE_BERRY_PICKED,
				ResourceField.NODE_SIZE_GROVE)
		"grave":
			n = ResourceNode.make_grave(Vector2.ZERO)
			n.setup_sprites(ResourceField.SPRITE_GRAVE, ResourceField.SPRITE_GRAVE_SPENT,
				ResourceField.NODE_SIZE_GRAVE)
		"stone_deposit":
			n = ResourceNode.make_stone_deposit(Vector2.ZERO)
			n.setup_sprites(ResourceField.SPRITE_STONE, "", ResourceField.NODE_SIZE_STONE)
		"carcass":
			n = ResourceNode.make_carcass(Vector2.ZERO)
			n.setup_sprites(ResourceField.SPRITE_CARCASS, "", ResourceField.NODE_SIZE_CARCASS)
		"deer":
			n = ResourceNode.make_deer(Vector2.ZERO, Rect2())
			n.setup_sprites(ResourceField.SPRITE_DEER, "", ResourceField.NODE_SIZE_DEER)
	return n

# ---------------- Unit tokens ----------------

func _check_tokens() -> void:
	print("\n-- Unit tokens (SPRITE_SPEC.md section 3 families) --")

	_close("Skeleton Worker (Medium) is 0.90 tiles",
		WorkerToken.SPRITE_TARGET_SIZE / CELL, 0.90, 0.01)
	_close("Follower (Medium) is 0.90 tiles",
		FollowerToken.SPRITE_TARGET_SIZE / CELL, 0.90, 0.01)
	_close("Necromancer (Villain) is 1.05 tiles",
		NecromancerToken.TOKEN_SIZE / CELL, 1.05, 0.01)
	_close("Wolf (Quadruped) is 1.15 tiles WIDE",
		Wolf.TOKEN_SIZE / CELL, 1.15, 0.01)

	var worker := WorkerToken.new()
	add_child(worker)
	worker.sprite.texture = load("res://assets/official/characters/Skeleton_Worker.png")
	worker.sprite.scale = Vector2.ONE * Anchoring.scale_for_content_height(
		worker.sprite.texture, WorkerToken.SPRITE_TARGET_SIZE)
	Anchoring.foot(worker.sprite)
	var w_drawn: Vector2 = Anchoring.drawn_content_size(worker.sprite)
	_close("...the skeleton actually draws 58px of skeleton", w_drawn.y, 58.0)
	_ok("...and its hit radius follows the content, not the constant",
		absf(worker.hit_radius() - maxf(w_drawn.x, w_drawn.y) * Anchoring.HIT_RADIUS_FRACTION) < 0.01)

	var necro := NecromancerToken.new()
	add_child(necro)
	var n_drawn: Vector2 = Anchoring.drawn_content_size(necro.sprite)
	_close("the Necromancer actually draws 67px of necromancer", n_drawn.y, 67.0)

	var wolf := Wolf.new()
	add_child(wolf)
	var wolf_drawn: Vector2 = Anchoring.drawn_content_size(wolf.get_child(0))
	_close("the wolf actually draws 74px of wolf across", wolf_drawn.x, 74.0)

	print("   (necromancer %.0fx%.0f, wolf %.0fx%.0f)"
		% [n_drawn.x, n_drawn.y, wolf_drawn.x, wolf_drawn.y])

	worker.queue_free()
	necro.queue_free()
	wolf.queue_free()

# ---------------- Buildings ----------------

func _check_buildings() -> void:
	print("\n-- Buildings (content height, one cap for all art) --")
	var paths := {
		"Throne of Bones": "res://assets/official/buildings/Throne_of_Bones.png",
		"Barracks": "res://assets/official/buildings/Barracks.png",
		"Bone Pile": "res://assets/official/buildings/Bone_Pile.png",
		"recruit house": "res://assets/placeholder/kenney/House/house_1_blue.png",
		"Workshop tower": "res://assets/placeholder/kenney/Tower/tower_red.png",
	}
	for name: String in paths.keys():
		var b := Building.new()
		b.sprite_path = paths[name]
		add_child(b)
		var sprite: Sprite2D = b.get_child(0)
		var drawn: Vector2 = Anchoring.drawn_content_size(sprite)
		_close("%s stands %.0fpx tall" % [name, Building.SPRITE_MAX_SIDE],
			drawn.y, Building.SPRITE_MAX_SIDE)
		print("   (%s draws %.0fx%.0f)" % [name, drawn.x, drawn.y])
		b.queue_free()

# ---------------- The orderings that are the actual point ----------------

func _check_orderings() -> void:
	print("\n-- Orderings the playtest has to show --")
	_ok("a pine towers over the Necromancer",
		ResourceField.NODE_SIZE_TREE > NecromancerToken.TOKEN_SIZE + 20.0)
	_ok("a stump does not",
		ResourceField.NODE_SIZE_STUMP < NecromancerToken.TOKEN_SIZE * 0.6)
	_ok("a pine is three times its own stump",
		ResourceField.NODE_SIZE_TREE / ResourceField.NODE_SIZE_STUMP >= 2.5)
	_ok("the Necromancer is the tallest humanoid",
		NecromancerToken.TOKEN_SIZE > FollowerToken.SPRITE_TARGET_SIZE
		and NecromancerToken.TOKEN_SIZE > WorkerToken.SPRITE_TARGET_SIZE)
	# SPRITE_SPEC section 5: the deer is the tall short one, the wolf the low long
	# one, and that contrast is what stops them being confused at night.
	_ok("the deer stands taller than the wolf", ResourceField.NODE_SIZE_DEER > 51.0)
	_ok("the carcass is the smallest thing on the map",
		ResourceField.NODE_SIZE_CARCASS < ResourceField.NODE_SIZE_STUMP)

# ---------------- Assertions ----------------

func _ok(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("  PASS  %s" % label)
	else:
		_failed += 1
		printerr("  FAIL  %s" % label)

func _eq(label: String, got: Variant, want: Variant) -> void:
	_ok("%s  (got %s)" % [label, got], got == want)

func _close(label: String, got: float, want: float, tol: float = TOLERANCE_PX) -> void:
	_ok("%s  (got %.2f, want %.2f)" % [label, got, want], absf(got - want) <= tol)
