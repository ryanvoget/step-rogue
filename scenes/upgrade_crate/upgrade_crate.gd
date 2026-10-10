extends Node2D

# The reward crate that drops in once a floor is cleared. The player walks up to it, an "Open"
# prompt appears, and opening it offers three upgrades to pick one from (see world.gd's
# _show_upgrade_crate). Taking one makes the crate burst in a blue spark and unlocks the doors.
#
# Drawn rather than sprited: a hovering container with a lit seam, corner braces and a slow bob,
# so it reads as the same technology as the fusion table and the holo UI.

const T := preload("res://scenes/ui/ui_theme.gd")

const W := 42.0
const H := 34.0

var _t := 0.0
var _opening := false

func _ready() -> void:
	z_index = 4

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	if _opening:
		return
	var bob := sin(_t * 1.6) * 3.0
	var pulse := 0.6 + 0.4 * sin(_t * 2.4)
	var o := Vector2(0.0, bob)

	# Ground shadow — shrinks as the crate bobs up, which is what sells the hover.
	draw_set_transform(Vector2(0.0, H * 0.62), 0.0, Vector2(1.0, 0.34))
	draw_circle(Vector2.ZERO, W * 0.42 - bob * 0.5, Color(0, 0, 0, 0.30))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Body.
	var body := Rect2(o.x - W * 0.5, o.y - H * 0.5, W, H)
	draw_rect(body, Color(0.071, 0.102, 0.141))
	draw_rect(body, Color(T.CYAN, 0.55), false, 1.5)

	# Lit horizontal seam across the middle — the part that will split open.
	var seam_y := o.y
	T.draw_glow_line(self, Vector2(o.x - W * 0.5, seam_y), Vector2(o.x + W * 0.5, seam_y),
		T.CYAN, 1.5, 0.9 * pulse)

	# Corner braces.
	T.draw_brackets(self, body, Color(T.CYAN, 0.9), 9.0, 2.0)

	# Core light showing through the seam.
	draw_circle(o, 5.0 * pulse, Color(T.CYAN_HOT, 0.55))
	draw_circle(o, 12.0, Color(T.CYAN, 0.10 * pulse))

	# Floating glyph above it, marking it as interactive from across the room.
	var gy := o.y - H * 0.5 - 16.0 - sin(_t * 2.0) * 2.0
	T.draw_glow_arc(self, Vector2(o.x, gy), 7.0, _t * 1.5, _t * 1.5 + deg_to_rad(240.0),
		T.CYAN, 1.5, 0.8, 16)

# Blue spark burst, then free. Returns the time the effect needs so the caller can sequence
# the door unlock behind it.
func burst() -> float:
	_opening = true
	var fx := Node2D.new()
	fx.z_index = 20
	add_child(fx)
	var life := 0.45
	var elapsed := [0.0]
	fx.draw.connect(func():
		var f: float = clampf(elapsed[0] / life, 0.0, 1.0)
		var r: float = 10.0 + f * 64.0
		fx.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(T.CYAN_HOT, (1.0 - f) * 0.95), 3.0)
		fx.draw_arc(Vector2.ZERO, r * 0.65, 0.0, TAU, 32, Color(T.CYAN, (1.0 - f) * 0.7), 2.0)
		# Shards flying outward.
		for i in 10:
			var a := TAU * float(i) / 10.0
			var d := r * (0.8 + 0.3 * float(i % 3))
			fx.draw_line(Vector2(d * 0.7, 0).rotated(a), Vector2(d, 0).rotated(a),
				Color(T.CYAN_HOT, (1.0 - f) * 0.9), 2.0)
	)
	var tw := create_tween()
	tw.tween_method(func(v: float):
		elapsed[0] = v
		fx.queue_redraw()
	, 0.0, life, life)
	tw.tween_callback(queue_free)
	return life
