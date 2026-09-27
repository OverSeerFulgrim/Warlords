class_name UiKit
extends RefCounted
## **The commissioned UI kit on the menus** (2026-09-27): the title frame, the
## popup frame with its crest, the bone-and-stone buttons, the divider, the bar
## and the tick boxes. The pieces are cut from the masters in
## `assets/official/_originals/UI/` by `tools/make_ui_kit.py`; the margins below
## are the numbers that script prints, so re-run it and check them together.
##
## Scope: the full-screen menus and dialogs (title, pause, run-end, the flee
## picker, the Lair, the items dialog). The floating HUD keeps `HudStyle`'s slim
## boxes -- an ornate plate does not read at 8 px bars and 12 px chips.
##
## Use: `root.theme = UiKit.menu_theme()` on a menu's root Control styles every
## Button and CheckBox under it; `UiKit.panel_style()` + `UiKit.add_crest(panel)`
## frame its panel.

const BUTTON := preload("res://assets/official/ui/UI_Button.png")
const BUTTON_HOVER := preload("res://assets/official/ui/UI_Button_Hover.png")
const BUTTON_PRESSED := preload("res://assets/official/ui/UI_Button_Pressed.png")
const BUTTON_DISABLED := preload("res://assets/official/ui/UI_Button_Disabled.png")
const PANEL := preload("res://assets/official/ui/UI_Panel.png")
const PANEL_CREST := preload("res://assets/official/ui/UI_Panel_Crest.png")
const TITLE_FRAME := preload("res://assets/official/ui/UI_Title_Frame.png")
const DIVIDER := preload("res://assets/official/ui/UI_Divider.png")
const BAR_BACK := preload("res://assets/official/ui/UI_Bar_Back.png")
const BAR_FILL := preload("res://assets/official/ui/UI_Bar_Fill.png")
const CHECK_OFF := preload("res://assets/official/ui/UI_Check_Off.png")
const CHECK_ON := preload("res://assets/official/ui/UI_Check_On.png")
const CHECK_OFF_DISABLED := preload("res://assets/official/ui/UI_Check_Off_Disabled.png")
const CHECK_ON_DISABLED := preload("res://assets/official/ui/UI_Check_On_Disabled.png")

## make_ui_kit.py: "button caps 22 / 20 px, height 40".
const BUTTON_CAP := 22
const BUTTON_HOVER_CAP := 20
## make_ui_kit.py: "panel margins: sides 52, top 38, bottom 38; inside starts
## 28 in, 28 down, 27 up".
const PANEL_SIDE := 52
const PANEL_TOP := 38
const PANEL_BOTTOM := 38
const PANEL_INSIDE := 28
## make_ui_kit.py: "crest sits -20 px from the panel's top".
const CREST_Y := -20.0
## make_ui_kit.py: "bar: caps 20 px; inside x 11..75, y 6..17 of 86x24".
const BAR_HEIGHT := 24.0
const BAR_CAP := 20
const BAR_INSET_X := 11.0
const BAR_INSET_TOP := 7.0
const BAR_INSET_BOTTOM := 7.0
## The title frame's inside, as fractions of the frame (the main-menu master is
## 1672x941; its inner edge runs ~200..1470 by ~175..790), padded a little.
const TITLE_INSIDE := Rect2(0.15, 0.21, 0.70, 0.60)

static var _theme: Theme = null

## Cached: every menu shares one Theme.
static func menu_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.set_stylebox("normal", "Button", _plate(BUTTON, BUTTON_CAP, 13, 8))
	t.set_stylebox("hover", "Button", _plate(BUTTON_HOVER, BUTTON_HOVER_CAP, 10, 8))
	t.set_stylebox("pressed", "Button", _plate(BUTTON_PRESSED, BUTTON_HOVER_CAP, 10, 8))
	t.set_stylebox("hover_pressed", "Button", _plate(BUTTON_PRESSED, BUTTON_HOVER_CAP, 10, 8))
	# Keyboard focus lights the plate the way the mouse does: the focused button
	# is the one Enter presses.
	t.set_stylebox("focus", "Button", _plate(BUTTON_HOVER, BUTTON_HOVER_CAP, 10, 8))
	t.set_stylebox("disabled", "Button", _plate(BUTTON_DISABLED, BUTTON_CAP, 13, 8))
	t.set_color("font_color", "Button", HudStyle.TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", HudStyle.ACCENT)
	t.set_color("font_hover_pressed_color", "Button", HudStyle.ACCENT)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color("7d738a"))
	t.set_font_size("font_size", "Button", 14)
	# A CheckBox inherits Button's theme items, so it must say plainly that it
	# has no plate -- only the kit's tick box.
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 2
	empty.content_margin_right = 2
	empty.content_margin_top = 2
	empty.content_margin_bottom = 2
	for k in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		t.set_stylebox(k, "CheckBox", empty)
	t.set_icon("checked", "CheckBox", CHECK_ON)
	t.set_icon("unchecked", "CheckBox", CHECK_OFF)
	t.set_icon("checked_disabled", "CheckBox", CHECK_ON_DISABLED)
	t.set_icon("unchecked_disabled", "CheckBox", CHECK_OFF_DISABLED)
	t.set_constant("h_separation", "CheckBox", 8)
	t.set_color("font_color", "CheckBox", HudStyle.TEXT)
	t.set_color("font_hover_color", "CheckBox", Color.WHITE)
	t.set_color("font_pressed_color", "CheckBox", HudStyle.TEXT)
	t.set_color("font_hover_pressed_color", "CheckBox", Color.WHITE)
	t.set_color("font_focus_color", "CheckBox", Color.WHITE)
	t.set_color("font_disabled_color", "CheckBox", Color("7d738a"))
	# Scroll bars: a slim violet grabber on a dark track, like the HUD's.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(HudStyle.BG, 0.6)
	track.set_corner_radius_all(3)
	track.content_margin_left = 4
	track.content_margin_right = 4
	var grab := StyleBoxFlat.new()
	grab.bg_color = HudStyle.BORDER_ACCENT
	grab.set_corner_radius_all(3)
	var grab_hi := grab.duplicate()
	grab_hi.bg_color = HudStyle.ACCENT
	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab_hi)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab_hi)
	var sep := StyleBoxTexture.new()
	sep.texture = DIVIDER
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", DIVIDER.get_height())
	_theme = t
	return t

