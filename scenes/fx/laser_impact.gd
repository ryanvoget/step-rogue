extends Node2D

# Energy-impact burst where a player laser lands — "the energy transferring": an expanding
# shockwave ring, a white core flash, and radial spark shards, all fading fast. Scaled up for
# heavier shots. Lives in the world so it animates independently of the (freed) bullet.

const DUR := 0.18
var _t := 0.0
var _color := Color(1.0, 0.35, 0.2)
var _scale := 1.0
var _shards: Array = []

func setup(color: Color, scale: float = 1.0) -> void:
	_color = color
	_scale = scale

func _ready() -> void:
	z_index = 60
	for _i in range(9):
		_shards.append(Vector2.RIGHT.rotated(randf() * TAU) * randf_range(16.0, 34.0) * _scale)

func _process(delta: float) -> void:
	_t += delta
	if _t >= DUR:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var p := clampf(_t / DUR, 0.0, 1.0)
	var a := 1.0 - p
	# Expanding shockwave ring (thins as it grows).
	var r := lerpf(4.0, 40.0 * _scale, p)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 28, Color(_color, a * 0.8), maxf(3.0 * (1.0 - p), 0.5))
	# Radial spark shards flung outward from the point of contact.
	for d in _shards:
		var from: Vector2 = d * (0.2 + 0.5 * p)
		var to: Vector2 = d * (0.5 + 1.1 * p)
		draw_line(from, to, Color(1.0, 0.9, 0.8, a), maxf(2.5 * (1.0 - p * 0.5), 0.5))
	# White-hot core flash inside a coloured glow.
	draw_circle(Vector2.ZERO, 18.0 * _scale * (1.0 - p), Color(_color, a * 0.5))
	draw_circle(Vector2.ZERO, 10.0 * _scale * (1.0 - p), Color(1, 1, 1, a))
