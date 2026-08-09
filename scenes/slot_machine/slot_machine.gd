extends Node2D

# A cantina slot machine (bar rooms only): a low-detail drawn placeholder (a PNG can replace it
# later). world.gd spawns one off to the side of the bar and opens the artifact-spin dialog when the
# player walks up to it (see world.gd's _physics_process / _show_slots).

const BODY_COLOR   := Color(0.55, 0.12, 0.16)
const SCREEN_COLOR := Color(0.10, 0.10, 0.16)
const REEL_COLOR   := Color(0.85, 0.80, 0.35)
const TRIM_COLOR   := Color(0.90, 0.75, 0.20)

func _ready() -> void:
	queue_redraw()
	# Floating "SLOTS" tag above the machine.
	var lbl := Label.new()
	lbl.text = "🎰 SLOTS"
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size = Vector2(80, 20)
	lbl.position = Vector2(-40, -54)
	add_child(lbl)

func _draw() -> void:
	# Cabinet (origin = machine centre).
	draw_rect(Rect2(-22, -34, 44, 64), BODY_COLOR)
	draw_rect(Rect2(-22, -34, 44, 64), TRIM_COLOR, false, 2.0)
	# Screen with three little reels.
	draw_rect(Rect2(-17, -26, 34, 20), SCREEN_COLOR)
	for i in range(3):
		draw_rect(Rect2(-15 + i * 11, -24, 8, 16), REEL_COLOR)
	# Lever knob on the side.
	draw_circle(Vector2(26, -18), 4.0, TRIM_COLOR)
