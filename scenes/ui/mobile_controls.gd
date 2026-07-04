extends CanvasLayer

const JOYSTICK_RADIUS := 72.0
const KNOB_RADIUS     := 32.0
const DEAD_ZONE       := 10.0

# ── Move joystick (left) ───────────────────────────────────────────────────
var _joy_center:  Vector2 = Vector2.ZERO
var _joy_touch:   int = -1
var _knob_offset: Vector2 = Vector2.ZERO

# ── Aim joystick (right) ───────────────────────────────────────────────────
var _aim_center:  Vector2 = Vector2.ZERO
var _aim_touch:   int = -1
var _aim_offset:  Vector2 = Vector2.ZERO

var _draw_node: Node2D = null
var _ready_done := false

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_draw_node = Node2D.new()
	add_child(_draw_node)
	_draw_node.draw.connect(_on_draw)
	call_deferred("_init_positions")

func _init_positions() -> void:
	var vp := get_viewport().get_visible_rect().size
	_joy_center = Vector2(vp.x * 0.18, vp.y * 0.82)
	_aim_center = Vector2(vp.x * 0.82, vp.y * 0.82)
	_ready_done = true
	_draw_node.queue_redraw()

# ── Input ─────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not _ready_done:
		return
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)

func _handle_touch(e: InputEventScreenTouch) -> void:
	var left_half := get_viewport().get_visible_rect().size.x * 0.5
	if e.pressed:
		if _joy_touch == -1 and e.position.x < left_half:
			_joy_touch = e.index
			_update_joystick(e.position)
		elif _aim_touch == -1 and e.position.x >= left_half:
			_aim_touch = e.index
			_update_aim(e.position)
	else:
		if e.index == _joy_touch:
			_joy_touch   = -1
			_knob_offset = Vector2.ZERO
			_release_move_actions()
			_draw_node.queue_redraw()
		elif e.index == _aim_touch:
			_aim_touch  = -1
			_aim_offset = Vector2.ZERO
			GameManager.mobile_aim_dir = Vector2.ZERO
			Input.action_release("shoot")
			_draw_node.queue_redraw()

func _handle_drag(e: InputEventScreenDrag) -> void:
	if e.index == _joy_touch:
		_update_joystick(e.position)
	elif e.index == _aim_touch:
		_update_aim(e.position)

func _update_joystick(pos: Vector2) -> void:
	var delta := pos - _joy_center
	if delta.length() > JOYSTICK_RADIUS:
		delta = delta.normalized() * JOYSTICK_RADIUS
	_knob_offset = delta
	_apply_move(delta)
	_draw_node.queue_redraw()

func _update_aim(pos: Vector2) -> void:
	var delta := pos - _aim_center
	if delta.length() > JOYSTICK_RADIUS:
		delta = delta.normalized() * JOYSTICK_RADIUS
	_aim_offset = delta
	if delta.length() >= DEAD_ZONE:
		GameManager.mobile_aim_dir = delta.normalized()
		Input.action_press("shoot")
	else:
		GameManager.mobile_aim_dir = Vector2.ZERO
		Input.action_release("shoot")
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

# ── Drawing ───────────────────────────────────────────────────────────────

func _on_draw() -> void:
	if not _ready_done:
		return

	# ── Move joystick (left) ──
	var knob := _joy_center + _knob_offset
	_draw_node.draw_circle(_joy_center, JOYSTICK_RADIUS, Color(1, 1, 1, 0.08))
	_draw_node.draw_arc(_joy_center, JOYSTICK_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.55), 2.5)
	_draw_node.draw_circle(_joy_center, 5.0, Color(1, 1, 1, 0.25))
	var knob_col := Color(1, 1, 1, 0.70) if _joy_touch != -1 else Color(1, 1, 1, 0.45)
	_draw_node.draw_circle(knob, KNOB_RADIUS, knob_col)

	# ── Aim joystick (right) ──
	var aim_knob  := _aim_center + _aim_offset
	var is_firing := _aim_touch != -1 and GameManager.mobile_aim_dir.length() > 0.0
	var rim_col   := Color(1.0, 0.55, 0.2, 0.90) if is_firing else Color(1.0, 0.45, 0.15, 0.55)
	var knob2_col := Color(1.0, 0.55, 0.15, 0.85) if _aim_touch != -1 else Color(1.0, 0.45, 0.15, 0.45)
	_draw_node.draw_circle(_aim_center, JOYSTICK_RADIUS, Color(1.0, 0.4, 0.1, 0.08))
	_draw_node.draw_arc(_aim_center, JOYSTICK_RADIUS, 0.0, TAU, 48, rim_col, 2.5)
	_draw_node.draw_circle(_aim_center, 5.0, Color(1.0, 0.5, 0.2, 0.25))
	_draw_node.draw_circle(aim_knob, KNOB_RADIUS, knob2_col)
