extends Node2D
class_name ResourceField
## Owns every ResourceNode on the map: seeds them at game start, answers "what
## should this worker walk to next", and handles the dawn upkeep (berry
## regrowth, a new deer wandering in).
##
## Split out from Main.gd's old _build_resource_nodes() because the map's
## resources are now a real system with queries and per-dawn behavior, not two
## decorative sprites. Main constructs and positions it; WorkerSystem holds a
## reference and asks it for targets. Neither reaches into `nodes` directly --
## go through find_best_node()/nodes_of_kind() so the crowding and depletion
## rules stay in one place.
##
## Map seeds are FOUNDATION_SPEC section 5's list, at fixed positions ("Fixed
## positions for now, procedural later" -- procgen is still out of scope, see
## CLAUDE.md).

const FOREST_TREE_COUNT: int = 20
const FOREST_CARCASS_COUNT: int = 4
const GRAVE_COUNT: int = 2
const DEER_CAP: int = 3
const DEER_STARTING_COUNT: int = 2

## Added to a node's effective distance for each worker already heading to or
## working it. Roughly three grid cells: enough that a worker will happily
## walk past a busy tree to an idle one a couple of cells further out, but not
## so much that the single Stone Deposit stops being worth sharing.
const CROWDING_PENALTY_PX: float = 200.0

## Art notes: trees, berry groves and graves now use the commissioned art in
## "Official Sprites/" -- each with a real depleted-state sprite, so a chopped
## tree becomes an actual stump and a robbed grave an actual dug-up pit rather
## than the same image dimmed. Still placeholder: the stone deposit (Kenney
## materials icon) and the deer (generated, see tools/make_deer_sprite.gd).
const SPRITE_TREE := "res://assets/official/nodes/Pine_Tree.png"
const SPRITE_STUMP := "res://assets/official/nodes/Pine_Stump.png"
const SPRITE_BERRY := "res://assets/official/nodes/Berry_Grove_Full.png"
## The grove regrows at dawn, so "picked" is a *state*, not an end state --
## ResourceNode swaps back to the full sprite the moment remaining goes above 0.
const SPRITE_BERRY_PICKED := "res://assets/official/nodes/Berry_Grove_Picked.png"
const SPRITE_GRAVE := "res://assets/official/nodes/Grave_Undisturbed.png"
const SPRITE_GRAVE_SPENT := "res://assets/official/nodes/Grave_Dug_Up.png"

## Still placeholders -- no official art for these two yet. The stone deposit
## reuses the Kenney materials icon and wild game reuses the generated deer
## (see tools/make_deer_sprite.gd), same as before this pass.
const SPRITE_STONE := "res://assets/placeholder/kenney/materials_005_stone.png"
const SPRITE_CARCASS := "res://assets/placeholder/kenney/icon_bones_kenney.png"
const SPRITE_DEER := "res://assets/placeholder/generated/creature_deer.png"

var nodes: Array = []  # Array[ResourceNode]

## **On-screen CONTENT height per node type**, in world pixels, against a 64px
## tile. Width is whatever the art's own aspect ratio makes it, which is the
## point: the stone deposit is a wide flat outcrop and comes out ~82px across
## from a 45px height target, and that is correct.
##
##   tree     96 = 1.50 tiles   pines should tower over units
##   stump    32 = 0.50         a stump is low; it is not a short tree
##   grove    58 = 0.90
##   grave    48 = 0.75
##   stone    45 = 0.70         wide and flat -- ~82px of ground covered
##   carcass  26 = 0.40         deliberately the smallest -- it is a scrap
##   deer     58 = 0.90         and taller than the wolf, which is the read
##                              SPRITE_SPEC §5 asks the two silhouettes to carry
##
## **These were canvas widths until the content-height pass, and that is why
## they used to be meaningless.** Content fills 42%-100% of a canvas depending
## on the asset, so dividing a target by `texture.get_size().x` produced a
## different real size for every sprite: the tree asked for 76 and drew 46px of
## actual tree, while the grave asked for 50 and drew 50. The old numbers
## (76/66/88/50/40/54) were describing the picture, not the thing. See
## `Anchoring.scale_for_content_height`.
##
## They live here rather than at the call sites so the whole scale of the map is
## one block you can read and retune. `ResourceNode.hit_radius()` derives from
## the drawn content, so click targets grow with the art.
const NODE_SIZE_TREE: float = 96.0
const NODE_SIZE_STUMP: float = 32.0
const NODE_SIZE_GROVE: float = 58.0
const NODE_SIZE_STONE: float = 45.0
const NODE_SIZE_GRAVE: float = 48.0
const NODE_SIZE_CARCASS: float = 26.0
const NODE_SIZE_DEER: float = 58.0

