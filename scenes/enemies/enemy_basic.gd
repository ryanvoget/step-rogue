extends CharacterBody2D

signal died

enum State { IDLE, CHASE, ATTACK }

const SPEED       := 90.0
const DETECT_DIST := 320.0
const ATTACK_DIST := 36.0
const ATTACK_DMG  := 8
const ATTACK_CD   := 1.2
const KNOCKBACK_FRICTION := 600.0 # px/sec^2 deceleration applied to knockback velocity
const STUN_FLASH_INTERVAL := 0.05 # white flash toggles this often while stunned (e.g. Metallic Whip)

@export var max_health    := 10
@export var sandbox_mode  := false

var health: int
var _state  := State.IDLE
var _player: Node2D = null
var _attack_timer := 0.0
var _knockback_vel := Vector2.ZERO
var _stun_timer := 0.0
var _stun_flash_timer := 0.0
var _stun_flash_on := false

func _ready() -> void:
	health = max_health
	add_to_group("enemies")

func _physics_process(delta: float) -> void:
	_resolve_player()
	_tick_stun(delta)
	_tick(delta)
	_apply_knockback(delta)
	move_and_slide()

# While stunned, the AI state machine is skipped entirely (see _tick's early return) and
# a white flash pulses every STUN_FLASH_INTERVAL to telegraph it, independent of knockback.
func _tick_stun(delta: float) -> void:
	if _stun_timer <= 0.0:
		return
	_stun_timer -= delta
	_stun_flash_timer -= delta
	if _stun_flash_timer <= 0.0 or _stun_timer <= 0.0:
		_stun_flash_timer = STUN_FLASH_INTERVAL
		_stun_flash_on = _stun_timer > 0.0 and not _stun_flash_on
		queue_redraw()

# Knockback is an additive impulse on top of the state-machine velocity so a melee hit
# can shove the enemy back without interrupting/overriding its chase or attack logic.
func _apply_knockback(delta: float) -> void:
	if _knockback_vel.length() <= 1.0:
		_knockback_vel = Vector2.ZERO
		return
	velocity += _knockback_vel
	_knockback_vel = _knockback_vel.move_toward(Vector2.ZERO, KNOCKBACK_FRICTION * delta)

func _resolve_player() -> void:
	if _player != null and is_instance_valid(_player):
		return
	var hits := get_tree().get_nodes_in_group("player")
	_player = hits[0] if hits.size() > 0 else null

func _tick(delta: float) -> void:
	if _stun_timer > 0.0:
		velocity = Vector2.ZERO
		return
	if sandbox_mode:
		velocity = Vector2.ZERO
		return
	if _player == null:
		velocity = Vector2.ZERO
		return

	var dist := global_position.distance_to(_player.global_position)

	match _state:
		State.IDLE:
			velocity = Vector2.ZERO
			if dist < DETECT_DIST:
				_state = State.CHASE
				queue_redraw()

		State.CHASE:
			if dist <= ATTACK_DIST:
				_state = State.ATTACK
				velocity = Vector2.ZERO
				_attack_timer = 0.0
				queue_redraw()
			elif dist > DETECT_DIST * 1.5:
				_state = State.IDLE
				queue_redraw()
			else:
				var dir := (_player.global_position - global_position).normalized()
				velocity = dir * SPEED
				look_at(_player.global_position)

		State.ATTACK:
			velocity = Vector2.ZERO
			_attack_timer -= delta
			if _attack_timer <= 0.0:
				if dist <= ATTACK_DIST * 1.5 and _player.has_method("take_damage"):
					_player.take_damage(ATTACK_DMG)
				_attack_timer = ATTACK_CD
			if dist > ATTACK_DIST * 2.0:
				_state = State.CHASE
				queue_redraw()

func take_damage(amount: int, knockback_dir: Vector2 = Vector2.ZERO, knockback_force: float = 0.0, stun_duration: float = 0.0) -> void:
	health -= amount
	if knockback_force > 0.0:
		_knockback_vel = knockback_dir * knockback_force
	if stun_duration > 0.0:
		_stun_timer = stun_duration
		_stun_flash_timer = STUN_FLASH_INTERVAL
		_stun_flash_on = true
	queue_redraw()
	if health <= 0:
		died.emit()
		queue_free()

func _draw() -> void:
	var col := Color(0.85, 0.20, 0.20)
	if _state == State.ATTACK:
		col = Color(1.0, 0.40, 0.05)
	if _stun_flash_on:
		col = Color(1.0, 1.0, 1.0)
	draw_circle(Vector2.ZERO, 18.0, col)
	# Health bar below sprite
	var ratio := clampf(float(health) / float(max_health), 0.0, 1.0)
	draw_rect(Rect2(-18, 24, 36, 5), Color(0.2, 0.2, 0.2))
	draw_rect(Rect2(-18, 24, 36 * ratio, 5), Color(0.2, 0.9, 0.2))
