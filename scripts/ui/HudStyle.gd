class_name HudStyle
extends RefCounted
## **The HUD's look, in one place** (the HUD redo, 2026-09-26 -- mockups in the
## "Warlords HUD redo" canvas). Dark violet panels with a thin border, bone text,
## a violet accent for the villain's own things, amber for "not home yet", red
## for danger. Every HUD piece reads its colours and boxes from here so a later
## art pass changes one file.

const BG := Color("17131d")
const BG_RAISED := Color("211c28")
const BG_ACCENT := Color("2b2438")
const BORDER := Color("3b3247")
const BORDER_ACCENT := Color("8c74c9")
const TEXT := Color("ece4d4")
const MUTED := Color("b4a9c4")
const ACCENT := Color("c9b3ff")
const AMBER := Color("e8d6a6")
const AMBER_BORDER := Color("5c4a2a")
const DANGER := Color("d8604f")
const GOOD := Color("8fbf7a")
const HP_BACK := Color("3a2230")
const HP_FILL := Color("c9493b")

static func box(bg: Color = BG, border: Color = BORDER, radius: int = 8, pad: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.8
	s.content_margin_bottom = pad * 0.8
	return s

static func panel(border: Color = BORDER) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(BG, border))
	return p

## A HUD button: `accent` for the villain's own actions, plain otherwise.
static func style_button(b: Button, accent: bool = false, font_size: int = 14) -> void:
	var normal := box(BG_ACCENT if accent else BG, BORDER_ACCENT if accent else BORDER, 8, 8)
	var hover := box(Color("342b44") if accent else BG_RAISED, ACCENT if accent else BORDER_ACCENT, 8, 8)
	var disabled := box(Color("15121a"), BORDER, 8, 8)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color("7d738a"))
	b.add_theme_font_size_override("font_size", font_size)

## A small rounded chip (stance, bag, guild standing).
static func style_chip(b: Button, border: Color = BORDER, bg: Color = BG_RAISED, fg: Color = MUTED) -> void:
	var s := box(bg, border, 10, 4)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	for k in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(k, s)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_font_size_override("font_size", 12)

static func label(text: String = "", size: int = 13, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

## A thin hp bar: a background rect with a fill child. `set_bar()` updates it.
static func bar(width: float, height: float = 8.0) -> ColorRect:
	var back := ColorRect.new()
	back.color = HP_BACK
	back.custom_minimum_size = Vector2(width, height)
	var fill := ColorRect.new()
	fill.name = "Fill"
	fill.color = HP_FILL
	fill.size = Vector2(width, height)
	back.add_child(fill)
	return back

static func set_bar(back: ColorRect, fraction: float, color: Color = HP_FILL) -> void:
	var fill: ColorRect = back.get_node_or_null("Fill")
	if fill == null:
		return
	var w: float = maxf(back.size.x, back.custom_minimum_size.x)
	fill.size = Vector2(w * clampf(fraction, 0.0, 1.0), maxf(back.size.y, back.custom_minimum_size.y))
	fill.color = color

## Green when whole, amber when hurt, red when in trouble -- the colours the
## roster and the overhead bars share.
static func hp_color(fraction: float) -> Color:
	if fraction >= 0.999:
		return GOOD
	if fraction < 0.4:
		return DANGER
	return Color("e0a050")
