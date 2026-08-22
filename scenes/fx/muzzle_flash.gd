extends Node2D

# Brief muzzle flash at the barrel the instant a laser weapon fires — the "energy release": a
# blinding white/cyan core inside a soft coloured bloom, with a few forward spark streaks. Lives in
# the world (bullets container) so it fades on its own, oriented along the shot (rotation set by the
# spawner). Mirrors hit_spark.gd's lightweight draw-and-fade pattern.

const DUR := 0.09
var _t := 0.0
var _color := Color(1.0, 0.35, 0.2) # bloom tint (weapon energy colour)
var _scale := 1.0
var _streaks: Array = []

func setup(color: Color, scale: float = 1.0) -> void:
	_color = color
	_scale = scale

func _ready() -> void:
	z_index = 55
	for _i in range(4):
		_streaks.append(Vector2.RIGHT.rotated(randf_range(-0.45, 0.45)) * randf_range(16.0, 30.0) * _scale)

func _process(delta: float) -> void:
	_t += delta
	if _t >= DUR:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var p := clampf(_t / DUR, 0.0, 1.0)
	var a := 1.0 - p
	var g := 1.0 - p * 0.7 # shrinks slightly as it fades — a collapsing point light
	# Soft coloured bloom.
	draw_circle(Vector2.ZERO, 22.0 * _scale * g, Color(_color, 0.22 * a))
	draw_circle(Vector2.ZERO, 13.0 * _scale * g, Color(_color, 0.50 * a))
	# Forward spark streaks (fan out along the shot direction, local +x).
	for d in _streaks:
		draw_line(Vector2.ZERO, d * (0.4 + 0.9 * p), Color(1.0, 0.9, 0.8, a * 0.8), 2.0)
	# Blinding white/cyan core.
	draw_circle(Vector2.ZERO, 8.0 * _scale * g, Color(0.85, 0.98, 1.0, a))
	draw_circle(Vector2.ZERO, 4.0 * _scale * g, Color(1, 1, 1, a))