var _deer_roam_rect: Rect2
var _grid_w: float = 0.0
var _grid_h: float = 0.0

## The world this field seeds into. Set by Main before build(). Only the deer
## use it (to amble around blocking terrain); the fixed nodes are all inside the
## guaranteed-walkable lair band, so nothing else needs to ask.
##
## **This is the lair-band seeder now** (rework §12), not "the map": everything
## below is still positioned relative to the settlement grid, which is exactly
## what keeps the forest, deposit, grove and graves where they have always been
## relative to the Throne now that the Throne sits inside a 144x144 world.
var world: WorldMap = null

func _ready() -> void:
	EventBus.dawn_started.connect(_on_dawn)

## Seeds the whole map. `grid_w`/`grid_h` are the settlement grid's pixel
## dimensions -- everything is placed relative to those so the map still makes
## sense if the grid is ever resized.
func build(grid_w: float, grid_h: float) -> void:
	_grid_w = grid_w
	_grid_h = grid_h
	var cell: float = float(SettlementGrid.CELL_SIZE)

	# Deer roam "near the map edges" -- a band wrapping well outside the grid.
	_deer_roam_rect = Rect2(
		Vector2(-cell * 3.0, -cell * 3.0),
		Vector2(grid_w + cell * 6.0, grid_h + cell * 6.0)
	)

	_build_forest(Vector2(grid_w + cell * 2.2, grid_h * 0.35), cell)
	_build_stone_deposit(Vector2(grid_w * 0.5, grid_h + cell * 2.0))
	_build_berry_grove(Vector2(-cell * 2.4, grid_h * 0.55))
	_build_graves(cell)
	for i in range(DEER_STARTING_COUNT):
		_spawn_deer()

## The Forest is a *cluster* of individual Tree nodes, not one "forest" node --
## that's what lets it visibly thin as it's cut (FOUNDATION_SPEC section 5).
## The 4 animal carcasses are scattered among the trees, so a Bones trip and a
## Wood trip go to the same corner of the map.
func _build_forest(center: Vector2, cell: float) -> void:
	var spread := cell * 2.6
	for i in range(FOREST_TREE_COUNT):
		var pos := center + Vector2(randf_range(-spread, spread), randf_range(-spread, spread))
		var tree := ResourceNode.make_tree(pos)
		_add(tree, SPRITE_TREE, SPRITE_STUMP, NODE_SIZE_TREE, NODE_SIZE_STUMP)
	for i in range(FOREST_CARCASS_COUNT):
		var pos := center + Vector2(randf_range(-spread, spread), randf_range(-spread, spread))
		var carcass := ResourceNode.make_carcass(pos)
		_add(carcass, SPRITE_CARCASS, "", NODE_SIZE_CARCASS)

func _build_stone_deposit(pos: Vector2) -> void:
	_add(ResourceNode.make_stone_deposit(pos), SPRITE_STONE, "", NODE_SIZE_STONE)

func _build_berry_grove(pos: Vector2) -> void:
	_add(ResourceNode.make_berry_grove(pos), SPRITE_BERRY, SPRITE_BERRY_PICKED, NODE_SIZE_GROVE)

## "One by the road, one at the forest's far edge" -- the road-side grave sits
## north of the settlement (the approach side), the other past the forest to
## the east. Graves are richer than carcasses but there are only two of them,
## which is the point: bones run out.
func _build_graves(cell: float) -> void:
	var road_grave := Vector2(_grid_w * 0.25, -cell * 2.2)
	var forest_grave := Vector2(_grid_w + cell * 5.4, _grid_h * 0.35 - cell * 2.0)
	for pos in [road_grave, forest_grave]:
		_add(ResourceNode.make_grave(pos), SPRITE_GRAVE, SPRITE_GRAVE_SPENT, NODE_SIZE_GRAVE)

func _spawn_deer() -> void:
	var pos := Vector2(
		randf_range(_deer_roam_rect.position.x, _deer_roam_rect.position.x + _deer_roam_rect.size.x),
		randf_range(_deer_roam_rect.position.y, _deer_roam_rect.position.y + _deer_roam_rect.size.y)
	)
	var deer := ResourceNode.make_deer(pos, _deer_roam_rect)
	deer.world = world
	_add(deer, SPRITE_DEER, "", NODE_SIZE_DEER)

## `depleted_height` is only passed where the spent state is a different-sized
## object -- the pine, whose 1.5-tile trunk leaves a 0.5-tile stump. A picked
## grove and a robbed grave stay the size they were.
func _add(
	node: ResourceNode,
	alive_sprite: String,
	depleted_sprite: String,
	height: float,
	depleted_height: float = -1.0,
) -> void:
	add_child(node)
	node.setup_sprites(alive_sprite, depleted_sprite, height, depleted_height)
	nodes.append(node)

