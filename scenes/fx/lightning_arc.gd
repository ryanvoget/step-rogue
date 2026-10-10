extends Node2D

# The visible arc for chain lightning (Photon Spear, Electro Blaster, the Electric Boost). Before
# this existed the chain dealt its damage silently, so a player had no way to tell an arc had
# fired at all. Drawn in global space between two points as a jagged polyline that re-randomises a
# few times over its short life, then fades out.

const DURATION    := 0.22   # total lifetime
const RESHAPE     := 0.05   # seconds between re-randomising the zigzag
const SEGMENTS    := 7      # kinks along the arc
const JAG         := 9.0    # max perpendicular deviation, px
const COLOR       := Color(0.45, 0.80, 1.0)
const CORE_COLOR  := Color(0.92, 0.99, 1.0)

var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _life := DURATION
var _reshape_in := 0.0
var _points := PackedVector2Array()

func setup(from: Vector2, to: Vector2) -> void:
	_from = from
	_to = to
	_rebuild()

func _rebuild() -> void:
	# Points are local: the node sits at _from, so the arc travels to (_to - _from).
	var span := _to - _from
	var perp := Vector2(-span.y, span.x).normalized()
	_points = PackedVector2Array()
	for i in range(SEGMENTS + 1):
		var t := float(i) / float(SEGMENTS)
		# Deviation tapers to zero at both ends so the arc stays anchored to its two enemies.
		var taper := sin(t * PI)
		_points.append(span * t + perp * randf_range(-JAG, JAG) * taper)
	_reshape_in = RESHAPE

func _ready() -> void:
	global_position = _from
	z_index = 5

func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	_reshape_in -= delta
	if _reshape_in <= 0.0:
		_rebuild()
	queue_redraw()

func _draw() -> void:
	if _points.size() < 2:
		return
	var a := clampf(_life / DURATION, 0.0, 1.0)
	for i in range(_points.size() - 1):
		draw_line(_points[i], _points[i + 1], Color(COLOR, 0.35 * a), 7.0)      # bloom
		draw_line(_points[i], _points[i + 1], Color(COLOR, 0.75 * a), 3.5)      # body
		draw_line(_points[i], _points[i + 1], Color(CORE_COLOR, 0.95 * a), 1.5) # core
	draw_circle(_points[0], 5.0 * a, Color(CORE_COLOR, 0.8 * a))
	draw_circle(_points[_points.size() - 1], 6.0 * a, Color(CORE_COLOR, 0.9 * a))
