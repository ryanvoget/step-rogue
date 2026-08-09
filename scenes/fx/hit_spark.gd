extends Node2D

# A short-lived impact spark burst, spawned at the point a melee hit connects. Lives in the world
# (not parented to the player), so it animates/fades on its own and is never cut short if the
# player's swing is cancelled or another attack starts.

const DUR := 0.16
var _t := 0.0
var _color := Color(1.0, 0.95, 0.6)
var _dirs: Array = []

func setup(color: Color) -> void:
	_color = color

func _ready() -> void:
	z_index = 60
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for _i in range(7):
		_dirs.append(Vector2.RIGHT.rotated(randf() * TAU) * randf_range(12.0, 26.0))

func _process(delta: float) -> void:
	_t += delta
	if _t >= DUR:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var p := clampf(_t / DUR, 0.0, 1.0)
	var a := 1.0 - p
	for d in _dirs:
		var from: Vector2 = d * (0.25 + 0.55 * p)
		var to: Vector2 = d * (0.55 + 1.0 * p)
		draw_line(from, to, Color(_color, a), 2.5)
	draw_circle(Vector2.ZERO, 5.0 * (1.0 - p), Color(1, 1, 1, a * 0.85))
