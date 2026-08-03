extends Node2D
class_name ResourceNode
## A single physical thing on the map that a Worker can walk to and harvest:
## one tree, one stone deposit, one berry grove, one animal carcass, one
## grave, one deer. Implements FOUNDATION_SPEC section 5's node table.
##
## This is a Node2D rather than a RefCounted (unlike Worker/Follower) for the
## obvious reason: a resource node's whole point is that it occupies a spot on
## the map you have to walk to, and it visibly changes as it's worked. Its
## position IS gameplay data now -- WorkerSystem's trip loop measures walking
## distance against it.
##
## Depletion is visible, not just numeric: a chopped-out tree swaps to a stump
## sprite, an emptied grave dims to a spent marker, a picked-over berry grove
## fades toward transparent as its stock drops. That visibility is a stated
## foundation exit criterion ("trees visibly deplete", FOUNDATION_SPEC section
## 11.1), not decoration.

## Which GameState resource this yields. One of "wood"/"stone"/"food"/"bones"
## -- the four mundane resources. Deliberately the same strings GameState's
## add_resource() takes, so depositing is a straight pass-through.
@export var kind: String = ""

## Flavor/routing subtype: "tree", "stone_deposit", "berry_grove", "carcass",
## "grave", "deer". Two node types can share a `kind` (berry grove and deer
## are both "food") -- the priority list routes by `kind`, and which specific
## node gets picked is a nearest-available question (see ResourceField).
@export var node_type: String = ""

## Which labor skill sets the work speed here (FOUNDATION_SPEC section 6).
## Hunting a deer uses Foraging too -- it's the find/stalk skill.
@export var skill_key: String = "foraging"

var remaining: int = 0
var capacity: int = 0          # starting/max stock; regrowth caps at this
var yield_per_action: int = 1  # units produced by one completed gather action
var regrows_per_dawn: int = 0  # 0 = finite, no regrowth (trees, stone, bones)

## Soft crowding hint, not a lock: incremented while a worker is en route or
## working here. ResourceField's node picker penalizes already-claimed nodes
## so three workers spread across three trees instead of all queueing on the
## nearest one -- but it will still hand out a claimed node when that's the
## only one left, which is what has to happen for a single Stone Deposit
## shared by the whole workforce. See ResourceField.find_best_node().
var claims: int = 0

var _sprite: Sprite2D
var _alive_texture: Texture2D
var _depleted_texture: Texture2D
## On-screen width in px this node should occupy; see setup_sprites().
var _target_size: float = 32.0

# --- Deer roaming (node_type == "deer" only) ---
# "2-3 deer on the map at once ... Simple wander movement, no fleeing AI yet."
# A deer drifts between random points inside its roam rect; once a hunter is
# close enough to start the kill it holds still (see freeze()).
var roam_rect: Rect2
var _roam_target: Vector2
var _frozen: bool = false
const DEER_WANDER_SPEED: float = 18.0  # px/sec -- an amble, well under any worker's walk

func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.centered = true
	add_child(_sprite)
	_refresh_visual()
	set_process(node_type == "deer")
	if node_type == "deer":
		_pick_roam_target()

func _process(delta: float) -> void:
	if _frozen or is_depleted():
		return
	if position.distance_to(_roam_target) < 4.0:
		_pick_roam_target()
	position += position.direction_to(_roam_target) * DEER_WANDER_SPEED * delta

func _pick_roam_target() -> void:
	_roam_target = Vector2(
		randf_range(roam_rect.position.x, roam_rect.position.x + roam_rect.size.x),
		randf_range(roam_rect.position.y, roam_rect.position.y + roam_rect.size.y)
	)

## Stops a deer moving while it's being hunted, so the hunter isn't chasing a
## target that keeps sliding out from under them. Harmless no-op for every
## other node type.
func freeze(value: bool) -> void:
	_frozen = value

