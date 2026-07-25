extends Node2D

# A gold coin dropped by a defeated enemy (see enemy_basic.gd's _drop_coins). Bursts outward
# from the death spot, decelerating, then magnets toward the player when they come close and is
# collected on contact — adding VALUE to GameManager.coins. Distance-based (no Area2D) since the
# player is the only thing that can pick it up.

const VALUE := 5
const FRICTION := 360.0        # px/s^2 the initial burst velocity decays
const MAGNET_RANGE := 78.0     # pulled toward the player within this range
const MAGNET_SPEED := 270.0
const PICKUP_RADIUS := 22.0    # player radius (~14) + coin radius + a little grace
const PICKUP_DELAY := 0.18     # brief grace so it visibly pops out before it can be grabbed

var _vel := Vector2.ZERO
var _player: Node2D = null
var _age := 0.0

func burst(pos: Vector2, dir: Vector2, speed: float) -> void:
	global_position = pos
	_vel = dir * speed

func _physics_process(delta: float) -> void:
	_age += delta
	if _player == null or not is_instance_valid(_player):
		var hits := get_tree().get_nodes_in_group("player")
		_player = hits[0] if hits.size() > 0 else null
	if _player != null:
		var to := _player.global_position - global_position
		var d := to.length()
		if d <= MAGNET_RANGE and d > 0.1:
			_vel = (to / d) * MAGNET_SPEED
		else:
			_vel = _vel.move_toward(Vector2.ZERO, FRICTION * delta)
		if _age >= PICKUP_DELAY and d <= PICKUP_RADIUS:
			GameManager.add_coins(VALUE)
			queue_free()
			return
	else:
		_vel = _vel.move_toward(Vector2.ZERO, FRICTION * delta)
	global_position += _vel * delta

func _draw() -> void:
	draw_circle(Vector2.ZERO, 6.0, Color(0.75, 0.55, 0.05))
	draw_circle(Vector2.ZERO, 5.0, Color(1.0, 0.82, 0.2))
	draw_circle(Vector2.ZERO, 2.5, Color(1.0, 0.96, 0.65))
