class_name TokenLayer
extends Node

## The on-screen presence of Workers and Followers: the two y-sorted Node2D
## layers they're drawn into, the token-per-unit reconcile, and the proximity
## hit-test the inspect path picks with.
##
## Extracted from Main.gd (CLEANUP_PLAN.md Pass 4). Tokens are pure views --
## sim state lives on the Worker/Follower data objects (see Laborer.gd), and
## nothing here owns a timer or a piece of gameplay state. This module keeps the
## Dictionary that maps each data object to its token, which is also why the
## hit-test lives here: the keys *are* the simulation objects.
##
## It does not decide anything. Main.gd still arbitrates input and owns the
## inspect path; this module only answers "which unit is under this point".

## Maps a Follower.species string to its portrait. Followers are RefCounted
## data objects (see Follower.gd header for why); FollowerToken is the actual
## on-screen stand-in spawned per follower, and this roster row in the HUD is
## a second, smaller use of the same portraits.
##
## **Legacy fallback only.** Token art is now data-driven: every race carries a
## `sprite` in races.json (see RaceCatalog.sprite), pointing at the
## commissioned art in `assets/official/`. This Dictionary survives for the
## handful of *species* that were never races -- Ghoul and Wraith exist only in
## the superseded followers.json templates and have no races.json row, so a
## follower built through that path would otherwise have no art at all.
## Skeleton/Orc/Goblin are here for the same historical reason and are
## shadowed in practice by the races.json entries.
##
## Don't add to this. Add a `sprite` to races.json instead.
const SPECIES_SPRITES := {
	"Skeleton": "res://assets/placeholder/modular/character_024.png",
	"Ghoul": "res://assets/placeholder/modular/character_036.png",
	"Wraith": "res://assets/placeholder/modular/character_020.png",
	"Orc": "res://assets/placeholder/modular/character_023.png",
	"Goblin": "res://assets/placeholder/modular/character_022.png",
}

## Last-resort portrait if a follower has neither a races.json sprite nor a
## SPECIES_SPRITES entry. Reaching this means a data gap, not a normal path.
const FALLBACK_SPECIES_SPRITE := "res://assets/placeholder/modular/character_001.png"

# ---------------- Follower tokens (see FollowerToken.gd) ----------------
var followers_layer: Node2D
var follower_tokens: Dictionary = {}  # Follower -> FollowerToken
var followers_idle_zone: Rect2
var followers_gate_point: Vector2

# ---------------- Worker tokens (see WorkerToken.gd) ----------------
var workers_layer: Node2D
var worker_tokens: Dictionary = {}  # Worker -> WorkerToken

# ---------------- References handed in by Main.gd ----------------
var _worker_system: WorkerSystem

## Builds the two draw layers as children of `settlement` so they share the
## coordinate space the units walk in. Called from _build_systems(), before the
## UI exists -- `worker_system` is handed over separately by set_worker_system()
## because it is constructed after these layers.
func build_layers(settlement: SettlementGrid, grid_w: float, grid_h: float) -> void:
	followers_layer = Node2D.new()
	followers_layer.name = "FollowersLayer"
	followers_layer.y_sort_enabled = true
	settlement.add_child(followers_layer)

	# A "town green" strip along the bottom of the grid, clear of the seeded
	# buildings up top -- where idle followers wander while not busy.
	followers_idle_zone = Rect2(
		Vector2(SettlementGrid.CELL_SIZE, grid_h - 2.5 * SettlementGrid.CELL_SIZE),
		Vector2(grid_w - 2.0 * SettlementGrid.CELL_SIZE, 2.0 * SettlementGrid.CELL_SIZE)
	)
	# Just off the west edge of the grid -- where tokens glide to/from when
	# their follower leaves on a bounty or mission.
	followers_gate_point = Vector2(-SettlementGrid.CELL_SIZE * 0.6, grid_h * 0.5)

	workers_layer = Node2D.new()
	workers_layer.name = "WorkersLayer"
	workers_layer.y_sort_enabled = true
	settlement.add_child(workers_layer)

## WorkerSystem is built after the layers, so Main.gd hands it over once it
## exists. sync_worker_tokens() is a no-op until then.
func set_worker_system(worker_system: WorkerSystem) -> void:
	_worker_system = worker_system

## The count-changed signals are pure token concerns, so they're wired here
## rather than in Main.gd. Call sites that do a token sync *alongside* other
## work stay in Main.gd and call the sync methods directly.
func connect_signals() -> void:
	EventBus.follower_count_changed.connect(func(_c): sync_follower_tokens())
	EventBus.worker_count_changed.connect(func(_c): sync_worker_tokens())

# ---------------- Follower tokens (on-screen presence) ----------------

