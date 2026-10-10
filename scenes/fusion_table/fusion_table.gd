extends Node2D

# The weapon-fusion console in the bar — a low sci-fi workbench with a holographic projection
# floating above its plate. Everything the removed shops used to offer for weapons (fusing a
# second weapon in, and loading an elemental boost) happens here instead.
#
# Drawn rather than sprited so it matches the bar art's palette without needing new pixel work:
# a dark angled housing, a lit inset plate, and a slowly rotating holo above it whose rings read
# as "something is being assembled here".

const T := preload("res://scenes/ui/ui_theme.gd")

const BODY_W := 76.0
const BODY_H := 34.0
const PLATE_INSET := 9.0

var _t := 0.0
var _available := true # dimmed once the run's single fusion has been spent

func _ready() -> void:
	z_index = 3 # above the floor art, below the actors

func set_available(v: bool) -> void:
	_available = v
	queue_redraw()

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var accent: Color = T.CYAN if _available else T.TEXT_DIM
	var pulse := 0.65 + 0.35 * sin(_t * 1.8)

	# Housing: a squat angled slab, darker at the base so it sits on the floor.
	var body := PackedVector2Array([
		Vector2(-BODY_W * 0.5, 0.0),
		Vector2(BODY_W * 0.5, 0.0),
		Vector2(BODY_W * 0.42, BODY_H),
		Vector2(-BODY_W * 0.42, BODY_H),
	])
	draw_colored_polygon(body, Color(0.063, 0.086, 0.122))
	draw_polyline(body + PackedVector2Array([body[0]]), Color(accent, 0.45), 1.5)

	# Lit inset plate on top — the emitter.
	var plate := Rect2(-BODY_W * 0.5 + PLATE_INSET, -5.0,
		BODY_W - PLATE_INSET * 2.0, 10.0)
	draw_rect(plate, Color(accent, 0.12 * pulse))
	draw_rect(plate, Color(accent, 0.65), false, 1.0)

	# Side vents, the detail that makes it read as machinery rather than a box.
	for i in 3:
		var x := -BODY_W * 0.30 + float(i) * BODY_W * 0.30
		draw_line(Vector2(x, BODY_H * 0.35), Vector2(x, BODY_H * 0.75),
			Color(accent, 0.30), 1.0)

	if not _available:
		return

	# The projection: two counter-rotating rings and a drifting core, floating above the plate.
	var c := Vector2(0.0, -34.0)
	var r := 19.0
	for i in 3:
		var a := _t * 0.9 + TAU * float(i) / 3.0
		T.draw_glow_arc(self, c, r, a, a + deg_to_rad(70.0), T.CYAN, 1.5, 0.75, 16)
	for i in 2:
		var a2 := -_t * 1.3 + PI * float(i)
		T.draw_glow_arc(self, c, r * 0.58, a2, a2 + deg_to_rad(100.0), T.CYAN_HOT, 1.2, 0.7, 14)
	draw_circle(c, 4.0 + pulse * 1.5, Color(T.CYAN_HOT, 0.85))
	draw_circle(c, 9.0, Color(T.CYAN, 0.15 * pulse))

	# Beam from the plate up to the projection, so the holo reads as emitted by this machine.
	draw_line(Vector2(0.0, -5.0), c + Vector2(0.0, r * 0.5), Color(T.CYAN, 0.16 * pulse), 10.0)
	draw_line(Vector2(0.0, -5.0), c + Vector2(0.0, r * 0.5), Color(T.CYAN, 0.30 * pulse), 3.0)
