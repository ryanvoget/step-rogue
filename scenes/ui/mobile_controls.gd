extends CanvasLayer

const JOYSTICK_RADIUS := 60.0
const KNOB_RADIUS     := 28.0
const DEAD_ZONE       := 12.0

var _joystick_center := Vector2.ZERO
var _shoot_rect      := Rect2.ZERO

var _joystick_touch  := -1
var _shoot_touch     := -1
var _knob_offset     := Vector2.ZERO

var _draw_node: Node2D

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Position controls relative to the actual visible rect so they adapt
	# to any device resolution and to the landscape rotation the world uses.
	var vp := get_viewport().get_visible_rect().size
	_joystick_center = Vector2(vp.x * 0.15, vp.y * 0.78)
	_shoot_rect      = Rect2(vp.x * 0.5, vp.y * 0.25, vp.x * 0.5, vp.y * 0.65)

	_draw_node = Node2D.new()
	add_child(_draw_node)
	_draw_node.draw.connect(_on_draw)
	_draw_node.queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)

func _handle_touch(e: InputEventScreenTouch) -> void:
	var mid_x := get_viewport().get_visible_rect().size.x * 0.5
	if e.pressed:
		if _joystick_touch == -1 and e.position.x < mid_x:
			_joystick_touch = e.index
			_update_joystick(e.position)
		elif _shoot_touch == -1 and _shoot_rect.has_point(e.position):
			_shoot_touch = e.index
			Input.action_press("shoot")
	else:
		if e.index == _joystick_touch:
			_joystick_touch = -1
			_knob_offset    = Vector2.ZERO
			_release_move_actions()
			_draw_node.queue_redraw()
		elif e.index == _shoot_touch:
			_shoot_touch = -1
			Input.action_release("shoot")

func _handle_drag(e: InputEventScreenDrag) -> void:
	if e.index == _joystick_touch:
		_update_joystick(e.position)

func _update_joystick(pos: Vector2) -> void:
	var delta := pos - _joystick_center
	if delta.length() > JOYSTICK_RADIUS:
		delta = delta.normalized() * JOYSTICK_RADIUS
	_knob_offset = delta
	_apply_move(delta)
	_draw_node.queue_redraw()

func _apply_move(offset: Vector2) -> void:
	_release_move_actions()
	if offset.length() < DEAD_ZONE:
		return
	var n := offset.normalized()
	if n.x >  0.3: Input.action_press("move_right")
	if n.x < -0.3: Input.action_press("move_left")
	if n.y >  0.3: Input.action_press("move_down")
	if n.y < -0.3: Input.action_press("move_up")

func _release_move_actions() -> void:
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(a)

func _on_draw() -> void:
	var knob := _joystick_center + _knob_offset
	_draw_node.draw_arc(_joystick_center, JOYSTICK_RADIUS, 0.0, TAU, 32, Color(1, 1, 1, 0.2), 3.0)
	_draw_node.draw_circle(knob, KNOB_RADIUS, Color(1, 1, 1, 0.28))
	# Faint shoot zone hint
	_draw_node.draw_rect(
		Rect2(_shoot_rect.position + Vector2(8, 8), _shoot_rect.size - Vector2(16, 16)),
		Color(1, 1, 1, 0.04)
	)
