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
## On-screen height in world px of the node's **drawn content**; see
## setup_sprites(). Was a canvas width, which meant it described the picture
## rather than the tree.
var _target_height: float = 32.0
## Same, for the depleted art, because a stump is not a shorter tree -- it is a
## different object at a different real-world size (1.5 tiles becomes 0.5). Most
## nodes leave this equal to `_target_height`.
var _depleted_target_height: float = 32.0
## Kept alongside the loaded textures purely so the inspection panel can show
## whichever art is currently on screen -- Texture2D has no path back to its
## res:// source once loaded.
var _alive_sprite_path: String = ""
var _depleted_sprite_path: String = ""

# --- Deer roaming (node_type == "deer" only) ---
# "2-3 deer on the map at once ... Simple wander movement, no fleeing AI yet."
# A deer drifts between random points inside its roam rect; once a hunter is
# close enough to start the kill it holds still (see freeze()).
var roam_rect: Rect2
var _roam_target: Vector2
var _frozen: bool = false
## Terrain, for deer only -- set by ResourceField when it spawns one. Null-safe.
var world: WorldMap = null
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
	# Shared with the wolf -- see Roaming.gd for why this is two static helpers
	# rather than a base class the deer and the wolf both extend.
	if Roaming.arrived(position, _roam_target):
		_pick_roam_target()
	var before: Vector2 = position
	position = Roaming.step(position, _roam_target, DEER_WANDER_SPEED, delta, world)
	if position.is_equal_approx(before):
		_pick_roam_target()  # wedged against terrain -- amble somewhere else

func _pick_roam_target() -> void:
	_roam_target = Roaming.random_point_in(roam_rect, world)

## Stops a deer moving while it's being hunted, so the hunter isn't chasing a
## target that keeps sliding out from under them. Harmless no-op for every
## other node type.
func freeze(value: bool) -> void:
	_frozen = value

## `target_height` is how tall the **thing drawn on the sprite** should be on
## screen, in world pixels -- not how wide its canvas is. A pine and a grave sit
## very differently inside their identical 128px frames, so a canvas target
## described neither of them (the pine asked for 76 and drew 43).
##
## Width falls out of the art's own aspect ratio, which is correct: the stone
## deposit is a wide flat outcrop and comes out roughly 82px across from a 45px
## height target.
## `depleted_height` defaults to the alive height; pass it only where the spent
## state is a genuinely different-sized object, which so far is the pine (a
## 1.5-tile tree leaves a 0.5-tile stump).
func setup_sprites(
	alive_path: String,
	depleted_path: String,
	target_height: float,
	depleted_height: float = -1.0,
) -> void:
	_target_height = target_height
	_depleted_target_height = target_height if depleted_height < 0.0 else depleted_height
	_alive_sprite_path = alive_path
	_depleted_sprite_path = depleted_path
	_alive_texture = _load_texture(alive_path)
	_depleted_texture = _load_texture(depleted_path) if depleted_path != "" else null
	_refresh_visual()

## Whichever art is showing right now -- stump rather than tree once chopped.
## The inspection panel's portrait uses this so the picture matches the state
## the details rows are describing.
func current_sprite_path() -> String:
	if is_depleted() and _depleted_sprite_path != "":
		return _depleted_sprite_path
	return _alive_sprite_path

## Click-selection radius, in world pixels. Derived from the node's **drawn
## content**, not from its size target: the stone deposit is asked for 45px of
## height and covers ~82px of ground, and a circle built from the height alone
## would leave most of the outcrop unclickable. A floor keeps the smallest nodes
## (a 26px carcass) hittable without pixel-hunting.
func hit_radius() -> float:
	var drawn: Vector2 = Anchoring.drawn_content_size(_sprite)
	return maxf(18.0, maxf(drawn.x, drawn.y) * 0.6)

