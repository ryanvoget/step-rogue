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

# ── Equipment control (above the fire button): a tap-button for placeables (Turret),
# or a drag-to-aim/release-to-throw joystick for throwables (Blast Grenade) ────────────
const DEPLOY_BUTTON_RADIUS := 32.0
const THROW_RADIUS         := 40.0 # joystick ring radius for throwables — smaller than
                                    # JOYSTICK_RADIUS so it clears the aim ring above it
const THROW_KNOB_RADIUS    := 18.0
const DEPLOY_OFFSET_Y      := 175.0 # clears the aim/attack ring (radius 72) with a bigger gap
                                    # than before, so it's harder to fat-finger the fire control
var _deploy_center: Vector2 = Vector2.ZERO
var _deploy_touch:  int = -1
var _throw_offset:  Vector2 = Vector2.ZERO

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
	_joy_center    = Vector2(vp.x * 0.18, vp.y * 0.82)
	_aim_center    = Vector2(vp.x * 0.82, vp.y * 0.82)
	_deploy_center = _aim_center - Vector2(0, DEPLOY_OFFSET_Y)
	_ready_done = true
	_draw_node.queue_redraw()

# True only while there's a placeable or throwable equipment item that hasn't been used
# yet this run (world.gd sets equipment_deployed after one use; sandbox.gd may not, to
# allow repeat testing).
func _deploy_active() -> bool:
	return (GameManager.equipment_placeable or GameManager.equipment_throwable) and not GameManager.equipment_deployed

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
		if _deploy_touch == -1 and _deploy_active() and e.position.distance_to(_deploy_center) <= THROW_RADIUS:
			_deploy_touch = e.index
			if GameManager.equipment_placeable:
				_press_deploy_button()
			else:
				_throw_offset = Vector2.ZERO
				_draw_node.queue_redraw()
		elif _joy_touch == -1 and e.position.x < left_half:
			_joy_touch = e.index
			_update_joystick(e.position)
		elif _aim_touch == -1 and e.position.x >= left_half:
			_aim_touch = e.index
			if GameManager.melee_equipped:
				_press_attack_button()
			else:
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
		elif e.index == _deploy_touch:
			_deploy_touch = -1
			# Throwables fire on release, in whatever direction the joystick was dragged —
			# independent of movement/weapon-aim direction. No drag past the dead zone means
			# no clear direction was chosen, so the throw is cancelled rather than guessing one.
			if GameManager.equipment_throwable and _throw_offset.length() >= DEAD_ZONE:
				GameManager.deploy_equipment_requested.emit(_throw_offset.angle())
			_throw_offset = Vector2.ZERO
			_draw_node.queue_redraw()

func _handle_drag(e: InputEventScreenDrag) -> void:
	if e.index == _joy_touch:
		_update_joystick(e.position)
	elif e.index == _deploy_touch and GameManager.equipment_throwable:
		var delta := e.position - _deploy_center
		if delta.length() > THROW_RADIUS:
			delta = delta.normalized() * THROW_RADIUS
		_throw_offset = delta
		_draw_node.queue_redraw()
	elif e.index == _aim_touch and not GameManager.melee_equipped:
		# Melee's right control is a plain press button — dragging the finger around
		# while held has no directional influence, unlike the ranged aim joystick.
		_update_aim(e.position)

func _update_joystick(pos: Vector2) -> void:
	var delta := pos - _joy_center
	if delta.length() > JOYSTICK_RADIUS:
		delta = delta.normalized() * JOYSTICK_RADIUS
	_knob_offset = delta
	_apply_move(delta)
	_draw_node.queue_redraw()

# Melee weapons attack in the direction the player is facing/moving (see player.gd's
# mobile fallback), not a joystick direction — so pressing just holds "shoot", no offset.
func _press_attack_button() -> void:
	_aim_offset = Vector2.ZERO
	GameManager.mobile_aim_dir = Vector2.ZERO
	Input.action_press("shoot")
	_draw_node.queue_redraw()

