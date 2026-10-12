extends Node2D

# A circular teleport pad on the floor — the replacement for the room's doors. One pad per exit
# the room used to have. Standing on it sends the player to that destination.
#
# Drawn as a lit ring on the ground with a rising column of light above it, so it reads as a
# floor fixture rather than a decal, and a drifting inner disc so it is obviously active.

const T := preload("res://scenes/ui/ui_theme.gd")

const RADIUS := 34.0
const COLUMN_H := 54.0

@export var accent: Color = T.CYAN
var _t := 0.0
var _armed := false # pads ignore the player until they step OFF, so arriving can't re-trigger

func _ready() -> void:
	z_index = 2 # on the floor, under the actors

func arm() -> void:
	_armed = true

func is_armed() -> bool:
	return _armed

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var pulse := 0.55 + 0.45 * sin(_t * 2.2)

	# Ground ring, flattened so it lies on the floor plane rather than facing the camera.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, RADIUS * 1.25, Color(accent, 0.07 * pulse))
	draw_circle(Vector2.ZERO, RADIUS, Color(accent, 0.13))
	T.draw_glow_arc(self, Vector2.ZERO, RADIUS, 0.0, TAU, accent, 2.0, 0.9, 40)
	# Inner ring, counter-rotating so the pad never looks static.
	for i in 3:
		var a := -_t * 1.1 + TAU * float(i) / 3.0
		T.draw_glow_arc(self, Vector2.ZERO, RADIUS * 0.58, a, a + deg_to_rad(76.0),
			T.CYAN_HOT, 1.5, 0.75, 16)
	draw_circle(Vector2.ZERO, RADIUS * 0.22 * pulse, Color(T.CYAN_HOT, 0.6))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Column of light rising from the pad — what makes it visible across the room.
	for i in 5:
		var f := float(i) / 5.0
		var w := RADIUS * (1.0 - f * 0.55)
		var y := -COLUMN_H * f
		draw_rect(Rect2(-w, y - 3.0, w * 2.0, 6.0), Color(accent, 0.05 * (1.0 - f) * pulse))
	# Rising motes, so the column reads as moving upward.
	for i in 4:
		var phase := fmod(_t * 0.6 + float(i) * 0.25, 1.0)
		var y2 := -COLUMN_H * phase
		var a2 := (1.0 - phase) * 0.7
		draw_circle(Vector2(sin(_t * 1.7 + float(i)) * RADIUS * 0.4, y2), 2.5, Color(T.CYAN_HOT, a2))
