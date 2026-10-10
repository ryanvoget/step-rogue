extends Node2D

# The key card sitting on the table in the player's holding cell. Walking over it unlocks the
# blue door so the run can begin. Drawn rather than sprited — a small card with a magnetic stripe
# and a chip, glowing enough to be found in a dark cell without a tutorial prompt.

const T := preload("res://scenes/ui/ui_theme.gd")
const W := 22.0
const H := 14.0

var _t := 0.0

func _ready() -> void:
	z_index = 5

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var bob := sin(_t * 2.0) * 2.0
	var pulse := 0.55 + 0.45 * sin(_t * 2.6)
	var o := Vector2(0.0, bob)

	# Glow pool underneath, so it reads as the one lit thing on the table.
	draw_circle(o, 26.0, Color(T.CYAN, 0.07 * pulse))
	draw_circle(o, 15.0, Color(T.CYAN, 0.10 * pulse))

	# Card body, tilted slightly so it looks placed rather than floating square-on.
	draw_set_transform(o, 0.22, Vector2.ONE)
	var body := Rect2(-W * 0.5, -H * 0.5, W, H)
	draw_rect(body, Color(0.086, 0.137, 0.188))
	draw_rect(body, Color(T.CYAN, 0.85), false, 1.5)
	# Magnetic stripe.
	draw_rect(Rect2(-W * 0.5 + 2.0, -H * 0.5 + 2.5, W - 4.0, 2.5), Color(T.CYAN, 0.55))
	# Chip.
	draw_rect(Rect2(-W * 0.5 + 3.0, 1.0, 5.0, 4.0), Color(T.AMBER, 0.9 * pulse))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Marker above it, visible across the cell.
	var gy := o.y - 20.0 - sin(_t * 2.0) * 1.5
	T.draw_glow_arc(self, Vector2(0.0, gy), 5.0, _t * 2.0, _t * 2.0 + deg_to_rad(250.0),
		T.CYAN, 1.5, 0.8, 14)
