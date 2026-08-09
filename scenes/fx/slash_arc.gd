extends Node2D

# A weapon-arc slash trail, spawned at the player on a melee swing. Lives in the world (not parented
# to the player) so it sweeps and fades independently and is never cut short. A bright leading arc
# sweeps across the swing cone, trailing a fading band behind it.

const DUR := 0.18
var _t := 0.0
var _angle := 0.0
var _half_arc := 1.0
var _range := 100.0
var _color := Color(0.75, 0.9, 1.0)

func setup(angle: float, arc_degrees: float, range_px: float, color: Color) -> void:
	_angle = angle
	_half_arc = deg_to_rad(arc_degrees / 2.0)
	_range = range_px
	_color = color

func _ready() -> void:
	z_index = 50
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _process(delta: float) -> void:
	_t += delta
	if _t >= DUR:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var p := clampf(_t / DUR, 0.0, 1.0)
	var a := (1.0 - p) * 0.9
	# The leading edge accelerates across the cone (fast-forward snap); a fixed-width band trails
	# behind it. The band width is constant (not clamped to the cone start) so the polygon always
	# spans a real arc and is never degenerate/collinear — draw_colored_polygon dislikes that.
	var lead := lerpf(-_half_arc, _half_arc, ease(p, 2.4))
	var band := deg_to_rad(45.0)
	var a0 := lead - band
	var seg := 16
	var r0 := _range * 0.5
	var r1 := _range
	var pts := PackedVector2Array()
	for i in range(seg + 1):
		var ang := _angle + lerpf(a0, lead, float(i) / float(seg))
		pts.append(Vector2(r1, 0.0).rotated(ang))
	for i in range(seg, -1, -1):
		var ang := _angle + lerpf(a0, lead, float(i) / float(seg))
		pts.append(Vector2(r0, 0.0).rotated(ang))
	draw_colored_polygon(pts, Color(_color, a * 0.45))
	# Bright leading edge line.
	draw_line(Vector2(r0, 0.0).rotated(_angle + lead), Vector2(r1, 0.0).rotated(_angle + lead), Color(1, 1, 1, a), 3.0)
