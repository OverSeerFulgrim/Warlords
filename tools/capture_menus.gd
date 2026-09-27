extends SceneTree
## Boots the real game and screenshots every menu the UI kit dresses: the title
## (and its controls page), the pause menu and its abandon confirm, the flee
## picker, the Lair, the items dialog and the run-end screen. Run **windowed**
## (there is no framebuffer headless):
##
##   godot --path . --resolution 1400x760 -s res://tools/capture_menus.gd -- <out_dir>
##
## Exists for the same reason as capture_settlement.gd: the menus are built in
## code, so the only way to judge an art change to them is to look. The run-end
## screen and the Lair get made-up contents (a scratch profile in user://, never
## the player's); everything else is what the game shows on launch.

const SETTLE_FRAMES := 60
const STEP_FRAMES := 12

var _out: String = "user://menus"
var _frames: int = 0
var _step: int = 0
var _wait: int = SETTLE_FRAMES
var _main: Node = null

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	seed(20260927)
	change_scene_to_file("res://scenes/Main.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < _wait:
		return false
	_main = current_scene
	if _main == null:
		return false
	if _step > 0:
		_shoot(STEPS[_step - 1])
	if _step >= STEPS.size():
		print("capture_menus: done -> %s" % _out)
		return true
	call(STEPS[_step])
	_step += 1
	_wait = _frames + STEP_FRAMES
	return false

const STEPS: Array[String] = ["title", "title_controls", "pause", "pause_confirm", "flee_pick",
	"lair", "items", "run_end"]

func _shoot(name: String) -> void:
	var img: Image = root.get_texture().get_image()
	if img == null:
		printerr("capture_menus: no framebuffer -- did this run with --headless?")
		return
	var path: String = "%s/%s.png" % [_out, name]
	print("capture_menus: %s (err %d)" % [path, img.save_png(path)])

func _hide_all() -> void:
	for n in ["title_screen", "pause_menu", "keep_dialog", "lair_screen", "items_dialog", "run_summary"]:
		var m = _main.get(n)
		if m is CanvasLayer:
			if m.has_method("close"):
				m.close()
			m.visible = false
	paused = true

func title() -> void:
	_main.title_screen.show_title({"level": 3, "xp": 420, "runs": 4,
		"last_epitaph": "Run 4 — slain on day 3 by a guard of Harrowdale, eleven dead raised, one den cleared."})

func title_controls() -> void:
	_main.title_screen._show_controls()

func pause() -> void:
	_hide_all()
	paused = false
	_main.pause_menu.open()

func pause_confirm() -> void:
	_main.pause_menu._show_confirm()

func flee_pick() -> void:
	_hide_all()
	paused = false
	_main.keep_dialog.open(["tarnished_locket", "grave_coins", "sextons_ring", "wolfhide_cloak", "noble_seal"])

func lair() -> void:
	_hide_all()
	var p := MetaProfile.open("user://capture_menus_profile.json")
	if p.stash.is_empty():
		for id in ["tarnished_locket", "noble_seal", "wolfhide_cloak", "sextons_ring"]:
			p.add_to_stash(id, 2, 4)
		p.set_shelf(int(p.stash[0]["uid"]), 0)
		p.set_shelf(int(p.stash[1]["uid"]), 2)
		p.set_carry("necromancer", int(p.stash[2]["uid"]), true)
	_main.lair_screen.show_lair(p, "necromancer")

func items() -> void:
	_hide_all()
	paused = false
	_main.items_dialog.open()

func run_end() -> void:
	_hide_all()
	_main.run_summary.show_summary({
		"ending": "slain", "title": "Slain on the road",
		"epitaph": "Run 5 — slain on day 3 by a guard of Harrowdale, with eleven dead behind him.",
		"day": 3, "run_seconds": 1234.0,
		"stats": {"skeletons_raised": 11, "raised_at_graves": 3, "sites_looted": 6, "wolves_killed": 4,
			"banked_units": 23, "relics_banked": 1, "max_escort": 5, "buildings_placed": 2,
			"deeds": {"rob_the_dead": 3, "cleared_a_den": 1}},
		"level": 3, "progress": [140, 300], "xp_run": 185, "xp_total": 440,
		"next_unlock": {"name": "Second Wake", "level": 5, "description": "Once per run, he wakes at the Throne instead of dying."},
		"lost": ["wolfhide_cloak"],
		"chronicle": [{"epitaph": "Run 4 — slain at the den."}, {"epitaph": "Run 5 — slain on the road."}],
		"persistent": false,
	})
