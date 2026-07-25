extends Node2D

# Deployable Barrier Wall (equipment): traces a line under the player as they walk, up to
# max_length pixels total, starting the instant start() is called (the first green
# equipment-button tap) and ending either automatically at the cap or early via
# stop_and_finalize() (the second tap — see world.gd/sandbox.gd's _use_barrier). The traced
# path is then baked into a permanent chain of StaticBody2D wall segments, one per consecutive
# pair of trail points, on collision layer 8 — the same layer the room's boundary walls use
# (see room.gd's _wall) — so it blocks player/enemy movement (their collision_mask includes
# layer 8) but bullets and thrown equipment, which never check that layer, pass through freely.

signal finished

const MIN_STEP := 6.0 # minimum player movement (px) between recorded trail points — keeps
                       # segment count reasonable without the traced line looking blocky
const COLOR_PLACING := Color(0.3, 1.0, 0.6, 0.9)   # bright green while actively tracing
const COLOR_SOLID   := Color(0.55, 0.5, 0.75, 0.95) # dulled, wall-like once finalized

var _player: Node2D = null
var _max_length := 200.0
var _thickness := 12.0
var _trail: PackedVector2Array = PackedVector2Array()
var _traveled := 0.0
var _active := false
var _finalized := false

func start(player: Node2D, max_length: float, thickness: float) -> void:
	_player = player
	_max_length = max_length
	_thickness = thickness
	_trail.append(player.global_position)
	_active = true
	queue_redraw()

func _physics_process(_delta: float) -> void:
	if not _active or _player == null or not is_instance_valid(_player):
		return
	var last: Vector2 = _trail[_trail.size() - 1]
	var pos: Vector2 = _player.global_position
	var d := last.distance_to(pos)
	if d < MIN_STEP:
		return
	var remaining := _max_length - _traveled
	if d > remaining:
		pos = last + (pos - last).normalized() * remaining
		d = remaining
	_trail.append(pos)
	_traveled += d
	queue_redraw()
	if _traveled >= _max_length:
		stop_and_finalize()

# Ends placement (whether called from the length cap above or a second button tap) and bakes
# the traced path into physical wall segments. Safe to call more than once — only the first
# call does anything, since either trigger path could otherwise both fire in the same frame.
func stop_and_finalize() -> void:
	if _finalized:
		return
	_finalized = true
	_active = false
	_build_wall_segments()
	queue_redraw()
	finished.emit()

func _build_wall_segments() -> void:
	for i in range(_trail.size() - 1):
		_wall_segment(_trail[i], _trail[i + 1])

# Mirrors room.gd's _wall() (StaticBody2D + RectangleShape2D on collision layer 8), just
# rotated to match an arbitrary traced segment instead of being axis-aligned.
func _wall_segment(from: Vector2, to: Vector2) -> void:
	var length := from.distance_to(to)
	if length < 0.5:
		return
	var body := StaticBody2D.new()
	body.position = (from + to) * 0.5
	body.rotation = (to - from).angle()
	body.collision_layer = 8
	body.collision_mask = 0

	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(length, _thickness)
	col.shape = shape
	body.add_child(col)
	add_child(body)

func _draw() -> void:
	if _trail.size() < 2:
		return
	var col := COLOR_PLACING if _active else COLOR_SOLID
	for i in range(_trail.size() - 1):
		draw_line(_trail[i], _trail[i + 1], col, _thickness)