## Reconciles follower_tokens against GameState.followers: spawns a token for
## any follower that doesn't have one yet, despawns any token whose follower
## is gone (removed, captured, etc). Called on follower_count_changed.
func sync_follower_tokens() -> void:
	for f in GameState.followers:
		if not follower_tokens.has(f):
			_spawn_token(f)
	for f in follower_tokens.keys().duplicate():
		if not GameState.followers.has(f):
			_despawn_token(f)

## Token art for a follower, preferring the data-driven races.json sprite and
## degrading through the legacy species map to a generic portrait. Three tiers
## because followers can arrive by two different paths -- the race roster
## (everything current) and the superseded followers.json templates (Ghoul,
## Wraith), which have a species but no race_id.
func _token_sprite_for(follower) -> String:
	if follower.race_id != "":
		var from_data: String = RaceCatalog.sprite(follower.race_id)
		if from_data != "":
			return from_data
	return SPECIES_SPRITES.get(follower.species, FALLBACK_SPECIES_SPRITE)

func _spawn_token(follower) -> void:
	var token := FollowerToken.new()
	followers_layer.add_child(token)
	var sprite_path: String = _token_sprite_for(follower)
	var tex: Texture2D = null
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		tex = load(sprite_path)
	token.setup(follower, tex, followers_gate_point)
	follower_tokens[follower] = token

func _despawn_token(follower) -> void:
	var token: FollowerToken = follower_tokens.get(follower)
	if token:
		token.queue_free()
	follower_tokens.erase(follower)

func send_token_away(follower) -> void:
	if follower_tokens.has(follower):
		follower_tokens[follower].send_away()

func return_token_home(follower) -> void:
	if follower_tokens.has(follower):
		follower_tokens[follower].return_home()

# ---------------- Worker tokens (on-screen presence) ----------------

## Same reconcile pattern as sync_follower_tokens() -- spawns a token for
## any Worker that doesn't have one yet, despawns any orphaned token.
func sync_worker_tokens() -> void:
	if _worker_system == null:
		return
	for w in _worker_system.workers:
		if not worker_tokens.has(w):
			_spawn_worker_token(w)
	for w in worker_tokens.keys().duplicate():
		if not _worker_system.workers.has(w):
			_despawn_worker_token(w)

func _spawn_worker_token(worker) -> void:
	var token := WorkerToken.new()
	workers_layer.add_child(token)
	# Workers now have their own commissioned art rather than borrowing a
	# Follower portrait -- Skeleton_Worker.png, via the same races.json lookup
	# every other unit uses. They still read as interchangeable by design:
	# every worker is the same skeleton, which is the point.
	var sprite_path: String = RaceCatalog.sprite(Worker.RACE_ID)
	var tex: Texture2D = null
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		tex = load(sprite_path)
	token.setup(worker, tex)
	worker_tokens[worker] = token

func _despawn_worker_token(worker) -> void:
	var token: WorkerToken = worker_tokens.get(worker)
	if token:
		token.queue_free()
	worker_tokens.erase(worker)

# ---------------- Hit-testing ----------------

## The closest Follower under `world_pos`, or null.
func follower_at(world_pos: Vector2) -> Follower:
	return closest_token_hit(follower_tokens, world_pos)

## The closest Worker under `world_pos`, or null.
func worker_at(world_pos: Vector2) -> Worker:
	return closest_token_hit(worker_tokens, world_pos)

## Shared proximity hit-test for both follower_tokens and worker_tokens --
## Laborers roam freely rather than sitting in grid cells, so this measures
## distance rather than resolving a cell. Returns the closest Worker/Follower
## within `radius`, or null.
##
## **Measures the Laborer's own `position`, not the token's.** They agree to
## within a frame in normal play, but the token is a pure view that copies it
## in `_process` -- so the token is always one frame stale, and a follower sent
## away on a bounty has a token that stopped mirroring entirely and glided off
## to the gate. Hit-testing the view would mean clicking a ghost at the gate
## and missing the real unit. The Dictionary keys *are* the simulation objects,
## so this costs nothing.
##
## Tokens that are hidden (away on a bounty/mission) are skipped: they're off
## the map, so there's nothing there to click.
##
## **The radius comes from the token, not from a number passed in here.** It
## used to be a hardcoded 20.0 for followers and 16.0 for workers, which was
## fine while they were drawn at 40 and 32 -- and became wrong the moment the
## art grew, leaving clicks landing beside a unit the player was aiming at.
## `hit_radius()` derives from the same target-size constant that scales the
## sprite, so the two can no longer drift apart.
func closest_token_hit(tokens: Dictionary, world_pos: Vector2):
	var best = null
	var best_dist := INF
	for key in tokens.keys():
		var token: Node2D = tokens[key]
		if token == null or not token.visible:
			continue
		var d: float = key.position.distance_to(world_pos)
		if d <= token.hit_radius() and d < best_dist:
			best_dist = d
			best = key
	return best
