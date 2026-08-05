extends SceneTree
## Prints the alpha bounding box of every sprite the game scales, as a fraction
## of its canvas. Run:
##
##   godot --headless --path . -s res://tools/measure_sprite_content.gd
##
## This is the measurement behind the content-height scaling rule: a sprite's
## canvas says nothing about how big the thing drawn on it is, and these numbers
## are how far apart the two are for the art actually in the repo.

const PATHS := [
	"res://Official Sprites/Pine_Tree.png",
	"res://Official Sprites/Pine_Stump.png",
	"res://Official Sprites/Berry_Grove_Full.png",
	"res://Official Sprites/Berry_Grove_Picked.png",
	"res://Official Sprites/Grave_Undisturbed.png",
	"res://Official Sprites/Grave_Dug_Up.png",
	"res://Icons/Materials/materials_005_stone.png",
	"res://art/icon_bones_kenney.png",
	"res://art/creature_deer.png",
	"res://art/creature_wolf.png",
	"res://Official Sprites/Skeleton_Worker.png",
	"res://Official Sprites/Necromancer_Full_Body.png",
	"res://Official Sprites/Throne_of_Bones.png",
	"res://Official Sprites/Barracks.png",
	"res://Official Sprites/Bone_Pile.png",
	"res://Official Sprites/Dark_Altar.png",
	"res://Buildings/House/house_1_blue.png",
	"res://Buildings/House/house_2_green.png",
	"res://Buildings/Tower/tower_red.png",
	"res://art/building_crypt_kenney.png",
]

## `_initialize()`, not `_init()`: the other SceneTree tools in this folder only
## touch the Image API, but this one calls `load()`, and ResourceLoader is not
## up yet while the main loop is still being constructed -- doing it in `_init`
## hangs headless Godot rather than failing.
func _initialize() -> void:
	print("path,canvas_w,canvas_h,content_x,content_y,content_w,content_h,fill_w,fill_h")
	var extra: Array = PATHS.duplicate()
	# Every race token, so the character families can be checked in one pass.
	var races: Dictionary = _load_json("res://data/races.json")
	for id: String in races.keys():
		# races.json carries a top-level "_comment" String alongside the rows.
		if not (races[id] is Dictionary):
			continue
		var s: String = str((races[id] as Dictionary).get("sprite", ""))
		if s != "" and not extra.has(s):
			extra.append(s)
	for p: String in extra:
		if not ResourceLoader.exists(p):
			print("%s,MISSING" % p)
			continue
		var tex: Texture2D = load(p)
		var img: Image = tex.get_image()
		if img == null:
			print("%s,NO_IMAGE" % p)
			continue
		if img.is_compressed():
			img.decompress()
		var r: Rect2i = img.get_used_rect()
		var cw: float = float(img.get_width())
		var ch: float = float(img.get_height())
		print("%s,%d,%d,%d,%d,%d,%d,%.3f,%.3f" % [
			p, img.get_width(), img.get_height(),
			r.position.x, r.position.y, r.size.x, r.size.y,
			float(r.size.x) / maxf(1.0, cw), float(r.size.y) / maxf(1.0, ch),
		])
	quit()

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var txt: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(txt)
	return parsed if parsed is Dictionary else {}