## Scale is recomputed from whichever texture is actually showing, rather than
## fixed once from the alive one. The alive and depleted art are not guaranteed
## to share dimensions -- and when they didn't, swapping in the depleted
## texture kept the alive texture's scale factor and rendered it at the wrong
## size. Now they also don't share a *content* box even when the canvases match:
## a stump occupies far less of its 128px frame than the pine it replaces, so
## rescaling per texture is what keeps the stump reading as 0.5 tiles.
func _apply_scale_for(tex: Texture2D, target_height: float) -> void:
	if tex == null or tex.get_size().x <= 0.0:
		return
	_sprite.scale = Vector2.ONE * Anchoring.scale_for_content_height(tex, target_height)
	# A tree's position is the base of its trunk, not the middle of its canopy.
	# Re-applied per texture because the depleted art can differ in height from
	# the alive art, and the anchor is computed from whichever is showing.
	Anchoring.foot(_sprite)

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
			# "Pine", not just "Tree" -- the commissioned art is specifically a
			# pine, and the stump it leaves behind is its own sprite.
			return "Pine Stump" if is_depleted() else "Pine Tree"
		"stone_deposit":
			return "Stone Deposit"
		"berry_grove":
			return "Berry Grove"
		"carcass":
			return "Animal Carcass"
		"grave":
			return "Spent Grave" if is_depleted() else "Grave"
		"deer":
			return "Deer"
		_:
			return node_type.capitalize()

# ---------------- Inspection (see InspectionPanel.gd for the contract) -------

## One flavor line per node type. Lives here rather than in the panel because
## the panel is deliberately type-blind -- see InspectionPanel's header.
const FLAVOR := {
	"tree": "A cold-country pine. Sound timber, if someone can be bothered to swing at it.",
	"stone_deposit": "Raw rock pushing up through the frost. Deep enough to outlast you.",
	"berry_grove": "Hardy winter berries. Stripped bare by evening, back by morning.",
	"carcass": "Something died here a while ago. The bones are still good.",
	"grave": "Someone was buried here and mourned. Neither fact is your concern.",
	"deer": "Wary, and faster than your labourers. Worth the walk.",
}

## Depleted-state line, so an emptied node says what it is now rather than
## just reading "0 left" -- FOUNDATION_SPEC section 11.1 wants exhaustion to be
## legible, and the panel is where a player goes to ask "why is nobody working
## this?".
const SPENT_NOTE := {
	"tree": "Chopped out. Only a stump remains.",
	"stone_deposit": "Quarried out. Nothing workable left.",
	"berry_grove": "Picked clean — but it will bear again at dawn.",
	"carcass": "Stripped to nothing.",
	"grave": "Already dug up. There is nothing left to rob.",
	"deer": "Hunted.",
}

func get_inspect_data() -> Dictionary:
	var rows: Array = []

	if is_depleted():
		rows.append({"label": "Remaining", "value": "Empty", "color": Color(0.95, 0.6, 0.5)})
		rows.append({"label": "", "value": SPENT_NOTE.get(node_type, "Exhausted."), "muted": true})
	else:
		rows.append({"label": "Remaining", "value": "%d / %d %s" % [remaining, capacity, kind]})

	rows.append({"label": "Gathered by", "value": skill_key.capitalize()})

	# The deer is the one node that yields its whole stock in a single action
	# (FOUNDATION_SPEC section 5, "whole deer on kill"), which is exactly the
	# thing worth telling the player about it.
	if yield_per_action > 1:
		rows.append({"label": "Yield", "value": "%d %s in one action" % [yield_per_action, kind]})

	if regrows_per_dawn > 0:
		rows.append({"label": "Regrowth", "value": "+%d at dawn, up to %d" % [regrows_per_dawn, capacity]})
	else:
		rows.append({"label": "Regrowth", "value": "None — finite", "muted": true})

	if claims > 0:
		rows.append({"label": "Claimed by", "value": "%d worker%s" % [claims, "" if claims == 1 else "s"]})

	return {
		"title": display_name(),
		"subtitle": "Resource node",
		"sprite": current_sprite_path(),
		"description": FLAVOR.get(node_type, ""),
		"details": rows,
	}

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
			_apply_scale_for(_depleted_texture, _depleted_target_height)
			# The commissioned depleted sprites (stump, dug-up grave, picked
			# grove) already read as spent on their own, so they're drawn at
			# full colour. The old placeholders needed dimming because they
			# were the same image reused.
			_sprite.modulate = Color(1, 1, 1, 1)
		else:
			# No empty-state art: a killed deer / emptied carcass just goes
			# away rather than lingering as a ghost sprite.
			_sprite.texture = _alive_texture
			_apply_scale_for(_alive_texture, _target_height)
			_sprite.modulate = Color(1, 1, 1, 0.0)
		return
	_sprite.texture = _alive_texture
	_apply_scale_for(_alive_texture, _target_height)
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