## Public version of _add, for nodes that appear during play rather than at
## seeding -- currently just the carcass a killed wolf leaves behind. Goes
## through here rather than letting the caller touch `nodes` directly, so the
## "nothing reaches into ResourceField.nodes" rule holds for creation too.
func add_node(
	node: ResourceNode,
	alive_sprite: String,
	depleted_sprite: String,
	height: float,
	depleted_height: float = -1.0,
) -> void:
	_add(node, alive_sprite, depleted_sprite, height, depleted_height)

# ---------------- Dawn upkeep ----------------

## Berry groves regrow; a new deer wanders in up to the cap. Both are
## FOUNDATION_SPEC section 5. Nothing else renews -- trees, stone, carcasses
## and graves are finite by design.
## Takes the day number even though it doesn't use it -- EventBus.dawn_started
## carries one, and a zero-arg handler silently fails at emit time in Godot 4
## rather than at connect time (this bit once already: regrowth quietly did
## nothing while the clock looked fine).
func _on_dawn(_day_number: int) -> void:
	for n in nodes:
		n.regrow()
	_purge_dead_deer()
	if live_deer_count() < DEER_CAP:
		_spawn_deer()

## Hunted deer are removed from the map outright, unlike stumps and spent
## graves which stay as visible evidence of what's been used up. Two reasons:
## a killed deer has no empty-state art to leave behind (it just goes
## invisible), and a new one wanders in every dawn -- so without this, `nodes`
## would grow by one dead entry per day forever and slow every find_best_node()
## scan down with it.
func _purge_dead_deer() -> void:
	for n in nodes.duplicate():
		if n.node_type == "deer" and n.is_depleted():
			nodes.erase(n)
			n.queue_free()

func live_deer_count() -> int:
	var count := 0
	for n in nodes:
		if n.node_type == "deer" and not n.is_depleted():
			count += 1
	return count

# ---------------- Queries (what WorkerSystem asks) ----------------

func nodes_of_kind(kind: String) -> Array:
	return nodes.filter(func(n): return n.kind == kind and not n.is_depleted())

## True if there's anything of this kind left to harvest anywhere on the map.
## The priority list uses this to skip a resource whose nodes are all gone
## rather than parking a worker on an unreachable job.
func has_available(kind: String) -> bool:
	for n in nodes:
		if n.kind == kind and not n.is_depleted():
			return true
	return false

## Click picking: the closest node whose own hit radius contains `world_pos`,
## or null. Depleted nodes are deliberately still hittable -- a stump and a
## dug-up grave are exactly the things a player clicks to ask "is this
## finished?", and answering that is half the point of the inspection panel.
##
## Lives here rather than in Main so the "nothing reaches into `nodes`
## directly" rule holds for input too.
func node_at(world_pos: Vector2) -> ResourceNode:
	var best: ResourceNode = null
	var best_dist: float = INF
	for n in nodes:
		var d: float = n.position.distance_to(world_pos)
		if d <= n.hit_radius() and d < best_dist:
			best_dist = d
			best = n
	return best

## Nearest non-depleted node of `kind`, biased away from nodes other workers
## are already claiming (see ResourceNode.claims / CROWDING_PENALTY_PX).
##
## This is also where Food routing resolves: berry groves and deer are both
## kind "food", so "berries or deer, whichever is nearest-available" is not a
## special case here -- it's just this function running over a mixed set. A
## skeleton with Foraging 2 will happily hunt; it's simply slow at it.
func find_best_node(kind: String, from_pos: Vector2) -> ResourceNode:
	var best: ResourceNode = null
	var best_score: float = INF
	for n in nodes:
		if n.kind != kind or n.is_depleted():
			continue
		var score: float = from_pos.distance_to(n.position) + n.claims * CROWDING_PENALTY_PX
		if score < best_score:
			best_score = score
			best = n
	return best

## Debug/QA helper -- a one-line census of what's left on the map. Used by the
## HUD's map-stock readout and by smoke tests.
func stock_summary() -> String:
	var totals := {"wood": 0, "stone": 0, "food": 0, "bones": 0}
	var live_trees := 0
	for n in nodes:
		totals[n.kind] = totals.get(n.kind, 0) + n.remaining
		if n.node_type == "tree" and not n.is_depleted():
			live_trees += 1
	return "Map: %d trees, %d wood, %d stone, %d food, %d bones, %d deer" % [
		live_trees, totals["wood"], totals["stone"], totals["food"], totals["bones"], live_deer_count()
	]