# One-shot tap (placeables only — Turret deploys at the player's position, no direction
# needed, so the angle argument is unused downstream). world.gd's handler sets
# GameManager.equipment_deployed synchronously during this emit(), so the button reflects
# the used-up state as soon as we redraw.
func _press_deploy_button() -> void:
	GameManager.deploy_equipment_requested.emit(0.0)
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

	# ── Right control: aim joystick (ranged) or plain attack button (melee) ──
	if GameManager.melee_equipped:
		_draw_attack_button()
	else:
		_draw_aim_joystick()

	# ── Equipment control, above the fire button: tap-button (placeable) or
	# drag-to-aim joystick (throwable) ──
	if _deploy_active():
		if GameManager.equipment_throwable:
			_draw_throw_joystick()
		else:
			_draw_deploy_button()

func _draw_aim_joystick() -> void:
	var aim_knob  := _aim_center + _aim_offset
	var is_firing := _aim_touch != -1 and GameManager.mobile_aim_dir.length() > 0.0
	var rim_col   := Color(1.0, 0.55, 0.2, 0.90) if is_firing else Color(1.0, 0.45, 0.15, 0.55)
	var knob2_col := Color(1.0, 0.55, 0.15, 0.85) if _aim_touch != -1 else Color(1.0, 0.45, 0.15, 0.45)
	_draw_node.draw_circle(_aim_center, JOYSTICK_RADIUS, Color(1.0, 0.4, 0.1, 0.08))
	_draw_node.draw_arc(_aim_center, JOYSTICK_RADIUS, 0.0, TAU, 48, rim_col, 2.5)
	_draw_node.draw_circle(_aim_center, 5.0, Color(1.0, 0.5, 0.2, 0.25))
	_draw_node.draw_circle(aim_knob, KNOB_RADIUS, knob2_col)

const ATTACK_BUTTON_RADIUS := 42.0

func _draw_attack_button() -> void:
	var pressed  := _aim_touch != -1
	var ring_col := Color(0.95, 0.15, 0.15, 0.9) if pressed else Color(0.85, 0.15, 0.15, 0.55)
	var fill_col := Color(1.0, 0.2, 0.2, 0.95) if pressed else Color(0.85, 0.15, 0.15, 0.7)
	_draw_node.draw_circle(_aim_center, JOYSTICK_RADIUS, Color(0.8, 0.1, 0.1, 0.08))
	_draw_node.draw_arc(_aim_center, JOYSTICK_RADIUS, 0.0, TAU, 48, ring_col, 2.5)
	_draw_node.draw_circle(_aim_center, ATTACK_BUTTON_RADIUS, fill_col)

func _draw_deploy_button() -> void:
	var pressed  := _deploy_touch != -1
	var ring_col := Color(0.25, 0.9, 0.55, 0.9) if pressed else Color(0.2, 0.75, 0.45, 0.6)
	var fill_col := Color(0.3, 1.0, 0.6, 0.95) if pressed else Color(0.2, 0.75, 0.45, 0.75)
	_draw_node.draw_circle(_deploy_center, DEPLOY_BUTTON_RADIUS + 10.0, Color(0.2, 0.8, 0.5, 0.08))
	_draw_node.draw_arc(_deploy_center, DEPLOY_BUTTON_RADIUS + 10.0, 0.0, TAU, 32, ring_col, 2.5)
	_draw_node.draw_circle(_deploy_center, DEPLOY_BUTTON_RADIUS, fill_col)

func _draw_throw_joystick() -> void:
	var knob      := _deploy_center + _throw_offset
	var pressed   := _deploy_touch != -1
	var rim_col   := Color(0.25, 0.9, 0.55, 0.9) if pressed else Color(0.2, 0.75, 0.45, 0.6)
	var knob_col  := Color(0.3, 1.0, 0.6, 0.95) if pressed else Color(0.2, 0.75, 0.45, 0.75)
	_draw_node.draw_circle(_deploy_center, THROW_RADIUS, Color(0.2, 0.8, 0.5, 0.08))
	_draw_node.draw_arc(_deploy_center, THROW_RADIUS, 0.0, TAU, 32, rim_col, 2.5)
	_draw_node.draw_circle(_deploy_center, 4.0, Color(0.2, 0.8, 0.5, 0.25))
	_draw_node.draw_circle(knob, THROW_KNOB_RADIUS, knob_col)
