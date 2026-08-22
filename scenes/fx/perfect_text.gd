extends Node2D

# Floating "Perfect!" that drifts up and fades — spawned above the player on a perfect dash. Lives
# in the world (not parented to the player) so it animates independently.

const DUR := 0.7
var _t := 0.0

func _ready() -> void:
	z_index = 100
	var lbl := Label.new()
	lbl.text = "Perfect!"
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.position = Vector2(-40, -10)
	lbl.size = Vector2(80, 20)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(lbl)

func _process(delta: float) -> void:
	_t += delta
	if _t >= DUR:
		queue_free()
		return
	position.y -= 26.0 * delta
	modulate.a = 1.0 - (_t / DUR)
