class_name HouseStyle
extends RefCounted
## Which sprite and colour wash a given race's house gets.
##
## Split out from HousePlanner (which decides *where*) because this decides
## *what it looks like* -- different concern, and this is the bit an art pass
## will delete outright once there is real per-race building art.
##
## The Kenney House pack has two shapes in four colours, which is eight
## combinations for sixteen races. So shape is assigned by rough build style
## (squat burrow vs upright lodge) and colour by race, with a tint on top to
## widen the palette. It is a placeholder in the same documented spirit as the
## generated deer sprite -- the goal is only that a goblin warren and a
## minotaur's lodge don't read as the same building.

const HOUSE_SQUAT := "res://assets/placeholder/kenney/House/house_1_%s.png"
const HOUSE_TALL := "res://assets/placeholder/kenney/House/house_2_%s.png"
const DEFAULT_SPRITE := "res://assets/placeholder/kenney/House/house_1_blue.png"

## race_id -> [shape_template, colour, tint]
const STYLES := {
	# Warriors: red/earth, upright.
	"orc":            [HOUSE_TALL,  "red",    Color(1.00, 0.85, 0.80)],
	"hobgoblin":      [HOUSE_TALL,  "red",    Color(0.95, 0.80, 0.70)],
	"ogre":           [HOUSE_SQUAT, "yellow", Color(0.85, 0.78, 0.60)],
	"troll":          [HOUSE_SQUAT, "green",  Color(0.70, 0.80, 0.65)],
	# Economy: stone-grey and workmanlike.
	"gray_dwarf":     [HOUSE_SQUAT, "blue",   Color(0.72, 0.74, 0.80)],
	"mountain_dwarf": [HOUSE_SQUAT, "blue",   Color(0.85, 0.87, 0.95)],
	"kobold":         [HOUSE_SQUAT, "yellow", Color(0.90, 0.82, 0.55)],
	"minotaur":       [HOUSE_TALL,  "yellow", Color(0.80, 0.70, 0.55)],
	# Research: cool colours.
	"gnome":          [HOUSE_TALL,  "green",  Color(0.80, 0.95, 0.85)],
	"dark_elf":       [HOUSE_TALL,  "blue",   Color(0.55, 0.50, 0.70)],
	"high_elf":       [HOUSE_TALL,  "blue",   Color(0.90, 0.95, 1.00)],
	# Foraging: green, low to the ground.
	"goblin":         [HOUSE_SQUAT, "green",  Color(0.75, 0.90, 0.60)],
	"gnoll":          [HOUSE_SQUAT, "yellow", Color(0.88, 0.80, 0.62)],
	"halfling":       [HOUSE_SQUAT, "green",  Color(0.95, 0.90, 0.70)],
	# Versatile.
	"human_outcast":  [HOUSE_TALL,  "yellow", Color(0.92, 0.90, 0.85)],
}

static func sprite_for(race_id: String) -> String:
	if not STYLES.has(race_id):
		return DEFAULT_SPRITE
	var entry: Array = STYLES[race_id]
	return (entry[0] as String) % entry[1]

static func tint_for(race_id: String) -> Color:
	if not STYLES.has(race_id):
		return Color.WHITE
	return STYLES[race_id][2]
