extends Node2D
class_name RaisedDead

## Something the Necromancer pulled out of a grave, standing where it came up.
##
## ## Why it exists at all
##
## `LOOT_SITES_SPEC.md` §4 says a raised corpse is "+1 escort-eligible skeleton
## at the site, dormant until escort lands, then retroactively live". R2a
## implemented that literally -- an entry appended to `Necromancer.raised_dead`
## and nothing else -- which is per spec and completely **illegible**: the
## playtest raised a corpse and the world showed nothing at all. The player has
## to *see* the necromancy; the dormancy is about what it can be ordered to do,
## not about whether it is there.
##
## ## A pure view, and the data is the ledger entry
##
## CLAUDE.md's rule: sim state lives on data objects, tokens only draw. The data
## here is the villain's `raised_dead` entry -- a Dictionary with the position
## it came up at and its dormant flag -- and this node reads it. Nothing is
## stored twice, and R2d can bind these into the escort by walking that Array
## without having to reconcile it against a second list.
##
## ## What it is not
##
## **Not a `Worker` and not in any labour pool.** Handing it to `WorkerSystem`
## would put it on the gathering rota, and it would walk off to chop wood --
## which is neither what §4 promises nor what the player just watched happen. It
## stands at the graveside until R2d gives it somewhere to be.
##
## **Not a `SiteGuardian`.** It is not hostile, it guards nothing, and it must
## never end up in `CombatSystem`'s target lists. It is scenery with a ledger
## entry behind it, and it is the first thing on this map that is.

## The skeleton it wears. Its own race row's art, so a raised corpse and a bound
## worker are visibly the same dead thing -- which they are.
const RACE_ID := "skeleton_worker"
const SPRITE_PATH := "res://assets/official/characters/Skeleton_Worker.png"
## Same content height as `WorkerToken.SPRITE_TARGET_SIZE`, from the constant
## rather than a literal: a raised skeleton standing beside a bound one must not
## be a different size.
const TOKEN_SIZE: float = WorkerToken.SPRITE_TARGET_SIZE

## The villain who raised it. A **reference handed in**, never looked up --
## ROGUELITE_REWORK §11, and the reason a second villain's dead are his own.
var villain = null
## The entry in `villain.raised_dead` this node draws. The Dictionary itself,
## not a copy, so a flag flipped there is read here on the next frame.
var entry: Dictionary = {}
## Where it came up, for the inspection payload.
var from_site_name: String = ""

var _sprite: Sprite2D

func setup(p_villain, p_entry: Dictionary, at: Vector2, site_name: String) -> void:
	villain = p_villain
	entry = p_entry
	from_site_name = site_name
	position = at

func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.centered = true
	if ResourceLoader.exists(SPRITE_PATH):
		var tex: Texture2D = load(SPRITE_PATH)
		_sprite.texture = tex
		_sprite.scale = Vector2.ONE * Anchoring.scale_for_content_height(tex, TOKEN_SIZE)
		Anchoring.foot(_sprite)
	else:
		push_warning("RaisedDead: sprite not found at %s" % SPRITE_PATH)
	add_child(_sprite)
	# Workers are z 0 and this stands among them; it takes the same layer so
	# y-sorting puts it correctly in front of and behind what it is standing by.
	z_index = 0

func is_dormant() -> bool:
	return bool(entry.get("dormant", true))

# ---------------- Inspection (see InspectionPanel.gd) -------------------------

func hit_radius() -> float:
	if _sprite == null:
		return TOKEN_SIZE * Anchoring.HIT_RADIUS_FRACTION
	var drawn: Vector2 = Anchoring.drawn_content_size(_sprite)
	return maxf(drawn.x, drawn.y) * Anchoring.HIT_RADIUS_FRACTION

func get_inspect_data() -> Dictionary:
	var rows: Array = [
		{"label": "Activity", "value": "Standing where it came up"},
		{"label": "Raised at", "value": from_site_name},
	]
	if is_dormant():
		rows.append({"label": "Orders", "value": "None — nothing to follow yet", "muted": true})
		rows.append({"label": "", "value": "It waits. When you can lead an escort, it walks with you (LOOT_SITES_SPEC §4).", "muted": true})
	return {
		"title": "A Raised Corpse",
		"subtitle": "Undead — yours",
		"sprite": SPRITE_PATH,
		"description": "It climbed out of its own grave and has not moved since. Whatever it was, it is yours now.",
		"details": rows,
	}