## `target_size` is the on-screen width in pixels the node should occupy,
## regardless of how large the source art is -- the commissioned sprites are
## 1024px square, so everything here is scaled down by ~0.03-0.06.
func setup_sprites(alive_path: String, depleted_path: String, target_size: float) -> void:
	_target_size = target_size
	_alive_texture = _load_texture(alive_path)
	_depleted_texture = _load_texture(depleted_path) if depleted_path != "" else null
	_refresh_visual()

## Scale is recomputed from whichever texture is actually showing, rather than
## fixed once from the alive one. The alive and depleted art are not guaranteed
## to share dimensions -- and when they didn't, swapping in the depleted
## texture kept the alive texture's scale factor and rendered it at the wrong
## size. Currently every pair happens to match at 1024px, so this is a latent
## bug being closed rather than a visible one being fixed.
func _apply_scale_for(tex: Texture2D) -> void:
	if tex == null or tex.get_size().x <= 0.0:
		return
	_sprite.scale = Vector2.ONE * (_target_size / tex.get_size().x)

func _load_texture(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		push_warning("ResourceNode: sprite not found at %s" % path)
		return null
	return load(path)

func is_depleted() -> bool:
	return remaining <= 0

## How long one gather action takes for a given worker, per FOUNDATION_SPEC
## section 6: `base_time * 5 / skill`, base_time 4s. The human peasant (skill
## 5) lands on exactly 4s, which is what the old flat WorkerSystem tick used
## -- so overall pacing survives the switch to a real trip loop. A Gray Dwarf
## mining at 9 gets ~2.2s; a Skeleton at 3 gets ~6.7s. Skill is visible as
## speed rather than as a permission.
const BASE_ACTION_TIME: float = 4.0
const SKILL_REFERENCE: float = 5.0

func action_time_for_skill(skill: int) -> float:
	# max(1, ...) mirrors the 1-10 stat floor -- skills can never legitimately
	# be 0, but guarding here means a bad data row can't divide by zero.
	return BASE_ACTION_TIME * SKILL_REFERENCE / float(max(1, skill))

## Removes up to `amount` units and returns how many were actually taken
## (fewer than asked for when the node runs dry mid-action). Callers must use
## the return value, not the request, when crediting a worker's load.
func take(amount: int) -> int:
	var taken: int = min(amount, remaining)
	remaining -= taken
	if taken > 0:
		_refresh_visual()
		if is_depleted():
			EventBus.resource_node_depleted.emit(self)
	return taken

## Dawn regrowth (FOUNDATION_SPEC section 5): only the Berry Grove renews, and
## only up to its cap. Everything else -- trees, stone, carcasses, graves -- is
## finite on purpose: the map running out of bones is exactly what's meant to
## make Stage 4's harvest bounties attractive.
func regrow() -> void:
	if regrows_per_dawn <= 0:
		return
	var before := remaining
	remaining = min(capacity, remaining + regrows_per_dawn)
	if remaining != before:
		_refresh_visual()

func display_name() -> String:
	match node_type:
		"tree":
			return "Stump" if is_depleted() else "Tree"
		"stone_deposit":
			return "Stone Deposit"
		"berry_grove":
			return "Berry Grove"
		"carcass":
			return "Animal Bones"
		"grave":
			return "Spent Grave" if is_depleted() else "Grave"
		"deer":
			return "Deer"
		_:
			return node_type.capitalize()

## Swaps to the depleted sprite where there is one (tree -> stump, grave ->
## spent marker) and otherwise fades toward transparent in proportion to how
## picked-over the node is. The fade is what makes a Stone Deposit or Berry
## Grove read as "getting low" when it has no distinct empty-state art.
func _refresh_visual() -> void:
	if not _sprite:
		return
	if is_depleted():
		if _depleted_texture:
			_sprite.texture = _depleted_texture
			_apply_scale_for(_depleted_texture)
			# The commissioned depleted sprites (stump, dug-up grave, picked
			# grove) already read as spent on their own, so they're drawn at
			# full colour. The old placeholders needed dimming because they
			# were the same image reused.
			_sprite.modulate = Color(1, 1, 1, 1)
		else:
			# No empty-state art: a killed deer / emptied carcass just goes
			# away rather than lingering as a ghost sprite.
			_sprite.texture = _alive_texture
			_apply_scale_for(_alive_texture)
			_sprite.modulate = Color(1, 1, 1, 0.0)
		return
	_sprite.texture = _alive_texture
	_apply_scale_for(_alive_texture)
	var fullness: float = float(remaining) / float(max(1, capacity))
	# Floor at 0.45 alpha -- a nearly-empty node still has to be findable and
	# clickable, it just shouldn't look untouched.
	_sprite.modulate = Color(1, 1, 1, lerpf(0.45, 1.0, fullness))

# ---------------- Factories (one per FOUNDATION_SPEC section 5 row) ----------------

const TREE_STOCK: int = 10
const STONE_DEPOSIT_STOCK: int = 250
const BERRY_GROVE_CAP: int = 40
const BERRY_REGROWTH_PER_DAWN: int = 8
const CARCASS_STOCK: int = 5
const GRAVE_STOCK: int = 12
const DEER_STOCK: int = 8

static func make_tree(pos: Vector2) -> ResourceNode:
	var n := ResourceNode.new()
	n.kind = "wood"
	n.node_type = "tree"
	n.skill_key = "woodcutting"
	n.capacity = TREE_STOCK
	n.remaining = TREE_STOCK
	n.position = pos
	return n

static func make_stone_deposit(pos: Vector2) -> ResourceNode:
	var n := ResourceNode.new()
	n.kind = "stone"
	n.node_type = "stone_deposit"
	n.skill_key = "mining"
	n.capacity = STONE_DEPOSIT_STOCK
	n.remaining = STONE_DEPOSIT_STOCK
	n.position = pos
	return n

static func make_berry_grove(pos: Vector2) -> ResourceNode:
	var n := ResourceNode.new()
	n.kind = "food"
	n.node_type = "berry_grove"
	n.skill_key = "foraging"
	n.capacity = BERRY_GROVE_CAP
	n.remaining = BERRY_GROVE_CAP
	n.regrows_per_dawn = BERRY_REGROWTH_PER_DAWN
	n.position = pos
	return n

static func make_carcass(pos: Vector2) -> ResourceNode:
	var n := ResourceNode.new()
	n.kind = "bones"
	n.node_type = "carcass"
	n.skill_key = "foraging"
	n.capacity = CARCASS_STOCK
	n.remaining = CARCASS_STOCK
	n.position = pos
	return n

static func make_grave(pos: Vector2) -> ResourceNode:
	var n := ResourceNode.new()
	n.kind = "bones"
	n.node_type = "grave"
	# Digging is mining, not foraging -- a grave is a hole, not a forage find.
	n.skill_key = "mining"
	n.capacity = GRAVE_STOCK
	n.remaining = GRAVE_STOCK
	n.position = pos
	return n

## The one node that doesn't yield per-unit: FOUNDATION_SPEC section 5 says a
## deer is "whole deer on kill" and is "hauled home like any load", so a single
## completed action produces all 8 Food at once. That deliberately overrides
## the carry-capacity-= Might rule in WorkerSystem -- a Might-4 skeleton could
## otherwise never bring a deer home at all, which would make the whole
## higher-yield-but-longer-trip tradeoff unreachable for undead labor.
static func make_deer(pos: Vector2, p_roam_rect: Rect2) -> ResourceNode:
	var n := ResourceNode.new()
	n.kind = "food"
	n.node_type = "deer"
	n.skill_key = "foraging"
	n.capacity = DEER_STOCK
	n.remaining = DEER_STOCK
	n.yield_per_action = DEER_STOCK
	n.position = pos
	n.roam_rect = p_roam_rect
	return n
