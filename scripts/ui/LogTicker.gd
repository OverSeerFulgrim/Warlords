class_name LogTicker
extends VBoxContainer
## **The last few things that happened**, as fading lines above the action bar
## (the HUD redo, 2026-09-26). The full record is the History window (L); this
## is just enough to notice something without opening it. Each line lives
## LINE_SECONDS and then fades; at most MAX_LINES stay on screen.

const MAX_LINES := 4
const LINE_SECONDS := 9.0

func _init() -> void:
	add_theme_constant_override("separation", 2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func push(bbcode: String) -> void:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(560, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("normal_font_size", 13)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.text = bbcode
	add_child(l)
	while get_child_count() > MAX_LINES:
		var oldest := get_child(0)
		remove_child(oldest)
		oldest.queue_free()
	var tw := l.create_tween()
	tw.tween_interval(LINE_SECONDS)
	tw.tween_property(l, "modulate:a", 0.0, 1.5)
	tw.tween_callback(func():
		if is_instance_valid(l) and l.get_parent() == self:
			remove_child(l)
			l.queue_free())