static func _plate(tex: Texture2D, cap: int, top: int, bottom: int) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = tex
	s.texture_margin_left = cap
	s.texture_margin_right = cap
	s.texture_margin_top = top
	s.texture_margin_bottom = bottom
	s.content_margin_left = cap + 6
	s.content_margin_right = cap + 6
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

## The popup frame as a panel. `pad` is the breathing room inside the stone.
static func panel_style(pad: int = 14) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = PANEL
	s.texture_margin_left = PANEL_SIDE
	s.texture_margin_right = PANEL_SIDE
	s.texture_margin_top = PANEL_TOP
	s.texture_margin_bottom = PANEL_BOTTOM
	s.content_margin_left = PANEL_INSIDE + pad
	s.content_margin_right = PANEL_INSIDE + pad
	s.content_margin_top = PANEL_INSIDE + pad + 4    # clear of the crest's gem
	s.content_margin_bottom = PANEL_INSIDE + pad
	return s

## The crest over the middle of a framed panel's top edge. Drawn by the panel
## itself, so it follows the panel wherever a container puts it.
static func add_crest(panel: Control) -> void:
	panel.draw.connect(func():
		panel.draw_texture(PANEL_CREST,
			Vector2(roundf((panel.size.x - PANEL_CREST.get_width()) * 0.5), CREST_Y)))

## The kit's divider, centred, in place of a plain HSeparator.
static func divider() -> CenterContainer:
	var c := CenterContainer.new()
	var r := TextureRect.new()
	r.texture = DIVIDER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(r)
	return c

## A framed bar (the XP bar). `set_bar()` fills it.
static func bar(min_width: float) -> NinePatchRect:
	var back := NinePatchRect.new()
	back.texture = BAR_BACK
	back.patch_margin_left = BAR_CAP
	back.patch_margin_right = BAR_CAP
	back.custom_minimum_size = Vector2(min_width, BAR_HEIGHT)
	var fill := NinePatchRect.new()
	fill.name = "Fill"
	fill.texture = BAR_FILL
	fill.patch_margin_left = 3
	fill.patch_margin_right = 3
	fill.patch_margin_top = 3
	fill.patch_margin_bottom = 3
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(fill)
	back.set_meta("fraction", 0.0)
	back.resized.connect(func(): _layout_bar(back))
	return back

static func set_bar(back: NinePatchRect, fraction: float) -> void:
	back.set_meta("fraction", clampf(fraction, 0.0, 1.0))
	_layout_bar(back)

static func _layout_bar(back: NinePatchRect) -> void:
	var fill: NinePatchRect = back.get_node_or_null("Fill")
	if fill == null:
		return
	var w: float = maxf(back.size.x, back.custom_minimum_size.x) - BAR_INSET_X * 2.0
	var f: float = float(back.get_meta("fraction", 0.0))
	fill.visible = f > 0.0
	fill.position = Vector2(BAR_INSET_X, BAR_INSET_TOP)
	fill.size = Vector2(maxf(6.0, w * f), BAR_HEIGHT - BAR_INSET_TOP - BAR_INSET_BOTTOM)

## Sizes a dialog's scroll box to its content, capped so the framed panel
## always fits the window (the frame adds ~90 px and the crest ~20). Waits a
## frame so rows freed by a rebuild no longer count.
static func fit_scroll(sc: ScrollContainer, body: Control, cap: float = INF) -> void:
	if sc == null or not sc.is_inside_tree():
		return
	await sc.get_tree().process_frame
	if not is_instance_valid(sc) or not is_instance_valid(body):
		return
	var room: float = sc.get_viewport().get_visible_rect().size.y - 150.0
	sc.custom_minimum_size.y = minf(body.get_combined_minimum_size().y, minf(room, cap))
